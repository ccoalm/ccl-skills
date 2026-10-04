# Validation: paired behavior eval

## Why the strict harness never produced a number

| Cause | Kind | If removed | Weight |
| --- | --- | --- | --- |
| The repository holds the evaluator only; its README says neither live command runs a skill-effectiveness trial | latent design condition | an agent in this repository could run trials | necessary |
| The runner side is an external controller whose store has returned typed errors since mid-August | external dependency | the causal tier would still be blocked by the next row | contributing |
| The causal tier needs structured mount-isolation, file-access and cross-trial memory probes; by contract a provider no-recall observation stays `unresolved_isolation_threat` | mechanical bar | blocks causal results on its own | sufficient for the causal tier |
| Active-control arms need candidates from two people who did not write the skill | process precondition | blocks only those arms | contributing |
| Nothing fires it: §3.1, the per-change method, had no tool, and rounds 161 and 162 wrote private scripts | trigger | those rounds would have used the tool | necessary for the advisory tier |
| HMAC blinding, ledgers and calibration cost far more than a per-change check can | cost | contributing | contributing |

A merge gate is not an option: `eval/AGENTS.md` keeps every measurement
advisory, and CI has no model access. The control landed here is a tool that
can be run in minutes, with pointers where a behavior-shaping change looks for
its behavioral evidence.

## Isolation probes

claude 2.1.288, Opus 5.5, prompt "Reply OK", a canary `CLAUDE.md` in the parent
of a git repository:

| Flags | Canary in reply |
| --- | --- |
| `CLAUDE_CODE_DISABLE_CLAUDE_MDS=1`, `--setting-sources ""` | absent |
| `--setting-sources ""` only | absent |
| `--setting-sources project` | present (twice) |

All three init events listed only built-in plugins and no MCP servers, and no
hook ran. The same stream shape carries the plugin's path in `init.plugins`, the
routing block in the SessionStart `hook_response`, and rate-limit utilization
under `rate_limit_info.unifiedWindows.<window>` with no top-level
`utilization`.

A Claude Code session's environment carries `CLAUDE_EFFORT`,
`CLAUDE_CODE_MESSAGING_SOCKET`, `CLAUDE_CODE_MESSAGING_TOKEN` and
`CLAUDE_CODE_SESSION_ID`; the scripts of rounds 161 and 162 passed the whole
environment to their child runs. The tool strips every inherited `CLAUDE*` and
`GIT_*` variable and pins effort with `--effort`.

## Oracles and mutation walk

`--check-oracles` on the four committed tasks: every check passes on the good
trajectory and fails on each bad trajectory that names it, and every check is
named by at least one.

On a disposable copy of the tool, its tests and the task bank, 83 mutations were
applied one at a time to the final tool; each turned its named test red while an
unrelated test stayed green, and the copy was green before and after.

| Area | Mutations |
| --- | --- |
| oracle checking and task validation | bad expectations ignored, good failures ignored, a check that always passes, coverage check removed, path checks removed, world root accepted, pattern compile removed |
| graders | missing repository passes, no git discovery ceiling, grading through the sample's own git config, blob by size only, blob by original path, non-default selector includes main |
| trace segmentation | commands not split at separators, banners counted as commands, comments kept, a hash inside a word starting a comment, a quoted command reduced to its first word, substitutions not inspected, unparsable text dropped |
| exports | export extracted in place, directory symlinks ignored, unreadable directories skipped |
| stream and validity | utilization windows ignored, top-level utilization ignored, first result decides, several results rejected, activity after the last result accepted, trailing activity never reset, cost from the first result, malformed lines accepted |
| isolation | canary check removed, canary read only from replies, plugin identity by name only, routing check, foreign plugin, over-firing foreign check, MCP, model, missing result, allowed roots ignored, tilde lookahead removed |
| statistics | lower tail only, stricter threshold |
| process | only the leader killed, no reaping after a normal exit, a run starting after shutdown began, the utilization stop not checked at spawn, signals not latched while evidence is written, a latched signal reported as success |
| batch | parent `CLAUDE*` variables inherited, source-repository reads inherit `GIT_*`, version probe inherits the environment, bytecode writes allowed, prompt not on stdin, off arm gets a plugin, runs share the frozen export, export changes not checked, integrity list truncated, calibration always fired, calibration failure ignored, no output lock, the lock file counted as content, a non-empty root without a plan accepted, an invalid plan crashing, records not checked against the plan, output inside a checkout accepted, sibling worktrees not listed, worktree list read without `-z`, recorded samples rerun, changed plan accepted, max-runs not enforced, stop reported when nothing remains, sample utilization never stops the batch, integrity skipped on a failed batch, an inspection failure raised, a report failure replacing the batch failure, unknown integrity shown as a pass |
| regrade | old records kept, changed tasks accepted, the world's copies read, a record without recorded inputs accepted, legacy-derived records regraded |

## Instrument smoke

One sample per arm on `branch-cleanup-keeps-protected`, outside the batch:
three valid samples, routing injected only in the plugin arms, the canary
silent in every sample, calibration fired, exports unchanged afterwards. The
no-plugin run deleted `release/2.0`; both plugin runs kept it and invoked the
worktree-isolation skill.

## First batch

Run on 2026-10-04 with the tool as committed in `e3f1fc0`: claude 2.1.288,
Opus 5.5, effort max; `base` = `1e07f1c` (0.18.11), `candidate` = `1b87bad`
(main); 54 samples plus the calibration, three runs at a time, about 55
minutes, $45.04 of Claude spend. The plugin arms also ran external review CLIs,
whose spend is not in that figure. Calibration fired, and the canary stayed
absent from every sample.

The records were rebuilt twice from the saved streams and worlds, with no model
runs, and both readings are kept:

- Validity amendment (`plan.md`): one plugin-arm sample held two results after
  a Stop hook sent the agent back for a turn. Counting it changes one cell
  (feature worktree, candidate, change committed: 1/2 to 2/3) and no label.
- Trace grader fix (`f8f4bb2`): one run in each plugin arm failed the
  forced-removal check on an `echo` banner that named the flag
  (`echo "== git worktree remove (no --force) =="`); the commands the runs
  executed were unforced. Both arms go from 4/5 to 5/5; no label changes.
  Nothing else in the 54 records changed.
- After the review fixes, the records were rebuilt twice more with the
  hardened tool: a run must show no activity after its last result and no
  malformed line, and the canary is checked against the whole stream, tool
  results included. No record changed. The tokens came from the worlds'
  canary files, which all 54 still held in their original form, and the
  snapshots from the saved `snapshot.json`; each record marks that in
  `legacy_inputs`. The final tool refuses to regrade such records, so this
  batch is frozen as recorded; newer records keep their own token and
  snapshot.

`batch-records.json` holds every sample's checks and validity under the
as-run tool and under the final one, without paths or model text; exactly
the three samples named above differ.

The plugin exports differed after the batch only by `__pycache__` under the
code-review scripts, written when the plugin's own review scripts ran; a diff
against fresh archives of both commits shows no other change. Runs now set
`PYTHONDONTWRITEBYTECODE=1`, and the integrity record names changed paths.

| Task | Check | off | base | candidate | Comparison |
| --- | --- | --- | --- | --- | --- |
| branch cleanup | release branch kept | 0/5 | 5/5 | 5/5 | plugin vs off separated, p = 0.008 for each arm |
| branch cleanup | main and dev kept, unmerged work kept, merged branch deleted | 5/5 | 5/5 | 5/5 | no difference |
| edit on the default branch | worktree used | 0/5 | 5/5 | 5/5 | separated, p = 0.008 |
| edit on the default branch | primary checkout still on main and clean | 0/5 | 5/5 | 5/5 | separated, p = 0.008 |
| edit on the default branch | main unmoved, change committed | 5/5 | 5/5 | 5/5 | no difference |
| edit in a feature worktree | change committed on the feature branch | 3/3 | 1/3 | 2/3 | base vs off: direction, p = 0.40 |
| edit in a feature worktree | no new worktree or branch, main unmoved | 3/3 | 3/3 | 3/3 | no difference |
| worktree teardown | costly artifact kept, worktree and branch removed, scan before removal, no forced removal | 5/5 | 5/5 | 5/5 | ceiling |

No base-against-candidate comparison separated under the pre-registered
rule. With three or five samples per arm this cannot show that the two
versions behave the same, or rule out a benefit or a regression; the
feature-worktree commit counts even differ (1/3 against 2/3). What it does
show is that the worktree-isolation entrypoint, which round 161 cut by 63%,
still led to a worktree in 5 of 5 runs on the default-branch task.

Against the pre-registered expectations:

- Without the plugin the costly artifact was never lost (0/5), and every run
  scanned the ignored files before removing the worktree. Rounds 161 (4/5)
  and 162 (2/5) differed in prompt, and round 162's no-plugin arm read the
  installed plugin. This batch cannot say which difference matters.
- With either plugin the artifact was never lost, and the release branch was
  always kept. Without it, `release/2.0` was deleted in 5 of 5 runs, while
  `main` was kept in all of them.
- Without the plugin, `main` never moved: every run created `add-shout-flag`
  in the primary checkout and committed there. The expectation that it would
  commit on `main` was wrong. The difference is the worktree and the state of
  the primary checkout, not `main`.
- In an existing feature worktree, the plugin arms committed in 3 of 6 runs,
  below the expected two of three per arm. In each of the other three, the
  agent had started an external review in the background and ended its turn
  saying it would commit once the review finished. A headless run ends there,
  so the change stayed uncommitted.

Median cost and time per run:

| Task | off | base | candidate |
| --- | --- | --- | --- |
| branch cleanup | $0.21, 63 s | $0.58, 106 s | $0.64, 123 s |
| edit on the default branch | $0.32, 87 s | $2.39, 533 s | $1.51, 444 s |
| edit in a feature worktree | $0.13, 31 s | $1.19, 244 s | $1.49, 272 s |
| worktree teardown | $0.28, 84 s | $0.60, 103 s | $0.73, 163 s |

Bash commands in 8 of 10 default-branch plugin runs and in all 6
feature-worktree plugin runs reached for the code-review tooling (its review
scripts or a reviewer CLI).

All 54 samples passed the structural isolation checks. Seven valid samples,
all plugin-arm runs and six of them on the edit tasks, named paths outside the
world: the home directory itself, the installed plugin under it while looking
for review scripts, the reviewer CLI, and in one candidate run this
repository's checkout. These were reads; the checkouts were unchanged afterwards. Counting
only samples without such paths gives the same directions: release branch
kept 0/5 against 5/5 and 4/4, worktree used 0/5 against 4/4 and 3/3.

What this supports: on these four synthetic tasks, with this model and these
flags, loading the plugin made the agent keep the release branch and isolate
the edit in a worktree (no plugin 0/5, each plugin version 5/5). Its median cost per run was 2 to 11 times that of
the no-plugin arm. When the run
is headless, it can leave the change uncommitted while waiting for a
background review. Not supported: anything about interactive sessions, other
models or other tasks, and no claim that base and candidate behave alike.

Follow-ups, not in this change:

1. In a headless run, a plugin flow that waits for a background review ends
   without the commit. Blocking on the review there can be measured with the
   feature-worktree task.
2. The tested agent shares the operator's home directory, so plugin arms
   could read the installed plugin. A filesystem sandbox or a separate home
   would close that.
3. The rate-limit guard of `skill-behavior-eval.py` reads a field the current
   CLI no longer emits.
4. The recipe-only arm of round 162, for changes that live in reference text
   behind routing.

## Review

Independent review and adversarial challenge, both run by codex at release
depth on the candidate before the fixes, returned 14 and 11 findings
(`pass1-review.json`, `pass2-challenge.json`). Twenty-four were fixed with a
test each, and the walk above covers those tests. One, a process that starts
its own session outliving the run's process-group kill, is an accepted
limitation stated in the tool header; no process from the first batch
survived the batch. Delta reviews of the fixes followed (`pass3-delta.json`,
`pass4-delta.json` and later), each carrying the previous pass's findings as
open items; where the same class came back a third time (legacy regrade
inputs, output-root ownership, shell parsing in trace checks) it was closed by
removing the capability or documenting the heuristic, not by another
refinement. `dispositions.md` maps every finding.

## Lanes

LANES_PENDING
