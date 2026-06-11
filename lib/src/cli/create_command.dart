import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:path/path.dart' as p;

import 'sync_config.dart';
import 'templates.dart';
import 'utils.dart';

/// `cqrs_sync create` — creates modules, commands, and other boilerplate.
class CreateCommand extends Command<void> {
  @override
  final String name = 'create';

  @override
  final String description = 'Create modules, commands, and other boilerplate.';

  CreateCommand() {
    addSubcommand(CreateModuleCommand());
    addSubcommand(CreateCommandSubCommand());
  }

  @override
  Future<void> run() async {
    // create has sub-commands only
  }
}

class CreateModuleCommand extends Command<void> {
  @override
  final String name = 'module';

  @override
  final String description = 'Register a new module and generate stubs.';

  CreateModuleCommand() {
    argParser.addOption(
      'database-class',
      abbr: 'd',
      help: 'The Dart database class name for this module (e.g. LatinTextsDatabase).',
    );
  }

  @override
  Future<void> run() async {
    final config = readSyncConfig();
    if (config == null) {
      stderr.writeln('No sync_config.yaml found. Run `cqrs_sync init` first.');
      exitCode = 1;
      return;
    }

    final moduleName = argResults!.rest.isEmpty
        ? null
        : argResults!.rest.first;

    if (moduleName == null || moduleName.isEmpty) {
      stderr.writeln('Usage: cqrs_sync create module <module-name>');
      exitCode = 1;
      return;
    }

    final existing = config.modules.where((m) => m.moduleId == moduleName);
    if (existing.isNotEmpty) {
      stderr.writeln('Module "$moduleName" already exists in sync_config.yaml.');
      exitCode = 1;
      return;
    }

    final pascal = toPascalCase(moduleName);
    final dbClass = argResults!['database-class'] as String? ?? '${pascal}Database';

    final module = SyncModuleConfig(
      moduleId: moduleName,
      databaseClass: dbClass,
    );

    config.modules.add(module);
    final configFile = File('sync_config.yaml');
    if (configFile.existsSync()) {
      await config.write(configFile);
    }
    stdout.writeln('Added module "$moduleName" to sync_config.yaml');

    final baseDir = Directory(p.join(Directory.current.path, config.syncRoot));

    // Module folders
    ensureDir(p.join(baseDir.path, 'commands', '${moduleName}_commands'));
    ensureDir(p.join(baseDir.path, 'runtime/change_applier', moduleName));
    ensureDir(p.join(baseDir.path, 'runtime/conflict/profiles', moduleName, 'models'));
    ensureDir(p.join(baseDir.path, 'runtime/conflict/profiles', moduleName, 'snapshots'));

    // Stub files
    final registrationPath = p.join(
      baseDir.path,
      '${moduleName}_sync_registration.dart',
    );
    if (!File(registrationPath).existsSync()) {
      File(registrationPath).writeAsStringSync(
        moduleRegistrationTemplate(
          moduleName: moduleName,
          pascalModule: pascal,
          dbClass: dbClass,
        ),
      );
      stdout.writeln('  Created ${registrationPath.replaceFirst(baseDir.path + '/', '')}');
    }

    final localScopePath = p.join(
      baseDir.path,
      'runtime/auth',
      '${moduleName}_local_data_scope.dart',
    );
    if (!File(localScopePath).existsSync()) {
      File(localScopePath).writeAsStringSync(
        localDataScopeTemplate(
          moduleName: moduleName,
          pascalModule: pascal,
          dbClass: dbClass,
        ),
      );
      stdout.writeln('  Created ${localScopePath.replaceFirst(baseDir.path + '/', '')}');
    }

    final rebuildGraphPath = p.join(
      baseDir.path,
      'runtime/rebuild',
      '${moduleName}_rebuild_graph.dart',
    );
    if (!File(rebuildGraphPath).existsSync()) {
      File(rebuildGraphPath).writeAsStringSync(
        rebuildGraphTemplate(
          moduleName: moduleName,
          pascalModule: pascal,
        ),
      );
      stdout.writeln('  Created ${rebuildGraphPath.replaceFirst(baseDir.path + '/', '')}');
    }

    final staleProfilesPath = p.join(
      baseDir.path,
      'runtime/conflict/profiles',
      moduleName,
      '${moduleName}_stale_conflict_profiles.dart',
    );
    if (!File(staleProfilesPath).existsSync()) {
      File(staleProfilesPath).writeAsStringSync(
        staleConflictProfilesTemplate(
          moduleName: moduleName,
          pascalModule: pascal,
          dbClass: dbClass,
        ),
      );
      stdout.writeln('  Created ${staleProfilesPath.replaceFirst(baseDir.path + '/', '')}');
    }
  }
}

class CreateCommandSubCommand extends Command<void> {
  @override
  final String name = 'command';

  @override
  final String description = 'Generate a sync command and update module registration.';

  CreateCommandSubCommand() {
    argParser
      ..addOption('fields',
          abbr: 'f',
          defaultsTo: '',
          help: 'Comma-separated fields, e.g. "title:String,body:String"')
      ..addFlag('backend',
          defaultsTo: true,
          help: 'Also generate backend TypeScript files.');
  }

  @override
  Future<void> run() async {
    final config = readSyncConfig();
    if (config == null) {
      stderr.writeln('No sync_config.yaml found. Run `cqrs_sync init` first.');
      exitCode = 1;
      return;
    }

    if (argResults!.rest.length < 3) {
      stderr.writeln('Usage: cqrs_sync create command <module> <entity> <operation> [--fields ...] [--no-backend]');
      exitCode = 1;
      return;
    }

    final moduleName = argResults!.rest[0];
    final entityName = argResults!.rest[1];
    final operationName = argResults!.rest[2];

    final moduleConfig = config.modules.firstWhere(
      (m) => m.moduleId == moduleName,
      orElse: () => throw StateError('Module "$moduleName" not found in sync_config.yaml.'),
    );

    final baseDir = Directory(p.join(Directory.current.path, config.syncRoot));

    // --- Frontend Dart file ---
    final pascalOp = toPascalCase(operationName);
    final pascalEntity = toPascalCase(entityName);
    final pascalModule = toPascalCase(moduleName);
    final aggregate = toSnakeCase(entityName);
    final commandType = '${toSnakeCase(moduleName)}.${toSnakeCase(operationName)}_${toSnakeCase(entityName)}';

    final fieldTokens = (argResults!['fields'] as String)
        .split(',')
        .where((s) => s.trim().isNotEmpty)
        .map((s) {
      final parts = s.trim().split(':');
      if (parts.length != 2) {
        stderr.writeln('Invalid field spec: "$s". Expected "name:Type".');
        exitCode = 1;
        throw StateError('Invalid field spec');
      }
      return Field(name: parts[0].trim(), type: parts[1].trim());
    });

    final fields = <Field>[
      Field(name: 'id', type: 'String'),
      ...fieldTokens,
    ];

    final commandFileName = '${toSnakeCase(operationName)}_${toSnakeCase(entityName)}_command.dart';
    final commandDir = Directory(p.join(baseDir.path, 'commands', '${moduleName}_commands'));
    commandDir.createSync(recursive: true);
    final commandFile = File(p.join(commandDir.path, commandFileName));

    commandFile.writeAsStringSync(
      commandDartTemplate(
        moduleName: moduleName,
        projectPackage: config.projectPackage,
        operationName: operationName,
        entityName: entityName,
        fields: fields,
        commandType: commandType,
        aggregate: aggregate,
        pascalOp: pascalOp,
        pascalEntity: pascalEntity,
      ),
    );
    stdout.writeln('Created commands/${moduleName}_commands/$commandFileName');

    // --- Regenerate registration ---
    final regPath = p.join(baseDir.path, '${moduleName}_sync_registration.dart');
    if (File(regPath).existsSync()) {
      await _regenerateRegistration(
        regPath: regPath,
        config: config,
        moduleName: moduleName,
        moduleConfig: moduleConfig,
        pascalModule: pascalModule,
        baseDir: baseDir,
      );
      stdout.writeln('Regenerated ${moduleName}_sync_registration.dart');
    } else {
      stderr.writeln('Warning: No registration file found at ${moduleName}_sync_registration.dart. Skipping regeneration.');
    }

    // --- Backend TS files ---
    final generateBackend = argResults!['backend'] as bool;
    if (generateBackend && config.backendRoot != null) {
      await _generateBackendFiles(
        config: config,
        moduleName: moduleName,
        entityName: entityName,
        operationName: operationName,
        fields: fields,
        commandType: commandType,
        aggregate: aggregate,
        pascalOp: pascalOp,
        pascalEntity: pascalEntity,
      );
    }
  }

  Future<void> _regenerateRegistration({
    required String regPath,
    required SyncConfig config,
    required String moduleName,
    required SyncModuleConfig moduleConfig,
    required String pascalModule,
    required Directory baseDir,
  }) async {
    final commandsDir = Directory(p.join(baseDir.path, 'commands', '${moduleName}_commands'));
    if (!commandsDir.existsSync()) return;

    final files = commandsDir
        .listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart') && !f.path.endsWith('.freezed.dart') && !f.path.endsWith('.g.dart'))
        .toList()
      ..sort((a, b) => p.basename(a.path).compareTo(p.basename(b.path)));

    final imports = <String, String>{};
    final codecList = <String>[];

    final importRoot = config.syncRoot.startsWith('lib/') ? config.syncRoot.substring(4) : config.syncRoot;

    for (final file in files) {
      final basename = p.basename(file.path);
      final importPath = 'package:${config.projectPackage}/$importRoot/commands/${moduleName}_commands/$basename';
      final content = file.readAsStringSync();

      final classMatch = RegExp(r'class\s+(\w+)Payload\s+').firstMatch(content);
      // Derive the base name from the file, e.g. create_text_command.dart => CreateTextPayload
      final fileParts = basename.replaceAll('_command.dart', '').split('_');
      final guessedClass = fileParts
          .map((s) => s.isEmpty ? '' : s[0].toUpperCase() + s.substring(1))
          .join('') + 'Payload';
      final className = classMatch?.group(1) ?? guessedClass;

      final codecMatch = RegExp(r'final\s+CommandPayloadCodec<\w+>\s+(\w+)\s*=')
          .firstMatch(content);
      // Codec naming convention: <camelCase class name> without "Payload" + "PayloadCodec"
      final lowerFirst = className[0].toLowerCase() + className.substring(1);
      final guessedCodec = lowerFirst.replaceAll('Payload', 'PayloadCodec');
      final codecName = codecMatch?.group(1) ?? guessedCodec;

      imports[codecName] = importPath;
      codecList.add(codecName);
    }

    final importLines = imports.entries
        .map((e) => "import '${e.value}';")
        .toList()
      ..sort();

    final buffer = StringBuffer()
      ..writeln("import 'package:cqrs_offline_sync/cqrs_offline_sync.dart';")
      ..writeln("import 'package:${config.projectPackage}/$importRoot/runtime/auth/${moduleName}_local_data_scope.dart';")
      ..writeln("import 'package:${config.projectPackage}/$importRoot/runtime/rebuild/${moduleName}_rebuild_graph.dart';")
      ..writeln("import 'package:${config.projectPackage}/$importRoot/runtime/conflict/profiles/${moduleName}/${moduleName}_stale_conflict_profiles.dart';")
      ..writeln();
    for (final line in importLines) {
      buffer.writeln(line);
    }

    buffer
      ..writeln()
      ..writeln('class ${pascalModule}SyncRegistration extends SyncModuleRegistration {')
      ..writeln('  ${pascalModule}SyncRegistration({required ${moduleConfig.databaseClass} database})')
      ..writeln('      : _database = database;')
      ..writeln()
      ..writeln('  final ${moduleConfig.databaseClass} _database;')
      ..writeln()
      ..writeln("  @override \n  String get moduleId => '${moduleName}';")
      ..writeln()
      ..writeln('  @override \n  List<AnyCommandCodec> get commandCodecs =>')
      ..writeln('      List<AnyCommandCodec>.unmodifiable(<AnyCommandCodec>[');
    for (final codec in codecList) {
      buffer.writeln('        $codec,');
    }
    buffer
      ..writeln('      ]);')
      ..writeln()
      ..writeln('  @override \n  List<SyncTableChangeHandler> get tableChangeHandlers =>')
      ..writeln('      // TODO: add table change handlers')
      ..writeln('      List<SyncTableChangeHandler>.unmodifiable(<SyncTableChangeHandler>[]);')
      ..writeln()
      ..writeln('  @override \n  List<StaleConflictProfile> get staleConflictProfiles =>')
      ..writeln('      build${pascalModule}StaleConflictProfiles(_database);')
      ..writeln()
      ..writeln('  @override \n  LocalDataScope get localDataScope =>')
      ..writeln('      ${pascalModule}LocalDataScope(_database);')
      ..writeln()
      ..writeln('  @override \n  RebuildGraph get rebuildGraph =>')
      ..writeln('      build${pascalModule}RebuildGraph(_database);')
      ..writeln('}');

    File(regPath).writeAsStringSync(buffer.toString());
  }

  Future<void> _generateBackendFiles({
    required SyncConfig config,
    required String moduleName,
    required String entityName,
    required String operationName,
    required List<Field> fields,
    required String commandType,
    required String aggregate,
    required String pascalOp,
    required String pascalEntity,
  }) async {
    final backendRoot = config.backendRoot!;
    final entityDir = Directory(p.join(
      backendRoot,
      'commands',
      'modules',
      moduleName,
      toSnakeCase(entityName),
      '${toSnakeCase(operationName)}_${toSnakeCase(entityName)}',
    ));
    ensureDir(entityDir.path);

    final baseName = '${toSnakeCase(operationName)}_${toSnakeCase(entityName)}';

    File(p.join(entityDir.path, '${baseName}_command.ts'))
        .writeAsStringSync(commandTsTemplate(
      commandType: commandType,
      aggregate: aggregate,
      fields: fields,
      pascalOp: pascalOp,
      pascalEntity: pascalEntity,
    ));

    File(p.join(entityDir.path, '${baseName}_handler.ts'))
        .writeAsStringSync(handlerTsTemplate(
      commandType: commandType,
      pascalOp: pascalOp,
      pascalEntity: pascalEntity,
    ));

    File(p.join(entityDir.path, '${baseName}_stale_policy.ts'))
        .writeAsStringSync(stalePolicyTsTemplate(
      commandType: commandType,
      pascalOp: pascalOp,
      pascalEntity: pascalEntity,
    ));

    File(p.join(entityDir.path, '${baseName}_definition.ts'))
        .writeAsStringSync(definitionTsTemplate(
      pascalOp: pascalOp,
      pascalEntity: pascalEntity,
    ));

    stdout.writeln('Generated backend files in ${entityDir.path}');
  }
}

class Field {
  final String name;
  final String type;
  Field({required this.name, required this.type});
}
