# Finding dispositions

Review and challenge results for this round are in this directory. Each
finding below was checked against the code it names before it was fixed or
answered.

## Challenge (pass 2)

| Finding | Check | Disposition |
| --- | --- | --- |
| C1 (P2) the sweep accepts the scan without its success condition | Confirmed: a surface with `status --ignored` and the pointer but no exit-0 requirement passed, and the walk's compliant decoy had none | Fixed: the sweep also requires `exit 0`; every restating surface already stated it. The compliant decoy now carries it and a decoy without it reds the sweep. |
| C2 (P2) the pointer check matches the file name only | Confirmed: `references/merge-and-teardown.md` in a `docs/` page passed although it does not name worktree-isolation's reference | Fixed: outside the worktree-isolation package the sweep requires `worktree-isolation/references/merge-and-teardown.md`; the package's own files may use the package-relative path. A file-name-only pointer in `docs/` reds; the same pointer inside the package stays green. |
| C3 (P2) order rows compare first occurrences anywhere in the file | Confirmed: moving the scan command ahead of the Closeout Cleanup section kept the order row green | Fixed: order rows name their section and compare positions inside it. The walk reorders inside the section and relocates an order row's first line ahead of the section; the sabotage that compares file-wide now fails the walk (it passed before this relocation was moved ahead of the section). |
| C4 (P2) listing and read errors fail open | Confirmed: `find` ran inside process substitution with its status unchecked, and a `grep` read error counted as no match | Fixed: listing failures and read errors fail the sweep (the `find` listing was later replaced by the git-only listing, see D1 and D2). The walk adds an unreadable directory and an unreadable file (skipped when running as root, where permissions do not bind). |
| C5 (P2) the packet omits unchanged helpers and surfaces | Packet boundary, not a defect: the helpers (`assert_in_section`, `assert_same_line`, the root resolver) are unchanged and already walked by the escalation-pin suite, and the surface enumeration is recorded in `validation.md` | No code change. |

## Review (pass 1)

The first run ended inconclusive on every client (codex and kimi timed out at
600 s, opencode returned no final text) and does not count as a review. Its
partial transcript raised the same exit-0, pointer and fail-open points as the
challenge. The rerun on the final candidate used a longer per-attempt timeout.

| Finding | Check | Disposition |
| --- | --- | --- |
| R1 (P2) the sweep scans a fixed list of directories | Confirmed: a Markdown file in a new top-level directory was never listed | Fixed: the sweep lists what git tracks or would track, so a new top-level directory is covered (a plain-copy listing added here was later removed, see D2). A decoy in a new top-level directory reds. |
| R2 (P2) the exit-0 check accepts the phrase anywhere | Confirmed: an `exit 0` in an unrelated sentence satisfied it | Fixed: the requirement must sit on the same line as the scan, which every restating surface already does. A decoy with an unrelated `exit 0` reds. |
| R3 (P2) the walk's fixture runs write temp files outside its directory | Confirmed: the sweep's listing file went to the inherited `TMPDIR` | Fixed: the walk runs the fixture with `TMPDIR` set to its own directory, and the fixture removes its listing on exit. |
| R4 (P2) the packet cannot show the retargeted sections exist | Evidence gap | Recorded in `validation.md`: each named section's line in its target file, and the Markdown link check. |
| R5 (P2) the lanes are pending and the sabotage table lists six of twelve cases | Evidence gap | `validation.md` records the final lanes and the full sabotage table. |

## Delta (pass 3)

| Finding | Check | Disposition |
| --- | --- | --- |
| D1 (P1) git warns about an unreadable untracked directory and still exits 0 | Confirmed: `ls-files` printed the warning on stderr with status 0 and the directory's files were missing from the list | Fixed: anything git reports while listing fails the sweep as an incomplete listing; the walk adds an unreadable untracked directory in git mode. |
| D2 (P2) a failed `rev-parse` silently selects the plain-copy listing | Confirmed: any discovery error took the fallback, which prunes paths a checkout might track | Fixed by removal: the fallback is gone. The sweep lists only through git and fails outside a git work tree; the one other runner of the fixture, the escalation-pin walk, now builds a repository copy. |
| D3 (P2) a file name starting with a newline empties the parsed offender list | Confirmed: the verdict was parsed from the classifier's text | Fixed: the classifier reports through its exit status and escapes control characters in printed names; a newline-named decoy reds with the escaped name. |
| D4 (P2) the walk's `git commit` inherits signing and hook settings | Confirmed: the commit ran with the user's git configuration | Fixed: no commit; `git add` builds the index the listing and the index probe need. |
| D5 (P2) the packet omits the comparator, mutation and cleanup bodies | Packet boundary: the delta packet held only changed hunks | No code change; the implementations are in the reviewed scripts and their behavior is recorded in `validation.md`. |
| D6 (P2) the register row claims seventeen sabotages while the run was in progress | Confirmed: the claim preceded the completed run | Fixed: the row states the count from the completed suite on the final code. |
| D7 (P2) no full-lane results for the candidate | Evidence gap at packet time | `validation.md` records the final `make test`, heavy lane and sanitization results. |

## Delta (pass 4)

| Finding | Check | Disposition |
| --- | --- | --- |
| E1 (P2) a stderr of only newline bytes is stripped and read as clean | Not a git behavior: git's listing diagnostics carry text, and the sweep's contract is a diagnostic git prints | No change. Recorded as residual risk under the repository's trusted-contributor model for its own gates, alongside the prose blind spot. |
| E2 (P2) inherited `GIT_DIR` or `GIT_INDEX_FILE` would send the walks' git writes elsewhere | Confirmed by experiment: with `GIT_DIR` pointing at a scratch repository, the previous walk staged 652 of its copy's files into that repository's index | Fixed: both walks clear inherited git variables first, as the repository's other git-writing suites do; rerun with the same `GIT_DIR`, both walks pass and the scratch index keeps its single entry. The escalation walk also binds `TMPDIR` to its own directory. |
| E3 (P2) the sabotage run and final-candidate lanes were pending | Evidence gap at packet time | `validation.md` records the completed sabotage suite and the final lanes. |

## Agent delta after pass 4

The only change after pass 4 clears inherited git variables in both walks and
binds the escalation walk's `TMPDIR`. Checked by the scratch-repository
experiment recorded for E2 (652 files staged before, none after) and by both
walks passing on the final candidate; no external pass was run for this
change.

## Same-class recurrence

C1, C2, C4, R1, R2, D1, D2 and D3 share one shape: the sweep's predicate was
looser than the guard it claims to enforce. Once the review repeated the
challenge's shape, the sweep was reworked as a whole rather than patched one
finding at a time: every dimension
of its predicate was walked — which files it lists, what triggers a check, the
scan, the exit-0 requirement and where it sits, the pointer, exclusions, error
handling, vacuity, and precision — and each now has a decoy or a failure probe
in the walk and a sabotage that the walk catches. The plain-copy fallback was a capability that served only a test copy and
kept producing findings (D2), so it was deleted rather than hardened. Deleting
the sweep itself was considered and rejected: on the base text it found three live restatements
without the guard, which per-surface pins cannot catch for a surface added
later.
