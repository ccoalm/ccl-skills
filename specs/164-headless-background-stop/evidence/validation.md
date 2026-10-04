# Validation: a headless stop that still has background work

## Host behavior

Claude Code 2.1.288, headless (`claude -p`), no plugin, legs that differ only in how long a background
Bash task runs; the agent starts it and ends its turn:

| Background task | Task's final status | Second turn | Process exit |
| --- | --- | --- | --- |
| `sleep 2` | completed | yes, the agent replied to the notification | 12.2 s |
| `sleep 40` | killed | none | 12.6 s |

In the round 163 batch every killed background review ended about 5 s after the turn's last result,
and the one that completed 1.5 s after it woke the session.

The agent's shell and the hooks see `CLAUDE_CODE_ENTRYPOINT=sdk-cli` in headless runs, while an
interactive session reports `cli`. The Stop hook's input carries `background_tasks`, each with an id,
type, status (`running`) and description; with session persistence off the transcript file it names
does not exist. Headless runs offer `Task`, `Bash`, `Monitor` and `TaskStop`, but no blocking wait on a
background task.

## Round 163 batch

Seven of the 36 plugin-arm runs launched a background review, and six of those reviews were killed
after the turn ended: three runs had not committed, three had committed and never read the result. The
batch ran with session persistence off, and in it the plugin's transcript-reading Stop reminder reported
itself unavailable at every stop.

## Baseline with the transcript-reading hooks working

Pre-registered in `../plan.md`. Feature-worktree task, Opus 5.5 at effort max, session persistence on:

| Arm | Committed | Background launches | Killed tasks |
| --- | --- | --- | --- |
| no plugin | 3/3 | 0 | 0 |
| `main` | 3/3 | 0 | 0 |

With those hooks working, this task did not reproduce the loss; the `main` runs committed early and ran
their reviews afterwards. Three runs establish that the loss is not universal there, not a rate.

## Guard probe

Pre-registered in `../plan.md`. Headless, Opus 5.5 at effort max, session persistence on; the plugin
export of `main` against the export of this round's guard commit; three runs each, interleaved;
per-run rows in `probe-rows.json`.

| Arm | `status.txt` says verified | `check.txt` written | Background task | Run time |
| --- | --- | --- | --- | --- |
| `main` | 0/3 | 0/3 | killed in 3 | 21–24 s |
| guard | 3/3 | 3/3 | completed in 3 | 65–87 s |

The reading rule's separating outcome held. On `main` the agent ended its turn trusting the promised
notification and the host stopped the task; no other plugin hook stopped it, persistence included. With
the guard, the stop was blocked once with the task named, and the agent waited in the foreground, saw
the check pass and wrote the status.

## Suite and mutation walk

`hooks/test_headless_background_stop.sh` (repository-gates lane, 30 cases) drives the hook with
synthetic Stop inputs: a block naming the task, telling the agent to wait for it in the foreground
without starting it again; no repeat for the same task, with or without the host's retry flag; a new
task in the same session blocks with only that task; per-session state; the SDK entrypoint;
interactive, missing and lookalike entrypoints stay quiet, also through the helper alone and on bad
input; finished tasks, a missing field and other hook events stay quiet; input that is not JSON gives a
notice; without usable state the host's retry flag bounds the block; long lists stop at five with a
count and descriptions at 100 characters; hostile session and task ids never become paths; four racing
stops for one task block once; a symlinked state root is refused and nothing is written through it; an
interactive session never starts the helper, and a headless one without Python gets a notice.

On a disposable copy of the hook, its helper, the state helper and the suite, 22 mutations were applied
one at a time; each turned its named case red and the copy was green before and after. The
per-mutation output is in `hook-mutation-walk.txt`.

| Area | Mutations |
| --- | --- |
| entrypoint | no headless session recognized, the helper speaking to interactive sessions, a lookalike accepted, only `claude -p` recognized, the wrapper letting interactive sessions through, a missing helper passing silently |
| once per task | every stop blocking again, reported tasks listed again, state shared across sessions, without state every stop blocking, without state nothing blocking |
| input and state | finished tasks counted, other hook events handled, bad input passing silently, the session id used as a path, a symlinked state root followed |
| reason | a long list not summarized, every task listed, descriptions not capped, line breaks kept in labels, the way out (TaskStop or a reason) missing, a rerun advised |

## Lanes

LANES_PENDING
