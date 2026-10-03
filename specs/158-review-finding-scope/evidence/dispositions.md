# 158 review dispositions

R0 evidence: `check-ccl-skills.sh` against `origin/main` reported
`r0_status=private-ok` (`alias_audit_ok`) on `8d84e30`, `82faac0` and `a844691`.

## Pass 1 — review (kimi), base `origin/main`, reviewed commit `8d84e30`: passed

No findings. Record: `pass1-review.json`.

## Pass 2 — challenge (codex), base `origin/main`, reviewed commit `8d84e30`: 3 × P2

Focus: bypass by omission (no quote, or a paraphrase passed off as verbatim);
leaking confidential detail through the quote; over-correction against needed
or requested fixes; one rule across the code-review docs, the manual template
and the design gate; records claiming more than the replays show.

- Gate-fireability applicability: yes — the round edits the rule a reviewer
  applies when the intent or focus quotes the requester.
- Item 9 exercised: yes — the recorded `challenge_focus` in
  `pass2-challenge.json` opens with bypass by omission, and its concern result
  says the omission and misquotation limits are stated.

| # | Sev | Finding | Disposition | Where |
| --- | --- | --- | --- | --- |
| 1 | P2 | "Each fix for a risk that predates the change" would make reviewers call a requested fix of an older defect droppable; the manual template scopes the same list by what the request needs | fixed in `82faac0`: the clause now covers only a pre-existing risk that the request does not cover and the change does not expose or worsen, in the controller (build and release) and the manual template. The counterexample did not reproduce: in the added `--requested-fix` control no run called the fix droppable under either wording (Claude 0/6 and 0/6, Codex 0/3 and 0/3); the narrowing stays because the first wording read that way literally | `review_gate.py`, `manual-invocation-and-prompts.md`, `test_review_gate.sh`, `scope_anchor_replay.py` |
| 2 | P2 | Evidence gap: "sanitized like the rest of the packet" is an obligation, not proof that confidential detail in a quote is contained | fixed in two steps: `82faac0` stated the boundary in the record (credential-shaped secrets are scanned, other confidential detail is the caller's obligation); pass 3 found the scan claim untested, and tests for both routes followed (pass 3, finding 3) | `validation.md` Self-review; `test_review_gate.sh` |
| 3 | P2 | Evidence gap: aggregate counts only; per-run outputs and the exact concern text are absent, and the regex can match hardening findings | fixed in two steps: `82faac0` added a per-run record, but with truncated findings and regex classifications; pass 3 found both, and the record now holds complete findings with a by-hand classification (pass 3, findings 1 and 2) | `scope_anchor_runs.json`, `validation.md` |

## Pass 3 — delta review (codex), base `8d84e30`, reviewed commit `82faac0`: 5 × P2

The packet quoted the three pass 2 findings verbatim as open items; the focus
opened with bypass by omission. Record: `pass3-delta.json`.

| # | Sev | Finding | Disposition | Where |
| --- | --- | --- | --- | --- |
| 1 | P2 | The first matched plan's weekly step was called unrequested in Claude 5/6 and Codex 3/3 runs, not 0/6 and 2/3 | fixed: the count came from the runner regex, labelled as a reading by eye. Every run in every arm was re-read by hand against rules fixed first. Corrected: that plan 5/6 and 3/3; arm B's override or rollout column 3/6 to 0/6 (its regex hits offered removal as hardening). An uncheckable source-domain sentence was removed. The same check on `reviewer_scope_replay.py`, rerun with raw capture: both texts flag the out-of-scope code 4/4; only the new text calls the switch unrequested, 0/4 to 4/4 | `scope_anchor_runs.json`, `reviewer_scope_runs.json`, `reviewer_scope_replay.py`, `validation.md`, `plan.md` |
| 2 | P2 | The record truncates findings at 180 characters and omits the fixes, so zero counts cannot be audited | fixed: both per-run records hold every finding's complete failure path and fix, the classification with the index of each finding it rests on, and notes on borderline readings | `scope_anchor_runs.json`, `reviewer_scope_runs.json` |
| 3 | P2 | The credential scan of the intent and `--focus` routes is asserted, not shown | fixed: a test sends a credential-shaped `--focus` value and expects egress denied; the plan route already had one. A controller copy that skips the profile scan fails both and no other check | `test_review_gate.sh` |
| 4 | P2 | The `--focus` test inspects only the Claude profile; other clients could omit it | fixed: the controller writes one frozen profile file and passes it to every client; the Claude, Kimi, Codex and OpenCode wrappers embed the whole file. A test shows a fallback reviewer receiving the same file. A copy that drops the focus fails the three focus checks and no other | `test_review_gate.sh`; wrappers in `skills/code-review/scripts/` |
| 5 | P2 | The plan claims local verification complete without the mandatory `make test` result | fixed: the plan no longer claims it; lane results on the final commit are recorded below | `plan.md` |

## Pass 4 — delta review (codex), base `82faac0`, reviewed commit `a844691`: 5 × P2

The packet quoted the five pass 3 findings verbatim as open items and left out
`scope_anchor_runs.json`, which alone exceeds the 200 KB packet limit; its
summary was in the plan evidence. A first attempt stopped before review with
`egress_denied`: the only scan hit was `AKIAIOSFODNN7EXAMPLE`, the documented
AWS example key the new egress test sends (the suite already uses it in three
cases), so the rerun passed `--allow-fallback-egress`. Record: `pass4-delta.json`.

| # | Sev | Finding | Disposition | Where |
| --- | --- | --- | --- | --- |
| 1 | P2 | Rerunning `reviewer_scope_replay.py` into the same `--raw-dir` overwrites an earlier capture non-atomically | accepted, no change: the caller chooses the raw directory; the evidence contract puts a new measurement in a new round's directory, and this round's raw outputs are archived separately | `reviewer_scope_replay.py` |
| 2 | P2 | Pass 3 finding 2 cannot be verified because the per-run record is outside the packet | packet boundary: the record is in the repository with every finding and the index behind each count; the by-hand reading is the implementer's record, open to audit there. `reviewer_scope_runs.json`, in the packet, has the same structure | `scope_anchor_runs.json` |
| 3 | P2 | The intent-route scan, the approval case and the mutation results are not shown | covered outside the delta: the plan-secret test (`test_review_gate.sh`, just before the derived-default checks) covers the intent route, the approval-flag test follows it, and the mutation results are in `validation.md` | `test_review_gate.sh`, `validation.md` |
| 4 | P2 | Equal profile hashes do not show each wrapper puts the focus in its prompt | covered by existing wrapper tests, which assert the profile body between each wrapper's sentinels in the prompt it builds: Claude in `test_claude_review_probe.sh`, Kimi and Codex in `test_cli_review_wrappers.sh`, OpenCode in `test_opencode_review_retry.sh`. The wrappers embed the whole profile file, focus included | wrapper test suites |
| 5 | P2 | The lane results the dispositions point to are not supplied | recorded below after the lanes ran on the final commit | this file |

## Verification lanes on `a844691`

Run in a detached checkout of `a844691` with `CCL_SKILL_BASE_REF=origin/main`,
as CI sets it. The commit after `a844691` adds only records in this directory.

- `make -k test`: `regression_fast_lane_ok` (44 suites), `code_review_shard_1_ok`,
  `code_review_shard_2_ok`, `review_gate_abort_leak_ok` for both legs. Its
  `test-repo-gates` step stopped at `shared_git_surface_gate_error: candidate
  branch name is unavailable`, an effect of the detached checkout; rerun with
  `GITHUB_HEAD_REF` set as CI does, `make test-repo-gates` exits 0
  (`ccl_skill_check_clean_ok`, `shared_git_surface_gate_ok`).
- `test_check_ccl_regressions.sh --heavy-only`: `regression_heavy_lane_ok`
  (10 suites).
- An earlier run on `82faac0` failed the impact-chain gate, because that
  commit changed `code-review` after the first register commit; the second
  register row in `a844691` closes that round.
