# Validation evidence

## Measurements behind the round

Per-session metrics from one product line's month of Claude Code sessions
(151 main sessions), recomputed from the previous round's private per-session
data; raw data stays in a private archive.

| Measure | Value |
| --- | --- |
| Distinct CCL skills loaded per session, median / p75 | 4 / 6 |
| Sessions loading four or more CCL skills | 54% |
| CCL skill-body tokens loaded per session, median / p75 | about 39k / 67k |
| `code-review` loads, tokens per load | 115, about 11.6k |
| `worktree-isolation` loads, tokens per load | 85, about 9.6k |
| `product-rd-workflow` loads, tokens per load | 68, about 19.8k |
| Open-specification recommendation for a loaded skill body | under 5,000 tokens |

Before this round `worktree-isolation/SKILL.md` spent about 27 KB of its
38 KB on push, merge and teardown sections that apply only after the work is
done, while it is loaded at Step 0 before the first edit.

## Pre-registered checks

| Check | Result |
| --- | --- |
| Entrypoint load | 38,112 → 13,672 bytes (−64%) |
| Zero loss | 81 moved lines, every one verbatim in `pre-merge-landing-checks.md` or `merge-and-teardown.md`; with one moved line dropped from a scratch copy the check reports exactly that line and exits 1 |
| Sync gate, relocated text with the old registry | exit 1; blocks `merge-exec-protocol-section`, `merge-exec-citation-token` and `worktree-teardown-section` only |
| Sync gate, new registry | exit 0, `sync_semantic_check_ok` |
| Sync gate, protocol anchor removed from the reference (scratch copy) | exit 1; blocks the two merge-exec pins naming the reference path, nothing else |
| Sync gate, teardown heading renamed in the reference (scratch copy) | exit 1; blocks `worktree-teardown-section` only |
| Hook suite against the previous hook | exit 1; the six new text-contract assertions fail (canonical pointer, ignored-artifact scan, exit-0 requirement, release-name exception, "only exception" claim, pointer target) and every one of the 57 existing remind/quiet probes passes |
| Hook suite against the new hook | 64 pass, 0 fail |

## Killing mutations for the new hook assertions

Applied one at a time to a scratch copy of the hook and the reference, then
restored; the restored control passes.

| Named property | Mutation | Result |
| --- | --- | --- |
| canonical teardown pointer | drop the reference path from the reminder | only that assertion fails |
| ignored-artifact scan before removal | `status --ignored -s` → `status -s` | only that assertion fails |
| scan exit-0 requirement | drop "必须 exit 0" | only that assertion fails |
| release-name branch exception | drop the release exception | only that assertion fails |
| single-exception claim | reintroduce "唯一例外" | only that assertion fails |
| pointer target resolves | rename `## 收尾：` in the reference | only that assertion fails |

## Recorded incident: a ledger anchor moved with the text

The first relocation also moved the shared-branch update bullet. Six register
rows name that bullet's text in `worktree-isolation/SKILL.md` as their firing
path. The sync-pointer suite's end-to-end case then lost its combined verdict
token: the full validator stopped on `register_firing_path_unresolved` (six
locators) before printing it. The same case on the base tree printed the
token, so the change caused it. The pin enumeration had read the contract
anchors and the suite assertions but not the ledger anchors, which is the
recipe gap the trim rule in `attention-budget-ratchet.md` now closes. The
bullet went back into the entrypoint verbatim; afterwards
`register_firing_path_resolution_ok (606 locators resolved)` and the suite
passes.

## Focused suites on the candidate

| Suite | Result |
| --- | --- |
| `skills/skill-extraction-workflow/scripts/test_check_sync_pointers.sh` | ok |
| `skills/skill-extraction-workflow/scripts/test_ai_coding_implementation_gates.sh` | ok |
| `skills/worktree-isolation/scripts/test_worktree_sweep.sh` | 17 passed, 0 failed |
| `skills/worktree-isolation/scripts/test_worktree_status.sh` | ok |
| `hooks/test_remind_post_merge_cleanup.sh` | 64 pass, 0 fail |
