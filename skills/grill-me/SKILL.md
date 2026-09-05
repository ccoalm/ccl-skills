---
name: grill-me
description: grill-me / 访谈 / 一问一答拷问（一次问一个）/ 压力测试方案 / stress-test a plan — lightweight one-question-at-a-time interview to challenge a plan, design, API shape, data model, or feature direction before implementation. Skip 拷问用的问题池·推荐默认值等材料，以及拷问后的结论整理（不是逐问过程）→ requirement-intent；code-level YAGNI/delete/adversarial review of written code → `product-rd-workflow`'s independent-review gate; full delivery/spec/plan authoring → product-rd-workflow; tests → testing-strategy; implementation → stack/dev skill; process lesson extraction → skill-extraction-workflow.
---

# grill-me — 轻量方案拷问

Use this when the user explicitly asks to grill, interview, challenge, or stress-test a plan before implementation.

This is a narrow pre-implementation interview. It clarifies the next blocking decision; it does not write the plan, own delivery gates, or replace the relevant owner workflow.

## When to use

Use for explicit requests such as:

- `grill-me` / `grill me`;
- 访谈、拷问、追问一个方案；
- 压力测试方案、设计、API shape、数据模型、权限模型、工作流；
- before implementation, when several product or technical decisions depend on each other.

Do not auto-trigger this from generic “帮我规划 / scope 一下 / 写个方案”. Those route to the owning workflow first, usually `product-rd-workflow`.

## Owner boundaries

- Full requirement shaping, spec, plan, lifecycle gates, or multi-step delivery → `product-rd-workflow`.
- Risk tags, gate selection, rollout or review requirements → `feature-risk-router`.
- Code-level YAGNI, delete-code, overengineering, or adversarial review of already-written code → `product-rd-workflow`'s independent-review gate (no dedicated CCL delete-code/YAGNI skill; the review gate owns it).
- Test layers, fixtures, coverage, regression, CI gate design → `testing-strategy`.
- Bug/root-cause diagnosis → `defect-diagnosis`.
- Implementation → the relevant stack/dev skill or bounded executor.
- Reusable process/skill lesson extraction → `skill-extraction-workflow`.

`grill-me` may feed those owners by resolving one unclear decision first. It must hand back once the user asks for a deliverable artifact, implementation, formal review, or test plan.

## Core contract

Ask one blocking question at a time.

Each turn must include:

1. `Target`: the plan/design being challenged.
2. `Current assumption`: the most important assumption currently visible.
3. `Question N`: exactly one unresolved decision.
4. `Recommended answer`: a concrete default.
5. `Why`: short rationale and the risk if the answer is wrong.

Then wait for the user's answer before asking the next dependent question.

If the answer depends on existing repo facts, inspect the relevant files first. Do not ask the user to restate facts that are available in code, specs, runbooks, or local docs.

## Workflow

1. Frame the target. If the target is ambiguous, ask one clarifying question only.
2. Identify the next decision that blocks meaningful progress.
3. Ask exactly one question with the recommended answer and why.
4. After the answer, update the assumption and choose the next dependent question.
5. Stop when the direction is clear enough to route to the next owner or when the user rejects the premise.

Avoid bundled questions. Avoid long lectures. Do not produce a full PRD, architecture doc, implementation plan, or code unless the user explicitly switches workflows.

## Closeout

When the interview reaches a stable stop, return:

```text
Resolved direction
- <decision>: <answer>

Remaining risks
- <risk or unknown>

Recommended next step
- <owner workflow / implementation / no-op>
```

## Tone

- Direct, skeptical, and practical.
- Push back on weak assumptions with evidence.
- No flattery.
