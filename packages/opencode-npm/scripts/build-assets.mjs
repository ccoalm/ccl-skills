// Build step: copy repo-level assets into dist/assets/ so the npm package
// ships bootstrap.md, the standalone plugin .ts, command templates, and the
// source opencode.json (used by install-commands).
//
// Runs after tsc. In a published package dist/assets/ is the only source for
// these files — the repo root is not available to consumers.

import { copyFileSync, cpSync, existsSync, mkdirSync, readdirSync } from "node:fs"
import { dirname, join, resolve } from "node:path"
import { fileURLToPath } from "node:url"

const here = dirname(fileURLToPath(import.meta.url))
const pkgRoot = resolve(here, "..")
const repoRoot = resolve(pkgRoot, "..", "..")
const distAssets = join(pkgRoot, "dist", "assets")

function die(msg) {
  console.error(`[build-assets] ERROR: ${msg}`)
  process.exit(1)
}

function ensureDir(dir) {
  mkdirSync(dir, { recursive: true })
}

function copyFile(src, dst, label) {
  if (!existsSync(src)) die(`${label} not found: ${src}`)
  ensureDir(dirname(dst))
  copyFileSync(src, dst)
  console.log(`  [build-assets] copied ${label} -> ${dst.slice(pkgRoot.length + 1)}`)
}

function copyDir(src, dst, label, filter) {
  if (!existsSync(src)) die(`${label} not found: ${src}`)
  ensureDir(dst)
  let count = 0
  for (const name of readdirSync(src)) {
    if (filter && !filter(name)) continue
    copyFileSync(join(src, name), join(dst, name))
    count++
  }
  console.log(`  [build-assets] copied ${count} file(s) ${label} -> ${dst.slice(pkgRoot.length + 1)}/`)
}

console.log("[build-assets] copying source-repo assets into dist/assets/")

ensureDir(distAssets)

// Routing hard discipline — injected by the plugin. Source lives at
// agent-context/session-start.md; the shipped asset name stays bootstrap.md
// because it is the installed artifact name (~/.config/opencode/ccl-skills/),
// not a repo path.
copyFile(
  join(repoRoot, "agent-context", "session-start.md"),
  join(distAssets, "bootstrap.md"),
  "bootstrap.md",
)

// Standalone plugin .ts for CLI file-based install mode (copies to
// ~/.config/opencode/plugins/ccl-skills.ts). The global-install path
// resolution in this file already handles ~/.config/opencode/ccl-skills/.
copyFile(
  join(repoRoot, "packages", "opencode-plugin", "ccl-skills.ts"),
  join(distAssets, "ccl-skills.ts"),
  "standalone plugin (packages/opencode-plugin/ccl-skills.ts)",
)

// opencode.json — source of the `command` field for install-commands.
copyFile(
  join(repoRoot, "opencode.json"),
  join(distAssets, "opencode.json"),
  "opencode.json",
)

// Command templates.
copyDir(
  join(repoRoot, "packages", "opencode-plugin", "commands"),
  join(distAssets, "commands"),
  "command templates",
  (name) => name.startsWith("ccl-") && name.endsWith(".md"),
)

console.log("[build-assets] done.")
