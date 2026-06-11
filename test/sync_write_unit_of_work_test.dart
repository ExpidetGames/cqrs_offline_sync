import 'package:cqrs_offline_sync/cqrs_offline_sync.dart';
import 'package:test/test.dart';

void main() {
  group('SyncWriteUnitOfWork', () {
    test(
      'appends command inside transaction and triggers sync after success',
      () async {
        final writer = _RecordingCommandWriter();
        final sink = _RecordingTriggerSink();
        var didRunTransaction = false;

        final uow = SyncWriteUnitOfWork(
          transactionRunner: <T>(Future<T> Function() action) async {
            didRunTransaction = true;
            return action();
          },
          commandWriter: writer,
          triggerSink: sink,
        );

        final result = await uow.runWithSingleCommand<int>(
          writeLocal: () async => 42,
          buildCommand: (_) => const _TestCommand(),
          buildRebuildContext: (_) => <String, dynamic>{'source': 'test'},
        );

        expect(result, 42);
        expect(didRunTransaction, isTrue);
        expect(writer.commands, hasLength(1));
        expect(writer.rebuildContexts.single, <String, dynamic>{
          'source': 'test',
        });
        expect(sink.reasons, <SyncTriggerReason>[
          SyncTriggerReason.localWriteCommitted,
        ]);
      },
    );

    test('does not trigger sync when no command is appended', () async {
      final sink = _RecordingTriggerSink();
      final uow = SyncWriteUnitOfWork(
        transactionRunner: <T>(Future<T> Function() action) => action(),
        commandWriter: _RecordingCommandWriter(),
        triggerSink: sink,
      );

      await uow.run<void>(action: (_) async {});

      expect(sink.reasons, isEmpty);
    });
  });
}

class _TestCommand implements SyncCommand {
  const _TestCommand();

  @override
  String get aggregateType => 'test.aggregate';

  @override
  String get commandType => 'test.command';
}

class _RecordingCommandWriter implements SyncCommandWriter {
  final commands = <SyncCommand>[];
  final rebuildContexts = <Map<String, dynamic>?>[];

  @override
  Future<void> append(
    SyncCommand payload, {
    Map<String, dynamic>? rebuildContext,
  }) async {
    commands.add(payload);
    rebuildContexts.add(rebuildContext);
  }
}

class _RecordingTriggerSink implements SyncTriggerSink {
  final reasons = <SyncTriggerReason>[];

  @override
  void requestSync({required SyncTriggerReason reason}) {
    reasons.add(reason);
  }
}
