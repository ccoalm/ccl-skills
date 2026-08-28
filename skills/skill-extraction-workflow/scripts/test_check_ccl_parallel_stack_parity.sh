#!/usr/bin/env bash
# Integration test for check-parallel-stack-parity.sh (the cross-file mirror gate
# wired into check-ccl-skills.sh). Builds throwaway sibling trees so verdicts are
# DETERMINISTIC and do not depend on the real repository's current file content.
#
# Cases:
#   a. identical mirrored regions + differing stack-glue        => exit 0, ok marker
#   b. one-word drift inside the mirrored region                => exit 1, parity_drift + FAIL marker
#   c. dual-tree routing text identical on both sides           => exit 0 (the supported shape)
#   d. one-sided sibling-name / routing-reference divergence    => exit 1, parity_drift (no normalization)
#   e. missing sibling file                                     => exit 1, parity_missing_file
#   f. missing marker headings                                   => exit 1, parity_malformed_markers
#   g. stop heading duplicated                                   => exit 1, parity_malformed_markers
#   h. canonical (non-routing-mapped) reference swapped one side => exit 1, parity_drift
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

# --- case c: the supported dual-tree routing shape — identical bytes on both sides => ok
DUAL="${MIRROR_BASE/\`local-a.md\`/\`api-contract-and-schema.md\` on the Python tree \/ \`protobuf-contract-architecture.md\` on the Go tree}"
write_pair "event-driven-architecture" "$DUAL" "$DUAL"
run_gate
assert_rc "$RC" 0 "case c"
assert_contains "parallel_stack_parity_ok" "$OUT" "case c"

# --- case d: one-sided divergence is drift — there is NO normalization to hide behind
# (d1: a routing reference differing per side; d2: an asymmetric sibling-name mention)
PY_REFS_BODY="${MIRROR_BASE/\`local-a.md\`/\`api-contract-and-schema.md\`}"
GO_REFS_BODY="${MIRROR_BASE/\`local-a.md\`/\`protobuf-contract-architecture.md\`}"
write_pair "event-driven-architecture" "$PY_REFS_BODY" "$GO_REFS_BODY"
run_gate
assert_rc "$RC" 1 "case d1"
assert_contains "parity_drift: event-driven-architecture.md" "$OUT" "case d1"
PY_NAME_BODY="${MIRROR_BASE/python-service-architecture and go-microservice-architecture/python-service-architecture}"
GO_NAME_BODY="${MIRROR_BASE/python-service-architecture and go-microservice-architecture/go-microservice-architecture}"
write_pair "event-driven-architecture" "$PY_NAME_BODY" "$GO_NAME_BODY"
run_gate
assert_rc "$RC" 1 "case d2"
assert_contains "parity_drift: event-driven-architecture.md" "$OUT" "case d2"

# --- case e: missing sibling file => FAIL with missing token
rm "$GO_REFS/event-driven-architecture.md"
run_gate
assert_rc "$RC" 1 "case e"
assert_contains "parity_missing_file: event-driven-architecture.md" "$OUT" "case e"

# --- case f: start marker missing => FAIL with malformed-markers token
seed_all_identical
printf '# t\n\nno markers here\n\n## Go-specific implementation patterns\n\nx\n' > "$GO_REFS/multi-tenant-isolation.md"
run_gate
assert_rc "$RC" 1 "case f"
assert_contains "parity_malformed_markers: multi-tenant-isolation.md" "$OUT" "case f"

# --- case g: stop heading duplicated => FAIL with malformed-markers token (a missing or
# doubled stop must not silently fall through to a drift/ok verdict)
seed_all_identical
printf '\n## Go-specific implementation patterns\n\n- dup glue\n' >> "$GO_REFS/event-driven-architecture.md"
run_gate
assert_rc "$RC" 1 "case g"
assert_contains "parity_malformed_markers: event-driven-architecture.md" "$OUT" "case g"

# --- case h: canonical-pointer swap on one side only stays drift
seed_all_identical
PY_CANON="${MIRROR_BASE/Delivery semantics declared explicitly./Delivery semantics declared explicitly per \`data-modeling-and-migrations.md\`.}"
GO_CANON="${MIRROR_BASE/Delivery semantics declared explicitly./Delivery semantics declared explicitly per \`background-jobs-and-scheduling.md\`.}"
write_pair "event-driven-architecture" "$PY_CANON" "$GO_CANON"
run_gate
assert_rc "$RC" 1 "case h"
assert_contains "parity_drift: event-driven-architecture.md" "$OUT" "case h"

# --- case i: prefix/suffix-gamed stop heading => malformed, not silent region shrink
seed_all_identical
python_side="$PY_REFS/event-driven-architecture.md"
sed_inplace() { local expr="$1" file="$2"; sed "$expr" "$file" > "$file.tmp" && mv "$file.tmp" "$file"; }
sed_inplace 's/^## Python-specific implementation patterns$/## Python-specific implementation patterns (v2)/' "$python_side"
run_gate
assert_rc "$RC" 1 "case i"
assert_contains "parity_malformed_markers: event-driven-architecture.md" "$OUT" "case i"

echo "test_check_ccl_parallel_stack_parity_ok"
