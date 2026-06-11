import '../../persistence/sync_outbox_store.dart';
import '../../protocol/sync_batch_request.dart';

/// Result of [SyncUnitOfWork.prepareBatch].
///
/// Bundles the wire [request], the list of [inFlightOpIds], and the full
/// [inFlightCommands] for later resolution and commit.
class PreparedSyncBatch {
  /// Creates a prepared batch.
  const PreparedSyncBatch({
    required this.request,
    required this.inFlightOpIds,
    required this.inFlightCommands,
  });

  /// The wire request built from pending commands and current cursor.
  final SyncBatchRequest request;

  /// Operation identifiers of the commands marked in-flight.
  final List<String> inFlightOpIds;

  /// Full decoded command envelopes (including rebuild context).
  final List<DecodedOutboxCommand> inFlightCommands;

  /// Whether this batch contains at least one command to push.
  bool get hasCommands => inFlightOpIds.isNotEmpty;
}
