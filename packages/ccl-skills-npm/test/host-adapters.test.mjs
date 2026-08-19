import test from "node:test";
import assert from "node:assert/strict";
import {
	cpSync,
	copyFileSync,
	existsSync,
	mkdtempSync,
	mkdirSync,
	readFileSync,
	readdirSync,
	rmSync,
	symlinkSync,
	writeFileSync,
} from "node:fs";
import { join, resolve } from "node:path";
import { tmpdir } from "node:os";
import { spawnSync } from "node:child_process";
import { createHash } from "node:crypto";
import { runClaude } from "../dist/claude-adapter.js";
import { runOpenCode } from "../dist/opencode-adapter.js";
import { runHostSequence } from "../dist/unified.js";
import { fixture as codexFixture } from "./helpers.mjs";

const assets = resolve("dist/assets");

function listFiles(root, prefix = "") {
	return readdirSync(root, { withFileTypes: true }).flatMap((entry) => {
		const relative = prefix ? `${prefix}/${entry.name}` : entry.name;
		return entry.isDirectory() ? listFiles(join(root, entry.name), relative) : [relative];
	}).sort();
}

function fixture() {
	const root = mkdtempSync(join(tmpdir(), "ccl-unified-host-"));
	const home = join(root, "home"), bin = join(root, "bin"), state = join(root, "state");
	mkdirSync(home);
	mkdirSync(bin);
	mkdirSync(state);
	writeFileSync(join(bin, "opencode"), "#!/bin/sh\n[ \"$1\" = --version ] && { echo '1.0.0'; exit 0; }\nexit 0\n", { mode: 0o755 });
	writeFileSync(join(bin, "claude"), `#!/bin/sh
set -eu
state="$FAKE_STATE"
if [ "$1" = --version ]; then echo '2.1.233'; exit 0; fi
if [ "\${FAIL_MUTATION:-0}" = 1 ]; then
  case "$1 $2 $3" in
    'plugin uninstall '*|'plugin install '*|'plugin marketplace add'|'plugin marketplace remove') exit 9 ;;
  esac
fi
if [ "$1 $2 $3" = 'plugin marketplace list' ]; then
  if [ -f "$state/market" ]; then printf '[{"name":"ccl-skills-npm","source":"directory","path":"%s","installLocation":"%s"}]\\n' "$(cat "$state/market")" "$(cat "$state/market")"; else echo '[]'; fi
  exit 0
fi
if [ "$1 $2 $3" = 'plugin marketplace add' ]; then printf '%s' "$4" > "$state/market"; exit 0; fi
if [ "$1 $2 $3" = 'plugin marketplace remove' ]; then rm -f "$state/market"; exit 0; fi
if [ "$1 $2" = 'plugin list' ]; then
  if [ -f "$state/plugin" ]; then echo '[{"id":"ccl-skills@ccl-skills-npm","scope":"user","enabled":true}]'; else echo '[]'; fi
  exit 0
fi
if [ "$1 $2" = 'plugin install' ]; then : > "$state/plugin"; exit 0; fi
if [ "$1 $2" = 'plugin uninstall' ]; then rm -f "$state/plugin"; exit 0; fi
exit 2
`, { mode: 0o755 });
	return {
		root,
		home,
		state,
		env: { ...process.env, HOME: home, PATH: `${bin}:${process.env.PATH}`, FAKE_STATE: state },
	};
}

test("Claude local marketplace lifecycle is self-contained", () => {
	const f = fixture(), context = { home: f.home, assets, env: f.env };
	let result = runClaude("install", {}, context);
	assert.equal(result.status, "installed", result.message);
	const market = readFileSync(join(f.state, "market"), "utf8");
	assert.match(market, new RegExp(`^${f.home.replace(/[.*+?^${}()|[\]\\]/g, "\\$&")}`));
	assert.equal(existsSync(join(f.state, "plugin")), true);
	result = runClaude("doctor", {}, context);
	assert.equal(result.status, "healthy");
	result = runClaude("uninstall", {}, context);
	assert.equal(result.status, "dry-run");
	assert.equal(existsSync(join(f.state, "plugin")), true);
	result = runClaude("uninstall", { yes: true }, context);
	assert.equal(result.status, "uninstalled", result.message);
	assert.equal(existsSync(join(f.state, "plugin")), false);
});

test("Claude accepts the canonical macOS private-path alias", {
	skip: process.platform !== "darwin",
}, () => {
	const f = fixture(), context = { home: f.home, assets, env: f.env };
	assert.equal(runClaude("install", {}, context).status, "installed");
	const market = readFileSync(join(f.state, "market"), "utf8"), alias = market.startsWith("/private/var/") ? market.slice(8) : `/private${market}`;
	writeFileSync(join(f.state, "market"), alias);
	assert.equal(runClaude("doctor", {}, context).status, "healthy");
});

test("Claude retains only active and previous npm snapshots", () => {
	const f = fixture();
	function versionedAssets(version) {
		const target = join(f.root, `assets-${version}`);
		cpSync(assets, target, { recursive: true });
		const releasePath = join(target, "release.json"), release = JSON.parse(readFileSync(releasePath, "utf8"));
		release.version = version;
		release.snapshotHash = createHash("sha256").update(JSON.stringify({ version, files: release.files })).digest("hex");
		writeFileSync(releasePath, `${JSON.stringify(release, null, 2)}\n`);
		return target;
	}
	const v1 = versionedAssets("1.0.0"), v2 = versionedAssets("2.0.0"), v3 = versionedAssets("3.0.0");
	assert.equal(runClaude("install", {}, { home: f.home, assets: v1, env: f.env }).status, "installed");
	assert.equal(runClaude("update", { yes: true }, { home: f.home, assets: v2, env: f.env }).status, "updated");
	assert.equal(runClaude("update", { yes: true }, { home: f.home, assets: v3, env: f.env }).status, "updated");
	const snapshots = join(f.home, ".claude/ccl-skills-npm/snapshots");
	assert.equal(readdirSync(snapshots, { withFileTypes: true }).filter((entry) => entry.isDirectory()).length, 2);
});

test("Claude refuses an unowned npm marketplace before mutation", () => {
	const f = fixture(), foreign = join(f.root, "foreign-marketplace");
	writeFileSync(join(f.state, "market"), foreign);
	const result = runClaude("install", {}, { home: f.home, assets, env: f.env });
	assert.equal(result.status, "unowned-registration");
	assert.equal(readFileSync(join(f.state, "market"), "utf8"), foreign);
	assert.equal(existsSync(join(f.state, "plugin")), false);
});

test("Claude refuses a symlinked snapshots directory before mutation", () => {
	const f = fixture(), outside = join(f.root, "outside"), managed = join(f.home, ".claude/ccl-skills-npm");
	mkdirSync(outside);
	mkdirSync(managed, { recursive: true });
	symlinkSync(outside, join(managed, "snapshots"));
	const result = runClaude("install", {}, { home: f.home, assets, env: f.env });
	assert.equal(result.status, "safety-refusal");
	assert.deepEqual(readdirSync(outside), []);
	assert.equal(existsSync(join(f.state, "plugin")), false);
});

test("Claude reports a missing CLI as host-missing", () => {
	const f = fixture(), emptyBin = join(f.root, "empty-bin");
	mkdirSync(emptyBin);
	const result = runClaude("install", {}, { home: f.home, assets, env: { ...f.env, PATH: emptyBin } });
	assert.equal(result.code, 4);
	assert.equal(result.status, "host-missing");
});

test("OpenCode installs bundled skills and preserves shared files on uninstall", () => {
	const f = fixture(), context = { home: f.home, assets, env: f.env };
	let result = runOpenCode("install", {}, context);
	assert.equal(result.status, "installed", result.message);
	const skills = join(f.home, ".config/opencode/skills");
	const bundledSkills = join(assets, "marketplace/plugins/ccl-skills/skills"),
		expectedSkillCount = readdirSync(bundledSkills, { withFileTypes: true })
			.filter((entry) => entry.isDirectory() && existsSync(join(bundledSkills, entry.name, "SKILL.md"))).length;
	assert.equal(readdirSync(skills, { withFileTypes: true }).filter((entry) => entry.isDirectory()).length, expectedSkillCount);
	const sample = join(skills, "product-rd-workflow/SKILL.md");
	assert.equal(readFileSync(sample, "utf8"), readFileSync(join(assets, "marketplace/plugins/ccl-skills/skills/product-rd-workflow/SKILL.md"), "utf8"));
	const runtime = join(f.home, ".config/opencode/ccl-skills/runtime");
	const pluginAssets = join(assets, "marketplace/plugins/ccl-skills");
	const expectedRuntimeFiles = [
		"hooks/hooks.json",
		...readdirSync(join(pluginAssets, "hooks"), { withFileTypes: true })
			.filter((entry) => entry.isFile() && entry.name.endsWith(".sh") && !entry.name.startsWith("test_"))
			.map((entry) => `hooks/${entry.name}`),
		"scripts/owner-dispatch/owner-dispatch.sh",
		"agent-context/session-start.md",
		"agent-context/subagent-start.md",
	].sort();
	assert.deepEqual(listFiles(runtime), expectedRuntimeFiles, "OpenCode runtime closure must be exact");
	for (const path of expectedRuntimeFiles) {
		assert.equal(
			readFileSync(join(runtime, path), "utf8"),
			readFileSync(join(pluginAssets, path), "utf8"),
			`OpenCode runtime asset drifted: ${path}`,
		);
	}
	result = runOpenCode("uninstall", { yes: true }, context);
	assert.equal(result.status, "uninstalled-shared-retained", result.message);
	assert.equal(existsSync(sample), true);
	assert.equal(existsSync(join(runtime, "hooks/hooks.json")), true);
	assert.equal(existsSync(join(f.home, ".config/opencode/ccl-skills-npm")), false);
});

test("OpenCode refuses symlinked shared parents before writing outside its base", () => {
	const f = fixture(), base = join(f.home, ".config/opencode"), outside = join(f.root, "outside");
	mkdirSync(base, { recursive: true });
	mkdirSync(outside);
	symlinkSync(outside, join(base, "skills"));
	const result = runOpenCode("install", {}, { home: f.home, assets, env: f.env });
	assert.equal(result.code, 3);
	assert.equal(result.status, "collision");
	assert.deepEqual(readdirSync(outside), []);
	assert.equal(existsSync(join(base, "plugins/ccl-skills.ts")), false);
});

test("Claude and OpenCode fail closed when HOME is unavailable", () => {
	const f = fixture(), env = { PATH: f.env.PATH, FAKE_STATE: f.state };
	for (const result of [
		runClaude("install", {}, { assets, env }),
		runOpenCode("install", {}, { assets, env }),
	]) {
		assert.equal(result.code, 3);
		assert.equal(result.status, "safety-refusal");
		assert.match(result.message, /HOME is not set/);
	}
});

test("Claude and OpenCode honor interruption before public mutation", () => {
	for (const run of [runClaude, runOpenCode]) {
		const f = fixture(), result = run("install", {}, {
			home: f.home,
			assets,
			env: f.env,
			isInterrupted: () => true,
		});
		assert.equal(result.code, 130, result.message);
		assert.equal(result.interrupted, true);
		assert.equal(existsSync(join(f.state, "plugin")), false);
		assert.equal(existsSync(join(f.home, ".config/opencode/plugins/ccl-skills.ts")), false);
	}
});

test("Claude rolls back when interrupted after registration but before its manifest commit", () => {
	const f = fixture();
	let checks = 0;
	const result = runClaude("install", {}, {
		home: f.home,
		assets,
		env: f.env,
		isInterrupted: () => ++checks === 3,
	});
	assert.equal(result.code, 130, result.message);
	assert.equal(result.interrupted, true);
	assert.equal(existsSync(join(f.state, "plugin")), false);
	assert.equal(existsSync(join(f.state, "market")), false);
	assert.equal(existsSync(join(f.home, ".claude/ccl-skills-npm/install-manifest.json")), false);
});

test("Claude interruption before update mutation never enters rollback", () => {
	const f = fixture(), nextAssets = join(f.root, "claude-next-assets");
	cpSync(assets, nextAssets, { recursive: true });
	const releasePath = join(nextAssets, "release.json"), release = JSON.parse(readFileSync(releasePath, "utf8"));
	release.version = "2.0.0";
	release.snapshotHash = createHash("sha256").update(JSON.stringify({ version: release.version, files: release.files })).digest("hex");
	writeFileSync(releasePath, `${JSON.stringify(release, null, 2)}\n`);
	assert.equal(runClaude("install", {}, { home: f.home, assets, env: f.env }).status, "installed");
	const result = runClaude("update", { yes: true }, {
		home: f.home,
		assets: nextAssets,
		env: { ...f.env, FAIL_MUTATION: "1" },
		isInterrupted: () => true,
	});
	assert.equal(result.code, 130, result.message);
	assert.equal(result.status, "interrupted");
	assert.equal(existsSync(join(f.state, "plugin")), true);
});

test("OpenCode rolls back shared writes when interruption arrives mid-copy", () => {
	const f = fixture();
	let checks = 0;
	const result = runOpenCode("install", {}, {
		home: f.home,
		assets,
		env: f.env,
		isInterrupted: () => ++checks === 2,
	});
	assert.equal(result.code, 130, result.message);
	assert.equal(result.interrupted, true);
	assert.equal(existsSync(join(f.home, ".config/opencode/plugins/ccl-skills.ts")), false);
	assert.equal(existsSync(join(f.home, ".config/opencode/ccl-skills-npm/install-manifest.json")), false);
	const retry = runOpenCode("install", {}, { home: f.home, assets, env: f.env });
	assert.equal(retry.status, "installed", retry.message);
});

test("OpenCode removes a failed per-file temp and permits an immediate retry", () => {
	const f = fixture(), context = {
		home: f.home,
		assets,
		env: f.env,
		copyShared(from, to) {
			copyFileSync(from, to);
			throw new Error("injected temp-file failure");
		},
	};
	const failed = runOpenCode("install", {}, context);
	assert.equal(failed.code, 5);
	const retry = runOpenCode("install", {}, { home: f.home, assets, env: f.env });
	assert.equal(retry.status, "installed", retry.message);
});

test("OpenCode update removes dropped owned files and superseded snapshots", () => {
	const f = fixture(), override = join(f.root, "checkout"), synthetic = join(override, "skills/synthetic/SKILL.md");
	cpSync(join(assets, "marketplace/plugins/ccl-skills"), override, { recursive: true });
	mkdirSync(join(override, "skills/synthetic"), { recursive: true });
	writeFileSync(synthetic, "first\n");
	const context = { home: f.home, assets, env: { ...f.env, CCL_SKILLS_REPO: override } };
	assert.equal(runOpenCode("install", {}, context).status, "installed");
	const installed = join(f.home, ".config/opencode/skills/synthetic/SKILL.md");
	assert.equal(existsSync(installed), true);
	rmSync(synthetic);
	let result = runOpenCode("update", { yes: true }, context);
	assert.equal(result.status, "updated", result.message);
	assert.equal(existsSync(installed), false);
	writeFileSync(join(override, "skills/product-rd-workflow/SKILL.md"), "third snapshot\n");
	result = runOpenCode("update", { yes: true }, context);
	assert.equal(result.status, "updated", result.message);
	const snapshots = join(f.home, ".config/opencode/ccl-skills-npm/snapshots");
	assert.equal(readdirSync(snapshots, { withFileTypes: true }).filter((entry) => entry.isDirectory()).length, 1);
});

test("OpenCode version-only update keeps the shared active snapshot", () => {
	const f = fixture(), nextAssets = join(f.root, "version-only-assets");
	cpSync(assets, nextAssets, { recursive: true });
	const releasePath = join(nextAssets, "release.json"), release = JSON.parse(readFileSync(releasePath, "utf8"));
	release.version = "2.0.0";
	release.snapshotHash = createHash("sha256").update(JSON.stringify({ version: release.version, files: release.files })).digest("hex");
	writeFileSync(releasePath, `${JSON.stringify(release, null, 2)}\n`);
	const base = { home: f.home, env: f.env };
	assert.equal(runOpenCode("install", {}, { ...base, assets }).status, "installed");
	const result = runOpenCode("update", { yes: true }, { ...base, assets: nextAssets });
	assert.equal(result.status, "updated", result.message);
	assert.equal(runOpenCode("doctor", {}, { ...base, assets: nextAssets }).status, "healthy");
});

test("Claude reports cleanup failure after registration removal as partial", () => {
	const f = fixture(), context = {
		home: f.home,
		assets,
		env: f.env,
		removeRoot: () => { throw new Error("injected cleanup failure"); },
	};
	assert.equal(runClaude("install", {}, context).status, "installed");
	const result = runClaude("uninstall", { yes: true }, context);
	assert.equal(result.code, 5);
	assert.equal(result.status, "partial");
	assert.equal(existsSync(join(f.state, "plugin")), false);
});

test("Claude retains ownership evidence when its CLI is unavailable during uninstall", () => {
	const f = fixture(), context = { home: f.home, assets, env: f.env }, emptyBin = join(f.root, "empty-bin");
	assert.equal(runClaude("install", {}, context).status, "installed");
	mkdirSync(emptyBin);
	const result = runClaude("uninstall", { yes: true }, { ...context, env: { ...f.env, PATH: emptyBin } });
	assert.equal(result.code, 4);
	assert.equal(result.status, "host-missing");
	assert.equal(existsSync(join(f.home, ".claude/ccl-skills-npm/install-manifest.json")), true);
	assert.equal(existsSync(join(f.state, "plugin")), true);
});

test("OpenCode reports exclusive metadata cleanup failure as partial", () => {
	const f = fixture(), context = {
		home: f.home,
		assets,
		env: f.env,
		removeRoot: () => { throw new Error("injected cleanup failure"); },
	};
	assert.equal(runOpenCode("install", {}, context).status, "installed");
	const result = runOpenCode("uninstall", { yes: true }, context);
	assert.equal(result.code, 5);
	assert.equal(result.status, "partial");
});

test("multi-host execution stops on partial and preserves the strongest exit code", () => {
	const called = [], result = runHostSequence(["claude", "codex", "opencode"], (host) => {
		called.push(host);
		if (host === "claude") return { code: 3, status: "safety-refusal", message: "no mutation" };
		if (host === "codex") return { code: 5, status: "partial", message: "unknown finality" };
		return { code: 0, status: "installed", message: "must not run" };
	});
	assert.deepEqual(called, ["claude", "codex"]);
	assert.equal(result.code, 5);
	assert.equal(result.status, "multi-host-partial");
});

test("OpenCode collision and invalid override fail before writes", () => {
	const f = fixture(), skills = join(f.home, ".config/opencode/skills");
	mkdirSync(join(skills, "product-rd-workflow"), { recursive: true });
	writeFileSync(join(skills, "product-rd-workflow/SKILL.md"), "custom\n");
	let result = runOpenCode("install", {}, { home: f.home, assets, env: f.env });
	assert.equal(result.status, "collision");
	assert.equal(readFileSync(join(skills, "product-rd-workflow/SKILL.md"), "utf8"), "custom\n");
	assert.equal(existsSync(join(f.home, ".config/opencode/plugins/ccl-skills.ts")), false);

	const g = fixture(), missing = join(g.root, "missing");
	result = runOpenCode("install", {}, { home: g.home, assets, env: { ...g.env, CCL_SKILLS_REPO: missing } });
	assert.equal(result.status, "invalid-source-override");
	assert.equal(existsSync(join(g.home, ".config/opencode")), false);
});

test("production CLI honors an invalid CCL_SKILLS_REPO override before writes", () => {
	const f = fixture(), missing = join(f.root, "missing");
	const result = spawnSync(process.execPath, ["dist/cli.js", "install", "--host", "opencode", "--json"], {
		encoding: "utf8",
		env: { ...f.env, CCL_SKILLS_REPO: missing },
	});
	assert.equal(result.status, 3, result.stderr);
	assert.equal(JSON.parse(result.stdout).status, "invalid-source-override");
	assert.equal(existsSync(join(f.home, ".config/opencode")), false);
});

test("OpenCode update preview runs ownership preflight before package self-update", () => {
	const f = fixture(), nextAssets = join(f.root, "preflight-next-assets"), context = { home: f.home, assets, env: f.env };
	assert.equal(runOpenCode("install", {}, context).status, "installed");
	cpSync(assets, nextAssets, { recursive: true });
	const releasePath = join(nextAssets, "release.json"), release = JSON.parse(readFileSync(releasePath, "utf8"));
	release.version = "2.0.0";
	release.snapshotHash = createHash("sha256").update(JSON.stringify({ version: release.version, files: release.files })).digest("hex");
	writeFileSync(releasePath, `${JSON.stringify(release, null, 2)}\n`);
	writeFileSync(join(f.home, ".config/opencode/skills/product-rd-workflow/SKILL.md"), "user change\n");
	const result = runOpenCode("update", {}, { ...context, assets: nextAssets });
	assert.equal(result.code, 3);
	assert.equal(result.status, "collision");
});

test("OpenCode honors a valid source override and rejects a tampered manifest", () => {
	const f = fixture(), override = join(f.root, "checkout");
	cpSync(join(assets, "marketplace/plugins/ccl-skills"), override, { recursive: true });
	writeFileSync(join(override, "skills/product-rd-workflow/SKILL.md"), "override-source\n");
	const context = { home: f.home, assets, env: { ...f.env, CCL_SKILLS_REPO: override } };
	let result = runOpenCode("install", {}, context);
	assert.equal(result.status, "installed", result.message);
	assert.equal(readFileSync(join(f.home, ".config/opencode/skills/product-rd-workflow/SKILL.md"), "utf8"), "override-source\n");
	const manifestPath = join(f.home, ".config/opencode/ccl-skills-npm/install-manifest.json"), manifest = JSON.parse(readFileSync(manifestPath, "utf8"));
	manifest.snapshot = "../../escape";
	writeFileSync(manifestPath, JSON.stringify(manifest));
	result = runOpenCode("uninstall", { yes: true }, context);
	assert.equal(result.status, "safety-refusal");
	assert.equal(existsSync(join(f.home, ".config/opencode/skills/product-rd-workflow/SKILL.md")), true);
	assert.equal(existsSync(join(f.home, ".config/opencode/ccl-skills-npm")), true);
});

test("doctor reports legacy plus npm installs as double-install", () => {
	const f = fixture(), context = { home: f.home, assets, env: f.env };
	assert.equal(runOpenCode("install", {}, context).status, "installed");
	mkdirSync(join(f.home, ".config/opencode/ccl-skills"), { recursive: true });
	writeFileSync(join(f.home, ".config/opencode/ccl-skills/install-manifest.json"), "{}\n");
	assert.equal(runOpenCode("doctor", {}, context).status, "double-install");
});

test("default CLI selects every detected host", () => {
	const f = fixture(), result = spawnSync(process.execPath, ["dist/cli.js", "install", "--json"], {
		encoding: "utf8",
		env: { ...f.env, PATH: `${join(f.root, "bin")}:/bin:/usr/bin` },
	});
	assert.equal(result.status, 0, result.stderr);
	const output = JSON.parse(result.stdout);
	assert.equal(output.status, "multi-host-complete");
	assert.equal(existsSync(join(f.state, "plugin")), true);
	assert.equal(existsSync(join(f.home, ".config/opencode/plugins/ccl-skills.ts")), true);
});

test("default update selects owned hosts and ignores available unowned hosts", () => {
	const f = fixture(), context = { home: f.home, assets, env: f.env };
	assert.equal(runOpenCode("install", {}, context).status, "installed");
	const result = spawnSync(process.execPath, ["dist/cli.js", "update", "--json"], {
		encoding: "utf8",
		env: { ...f.env, PATH: `${join(f.root, "bin")}:/bin:/usr/bin` },
	});
	assert.equal(result.status, 0, result.stderr);
	const output = JSON.parse(result.stdout);
	assert.equal(output.status, "healthy");
	assert.match(output.message, /^OpenCode uses/);
});

test("self-update failure after npm mutation discloses the global package change", () => {
	const f = fixture(), context = { home: f.home, assets, env: f.env }, bin = join(f.root, "bin");
	assert.equal(runOpenCode("install", {}, context).status, "installed");
	writeFileSync(join(bin, "npm"), "#!/bin/sh\nexit 0\n", { mode: 0o755 });
	writeFileSync(join(bin, "ccl-skills"), "#!/bin/sh\necho '{\"code\":3,\"status\":\"collision\",\"message\":\"owned drift\"}'\nexit 3\n", { mode: 0o755 });
	const result = spawnSync(process.execPath, ["dist/cli.js", "update", "--host", "opencode", "--yes", "--json"], {
		encoding: "utf8",
		env: f.env,
	});
	assert.equal(result.status, 3, result.stderr);
	const output = JSON.parse(result.stdout);
	assert.equal(output.status, "collision");
	assert.equal(output.details.globalPackageUpdated, true);
});

test("default uninstall processes an owned host even after its CLI disappears", () => {
	const f = fixture(), context = { home: f.home, assets, env: f.env };
	assert.equal(runOpenCode("install", {}, context).status, "installed");
	const result = spawnSync(process.execPath, ["dist/cli.js", "uninstall", "--yes", "--json"], {
		encoding: "utf8",
		env: { ...f.env, PATH: "/usr/bin:/bin" },
	});
	assert.equal(result.status, 0, result.stderr);
	assert.equal(JSON.parse(result.stdout).status, "uninstalled-shared-retained");
	assert.equal(existsSync(join(f.home, ".config/opencode/ccl-skills-npm")), false);
});

test("explicit Codex host has zero Claude and OpenCode side effects", () => {
	const f = codexFixture(), bin = join(f.root, "bin");
	writeFileSync(join(bin, "claude"), "#!/bin/sh\ntouch \"$FAKE_STATE.claude-called\"\nexit 0\n", { mode: 0o755 });
	writeFileSync(join(bin, "opencode"), "#!/bin/sh\ntouch \"$FAKE_STATE.opencode-called\"\nexit 0\n", { mode: 0o755 });
	const result = spawnSync(process.execPath, ["dist/cli.js", "install", "--host", "codex", "--json"], { encoding: "utf8", env: f.env });
	assert.notEqual(result.status, 5, result.stderr);
	assert.equal(existsSync(`${f.state}.claude-called`), false);
	assert.equal(existsSync(`${f.state}.opencode-called`), false);
	assert.equal(existsSync(join(f.home, ".config/opencode")), false);
});
