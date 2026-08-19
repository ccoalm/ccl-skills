import test, { before } from "node:test";
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
before(() => {
	const packed = spawnSync(process.execPath, ["scripts/pack-artifact.mjs", "artifacts"], { encoding: "utf8" });
	assert.equal(packed.status, 0, packed.stderr);
});
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
test("packed verifier binds the executable JavaScript runtime", () => {
	const t = mkdtempSync(join(tmpdir(), "packed-runtime-mutation-"));
	cpSync("dist", t, { recursive: true });
	writeFileSync(join(t, "cli.js"), "\n// mutated\n", { flag: "a" });
	const p = spawnSync(process.execPath, ["scripts/verify-packed.mjs", join(t, "assets")], { encoding: "utf8" });
	assert.notEqual(p.status, 0);
	assert.match(p.stderr, /runtime.*mismatch/i);
});
test("generated artifacts are ignored by release cleanliness checks", () => {
	const p = spawnSync("git", ["check-ignore", "packages/ccl-skills-npm/artifacts/pack-metadata.json"], {
		cwd: "../..",
		encoding: "utf8",
	});
	assert.equal(p.status, 0, p.stderr);
});
test("distribution includes CLI worker", () =>
	assert.equal(existsSync("dist/cli-worker.js"), true));
test("distribution includes a local Claude marketplace", () => {
	const marketplace = JSON.parse(
		readFileSync("dist/assets/marketplace/.claude-plugin/marketplace.json", "utf8"),
	);
	assert.equal(marketplace.name, "ccl-skills-npm");
	assert.equal(marketplace.plugins?.[0]?.source, "./plugins/ccl-skills");
});
test("published tarball declares and carries Apache-2.0", () => {
	if (!existsSync("artifacts/pack-metadata.json")) {
		const packed = spawnSync(process.execPath, ["scripts/pack-artifact.mjs", "artifacts"], { encoding: "utf8" });
		assert.equal(packed.status, 0, packed.stderr);
	}
	const metadata = JSON.parse(readFileSync("artifacts/pack-metadata.json", "utf8")),
		artifact = join("artifacts", metadata.filename),
		packageJson = spawnSync("tar", ["-xOzf", artifact, "package/package.json"], { encoding: "utf8" }),
		license = spawnSync("tar", ["-xOzf", artifact, "package/LICENSE"], { encoding: "utf8" });
	assert.equal(packageJson.status, 0, packageJson.stderr);
	assert.equal(JSON.parse(packageJson.stdout).license, "Apache-2.0");
	assert.equal(license.status, 0, license.stderr);
	assert.equal(license.stdout, readFileSync("../../LICENSE", "utf8"));
});
test("artifact verifier binds metadata and the embedded release to the exact tgz", () => {
	if (!existsSync("artifacts/pack-metadata.json")) {
		const packed = spawnSync(process.execPath, ["scripts/pack-artifact.mjs", "artifacts"], { encoding: "utf8" });
		assert.equal(packed.status, 0, packed.stderr);
	}
	let verified = spawnSync(process.execPath, ["scripts/verify-artifact.mjs", "artifacts/pack-metadata.json"], { encoding: "utf8" });
	assert.equal(verified.status, 0, verified.stderr);
	verified = spawnSync(process.execPath, ["scripts/verify-artifact.mjs", "artifacts/pack-metadata.json"], {
		encoding: "utf8",
		env: { ...process.env, EXPECT_SOURCE_COMMIT: "0".repeat(40) },
	});
	assert.notEqual(verified.status, 0);
	assert.match(verified.stderr, /source commit mismatch/);
	const metadata = JSON.parse(readFileSync("artifacts/pack-metadata.json", "utf8")),
		t = mkdtempSync(join(tmpdir(), "artifact-integrity-"));
	cpSync("artifacts", t, { recursive: true });
	writeFileSync(join(t, metadata.filename), "tampered", { flag: "a" });
	verified = spawnSync(process.execPath, ["scripts/verify-artifact.mjs", join(t, "pack-metadata.json")], { encoding: "utf8" });
	assert.notEqual(verified.status, 0);
	assert.match(verified.stderr, /integrity mismatch/);
});
test("published tarball carries the plugin hooks in the verified snapshot", () => {
	if (!existsSync("artifacts/pack-metadata.json")) {
		const packed = spawnSync(process.execPath, ["scripts/pack-artifact.mjs", "artifacts"], { encoding: "utf8" });
		assert.equal(packed.status, 0, packed.stderr);
	}
	const metadata = JSON.parse(readFileSync("artifacts/pack-metadata.json", "utf8")),
		artifact = join("artifacts", metadata.filename),
		listing = spawnSync("tar", ["-tzf", artifact], { encoding: "utf8" }),
		release = JSON.parse(spawnSync("tar", ["-xOzf", artifact, "package/dist/assets/release.json"], { encoding: "utf8" }).stdout),
		releasePaths = new Set(release.files.map((entry) => entry.path));
	assert.equal(listing.status, 0, listing.stderr);
	for (const path of ["hooks/hooks.json", "hooks/session-start.sh", "hooks/guard-edit-isolation.sh", "agent-context/subagent-start.md"]) {
		const assetPath = `marketplace/plugins/ccl-skills/${path}`;
		assert.match(listing.stdout, new RegExp(`package/dist/assets/${assetPath.replace(/[.*+?^${}()|[\]\\]/g, "\\$&")}`));
		assert.equal(releasePaths.has(assetPath), true, `${assetPath} missing from release manifest`);
	}
});
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
		t = mkdtempSync(join(tmpdir(), "ccl-skills-tgz-cli-")),
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
		"bin/ccl-skills",
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
	p = spawnSync(cli, ["install", "--host", "codex", "--json"], {
		env,
		encoding: "utf8",
	});
	assert.notEqual(p.stdout, "", p.stderr);
	const result = JSON.parse(p.stdout);
	assert.equal(result.code, p.status);
	assert.equal(typeof result.status, "string");
});
