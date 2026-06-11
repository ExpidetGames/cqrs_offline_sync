import '../protocol/sync_cursor.dart';

/// Wire-serializable envelope that carries a single sync command to the server.
///
/// [T] is the typed payload type (must extend [SyncCommand]).
/// The envelope adds metadata required by the sync protocol: [opId] for
/// idempotency, [occurredAtUtc] for ordering, [baseCursor] for conflict
/// detection, and [aggregateType]/[commandType] for routing.
class CommandEnvelope<T> {
  /// Creates an envelope with all required fields.
  const CommandEnvelope({
    required this.opId,
    required this.occurredAtUtc,
    required this.aggregateType,
    required this.commandType,
    required this.payload,
    required this.baseCursor,
  });

  /// Unique operation identifier. Re-sending the same [opId] must be a no-op.
  final String opId;

  /// When the command logically occurred, in UTC.
  final DateTime occurredAtUtc;

  /// Domain aggregate this command targets (e.g. `'vocab_trainer'`).
  final String aggregateType;

  /// Concrete command type within the aggregate (e.g. `'vocab_trainer.create_chapter'`).
  final String commandType;

  /// Typed command payload. Serialized via the codec registry.
  final T payload;

  /// Local cursor at command creation time. Used for stale-conflict detection.
  final SyncCursor baseCursor;

  /// Serializes this envelope to JSON using [toJsonT] for the payload.
  Map<String, dynamic> toJson(Object? Function(T value) toJsonT) {
    return <String, dynamic>{
      'opId': opId,
      'occurredAtUtc': occurredAtUtc.toUtc().toIso8601String(),
      'aggregateType': aggregateType,
      'commandType': commandType,
      'payload': toJsonT(payload),
      'baseCursor': baseCursor.value,
    };
  }

  /// Parses a [CommandEnvelope] from JSON using [fromJsonT] for the payload.
  ///
  /// Throws [FormatException] for missing or malformed required fields.
  factory CommandEnvelope.fromJson(
    Map<String, dynamic> json,
    T Function(Object? json) fromJsonT,
  ) {
    final opId = json['opId'];
    final occurredAtUtc = json['occurredAtUtc'];
    final aggregateType = json['aggregateType'];
    final commandType = json['commandType'];
    final baseCursor = json['baseCursor'];

    if (opId is! String || opId.isEmpty) {
      throw const FormatException('Missing or invalid opId.');
    }
    if (occurredAtUtc is! String || occurredAtUtc.isEmpty) {
      throw const FormatException('Missing or invalid occurredAtUtc.');
    }
    if (aggregateType is! String || aggregateType.isEmpty) {
      throw const FormatException('Missing or invalid aggregateType.');
    }
    if (commandType is! String || commandType.isEmpty) {
      throw const FormatException('Missing or invalid commandType.');
    }

    return CommandEnvelope<T>(
      opId: opId,
      occurredAtUtc: DateTime.parse(occurredAtUtc).toUtc(),
      aggregateType: aggregateType,
      commandType: commandType,
      payload: fromJsonT(json['payload']),
      baseCursor: SyncCursor.fromJson(baseCursor),
    );
  }
}
