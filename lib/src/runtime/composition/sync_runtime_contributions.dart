import '../../commands/command_codec_registry.dart';
import '../local_data/local_data_scope.dart';
import '../change_applier/sync_table_change_handler.dart';
import '../conflict/stale_conflict_profile.dart';
import '../rebuild/rebuild_graph.dart';

/// Extra runtime contributions supplied by the host app in addition to those
/// contributed by registered [SyncModuleRegistration]s.
///
/// Extras are append-only: they never override module contributions.
/// Duplicates across modules and extras are detected during composition.
class SyncRuntimeContributions {
  /// Creates empty extra contributions.
  const SyncRuntimeContributions()
      : commandCodecs = const <AnyCommandCodec>[],
        tableChangeHandlers = const <SyncTableChangeHandler>[],
        staleConflictProfiles = const <StaleConflictProfile>[],
        localDataScopes = const <LocalDataScope>[],
        rebuildEdges = const <AnyRebuildGraphEdge>[];

  /// Creates extra contributions from iterables.
  SyncRuntimeContributions.from({
    Iterable<AnyCommandCodec> commandCodecs = const <AnyCommandCodec>[],
    Iterable<SyncTableChangeHandler> tableChangeHandlers = const <SyncTableChangeHandler>[],
    Iterable<StaleConflictProfile> staleConflictProfiles = const <StaleConflictProfile>[],
    Iterable<LocalDataScope> localDataScopes = const <LocalDataScope>[],
    Iterable<AnyRebuildGraphEdge> rebuildEdges = const <AnyRebuildGraphEdge>[],
  })  : commandCodecs = List<AnyCommandCodec>.unmodifiable(commandCodecs),
        tableChangeHandlers = List<SyncTableChangeHandler>.unmodifiable(tableChangeHandlers),
        staleConflictProfiles = List<StaleConflictProfile>.unmodifiable(staleConflictProfiles),
        localDataScopes = List<LocalDataScope>.unmodifiable(localDataScopes),
        rebuildEdges = List<AnyRebuildGraphEdge>.unmodifiable(rebuildEdges);

  /// Extra command codecs.
  final List<AnyCommandCodec> commandCodecs;

  /// Extra table change handlers.
  final List<SyncTableChangeHandler> tableChangeHandlers;

  /// Extra stale conflict profiles.
  final List<StaleConflictProfile> staleConflictProfiles;

  /// Extra local data scopes.
  final List<LocalDataScope> localDataScopes;

  /// Extra rebuild graph edges.
  final List<AnyRebuildGraphEdge> rebuildEdges;
}
