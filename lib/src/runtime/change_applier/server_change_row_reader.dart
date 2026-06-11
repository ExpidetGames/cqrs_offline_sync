import '../../protocol/server_change.dart';

/// Utility for type-safe reading of fields from server feed change row payloads.
///
/// Provides strict parsing of required fields from the untyped
/// `Map<String, dynamic>` row payload in [UpsertServerChange].
///
/// Supports field aliases to accommodate wire-format variations
/// (e.g. `fromTerm` / `from` for the same column).
class ServerChangeRowReader {
  const ServerChangeRowReader(this.change);

  final ServerChange change;

  /// Returns the raw row map, or throws if the change is a delete.
  Map<String, dynamic> requireRow() {
    switch (change) {
      case UpsertServerChange(:final Map<String, dynamic> row):
        return row;
      case DeleteServerChange():
        throw FormatException(
          'Missing row payload for ${change.table} ${change.operation}.',
        );
    }
  }

  /// Reads a required [String] value by [key] or any of [aliases].
  String requireString(
    String key, {
    List<String> aliases = const <String>[],
    bool allowEmpty = false,
  }) {
    final Object? rawValue = _readValue(key, aliases);
    if (rawValue is String && (allowEmpty || rawValue.trim().isNotEmpty)) {
      return rawValue;
    }

    throw FormatException('Missing or invalid "$key" in ${change.table} row.');
  }

  /// Reads a required [int] value by [key] or any of [aliases].
  int requireInt(String key, {List<String> aliases = const <String>[]}) {
    final Object? rawValue = _readValue(key, aliases);
    if (rawValue is int) {
      return rawValue;
    }
    if (rawValue is num) {
      return rawValue.toInt();
    }
    if (rawValue is String) {
      final int? parsed = int.tryParse(rawValue);
      if (parsed != null) {
        return parsed;
      }
    }

    throw FormatException('Missing or invalid "$key" in ${change.table} row.');
  }

  /// Reads a required [DateTime] value (UTC) by [key] or any of [aliases].
  DateTime requireDateTime(
    String key, {
    List<String> aliases = const <String>[],
  }) {
    final Object? rawValue = _readValue(key, aliases);
    if (rawValue is DateTime) {
      return rawValue.toUtc();
    }
    if (rawValue is String) {
      final DateTime? parsed = DateTime.tryParse(rawValue);
      if (parsed != null) {
        return parsed.toUtc();
      }
    }

    throw FormatException('Missing or invalid "$key" in ${change.table} row.');
  }

  Object? _readValue(String key, List<String> aliases) {
    final Map<String, dynamic> row = requireRow();

    if (row.containsKey(key)) {
      return row[key];
    }

    for (final String alias in aliases) {
      if (row.containsKey(alias)) {
        return row[alias];
      }
    }

    return null;
  }
}
