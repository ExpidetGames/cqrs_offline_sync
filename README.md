# cqrs_offline_sync

Command-based offline-first sync runtime primitives for Dart apps.

This package owns generic sync mechanics. A host app owns domain commands,
persistence, transport, and table-specific change application.

The current audience is future maintainers and project agents validating the
package across real projects. It is not yet shaped for pub.dev publication.

## What the package owns

- Command envelopes and codecs.
- Outbox write helpers.
- Sync batch preparation and commit mechanics.
- The coalesced sync runner.
- Pull-side server change dispatch.
- Conflict resolution mechanics.
- Delete-rebuild planning primitives.
- Protocol models for push/pull and bootstrap replace.

## What the host app owns

- Domain command payloads implementing `SyncCommand`.
- Command codecs registered in `CommandCodecRegistry`.
- Persistence adapters for outbox, sync state, conflict logs, and rebuild instructions.
- A transport adapter implementing `SyncTransport`.
- Table change adapters implementing `SyncTableChangeHandler`.
- Optional conflict policy via `ConflictResolver`.
- Optional resync handling via `SyncResyncHandler`.
- The local transaction runner used for writes and sync commits.

## Adapter Checklist

Before a host app can run sync, provide these adapters and registrations:

- `SyncCommand` payloads for each local write that must sync.
- `CommandPayloadCodec<T>` for each payload type.
- `CommandCodecRegistry` collecting all codecs.
- `SyncOutboxStore` for pending, in-flight, acked, and failed command rows.
- `SyncStateStore` for last server cursor and sync epoch.
- `SyncPersistenceTransactionRunner` for sync runtime commits.
- `SyncCommandWriter`, usually `PersistentSyncCommandWriter`.
- `SyncWriteUnitOfWork` around local writes that append commands.
- `SyncTransport` for one push/pull round-trip.
- `SyncTableChangeHandler` per server feed table.
- `ServerChangeApplier`, usually `CompositeServerChangeApplier`.
- Optional `SyncConflictLogStore` for diagnostics.
- Optional `SyncRebuildInstructionStore` for delete-rebuild conflict recovery.
- Optional `ConflictResolver` for stale command outcomes.
- Optional `SyncResyncHandler` for epoch mismatch responses.
- Optional `SyncTriggerSink` to schedule sync after local writes.

## Optional Host-Side Composition

`SyncModuleRegistration` is a convenience contract for apps with multiple
syncable domain modules. It groups one module's codecs, table handlers, stale
conflict profiles, local data scope, and rebuild graph.

The runtime does not require Riverpod, Flutter, Supabase, Drift, or a specific
folder layout. A host app can collect the same pieces directly, or use
`SyncModuleRegistration` to keep module-local sync knowledge together.

## Minimal Runtime Shape

```dart
final registry = CommandCodecRegistry(<AnyCommandCodec>[
  createNoteCommandCodec,
]);

final stateStore = MySyncStateStore();
final outboxStore = MySyncOutboxStore();
final envelopeFactory = CommandEnvelopeFactory(
  codecRegistry: registry,
  opIdGenerator: const UuidOpIdGenerator(),
  clock: const SystemUtcClock(),
);

final runner = SyncRunner(
  unitOfWork: SyncUnitOfWork(
    transactionRunner: myTransactionRunner,
    outboxStore: outboxStore,
    syncStateStore: stateStore,
    envelopeFactory: envelopeFactory,
  ),
  transport: MySyncTransport(),
  changeApplier: CompositeServerChangeApplier(
    handlers: <SyncTableChangeHandler>[MyNotesChangeHandler()],
  ),
);
```

See `example/cqrs_offline_sync_example.dart` for a runnable in-memory notes
sync example.

## Runtime Invariants

- In-flight outbox rows are recovered before a new batch is selected.
- Selected outbox rows are marked in-flight before transport runs.
- Transport failure leaves commands retryable instead of acked.
- Server changes apply before command results are committed.
- Cursor writes are monotonic through `SyncStateStore.writeLastServerCursorIfAdvanced`.
- Conflict resolution commits one action per in-flight command in the batch.
- Rebuild instructions clear only when no unsettled outbox commands remain.

## More Detail

- `doc/architecture.md` explains the package module, interface, seams, adapters,
  and test strategy.
- `example/cqrs_offline_sync_example.dart` shows one complete in-memory adapter.
