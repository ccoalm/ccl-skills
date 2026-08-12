# skills/skill-extraction-workflow/scripts Agent Contract

Scripts here validate shared CCL skills, routing surfaces, extraction
discipline, and structural invariants.

Rules:

- Keep validators deterministic and explicit about warning versus blocking
  status.
- Do not broaden allowlists or downgrade failures without a recorded rationale
  and regression evidence.
- Route/frontmatter checks must fail closed on malformed YAML or stale route
  references that affect behavior.
- Script changes need self-tests or fixture coverage where feasible.

Validation:

- `bash skills/skill-extraction-workflow/scripts/check-ccl-skills.sh .`
