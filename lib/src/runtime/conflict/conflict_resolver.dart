import 'conflict_resolution_context.dart';
import 'conflict_resolution_plan.dart';

/// Contract for resolving stale conflicts after a sync batch response.
///
/// The resolver inspects `rejected_conflict_stale` results, looks up the
/// matching [StaleConflictProfile] per command type, and produces a
/// [ConflictResolutionPlan] with per-command actions (ack, requeue, fail).
abstract interface class ConflictResolver {
  /// Resolves stale conflicts from [context] into a plan.
  Future<ConflictResolutionPlan> resolve(ConflictResolutionContext context);
}
