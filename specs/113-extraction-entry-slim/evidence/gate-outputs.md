# 113 gate outputs (deterministic checks on the reviewed tree)

Recorded by the author from commands run on the landing tree; each block names the commit it ran on so a reviewer can re-run the same command against the same tree. Base (landing target, attested): `e71598540c96abc079abc67fb10985f39576c0bb`. Owner tree at the time of these runs: commit `908a3e4` (the last commit that changes a bound skill or spec path before this artifact; this artifact itself is a later commit and changes no gate input).

## check-ccl-skills.sh with CCL_SKILL_BASE_REF=origin/dev (commit 908a3e4)

```
r0_status=private-ok
md_reference_check_done
sync_pointer_check_done
task_retro_memory_escape_gate_ok
contract_anchor_gate_ok (10 anchors)
register_firing_path_resolution_ok (444 locators resolved)
changed_entrypoint_word_delta: skills/skill-extraction-workflow/SKILL.md base_body_words=16600 head_body_words=15651 delta_body_words=-949
entrypoint_word_budget_legacy_ok: skills/skill-extraction-workflow/SKILL.md base_body_words=16600 head_body_words=15651 allowed_body_words=16600
reference_line_over_limit_count_delta=+0
changed_reference_line_delta: skills/skill-extraction-workflow/references/attention-budget-ratchet.md base_lines=46 head_lines=48 delta_lines=+2
changed_reference_line_delta: skills/skill-extraction-workflow/references/coverage-exhaustion-traps.md base_lines=90 head_lines=97 delta_lines=+7
changed_reference_line_delta: skills/skill-extraction-workflow/references/description-authoring.md base_lines=175 head_lines=201 delta_lines=+26
changed_reference_line_delta: skills/skill-extraction-workflow/references/dual-track-review-gate.md base_lines=644 head_lines=644 delta_lines=+0
changed_reference_line_delta: skills/skill-extraction-workflow/references/external-practice-controls.md base_lines=164 head_lines=168 delta_lines=+4
reference_line_budget_blocking_ok
ccl_skill_check_clean_ok
```

## Regression lanes (commit 908a3e4)

```
regression_fast_lane_ok: 42 suites, jobs=8
test_check_ccl_regressions_fast_ok
fast rc=0
|   row: | A deterministic gate's terminal REASON CODES are the coverage unit — not its assertion count, and not its exit codes, since many distinct fail-closed outcomes share one nonzero exit and auditing by exit code reads them all as covered: the review controller carried 111 assertions while two of its terminal reason codes — including the fail-closed floor that fires when the configured client order holds no cross-family reviewer — had no assertion anywhere in the repository, so a regression in either was undetectable by the suite. What the mutations establish is that detection gap and its closure, not that any lane was in fact recorded clean. Enumerate a gate's terminal outcomes and check each has an owning assertion, rather than reading a large suite as coverage | `code-review` | behavioral-evidence: RED-baseline; observed-failure: no; firing-path: command:skills/code-review/scripts/test_review_gate.sh | updated | `code-review/SKILL.md` is the owner key and is itself unchanged this round; the cases land in `code-review/scripts/test_review_gate.sh`. Applied mutations, each attributed differentially. Control accounting, stated exactly because the two walks ran in different copies: the first walk's disposable copy omitted the owner's `references/`, so one unrelated check that greps a file there failed identically in its control and in every mutant, leaving attribution differential but its control not green; the second walk's copy was complete and its control was green; the final candidate in the worktree runs 138 ok / 0 FAIL. The RED here is mutation-induced, not pre-change: the added cases pass against the unmodified controller by construction, because they assert outcomes it already produces correctly, so the evidence is applied-mutation sensitivity rather than a failing baseline that the change then fixes. Attribution is per-assertion, not per-suite: each owning case passes in its control and fails under its mutant. Rewriting the initial `last_reason_code` literal fails the no-cross-family-reviewer case and nothing else; deleting the empty-packet guard fails the empty-candidate case and nothing else. The two mutations that remove the same-family `continue` also fail a recorded collateral set — 27 and 24 total FAIL lines — because that `continue` carries the whole fallback path, so their evidence is the owning flip, not containment: turning it into `break` flips the precision case that proves the skip does not kill the lane, and dropping it while exiting the fake wrapper before it appends `client_sequence` flips the no-cross-family case while leaving the empty-candidate case GREEN, which is what isolates the added earlier-write clause — that path raises before the client loop exists, so the clause was added to the first case and deliberately not to the second |
test_check_ccl_regressions_heavy_only_ok
heavy rc=0
```

## Census test: clean / mutant / restored (test file as committed in 5bfdba7; mutant = the `-mtime "-$days"` predicate removed from the find in reference-access-census.sh on a working copy, then restored)

```
## census test: clean run
test_reference_access_census_ok
rc=0
## mutant: -mtime predicate removed from find
rc=1
FAIL: denominator wrong:\nreference_access_census: skill=demo-skill window=30d transcripts=5 sessions_touching_package=4
## restored
test_reference_access_census_ok
rc=0
```

## Pinned phrases and ledger anchors into SKILL.md (counts via grep -oF | wc -l, commit 908a3e4)

```
would other teammates hit this => 1
will we forget next time => 1
teamwide recurrence => 1
reusable routing/process/team failure => 1
memory-only landing as insufficient => 1
- **Firing-point-placement corollary:** => 1
anchor a bare mention of runtime or external ac => 1
anchor a loosening must be checked hardest => 1
anchor Descriptive, not permissive => 1
anchor do not claim design-judgment extraction => 1
anchor do not make normal users route through a => 1
anchor enumerates what an external source has t => 1
anchor M needs the functional-equivalent check => 1
anchor must cover three axes, not only the exec => 1
anchor must define eval/pressure scenarios, bas => 1
anchor never close a judgment-delta row whose v => 1
anchor stays inside the reference line budget => 1
anchor until an operation that could have falsi => 1
```

## Obligation table reproduction (commit 908a3e4)

```
governing-chain-diff: skills/skill-extraction-workflow/SKILL.md
derived row set: 104
rows: 109 written: specs/113-extraction-entry-slim/obligation-preservation.md
generator exit status: 0 (non-zero would list every survivor phrase whose carrier count is not 1)
```
