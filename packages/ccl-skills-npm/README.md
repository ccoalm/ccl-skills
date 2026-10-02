# @ccoalm/ccl-skills

[![npm version](https://img.shields.io/npm/v/@ccoalm/ccl-skills)](https://www.npmjs.com/package/@ccoalm/ccl-skills)
[![downloads](https://img.shields.io/npm/dt/@ccoalm/ccl-skills)](https://www.npmjs.com/package/@ccoalm/ccl-skills)
[![license](https://img.shields.io/npm/l/@ccoalm/ccl-skills)](https://github.com/ccoalm/ccl-skills/blob/main/LICENSE)

**Reusable workflows that help coding agents plan, build, test, review, and release software.**

Not a prompt pack — a routed delivery system. 33 skills cover the whole lifecycle, and a routing layer reads what you asked for and hands it to the skill that owns that deliverable, so you never look one up.

Ask it to fix a bug and `defect-diagnosis` takes over: reproduce from first-hand failure evidence, isolate the cause, verify the fix, leave a regression test behind. Ask for a feature and `product-rd-workflow` routes it through requirement shaping, risk gates, implementation, and release. Ask it to touch code at all and `worktree-isolation` puts the work on its own branch first. Every skill also states when *not* to use it and which one to use instead — that is what keeps the routing sharp.

Each skill is a method, not a suggestion, and it ships with the gate that protects it. The methods are what worked, written down. The gates are what went wrong, turned into a stop: no patch before a reproduction, no edit on `main`, no *done* without evidence. A routing eval bank and CI gates check that both still fire.

## Install

```bash
npm install --global @ccoalm/ccl-skills
ccl-skills install
```

Restart your CLI so it reloads the skills.

`install` configures every host it detects. The package carries an immutable snapshot of the skills, agent context, plugin manifests, and runtime hooks, so installation needs no Git checkout.

Requirements: Node.js 20 or later, macOS or Linux, and at least one host CLI — Claude Code, Codex with working `plugin marketplace list` and `plugin list` commands, or OpenCode. Codex availability is checked through these commands rather than its version number.

Run it without a global install:

```bash
npx @ccoalm/ccl-skills@latest install
```

## What you get

| Stage | Covered by the skills |
| --- | --- |
| Requirements | intent and acceptance points, current-state baseline, change scope and slicing, PRD writing |
| Design | layout, interaction, states, accessibility, design-system consistency |
| Architecture | Go and Python service boundaries, RPC and API contracts, data ownership, reliability invariants |
| Implementation | Go, Python, React web, mini-programs, Flutter/React Native/iOS/Android, terminal and TUI, LLM integration |
| Testing | test layers, fixtures, mocks, regression coverage, CI gates, test-case documents, defect diagnosis |
| Review | independent CLI review, adversarial challenge, risk and gate routing, multi-perspective research |
| Release | rollout, canary, rollback, environment lanes, release scope and docs |
| Operations | logs, metrics, tracing, dashboards, alerts, SLO, service connectivity |
| Cross-stage | worktree isolation, multi-agent delegation, doc tightening, lesson extraction |

[Browse the full catalog](https://github.com/ccoalm/ccl-skills/blob/main/docs/SKILLS.md) for what each skill does and when to use another one instead. [Architecture](https://github.com/ccoalm/ccl-skills/blob/main/docs/ARCHITECTURE.md) explains how skills are selected, loaded, and checked; [Theory](https://github.com/ccoalm/ccl-skills/blob/main/docs/skills-theory-foundations.md) explains why the rules read the way they do.

This page ships inside the published tarball, so it only changes when a new version is released. The links above always show the current state.

## Commands

```bash
ccl-skills install           # write host assets
ccl-skills doctor            # report install state and drift from the manifest
ccl-skills update            # preview
ccl-skills update --yes      # upgrade the package, then refresh host assets
ccl-skills uninstall         # preview
ccl-skills uninstall --yes   # remove host assets
```

Limit these operations to one host with `--host claude`, `--host codex`, or `--host opencode`. Add `--json` for machine-readable output.

For `--host codex`, unreadable public plugin state returns exit `3` with `host-state-unknown`; a missing CLI or failed capability probe returns `4`. If that host failure occurs with a pending journal, recovery is deferred: exit `5` with `partial-journal` retains the journal and records `details.hostFailure`. Restore the CLI or readable public plugin state, then rerun the command. Other outcomes can share these exit codes, so inspect the JSON status as well.

Codex `doctor` also reads the native hook inventory. When every expected package hook is enabled, trusted (or managed), and matches the installed content, it returns exit `0` with `installed-hooks-trusted`. `details.hooks` distinguishes untrusted, modified, disabled, missing and unknown states. Trust checks do not execute hooks: `details.hooks.runtime` remains `unverified`. Install/update never approve hook trust automatically.

`update` and `uninstall` are previews unless `--yes` is supplied. `update --yes` first upgrades the global npm package to `@latest`, then asks the freshly installed CLI to refresh host assets. Set `CCL_SKILLS_SKIP_SELF_UPDATE=1` for an assets-only refresh; `--allow-downgrade` always uses the currently invoked package without installing `@latest` first.

After `ccl-skills uninstall --yes`, remove the CLI package itself with `npm uninstall --global @ccoalm/ccl-skills` if it is no longer needed.

## Automatic CCL updates

On macOS, explicitly enable daily CCL updates for one host:

```bash
# Existing Codex Git plugin; Codex is the default host
npx --yes @ccoalm/ccl-skills@latest auto-update enable
npx --yes @ccoalm/ccl-skills@latest auto-update status --json
npx --yes @ccoalm/ccl-skills@latest auto-update disable

# Existing npm-managed OpenCode skills, plugin and hooks
npx --yes @ccoalm/ccl-skills@latest auto-update enable --host opencode
npx --yes @ccoalm/ccl-skills@latest auto-update status --host opencode --json
npx --yes @ccoalm/ccl-skills@latest auto-update disable --host opencode
```

With the CLI installed globally, replace `npx --yes @ccoalm/ccl-skills@latest` with `ccl-skills`. Each command acts on one host and executes directly; `--yes` and `--host all` are unsupported. Installation never enables scheduling. Separate launchd jobs run every 24 hours while logged in and when loaded at login. A non-root macOS user is required; other platforms return exit `4` with `unsupported-platform`.

### Codex

The target is `ccl-skills@ccl-skills` in the current `CODEX_HOME`, or `~/.codex` when unset. Its marketplace and plugin must use the canonical `ccoalm/ccl-skills` Git repository over HTTPS or SSH, and the plugin must be enabled. Codex must support `--no-daemon` and plugin JSON output.

Each run checks public plugin state before and between these steps:

```bash
codex --no-daemon plugin marketplace upgrade ccl-skills
codex --no-daemon plugin add ccl-skills@ccl-skills
```

An unsuccessful upgrade prevents the add step. Each update command has a two-minute limit; timeout terminates its child process group. Source changes are checked at those boundaries; Codex does not provide an atomic compare-and-update operation. Restart Codex to load changes. Hook trust follows Codex's normal policy.

Codex npm installations use a local snapshot under `ccl-skills-npm`, which this scheduler refuses. Keep those current with `ccl-skills update --yes`. To migrate, preview removal with `ccl-skills uninstall --host codex`, then repeat with `--yes`. Register the Git installation explicitly:

```bash
codex --no-daemon plugin marketplace add https://github.com/ccoalm/ccl-skills.git
codex --no-daemon plugin add ccl-skills@ccl-skills
npx --yes @ccoalm/ccl-skills@latest auto-update enable
```

### OpenCode

OpenCode requires an existing healthy npm-managed CCL installation with bundled assets. The scheduler updates only its CCL skills, native plugin and hook runtime under `~/.config/opencode`. It preserves OpenCode itself, application configuration, authentication, unrelated files and `~/.agents`. Restart OpenCode to load changes.

Each run downloads `@ccoalm/ccl-skills@latest` from the public npm registry into a fresh private directory. It disables lifecycle scripts and package self-update, validates package identity, then invokes the fetched CLI's OpenCode doctor and update commands. It refuses missing installations, source overrides and locally changed managed files. A newer installed version is retained. Success requires a healthy receipt matching the fetched package version and bundled source.

Source-checkout installs are unsupported. To migrate, first back up their CCL files and receipt, move only those verified CCL-owned files out of OpenCode's shared directories, then explicitly run the npm installer:

```bash
npx --yes @ccoalm/ccl-skills@latest install --host opencode
npx --yes @ccoalm/ccl-skills@latest doctor --host opencode
npx --yes @ccoalm/ccl-skills@latest auto-update enable --host opencode
```

The scheduler never adopts or deletes a source-copy installation. Resolve any collision or drift reported by the installer before enabling it.

Package download has a three-minute limit; asset update has a two-minute limit. Cancellation sends SIGINT and allows ten seconds for rollback before forcing termination. A forced termination reports unknown finality; inspect `doctor --host opencode` before retrying. Fetch and preflight failures leave installed assets intact.

### Status and recovery

State lives in `$CODEX_HOME/ccl-skills-auto-update` for Codex and `~/.config/opencode/ccl-skills-auto-update` for OpenCode. Each profile has its own file in `~/Library/LaunchAgents`. The saved runner survives removal of an npx download and keeps the executable paths and profile selected at enable time. Those executables must remain installed. Re-enabling retains the saved runner; upgrading the npm CLI does not replace it.

Commands receive fixed HOME/PATH plus CODEX_HOME and `GIT_TERMINAL_PROMPT=0` for Codex, or the self-update/notifier opt-outs for OpenCode. npm uses private empty config files and cache. Credentials and source/registry overrides from the enabling shell are not persisted; macOS may add runtime variables.

`status` checks live registration and the latest bounded `last-run.json` record, which excludes raw command output. Failed or interrupted runs, registration errors and ownership errors return exit `5`. Restore the reported dependency and retry `enable` or `disable`. Overlapping runs are skipped. `disable` removes only that host's owned schedule and retains its runner, state and log. Disable first if removing the CLI should also stop updates.

SIGINT and SIGTERM release owned locks, including between commands. A crash or forced kill can leave a `run.lock` or `manage.lock`. A lock at least 15 minutes old, or dated at least 15 minutes into the future, reports failure even if its PID is alive. The scheduler never removes these locks automatically. Inspect the recorded PID and launchd job; remove only that lock after confirming no updater owns it. Never remove a running updater's lock.

## Update notice

The npm package does not update itself automatically. An interactive run prints a one-line notice on **stderr** when a newer version exists, at most once a day per version:

```
Update available: 0.2.0 -> 0.3.0
Run: ccl-skills update --yes
Silence: CCL_SKILLS_NO_UPDATE_NOTIFIER=1
```

The registry check runs at most once every 24 hours in a detached background process, so no invocation waits for the network, and its result is shown by the next run. The notice and its check are both silent under `--json`, in CI, when stdout or stderr is not a terminal, in terminals narrower than 60 columns, and when `CCL_SKILLS_NO_UPDATE_NOTIFIER` or `NO_UPDATE_NOTIFIER` is set. State lives in `version-check.json` under the managed root; a failed check keeps the last known version and never blocks or fails the command.

## What lands where

| Host | What the installer writes |
| --- | --- |
| Claude Code | A package-owned local marketplace snapshot; the plugin hooks are consumed directly. |
| Codex | The same package-owned local marketplace snapshot. |
| OpenCode | Skills, a native event plugin, and `ccl-skills/runtime` under shared host directories. The adapter maps the shipped session, tool, prompt, subagent, and stop behaviors to OpenCode events and covers `edit`, `write`, and `apply_patch`. |

Installation refuses unknown collisions, and uninstall preserves shared files for manual cleanup instead of guessing ownership.

Set `CCL_SKILLS_REPO` to a valid checkout to override only the OpenCode asset source. An invalid override fails before writing host files. Without the variable, installation is offline after npm has downloaded the package.

## Build and test

```bash
npm ci
npm test
npm run test:pack
```

Issues and pull requests go to [ccoalm/ccl-skills](https://github.com/ccoalm/ccl-skills); see [CONTRIBUTING](https://github.com/ccoalm/ccl-skills/blob/main/docs/CONTRIBUTING.md).
