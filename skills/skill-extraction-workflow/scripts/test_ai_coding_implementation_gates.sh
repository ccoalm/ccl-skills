#!/usr/bin/env bash
# Semantic-anchor regression for the two independent implementation gates.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd -P)"
REPO_ROOT="$(git -C "$SCRIPT_DIR" rev-parse --show-toplevel 2>/dev/null || { cd "$SCRIPT_DIR/../../.." && pwd -P; })"

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

assert_contains() {
  local file="$1" text="$2" label="$3"
  [[ -f "$file" ]] || fail "$label: missing file $file"
  grep -Fq -- "$text" "$file" || fail "$label: missing semantic anchor: $text"
}

PRODUCT_SKILL="$REPO_ROOT/skills/product-rd-workflow/SKILL.md"
PRODUCT_REF="$REPO_ROOT/skills/product-rd-workflow/references/implementation-completeness-and-minimality.md"
REVIEW_REF="$REPO_ROOT/skills/product-rd-workflow/references/code-review-checklist.md"
PRE_FINAL_REF="$REPO_ROOT/skills/product-rd-workflow/references/pre-final-continuation-gate.md"
STATUS_REF="$REPO_ROOT/skills/product-rd-workflow/references/status-tracker-sync.md"
TESTING_SKILL="$REPO_ROOT/skills/testing-strategy/SKILL.md"
SCENARIO_REF="$REPO_ROOT/skills/testing-strategy/references/scenario-testing.md"
EXTRACTION_SKILL="$REPO_ROOT/skills/skill-extraction-workflow/SKILL.md"

# The rule BODY lives in the reference; the entrypoint keeps the firing signal
# plus the load pointer. Both sides are pinned: dropping the destination sentence
# loses the rule, and dropping the entry clause or the pointer means nothing ever
# tells the agent to load it — a relocation that keeps only one side is exactly
# the silent-hollowing failure this pair of assertions exists to catch.
assert_contains "$PRODUCT_REF" "Functional completeness and structural minimality are independent gates." "product workflow gate (destination)"
assert_contains "$PRODUCT_SKILL" "functional completeness and structural minimality are independent gates" "product workflow gate (entry firing signal)"
assert_contains "$PRODUCT_SKILL" 'gaps block `complete`' "product workflow gate (entry firing consequence)"
assert_contains "$PRODUCT_SKILL" "references/implementation-completeness-and-minimality.md" "product workflow pointer"
assert_contains "$PRODUCT_REF" "Requirement / acceptance point | Source decision | Implementation surface | Verification | Fresh evidence | Status" "acceptance closure matrix"
assert_contains "$PRODUCT_REF" "New concept | Current acceptance point or hard constraint | Simpler alternative | Decision" "concept delta matrix"
assert_contains "$PRODUCT_REF" "Passing one question never compensates for failing the other." "independent axes"
assert_contains "$PRODUCT_REF" 'An implementer may not silently downscope a point' "no self-downscope"
assert_contains "$PRODUCT_REF" 'hypothetical reuse are not evidence' "no speculative concepts"
assert_contains "$PRODUCT_REF" 'behavior-changing by default and never take any exemption' "exemption surface floor"
assert_contains "$PRODUCT_REF" 'Exemptions are per-axis, not blanket' "per-axis exemption"
assert_contains "$PRODUCT_REF" 'never present generated IDs as source-native' "generated trace IDs"
assert_contains "$TESTING_SKILL" 'acceptance-source lookup' "acceptance source record"
assert_contains "$PRE_FINAL_REF" 'For behavior-changing product delivery, refuse implementation completion without both closure tables.' "completion firing point"
assert_contains "$STATUS_REF" 'A behavior-changing implementation row may become `complete` only when both closure tables are present' "status firing point"
assert_contains "$REVIEW_REF" "Review both negative space and concept delta." "review firing point"
assert_contains "$REVIEW_REF" 'qualify for no exemption' "review exemption floor"
assert_contains "$TESTING_SKILL" "Code analysis may add risk scenarios; it must not define product-delivery completeness." "requirement-first testing"
assert_contains "$SCENARIO_REF" "Requirement-derived completeness" "scenario coverage"
assert_contains "$EXTRACTION_SKILL" "recurring cross-project agent failure" "durable extraction trigger"

# ── Relocated-rule dual-side pins ────────────────────────────────────────────
# Seven entrypoint rules had their mechanics moved into package references and
# their old ledger anchors waived through anchored EXEMPT. That waiver is
# existence-only by design, so on its own NOTHING would notice if a relocated
# rule were later reworded or deleted at its destination — the ledger row keeps
# resolving and the gate stays green. Each relocation therefore gets both sides
# pinned here: the rule BODY at the destination, and at the entrypoint the
# firing signal plus the load pointer that is the only reason an agent ever
# reaches that destination. Dropping either side reds this fixture.
MECHANISM_REF="$REPO_ROOT/skills/product-rd-workflow/references/design-review-gate-mechanics.md"
ENTRY_GATE_REF="$REPO_ROOT/skills/product-rd-workflow/references/implementation-entry-reentry-gate.md"
LIFECYCLE_REF="$REPO_ROOT/skills/product-rd-workflow/references/delivery-lifecycle.md"
SYNC_REF="$REPO_ROOT/skills/product-rd-workflow/references/sync-spec-repo-contract.md"

# The pointer must sit in the SAME entrypoint bullet as the firing signal.
# Asserting each independently over the whole file proves nothing about routing:
# these reference paths occur several times in the entrypoint, so deleting the
# pointer from the relocated bullet would leave a whole-file assertion green
# while that trigger no longer routes anywhere. Entrypoint bullets are one line
# each, so the line carrying the firing phrase is the bounded scope.
assert_same_bullet() {
  local file="$1" phrase="$2" pointer="$3" label="$4"
  [[ -f "$file" ]] || fail "$label: missing file $file"
  local bullet
  bullet="$(grep -F -m1 -- "$phrase" "$file")" \
    || fail "$label: firing phrase absent from entrypoint: $phrase"
  case "$bullet" in
    *"$pointer"*) : ;;
    *) fail "$label: firing phrase found, but its own bullet does not carry the load pointer: $pointer" ;;
  esac
}

# 1. Mechanism-operability check
assert_contains "$MECHANISM_REF" 'A mechanism failing this check is redesigned or lightened at design time' "mechanism gate (destination)"
assert_contains "$MECHANISM_REF" 'trust-model fit' "mechanism gate leg (destination)"
assert_same_bullet "$PRODUCT_SKILL" 'Mechanism-operability check** fires whenever the design proposes' \
  "references/design-review-gate-mechanics.md" "mechanism gate (entry signal+pointer)"

# 2. Affirmative-assent binding
assert_contains "$PRE_FINAL_REF" 'the required `proposed-next:` marker makes that binding observable' "assent binding (destination)"
assert_same_bullet "$PRODUCT_SKILL" 'Affirmative-assent binding rule' \
  "references/pre-final-continuation-gate.md" "assent binding (entry signal+pointer)"
assert_contains "$PRODUCT_SKILL" 'self-classifying the reply or marker away is never an exit' "assent binding (entry no-exit clause)"

# 3. Owner invoke bar
assert_contains "$ENTRY_GATE_REF" 'The invoke bar applies to every field that names an owner' "invoke bar (destination)"
assert_same_bullet "$PRODUCT_SKILL" 'delegation being plausible at all loads `multi-agent-delegation`' \
  "references/implementation-entry-reentry-gate.md" "invoke bar (entry signal+pointer)"

# 4. Deep self-audit / walked enumeration
assert_contains "$LIFECYCLE_REF" 'walked enumeration over the properties this delivery asserts' "self-audit (destination)"
assert_same_bullet "$PRODUCT_SKILL" 'external review is the backstop for what the audit missed' \
  "references/delivery-lifecycle.md" "self-audit (entry signal+pointer)"

# 5/6. Upstream-authority no-copy rule and its dependency default
assert_contains "$SYNC_REF" 'The same no-copy rule governs any UPSTREAM AUTHORITY the repo does not own' "no-copy rule (destination)"
assert_contains "$SYNC_REF" 'default to the access-controlled pointer + revision' "dependency default (destination)"
assert_same_bullet "$PRODUCT_SKILL" 'upstream-owned value set' \
  "references/sync-spec-repo-contract.md" "no-copy rule (entry signal+pointer)"
assert_contains "$PRODUCT_SKILL" 'cite the access-controlled pointer + revision' "dependency default (entry variant)"

echo "test_ai_coding_implementation_gates: ok"
