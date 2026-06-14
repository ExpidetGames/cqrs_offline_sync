import 'package:cqrs_offline_sync/cqrs_offline_sync.dart';
import 'package:test/test.dart';

void main() {
  const String opId = 'op-1';
  final SyncCursor baseCursor = SyncCursor('5');

  final DecodedOutboxCommand inFlightCommand = DecodedOutboxCommand(
    opId: opId,
    envelope: CommandEnvelope<_TestCommand>(
      opId: opId,
      occurredAtUtc: DateTime.utc(2024, 1, 1),
      aggregateType: 'test',
      commandType: _TestCommand.type,
      payload: const _TestCommand(),
      baseCursor: SyncCursor('1'),
    ),
    rebuildContext: null,
  );

  final ConflictResolutionContext context = ConflictResolutionContext(
    batch: PreparedSyncBatch(
      request: SyncBatchRequest(
        sinceCursor: SyncCursor('0'),
        syncEpoch: SyncEpoch('0'),
        commands: [inFlightCommand.envelope],
        pullLimit: 500,
        includePull: true,
      ),
      inFlightOpIds: [opId],
      inFlightCommands: [inFlightCommand],
    ),
    response: SyncBatchResponse(
      commandResults: [
        SyncCommandResult(
          opId: opId,
          status: SyncCommandResultStatus.rejectedConflictStale,
          latestCursor: baseCursor,
          reasonCode: SyncCommandResultReasonCodes.recoverableMissingRow,
        ),
      ],
      changes: [],
      newCursor: baseCursor,
    ),
    requeueBaseCursor: baseCursor,
  );

  group('DefaultConflictResolver', () {
    test('acks applied, noopAlreadyApplied, rejectedInvalid', () async {
      final resolver = DefaultConflictResolver(
        staleProfileRegistry: StaleConflictProfileRegistry(),
      );

      for (final status in [
        SyncCommandResultStatus.applied,
        SyncCommandResultStatus.noopAlreadyApplied,
        SyncCommandResultStatus.rejectedInvalid,
      ]) {
        final plan = await resolver.resolve(
          _contextWithStatus(status, baseCursor: baseCursor),
        );
        expect(
          plan.getActionByOpId(opId),
          isA<AckCommandAction>(),
          reason: 'Expected ack for $status',
        );
      }
    });

    test('fails retryableError', () async {
      final resolver = DefaultConflictResolver(
        staleProfileRegistry: StaleConflictProfileRegistry(),
      );

      final plan = await resolver.resolve(
        _contextWithStatus(SyncCommandResultStatus.retryableError, baseCursor: baseCursor),
      );
      expect(plan.getActionByOpId(opId), isA<FailCommandAction>());
    });

    test('drops stale when policy does not route', () async {
      final resolver = DefaultConflictResolver(
        staleProfileRegistry: StaleConflictProfileRegistry(),
        routingPolicy: const SyncStaleRoutingPolicy.recoverableMissingRowOnly(),
      );

      final staleContext = _contextWithStatus(
        SyncCommandResultStatus.rejectedConflictStale,
        baseCursor: baseCursor,
      );

      final plan = await resolver.resolve(staleContext);
      expect(plan.getActionByOpId(opId), isA<AckCommandAction>());
    });

    test('routes stale via recoverableMissingRow reasonCode', () async {
      final resolver = DefaultConflictResolver(
        staleProfileRegistry: StaleConflictProfileRegistry(
          profiles: [
            _DropProfile(commandType: _TestCommand.type),
          ],
        ),
        routingPolicy: const SyncStaleRoutingPolicy.recoverableMissingRowOnly(),
      );

      final plan = await resolver.resolve(context);
      expect(plan.getActionByOpId(opId), isA<AckCommandAction>());
    });

    test('supports legacy reason prefix fallback', () async {
      final resolver = DefaultConflictResolver(
        staleProfileRegistry: StaleConflictProfileRegistry(
          profiles: [
            _ReplayProfile(commandType: _TestCommand.type),
          ],
        ),
        routingPolicy: const SyncStaleRoutingPolicy.recoverableMissingRowOnly(
          allowLegacyReasonPrefixFallback: true,
        ),
      );

      final staleContext = ConflictResolutionContext(
        batch: context.batch,
        response: SyncBatchResponse(
          commandResults: [
            SyncCommandResult(
              opId: opId,
              status: SyncCommandResultStatus.rejectedConflictStale,
              latestCursor: baseCursor,
              reason: 'recoverable_missing_row: row gone',
            ),
          ],
          changes: [],
          newCursor: baseCursor,
        ),
        requeueBaseCursor: baseCursor,
      );

      final plan = await resolver.resolve(staleContext);
      expect(plan.getActionByOpId(opId), isA<RequeueCommandAction>());
    });

    test('fails stale when policy routes but no profile registered', () async {
      final resolver = DefaultConflictResolver(
        staleProfileRegistry: StaleConflictProfileRegistry(),
        routingPolicy: const SyncStaleRoutingPolicy.alwaysRoute(),
      );

      final plan = await resolver.resolve(context);
      expect(plan.getActionByOpId(opId), isA<FailCommandAction>());
    });

    test('replays same command preserving occurredAtUtc', () async {
      final resolver = DefaultConflictResolver(
        staleProfileRegistry: StaleConflictProfileRegistry(
          profiles: [
            _ReplayProfile(commandType: _TestCommand.type),
          ],
        ),
        routingPolicy: const SyncStaleRoutingPolicy.alwaysRoute(),
      );

      final plan = await resolver.resolve(context);
      final action = plan.getActionByOpId(opId) as RequeueCommandAction;
      expect(action.requeuedCommands.length, 1);
      expect(action.requeuedCommands.first.occurredAtUtc, inFlightCommand.envelope.occurredAtUtc);
      expect(action.baseCursor, baseCursor);
    });

    test('rebuilds with provided commands', () async {
      final resolver = DefaultConflictResolver(
        staleProfileRegistry: StaleConflictProfileRegistry(
          profiles: [
            _RebuildProfile(commandType: _TestCommand.type),
          ],
        ),
        routingPolicy: const SyncStaleRoutingPolicy.alwaysRoute(),
      );

      final plan = await resolver.resolve(context);
      final action = plan.getActionByOpId(opId) as RequeueCommandAction;
      expect(action.requeuedCommands.length, 2);
      expect(action.baseCursor, baseCursor);
    });

    test('rebuild with empty commands becomes ack', () async {
      final resolver = DefaultConflictResolver(
        staleProfileRegistry: StaleConflictProfileRegistry(
          profiles: [
            _EmptyRebuildProfile(commandType: _TestCommand.type),
          ],
        ),
        routingPolicy: const SyncStaleRoutingPolicy.alwaysRoute(),
      );

      final plan = await resolver.resolve(context);
      expect(plan.getActionByOpId(opId), isA<AckCommandAction>());
    });

    test('custom routing policy controls routing', () async {
      final resolver = DefaultConflictResolver(
        staleProfileRegistry: StaleConflictProfileRegistry(
          profiles: [
            _DropProfile(commandType: _TestCommand.type),
          ],
        ),
        routingPolicy: SyncStaleRoutingPolicy.custom(
          (context) => context.commandType == _TestCommand.type,
        ),
      );

      final plan = await resolver.resolve(context);
      expect(plan.getActionByOpId(opId), isA<AckCommandAction>());
    });
  });
}

ConflictResolutionContext _contextWithStatus(
  SyncCommandResultStatus status, {
  required SyncCursor baseCursor,
}) {
  const String opId = 'op-1';
  final envelope = CommandEnvelope<_TestCommand>(
    opId: opId,
    occurredAtUtc: DateTime.utc(2024, 1, 1),
    aggregateType: 'test',
    commandType: _TestCommand.type,
    payload: const _TestCommand(),
    baseCursor: SyncCursor('1'),
  );

  return ConflictResolutionContext(
    batch: PreparedSyncBatch(
      request: SyncBatchRequest(
        sinceCursor: SyncCursor('0'),
        syncEpoch: SyncEpoch('0'),
        commands: [envelope],
        pullLimit: 500,
        includePull: true,
      ),
      inFlightOpIds: [opId],
      inFlightCommands: [
        DecodedOutboxCommand(
          opId: opId,
          envelope: envelope,
          rebuildContext: null,
        ),
      ],
    ),
    response: SyncBatchResponse(
      commandResults: [
        SyncCommandResult(
          opId: opId,
          status: status,
          latestCursor: baseCursor,
        ),
      ],
      changes: [],
      newCursor: baseCursor,
    ),
    requeueBaseCursor: baseCursor,
  );
}

class _TestCommand implements SyncCommand {
  const _TestCommand();

  static const String type = 'test.do_thing';

  @override
  String get commandType => type;

  @override
  String get aggregateType => 'test';
}

class _DropProfile implements StaleConflictProfile {
  const _DropProfile({required this.commandType});

  @override
  final String commandType;

  @override
  bool get requiresRebuildInstructions => false;

  @override
  Future<ResolutionDecision<SyncCommand>> resolve(
    StaleConflictProfileContext context,
  ) async =>
      const DropResolutionDecision<SyncCommand>();
}

class _ReplayProfile implements StaleConflictProfile {
  const _ReplayProfile({required this.commandType});

  @override
  final String commandType;

  @override
  bool get requiresRebuildInstructions => false;

  @override
  Future<ResolutionDecision<SyncCommand>> resolve(
    StaleConflictProfileContext context,
  ) async =>
      const ReplaySameResolutionDecision<SyncCommand>();
}

class _RebuildProfile implements StaleConflictProfile {
  const _RebuildProfile({required this.commandType});

  @override
  final String commandType;

  @override
  bool get requiresRebuildInstructions => false;

  @override
  Future<ResolutionDecision<SyncCommand>> resolve(
    StaleConflictProfileContext context,
  ) async =>
      RebuildResolutionDecision<SyncCommand>(
        commands: [
          RequeuedCommand(command: const _TestCommand()),
          RequeuedCommand(command: const _TestCommand()),
        ],
      );
}

class _EmptyRebuildProfile implements StaleConflictProfile {
  const _EmptyRebuildProfile({required this.commandType});

  @override
  final String commandType;

  @override
  bool get requiresRebuildInstructions => false;

  @override
  Future<ResolutionDecision<SyncCommand>> resolve(
    StaleConflictProfileContext context,
  ) async =>
      RebuildResolutionDecision<SyncCommand>(commands: []);
}
