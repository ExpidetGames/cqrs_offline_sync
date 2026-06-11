import '../conflict/requeued_command.dart';
import 'rebuild_instructions.dart';

/// Reference to a parent entity used when building [RebuildGraph] edges.
class RebuildGraphParentRef {
  /// Creates a parent reference.
  const RebuildGraphParentRef({required this.tableName, required this.rowId});

  final String tableName;
  final String rowId;
}

typedef RebuildGraphRowLoader<RowT extends Object> = Future<RowT?> Function(String rowId);
typedef RebuildGraphAllRowsLoader<RowT extends Object> = Future<List<RowT>> Function();
typedef RebuildGraphEntityBuilder<RowT extends Object> = RebuildEntityRef Function(RowT row);
typedef RebuildGraphCommandBuilder<RowT extends Object> = RequeuedCommand Function(RowT row);
typedef RebuildGraphSnapshotProjection<RowT extends Object> = Map<String, dynamic> Function(RowT row);
typedef RebuildGraphParentResolver<RowT extends Object> = RebuildGraphParentRef? Function(RowT row);

/// Untyped node contract for [RebuildGraph].
///
/// Implementations are typically [RebuildGraphNode<RowT>] with a concrete row type.
abstract interface class AnyRebuildGraphNode {
  String get tableName;

  Future<Object?> loadById(String rowId);

  /// Loads all rows from this table for snapshot building.
  Future<List<Object>> loadAll();

  RebuildEntityRef toEntityRef(Object row);

  RequeuedCommand toCreateCommand(Object row);

  /// Projects a row to a JSON map for the bootstrap-replace snapshot.
  ///
  /// This is a separate projection from [toCreateCommand] — it uses the
  /// wire-format field names expected by the backend bootstrap-replace gateway.
  Map<String, dynamic> toSnapshot(Object row);

  RebuildGraphParentRef? parentOf(Object row);
}

/// Typed node in a [RebuildGraph].
///
/// Binds a table to row load/create/snapshot operations for a concrete [RowT].
class RebuildGraphNode<RowT extends Object> implements AnyRebuildGraphNode {
  const RebuildGraphNode({
    required this.tableName,
    required RebuildGraphRowLoader<RowT> loadById,
    required RebuildGraphAllRowsLoader<RowT> loadAll,
    required RebuildGraphEntityBuilder<RowT> toEntityRef,
    required RebuildGraphCommandBuilder<RowT> toCreateCommand,
    required RebuildGraphSnapshotProjection<RowT> toSnapshot,
    RebuildGraphParentResolver<RowT>? parentOf,
  }) : _loadById = loadById,
       _loadAll = loadAll,
       _toEntityRef = toEntityRef,
       _toCreateCommand = toCreateCommand,
       _toSnapshot = toSnapshot,
       _parentOf = parentOf;

  @override
  final String tableName;

  final RebuildGraphRowLoader<RowT> _loadById;
  final RebuildGraphAllRowsLoader<RowT> _loadAll;
  final RebuildGraphEntityBuilder<RowT> _toEntityRef;
  final RebuildGraphCommandBuilder<RowT> _toCreateCommand;
  final RebuildGraphSnapshotProjection<RowT> _toSnapshot;
  final RebuildGraphParentResolver<RowT>? _parentOf;

  @override
  Future<Object?> loadById(String rowId) {
    return _loadById(rowId);
  }

  @override
  Future<List<Object>> loadAll() async {
    final List<RowT> rows = await _loadAll();
    return List<Object>.from(rows);
  }

  @override
  RebuildEntityRef toEntityRef(Object row) {
    return _toEntityRef(_castRow(row));
  }

  @override
  RequeuedCommand toCreateCommand(Object row) {
    return _toCreateCommand(_castRow(row));
  }

  @override
  Map<String, dynamic> toSnapshot(Object row) {
    return _toSnapshot(_castRow(row));
  }

  @override
  RebuildGraphParentRef? parentOf(Object row) {
    final RebuildGraphParentResolver<RowT>? parentResolver = _parentOf;
    if (parentResolver == null) {
      return null;
    }
    return parentResolver(_castRow(row));
  }

  RowT _castRow(Object row) {
    if (row is! RowT) {
      throw StateError(
        'Row cast failed for table $tableName. '
        'Expected $RowT, got ${row.runtimeType}.',
      );
    }
    return row;
  }
}

typedef RebuildGraphChildrenLoader<ParentT extends Object, ChildT extends Object> =
    Future<List<ChildT>> Function(ParentT parentRow);

/// Untyped edge contract for [RebuildGraph].
///
/// Defines a parent-child relationship between two tables.
abstract interface class AnyRebuildGraphEdge {
  String get parentTableName;

  String get childTableName;

  Future<List<Object>> loadChildren(Object parentRow);
}

/// Typed edge in a [RebuildGraph].
class RebuildGraphEdge<ParentT extends Object, ChildT extends Object> implements AnyRebuildGraphEdge {
  const RebuildGraphEdge({
    required this.parentTableName,
    required this.childTableName,
    required RebuildGraphChildrenLoader<ParentT, ChildT> loadChildren,
  }) : _loadChildren = loadChildren;

  @override
  final String parentTableName;

  @override
  final String childTableName;

  final RebuildGraphChildrenLoader<ParentT, ChildT> _loadChildren;

  @override
  Future<List<Object>> loadChildren(Object parentRow) async {
    if (parentRow is! ParentT) {
      throw StateError(
        'Parent row cast failed for edge $parentTableName -> $childTableName. '
        'Expected $ParentT, got ${parentRow.runtimeType}.',
      );
    }
    final List<ChildT> children = await _loadChildren(parentRow);
    return List<Object>.from(children);
  }
}

/// Graph of entities used for delete-rebuild planning and bootstrap-replace snapshots.
///
/// Nodes represent tables; edges represent parent-child relationships. The graph
/// is traversed by [GraphDeleteRebuildPlanner] to capture subtrees before deletes,
/// and by [SyncBootstrapReplaceService] to build table-level snapshots.
class RebuildGraph {
  RebuildGraph({
    required Iterable<AnyRebuildGraphNode> nodes,
    Iterable<AnyRebuildGraphEdge> edges = const <AnyRebuildGraphEdge>[],
  }) : _nodesByTable = <String, AnyRebuildGraphNode>{},
       _edgesByParent = <String, List<AnyRebuildGraphEdge>>{},
       _allEdges = <AnyRebuildGraphEdge>[] {
    final List<AnyRebuildGraphNode> nodeList = nodes.toList(growable: false);
    for (final AnyRebuildGraphNode node in nodeList) {
      _nodesByTable[node.tableName] = node;
    }
    if (_nodesByTable.length != nodeList.length) {
      throw StateError('Duplicate tableName entries in RebuildGraph nodes.');
    }

    for (final AnyRebuildGraphEdge edge in edges) {
      if (!_nodesByTable.containsKey(edge.parentTableName)) {
        throw StateError(
          'RebuildGraph edge parent table is not registered: '
          '${edge.parentTableName}.',
        );
      }
      if (!_nodesByTable.containsKey(edge.childTableName)) {
        throw StateError(
          'RebuildGraph edge child table is not registered: '
          '${edge.childTableName}.',
        );
      }

      _edgesByParent.putIfAbsent(edge.parentTableName, () => <AnyRebuildGraphEdge>[]);
      _edgesByParent[edge.parentTableName]!.add(edge);
      _allEdges.add(edge);
    }
  }

  final Map<String, AnyRebuildGraphNode> _nodesByTable;
  final Map<String, List<AnyRebuildGraphEdge>> _edgesByParent;
  final List<AnyRebuildGraphEdge> _allEdges;

  /// All registered nodes in this graph.
  Iterable<AnyRebuildGraphNode> get allNodes => _nodesByTable.values;

  /// All registered edges in this graph.
  List<AnyRebuildGraphEdge> get allEdges =>
      List<AnyRebuildGraphEdge>.unmodifiable(_allEdges);

  /// Looks up a node by [tableName], or `null`.
  AnyRebuildGraphNode? nodeForTable(String tableName) {
    return _nodesByTable[tableName];
  }

  /// Returns the child edges for a given parent [tableName].
  List<AnyRebuildGraphEdge> childrenOf(String tableName) {
    return List<AnyRebuildGraphEdge>.unmodifiable(_edgesByParent[tableName] ?? const <AnyRebuildGraphEdge>[]);
  }
}
