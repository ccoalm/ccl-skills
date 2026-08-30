#!/usr/bin/env bash
# Real-repository audit of the checked-in obligation mapping/ledger.
#
# test_obligation_ledger.sh proves the TOOL against synthetic fixtures; it
# cannot see drift in the real specs/065 mapping — a later semantic edit to a
# carrier file invalidates checked-in carrier text/hashes while every synthetic
# suite stays green (this exact false green shipped once: the PR's own audit
# exited 1 at its head while validation evidence recorded it as passing).
#
# The base commit comes from the SHA pinned in the committed ledger header, so
# the audit stays reproducible after the base branch advances. Requires full
# history (CI checkouts use fetch-depth: 0); a missing base commit fails
# closed rather than skipping.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd -P)"
ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd -P)"
TOOL="$SCRIPT_DIR/obligation-ledger.py"
LEDGER="$ROOT/specs/065-uiux-evidence-delivery/obligation-preservation.md"
MAPPING="$ROOT/specs/065-uiux-evidence-delivery/obligation-mapping.jsonl"

fail() { printf 'FAIL: %b\n' "$*" >&2; exit 1; }

[ -f "$LEDGER" ] || fail "ledger missing: $LEDGER"
[ -f "$MAPPING" ] || fail "mapping missing: $MAPPING"

base="$(sed -n 's/^- Base revision: `\([0-9a-f]\{40\}\)`$/\1/p' "$LEDGER")"
[ -n "$base" ] || fail "no pinned 40-hex base SHA in the ledger header; the header must record the resolved base commit"
case "$base" in
  *$'\n'*) fail "multiple base-revision lines in the ledger header" ;;
esac

# The head must be pinned too: an unbounded head makes this frozen ledger
# demand preservation rows from every later, unrelated skills/**/*.md change
# (observed: the first post-landing PR went red on rows it never owed).
head="$(sed -n 's/^- Head revision: `\([0-9a-f]\{40\}\)`$/\1/p' "$LEDGER")"
[ -n "$head" ] || fail "no pinned 40-hex head SHA in the ledger header; regenerate the ledger with --head at its landing commit"
case "$head" in
  *$'\n'*) fail "multiple head-revision lines in the ledger header" ;;
esac

git -C "$ROOT" cat-file -e "$base^{commit}" 2>/dev/null \
  || fail "pinned base commit $base is absent; this audit needs full history (fetch-depth: 0)"
git -C "$ROOT" cat-file -e "$head^{commit}" 2>/dev/null \
  || fail "pinned head commit $head is absent; this audit needs full history (fetch-depth: 0)"

audit_output="$(python3 "$TOOL" audit \
  --repo "$ROOT" --base "$base" --head "$head" \
  --mapping "$MAPPING" --ledger "$LEDGER" 2>&1)" \
  || fail "real-repository obligation audit failed:\n$audit_output"
case "$audit_output" in
  *audit_ok*) : ;;
  *) fail "audit exited 0 without the audit_ok sentinel:\n$audit_output" ;;
esac
printf '%s\n' "$audit_output" | tail -1

echo "test_obligation_ledger_repo_audit_ok"
