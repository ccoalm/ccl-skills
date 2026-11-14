# Pipe-into-`grep -q` sweep

Several test suites check text by piping it into `grep -q` while `pipefail` is set. `grep -q` exits on its first matching line. If the writer still has data to write, it takes SIGPIPE, and `pipefail` reports the pipeline's status as 141 instead of grep's 0. A positive assertion then reads a match as a miss (a false red). A negated assertion (`! … | grep -q X`) reads a present string as absent (a false green). `lang-basics-go-check.test.sh` was fixed for this in `specs/eval-harness-arm-isolation/`, and that round named the other suites as follow-up. This round goes through them.

## Charter

| Field | Answer |
| --- | --- |
| Purpose | Remove the remaining sites where this race can flip an assertion, so suites in the required local lanes and CI do not fail on a real match, and negated checks do not pass on a real defect. |
| Scope | In: pipe-into-`grep -q` sites in test suites and gate scripts under `skills/`, starting from the 13 suites named in the follow-up and extended to the other suites a wider scan turned up. Out: gate semantics; `packages/ccl-skills-npm/scripts/host-smoke.sh` (see Residual risk); frozen evidence scripts under `specs/` and `eval/evidence/`; other early-exit readers such as `head`; a static check for the class (see Root cause). No watermark applies; this is not an iterative-program source. |
| Depth | Targeted check. Each site is classified, the changed ones are one-line edits, and a paired probe is run against the old and new trees. No skill text changes. |
| Result classification | Failure. The class has failed in practice in other suites and gates (`specs/regression-suite-flakes/`, `specs/obligation-ledger-pipe-race/`, `specs/liveness-gate-pipe-race/`). The sites changed here were not seen failing; the probe shows each one giving the wrong verdict on input it can receive. |
| Matching analysis | Per site: is `pipefail` in effect, does the input have lines after the matching one, and can the writer emit more than one write? Measured how many writes bash's `printf` makes (below). Paired probe on the old and new trees, with inverse cases that must keep their opposite verdict. |
| Failure mode | A weak sweep would change every hit from a text search, including sites that cannot race, or would rerun suites until green. The first adds churn and review cost without removing a failure. The second hides the class. |
| Lifecycle impact | Testing and CI only. No assertion's accept or reject set changes; only the false outcomes go away. Product intent, design, implementation, release and onboarding are unaffected. |
| Evidence plan | The prior round's record and register row; each candidate site in context; the shell options in force at each site; measured output sizes and line counts from instrumented runs of the code-review suites; a write-count measurement of bash's `printf`; the paired probe `evidence/pipe-probe.sh`. |
| Completion standard | The probe gives wrong verdicts on the old tree and none on the new tree for every changed site; inverse and control cases have no wrong verdicts on either tree; the changed suites pass; local lanes pass on the exact candidate; extraction review and challenge run, plus a delta pass for any later change. |

## When the race can happen

Three conditions must all hold:

1. `pipefail` is in effect where the pipeline runs. Without it the pipeline reports grep's status, and the writer's SIGPIPE does not matter.
2. The input has text after the matching line. `grep` matches whole lines, so with a single line (compact JSON, or text joined by `tr '\n' ' '`) it reads to the end of the input before it can match.
3. The writer issues more than one `write()`. If the whole output goes out in one write, it is in the pipe before `grep` can see it, and no later write remains to fail.

Measured on this host (bash 5.2.15; counted from `/proc/<pid>/io` `syscw` around the builtin): `printf '%s'` into a pipe makes one write for up to 4096 bytes and two above that, unless the size is a multiple of 4096. External writers (`tr`, `ps`, `find`, `cut`) also buffer and write in chunks. A site is changed when its writer's output is not kept under 4096 bytes by the suite's own construction: it carries the tested program's output, a file's contents, the process table, or a directory listing. A site is left alone when its input is a constant message, one source line, or a one-line token.

This measurement does not support the earlier record's "1 failure in 10 suite runs" attribution for `lang-basics-go-check.test.sh`. That suite's outputs measure 144 to 285 bytes, one write each, so SIGPIPE cannot hit them. The large-output control in that record (20,000 lines, pipe 199/200 wrong, here-string 0/200) still holds. The earlier one-in-ten red had some other cause, which this round did not investigate.

## Site classification

Changed:

| File | Site | `pipefail` source | Writer and input | Wrong verdict with the pipe |
| --- | --- | --- | --- | --- |
| `testing-strategy/scripts/lang-basics-ast-check.test.sh` | `assert_hit` | line 5 `set -euo pipefail` | checker output, 110 to 1177 bytes over up to 11 lines; each line carries a `$TMPDIR` path | false red |
| `testing-strategy/scripts/client-terminal-ansi-check.test.sh` | `assert_hit` | line 6 `set -euo pipefail` | checker output, 163 to 266 bytes over up to 3 lines, also path-bearing | false red |
| `tighten-doc/scripts/mutation_probe.sh` | `probe()` | line 10 `set -uo pipefail` | the whole lint suite's output under a mutant, multi-line, size not fixed | a red mutant reported as uncovered |
| `code-review/scripts/test_opencode_review_retry.sh` | credential-binding check, `! find … -type l -print \| grep -q .` | line 19 `set -uo pipefail`; `check` runs the expression with `eval` in the suite's shell | `find` listing of the wrapper's diagnostic copy | false green: copied links read as absent |
| `code-review/scripts/test_review_gate.sh` | `prune_dead_pgid_records` | line 4 `set -uo pipefail`; the function runs in the suite's shell | `ps -eo pgid= \| tr -d ' '` of the whole host (1917 bytes, 482 processes on the measuring host) | a live group's record dropped as dead, which can hide a leak |
| `skill-extraction-workflow/scripts/test_uiux_delivery_contract.sh` | `parallel_completion_claims_absent` | line 5 `set -euo pipefail` | `active_text` of design references and handbooks (12 to 18 KB each) | false green: a forbidden completion claim mid-file reads as absent |
| `code-review/scripts/test_concern_excerpt.sh` | wrapper wiring check, `grep -A8 … claude_review.sh \| grep -q concern_excerpt` | line 5 `set -uo pipefail`; `check` runs the expression with `eval` in the suite's shell | nine lines of the wrapper's source (414 bytes on this tree, from a file whose lines run to 913 characters) | false red |

None of these files turns `pipefail` off again; the later `set -u`, `set +e`/`set -e` and `set -T` lines in them leave it on. Candidates came from `git ls-files '*.sh' \| xargs grep -lE pipefail`, then every non-comment line matching `\|[[:space:]]*grep[[:space:]]+-[a-zA-Z]*q` in those files, plus a second pass for `-E -q`, `--quiet` and `--silent` spellings (no extra hits).

The `find` site uses `[ -z "$(find … -type l -print -quit)" ]`, the form the same expression already uses for `auth.json`. The others read from a here-string.

Not changed:

| File | Reason |
| --- | --- |
| `skill-extraction-workflow/scripts/test_liveness_predicate_gate.sh`, `test_git_identity_predicate_gate.sh` | The suite runs under `set -u` only; `pipefail` appears only in the gate section it generates. |
| `skill-extraction-workflow/scripts/test_validate_skill_root_depth.sh`, `test_register_firing_path_wiring.sh`, `test_check_ccl_skill_catalog.sh` | Already fixed; the hits are comments explaining why. |
| `skill-extraction-workflow/scripts/generic-r0-leak-scan.sh` (self-test) | The input is one fixed message from `emit_clean_result`, at most a few hundred bytes. |
| `skill-extraction-workflow/scripts/check-ccl-skills.sh` contract-anchor grammar check | The input is the anchor gate's stdout, which is the one-line `contract_anchor_gate_ok (N anchors)` token (37 bytes on this tree). |
| `skill-extraction-workflow/scripts/test_locale_independent_gates.sh` | The input is one source line. |
| `code-review/scripts/test_opencode_review_retry.sh`, other checks | Checks on `$out` read the wrapper's stdout, one compact JSON line (440 to 893 bytes, 0 newlines in every case of a full run). The two checks on `field` values read a value from that JSON, so it is smaller than the whole line (499 and 771 bytes): the excerpt of a one-sentence fixture reply and the first reply the wrapper caps under 400 characters (the same suite asserts that cap). |
| `code-review/scripts/test_review_gate.sh`, other checks | `$out` is the gate's one-line JSON (275 to 6186 bytes, 0 newlines in every case of a full run); `ps -o stat= -p <pid>` is one line; `contract_packet_check` prints one token. |
| `code-review/scripts/test_code_review_identity.sh` | `tr '\n' ' '` joins the reference into one line, so `grep` reads all of it. Confirmed by the probe's control cases. |
| `code-review/scripts/test_review_gate_abort_leak.sh` | `probe_processes` (lines 132 to 138) filters `ps` through `awk` and prints one pid per live process whose command line contains this run's private `mktemp` path; `awk` reads all of `ps`, so that inner pipe cannot race. The input to `grep -qx` is therefore the processes the fixture itself starts under that path, a few pids at a time. This bound comes from the code, not a measurement: the output would pass 4096 bytes only if the fixture started several hundred processes under its path. |
| `skill-extraction-workflow/scripts/test_impact_chain_round_attribution.sh`, `scripts/test_install_opencode_skill_migration.sh`, `skill-extraction-workflow/scripts/check-evidence-card-leak.sh` | Inputs come from small seeded fixtures (a few file names, one ledger row, one field value). |

The follow-up list's 13 suites are all covered above. Four changed sites (`test_review_gate.sh`'s process table, the retry suite's `find`, the UI/UX scan and the concern-excerpt wiring check) are outside that list. The search behind the list did not match `find … | grep -q`, `-Fq`/`-Eiq` spellings, `ps … | tr … | grep`, or a `grep` feeding `grep -q`.

## Change

| Site | Before | After |
| --- | --- | --- |
| `assert_hit` (two suites) | `printf '%s' "$out" \| grep -qF "$want"` | `grep -qF "$want" <<<"$out"` |
| `mutation_probe.sh` | `printf '%s' "${out}" \| grep -q FAIL` | `grep -q FAIL <<<"${out}"` |
| retry credential check | `! find "$diagnostic_path" -type l -print \| grep -q .` | `[ -z "$(find "$diagnostic_path" -type l -print -quit)" ]` |
| `prune_dead_pgid_records` | `ps -eo pgid= 2>/dev/null \| tr -d ' ' \| grep -qx "$pgid"` | `grep -qx "$pgid" <<<"$(ps -eo pgid= 2>/dev/null \| tr -d ' ')"` |
| `parallel_completion_claims_absent` | `active_text "$file" \| grep -Eiq '…'` | `grep -Eiq '…' <<<"$(active_text "$file")"` |
| concern-excerpt wiring check | `grep -A8 "…" "$DIR/claude_review.sh" \| grep -q "concern_excerpt"` | `grep -q "concern_excerpt" <<<"$(grep -A8 "…" "$DIR/claude_review.sh")"` |

A writer that fails can change a verdict in one way. The new forms decide from what the writer printed; the old pipes also failed on the writer's exit status.

| Writer behaviour | `prune` (ps, tr) | symlink check (find) | UI/UX scan (active_text) |
| --- | --- | --- | --- |
| fails, prints nothing | record dropped, before and after | passes, before and after | no claim, before and after |
| prints the match, then fails | before: record dropped; after: kept | before: passes (links missed); after: fails | before: no claim; after: claim found |

The second row moves the symlink check and the UI/UX scan from a false green to the right verdict. `prune` keeps the record of a group that `ps` did list. The `assert_hit` and `mutation_probe.sh` sites read output already captured in a variable, so the checker's exit status is tested separately there, as before. The UI/UX scan still treats an `active_text` that prints nothing (for example, `ruby` missing) as "no claim", as before; that fail-open is recorded under Residual risk. A here-string adds one trailing newline. None of the patterns is anchored at the end of the input, so the set of matches is unchanged.

The two `testing-strategy` suites also gain the executable bit their shebang implies, as `lang-basics-go-check.test.sh` did, because the impact-chain row's firing path must name an executable.

## Test cases

`evidence/pipe-probe.sh <source-root> [runs]` takes each assertion's own code from the given tree (the helper function, or the `check "<label>"` expression) and runs it on input whose match is on the first line, followed by 256 KiB of further lines. It refuses to run a case whose extraction comes back empty.

| Group | Case | Old tree | New tree |
| --- | --- | --- | --- |
| changed | each of the seven sites above, on input it must accept (or, for the negated sites, reject) | wrong in every run | never wrong |
| inverse | the same seven sites on the same input shape without the needle | never wrong | never wrong |
| writer-fails | `prune`, the symlink check and the UI/UX scan when the writer prints the match and then exits non-zero (the second row of the table under Change) | wrong in every run | never wrong |
| control | four retry checks on one-line JSON, three identity checks on a `tr`-joined reference | never wrong | never wrong |

The inverse group shows the new forms still reach the opposite verdict. The control group backs the "one line, no race" reason for the sites left alone. Results: `evidence/validation.md`.

## Target-output map

| Owner | Direction | Status | File or reason |
| --- | --- | --- | --- |
| `testing-strategy` | owner | updated | `scripts/lang-basics-ast-check.test.sh`, `scripts/client-terminal-ansi-check.test.sh` |
| `code-review` | owner | updated | `scripts/test_opencode_review_retry.sh`, `scripts/test_review_gate.sh`, `scripts/test_concern_excerpt.sh` |
| `tighten-doc` | owner | updated | `scripts/mutation_probe.sh` |
| `skill-extraction-workflow` | owner | updated | `scripts/test_uiux_delivery_contract.sh`, register rows |
| `defect-diagnosis` | sibling | unchanged | Applied as written: the failing-path probe and paired control ran before the fix and decided which sites change. |
| `product-rd-workflow` | upstream | unchanged | No shared gate, contract or status semantics change; every edit is in a test or an evidence tool. |
| `product-ui-ux-design` | downstream of the UI/UX test | unchanged | The completion-claim rule it owns is unchanged; only the scan that enforces it is fixed. |

## Root cause and prevention

Contributing factors: (1) the pipe-into-`grep -q` shape is natural to write and its failure depends on scheduling; (2) most inputs are small, so the race is rare and looks like load; (3) each earlier round fixed the suites that failed and listed the rest, so sites waited for their own failure; (4) the follow-up list came from a text search that missed several spellings and over-counted comments and safe sites. A class control, a static check that flags `| grep -q` under `pipefail` unless the input is shown to be one line or one write, would stop new sites. It is a new blocking check, and the three-condition rule above is its false-positive design. It is left as a proposal for its own change.

## Residual risk

- `packages/ccl-skills-npm/scripts/host-smoke.sh` runs under `set -Eeuo pipefail` and pipes `codex plugin list`, `codex plugin marketplace list` and `claude plugin list --json` into `grep -q`, some of them negated. Those listings grow with the plugins installed on the host. This script installs into real hosts and was not run here, so it is left for a change that can run it.
- `parallel_completion_claims_absent` treats a failed `active_text` (for example, `ruby` missing) as "no claim", as it did before. Making it fail closed is a semantic change outside this sweep.
- Other early-exit readers under `pipefail` (`head`, `grep -m`, `grep -l`) are not swept.

## Validation

Results on the final candidate, the review passes and the commits they reviewed: `evidence/validation.md`.
