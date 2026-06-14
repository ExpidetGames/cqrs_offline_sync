import '../../persistence/sync_outbox_store.dart';
import '../../protocol/sync_batch_response.dart';

/// Context provided to a [SyncStaleRoutingPolicy] when deciding whether a
/// stale command should be routed to its registered [StaleConflictProfile].
class StaleConflictRoutingContext {
  /// Creates a routing context.
  const StaleConflictRoutingContext({
    required this.inFlightCommand,
    required this.result,
    required this.response,
  });

  /// The original in-flight command that was rejected as stale.
  final DecodedOutboxCommand inFlightCommand;

  /// Server result for this command.
  final SyncCommandResult result;

  /// Full server response (for context-aware routing).
  final SyncBatchResponse response;

  /// Convenience accessor for the command type.
  String get commandType => inFlightCommand.envelope.commandType;

  /// Convenience accessor for the result reason code.
  String? get reasonCode => result.reasonCode;

  /// Convenience accessor for the human-readable result reason.
  String? get reason => result.reason;
}
