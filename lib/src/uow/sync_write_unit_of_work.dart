import '../commands/sync_command.dart';
import '../outbox/sync_command_writer.dart';
import '../persistence/sync_transaction_runner.dart';
import 'sync_trigger_sink.dart';

/// Coordinates one local write transaction with outbox command creation.
///
/// Wraps a [transactionRunner], a [commandWriter], and an optional
/// [triggerSink] so that:
/// 1. Local writes run inside a transaction
/// 2. Commands are appended to the outbox
/// 3. After successful commit, a sync trigger is fired
class SyncWriteUnitOfWork {
  /// Creates a write unit of work.
  const SyncWriteUnitOfWork({
    required SyncTransactionRunner transactionRunner,
    required SyncCommandWriter commandWriter,
    SyncTriggerSink triggerSink = const NoopSyncTriggerSink(),
  }) : _transactionRunner = transactionRunner,
       _commandWriter = commandWriter,
       _triggerSink = triggerSink;

  final SyncTransactionRunner _transactionRunner;
  final SyncCommandWriter _commandWriter;
  final SyncTriggerSink _triggerSink;

  /// Runs [action] inside a transaction and fires a sync trigger if any
  /// command was appended.
  Future<T> run<T>({required Future<T> Function(SyncWriteTx tx) action}) async {
    bool didAppendCommand = false;

    final T result = await _transactionRunner<T>(() async {
      final SyncWriteTx tx = SyncWriteTx._(
        commandWriter: _commandWriter,
        onCommandAppended: () {
          didAppendCommand = true;
        },
      );
      return action(tx);
    });

    if (didAppendCommand) {
      _triggerSink.requestSync(reason: SyncTriggerReason.localWriteCommitted);
    }

    return result;
  }

  /// Convenience helper that runs [writeLocal], builds a command from the
  /// result, appends it, and fires the trigger.
  Future<T> runWithSingleCommand<T>({
    required Future<T> Function() writeLocal,
    required SyncCommand Function(T result) buildCommand,
    Map<String, dynamic>? Function(T result)? buildRebuildContext,
  }) {
    return run<T>(
      action: (SyncWriteTx tx) async {
        final T result = await writeLocal();
        await tx.appendCommand(
          buildCommand(result),
          rebuildContext: buildRebuildContext?.call(result),
        );
        return result;
      },
    );
  }

  /// Convenience helper for void writes with a single command.
  Future<void> runVoidWithCommand({
    required Future<void> Function() writeLocal,
    required SyncCommand command,
    Map<String, dynamic>? rebuildContext,
  }) {
    return run<void>(
      action: (SyncWriteTx tx) async {
        await writeLocal();
        await tx.appendCommand(command, rebuildContext: rebuildContext);
      },
    );
  }
}

/// Transaction handle provided to [SyncWriteUnitOfWork.run] callbacks.
class SyncWriteTx {
  const SyncWriteTx._({
    required SyncCommandWriter commandWriter,
    required void Function() onCommandAppended,
  }) : _commandWriter = commandWriter,
       _onCommandAppended = onCommandAppended;

  final SyncCommandWriter _commandWriter;
  final void Function() _onCommandAppended;

  /// Appends [payload] to the outbox and marks the transaction as needing
  /// a post-commit sync trigger.
  Future<void> appendCommand(
    SyncCommand payload, {
    Map<String, dynamic>? rebuildContext,
  }) async {
    await _commandWriter.append(payload, rebuildContext: rebuildContext);
    _onCommandAppended();
  }
}
