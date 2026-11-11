# Performance And Capacity Architecture

Use this when a Go backend needs capacity planning, load-shedding, batch processing, replay, shadow rollout, or database/query safety. Keep it product-agnostic.

## Design Surfaces

- Define expected QPS, concurrency, p95/p99 latency, timeout budget, payload size, data volume, and batch size before implementation.
- Decide which paths are synchronous, async, scheduled, backfill, replay, or shadow-only.
- Put admission control in the architecture: per-route rate limits, concurrency limits, queue limits, backpressure, and overload behavior.
- Long-running work needs durable task state, lease/lock, retry count, timeout threshold, terminal failure, and repair visibility.
- Batch jobs need dry-run/report mode, cursor or checkpoint, max rows per batch, bounded concurrency, error samples, and resume behavior.

## Database Capacity

- Treat indexes and query plans as architecture requirements for high-cardinality reads and list APIs.
- Define pagination/cursor policy and avoid unbounded offset scans on large tables.
- Connection pools must match expected concurrency and DB limits.
- Add non-production query-plan checks where practical, but do not run expensive EXPLAIN hooks in production traffic.
- Schema migrations need rollout order, backfill plan, rollback notes, and online DDL strategy when tables may be large.

## Replay And Shadow Capacity

- Replay and shadow systems must not compete unchecked with production traffic.
- Define max concurrency, delay, timeout, filters, comparison threshold, and result retention.
- Lock scheduled replay jobs so only one instance runs per scope.
- Keep replay/shadow results separate from production truth unless explicitly promoted.

## Launch Readiness

Before launch, require evidence for:

- latency under expected and peak concurrency;
- DB pool saturation and slow query profile;
- cache hit/miss behavior;
- queue depth and retry rate;
- downstream timeout/fallback behavior;
- pprof or equivalent debug exposure policy;
- rollback or traffic-disable switch.
