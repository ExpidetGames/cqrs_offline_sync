import '../../commands/command_codec_registry.dart';
import '../../commands/command_envelope_factory.dart';
import '../../outbox/persistent_sync_command_writer.dart';
import '../../persistence/noop_sync_rebuild_instruction_store.dart';
import '../../persistence/sync_transaction_runner.dart';
import '../../uow/sync_trigger_sink.dart';
import '../../uow/sync_write_unit_of_work.dart';
import '../local_data/local_data_scope.dart';
import '../change_applier/composite_server_change_applier.dart';
import '../change_applier/server_change_decision_policy.dart';
import '../change_applier/sync_table_change_handler.dart';
import '../conflict/conflict_resolver.dart';
import '../conflict/stale_conflict_profile.dart';
import '../conflict/stale_conflict_profile_registry.dart';
import '../rebuild/delete_rebuild_planner.dart';
import '../rebuild/graph_delete_rebuild_planner.dart';
import '../rebuild/rebuild_graph.dart';
import '../rebuild/server_change_applier.dart';
import '../sync_module_registration.dart';
import '../sync_resync_handler.dart';
import '../sync_runner.dart';
import '../sync_transport.dart';
import '../sync_unit_of_work.dart';
import 'local_data_reset_service.dart';
import '../bootstrap/sync_bootstrap_replace_client.dart';
import '../bootstrap/sync_bootstrap_replace_service.dart';
import 'sync_change_application_config.dart';
import 'sync_conflict_resolution.dart';
import 'sync_runtime_configuration_exception.dart';
import 'sync_runtime_contributions.dart';
import 'sync_runtime_queue_reset.dart';
import 'sync_stores.dart';

export 'local_data_reset_service.dart';
export 'sync_change_application_config.dart';
export 'sync_conflict_resolution.dart';
export 'sync_runtime_configuration_exception.dart';
export 'sync_runtime_contributions.dart';
export 'sync_runtime_queue_reset.dart';
export 'sync_stores.dart';

/// Host-agnostic composition facade for the cqrs_offline_sync runtime.
///
/// [CqrsSyncRuntime.compose] collects [SyncModuleRegistration]s, stores,
/// transport, and policies into a single object that exposes the ready-to-use
/// sync primitives. Lower-level public APIs remain available for advanced
/// customization.
class CqrsSyncRuntime {
  CqrsSyncRuntime._({
    required this.modules,
    required this.stores,
    required this.transactionRunner,
    required this.transport,
    required this.opIdGenerator,
    required this.clock,
    required this.extraContributions,
    required this.changeApplication,
    required this.conflictResolution,
    required this.commandCodecs,
    required this.tableChangeHandlers,
    required this.staleConflictProfiles,
    required this.localDataScopes,
    required this.rebuildEdges,
    required this.codecRegistry,
    required this.envelopeFactory,
    required this.commandWriter,
    required this.unitOfWork,
    required this.changeApplier,
    required this.runner,
    required this.conflictResolver,
    required this.staleProfileRegistry,
    required this.rebuildGraph,
    required this.localDataResetService,
    required this.runtimeQueueReset,
    this.bootstrapReplaceService,
  });

  /// Registered sync modules, in the order supplied to [compose].
  final List<SyncModuleRegistration> modules;

  /// Persistence stores used by the runtime.
  final SyncStores stores;

  /// Transaction runner passed to [compose].
  final SyncTransactionRunner transactionRunner;

  /// Transport used to push commands and pull server changes.
  final SyncTransport transport;

  /// Operation id generator used for new command envelopes.
  final OpIdGenerator opIdGenerator;

  /// Clock used for new command timestamps.
  final UtcClock clock;

  /// Extra runtime contributions supplied in addition to module contributions.
  final SyncRuntimeContributions extraContributions;

  /// Change application configuration supplied to [compose].
  final SyncChangeApplicationConfig changeApplication;

  /// Conflict resolution configuration supplied to [compose].
  final SyncConflictResolution conflictResolution;

  /// Flattened immutable list of all command codecs.
  final List<AnyCommandCodec> commandCodecs;

  /// Flattened immutable list of all table change handlers.
  final List<SyncTableChangeHandler> tableChangeHandlers;

  /// Flattened immutable list of all stale conflict profiles.
  final List<StaleConflictProfile> staleConflictProfiles;

  /// Flattened immutable list of all local data scopes.
  final List<LocalDataScope> localDataScopes;

  /// Flattened immutable list of all extra rebuild edges.
  final List<AnyRebuildGraphEdge> rebuildEdges;

  /// Codec registry built from [commandCodecs].
  final CommandCodecRegistry codecRegistry;

  /// Envelope factory built from [codecRegistry], [opIdGenerator], and [clock].
  final CommandEnvelopeFactory envelopeFactory;

  /// Shared persistent command writer built from [envelopeFactory] and
  /// [stores.outbox].
  final PersistentSyncCommandWriter commandWriter;

  /// Unit of work used by [runner].
  final SyncUnitOfWork unitOfWork;

  /// Change applier used by [runner].
  final ServerChangeApplier changeApplier;

  /// Sync runner that executes sync cycles.
  final SyncRunner runner;

  /// Conflict resolver used by [runner], or `null` if disabled.
  final ConflictResolver? conflictResolver;

  /// Stale profile registry built from [staleConflictProfiles], or `null` if
  /// none were registered.
  final StaleConflictProfileRegistry? staleProfileRegistry;

  /// Merged rebuild graph built from module graphs and [rebuildEdges], or
  /// `null` if no graph nodes exist.
  final RebuildGraph? rebuildGraph;

  /// Local data reset service built from [localDataScopes].
  final LocalDataResetService localDataResetService;

  /// Helper for clearing runtime queue data.
  final SyncRuntimeQueueReset runtimeQueueReset;

  /// Device-wins bootstrap-replace service, or `null` if no client was
  /// supplied or no rebuild graph exists.
  final SyncBootstrapReplaceService? bootstrapReplaceService;

  /// Composes a sync runtime from modules, stores, transaction runner, and
  /// transport.
  ///
  /// Required parameters:
  /// - [modules]: sync module registrations.
  /// - [stores]: persistence stores.
  /// - [transactionRunner]: transaction runner for sync commits.
  /// - [transport]: sync transport.
  ///
  /// Optional parameters:
  /// - [extraContributions]: additional codecs, handlers, profiles, scopes, and
  ///   rebuild edges.
  /// - [changeApplication]: server change application configuration.
  /// - [conflictResolution]: stale conflict resolution configuration.
  /// - [opIdGenerator]: operation id generator. Defaults to UUID v4.
  /// - [clock]: UTC clock. Defaults to system clock.
  /// - [resyncHandler]: invoked when the server requests a full resync.
  /// - [bootstrapReplaceClient]: optional host client for the device-wins
  ///   bootstrap-replace flow. Requires a non-empty [rebuildGraph].
  ///
  /// Throws [SyncRuntimeConfigurationException] if the configuration is invalid.
  static CqrsSyncRuntime compose({
    required Iterable<SyncModuleRegistration> modules,
    required SyncStores stores,
    required SyncTransactionRunner transactionRunner,
    required SyncTransport transport,
    SyncRuntimeContributions extraContributions = const SyncRuntimeContributions(),
    SyncChangeApplicationConfig changeApplication = const SyncChangeApplicationConfig(),
    SyncConflictResolution conflictResolution = const SyncConflictResolution.auto(),
    OpIdGenerator opIdGenerator = const UuidOpIdGenerator(),
    UtcClock clock = const SystemUtcClock(),
    SyncResyncHandler? resyncHandler,
    SyncBootstrapReplaceClient? bootstrapReplaceClient,
  }) {
    final List<SyncModuleRegistration> moduleList = List<SyncModuleRegistration>.unmodifiable(modules);

    final List<String> errors = <String>[];
    _validateModules(moduleList, errors);

    final List<AnyCommandCodec> commandCodecs = _flattenCommandCodecs(
      moduleList,
      extraContributions,
      errors,
    );
    final List<SyncTableChangeHandler> tableChangeHandlers = _flattenTableHandlers(
      moduleList,
      extraContributions,
      errors,
    );
    final List<StaleConflictProfile> staleConflictProfiles = _flattenStaleProfiles(
      moduleList,
      extraContributions,
      errors,
    );
    final List<LocalDataScope> localDataScopes = _flattenLocalDataScopes(
      moduleList,
      extraContributions,
      errors,
    );
    final RebuildGraph? rebuildGraph = _buildRebuildGraph(
      moduleList,
      extraContributions,
      errors,
    );

    _validateFeatureDependencies(
      stores: stores,
      changeApplication: changeApplication,
      staleConflictProfiles: staleConflictProfiles,
      conflictResolution: conflictResolution,
      errors: errors,
    );
    _validateBootstrapReplaceClient(
      bootstrapReplaceClient: bootstrapReplaceClient,
      rebuildGraph: rebuildGraph,
      errors: errors,
    );

    if (errors.isNotEmpty) {
      throw SyncRuntimeConfigurationException(errors.join('\n'));
    }

    final BuiltConflictResolution builtConflictResolution = buildConflictResolution(
      config: conflictResolution,
      profiles: staleConflictProfiles,
    );

    final CommandCodecRegistry codecRegistry = CommandCodecRegistry(commandCodecs);
    final CommandEnvelopeFactory envelopeFactory = CommandEnvelopeFactory(
      codecRegistry: codecRegistry,
      opIdGenerator: opIdGenerator,
      clock: clock,
    );
    final PersistentSyncCommandWriter commandWriter = PersistentSyncCommandWriter(
      outboxStore: stores.outbox,
      stateStore: stores.state,
      envelopeFactory: envelopeFactory,
    );

    final SyncUnitOfWork unitOfWork = SyncUnitOfWork(
      transactionRunner: transactionRunner,
      outboxStore: stores.outbox,
      syncStateStore: stores.state,
      conflictLogStore: stores.conflictLog,
      envelopeFactory: envelopeFactory,
    );

    final ServerChangeApplier changeApplier = _buildChangeApplier(
      handlers: tableChangeHandlers,
      config: changeApplication,
      stores: stores,
      rebuildGraph: rebuildGraph,
    );

    final SyncRunner runner = SyncRunner(
      unitOfWork: unitOfWork,
      transport: transport,
      changeApplier: changeApplier,
      conflictResolver: builtConflictResolution.resolver,
      resyncHandler: resyncHandler,
      rebuildInstructionStore: stores.rebuildInstructions,
    );

    final SyncBootstrapReplaceService? bootstrapReplaceService =
        bootstrapReplaceClient == null || rebuildGraph == null
            ? null
            : SyncBootstrapReplaceService(
                client: bootstrapReplaceClient,
                stateStore: stores.state,
                rebuildGraph: rebuildGraph,
              );

    return CqrsSyncRuntime._(
      modules: moduleList,
      stores: stores,
      transactionRunner: transactionRunner,
      transport: transport,
      opIdGenerator: opIdGenerator,
      clock: clock,
      extraContributions: extraContributions,
      changeApplication: changeApplication,
      conflictResolution: conflictResolution,
      commandCodecs: commandCodecs,
      tableChangeHandlers: tableChangeHandlers,
      staleConflictProfiles: staleConflictProfiles,
      localDataScopes: localDataScopes,
      rebuildEdges: List<AnyRebuildGraphEdge>.unmodifiable(extraContributions.rebuildEdges),
      codecRegistry: codecRegistry,
      envelopeFactory: envelopeFactory,
      commandWriter: commandWriter,
      unitOfWork: unitOfWork,
      changeApplier: changeApplier,
      runner: runner,
      conflictResolver: builtConflictResolution.resolver,
      staleProfileRegistry: builtConflictResolution.registry,
      rebuildGraph: rebuildGraph,
      localDataResetService: LocalDataResetService(scopes: localDataScopes),
      runtimeQueueReset: SyncRuntimeQueueReset(stores: stores),
      bootstrapReplaceService: bootstrapReplaceService,
    );
  }

  /// Creates a write-side [SyncWriteUnitOfWork] using the shared
  /// [commandWriter].
  SyncWriteUnitOfWork createWriteUnitOfWork({
    SyncTriggerSink? triggerSink,
  }) {
    return SyncWriteUnitOfWork(
      transactionRunner: transactionRunner,
      commandWriter: commandWriter,
      triggerSink: triggerSink ?? const NoopSyncTriggerSink(),
    );
  }

  static void _validateModules(
    List<SyncModuleRegistration> modules,
    List<String> errors,
  ) {
    final Set<String> seenModuleIds = <String>{};
    for (int i = 0; i < modules.length; i++) {
      final SyncModuleRegistration module = modules[i];
      if (!seenModuleIds.add(module.moduleId)) {
        errors.add('Duplicate moduleId: "${module.moduleId}" at index $i.');
      }
    }
  }

  static List<AnyCommandCodec> _flattenCommandCodecs(
    List<SyncModuleRegistration> modules,
    SyncRuntimeContributions extras,
    List<String> errors,
  ) {
    final List<AnyCommandCodec> result = <AnyCommandCodec>[];
    final Set<String> seenCommandTypes = <String>{};

    for (final SyncModuleRegistration module in modules) {
      for (int i = 0; i < module.commandCodecs.length; i++) {
        final AnyCommandCodec codec = module.commandCodecs[i];
        if (!seenCommandTypes.add(codec.commandType)) {
          errors.add(
            'module "${module.moduleId}".commandCodecs[$i]: '
            'duplicate commandType "${codec.commandType}".',
          );
        }
        result.add(codec);
      }
    }

    for (int i = 0; i < extras.commandCodecs.length; i++) {
      final AnyCommandCodec codec = extras.commandCodecs[i];
      if (!seenCommandTypes.add(codec.commandType)) {
        errors.add(
          'extraContributions.commandCodecs[$i]: '
          'duplicate commandType "${codec.commandType}".',
        );
      }
      result.add(codec);
    }

    return List<AnyCommandCodec>.unmodifiable(result);
  }

  static List<SyncTableChangeHandler> _flattenTableHandlers(
    List<SyncModuleRegistration> modules,
    SyncRuntimeContributions extras,
    List<String> errors,
  ) {
    final List<SyncTableChangeHandler> result = <SyncTableChangeHandler>[];
    final Set<String> seenTableNames = <String>{};

    for (final SyncModuleRegistration module in modules) {
      for (int i = 0; i < module.tableChangeHandlers.length; i++) {
        final SyncTableChangeHandler handler = module.tableChangeHandlers[i];
        if (!seenTableNames.add(handler.tableName)) {
          errors.add(
            'module "${module.moduleId}".tableChangeHandlers[$i]: '
            'duplicate tableName "${handler.tableName}".',
          );
        }
        result.add(handler);
      }
    }

    for (int i = 0; i < extras.tableChangeHandlers.length; i++) {
      final SyncTableChangeHandler handler = extras.tableChangeHandlers[i];
      if (!seenTableNames.add(handler.tableName)) {
        errors.add(
          'extraContributions.tableChangeHandlers[$i]: '
          'duplicate tableName "${handler.tableName}".',
        );
      }
      result.add(handler);
    }

    return List<SyncTableChangeHandler>.unmodifiable(result);
  }

  static List<StaleConflictProfile> _flattenStaleProfiles(
    List<SyncModuleRegistration> modules,
    SyncRuntimeContributions extras,
    List<String> errors,
  ) {
    final List<StaleConflictProfile> result = <StaleConflictProfile>[];
    final Set<String> seenCommandTypes = <String>{};

    for (final SyncModuleRegistration module in modules) {
      for (int i = 0; i < module.staleConflictProfiles.length; i++) {
        final StaleConflictProfile profile = module.staleConflictProfiles[i];
        if (!seenCommandTypes.add(profile.commandType)) {
          errors.add(
            'module "${module.moduleId}".staleConflictProfiles[$i]: '
            'duplicate commandType "${profile.commandType}".',
          );
        }
        result.add(profile);
      }
    }

    for (int i = 0; i < extras.staleConflictProfiles.length; i++) {
      final StaleConflictProfile profile = extras.staleConflictProfiles[i];
      if (!seenCommandTypes.add(profile.commandType)) {
        errors.add(
          'extraContributions.staleConflictProfiles[$i]: '
          'duplicate commandType "${profile.commandType}".',
        );
      }
      result.add(profile);
    }

    return List<StaleConflictProfile>.unmodifiable(result);
  }

  static List<LocalDataScope> _flattenLocalDataScopes(
    List<SyncModuleRegistration> modules,
    SyncRuntimeContributions extras,
    List<String> errors,
  ) {
    final List<LocalDataScope> result = <LocalDataScope>[];
    final Set<String> seenIds = <String>{};

    for (final SyncModuleRegistration module in modules) {
      final LocalDataScope scope = module.localDataScope;
      if (!seenIds.add(scope.id)) {
        errors.add(
          'module "${module.moduleId}".localDataScope: '
          'duplicate scope id "${scope.id}".',
        );
      }
      result.add(scope);
    }

    for (int i = 0; i < extras.localDataScopes.length; i++) {
      final LocalDataScope scope = extras.localDataScopes[i];
      if (!seenIds.add(scope.id)) {
        errors.add(
          'extraContributions.localDataScopes[$i]: '
          'duplicate scope id "${scope.id}".',
        );
      }
      result.add(scope);
    }

    return List<LocalDataScope>.unmodifiable(result);
  }

  static RebuildGraph? _buildRebuildGraph(
    List<SyncModuleRegistration> modules,
    SyncRuntimeContributions extras,
    List<String> errors,
  ) {
    final List<AnyRebuildGraphNode> nodes = <AnyRebuildGraphNode>[];
    final Set<String> seenTableNames = <String>{};

    for (final SyncModuleRegistration module in modules) {
      final RebuildGraph graph = module.rebuildGraph;
      for (final AnyRebuildGraphNode node in graph.allNodes) {
        if (!seenTableNames.add(node.tableName)) {
          errors.add(
            'module "${module.moduleId}".rebuildGraph: '
            'duplicate tableName "${node.tableName}".',
          );
        }
        nodes.add(node);
      }
    }

    if (nodes.isEmpty && extras.rebuildEdges.isEmpty) {
      return null;
    }

    final List<AnyRebuildGraphEdge> edges = <AnyRebuildGraphEdge>[
      for (final SyncModuleRegistration module in modules)
        ...module.rebuildGraph.allEdges,
      ...extras.rebuildEdges,
    ];

    try {
      return RebuildGraph(nodes: nodes, edges: edges);
    } on StateError catch (error) {
      errors.add('rebuildGraph: ${error.message}');
      return null;
    }
  }

  static void _validateFeatureDependencies({
    required SyncStores stores,
    required SyncChangeApplicationConfig changeApplication,
    required List<StaleConflictProfile> staleConflictProfiles,
    required SyncConflictResolution conflictResolution,
    required List<String> errors,
  }) {
    final bool rebuildInstructionsAreNoop =
        stores.rebuildInstructions is NoopSyncRebuildInstructionStore;

    if (changeApplication.deleteRebuild is SyncDeleteRebuildEnabled &&
        rebuildInstructionsAreNoop) {
      errors.add(
        'changeApplication.deleteRebuild enabled but stores.rebuildInstructions '
        'is a NoopSyncRebuildInstructionStore.',
      );
    }

    final bool conflictResolverNeedsInstructions = switch (conflictResolution) {
      SyncConflictResolutionDisabled() => false,
      SyncConflictResolutionCustom() => false,
      SyncConflictResolutionAuto() || SyncConflictResolutionDefaults() =>
          staleConflictProfiles.any(
            (StaleConflictProfile profile) => profile.requiresRebuildInstructions,
          ),
    };

    if (conflictResolverNeedsInstructions && rebuildInstructionsAreNoop) {
      errors.add(
        'conflictResolution auto/defaults requires rebuild instructions '
        'because at least one stale profile has requiresRebuildInstructions=true, '
        'but stores.rebuildInstructions is a NoopSyncRebuildInstructionStore.',
      );
    }
  }

  static void _validateBootstrapReplaceClient({
    required SyncBootstrapReplaceClient? bootstrapReplaceClient,
    required RebuildGraph? rebuildGraph,
    required List<String> errors,
  }) {
    if (bootstrapReplaceClient == null) {
      return;
    }

    if (rebuildGraph == null || rebuildGraph.allNodes.isEmpty) {
      errors.add(
        'bootstrapReplaceClient provided but no rebuild graph is available. '
        'A non-empty rebuild graph is required to build the snapshot.',
      );
    }
  }

  static ServerChangeApplier _buildChangeApplier({
    required List<SyncTableChangeHandler> handlers,
    required SyncChangeApplicationConfig config,
    required SyncStores stores,
    required RebuildGraph? rebuildGraph,
  }) {
    final DeleteRebuildPlanner? planner = switch (config.deleteRebuild) {
      SyncDeleteRebuildDisabled() => null,
      SyncDeleteRebuildEnabled() => rebuildGraph == null
          ? null
          : GraphDeleteRebuildPlanner(graph: rebuildGraph),
    };

    return CompositeServerChangeApplier(
      handlers: handlers,
      decisionPolicy: config.decisionPolicy ?? const AlwaysApplyServerChangeDecisionPolicy(),
      deleteRebuildPlanner: planner,
      rebuildInstructionStore: stores.rebuildInstructions,
    );
  }
}
