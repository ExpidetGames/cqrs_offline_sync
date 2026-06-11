import 'rebuild_instructions.dart';

/// Contract for planning how to recreate a row (and its subtree) after a
/// server-side delete.
///
/// Called by [CompositeServerChangeApplier] during the first pass of change
/// application, before local rows are actually removed.
abstract interface class DeleteRebuildPlanner {
  /// Returns a [RebuildInstruction] for the deleted row, or `null` if no
  /// rebuild is needed or possible.
  Future<RebuildInstruction?> planForDelete({
    required String tableName,
    required String rowId,
  });
}

/// A planner that never produces instructions.
class NoopDeleteRebuildPlanner implements DeleteRebuildPlanner {
  /// Creates a const noop planner.
  const NoopDeleteRebuildPlanner();

  @override
  Future<RebuildInstruction?> planForDelete({
    required String tableName,
    required String rowId,
  }) async {
    return null;
  }
}
