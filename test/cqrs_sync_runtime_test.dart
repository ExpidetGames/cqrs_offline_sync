import 'package:cqrs_offline_sync/cqrs_offline_sync.dart';
import 'package:test/test.dart';

void main() {
  group('CqrsSyncRuntime.compose', () {
    test('composes a minimal runtime with empty modules', () {
      final runtime = CqrsSyncRuntime.compose(
        modules: const [],
        stores: _minimalStores(),
        transactionRunner: _noopTransactionRunner,
        transport: const NoopSyncTransport(),
      );

      expect(runtime.modules, isEmpty);
      expect(runtime.commandCodecs, isEmpty);
      expect(runtime.tableChangeHandlers, isEmpty);
      expect(runtime.staleConflictProfiles, isEmpty);
      expect(runtime.localDataScopes, isEmpty);
      expect(runtime.rebuildEdges, isEmpty);
      expect(runtime.codecRegistry, isA<CommandCodecRegistry>());
      expect(runtime.envelopeFactory, isA<CommandEnvelopeFactory>());
      expect(runtime.commandWriter, isA<PersistentSyncCommandWriter>());
      expect(runtime.unitOfWork, isA<SyncUnitOfWork>());
      expect(runtime.changeApplier, isA<ServerChangeApplier>());
      expect(runtime.runner, isA<SyncRunner>());
      expect(runtime.conflictResolver, isNull);
      expect(runtime.staleProfileRegistry, isNull);
      expect(runtime.rebuildGraph, isNull);
      expect(runtime.localDataResetService, isA<LocalDataResetService>());
      expect(runtime.runtimeQueueReset, isA<SyncRuntimeQueueReset>());
      expect(runtime.createWriteUnitOfWork(), isA<SyncWriteUnitOfWork>());
    });

    test('collects module contributions', () {
      final runtime = CqrsSyncRuntime.compose(
        modules: [
          _TestModule(
            moduleId: 'notes',
            commandCodecs: const [_TestCodec(commandType: 'notes.create')],
            tableChangeHandlers: const [
              _TestHandler(tableName: 'notes'),
            ],
            staleConflictProfiles: const [
              _TestProfile(commandType: 'notes.create'),
            ],
          ),
        ],
        stores: _minimalStores(),
        transactionRunner: _noopTransactionRunner,
        transport: const NoopSyncTransport(),
      );

      expect(runtime.commandCodecs.length, 1);
      expect(runtime.tableChangeHandlers.length, 1);
      expect(runtime.staleConflictProfiles.length, 1);
      expect(runtime.staleProfileRegistry, isA<StaleConflictProfileRegistry>());
    });

    test('detects duplicate module ids', () {
      expect(
        () => CqrsSyncRuntime.compose(
          modules: [
            _TestModule(moduleId: 'notes'),
            _TestModule(moduleId: 'notes'),
          ],
          stores: _minimalStores(),
          transactionRunner: _noopTransactionRunner,
          transport: const NoopSyncTransport(),
        ),
        throwsA(
          isA<SyncRuntimeConfigurationException>().having(
            (e) => e.message,
            'message',
            contains('Duplicate moduleId'),
          ),
        ),
      );
    });

    test('detects duplicate command codecs', () {
      expect(
        () => CqrsSyncRuntime.compose(
          modules: [
            _TestModule(
              moduleId: 'a',
              commandCodecs: const [
                _TestCodec(commandType: 'shared.create'),
              ],
            ),
            _TestModule(
              moduleId: 'b',
              commandCodecs: const [
                _TestCodec(commandType: 'shared.create'),
              ],
            ),
          ],
          stores: _minimalStores(),
          transactionRunner: _noopTransactionRunner,
          transport: const NoopSyncTransport(),
        ),
        throwsA(
          isA<SyncRuntimeConfigurationException>().having(
            (e) => e.message,
            'message',
            contains('duplicate commandType'),
          ),
        ),
      );
    });

    test('detects duplicate table handlers', () {
      expect(
        () => CqrsSyncRuntime.compose(
          modules: [
            _TestModule(
              moduleId: 'a',
              tableChangeHandlers: const [
                _TestHandler(tableName: 'shared'),
              ],
            ),
            _TestModule(
              moduleId: 'b',
              tableChangeHandlers: const [
                _TestHandler(tableName: 'shared'),
              ],
            ),
          ],
          stores: _minimalStores(),
          transactionRunner: _noopTransactionRunner,
          transport: const NoopSyncTransport(),
        ),
        throwsA(
          isA<SyncRuntimeConfigurationException>().having(
            (e) => e.message,
            'message',
            contains('duplicate tableName'),
          ),
        ),
      );
    });

    test('detects duplicate stale profiles', () {
      expect(
        () => CqrsSyncRuntime.compose(
          modules: [
            _TestModule(
              moduleId: 'a',
              staleConflictProfiles: const [
                _TestProfile(commandType: 'shared.create'),
              ],
            ),
            _TestModule(
              moduleId: 'b',
              staleConflictProfiles: const [
                _TestProfile(commandType: 'shared.create'),
              ],
            ),
          ],
          stores: _minimalStores(),
          transactionRunner: _noopTransactionRunner,
          transport: const NoopSyncTransport(),
        ),
        throwsA(
          isA<SyncRuntimeConfigurationException>().having(
            (e) => e.message,
            'message',
            contains('duplicate commandType'),
          ),
        ),
      );
    });

    test('detects duplicate local data scope ids', () {
      expect(
        () => CqrsSyncRuntime.compose(
          modules: [
            _TestModule(
              moduleId: 'a',
              localDataScope: const _TestScope(id: 'shared'),
            ),
            _TestModule(
              moduleId: 'b',
              localDataScope: const _TestScope(id: 'shared'),
            ),
          ],
          stores: _minimalStores(),
          transactionRunner: _noopTransactionRunner,
          transport: const NoopSyncTransport(),
        ),
        throwsA(
          isA<SyncRuntimeConfigurationException>().having(
            (e) => e.message,
            'message',
            contains('duplicate scope id'),
          ),
        ),
      );
    });

    test('extra rebuild edges require registered nodes', () {
      expect(
        () => CqrsSyncRuntime.compose(
          modules: [
            _TestModule(
              moduleId: 'notes',
              rebuildGraph: RebuildGraph(
                nodes: [
                  _TestRebuildNode(tableName: 'notes'),
                ],
              ),
            ),
          ],
          extraContributions: SyncRuntimeContributions.from(
            rebuildEdges: [
              RebuildGraphEdge<Object, Object>(
                parentTableName: 'notes',
                childTableName: 'missing',
                loadChildren: (_) async => [],
              ),
            ],
          ),
          stores: _minimalStores(),
          transactionRunner: _noopTransactionRunner,
          transport: const NoopSyncTransport(),
        ),
        throwsA(
          isA<SyncRuntimeConfigurationException>().having(
            (e) => e.message,
            'message',
            contains('RebuildGraph edge child table is not registered'),
          ),
        ),
      );
    });

    test('deleteRebuild enabled requires real rebuild instruction store', () {
      expect(
        () => CqrsSyncRuntime.compose(
          modules: [
            _TestModule(
              moduleId: 'notes',
              rebuildGraph: RebuildGraph(
                nodes: [
                  _TestRebuildNode(tableName: 'notes'),
                ],
              ),
            ),
          ],
          stores: _minimalStores(),
          changeApplication: const SyncChangeApplicationConfig(
            deleteRebuild: SyncDeleteRebuild.enabled(),
          ),
          transactionRunner: _noopTransactionRunner,
          transport: const NoopSyncTransport(),
        ),
        throwsA(
          isA<SyncRuntimeConfigurationException>().having(
            (e) => e.message,
            'message',
            contains('deleteRebuild enabled but stores.rebuildInstructions is a NoopSyncRebuildInstructionStore'),
          ),
        ),
      );
    });

    test('auto conflict resolution builds default resolver when profiles exist', () {
      final runtime = CqrsSyncRuntime.compose(
        modules: [
          _TestModule(
            moduleId: 'notes',
            staleConflictProfiles: const [
              _TestProfile(commandType: 'notes.create'),
            ],
          ),
        ],
        stores: _minimalStores(),
        transactionRunner: _noopTransactionRunner,
        transport: const NoopSyncTransport(),
      );

      expect(runtime.conflictResolver, isA<DefaultConflictResolver>());
      expect(runtime.staleProfileRegistry, isA<StaleConflictProfileRegistry>());
    });

    test('disabled conflict resolution yields no resolver', () {
      final runtime = CqrsSyncRuntime.compose(
        modules: [
          _TestModule(
            moduleId: 'notes',
            staleConflictProfiles: const [
              _TestProfile(commandType: 'notes.create'),
            ],
          ),
        ],
        stores: _minimalStores(),
        conflictResolution: const SyncConflictResolution.disabled(),
        transactionRunner: _noopTransactionRunner,
        transport: const NoopSyncTransport(),
      );

      expect(runtime.conflictResolver, isNull);
      expect(runtime.staleProfileRegistry, isA<StaleConflictProfileRegistry>());
    });

    test('custom conflict resolution uses provided resolver', () {
      final customResolver = _TestResolver();
      final runtime = CqrsSyncRuntime.compose(
        modules: [
          _TestModule(
            moduleId: 'notes',
            staleConflictProfiles: const [
              _TestProfile(commandType: 'notes.create'),
            ],
          ),
        ],
        stores: _minimalStores(),
        conflictResolution: SyncConflictResolution.custom(customResolver),
        transactionRunner: _noopTransactionRunner,
        transport: const NoopSyncTransport(),
      );

      expect(runtime.conflictResolver, same(customResolver));
      expect(runtime.staleProfileRegistry, isA<StaleConflictProfileRegistry>());
    });

    test('collects all errors in one exception', () {
      expect(
        () => CqrsSyncRuntime.compose(
          modules: [
            _TestModule(moduleId: 'dup'),
            _TestModule(moduleId: 'dup'),
          ],
          stores: _minimalStores(),
          changeApplication: const SyncChangeApplicationConfig(
            deleteRebuild: SyncDeleteRebuild.enabled(),
          ),
          transactionRunner: _noopTransactionRunner,
          transport: const NoopSyncTransport(),
        ),
        throwsA(
          isA<SyncRuntimeConfigurationException>().having(
            (e) => e.message,
            'message',
            allOf(contains('Duplicate moduleId'), contains('deleteRebuild enabled')),
          ),
        ),
      );
    });
  });
}

SyncStores _minimalStores() {
  return SyncStores(
    outbox: _TestOutboxStore(),
    state: _TestStateStore(),
  );
}

Future<T> _noopTransactionRunner<T>(Future<T> Function() action) => action();

class _TestModule implements SyncModuleRegistration {
  _TestModule({
    required this.moduleId,
    this.commandCodecs = const [],
    this.tableChangeHandlers = const [],
    this.staleConflictProfiles = const [],
    this.localDataScope = const _TestScope(id: 'test_scope'),
    RebuildGraph? rebuildGraph,
  }) : rebuildGraph = rebuildGraph ?? RebuildGraph(nodes: const []);

  @override
  final String moduleId;

  @override
  final List<AnyCommandCodec> commandCodecs;

  @override
  final List<SyncTableChangeHandler> tableChangeHandlers;

  @override
  final List<StaleConflictProfile> staleConflictProfiles;

  @override
  final LocalDataScope localDataScope;

  @override
  final RebuildGraph rebuildGraph;
}


class _TestCodec implements AnyCommandCodec {
  const _TestCodec({required this.commandType});

  @override
  final String commandType;

  @override
  String get aggregateType => 'test';

  @override
  Type get payloadType => _TestPayload;

  @override
  SyncCommand decode(Object? payloadJson) => const _TestPayload();

  @override
  Object? encode(SyncCommand payload) => {};
}

class _TestPayload implements SyncCommand {
  const _TestPayload();

  @override
  String get commandType => 'test';

  @override
  String get aggregateType => 'test';
}

class _TestHandler implements SyncTableChangeHandler {
  const _TestHandler({required this.tableName});

  @override
  final String tableName;

  @override
  Future<void> apply(ServerChange change) async {}
}

class _TestProfile implements StaleConflictProfile {
  const _TestProfile({required this.commandType});

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

class _TestScope implements LocalDataScope {
  const _TestScope({required this.id});

  @override
  final String id;

  @override
  Future<bool> hasData() async => false;

  @override
  Future<void> clear() async {}
}

class _TestRebuildNode implements AnyRebuildGraphNode {
  const _TestRebuildNode({required this.tableName});

  @override
  final String tableName;

  @override
  Future<Object?> loadById(String rowId) async => null;

  @override
  Future<List<Object>> loadAll() async => [];

  @override
  RebuildEntityRef toEntityRef(Object row) =>
      RebuildEntityRef(tableName: tableName, rowId: 'row');

  @override
  RequeuedCommand toCreateCommand(Object row) =>
      RequeuedCommand(command: const _TestPayload());

  @override
  Map<String, dynamic> toSnapshot(Object row) => {};

  @override
  RebuildGraphParentRef? parentOf(Object row) => null;
}

class _TestOutboxStore implements SyncOutboxStore {
  @override
  Future<void> append(
    CommandEnvelope<SyncCommand> envelope, {
    Map<String, dynamic>? rebuildContext,
  }) async {}

  @override
  Future<List<DecodedOutboxCommand>> nextPending({int limit = 100}) async => [];

  @override
  Future<void> recoverInFlightToPending() async {}

  @override
  Future<void> markInFlight(Iterable<String> opIds) async {}

  @override
  Future<void> markAcked(Iterable<String> opIds) async {}

  @override
  Future<void> markManyFailed(Iterable<OutboxFailureUpdate> failures) async {}

  @override
  Future<bool> hasUnsettledCommands() async => false;

  @override
  Future<void> clear() async {}
}

class _TestStateStore implements SyncStateStore {
  @override
  Future<SyncCursor> readLastServerCursorOrZero() async => SyncCursor('0');

  @override
  Future<void> writeLastServerCursorIfAdvanced(SyncCursor candidate) async {}

  @override
  Future<SyncEpoch> readLastSyncEpochOrZero() async => SyncEpoch('0');

  @override
  Future<void> writeLastSyncEpoch(SyncEpoch epoch) async {}

  @override
  Future<void> writeLastServerCursor(SyncCursor cursor) async {}

  @override
  Future<void> clearAll() async {}
}

class _TestResolver implements ConflictResolver {
  @override
  Future<ConflictResolutionPlan> resolve(ConflictResolutionContext context) async {
    return ConflictResolutionPlan(actions: []);
  }
}
