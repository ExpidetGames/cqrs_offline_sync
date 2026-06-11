import 'dart:convert';
import 'dart:io';

import 'package:yaml/yaml.dart';

import 'utils.dart';

/// Parses a YAML file into a serialisable JSON-backed map.
Map<dynamic, dynamic> _yamlToJsonMap(String yamlString) {
  return jsonDecode(jsonEncode(loadYaml(yamlString))) as Map<dynamic, dynamic>;
}

/// Holds the contents of `sync_config.yaml`.
class SyncConfig {
  final String syncRoot;
  final String projectPackage;
  final String? backendRoot;
  final List<SyncModuleConfig> modules;

  SyncConfig({
    required this.syncRoot,
    required this.projectPackage,
    this.backendRoot,
    this.modules = const [],
  });

  factory SyncConfig.fromMap(Map<dynamic, dynamic> map) {
    final modulesMap = map['modules'] as Map<dynamic, dynamic>?;
    final modules = <SyncModuleConfig>[];
    if (modulesMap != null) {
      for (final entry in modulesMap.entries) {
        modules.add(SyncModuleConfig.fromMap(
          entry.key as String,
          entry.value as Map<dynamic, dynamic>,
        ));
      }
    }
    return SyncConfig(
      syncRoot: map['sync_root'] as String? ?? 'lib/sync',
      projectPackage: map['project_package'] as String? ?? 'my_app',
      backendRoot: map['backend_root'] as String?,
      modules: modules,
    );
  }

  Map<String, dynamic> toMap() {
    final map = <String, dynamic>{
      'sync_root': syncRoot,
      'project_package': projectPackage,
    };
    if (backendRoot != null) {
      map['backend_root'] = backendRoot;
    }
    if (modules.isNotEmpty) {
      map['modules'] = <String, dynamic>{
        for (final m in modules) m.moduleId: m.toMap(),
      };
    }
    return map;
  }

  Future<void> write(File file) async {
    final buffer = StringBuffer()
      ..writeln('# Auto-generated sync configuration')
      ..writeln('# Do not edit manually unless you know what you are doing.')
      ..writeln()
      ..writeln('sync_root: $syncRoot')
      ..writeln('project_package: $projectPackage');
    if (backendRoot != null) {
      buffer.writeln('backend_root: $backendRoot');
    }
    if (modules.isNotEmpty) {
      buffer.writeln('modules:');
      for (final m in modules) {
        buffer.writeln('  ${m.moduleId}:');
        buffer.writeln('    module_id: ${m.moduleId}');
        buffer.writeln('    database_class: ${m.databaseClass}');
      }
    }
    await file.writeAsString(buffer.toString());
  }
}

class SyncModuleConfig {
  final String moduleId;
  final String databaseClass;

  SyncModuleConfig({
    required this.moduleId,
    required this.databaseClass,
  });

  factory SyncModuleConfig.fromMap(String key, Map<dynamic, dynamic> map) {
    return SyncModuleConfig(
      moduleId: map['module_id'] as String? ?? key,
      databaseClass: map['database_class'] as String? ?? '${_toPascalCase(key)}Database',
    );
  }

  Map<String, dynamic> toMap() => <String, dynamic>{
    'module_id': moduleId,
    'database_class': databaseClass,
  };
}

String _toPascalCase(String input) {
  final parts = input.split(RegExp(r'[_\-]+'));
  return parts.map((s) => s.isEmpty ? '' : s[0].toUpperCase() + s.substring(1)).join('');
}

/// Reads `sync_config.yaml` from the current directory or walks up.
SyncConfig? readSyncConfig([String? explicitPath]) {
  File? file;
  if (explicitPath != null) {
    file = File(explicitPath);
  } else {
    file = findSyncConfig(Directory.current);
  }
  if (file == null || !file.existsSync()) return null;
  final content = file.readAsStringSync();
  final map = _yamlToJsonMap(content);
  return SyncConfig.fromMap(map);
}
