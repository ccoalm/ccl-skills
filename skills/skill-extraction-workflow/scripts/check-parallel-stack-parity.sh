#!/usr/bin/env bash
# check-parallel-stack-parity.sh — cross-file parity gate for parallel-stack mirrored references.
#
# The parallel-stack pattern (references/parallel-stack-references-pattern.md) requires the
# mirrored region of each sibling pair — everything from "## When this applies" up to the
# stack-specific "## <Stack>-specific implementation patterns" H2 — to stay in sync across the
# Python and Go trees. The per-file grep gates check token hygiene INSIDE one file; they cannot
# see cross-file drift. This gate diffs the mirrored regions after normalizing the two divergence
# classes the pattern explicitly allows:
#   1. sibling skill names (each file names the OTHER tree's skill in headers/pointers);
#   2. routing references that legitimately differ per tree — normalized via the EXPLICIT
#      per-pair mapping table below (Go-side reference -> Python-side counterpart), plus a
#      generic collapse of "`a.md` or `b.md`" reference lists to their first element on both
#      sides. A backticked reference NOT in the mapping must be byte-identical on both sides,
#      so swapping a canonical pointer to an unrelated file on one sibling is drift, not an
#      allowed divergence. Extending the mapping is a reviewable edit to this script.
# Everything else in the mirrored region must be byte-identical, or the pair has drifted.
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

PAIRS=(
  "event-driven-architecture.md"
  "multi-tenant-isolation.md"
  "data-platform-architecture.md"
)

# Go-side routing reference -> Python-side counterpart. Order-independent pairs where the
# two trees legitimately route the same concern to differently-named sibling files.
REF_MAP_GO=(
  "protobuf-contract-architecture.md"
  "notification-architecture.md"
  "bulk-workflow-architecture.md"
  "api-security-boundaries.md"
)
REF_MAP_PY=(
  "api-contract-and-schema.md"
  "background-jobs-and-scheduling.md"
  "batch-and-pipeline-architecture.md"
  "web-framework-boundaries.md"
)

# extract_mirrored <file> <stop-H2-literal>
# Prints the mirrored region; fails (return 1) unless the start marker and the stop marker
# each occur EXACTLY once and in that order. A missing stop marker must not silently yield
# a nonempty body (review finding: that path previously reported drift-or-ok, never
# malformed-markers).
extract_mirrored() {
  # Markers are matched at LINE START: the heading string also appears in prose and in the
  # embedded grep-gate's awk command, so a substring match would over-count and false-fail.
  local file="$1" stop="$2" starts stops start_line stop_line
  starts=$(grep -c '^## When this applies' "$file") || starts=0
  stops=$(grep -c "^$stop" "$file") || stops=0
  if [ "$starts" -ne 1 ] || [ "$stops" -ne 1 ]; then
    return 1
  fi
  start_line=$(grep -n '^## When this applies' "$file" | head -1 | cut -d: -f1)
  stop_line=$(grep -n "^$stop" "$file" | head -1 | cut -d: -f1)
  if [ "$start_line" -ge "$stop_line" ]; then
    return 1
  fi
  sed -n "${start_line},$((stop_line - 1))p" "$file"
}

normalize_common() {
  # Collapse "`a.md` or `b.md`[ or ...]" reference lists to their first element, then map
  # sibling skill names. Applied to BOTH sides.
  sed -E \
    -e ':x' -e 's/(`[A-Za-z0-9_./-]+\.md`) or `[A-Za-z0-9_./-]+\.md`/\1/' -e 'tx' \
    -e 's/go-microservice-architecture/<SIBLING-ARCH>/g' \
    -e 's/python-service-architecture/<SIBLING-ARCH>/g' \
    -e 's/go-microservice-dev/<SIBLING-DEV>/g' \
    -e 's/python-service-dev/<SIBLING-DEV>/g'
}

map_go_refs() {
  # Rewrite mapped Go-side references to their Python counterparts. Unmapped references
  # pass through untouched and must match the Python side byte-for-byte.
  local sed_args=()
  local i
  for i in "${!REF_MAP_GO[@]}"; do
    sed_args+=(-e "s|\`${REF_MAP_GO[$i]}\`|\`${REF_MAP_PY[$i]}\`|g")
  done
  sed "${sed_args[@]}"
}

fail=0
for f in "${PAIRS[@]}"; do
  py="$PY_DIR/$f"
  go="$GO_DIR/$f"
  if [ ! -f "$py" ] || [ ! -f "$go" ]; then
    echo "parity_missing_file: $f"
    fail=1
    continue
  fi
  if ! py_raw=$(extract_mirrored "$py" "## Python-specific implementation patterns"); then
    echo "parity_malformed_markers: $f (python side: start/stop heading missing, duplicated, or out of order)"
    fail=1
    continue
  fi
  if ! go_raw=$(extract_mirrored "$go" "## Go-specific implementation patterns"); then
    echo "parity_malformed_markers: $f (go side: start/stop heading missing, duplicated, or out of order)"
    fail=1
    continue
  fi
  if [ -z "$py_raw" ] || [ -z "$go_raw" ]; then
    echo "parity_empty_mirrored_region: $f"
    fail=1
    continue
  fi
  py_body=$(printf '%s\n' "$py_raw" | normalize_common)
  go_body=$(printf '%s\n' "$go_raw" | map_go_refs | normalize_common)
  if [ "$py_body" != "$go_body" ]; then
    echo "parity_drift: $f"
    diff <(printf '%s\n' "$py_body") <(printf '%s\n' "$go_body") | head -40 || true
    fail=1
  fi
done

if [ "$fail" -ne 0 ]; then
  echo "parallel_stack_parity_FAIL"
  exit 1
fi
echo "parallel_stack_parity_ok"
