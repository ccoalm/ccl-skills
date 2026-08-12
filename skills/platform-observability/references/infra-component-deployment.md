# Infrastructure Component Deployment Patterns

Concrete sizing, HA stance, retention, and in-cluster vs externally-hosted decisions for the observability infra stack. From production deployments.

## Component-by-component shape

| Component | Replicas | Stateful? | Storage | Retention | Mesh inject | Notes |
|---|---|---|---|---|---|---|
| OTel collector | 3-4 (Deployment) | No | None | n/a | NO | Multi-replica; tail-sampling possible only here, not at DaemonSet |
| Filebeat (DaemonSet) | one per node | No | hostPath to app log dir | n/a | NO | hostPath mount required; one process per node |
| Filebeat (sidecar, VCI mode) | one per pod | No | emptyDir | n/a | n/a (sidecar in app pod) | For serverless k8s where hostPath is unavailable |
| Logstash | 2-5 (HPA on CPU>70% / Mem>80%) | No | None | n/a | NO | Bulk 500, 2 workers, 5s flush |
| Elasticsearch / OpenSearch | 3+ | Yes | Persistent (often external) | per-ILM | NO | Often externally hosted (see below) |
| Kibana | 1 | No | ConfigMap only | n/a | NO | Single replica fine — read-only UI |
| Grafana | 1-2 | Yes (MySQL backend) | External MySQL for dashboards | dashboards forever | NO | Single replica per env in many platforms |
| Prometheus (scrape layer) | 1-2 | Yes | Local PVC | short (days) | NO | scrape + relay only; do not use as long-term store |
| VictoriaMetrics / Mimir / Cortex | 1+ (single-replica = dev only) | Yes | NAS RWX or block | 1 week to months | NO | Long-term store; separate from scraper; **single-replica is dev-grade only** — prod needs replication or VM-cluster mode |
| AlertManager | 0 or 1 | No | Local | n/a | NO | Optional; grafana-only alerting is a real alternative |
| Trace backend (Jaeger / Tempo) | 1-3 | Yes | Block storage | 7-30 days | NO | OTel-native collectors (Jaeger v2) include the backend |

A few non-obvious choices:

- **OTel collector as Deployment, not DaemonSet**: tail-sampling needs cross-node aggregation; DaemonSet can't see the full trace.
- **Filebeat as DaemonSet** in node-attached k8s; as **sidecar** in serverless k8s (cloud-provider container instance). Same filebeat image, different deployment shape.
- **Mesh injection OFF for observability infra components**: telemetry must not depend on mesh.

## In-cluster vs externally-hosted

Production platforms typically split:

| Component | In-cluster | External | Rationale |
|---|---|---|---|
| OTel collector | YES | NO | App SDK → collector is in-cluster traffic |
| Filebeat / Logstash | YES | NO | tight loop with app logs |
| Kibana | YES | rare | UI is light |
| Grafana | YES or external | sometimes external | If a dedicated obs team runs it, lives outside |
| Elasticsearch | often EXTERNAL | sometimes in-cluster | High storage; many platforms run on bare metal or managed ES |
| VictoriaMetrics | both | both | small platforms in-cluster; large platforms central VM cluster |
| Prometheus scraper | YES | YES | sometimes a central cross-cluster scraper |

External components reached via:

```yaml
# ExternalName for cloud-provider managed services (RDS, etc.)
apiVersion: v1
kind: Service
metadata:
  name: <mysql-or-equivalent>
spec:
  type: ExternalName
  externalName: <cloud-provider-hostname>

# Endpoints with explicit IPs for on-prem / fixed-IP services (ES bare-metal)
apiVersion: v1
kind: Service
metadata:
  name: es-cluster
spec:
  ports:
    - { name: es, port: 9200, targetPort: 9200 }
    - { name: inter-node, port: 9300, targetPort: 9300 }
---
apiVersion: v1
kind: Endpoints
metadata:
  name: es-cluster
subsets:
  - addresses:
      - { ip: <fixed-ip-1> }
      - { ip: <fixed-ip-2> }
      - { ip: <fixed-ip-3> }
    ports:
      - { name: es, port: 9200 }
      - { name: inter-node, port: 9300 }
```

The Service + Endpoints pattern lets in-cluster pods reach external systems via the k8s service name as if they were in-cluster, without DNS resolution dependency on external DNS.

## Online / Offline parallel deployments

A platform may run **parallel obs stacks** for online (production) and offline (staging/dev) separation:

| Concern | Online | Offline |
|---|---|---|
| ES cluster | external bare-metal IPs (set A) | external bare-metal IPs (set B) OR in-cluster |
| Long-term metric store | external (separate cluster hosted at a stable hostname) | in-cluster VM single-replica |
| Service names | `es-cluster`, `victoria-metrics-service` | `es-cluster-offline`, `victoria-metrics-service` (same name, different cluster context) |
| Prom AlertManager | typically off (grafana-driven) | typically off |

Same service names in different namespaces / environments let app config stay environment-neutral. Application reads `<service>.<infra-namespace>.svc.cluster.local:<port>` in both environments; the Service definition resolves to different upstreams.

## Sizing reference

Concrete starting points from real deployments (tune by load):

```
OTel collector:
  resources:
    requests: { cpu: 250m, memory: 512Mi }
    limits:   { cpu: 4000m, memory: 8Gi }
  4 replicas

Filebeat DaemonSet:
  resources: per-node, similar to app — small (1 cpu, 1Gi)

Logstash:
  resources:
    requests: { cpu: 500m, memory: 1Gi }
    limits:   { cpu: 2000m, memory: 2Gi }
  2 replicas + HPA to 5
  JVM heap: -Xms1g -Xmx1g
  PIPELINE_WORKERS: 2
  PIPELINE_BATCH_SIZE: 500
  PIPELINE_BATCH_DELAY: 5

Kibana:
  resources:
    requests: { cpu: 500m, memory: 1Gi }
    limits:   { cpu: 1000m, memory: 2Gi }
  1 replica

Grafana:
  resources:
    requests: { cpu: 500m, memory: 1Gi }
    limits:   { cpu: 1000m, memory: 2Gi }
  1 replica per env, external MySQL backend for dashboards

VictoriaMetrics (single-instance — DEV/NON-CRITICAL ONLY):
  resources:
    requests: { cpu: 1000m, memory: 2Gi }
    limits:   { cpu: 4000m, memory: 8Gi }
  Retention: 1 week to 30 days
  Storage: 50Gi NAS RWX (allows snapshot DR)
  WARNING: single-instance with 1-week retention loses ALL metrics on disk failure or
  pod loss with corrupted PVC. For production, run VM-cluster mode (vmstorage 3+
  replicas with replication factor 2+) OR send to a managed metrics service.
  Single-instance is acceptable for dev/staging where losing a week's metrics
  during an incident is an inconvenience, not a blocker.

```

## Log noise discipline: cleaner sidecar pattern

Some observability infra components emit huge access / debug logs by default. Without cleanup, disk fills. Pattern:

```yaml
containers:
  - name: <main-component>
    # ... main spec
    volumeMounts:
      - { name: data, mountPath: <log-dir> }

  - name: log-cleaner
    image: <small-image-with-find-and-rm>:latest
    resources:
      requests: { cpu: 125m, memory: 256Mi }
      limits:   { cpu: 500m, memory: 1Gi }
    volumeMounts:
      - { name: data, mountPath: <log-dir> }
    command:
      - "/bin/sh"
      - "-c"
      - |
        while true; do
          find <log-dir> -type f \( -name "*.log.*" -o -name "*[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9].log" \) \
            -mtime +3 -print | while read f; do
            rm -f "$f"
          done
          sleep 3600
        done
```

Sleep 1 hour, delete files older than 3 days. The patterns match both `xxx.log.<date>.0` (logrotate format) and `xxx-<date>.log` (date-suffix format).

**Critical safety**: do NOT mount the entire host log directory or share a mount with audit/security logs. The cleaner's broad glob (`*[0-9][0-9][0-9][0-9]-...`) will happily delete `audit.log.2026-01-15.0` during an incident investigation. Required restrictions:
- Mount only the specific verbose component's log subdirectory; never a shared root.
- Use `-xdev` (don't cross filesystem boundaries) and depth limits in `find`.
- Maintain an allowlist of filenames the cleaner is permitted to remove, not just a date-pattern.
- Emit a metric (`log_cleaner_files_deleted_total`) for monitoring; alert on anomalous deletion volume.
- Document the cleaner's mount and pattern in the component's runbook so incident responders know what is auto-deleted.

This is preferable to:
- Disabling the verbose log entirely (loses incident-time data).
- Per-deployment custom log-rotate config (drift; hard to audit).
- Trusting the component's built-in rotation (often misconfigured; observed 1.9 GB / day from one registry component without cleanup).
- **In-app log cleanup running as a daemon timer inside the application process** (the application starts a goroutine/thread that periodically `find <log-dir> -mtime +N -delete`). This is a recurring anti-pattern with multiple problems: it races with the platform's log rotation (logrotate, k8s log driver, fluent-bit tail), it deletes files that observability collectors are still reading and produces inconsistent log-truncation events, it requires the application container to have write+delete permission on its own log directory (broader than the standard read-by-collector posture), and it makes log-retention policy implicit in application binary instead of explicit in deployment config. Log retention is a platform concern; the application emits logs and the platform decides retention. Move app-internal log-cleanup timers to the sidecar pattern above or to the cluster's log driver.

## Stateful component snapshot DR

**Safety scope**: this pattern is for **whole-cluster DR** (lost data dir + lost quorum). It is NOT a single-replica repair tool. Misuse causes data corruption:
- Single replica loses its PVC while the other replicas have newer state → init container restores stale snapshot into a live quorum → member-ID conflict, divergent log, or stale state rejoin → cluster split or data loss.
- Therefore: gate the init container behind an **explicit DR marker** (e.g. ConfigMap key, annotation, env var set only by operator during DR scale-to-zero procedure).
- Without the DR marker, init container exits 0 immediately. With the marker, it performs the restore — but only after confirming the StatefulSet is scaled to 0 first.
- For single-replica repair (one pod lost PVC, others healthy): use the component's native `member remove + member add` workflow, not snapshot restore.

For stateful observability infra such as a trace backend or long-term metric/log store that needs disaster recovery beyond replica redundancy:

```yaml
initContainers:
  - name: restore-from-snapshot
    image: <component-image>:<version>
    env:
      - { name: CLUSTER_SIZE, value: "3" }
      - { name: SET_NAME, value: "<statefulset-name>" }
      - name: NAMESPACE
        valueFrom: { fieldRef: { fieldPath: metadata.namespace } }
    command:
      - "/bin/sh"
      - "-exc"
      - |
        SNAPSHOT_DIR=/snapshot
        SNAPSHOT_FILE=${SNAPSHOT_DIR}/<component>-snapshot.db
        DATA_DIR=/data/<component>
        RESTORE_LOCK=${SNAPSHOT_DIR}/.restore-lock

        # 1. If data dir already populated, skip (normal restart).
        if [ -d "${DATA_DIR}/member" ]; then exit 0; fi

        # 2. If no snapshot, skip (first-time cluster bootstrap).
        if [ ! -s "${SNAPSHOT_FILE}" ]; then exit 0; fi

        # 3. Lock to prevent multiple pods restoring simultaneously.
        if ! mkdir "${RESTORE_LOCK}" 2>/dev/null; then
          # Another pod holds the lock; wait for it.
          while [ -d "${RESTORE_LOCK}" ]; do sleep 2; done
          if [ -d "${DATA_DIR}/member" ]; then exit 0; fi  # peer completed it
          exit 1  # lock disappeared but data dir empty → retry
        fi
        trap "rm -rf \"${RESTORE_LOCK}\"" EXIT

        # 4. Perform the restore.
        <component-restore-command> "${SNAPSHOT_FILE}" --data-dir "${DATA_DIR}"
    volumeMounts:
      - { name: data, mountPath: /data/<component> }
      - { name: snapshot, mountPath: /snapshot }

volumes:
  - name: snapshot
    persistentVolumeClaim:
      claimName: <shared-rwx-pvc>     # ReadWriteMany NAS volume

volumeClaimTemplates:
  - metadata: { name: data }
    spec:
      storageClassName: <nas-class>
      accessModes: ["ReadWriteMany"]
      resources: { requests: { storage: 50Gi } }
```

Critical patterns:
- **DR marker gate** (see Safety scope above) before ANY restore action runs.
- **Shared NAS PVC** (ReadWriteMany) for the snapshot file — all replicas read from the same place.
- **File-lock for coordination** — `mkdir` is atomic; the first pod to create the lock dir wins. BUT: lock files MUST have a TTL or holder metadata. Pure `mkdir` lock is broken on holder crash: if the locking pod SIGKILLs mid-restore, peers wait forever for the lock dir to disappear. Mitigations:
  - Write a heartbeat file inside the lock dir with timestamp + holder identity (`pod-name + uid`); peers check heartbeat age and force-release after `4× heartbeat_interval`.
  - Or use a Kubernetes `Lease` resource (lease.coordination.k8s.io) which has built-in TTL and renewal — preferable over file-based locks for k8s-native operation.
  - Document break-glass: when peers detect a stale lock holder (heartbeat > N minutes), operator manually deletes the lock dir after confirming the original holder is gone.
- **Idempotent**: existing data dir means "already restored or already running" — skip.
- **Restore command varies by component** (`etcdctl snapshot restore`, equivalent for others).

Snapshot generation runs as a separate CronJob (not shown here) — periodic dump to the NAS volume.

## Verification

- Storage limits met: monitor disk usage per stateful component; alert at 70% / 85%.
- Log cleaner sidecar working: file count + total size graph shows daily reset.
- Snapshot DR drill: in non-prod, scale StatefulSet to 0, delete data PVCs, scale back; init container should restore from the latest snapshot within timeout (typically minutes).
- Multi-replica check: scale a component to N replicas; kill 1; remaining serves; replica returns; cluster heals.
- Cross-environment routing: same service name (e.g. `es-cluster`) resolves to different endpoints in offline vs online envs — pod's resolved IPs differ as expected.
