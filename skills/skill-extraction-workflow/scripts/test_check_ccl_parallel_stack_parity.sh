#!/usr/bin/env bash
# Integration test for check-parallel-stack-parity.sh (the cross-file mirror gate
# wired into check-ccl-skills.sh). Builds throwaway sibling trees so verdicts are
# DETERMINISTIC and do not depend on the real repository's current file content.
#
# Cases:
#   a. identical mirrored regions + differing stack-glue        => exit 0, ok marker
#   b. one-word drift inside the mirrored region                => exit 1, parity_drift + FAIL marker
#   c. routing-reference divergence (one `x.md` vs `y.md` or `z.md`) => exit 0 (allowed class)
#   d. sibling skill-name mentions inside the mirrored region   => exit 0 (allowed class)
#   e. missing sibling file                                     => exit 1, parity_missing_file
#   f. missing marker headings (mirrored region not extractable) => exit 1, parity_empty_mirrored_region
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd -P)"
PARITY_SCRIPT="$SCRIPT_DIR/check-parallel-stack-parity.sh"
[ -f "$PARITY_SCRIPT" ] || { echo "FAIL: parity script not found: $PARITY_SCRIPT" >&2; exit 1; }

TMP="$(mktemp -d "${TMPDIR:-/tmp}/stackparity.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

fail() { echo "FAIL: $*" >&2; exit 1; }
assert_rc() { [ "$1" = "$2" ] || fail "expected rc=$2 got rc=$1${3:+ ($3)}"; }
assert_contains() { case "$2" in *"$1"*) : ;; *) fail "expected output to contain: $1${3:+ ($3)}";; esac; }
assert_not_contains() { case "$2" in *"$1"*) fail "expected output NOT to contain: $1${3:+ ($3)}";; *) : ;; esac; }

PY_REFS="$TMP/skills/python-service-architecture/references"
GO_REFS="$TMP/skills/go-microservice-architecture/references"
mkdir -p "$PY_REFS" "$GO_REFS"

# write_pair <mirrored-body-file-py> <mirrored-body-file-go>
# Wraps each body in the standard skeleton: title + mirrored region + stack glue.
write_pair() {
  local name="$1" py_body="$2" go_body="$3"
  {
    echo "# $name (Python)"
    echo
    echo "Sibling: go-microservice-architecture mirrors this file."
    echo
    printf '%s\n' "$py_body"
    echo "## Python-specific implementation patterns"
    echo
    echo "- Python glue: asyncio consumer shape."
  } > "$PY_REFS/$name.md"
  {
    echo "# $name (Go)"
    echo
    echo "Sibling: python-service-architecture mirrors this file."
    echo
    printf '%s\n' "$go_body"
    echo "## Go-specific implementation patterns"
    echo
    echo "- Go glue: goroutine consumer shape."
  } > "$GO_REFS/$name.md"
}

MIRROR_BASE='## When this applies / does not apply

Apply when the service publishes durable events.
Skip when it only does in-process pub-sub (use `local-a.md` instead).
The sibling tree is maintained by python-service-architecture and go-microservice-architecture maintainers.

## Operations checklist

- Delivery semantics declared explicitly.
'

# The gate iterates a fixed pair list; give all three names the same skeleton, then
# vary the one under test per case.
seed_all_identical() {
  write_pair "event-driven-architecture" "$MIRROR_BASE" "$MIRROR_BASE"
  write_pair "multi-tenant-isolation" "$MIRROR_BASE" "$MIRROR_BASE"
  write_pair "data-platform-architecture" "$MIRROR_BASE" "$MIRROR_BASE"
}

run_gate() {
  set +e
  OUT="$(bash "$PARITY_SCRIPT" "$TMP" 2>&1)"
  RC=$?
  set -e
}

# --- case a: identical mirrored regions, differing glue => ok
seed_all_identical
run_gate
assert_rc "$RC" 0 "case a"
assert_contains "parallel_stack_parity_ok" "$OUT" "case a"

# --- case b: one-word drift in a mirrored region => FAIL naming the pair
GO_DRIFT="${MIRROR_BASE/durable events/durable events plus commands}"
write_pair "event-driven-architecture" "$MIRROR_BASE" "$GO_DRIFT"
run_gate
assert_rc "$RC" 1 "case b"
assert_contains "parity_drift: event-driven-architecture.md" "$OUT" "case b"
assert_contains "parallel_stack_parity_FAIL" "$OUT" "case b"

# --- case c: routing-reference divergence (different refs, different list length) => ok
PY_REFS_BODY="${MIRROR_BASE/\`local-a.md\`/\`api-contract-and-schema.md\` or \`web-framework-boundaries.md\`}"
GO_REFS_BODY="${MIRROR_BASE/\`local-a.md\`/\`protobuf-contract-architecture.md\`}"
write_pair "event-driven-architecture" "$PY_REFS_BODY" "$GO_REFS_BODY"
run_gate
assert_rc "$RC" 0 "case c"
assert_contains "parallel_stack_parity_ok" "$OUT" "case c"

# --- case d: sibling skill-name mentions normalize => ok (already exercised by
# MIRROR_BASE naming both skills; pin it explicitly with asymmetric ordering)
PY_NAME_BODY="${MIRROR_BASE/python-service-architecture and go-microservice-architecture/python-service-architecture}"
GO_NAME_BODY="${MIRROR_BASE/python-service-architecture and go-microservice-architecture/go-microservice-architecture}"
write_pair "event-driven-architecture" "$PY_NAME_BODY" "$GO_NAME_BODY"
run_gate
assert_rc "$RC" 0 "case d"

# --- case e: missing sibling file => FAIL with missing token
rm "$GO_REFS/event-driven-architecture.md"
run_gate
assert_rc "$RC" 1 "case e"
assert_contains "parity_missing_file: event-driven-architecture.md" "$OUT" "case e"

# --- case f: marker headings missing => FAIL with empty-region token
seed_all_identical
printf '# t\n\nno markers here\n\n## Go-specific implementation patterns\n\nx\n' > "$GO_REFS/multi-tenant-isolation.md"
run_gate
assert_rc "$RC" 1 "case f"
assert_contains "parity_empty_mirrored_region: multi-tenant-isolation.md" "$OUT" "case f"

echo "test_check_ccl_parallel_stack_parity_ok"
