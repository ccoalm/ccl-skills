# @ccoalm/ccl-skills

[![npm version](https://img.shields.io/npm/v/@ccoalm/ccl-skills)](https://www.npmjs.com/package/@ccoalm/ccl-skills)
[![downloads](https://img.shields.io/npm/dm/@ccoalm/ccl-skills)](https://www.npmjs.com/package/@ccoalm/ccl-skills)
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

Requirements: Node.js 20 or later, macOS or Linux, and at least one host CLI — Claude Code, Codex 0.133.0 or later, or OpenCode.

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

Limit any operation to one host with `--host claude`, `--host codex`, or `--host opencode`. Add `--json` for machine-readable output.

`update` and `uninstall` are previews unless `--yes` is supplied. `update --yes` first upgrades the global npm package to `@latest`, then asks the freshly installed CLI to refresh host assets. Set `CCL_SKILLS_SKIP_SELF_UPDATE=1` for an assets-only refresh; `--allow-downgrade` always uses the currently invoked package without installing `@latest` first.

After `ccl-skills uninstall --yes`, remove the CLI package itself with `npm uninstall --global @ccoalm/ccl-skills` if it is no longer needed.

## Update notice

Nothing here updates itself. An interactive run prints a one-line notice on **stderr** when a newer version exists, at most once a day per version:

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
