import 'package:cqrs_offline_sync/cqrs_offline_sync.dart';
import 'package:test/test.dart';

void main() {
  group('NoopSyncConflictLogStore', () {
    test('logDecision returns 0 and clear is no-op', () async {
      const store = NoopSyncConflictLogStore();

      expect(
        await store.logDecision(
          opId: 'op-1',
          entityTableName: 'sync_outbox',
          decision: SyncConflictDecision.applyServer,
        ),
        0,
      );

      await store.clear();
    });
  });

  group('NoopSyncRebuildInstructionStore', () {
    test('discards writes, returns empty instructions, is empty', () async {
      const store = NoopSyncRebuildInstructionStore();

      final empty = await store.readAll();
      expect(empty.asIterable, isEmpty);
      expect(await store.isEmpty(), isTrue);

      await store.write(
        RebuildInstruction(
          rootEntity: const RebuildEntityRef(tableName: 't', rowId: 'r'),
          coveredEntities: const [RebuildEntityRef(tableName: 't', rowId: 'r')],
          commands: const [],
        ),
      );
      await store.writeMany([
        RebuildInstruction(
          rootEntity: const RebuildEntityRef(tableName: 't2', rowId: 'r2'),
          coveredEntities: const [RebuildEntityRef(tableName: 't2', rowId: 'r2')],
          commands: const [],
        ),
      ]);

      final afterWrites = await store.readAll();
      expect(afterWrites.asIterable, isEmpty);
      expect(await store.isEmpty(), isTrue);

      await store.clear();
      expect(await store.isEmpty(), isTrue);
    });
  });
}
