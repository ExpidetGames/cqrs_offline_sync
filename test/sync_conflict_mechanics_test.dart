import 'package:cqrs_offline_sync/cqrs_offline_sync.dart';
import 'package:test/test.dart';

import 'support/sync_test_harness.dart';

void main() {
  group('Sync conflict mechanics', () {
    test(
      'ack action acks the command, logs applyServer, and clears rebuild instructions when settled',
      () async {
        final harness = await _ConflictHarness.create();
        final conflictLog = RecordingSyncConflictLogStore();
        await harness.rebuildStore.write(_instructionFor('items', 'stale-1'));

        harness.transport.respond = (request) =>
            _staleResponse(request, cursor: SyncCursor('9'));
        harness.resolver.planBuilder = (context) {
          expect(context.requeueBaseCursor, SyncCursor('9'));
          expect(context.rebuildInstructions.isEmpty, isFalse);
          return ConflictResolutionPlan(
            actions: <CommandResolutionAction>[
              const AckCommandAction(opId: 'op-1', reason: 'server wins'),
            ],
          );
        };

        await harness
            .runner(conflictLogStore: conflictLog)
            .runOnce(SyncTriggerReason.manual);

        expect(
          harness.outbox.ackedRows.map((row) => row.envelope.opId),
          <String>['op-1'],
        );
        expect(harness.outbox.failedRows, isEmpty);
        expect(
          conflictLog.decisions.single.decision,
          SyncConflictDecision.applyServer,
        );
        expect(conflictLog.decisions.single.reason, 'server wins');
        expect(harness.rebuildStore.clearCount, 1);
      },
    );

    test('fail action marks the command failed with retry metadata', () async {
      final harness = await _ConflictHarness.create();
      harness.transport.respond = (request) =>
          _staleResponse(request, cursor: SyncCursor('5'));
      harness.resolver.planBuilder = (context) => ConflictResolutionPlan(
        actions: <CommandResolutionAction>[
          const FailCommandAction(
            opId: 'op-1',
            error: 'cannot resolve',
            retryAfter: Duration(minutes: 2),
          ),
        ],
      );

      await harness.runner().runOnce(SyncTriggerReason.manual);

      expect(
        harness.outbox.failedRows.map((row) => row.envelope.opId),
        <String>['op-1'],
      );
      expect(harness.outbox.failures.single.error, 'cannot resolve');
      expect(
        harness.outbox.failures.single.retryAfter,
        const Duration(minutes: 2),
      );
      expect(harness.rebuildStore.clearCount, 0);
    });

    test(
      'requeue action acks old command, appends replacement with resolver base cursor, and keeps rebuild instructions',
      () async {
        final harness = await _ConflictHarness.create();
        final conflictLog = RecordingSyncConflictLogStore();
        harness.transport.respond = (request) =>
            _staleResponse(request, cursor: SyncCursor('12'));
        harness.resolver.planBuilder = (context) => ConflictResolutionPlan(
          actions: <CommandResolutionAction>[
            RequeueCommandAction(
              opId: 'op-1',
              baseCursor: context.requeueBaseCursor,
              reason: 'keep local',
              requeuedCommands: const <RequeuedCommand>[
                RequeuedCommand(
                  command: TestCommand(id: 'local-1', value: 'rebased'),
                  rebuildContext: <String, dynamic>{'source': 'test'},
                ),
              ],
            ),
          ],
        );

        await harness
            .runner(conflictLogStore: conflictLog)
            .runOnce(SyncTriggerReason.manual);

        final rows = harness.outbox.rows.toList(growable: false);
        expect(
          rows.map((row) => row.envelope.opId),
          containsAll(<String>['op-1', 'op-2']),
        );
        expect(
          harness.outbox.rowsByOpId['op-1']!.status,
          InMemoryOutboxStatus.acked,
        );
        expect(
          harness.outbox.rowsByOpId['op-2']!.status,
          InMemoryOutboxStatus.pending,
        );
        expect(
          harness.outbox.rowsByOpId['op-2']!.envelope.baseCursor,
          SyncCursor('12'),
        );
        expect(
          harness.outbox.rowsByOpId['op-2']!.rebuildContext,
          <String, dynamic>{'source': 'test'},
        );
        expect(
          conflictLog.decisions.single.decision,
          SyncConflictDecision.keepLocal,
        );
        expect(harness.rebuildStore.clearCount, 0);
      },
    );

    test('missing action fails the command safely', () async {
      final harness = await _ConflictHarness.create();
      harness.transport.respond = (request) =>
          _staleResponse(request, cursor: SyncCursor('6'));
      harness.resolver.planBuilder = (context) =>
          ConflictResolutionPlan(actions: const <CommandResolutionAction>[]);

      await harness.runner().runOnce(SyncTriggerReason.manual);

      expect(
        harness.outbox.failedRows.map((row) => row.envelope.opId),
        <String>['op-1'],
      );
      expect(
        harness.outbox.failures.single.error,
        'Conflict resolution did not return an action for opId=op-1.',
      );
    });

    test('mixed actions are committed in one batch', () async {
      final harness = await _ConflictHarness.create(commandCount: 3);
      harness.transport.respond = (request) => SyncBatchResponse(
        commandResults: request.commands
            .map(
              (envelope) => SyncCommandResult(
                opId: envelope.opId,
                status: SyncCommandResultStatus.rejectedConflictStale,
                latestCursor: SyncCursor('20'),
              ),
            )
            .toList(growable: false),
        changes: const <ServerChange>[],
        newCursor: SyncCursor('20'),
      );
      harness.resolver.planBuilder = (context) => ConflictResolutionPlan(
        actions: <CommandResolutionAction>[
          const AckCommandAction(opId: 'op-1'),
          const FailCommandAction(opId: 'op-2', error: 'no replay'),
          RequeueCommandAction(
            opId: 'op-3',
            baseCursor: context.requeueBaseCursor,
            requeuedCommands: const <RequeuedCommand>[
              RequeuedCommand(command: TestCommand(id: 'replacement')),
            ],
          ),
        ],
      );

      await harness.runner().runOnce(SyncTriggerReason.manual);

      expect(
        harness.outbox.rowsByOpId['op-1']!.status,
        InMemoryOutboxStatus.acked,
      );
      expect(
        harness.outbox.rowsByOpId['op-2']!.status,
        InMemoryOutboxStatus.failed,
      );
      expect(
        harness.outbox.rowsByOpId['op-3']!.status,
        InMemoryOutboxStatus.acked,
      );
      expect(
        harness.outbox.rowsByOpId['op-4']!.status,
        InMemoryOutboxStatus.pending,
      );
      expect(
        harness.outbox.rowsByOpId['op-4']!.envelope.baseCursor,
        SyncCursor('20'),
      );
    });

    test('conflict log is optional', () async {
      final harness = await _ConflictHarness.create();
      harness.transport.respond = (request) =>
          _staleResponse(request, cursor: SyncCursor('7'));
      harness.resolver.planBuilder = (context) => ConflictResolutionPlan(
        actions: <CommandResolutionAction>[
          const AckCommandAction(opId: 'op-1'),
        ],
      );

      await harness.runner().runOnce(SyncTriggerReason.manual);

      expect(
        harness.outbox.rowsByOpId['op-1']!.status,
        InMemoryOutboxStatus.acked,
      );
    });
  });
}

class _ConflictHarness {
  _ConflictHarness({
    required this.outbox,
    required this.state,
    required this.transport,
    required this.handler,
    required this.resolver,
    required this.rebuildStore,
    required this.envelopeFactory,
  });

  final InMemorySyncOutboxStore outbox;
  final InMemorySyncStateStore state;
  final FakeSyncServerTransport transport;
  final RecordingTableChangeHandler handler;
  final RecordingConflictResolver resolver;
  final InMemorySyncRebuildInstructionStore rebuildStore;
  final CommandEnvelopeFactory envelopeFactory;

  static Future<_ConflictHarness> create({int commandCount = 1}) async {
    final outbox = InMemorySyncOutboxStore();
    final envelopeFactory = testEnvelopeFactory();
    for (var index = 1; index <= commandCount; index += 1) {
      await outbox.appendPayload(
        TestCommand(id: 'local-$index'),
        envelopeFactory: envelopeFactory,
      );
    }
    return _ConflictHarness(
      outbox: outbox,
      state: InMemorySyncStateStore(),
      transport: FakeSyncServerTransport(),
      handler: RecordingTableChangeHandler(),
      resolver: RecordingConflictResolver(),
      rebuildStore: InMemorySyncRebuildInstructionStore(),
      envelopeFactory: envelopeFactory,
    );
  }

  SyncRunner runner({RecordingSyncConflictLogStore? conflictLogStore}) {
    return SyncRunner(
      unitOfWork: SyncUnitOfWork(
        transactionRunner: runInMemoryTransaction,
        outboxStore: outbox,
        syncStateStore: state,
        conflictLogStore: conflictLogStore,
        envelopeFactory: envelopeFactory,
      ),
      transport: transport,
      changeApplier: CompositeServerChangeApplier(
        handlers: <SyncTableChangeHandler>[handler],
      ),
      conflictResolver: resolver,
      rebuildInstructionStore: rebuildStore,
    );
  }
}

SyncBatchResponse _staleResponse(
  SyncBatchRequest request, {
  required SyncCursor cursor,
}) {
  return SyncBatchResponse(
    commandResults: request.commands
        .map(
          (envelope) => SyncCommandResult(
            opId: envelope.opId,
            status: SyncCommandResultStatus.rejectedConflictStale,
            latestCursor: cursor,
          ),
        )
        .toList(growable: false),
    changes: const <ServerChange>[],
    newCursor: cursor,
  );
}

RebuildInstruction _instructionFor(String tableName, String rowId) {
  final entity = RebuildEntityRef(tableName: tableName, rowId: rowId);
  return RebuildInstruction(
    rootEntity: entity,
    coveredEntities: <RebuildEntityRef>[entity],
    commands: const <RequeuedCommand>[
      RequeuedCommand(command: TestCommand(id: 'rebuilt')),
    ],
  );
}
