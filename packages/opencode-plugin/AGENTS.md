# opencode-plugin Agent Contract

OpenCode assets expose CCL skills and commands to OpenCode hosts.

Rules:

- Keep command entries short and route to owner skills; do not duplicate long
  workflow bodies here.
- Do not embed model choices, credentials, personal MCP config, or local
  absolute paths.
- Match OpenCode schema exactly; verify schema before adding new fields.
- Changes to command behavior or routing are non-wording shared-skill changes.

Validation:

- `bash skills/skill-extraction-workflow/scripts/check-ccl-skills.sh .`
- JSON/schema validation when OpenCode config changes.
