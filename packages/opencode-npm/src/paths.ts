import { dirname, join } from "node:path"
import { fileURLToPath } from "node:url"

// dist/ is the directory that contains this compiled module (src/ → dist/).
// All modules in the flat layout live directly in dist/, so DIST_ROOT == HERE.
const HERE = dirname(fileURLToPath(import.meta.url))
export const DIST_ROOT = HERE

// Package root (parent of dist/) — where package.json lives.
export const PKG_ROOT = dirname(DIST_ROOT)

// Bundled assets copied at build time from the source repo.
export const ASSETS_ROOT = join(DIST_ROOT, "assets")
export const BUNDLED_BOOTSTRAP = join(ASSETS_ROOT, "bootstrap.md")
export const BUNDLED_PLUGIN_SRC = join(ASSETS_ROOT, "ccl-skills.ts")
export const BUNDLED_OPENCODE_JSON = join(ASSETS_ROOT, "opencode.json")
export const BUNDLED_COMMANDS_DIR = join(ASSETS_ROOT, "commands")

// User-level OpenCode paths.
export const HOME = process.env.HOME ?? ""
export const OPENCODE_CONFIG_ROOT = join(HOME, ".config", "opencode")
export const OPENCODE_PLUGIN_DIR = join(OPENCODE_CONFIG_ROOT, "plugins")
export const OPENCODE_DATA_DIR = join(OPENCODE_CONFIG_ROOT, "ccl-skills")
export const OPENCODE_SKILLS_DIR = join(OPENCODE_CONFIG_ROOT, "skills")
export const OPENCODE_COMMANDS_DIR = join(OPENCODE_CONFIG_ROOT, "commands")
export const AGENT_SKILLS_DIR = join(HOME, ".agents", "skills")

export const PLUGIN_DST = join(OPENCODE_PLUGIN_DIR, "ccl-skills.ts")
export const BOOTSTRAP_DST = join(OPENCODE_DATA_DIR, "bootstrap.md")
export const MANIFEST_DST = join(OPENCODE_DATA_DIR, "install-manifest.json")

// Bootstrap search order for the npm plugin runtime.
// 1. Bundled copy shipped inside this package (always available).
// 2. Global install copy (written by CLI install / install-opencode.sh).
export const BOOTSTRAP_PATHS = [BUNDLED_BOOTSTRAP, BOOTSTRAP_DST]

export const MANIFEST_PATHS = [MANIFEST_DST]

export const WORKTREE_MARKER = ".worktree-only"
export const BOOTSTRAP_DEDUPE_MARKER = "ccl-skills-routing"
export const UPDATE_REMINDER_MARKER = "CCL Skills Update Reminder"
