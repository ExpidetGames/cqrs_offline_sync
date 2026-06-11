import '../internal/uuid.dart';
import '../protocol/sync_cursor.dart';
import 'command_codec_registry.dart';
import 'command_envelope.dart';
import 'sync_command.dart';

/// Generates unique operation identifiers for command envelopes.
///
/// Implementations decide the ID format (UUID, ULID, snowflake, etc.).
/// The default is [UuidOpIdGenerator].
abstract interface class OpIdGenerator {
  /// Returns the next unique operation identifier.
  String nextOpId();
}

/// [OpIdGenerator] that produces cryptographically secure UUID v4 strings.
///
/// Use this when you need globally unique opIds without a central coordinator.
class UuidOpIdGenerator implements OpIdGenerator {
  /// Creates a const [UuidOpIdGenerator].
  const UuidOpIdGenerator();

  @override
  String nextOpId() {
    return generateSyncUuidV4();
  }
}

/// Contract for obtaining the current UTC time.
///
/// Extracted as an interface so tests can inject a fixed clock.
abstract interface class UtcClock {
  /// Returns the current time in UTC.
  DateTime nowUtc();
}

/// [UtcClock] that delegates to [DateTime.now] in UTC.
class SystemUtcClock implements UtcClock {
  /// Creates a const [SystemUtcClock].
  const SystemUtcClock();

  @override
  DateTime nowUtc() {
    return DateTime.now().toUtc();
  }
}

/// Factory that assembles [CommandEnvelope] instances from typed payloads.
///
/// Encapsulates codec validation, opId generation, and timestamp assignment
/// so callers only need to supply the [SyncCommand] payload and its base cursor.
class CommandEnvelopeFactory {
  /// Creates a factory backed by [codecRegistry], [opIdGenerator], and [clock].
  const CommandEnvelopeFactory({
    required CommandCodecRegistry codecRegistry,
    required OpIdGenerator opIdGenerator,
    required UtcClock clock,
  }) : _codecRegistry = codecRegistry,
       _opIdGenerator = opIdGenerator,
       _clock = clock;

  final CommandCodecRegistry _codecRegistry;
  final OpIdGenerator _opIdGenerator;
  final UtcClock _clock;

  /// Builds a new [CommandEnvelope] for [payload].
  ///
  /// [baseCursor] is the local cursor at the moment the command was created.
  /// [occurredAtUtc] defaults to the clock's current UTC time.
  CommandEnvelope<SyncCommand> create({
    required SyncCommand payload,
    required SyncCursor baseCursor,
    DateTime? occurredAtUtc,
  }) {
    return _codecRegistry.createEnvelope(
      opId: _opIdGenerator.nextOpId(),
      occurredAtUtc: occurredAtUtc ?? _clock.nowUtc(),
      payload: payload,
      baseCursor: baseCursor,
    );
  }
}
