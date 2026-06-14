import '../../commands/command_envelope.dart';
import '../../commands/sync_command.dart';
import '../../persistence/sync_outbox_store.dart';
import '../../protocol/sync_batch_response.dart';
import '../../protocol/sync_cursor.dart';
import 'command_resolution_action.dart';
import 'conflict_resolution_context.dart';
import 'conflict_resolution_plan.dart';
import 'conflict_resolver.dart';
import 'requeued_command.dart';
import 'resolution_decision.dart';
import 'stale_conflict_profile.dart';
import 'stale_conflict_profile_registry.dart';
import 'stale_conflict_routing_context.dart';
import 'sync_stale_routing_policy.dart';

/// Default [ConflictResolver] implementation that routes stale conflicts
/// through registered [StaleConflictProfile]s according to a
/// [SyncStaleRoutingPolicy].
///
/// Non-stale commands are handled generically:
/// - `applied`, `noop_already_applied`, `rejected_invalid` => ack
/// - `retryable_error` => fail with retry
///
/// `rejected_invalid` is treated as terminal: the command will not be retried.
///
/// Stale commands are dropped (acked) unless the routing policy says the
/// command type should be resolved by its profile. If the policy routes but no
/// profile is registered, the command is failed rather than thrown.
class DefaultConflictResolver implements ConflictResolver {
  /// Creates a default resolver backed by [staleProfileRegistry] and
  /// [routingPolicy].
  DefaultConflictResolver({
    required StaleConflictProfileRegistry staleProfileRegistry,
    SyncStaleRoutingPolicy routingPolicy =
        const SyncStaleRoutingPolicy.recoverableMissingRowOnly(),
  })  : _staleProfileRegistry = staleProfileRegistry,
        _routingPolicy = routingPolicy;

  final StaleConflictProfileRegistry _staleProfileRegistry;
  final SyncStaleRoutingPolicy _routingPolicy;

  @override
  Future<ConflictResolutionPlan> resolve(ConflictResolutionContext context) async {
    final List<CommandResolutionAction> actions = <CommandResolutionAction>[];
    for (final String opId in context.batch.inFlightOpIds) {
      actions.add(await _resolveOpId(context, opId));
    }

    return ConflictResolutionPlan(actions: actions);
  }

  Future<CommandResolutionAction> _resolveOpId(
    ConflictResolutionContext context,
    String opId,
  ) async {
    final SyncCommandResult? result = context.response.getResultByOpId(opId);
    if (result == null) {
      return FailCommandAction(
        opId: opId,
        error: 'Missing command result in sync response.',
      );
    }

    final DecodedOutboxCommand? inFlightCommand =
        context.inFlightCommandByOpId(opId);
    if (inFlightCommand == null) {
      return FailCommandAction(
        opId: opId,
        error: 'In-flight command envelope missing for opId=$opId.',
      );
    }

    if (result.status == SyncCommandResultStatus.rejectedConflictStale) {
      return _resolveStale(
        context: context,
        opId: opId,
        result: result,
        inFlightCommand: inFlightCommand,
      );
    }

    return _resolveNonStale(opId: opId, result: result);
  }

  CommandResolutionAction _resolveNonStale({
    required String opId,
    required SyncCommandResult result,
  }) {
    return switch (result.status) {
      SyncCommandResultStatus.applied ||
      SyncCommandResultStatus.noopAlreadyApplied ||
      SyncCommandResultStatus.rejectedInvalid =>
        AckCommandAction(opId: opId, reason: result.reason),
      SyncCommandResultStatus.retryableError => FailCommandAction(
        opId: opId,
        error: result.reason ?? 'Command failed with retryable error.',
      ),
      SyncCommandResultStatus.rejectedConflictStale => throw StateError(
        'Stale status should be resolved in _resolveStale.',
      ),
    };
  }

  Future<CommandResolutionAction> _resolveStale({
    required ConflictResolutionContext context,
    required String opId,
    required SyncCommandResult result,
    required DecodedOutboxCommand inFlightCommand,
  }) async {
    final CommandEnvelope<SyncCommand> command = inFlightCommand.envelope;

    final StaleConflictRoutingContext routingContext =
        StaleConflictRoutingContext(
      inFlightCommand: inFlightCommand,
      result: result,
      response: context.response,
    );

    if (!_routingPolicy.shouldRouteToProfile(routingContext)) {
      return AckCommandAction(
        opId: opId,
        reason: result.reason ?? 'Stale conflict resolved by server winner.',
      );
    }

    final StaleConflictProfile? profile =
        _staleProfileRegistry.tryResolve(command.commandType);
    if (profile == null) {
      return FailCommandAction(
        opId: opId,
        error:
            'No stale conflict profile registered for ${command.commandType}.',
      );
    }

    final ResolutionDecision<SyncCommand> decision = await profile.resolve(
      StaleConflictProfileContext(
        inFlightCommand: inFlightCommand,
        result: result,
        response: context.response,
        rebuildInstructions: context.rebuildInstructions,
      ),
    );

    return switch (decision) {
      DropResolutionDecision<SyncCommand>() => AckCommandAction(
          opId: opId,
          reason: _staleAckReason(result: result, decisionReason: decision.reason),
        ),
      ReplaySameResolutionDecision<SyncCommand>() => RequeueCommandAction(
          opId: opId,
          requeuedCommands: <RequeuedCommand>[
            RequeuedCommand(
              command: command.payload,
              rebuildContext: decision.rebuildContext ?? inFlightCommand.rebuildContext,
              occurredAtUtc: command.occurredAtUtc,
            ),
          ],
          baseCursor: context.requeueBaseCursor,
          reason: decision.reason,
        ),
      RebuildResolutionDecision<SyncCommand>() => _resolveRebuildDecisionAsAction(
          opId: opId,
          result: result,
          decision: decision,
          baseCursor: context.requeueBaseCursor,
        ),
    };
  }

  CommandResolutionAction _resolveRebuildDecisionAsAction({
    required String opId,
    required SyncCommandResult result,
    required RebuildResolutionDecision<SyncCommand> decision,
    required SyncCursor baseCursor,
  }) {
    if (decision.commands.isEmpty) {
      return AckCommandAction(
        opId: opId,
        reason: _staleAckReason(result: result, decisionReason: decision.reason),
      );
    }

    return RequeueCommandAction(
      opId: opId,
      requeuedCommands: decision.commands,
      baseCursor: baseCursor,
      reason: decision.reason,
    );
  }

  String _staleAckReason({
    required SyncCommandResult result,
    String? decisionReason,
  }) {
    return decisionReason ?? result.reason ?? 'Stale conflict resolved without replay.';
  }
}
