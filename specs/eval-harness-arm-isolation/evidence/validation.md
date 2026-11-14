# Validation

Host: Linux, Claude Code 2.1.322, Python 3.12, Ruby 3.1. Live probes used `claude-haiku-5-5`; tool availability and permissions are decided by the CLI, not the model. Raw probe streams stay in the session scratch area; this file records results only.

## Reproduction on the base code (RED)

Probes drive the exact argv that the base `run_agent` builds, from an empty directory.

| Probe | Result on base argv |
| --- | --- |
| Ask for Bash `echo > file` and a Write | both ran; two files created |
| Glob/Read a canary outside the working directory and the fixture file | both read (host has unscoped `Read`/`Glob` allow rules) |
| Same read, user settings excluded, `dontAsk`, with and without `--add-dir` | denied: the reads above come from host rules, not from the working directory |
| Saved answer under `behavior-eval-out/` in the working directory, user settings excluded, `dontAsk` | read |
| Write and read in the parent session's scratch directory, user settings excluded, `dontAsk`, inherited vs stripped `CLAUDE*` variables | denied in both: defect 2 does not reproduce |
| `--tools` alone in place of `--allowedTools` | Bash and Write not offered; the context-mode plugin's MCP shell tool created a file |
| `--tools` + `--strict-mcp-config` | init lists only Glob/Grep/Read/Skill, no MCP tool; nothing created; plugin skills still load |

## Regression tests

`test_eval_runtime.py` with the new cases, run against the base scripts in a detached worktree of the base commit: 17 failed, 19 passed. The failures are exactly the new assertions (argv, fresh directory, init-event boundary for both tools, judge tools, sample signature); every pre-existing case, with an init event added to its stream, passes on base.

On the fix: 24 passed, 68 subtests passed.

Applied mutations on the fix, each run against the full file. The first eight ran before the signature test existed (unmutated control then: 23 passed); the last ran with all fixed scripts in place (control: 24 passed).

| Mutation | Failing assertions |
| --- | --- |
| Python: drop `--strict-mcp-config` | arms (both), judge |
| Python: `--allowedTools` instead of `--tools` | arms (both) |
| Python: ignore a widened init tool list | init cases `bash_offered`, `mcp_offered`, `second_init_widened` |
| Python: accept a missing init event | init cases `no_init`, `tools_not_a_list` |
| Python: start the agent in the caller's directory | fresh-directory test |
| Ruby: drop `--strict-mcp-config` | replay argv test |
| Ruby: ignore a widened init tool list | golden `bash_offered`, `mcp_offered` |
| Ruby: accept a missing init event | golden `no_boundary` |
| Python: drop the launch-boundary version from the sample signature | stale-sample test |
| Python: temporary directory not removed | fresh-directory test |
| Python: temporary directory seeded with a file | fresh-directory test |
| Python: one shared directory for every run | fresh-directory test |

## Live check on the fix (GREEN)

The fixed `run_agent` (only `--model` appended) for both arms, run from a caller directory holding `behavior-eval-out/F1.candidate.s1.txt` with a fresh canary:

| Arm | Probe | Result |
| --- | --- | --- |
| current | Bash, Write, any MCP shell tool | `err: null` (boundary verified from init); the agent reports Bash and Write unavailable and no MCP tool; fresh directory empty and removed; caller directory unchanged |
| candidate | same | same |
| current | Glob `**/*.txt` in the working directory and read | finds nothing; canary absent from the answer |
| candidate | same | same |

Judge argv with `--tools ""` + `--strict-mcp-config`: init `tools: []`; an attempted Bash call created nothing.

## Repository checks

`make test-repo-gates` on the first candidate failed in `skills/testing-strategy/scripts/lang-basics-go-check.test.sh`, a suite this change does not touch: the case's output contained the expected text, yet it was marked FAIL. Cause: its assertion piped `printf` into `grep -qF` under `pipefail`; `grep -q` exits on the first match and the writer can take SIGPIPE, so the pipeline reports 141. Measured: 1 failure in 10 suite runs on this host under load; with a 20,000-line output after the match, the pipe form failed 199/200 and a here-string 0/200 on the same input. The assertion now reads from a here-string; 15/15 suite runs pass. Thirteen other suites contain similar pipe-into-`grep -q` checks; they did not fail here and are left as a follow-up.

`check-ccl-skills.sh` with the private alias audit: `r0_status=private-ok`, `eval_routing_ok`, `ccl_skill_check_clean_ok`.

## Review pass R1

- Candidate: `3f33fce` (rebased onto `b1b8509`). Reviewer: codex via `extraction_review_gate.sh --mode review --stage build`, result `review-R1.json` (status `findings`, three P2).
- F1 (`skill-behavior-eval.py`): the boundary check ran before terminal-result validation, so a failed run with a missing or widened init reported a boundary error instead of its own. Fixed: the check now runs last, only on an otherwise valid answer (the Ruby replay already did this). Test `test_failed_run_keeps_its_own_error_whatever_its_boundary` (four failure kinds × three init shapes). Applied mutation moving the check back before validation: 6 subtests fail.
- F2 (`test_eval_runtime.py`): the fresh-directory test mocked the launcher, so dropping `cwd=cwd` from `Popen` would stay green. Fixed: `test_launched_agent_process_runs_in_the_fresh_directory` runs both arms through `run_agent` with a stub `claude` that reports its own `os.getcwd()` and directory listing. Applied mutation removing `cwd=cwd` from `Popen`: that test fails, nothing else.
- F3 (this file): lanes beyond `test-repo-gates` were not recorded. Disposition: run `make test`'s other lanes, `regression-heavy` and the public-sanitization check on the final candidate; results below.
- After the fixes: 26 passed, 80 subtests; unmutated control green.
