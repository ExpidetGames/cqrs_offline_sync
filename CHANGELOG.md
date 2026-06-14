## 1.0.0

### New features

- Added `CqrsSyncRuntime.compose(...)` as the host-agnostic composition entrypoint for building a sync runtime.
- Added `SyncStores`, `SyncRuntimeContributions`, `SyncRuntimeQueueReset`, and `LocalDataResetService` to support the composition facade.
- Added `SyncChangeApplicationConfig` and `SyncDeleteRebuild` for configuring server change application.
- Added `SyncConflictResolution` sealed configuration for stale conflict resolution (`auto`, `disabled`, `defaults`, `custom`).
- Added package `DefaultConflictResolver` that routes stale conflicts through `StaleConflictProfile`s based on a `SyncStaleRoutingPolicy`.
- Added `SyncStaleRoutingPolicy` with built-in implementations: `recoverableMissingRowOnly()`, `alwaysRoute()`, and `custom(...)`.
- Added `StaleConflictRoutingContext` for routing policy decisions.
- Added `StaleConflictProfileRegistry.tryResolve(...)` alongside the existing throwing `resolve(...)`.
- Added `requiresRebuildInstructions` getter to `StaleConflictProfile`.
- Added `String? reasonCode` to `SyncCommandResult` with stable machine-readable reason codes.
- Added `SyncCommandResultReasonCodes` with `recoverableMissingRow`.
- Added no-op store implementations: `NoopSyncConflictLogStore` and `NoopSyncRebuildInstructionStore`.
- Added `SyncBootstrapReplaceService` and `SyncBootstrapReplaceClient` for device-wins bootstrap flows.
- Added same-run pull pagination to `SyncRunner`: `runOnce()` now loops while the server response signals `hasMore`.

### CLI

- `cqrs_sync init` now generates a `sync_runtime.dart` entrypoint using `CqrsSyncRuntime.compose(...)` and a root `README.md` with integration snippets.
- `cqrs_sync init` now creates `runtime/local_data/` instead of `runtime/auth/`, and `stores/` instead of `database/` and `outbox/`.
- `cqrs_sync init` no longer creates `providers/`.
- `cqrs_sync create module` now generates local data scopes under `runtime/local_data/`.
- Backend TypeScript templates now include `reasonCode` fields.

### Docs

- Rewrote `doc/getting_started.md` and `doc/api_overview.md` to present the new `CqrsSyncRuntime.compose(...)` happy path.
- Updated `example/cqrs_offline_sync_example.dart` to use `CqrsSyncRuntime.compose(...)` and `runtime.createWriteUnitOfWork(...)`.