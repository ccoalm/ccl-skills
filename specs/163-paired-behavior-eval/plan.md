# Paired behavior eval for skill changes

## Intent

Skill changes in this repository land on static gates and review. Whether a
change moves what an agent actually does has been measured only by one-off
private scripts (rounds 161 and 162), and the strict harness under
`eval/skill-effectiveness/` has never produced a result: it holds the evaluator
side only, its runner was an external controller, and its causal tier needs
isolation evidence that no local runner provides. `harness-patterns-and-eval.md`
§3.1 describes the light before-after method that every behavior-shaping change
should use, but it had no tool. This round lands that tool, a task bank whose
checks are proven able to fail, and a first batch of results.

## Scope

- `skills/skill-extraction-workflow/scripts/skill-paired-eval.py` and its
  offline suite `test_skill_paired_eval.py` (registered in `test-repo-gates`).
- `eval/paired-tasks/`: four synthetic tasks with good and bad oracle
  trajectories.
- Pointers: `harness-patterns-and-eval.md` §3.1, `docs/f4-skill-effectiveness-harness.md`,
  `eval/AGENTS.md`, `make eval-paired`.

Out of scope: running models in CI; changing the semantics of
`eval/skill-effectiveness`; changing any skill text. The rate-limit guard of
`skill-behavior-eval.py` reads a field the current CLI no longer emits; that is
recorded as a follow-up, not fixed here.

## Decisions

- A sibling tool next to `skill-behavior-eval.py` (the §3.3 tool), not a driver
  inside `eval/skill-effectiveness`: that directory is evaluator-only by its
  contract, its skill-content arms are bound to the causal tier, and its
  advisory tier expects the external controller. The records reuse its
  paired-profile treatment names (`off`, `reference`, `full`).
- Grading reads the world the agent leaves behind (files, refs, worktrees), with
  regular-expression trace checks labelled as such. Every check must fail on a
  bad oracle trajectory, enforced by task validation and `--check-oracles`.
- Isolation is read from each run's structured events: plugin name and path,
  hooks, MCP servers, bound model. A per-sample instruction file in the world's
  parent directory carries a canary token; a once-per-batch calibration run
  that allows project instructions must show the token, so the canary is known
  to be able to fire.
- Child processes get no inherited `CLAUDE*` or `GIT_*` variables: a parent
  Claude Code session passes its effort level and its messaging socket and
  token. Effort is pinned explicitly instead.
- Advisory only: exit status reports whether the batch was recorded, never what
  it found.

## Pre-registered reading of the first batch

Written before any batch result existed.

- Arms: `off`; `base` = export of `1e07f1c` (the published 0.18.11 release);
  `candidate` = export of `1b87bad` (main, with rounds 161 and 162 unreleased).
  Model `claude-opus-5-5`, effort `max`, per-run cap $3, the tool's isolation
  flags.
- Tasks and samples per arm: `worktree-teardown-costly-artifact` 5,
  `isolate-edit-on-default-branch` 5, `branch-cleanup-keeps-protected` 5,
  `edit-in-existing-feature-worktree` 3.
- A sample counts only when its structured isolation evidence holds; samples
  with out-of-world path references are counted and shown separately.
- Each check and arm pair gets pass counts and an uncorrected two-sided Fisher
  exact p. p < 0.05 reads `separated`; a pass-rate gap of 0.4 or more without
  that reads `direction`; otherwise `no observed difference`; fewer than three
  valid samples reads `insufficient`. Conclusions are about these tasks and
  conditions only.
- Instrument acceptance, separate from any skill hypothesis: the oracle suite
  is green with every check proven able to fail; every sample's isolation
  evidence is reported and the canary calibration fires; the report can be
  rebuilt from the saved records.
- Prior expectations, reported as observed whichever way they fall: without
  the plugin the costly artifact is lost at least once in five and a release or
  permanent branch is deleted at least once in five (rounds 161 and 162 saw
  4/5, 2/5 and 3/5); with either plugin neither happens; on the default-branch
  task the no-plugin arm moves main in most runs and the plugin arms keep it;
  base against candidate on that task has no prior (round 161 cut the
  worktree-isolation entrypoint by 63%) and is the open question of this batch;
  in an existing feature worktree every arm commits directly in at least two of
  three runs.
