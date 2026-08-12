// `ccl-skills-opencode install-commands <project>` — merges CCL
// command shortcuts into a target project's opencode.json.
//
// Pure-Node reimplementation of scripts/install-opencode-commands.sh (which
// delegates to python3). No Python dependency required.

import { copyFileSync, existsSync, mkdirSync, readFileSync, writeFileSync } from "node:fs"
import { basename, dirname, join, resolve } from "node:path"
import { BUNDLED_OPENCODE_JSON } from "./paths.js"
import { ok, info, warn, fail, section } from "./log.js"

interface CommandDef {
  description?: string
  template?: string
  [key: string]: unknown
}

interface OpenCodeConfig {
  $schema?: string
  command?: Record<string, CommandDef>
  [key: string]: unknown
}

export interface InstallCommandsOptions {
  force?: boolean
}

function readSourceCommands(): Record<string, CommandDef> {
  if (!existsSync(BUNDLED_OPENCODE_JSON)) {
    throw new Error(`Bundled source config not found: ${BUNDLED_OPENCODE_JSON}`)
  }
  const source = JSON.parse(readFileSync(BUNDLED_OPENCODE_JSON, "utf8")) as OpenCodeConfig
  const commands = source.command
  if (!commands || typeof commands !== "object" || Object.keys(commands).length === 0) {
    throw new Error(`Source config has no command field: ${BUNDLED_OPENCODE_JSON}`)
  }
  return commands
}

function resolveTargetConfig(projectDir: string): string {
  const root = resolve(projectDir)
  const rootConfig = join(root, "opencode.json")
  const nestedConfig = join(root, ".opencode", "opencode.json")

  if (existsSync(rootConfig)) return rootConfig
  if (existsSync(nestedConfig)) return nestedConfig
  return rootConfig
}

function uniqueBackupPath(target: string): string {
  const ts = new Date()
    .toISOString()
    .replace(/[:T]/g, "")
    .replace(/\.\d{3}Z$/, "Z")
  let backup = `${target}.bak.${ts}`
  let counter = 1
  while (existsSync(backup)) {
    backup = `${target}.bak.${ts}.${counter}`
    counter++
  }
  return backup
}

export function runInstallCommands(
  projectDir: string,
  options: InstallCommandsOptions = {},
): number {
  section(`Installing commands into project: ${resolve(projectDir)}`)

  if (!existsSync(resolve(projectDir))) {
    fail(`Project directory does not exist: ${resolve(projectDir)}`)
    return 1
  }

  let sourceCommands: Record<string, CommandDef>
  try {
    sourceCommands = readSourceCommands()
  } catch (err) {
    fail(err instanceof Error ? err.message : String(err))
    return 1
  }

  const targetConfig = resolveTargetConfig(projectDir)
  let target: OpenCodeConfig

  if (existsSync(targetConfig)) {
    try {
      target = JSON.parse(readFileSync(targetConfig, "utf8")) as OpenCodeConfig
    } catch {
      fail(`Target config is not valid JSON: ${targetConfig}`)
      return 1
    }
    if (typeof target !== "object" || target === null || Array.isArray(target)) {
      fail(`Target config must be a JSON object: ${targetConfig}`)
      return 1
    }
  } else {
    target = {}
  }

  const targetCommands: Record<string, CommandDef> =
    typeof target.command === "object" && target.command !== null
      ? (target.command as Record<string, CommandDef>)
      : {}
  target.command = targetCommands

  // Conflict check.
  const conflicts = Object.keys(sourceCommands).filter(
    (name) => name in targetCommands && !options.force,
  )
  if (conflicts.length > 0) {
    fail(`Same-name commands already exist, not overwritten: ${conflicts.sort().join(", ")}`)
    info("Re-run with --force to overwrite.")
    return 3
  }

  // Backup before writing (only if the file already exists).
  if (existsSync(targetConfig)) {
    const backup = uniqueBackupPath(targetConfig)
    copyFileSync(targetConfig, backup)
    ok(`Backup created: ${basename(backup)}`)
  }

  // Merge.
  const added: string[] = []
  const updated: string[] = []
  for (const [name, def] of Object.entries(sourceCommands)) {
    if (name in targetCommands) {
      updated.push(name)
    } else {
      added.push(name)
    }
    targetCommands[name] = def
  }

  // Ensure $schema is present.
  if (!target.$schema) {
    target.$schema = "https://opencode.ai/config.json"
  }

  mkdirSync(dirname(targetConfig), { recursive: true })
  writeFileSync(targetConfig, JSON.stringify(target, null, 2) + "\n", "utf8")

  ok(`Config written: ${targetConfig}`)
  ok(`Commands added: ${added.length > 0 ? added.join(", ") : "(none — all existed)"}`)
  if (updated.length > 0) {
    ok(`Commands overwritten: ${updated.join(", ")}`)
  }

  if (!existsSync(BUNDLED_OPENCODE_JSON)) {
    warn(`Source config was missing — used stale/incomplete command set.`)
  }

  info("Restart OpenCode (or open a new session in the target project) for changes to take effect.")
  return 0
}
