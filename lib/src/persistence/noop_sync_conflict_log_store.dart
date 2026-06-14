import '../protocol/sync_cursor.dart';
import 'sync_conflict_log_store.dart';

/// No-op [SyncConflictLogStore] that discards all decisions.
///
/// Use this when conflict logging is not required. The store is safe to
/// const-construct and can be used as the default for [SyncStores].
class NoopSyncConflictLogStore implements SyncConflictLogStore {
  /// Creates a no-op conflict log store.
  const NoopSyncConflictLogStore();

  @override
  Future<int> logDecision({
    String? opId,
    required String entityTableName,
    String? rowId,
    required SyncConflictDecision decision,
    String? reason,
    SyncCursor? localCursor,
    SyncCursor? serverCursor,
    DateTime? localModifiedAtUtc,
    DateTime? serverModifiedAtUtc,
  }) async =>
      0;

  @override
  Future<void> clear() async {}
}
