# evidence Agent Contract

Frozen artifacts for round 158: the validation record, the replay runners
behind its numbers and their per-run record, and the review pass records with
their dispositions.

Rules:

- **Frozen after landing.** Do not edit, regrade or regenerate these files to
  improve a later conclusion. Overturn a reading with a new measurement in a new
  round's evidence directory and cite it from that round's register row.
- **The runners are evidence tools, not repository gates.** They call live
  models, are non-deterministic, and must never be wired into `make test` or any
  blocking check. A run proves only what one model produced on one prompt.
- **Read the runner before citing a number.** Each one disables tools and hooks,
  runs in an empty directory and states in its docstring what it counts. The
  regex graders are recall aids: the scope counts in the validation record come
  from by-hand readings kept in the per-run records, and the triage replay reads
  a marker the model emits.
- **Neutral domain only.** Scenarios use a synthetic report-export service; no
  credentials, host paths, source sessions' product terms or requester text.

Validation:

- `python3 -m py_compile specs/158-review-finding-scope/evidence/*.py`
- `bash skills/skill-extraction-workflow/scripts/check-ccl-skills.sh .`
