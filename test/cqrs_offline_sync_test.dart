import 'package:cqrs_offline_sync/cqrs_offline_sync.dart';
import 'package:test/test.dart';

import 'support/sync_test_harness.dart';

void main() {
  group('cqrs_offline_sync public surface', () {
    test(
      'creates and serializes a typed command envelope through the registry',
      () {
        final registry = testCommandRegistry();
        final envelope = registry.createEnvelope(
          opId: 'op-1',
          occurredAtUtc: DateTime.utc(2026),
          payload: const TestCommand(id: 'item-1'),
          baseCursor: SyncCursor.zero(),
        );

        final json = registry.encode(envelope);
        final decoded = registry.decode(json);

        expect(json['commandType'], TestCommand.type);
        expect(json['aggregateType'], TestCommand.aggregate);
        expect(decoded.envelope.opId, 'op-1');
        expect(decoded.payloadAs<TestCommand>().id, 'item-1');
      },
    );
  });
}
