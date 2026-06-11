# Getting Started with `cqrs_offline_sync`

A reusable, host-agnostic Dart library for **command-based offline-first synchronization**.

This package provides the **primitives and contracts** that a host app wires to its own persistence layer and transport client. It does **not** own a database, HTTP client, or UI — it defines the interfaces that your app implements (for example with Drift + Supabase, or Hive + REST).

## What this package does

- **Command envelope encoding** — typed `SyncCommand` payloads with per-type codecs
- **Outbox persistence contracts** — `SyncOutboxStore`, `SyncStateStore`, `SyncConflictLogStore`, `SyncRebuildInstructionStore`
- **Batch preparation & commit** — `SyncUnitOfWork` locks pending rows, builds `SyncBatchRequest`, and commits results
- **Server change application** — `CompositeServerChangeApplier` routes feed rows to per-table `SyncTableChangeHandler`s
- **Stale conflict resolution** — profile-based `ConflictResolver` decides whether to ack, replay, or rebuild a stale command
- **Delete-rebuild planning** — `RebuildGraph` / `DeleteRebuildPlanner` capture and replay lost subtrees
- **Resync & bootstrap-replace DTOs** — transport-neutral request/response shapes

## Installation

Add to your `pubspec.yaml`:

```yaml
dependencies:
  cqrs_offline_sync:
    path: ../cqrs_offline_sync   # or a git / hosted reference
```

## Quick integration checklist

1. **Implement `SyncOutboxStore`, `SyncStateStore`** on your database
2. **Register command codecs** in a `CommandCodecRegistry`
3. **Implement `SyncTableChangeHandler`** for each syncable table
4. **Register modules** via `SyncModuleRegistration`
5. **Wire `SyncRunner`** with your transport (`SyncTransport`) and change applier
6. **Trigger sync** from your scheduler / write-commit hooks (`SyncTriggerSink`)

## Core abstractions

### Persistence (you implement)

| Interface | Responsibility |
|---|---|
| `SyncOutboxStore` | Read pending commands, mark in-flight, ack, fail, retry |
| `SyncStateStore` | Read/write `lastServerCursor` monotonically |
| `SyncConflictLogStore` | Audit log for conflict decisions |
| `SyncRebuildInstructionStore` | Persist/ consume rebuild instructions for stale recovery |
| `SyncTransactionRunner` | Run a callback inside your DB transaction |

### Commands & transport

| Class | Responsibility |
|---|---|
| `CommandCodecRegistry` | Encode/decode `CommandEnvelope<SyncCommand>` by `commandType` |
| `SyncBatchRequest` / `SyncBatchResponse` | Wire DTOs for one push/pull round-trip |
| `SyncTransport` | Your HTTP / WebSocket / edge-function client contract |

### Runtime

| Class | Responsibility |
|---|---|
| `SyncRunner` | Coalesced `runOnce()` loop: prepare → transport → apply → resolve → commit |
| `SyncUnitOfWork` | Batch lifecycle: `prepareBatch`, `commitSuccess`, `commitFailure`, `commitResolved` |
| `CompositeServerChangeApplier` | Two-pass apply: capture delete-rebuild, then dispatch to handlers |
| `ConflictResolver` | Profile-driven stale resolution returning `ConflictResolutionPlan` |
| `SyncResyncHandler` | Callback when server signals `resync_required` |

### Auth / local data boundaries

| Class | Responsibility |
|---|---|
| `LocalDataScope` | Per-module `hasData()` + `clear()` for login/logout/delete-account flows |
| `SyncModuleRegistration` | One per module: codecs, handlers, profiles, scope, rebuild graph |

## Example: minimal module registration

```dart
class VocabTrainerModule implements SyncModuleRegistration {
  @override
  String get moduleId => 'vocab_trainer';

  @override
  List<AnyCommandCodec> get commandCodecs => [
    CommandPayloadCodec<CreateChapterCommand>(
      commandType: 'vocab_trainer.create_chapter',
      aggregateType: 'vocab_trainer',
      fromJson: CreateChapterCommand.fromJson,
      toJson: (c) => c.toJson(),
    ),
  ];

  @override
  List<SyncTableChangeHandler> get tableChangeHandlers => [
    UserChaptersTableChangeHandler(db),
    UserVocabsTableChangeHandler(db),
  ];

  @override
  List<StaleConflictProfile> get staleConflictProfiles => [
    VocabTrainerStaleProfiles.all,
  ];

  @override
  LocalDataScope get localDataScope => VocabTrainerLocalDataScope(db);

  @override
  RebuildGraph get rebuildGraph => vocabTrainerRebuildGraph;
}
```

## Running a sync cycle

```dart
final runner = SyncRunner(
  unitOfWork: myUnitOfWork,
  transport: myTransport,
  changeApplier: myChangeApplier,
  conflictResolver: myConflictResolver,
  resyncHandler: myResyncHandler,
);

// Called from your scheduler or after a local write commits
await runner.runOnce(SyncTriggerReason.localWriteCommitted);
```

## Next steps

- Read [`architecture.md`](architecture.md) for the full sync pipeline, conflict model, and rebuild mechanics.
- Read [`api_overview.md`](api_overview.md) for a per-file summary of every public API.
