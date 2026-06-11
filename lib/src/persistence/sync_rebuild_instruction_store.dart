import '../runtime/rebuild/rebuild_instructions.dart';

/// Persistence contract for rebuild instructions captured during delete apply.
///
/// These instructions are consumed later by [ConflictResolver] when a stale
/// command needs to recreate rows that were deleted on the server.
abstract interface class SyncRebuildInstructionStore {
  /// Persists a single instruction.
  Future<void> write(RebuildInstruction instruction);

  /// Persists multiple instructions in one call.
  Future<void> writeMany(Iterable<RebuildInstruction> instructions);

  /// Reads all persisted instructions.
  Future<RebuildInstructions> readAll();

  /// Removes all persisted instructions.
  Future<void> clear();

  /// Whether the store currently contains no instructions.
  Future<bool> isEmpty();
}
