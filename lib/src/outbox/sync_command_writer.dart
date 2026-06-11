import '../commands/sync_command.dart';

/// Contract for appending a command to the local sync outbox.
///
/// Implementations are typically backed by a database store. The outbox row
/// is created with status `pending` so the next sync run will pick it up.
///
/// [rebuildContext] is optional local-only metadata used by stale conflict
/// profiles when the original payload is not enough to reconstruct the
/// intended result from latest local/server state.
abstract interface class SyncCommandWriter {
  /// Appends [payload] to the outbox.
  ///
  /// [rebuildContext] is not sent to the server; it is private seed data for
  /// client-side stale-recovery rebuild planning.
  Future<void> append(
    SyncCommand payload, {
    Map<String, dynamic>? rebuildContext,
  });
}
