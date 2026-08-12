// `ccl-skills-opencode uninstall` — safely removes the global
// plugin/bootstrap/manifest that this CLI (or install-opencode.sh) installed.
//
// Safety model (Blocker 1):
//   - Default = dry-run: lists what WOULD be removed and why, deletes nothing.
//   - --yes / -y = actually remove owned + content-validated files.
//   --force (requires --yes) also removes an unknown/unowned manifest.
//   - Plugin/bootstrap are only removed when:
//       (a) the manifest installer is owned (OWNED_INSTALLERS), AND
//       (b) the file content contains ccl-skills markers.
//     A missing manifest or unowned installer → refuse, print manual guidance.
//   - Skills and project-level commands are NEVER auto-deleted.

import { existsSync, readFileSync, rmSync } from "node:fs"
import {
  BOOTSTRAP_DST,
  BOOTSTRAP_DEDUPE_MARKER,
  MANIFEST_DST,
  OPENCODE_COMMANDS_DIR,
  PLUGIN_DST,
} from "./paths.js"
import { isOwnedInstaller, readManifest } from "./manifest.js"
import { ok, info, warn, section } from "./log.js"
import { findTuiPluginEntryPath, removeTuiPluginEntry, TUI_JSON, TUI_JSONC } from "./tui-config.js"

export interface UninstallOptions {
  yes?: boolean
  force?: boolean
}

// Distinctive substrings in the standalone plugin file
// (packages/opencode-plugin/ccl-skills.ts).
// If none are present, the file is NOT our plugin and we refuse to delete it.
const PLUGIN_MARKERS = ["CclSkills", "blockReason", "worktree guard"]

function fileContainsAny(path: string, markers: string[]): boolean {
  try {
    const content = readFileSync(path, "utf8")
    return markers.some((m) => content.includes(m))
  } catch {
    return false
  }
}

type Action = "remove" | "dryrun" | "refuse" | "absent"

interface FilePlan {
  path: string
  label: string
  action: Action
  reason: string
}

function planPlugin(owned: boolean, yes: boolean): FilePlan {
  if (!existsSync(PLUGIN_DST)) return { path: PLUGIN_DST, label: "plugin", action: "absent", reason: "not found" }
  if (!fileContainsAny(PLUGIN_DST, PLUGIN_MARKERS)) {
    return { path: PLUGIN_DST, label: "plugin", action: "refuse", reason: "content markers not found — not our plugin" }
  }
  if (!owned) {
    return { path: PLUGIN_DST, label: "plugin", action: "refuse", reason: "manifest installer not owned" }
  }
  if (!yes) {
    return { path: PLUGIN_DST, label: "plugin", action: "dryrun", reason: "owned + content validated" }
  }
  return { path: PLUGIN_DST, label: "plugin", action: "remove", reason: "owned + content validated" }
}

function planBootstrap(owned: boolean, yes: boolean): FilePlan {
  if (!existsSync(BOOTSTRAP_DST)) return { path: BOOTSTRAP_DST, label: "bootstrap", action: "absent", reason: "not found" }
  if (!fileContainsAny(BOOTSTRAP_DST, [BOOTSTRAP_DEDUPE_MARKER])) {
    return { path: BOOTSTRAP_DST, label: "bootstrap", action: "refuse", reason: "ccl-skills-routing marker not found" }
  }
  if (!owned) {
    return { path: BOOTSTRAP_DST, label: "bootstrap", action: "refuse", reason: "manifest installer not owned" }
  }
  if (!yes) {
    return { path: BOOTSTRAP_DST, label: "bootstrap", action: "dryrun", reason: "owned + content validated" }
  }
  return { path: BOOTSTRAP_DST, label: "bootstrap", action: "remove", reason: "owned + content validated" }
}

function planManifest(owned: boolean, yes: boolean, force: boolean): FilePlan {
  if (!existsSync(MANIFEST_DST)) return { path: MANIFEST_DST, label: "manifest", action: "absent", reason: "not found" }
  if (owned) {
    if (!yes) return { path: MANIFEST_DST, label: "manifest", action: "dryrun", reason: "owned installer" }
    return { path: MANIFEST_DST, label: "manifest", action: "remove", reason: "owned installer" }
  }
  // Unowned / unknown manifest.
  if (yes && force) {
    return { path: MANIFEST_DST, label: "manifest", action: "remove", reason: "unknown installer — --yes --force" }
  }
  return { path: MANIFEST_DST, label: "manifest", action: "refuse", reason: "unknown/missing installer — use --yes --force" }
}

function planTuiConfig(owned: boolean, yes: boolean): FilePlan {
  const entryPath = findTuiPluginEntryPath()
  const path = entryPath ?? (existsSync(TUI_JSONC) ? TUI_JSONC : TUI_JSON)
  if (!entryPath) return { path, label: "TUI plugin entry", action: "absent", reason: "TUI plugin entry not present" }
  if (!owned) {
    return { path, label: "TUI plugin entry", action: "refuse", reason: "manifest installer not owned" }
  }
  if (!yes) {
    return { path, label: "TUI plugin entry", action: "dryrun", reason: "owned config entry" }
  }
  return { path, label: "TUI plugin entry", action: "remove", reason: "owned config entry" }
}

export function runUninstall(options: UninstallOptions = {}): number {
  const yes = options.yes ?? false
  const force = options.force ?? false

  section(yes ? "Uninstalling ccl-skills OpenCode assets" : "Uninstall preview (dry-run — pass --yes to remove)")

  const manifest = readManifest()
  const owned = isOwnedInstaller(manifest?.installer)

  if (!owned) {
    if (manifest) {
      warn(`Install manifest installer "${manifest.installer}" is not recognized as owned by this CLI.`)
    } else {
      info("No install manifest found — cannot verify ownership.")
    }
    info("Plugin/bootstrap will be refused. Manual cleanup guidance is printed below.")
  }

  const plans: FilePlan[] = [
    planPlugin(owned, yes),
    planBootstrap(owned, yes),
    planTuiConfig(owned, yes),
    planManifest(owned, yes, force),
  ]

  let removed = 0
  for (const p of plans) {
    switch (p.action) {
      case "absent":
        info(`${p.label}: not found (already removed or never installed)`)
        break
      case "dryrun":
        info(`[dry-run] Would remove ${p.label}: ${p.path} (${p.reason})`)
        break
      case "refuse":
        warn(`Refusing to remove ${p.label}: ${p.reason}`)
        info(`  File: ${p.path}`)
        break
      case "remove":
        if (p.label === "TUI plugin entry") {
          removeTuiPluginEntry()
        } else {
          rmSync(p.path, { force: true })
        }
        ok(`Removed ${p.label}: ${p.path} (${p.reason})`)
        removed++
        break
    }
  }

  // Manual cleanup guidance (always shown).
  section("Manual cleanup (not done automatically)")
  info("Skills are NOT removed — they may be shared across tools. To clean manually:")
  info("  rm -rf ~/.config/opencode/skills/<skill-name>   # per skill")
  info("  rm -rf ~/.agents/skills/<skill-name>            # per skill (compat dir)")
  info("Global commands are NOT removed — to clean manually:")
  info(`  rm -f ${OPENCODE_COMMANDS_DIR}/ccl-*.md`)
  info('If using server-only npm plugin mode, remove from your opencode.json plugin array:')
  info('  "@ccoalm/ccl-skills-opencode"')
  info('TUI config files are preserved; only this package TUI plugin entry is removed when owned.')

  section("Result")
  if (yes) {
    ok(`Removed ${removed} file(s).`)
    if (removed > 0) warn("Restart OpenCode for changes to take effect.")
  } else {
    info("This was a dry-run. Re-run with --yes to perform the removal.")
  }

  return 0
}
