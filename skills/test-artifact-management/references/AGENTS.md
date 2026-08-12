# skills/test-artifact-management/references Agent Contract

References here define testcase/report generation behavior and helper
conventions consumed by product repositories.

Rules:

- Keep examples source-neutral and free of private project names, tokens,
  hostnames, or personal paths.
- Report generation must not fabricate pass status; blocked, skipped, failed,
  and unlinked cases must remain distinguishable.
- Read-modify-write examples must fail loudly on read/write errors and preserve
  existing state.
- Behavioral changes to report semantics need tests.

Validation:

- `python3 -m pytest -q skills/test-artifact-management/references/test_gen_report.py`
