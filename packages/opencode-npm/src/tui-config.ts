import { existsSync, mkdirSync, readFileSync, renameSync, writeFileSync } from "node:fs"
import { basename, dirname, join } from "node:path"
import { OPENCODE_CONFIG_ROOT, PKG_ROOT } from "./paths.js"

export const TUI_PLUGIN_PACKAGE = "@ccoalm/ccl-skills-opencode"
export const TUI_PLUGIN_ENTRY = PKG_ROOT
export const TUI_JSONC = join(OPENCODE_CONFIG_ROOT, "tui.jsonc")
export const TUI_JSON = join(OPENCODE_CONFIG_ROOT, "tui.json")

export interface TuiConfigResult {
  changed: boolean
  path: string
  present: boolean
  message: string
}

interface StringSpan {
  start: number
  end: number
  value: string
}

interface PluginArraySpan {
  start: number
  end: number
  entries: StringSpan[]
}

interface TopLevelObjectInfo {
  start: number
  end: number
  hasPluginKey: boolean
}

function writeAtomic(path: string, data: string): void {
  mkdirSync(dirname(path), { recursive: true })
  const tmp = join(dirname(path), `.${basename(path)}.${process.pid}.${Date.now()}.tmp`)
  writeFileSync(tmp, data, "utf8")
  renameSync(tmp, path)
}

function configPath(): string {
  if (existsSync(TUI_JSONC)) return TUI_JSONC
  if (existsSync(TUI_JSON)) return TUI_JSON
  return TUI_JSONC
}

function skipWhitespaceAndComments(text: string, index: number): number {
  let i = index
  while (i < text.length) {
    const ch = text[i]
    const next = text[i + 1]
    if (/\s/.test(ch)) {
      i++
      continue
    }
    if (ch === "/" && next === "/") {
      i += 2
      while (i < text.length && text[i] !== "\n") i++
      continue
    }
    if (ch === "/" && next === "*") {
      i += 2
      while (i < text.length && !(text[i] === "*" && text[i + 1] === "/")) i++
      if (i >= text.length) return i
      i += 2
      continue
    }
    break
  }
  return i
}

function readJsonString(text: string, index: number): StringSpan | null {
  if (text[index] !== '"') return null
  let value = ""
  for (let i = index + 1; i < text.length; i++) {
    const ch = text[i]
    if (ch === '"') return { start: index, end: i + 1, value }
    if (ch !== "\\") {
      value += ch
      continue
    }
    const next = text[++i]
    if (next === undefined) return null
    switch (next) {
      case '"':
      case "\\":
      case "/":
        value += next
        break
      case "b":
        value += "\b"
        break
      case "f":
        value += "\f"
        break
      case "n":
        value += "\n"
        break
      case "r":
        value += "\r"
        break
      case "t":
        value += "\t"
        break
      case "u": {
        const hex = text.slice(i + 1, i + 5)
        if (!/^[0-9a-fA-F]{4}$/.test(hex)) return null
        value += String.fromCharCode(Number.parseInt(hex, 16))
        i += 4
        break
      }
      default:
        return null
    }
  }
  return null
}

function findMatchingBracket(text: string, openIndex: number): number {
  let depth = 0
  for (let i = openIndex; i < text.length; i++) {
    const ch = text[i]
    const next = text[i + 1]
    if (ch === '"') {
      const span = readJsonString(text, i)
      if (!span) return -1
      i = span.end - 1
      continue
    }
    if (ch === "/" && next === "/") {
      i += 2
      while (i < text.length && text[i] !== "\n") i++
      continue
    }
    if (ch === "/" && next === "*") {
      i += 2
      while (i < text.length && !(text[i] === "*" && text[i + 1] === "/")) i++
      if (i >= text.length) return -1
      i++
      continue
    }
    if (ch === "[") depth++
    if (ch === "]") {
      depth--
      if (depth === 0) return i
    }
  }
  return -1
}

function pluginArrayEntries(text: string, arrayStart: number, arrayEnd: number): StringSpan[] {
  const entries: StringSpan[] = []
  let depth = 0
  for (let i = arrayStart + 1; i < arrayEnd; i++) {
    const ch = text[i]
    const next = text[i + 1]
    if (ch === '"') {
      const span = readJsonString(text, i)
      if (!span) throw new Error("Invalid string inside top-level TUI plugin array")
      if (depth === 0) entries.push(span)
      i = span.end - 1
      continue
    }
    if (ch === "/" && next === "/") {
      i += 2
      while (i < text.length && text[i] !== "\n") i++
      continue
    }
    if (ch === "/" && next === "*") {
      i += 2
      while (i < text.length && !(text[i] === "*" && text[i + 1] === "/")) i++
      if (i >= text.length) throw new Error("Unterminated block comment inside TUI plugin array")
      i++
      continue
    }
    if (ch === "[" || ch === "{") depth++
    if (ch === "]" || ch === "}") depth--
  }
  return entries
}

function findTopLevelPluginArray(text: string): PluginArraySpan | null {
  const start = skipWhitespaceAndComments(text, text.charCodeAt(0) === 0xfeff ? 1 : 0)
  if (text[start] !== "{") return null

  let i = start + 1
  while (i < text.length) {
    i = skipWhitespaceAndComments(text, i)
    if (text[i] === "}") return null
    const key = readJsonString(text, i)
    if (!key) return null
    i = skipWhitespaceAndComments(text, key.end)
    if (text[i] !== ":") return null
    i = skipWhitespaceAndComments(text, i + 1)
    if (key.value === "plugin") {
      if (text[i] !== "[") return null
      const end = findMatchingBracket(text, i)
      if (end < 0) return null
      return { start: i, end: end + 1, entries: pluginArrayEntries(text, i, end) }
    }

    i = skipValue(text, i)
    if (i < 0) return null
    i = skipWhitespaceAndComments(text, i)
    if (text[i] === ",") i++
  }
  return null
}

function topLevelObjectInfo(text: string): TopLevelObjectInfo | null {
  const start = skipWhitespaceAndComments(text, text.charCodeAt(0) === 0xfeff ? 1 : 0)
  if (text[start] !== "{") return null

  let i = start + 1
  while (i < text.length) {
    i = skipWhitespaceAndComments(text, i)
    if (text[i] === "}") return { start, end: i + 1, hasPluginKey: false }
    const key = readJsonString(text, i)
    if (!key) return null
    i = skipWhitespaceAndComments(text, key.end)
    if (text[i] !== ":") return null
    i = skipWhitespaceAndComments(text, i + 1)
    const valueEnd = skipValue(text, i)
    if (valueEnd < 0) return null
    if (key.value === "plugin") return { start, end: findObjectEnd(text, start), hasPluginKey: true }
    i = skipWhitespaceAndComments(text, valueEnd)
    if (text[i] === ",") i++
  }
  return null
}

function findObjectEnd(text: string, objectStart: number): number {
  const end = skipValue(text, objectStart)
  return end > 0 ? end : -1
}

function skipValue(text: string, index: number): number {
  let i = index
  const first = text[i]
  if (first === '"') {
    const span = readJsonString(text, i)
    return span ? span.end : -1
  }
  if (first === "[" || first === "{") {
    const open = first
    const close = open === "[" ? "]" : "}"
    let depth = 0
    for (; i < text.length; i++) {
      const ch = text[i]
      const next = text[i + 1]
      if (ch === '"') {
        const span = readJsonString(text, i)
        if (!span) return -1
        i = span.end - 1
        continue
      }
      if (ch === "/" && next === "/") {
        i += 2
        while (i < text.length && text[i] !== "\n") i++
        continue
      }
      if (ch === "/" && next === "*") {
        i += 2
        while (i < text.length && !(text[i] === "*" && text[i + 1] === "/")) i++
        if (i >= text.length) return -1
        i++
        continue
      }
      if (ch === open) depth++
      if (ch === close) {
        depth--
        if (depth === 0) return i + 1
      }
    }
    return -1
  }
  while (i < text.length && ![",", "}", "]"].includes(text[i])) i++
  return i
}

function readText(path: string): string {
  return readFileSync(path, "utf8")
}

function pluginEntryPath(path: string): string | null {
  if (!existsSync(path)) return null
  try {
    const array = findTopLevelPluginArray(readText(path))
    if (array?.entries.some((entry) => isCclSkillsTuiEntry(entry.value))) return path
  } catch {
    // Unsafe or malformed config: no confirmed entry path.
  }
  return null
}

function isCclSkillsTuiEntry(value: string): boolean {
  return value === TUI_PLUGIN_ENTRY || value === TUI_PLUGIN_PACKAGE || value.startsWith(`${TUI_PLUGIN_PACKAGE}@`)
}

export function findTuiPluginEntryPath(): string | null {
  return pluginEntryPath(TUI_JSONC) ?? pluginEntryPath(TUI_JSON)
}

export function hasTuiPluginEntry(): boolean {
  return findTuiPluginEntryPath() !== null
}

function insertEntry(text: string, array: PluginArraySpan): string {
  const beforeClose = text.slice(array.start + 1, array.end - 1)
  const quote = JSON.stringify(TUI_PLUGIN_ENTRY)
  const insertion = array.entries.length === 0 || beforeClose.trim() === "" ? quote : `, ${quote}`
  return text.slice(0, array.end - 1) + insertion + text.slice(array.end - 1)
}

function insertPluginProperty(text: string, objectInfo: TopLevelObjectInfo): string {
  const closeIndex = objectInfo.end - 1
  const body = text.slice(objectInfo.start + 1, closeIndex)
  const property = `"plugin":[${JSON.stringify(TUI_PLUGIN_ENTRY)}]`
  if (body.trim() === "") {
    return text.slice(0, objectInfo.start + 1) + property + text.slice(closeIndex)
  }
  return text.slice(0, closeIndex) + `, ${property}` + text.slice(closeIndex)
}

function commaAfter(text: string, index: number, stop: number): number | null {
  const i = skipWhitespaceAndComments(text, index)
  return i < stop && text[i] === "," ? i : null
}

function commaBefore(text: string, index: number, stop: number): number | null {
  let i = index - 1
  while (i > stop && /\s/.test(text[i])) i--
  if (text[i] === ",") return i
  return null
}

function removeEntry(text: string, array: PluginArraySpan): string {
  const entry = array.entries.find((item) => isCclSkillsTuiEntry(item.value))
  if (!entry) return text
  const after = commaAfter(text, entry.end, array.end - 1)
  if (after !== null) return text.slice(0, entry.start) + text.slice(after + 1)
  const before = commaBefore(text, entry.start, array.start)
  if (before !== null) return text.slice(0, before) + text.slice(entry.end)
  return text.slice(0, entry.start) + text.slice(entry.end)
}

export function ensureTuiPluginEntry(): TuiConfigResult {
  const existing = findTuiPluginEntryPath()
  if (existing) return { changed: false, path: existing, present: true, message: "TUI plugin entry already present" }

  const path = configPath()
  if (!existsSync(path)) {
    writeAtomic(path, `{"plugin":["${TUI_PLUGIN_ENTRY}"]}\n`)
    return { changed: true, path, present: true, message: "TUI plugin entry added" }
  }

  const text = readText(path)
  const array = findTopLevelPluginArray(text)
  if (array) {
    writeAtomic(path, insertEntry(text, array))
    return { changed: true, path, present: true, message: "TUI plugin entry added" }
  }

  const objectInfo = topLevelObjectInfo(text)
  if (!objectInfo || objectInfo.hasPluginKey) {
    throw new Error(`Could not safely find a top-level plugin array in ${path}`)
  }
  writeAtomic(path, insertPluginProperty(text, objectInfo))
  return { changed: true, path, present: true, message: "TUI plugin entry added" }
}

export function removeTuiPluginEntry(): TuiConfigResult {
  const path = findTuiPluginEntryPath() ?? configPath()
  if (!existsSync(path)) return { changed: false, path, present: false, message: "TUI config not found" }
  const text = readText(path)
  const array = findTopLevelPluginArray(text)
  if (!array) {
    throw new Error(`Could not safely find a top-level plugin array in ${path}`)
  }
  if (!array.entries.some((entry) => isCclSkillsTuiEntry(entry.value))) {
    return { changed: false, path, present: false, message: "TUI plugin entry not present" }
  }
  writeAtomic(path, removeEntry(text, array))
  return { changed: true, path, present: false, message: "TUI plugin entry removed" }
}
