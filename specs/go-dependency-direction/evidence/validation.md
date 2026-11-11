# Validation

## Probe

One forced-choice question, sent with no tools and no project settings
(`claude -p --model sonnet --tools "" --setting-sources ""`), five parallel
runs per section text. The section text is the Dependency Direction section of
`architecture-playbook.md` from its heading to the end of the rules list.

Question:

> A Go service follows the architecture guidance below. It has a package
> `domain/order` (order rules and state transitions) and a package
> `infra/mysql` (the MySQL repository adapter for orders). You must draw the
> import arrows exactly as the "Recommended" diagram in the guidance shows
> them. According to that diagram, which source-code import does the guidance
> recommend? A: `domain/order` imports `infra/mysql`. B: `infra/mysql` imports
> `domain/order`. Reply with exactly one letter.

| Section text | Runs | Answers |
| --- | --- | --- |
| Base (`origin/main` at 55c3ce5) | 10 | A in 8; 2 runs returned no output |
| Candidate, first draft (rule in a paragraph under the diagram) | 5 | B in 5 |
| Candidate, second draft (rule in the rules list) | 5 | B in 5 |
| Candidate, final (after the challenge fixes) | 5 | B in 5 |

A is the import the section's own rules forbid. The question asks what the
diagram shows, so it measures how the diagram reads, not what a model would
build from the whole file. The two empty base runs were not diagnosed.

## Red baseline and mutants for the contract test

`POINTER_ROOT=<export of origin/main> bash skills/skill-extraction-workflow/scripts/test_routing_pointer_integrity.sh`
exits 1 with exactly five failures, the five assertions this round adds. On
the candidate it prints `routing_pointer_integrity_ok`.

Each mutant is one replacement applied to the candidate's playbook in a fresh
copy of the tree, then the suite is run against that copy:

| Mutant | Replacement | Result |
| --- | --- | --- |
| Arrow appended to the first import line | the line gains ` -> infrastructure adapter` | exit 1: the absent pin and the whole-line pin for that line |
| Adapter line deleted | `          infrastructure adapters -> domain` removed | exit 1: the whole-line pin for that line |
| Arrow appended to the generated-code line | the line gains ` -> domain` | exit 1: the whole-line pin for that line |
| Rule sentence deleted | `The domain never imports an adapter package. ` removed | exit 1: the rule pin |

No assertion outside the mutated one's own failed in any mutant.

## Commands on the candidate

The host's system Python has no PyYAML, so the lanes ran with a virtual
environment holding `requirements-test.txt` first on `PATH`. The session umask
was 077, which made the worktree's files mode 600 and failed two permission
assertions in the evaluation tests; the lanes below ran with umask 022 and
conventional file modes.

| Command | Result |
| --- | --- |
| `CCL_SKILL_BASE_REF=origin/main bash skills/skill-extraction-workflow/scripts/check-ccl-skills.sh .` | `ccl_skill_check_interim_ok` (`r0_status=public-fallback`: no private alias audit is configured on this host) |
| `bash skills/skill-extraction-workflow/scripts/test_check_ccl_regressions.sh --heavy-only` | `test_check_ccl_regressions_heavy_only_ok`, 9 suites |
| `python3 scripts/check-public-sanitization.py .` | `public_sanitization_ok` |
| `make test-repo-gates` | Every step passed except the last (`python3 -m unittest eval.…`): in the full run three cases of `test_provider_subprocess_is_reaped_on_parent_signals` failed with the host load average above 40; that step rerun alone passed, 119 tests |
| `make test-regressions-fast` | `test_check_ccl_regressions_fast_ok` |
| `make test-code-review` | Not passed locally; left to CI. Shard 1 failed in `test_opencode_review_retry.sh` (11 timeout cases; the suite took 1,094 s) and a rerun of that suite alone left one failing case. Shard 2 and the abort-leak lane were stopped unfinished after 55 minutes. The host load average stayed between 40 and 70 from another workspace throughout. This change touches no file under `skills/code-review/` (`git diff origin/main -- skills/code-review` is empty), but a control run of the suite on `origin/main` under the same load was stopped before it finished, so the load explanation is not confirmed locally. The maintainer chose the pull request's CI run as the result for this lane |

Two earlier full-lane runs failed for reasons that are recorded here because
they changed the candidate's shape. The impact-chain gate cuts rounds at
commits that touch the register, so a third local commit that changed both
owners and edited a row of the second commit read as a round with no row; the
local commits were combined into one. And this round's plan cited the
consolidation plan by its `specs/` path before that plan is on `main`; the
citation was replaced with a description.

## Reviews

All three passes ran through `extraction_review_gate.sh` with the Codex
reviewer; the implementer family was declared as Claude.

| Pass | File | Result | Disposition |
| --- | --- | --- | --- |
| Review (base `origin/main`, first draft) | `review.json` | 2 × P2 | R1 applied: this file. R2 is a packet gap, not a candidate defect; the challenge packet added the assertion helpers, the exit handling and the full section. |
| Challenge (base `origin/main`, second draft, widened packet) | `challenge.json` | 3 × P2 | C1 applied: the rule no longer says the adapter package must import the inner layer; Go satisfies an interface implicitly, so it imports inner-layer packages only for the types its signatures use. C2 applied: the three import lines are pinned as whole lines and the absent pin covers singular and plural; the mutants above include the reviewer's appended-arrow case. C3 deferred: the reviewer asks for the selected skill bodies inside the packet; the controller binds owners by name and hash and this lane does not paste skill bodies into packets. |
| Delta (base the challenged commit, the challenge fixes only) | `delta-review.json` | 2 × P2 | Last reviewer call. D1 repeats C3, same disposition. D2 applied: the mutant definitions, the baseline and the command results are recorded above. |

The three passes reviewed local commits that were later combined into one;
each result file records the digest of the packet it read.
