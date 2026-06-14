import '../protocol/sync_cursor.dart';

/// Decision made by the conflict resolver for a single stale command.
enum SyncConflictDecision {
  /// Accept the server change and overwrite the local row.
  applyServer,

  /// Preserve the local row and discard the server change.
  keepLocal,
}

/// Audit-log store for conflict resolution decisions.
///
/// Implementations typically persist a local-only table of decisions so
/// diagnostics and telemetry can inspect how conflicts were resolved.
abstract interface class SyncConflictLogStore {
  /// Records a conflict decision.
  ///
  /// [entityTableName] and [decision] are required; everything else is optional
  /// context that can help during debugging or support analysis.
  Future<int> logDecision({
    String? opId,
    required String entityTableName,
    String? rowId,
    required SyncConflictDecision decision,
    String? reason,
    SyncCursor? localCursor,
    SyncCursor? serverCursor,
    DateTime? localModifiedAtUtc,
    DateTime? serverModifiedAtUtc,
  });

  /// Removes all recorded decisions.
  Future<void> clear();
}
