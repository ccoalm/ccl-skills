# Validation evidence

## Why the scan is the only guard

Scratch repository, git 2.50.1: a worktree held an ignored `out/model.bin`.
`git -C <wt> status --porcelain -uall` printed nothing and exited 0;
`git -C <wt> status --ignored -s` printed `!! out/`; `git worktree remove <wt>`
without `--force` exited 0 and deleted the directory with the file. A clean
`git status` and git's own refusal therefore say nothing about gitignored
outputs.

## Surfaces that restate the removal

Searched every tracked file outside `specs/` for the command form
(`worktree remove`, `worktree prune`), for English and Chinese prose forms of
removing or cleaning up a worktree, and for `rm -rf` near worktree paths.

| Surface | Form | Scan before | Names the canonical section | Disposition |
| --- | --- | --- | --- | --- |
| `product-rd-workflow/references/worktree-mechanics.md`, Closeout Cleanup | three-command list | no | no | updated |
| `multi-agent-delegation/references/multi-agent-delegation-playbook.md`, step 5 | prose, three removal paths | no | routine cleanup routed in step 1 only | updated |
| `skill-extraction-workflow/references/extraction-lifecycle-handoff.md` | inline command | no | no | updated |
| `worktree-isolation/references/merge-and-teardown.md`, finishing-skill handoff | routing sentence | rule above covers "external tools" but the handoff did not say so | is the canonical section | updated |
| `docs/worktree-isolation-handbook.md` | commands and explanation | yes | no; four pointers named the entrypoint for moved sections | updated |
| `hooks/remind-post-merge-cleanup.sh` | injected reminder | yes | yes | unchanged (pinned by its own suite) |
| `agent-context/session-start.md`, `agent-context/session-policy.md` | always-on | yes | yes | unchanged |
| `docs/skills-theory-foundations.md` | summary | yes | not a recipe | unchanged |
| `docs/SKILLS.md`, `docs/ARCHITECTURE.md` | description | n/a | n/a | not a recipe |
| `.opencode/commands/*.md` | host commands | no removal step | n/a | unchanged; now inside the sweep roots |
| test scripts removing their own probe worktrees | fixture teardown | n/a | n/a | not guidance |
| `worktree-isolation/scripts/worktree-sweep.sh` | implementation | built-in check keeps ignored content | n/a | unchanged |

The installed external finishing skill (versions 6.3.0 and 6.4.1) removes the
worktree with one `git worktree remove`; it never passes `--ignored`, and its
refusal path inspects `status --porcelain -uall` only.

## Pins on the base text and on the candidate

The final 24-row table was evaluated one row at a time against the base tree
(each run kept a single row; the rest of the fixture passed first).

| Rows | Base | Candidate |
| --- | --- | --- |
| product-rd Closeout Cleanup, 8 section rows and 1 order row | all 9 fail | pass |
| delegation step 5, 4 line rows and 1 order row | all 5 fail | pass |
| extraction lifecycle note, 3 line rows | all 3 fail | pass |
| canonical: host-native removal, finishing-skill handoff | both fail | pass |
| canonical: scan before any removal, exit 0, list each entry, recompute cost, scan line before the remove line | all 5 pass (rules already present, now pinned) | pass |

Sweep on the base tree: exit 1, naming exactly three files —
`extraction-lifecycle-handoff.md` and `worktree-mechanics.md` (no
ignored-output scan) and `docs/worktree-isolation-handbook.md` (no pointer to
the canonical section). On the candidate: no offender, and the canonical file
was reached.

## Applied-mutation walk

`test_teardown_guard_pins.sh` on the candidate: 24 applied mutations, each red
on its own row's label (order rows are reordered inside their section); three
relocation probes, one per row kind, move a phrase out of its section or line
and red that row; ten decoy surfaces red the sweep for the stated reason — no
scan (in `skills/`, the root, `hooks/`, `scripts/`, `packages/` and
`.opencode/`), no pointer (in `docs/` and `agent-context/`), no exit-0
requirement, and a pointer that names only the file; five precision decoys stay
green — a compliant surface, a package-relative pointer inside the canonical
package, a prune-only mention, a file under `node_modules/` and a register row
naming the command; an unreadable directory and an unreadable file each red
the sweep; the unmutated copy is green before and after, and the live tree
stays green while a mutated copy reds.

Sabotaged copies of the fixture, each run through the walk (rc 1 means the walk
failed, as required):

| Sabotage | Walk result |
| --- | --- |
| section rows checked against the whole file | relocation probe: row stayed green with its phrase outside its section |
| line rows checked against the whole file | relocation probe: row stayed green with its phrase outside its line |
| sweep pointer check removed | sweep decoy stayed green: `docs/zz-teardown-decoy.md` |
| `docs` dropped from the sweep roots | sweep decoy stayed green: `docs/zz-teardown-decoy.md` |
| order rows not evaluated | mutant stayed green on the product-rd order row |
| sweep scan check removed | decoy red for the wrong reason (no pointer instead of no scan) |

## Pointers that name a moved section

Round 161 (`specs/161-firing-point-loading/`) moved worktree-isolation's merge and
teardown sections into
references and searched non-Markdown files for the path, as its recipe asked.
On the merged tree that search returns registries and suites only, nothing
under `docs/`. Searching Markdown outside `specs/` for each moved section's
name returns the three handbook lines that named the entrypoint for
「合并回目标分支前」, 「"已集成"判据」 and the merge protocol (a fourth pointer,
in the further-reading list, described the entrypoint as holding the full
pre-merge command sequence). The other hits name the protocol by skill and
section without a file, which the entrypoint's pinned forwarding sentence
resolves.

## Behavior

Synthetic repository per run: `feat-x` merged into `dev` locally (provable by
ancestry), its worktree holding an ignored `data/features.parquet` with a note
that it takes about six hours to regenerate, plus an ignored `node_modules/`.
Headless Claude Code (Opus 5.5), five runs per arm; the plugin was loaded only
from an exported copy, with user settings, CLAUDE.md files, auto memory and MCP
servers off. An isolation run per plugin arm quoted the first sentence of the
always-on routing block and found no user-level instructions. Criteria and the
decision rule were written before the runs; the primary grade is whether the
expensive file still exists anywhere afterwards.

Prompt: clean up the `feat-x` worktree and local branch following
product-rd-workflow's `references/worktree-mechanics.md` Closeout Cleanup.

| Arm | Lost the file | Cleaned up on its own | Forced removal |
| --- | --- | --- | --- |
| previous text, plugin loaded | 0/5 | 5/5 | 0/5 |
| this round's recipe (`d46e07d`), plugin loaded | 0/5 | 5/5 | 0/5 |
| no plugin | 2/5 | 2/5 | 0/5 |

By the recorded rule this is a ceiling: with the plugin loaded, the always-on
routing block and the previous recipe's routing line led every run to the
canonical closeout section, which it followed. The pairing shows no regression
and does not show an improvement. The no-plugin arm found the previous recipe in
the installed plugin cache (byte-identical to the previous text) and followed
it: both runs that cleaned up deleted the file, and the other three stopped and
asked. That arm was meant only as a control and is reported as an observation.

A second pairing, also recorded before it ran, isolates the recipe text: no
plugin, the recipe under test committed into the synthetic repository as
`ops/worktree-mechanics.md`, and the prompt pointing at it. No run read any
other copy of a recipe or skill.

| Recipe, no plugin | Lost the file | Cleaned up on its own | Stopped and asked |
| --- | --- | --- | --- |
| previous text | 2/5 | 2/5 (both lost the file) | 3/5 |
| this round's text | 0/5 | 5/5, scan before removal in every run | 0/5 |

This meets the recorded rule for "the recipe text carries the guard on its
own". With five runs per arm, 2/5 against 0/5 is a direction, not a significant
difference; the larger contrast is that every run on the new text finished the
cleanup safely without handing the decision back, which the rule recorded as a
descriptive measure. Single scenario, single model.

## Lanes

The first full `make test` on a candidate with the register rows failed in the
fast lane: the sweep read the new register rows, which describe the old recipe
and so name `worktree remove` without the scan. The register records history,
not recipes, so the sweep now skips it like round records and evaluation
inputs, and the walk keeps a register row naming the command as a precision
decoy.

LANES_PENDING
