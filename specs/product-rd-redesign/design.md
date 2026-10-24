# Product-rd redesign: design

## Evidence that shapes the design

Owner's main machine, 2026-09-13 to 2026-10-23 (1,155 Claude sessions; `product-rd-workflow` loaded in 139):

- Of 51 rule units, only "Pre-Final Continuation Gate" is named in agents' visible reasoning or replies with any frequency (33 sessions), and a stop hook enforces it. "Technical design gate", "Enforce quality gates" and "Human/team sign-off" appear in 2 to 3 sessions. Every other unit appears in 0 or 1.
- 22 of 35 references were never read. The most-read reference, `implementation-entry-reentry-gate.md` (11 sessions), is the one a hook names at the first source edit.
- In the stack hazard experiment (32 runs per arm), added entrypoint prose did not change agent behavior.

Rules hold when a mechanism fires them at the moment of action. The redesign therefore keeps every mechanised gate prominent and short, keeps rare but high-blast-radius rules as one-line triggers that name their reference, and moves everything else out of the always-loaded text.

## Mechanism inventory

| Gate | Mechanism that fires it | Owner of the mechanism |
| --- | --- | --- |
| Implementation entry / re-entry gate | `hooks/skill-loading.py` first-source-edit checkpoint; `hooks/task-entry.sh` | product-rd |
| Owner-dispatch firing gate | `hooks/owner-dispatch-guard.sh`, `hooks/owner-dispatch-stop.sh`, `scripts/owner-dispatch/` (opt-in per repo) | product-rd |
| Pre-Final Continuation Gate and the continuation-proposal contract | `hooks/proposed-next-stop.sh`; `hooks/host-input.py` reads the contract paragraph verbatim | product-rd |
| Review covers the final candidate | `hooks/remind-review-covers-head.sh` | code-review |
| Edit isolation, merge authorization | `hooks/guard-edit-isolation.sh`, `hooks/guard-merge-authorization.sh` | worktree-isolation |
| Delegation owner load | `hooks/guard-delegation-owner.sh` | multi-agent-delegation |

Anchors that must survive verbatim: the `**Continuation-proposal output contract (session-wide for product delivery).**` paragraph (read by `host-input.py`), and the names `Implementation entry / re-entry gate` and `Owner-dispatch firing gate` (named by the always-on Transitions line).

## New entrypoint shape (target 20 KB or less)

1. Frontmatter: unchanged. The description is the routing surface; changing it is a separate routing decision outside this round.
2. Purpose and entry precedence: three sentences.
3. Continuation-proposal output contract: verbatim (hook anchor).
4. Routing table: request type → owning skill, one row each, including the "go straight to the owner" cases, the shared-gate re-entry exception, and the authorship rule for process-skill suggestions.
5. Hard gates, each as one block with four fields: trigger, required action, what checks it, reference. Mechanised gates first.
   - G1 Implementation entry / re-entry gate (boundary record before the first implementation edit).
   - G2 Owner-dispatch firing gate (multi-owner designs; owner set before design substance).
   - G3 Test-first and verification by layer, with the only closeout labels `complete`, `pre-runtime-test-ready`, `blocked`, and no shared push or MR until required layers are green on the final state.
   - G4 Technical design review for cross-repo, multi-client, external-contract or high-risk work, including shared deterministic gates through `feature-risk-router`.
   - G5 Visible surface: `product-ui-ux-design` before the first edit, or `visible surface: no` with a reason.
   - G6 Pre-Final Continuation Gate: the six steps as one-line items, with `DFE-CONT` and assent binding named.
6. One-line triggers for rare, high-blast-radius rules, each naming its reference: artifact egress confidentiality, high-risk resilience, implementation completeness and minimality, spec and repo-contract sync, cross-repo coordination, feature deprecation, dormant code activation, existing-project assessment, quality remediation program, diagnostic spec-match baseline, R&D standards doc family, algorithm launch, developer-facing surfaces, user-visible tips and notices, multi-repo status ledger.
7. Non-negotiables, one line each: no weakened tests, no fabricated evidence, no completion claim without fresh evidence, landing labels need matching evidence, no direct push to a protected default branch, no workaround reported as a fix.
8. Reference map by trigger.

## Disposition ledger

Status values: `gate` (stays in the entrypoint as a hard-gate block), `trigger` (one line in the entrypoint plus its reference), `routing` (folded into the routing table), `move` (text moves verbatim or near-verbatim into a named reference), `owner` (stated by another skill; the entrypoint keeps a pointer), `retire` (removed with the reason given; owner-approved category).

| Lines | Unit | Status | Destination or reason |
| --- | --- | --- | --- |
| 6–10 | Purpose, entry precedence | gate | Section 2, shortened. |
| 12 | Continuation-proposal output contract | gate | Verbatim; `host-input.py` anchor. |
| 14 | Restart/redo of an in-flight delivery | routing | Routing row; mechanics already in `implementation-entry-reentry-gate.md` §Baseline Selection. |
| 15–19 | Implementation entry / re-entry gate | gate | G1; the four sub-bullets compress to the boundary-record field list; full text stays in the reference. |
| 20 | Go straight to the owning skill | routing | Routing rows, keeping the shared-gate re-entry exception. |
| 21 | Process-skill suggestions do not replace entry | routing | One routing note with the authorship test. |
| 22 | Delegated execution | owner | `multi-agent-delegation`; pointer row. |
| 23 | Multi-repo delivery-status ledger | trigger | One line; `status-tracker-sync.md` already holds schema and rules. |
| 24 | Precedence order | gate | One sentence in section 2. |
| 28 | Product shaping, acceptance-coverage matrix | move | `delivery-lifecycle.md` §Product Shaping Checklist (already holds the detail); routing row to requirement owners. |
| 29 | Implementation completeness/minimality gate | trigger | One line; `implementation-completeness-and-minimality.md`; its pinned phrase stays in that line. |
| 30 | Requirement artifact routing, PRD Ready verdict | routing | Routing rows to the four requirement skills; Ready verdict ownership stays one line. |
| 31–38 | Design, architecture, development, quality, defect, research, assessment, algorithm routing | routing | Routing table. |
| 39 | User-visible tips and notices | move | `design-routing-and-readiness.md` new section; one trigger line. |
| 40 | Developer-facing surfaces | trigger | One line; `verify-developer-experience.md` holds the detail. |
| 41 | Artifact-egress confidentiality gate | trigger | One line, kept despite low usage because a miss leaks data; `artifact-egress-confidentiality.md`. |
| 42–44 | Learning loop, extraction routing, upstream decision propagation | owner | `skill-extraction-workflow`; one routing row. |
| 45 | Text artifact quality | owner | `tighten-doc`, which a stop hook already enforces; one routing row. |
| 46–47 | R&D standards docs, standards-to-health-gate | trigger | One line; `rd-standards-doc-family-checklist.md`. |
| 48 | High-risk resilience gating | trigger | One line; `high-risk-resilience-gates.md`; routes to `feature-risk-router`. |
| 50–57 | Generalization Discipline | retire, one rule merged | Lines 52, 53, 55 and 56 restate rules that already hold elsewhere: no project nouns (`skill-extraction-workflow` "do not extract business nouns" and "no business or source-repo leakage"), generic SOP versus project evidence (`tighten-doc` "Generic process docs should carry rules, gates, owners"), extraction routing. Line 54 (split a mined observation into mechanism, business noun and source quality or age) applies to building a new product from an old one, which those homes do not cover, so it merges into the internal-reference trigger line (rows 173–174). Line 57's precedence survives in G3 and the non-negotiables. |
| 61 | Stage-entry state checklist | trigger | One line; `delivery-lifecycle.md`. |
| 63–77 | Classify the work (14 bullets) | routing | Routing table; the diagnostic spec-match baseline and quality remediation program become trigger lines. |
| 79–100 | Route responsibilities (owner list) | routing | Routing table; duplicates of the owners' own descriptions are dropped. |
| 96 | Surface delegation when work becomes parallelizable | trigger | Its own trigger line, because the trigger is mid-delivery (two or more slices that look independent), not the first edit; the G1 boundary field still records the decision. The delegation hook fires only at dispatch and does not cover discovery. |
| 103–106 | Plan before editing, re-entry check, formal spec-plan decision | gate | G1 and `delivery-lifecycle.md` §Plan Authoring. |
| 104 | Optional Feishu requirement record | move | `delivery-lifecycle.md`; no trigger line (only on request). |
| 107 | Spec / repo-contract sync gate | trigger | One line; `sync-spec-repo-contract.md`. |
| 108 | Cross-repo feature coordination | trigger | One line; `cross-repo-coordination.md`. |
| 109–116, 118–119 | Technical design gate, owner ownership, owner-dispatch | gate | G2 and G4; sub-rules stay in `dispatch-owner-skills.md` and `design-review-gate-mechanics.md`. |
| 117 | Mechanism-operability check | trigger | Its own trigger line with both triggers: proposing new mechanical enforcement or verification machinery, and withdrawing or downgrading the evidentiary claim an existing mechanism rests on, at any scope; `design-review-gate-mechanics.md`. |
| 120–129 | Design review firing-point registry | move | `design-review-gate-mechanics.md`, which already holds the authoritative text; G4 names it. |
| 130 | Task plan for assessment-fix-verify | gate | G1. |
| 131 | Concurrent-session isolation | owner | `worktree-isolation` and `guard-edit-isolation.sh`; pointer. |
| 132 | Test-layer decision table | gate | G3. |
| 133 | Dormant code activation | trigger | One line; `dormant-code-activation.md`. |
| 134, 139 | Doc-family checklist label | trigger | Covered by the R&D standards trigger line. |
| 135 | Avoid unneeded documents | retire | Generic guidance with no mechanism; the plan-depth rule in G1 covers it. |
| 138, 140 | Work begun without a plan is a process defect | gate | G1. |
| 141–144 | No workaround, no weakened test, fresh evidence, no fabrication | gate | Non-negotiables; the completion evidence gate stays in `delivery-lifecycle.md` §Completion Evidence Gate. |
| 145 | `tighten-doc` before sharing | owner | `tighten-doc` and its stop hook. |
| 146–148 | Visible surface classification and readiness | gate | G5; detail stays in `design-routing-and-readiness.md`. |
| 149–157 | Non-UI verification binds to the action | gate | G3 keeps the action rule and the three closeout labels; the remaining text moves to `delivery-lifecycle.md` §Completion Evidence Gate. |
| 158, 163, 165 | Rendered and runtime evidence for clients | gate | G3 one line; detail to `delivery-lifecycle.md`. |
| 159 | UI quality challenge is a design defect | owner | `product-ui-ux-design`. |
| 160–162 | Test-case-first, verification match risk, layer report | gate | G3. |
| 164 | High-risk scenario matrix | trigger | Covered by the high-risk resilience trigger. |
| 166 | Live infrastructure kept separate | move | `delivery-lifecycle.md`. |
| 167–168 | Self-review then `code-review` | owner | `code-review` development completion and its hook; one line in G3. |
| 169 | Shared deterministic gate classification | gate | G4; detail stays in `shared-gate-artifact-classification.md`. |
| 170 | Landing labels need evidence | gate | Kept in the entrypoint as a compact definition list, not one sentence: `landed`, `MR-ready`, `release-ready`, `shared-status-ready` with their required evidence, and the local-status rule for exploratory slices. |
| 171–172 | Status docs and contract-sync evidence | trigger | Covered by the status ledger and spec-sync trigger lines. |
| 173–174 | Internal reference sanitization, inspect other branches | trigger | One trigger line for product artifacts built from an internal checkout: name only mechanisms, boundaries and acceptance gates, split observations into mechanism, business noun and source quality or age (from line 54), scan changed files for source identity before commit, and inspect nested repositories and other branches before declaring no evidence. These are product-artifact rules, not only skill-extraction rules. |
| 175–176 | Hosted platform, protected default branch | gate | Non-negotiables, keeping the specifics: separate transport from platform control plane and verify platform auth before trusting API errors; when the default branch is protected or its protection is unknown, land through branch plus MR; an accidental local commit on it moves to a branch and MR; MR creation is not merge authorization (`worktree-isolation`). |
| 177 | Verify a reference's core abstraction | move | `delivery-lifecycle.md`. |
| 179–186 | Close the loop | owner | `skill-extraction-workflow`; lines 181–182 fold into G6. |
| 188–199 | Pre-Final Continuation Gate | gate | G6; step text compressed to one line each, full text stays in `pre-final-continuation-gate.md`. |
| 201 | "Why did you stop" challenge | owner | `skill-extraction-workflow`. |
| 203–205 | External skill augmentation | trigger | One line; `external-skill-augmentation.md`. |
| 207–215 | Existing project assessment | trigger | One line plus routing row; section text moves to `existing-project-assessment-report.md`. |
| 217–219 | Feature deprecation | trigger | One line; `feature-deprecation-cascade.md`. |
| 221–233 | Reference loading | gate | Section 8, regenerated from the trigger lines. |

Retired outright: lines 52, 53, 55 and 56 of Generalization Discipline (homes verified above) and line 135. Line 54 merges into the internal-reference trigger line. Every other unit keeps a home in the entrypoint, a reference, or another owner. Implementation checks each `move` and `owner` row against the destination text in the review packet; a row whose destination does not already hold the obligation gets the text added there in the same change.

## Migration work

- Tests and checks that quote moved phrases (`test_ai_coding_implementation_gates.sh`, `check-ccl-skills.sh`, `test_pinned_phrase_mutation_walk.sh`, `hooks/test_proposed_next.py`, `test_routing_pointer_integrity.sh` and others found by the pin scan) are re-pointed to the file that now holds each phrase, never deleted.
- Sibling skills and the always-on layer that cite a moved section get their pointer updated.
- The specs/065 obligation ledger is re-rendered; any carrier that moves across files is handled through its mapping before landing, or the text stays put.

## Validation

1. Deterministic: all repository lanes green except the known host baseline failures; size budget shrinks; the disposition ledger above is checked row by row against the diff.
2. Dual-track review and challenge on the diff. The packet carries the old and new entrypoint, the hooks that read it, every destination reference, and this ledger, so each row can be checked against real text rather than taken on trust.
3. Behavior: the `evals-stack-hazard` hard suite, three runs per case on the redesigned branch. The baseline is the existing 24-run `main` result at 590eb29 from the stack hazard round (mean 0.760, code handles the hazard 17/24, $23.79). Pass requires all three: every case keeps at least `main`'s "code handles the hazard" count, where a case that loses any pass is rerun three more times and its six-run rate must be at least `main`'s three-run rate; mean score at least 0.710; total cost below $23.79. Any failed condition blocks the merge and sends the failing case back to the ledger.

## Open questions for the owner

- The frontmatter description stays as is in this round. Change it later as a separate routing round, or now?
- The retire list is deliberately short (one section and one line). Retire more aggressively, for example the low-usage references with no mechanism, or keep moving rather than deleting?
