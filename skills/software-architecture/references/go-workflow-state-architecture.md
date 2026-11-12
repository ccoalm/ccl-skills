# Workflow State Architecture

Use this when designing durable task, async workflow, import/export, backfill, or scheduled processing state.

## State Contract

- Define state enum, terminal states, allowed transitions, retry policy, and ownership before handlers are written.
- Keep allowed transitions in one table, diagram, or policy function so handlers do not invent their own rules.
- Separate state, progress, result pointer, error metadata, retry metadata, and audit metadata.
- Persist the task record before starting expensive work, background execution, or external artifact generation so process failure leaves an inspectable and repairable state.
- Define duplicate handling for every entrypoint: create, start, process, fail, succeed, cancel, and retry.
- Transitions that affect durable truth need compare-and-update, transaction, or lock.
- Completion events should be published after durable state update and should be idempotent.

## Processing Semantics

- Create should be idempotent when the caller supplies an idempotency key or natural unique key.
- Start should claim ownership before expensive side effects.
- Process should re-check state after ownership is acquired.
- Success should persist result data before publishing completion.
- Failure should record canonical error code, safe message, retryable flag, retry count, and trace or log id.
- Cancellation should define whether in-flight work is interrupted, allowed to finish, or marked for later stop.

## Retry And Recovery

- Retry threshold and backoff belong in policy/config, not inline literals.
- Terminal state recovery must be explicit; ordinary retries should not move successful or cancelled tasks.
- Delayed events and queue messages must re-check current state before acting.
- Process restart should leave enough durable state to resume, retry, or safely skip.
- Background goroutines, workers, and scheduled cleaners need panic recovery and a bounded cursor/batch model; long-lived loops should use stoppable tickers or an explicit process-lifetime owner.

## Acceptance Checks

- Illegal transitions are rejected or no-op according to a documented policy.
- Duplicate messages, delayed messages, and concurrent processors produce one durable outcome.
- Every terminal state includes enough result or error context for support and reconciliation.
- Expensive background work cannot start without an inspectable durable task record or an explicitly documented non-durable rationale.
- Worker, goroutine, scheduler, and cleaner paths have panic recovery, bounded scan/batch behavior, and a visible recovery or repair result.
