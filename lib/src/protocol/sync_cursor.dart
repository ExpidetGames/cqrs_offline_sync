/// Base class for strongly-typed numeric sync identifiers.
///
/// [SyncCursor] and [SyncEpoch] both extend this class and share comparison,
/// parsing, and equality logic. Values are stored as [String] and parsed to
/// [BigInt] for ordering.
sealed class SyncNumber<T extends SyncNumber<T>> implements Comparable<T> {
  const SyncNumber._(this.value, this.asBigInt);

  /// The raw string value.
  final String value;

  /// Parsed [BigInt] for ordering and comparison.
  final BigInt asBigInt;

  bool operator >(T other) => compareTo(other) > 0;
  bool operator >=(T other) => compareTo(other) >= 0;
  bool operator <(T other) => compareTo(other) < 0;
  bool operator <=(T other) => compareTo(other) <= 0;

  static BigInt _parseStringToBigInt(String rawValue) {
    final normalized = rawValue.trim();
    if (normalized.isEmpty) {
      throw const FormatException('Sync cursor cannot be empty.');
    }

    final parsed = BigInt.tryParse(normalized);
    if (parsed == null) {
      throw FormatException('Sync cursor is not numeric: $rawValue');
    }
    if (parsed < BigInt.zero) {
      throw FormatException('Sync cursor must be >= 0: $rawValue');
    }
    return parsed;
  }

  @override
  int compareTo(T other) {
    return asBigInt.compareTo(other.asBigInt);
  }

  @override
  String toString() => value;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) {
      return true;
    }
    return other is T && other.value == value;
  }

  @override
  int get hashCode => value.hashCode;
}

/// Strongly-typed sync epoch value object.
///
/// The epoch is a server-managed generation counter used to detect when a
/// full resync is required (for example after account deletion or major schema
/// changes).
class SyncEpoch extends SyncNumber<SyncEpoch> {
  const SyncEpoch._(super.value, super.asBigInt) : super._();

  /// Parses a raw string into a [SyncEpoch].
  factory SyncEpoch(String rawValue) {
    final parsed = SyncNumber._parseStringToBigInt(rawValue);
    return SyncEpoch._(parsed.toString(), parsed);
  }

  /// The epoch value `'0'`.
  factory SyncEpoch.zero() {
    return SyncEpoch('0');
  }

  static SyncEpoch fromJson(Object? json) {
    if (json == null) {
      throw const FormatException('Missing sync epoch.');
    }

    return SyncEpoch(json.toString());
  }

  static String toJson(SyncEpoch epoch) {
    return epoch.value;
  }
}

/// Strongly-typed sync cursor value object.
///
/// Cursors are monotonic server-side counters that define the canonical
/// ordering of changes. The client stores the last known cursor and sends
/// it as `sinceCursor` in batch requests.
class SyncCursor extends SyncNumber<SyncCursor> {
  const SyncCursor._(super.value, super.asBigInt) : super._();

  /// Parses a raw string into a [SyncCursor].
  factory SyncCursor(String rawValue) {
    final parsed = SyncNumber._parseStringToBigInt(rawValue);
    return SyncCursor._(parsed.toString(), parsed);
  }

  /// The cursor value `'0'`.
  factory SyncCursor.zero() {
    return SyncCursor('0');
  }

  static SyncCursor fromJson(Object? json) {
    if (json == null) {
      throw const FormatException('Missing sync cursor.');
    }

    return SyncCursor(json.toString());
  }

  static String toJson(SyncCursor cursor) {
    return cursor.value;
  }
}

/// JSON converter for [SyncCursor] (useful with code generators).
class SyncCursorJsonConverter {
  const SyncCursorJsonConverter();

  SyncCursor fromJson(Object? json) {
    return SyncCursor.fromJson(json);
  }

  Object? toJson(SyncCursor object) {
    return SyncCursor.toJson(object);
  }
}

/// JSON converter for [SyncEpoch] (useful with code generators).
class SyncEpochJsonConverter {
  const SyncEpochJsonConverter();

  SyncEpoch fromJson(Object? json) {
    return SyncEpoch.fromJson(json);
  }

  Object? toJson(SyncEpoch object) {
    return SyncEpoch.toJson(object);
  }
}
