import '../../protocol/sync_bootstrap_replace_request.dart';
import '../../protocol/sync_bootstrap_replace_response.dart';
import '../../protocol/sync_cursor.dart';
import '../../persistence/sync_state_store.dart';
import '../rebuild/rebuild_graph.dart';
import 'sync_bootstrap_replace_client.dart';

/// Builds and sends a full local snapshot to the server as part of a
/// device-wins auth flow.
///
/// The service is host-agnostic: it depends only on [RebuildGraph],
/// [SyncBootstrapReplaceClient], and [SyncStateStore]. Host apps provide the
/// transport client and decide when to call [replaceServerWithLocalSnapshot].
class SyncBootstrapReplaceService {
  /// Creates a service backed by [client], [stateStore], and [rebuildGraph].
  const SyncBootstrapReplaceService({
    required SyncBootstrapReplaceClient client,
    required SyncStateStore stateStore,
    required RebuildGraph rebuildGraph,
  })  : _client = client,
        _stateStore = stateStore,
        _rebuildGraph = rebuildGraph;

  final SyncBootstrapReplaceClient _client;
  final SyncStateStore _stateStore;
  final RebuildGraph _rebuildGraph;

  /// Builds a snapshot from [rebuildGraph], sends it to the server, and
  /// persists the returned cursor and epoch.
  ///
  /// [expectedSyncEpoch] is the server epoch the host app expects to replace.
  /// [confirmationToken] is a host-generated token used by the server to guard
  /// against accidental or duplicate replace operations.
  Future<SyncBootstrapReplaceResponse> replaceServerWithLocalSnapshot({
    required SyncEpoch expectedSyncEpoch,
    required String confirmationToken,
  }) async {
    final SyncBootstrapReplaceSnapshot snapshot = await _buildSnapshot();

    final SyncBootstrapReplaceResponse response = await _client.replace(
      SyncBootstrapReplaceRequest(
        expectedSyncEpoch: expectedSyncEpoch,
        snapshot: snapshot,
        confirmationToken: confirmationToken,
      ),
    );

    await _stateStore.writeLastServerCursor(response.newCursor);
    await _stateStore.writeLastSyncEpoch(response.newSyncEpoch);

    return response;
  }

  Future<SyncBootstrapReplaceSnapshot> _buildSnapshot() async {
    final List<SyncBootstrapReplaceTableSnapshot> tableSnapshots =
        <SyncBootstrapReplaceTableSnapshot>[];

    final List<AnyRebuildGraphNode> orderedNodes = _topologicalSortNodes();

    for (final AnyRebuildGraphNode node in orderedNodes) {
      final List<Object> rows = await node.loadAll();
      if (rows.isEmpty) {
        continue;
      }

      tableSnapshots.add(
        SyncBootstrapReplaceTableSnapshot(
          tableName: node.tableName,
          rows: rows
              .map((Object row) => node.toSnapshot(row))
              .toList(growable: false),
        ),
      );
    }

    return SyncBootstrapReplaceSnapshot(tables: tableSnapshots);
  }

  /// Returns nodes ordered so parent tables appear before child tables.
  List<AnyRebuildGraphNode> _topologicalSortNodes() {
    final List<AnyRebuildGraphNode> ordered = <AnyRebuildGraphNode>[];
    final Set<String> visited = <String>{};

    void visit(AnyRebuildGraphNode node) {
      if (!visited.add(node.tableName)) {
        return;
      }

      for (final AnyRebuildGraphEdge edge in _rebuildGraph.childrenOf(node.tableName)) {
        final AnyRebuildGraphNode? child = _rebuildGraph.nodeForTable(edge.childTableName);
        if (child != null) {
          visit(child);
        }
      }

      ordered.add(node);
    }

    for (final AnyRebuildGraphNode node in _rebuildGraph.allNodes) {
      visit(node);
    }

    return ordered.reversed.toList(growable: false);
  }
}
