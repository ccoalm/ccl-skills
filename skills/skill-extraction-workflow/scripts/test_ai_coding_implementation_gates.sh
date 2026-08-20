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
  assert_same_line "$@"
}

# The real primitive underneath: phrase and pointer must share one PHYSICAL LINE.
# `assert_same_bullet` is the entrypoint-shaped name for it and stays, because
# there a bullet IS one line. Callers outside that shape use this name instead, so
# the assertion advertises the unit it actually enforces rather than borrowing a
# name whose justification ("entrypoint bullets are one line each") does not hold
# for them. The unit matters: it is only a co-location guarantee while the host
# block stays unwrapped, so a caller pointing at prose is asserting that too.

assert_same_line() {
  local file="$1" phrase="$2" pointer="$3" label="$4"
  [[ -f "$file" ]] || fail "$label: missing file $file"
  local line
  line="$(grep -F -m1 -- "$phrase" "$file")" \
    || fail "$label: firing phrase absent from $file: $phrase"
  case "$line" in
    *"$pointer"*) : ;;
    *) fail "$label: firing phrase found, but its own line does not carry the load pointer: $pointer" ;;
  esac
}

# Anchor inside ONE Markdown section, not anywhere in the file. A whole-file grep
# cannot tell a normative rule from a mention of it, so relocating the clause into
# commentary elsewhere in the reference would keep a file-wide check green. The
# section is the heading line through the next heading at any level.
# Co-location within one Markdown PARAGRAPH (blank-line delimited). Prose is
# wrapped by formatters, so binding a prose pointer to a physical line makes an
# ordinary rewrap red the gate while rendered routing is untouched — a false red
# on a shared gate is a real cost, and the guarantee that actually matters is
# that a reader meeting the trigger meets the pointer without leaving the block.
assert_same_paragraph() {
  local file="$1" phrase="$2" pointer="$3" label="$4"
  [[ -f "$file" ]] || fail "$label: missing file $file"
  local para
  para="$(awk -v p="$phrase" '
    BEGIN {RS = ""}
    index($0, p) {print; exit}
  ' "$file")"
  [[ -n "$para" ]] || fail "$label: firing phrase absent from $file: $phrase"
  case "$para" in
    *"$pointer"*) : ;;
    *) fail "$label: firing phrase found, but its own paragraph does not carry the load pointer: $pointer" ;;
  esac
}

assert_in_section() {
  local file="$1" heading="$2" text="$3" label="$4"
  [[ -f "$file" ]] || fail "$label: missing file $file"
  local section
  section="$(awk -v h="$heading" '
    $0 == h {inside = 1; next}
    inside && /^#/ {exit}
    inside {print}
  ' "$file")"
  [[ -n "$section" ]] || fail "$label: section not found or empty: $heading"
  case "$section" in
    *"$text"*) : ;;
    *) fail "$label: text missing from section $heading: $text" ;;
  esac
}

# 1. Mechanism-operability check
assert_contains "$MECHANISM_REF" 'A mechanism failing this check is redesigned or lightened at design time' "mechanism gate (destination)"
assert_contains "$MECHANISM_REF" 'trust-model fit' "mechanism gate leg (destination)"
assert_same_bullet "$PRODUCT_SKILL" 'Mechanism-operability check** fires whenever the design proposes' \
  "references/design-review-gate-mechanics.md" "mechanism gate (entry signal+pointer)"

# 1b. Claim liveness — the mechanism check's SECOND firing point, whose actor is
# whoever withdraws the claim rather than the machinery's author. The design-time
# pins above cannot notice its loss: every one of them stays green with the
# claim-liveness rule deleted, because they assert the design-time legs only. Its
# two halves are pinned separately on purpose — "retire the gate" without the
# obligation walk is the failure that walk exists to prevent, and a reworded
# retirement sentence would keep the first pin green while dropping the second.
assert_in_section "$MECHANISM_REF" '## Mechanism-operability check' 're-based onto a claim that still holds, or retired, in that same landing' \
  "claim liveness (destination rule)"
assert_in_section "$MECHANISM_REF" '## Mechanism-operability check' 'obligations it carried that never depended on the dead claim do not die with it' \
  "claim liveness (destination retirement walk)"
# The rule offers TWO dispositions and the walk must cover both. Scoping it to
# retirement alone leaves re-basing free to rewrite the enforcement surface — an
# independent obligation quietly dropped, or the withdrawn claim still enforced
# under a new name, with every other pinned clause satisfied.
assert_in_section "$MECHANISM_REF" '## Mechanism-operability check' 'Neither path is a free edit' \
  "claim liveness (walk covers re-base as well as retirement)"
assert_in_section "$MECHANISM_REF" '## Mechanism-operability check' 'no component still enforces the withdrawn claim' \
  "claim liveness (a re-base must not carry the dead claim forward)"
# The walk above says "disposition each", and one of the dispositions is giving an
# obligation up. Without the next clause that disposition is self-serviceable, so
# a claim withdrawal becomes a route to delete a permission, data-safety, or
# finality control by writing "accepted" about your own landing. This is the
# highest-consequence sentence in the rule; pin it separately from the walk so a
# rewrite cannot drop the approver while keeping the walk green.
#
# Pin the clause's OBLIGATIONS one by one, not its headline. Three review rounds
# in a row found the same class of gap — an anchor on the sentence stays green
# while a sub-requirement inside it is deleted — so the unit here is "one
# assertion per thing the clause actually requires", and each is mutation-tested
# on its own. The headline and the teeth are independently droppable, which is
# precisely why they are independently pinned.
#
# WHAT THESE PROVE, AND WHAT THEY DO NOT. They prove each obligation is PRESENT
# and lives INSIDE the owning section — that is, they catch deletion, rewording
# away, and relocation into commentary. They do NOT prove the safety SEMANTICS
# survived: a later sentence added to this same section ("except availability
# controls may be self-accepted") leaves every fragment in place and every
# assertion green while gutting the rule. That gap is accepted deliberately, not
# overlooked — closing it needs a normative-block comparator, which reds on every
# legitimate wording edit and defends only against an author who would edit this
# fixture in the same commit. Catching a deliberate weakening is the dual-track
# review's job, not this file's. Do not cite a green run here as evidence that
# the rule still MEANS what it meant.
assert_in_section "$MECHANISM_REF" '## Mechanism-operability check' 'That last disposition is not self-serviceable' \
  "claim liveness (headline: acceptance is not self-serviceable)"
assert_in_section "$MECHANISM_REF" '## Mechanism-operability check' 'named accountable risk owner' \
  "claim liveness (obligation: a named accountable approver exists)"
assert_in_section "$MECHANISM_REF" '## Mechanism-operability check' 'routes through `feature-risk-router`' \
  "claim liveness (obligation: escalation route)"
assert_in_section "$MECHANISM_REF" '## Mechanism-operability check' 'keeps enforcing — retained or re-based — until a' \
  "claim liveness (obligation: enforcement continues until acceptance)"
# The rule binds every abandoned control, with no protected-class list. That is a
# deliberate shape, not an omission: a list is one unlisted class away from
# letting a real control out, and review found exactly that twice. Pin the
# unconditional scope, or a later edit "clarifies" it into an enumeration and the
# assertions above keep passing for whichever classes survive the narrowing.
assert_in_section "$MECHANISM_REF" '## Mechanism-operability check' 'deliberately carries no class list to narrow' \
  "claim liveness (obligation: scope is unconditional, not an enumeration)"
assert_in_section "$MECHANISM_REF" '## Mechanism-operability check' 'it binds whatever that control protects' \
  "claim liveness (obligation: binds regardless of what is protected)"
# The deferral escape hatch is the rule's own re-entry point for the failure it
# prevents: "pending" with no approver, no end, and no consequence lets the dead
# claim keep charging rent forever, which is exactly the tax being outlawed. Its
# three teeth are pinned individually for the same reason as the clause above.
assert_in_section "$MECHANISM_REF" '## Mechanism-operability check' 'accepted risk with an end, not a note' \
  "claim liveness (deferral: pending is an accepted risk, not a note)"
assert_in_section "$MECHANISM_REF" '## Mechanism-operability check' 'risk owner accepts the deferral itself' \
  "claim liveness (deferral: owner approves the deferral)"
assert_in_section "$MECHANISM_REF" '## Mechanism-operability check' 'the first landing that pays the cost' \
  "claim liveness (deferral: bounded by an observable end event)"
assert_in_section "$MECHANISM_REF" '## Mechanism-operability check' 'the next one that invokes or modifies the mechanism' \
  "claim liveness (deferral: the bound is whoever PAYS, not whoever edits)"
assert_in_section "$MECHANISM_REF" '## Mechanism-operability check' 'the per-change cost being paid meanwhile' \
  "claim liveness (deferral: the standing cost is recorded)"
assert_in_section "$MECHANISM_REF" '## Mechanism-operability check' 'escalates through `feature-risk-router` instead of renewing quietly' \
  "claim liveness (deferral: expiry escalates, never renews silently)"
assert_in_section "$MECHANISM_REF" '## Mechanism-operability check' 'about its own landing is not an acceptance' \
  "claim liveness (obligation: self-acceptance is rejected)"
# The entrypoint must advertise the second trigger in the SAME bullet as the load
# pointer, for the same routing reason assert_same_bullet exists above: the actor
# who withdraws a claim never matches the design-time phrasing, so a firing signal
# that lost its pointer would route that actor nowhere.
assert_same_bullet "$PRODUCT_SKILL" 'and again when a landing withdraws or downgrades the evidentiary claim' \
  "references/design-review-gate-mechanics.md" "claim liveness (entry signal+pointer)"
# The shared-skill instantiation reaches the rule only through this pointer; the
# observed failure (round 028) was a shared-skill gate, so losing it re-opens the
# exact path that failed. Co-location is the assertion, not presence: this side is
# ONLY a pointer, so a check on the trigger phrase alone would stay green after the
# destination path is deleted from it — leaving a reader who is told a fifth firing
# point exists and never told where the rule lives, which is the reachability
# failure this whole round exists to close.
assert_same_paragraph "$REPO_ROOT/skills/skill-extraction-workflow/references/dual-track-review-gate.md" \
  'withdraws or downgrades the evidentiary claim an existing gate rests on' \
  "product-rd-workflow/references/design-review-gate-mechanics.md" \
  "claim liveness (shared-skill instantiation pointer)"

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
