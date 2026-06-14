import 'package:cqrs_offline_sync/cqrs_offline_sync.dart';
import 'package:test/test.dart';

void main() {
  group('SyncBootstrapReplaceService', () {
    test('builds snapshot and persists cursor/epoch', () async {
      final state = _InMemoryStateStore();
      final client = _FakeClient();
      final graph = RebuildGraph(
        nodes: [
          _Node(tableName: 'parents'),
          _Node(tableName: 'children'),
        ],
        edges: [
          RebuildGraphEdge<Object, Object>(
            parentTableName: 'parents',
            childTableName: 'children',
            loadChildren: (_) async => [],
          ),
        ],
      );

      final service = SyncBootstrapReplaceService(
        client: client,
        stateStore: state,
        rebuildGraph: graph,
      );

      final response = await service.replaceServerWithLocalSnapshot(
        expectedSyncEpoch: SyncEpoch('3'),
        confirmationToken: 'token-1',
      );

      expect(response.newCursor, SyncCursor('100'));
      expect(response.newSyncEpoch, SyncEpoch('4'));
      expect(state.cursor, SyncCursor('100'));
      expect(state.epoch, SyncEpoch('4'));

      final request = client.lastRequest!;
      expect(request.expectedSyncEpoch, SyncEpoch('3'));
      expect(request.confirmationToken, 'token-1');
      expect(request.snapshot.tables.length, 2);
      expect(request.snapshot.tables.first.tableName, 'parents');
      expect(request.snapshot.tables.last.tableName, 'children');
    });

    test('skips empty tables', () async {
      final state = _InMemoryStateStore();
      final client = _FakeClient();
      final graph = RebuildGraph(
        nodes: [
          _Node(tableName: 'empty', rows: []),
          _Node(tableName: 'full', rows: [_Row('r1')]),
        ],
      );

      final service = SyncBootstrapReplaceService(
        client: client,
        stateStore: state,
        rebuildGraph: graph,
      );

      await service.replaceServerWithLocalSnapshot(
        expectedSyncEpoch: SyncEpoch('0'),
        confirmationToken: 'token',
      );

      expect(client.lastRequest!.snapshot.tables.length, 1);
      expect(client.lastRequest!.snapshot.tables.single.tableName, 'full');
    });
  });
}

class _Row {
  const _Row(this.id);
  final String id;
}

class _Node implements AnyRebuildGraphNode {
  _Node({
    required this.tableName,
    this.rows = const [_Row('p1'), _Row('p2')],
  });

  @override
  final String tableName;
  final List<Object> rows;

  @override
  Future<Object?> loadById(String rowId) async => null;

  @override
  Future<List<Object>> loadAll() async => rows;

  @override
  RebuildEntityRef toEntityRef(Object row) =>
      RebuildEntityRef(tableName: tableName, rowId: (row as _Row).id);

  @override
  RequeuedCommand toCreateCommand(Object row) =>
      RequeuedCommand(command: const _DummyCommand());

  @override
  Map<String, dynamic> toSnapshot(Object row) =>
      <String, dynamic>{'id': (row as _Row).id};

  @override
  RebuildGraphParentRef? parentOf(Object row) => null;
}

class _DummyCommand implements SyncCommand {
  const _DummyCommand();

  @override
  String get commandType => 'dummy.create';

  @override
  String get aggregateType => 'dummy';
}

class _InMemoryStateStore implements SyncStateStore {
  SyncCursor cursor = SyncCursor('0');
  SyncEpoch epoch = SyncEpoch('0');

  @override
  Future<SyncCursor> readLastServerCursorOrZero() async => cursor;

  @override
  Future<void> writeLastServerCursorIfAdvanced(SyncCursor candidate) async {
    if (candidate > cursor) {
      cursor = candidate;
    }
  }

  @override
  Future<SyncEpoch> readLastSyncEpochOrZero() async => epoch;

  @override
  Future<void> writeLastSyncEpoch(SyncEpoch epoch) async {
    this.epoch = epoch;
  }

  @override
  Future<void> writeLastServerCursor(SyncCursor cursor) async {
    this.cursor = cursor;
  }

  @override
  Future<void> clearAll() async {
    cursor = SyncCursor('0');
    epoch = SyncEpoch('0');
  }
}

class _FakeClient implements SyncBootstrapReplaceClient {
  SyncBootstrapReplaceRequest? lastRequest;

  @override
  Future<SyncBootstrapReplaceResponse> replace(SyncBootstrapReplaceRequest request) async {
    lastRequest = request;
    return SyncBootstrapReplaceResponse(
      newCursor: SyncCursor('100'),
      newSyncEpoch: SyncEpoch('4'),
    );
  }
}
