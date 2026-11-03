# Validation

Candidate: branch `feat/product-rd-redesign`, base fd3e8b8 for the implementation diff.

## RED baseline

| Check | Base result |
| --- | --- |
| Size ratchet in `test_ai_coding_implementation_gates.sh` | fails on the 75,741-byte base entrypoint: "over the 32768-byte ratchet" |
| `register-firing-path-resolution.rb` | after the rewrite and before the exemption, `source-register.md:598` fails: anchor text absent from target |
| specs/065 `obligation-ledger.py render` | after the rewrite and before rebinding, `CARRIER_COMPOSITE_NOT_UNIQUE` on `product-rd-workflow/SKILL.md#1` |

## GREEN

| Check | Result |
| --- | --- |
| `check-ccl-skills.sh` | `ccl_skill_check_interim_ok` (R0 pending maintainer audit; the private alias audit is not configured on this host) |
| `test_ai_coding_implementation_gates.sh`, `test_pinned_phrase_mutation_walk.sh`, `test_routing_pointer_integrity.sh` | ok |
| `test_register_firing_path_resolution.sh`, `test_register_firing_path_wiring.sh` | ok (59 and 21 assertions) |
| `hooks/test_proposed_next.py`, `test_skill_loading.py`, `test_task_entry.py` | OK |
| `obligation-ledger.py render`, `test_obligation_ledger_repo_audit.sh` | `render_ok ... unresolved=0`; audit ok. 40 carriers rehosted by exact text, eight dispositions changed from merged/subsumed to `rehosted`, one composite carrier digest recomputed; untouched rows keep their original bytes |
| `check-markdown-links.py`, `check-public-sanitization.py` | ok |
| `make test-regressions-fast` (on 5ab75a2, before the review fixes) | all suites ok except `test_check_ccl_skill_catalog.sh`, which fails the same way on unmodified `main` on this host |

Every row except the fast lane ran on 4c78255, after the review fixes. The full `make test` has not run yet.

## Review (`evidence/impl-review-p1.json`, `evidence/impl-review-p2.json`)

The diff is over the 200 KB packet cap with the obligation mapping, so it ran as two partitions: P1 the entrypoint with the design and the hook readers, P2 the references, the register rows, the exemption and the ratchet.

| Finding | Disposition |
| --- | --- |
| P1 Stage-Entry State Checklist trigger lost | Applied: the stage-boundary sentence is back under Hard gates. |
| P1 completeness trigger narrowed (exemption claims, load before implementation) | Applied: the line covers exemption claims and loads before implementation. |
| P1 user-visible notices destination missing | Source-refuted: the text moved verbatim to `design-routing-and-readiness.md:45`, outside the P1 partition. |
| P1 spec sync no longer names contract layers or directory-local rules | Applied: the line names the active contract layers before implementation, includes directory-local rules, and loads the reference. |
| P1 G4 makes every shared-gate change require a technical design | Applied: shared gates are a separate bullet with their own classification, review and `interim` rule. |
| P1 standalone non-PRD artifacts lost their direct return | Applied: the routing row keeps the exception. |
| P1 DX trigger broadened to any developer surface | Applied: the original qualifier is restored. |
| P1, P2 evidence gaps (no test results; old text, hooks or digest logic outside the partition) | Disposed by the GREEN table above. The exemption is bound to the digest of register line 598; `test_register_firing_path_wiring.sh` drives a clone of the repository and covers the real-ledger digest and missing-row cases. |

## Challenge (`evidence/impl-challenge-c1.json`, `evidence/impl-challenge-c2.json`)

Run on 4c78255, the candidate after the review fixes, in the same two partitions.

| Finding | Disposition |
| --- | --- |
| C1 a process skill mentioned as an auxiliary step could take over as the primary action | Applied: the exception again requires the user to name the process skill as the primary or only action. |
| C1 product/spec normalization and standards-to-health-gate work no longer reach the shared-gate classification | Applied: both are back in the shared-gate trigger. |
| C1, C2 evidence gaps on preservation | Checked mechanically: of 183 old entrypoint lines of 30 characters or more, all but 13 appear verbatim in the new entrypoint or a reference. The 13 are line 61 (rewritten as the stage-boundary sentence), line 135 (retired) and lines 223–233 (the old reference-loading list). Every reference that list names is still named in the new entrypoint, and each conditional load survives at its trigger. |
| C2 evidence gap on the exemption | Checked by mutation: changing one word in register line 598 makes `register-firing-path-resolution.rb` fail with `register_firing_path_unresolved`; restoring it passes. The exemption covers only that exact row. |

## Delta review (`evidence/impl-delta-review.json`)

Run over the two challenge fixes and the new register row, base 4c78255. One P2, an evidence gap: the narrow packet held only the two restored triggers, not this file. The other six restorations are the review findings applied above, and the check results are the GREEN table plus `check-ccl-skills.sh` rerun after this round (`ccl_skill_check_interim_ok`). No further review round runs on this candidate.

## Hard stack-hazard suite (candidate 03216ed against `main` at 590eb29)

Same eight cases, settings and three runs per case as the `main` baseline.

| Arm | Mean score | Code handles the hazard (judge) | Hazard-targeted test | Cost | Duration |
| --- | --- | --- | --- | --- | --- |
| candidate | 0.771 | 17/24 | 20/24 | $24.01 | 1341 s |
| main | 0.760 | 17/24 | 19/24 | $23.79 | 1347 s |

No case lost a judge pass; every case matches `main`'s count. The mean clears 0.710. Cost is $0.22 over the "below $23.79" bar.

This suite cannot decide the redesign. Two diagnostic runs with traces kept (`hard-react-checkout`, `hard-go-deposits`) loaded the stack skill and `multi-agent-delegation`, never `product-rd-workflow`: these are narrow coding tasks that route straight to the stack owner. The entrypoint therefore never enters these sessions, and the cost difference is run-to-run variation (single runs of one case range from $0.69 to $1.41). What the suite shows is that narrow coding work did not regress. The cost condition is judged on the delivery suite below, whose cases enter product-rd.

## Delivery suite (candidate 03216ed against `main` at 590eb29)

Four delivery cases, three runs per case per arm, same graders on both arms: a CSV export feature, a per-user daily upload quota, invoice-paid webhooks, and removing a replaced endpoint whose module a scheduled job still calls. The export case ran a second round after a grader fix, described below.

| Measure | main | candidate |
| --- | --- | --- |
| Runs that loaded `product-rd-workflow` | 9 of 9 export and webhook runs; 0 of 6 quota and removal runs | same |
| Cost per run, runs that loaded product-rd (n=9 each) | mean $1.41, sd $0.33 | mean $1.15, sd $0.37 |
| Cost per run, runs that did not (n=6 each) | mean $0.83 | mean $0.74 |
| Export judge, second round | 3/3 | 2/3 |
| Export range check, second round | 2/3 | 3/3 |
| Webhook judge | 1/3 | 2/3 |
| Quota judge | 0/3 | 0/3 |
| Removal: route, doc row, scheduled caller kept | 9/9 | 9/9 |
| Removal: v1 test removed | 3/3 | 2/3 |
| Plan file written before code | 0/12 | 0/12 |
| Continuation line in the final message | 12/12 | 12/12 |

- **Quality:** no difference found. Every candidate export run that the judge failed (three in the first round, one in the second) keeps the failing piece outside `orders/export.py`, the only file the judge reads: the inverted-range check in `api/routes.py` in all three first-round failures, and the inclusive end date (`end + timedelta(days=1)`) in the route for the second-round failure. The same placement made a first-round `main` run fail. The traces show every export run in both arms rejects an inverted range somewhere.
- **Grader fix:** the first round's export judge also required the range check, and the Write/Edit regexes assumed `file_path` is the first input field, which an Edit with `replace_all` breaks. The range check became its own trace grader and both regexes accept the `replace_all` field; the fixed graders were checked on the first-round traces and a negative-control trace before the second round, and both arms used the same files.
- **Cost:** the point estimate is 18% lower per product-rd run, but with nine runs per arm the difference is within run-to-run spread (t ≈ 1.6). The certain saving is fixed per load: the entrypoint is 44,247 bytes smaller (75,741 to 31,494 at 4c78255; 31,659 now).
- **No reference reads:** no run in either arm opened a product-rd reference file, so moving text into references does not change what these sessions read.
- **Plan gate:** neither arm wrote a plan file before code in any case; this is current `main` behavior, unchanged by the redesign.

## Full local lane (candidate 03216ed)

`make -k test` with `SUITE_JOBS=1`, then each `test-repo-gates` command after the first failure run individually. Python 3.12 here has no PyYAML or pytest, so the lane ran with a virtual environment first on `PATH`.

| Lane | Result |
| --- | --- |
| `test-code-review` | all suites ok |
| `test-regressions-fast` | all ok except `test_check_ccl_skill_catalog.sh` (`c12-upstream-empty`) |
| `test-repo-gates` | all ok except `hooks/test_host_input.py` (17 failures) and `hooks/test_remind_unverified_cli_flag.sh` (100 pass, 19 fail) |

All three failures reproduce identically on `main` at 590eb29 on this host, run in the same session; they are host baseline failures, not caused by this change. CI on a pull request is the authoritative run for them.

## Full local lane after rebasing onto main at f6cc294

The three host baseline failures were fixed on `main`, and the branch was rebased onto it; the rebase brought in exactly that change and left the branch's own content unchanged.

| Lane | Result |
| --- | --- |
| `test-repo-gates` | all ok |
| `test-regressions-fast` | all ok |
| `test-code-review` | all ok except one assertion in `test_cli_review_wrappers.sh` ("Kimi reports a capability probe that exits on its timeout signal", a 5-second timeout case), with the host load average near 29 |
| `test_cli_review_wrappers.sh` rerun alone, three times | 0 failures each time, two of them at the same load |
| `test_check_ccl_regressions.sh --heavy-only` (`SUITE_JOBS=1`) | `test_check_ccl_regressions_heavy_only_ok` |
| `check_review_evidence_present.py`, `shared_git_surface_gate.py`, `check-public-sanitization.py`, `git diff --check` | ok |

The branch changes no file under `skills/code-review/`, so the one failure is recorded as a load-dependent flake in a timing-sensitive case, not caused by this change.

## Daily-use trial (candidate b49446d, 2026-10-24 to 2026-10-30)

Counts-only census over Claude transcripts, reviewed on 2026-11-03. A session is assigned to an arm by the plugin root its SessionStart injection links; evaluation and scratch harness directories are excluded. A code edit is an Edit or Write on a source-file extension; a plan is a Write to a plan, spec, design or proposal Markdown file before the first code edit. Arms:

- trial: the owner's main machine through the trial wrapper, 36 sessions, 26 with code edits, 17 loading product-rd;
- concurrent `main`: another of the owner's machines in the same window, 157 sessions, 137 with code edits, 88 loading product-rd;
- later `main`: the owner's main machine from 2026-10-31 to 2026-11-03, 24 sessions, 16 with code edits, 14 loading product-rd;
- earlier `main`: the owner's main machine from 2026-09-13 to 2026-10-23, 204 sessions. Only sessions whose injection carries the link are classified, and the hooks were older then, so this arm is not a fair control.

| Measure | trial | concurrent `main` | later `main` | earlier `main` |
| --- | --- | --- | --- | --- |
| product-rd loaded before the first code edit | 12/26 (46%) | 69/137 (50%), p=0.83 | 9/16 (56%), p=0.75 | 53/161 (33%), p=0.19 |
| Plan written before the first code edit | 5/26 (19%) | 42/137 (31%), p=0.34 | 4/16 (25%), p=0.71 | 26/161 (16%) |
| product-rd sessions that read a reference | 6/17 (35%) | 20/88 (23%) | 8/14 (57%) | 13/81 (16%) |
| Reads of `delivery-lifecycle.md` | 0 | 6 | 7 | 0 |

p is Fisher's exact test against the trial arm.

- **Direction:** against both same-era controls the trial is lower on loading before the first edit and on plans written before code. Against the earlier arm it looks better, but that arm predates the hooks that raised loading on `main`.
- **Moved text:** `delivery-lifecycle.md` holds most of the old entrypoint and was never opened in the trial. Rare-path situations did occur: 7 trial sessions sent content to shared docs or chat and 10 deleted code files, and `artifact-egress-confidentiality.md` and `feature-deprecation-cascade.md` were opened 0 times. Controls also almost never open those references, but there the text sits in the loaded entrypoint.
- **Corrections:** user messages with a correction marker are too sparse to compare (trial 1 of 409, earlier `main` 3 of 2,008).
- **Power:** none of the differences is significant at 26 sessions with code edits. Detecting 31% against 19% at 80% power needs about 200 sessions with code edits per arm, so another daily trial cannot decide this either.

## Decision

The trial does not pass validation step 4 in `design.md`. Both behavior measures are worse against both same-era controls, and the most plausible mechanism is the failure mode named in the charter in `plan.md`: text moved into a reference that agents do not open. The branch is not merged; it stays as the record of this round.

The branch is also stale: 96 commits behind `main` at d0e9b34, with merge conflicts in the entrypoint, `source-register.md` and both specs/065 obligation files. The entrypoint and `delivery-lifecycle.md` still cite `owner-dispatch.sh ci`, which `main` has since removed.

A later slimming round keeps behavior-shaping lines, such as the plan gate and the rare-path triggers, in the entrypoint or turns them into hooks. It decides on the delivery suite with more runs per arm, with plans written before code as a measure, rather than on a daily trial.

The trial wrapper, its `.zshrc` source line and the pinned trial checkout were removed from the owner's main machine on 2026-11-03.
