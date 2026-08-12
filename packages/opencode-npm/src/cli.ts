#!/usr/bin/env node

// ccl-skills-opencode — CLI entry point.
//
// Subcommands: install, install-commands <project>, doctor, update, uninstall.
// No external runtime dependencies; uses only Node built-ins.

import { runInstall } from "./install.js"
import { runInstallCommands } from "./commands.js"
import { runDoctor } from "./doctor.js"
import { runUpdate } from "./update.js"
import { runUninstall } from "./uninstall.js"

const HELP = `\
ccl-skills-opencode — OpenCode distribution shell for ccl-skills

Usage:
  ccl-skills-opencode install [--no-agent]
      Install/refresh the global OpenCode plugin, bootstrap, commands, and
      manifest from bundled package assets. Skills are synced from the source
      repo when CCL_SKILLS_REPO is set; otherwise guidance is printed.
      --no-agent  Skip the ~/.agents/skills compatibility sync.

  ccl-skills-opencode install-commands <project-dir> [--force]
      Merge CCL command shortcuts (/rd, /risk, /bug, ...) into a target
      project's opencode.json. Creates the file if absent. Same-name commands
      are refused unless --force is passed; --force creates a timestamped
      backup before overwriting.

  ccl-skills-opencode doctor
      Read-only check of skills, plugin, bootstrap, commands, manifest,
      and npm package version (queries registry best-effort).
      Prints status and exits 0 regardless of findings.

  ccl-skills-opencode update [--yes]
      Preview (default) or execute a package upgrade + asset refresh.
      Without --yes: prints what would happen, executes nothing.
      --yes: runs  npm install -g <pkg>@latest  (uses your npm config for
      registry/auth), then refreshes plugin/bootstrap/commands/manifest.
      Restart OpenCode after updating.

  ccl-skills-opencode uninstall [--yes] [--force]
      Preview (default) or remove the global plugin, bootstrap, and manifest.
      Without --yes: dry-run only — lists what WOULD be removed and why.
      --yes / -y: actually remove owned + content-validated files.
      --force (requires --yes): also remove an unknown/unowned manifest.
      Skills and project-level commands are NEVER auto-deleted; guidance for
      manual cleanup is printed.

  ccl-skills-opencode --help | -h
      Show this help.

Private registry:
  This package does not hard-code a registry URL. Configure your npm registry
  via .npmrc, NPM_CONFIG_REGISTRY, or CI variables before installing.

OpenCode plugin mode (alternative to CLI install):
  Add  "plugin": ["@ccoalm/ccl-skills-opencode"]  to your global or
  project opencode.json, then restart OpenCode. Bun auto-installs npm plugins.`

function main(): void {
  const args = process.argv.slice(2)
  const [cmd, ...rest] = args

  switch (cmd) {
    case undefined:
    case "-h":
    case "--help":
    case "help":
      console.log(HELP)
      process.exit(0)

    case "install": {
      const noAgent = rest.includes("--no-agent") || rest.includes("--no-agent-skills")
      const unknown = rest.filter((a) => a !== "--no-agent" && a !== "--no-agent-skills")
      if (unknown.length > 0) {
        console.error(`Unknown option(s): ${unknown.join(", ")}`)
        console.error('Run "ccl-skills-opencode --help" for usage.')
        process.exit(2)
      }
      runInstall({ noAgent })
      process.exit(0)
    }

    case "install-commands": {
      const positional = rest.filter((a) => !a.startsWith("-"))
      const flags = rest.filter((a) => a.startsWith("-"))
      const force = flags.includes("--force")
      const unknownFlags = flags.filter((a) => a !== "--force")
      if (unknownFlags.length > 0) {
        console.error(`Unknown option(s): ${unknownFlags.join(", ")}`)
        console.error('Run "ccl-skills-opencode --help" for usage.')
        process.exit(2)
      }
      if (positional.length < 1) {
        console.error("Usage: ccl-skills-opencode install-commands <project-dir> [--force]")
        process.exit(2)
      }
      const code = runInstallCommands(positional[0], { force })
      process.exit(code)
    }

    case "doctor": {
      const code = runDoctor()
      process.exit(code)
    }

    case "update": {
      const yes = rest.includes("--yes") || rest.includes("-y")
      const unknown = rest.filter((a) => a !== "--yes" && a !== "-y")
      if (unknown.length > 0) {
        console.error(`Unknown option(s): ${unknown.join(", ")}`)
        console.error('Run "ccl-skills-opencode --help" for usage.')
        process.exit(2)
      }
      const code = runUpdate({ yes })
      process.exit(code)
    }

    case "uninstall": {
      const yes = rest.includes("--yes") || rest.includes("-y")
      const force = rest.includes("--force")
      const unknown = rest.filter((a) => a !== "--yes" && a !== "-y" && a !== "--force")
      if (unknown.length > 0) {
        console.error(`Unknown option(s): ${unknown.join(", ")}`)
        console.error('Run "ccl-skills-opencode --help" for usage.')
        process.exit(2)
      }
      const code = runUninstall({ yes, force })
      process.exit(code)
    }

    default:
      console.error(`Unknown command: ${cmd}`)
      console.error('Run "ccl-skills-opencode --help" for usage.')
      process.exit(1)
  }
}

main()
