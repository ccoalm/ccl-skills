import test from "node:test";
import assert from "node:assert/strict";
import {
	cpSync,
	existsSync,
	mkdtempSync,
	mkdirSync,
	readFileSync,
	writeFileSync,
} from "node:fs";
import { join } from "node:path";
import { tmpdir } from "node:os";
import { spawnSync } from "node:child_process";
test("packed verifier passes and rejects mutation", () => {
	let p = spawnSync(
		process.execPath,
		["scripts/verify-packed.mjs", "dist/assets"],
		{ encoding: "utf8" },
	);
	assert.equal(p.status, 0, p.stderr);
	const t = mkdtempSync(join(tmpdir(), "packed-mutation-"));
	cpSync("dist/assets", t, { recursive: true });
	writeFileSync(
		join(t, "marketplace/plugins/ccl-skills/agent-context/session-start.md"),
		"mutated",
	);
	p = spawnSync(process.execPath, ["scripts/verify-packed.mjs", t], {
		encoding: "utf8",
	});
	assert.notEqual(p.status, 0);
	assert.match(p.stderr, /mismatch/);
});
test("distribution includes CLI worker", () =>
	assert.equal(existsSync("dist/cli-worker.js"), true));
test("actual tgz CLI executes through macOS tmp alias", () => {
	if (!existsSync("artifacts/pack-metadata.json")) {
		const packed = spawnSync(
			process.execPath,
			["scripts/pack-artifact.mjs", "artifacts"],
			{ encoding: "utf8" },
		);
		assert.equal(packed.status, 0, packed.stderr);
	}
	const metadata = JSON.parse(
			readFileSync("artifacts/pack-metadata.json", "utf8"),
		),
		t = mkdtempSync(join(tmpdir(), "codex-tgz-cli-")),
		prefix = join(t, "user-prefix"),
		hostBin = join(t, "host-bin"),
		home = join(t, "home");
	mkdirSync(prefix);
	mkdirSync(hostBin);
	mkdirSync(join(home, ".codex"), { recursive: true });
	writeFileSync(
		join(hostBin, "codex"),
		"#!/bin/sh\n[ \"$1\" = --version ] && { echo 'codex-cli 0.133.0'; exit 0; }\nexit 0\n",
		{ mode: 0o755 },
	);
	let p = spawnSync(
		"npm",
		[
			"install",
			"--global",
			"--prefix",
			prefix,
			"--cache",
			join(t, "npm-cache"),
			"--userconfig",
			join(home, ".npmrc"),
			"--ignore-scripts",
			"--no-audit",
			"--no-fund",
			join(process.cwd(), "artifacts", metadata.filename),
		],
		{
			cwd: t,
			encoding: "utf8",
			env: {
				...process.env,
				HOME: home,
			},
		},
	);
	assert.equal(p.status, 0, p.stderr);
	const canonical = join(
			prefix,
			"bin/ccl-skills-codex",
		),
		cli =
			process.platform === "darwin" && canonical.startsWith("/private/var/")
				? canonical.slice(8)
				: canonical,
		env = {
			...process.env,
			HOME: home,
			CODEX_HOME: join(home, ".codex"),
			PATH: `${hostBin}:${prefix}/bin:${process.env.PATH}`,
		};
	p = spawnSync(cli, ["--version"], {
		env,
		encoding: "utf8",
	});
	assert.equal(p.status, 0, p.stderr);
	assert.equal(p.stdout.trim(), metadata.version);
	p = spawnSync(cli, ["install", "--json"], {
		env,
		encoding: "utf8",
	});
	assert.notEqual(p.stdout, "", p.stderr);
	const result = JSON.parse(p.stdout);
	assert.equal(result.code, p.status);
	assert.equal(typeof result.status, "string");
});
