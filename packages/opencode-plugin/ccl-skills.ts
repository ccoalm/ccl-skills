import {
  appendFileSync,
  chmodSync,
  existsSync,
  lstatSync,
  mkdirSync,
  mkdtempSync,
  readFileSync,
  realpathSync,
  rmSync,
  statSync,
  writeFileSync,
} from "node:fs"
import { dirname, join, resolve } from "node:path"
import { fileURLToPath } from "node:url"
import { execFileSync, spawnSync } from "node:child_process"
import { createHash } from "node:crypto"
import { tmpdir } from "node:os"

const PLUGIN_DIR = dirname(fileURLToPath(import.meta.url))
const LOCAL_REPO_ROOT = resolve(PLUGIN_DIR, "..")
const SOURCE_REPO_ROOT = resolve(PLUGIN_DIR, "../..")
const HOST_HOME = process.env.HOME ?? ""
const BOOTSTRAP_PATHS = [
  join(LOCAL_REPO_ROOT, "bootstrap.md"),
  join(LOCAL_REPO_ROOT, "ccl-skills", "bootstrap.md"),
  join(HOST_HOME, ".config", "opencode", "ccl-skills", "bootstrap.md"),
  join(SOURCE_REPO_ROOT, "agent-context", "session-start.md"),
]
const MANIFEST_PATHS = [
  join(HOST_HOME, ".config", "opencode", "ccl-skills-npm", "install-manifest.json"),
  join(LOCAL_REPO_ROOT, ".opencode", "ccl-skills", "install-manifest.json"),
  join(LOCAL_REPO_ROOT, "ccl-skills", "install-manifest.json"),
  join(HOST_HOME, ".config", "opencode", "ccl-skills", "install-manifest.json"),
]
const RUNTIME_ROOTS = [
  join(LOCAL_REPO_ROOT, "ccl-skills", "runtime"),
  join(HOST_HOME, ".config", "opencode", "ccl-skills", "runtime"),
  SOURCE_REPO_ROOT,
]
const WORKTREE_MARKER = ".worktree-only"
const UPDATE_REMINDER_DAYS = Number(process.env.CCL_SKILLS_UPDATE_REMINDER_DAYS ?? "7")
const MAX_TRANSCRIPT_BYTES = 4 * 1024 * 1024
// Distinctive substring of bootstrap.md; when the system prompt already carries
// it (e.g. the source repo's opencode.json instructions), skip the second copy.
const BOOTSTRAP_DEDUPE_MARKER = "ccl-skills-routing"
const UPDATE_REMINDER_MARKER = "CCL Skills Update Reminder"

// Keep this inventory in one-to-one correspondence with hooks/hooks.json.
// The npm test compares the two so a newly shipped command hook cannot remain
// silently inactive in OpenCode.
export const OPENCODE_HOOK_BINDINGS = Object.freeze({
  "session-start.sh": "experimental.chat.system.transform",
  "guard-edit-isolation.sh": "tool.execute.before:edit/write/apply_patch",
  "owner-dispatch-guard.sh": "tool.execute.before:edit/write/apply_patch/bash",
  "guard-merge-authorization.sh": "tool.execute.before:bash",
  "remind-unverified-cli-flag.sh": "tool.execute.before:bash",
  "guard-delegation-owner.sh": "tool.execute.before:task/agent",
  "remind-post-merge-cleanup.sh": "tool.execute.after:bash",
  "merge-authorization-prompt.sh": "chat.message",
  "subagent-start.sh": "tool.execute.before:task/agent",
  "owner-dispatch-stop.sh": "event:session.idle/session.status",
  "skill-extraction-gate-stop.sh": "event:session.idle/session.status",
})

type HookJson = {
  hookSpecificOutput?: {
    permissionDecision?: "allow" | "ask" | "deny"
    permissionDecisionReason?: string
    additionalContext?: string
  }
  decision?: "block" | string
  reason?: string
  systemMessage?: string
}

type HookRun = {
  status: "ok" | "missing" | "error"
  output?: HookJson
  message?: string
}

function runtimeRoot() {
  for (const root of RUNTIME_ROOTS) {
    try {
      if (existsSync(join(root, "hooks", "hooks.json"))) return root
    } catch {
      // Try the next package/source layout.
    }
  }
  return null
}

function runHook(root: string | null, script: keyof typeof OPENCODE_HOOK_BINDINGS, payload: object, cwd: string, timeout: number): HookRun {
  if (!root) return { status: "missing", message: "OpenCode hook runtime is not installed" }
  const path = join(root, "hooks", script)
  try {
    if (!existsSync(path) || !lstatSync(path).isFile() || lstatSync(path).isSymbolicLink()) {
      return { status: "missing", message: `${script} is missing from the OpenCode hook runtime` }
    }
    const result = spawnSync("bash", [path], {
      cwd,
      encoding: "utf8",
      env: { ...process.env, CLAUDE_PLUGIN_ROOT: root },
      input: JSON.stringify(payload),
      maxBuffer: 256 * 1024,
      timeout,
    })
    if (result.error || result.status !== 0) {
      return { status: "error", message: result.error?.message ?? `${script} exited ${result.status}` }
    }
    const stdout = result.stdout.trim()
    if (!stdout) return { status: "ok", output: {} }
    const output = JSON.parse(stdout)
    if (!output || typeof output !== "object" || Array.isArray(output)) throw new Error("hook output is not an object")
    return { status: "ok", output: output as HookJson }
  } catch (error) {
    return { status: "error", message: error instanceof Error ? error.message : String(error) }
  }
}

function permission(run: HookRun) {
  const decision = run.output?.hookSpecificOutput?.permissionDecision
  const reason = run.output?.hookSpecificOutput?.permissionDecisionReason
  return { decision, reason }
}

function enforce(run: HookRun, label: string) {
  if (run.status !== "ok") {
    throw new Error(`${label} could not run.\n${run.message ?? "The CCL hook runtime is unavailable."}`)
  }
  const result = permission(run)
  if (result.decision !== "ask" && result.decision !== "deny") return
  throw new Error(`${label} blocked this operation.\n${result.reason ?? "The CCL hook denied the operation."}`)
}

function additionalContext(run: HookRun) {
  const value = run.output?.hookSpecificOutput?.additionalContext
  return typeof value === "string" ? value.trim() : ""
}

function claudeToolName(tool: string) {
  const names: Record<string, string> = {
    edit: "Edit",
    write: "Write",
    apply_patch: "Edit",
    bash: "Bash",
    task: "Task",
    agent: "Agent",
    skill: "Skill",
  }
  return names[tool] ?? tool
}

function patchPaths(patchText: unknown, directory: string) {
  if (typeof patchText !== "string") return []
  const paths: string[] = []
  for (const line of patchText.split("\n")) {
    const match = line.match(/^\*\*\* (?:Add|Update|Delete) File: (.+)$/) ?? line.match(/^\*\*\* Move to: (.+)$/)
    if (!match) continue
    paths.push(resolve(directory, match[1]))
  }
  return [...new Set(paths)]
}

function editPaths(tool: string, args: Record<string, unknown>, directory: string) {
  if (tool === "apply_patch") return patchPaths(args.patchText, directory)
  if (tool !== "edit" && tool !== "write") return []
  const value = args.filePath ?? args.file_path ?? args.path
  return typeof value === "string" && value ? [resolve(directory, value)] : []
}

function promptText(parts: unknown) {
  if (!Array.isArray(parts)) return ""
  return parts
    .filter((part): part is { type: string; text: string } => Boolean(part) && typeof part === "object" && (part as { type?: unknown }).type === "text" && typeof (part as { text?: unknown }).text === "string")
    .map((part) => part.text)
    .join("\n")
}

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

export const CclSkills = async (context: {
  directory?: string
  worktree?: string
  client?: {
    session?: {
      prompt?: (input: unknown) => Promise<unknown>
      promptAsync?: (input: unknown) => Promise<unknown>
    }
  }
} = {}) => {
  const directory = resolve(context.directory ?? context.worktree ?? process.cwd())
  const hooksRoot = runtimeRoot()
  const parentSessions = new Map<string, string>()
  const idleInFlight = new Set<string>()
  let stateRoot: string | null = null

  function ensureStateRoot() {
    if (stateRoot) return stateRoot
    stateRoot = mkdtempSync(join(tmpdir(), "ccl-skills-opencode-"))
    chmodSync(stateRoot, 0o700)
    return stateRoot
  }

  function transcriptPath(sessionID: string) {
    try {
      const key = createHash("sha256").update(sessionID).digest("hex")
      const path = join(ensureStateRoot(), `${key}.jsonl`)
      if (!existsSync(path)) writeFileSync(path, "", { mode: 0o600 })
      return path
    } catch {
      return ""
    }
  }

  function appendTranscript(sessionID: string, value: object) {
    try {
      const path = transcriptPath(sessionID)
      if (!path || statSync(path).size >= MAX_TRANSCRIPT_BYTES) return
      appendFileSync(path, `${JSON.stringify(value)}\n`, { encoding: "utf8" })
    } catch {
      // Transcript evidence improves advisory gates; it must not break the host.
    }
  }

  function payload(sessionID: string, extra: Record<string, unknown> = {}) {
    const currentTranscript = transcriptPath(sessionID)
    const parent = parentSessions.get(sessionID)
    return {
      session_id: sessionID,
      cwd: directory,
      transcript_path: parent ? transcriptPath(parent) : currentTranscript,
      ...(parent ? { agent_id: sessionID, agent_transcript_path: currentTranscript } : {}),
      ...extra,
    }
  }

  function prependTaskContext(args: Record<string, unknown>, values: string[]) {
    const contextText = values.filter(Boolean).join("\n\n")
    if (!contextText) return
    const original = typeof args.prompt === "string" ? args.prompt : ""
    args.prompt = `${contextText}\n\n${original}`.trim()
  }

  function potentialLandingCommand(command: unknown) {
    return typeof command === "string" && /\b(?:git\s+(?:push|merge)|gh\b[^\n;&|]*\bpr\s+merge|glab\b[^\n;&|]*\bmr\s+(?:merge|accept)|curl|wget)\b/i.test(command)
  }

  function safeTranscriptInput(tool: string, args: Record<string, unknown>) {
    if (tool === "skill") return typeof args.skill === "string" ? { skill: args.skill } : {}
    return {}
  }

  async function resumeForStop(sessionID: string, reasons: string[]) {
    if (!reasons.length) return
    const request = {
      path: { id: sessionID },
      body: {
        parts: [{ type: "text", text: `[ccl-skills stop backstop]\n${reasons.join("\n\n")}` }],
      },
    }
    const session = context.client?.session
    if (session?.promptAsync) await session.promptAsync(request)
    else if (session?.prompt) await session.prompt(request)
  }

  return {
    "experimental.chat.system.transform": async (input: { sessionID?: string }, output: { system: string[] }) => {
      const hasBootstrap = output.system.some((entry) => entry.includes(BOOTSTRAP_DEDUPE_MARKER))
      if (!hasBootstrap) {
        const sessionID = input.sessionID ?? `pid-${process.ppid}`
        const result = runHook(hooksRoot, "session-start.sh", payload(sessionID, { source: "startup" }), directory, 5_000)
        const hookContext = additionalContext(result)
        const bootstrap = hookContext || readBootstrap()
        if (bootstrap) output.system.push(`\n# CCL Skills Bootstrap\n\n${bootstrap}`)
      }

      try {
        const reminder = updateReminder()
        if (reminder && !output.system.some((entry) => entry.includes(UPDATE_REMINDER_MARKER))) output.system.push(reminder)
      } catch {
        // Reminder failures must never break OpenCode startup.
      }
    },

    "chat.message": async (input: { sessionID: string }, output: { message?: { role?: string }; parts?: unknown[] }) => {
      const text = promptText(output.parts)
      // The runtime only needs structural tool/skill evidence. Do not persist a
      // second copy of user prompt contents in the temporary bridge transcript.
      appendTranscript(input.sessionID, { type: "user", message: { content: [{ type: "text", text: "" }] } })
      runHook(hooksRoot, "merge-authorization-prompt.sh", payload(input.sessionID, { prompt: text }), directory, 5_000)
    },

    "tool.execute.before": async (
      input: { tool: string; sessionID?: string; callID?: string },
      output: { args?: Record<string, unknown> },
    ) => {
      const tool = input.tool.toLowerCase()
      const sessionID = input.sessionID ?? `pid-${process.ppid}`
      const callID = input.callID ?? `call-${Date.now()}`
      const args = output.args ?? {}
      output.args = args
      const targets = editPaths(tool, args, directory)
      const toolName = claudeToolName(tool)
      if (targets.length) {
        targets.forEach((filePath, index) => appendTranscript(sessionID, {
          type: "assistant",
          message: { content: [{ type: "tool_use", id: targets.length === 1 ? callID : `${callID}-${index}`, name: "Edit", input: { file_path: filePath } }] },
        }))
      } else {
        appendTranscript(sessionID, {
          type: "assistant",
          message: { content: [{ type: "tool_use", id: callID, name: toolName, input: safeTranscriptInput(tool, args) }] },
        })
      }

      for (const filePath of targets) {
        const reason = blockReason(filePath)
        if (reason) {
          throw new Error(
            [
              "ccl-skills worktree guard blocked this edit.",
              `Target file: ${filePath}`,
              reason,
              "Create a feature worktree first (git worktree add -b <branch> <path>), then retry the edit there.",
            ].join("\n"),
          )
        }
        const hookPayload = payload(sessionID, { tool_name: "Edit", tool_input: { ...args, file_path: filePath } })
        enforce(runHook(hooksRoot, "guard-edit-isolation.sh", hookPayload, directory, 10_000), "ccl-skills edit-isolation guard")
        enforce(runHook(hooksRoot, "owner-dispatch-guard.sh", hookPayload, directory, 10_000), "ccl-skills owner-dispatch guard")
      }

      if (tool === "bash") {
        const hookPayload = payload(sessionID, { tool_name: "Bash", tool_input: args })
        enforce(runHook(hooksRoot, "owner-dispatch-guard.sh", hookPayload, directory, 10_000), "ccl-skills owner-dispatch guard")
        const merge = runHook(hooksRoot, "guard-merge-authorization.sh", hookPayload, directory, 10_000)
        if (merge.status !== "ok" && potentialLandingCommand(args.command)) {
          throw new Error(`ccl-skills merge authorization blocked this operation.\n${merge.message ?? "OpenCode hook runtime unavailable."}`)
        }
        enforce(merge, "ccl-skills merge authorization")
        // Advisory only: it never blocks, so its context is appended rather than
        // enforced. Mirrors hooks/remind-unverified-cli-flag.sh under Claude Code.
        const flagNote = additionalContext(runHook(hooksRoot, "remind-unverified-cli-flag.sh", hookPayload, directory, 10_000))
        if (flagNote) prependTaskContext(args, [flagNote])
      }

      if (tool === "task" || tool === "agent") {
        const hookPayload = payload(sessionID, { tool_name: toolName, tool_input: args })
        const delegation = runHook(hooksRoot, "guard-delegation-owner.sh", hookPayload, directory, 10_000)
        const delegationReason = permission(delegation).reason ?? ""
        enforce(delegation, "ccl-skills delegation-owner guard")
        const subagent = runHook(hooksRoot, "subagent-start.sh", hookPayload, directory, 5_000)
        enforce(subagent, "ccl-skills subagent-context hook")
        prependTaskContext(args, [delegationReason, additionalContext(subagent)])
      }
    },

    "tool.execute.after": async (
      input: { tool: string; sessionID?: string; callID?: string; args?: Record<string, unknown> },
      output: { title?: string; output?: string; metadata?: unknown },
    ) => {
      const tool = input.tool.toLowerCase()
      const sessionID = input.sessionID ?? `pid-${process.ppid}`
      const callID = input.callID ?? "unknown-call"
      appendTranscript(sessionID, {
        type: "user",
        message: { content: [{ type: "tool_result", tool_use_id: callID, content: "" }] },
      })
      if (tool !== "bash") return
      const run = runHook(hooksRoot, "remind-post-merge-cleanup.sh", payload(sessionID, {
        tool_name: "Bash",
        tool_input: input.args ?? {},
        tool_response: { output: output.output ?? "", metadata: output.metadata ?? {} },
      }), directory, 10_000)
      const reminder = additionalContext(run)
      if (reminder) output.output = [output.output ?? "", reminder].filter(Boolean).join("\n\n")
    },

    event: async (input: { event?: { type?: string; properties?: Record<string, unknown> } }) => {
      const event = input.event
      if (!event?.type) return
      const properties = event.properties ?? {}
      if (event.type === "session.created") {
        const info = properties.info as { id?: string; parentID?: string } | undefined
        if (info?.id && info.parentID) parentSessions.set(info.id, info.parentID)
        return
      }
      const sessionID = typeof properties.sessionID === "string"
        ? properties.sessionID
        : typeof (properties.info as { id?: unknown } | undefined)?.id === "string"
          ? (properties.info as { id: string }).id
          : ""
      if (!sessionID) return
      if (event.type === "session.deleted") {
        const path = transcriptPath(sessionID)
        if (path) rmSync(path, { force: true })
        parentSessions.delete(sessionID)
        return
      }
      const status = properties.status as { type?: string } | undefined
      const isIdle = event.type === "session.idle" || (event.type === "session.status" && status?.type === "idle")
      if (!isIdle || idleInFlight.has(sessionID)) return
      idleInFlight.add(sessionID)
      try {
        const stopPayload = payload(sessionID, { stop_hook_active: false })
        const results = [
          runHook(hooksRoot, "owner-dispatch-stop.sh", stopPayload, directory, 10_000),
          runHook(hooksRoot, "skill-extraction-gate-stop.sh", stopPayload, directory, 15_000),
        ]
        const reasons = results
          .filter((result) => result.output?.decision === "block" && typeof result.output.reason === "string")
          .map((result) => result.output?.reason as string)
        await resumeForStop(sessionID, reasons)
      } finally {
        idleInFlight.delete(sessionID)
      }
    },

    dispose: async () => {
      if (stateRoot) rmSync(stateRoot, { recursive: true, force: true })
      stateRoot = null
    },
  }
}
