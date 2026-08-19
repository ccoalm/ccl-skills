import test from "node:test";
import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { existsSync, mkdtempSync, mkdirSync, readFileSync, symlinkSync, writeFileSync } from "node:fs";
import { join } from "node:path";
import { pathToFileURL } from "node:url";
import { tmpdir } from "node:os";
import { isDirectEntrypoint, parseArgs } from "../dist/cli.js";
function env(version = "codex-cli 0.133.0") {
	const t = mkdtempSync(join(tmpdir(), "codex-npm-")),
		bin = join(t, "bin");
	mkdirSync(bin);
	writeFileSync(
		join(bin, "codex"),
		`#!/bin/sh\n[ "$1" = --version ] && { echo '${version}'; exit 0; }\nexit 0\n`,
		{ mode: 0o755 },
	);
	return {
		...process.env,
		HOME: join(t, "home"),
		CODEX_HOME: join(t, "home/.codex"),
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
test("old host rejected", () => {
	const p = spawnSync(process.execPath, ["dist/cli.js", "doctor", "--host", "codex", "--json"], {
		env: env("codex-cli 0.132.9"),
		encoding: "utf8",
	});
	assert.equal(p.status, 4);
});
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
