# owner-dispatch redesign

## Problem

Product repositories that enable owner-dispatch get a merge conflict whenever parallel merge requests both touch gated code. The `ci` subcommand accepts a change only when one fixed file, `ci_artifact` (default `design/owner-dispatch-map.md`), is part of the diff. Every request appends a section at the end of that file, and two insertions at the same position cannot merge automatically.

A scratch repository reproduced it with two parallel branches:

| Shape | Second merge |
| --- | --- |
| Both append to one map file (current practice) | conflict |
| Each branch adds its own file in a directory | clean |
| One map file with `merge=union` | clean, but the two sections are spliced together and one separator is lost |

## What the subsystem is for

The rule: an agent loads the owning skills into its current context before it produces substance. Naming a skill is not loading it. The only evidence of a load is a `Skill` invocation, or a full read of its `SKILL.md`, in the session transcript.

Each part, measured against that purpose:

| Part | Evidence it uses | Does it show the skills were loaded? |
| --- | --- | --- |
| `ci` map file | a paragraph the agent writes; `ci` checks only that the file changed | no |
| `record --owners` | owner names the agent declares at the start of a slice, kept in local git state and never committed | no, but it fixes the set to check |
| Stop check | `Skill` calls in the transcript, compared with the `record` list | yes, for every declared owner |
| Default first-edit checkpoint (`hooks/skill-loading.py`) | the transcript | it denies the first source edit once per context so the agent loads an owner; it does not judge which owners are needed |

The map file is the only part that is both committed and shared, which is why only it conflicts. It is also the only part whose check reads nothing but the agent's own text.

## Measurement

### Population

- Local transcripts from the last 60 days, in product repositories that had the gate enabled.
- 258 main sessions and 100 subagent transcripts.
- Repositories with no transcripts in that window are not represented. All opted-in repositories run the same gate code.

### Definitions

- An implementation-class skill has a name ending in `-dev` or `-architecture`, or is `testing-strategy` or `defect-diagnosis`.
- A load is a `Skill` call or a slash command.
- Before and after use line order within one transcript file.

### Results

| Measure | Value |
| --- | --- |
| Main sessions with a source edit | 191 |
| Never loaded an implementation-class skill | 5, of which 4 read one in full through its `SKILL.md` |
| First-edit checkpoint fired | in 188 of 191 |
| Stop blocks, nothing recorded | 45; `record` followed in 40 |
| Stop blocks, a declared owner was never loaded | 27 |
| Of those 27, every missing owner was then loaded | 16 |
| Sessions where the first implementation-class load came only after a Stop block | 3; 2 of these had already read a `SKILL.md` |
| Owner-dispatch PreToolUse `ask` prompts | 752, in 72 sessions |

Owners named as declared but not loaded, counted per block: `testing-strategy` 17, `defect-diagnosis` 9, `python-service-dev` 7, `product-rd-workflow` 7, `feature-risk-router` 6, `platform-observability` 5, others 1 to 3.

### Reading

- The Stop check on declared owners is the one part with measured effect beyond the first-edit checkpoint. In 16 sessions, a second owner that the agent had itself named (most often the testing owner) was loaded after the block. Transcript order shows the sequence, not that the block caused the load.
- The first-edit checkpoint cannot replace it. It asks for one owner and does not know which others the slice needs.
- A transcript-only Stop check with no declared list would only ask "was any implementation skill loaded". It would have caught at most 3 sessions and none of the 16.
- The `ci` map has no measurable detection effect: it checks the file changed, not its content.

### Caveats

- A resumed session is a new file, so a load in the earlier file is not counted.
- Opt-in was dated by commit, not by the worktree a session ran in.
- "Then loaded" means a later `Skill` call for each missing name in the same file. It does not show the reload changed the work.

The scripts and per-transcript rows stay outside the repository, because they carry session file names and local paths.

## Change

Delete the committed, shared layer and keep the in-session layer.

Delete from the plugin:

- The `ci` subcommand (`cmd_ci`, `cmd_ci_python`) and the `ci_artifact` config key in `scripts/owner-dispatch/owner-dispatch.sh`. A config that still sets `ci_artifact` is accepted and the key ignored, so existing product configs stay valid.
- The `owner-dispatch` job in the CI fragment `install-gates.sh` emits, and the install text about the map.
  - `install-gates` keeps writing the config and vendoring the engine and `host-input.py`.
  - The plugin hooks run the plugin's own engine. The vendored copy is still the path rule text gives for `record` and `status` (`scripts/owner-dispatch/owner-dispatch.sh`), so it stays.
- Rule and doc text that tells agents to keep the committed map file or describes `ci` as the backstop:
  - `skills/product-rd-workflow/SKILL.md` (mechanical-firing bullet)
  - `references/dispatch-owner-skills.md`
  - `scripts/owner-dispatch/README.md`
  - `firing-point-placement.md`
  - README, `docs/ARCHITECTURE.md`, `docs/CONTRIBUTING.md`
- In `firing-point-placement.md`, the closing advice to "build the in-session-hook + CI-backstop pair" becomes: a backstop must check a property the agent cannot satisfy just by writing a declaration.
- Tests for `ci` in `scripts/owner-dispatch/test.sh` and the CI-fragment assertions in the install tests.

Keep unchanged: `.owner-dispatch.json` opt-in and globs, `record`, the PreToolUse `ask`, the Stop and SubagentStop checks, `status`, `verify-invocations`, and the first-edit checkpoint.

The closeout-acquire rule in `product-rd-workflow` (`status` must read `opted-in: yes`) stays. It no longer mentions the CI backstop.

## Product repositories

Plugin users are not broken by the plugin change alone:

- Each product repository runs its own vendored engine copy in CI.
- The `ask` and Stop hooks keep working, because they never used `ci`.

They are broken by the combination. Once the plugin docs stop telling agents about the map, agents in a repository whose CI still runs `owner-dispatch.sh ci` stop updating the map, and its pipeline fails on every gated change.

Local inventory, taken from checkouts that track `.owner-dispatch.json` at the repository root:

- 40 opted-in checkouts.
- 39 of them have a tracked CI file that runs `owner-dispatch.sh ci`, in most cases `ci/agent-gates.gitlab-ci.yml` included from `.gitlab-ci.yml`. One has no such job.
- In 3 checkouts the job is enforced (no `allow_failure`). One of those is a plain directory copy with no git repository, so 2 repositories enforce it: one toolkit repository and one service repository.
- Everywhere else it is the installer's warn-only default: a failure shows as a warning and does not block merge.

Order:

1. The 2 enforced repositories delete the `owner-dispatch` job block by hand before the plugin change lands. Each is a config-only change.
   - Do not rerun `install-gates` there. Regenerating a fragment that still carries the installer marker writes `allow_failure: true` back, which would also undo the enforcement those repositories set on the coverage job.
2. The plugin change lands.
3. The warn-only repositories drop the job as ordinary cleanup.
   - Rerunning `install-gates` regenerates their unedited fragment without it and refreshes the vendored engine.
   - Until then their pipelines show a warning and nothing blocks.
   - `.owner-dispatch.json`, the vendored engine and the coverage job stay.

The existing map files stay as history and are no longer appended to.

## Out of scope

- Reducing the 752 PreToolUse `ask` prompts. They are friction, but the data does not separate how much of the record-then-load effect they drive. This is a candidate for a later measured round.
- Mechanising the design-time owner rule. No hook can tell when design work starts.
- `agents-file-coverage-gate`.

## Risk

- `shared-gate`: this removes a merge gate other repositories installed. Independent review and challenge run before push.
- `release-ops`: product-repository CI changes. The 2 enforced repositories land before the plugin change, each as a config-only change.
- `security-review`: not applicable. Security posture is unchanged: no trust boundary, secret, permission or data-visibility path changes.

## Verification

- `scripts/owner-dispatch/test.sh`:
  - the `ci` cases are removed;
  - a new case shows a config carrying `ci_artifact` still loads, and `pretool`, `stop` and `record` behave as before;
  - a case fails if `ci` is still dispatched.
- `test_install_gates_runtime.py` and `test_install_status.py`:
  - no owner-dispatch CI job is emitted;
  - the engine, `host-input.py` and config are still vendored;
  - the coverage job is unchanged;
  - an existing pipeline file that still runs `owner-dispatch.sh ci` produces a warning to delete that job, because the refreshed engine exits 2 on it.
- `test_skill_loading.py` and `test_host_input.py`: unchanged and still green, since the checkpoint and transcript parsing are untouched.
- `check-sync-pointers.sh` stays green; the pinned `Owner-dispatch firing gate` heading is kept.
- A sweep for `ci_artifact`, `owner-dispatch.sh ci` and `owner-dispatch-map` returns only history (specs, evidence, the source register).
- Product repositories: in each of the 2 enforced ones, a pipeline on the removal change is green before the plugin change merges.
- `make test`, `make npm-test`, the heavy lane and public sanitization. Results go in `evidence/validation.md`.

Plan review results are in `evidence/plan-review.md`.
