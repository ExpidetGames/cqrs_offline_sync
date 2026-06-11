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
  StaleConflictProfileRegistry({
    Iterable<StaleConflictProfile> profiles = const <StaleConflictProfile>[],
    StaleConflictProfile? defaultProfile,
  }) : _defaultProfile = defaultProfile ?? const _ReplayStaleConflictProfile(),
       _byCommandType = <String, StaleConflictProfile>{
         for (final StaleConflictProfile profile in profiles)
           profile.commandType: profile,
       };

  final StaleConflictProfile _defaultProfile;
  final Map<String, StaleConflictProfile> _byCommandType;

  /// Returns the profile for [commandType], or the default.
  StaleConflictProfile resolve(String commandType) {
    return _byCommandType[commandType] ?? _defaultProfile;
  }
}

class _ReplayStaleConflictProfile implements StaleConflictProfile {
  const _ReplayStaleConflictProfile();

  @override
  String get commandType => '*';

  @override
  Future<ResolutionDecision<SyncCommand>> resolve(StaleConflictProfileContext context) async {
    throw UnsupportedError(
      '_ReplayStaleConflictProfile is a registry placeholder. '
      'It should never be called directly — concrete profiles must be registered.',
    );
  }
}
