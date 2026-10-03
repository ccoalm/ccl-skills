# 158 review dispositions

R0 evidence for every pass: `check-ccl-skills.sh` against `origin/main`
reported `r0_status=private-ok` (`alias_audit_ok`) on the reviewed candidate.

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
| 1 | P2 | "Each fix for a risk that predates the change" would make reviewers call a requested fix of an older defect droppable; the manual template scopes the same list by what the request needs | fixed: the clause now covers only a pre-existing risk that the request does not cover and the change does not expose or worsen, in the controller (build and release) and the manual template. The counterexample did not reproduce: in the added `--requested-fix` control no run called the fix droppable under either wording (Claude 0/6 and 0/6, Codex 0/3 and 0/3); the narrowing stays because the first wording read that way literally | `review_gate.py`, `manual-invocation-and-prompts.md`, `test_review_gate.sh`, `scope_anchor_replay.py` |
| 2 | P2 | Evidence gap: "sanitized like the rest of the packet" is an obligation, not proof that confidential detail in a quote is contained | fixed in the record: the quote travels in the intent or `--focus`, both in the frozen profile, which the controller scans for credential-shaped secrets before a non-Claude reviewer sees it; other confidential detail is not machine-checked and stays the caller's obligation. A test now shows `--focus` reaching the profile in a derived-default review | `validation.md` Self-review; `test_review_gate.sh` |
| 3 | P2 | Evidence gap: aggregate counts only; per-run outputs and the exact concern text are absent, and the regex can match hardening findings | fixed: `scope_anchor_runs.json` records every run's findings, its classification, the by-eye notes and the concern text each arm used; the neutral-domain raw outputs stay in the maintainer's private archive | `scope_anchor_runs.json`, `validation.md` |

Re-measurement after the fixes, with the landed wording: arms C and D, the
matched plan and the requested-fix control (numbers in `validation.md`). The
matched plan's first version also had a weekly review of the differences,
which the request does not ask for; Codex flagged it in 2/3 runs, so the step
was removed and the control rerun.
