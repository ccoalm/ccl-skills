# Dual-Track Review Gate

Independent-review gate for shared-skill changes, deep extraction, and any skill change that ships operational, architectural, or security-sensitive rules. `Shared-skill change` means any change under a shared skill package, including `SKILL.md`, references, scripts, validators, templates, generated outputs, metadata, and examples — **plus the repo's own plugin-shipped command / behavior surfaces outside `skills/`**: any executable, command, server, monitor, hook, settings, or behavior-activation surface the plugin ships and a host runs — today root `hooks/*` (SessionStart / PreToolUse shell on every session and tool call), `scripts/install.sh` (teammates run it at install), plugin `bin/` (added to the Bash `PATH` while enabled); the same applies to `.mcp.json`, `.lsp.json`, `monitors/**`, `settings.json`, and any manifest path that declares or redirects those. Those are the install-time and runtime code-execution supply-chain surface every install runs, so a change to them is a shared-skill change — independent review always, adversarial challenge for any non-wording change — and is never `not-applicable: docs-only`. Every shared-skill change requires an independent review before commit. Non-wording shared-skill changes also require an adversarial challenge before commit.

This gate owns *when* two passes run, *what each catches*, and what a finding state does to a landing (block / accept / defer / rerun). How findings are severity-calibrated (P0/P1/P2), what makes a finding actionable vs noise, and what makes a `findings` / `no-findings` / `inconclusive` result *valid* are owned by `review-finding-standards.md` — apply that standard to every finding either pass produces, so convergence is measured against a shared bar rather than each reviewer's private sense of "P1" or a rubber-stamped empty result.

## Why two passes

| Pass | What it catches | What it misses |
|---|---|---|
| **Fact/consistency review** (`codex review` or equivalent) | Technical inaccuracies (semantic claims that are wrong), contradictions across references, sanitization gaps (residual ccl-specific names/IPs/hostnames), over-prescription (saying MUST when industry has multiple acceptable patterns), API/path inconsistencies | Production-safety chaos modes: race conditions, data-loss paths, security holes, algorithm flaws, operational footguns |
| **Adversarial challenge** (`codex exec` with adversarial prompt) | Production-down scenarios under chaos, attacker-style abuse paths, edge cases that break the documented happy path, sequencing/timing issues, broken algorithms at small/large scale | The flat-text consistency layer (handled by the first pass) |

### Closeout reads the LANE NAMES, not the round count

A slice can record many rounds and still have run only one lane, because the only
record of which lanes ran is the landing artifact's own author-written rounds
table. At closeout:

- **Count lane names, never rounds**: enumerate the lanes the slice's own gate section requires, and confirm each one has a recorded outcome.
- **A rounds table naming one lane while the gate requires two is `interim`, never landed** — no round count and no green deterministic gate substitutes for a lane that never ran.
- **Where lanes leave evidence in a local store, a chain must exist for THIS slice** — check what the stored packets actually covered rather than assuming one is there.

Observed: a mandatory, fail-closed repository gate landed with nine review-mode
rounds recorded, no challenge lane run, and a landing state still reading
`plan drafted`. Run afterwards against the landed diff, the challenge found a
one-character bypass of that gate in a single round — appending one bracket
anywhere in a citation skipped resolution entirely, so the gate reported success
on exactly the input it exists to reject. The defect lived in "how would this
break", which is the question only the missing lane asks.

Skipping the challenge is how P0/P1 issues survive into shared skills. Real example from one multi-batch real-project extraction:
- Review pass found 8 issues (P2/P3): all factual/consistency.
- Challenge pass found 19 issues (3 P0 + 14 P1 + 2 P2): production-down + security + algorithm + footgun.

The 11 challenge-only findings included: `DELETE /lane` cascade without safety gates, mesh reconcile without serialization, snapshot DR corrupting live quorum, log-error-diff comparing counts not rates, `docker login -p` leaking password to process args, chat callback without signature/replay protection, FQDN fallback bypassing lane filtering. None of these were caught by review.

## Self-audit to convergence BEFORE the gate — the passes are an adversarial backstop, not your defect-finder

**The two passes are a final *independent adversarial backstop*, not your defect-discovery loop.** The recurring failure: an agent ships unconverged work into review/challenge, then treats the third-party model as the primary mechanism that finds what's wrong and uses its findings as the task list — review/challenge → fix → re-review/re-challenge → fix. It burns rounds, offloads the implementer's own diligence, and (because each fix can add a fresh P0/P1 — see *Iterating*) routinely fails to converge.

Before invoking either pass, self-audit the candidate to the point where *you* expect it to pass: for any non-wording semantic rule / gate / status / verdict / code-mechanism change, first **state its load-bearing invariants** — the properties that must hold on *every* path ("exactly one terminalizer fires", "no per-object state outlives its owner's close", "a deadline only shrinks across hops", "the required schema fields always survive truncation", "input is bounded before any hot-path step touches it") — make each a checkable assertion, and **record them under the implementer self-review row's edge/failure-paths element** (the row `product-rd`/`extraction-quickstart` already require — not a new field): each applicable invariant → its derived failure mode → the concrete check or a residual-risk disposition. Invariants absent, shallow, or vacuous make that element **inconclusive, not a checked box**; if the change genuinely has none, record `invariant-pass: not-applicable` with a reason held to the same gate-fireability standard (not self-waived — "it's just prose, not a mechanism" is the decorative-gate dodge). Many failure modes are just an unstated invariant broken, so derive them from the invariants too — an **additive lens**, not the universal root cause (some P0/P1s instead come from rollout ordering, authority, or a factual-contract miss that no single invariant captures; those are the axis list below). Doing the invariant pass is a large part of what separates a happy-path draft from senior-grade code. Then independently enumerate every path/branch/state that affects the outcome and pull each into the test matrix, run the complete checks/suite the owner/risk gate selects (risk-matched, not blanket), and re-check acceptance criteria, edge/failure paths, and the **recurring first-draft blind-spot axes** yourself (security/authority/data-loss, concurrency & lifecycle, resource bounds, rollout/migration ordering, over-broad absolutes, and enumeration-completeness — under-listing a set the rule itself defines — the set the challenge most reliably supplies, so pre-cover each applicable one; the full enumeration is the draft-time corollary in `SKILL.md`). Good shape: *"the only new runtime path is the no-jq fallback; I enumerated every merge-affecting branch into the matrix, asserted the jq and no-jq paths give identical exit codes on the same fixture, ran the full repo suite — now I hand it to the challenge as a last adversarial backstop."*

**Self-audit never narrows the gate.** Converging your own work first does NOT shorten, soften, rescope, or pre-bias the required challenge: a self-audited candidate still gets a fresh full *adversarial* pass under the convergence rules below (`Do not bias the re-challenge`), never a "confirm my work" pass. The self-audit conclusion is *your* controller-side evidence — never feed it to the challenger as framing that asks it to confirm your work; challenge prompts stay adversarial and diff-scoped. This is the same ordering `product-rd-workflow`'s technical-design gate and `extraction-quickstart.md` already mandate; a *valid* persisted self-review row (validity rules in `extraction-quickstart.md`) is **ordering evidence only** — proof the self-audit ran *first*, not proof its claims are *true*. Test/verification claims still need command/artifact evidence, and a backfilled or thin row is invalid. Don't restate the row's field list here.

"Self-review does not count as dual-track" (*What does NOT count*, below) means self-review is not sufficient *evidence* of independence — it does NOT make the self-audit-to-convergence preparation skippable. And if review/challenge is the first place a basic scope/contract/test/security issue surfaces, that is a process defect in the self-audit loop — but the finding is still a normal gate finding: resolve or disposition it under this gate (fix, or documented accept/defer/out-of-scope), never waive or downgrade it as "should have been caught earlier." The process-defect repair (close the self-audit gap, then rerun) is additional, not a substitute.

**A design pivot resets the self-audit obligation.** When the candidate is substantially redesigned mid-gate (a mechanism replaced, a capability torn down, a rewrite beyond the findings being fixed), the earlier self-audit covered the OLD candidate: redo the closure self-audit on the NEW candidate before re-entering the challenge. Sliding from a pivot straight back into challenge → fix → re-challenge is the exact loop this section forbids, and it recurs precisely at pivots because the prior audit feels "already done."

**Partition findings before fixing: mechanical fixes vs design decisions.** When a round returns findings, classify each before starting fix work: a *mechanical* finding (bug, missing check, wrong value) goes on the fix list; a *design-level* finding — one that questions a mechanism's cost, operability, trust-model fit, or existence (the remove-the-capability signal in `SKILL.md`), OR one whose remediation would expand scope into an explicitly-deferred concern (the scope-direction / controller-cut-scope signal in `SKILL.md`), recognized on its FIRST appearance (recurrence across rounds is only the reviewer-lane stop/reframe escalation, never the point at which you first classify) — is a **risk-owner decision item**: present keep / delete / narrow / replace — or, only after the current-phase-impact test and compound split (see `Findings, autonomous budget, and human authority`) leave a residual with no current-phase impact, cut-scope-to-phase-boundary — to the user/maintainer BEFORE investing hardening rounds in the questioned mechanism. Executing "fix the findings" by hardening a mechanism whose design finding was never decided pays the hardening cost twice — once to build, once to tear down.

**A finding-fix that widens or hardens a validator needs a false-positive sweep against an explicit accept-set oracle.** Before landing a fix that strengthens a check in response to a finding (advisory → blocking, a narrower accept-set, a new rejection class), set-diff the strengthened check against an authoritative universe of legitimate content — a finite schema, the surface's own inventory of shapes, or the existing corpus the check will scan; when no finite oracle exists, name the representative legitimate classes checked, the sampling boundary, and the uncovered residual as explicit risk. Listing the salient examples that came to mind is not a sweep — the fix must state its precision exposure, not only close the recall gap. Failure shape: a "block malformed ledger rows" fix that would have false-positived on the register's other legitimate table shapes, reverted one round later.

### The self-adversary enumeration — method detail (relocated from `SKILL.md`)

The recurring failure: the agent declares done/covered/converged, and the *user* has to push — "keep going", "did you verify", "that's not actually covered", "深度分析了么" — before the agent runs the loop that would have caught the gap. The `SKILL.md` rule carries the red lines (clean-fresh-result-or-`interim`, `unverified` labelling, risk-owner acceptance); this section carries the method detail.

- **Mutation enumeration.** List every property the candidate states — in the rule text, the commit message, a register row, a doc, or a test name — and for each one name the mutation that would make it RED. Where the property has an executable test, apply the mutation and watch it go RED; bound the blast radius — never disable an authorization, idempotency, or deletion guard and then exercise it against a shared or live dependency, where buying a RED can destroy real data or perform a real unauthorized action; mutate against isolated dependencies or at the lowest layer that avoids them, and where neither is possible record the property `unverified` — naming a plausible-sounding one and moving on is the same self-certification this rule exists to stop.
- **Independent oracle.** Where the property has no executable test — rule text, a register row, a doc — the enumeration is discharged only by an **independent oracle**: name the concrete observation that would contradict the property, say where that observation lives (the owner file and line, the primary source, the command whose output would differ), and go look. **Validate the oracle before trusting its verdict**: a check that returns "clean" because it looked in the wrong place, matched case-sensitively, used too narrow a pattern, or swallowed an error is indistinguishable from a passing property, and it fails in the dangerous direction. Before accepting a clean result you must PROVE THE CHECK CAN FAIL — point it at something you know is broken and watch it report that. Confirming it enumerated the inputs you meant is a necessary extra step, never a substitute: correct inputs say nothing about whether the predicate detects a mismatch or whether a non-zero exit was swallowed, so a check that can only ever say clean passes that weaker test. An unvalidated oracle is not weaker evidence than an imagined mutation; it is the same thing wearing a command prompt.
- **Dimension walk.** Adding cases inside an axis you already had buys nothing against one you did not: the enumeration walks dimensions (shape / provenance-and-trust / cardinality / semantics / ordering) before values — `testing-strategy` owns that list and the precision-row obligation that goes with it. A walk whose rows are all imagined mutations is exhortation wearing a checklist's clothes.
- **Re-owe after fixes.** Whatever you produced while fixing a previous round's findings is part of the current candidate and re-owes the whole enumeration — that newly-added mechanism is the most dangerous line in the diff, because it has no test yet and you wrote it with your attention on the defect it repairs. "The whole enumeration" includes the **pre-cover axes sweep** (concurrency & lifecycle above all): remediation text written mid-round re-owes the draft-time axes BEFORE the candidate goes back to the reviewer, because a fix written with attention on one defect systematically re-opens the same blind-spot axes the original draft missed. And the loop has an escalation point: when the same blind-spot axis or finding class supplies findings in a **third** round, stop the per-finding loop and run one full-matrix implementer self-enumeration (the artifact's own states × failure points × orderings × residues × cross-references) on the current candidate before any further external round — letting the reviewer surface one hole per round is the reviewer-as-defect-finder failure at its most expensive (observed shape: a multi-round program burned twenty-plus single-finding rounds on one axis family; the one full-lifecycle enumeration, run at the maintainer's correction, found the remaining holes in a single batch).
- **Classify before fixing.** Persist one transition row per finding class: a stable semantic class key, its root-cause predicate, affected surface, and one disposition per occurrence. Each occurrence names the SHA-256 of its controller receipt plus the canonical JSON SHA-256 of a finding that actually appears in that receipt; the closeout must classify every controller finding exactly once. New wording or a new file is not a new class when the predicate is the same. Root-cause predicates must be unique across classes after case-folding and whitespace collapse; **only that exact normalization is mechanical**. It catches cosmetic case/whitespace key splits but does not decide whether differently worded predicates are semantically equivalent, which remains reviewer-contestable. Resolution is per occurrence, not "the last disposition wins": every `fixed`, `accepted_tradeoff`, `pre_existing_out_of_scope`, or `source_refuted` occurrence names one same-directory structured disposition-evidence file plus its SHA-256. That file binds schema version, exact current candidate, its controller receipt and finding, the disposition, a non-empty evidence list, and the ordered current/prior class occurrences it resolves. It must resolve its own occurrence; a later closing disposition that lists only itself leaves an earlier `open` occurrence unresolved until later evidence explicitly includes that exact receipt/finding pair. A `needs_human_decision` occurrence cannot be resolved by any candidate-local disposition evidence and stays unresolved until an authenticated external human/platform decision takes the separately authorized path. A controller finding disproved by first-hand source or failure-path evidence records `source_refuted`; this is a classification of an invalid finding, not a fourth disposition for a valid P0/P1. The validator binds every JSON input using duplicate-key rejection, plus the evidence file, digest, candidate, occurrence, disposition, and transition links; it does not judge the evidence text or authenticate tradeoff/scope acceptance. The reviewer or human decision-maker still owns those semantic and authority verdicts, and `ready_for_human_decision` is not approval or merge authority. On the class's third appearance, stop patching individual instances and enumerate the complete authoritative surface against that predicate. The sweep names a same-directory manifest plus its SHA-256; its candidate and exact ordered `searched_set` must match the row, and its unmatched list supplies the recorded count. `ready_for_human_decision` requires zero unresolved occurrences and zero unmatched instances; `continuation_authorization_required` and `baseline_race` retain non-zero unmatched evidence instead of lying about closure. Classification is reviewer-contestable evidence, not an author-controlled escape hatch; splitting one predicate into cosmetic sub-classes does not reset the count. `scripts/validate_extraction_review_state.py` enforces these bindings within the referenced receipt/evidence set.
- **Graded verdict shape.** When the assessed reality is multi-dimensional or partial (capability, coverage, feasibility, quality, completion), collapsing it into one binary verdict — "done/not-done", "possible/impossible", "all correct/all wrong" — is the over-broad-absolute axis applied to your own claim layer: the swing to whichever pole feels safest to assert misrepresents a distribution, and the opposite-pole absolute ("structurally impossible", "nothing works") is the SAME defect as an unearned "done", not a humbler one. Report per-dimension status — what's strong, what's weak, what wasn't checked — with the confidence each part actually earned; and where a binary gate genuinely applies (a pass/fail check, a blocked/allowed decision), still give the clear top-line verdict after the per-dimension basis — calibration is not hedged mush. A user correcting your answers as too absolute ("每次都很绝对") is this defect's recurrence signal, same escalation as the `SKILL.md` rule states.
- **Honesty (descriptive, not permissive).** This is recognition-dependent salience, not a mechanical gate — an agent that doesn't notice it is done-claiming cannot self-fire it; the mechanical backstops remain the closeout `interim` gates + user-signal escalation. "I didn't notice I was claiming done" does NOT waive the rule — any non-trivial completion/coverage/convergence wording must carry clean-pass evidence or an explicit interim/downscope disposition *before* you emit it. The rule targets completion/coverage/convergence assertions on work whose failure a check could catch, and never narrows the mandatory dual-track challenge (it is the always-on generalization of *self-audit to convergence*, not a replacement for the gate).

### Pre-cover axis detail (relocated from `SKILL.md`)

Across a long operational-rule/code extraction series the challenge supplies *the same handful of axes* as the recurring P0/P1 — first drafts systematically nail the functional / cost / happy-path and omit a predictable set. The per-axis instance lists for the six first-draft blind-spot axes:

- **(1) security / privacy / authority / data-loss** — weakened safety/refusal/authorization, secret/PII into a durable artifact, non-restorable delete vs archive, lost/orphaned/duplicated work, untrusted input treated as authority, runs-against-prod/live-creds instead of a sandbox; and — because skill/reference text is itself a prompt agents execute — the rollout-safety screen an eval harness runs on skill text before release: wording that induces context/secret exfiltration (prompt leakage), assumes or grants permissions beyond the task (overreach), or automates a destructive or confirmation-skipping step (unsafe automation) — text a draft must not carry except as an explicitly labelled anti-example.
- **(2) concurrency & lifecycle** — races, deadlock (e.g. holding a lock through a drain/callback), use-after-close/free, resurrection after delete, double-free/double-close, cleanup ordering, at-most-once/fires-once.
- **(3) resource bounds** — an unbounded default/timeout/buffer/retry, a leaked registry/goroutine/task entry, a missing max backstop.
- **(4) rollout / migration ordering** — a step that breaks not-yet-upgraded consumers, or abandons a live bug to do the clean refactor first.
- **(5) over-broad absolute** — an "always/never" rule or impl that breaks a legitimate case and needs a scoped exception.
- **(6) enumeration-completeness (the mirror of (5) — under-listing, not over-listing)** — when the rule itself DEFINES or LISTS a set (allowed values/schemes, risk tags, change-shapes, state/error classes, reconciliation outcomes, OS/runtime/transport variants, the cases a guard must cover), the first draft lists the *salient* members and silently omits siblings; the check here is a **set-diff, not a negative case** — diff your enumerated set against its authoritative complete source (the same file's own table/enum, the primary-source spec, or an explicitly declared variant matrix in the changed artifact — not a taste call), not just the members that came to mind.

That the challenge reliably catches them does NOT make pre-covering redundant: the challenge is the safety net, not the first line, and a teammate whose challenge is weaker or (against the gate) skipped otherwise ships the blind draft.

Three per-edit instances of the axes above that recur because their canonical rules live AWAY from the editing surface (observed shape: three externally-caught defects in one batch, each covered by a rule the author had read but that had no firing point at the edit site): **(axis 1/6, new fillable fields)** every record field/slot/status value the diff INTRODUCES gets the record-field forgery question before handoff — what makes a false fill fail? — a field without a validation bar is the `SKILL.md` record-field corollary shipping a new forgery surface; **(axis 6, renames/recounts)** a change that renames, re-counts, or re-labels anything runs the family-wide stale-term scan to zero (tighten-doc closeout owns the rule; run it on skill text too — skill text IS a reader-facing doc) before review, not after the reviewer greps it for you; **(axis 5, gate-satisfying substitutions)** when a mechanical gate rejects your first choice, check the substitute against the gate's INTENT, not only its predicate — a predicate-passing substitute that misses the intent is self-goodharting under gate pressure (the circular-anchor shape: a firing-path anchor that points at prose ABOUT firing paths instead of the decision point that fires this change).

### Design-time operability check (relocated from `SKILL.md`)

For any new mechanical gate, validator, or evidence apparatus — **and for any change that makes an existing one's verdict stricter** — run the four legs at design time, not after challenge rounds force them. These four legs all fire at design time; the check has a second firing point they do not cover, because its actor is not the gate's author: when a landing **withdraws or downgrades the evidentiary claim an existing gate rests on**, that gate is re-based or retired in the same landing — see the claim-liveness rule in `product-rd-workflow/references/design-review-gate-mechanics.md`, which owns it, including the obligation walk a retirement owes.

- **(a) author dogfood, scaled to the gate's statefulness** — for a gate that is base-relative, stateful, or evidence-regenerating, the intended authoring workflow (multi-commit development, a rebase, one routine follow-up edit) must pass it end-to-end under the SAME base resolution CI uses, before the gate lands (a gate whose own author's branch fails it ships a broken contract); a trivial stateless check needs only a proportional smoke run (this leg stays risk-matched — it never demands synthetic multi-commit ceremony for a one-shot grep).
- **(b) marginal-cost statement** — record what the cheapest routine change costs under the gate (recompute/regenerate/rerun burden); a gate whose per-iteration cost defeats normal development gets lightened or redesigned at design time.
- **(c) trust-model fit** — name what the mechanism defends against under its DECLARED trust model; machinery that only defends against adversaries the trust model already excludes (e.g. content digests where the author can regenerate every hash) buys redundant detection at full complexity cost — prefer the lighter mechanism that keeps the enforceable core.
- **(e) loosening check — an exemption must name the class of change that stops owing evidence, and that class must be one with no behaviour to evidence.** Fires whenever a change makes a gate accept what it used to reject: a new exemption class, a waived requirement, a widened accept set. A loosening is easier to get wrong than a tightening and shows up later, because it produces no red for anyone to notice — the gate simply stops asking. Two obligations, both outcomes rather than procedures. **First, state the exempted class in behavioural terms and check it against the repo's own definition of that class**: an exemption named `not-required` asserts *no behaviour*, so if any rule in the tree already classifies that same diff shape as behaviour-changing, the exemption contradicts it and the answer is to fix the *anchor/evidence form* for that shape, never to drop the evidence. **Second, if the class does carry behaviour, the exemption must be replaced by a way to SUPPLY the evidence** — widen where the anchor may land, add an evidence form the shape can satisfy — because the class with the most behaviour is exactly the one an exemption hurts most. **A precedent of the same shape is not a justification**: reaching for an existing exemption class because the root cause rhymes with an earlier one transfers the solution without checking the disanalogy, and the disanalogy is usually the load-bearing part. Failure shape: a gate anchor that structurally cannot bind to a frontmatter-only change was answered with a third `not-required` class by analogy to two existing ones, even though the same repository elsewhere states that any frontmatter edit is a routing-surface change and the author had just measured its routing delta; the adversarial review caught it on the first finding, and the correct fix was to let the anchor bind to the changed description instead.
  - **Proposal-time corollary.** This check fires **before** a design option list reaches a human, not only before landing. An option list must carry, per option, what evidence that option removes and from which class of change; a `recommended` label asserts that comparison was made. A recommendation resting on *consistency with precedent* rather than on that comparison is unearned — and when a rejected option's stated downside reads back as a true statement about the domain, that option is probably the right one.
- **(d) premise check for a verdict-tightening change — a clean run on the CURRENT corpus is not evidence.** Fires whenever the change makes the verdict stricter for inputs that previously passed (a reporting check turned blocking, a warning turned error, a widened reject set, a new blocking gate landing over an existing corpus). Today's zero-violation count is the sum of inputs that pass because they are *registered or correct* and inputs that pass by an **incidental property of how they happen to be written**; the tightening silently converts the second group into reds with no legal exit — and the author never sees it, because it fires on whoever edits those inputs next. So verify the premise, not the state: drive the gate's own input toward the worst case it will legitimately see — saturate the incidental property across the whole scanned set, or apply the cheapest edit to the input nearest the threshold — in a **throwaway copy**, never the live tree, and re-run. Then **classify what fails against what the tightening was SUPPOSED to reject** — "it failed" alone is a false green, because on a gate whose whole point is to start rejecting something, the worst-case input fails by design and you learn nothing. An **intended** rejection is the change working. The finding is the other kind: an input that was meant to stay valid and fails only because of an incidental property of how it is written. **The leg is satisfied by an outcome, not by having run the procedure: no such input may be able to hit the tightened verdict with no way out.** So the disposition menu for one of these is closed, with exactly three exits: give it a **legal exit** before landing (register/exempt it, or narrow the rule); keep the tightened behavior **non-blocking** until it has one; or obtain an **explicit risk-owner deferral** carrying a repair path the affected inputs can actually take **at or before the moment the blocking verdict turns on** — a repair that only becomes usable later is the non-blocking exit, not this one, because until it lands the next ordinary edit still hard-fails with nowhere to go. All three name the affected inputs, never an unenumerated blanket. "I ran the procedure" and a bare "accepted cost" are not exits — accepting a residual that still hard-fails the next ordinary edit *is* the outcome this leg exists to prevent. Run the perturb-and-classify exercise **once per newly-tightened predicate and per materially distinct class of affected input** — a change tightening two predicates is not covered by exercising the louder one, and the class you never perturbed is exactly where the next contributor's ordinary edit lands; representative sampling is allowed only when you record why the sampled classes cover the omitted ones. Keep it proportional — scope the saturation to the gate's own input set, it is a one-time design-time run, and a reasoned narrowing is fine while silent skipping is not; where the worst case cannot be constructed cheaply, the premise is `unverified` — and `unverified` is **not a landing state for the blocking form** (an un-run check is not a passed check, the same semantics this repo already gives its `*_unevaluated` size-gate token) — route it through the non-blocking or authorized-deferral exit above, per affected input class.

Failure shape (a)–(c): the digest-bound evidence apparatus evaluated and removed in `external-practice-controls.md` (behavioral-evidence-and-attestation) — its full-suite double-arm regeneration cost broke its own author's multi-commit branch, and it survived review as a fix-list item until the maintainer's cost challenge tore it down to a static gate.

Failure shape (d): a route-existence check flipped from warn-only to blocking on a corpus measured at zero violations. The zero was partly accidental — a canonical vocabulary token that the check's own exemption tables never registered sat on several lines that happened to carry no trigger word, so the first ordinary wording edit to any of them would have reddened CI with a diagnostic telling the author to restore something that never existed. Legs (a)–(c) all passed: the author's own branch was green, the marginal cost of a typical edit was zero, and the trust model was sound. Six external review rounds missed it too — they read the diff, and the evidence was a statistic over the corpus *outside* it. One saturation run surfaced every affected line at once.

### Green verdicts that were structurally incapable of being red (relocated from `SKILL.md` §Self-audit)

The self-audit rule says to prove the oracle can fail before trusting its clean verdict. Two shapes make that proof skippable because the verdict *looks* like it came from the thing you meant to run:

- **A pipeline reports its LAST stage's status.** `make test | tail -20` exits with `tail`'s status, so a failing `make` reads as exit 0; the same holds for `| grep`, `| head`, and any `$?` read after a pipe. Redirect and read the command's own status (`cmd > log 2>&1; echo $?`) or set `pipefail`. Observed: a full-suite failure was reported as passing, and the mistake was caught only because the summary line the suite prints on success was missing from the captured tail.
- **A check run against the wrong tree passes silently.** When the work lives in a git worktree, an ambient `cwd` the harness may reset between tool calls sends relative-path commands to the primary checkout, which is clean — so the gate evaluates a tree that does not contain the change. Resolve the target by absolute path (`git -C <abs>`, `bash <abs>/script.sh <abs>`); `worktree-isolation` owns that discipline. Observed: a catalog test's pristine-tree case passed against the primary checkout while the real candidate was blocked.

Both are the same defect as a check that can only ever say clean: if you cannot produce the red path on demand, the green is not evidence.

### A new gate owes the negative half (relocated from `SKILL.md` §behavioral-evidence)

A `RED-baseline` row proves the gate fires on what it must catch. That is one side. The other side — proof it does **not** fire on untouched, legacy, or out-of-scope inputs — is the half authors skip, because those cases feel uninteresting and the suite is already green without them. A gate that also blocks what it should spare is a regression wearing a green suite, and it lands where it hurts most: on repositories and fixtures that never opted into the change.

So a new or tightened gate records spare-case rows beside its block-case rows. Observed: a catalog gate shipped with five block-case rows, all green; nothing checked what it did to a repository whose catalog predated the format, and a nested test fixture found the hard failure instead of the author.

### Residency in the always-on layer is a measurable claim (relocated from `SKILL.md` §behavioral-evidence)

The always-on injection layer (`agent-context/session-start.md`) enters every session on every host and carries a zero-net-growth budget enforced by `scripts/check-size-budget.sh`. "This skill/rule has to be resident" therefore spends a scarce, contested resource — and before there was a way to measure it, the claim could only be argued.

Measure the A/B first: `scripts/eval-routing-bank.rb --with-bootstrap` runs the task bank with and without the injected entry-routing region, so the delta the layer buys is observable. Spend bytes only on a delta that shows up. When the measured delta is zero the honest landing is to leave the content out — not to argue the budget down, and not to trade an existing rule away to fund it. Observed: seven skills a plan asserted were routing gaps showed 19/22 → 19/22 with the full skill listing and 20/21 → 21/22 with descriptions truncated to 250 chars; they stayed out, and the layer ended smaller than it started.

### Verify a load-bearing premise before designing on it; non-convergence is a premise smell

The self-audit rules above catch a claim you make about your own change. This one catches
the claim you never examined because it felt like background fact: who calls this script,
what the packaging actually ships, what a field in a gate's output means, which states are
reachable at all. Those are premises about the system's own topology, and a design built on
a wrong one cannot converge no matter how many rounds it runs.

**The trigger is a design decision, scope cut, or escalation whose correctness depends on
such a claim.** Before the design work — not after the third round — falsify it with the
cheap local command that settles it: grep the callers, read the gate source at the line that
defines the field, list the packaging roots. The predictor of these failures is not that
reasoning was unavailable; it is that verification was cheap and skipped.

**Escalation corollary — the dangerous one, because it looks responsible.** When successive
review rounds keep surfacing new instances of the same class, the documented reading is a
design smell (question whether the capability should exist). Check the premise first: if a
premise is wrong, rounds will not converge and the pattern is indistinguishable from a
genuine design dilemma. Handing that non-convergence to a human as a decision *feels* like
responsible escalation while the missing input is one command, not a judgment. Escalate only
after the premises the tradeoff rests on have been falsified or confirmed.

- **A design decision, scope cut, or escalation must not rest on a premise about the system own topology that a cheap local command would settle** — grep the callers, read the gate source at the line defining the field, list the packaging roots — **and non-convergence across review rounds must never be escalated as a design tradeoff before those premises are checked.**

Observed, both inside one session: a shared gate was redesigned to stay compatible with
downstream repositories that a one-line grep showed it is never installed into; and three
rounds of design were spent on a state ("a checkout without the always-on layer") that the
caller list showed only test fixtures can reach — the third round was escalated to the
maintainer as a design tradeoff, and their one question about the premise closed it. A third
instance in the same session shows the same shape at reporting altitude: an empty background
output file plus a stale status snapshot were reported as "the commit did not land" instead
of being re-read.

### The claim/evidence pair table — the single most-recorded failure class

**Invariant: the proof you hold establishes a DIFFERENT proposition than the one you are about to assert.** Not a weaker proof of the same claim — a sound proof of an adjacent claim. That is why it survives an honest self-check: the agent did verify something, and it was real.

This is the largest class in the round-059 corpus by a wide margin. The counts below are the instances that could be attributed to a specific pair on a re-read — **71 of the 400 failure records read in that pass**, across 14 pairs. (The denominator is the size of that one READ, which is fixed and re-countable from the extraction artifact; it is not the store's current size, which grows.) A coarser class-level pass over the same corpus put the shape higher still, but that figure is not reproducible from this table and is deliberately not quoted here: a table about asserting propositions your evidence does not establish must not open with one. Read 71 as a floor. Every pair is the same sentence with different nouns, which is why patching them one at a time never converged: each fix taught the next agent about `merge` versus `release` and nothing about the shape.

| You are about to claim | What your evidence actually establishes | corpus |
| --- | --- | --- |
| the reviewer approved it | the review lane returned no verdict (timeout, quota, auth failure, invalid output, exhausted budget) | 16 |
| the product or the code is defective | YOUR INVOCATION of it failed — missing runner or binary, container runtime down, sandbox denial, unwritable cache, expired credential, toolchain drift | 22 |
| released / deployed | merged | 8 |
| runtime behavior is correct | static, contract, compile, or lint evidence passed | 5 |
| the content is correct | the command exited 0 | 4 |
| this produced a product effect | CI is green / the package published | 4 |
| deletion is authorized | merging was authorized | 3 |
| the data is physically erased | refs are clean and a fresh clone looks right | 2 |
| there is a live incident | the code path is reachable | 2 |
| the item is resolved | a reply was posted | 1 |
| the capability executes | it is registered or configured | 1 |
| the caller can read it | the caller is a member | 1 |
| it is implemented | the plan validated | 1 |
| the application is authenticated | the user identity is authenticated | 1 |

**How to use it.** Not as a checklist — as a recognition aid at ONE moment: when you are about to write `done` / `complete` / `verified` / `ready` / `passed` / `covered`. Say out loud the proposition your evidence establishes, then say the proposition you are about to assert. If they are not the same sentence, report the one you have and name the one you do not. `merged; the release pipeline has not run` costs one clause and is true.

**What a reader here can and cannot check.** The rows sum to the stated total and that is verifiable in this file. The corpus behind them is NOT in this repository and cannot be: it is per-host agent session history carrying business identifiers, and it stays in private scratch under the extraction lifecycle rules. So the counts are **provenance-bound** — reproducible by whoever holds that corpus, opaque to everyone else. Treat them as what motivated the table, never as a measurement you can audit from here, and do not build a further claim on the exact number. The table earns its keep by whether the shape is recognizable when you next write `done`, which every reader can judge without the corpus.

**Why the table is a table and not a rule per row.** The rows are evidence that the invariant is real and recurrent; they are not the specification. A pair absent from this table is still the same defect — the table earns its place by making the shape recognizable, not by enumerating it. Do not extend it every time a new pair appears in the wild; extend it only when a pair recurs and the invariant alone did not catch it.

**Two families collapse into this one.** The environment row above was first classified as its own class ("an environment-layer failure reported as a product finding") and the whole-document-overwrite family as another ("the write succeeded" from "the command returned success"). Both are this invariant with different nouns, and `defect-diagnosis` already owns the substantive half of the first — its red-CI cause classification and its prove-it-from-the-tool-that-owns-the-state rule. Recording them as rows rather than as new rules is the point: the count is evidence of the shape, and three parallel rules would have taught three vocabularies instead of one invariant.

**Boundary.** This is about the PROPOSITION, orthogonal to `testing-strategy`'s strong/medium/weak evidence *quality* axis: a strong test can perfectly establish the wrong proposition, and that is the failure recorded here. Where a pair has an owner, the substantive rule lives there — release-versus-merge semantics with `release-coordination`, review verdicts in this gate, runtime-versus-static with `testing-strategy` — and this table only makes the class visible at the moment of claiming.


## When dual-track is mandatory

| Extraction type | Review | Challenge |
|---|---|---|
| New shared skill | required | required |
| Deep extraction (multi-batch over multiple sessions) | required | required |
| Multi-skill landing (≥ 2 skills changed) | required | required |
| Skill that ships operational rules (deploy, rollback, mesh, secret, audit) | required | required |
| Skill that ships architectural rules (boundary, lifecycle, retention) | required | required |
| Skill that ships security-sensitive rules (CORS, auth, secrets, callbacks) | required | required |
| Skill description / frontmatter rewrite (changes to triggers, Proactively-invoke, Skip-when, or capability statement) | required | required |
| Wording-only shared-skill edit (typo, grammar, formatting — NOT triggers, NOT routing, NOT description content) | required | not required |
| Single trivial shared-skill update with any non-wording change | required | required |
| Single trivial non-shared-skill update with no operational/security claims | optional | not required |
| Generator-owned shared skill regenerated through its tool | required independent review; generator validation is additional, not a substitute | required for any non-wording shared-skill change |
| Generator-owned non-shared skill regenerated through its tool | required (the generator's own) | required if rules changed |

Only the challenge pass may be skipped, and only when this table marks challenge not required; record an explicit `challenge: not-required, reason: ...` row in the validation log. Independent review for shared-skill changes has no skip row. A required review or challenge that is missing, inconclusive, or skipped blocks commit and landing; the work may only be reported as an uncommitted interim checkpoint until the required pass succeeds.

**Canonical wording-only criterion + the deterministic scope check (challenge-skip gate).** This is the single source of truth the L0/L1/L2 risk view (`l0-l1-l2-routing.md`) defers to; do not redefine it elsewhere. An edit qualifies as `wording-only` — and so may take the challenge-not-required row above — **only when BOTH** of the following hold, never on the author's say-so:

- **(a) Bounded change class.** The edit changes ONLY typo, grammar, formatting, or a meaning-preserving synonym, and changes NO trigger, scope, routing, validation, acceptance, rule/threshold/boundary text, or any other meaning. Reference/body prose that states a rule, threshold, boundary, rubric, or applies/does-not-apply line IS a semantic surface — editing it is NOT wording-only unless the change is purely typo/grammar/formatting with no meaning change. A synonym substitution usually cannot satisfy (b)'s deterministic evidence bar unless the proof avoids intent/meaning judgment. Description / frontmatter is never wording-only (see below).
- **(b) Deterministic scope check + independent review.** Dropping challenge for the edit requires a **deterministic scope check** — recorded controller-side or diff-based scope evidence that is decidable without judging intent or meaning, such as: touched files are formatting-only by formatter output; hunks are only meaning-inert whitespace / punctuation / markdown table alignment; or token-level changes are limited to a named typo correction while the surrounding rule sentence is byte-identical. If the proof depends on a human or LLM deciding whether revised prose changes a rule, threshold, boundary, applicability, or acceptance meaning, it is NOT deterministic and challenge stays required. The deterministic evidence **AND** an independent review row confirming the same must both be present. Either piece missing, or any reviewer-flagged / unconfirmed meaning / scope / trigger / routing / validation / acceptance change, **re-arms challenge + the behavioral-evidence row** (never demoted to "recommended").

The executable controller proof is intentionally narrower than every edit a
human might call wording-only. It accepts only a canonical full-context
Markdown diff inside one existing skill and recomputes either punctuation-only
changed lines or one named whole-token replacement with an exact count. Use the
schema and command in `code-review/references/staged-review-contract.md`; the
result must carry both `wording_only_scope.status=passed` and the independently
reviewed `wording_only_boundary` concern. Other grammar/synonym edits, custom or
context-augmented packets, multiple skills, and any unconfirmed meaning change
take the normal challenge path.

**If no such deterministic scope check can be formed for the change, challenge stays required.** This is a hard gate, not a default the author may waive: an LLM independent review is hypothesis-grade, so review alone never downgrades a non-wording change. Every shared-skill change still requires the independent review row regardless of class.

If either required pass times out, returns empty output, is rate-limited, cannot access auth, exits nonzero, emits malformed or truncated output, fails JSON/shape parsing when structured output was requested, lacks evidence that the pass inspected the target diff/files, shows a prompt/tool-scope mismatch, or returns any `inconclusive` status, the dual-track gate has not passed **for that lane via that reviewer**. A *recoverable-lane* failure — auth, quota, rate limit, timeout, local cache/db failure, or missing capability — is NOT a terminal stop and is NOT "the gate is unrunnable on this host": before you record `blocked`, you MUST walk the **Primary reviewer failure** remediation ladder below and route to an approved independent third-party reviewer (preferably a different model family) — either your runtime's native multi-model subagent (e.g. an OpenCode `Task`/council subagent on a separate model) or a shell wrapper such as `opencode_review.sh --model <provider/model> --implementer-family <author-family> --mode review|challenge`. A primary CLI lacking auth is a routing trigger to that fallback lane, never a license to declare the gate unrunnable. Only after that ladder is exhausted — every approved independent reviewer probed and unavailable — do you record the row as `pending` or `blocked`, include the remediation attempted (which ladder steps were tried) and the next unblock action, and do not describe the skill change as solved, complete, landed, or fully closed. (A large reviewer INPUT can also be silently middle-truncated, not just the reviewer's OUTPUT — see **Read-coverage of large inputs** under *Sanity checks the gate must enforce*.)

**Description / frontmatter rewrites are NOT wording-only.** The `description` field is the routing-surface that AI clients match user requests against to decide which skill to auto-invoke; changing it changes which asks the skill catches and which sibling skills it collides with. Treat every description rewrite as a multi-skill landing for the purposes of this gate, even when only one file changed. See `references/description-authoring.md` for the structure and validation checklist.

## Behavioral-evidence row (required for every non-wording shared-skill change)

Review + challenge check the change for defects; neither checks whether it actually moves agent behavior the intended way. Record one behavioral-evidence row per non-wording shared-skill change, in the same validation file. The building blocks already exist — pressure scenarios (`references/validation-and-landing.md`) and the test-case-first hard-check in `check-ccl-skills.sh`; this row makes recording one of them mandatory and uniform.

**Primary status** (pick one):

| Status | Use when |
|---|---|
| `RED-baseline` | the change alters behavior or routing (trigger / scope / routing / validation / acceptance). Run the scenario WITHOUT the change first (baseline failure), then WITH it (compliance) |
| `semantic-control` | a non-wording but semantic-preserving mechanical refactor (e.g. mega-bullet split per the B0 checklist). The **reviewer** confirms NO change to trigger / scope / routing / validation / acceptance, and an existing scenario or control still behaves identically. NOT for pure formatting — that is wording-only and needs no row |
| `not-applicable: docs-only` | the change touches NO file under `skills/**` and no skill-loaded guidance — i.e. `README` / `ARCHITECTURE` / `CONTRIBUTING` / `docs/**` only. Forbidden for `SKILL.md`, `references/**`, validators, templates, examples, and the plugin-shipped command/behavior surfaces (`hooks/*`, `scripts/install.sh`, `bin/`, `.mcp.json`, `.lsp.json`, `monitors/**`, `settings.json`): those are behavioral or executable source even when they read like prose |

For a `RED-baseline`, the evidence form can be a before-after task diff, a golden trace, or a pressure scenario — these are *how* you show baseline→compliance, not standalone substitutes for it. For a routing-surface / hub-skill change you can run the golden-trace form as a REAL headless-agent run via the F4 Tier-3 harness (optional, higher-fidelity than a recorded scenario — see `validation-and-landing.md` Behavioral Validation); a recorded scenario is not by itself a failing baseline.

**A change that ships a DESTRUCTIVE or irreversible operation** (a script/recipe that deletes/overwrites/prunes worktrees, branches, files, records; bulk or `--force`-class mutation) must EXECUTE its protected/NEGATIVE cases as part of the evidence — run it (in a throwaway repo/dir) and assert it does NOT touch what it must keep (unmerged commits, dirty/untracked/ignored files, the protected/default targets), not only that it acts on the intended input. A positive-only test ("it removed the merged one") does not establish safety; the data-loss footguns hide in the must-NOT-touch set, and the adversarial challenge will hunt exactly there (expect ~3–4 rounds for a stateful destructive recipe). Dry-run-default + a no-`--force` second net are design safeguards, not a substitute for executing the negative cases. **Executing the negative cases is necessary but NOT sufficient — the probes must be SENSITIVE, and this is the half that ships blind.** A negative probe that would still pass with the protecting predicate removed is evidence of nothing, and a suite of them reads as thorough coverage: the recurring shape is a degenerate fixture that makes every probe short-circuit on an unrelated conservative branch, so the safety predicate is never reached and a green suite certifies a hole. So the evidence row for a destructive change records, per protected predicate, that its removal was **applied** and observed to turn the suite RED — an unapplied "this mutation would fail it" is a hypothesis — and for the encoded form of that walk `testing-strategy` owns the rule (route, don't copy). Failure shape: a 9-probe negative suite for a worktree-pruning script passed fully green with its "only remove an actually-merged branch" predicate stubbed to always-true, because the fixture put the integration ref at the default branch's tip.

**Skill-TYPE refines the evidence FORM, never the status** (advisory; only when creating or substantially authoring a *whole* skill, not every small extraction). FIRST pick the primary status from the table above based ONLY on the diff — a whole new skill almost always adds a routing/discovery surface plus acceptance/use behavior, so it is a `RED-baseline` even when its CONTENT is Reference material; skill type never downgrades that status and never invents a fourth one. THEN use the skill type (classify per `superpowers:writing-skills` if installed, else inline — **Technique** = a method with steps; **Pattern** = a way of thinking; **Reference** = API/syntax/lookup material; plus **discipline-enforcing** = a rule/gate, which in `writing-skills` is a 4th *test category*, NOT a 4th Skill Type and NOT a 4th status) only to choose the evidence ARTIFACT within the already-chosen status: Technique → a RED-GREEN behavior trace; Pattern → applied-to-a-real-scenario evidence; Reference → source fact/coverage PLUS a lightweight retrieval + application + gap check (per `writing-skills`: can an agent find the right entry, apply it correctly, and are common cases covered — "correct docs, unusable skill" is the failure to catch), not link-correctness alone; discipline-enforcing rule/gate (TDD-like — and most of THIS workflow's own rules, e.g. worktree-isolation and the dual-track gate, are this kind) → its `RED-baseline` artifact is a **pressure scenario** (does the agent comply under combined stress — time / sunk-cost / exhaustion — not merely understand the rule academically). Type does NOT widen `not-applicable: docs-only`: a Reference-type skill under `skills/**` is still a shared-skill change needing review/challenge and a recorded evidence row.

Rules:

- `RED-baseline` is required whenever the change alters behavior or routing. `semantic-control` is valid ONLY with reviewer confirmation that none of trigger/scope/routing/validation/acceptance changed — an author cannot self-assert it.
- The row must give a concrete locator + evidence shape, not a bare status: artifact path / commit / transcript / command, the exact prompt or scenario, and expected-vs-actual. For `RED-baseline`, record BOTH the without-change (baseline failure) and with-change (compliance) results, and name the baseline's **provenance type**: a *recorded incident* (cite where the failure is actually recorded — transcript, note, issue; the cited record must describe a failure that occurred, not prescribe a method) or a *constructed scenario* (run against BOTH the unchanged baseline and the changed rule, with an openable artifact for each run — a scenario "run" only mentally, only against the patched text, or only as reviewer discussion does not count). A prescriptive source — a method-bar or best-practice note with no failure recorded — cannot be cited as an occurred failure and is not by itself a valid `RED-baseline`; it may seed the constructed scenario's design or support the rule's rationale, but the RED evidence is the run artifact. Narrating what "would have" failed as if it happened is a fabricated evidence row, the same defect class as fabricated verification output. A status word with no openable artifact is not a valid row, same as a missing review row.
- A missing or unreviewable behavioral-evidence row blocks landing the same way a missing review row does; until it exists the work is an uncommitted interim checkpoint.

## Running the review pass

### Freeze the packet against a base you have proven current

A stale base puts the upstream's newer fixes into the packet **reversed**, so the reviewer raises findings against code that is already correct — findings that read as real until someone re-checks history, and that cost a full round each. Freezing and currency are **different properties and the packet owes both**: pinning to an immutable commit stops the base moving mid-read, but says nothing about *which* commit. **Five properties, mutually independent — none implies another, so walk them as a list rather than holding them as a sentence.** Every observed failure of this check satisfied four and missed the fifth.

1. **Target-derived, not caller-chosen.** The landing lane's base is the landing target, derived from trusted configuration rather than an arbitrary caller-supplied `--base`. There is **no declared-intent exemption**: a declaration is author-controlled and cannot distinguish a considered pin from a stale one. A review deliberately scoped to a historical base — auditing what some past release shipped — is a separate lane whose result cannot satisfy landing review.
2. **Confirmed against the remote that owns the landing target, not against your fetch having run.** `git ls-remote <that remote> refs/heads/<branch>` is the authority — and **`origin` is not automatically it**: on a fork, `origin` is the fork and the landing target lives on the upstream, so querying `origin` confirms a SHA from the wrong authority. Record the **remote, ref, SHA, and the moment confirmed** together; a bare SHA does not preserve which authority supplied it and cannot be audited afterwards. The output must be **non-empty** before it is compared — the command exits `0` with no output for a branch that does not exist on the remote, so a naive comparison turns "the branch is gone" into a silent pass. A fetch that fails, or that succeeds without covering that branch under the configured refspec, leaves the old `origin/<branch>` resolving to a stale commit — a remote-tracking ref is a local mirror and cannot attest to its own freshness.
3. **Pinned to an immutable object.** Resolve that tip to a SHA, pass the SHA, and record it next to the packet hash. A ref *name* is not enough: it is mutable, so a sibling agent or background fetch between your resolve and packet construction moves it and the packet is built on a base neither recorded nor checked. Re-pin after any rebase or upstream advance mid-round.
4. **Independent of the candidate.** The base comes from the landing-target authority, outside candidate-controlled inputs. Immutability is not independence — a candidate can commit a tuned fixture and cite its perfectly immutable SHA.
5. **Contained in HEAD.** `git rev-list --count HEAD..<pinned SHA>` must be `0`, and nothing above implies it: the count passes while a wrapper builds from a stale local `dev` or an old SHA you supplied (a property of HEAD, not of the packet), and a correctly pinned current tip still shows the target's newer commits as *reversals* once the candidate branch has diverged. Count against the **branch tip** — not the derived base commit or a `merge-base HEAD <upstream>` (ancestors of HEAD by construction, so `0` for free), not the *local* branch (the fetch did not advance it), not a *different* branch than the real base. A non-zero count is not a note-and-continue: integrate the target first (`worktree-isolation` owns that sequence and its stale-overwrite hazard), then re-pin and rebuild. **Scoping the packet to the merge base instead does not discharge this** — a three-dot range hides the target's newer commits rather than reversing them, which fixes the reviewer-facing artifact and leaves the real gap: the candidate was never exercised against the code it will land on top of. That is the right bound for reviewing what an author wrote; it is the wrong bound for a landing candidate, whose artifact is the merge.

Walking all five is a **point-in-time attestation, not a lock**: the target can advance after you confirm and pin, while the packet is being built or reviewed. That is what item 2's recorded confirmation moment is for — the verdict covers that base only. So **re-query the authority at landing time, immediately before acting on the verdict**: if its tip is no longer the pinned SHA, the review is not landing evidence until the base is re-pinned and the round re-run. Stating the consequence is not enough without that second query — nothing else would ever detect the movement. A force-push or branch deletion is the sharp case: the new tip need not contain the old one, so "it can only have moved forward" is not an assumption available to you. Do not paper over the window by re-checking harder; bound it, and say when it closed.

When that check detects drift, rebuild instead of improvising: stop the reviewer
lane; preserve the named candidate manifest/patch and the caller-owned ordered evidence rows;
integrate the newly attested target in an isolated worktree; reapply only the
named candidate paths/rows; regenerate derived artifacts; compare the resulting
path set with the manifest; rerun the selected tests; then re-pin and rebuild the
packet. Never use a broad reset plus `add -A`, which can silently absorb ambient
work. Keep every base attestation in one ledger scoped from the first packet
until landing or a human scheduling decision; repinning, retrying, or rebuilding
does not reset it. Each row uses one remote/ref, a contiguous sequence, a strictly
increasing RFC3339 confirmation time, the corresponding controller-receipt hash
when a round consumed it, and a same-directory hash-bound file containing the
canonical raw `ls-remote` line. A second ordered SHA change (A→B→C or A→B→A) is
the second drift and must terminate the lane as `baseline_race`, with the
unreviewed delta; the drift row and every later row must not map another
controller receipt. For every non-race closeout — `ready_for_human_decision`
and `continuation_authorization_required` alike — the final controller receipt
must consume the latest attested SHA; later same-SHA live rechecks are allowed,
but an unconsumed newer SHA is not reviewed evidence (a post-final-round drift
belongs in the next round's ledger, not appended unconsumed to this one). Do not open another
automatic rebuild after the second drift. The state validator counts these
transitions and receipt/base associations inside the complete referenced row
set. Keep independent work moving while a human chooses a landing window.

**Until a wrapper enforces these, the caller owns them — and an unenforced obligation must at least be a recorded one.** No wrapper checks the five live-Git properties (observed 2026-08: `review_gate.sh` freezes whatever base it is handed, and neither wrapper fetches), so an agent that never loads this section can still pass a stale base. The v3 closeout validator makes referenced evidence tampering and broken round association detectable, but it cannot prove that a caller supplied every historical attestation or that the recorded `ls-remote` output is still current; candidate-local receipts are consistency evidence, not remote authority or an append-only log. Therefore **each review/challenge row carries the base attestation — remote, ref, SHA, confirmation moment — and a row without one is `base-unattested`, not landing evidence**, the caller retains the complete history across rebuilds, and item 2's live authority query is still repeated immediately before landing. Mechanising the live checks and history retention into a trusted wrapper/platform is follow-up work. This is the review-lane instance of the baseline rule in `external-practice-controls.md#designing-a-behavioral-evidence-measurement`: the packet is a measurement, and its base must be one the candidate has not moved.

> **Pick the reviewer — route through the owning wrapper before hand-rolling.** The gate needs an independent reviewer; it is **tool-agnostic**. Invariants regardless of tool: prefer a model from a **different family than the author** (cross-model catches shared blind spots — it is symmetric: Claude-authored → OpenAI-family reviews, OpenAI-authored → Claude/Moonshot reviews), and treat any sign-off as **hypothesis-grade** (verify load-bearing claims against primary sources). The agent running the gate, before reviewing:
>
> 1. **Resolve the organization `code-review` gate first.** It owns the installed-client checks, local `CODE_REVIEW_CLIENT_ORDER`, same-family exclusion, frozen packet, timeout, egress approval, tool boundary, and verdict parsing for Claude, Kimi, OpenCode, and Codex. Do not preselect a client from `command -v` output.
> 2. **Pass the actual implementer family.** A known same-family Claude, Moonshot/Kimi, or OpenAI/Codex client is excluded before inference; OpenCode is excluded after its exported session binds the actual provider/model family. An unmapped family is inconclusive, not permission to guess.
> 3. **Do not add a separate model behavior probe.** Claude, Kimi, and Codex validate the formal invocation stream; OpenCode additionally uses only the non-inference `debug agent ccl-review` structural check before its formal run. Availability/help checks are local and are not review evidence.
> 4. **Use another approved wrapper or runtime-native independent lane only when the organization gate itself is absent or cannot start.** Preserve the same bounded packet, read-only/no-exec posture, independent family, reviewer-emitted verdict, and review-vs-challenge separation. Raw CLI commands are debugging/reference shapes, not a shortcut around a terminal ccl-gate result.
> 5. **Run review and challenge separately.** Each result must bind its own mode, packet, selected reviewer, family, and verdict. A non-empty finding remains a finding; the controller never rewrites it into a pass.

### Primary Reviewer Unavailable

Primary reviewer failure is a remediation branch only when the owning gate classifies it as candidate-local. Use this ladder separately for the review lane and challenge lane:

1. Persist the owner-guided self-review and pass it through the required `--review-plan-file`. For non-wording extraction work, run `scripts/extraction_review_gate.sh` from round 1; a strictly proven wording-only lane uses the proof-bound generic `code-review` single-review recipe in `code-review/references/staged-review-contract.md`, without chain or completion flags. A host-returned live `session_id`/execution handle is still that same run: poll it to terminal exit and do not start a replacement or fallback from its empty current output. Record the handle type, opaque host transcript/tool-call reference and terminal exit. If the handle is lost, the lane is infrastructure-inconclusive/manual-review-required and no replacement or fallback may be started or credited; process-tree and wrapper artifacts are diagnostic only. This is a procedural host obligation because the inner gate cannot observe the outer handle; machine enforcement requires a trusted host adapter. Never persist a credential-like raw handle in shared evidence. If Claude then returns `auth_path_unavailable`, perform the one documented host rerun with the same frozen candidate, plan, stage, and `--host-remediation-attempted`.
2. Let the gate continue only for its allowlisted candidate-local classes: missing client/provider, bounded auth failure, quota/rate limit, timeout, missing capability, or malformed model output. It records every skipped/attempted client.
3. Packet/input/binding/tool-boundary, egress, same-family, mode, and unknown failures are not manually bypassed. A terminal result stops that lane.
4. If the organization gate could not start at all, an approved alternate wrapper or runtime-native lane may be used only with the same bounded packet, independent family, no-write/no-exec boundary, attribution, and parseable verdict. Do not invent a one-off provider/model chain.
5. A fallback result satisfies only the exact lane it ran. If no candidate returns a conclusive verdict, keep the work `interim`.

Do not call a manual ad-hoc run "fallback review" unless it meets the same evidence bar. Correcting a CLI argument mistake and rerunning is remediation; waiting forever, killing the process, or accepting partial stdout is not evidence.

- **Open the non-wording Agent chain on the FIRST review — it cannot be retrofitted.** A non-wording extraction's required review and challenge are one tracked multi-round run through `scripts/extraction_review_gate.sh`, so the round budget is decided before round 1, not after reading the review; a run that starts untracked or through the generic controller is thrown away and restarted. A strictly proven wording-only change instead uses the proof-bound single-review exception and opens no challenge chain or `complete` checkpoint. Every trigger, proof, index, prior-result and advisory rule behind those invocation shapes is owned by `code-review/references/staged-review-contract.md`, with controller options in `code-review/SKILL.md`; do not reconstruct them from this bullet.

- **Compose the packet — it is the mechanism that decides which finding classes are reachable at all.** The lever and its constraints are owned by `code-review`'s `SKILL.md` (packet-bounded reviewer; `--paths` only narrows; `--diff-file` supplies a packet you assembled), including the rule that an "input insufficient to judge" finding is an input defect rather than a candidate defect. What this workflow adds is the shared-skill inclusion list: alongside the diff, carry (a) the canonical rule or contract text the changed clause must not contradict, (b) the sibling clauses in the same section or file, (c) the derived carriers that restate the change — commit message, MR body, register row, `description` surface, (d) the actual output of any gate or script the change touches. Measured over one 11-round gate on a prose-rule change, a diff-only packet surfaced only defects in the tail of the just-edited sentence; the composed packet is what surfaced cross-clause contradiction, cross-carrier drift, and silent weakening of the canonical wording. Reach for packet composition before inventing another prose rule or a wording-level grep for the same defect class, and pick between candidate mechanisms by their hit rate over the round's actual findings, not by whether they feel in scope.

The following raw CLI shapes are **debugging diagnostics only**. They may help
isolate an owner-wrapper failure, but neither output is review/challenge evidence
and neither may replace `scripts/extraction_review_gate.sh` for a non-wording
lane.

Debug a wrapper with raw `codex review` against the target diff:

```bash
cd <skills-repo>
# Current codex: a custom PROMPT is mutually exclusive with --base / --uncommitted / --commit.
# Give a prompt (default scope = working-tree uncommitted changes):
timeout 540 codex review "<prompt>" \
  -c 'model_reasoning_effort="high"' \
  -c notify='[]' \
  --enable web_search_cached
# …or a scope flag with NO custom prompt: codex review --base <base-sha-or-branch> -c '…'
# Flag arity is version-sensitive — run `codex review --help` if either form errors.
# (codex review reads stdin only when PROMPT is `-`; the </dev/null gotcha below is codex-exec-specific.)
```

Prompt template (adapt as needed):

```
IMPORTANT: Do NOT read or execute any files under ~/.claude/, ~/.agents/, .claude/skills/, or agents/.
Stay focused on the diff.

Focus: <one-paragraph context — what was added/changed, what the references document>.

Specifically check:
1. Internal consistency across the touched references (any contradictions?).
2. Sanitization gaps (any residual ccl-specific names, IPs, hostnames, namespace names, vendor terms that look like real internal artifacts).
3. Technical accuracy of generic claims (etcd Watch semantics, Istio VirtualService routing, framework patterns, OTel/Prom/VM sizing, gRPC quirks, k8s control-plane behavior — whatever the diff touches).
4. Over-prescription: is anything written as MUST when industry has multiple acceptable patterns?
5. Cross-skill handoff coherence: boundaries clear, no overlap or gap between the touched skills.
6. Anti-patterns: is anything in 'Common Pitfalls' misclassified?
```

Output: one finding per line with severity (P0/P1/P2), file:line, scenario, fix. Apply each finding before the second pass.

## Running the challenge pass

Debug a wrapper with raw `codex exec` and an adversarial prompt (read-only):

```bash
timeout 540 codex exec "<adversarial-prompt>" </dev/null \
  -C <skills-repo> \
  -s read-only \
  -c 'model_reasoning_effort="high"' \
  -c notify='[]' \
  --enable web_search_cached \
  --json
# timeout + -c notify='[]' inline on purpose (see notes below): a stuck round-end
# notifier otherwise hangs a finished run; a timeout-kill (exit 124) = inconclusive lane, not a pass.
# BUT only disable a NON-policy notifier: if the host's notify is an audit/DLP/transcript control,
# drop -c notify='[]' and use a bounded non-blocking wrapper instead (see notes) — don't skip a required control.
```

Redirect stdin from `/dev/null` (**`codex exec` specifically**): `codex exec` reads instructions from stdin, so when the prompt is large, or it is wrapped in `timeout` / run in the background, it otherwise blocks on `Reading additional input from stdin...` and returns no output — it looks like a hang but is just waiting on stdin. `</dev/null` makes it read only the prompt argument. If a `codex exec` call sits at zero output, suspect a missing `</dev/null` before killing it. (`codex review` reads stdin only when PROMPT is `-`, so it does not have this gotcha — a quiet `codex review` has another cause.)

A **second, distinct** hang cause is the round-**end** `notify` hook, not the start-of-turn stdin read above: when the host's codex config sets a `notify` program (run on turn completion), codex waits for that program to return before exiting, so a `notify` command that blocks makes an otherwise-finished `codex exec`/`codex review` hang at the *end* with the full answer already produced. Neutralize it per-invocation with `-c notify='[]'` (override to no notifier — per-invocation only, so a notifier the host configured for normal runs is untouched). Only blanket-disable a **non-policy desktop/notification** hook; if the configured notifier is an audit / DLP / transcript-capture control, preserve it with a bounded non-blocking wrapper instead of disabling it, or you produce a clean-looking reviewer lane that skipped a required control. Always wrap the call in `timeout` so a stuck notifier bounds to a failed lane instead of an indefinite hang. A `timeout`-killed call (exit 124) or any partial/nonzero result is an **inconclusive lane per the failure rule above — never recorded as a clean "no findings" pass**; the point is to fail the lane fast and remediate, not to accept a truncated review. Verify the override for the installed version before relying on it — `codex --help` / `codex exec --help`, or a strict-config probe (`codex --strict-config -c notify='[]' <subcmd>` errors out on an unrecognized key, stays clean when `notify` is valid) — codex config keys drift across versions (there is no `codex config` subcommand to consult).

Prompt template:

```
IMPORTANT: Do NOT read or execute any files under ~/.claude/, ~/.agents/, .claude/skills/, or agents/.

ADVERSARIAL CHALLENGE mode. Review the new/changed reference files at:
<list the files explicitly>.

Your job: find ways an engineer who follows these references LITERALLY will produce
a production failure, security incident, data loss, or operational disaster. Be
brutal. Think like a chaos engineer + attacker + paranoid SRE + auditor.

Specifically hunt for:
1. Race conditions in described workflows.
2. Data loss / corruption paths.
3. Security holes (auth bypass, replay, credential leakage, CORS, mesh bypass).
4. Failure cascades (control plane down → no rollback; partition; upgrade ordering;
   trust-domain misconfig).
5. Algorithm flaws (thresholds at edge values, sample-size assumptions, retry budgets,
   timeout chains).
6. Operational footguns (broad-glob cleanups, single-instance "long-term" stores,
   HPA thrashing, override paths too easy).
7. Subtle inconsistencies between references.
8. Things readers would do WORSE than ad-hoc scripts if they followed the reference
   verbatim.
9. Gate-fireability / bypass-by-omission (REQUIRED when the change adds or edits a
   rule/gate/status/verdict — "when X, do/block Y"). Can Y be reached WITHOUT ever
   producing X? Is the trigger condition X a mandatorily-recorded field/output of an
   upstream step, or an optional signal a reader can simply never emit (no verdict
   recorded = never "rejected" = ships)? Who is allowed to set X — can the gated party
   self-adjudicate it? A gate whose trigger is never mandatorily produced is decorative.
   List every literal path that reaches the gated outcome while skipping the gate.

Output one finding per issue with: severity (P0 production-down / P1 high / P2
medium), file:line, the failure scenario in concrete steps, and the fix. Be terse.
No compliments.
```

For a rule/gate/status change specifically, item 9 is not optional padding: a generic
challenge (items 1–8) will pass a decorative gate because none of those classes asks
"is the trigger ever produced." The failure shape this prevents: a gate keyed on a
`rejected`/approved/verified verdict that nothing requires anyone to record, so the
gated outcome ships by simply never emitting the verdict — and a challenge run without
item 9 signs off on it.

Use `--json` to capture reasoning traces and tool calls cleanly. Parse the JSONL stream with a small Python or jq script as documented in `gstack-codex` skill.

## Reviewer verification scope (packet-verifiability boundary)

The external reviewer judges what the bounded packet can show; the packet structurally cannot carry every deterministic oracle its acceptance claims depend on (frozen preservation-mapping rows, the checker's complete pinned-literal sets, whole-file postimages, immutable pre-fix revisions). The division of labor is fixed and documented here so it is ruled on once, not re-litigated per round:

- The reviewer owns CONTENT SEMANTICS: wording coherence, dropped qualifiers/obligations, source-accuracy, sanitization, scope drift — everything decidable from the packet plus the reviewer's own reasoning.
- Deterministic-gate claims (pinned literals present, size ratchet net-zero, obligation audit green, R0 clean, parity) are verified by the repository's CI re-running those gates on the actual branch — never by the reviewer, and never accepted from the implementer's prose alone; a finding that only restates this boundary is dispositioned against this rule, never re-litigated per round.
- Historical-process claims (a pre-fix RED, a measurement taken before landing) are session-record-grade unless bound to an immutable revision or a candidate-bound receipt; treat them as the implementer's testimony, and say so in the disposition instead of demanding evidence the packet cannot hold.
- The receipt channel for the third bullet is landed: `scripts/gate_receipt.py mint --out <ledger-dir>/gate-receipt-N.json -- <gate command>` binds one deterministic-gate run to the committed candidate — clean tree required, HEAD commit recorded, argv + repository-relative cwd + exit code + output SHA-256 + RFC3339 mint time, with an off-by-default opt-in output tail (a verbatim excerpt would copy a leaked token into the ledger; receipts are created 0600) and a post-run candidate re-read that refuses a result when HEAD moved mid-run; a RED run mints fine (the pre-fix RED is the canonical use). Receipts live OUTSIDE the candidate tree (the chain ledger directory) and ride the packet by reference: name the receipt file plus its own SHA-256 in a review-plan `evidence` entry or a disposition-evidence `evidence` item, so `review_context_sha256` / the v3 ledger's sibling-hash discipline bind it. Anyone re-checks with `gate_receipt.py verify <file>` (structural) or `verify <file> --rerun -- <the gate command you expect>` at the recorded commit — the verifier types the command and the tool compares it against the recorded argv before executing only the verifier's own words, because a receipt is untrusted input and its recorded argv must never be executed as-is (differential exit-code + output-hash comparison; `--exit-only` for a legitimately nondeterministic gate, and say so in the referencing row). Trust model, stated so it is not oversold: a receipt is candidate-bound, falsifiable consistency evidence — it does not authenticate who ran the command; deterministic authority stays with CI re-running the gates on the actual branch (second bullet), and a process claim carrying no receipt remains testimony under the third bullet.

## Recording findings + fixes

For each pass, record in the extraction's working file (e.g. `<project>-extraction-summary.md`):

```
## Review pass (codex review)
- Findings: N total (a P0 / b P1 / c P2 / d P3)
- R0 evidence: <alias_audit_ok | named private-profile result: project-alias/process-retro/both | alias_audit_unavailable or generic_r0_leak_scan_ok => private R0 not run / interim, not landing-clean>
- Applied: M fixes (commit: <sha>)
- Deferred: <list with reason>

## Challenge pass (codex exec adversarial)
- Findings: N total (a P0 / b P1 / c P2)
- R0 evidence: <alias_audit_ok | named private-profile result: project-alias/process-retro/both | alias_audit_unavailable or generic_r0_leak_scan_ok => private R0 not run / interim, not landing-clean>
- Gate-fireability applicability: <yes — change adds/edits a semantic rule/gate/status/verdict | no — valid ONLY when the diff is wording-only or adds/edits no semantic rule/gate/status/verdict>
- Item 9 exercised: <locator to the captured prompt/transcript/JSONL showing the bypass-by-omission probe actually ran (not a pasted self-assertion) | n/a per line above>
- Applied: M fixes (commit: <sha>)
- Deferred: <list with reason>

## Behavioral evidence
- Status: <RED-baseline | semantic-control | not-applicable: docs-only>
- Artifact + outcome: <locator: path/commit/transcript/command> · <exact prompt/scenario> · <expected vs actual> (RED-baseline: include both without-change and with-change results; semantic-control: name the reviewer who confirmed no behavior change)
```

Each fix lands as its own commit when meaningful; small fixes can batch. The commit message lists the issues addressed (by review-pass severity + short description).

## Sanity checks the gate must enforce

- Both passes ran against the actual target diff, not an older snapshot.
- All P0 findings have an applied fix OR an explicit acceptance with documented mitigation in a deferred-fix note + a tracking ticket.
- All P1 findings have an applied fix OR an explicit deferred row with reason.
- P2/P3 findings may be deferred more freely; track for the next pass.
- Re-run sanitization after fixes (fixes can introduce new leakage).
- Re-run `check-ccl-skills.sh` after fixes.
- **Inspect the validator output for `alias_audit_unavailable`.** `check-ccl-skills.sh` exits 0 even when the private R0 alias audit never ran (`ALIAS_AUDIT_CMD` unset); in that case its final token is `ccl_skill_check_interim_ok` (with `r0_status=public-fallback`), not the clean token. When unset it runs the public fallback (`generic-r0-leak-scan.sh`) and prints `generic_r0_leak_scan_ok` + `alias_audit_unavailable`; that fallback is diff-scoped public evidence, not the private audit. Only a clean private audit ends on `ccl_skill_check_clean_ok` (with `r0_status=private-ok`); a deprecated `ccl_skill_check_ok` line is still printed for old consumers but is no longer the last line or a sufficient signal. Review/challenge evidence MUST read the full output and treat any `alias_audit_unavailable` / `ccl_skill_check_interim_ok` as **private R0 not run** — a no-findings review that ignores it (or that accepts the clean generic fallback as if it were the private audit) is **inconclusive** for landing readiness, not a clean pass. The R0 lane is satisfied only when the output shows `alias_audit_ok` / `ccl_skill_check_clean_ok` or the record cites a named private-profile result (see `r0-leakage-audit.md`); neither the deprecated `ccl_skill_check_ok`, the interim token, nor `generic_r0_leak_scan_ok` alone closes it.
- A behavioral-evidence row exists with an allowed status and a referenced artifact; `RED-baseline` is used for any change that alters behavior or routing.
- **Read-coverage of large inputs**: if any touched file, required reference, or supplied diff exceeds ~200 lines or ~8 KiB (`wc -lc`, objective — not the author's to wave off as "not relied on"), the pass is **inconclusive** unless its transcript shows chunked reads (each under **both** limits) covering the changed hunks plus their owning/referenced sections; naming the exact unread line ranges only **downscopes** the verdict to what was covered — any unread changed hunk or owning/referenced section keeps the pass **inconclusive**, it does not make it conclusive — a single whole-file read drops the middle (codex keeps only head+tail past 256 lines / 10 KiB, [openai/codex#6426](https://github.com/openai/codex/issues/6426)). Tool-call presence alone (an `nl -ba`/`sed -n` line) does NOT satisfy this — a single oversized `nl -ba` still drops the middle. This is the review-lane application of the always-on read-in-chunks rule (`agent-context/session-start.md`; detail in `references/source-to-skill-extraction.md#read-in-chunks-large-reads-lose-the-middle`). The 256-line / 10-KiB cutoff is version-drift-prone: record `codex --version` and probe locally when the exact cutoff is load-bearing. (Separately, `project_doc_max_bytes` is a host config budget for project-doc ingestion — verify the version's default — and does NOT affect tool-output truncation.)
- **For a NON-WORDING change that adds/edits a semantic rule/gate/status/verdict, the challenge row's `R0 evidence`, `Gate-fireability applicability`, and `Item 9 exercised` fields must be present, and the latter two must be affirmative** (a wording-only edit inside a rule sentence — with NO trigger/scope/routing/validation/acceptance meaning change, per the strict line-31 table — is out of scope; mark applicability `no` with that reason). A generic challenge that reused an older prompt without item 9 passes a decorative gate, and a row with no `R0 evidence` field can hide `alias_audit_unavailable` by omission, so a row missing those fields is **inconclusive** for the gate change regardless of finding count, and must be re-run with item 9 plus R0 evidence recorded. This is the canonical validity criterion; the no-findings section and the per-round log reference it rather than restating it.
- **Tool-boundary capability review heuristic (advisory):** when a wrapper claims `no tools`, `read-only tools`, or an exact tool set, reviewers should distinguish permission allow-rules from availability restrictions and inspect the installed tool's preferred live-help branch, effective argv/config, inherited extension surfaces, and runtime-init data when exposed. A fake CLI that omits the production-preferred flag proves only its fallback, and prompt wording or directory-add flags are not filesystem sandboxes. This is a review lens, not a new landing field/status gate; executable enforcement belongs in the wrapper's capability probes, runtime checks, and regression tests.

## When the challenge pass returns "no findings"

A genuine no-finding result from a high-reasoning-effort adversarial pass is rare but valid. Validate by:
- Confirming the prompt actually asked for adversarial finding (not a summary).
- Confirming the pass read the actual files (look for tool-call lines like `nl -ba <file>` or `sed -n`). For inputs over ~200 lines / ~8 KiB this is necessary but NOT sufficient — a single oversized `nl -ba` still drops the middle; satisfy the read-coverage check above (chunked ranges covering the changed hunks + owning/referenced sections).
- Confirming the model had time to run (high reasoning + bounded by timeout).
- For a non-wording rule/gate/status change, confirming the challenge row's `Gate-fireability applicability` and `Item 9 exercised` fields are both present and affirmative (per the sanity-check validity criterion above) — a no-findings pass from a prompt that never probed bypass-by-omission is inconclusive for the gate, not a clean pass.

If the pass returned no findings within seconds, treat it as failed (likely a prompt error or auth issue) and rerun.

## Iterating: challenge → fix → re-challenge

A single challenge pass is not always enough. Fix-ups can introduce new bugs, and challenge passes have stochastic depth — what one pass missed, the next may surface. Plan for multiple rounds when the change is non-trivial.

### The pattern

Each round produces three classes of finding:

1. **Genuine issues from the original change** — what challenge was meant to catch.
2. **New issues introduced by the previous round's fixes** — e.g. a fix narrows a regex but the narrowed version misses a real case; a fix moves a routing pointer but the new location creates a different collision.
3. **Pre-existing issues codex notices on second look** — often P2/P3, often deferrable, but worth recording.

After applying fixes from round N, re-run the challenge. The next round should produce strictly fewer findings AND no new P0/P1 from the round-N fixes themselves. If round N+1 surfaces a P0 the round-N fix introduced, the fix was wrong — revert or redesign before continuing.

### Do not bias the re-challenge (gate integrity)

Each round — first and every re-challenge — must give the reviewer the artifact and an open "find any remaining P0/P1" instruction. The one thing to withhold is your own **fix-claim**: any list, changelog, or self-assessed conclusion stating which issues you fixed or that prior findings are resolved ("I fixed X, Y, Z", "all prior findings addressed"). A fix-claim primes the reviewer to confirm those specific items and skim the rest, so a "CONVERGED" verdict certifies a gate that was never actually re-tested. This holds even when every claimed fix is real: findings from the first pass, or newly introduced by the patch, go unexamined. A round run with a fix-claim through *any* channel does not count — re-run it clean before claiming convergence or landing.

Run the reviewer in a **fresh, isolated context**. A re-challenge in the same chat/session that already contains "I fixed X/Y" from earlier turns is already primed even if the new prompt is clean — the fix-claim leaked through conversation history and tool logs. Use a separate reviewer invocation (a fresh `codex exec`, a new session) whose only inputs are what you deliberately supply; if you cannot isolate, explicitly audit that no fix-claim sits anywhere in the reviewer-visible context, not just in the prompt you typed.

Withhold the fix-claim through every channel that reaches the reviewer, including commit messages in a `git show` / PR-patch / log view, and fix-claims **embedded in the artifact itself** — a changelog entry, PR-template line, or code comment that says "fixed the P1 cancellation race". Redact or omit such review metadata for the gate run (strip or mask in-artifact fix-claim lines and commit messages), not a disclaimer that the text is unverified — a disclaimer still primes. The sole exception: when the fix-claim text *is* the product surface under review (e.g. you are reviewing the changelog's accuracy itself), it stays, because then judging it is the task.

Removing the fix-claim must not shrink or distort the artifact. Give the reviewer the **complete, exact landing candidate** — the full file list and full diff for the whole change set, never a path-filtered subset or a hand-assembled patch. A subset is itself a bias: it hides a finding the author didn't think to include (a P1 introduced in a teardown file outside the "interesting" path). Three precision requirements so this can't be gamed:

- **Right SHAs.** Diff the verified base (the target merge-base with the branch you'll land into) against the *exact* head that will land (the PR head / landing-candidate HEAD), not an intermediate commit or a stale base. A "complete" diff of the wrong revision range certifies nothing.
- **Everything that will land.** If staged-but-uncommitted, untracked, or generated files are part of the landing artifact, include them (commit to a verified candidate tree, or require a clean working tree first). `git diff <base> <head>` silently omits them.
- **Redaction preserves content.** When you strip an embedded fix-claim, neutralize only the narration with a placeholder and keep the file, hunk, and surrounding lines intact. If the line also carries behavior or user-facing content, you cannot mask it without changing what's reviewed — fall back to the product-surface exception and leave it in.

Withholding is only about the *fix-claim narration*, never about the *scope or fidelity of code shown*.

Neutral, non-leading context is encouraged, not withheld (starving the reviewer causes the opposite failure — a false "no findings"). Safe to supply: the artifact/diff, the original requirement / acceptance criteria, reproduction steps, and the threat model. A scope statement is allowed but must be **additive, never exclusive** — "review the entire artifact for any P0/P1, especially surfaces X/Y/Z", never "focus only on X". An exclusive scope is path-filtering by instruction: the full diff is attached but the reviewer is steered past a P1 introduced elsewhere (a teardown file outside the named surface). Two cases need care:

- **Prior accepted/deferred risks**: supply them so settled tradeoffs aren't re-litigated, but only with their acceptance evidence (who accepted, when, why) attached, and tell the reviewer it may re-raise any of them if this change alters their severity. Without verifiable acceptance evidence, present the item as open — an author must not silently relabel a live P0/P1 as "accepted" to suppress it.
- **Prior reviewer findings**: may be resurfaced as raw open items in the reviewer's own words (never "I fixed X"), but only as the *complete* prior set or a stable reference the reviewer can actually open — never an author-picked subset, since choosing which to resurface re-biases scope exactly like a fix-claim. Any resurfaced material (inline or behind a reference) must be sanitized to reviewer findings plus acceptance evidence only — a linked thread or doc that still contains author fix-claims re-primes through the back door and is not a valid "complete history". If the full history is too large to inline, attach at minimum every prior P0/P1 verbatim plus an accessible pointer to the remainder, and tell the reviewer the omitted lower-severity items still need a severity re-check under this change.

(Self-extracted: an agent-runtime reference in this tree was reported CONVERGED off a fix-list-primed re-challenge; an unbiased re-run surfaced real remaining P1s — partial-stream double-dispatch, cancellation-vs-error path split, finalization-vs-idle-wake race, abort-cleanup deadlock.)

### Findings, autonomous budget, and human authority

A candidate may be claimed review-ready only when **every** remaining P0/P1 finding has a disposition — there are exactly three, each evidence-backed, not the author's word. Missing disposition blocks the readiness claim and the next external review; it does not stop implementation or unrelated work:

- **fixed** — the patch resolves it (and the re-challenge that confirms this is unprimed, per the gate-integrity rule above);
- **accepted** — recorded as `deferred: <reason>` with acceptance evidence (who/when/why);
- **pre-existing & out-of-scope** — recorded with evidence it existed at the base SHA **and** that this change does not increase its reachability or severity. A latent deadlock the old code never reached but the new code now can is in-scope, not pre-existing. An unaudited "that was already broken" is not a valid disposition.

A **scope-cut / out-of-phase** finding (the scope-direction signal in `SKILL.md`) is not a new disposition or severity. On first appearance, before implementing, it is a **classification checkpoint, not a cut**: **(1)** test current-phase impact — any current execution path, data/authority boundary, contract commitment, or diff-added reachability **or severity**; a remediation that merely looks deferred never proves its absence (a live defect whose repair happens to need future machinery is current-phase); **(2)** split a compound finding. These signals can co-occur: if the recurrence is *also* same-risk-class, run the delete-capability existence evaluation (`keep / delete / narrow / replace`) on it too — scope-cut applies only to the no-current-impact residual and never waives that evaluation. The current-phase core takes its normal disposition above at its real severity — P0/P1 via the three dispositions, P2/P3 under normal non-blocking handling — and is **never cut**. Only a residual with **no** current-phase impact — *proven by recorded negative evidence* (the specific execution paths / data-authority boundaries / contracts / reachability actually checked), never by assertion — is a cut candidate: the controller proposes that residual and **a risk owner distinct from that proposing controller reviews the original finding, confirms the impact classification and split, and decides before anything is reverted** (a self-approval fails the `accepted` who/when/why bar; with no distinct risk owner available, do not cut at any severity — not-cutting governs only the scope-cut operation and never downgrades blocking, so the finding then follows its normal disposition, P0/P1 blocking and P2/P3 non-blocking). An approved cut lands as one of the three dispositions above plus a tracked follow-up **recorded now in a durable tracker that the deferred phase OWNS and its own entry/acceptance gate CONSUMES on entry** (a reverse-consumed link, not just a forward reference), with an owner and a reopen trigger, so that phase cannot claim done until the finding is re-dispositioned under the then-current gate. You need not build that gate now, but the tracker must be one the phase's start is bound to read; if no such phase-owned, gate-consumed tracker exists (the reverse link can't be established), do not cut — keep the P0/P1 blocking. The cut thus defers rather than discards, and the controller never self-accepts convergence. Recurrence across 2+ rounds that stays **undispositioned** — or was implemented despite a prior out-of-phase classification — is the reviewer-lane stop/reframe escalation; an already evidence-backed accepted/deferred finding that a later unbiased challenge legitimately repeats is not, **but only after it is re-verified against the exact current candidate** (fresh recorded evidence that its current-phase paths/boundaries/reachability/severity have not changed since acceptance — the same freshness bar as `pre-existing & out-of-scope`; any delta invalidates the old disposition and reruns classification, split, and risk-owner approval). Throughout, the severity that routes a finding is the **reviewer's assigned severity** (per `references/review-finding-standards.md`), never re-rated by the proposing controller, and the scope-cut safeguards (recorded no-impact evidence, distinct-owner ratification, phase-owned consumed tracker) attach to the cut operation **at any severity** — a finding can never be discarded by self-rating it P2/P3.

- When the recurring surface is a **self-adjudication clause** — decidable test: the clause's classification verb has NO named test whose output produces the classification, so the receiver/author judges it — the `keep / delete / narrow / replace` decision must first ask whether an existing mechanical or semi-mechanical test can carry the adjudication: name the test whose output settles the classification, **and the mapping from its output to the classes** — which output means which class — plus the actual result or the evidence contract that will produce it. Naming a test is not routing to it: a test whose output cannot discriminate the classes, or one named with no recorded output-to-class mapping, leaves the adjudication exactly where it was and does not satisfy this rule. A `keep` that retains self-adjudication prose, or a `narrow`/`replace` that adds more prose bindings, is landed only when the decision record (the same-class rule's recorded decision, in the commit body or register row) names the reason no existing test could carry it — a reason left in chat does not count; two challenge rounds attacking the same self-adjudication surface are the signal that prose is the wrong layer — a clause routed to an existing test inherits that test's evidence bar instead of the adjudicator's say-so (worked instance: a review-reception clause that left "is this finding scope-adding" to the receiver survived two rounds of attacks on that self-classification until the classification was routed to the existing structural-minimality test). The same question fires at drafting time for any new reception/discipline-style clause that would grant a self-adjudication.

"No *new* P0/P1 this round" and "findings stabilized into the same categories" are necessary but **not sufficient** — a finding repeated unchanged across rounds is still unresolved and still blocks landing until it gets one of the three dispositions. Convergence means *no undispositioned P0/P1 remains*, not *no new P0/P1 appeared*.

**A convergence or closure declaration must be written falsifiably.** Name the exact candidate identity it covers, each lane's terminal evidence, the axes/dimensions the closing self-audit actually crossed, and every standing open item by name (e.g. "the final challenge's own fix has not itself been re-challenged") — an aggregate "converged / all axes closed" whose axes are unnamed cannot be checked false and is inconclusive, and any "full X" adjective is scoped to the named axes, never wider. The named enumeration is what lets a fresh challenge falsify the claim by pointing at an un-crossed axis (observed both ways in one program: a self-audit that named its five walked axes was caught exactly one axis short by the final challenge — the naming is why the gap was findable — and the honest handoff that named its open item let the human choose between one fresh pass and explicit risk acceptance instead of inheriting a false "done").

Do NOT iterate to zero *findings* — some are intentional design tradeoffs the user already rejected the alternative for, some are genuinely pre-existing. Forcing the finding count to zero either over-corrects or scope-creeps. The bar is zero *undispositioned P0/P1*, which is different from zero findings.

The initial independent review plus Agent-initiated challenges share one **Agent-autonomous external-review budget of at most five rounds**. The initial review consumes round 1, so `challenge_budget` is `0..4`. Candidate edits, commits, rebases, amended plans, renamed slices, or a fresh controller invocation do not create more Agent authority. A stateless local controller cannot prove omitted history against a caller that controls its files, so the consuming workflow must preserve the complete review ledger and treat an Agent-created reset as a contract violation.

Five is the generic `code-review` transport ceiling, not this extraction lane's
spend. Non-wording Agent-autonomous extraction calls go through
`scripts/extraction_review_gate.sh`, which fixes `challenge_budget=1`: the
initial review plus at most one challenge. At round 2 the autonomous lane ends.
An authenticated human may request later review, but that is separately
attributed human-requested evidence outside this chain/budget, never an
additional Agent round. Unused generic capacity never authorizes automatic continuation.
The v3 closeout validator rejects referenced receipts whose recorded budget is
not the wrapper-fixed value and checks budget and ordering consistency within the caller-supplied
set. It cannot authenticate that the wrapper produced those receipts or that
the caller retained every earlier chain or receipt. The wrapper does not mint or
persist
`review_chain_id` or `autonomous_review_index`: the caller still supplies both,
and could start a fresh-looking chain after the final round. The validator detects bad
order inside the referenced set but cannot detect a prior chain the caller
omitted, so complete caller-owned ledger retention—and treating an Agent reset
as a contract violation—remains part of the boundary rather than a property the
local scripts prove.

**Self-hosted chains break on every fix; the budget is summed across chains, never per chain.** In a skill repository the candidate edits its own owner package by construction, so the chain's stable bindings make the dead-end the norm, not an edge case: the selected-owner digest hashes each owner package's current working tree and owners derive from the candidate's own paths, so a fix that touches any selected-owner tree ends the tracked chain (`review_chain_invalid`) — in an extraction round that is nearly every fix, while a fix confined to files outside every selected owner drifts only the candidate hash and continues in-chain — and a plan edit that changes the normalized review scope (intent, acceptance, stage/depth, risk tags, budget) ends it as `review_scope_changed` — a self-review- or evidence-only plan refresh keeps the scope digest and the chain (binding mechanics are owned by the staged review contract in `code-review`). A chain restarted at index 1 after such a break spends the SAME Agent-autonomous budget. Treating each restarted chain as a procedurally required fresh review loop is the observed way the budget hollows out: two consecutive extraction rounds ran 20+ reviewer rounds and then 12 restarted chains — 21 reviewer invocations to land a three-line diff — each restart looking locally mandatory. When a round returns findings, walk this enumeration before any further external call:

1. **Batch dispositions; never re-chain per finding — and hold fixes until the ledger can afford their application.** Triage every finding through the disposition bar and deep-self-review once, then decide when the batch lands by budget arithmetic, never by the urge to fix now: applying any fix to a selected-owner tree ends the tracked chain, so apply-now is legal only when the remaining ledger can still fund a restarted chain's ready floor. **Under the wrapper-fixed 1+1 budget that condition is NEVER true after the review round — the one remaining round cannot fund review plus challenge — so there the rule is unconditional: accumulate every fix unapplied, run the challenge on the frozen, unchanged round-1 candidate, and land the whole batch only after the full review+challenge chain has run, MR/PR-listed.** A fix applied between review and challenge breaks the chain (the challenge binds to the round-1 candidate), forfeits the double-receipt terminal, and costs a fresh human-authorized chain to recover — an observed failure, not a hypothetical: a round that landed its review fixes before the challenge had to be closed by a user-granted continuation chain.
2. **Sum spent rounds across all chains before opening one more.** Count every prior external round in the caller-retained ledger — every chain, finished or broken — against the lane's wrapper-fixed budget; at the cap a restarted chain must not be opened autonomously, and below it budget the restart so the final chain can still hold review plus one challenge (the closeout ready floor) — a restarted chain opens with a fresh review by contract, so every restart trades a challenge round for a review round. Effective exhaustion is reached when the remaining rounds cannot fund that floor for any continuation; treat it exactly like the cap.
3. **Front-load packet quality in chain 1.** The first chain's packet must already be the full-context diff (`--unified` wide enough to carry whole files, e.g. `-U200`) with the plan frozen alongside the candidate; narrow packets breed packet-boundary pseudo-findings whose fixes break chains and burn rounds on artifacts of the packet itself.
4. **At the cap — or at effective exhaustion — the designed terminal is disposition, never another chain.** Apply or disposition the final batch, name every post-review fix in the MR/PR description, record the honest terminal state (`continuation_authorization_required` when the lane's final round ran and itself returned findings; otherwise — including a chain broken before its challenge could run — an interim record naming the last externally reviewed candidate and every later delta), and hand continuation or merge to the human. The post-review batch sits only on the pending MR/PR branch beside that record — the human's authenticated continuation, waiver, or merge decision is what certifies it, and it is never reported as reviewed. This is the bounded outcome working as designed, so do not report it as convergence and do not launder it through a fresh-looking chain.

A strictly proven wording-only change has no convergence loop: it uses one
generic `code-review` pass, records the independent-review row and the
challenge-not-required proof, and does not create a schema-v3 multi-round
terminal ledger. This exception does not apply to frontmatter, routing,
validation, acceptance, example, owner or behavior changes.

This budget limits only automatic reviewer invocation. It does **not** stop implementation, tests, debugging, or deep self-review, and it does not limit an authenticated human:

- A human may request another review or self-review, stop a live review or the overall iteration, commit, or merge. Record human-requested review separately from Agent-autonomous rounds.
- A human merge/risk decision must come from platform-authenticated authority outside the candidate diff, such as a protected maintainer approval. A repository file, branch flag, CLI argument, environment variable, model statement, or Agent-written note is not human authentication.
- A narrow authenticated `review_waiver` clears only the review-process gate for the exact candidate and records decision-maker, time, reason, residual findings, and accepted risk.
- A distinct authenticated `merge_authorization` is the human's final decision for the exact candidate. CI still runs and reports review/build/test/security/compliance failures, but none remains merge-blocking after that decision. Report `merge_authorized_by_human` / `failed_but_human_overridden`; never rewrite any underlying result as `passed` or discard residual findings.
- A distinct authenticated **`continuation_authorization`** is the third human state, for a budget that is exhausted or has dead-ended: it waives nothing and decides no merge — both lanes stay intact and blocking — the human only authorizes further external rounds toward convergence, each recorded as human-authorized (never counted as Agent-autonomous) and run as a fresh chain bound to the current candidate — a fresh chain restarts the candidate binding, never the history: it carries forward the complete review ledger and every prior round's focuses and dispositions, per the Agent-review-chain fields of `code-review`'s staged review contract. The grant itself is scope-bound, not reusable: it names the granting session and either one exact candidate or, explicitly, this program's rounds to convergence in that session — a candidate or session outside the named scope requires a fresh authorization, so recording rounds as human-authorized can never launder an expired or broader-than-granted continuation. The dead-end is **by design, not an error**: a finding's fix that edits the owner package's own files breaks the review chain's content binding, so the tracker rightly refuses both another autonomous round and a challenge bound to the stale prior result. While cross-chain budget remains, that break is handled autonomously by the self-hosted-chain rule's ledger-counted restart; it becomes this bullet's human-decision dead-end when the remaining budget cannot fund the re-review. The recovery at that point is always the same shape — an `interim` checkpoint that names each lane's terminal state and the exact un-run remainder ("challenge not yet run against any candidate", "the final fix is pinned but not re-challenged"), then the human's continuation authorization or their explicit risk acceptance with the record as the disposition trail. Never Agent self-authorization, and never a lane waiver inferred from the human's silence or from the authorization to continue.

When a round returns findings, hand them to the implementer before another autonomous review. The implementer verifies each failure path, classifies it as a local fix, false positive, deferred risk, or human decision, and records targeted self-review plus tests. Do not blindly apply every suggestion and do not use the reviewer as the primary defect finder.

The mechanical reminder is `self_review_gate`, not prose alone. It records outstanding and satisfied triggers, the narrow blocked actions, and the productive actions that remain allowed. It fires before external review, after findings, after a tracked candidate change, on risk/scope escalation, at the post-budget checkpoint, and before a completion claim. A final passed review stays `completion_gated=true` until the exact-candidate local `complete` checkpoint validates the new deep-self-review plan; this checkpoint invokes no reviewer and grants no human authority.

In this gate, `stop`, `terminal`, `abort`, or `revert` applies to the current reviewer lane, readiness claim, or defective dependent slice unless an authenticated human explicitly stops the overall iteration. Repeated root cause, two no-progress attempts, or recurring findings trigger a method change, narrower reproduction, redesign, validation switch, or parked decision item; they never auto-stop unrelated runnable work.

At the final Agent-autonomous round, do not start another automatically. If findings remain:

- keep fixing local bugs, testing, and self-reviewing under `post_review_budget / human_decision_required`;
- record the last externally reviewed candidate and every later candidate delta; stale review evidence never certifies changed content;
- mark findings that need product/design/risk authority as `needs_human_decision`, freeze only dependent work, and continue independent runnable slices;
- enter `awaiting_human` only when no independent runnable work remains. This is a scheduling state, not task failure and not a human merge prohibition.

The terminal checkpoint is an extraction closeout record, not a state emitted by
`review_gate.py`, and its schema-v3 state is derived from evidence rather than
trusted as an author assertion. Schema-v2 closeout ledgers are rejected rather
than silently reinterpreted under the breaking occurrence/evidence shape. The
ledger and every referenced controller, completion, base, and sweep file live
in one directory and carry SHA-256s. The validator walks the ordered schema-v3
controller chain (same chain and scope,
review then contiguous challenges, packet=candidate, complete prior-result hash
prefix, the wrapper-fixed `challenge_budget`) and binds every closeout candidate to its
last receipt. Ready requires at least review + challenge; a second base drift may
stop as race immediately after round 1 rather than spending an illegal challenge
after the terminal predicate already fired.
It ends in exactly one state:

- `ready_for_human_decision`: a real `complete` receipt is `passed / self_reviewed`, binds the final external receipt and exact current candidate, and there is no unresolved finding occurrence, unreviewed delta, or unmatched sweep instance.
- `continuation_authorization_required`: the final round itself returned `findings / post_review_budget`; a passed/unknown/inconclusive state cannot be relabelled continuation.
- `baseline_race`: the referenced ordered base rows contain a second SHA change, including A→B→A; there is no completion receipt and the unreviewed delta is non-empty. Open findings and unmatched sweep instances remain visible and do not prevent this stop state.

Run `scripts/validate_extraction_review_state.py <closeout.json>` before reporting
the state. This proves internal consistency and coverage of the files the ledger
references. It does **not** authenticate that no earlier receipt/attestation was
omitted and does not replace the live remote recheck above; the caller still owns
complete-history retention until a trusted platform owns it. An exhausted budget,
stale review, omitted evidence, or unknown lane state is never represented as
convergence.

### Concrete cadence

For a focused single-skill change:
- **Round 1 — independent review**: inspect the self-reviewed candidate broadly.
- **Round 2 — challenge**: after implementer triage — fixes stay HELD: under the 1+1 budget applying any fix before this round always breaks the chain, so the challenge runs on the frozen round-1 candidate (self-hosted-chain rule; enumeration item 1 above) — attack the highest-risk unresolved surface with an unprimed prompt. This is the final Agent-initiated external round; findings feed the post-budget checkpoint rather than an automatic further round, and the post-review fix batch lands MR/PR-listed.

Broad extractions use the same fixed two-round Agent budget. Continue their implementation in smaller independent slices after budget exhaustion; a human may explicitly request further review when useful.

### Anti-patterns

- **Single-round challenge → done**. The round-1 fix-up itself may introduce bugs. Always do at least one re-challenge after a non-trivial fix-up.
- **Iterating external review until zero findings**. Stop Agent reviewer calls at the configured budget. Stabilized or repeated findings are recorded, triaged, and may cause a method/design change or a parked dependent slice; implementation and independent work continue.
- **Treating "no new high-severity findings" as "ready to ship" without recording the deferred items**. Deferred findings still need a written reason in the validation log.
- **Treating every tiny edit as an automatic new external round**. Re-run deep self-review at the required checkpoint; consume another Agent review round only when the retained chain and risk call for it, or when a human explicitly requests one. The observed extreme is chain multiplication: a chain broken by your own fix and restarted at index 1 is the same budget, not a new loop — sum rounds across chains per the self-hosted-chain rule above.
- **Re-running with a softer prompt after fixes**. Use the same adversarial framing every round; weakening the prompt to make later rounds "pass" defeats the purpose.

### Recording the loop

Add one row per round to the validation log:

```
## Challenge pass — round N (codex exec adversarial)
- Diff scope: <files / commit range / sha>
- Findings: N total (a P0 / b P1 / c P2)
- R0 evidence: <alias_audit_ok | named private-profile result: project-alias/process-retro/both | alias_audit_unavailable or generic_r0_leak_scan_ok => private R0 not run / interim, not landing-clean>
- Gate-fireability applicability: <yes | no — reason>; Item 9 exercised: <captured prompt/transcript/JSONL locator per the single-pass field above, not a pasted self-assertion | n/a>
- New since prior round: <count> (subset of above; flag round-introduced bugs)
- Stabilized: <list of findings carried over without change>
- Applied: M fixes (commit: <sha>)
- Deferred: <list with reason>
- Decision: continue implementation / park dependent slice / await human / human stop, because <reason>
```

A complete dual-track-validated change names every round explicitly. Skipping rounds without recording the decision is the same as not running them.

## What does NOT count as dual-track

- Two reviews of the same kind (e.g. two consistency reviews from different reviewers — both still miss chaos modes).
- Self-review by the extractor before submitting (catches obvious things but not adversarial scenarios) — insufficient as independent *evidence*, but NOT skippable: the self-audit-to-convergence preparation above is still required before the gate runs.
- Static validation script (covers YAML/links/sanitization, not chaos modes).
- Human PR review without an explicit challenge framing (humans default to consistency review unless prompted).

The challenge pass is **structurally different** from review — it must be invoked with an adversarial prompt. The same model can do both passes, but each pass needs its own prompt and its own output.

## Cost note

Challenge pass at high reasoning typically costs 2-5× review pass in tokens. For a ~3 kLOC reference diff, expect ~250-500k tokens on challenge vs ~50-100k on review. The value of one P0 finding caught before landing dwarfs the cost difference; do not skip on cost.

## 错误锚点：用错的尺子量对的实现

验证 oracle 用的**锚点本身可能是错的**，而这比 oracle 出错更难发现——因为**其余锚点会继续通过**。

当锚点的预期方向来自**你对一手源的解读**时，该解读是 hypothesis-grade。锚点不过，第一步应是质疑锚点、回到源的机制陈述重新推导预期，而不是判实现有 bug。否则两种后果：要么去「修」一个正确的实现，要么——更危险——因为其余锚点通过而接受一个错的。

观测实例：验证色觉障碍模拟时，用「红色模拟后应变暗」作锚点，实测亮度上升。回到一手后确认：模拟把颜色投影到**单侧二色视者双眼一致的不变轴**（protan/deutan 取 475nm 与 575nm），红投到黄轴、亮度上升是算法的**正确行为**；而「红色看起来暗」说的是**红与黑难以区分**，是另一个量。另外两个锚点（灰阶不变、已知色对靠拢）当时都通过。
