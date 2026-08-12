# Review Rubric — Counterexample-Oriented

Phase 1 material (design source: `docs/skill-extraction-optimization-design.md`). This rubric structures the **review pass** of the dual-track gate so it hunts for counterexamples instead of agreeing. It does not replace `references/dual-track-review-gate.md` — that reference still owns the run-BOTH-tracks requirement, convergence standard, and lens-independence rules. This rubric is the question set the review pass works through; the challenge pass stays adversarial per its own runbook.

The failure this prevents: an LLM reviewer that answers "looks reasonable, no problems" — confident agreement that misses over-firing, under-firing, leakage, and authority overreach. LLM-as-judge has known position / verbosity / self-enhancement biases, so a clean review is one evidence class, not a verdict.

## Rubric — every L1 / L2 review answers all of these

| Dimension | Required question |
|---|---|
| Provenance | Can every rule trace back to evidence? |
| Generalization | Is it generalized from the specific case into a reusable capability, not copied? |
| Boundary | Are applies / does-not-apply written explicitly? |
| Routing | Could it mis-fire or steal another owner's task? |
| Cognitive load | Could a reference, example, or eval carry this instead of the entrance? |
| Privacy / R0 | Any business noun, internal host, private path, person, or source-shaped example? |
| Behavior | Which observable agent behavior does it change? |
| False positive | Which scenarios would over-fire? |
| False negative | Which scenarios would it miss? |
| Regression | Is there a should-trigger / should-not-trigger case? |
| User authority | Does it decide on the user's behalf where it should ask? |
| Rule budget | Could this avoid adding a new hard rule? |

## Reviewer prompt direction — find counterexamples, do not affirm

Do NOT ask "is this change reasonable?". Require the reviewer to produce concrete failing scenarios:

```text
Find the scenarios where this skill change would mis-fire, under-fire, bloat the rule
set, fail sanitization, collide with another owner's boundary, override user sovereignty,
become un-verifiable in behavior, or duplicate/contradict an existing skill.
```

A review that returns no counterexamples must say *why each rubric row is clear*, not just "no issues found". An empty finding list with no per-row reasoning is inconclusive, not a pass.

## The rubric is necessary, not sufficient

- For an L1 change, the rubric review plus the recorded challenge row and behavioral-evidence row close the gate.
- For an L2 change, a clean review is explicitly NOT enough on its own: automatic R0 (`references/r0-leakage-audit.md`), deterministic checks (`check-ccl-skills.sh`, `git diff --check`, the routing analyzer where applicable), and behavioral regression (≥1 should-trigger + ≥1 should-not-trigger) must also pass.
- Treat any LLM reviewer output — supporting or critical — as hypothesis-grade: a "looks correct" does not raise the draft's evidence grade, and a finding stays valid until specifically verified or refuted (see the Core Rules on LLM-consultation evidence).
