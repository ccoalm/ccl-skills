# @ccoalm/ccl-skills

Self-contained CCL Skills installer for Claude Code, Codex, and OpenCode. The package carries an immutable snapshot of the skills, agent context, plugin manifests, and runtime hooks, so normal installation does not need a Git checkout. Claude Code and Codex consume their plugin hooks directly; OpenCode installs a native event adapter and the same bundled hook runtime.

## Requirements

- Node.js 20 or later
- At least one supported host CLI: Claude Code, Codex 0.133.0 or later, or OpenCode
- macOS or Linux

## Install

```bash
npm install --global @ccoalm/ccl-skills
ccl-skills install
```

Run without a global install:

```bash
npx @ccoalm/ccl-skills@latest install
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

## Update notice

Nothing here updates itself. An interactive run prints a one-line notice on **stderr** when a newer version exists, at most once a day per version:

```
Update available: 0.2.0 -> 0.3.0
Run: ccl-skills update --yes
Silence: CCL_SKILLS_NO_UPDATE_NOTIFIER=1
```

The registry check runs at most once every 24 hours in a detached background process, so no invocation waits for the network, and its result is shown by the next run. The notice and its check are both silent under `--json`, in CI, when stdout or stderr is not a terminal, in terminals narrower than 60 columns, and when `CCL_SKILLS_NO_UPDATE_NOTIFIER` or `NO_UPDATE_NOTIFIER` is set. State lives in `version-check.json` under the managed root; a failed check keeps the last known version and never blocks or fails the command.

Claude and Codex use package-owned local marketplace snapshots. OpenCode exposes skills, its native plugin, and `ccl-skills/runtime` through shared host directories. The native adapter maps the shipped session, tool, prompt, subagent, and stop behaviors to OpenCode events and covers `edit`, `write`, and `apply_patch`. Installation refuses unknown collisions, and uninstall preserves shared files for manual cleanup instead of guessing ownership.

Set `CCL_SKILLS_REPO` to a valid checkout to override only the OpenCode asset source. An invalid override fails before writing host files. Without the variable, installation is offline after npm has downloaded the package.

## Build and test

```bash
npm ci
npm test
npm run test:pack
```
