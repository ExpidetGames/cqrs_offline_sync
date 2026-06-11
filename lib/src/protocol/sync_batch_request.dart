import '../commands/command_codec_registry.dart';
import '../commands/command_envelope.dart';
import '../commands/sync_command.dart';
import 'json_parse_utils.dart';
import 'sync_cursor.dart';

/// Wire-serializable request for one sync push/pull round-trip.
///
/// Contains the local [sinceCursor], optional sync [commands], and pull
/// configuration ([includePull], [pullLimit]).
class SyncBatchRequest {
  const SyncBatchRequest({
    required this.sinceCursor,
    required this.syncEpoch,
    required this.commands,
    this.pullLimit = 500,
    this.includePull = true,
  });

  /// Last known server cursor on the client.
  final SyncCursor sinceCursor;

  /// Current sync epoch expected by the client.
  final SyncEpoch syncEpoch;

  /// Pending local commands to push.
  final List<CommandEnvelope<SyncCommand>> commands;

  /// Maximum number of downstream changes to request.
  final int pullLimit;

  /// Whether the client wants downstream changes in this request.
  final bool includePull;

  /// True when there are no commands and pull is disabled.
  bool get isEmpty => commands.isEmpty && !includePull;

  /// Serializes this request to JSON using [registry] for command encoding.
  Map<String, dynamic> toJson(CommandCodecRegistry registry) {
    return <String, dynamic>{
      'sinceCursor': sinceCursor.value,
      'syncEpoch': syncEpoch.value,
      'commands': commands.map(registry.encode).toList(growable: false),
      'pull': <String, dynamic>{'enabled': includePull, 'limit': pullLimit},
    };
  }

  /// Parses a [SyncBatchRequest] from JSON using [registry] for command decoding.
  factory SyncBatchRequest.fromJson(
    Map<String, dynamic> json, {
    required CommandCodecRegistry registry,
  }) {
    final rawCommands = asListOr(json['commands'], fallback: const <dynamic>[]);
    final parsedCommands = rawCommands
        .map((entry) => asMapOr(entry, fallback: const <String, dynamic>{}))
        .where((entry) => entry.isNotEmpty)
        .map(registry.decode)
        .map((decoded) => decoded.envelope)
        .toList(growable: false);

    final pull = asMapOr(json['pull'], fallback: const <String, dynamic>{});
    final includePull = asBoolOr(pull['enabled'], fallback: true);
    final pullLimit = asIntOr(pull['limit'], fallback: 500);
    final sinceCursorRaw = asStringOr(json['sinceCursor'], fallback: '');
    final syncEpochRaw = asStringOr(json['syncEpoch'], fallback: '');
    if (sinceCursorRaw.isEmpty) {
      throw const FormatException('Missing required sinceCursor.');
    }
    if (syncEpochRaw.isEmpty) {
      throw const FormatException('Missing required syncEpoch.');
    }

    return SyncBatchRequest(
      sinceCursor: SyncCursor(sinceCursorRaw),
      syncEpoch: SyncEpoch(syncEpochRaw),
      commands: parsedCommands,
      pullLimit: pullLimit,
      includePull: includePull,
    );
  }
}
