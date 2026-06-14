# API Overview

This document maps every public export of `cqrs_offline_sync` to its subsystem and typical usage.

## Commands (`src/commands/`)

### `command_envelope_factory.dart`
- **`CommandEnvelopeFactory`** — creates `CommandEnvelope<SyncCommand>` with injected `OpIdGenerator` and `UtcClock`
- **`OpIdGenerator`** — contract for generating `opId` strings
- **`UuidOpIdGenerator`** — UUID-v4 implementation using `generateSyncUuidV4()`
- **`UtcClock`** — contract for current UTC time
- **`SystemUtcClock`** — `DateTime.now().toUtc()` implementation

### `command_envelope.dart`
- **`CommandEnvelope<T extends SyncCommand>`** — typed envelope carrying `opId`, `occurredAtUtc`, `aggregateType`, `commandType`, `payload`, `baseCursor`

### `command_codec_registry.dart`
- **`AnyCommandCodec`** — base codec contract
- **`CommandPayloadCodec<T>`** — typed codec with `fromJson`/`toJson`
- **`CommandCodecRegistry`** — runtime registry mapping `commandType` and payload `Type` to codecs; creates and validates envelopes

### `sync_command.dart`
- **`SyncCommand`** — marker interface for all sync command payloads

## Outbox (`src/outbox/`)

### `sync_command_writer.dart`
- **`SyncCommandWriter`** — contract for appending a command envelope to outbox storage

### `persistent_sync_command_writer.dart`
- **`PersistentSyncCommandWriter`** — `SyncCommandWriter` that reads the current cursor from `SyncStateStore` and wraps payloads with `CommandEnvelopeFactory`

## Persistence (`src/persistence/`)

### `sync_outbox_store.dart`
- **`SyncOutboxStore`** — read pending, mark in-flight, ack, fail, retry

### `sync_state_store.dart`
- **`SyncStateStore`** — read/write `lastServerCursor` monotonically; read/write `syncEpoch`

### `sync_conflict_log_store.dart`
- **`SyncConflictLogStore`** — audit log for conflict decisions; now includes `clear()`

### `sync_rebuild_instruction_store.dart`
- **`SyncRebuildInstructionStore`** — persist and consume `RebuildInstruction` objects for stale recovery

### `noop_sync_conflict_log_store.dart`
- **`NoopSyncConflictLogStore`** — default no-op implementation of `SyncConflictLogStore`

### `noop_sync_rebuild_instruction_store.dart`
- **`NoopSyncRebuildInstructionStore`** — default no-op implementation of `SyncRebuildInstructionStore`

### `sync_transaction_runner.dart`
- **`SyncTransactionRunner`** — runs a callback inside the host app's database transaction (used by both sync commits and write-side UoW)

## Protocol / Transport DTOs (`src/protocol/`)

### `server_change.dart`
- **`ServerChange`** — base class for `UpsertServerChange` and `DeleteServerChange`
- **`UpsertServerChange`** — `table`, `rowId`, `row` map
- **`DeleteServerChange`** — `table`, `rowId`

### `sync_batch_request.dart`
- **`SyncBatchRequest`** — `sinceCursor`, `commands` list, `pull` config

### `sync_batch_response.dart`
- **`SyncBatchResponse`** — `commandResults`, `changes`, `newCursor`, `hasMore`, `resyncRequired`, `expectedSyncEpoch`
- **`SyncCommandResult`** — per-command result; includes `reasonCode` for machine-readable routing

### `sync_command_result_reason_codes.dart`
- **`SyncCommandResultReasonCodes`** — stable reason code constants, e.g. `recoverableMissingRow`

### `sync_bootstrap_replace_request.dart`
- **`SyncBootstrapReplaceRequest`** — `snapshot` map, `expectedSyncEpoch`, `confirmationToken`
- **`SyncBootstrapReplaceSnapshot`** / **`SyncBootstrapReplaceTableSnapshot`** — generic local snapshot shapes

### `sync_bootstrap_replace_response.dart`
- **`SyncBootstrapReplaceResponse`** — `newCursor`, `newSyncEpoch`

### `sync_cursor.dart`
- **`SyncCursor`** / **`SyncEpoch`** — typed wrappers around numeric values with comparison helpers

## Runtime Local Data (`src/runtime/local_data/`)

### `local_data_scope.dart`
- **`LocalDataScope`** — per-module `hasData()` / `clear()` contract; `id` is a `String`

## Runtime Composition (`src/runtime/composition/`)

### `cqrs_sync_runtime.dart`
- **`CqrsSyncRuntime`** — host-agnostic composition facade; `CqrsSyncRuntime.compose(...)` is the main entrypoint
- **`SyncStores`** — immutable collection of outbox, state, conflict log, and rebuild instruction stores
- **`SyncRuntimeContributions`** — extra codecs, handlers, profiles, scopes, and rebuild edges beyond module contributions
- **`SyncRuntimeQueueReset`** — clears outbox, conflict log, and rebuild instructions without touching sync state
- **`LocalDataResetService`** — generic reset orchestrator for registered `LocalDataScope`s
- **`SyncChangeApplicationConfig`** — change application configuration, including `SyncDeleteRebuild` policy
- **`SyncConflictResolution`** — sealed configuration for stale conflict resolution (auto / disabled / defaults / custom)
- **`SyncRuntimeConfigurationException`** — exception thrown for invalid `compose(...)` configuration

## Runtime Change Applier (`src/runtime/change_applier/`)

### `composite_server_change_applier.dart`
- **`CompositeServerChangeApplier`** — two-pass orchestrator that sorts changes, captures delete-rebuild instructions, and dispatches to handlers

### `server_change_decision_policy.dart`
- **`ServerChangeDecisionPolicy`** — `applyServer` vs `keepLocal` hook
- **`AlwaysApplyServerChangeDecisionPolicy`** — default policy that always applies server changes

### `server_change_row_reader.dart`
- **`ServerChangeRowReader`** — strict typed reader for `UpsertServerChange.row` maps with alias support

### `sync_table_change_handler.dart`
- **`SyncTableChangeHandler`** — per-table contract: `tableName` + `apply(change)`

## Runtime Conflict (`src/runtime/conflict/`)

### `command_resolution_action.dart`
- **`CommandResolutionAction`** — `ack`, `requeue`, `fail`

### `conflict_resolution_context.dart`
- **`ConflictResolutionContext`** — carries the stale command, its result, local cursor, and available rebuild instructions

### `conflict_resolution_plan.dart`
- **`ConflictResolutionPlan`** — list of per-command actions produced by the resolver

### `conflict_resolver.dart`
- **`ConflictResolver`** — contract: `resolve(context)` -> `ConflictResolutionPlan`

### `default_conflict_resolver.dart`
- **`DefaultConflictResolver`** — ready-to-use resolver that routes stale commands through profiles based on a `SyncStaleRoutingPolicy`

### `drop_stale_conflict_profile.dart`
- **`DropStaleConflictProfile`** / **`DropTypedStaleConflictProfile`** — profile that always drops (acks) stale commands

### `requeued_command.dart`
- **`RequeuedCommand`** — wrapper for a replayed/rebuilt command with its fresh envelope

### `replay_stale_conflict_profile.dart`
- **`ReplayStaleConflictProfile`** / **`ReplayTypedStaleConflictProfile`** — profile that replays the same payload with a fresh cursor

### `resolution_decision.dart`
- **`ResolutionDecision`** — `drop`, `replay`, `rebuild`

### `stale_conflict_profile.dart`
- **`StaleConflictProfile`** — base contract for per-command-type stale resolution logic
- **`TypedStaleConflictProfile<T>`** — typed base class that casts payload before delegating to `resolveTyped`

### `stale_conflict_profile_registry.dart`
- **`StaleConflictProfileRegistry`** — maps `commandType` to profile; now throws `ArgumentError` on duplicate command types

### `stale_conflict_routing_context.dart`
- **`StaleConflictRoutingContext`** — context for `SyncStaleRoutingPolicy` decisions

### `sync_stale_routing_policy.dart`
- **`SyncStaleRoutingPolicy`** — policy class for routing stale conflicts to profiles
  - **`recoverableMissingRowOnly(...)`** — route only `reasonCode == recoverable_missing_row`, with optional legacy `reason` prefix fallback
  - **`alwaysRoute()`** — route every stale command to its profile
  - **`custom(...)`** — user-supplied predicate

## Runtime Rebuild (`src/runtime/rebuild/`)

### `delete_rebuild_planner.dart`
- **`DeleteRebuildPlanner`** — contract: given a delete change, return a `RebuildInstruction`

### `graph_delete_rebuild_planner.dart`
- **`GraphDeleteRebuildPlanner`** — `DeleteRebuildPlanner` backed by a `RebuildGraph`

### `rebuild_graph.dart`
- **`RebuildGraph`** — graph of entity nodes with `loadAll()` / `toSnapshot()` for delete-rebuild and bootstrap-replace
- **`RebuildGraphNode`** — single node: table name, parent relation, projection
- **`RebuildGraphEdge`** — parent-child edge for subtree traversal

### `rebuild_instructions.dart`
- **`RebuildInstruction`** / **`RebuildInstructions`** — data classes describing how to recreate a deleted subtree

### `server_change_applier.dart`
- **`ServerChangeApplier`** — contract for the apply phase: `apply(changes)` -> `ServerChangeApplyResult`

## Runtime Bootstrap (`src/runtime/bootstrap/`)

### `sync_bootstrap_replace_client.dart`
- **`SyncBootstrapReplaceClient`** — host-provided client contract for the bootstrap-replace endpoint

### `sync_bootstrap_replace_service.dart`
- **`SyncBootstrapReplaceService`** — builds a snapshot from `RebuildGraph`, calls the client, and persists the new cursor/epoch

## Runtime Orchestration (`src/runtime/`)

### `sync_module_registration.dart`
- **`SyncModuleRegistration`** — one-per-module contract exposing codecs, handlers, profiles, scope, rebuild graph

### `sync_resync_handler.dart`
- **`SyncResyncHandler`** — callback contract for `resync_required` server signals

### `sync_runner.dart`
- **`SyncRunner`** — coalesced `runOnce()` loop: prepare → transport → apply → resolve → commit; supports pull pagination loops

### `sync_run_phase.dart`
- **`SyncRunPhase`** — enum: `idle`, `syncingUp`, `pulling`, `applyingChanges`

### `sync_transport.dart`
- **`SyncTransport`** — contract for one push/pull round-trip

### `sync_unit_of_work.dart`
- **`SyncUnitOfWork`** — batch lifecycle: `prepareBatch`, `commitSuccess`, `commitFailure`, `commitResolved`

## Unit of Work (`src/uow/`)

### `sync_trigger_sink.dart`
- **`SyncTriggerSink`** — contract for requesting a sync run with a reason

### `sync_write_unit_of_work.dart`
- **`SyncWriteUnitOfWork`** — contract wrapping local writes + command append + post-commit trigger emission

## Internal (not exported)

- `src/internal/uuid.dart` — `generateSyncUuidV4()` used by `UuidOpIdGenerator`
- `src/internal/json_parse_utils.dart` — strict JSON parsing helpers for protocol DTOs
