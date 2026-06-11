import 'dart:io';

import 'package:path/path.dart' as p;

/// Finds the `sync_config.yaml` by walking up from [startDir].
File? findSyncConfig(Directory startDir) {
  var dir = startDir.absolute;
  while (true) {
    final candidate = File(p.join(dir.path, 'sync_config.yaml'));
    if (candidate.existsSync()) return candidate;
    final parent = dir.parent;
    if (parent.path == dir.path) break;
    dir = parent;
  }
  return null;
}

/// Converts a string like 'my_module' or 'myModule' to PascalCase: 'MyModule'.
String toPascalCase(String input) {
  final parts = input.split(RegExp(r'[_\-]+'));
  return parts.map((s) => s.isEmpty ? '' : s[0].toUpperCase() + s.substring(1)).join('');
}

/// Converts a string like 'my_module' to snake_case: 'my_module'.
String toSnakeCase(String input) {
  return input.replaceAll(RegExp(r'[\-]+'), '_').toLowerCase();
}

/// Checks if a directory exists and creates it if not.
Directory ensureDir(String path) {
  final dir = Directory(path);
  if (!dir.existsSync()) dir.createSync(recursive: true);
  return dir;
}
