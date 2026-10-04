# Round 164 review dispositions

Independent review (`pass1-review.json`) and adversarial challenge (`pass2-challenge.json`), both on the
round's first full candidate against `origin/main`. Both passes first stopped on a missing owner in
the self-review and ran again with it added.

| Pass | # | Severity | Finding | Disposition |
| --- | --- | --- | --- | --- |
| challenge | 1 | P1 | the reason told the agent it could run a still-running task again in the foreground, which would repeat a deployment's or migration's effects | fixed: the reason says to wait for that task by polling its output or the files it writes in a bounded foreground loop, and not to start it again; the probe's guarded agents waited exactly that way. The suite checks the new wording and fails on any rerun advice |
| review | 1 | P1 | same as challenge 1 | fixed with it |
| challenge | 2 | P1 | the packet did not show the state helper, so containment, atomic claims and the unavailable-state fallback could not be checked | fixed: the next pass gets the state helper and the existing Stop logic appended; the suite now drives hostile session and task ids (nothing becomes a path), four racing stops for one task (exactly one block) and a symlinked state root (refused, so the host retry flag bounds the block and nothing is written through the link) |
| review | 2 | P1 | same as challenge 2 | fixed with it |
| review | 3 | P2 | the helper called directly in an interactive session still printed a notice on bad input | fixed: the subcommand checks the entrypoint before reading input; the check inside the function, now redundant, is gone so one pinned gate remains |
| review | 4 | P2 | the caps on the reason were not asserted, the walk had only a prose summary and the lanes were pending | fixed: the suite asserts the 100-character description cap and that tasks past the fifth are not listed; the walk's per-mutation record is `hook-mutation-walk.json`; the lanes are recorded when they run on the final candidate |

## Delta review (`pass3-delta.json`)

Run on the diff from the reviewed candidate, with the state helper, the guard's functions, the Stop
registration and the existing Stop retry logic appended.

| # | Severity | Finding | Disposition |
| --- | --- | --- | --- |
| 1 | P1 | the packet could not show that the whole Stop group stays bounded, because the other registered Stop hooks' retry paths, the wrapper, the entrypoint definition and the full suite were not in it | the claim is narrowed to what this hook guarantees: it adds at most one block per distinct running task id per session, and without usable state at most one per stop chain; the other Stop hooks are unchanged and keep their own bounds. The next pass gets the wrapper, the entrypoint definition, the complete suite and its Makefile entry appended |

## Second delta review (`pass4-delta.json`)

Run through the generic controller, because the delta held only records, on the diff from the
register commit with the wrapper, entrypoint definition, state helper, Stop registration, complete
suite and Makefile entry appended.

| # | Severity | Finding | Disposition |
| --- | --- | --- | --- |
| 1 | P1 | the packet still lacked the helpers' module initialization, the rule and register excerpts, the mutation and probe records and the lanes | method changed instead of appending more excerpts: an evidence gap came back twice because a record-only delta cannot carry the round-level claims, so the next pass reviews the whole candidate against `origin/main`, which holds every record, the rule, the register row and the Makefile entry, with both helpers' unchanged module initialization appended. The lanes are claimed only after they run on the final candidate |

## Full-candidate review (`pass5-full.json`)

Run on the whole candidate against `origin/main`, with both helpers' module initialization and the
state helper appended.

| # | Severity | Finding | Disposition |
| --- | --- | --- | --- |
| 1 | P1 | the dispatcher's prelude and epilogue and both modules' entry guards were not shown, so the full path's reads could not be checked | closed by construction for this class: the third evidence gap in a row, so the next pass gets both helper files appended whole instead of another excerpt |
| 2 | P1 | the walk recorded mutation names and failing cases but not the edits applied | fixed: `hook-mutation-walk.json` holds, for each of the 22 mutations, the exact text replaced and its replacement, the named cases, the cases that failed and the suite's exit, plus the unmutated copy's exit before and after |

## Second full-candidate review (`pass6-full.json`)

Run with both helpers appended in full.

| # | Severity | Finding | Disposition |
| --- | --- | --- | --- |
| 1 | P1 | the packet was too large for the controller to include the root repository contract | fixed: for the next pass the earlier passes' result files were set aside, since they are review records summarized here and are committed back afterwards, which left room for the contract |

## Third full-candidate review (`pass7-full.json`)

Run on the whole candidate with both helpers in full and both repository contracts included. Passed
with no findings. It notes that the mutation results were not re-executed by the reviewer and that the
probes support the sampled mechanism, not a reliability rate.

## OpenCode binding review (`pass8-delta.json`)

CI then failed `npm-packages`: the OpenCode adapter keeps a one-to-one inventory of the command hooks
in `hooks.json`. The adapter now binds the guard and runs it on session idle with the other Stop hooks.
This pass ran through the generic controller on that change.

| # | Severity | Finding | Disposition |
| --- | --- | --- | --- |
| 1 | P1 | an OpenCode process started from a headless Claude Code process can inherit `CLAUDE_CODE_ENTRYPOINT=sdk-cli`, so the guard could act inside OpenCode, and the packet did not show the hook environment | fixed: `runHook` drops `CLAUDE_CODE_ENTRYPOINT` from every hook's environment, since a Claude Code entrypoint never describes an OpenCode session. A spy test sets `sdk-cli` in the parent and asserts that the guard sees it unset. On a disposable copy, removing the strip fails that test (1 of 49) |
| 2 | P1 | the packet did not show that the idle invocation runs, nor what happens if it fails | the coverage existed and is now in the packet: the native-events test asserts that the hooks traced during a simulated session equal every command hook in `hooks.json`. On a disposable copy, removing the guard's idle call fails that test and the spy test (2 of 49). `runHook` catches every error and returns a status, so a failing hook cannot skip the other results or the resume |

## Delta review of the OpenCode fixes (`pass9-delta.json`)

Run through the generic controller on the diff that dropped the inherited entrypoint, with `runHook`, `resumeForStop`, the
idle handler and the three related tests appended.

| # | Severity | Finding | Disposition |
| --- | --- | --- | --- |
| 1 | P1 | the spy stands in for the real guard, so the packet could not show that the real guard stays silent without an entrypoint | rejected with evidence: the wrapper reads `${CLAUDE_CODE_ENTRYPOINT:-}` and exits 0 before Python for anything but `sdk` or `sdk-*`, so unset and empty take the same branch. The guard's suite pins that path in its no-entrypoint, lookalike and interactive-without-Python cases, and the walk's "the wrapper letting interactive sessions through" mutation fails them. A test of the real guard inside OpenCode could not catch a missing strip anyway: OpenCode's Stop payload carries no `background_tasks`, so the guard has nothing to block even with an `sdk` entrypoint. The spy is the test that fails when the strip is removed |
| 2 | P1 | the npm results, the mutation results and the repository lanes were asserted in the plan but not shown | the results are recorded in this round's `validation.md` (433 of 433 npm tests and both mutations with their failing tests). The repository lanes on the final code are recorded there too |
