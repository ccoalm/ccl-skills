# Behavior evidence

Tool: `skills/skill-extraction-workflow/scripts/skill-paired-eval.py`, arms `base` (`326374b`) and `candidate`. Model `claude-opus-5-5`, CLI default effort, $4 cap per run. Every task is a synthetic job-scheduler repository built from scratch. The decisive task's repository, prompt and grader are published in `legacy-model-task.md`; the other two tasks, the run records and the transcripts stay in the maintainer's private archive.

## Grading

Each world is graded after the run by a hidden Node test that imports the modules from every worktree of the world's repository. A sample passes if any worktree passes all of these:

- the writer stores `auto` for the Auto choice;
- the reader under test no longer turns `auto` into the absence default (60 minutes);
- controls hold: `30m` and `15m` still compute as before, and a job with no interval still gets the 60-minute default.

Before any run, each grader was checked against the untouched world (fails), a fix that leaves the reader stale (fails) and a full fix (passes).

The challenge pass found that the first grader for the decisive task accepted a capacity result of `Infinity`, and it ignored the named consumers and the details mapper. That grader was tightened (see `legacy-model-task.md`). Under the tightened grader a mutant that makes the mapper return null without fixing capacity now fails. Every sample of that task was then regraded, and the counts did not change.

## Results

| Task | Shape | Candidate | base pass | candidate pass |
| --- | --- | --- | --- | --- |
| `widened-field-stale-reader` | The fix stores `auto`; two readers share a minutes-only parser whose comment says the writer only produces minutes | `3621914` | 4/4 | 3/3 valid |
| `widened-field-sibling-reader` | The bug names one reader; an independent second reader has the same defect | `f5e8725` | 5/5 | 4/4 valid |
| `widened-field-legacy-model-reader` | The fix names two consumers that already use a newer cadence model; a legacy details mapper still parses the field and feeds capacity planning | `f5e8725` | **0/5** | **5/5** |

Invalid samples: one candidate run in the first task (`routing_injection_mismatch`), one in the second (`instruction_file_canary_seen`). Both were excluded by the tool's isolation checks.

The first two tasks hit a ceiling. Every file is visible in a three-module repository, and the base skills already find both readers. They show the change does not regress the easy case. They are not evidence of a delta.

The third task reproduces the shape of the escaped defect. All five base runs fixed the writer and both named consumers, and left the legacy mapper returning the 60-minute default for `auto`. Capacity planning therefore counted an Auto job as one run per hour. All five candidate runs changed the mapper to report unknown and kept the controls passing. Fisher exact two-sided p ≈ 0.008 for 0/5 against 5/5. That holds for this one task and model only.

Both arms loaded `defect-diagnosis` in every run of the third task. Only candidate transcripts contain the new Phase B line. The pointer to `refactoring-discipline.md` was not followed in those runs, so the measured effect comes from the entrypoint line. The canonical reference text is not measured.

`3621914` and `f5e8725` differ only in example words: `anchor` became `variant`, and "a content-sized marker" became "an `unknown` state".

## Replays on later text

The rule was narrowed after `f5e8725`, so the decisive task's candidate arm was rerun on later text. The base arm's ref did not change and was not rerun.

| Candidate | What changed since the previous measurement | candidate pass |
| --- | --- | --- |
| `9224c5d` | only a reader that cannot interpret the form reports unknown; the enum wording was corrected | 5/5 |
| `c4c7560` | contract-defined rejection and safe fallbacks are kept; the `defect-diagnosis` line was trimmed to its word budget (final text) | 5/5 |

Spend: $4.32 + $4.62 + $5.84 + $2.72 + $2.66.
