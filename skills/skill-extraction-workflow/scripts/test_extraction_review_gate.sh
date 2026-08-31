#!/usr/bin/env bash
# Regression for the extraction-specific autonomous review budget wrapper.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd -P)"
WRAPPER="$SCRIPT_DIR/extraction_review_gate.sh"
REAL_CONTROLLER="$SCRIPT_DIR/../../code-review/scripts/review_gate.sh"
REAL_VALIDATOR="$SCRIPT_DIR/validate_extraction_review_state.py"
ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd -P)"
[ -x "$WRAPPER" ] || { echo "FAIL: wrapper missing or not executable: $WRAPPER" >&2; exit 1; }
[ -x "$REAL_CONTROLLER" ] || { echo "FAIL: real controller missing or not executable: $REAL_CONTROLLER" >&2; exit 1; }
[ -f "$REAL_VALIDATOR" ] || { echo "FAIL: real validator missing: $REAL_VALIDATOR" >&2; exit 1; }

TMP="$(mktemp -d "${TMPDIR:-/tmp}/extraction-review-gate.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

fail() { echo "FAIL: $*" >&2; exit 1; }
assert_rc() { [ "$1" = "$2" ] || fail "expected rc=$2 got rc=$1 ($3)"; }
assert_contains() { case "$2" in *"$1"*) : ;; *) fail "expected '$1' ($3): $2";; esac; }

mkdir -p "$TMP/skills/skill-extraction-workflow/scripts" "$TMP/skills/code-review/scripts"
cp "$WRAPPER" "$TMP/skills/skill-extraction-workflow/scripts/extraction_review_gate.sh"
printf '%s\n' \
  '#!/usr/bin/env bash' \
  'printf '\''%s\0'\'' "$@" >"$CAPTURE_PATH"' \
  'exit "${FAKE_RC:-0}"' >"$TMP/skills/code-review/scripts/review_gate.sh"
chmod +x "$TMP/skills/skill-extraction-workflow/scripts/extraction_review_gate.sh" "$TMP/skills/code-review/scripts/review_gate.sh"

CAPTURE_PATH="$TMP/args" "$TMP/skills/skill-extraction-workflow/scripts/extraction_review_gate.sh" \
  --mode review --cwd /synthetic --base base --implementer-family openai
python3 - "$TMP/args" <<'PY'
import sys
from pathlib import Path

args = [item.decode() for item in Path(sys.argv[1]).read_bytes().split(b"\0") if item]
assert args[:2] == ["--challenge-budget", "1"], args
assert args.count("--challenge-budget") == 1, args
PY

# A caller option with a missing operand must not consume the wrapper-owned
# budget flag. The real controller will reject the missing operand, but only
# after seeing the fixed extraction budget as its own option/value pair.
CAPTURE_PATH="$TMP/args" "$TMP/skills/skill-extraction-workflow/scripts/extraction_review_gate.sh" \
  --mode review --cwd /synthetic --implementer-family openai --base
python3 - "$TMP/args" <<'PY'
import sys
from pathlib import Path

args = [item.decode() for item in Path(sys.argv[1]).read_bytes().split(b"\0") if item]
assert args[:2] == ["--challenge-budget", "1"], args
assert args[-1] == "--base", args
assert args.count("--challenge-budget") == 1, args
PY

# Exercise the installed wrapper/controller pair without invoking a model. The
# same real controller defaults to budget 0 when called directly, while the
# extraction wrapper must make the emitted receipt report budget 1.
python3 - "$TMP/real-controller.diff" "$TMP/real-controller-plan.json" <<'PY'
import json
import sys
from pathlib import Path

diff_path, plan_path = map(Path, sys.argv[1:])
diff_path.write_text(
    "diff --git a/skills/skill-extraction-workflow/scripts/extraction_review_gate.sh "
    "b/skills/skill-extraction-workflow/scripts/extraction_review_gate.sh\n"
    "--- a/skills/skill-extraction-workflow/scripts/extraction_review_gate.sh\n"
    "+++ b/skills/skill-extraction-workflow/scripts/extraction_review_gate.sh\n"
    "@@ -1 +1 @@\n-old wrapper\n+new wrapper\n",
    encoding="utf-8",
)
conclusions = {
    "correctness": "The real controller receipt exposes the effective extraction budget.",
    "safety": "The probe selects only the implementer family and invokes no external reviewer.",
    "failure_paths": "The no-independent-reviewer boundary remains structured and fail closed.",
    "tests_evidence": "Direct and wrapped calls provide a differential budget assertion.",
    "compatibility": "The generic controller default remains zero while extraction fixes one.",
}
skills = {
    "correctness": "skill-extraction-workflow",
    "safety": "code-review",
    "failure_paths": "python-service-dev",
    "tests_evidence": "testing-strategy",
    "compatibility": "terminal-cli-dev",
}
plan = {
    "intent": "Prove the extraction wrapper and real review controller agree on budget one.",
    "acceptance": ["The wrapped real-controller receipt reports challenge_budget one."],
    "self_review": [
        {
            "concern": concern,
            "skill": skills[concern],
            "conclusion": conclusion,
            "evidence_refs": ["real-controller-differential"],
        }
        for concern, conclusion in conclusions.items()
    ],
    "evidence": [
        {
            "id": "real-controller-differential",
            "result": "The same real controller is invoked directly and through the extraction wrapper.",
        }
    ],
}
plan_path.write_text(json.dumps(plan, indent=2) + "\n", encoding="utf-8")
PY

real_args=(
  --mode review --cwd "$ROOT" --diff-file "$TMP/real-controller.diff"
  --implementer-family openai --review-plan-file "$TMP/real-controller-plan.json"
  --stage build --review-harness --timeout 5 --total-timeout 5
)
# Make a Codex executable visibly available, independent of whichever CLI
# version the host carries. Because the implementer is OpenAI-family, the real
# controller must reject Codex as same-family before probing or invoking it.
mkdir -p "$TMP/fake-bin"
printf '%s\n' \
  '#!/usr/bin/env bash' \
  'printf invoked >"$CODEX_MARKER"' \
  'exit 99' >"$TMP/fake-bin/codex"
chmod +x "$TMP/fake-bin/codex"
set +e
direct_out="$(CODEX_MARKER="$TMP/codex-invoked" PATH="$TMP/fake-bin:$PATH" \
  CODE_REVIEW_CLIENT_ORDER=codex bash "$REAL_CONTROLLER" "${real_args[@]}" 2>&1)"
direct_rc=$?
wrapped_out="$(CODEX_MARKER="$TMP/codex-invoked" PATH="$TMP/fake-bin:$PATH" \
  CODE_REVIEW_CLIENT_ORDER=codex "$WRAPPER" "${real_args[@]}" \
  --review-chain-id extraction-wrapper-real-controller \
  --autonomous-review-index 1 2>&1)"
wrapped_rc=$?
set -e
assert_rc "$direct_rc" 2 "direct real controller must stop before model inference"
assert_rc "$wrapped_rc" 2 "wrapped real controller must stop before model inference"
assert_contains '"reason_code":"no_independent_reviewer_available"' "$direct_out" "direct real-controller boundary"
assert_contains '"reason_code":"no_independent_reviewer_available"' "$wrapped_out" "wrapped real-controller boundary"
assert_contains '"challenge_budget":0' "$direct_out" "generic controller default budget"
assert_contains '"challenge_budget":1' "$wrapped_out" "wrapper-enforced real-controller budget"
[ ! -e "$TMP/codex-invoked" ] || fail "same-family Codex executable was invoked"

# Join the producer and consumer contracts. First feed the exact real receipt
# to the validator and reach its semantic status boundary. Then normalize only
# the terminal disposition fields so validation must walk the producer's real
# chain/scope shape before stopping at the intentionally omitted base evidence.
printf '%s\n' "$wrapped_out" >"$TMP/wrapped-real-controller.out"
python3 - "$TMP/wrapped-real-controller.out" "$TMP" <<'PY'
import copy
import hashlib
import json
import sys
from pathlib import Path

output_path = Path(sys.argv[1])
root = Path(sys.argv[2])
receipt = None
for line in reversed(output_path.read_text(encoding="utf-8").splitlines()):
    try:
        value = json.loads(line)
    except json.JSONDecodeError:
        continue
    if isinstance(value, dict) and value.get("schema_version") == 3:
        receipt = value
        break
assert receipt is not None


def write_receipt_and_ledger(stem, value, controller_state):
    encoded = (json.dumps(value, ensure_ascii=False, indent=2) + "\n").encode()
    receipt_name = f"{stem}-receipt.json"
    (root / receipt_name).write_bytes(encoded)
    digest = hashlib.sha256(encoded).hexdigest()
    ledger = {
        "schema_version": 3,
        "candidate_sha256": value["candidate_sha256"],
        "controller_receipts": [
            {"sequence": 1, "file": receipt_name, "sha256": digest}
        ],
        "completion_receipt": None,
        "base_attestations": [],
        "autonomous_round": 1,
        "controller_review_state": controller_state,
        "finding_classes": [],
        "unreviewed_delta": [],
        "closeout_state": "ready_for_human_decision",
    }
    (root / f"{stem}-ledger.json").write_text(
        json.dumps(ledger, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )


write_receipt_and_ledger("real-emitted", receipt, receipt.get("review_state", "inconclusive"))
normalized = copy.deepcopy(receipt)
scope_before = json.dumps(normalized["review_scope"], sort_keys=True)
normalized.update(
    status="passed",
    findings=[],
    review_state="reviewed",
    human_decision_required=False,
)
assert json.dumps(normalized["review_scope"], sort_keys=True) == scope_before
write_receipt_and_ledger("real-scope", normalized, "reviewed")
PY

set +e
emitted_state_out="$(python3 "$REAL_VALIDATOR" "$TMP/real-emitted-ledger.json" 2>&1)"
emitted_state_rc=$?
scope_state_out="$(python3 "$REAL_VALIDATOR" "$TMP/real-scope-ledger.json" 2>&1)"
scope_state_rc=$?
set -e
assert_rc "$emitted_state_rc" 1 "exact real receipt reaches semantic status validation"
assert_contains "must have status passed or findings" "$emitted_state_out" "exact real receipt semantic boundary"
assert_rc "$scope_state_rc" 1 "producer-derived receipt reaches post-scope validation"
assert_contains "base_attestations must be a non-empty array" "$scope_state_out" "real producer scope shape"

# Shorter spellings that do not start with --challenge-b are ambiguous among
# the controller's budget/index/classes options, so they fail closed instead of
# becoming a hidden budget override.
for abbreviated in --challeng --challenge=4; do
  set +e
  out="$(CODE_REVIEW_CLIENT_ORDER=codex "$WRAPPER" "${real_args[@]}" "$abbreviated" 4 2>&1)"
  rc=$?
  set -e
  assert_rc "$rc" 2 "ambiguous budget abbreviation must fail closed"
  assert_contains "ambiguous option" "$out" "ambiguous abbreviation reason"
done

for spelling in --challenge-budget --challenge-budget=4 --challenge-b=4; do
  : >"$TMP/args"
  set +e
  out="$(CAPTURE_PATH="$TMP/args" "$TMP/skills/skill-extraction-workflow/scripts/extraction_review_gate.sh" "$spelling" 4 2>&1)"
  rc=$?
  set -e
  assert_rc "$rc" 2 "caller budget override must be rejected"
  assert_contains "challenge budget is fixed at 1" "$out" "override reason"
  [ ! -s "$TMP/args" ] || fail "controller ran after budget override"
done

set +e
CAPTURE_PATH="$TMP/args" FAKE_RC=7 "$TMP/skills/skill-extraction-workflow/scripts/extraction_review_gate.sh" \
  --mode review --cwd /synthetic --base base --implementer-family openai >/dev/null 2>&1
rc=$?
set -e
assert_rc "$rc" 7 "wrapper must preserve controller exit status"

mv "$TMP/skills/code-review/scripts/review_gate.sh" "$TMP/controller-away"
set +e
out="$(CAPTURE_PATH="$TMP/args" "$TMP/skills/skill-extraction-workflow/scripts/extraction_review_gate.sh" \
  --mode review --cwd /synthetic --base base --implementer-family openai 2>&1)"
rc=$?
set -e
assert_rc "$rc" 2 "missing controller must fail closed"
assert_contains "controller is unavailable" "$out" "missing-controller reason"

# The owner-facing start-here documents must route non-wording extraction work
# through the fixed-budget wrapper and its terminal validator.  Strict
# wording-only changes retain the documented single-review exception; they must
# not be accidentally pulled into the multi-round ledger contract.
python3 - "$ROOT" <<'PY'
import re
import sys
from pathlib import Path

root = Path(sys.argv[1])
skill = (root / "skills/skill-extraction-workflow/SKILL.md").read_text(encoding="utf-8")
quickstart = (
    root / "skills/skill-extraction-workflow/references/extraction-quickstart.md"
).read_text(encoding="utf-8")
dual = (
    root / "skills/skill-extraction-workflow/references/dual-track-review-gate.md"
).read_text(encoding="utf-8")
landing = (
    root / "skills/skill-extraction-workflow/references/validation-and-landing.md"
).read_text(encoding="utf-8")
staged = (
    root / "skills/code-review/references/staged-review-contract.md"
).read_text(encoding="utf-8")
code_review = (root / "skills/code-review/SKILL.md").read_text(encoding="utf-8")

for label, text in {
    "SKILL": skill,
    "quickstart": quickstart,
    "dual-track": dual,
    "validation-and-landing": landing,
}.items():
    assert "scripts/extraction_review_gate.sh" in text, (
        f"{label} does not route the non-wording lane through the owner wrapper"
    )

for label, text in {"quickstart": quickstart, "dual-track": dual}.items():
    assert "scripts/validate_extraction_review_state.py <closeout.json>" in text, (
        f"{label} omits the terminal closeout validator"
    )

assert re.search(
    r"[Nn]on-wording.{0,240}scripts/extraction_review_gate\.sh",
    skill,
    re.DOTALL,
), "SKILL does not scope the fixed-budget wrapper to non-wording changes"
assert re.search(
    r"[Ww]ording-only.{0,500}(?:single|one)[- ](?:round|review)",
    quickstart,
    re.DOTALL,
), "quickstart lost the strict wording-only single-review exception"
for label, text in {
    "quickstart": quickstart,
    "dual-track": dual,
    "validation-and-landing": landing,
    "code-review": code_review,
}.items():
    assert "wording_only_boundary" in text, (
        f"{label} does not require independent wording-only semantic confirmation"
    )
assert "--wording-only-proof-file" in staged
assert "--challenge-budget 0" in staged
assert "markdown-punctuation-only" in staged
assert "markdown-token-replacement" in staged
assert "opens no challenge chain or `complete` checkpoint" in dual
assert "codex review --base" not in quickstart
assert "codex exec adversarial" not in quickstart
assert "--challenge-budget" not in quickstart, (
    "quickstart must not let callers override the extraction review budget"
)
assert re.search(
    r"[Rr]ound 2 challenge.{0,500}ready_for_human_decision",
    quickstart,
    re.DOTALL,
), "quickstart does not validate an early-clean round-2 terminal checkpoint"
assert re.search(
    r"[Rr]ound 2 findings.{0,200}continuation_authorization_required",
    quickstart,
    re.DOTALL,
), "quickstart does not validate the exhausted-budget terminal checkpoint"
assert "baseline_race" in quickstart
PY

echo "test_extraction_review_gate: ok"
