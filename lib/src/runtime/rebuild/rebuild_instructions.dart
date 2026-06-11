import '../conflict/requeued_command.dart';

/// Reference to a single entity in a [RebuildInstruction].
class RebuildEntityRef {
  /// Creates an entity reference.
  const RebuildEntityRef({required this.tableName, required this.rowId});

  final String tableName;
  final String rowId;

  /// Composite key used for deduplication.
  String get key => '$tableName::$rowId';

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) {
      return true;
    }
    return other is RebuildEntityRef && other.tableName == tableName && other.rowId == rowId;
  }

  @override
  int get hashCode => Object.hash(tableName, rowId);
}

/// Instruction describing how to recreate a deleted entity and its subtree.
class RebuildInstruction {
  /// Creates a rebuild instruction.
  ///
  /// [coveredEntities] must include [rootEntity].
  RebuildInstruction({
    required this.rootEntity,
    required Iterable<RebuildEntityRef> coveredEntities,
    required Iterable<RequeuedCommand> commands,
  })  : coveredEntities = List<RebuildEntityRef>.unmodifiable(coveredEntities),
        commands = List<RequeuedCommand>.unmodifiable(commands) {
    if (!this.coveredEntities.contains(rootEntity)) {
      throw ArgumentError('coveredEntities must include rootEntity (${rootEntity.key}).');
    }
  }

  /// The top-level entity that was deleted.
  final RebuildEntityRef rootEntity;

  /// All entities covered by this instruction (including descendants).
  final List<RebuildEntityRef> coveredEntities;

  /// Commands needed to recreate the subtree.
  final List<RequeuedCommand> commands;

  /// Key used for deduplication in [RebuildInstructions].
  String get dedupeKey => rootEntity.key;
}

/// Immutable collection of [RebuildInstruction]s indexed by entity key.
///
/// Supports deduplication and ancestor-overwrite semantics: when two instructions
/// overlap, the one whose root is higher in the graph wins.
class RebuildInstructions {
  const RebuildInstructions._(this._byEntityKey);

  /// Empty instruction set.
  static const RebuildInstructions empty = RebuildInstructions._(<String, RebuildInstruction>{});

  final Map<String, RebuildInstruction> _byEntityKey;

  bool get isEmpty => _byEntityKey.isEmpty;

  /// Returns deduplicated instructions.
  Iterable<RebuildInstruction> get asIterable {
    final Set<String> seen = <String>{};
    return _byEntityKey.values.where((RebuildInstruction instruction) {
      return seen.add(instruction.dedupeKey);
    });
  }

  /// Looks up an instruction by [entity], or `null`.
  RebuildInstruction? findForEntity(RebuildEntityRef entity) {
    return _byEntityKey[entity.key];
  }

  /// Looks up an instruction by table + row id, or `null`.
  RebuildInstruction? findForTableRow({required String tableName, required String rowId}) {
    return findForEntity(RebuildEntityRef(tableName: tableName, rowId: rowId));
  }

  /// Returns a new [RebuildInstructions] with [instruction] merged in.
  ///
  /// If [instruction] is `null`, returns `this`. Uses ancestor-overwrite
  /// semantics when instructions overlap.
  RebuildInstructions add(RebuildInstruction? instruction) {
    if (instruction == null) {
      return this;
    }

    final Map<String, RebuildInstruction> next = <String, RebuildInstruction>{..._byEntityKey};

    for (final RebuildEntityRef entity in instruction.coveredEntities) {
      final RebuildInstruction? existing = next[entity.key];
      if (existing == null) {
        next[entity.key] = instruction;
      } else if (instruction.coveredEntities.contains(existing.rootEntity)) {
        // The new instruction encompasses the root of the existing instruction,
        // meaning it is an ancestor / higher up in the graph. Overwrite!
        next[entity.key] = instruction;
      }
      // Else: The existing instruction encompasses the new instruction's root,
      // so it is already the higher up ancestor. Do nothing.
    }

    return RebuildInstructions._(Map<String, RebuildInstruction>.unmodifiable(next));
  }
}
