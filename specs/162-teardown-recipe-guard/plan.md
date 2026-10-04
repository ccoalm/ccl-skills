# Carry the teardown guard to every removal recipe

## Intent

`git worktree remove` without `--force` deletes gitignored files and exits 0.
The canonical teardown section (`skills/worktree-isolation/references/merge-and-teardown.md`)
therefore requires a successful scan of gitignored outputs before any removal,
and copying costly ones out first. Three other skills restated the removal as
a command list without that pre-step, the same shape the post-merge reminder
had until round 161
(`specs/161-firing-point-loading/`). An agent that follows one of those lists at
closeout can delete hours of results with no error. This round carries the
pre-step to every restatement and adds a sweep, so a restatement added later
cannot leave it out.

## Scope

- `product-rd-workflow/references/worktree-mechanics.md`, Closeout Cleanup.
- `multi-agent-delegation/references/multi-agent-delegation-playbook.md`,
  handoff step 5 (worker worktree removal).
- `skill-extraction-workflow/references/extraction-lifecycle-handoff.md`,
  the extraction worktree note.
- `worktree-isolation/references/merge-and-teardown.md`: the "any removal
  method" list names host-native worktree removal, and the handoff to an
  external finishing skill keeps the scan, because that skill's cleanup relies
  on git's refusal and cannot see gitignored files.
- `docs/worktree-isolation-handbook.md`: four pointers still named the skill
  entrypoint for sections round 161 moved to references.
- `skill-extraction-workflow/references/attention-budget-ratchet.md`: moving a
  section requires a Markdown search for its name, since no gate resolves
  pointers that name a section.
- Tests: a pin family and a sweep in `test_ai_coding_implementation_gates.sh`,
  and `test_teardown_guard_pins.sh`, which applies one mutation per pin.

Out of scope: the post-merge hook and the always-on layer already carry the
scan; historical evidence tables under `specs/` and in reference evidence
records are not rewritten; `eval/` inputs are not guidance.

## Decisions

- The sweep keys on the `worktree remove` command and requires the scan, its
  exit-0 condition and the qualified pointer
  `worktree-isolation/references/merge-and-teardown.md` (the package's own files
  may use the package-relative path). Removal described only in prose is pinned
  per surface; a prose vocabulary would flag catalog and architecture pages that
  describe cleanup without prescribing it. Round records, evaluation inputs and
  the append-only source register are not scanned, and a listing or read error
  fails the sweep.
- Cross-skill pointers use the `<skill>/references/<file>.md` form, so the
  fast validator also fails when the canonical file moves.
- No new gate in `check-ccl-skills.sh`: the fixture and its mutation walk run
  in the fast regression lane, which every pull request runs.

## Checks

The RED, GREEN, mutation-per-pin and behavior checks were recorded before the
edits; the walk's relocation, decoy and self-check legs were added while the
walk was built.

| Check | Pass condition |
| --- | --- |
| Pins RED on the base text | every pin row that encodes a new obligation fails on its own; rows for canonical rules that already existed pass and become pinned |
| Sweep RED on the base text | reports exactly the restating files that lack the scan or the canonical pointer |
| Pins and sweep GREEN | the fixture passes on the candidate |
| Mutation walk | every row reds on its own label under an applied mutation; relocating a scoped phrase reds its row; decoy surfaces red the sweep for the stated reason; a compliant decoy, a prune-only mention and a vendored dependency file stay green; the live tree stays green while a mutated copy reds |
| Probe self-check | sabotaged copies of the fixture make the walk fail for the right reason |
| Behavior | paired runs with and without the change, plus a no-plugin arm, judged by the decision rule recorded before the runs |
