# @ccoalm/ccl-skills

Self-contained CCL Skills installer for Claude Code, Codex, and OpenCode. The package carries an immutable skill snapshot, so normal installation does not need a Git checkout.

## Requirements

- Node.js 20 or later
- At least one supported host CLI: Claude Code, Codex 0.133.0 or later, or OpenCode
- macOS or Linux

## Install

```bash
npm install --global @ccoalm/ccl-skills
ccl-skills install
```

The CLI detects installed hosts. Limit an operation with `--host claude`, `--host codex`, or `--host opencode`.

```bash
ccl-skills install --host codex
ccl-skills doctor
ccl-skills update
ccl-skills update --yes
ccl-skills uninstall
ccl-skills uninstall --yes
```

`update` and `uninstall` are previews unless `--yes` is supplied. By default, `update --yes` first upgrades the global npm package to `@latest`, then asks the freshly installed CLI to refresh host assets. Set `CCL_SKILLS_SKIP_SELF_UPDATE=1` for an assets-only refresh. `--allow-downgrade` always uses the currently invoked package without installing `@latest` first.

After `ccl-skills uninstall --yes`, remove the CLI package itself with `npm uninstall --global @ccoalm/ccl-skills` if it is no longer needed.

Claude and Codex use package-owned local marketplace snapshots. OpenCode must expose skills through shared host directories; installation refuses unknown collisions, and uninstall preserves those shared files for manual cleanup instead of guessing ownership.

Set `CCL_SKILLS_REPO` to a valid checkout to override only the OpenCode asset source. An invalid override fails before writing host files. Without the variable, installation is offline after npm has downloaded the package.

## Build and test

```bash
npm ci
npm test
npm run test:pack
```
