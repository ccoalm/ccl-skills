import { existsSync, readFileSync } from "node:fs"
import { MANIFEST_PATHS } from "./paths.js"

const DEFAULT_UPDATE_REMINDER_DAYS = 7
const DAY_MS = 86_400_000

interface ReminderManifest {
  installed_at?: string
  source_commit?: string
  install_mode?: string
  installer?: string
}

function reminderDays(): number {
  const raw = process.env.CCL_SKILLS_UPDATE_REMINDER_DAYS
  if (raw === undefined || raw === "") return DEFAULT_UPDATE_REMINDER_DAYS
  const parsed = Number(raw)
  if (!Number.isFinite(parsed) || parsed < 0) return DEFAULT_UPDATE_REMINDER_DAYS
  return parsed
}

function readManifest(): ReminderManifest | null {
  for (const path of MANIFEST_PATHS) {
    try {
      if (!existsSync(path)) continue
      return JSON.parse(readFileSync(path, "utf8")) as ReminderManifest
    } catch {
      // Ignore malformed or unreadable manifests.
    }
  }
  return null
}

export interface UpdateReminder {
  title: string
  message: string
  systemPrompt: string
}

export function updateReminder(): UpdateReminder | null {
  const thresholdDays = reminderDays()
  if (thresholdDays <= 0) return null

  const manifest = readManifest()
  if (typeof manifest?.installed_at !== "string") return null

  const installedAt = Date.parse(manifest.installed_at)
  if (!Number.isFinite(installedAt)) return null

  const ageDays = Math.floor((Date.now() - installedAt) / DAY_MS)
  if (ageDays < thresholdDays) return null

  const commit =
    typeof manifest.source_commit === "string" ? ` commit ${manifest.source_commit.slice(0, 12)}` : ""
  const mode = typeof manifest.install_mode === "string" ? ` (${manifest.install_mode})` : ""
  const isNpmInstall = manifest.installer === "ccl-skills-opencode-cli"
  const instruction = isNpmInstall
    ? "Run `ccl-skills-opencode update` to preview; only after confirming run `ccl-skills-opencode update --yes`, then restart OpenCode."
    : "Run `/update` or `/ccl-update-skills`, then restart OpenCode."

  const title = "CCL Skills update reminder"
  const message = `Installed ccl-skills OpenCode assets${mode}${commit} are ${ageDays} day(s) old. ${instruction}`
  const systemPrompt = [
    "\n# CCL Skills Update Reminder",
    `The installed ccl-skills OpenCode assets${mode}${commit} are ${ageDays} day(s) old.`,
    isNpmInstall
      ? "Installed via the npm package. Ask before changing global npm state: run `ccl-skills-opencode update` to preview; only after explicit confirmation run `ccl-skills-opencode update --yes`, then restart OpenCode."
      : "Installed from a source checkout. Run `/update` or `/ccl-update-skills`, then restart OpenCode.",
  ].join("\n")

  return { title, message, systemPrompt }
}
