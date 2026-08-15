---
description: Refresh CCL skills for OpenCode and remind to restart
argument-hint: "[--project]"
---

Refresh the CCL OpenCode assets. There are two installation modes — use the one matching how the user installed ccl-skills.

## Source-repo mode (Git checkout)

If ccl-skills is installed from a Git source checkout (the `scripts/install-opencode.sh` path):

Use `--project` when the user wants project-local `.opencode/skills`, `.opencode/commands`, `.opencode/plugins`, and install manifest updated in this repository.

First fast-forward the source checkout so this does not simply reinstall an old local copy and reset the reminder clock.

```bash
git status --short --branch
git pull --ff-only && \
bash scripts/install-opencode.sh $ARGUMENTS
```

## npm CLI mode (`ccl-skills`)

If ccl-skills was installed via the npm package (`npm install -g @ccoalm/ccl-skills`), do NOT silently run a global npm install. Instead:

1. First preview what the update would do (this is a dry-run, no changes):

```bash
ccl-skills update
```

2. Show the user the preview output and ask them to confirm before proceeding.

3. Only after the user explicitly confirms, run the real update:

```bash
ccl-skills update --yes
```

The update command runs `npm install -g @ccoalm/ccl-skills@latest` (using the user's npm config for registry/auth) and then refreshes the assets for every detected host. Pass `--host opencode` to limit the operation.

## After updating (both modes)

Tell the user to restart OpenCode or open a new session so the refreshed plugin, commands, and skills are loaded.
