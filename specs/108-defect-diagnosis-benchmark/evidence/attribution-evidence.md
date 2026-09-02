# Round 108 — attribution and gate evidence

Bounded evidence for the claims the review plan makes. Every excerpt below was read from the named public page on 2026-09-02; excerpts are kept to the sentence that supports the landed rule. Command outputs are the terminal verdict tokens of each deterministic gate run on the candidate tree (the tree of the commit this file lands in, minus this file); CI re-runs the same gates on the pushed commit, which is the authoritative result.

## Primary-source excerpts

- Google SRE Book, ch. 12 *Effective Troubleshooting* — `https://sre.google/sre-book/effective-troubleshooting/`
  - Model: "we can think of the troubleshooting process as an application of the hypothetico-deductive method".
  - Pitfalls: "Coming up with wildly improbable theories about what's wrong, or latching on to causes of past problems"; "Hunting down spurious correlations that are actually coincidences".
  - Simplify and reduce: "Injecting known test data in order to check that the resulting output is expected (a form of black-box testing) at each step can be especially effective"; "bisection, splits the system in half and examines the communication paths between components".
  - Test ordering: "Consider the obvious first: perform the tests in decreasing order of likelihood, considering possible risks to the system from the test."
  - Side effects: "Active tests may have side effects that change future test results."
  - Suggestive evidence: "Some tests may not be definitive, only suggestive. It can be very difficult to make race conditions or deadlocks happen in a timely and reproducible manner".
  - Notes: "Take clear notes of what ideas you had, which tests you ran, and the results you saw."
- The Debugging Book, *Introduction to Debugging* — `https://www.debuggingbook.org/html/Intro_Debugging.html`
  - Scientific method: "formulate a prediction that can support or refute the hypothesis. Ideally, the prediction would distinguish the hypothesis from likely alternatives."
  - Fix gate: "you should start to fix your code if and only if you have a diagnosis that shows two things: Causality … Incorrectness".
  - Log: "Keep a Log … Writing these things down explicitly allow you to keep track of all your observations and hypotheses over time."
  - Fault propagation: "we find out which faults in the earlier state have caused the later faults … until we find a transition from a correct state to a faulty state".
- The Debugging Book, *Reducing Failure-Inducing Inputs* — `https://www.debuggingbook.org/html/DeltaDebugger.html`
  - "Delta Debugging implements the 'binary search' strategy … If neither half fails … it keeps on cutting away smaller and smaller chunks from the input".
- The Debugging Book, *Statistical Debugging* — `https://www.debuggingbook.org/html/StatisticalDebugger.html`
  - Section headings read: "Ranking Lines by Suspiciousness", "The Tarantula Metric", "The Ochiai Metric" (heading-level verification only; no sentence is quoted in landed text).
- `git bisect` documentation — `https://git-scm.com/docs/git-bisect`
  - "You can further cut down the number of trials, if you know what part of the tree is involved in the problem you are tracking down, by specifying pathspec parameters when issuing the bisect start command".
  - "If you know beforehand more than one good commit, you can narrow the bisect space down by specifying all of the good commits immediately after the bad commit".
  - Sections "Bisect log and bisect replay", "--first-parent", and the `bisect run` exit-code contract ("exit with code 0 if the current source code is good/old, and exit with a code between 1 and 127 (inclusive), except 125, if the current source code is bad/new").
- *What we can learn from how programmers debug their code* — `https://arxiv.org/abs/2103.12447` (2021)
  - "Locating a bug is more difficult than reproducing and fixing it."; "Memory and concurrency bugs do not occur as frequently (6.9 % and 8.8 %), but they consume more debugging time."
- Agentless — `https://arxiv.org/abs/2407.01489` (Xia, Deng, Dunn, Zhang, 2024)
  - "Agentless employs a simplistic three-phase process of localization, repair, and patch validation".
- Microsoft Research, debug-gym — `https://www.microsoft.com/en-us/research/blog/debug-gym-an-environment-for-ai-coding-tools-to-learn-how-to-debug-code-like-programmers/` (2025)
  - "In most existing approaches … an agent rewrites its code conditioned on" the error; tools "enabling setting breakpoints, navigating code, printing variable values"; "Even with debugging tools, our simple prompt-based agent rarely solves more than half of the SWE-bench Lite issues. We believe this is due to the scarcity of data representing sequential decision-making behavior".
- Not attributed: Agans, *Debugging* — the author's site is a landing page and the book text was not read; no landed rule names it.
- Installed process pack cited in three register rows as the second, independent source — `superpowers` plugin v6.3.0, skill `systematic-debugging` (installed at the Claude plugin cache path `claude-plugins-official/superpowers/6.3.0/skills/systematic-debugging/`, read 2026-09-02):
  - Boundary walk: `SKILL.md` Phase 1 step 4 "Gather Evidence in Multi-Component Systems … For EACH component boundary: Log what data enters component / Log what data exits component / Verify environment/config propagation … Run once to gather evidence showing WHERE it breaks".
  - Suite polluter search: the package ships `find-polluter.sh` (listed under Supporting Techniques in the same directory).
  - Backward trace: `root-cause-tracing.md` ("Trace bugs backward through call stack to find original trigger"); `SKILL.md` Phase 1 step 5 "Where does bad value originate? … Keep tracing up until you find the source. Fix at source, not at symptom".
  - This pack is reference-only for the shared tree: nothing was copied from it; it corroborates the primary sources above.

## Deterministic gate results on the candidate tree

- `git diff --check` → clean (no output, exit 0).
- `python3 scripts/check-public-sanitization.py .` → `public_sanitization_ok`.
- `CCL_SKILL_BASE_REF=origin/dev bash skills/skill-extraction-workflow/scripts/check-ccl-skills.sh .` → `r0_status=private-ok`, `register_firing_path_resolution_ok`, `entrypoint_word_budget_blocking_ok`, `reference_line_budget_blocking_ok`, `ccl_skill_check_ok`, `ccl_skill_check_clean_ok` (exit 0).
- Recurring anti-pattern grep panel over `skills/defect-diagnosis/SKILL.md` and `references/diagnosis-playbook.md` → 0 hits.
- `python3 skills/skill-extraction-workflow/scripts/shared_git_surface_gate.py --repo . --base-ref origin/dev` → `shared_git_surface_gate_ok`.
- Word budget (gate token pattern, `check-size-budget.sh`): base body words 4416 → head see the size line in the same check output; blocking verdict `entrypoint_word_budget_blocking_ok`.
- Immovable anchors still resolve at head (`grep -c` in `skills/defect-diagnosis/SKILL.md`, each = 1): `never silently take the first row of N`; `the observation that would falsify it`; `must not be filed under a sibling stack's architecture skill`.
