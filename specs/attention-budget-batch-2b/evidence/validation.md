# Batch 2b Validation & Evidence Ledger

Scope note: Batch 2b (`specs/attention-budget-batch-2b/plan.md`, tracked under `specs/ci-gate-npm-slimming/plan.md`) modifies `43` implementation/spec files across `4` upstream owners plus `specs/` (plus recorded review/challenge JSON receipts under `specs/attention-budget-batch-2b/evidence/`). Because `review_gate.py` enforces a `200,000`-byte per-packet ceiling (`skills/code-review/SKILL.md`), initial review, challenge, and oversized delta rounds partition files across `< 200,000`-byte `--paths` packets while bounded whole-worktree deltas run without `--paths`; each packet covers its supplied content semantics, while repository-wide deterministic gates (`check-size-budget.sh`, `check-ccl-skills.sh`, `make test`, `--heavy-only`, `npm test`, `test:pack`) verify cross-partition invariants on the full tree (`skills/skill-extraction-workflow/references/dual-track-review-gate.md`, *Reviewer verification scope*).

## 1. Attention-Budget Debt Retirement (`check-size-budget.sh` against `58cd1784d643`)

Command: `CCL_SKILL_BASE_REF=origin/main bash skills/skill-extraction-workflow/scripts/check-size-budget.sh .`

| Metric / Target File | Baseline (`58cd1784d643`) | Batch 2b (`HEAD`) | Delta / Outcome |
| --- | --- | --- | --- |
| `reference_line_over_limit_count` | `3` | **`0`** | **`-3`** (`reference_line_budget_blocking_ok`) |
| `entrypoint_size_severe_debt_count` (`> 50,000B`) | `2` | **`1`** | **`-1`** (`entrypoint_size_blocking_ok`) |
| `entrypoint_word_budget_over_limit_count` (`> 5,000w`) | `7` | **`5`** | **`-2`** (`entrypoint_word_budget_blocking_ok`) |
| `skills/skill-extraction-workflow/references/source-to-skill-extraction.md` | `691` lines | **`492` lines** | `-199` lines (split to `backend-data-and-redis-extraction.md` `83L` & `design-and-ledger-extraction.md` `143L`; all `#fragment` headings retained) |
| `skills/test-artifact-management/references/bitable-setup.md` | `573` lines | **`413` lines** | `-160` lines (Steps 8–9 moved to `update-lifecycle.md` `64 -> 250L`) |
| `skills/multi-perspective-research/references/public-data-acquisition.md` | `551` lines | **`495` lines** | `-56` lines (`12/12` `MANIFEST` fenced blocks preserved; pure-prose tail moved to `evidence-controls-and-program-mode.md` `124L`; `public-disclosure-channels.md` `99L`) |
| `skills/testing-strategy/SKILL.md` | `51,410` B / `7,019` words | **`31,101` B / `4,060` words** | `-20,309` B / `-2,959` words (`0` new reference files; all `11` touched `references/*.md` `<= 414L`) |
| `skills/multi-perspective-research/SKILL.md` | `33,377` B / `8,917` words | **`17,774` B / `4,313` words** | `-15,603` B / `-4,604` words |
| `skills/skill-extraction-workflow/SKILL.md` | `113,487` B / `15,554` words | **`112,846` B / `15,374` words** | `-641` B / `-180` words (`entrypoint_word_budget_legacy_ok`) |

## 2. Pre-Implementation RED & Post-Fix GREEN (`T1`–`T4`)

| Register ID | Owner & Suite | Pre-Fix RED Observation | Post-Fix GREEN Observation |
| --- | --- | --- | --- |
| `T1a` | `testing-strategy`: `skills/testing-strategy/scripts/client-terminal-ansi-check.test.sh` | `passed=13 failed=4` (initial pre-fix RED: `render/../src/colors.go` exempted `rc=0`, `--allow=..` wildcarded `rc=0`, `--allow=./render` failed `rc=1`, unreadable subdir printed `no source files under directory`; plus challenge/delta regressions for checkout-ancestor `render/`, symlink-parent & symlinked-dir containment, markerless directory & symlinked-directory escaping-symlink containment, markerless `cwd` explicit-file symlink scope, and POSIX literal backslash directory names) | **`passed=36 failed=0`** (`exit 0`, `-B -W error` clean) |
| `T1b` | `testing-strategy`: `skills/testing-strategy/scripts/lang-basics-ast-check.test.sh` | `passed=12 failed=3` (`ast.IfExp` ternary fake-success return exited `0`, count `0 != 2`, unreadable subdir printed `no Python files under directory`) | **`passed=19 failed=0`** (`exit 0`, `-B -W error` clean) |
| `T2` | `skill-extraction-workflow`: `skills/skill-extraction-workflow/scripts/test_governing_chain_diff.sh` | `18 passed, 5 failed` (initial pre-fix RED on `governing-chain-diff.py`: 4-backtick outer fence extracted `1` inner row & dropped post-block row `0 != 1`, `~~~` inside ```` ``` ```` got `0 != 1`, inline ```` ```--force``` ```` got `0 != 1`, poisoned `GIT_DIR` exited `2`; plus challenge/delta regressions for list-nested dedent, `U+00A0`, marker-line fences, 5-space indented code on list-marker lines, list-nested thematic breaks, `GIT_CONFIG_GLOBAL/SYSTEM=/dev/null`, and promisor `GIT_NO_LAZY_FETCH=1` verified with a paired `read_rev` spy control on `git 2.39.5`; `Decision Persistence` routing & substance pinned and mutation-killed via `M38` in `test_ai_coding_implementation_gates.sh`) | **`governing-chain-diff: 32 passed, 0 failed`** (`exit 0`; `test_ai_coding_implementation_gates.sh` `ok`) |
| `T3` | `test-artifact-management`: `python3 -m pytest -q skills/test-artifact-management/references/test_gen_report.py` | `3 failed` (`xml.etree.ElementTree.ParseError` crash in `parse_junit` and `collect_results`; un-scrubbed `GIT_DIR` in `_default_author`/`_default_version`; plus challenge/delta regressions for element- & attribute-namespaced XML, `ValueError` multibyte encodings, minimal-mode and columnar `+record-list` full-Bitable-mode mixed valid+corrupt/namespaced CLI baseline preservation, `matrix_gate: false` `excluded_missing_files` scope, and Step 9 batch `信息流转` preflight) | **`193 passed`** (`exit 0`) |
| `T4` | `multi-perspective-research`: `skills/multi-perspective-research/scripts/test-public-data-acquisition-recipes.sh` + `shellcheck -S warning` | `失败 6` (missing/co-deleted `"exempt"` `MANIFEST` block exited `0`; pre-existing leaf symlinks bypassed `return 2` (`accept` read target MIME -> `rc=0` `SKIP` on JSON target or `rc=1` on mismatch, and `ln` failed `rc=1` on dangling symlinks); intermediate parent symlink returned `0` `SKIP` / wrote outside `$OUT`; `pagerun.sh` lacked `$WORKDIR/bin` on `PATH` under system `curl 7.88.1`; plus delta regressions for `CDPATH`-sensitive `OUT=data`, `set -u` unset/empty `OUT`, `OUT=./data` with `data/`, tilde/indented/quoted/bullet-marker/ordered-marker/list-continuation/dedent-closed unregistered fences, 4+-space & paragraph-wrapped `100.` indented-code controls, and publication-entry directory & directory-symlink collisions) | **`通过 88，失败 0` (`public_data_acquisition_recipes_ok`)** + **`shellcheck -S warning` `0` warnings** (after the §3b carrier-format replacement; `78/78` at the prior candidate) |

## 3. Applied Differential Killing-Mutation Walk (`M01`–`M42`)

Executed in a disposable `tempfile.TemporaryDirectory` copy with SHA-256 verification of all `13` target files in the worktree before and after (unmutated controls `rc=0` across all `6` suites: `client-terminal-ansi-check.test.sh` `36/36`, `lang-basics-ast-check.test.sh` `19/19`, `test_governing_chain_diff.sh` `32/32`, `test_ai_coding_implementation_gates.sh` `ok`, `test_gen_report.py` `193/193`, `test-public-data-acquisition-recipes.sh` `78/78`):

| Mutant | File & Applied Change | Control | Mutant Result & Verbatim Failing Test / Node ID |
| --- | --- | --- | --- |
| `M01` | `client-terminal-ansi-check.py`: replace `os.path.realpath(path)` with `os.path.abspath(path)` in `_rel_segments` | `rc=0` (`36/36`) | `rc=1` — `FAIL - symlink render/link_to_src.go -> ../src/colors.go NOT exempted by --allow=render` ; `FAIL - symlink render/ext_link.go escaping checkout NOT exempted by --allow=render` ; `FAIL - markerless symlink render/nested/escape.go -> ../../src/colors.go NOT exempted` |
| `M02` | `client-terminal-ansi-check.py`: normalize `raw` with `os.path.normpath` in `_allow_segments` | `rc=0` (`36/36`) | `rc=1` — `FAIL - --allow=render/../src does NOT collapse to exempt src/` |
| `M03` | `client-terminal-ansi-check.py`: keep `.` segments in `_allow_segments` | `rc=0` (`36/36`) | `rc=1` — `FAIL - --allow=./render rejected render/ansi.go` |
| `M04` | `client-terminal-ansi-check.py`: check `if not sub:` before `if walk_errs:` | `rc=0` (`36/36`) | `rc=1` — `FAIL - deterministic walk_errs probe` ; `FAIL - unreadable subdir diagnostic` |
| `M05` | `lang-basics-ast-check.py`: remove `isinstance(v, ast.IfExp)` in `_return_hit` | `rc=0` (`19/19`) | `rc=1` — `FAIL - IfExp ternary fake-success dict caught` ; `FAIL - ternary.py count: want 4 got 2` |
| `M06` | `lang-basics-ast-check.py`: omit `orelse` branch in `_is_fake_dict_node` | `rc=0` (`19/19`) | `rc=1` — `FAIL - constructor-wrapped IfExp false-branch fake dict caught` ; `FAIL - ternary.py count: want 4 got 3` |
| `M07` | `lang-basics-ast-check.py`: check `if not sub:` before `if walk_errs:` | `rc=0` (`19/19`) | `rc=1` — `FAIL - deterministic walk_errs probe` ; `FAIL - unreadable subdir diagnostic` |
| `M08` | `governing-chain-diff.py`: hardcode `min_len = 3` on fence closer | `rc=0` (`32/32`) | `rc=1` — `FAIL fence: 4-backtick outer ignores inner 3-backtick prose expected 0 row(s), got 1` ; `FAIL fence: 4-backtick outer with odd inner 3-backtick line expected 1 row(s), got 0` |
| `M09` | `governing-chain-diff.py`: omit `lead_cols <= container_indent + 3` CommonMark indent check | `rc=0` (`32/32`) | `rc=1` — `FAIL fence: 4-space indented delimiter at root is indented code, not fence expected 1 row(s), got 0` |
| `M10` | `governing-chain-diff.py`: omit backtick-in-info-string guard on `_FENCE_OPEN` | `rc=0` (`32/32`) | `rc=1` — `FAIL fence: inline triple-backtick span at line start expected 1 row(s), got 0` |
| `M11` | `governing-chain-diff.py`: omit `"--no-replace-objects"` in `read_rev` | `rc=0` (`32/32`) | `rc=1` — `FAIL git: --rev isolates XDG/HOME, scrubs GIT_* (incl. GIT_TRACE), & ignores replace refs` |
| `M12` | `governing-chain-diff.py`: set `env=None` in `read_rev` | `rc=0` (`32/32`) | `rc=1` — `FAIL git: --rev isolates XDG/HOME, scrubs GIT_* (incl. GIT_TRACE), & ignores replace refs` ; `FAIL git: --rev enforces GIT_NO_LAZY_FETCH=1 on promisor missing blobs` |
| `M13` | `gen_report.py`: drop `root.tag not in ("testsuite", "testsuites")` check in `_parse_junit_checked` | `rc=0` (`193/193`) | `rc=1` — `FAILED skills/test-artifact-management/references/test_gen_report.py::test_parse_junit_malformed_xml_returns_empty` |
| `M14` | `gen_report.py`: require `parsed_suites == 0` to preserve `last-run.json` in `_exit_with_gate` | `rc=0` (`193/193`) | `rc=1` — `FAILED skills/test-artifact-management/references/test_gen_report.py::test_collect_results_corrupt_junit_xml_records_infra_missing_and_preserves_baseline` ; `FAILED skills/test-artifact-management/references/test_gen_report.py::test_full_bitable_mode_mixed_corrupt_xml_default_fail_on_preserves_baseline` ; `FAILED skills/test-artifact-management/references/test_gen_report.py::test_exit_with_gate_preserves_baseline_on_infra_failure` |
| `M15` | `gen_report.py`: set `env=None` in `_default_author` / `_default_version` | `rc=0` (`193/193`) | `rc=1` — `FAILED skills/test-artifact-management/references/test_gen_report.py::test_collect_results_corrupt_junit_xml_records_infra_missing_and_preserves_baseline` ; `FAILED skills/test-artifact-management/references/test_gen_report.py::test_full_bitable_mode_mixed_corrupt_xml_default_fail_on_preserves_baseline` ; `FAILED skills/test-artifact-management/references/test_gen_report.py::test_default_author_and_version_scrub_poisoned_git_env` |
| `M16` | `public-data-acquisition.md`: remove `[ ! -L "$out" ]` guard in `fetch()` | `rc=0` (`78/78`) | `rc=1` — `FAIL 目标是有效符号链接返回 2 — 期望 2，实得 1` |
| `M17` | `test-public-data-acquisition-recipes.sh`: skip `len(hit_idxs) != 1` when `how != "exec"` | `rc=0` (`78/78`) | `rc=1` — `FAIL 块清单能报缺失的已登记豁免块` |
| `M18` | `client-terminal-ansi-check.py`: omit `if not parts: continue` empty-allowlist guard | `rc=0` (`36/36`) | `rc=1` — `FAIL - --allow=. does NOT wildcard src/colors.go` |
| `M19` | `client-terminal-ansi-check.py`: match `real_file` instead of `os.path.relpath(real_file, segment_root)` | `rc=0` (`36/36`) | `rc=1` — `FAIL - ancestor render/ exempted relative src/colors.go` ; `FAIL - ancestor render/ does NOT exempt checkout/src/colors.go` ; `FAIL - symlink render/link_to_src.go -> ../src/colors.go NOT exempted by --allow=render` |
| `M20` | `governing-chain-diff.py`: disable `raw_lead_cols < fence_container_indent` dedent closure | `rc=0` (`32/32`) | `rc=1` — `FAIL fence: unclosed list-nested fence ends on dedent to root rule expected 1 row(s), got 0` |
| `M21` | `gen_report.py`: strip root namespace instead of rejecting namespaced XML in `_parse_junit_checked` | `rc=0` (`193/193`) | `rc=1` — `FAILED skills/test-artifact-management/references/test_gen_report.py::test_parse_junit_malformed_xml_returns_empty` ; `FAILED skills/test-artifact-management/references/test_gen_report.py::test_collect_results_corrupt_junit_xml_records_infra_missing_and_preserves_baseline` ; `FAILED skills/test-artifact-management/references/test_gen_report.py::test_full_bitable_mode_mixed_corrupt_xml_default_fail_on_preserves_baseline` |
| `M22` | `gen_report.py`: drop `ValueError` from `_parse_junit_checked` exception tuple | `rc=0` (`193/193`) | `rc=1` — `FAILED skills/test-artifact-management/references/test_gen_report.py::test_parse_junit_malformed_xml_returns_empty` |
| `M23` | `update-lifecycle.md`: remove `direct_log_ids` preflight check in Step 9 batch upsert | `rc=0` (`193/193`) | `rc=1` — `FAILED skills/test-artifact-management/references/test_gen_report.py::test_update_lifecycle_rmw_recipes_reject_direct_info_log_and_missing_ids` |
| `M24` | `public-data-acquisition.md`: omit `$real_out` canonical containment check in `fetch()` | `rc=0` (`78/78`) | `rc=1` — `FAIL 越出 OUT 的路径返回 2 — 期望 2，实得 0` ; `FAIL 越出 OUT 的路径未写文件 — 期望 absent，实得 created` |
| `M25` | `governing-chain-diff.py`: use `raw.strip()` instead of `raw.strip(" \t\r")` in `_is_blank_line` | `rc=0` (`32/32`) | `rc=1` — `FAIL fence: column-0 NBSP line is non-blank and closes unclosed list fence expected 1 row(s), got 0` |
| `M26` | `governing-chain-diff.py`: omit `clean["GIT_NO_LAZY_FETCH"] = "1"` in `_git_clean_env` | `rc=0` (`32/32`) | `rc=1` — `FAIL git: _git_clean_env sets GIT_NO_LAZY_FETCH=1 & GIT_CONFIG_GLOBAL/SYSTEM=/dev/null` ; `FAIL git: --rev enforces GIT_NO_LAZY_FETCH=1 on promisor missing blobs` |
| `M27` | `update-lifecycle.md`: remove `missing_ids` preflight check in Step 9 batch upsert | `rc=0` (`193/193`) | `rc=1` — `FAILED skills/test-artifact-management/references/test_gen_report.py::test_update_lifecycle_rmw_recipes_reject_direct_info_log_and_missing_ids` |
| `M28` | `test-public-data-acquisition-recipes.sh`: allow empty `expected_ids` in `check-block-manifest.py` | `rc=0` (`78/78`) | `rc=1` — `FAIL 块清单缺少独立基线时必须失败` |
| `M29` | `client-terminal-ansi-check.py`: resolve `os.path.realpath(arg)` before `_lexical_anchor_dir(arg)` on directory args | `rc=0` (`36/36`) | `rc=1` — `FAIL - absolute symlinked directory checkout/ext_dir_link NOT exempted by --allow=render` |
| `M30` | `governing-chain-diff.py`: omit CommonMark §5.2 Rule 2 `first_content_col - marker_base > 3` indented-code padding bound | `rc=0` (`32/32`) | `rc=1` — `FAIL fence: 5-space indented code on list-marker line keeps content_indent at marker+1 expected 1 row(s), got 0` |
| `M31` | `governing-chain-diff.py`: omit `clean["GIT_CONFIG_GLOBAL"] = os.devnull` in `_git_clean_env` | `rc=0` (`32/32`) | `rc=1` — `FAIL git: _git_clean_env sets GIT_NO_LAZY_FETCH=1 & GIT_CONFIG_GLOBAL/SYSTEM=/dev/null` ; `FAIL git: --rev isolates XDG/HOME, scrubs GIT_* (incl. GIT_TRACE), & ignores replace refs` |
| `M32` | `gen_report.py`: drop attribute-namespace `any("{" in k for k in el.attrib)` check in `_parse_junit_checked` | `rc=0` (`193/193`) | `rc=1` — `FAILED skills/test-artifact-management/references/test_gen_report.py::test_parse_junit_malformed_xml_returns_empty` ; `FAILED skills/test-artifact-management/references/test_gen_report.py::test_collect_results_corrupt_junit_xml_records_infra_missing_and_preserves_baseline` ; `FAILED skills/test-artifact-management/references/test_gen_report.py::test_full_bitable_mode_mixed_corrupt_xml_default_fail_on_preserves_baseline` |
| `M33` | `client-terminal-ansi-check.py`: set `containment_roots = (os.path.abspath(os.sep),)` on markerless directory args | `rc=0` (`36/36`) | `rc=1` — `FAIL - markerless directory scan does NOT exempt escaping symlink to sibling render/` ; `FAIL - symlinked markerless directory scan does NOT exempt symlink escaping scanned dir` |
| `M34` | `public-data-acquisition.md`: revert atomic `python3` `os.link` publish to guarded `if [ ! -e "$out" ] && [ ! -L "$out" ] && ln -- "$part" "$out"` in `fetch()` | `rc=0` (`78/78`) | `rc=1` — `FAIL 链接边界目标变为目录时返回 2 且 FETCHED=0 — 期望 2:0，实得 0:1` ; `FAIL 链接边界新建目录内未被链入 .part — 期望 0，实得 1` ; `FAIL 链接边界目标变为目录符号链接时返回 2 且 FETCHED=0 — 期望 2:0，实得 0:1` ; `FAIL 链接边界目录符号链接目标未被链入 .part — 期望 0，实得 1` |
| `M35` | `public-data-acquisition.md`: omit `CDPATH=''` on `cd -P -- "$eff_out"` in `fetch()` | `rc=0` (`78/78`) | `rc=1` — `FAIL CDPATH 工作目录写入 bare.json — 期望 present，实得 missing` ; `FAIL CDPATH 诱饵目录未被写入 — 期望 clean，实得 leaked` |
| `M36` | `governing-chain-diff.py`: call `list_stack.clear()` unconditionally on `_THEMATIC_BREAK` | `rc=0` (`32/32`) | `rc=1` — `FAIL fence: list-nested thematic break retains enclosing list for unclosed fence dedent expected 1 row(s), got 0` |
| `M37` | `client-terminal-ansi-check.py`: omit `os.path.realpath(arg)` from `containment_roots` on markerless directory args (`containment_roots = (anchor_dir,)`) | `rc=0` (`36/36`) | `rc=1` — `FAIL - symlinked markerless directory scan does NOT exempt symlink escaping scanned dir` |
| `M38` | `design-and-ledger-extraction.md`: remove `Decision Persistence` durable-trace bullet (`retain rule origin, source IDs read before drafting, and concrete observations`) | `rc=0` (`ok`) | `rc=1` — `FAIL: ledger split (substance: Decision Persistence retains rule origin, pre-draft source IDs, and observations)` |
| `M39` | `test-public-data-acquisition-recipes.sh`: omit cross-line list-container tracking (`containers.append(['list', _cind_rel, False])`) in `check-block-manifest.py` | `rc=0` (`78/78`) | `rc=1` — `FAIL 块清单能报有序列表续行未登记代码块` ; `FAIL 块清单能报缩进回退闭合的列表代码块` **Retired by §3b**: the mutated CommonMark container code was deleted. |
| `M40` | `gen_report.py`: record `matrix_gate: false` invalid JUnit XML in `missing_files` instead of `excluded_missing_files` | `rc=0` (`193/193`) | `rc=1` — `FAILED skills/test-artifact-management/references/test_gen_report.py::test_collect_results_corrupt_junit_xml_records_infra_missing_and_preserves_baseline` |
| `M41` | `test-public-data-acquisition-recipes.sh`: advance post-marker padding from `_rem` instead of `_rem[_mi.start(3):]` at `_mcol_end` in `check-block-manifest.py` | `rc=0` (`78/78`) | `rc=1` — `FAIL 块清单能报列表标记行未登记代码块` ; `FAIL 块清单能报有序列表标记行未登记代码块` **Retired by §3b**: the mutated CommonMark container code was deleted. |
| `M42` | `test-public-data-acquisition-recipes.sh`: disable CommonMark §5.2 `_in_para` list-interruption guard (`int(_mnum) != 1` / empty marker) in `check-block-manifest.py` | `rc=0` (`78/78`) | `rc=1` — `FAIL 块清单不误报 4+ 空格缩进代码块` **Retired by §3b**: the mutated CommonMark container code was deleted. |

## 3b. Carrier-Format Replacement of the Fence Scanner (`recurring-class-decision: replace`)

Every review round from the original challenge through delta pass 6 reported a new same-class misparse in the hand-written CommonMark container scanner. The final round's HTML-comment counterexample exited `0` with the fence missing from the inventory. The scanner now decodes with `utf-8-sig` (a renderer skips a leading BOM) and splits lines on LF only, which matches CommonMark line endings once `open()` has normalised CR and CRLF. It enumerates only column-0 root fences and fails closed on:

- every other fence-like line, after stripping blockquote, list-marker and whitespace prefixes;
- any fence-like line inside a root fence body that is not its closer;
- any unclosed root fence.

The decision record is the last `multi-perspective-research` row of `skills/skill-extraction-workflow/references/source-register.md`.

- **Pre-fix RED**:
  - Scanner: the prior scanner, given the document plus `<!-- note -->` / `100. Instructions` / a five-space `bash` fence, printed `块清单：共 12 个` and exited `rc=0`. It did the same with the tab-indented heading near miss. The replacement exits `rc=1` with `承载文档格式不合规` and names the offending line in both cases and in a comment-swallowed phantom fence.
  - Suite: the tab-heading case was fed to `layout_case` through a pipe, so its result counter was lost in a subshell. Row `N8-baseline` shows that form exiting `rc=0` while printing a `FAIL`. The case now reads its input through process substitution.
  - Decoding: with plain `utf-8`, a carrier that starts with a BOM followed by a tilde fence kept the original inventory, so the fence the renderer opens was missed (row `N9`).
- **Post-fix** (candidate after the review and challenge fixes): `test-public-data-acquisition-recipes.sh` `通过 88，失败 0`; `shellcheck -S warning` clean.
- **Review-pass dispositions**:
  - The review of the first replacement commit returned P1 U+2028 line splitting (fixed, `N7`) and P1 the pipe-subshell counter loss (fixed, `N8`). Its two P2s asked for a verbatim mutant log, the block inventory and candidate-bound lane results. They are addressed by this section and by the §5 lane rows.
  - The challenge of the fixed candidate returned P1 the leading-BOM opener (fixed, `N9`) and two P2s about context missing from the packet. Source check: `bad()` increments `fail` in the parent shell, and the suite ends with `[ "$fail" -eq 0 ] || exit 1`. `N8` shows a single failed layout case moving the top-level exit to `rc=1`. The manifest predicates and the exactly-one-claim check are unchanged from `5f25afc`, and the real carrier still yields the 12 blocks listed below. Dispositioned as verified from source; no code change.
  - The incremental re-review of the challenge fixes (`8c21532..1833460`) returned no P0/P1 and four P2s, all accepted:
    - The BOM fixture depended on the carrier having no longer tilde closer. It is now self-contained.
    - A carrier-prefixed closed-but-unregistered BOM fixture was added, and `N9` now fails both BOM assertions.
    - The lane rows below are bound to the final candidate.
    - The replacement-decision row is restored to its earlier text, and the BOM fix is appended as a follow-up row, keeping the register append-only.
  - These fixes are test-fixture and record changes only, proven by the suite and the mutant walk. No further external pass is owed.
- **Real carrier inventory**: `public-data-acquisition.md` has no layout errors and yields these 12 blocks, each claimed by exactly one `MANIFEST` entry:

1. `bash` — `UA="<项目或用途> <联系邮箱>"` (`fetch/accept`)
2. no info string — `$ curl -s --show-error --max-filesize 1K …` (`curl-size-log`)
3. no info string — `$ curl -s -o data.json "<当时返回 504 的接口>" ; echo $?` (`curl-fail-log`)
4. `bash` — `# 快照清单：目标 URL 与各参数都由 curl 编码` (`cdx`)
5. `bash` — `# 注意单引号：URL 里的 $ 不能进双引号…` (`catalog`)
6. `bash` — `# 取数据集本身：$limit 只是"这一页多少行"，必须自己翻页` (`paging`)
7. `python` — `# 跨年取同一语义字段：列名会改，先过别名表，再判缺` (`alias-parse`)
8. `bash` — `# 启发式探针：目标页能抽出多少非空白字符` (`pdf-probe`)
9. `bash` — `# MediaBox 可以很大…` (`pdf-render`)
10. `swift` — `// swiftc -O -o ocr ocr.swift …` (`ocr`)
11. `javascript` — `const TAGS = ['<PreferredTag>', …` (`tag-fallback`)
12. `python` — `totA = sum(v[0] for v in rows.values())` (`col-attrib`)

- **Applied differential mutants**: each mutant was applied to a temporary copy of the suite next to the original. Each turned only its owning assertions RED. Under `N1` the comment-swallow and nested-tilde cases are still rejected by the unregistered-block layer, and `N3` owns them. Verbatim runner output:

```text
control: rc=0 ['通过 88，失败 0'] fails=[]
N1 drop sys.exit(1) after layout errors: rc=1 ['通过 78，失败 10'] fails=['块清单拒绝 1-3 空格缩进的 fence', '块清单拒绝引用块内 fence', '块清单拒绝列表标记行 fence', '块清单拒绝有序列表标记行 fence', '块清单拒绝有序列表续行 fence', '块清单拒绝缩进回退才闭合的列表 fence', '块清单拒绝 4 空格根级缩进的类 fence 行', '块清单拒绝 HTML 注释后列表续行 fence', '块清单拒绝制表符标题近似后的缩进 fence', '块清单拒绝未闭合的根级 fence']
N2 _fence_like skips container-prefix strip: rc=1 ['通过 79，失败 9'] fails=['块清单拒绝 1-3 空格缩进的 fence', '块清单拒绝引用块内 fence', '块清单拒绝列表标记行 fence', '块清单拒绝有序列表标记行 fence', '块清单拒绝有序列表续行 fence', '块清单拒绝缩进回退才闭合的列表 fence', '块清单拒绝 4 空格根级缩进的类 fence 行', '块清单拒绝 HTML 注释后列表续行 fence', '块清单拒绝制表符标题近似后的缩进 fence']
N3 disable nested check in fence body: rc=1 ['通过 85，失败 3'] fails=['块清单不在 U+2028 处断行', '块清单拒绝根级 fence 体内的嵌套开头行', '块清单拒绝反引号 fence 体内的波浪线 fence']
N4 disable unclosed-fence error: rc=1 ['通过 86，失败 2'] fails=['块清单识别 BOM 后的首行 fence', '块清单拒绝未闭合的根级 fence']
N5 drop backtick-in-info inline-span exclusion: rc=1 ['通过 87，失败 1'] fails=['块清单不把行首行内代码当 fence']
N6 drop > from container prefix: rc=1 ['通过 87，失败 1'] fails=['块清单拒绝引用块内 fence']
N7 split lines with str.splitlines(): rc=1 ['通过 87，失败 1'] fails=['块清单不在 U+2028 处断行']
N8 break only the tab-heading needle (process substitution): rc=1 ['通过 87，失败 1'] fails=['块清单拒绝制表符标题近似后的缩进 fence']
N8-baseline same break under the old pipe form: rc=0 ['通过 87，失败 0'] fails=['块清单拒绝制表符标题近似后的缩进 fence']
N9 decode with utf-8 instead of utf-8-sig: rc=1 ['通过 86，失败 2'] fails=['块清单识别 BOM 后的首行 fence', '块清单报 BOM 后已闭合的未登记 fence']
```

## 4. Obligation-Preservation Ledger (`678/678` Derived Rows) & Preservation Walk

Every modified and newly created Markdown file across `skill-extraction-workflow`, `testing-strategy`, `test-artifact-management`, and `multi-perspective-research` was mechanically verified from `origin/main` (`58cd1784d643b92bd4e7a0e417e747d60208d2d1`) against the Batch 2b worktree using `governing-chain-diff.py` Checks 1–4 (`carrier_count == 1` across the owning package's `SKILL.md` + `references/*.md`, modal/negation/threshold qualifier parity, exact 1-based destination line and heading locators, `subsumed` vs `rehosted` base-file provenance, and governing-chain verification); semantic equivalence of consolidated/rehosted prose is covered alongside the mechanical locator checks through the bounded review packets:

- [`obligation-preservation-sew-tam.md`](obligation-preservation-sew-tam.md): `213/213` rows (`204` `skill-extraction-workflow` + `9` `test-artifact-management`), `carrier_count_all_equal_1=True`.
- [`obligation-preservation-ts.md`](obligation-preservation-ts.md): `229/229` rows (`testing-strategy`), `carrier_count_all_equal_1=True`.
- [`obligation-preservation-mpr.md`](obligation-preservation-mpr.md): `236/236` rows (`multi-perspective-research`), `carrier_count_all_equal_1=True`.
- **Preservation walk & file-axis summary**:
  - Source `(a)` (`source-register.md` `firing-path:`): `55` locators across touched Markdown files walked, `55/55` resolved (`register_firing_path_resolution_ok`).
  - Source `(b)` (repo-wide check/test pin lists: `28` `required_phrase`, `335` `grep -F`/`rg -F`/`has_marker`, `contract-anchors.tsv`, `check-sync-pointers.sh`, `MANIFEST`): all pins verified intact (`ccl_skill_check_clean_ok`).
  - Source `(c)` (cross-file `#fragment` & prose couplings) and `package-file-axis`: `markdown_link_check_ok`, `0` dangling skill-relative links, `0` new orphan support files; historical carrier ledger `specs/065-uiux-evidence-delivery/obligation-mapping.jsonl` and `specs/065-uiux-evidence-delivery/obligation-preservation.md` updated across `14` relocated/consolidated rows and re-rendered (`audit_ok domain=56 rows=1240 unresolved=0`, `test_obligation_ledger_repo_audit_ok`).

## 5. `tighten-doc` Closeout Sweep, Oracle Dimensions & Local Gate Matrix

- **`tighten-doc` pass**: Ran Tighten mode + standalone-paste closeout reread across all `23` touched/new skill & reference Markdown files plus `specs/ci-gate-npm-slimming/plan.md`, `specs/attention-budget-batch-2b/plan.md`, and this validation ledger — verified `0` meta-narration filler, `0` cross-file or intra-bullet duplicate sentences, `0` session-vantage or local-path tokens, and `0` broken `#fragment` or spec links.
- **Oracle dimensions crossed**: `shape` (`.`/`..`, symlink, and ancestor-`render` path segments, root & constructor-wrapped true/false-branch `IfExp` AST nodes, 4-backtick / `~~~` / 4-space-root / closed & unclosed list-nested / inline fences, truncated/unknown-encoding/`ValueError`/namespaced/non-JUnit XML, direct `信息流转` batch keys, leaf & intermediate-parent symlinks and outside-`$OUT` paths), `provenance` (poisoned `GIT_*` / `GIT_TRACE` / `XDG_CONFIG_HOME` env vars, `git replace` refs, external symlink targets), `cardinality` (`0`/`1`/`2` `MANIFEST` block hits & co-deleted inventory check, `0` vs `>=1` `parsed_suites` across single and mixed suites in minimal and full Bitable modes), `semantics` (benign near-miss cases preserved across all `5` suites), and `ordering` (`walk_errs` checked before empty-directory fallback; `[ -L ]` & `pwd -P` `$OUT` containment checked before `-e`/`-f`/staging; `_parse_junit_checked` checked before `parsed_suites += 1`; Step 9 direct-`信息流转` preflight checked before writes).
- **Candidate-bound local gate matrix (`umask 0022`)**:
  - `python3 scripts/select-affected-tests.py --run` -> `passed`
  - `CCL_BROAD_TEST_REASON=repo-required make test` (`test-repo-gates` + `test-regressions-fast` + `test-code-review`) -> `passed`
  - `python3 scripts/check-skill-count.py` -> `skill_count_ok: READMEs agree with skills/ (33)`
  - `bash skills/skill-extraction-workflow/scripts/test_check_ccl_regressions.sh --heavy-only` -> `passed`
  - `CCL_BROAD_TEST_REASON=repo-required npm --prefix packages/ccl-skills-npm test && CCL_BROAD_TEST_REASON=repo-required npm --prefix packages/ccl-skills-npm run test:pack` -> `passed`
  - `bash scripts/test_public_sanitization_leak_cases.sh && bash skills/skill-extraction-workflow/scripts/test_check_evidence_card_leak_cache.sh && bash skills/skill-extraction-workflow/scripts/test_generic_r0_leak_scan.sh` -> `passed`
  - `ALIAS_AUDIT_CMD` via `check-ccl-skills.sh` (`process-retro + 12 alias files`) -> `alias_audit_ok`, `r0_status=private-ok`, `ccl_skill_check_clean_ok`

## 6. Gate & Independent Dual-Track Review Ledger

- **Private R0 audit**: `alias_audit_ok` / `r0_status=private-ok` / `ccl_skill_check_clean_ok`.
- **Boundary acceptance (`extraction_review_gate.sh` across `< 200,000`-byte `--paths` partitions)**: `pending` (recorded upon completion of review, challenge, and delta passes).
