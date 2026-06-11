import 'package:cqrs_offline_sync/cqrs_offline_sync.dart';
import 'package:test/test.dart';

void main() {
  test('NoopSyncTransport acknowledges all request commands', () async {
    final registry = CommandCodecRegistry(<AnyCommandCodec>[
      CommandPayloadCodec<_TestCommand>(
        commandType: 'test.command',
        aggregateType: 'test.aggregate',
        payloadType: _TestCommand,
        fromJson: (_) => const _TestCommand(),
        toJson: (_) => const <String, dynamic>{},
      ),
    ]);
    final envelope = registry.createEnvelope(
      opId: 'op-1',
      occurredAtUtc: DateTime.utc(2026),
      payload: const _TestCommand(),
      baseCursor: SyncCursor('12'),
    );
    final request = SyncBatchRequest(
      sinceCursor: SyncCursor('12'),
      syncEpoch: SyncEpoch.zero(),
      commands: <CommandEnvelope<SyncCommand>>[envelope],
    );

    final response = await const NoopSyncTransport().pushPull(request);

    expect(response.commandResults, hasLength(1));
    expect(response.commandResults.single.opId, 'op-1');
    expect(
      response.commandResults.single.status,
      SyncCommandResultStatus.applied,
    );
    expect(response.newCursor, SyncCursor('12'));
    expect(response.changes, isEmpty);
  });
}

class _TestCommand implements SyncCommand {
  const _TestCommand();

  @override
  String get aggregateType => 'test.aggregate';

  @override
  String get commandType => 'test.command';
}
