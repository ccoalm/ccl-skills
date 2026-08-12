#!/usr/bin/env bash
# Documentation-shape contract test for provider-neutral identity, routing, and
# host-wait wording. It does not simulate or enforce host execution behavior.
set -uo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
REPO_ROOT="$(cd "$DIR/../../.." && pwd -P)"
SKILL="$REPO_ROOT/skills/code-review/SKILL.md"
GATE="$REPO_ROOT/skills/code-review/scripts/review_gate.py"
WAIT_REF="$REPO_ROOT/skills/code-review/references/timeout-auth-and-capabilities.md"
QUICKSTART="$REPO_ROOT/skills/skill-extraction-workflow/references/extraction-quickstart.md"
DUAL_TRACK="$REPO_ROOT/skills/skill-extraction-workflow/references/dual-track-review-gate.md"
fails=0

check() {
  if eval "$2"; then echo "ok   - $1"; else echo "FAIL - $1"; fails=$((fails+1)); fi
}

check "provider-neutral skill directory exists" '[ -f "$SKILL" ]'
check "legacy Claude-specific skill directory is absent" '[ ! -e "$REPO_ROOT/skills/claude-code-review" ]'
check "frontmatter uses code-review" 'grep -q "^name: code-review$" "$SKILL"'
check "Claude may route to the provider-neutral skill" \
  '[ -f "$SKILL" ] && ! grep -q "^disable-model-invocation:" "$SKILL"'
check "client order uses the provider-neutral local variable" \
  'grep -q "CODE_REVIEW_CLIENT_ORDER" "$GATE" && ! grep -q "CLAUDE_CODE_REVIEW_CLIENT_ORDER" "$GATE"'
check "owner wait contract records timeout as inconclusive" \
  'grep -Fq "the final status must say \`inconclusive\` with the timeout reason so downstream review or merge state cannot treat the missing lane as approval" "$SKILL"'
check "owner wait contract polls the exact live handle" \
  'grep -Fq "poll that exact handle to terminal exit, and never start a replacement/fallback while its process is live" "$SKILL"'
check "owner wait contract rejects nonzero unparseable output" \
  'grep -Fq "non-zero exit without valid JSON remains inconclusive/manual-review-required, never as success" "$SKILL"'
check "owner wait contract rejects kill-then-credit" \
  'grep -Fq "must never kill the wrapper and then treat the killed output as success" "$SKILL"'
check "owner wait contract forbids fallback after handle loss" \
  'grep -Fq "If that handle is lost, the lane is infrastructure-inconclusive/manual-review-required and no replacement or fallback may be started or credited" "$SKILL"'
check "owner final summary records lost-handle state" \
  'grep -Fq "record that infrastructure-inconclusive state, diagnostic artifacts, and that fallback was unavailable" "$SKILL"'
check "wait reference forbids replacement while the original handle is live" \
  'tr "\n" " " <"$WAIT_REF" | grep -Fq "Do not start a second reviewer, enter fallback, or call the partial chunk \"empty reviewer output\" while that handle or its child process is alive"'
check "wait reference rejects kill-then-credit" \
  'grep -Fq "must never kill the wrapper and then treat the killed output as success" "$WAIT_REF"'
check "wait reference rejects nonzero unparseable output" \
  'grep -Fq "inconclusive/manual-review-required, never as success" "$WAIT_REF"'
check "wait reference forbids replacement after handle loss" \
  'tr "\n" " " <"$WAIT_REF" | grep -Fq "If orchestration loses the handle, the lane is infrastructure-inconclusive/manual-review-required and no replacement or fallback may be started or credited"'
check "wait reference makes artifacts diagnostic only" \
  'tr "\n" " " <"$WAIT_REF" | grep -Fq "may be inspected for diagnosis only; they cannot reconstruct the missing terminal result or authorize continuation"'
check "wait reference scopes enforcement to the outer host" \
  'grep -Fq "procedural host-workflow obligation, not a controller-owned field" "$WAIT_REF"'
check "extraction quickstart forbids fallback while the original process is live" \
  'grep -Fq "no replacement/fallback reviewer may start while the original process is live" "$QUICKSTART"'
check "extraction quickstart forbids fallback after handle loss" \
  'grep -Fq "If the handle is lost, the lane is infrastructure-inconclusive/manual-review-required and no replacement or fallback may be started or credited" "$QUICKSTART"'
check "extraction quickstart makes artifacts diagnostic only" \
  'grep -Fq "process-tree and wrapper artifacts are diagnostic only" "$QUICKSTART"'
check "extraction quickstart scopes enforcement to the outer host" \
  'grep -Fq "procedural host obligation because the inner gate cannot observe the outer handle" "$QUICKSTART"'
check "dual-track remediation polls the original handle" \
  'grep -Fq "poll it to terminal exit and do not start a replacement or fallback from its empty current output" "$DUAL_TRACK"'
check "dual-track remediation forbids fallback after handle loss" \
  'grep -Fq "If the handle is lost, the lane is infrastructure-inconclusive/manual-review-required and no replacement or fallback may be started or credited" "$DUAL_TRACK"'
check "dual-track remediation makes artifacts diagnostic only" \
  'grep -Fq "process-tree and wrapper artifacts are diagnostic only" "$DUAL_TRACK"'
check "dual-track remediation scopes enforcement to the outer host" \
  'grep -Fq "procedural host obligation because the inner gate cannot observe the outer handle" "$DUAL_TRACK"'

echo '----'
if [ "$fails" -eq 0 ]; then
  echo code_review_identity_tests_ok
else
  echo "$fails FAILURES"
  exit 1
fi
