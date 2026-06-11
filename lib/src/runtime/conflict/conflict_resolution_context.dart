import '../../commands/command_envelope.dart';
import '../../commands/sync_command.dart';
import '../../persistence/sync_outbox_store.dart';
import '../../protocol/sync_batch_response.dart';
import '../../protocol/sync_cursor.dart';
import '../models/prepared_sync_batch.dart';
import '../rebuild/rebuild_instructions.dart';

/// Context provided to [ConflictResolver] during stale resolution.
///
/// Bundles the original batch, server response, rebuild instructions, and the
/// current requeue base cursor.
class ConflictResolutionContext {
  /// Creates a resolution context.
  const ConflictResolutionContext({
    required this.batch,
    required this.response,
    required this.requeueBaseCursor,
    this.rebuildInstructions = RebuildInstructions.empty,
  });

  /// The batch that was sent in this sync run.
  final PreparedSyncBatch batch;

  /// Server response containing per-command results.
  final SyncBatchResponse response;

  /// Cursor to use as base for any requeued commands.
  final SyncCursor requeueBaseCursor;

  /// Rebuild instructions captured during change application.
  final RebuildInstructions rebuildInstructions;

  /// Looks up an in-flight command by [opId], or `null` if not found.
  DecodedOutboxCommand? inFlightCommandByOpId(String opId) {
    for (final DecodedOutboxCommand command in batch.inFlightCommands) {
      if (command.opId == opId) {
        return command;
      }
    }
    return null;
  }

  /// Returns the envelope for an in-flight command by [opId].
  CommandEnvelope<SyncCommand>? commandByOpId(String opId) {
    return inFlightCommandByOpId(opId)?.envelope;
  }
}
