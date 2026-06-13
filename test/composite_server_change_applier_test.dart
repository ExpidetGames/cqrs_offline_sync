import 'package:cqrs_offline_sync/cqrs_offline_sync.dart';
import 'package:test/test.dart';

import 'support/sync_test_harness.dart';

void main() {
  group('CompositeServerChangeApplier', () {
    test('dispatches changes by table name in cursor order', () async {
      final items = RecordingTableChangeHandler(tableName: 'items');
      final notes = RecordingTableChangeHandler(tableName: 'notes');
      final applier = CompositeServerChangeApplier(
        handlers: <SyncTableChangeHandler>[items, notes],
      );

      await applier.apply(<ServerChange>[
        ServerChange.upsert(
          cursor: SyncCursor('3'),
          table: 'notes',
          rowId: 'n1',
          row: const <String, dynamic>{},
        ),
        ServerChange.upsert(
          cursor: SyncCursor('1'),
          table: 'items',
          rowId: 'i1',
          row: const <String, dynamic>{},
        ),
        ServerChange.delete(
          cursor: SyncCursor('2'),
          table: 'items',
          rowId: 'i2',
        ),
      ]);

      expect(items.applied.map((change) => change.rowId), <String>['i1', 'i2']);
      expect(notes.applied.map((change) => change.rowId), <String>['n1']);
    });

    test('rejects duplicate handlers for a table', () {
      expect(
        () => CompositeServerChangeApplier(
          handlers: <SyncTableChangeHandler>[
            RecordingTableChangeHandler(tableName: 'items'),
            RecordingTableChangeHandler(tableName: 'items'),
          ],
        ),
        throwsStateError,
      );
    });

    test('throws when no handler is registered for a change table', () async {
      final applier = CompositeServerChangeApplier(
        handlers: <SyncTableChangeHandler>[
          RecordingTableChangeHandler(tableName: 'items'),
        ],
      );

      await expectLater(
        applier.apply(<ServerChange>[
          ServerChange.upsert(
            cursor: SyncCursor('1'),
            table: 'unknown',
            rowId: 'u1',
            row: const <String, dynamic>{},
          ),
        ]),
        throwsUnsupportedError,
      );
    });

    test(
      'drops upserts superseded by later deletes for the same row',
      () async {
        final handler = RecordingTableChangeHandler(tableName: 'items');
        final applier = CompositeServerChangeApplier(
          handlers: <SyncTableChangeHandler>[handler],
        );

        await applier.apply(<ServerChange>[
          ServerChange.upsert(
            cursor: SyncCursor('1'),
            table: 'items',
            rowId: 'i1',
            row: const <String, dynamic>{'version': 1},
          ),
          ServerChange.upsert(
            cursor: SyncCursor('2'),
            table: 'items',
            rowId: 'i2',
            row: const <String, dynamic>{'version': 1},
          ),
          ServerChange.delete(
            cursor: SyncCursor('3'),
            table: 'items',
            rowId: 'i1',
          ),
        ]);

        expect(
          handler.applied.map(
            (change) => '${change.operation}:${change.rowId}',
          ),
          <String>['upsert:i2', 'delete:i1'],
        );
      },
    );

    test('persists rebuild instructions before applying deletes', () async {
      final handler = RecordingTableChangeHandler(tableName: 'items');
      final rebuildStore = InMemorySyncRebuildInstructionStore();
      final applier = CompositeServerChangeApplier(
        handlers: <SyncTableChangeHandler>[handler],
        deleteRebuildPlanner: GraphDeleteRebuildPlanner(
          graph: _singleItemGraph(),
        ),
        rebuildInstructionStore: rebuildStore,
      );

      await applier.apply(<ServerChange>[
        ServerChange.delete(
          cursor: SyncCursor('1'),
          table: 'items',
          rowId: 'i1',
        ),
      ]);

      final instruction = rebuildStore.instructions.findForTableRow(
        tableName: 'items',
        rowId: 'i1',
      );
      expect(instruction, isNotNull);
      expect(instruction!.commands.single.command, isA<TestCommand>());
      expect(rebuildStore.operations, <String>['write:items::i1']);
      expect(handler.applied.map((change) => change.rowId), <String>['i1']);
    });
  });
}

RebuildGraph _singleItemGraph() {
  const row = _ItemRow(id: 'i1');
  return RebuildGraph(
    nodes: <AnyRebuildGraphNode>[
      RebuildGraphNode<_ItemRow>(
        tableName: 'items',
        loadById: (rowId) async => rowId == row.id ? row : null,
        loadAll: () async => const <_ItemRow>[row],
        toEntityRef: (row) =>
            RebuildEntityRef(tableName: 'items', rowId: row.id),
        toCreateCommand: (row) =>
            RequeuedCommand(command: TestCommand(id: row.id)),
        toSnapshot: (row) => <String, dynamic>{'id': row.id},
      ),
    ],
  );
}

class _ItemRow {
  const _ItemRow({required this.id});

  final String id;
}
