# Workflow State Architecture

Use this when designing durable task, async workflow, import/export, backfill, or scheduled processing state. Implementation mechanics live in `python-service-dev/references/state-machine-task-patterns.md`.

Sibling note: `go-microservice-architecture/references/workflow-state-architecture.md` carries the Go rendering; adapted per stack, kept in sync by review (not under the parallel-stack parity gate).

## State Contract

- Define state enum, terminal states, allowed transitions, retry policy, and ownership before handlers are written.
- Keep allowed transitions in one table, diagram, or policy function so handlers do not invent their own rules.
- Separate state, progress, result pointer, error metadata, retry metadata, and audit metadata.
- Persist the task record before starting expensive work, background execution, or external artifact generation so process failure leaves an inspectable, repairable state.
- Define duplicate handling for every entrypoint: create, start, process, fail, succeed, cancel, and retry.
- Transitions that affect durable truth need compare-and-update, a transaction, or a lock.
- Completion events are published after the durable state update and are idempotent.

## Processing Semantics

- Create is idempotent when the caller supplies an idempotency key or natural unique key.
- Start claims ownership before expensive side effects; process re-checks state after ownership is acquired.
- Success persists result data before publishing completion.
- Failure records canonical error code, safe message, retryable flag, retry count, and trace/log id.
- Cancellation defines whether in-flight work is interrupted, allowed to finish, or marked for later stop.

## Retry And Recovery

- Retry threshold and backoff belong in policy/config, not inline literals.
- Terminal-state recovery is explicit; ordinary retries must not move successful or cancelled tasks.
- Delayed events and queue messages re-check current state before acting.
- Process restart leaves enough durable state to resume, retry, or safely skip.
- Background workers and scheduled cleaners need exception recovery and a bounded cursor/batch model; long-lived loops need a stoppable schedule or an explicit process-lifetime owner (`async-execution-model.md`, `background-jobs-and-scheduling.md`).

## Acceptance Checks

- Illegal transitions are rejected or no-op according to a documented policy.
- Duplicate messages, delayed messages, and concurrent processors produce one durable outcome.
- Every terminal state includes enough result or error context for support and reconciliation.
- Expensive background work cannot start without an inspectable durable task record, or carries an explicitly documented non-durable rationale.
- Worker, scheduler, and cleaner paths have exception recovery, bounded scan/batch behavior, and a visible recovery/repair result.
