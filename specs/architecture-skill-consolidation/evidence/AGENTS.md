# evidence Agent Contract

Frozen artifacts for the architecture-skill consolidation: the validation
record, the two scripts that rebuild the migrated references from the old
skills, and the review pass records with their dispositions.

Rules:

- **Frozen after landing.** Do not edit or regenerate these files to improve a
  later conclusion. A later round records its own evidence in its own directory.
- **The scripts are evidence tools, not repository gates.** They read the two
  old skills from a base ref that still contains them, so they stop being
  runnable against a ref that has no such history. Never wire them into
  `make test` or any blocking check.
- **They rebuild, they do not judge.** `migrate_refs.py verify` and
  `entry_rules.py verify` prove that the migrated files equal what the scripts
  produce from the old text and that no old block was dropped. Whether a
  hand-merged block keeps the meaning of the two blocks it replaced is a
  reading, recorded in the zero-loss map and checked by review.

Validation:

- `python3 -m py_compile specs/architecture-skill-consolidation/evidence/*.py`
- `python3 specs/architecture-skill-consolidation/evidence/migrate_refs.py . 2126c9d verify`
- `python3 specs/architecture-skill-consolidation/evidence/entry_rules.py . 2126c9d verify`
