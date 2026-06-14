# Getting Started with `cqrs_offline_sync`

A reusable, host-agnostic Dart library for **command-based offline-first synchronization**.

This package provides the **primitives and contracts** that a host app wires to its own persistence layer and transport client. It does **not** own a database, HTTP client, or UI — it defines the interfaces that your app implements (for example with Drift + Supabase, or Hive + REST).

## What this package does

- **Command envelope encoding** — typed `SyncCommand` payloads with per-type codecs.
- **Outbox persistence contracts** — `SyncOutboxStore`, `SyncStateStore`, `SyncConflictLogStore`, `SyncRebuildInstructionStore`.
- **Batch preparation & commit** — `SyncUnitOfWork` locks pending rows, builds `SyncBatchRequest`, and commits results.
- **Server change application** — `CompositeServerChangeApplier` routes feed rows to per-table `SyncTableChangeHandler`s.
- **Stale conflict resolution** — profile-based `ConflictResolver` decides whether to ack, replay, or rebuild a stale command; `DefaultConflictResolver` provides a ready-to-use implementation.
- **Delete-rebuild planning** — `RebuildGraph` / `DeleteRebuildPlanner` capture and replay lost subtrees.
- **Resync & bootstrap-replace DTOs** — transport-neutral request/response shapes, plus `SyncBootstrapReplaceService` for device-wins flows.
- **Runtime composition** — `CqrsSyncRuntime.compose(...)` collects modules, stores, transport, and policies into a single facade.

## Installation

Add to your `pubspec.yaml`:

```yaml
dependencies:
  cqrs_offline_sync:
    path: ../cqrs_offline_sync   # or a git / hosted reference
```

## Quick integration checklist

1. **Implement `SyncOutboxStore`, `SyncStateStore`** on your database.
2. **Register command codecs** in a `CommandCodecRegistry` (or via `SyncModuleRegistration`).
3. **Implement `SyncTableChangeHandler`** for each syncable table.
4. **Register modules** via `SyncModuleRegistration`.
5. **Compose `CqrsSyncRuntime`** with your stores, transaction runner, and transport.
6. **Trigger sync** from your scheduler / write-commit hooks (`SyncTriggerSink`).

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
| `CqrsSyncRuntime` | Composition facade built from modules, stores, transport, and policies |
| `SyncRunner` | Coalesced `runOnce()` loop: prepare → transport → apply → resolve → commit; supports pull pagination |
| `SyncUnitOfWork` | Batch lifecycle: `prepareBatch`, `commitSuccess`, `commitFailure`, `commitResolved` |
| `CompositeServerChangeApplier` | Two-pass apply: capture delete-rebuild, then dispatch to handlers |
| `ConflictResolver` / `DefaultConflictResolver` | Profile-driven stale resolution returning `ConflictResolutionPlan` |
| `SyncResyncHandler` | Callback when server signals `resync_required` |

### Auth / local data boundaries

| Class | Responsibility |
|---|---|
| `LocalDataScope` | Per-module `hasData()` + `clear()` for login/logout/delete-account flows |
| `SyncModuleRegistration` | One per module: codecs, handlers, profiles, scope, rebuild graph |
| `LocalDataResetService` | Generic reset orchestrator built from registered `LocalDataScope`s |
| `SyncRuntimeQueueReset` | Clears runtime queues (outbox, conflict log, rebuild instructions) |

## Example: composed runtime

```dart
final runtime = CqrsSyncRuntime.compose(
  modules: [vocabTrainerModule, latinTextsModule],
  stores: SyncStores(
    outbox: myOutboxStore,
    state: myStateStore,
    conflictLog: myConflictLogStore,
    rebuildInstructions: myRebuildInstructionStore,
  ),
  transactionRunner: myDatabase.transactionRunner,
  transport: mySyncTransport,
  conflictResolution: const SyncConflictResolution.auto(),
);

// Pull changes / push pending commands
await runtime.runner.runOnce(SyncTriggerReason.manual);

// Domain write
await runtime.createWriteUnitOfWork().runVoidWithCommand(
  writeLocal: () async { /* local db write */ },
  command: myCommand,
);
```

## CLI scaffolding

Run the CLI from a host project root:

```bash
dart run cqrs_offline_sync:cqrs_sync init \
  --root lib/sync \
  --project my_app
```

This creates `sync_config.yaml` and a `sync_runtime.dart` entrypoint that uses `CqrsSyncRuntime.compose(...)`.

## Next steps

- Read [`architecture.md`](architecture.md) for the full sync pipeline, conflict model, and rebuild mechanics.
- Read [`api_overview.md`](api_overview.md) for a per-file summary of every public API.
- See `example/cqrs_offline_sync_example.dart` for a runnable in-memory notes sync example.
