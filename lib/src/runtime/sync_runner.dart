import '../persistence/sync_rebuild_instruction_store.dart';
import '../protocol/sync_batch_response.dart';
import '../protocol/sync_cursor.dart';
import '../uow/sync_trigger_sink.dart';
import 'conflict/conflict_resolution_context.dart';
import 'conflict/conflict_resolution_plan.dart';
import 'conflict/conflict_resolver.dart';
import 'models/prepared_sync_batch.dart';
import 'rebuild/rebuild_instructions.dart';
import 'rebuild/server_change_applier.dart';
import 'sync_resync_handler.dart';
import 'sync_transport.dart';
import 'sync_unit_of_work.dart';

/// Coalesced sync run loop.
///
/// [SyncRunner] is the central orchestrator that executes one sync cycle:
/// prepare batch → transport → apply changes → resolve stale conflicts →
/// commit results. It ensures only one run is active at a time; concurrent
/// callers receive the same future.
class SyncRunner {
  SyncRunner({
    required SyncUnitOfWork unitOfWork,
    required SyncTransport transport,
    required ServerChangeApplier changeApplier,
    ConflictResolver? conflictResolver,
    SyncResyncHandler? resyncHandler,
    SyncRebuildInstructionStore? rebuildInstructionStore,
  })  : _unitOfWork = unitOfWork,
        _transport = transport,
        _changeApplier = changeApplier,
        _conflictResolver = conflictResolver,
        _resyncHandler = resyncHandler,
        _rebuildInstructionStore = rebuildInstructionStore;

  final SyncUnitOfWork _unitOfWork;
  final SyncTransport _transport;
  final ServerChangeApplier _changeApplier;
  final ConflictResolver? _conflictResolver;
  final SyncResyncHandler? _resyncHandler;
  final SyncRebuildInstructionStore? _rebuildInstructionStore;

  Future<void>? _activeRun;

  /// Runs one sync cycle, coalesced with any already-active run.
  ///
  /// [pullLimit] controls how many downstream changes are requested from the
  /// server. Defaults to 500.
  ///
  /// Returns a future that completes when the cycle finishes (success or failure).
  Future<void> runOnce(SyncTriggerReason reason, {int pullLimit = 500}) async {
    if (_activeRun != null) {
      return _activeRun;
    }

    final Future<void> run = _doRun(reason, pullLimit: pullLimit);
    _activeRun = run;

    try {
      await run;
    } finally {
      _activeRun = null;
    }
  }

  Future<void> _doRun(SyncTriggerReason reason, {required int pullLimit}) async {
    SyncCursor? nextSinceCursor;

    while (true) {
      final PreparedSyncBatch batch = await _unitOfWork.prepareBatch(
        pullLimit: pullLimit,
        sinceCursor: nextSinceCursor,
      );
      if (batch.request.isEmpty) {
        return;
      }

      SyncBatchResponse response;
      try {
        response = await _transport.pushPull(batch.request);
      } catch (error) {
        await _unitOfWork.commitFailure(batch: batch, error: error);
        return;
      }

      if (response.isResyncRequired) {
        final SyncResyncHandler? handler = _resyncHandler;
        if (handler != null && response.expectedSyncEpoch != null) {
          await handler.onResyncRequired(response.expectedSyncEpoch!);
        }
        return;
      }

      await _changeApplier.apply(response.changes);

      final ConflictResolver? resolver = _conflictResolver;
      if (resolver != null && response.commandResults.isNotEmpty) {
        final RebuildInstructions rebuildInstructions =
            await _rebuildInstructionStore?.readAll() ?? RebuildInstructions.empty;

        final ConflictResolutionContext context = ConflictResolutionContext(
          batch: batch,
          response: response,
          requeueBaseCursor: response.newCursor,
          rebuildInstructions: rebuildInstructions,
        );

        final ConflictResolutionPlan plan = await resolver.resolve(context);
        await _unitOfWork.commitResolved(
          batch: batch,
          response: response,
          plan: plan,
        );

        if (!await _unitOfWork.hasUnsettledOutboxCommands()) {
          await _rebuildInstructionStore?.clear();
        }
      } else {
        await _unitOfWork.commitSuccess(batch, response);
      }

      if (!response.hasMore) {
        return;
      }

      nextSinceCursor = response.newCursor;
    }
  }
}
