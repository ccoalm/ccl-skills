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
| inverse | the same six sites without the needle | 0/100 each | 0/100 each |
| control | four retry checks on one-line JSON | 0/100 each | 0/100 each |
| control | three identity checks on a `tr`-joined reference | 0/100 each | 0/100 each |

The old and new trees differ at these functions and checks only in the changed lines, so the wrong runs come from the pipe form. A first draft of the probe left `$script` unset in the `assert_hit` cases, which made them wrong on both trees for that reason alone. The cases now require the stub output to reach the assertion, and the table above is from the corrected probe.

## Suites and local lanes

On `4bd8435`, environment: test venv with `requirements-test.txt`, `umask 022` and `chmod go+rX` on tracked files, `CCL_BROAD_TEST_REASON=repo-required`, the private alias audit configured.

- Run directly: `lang-basics-ast-check.test.sh` and `client-terminal-ansi-check.test.sh` passed=12 failed=0 each; `mutation_probe.sh` `mutation_probe_ok`; `test_uiux_delivery_contract.sh` `uiux_delivery_contract_ok`.
- `make test-regressions-fast`, `make test-code-review-1`, `make test-code-review-2`, `test_check_ccl_regressions.sh --heavy-only`: exit 0.
- `make test-code-review-abort-leak-1` and `-2` under `unshare --user --map-current-user --pid --fork --mount-proc` (this host's session ancestry includes a child subreaper): exit 0.
- `make test-repo-gates`: `ccl_skill_check_clean_ok` and `shared_git_surface_gate_ok`, then failed `check-agent-contract-coverage.sh` because this evidence directory holds a script and had no `AGENTS.md`. Fixed by adding one; results on the next commit are below.
