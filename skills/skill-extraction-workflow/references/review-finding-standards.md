# Review Finding Standards

Shared output standard for any code/plan/design review, regardless of who runs it (human, Claude, Codex, an external review wrapper) or which path produced it. Two things must mean the same across all reviewers, or review and dual-track convergence are theater: **how severity is calibrated** and **what makes a finding actionable rather than noise**.

This file does NOT teach what to look for — that craft is owned where it is operational (see Non-Goals). It standardizes only the finding's severity and shape.

## Severity Rubric

Calibrate by *consequence and reversibility*, not by how clever the bug is or how confident the reviewer feels. Definitions are behavioral, not domain-specific. This file sets what each level *means*; the accept / defer / convergence mechanics that decide whether a landing may proceed are owned by `dual-track-review-gate.md` — apply both together.

- **P0 — must block landing.** Security breach, data loss/exposure, irreversible destructive action, auth / permission / tenant bypass, money/quota error, or production outage. These stay P0 *even when a later mitigation exists* — the ability to rotate keys, restore a backup, refund, or re-run a job does NOT downgrade enduring harm (exposure already happened, trust/auditability already breached). A P0 clears only by an applied fix, rollback/removal of the change, or an explicit risk-owner exception (not a routine owner sign-off) that records mitigation plus a tracking item per `dual-track-review-gate.md`. "Mitigation + ticket" must never be a rubber stamp on a known catastrophic risk.
- **P1 — should block landing.** Serious correctness, reliability, regression, privacy, or user-trust failure with a *genuine* recovery path — defined narrowly as complete restoration with no external exposure, no tenant/user-trust breach, no lost auditability, no unrecoverable money/quota effect, and no required customer or security incident response. Clears by an applied fix or an explicit deferred acceptance recording reason + residual risk; it does not silently pass. If a failure meets the P0 categories above, it stays P0 — you cannot reclassify it P1 by asserting a recovery path.
- **P2 — worth fixing, not landing-blocking.** Localized bug, maintainability issue, confusing copy, weak-but-present test, minor edge case. May be deferred freely; track for the next pass.

Scale reconciliation: some gates add an optional **P3** tier for nits / informational notes — treat it as a non-blocking sub-tier of P2. Structured finding schemas that accept only `P0|P1|P2` (e.g. `code-review`) fold P3 into P2.

Same tiers, different input: the P0/P1/P2 blocking semantics here are the canonical definition, and they are reused for **test-case priority** in `test-artifact-management` (P0 = must pass before release, P2 = nice-to-have). The difference is only the *input* that picks the tier — a review finding's tier comes from the defect's consequence/reversibility (above); a test case's tier comes from scenario centrality (primary/security path → P0, edge → P1/P2). The tier meaning (P0 blocks shipping — "landing" for a finding, "release" for a test case — P2 does not) is identical, so the two never need separate definitions.

Notes:
- When unsure between two levels, state the failure path and let consequence decide; do not average to the middle.
- "Style / preference" with no failure path is not a finding at any level — see noise below.
- Evidence quality is not severity. If a claimed P0/P1 lacks a concrete failure path, require clarification or mark the review **inconclusive** — do NOT lower the severity just because the report is under-specified. An under-described auth bypass is an inconclusive-blocking escalation, not a quietly-downgraded P2.

## Finding Quality

Every finding must carry the first three; the fourth is required when it can be known:

1. **failure_path** — the concrete way it breaks or gets exploited, specific enough to reproduce or trace ("on duplicate callback the row is written twice"), not a category ("idempotency issue").
2. **impact** — who/what is harmed and how badly; this is what sets the severity above.
3. **evidence** — a code path, a violated invariant, a reachable precondition, a threat-model step, a prior-incident pattern, or a reproduction. A *clean reproduction is not required* — hard-to-reproduce classes (races, prompt-injection, auth edge cases, distributed flakiness, supply-chain) are legitimately evidenced by a reachable code path plus plausible exploitability. What is rejected is speculation with NO code-path, invariant, or threat-model basis.
4. **smallest_fix** — the smallest credible change that closes it (not a redesign). When the reviewer can prove the breakage but cannot safely prescribe the patch (security, concurrency, infra, product-policy), use `owner investigation required` instead. Missing fix guidance lowers actionability; it does not erase a proven finding.

Noise, to be rejected before it enters a review result:
- vague approval/disapproval ("LGTM", "looks risky") with no failure path;
- restating what the code does without naming a failure;
- pure speculation with no code-path, invariant, or threat-model basis (distinct from an evidence-backed risk that merely lacks a clean repro — that is a real finding, and an uncertain high-impact one routes to `inconclusive`/escalation, never to noise);
- scope-expansion suggestions ("while you're here, also rewrite X") unless they close a named failure;
- duplicate findings that restate one root cause as several.

**Validity contract (this file owns this; the gate owns the consequences).** A result is one of three states:
- *findings* — one or more entries each meeting the bar above;
- *no-findings* — a valid, strong result ONLY when accompanied by an inspection record: scope reviewed, files/diffs actually inspected, any checks/commands run, explicit limitations, and reviewer/tool attribution. An empty list with no inspection record is `inconclusive`, not "no findings";
- *inconclusive* — empty/partial/tail-only/timed-out/unparsable output, an unverified claimed-blocking finding, or a no-findings result lacking the inspection record.

`dual-track-review-gate.md` owns what each state does to a landing (block / accept / defer / rerun); this file owns what makes each state valid.

## Non-Goals (route, do not duplicate)

This file standardizes the *output* of a review (severity + finding shape + validity), not its *depth*. Output conformance is not review depth: a finding set that fits this shape but was produced by a shallow skim is still a weak review. So before applying this standard, **name the review lens** — pick the owner/checklist that matches the change's risk (the routes below); if none applies, state explicitly what lens you used to decide what to look for. Then do NOT grow this file into a bug taxonomy, security checklist, or test strategy — route those to their owners:

- which risk classes a change carries / which gates apply → `feature-risk-router`
- what tests miss, assertion strength, scenario coverage → `testing-strategy`
- adversarial / chaos failure modes and when two review passes are required → `dual-track-review-gate.md`
- stack-specific pitfalls → the per-stack dev skills
- CLI/tool invocation mechanics for a specific reviewer → e.g. `code-review`

If a candidate rule names specific bug classes, it belongs in one of those owners, not here.
