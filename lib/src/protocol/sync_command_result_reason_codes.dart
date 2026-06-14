/// Stable machine-readable reason codes returned in [SyncCommandResult.reasonCode].
///
/// These codes are part of the sync protocol contract. Host apps and backends
/// should rely on them for automated conflict routing rather than parsing the
/// human-readable [SyncCommandResult.reason] field.
abstract final class SyncCommandResultReasonCodes {
  /// A stale command failed because the target row does not exist on the
  /// server, but the failure is recoverable (e.g. the row was deleted by a
  /// concurrent change and can be rebuilt or replayed).
  static const String recoverableMissingRow = 'recoverable_missing_row';
}
