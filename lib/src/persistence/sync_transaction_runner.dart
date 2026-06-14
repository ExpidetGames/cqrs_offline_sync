/// Signature for running a callback inside a database transaction.
///
/// Host apps provide this so the sync runtime can execute batch commit
/// operations atomically with their own local database. The same runner is
/// used for both sync-unit-of-work commits and write-side units of work.
typedef SyncTransactionRunner = Future<T> Function<T>(
  Future<T> Function() action,
);
