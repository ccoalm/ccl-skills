# Run The Killing-Mutation Walk

Mechanics for the entry rule's killing-mutation obligation in `SKILL.md` (Core Rules): the guarded backup recipe that makes mutating safe, the side-effect blast-radius discipline, the encoded probe for destructive artifacts, and the round-trip nuances. The obligations themselves — every named property owes a mutation, the walk is driven from named properties, destructive artifacts need the probe — live in the entry rule; this file owns how to execute them without losing work or buying false evidence.

## Why The Walk Is Property-Driven, Not Assertion-Driven

The entry rule drives the walk from the named properties in every changed test artifact rather than from the changed assertions, because a rename or an added docstring line introduces a new claim while touching no assertion at all — an assertion-driven walk would enumerate zero rows and let it through.

## Guarded Backup Recipe

The entry rule requires the restore to be guarded and the guard kept out of version control. The executable form: before mutating, copy each target OUT of the repo, and restore by copying back.

- `bak=$(mktemp -d)`; per target `f=<repo-relative path>`: `mkdir -p "$bak/$(dirname "$f")" && cp -a -- "$f" "$bak/$f" || exit`.
- Restore with the same fail-fast: `cp -a -- "$bak/$f" "$f" || exit`.
- Verify the backup root actually landed outside the worktree — the executable spec does this with a canonical-path check against the repo root, not by assuming — since `mktemp -d` honours `TMPDIR` and a `TMPDIR` pointing inside the repo puts the snapshot right back where a later `add` can sweep it up.
- Delete the temp directory only after every restore has succeeded: cleanup after a failed copy-back destroys the sole remaining copy while the mutation is still live. Remove the temp directory when the run ends.

Scope of the recipe: it covers the in-place content mutation a killing mutation actually is — edit a function body, flip a constant, delete a guard clause. It is not a general filesystem-restore tool: a symlinked target, a mutation that changes a target's *type*, a path that resolves outside the repo through a symlinked parent, and any target you cannot hold exclusively between snapshot and restore are all outside it, since the restore is an unconditional overwrite that silently replaces a formatter's or another agent's edits. For any of those, take the disposable checkout the entry rule offers instead.

Do not reach for git as the scratch buffer: `git stash` skips untracked files (exactly the new test a fresh mutation targets), `git add -A` sweeps unignored credentials into the snapshot, a bare `git commit` after a pathspec `add` still writes the whole index, and the resulting commit is publishable for its whole lifetime and survives `reset` in the object database. A copy has none of that. It also removes the ambiguity that makes the restore uncheckable: a clean tree after a rollback is evidence only when the tree was clean before it, and mutating a file that already had uncommitted edits makes `clean` the signature of loss rather than restoration — the copy sidesteps this because the restore never consults git at all.

The recipe's guarantees are pinned by `../scripts/test_mutation_backup_recipe.sh` (this skill's `scripts/`, resolved from the skill root), registered in the repo regression lane.

## Mutation Blast-Radius

A disposable checkout protects SOURCE, not the world the test talks to: disabling an authorization check, an idempotency guard, or a deletion safeguard and then running it against a shared or live dependency can destroy real data or perform a real unauthorized action purely to obtain a RED. Mutate against isolated dependencies, or prove the property at the lowest layer that does not touch them — and if neither is possible, record the property `unverified` rather than buying evidence with a real side effect.

## Encoded Probe For Destructive Artifacts

For a destructive or irreversible artifact under test, the entry rule requires the walk to live inside the suite as an encoded probe rather than a one-off run. Mechanics:

- Iterate the enumerated protected predicates, rebuild a mutant per predicate, and require each to make the suite fail **for the right reason**.
- A bare non-zero exit is NOT that reason and is the trap this form most easily falls into: a mutant that breaks syntax, or breaks fixture setup, also exits non-zero, so the probe banks a broken build as proof of sensitivity while the protected assertion never ran — a false green wearing a RED's clothes. So require, per mutant, that it still parses/builds, that fixtures still set up, and that the failure is **attributable to the named protected assertion**.
- Attribution by substring match over aggregate output is not enough on its own — an unrelated probe or a teardown can fail while the owning assertion still passes or never runs, and the expected name can appear in the output anyway; worse, the cheap repair when a probe is later renamed is to loosen the pattern, which quietly re-blinds the check. Make it **differential** instead: the owning assertion must PASS in the unmutated control run and FAIL under the mutant, and **no non-owning assertion may fail under the mutant** — so the mutant flips exactly the one thing it targets.
- Prefer stable per-assertion identifiers or structured per-probe results over scraping prose, and fail closed when a declared owner identifier is missing rather than treating the absence as a match.
- A one-off run certifies the author's attention at one moment; the encoded probe is what stops a later fixture change from silently re-blinding the suite, and it is what makes the sensitivity claim re-checkable by CI instead of a sentence in an MR description.
- Two failure modes the probe must itself guard: **an anchor that stops matching** — if the mutation is applied by locating a line, a refactor that moves it yields a "mutant" byte-identical to the original, which passes and proves nothing, so assert the injection landed (literal-substring anchors, then verify the mutant differs) and fail loudly when it did not; and **a recursion guard** so the child runs skip the probe.
- Budget it honestly — one suite-rerun per predicate — and if that is too slow for the lane, mutate the predicates directly rather than dropping the check.
- For a pinned contract or prose artifact, the probe set grows with the artifact's own failure modes, not only the mutation list: **relocation** — a pinned section moved elsewhere in the file must still be matched (the stops-matching anchor rule above, applied per section); **reachability** — when the pinned body lives in a reference, assert the entrypoint's route to it still resolves (e.g. the firing signal and the pointer share the same entrypoint bullet), so the route cannot be dropped while every section pin stays green; **tree isolation** — mutants applied to a throwaway copy go RED there while the live tree's run stays green, making the disposable-checkout rule itself assertable; **parser completeness** — the probe discovers its pin list by parsing the fixture rather than a hand-kept list, so a newly added pin cannot be silently excluded from the walk. Coverage in the reverse direction — every obligation sentence of the pinned artifact names its pin — is the entry rule's artifact→pin discipline; the walk itself can never detect an unpinned obligation, which is why that enumeration is a separate recorded gate, not a walk output.

## Round-Trip Nuance

An ordinary encode/decode round-trip that feeds real output back through the real decoder is a valid invariant and does catch decoder defects; what it cannot do is prove agreement with an *external* mapping, which needs an oracle derived independently of the forward side. The narrow case the entry rule names is a reverse expectation computed from the same source as the forward one, so both drift together — not round-trips in general.
