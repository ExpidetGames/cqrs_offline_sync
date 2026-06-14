import 'sync_stores.dart';

/// Clears runtime queue data without touching sync state.
///
/// This is a separate helper rather than a method on [CqrsSyncRuntime] so
/// callers can decide when and whether to wrap it in a transaction.
class SyncRuntimeQueueReset {
  /// Creates a queue reset helper backed by [stores].
  const SyncRuntimeQueueReset({required this.stores});

  /// The stores to clear.
  final SyncStores stores;

  /// Clears outbox, conflict log, and rebuild instructions in that order.
  ///
  /// Does not clear sync state (cursor/epoch).
  Future<void> clear() async {
    await stores.outbox.clear();
    await stores.conflictLog.clear();
    await stores.rebuildInstructions.clear();
  }
}
