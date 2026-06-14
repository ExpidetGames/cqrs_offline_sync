import 'json_parse_utils.dart';
import 'server_change.dart';
import 'sync_cursor.dart';

export 'server_change.dart';

/// Overall status of a [SyncBatchResponse].
enum SyncBatchResponseStatus {
  ok,
  resyncRequired;

  @override
  String toString() {
    return switch (this) {
      SyncBatchResponseStatus.ok => 'ok',
      SyncBatchResponseStatus.resyncRequired => 'resync_required',
    };
  }

  static SyncBatchResponseStatus fromString(String status) {
    return switch (status) {
      'ok' => SyncBatchResponseStatus.ok,
      'resync_required' => SyncBatchResponseStatus.resyncRequired,
      _ => throw FormatException('Unknown sync batch response status: $status'),
    };
  }
}

/// Server response for one sync batch.
///
/// Contains per-command results, downstream [changes], the [newCursor],
/// and pagination state ([hasMore]).
class SyncBatchResponse {
  const SyncBatchResponse({
    this.status = SyncBatchResponseStatus.ok,
    required this.commandResults,
    required this.changes,
    required this.newCursor,
    this.expectedSyncEpoch,
    this.hasMore = false,
  });

  /// Overall status of this batch.
  final SyncBatchResponseStatus status;

  /// Per-command results in the same order as the request.
  final List<SyncCommandResult> commandResults;

  /// Downstream server changes to apply locally.
  final List<ServerChange> changes;

  /// Highest cursor in this response.
  final SyncCursor newCursor;

  /// Expected sync epoch when [status] is [resyncRequired].
  final SyncEpoch? expectedSyncEpoch;

  /// Whether additional pull pages exist on the server.
  final bool hasMore;

  /// Whether the server signaled that a full resync is required.
  bool get isResyncRequired => status == SyncBatchResponseStatus.resyncRequired;

  /// Serializes this response to JSON.
  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'status': status.toString(),
      'commandResults': commandResults
          .map((result) => result.toJson())
          .toList(growable: false),
      'changes': changes
          .map((change) => change.toJson())
          .toList(growable: false),
      'newCursor': newCursor.value,
      if (expectedSyncEpoch != null)
        'expectedSyncEpoch': expectedSyncEpoch!.value,
      'hasMore': hasMore,
    };
  }

  /// Parses a [SyncBatchResponse] from JSON.
  factory SyncBatchResponse.fromJson(Map<String, dynamic> json) {
    final rawResults = asListOr(
      json['commandResults'] ?? json['acked'],
      fallback: const <dynamic>[],
    );
    final rawChanges = asListOr(json['changes'], fallback: const <dynamic>[]);
    final statusWire = asStringOr(json['status'], fallback: 'ok');
    final status = SyncBatchResponseStatus.fromString(statusWire);

    final newCursorRaw = asStringOr(json['newCursor'], fallback: '');
    if (newCursorRaw.isEmpty) {
      throw const FormatException('Missing required newCursor.');
    }

    final expectedSyncEpochRaw = asStringOr(
      json['expectedSyncEpoch'],
      fallback: '',
    );
    if (status == SyncBatchResponseStatus.resyncRequired &&
        expectedSyncEpochRaw.isEmpty) {
      throw const FormatException(
        'Missing expectedSyncEpoch for resync_required response.',
      );
    }

    return SyncBatchResponse(
      status: status,
      commandResults: rawResults
          .map((entry) => asMapOr(entry, fallback: const <String, dynamic>{}))
          .where((entry) => entry.isNotEmpty)
          .map(SyncCommandResult.fromJson)
          .toList(growable: false),
      changes: rawChanges
          .map((entry) => asMapOr(entry, fallback: const <String, dynamic>{}))
          .where((entry) => entry.isNotEmpty)
          .map(ServerChange.fromJson)
          .toList(growable: false),
      newCursor: SyncCursor(newCursorRaw),
      expectedSyncEpoch: expectedSyncEpochRaw.isEmpty
          ? null
          : SyncEpoch(expectedSyncEpochRaw),
      hasMore: asBoolOr(json['hasMore'], fallback: false),
    );
  }

  /// Looks up a [SyncCommandResult] by [opId], or `null`.
  SyncCommandResult? getResultByOpId(String opId) {
    for (final result in commandResults) {
      if (result.opId == opId) {
        return result;
      }
    }
    return null;
  }
}

/// Status of a single command after server evaluation.
enum SyncCommandResultStatus {
  applied,
  noopAlreadyApplied,
  rejectedConflictStale,
  rejectedInvalid,
  retryableError;

  @override
  String toString() {
    return switch (this) {
      SyncCommandResultStatus.applied => 'applied',
      SyncCommandResultStatus.noopAlreadyApplied => 'noop_already_applied',
      SyncCommandResultStatus.rejectedConflictStale =>
        'rejected_conflict_stale',
      SyncCommandResultStatus.rejectedInvalid => 'rejected_invalid',
      SyncCommandResultStatus.retryableError => 'retryable_error',
    };
  }

  static SyncCommandResultStatus fromString(String status) {
    return switch (status) {
      'applied' => SyncCommandResultStatus.applied,
      'noop_already_applied' => SyncCommandResultStatus.noopAlreadyApplied,
      'rejected_conflict_stale' =>
        SyncCommandResultStatus.rejectedConflictStale,
      'rejected_invalid' => SyncCommandResultStatus.rejectedInvalid,
      'retryable_error' => SyncCommandResultStatus.retryableError,
      _ => throw FormatException('Unknown command result status: $status'),
    };
  }
}

/// Result for one command in a [SyncBatchResponse].
class SyncCommandResult {
  const SyncCommandResult({
    required this.opId,
    required this.status,
    required this.latestCursor,
    this.reasonCode,
    this.reason,
    this.latestRow,
  });

  /// The operation identifier matching the request envelope.
  final String opId;

  /// Server-evaluated status.
  final SyncCommandResultStatus status;

  /// Optional stable machine-readable reason code for automated routing.
  ///
  /// Use this instead of parsing [reason] for new machine logic. See
  /// [SyncCommandResultReasonCodes] for defined values.
  final String? reasonCode;

  /// Optional human-readable reason (often used for errors or diagnostics).
  ///
  /// New machine-readable routing logic should prefer [reasonCode].
  final String? reason;

  /// Highest server cursor at the time this result was produced.
  final SyncCursor latestCursor;

  /// Latest server row snapshot for upserts (e.g. for conflict diagnostics).
  final Map<String, dynamic>? latestRow;

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'opId': opId,
      'status': status.toString(),
      if (reasonCode != null) 'reasonCode': reasonCode,
      if (reason != null) 'reason': reason,
      'latestCursor': latestCursor.value,
      if (latestRow != null) 'latestRow': latestRow,
    };
  }

  factory SyncCommandResult.fromJson(Map<String, dynamic> json) {
    final opId = asStringOr(json['opId'], fallback: '');
    final statusWire = asStringOr(
      json['status'],
      fallback: SyncCommandResultStatus.retryableError.toString(),
    );
    final reasonCode = asStringOr(json['reasonCode'], fallback: '');
    final reason = asStringOr(json['reason'], fallback: '');
    final latestCursorRaw = asStringOr(json['latestCursor'], fallback: '');
    if (latestCursorRaw.isEmpty) {
      throw const FormatException('Missing required latestCursor.');
    }
    final latestRow = asMapOr(
      json['latestRow'],
      fallback: const <String, dynamic>{},
    );

    return SyncCommandResult(
      opId: opId,
      status: SyncCommandResultStatus.fromString(statusWire),
      reasonCode: reasonCode.isEmpty ? null : reasonCode,
      reason: reason.isEmpty ? null : reason,
      latestCursor: SyncCursor(latestCursorRaw),
      latestRow: latestRow.isEmpty ? null : latestRow,
    );
  }
}
