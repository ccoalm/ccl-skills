# Primary-source excerpts behind the new instruction-load rows

Each row added to `skills/skill-extraction-workflow/references/external-practice-controls.md`
(Instruction-following mechanisms) is backed by the excerpts below, quoted from
the primary source as retrieved on 2026-10-04 (arXiv abstract pages; arXiv HTML
for section text; the vendor page as published that day).

## AgentIF — [arXiv 2505.16944](https://arxiv.org/abs/2505.16944) (v1)

- Abstract: "(1) Realistic, constructed from 50 real-world agentic applications. (2) Long, averaging 1,723 words with a maximum of 15,630 words. (3) Complex, averaging 11.9 constraints per instruction" and "we collect 707 human-annotated instructions across 50 agentic tasks".
- Section 5: "the best model perfectly follows fewer than 30% of the instructions" and "We find that condition and tool constraints introduce new challenges. We also observe performance degradation as instruction length increases".

## Context Length Alone Hurts LLM Performance Despite Perfect Retrieval — [arXiv 2510.05381](https://arxiv.org/abs/2510.05381)

- Abstract: "Our systematic experiments across 5 open- and closed-source LLMs on math, question answering, and coding tasks reveal that, even when models can perfectly retrieve all relevant information, their performance still degrades substantially (13.9%--85%) as input length increases but remains well within the models' claimed lengths. This failure occurs even when the irrelevant tokens are replaced with minimally distracting whitespace, and, more surprisingly, when they are all masked".
- Abstract: "prompting the model to recite the retrieved evidence before attempting to solve the problem. On RULER, we observe a consistent improvement of GPT-4o up to 4%".

## SkillsBench — [arXiv 2602.12670](https://arxiv.org/abs/2602.12670) and its [HTML](https://arxiv.org/html/2602.12670) (the version served on 2026-10-04)

- Abstract: "Our latest aggregate evaluation runs the 87-task benchmark under matched no-Skills and curated-Skills conditions for 18 model-harness configurations. Curated Skills raise the average pass rate from 33.9% to 50.5% (+16.6 percentage points; 25.5% normalized gain)".
- Table 8 (Skills per task; no Skills / with Skills / delta): 1 Skill, 23 tasks, 32.2% / 50.2% / +18.0; 2–3, 43 tasks, 34.4% / 53.4% / +19.0; ≥4, 21 tasks, 34.8% / 44.9% / +10.1.
- Table 9 (SKILL.md size bucket by 25th/50th/95th percentile): Compact, 22 tasks, +19.0; Standard, 22, +21.5; Detailed, 38, +14.5; Comprehensive, 5, +0.7.
- Section 6: "Comprehensive prose is essentially flat while focused documentation yields larger aggregate lift (+0.7 pp vs. +19.0/+21.5 pp; Appendix F)".
- Appendix F.3: "Pattern A: heavyweight pipeline crowds out simpler execution", "Pattern B: Skill activation displaces a stronger native strategy", "Pattern C: Skill points the agent at a solver it can't debug".
- Appendix D.6: "On all three configurations, self-generated Skills land below the no-Skills baseline (−8.1 to −11.5 pp)".
- Section 6.1: "results may not transfer directly to GUI agents, multi-agent coordination, or very long-horizon workflows".

## SkillJuror — [arXiv 2606.11543](https://arxiv.org/abs/2606.11543)

- Abstract: "In an 82-task SkillsBench study, Progressive Disclosure changes runtime behavior before aggregate outcomes: distinct Skill resources touched per trajectory rise from 1.18 to 3.85, and effective uptake events rise from 1.33 to 3.92. It also yields 17 additional verifier-passing trials out of 410 matched trials (+4.1%) over the normalized flat baseline."
- Abstract: "Progressive Disclosure helps when supporting resources guide implementation, checking, or repair, but is weaker when success hinges on exact output conventions, numerical thresholds, or long artifact-generation pipelines."

## Skill Availability and Presentation Granularity — [arXiv 2605.31408](https://arxiv.org/abs/2605.31408)

- Abstract: "a 30-task domain-balanced subset validated by official oracle runs, two reasoning-enabled model configurations, six skill conditions, and five trials per task-condition-model cell".
- Abstract: "Relative to no skill, skill conditions increase task-mean pass rate by 26.7 to 36.0 percentage points for GPT-5.5 and by 18.0 to 26.0 percentage points for DeepSeek V4-Flash."
- Abstract: "Low-abstraction guidance differs from high-abstraction guidance by +0.7 percentage points for GPT-5.5 and -6.7 percentage points for DeepSeek V4-Flash, with both 95% bootstrap confidence intervals crossing zero. Adding one worked example to medium-abstraction guidance differs from the no-example variant by +0.7 and +1.3 percentage points."

## Anthropic, [Prompting best practices](https://platform.claude.com/docs/en/build-with-claude/prompt-engineering/claude-prompting-best-practices)

- "Claude Opus 4.5 and Claude Opus 4.6 are also more responsive to the system prompt than previous models. If your prompts were designed to reduce undertriggering on tools or skills, these models may now overtrigger. The fix is to dial back any aggressive language. Where you might have said \"CRITICAL: You MUST use this tool when...\", you can use more normal prompting like \"Use this tool when...\"."
