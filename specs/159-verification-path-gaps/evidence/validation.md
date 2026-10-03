# Validation evidence

## Sources

The forms were registered by the review of recent sessions behind round 156 and
re-read here from what those rounds produced: the failed CI runs of round 156's
pull request, the delta-pass invocations of rounds 156 and 158, and the
controller results they left. Every form was treated as a hypothesis and
reproduced on main (`44cc6d8`) before any change.

- Round 156's pull request was opened as a draft at 04:55 and marked ready at
  08:20. Three CI runs in that window failed `repository-gates` on
  `review_evidence_missing`; the last also failed `regression-heavy` on
  `STALE_LEDGER` for the line-cited obligation ledger.
- Rounds 156 and 158 ran their delta passes through the generic controller with
  improvised `--review-chain-id` values after the extraction wrapper refused
  deltas that held no file it owns.

## Reproduction on main

### Stale ledger reaches CI past the local checks

- Control: `test_obligation_ledger_repo_audit.sh` on a clean tree:
  `audit_ok`, about 8 s.
- Probe: one line inserted above `skills/defect-diagnosis/SKILL.md:160`, a
  carrier the ledger cites. The repo audit fails with `STALE_LEDGER`;
  `check-ccl-skills.sh` (base `origin/main`) ends `ccl_skill_check_clean_ok`;
  `test_check_ccl_regressions.sh --fast` ends `regression_fast_lane_ok: 44
  suites`. Its only `STALE_LEDGER` line is the synthetic `stale_locator`
  fixture case.
- The audit sat in the heavy lane "because it needs full history and walks a
  1240-row corpus". The CI fast job checks out with `fetch-depth: 0`, and the
  fast lane's slowest suites took 260 s and 222 s in the same run, so the audit
  does not lengthen it.
- Fix safety: with the line shifted, `obligation-ledger.py render` with the
  header's pinned base and head rewrites two ledger lines and the audit passes.
  With the carrier's text replaced instead, render and audit both fail with
  `CARRIER_COMPOSITE_NOT_UNIQUE`: re-rendering cannot hide a dropped obligation.

### Delta pass over files the extraction lane does not own

All probes ran with no reviewer CLI on `PATH`, so a call that passes every
precondition stops at client selection.

| Call on a delta touching only a code-review file | Result |
| --- | --- |
| `extraction_review_gate.sh --mode review --base HEAD~1` | refused: extraction lane requires controller-derived skill-extraction-workflow ownership |
| Same, delta also touching one extraction-owned file (control) | passes the precondition; stops at clients |
| `review_gate.sh --mode review --risk-tag shared-gate` | refused: `review_chain_required` |
| Same with `--challenge-budget 0` | refused: release and high-risk review require at least one challenge |
| Same without the risk tag (control) | passes; the round's risk declaration is lost |
| `review_gate.sh --mode review --risk-tag shared-gate --review-chain-id <fresh> --autonomous-review-index 1` | passes the preconditions; stops at clients |

### Review evidence checked only on pull requests

- Probe: a commit changing one file under `skills/`, then
  `check_review_evidence_present.py --repo-root . --base 44cc6d8`:
  `review_evidence_missing`, exit 1.
- Control: the same branch plus a committed controller result under a round's
  `evidence/`: `review_evidence_present_ok: 1 review, 0 challenge`, exit 0.

## Candidate behavior

- The same one-line shift in a clone of the candidate (`a37d9df`):
  `test_check_ccl_regressions.sh --fast` exits 1, with one failed suite,
  `test_obligation_ledger_repo_audit.sh`. Its output names `STALE_LEDGER` and a
  `fix: regenerate the ledger:` command. Running that command exactly as
  printed regenerates the ledger, and the repo audit then passes.

## Tests against the base

- `test_obligation_ledger.sh` with main's `obligation-ledger.py`: fails at the
  new case, "expected one fix line", after every earlier case passed. With the
  candidate tool: `test_obligation_ledger_ok`.
- `test_review_gate.sh` with main's `review_gate.py`: one failure, the new
  refusal check. With the candidate controller: `review_gate_tests_ok`.

## Example-domain preselection

No new example set: the new test reuses the existing synthetic ledger fixture,
and the `AGENTS.md` line names repository commands only.

## Target-output map

| Owner | Direction | Status | Changed file or reason |
| --- | --- | --- | --- |
| skill-extraction-workflow (regression lanes) | firing point | updated | `test_check_ccl_regressions.sh` |
| skill-extraction-workflow (ledger tool) | failure message | updated | `obligation-ledger.py`, `test_obligation_ledger.sh` |
| skill-extraction-workflow (dual-track gate) | recipe | updated | `dual-track-review-gate.md` delta-pass step |
| code-review (controller) | refusal message | updated | `review_gate.py`, `test_review_gate.sh` |
| code-review (development-completion) | pre-PR walk | unchanged | step 3 already sends extraction work to its own delta pass |
| repository contract | CI-only list | updated | `AGENTS.md` |
| testing-strategy | generic local/CI rule | unchanged | states the principle; the miss was lane placement here |
| product-rd-workflow | delivery gates | unchanged | no text claims this repository's local path |
| hooks | pull-request reminder | unchanged | plugin-wide; cannot call a repository-local script or see a push to an open PR |
