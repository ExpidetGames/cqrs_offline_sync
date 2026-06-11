import 'command_resolution_action.dart';

/// Immutable plan produced by [ConflictResolver.resolve].
///
/// Contains one [CommandResolutionAction] per stale or otherwise unresolved
/// command. The plan is committed by [SyncUnitOfWork.commitResolved].
class ConflictResolutionPlan {
  /// Creates a plan from a list of actions.
  ConflictResolutionPlan({required this.actions}) {
    for (final CommandResolutionAction action in actions) {
      _actionsByOpId[action.opId] = action;
    }
  }

  /// All actions in this plan.
  final List<CommandResolutionAction> actions;

  final Map<String, CommandResolutionAction> _actionsByOpId =
      <String, CommandResolutionAction>{};

  /// Looks up the action for a given [opId], or `null`.
  CommandResolutionAction? getActionByOpId(String opId) {
    if (_actionsByOpId.containsKey(opId)) {
      return _actionsByOpId[opId]!;
    }
    return null;
  }

  /// Whether this plan contains at least one [RequeueCommandAction].
  bool get hasRequeuedCommands {
    return actions.any((CommandResolutionAction action) {
      return action is RequeueCommandAction;
    });
  }
}
