# Design Review Gate Mechanics

Full mechanics for the technical design gate's recorded-review discipline in
`SKILL.md` Workflow step 3 ("The technical design gate's review is recorded,
not implied"). The sub-rules below form ONE gate, walked individually at
their firing points. The entrypoint keeps the firing-point registry; this
file is the authoritative full text. Load it whenever the technical design
gate is triggered — before invoking the independent review, before merging
a triggered diff, and whenever the candidate diff changes after a review.

## Recorded review artifact

(a) a recorded independent adversarial review is the gate for all triggered work — prefer an available review/challenge skill discovered in the session when suitable, otherwise a ccl-owned independent review (the external skill supplements, it is not itself the required gate); save an artifact naming concrete objections, their disposition, and the reviewer or tool identity; same-agent inline prose review is acceptable only for explicitly low-risk, non-cross-boundary work.

## Binds to the implementation diff

When this gate requires the independent review for triggered work, that review **binds to the implementation diff, not only the upstream design/decision**: the adversarial review/challenge must cover the actual code diff before it merges or pushes to a shared branch — green unit/conformance tests do NOT discharge it (tests prove the code does what it does, not that the behavior is correct, and a test written to assert the current behavior can lock in the very flaw the review should catch).

## Bounded exception — verifiably mechanical move commits inside a mixed diff

When the diff is dominated by pure code moves (file splits/renames at declaration boundaries with no semantic edit) so large that a full-diff adversarial pass is objectively infeasible (an actual full-pass attempt failed on time/context limits after normal remediation — chunking/splitting the review packet; a maintainer approval is a risk-owner waiver accepting the unreviewed remainder, recorded as such, never recorded as infeasibility evidence; self-labeling a diff "too big" is not enough), the review may scope to the substantive commits ONLY when all of:

- (a) moves are isolated in their own commits, never mixed with behavior changes, and content-equivalence is verified — any moved declaration/hunk that is not identical to its origin is substantive and joins the full review (whitespace may be disregarded only on whitespace-insensitive surfaces; in indentation-sensitive files — Python, YAML, Makefiles — an indentation change IS a content change);
- (b) deterministic behavior-preservation evidence is recorded AT the move-only commit(s) — the full suite run green checked out at that commit (a move commit that cannot build/run its suite independently does not qualify for the exception; that is not infeasibility evidence), plus an unchanged conformance/golden digest where one exists — AND the move hunks are checked to touch none of the move-sensitive surfaces (including but not limited to: build-tag lines, file-name-suffix semantics, path-based discovery/registration, init/registration-order code, import-visibility changes, generated-code or embed/link directives; any hit sends that commit back to full review); `git diff --color-moved` is a supplementary visual aid, never sufficient alone;
- (c) the net non-move diff of the final candidate gets the full adversarial pass — combined, not only per-commit slices, so cross-commit interactions are seen;
- (d) the scoping decision and its evidence are recorded in the review row bound to the final candidate head SHA — rewriting the candidate after the evidence (rebase/amend/new commits) invalidates the scoping and re-derives it, while a platform merge-time squash that preserves the reviewed tree does not.

A "mechanical"/"refactor-only" label in a commit message is a claim, not evidence; missing any condition, the full-diff binding applies.

## Mechanism-operability check

- **Mechanism-operability check — required whenever the design proposes new mechanical enforcement or verification machinery** (a CI/merge gate, pre-commit hook, schema/signature/checksum validator, evidence or attestation apparatus, migration guard): the design must record (a) **author dogfood, scaled to the machinery's statefulness** — for base-relative, stateful, or evidence-regenerating machinery, the intended day-to-day workflow (multi-commit development, a rebase, one routine follow-up change) passes it end-to-end under the same resolution CI will use, before it lands; a trivial stateless check needs only a proportional smoke run; (b) **marginal cost** — what the cheapest routine change costs under it (regenerate/rerun/recompute burden), and that this cost does not defeat normal iteration; (c) **trust-model fit** — what it defends against under the declared trust model; machinery that only defends against adversaries the trust model already excludes (e.g. content digests the author can freely regenerate) is redundant detection at full complexity cost — choose the lighter mechanism that keeps the enforceable core. A mechanism failing this check is redesigned or lightened at design time, not hardened round-by-round after review findings. (The shared-skill-gate instantiation of this rule lives in `skill-extraction-workflow`'s remove-the-capability Core Rule.)

## Cross-cutting shared-runtime primitives

A change to a cross-cutting primitive that shares a runtime — interceptor/middleware chains, logging/metrics/recovery adapters, context/identity propagation, global/env wiring — is a high-hidden-edge class: its happy path passes while edge paths (propagation, caller overrides, nil/empty inputs, optional-dependency failure, request-shape asymmetry) fail silently, so budget an explicit adversarial pass over those edge paths and add a regression test per path found before treating it done.

## Implementer self-review row (before the independent review)

Before invoking that independent review/challenge, persist an implementer self-review row in a revision-tracked record whose history is retrievable that will carry the independent-review result — a commit on the working branch, or a platform artifact with retained revision history; **when this change's own gate requires the independent review before the landing commit (e.g. a shared-skill change under the dual-track gate), the ordering-proof record must be a non-landing revision-tracked artifact, not the landing commit, so this rule never forces a premature landing commit** — the row carries: acceptance criteria rechecked, changed files/scope matched to the active artifact, edge/failure paths considered, a named regression test that fails before the change and passes after (or the recorded reason none is feasible), deterministic gates already run with what each proves, and known residual risks.

Ordering must be provable from that history, not merely asserted: the row must predate the review/challenge run in an immutable or revision-tracked record, and a plain MR/PR description or any in-place-editable field is NOT acceptable ordering proof unless its edit history is retrievable AND was actually checked to confirm the row preceded the review; if the row is added only after review/challenge, that review is invalid for the gate and must be rerun after the row exists. The row is conclusive only when each required field is non-empty and non-placeholder, and the changed-file scope equals the candidate diff's changed-file set or explicitly explains any excluded generated/irrelevant file; otherwise it is inconclusive.

## Changed candidate = refreshed row + fresh full-scope rerun

If the candidate diff changes after the row is saved — a file added or removed, OR the content of any listed file materially changed (not just whitespace/typo) — refresh the row and rerun the independent review/challenge against the new candidate; a stale row does not cover files or rule text it never reviewed. When that changed candidate is a remediation of prior review/challenge findings, the rerun is a fresh full-scope pass over the new candidate, not a scoped confirm-my-fix check — the trigger is the changed candidate diff itself (mechanical), never the author's framing, the author cannot narrow the rerun's scope by describing which findings were fixed, and a "whitespace/typo-only, no rerun needed" classification of a post-review change is not the author's to make alone — it needs diff-based deterministic evidence or an independent reviewer's confirmation: author over-optimism about their own fix is an observed failure mode — especially on high-risk paths (money, concurrency, identity, write-finality), where a second independent round repeatedly catches first-round remediation that is still insufficient and forces a changed approach.

## Independent gate surfacing basics = process defect

If review/challenge is the first place basic scope, contract, privacy, or test issues are discovered, treat it as a process defect and repair the self-review/deterministic-gate loop before rerunning the independent gate; the discovered findings still require disposition under the dual-track gate (fix, or a documented accept/defer/out-of-scope), not waived or downgraded by the process-defect framing.

## Green-tests-alone merge is the same defect

Merging triggered-work implementation on green-tests-alone, with the adversarial review applied only to the upstream decision, or with no checkable implementer self-review row before the diff review, is the same process defect as reaching implementation with only spec plus plan.

## Human/team sign-off

(b) human/team sign-off before implementation, merge, or launch for high-risk money/permission/data paths and for any contract/API change with an external consumer (reviewed interface diff plus compatibility decision); read-only investigation or an isolated disposable prototype that will not be merged, reused, or launched is exempt, and promoting such work to implementation reruns this gate.

## Floor

Reaching implementation with only spec plus plan on triggered work is a process defect, not a shortcut.
