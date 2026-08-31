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

Pick a number that reflects user expectation and product maturity, not aspiration. The ladder below is a **team-heuristic starting point, not an industry standard** — Google SRE literature deliberately gives no numeric ladder; its direction is that each extra nine costs sharply more for marginal utility approaching zero (SRE Workbook Ch.2), and that targets should come from user expectation, not current performance:
- New service: 99.0% — generous.
- Mature service: 99.9% — three nines.
- Critical path (payment, login): 99.95% — push.
- Never start with 99.99% without 24/7 staffing (team heuristic: at four nines the monthly budget is minutes, which no unstaffed rotation can defend).

Lower the target if every release burns the budget. Raise it only after sustained achievement.

## Error budget

`error_budget = 1 - SLO`. Tracked in the same window as the SLI (rolling 30 days is the default).

Operational rule: if error budget is exhausted, the service stops shipping non-critical changes until the budget recovers. This makes SLOs actually mean something.

## Burn-rate alerts

Multi-window, multi-burn-rate per Google SRE Workbook ch. 5, Table 5-6 (2% of a 30d budget in 1h, 5% in 6h, 10% in 3d):

| Severity | Long window | Short window (~1/12 of long) | Burn rate | Meaning |
|---|---|---|---|---|
| Page (P0) | 1h | 5m | 14.4 | Exhausts the 30d budget in ~2 days at this rate |
| Page (P0) | 6h | 30m | 6 | Exhausts in 5 days |
| Ticket (P2) | 3d | 6h | 1 | Sustained exactly at the SLO threshold |

A tier fires only when **both** its long AND short window burn above the threshold. The long window gives detection over meaningful budget consumption; the short window confirms the burn is *still happening now*, so the alert resets quickly once the incident ends — with a long window alone, a resolved 1h page keeps firing for up to an hour, and a 3d ticket for days.

The Workbook's notification types are page and ticket; P0/P2 above are this platform's local severity mapping. The Workbook maps both the 1h and the 6h tier to **page** — that stays the default (at 6×, 5% of the monthly budget is already gone and the 30m window says it is still burning). Downgrading the 6h tier to a non-paging channel is allowed only under a documented, staffed response-time policy showing that tier is acted on before material further budget loss — record it as a deliberate local deviation, never as the Workbook default.

Alert query template (per tier — the recorded metric is the raw error *ratio* per window, as in the Workbook's `slo_errors_per_request:ratio_rate1h`; the burn rate is the multiplier on `(1 - SLO)`, not a pre-divided metric):

```
slo_error_ratio_1h{...}  > 14.4 * (1 - <slo_target>)
and
slo_error_ratio_5m{...}  > 14.4 * (1 - <slo_target>)
# <slo_target> is a literal scalar strictly between 0 and 1, e.g.
# 14.4 * (1 - 0.999) — at 1.0 there is no budget to burn and at 0 the alert
# can never fire (see the 100%-SLO anti-pattern below) —
# a bare `SLO` token would parse as a metric selector and silently match nothing.
# PromQL `and` intersects on the full label set. Invariant: record BOTH window
# rules aggregated to the SAME alert-identity label set — every label that
# distinguishes one alert instance from another (service, route, and region/
# lane if they exist), the window living in the metric NAME, never as a label.
# Identity labels differing between the rules → empty intersection, the page
# silently never fires; an `on(...)` that omits an identity label → cross-match
# (1h burn in one region and-ed with a 5m burn in another) → false page.
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
