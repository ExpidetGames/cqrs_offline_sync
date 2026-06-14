import '../runtime/rebuild/rebuild_instructions.dart';
import 'sync_rebuild_instruction_store.dart';

/// No-op [SyncRebuildInstructionStore] that silently discards writes.
///
/// Use this when delete-rebuild support is not required. The store is safe to
/// const-construct and can be used as the default for [SyncStores].
class NoopSyncRebuildInstructionStore implements SyncRebuildInstructionStore {
  /// Creates a no-op rebuild instruction store.
  const NoopSyncRebuildInstructionStore();

  @override
  Future<void> write(RebuildInstruction instruction) async {}

  @override
  Future<void> writeMany(Iterable<RebuildInstruction> instructions) async {}

  @override
  Future<RebuildInstructions> readAll() async => RebuildInstructions.empty;

  @override
  Future<void> clear() async {}

  @override
  Future<bool> isEmpty() async => true;
}
