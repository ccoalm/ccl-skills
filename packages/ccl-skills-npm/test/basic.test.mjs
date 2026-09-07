import test from "node:test";
import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { existsSync, mkdtempSync, mkdirSync, readFileSync, symlinkSync, writeFileSync } from "node:fs";
import { join } from "node:path";
import { pathToFileURL } from "node:url";
import { tmpdir } from "node:os";
import { isDirectEntrypoint, parseArgs } from "../dist/cli.js";
function env(version = "codex-cli 0.133.0", versionExit = 0) {
	const t = mkdtempSync(join(tmpdir(), "codex-npm-")),
		bin = join(t, "bin");
	mkdirSync(bin);
	writeFileSync(
		join(bin, "codex"),
		`#!/bin/sh\nprintf '%s\\n' "$*" >> "$HOST_CALL_LOG"\n[ "$1" = --version ] && { echo '${version}'; exit ${versionExit}; }\nexit 0\n`,
		{ mode: 0o755 },
	);
	return {
		...process.env,
		HOME: join(t, "home"),
		CODEX_HOME: join(t, "home/.codex"),
		HOST_CALL_LOG: join(t, "calls"),
		PATH: `${bin}:${process.env.PATH}`,
	};
}
test("help and version", () => {
	for (const flag of ["--help", "--version"]) {
		const p = spawnSync(process.execPath, ["dist/cli.js", flag], {
			encoding: "utf8",
		});
		assert.equal(p.status, 0);
		assert.ok(p.stdout);
	}
});
test("unified CLI exposes all hosts and accepts one explicit host", () => {
	const help = spawnSync(process.execPath, ["dist/cli.js", "--help"], {
		encoding: "utf8",
	});
	assert.equal(help.status, 0);
	assert.match(help.stdout, /--host claude\|codex\|opencode/);
	const parsed = parseArgs(["install", "--host", "codex"]);
	assert.equal(parsed.direct, undefined);
	assert.equal(parsed.options?.host, "codex");
});
test("update of absent install is refused", () => {
	const p = spawnSync(process.execPath, ["dist/cli.js", "update", "--host", "codex", "--json"], {
		env: env(),
		encoding: "utf8",
	});
	assert.equal(p.status, 3);
	assert.equal(JSON.parse(p.stdout).status, "not-installed");
});
test("update --yes refuses an absent install before mutating global npm state", () => {
	const runtime = env(), bin = runtime.PATH.split(":")[0], log = join(runtime.HOME, "..", "npm-update");
	writeFileSync(join(bin, "npm"), "#!/bin/sh\nprintf '%s' \"$*\" > \"$FAKE_UPDATE_LOG\"\nexit 0\n", { mode: 0o755 });
	delete runtime.CCL_SKILLS_SKIP_SELF_UPDATE;
	const p = spawnSync(process.execPath, ["dist/cli.js", "update", "--host", "codex", "--yes", "--json"], {
		env: { ...runtime, FAKE_UPDATE_LOG: log }, encoding: "utf8",
	});
	assert.equal(p.status, 3, p.stderr);
	assert.equal(JSON.parse(p.stdout).status, "not-installed");
	assert.equal(existsSync(log), false);
});
test("allow-downgrade never self-installs latest first", () => {
	const runtime = env(), bin = runtime.PATH.split(":")[0], log = join(runtime.HOME, "..", "npm-update");
	writeFileSync(join(bin, "npm"), "#!/bin/sh\n: > \"$FAKE_UPDATE_LOG\"\nexit 0\n", { mode: 0o755 });
	const p = spawnSync(process.execPath, ["dist/cli.js", "update", "--host", "codex", "--yes", "--allow-downgrade", "--json"], {
		env: { ...runtime, FAKE_UPDATE_LOG: log }, encoding: "utf8",
	});
	assert.equal(p.status, 3, p.stderr);
	assert.equal(existsSync(log), false);
});
test("help discloses package self-update and assets-only escape hatch", () => {
	const p = spawnSync(process.execPath, ["dist/cli.js", "--help"], { encoding: "utf8" });
	assert.match(p.stdout, /npm package to @latest/);
	assert.match(p.stdout, /CCL_SKILLS_SKIP_SELF_UPDATE=1/);
});
for (const [version, versionExit] of [["codex-cli 0.132.9", 0], ["development-build", 0], ["", 2]]) {
	for (const selection of [["--host", "codex"], []]) {
		test(`capable Codex doctor ignores version ${JSON.stringify(version)} via ${selection.length ? "explicit" : "unified"} selection`, () => {
			const runtime = env(version, versionExit);
			runtime.PATH = runtime.PATH.split(":")[0];
			const p = spawnSync(process.execPath, ["dist/cli.js", "doctor", ...selection, "--json"], { env: runtime, encoding: "utf8" });
			assert.equal(p.status, 3, p.stdout || p.stderr);
			assert.equal(JSON.parse(p.stdout).status, "absent");
			const calls = readFileSync(runtime.HOST_CALL_LOG, "utf8");
			assert.match(calls, /^plugin marketplace list$/m);
			assert.match(calls, /^plugin list$/m);
			assert.doesNotMatch(calls, /--version|plugin (?:add|remove)|marketplace (?:add|remove)/);
		});
	}
}
for (const unsafePath of ["symlink home", "file home", "symlink ancestor", "file ancestor"]) {
	for (const selection of [["--host", "codex"], []]) {
		test(`unsafe Codex ${unsafePath} is refused before host queries via ${selection.length ? "explicit" : "unified"} selection`, () => {
			const runtime = env();
			runtime.PATH = runtime.PATH.split(":")[0];
			mkdirSync(runtime.HOME);
			const outside = join(runtime.HOME, "..", "outside"), sentinel = join(outside, "sentinel");
			mkdirSync(outside);
			writeFileSync(sentinel, "unchanged");
			if (unsafePath === "symlink home") symlinkSync(outside, runtime.CODEX_HOME);
			if (unsafePath === "file home") writeFileSync(runtime.CODEX_HOME, "not a directory");
			if (unsafePath.endsWith("ancestor")) {
				const ancestor = join(runtime.HOME, "ancestor");
				if (unsafePath === "symlink ancestor") symlinkSync(outside, ancestor);
				else writeFileSync(ancestor, "not a directory");
				runtime.CODEX_HOME = join(ancestor, "nested", ".codex");
			}
			const p = spawnSync(process.execPath, ["dist/cli.js", "doctor", ...selection, "--json"], { env: runtime, encoding: "utf8" });
			assert.equal(p.status, 3, p.stdout || p.stderr);
			assert.equal(JSON.parse(p.stdout).status, "safety-refusal");
			assert.equal(existsSync(runtime.HOST_CALL_LOG), false, "Codex must not query an unsafe home");
			assert.equal(readFileSync(sentinel, "utf8"), "unchanged");
		});
	}
}
test("direct entrypoint resolves real paths and symlinks safely", () => {
	const t = mkdtempSync(join(tmpdir(), "codex-entry-")),
		real = join(t, "cli.js"),
		link = join(t, "bin");
	writeFileSync(real, "");
	symlinkSync(real, link);
	assert.equal(isDirectEntrypoint(pathToFileURL(real).href, real), true);
	assert.equal(isDirectEntrypoint(pathToFileURL(real).href, link), true);
	assert.equal(
		isDirectEntrypoint(pathToFileURL(real).href, join(t, "missing")),
		false,
	);
	assert.equal(isDirectEntrypoint(pathToFileURL(real).href, undefined), false);
});
test("direct entrypoint accepts macOS /var alias", {
	skip: process.platform !== "darwin",
}, () => {
	const t = mkdtempSync(join(tmpdir(), "codex-entry-alias-")),
		real = join(t, "cli.js");
	writeFileSync(real, "");
	const alias = real.startsWith("/private/var/") ? real.slice(8) : real;
	assert.equal(isDirectEntrypoint(pathToFileURL(real).href, alias), true);
});
