# Extraction Quickstart — One-Page Flow

For maintainers running a fresh codebase / Figma / doc extraction. Read this first; deep references handle each step's detail.

## Flow at a glance

```
0. Charter        → ~/.<host>/skills/.extraction-work/<project>-charter.md
                    Purpose / Scope / Depth / Result baseline / Open questions
                          │
1. Source register → ~/.<host>/skills/.extraction-work/<project>-source-register.md
                    Each row: source id / class / status / target skill / extracted mechanisms
                          │
2. Batch plan      → B1..Bn in charter §Batch plan; one batch per problem domain, not time slice
                          │
3. Per-batch loop:
   ├─ a. Read sources to documented min depth
   ├─ b. Draft skill / reference (new or update existing)
   ├─ c. Sibling-generalization mini-map (which sibling skills may share / route)
   ├─ d. Sanitization pass with checklist (cheap, seconds)
   ├─ e. Owner review gate per mandatory table (deep, minutes)
   │     ├─ Strict wording-only → one independent code-review pass
   │     └─ Non-wording → extraction_review_gate review + at most two challenges
   ├─ f. Apply fixes, re-sanitize
   ├─ g. Commit per batch on a feature branch → MR pending review (never push to main)
   └─ h. Update charter completion log
                          │
4. Closeout       → ~/.<host>/skills/.extraction-work/<project>-completion.md
                    Non-wording terminal ledger validator + final state + deferred backlog
                          │
5. Provenance migration → ~/.<host>/.private-aliases/<project>.yaml
                    Move file keys / paths / counts / dates out of working files
                          │
6. (If lesson applies broadly) → patch skill-extraction-workflow itself
                    New anti-pattern → recurring-anti-patterns-checklist.md
                    New review angle → dual-track-review-gate.md
                    New workflow step → SKILL.md core rules
```

## Per-step quick reference

### 0. Charter (always)

- Owner: maintainer
- Location: `~/.<host>/skills/.extraction-work/<project>-charter.md`
- Required fields: Purpose, Scope, Depth, Result classification, matching analysis, Failure modes or success-reuse conditions, Lifecycle impact, Evidence plan, Completion standard.
- Result classification: failure/correction → Deep RCA (widen → counterfactual-test → control); stable success → mechanism + non-luck evidence + reuse conditions + firing point + owner; unstable/insufficient evidence → observation only.
- Full structure: `SKILL.md` Core Workflow Step 0.
- Output: a file the maintainer can re-read in 3 months and understand what they were trying to do.

### 1. Source register

- Owner: maintainer
- Each row: `source_id / class (A1/A2/B/C/D) / path / status (pending|read|deep-read|excluded|unavailable|routed) / min_depth / actual_depth / extracted_mechanisms / discarded_business_details / target_skill / evidence_link`.
- Full structure: `references/source-register.md` template; the shared file also contains source-neutral ledger rows, not project provenance.
- Discipline: every dimension has a status before any "complete" claim.

### 2. Batch plan

- Decompose by problem domain (observability / connectivity / release), not time slice.
- Each batch closes its own row in source register before the next batch starts.
- Charter section §Batch plan tracks status.

### 3. Per-batch loop

#### 3a. Read sources

- Respect min-depth from source register row.
- For source-read failures (timeout, branch missing, doc unavailable): apply remediation (smaller read, different branch, screenshot fallback) BEFORE marking unavailable.
- Reference: `SKILL.md` "Source-read remediation standard".

#### 3b. Draft skill / reference

- New shared skill → frontmatter with trigger-focused description.
- Update existing → minimal surgical edit; preserve existing content unless contradicted by new evidence.
- Reference files: `<verb>-<noun>.md` naming; entrypoint = `SKILL.md`.

#### 3c. Sibling mini-map (required for stack-specific extraction)

- Map: source stack → sibling stacks → shared workflow owner → per-sibling decision.
- For each sibling skill: `update / unchanged / route-to-shared` with reason.
- Don't skip even when "obvious"; documenting `unchanged` is part of the gate.

#### 3d. Sanitization (cheap)

- Run `references/recurring-anti-patterns-checklist.md` grep panel against changed files.
- The current checklist patterns (count grows over time as new anti-patterns are added); ~30 seconds total runtime for the full panel.
- Hits → fix in this commit, OR record `known_debt` in private alias map (pre-existing only).

#### 3e. Dual-track review/challenge

- When required: see `references/dual-track-review-gate.md` table.
- Choose the review tier from that table, not from intuition. Do not restate the rows locally; record the exact `dual-track-review-gate.md` table row used. Record `challenge: not-required` only when that row classifies the actual diff as challenge-not-required (for shared skills, this means strict wording-only with deterministic scope proof + independent review confirmation). Non-wording shared-skill changes cannot skip challenge.
- Run deterministic checks and implementer self-review first, and record what each proves before invoking review/challenge (this self-review-before-review ordering applies to every non-wording shared-skill change the dual-track table requires review for, not only the rows that look high-risk): `git diff --check` proves whitespace/conflict-marker hygiene only; validators prove schema/link/routing invariants; leakage/sanitization scans prove only their configured patterns; scope checks must name the changed files or expected file set; the self-review row is conclusive only when each required field is non-empty (acceptance criteria, changed-file scope, edge/failure paths, known residual risks) and the changed-file scope equals the candidate diff's changed-file set, or explicitly explains any excluded generated/irrelevant file. Persist it before the review/challenge run in a fresh, non-overwritten task-evidence path outside the candidate diff, pass that exact file as the gate's review plan, and retain the gate result that binds its profile hash; do not edit the candidate merely to record self-review or review outcome, because that creates self-referential candidate churn. A candidate-local row is appropriate only when the row itself is a substantive deliverable under review. A plain in-place-editable MR description or scratch log is not ordering proof unless its edit history is retrievable and checked; a backfilled row is invalid and forces a rerun. If the candidate diff changes after the row is saved — a file added/removed OR the content of any listed file materially changed — refresh the row and rerun review/challenge against the new candidate. Changing only the external self-review record refreshes the profile binding; it does not by itself invalidate implementation tests or the candidate packet. A missing field, "ok" placeholder, mismatched scope, or unprovable ordering makes the row inconclusive. Do not spend LLM review rounds on issues a script or implementer-side checklist can decide. If the independent pass is the first place basic scope, contract, privacy, or test issues surface, apply those findings to the diff, close the self-review gap, and rerun the deterministic gates before rerunning review/challenge; the process-defect repair is in addition to resolving the findings, not a way to discard or downgrade them.
- Review pass: persist the complete self-review row and encode it in the review plan. For a **non-wording** lane, resolve the repository-owned `scripts/extraction_review_gate.sh` and use it from round 1; never substitute the generic controller, scan writable plugin roots, or supply a caller-selected budget. For a strictly proven **wording-only** lane, use the generic `code-review` proof-bound single-review recipe in `code-review/references/staged-review-contract.md` and record `challenge: not-required`; require its controller-derived wording scope plus the independent `wording_only_boundary` confirmation. This is the only extraction path that stays outside the multi-round wrapper and terminal ledger; the gate, not this page, decides whether a chainless review is legal, and it may still demand the tracked pair. Take all controller options from that runnable recipe, supplying the actual stage and exact candidate rather than an example default. The non-wording chain cannot be retrofitted, so a run started outside its owner wrapper is thrown away and restarted. Read the chain-opening and packet-composition rules in `references/dual-track-review-gate.md` first. Require conclusive JSON, selected-client attribution, packet/profile binding, family exclusion, and wrapper runtime evidence. When the host returns a live execution handle (`session_id`, `cell_id`, or equivalent), keep polling that exact handle until terminal exit; empty current output is progress, not a verdict, and no replacement/fallback reviewer may start while the original process is live. The result row records handle type, an opaque host transcript/tool-call reference and terminal exit status. If the handle is lost, the lane is infrastructure-inconclusive/manual-review-required and no replacement or fallback may be started or credited; process-tree and wrapper artifacts are diagnostic only. This is a procedural host obligation because the inner gate cannot observe the outer handle. Never copy a credential-like raw handle into shared evidence. `findings` is not pass; inconclusive, malformed, or free-form output stays interim. Do not add a separate behavior probe.
- Challenge pass: for a non-wording lane, invoke `scripts/extraction_review_gate.sh` separately with the same plan, stage, candidate, family and tracked chain. Pass the next one-based index; later rounds include a distinct focus and all prior focuses. Preserve a separate result row with the same binding, exclusion, egress, attribution and conclusive checks. Review never satisfies challenge; missing or inconclusive required challenge keeps extraction interim. A wording-only lane has no challenge pass.
- Treat review/challenge as batch-level gates over the landing candidate, not as a per-bullet or per-line edit loop. Apply all findings from a round; when both lenses are required, re-run both on the updated candidate before landing.
- Skipping a required challenge = work can only land as interim, not complete.

#### 3f. Apply fixes, re-sanitize

- Each P0/P1 finding: applied fix OR deferred row with reason.
- After fixes: re-run sanitization (fixes can introduce new leakage).
- Re-run `check-ccl-skills.sh` for static validation.

#### 3g. Commit per batch

- Branch: never `main` — work in a dedicated worktree + feature branch and integrate via MR (worktree-isolation / MR-not-main discipline). `main` is the integration point, not the dev surface.
- Commit shape in a multi-batch same-branch program: every findings fix is a NEW commit; never reach for `git commit --amend` — with several batches' commits stacked on one branch, `--amend` silently retargets whatever commit HEAD happens to be, and "fold the fix into the previous batch" is exactly the instinct that hits the wrong one (one program amended the wrong commit three times before noticing). That NEW-commit shape is not negotiable for a findings fix, and **a findings fix is defined by provenance, not by edit shape**: any edit requested by — or made to disposition — a review/challenge finding is a findings fix, including one whose shape is evidence completion or mirror synchronization, and including the sync fix in `validation-and-landing.md` step 5 when a finding is what surfaced the drift. Provenance is the test because edit shape is self-classified, and "it's just a sync" is the label the wrong amend arrives wearing. So inside such a program `--amend` stays available only for a correction you discovered independently of any finding, on a commit still unpushed AND the one just created, confirmed with `git log -1` immediately before amending. That NEW-commit consequence is scoped to this program shape and nothing wider: outside a multi-batch same-branch program a finding-derived fix may amend on those same unpushed-and-just-created terms, and only the provenance record still applies — `validation-and-landing.md` step 5 states the identical boundary. A findings fix that happens to land right after its own commit is still a findings fix and still takes a NEW commit; "it's unpushed and it's HEAD" is a necessary condition for amending, never a licence to fold a finding in.
- Sanitize **every shared surface the MR flow creates**, not just the commit body — when unsure whether a surface is shared, treat it as shared and sanitize. This covers the feature branch name, the commit message(s), the eventual merge/squash message, and the **entire MR record** (title, body, comments/discussion, labels/metadata). Each names only sanitized capability labels, the target skill/reference, and the private archive by alias — NEVER real source artifacts, project/repo names, real branch/ticket names, or other provenance. Git history, branch refs, and the MR record are all shared tree (see the Extraction lifecycle handoff rule); a sanitized commit with a source-shaped branch name or MR title still leaks.
- Push the branch and open/update the MR, then stop: leave it pending review — do not merge, and do not enable auto-merge / merge-when-pipeline-succeeds. Merge only on the user's explicit merge instruction for that MR.

#### 3h. Update charter completion log

- Append batch result: read sources, mechanisms extracted, sibling mini-map decisions, review/challenge counts, fixes applied/deferred.

### 4. Closeout

- File: `~/.<host>/skills/.extraction-work/<project>-completion.md`
- Final state: which batches done, which deferred, which sources unavailable.
- Lessons: what surprised; what would change in next extraction; what to add to skill-extraction-workflow.
- For every non-wording review chain, build the receipt-bound closeout ledger and run `scripts/validate_extraction_review_state.py <closeout.json>` before reporting a terminal state. A clean Round 2 plus its exact-candidate completion receipt may validate as `ready_for_human_decision`; Round 3 findings validate as `continuation_authorization_required`; a second ordered base drift validates as `baseline_race`. Unknown, stale, omitted, or invalid evidence remains `interim`. The strict wording-only single-review path records its independent review row but does not fabricate a multi-round ledger.

### 5. Provenance migration

- Move from working artifacts → `~/.<host>/.private-aliases/<project>.yaml`:
  - Real file keys / URLs / paths / branches
  - Counts / dates / branch state
  - Contributor habits and team notes
  - Known-debt list
- For task/session/process retrospectives with no single product corpus, use the generic private profile `~/.<host>/.private-aliases/process-retro.yaml` for the R0 audit; do not replace it with an inline grep. If the retro also cites a concrete product artifact, run both the project alias and `process-retro`.
- The shared skill tree keeps only label-based capability rules.
- Working artifacts may stay as the maintainer's local notes; they are never pushed.

### 6. Patch the workflow itself

If the extraction surfaced:
- **A new anti-pattern in ≥ 2 skills** → add to `references/recurring-anti-patterns-checklist.md`.
- **A new review/challenge angle** → add to `references/dual-track-review-gate.md` (e.g. a new category in the challenge prompt template).
- **A new workflow step** → add to `SKILL.md` Core Rules or Core Workflow.
- **A new validation gate** → add to Step 6 validation list.

Skip this step when nothing transferable surfaced.

## Tool inventory

| Tool | Where | When |
|---|---|---|
| Anti-pattern grep panel | `references/recurring-anti-patterns-checklist.md` | Every commit; ~30s |
| `check-ccl-skills.sh` | `scripts/check-ccl-skills.sh` | Every commit; ~10s |
| Generic `code-review` gate | repository-owned skill | Strict wording-only independent review; ~5-10 min |
| `scripts/extraction_review_gate.sh` | this skill package | Non-wording review plus at most two challenges; ~5-15 min each |
| `scripts/validate_extraction_review_state.py <closeout.json>` | this skill package | Every non-wording terminal checkpoint |
| Source-read fallback ladder | `SKILL.md` Source-read remediation | When a source read fails or times out |
| Sibling mini-map | `SKILL.md` Step 4 stack-specific updates | Every stack-specific change |
| Private alias map `audit_cmd` | `~/.<host>/.private-aliases/<project>.yaml` or process-retro profile | Every commit's R0 audit |

## Typical timings

For a medium extraction project (~5 source domains, ~10 skills touched, ~50 references created or modified):

| Step | Time |
|---|---|
| Charter | 1-2 hours |
| Source register populate | 2-4 hours |
| Per batch (read + draft + sibling + sanitize) | 3-6 hours × N batches |
| Dual-track review per batch (review + challenge + fixes) | 1-3 hours × N batches |
| Closeout + provenance migration | 1-2 hours |
| Workflow self-patch (only if applicable) | 1-2 hours |

For a representative real-project extraction (the worked example for this skill): ~7 batches over multiple sessions; ~4 reviews + 4 challenges; ~50 issues found across all batches; ~3 workflow self-patches landed (dual-track gate, recurring anti-patterns checklist, this quickstart).

## Worked example

See `~/.<host>/skills/.extraction-work/<project>-extraction-summary.md` (the maintainer's local notes) for a full real-project extraction run — every batch, every codex pass count, every deferred item — as a reference shape.

## When to NOT use this workflow

- Wording-only typo / grammar / formatting fix in one file (no change to trigger / routing / scope / validation / acceptance / meaning) → no charter; still record the independent review row. Anything beyond true wording-only is non-wording and takes the full dual-track + behavioral-evidence row — `description` / frontmatter edits never qualify as wording-only (routing surface).
- Reverting a commit → use git; charter not required.
- Updating only the maintainer's working notes → no shared skill change → no R0 audit, no review.

If in doubt, the charter step is cheap (20-30 min); doing it for borderline work is fine.

## Failure modes to avoid

- Skipping charter → "wait, what was I trying to extract here?" 2 weeks later.
- Skipping source register → re-extraction can't reproduce coverage; "complete" claims can't be verified.
- Skipping sibling mini-map → cross-language rules drift between language pairs.
- Skipping sanitization checklist → real ccl-specific names ship into shared skill tree.
- Skipping challenge pass → P0/P1 production-safety issues survive into shared skills (worst class).
- Stuffing provenance into shared skills → leaks; later re-extraction has to delete + rewrite.
- Patching workflow without a real ≥ 2-skill pattern → workflow bloat.

## One-line summary

**Charter → register → batch (read, draft, sibling, sanitize, dual-track, fix, commit) → closeout → migrate provenance → patch workflow if applicable.**
