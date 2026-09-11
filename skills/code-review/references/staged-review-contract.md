# Staged Review Contract

The controller has three modes:

- `review`: initial independent external review;
- `challenge`: a focused adversarial external round;
- `complete`: a local deep-self-review checkpoint that calls no reviewer.

Explore/build may configure `challenge_budget=0..4`; release/high-risk requires
at least one challenge unless the exact candidate qualifies for the
proof-bound wording-only single-review exception below. The initial review consumes chain round 1;
each bounded chain uses at most five rounds. Necessary task-scoped review after a
checkpoint inherits existing task authority; attribute explicit human round requests separately.
The budget is a ceiling, not a quota: after a clean or fully source-refuted tracked challenge, local
`complete` may close the chain early. It preserves unused-round count but sets
`autonomous_review_allowed=false`; release/high-risk still requires at least one
challenge before this early close is eligible.

## What `complete` closes, and what it does not

`--mode complete` is the checkpoint for a chain whose findings were **shown to
be wrong**. Every original occurrence must carry a `source_refuted`
disposition; `unresolved`, `accepted_risk`, `accepted_tradeoff`, and
`needs_human_decision` are refused, and that refusal is deliberate. The gate
binds structure and provenance, never authority: it cannot tell a human
acceptance from an agent that labelled its own findings accepted, so it does
not let an acceptance close a machine checkpoint.

**A chain whose findings are accepted, out of scope, or input defects is not
stalled — it is simply not closed by this mode.** Such a round ends at its
`findings` result with a recorded disposition per occurrence, and the round's
own ledger carries the wider vocabulary. Do not read a refused `complete` as an
unfinished review; read it as "no refutation was claimed". Reporting the round
requires the dispositions, not a completion receipt.

Two mechanics that cost time when they are discovered by experiment:

- **`--stage` and `--risk-tag` must be passed to `complete`, not omitted.** The
  binding predicate compares the prior rounds against the profile derived from
  the arguments given here, so a risk-tagged chain checked without its tags
  fails as an unbound candidate rather than as a mismatch.
- **A round that edits `skills/code-review/scripts/**` cannot bind its own
  earlier rounds.** `review_controller_sha256` covers every `.py` and `.sh`
  there, so any further edit to the harness mid-round changes the controller
  identity and both chain succession and `complete` refuse the earlier
  receipts. Land every harness edit first, then run review and challenge back
  to back with nothing changed in between.

## Plan and owner binding

The plan is optional for `review` and `challenge` and required for `complete`.
When supplied, the bounded UTF-8 plan contains exactly intent, acceptance,
self-review, and evidence. When omitted for review/challenge, the controller
synthesizes a schema-valid derived default (generic intent/acceptance/evidence
plus self-review rows covering the required concerns) and stamps
`review_plan_source=derived-default` on the result so it is never mistaken for a
hand-attested plan (`review_plan_source=implementer-supplied` otherwise).
Self-review accumulates stage concerns: explore covers correctness and
safety; build adds failure paths, tests, and compatibility; release adds rollout
and operations. High-risk input raises depth to release and adds
`high_risk_boundary`. That set has one owner, and
`review_gate.sh --print-required-concerns --stage <stage> [--risk-tag <tag>]`
prints it, so a caller building a plan derives the list instead of keeping a copy
that silently stops satisfying the gate when the set changes. It prints what the
PLAN owes: the synthetic challenge slot and the wording-only boundary, which the
controller adds for the reviewer and never for the plan, are absent.

The serialized plan is at most 32,000 bytes and `intent` is 8..4,000
characters. Those are validation limits, not permission for a caller to slice a
longer value into shape: the gate can validate only the final value it receives
and cannot detect that a caller discarded the newest scope transition first.
Call `scripts/update_review_plan_intent.py` to mutate an existing plan. It checks
an optional expected SHA-256, opens bounded inputs without following links,
writes atomically, preserves ordinary POSIX permission bits, rejects duplicate
JSON object keys before mutation, and leaves the plan byte-identical on
validation or overflow failure. When the plan producer first
chooses the stable core, it persists one reserved evidence row with
`id=review-plan-intent-stable-core-v1` and result
`chars=<character-count>;sha256=<UTF-8-SHA-256>`. On overflow, pass that exact
core and the latest transition as separate files: the helper requires both the
character count and digest to match the persisted identity, requires latest to
be absent from the current intent, and joins them with one fixed blank line.
Before replacing the visible intent, it archives the exact removed suffix in a
reserved, ordered base64 evidence group. That group's manifest binds the prior
intent character count and SHA-256, core length, suffix byte count and SHA-256,
encoding, and part count; if the plan or evidence-row cap cannot hold the group,
compaction fails without changing the file. These rows preserve bytes but do not
classify their meaning. A matching arbitrary prefix is therefore insufficient. Existing plans without
the reserved row remain appendable but cannot compact until their producer has
explicitly established the identity; the helper returns
`intent_core_identity_missing` instead of guessing. The identity proves the
recorded text boundary, not semantic correctness or protection from a caller
that rewrites the whole plan outside the helper. Keep semantic dispositions in
ordinary evidence rows and ordered prior-review results; the byte archive is a
loss-prevention carrier, not a substitute. Never use prefix/tail truncation as
compaction. One final line ending is treated as a file delimiter; other outer
whitespace is rejected.

The expected digest is a stale-at-open guard, not a lock: callers serialize
writers and provide a trusted, stable parent directory for the read-check-replace
interval. Plans are caller-owned, singly linked regular files; ACLs, extended
attributes, ownership, and special mode bits are outside this replacement
contract. A post-rename directory-sync failure reports
`plan_committed_durability_unknown` with the new digest: re-read before deciding
whether to retry, because the target has already changed. A stdout pipe that
closes before the success receipt is delivered likewise reports
`plan_committed_receipt_lost` on stderr with a nonzero exit: the update is
committed, only the receipt was lost, so re-read the plan instead of retrying.

Each self-review row may name a direct sibling skill. Omission selects the
`code-review` baseline. The controller also derives owners deterministically
from changed `skills/<name>/` paths, test paths, and supported source extensions.
With an implementer-supplied plan, every derived owner must have a self-review
row before provider execution, and missing owners are incomplete self-review. A
derived-default plan carries no implementer attestation to check against, so it
waives that pre-attestation requirement while still selecting and loading the
derived owners for the reviewer. The controller binds regular `SKILL.md` plus
recursive `references/**/*.md` and reports
`owner_selection_source=controller-derived+implementer-declared` when derivation
participates. Linked, inaccessible, or non-regular owner/controller content is a
terminal local integrity error.

Owner-aware wrappers receive only the canonical registry root, selected names,
and their frozen hashes. They verify that binding, use the already-installed
CCL skill registry through each client-native mechanism, and explicitly
name the selected owners: Claude `--plugin-dir`, Kimi `--skills-dir`, OpenCode
`skills.paths`, or Codex `$skill-name`. Skill bodies are never copied into the
review profile or prompt. Each successful owner-aware wrapper adds a
post-parse `native_skill_binding` receipt: `established` when the owners were
natively bound, or `unavailable` when the wrapper reviewed the packet without
owner skills because the installed registry or plugin could not be used (the
Claude wrapper degrades this way rather than refusing). A receipt saying
neither fails closed before the controller claims usage. Receipt injection itself is part of the
trusted wrapper path: a local serialization or output failure is terminal
`local_tool_failure`, never an empty or apparently successful result. After a
valid verdict, `reviewed_skills` contains only the selected owners passed
through the client-native invocation;
the general `code-review` baseline remains in `selected_skills` but is not
reported as natively invoked. The installed registry may remain visible. For
Codex, an independently updated installed package must exist and pass the same
safe-package validation, but its bytes need not equal an older candidate
branch; `$skill-name` binds the selected identity. The frozen source hash still
binds controller routing and review-chain reuse, not the host release version.
For Claude, the wrapper verifies the selected package hashes against the
installed registry, loads that plugin through `--plugin-dir`, and explicitly
names the owners; what the public init surface enumerates is vocabulary and is
not read. Loading the plugin is binding evidence, not proof that the model read
a skill body. `skill_usage_evidence` records native explicit invocation with
`observed=false` after an `established` receipt and `controller-profile` after
an `unavailable` one; only a public client event/export may populate
`observed_skill_usage`. Reviewer prose and private client databases do not
count as observation evidence.

For every client, `native_skill_binding=established` means the wrapper verified
the frozen selected packages and emitted that client's native explicit-invocation
syntax. It does not assert internal activation; that stronger claim belongs only
in `observed_skill_usage`.

This binding check also applies to direct wrapper calls. If a native-installed
profile selects owners but the matching registry root or owner arguments are
omitted, every wrapper returns terminal `binding_mismatch` before inference.

Owner-aware Claude requires `--safe-mode`; `--plugin-dir` is added only when
the installed registry verifies and the plugin manifest exposes only the
`./skills` entrypoint, so ambient customizations stay disabled while the
installed plugin supplies skills and normal OAuth/keychain authentication
remains available; otherwise the run proceeds without owner skills and attests
`native_skill_binding=unavailable`. The wrapper must not add `--bare`, because
that flag disables the ordinary OAuth/keychain path and turns a logged-in CLI
into an auth failure unless a separate API key is injected. A manifest declaring
top-level agents, commands, hooks, or MCP servers is not loaded.

Wrappers keep an explicit selected-owner count instead of testing empty Bash
arrays under `set -u`, preserving the no-owner lane on Bash 3.2.

### The claim-strength walk, and why the late correction is not cheaper

`claim_strength` is a required self-review concern at build and release depth. The
plan walks the candidate's load-bearing claims — absolutes, universals, causal
statements, exhaustiveness — and for each one either names evidence that would
survive a challenge or weakens the claim on the spot. It is owed before round 1
because that is the only point in a round where correcting a claim is free: once a
round binds the candidate, an edit inside a selected owner package voids every
receipt bound to it, so a sentence that claims too much costs exactly what a changed
predicate costs. The concern also reaches the reviewer, so a claim that survives the
walk comes back as a round-1 finding — inside the fix batch the round was going to
pay for anyway — rather than at closeout, where the remaining moves are a fresh chain
or leaving it standing.

There is deliberately no cheap late path. The proof-bound single review
(`wording-only-review.md`) refuses any changed non-punctuation character, which is
exactly what weakening a claim is, and an exception keyed on the author's own "this
edit only weakens a claim" is an assertion the controller cannot re-derive — a waiver
of that shape was carried here once and removed, because a predicate that approximates
meaning keeps admitting shapes it did not anticipate. The price stays uniform in both
directions; the walk is what moves the correction to where the price is zero.

## Base-derived packet input boundary

`--base` freezes the tracked diff plus every non-ignored untracked path in
scope. Exact-candidate binding means the controller never skips an untracked
path or replaces its contents with a placeholder. An untracked path containing
a Unicode control or line-separator character, symlink, hardlink, other
non-regular file, NUL-bearing file, non-UTF-8 file, or file over 200,000 bytes
makes the whole lane fail before provider execution with
`reason_code=invalid_input`. The same result applies when rendered untracked
content or the combined tracked-plus-untracked packet exceeds 200,000 bytes.

Move an out-of-scope path outside the candidate or add a correct ignore rule;
commit an in-scope path when Git should represent it; or compose complete
`--diff-file` partitions when the candidate must be split. Never omit a path
and report the remaining packet as the whole candidate.

## The packet and the candidate

They are two objects. The **packet** is what the reviewer reads; the **candidate**
is what will land. A receipt records both hashes; a caller that needs the landing
tree to equal a reviewed candidate compares against the recorded candidate hash.

They hold the same value when the packet came from `--base` alone. Pass
`--diff-file` **with** `--base`/`--paths` to widen what the reviewer reads while
the round still binds the landing candidate — the shape an evidence-gap finding
needs, since editing the candidate would answer an input defect with a candidate
change. `--diff-file` alone binds no landing; only the combined form rejects a
`--wording-only-proof-file`.

What makes the widened form safe is a **prefix requirement**: the packet begins
with the base-derived candidate, byte for byte, so nothing lands unread.

- **Append context after the candidate diff.** Putting anything before the
  candidate fails, and that is not cosmetic: a packet preceding it with a decoy
  diff would read as the change while the real candidate read as context.
  Interleaving context inside the candidate fails, as does dropping any part of
  it. The reviewer is told where the candidate ends — the profile carries
  `candidate_bytes` and states that exactly the first N packet bytes land — so
  appended hunks that continue or seem to revert the diff cannot pass as it.
- **Keep the packet file outside the repository, and put nothing else in the
  tree while the rounds run.** The controller counts every untracked path into
  the candidate; the binder counts only committed content minus the receipt JSON
  a round adds. A packet file, a superseded round's receipt, or any scratch
  artifact in the worktree therefore moves the candidate the rounds bind and the
  binder never computes it — the mirror of committing a plain-text attestation
  after the rounds. Bound evidence lands before the rounds, receipts after,
  nothing else present.
- **Read the candidate identity, do not reconstruct it.** `--print-candidate`
  is the authority: its base is a fork point, its paths carry the round's
  exclusions, and it refuses an uncommitted tree.
- Worth adding beyond the diff — the canonical rule the changed lines must not
  contradict, sibling clauses, the carriers restating the change, gate output.

Rounds in one chain agree on the **candidate**, not the packet, which lets a
later round read more than an earlier one.

## Proof-bound wording-only single review

The wording-only exception — its depth limits, the proof schema, the accepted
packet, the recipe that produces both, and how a valid result is read — is
specified in `wording-only-review.md`.

## Agent review chain

Multi-round Agent automation supplies `review_chain_id`, a contiguous
`autonomous_review_index` in `1..5`, and every earlier result through ordered
`--prior-review-result-file` arguments. Prior rounds may contain findings and
older candidate hashes; they remain consumed. Candidate edits, commits, plan
refreshes, mode changes, and renamed invocations never erase spending or broaden task authority.
An initial `review` with positive challenge capacity must start this chain at
index 1; an untracked initial review is single-round and therefore uses budget 0.

**Chain succession.** A fix that edits a selected owner's package moves
`selected_skills_sha256` and ends its chain by construction, so the post-fix
candidate can never be challenged inside it. One succeeding chain may open at
index 1 in `challenge` mode by supplying `--predecessor-chain-result-file` — the
ended chain's terminal receipt — instead of an in-chain prior result. The
controller accepts it only when that receipt is the tracked round its chain ended
on — a terminal challenge, or a round-1 review whose own
arithmetic still reports its challenge unspent — carrying this chain's
`review_scope_sha256` and matching
stage/depth/risk-tags/budget, preserves the controller digest, owner-selection
source, and selected owner names, and binds a candidate that DIFFERS from this
packet: the owner-package digest is the one binding allowed to move, because its
move is why the chain ended, and an unmoved candidate is a repeat round wearing a
new chain id. Earlier challenge focuses carry forward, so a succession focus must
differ from every focus the ended chain spent. The result records
`predecessor_chain_id`, `predecessor_result_sha256`, and
`predecessor_candidate_sha256`, and counts `material_candidate_change` as a
satisfied self-review trigger. Succession carries history rather than resetting
it: consumers still sum rounds across both chains.

A chain ends where the candidate moves, and a fix applied straight after the review
moves the owner digest exactly as one applied after the challenge does. Requiring a
challenge receipt here never protected the landing candidate — the succession
challenge binds that either way — it only forced the challenge to be spent on a
candidate the author had already decided to replace. The single class that stops
being owed is a challenge on a candidate that will never land, which carries no
evidence about the one that does; every other binding is unchanged, the candidate
must still have moved, succession still does not compose, and this path spends
fewer rounds than the old one, never more. What bounds it is the receipt's own arithmetic, and that is a
forgery guard rather than a history check: a genuine round-1 review reads the same
whether its chain later ran a challenge or not, so a caller who spent the challenge
and presents only the review is accepted, and the successor inherits no challenge
focuses — a focus that chain did spend can be spent again. This is the same
omitted-history boundary the rest of this contract states rather than a new one, and
the closeout validator's ordered receipt set is where a retained challenge receipt
would show it; no check at the succession call site can close it, and none is
claimed.

The chain binds task scope, candidate identity per round, result hashes, mode,
status, challenge focus, controller, and selected owners. The opaque
`review_scope_sha256` always hashes normalized intent, acceptance, stage/depth,
risk tags, challenge budget, and the wording-only proof/scope digests (both
`null` outside that exception); chain identity is validated separately. This
prevents deleting or nulling the top-level wording-only fields from reclassifying
that receipt as a normal completion input. Every result also carries the
canonical `review_scope` object that digest is taken over — intent and
acceptance appear only as `intent_sha256` / `acceptance_sha256`, never as raw
plan text, because results are logged and archived independently of the plan. A prior result is accepted only when its
recorded `review_scope` reproduces its own `review_scope_sha256` and that digest
matches the current scope, so copying a digest onto a differently-scoped result
no longer passes. This binding proves internal consistency, not authority: prior
result files are unauthenticated, so a caller able to rewrite an entire envelope
consistently is still accepted, per this gate's trusted-local-agent trust model.
Envelope `schema_version` is `3`; a legacy `2` envelope predates the recorded
scope and is rejected, which requires restarting an in-flight chain. Every
prior round must retain the same controller digest, owner-selection source,
selected owner names, and selected-owner digest. Missing, substituted,
inconclusive, reordered, renamed-chain, or over-budget input fails before any
provider runs. Scope drift returns `review_scope_changed` and requires deep
self-review plus explicit task reframing; it does not silently create a new
Agent budget. An untracked challenge is one-off advisory evidence; it cannot
enter a later Agent round or satisfy the local completion checkpoint.

Two consequences follow from those stable bindings and must be planned for before round 1:

- The selected-owner digest hashes each selected owner package's current working tree, and owners derive from the candidate's own paths — so a candidate edit inside any selected owner package invalidates every prior receipt and the next tracked round fails `review_chain_invalid`. For a self-hosted candidate (a skill-repo diff editing the package that owns it) that is nearly every applied fix — one confined to files outside every selected owner drifts only the candidate hash and may continue in-chain: in-chain tolerance for older candidate hashes applies only while fixes stay outside selected owners. Necessary recovery uses fresh bindings after the task checkpoint below.
- A chain restarted after such a break never erases cumulative spending or task history. An existing task includes necessary fixes, tests and review by default. At exhaustion, first disposition findings from source, run deep self-review and tests, and change the failed method or add missing evidence before another necessary bounded sequence. Record `continuation_basis=existing-task-scope`, the original authority reference and scope, the reason and changed method/evidence, cumulative rounds, and old/new sequence links in the caller-owned task artifact. Preserve every earlier receipt, focus and disposition; do not add this field to CLI arguments or runtime receipts. Existing per-chain and consuming-owner sequence bounds still apply; the extraction recipe remains in its dual-track gate reference. No repeated calls solely to obtain an empty verdict, invented human round requests, history reset or ignored user cost/round/stop limit is allowed.

The controller is stateless and prevents accidental/cooperative resets only. A
trusted host or platform must retain the ledger when hostile local callers are in
scope; a repository-local counter cannot authenticate human authority.

## Mechanical self-review gate

Every stable result that reaches the gate's composite stage includes
controller-owned `self_review_gate` (a freeze-stage argument-validation
envelope — for example `invalid_input`, or the argument-combination variant of
`completion_checkpoint_invalid` raised before profile freeze — carries
`schema_version` but may omit `self_review_gate`, `review_state`, `stage`, and
`attempts`; consumers must not read those fields unconditionally on every
exit-2 result):

- `required_triggers`: outstanding deep-self-review checkpoints;
- `satisfied_triggers`: checkpoints validated by the current plan;
- `blocks`: only the next external review and/or a completion claim;
- `allowed_next_actions`: productive work that remains legal.

The controller fires at these boundaries: before external review, findings
returned, candidate change in a tracked chain, risk/scope escalation, post-budget
checkpoint, and before a completion claim. Findings never produce a blind
review-fix-review loop: they block another reviewer call, return to implementer
triage, and still allow implementation, tests, and independent runnable work.

**Findings that come back are a design question.** When a round returns findings and
the history it carries already holds one — an earlier round of this chain, or the
predecessor chain a succession names — the gate adds
`recurring_findings_design_check` to the required triggers and
`decide_keep_delete_narrow_replace` to the allowed actions. It blocks nothing that
`findings_returned` does not already block; what it adds is the question the next
patch would walk past: whether the reviewed surface should exist in this shape at
all, answered as `keep`, `delete`, `narrow`, or `replace`, resting on the rounds and
findings it recurred across, and ratified by a risk owner other than the one
proposing it. `../../skill-extraction-workflow/SKILL.md` owns that rule; this is where
it fires, because the situation arises inside a chain and that skill is usually not
loaded there. Two findings rounds need not share a class, so the trigger over-fires
by design — answering an inapplicable question costs a line, and the round it saves
does not.

The count is what the controller can prove, and no more: the rounds of this chain plus
the predecessor a succession names, which is why the trigger reaches across a chain
break at all (Chain succession, below). Succession does not compose, so a third chain
opened fresh carries no history and the recurrence becomes the round's own record.

A passed final external round returns
`next_action=deep_self_review_before_completion` and remains
`completion_gated=true`. `--mode complete` accepts one exact-candidate passed
review result plus the current self-review plan, calls no reviewer, rejects stale
candidate/controller/owner bindings and changed intent or acceptance, while
allowing refreshed self-review conclusions and evidence, and is the Agent path to
`completion_gated=false`. Its result preserves the verified chain id, scope,
round index, prior-result hashes, and prior challenge focuses. It is not a human
waiver or merge authorization.

For an unchanged candidate with a conclusive tracked review and challenge,
`complete` also accepts `--finding-dispositions-file`. Supply every earlier raw
receipt with ordered `--prior-review-result-file` arguments and the final one
with `--completion-review-result-file`. The UTF-8 JSON has `schema_version: 1`,
`candidate_sha256`, ordered `review_result_sha256` hashes including the final
receipt, and `dispositions`. Each disposition contains `receipt_sha256`, the
canonical-JSON `finding_sha256`, `disposition: "source_refuted"`, and a non-empty
`evidence` array naming the first-hand source or failure-path counter-evidence.
Every original finding occurrence must appear exactly once. Within one receipt,
findings with identical canonical content share one hash-pair identity in
first-seen order; retain every raw entry unchanged. Different content or a
different receipt remains a separate occurrence. Missing history,
changed candidates, inconclusive results, open findings and risk acceptance do
not qualify. A code fix with changed bytes requires renewed review.

This local checkpoint records `completion_basis=source_refuted_findings`, the
dispositions digest and resolved occurrence bindings; original external
findings remain unchanged. A clean external result uses `external_pass`.
Validation proves binding and coverage, not the truth of an evidence statement:
the implementer must trace the cited source, and the judgment remains open to
challenge. No budget is refreshed and no model is called. At the review cap,
finish this local work instead of requesting another round solely to obtain an
empty verdict. Unresolved findings still block completion, not independent work.

## Human and failure boundary

Existing task scope covers necessary continuation; exhaustion alone creates no new grant.
Only an external authenticated platform action may prove new human request, stop, resume, waiver, commit, or merge authority. A `review_waiver` clears only the
review-process gate. A distinct exact-candidate `merge_authorization` is the
human's final decision: CI may keep running and reporting every failed/pending
gate, but none may block that authorized merge. Report
`merge_authorized_by_human` / `failed_but_human_overridden`, never `passed`.

Provider/input/integrity failures stop that reviewer lane, not the whole task.
Their stable action is `stop_reviewer_lane`, never the ambiguous `stop`.
Budget exhaustion triggers the method/authority checkpoint, not an automatic user handoff. Check legacy
`human_decision_required` / `continuation_authorization_required` against existing task scope first.
Continue necessary bounded review; enter `awaiting_human` only for a genuine missing decision, explicit user limit or authority outside that scope.

The current result envelope is schema 3. The generic per-invocation `--timeout`
keeps its 600-second default and accepts 5..1200 seconds; direct wrappers clamp
higher decimal values, including values beyond shell integer range, to 1200.
Wrapper-internal sub-mode limits such as Kimi inline mode's 120-second cap stay
separate. The controller bounds cumulative reviewer-lane execution with `--total-timeout`
(default 2400 seconds, accepted range 5..3600). Setup time reduces the budget,
and git preflight subprocesses share its deadline; direct filesystem reads
remain subject to the host's outer timeout. Each client receives the smaller of the requested per-invocation
timeout and `(remaining total budget - ten controller seconds) / maximum mode
invocations`; review reserves two invocations and challenge one. If that
allowance is below five seconds, the gate returns inconclusive `gate_timeout`
and starts no later client. Each wrapper lane is separately bounded by its
mode-adjusted allowance plus controller headroom. A lane timeout gets bounded
TERM/KILL/final-reap cleanup and may cascade while total budget remains; killed
or partial output is never a verdict. A verdict that arrives after total expiry
is cleared; prior findings remain only in diagnostic `unbound_findings`, which
must not be treated as a verdict. Before setup overhead, the practical minimum that can
start a lane is 21 seconds for review and 16 for challenge; smaller accepted
values intentionally fail closed.
