import '../../commands/sync_command.dart';
import 'resolution_decision.dart';
import 'stale_conflict_profile.dart';

/// A profile that always drops (acks) stale commands.
///
/// Useful when a command type represents an intent that should be silently
/// discarded if it conflicts with newer server state.
class DropStaleConflictProfile implements StaleConflictProfile {
  /// Creates a universal drop profile.
  const DropStaleConflictProfile();

  @override
  String get commandType => '*';

  @override
  Future<ResolutionDecision<SyncCommand>> resolve(StaleConflictProfileContext context) async {
    return DropResolutionDecision<SyncCommand>(reason: context.result.reason ?? 'Command stale; dropping intent.');
  }
}

/// A typed drop profile for a specific command subtype.
class DropTypedStaleConflictProfile<TCommand extends SyncCommand> extends TypedStaleConflictProfile<TCommand> {
  /// Creates a typed drop profile for [commandType].
  const DropTypedStaleConflictProfile({required this.commandType});

  @override
  final String commandType;

  @override
  Future<ResolutionDecision<TCommand>> resolveTyped(TypedStaleConflictProfileContext<TCommand> context) async {
    return DropResolutionDecision<TCommand>(reason: context.result.reason ?? 'Command stale; dropping intent.');
  }
}
