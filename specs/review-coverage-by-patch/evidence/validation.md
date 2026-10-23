# Validation

Candidate: branch `fix/review-coverage-by-patch` from `origin/main` 20c7102.

## RED baseline

Acceptance probes were added to `hooks/test_remind_review_covers_head.sh`
before the hook changed. Against the unchanged hook, A1 (clean merge of the
target) and A3 (same-patch rebase) reminded where quiet is required, and A6
(clean merge-in, receipt `findings`) gave the "not covered" message instead of
the findings message. The author-change probes reminded, as required.

## GREEN

Final predicate (three `diff-tree` comparisons against the remote default
branch, see the plan): 62 passed, 0 failed.

| ID | Scenario | Result |
| --- | --- | --- |
| A1 | clean merge of the target | quiet |
| A3 | same-patch rebase | quiet |
| A17 control | reviewed block replayed in place | quiet |
| A20 | reviewed patch with trailing spaces, `apply.whitespace=error` | quiet |
| A26 | same-patch replay checked from a subdirectory | quiet |
| A6 | clean merge-in, findings receipt | findings reminder |
| A15 | merge driver, textconv, external diff and `post-index-change` hook configured | quiet, none ran |
| A14 | no remote default branch | remind |
| A19 | partial clone | remind |
| A22 | promisor remote without the partial-clone extension | remind |
| A2 | merge commit carrying an edit | remind |
| A12 | another author branch merged in | remind |
| A5 | rebase plus an extra commit | remind |
| A11 | unreviewed commit below the replayed patch | remind |
| A4 | amended patch | remind |
| A7 | whitespace-only amend | remind |
| A13 | gitlink hidden by `diff.ignoreSubmodules=all` | remind |
| A16 | change outside a `diff.relative` view, run from a subdirectory | remind |
| A17 | same edit moved to a look-alike block | remind |
| A18 | A17 under `diff.context=0` | remind |
| A21 | target rewrote the reviewed block; HEAD edits the look-alike block | remind |
| A25 | A21 run from a subdirectory with `diff.relative` | remind |
| A23 | target changed the same file elsewhere (stricter than Gerrit) | remind |
| A24 | nested edit moved to a same-named root file under `diff.noprefix` | remind |
| A27 | merge keeps the reviewed file and drops the target's change to it | remind |
| A28 | glob-like reviewed file name next to an unreviewed change | remind |
| A29 | bracketed reviewed file name whose reviewed change an amend dropped | remind |
| A9 | same patch on an unrelated root (fixture setup fatal on failure) | remind |
| A8 | merge with a resolved conflict | remind |
| A10 | merge committed with conflict markers | remind |

## Applied mutations

Each mutant ran the full suite in a scratch copy, never the worktree.

| Mutation | Result |
| --- | --- |
| drop condition 1 (target unchanged on reviewed paths) | RED: A27 |
| drop condition 2 (HEAD equals reviewed on reviewed paths) | RED: A2, A4, A7, A17, A18 |
| drop condition 3 (HEAD equals target elsewhere) | RED: A5, A11, A12, A13, A16 |
| drop the promisor / partial-clone check | RED: A19, A22 |
| base from the reviewed side, or fork from the HEAD side | RED: A1, A3, A6, A15, A17 control, A20, A26 |
| target from `HEAD~1` | RED: A1, A6, A15, A11 |
| drop the empty path-list guard | GREEN → deleted: with no reviewed paths the conditions require HEAD to equal the target |
| drop `literal` pathspec magic | GREEN on git 2.50 (pathspecs also match the name literally, A28 and A29 still remind) → kept as an explicit constraint, not counted as verified |

Earlier designs' mutation results are superseded; their findings are listed below.

## Review findings and dispositions

First review (codex, 6 findings) on the `merge-tree` design:

- P1 target not bound, a commit below the replay escapes → design replaced; A11, A12, A14.
- P1 `merge-tree` runs repository merge drivers → removed; A15.
- P2 submodule changes hidden by config → A13, A16.
- P2 `cherry-pick -q` unsupported, A9 setup could silently fail → fixture steps fatal.
- P2 64-step boundary → walk removed.
- P2 evidence not candidate-bound → lanes below.

Challenge (codex, 2 findings) on the patch-id design:

- P1 patch-id ignores line numbers → replaced; A17, A18.
- P1 partial clone lazy fetch → never exempt; A19.

Delta pass 1 (3 findings) on the replay design:

- P1 offset matching after the target rewrote the reviewed block → path-disjoint condition; A21, A23.
- P1 promisor remotes without the extension → never exempt; A22.
- P2 lanes → below.

Delta pass 2 (4 findings):

- P1 `diff.noprefix` stripped a real path component → A24.
- P1 disjoint check honoured `diff.relative` → A25, A26.
- P2 A23 contradicts clean-integration coverage → not adopted; the narrowing is deliberate (plan, review-plan acceptance).
- P2 lanes → below.

Delta pass 3 (3 findings):

- P1 temporary index writes run the `post-index-change` hook → the replay and its index were removed; A15 now installs that hook.
- P2 lanes → below.
- P2 packet lacked step 2 and caller context; the review-plan acceptance still named the removed 64-step walk → acceptance corrected.

Delta pass 4 (3 findings):

- P1 a bracketed reviewed name is a glob that misses itself → not reproduced: on git 2.50 the pathspec still matches the name literally (A29 reminds with and without `literal`); `literal` is kept as the stated intent and A29 as a regression probe.
- P2 lanes → below.
- P2 packet context → the review plan and step 2 are in the pull request.

Same-class recurrence decision (`dual-track-review-gate` same-class rule): the
classes "a repository-configured program runs" and "user diff config changes
the comparison" recurred in four passes. Decision: `replace` — the predicate
now compares tree entries only, which removes every content, index and helper
step instead of pinning one more option.

## External source

Gerrit `config-labels`, copyCondition change kinds `TRIVIAL_REBASE` (same diff
including context lines, no conflict resolution; default for Code-Review) and
`MERGE_FIRST_PARENT_UPDATE`. Read on 2026-10-22.

## Repository lanes

Tested tree: commit c9a14c6 (tree 9c3d230), base `origin/main` 20c7102. After
it, `git diff --stat c9a14c6 HEAD` lists only files in this evidence
directory, so every lane below applies to the current candidate; the
reference and link checks were rerun on it (`spec_reference_check_ok`,
`markdown_link_check_ok`).

| Command | Result |
| --- | --- |
| `make test` | exit 0 |
| `bash skills/skill-extraction-workflow/scripts/test_check_ccl_regressions.sh --heavy-only` | `regression_heavy_lane_ok: 9 suites` |
| `python3 scripts/check-public-sanitization.py .` | `public_sanitization_ok` |
| `python3 skills/skill-extraction-workflow/scripts/check_review_evidence_present.py --repo-root . --base 20c7102` (merge-base with fetched `origin/main`) | `review_evidence_present_ok: 5 review, 1 challenge` |
| `CCL_SKILL_BASE_REF=origin/main bash skills/skill-extraction-workflow/scripts/check-ccl-skills.sh .` | `ccl_skill_check_clean_ok`, `r0_status=private-ok` |
| `python3 skills/skill-extraction-workflow/scripts/shared_git_surface_gate.py --repo . --base-ref origin/main` | `shared_git_surface_gate_ok` |
| `bash hooks/test_remind_review_covers_head.sh` | 62 passed, 0 failed |

Delta pass 5 on the final hook change and delta pass 6 on the plan wording
reported no P0/P1; their P2s asked for these lane results, the tested-tree
binding and wider packet context.
