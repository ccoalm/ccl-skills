# SLI / SLO / Error Budget Design

Industry baseline: Google SRE Workbook ch. 2–4 ("Implementing SLOs"). Use those formal definitions; this reference is the operational shortlist.

## Define SLIs from user-visible journeys, not internal counters

Bad SLI: "DB query success rate."
Good SLI: "Successful checkout request rate (user clicks pay → response 2xx within 3 seconds)."

For each top user journey, write at least:
- **Availability SLI** — successful requests / total requests, in a measurement window.
- **Latency SLI** — the proportion of requests faster than a threshold T: `count(latency ≤ T) / total` (from histogram buckets). A p95/p99 *value* is a dashboard aid, NOT the SLI (Google SRE: an SLI is good events / valid events).

For queue-driven flows:
- **Freshness SLI** — events processed within N seconds of arrival.
- **Throughput SLI** — sustained events per second under acceptable backlog.

## Concretize as a query against the long-term metric store

Example (PromQL-style):

```
# Availability for journey X
# Uses separate counters per framework-middleware-checklist.md:
#   request_total       = baseline + route + method labels (no status_class)
#   request_error_total = 5xx with error_class label
1 - (
  sum(rate(http_server_request_error_total{service="<svc>", route="<route>"}[5m]))
  /
  sum(rate(http_server_request_total{service="<svc>", route="<route>"}[5m]))
)
```

```
# Latency SLI: proportion of requests faster than threshold T (good / total) — NOT a percentile value
sum(rate(http_server_request_duration_seconds_bucket{service="<svc>", route="<route>", le="<T>"}[5m]))
/
sum(rate(http_server_request_duration_seconds_count{service="<svc>", route="<route>"}[5m]))
# (p95/p99 via histogram_quantile is a dashboard diagnostic, not the SLI input)
```

> The SLO threshold `T` MUST be a real explicit histogram bucket boundary (`le="<T>"` must exist); if it isn't, add/migrate the bucket boundary before claiming the SLI — otherwise the query is empty or silently uses a wrong nearby bucket.

If you cannot write the query against existing metrics, the metric set is incomplete. Add the metric before claiming the SLI.

## SLO target

Pick a number that reflects user expectation and product maturity, not aspiration:
- New service: 99.0% — generous.
- Mature service: 99.9% — three nines.
- Critical path (payment, login): 99.95% — push.
- Never start with 99.99% without 24/7 staffing.

Lower the target if every release burns the budget. Raise it only after sustained achievement.

## Error budget

`error_budget = 1 - SLO`. Tracked in the same window as the SLI (rolling 30 days is the default).

Operational rule: if error budget is exhausted, the service stops shipping non-critical changes until the budget recovers. This makes SLOs actually mean something.

## Burn-rate alerts

Multi-window, multi-burn-rate per Google SRE Workbook:

| Severity | Window | Burn rate | Meaning |
|---|---|---|---|
| Page (P0) | 1h | 14x | Will exhaust 30d budget in ~2 days at this rate |
| Page (P0) | 5min | 14x | Same, but fast detection |
| Notify (P1) | 6h | 6x | Will exhaust in 5 days |
| Digest (P2) | 24h | 1x | Sustained at SLO threshold |

Alert query template:

```
slo_burn_rate{...} > <threshold>
```

Each burn rate alert MUST link to a runbook entry.

## Anti-patterns

- SLI written as "DB up" — that is a probe, not a user-facing SLI.
- SLO set to 100% — leaves no budget for releases.
- Burn rate calculated over 1 minute → false-positive paging on natural noise.
- One SLI per service — composite journeys lose visibility.
- SLO without error-budget-driven release policy → number on a wall.

## Releases consume budget

The release skill (`platform-release-engineering`) MUST query the SLI / budget before promoting a canary. A canary is only promoted if:
- Its burn rate during the bake window is within budget.
- The cumulative budget for the release window is not exhausted.

This is the handoff: observability owns the signal; release owns the gate.
