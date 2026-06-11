import '../../protocol/server_change.dart';
import 'rebuild_instructions.dart';

/// Result of applying server changes via [ServerChangeApplier].
class ServerChangeApplyResult {
  const ServerChangeApplyResult({
    this.rebuildInstructions = RebuildInstructions.empty,
  });

  /// Empty result with no rebuild instructions.
  static const ServerChangeApplyResult empty = ServerChangeApplyResult();

  /// Rebuild instructions captured during delete processing.
  final RebuildInstructions rebuildInstructions;
}

/// Contract for applying server feed changes to local tables.
///
/// [CompositeServerChangeApplier] is the standard implementation that routes
/// changes to per-table handlers and captures delete-rebuild instructions.
abstract interface class ServerChangeApplier {
  /// Applies [changes] in cursor order and returns captured instructions.
  Future<ServerChangeApplyResult> apply(List<ServerChange> changes);
}

/// No-op applier that returns an empty result.
class NoopServerChangeApplier implements ServerChangeApplier {
  /// Creates a const noop applier.
  const NoopServerChangeApplier();

  @override
  Future<ServerChangeApplyResult> apply(List<ServerChange> changes) async {
    return ServerChangeApplyResult.empty;
  }
}
