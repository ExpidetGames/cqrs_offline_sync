import '../commands/command_envelope_factory.dart';
import '../commands/sync_command.dart';
import '../protocol/sync_cursor.dart';
import '../persistence/sync_outbox_store.dart';
import '../persistence/sync_state_store.dart';
import 'sync_command_writer.dart';

/// Sync command writer that appends commands into the shared [SyncOutboxStore]
/// using the base cursor from [SyncStateStore] and wrapping the payload with
/// [CommandEnvelopeFactory].
///
/// This implementation is persistence-agnostic: it only depends on the
/// package contracts. Concrete storage (Drift, Hive, Isar, …) is provided
/// through injected store implementations.
///
/// Wire it into [SyncWriteUnitOfWork] alongside a transaction runner that
/// matches whatever local database executes the domain write.
class PersistentSyncCommandWriter implements SyncCommandWriter {
  /// Creates a writer backed by [stateStore], [outboxStore] and [envelopeFactory].
  const PersistentSyncCommandWriter({
    required SyncStateStore stateStore,
    required SyncOutboxStore outboxStore,
    required CommandEnvelopeFactory envelopeFactory,
  })  : _stateStore = stateStore,
        _outboxStore = outboxStore,
        _envelopeFactory = envelopeFactory;

  final SyncStateStore _stateStore;
  final SyncOutboxStore _outboxStore;
  final CommandEnvelopeFactory _envelopeFactory;

  @override
  Future<void> append(
    SyncCommand payload, {
    Map<String, dynamic>? rebuildContext,
  }) async {
    final SyncCursor baseCursor = await _stateStore.readLastServerCursorOrZero();
    final envelope = _envelopeFactory.create(
      payload: payload,
      baseCursor: baseCursor,
    );
    await _outboxStore.append(envelope, rebuildContext: rebuildContext);
  }
}
