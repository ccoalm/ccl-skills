# Deploy CLI — Concrete Recipe

Working implementation of the deploy CLI described in `custom-control-plane-boundary.md`. Distilled from a production CLI that ships every release of a multi-language platform.

## Surface — 5 commands

```
deploy-cli compile        Compile source into a build artifact (tar.gz)
deploy-cli build          Build a Docker image from the artifact, push to registry
deploy-cli deploy-config  Preview the rendered k8s YAML (optionally save to file)
deploy-cli review         Create an approval task, optionally wait for the result
deploy-cli deploy         Apply the deploy via control plane; stream watch events via WebSocket
```

Each command:
- Takes a small set of named flags (parsed from struct tags via reflection — see CLI builder below).
- Calls the control plane's HTTP API.
- Returns 0 on success, non-zero on failure.
- Prints structured progress to stdout.

Importantly, the CLI **never** applies deploy/update state directly to k8s, service discovery, mesh control plane, or etcd. Deploy-config, review, deploy, rollback, and traffic-policy changes route through the control plane. Source compilation and image build may call pinned project build tools and the image registry behind typed CLI commands, but long-lived deploy/update behavior must stay declarative and auditable.

## Pipeline-name parsing convention

The CI/CD system passes a `pipeline_name` flag in the form `[lane_name] P.S.M XXXX` or `【lane_name】P.S.M XXXX` (Chinese brackets accepted). The CLI parses both `lane_name` and `PSM` from this single string:

```go
laneNameReg := regexp.MustCompile(`[\[【]([0-9a-zA-Z-]+)[]】]`)
psmReg      := regexp.MustCompile(`[0-9a-zA-Z-_]+\.[0-9a-zA-Z-_]+\.[0-9a-zA-Z-_]+`)

// Validate: exactly one lane name + exactly one PSM in the string.
// Reject otherwise — "[a] [b] x.y.z" or "[a] x.y.z m.n.o" is ambiguous.
```

Why this convention: external CI/CD platforms (e.g. cloud-provider continuous pipeline) name their pipelines manually with a project-recognizable label. Embedding lane + PSM in the name means the CLI doesn't need separate flags for them, and a glance at the pipeline name tells operators what's deploying where.

If your platform passes lane and PSM as explicit flags, skip this parser. The convention is one less round-trip; explicit flags are clearer.

## Image naming convention

```
<registry-host>/<namespace>/<psm>:<lane-type>-<image-version>
```

Where:
- `registry-host`: private image registry hostname.
- `namespace`: separate namespace per environment tier (e.g. one for offline lanes, one for online lanes — two-tier organization for RBAC + cleanup policies).
- `psm`: service PSM as-is.
- `lane-type`: `prod` (online) or `dev` (offline) — derived from `lane.LaneType`.
- `image-version`: caller-supplied, typically `<git-commit-sha>` or `<release-tag>`.

This naming lets you:
- Filter all online images via the namespace prefix.
- Quickly identify the lane type from the tag.
- Garbage-collect dev images on a shorter retention than prod.

## Compile flow

```
deploy-cli compile --workspace <dir> --pipeline_name "[lane] x.y.z ..."
  │
  ├─ parse pipeline_name → psm, lane
  ├─ control plane: GetLaneServiceDetail(lane, psm)
  │   → buildScript (from cluster config, or service config, or default ./build.sh)
  │   → runtime (from env RUNTIME, or cluster config, or default e.g. "go:1.25")
  ├─ execute embedded compile.sh with env vars:
  │     CP_WORKSPACE, PSM, LANE, BUILD_SCRIPT, RUNTIME
  │   → runs user's build script (sh "$BUILD_SCRIPT") in workspace
  │   → packs ./output/* into output.tar.gz in workspace
  ├─ generate Dockerfile in workspace from embedded template:
  │     FROM <registry>/<runtime>
  │     USER <runtime-user>
  │     WORKDIR /opt/<org>/app
  │     ADD output.tar.gz .
  │     ENTRYPOINT ["./bootstrap.sh"]
  └─ done; tar.gz + Dockerfile ready in workspace
```

Embedded compile.sh:

```sh
#!/bin/bash
set -e
mkdir -p "$CP_WORKSPACE/.gomod"
cd "$CP_WORKSPACE"
rm -rf output/
sh "$BUILD_SCRIPT"               # user's build script writes to ./output
cd output
shopt -s dotglob
tar cvzf output.tar.gz *
shopt -u dotglob
mv output.tar.gz "$CP_WORKSPACE"
```

The user's `build.sh` (in the service repo) is responsible for writing the actual artifact to `./output`. Compile orchestrates: cache setup, output packing, Dockerfile generation.

`bootstrap.sh` lives inside the user's output tarball — it is the service-specific entrypoint. Compile doesn't generate it.

## Build flow

```
deploy-cli build --pipeline_name "[lane] x.y.z ..." --image_version <v>
                 [--registry_user <u> --registry_pwd <p>]
  │
  ├─ parse pipeline_name → psm, lane
  ├─ control plane: ListLane(lane) → lane type → image namespace + tag
  ├─ registry credentials from flag OR env (REGISTRY_USERNAME / REGISTRY_PASSWORD)
  ├─ registry host from env (REGISTRY_HOST) — required, no default
  └─ execute embedded build.sh with env vars:
        PSM, LANE, NAMESPACE, IMAGE, REGISTRY_USERNAME, REGISTRY_PASSWORD, REGISTRY_HOST
      → docker login → docker build -t $IMAGE -f Dockerfile .
                     → docker push $IMAGE → docker rmi $IMAGE
```

Embedded build.sh:

```sh
#!/bin/bash
set -e
# Use --password-stdin to keep password out of process args / CI command logs.
echo "$REGISTRY_PASSWORD" | docker login -u "$REGISTRY_USERNAME" --password-stdin "$REGISTRY_HOST"
docker build -t "$IMAGE" -f Dockerfile .
docker push "$IMAGE"
docker rmi "$IMAGE"
```

**Never pass passwords with `-p` / `--password` flags** — they appear in `ps`, `/proc/<pid>/cmdline`, container event logs, and CI build output. `--password-stdin` is the universal correct form. Pair with:
- CI secret masking (most CI platforms scrub matching strings from logs).
- Short-lived registry tokens (rotate per CI run if the registry supports it).
- Image registry RBAC: build-time tokens have push-only scope to the target namespace, not org-wide.

Why bash not Go: docker CLI is the path of least friction; Go reimplementations of docker daemon interaction are fragile. Embed the script, execute with `exec.CommandContext`.

## Deploy-config flow (preview YAML)

```
deploy-cli deploy-config --pipeline_name "[lane] x.y.z ..." --image_version <v>
                          [--use_lane <override>] [--save_path <file>]
  │
  ├─ parse pipeline_name → psm, lane
  ├─ compute image URI
  ├─ if special PSM (control plane itself): render embedded YAML template
  │     with placeholders <psm> <appName> <laneName> <image>
  ├─ else: control plane: GetLaneServiceDeployConfig(lane, psm, image)
  │     → returns server-rendered YAML
  ├─ print YAML to stdout
  └─ if --save_path given: write to file
```

The preview lets operators eyeball the YAML before deploying — useful for "is this template change going to do what I think" review.

The "special PSM" branch handles the chicken-egg case: when deploying the control plane itself, the control plane API may be unavailable, so the CLI ships an embedded template for those services.

## Review flow

```
deploy-cli review --workspace_id <id> --pipeline_id <id> --pipeline_name "..."
                  --pipeline_run_id <id> [--need_approve <n>=1] [--expire <dur>=24h]
                  [--wait_result]
  │
  ├─ validate: pipeline_run_id and pipeline_name required
  ├─ parse pipeline_name → psm, lane
  ├─ control plane: CreateReviewTask(
  │       lane, psm, workspace_id, pipeline_id, pipeline_name, run_id,
  │       expire, need_approve_num)
  ├─ control plane sends chat-platform card to reviewers (out-of-band)
  └─ if --wait_result:
        poll GetReviewTask(task_id) every 5s
          tolerate up to 5 consecutive errors before failing
          until: status != Pending OR elapsed > expire
        on result: print approver list + decisions
```

The review task is bound to the **pipeline run id** — one approval per CI/CD pipeline run. The pipeline runs `review --wait_result`, which blocks until approved or expired; then runs `deploy`.

If approval expires or is rejected, `deploy` should not be called. The CI/CD orchestrator enforces this — typically by checking the review command's exit code.

## Deploy flow (the actual k8s apply)

```
deploy-cli deploy --pipeline_name "[lane] x.y.z ..." --image_version <v>
                  [--use_lane <override>]
  │
  ├─ parse pipeline_name → psm, lane (or use --use_lane override)
  ├─ compute image URI
  ├─ open WebSocket to control plane: /v1/deploy_lane_service
  │   query: ?psm=<psm>&name=<lane>&image=<image>&interactive=true
  ├─ control plane:
  │     start k8s Deployment apply
  │     start k8s.Watch on the Deployment
  │     for each watch event: format as JSON → write to WebSocket
  ├─ CLI reads events from WebSocket with 5-min read deadline (reset per message):
  │     event = { type, app_name, ready_replica, expect_replica,
  │              condition_* (optional), is_result_event, is_success }
  │   each event printed as a status line, e.g.:
  │     [MODIFIED] <app>(2/3)
  │     [MODIFIED-CONDITION] <app>(2/3), Available - True ...: Deployment available
  ├─ stop reading on is_result_event=true
  └─ exit 0 if is_success, else non-zero
```

This gives the user real-time feedback. A deploy that gets stuck (e.g. ImagePullBackOff) surfaces conditions immediately, not after a timeout.

## CLI builder via reflection (generic)

A reusable pattern for adding new commands without boilerplate:

```go
func MustBuildCommand[P any](name, usage string, action func(*P) error) *cli.Command
```

Define a params struct with `json` + `usage` + `default` tags:

```go
type DeployParams struct {
    PipelineName string `json:"pipeline_name" usage:"Pipeline name in '[lane] psm ...' format"`
    ImageVersion string `json:"image_version" usage:"Image version tag"`
    UseLane      string `json:"use_lane" usage:"Override lane (optional)"`
}

var Deploy = MustBuildCommand[DeployParams]("deploy", "Deploy a service", deployHandler)
```

The builder uses reflection to:
- Read each field's `json` tag → flag name.
- Read `usage` tag → flag help text.
- Read `default` tag → default value.
- Detect field type (string/bool/int/int64/float64) → register the right flag type.

Supported types: `string`, `bool`, `int`, `int64`, `float64`. Slices via comma-separated strings, parsed with helpers (`GetStringSlice`, `GetInt64Slice`, etc.).

Adding a new command is one struct + one handler function + one `MustBuildCommand` line.

## Control plane host override

The CLI looks up the control plane at:

```
host = env.<CONTROL_PLANE_HOST> || <default-host>
lane_for_api = env.<CONTROL_PLANE_LANE>   // optional; injected as request header
```

So a developer testing against a non-prod control plane (e.g. a dev-lane deployment of the control plane itself) sets one env var. The CLI's HTTP middleware adds the `<lane-header>` to outgoing requests, and the mesh routes them to the right lane of the control plane.

This lets the platform team dogfood the control plane in non-prod lanes before promoting it to prod.

**Security**: open host override is a real attack surface. A compromised CI environment that sets `<CONTROL_PLANE_HOST>` to an attacker-controlled URL would have the deploy CLI build + deploy via malicious rendered YAML. Production lanes MUST add safeguards:
- **Pinned host allowlist**: a build-time-baked list of allowed control-plane hosts. Override permitted only to hosts in the list (typically: prod, pre-prod, staging variants).
- **TLS identity validation**: pin the control-plane TLS cert fingerprint or require a specific CA; reject unexpected certs even on HTTPS.
- **Audience-bound tokens**: CLI's SSO token specifies the target host as audience; refuses to send the token to a different host. Prevents token reuse against a redirected control plane.
- **Break-glass approval for prod override**: setting `<CONTROL_PLANE_HOST>` for a prod lane requires an approval ticket; CLI refuses without it.
- **Audit log on override**: every CLI invocation with non-default host emits an audit entry to the platform's central audit log (not just local).

## Special-PSM bypass (chicken-and-egg)

A handful of platform services (typically the control plane itself + a secrets/auth service) are marked as "special PSM". For those:

- Image namespace logic uses lane-name prefix instead of querying the control plane (which may not be reachable when deploying itself).
- Deploy-config uses an embedded YAML template instead of calling the rendering API.

Limit the special-PSM set to the minimum necessary for self-bootstrap. Adding regular services here creates inconsistent paths and audit gaps.

## What this confirms about `custom-control-plane-boundary.md`

Mapping the recommended boundary to this concrete CLI:

| Boundary rule | CLI evidence |
|---|---|
| Deploy/update calls API; never k8s/etcd directly | ✅ Deploy-config, review, deploy, rollback, and traffic-policy changes go through `cloudapi.Client` HTTP |
| Audit every deploy event | ✅ control plane records each deploy; CLI just initiates |
| WebSocket for live deploy progress | ✅ `/deploy_lane_service` over WS with 5-min read deadline |
| Approval via chat platform | ✅ control plane sends card; CLI's `review --wait_result` polls task status |
| Stateless beyond audit + tasks | ✅ CLI is fully stateless; control plane holds task state |
| Single endpoint, single auth | ✅ `CONTROL_PLANE_HOST` env, lane-header optional |
| No business logic | ✅ CLI is pure orchestration |
| Break-glass kubectl open | ✅ Admin can bypass; CLI doesn't gatekeep cluster access |
| Generic helpers | ✅ Generic `MustBuildCommand[P]` for new commands |

The recommended boundary holds in practice. The CLI is small (~12 files, ~3.5kLOC), maintained by a small platform team, and ships every release.

## Pipeline integration (external CI/CD)

The CLI is designed to be called from a CI/CD pipeline runner (cloud-provider continuous-pipeline / GitLab CI / GitHub Actions / Tekton). A typical pipeline:

```yaml
stages:
  - name: compile
    script: deploy-cli compile --workspace . --pipeline_name "$PIPELINE_NAME"
  - name: build
    script: deploy-cli build --pipeline_name "$PIPELINE_NAME" --image_version "$VERSION"
  - name: review
    script: deploy-cli review --pipeline_run_id "$RUN_ID" --pipeline_name "$PIPELINE_NAME" --wait_result
    timeout: 24h    # matches review expire
  - name: deploy
    script: deploy-cli deploy --pipeline_name "$PIPELINE_NAME" --image_version "$VERSION"
```

The pipeline runner provides:
- `PIPELINE_NAME` (encodes lane + PSM)
- `VERSION` (image version, typically `$COMMIT_SHA`)
- `RUN_ID` (unique per pipeline run)
- `WORKSPACE_ID`, `PIPELINE_ID` (for review task linking)

The pipeline runner handles auth (image-registry credentials, control-plane SSO token) via environment variables. The CLI inherits them.

## Verification

- Run `compile + build + deploy-config + deploy` end-to-end against a dev lane; expect each stage idempotent (re-running same command produces same result).
- Override `CONTROL_PLANE_HOST` to a stub server; CLI calls hit the stub, no production traffic.
- Set `CONTROL_PLANE_LANE` to a dev lane; verify the mesh routes CLI's calls to the dev control plane.
- Kill the control plane mid-deploy; CLI surfaces the disconnection cleanly (not hung indefinitely).
- Add a new command via `MustBuildCommand[NewParams]("name", ...)`; expect compile + register + work without other code changes.
