# Local checks reach what CI enforces

Status: implemented. Reproduction and measurements are in
[validation evidence](evidence/validation.md); review passes and the
verification lanes are in [dispositions](evidence/dispositions.md).

Artifact classification: gate implementation (repository tooling and the root
contract). Risk tag: shared-gate. The round moves one existing check to an
earlier lane, adds a fix hint to one failure, names a missing recipe, and lists
one CI-only check. It adds no gate, flag or permission.

## Observed failures

- After pushes in round 156, CI went red on the line-cited obligation ledger
  (`STALE_LEDGER`), which only the heavy lane audits, while `make test` and
  `check-ccl-skills.sh` were green.
- The same round's pull request was opened as a draft and stayed red on
  `review_evidence_missing`, a check CI runs only on pull requests, until the
  review results were committed; nothing in the local path names it.
- In rounds 156 and 158 a delta pass over files the extraction lane does not
  own was refused by `extraction_review_gate.sh`; both rounds improvised a call
  to the generic controller that the extraction docs do not describe.

## Reproduction on main

Each form ran against main with a control that differs in one variable
(details in the validation record):

| Form | Probe | Control |
| --- | --- | --- |
| Stale ledger | One line inserted above a cited carrier: the repo audit fails; `check-ccl-skills.sh` and the fast lane pass | No edit: the audit passes in about 8 s |
| Delta pass without an extraction-owned file | The wrapper refuses on ownership; the generic controller with the round's high-risk tag demands a review chain, and refuses a zero challenge budget | The same delta plus one extraction-owned file passes the precondition; the generic call with a one-pass chain id passes |
| Review evidence | A `skills/` change without a committed result fails the check | The same change with a committed result passes |

## Change

- `test_check_ccl_regressions.sh`: the real-repository ledger audit runs in the
  fast lane, which `make test` and the CI fast job run, not only in the heavy
  lane. The CI fast job already checks out full history, which the audit needs.
- `obligation-ledger.py`: a `STALE_LEDGER` failure prints the render command
  that regenerates the ledger. A ledger is stale only after every other check
  passed, so the mapping still resolves; a carrier whose text changed fails
  earlier with its own code, which re-rendering cannot clear.
- `dual-track-review-gate.md`: the delta-pass step names the entrypoint for a
  delta with and without a file this skill owns.
- `review_gate.py`: the extraction lane's ownership refusal points at that step.
- `AGENTS.md`: the list of checks outside `make test` names the review-evidence
  check and its local command.

## Not changed

- The extraction lane's ownership precondition. A round-level ownership flag was
  considered and rejected: it would add a switch and loosen the guard that keeps
  the single-shot lane for extraction work, while a working route exists.
- `make test` does not run the review-evidence check: it would be red during
  development, before any review exists.
- The plugin-wide pull-request hook: it must not call a script that only this
  repository has, and a push to an open pull request is invisible to it.
- `testing-strategy`: its rule that CI owns only what it runs, and that the
  narrowest failing evidence runs before a push, already states the principle;
  the miss was this repository's lane placement.

## Acceptance

| Input | Expected | Test |
| --- | --- | --- |
| A carrier line moves without a ledger render | The fast lane fails with `STALE_LEDGER` | fast lane with a shifted carrier: main passes, candidate fails (evidence) |
| A stale ledger | The failure prints a render command, and running it clears the failure | `test_obligation_ledger.sh` (fails on main's tool) |
| Carrier text deleted | Re-rendering does not clear it | probe (evidence) |
| Extraction lane, candidate without a file it owns | Refused before any reviewer runs, pointing at the delta-pass step | `test_review_gate.sh` (fails on main's controller) |
| The documented generic delta call | Passes the controller's preconditions | probe (evidence) |
| A `skills/` pull request without a committed review result | The command named in `AGENTS.md` reports it locally | probe and control (evidence) |
