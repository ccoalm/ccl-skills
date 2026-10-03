# evidence Agent Contract

Frozen measurement artifacts for round 156: the validation record and the
replay runner that produced its firing-point numbers.

Rules:

- **Frozen after landing.** Do not edit, regrade or regenerate these files to
  improve a later conclusion. Overturn a reading with a new measurement in a new
  round's evidence directory and cite it from that round's register row.
- **`recheck_replay.py` is an evidence tool, not a repository gate.** It calls a
  live model, is non-deterministic, and must never be wired into `make test` or
  any blocking check. A run proves only what one model produced on one prompt.
- **Read the runner before citing a number.** It reads `DECISION_RECHECK` from
  each checkout given on the command line, disables tools and hooks, runs in an
  empty directory, and counts a run as `none` when neither verdict line appears;
  a `none` is a grading miss, never a pass for either arm.
- **No credentials, host paths or third-party content.** Scenario text is
  synthetic and uses a neutral domain.

Validation:

- `python3 -m py_compile specs/156-stop-recheck-escape-terms/evidence/recheck_replay.py`
- `bash skills/skill-extraction-workflow/scripts/check-ccl-skills.sh .`
