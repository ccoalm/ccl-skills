---
description: Install or refresh CCL skills for OpenCode
argument-hint: "[--project]"
---

Run the CCL OpenCode installer from the repository root.

Use `--project` when the user wants project-local `.opencode/skills`, `.opencode/commands`, and `.opencode/plugins` copied into this repository.

```bash
bash scripts/install-opencode.sh $ARGUMENTS
```

After installation, tell the user to restart OpenCode or open a new session.
