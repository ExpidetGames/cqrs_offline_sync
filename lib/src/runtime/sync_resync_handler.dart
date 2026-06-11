import '../protocol/sync_cursor.dart';

/// Contract for handling a server-side `resync_required` signal.
///
/// When the server returns [SyncBatchResponseStatus.resyncRequired], the
/// [SyncRunner] pauses normal batch processing and delegates to this handler.
/// The host app typically clears local data, resets cursors, and re-authenticates.
abstract interface class SyncResyncHandler {
  /// Called when the server signals that the client must resync.
  ///
  /// [expectedSyncEpoch] is the new epoch the client should adopt.
  Future<void> onResyncRequired(SyncEpoch expectedSyncEpoch);
}
