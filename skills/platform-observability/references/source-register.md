# platform-observability — impact-chain / owner map

Upstream-owner decision-surface changes record their downstream owners here
(`upstream rule | downstream owner | expected executable behavior | status | evidence`).

| upstream rule (this skill) | downstream / sibling owner | expected behavior there | status | evidence |
|---|---|---|---|---|
| R1 propagation trust boundary; Baggage carries non-authoritative context only; `lane`/routing derived from authenticated identity | `platform-service-connectivity` | mesh/gateway derives lane from identity; routing keys not trusted from inbound Baggage | routed (its domain) | W3C Baggage security note; OTel docs |
| Phase C: non-mesh collector + STRICT mTLS conflict → exception required | `platform-service-connectivity` | owns the mTLS exception YAML (sidecar/ambient PeerAuthentication/DestinationRule); obs only requires it be declared | routed | Istio PeerAuthentication docs |
| R8 SLI = good/valid events ratio; latency = threshold-bucket ratio | `platform-release-engineering` | error-budget release gate consumes these SLIs | unchanged (already references R8) | Google SRE Workbook |
| R3 instance-identity not a metric label; instrument discipline | `go-microservice-architecture` / `python-service-architecture` | language-agnostic rule; no stack-specific glue needed | unchanged | Prometheus / OTel Metrics docs |
