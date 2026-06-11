/// Contract for a local data scope that can be queried and cleared.
///
/// Used by auth reset flows (login/logout/delete account) to determine
/// whether a module has local data and to clear it when needed.
///
/// Library users implement this for each module that participates in sync.
abstract interface class LocalDataScope {
  /// Stable identifier for this scope (e.g. 'vocab_trainer', 'workspace').
  ///
  /// Must be unique across all registered modules.
  String get id;

  /// Returns true if this scope contains any local data.
  Future<bool> hasData();

  /// Clears all local data in this scope.
  Future<void> clear();
}
