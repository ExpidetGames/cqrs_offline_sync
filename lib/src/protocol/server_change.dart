import 'json_parse_utils.dart';
import 'sync_cursor.dart';

/// A single server feed change delivered in a [SyncBatchResponse].
///
/// Subtypes are [UpsertServerChange] and [DeleteServerChange].
/// Each change carries a [cursor] for deterministic apply ordering.
sealed class ServerChange {
  const ServerChange({
    required this.cursor,
    required this.table,
    required this.rowId,
    this.modifiedAt,
    this.originOpId,
  });

  /// Creates an upsert change with the given row payload.
  const factory ServerChange.upsert({
    required SyncCursor cursor,
    required String table,
    required String rowId,
    required Map<String, dynamic> row,
    DateTime? modifiedAt,
    String? originOpId,
  }) = UpsertServerChange;

  /// Creates a delete change.
  const factory ServerChange.delete({
    required SyncCursor cursor,
    required String table,
    required String rowId,
    DateTime? modifiedAt,
    String? originOpId,
  }) = DeleteServerChange;

  /// Server cursor defining apply order.
  final SyncCursor cursor;

  /// Target table name.
  final String table;

  /// Identifier of the affected row.
  final String rowId;

  /// Optional server-side modification timestamp.
  final DateTime? modifiedAt;

  /// Optional opId that produced this change on the server.
  final String? originOpId;

  /// `'upsert'` or `'delete'`.
  String get operation;

  /// Serializes this change to a JSON map.
  Map<String, dynamic> toJson();

  /// Parses a [ServerChange] from JSON.
  ///
  /// Throws [FormatException] for missing/unknown fields.
  factory ServerChange.fromJson(Map<String, dynamic> json) {
    final operation = asStringOr(json['operation'], fallback: '');
    final cursor = SyncCursor.fromJson(json['cursor']);
    final table = asStringOr(json['table'], fallback: '');
    final rowId = asStringOr(json['rowId'], fallback: '');
    final modifiedAtRaw = json['modifiedAt'];
    final modifiedAt = modifiedAtRaw == null
        ? null
        : asDateTimeOr(
            modifiedAtRaw,
            fallback: DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
          );
    final originOpId = asStringOr(json['originOpId'], fallback: '');

    if (table.isEmpty) {
      throw const FormatException('Missing required server change table.');
    }
    if (rowId.isEmpty) {
      throw const FormatException('Missing required server change rowId.');
    }

    return switch (operation) {
      'upsert' => ServerChange.upsert(
        cursor: cursor,
        table: table,
        rowId: rowId,
        row: asMapOr(json['row'], fallback: const <String, dynamic>{}),
        modifiedAt: modifiedAt,
        originOpId: originOpId.isEmpty ? null : originOpId,
      ),
      'delete' => ServerChange.delete(
        cursor: cursor,
        table: table,
        rowId: rowId,
        modifiedAt: modifiedAt,
        originOpId: originOpId.isEmpty ? null : originOpId,
      ),
      _ => throw FormatException('Unknown server change operation: $operation'),
    };
  }
}

/// Server change that inserts or updates a row.
final class UpsertServerChange extends ServerChange {
  const UpsertServerChange({
    required super.cursor,
    required super.table,
    required super.rowId,
    required this.row,
    super.modifiedAt,
    super.originOpId,
  });

  /// The row payload as a JSON map.
  final Map<String, dynamic> row;

  @override
  String get operation => 'upsert';

  @override
  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'operation': operation,
      'cursor': cursor.value,
      'table': table,
      'rowId': rowId,
      'row': row,
      if (modifiedAt != null)
        'modifiedAt': modifiedAt!.toUtc().toIso8601String(),
      if (originOpId != null) 'originOpId': originOpId,
    };
  }
}

/// Server change that deletes a row.
final class DeleteServerChange extends ServerChange {
  const DeleteServerChange({
    required super.cursor,
    required super.table,
    required super.rowId,
    super.modifiedAt,
    super.originOpId,
  });

  @override
  String get operation => 'delete';

  @override
  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'operation': operation,
      'cursor': cursor.value,
      'table': table,
      'rowId': rowId,
      if (modifiedAt != null)
        'modifiedAt': modifiedAt!.toUtc().toIso8601String(),
      if (originOpId != null) 'originOpId': originOpId,
    };
  }
}
