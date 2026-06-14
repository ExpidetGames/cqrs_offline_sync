import '../../protocol/sync_command_result_reason_codes.dart';
import 'stale_conflict_routing_context.dart';

/// Decides whether a stale conflict should be routed to the registered
/// [StaleConflictProfile] for the command type.
///
/// This is a policy object rather than a bare function so the host app can
/// choose among built-in implementations or supply its own.
abstract interface class SyncStaleRoutingPolicy {
  /// Returns `true` if the stale command in [context] should be resolved by
  /// its profile, or `false` if it should be dropped (acked) by default.
  bool shouldRouteToProfile(StaleConflictRoutingContext context);

  /// Routes only commands whose [SyncCommandResult.reasonCode] is
  /// [SyncCommandResultReasonCodes.recoverableMissingRow].
  ///
  /// [allowLegacyReasonPrefixFallback] enables matching the human-readable
  /// [SyncCommandResult.reason] when it starts with [legacyReasonPrefix].
  /// This supports backends that have not yet migrated to [reasonCode].
  const factory SyncStaleRoutingPolicy.recoverableMissingRowOnly({
    bool allowLegacyReasonPrefixFallback,
    String legacyReasonPrefix,
  }) = _RecoverableMissingRowRoutingPolicy;

  /// Routes every stale command to its registered profile.
  ///
  /// This is appropriate when every command type in the app has an explicit
  /// stale-conflict profile registered.
  const factory SyncStaleRoutingPolicy.alwaysRoute() = _AlwaysRoutePolicy;

  /// Routes stale commands to their profile when [decider] returns `true`.
  const factory SyncStaleRoutingPolicy.custom(
    bool Function(StaleConflictRoutingContext context) decider,
  ) = _CustomRoutingPolicy;
}

class _RecoverableMissingRowRoutingPolicy implements SyncStaleRoutingPolicy {
  const _RecoverableMissingRowRoutingPolicy({
    this.allowLegacyReasonPrefixFallback = false,
    this.legacyReasonPrefix = 'recoverable_missing_row:',
  });

  final bool allowLegacyReasonPrefixFallback;
  final String legacyReasonPrefix;

  void _validate() {
    if (allowLegacyReasonPrefixFallback && legacyReasonPrefix.isEmpty) {
      throw ArgumentError(
        'legacyReasonPrefix must be non-empty when fallback is enabled.',
      );
    }
  }

  @override
  bool shouldRouteToProfile(StaleConflictRoutingContext context) {
    _validate();
    if (context.result.reasonCode ==
        SyncCommandResultReasonCodes.recoverableMissingRow) {
      return true;
    }

    if (allowLegacyReasonPrefixFallback) {
      final String? reason = context.result.reason;
      if (reason != null && reason.startsWith(legacyReasonPrefix)) {
        return true;
      }
    }

    return false;
  }
}

class _AlwaysRoutePolicy implements SyncStaleRoutingPolicy {
  const _AlwaysRoutePolicy();

  @override
  bool shouldRouteToProfile(StaleConflictRoutingContext context) => true;
}

class _CustomRoutingPolicy implements SyncStaleRoutingPolicy {
  const _CustomRoutingPolicy(this._decider);

  final bool Function(StaleConflictRoutingContext context) _decider;

  @override
  bool shouldRouteToProfile(StaleConflictRoutingContext context) =>
      _decider(context);
}
