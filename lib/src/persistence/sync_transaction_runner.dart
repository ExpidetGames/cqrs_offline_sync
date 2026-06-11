/// Signature for running a callback inside a database transaction.
///
/// Host apps provide this so the sync runtime can execute batch commit
/// operations atomically with their own local database.
typedef SyncPersistenceTransactionRunner = Future<T> Function<T>(
  Future<T> Function() action,
);
