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

## CLI

The package includes a small boilerplate generator named `cqrs_sync`.

Run it from a host project root:

```bash
dart run cqrs_offline_sync:cqrs_sync --help
```

If the package is used through a local path dependency, the same command works
after the host project has run `dart pub get` or `flutter pub get`.

### Initialize Sync Files

```bash
dart run cqrs_offline_sync:cqrs_sync init \
  --root lib/sync \
  --project my_app
```

This creates:

- `sync_config.yaml` in the current project.
- The sync folder tree under `--root`.
- README stubs for commands, runtime change application, conflict profiles,
  auth, rebuild, outbox, providers, and database folders.

Options:

- `--root`, `-r`: sync file root. Defaults to `lib/sync`.
- `--project`, `-p`: Dart package name used in generated imports. Defaults to
  `my_app`.

`init` aborts if `sync_config.yaml` already exists.

### Register A Module

```bash
dart run cqrs_offline_sync:cqrs_sync create module notes \
  --database-class NotesDatabase
```

This updates `sync_config.yaml` and creates module-local sync stubs under the
configured sync root:

- `notes_sync_registration.dart`
- `runtime/auth/notes_local_data_scope.dart`
- `runtime/rebuild/notes_rebuild_graph.dart`
- `runtime/conflict/profiles/notes/notes_stale_conflict_profiles.dart`
- module folders for commands, change handlers, conflict models, and snapshots

Options:

- `--database-class`, `-d`: Dart database class for the module. Defaults to the
  PascalCase module name plus `Database`, for example `NotesDatabase`.

### Generate A Command

```bash
dart run cqrs_offline_sync:cqrs_sync create command notes note create \
  --fields "text:String,updatedAt:DateTime"
```

This creates a Dart command payload and codec file under:

```text
<sync_root>/commands/notes_commands/create_note_command.dart
```

It also regenerates `notes_sync_registration.dart` so the new codec appears in
the module's `commandCodecs` list.

The generated command always includes an `id:String` field. Additional fields
come from `--fields` as comma-separated `name:Type` pairs.

Options:

- `--fields`, `-f`: additional payload fields, for example
  `"title:String,count:int"`.
- `--backend`: generate backend TypeScript files too. Enabled by default.
- `--no-backend`: skip backend TypeScript generation.

Backend files are generated only when `sync_config.yaml` contains `backend_root`.
`init` does not set this field yet; add it manually when the host project has a
backend command tree:

```yaml
sync_root: lib/sync
project_package: my_app
backend_root: supabase/functions/sync-v2
```

With `backend_root` set, command generation writes TypeScript stubs under:

```text
<backend_root>/commands/modules/<module>/<entity>/<operation>_<entity>/
```

Generated TypeScript files include:

- `<operation>_<entity>_command.ts`
- `<operation>_<entity>_handler.ts`
- `<operation>_<entity>_stale_policy.ts`
- `<operation>_<entity>_definition.ts`

### Current CLI Limits

- The CLI writes starter boilerplate; generated files still need domain-specific
  table handlers, rebuild graph mappings, stale conflict policy, and backend
  handler implementation.
- The CLI does not update a backend command catalog automatically.
- The CLI does not add package dependencies or run code generation.
- The CLI is intended for internal acceleration, not a polished public workflow.

## More Detail

- `doc/architecture.md` explains the package module, interface, seams, adapters,
  and test strategy.
- `example/cqrs_offline_sync_example.dart` shows one complete in-memory adapter.
