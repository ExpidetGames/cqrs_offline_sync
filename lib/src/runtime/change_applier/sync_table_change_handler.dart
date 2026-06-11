import '../../protocol/server_change.dart';

/// Core contract for applying a single server feed change to a local table.
///
/// Each syncable table provides one implementation of this interface.
/// The composite change applier dispatches changes by [tableName].
///
/// Implementations live in module-specific table handler files.
abstract interface class SyncTableChangeHandler {
  /// The server feed table name this handler is responsible for.
  ///
  /// Must match the `table` field from [ServerChange].
  String get tableName;

  /// Applies a single server change (upsert or delete) to the local database.
  Future<void> apply(ServerChange change);
}
