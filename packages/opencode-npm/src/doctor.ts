// `ccl-skills-opencode doctor` — read-only diagnostic check of the
// OpenCode ccl-skills install state. Never exits non-zero for missing
// components; only for internal errors.

import { existsSync, readdirSync, readFileSync } from "node:fs"
import { execFileSync } from "node:child_process"
import { join } from "node:path"
import {
  AGENT_SKILLS_DIR,
  BOOTSTRAP_DST,
  BUNDLED_BOOTSTRAP,
  MANIFEST_DST,
  OPENCODE_COMMANDS_DIR,
  OPENCODE_PLUGIN_DIR,
  OPENCODE_SKILLS_DIR,
  PLUGIN_DST,
} from "./paths.js"
import { readPackageInfo, isRemoteNewer } from "./pkg.js"
import { ok, info, warn, section } from "./log.js"
import { hasTuiPluginEntry, TUI_PLUGIN_ENTRY } from "./tui-config.js"

function listSkillDirs(dir: string): string[] {
  if (!existsSync(dir)) return []
  try {
    return readdirSync(dir, { withFileTypes: true })
      .filter((e) => e.isDirectory())
      .map((e) => e.name)
  } catch {
    return []
  }
}

function readManifestInstaller(): string | null {
  try {
    if (!existsSync(MANIFEST_DST)) return null
    const m = JSON.parse(readFileSync(MANIFEST_DST, "utf8")) as { installer?: string }
    return m.installer ?? null
  } catch {
    return null
  }
}

/**
 * Best-effort npm registry query for the latest published version.
 * Returns null on any failure (offline, timeout, registry misconfigured,
 * package not found). Never throws — doctor must stay exit 0.
 */
function queryLatestVersion(pkgName: string): string | null {
  try {
    const output = execFileSync("npm", ["view", pkgName, "version", "--json"], {
      encoding: "utf8",
      stdio: ["ignore", "pipe", "ignore"],
      timeout: 10_000,
    }).trim()
    const parsed = JSON.parse(output)
    // npm view --json returns a quoted string for a single version field,
    // e.g.  "0.2.0"  (with JSON double-quotes).
    if (typeof parsed === "string") return parsed
    return null
  } catch {
    return null
  }
}

export function runDoctor(): number {
  section("ccl-skills OpenCode doctor")
  let allGood = true

  // Skills
  const ocSkills = listSkillDirs(OPENCODE_SKILLS_DIR)
  if (ocSkills.length > 0) {
    ok(`OpenCode skills directory (${ocSkills.length} dirs): ${OPENCODE_SKILLS_DIR}`)
  } else {
    warn(`No skills in OpenCode native dir: ${OPENCODE_SKILLS_DIR}`)
    allGood = false
  }

  const agentSkills = listSkillDirs(AGENT_SKILLS_DIR)
  if (agentSkills.length > 0) {
    info(`Agent skills compat dir (${agentSkills.length} dirs): ${AGENT_SKILLS_DIR}`)
  }

  // Plugin (file-based). Missing is NOT a health failure — npm plugin mode
  // users ("plugin": ["@ccoalm/..."]) never have a file-based plugin.
  if (existsSync(PLUGIN_DST)) {
    ok(`File-based plugin present: ${PLUGIN_DST}`)
  } else {
    info("No file-based plugin (npm plugin mode users don't need one).")
    info('  If using file-based mode, run: ccl-skills-opencode install')
  }
  info(`Plugin directory: ${OPENCODE_PLUGIN_DIR}`)

  if (hasTuiPluginEntry()) {
    ok(`TUI startup reminder plugin configured: ${TUI_PLUGIN_ENTRY}`)
  } else {
    info(`No TUI startup reminder plugin entry (${TUI_PLUGIN_ENTRY}).`)
    info("  npm-plugin-only server users are still valid; run `ccl-skills-opencode install` to add TUI toast reminders.")
  }

  // Bootstrap
  if (existsSync(BOOTSTRAP_DST)) {
    ok(`Global bootstrap present: ${BOOTSTRAP_DST}`)
  } else if (existsSync(BUNDLED_BOOTSTRAP)) {
    ok(`Bundled bootstrap available (npm plugin will use it): ${BUNDLED_BOOTSTRAP}`)
  } else {
    warn("No bootstrap found — install it with: ccl-skills-opencode install")
    allGood = false
  }

  // Commands
  let commandCount = 0
  if (existsSync(OPENCODE_COMMANDS_DIR)) {
    commandCount = readdirSync(OPENCODE_COMMANDS_DIR).filter(
      (n) => n.startsWith("ccl-") && n.endsWith(".md"),
    ).length
  }
  if (commandCount > 0) {
    ok(`Global commands present (${commandCount}): ${OPENCODE_COMMANDS_DIR}/ccl-*.md`)
  } else {
    info(`No global CCL commands in ${OPENCODE_COMMANDS_DIR}`)
    info("  Install with: ccl-skills-opencode install")
  }

  // Manifest
  const installer = readManifestInstaller()
  if (installer) {
    ok(`Install manifest present (installer: ${installer}): ${MANIFEST_DST}`)
  } else {
    info("No install manifest — install with: ccl-skills-opencode install")
  }

  // Version check (network call, best-effort — never fails doctor).
  section("Version check")
  const pkgInfo = readPackageInfo()
  if (!pkgInfo) {
    info("Could not read local package version.")
  } else {
    ok(`Local version: ${pkgInfo.version} (${pkgInfo.name})`)
    const latest = queryLatestVersion(pkgInfo.name)
    if (latest === null) {
      info("Could not query npm registry for latest version (offline or registry not configured).")
    } else if (isRemoteNewer(latest, pkgInfo.version)) {
      warn(`Update available: ${latest} (you have ${pkgInfo.version})`)
      info("  Run: ccl-skills-opencode update --yes")
      info("  Then restart OpenCode.")
    } else {
      ok(`Up to date (latest on registry: ${latest})`)
    }
  }

  // Summary
  section("Summary")
  if (allGood) {
    ok("Core components (skills, plugin/bootstrap, commands) all detected.")
  } else {
    warn("Some components are missing — see notes above. Run `ccl-skills-opencode install`.")
  }
  info("Note: project-level opencode.json commands are not checked here; inspect per-project.")

  return 0
}
