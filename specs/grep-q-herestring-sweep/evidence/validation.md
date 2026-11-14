# Validation

Host: Linux 6.1, bash 5.2.15, GNU grep 3.8 (`/usr/bin/grep`, which the suites run), default 64 KiB pipe buffer.

## Write counts and input shapes

- bash's `printf '%s'` into a pipe, counted from `/proc/<pid>/io` `syscw` around the builtin: 1 write for 100, 285, 1177, 4000 and 4096 bytes; 2 writes for 4097, 8193, 20000 and 70000 bytes; 1 write for 8192 bytes.
- Instrumented full runs of the code-review suites, logging every captured `out` that a `grep -q` check reads: `test_opencode_review_retry.sh` 440 to 893 bytes, `test_review_gate.sh` 275 to 6186 bytes, 0 newlines in every case. Both runs passed (103 and 310 checks).
- Checker outputs in the testing-strategy suites: `lang-basics-ast-check` 110 to 1177 bytes, up to 11 lines; `client-terminal-ansi-check` 163 to 266 bytes, up to 3 lines; `lang-basics-go-check` 144 to 285 bytes, up to 2 lines.
- `check-contract-anchors.sh` stdout on this tree: 37 bytes, one line.

## Paired probe

`bash specs/grep-q-herestring-sweep/evidence/pipe-probe.sh <tree> 100`. Old tree: `git archive ffd974b skills`. New tree: the candidate.

| Group | Case | Old tree | New tree |
| --- | --- | --- | --- |
| changed | `lang-basics-ast-check.test.sh`: assert_hit finds a match | 100/100 wrong | 0/100 |
| changed | `client-terminal-ansi-check.test.sh`: assert_hit finds a match | 100/100 wrong | 0/100 |
| changed | `mutation_probe.sh`: a red mutant counts as covered | 100/100 wrong | 0/100 |
| changed | `test_opencode_review_retry.sh`: 3000 symlinks are found | 100/100 wrong | 0/100 |
| changed | `test_review_gate.sh`: a live group keeps its record | 100/100 wrong | 0/100 |
| changed | `test_uiux_delivery_contract.sh`: a claim on line 1 is found | 100/100 wrong | 0/100 |
| changed | `test_concern_excerpt.sh`: excerpt wiring found in nine long lines | 100/100 wrong | 0/100 |
| inverse | the same seven sites without the needle | 0/100 each | 0/100 each |
| writer-fails | `test_review_gate.sh`: a group `ps` listed before failing keeps its record | 100/100 wrong | 0/100 |
| writer-fails | `test_opencode_review_retry.sh`: a link `find` printed before failing is caught | 100/100 wrong | 0/100 |
| writer-fails | `test_uiux_delivery_contract.sh`: a claim `active_text` printed before failing is found | 100/100 wrong | 0/100 |
| control | four retry checks on one-line JSON | 0/100 each | 0/100 each |
| control | three identity checks on a `tr`-joined reference | 0/100 each | 0/100 each |

The old and new trees differ at these functions and checks only in the changed lines, so the wrong runs come from the pipe form. The writer-fails rows were added after review R1 (below); on the old tree they are wrong because the old pipe also failed on the writer's status. A first draft of the probe left `$script` unset in the `assert_hit` cases, which made them wrong on both trees for that reason alone. The cases now require the stub output to reach the assertion, and the table above is from the corrected probe.

## Suites and local lanes

On `4bd8435`, environment: test venv with `requirements-test.txt`, `umask 022` and `chmod go+rX` on tracked files, `CCL_BROAD_TEST_REASON=repo-required`, the private alias audit configured.

- Run directly: `lang-basics-ast-check.test.sh` and `client-terminal-ansi-check.test.sh` passed=12 failed=0 each; `mutation_probe.sh` `mutation_probe_ok`; `test_uiux_delivery_contract.sh` `uiux_delivery_contract_ok`.
- `make test-regressions-fast`, `make test-code-review-1`, `make test-code-review-2`, `test_check_ccl_regressions.sh --heavy-only`: exit 0.
- `make test-code-review-abort-leak-1` and `-2` under `unshare --user --map-current-user --pid --fork --mount-proc` (this host's session ancestry includes a child subreaper): exit 0.
- `make test-repo-gates`: `ccl_skill_check_clean_ok` and `shared_git_surface_gate_ok`, then failed `check-agent-contract-coverage.sh` because this evidence directory holds a script and had no `AGENTS.md`. Fixed by adding one.

On `9692c19` (adds the evidence `AGENTS.md` and this file), same environment plus `CCL_SKILL_BASE_REF=origin/main`: `make test-repo-gates` passes (`ccl_skill_check_clean_ok`, `shared_git_surface_gate_ok`); `test_check_public_sanitization.py`, `check-public-sanitization.py`, `check-markdown-links.py`, `check-spec-references.py`, `test_check_skill_count.py` and `check-skill-count.py` exit 0.

## Review pass R1

- Candidate: `9692c19`, base `origin/main` (`ffd974b`). Reviewer: codex via `extraction_review_gate.sh --mode review --stage build`. Result `review-R1.json` (status `findings`, three P2).
- R1-1: when a writer prints the match and then exits non-zero, the new forms decide from the printed text, while the old pipes failed on the writer's status. The plan had said writer failures keep their verdict. Disposition: the plan now tabulates both cases under Change. For the symlink check and the UI/UX scan the new verdict is the right one (the old one was a false green); `prune` keeps the record of a group `ps` listed. The code is kept; three writer-fails probe cases are added (above).
- R1-2: this record ended on the failed repository-gate run. Disposition: the rerun on `9692c19` is recorded above; the final lanes are recorded below.
- R1-3: the packet did not show that the real sites run under `pipefail`, nor how candidates were found. Disposition: the plan's changed-site table now names each file's `pipefail` line and how the check runs in the suite shell, and states the search used. The selected skill texts and the commit message were not added to the packet.

## Challenge pass C1

- Candidate: `9072f6c`, base `origin/main`. Challenger: codex via `extraction_review_gate.sh --mode challenge --stage build`, focus: verdicts the rewrite changes beyond a cut-off writer, unchanged sites that can race, probe cases that stay green with the defect, claims the measurements do not carry. Result `challenge-C1.json` (status `findings`, three P2).
- C1-1: `test_concern_excerpt.sh` was excluded by line count ("at most nine lines"), not by size. On this tree the nine lines are 414 bytes, but lines in `claude_review.sh` run to 913 characters, and the input is a checked-in file's contents, which the plan's own rule sends to "changed". Fixed: the wiring check reads the `grep -A8` output from a here-string; probe case and inverse added (above); register row added for `code-review`. `test_review_gate_abort_leak.sh` now has its own row with a size bound.
- C1-2: final-lane results were not recorded for the submitted candidate. Disposition: recorded under Final local lanes.
- C1-3: the packet omits the selected skill texts and the commit message. No change: the commit messages are on the branch and listed in the pull request.

## Delta pass D1

- Candidate: `c70e1c9`, base `9072f6c` (the challenge candidate), so the packet holds only the C1 fixes. Reviewer: codex via `extraction_review_gate.sh --mode review --base 9072f6c`. Result `delta-D1.json` (status `findings`, three P2, all on the evidence record, none on code).
- D1-1: the final-lane results were not yet recorded. Disposition: recorded below.
- D1-2: the packet omits the selected skill texts and commit messages. No change, as for C1-3.
- D1-3: the abort-leak exclusion stated a threshold, not a bound. Disposition: the plan row now cites `probe_processes` and states that the bound comes from the code, not a measurement.
- This is the last external pass. Later commits change only `plan.md` and evidence records in this directory.

## Final local lanes

On `c70e1c9` (last executable change), same environment as above with `CCL_SKILL_BASE_REF=origin/main`: `make test-repo-gates` (`ccl_skill_check_clean_ok`, `shared_git_surface_gate_ok`), `make test-regressions-fast`, `make test-code-review-1`, `make test-code-review-2`, `test_check_public_sanitization.py`, `check-public-sanitization.py`, `check-markdown-links.py`, `check-spec-references.py`, `test_check_skill_count.py` and `check-skill-count.py` all exit 0. `test_concern_excerpt.sh` prints `concern_excerpt_tests_ok`. The probe on `c70e1c9` prints `pipe_probe_ok`.

Not rerun after `4bd8435`: the heavy regression lane and the two abort-leak legs. The commits since then change only `test_concern_excerpt.sh` (run in `test-code-review-1`), the register, and files under `specs/`.
