import 'create_command.dart' show Field;

/// README content for the `commands/` folder.
const String commandsReadme = '''# Sync Commands

Each module has its own command folder (`<module>_commands/`).

Inside, every command is a Freezed class that extends `SyncCommand`, plus a codec.

## Adding a command

1. Create a new `.dart` file under `commands/<module>_commands/`
2. Run `cqrs_sync create command <module> <entity> <operation> --fields "..."`
3. Implement `build_runner` to generate `.freezed.dart` and `.g.dart`
4. The module registration is regenerated automatically
''';

const String changeApplierReadme = '''# Sync Change Applier

Register per-table `SyncTableChangeHandler` implementations here, organised by module.

Each handler declares the `tableName` it covers and handles `UpsertServerChange` / `DeleteServerChange`.
''';

const String conflictProfilesReadme = '''# Stale Conflict Profiles

Each module has a dedicated folder containing its profiles.

A profile binds a `commandType` to snapshot-reading logic and a resolution policy, used when the server rejects a command as stale.

Subfolders:
- `models/`   → rebuild-context classes
- `snapshots/`  → snapshot DTOs for `ensurePresent` policies
''';

const String localDataReadme = '''# Local Data Scopes

One `LocalDataScope` per module lives here.

It answers two questions:
1. `hasData()`  — does this module hold any unsynced local rows?
2. `clear()`    — deletes all local module data (used during auth reset flows).
''';

const String rebuildReadme = '''# Rebuild Graphs

A `RebuildGraph` per module describes the entity hierarchy, parent-child edges, and snapshot projections.

Used by:
- `GraphDeleteRebuildPlanner` when a delete change arrives.
- `SyncBootstrapReplaceService` for device-wins snapshot building.
''';

const String storesReadme = '''# Sync Stores

Concrete implementations of `SyncOutboxStore`, `SyncStateStore`, `SyncConflictLogStore`, and `SyncRebuildInstructionStore` belong to the host app and are wired in `sync_runtime.dart`.

This folder is README-only during init. Add your store files here once you pick a persistence layer (Drift, Hive, Isar, etc.).
''';

const String syncRuntimeReadme = '''# Sync Runtime

The host app composes all sync modules, stores, transport, and policies into a single `CqrsSyncRuntime` in `sync_runtime.dart`.

## Quick start

```dart
import 'package:my_app/sync/sync_runtime.dart';

final runtime = buildSyncRuntime(
  modules: [notesSyncModule, tasksSyncModule],
  stores: mySyncStores,
  transactionRunner: myDatabase.transactionRunner,
  transport: mySyncTransport,
);

// Pull changes / push pending commands
await runtime.runner.runOnce(SyncTriggerReason.manual);

// Domain write
await runtime.createWriteUnitOfWork().runVoidWithCommand(
  writeLocal: () async { /* local db write */ },
  command: myCommand,
);
```

## Repository guidance

Repositories should depend on `SyncWriteUnitOfWork`, not `SyncCommandWriter`, except for advanced cases.
''';

/// Template for `sync_runtime.dart`.
String syncRuntimeTemplate({required String projectPackage}) {
  return """// Composes app sync modules, stores, transport, and policies into a
// `CqrsSyncRuntime`. Host apps call `buildSyncRuntime(...)` once at startup
// and keep the resulting runtime in their DI/service layer.

import 'package:cqrs_offline_sync/cqrs_offline_sync.dart';

/// Builds the host app's sync runtime.
///
/// Required dependencies ([modules], [stores], [transactionRunner], [transport])
/// are provided by the host. Optional config parameters use sensible defaults.
CqrsSyncRuntime buildSyncRuntime({
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
}) {
  return CqrsSyncRuntime.compose(
    modules: modules,
    stores: stores,
    transactionRunner: transactionRunner,
    transport: transport,
    extraContributions: extraContributions,
    changeApplication: changeApplication,
    conflictResolution: conflictResolution,
    opIdGenerator: opIdGenerator,
    clock: clock,
    resyncHandler: resyncHandler,
  );
}
""";
}

/// Template for `module_sync_registration.dart`.
String moduleRegistrationTemplate({
  required String moduleName,
  required String pascalModule,
  required String dbClass,
}) {
  return """import 'package:cqrs_offline_sync/cqrs_offline_sync.dart';
import 'package:${_projectPlaceholder}/sync/runtime/local_data/${moduleName}_local_data_scope.dart';
import 'package:${_projectPlaceholder}/sync/runtime/conflict/profiles/${moduleName}/${moduleName}_stale_conflict_profiles.dart';
import 'package:${_projectPlaceholder}/sync/runtime/rebuild/${moduleName}_rebuild_graph.dart';

// TODO: add command imports here

class ${pascalModule}SyncRegistration extends SyncModuleRegistration {
  ${pascalModule}SyncRegistration({required $dbClass database})
      : _database = database;

  final $dbClass _database;

  @override
  String get moduleId => '$moduleName';

  @override
  List<AnyCommandCodec> get commandCodecs =>
      // TODO: add command codecs
      List<AnyCommandCodec>.unmodifiable(<AnyCommandCodec>[]);

  @override
  List<SyncTableChangeHandler> get tableChangeHandlers =>
      // TODO: add table change handlers
      List<SyncTableChangeHandler>.unmodifiable(<SyncTableChangeHandler>[]);

  @override
  List<StaleConflictProfile> get staleConflictProfiles =>
      build${pascalModule}StaleConflictProfiles(_database);

  @override
  LocalDataScope get localDataScope =>
      ${pascalModule}LocalDataScope(_database);

  @override
  RebuildGraph get rebuildGraph =>
      build${pascalModule}RebuildGraph(_database);
}
""";
}

/// Template for `module_local_data_scope.dart`.
String localDataScopeTemplate({
  required String moduleName,
  required String pascalModule,
  required String dbClass,
}) {
  return """import 'package:cqrs_offline_sync/cqrs_offline_sync.dart';
import 'package:${_projectPlaceholder}/sync/database/$dbClass.dart';

class ${pascalModule}LocalDataScope implements LocalDataScope {
  const ${pascalModule}LocalDataScope(this._database);

  final $dbClass _database;

  @override
  String get id => '${moduleName}';

  @override
  Future<bool> hasData() async {
    // TODO: check each table in your module
    return false;
  }

  @override
  Future<void> clear() async {
    // TODO: delete all module tables in dependency order
  }
}
""";
}

/// Template for `module_rebuild_graph.dart`.
String rebuildGraphTemplate({
  required String moduleName,
  required String pascalModule,
}) {
  return """import 'package:cqrs_offline_sync/cqrs_offline_sync.dart';
// TODO: import module database and command payloads

RebuildGraph build${pascalModule}RebuildGraph(/* database */) {
  return RebuildGraph(
    nodes: <AnyRebuildGraphNode>[
      // TODO: add RebuildGraphNode for each table
    ],
    edges: <AnyRebuildGraphEdge>[
      // TODO: add RebuildGraphEdge for each parent-child relationship
    ],
  );
}
""";
}

/// Template for `module_stale_conflict_profiles.dart`.
String staleConflictProfilesTemplate({
  required String moduleName,
  required String pascalModule,
  required String dbClass,
}) {
  return """import 'package:cqrs_offline_sync/cqrs_offline_sync.dart';
// TODO: import module database

List<StaleConflictProfile> build${pascalModule}StaleConflictProfiles($dbClass database) {
  return <StaleConflictProfile>[
    // TODO: add one profile per command type
  ];
}
""";
}

/// Template for a single command Dart file.
String commandDartTemplate({
  required String moduleName,
  required String projectPackage,
  required String operationName,
  required String entityName,
  required List<Field> fields,
  required String commandType,
  required String aggregate,
  required String pascalOp,
  required String pascalEntity,
}) {
  final className = '${pascalOp}${pascalEntity}Payload';
  final fieldLines = fields.map((f) {
    final dartType = _mapDartType(f.type);
    return '    required $dartType ${f.name},';
  }).join('\n');

  final partSnake = '${_toSnakeCase(operationName)}_${_toSnakeCase(entityName)}_command';

  final buffer = StringBuffer()
    ..writeln("import 'package:freezed_annotation/freezed_annotation.dart';")
    ..writeln("import 'package:cqrs_offline_sync/cqrs_offline_sync.dart';")
    ..writeln()
    ..writeln("part '$partSnake.freezed.dart';")
    ..writeln("part '$partSnake.g.dart';")
    ..writeln()
    ..writeln('@freezed')
    ..writeln('abstract class $className')
    ..writeln('    with _\$$className')
    ..writeln('    implements SyncCommand {')
    ..writeln('  const $className._();')
    ..writeln()
    ..writeln('  const factory $className({')
    ..writeln(fieldLines)
    ..writeln('  }) = _$className;')
    ..writeln()
    ..writeln("  static const String type = '${commandType}';")
    ..writeln("  static const String aggregate = '${aggregate}';")
    ..writeln()
    ..writeln('  @override')
    ..writeln('  String get commandType => type;')
    ..writeln()
    ..writeln('  @override')
    ..writeln('  String get aggregateType => aggregate;')
    ..writeln()
    ..writeln('  factory $className.fromJson(Map<String, dynamic> json) =>')
    ..writeln('      _\$${className}FromJson(json);')
    ..writeln('}')
    ..writeln()
    ..writeln('final CommandPayloadCodec<$className> ${_lcFirst(className)}Codec =')
    ..writeln('    CommandPayloadCodec<$className>(\n')
    ..writeln('      commandType: $className.type,\n')
    ..writeln('      aggregateType: $className.aggregate,\n')
    ..writeln('      payloadType: $className,\n')
    ..writeln('      fromJson: $className.fromJson,\n')
    ..writeln('      toJson: (payload) => payload.toJson(),\n')
    ..writeln('    );');

  return buffer.toString();
}

String _toSnakeCase(String input) {
  return input
      .replaceAllMapped(RegExp(r'[A-Z]'), (m) => '_${m.group(0)!.toLowerCase()}')
      .replaceFirst(RegExp(r'^_'), '');
}

String _mapDartType(String raw) {
  switch (raw.toLowerCase()) {
    case 'string':
      return 'String';
    case 'int':
      return 'int';
    case 'double':
      return 'double';
    case 'bool':
      return 'bool';
    case 'datetime':
      return 'DateTime';
    case 'json':
    case 'map':
      return 'Map<String, dynamic>';
    case 'list':
      return 'List<String>';
    default:
      return raw;
  }
}

String _lcFirst(String s) => s.isEmpty ? s : s[0].toLowerCase() + s.substring(1);

/// TypeScript command payload template.
String commandTsTemplate({
  required String commandType,
  required String aggregate,
  required List<Field> fields,
  required String pascalOp,
  required String pascalEntity,
}) {
  final fieldsTs = fields.map((f) {
    final tsType = _mapTsType(f.type);
    return '    readonly ${f.name}: $tsType;';
  }).join('\n');

  return """import type { CommandPayloadCodec } from "../../../../core/command_codec.ts";
import {
    parseCommandKey,
    parseCommandPayloadObject,
} from "../../../../core/command_codec.ts";
import type { SyncCommand } from "../../../../core/sync_command.ts";

export interface ${pascalOp}${pascalEntity}Payload extends SyncCommand {
$fieldsTs
}

export const ${pascalOp.toLowerCase()}${pascalEntity}CommandType = "${commandType}";
export const ${pascalOp.toLowerCase()}${pascalEntity}AggregateType = "${aggregate}";

export const ${pascalOp.toLowerCase()}${pascalEntity}PayloadCodec: CommandPayloadCodec<${pascalOp}${pascalEntity}Payload> = {
    commandType: ${pascalOp.toLowerCase()}${pascalEntity}CommandType,
    aggregateType: ${pascalOp.toLowerCase()}${pascalEntity}AggregateType,
    parsePayload(payload: unknown): ${pascalOp}${pascalEntity}Payload {
        const payloadObject: Record<string, unknown> = parseCommandPayloadObject(
            payload,
            "command.payload",
        );

        return {
            commandType: ${pascalOp.toLowerCase()}${pascalEntity}CommandType,
            aggregateType: ${pascalOp.toLowerCase()}${pascalEntity}AggregateType,
            // TODO: parse fields
        };
    },
};
""";
}

/// TypeScript handler stub template.
String handlerTsTemplate({
  required String commandType,
  required String pascalOp,
  required String pascalEntity,
}) {
  return """import type { CommandExecutionContext } from "../../../../engine/command_execution_context.ts";
import type { CommandExecutionOutcome } from "../../../../engine/command_engine_types.ts";
import type { CommandEnvelope } from "../../../../core/command_envelope.ts";
import type { CommandHandler } from "../../../../handlers/command_handler.ts";
import {
    ${pascalOp.toLowerCase()}${pascalEntity}CommandType,
    type ${pascalOp}${pascalEntity}Payload,
} from "./${_toSnakeCase(pascalOp)}_${_toSnakeCase(pascalEntity)}_command.ts";

export class ${pascalOp}${pascalEntity}CommandHandler implements CommandHandler<${pascalOp}${pascalEntity}Payload> {
    readonly commandType: string = ${pascalOp.toLowerCase()}${pascalEntity}CommandType;

    async execute(
        envelope: CommandEnvelope<${pascalOp}${pascalEntity}Payload>,
        context: CommandExecutionContext,
    ): Promise<CommandExecutionOutcome> {
        // TODO: implement domain mutation
        return { kind: "applied", reasonCode: null, feedChanges: [] };
    }
}
""";
}

/// TypeScript stale policy stub template.
String stalePolicyTsTemplate({
  required String commandType,
  required String pascalOp,
  required String pascalEntity,
}) {
  return """import { RowSinceOccurredAtStalePolicy } from "../../../../stale/row_since_occurred_at_stale_policy.ts";
import {
    ${pascalOp.toLowerCase()}${pascalEntity}CommandType,
    type ${pascalOp}${pascalEntity}Payload,
} from "./${_toSnakeCase(pascalOp)}_${_toSnakeCase(pascalEntity)}_command.ts";

// TODO: define table name and row reader
export const ${_toSnakeCase(pascalOp)}${pascalEntity}StalePolicy = new RowSinceOccurredAtStalePolicy<${pascalOp}${pascalEntity}Payload>({
    commandType: ${pascalOp.toLowerCase()}${pascalEntity}CommandType,
    tableName: "TODO_table_name",
    reasonCode: null,
    reason: "TODO stale reason",
    getRowId: (envelope) => envelope.payload.id,
    readLatestRow: async (params) => {
        // TODO: query latest row
        return null;
    },
});
""";
}

/// TypeScript definition binding template.
String definitionTsTemplate({
  required String pascalOp,
  required String pascalEntity,
}) {
  final base = '${_toSnakeCase(pascalOp)}_${_toSnakeCase(pascalEntity)}';
  return """import {
    defineCommand,
    type CommandDefinition,
} from "../../../../catalog/command_definition.ts";
import {
    ${base}PayloadCodec,
    type ${pascalOp}${pascalEntity}Payload,
} from "./${base}_command.ts";
import { ${pascalOp}${pascalEntity}CommandHandler } from "./${base}_handler.ts";
import { ${base}StalePolicy } from "./${base}_stale_policy.ts";

export const ${base}CommandDefinition: CommandDefinition<
    ${pascalOp}${pascalEntity}Payload
> = defineCommand<${pascalOp}${pascalEntity}Payload>({
    codec: ${base}PayloadCodec,
    handler: new ${pascalOp}${pascalEntity}CommandHandler(),
    stalePolicy: ${base}StalePolicy,
});
""";
}

String _mapTsType(String raw) {
  switch (raw.toLowerCase()) {
    case 'string':
      return 'string';
    case 'int':
      return 'number';
    case 'double':
      return 'number';
    case 'bool':
      return 'boolean';
    case 'datetime':
      return 'Date';
    case 'json':
    case 'map':
      return 'Record<string, unknown>';
    case 'list':
      return 'string[]';
    default:
      return raw;
  }
}

const String _projectPlaceholder = 'lateinorum_package_name_placeholder';
