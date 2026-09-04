#!/usr/bin/env bash
# Regression test for the bank runner's screening-vs-action resolution signal.
#
# A report taken below the action floor locates candidates; it does not license
# a description edit. The runner says so on stdout and in the JSON report, and
# this test pins BOTH sides of the number — the reference that states the rule
# and the executable that enforces it — so they cannot drift apart the way the
# description-length thresholds once did.
#
# Uses a fake `claude` earlier in PATH: never invokes a real CLI or account.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd -P)"
EVAL_SCRIPT="$SCRIPT_DIR/eval-routing-bank.rb"
DOC="$SCRIPT_DIR/../references/eval-routing.md"
[ -f "$EVAL_SCRIPT" ] || { echo "FAIL: eval script not found: $EVAL_SCRIPT" >&2; exit 1; }
[ -f "$DOC" ] || { echo "FAIL: reference not found: $DOC" >&2; exit 1; }

fail() { echo "FAIL: $*" >&2; exit 1; }
assert_contains() { case "$2" in *"$1"*) : ;; *) fail "expected output to contain: $1${3:+ ($3)}";; esac; }
assert_absent() { case "$2" in *"$1"*) fail "expected output NOT to contain: $1${3:+ ($3)}";; *) : ;; esac; }

TMP="$(mktemp -d "${TMPDIR:-/tmp}/eval-routing-bank-resolution.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

REPO="$TMP/repo"
FAKE_BIN="$TMP/bin"
mkdir -p "$REPO/skills/testing-strategy" "$REPO/skills/tighten-doc" "$REPO/eval" "$FAKE_BIN"

git -C "$TMP" init -q repo
git -C "$REPO" config user.email test@example.invalid
git -C "$REPO" config user.name "Test User"

cat > "$REPO/skills/testing-strategy/SKILL.md" <<'EOF'
---
description: Use when choosing test layers and regression evidence.
---
# Testing Strategy
EOF

# Keeps the outcome space larger than {expected, none} so the fixture is not
# vacuous: a grader that always answered the only skill would pass trivially.
cat > "$REPO/skills/tighten-doc/SKILL.md" <<'EOF'
---
description: Use when polishing document wording.
---
# Tighten Doc
EOF

cat > "$REPO/eval/routing-tasks.jsonl" <<'EOF'
{"id":"resolution-fixture","utterance":"补一个回归测试","expected_skill":"testing-strategy","frozen_at_sha":""}
EOF

git -C "$REPO" add -A
git -C "$REPO" commit -qm "fixture"

cat > "$FAKE_BIN/claude" <<'EOF'
#!/usr/bin/env bash
cat >/dev/null
printf '{"selected_skill":"testing-strategy","clarify":false,"confidence":0.9,"rationale_short":"fixture"}\n'
EOF
chmod +x "$FAKE_BIN/claude"
export PATH="$FAKE_BIN:$PATH"

# --- (1) below the floor: banner printed, report says action_resolution false --
out_lo="$(ruby "$EVAL_SCRIPT" "$REPO" --replicas 3 --json "$TMP/lo.json" 2>&1)" \
  || fail "runner exited non-zero below the floor:\n$out_lo"
assert_contains "screening_resolution_only" "$out_lo" "sub-floor run must announce screening resolution"
assert_contains "replicas=3" "$out_lo" "banner must name the observed replica count"
assert_contains "floor 10" "$out_lo" "banner must name the required floor"
assert_contains "valid observations" "$out_lo" "banner must report the weakest task's valid-observation count, not the request alone"
grep -q '"action_resolution": false' "$TMP/lo.json" \
  || fail "sub-floor report must carry action_resolution:false — a consumer cannot read a printed banner"

# --- (2) at the floor: no banner, report says action_resolution true -----------
out_hi="$(ruby "$EVAL_SCRIPT" "$REPO" --replicas 10 --json "$TMP/hi.json" 2>&1)" \
  || fail "runner exited non-zero at the floor:\n$out_hi"
assert_absent "screening_resolution_only" "$out_hi" "a run at the floor must not be labelled screening-only"
grep -q '"action_resolution": true' "$TMP/hi.json" \
  || fail "at-floor report must carry action_resolution:true"

# --- (2b) a nominal at-floor run with an invalid observation is NOT actionable -
# The floor is on valid observations. A grader that fails one call leaves the
# task below the floor while `--replicas` still reads 10, and a report that
# trusted the request would license an edit its evidence cannot support.
# The runner gives each unparsable verdict ONE retry, treating it as a sampling
# accident, so a fixture that fails a single call is repaired and records no
# error. The failure has to persist across the retry to leave the task short of
# the floor -- which is exactly the real shape this guards: a grader that is
# reliably unable to answer one utterance, not a stray quote.
cat > "$FAKE_BIN/claude" <<'EOF'
#!/usr/bin/env bash
cat >/dev/null
echo x >> "$RESOLUTION_COUNT_FILE"
n=$(wc -l < "$RESOLUTION_COUNT_FILE" | tr -d ' ')
if [ "$n" = "3" ] || [ "$n" = "4" ]; then printf 'not json at all\n'; exit 0; fi
printf '{"selected_skill":"testing-strategy","clarify":false,"confidence":0.9,"rationale_short":"fixture"}\n'
EOF
chmod +x "$FAKE_BIN/claude"
: > "$TMP/count"
out_deg="$(RESOLUTION_COUNT_FILE="$TMP/count" ruby "$EVAL_SCRIPT" "$REPO" --replicas 10 --json "$TMP/deg.json" 2>&1)" \
  || fail "runner exited non-zero on the degraded run:\n$out_deg"
assert_contains "screening_resolution_only" "$out_deg" "a nominal 10-replica run with an invalid observation must not be actionable"
grep -q '"action_resolution": false' "$TMP/deg.json" \
  || fail "a 10-replica run with only 9 valid observations must report action_resolution:false"
grep -q '"min_valid_observations": 9' "$TMP/deg.json" \
  || fail "the report must expose the weakest task's valid-observation count"

# --- (2c) the verdict is per case, and says nothing about a case not measured --
# A report-wide boolean alone is unsound in the licensing direction: a subset run
# over one case would otherwise read as licence for an edit to a case the run
# never graded. Each result carries its own actionable and valid_observations.
grep -q '"actionable": true' "$TMP/hi.json" \
  || fail "an at-floor case must carry its own actionable:true"
grep -q '"valid_observations": 10' "$TMP/hi.json" \
  || fail "each case must expose its own valid-observation count"
grep -q '"action_resolution_scope"' "$TMP/hi.json" \
  || fail "the report must say its top-level verdict covers only the cases it measured"
grep -q '"actionable": false' "$TMP/deg.json" \
  || fail "a case left short by an invalid observation must carry actionable:false"

# --- (3) the two sides of the number must agree -------------------------------
# The rule is only as good as the agreement between the reference that states it
# and the executable that enforces it. Compare the numbers themselves rather
# than pinning one literal in two places.
exe_min="$(grep -oE 'ACTION_RESOLUTION_MIN_REPLICAS = [0-9]+' "$EVAL_SCRIPT" | grep -oE '[0-9]+$' | sort -u)"
[ -n "$exe_min" ] || fail "could not read ACTION_RESOLUTION_MIN_REPLICAS from $EVAL_SCRIPT"
[ "$(printf '%s\n' "$exe_min" | wc -l | tr -d ' ')" = "1" ] \
  || fail "ACTION_RESOLUTION_MIN_REPLICAS is defined with more than one value: $exe_min"
doc_min="$(grep -oE 'replicas < [0-9]+' "$DOC" | grep -oE '[0-9]+$' | sort -u)"
[ -n "$doc_min" ] || fail "$DOC does not state the replicas floor as \`replicas < N\`"
[ "$doc_min" = "$exe_min" ] \
  || fail "doc states floor $doc_min but the runner enforces $exe_min — they must be one number"

# The prose obligation (">=N valid observations before acting") must name the
# same number too, so a reader following the sentence and a consumer reading the
# report are held to one bar.
grep -qF "≥${exe_min} 个有效观测" "$DOC" \
  || fail "$DOC must state the per-case obligation with the same floor (≥${exe_min} 个有效观测)"

echo "PASS: eval-routing-bank resolution signal (banner, report field, doc/executor agreement)"
