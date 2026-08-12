// Shared install-manifest read/write and ownership logic.
// Used by both install.ts (writes manifest) and uninstall.ts (checks ownership).

import { existsSync, mkdirSync, readFileSync, writeFileSync } from "node:fs"
import { MANIFEST_DST, OPENCODE_DATA_DIR } from "./paths.js"

export interface InstallManifest {
  installed_at: string
  source_commit: string
  source_repo?: string
  install_mode: string
  installer: string
  synced_skills?: string[]
  target_dirs?: string[]
  owned_files?: string[]
  modified_files?: string[]
}

// Installers whose plugin/bootstrap/commands files this CLI is willing to
// remove. Both the npm CLI and the legacy source-repo installer write the
// same file-based plugin and bootstrap to the same paths, so both are
// considered "owned" — removing their files is safe (with content validation).
export const OWNED_INSTALLERS = [
  "ccl-skills-opencode-cli",
  "scripts/install-opencode.sh",
] as const

export function isOwnedInstaller(installer: string | undefined | null): boolean {
  if (!installer) return false
  return (OWNED_INSTALLERS as readonly string[]).includes(installer)
}

export function readManifest(): InstallManifest | null {
  try {
    if (!existsSync(MANIFEST_DST)) return null
    return JSON.parse(readFileSync(MANIFEST_DST, "utf8")) as InstallManifest
  } catch {
    return null
  }
}

export function writeManifest(manifest: InstallManifest): void {
  mkdirSync(OPENCODE_DATA_DIR, { recursive: true })
  writeFileSync(MANIFEST_DST, JSON.stringify(manifest, null, 2) + "\n", "utf8")
}
