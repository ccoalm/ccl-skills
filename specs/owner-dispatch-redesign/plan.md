# owner-dispatch redesign

## Problem

Product repositories that enable owner-dispatch get a merge conflict on every pair of parallel merge requests. The `ci` subcommand accepts the change only when one fixed file, `ci_artifact` (default `design/owner-dispatch-map.md`), is part of the diff. Every request appends a section at the end of that file. Two insertions at the same position cannot merge automatically.

A scratch repository reproduced it with two parallel branches:

| Shape | Second merge |
| --- | --- |
| Both append to one map file (current practice) | conflict |
| Each branch adds its own file in a directory | clean |
| One map file with `merge=union` | clean, but the two sections are spliced together and one separator is lost |

## What the subsystem is for

The rule behind it: an agent loads the owning skill into its current context before it produces substance. Naming the skill is not loading it. The only evidence that a skill was loaded is a `Skill` invocation, or a full read of its `SKILL.md`, in the session transcript.

Measured against that purpose:

| Part | Evidence it uses | Does it show the skill was loaded? |
| --- | --- | --- |
| `ci` map file | a paragraph the agent writes; `ci` checks only that the file changed | no |
| `record --owners` | owner names the agent declares | no; the README calls it self-attestation |
| Stop check | `Skill` calls in the transcript, compared with the `record` list | only for the names that were declared; an owner left out of `record` is never checked |
| Default first-edit checkpoint (`hooks/skill-loading.py`) | the transcript | it does not judge which owner is right; it denies the first source edit once per context so the agent loads the owner before retrying |

Two further mismatches:

- The rule fires before design substance. The hooks fire at the first code edit, so the design-time half was never enforced mechanically.
- The first-edit checkpoint already covers "load before editing code" in every repository with no configuration. The opt-in parts were not retired when it landed.

## Change

Keep what reads the transcript; delete what rests on self-declaration.

Keep:

- The first-edit checkpoint, unchanged in behavior. Its wrapper no longer calls the engine. The wrapper is renamed from `owner-dispatch-guard.sh` to `source-edit-checkpoint.sh`, and the `Bash` matcher is dropped, because the checkpoint handles only edit tools.
- The design-time rule in `product-rd-workflow` (`Owner-dispatch firing gate`). It stays prose, and the text says no hook enforces it. `check-sync-pointers.sh` pins this heading, so the heading is kept.
- The controller's worker-recovery rule in `multi-agent-delegation`, which checks transcripts directly.

Delete:

- `scripts/owner-dispatch/`: the engine, `test.sh`, README, example config and AGENTS.md. This removes `.owner-dispatch.json` opt-in, `record`, `ci`, `status` and `verify-invocations`.
- `hooks/owner-dispatch-stop.sh` and its Stop and SubagentStop wiring, with no replacement (see the next section).
- The owner-dispatch path in `install-gates.sh`, which vendored the engine, wrote the config and emitted the CI job. `agents-file-coverage-gate` stays.
- Packaging and runtime lists: `install-opencode.sh`, the npm build roots, `host-smoke.sh`, `verify-packed.mjs`, the OpenCode adapter and plugin mapping, and the control-plane protected paths.
- Rule text telling agents to run `record` or keep the map:
  - `agent-context/session-policy.md` (unlock line)
  - `agent-context/subagent-start.md` (last bullet)
  - `agent-context/session-start.md` (the clause "recording the boundary" in Transitions)
  - `product-rd-workflow/SKILL.md` (mechanical-firing bullet and closeout-acquire)
  - `references/dispatch-owner-skills.md` (mechanical section)
  - `multi-agent-delegation/SKILL.md` (mechanical-backstop bullet)
- Descriptive text in README, `docs/ARCHITECTURE.md`, `docs/CONTRIBUTING.md` and `firing-point-placement.md`:
  - It is rewritten to describe the checkpoint.
  - The firing-point example keeps its history and records why the self-attested layer was retired.
  - Its closing advice to "build the in-session-hook + CI-backstop pair" is replaced. A backstop must read real evidence; a file the agent writes is not evidence.

## Stop check: deleted, not replaced

The candidate replacement was to block once at Stop when an actor edited a source file and its transcript shows no implementation-skill load. The decision was to add it only if the first-edit checkpoint leaves a material share of source-editing sessions with no load.

### Population

- Local transcripts from the last 60 days, in product repositories that had the gate enabled.
- 258 main sessions and 100 subagent transcripts.
- The repositories in the original report had no transcripts in that window. The gate code is the same, so the active ones were measured instead.

### Definitions

- An implementation-class skill is one whose name ends in `-dev` or `-architecture`, or is `testing-strategy` or `defect-diagnosis`.
- A load is a `Skill` call or a slash command.
- Before and after use line order within one transcript file.

### Results

| Measure | Value |
| --- | --- |
| Main sessions with a source edit | 191 |
| Loaded an implementation skill at some point | 186 (97%) |
| Loaded one only by reading its `SKILL.md` | 4 |
| Never loaded one | 1 |
| Loaded before the first successful edit | 170 of 189 |
| First-edit checkpoint fired | in 188 of 191 |
| Owner-dispatch Stop blocks | 72 |
| Stop blocks where a skill was already loaded before the block | 66 |
| Stop blocks where a load followed the block and none preceded it | 5 |
| Of those 5, preceded by the first-edit checkpoint | 2 |
| Owner-dispatch PreToolUse `ask` prompts | 752, in 72 sessions |

- The 2 sessions in the second-to-last row had read a `SKILL.md` and been compacted, so they may not be real misses.
- Subagents: 4 transcripts had source edits. All 4 loaded a skill, and the Stop block never fired in a subagent.

### Reading

- The Stop block mostly enforced running `record`, not loading a skill. The `ask` prompts are recurring friction for the same declaration.
- With the first-edit checkpoint alone, the residual is about 1 session in 191.
- A Stop replacement would catch that one session at the cost of a new predicate, a list of implementation-skill names that must not drift, and a block on every session where the agent legitimately needed none.
- So the Stop hook is deleted with no replacement. If the residual grows, the trigger to revisit is this same measurement over a later window.

### Caveats

- A resumed session is a new file, so a load in the earlier file is not counted. That understates "before" and overstates the caught bucket.
- Opt-in was dated by commit, not by the worktree a session ran in.

The script and per-transcript rows stay outside the repository, because they carry session file names and local paths.

## Consumers

- Product repositories with a vendored engine and CI job keep running their own copy. Nothing breaks on plugin update.
- The plugin's in-session `ask` in those repositories stops, because the plugin no longer ships the engine. The first-edit checkpoint still fires there.
- Removing `.owner-dispatch.json`, the CI include, the vendored engine and the map requirement from each product repository is a separate round, one config-only change per repository.
- The existing map files stay as history.

## Out of scope

- Product-repository cleanup.
- `agents-file-coverage-gate`.
- The checkpoint's decision logic.
- Mechanising the design-time owner rule. No hook can tell when design work starts.

## Risk

- `shared-gate`: this deletes a merge gate other repositories installed, so independent review and challenge run before push.
- `security-review`: not applicable. Security posture is unchanged: no trust boundary, secret, permission or data-visibility path changes.
- `release-ops`: not triggered in this round. No product-repository CI changes here.

## Verification

- `test_skill_loading.py`: the checkpoint still denies the first source edit and allows after a load, with the engine absent. Tests that built `.owner-dispatch.json` are removed or rewritten.
- `test_host_input.py`: the `verify-invocations` case is removed. The transcript parser cases stay.
- `test_install_gates_runtime.py` and `test_install_status.py`: install-gates no longer accepts or installs `owner-dispatch`, and the coverage gate still installs.
- `test_install_opencode_skill_migration.sh` and the npm `opencode-hooks` and `host-adapters` tests: the mapping update matches the renamed wrapper.
- `check-sync-pointers.sh` stays green, with the heading kept.
- A sweep for `owner-dispatch.sh`, `record --owners`, `.owner-dispatch.json` and `ci_artifact` returns only history (specs, evidence, the source register).
- `make test`, `make npm-test`, the heavy lane and public sanitization. Results go in `evidence/validation.md`.
