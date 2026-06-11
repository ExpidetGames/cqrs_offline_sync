/// Phase of a sync run, exposed to UI and diagnostics.
enum SyncRunPhase { idle, syncingUp, pulling, applyingChanges }

/// Human-readable labels for [SyncRunPhase].
extension SyncRunPhaseDescription on SyncRunPhase {
  /// Returns a short label suitable for UI or logs.
  String get label {
    return switch (this) {
      SyncRunPhase.idle => 'Idle',
      SyncRunPhase.syncingUp => 'Syncing up',
      SyncRunPhase.pulling => 'Pulling',
      SyncRunPhase.applyingChanges => 'Applying',
    };
  }
}
