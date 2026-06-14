import '../../commands/sync_command.dart';
import 'resolution_decision.dart';
import 'stale_conflict_profile.dart';

/// A profile that always replays the same payload with a fresh cursor.
///
/// This is the simplest safe default: if the server rejected a command as stale,
/// re-send the identical intent from the current base cursor.
class ReplayStaleConflictProfile implements StaleConflictProfile {
  /// Creates a universal replay profile.
  const ReplayStaleConflictProfile();

  @override
  String get commandType => '*';

  @override
  bool get requiresRebuildInstructions => false;

  @override
  Future<ResolutionDecision<SyncCommand>> resolve(StaleConflictProfileContext context) async {
    return ReplaySameResolutionDecision<SyncCommand>(
      rebuildContext: context.rebuildContext,
      reason: context.result.reason ?? 'Command stale; replaying intent.',
    );
  }
}

/// A typed replay profile for a specific command subtype.
class ReplayTypedStaleConflictProfile<TCommand extends SyncCommand> extends TypedStaleConflictProfile<TCommand> {
  /// Creates a typed replay profile for [commandType].
  const ReplayTypedStaleConflictProfile({required this.commandType});

  @override
  final String commandType;

  @override
  bool get requiresRebuildInstructions => false;

  @override
  Future<ResolutionDecision<TCommand>> resolveTyped(TypedStaleConflictProfileContext<TCommand> context) async {
    return ReplaySameResolutionDecision<TCommand>(
      rebuildContext: context.rebuildContext,
      reason: context.result.reason ?? 'Command stale; replaying intent.',
    );
  }
}
