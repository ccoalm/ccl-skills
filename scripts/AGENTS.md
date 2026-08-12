# scripts Agent Contract

Root scripts install, update, validate, and dispatch the CCL skill package.

Rules:

- Keep scripts path-portable and idempotent. Prefer explicit flags over hidden
  host-specific behavior.
- Do not hard-code personal paths, secrets, or credentials.
- Destructive cleanup scripts must be dry-run by default or protected by
  explicit apply flags and negative tests.
- Installer and runtime-surface changes are shared-skill behavior changes.

Validation:

- `bash skills/skill-extraction-workflow/scripts/check-ccl-skills.sh .`
- Relevant script self-tests for touched scripts.
