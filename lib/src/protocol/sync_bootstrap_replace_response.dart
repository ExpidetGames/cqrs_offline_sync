import 'json_parse_utils.dart';
import 'sync_cursor.dart';

/// Server response after a successful bootstrap-replace operation.
///
/// Contains the [newCursor] and [newSyncEpoch] that the client should adopt
/// after its local dataset has been replaced by the server.
class SyncBootstrapReplaceResponse {
  /// Creates a response with [newCursor] and [newSyncEpoch].
  const SyncBootstrapReplaceResponse({required this.newCursor, required this.newSyncEpoch});

  /// The new server cursor after the replace.
  final SyncCursor newCursor;

  /// The new sync epoch after the replace.
  final SyncEpoch newSyncEpoch;

  /// Parses a [SyncBootstrapReplaceResponse] from JSON.
  factory SyncBootstrapReplaceResponse.fromJson(Map<String, dynamic> json) {
    final String newCursorRaw = asStringOr(json['newCursor'], fallback: '');
    final String newSyncEpochRaw = asStringOr(json['newSyncEpoch'], fallback: '');
    if (newCursorRaw.isEmpty) {
      throw const FormatException('Missing required newCursor in bootstrap replace response.');
    }
    if (newSyncEpochRaw.isEmpty) {
      throw const FormatException('Missing required newSyncEpoch in bootstrap replace response.');
    }

    return SyncBootstrapReplaceResponse(newCursor: SyncCursor(newCursorRaw), newSyncEpoch: SyncEpoch(newSyncEpochRaw));
  }
}
