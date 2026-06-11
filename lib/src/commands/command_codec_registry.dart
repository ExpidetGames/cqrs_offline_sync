import '../protocol/sync_cursor.dart';
import 'command_envelope.dart';
import 'sync_command.dart';

/// Parses a JSON map into a typed [SyncCommand] payload.
///
/// Typically used as the `fromJson` constructor of a concrete command class.
typedef CommandPayloadFromJson<T extends SyncCommand> =
    T Function(Map<String, dynamic> json);

/// Serializes a typed [SyncCommand] payload into a JSON map.
///
/// Typically used as the `toJson` method of a concrete command class.
typedef CommandPayloadToJson<T extends SyncCommand> =
    Map<String, dynamic> Function(T payload);

/// Base codec contract for a single command type.
///
/// [CommandCodecRegistry] collects [AnyCommandCodec]s and routes by
/// [commandType] (for decoding) and by payload [Type] (for encoding).
abstract interface class AnyCommandCodec {
  /// Wire command type identifier (e.g. `'vocab_trainer.create_chapter'`).
  String get commandType;

  /// Domain aggregate type (e.g. `'vocab_trainer'`).
  String get aggregateType;

  /// Dart [Type] of the decoded payload.
  Type get payloadType;

  /// Parses [payloadJson] into a [SyncCommand] instance.
  SyncCommand decode(Object? payloadJson);

  /// Serializes [payload] into a JSON-compatible value.
  Object? encode(SyncCommand payload);
}

/// Typed codec implementation that binds a concrete [SyncCommand] subtype.
///
/// Provide [fromJson] and [toJson] for the payload, and [commandType] /
/// [aggregateType] / [payloadType] for registry routing.
class CommandPayloadCodec<T extends SyncCommand> implements AnyCommandCodec {
  /// Creates a codec for a single command type.
  const CommandPayloadCodec({
    required this.commandType,
    required this.aggregateType,
    required this.payloadType,
    required this.fromJson,
    required this.toJson,
  });

  @override
  final String commandType;

  @override
  final String aggregateType;

  @override
  final Type payloadType;

  final CommandPayloadFromJson<T> fromJson;
  final CommandPayloadToJson<T> toJson;

  @override
  T decode(Object? payloadJson) {
    return fromJson(_toPayloadMap(payloadJson));
  }

  @override
  Object? encode(SyncCommand payload) {
    if (payload is! T) {
      throw StateError(
        'Codec for $commandType cannot encode payload type ${payload.runtimeType}.',
      );
    }
    return toJson(payload);
  }
}

/// Result of decoding a wire envelope back into a typed payload.
///
/// Holds both the matched [codec] and the parsed [envelope].
class DecodedCommandEnvelope {
  /// Creates a decoded envelope.
  const DecodedCommandEnvelope({required this.codec, required this.envelope});

  /// The codec that matched this envelope's [commandType].
  final AnyCommandCodec codec;

  /// The parsed envelope with a [SyncCommand] payload.
  final CommandEnvelope<SyncCommand> envelope;

  /// Casts the payload to [T] or throws a [StateError] if the type mismatches.
  T payloadAs<T extends SyncCommand>() {
    final payload = envelope.payload;
    if (payload is! T) {
      throw StateError(
        'Decoded payload has type ${payload.runtimeType}, expected $T.',
      );
    }
    return payload;
  }
}

/// Runtime registry that maps command types to their codecs.
///
/// Used by:
/// - [CommandEnvelopeFactory] to validate and wrap payloads
/// - [SyncTransport] to encode outgoing commands
/// - [SyncUnitOfWork] to decode incoming command results
class CommandCodecRegistry {
  /// Creates a registry from a list of codecs.
  ///
  /// Throws [StateError] if [codecs] contains duplicate [commandType] values.
  CommandCodecRegistry(Iterable<AnyCommandCodec> codecs)
    : _byCommandType = {for (final codec in codecs) codec.commandType: codec},
      _byPayloadType = {for (final codec in codecs) codec.payloadType: codec} {
    if (_byCommandType.length != codecs.length) {
      throw StateError(
        'Duplicate commandType entries in CommandCodecRegistry.',
      );
    }
  }

  final Map<String, AnyCommandCodec> _byCommandType;
  final Map<Type, AnyCommandCodec> _byPayloadType;

  /// Decodes a JSON map into a [DecodedCommandEnvelope].
  ///
  /// Validates that the [commandType] and [aggregateType] match the codec.
  /// Throws [FormatException] for unknown types or mismatched aggregates.
  DecodedCommandEnvelope decode(Map<String, dynamic> json) {
    final rawCommandType = json['commandType'];
    if (rawCommandType is! String || rawCommandType.isEmpty) {
      throw const FormatException('Missing or invalid commandType.');
    }

    final codec = _byCommandType[rawCommandType];
    if (codec == null) {
      throw FormatException('Unsupported commandType: $rawCommandType');
    }

    final envelope = CommandEnvelope<SyncCommand>.fromJson(json, codec.decode);

    if (envelope.aggregateType != codec.aggregateType) {
      throw FormatException(
        'Invalid aggregateType for ${codec.commandType}: ${envelope.aggregateType} != ${codec.aggregateType}',
      );
    }

    return DecodedCommandEnvelope(codec: codec, envelope: envelope);
  }

  /// Serializes an envelope to a JSON map.
  ///
  /// Throws [StateError] if the envelope's [commandType] is not registered.
  Map<String, dynamic> encode(CommandEnvelope<SyncCommand> envelope) {
    final codec = _byCommandType[envelope.commandType];
    if (codec == null) {
      throw StateError('No codec registered for ${envelope.commandType}.');
    }

    return envelope.toJson(codec.encode);
  }

  /// Builds a new envelope for [payload] with explicit metadata.
  ///
  /// Validates that the payload's [commandType] and [aggregateType] match
  /// the registered codec. Throws [StateError] on mismatch.
  CommandEnvelope<SyncCommand> createEnvelope({
    required String opId,
    required DateTime occurredAtUtc,
    required SyncCommand payload,
    required SyncCursor baseCursor,
  }) {
    final codec = _byCommandType[payload.commandType];
    if (codec == null) {
      throw StateError('No codec registered for ${payload.commandType}.');
    }

    if (codec.aggregateType != payload.aggregateType) {
      throw StateError(
        'Payload aggregateType mismatch for ${payload.commandType}: ${payload.aggregateType} != ${codec.aggregateType}',
      );
    }

    return CommandEnvelope<SyncCommand>(
      opId: opId,
      occurredAtUtc: occurredAtUtc,
      aggregateType: payload.aggregateType,
      commandType: payload.commandType,
      payload: payload,
      baseCursor: baseCursor,
    );
  }

  /// Looks up the codec for a given payload [Type], or `null` if not registered.
  AnyCommandCodec? lookupByPayloadType(Type payloadType) {
    return _byPayloadType[payloadType];
  }
}

Map<String, dynamic> _toPayloadMap(Object? payloadJson) {
  if (payloadJson is Map<String, dynamic>) {
    return payloadJson;
  }
  if (payloadJson is Map) {
    return payloadJson.map((key, value) => MapEntry(key.toString(), value));
  }
  throw const FormatException('Command payload must be a JSON object.');
}
