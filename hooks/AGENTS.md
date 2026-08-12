# hooks Agent Contract

Hooks are plugin-shipped runtime enforcement surfaces. Hosts may execute them on
session start or tool use, so changes here are shared-skill behavior changes.

Rules:

- Keep hooks deterministic, fail-closed where safety requires it, and explicit
  about advisory versus blocking outcomes.
- Do not read secrets or personal config unless the hook's contract documents
  why and how failures degrade.
- Avoid broad filesystem mutation from hooks.
- Non-wording changes require deterministic validation plus independent review
  and adversarial challenge before landing.

Validation:

- `bash skills/skill-extraction-workflow/scripts/check-ccl-skills.sh .`
- `git diff --check`
