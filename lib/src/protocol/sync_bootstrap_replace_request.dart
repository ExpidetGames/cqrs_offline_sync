import 'sync_cursor.dart';
import '../runtime/rebuild/rebuild_graph.dart';

/// A single table's contribution to a bootstrap-replace snapshot.
///
/// Contains the table name and all rows projected as JSON maps
/// via [RebuildGraphNode.toSnapshot].
class SyncBootstrapReplaceTableSnapshot {
  const SyncBootstrapReplaceTableSnapshot({
    required this.tableName,
    required this.rows,
  });

  final String tableName;
  final List<Map<String, dynamic>> rows;

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'tableName': tableName,
      'rows': rows,
    };
  }
}

/// Generic bootstrap-replace snapshot built from rebuild graph nodes.
///
/// The `tables` list preserves insertion order from the rebuild graph,
/// which determines the clear/insert order on the backend.
class SyncBootstrapReplaceSnapshot {
  const SyncBootstrapReplaceSnapshot({required this.tables});

  final List<SyncBootstrapReplaceTableSnapshot> tables;

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'tables': tables.map((SyncBootstrapReplaceTableSnapshot t) => t.toJson()).toList(growable: false),
    };
  }
}

class SyncBootstrapReplaceRequest {
  const SyncBootstrapReplaceRequest({
    required this.expectedSyncEpoch,
    required this.snapshot,
    required this.confirmationToken,
  });

  final SyncEpoch expectedSyncEpoch;
  final SyncBootstrapReplaceSnapshot snapshot;
  final String confirmationToken;

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'expectedSyncEpoch': expectedSyncEpoch.value,
      'confirmationToken': confirmationToken,
      'snapshot': snapshot.toJson(),
    };
  }
}
