import '../conflict/conflict_resolver.dart';
import '../conflict/default_conflict_resolver.dart';
import '../conflict/stale_conflict_profile.dart';
import '../conflict/stale_conflict_profile_registry.dart';
import '../conflict/sync_stale_routing_policy.dart';

/// Sealed configuration for stale conflict resolution.
sealed class SyncConflictResolution {
  const SyncConflictResolution();

  /// Build a default resolver when stale profiles exist; otherwise no
  /// resolver is provided.
  ///
  /// Uses [SyncStaleRoutingPolicy.recoverableMissingRowOnly()] as the default
  /// routing policy.
  const factory SyncConflictResolution.auto() = SyncConflictResolutionAuto;

  /// No resolver is built. Profile dependencies are ignored, but structural
  /// duplicate profile validation still applies.
  const factory SyncConflictResolution.disabled() = SyncConflictResolutionDisabled;

  /// Build a default resolver using an explicit routing policy even when no
  /// stale profiles are registered.
  const factory SyncConflictResolution.defaults({
    SyncStaleRoutingPolicy staleRoutingPolicy,
  }) = SyncConflictResolutionDefaults;

  /// Use a custom resolver. No profile dependencies are validated.
  const factory SyncConflictResolution.custom(ConflictResolver resolver) =
      SyncConflictResolutionCustom;
}

/// Auto conflict resolution variant.
final class SyncConflictResolutionAuto extends SyncConflictResolution {
  /// Creates auto conflict resolution config.
  const SyncConflictResolutionAuto();
}

/// Disabled conflict resolution variant.
final class SyncConflictResolutionDisabled extends SyncConflictResolution {
  /// Creates disabled conflict resolution config.
  const SyncConflictResolutionDisabled();
}

/// Defaults conflict resolution variant.
final class SyncConflictResolutionDefaults extends SyncConflictResolution {
  /// Creates defaults config with [staleRoutingPolicy].
  const SyncConflictResolutionDefaults({
    this.staleRoutingPolicy = const SyncStaleRoutingPolicy.recoverableMissingRowOnly(),
  });

  /// Routing policy used by the built default resolver.
  final SyncStaleRoutingPolicy staleRoutingPolicy;
}

/// Custom conflict resolution variant.
final class SyncConflictResolutionCustom extends SyncConflictResolution {
  /// Creates custom conflict resolution config with [resolver].
  const SyncConflictResolutionCustom(this.resolver);

  /// The custom resolver to use.
  final ConflictResolver resolver;
}

/// Internal result of resolving [SyncConflictResolution] against the available
/// stale profiles.
class BuiltConflictResolution {
  const BuiltConflictResolution({
    required this.resolver,
    required this.registry,
  });

  /// The resolver to pass to [SyncRunner], or `null` if conflict resolution
  /// is disabled.
  final ConflictResolver? resolver;

  /// The built stale profile registry, or `null` if no profiles were
  /// registered.
  final StaleConflictProfileRegistry? registry;
}

/// Builds a [BuiltConflictResolution] from configuration and registered
/// profiles.
BuiltConflictResolution buildConflictResolution({
  required SyncConflictResolution config,
  required List<StaleConflictProfile> profiles,
}) {
  final StaleConflictProfileRegistry? registry = profiles.isEmpty
      ? null
      : StaleConflictProfileRegistry(profiles: profiles);

  return switch (config) {
    SyncConflictResolutionDisabled() =>
        BuiltConflictResolution(resolver: null, registry: registry),
    SyncConflictResolutionCustom(:final ConflictResolver resolver) =>
        BuiltConflictResolution(resolver: resolver, registry: registry),
    SyncConflictResolutionAuto() => _buildAuto(registry),
    SyncConflictResolutionDefaults(:final SyncStaleRoutingPolicy staleRoutingPolicy) =>
        BuiltConflictResolution(
          resolver: DefaultConflictResolver(
            staleProfileRegistry: registry ?? StaleConflictProfileRegistry(),
            routingPolicy: staleRoutingPolicy,
          ),
          registry: registry,
        ),
  };
}

BuiltConflictResolution _buildAuto(StaleConflictProfileRegistry? registry) {
  if (registry == null) {
    return const BuiltConflictResolution(resolver: null, registry: null);
  }

  return BuiltConflictResolution(
    resolver: DefaultConflictResolver(
      staleProfileRegistry: registry,
      routingPolicy: const SyncStaleRoutingPolicy.recoverableMissingRowOnly(),
    ),
    registry: registry,
  );
}
