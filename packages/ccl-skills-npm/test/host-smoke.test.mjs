import test from "node:test";
import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { chmodSync, cpSync, existsSync, mkdirSync, mkdtempSync, readdirSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";

process.umask(0o022);

const pkgDir = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const repoRoot = resolve(pkgDir, "../..");

function buildMiniSmokeRepo(sandbox) {
	const repo = join(sandbox, "repo");
	const miniPkg = join(repo, "packages/ccl-skills-npm");
	mkdirSync(miniPkg, { recursive: true });

	// Stage minimal tracked roots matching build-assets.mjs allowlist + compiled dist
	const copyTracked = [
		".claude-plugin/plugin.json",
		".codex-plugin/plugin.json",
		".antigravity-plugin/plugin.json",
		"hooks.json",
		"agent-context/session-start.md",
		"agent-context/session-policy.md",
		"agent-context/subagent-start.md",
		"skills/product-rd-workflow/SKILL.md",
		"skills/code-review/SKILL.md",
		"hooks/hooks.json",
		"hooks/agy-bridge.py",
		"hooks/host-input.py",
		"hooks/skill-loading.py",
		"hooks/guard-merge-authorization.sh",
		"hooks/merge-authorization-prompt.sh",
		"packages/opencode-plugin/ccl-skills.ts",
		"packages/opencode-plugin/commands/ccl-install-skills.md",
		"scripts/owner-dispatch/owner-dispatch.sh",
		"skills/code-review/scripts/normalize_review_timeout.sh",
		"skills/code-review/scripts/update_review_plan_intent.py",
		".worktree-only",
		"packages/ccl-skills-npm/package.json",
		"packages/ccl-skills-npm/package-lock.json",
		"packages/ccl-skills-npm/README.md",
		"packages/ccl-skills-npm/LICENSE",
		"packages/ccl-skills-npm/scripts/build-assets.mjs",
		"packages/ccl-skills-npm/scripts/verify-packed.mjs",
		"packages/ccl-skills-npm/scripts/host-smoke.sh",
	];
	for (const rel of copyTracked) {
		const src = join(repoRoot, rel);
		const dst = join(repo, rel);
		mkdirSync(dirname(dst), { recursive: true });
		cpSync(src, dst);
	}
	// Stash pre-built JS runtime files outside the repo so the offline `tsc` shim can emit `dist/*.js`
	// during `npm run build` just like real `tsc`, while `dist/` stays untracked inside the repo.
	const realDist = join(pkgDir, "dist");
	const prebuiltDist = join(sandbox, "prebuilt-dist");
	mkdirSync(prebuiltDist, { recursive: true });
	if (existsSync(join(realDist, "cli.js"))) {
		for (const entry of readdirSync(realDist)) {
			if (entry.endsWith(".js")) {
				cpSync(join(realDist, entry), join(prebuiltDist, entry));
			}
		}
	} else {
		const tscBin = existsSync(join(pkgDir, "node_modules/.bin/tsc")) ? join(pkgDir, "node_modules/.bin/tsc") : "tsc";
		const built = spawnSync(tscBin, ["-p", join(pkgDir, "tsconfig.json"), "--outDir", prebuiltDist], { encoding: "utf8" });
		assert.equal(built.status, 0, built.stderr || built.stdout);
	}

	const gitEnv = { ...process.env, GIT_CONFIG_NOSYSTEM: "1", GIT_CONFIG_GLOBAL: "/dev/null", GIT_CONFIG_SYSTEM: "/dev/null" };
	assert.equal(spawnSync("git", ["init", "-q", "-b", "main", repo], { env: gitEnv }).status, 0);
	assert.equal(spawnSync("git", ["-C", repo, "add", "."], { env: gitEnv }).status, 0);
	assert.equal(spawnSync("git", ["-C", repo, "-c", "user.name=test", "-c", "user.email=test@example.invalid", "commit", "-qm", "fixture"], { env: gitEnv }).status, 0);

	// Plant untracked workspace canaries AFTER commit: tracked-only staging must ignore all of them!
	writeFileSync(join(repo, "skills/product-rd-workflow/UNTRACKED_SKILL_CANARY.md"), "untracked");
	writeFileSync(join(repo, "packages/opencode-plugin/commands/UNTRACKED_CMD_CANARY.md"), "untracked");
	writeFileSync(join(miniPkg, "UNTRACKED_PKG_CANARY.txt"), "untracked");

	return { repo, miniPkg, prebuiltDist, smokeScript: join(miniPkg, "scripts/host-smoke.sh") };
}

function makeStubBin(sandbox, prebuiltDist) {
	const bin = join(sandbox, "stub-bin");
	mkdirSync(bin, { recursive: true });

	const whichGit = spawnSync("sh", ["-c", "command -v git"], { encoding: "utf8" });
	const realGit = whichGit.stdout.trim();
	writeFileSync(join(bin, "git"), `#!/usr/bin/env node
const { spawnSync } = require("node:child_process");
const args = process.argv.slice(2);
const guardedRepo = process.env.SMOKE_DUBIOUS_OWNERSHIP_REPO;
if (guardedRepo && args.includes("ls-files") && args.includes(guardedRepo)) {
  const hasSafeDir = args.some((a, idx) => a === "-c" && (args[idx + 1] === "safe.directory=" + guardedRepo || args[idx + 1] === "safe.directory=*"));
  if (!hasSafeDir) {
    console.error("fatal: detected dubious ownership in repository at '" + guardedRepo + "'");
    process.exit(128);
  }
}
const res = spawnSync(${JSON.stringify(realGit)}, args, { stdio: "inherit" });
process.exit(res.status ?? 1);
`, { mode: 0o755 });

	// Offline fast `npm` + `tsc` shims exercising real build-assets.mjs, verify-packed.mjs, tarballs, and dist/cli.js
	writeFileSync(join(bin, "tsc"), `#!/usr/bin/env node
const fs = require("node:fs");
const path = require("node:path");
const src = ${JSON.stringify(prebuiltDist)};
fs.mkdirSync("dist", { recursive: true });
for (const entry of fs.readdirSync(src)) {
  fs.cpSync(path.join(src, entry), path.join("dist", entry));
}
`, { mode: 0o755 });
	writeFileSync(join(bin, "npm"), `#!/usr/bin/env node
process.umask(0o022);
const { spawnSync } = require("node:child_process");
const fs = require("node:fs");
const path = require("node:path");
const allowedGitEnv = new Set(["GIT_CONFIG_NOSYSTEM", "GIT_CONFIG_GLOBAL", "GIT_CONFIG_SYSTEM"]);
const leakedGit = Object.keys(process.env).filter((k) => k.startsWith("GIT_") && !allowedGitEnv.has(k));
if (leakedGit.length) {
  console.error("leaked GIT env into host-smoke: " + leakedGit.join(","));
  process.exit(9);
}
const args = process.argv.slice(2);
const isBuild = args[0] === "run" && args[1] === "build";
const forbiddenCiEnv = [
  "CONTINUOUS_INTEGRATION",
  "BUILD_NUMBER",
  "GITLAB_CI",
  "BUILDKITE",
  "CIRCLECI",
  "TRAVIS",
  "TEAMCITY_VERSION",
  "JENKINS_URL",
  "EXPECT_SOURCE_COMMIT",
  "REQUIRE_CLEAN_RELEASE",
  ...(isBuild ? [] : ["CI"]),
];
const leakedCi = [
  ...forbiddenCiEnv.filter((k) => process.env[k] !== undefined),
  ...Object.keys(process.env).filter(
    (k) => k.startsWith("GITHUB_") || (k.startsWith("CI_") && !(isBuild && k === "CI_COMMIT_SHA")),
  ),
];
if (leakedCi.length) {
  console.error("leaked CI/release env into npm(" + args.join(" ") + "): " + leakedCi.join(","));
  process.exit(9);
}
if (isBuild && !/^0{39}[12]$/.test(process.env.CI_COMMIT_SHA || "")) {
  console.error("unexpected CI_COMMIT_SHA in synthetic build: " + process.env.CI_COMMIT_SHA);
  process.exit(9);
}
if (args[0] === "ci") {
  fs.mkdirSync("node_modules/.bin", { recursive: true });
  process.exit(0);
}
if (args[0] === "version") {
  const ver = args[1];
  const pkg = JSON.parse(fs.readFileSync("package.json", "utf8"));
  pkg.version = ver;
  fs.writeFileSync("package.json", JSON.stringify(pkg, null, 2) + "\\n");
  process.exit(0);
}
if (args[0] === "run" && args[1] === "build") {
  const tc = spawnSync("tsc", [], { stdio: "inherit" });
  if ((tc.status ?? 1) !== 0) process.exit(tc.status ?? 1);
  fs.chmodSync("dist/cli.js", 0o755);
  const r = spawnSync(process.execPath, ["scripts/build-assets.mjs"], { stdio: "inherit" });
  process.exit(r.status ?? 1);
}
if (args[0] === "pack") {
  if (fs.existsSync("UNTRACKED_PKG_CANARY.txt")) {
    console.error("untracked package file leaked into staged source");
    process.exit(9);
  }
  const pkg = JSON.parse(fs.readFileSync("package.json", "utf8"));
  const release = JSON.parse(fs.readFileSync("dist/assets/release.json", "utf8"));
  const expectedCommit = "0".repeat(39) + pkg.version.split(".")[0];
  if (release.sourceCommit !== expectedCommit || release.sourceState !== "clean") {
    console.error(
      "unexpected synthetic release metadata: " +
        JSON.stringify({ sourceCommit: release.sourceCommit, sourceState: release.sourceState, expectedCommit }),
    );
    process.exit(9);
  }
  if (process.env.SMOKE_PACK_RELEASE_LOG) {
    fs.appendFileSync(
      process.env.SMOKE_PACK_RELEASE_LOG,
      JSON.stringify({ version: pkg.version, sourceCommit: release.sourceCommit, sourceState: release.sourceState }) + "\\n",
    );
  }
  const outName = "ccoalm-ccl-skills-" + pkg.version + ".tgz";
  const stage = fs.mkdtempSync(path.join(require("node:os").tmpdir(), "stub-pack-"));
  const dst = path.join(stage, "package");
  fs.mkdirSync(dst, { recursive: true });
  for (const item of ["package.json", "LICENSE", "README.md", "dist"]) {
    if (fs.existsSync(item)) fs.cpSync(item, path.join(dst, item), { recursive: true });
  }
  const tar = spawnSync("tar", ["-czf", path.resolve(outName), "-C", stage, "package"], { stdio: "inherit" });
  fs.rmSync(stage, { recursive: true, force: true });
  if ((tar.status ?? 1) !== 0) process.exit(tar.status ?? 1);
  process.stdout.write(outName + "\\n");
  process.exit(0);
}
if (args[0] === "install") {
  const tgz = args.find((a) => a.endsWith(".tgz"));
  const dest = path.resolve("node_modules/@ccoalm/ccl-skills");
  fs.rmSync(dest, { recursive: true, force: true });
  fs.mkdirSync(dest, { recursive: true });
  const tar = spawnSync("tar", ["-xzf", tgz, "--strip-components=1", "-C", dest], { stdio: "inherit" });
  process.exit(tar.status ?? 1);
}
process.exit(2);
`, { mode: 0o755 });

	// Stub codex CLI
	writeFileSync(join(bin, "codex"), `#!/usr/bin/env node
const fs = require("node:fs");
const path = require("node:path");
const args = process.argv.slice(2);
if (args[0] === "--version") { console.log("codex-cli 0.133.0"); process.exit(0); }
const stateFile = path.join(process.env.CODEX_HOME, "stub-codex-state.json");
const load = () => fs.existsSync(stateFile) ? JSON.parse(fs.readFileSync(stateFile, "utf8")) : { market: null, plugin: false };
const save = (s) => { fs.mkdirSync(path.dirname(stateFile), { recursive: true }); fs.writeFileSync(stateFile, JSON.stringify(s)); };
const st = load();
if (args[0] === "plugin" && args[1] === "marketplace" && args[2] === "list") {
  if (st.market) {
    console.log("MARKETPLACE  ROOT");
    console.log("ccl-skills-npm  " + st.market);
  } else {
    console.log("No plugin marketplaces in scope.");
  }
  process.exit(0);
}
if (args[0] === "plugin" && args[1] === "marketplace" && (args[2] === "add" || args[2] === "upgrade")) {
  if (args[3]) st.market = path.resolve(args[3]);
  save(st); process.exit(0);
}
if (args[0] === "plugin" && args[1] === "marketplace" && args[2] === "remove") {
  st.market = null; save(st); process.exit(0);
}
if (args[0] === "plugin" && args[1] === "list") {
  if (st.plugin) {
    console.log("PLUGIN  STATUS  VERSION  SOURCE");
    console.log("ccl-skills@ccl-skills-npm  installed, enabled  local  " + (st.market || "/tmp/source"));
  } else {
    console.log("No marketplace plugins found.");
  }
  process.exit(0);
}
if (args[0] === "plugin" && args[1] === "install" || (args[0] === "plugin" && args[1] === "add")) {
  st.plugin = true; save(st); process.exit(0);
}
if (args[0] === "plugin" && (args[1] === "uninstall" || args[1] === "remove")) {
  st.plugin = false; save(st); process.exit(0);
}
process.exit(0);
`, { mode: 0o755 });

	// Stub claude CLI (fails if CLAUDE_CONFIG_DIR or CLAUDE_CODE_PLUGIN_* leaked)
	writeFileSync(join(bin, "claude"), `#!/usr/bin/env node
const fs = require("node:fs");
const path = require("node:path");
if (process.env.CLAUDE_CONFIG_DIR || Object.keys(process.env).some((k) => k.startsWith("CLAUDE_CODE_PLUGIN_"))) {
  console.error("leaked CLAUDE env into host-smoke");
  process.exit(9);
}
const args = process.argv.slice(2);
if (args[0] === "--version") { console.log("2.1.0"); process.exit(0); }
const stateFile = path.join(process.env.HOME, ".claude", "stub-claude-state.json");
const load = () => fs.existsSync(stateFile) ? JSON.parse(fs.readFileSync(stateFile, "utf8")) : { market: null, plugin: false };
const save = (s) => { fs.mkdirSync(path.dirname(stateFile), { recursive: true }); fs.writeFileSync(stateFile, JSON.stringify(s)); };
const st = load();
if (args[0] === "plugin" && args[1] === "marketplace" && args[2] === "list") {
  console.log(JSON.stringify(st.market ? [{ name: "ccl-skills-npm", installLocation: st.market }] : []));
  process.exit(0);
}
if (args[0] === "plugin" && args[1] === "marketplace" && args[2] === "add") {
  st.market = path.resolve(args[3]); save(st); process.exit(0);
}
if (args[0] === "plugin" && args[1] === "marketplace" && args[2] === "remove") {
  st.market = null; save(st); process.exit(0);
}
if (args[0] === "plugin" && args[1] === "list") {
  console.log(JSON.stringify(st.plugin ? [{ id: "ccl-skills@ccl-skills-npm", enabled: true }] : []));
  process.exit(0);
}
if (args[0] === "plugin" && args[1] === "install") {
  st.plugin = true; save(st); process.exit(0);
}
if (args[0] === "plugin" && args[1] === "uninstall") {
  st.plugin = false; save(st); process.exit(0);
}
process.exit(0);
`, { mode: 0o755 });

	// Stub opencode CLI: mirrors real OpenCode XDG_CONFIG_HOME precedence and checks leaked OPENCODE_*/CCL_SKILLS_REPO
	writeFileSync(join(bin, "opencode"), `#!/usr/bin/env node
const fs = require("node:fs");
const path = require("node:path");
const args = process.argv.slice(2);
if (args[0] === "--version") { console.log("1.4.0"); process.exit(0); }
for (const bad of ["OPENCODE_CONFIG", "OPENCODE_CONFIG_DIR", "OPENCODE_CONFIG_CONTENT", "CCL_SKILLS_REPO"]) {
  if (process.env[bad]) { console.error("leaked " + bad + "=" + process.env[bad]); process.exit(9); }
}
for (const xdg of ["XDG_CONFIG_HOME", "XDG_DATA_HOME", "XDG_STATE_HOME", "XDG_CACHE_HOME"]) {
  const val = process.env[xdg] || "";
  if (!val.startsWith(process.env.HOME + "/")) {
    console.error(xdg + " not isolated under HOME: " + val);
    process.exit(9);
  }
}
if (args[0] === "debug" && args[1] === "config") {
  const cfgRoot = path.join(process.env.XDG_CONFIG_HOME || path.join(process.env.HOME, ".config"), "opencode");
  if (fs.existsSync(path.join(cfgRoot, "commands/UNTRACKED_CMD_CANARY.md"))) {
    console.error("untracked opencode command leaked into staged package");
    process.exit(9);
  }
  const pluginPath = path.join(cfgRoot, "plugins/ccl-skills.ts");
  console.log(JSON.stringify({ plugin: fs.existsSync(pluginPath) ? [pluginPath] : [] }));
  process.exit(0);
}
process.exit(0);
`, { mode: 0o755 });

	// Stub agy CLI
	writeFileSync(join(bin, "agy"), `#!/usr/bin/env node
const fs = require("node:fs");
const path = require("node:path");
const args = process.argv.slice(2);
const leakedAgyEnv = Object.keys(process.env).filter(
  (k) => k.startsWith("ANTIGRAVITY_") || k.startsWith("AGY_"),
);
if (leakedAgyEnv.length) {
  console.error("leaked ANTIGRAVITY/AGY env into agy: " + leakedAgyEnv.join(","));
  process.exit(9);
}
const leakedReleaseEnv = Object.keys(process.env).filter(
  (k) =>
    k === "CI" ||
    k === "CONTINUOUS_INTEGRATION" ||
    k === "BUILD_NUMBER" ||
    k === "GITLAB_CI" ||
    k === "EXPECT_SOURCE_COMMIT" ||
    k === "REQUIRE_CLEAN_RELEASE" ||
    k.startsWith("GITHUB_") ||
    k.startsWith("CI_"),
);
if (process.env.SMOKE_ENV_AUDIT_LOG) {
  fs.appendFileSync(
    process.env.SMOKE_ENV_AUDIT_LOG,
    JSON.stringify({ tool: "agy", args, leakedReleaseEnv, leakedAgyEnv }) + "\\n",
  );
}
if (leakedReleaseEnv.length) {
  console.error("leaked CI/release env into agy: " + leakedReleaseEnv.join(","));
  process.exit(9);
}
if (args.includes("--LogFile") || process.env.SMOKE_AGY_CALL_LOG) {
  if (process.env.SMOKE_AGY_CALL_LOG) fs.appendFileSync(process.env.SMOKE_AGY_CALL_LOG, args.join(" ") + "\\n");
}
if (args[0] === "--version") { console.log("1.5.14"); process.exit(0); }
const geminiRoot = process.env.ANTIGRAVITY_GEMINI_DIR || path.join(process.env.HOME, ".gemini");
const dest = path.join(geminiRoot, "config/plugins/ccl-skills");
const staleMarker = path.join(geminiRoot, "stale-post-uninstall.flag");
if (args[0] === "plugin" && args[1] === "list") {
  if (process.env.SMOKE_STALE_POST_UNINSTALL_LIST === "1" && fs.existsSync(staleMarker)) {
    const count = Number(fs.readFileSync(staleMarker, "utf8")) + 1;
    fs.writeFileSync(staleMarker, String(count));
    if (count >= 2) {
      console.log(JSON.stringify([{ name: "ccl-skills", enabled: true, source: "antigravity", path: dest }]));
      process.exit(0);
    }
  }
  console.log(JSON.stringify(fs.existsSync(dest) ? [{ name: "ccl-skills", enabled: true, source: "antigravity", path: dest }] : []));
  process.exit(0);
}
if (args[0] === "plugin" && args[1] === "install") {
  const src = args[2];
  if (fs.existsSync(path.join(src, "skills/product-rd-workflow/UNTRACKED_SKILL_CANARY.md"))) {
    console.error("untracked workspace file leaked into packaged plugin");
    process.exit(9);
  }
  fs.rmSync(staleMarker, { force: true });
  fs.rmSync(dest, { recursive: true, force: true });
  fs.mkdirSync(path.dirname(dest), { recursive: true });
  fs.cpSync(src, dest, { recursive: true });
  process.exit(0);
}
if (args[0] === "plugin" && args[1] === "uninstall") {
  fs.rmSync(dest, { recursive: true, force: true });
  if (process.env.SMOKE_STALE_POST_UNINSTALL_LIST === "1") {
    fs.mkdirSync(geminiRoot, { recursive: true });
    fs.writeFileSync(staleMarker, "0");
  }
  process.exit(0);
}
process.exit(2);
`, { mode: 0o755 });

	return bin;
}

test("host-smoke fails closed with exit 4 when agy CLI is missing", () => {
	const sandbox = mkdtempSync(join(tmpdir(), "ccl-host-smoke-missing-"));
	try {
		const { repo, smokeScript, prebuiltDist } = buildMiniSmokeRepo(sandbox);
		const bin = makeStubBin(sandbox, prebuiltDist);
		rmSync(join(bin, "agy"));
		// Symlink only essential POSIX utilities into an isolated PATH without agy
		const sysBin = join(sandbox, "sys-bin");
		mkdirSync(sysBin);
		for (const tool of ["bash", "sh", "env", "mkdir", "rm", "cp", "mv", "cat", "grep", "awk", "find", "wc", "tr", "printf", "test", "dirname", "basename", "mktemp", "chmod", "tar", "git", "node"]) {
			const which = spawnSync("sh", ["-c", `command -v ${tool}`], { encoding: "utf8" });
			if (which.status === 0 && which.stdout.trim()) {
				const target = which.stdout.trim();
				writeFileSync(join(sysBin, tool), `#!/bin/sh\nexec "${target}" "$@"\n`, { mode: 0o755 });
			}
		}
		const res = spawnSync("bash", [smokeScript], {
			encoding: "utf8",
			env: { PATH: `${bin}:${sysBin}`, HOME: join(sandbox, "caller-home") },
		});
		assert.equal(res.status, 4, res.stderr || res.stdout);
		assert.match(res.stderr, /agy missing/);
	} finally {
		rmSync(sandbox, { recursive: true, force: true });
	}
});

test("host-smoke isolates XDG/OPENCODE/CCL_SKILLS_REPO env, stages only tracked files, and exercises all 4 hosts including antigravity", () => {
	const sandbox = mkdtempSync(join(tmpdir(), "ccl-host-smoke-e2e-"));
	try {
		const { repo, smokeScript, prebuiltDist } = buildMiniSmokeRepo(sandbox);
		const bin = makeStubBin(sandbox, prebuiltDist);
		const agyLog = join(sandbox, "agy-calls.log");
		const packReleaseLog = join(sandbox, "pack-release.jsonl");
		const envAuditLog = join(sandbox, "env-audit.jsonl");
		const poisonXdg = join(sandbox, "poison-xdg");
		mkdirSync(join(poisonXdg, "opencode"), { recursive: true });
		writeFileSync(join(poisonXdg, "opencode/opencode.json"), '{"plugin":[]}');

		const res = spawnSync("bash", [smokeScript], {
			encoding: "utf8",
			env: {
				...process.env,
				PATH: `${bin}:${process.env.PATH}`,
				HOME: join(sandbox, "caller-home"),
				XDG_CONFIG_HOME: poisonXdg,
				XDG_DATA_HOME: join(sandbox, "poison-data"),
				XDG_STATE_HOME: join(sandbox, "poison-state"),
				XDG_CACHE_HOME: join(sandbox, "poison-cache"),
				OPENCODE_CONFIG: join(poisonXdg, "opencode/opencode.json"),
				OPENCODE_CONFIG_DIR: join(poisonXdg, "opencode"),
				OPENCODE_CONFIG_CONTENT: '{"plugin":[]}',
				CCL_SKILLS_REPO: join(sandbox, "nonexistent-override-repo"),
				CLAUDE_CONFIG_DIR: join(sandbox, "poison-claude"),
				CLAUDE_CODE_PLUGIN_ROOT: join(sandbox, "poison-plugin-root"),
				ANTIGRAVITY_GEMINI_DIR: join(sandbox, "poison-agy-gemini"),
				ANTIGRAVITY_CONFIG_REL_DIR: "poison-agy-config",
				ANTIGRAVITY_APP_DATA_DIR: join(sandbox, "poison-agy-appdata"),
				AGY_ACCOUNT: "poison@example.invalid",
				GIT_DIR: join(sandbox, "poison-git-dir"),
				GIT_WORK_TREE: join(sandbox, "poison-work-tree"),
				GIT_EXEC_PATH: join(sandbox, "poison-git-exec"),
				GIT_SSH_COMMAND: "false",
				GIT_ASKPASS: "false",
				GIT_TRACE: join(sandbox, "poison-git-trace.log"),
				GIT_CONFIG_COUNT: "1",
				GIT_CONFIG_KEY_0: "core.sshCommand",
				GIT_CONFIG_VALUE_0: "false",
				CI: "true",
				CONTINUOUS_INTEGRATION: "1",
				GITHUB_ACTIONS: "true",
				GITHUB_REF: "refs/heads/main",
				GITHUB_REF_NAME: "main",
				GITHUB_SHA: "f".repeat(40),
				GITLAB_CI: "true",
				CI_COMMIT_REF_NAME: "main",
				CI_COMMIT_SHA: "e".repeat(40),
				EXPECT_SOURCE_COMMIT: "d".repeat(40),
				REQUIRE_CLEAN_RELEASE: "1",
				SMOKE_AGY_CALL_LOG: agyLog,
				SMOKE_PACK_RELEASE_LOG: packReleaseLog,
				SMOKE_ENV_AUDIT_LOG: envAuditLog,
				SMOKE_DUBIOUS_OWNERSHIP_REPO: repo,
			},
		});
		assert.equal(res.status, 0, `stdout:\n${res.stdout}\nstderr:\n${res.stderr}`);
		const lines = res.stdout.trim().split("\n");
		const summary = JSON.parse(lines.at(-1));
		assert.equal(summary.status, "four-host-smoke-passed");
		assert.equal(summary.antigravityPlugin, "native-plugin-registered");
		assert.equal(existsSync(agyLog), true, "agy must be exercised by host-smoke.sh");
		const agyCalls = readFileSync(agyLog, "utf8");
		assert.match(agyCalls, /^plugin install /m);
		assert.match(agyCalls, /^plugin uninstall ccl-skills$/m);
		const packedReleases = readFileSync(packReleaseLog, "utf8")
			.trim()
			.split("\n")
			.map((line) => JSON.parse(line));
		assert.deepEqual(packedReleases, [
			{ version: "1.0.0", sourceCommit: `${"0".repeat(39)}1`, sourceState: "clean" },
			{ version: "2.0.0", sourceCommit: `${"0".repeat(39)}2`, sourceState: "clean" },
		]);
		const envAudits = readFileSync(envAuditLog, "utf8")
			.trim()
			.split("\n")
			.map((line) => JSON.parse(line));
		assert.equal(envAudits.length > 0, true);
		for (const audit of envAudits) {
			assert.deepEqual(audit.leakedReleaseEnv, []);
			assert.deepEqual(audit.leakedAgyEnv, []);
		}
		assert.equal(existsSync(join(sandbox, "caller-home")), false, "caller HOME must stay untouched");
		assert.equal(existsSync(join(sandbox, "poison-agy-gemini")), false, "caller ANTIGRAVITY_GEMINI_DIR must stay untouched");

		// Stale post-uninstall plugin list entry must fail closed (not be ignored by `! grep -q` under `set -e`)
		const staleListRes = spawnSync("bash", [smokeScript], {
			encoding: "utf8",
			env: {
				...process.env,
				PATH: `${bin}:${process.env.PATH}`,
				HOME: join(sandbox, "caller-home-stale"),
				SMOKE_STALE_POST_UNINSTALL_LIST: "1",
			},
		});
		assert.notEqual(staleListRes.status, 0, "stale post-uninstall plugin list must fail host-smoke.sh");
		assert.match(staleListRes.stderr, /antigravity plugin still listed after uninstall/);

		// Unstaged deletion of a tracked source file must fail closed with an explicit message
		rmSync(join(repo, "skills/code-review/SKILL.md"));
		const missingRes = spawnSync("bash", [smokeScript], {
			encoding: "utf8",
			env: {
				...process.env,
				PATH: `${bin}:${process.env.PATH}`,
				HOME: join(sandbox, "caller-home-2"),
			},
		});
		assert.notEqual(missingRes.status, 0);
		assert.match(missingRes.stderr, /tracked source entry missing from working tree: skills\/code-review\/SKILL\.md/);
	} finally {
		rmSync(sandbox, { recursive: true, force: true });
	}
});
