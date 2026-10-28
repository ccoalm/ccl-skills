# Validation

## Red baseline

Each new case was run against the code before its fix:

- `scripts/owner-dispatch/test.sh`:
  - on the base engine, `ci` still ran and exited 0;
  - after the subcommand was removed, the actionable-message case failed until the removal message was added.
- `scripts/test_install_gates_runtime.py`:
  - on the base installer, the four installer cases failed, because the installer still wrote `ci_artifact` and emitted the job;
  - the stale-job warning failed on the installer before the warning existed;
  - the nested-include case failed on the fixed-path scan;
  - the quoted and spaced spellings failed on the fixed-string scan;
  - the `ci;` spelling failed on the first regex.

## Commands on the final candidate

Run on `1b01a27`, which adds the prompt change below. `CCL_SKILL_BASE_REF=origin/main` is set explicitly: after the branch is pushed, `check-ccl-skills.sh` otherwise takes the upstream branch as its base, sees the owner packages unchanged, and rejects the register rows. That is a local tracking artifact; CI compares against the pull request base.

| Command | Result |
| --- | --- |
| `CCL_SKILL_BASE_REF=origin/main make test` | `make_test_rc=0` |
| `CCL_SKILL_BASE_REF=origin/main bash skills/skill-extraction-workflow/scripts/test_check_ccl_regressions.sh --heavy-only` | `test_check_ccl_regressions_heavy_only_ok` |
| `python3 scripts/check-public-sanitization.py .` | `public_sanitization_ok` |
| `CCL_SKILL_BASE_REF=origin/main bash skills/skill-extraction-workflow/scripts/check-ccl-skills.sh .` | `ccl_skill_check_clean_ok` (`r0_status=private-ok`) |
| `bash skills/skill-extraction-workflow/scripts/test_obligation_ledger_repo_audit.sh` | `audit_ok domain=50 rows=1240 unresolved=0` (inside `make test`) |

## Reviews

| Pass | File | Result | Disposition |
| --- | --- | --- | --- |
| Review, extraction lane, base `origin/main` | `review.json` | 1 × P1, 5 × P2 | See below. |
| Challenge, extraction lane, base `origin/main` | `challenge.json` | 1 × P1, 1 × P2 | See below. |
| Delta, generic controller, base = the challenged commit | `delta-review-1.json` | 2 × P2 | See below. |
| Delta, generic controller, base `dbf19f0` | `delta-review-2.json` | passed, no findings | Covers the prompt change below. |

Review:

- **P1, both enforced consumers must migrate first.** This is a merge-ordering question, not a defect in the candidate.
  - The service repository has merged its removal.
  - The toolkit repository keeps its own vendored engine and its own rules until it reruns `install-gates`, so this change cannot break it.
  - The remaining condition is operational: do not rerun `install-gates` there before its job is deleted (see Product repositories).
- **P2, a nested include escaped the stale-job scan.** Fixed: every YAML file outside `.git` and `node_modules` is scanned. A nested-include case was added.
- **P2, "build the map" read as the retired map.** That map is the design-time owner map in the design artifact, which the plan keeps. The README now names it that way, and the acceptance text names the committed map file.
- **P2, the backstop rule was too broad.** The rule is narrowed: a backstop must check a property the agent cannot satisfy just by writing a declaration.
- **P2, causal and conflict claims overstated the evidence.**
  - The loads are stated as following the blocks, not as caused by them.
  - The conflict claim is scoped to requests that each append to the shared file.
- **P2, the full lane predated later edits.** Superseded: the table above runs on the final candidate.

Challenge:

- **P1, the same migration prerequisite.** Same disposition as the review P1.
- **P2, quoted and spaced spellings were missed.** Fixed with a pattern match and regression fixtures.

Delta:

- **P2, `ci;` was missed by the first regex.** Fixed. After `ci`, any character that cannot continue a word, or the line end, now matches. The fix is proven by a semicolon fixture that fails on the first regex and passes after. A `ci-report` fixture must stay silent, and does. This fix followed the last reviewer call, so its evidence is the test.
- **P2, the evidence did not cover this delta.** Superseded by the table above.

Prompt change, added after the pull request opened: the engine's PreToolUse prompt no longer says "build the owner-dispatch map". Where a repository configures `ci_artifact`, agents read that phrase as the map file and kept appending to it. `scripts/owner-dispatch/test.sh` asserts the prompt asks only for the owner load and `record`; that case fails on the previous prompt.

## Product repositories

| Repository | Job | State |
| --- | --- | --- |
| Service repository | enforced | Merged: job and per-MR map rule removed, pipeline green. |
| Toolkit repository | enforced | Not started; its remote was unreachable from this machine (TLS connection failure). Delete the job by hand before any `install-gates` rerun. |
| Gateway repository | warn-only | Removal open. A first pipeline failed the repository's AGENTS.md chain budget; the rule text was shortened below its original size, and the local check passes. |
| Orchestrator repository | warn-only | Removal open. Its pipeline fails a dependency scan on an advisory published on 2026-10-27 for a package its main branch already pins. That failure is unrelated to this change, and every merge request there now hits it. |
| 34 others | warn-only | Clean up after this lands, by rerunning `install-gates` or deleting the job. Also remove any repository rule that asks for a map update per merge request. |

Repository rules that ask for a map update in every merge request are what made agents append to the map. They are removed in the same per-repository change as the job.
