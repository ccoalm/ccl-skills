// CCL Skills OpenCode plugin — npm package edition.
//
// Adapted from packages/opencode-plugin/ccl-skills.ts. The only behavioural difference is
// bootstrap/manifest path resolution: this module prefers the bundled copy
// shipped inside the npm package (dist/assets/), then falls back to the global
// install path. The worktree guard logic is identical so file-based and npm
// plugin installs enforce the same discipline.

import { existsSync, lstatSync, readFileSync, realpathSync } from "node:fs"
import { dirname, join, resolve } from "node:path"
import { execFileSync } from "node:child_process"
import {
  BOOTSTRAP_PATHS,
  BOOTSTRAP_DEDUPE_MARKER,
  UPDATE_REMINDER_MARKER,
  WORKTREE_MARKER,
} from "./paths.js"
import { updateReminder } from "./reminder.js"

interface SystemTransformInput {
  // OpenCode passes the current system-prompt state; we only read enough to
  // decide whether bootstrap is already present.
  _?: unknown
}

interface SystemTransformOutput {
  system: string[]
}

interface ToolBeforeInput {
  tool: string
  _?: unknown
}

interface ToolBeforeOutput {
  args: { filePath?: string }
  _?: unknown
}

function readBootstrap(): string {
  for (const path of BOOTSTRAP_PATHS) {
    try {
      if (existsSync(path)) return readFileSync(path, "utf8")
    } catch {
      // Try the next bootstrap source.
    }
  }
  return ""
}

function git(args: string[], cwd: string): string {
  return execFileSync("git", args, {
    cwd,
    encoding: "utf8",
    stdio: ["ignore", "pipe", "ignore"],
  }).trim()
}

function nearestExistingDir(filePath: string): string | null {
  let dir = dirname(filePath)
  while (dir !== "/" && dir !== "." && !existsSync(dir)) dir = dirname(dir)
  return existsSync(dir) ? dir : null
}

function isPrimaryCheckout(repoRoot: string, cwd: string): boolean {
  const gitDir = git(["rev-parse", "--git-dir"], cwd)
  const gitCommonDir = git(["rev-parse", "--git-common-dir"], cwd)
  return resolve(repoRoot, gitDir) === resolve(repoRoot, gitCommonDir)
}

function liveWorktreeCount(cwd: string): number {
  let count = 0
  let inEntry = false
  let prunable = false
  for (const line of git(["worktree", "list", "--porcelain"], cwd).split("\n")) {
    if (line.startsWith("worktree ")) {
      inEntry = true
      prunable = false
    } else if (line.startsWith("prunable")) {
      prunable = true
    } else if (line === "") {
      if (inEntry && !prunable) count++
      inEntry = false
    }
  }
  if (inEntry && !prunable) count++
  return count
}

function blockReason(filePath: string): string | null {
  try {
    let target = resolve(filePath)
    try {
      if (lstatSync(target).isSymbolicLink()) target = realpathSync(target)
    } catch {
      // Target may not exist yet (new file) — judge by its directory below.
    }
    let cwd = nearestExistingDir(target)
    if (!cwd) return null
    cwd = realpathSync(cwd)
    const repoRoot = git(["rev-parse", "--show-toplevel"], cwd)
    if (!repoRoot) return null
    if (!isPrimaryCheckout(repoRoot, cwd)) return null

    if (existsSync(join(repoRoot, WORKTREE_MARKER))) {
      return `[${repoRoot}] is marked as a shared repository (.worktree-only): never edit the primary checkout directly, regardless of branch.`
    }
    const live = liveWorktreeCount(cwd)
    if (live > 1) {
      return `[${repoRoot}] has ${live} live worktrees (parallel work in progress): edit in the matching worktree instead of the primary checkout.`
    }
    return null
  } catch {
    return null
  }
}

/**
 * CCL Skills OpenCode plugin entry point.
 *
 * Loaded by OpenCode when the user declares this package in their `plugin`
 * config array. Returns hooks that inject the routing bootstrap (deduplicated)
 * and guard the primary checkout against direct edits.
 */
export const CclSkills = async () => {
  return {
    "experimental.chat.system.transform": async (
      _input: SystemTransformInput,
      output: SystemTransformOutput,
    ) => {
      const hasBootstrap = output.system.some((entry) => entry.includes(BOOTSTRAP_DEDUPE_MARKER))

      const bootstrap = readBootstrap()
      if (bootstrap && !hasBootstrap) {
        output.system.push(`\n# CCL Skills Bootstrap\n\n${bootstrap}`)
      }

      try {
        const reminder = updateReminder()
        if (reminder && !output.system.some((entry) => entry.includes(UPDATE_REMINDER_MARKER))) {
          output.system.push(reminder.systemPrompt)
        }
      } catch {
        // Reminder failures must never break OpenCode startup.
      }
    },

    "tool.execute.before": async (input: ToolBeforeInput, output: ToolBeforeOutput) => {
      if (input.tool !== "edit" && input.tool !== "write") return

      const filePath = output.args?.filePath
      if (!filePath) return
      const reason = blockReason(filePath)
      if (!reason) return

      throw new Error(
        [
          "ccl-skills worktree guard blocked this edit.",
          `Target file: ${filePath}`,
          reason,
          "Create a feature worktree first (git worktree add -b <branch> <path>), then retry the edit there.",
        ].join("\n"),
      )
    },
  }
}

export default CclSkills
