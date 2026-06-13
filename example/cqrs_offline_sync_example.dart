import 'package:cqrs_offline_sync/cqrs_offline_sync.dart';

Future<void> main() async {
  final notesStore = InMemoryNotesStore();
  final outboxStore = InMemoryOutboxStore();
  final stateStore = InMemorySyncStateStore();
  final server = InMemoryNotesServer();
  final triggerSink = RecordingTriggerSink();

  final registry = CommandCodecRegistry(<AnyCommandCodec>[
    createNoteCommandCodec,
  ]);
  final envelopeFactory = CommandEnvelopeFactory(
    codecRegistry: registry,
    opIdGenerator: SequentialOpIdGenerator(),
    clock: FixedClock(DateTime.utc(2026, 1, 1)),
  );
  final commandWriter = PersistentSyncCommandWriter(
    stateStore: stateStore,
    outboxStore: outboxStore,
    envelopeFactory: envelopeFactory,
  );
  final writeUnitOfWork = SyncWriteUnitOfWork(
    transactionRunner: runInMemoryTransaction,
    commandWriter: commandWriter,
    triggerSink: triggerSink,
  );
  final runner = SyncRunner(
    unitOfWork: SyncUnitOfWork(
      transactionRunner: runInMemoryTransaction,
      outboxStore: outboxStore,
      syncStateStore: stateStore,
      envelopeFactory: envelopeFactory,
    ),
    transport: server,
    changeApplier: CompositeServerChangeApplier(
      handlers: <SyncTableChangeHandler>[NotesTableChangeHandler(notesStore)],
    ),
  );

  print('Local write: create note n1');
  await writeUnitOfWork.runVoidWithCommand(
    writeLocal: () => notesStore.upsert(const Note(id: 'n1', text: 'Salve')),
    command: const CreateNoteCommand(id: 'n1', text: 'Salve'),
  );

  print('Outbox rows before sync: ${outboxStore.pendingCount}');
  print(
    'Sync triggers: ${triggerSink.reasons.map((reason) => reason.name).join(', ')}',
  );

  server.queueRemoteNote(const Note(id: 'n2', text: 'Remote hello'));

  print('Run sync');
  await runner.runOnce(SyncTriggerReason.localWriteCommitted);

  print('Outbox rows after sync: ${outboxStore.unsettledCount}');
  print(
    'Last cursor: ${(await stateStore.readLastServerCursorOrZero()).value}',
  );
  print('Local notes: ${notesStore.describe()}');
}

Future<T> runInMemoryTransaction<T>(Future<T> Function() action) {
  return action();
}

class Note {
  const Note({required this.id, required this.text});

  final String id;
  final String text;

  Map<String, dynamic> toJson() => <String, dynamic>{'id': id, 'text': text};

  static Note fromJson(Map<String, dynamic> json) {
    return Note(id: json['id'] as String, text: json['text'] as String);
  }
}

class CreateNoteCommand implements SyncCommand {
  const CreateNoteCommand({required this.id, required this.text});

  static const String type = 'notes.create';
  static const String aggregate = 'notes.note';

  final String id;
  final String text;

  @override
  String get commandType => type;

  @override
  String get aggregateType => aggregate;

  Map<String, dynamic> toJson() => <String, dynamic>{'id': id, 'text': text};

  static CreateNoteCommand fromJson(Map<String, dynamic> json) {
    return CreateNoteCommand(
      id: json['id'] as String,
      text: json['text'] as String,
    );
  }
}

final CommandPayloadCodec<CreateNoteCommand> createNoteCommandCodec =
    CommandPayloadCodec<CreateNoteCommand>(
      commandType: CreateNoteCommand.type,
      aggregateType: CreateNoteCommand.aggregate,
      payloadType: CreateNoteCommand,
      fromJson: CreateNoteCommand.fromJson,
      toJson: (CreateNoteCommand command) => command.toJson(),
    );

class InMemoryNotesStore {
  final Map<String, Note> _notesById = <String, Note>{};

  Future<void> upsert(Note note) async {
    _notesById[note.id] = note;
  }

  Future<void> delete(String id) async {
    _notesById.remove(id);
  }

  String describe() {
    final notes = _notesById.values.toList()
      ..sort((left, right) => left.id.compareTo(right.id));
    return notes.map((note) => '${note.id}=${note.text}').join(', ');
  }
}

class NotesTableChangeHandler implements SyncTableChangeHandler {
  NotesTableChangeHandler(this._store);

  final InMemoryNotesStore _store;

  @override
  String get tableName => 'notes';

  @override
  Future<void> apply(ServerChange change) async {
    switch (change) {
      case UpsertServerChange():
        await _store.upsert(Note.fromJson(change.row));
      case DeleteServerChange():
        await _store.delete(change.rowId);
    }
  }
}

class InMemoryNotesServer implements SyncTransport {
  final Map<String, Note> _notesById = <String, Note>{};
  final List<ServerChange> _feed = <ServerChange>[];
  int _cursor = 0;

  void queueRemoteNote(Note note) {
    _notesById[note.id] = note;
    _feed.add(
      ServerChange.upsert(
        cursor: _nextCursor(),
        table: 'notes',
        rowId: note.id,
        row: note.toJson(),
      ),
    );
  }

  @override
  Future<SyncBatchResponse> pushPull(SyncBatchRequest request) async {
    final results = <SyncCommandResult>[];

    for (final envelope in request.commands) {
      final payload = envelope.payload;
      if (payload is CreateNoteCommand) {
        final note = Note(id: payload.id, text: payload.text);
        _notesById[note.id] = note;
        final cursor = _nextCursor();
        _feed.add(
          ServerChange.upsert(
            cursor: cursor,
            table: 'notes',
            rowId: note.id,
            row: note.toJson(),
            originOpId: envelope.opId,
          ),
        );
        results.add(
          SyncCommandResult(
            opId: envelope.opId,
            status: SyncCommandResultStatus.applied,
            latestCursor: cursor,
          ),
        );
      } else {
        results.add(
          SyncCommandResult(
            opId: envelope.opId,
            status: SyncCommandResultStatus.rejectedInvalid,
            latestCursor: SyncCursor(_cursor.toString()),
            reason: 'Unsupported command: ${envelope.commandType}',
          ),
        );
      }
    }

    final changes = request.includePull
        ? _feed
              .where((change) => change.cursor > request.sinceCursor)
              .take(request.pullLimit)
              .toList(growable: false)
        : const <ServerChange>[];
    final newCursor = changes.isEmpty && results.isEmpty
        ? request.sinceCursor
        : SyncCursor(_cursor.toString());

    return SyncBatchResponse(
      commandResults: results,
      changes: changes,
      newCursor: newCursor,
      hasMore: false,
    );
  }

  SyncCursor _nextCursor() {
    _cursor += 1;
    return SyncCursor(_cursor.toString());
  }
}

class InMemoryOutboxStore implements SyncOutboxStore {
  final Map<String, _OutboxRow> _rowsByOpId = <String, _OutboxRow>{};

  int get pendingCount => _rowsByOpId.values
      .where((row) => row.status == _OutboxStatus.pending)
      .length;
  int get unsettledCount => _rowsByOpId.values
      .where((row) => row.status != _OutboxStatus.acked)
      .length;

  @override
  Future<void> append(
    CommandEnvelope<SyncCommand> envelope, {
    Map<String, dynamic>? rebuildContext,
  }) async {
    _rowsByOpId[envelope.opId] = _OutboxRow(
      envelope: envelope,
      rebuildContext: rebuildContext,
    );
  }

  @override
  Future<void> clear() async {
    _rowsByOpId.clear();
  }

  @override
  Future<bool> hasUnsettledCommands() async => unsettledCount > 0;

  @override
  Future<void> markAcked(Iterable<String> opIds) async {
    for (final opId in opIds) {
      _rowsByOpId[opId]?.status = _OutboxStatus.acked;
    }
  }

  @override
  Future<void> markInFlight(Iterable<String> opIds) async {
    for (final opId in opIds) {
      _rowsByOpId[opId]?.status = _OutboxStatus.inFlight;
    }
  }

  @override
  Future<void> markManyFailed(Iterable<OutboxFailureUpdate> failures) async {
    for (final failure in failures) {
      final row = _rowsByOpId[failure.opId];
      if (row != null) {
        row.status = _OutboxStatus.failed;
        row.error = failure.error;
      }
    }
  }

  @override
  Future<List<DecodedOutboxCommand>> nextPending({int limit = 100}) async {
    return _rowsByOpId.values
        .where(
          (row) =>
              row.status == _OutboxStatus.pending ||
              row.status == _OutboxStatus.failed,
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
    for (final row in _rowsByOpId.values) {
      if (row.status == _OutboxStatus.inFlight) {
        row.status = _OutboxStatus.pending;
      }
    }
  }
}

enum _OutboxStatus { pending, inFlight, acked, failed }

class _OutboxRow {
  _OutboxRow({required this.envelope, this.rebuildContext});

  final CommandEnvelope<SyncCommand> envelope;
  final Map<String, dynamic>? rebuildContext;
  _OutboxStatus status = _OutboxStatus.pending;
  String? error;
}

class InMemorySyncStateStore implements SyncStateStore {
  SyncCursor _cursor = SyncCursor.zero();
  SyncEpoch _epoch = SyncEpoch.zero();

  @override
  Future<void> clearAll() async {
    _cursor = SyncCursor.zero();
    _epoch = SyncEpoch.zero();
  }

  @override
  Future<SyncCursor> readLastServerCursorOrZero() async => _cursor;

  @override
  Future<SyncEpoch> readLastSyncEpochOrZero() async => _epoch;

  @override
  Future<void> writeLastServerCursor(SyncCursor cursor) async {
    _cursor = cursor;
  }

  @override
  Future<void> writeLastServerCursorIfAdvanced(SyncCursor candidate) async {
    if (candidate > _cursor) {
      _cursor = candidate;
    }
  }

  @override
  Future<void> writeLastSyncEpoch(SyncEpoch epoch) async {
    _epoch = epoch;
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

class RecordingTriggerSink implements SyncTriggerSink {
  final List<SyncTriggerReason> reasons = <SyncTriggerReason>[];

  @override
  void requestSync({required SyncTriggerReason reason}) {
    reasons.add(reason);
  }
}
