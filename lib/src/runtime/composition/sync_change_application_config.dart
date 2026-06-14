import '../change_applier/server_change_decision_policy.dart';

/// Sealed configuration for delete-rebuild behavior during change application.
sealed class SyncDeleteRebuild {
  const SyncDeleteRebuild();

  /// Delete-rebuild is disabled. No rebuild instructions are captured.
  const factory SyncDeleteRebuild.disabled() = SyncDeleteRebuildDisabled;

  /// Delete-rebuild is enabled. Requires a real rebuild instruction store
  /// and a usable rebuild graph.
  const factory SyncDeleteRebuild.enabled() = SyncDeleteRebuildEnabled;
}

/// Delete-rebuild disabled variant.
final class SyncDeleteRebuildDisabled extends SyncDeleteRebuild {
  /// Creates a disabled delete-rebuild config.
  const SyncDeleteRebuildDisabled();
}

/// Delete-rebuild enabled variant.
final class SyncDeleteRebuildEnabled extends SyncDeleteRebuild {
  /// Creates an enabled delete-rebuild config.
  const SyncDeleteRebuildEnabled();
}

/// Immutable configuration for server-side change application.
class SyncChangeApplicationConfig {
  /// Creates a change application config.
  ///
  /// [deleteRebuild] defaults to disabled. [decisionPolicy] defaults to
  /// always applying server changes.
  const SyncChangeApplicationConfig({
    this.deleteRebuild = const SyncDeleteRebuild.disabled(),
    this.decisionPolicy,
  });

  /// Whether to capture rebuild instructions for delete changes.
  final SyncDeleteRebuild deleteRebuild;

  /// Optional policy that decides whether to keep local rows or apply server
  /// changes. If omitted, server changes are always applied.
  final ServerChangeDecisionPolicy? decisionPolicy;
}
