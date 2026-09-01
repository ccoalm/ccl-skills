#!/usr/bin/env bash
# Self-proof for test_frozen_case_sanctity.sh: builds a synthetic repo and
# proves the oracle can fail for the right reason on every guarded surface —
# deletion, judgment re-scope, subdirectory golden-trace deletion — and that
# adjudication credit cannot be minted by a prefix-colliding id or an HTML
# comment (only an added register TABLE ROW with a token-bounded id counts).
# The unmutated control and the properly-adjudicated leg must stay green, and
# the no-base leg must print the explicit skip token. Runs in mktemp only.
set -u

SCRIPTS_DIR="$(cd "$(dirname "$0")" && pwd)"
GATE="$SCRIPTS_DIR/test_frozen_case_sanctity.sh"
[ -f "$GATE" ] || { echo "FAIL: gate script missing ($GATE)" >&2; exit 1; }

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
REPO="$WORK/repo"
mkdir -p "$REPO/eval/golden-traces/nested" "$REPO/skills/skill-extraction-workflow/references"

BANK="$REPO/eval/routing-tasks.jsonl"
REG="$REPO/skills/skill-extraction-workflow/references/source-register.md"
cat > "$BANK" <<'EOF'
{"id": "a1", "utterance": "u1", "expected_skill": "s-one", "why_expected": "w", "frozen_at_sha": "root"}
{"id": "a1x", "utterance": "u2", "expected_skill": "s-two", "why_expected": "w", "frozen_at_sha": "root"}
EOF
cat > "$REPO/eval/golden-traces/nested/t1.json" <<'EOF'
{"id": "trace-nested-one", "assert": {"must_invoke_skill": "s-one"}}
EOF
printf '| base row |\n' > "$REG"

git -C "$REPO" init -q
git -C "$REPO" -c user.email=t@t -c user.name=t add -A
git -C "$REPO" -c user.email=t@t -c user.name=t commit -qm base
BASE_SHA="$(git -C "$REPO" rev-parse HEAD)"

pass=0
fail=0
ok()  { pass=$((pass+1)); }
bad() { fail=$((fail+1)); echo "FAIL: $1" >&2; }

run_gate() {
  SANCTITY_ROOT="$REPO" CCL_SKILL_BASE_REF="$BASE_SHA" bash "$GATE" > "$WORK/out.log" 2> "$WORK/err.log"
}

reset_tree() { git -C "$REPO" checkout -q -- .; }

# Leg 1: unmutated control is green with the success token.
reset_tree
if run_gate && grep -q "frozen_case_sanctity_ok" "$WORK/out.log"; then ok; else bad "control leg not green"; fi

# Leg 2: deleting bank case a1 reds, naming a1.
reset_tree
grep -v '"id": "a1",' "$BANK" > "$BANK.t" && mv "$BANK.t" "$BANK"
if run_gate; then bad "bank deletion passed"; else
  grep -q "deleted bank case 'a1'" "$WORK/err.log" && ok || bad "bank deletion red but not attributed to a1"
fi

# Leg 3: re-scoping a1's expected_skill reds.
reset_tree
python3 - "$BANK" <<'PY'
import json, sys
path = sys.argv[1]
rows = [json.loads(l) for l in open(path) if l.strip()]
rows[0]["expected_skill"] = "s-two"
open(path, "w").write("\n".join(json.dumps(r) for r in rows) + "\n")
PY
if run_gate; then bad "re-scope passed"; else
  grep -q "re-scoped bank case (judgment fields changed) 'a1'" "$WORK/err.log" && ok || bad "re-scope red but not attributed"
fi

# Leg 4: deleting the SUBDIRECTORY golden trace reds (recursive base walk).
reset_tree
rm "$REPO/eval/golden-traces/nested/t1.json"
if run_gate; then bad "nested trace deletion passed"; else
  grep -q "deleted golden trace 'trace-nested-one'" "$WORK/err.log" && ok || bad "trace deletion red but not attributed"
fi

# Leg 5: a prefix-colliding id mints no credit (case-retired: a1x != a1).
reset_tree
grep -v '"id": "a1",' "$BANK" > "$BANK.t" && mv "$BANK.t" "$BANK"
printf '| retired | case-retired: a1x | reason |\n' >> "$REG"
if run_gate; then bad "prefix-colliding adjudication credited"; else
  grep -q "deleted bank case 'a1'" "$WORK/err.log" && ok || bad "prefix leg red but not attributed"
fi

# Leg 6: an HTML comment mints no credit (row-only surface).
reset_tree
grep -v '"id": "a1",' "$BANK" > "$BANK.t" && mv "$BANK.t" "$BANK"
printf '<!-- case-retired: a1 -->\n' >> "$REG"
if run_gate; then bad "HTML-comment adjudication credited"; else
  grep -q "deleted bank case 'a1'" "$WORK/err.log" && ok || bad "comment leg red but not attributed"
fi

# Leg 7: a real added table row with the exact id is credited — green.
reset_tree
grep -v '"id": "a1",' "$BANK" > "$BANK.t" && mv "$BANK.t" "$BANK"
printf '| retired | case-retired: a1 | superseded by a2 probes |\n' >> "$REG"
if run_gate && grep -q "frozen_case_sanctity_ok" "$WORK/out.log"; then ok; else bad "adjudicated deletion not green"; fi

# Leg 8: no base ref prints the explicit skip token and exits 0. env -u so an
# outer CI-supplied CCL_SKILL_BASE_REF cannot leak into this leg (the known
# nested-suite leak class).
reset_tree
if env -u CCL_SKILL_BASE_REF SANCTITY_ROOT="$REPO" bash "$GATE" > "$WORK/out.log" 2>&1 && grep -q "frozen_case_sanctity_skipped no-base-ref" "$WORK/out.log"; then ok; else bad "no-base leg missing skip token"; fi

echo "frozen_case_sanctity_selfproof: pass=$pass fail=$fail"
[ "$fail" -eq 0 ] && [ "$pass" -eq 8 ] || exit 1
echo "frozen_case_sanctity_selfproof_ok"
