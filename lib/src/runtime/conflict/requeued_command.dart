import '../../commands/sync_command.dart';

/// A command to be re-enqueued during stale conflict resolution.
///
/// Wraps a [SyncCommand] payload with optional [rebuildContext] and an
/// override [occurredAtUtc] for the fresh envelope.
class RequeuedCommand {
  /// Creates a requeued command.
  const RequeuedCommand({
    required this.command,
    this.rebuildContext,
    this.occurredAtUtc,
  });

  /// The payload to enqueue.
  final SyncCommand command;

  /// Optional local-only rebuild metadata.
  final Map<String, dynamic>? rebuildContext;

  /// Optional override timestamp for the new envelope.
  final DateTime? occurredAtUtc;
}
