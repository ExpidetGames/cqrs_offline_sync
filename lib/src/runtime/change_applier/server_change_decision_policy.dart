import '../../protocol/server_change.dart';

/// Decision for how to handle a pulled server change during apply.
enum ServerChangeDecision { applyServer, keepLocal }

/// Policy that decides whether a server change should be applied or kept local.
///
/// The default [AlwaysApplyServerChangeDecisionPolicy] always applies server
/// changes, which is correct for most sync scenarios.
abstract interface class ServerChangeDecisionPolicy {
  ServerChangeDecision decide(ServerChange change);
}

/// Always applies server changes.
class AlwaysApplyServerChangeDecisionPolicy
    implements ServerChangeDecisionPolicy {
  const AlwaysApplyServerChangeDecisionPolicy();

  @override
  ServerChangeDecision decide(ServerChange change) {
    return ServerChangeDecision.applyServer;
  }
}
