import '../commands/command_codec_registry.dart';
import '../runtime/change_applier/sync_table_change_handler.dart';
import '../runtime/conflict/stale_conflict_profile.dart';
import '../runtime/rebuild/rebuild_graph.dart';
import 'auth/local_data_scope.dart';

/// Contract that each syncable module must implement to participate in sync.
///
/// The sync runtime collects all registered [SyncModuleRegistration]s and
/// composes their contributions (codecs, handlers, profiles, etc.) into the
/// unified sync pipeline.
///
/// Library users implement this in their module registration file.
abstract class SyncModuleRegistration {
  /// Unique module identifier (e.g. 'vocab_trainer', 'latin_text').
  ///
  /// Used for diagnostics and logging. Must be stable across app versions.
  String get moduleId;

  /// Command codecs for outbox serialization and transport.
  ///
  /// Each codec maps a `commandType` string to a typed payload encode/decode
  /// pair. The sync runtime collects codecs from all modules into a single
  /// [CommandCodecRegistry].
  List<AnyCommandCodec> get commandCodecs;

  /// Table change handlers for pull-side change application.
  ///
  /// Each handler applies server feed changes (`upsert` / `delete`) to one
  /// local table. The composite change applier dispatches changes by table name.
  List<SyncTableChangeHandler> get tableChangeHandlers;

  /// Stale conflict profiles for client-side conflict resolution.
  ///
  /// Each profile encodes domain-specific resolution logic for a particular
  /// command type when the server rejects it as `rejected_conflict_stale`.
  List<StaleConflictProfile> get staleConflictProfiles;

  /// Local data scope for auth reset flows (login/logout/delete account).
  ///
  /// Provides `hasData()` and `clear()` operations scoped to this module's
  /// local tables.
  LocalDataScope get localDataScope;

  /// Rebuild graph defining entity structure for delete-rebuild planning
  /// and snapshot building.
  ///
  /// Nodes describe tables, parent-child relationships, and projections.
  /// Used by the delete-rebuild planner (conflict handling) and the
  /// bootstrap-replace snapshot builder (device-wins auth flow).
  RebuildGraph get rebuildGraph;
}
