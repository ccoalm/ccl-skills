import test from "node:test";
import assert from "node:assert/strict";
import {
	existsSync,
	readFileSync,
	writeFileSync,
	mkdirSync,
	symlinkSync,
	rmSync,
	readdirSync,
} from "node:fs";
import { join } from "node:path";
import { cli, fixture, release } from "./helpers.mjs";
const packageVersion = JSON.parse(
	readFileSync(new URL("../package.json", import.meta.url), "utf8"),
).version;
test("fresh install is publicly verified but hooks remain pending", () => {
	const f = fixture(),
		p = cli(f, ["install", "--json"]);
	assert.equal(p.status, 3, p.stderr);
	assert.equal(JSON.parse(p.stdout).status, "installed-hooks-pending");
	assert.ok(
		existsSync(join(f.codexHome, "ccl-skills-npm/install-manifest.json")),
	);
});
test("production CLI ignores assets override environment", () => {
	const f = fixture(),
		evil = release(f, "9.9.9", "evil");
	delete f.assets;
	f.env.CCL_SKILLS_CODEX_ASSETS_DIR = evil;
	const p = cli(f, ["install", "--json"]);
	assert.equal(p.status, 3, p.stderr);
	const manifest = JSON.parse(
		readFileSync(join(f.codexHome, "ccl-skills-npm/install-manifest.json")),
	);
	assert.equal(manifest.active.version, packageVersion);
	assert.notEqual(manifest.active.version, "9.9.9");
});
test("same version install is idempotent pending", () => {
	const f = fixture();
	cli(f, ["install", "--json"]);
	const before = readFileSync(f.log, "utf8");
	const p = cli(f, ["install", "--json"]);
	assert.equal(p.status, 3);
	assert.match(JSON.parse(p.stdout).message, /same version/);
	assert.doesNotMatch(
		readFileSync(f.log, "utf8").slice(before.length),
		/marketplace add|plugin add/,
	);
});
test("missing and old hosts exit 4", () => {
	const old = fixture({ version: "0.132.9" });
	assert.equal(cli(old, ["doctor"]).status, 4);
	const f = fixture();
	f.env.PATH = "/usr/bin:/bin";
	assert.equal(cli(f, ["doctor"]).status, 4);
});
test("plugin failure rolls back; rollback failure retains journal", () => {
	const a = fixture({ pluginAddFail: true });
	let p = cli(a, ["install", "--json"]);
	assert.equal(p.status, 1);
	assert.ok(!existsSync(`${a.state}.market`));
	const b = fixture({ pluginAddFail: true, rollbackFail: true });
	p = cli(b, ["install", "--json"]);
	assert.equal(p.status, 5);
	assert.ok(
		existsSync(join(b.codexHome, "ccl-skills-npm/operation-journal.json")),
	);
});
test("doctor reports partial journal", () => {
	const f = fixture();
	mkdirSync(join(f.codexHome, "ccl-skills-npm"), { recursive: true });
	writeFileSync(
		join(f.codexHome, "ccl-skills-npm/operation-journal.json"),
		"{}",
	);
	assert.equal(
		JSON.parse(cli(f, ["doctor", "--json"]).stdout).status,
		"partial-journal",
	);
});
test("update absent and downgrade flag usage fail closed", () => {
	const f = fixture();
	assert.equal(cli(f, ["update", "--yes"]).status, 3);
	assert.equal(cli(f, ["update", "--allow-downgrade"]).status, 2);
});
test("uninstall defaults dry-run and modified owned file is retained", () => {
	const f = fixture();
	cli(f, ["install"]);
	assert.equal(cli(f, ["uninstall", "--json"]).status, 0);
	const root = join(f.codexHome, "ccl-skills-npm"),
		m = JSON.parse(readFileSync(join(root, "install-manifest.json")));
	writeFileSync(
		join(root, m.active.path, m.active.ownedFiles[0].path),
		"drift",
	);
	const p = cli(f, ["uninstall", "--yes", "--json"]);
	assert.equal(p.status, 3);
	assert.ok(existsSync(join(root, "install-manifest.json")));
});
test("json stdout is one document and usage is stderr-only", () => {
	const f = fixture(),
		p = cli(f, ["doctor", "--json"]);
	assert.doesNotThrow(() => JSON.parse(p.stdout));
	assert.equal(p.stderr, "");
	const u = cli(f, ["bogus", "--json"]);
	assert.equal(u.status, 2);
	assert.equal(u.stdout, "");
	assert.match(u.stderr, /Invalid/);
});
test("legacy plugin, legacy skill symlink, and unowned registration fail closed", () => {
	let f = fixture({ legacy: true }),
		p = cli(f, ["install", "--json"]);
	assert.equal(JSON.parse(p.stdout).status, "legacy-plugin-conflict");
	f = fixture();
	mkdirSync(join(f.codexHome, "skills"), { recursive: true });
	symlinkSync(f.root, join(f.codexHome, "skills/ccl-skills"));
	p = cli(f, ["install", "--json"]);
	assert.equal(JSON.parse(p.stdout).status, "legacy-skill-symlink");
	f = fixture();
	mkdirSync(f.codexHome, { recursive: true });
	writeFileSync(`${f.state}.market`, join(f.codexHome, "foreign-marketplace"));
	p = cli(f, ["install", "--json"]);
	assert.equal(JSON.parse(p.stdout).status, "unowned-registration");
});
test("malformed host state and disabled legacy refuse install without mutation", () => {
	for (const [expected, transform] of [
		["host-state-unknown", (script) => script.replace('echo "MARKETPLACE         ROOT";', 'echo "MARKETPLACE ROOT"; echo "ccl-skills-npm  relative/root";')],
		["legacy-plugin-conflict", (script) => script.replace("installed, enabled  local  /tmp/legacy';", "installed, disabled  local  /tmp/legacy';")],
	]) {
		const f = fixture({ legacy: true });
		const fake = join(f.root, "bin", "codex");
		writeFileSync(fake, transform(readFileSync(fake, "utf8")), { mode: 0o755 });
		const p = cli(f, ["install", "--json"]);
		assert.equal(p.status, 3, p.stdout);
		assert.equal(JSON.parse(p.stdout).status, expected);
		assert.doesNotMatch(readFileSync(f.log, "utf8"), /marketplace (add|remove)|plugin (add|remove)/);
	}
});
test("managed symlink and sibling lock fail closed", () => {
	let f = fixture();
	mkdirSync(join(f.codexHome, "ccl-skills-npm"), { recursive: true });
	symlinkSync(f.root, join(f.codexHome, "ccl-skills-npm/escape"));
	let p = cli(f, ["install", "--json"]);
	assert.equal(JSON.parse(p.stdout).status, "symlink-conflict");
	f = fixture();
	mkdirSync(f.codexHome, { recursive: true });
	writeFileSync(join(f.codexHome, "ccl-skills-npm.lock"), "");
	p = cli(f, ["install", "--json"]);
	assert.equal(JSON.parse(p.stdout).status, "lock-contended");
});
test("healthy owned install uninstalls after public removal", () => {
	const f = fixture();
	assert.equal(cli(f, ["install"]).status, 3);
	const p = cli(f, ["uninstall", "--yes", "--json"]);
	assert.equal(p.status, 0, p.stdout);
	assert.equal(JSON.parse(p.stdout).status, "uninstalled");
});
test("install uninstall same version reinstall succeeds", () => {
	const f = fixture();
	assert.equal(cli(f, ["install"]).status, 3);
	assert.equal(cli(f, ["uninstall", "--yes"]).status, 0);
	assert.equal(cli(f, ["install"]).status, 3);
});
test("v1 to v2 update switches exact source and manifest pointers", () => {
	const f = fixture();
	release(f, "1.0.0", "v1");
	assert.equal(cli(f, ["install"]).status, 3);
	const old = JSON.parse(
		readFileSync(join(f.codexHome, "ccl-skills-npm/install-manifest.json")),
	);
	release(f, "2.0.0", "v2");
	const before = readFileSync(f.log, "utf8");
	assert.equal(cli(f, ["update"]).status, 0);
	const dry = readFileSync(f.log, "utf8").slice(before.length);
	assert.doesNotMatch(dry, /marketplace (add|remove)|plugin (add|remove)/);
	assert.equal(cli(f, ["update", "--yes"]).status, 3);
	const m = JSON.parse(
		readFileSync(join(f.codexHome, "ccl-skills-npm/install-manifest.json")),
	);
	assert.equal(m.active.version, "2.0.0");
	assert.deepEqual(m.previous, old.active);
	assert.equal(
		readFileSync(`${f.state}.market`, "utf8"),
		join(f.codexHome, "ccl-skills-npm", m.active.path, "marketplace"),
	);
});
test("downgrade requires explicit permission and preserves previous", () => {
	const f = fixture();
	release(f, "2.0.0", "v2");
	cli(f, ["install"]);
	const v2 = JSON.parse(
		readFileSync(join(f.codexHome, "ccl-skills-npm/install-manifest.json")),
	);
	release(f, "1.0.0", "v1");
	assert.equal(
		JSON.parse(cli(f, ["update", "--yes", "--json"]).stdout).status,
		"downgrade-refused",
	);
	assert.equal(cli(f, ["update", "--allow-downgrade", "--yes"]).status, 3);
	assert.deepEqual(
		JSON.parse(
			readFileSync(
				join(f.codexHome, "ccl-skills-npm/install-manifest.json"),
			),
		).previous,
		v2.active,
	);
});

test("rollback unknown preserves candidate and the source Codex still references", () => {
	const f = fixture({ pluginAddFail: true, rollbackFail: true });
	const p = cli(f, ["install", "--json"]);
	assert.equal(p.status, 5);
	const journal = JSON.parse(
		readFileSync(
			join(f.codexHome, "ccl-skills-npm/operation-journal.json"),
		),
	);
	assert.ok(existsSync(journal.candidateSource));
	assert.ok(
		existsSync(
			join(journal.candidateSource, ".agents/plugins/marketplace.json"),
		),
	);
	assert.equal(
		readFileSync(`${f.state}.market`, "utf8"),
		journal.candidateSource,
	);
});

test("an intermediate symlink refuses install without writing through it", () => {
	const f = fixture(),
		outside = join(f.root, "outside");
	mkdirSync(outside);
	rmSync(f.home, { recursive: true, force: true });
	symlinkSync(outside, f.home);
	const p = cli(f, ["install", "--json"]);
	assert.equal(JSON.parse(p.stdout).status, "safety-refusal");
	assert.ok(!existsSync(join(outside, ".codex/ccl-skills-npm")));
});

for (const failure of [
	"plugin remove ccl-skills@ccl-skills-npm#1",
	"plugin marketplace remove ccl-skills-npm#1",
	"plugin marketplace add PLACEHOLDER#1",
	"plugin add ccl-skills@ccl-skills-npm#2",
]) {
	test(`update restores v1 after ${failure.split("#")[0]}`, () => {
		const f = fixture();
		release(f, "1.0.0");
		assert.equal(cli(f, ["install"]).status, 3);
		const manifestPath = join(
				f.codexHome,
				"ccl-skills-npm/install-manifest.json",
			),
			old = readFileSync(manifestPath, "utf8"),
			oldManifest = JSON.parse(old),
			oldSource = join(
				f.codexHome,
				"ccl-skills-npm",
				oldManifest.active.path,
				"marketplace",
			);
		const assets = release(f, "2.0.0"),
			candidate = join(
				f.codexHome,
				"ccl-skills-npm/snapshots",
				JSON.parse(readFileSync(join(assets, "release.json"))).snapshotHash,
				"marketplace",
			);
		f.env.FAKE_COMMAND_FAILURES = failure.replace("PLACEHOLDER", candidate);
		const p = cli(f, ["update", "--yes", "--json"]);
		assert.equal(p.status, 1, p.stdout);
		assert.equal(readFileSync(manifestPath, "utf8"), old);
		assert.equal(readFileSync(`${f.state}.market`, "utf8"), oldSource);
		assert.ok(
			!existsSync(
				join(f.codexHome, "ccl-skills-npm/operation-journal.json"),
			),
		);
	});
}

for (const failure of [
	"plugin remove ccl-skills@ccl-skills-npm#1",
	"plugin marketplace remove ccl-skills-npm#1",
]) {
	test(`uninstall restores installation after ${failure.split("#")[0]}`, () => {
		const f = fixture();
		assert.equal(cli(f, ["install"]).status, 3);
		const manifest = readFileSync(
			join(f.codexHome, "ccl-skills-npm/install-manifest.json"),
			"utf8",
		);
		f.env.FAKE_COMMAND_FAILURES = failure;
		const p = cli(f, ["uninstall", "--yes", "--json"]);
		assert.equal(p.status, 1, p.stdout);
		assert.equal(
			readFileSync(
				join(f.codexHome, "ccl-skills-npm/install-manifest.json"),
				"utf8",
			),
			manifest,
		);
		assert.ok(existsSync(`${f.state}.plugin`));
		assert.ok(
			!existsSync(
				join(f.codexHome, "ccl-skills-npm/operation-journal.json"),
			),
		);
	});
}

for (const kind of ["candidateDrift", "candidateSymlink"]) {
	test(`${kind} makes safe candidate cleanup partial`, () => {
		const f = fixture({ pluginAddFail: true, [kind]: true });
		const p = cli(f, ["install", "--json"]);
		assert.equal(p.status, 5, p.stdout);
		const journal = JSON.parse(
			readFileSync(
				join(f.codexHome, "ccl-skills-npm/operation-journal.json"),
			),
		);
		assert.ok(existsSync(journal.candidateSource));
		assert.match(journal.error, /cleanup:/);
	});
}

test("rollback restore failure is partial and retains old manifest and candidate", () => {
	const f = fixture();
	release(f, "1.0.0");
	assert.equal(cli(f, ["install"]).status, 3);
	const manifestPath = join(
			f.codexHome,
			"ccl-skills-npm/install-manifest.json",
		),
		old = readFileSync(manifestPath, "utf8"),
		oldManifest = JSON.parse(old);
	release(f, "2.0.0");
	f.env.FAKE_COMMAND_FAILURES =
		"plugin add ccl-skills@ccl-skills-npm#2|plugin marketplace add " +
		join(
			f.codexHome,
			"ccl-skills-npm",
			oldManifest.active.path,
			"marketplace",
		) +
		"#2";
	const p = cli(f, ["update", "--yes", "--json"]);
	assert.equal(p.status, 5, p.stdout);
	assert.equal(readFileSync(manifestPath, "utf8"), old);
	const journal = JSON.parse(
		readFileSync(
			join(f.codexHome, "ccl-skills-npm/operation-journal.json"),
		),
	);
	assert.ok(existsSync(journal.candidateSource));
});

test("v1 to v2 to v3 retains exactly active and previous snapshots", () => {
	const f = fixture(),
		root = join(f.codexHome, "ccl-skills-npm"),
		manifestPath = join(root, "install-manifest.json");
	release(f, "1.0.0");
	assert.equal(cli(f, ["install"]).status, 3);
	release(f, "2.0.0");
	assert.equal(cli(f, ["update", "--yes"]).status, 3);
	release(f, "3.0.0");
	assert.equal(cli(f, ["update", "--yes"]).status, 3);
	const manifest = JSON.parse(readFileSync(manifestPath));
	assert.equal(manifest.schema, 2);
	assert.equal(manifest.active.version, "3.0.0");
	assert.equal(manifest.previous.version, "2.0.0");
	assert.equal(
		readdirSync(join(root, "snapshots")).filter((x) => !x.startsWith(".trash-"))
			.length,
		2,
	);
});

test("drifted v1 prune candidate is retained with ownership evidence", () => {
	const f = fixture(),
		root = join(f.codexHome, "ccl-skills-npm"),
		manifestPath = join(root, "install-manifest.json");
	release(f, "1.0.0");
	cli(f, ["install"]);
	let m = JSON.parse(readFileSync(manifestPath));
	const v1 = m.active;
	release(f, "2.0.0");
	cli(f, ["update", "--yes"]);
	writeFileSync(join(root, v1.path, v1.ownedFiles[0].path), "drift");
	release(f, "3.0.0");
	const result = JSON.parse(cli(f, ["update", "--yes", "--json"]).stdout);
	assert.equal(result.status, "installed-hooks-pending");
	assert.ok(result.details.retainedDrift.length);
	assert.ok(existsSync(join(root, "ownership-evidence.json")));
	assert.ok(existsSync(join(root, v1.path)));
});

test("clean uninstall removes the complete managed root", () => {
	const f = fixture(),
		root = join(f.codexHome, "ccl-skills-npm");
	release(f, "1.0.0");
	cli(f, ["install"]);
	release(f, "2.0.0");
	cli(f, ["update", "--yes"]);
	assert.equal(cli(f, ["uninstall", "--yes"]).status, 0);
	assert.equal(existsSync(root), false);
	assert.equal(existsSync(`${root}.lock`), false);
});
