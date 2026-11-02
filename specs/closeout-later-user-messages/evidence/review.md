# Review record

Passes used `skills/skill-extraction-workflow/scripts/extraction_review_gate.sh` against `origin/main` at stage `build` with risk tag `shared-gate`. The implementer family was `anthropic`, so the reviewer was Codex.

The branch history was rebuilt so that the source-register commit comes last. Commit ids below are the ones each pass reviewed.

## Review pass

- Reviewed commit: `bdd79ef` (before a history rebuild)
- Result: `review.json`. An earlier call returned `inconclusive` before any review, because the self-review named too few owners. It was not counted.
- Findings: 3 total (0 P0 / 0 P1 / 3 P2)
- R0 evidence: `check-ccl-skills.sh` printed `alias_audit_ok` and `r0_status=private-ok`
- Dispositions:
  - P2 `hooks/host-input.py`, past the scan limits: split in two. Delivery evidence falling out of the tail could suppress the recheck. Fixed, with a test that fails on the earlier code. A message itself falling out of the tail before the first stop: not changed. It never happened in 40 real cases (longest 9.6 MB of a 16 MiB window), and a full scan of files up to 221 MB would risk the hook's 5-second limit. Recorded in `validation.md` and in the function's comment.
  - P2 `hooks/host-input.py`, helpers not in the packet: checked from source and recorded in `validation.md`.
  - P2 `hooks/test_proposed_next.py`, results not in the packet: `validation.md` now holds them, including the mutation table.

## Challenge pass

- Reviewed commit: `becd23b`
- Result: `challenge.json`
- Findings: 4 total (0 P0 / 0 P1 / 4 P2)
- R0 evidence: as above
- Gate-fireability applicability: yes, the change adds a Stop recheck. Exercised through real transcripts: `evidence/behavior-eval.md`, firings in the synthetic runs
- Dispositions:
  - P2 `hooks/host-input.py`, tail mode skips the delivery check: not changed in code. The review pass pushed the other way, and the two findings cannot both be met without scanning the whole file. The worst case is one extra continuation per message in a session already past 16 MiB. The acceptance text was wrong, so `pre-final-continuation-gate.md` and `plan.md` now state the exception.
  - P2 `pre-final-continuation-gate.md`, "especially Y requests Y" also matches existing material: fixed in the rule and the hook note, which now say it may ask for the agent's own Y or only point at material, and that an unclear reading gets one line. Retested for recall and precision in `behavior-eval.md`.
  - P2 `hooks/host-input.py`, helpers not in the packet: added `test_concurrent_stops_get_one_recheck` and `test_recheck_rides_with_the_large_context_notice`; the source check is in `validation.md`.
  - P2 `validation.md`, final run still pending: filled in under Final run after the last commit that changes anything outside this directory.

## Delta pass 1

- Reviewed commit: `d6f1d18`; packet: `git diff becd23b..d6f1d18`, with three challenge findings passed verbatim as open items. Run with the generic `code-review` controller, because the delta holds no file this skill owns.
- Result: `delta-review-1.json`
- Findings: 2 total (0 P0 / 0 P1 / 2 P2)
- Dispositions:
  - P2 `pre-final-continuation-gate.md`, the exception could not be checked from the packet: checked from source. `test_recheck_waits_for_delivery_evidence` pins the check on a complete view, and `test_tail_scan_does_not_need_delivery_evidence_it_cannot_see` pins the exception past the limits. The killing mutations `no-delivery-gate` and `tail-needs-delivery` turn each one red.
  - P2 `validation.md`, final run absent from the packet: filled in after this pass.

## Post-review delta

After `d6f1d18`, the history was rebuilt so the source-register commit comes last, and the tree was compared by hash. The commits after it change only record files in this directory.
