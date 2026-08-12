// Shared package-info reader and semver comparison.
// Used by update.ts (needs package name for npm install) and doctor.ts
// (compares local vs latest version).

import { existsSync, readFileSync } from "node:fs"
import { join } from "node:path"
import { PKG_ROOT } from "./paths.js"

export interface PackageInfo {
  name: string
  version: string
}

export function readPackageInfo(): PackageInfo | null {
  try {
    const pjsonPath = join(PKG_ROOT, "package.json")
    if (!existsSync(pjsonPath)) return null
    const pkg = JSON.parse(readFileSync(pjsonPath, "utf8")) as Record<string, unknown>
    if (typeof pkg.name !== "string" || typeof pkg.version !== "string") return null
    return { name: pkg.name, version: pkg.version }
  } catch {
    return null
  }
}

/**
 * Parse the numeric core of a semver string (ignores prerelease/build tags).
 * Returns [major, minor, patch] or null if unparseable.
 */
function parseSemverCore(v: string): [number, number, number] | null {
  const m = v.match(/^(\d+)\.(\d+)\.(\d+)/)
  if (!m) return null
  return [Number(m[1]), Number(m[2]), Number(m[3])]
}

/**
 * Returns true if `remote` is strictly newer than `local` by numeric
 * major.minor.patch comparison. Prerelease tags are ignored (conservative:
 * a prerelease remote is not flagged as "newer" unless the numeric core is
 * higher). Returns false if either version is unparseable.
 */
export function isRemoteNewer(remote: string, local: string): boolean {
  const r = parseSemverCore(remote)
  const l = parseSemverCore(local)
  if (!r || !l) return false
  if (r[0] !== l[0]) return r[0] > l[0]
  if (r[1] !== l[1]) return r[1] > l[1]
  return r[2] > l[2]
}
