#!/usr/bin/env bash
# check-parallel-stack-parity.sh — cross-file parity gate for parallel-stack mirrored references.
#
# The parallel-stack pattern (references/parallel-stack-references-pattern.md) requires the
# mirrored region of each sibling pair — everything from the exact heading line
# "## When this applies / does not apply" up to the stack-specific
# "## <Stack>-specific implementation patterns" H2 — to be BYTE-IDENTICAL across the Python
# and Go trees. There is deliberately NO normalization: earlier versions rewrote routing
# references and sibling skill names before diffing, and two adversarial rounds each found a
# fresh way that lossy rewriting could mask real drift (second element of an or-list swapped,
# canonical pointer replaced by a mapped name, self-reference via name mapping). The
# capability was removed rather than patched again: routing text that legitimately differs
# per tree is written INTO the mirrored region naming both trees inline —
#   `x.md` (Python) / `y.md` (Go)
# — so both files carry the same bytes and a one-sided change is always drift.
#
# Marker integrity: each marker must match as an EXACT whole line, exactly once, in order.
# A missing, duplicated, or prefix-gamed heading is a malformed-markers verdict, never a
# silent ok. Residual accepted and documented: moving BOTH stop markers earlier in the same
# change shrinks the compared region symmetrically; that is a visible, reviewable contract
# edit in the diff, not something this gate can distinguish from a legitimate region change.
# The optional "## Topic-extension backlog" H2 after the stack-glue H2 is mirrored by
# convention but excluded from this strict gate (its section rule allows near-identical
# wording so it can name vendors/engines); keep it in sync by review.
#
# Exit codes: 0 = parity ok; 1 = drift / missing file / malformed markers (content verdict);
# 2 = infrastructure failure (this script could not run its own checks).
#
# Usage: check-parallel-stack-parity.sh [repo-root]   (default: .)
set -euo pipefail

ROOT="${1:-.}"
PY_DIR="$ROOT/skills/python-service-architecture/references"
GO_DIR="$ROOT/skills/go-microservice-architecture/references"

START_MARKER="## When this applies / does not apply"

PAIRS=(
  "event-driven-architecture.md"
  "multi-tenant-isolation.md"
  "data-platform-architecture.md"
)

# count_exact <file> <exact line> — prints the match count. Distinguishes grep's "no
# match" (rc 1, a legitimate count of 0) from a hard failure such as an unreadable file
# (rc >1), which must surface as infrastructure failure, never as a content verdict.
count_exact() {
  local c rc
  set +e; c=$(grep -cxF "$2" "$1"); rc=$?; set -e
  case "$rc" in
    0|1) printf '%s\n' "${c:-0}"; return 0 ;;
    *) return 2 ;;
  esac
}

# extract_mirrored <file> <stop-H2 exact line> <out-file>
# Writes the mirrored region to <out-file> BYTE-EXACTLY (a file, not a command
# substitution: $(...) strips trailing newlines, which let a trailing blank line before
# the stack-glue H2 diverge invisibly). Returns 1 on malformed markers (missing,
# duplicated, or out of order), 2 on infrastructure failure.
extract_mirrored() {
  local file="$1" stop="$2" out="$3" starts stops start_line stop_line
  starts=$(count_exact "$file" "$START_MARKER") || return 2
  stops=$(count_exact "$file" "$stop") || return 2
  if [ "$starts" -ne 1 ] || [ "$stops" -ne 1 ]; then
    return 1
  fi
  start_line=$(grep -nxF "$START_MARKER" "$file" | head -1 | cut -d: -f1) || return 2
  stop_line=$(grep -nxF "$stop" "$file" | head -1 | cut -d: -f1) || return 2
  if [ "$start_line" -ge "$stop_line" ]; then
    return 1
  fi
  sed -n "${start_line},$((stop_line - 1))p" "$file" > "$out" || return 2
}

WORK="$(mktemp -d "${TMPDIR:-/tmp}/stack-parity.XXXXXX")" || { echo "parity_infra: mktemp failed" >&2; exit 2; }
trap 'rm -rf "$WORK"' EXIT

fail=0
for f in "${PAIRS[@]}"; do
  py="$PY_DIR/$f"
  go="$GO_DIR/$f"
  if [ ! -f "$py" ] || [ ! -f "$go" ]; then
    echo "parity_missing_file: $f"
    fail=1
    continue
  fi
  py_out="$WORK/py-$f.txt"; go_out="$WORK/go-$f.txt"
  rc=0; extract_mirrored "$py" "## Python-specific implementation patterns" "$py_out" || rc=$?
  if [ "$rc" -eq 2 ]; then echo "parity_infra: $f (python side: grep/sed could not run)" >&2; exit 2; fi
  if [ "$rc" -ne 0 ]; then
    echo "parity_malformed_markers: $f (python side: start/stop heading missing, duplicated, not an exact heading line, or out of order)"
    fail=1
    continue
  fi
  rc=0; extract_mirrored "$go" "## Go-specific implementation patterns" "$go_out" || rc=$?
  if [ "$rc" -eq 2 ]; then echo "parity_infra: $f (go side: grep/sed could not run)" >&2; exit 2; fi
  if [ "$rc" -ne 0 ]; then
    echo "parity_malformed_markers: $f (go side: start/stop heading missing, duplicated, not an exact heading line, or out of order)"
    fail=1
    continue
  fi
  if [ ! -s "$py_out" ] || [ ! -s "$go_out" ]; then
    echo "parity_empty_mirrored_region: $f"
    fail=1
    continue
  fi
  if ! cmp -s "$py_out" "$go_out"; then
    echo "parity_drift: $f"
    diff "$py_out" "$go_out" | head -40 || true
    fail=1
  fi
done

if [ "$fail" -ne 0 ]; then
  echo "parallel_stack_parity_FAIL"
  exit 1
fi
echo "parallel_stack_parity_ok"
