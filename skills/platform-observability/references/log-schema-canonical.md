# Canonical Log Schema (Concrete Field Set)

The authoritative field list for structured platform logs, derived from a working production deployment. Use as a template; localize header names but preserve the field shape.

## Required fields (every log line)

| Field | Type | Purpose |
|---|---|---|
| `_ts` | keyword | ISO-8601 timestamp with timezone (e.g. `2026-05-20T14:23:01.123+08:00`) |
| `_datetime` | date | Parsed timestamp for the search backend |
| `_timestamp` | long | Unix ms (Asia/Shanghai or UTC; document the choice) |
| `_level` | keyword | TRACE / DEBUG / INFO / WARN / ERROR / FATAL (OTel-spec severity text) |
| `_msg` | text | Message body |
| `_logid` | keyword | Platform log-id (correlation handle, generated at edge if absent) |
| `_trace_id` | keyword | OTel trace id (hex) |
| `_span_id` | keyword | OTel span id (hex) |
| `_trace_flags` | keyword | OTel trace flags |
| `_psm` | keyword | Service identity (PSM-style or `service.name` OTel attr) |
| `_lane` / `_env` | text | Lane / environment label |
| `_idc` | text | Region / data center |
| `_cluster` | text | Kubernetes cluster name |
| `_pod` | text | Pod name |
| `_addr` | ip | Service IP (pod IP) |
| `_caller` | text | Source file:line where the log was emitted (file.go:123 form) |
| `_language` | text | Programming language (go, python, java, ...) |

Fields prefixed `_` are platform-reserved. Application fields use `app_*` or `biz_*` prefix to prevent collision.

`_stack` (type `text`) is set only for ERROR and above; contains the full stack trace.

## Why each field

- `_logid` — human-friendly correlation id; the only id a user reports in a ticket.
- `_trace_id` + `_span_id` — cross-service trace join; OTel-managed.
- `_caller` — source location; powerful for diff-based canary checks (see `platform-release-engineering/references/lane-orchestration-control-plane.md` § canary algorithm). Two services that emit "DB timeout" from different code lines are correctly distinguished.
- `_language` — multi-language platforms need this to group / filter log queries; also useful for stack-format detection.
- `_addr` / `_pod` — drill from "lane has problem" → "this specific pod" → "this specific replica".
- `_idc` / `_cluster` — multi-region / multi-cluster drilldown.

## Index template (Elasticsearch / OpenSearch)

```yaml
setup.template:
  enabled: true
  overwrite: true
  pattern: "bizlogs-*"        # localize prefix
  fields: fields.yml
  order: 140
  settings:
    index.number_of_shards: 3
    _source.enabled: true
  mappings:
    dynamic: true
    dynamic_date_formats: "strict_date_optional_time"
    date_detection: true
```

3 shards is a reasonable default for cluster sizing 10-50 nodes. Adjust based on ingest rate.

## ILM policy

Hot 7 days, then delete is a common defensible default for biz logs:

```yaml
policy:
  phases:
    hot:
      min_age: "0ms"
      actions:
        rollover:
          max_age: "7d"
          max_size: "30gb"
    delete:
      min_age: "7d"
      actions:
        delete: {}
```

Adjust by:
- **Compliance** — some industries require 90 days+ of audit logs (set a separate index/policy for audit-class logs).
- **Cost** — warm tier (cheaper storage) for 30-90 days is a middle ground.
- **Investigation cadence** — if incidents are typically detected and root-caused within 7d, 7d hot is sufficient.

Separate ILM policies for `audit-*` (long retention), `bizlogs-*` (7d), `debug-*` (1-3d) prevents pinning all retention to the strictest requirement.

## Filebeat configuration shape

```yaml
filebeat.inputs:
  - type: log
    id: bizlogs
    enabled: true
    paths:
      - /opt/<org>/app/log/*.log
      - /opt/<org>/app/log/*/*.log
      - /opt/<org>/app/log/*/*/*.log         # per-service/per-lane subdirs
    fields_under_root: true
    json:
      keys_under_root: true
      overwrite_keys: false                  # CRITICAL: see "Platform-field protection" below
      add_error_key: true

processors:
  - add_host_metadata:
      when.not.contains.tags: forwarded
  - script:
      lang: javascript
      id: extract_ts
      file: ${path.config}/extract_ts.js   # custom timestamp parser if needed
  - timestamp:
      field: "_timestamp"
      target_field: "_datetime"
      layouts: ["UNIX_MS"]
      timezone: "Asia/Shanghai"            # or UTC
```

`fields_under_root: true` + `json.keys_under_root: true` together mean: the JSON log line's fields become root-level fields in the indexed document. So `_logid` from the log → `_logid` in Elasticsearch. No nested `parsed.<field>` digging.

### Platform-field protection

**Do NOT set `overwrite_keys: true` with `keys_under_root: true` for reserved fields.** A compromised or malicious service could emit `{"_lane":"prod", "_level":"INFO", "_msg":"..."}` from a non-prod pod, and the log pipeline would index it as if it came from prod with INFO severity — corrupting canary queries, audit searches, and incident triage.

Enforcement options (pick at least one):
1. **Logstash filter strips/renames `_`-prefixed fields supplied by the app**, then re-injects authoritative `_lane`, `_psm`, `_idc`, `_cluster`, `_pod`, `_addr` from metadata the pipeline knows for sure (e.g. from k8s pod annotations the filebeat shipper adds).
2. **Filebeat `processors.drop_fields`** removes a denylist of app-supplied platform fields before they hit logstash.
3. **Application logger contract**: SDK is the only code path that writes `_`-prefixed fields; lint rule rejects app code that touches them directly.

Layered defense is best: SDK contract (#3) for the common case + pipeline strip (#1) as the durable guardrail in case the SDK is bypassed.

## Log path layout

Services write structured JSON logs to disk (not stdout in this pattern). Layout:

```
/opt/<org>/app/log/
  <psm-1>/
    <lane-A>/
      app.log
      app-error.log
    <lane-B>/
      ...
  <psm-2>/
    ...
```

Why files not stdout (in this pattern):
- Per-service per-lane separation: cleaner debugging.
- File rotation (size + time) is well-tooled.
- Filebeat reads efficiently with offset tracking.
- App can keep writing during transient filebeat outages (file buffer absorbs).

Why stdout in other patterns (mature alternative):
- k8s-native; logs visible to `kubectl logs`.
- No volume mount needed.
- Cloud-native log shippers (Cloud Logging, etc.) usually pull from stdout.

Pick one per platform; do not mix.

## In-pod sidecar vs DaemonSet collection

Two patterns:

**DaemonSet** (one filebeat per node, hostPath mount):
```
Node
├─ filebeat (DaemonSet pod)
│   └─ reads /opt/<org>/app/log/* via hostPath
└─ App pods write to /opt/<org>/app/log/<psm>/<lane>/
```
Pros: one filebeat process per node, low overhead.
Cons: hostPath access required; not compatible with serverless k8s.

**Sidecar** (one filebeat per app pod):
```
App Pod
├─ app container       writes to emptyDir
└─ filebeat container  reads emptyDir
```
Pros: works in serverless k8s (no hostPath); per-pod resource accounting.
Cons: filebeat container per pod multiplies resource cost.

Many platforms use **both**, selected by pod environment: serverless k8s (e.g. cloud-provider container instance) → sidecar; node-attached k8s → DaemonSet.

## Output endpoints by environment

Online (production) and offline (staging/dev) typically have different log backends:

```yaml
output:
  elasticsearch:
    hosts: [{{ online_es_host or offline_es_host }}]

setup.kibana:
  host: {{ online_kibana_host or offline_kibana_host }}
```

Reasons to split:
- Cost: offline ES can be smaller, single-node, no replicas.
- Isolation: a dev mistake bursting logs doesn't pressure prod ES.
- Compliance: prod logs may need stricter access control.

## Verification

- Open a service log line in kibana → all required fields present, no missing fields.
- Search `_trace_id:<id>` → returns all hops of one trace.
- Search `_caller:<source-location>` → returns the same error pattern across the fleet.
- ILM rollover triggers at 7d / 30gb (test by writing high volume to a non-critical index).
- Cluster failure of online ES → filebeat buffers locally; resumes when ES returns.
