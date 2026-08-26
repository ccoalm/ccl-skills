# Firing-point placement — worked recurrence-chain + the owner-dispatch implementation

Companion to the **firing-point-placement corollary** in `SKILL.md` (under *Retrospectives, corrections & auto-triggered learning*, in the repeated-user-corrections rule). The Core Rule carries the gates: under-trigger is a tracked failure class; the self-trigger is recognition-dependent (bootstrap raises salience but is not mechanical); the two mechanical backstops (closeout gate + user-signal escalation); and the red-line — when the same meta-class recurs at a *new* sub-point, move the owning gate's firing point ONTO the transition and sharpen *name→invoke*, not more prose. This file carries the **worked recurrence-chain** (the concrete history that justifies the corollary), the **landed mechanical implementation** for the owner-invoke case, and two expansions relocated from the Core Rule: the self-detect firing point's authority boundary + observed shape, and the record-field corollary's forgery-surface mechanics. The gates themselves stay in the Core Rule.

## The worked recurrence-chain (why "move the firing point", not "add another bullet")

The same meta-class — a rule is precise but is walked past at the routing → pre-code-gate / → first-implementation-edit transition — recurred at a *new* lifecycle sub-point each time, despite prior bootstrap-salience and a completion-time closeout gate:

1. **entry-routing** — landed in the bootstrap layer.
2. **impl-entry** — then recurred at the first-implementation-edit transition; landed in the owner workflow.
3. **design-substance ownership** — design produced by the router + an external/codex review, with no owner stack skill invoked.
4. **impl-mechanics ownership** — the impl-owner skill was **named/known but never invoked**, so its own current mechanical rules (e.g. directory-`AGENTS.md` sync) never fired across a multi-slice loop until the user flagged it.
5. **design-gate ownership** — the visible-UI design-gate owner, named in the coordinator's visible-UI checkpoint clause + the stack owner's body but **never invoked** before a visible-UI slice (even though the impl-mechanics owner WAS invoked), so the page-slice gate never ran until the user asked whether the design skill was used.

The lesson: a repeat at a new sub-point signals the prior firing point was under-specified. **Naming/knowing an owner is not invoking/loading it** — a named-but-unloaded owner's mechanical rules never fire. The durable lever is to move the owning gate's firing point ONTO the transition itself (pre-substance-draft AND pre-first-impl-edit) and sharpen *name→invoke* at the SAME transition, rather than adding a downstream bullet or more prose. And note the honest limit: a completion-time "interim until the map exists" check does not fire if the agent produces+completes the substance without ever building the map — so the closeout gate + user-signal escalation remain the real-world backstops (do not overclaim the moved firing point is mechanical).

## The landed mechanical implementation (owner-invoke case)

For the specific owner-dispatch case, the firing point is now **mechanically enforceable where the plugin hooks + a wired CI gate are present** (not merely prose):

- `owner-dispatch` PreToolUse/Stop hooks (`hooks/owner-dispatch-guard.sh`, `hooks/owner-dispatch-stop.sh`) gate the first product-code edit and session close.
- **Subagent extension** (delegated workers are a separate firing surface — SessionStart routing is NOT inherited by subagents, so a cold worker never sees the gate): `SubagentStart` (`hooks/subagent-start.sh`) injects a slim self-gating routing pointer, and `SubagentStop` reuses `owner-dispatch-stop.sh` (PreToolUse already fires inside subagents) with `agent_id`-scoped, actor-precise markers/cap so the invoke-owner backstop applies one level down for a worker's **path-attributable** gated Edit/Write (Bash-only and missing-baseline cases stay advisory under the session Stop / CI backstop, not SubagentStop). This closes the recurrence where `multi-agent-delegation` had to *manually* inject owners into every worker prompt (`skills/multi-agent-delegation/SKILL.md` Core Rules) and the user reminded when it was forgotten.
- `scripts/owner-dispatch/owner-dispatch.sh ci` is the host-agnostic merge backstop (engine: `scripts/owner-dispatch/owner-dispatch.sh`; rationale + safety posture: `scripts/owner-dispatch/README.md`).

This is the worked example of moving an already-precise recognition-dependent gate ONTO the transition. **Honesty preserved — enforcement is partial, not total:** opt-in per product repo (`.owner-dispatch.json`), default `ask`, fail-open, Claude-hook-hard / Codex-advisory, in-session Bash-write detection is best-effort (the un-bypassable layer is CI, and only when the CI job itself is enforced), and the whole thing is a no-op on the generic Agent-Skills channel. So it raises enforcement where the plugin/hook + CI layers load, but the closeout gate + user-signal escalation remain the backstop everywhere they do not. The opt-in gap itself is now narrowed by a **closeout-acquire check** in `product-rd-workflow` (a gated multi-owner delivery whose repo lacks `.owner-dispatch.json` installs the backstop or records exempt at closeout) — so "silently absent" is caught, though still recognition-dependent at closeout, not a hard gate.

**When a future recognition-dependent gate recurs, prefer building the analogous in-session-hook + CI-backstop pair over adding more prose.**

## Recursive worked example: the gate's own agent-facing guidance must also sit at the seen surface

The same placement principle applies to the *guidance about the gate*, not only the gate. The clarification — *a `deny`/`ask`/`Stop` is the agent's to clear by invoking owners + `record`, **not** a user-authorization prompt (it clears only this gate; merge/push/destructive/scope/product decisions still need the user); and `strict:true` is a maintainer/committed-config decision, not an agent prompt-reduction knob* — originally lived only as `scripts/owner-dispatch/README.md` prose. An agent does not auto-read reference files, so it misread the runtime `ask` prompts as per-edit *user* authorization and pushed the approvals onto the user. Fix: move that one-liner onto the surfaces the agent actually reads at the firing moment — the `deny`/`ask`/`Stop` **message text** and the always-on `agent-context/session-start.md` — keeping the full rationale in the README. Same lesson, one level up: a precise clarification in an unread doc does not fire; place it where it is seen when it matters.

## The self-detect firing point — authority boundary and observed shape (relocated from `SKILL.md`)

When the self-detect firing point fires (your own output names 沉淀 / 提炼 / 复盘 / "distil this into a skill" as a recommended or deferred next action), concretely: invoke the workflow and do the read-only part (charter, RCA, owner map) rather than parking it as a low-priority follow-up; but **shared-skill edits still need the authority you already have** — when the user's request covered only a status review or a narrow fix, record the extraction as `pending` with the owner named and ask, instead of self-authorising a shared-skill change off your own suggestion. Observed shape: the agent proposes "沉淀方法论" as one of several optional next steps, the user answers "是应该沉淀", and only then is the workflow invoked — so recognition was owed one turn earlier, while the edit authority arrived with the user's answer.

### The output-shape sibling — your own deliverable names the owner the entry phrasing did not

The self-detect firing point above triggers on what your output *mentions*; this one triggers on what your output *has become*. Entry phrasing and deliverable shape diverge routinely — the request reads as a narrow how-to ("how do I configure X"), and the answer grows into candidate comparison, rejection rationale, and a recommendation. At that point the deliverable is a selection/assessment artifact regardless of how the request was worded, and the owner that governs it never entered.

Walk these three shapes against your own draft — holding them as one conjunction is what fails, so check them one at a time. Any single hit means the deliverable is a selection/assessment artifact regardless of how the request was worded:

Throughout, **candidate** means a component, service, product, library, vendor, or replacement that is actually up for selection — never a configuration value, parameter, or technique when nothing is being selected. Comparing fixed delay with exponential backoff inside a how-to is not a candidate comparison.

- Named candidates compared side by side.
- An adopt / reject / replace verdict on a named candidate — "just use X" counts, with or without a comparison.
- As-is evidence gathered across several artifacts to support such a verdict.

- **On any hit, re-judge the entry owner before writing further** — you must not keep writing under the initial narrow classification, because the gates that would have constrained the work (research routing before a selection verdict, named-source-plus-freshness discipline on as-is claims) hang off that owner; with no owner in play, none of them fire, and the output looks complete while resting on unexamined evidence.

A fourth trigger on recommendation *wording* was tried and removed: it kept firing on ordinary how-to advice that prefers one configuration value or technique over another ("enable jitter", "prefer exponential backoff over fixed delay") while adding no coverage, because recommending a named candidate is already an adopt verdict. The three that remain key on the deliverable's SHAPE, which is what this section is about; a wording-keyed trigger drifts back toward matching phrases.

Observed shape: an entry judged as configuration how-to produced several rounds of candidate comparison and a recommendation; the current-state evidence discipline and the research-routing rule both stayed dormant for the whole stretch, surfacing only when the user challenged what the conclusion rested on. Same honesty bound as the rest of this section — this is recognition-dependent and must not be overclaimed as a mechanical gate; what is self-checkable is the shape of your own output, not the intent behind the request.

## The record-field corollary — expansion (the forgery surface, relocated from `SKILL.md`)

When you land an owner gate as a *field in a record* — a checklist row, a boundary-record line, a CLI flag taking owner names, a "decision:" slot — that field is fillable without invoking the owner, and filling it is what *feels* like discharging the gate, so the record reads complete while none of the owner's mechanical rules fired. Any field naming an owner therefore carries an explicit invoke bar on its triggered values, and the coverage question is a **set-diff over every owner-naming field in that record**, not a fix for the one owner that just failed (the recurrence shape: a record whose salient fields carry the bar while its siblings silently do not). Prefer a firing point the controller cannot route around: when the gated action produces no local artifact — delegation dispatch being the worked case, where substance is produced by a worker and the controller edits nothing — every edit-triggered and dirty-tree-triggered backstop stays silent, so the gate must hang on the action itself (`hooks/guard-delegation-owner.sh` asks once per session at dispatch when the delegation owner was never invoked).

### The IMPOSSIBLE-invocation value (a bar with no legal third value forges itself)

An invoke bar — or a mandatory-read/mandatory-load gate ("read `X.md` before answering") — **that names no legal value for the case where the invocation is IMPOSSIBLE (no file tool in this session, artifact absent, load fails) forges itself.** Such gates are usually written as a pair: skipping the read is forbidden AND answering from memory is *also* a violation. When the read is unavailable, every action the agent can take is a violation, so the cheapest exit is to assert the gate was satisfied — and if the gate's evidence is a fixed attestation string, that string is emitted by an agent that read nothing and the record reads compliant to every downstream consumer.

So every such gate defines a **third legal value — an unavailable form textually distinct from the satisfied form** (`依据: 不可得(<reason>)` vs the satisfied `依据: <path>`). Two placement rules make it real:

- The unavailable value must sit on a surface still reachable when the artifact is not — the `SKILL.md` or always-on layer; a branch written only into the file you cannot read never fires.
- The gap that value records is the risk owner's to close: the agent must not self-accept it, and the requesting party must not either — a requester who can self-accept can trigger or claim a read failure and bypass the gate entirely.

Honest scope, from the eval that landed this (2 arms x 5 fixtures x 6 samples in a genuinely tool-restricted environment, oracle canary-validated): adding the third value moved the **record form** (legal unavailable record 0/30 -> 29/30; ad-hoc refuse-and-leave-blank 18/30 -> 0/30), and did **not** demonstrate a drop in fabrication — the motivating "agent claims it read the file" did not reproduce at all (0/30 in the unpatched arm, where an always-on no-evidence-no-completion-claim layer was present). Claim the auditability gain, not a forgery-prevention gain; if a true 10% fabrication rate is suspected, 0/30 is only ~4% likely under it, so the premise is weakened for that configuration, not refuted for every host.


## The tool-skill-masks-deliverable-owner variant — a loaded platform/tool skill is not the deliverable owner

Observed shape: a session produces a reader-facing deliverable end-to-end through a platform/tool skill pack (a collaborative-doc platform, spreadsheet, or browser pack), and the loaded tool skill supplies enough "already being guided" feeling that nobody ever asks which skill owns the DELIVERABLE's quality bar — so the finalization owner's gates (doc charter, completeness audit, closeout sweep, structural-reference re-resolution) stay dormant for the whole effort, surfacing only when the user asks "did you run the doc-optimization skill". This is the behavioral twin of the digest-masks-corpus trap: the tool layer's presence masks the owner layer's absence.

Firing point: **producing or first-publishing a reader-facing deliverable is an owner-check transition** — before the first publish to a collaborative or reader-visible surface, answer "which skill owns this deliverable's quality bar" as a separate question from "which tool writes it"; a tool-skill invocation never discharges that check, and a deliverable with no matching owner routes to the finalization skill's Draft mode rather than proceeding ownerless. Mechanical anchors: the no-owner-deliverable triggers on the finalization skill's routing surface (`tighten-doc` description), and this workflow's closeout gate when the session later lands skill changes. Honesty bound as elsewhere in this section: between those anchors the check is recognition-dependent — do not overclaim it as a mechanical gate.

## gap-list 形态为什么最易滑过

自检触发点列举的是「沉淀 / 提炼 / 复盘 / distil」这类**自述措辞**。但一轮提炼最常见的第一个产出不是这些词，而是**一张缺口清单**——「外部源有 X、Y、Z，我们没有」。它读起来像在**答一个覆盖问题**，不像在提炼，所以 charter-before-findings 那条规则从不觉得被触发。

但按该规则自己的定义，**针对外部源的缺口清单就是它所说的 findings 回合**：一旦产出，charter 就只能事后补写。

观测实例：一轮里先产出四条「外部有我们没有」的缺口，之后才 invoke 提炼工作流；改前的触发词表逐字检索该轮实际措辞得零命中。
