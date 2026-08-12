#!/usr/bin/env bash
# verify-sandbox.sh — trust-rooted, sandboxed `make verify` for a candidate repo
# (mechanical-gate backlog ③: verify trust-root pin + sandbox).
#
# THREAT MODEL: `make verify` executes the CANDIDATE's test code on the host — with the
# host's network, env (tokens), HOME, and workspace. A hostile or buggy candidate can
# exfiltrate secrets, call live services, or corrupt the workspace, and a candidate that
# edits the verify machinery can self-approve. Mitigations here:
#   - TRUST ROOT: this runner lives in ccl-skills (invoked from OUTSIDE the candidate
#     repo); the candidate cannot alter the sandbox constraints. Diffs that edit the verify
#     machinery itself are routed to humans by the control-plane detector (sibling gate).
#   - COMMITTED-STATE ONLY: the candidate is `git clone`d (committed HEAD state) into a
#     throwaway temp dir — uncommitted edits are excluded and the real workspace is never
#     touched or written.
#   - SANDBOX: tests run in docker with --network=none (deps pre-warmed in a separate
#     network phase that runs NO candidate code for Go; pip build isolation noted below),
#     an explicit minimal env (host env never passed through), CPU/memory/pids caps, and a
#     host-side hard timeout.
#   - SECRET SCAN ON HOST: gitleaks reads the clone without executing candidate code, so it
#     needs no sandbox and no in-container install.
#
# USAGE
#   bash scripts/verify-sandbox/verify-sandbox.sh <repo-path> [options]
# OPTIONS
#   --ref REF          committed ref to verify (default: the repo's current HEAD)
#   --image IMG        override the stack image (defaults: golang:1.26 / python:3.12-slim)
#   --core PATH        python family: path to the sibling core repo (default: <repo>/../python)
#   --cpus N           CPU cap (default 4)      --memory M   memory cap (default 4g)
#   --timeout SECS     per-phase hard timeout (default: warm 600, verify 1200; sets BOTH)
#   --keep             keep the temp clone for debugging (prints path)
# EXIT: 0 verify green · 2 verify failed · 3 runner/config error (fail closed)
set -u

die() { printf 'verify-sandbox: %s\n' "$*" >&2; exit 3; }
note() { printf 'verify-sandbox: %s\n' "$*"; }

command -v docker >/dev/null 2>&1 || die "docker required"
docker info >/dev/null 2>&1 || die "docker daemon not reachable"
command -v git >/dev/null 2>&1 || die "git required"
command -v gitleaks >/dev/null 2>&1 || die "gitleaks required on host (read-only secret scan)"
TIMEOUT_BIN=timeout
command -v timeout >/dev/null 2>&1 || { command -v gtimeout >/dev/null 2>&1 && TIMEOUT_BIN=gtimeout || die "timeout/gtimeout required (brew install coreutils)"; }

REPO=""; REF=""; IMAGE=""; CORE=""; PIP_DEPS="opentelemetry-api opentelemetry-sdk opentelemetry-exporter-otlp opentelemetry-propagator-b3"; CPUS=4; MEMORY=4g; TIMEOUT_WARM=600; TIMEOUT_VERIFY=1200; KEEP=0
while [ $# -gt 0 ]; do
  case "$1" in
    --ref|--image|--core|--pip-deps|--cpus|--memory|--timeout)
      [ $# -ge 2 ] || die "$1 requires a value"
      case "$1" in
        --ref) REF="$2" ;; --image) IMAGE="$2" ;; --core) CORE="$2" ;;
        --pip-deps) PIP_DEPS="$2" ;; --cpus) CPUS="$2" ;; --memory) MEMORY="$2" ;;
        --timeout) TIMEOUT_WARM="$2"; TIMEOUT_VERIFY="$2" ;;
      esac; shift 2 ;;
    --keep) KEEP=1; shift ;;
    -h|--help) sed -n '2,36p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    --*) die "unknown option: $1" ;;
    *) [ -z "$REPO" ] || die "unexpected extra argument: $1"; REPO="$1"; shift ;;
  esac
done
[ -n "$REPO" ] || die "usage: verify-sandbox.sh <repo-path> [options]"
[ -d "$REPO" ] || die "not a directory: $REPO"
git -C "$REPO" rev-parse --git-dir >/dev/null 2>&1 || die "not a git repository: $REPO"
REPO="$(cd "$REPO" && pwd -P)"
[ -n "$REF" ] || REF="$(git -C "$REPO" rev-parse HEAD)" || die "cannot resolve HEAD"
SHA="$(git -C "$REPO" rev-parse "$REF^{commit}" 2>/dev/null)" || die "cannot resolve ref: $REF"

# Work dir must be visible to the docker VM's file sharing. macOS engines vary (Docker
# Desktop shares /Users + /tmp; colima-style VMs often share only $HOME), so default to a
# $HOME path and PROVE visibility with a mount canary before trusting any result — an
# unshared path silently mounts as an EMPTY directory, which would otherwise surface as a
# baffling downstream failure (or worse, a false verdict).
VS_ROOT="${VERIFY_SANDBOX_TMPDIR:-$HOME/.cache/verify-sandbox}"
mkdir -p "$VS_ROOT" || die "cannot create $VS_ROOT"
WORK="$(mktemp -d "$VS_ROOT/run.XXXXXX")" || die "mktemp failed"
cleanup() { [ "$KEEP" = 1 ] && { note "kept: $WORK"; return; }; rm -rf "$WORK"; }
trap cleanup EXIT
CLONE="$WORK/repo"

# COMMITTED STATE ONLY: clone + hard checkout of the requested commit. --no-hardlinks so
# nothing in the throwaway clone shares inodes with the real repo's object store.
git clone -q --no-hardlinks "$REPO" "$CLONE" || die "clone failed"
git -C "$CLONE" checkout -q --detach "$SHA" || die "checkout $SHA failed"

# ----- stack detection ---------------------------------------------------------
STACK=""
if [ -f "$CLONE/go.mod" ]; then STACK=go
elif [ -f "$CLONE/pyproject.toml" ] || [ -d "$CLONE/src" ]; then STACK=python
else die "unsupported stack (no go.mod / pyproject.toml): $REPO"
fi
[ -f "$CLONE/Makefile" ] || die "no Makefile — the family verify baseline is required"
case "$STACK" in go) DEFAULT_IMAGE="golang:1.26" ;; python) DEFAULT_IMAGE="python:3.12-slim" ;; esac
[ -n "$IMAGE" ] || IMAGE="$DEFAULT_IMAGE"

# MOUNT CANARY (fail closed): prove the docker engine actually shares $WORK — an unshared
# host path mounts as an empty dir with no error.
"$TIMEOUT_BIN" -k 15 60 docker run --rm --network none -v "$CLONE":/canary "$IMAGE" test -f /canary/Makefile \
  || die "mount canary failed — docker engine cannot see $WORK (empty mount) — the engine's file sharing must cover it; set VERIFY_SANDBOX_TMPDIR to a shared path"

# ----- host-side secret scan (read-only; no candidate code executes) -----------
note "[1/3] secret scan (host, read-only)"
( cd "$CLONE" && gitleaks dir . --no-banner --redact ) || { echo "verify-sandbox: secret scan FAILED" >&2; exit 2; }

# ----- sandbox phases ----------------------------------------------------------
# Explicit minimal env only — the host environment is never passed into the container.
DLIMITS=(--cpus "$CPUS" --memory "$MEMORY" --pids-limit 1024)

# Verify-phase containers are NAMED so cleanup and leftover-detection can find them even
# if the docker CLI is killed by the host timeout before the container stops.
RUN_CTR="vs-run-$$-$RANDOM"
drun() { # $1 net  $2 timeout  rest: command — DCOMMON/DENV set per stack below
  local net="$1" to="$2" rc; shift 2
  "$TIMEOUT_BIN" -k 15 "$to" docker run --name "$RUN_CTR" "${DCOMMON[@]}" "${DENV[@]}" "${DLIMITS[@]}" --network "$net" "$IMAGE" "$@"
  rc=$?
  docker rm -f "$RUN_CTR" >/dev/null 2>&1   # reap even if timeout killed the CLI mid-run
  [ "$rc" = 124 ] && echo "verify-sandbox: phase TIMED OUT (${to}s)" >&2
  return "$rc"
}

case "$STACK" in
  go)
    # The family Makefile verify chain minus secret-scan (host-scanned above). Assert the
    # expected targets exist rather than silently running something else.
    for t in fmt-check vet verify-module-graph test-race; do
      grep -qE "^$t:" "$CLONE/Makefile" || die "Makefile lacks family target '$t' — run the make-verify baseline first"
    done
    command -v go >/dev/null 2>&1 || die "go required on host (to warm this repo's module cache)"
    # WARM (host): populate a THROWAWAY module cache with ONLY this repo's deps — no
    # candidate code runs (go mod download just fetches modules named in go.mod). This
    # avoids mounting the whole host GOMODCACHE (which holds OTHER projects' private
    # modules a hostile test could read via /romod and exfiltrate through stdout).
    # Seed from the host cache's own module store via a file:// GOPROXY first (offline,
    # reliable — reuses what the host-side verify already fetched), then the host's normal
    # proxy only for genuine misses. Only this repo's modules land in $WORK/gomod.
    note "[2/2] warm this repo's modules into a throwaway cache (host, no candidate code)"
    HOST_GOMOD="$(go env GOMODCACHE 2>/dev/null)"
    SEED=""
    [ -n "$HOST_GOMOD" ] && [ -d "$HOST_GOMOD/cache/download" ] && SEED="file://$HOST_GOMOD/cache/download,"
    ( cd "$CLONE" && GOMODCACHE="$WORK/gomod" GOFLAGS=-mod=mod GOPROXY="${SEED}$(go env GOPROXY)" go mod download ) \
      || die "go mod download failed (host must resolve this repo's private modules; a bad network+empty host cache both fail)"
    chmod -R u+w "$WORK/gomod" 2>/dev/null || true
    # VERIFY (network=none): the throwaway per-repo cache mounts read-only; no host env,
    # no host cache, no network.
    DCOMMON=(--rm --workdir /work -v "$CLONE":/work -v "$WORK/gomod":/romod:ro -v "$WORK/cache":/cache --tmpfs /tmp:rw,exec,size=1g)
    DENV=(--env HOME=/tmp --env GOPATH=/cache/gopath --env GOCACHE=/cache/gobuild --env GOMODCACHE=/romod --env GOPROXY=off)
    note "[2/2] verify phase (network=none; per-repo module cache read-only)"
    drun none "$TIMEOUT_VERIFY" make fmt-check vet verify-module-graph test-race GO_PROXY=off GO_CACHE=/cache/gobuild GO_MOD_CACHE=/romod \
      || { echo "verify-sandbox: verify FAILED" >&2; exit 2; }
    ;;
  python)
    grep -qE "^check:" "$CLONE/Makefile" || die "Makefile lacks family target 'check' — run the make-verify baseline first"
    # Family layout: adapters resolve the sibling core via PYTHONPATH=src:../python/src.
    # Clone the core beside the candidate clone when the Makefile references it.
    if grep -q '\.\./python' "$CLONE/Makefile"; then
      [ -n "$CORE" ] || CORE="$(dirname "$REPO")/python"
      [ -d "$CORE" ] || die "sibling python core repo not found at $CORE (pass --core)"
      git clone -q --no-hardlinks "$CORE" "$WORK/python" || die "core clone failed"
    fi
    DENV=(--env HOME=/tmp --env PIP_CACHE_DIR=/cache/pip --env DEBIAN_FRONTEND=noninteractive)
    # Warm state (apt make/git, pip deps) must SURVIVE into the offline phase: the warm
    # container is committed to a throwaway image, and verify runs from that image with
    # network=none. Both cleaned up on exit.
    WARM_CTR="vs-warm-$$-$RANDOM"; WARM_IMG="vs-img-$$-$RANDOM"
    cleanup_docker() { docker rm -f "$WARM_CTR" "$RUN_CTR" >/dev/null 2>&1; docker rmi -f "$WARM_IMG" >/dev/null 2>&1; }
    trap 'cleanup_docker; cleanup' EXIT
    note "[2/3] warm phase (network on; apt make/git + public pip deps only — candidate/core packages NOT installed; NO source mounted so a compromised dep's build hook cannot read /obs during the networked phase)"
    # NO candidate/core bind mounts in the networked warm phase — only the pip cache — so
    # a compromised public dependency's install hook has no candidate source to exfiltrate.
    "$TIMEOUT_BIN" -k 15 "$TIMEOUT_WARM" docker run --name "$WARM_CTR" -v "$WORK/cache":/cache "${DENV[@]}" "${DLIMITS[@]}" --network bridge "$IMAGE" \
      sh -c "set -e; apt-get update -qq >/dev/null; apt-get install -y -qq make git >/dev/null; pip install -q --no-warn-script-location pytest $PIP_DEPS" \
      || { echo "verify-sandbox: warm phase FAILED" >&2; exit 2; }
    docker commit "$WARM_CTR" "$WARM_IMG" >/dev/null || die "docker commit failed"
    docker rm -f "$WARM_CTR" >/dev/null 2>&1
    IMAGE="$WARM_IMG"
    # Source is mounted ONLY now, in the offline (network=none) verify phase.
    DCOMMON=(--rm --workdir /obs/repo -v "$CLONE":/obs/repo -v "$WORK/cache":/cache --tmpfs /tmp:rw,exec,size=1g)
    [ -d "$WORK/python" ] && DCOMMON+=(-v "$WORK/python":/obs/python)
    note "[3/3] verify phase (network=none; warmed image; source mounted here only)"
    drun none "$TIMEOUT_VERIFY" make check \
      || { echo "verify-sandbox: verify FAILED" >&2; exit 2; }
    ;;
esac

note "OK — verify green in sandbox (committed state $SHA, network=none, capped)"
exit 0
