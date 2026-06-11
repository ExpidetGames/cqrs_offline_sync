import '../conflict/requeued_command.dart';
import 'delete_rebuild_planner.dart';
import 'rebuild_graph.dart';
import 'rebuild_instructions.dart';

/// [DeleteRebuildPlanner] that traverses a [RebuildGraph] to capture full
/// subtrees when a parent row is deleted.
///
/// For each delete, it loads the row, collects all descendant rows via graph
/// edges, and produces a [RebuildInstruction] containing create commands for
/// the entire subtree.
class GraphDeleteRebuildPlanner implements DeleteRebuildPlanner {
  /// Creates a planner backed by [graph].
  const GraphDeleteRebuildPlanner({required RebuildGraph graph}) : _graph = graph;

  final RebuildGraph _graph;

  @override
  Future<RebuildInstruction?> planForDelete({
    required String tableName,
    required String rowId,
  }) async {
    final _GraphNodeState? root = await _resolveRoot(tableName: tableName, rowId: rowId);
    if (root == null) {
      return null;
    }

    final List<RebuildEntityRef> coveredEntities = <RebuildEntityRef>[];
    final List<RequeuedCommand> commands = <RequeuedCommand>[];
    final Set<String> visitedEntityKeys = <String>{};
    await _collectSubtree(
      current: root,
      coveredEntities: coveredEntities,
      commands: commands,
      visitedEntityKeys: visitedEntityKeys,
    );

    if (coveredEntities.isEmpty || commands.isEmpty) {
      return null;
    }

    return RebuildInstruction(
      rootEntity: coveredEntities.first,
      coveredEntities: coveredEntities,
      commands: commands,
    );
  }

  Future<_GraphNodeState?> _resolveRoot({required String tableName, required String rowId}) async {
    final AnyRebuildGraphNode? startNode = _graph.nodeForTable(tableName);
    if (startNode == null) {
      return null;
    }

    final Object? startRow = await startNode.loadById(rowId);
    if (startRow == null) {
      return null;
    }

    return _GraphNodeState(node: startNode, row: startRow);
  }

  Future<void> _collectSubtree({
    required _GraphNodeState current,
    required List<RebuildEntityRef> coveredEntities,
    required List<RequeuedCommand> commands,
    required Set<String> visitedEntityKeys,
  }) async {
    final RebuildEntityRef currentEntity = current.node.toEntityRef(current.row);
    if (visitedEntityKeys.add(currentEntity.key)) {
      coveredEntities.add(currentEntity);
      commands.add(current.node.toCreateCommand(current.row));

      for (final AnyRebuildGraphEdge edge in _graph.childrenOf(current.node.tableName)) {
        final AnyRebuildGraphNode? childNode = _graph.nodeForTable(edge.childTableName);
        if (childNode == null) {
          continue;
        }

        final List<Object> childRows = await edge.loadChildren(current.row);
        for (final Object childRow in childRows) {
          await _collectSubtree(
            current: _GraphNodeState(node: childNode, row: childRow),
            coveredEntities: coveredEntities,
            commands: commands,
            visitedEntityKeys: visitedEntityKeys,
          );
        }
      }
    }
  }
}

class _GraphNodeState {
  const _GraphNodeState({required this.node, required this.row});

  final AnyRebuildGraphNode node;
  final Object row;
}
