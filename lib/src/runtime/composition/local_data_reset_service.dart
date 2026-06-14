import '../local_data/local_data_scope.dart';

/// Generic service for clearing host app local data during auth reset flows.
///
/// Depends only on [LocalDataScope] and is therefore host-agnostic. It does not
/// clear sync runtime queues; use [SyncRuntimeQueueReset] for that.
class LocalDataResetService {
  /// Creates a reset service from the union of module and extra scopes.
  LocalDataResetService({
    required Iterable<LocalDataScope> scopes,
  })  : _scopes = List<LocalDataScope>.unmodifiable(scopes),
        _byId = _indexById(scopes) {
    if (_byId.length != _scopes.length) {
      throw ArgumentError.value(
        scopes,
        'scopes',
        'Duplicate local data scope ids in LocalDataResetService.',
      );
    }
  }

  final List<LocalDataScope> _scopes;
  final Map<String, LocalDataScope> _byId;

  static Map<String, LocalDataScope> _indexById(Iterable<LocalDataScope> scopes) {
    final Map<String, LocalDataScope> byId = <String, LocalDataScope>{};
    for (final LocalDataScope scope in scopes) {
      byId[scope.id] = scope;
    }
    return byId;
  }

  /// All registered scope ids, in registration order.
  List<String> get scopeIds =>
      _scopes.map((LocalDataScope scope) => scope.id).toList(growable: false);

  /// Clears the scopes identified by [scopeIds].
  ///
  /// Throws [ArgumentError] if [scopeIds] is empty, or if any id is unknown.
  Future<void> clear({required Set<String> scopeIds}) async {
    if (scopeIds.isEmpty) {
      throw ArgumentError.value(scopeIds, 'scopeIds', 'scopeIds must not be empty.');
    }

    final List<LocalDataScope> targets = <LocalDataScope>[];
    for (final String id in scopeIds) {
      final LocalDataScope? scope = _byId[id];
      if (scope == null) {
        throw ArgumentError.value(id, 'scopeIds', 'Unknown local data scope id.');
      }
      targets.add(scope);
    }

    for (final LocalDataScope scope in targets) {
      await scope.clear();
    }
  }

  /// Clears all registered scopes in registration order.
  ///
  /// No-ops when there are zero scopes.
  Future<void> clearAll() async {
    for (final LocalDataScope scope in _scopes) {
      await scope.clear();
    }
  }

  /// Whether any of the scopes in [scopeFilter] have data.
  ///
  /// Throws [ArgumentError] if [scopeFilter] is empty.
  Future<bool> hasAnyData({required Set<String> scopeFilter}) async {
    if (scopeFilter.isEmpty) {
      throw ArgumentError.value(
        scopeFilter,
        'scopeFilter',
        'scopeFilter must not be empty.',
      );
    }

    for (final String id in scopeFilter) {
      final LocalDataScope? scope = _byId[id];
      if (scope == null) {
        throw ArgumentError.value(id, 'scopeFilter', 'Unknown local data scope id.');
      }

      if (await scope.hasData()) {
        return true;
      }
    }

    return false;
  }
}
