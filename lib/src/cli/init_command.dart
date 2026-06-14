import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:path/path.dart' as p;

import 'sync_config.dart';
import 'templates.dart';
import 'utils.dart';

/// `cqrs_sync init` — creates sync_config.yaml and the folder tree.
class InitCommand extends Command<void> {
  @override
  final String name = 'init';

  @override
  final String description = 'Initialize sync file structure for the project.';

  InitCommand() {
    argParser
      ..addOption('root',
          abbr: 'r',
          defaultsTo: 'lib/sync',
          help: 'Root directory for sync files.')
      ..addOption('project',
          abbr: 'p',
          defaultsTo: 'my_app',
          help: 'Dart package name used in imports.');
  }

  @override
  Future<void> run() async {
    final root = argResults!['root'] as String;
    final project = argResults!['project'] as String;

    final cwd = Directory.current;
    final configFile = File(p.join(cwd.path, 'sync_config.yaml'));

    if (configFile.existsSync()) {
      stderr.writeln('sync_config.yaml already exists. Aborting.');
      exitCode = 1;
      return;
    }

    final config = SyncConfig(
      syncRoot: root,
      projectPackage: project,
      backendRoot: null,
    );
    await config.write(configFile);
    stdout.writeln('Created sync_config.yaml');

    final baseDir = Directory(p.join(cwd.path, root));
    ensureDir(baseDir.path);

    // Top-level folders with READMEs
    _writeReadme(baseDir, 'commands', commandsReadme);
    _writeReadme(baseDir, 'runtime/change_applier', changeApplierReadme);
    _writeReadme(baseDir, 'runtime/conflict/profiles', conflictProfilesReadme);
    _writeReadme(baseDir, 'runtime/local_data', localDataReadme);
    _writeReadme(baseDir, 'runtime/rebuild', rebuildReadme);
    _writeReadme(baseDir, 'stores', storesReadme);

    // Root entrypoint and README
    final syncRuntimePath = p.join(baseDir.path, 'sync_runtime.dart');
    if (!File(syncRuntimePath).existsSync()) {
      File(syncRuntimePath).writeAsStringSync(
        syncRuntimeTemplate(projectPackage: project),
      );
      stdout.writeln('  Created ${root}/sync_runtime.dart');
    }

    final rootReadmePath = p.join(baseDir.path, 'README.md');
    if (!File(rootReadmePath).existsSync()) {
      File(rootReadmePath).writeAsStringSync(syncRuntimeReadme);
      stdout.writeln('  Created ${root}/README.md');
    }

    stdout.writeln('Sync file structure created under \u001b[34m$root\u001b[0m');
  }

  void _writeReadme(Directory base, String relativePath, String content) {
    final dir = Directory(p.join(base.path, relativePath));
    ensureDir(dir.path);
    final file = File(p.join(dir.path, 'README.md'));
    file.writeAsStringSync(content);
  }
}
