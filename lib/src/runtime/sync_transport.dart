import '../protocol/sync_batch_request.dart';
import '../protocol/sync_batch_response.dart';

/// Contract for one push/pull round-trip against the sync server.
///
/// Host apps implement this with their HTTP client (e.g. Supabase, Dio).
abstract interface class SyncTransport {
  /// Sends [request] to the server and returns the parsed response.
  Future<SyncBatchResponse> pushPull(SyncBatchRequest request);
}

/// A no-op transport that acks all commands and returns no changes.
///
/// Useful for tests or offline-only modes.
class NoopSyncTransport implements SyncTransport {
  /// Creates a const [NoopSyncTransport].
  const NoopSyncTransport();

  @override
  Future<SyncBatchResponse> pushPull(SyncBatchRequest request) async {
    final List<SyncCommandResult> results = request.commands
        .map(
          (envelope) => SyncCommandResult(
            opId: envelope.opId,
            status: SyncCommandResultStatus.applied,
            latestCursor: request.sinceCursor,
          ),
        )
        .toList(growable: false);

    return SyncBatchResponse(
      commandResults: results,
      changes: const <ServerChange>[],
      newCursor: request.sinceCursor,
      hasMore: false,
    );
  }
}
