# Data Access Patterns

## Repository Shape

- Repositories should expose intent-focused methods such as `GetByID`, `GetByIDs`, `QueryPage`, `Create`, `UpdateStatus`, and `Upsert`.
- Keep `With(tx)` or an equivalent transaction binding method on repositories that participate in multi-write transactions.
- Return `nil, nil` for not-found only when the caller can distinguish it from an empty result; otherwise use a typed not-found error.
- Empty ID lists should be handled deliberately: no-op for optional filters, validation error for required keys.
- Keep raw SQL localized and covered by focused tests.

## Query Design

- Use read connections for reads and write connections for writes when the stack supports read/write separation.
- Use generated query builders for simple equality, range, order, and limit filters.
- For complex queries, keep conditions explicit and parameterized.
- Enforce safe defaults in repository methods: no unbounded list reads on serving paths, no update/delete without conditions, and no generic update with an empty update set.
- Convert time units at the boundary of a repository method and document whether fields use seconds, milliseconds, or database timestamps.
- Avoid offset pagination for long-running large reads; prefer `id > lastID` plus stable ascending order.

## Updates And Upserts

- Update only explicit columns; for upsert helpers, pass the intended update columns explicitly.
- Protect immutable fields such as primary key, create time, creator, and unique domain keys from generic update helpers.
- Use compare-and-update or row locking for counters, quotas, mutable quantities, and state machines.
- Re-read latest state inside a transaction before applying constrained updates or limits.
- Return affected row count when callers need to detect stale state or missing rows.

## Local Memory Cache

- Use local memory cache only for small, frequently read, eventually consistent data.
- Include TTL and capacity.
- Protect maps/LRU state with locks.
- Use singleflight or an equivalent duplicate-suppression mechanism for expensive cache misses.
- Cache key functions must be deterministic, panic-safe, and reject empty keys.
- If local cache is backed by a distributed store, distinguish local hit, distributed hit, miss, decode error, and store failure.
- Start cleanup workers carefully; make sure tests and short-lived commands are not polluted by infinite background goroutines unless acceptable.
- Cleanup workers should use stoppable tickers or be owned by a process-lifetime component with documented lifecycle.
- Cache miss and infrastructure/config failure should be distinguishable in callers.

## Redis Cache And Locks

- Centralize Redis key construction and include environment/lane/resource-scope dimensions where needed.
- Every cache key needs a TTL unless the data is intentionally durable.
- Lock values must be unique per attempt and unlock must compare value before delete.
- Use no-unlock throttling locks only when the lock's purpose is rate reduction and the TTL is the release mechanism.
- For work queues, record enough metadata to recover or inspect stuck work.
- Idempotency keys should include operation identity and retry window, not just message attempt count.

## Dynamic Config

- Wrap dynamic config access behind typed methods.
- Cache config briefly when it is read on hot paths.
- On dynamic config failure, choose an explicit default: fail closed for risk controls, fail open only when product behavior requires availability.
- Log config fetch failures with key name and safe context.
- Keep dynamic config keys stable and documented in code near the typed accessor.
