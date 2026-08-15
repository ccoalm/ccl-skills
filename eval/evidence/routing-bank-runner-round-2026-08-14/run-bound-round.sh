#!/bin/bash
# Full-surface-bound measurement round runner for the bank/runner co-change round.
# Methodology inherited from the routing-p3-log-plus-test checkout-independent
# revision, with one addition for this round's runner self-identification change:
# the evaluator now embeds routing_surface in its own report, and this wrapper
# independently recomputes the same quantity (all skills/*/SKILL.md description
# lines, dir-name-tagged, sorted glob order + the bank file bytes) and requires
# the two to MATCH — two independent computations of one binding, so a report
# claiming the wrong surface invalidates the round.
# The candidate under measurement is the runner script + the bank file, so the
# sidecar also records both hashes.
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
# Concluded-round artifacts are immutable: a rerun must never destroy an
# existing round file or sidecar even when its own output later turns out
# invalid (extension-challenge P1: the old flow moved the temp file into place
# BEFORE the completeness/binding checks decided validity) — refuse up front.
if [ -e "$OUT" ] || [ -e "$OUT.binding.json" ]; then
  echo "refusing: $OUT or its sidecar already exists (concluded-round artifacts are immutable; use a fresh out-dir or round number)" >&2
  exit 1
fi

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

# The raw first-line surface above misses a multiline YAML description
# (`description: >-` continuation lines change what the grader SEES without
# changing the first raw line — both review lanes hit this hole), so the
# wrapper also independently recomputes the GRADED catalog text with the same
# construction the evaluator uses (frontmatter parse, YAML description value,
# plain arm) and requires the evaluator's embedded catalog_sha256 to match it,
# before AND after the round.
catalog_hash() {
  (cd "$WT" && ruby -ryaml -rdigest -e '
    catalog = Dir[File.join("skills", "*", "SKILL.md")].sort.map do |path|
      name = File.basename(File.dirname(path))
      m = File.read(path).match(/\A---\s*\n(.*?)\n---\s*\n/m)
      next unless m
      desc = (YAML.safe_load(m[1]) rescue {})["description"].to_s.strip
      next if desc.empty?
      "### #{name}\n#{desc}"
    end.compact.join("\n\n")
    puts Digest::SHA256.hexdigest(catalog)
  ')
}

BEFORE=$(surface_hash)
CAT_BEFORE=$(catalog_hash)
HEAD_SHA=$(git -C "$WT" rev-parse HEAD)
DIRTY=$(git -C "$WT" status --porcelain -- skills/ | wc -l | tr -d ' ')
RUNNER_SHA=$(shasum -a 256 "$WT/skills/skill-extraction-workflow/scripts/eval-routing-bank.rb" | awk '{print $1}')
BANK_SHA=$(shasum -a 256 "$BANK" | awk '{print $1}')

# Evaluator writes to a fresh temp path; it is validated and only then atomically
# moved into place, so a stale pre-existing round-$N.json can never be hashed or
# validated as this run's result (stale-output reuse guard, inherited).
TMP_OUT="$(mktemp "$OUTDIR/.round-$N.json.XXXXXX")" || exit 1
trap 'rm -f "$TMP_OUT"' EXIT
(cd "$WT" && ruby skills/skill-extraction-workflow/scripts/eval-routing-bank.rb . --bank "$BANK" --timeout 120 --json "$TMP_OUT")
RC=$?

AFTER=$(surface_hash)
CAT_AFTER=$(catalog_hash)
OUT_OK=false
if [ -f "$TMP_OUT" ] && [ -s "$TMP_OUT" ] \
   && python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); rs=d["results"]; assert isinstance(rs,list) and rs and all("status" in r and "selected" in r for r in rs)' "$TMP_OUT" 2>/dev/null; then
  OUT_OK=true
fi
# A structurally valid report can still silently COVER LESS THAN THE BANK (a
# broken evaluator that skips cases keeps every hash check green — r2 challenge
# P1), so the wrapper independently parses the bank and requires the report's
# result ids to match the bank ids exactly (no missing, duplicate, or
# unexpected entries) with self-consistent totals.
IDS_OK=false
if [ "$OUT_OK" = "true" ]; then
  if python3 - "$TMP_OUT" "$BANK" <<'PYCHECK' >/dev/null 2>&1; then IDS_OK=true; fi
import json, sys
report = json.load(open(sys.argv[1]))
bank_ids = []
for line in open(sys.argv[2], encoding="utf-8"):
    line = line.strip()
    if line:
        bank_ids.append(json.loads(line)["id"])
results = report["results"]
result_ids = [r.get("id") for r in results]
assert sorted(result_ids) == sorted(bank_ids), "result ids do not match bank ids"
assert len(result_ids) == len(set(result_ids)), "duplicate result ids"
assert report.get("tasks") == len(results), "tasks total inconsistent"
assert report.get("pass", 0) + report.get("fail", 0) + report.get("error", 0) == len(results), "verdict totals inconsistent"
PYCHECK
fi
EMBEDDED=""
EMBED_CAT=""
if [ "$OUT_OK" = "true" ]; then
  EMBEDDED=$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1])).get("routing_surface",{}).get("descriptions_sha256") or "")' "$TMP_OUT" 2>/dev/null)
  EMBED_CAT=$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1])).get("routing_surface",{}).get("catalog_sha256") or "")' "$TMP_OUT" 2>/dev/null)
fi
EMBED_OK=false
[ -n "$EMBEDDED" ] && [ "$EMBEDDED" = "$BEFORE" ] && EMBED_OK=true
EMBED_CAT_OK=false
[ -n "$EMBED_CAT" ] && [ -n "$CAT_BEFORE" ] && [ "$EMBED_CAT" = "$CAT_BEFORE" ] && EMBED_CAT_OK=true
ROUND_SHA=""
if [ "$OUT_OK" = "true" ]; then
  ROUND_SHA=$(shasum -a 256 "$TMP_OUT" 2>/dev/null | awk '{print $1}')
  [ -n "$ROUND_SHA" ] || OUT_OK=false
fi
VALID=false
if [ "$BEFORE" = "$AFTER" ] && [ "$CAT_BEFORE" = "$CAT_AFTER" ] && [ "$DIRTY" = "0" ] && [ "$RC" = "0" ] && [ "$OUT_OK" = "true" ] && [ "$IDS_OK" = "true" ] && [ "$EMBED_OK" = "true" ] && [ "$EMBED_CAT_OK" = "true" ]; then VALID=true; fi
# The round file lands ONLY after every validity leg passed; an invalid run
# leaves no round file behind — its rejection is documented by the sidecar,
# whose round_file_sha256 still pins the rejected temp content for audit.
if [ "$VALID" = "true" ]; then
  mv "$TMP_OUT" "$OUT" || exit 1
fi

cat > "$OUT.binding.json" <<EOF
{"round_file": "round-$N.json", "round_file_sha256": "$ROUND_SHA", "routing_surface_sha256_before": "$BEFORE", "routing_surface_sha256_after": "$AFTER", "surface_scope": "all skills/*/SKILL.md description lines (dir-name-tagged, sorted glob order) + the bank file", "graded_catalog_sha256_before": "$CAT_BEFORE", "graded_catalog_sha256_after": "$CAT_AFTER", "embedded_descriptions_sha256": "$EMBEDDED", "embedded_matches_surface": $EMBED_OK, "embedded_catalog_sha256": "$EMBED_CAT", "embedded_matches_catalog": $EMBED_CAT_OK, "results_match_bank": $IDS_OK, "runner_script_sha256": "$RUNNER_SHA", "bank_sha256": "$BANK_SHA", "skills_tree_dirty_entries": $DIRTY, "binding_valid": $VALID, "repo_head": "$HEAD_SHA", "runner_rc": $RC, "captured_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)"}
EOF

echo "round-$N rc=$RC binding_valid=$VALID embedded_matches_surface=$EMBED_OK embedded_matches_catalog=$EMBED_CAT_OK results_match_bank=$IDS_OK"
if [ "$RC" != "0" ]; then exit "$RC"; fi
[ "$VALID" = "true" ] || exit 1
exit 0
