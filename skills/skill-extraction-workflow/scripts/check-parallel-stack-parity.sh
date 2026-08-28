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
#   2. routing-reference text: backticked `*.md` file references may point at different sibling
#      files per tree, so every backticked .md reference is normalized to <REF> before diffing.
# Everything else in the mirrored region must be byte-identical, or the pair has drifted.
# The optional "## Topic-extension backlog" H2 after the stack-glue H2 is mirrored by
# convention but excluded from this strict gate (its section rule allows near-identical
# wording so it can name vendors/engines); keep it in sync by review.
#
# Usage: check-parallel-stack-parity.sh [repo-root]   (default: .)
# Output: parallel_stack_parity_ok on success; parity_drift + a bounded diff per drifted pair
# and parallel_stack_parity_FAIL (exit 1) on failure.
set -euo pipefail

ROOT="${1:-.}"
PY_DIR="$ROOT/skills/python-service-architecture/references"
GO_DIR="$ROOT/skills/go-microservice-architecture/references"

PAIRS=(
  "event-driven-architecture.md"
  "multi-tenant-isolation.md"
  "data-platform-architecture.md"
)

extract_mirrored() { # $1=file $2=stack-specific H2 literal prefix
  awk -v stop="$2" '
    index($0, "## When this applies") == 1 { on = 1 }
    on && index($0, stop) == 1 { exit }
    on { print }
  ' "$1"
}

normalize() {
  # A routing-reference LIST may differ in length per tree ("route to `a.md` or `b.md`" vs
  # "route to `c.md`"), so collapse "<REF> or <REF>[ or <REF>...]" to one <REF> after mapping.
  sed -E \
    -e 's/`[A-Za-z0-9_./-]+\.md`/<REF>/g' \
    -e 's/<REF>( or <REF>)+/<REF>/g' \
    -e 's/go-microservice-architecture/<SIBLING-ARCH>/g' \
    -e 's/python-service-architecture/<SIBLING-ARCH>/g' \
    -e 's/go-microservice-dev/<SIBLING-DEV>/g' \
    -e 's/python-service-dev/<SIBLING-DEV>/g'
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
  py_body=$(extract_mirrored "$py" "## Python-specific implementation patterns" | normalize)
  go_body=$(extract_mirrored "$go" "## Go-specific implementation patterns" | normalize)
  if [ -z "$py_body" ] || [ -z "$go_body" ]; then
    echo "parity_empty_mirrored_region: $f (marker headings missing or renamed)"
    fail=1
    continue
  fi
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
