import '../../commands/sync_command.dart';
import 'resolution_decision.dart';
import 'stale_conflict_profile.dart';

/// Registry that maps `commandType` to its [StaleConflictProfile].
///
/// Falls back to a placeholder replay profile when no specific profile is
/// registered. The placeholder throws if actually invoked, encouraging
/// explicit registration of concrete profiles.
class StaleConflictProfileRegistry {
  /// Creates a registry from a list of [profiles] and an optional [defaultProfile].
  ///
  /// Throws [ArgumentError] if [profiles] contains duplicate [commandType]
  /// values.
  StaleConflictProfileRegistry({
    Iterable<StaleConflictProfile> profiles = const <StaleConflictProfile>[],
    StaleConflictProfile? defaultProfile,
  }) : _defaultProfile = defaultProfile ?? const _ReplayStaleConflictProfile(),
       _byCommandType = _buildByCommandType(profiles) {
    if (_byCommandType.length != profiles.length) {
      throw ArgumentError.value(
        profiles,
        'profiles',
        'Duplicate commandType entries in StaleConflictProfileRegistry.',
      );
    }
  }

  final StaleConflictProfile _defaultProfile;
  final Map<String, StaleConflictProfile> _byCommandType;

  static Map<String, StaleConflictProfile> _buildByCommandType(
    Iterable<StaleConflictProfile> profiles,
  ) {
    final Map<String, StaleConflictProfile> map = <String, StaleConflictProfile>{};
    for (final StaleConflictProfile profile in profiles) {
      map[profile.commandType] = profile;
    }
    return map;
  }

  /// Returns the profile for [commandType], or the default.
  ///
  /// Throws [UnsupportedError] if no profile is registered and no
  /// [defaultProfile] was provided.
  StaleConflictProfile resolve(String commandType) {
    return _byCommandType[commandType] ?? _defaultProfile;
  }

  /// Returns the registered profile for [commandType], or `null` if none is
  /// registered.
  ///
  /// This is the non-throwing counterpart of [resolve].
  StaleConflictProfile? tryResolve(String commandType) {
    return _byCommandType[commandType];
  }
}

class _ReplayStaleConflictProfile implements StaleConflictProfile {
  const _ReplayStaleConflictProfile();

  @override
  String get commandType => '*';

  @override
  bool get requiresRebuildInstructions => false;

  @override
  Future<ResolutionDecision<SyncCommand>> resolve(StaleConflictProfileContext context) async {
    throw UnsupportedError(
      '_ReplayStaleConflictProfile is a registry placeholder. '
      'It should never be called directly — concrete profiles must be registered.',
    );
  }
}
