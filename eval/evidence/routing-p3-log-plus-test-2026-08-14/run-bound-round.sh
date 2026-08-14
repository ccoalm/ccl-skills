#!/bin/bash
# Full-surface-bound measurement round runner for the p3-log-plus-test independent round.
# Methodology inherited from routing-oncall-sop h1a final state:
#   binding sidecar = hash of the FULL routing input surface (all skills/*/SKILL.md
#   description lines, dir-name-tagged, in sorted glob order + the bank file bytes),
#   captured before AND after each round, plus repo HEAD and skills-tree clean proof.
# This committed copy is the checkout-independent revision (chain r1 P1 fix): the
# generating revision at commit 9fcba9d differed only by hard-coding the generating
# worktree root and requiring absolute bank/outdir arguments; see MANIFEST.json
# provenance_correction for the exact generating invocation and validity proof.
# Usage: run-bound-round.sh <round-number> <bank-file> <out-dir>
set -uo pipefail

WT="$(git -C "$(cd "$(dirname "$0")" && pwd -P)" rev-parse --show-toplevel)" || exit 1
[ "$#" -eq 3 ] || { echo "usage: run-bound-round.sh <round-number> <bank-file> <out-dir>" >&2; exit 2; }
case "$1" in
  ''|*[!0-9]*|0*) echo "round-number must be a positive decimal integer, got: $1" >&2; exit 2;;
esac
N="$1"
BANK="$(cd "$(dirname "$2")" && pwd -P)/$(basename "$2")" || exit 1
test -r "$BANK" || { echo "bank file not readable: $BANK" >&2; exit 1; }
mkdir -p "$3" || exit 1
OUTDIR="$(cd "$3" && pwd -P)" || exit 1
OUT="$OUTDIR/round-$N.json"

surface_hash() {
  {
    for f in "$WT"/skills/*/SKILL.md; do
      d=$(basename "$(dirname "$f")")
      printf '%s\t' "$d"
      grep -m1 '^description:' "$f"
    done
    cat "$BANK"
  } | shasum -a 256 | awk '{print $1}'
}

BEFORE=$(surface_hash)
HEAD_SHA=$(git -C "$WT" rev-parse HEAD)
DIRTY=$(git -C "$WT" status --porcelain -- skills/ | wc -l | tr -d ' ')

# Evaluator writes to a fresh temp path; it is validated and only then atomically
# moved into place, so a stale pre-existing round-$N.json can never be hashed or
# validated as this run's result (extension-challenge P1: stale-output reuse).
TMP_OUT="$(mktemp "$OUTDIR/.round-$N.json.XXXXXX")" || exit 1
trap 'rm -f "$TMP_OUT"' EXIT
(cd "$WT" && ruby skills/skill-extraction-workflow/scripts/eval-routing-bank.rb . --bank "$BANK" --timeout 120 --json "$TMP_OUT")
RC=$?

AFTER=$(surface_hash)
DESC_SHA=$(grep -m1 '^description:' "$WT/skills/platform-observability/SKILL.md" | shasum -a 256 | awk '{print $1}')
OUT_OK=false
if [ -f "$TMP_OUT" ] && [ -s "$TMP_OUT" ] \
   && python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); rs=d["results"]; assert isinstance(rs,list) and rs and all("status" in r and "selected" in r for r in rs)' "$TMP_OUT" 2>/dev/null; then
  OUT_OK=true
fi
ROUND_SHA=""
if [ "$OUT_OK" = "true" ]; then
  mv -f "$TMP_OUT" "$OUT" || exit 1
  ROUND_SHA=$(shasum -a 256 "$OUT" 2>/dev/null | awk '{print $1}')
  [ -n "$ROUND_SHA" ] || OUT_OK=false
fi
VALID=false
if [ "$BEFORE" = "$AFTER" ] && [ "$DIRTY" = "0" ] && [ "$RC" = "0" ] && [ "$OUT_OK" = "true" ]; then VALID=true; fi

cat > "$OUT.binding.json" <<EOF
{"round_file": "round-$N.json", "round_file_sha256": "$ROUND_SHA", "routing_surface_sha256_before": "$BEFORE", "routing_surface_sha256_after": "$AFTER", "surface_scope": "all skills/*/SKILL.md description lines (dir-name-tagged, sorted glob order) + the bank file", "platform_observability_description_line_sha256": "$DESC_SHA", "skills_tree_dirty_entries": $DIRTY, "binding_valid": $VALID, "repo_head": "$HEAD_SHA", "runner_rc": $RC, "captured_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)"}
EOF

echo "round-$N rc=$RC binding_valid=$VALID"
if [ "$RC" != "0" ]; then exit "$RC"; fi
[ "$VALID" = "true" ] || exit 1
exit 0
