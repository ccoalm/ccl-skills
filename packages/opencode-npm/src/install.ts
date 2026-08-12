// `ccl-skills-opencode install` — copies bundled plugin, bootstrap,
// commands, and manifest to the user's global OpenCode config. Skills are
// synced from the source repo when CCL_SKILLS_REPO points to a valid
// ccl-skills checkout; otherwise actionable guidance is printed.
//
// Safety model (Blocker 2):
//   - CCL_SKILLS_REPO must pass structural validation (skills/,
//     agent-context/session-start.md, AGENTS.md, .worktree-only, and at least
//     one skills/*/SKILL.md) before
//     any skill is synced. An invalid repo is refused — no half-sync.
//   - Each skill is copied atomically: cp to a temp dir in the same parent,
//     then rm old + rename. A cross-device rename falls back to cp + rm.
//     No half-written skill directories are left behind on failure.

import {
  copyFileSync,
  cpSync,
  existsSync,
  mkdirSync,
  readdirSync,
  renameSync,
  rmSync,
  writeFileSync,
} from "node:fs"
import { basename, dirname, join } from "node:path"
import { execFileSync } from "node:child_process"
import {
  AGENT_SKILLS_DIR,
  BOOTSTRAP_DST,
  BUNDLED_BOOTSTRAP,
  BUNDLED_COMMANDS_DIR,
  BUNDLED_PLUGIN_SRC,
  OPENCODE_COMMANDS_DIR,
  OPENCODE_DATA_DIR,
  OPENCODE_PLUGIN_DIR,
  OPENCODE_SKILLS_DIR,
  PLUGIN_DST,
} from "./paths.js"
import type { InstallManifest } from "./manifest.js"
import { writeManifest } from "./manifest.js"
import { ok, info, warn, fail, section } from "./log.js"
import { ensureTuiPluginEntry, TUI_PLUGIN_ENTRY } from "./tui-config.js"

export interface InstallOptions {
  noAgent?: boolean
}

function copyBundledCommands(): string[] {
  mkdirSync(OPENCODE_COMMANDS_DIR, { recursive: true })
  const copied: string[] = []
  if (!existsSync(BUNDLED_COMMANDS_DIR)) return copied

  for (const name of readdirSync(BUNDLED_COMMANDS_DIR)) {
    if (!name.startsWith("ccl-") || !name.endsWith(".md")) continue
    copyFileSync(join(BUNDLED_COMMANDS_DIR, name), join(OPENCODE_COMMANDS_DIR, name))
    copied.push(name)
  }
  return copied
}

const REQUIRED_REPO_FILES = ["agent-context/session-start.md", "AGENTS.md", ".worktree-only"]

interface RepoValidation {
  valid: boolean
  repoRoot: string
  skillNames: string[]
  errors: string[]
}

function validateSourceRepo(repoRoot: string): RepoValidation {
  const errors: string[] = []

  for (const f of REQUIRED_REPO_FILES) {
    if (!existsSync(join(repoRoot, f))) {
      errors.push(`missing required file: ${f}`)
    }
  }

  const skillsDir = join(repoRoot, "skills")
  if (!existsSync(skillsDir) || !readdirSync(skillsDir, { withFileTypes: true }).some((e) => e.isDirectory())) {
    errors.push("missing skills/ directory or no skill subdirectories")
    return { valid: false, repoRoot, skillNames: [], errors }
  }

  // Collect skill names that have a SKILL.md.
  const skillNames: string[] = []
  for (const entry of readdirSync(skillsDir, { withFileTypes: true })) {
    if (!entry.isDirectory()) continue
    if (existsSync(join(skillsDir, entry.name, "SKILL.md"))) {
      skillNames.push(entry.name)
    }
  }
  if (skillNames.length === 0) {
    errors.push("no skills/*/SKILL.md found — not a valid ccl-skills repo")
  }

  return { valid: errors.length === 0, repoRoot, skillNames, errors }
}

/**
 * Atomically sync a single skill directory.
 *
 * Copies the source into a temp directory, moves any old target to a backup,
 * then renames the temp into place. On failure, a moved backup is restored;
 * on cross-device rename failure (EXDEV), falls back to cp + rm.
 */
function atomicSyncSkill(srcDir: string, dstDir: string): void {
  const parent = dirname(dstDir)
  mkdirSync(parent, { recursive: true })

  // Create a temp dir in the same parent so rename stays on the same filesystem.
  let tempDir: string | null = null
  let backupDir: string | null = null
  let targetMovedToBackup = false
  try {
    tempDir = join(parent, `.cs-skill-tmp-${basename(dstDir)}-${Date.now()}`)
    backupDir = join(parent, `.cs-skill-bak-${basename(dstDir)}-${Date.now()}`)
    mkdirSync(tempDir, { recursive: true })
    const tempSkill = join(tempDir, basename(dstDir))

    cpSync(srcDir, tempSkill, { recursive: true })

    if (existsSync(dstDir)) {
      renameSync(dstDir, backupDir)
      targetMovedToBackup = true
    }

    try {
      renameSync(tempSkill, dstDir)
    } catch (err: unknown) {
      if (err instanceof Error && (err as NodeJS.ErrnoException).code === "EXDEV") {
        // Cross-device: fall back to copy + remove.
        cpSync(tempSkill, dstDir, { recursive: true })
      } else {
        throw err
      }
    }

    if (backupDir && existsSync(backupDir)) {
      rmSync(backupDir, { recursive: true, force: true })
      targetMovedToBackup = false
    }
  } catch (err) {
    if (targetMovedToBackup && backupDir && existsSync(backupDir)) {
      if (existsSync(dstDir)) {
        rmSync(dstDir, { recursive: true, force: true })
      }
      renameSync(backupDir, dstDir)
      targetMovedToBackup = false
    }
    throw err
  } finally {
    if (tempDir && existsSync(tempDir)) {
      rmSync(tempDir, { recursive: true, force: true })
    }
    if (backupDir && existsSync(backupDir)) {
      rmSync(backupDir, { recursive: true, force: true })
    }
  }
}

interface SyncResult {
  synced: string[]
  overwritten: string[]
  failed: string[]
}

function syncSkillsFromRepo(repoRoot: string, dst: string): SyncResult {
  const srcSkills = join(repoRoot, "skills")
  const result: SyncResult = { synced: [], overwritten: [], failed: [] }

  mkdirSync(dst, { recursive: true })

  for (const entry of readdirSync(srcSkills, { withFileTypes: true })) {
    if (!entry.isDirectory()) continue
    if (!existsSync(join(srcSkills, entry.name, "SKILL.md"))) continue

    const src = join(srcSkills, entry.name)
    const target = join(dst, entry.name)

    const existed = existsSync(target)
    try {
      atomicSyncSkill(src, target)
      result.synced.push(entry.name)
      if (existed) result.overwritten.push(entry.name)
    } catch (err) {
      result.failed.push(entry.name)
      warn(`Failed to sync skill "${entry.name}": ${err instanceof Error ? err.message : String(err)}`)
    }
  }

  return result
}

function gitHeadCommit(repoRoot: string): string {
  try {
    return execFileSync("git", ["rev-parse", "HEAD"], { cwd: repoRoot, encoding: "utf8" }).trim()
  } catch {
    return "unknown"
  }
}

export function runInstall(options: InstallOptions = {}): void {
  section("Installing ccl-skills OpenCode assets")

  // --- Plugin + bootstrap + commands (from bundled package assets) ---
  mkdirSync(OPENCODE_PLUGIN_DIR, { recursive: true })
  mkdirSync(OPENCODE_DATA_DIR, { recursive: true })

  const ownedFiles: string[] = []
  const modifiedFiles: string[] = []

  if (existsSync(BUNDLED_PLUGIN_SRC)) {
    copyFileSync(BUNDLED_PLUGIN_SRC, PLUGIN_DST)
    ownedFiles.push(PLUGIN_DST)
    ok(`OpenCode plugin installed: ${PLUGIN_DST}`)
  } else {
    warn(`Bundled plugin source not found: ${BUNDLED_PLUGIN_SRC}`)
  }

  if (existsSync(BUNDLED_BOOTSTRAP)) {
    copyFileSync(BUNDLED_BOOTSTRAP, BOOTSTRAP_DST)
    ownedFiles.push(BOOTSTRAP_DST)
    ok(`Bootstrap installed: ${BOOTSTRAP_DST}`)
  } else {
    warn(`Bundled bootstrap not found: ${BUNDLED_BOOTSTRAP}`)
  }

  const commands = copyBundledCommands()
  if (commands.length > 0) {
    ok(`Commands installed (${commands.length}): ${OPENCODE_COMMANDS_DIR}/ccl-*.md`)
  } else {
    warn(`No bundled commands found in ${BUNDLED_COMMANDS_DIR}`)
  }

  try {
    const tui = ensureTuiPluginEntry()
    if (tui.changed) modifiedFiles.push(tui.path)
    if (tui.changed) {
      ok(`${tui.message}: ${tui.path}`)
    } else {
      ok(`${tui.message}: ${tui.path}`)
    }
  } catch (err) {
    warn(`Could not update OpenCode TUI config for startup reminder: ${err instanceof Error ? err.message : String(err)}`)
    warn(`Add ${JSON.stringify(TUI_PLUGIN_ENTRY)} to ~/.config/opencode/tui.jsonc plugin array manually if you want TUI toast reminders.`)
  }

  // --- Skills (from validated source repo) ---
  const repoEnv = process.env.CCL_SKILLS_REPO
  const targetDirs: string[] = []
  let syncedSkills: string[] = []
  let commit = "unknown"
  let repoRoot: string | undefined

  if (repoEnv) {
    const validation = validateSourceRepo(repoEnv)
    if (!validation.valid) {
      fail(`CCL_SKILLS_REPO validation failed: ${repoEnv}`)
      for (const e of validation.errors) info(`  ${e}`)
      info("Skills were NOT synced. Fix the repo path or unset CCL_SKILLS_REPO to skip.")
    } else {
      repoRoot = validation.repoRoot
      commit = gitHeadCommit(repoRoot)
      syncedSkills = validation.skillNames.slice().sort()

      const r1 = syncSkillsFromRepo(repoRoot, OPENCODE_SKILLS_DIR)
      targetDirs.push(OPENCODE_SKILLS_DIR)
      ok(`OpenCode native skills synced (${r1.synced.length}): ${OPENCODE_SKILLS_DIR}`)
      if (r1.overwritten.length > 0) {
        warn(`Overwrote existing skills: ${r1.overwritten.join(", ")}`)
      }
      if (r1.failed.length > 0) {
        warn(`Failed to sync: ${r1.failed.join(", ")}`)
      }

      if (!options.noAgent) {
        const r2 = syncSkillsFromRepo(repoRoot, AGENT_SKILLS_DIR)
        targetDirs.push(AGENT_SKILLS_DIR)
        ok(`Agent skills compat synced (${r2.synced.length}): ${AGENT_SKILLS_DIR}`)
        if (r2.failed.length > 0) {
          warn(`Failed to sync (compat): ${r2.failed.join(", ")}`)
        }
      } else {
        info("--no-agent: skipped ~/.agents/skills compat sync")
      }
    }
  } else {
    info("Skills not bundled in this npm package. To sync skills:")
    info("  1. Set CCL_SKILLS_REPO=/path/to/ccl-skills and re-run install, or")
    info("  2. From the source repo run: bash scripts/install-opencode.sh")
  }

  // --- Manifest ---
  const manifest: InstallManifest = {
    installed_at: new Date().toISOString().replace(/\.\d{3}Z$/, "Z"),
    source_commit: commit,
    source_repo: repoRoot,
    install_mode: "global",
    installer: "ccl-skills-opencode-cli",
    synced_skills: syncedSkills,
    target_dirs: targetDirs,
    owned_files: [...ownedFiles, join(OPENCODE_DATA_DIR, "install-manifest.json")],
    modified_files: modifiedFiles,
  }
  writeManifest(manifest)
  ok(`Install manifest written: ${OPENCODE_DATA_DIR}/install-manifest.json`)

  info("Restart OpenCode (or open a new session) for changes and TUI reminders to take effect.")
}
