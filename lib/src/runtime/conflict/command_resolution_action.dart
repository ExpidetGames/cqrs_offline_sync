import '../../protocol/sync_cursor.dart';
import 'requeued_command.dart';

/// Base class for actions the conflict resolver assigns to individual commands.
sealed class CommandResolutionAction {
  /// Creates an action targeting [opId].
  const CommandResolutionAction({required this.opId});

  /// The operation identifier of the command being resolved.
  final String opId;
}

/// Terminal action: acknowledge the command and remove it from the outbox.
final class AckCommandAction extends CommandResolutionAction {
  /// Creates an ack action for [opId].
  const AckCommandAction({required super.opId, this.reason});

  /// Optional diagnostic reason for the ack.
  final String? reason;
}

/// Terminal action: mark the command as failed with retry metadata.
final class FailCommandAction extends CommandResolutionAction {
  /// Creates a fail action for [opId].
  const FailCommandAction({
    required super.opId,
    required this.error,
    this.retryAfter = const Duration(seconds: 30),
  });

  /// Error description stored on the failed row.
  final String error;

  /// Delay before the command becomes eligible for retry.
  final Duration retryAfter;
}

/// Action: replay or rebuild the command with a fresh cursor.
///
/// [requeuedCommands] contains the replacement commands to append to the outbox.
/// [baseCursor] is the current local cursor after pull, used as the new base.
final class RequeueCommandAction extends CommandResolutionAction {
  /// Creates a requeue action for [opId].
  const RequeueCommandAction({
    required super.opId,
    required this.requeuedCommands,
    required this.baseCursor,
    this.reason,
  });

  /// Replacement commands to enqueue.
  final List<RequeuedCommand> requeuedCommands;

  /// The cursor to use as base for the new envelopes.
  final SyncCursor baseCursor;

  /// Optional diagnostic reason for the requeue.
  final String? reason;
}
