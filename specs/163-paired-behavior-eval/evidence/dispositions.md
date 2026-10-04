# Round 163 review dispositions

Commit ids below name what each pass reviewed. The branch was later rebuilt
with identical trees so that the register changes in one commit after the
code, so those ids stay in the review results but are no longer on the
branch.

Review (independent, codex, release depth) and challenge (adversarial, codex,
release depth), both on candidate `7574e97`, the branch before the fixes and
before the history was reordered to keep the register row last. The fixes
landed together in the commit "Harden paired-eval validity, isolation and
recovery"; the records were regraded with it (no record changed) and the
write-up corrected. 24 findings were fixed; one is an accepted limitation.

| Pass | # | Severity | Finding | Disposition |
| --- | --- | --- | --- | --- |
| challenge | 1 | P1 | canary seen only in a tool result left the run valid | fixed: the canary is checked against the whole stream (`instruction_file_canary_seen`); isolation and batch tests |
| review | 2 | P1 | same as challenge 1 | fixed with it |
| challenge | 2 | P1 | success, then more activity and a crash still counted | fixed: `activity_after_last_result`; isolation and batch tests |
| review | 1 | P1 | same as challenge 2 | fixed with it |
| challenge | 3 | P1 | regrade read the canary from an agent-writable world file | fixed: records keep the token, snapshot and plugin path; legacy records regrade only from an untouched canary file; class sweep also moved grading off the sample's own git config |
| challenge | 4 | P1 | exports left without a frozen plan were reused under new refs | fixed: with no plan.json, exports are rebuilt |
| review | 4 | P1 | same as challenge 4 | fixed with it |
| challenge | 5 | P1 | reports counted any record.json | fixed: records must match the plan hash, the frozen inventory and their own path |
| review | 5 | P1 | shared exports let one run change the treatment of later runs | fixed: each run gets a private copy; a run that edits it is invalid (`plugin_export_changed`) |
| review | 6 | P1 | two invocations could share one output root | fixed: exclusive lock on the output root |
| challenge | 6 | P1 | a detached descendant outlives the process-group kill | accepted limitation, now stated in the tool header (no defence against a hostile agent); no process from the first batch survived it; sandboxing stays a follow-up |
| challenge | 7 | P2 | output inside a sibling linked worktree was not refused | fixed: every registered worktree root is refused |
| review | 3 | P1 | same as challenge 7 | fixed with it |
| challenge | 8 | P2 | trace segmentation split inside quotes and comments and skipped substitutions | fixed: shell-aware segmentation (quotes, comments, substitutions, a hash inside a word) with the reported near-miss cases as tests |
| review | 8 | P2 | same as challenge 8 | fixed with it |
| challenge | 9 | P2 | integrity list truncated, directory symlinks missed | fixed: full list stored, report truncates only its display; directory symlinks in manifests |
| review | 11 | P2 | same as challenge 9 | fixed with it |
| review | 7 | P2 | a calibration that did not fire still let samples count | fixed: the batch runs no sample unless the calibration finished and fired |
| review | 9 | P2 | JSON written in place could tear | fixed: atomic writes for plan, records, snapshots, calibration, integrity, results and report |
| review | 10 | P2 | an interrupt during setup could still launch a run | fixed: spawning happens under a lock and is refused once shutdown begins |
| review | 12 | P2 | source-repo reads and the version probe kept CLAUDE* variables | fixed: one inherited-environment sanitizer for every child |
| challenge | 10 | P2 | no per-sample evidence for the post-batch readings | fixed: `batch-records.json` with both readings per sample |
| challenge | 11 | P2 | "neither helped nor hurt" treated no separation as equivalence | fixed in the write-up, the PR text and the register row |
| review | 13 | P2 | same as challenge 11 | fixed with it |
| review | 14 | P2 | lanes still pending in the committed record | closed by the final lanes on the final candidate |

## Delta review of the fixes (`pass3-delta.json`)

Run on `0539ab9`, a path slice of the candidate (tool, tests, register row and
round records). The slice was a workaround for the packet limit; the protocol's
delta packet is the diff from the reviewed commit, which the next pass used.

| # | Severity | Finding | Disposition |
| --- | --- | --- | --- |
| 1 | P1 | a truncated line after the last result left the run valid | fixed: a malformed line makes the stream unfinished (`malformed_stream`); isolation and batch tests |
| 2 | P1 | the legacy canary fallback accepted a re-tokened file | fixed by deletion: regrading reads only runner-recorded inputs and refuses a record without them; the first batch's records already hold theirs, taken from untouched canary files and marked in `legacy_inputs` |
| 3 | P1 | an output root without plan.json lost its arms/ directory | fixed: the runner only touches an output root it created (owner marker) or already planned in, and refuses one holding other files |
| 4 | P2 | a worker past its stop check could still spawn | fixed: the utilization stop is checked and set under the spawn lock |
| 5 | P2 | single-quoted substitutions and multi-command `bash -c` payloads are misread | accepted and documented in the tool header: the third successive round of shell-parsing near-misses, in a check labelled heuristic whose outcome is graded directly from the world, so the class stops being patched |
| 6 | P2 | worktree paths with special characters were quoted | fixed: `git worktree list --porcelain -z` |
| 7 | P2 | integrity was lost on interrupted or failed exits | fixed: recorded on every exit |
| 8 | P2 | the slice omitted unchanged files and the projection | the unchanged files were covered by the first two passes; the next delta pass reviews the diff from the reviewed commit |
| 9 | P2 | lanes were still pending | closed when the final lanes on the final candidate finished |

## Second delta review (`pass4-delta.json`)

Run on the diff from `0539ab9` with the previous pass's P1 findings carried
verbatim as open items.

| # | Severity | Finding | Disposition |
| --- | --- | --- | --- |
| 1 | P1 | records an older regrade built from world-side inputs were still accepted | fixed by deletion: regrading refuses any record whose inputs were legacy-derived; the first batch, last regraded before this, is frozen as recorded |
| 2 | P1 | the ownership marker was written before an existing plan was validated | fixed by deletion: the runner no longer deletes exports and needs no marker; a non-empty output root without a plan from this tool is refused |
| 3 | P1 | integrity on every exit was not established, and inspecting a damaged export could raise over the original failure | fixed: an export that cannot be inspected is recorded as unknown with its reason, evidence writing after a failure never replaces that failure, and the claim is scoped to every exit once runs may have started; tests for both |

The ownership and legacy findings were the third round of each class, so both
converged by removing the capability rather than refining it again.

## Third delta review (`pass5-delta.json`)

Run on the diff from `ed2d10a`.

| # | Severity | Finding | Disposition |
| --- | --- | --- | --- |
| 1 | P1 | integrity on every exit could not be established from the bounded packet, and a mocked inspection error proved nothing about real traversal | fixed: `os.walk` skipped unreadable directories silently, so traversal now raises and the record says unknown; tests use a real unreadable export directory and an interrupt during the batch; the next pass received the batch lifecycle as appended context |

## Fourth delta review (`pass6-delta.json`)

Run on the diff from `7e6dad9`, with the batch lifecycle's current source
appended after the candidate.

| # | Severity | Finding | Disposition |
| --- | --- | --- | --- |
| 1 | P1 | an interrupt after the last worker finished, during pool shutdown or the integrity write, bypassed the handler, so "only SIGKILL skips it" was false | fixed: shutdown, integrity and report run in a `finally` section on every exit after the first launch, with SIGINT and SIGTERM latched while they are written and a retry if a signal lands before the latch; a latched signal exits 130 after the evidence is complete; regression for both signals during the integrity write |

### Review continuation checkpoint

The next delta pass is the fifth. What changed: the finalization rewrite above,
nothing else in the tool. Integrity-on-exit has returned three times (second,
third and fourth delta passes). Decision: keep it, since the always-run
finalization closes the class by construction instead of patching one more
path; if it returns again, narrow the claim to normal completion, because a
changed export is still caught on the next invocation, where the plan hash,
which binds each export's digest, refuses a mismatch. The next pass should
establish whether any exit after a launch can skip or replace the evidence.

### Self-review before the fifth delta pass

| # | Severity | Finding | Disposition |
| --- | --- | --- | --- |
| 1 | P1 | until the finalization latch was installed, signals still raised asynchronously, so whether an interrupt at that boundary skipped the evidence depended on where the interpreter checks for signals | fixed by construction: from before the first launch, SIGINT, SIGTERM and SIGHUP only latch (a signal the caller ignores stays ignored), waits poll the latch, and the calibration runs in the pool so it stops the same way; tests send real signals mid-run and mid-calibration |
| 2 | P1 | after a hard kill, `--report-only` rewrote the report with an earlier invocation's integrity record | fixed: every report recomputes integrity against the manifest the plan froze, and a manifest that does not hash to the plan's export digest is recorded as unknown |
| 3 | P1 | a terminal interrupt also reached the runner's own git, so a grade in progress could fail and be recorded for a run that had finished | fixed: the runner's git and setup commands run in their own session |

The class came back a fourth time, found in self-review rather than by the
reviewer. Instead of narrowing the claim, the fix removed its dependence on the
exit path: no handler raises once runs may start, and integrity is recomputed
by every report instead of written by whichever exit is taken. Only an
uncatchable kill skips the final report; the next rerun or `--report-only`
then writes a current one.

## Fifth delta review (`pass7-delta.json`)

Run on the diff from `384b532`, with the batch lifecycle's current source
appended after the candidate.

| # | Severity | Finding | Disposition |
| --- | --- | --- | --- |
| 1 | P1 | the spawn check could not see a latched signal, so for up to one wait interval another worker could still start a run | fixed, and the claim narrowed to what the design guarantees: the spawn check reads the latch, so no run starts once a signal is latched. The latch is set when the main thread handles the signal, at most one 0.2 s wait after it arrives; a run that passed the check before then is killed with the others and records nothing. Work submitted after a signal needs no separate check, because every run passes the spawn check. Regression: the check refuses with a latched signal, with shutdown begun and with the guard stopped, and starts a run when nothing is tripped. The suggested synchronized test would exercise the window that is now a stated limit, so the guard is pinned directly instead |

### Review continuation checkpoint (after five delta passes)

What changed since the last checkpoint: the latch from the first launch,
report-time integrity, the runner's own commands in their own session, and the
spawn check reading the latch. Integrity on exit did not come back in this
pass. Starting a run after a stop or an interrupt has now come back three times
(review 10, the third delta pass's 4, this pass). The recurrence rule applies,
so the claim is narrowed to what the design guarantees instead of adding a
thread-independent signal channel: no run starts once a signal is latched, and
the lag between arrival and latching is bounded and stated. If the class comes
back again, that claim is removed too, leaving only that every run alive at
shutdown is killed and records nothing. The next delta pass covers this change.

## Sixth delta review (`pass8-delta.json`)

Run on the diff from `9fbfe33`, with the batch lifecycle's current source
appended after the candidate. Passed with no findings. It noted that the 0.2 s
figure bounds the main thread's wait, not every delay between a signal and its
handling; during the run phase the main thread is either in that wait or
running Python code, so the stated latch interval holds wherever a run could
still start.

## Found after the sixth delta pass

Reading the first batch's plugin-arm transcripts for a follow-up showed every
Stop hook reporting "Delivery handoff reminder unavailable" and the
skill-loading checkpoint reporting unavailable. The cause was the tool's own
`--no-session-persistence` flag: without a transcript those hooks fail open.

| # | Severity | Finding | Disposition |
| --- | --- | --- | --- |
| 1 | P1 | the runs disabled session persistence, so the plugin's transcript-reading hooks did not run and the plugin arms measured a degraded plugin | fixed: persistence stays on; after each run, calibration included, the files named by that run's own session ids move from `~/.claude/projects` into the sample directory, a project directory is removed only when empty, and a run without a transcript is invalid. Proven by a paired probe (only the flag differs) and a live smoke (both runs valid, nothing left under `~/.claude/projects`, no "unavailable" message). The first batch carries a caveat in `validation.md`, the PR text and the register row instead of a rerun |

## Seventh delta review (`pass9-delta.json`)

Run on the diff from `6e6b5b4` (the tree the sixth delta pass reviewed), with
the transcript functions appended after the candidate.

| # | Severity | Finding | Disposition |
| --- | --- | --- | --- |
| 1 | P1 | a rerun deleted every `transcript-*` entry in the sample directory, including files the runner never created | fixed by deletion: the rerun cleanup is gone. An interrupted attempt's transcripts stay as its evidence, and a record lists only the files its own run collected. Regression: an operator's `transcript-notes.txt` and `transcript-analysis/` survive a rerun, and each record's list matches the session ids in its own stream |
| 2 | P1 | a session directory without its `.jsonl` transcript counted as persisted | fixed: validity needs a collected `.jsonl` transcript, so a directory alone stays `transcript_missing`, on regrade too. Regression with a fake session that writes only the directory |
