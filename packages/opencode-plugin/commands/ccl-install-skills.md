---
description: Install or refresh CCL skills for OpenCode
argument-hint: "[--project]"
---

Install or reapply the CCL assets using the current installation mode. Check the existing CCL installation record and available entrypoint before running a command.

For an npm installation, reapply the invoked package's OpenCode assets:

```bash
ccl-skills install --host opencode
```

For a newer package version, follow `/ccl-update-skills`. The npm package does not include the source installer or support `--project`; do not forward that flag to the npm CLI.

For a source checkout, locate the actual CCL repository and verify its installer exists. By default, from that checkout run:

```bash
bash scripts/install-opencode.sh --no-agent $ARGUMENTS
```

Use `--project` only for source mode when the user wants `.opencode/skills`, `.opencode/commands`, and `.opencode/plugins` copied into that checkout. Do not run a relative source-installer path in an unrelated project.

For a global source installation, omit `--no-agent` when the user also needs `~/.agents/skills` for another tool. To sync only that compatibility path, run `bash scripts/install-opencode.sh --only-agent`; this mode does not install OpenCode assets and cannot be combined with `--project` or `--no-agent`.

After OpenCode assets change, restart OpenCode or open a new session. After a compatibility-only sync, restart the tool that reads `~/.agents/skills`.
