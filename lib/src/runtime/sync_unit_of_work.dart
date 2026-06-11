import '../commands/command_envelope_factory.dart';
import '../persistence/sync_conflict_log_store.dart';
import '../persistence/sync_outbox_store.dart';
import '../persistence/sync_state_store.dart';
import '../persistence/sync_transaction_runner.dart';
import '../protocol/sync_batch_request.dart';
import '../protocol/sync_batch_response.dart';
import '../protocol/sync_cursor.dart';
import 'conflict/command_resolution_action.dart';
import 'conflict/conflict_resolution_plan.dart';
import 'conflict/requeued_command.dart';
import 'models/prepared_sync_batch.dart';

/// Prepares sync batches, commits results, and manages outbox row lifecycle.
///
/// All mutating operations run inside the host app's transaction via
/// [SyncPersistenceTransactionRunner].
class SyncUnitOfWork {
  /// Creates a unit of work backed by the given stores.
  SyncUnitOfWork({
    required SyncPersistenceTransactionRunner transactionRunner,
    required SyncOutboxStore outboxStore,
    required SyncStateStore syncStateStore,
    SyncConflictLogStore? conflictLogStore,
    CommandEnvelopeFactory? envelopeFactory,
  }) : _transactionRunner = transactionRunner,
       _outboxStore = outboxStore,
       _syncStateStore = syncStateStore,
       _conflictLogStore = conflictLogStore,
       _envelopeFactory = envelopeFactory;

  final SyncPersistenceTransactionRunner _transactionRunner;
  final SyncOutboxStore _outboxStore;
  final SyncStateStore _syncStateStore;
  final SyncConflictLogStore? _conflictLogStore;
  final CommandEnvelopeFactory? _envelopeFactory;

  /// Prepares a batch for the next sync run.
  ///
  /// 1. Recovers abandoned `inFlight` rows to `pending`
  /// 2. Reads the current cursor and epoch
  /// 3. Selects up to [commandLimit] pending commands
  /// 4. Marks selected rows as `inFlight`
  /// 5. Builds a [PreparedSyncBatch]
  Future<PreparedSyncBatch> prepareBatch({
    int commandLimit = 100,
    int pullLimit = 500,
    bool includePull = true,
  }) async {
    if (commandLimit <= 0) {
      throw ArgumentError.value(commandLimit, 'commandLimit', 'Must be > 0.');
    }

    return _transactionRunner(() async {
      await _outboxStore.recoverInFlightToPending();

      final SyncCursor sinceCursor =
          await _syncStateStore.readLastServerCursorOrZero();
      final SyncEpoch syncEpoch =
          await _syncStateStore.readLastSyncEpochOrZero();
      final List<DecodedOutboxCommand> pending =
          await _outboxStore.nextPending(limit: commandLimit);
      final List<String> inFlightOpIds = pending
          .map((DecodedOutboxCommand entry) => entry.opId)
          .toSet()
          .toList(growable: false);

      if (inFlightOpIds.isNotEmpty) {
        await _outboxStore.markInFlight(inFlightOpIds);
      }

      return PreparedSyncBatch(
        request: SyncBatchRequest(
          sinceCursor: sinceCursor,
          syncEpoch: syncEpoch,
          commands: pending
              .map((DecodedOutboxCommand entry) => entry.envelope)
              .toList(growable: false),
          pullLimit: pullLimit,
          includePull: includePull,
        ),
        inFlightOpIds: inFlightOpIds,
        inFlightCommands: pending,
      );
    });
  }

  /// Commits a successful batch response.
  ///
  /// - Acks `applied`, `noop_already_applied`, `rejected_conflict_stale`,
  ///   and `rejected_invalid` commands
  /// - Marks `retryable_error` as failed with retry metadata
  /// - Advances the stored cursor monotonically
  Future<void> commitSuccess(
    PreparedSyncBatch batch,
    SyncBatchResponse response,
  ) async {
    await _transactionRunner(() async {
      final List<String> ackedOpIds = <String>[];
      final List<OutboxFailureUpdate> failed = <OutboxFailureUpdate>[];

      for (final String opId in batch.inFlightOpIds) {
        final SyncCommandResult? result = response.getResultByOpId(opId);
        if (result == null) {
          failed.add(
            OutboxFailureUpdate(
              opId: opId,
              error: 'Missing command result in sync response.',
            ),
          );
          continue;
        }

        switch (result.status) {
          case SyncCommandResultStatus.applied:
          case SyncCommandResultStatus.noopAlreadyApplied:
          case SyncCommandResultStatus.rejectedConflictStale:
          case SyncCommandResultStatus.rejectedInvalid:
            ackedOpIds.add(opId);
            break;
          case SyncCommandResultStatus.retryableError:
            failed.add(
              OutboxFailureUpdate(
                opId: opId,
                error: result.reason ?? 'Command failed with retryable error.',
              ),
            );
            break;
        }
      }

      await _outboxStore.markAcked(ackedOpIds);
      await _outboxStore.markManyFailed(failed);
      await _syncStateStore.writeLastServerCursorIfAdvanced(response.newCursor);
    });
  }

  /// Commits a resolved conflict plan after stale resolution.
  ///
  /// Applies ack / fail / requeue actions from [plan] and advances the cursor.
  Future<void> commitResolved({
    required PreparedSyncBatch batch,
    required SyncBatchResponse response,
    required ConflictResolutionPlan plan,
  }) async {
    await _transactionRunner(() async {
      final List<String> ackedOpIds = <String>[];
      final List<OutboxFailureUpdate> failed = <OutboxFailureUpdate>[];
      final Map<String, DecodedOutboxCommand> inFlightByOpId =
          <String, DecodedOutboxCommand>{
            for (final DecodedOutboxCommand inFlight in batch.inFlightCommands)
              inFlight.opId: inFlight,
          };

      for (final String opId in batch.inFlightOpIds) {
        final CommandResolutionAction? action = plan.getActionByOpId(opId);
        if (action == null) {
          failed.add(
            OutboxFailureUpdate(
              opId: opId,
              error: 'Conflict resolution did not return an action for opId=$opId.',
            ),
          );
          continue;
        }

        if (action is AckCommandAction) {
          ackedOpIds.add(opId);
          await _logDecision(
            opId: opId,
            decision: SyncConflictDecision.applyServer,
            reason: action.reason,
          );
          continue;
        }

        if (action is FailCommandAction) {
          failed.add(
            OutboxFailureUpdate(
              opId: opId,
              error: action.error,
              retryAfter: action.retryAfter,
            ),
          );
          continue;
        }

        if (action is RequeueCommandAction) {
          final DecodedOutboxCommand? inFlightCommand = inFlightByOpId[opId];
          if (inFlightCommand == null) {
            failed.add(
              OutboxFailureUpdate(
                opId: opId,
                error: 'Missing in-flight command envelope for opId=$opId.',
              ),
            );
            continue;
          }

          ackedOpIds.add(opId);
          await _logDecision(
            opId: opId,
            decision: SyncConflictDecision.keepLocal,
            reason: action.reason ?? 'Requeueing stale command from latest base.',
          );

          await _appendRequeuedCommands(
            opId: opId,
            requeuedCommands: action.requeuedCommands,
            baseCursor: action.baseCursor,
            fallbackOccurredAtUtc: inFlightCommand.envelope.occurredAtUtc,
          );
          continue;
        }
      }

      await _outboxStore.markAcked(ackedOpIds);
      await _outboxStore.markManyFailed(failed);
      await _syncStateStore.writeLastServerCursorIfAdvanced(response.newCursor);
    });
  }

  /// Marks all in-flight commands as failed after a transport/runtime error.
  Future<void> commitFailure({
    required PreparedSyncBatch batch,
    required Object error,
    Duration retryAfter = const Duration(seconds: 30),
  }) async {
    if (!batch.hasCommands) {
      return;
    }

    await _transactionRunner(() async {
      final List<OutboxFailureUpdate> failures = batch.inFlightOpIds
          .map(
            (String opId) => OutboxFailureUpdate(
              opId: opId,
              error: error.toString(),
              retryAfter: retryAfter,
            ),
          )
          .toList(growable: false);

      await _outboxStore.markManyFailed(failures);
    });
  }

  /// Whether any pending or in-flight outbox rows remain.
  Future<bool> hasUnsettledOutboxCommands() {
    return _outboxStore.hasUnsettledCommands();
  }

  /// Clears all outbox rows. Used by auth reset flows.
  Future<void> clearRuntimeTables() async {
    await _transactionRunner(() async {
      await _outboxStore.clear();
    });
  }

  Future<void> _appendRequeuedCommands({
    required String opId,
    required List<RequeuedCommand> requeuedCommands,
    required SyncCursor baseCursor,
    required DateTime fallbackOccurredAtUtc,
  }) async {
    final CommandEnvelopeFactory? envelopeFactory = _envelopeFactory;
    if (envelopeFactory == null) {
      throw StateError(
        'CommandEnvelopeFactory is required to requeue stale command $opId.',
      );
    }

    for (final RequeuedCommand requeued in requeuedCommands) {
      final envelope = envelopeFactory.create(
        payload: requeued.command,
        baseCursor: baseCursor,
        occurredAtUtc: requeued.occurredAtUtc ?? fallbackOccurredAtUtc,
      );
      await _outboxStore.append(
        envelope,
        rebuildContext: requeued.rebuildContext,
      );
    }
  }

  Future<void> _logDecision({
    required String opId,
    required SyncConflictDecision decision,
    String? reason,
  }) async {
    final SyncConflictLogStore? conflictLogStore = _conflictLogStore;
    if (conflictLogStore == null) {
      return;
    }

    await conflictLogStore.logDecision(
      opId: opId,
      entityTableName: 'sync_outbox',
      decision: decision,
      reason: reason,
    );
  }
}
