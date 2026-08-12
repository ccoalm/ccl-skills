# Quality Remediation Program

Structure for a cross-cutting, multi-phase engineering-quality initiative — a "quality special project" / planned technical-debt paydown across architecture, implementation, and code structure.

This is a distinct work type from its neighbors, which is why it has its own reference:
- An **existing-project assessment** (`existing-project-assessment-report.md`) ends at diagnosis plus next actions; it does not own a multi-week program with metric baselines and exit gates.
- A **single behavior-preserving refactor** (`refactoring-discipline.md`) owns one change; it does not own program sequencing, baselines, or stop-the-bleeding institutional changes.

This reference owns the **program shape and per-phase exit gates**, and routes each phase's execution to the smallest owning skill.

## When to use

The request is a cross-cutting, multi-phase quality initiative ("做一次质量专项", "治理工程质量", "整体架构/实现/质量偏差怎么规划", "pay down tech debt as a program") rather than one feature, one bug, or one isolated refactor. Also use it when a team wants to **establish and hold an engineering-quality baseline on an existing project** — raising and protecting quality as ongoing practice, not as a one-off cleanup.

## Two operating modes

The same phase logic runs at two altitudes; pick the lighter one that fits the request, and record which mode and why. When debt already makes normal iteration unsafe or slow, or the hotspots being touched have no safety net, default to campaign rather than continuous (or record why continuous is still sufficient) — do not pick the lighter mode just to avoid closeout pressure:

- **Remediation campaign** (heavyweight, time-boxed): a deliberate quality special project / tech-debt paydown that runs all phases to a defined acceptance, then ends. Use when debt has accumulated enough that normal iteration is unsafe or slow.
- **Continuous baseline-and-hold** (lightweight, standing): for an existing project that is simply raising and protecting quality while it keeps shipping features. Run Phase 0 once to capture starting numbers, stand up the Phase 1 new-code gates permanently, and add Phase 2 safety-net coverage incrementally — mandatory before any refactor or behavior-risking change to a hotspot, never deferred under delivery pressure — with no time-boxed campaign required.

**Minimum standing floor — every existing project should have this, campaign or not:** Phase 0 baseline numbers recorded, plus Phase 1's changed-line-scoped new-code gates live (gate intent and thresholds are owned by Phase 1 and `testing-strategy`, not redefined here), enforced with Phase 1's anti-gaming controls — suppressions and analyzer-config weakening need owner approval, generated/vendored code is excluded, test deletions are reviewed, and coverage is mapped to the changed behavior/risk surface, not just touched lines. This floor stops the bleed and makes quality measurable; Phases 2–4 layer on as need and capacity allow. A project with neither a recorded baseline nor new-code gates has no quality baseline, regardless of how much one-off cleanup has happened. The floor covers *ordinary* quality debt only: when a change touches a high-risk surface (security / permission / privacy / money / data-isolation / high-impact-AI), that surface's baseline is not "held" until it also has `feature-risk-router` classification, a known-bad inventory, and the selected high-risk gates from `high-risk-resilience-gates.md` — gates-plus-baseline alone is never sufficient there.

The failure modes, exit gates, stop conditions, and ownership boundaries below apply to both modes. The only difference is program closeout: a campaign drives each phase to its exit gate and then *ends*, so `complete` (every exit gate has evidence) is the goal; continuous mode has no closeout and runs Phase 1 — plus the parts of Phase 2 it has reached — indefinitely. "No closeout" does not weaken evidence discipline: every phase that has been reached, and every hotspot touch, still needs its relevant exit-gate evidence (Phase 0 baseline numbers backed by command output, Phase 2 RED/GREEN on the touched flow). The phase-order invariants do not relax in either mode: the Phase 2 safety net for a given hotspot is still mandatory before any Phase 3 refactor of it.

## Core principle: phase order prevents three failure modes

Quality programs fail in three predictable ways; the phase order exists to block each:

- **No baseline → no acceptance.** Without quantified before-numbers the program becomes an unbounded refactor with no definition of done. → Phase 0.
- **Refactor before stopping the bleed → debt re-accumulates.** If the conventions and CI that let debt grow stay unchanged, cleaned-up code rots again. → Phase 1 before Phase 3.
- **Refactor before a safety net → regressions.** Large legacy hotspot files usually have no tests; refactoring them blind ships bugs. → Phase 2 before Phase 3.

If time pressure tempts skipping Phase 0 (baseline) or Phase 2 (safety net), treat that as a process defect, not a shortcut.

## Phases (each has an exit gate)

### Phase 0 — Baseline & charter
- Quantify current state with repeatable commands: hotspot / largest-file inventory, static-analyzer warning count, test coverage, CI presence and status, and production defect/crash rate where available (if unavailable, mark stability targets provisional and name a substitute signal). Exclude generated / vendored / non-owned code from hotspot and size metrics.
- Classify high-risk surfaces now (security / permission / privacy / money / data-isolation / high-impact-AI) with `feature-risk-router`, so no later phase touches them ungated.
- Pick the program driver (stability / iteration speed / maintainability / test foundation, or a custom driver such as security / compliance / cost / DX with matching metrics). The driver decides Phase 3 ordering.
- Define quantified acceptance targets per driver as before → target pairs.
- Follow the host workflow's branch/worktree and clean-tree preflight before broad edits.
- **Exit gate:** a baseline report exists with a real starting number per target, backed by command + output + commit evidence (not mere file existence). Missing baseline → the program is `interim`, not started; scoped emergency stabilization is allowed only with the missing baseline documented and a follow-up baseline task filed.

### Phase 1 — Stop the bleeding
- Add CI gates that block *new* debt, scoped to changed lines/files: no net-new analyzer warnings, changed-line coverage non-decreasing, and a size/line cap on new files as a review trigger (not a hard block that fragments cohesion). Dry-run gates against unchanged mainline first and promote to blocking only after they pass clean; track any suppression as debt needing owner approval. Route gate thresholds and CI placement to `testing-strategy`; this phase names gate *intent*. Global-percentage coverage gates are gameable and can punish deletion/refactor — do not use them as the bar.
- If evidence shows a repo/team convention is blocking scoped, test-protected structural improvement (for example a contributor guide that forbids all structural change), revise it *with the convention owner's approval* — unapproved convention edits are advisory drafts only. Flip the default from "no structural change" to "structural change allowed when it is test-protected, small-step, and inside a scoped program task"; keep the prohibition on *unscoped* churn and pure-style noise so the original over-correction is not merely reversed.
- Add a PR/review gate scoped to the program.
- **Exit gate:** new code can no longer pile onto hotspot files unprotected; the revised convention is owner-approved and merged.

### Phase 2 — Safety net
- Before locking any behavior, inventory known-bad behavior on high-risk surfaces (security / permission / privacy / money / data-isolation / high-impact-AI) that must NOT be preserved; fix those (route via `feature-risk-router` / `high-risk-resilience-gates.md`) instead of characterizing them. Characterization tests freeze whatever exists today, bugs included — freezing a security or compliance defect is a failure, not coverage. On a high-risk surface, a "no known-bad behavior" conclusion needs the domain/security owner's signoff plus evidence of a defect / vuln / incident search, not a bare assertion.
- For the rest, add characterization tests (golden / snapshot / widget / contract, as fits the stack) that lock current observable behavior; route layer and fixture selection to `testing-strategy`. Where a target's refactor will touch shared contracts or transitive consumers, add dependency-impact mapping and contract/integration coverage for those seams, not only the hotspot file.
- Classify each target as **test-lockable** or `needs-seam` before relying on it as netted: some logic (library-private, or entangled with native / platform / UI machinery) cannot be locked without first changing production code to expose it, so "add characterization tests" is not always a drop-in. A `needs-seam` target is blocked, not covered — it gets an owner and a resolution path, is barred from Phase 3 until netted, and must not be papered over with low-value tests that raise the count without locking risk. The minimal enabling seam-cut needed to create the locking test may happen before Phase 3, landing together with that test (otherwise netting deadlocks); the target's full structural refactor stays barred until netted. Route seam design and locking-test-layer choice to `refactoring-discipline.md` and `testing-strategy`.
- **Exit gate:** the targeted flows verify RED/GREEN, the known-bad inventory is recorded so no defect is silently frozen, and any `needs-seam` target is excluded from the ready-for-Phase-3 set and reported as an explicit not-done row in the Phase 4 acceptance report.

### Phase 3 — Controlled refactor
- Order targets by risk-adjusted ROI — change-frequency × defect-density × business-risk × testability — and defer targets too unsafe to start until confidence and coverage are higher. Do not auto-pick the most-churned critical file first if the team lacks domain confidence in it.
- Each refactor is behavior-preserving, test-protected, and committed in small steps, each with a rollback path; gate runtime-impacting changes with staged rollout / feature flags per `high-risk-resilience-gates.md`. Route single-change discipline to `refactoring-discipline.md` and stack execution to the owning development skill.
- **Exit gate:** targeted hotspots meet their size/structure targets with all safety-net tests green and no behavior regression.

### Phase 4 — Institutionalize
- Keep a running decision log from Phase 0 onward; consolidate it here so Phase 1/2 lessons are not lost to the end of the program.
- Write the new structural rules back into the repo convention / team doc so the improvement holds.
- Compare final metrics against the Phase 0 baseline; report before → after per driver.
- Route any reusable cross-project lesson through `skill-extraction-workflow`.
- **Exit gate:** an acceptance report shows before → after numbers for each target and the new rules are merged.

## Stop conditions

Any regression on a security / permission / privacy / money / data-isolation / high-impact-AI surface is an immediate pause-and-rollback, regardless of count. For the softer signals — regressions traced to the refactors, CI instability from the new gates, or a target trending away from its goal — set numeric thresholds up front (for example N regressions in a week) and name the stop authority, rather than leaving "repeated" or "below the bar" to in-the-moment judgment. Re-baseline or re-scope before resuming.

## Exit-gate evidence

Every exit gate needs evidence, not artifact existence: the command run, an output excerpt, the commit SHA, the scope, and the owner/reviewer. When a phase routes to another skill, that skill's concrete output (test file, gate config, plan) must be linked in the phase evidence, or the routing is ceremonial.

## Ownership boundaries

- This reference owns the program shape and phase gates.
- `feature-risk-router` and `high-risk-resilience-gates.md` own high-risk surface classification and resilience gating (used from Phase 0 onward).
- `existing-project-assessment-report.md` owns the Phase 0 diagnosis report format.
- `testing-strategy` owns Phase 1 new-debt CI-gate design and Phase 2 layer / fixture / CI-gate selection.
- `refactoring-discipline.md` owns Phase 3 single-change behavior preservation.
- The owning stack development skill owns the actual code changes and rendered/runtime evidence.
- `skill-extraction-workflow` owns Phase 4 durable lesson landing.

A program is `complete` only when each phase's exit gate has evidence. A skipped Phase 0 baseline or Phase 2 safety net is a process defect, not a shortcut.
