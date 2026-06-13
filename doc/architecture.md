# Architecture

`cqrs_offline_sync` is a generic sync runtime module. Its interface is the set
of public contracts a host app must satisfy: command codecs, persistence stores,
transport, table change handlers, conflict resolution, and transaction runners.

The implementation is the package code behind that interface: command envelope
creation, outbox lifecycle, batch preparation, push/pull execution, pull-side
change application, conflict action commits, and delete-rebuild planning.

## Depth

The module is intended to be deep: host apps provide a small set of adapters and
receive a full sync run loop in return.

Callers should not need to know the ordering details inside the implementation:

- recover abandoned in-flight commands
- select pending commands
- mark selected commands in-flight
- call transport
- apply server changes
- resolve command outcomes
- advance cursor and epoch state
- preserve retryable commands on failure

Those details are package locality. Bugs in those mechanics should be caught by
package tests, not rediscovered in every host app.

## Seams And Adapters

The important seams are:

- `SyncOutboxStore`: command row persistence.
- `SyncStateStore`: cursor and epoch persistence.
- `SyncConflictLogStore`: optional conflict diagnostics.
- `SyncRebuildInstructionStore`: optional delete-rebuild persistence.
- `SyncTransport`: push/pull transport.
- `SyncTableChangeHandler`: table-specific pull application.
- `ConflictResolver`: stale command policy.
- `SyncResyncHandler`: epoch mismatch handling.

Adapters satisfy those interfaces. Lateinorum is one production adapter set. The
package tests use private in-memory adapters to prove the same seams without any
Lateinorum dependency.

## Host-Side Composition

`SyncModuleRegistration` is an optional host-side composition module. It groups a
domain module's sync pieces:

- command codecs
- table change handlers
- stale conflict profiles
- local data scope
- rebuild graph

The runtime ultimately consumes the collected pieces. Apps can use
`SyncModuleRegistration` when it improves locality, or wire the pieces directly.

## Test Strategy

Package tests validate protocol and runtime mechanics, not host app policy.

They should be strict about correctness-relevant ordering:

- recovery before selection
- reservation before transport
- change application before result commit
- no ack on transport failure
- monotonic cursor advancement
- deterministic conflict action commits

They should avoid testing domain choices such as whether a particular app should
drop, replay, or rebuild a stale command. Host apps own those decisions.
