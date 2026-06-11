import '../commands/command_envelope.dart';
import '../commands/sync_command.dart';

/// A pending or in-flight outbox row decoded back into a typed envelope.
class DecodedOutboxCommand {
  /// Creates a decoded outbox entry.
  const DecodedOutboxCommand({
    required this.opId,
    required this.envelope,
    required this.rebuildContext,
  });

  /// The operation identifier.
  final String opId;

  /// The parsed command envelope.
  final CommandEnvelope<SyncCommand> envelope;

  /// Optional local-only rebuild metadata.
  final Map<String, dynamic>? rebuildContext;
}

/// Describes a single failed command for retry bookkeeping.
class OutboxFailureUpdate {
  /// Creates a failure update for [opId].
  const OutboxFailureUpdate({
    required this.opId,
    required this.error,
    this.retryAfter = const Duration(seconds: 30),
  });

  /// The operation identifier.
  final String opId;

  /// Human-readable or machine-readable error description.
  final String error;

  /// How long to wait before this command is eligible for retry.
  final Duration retryAfter;
}

/// Outbox persistence contract.
///
/// The sync runtime uses this store to queue commands, reserve batches,
/// and commit results. Implementations are typically backed by a local
/// SQLite / Drift table with columns for status, attempts, and retry timing.
abstract interface class SyncOutboxStore {
  /// Appends a new command row with status `pending`.
  Future<void> append(
    CommandEnvelope<SyncCommand> envelope, {
    Map<String, dynamic>? rebuildContext,
  });

  /// Returns up to [limit] commands that are eligible to send (`pending` or
  /// retryable `failed` rows whose `nextAttemptAtUtc` has passed).
  Future<List<DecodedOutboxCommand>> nextPending({int limit = 100});

  /// Recovers any `inFlight` rows back to `pending`.
  ///
  /// Called at the start of [SyncUnitOfWork.prepareBatch] so abandoned
  /// batches from a crashed previous run are not lost.
  Future<void> recoverInFlightToPending();

  /// Marks the given [opIds] as `inFlight`.
  Future<void> markInFlight(Iterable<String> opIds);

  /// Marks the given [opIds] as terminal success (`acked`).
  Future<void> markAcked(Iterable<String> opIds);

  /// Marks the given [failures] as `failed` with retry metadata.
  Future<void> markManyFailed(Iterable<OutboxFailureUpdate> failures);

  /// Whether any `pending` or `inFlight` rows remain.
  Future<bool> hasUnsettledCommands();

  /// Removes all rows. Used by auth reset flows.
  Future<void> clear();
}
