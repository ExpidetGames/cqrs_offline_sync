import '../protocol/sync_cursor.dart';

/// Persistence contract for sync runtime state.
///
/// Currently stores the last known server cursor and the current sync epoch.
/// Cursor writes are monotonic: a lower or equal candidate is ignored.
abstract interface class SyncStateStore {
  /// Reads the last known server cursor, or [SyncCursor.zero] if none.
  Future<SyncCursor> readLastServerCursorOrZero();

  /// Writes [candidate] only if it is greater than the stored cursor.
  Future<void> writeLastServerCursorIfAdvanced(SyncCursor candidate);

  /// Reads the last known sync epoch, or [SyncEpoch.zero] if none.
  Future<SyncEpoch> readLastSyncEpochOrZero();

  /// Stores the current sync epoch.
  Future<void> writeLastSyncEpoch(SyncEpoch epoch);

  /// Unconditionally sets the server cursor. Used by auth reset flows.
  Future<void> writeLastServerCursor(SyncCursor cursor);

  /// Removes all stored state. Used by auth reset flows.
  Future<void> clearAll();
}
