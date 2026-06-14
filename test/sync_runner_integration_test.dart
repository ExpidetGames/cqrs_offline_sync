import 'package:cqrs_offline_sync/cqrs_offline_sync.dart';
import 'package:test/test.dart';

import 'support/sync_test_harness.dart';

void main() {
  group('SyncRunner integration', () {
    test(
      'reserves pending commands before transport and acks applied results',
      () async {
        final outbox = InMemorySyncOutboxStore();
        final state = InMemorySyncStateStore();
        final transport = FakeSyncServerTransport();
        final handler = RecordingTableChangeHandler();
        final envelopeFactory = testEnvelopeFactory();

        await outbox.appendPayload(
          const TestCommand(id: 'local-1'),
          envelopeFactory: envelopeFactory,
        );

        transport.respond = (request) {
          expect(outbox.inFlightRows.map((row) => row.envelope.opId), <String>[
            'op-1',
          ]);
          return SyncBatchResponse(
            commandResults: <SyncCommandResult>[
              SyncCommandResult(
                opId: 'op-1',
                status: SyncCommandResultStatus.applied,
                latestCursor: SyncCursor('5'),
              ),
            ],
            changes: const <ServerChange>[],
            newCursor: SyncCursor('5'),
          );
        };

        final runner = _runner(
          outbox: outbox,
          state: state,
          transport: transport,
          handler: handler,
          envelopeFactory: envelopeFactory,
        );

        await runner.runOnce(SyncTriggerReason.manual);

        expect(transport.requests, hasLength(1));
        expect(transport.requests.single.commands.single.opId, 'op-1');
        expect(outbox.ackedRows.map((row) => row.envelope.opId), <String>[
          'op-1',
        ]);
        expect(state.cursor, SyncCursor('5'));
        expect(outbox.operations.take(3), <String>[
          'append:op-1:0',
          'recoverInFlightToPending',
          'nextPending:100',
        ]);
        expect(outbox.operations, contains('markInFlight:op-1'));
        expect(outbox.operations, contains('markAcked:op-1'));
      },
    );

    test('applies server changes before committing command results', () async {
      final outbox = InMemorySyncOutboxStore();
      final state = InMemorySyncStateStore();
      final transport = FakeSyncServerTransport();
      final handler = RecordingTableChangeHandler();
      final envelopeFactory = testEnvelopeFactory();
      final events = <String>[];

      await outbox.appendPayload(
        const TestCommand(id: 'local-1'),
        envelopeFactory: envelopeFactory,
      );
      transport.respond = (request) => SyncBatchResponse(
        commandResults: <SyncCommandResult>[
          SyncCommandResult(
            opId: 'op-1',
            status: SyncCommandResultStatus.applied,
            latestCursor: SyncCursor('2'),
          ),
        ],
        changes: <ServerChange>[
          ServerChange.upsert(
            cursor: SyncCursor('2'),
            table: 'items',
            rowId: 'server-1',
            row: const <String, dynamic>{'id': 'server-1'},
          ),
        ],
        newCursor: SyncCursor('2'),
      );

      final runner = SyncRunner(
        unitOfWork: SyncUnitOfWork(
          transactionRunner: <T>(action) async {
            events.add('transaction');
            return action();
          },
          outboxStore: _EventingOutboxStore(outbox, events),
          syncStateStore: state,
          envelopeFactory: envelopeFactory,
        ),
        transport: transport,
        changeApplier: CompositeServerChangeApplier(
          handlers: <SyncTableChangeHandler>[_EventingHandler(handler, events)],
        ),
      );

      await runner.runOnce(SyncTriggerReason.manual);

      expect(handler.applied.map((change) => change.rowId), <String>[
        'server-1',
      ]);
      expect(
        events.indexOf('apply:server-1'),
        lessThan(events.indexOf('markAcked:op-1')),
      );
    });

    test('marks in-flight commands failed when transport throws', () async {
      final outbox = InMemorySyncOutboxStore();
      final state = InMemorySyncStateStore(cursor: SyncCursor('3'));
      final transport = FakeSyncServerTransport()
        ..throwOnPushPull = StateError('network down');
      final handler = RecordingTableChangeHandler();
      final envelopeFactory = testEnvelopeFactory();

      await outbox.appendPayload(
        const TestCommand(id: 'local-1'),
        envelopeFactory: envelopeFactory,
        baseCursor: SyncCursor('3'),
      );

      await _runner(
        outbox: outbox,
        state: state,
        transport: transport,
        handler: handler,
        envelopeFactory: envelopeFactory,
      ).runOnce(SyncTriggerReason.manual);

      expect(outbox.failedRows.map((row) => row.envelope.opId), <String>[
        'op-1',
      ]);
      expect(outbox.failures.single.error, contains('network down'));
      expect(state.cursor, SyncCursor('3'));
      expect(handler.applied, isEmpty);
    });

    test('paginates while response signals hasMore', () async {
      final outbox = InMemorySyncOutboxStore();
      final state = InMemorySyncStateStore();
      final transport = FakeSyncServerTransport();
      final handler = RecordingTableChangeHandler();
      final envelopeFactory = testEnvelopeFactory();

      await outbox.appendPayload(
        const TestCommand(id: 'local-1'),
        envelopeFactory: envelopeFactory,
      );

      transport.respond = (request) {
        if (request.sinceCursor == SyncCursor('0')) {
          return SyncBatchResponse(
            commandResults: <SyncCommandResult>[
              SyncCommandResult(
                opId: 'op-1',
                status: SyncCommandResultStatus.applied,
                latestCursor: SyncCursor('5'),
              ),
            ],
            changes: const <ServerChange>[],
            newCursor: SyncCursor('5'),
            hasMore: true,
          );
        }

        return SyncBatchResponse(
          commandResults: const <SyncCommandResult>[],
          changes: const <ServerChange>[],
          newCursor: SyncCursor('10'),
        );
      };

      await _runner(
        outbox: outbox,
        state: state,
        transport: transport,
        handler: handler,
        envelopeFactory: envelopeFactory,
      ).runOnce(SyncTriggerReason.manual);

      expect(transport.requests, hasLength(2));
      expect(transport.requests.first.sinceCursor, SyncCursor('0'));
      expect(transport.requests.last.sinceCursor, SyncCursor('5'));
      expect(state.cursor, SyncCursor('10'));
      expect(outbox.ackedRows.map((row) => row.envelope.opId), <String>['op-1']);
    });

    test(
      'recovers abandoned in-flight rows before selecting the next batch',
      () async {
        final outbox = InMemorySyncOutboxStore();
        final state = InMemorySyncStateStore();
        final transport = FakeSyncServerTransport();
        final handler = RecordingTableChangeHandler();
        final envelopeFactory = testEnvelopeFactory();

        await outbox.appendPayload(
          const TestCommand(id: 'local-1'),
          envelopeFactory: envelopeFactory,
        );
        await outbox.markInFlight(<String>['op-1']);
        outbox.operations.clear();

        transport.respond = (request) => SyncBatchResponse(
          commandResults: <SyncCommandResult>[
            SyncCommandResult(
              opId: 'op-1',
              status: SyncCommandResultStatus.applied,
              latestCursor: SyncCursor('1'),
            ),
          ],
          changes: const <ServerChange>[],
          newCursor: SyncCursor('1'),
        );

        await _runner(
          outbox: outbox,
          state: state,
          transport: transport,
          handler: handler,
          envelopeFactory: envelopeFactory,
        ).runOnce(SyncTriggerReason.manual);

        expect(outbox.operations.take(2), <String>[
          'recoverInFlightToPending',
          'nextPending:100',
        ]);
        expect(outbox.ackedRows.map((row) => row.envelope.opId), <String>[
          'op-1',
        ]);
      },
    );

    test('cursor writes are monotonic through commit success', () async {
      final outbox = InMemorySyncOutboxStore();
      final state = InMemorySyncStateStore(cursor: SyncCursor('10'));
      final transport = FakeSyncServerTransport();
      final handler = RecordingTableChangeHandler();
      final envelopeFactory = testEnvelopeFactory();

      await outbox.appendPayload(
        const TestCommand(id: 'local-1'),
        envelopeFactory: envelopeFactory,
        baseCursor: SyncCursor('10'),
      );
      transport.respond = (request) => SyncBatchResponse(
        commandResults: <SyncCommandResult>[
          SyncCommandResult(
            opId: 'op-1',
            status: SyncCommandResultStatus.applied,
            latestCursor: SyncCursor('8'),
          ),
        ],
        changes: const <ServerChange>[],
        newCursor: SyncCursor('8'),
      );

      await _runner(
        outbox: outbox,
        state: state,
        transport: transport,
        handler: handler,
        envelopeFactory: envelopeFactory,
      ).runOnce(SyncTriggerReason.manual);

      expect(state.cursor, SyncCursor('10'));
      expect(state.operations, contains('writeLastServerCursorIfAdvanced:8'));
    });

    test(
      'missing command result fails the command instead of acking it',
      () async {
        final outbox = InMemorySyncOutboxStore();
        final state = InMemorySyncStateStore();
        final transport = FakeSyncServerTransport();
        final handler = RecordingTableChangeHandler();
        final envelopeFactory = testEnvelopeFactory();

        await outbox.appendPayload(
          const TestCommand(id: 'local-1'),
          envelopeFactory: envelopeFactory,
        );
        transport.respond = (request) => SyncBatchResponse(
          commandResults: const <SyncCommandResult>[],
          changes: const <ServerChange>[],
          newCursor: SyncCursor('1'),
        );

        await _runner(
          outbox: outbox,
          state: state,
          transport: transport,
          handler: handler,
          envelopeFactory: envelopeFactory,
        ).runOnce(SyncTriggerReason.manual);

        expect(outbox.failedRows.map((row) => row.envelope.opId), <String>[
          'op-1',
        ]);
        expect(
          outbox.failures.single.error,
          'Missing command result in sync response.',
        );
        expect(state.cursor, SyncCursor('1'));
      },
    );
  });
}

SyncRunner _runner({
  required InMemorySyncOutboxStore outbox,
  required InMemorySyncStateStore state,
  required FakeSyncServerTransport transport,
  required RecordingTableChangeHandler handler,
  required CommandEnvelopeFactory envelopeFactory,
}) {
  return SyncRunner(
    unitOfWork: SyncUnitOfWork(
      transactionRunner: runInMemoryTransaction,
      outboxStore: outbox,
      syncStateStore: state,
      envelopeFactory: envelopeFactory,
    ),
    transport: transport,
    changeApplier: CompositeServerChangeApplier(
      handlers: <SyncTableChangeHandler>[handler],
    ),
  );
}

class _EventingOutboxStore implements SyncOutboxStore {
  _EventingOutboxStore(this.delegate, this.events);

  final InMemorySyncOutboxStore delegate;
  final List<String> events;

  @override
  Future<void> append(
    CommandEnvelope<SyncCommand> envelope, {
    Map<String, dynamic>? rebuildContext,
  }) => delegate.append(envelope, rebuildContext: rebuildContext);

  @override
  Future<void> clear() => delegate.clear();

  @override
  Future<bool> hasUnsettledCommands() => delegate.hasUnsettledCommands();

  @override
  Future<void> markAcked(Iterable<String> opIds) {
    final ids = opIds.toList(growable: false);
    events.add('markAcked:${ids.join(',')}');
    return delegate.markAcked(ids);
  }

  @override
  Future<void> markInFlight(Iterable<String> opIds) =>
      delegate.markInFlight(opIds);

  @override
  Future<void> markManyFailed(Iterable<OutboxFailureUpdate> failures) =>
      delegate.markManyFailed(failures);

  @override
  Future<List<DecodedOutboxCommand>> nextPending({int limit = 100}) =>
      delegate.nextPending(limit: limit);

  @override
  Future<void> recoverInFlightToPending() =>
      delegate.recoverInFlightToPending();
}

class _EventingHandler implements SyncTableChangeHandler {
  _EventingHandler(this.delegate, this.events);

  final RecordingTableChangeHandler delegate;
  final List<String> events;

  @override
  String get tableName => delegate.tableName;

  @override
  Future<void> apply(ServerChange change) async {
    events.add('apply:${change.rowId}');
    await delegate.apply(change);
  }
}
