import '../../protocol/server_change.dart';
import '../../persistence/sync_rebuild_instruction_store.dart';
import '../rebuild/delete_rebuild_planner.dart';
import '../rebuild/rebuild_instructions.dart';
import '../rebuild/server_change_applier.dart';
import 'server_change_decision_policy.dart';
import 'sync_table_change_handler.dart';

/// Module-agnostic server change applier that dispatches changes by table name.
///
/// Collects [SyncTableChangeHandler]s from all registered sync modules and
/// routes each [ServerChange] to the appropriate handler. This generic
/// composite scales to any number of sync modules.
///
/// Rebuild instructions for delete changes are captured via the optional
/// [DeleteRebuildPlanner] before the handler processes the change.
class CompositeServerChangeApplier implements ServerChangeApplier {
  CompositeServerChangeApplier({
    required List<SyncTableChangeHandler> handlers,
    ServerChangeDecisionPolicy decisionPolicy = const AlwaysApplyServerChangeDecisionPolicy(),
    DeleteRebuildPlanner? deleteRebuildPlanner,
    SyncRebuildInstructionStore? rebuildInstructionStore,
  })  : _decisionPolicy = decisionPolicy,
        _deleteRebuildPlanner = deleteRebuildPlanner,
        _rebuildInstructionStore = rebuildInstructionStore,
        _handlersByTable = _buildHandlerMap(handlers);

  final ServerChangeDecisionPolicy _decisionPolicy;
  final DeleteRebuildPlanner? _deleteRebuildPlanner;
  final SyncRebuildInstructionStore? _rebuildInstructionStore;
  final Map<String, SyncTableChangeHandler> _handlersByTable;

  @override
  Future<ServerChangeApplyResult> apply(List<ServerChange> changes) async {
    if (changes.isEmpty) {
      return ServerChangeApplyResult.empty;
    }

    final List<ServerChange> orderedChanges = List<ServerChange>.from(changes)
      ..sort((ServerChange left, ServerChange right) => left.cursor.compareTo(right.cursor));
    final List<ServerChange> normalizedChanges = _dropUpsertsSupersededByLaterDeletes(orderedChanges);
    RebuildInstructions rebuildInstructions = RebuildInstructions.empty;

    for (final ServerChange change in normalizedChanges) {
      final ServerChangeDecision decision = _decisionPolicy.decide(change);
      if (decision == ServerChangeDecision.keepLocal) {
        continue;
      }

      final RebuildInstruction? rebuildInstruction = await _captureRebuildInstructionForDelete(change);
      if (rebuildInstruction != null) {
        rebuildInstructions = rebuildInstructions.add(rebuildInstruction);
        await _rebuildInstructionStore?.write(rebuildInstruction);
      }
    }

    final List<ServerChange> changesToApply = <ServerChange>[];
    for (final ServerChange change in normalizedChanges) {
      final ServerChangeDecision decision = _decisionPolicy.decide(change);
      if (decision == ServerChangeDecision.keepLocal) {
        continue;
      }
      changesToApply.add(change);
    }

    await _applyWithForeignKeyDeferral(changesToApply);

    return ServerChangeApplyResult(rebuildInstructions: rebuildInstructions);
  }

  Future<RebuildInstruction?> _captureRebuildInstructionForDelete(ServerChange change) async {
    if (change is! DeleteServerChange) {
      return null;
    }

    final DeleteRebuildPlanner? planner = _deleteRebuildPlanner;
    if (planner == null) {
      return null;
    }

    final String rowId = change.rowId;
    if (rowId.isEmpty) {
      return null;
    }

    return planner.planForDelete(tableName: change.table, rowId: rowId);
  }

  static Map<String, SyncTableChangeHandler> _buildHandlerMap(List<SyncTableChangeHandler> handlers) {
    final Map<String, SyncTableChangeHandler> map = <String, SyncTableChangeHandler>{};

    for (final SyncTableChangeHandler handler in handlers) {
      if (map.containsKey(handler.tableName)) {
        throw StateError('Duplicate SyncTableChangeHandler for table: ${handler.tableName}');
      }
      map[handler.tableName] = handler;
    }

    return map;
  }

  static List<ServerChange> _dropUpsertsSupersededByLaterDeletes(List<ServerChange> orderedChanges) {
    if (orderedChanges.isEmpty) {
      return orderedChanges;
    }

    final Set<String> deletedKeys = <String>{};
    final List<ServerChange> retainedReversed = <ServerChange>[];

    for (final ServerChange change in orderedChanges.reversed) {
      switch (change) {
        case DeleteServerChange():
          deletedKeys.add(_changeKey(change.table, change.rowId));
          retainedReversed.add(change);
          break;
        case UpsertServerChange():
          final String key = _changeKey(change.table, change.rowId);
          if (deletedKeys.contains(key)) {
            continue;
          }
          retainedReversed.add(change);
          break;
      }
    }

    return retainedReversed.reversed.toList(growable: false);
  }

  static String _changeKey(String tableName, String rowId) => '$tableName:$rowId';

  Future<void> _applyWithForeignKeyDeferral(List<ServerChange> changes) async {
    List<ServerChange> pending = List<ServerChange>.from(changes);

    while (pending.isNotEmpty) {
      bool madeProgress = false;
      final List<ServerChange> deferred = <ServerChange>[];
      Object? lastForeignKeyError;

      for (final ServerChange change in pending) {
        final SyncTableChangeHandler? handler = _handlersByTable[change.table];
        if (handler == null) {
          throw UnsupportedError('No server change handler registered for table: ${change.table}');
        }

        try {
          await handler.apply(change);
          madeProgress = true;
        } on Exception catch (error) {
          if (change is UpsertServerChange && error.toString().contains('SqliteException(787)')) {
            deferred.add(change);
            lastForeignKeyError ??= error;
            continue;
          }
          rethrow;
        }
      }

      if (deferred.isEmpty) {
        return;
      }

      if (!madeProgress) {
        throw lastForeignKeyError ?? StateError('Unable to apply deferred FK-dependent server upserts.');
      }

      pending = deferred;
    }
  }
}
