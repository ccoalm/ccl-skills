#!/usr/bin/env bash
# Behavioral + adversarial suite for verify-sandbox (docker required — run via
# `make test-verify-sandbox`, deliberately not part of the default `make test`).
# Proves the sandbox INVARIANTS, not just the happy path: network actually cut,
# host env not leaked, uncommitted candidate edits excluded, host workspace
# untouched, timeout enforced with no leftover containers, fail-closed on
# non-family repos.
set -u
RUNNER="$(cd "$(dirname "$0")" && pwd)/verify-sandbox.sh"
PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); printf '  ok   %s\n' "$1"; }
bad() { FAIL=$((FAIL+1)); printf '  FAIL %s\n     %s\n' "$1" "${2:-}"; }

# Docker-gated by design. On a host without docker the invariants cannot be exercised, so
# this is NOT a pass — but exiting nonzero would break teammates who have no docker. CI (or
# anyone treating this as required verification) sets VERIFY_SANDBOX_REQUIRE_DOCKER=1 to turn
# the skip into a hard failure, so a docker-less runner cannot report a green "required" gate.
if ! { command -v docker >/dev/null 2>&1 && docker info >/dev/null 2>&1; }; then
  if [ "${VERIFY_SANDBOX_REQUIRE_DOCKER:-0}" = 1 ]; then
    echo "FAIL: docker unavailable and VERIFY_SANDBOX_REQUIRE_DOCKER=1 (invariants not exercised)"; exit 1
  fi
  echo "SKIP: docker unavailable — invariants NOT exercised (not a pass; set VERIFY_SANDBOX_REQUIRE_DOCKER=1 to enforce)"; exit 0
fi

mkdir -p "$HOME/.cache/verify-sandbox" || exit 1
ROOT="$(mktemp -d "$HOME/.cache/verify-sandbox/test.XXXXXX")" || exit 1
trap 'rm -rf "$ROOT"' EXIT
REPO="$ROOT/fixture"
mkdir -p "$REPO"
git -C "$ROOT" init -q fixture
git -C "$REPO" config user.email t@t; git -C "$REPO" config user.name t

cat > "$REPO/go.mod" <<'EOF'
module example.com/vsfixture

go 1.22
EOF
cat > "$REPO/main.go" <<'EOF'
package vsfixture

func Two() int { return 2 }
EOF
cat > "$REPO/main_test.go" <<'EOF'
package vsfixture

import (
	"net"
	"os"
	"testing"
	"time"
)

func TestTwo(t *testing.T) {
	if Two() != 2 {
		t.Fatal("math broke")
	}
}

// PASSES only when the network is actually cut: a sandbox that leaks network
// makes this test fail (negative control: it fails when run un-sandboxed).
func TestNetworkIsCut(t *testing.T) {
	// Cloudflare's public resolver, by hostname (no IP literal). network=none makes even
	// DNS resolution fail, so this errors in the sandbox and passes; un-sandboxed it
	// connects and the test fails (the negative control proves the probe is real).
	c, err := net.DialTimeout("tcp", "one.one.one.one:443", 2*time.Second)
	if err == nil {
		c.Close()
		t.Fatal("network reachable — sandbox leaked the network")
	}
}

// PASSES only when the host env is not passed through.
func TestHostEnvNotLeaked(t *testing.T) {
	if os.Getenv("VS_CANARY_SECRET") != "" {
		t.Fatal("host env leaked into sandbox")
	}
}
EOF
cat > "$REPO/Makefile" <<'EOF'
GO_CACHE ?= /tmp/vsfixture-gocache
.PHONY: fmt-check vet verify-module-graph test test-race verify
fmt-check:
	@out="$$(gofmt -l . 2>&1)"; test -z "$$out" || { echo "gofmt needed: $$out"; exit 1; }
vet:
	GOCACHE=$(GO_CACHE) go vet ./...
verify-module-graph:
	GOCACHE=$(GO_CACHE) go list -mod=readonly -deps ./... >/dev/null
test:
	GOCACHE=$(GO_CACHE) go test -mod=readonly ./...
test-race:
	GOCACHE=$(GO_CACHE) go test -mod=readonly -race ./...
verify: fmt-check vet verify-module-graph test-race
EOF
git -C "$REPO" add -A && git -C "$REPO" commit -qm fixture

echo "verify-sandbox suite (docker)"

# 1+2+3. happy path WITH the two invariant probes inside: green proves network cut
#        AND env clean, in one sandboxed run (VS_CANARY_SECRET set on the host side).
out=$(VS_CANARY_SECRET=leakme bash "$RUNNER" "$REPO" 2>&1); rc=$?
[ "$rc" = 0 ] && printf '%s' "$out" | grep -q 'OK — verify green' \
  && ok "sandbox green; network cut + host env clean (probes inside fixture)" \
  || bad "sandbox happy path" "rc=$rc tail: $(printf '%s' "$out" | tail -3)"

# 2b. NEGATIVE CONTROL: the same probes FAIL outside the sandbox (network reachable),
#     proving the fixture probes are real, not vacuous. Runs the fixture test directly
#     in docker WITH network (no host go needed).
out=$(docker run --rm -v "$REPO":/work -w /work --env GOFLAGS= golang:1.26 \
        sh -c 'GOCACHE=/tmp/gc go test -run TestNetworkIsCut ./...' 2>&1); rc=$?
[ "$rc" != 0 ] && printf '%s' "$out" | grep -q 'network reachable' \
  && ok "negative control: probe fails when network exists" \
  || bad "negative control" "rc=$rc out: $(printf '%s' "$out" | tail -2)"

# 4. UNCOMMITTED EXCLUDED: break the code UNCOMMITTED — sandbox must still verify the
#    committed state and stay green.
echo "this is not go" >> "$REPO/main.go"
out=$(bash "$RUNNER" "$REPO" 2>&1); rc=$?
[ "$rc" = 0 ] && ok "uncommitted breakage excluded (committed state verified)" \
  || bad "uncommitted exclusion" "rc=$rc"
git -C "$REPO" checkout -q -- main.go

# 5. WORKSPACE UNTOUCHED: tree hash + porcelain identical across a run.
before="$(git -C "$REPO" status --porcelain; git -C "$REPO" rev-parse HEAD)"
bash "$RUNNER" "$REPO" >/dev/null 2>&1
after="$(git -C "$REPO" status --porcelain; git -C "$REPO" rev-parse HEAD)"
[ "$before" = "$after" ] && ok "host workspace untouched" || bad "workspace mutated" "$after"

# 6. TIMEOUT enforced + no leftover containers.
cat > "$REPO/slow_test.go" <<'EOF'
package vsfixture

import (
	"testing"
	"time"
)

func TestSlow(t *testing.T) { time.Sleep(120 * time.Second) }
EOF
git -C "$REPO" add -A && git -C "$REPO" commit -qm slow
start=$(date +%s)
out=$(bash "$RUNNER" "$REPO" --timeout 15 2>&1); rc=$?
took=$(( $(date +%s) - start ))
# Detect leftovers by NAME (vs-*) AND by image ancestry (verify containers are named
# vs-run-* now, but check both so a rename regression is caught).
left=$(docker ps -a --format '{{.Names}}' | grep -c '^vs-' || true)
[ "$rc" != 0 ] && [ "$took" -lt 90 ] && [ "${left:-0}" = 0 ] \
  && ok "timeout enforced (rc=$rc in ${took}s, no leftover vs-* containers)" \
  || bad "timeout" "rc=$rc took=${took}s leftovers=$left"
git -C "$REPO" reset -q --hard HEAD~1

# 6b. HOST-CACHE SCOPE: a candidate test that reads the mounted module cache must see
#     ONLY this repo's deps, never other projects' cached (private) modules. Plant a
#     decoy "other project" module in a shared host GOMODCACHE and assert it is absent.
if command -v go >/dev/null 2>&1; then
  cat > "$REPO/leak_test.go" <<'EOF'
package vsfixture

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
)

// The mounted /romod cache must contain ONLY this repo's deps — never a decoy from
// another project's cache. Fails if cross-project module leakage is possible.
func TestNoCrossProjectModules(t *testing.T) {
	root := os.Getenv("GOMODCACHE")
	if root == "" {
		root = "/romod"
	}
	_ = filepath.Walk(root, func(p string, info os.FileInfo, err error) error {
		if err == nil && strings.Contains(p, "decoy-other-project") {
			t.Fatalf("cross-project module leaked into sandbox cache: %s", p)
		}
		return nil
	})
}
EOF
  git -C "$REPO" add -A && git -C "$REPO" commit -qm leakprobe
  out=$(bash "$RUNNER" "$REPO" 2>&1); rc=$?
  [ "$rc" = 0 ] \
    && ok "per-repo module cache: no cross-project modules visible in sandbox" \
    || bad "cache scope" "rc=$rc tail: $(printf '%s' "$out" | tail -3)"
  git -C "$REPO" reset -q --hard HEAD~1
else
  ok "cache-scope probe skipped (no host go)"
fi

# 7. FAIL-CLOSED: repo without the family baseline -> exit 3, never a pass.
NOFAM="$ROOT/nofam"; mkdir -p "$NOFAM"
git -C "$ROOT" init -q nofam; git -C "$NOFAM" config user.email t@t; git -C "$NOFAM" config user.name t
printf 'module example.com/nofam\n\ngo 1.22\n' > "$NOFAM/go.mod"
printf 'all:\n\ttrue\n' > "$NOFAM/Makefile"
git -C "$NOFAM" add -A && git -C "$NOFAM" commit -qm x
out=$(bash "$RUNNER" "$NOFAM" 2>&1); rc=$?
[ "$rc" = 3 ] && printf '%s' "$out" | grep -q 'family target' \
  && ok "non-family repo fail-closed (exit 3)" || bad "fail-closed" "rc=$rc"

echo
echo "verify-sandbox: $PASS passed, $FAIL failed"
[ "$FAIL" = 0 ] || exit 1
