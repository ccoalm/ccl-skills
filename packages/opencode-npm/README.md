# @ccoalm/ccl-skills-opencode

OpenCode plugin and installation CLI for CCL Skills.

## Requirements

- Node.js 18 or later
- OpenCode with `@opencode-ai/plugin` 1.0 or later

## Plugin mode

Add the package to a global or project `opencode.json`:

```json
{
  "plugin": ["@ccoalm/ccl-skills-opencode"]
}
```

Restart OpenCode after changing the configuration. Plugin mode loads the bootstrap and worktree protection hooks; it does not install the skill directories.

## CLI mode

Install the package, then use the CLI to manage the local adapter files:

```bash
npm install -g @ccoalm/ccl-skills-opencode
ccl-skills-opencode install
ccl-skills-opencode doctor
ccl-skills-opencode update
ccl-skills-opencode update --yes
ccl-skills-opencode uninstall
ccl-skills-opencode uninstall --yes
```

`update` and `uninstall` are previews unless `--yes` is supplied. The uninstaller only removes files owned by its manifest and leaves skills and project commands intact.

To install the skill directories from a checkout, set `CCL_SKILLS_REPO` to the repository root before running `install`:

```bash
CCL_SKILLS_REPO=/path/to/ccl-skills ccl-skills-opencode install
```

Install command shortcuts into a project with:

```bash
ccl-skills-opencode install-commands /path/to/project
```

## Registry configuration

The package uses the registry configured by npm. Configure private or mirrored registries in the user's `.npmrc` or through standard npm environment variables. Do not commit registry credentials.

## Build

```bash
npm ci
npm run build
npm run verify
```

The build compiles `src/` into `dist/` and copies the versioned adapter assets from the repository. `@opencode-ai/plugin` is an optional peer dependency because the OpenCode host supplies it at runtime.
