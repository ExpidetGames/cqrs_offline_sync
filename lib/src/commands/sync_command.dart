/// Marker interface for all command payloads that can be enqueued in the sync outbox.
///
/// Every concrete command must provide [commandType] and [aggregateType] so
/// the [CommandCodecRegistry] can route encode/decode and the sync runtime
/// can route stale-conflict profiles.
abstract interface class SyncCommand {
  /// Wire command type identifier (e.g. `'vocab_trainer.create_chapter'`).
  String get commandType;

  /// Domain aggregate type (e.g. `'vocab_trainer'`).
  String get aggregateType;
}
