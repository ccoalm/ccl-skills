# Batch 2b Validation & Evidence Ledger

Scope note: Batch 2b (`specs/attention-budget-batch-2b/plan.md`, tracked under `specs/ci-gate-npm-slimming/plan.md`) modifies `40` files across `4` upstream owners plus `specs/`. Because `review_gate.py` enforces a `200,000`-byte per-packet ceiling (`skills/code-review/SKILL.md`), independent review and challenge partition those `40` files across `5` complete `--paths` packets (`p1-sew`, `p2-ts`, `p3-mpr`, `p4-tam-plans`, `p5-065-ledger`); each packet covers its partition's content semantics, while repository-wide deterministic gates (`check-size-budget.sh`, `check-ccl-skills.sh`, `make test`, `--heavy-only`, `npm test`, `test:pack`) verify cross-partition invariants on the full tree (`skills/skill-extraction-workflow/references/dual-track-review-gate.md`, *Reviewer verification scope*).

## 1. Attention-Budget Debt Retirement (`check-size-budget.sh` against `58cd1784d643`)

Command: `CCL_SKILL_BASE_REF=origin/main bash skills/skill-extraction-workflow/scripts/check-size-budget.sh .`

| Metric / Target File | Baseline (`58cd1784d643`) | Batch 2b (`HEAD`) | Delta / Outcome |
| --- | --- | --- | --- |
| `reference_line_over_limit_count` | `3` | **`0`** | **`-3`** (`reference_line_budget_blocking_ok`) |
| `entrypoint_size_severe_debt_count` (`> 50,000B`) | `2` | **`1`** | **`-1`** (`entrypoint_size_blocking_ok`) |
| `entrypoint_word_budget_over_limit_count` (`> 5,000w`) | `7` | **`5`** | **`-2`** (`entrypoint_word_budget_blocking_ok`) |
| `skills/skill-extraction-workflow/references/source-to-skill-extraction.md` | `691` lines | **`492` lines** | `-199` lines (split to `backend-data-and-redis-extraction.md` `83L` & `design-and-ledger-extraction.md` `143L`; all `#fragment` headings retained) |
| `skills/test-artifact-management/references/bitable-setup.md` | `573` lines | **`413` lines** | `-160` lines (Steps 8–9 moved to `update-lifecycle.md` `64 -> 243L`) |
| `skills/multi-perspective-research/references/public-data-acquisition.md` | `551` lines | **`481` lines** | `-70` lines (`12/12` `MANIFEST` fenced blocks preserved; pure-prose tail moved to `evidence-controls-and-program-mode.md` `124L`) |
| `skills/testing-strategy/SKILL.md` | `51,410` B / `7,019` words | **`30,679` B / `4,002` words** | `-20,731` B / `-3,017` words (`0` new reference files; all `11` touched `references/*.md` `<= 414L`) |
| `skills/multi-perspective-research/SKILL.md` | `33,377` B / `8,917` words | **`17,774` B / `4,313` words** | `-15,603` B / `-4,604` words |
| `skills/skill-extraction-workflow/SKILL.md` | `113,487` B / `15,554` words | **`113,088` B / `15,418` words** | `-399` B / `-136` words (`entrypoint_word_budget_legacy_ok`) |

## 2. Pre-Implementation RED & Post-Fix GREEN (`T1`–`T4`)

| Register ID | Owner & Suite | Pre-Fix RED Observation | Post-Fix GREEN Observation |
| --- | --- | --- | --- |
| `T1a` | `testing-strategy`: `skills/testing-strategy/scripts/client-terminal-ansi-check.test.sh` | `passed=13 failed=4` (`render/../src/colors.go` exempted `rc=0`, `--allow=..` wildcarded `rc=0`, `--allow=./render` failed `rc=1`, unreadable subdir printed `no source files under directory`) | **`passed=21 failed=0`** (`exit 0`, `-W error` clean) |
| `T1b` | `testing-strategy`: `skills/testing-strategy/scripts/lang-basics-ast-check.test.sh` | `passed=12 failed=3` (`ast.IfExp` ternary fake-success return exited `0`, count `0 != 2`, unreadable subdir printed `no Python files under directory`) | **`passed=17 failed=0`** (`exit 0`, `-W error` clean) |
| `T2` | `skill-extraction-workflow`: `skills/skill-extraction-workflow/scripts/test_governing_chain_diff.sh` | `18 passed, 5 failed` (4-backtick outer fence extracted `1` inner row & dropped post-block row `0 != 1`, `~~~` inside ```` ``` ```` got `0 != 1`, inline ```` ```--force``` ```` got `0 != 1`, poisoned `GIT_DIR` exited `2`) | **`governing-chain-diff: 25 passed, 0 failed`** (`exit 0`) |
| `T3` | `test-artifact-management`: `python3 -m pytest -q skills/test-artifact-management/references/test_gen_report.py` | `3 failed` (`xml.etree.ElementTree.ParseError` crash in `parse_junit` and `collect_results`; un-scrubbed `GIT_DIR` in `_default_author`/`_default_version`) | **`191 passed`** (`exit 0`) |
| `T4` | `multi-perspective-research`: `skills/multi-perspective-research/scripts/test-public-data-acquisition-recipes.sh` + `shellcheck -S warning` | `失败 6` (missing `"exempt"` `MANIFEST` block exited `0`; live symlink `$out` returned `0` `SKIP`; dangling symlink `$out` returned `1`; `pagerun.sh` lacked `$WORKDIR/bin` on `PATH` under system `curl 7.88.1`) | **`通过 49，失败 0` (`public_data_acquisition_recipes_ok`)** + **`shellcheck -S warning` `0` warnings** |

## 3. Applied Differential Killing-Mutation Walk (`M01`–`M18`)

Executed in a disposable `tempfile.TemporaryDirectory` copy with SHA-256 verification of all `10` target files in the worktree before and after (`pre_wt_sha256 == post_wt_sha256`; unmutated controls `rc=0` across all `5` suites):

| Mutant | File & Applied Change | Control | Mutant Result & Verbatim Failing Test / Node ID |
| --- | --- | --- | --- |
| `M01` | `client-terminal-ansi-check.py`: omit `os.path.realpath(path)` in `_path_segments` | `rc=0` (`21/21`) | `rc=1` — `FAIL - --allow=render does NOT exempt render/../src/colors.go traversal` ; `FAIL - --allow=.. exempted ../src/colors.go` ; `FAIL - symlink-parent src/link/../render/colors.go NOT exempted by --allow=src/render` |
| `M02` | `client-terminal-ansi-check.py`: normalize `raw` with `os.path.normpath` in `_allow_segments` | `rc=0` (`21/21`) | `rc=1` — `FAIL - --allow=render/../src does NOT collapse to exempt src/` |
| `M03` | `client-terminal-ansi-check.py`: keep `.` segments in `_allow_segments` | `rc=0` (`21/21`) | `rc=1` — `FAIL - --allow=./render rejected render/ansi.go` |
| `M04` | `client-terminal-ansi-check.py`: check `if not sub:` before `if walk_errs:` | `rc=0` (`21/21`) | `rc=1` — `FAIL - deterministic walk_errs probe` ; `FAIL - unreadable subdir diagnostic` |
| `M05` | `lang-basics-ast-check.py`: remove `isinstance(v, ast.IfExp)` in `_return_hit` | `rc=0` (`17/17`) | `rc=1` — `FAIL - IfExp ternary fake-success dict caught` ; `FAIL - ternary.py count: want 3 got 1` |
| `M06` | `lang-basics-ast-check.py`: remove `isinstance(n, ast.IfExp)` in `_is_fake_dict_node` | `rc=0` (`17/17`) | `rc=1` — `FAIL - constructor-wrapped IfExp ternary fake dict caught` ; `FAIL - ternary.py count: want 3 got 2` |
| `M07` | `lang-basics-ast-check.py`: check `if not sub:` before `if walk_errs:` | `rc=0` (`17/17`) | `rc=1` — `FAIL - deterministic walk_errs probe` ; `FAIL - unreadable subdir diagnostic` |
| `M08` | `governing-chain-diff.py`: hardcode `min_len = 3` on fence closer | `rc=0` (`25/25`) | `rc=1` — `FAIL fence: 4-backtick outer ignores inner 3-backtick prose expected 0 row(s), got 1` ; `FAIL fence: 4-backtick outer with odd inner 3-backtick line expected 1 row(s), got 0` |
| `M09` | `governing-chain-diff.py`: omit `lead_cols <= container_indent + 3` CommonMark indent check | `rc=0` (`25/25`) | `rc=1` — `FAIL fence: 4-space indented delimiter at root is indented code, not fence expected 1 row(s), got 0` |
| `M10` | `governing-chain-diff.py`: omit backtick-in-info-string guard on `_FENCE_OPEN` | `rc=0` (`25/25`) | `rc=1` — `FAIL fence: inline triple-backtick span at line start expected 1 row(s), got 0` |
| `M11` | `governing-chain-diff.py`: omit `"--no-replace-objects"` in `read_rev` | `rc=0` (`25/25`) | `rc=1` — `FAIL git: --rev scrubs GIT_DIR/GIT_CONFIG_PARAMETERS & ignores replace refs` |
| `M12` | `governing-chain-diff.py`: set `env=None` in `read_rev` | `rc=0` (`25/25`) | `rc=1` — `FAIL git: --rev scrubs GIT_DIR/GIT_CONFIG_PARAMETERS & ignores replace refs` |
| `M13` | `gen_report.py`: drop `root_tag not in ("testsuite", "testsuites")` check in `_parse_junit_checked` | `rc=0` (`191/191`) | `rc=1` — `FAILED skills/test-artifact-management/references/test_gen_report.py::test_parse_junit_malformed_xml_returns_empty` |
| `M14` | `gen_report.py`: require `parsed_suites == 0` to preserve `last-run.json` in `_exit_with_gate` | `rc=0` (`191/191`) | `rc=1` — `FAILED skills/test-artifact-management/references/test_gen_report.py::test_collect_results_corrupt_junit_xml_records_infra_missing_and_preserves_baseline` ; `FAILED skills/test-artifact-management/references/test_gen_report.py::test_exit_with_gate_preserves_baseline_on_infra_failure` |
| `M15` | `gen_report.py`: set `env=None` in `_default_author` / `_default_version` | `rc=0` (`191/191`) | `rc=1` — `FAILED skills/test-artifact-management/references/test_gen_report.py::test_default_author_and_version_scrub_poisoned_git_env` |
| `M16` | `public-data-acquisition.md`: remove `[ -L "$out" ]` guard in `fetch()` | `rc=0` (`49/49`) | `rc=1` — `FAIL 目标是有效符号链接返回 2 — 期望 2，实得 1` ; `FAIL 目标是悬空符号链接返回 2 — 期望 2，实得 1` |
| `M17` | `test-public-data-acquisition-recipes.sh`: skip `len(hit) != 1` when `how != "exec"` | `rc=0` (`49/49`) | `rc=1` — `FAIL 块清单能报缺失的已登记豁免块` |
| `M18` | `client-terminal-ansi-check.py`: omit `if not parts: continue` empty-allowlist guard | `rc=0` (`21/21`) | `rc=1` — `FAIL - --allow=. does NOT wildcard src/colors.go` |

## 4. Zero-Loss Obligation-Preservation Verification (`656/656` Rows) & Preservation Walk

Every modified and newly created Markdown file across `skill-extraction-workflow`, `testing-strategy`, `test-artifact-management`, and `multi-perspective-research` was mechanically verified against `origin/main` (`58cd1784d643`) using `governing-chain-diff.py` Checks 1–4 (`carrier_count == 1` across the owning package's `SKILL.md` + `references/*.md`, modal/negation/threshold qualifier parity, exact 1-based destination line and heading locators, `subsumed` vs `rehosted` base-file provenance, and governing-chain verification):

- [`obligation-preservation-sew-tam.md`](obligation-preservation-sew-tam.md): `202/202` rows (`193` `skill-extraction-workflow` + `9` `test-artifact-management`), `carrier_count_all_equal_1=True`.
- [`obligation-preservation-ts.md`](obligation-preservation-ts.md): `231/231` rows (`testing-strategy`), `carrier_count_all_equal_1=True`.
- [`obligation-preservation-mpr.md`](obligation-preservation-mpr.md): `223/223` rows (`multi-perspective-research`), `carrier_count_all_equal_1=True`.
- **Preservation walk & file-axis summary**:
  - Source `(a)` (`source-register.md` `firing-path:`): `52` locators across touched Markdown files walked, `52/52` resolved (`register_firing_path_resolution_ok`).
  - Source `(b)` (repo-wide check/test pin lists: `28` `required_phrase`, `335` `grep -F`/`rg -F`/`has_marker`, `contract-anchors.tsv`, `check-sync-pointers.sh`, `MANIFEST`): all pins verified intact (`ccl_skill_check_clean_ok`).
  - Source `(c)` (cross-file `#fragment` & prose couplings) and `package-file-axis`: `markdown_link_check_ok`, `0` dangling skill-relative links, `0` new orphan support files; historical carrier ledger `specs/065-uiux-evidence-delivery/obligation-mapping.jsonl` and `specs/065-uiux-evidence-delivery/obligation-preservation.md` updated across `14` relocated/consolidated rows and re-rendered (`audit_ok domain=56 rows=1240 unresolved=0`, `test_obligation_ledger_repo_audit_ok`).

## 5. `tighten-doc` Closeout Sweep, Oracle Dimensions & Local Gate Matrix

- **`tighten-doc` pass**: Ran Tighten mode + standalone-paste closeout reread across all `22` touched/new skill & reference Markdown files plus `specs/ci-gate-npm-slimming/plan.md`, `specs/attention-budget-batch-2b/plan.md`, and this validation ledger — verified `0` meta-narration filler, `0` cross-file or intra-bullet duplicate sentences, `0` session-vantage or local-path tokens, and `0` broken `#fragment` or spec links.
- **Oracle dimensions crossed**: `shape` (`.`/`..` and symlink-parent path segments, root & constructor-wrapped `IfExp` AST nodes, 4-backtick / `~~~` / 4-space-root / list-nested / inline fences, truncated/unknown-encoding/non-JUnit XML, live & dangling symlinks), `provenance` (poisoned `GIT_*` env vars, `git replace` refs, external symlink targets), `cardinality` (`0`/`1`/`2` `MANIFEST` block hits, `0` vs `>=1` `parsed_suites` across single and mixed suites), `semantics` (benign near-miss cases preserved across all `5` suites), and `ordering` (`walk_errs` checked before empty-directory fallback; `[ -L "$out" ]` checked before `-e`/`-f`; `_parse_junit_checked` checked before `parsed_suites += 1`).
- **Candidate-bound local gate matrix (`umask 0022`)**:
  - `python3 scripts/select-affected-tests.py --run` -> `passed`
  - `CCL_BROAD_TEST_REASON=repo-required make test` (`test-repo-gates` + `test-regressions-fast` + `test-code-review`) -> `passed`
  - `python3 scripts/check-skill-count.py` -> `skill_count_ok: READMEs agree with skills/ (33)`
  - `bash skills/skill-extraction-workflow/scripts/test_check_ccl_regressions.sh --heavy-only` -> `passed`
  - `CCL_BROAD_TEST_REASON=repo-required npm --prefix packages/ccl-skills-npm test && CCL_BROAD_TEST_REASON=repo-required npm --prefix packages/ccl-skills-npm run test:pack` -> `passed`
  - `bash scripts/test_public_sanitization_leak_cases.sh && bash skills/skill-extraction-workflow/scripts/test_generic_r0_leak_scan.sh` -> `passed`
  - `ALIAS_AUDIT_CMD` via `check-ccl-skills.sh` (`process-retro + 12 alias files`) -> `alias_audit_ok`, `r0_status=private-ok`, `ccl_skill_check_clean_ok`

## 6. Gate & Independent Dual-Track Review Ledger

- **Private R0 audit**: `alias_audit_ok` / `r0_status=private-ok` / `ccl_skill_check_clean_ok`.
- **Boundary acceptance (`extraction_review_gate.sh` across `5` `< 200,000`-byte `--paths` partitions)**: `pending` (recorded upon completion of dual-track review and challenge passes).
