/// Exception thrown when [CqrsSyncRuntime.compose] detects configuration
/// errors.
///
/// The message contains all detected errors so callers can fix them in one pass.
class SyncRuntimeConfigurationException implements Exception {
  /// Creates a configuration exception with the combined [message].
  SyncRuntimeConfigurationException(this.message);

  /// Human-readable message listing all detected configuration errors.
  final String message;

  @override
  String toString() => 'SyncRuntimeConfigurationException: $message';
}
