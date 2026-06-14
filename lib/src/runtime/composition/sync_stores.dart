import '../../persistence/noop_sync_conflict_log_store.dart';
import '../../persistence/noop_sync_rebuild_instruction_store.dart';
import '../../persistence/sync_conflict_log_store.dart';
import '../../persistence/sync_outbox_store.dart';
import '../../persistence/sync_rebuild_instruction_store.dart';
import '../../persistence/sync_state_store.dart';

/// Immutable collection of sync persistence stores.
///
/// Required stores ([outbox], [state]) must be provided by the host app.
/// Optional stores ([conflictLog], [rebuildInstructions]) default to no-op
/// implementations so callers never have to pass `null`.
class SyncStores {
  /// Creates a store collection.
  const SyncStores({
    required this.outbox,
    required this.state,
    this.conflictLog = const NoopSyncConflictLogStore(),
    this.rebuildInstructions = const NoopSyncRebuildInstructionStore(),
  });

  /// Outbox store for pending, in-flight, and failed commands.
  final SyncOutboxStore outbox;

  /// State store for cursor and epoch.
  final SyncStateStore state;

  /// Conflict decision log store. Defaults to a no-op implementation.
  final SyncConflictLogStore conflictLog;

  /// Rebuild instruction store used by delete-rebuild and conflict recovery.
  /// Defaults to a no-op implementation.
  final SyncRebuildInstructionStore rebuildInstructions;
}
