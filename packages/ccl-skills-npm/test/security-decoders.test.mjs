import test from "node:test";
import assert from "node:assert/strict";
import { mkdtempSync, mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { join } from "node:path";
import { tmpdir } from "node:os";
import { assertSafeRoot, canonicalAlias } from "../dist/fs-safe.js";
import { readManifest, readRelease } from "../dist/manifest.js";
import { cli, fixture } from "./helpers.mjs";

test("release decoder rejects malformed identity, duplicate, and traversal", () => {
	const dir = mkdtempSync(join(tmpdir(), "release-red-")),
		path = join(dir, "release.json");
	for (const value of [
		{ schema: 1 },
		{
			schema: 1,
			npmPackage: "@ccoalm/ccl-skills",
			version: "1.0.0",
			sourceCommit: "a".repeat(40),
			sourceState: "clean",
			snapshotHash: "0".repeat(64),
			files: [{ path: "../escape", sha256: "0".repeat(64), mode: 420 }],
		},
		{
			schema: 1,
			npmPackage: "@ccoalm/ccl-skills",
			version: "1.0.0",
			sourceCommit: "a".repeat(40),
			sourceState: "clean",
			snapshotHash: "0".repeat(64),
			files: [
				{ path: "x", sha256: "0".repeat(64), mode: 420 },
				{ path: "x", sha256: "0".repeat(64), mode: 420 },
			],
		},
	]) {
		writeFileSync(path, JSON.stringify(value));
		assert.throws(() => readRelease(path));
	}
});

test("manifest traversal is a structured refusal with zero mutation", () => {
	const f = fixture(),
		root = join(f.codexHome, "ccl-skills-npm"),
		victim = join(f.root, "victim");
	mkdirSync(root, { recursive: true });
	writeFileSync(victim, "keep");
	writeFileSync(
		join(root, "install-manifest.json"),
		JSON.stringify({
			schema: 1,
			packageVersion: "1.0.0",
			sourceCommit: "a".repeat(40),
			sourceState: "clean",
			snapshotHash: "b".repeat(64),
			ownedFiles: [{ path: "victim", sha256: "0".repeat(64), mode: 420 }],
			active: "../../",
			previous: null,
		}),
	);
	for (const command of [
		["doctor", "--json"],
		["update", "--yes", "--json"],
		["uninstall", "--yes", "--json"],
	]) {
		const before = readFileSync(victim, "utf8"),
			p = cli(f, command);
		assert.equal(p.status, 3, p.stderr);
		assert.equal(JSON.parse(p.stdout).status, "safety-refusal");
		assert.equal(readFileSync(victim, "utf8"), before);
	}
});

test("manifest decoder rejects malformed JSON", () => {
	const dir = mkdtempSync(join(tmpdir(), "manifest-red-")),
		p = join(dir, "m");
	writeFileSync(p, "{");
	assert.throws(() => readManifest(p));
});

test("managed roots accept the macOS /tmp alias", { skip: process.platform !== "darwin" }, () => {
	const root = mkdtempSync("/tmp/ccl-root-alias-"), codexHome = join(root, "home", ".codex");
	assert.doesNotThrow(() => assertSafeRoot(codexHome, join(codexHome, "ccl-skills-npm"), true));
});

test("private aliases are Darwin-only", () => {
	assert.equal(canonicalAlias("/tmp/ccl", "darwin"), "/private/tmp/ccl");
	assert.equal(canonicalAlias("/var/ccl", "darwin"), "/private/var/ccl");
	assert.equal(canonicalAlias("/tmp/ccl", "linux"), "/tmp/ccl");
	assert.equal(canonicalAlias("/var/ccl", "linux"), "/var/ccl");
});
