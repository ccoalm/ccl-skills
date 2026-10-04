# Plan: a headless stop that still has background work

## Trigger

In the round 163 paired batch, plugin-arm runs in headless Claude Code (`claude -p`) started an
external review in the background and ended their turn. Six of the seven background reviews in the
batch were killed a few seconds after the turn ended. In three of those runs the change was never
committed; in the other three it was committed but the review's result was never read. The one review
that finished within a second and a half of the turn's end woke the session, and that run committed.

## Result classification

Failure, observed. A paired host probe fixes the mechanism, and a pre-registered probe reproduces the
loss on `main` with every other plugin hook working.

## Cause analysis

| Factor | Kind | If removed | Weight |
| --- | --- | --- | --- |
| A headless session ends at the stop; the host waits a few seconds for background tasks, then stops them and starts no further turn | host behavior | the deferred work would run when the task finished, as in interactive sessions | necessary |
| The host's background tool tells the agent it will be notified when the task finishes, with no headless caveat | process model | the agent would wait in the foreground | contributing |
| A review whose timeout exceeds the foreground tool limit gets run in the background | trigger | most reviews would run in the foreground | contributing |
| The plugin's rule that awaiting your own work is not a stop condition fires through a Stop reminder that reads the transcript | missing firing point | the rule would catch the stop in every configuration | necessary for the plugin's part |
| The paired batch ran without session persistence, so that reminder could not run there | detection | the batch would have measured the working plugin | contributing to how the loss surfaced |

Prevention lands on the class: a stop in a session nothing re-invokes, while background tasks still run.
The firing point reads the running tasks from the Stop hook's own input, which needs no transcript.

## Owner map

| Owner | Direction | Status | File or reason |
| --- | --- | --- | --- |
| `product-rd-workflow` | owner of the in-flight-work rule and the Stop reminders | updated | `references/pre-final-continuation-gate.md` |
| plugin hooks | implementation of that rule's firing point | updated | `hooks/headless-background-stop.sh`, `hooks/host-input.py`, `hooks/hooks.json`, `hooks/test_headless_background_stop.sh`, `Makefile` |
| `skill-extraction-workflow` | process | unchanged | the measurement lesson landed with the paired-eval tool; this round adds its register row |
| `code-review` | sibling: review length drives backgrounding | unchanged | the guard covers the class at the stop, whatever was backgrounded |
| `multi-agent-delegation` | sibling: background jobs | unchanged | job-board semantics are not involved |
| `testing-strategy` | downstream | unchanged | the suite follows the existing hook-suite conventions |
| `hooks/remind-untracked-background.sh` | sibling advisory | unchanged | it fires for untracked launches only, and its tracked-waiter advice holds in interactive sessions |
| always-on session start | routing layer | unchanged | it already says announced next steps never end the turn |

## Pre-registered readings

Both were written before their runs.

Baseline (diagnostic), with session persistence on so the plugin's transcript-reading hooks run: the
feature-worktree task on `main` and without the plugin, three runs each, counting killed background
reviews and missing commits. It only decides whether the round 163 loss reproduces with those hooks
working.

Guard probe: plugin export of `main` against the export of this round's commit, three runs each,
interleaved; a headless run is asked to start `sleep 45 && echo PASS > check.txt` in the background,
write `verified` into `status.txt` once it passed, and is told a notification will follow. The guard
helps if the candidate writes `status.txt` in at least two of three runs and `main` in at most one. If
`main` also writes it in two or three, the probe does not separate the arms and the guard rests on its
suite and mutation walk.

## Completion

The guard's suite registered and green, an applied mutation walk over its properties, the probe read
against the rule above, independent review and adversarial challenge with delta passes on later
changes, the register row as the last content commit, the repository lanes, and a pull request to
`main` with CI green.
