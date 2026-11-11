# Usage census and slimming proposal

Corpus: every Claude transcript on one machine, 2026-10-21 to 2026-10-23. That is three days, the machine's whole history: 55 sessions, 42 with source edits, a few repositories concentrated in one product domain. Single user; rare paths such as release or destructive change are judged by mechanism, not frequency. Codex transcripts are not included. "Never read" below means never read in those three days, which is weak evidence for rarely needed references.

## Census

### Loads

| Skill | Loaded (sessions) | Loaded before the first source edit |
| --- | --- | --- |
| `product-rd-workflow` | 27 | 26 |
| `python-service-dev` | 14 | 6 |
| `nodejs-service-dev` | 14 | 11 |
| `go-microservice-dev` | 2 | 0 |

By the language each session actually edited, the stack skill was loaded before the first edit of that language in:

| Stack skill | Sessions editing that language | Loaded first | `product-rd-workflow` loaded first |
| --- | --- | --- | --- |
| `python-service-dev` | 12 | 11 (92%) | 8 (67%) |
| `go-microservice-dev` | 2 | 2 | 2 |
| `web-react-dev` | 6 | 4 (67%) | 3 (50%) |
| `nodejs-service-dev` | 22 | 11 (50%) | 12 (55%) |

The stack skills are mostly loaded when they apply; `nodejs-service-dev` is the gap. Some `.ts`/`.js` edits belong to web or tooling code, so part of that gap may be correct routing.

### Reads and citations

- `product-rd-workflow` has 35 references; 32 were never read in the window. `implementation-entry-reentry-gate.md` was read in 5 sessions, two others in 1 each.
- The go and python skills have 27 and 20 references; none was read in the window.
- Ten rule names from the `product-rd-workflow` entrypoint appear about 51 times each in injected skill text and hook output, and 4 times in total in the agent's own visible reasoning and replies (about 0.9 M characters of visible reasoning, 1.8 M of replies). Agents may restate a rule in Chinese without its English name, so this undercounts use; it does show the names are not what agents reason with.
- The owner-dispatch rule fires through hooks: its text appears 148 times in tool results. The mechanical part works independently of the prose.

### Size and anchors

The entrypoint is 73 KB in 51 rule units. The largest:

| Unit | Bytes | Test or script pins |
| --- | --- | --- |
| Non-UI verification binds to the action | 12.9 K | 4 |
| Implementation completeness/minimality gate | 4.6 K | 15 |
| Diagnostic spec-match baseline gate | 4.6 K | 2 |
| Enforce quality gates (step 4) | 4.5 K | 5 |
| Artifact-egress confidentiality gate | 4.0 K | 1 |
| Route responsibilities (step 2) | 3.9 K | 0 |
| Go straight to the owning skill instead | 3.4 K | 0 |
| Implementation entry / re-entry gate | 2.9 K | 9 |
| Reference Loading | 2.9 K | 1 |
| Concurrent-session isolation | 2.5 K | 1 |
| Existing Project Assessment | 2.1 K | 7 |
| Pre-Final Continuation Gate and its steps | 7.0 K in 8 units | 14 |

24 of the 51 units carry 89 phrases that tests, hooks or install scripts quote verbatim. Moving or rewording those phrases means moving their pins in the same change.

### Wider corpus

The same census script, run on the owner's main machine (2026-09-13 to 2026-10-23: 1,155 Claude sessions, 239 with source edits; 3,250 Codex sessions, counted only), supersedes the three-day figures above where they differ:

| Stack skill | Sessions editing that language | Stack skill loaded first | `product-rd-workflow` loaded first |
| --- | --- | --- | --- |
| `python-service-dev` | 102 | 65 (64%) | 47 (46%) |
| `nodejs-service-dev` | 149 | 43 (29%) | 56 (38%) |
| `web-react-dev` | 53 | 32 (60%) | 17 (32%) |
| `go-microservice-dev` | 7 | 6 | 5 |

- References read in the window: `product-rd-workflow` 13 of 35 (118 reads); `go-microservice-dev` 0 of 27; `python-service-dev` 1 of 20; `nodejs-service-dev` 0 of 4; `web-react-dev` 0 of 6.
- P0/P1 categories over 2,062 findings (multi-label): failure path 42%, concurrency 35%, money/permission/data loss 30%, cross-module contract 22%, retry/idempotency 21%, lifecycle 16%, review-packet noise 13%.

So the stack skills are loaded before the first edit in only 29% to 64% of the sessions that edit their language, their references are effectively never read, and the hazard classes are stable across the wider corpus. Part of the `nodejs-service-dev` gap is `.ts`/`.js` code that is not service code.

## Proposal

Goal: entrypoint from 73 KB to about 25 KB with no gate lost, and the engineering-hazard checks placed where code is written.

### A. `product-rd-workflow` entrypoint

| Action | Units | Reason |
| --- | --- | --- |
| Keep, compress to a trigger line plus pointer | Implementation entry gate; owner-dispatch firing gate; completeness/minimality gate; Pre-Final Continuation Gate (as a numbered list); `DFE-CONT`; artifact-egress trigger | Hooks or pins depend on them; the detail already has or gets a reference. |
| Move to an existing or new reference | Non-UI verification (12.9 K); spec-match baseline; Existing Project Assessment; Feature Deprecation; optional Feishu record; External Skill Augmentation; mechanism-operability check | Never cited by name; detail belongs one level down. Pins move with the text. |
| Merge into the owner | Concurrent-session isolation (owned by `worktree-isolation` and the session-start Isolation line) | Same rule stated twice; its extra clauses (no unreviewed commit to dodge clobber, pre-merge freshness gate) move to `worktree-isolation` if missing there. |
| Shorten | "Go straight to the owning skill" block; Route responsibilities (step 2); Enforce quality gates (step 4); Reference Loading | The "go straight" block partly repeats session-start routing and the authorship rule; it also holds the shared-gate re-entry exception and the multi-repo status-ledger rule, which stay. Keep routing tables, drop restatements of sibling skills. |

Every move carries a zero-loss obligation map: each obligation before the change maps to surviving text or a reference, and each of the 89 pins follows its phrase.

### B. Stack implementation skills

The stack skills are often not loaded before the first edit, and when they are, their hazard detail sits in references nobody reads, while the most frequent reported P0/P1 classes are failure paths, concurrency, money/permission and retry/idempotency. Add to each stack entrypoint, near the top, a short pre-edit check for changes that touch shared state, external calls, retries or money: list the states, who writes each, and what happens on a lost response, a duplicate, reordering and a timeout, with one test per row. Keep it under 1 KB per skill and point to the existing references for depth. Because the stack skills load before the first edit in only 29% to 64% of the relevant sessions, the check also needs a firing point that does not depend on the agent choosing the stack skill: the existing first-source-edit checkpoint is the candidate. For `nodejs-service-dev`, separate service code from web and tooling `.ts`/`.js` edits before changing its routing.

### C. Validation before any live trial

1. Each edit step owes the full extraction gate: review, challenge, a behavioral-evidence row and the zero-loss map.
2. Offline comparison with `claude plugin eval`: replay 5 to 10 past changes with the current and the slimmed skills, and compare reported P0/P1, time and tokens. A slimmed skill that does worse is not landed.
3. A live trial starts only after the review-budget trial ends on 2026-11-06, so the two results stay separable.

## Open questions for the owner

- Is about 25 KB the right target, or should the entrypoint go further toward routing only?
- Should A and B land together or as two changes? Two changes keep the offline comparison readable.
