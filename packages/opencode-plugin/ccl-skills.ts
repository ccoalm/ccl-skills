import { existsSync, lstatSync, readFileSync, realpathSync } from "node:fs"
import { dirname, join, resolve } from "node:path"
import { fileURLToPath } from "node:url"
import { execFileSync } from "node:child_process"

const PLUGIN_DIR = dirname(fileURLToPath(import.meta.url))
const LOCAL_REPO_ROOT = resolve(PLUGIN_DIR, "..")
const BOOTSTRAP_PATHS = [
  join(LOCAL_REPO_ROOT, "bootstrap.md"),
  join(LOCAL_REPO_ROOT, "ccl-skills", "bootstrap.md"),
  join(process.env.HOME ?? "", ".config", "opencode", "ccl-skills", "bootstrap.md"),
]
const MANIFEST_PATHS = [
	join(process.env.HOME ?? "", ".config", "opencode", "ccl-skills-npm", "install-manifest.json"),
  join(LOCAL_REPO_ROOT, ".opencode", "ccl-skills", "install-manifest.json"),
  join(LOCAL_REPO_ROOT, "ccl-skills", "install-manifest.json"),
  join(process.env.HOME ?? "", ".config", "opencode", "ccl-skills", "install-manifest.json"),
]
const WORKTREE_MARKER = ".worktree-only"
const UPDATE_REMINDER_DAYS = Number(process.env.CCL_SKILLS_UPDATE_REMINDER_DAYS ?? "7")
// Distinctive substring of bootstrap.md; when the system prompt already carries
// it (e.g. the source repo's opencode.json instructions), skip the second copy.
const BOOTSTRAP_DEDUPE_MARKER = "ccl-skills-routing"
const UPDATE_REMINDER_MARKER = "CCL Skills Update Reminder"

function readBootstrap() {
  for (const path of BOOTSTRAP_PATHS) {
    try {
      if (existsSync(path)) return readFileSync(path, "utf8")
    } catch {
      // Try the next bootstrap source.
    }
  }

  return ""
}

function readManifest() {
  for (const path of MANIFEST_PATHS) {
    try {
      if (!existsSync(path)) continue
      return JSON.parse(readFileSync(path, "utf8")) as {
		installedAt?: string
		sourceCommit?: string
		sourceKind?: string
		npmPackage?: string
        installed_at?: string
        source_commit?: string
        install_mode?: string
        installer?: string
      }
    } catch {
      // Ignore malformed or unreadable manifests; the plugin must not break startup.
    }
  }

  return null
}

function updateReminder() {
  if (!Number.isFinite(UPDATE_REMINDER_DAYS) || UPDATE_REMINDER_DAYS <= 0) return ""

  const manifest = readManifest()
  const installedAtValue = manifest?.installedAt ?? manifest?.installed_at
  if (typeof installedAtValue !== "string") return ""

  const installedAt = Date.parse(installedAtValue)
  if (!Number.isFinite(installedAt)) return ""

  const ageDays = Math.floor((Date.now() - installedAt) / 86_400_000)
  if (ageDays < UPDATE_REMINDER_DAYS) return ""

  const sourceCommit = manifest.sourceCommit ?? manifest.source_commit
  const commit = typeof sourceCommit === "string" ? ` commit ${sourceCommit.slice(0, 12)}` : ""
  const modeValue = manifest.sourceKind ?? manifest.install_mode
  const mode = typeof modeValue === "string" ? ` (${modeValue})` : ""
  const isNpmInstall = manifest.npmPackage === "@ccoalm/ccl-skills" || manifest.installer === "ccl-skills-opencode-cli"
  const updateInstruction = isNpmInstall
    ? "Installed via the npm package. Ask before changing global npm state: run `ccl-skills update` to preview; only after explicit confirmation run `ccl-skills update --yes`, then restart OpenCode."
    : "Installed from a source checkout. Run `/ccl-update-skills` (or fast-forward the ccl-skills checkout and run `bash scripts/install-opencode.sh`), then restart OpenCode."
  return [
    "\n# CCL Skills Update Reminder",
    `The installed ccl-skills OpenCode assets${mode}${commit} are ${ageDays} day(s) old.`,
    updateInstruction,
  ].join("\n")
}

function git(args: string[], cwd: string) {
  return execFileSync("git", args, {
    cwd,
    encoding: "utf8",
    stdio: ["ignore", "pipe", "ignore"],
  }).trim()
}

// A write may target a file in a directory that does not exist yet; running
// git from a missing cwd throws and would silently disable the guard for
// exactly that case, so walk up to the nearest existing ancestor.
function nearestExistingDir(filePath: string) {
  let dir = dirname(filePath)
  while (dir !== "/" && dir !== "." && !existsSync(dir)) dir = dirname(dir)
  return existsSync(dir) ? dir : null
}

function isPrimaryCheckout(repoRoot: string, cwd: string) {
  // A linked worktree's git-dir lives under <common>/.git/worktrees/<id>;
  // in the primary checkout git-dir and git-common-dir are the same path.
  const gitDir = git(["rev-parse", "--git-dir"], cwd)
  const gitCommonDir = git(["rev-parse", "--git-common-dir"], cwd)
  return resolve(repoRoot, gitDir) === resolve(repoRoot, gitCommonDir)
}

function liveWorktreeCount(cwd: string) {
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

// Mirrors hooks/guard-edit-isolation.sh (the Claude Code PreToolUse guard):
// allow edits from a linked worktree; deny PRIMARY-checkout edits when
//   (a) the repo declares itself shared via a committed `.worktree-only`
//       marker — regardless of branch; or
//   (b) another LIVE worktree exists (parallel work in progress).
function blockReason(filePath: string) {
  try {
    // Resolve a symlinked target (and symlinked ancestors, e.g. /tmp on
    // macOS) so a path pointing into a protected repo is judged by its real
    // location; otherwise repo paths from git (already resolved) and the
    // caller-supplied path silently disagree and the guard never fires.
    let target = resolve(filePath)
    try {
      if (lstatSync(target).isSymbolicLink()) target = realpathSync(target)
    } catch {
      // Target does not exist yet (new file) — judge by its directory below.
    }
    let cwd = nearestExistingDir(target)
    if (!cwd) return null
    cwd = realpathSync(cwd)
    // Repo membership comes from the file's own directory, so no separate
    // containment check is needed (mirrors the Claude hook).
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

export const CclSkills = async () => {
  return {
    "experimental.chat.system.transform": async (_input: unknown, output: { system: string[] }) => {
      const hasBootstrap = output.system.some((entry) => entry.includes(BOOTSTRAP_DEDUPE_MARKER))

      const bootstrap = readBootstrap()
      if (bootstrap && !hasBootstrap) output.system.push(`\n# CCL Skills Bootstrap\n\n${bootstrap}`)

      try {
        const reminder = updateReminder()
        if (reminder && !output.system.some((entry) => entry.includes(UPDATE_REMINDER_MARKER))) output.system.push(reminder)
      } catch {
        // Reminder failures must never break OpenCode startup.
      }
    },

    "tool.execute.before": async (input: { tool: string }, output: { args: { filePath?: string } }) => {
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
