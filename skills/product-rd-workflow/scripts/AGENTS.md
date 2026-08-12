# skills/product-rd-workflow/scripts Agent Contract

Scripts here implement product-RD workflow checks such as AGENTS coverage.

Rules:

- Keep checks deterministic, repo-scoped, and safe on legacy repositories.
- Group-parent detection must avoid false root findings for GitLab group
  checkouts.
- `--fix` may add files but must never overwrite existing contracts or follow
  symlinks.
- Enforcement behavior changes require focused tests or explicit behavioral
  evidence plus independent review/challenge.

Validation:

- Run the touched script against a fixture or representative repo.
- `bash skills/skill-extraction-workflow/scripts/check-ccl-skills.sh .`
