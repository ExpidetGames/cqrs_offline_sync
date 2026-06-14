import 'package:cqrs_offline_sync/cqrs_offline_sync.dart';

Future<T> runInMemoryTransaction<T>(Future<T> Function() action) => action();

CommandCodecRegistry testCommandRegistry() {
  return CommandCodecRegistry(<AnyCommandCodec>[testCommandCodec]);
}

CommandEnvelopeFactory testEnvelopeFactory({
  SequentialOpIdGenerator? opIdGenerator,
  DateTime? now,
}) {
  return CommandEnvelopeFactory(
    codecRegistry: testCommandRegistry(),
    opIdGenerator: opIdGenerator ?? SequentialOpIdGenerator(),
    clock: FixedClock(now ?? DateTime.utc(2026, 1, 1)),
  );
}

class TestCommand implements SyncCommand {
  const TestCommand({required this.id, this.value = 'value'});

  static const String type = 'test.command';
  static const String aggregate = 'test.aggregate';

  final String id;
  final String value;

  @override
  String get commandType => type;

  @override
  String get aggregateType => aggregate;

  Map<String, dynamic> toJson() => <String, dynamic>{'id': id, 'value': value};

  static TestCommand fromJson(Map<String, dynamic> json) {
    return TestCommand(
      id: json['id'] as String,
      value: json['value'] as String? ?? 'value',
    );
  }
}

final CommandPayloadCodec<TestCommand> testCommandCodec =
    CommandPayloadCodec<TestCommand>(
      commandType: TestCommand.type,
      aggregateType: TestCommand.aggregate,
      payloadType: TestCommand,
      fromJson: TestCommand.fromJson,
      toJson: (TestCommand command) => command.toJson(),
    );

class InMemorySyncOutboxStore implements SyncOutboxStore {
  final Map<String, InMemoryOutboxRow> rowsByOpId =
      <String, InMemoryOutboxRow>{};
  final List<String> operations = <String>[];
  final List<OutboxFailureUpdate> failures = <OutboxFailureUpdate>[];

  Iterable<InMemoryOutboxRow> get rows => rowsByOpId.values;
  Iterable<InMemoryOutboxRow> get unsettledRows =>
      rows.where((row) => row.status != InMemoryOutboxStatus.acked);
  Iterable<InMemoryOutboxRow> get ackedRows =>
      rows.where((row) => row.status == InMemoryOutboxStatus.acked);
  Iterable<InMemoryOutboxRow> get failedRows =>
      rows.where((row) => row.status == InMemoryOutboxStatus.failed);
  Iterable<InMemoryOutboxRow> get pendingRows =>
      rows.where((row) => row.status == InMemoryOutboxStatus.pending);
  Iterable<InMemoryOutboxRow> get inFlightRows =>
      rows.where((row) => row.status == InMemoryOutboxStatus.inFlight);

  Future<void> appendPayload(
    SyncCommand payload, {
    CommandEnvelopeFactory? envelopeFactory,
    SyncCursor? baseCursor,
    Map<String, dynamic>? rebuildContext,
  }) async {
    final factory = envelopeFactory ?? testEnvelopeFactory();
    await append(
      factory.create(
        payload: payload,
        baseCursor: baseCursor ?? SyncCursor.zero(),
      ),
      rebuildContext: rebuildContext,
    );
  }

  @override
  Future<void> append(
    CommandEnvelope<SyncCommand> envelope, {
    Map<String, dynamic>? rebuildContext,
  }) async {
    operations.add('append:${envelope.opId}:${envelope.baseCursor.value}');
    rowsByOpId[envelope.opId] = InMemoryOutboxRow(
      envelope: envelope,
      rebuildContext: rebuildContext,
    );
  }

  @override
  Future<void> clear() async {
    operations.add('clear');
    rowsByOpId.clear();
  }

  @override
  Future<bool> hasUnsettledCommands() async {
    operations.add('hasUnsettledCommands');
    return unsettledRows.isNotEmpty;
  }

  @override
  Future<void> markAcked(Iterable<String> opIds) async {
    final ids = opIds.toList(growable: false);
    operations.add('markAcked:${ids.join(',')}');
    for (final opId in ids) {
      rowsByOpId[opId]?.status = InMemoryOutboxStatus.acked;
    }
  }

  @override
  Future<void> markInFlight(Iterable<String> opIds) async {
    final ids = opIds.toList(growable: false);
    operations.add('markInFlight:${ids.join(',')}');
    for (final opId in ids) {
      rowsByOpId[opId]?.status = InMemoryOutboxStatus.inFlight;
    }
  }

  @override
  Future<void> markManyFailed(Iterable<OutboxFailureUpdate> failures) async {
    final updates = failures.toList(growable: false);
    operations.add(
      'markManyFailed:${updates.map((failure) => failure.opId).join(',')}',
    );
    this.failures.addAll(updates);
    for (final failure in updates) {
      final row = rowsByOpId[failure.opId];
      if (row != null) {
        row.status = InMemoryOutboxStatus.failed;
        row.error = failure.error;
        row.retryAfter = failure.retryAfter;
      }
    }
  }

  @override
  Future<List<DecodedOutboxCommand>> nextPending({int limit = 100}) async {
    operations.add('nextPending:$limit');
    return rows
        .where(
          (row) =>
              row.status == InMemoryOutboxStatus.pending ||
              row.status == InMemoryOutboxStatus.failed,
        )
        .take(limit)
        .map(
          (row) => DecodedOutboxCommand(
            opId: row.envelope.opId,
            envelope: row.envelope,
            rebuildContext: row.rebuildContext,
          ),
        )
        .toList(growable: false);
  }

  @override
  Future<void> recoverInFlightToPending() async {
    operations.add('recoverInFlightToPending');
    for (final row in rows) {
      if (row.status == InMemoryOutboxStatus.inFlight) {
        row.status = InMemoryOutboxStatus.pending;
      }
    }
  }
}

enum InMemoryOutboxStatus { pending, inFlight, acked, failed }

class InMemoryOutboxRow {
  InMemoryOutboxRow({required this.envelope, this.rebuildContext});

  final CommandEnvelope<SyncCommand> envelope;
  final Map<String, dynamic>? rebuildContext;
  InMemoryOutboxStatus status = InMemoryOutboxStatus.pending;
  String? error;
  Duration? retryAfter;
}

class InMemorySyncStateStore implements SyncStateStore {
  final List<String> operations = <String>[];
  SyncCursor cursor;
  SyncEpoch epoch;

  InMemorySyncStateStore({SyncCursor? cursor, SyncEpoch? epoch})
    : cursor = cursor ?? SyncCursor.zero(),
      epoch = epoch ?? SyncEpoch.zero();

  @override
  Future<void> clearAll() async {
    operations.add('clearAll');
    cursor = SyncCursor.zero();
    epoch = SyncEpoch.zero();
  }

  @override
  Future<SyncCursor> readLastServerCursorOrZero() async {
    operations.add('readLastServerCursorOrZero');
    return cursor;
  }

  @override
  Future<SyncEpoch> readLastSyncEpochOrZero() async {
    operations.add('readLastSyncEpochOrZero');
    return epoch;
  }

  @override
  Future<void> writeLastServerCursor(SyncCursor cursor) async {
    operations.add('writeLastServerCursor:${cursor.value}');
    this.cursor = cursor;
  }

  @override
  Future<void> writeLastServerCursorIfAdvanced(SyncCursor candidate) async {
    operations.add('writeLastServerCursorIfAdvanced:${candidate.value}');
    if (candidate > cursor) {
      cursor = candidate;
    }
  }

  @override
  Future<void> writeLastSyncEpoch(SyncEpoch epoch) async {
    operations.add('writeLastSyncEpoch:${epoch.value}');
    this.epoch = epoch;
  }
}

class InMemorySyncRebuildInstructionStore
    implements SyncRebuildInstructionStore {
  final List<String> operations = <String>[];
  RebuildInstructions instructions = RebuildInstructions.empty;
  int clearCount = 0;

  @override
  Future<void> clear() async {
    operations.add('clear');
    clearCount += 1;
    instructions = RebuildInstructions.empty;
  }

  @override
  Future<bool> isEmpty() async => instructions.isEmpty;

  @override
  Future<RebuildInstructions> readAll() async {
    operations.add('readAll');
    return instructions;
  }

  @override
  Future<void> write(RebuildInstruction instruction) async {
    operations.add('write:${instruction.rootEntity.key}');
    instructions = instructions.add(instruction);
  }

  @override
  Future<void> writeMany(Iterable<RebuildInstruction> instructions) async {
    for (final instruction in instructions) {
      await write(instruction);
    }
  }
}

class RecordingSyncConflictLogStore implements SyncConflictLogStore {
  final List<RecordedConflictDecision> decisions = <RecordedConflictDecision>[];

  @override
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
  }) async {
    decisions.add(
      RecordedConflictDecision(
        opId: opId,
        entityTableName: entityTableName,
        decision: decision,
        reason: reason,
      ),
    );
    return decisions.length;
  }

  @override
  Future<void> clear() async {
    decisions.clear();
  }
}

class RecordedConflictDecision {
  const RecordedConflictDecision({
    required this.opId,
    required this.entityTableName,
    required this.decision,
    this.reason,
  });

  final String? opId;
  final String entityTableName;
  final SyncConflictDecision decision;
  final String? reason;
}

class FakeSyncServerTransport implements SyncTransport {
  final List<SyncBatchRequest> requests = <SyncBatchRequest>[];
  final List<String> operations = <String>[];
  SyncBatchResponse Function(SyncBatchRequest request)? respond;
  Object? throwOnPushPull;

  @override
  Future<SyncBatchResponse> pushPull(SyncBatchRequest request) async {
    operations.add('pushPull');
    requests.add(request);
    final error = throwOnPushPull;
    if (error != null) {
      throw error;
    }
    final custom = respond;
    if (custom != null) {
      return custom(request);
    }
    return SyncBatchResponse(
      commandResults: request.commands
          .map(
            (envelope) => SyncCommandResult(
              opId: envelope.opId,
              status: SyncCommandResultStatus.applied,
              latestCursor: request.sinceCursor,
            ),
          )
          .toList(growable: false),
      changes: const <ServerChange>[],
      newCursor: request.sinceCursor,
    );
  }
}

class RecordingTableChangeHandler implements SyncTableChangeHandler {
  RecordingTableChangeHandler({this.tableName = 'items'});

  @override
  final String tableName;
  final List<ServerChange> applied = <ServerChange>[];
  final List<String> operations = <String>[];

  @override
  Future<void> apply(ServerChange change) async {
    operations.add('apply:${change.operation}:${change.rowId}');
    applied.add(change);
  }
}

class RecordingConflictResolver implements ConflictResolver {
  ConflictResolutionPlan Function(ConflictResolutionContext context)?
  planBuilder;
  final List<ConflictResolutionContext> contexts =
      <ConflictResolutionContext>[];

  @override
  Future<ConflictResolutionPlan> resolve(
    ConflictResolutionContext context,
  ) async {
    contexts.add(context);
    return planBuilder?.call(context) ??
        ConflictResolutionPlan(actions: const <CommandResolutionAction>[]);
  }
}

class SequentialOpIdGenerator implements OpIdGenerator {
  int _next = 0;

  @override
  String nextOpId() {
    _next += 1;
    return 'op-$_next';
  }
}

class FixedClock implements UtcClock {
  const FixedClock(this.value);

  final DateTime value;

  @override
  DateTime nowUtc() => value;
}
