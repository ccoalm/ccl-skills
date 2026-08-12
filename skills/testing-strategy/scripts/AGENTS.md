# skills/testing-strategy/scripts Agent Contract

Scripts here support test strategy validation and harness checks.

Rules:

- Keep checks deterministic and explicit about what layer they prove.
- Do not let log-only or smoke-only checks masquerade as assertion-based test
  evidence.
- Changes to status mapping, gate semantics, or report output require regression
  tests.
- Avoid live service dependencies in default script paths.

Validation:

- Run the touched script's `.test.sh` or focused pytest equivalent.
- `bash skills/skill-extraction-workflow/scripts/check-ccl-skills.sh .`
