# L0 / L1 / L2 Routing — Risk-Tiered Extraction Paths

Phase 1 material for the risk-tiered extraction model (design source: `docs/skill-extraction-optimization-design.md`). This reference defines the **five-step analysis front door** and the **three landing paths** (L0 / L1 / L2). It does NOT weaken any existing gate: R0, dual-track review, provenance isolation, the routing analyzer, and `check-ccl-skills.sh` stay exactly as the Core Rules define them. The tiers only decide *gate strength*, never *gate existence*.

## L0 / L1 / L2 is a risk VIEW over the canonical gates, not a second gate set

The tiers are a **risk-tier router** onto the canonical dual-track / shared-skill gates — a way to read "how strong must the gates be for this change", never a parallel or competing set of canonical rules. The canonical definitions (what `wording-only` means, when challenge may be skipped, what independent review and behavioral evidence require) live in `dual-track-review-gate.md`; this file points at them and must not restate or fork them.

| Tier | Canonical classification it maps to | Canonical gate owner |
|---|---|---|
| L0 | Not a shared-skill landing (private scratch / route / backlog only); never lands skill content | n/a — leaves the shared tree, so no canonical gate runs |
| L1 | Non-wording, non-routing shared-skill change | `dual-track-review-gate.md` (review required; challenge + behavioral evidence required for any non-wording change) |
| L2 | High-risk shared-skill change (routing surface, R0, authorization, validation standard, user sovereignty, cross-owner gate, eval runner/task-bank) | `dual-track-review-gate.md` + routing analyzer (`eval-routing.md`); same mandatory gates plus behavioral regression |

The wording-only / challenge-skip question is owned in ONE place — `dual-track-review-gate.md`'s canonical wording-only criterion + deterministic scope check. The tiers never define their own skip path.

## Five-step analysis (五步分析法) — the prerequisite, not a substitute for the tiers

L0 / L1 / L2 answer "which path", not "did I analyze". Run the five steps FIRST; the tier is the output of step 4, and step 5 must be written back to closeout.

| Step | Question it must answer | Primary output | Link to the gates |
|---|---|---|---|
| 1. 定义问题 (define the problem) | What failure / drift / recurring friction must this prevent? Is it even a skill/process problem? | problem statement + explicit non-goals | Decides whether to extract at all; an ordinary bug routes to `defect-diagnosis`, pure wording routes to `tighten-doc` |
| 2. 收集证据 (collect evidence) | What is first-hand evidence vs second-hand judgment or model inference? | evidence card / source register | No first-hand evidence ⇒ no RCA; even L0 records the evidence gap |
| 3. 归因抽象 (attribute & abstract) | What is the root cause? Can it abstract into a reusable pattern? Does an existing owner already cover it? | RCA + reusable pattern + owner map | Default to merge/route; do not promote a one-off event into a hard rule |
| 4. 分层决策 (tier decision) | discard, route, L0 capture, L1 standard change, or L2 high-risk change? | L0/L1/L2 verdict + gate checklist | Sets the strength of R0, dual-track, behavioral evidence, routing eval; a failure-class reusable lesson cannot be demoted to an L0 backlog |
| 5. 验证闭环 (close the verification loop) | How do we prove no leakage, no drift, and that agent behavior improves? | R0 result, review/challenge, behavioral cases, rule-budget note, closeout | Both doc-compliance and behavioral effect must be re-checkable; "review ok" alone is not closure |

The tiers sit downstream of this: L0 is the lightweight result of steps 1–4 (not a landing proof); L1 enters the standard shared-skill change gates from step 4; L2 enters the high-risk gates from step 4; step 5 writes verification evidence back to closeout for later audit.

## Path selection at a glance

```
experience / failure / retro / external benchmark
        │
        ▼
   five-step analysis
        │
 reusable AND a skill/process problem?
   │no                       │yes
   ▼                         ▼
 discard / route        evidence card / source register
 to original owner            │
                       L0 / L1 / L2 tier decision
```

## L0 — Capture Card / 轻量经验卡

Use L0 when ALL hold:

- a single small process lesson;
- not yet sure it is worth a shared-skill change;
- does NOT touch `description`, triggers, Skip, redirect, or any owner gate;
- adds NO new hard rule;
- no sensitive source text or real project detail would enter a shared document.

**L0 is not a bypass channel.** Two hard limits:

- **Storage**: an L0 evidence card lives ONLY in per-host scratch / a private alias. The moment a card or its conclusion enters `skills/**`, a skill reference, a loading instruction, or this repo's plugin behavior surface, it is no longer L0 — it must take the shared-skill gates (L1 or L2).
- **Failure-class escalation**: a reusable lesson exposed by a *failure class* — routing miss, shallow retro, validation gap, wrong-ownership, missed gate — does NOT go to L0 `backlog`/`discard`. It MUST upgrade to L1/L2 and land at least one durable prevention point in this workflow or the owning target.

An L0 verdict is exactly one of: `discard` (not reusable), `route` (back to the original owner), `backlog` (revisit once a second piece of evidence appears), `upgrade-to-L1/L2` (enter formal extraction). L0 never claims "the skill is fixed" — it only captures and routes.

## L1 — Standard Skill Change / 标准技能变更

Use L1 for a non-routing, non-wording shared-skill change: add/modify a reference; add a template, checklist, or rubric; clarify one skill's internal process — without changing the routing surface or the user-authority boundary.

Any shared-skill landing — L1 or L2 — must clear the **three mandatory gates the Core Rules own**. A tier is never a lighter version of them:

- **R0 zero-hit leakage audit** — the automatic `audit_cmd`, zero hits across every leakage category (`references/r0-leakage-audit.md`). A sanitize/grep pass is *input* to R0, never a substitute for it; an informal sanitize does not satisfy R0.
- **dual-track review** — independent review + adversarial challenge (`references/dual-track-review-gate.md`).
- **provenance / lifecycle isolation** — project provenance stays in per-host scratch / private alias; the shared tree (incl. commit / branch / MR record) carries only label-based capability rules (`references/extraction-lifecycle-handoff.md`).

L1 then adds:

- charter;
- an evidence card or a short source-register table;
- sibling-map / owner-map (incl. the impact-chain row when an upstream-owner skill changes);
- a **behavioral-evidence row** — defer the exact status model to `references/dual-track-review-gate.md`;
- a closeout validation row recording each gate / track's command, result, and disposition;
- `check-ccl-skills.sh` + `git diff --check`.

**No-downgrade rule.** L1 is the path for non-wording shared-skill changes; it is NOT a shortcut that lowers existing gates. Every shared-skill landing keeps the **independent review row**, and a non-wording-only change always requires **challenge + the behavioral-evidence row** — those cannot be dropped. Whether an edit qualifies as `wording-only` (and may therefore skip challenge) is decided **only** by the canonical wording-only criterion + deterministic scope check in `references/dual-track-review-gate.md`; this file does not restate or fork those conditions. The author may not self-certify the classification, and an LLM independent review is hypothesis-grade, not a verdict (`references/review-rubric.md`), so review alone never downgrades a change to wording-only. The conclusion carried here: if the canonical deterministic scope check cannot prove the edit is purely typo / grammar / formatting / synonym with no meaning change, challenge stays required, and any reviewer-flagged or unconfirmed meaning / scope / trigger / routing / validation / acceptance change re-arms challenge + the behavioral-evidence row.

Escalate L1 → L2 whenever the change touches a routing surface, R0, authorization, the validation standard, user sovereignty, a cross-owner gate, or the eval runner / task-bank.

## L2 — High-Risk Route / 高风险变更

Use L2 when the change touches any of:

- `description`, triggers, `Use when`, `Skip`, redirects;
- bootstrap / owner routing;
- R0, sanitization, provenance, user authorization, merge policy, or a verification gate;
- default development behavior or a cross-skill lifecycle gate;
- the eval runner / task-bank / routing-decision logic.

L2 inherits the **three mandatory gates** above (R0 zero-hit audit, dual-track review, provenance / lifecycle isolation) — automatic R0 is the landing gate for **any** shared-skill landing, not an L2-only step. When the automatic R0 command is unavailable, the landing records the result as `inconclusive` / `manual-only residual risk` and treats the manual fallback as NOT an R0 pass (`references/r0-leakage-audit.md`); L2 additionally records that residual risk explicitly at closeout. On top of the mandatory gates, L2 adds:

- a full charter;
- full provenance / source register;
- sibling-map / impact-chain;
- **behavioral regression** — at least one should-trigger AND one should-not-trigger case; this is the L2 routing / behavioral-regression minimum, and the exact status model is deferred to `references/dual-track-review-gate.md`;
- the **Tier-1 routing analyzer** when a routing surface is touched (`references/eval-routing.md`);
- closeout recording findings, disposition, and residual risk.

For L2, a clean LLM review is not sufficient on its own — the mandatory gates, deterministic checks, and behavioral regression must also pass (see `references/review-rubric.md`).

## Anti-misuse guardrails

| Risk | Guardrail |
|---|---|
| Tiers misused to downgrade a gate | Touching routing / R0 / authorization / validation standard forces L2; L1's no-downgrade rule keeps challenge + behavioral evidence required on any meaning change |
| L0 becomes an unverified conclusion | L0 may only `capture` / `route` / `backlog` / `upgrade`, never claim landed; failure-class lessons cannot stay at L0 |
| Tiers replace analysis | The five-step analysis is the front door for every path; the tier only sets gate strength, it does not replace problem definition, evidence, RCA, or the verification loop |
