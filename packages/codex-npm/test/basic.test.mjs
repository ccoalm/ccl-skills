import test from "node:test";
import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { mkdtempSync, mkdirSync, symlinkSync, writeFileSync } from "node:fs";
import { join } from "node:path";
import { pathToFileURL } from "node:url";
import { tmpdir } from "node:os";
import { isDirectEntrypoint } from "../dist/cli.js";
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
test("update of absent install is refused", () => {
	const p = spawnSync(process.execPath, ["dist/cli.js", "update", "--json"], {
		env: env(),
		encoding: "utf8",
	});
	assert.equal(p.status, 3);
	assert.equal(JSON.parse(p.stdout).status, "not-installed");
});
test("old host rejected", () => {
	const p = spawnSync(process.execPath, ["dist/cli.js", "doctor", "--json"], {
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
