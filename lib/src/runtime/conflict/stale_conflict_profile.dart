import '../../commands/command_envelope.dart';
import '../../commands/sync_command.dart';
import '../../persistence/sync_outbox_store.dart';
import '../../protocol/sync_batch_response.dart';
import '../rebuild/rebuild_instructions.dart';
import 'resolution_decision.dart';

/// Context provided to a [StaleConflictProfile] during resolution.
class StaleConflictProfileContext {
  /// Creates a profile context.
  const StaleConflictProfileContext({
    required this.inFlightCommand,
    required this.result,
    required this.response,
    this.rebuildInstructions = RebuildInstructions.empty,
  });

  /// The original in-flight command that was rejected as stale.
  final DecodedOutboxCommand inFlightCommand;

  /// Server result for this command.
  final SyncCommandResult result;

  /// Full server response (for context-aware profiles).
  final SyncBatchResponse response;

  /// Rebuild instructions captured during change application.
  final RebuildInstructions rebuildInstructions;

  /// Convenience accessor for the command envelope.
  CommandEnvelope<SyncCommand> get command => inFlightCommand.envelope;

  /// Convenience accessor for the local-only rebuild context.
  Map<String, dynamic>? get rebuildContext => inFlightCommand.rebuildContext;
}

/// Typed variant of [StaleConflictProfileContext] with a concrete payload type.
class TypedStaleConflictProfileContext<TCommand extends SyncCommand> {
  /// Creates a typed context from the base [context] and typed [command].
  const TypedStaleConflictProfileContext({
    required this.base,
    required this.command,
  });

  /// The underlying untyped context.
  final StaleConflictProfileContext base;

  /// The typed command payload.
  final TCommand command;

  /// Delegates to [base.result].
  SyncCommandResult get result => base.result;

  /// Delegates to [base.response].
  SyncBatchResponse get response => base.response;

  /// Delegates to [base.rebuildContext].
  Map<String, dynamic>? get rebuildContext => base.rebuildContext;

  /// Delegates to [base.rebuildInstructions].
  RebuildInstructions get rebuildInstructions => base.rebuildInstructions;
}

/// Contract for domain-specific stale-conflict resolution logic.
///
/// Each command type may register a profile that decides whether to ack,
/// replay, rebuild, or fail a command rejected as `rejected_conflict_stale`.
abstract interface class StaleConflictProfile {
  /// The command type this profile handles (e.g. `'vocab_trainer.create_chapter'`).
  ///
  /// Use `'*'` as a wildcard fallback.
  String get commandType;

  /// Resolves a stale command in [context] into a [ResolutionDecision].
  Future<ResolutionDecision<SyncCommand>> resolve(
    StaleConflictProfileContext context,
  );
}

/// Base class for typed stale-conflict profiles.
///
/// Automatically casts the payload to [TCommand] before delegating to
/// [resolveTyped], then upcasts the decision back to [SyncCommand].
abstract class TypedStaleConflictProfile<TCommand extends SyncCommand> implements StaleConflictProfile {
  const TypedStaleConflictProfile();

  @override
  Future<ResolutionDecision<SyncCommand>> resolve(
    StaleConflictProfileContext context,
  ) async {
    final SyncCommand payload = context.command.payload;
    if (payload is! TCommand) {
      throw StateError(
        'Stale conflict profile for $commandType received payload '
        'type ${payload.runtimeType}.',
      );
    }

    final ResolutionDecision<TCommand> decision = await resolveTyped(
      TypedStaleConflictProfileContext<TCommand>(
        base: context,
        command: payload,
      ),
    );
    return upcastResolutionDecision(decision);
  }

  /// Typed resolution hook. Implement this in concrete profiles.
  Future<ResolutionDecision<TCommand>> resolveTyped(
    TypedStaleConflictProfileContext<TCommand> context,
  );
}
