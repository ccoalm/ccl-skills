# harness Agent Contract

The scripts that produced the F41–F44 paired evaluation in `..`, kept exactly
as run with local paths generalized.

Rules:

- **Records, not a maintained tool.** Do not extend or fix these scripts; a
  later evaluation copies what it needs or uses the maintained harness
  `skills/skill-extraction-workflow/scripts/skill-behavior-eval.py`.
- **Not run by any gate.** Nothing in CI or `make` executes these files.
- `oracle/` holds the hand-written answers used to check that each judge can
  return a failing verdict, and the judge's output on them.

Validation:

- `python3 -m py_compile specs/typescript-dev-skill/evidence/behavior-eval/harness/*.py`
