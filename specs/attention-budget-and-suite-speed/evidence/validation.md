# Batch 2a Validation & Evidence Record

## Scope & Candidate Baseline

- **Branch**: `ccoalm/attention-budget-and-suite-speed`
- **Target base**: `origin/main` (`a151098e21ab29e7a827a58b834c503012ca2eee`)
- **Plan**: `specs/attention-budget-and-suite-speed/plan.md` (Batch 2a of `specs/ci-gate-npm-slimming/plan.md`)
- **Visible UI surface**: `visible surface: no` (CLI review runner, repository size/hygiene validators, and shared-skill Markdown docs)
- **Risk tags**: `shared-gate`, `security-review` (`pending-dedicated-review` — bounded first-pass triage over `GIT_*` environment scrubbing in `review_diff.py` and `review_diff_clients.py`; merge decision rests with the sole repository owner/requester)

## Pre-Implementation RED Baselines (`T1a`–`T2b` + `T1d`)

All new defect/budget assertions were authored and executed against unpatched `a151098e21ab29e7a827a58b834c503012ca2eee` implementations before production edits:

| ID | Suite | Pre-Fix Result | Post-Fix GREEN Result |
| --- | --- | --- | --- |
| `T1a` (`10c2`) | `skills/code-review/scripts/test_review_diff.sh` | `exit 1` (**RED**) — `FAIL gitenv-rc: expected '0', got '2'`; `private opencode git init failed under poisoned GIT_DIR` | `exit 0` (`rc=0`, `status=passed`, `head` bound to `--cwd` repo, `GIT_DIR` / `GIT_CONFIG_PARAMETERS` / `GIT_CONFIG_COUNT` / `GIT_CONFIG_KEY_0` absent across all 4 `codex`, `claude`, `kimi`, and `opencode` child envs) |
| `T1b` (`14j`) | `skills/code-review/scripts/test_review_diff.sh` | `exit 1` (**RED**) — `expected <=10 git calls on clean run, got 14`; `36` fixture / `54` total `git init` calls across suite | `exit 0` (`10` `git` calls on clean run; `2` fixture `git init` calls + `16` isolated `opencode` scratch `git init` calls = `18` total `git init` calls) |
| `T1c` | `scripts/test_check_repo_hygiene.py` | `exit 1` (**RED**) — `('skills/code-review/scripts/review_diff.py', 'git_environment') not found in GIT_ENV_TARGETS` | `exit 0` (`Ran 6 tests OK`; `check-repo-hygiene.py .` -> `repo_hygiene_ok` across all `5` `GIT_ENV_TARGETS`) |
| `T1d` (`10f1b`) | `skills/code-review/scripts/test_review_diff.sh` | `pass-existing` (guards `Candidate.changed()` against caching `untracked` in `Git.digest()`) | `exit 0` (`reason_code=candidate_changed` on brand-new mid-review untracked file; differentially kills `M12`) |
| `T2a` (`g10b`) | `skills/skill-extraction-workflow/scripts/test_check_ccl_size_budget.sh` | `exit 1` (**RED**) — `expected reference_line_over_limit_count_base=2`, got `base=1, head=2, delta=+1` on 501-line CR-only base reference | `exit 0` (`reference_line_over_limit_count_base=2`, `head=2`, `delta=+0`) |
| `T2b` (`h1`) | `skills/skill-extraction-workflow/scripts/test_check_ccl_size_budget.sh` | `exit 1` (**RED**) — `1` `git grep` call and `10` total `git` calls on clean `REF_REPO` | `exit 0` (`0` `git grep` calls and `7` total `git` calls on clean `REF_REPO`; `8 -> 5` clean `git` calls on `ccl-skills`) |
| `T2c` | `skills/skill-extraction-workflow/scripts/test_skill_paired_eval.py` | `exit 1` (**RED**) — `SIGTERM-before-sibling-init` left killed `candidate-1-world-app` dir in `~/.claude/projects` | `exit 0` (UUID session files moved and empty project dir removed on pre-`init` interrupt; `M15` killed) |

## Attention-Budget & Interleaved Paired Benchmarks (`N=5`)

### `check-size-budget.sh` Before vs After (`origin/main` `a151098e21ab`)

| Surface / Metric | Base (`origin/main`) | Candidate (`HEAD`) | Delta |
| --- | --- | --- | --- |
| `skills/code-review/SKILL.md` body words / bytes | `5,917` words / `44,472` B (`>5,000` cap, `103L` fence warning) | `4,270` words / `31,823` B (`0` `>40L` fence warnings) | `-1,647` words (`-27.8%`) / `-12,649` B |
| `skills/code-review/references/manual-invocation-and-prompts.md` | `141` lines | `286` lines (`<500L` cap, `0` `>40L` fence warnings) | `+145` lines |
| `entrypoint_word_budget_over_limit_count` | `8` | `7` | **`-1`** |
| `skills/skill-extraction-workflow/references/dual-track-review-gate.md` | `573` lines (`>500L` cap) | `479` lines (`<=500L` cap) | `-94` lines (`-16.4%`) |
| `skills/skill-extraction-workflow/references/dual-track-debug-prompts.md` | absent | `101` lines (`<500L` cap, `##`-structured) | `+101` lines |
| `reference_line_over_limit_count` | `4` | `3` | **`-1`** |
| `skills/skill-extraction-workflow/SKILL.md` (`severe_debt`) | `15,586` words / `113,670` B | `15,554` words / `113,487` B | `-32` words / `-183` B (`entrypoint_word_budget_legacy_ok`) |

### Interleaved Paired Benchmarks (`N=5`, Single-Variable Control)

| Workload | Rounds | Base Median | Candidate Median | Subprocess / Speedup Delta |
| --- | --- | --- | --- | --- |
| `check-size-budget.sh` (clean `ccl-skills` checkout) | `5` | `290.89 ms` (`8` `git` calls) | `268.97 ms` (`5` `git` calls) | `1.08x` (`-3` `git` calls, `0` `git grep`) |
| `check-size-budget.sh` (dirty candidate worktree) | `5` | `328.12 ms` (`13` `git` calls) | `303.54 ms` (`10` `git` calls) | `1.08x` (`-3` `git` calls, `0` `git grep`) |
| `review_diff.py` single clean `codex` run | `5` | `312.74 ms` (`14` `git` calls) | `313.21 ms` (`10` `git` calls) | `1.00x` wall (`-4` `git` calls, `-28.6%`) |
| `test_review_diff.sh` full regression suite | `5` | `47.973 s` (`36` fixture / `54` total `git init`) | `43.476 s` (`2` fixture / `18` total `git init`) | `1.10x` (`-4.50 s` saved per run) |

## Applied Differential Killing-Mutation Walk (`15/15`)

Executed in disposable copies outside the candidate worktree (`pre_wt_sha256 == post_wt_sha256` verified on every run; unmutated control suites passed `rc=0` first):

| Mutant ID | Target File | Mutated Predicate | Differential RED Attribution (`rc=1`) |
| --- | --- | --- | --- |
| `M01_hygiene_target_review_diff` | `scripts/check-repo-hygiene.py` | Remove `review_diff.py` from `GIT_ENV_TARGETS` | `test_current_worktree_satisfies_hygiene_gate` (`AssertionError` on `review_diff.py`) |
| `M02_hygiene_target_review_diff_clients` | `scripts/check-repo-hygiene.py` | Remove `review_diff_clients.py` from `GIT_ENV_TARGETS` | `test_current_worktree_satisfies_hygiene_gate` (`AssertionError` on `review_diff_clients.py`) |
| `M03_review_diff_missing_git_config_key` | `skills/code-review/scripts/review_diff.py` | Drop `"GIT_CONFIG_PARAMETERS"` from `GIT_CONFIG_ROUTING_ENV` | `check-repo-hygiene.py` (`git-env-missing-config-keys` on `review_diff.py` only) |
| `M04_review_diff_clients_missing_git_routing_key` | `skills/code-review/scripts/review_diff_clients.py` | Drop `"GIT_DIR"` from `GIT_REPOSITORY_ROUTING_ENV` | `check-repo-hygiene.py` (`git-env-missing-routing-keys` on `review_diff_clients.py` only) |
| `M05_size_budget_cr_only_base_parity` | `skills/skill-extraction-workflow/scripts/check-size-budget.sh` | Count base blobs with `.count("\n")` instead of `ref_info_for_text` | `test_check_ccl_size_budget.sh` (`g10b` CR-only base parity only) |
| `M06_size_budget_no_git_grep` | `skills/skill-extraction-workflow/scripts/check-size-budget.sh` | Re-introduce a `git grep` probe | `test_check_ccl_size_budget.sh` (`h1` `expected 0 'git grep' calls, got 1`) |
| `M07_size_budget_clean_git_call_cap` | `skills/skill-extraction-workflow/scripts/check-size-budget.sh` | Add 2 redundant `git rev-parse` calls (`9 > 8` on `REF_REPO`) | `test_check_ccl_size_budget.sh` (`h1` `expected <=8 total git calls on clean tree, got 9`) |
| `M08_review_diff_git_env_scrub` | `skills/code-review/scripts/review_diff.py` | Return unscrubbed `dict(os.environ)` from `git_environment()` | `test_review_diff.sh` (`gitenv-*` assertions in `10c2` only) |
| `M09_review_diff_clients_git_env_scrub` | `skills/code-review/scripts/review_diff_clients.py` | Return unscrubbed `dict(os.environ)` from `git_environment()` | `test_review_diff.sh` (`gitenv-*` child-env assertions in `10c2` only) |
| `M10_review_diff_candidate_bind_git_batch` | `skills/code-review/scripts/review_diff.py` | Add 4 redundant `rev-parse` calls in `Candidate.bind()` (`14 > 10`) | `test_review_diff.sh` (`gitcount-single: expected <=10 git calls on clean run, got 14` only) |
| `M11_candidate_changed_cached_head` | `skills/code-review/scripts/review_diff.py` | Pass `head=self.head` inside `Candidate.changed()` | `test_review_diff.sh` (`FAIL commit-reason: expected 'candidate_changed', got ''` only) |
| `M12_candidate_changed_cached_untracked` | `skills/code-review/scripts/review_diff.py` | Pass `untracked=self.untracked` inside `Candidate.changed()` | `test_review_diff.sh` (`FAIL newuntracked-reason: expected 'candidate_changed', got ''` only) |
| `M13_claude_git_env_scrub` | `skills/code-review/scripts/review_diff_clients.py` | Pass `dict(os.environ)` instead of `git_environment()` in `Claude.run()` | `test_review_diff.sh` (`FAIL gitenv-claude-*` assertions in `10c2` only) |
| `M14_kimi_git_env_scrub` | `skills/code-review/scripts/review_diff_clients.py` | Use `dict(os.environ)` instead of `git_environment()` in `Kimi.run()` | `test_review_diff.sh` (`FAIL gitenv-kimi-*` assertions in `10c2` only) |
| `M15_paired_eval_pre_init_interrupt_cleanup` | `skills/skill-extraction-workflow/scripts/skill-paired-eval.py` | Disable `if interrupted and not init_seen and cwd is not None:` cleanup in `collect_transcripts()` | `test_skill_paired_eval.py` (`SIGTERM-before-sibling-init` in `test_a_signal_during_a_run_stops_the_batch_and_writes_its_evidence` only) |

## Zero-Loss Obligation-Preservation Table (`102/102` Derived Rows)

Derived via `skills/skill-extraction-workflow/scripts/governing-chain-diff.py` (`CR_SKILL` `69`, `CR_MAN` `4`, `SEW_SKILL` `4`, `SEW_DT` `25`, `SEW_DBG` `0` pre-existing; `carrier_count == 1` on `102/102` rows, qualifier co-occurrence, location/chain match, `0` broken/orphan links):

Legend: `CR_SKILL`=`skills/code-review/SKILL.md`, `CR_MAN`=`skills/code-review/references/manual-invocation-and-prompts.md`, `CR_TAC`=`skills/code-review/references/timeout-auth-and-capabilities.md`, `SEW_SKILL`=`skills/skill-extraction-workflow/SKILL.md`, `SEW_VAL`=`skills/skill-extraction-workflow/references/validation-and-landing.md`, `SEW_DT`=`skills/skill-extraction-workflow/references/dual-track-review-gate.md`, `SEW_DBG`=`skills/skill-extraction-workflow/references/dual-track-debug-prompts.md`; `§SEP`=`§Script Entry Point`, `§HE`=`§Harness Exclusion`, `§Auth`=`§Auth And CLI Pitfalls`, `§Routing`=`§Reviewer Client Routing`, `§Staged…`=`§Staged Controller, Harness Self-Review, And Consult Invocation`, `§Manual…`=`§Manual Command Shape`, `§Compat`=`§Consult Exit-Code Compatibility`, `§Cap`=`§CLI Capability Notes`, `§Challenge…`=`§Challenge Wrapper Debug Shape`, `§Review…`=`§Review Wrapper Debug Shape`.

|Before Obligation (`governing-chain-diff.py`)|Old|After|Status|Proof (Checks 1–4)|
|---|---|---|---|---|
|The Claude provider wrapper…|`CR_SKILL#R01`(`ch`)|`CR_SKILL` `§SEP`|`merged`|`c=1`(`enforces local he…`),`q:`0600`=2`; Tightened inline in `§Script Entry Point`; `--add-dir` / dirty-worktree / `--prompt-only` / schema rules stay inline in `SKILL.md`|
|Runs without selected owner…|`CR_SKILL#R02`(`ch`)|`CR_SKILL` `§HE`|`subsumed`|`c=1`(`runs without sele…`),`q:v`; dedup `L90`; canonical inline rule in `§HE` (`L146`) preserves trigger, flag & fail-closed gate|
|Owner-aware runs load the i…|`CR_SKILL#R03`(`ch`)|`CR_SKILL` `§HE`|`subsumed`|`c=1`(`while owner-aware…`),`q:v`; dedup `L90`; canonical inline rules in `L92-106` & `§HE` (`L146`) preserve `--plugin-dir` + explicit owners|
|they never manufacture a se…|`CR_SKILL#R04`(`ch`)|`CR_MAN` `§Manual…`|`rehosted`|`c=1`(`Do not emulate th…`),`q:`Do not`=10`; old(-dup clause->`CR_MAN §Manual…`): holds single prohibition|
|If that registry is absent,…|`CR_SKILL#R05`(`ch`)|`CR_SKILL` `§Routing`|`rehosted`|`c=1`(``native_skill_bin…`),`q:v`; old (`§Script Entry Point L90`): loses dup sentence->`§Routing L176` + `L98-102`): holds single unusable-registry rule|
|Init's command, skill, and …|`CR_SKILL#R06`(`ch`)|`CR_MAN` `§Manual…`|`rehosted`|`c=1`(`Runtime init may …`),`q:`never`=13`; old(-parser detail->`§Manual…`): holds single vocabulary-never-judged rule|
|tools, MCP, and permission …|`CR_SKILL#R07`(`ch`)|`CR_MAN` `§Manual…`|`rehosted`|`c=1`(`Only the exact to…`),`q:`Only`=1,`fail closed`=3`; old:keeps inline fail-closed pointer (`pinned permissionMode`)->`§Manual…`): holds full isolation predicate|
|For review/challenge it als…|`CR_SKILL#R08`(`ch`)|`CR_MAN` `§Manual…`|`rehosted`|`c=1`(`emits stable `rea…`),`q:`every`=4`; old(-wrapper field list->`§Manual…`): gains `--diff-file` + inconclusive-field contract|
|Every mode captures Claude …|`CR_SKILL#R09`(`ch`)|`CR_TAC` `§Cap`|`rehosted`|`c=1`(`paired with `--js…`),`q:v`; old:keeps `fail-closed stream-JSON schema` pointer->`CR_TAC §Cap`): holds `--json-schema` pairing|
|`parse_review_json.py` unwr…|`CR_SKILL#R10`(`ch`)|`CR_TAC` `§Cap`|`rehosted`|`c=1`(`unwraps `structur…`),`q:`rejects`=2`; old:loses envelope-field list->`§Cap`): holds `parse_review_json.py` rejection fields|
|`classify_envelope.py` read…|`CR_SKILL#R11`(`ch`)|`CR_MAN` `§Manual…`|`rehosted`|`c=1`(`raw-text matching…`),`q:`only`=70`; old:loses prose-fallback detail->`§Manual…` + `CR_TAC:177`): holds single rule|
|On an auth false negative t…|`CR_SKILL#R12`(`ch`)|`CR_SKILL` `§SEP`|`subsumed`|`c=1`(`When the gate ret…`),`q:v`; Duplicate in `L90` removed; `SKILL.md:118-123` in same section preserves `reason_code=auth_path_unavailable`|
|a host rerun of the same ga…|`CR_SKILL#R13`(`ch`)|`CR_SKILL` `§SEP`|`subsumed`|`c=1`(`rerun the same ga…`),`q:`once`=3`; Duplicate in `L90` removed; `SKILL.md:118-123` in same section preserves single `--host-remediation-attempted` rerun|
|`--timeout` controls each f…|`CR_SKILL#R14`(`ch`)|`CR_TAC` `§Wait Policy`|`rehosted`|`c=1`(`The wrapper rejec…`),`q:`5`=6,`1200`=2`; old:keeps `timeout clamping` pointer->`CR_TAC §Wait Policy`): holds `5..1200`s bounds|
|values above 1200 are clamp…|`CR_SKILL#R15`(`ch`)|`CR_TAC` `§Wait Policy`|`rehosted`|`c=1`(`including values …`),`q:`1200`=2`; old:loses `1200`s clamp detail->`§Wait Policy`): holds `1200`s ceiling|
|The wrapper does not make a…|`CR_SKILL#R16`(`ch`)|`CR_SKILL` `§Routing`|`rehosted`|`c=1`(`None of the four …`),`q:`None`=1`; old (`§Script Entry Point`): loses Claude-only dup->`§Routing L176`): holds 4-client no-probe rule|
|The formal invocation's own…|`CR_SKILL#R17`(`ch`)|`CR_TAC` `§Auth`|`rehosted`|`c=1`(`The formal invoca…`),`q:`must`=14`; old:keeps `exact --tools` pointer->`CR_TAC §Auth`): holds stream-init proof|
|packet-only modes allow onl…|`CR_SKILL#R18`(`ch`)|`CR_MAN` `§Manual…`|`rehosted`|`c=1`(`schema-enabled ma…`),`q:`only`=70`; old:keeps `Read,Grep,Glob` in `L146`->`§Manual…`): holds `StructuredOutput` allowance|
|Unexpected tool use, MCP in…|`CR_SKILL#R19`(`ch`)|`CR_TAC` `§Auth`|`rehosted`|`c=1`(`A permission deni…`),`q:`fails closed`=1`; old:keeps inline `fail-closed` summary->`§Auth`): holds per-condition fail-closed rule|
|`--allowedTools` is a permi…|`CR_SKILL#R20`(`ch`)|`CR_SKILL` `§Auth`|`rehosted`|`c=1`(``--allowedTools` …`),`q:`never`=26`; old (`§Script Entry Point`): loses dup->`§Auth L170` + `CR_MAN:174`): holds rule|
|The wrapper deliberately ne…|`CR_SKILL#R21`(`ch`)|`CR_MAN` `§Manual…`|`rehosted`|`c=1`(`The wrapper delib…`),`q:`never`=13`; old(-wrapper internal note->`§Manual…`): gains it verbatim|
|Run the script by path whil…|`CR_SKILL#R22`(`ch`)|`CR_SKILL` `§SEP`|`merged`|`c=1`(`Run the script by…`),`q:v`; Extended in place in `SKILL.md:108` with pointer to relocated recipes|
|The script directory and re…|`CR_SKILL#R23`(`ch`)|`CR_SKILL` `§SEP>Run…`|`merged`|`c=1`(`The script direct…`),`q:v`; host R22; verbatim & still supported|
|do not `cd` into the skill …|`CR_SKILL#R24`(`ch`)|`CR_SKILL` `§SEP>Run…`|`merged`|`c=1`(`do not `cd` into …`),`q:`do not`=4,`unless`=10`; host R22; verbatim|
|Consult mode requires a non…|`CR_SKILL#R25`(`ch`)|`CR_SKILL` `§SEP`|`merged`|`c=1`(`Consult mode requ…`),`q:`requires`=9,`unless`=10`; in-place `SKILL.md:108`|
|without `--include-diff`, r…|`CR_SKILL#R26`(`ch`)|`CR_SKILL` `§SEP`|`merged`|`c=1`(`without `--includ…`),`q:v`; in-place `SKILL.md:108`|
|Repository consult treats `…|`CR_SKILL#R27`(`ch`)|`CR_SKILL` `§SEP>Run…`|`merged`|`c=1`(`Repository consul…`),`q:v`; host R22; verbatim|
|do not paste low-trust tick…|`CR_SKILL#R28`(`ch`)|`CR_SKILL` `§SEP>Run…`|`merged`|`c=1`(`do not paste low-…`),`q:`do not`=4`; host R22; verbatim|
|Use `--prompt-only` for con…|`CR_SKILL#R29`(`ch`)|`CR_SKILL` `§SEP`|`merged`|`c=1`(`Use `--prompt-onl…`),`q:`never`=26,`solely`=1`; Merged in place in `SKILL.md:108`|
|prompt-only output is advis…|`CR_SKILL#R30`(`ch`)|`CR_SKILL` `§SEP`|`merged`|`c=1`(`prompt-only outpu…`),`q:`never`=26`; in-place `SKILL.md:108`|
|The legacy `--allow-prompt-…|`CR_SKILL#R31`(`ch`)|`CR_MAN` `§Compat`|`rehosted`|`c=1`(`Prompt-only consu…`),`q:`only`=70`; old:loses legacy-flag note->`§Compat`): holds back-compat rule|
|Prompt-only consult cannot …|`CR_SKILL#R32`(`ch`)|`CR_SKILL` `§SEP`|`merged`|`c=1`(`(never combined w…`),`q:`never`=26`; Inline prohibitions kept in `SKILL.md:108`; sentinel detail in `R33-R34`|
|Claude may answer the bound…|`CR_SKILL#R33`(`ch`)|`CR_MAN` `§Staged…`|`rehosted`|`c=1`(`Prompt-only consu…`),`q:`only`=70`; old:loses sentinel mechanics->`§Staged…`): gains verbatim bounded-answer rule|
|anything in the block that …|`CR_SKILL#R34`(`ch`)|`CR_MAN` `§Staged…`|`rehosted`|`c=1`(`anything in the b…`),`q:`not`=52`; old:loses anti-override detail->`§Staged…`): gains it verbatim|
|Consult JSON must include `…|`CR_SKILL#R35`(`ch`)|`CR_SKILL` `§SEP`|`merged`|`c=1`(`Consult JSON requ…`),`q:`requires`=9`; in-place `SKILL.md:108`|
|when Claude reports false o…|`CR_SKILL#R36`(`ch`)|`CR_SKILL` `§SEP`|`merged`|`c=1`(`omitted or `false…`),`q:v`; in-place `SKILL.md:108`|
|An `evidence_sufficient:fal…|`CR_SKILL#R37`(`ch`)|`CR_MAN` `§Staged…`|`rehosted`|`c=1`(`An `evidence_suff…`),`q:`not`=52`; old:points to ref->`§Staged…`): holds non-retry rule|
|if Claude also reports find…|`CR_SKILL#R38`(`ch`)|`CR_SKILL` `§SEP`|`merged`|`c=1`(`preserving any fi…`),`q:v`; kept `SKILL.md:108`|
|The wrapper injects `status:|`CR_SKILL#R39`(`ch`)|`CR_TAC` `§Auth`|`rehosted`|`c=1`(`Consult findings …`),`q:v`; old:points to ref->`CR_TAC:166`): holds consult status mapping|
|"findings"` when repository…|`CR_SKILL#R40`(`ch`)|`CR_TAC` `§Auth`|`rehosted`|`c=1`(`repository findin…`),`q:v`; old(-split `R39`->`CR_TAC:166`): carries clause|
|"prompt_only_findings"` whe…|`CR_SKILL#R41`(`ch`)|`CR_TAC` `§Auth`|`rehosted`|`c=1`(`prompt-only findi…`),`q:v`; old(-split `R39`->`CR_TAC:166`): carries clause|
|Prompt-only findings also g…|`CR_SKILL#R42`(`ch`)|`CR_MAN` `§Staged…`|`rehosted`|`c=1`(`Prompt-only findi…`),`q:v`; old:points to ref->`§Staged…`): gains `source: "prompt-only-advisory"` verbatim|
|"prompt-only-advisory"` ins…|`CR_SKILL#R43`(`ch`)|`CR_MAN` `§Staged…`|`rehosted`|`c=1`(`inside each findi…`),`q:v`; old(-split `R42`->`§Staged…`): carries clause verbatim|
|Empty prompt-only results g…|`CR_SKILL#R44`(`ch`)|`CR_TAC` `§Auth`|`rehosted`|`c=1`(`the final JSON ca…`),`q:v`; old:points to refs->`CR_TAC:166` + `R47`): holds empty prompt-only tuple|
|"evidence_only"`, `consult_…|`CR_SKILL#R45`(`ch`)|`CR_TAC` `§Auth`|`rehosted`|`c=1`(``status: "evidenc…`),`q:v`; old(-split `R44`->`CR_TAC:166`|
|"prompt-only"`, `tool_ident…|`CR_SKILL#R46`(`ch`)|`CR_TAC` `§Auth`|`rehosted`|`c=1`(``consult_scope: "…`),`q:v`; old(-split `R44`->`CR_TAC:166`|
|"code-review:no-tools"`, `a…|`CR_SKILL#R47`(`ch`)|`CR_MAN` `§Staged…`|`rehosted`|`c=1`(`empty prompt-only…`),`q:v`; old(-split `R44`->`§Staged…`): gains `tool_identity` field|
|true`, `untrusted_evidence:|`CR_SKILL#R48`(`ch`)|`CR_TAC` `§Auth`|`rehosted`|`c=1`(``advisory: true`,…`),`q:v`; old(-split `R44`->`CR_TAC:166`|
|true`, and `gate_eligible:|`CR_SKILL#R49`(`ch`)|`CR_TAC` `§Auth`|`rehosted`|`c=1`(``untrusted_eviden…`),`q:v`; old(-split `R44`->`CR_TAC:166`|
|empty repository consult re…|`CR_SKILL#R50`(`ch`)|`CR_MAN` `§Staged…`|`rehosted`|`c=1`(`and empty reposit…`),`q:v`; old:points to ref->`§Staged…`): gains empty-repo consult tuple verbatim|
|"answer"`, `consult_scope:|`CR_SKILL#R51`(`ch`)|`CR_MAN` `§Staged…`|`rehosted`|`c=1`(`empty repository …`),`q:v`; old(-split `R50`->`§Staged…` verbatim|
|"repository"`, `tool_identity:|`CR_SKILL#R52`(`ch`)|`CR_MAN` `§Staged…`|`rehosted`|`c=1`(``consult_scope: "…`),`q:v`; old(-split `R50`->`§Staged…` verbatim|
|"code-review:read-only-repo…|`CR_SKILL#R53`(`ch`)|`CR_MAN` `§Staged…`|`rehosted`|`c=1`(``tool_identity: "…`),`q:v`; old(-split `R50`->`§Staged…` verbatim|
|false`, `untrusted_evidence:|`CR_SKILL#R54`(`ch`)|`CR_MAN` `§Staged…`|`rehosted`|`c=1`(``tool_identity: "…`),`q:v`; old(-split `R50`->`§Staged…` verbatim|
|false`, and `gate_eligible:|`CR_SKILL#R55`(`ch`)|`CR_MAN` `§Staged…`|`rehosted`|`c=1`(``advisory: false`…`),`q:v`; old(-split `R50`->`§Staged…` verbatim|
|All consult results exit `2…|`CR_SKILL#R56`(`ch`)|`CR_SKILL` `§SEP`|`merged`|`c=1`(`All consult resul…`),`q:`cannot`=10`; in-place `SKILL.md:108`|
|This is a breaking migratio…|`CR_SKILL#R57`(`ch`)|`CR_MAN` `§Compat`|`rehosted`|`c=1`(`consult success u…`),`q:v`; old:keeps `Consult exit-code history` pointer (`L131`)->`§Compat`): holds history|
|update downstream controlle…|`CR_SKILL#R58`(`ch`)|`CR_MAN` `§Compat`|`rehosted`|`c=1`(`Existing consult …`),`q:`must`=21,`must not`=3`; old:loses dup migration note->`§Compat`): holds merged rule|
|Downstream controllers MUST…|`CR_SKILL#R59`(`ch`)|`CR_SKILL` `§SEP`|`merged`|`c=1`(`downstream contro…`),`q:`MUST`=1`; kept `SKILL.md:108`|
|consult output is not a rev…|`CR_SKILL#R60`(`ch`)|`CR_MAN` `§Staged…`|`rehosted`|`c=1`(``evidence_suffici…`),`q:v`; old:keeps advisory/never-gate-eligible inline->`§Staged…`): holds model-judgment clause|
|Never use a consult result …|`CR_SKILL#R61`(`ch`)|`CR_SKILL` `§SEP`|`merged`|`c=1`(`and must never us…`),`q:`must`=18,`never`=26`; in-place `SKILL.md:108` (`Never use` -> `must never use`)|
|If Claude needs to inspect …|`CR_SKILL#R62`(`ch`)|`CR_SKILL` `§SEP>Run…`|`merged`|`c=1`(`If Claude needs t…`),`q:v`; host R22; verbatim|
|Review/challenge require a …|`CR_SKILL#R63`(`ch`)|`CR_SKILL` `§SEP>Run…`|`merged`|`c=1`(`Review/challenge …`),`q:`require`=16`; host R22; verbatim|
|The script canonicalizes th…|`CR_SKILL#R64`(`ch`)|`CR_SKILL` `§SEP>Run…`|`merged`|`c=1`(`The script canoni…`),`q:v`; host R22; verbatim|
|If the executing wrapper it…|`CR_SKILL#R65`(`ch`)|`CR_SKILL` `§SEP>Run…`|`merged`|`c=1`(`If the executing …`),`q:`only`=48`; host R22; verbatim|
|otherwise it refuses to avo…|`CR_SKILL#R66`(`ch`)|`CR_SKILL` `§SEP>Run…`|`merged`|`c=1`(`otherwise it refu…`),`q:`refuses`=5`; host R22; verbatim|
|When intentionally reviewin…|`CR_SKILL#R67`(`ch`)|`CR_MAN` `§Staged…`|`rehosted`|`c=1`(`When intentionall…`),`q:`before`=10`; old:points to `§Staged…`->`CR_MAN`): gains sentence + `--review-harness` recipe|
|`references/manual-invocati…|`CR_SKILL#R68`(`ch`)|`CR_SKILL` `§Reference Loading`|`merged`|`c=1`(``references/manua…`),`q:v`; Updated in place in `SKILL.md:192` to index relocated wrapper recipes|
|Load only when debugging or…|`CR_SKILL#R69`(`ch`)|`CR_SKILL` `§Reference Loading`|`merged`|`c=1`(`raw CLI shapes mu…`),`q:`must`=18,`never`=26`; Updated in place in `SKILL.md:192` strengthening raw-CLI prohibition|
|Load this file only when de…|`CR_MAN#R01`(`ch`)|`CR_MAN` `H1 intro`|`merged`|`c=1`(`Load this file wh…`),`q:v`; Updated in place (`L3-6`) to cover relocated wrapper recipes|
|The raw commands below illu…|`CR_MAN#R02`(`ch`)|`CR_MAN` `H1 intro`|`merged`|`c=1`(`The raw `claude -…`),`q:`only`=70`; Tightened in place (`L6-7`) scoping raw-CLI warning to `§Manual…`|
|They intentionally do not r…|`CR_MAN#R03`(`ch`)|`CR_MAN` `H1 intro`|`merged`|`c=1`(`they do not repro…`),`q:`never`=13`; Tightened in place (`L7-9`)|
|Existing consult consumers …|`CR_MAN#R04`(`ch`)|`CR_MAN` `§Compat`|`merged`|`c=1`(`Existing consult …`),`q:`must`=21,`must not`=3`; Extended in place (`§Compat`) merging `SKILL.md R58`|
|If independent review was a…|`SEW_SKILL#R01`(`ch`)|`SEW_SKILL` `§Extraction Workflow > 6. Validate before landing.`|`merged`|`c=1`(`If primary Claude…`),`q:`must`=68`; Tightened in place (`SKILL.md:282`) pointing to canonical Core Rule `L167` + `SEW_VAL`|
|the `code-review` wrapper i…|`SEW_SKILL#R02`(`ch`)|`SEW_VAL` `§Bounded Independent Review Packet > 7.`|`rehosted`|`c=1`(`Record the result…`),`q:`only`=62`; old (`SKILL.md:282`): points to `SEW_VAL`->`SEW_VAL:166`): holds 3-outcome enum|
|The legacy bounded review p…|`SEW_SKILL#R03`(`ch`)|`SEW_SKILL` `§Core Rules > Validation & the dual-track gate`|`subsumed`|`c=1`(`The legacy bounde…`),`q:`only`=125,`never`=44`; Cross-section duplicate removed from `L282`; canonical Core Rule (`SKILL.md:167`) preserves stricter guard|
|does not replace `reference…|`SEW_SKILL#R04`(`ch`)|`SEW_SKILL` `§Reference Loading`|`merged`|`c=1`(`does not replace …`),`q:`only`=125,`never`=44`; Extended in place (`SKILL.md:306`) registering `SEW_DBG`|
|The raw CLI shapes below ar…|`SEW_DT#R01`(`ch`)|`SEW_DT` `§Unavail`|`merged`|`c=1`(`Raw `codex review…`),`q:`only`=108,`never`=81`; Tightened in place (`SEW_DT:287`) keeping inline non-evidence guard + pointer|
|Debug a wrapper with raw `c…|`SEW_DT#R02`(`ch`)|`SEW_DBG` `§Review…`|`rehosted`|`c=1`(`Debug a wrapper w…`),`q:v`; old(-raw CLI recipe->`SEW_DBG §Review…`): gains it|
|Prompt template (adapt as n…|`SEW_DT#R03`(`ch`)|`SEW_DBG` `§Review…`|`rehosted`|`c=1`(`Prompt template (…`),`q:v`; old(-review debug template); new(+verbatim)|
|one finding per line with s…|`SEW_DT#R04`(`ch`)|`SEW_DBG` `§Review…`|`rehosted`|`c=1`(`one finding per l…`),`q:v`; old(-debug output format); new(+verbatim)|
|Apply each finding before t…|`SEW_DT#R05`(`ch`)|`SEW_DBG` `§Review…`|`rehosted`|`c=1`(`Apply each findin…`),`q:`before`=4`; old(-debug note); new(+verbatim)|
|Debug a wrapper with raw `c…|`SEW_DT#R06`(`ch`)|`SEW_DBG` `§Challenge…`|`rehosted`|`c=1`(`Debug a wrapper w…`),`q:v`; old(-raw `codex exec` recipe->`§Challenge…`): gains it|
|Redirect stdin from `/dev/n…|`SEW_DT#R07`(`ch`)|`SEW_DBG` `§Challenge…`|`rehosted`|`c=1`(`Redirect stdin fr…`),`q:v`; old(-stdin heading); new(+verbatim)|
|`codex exec` reads instruct…|`SEW_DT#R08`(`ch`)|`SEW_DBG` `§Challenge…`|`rehosted`|`c=1`(``codex exec` read…`),`q:v`; old(-stdin-block note); new(+verbatim)|
|`</dev/null` makes it read …|`SEW_DT#R09`(`ch`)|`SEW_DBG` `§Challenge…`|`rehosted`|`c=1`(``</dev/null` make…`),`q:`only`=8`; old(-`</dev/null` note); new(+verbatim)|
|If a `codex exec` call sits…|`SEW_DT#R10`(`ch`)|`SEW_DBG` `§Challenge…`|`rehosted`|`c=1`(`If a `codex exec`…`),`q:`before`=4`; old(-zero-output note); new(+verbatim)|
|(`codex review` reads stdin…|`SEW_DT#R11`(`ch`)|`SEW_DBG` `§Challenge…`|`rehosted`|`c=1`(`(`codex review` r…`),`q:`only`=8`; old(-`codex review` stdin note); new(+verbatim)|
|A **second, distinct** hang…|`SEW_DT#R12`(`ch`)|`SEW_DBG` `§Challenge…`|`rehosted`|`c=1`(`A **second, disti…`),`q:v`; old(-`notify` hang intro); new(+verbatim)|
|when the host's codex confi…|`SEW_DT#R13`(`ch`)|`SEW_DBG` `§Challenge…`|`rehosted`|`c=1`(`when the host's c…`),`q:`before`=4`; old(-`notify` wait detail); new(+verbatim)|
|Neutralize it per-invocatio…|`SEW_DT#R14`(`ch`)|`SEW_DBG` `§Challenge…`|`rehosted`|`c=1`(`Neutralize it per…`),`q:`only`=8`; old(-`-c notify='[]'` note); new(+verbatim)|
|Only blanket-disable a **no…|`SEW_DT#R15`(`ch`)|`SEW_DBG` `§Challenge…`|`rehosted`|`c=1`(`Only blanket-disa…`),`q:`Only`=1`; old(-non-policy hook caveat); new(+verbatim)|
|if the configured notifier …|`SEW_DT#R16`(`ch`)|`SEW_DBG` `§Challenge…`|`rehosted`|`c=1`(`if the configured…`),`q:v`; old(-audit/DLP preservation note); new(+verbatim)|
|Always wrap the call in `ti…|`SEW_DT#R17`(`ch`)|`SEW_DBG` `§Challenge…`|`rehosted`|`c=1`(`Always wrap the c…`),`q:`Always`=1`; old(-`timeout` wrapper rule); new(+verbatim)|
|A `timeout`-killed call (ex…|`SEW_DT#R18`(`ch`)|`SEW_DBG` `§Challenge…`|`rehosted`|`c=1`(`A `timeout`-kille…`),`q:`124`=2,`never`=4`; old (`SEW_DT:220` keeps general timeout rule): loses `exit 124` debug line->`§Challenge…`): gains it|
|the point is to fail the la…|`SEW_DT#R19`(`ch`)|`SEW_DBG` `§Challenge…`|`rehosted`|`c=1`(`the point is to f…`),`q:`not`=25`; old(-fast-fail rationale); new(+verbatim)|
|Verify the override for the…|`SEW_DT#R20`(`ch`)|`SEW_DBG` `§Challenge…`|`rehosted`|`c=1`(`Verify the overri…`),`q:`before`=4`; old(-`--strict-config` probe); new(+verbatim)|
|For a rule/gate/status chan…|`SEW_DT#R21`(`ch`)|`SEW_DT` `§Running the challenge pass`|`merged`|`c=1`(`For a rule/gate/s…`),`q:`not`=265`; Extended in place (`SEW_DT:291`) linking item 9 to `SEW_DBG`|
|a generic challenge (items …|`SEW_DT#R22`(`ch`)|`SEW_DT` `§Chal>item9`|`merged`|`c=1`(`a generic challen…`),`q:`none`=4`; Host opener clarified (`R21`); child clause preserved verbatim|
|a gate keyed on a `rejected…|`SEW_DT#R23`(`ch`)|`SEW_DT` `§Chal>item9`|`merged`|`c=1`(`a gate keyed on a…`),`q:v`; Host opener clarified (`R21`); child clause preserved verbatim|
|Use `--json` to capture rea…|`SEW_DT#R24`(`ch`)|`SEW_DBG` `§Challenge…`|`rehosted`|`c=1`(`Use `--json` to c…`),`q:v`; old(-`--json` debug note); new(+verbatim)|
|Parse the JSONL stream with…|`SEW_DT#R25`(`ch`)|`SEW_DBG` `§Challenge…`|`rehosted`|`c=1`(`Parse the JSONL s…`),`q:v`; old(-JSONL parsing note); new(+verbatim)|

## Behavioral Evidence & Closeout Gates

- **`RED-baseline` (`code-review` & `skill-extraction-workflow` executable gates)**: Constructed scenarios `T1a`–`T2c` above ran RED on `a151098e21ab` and GREEN post-fix (`10c2`, `14j`, `T1c`, `g10b`, `h1`, `SIGTERM-before-sibling-init`), backed by `15/15` applied differential mutations (`M01`–`M15`).
- **`semantic-control` (`code-review` & `skill-extraction-workflow` consolidations)**: `102/102` `governing-chain-diff.py` rows verified `carrier_count == 1`; `test_code_review_identity.sh`, `test_extraction_review_gate.sh`, `test_ai_coding_implementation_gates.sh`, `validate-skill.sh`, and `check-ccl-skills.sh` (`eval_routing_ok`) pass unchanged; independent reviewer confirmation recorded below.
- **Closeout gates**: `make test`, `check-skill-count.py`, `test_check_ccl_regressions.sh --heavy-only`, `npm test`, `npm run test:pack`, private maintainer R0 (`alias_audit_ok` / `r0_status=private-ok` / `ccl_skill_check_clean_ok`), `shared_git_surface_gate.py`, and `tighten-doc` `Tighten` readback across all touched Markdown files verified `exit 0`.

## Dual-Track Review & Challenge Passes

Landing-target base authority verified live via `git ls-remote origin refs/heads/main` (`remote=origin`, `ref=refs/heads/main`, `sha=a151098e21ab29e7a827a58b834c503012ca2eee`, `git rev-list --count HEAD..a151098e21ab29e7a827a58b834c503012ca2eee == 0`). `AC-5` and `Batch 2a` remain `in-review` until PR CI checks pass and the PR merges to `main`.

### Review pass
- Reviewed commit: `4505ba16d7af668ed153de54e699a05893ec9ef4` (`specs/attention-budget-and-suite-speed/evidence/pass1-review.json`, client `claude`)
- Findings: `1` total (`0 P0 / 0 P1 / 1 P2`)
- R0 evidence: `alias_audit_ok` / `ccl_skill_check_clean_ok` (`r0_status=private-ok`, named profiles: `process-retro` + maintainer alias profiles)
- Dispositions: `0` P0/P1 findings; `[P2] specs/ci-gate-npm-slimming/plan.md:14` (`14/14` vs `15/15` mutation count in Batch 2a roadmap row) — **fixed** in `0adaa45afb3a5332d10bff244a1c19cd3d0b04dd`.

### Challenge pass
- Reviewed commit: `4505ba16d7af668ed153de54e699a05893ec9ef4` (`specs/attention-budget-and-suite-speed/evidence/pass2-challenge.json`, client `claude`)
- Findings: `1` total (`0 P0 / 0 P1 / 1 P2`)
- R0 evidence: `alias_audit_ok` / `ccl_skill_check_clean_ok` (`r0_status=private-ok`, named profiles: `process-retro` + maintainer alias profiles)
- Gate-fireability applicability: `yes — change edits shared-gate scripts and size/hygiene rules`; Item 9 exercised: `specs/attention-budget-and-suite-speed/evidence/pass2-challenge.json` (`challenge_focus` + `concern_results[0]` item-9 gate-fireability check)
- Dispositions: `0` P0/P1 findings; `[P2] specs/ci-gate-npm-slimming/plan.md:14` (`14/14` vs `15/15` mutation count in Batch 2a roadmap row) — **fixed** in `0adaa45afb3a5332d10bff244a1c19cd3d0b04dd`.

### Delta pass 1
- Reviewed commit: `0adaa45afb3a5332d10bff244a1c19cd3d0b04dd`; packet: `git diff 4505ba16d7af668ed153de54e699a05893ec9ef4..0adaa45afb3a5332d10bff244a1c19cd3d0b04dd` (`specs/attention-budget-and-suite-speed/evidence/pass3-delta-review.json`, client `claude`)
- Findings / Dispositions: `0` findings (`0 P0 / 0 P1 / 0 P2`); `status=passed`.

### Post-review delta (`0adaa45afb3a5332d10bff244a1c19cd3d0b04dd..HEAD`)
- `specs/attention-budget-and-suite-speed/evidence/pass1-review.json`: controller receipt for Pass 1 (`--mode review`)
- `specs/attention-budget-and-suite-speed/evidence/pass2-challenge.json`: controller receipt for Pass 2 (`--mode challenge`)
- `specs/attention-budget-and-suite-speed/evidence/pass3-delta-review.json`: controller receipt for Delta pass 1 (`--mode review`)
- `specs/attention-budget-and-suite-speed/evidence/validation.md`: pass-disposition log above (non-executable evidence record only)
