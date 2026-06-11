/// Reasons why a sync run was requested.
///
/// Used for logging, telemetry, and UI display.
enum SyncTriggerReason {
  startup('startup'),
  interval('interval'),
  resume('resume'),
  authAuthenticated('auth authenticated'),
  localWriteCommitted('local write committed'),
  manual('manual');

  const SyncTriggerReason(this.label);

  /// Human-readable label for this reason.
  final String label;
}

/// Contract for requesting a sync run from the scheduler or write path.
///
/// The host app implements this (e.g. via a scheduler, Riverpod provider, or
/// simple callback) and delegates to [SyncRunner.runOnce].
abstract interface class SyncTriggerSink {
  /// Requests a sync run. The implementation decides whether to run immediately,
  /// coalesce, or drop duplicate requests.
  void requestSync({required SyncTriggerReason reason});
}

/// A no-op trigger sink that silently discards all requests.
class NoopSyncTriggerSink implements SyncTriggerSink {
  /// Creates a const [NoopSyncTriggerSink].
  const NoopSyncTriggerSink();

  @override
  void requestSync({required SyncTriggerReason reason}) {}
}
