---
description: Refresh CCL skills for OpenCode and remind to restart
argument-hint: "[--project]"
---

Refresh the CCL OpenCode assets from the ccl-skills repository root.

Use `--project` when the user wants project-local `.opencode/skills`, `.opencode/commands`, `.opencode/plugins`, and install manifest updated in this repository.

First fast-forward the source checkout so this does not simply reinstall an old local copy and reset the reminder clock.

```bash
git status --short --branch
git pull --ff-only && \
bash scripts/install-opencode.sh $ARGUMENTS
```

After updating, tell the user to restart OpenCode or open a new session so the refreshed plugin, commands, and skills are loaded.
