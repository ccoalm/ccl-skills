// Deterministic verification for the npm package.
// Covers: build, pack contents, CLI help, doctor (version check), install-commands
//         round-trip, install + uninstall safety, CCL_SKILLS_REPO validation,
//         TUI plugin reminder/config, update preview + update --yes (fake npm).
// Does NOT depend on a real OpenCode install or real npm registry.

import { execFileSync, spawnSync } from "node:child_process"
import {
  chmodSync,
  cpSync,
  existsSync,
  mkdirSync,
  mkdtempSync,
  readdirSync,
  readFileSync,
  rmSync,
  writeFileSync,
} from "node:fs"
import { dirname, join, resolve } from "node:path"
import { tmpdir } from "node:os"
import { fileURLToPath } from "node:url"

const here = dirname(fileURLToPath(import.meta.url))
const pkgRoot = resolve(here, "..")
const tuiEntry = pkgRoot
const tuiPackageName = "@ccoalm/ccl-skills-opencode"
const nullDevice = process.platform === "win32" ? "NUL" : "/dev/null"
const npmRuntime = mkdtempSync(join(tmpdir(), "ccl-skills-npm-verify-"))
process.on("exit", () => rmSync(npmRuntime, { recursive: true, force: true }))
// The real ccl-skills repo root (for CCL_SKILLS_REPO positive test).
const repoRoot = resolve(pkgRoot, "..", "..")

function run(cmd, args, opts = {}) {
  let env = opts.env
  if (cmd === "npm") {
    env = {
      ...process.env,
      NPM_CONFIG_CACHE: join(npmRuntime, "cache"),
      NPM_CONFIG_USERCONFIG: nullDevice,
      ...(opts.env ?? {}),
    }
    delete env.npm_config_allow_scripts
    delete env.NPM_CONFIG_ALLOW_SCRIPTS
  }
  return execFileSync(cmd, args, {
    cwd: pkgRoot,
    encoding: "utf8",
    stdio: ["ignore", "pipe", "pipe"],
    ...opts,
    ...(env ? { env } : {}),
  })
}

function runNode(args, env = {}) {
  const result = spawnSync(process.execPath, args, {
    cwd: pkgRoot,
    encoding: "utf8",
    env: { ...process.env, ...env },
  })
  return result
}

let failures = 0

function check(label, condition, detail = "") {
  if (condition) {
    console.log(`  [verify] PASS: ${label}`)
  } else {
    console.error(`  [verify] FAIL: ${label}${detail ? " — " + detail : ""}`)
    failures++
  }
}

// ---------------------------------------------------------------------------
// [1] Build
// ---------------------------------------------------------------------------
console.log("== [1/12] Build ==")
try {
  run("npm", ["ci"])
  run("npm", ["run", "build"])
  check("npm ci + build succeeds", true)
} catch (err) {
  check("npm ci + build succeeds", false, err.stderr || err.message)
  process.exit(1)
}

// ---------------------------------------------------------------------------
// [2] Pack contents
// ---------------------------------------------------------------------------
console.log("== [2/12] Pack contents ==")
try {
  const packOutput = run("npm", ["pack", "--dry-run", "--json"])
  const packs = JSON.parse(packOutput)
  const entries = packs[0].files.map((f) => f.path)
  const required = [
    "dist/index.js",
    "dist/tui.js",
    "dist/cli.js",
    "dist/plugin.js",
    "dist/reminder.js",
    "dist/tui-config.js",
    "dist/paths.js",
    "dist/manifest.js",
    "dist/pkg.js",
    "dist/update.js",
    "dist/assets/bootstrap.md",
    "dist/assets/ccl-skills.ts",
    "dist/assets/opencode.json",
  ]
  for (const f of required) {
    check(`pack includes ${f}`, entries.includes(f), `entries: ${entries.slice(0, 10).join(", ")}...`)
  }
  const pkg = JSON.parse(readFileSync(join(pkgRoot, "package.json"), "utf8"))
  check("package declares server+tui OpenCode plugin", Array.isArray(pkg["oc-plugin"]) && pkg["oc-plugin"].includes("server") && pkg["oc-plugin"].includes("tui"))
  check("package exports ./tui", pkg.exports?.["./tui"] === "./dist/tui.js")
  const hasCommands = entries.some((e) => e.startsWith("dist/assets/commands/ccl-"))
  check("pack includes at least one command template", hasCommands)
} catch (err) {
  check("npm pack --dry-run succeeds", false, err.message)
  failures++
}

// ---------------------------------------------------------------------------
// [3] CLI --help
// ---------------------------------------------------------------------------
console.log("== [3/12] CLI --help ==")
{
  const result = runNode(["dist/cli.js", "--help"])
  check("CLI --help exits 0", result.status === 0)
  check("CLI --help lists subcommands", /install|doctor|uninstall/.test(result.stdout))
  check("CLI --help documents update", /\bupdate\b/.test(result.stdout))
  check("CLI --help documents --yes for uninstall", /--yes/.test(result.stdout))
}

// ---------------------------------------------------------------------------
// [4] CLI doctor (empty HOME)
// ---------------------------------------------------------------------------
console.log("== [4/12] CLI doctor (empty HOME + fake npm version check) ==")
{
  const tmp = mkdtempSync(join(tmpdir(), "cs-doc-"))
  // Fake npm that returns a very high version for `view` and exits 0 for everything else.
  const fakeBin = mkdtempSync(join(tmpdir(), "cs-fakebin-doc-"))
  const fakeNpm = join(fakeBin, "npm")
  writeFileSync(fakeNpm, `#!/bin/sh\nif [ "$1" = "view" ]; then echo '"99.99.99"'; exit 0; fi\nexit 0\n`)
  chmodSync(fakeNpm, 0o755)
  const fakePath = `${fakeBin}:${process.env.PATH ?? ""}`
  try {
    const result = runNode(["dist/cli.js", "doctor"], { HOME: tmp, PATH: fakePath })
    check("CLI doctor exits 0 in empty HOME", result.status === 0, result.stderr)
    check("CLI doctor prints summary", /Summary/i.test(result.stdout))
    check("CLI doctor treats missing file-based plugin as npm-plugin-mode info", /npm plugin mode users don't need one/i.test(result.stdout))
    check("CLI doctor does not warn on missing file-based plugin", !/\[!\].*file-based plugin/i.test(result.stdout))
    check("CLI doctor mentions optional TUI reminder without failing npm-only users", /npm-plugin-only server users are still valid/i.test(result.stdout))
    check("CLI doctor prints version check section", /Version check/i.test(result.stdout))
    check("CLI doctor detects update available via fake npm", /update available.*99\.99\.99/i.test(result.stdout))
    check("CLI doctor suggests update --yes", /update --yes/i.test(result.stdout))
  } finally {
    rmSync(tmp, { recursive: true, force: true })
    rmSync(fakeBin, { recursive: true, force: true })
  }
}

// ---------------------------------------------------------------------------
// [5] install-commands round-trip
// ---------------------------------------------------------------------------
console.log("== [5/12] install-commands round-trip ==")
{
  const tmp = mkdtempSync(join(tmpdir(), "cs-ic-"))
  try {
    const result = runNode(["dist/cli.js", "install-commands", tmp], { HOME: tmp })
    check("install-commands exits 0", result.status === 0, result.stderr)

    const targetConfig = join(tmp, "opencode.json")
    check("creates opencode.json", existsSync(targetConfig))

    if (existsSync(targetConfig)) {
      const config = JSON.parse(readFileSync(targetConfig, "utf8"))
      check("config has $schema", config.$schema === "https://opencode.ai/config.json")
      check("config has command field", typeof config.command === "object" && config.command !== null)
      check("config includes /rd command", "rd" in (config.command ?? {}))
    }

    const rerun = runNode(["dist/cli.js", "install-commands", tmp], { HOME: tmp })
    check("re-run without --force exits 3 (conflict)", rerun.status === 3, `got ${rerun.status}`)

    const force = runNode(["dist/cli.js", "install-commands", tmp, "--force"], { HOME: tmp })
    check("re-run with --force exits 0", force.status === 0, force.stderr)

    // Non-existent project dir should fail.
    const bad = runNode(["dist/cli.js", "install-commands", join(tmp, "does-not-exist")], { HOME: tmp })
    check("install-commands non-existent project exits 1", bad.status === 1, `got ${bad.status}`)
  } finally {
    rmSync(tmp, { recursive: true, force: true })
  }
}

// ---------------------------------------------------------------------------
// [6] install → uninstall dry-run (no deletion)
// ---------------------------------------------------------------------------
console.log("== [6/12] install + uninstall dry-run ==")
{
  const tmp = mkdtempSync(join(tmpdir(), "cs-ins-"))
  try {
    // Install (no CCL_SKILLS_REPO — skills guidance only).
    const ins = runNode(["dist/cli.js", "install"], { HOME: tmp })
    check("install exits 0", ins.status === 0, ins.stderr)
    check("plugin file created", existsSync(join(tmp, ".config/opencode/plugins/ccl-skills.ts")))
    check("bootstrap file created", existsSync(join(tmp, ".config/opencode/ccl-skills/bootstrap.md")))
    const tuiConfig = join(tmp, ".config/opencode/tui.jsonc")
    check("install creates tui.jsonc", existsSync(tuiConfig))
    if (existsSync(tuiConfig)) {
      const tui = JSON.parse(readFileSync(tuiConfig, "utf8"))
      check("install adds TUI plugin entry", Array.isArray(tui.plugin) && tui.plugin.includes(tuiEntry))
    }

    const manifestPath = join(tmp, ".config/opencode/ccl-skills/install-manifest.json")
    check("manifest created", existsSync(manifestPath))
    if (existsSync(manifestPath)) {
      const m = JSON.parse(readFileSync(manifestPath, "utf8"))
      check("manifest installer is ccl-skills-opencode-cli", m.installer === "ccl-skills-opencode-cli")
      check("manifest has owned_files array", Array.isArray(m.owned_files) && m.owned_files.length > 0)
      check("manifest owned_files does not claim user TUI config", !m.owned_files.some((p) => /tui\.jsonc?$/.test(p)))
      check("manifest modified_files records TUI config", Array.isArray(m.modified_files) && m.modified_files.some((p) => /tui\.jsonc?$/.test(p)))
    }

    // Uninstall dry-run (no --yes) — should NOT delete anything.
    const dry = runNode(["dist/cli.js", "uninstall"], { HOME: tmp })
    check("uninstall dry-run exits 0", dry.status === 0, dry.stderr)
    check("dry-run mentions 'dry-run'", /dry-run/i.test(dry.stdout))
    check("plugin still exists after dry-run", existsSync(join(tmp, ".config/opencode/plugins/ccl-skills.ts")))
    check("bootstrap still exists after dry-run", existsSync(join(tmp, ".config/opencode/ccl-skills/bootstrap.md")))
    check("manifest still exists after dry-run", existsSync(manifestPath))
    check("TUI config still exists after dry-run", existsSync(tuiConfig))
  } finally {
    rmSync(tmp, { recursive: true, force: true })
  }
}

// ---------------------------------------------------------------------------
// [7] uninstall --yes removes owned files
// ---------------------------------------------------------------------------
console.log("== [7/12] uninstall --yes removes owned files ==")
{
  const tmp = mkdtempSync(join(tmpdir(), "cs-uny-"))
  try {
    runNode(["dist/cli.js", "install"], { HOME: tmp })
    const plugin = join(tmp, ".config/opencode/plugins/ccl-skills.ts")
    const bootstrap = join(tmp, ".config/opencode/ccl-skills/bootstrap.md")
    const manifest = join(tmp, ".config/opencode/ccl-skills/install-manifest.json")
    const tuiConfig = join(tmp, ".config/opencode/tui.jsonc")
    check("pre: plugin exists", existsSync(plugin))
    writeFileSync(tuiConfig, `// keep this comment\n{\n  "plugin": [\n    "other-plugin",\n    ${JSON.stringify(tuiEntry)} // CCL entry\n  ]\n}\n`)

    const rm = runNode(["dist/cli.js", "uninstall", "--yes"], { HOME: tmp })
    check("uninstall --yes exits 0", rm.status === 0, rm.stderr)
    check("plugin removed", !existsSync(plugin))
    check("bootstrap removed", !existsSync(bootstrap))
    check("manifest removed", !existsSync(manifest))
    check("TUI config file preserved", existsSync(tuiConfig))
    if (existsSync(tuiConfig)) {
      const tui = readFileSync(tuiConfig, "utf8")
      check("uninstall --yes removes only package TUI entry", tui.includes("other-plugin") && !tui.includes(tuiEntry))
      check("uninstall --yes preserves TUI comments", tui.includes("// keep this comment"))
    }
  } finally {
    rmSync(tmp, { recursive: true, force: true })
  }
}

// ---------------------------------------------------------------------------
// [8] uninstall with unknown manifest refuses plugin/bootstrap
// ---------------------------------------------------------------------------
console.log("== [8/12] uninstall unknown manifest refuses ==")
{
  const tmp = mkdtempSync(join(tmpdir(), "cs-unu-"))
  try {
    runNode(["dist/cli.js", "install"], { HOME: tmp })
    const plugin = join(tmp, ".config/opencode/plugins/ccl-skills.ts")
    const bootstrap = join(tmp, ".config/opencode/ccl-skills/bootstrap.md")
    const manifestPath = join(tmp, ".config/opencode/ccl-skills/install-manifest.json")
    const tuiConfig = join(tmp, ".config/opencode/tui.jsonc")

    // Overwrite manifest with an unknown installer.
    writeFileSync(
      manifestPath,
      JSON.stringify({ installed_at: "2024-01-01T00:00:00Z", installer: "some-other-tool" }, null, 2),
    )

    // uninstall --yes should REFUSE plugin/bootstrap/manifest (not owned).
    const rm = runNode(["dist/cli.js", "uninstall", "--yes"], { HOME: tmp })
    check("uninstall --yes exits 0 (refusal is not an error)", rm.status === 0)
    check("refusal output mentions 'Refusing'", /refusing/i.test(rm.stdout + rm.stderr))
    check("plugin NOT removed (unowned)", existsSync(plugin))
    check("bootstrap NOT removed (unowned)", existsSync(bootstrap))
    check("manifest NOT removed (no --force)", existsSync(manifestPath))
    if (existsSync(tuiConfig)) {
      const tui = JSON.parse(readFileSync(tuiConfig, "utf8"))
      check("TUI plugin entry NOT removed (unowned)", tui.plugin.includes(tuiEntry))
    }

    // uninstall --yes --force removes only the unknown manifest.
    const rmf = runNode(["dist/cli.js", "uninstall", "--yes", "--force"], { HOME: tmp })
    check("uninstall --yes --force exits 0", rmf.status === 0)
    check("manifest removed (--force)", !existsSync(manifestPath))
    check("plugin still NOT removed (content valid but unowned)", existsSync(plugin))
    check("bootstrap still NOT removed (content valid but unowned)", existsSync(bootstrap))
  } finally {
    rmSync(tmp, { recursive: true, force: true })
  }
}

// ---------------------------------------------------------------------------
// [8b] TUI config conservative patching
// ---------------------------------------------------------------------------
console.log("== [8b/12] TUI config conservative patching ==")
{
  const tmp = mkdtempSync(join(tmpdir(), "cs-tuicfg-"))
  try {
    const configDir = join(tmp, ".config/opencode")
    mkdirSync(configDir, { recursive: true })
    const tuiJsonc = join(configDir, "tui.jsonc")
    writeFileSync(tuiJsonc, `﻿// top comment\n{\n  // plugin comment\n  "plugin": [\n    "existing-plugin" // keep inline\n  ],\n  "theme": "dark"\n}\n`)
    const result = runNode(["dist/cli.js", "install"], { HOME: tmp })
    check("install with commented tui.jsonc exits 0", result.status === 0, result.stderr)
    const patched = readFileSync(tuiJsonc, "utf8")
    check("install preserves tui.jsonc BOM", patched.charCodeAt(0) === 0xfeff)
    check("install preserves tui.jsonc comments", patched.includes("// top comment") && patched.includes("// plugin comment") && patched.includes("// keep inline"))
    check("install adds entry to commented tui.jsonc", patched.includes(tuiEntry))
    check("install preserves existing TUI plugin", patched.includes("existing-plugin"))
  } finally {
    rmSync(tmp, { recursive: true, force: true })
  }

  const tmpNoPlugin = mkdtempSync(join(tmpdir(), "cs-tuinoplugin-"))
  try {
    const configDir = join(tmpNoPlugin, ".config/opencode")
    mkdirSync(configDir, { recursive: true })
    const tuiJsonc = join(configDir, "tui.jsonc")
    writeFileSync(tuiJsonc, `// theme-only config\n{\n  "theme": "dark"\n}\n`)
    const result = runNode(["dist/cli.js", "install"], { HOME: tmpNoPlugin })
    check("install adds plugin field to theme-only tui.jsonc", result.status === 0, result.stderr)
    const patched = readFileSync(tuiJsonc, "utf8")
    check("theme-only tui.jsonc keeps comment", patched.includes("// theme-only config"))
    check("theme-only tui.jsonc keeps existing field", patched.includes('"theme": "dark"'))
    check("theme-only tui.jsonc gains plugin entry", patched.includes(tuiEntry))
  } finally {
    rmSync(tmpNoPlugin, { recursive: true, force: true })
  }

  const tmpBoth = mkdtempSync(join(tmpdir(), "cs-tuiboth-"))
  try {
    const configDir = join(tmpBoth, ".config/opencode")
    mkdirSync(configDir, { recursive: true })
    const tuiJsonc = join(configDir, "tui.jsonc")
    const tuiJson = join(configDir, "tui.json")
    writeFileSync(tuiJsonc, `{"plugin":["jsonc-only"]}\n`)
    writeFileSync(tuiJson, JSON.stringify({ plugin: [tuiEntry] }) + "\n")
    const result = runNode(["dist/cli.js", "install"], { HOME: tmpBoth })
    check("install with entry in tui.json exits 0", result.status === 0, result.stderr)
    check("install does not duplicate entry into tui.jsonc", !readFileSync(tuiJsonc, "utf8").includes(tuiEntry))
    check("install reports actual existing TUI path", result.stdout.includes(tuiJson))
  } finally {
    rmSync(tmpBoth, { recursive: true, force: true })
  }
}

// ---------------------------------------------------------------------------
// [9] install with valid / invalid CCL_SKILLS_REPO
// ---------------------------------------------------------------------------
console.log("== [9/12] install CCL_SKILLS_REPO validation ==")
{
  const tmpValid = mkdtempSync(join(tmpdir(), "cs-repo-ok-"))
  const tmpInvalid = mkdtempSync(join(tmpdir(), "cs-repo-bad-"))
  try {
    // --- Valid repo ---
    const insOk = runNode(["dist/cli.js", "install"], {
      HOME: tmpValid,
      CCL_SKILLS_REPO: repoRoot,
    })
    check("install with valid repo exits 0", insOk.status === 0, insOk.stderr)
    check("valid repo: skills synced", /synced/i.test(insOk.stdout))

    const skillsDir = join(tmpValid, ".config/opencode/skills")
    check("valid repo: skills directory created", existsSync(skillsDir))
    if (existsSync(skillsDir)) {
      const skillDirs = readdirSync(skillsDir).filter(
        (n) => existsSync(join(skillsDir, n, "SKILL.md")),
      )
      check("valid repo: at least one skill with SKILL.md synced", skillDirs.length > 0)
      const firstSkill = skillDirs[0]
      if (firstSkill) {
        const stale = join(skillsDir, firstSkill, "stale-file-should-be-removed.txt")
        writeFileSync(stale, "stale")
        const reinstall = runNode(["dist/cli.js", "install", "--no-agent"], {
          HOME: tmpValid,
          CCL_SKILLS_REPO: repoRoot,
        })
        check("valid repo: reinstall exits 0", reinstall.status === 0, reinstall.stderr)
        check("valid repo: stale file removed on resync", !existsSync(stale))
      }
    }

    const manifestPath = join(tmpValid, ".config/opencode/ccl-skills/install-manifest.json")
    if (existsSync(manifestPath)) {
      const m = JSON.parse(readFileSync(manifestPath, "utf8"))
      check("valid repo: manifest has source_repo", typeof m.source_repo === "string")
      check("valid repo: manifest has synced_skills array", Array.isArray(m.synced_skills) && m.synced_skills.length > 0)
      check("valid repo: manifest has target_dirs", Array.isArray(m.target_dirs) && m.target_dirs.length > 0)
    }

    // --- Invalid repo (exists but missing required files) ---
    const fakeRepo = mkdtempSync(join(tmpdir(), "cs-fakerepo-"))
    try {
      // Create a dummy file but no skills/, agent-context/session-start.md,
      // AGENTS.md, .worktree-only
      writeFileSync(join(fakeRepo, "README.md"), "not a ccl-skills repo")

      const insBad = runNode(["dist/cli.js", "install"], {
        HOME: tmpInvalid,
        CCL_SKILLS_REPO: fakeRepo,
      })
      check("install with invalid repo exits 0 (guidance, not crash)", insBad.status === 0)
      check("invalid repo: error message printed", /validation failed/i.test(insBad.stdout + insBad.stderr))
      check("invalid repo: NO skills synced", !existsSync(join(tmpInvalid, ".config/opencode/skills")))
      // Plugin/bootstrap should still install (they come from bundled assets).
      check("invalid repo: plugin still installed (bundled)", existsSync(join(tmpInvalid, ".config/opencode/plugins/ccl-skills.ts")))
    } finally {
      rmSync(fakeRepo, { recursive: true, force: true })
    }
  } finally {
    rmSync(tmpValid, { recursive: true, force: true })
    rmSync(tmpInvalid, { recursive: true, force: true })
  }
}

// ---------------------------------------------------------------------------
// [10] TUI export + local stale reminder branches
// ---------------------------------------------------------------------------
console.log("== [10/12] TUI export + reminder branches ==")
function runTuiCase(manifest, env = {}) {
  const tmp = mkdtempSync(join(tmpdir(), "cs-tui-"))
  const manifestDir = join(tmp, ".config/opencode/ccl-skills")
  mkdirSync(manifestDir, { recursive: true })
  if (manifest) {
    writeFileSync(join(manifestDir, "install-manifest.json"), JSON.stringify(manifest, null, 2))
  }
  const code = `
    const mod = await import(${JSON.stringify(resolve(pkgRoot, "dist/tui.js"))});
    const calls = [];
    await mod.default.tui({ ui: { toast: (options) => calls.push(options) } }, { test: true }, { meta: true });
    console.log(JSON.stringify(calls));
  `
  const result = runNode(["--input-type=module", "-e", code], { HOME: tmp, ...env })
  rmSync(tmp, { recursive: true, force: true })
  return result
}
{
  const stale = runTuiCase({
    installed_at: "2024-01-01T00:00:00Z",
    source_commit: "1234567890abcdef",
    install_mode: "global",
    installer: "ccl-skills-opencode-cli",
  })
  check("TUI export imports and executes", stale.status === 0, stale.stderr)
  if (stale.status === 0) {
    const calls = JSON.parse(stale.stdout)
    check("TUI stale npm install shows one toast", calls.length === 1)
    check("TUI stale toast confirms loaded", /loaded/i.test(calls[0]?.title ?? ""))
    check("TUI npm toast suggests update preview", /ccl-skills-opencode update/.test(calls[0]?.message ?? ""))
    check("TUI npm toast suggests --yes after confirmation", /update --yes/.test(calls[0]?.message ?? ""))
    check("TUI npm toast reminds restart", /restart OpenCode/i.test(calls[0]?.message ?? ""))
  }

  const disabled = runTuiCase({ installed_at: "2024-01-01T00:00:00Z", installer: "ccl-skills-opencode-cli" }, { CCL_SKILLS_UPDATE_REMINDER_DAYS: "0" })
  check("TUI disabled threshold exits 0", disabled.status === 0, disabled.stderr)
  if (disabled.status === 0) {
    const calls = JSON.parse(disabled.stdout)
    check("TUI disabled threshold still emits loaded toast", calls.length === 1)
    check("TUI disabled toast confirms loaded", /loaded/i.test(calls[0]?.title ?? ""))
    check("TUI disabled toast has no update warning", !/update --yes/.test(calls[0]?.message ?? ""))
  }

  const fresh = runTuiCase({ installed_at: new Date().toISOString(), installer: "scripts/install-opencode.sh" })
  check("TUI fresh source install exits 0", fresh.status === 0, fresh.stderr)
  if (fresh.status === 0) {
    const calls = JSON.parse(fresh.stdout)
    check("TUI fresh install emits loaded toast", calls.length === 1)
    check("TUI fresh toast confirms loaded", /loaded/i.test(calls[0]?.title ?? ""))
  }

  const missingManifest = runTuiCase(null)
  check("TUI missing manifest exits 0", missingManifest.status === 0, missingManifest.stderr)
  if (missingManifest.status === 0) {
    const calls = JSON.parse(missingManifest.stdout)
    check("TUI missing manifest still emits loaded toast", calls.length === 1)
    check("TUI missing manifest toast confirms loaded", /loaded/i.test(calls[0]?.title ?? ""))
    check("TUI missing manifest toast has no update warning", !/update --yes/.test(calls[0]?.message ?? ""))
  }

  const invalidThreshold = runTuiCase({ installed_at: "2024-01-01T00:00:00Z", installer: "scripts/install-opencode.sh" }, { CCL_SKILLS_UPDATE_REMINDER_DAYS: "bogus" })
  check("TUI invalid threshold falls back to default", invalidThreshold.status === 0, invalidThreshold.stderr)
  if (invalidThreshold.status === 0) {
    const calls = JSON.parse(invalidThreshold.stdout)
    check("TUI source toast suggests slash commands", /\/update.*\/ccl-update-skills|\/ccl-update-skills.*\/update/.test(calls[0]?.message ?? ""))
  }
}

// ---------------------------------------------------------------------------
// [11] update preview (dry-run — no network, no changes)
// ---------------------------------------------------------------------------
console.log("== [11/12] update preview (dry-run) ==")
{
  const tmp = mkdtempSync(join(tmpdir(), "cs-upd-dry-"))
  try {
    const result = runNode(["dist/cli.js", "update"], { HOME: tmp })
    check("update preview exits 0", result.status === 0, result.stderr)
    check("update preview mentions dry-run", /dry-run/i.test(result.stdout))
    check("update preview mentions npm install -g", /npm install -g.*@latest/i.test(result.stdout))
    check("update preview mentions restart OpenCode", /restart opencode/i.test(result.stdout))
    // No files should be created in temp HOME.
    check("update preview creates no plugin file", !existsSync(join(tmp, ".config/opencode/plugins/ccl-skills.ts")))
    check("update preview creates no bootstrap file", !existsSync(join(tmp, ".config/opencode/ccl-skills/bootstrap.md")))
  } finally {
    rmSync(tmp, { recursive: true, force: true })
  }
}

// ---------------------------------------------------------------------------
// [12] update --yes (fake npm — verifies npm install called + install logic runs)
// ---------------------------------------------------------------------------
console.log("== [12/12] update --yes (fake npm) ==")
{
  const tmpHome = mkdtempSync(join(tmpdir(), "cs-upd-yes-"))
  const fakeBin = mkdtempSync(join(tmpdir(), "cs-fakebin-upd-"))
  // Fake npm: logs args for verification, exits 0.
  const callLog = join(fakeBin, "npm-call.log")
  const installCallLog = join(fakeBin, "ccl-skills-opencode-call.log")
  const fakeNpm = join(fakeBin, "npm")
  writeFileSync(fakeNpm, `#!/bin/sh\necho "$@" > "${callLog}"\nexit 0\n`)
  chmodSync(fakeNpm, 0o755)
  const fakeCli = join(fakeBin, "ccl-skills-opencode")
  writeFileSync(fakeCli, `#!/bin/sh\necho "$@" > "${installCallLog}"\nexit 0\n`)
  chmodSync(fakeCli, 0o755)
  const fakePath = `${fakeBin}:${process.env.PATH ?? ""}`
  try {
    const result = runNode(["dist/cli.js", "update", "--yes"], {
      HOME: tmpHome,
      PATH: fakePath,
    })
    check("update --yes exits 0", result.status === 0, result.stderr)
    check("update --yes mentions restart", /restart opencode/i.test(result.stdout))

    // Verify fake npm was called with install -g <pkg>@latest.
    check("fake npm was called", existsSync(callLog))
    if (existsSync(callLog)) {
      const args = readFileSync(callLog, "utf8").trim()
      check("npm called with install -g", /install.*-g/.test(args), `args: ${args}`)
      check("npm called with @latest", /@latest/.test(args), `args: ${args}`)
      check("npm called with package name", /ccl-skills-opencode/.test(args), `args: ${args}`)
    }

    check("latest CLI install was called", existsSync(installCallLog))
    if (existsSync(installCallLog)) {
      const args = readFileSync(installCallLog, "utf8").trim()
      check("latest CLI called with install subcommand", args === "install", `args: ${args}`)
    }
    check("update --yes does not call old in-process install", !existsSync(join(tmpHome, ".config/opencode/plugins/ccl-skills.ts")))
  } finally {
    rmSync(tmpHome, { recursive: true, force: true })
    rmSync(fakeBin, { recursive: true, force: true })
  }
}

// ---------------------------------------------------------------------------
// Result
// ---------------------------------------------------------------------------
console.log("")
if (failures > 0) {
  console.error(`[verify] ${failures} check(s) FAILED`)
  process.exit(1)
} else {
  console.log("[verify] all checks PASSED")
  process.exit(0)
}
