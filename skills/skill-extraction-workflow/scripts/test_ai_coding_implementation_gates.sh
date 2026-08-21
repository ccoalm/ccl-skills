#!/usr/bin/env bash
# Semantic-anchor regression for the independent implementation-gate pin families.
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

# 7. Model-visible accounting invariant (agent session persistence, round 030).
# The clause is a security-owner-approved rule whose historical failure modes are
# each a specific sentence: forcing raw persistence (r4), accepting mutable
# reference targets (r5), and leaving a plain digest as the only residue (r6).
# One assertion per obligation, section-bound, for the same reasons as family 1b:
# a sentence-level anchor stays green while a sub-obligation inside it is
# deleted, and a whole-file grep cannot tell a normative rule from a mention.
# The same limits stated there apply here: these pins catch deletion,
# rewording-away, and relocation — not a weakening sentence added beside them;
# that is the dual-track review's job.
PERSISTENCE_REF="$REPO_ROOT/skills/llm-inference-integration/references/agent-session-persistence.md"
PERSISTENCE_POLICY_SECTION='## 3. A persistence policy decides what is durable, ephemeral, or truncated'
assert_in_section "$PERSISTENCE_REF" "$PERSISTENCE_POLICY_SECTION" 'client-dispatched envelope must carry' \
  "model-visible accounting (invariant: envelope items are the accounted set)"
# Review round 27 (codex) P1: weakening "exactly one" to "one or more" kept
# the lead pin green — the uniqueness quantifier gets its own pin.
assert_in_section "$PERSISTENCE_REF" "$PERSISTENCE_POLICY_SECTION" 'exactly one durable accounting classification' \
  "model-visible accounting (invariant: the classification is exactly one)"
# Review round 3 (codex): the invariant pin alone lets the three class
# DEFINITIONS be deleted or weakened while everything stays green, and the raw
# class needed byte-equivalence semantics (a persistence-redacted item is not
# what the model saw, so calling it raw breaks replay while completeness checks
# pass). One pin per class definition, plus the raw-semantics pair.
# Review round 22 (codex) P1: "byte-equivalent to what the model saw"
# contradicted the provider-effective scoping, which admits consumption is
# unverifiable — raw binds to the envelope item, the only thing the client can
# actually guarantee bytes for.
assert_in_section "$PERSISTENCE_REF" "$PERSISTENCE_POLICY_SECTION" 'byte-equivalent to its item in the' \
  "model-visible accounting (class: raw means byte-equivalent to the envelope item)"
assert_in_section "$PERSISTENCE_REF" "$PERSISTENCE_POLICY_SECTION" 'transformed by persistence-time' \
  "model-visible accounting (class: a redacted item does not classify raw)"
# Review round 4 (codex) P1: raw's out-of-line parenthetical re-opened the
# availability hole — an out-of-line store may purge before the log expires or
# deny the replay principal, yet the raw class required neither. Out-of-line is
# by-reference by definition; pinned so the routing sentence cannot be dropped.
assert_in_section "$PERSISTENCE_REF" "$PERSISTENCE_POLICY_SECTION" 'A payload stored out-of-line classifies by' \
  "model-visible accounting (class: out-of-line payloads classify by reference, never raw)"
assert_in_section "$PERSISTENCE_REF" "$PERSISTENCE_POLICY_SECTION" 'the log carries an immutable, versioned reference' \
  "model-visible accounting (class: by-reference means immutable versioned reference)"
# Review round 7 (codex) P2: "plus a digest" was droppable — the reference pin
# does not require a digest and the keyed-residue pins only constrain a digest
# when one exists, so the class could lose its integrity requirement silently.
assert_in_section "$PERSISTENCE_REF" "$PERSISTENCE_POLICY_SECTION" 'plus a digest, and the referenced store keeps the item' \
  "model-visible accounting (class: a by-reference record carries a mandatory digest)"
assert_in_section "$PERSISTENCE_REF" "$PERSISTENCE_POLICY_SECTION" 'an explicit marker carrying the reason' \
  "model-visible accounting (class: non-reconstructable carries a reason)"
assert_in_section "$PERSISTENCE_REF" "$PERSISTENCE_POLICY_SECTION" 'digest or an explicit no-digest note' \
  "model-visible accounting (class: non-reconstructable carries a keyed digest or a no-digest note)"
assert_in_section "$PERSISTENCE_REF" "$PERSISTENCE_POLICY_SECTION" 'no envelope item without a classification' \
  "model-visible accounting (obligation: assertions check completeness)"
# Review round 9 (codex) P1: a crash between model dispatch and the append, or
# a duplicating retry, leaves items a log-only audit cannot see — completeness
# was only as real as whatever reached the log. Round 10 deepened it: a manifest
# of ids+classifications alone still passes while a raw item's CONTENT never
# landed, so the pre-dispatch commit carries each classification's evidence.
# Four teeth, pinned individually.
assert_in_section "$PERSISTENCE_REF" "$PERSISTENCE_POLICY_SECTION" "durably commit each item's complete accounting record" \
  "model-visible accounting (obligation: the complete accounting record commits before dispatch)"
assert_in_section "$PERSISTENCE_REF" "$PERSISTENCE_POLICY_SECTION" "and that classification's evidence" \
  "model-visible accounting (obligation: the pre-dispatch commit includes the classification's evidence)"
assert_in_section "$PERSISTENCE_REF" "$PERSISTENCE_POLICY_SECTION" 'failing closed if that commit fails' \
  "model-visible accounting (obligation: a failed manifest commit fails closed)"
assert_in_section "$PERSISTENCE_REF" "$PERSISTENCE_POLICY_SECTION" 'reuses the ids so a replayed' \
  "model-visible accounting (obligation: retries deduplicate by stable item ids)"
# Review round 11 (codex) P1: with no authoritative denominator, an
# under-enumeration defect commits records for a subset and the audit checks
# the log against that same subset — a dropped item (injected instructions
# included) is invisible. The manifest derives from the finalized dispatch
# payload itself; both teeth pinned.
assert_in_section "$PERSISTENCE_REF" "$PERSISTENCE_POLICY_SECTION" 'invocation-scoped manifest from the finalized dispatch payload' \
  "model-visible accounting (obligation: the manifest derives from the finalized dispatch payload)"
assert_in_section "$PERSISTENCE_REF" "$PERSISTENCE_POLICY_SECTION" 'rather than against whatever subset of' \
  "model-visible accounting (obligation: the audit denominator is the invocation manifest)"
# Review round 12 (codex) P1: deriving manifest and records from a payload that
# middleware can still mutate re-opens the commit-to-send window — the model
# sees the changed payload while the audit passes against the unchanged
# manifest. Sealed-envelope closure, both teeth pinned.
assert_in_section "$PERSISTENCE_REF" "$PERSISTENCE_POLICY_SECTION" 'derive the manifest and records from that sealed envelope' \
  "model-visible accounting (obligation: manifest and records derive from the sealed envelope)"
assert_in_section "$PERSISTENCE_REF" "$PERSISTENCE_POLICY_SECTION" 'transport and retries send only the sealed envelope' \
  "model-visible accounting (obligation: transport sends only the sealed envelope)"
# Review round 13 (codex), two P1s: (a) after a transport failure or lost ack
# the log was indistinguishable from a consumed invocation, and an id-reusing
# retry could invoke the model twice while accounting showed one — the attempt
# needs its own durable states and provider idempotency key; (b) fail-closed
# auditing bricked pre-accounting sessions, and synthesizing records for them
# would fabricate evidence — the schema is versioned and prospective, legacy
# history carries a typed marker. Four teeth, pinned individually.
assert_in_section "$PERSISTENCE_REF" "$PERSISTENCE_POLICY_SECTION" 'prepared, dispatch-attempted, then accepted or' \
  "model-visible accounting (obligation: durable attempt states around the sealed envelope)"
assert_in_section "$PERSISTENCE_REF" "$PERSISTENCE_POLICY_SECTION" 'shows as two attempts even while item accounting deduplicates' \
  "model-visible accounting (obligation: a possible double invocation is visible as two attempts)"
# Review rounds 15/16 (codex) P1s: appending dispatch-attempted AFTER calling
# the provider loses the attempt on a crash between send and append, and a
# wording that let `prepared` satisfy the pre-transport commit kept that window
# open. The durable state that commits pre-transport IS dispatch-attempted, and
# post-transport transitions are accepted/delivery-uncertain only.
assert_in_section "$PERSISTENCE_REF" "$PERSISTENCE_POLICY_SECTION" 'dispatch-attempted state (unique attempt id plus that key) commits before transport' \
  "model-visible accounting (obligation: dispatch-attempted itself commits before transport)"
assert_in_section "$PERSISTENCE_REF" "$PERSISTENCE_POLICY_SECTION" 'after transport the state moves only to' \
  "model-visible accounting (obligation: post-transport states come from the closed enumeration)"
# Review round 26 (codex) P1: the closed post-transport enumeration had no
# place for a definitive provider rejection before model execution, forcing
# false uncertainty. `rejected` is provider-attested and records that no
# invocation occurred.
assert_in_section "$PERSISTENCE_REF" "$PERSISTENCE_POLICY_SECTION" 'provider-attested definitive rejection' \
  "model-visible accounting (obligation: rejected is provider-attested with no invocation)"
# Self-audit after round 27 (lifecycle walk, both found by the implementer, not
# a reviewer): (H1) a corrected resend after `rejected` must be a NEW sealed
# invocation — an idempotency key may only ever cover one identical payload;
# (H2) the rejected-exposure event had no content constraint.
assert_in_section "$PERSISTENCE_REF" "$PERSISTENCE_POLICY_SECTION" 'new sealed invocation with its own envelope and key' \
  "model-visible accounting (obligation: a corrected resend after rejected is a new invocation)"
assert_in_section "$PERSISTENCE_REF" "$PERSISTENCE_POLICY_SECTION" 'itself under the same discipline as every exposure record' \
  "model-visible accounting (obligation: the rejected-exposure event carries no value or plain digest)"
# Review round 17 (codex) P1: a crash just after the dispatch-attempted commit
# and a crash after provider acceptance leave the same record, so recovery
# could either drop a delivered invocation or blind-retry into a double one.
# Stale records resolve to delivery-uncertain, reconcile by provider request
# id, and auto-retry only under provider-guaranteed idempotency.
assert_in_section "$PERSISTENCE_REF" "$PERSISTENCE_POLICY_SECTION" 'treats a stale dispatch-attempted record as delivery-uncertain' \
  "model-visible accounting (obligation: recovery resolves stale attempts to delivery-uncertain)"
assert_in_section "$PERSISTENCE_REF" "$PERSISTENCE_POLICY_SECTION" "provider-guaranteed idempotency with the invocation's original key" \
  "model-visible accounting (obligation: auto-retry only under provider-guaranteed idempotency with the original key)"
# Review round 21 (codex) P1: a retry that mints a fresh idempotency key is a
# distinct request to the provider — the model runs twice while the accounting
# shows a retry. The key binds to the sealed logical invocation.
assert_in_section "$PERSISTENCE_REF" "$PERSISTENCE_POLICY_SECTION" 'a retry that mints a fresh key is a second invocation' \
  "model-visible accounting (obligation: a fresh-key retry counts as a second invocation)"
assert_in_section "$PERSISTENCE_REF" "$PERSISTENCE_POLICY_SECTION" 'uncertainty is surfaced, not retried through' \
  "model-visible accounting (obligation: unresolved uncertainty is surfaced, never retried through)"
# Challenge (chain r23) P1: a record committed but never dispatch-attempted had
# no recovery path — indefinitely prepared, surfacing nothing, stranding
# committed evidence. Cancel-or-resume, both teeth pinned.
assert_in_section "$PERSISTENCE_REF" "$PERSISTENCE_POLICY_SECTION" 'A stale prepared record — committed but never' \
  "model-visible accounting (obligation: stale prepared records are recovered explicitly)"
assert_in_section "$PERSISTENCE_REF" "$PERSISTENCE_POLICY_SECTION" 'resume by committing dispatch-attempted and sending the identical sealed' \
  "model-visible accounting (obligation: resume recommits dispatch-attempted with the identical envelope)"
# Review round 21 (codex) P1: raw evidence could be durably committed before
# the pre-transport secret scan rejected the envelope, leaving the value in the
# log with the erasure transition scoped to post-model discovery only.
assert_in_section "$PERSISTENCE_REF" "$PERSISTENCE_POLICY_SECTION" 'runs before accounting evidence is derived or committed' \
  "model-visible accounting (obligation: the secret scan precedes evidence derivation and commit)"
# Review round 24 (codex) P1: a scanner timeout/error/absence read as "no
# detection" and the envelope shipped unscanned — the scan itself fails closed.
assert_in_section "$PERSISTENCE_REF" "$PERSISTENCE_POLICY_SECTION" 'never reads as no detection' \
  "model-visible accounting (obligation: a failed or absent scan never reads as clean)"
assert_in_section "$PERSISTENCE_REF" "$PERSISTENCE_POLICY_SECTION" 'the late-discovery transition below applies to the aborted dispatch' \
  "model-visible accounting (obligation: an aborted dispatch with prior persistence takes the erasure transition)"
assert_in_section "$PERSISTENCE_REF" "$PERSISTENCE_POLICY_SECTION" 'Version the accounting schema and apply it prospectively' \
  "model-visible accounting (obligation: the schema is versioned and prospective)"
assert_in_section "$PERSISTENCE_REF" "$PERSISTENCE_POLICY_SECTION" 'never synthesized classifications' \
  "model-visible accounting (obligation: legacy history is marked, never fabricated)"
# Review round 14 (codex) P1: a provider that injects, truncates, or compacts
# server-side makes the model's effective context differ from the sealed
# envelope while every local record passes — the guarantee must claim the
# client-dispatched envelope and mark the rest unverifiable, not imply
# full fidelity it cannot see. Both teeth pinned.
assert_in_section "$PERSISTENCE_REF" "$PERSISTENCE_POLICY_SECTION" 'scoped to what the client dispatched' \
  "model-visible accounting (obligation: the guarantee is scoped to client-dispatched context)"
assert_in_section "$PERSISTENCE_REF" "$PERSISTENCE_POLICY_SECTION" 'typed model-context-unverifiable marker' \
  "model-visible accounting (obligation: absent provider evidence, unverifiability is marked)"
assert_in_section "$PERSISTENCE_REF" "$PERSISTENCE_POLICY_SECTION" 'resolve them by reference at the boundary' \
  "model-visible accounting (obligation: secrets are reference-resolved, never model-visible raw)"
# Review round 19 (codex) P1: a secret DETECTED before dispatch was accounted
# for and then sent anyway — the rule only failed closed on commit failure, so
# accounting a known exposure licensed shipping it. Detection aborts transport;
# the leak classification is reserved for post-dispatch discovery.
assert_in_section "$PERSISTENCE_REF" "$PERSISTENCE_POLICY_SECTION" 'before dispatch aborts the transport' \
  "model-visible accounting (obligation: a detected secret aborts the dispatch)"
assert_in_section "$PERSISTENCE_REF" "$PERSISTENCE_POLICY_SECTION" 'accounting for a known exposure never licenses sending it' \
  "model-visible accounting (obligation: accounting never licenses sending a known exposure)"
# Challenge (chain r20) P1: an unrecognized secret classified raw leaves its
# value readable in the append-only log after late discovery — relabeling did
# not touch the persisted bytes. The late-discovery transition has four teeth,
# pinned individually.
assert_in_section "$PERSISTENCE_REF" "$PERSISTENCE_POLICY_SECTION" 'covers every class that persisted content' \
  "model-visible accounting (obligation: late discovery covers raw and by-reference items)"
assert_in_section "$PERSISTENCE_REF" "$PERSISTENCE_POLICY_SECTION" 'contain read access to the affected records and the referenced target at once' \
  "model-visible accounting (obligation: containment reaches the referenced target too)"
# Review round 25 (codex) P1: erasure named the value and replicas but not the
# plain integrity digest legitimately stored beside a raw record — once the
# value is erased, that digest is the enumerable residue of a low-entropy
# secret. The erasure list includes it.
assert_in_section "$PERSISTENCE_REF" "$PERSISTENCE_POLICY_SECTION" 'erase the persisted or referenced content, its replicas, and any digest or' \
  "model-visible accounting (obligation: erasure covers content, replicas, digests, and derived identifiers)"
assert_in_section "$PERSISTENCE_REF" "$PERSISTENCE_POLICY_SECTION" 'recording any residue that could not be erased' \
  "model-visible accounting (obligation: unerased residue is recorded in the exposure event)"
assert_in_section "$PERSISTENCE_REF" "$PERSISTENCE_POLICY_SECTION" 'A mutable reference target does not qualify:' \
  "model-visible accounting (obligation: immutable reference targets only)"
# Review round 1 (codex) P1: "policy at least as strict" was wrong on both axes —
# a store purging EARLIER than the log, or denying the replay principal, passed
# the old wording while replay silently failed. The criterion is availability +
# authorization, and both corrected clauses are pinned so a reword back to the
# strictness proxy reds here.
assert_in_section "$PERSISTENCE_REF" "$PERSISTENCE_POLICY_SECTION" "resolvable for the session log's whole retention horizon" \
  "model-visible accounting (obligation: by-reference availability spans the retention horizon)"
assert_in_section "$PERSISTENCE_REF" "$PERSISTENCE_POLICY_SECTION" 'or denies the replay principal,' \
  "model-visible accounting (obligation: the replay principal keeps access)"
# Review round 5 (codex) P2: the no-broader-access clause was the one criterion
# of the by-reference class left unpinned — droppable while the horizon and
# principal pins stayed green, widening who can read replay data.
assert_in_section "$PERSISTENCE_REF" "$PERSISTENCE_POLICY_SECTION" 'with access no broader than' \
  "model-visible accounting (obligation: reference-store access is no broader than the log policy)"
assert_in_section "$PERSISTENCE_REF" "$PERSISTENCE_POLICY_SECTION" 'it must never force raw persistence' \
  "model-visible accounting (obligation: audits records, never forces persistence)"
assert_in_section "$PERSISTENCE_REF" "$PERSISTENCE_POLICY_SECTION" 'the accounting records a typed exposure event' \
  "model-visible accounting (obligation: leaked secret becomes a typed exposure event)"
assert_in_section "$PERSISTENCE_REF" "$PERSISTENCE_POLICY_SECTION" 'never the value, and never a plain digest of it' \
  "model-visible accounting (obligation: no value and no plain digest of a leaked secret)"
# Review round 1 (codex) P1: a leaked secret was covered by the exactly-one-
# classification invariant yet assigned no class, so a consumer had to leave it
# unclassified or invent one that could retain forbidden material. The corrected
# clause names the class and forbids the other two; pinned so the assignment
# cannot be dropped while the exposure-event pin stays green.
assert_in_section "$PERSISTENCE_REF" "$PERSISTENCE_POLICY_SECTION" 'explicit no-digest note — never raw, never by reference' \
  "model-visible accounting (obligation: a leaked secret classifies non-reconstructable, no digest)"
assert_in_section "$PERSISTENCE_REF" "$PERSISTENCE_POLICY_SECTION" 'allowed only where the same record already persists the content raw' \
  "model-visible accounting (obligation: plain digest only beside raw content)"
# Review round 6 (codex) P1: a content-addressed id IS a plain content hash, so
# a low-entropy value stored out-of-line under a conventional CAS id was
# enumerable from the log while every digest pin stayed green — the rule keyed
# the companion digest and forgot the identifier. Both teeth pinned.
assert_in_section "$PERSISTENCE_REF" "$PERSISTENCE_POLICY_SECTION" 'A content-derived reference identifier is a digest under this rule' \
  "model-visible accounting (obligation: reference identifiers fall under the digest rule)"
assert_in_section "$PERSISTENCE_REF" "$PERSISTENCE_POLICY_SECTION" 'never a plain content hash of the referenced content' \
  "model-visible accounting (obligation: no plain content hash as the log-visible identifier)"
assert_in_section "$PERSISTENCE_REF" "$PERSISTENCE_POLICY_SECTION" 'keyed digest with a non-secret key-id and algorithm-id' \
  "model-visible accounting (obligation: residue digests are keyed)"
# Review round 2 (codex) P1: the keyed-digest pin stays green with the
# retained-keyring / rotation clause deleted, and without that clause an
# implementation may discard old keys on rotation, leaving retained
# by-reference records unverifiable before the log expires. Pinned separately
# so dropping or weakening rotation semantics reds while the keyed pin alone
# would stay green.
assert_in_section "$PERSISTENCE_REF" "$PERSISTENCE_POLICY_SECTION" 'verified against a retained keyring, rotation handled as' \
  "model-visible accounting (obligation: keyring is retained across rotation)"
assert_in_section "$PERSISTENCE_REF" '## Non-negotiables' 'residue of an item is keyed, never plain' \
  "model-visible accounting (non-negotiable bullet present)"

echo "test_ai_coding_implementation_gates: ok"
