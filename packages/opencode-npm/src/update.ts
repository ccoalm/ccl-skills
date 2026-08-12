// `ccl-skills-opencode update [--yes]` — upgrades the globally installed
// npm package to latest, then refreshes plugin/bootstrap/commands/manifest.
//
// Default = preview/dry-run: prints what would happen, executes nothing,
// does NOT touch the network or global npm state.
// --yes = actually runs `npm install -g <pkg>@latest` (using the user's own
// npm config for registry/auth — nothing is hard-coded), then spawns the
// freshly installed CLI to refresh all OpenCode assets.

import { spawnSync } from "node:child_process"
import { readPackageInfo } from "./pkg.js"
import { ok, info, warn, fail, section } from "./log.js"

export interface UpdateOptions {
  yes?: boolean
}

export function runUpdate(options: UpdateOptions = {}): number {
  const yes = options.yes ?? false

  const pkgInfo = readPackageInfo()
  if (!pkgInfo) {
    fail("Could not read package.json — cannot determine package name or version.")
    return 1
  }

  if (!yes) {
    section("Update preview (dry-run — pass --yes to execute)")
    info(`Package:  ${pkgInfo.name}`)
    info(`Current:  ${pkgInfo.version}`)
    info("")
    info("Would execute:")
    info(`  1. npm install -g ${pkgInfo.name}@latest`)
    info("     (uses your npm config: .npmrc / NPM_CONFIG_REGISTRY / CI variables)")
    info("  2. Refresh plugin, bootstrap, commands, and manifest (install logic)")
    info("  3. Restart OpenCode (or open a new session) to load updated assets")
    info("")
    info("This dry-run does NOT modify anything.")
    info("Re-run with --yes to perform the update.")
    return 0
  }

  // --- Execute ---
  section("Updating ccl-skills-opencode")
  info(`Package:  ${pkgInfo.name}`)
  info(`Current:  ${pkgInfo.version}`)
  info(`Running:  npm install -g ${pkgInfo.name}@latest`)

  // Use spawnSync with inherited stdio so the user sees npm's own progress
  // and error output. We do NOT pass credentials on the command line — npm
  // reads registry/auth from .npmrc or env variables.
  const result = spawnSync("npm", ["install", "-g", `${pkgInfo.name}@latest`], {
    stdio: "inherit",
    env: { ...process.env },
  })

  if (result.error) {
    fail(`Failed to spawn npm: ${result.error.message}`)
    fail("Is npm installed and on your PATH?")
    return 1
  }

  if (result.status !== 0) {
    fail(`npm install exited with code ${result.status}. The global package was NOT updated.`)
    info("")
    info("Common causes:")
    info("  - Registry unreachable — check .npmrc / NPM_CONFIG_REGISTRY / NPM_INSTALL_REGISTRY")
    info("  - Authentication required — configure .npmrc with your registry credentials")
    info("  - Permission denied — you may need sudo or a Node version manager")
    info("  - Network timeout or proxy issue")
    info("")
    info("Do NOT pass credentials as command-line arguments. Use .npmrc or env variables.")
    return 1
  }

  ok("npm package updated to latest.")

  // The currently running process still holds the old code in memory. Spawn
  // the CLI from PATH so any future install/manifest migrations are handled by
  // the freshly-installed package, not this old process.
  info("")
  info("Refreshing OpenCode assets (plugin, bootstrap, commands, manifest)...")
  const install = spawnSync("ccl-skills-opencode", ["install"], {
    stdio: "inherit",
    env: { ...process.env },
  })

  if (install.error) {
    fail(`Failed to spawn ccl-skills-opencode install: ${install.error.message}`)
    fail("Is the global npm bin directory on your PATH?")
    return 1
  }

  if (install.status !== 0) {
    fail(`ccl-skills-opencode install exited with code ${install.status}.`)
    warn("The package was updated, but OpenCode assets may not have been refreshed.")
    return 1
  }

  section("Update complete")
  warn("Restart OpenCode (or open a new session) to load the updated plugin, commands, and skills.")

  return 0
}
