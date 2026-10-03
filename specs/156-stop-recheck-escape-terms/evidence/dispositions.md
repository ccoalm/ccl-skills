# 156 and 157 review dispositions

Both rounds ship in one pull request and share these passes. R0 evidence for
every pass: `check-ccl-skills.sh` against `origin/main` reported
`r0_status=private-ok` (`alias_audit_ok`) on the reviewed candidates and on the
final content commit `04f700e`.

## Pass 1 — review (kimi), base `origin/main`, reviewed commit `44262fd`: 1 × P2

| # | Finding | Disposition | Where |
| --- | --- | --- | --- |
| 1 | The red-CI section moved into the playbook still points at "the classes above" and "the flaky rule below", which the playbook does not contain | fixed: the copy names the entrypoint's Isolate-step test-evidence classes and its flaky-test rule; the four cause classes stay verbatim | `diagnosis-playbook.md`, `bb25b83` |

## Pass 2 — challenge (codex), base `origin/main`, reviewed commit `bb25b83`: 2 × P1, 2 × P2

Focus: whether the new text licenses unauthorized actions or overrides an
explicit limit; whether the merge guard's help parse can release a merge
without a grant or let a real merge skip consuming one; whether crafted or
batched prompts pass as a notification to keep or arm a grant; bash 3.2 and
quoting; loss in the moved red-CI text.

- Gate-fireability applicability: yes — the round edits when the merge gate
  consumes and revokes grants and when Stop reminders fire.
- Item 9 exercised: yes — the recorded `challenge_focus` in
  `pass2-challenge.json` asks for paths that keep or release a grant while
  skipping the gate's trigger, and finding 1 is such a path.

| # | Sev | Finding | Disposition | Where |
| --- | --- | --- | --- | --- |
| 1 | P1 | A typed stop inside a forged `<task-notification>` wrapper reaches the early exit, so the grant survives an explicit stop | narrowed in `ca5f595` (only a block whose every line is a single-line tag element was skipped); that narrowing was broken by pass 5, and the exemption was deleted in `2b20fe0` | `merge-authorization-prompt.sh`; see pass 5, finding 1 |
| 2 | P1 | A budget the user explicitly adopted ("keep that ceiling") is classified as the agent's estimate and may be exceeded | fixed: a count binds once the user adopted it as a limit; plain assent to the work does not adopt it | continuation gate, session policy, both Stop reminders; `ca5f595` |
| 3 | P2 | The diagnosis probe accepts a blocked fix, push and MR when the blocked line also names the merge | fixed: both diagnosis probes grade an explicit `next:` marker; the walk pins the escaping output as FAIL | `body-compliance-eval.rb`, grading walk; `ca5f595` |
| 4 | P2 | Evidence gap: help-probe containment for compound commands, quoted values and the no-grant case is not shown | fixed with added evidence: guard cases for `--help` compounded with a merge, a quoted `--help` message value and a help probe without a grant | `test_guard_merge_authorization.sh`; `ca5f595` |

## Pass 3 — review (opencode), base `origin/main`, reviewed commit `ca5f595`: 1 × P2

| # | Finding | Disposition |
| --- | --- | --- |
| 1 | Evidence gap: the packet rendered only about the first 720 lines of the 113,378-byte candidate, so the hooks, tests, records and version bump after that point were unread | coverage gap, not a defect: pass 2 read the whole branch up to `bb25b83`, and passes 5 and 6 read every later change |

## Pass 4 — path-scoped reviews, base `origin/main`, reviewed commit `bad610e`

Packets A (Stop hook and its tests) and B (merge hooks, their tests and notes)
were refused before review, because the extraction lane requires a file owned
by `skill-extraction-workflow` in each packet. They are inconclusive and not
counted; pass 5 covers their files.

Packet C (codex: session policy, continuation gate, `defect-diagnosis`,
playbook, extraction reference, probes, grading walk, 156 plan): 1 × P1, 2 × P2.

| # | Sev | Finding | Disposition | Where |
| --- | --- | --- | --- | --- |
| 1 | P1 | The packet has no hunks for the hooks, their tests or the version bump, so landing it would leave the hooks unchanged | source-refuted: the packet was path-scoped by design; the same candidate carries the hooks, tests and bump, read by passes 1, 2 and 5 | `git diff --stat origin/main bad610e` |
| 2 | P2 | Phase B lists its stops as "stop only for" four cases, so "fix locally, do not push", a cost cap, a destructive non-production repair or a purchase matches none of them | fixed: every explicit user limit and existing gate stops the step it covers, and the cases are examples; the continuation gate, session policy and both reminders say the same | `defect-diagnosis/SKILL.md`; reminder case red on the previous hook; `4808a50` |
| 3 | P2 | Evidence gap: the validation record, replay artifacts and register rows are not in the packet | source-refuted: they are in `evidence/validation.md`, `evidence/recheck_replay.py` and the source register, outside this packet's paths | — |

## Pass 5 — delta review (codex), base `bb25b83`, reviewed commit `4808a50`: 1 × P1, 2 × P2

The packet carried pass 2's fixed findings and pass 4's Phase B finding as
open items. It found Phase B and the adopted-limit wording resolved, and the
grader escape closed.

| # | Sev | Finding | Disposition | Where |
| --- | --- | --- | --- | --- |
| 1 | P1 | A stop written as a tag element (`<summary>先别合并</summary>`) inside notification markup still skips revocation, so pass 2's finding 1 stays open | fixed by deletion: the second same-class break of a predicate that only stands in for host origin, with no origin field in the payload; the prompt hook is main's again, a notification revokes like any message, and the hook notes require foreground CI waits during a granted merge sequence | `merge-authorization-prompt.sh`, `hook-authorization.md`, 157 plan; prompt cases fail twice on the exemption version; `2b20fe0` |
| 2 | P2 | Evidence gap: the packet has the new guard cases but not the guard implementation | source-refuted: the guard is unchanged since `1dbfca1`, whose hunks pass 2 read; the compound, quoted-value and no-grant cases pass (493/493) | `test_guard_merge_authorization.sh` |
| 3 | P2 | Evidence gap: the document check depends on the transcript scan, and fixtures cover only Write | fixed: the records bound the check to file-edit tool calls (shell writes are not seen); Edit and MultiEdit cases added; a NUL-bearing path never reaches the check (the scan drops it), pinned by a control case | `host-input.py` tests, 156 plan; `2b20fe0` |

Found between passes, when the hook ran in a live session: the post-merge
cleanup reminder fired after `gh help pr merge`, the help form the guard's
denial recommends. Fixed in
`2b20fe0` (three cases red on the previous hook).

## Pass 6 — delta review (codex), base `4808a50`, reviewed commit `2b20fe0`: 1 × P1, 4 × P2

Run through the code-review controller with the changed non-evidence paths,
because the extraction wrapper refuses a packet without a file owned by
`skill-extraction-workflow` and this delta had none.

| # | Sev | Finding | Disposition | Where |
| --- | --- | --- | --- | --- |
| 1 | P1 | Evidence gap: with the exemption removed, the packet lacks the arming and revocation code and main's hook, so it cannot show that notification text never arms or that a stop revokes | source-refuted: the hook is byte-identical to main (`git diff origin/main` is empty); main's suite plus three new cases pass (119), and the new cases fail twice on the exemption version | `test_merge_authorization_prompt.sh` |
| 2 | P2 | The help strip's optional prefix can swallow a real merge written before a help mention (`gh pr merge 45 --merge # gh help pr merge`) | fixed: only the literal help invocation is removed; a merge-first comment case and a command-substitution case fail on the previous strip | `remind-post-merge-cleanup.sh`; `04f700e` |
| 3 | P2 | Evidence gap: the NUL-path control cannot show that an exception inside the document check keeps the continuation reminder | fixed: the delivery reminder is computed first and any document-check failure is contained; an in-process case that makes the check raise fails on the previous hook | `host-input.py`; `04f700e` |
| 4 | P2 | Evidence gap: the ledger locator change is not shown to keep its text or match the renderer | source-refuted with evidence: the render output is byte-identical to the checked-in ledger, the audit prints `audit_ok rows=1240 unresolved=0`, and line 160 at `4808a50` equals line 158 at `bad610e` (sha256 `101a6195…`) | `obligation-preservation.md` |
| 5 | P2 | Evidence gap: the full lane, public sanitization and `git diff --check` are not shown for the candidate | fixed with evidence: all run on the final content commit (Final verification below) | — |

## Pass 7 — delta review (codex), base `2b20fe0` (full-context diff), reviewed commit `04f700e`: 1 × P1

The packet carried pass 6's findings 1–3 as open items. It found the prefix
erasure fixed, ordinary document-check exceptions contained with the
continuation reminder kept, and `TranscriptTruncated` still reaching the
overflow notice.

| # | Sev | Finding | Disposition | Where |
| --- | --- | --- | --- | --- |
| 1 | P1 | Evidence gap, repeating pass 6's finding 1: without the prompt hook, the guard's grant consumer and main's hook in the packet, notification revocation and arming cannot be confirmed | verification pass 8 read the complete prompt hook, its suite and the guard (see below) | — |

## Pass 8 — verification review (kimi, after a codex timeout), complete files at `04f700e`

Packet: the prompt hook (byte-identical to main), its full suite and the full
merge guard, rendered as added files, with pass 7's finding as the open item.

Result: passed (kimi; the codex attempt timed out and was not counted). It
traced the single, batch and target-goal arming paths, revocation and
suspension, and the guard's parse, deny and consume sequence, and found no
prompt or command path by which a grant survives a user stop, is armed from
notification text, or is consumed without a fresh, uid-owned, session-scoped
sentinel and a current epoch. A multi-line prompt empties the only string the
directive grammar matches, so nothing in notification markup arms; single-line
markup fails the anchored grammar. This closes pass 6's finding 1 and pass 7's
finding 1.

The implementer's reading of the code agrees: `merge-authorization-prompt.sh` blanks the matched text
for any prompt containing a newline, advances the epoch for every non-neutral
prompt, and keeps a target goal only across an exact single-line neutral word.

## Pass and commit map

| Pass | Mode | Base | Reviewed commit | Result |
| --- | --- | --- | --- | --- |
| `pass1-review.json` | review | `origin/main` | `44262fd` | findings (1 × P2) |
| `pass2-challenge.json` | challenge | `origin/main` | `bb25b83` | findings (2 × P1, 2 × P2) |
| `pass3-review.json` | review | `origin/main` | `ca5f595` | findings (1 × P2, coverage) |
| `pass4-review-scoped.json` | review, path-scoped (packet C) | `origin/main` | `bad610e` | findings (1 × P1, 2 × P2) |
| `pass5-delta.json` | delta review | `bb25b83` | `4808a50` | findings (1 × P1, 2 × P2) |
| `pass6-delta.json` | delta review (code-review controller, path-scoped) | `4808a50` | `2b20fe0` | findings (1 × P1, 4 × P2) |
| `pass7-delta.json` | delta review (code-review controller, full-context diff) | `2b20fe0` | `04f700e` | findings (1 × P1, evidence gap) |
| `pass8-verify.json` | verification review (code-review controller, complete files) | — | `04f700e` | passed (kimi) |

## Final verification

On the final content commit `04f700e`:

| Check | Result |
| --- | --- |
| `make test` (`CCL_SKILL_BASE_REF=origin/main`) | exit 0 |
| Heavy regression lane (`--heavy-only`) | `regression_heavy_lane_ok: 10 suites` |
| `make npm-publish-dry` | two full runs, with machine load 10–12 from other sessions, failed only on timing: the OpenCode saved-runner test exceeded its 20 s budget both times (25.8 s, 26.3 s; it passes alone in 4.1 s), and in the second run `quarantine-faults.test.mjs` failed after 11.5 minutes. Package code and tests are byte-identical to main apart from the version fields. A sequential run (`--test-concurrency=1`) passed 431 of 432; its one failure was another timing budget (10.0 s against a 10 s limit). Pack verification passed 11/11, and `npm pack --dry-run` builds `@ccoalm/ccl-skills@0.18.9` (709 files, 3.7 MB). CI `npm-packages` on `04f700e`, the same tests on an unloaded runner: pass. |
| `check-ccl-skills.sh` against `origin/main` | `r0_status=private-ok`, `ccl_skill_check_clean_ok` |
| Hook suites | guard 493, prompt 119, cleanup reminder 57, Stop and host-input 80 |
| `git diff --check`, shared Git surface gate | clean; `shared_git_surface_gate_ok` |
| Public sanitization with the evidence staged | `public_sanitization_ok` |
| CI on `04f700e` | all eight required checks pass |

No P0/P1 remains undispositioned. The last delta pass covered the last content
commit; later commits carry only this evidence.
