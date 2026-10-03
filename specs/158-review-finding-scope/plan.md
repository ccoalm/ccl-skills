# Reviews check scope against the requester's own words

Status: implemented. Measurements are in
[validation evidence](evidence/validation.md); review passes and the
verification lanes are in [dispositions](evidence/dispositions.md).

Artifact classification: gate implementation. Risk tag: shared-gate. The
change edits the reviewer lens the review controller sends with every build and
release review, the plan guidance that tells implementers what the review packet
carries, the manual review prompt, and the design review gate. It grants no
authority and changes no plan schema, concern ID or CLI flag.

## Observed failure

In a four-day window of interactive sessions, users corrected over-grown work in
about nine sessions: a configuration switch nobody asked for, a "hotfix" that
reached dozens of files, permission and staged-rollout machinery around a
request for a record of differences, manual review steps added to an automatic
flow. In two of them the growth had passed an independent review: a plan review
approved a design that turned an observation-only request into a blocking gate
with credentials, a staged enforcement rollout and an admin override; another
review's open questions were written into a hotfix plan as launch preconditions.
Both reviewers saw only the implementer's restatement of the goal.

## What was measured

Registered remedies were treated as hypotheses and replayed before any edit
(`evidence/`):

1. Triage when review findings arrive (fix only what the change introduced or
   the goal covers). Replayed clean, with accumulated scope momentum, on Claude
   and Codex, with and without the review-reception partition rule loaded:
   every arm fixed only the introduced defect. The isolated decision is already
   right; no change was made for it.
2. A scope lens on a diff whose intent states the narrow request: the current
   concern text already flagged the extra code paths in every run, so that part
   is a control. Only the new text called the configuration switch unrequested
   (0/4 runs before, 4/4 after).
3. A plan review of the over-designed plan, re-created in a neutral domain. With
   only the implementer's restatement, no reviewer questioned the gate, and the
   findings hardened it instead (bound the override, gate the downloads too).
   With the requester's words in the intent, every run flagged the gate as
   contradicting the request. The new concern text added the rest: the admin
   override and the staged rollout named as unrequested in every run. On a plan
   that matches the request, the new text raised no scope finding, and no run
   called a requested fix of an older defect droppable.

## Change

- `skills/code-review/scripts/review_gate.py`: the build and release
  `compatibility` concern now asks the reviewer to check scope against the
  requester's own words when the intent or focus quotes them, and to report each
  switch, flag, gate, permission, rollout restriction, compatibility layer,
  manual step or abstraction the request does not need, and each fix for a
  pre-existing risk that the request does not cover and the change does not
  expose or worsen.
- `skills/code-review/references/development-completion.md` and
  `staged-review-contract.md`: the plan's intent quotes the requester's own
  words verbatim ahead of the restatement; the derived default carries them in
  `--focus`.
- `skills/code-review/references/manual-invocation-and-prompts.md`: the review
  prompt template has a slot for the requester's words and the scope item.
- `skills/product-rd-workflow/references/design-review-gate-mechanics.md`: the
  design review packet must quote the requester's words and ask for the scope
  check first.

## Not changed

Concern IDs, the plan schema and `--print-required-concerns` output are
unchanged, so existing plans and fixtures stay valid. The review-reception
partition rule, a triage note in the controller result, `defect-diagnosis` and
the session policy are unchanged: their registered forms did not reproduce. The
direct `claude_review.sh` prompt has no intent to check scope against and keeps
its text.

## Acceptance

| Input | Expected | Test |
| --- | --- | --- |
| Build and release review profile | `compatibility` asks for the scope check against the requester's own words | `test_review_gate.sh` (absent on the base controller) |
| Concern IDs and required-concern output | Unchanged | `test_review_gate.sh` existing cases |
| Over-designed plan, restatement only vs requester's words with the new text | Gate questioned only with the words; override and rollout flagged with the new text | `scope_anchor_replay.py` (evidence) |
| Plan that matches the request, new text | No scope finding | `scope_anchor_replay.py --matched` (control) |
| Over-grown hotfix diff, new text | The configuration switch is called unrequested | `reviewer_scope_replay.py` (evidence) |
| Derived-default review with `--focus` | The words reach the reviewer profile and a fallback reviewer; a credential-shaped value blocks non-Claude egress | `test_review_gate.sh` (pins existing routes; mutated controller copies fail them) |
| Request to fix a defect that predates the change, plan that fixes exactly it | No run calls the fix droppable | `scope_anchor_replay.py --requested-fix` (control, both wordings) |
| Docs | Intent quotes the words; `--focus` for the derived default; manual template; design gate packet | review |
