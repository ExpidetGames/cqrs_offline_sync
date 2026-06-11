import '../../commands/sync_command.dart';
import 'requeued_command.dart';

/// Decision produced by a [StaleConflictProfile] for a stale command.
///
/// [T] is the concrete command subtype.
sealed class ResolutionDecision<T extends SyncCommand> {
  /// Creates a resolution decision with an optional human-readable [reason].
  const ResolutionDecision({this.reason});

  /// Optional diagnostic reason for the decision.
  final String? reason;
}

/// Drop the stale command without requeuing.
final class DropResolutionDecision<T extends SyncCommand> extends ResolutionDecision<T> {
  /// Creates a drop decision.
  const DropResolutionDecision({super.reason});
}

/// Replay the same payload with a fresh cursor.
final class ReplaySameResolutionDecision<T extends SyncCommand> extends ResolutionDecision<T> {
  /// Creates a replay decision, optionally carrying [rebuildContext].
  const ReplaySameResolutionDecision({this.rebuildContext, super.reason});

  /// Optional local-only rebuild metadata for the replayed command.
  final Map<String, dynamic>? rebuildContext;
}

/// Rebuild one or more replacement commands from captured instructions.
final class RebuildResolutionDecision<T extends SyncCommand> extends ResolutionDecision<T> {
  /// Creates a rebuild decision with the replacement [commands].
  RebuildResolutionDecision({required Iterable<RequeuedCommand> commands, super.reason})
    : commands = List<RequeuedCommand>.unmodifiable(commands);

  /// Replacement commands to enqueue.
  final List<RequeuedCommand> commands;
}

/// Upcasts a typed [ResolutionDecision] to [SyncCommand].
///
/// Used internally when aggregating decisions from typed profiles.
ResolutionDecision<SyncCommand> upcastResolutionDecision<T extends SyncCommand>(ResolutionDecision<T> decision) {
  switch (decision) {
    case DropResolutionDecision<T>():
      return DropResolutionDecision<SyncCommand>(reason: decision.reason);
    case ReplaySameResolutionDecision<T>():
      return ReplaySameResolutionDecision<SyncCommand>(
        rebuildContext: decision.rebuildContext,
        reason: decision.reason,
      );
    case RebuildResolutionDecision<T>():
      return RebuildResolutionDecision<SyncCommand>(commands: decision.commands, reason: decision.reason);
  }
}
