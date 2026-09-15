#!/usr/bin/env bash
# Regression for the extraction review wrapper: every call is one single-shot
# pass, and no caller option can reopen a tracked review chain.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd -P)"
WRAPPER="$SCRIPT_DIR/extraction_review_gate.sh"
REAL_CONTROLLER="$SCRIPT_DIR/../../code-review/scripts/review_gate.sh"
ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd -P)"
[ -x "$WRAPPER" ] || { echo "FAIL: wrapper missing or not executable: $WRAPPER" >&2; exit 1; }
[ -x "$REAL_CONTROLLER" ] || { echo "FAIL: real controller missing or not executable: $REAL_CONTROLLER" >&2; exit 1; }

TMP="$(mktemp -d "${TMPDIR:-/tmp}/extraction-review-gate.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

fail() { echo "FAIL: $*" >&2; exit 1; }
assert_rc() { [ "$1" = "$2" ] || fail "expected rc=$2 got rc=$1 ($3)"; }
assert_contains() { case "$2" in *"$1"*) : ;; *) fail "expected '$1' ($3): $2";; esac; }
assert_not_contains() { case "$2" in *"$1"*) fail "unexpected '$1' ($3): $2";; *) : ;; esac; }

# A fake controller that records its argv, so the fixed options are observable.
mkdir -p "$TMP/skills/skill-extraction-workflow/scripts" "$TMP/skills/code-review/scripts"
FAKE_WRAPPER="$TMP/skills/skill-extraction-workflow/scripts/extraction_review_gate.sh"
cp "$WRAPPER" "$FAKE_WRAPPER"
printf '%s\n' \
  '#!/usr/bin/env bash' \
  'printf '\''%s\0'\'' "$@" >"$CAPTURE_PATH"' \
  'exit "${FAKE_RC:-0}"' >"$TMP/skills/code-review/scripts/review_gate.sh"
chmod +x "$FAKE_WRAPPER" "$TMP/skills/code-review/scripts/review_gate.sh"

captured() {
  python3 - "$TMP/args" <<'PY'
import sys
from pathlib import Path
print(" ".join(i.decode() for i in Path(sys.argv[1]).read_bytes().split(b"\0") if i))
PY
}

CAPTURE_PATH="$TMP/args" "$FAKE_WRAPPER" --mode review --cwd /synthetic --implementer-family openai
assert_contains "--challenge-budget 0 --mode review" "$(captured)" "review is single-shot with no challenge capacity"
assert_contains "--review-lane extraction" "$(captured)" "wrapper selects its owner lane"

CAPTURE_PATH="$TMP/args" "$FAKE_WRAPPER" --mode challenge --cwd /synthetic --implementer-family openai --focus f
assert_contains "--challenge-budget 1 --challenge-index 1 --mode challenge" "$(captured)" "challenge is the single untracked challenge"

CAPTURE_PATH="$TMP/args" "$FAKE_WRAPPER" --mode=challenge --cwd /synthetic --focus f
assert_contains "--challenge-budget 1 --challenge-index 1 --mode=challenge" "$(captured)" "--mode=VALUE spelling"

# Missing or unsupported modes fail closed before the controller runs.
for bad in "" "--mode complete" "--mode=complete" "--mo challenge"; do
  : >"$TMP/args"
  set +e
  # shellcheck disable=SC2086
  out="$(CAPTURE_PATH="$TMP/args" "$FAKE_WRAPPER" $bad --cwd /synthetic 2>&1)"
  rc=$?
  set -e
  assert_rc "$rc" 2 "mode '$bad' must be refused"
  assert_contains "extraction_review_gate_error" "$out" "mode '$bad' reason"
  [ ! -s "$TMP/args" ] || fail "controller ran for mode '$bad'"
done

# Every chain option, full or abbreviated, with or without =VALUE, is refused.
for spelling in \
  --review-chain-id --review-chain-id=x --review-c \
  --review-lane --review-lane=staged --review-l \
  --autonomous-review-index --autonomous-review-index=2 --au \
  --prior-review-result-file --prior-review-result-file=/r.json --prio \
  --predecessor-chain-result-file --pre \
  --completion-review-result-file --com \
  --challenge-budget --challenge-budget=4 --challenge-b=4 \
  --challenge-index --challenge-index=2 --challenge-i; do
  : >"$TMP/args"
  set +e
  out="$(CAPTURE_PATH="$TMP/args" "$FAKE_WRAPPER" --mode challenge --focus f "$spelling" 1 2>&1)"
  rc=$?
  set -e
  assert_rc "$rc" 2 "chain option $spelling must be refused"
  assert_contains "extraction_review_gate_error" "$out" "$spelling reason"
  [ ! -s "$TMP/args" ] || fail "controller ran after $spelling"
done

set +e
CAPTURE_PATH="$TMP/args" FAKE_RC=7 "$FAKE_WRAPPER" --mode review --cwd /synthetic >/dev/null 2>&1
rc=$?
set -e
assert_rc "$rc" 7 "wrapper must preserve controller exit status"

mv "$TMP/skills/code-review/scripts/review_gate.sh" "$TMP/controller-away"
set +e
out="$(CAPTURE_PATH="$TMP/args" "$FAKE_WRAPPER" --mode review --cwd /synthetic 2>&1)"
rc=$?
set -e
assert_rc "$rc" 2 "missing controller must fail closed"
assert_contains "controller is unavailable" "$out" "missing-controller reason"

# The real controller must accept both single-shot shapes without a chain id.
# The implementer is OpenAI-family and the only client offered is Codex, so the
# controller must refuse it as same-family and stop before any model inference.
python3 - "$TMP/real.diff" "$TMP/real-plan.json" "$ROOT" <<'PY'
import json
import subprocess
import sys
from pathlib import Path

diff_path, plan_path = map(Path, sys.argv[1:3])
root = Path(sys.argv[3])
diff_path.write_text(
    "diff --git a/skills/skill-extraction-workflow/scripts/extraction_review_gate.sh "
    "b/skills/skill-extraction-workflow/scripts/extraction_review_gate.sh\n"
    "--- a/skills/skill-extraction-workflow/scripts/extraction_review_gate.sh\n"
    "+++ b/skills/skill-extraction-workflow/scripts/extraction_review_gate.sh\n"
    "@@ -1 +1 @@\n-old wrapper\n+new wrapper\n",
    encoding="utf-8",
)
# The required concern set has one owner, the controller; derive it rather than
# keeping a copy that drifts when the set changes.
required = subprocess.run(
    [sys.executable, str(root / "skills/code-review/scripts/review_gate.py"),
     "--print-required-concerns", "--stage", "release", "--risk-tag", "shared-gate"],
    capture_output=True, text=True, check=True,
).stdout.split()
assert required, "the controller printed no required concerns"
owners = ["skill-extraction-workflow", "code-review", "python-service-dev",
          "testing-strategy", "terminal-cli-dev"]
rows = [
    {"concern": c, "skill": owners[i % len(owners)],
     "conclusion": f"The single-shot wrapper probe covers {c} within its fixture.",
     "evidence_refs": ["wrapper-probe"]}
    for i, c in enumerate(required)
]
covered = {r["skill"] for r in rows}
rows += [
    {"concern": required[0], "skill": o,
     "conclusion": f"{o} is covered for {required[0]} by the same probe.",
     "evidence_refs": ["wrapper-probe"]}
    for o in owners if o not in covered
]
plan_path.write_text(json.dumps({
    "intent": "Prove the extraction wrapper drives the real controller single-shot.",
    "acceptance": ["Both passes reach the reviewer-selection boundary untracked."],
    "self_review": rows,
    "evidence": [{"id": "wrapper-probe", "result": "The real controller is invoked through the wrapper."}],
}, indent=2) + "\n", encoding="utf-8")
PY

mkdir -p "$TMP/fake-bin"
printf '%s\n' '#!/usr/bin/env bash' 'printf invoked >"$CODEX_MARKER"' 'exit 99' >"$TMP/fake-bin/codex"
chmod +x "$TMP/fake-bin/codex"
run_real_controller() {
  CODEX_MARKER="$TMP/codex-invoked" PATH="$TMP/fake-bin:$PATH" CODE_REVIEW_CLIENT_ORDER=codex \
    "$REAL_CONTROLLER" "$@"
}
real_args=(
  --cwd "$ROOT" --diff-file "$TMP/real.diff" --implementer-family openai
  --review-plan-file "$TMP/real-plan.json" --review-harness
  --timeout 5 --total-timeout 5
)
for profile in build release shared-gate; do
  risk_args=(--stage "$profile")
  [ "$profile" = shared-gate ] && risk_args=(--stage build --risk-tag shared-gate)
  for pass in review challenge; do
  extra=()
  [ "$pass" = challenge ] && extra=(--focus "single-shot probe")
  set +e
  out="$(CODEX_MARKER="$TMP/codex-invoked" PATH="$TMP/fake-bin:$PATH" CODE_REVIEW_CLIENT_ORDER=codex \
    "$WRAPPER" --mode "$pass" "${real_args[@]}" "${risk_args[@]}" "${extra[@]}" 2>&1)"
  rc=$?
  set -e
  assert_rc "$rc" 2 "real $profile $pass must stop before model inference: $out"
  assert_contains '"reason_code":"no_independent_reviewer_available"' "$out" "real $pass reaches reviewer selection"
  assert_not_contains 'review_chain_required' "$out" "real $pass needs no chain"
  assert_not_contains 'review_chain_invalid' "$out" "real $pass needs no chain"
  assert_contains '"review_lane":"extraction"' "$out" "$profile $pass binds the extraction lane"
  done
  if [ "$profile" != build ]; then
    set +e
    out="$(run_real_controller --mode review --challenge-budget 0 "${real_args[@]}" "${risk_args[@]}" 2>&1)"
    rc=$?
    set -e
    assert_rc "$rc" 2 "staged $profile review still requires challenge capacity"
    assert_contains 'release and high-risk review require at least one challenge' "$out" "staged risk guard remains active"
  fi
done

# The explicit owner lane must never turn into a chain or claim completion.
for incompatible in '--review-chain-id probe' '--challenge-budget 1' '--wording-only-proof-file /missing'; do
  set +e
  # shellcheck disable=SC2086
  out="$(run_real_controller --review-lane extraction --mode review --challenge-budget 0 \
    "${real_args[@]}" --stage release $incompatible 2>&1)"
  rc=$?
  set -e
  assert_rc "$rc" 2 "extraction rejects $incompatible"
  assert_contains 'extraction runs separate single-shot review and challenge passes' "$out" "extraction configuration fails closed"
done
[ ! -e "$TMP/codex-invoked" ] || fail "same-family Codex executable was invoked"

# Declaring the extraction owner in the plan cannot route an ordinary candidate
# around staged high-risk requirements. The real candidate must derive the owner.
sed 's@skills/skill-extraction-workflow/scripts/extraction_review_gate.sh@src/example.py@g' \
  "$TMP/real.diff" >"$TMP/ordinary.diff"
for pass in review challenge; do
  extra=(--challenge-budget 0)
  [ "$pass" = challenge ] && extra=(--challenge-budget 1 --focus "ordinary candidate")
  set +e
  out="$(run_real_controller "${real_args[@]}" --diff-file "$TMP/ordinary.diff" \
    --review-lane extraction --mode "$pass" --stage release "${extra[@]}" 2>&1)"
  rc=$?
  set -e
  assert_rc "$rc" 2 "ordinary candidate cannot use extraction $pass"
  assert_contains 'extraction lane requires controller-derived skill-extraction-workflow ownership' "$out" "candidate ownership is required"
done
set +e
out="$(run_real_controller "${real_args[@]}" --diff-file "$TMP/ordinary.diff" --mode review --stage build 2>&1)"
rc=$?
set -e
assert_rc "$rc" 2 "ordinary staged review reaches reviewer selection"
assert_contains '"reason_code":"no_independent_reviewer_available"' "$out" "ordinary staged scope stays valid"
[ ! -e "$TMP/codex-invoked" ] || fail "same-family Codex executable was invoked"

# The owner documents must route non-wording work through this wrapper and must
# no longer send anyone to the retired chain ledger or merge-side binder.
python3 - "$ROOT" <<'PY'
import re
import sys
from pathlib import Path

root = Path(sys.argv[1])
ref = root / "skills/skill-extraction-workflow"
docs = {
    "SKILL": (ref / "SKILL.md").read_text(encoding="utf-8"),
    "quickstart": (ref / "references/extraction-quickstart.md").read_text(encoding="utf-8"),
    "dual-track": (ref / "references/dual-track-review-gate.md").read_text(encoding="utf-8"),
    "validation-and-landing": (ref / "references/validation-and-landing.md").read_text(encoding="utf-8"),
}
for label, text in docs.items():
    assert "scripts/extraction_review_gate.sh" in text, f"{label} does not route through the wrapper"
    for retired in ("validate_extraction_review_state.py", "review_ledger_binding.py",
                    "challenge_budget=1", "succession challenge"):
        assert retired not in text, f"{label} still points at the retired {retired}"
assert re.search(r"[Nn]on-wording.{0,240}scripts/extraction_review_gate\.sh",
                 docs["SKILL"], re.DOTALL), "SKILL does not scope the wrapper to non-wording work"
assert re.search(r"[Ww]ording-only.{0,500}(?:single|one)[- ](?:round|review|pass)",
                 docs["quickstart"], re.DOTALL), "quickstart lost the wording-only single-review exception"
assert "--challenge-budget" not in docs["quickstart"], "quickstart must not hand callers the budget flag"
dual = docs["dual-track"]
for pinned in ("post-review delta", "Every post-review delta gets a delta pass", "never left to a human reader"):
    assert pinned in dual, f"dual-track lost '{pinned}'"
# The sixth necessary review inherits task authority. A convergence checkpoint
# must not become a fresh permission request, or override an explicit user limit.
completion = (root / "skills/code-review/references/development-completion.md").read_text(encoding="utf-8")
checkpoint = "#review-continuation-checkpoint"
assert checkpoint in dual, "extraction must use the canonical review continuation checkpoint"
assert "Unresolved P0/P1 or an unreviewed delta still blocks readiness" in dual, "extraction must keep unresolved findings and unreviewed changes pending"
assert "review continuation checkpoint" in docs["SKILL"], "entrypoint must route the continuation decision"
assert "review continuation checkpoint" in docs["quickstart"], "quickstart must route the continuation decision"
for label, text in {"completion": completion, **docs}.items():
    for retired in ("Renewed runs stop at five", "After five delta passes a still-open", "delta pass (at most five)", "delta only (at most five"):
        assert retired not in text, f"{label} restores a task-wide review permission ceiling"
for obligation in (
    "Five renewed runs trigger a progress checkpoint, not an authorization request",
    "Necessary in-scope review inherits the existing task authority",
    "explicit user stop, count, cost or time limit",
    "host permission denial",
    "change the method or gather different evidence",
    "tracked chain's own round ceiling",
    "never reset an unchanged candidate's chain merely to obtain zero findings",
    "A missing conclusive pass or unresolved P0/P1 remains pending",
):
    assert obligation in completion, f"review continuation lost '{obligation}'"
wording_only = (root / "skills/code-review/references/wording-only-review.md").read_text(encoding="utf-8")
assert "--wording-only-proof-file" in wording_only
assert "--challenge-budget 0" in wording_only
PY

echo "test_extraction_review_gate: ok"
