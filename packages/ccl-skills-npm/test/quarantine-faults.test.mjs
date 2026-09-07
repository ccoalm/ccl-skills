import test from "node:test";
import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import {
	existsSync,
	mkdirSync,
	readFileSync,
	readdirSync,
	writeFileSync,
} from "node:fs";
import { join } from "node:path";
import {
	injected,
	installed,
	invoke,
	journal,
	manifest,
	publicSource,
	release,
	root,
} from "./fault-harness.mjs";

const trash = (f) =>
	readdirSync(root(f)).filter((name) => name.startsWith(".trash-"));
const calls = (f) => (existsSync(f.log) ? readFileSync(f.log, "utf8") : "");

test("update commit survives prune quarantine rename failure", () => {
	const f = installed();
	release(f, "2.0.0");
	invoke(f, "update", { yes: true });
	const old = manifest(f).previous;
	release(f, "3.0.0");
	const result = invoke(
		f,
		"update",
		{ yes: true },
		injected("quarantine-rename"),
	);
	const current = manifest(f),
		j = journal(f);
	assert.equal(result.code, 5);
	assert.equal(result.status, "committed-stale-cleanup");
	assert.equal(current.active.version, "3.0.0");
	assert.equal(
		publicSource(f),
		join(root(f), current.active.path, "marketplace"),
	);
	assert.ok(existsSync(join(root(f), old.path)));
	assert.equal(j.step, "quarantine-rename-failed");
	assert.equal(j.snapshot.snapshotHash, old.snapshotHash);
	assert.equal(j.committed, true);
});

test("uninstall quarantine rename failure preserves absent public state and resumes", () => {
	const f = installed(),
		before = manifest(f),
		result = invoke(
			f,
			"uninstall",
			{ yes: true },
			injected("quarantine-rename"),
		);
	assert.equal(result.code, 5);
	assert.equal(result.status, "committed-stale-cleanup");
	assert.equal(publicSource(f), null);
	assert.ok(existsSync(join(root(f), before.active.path)));
	assert.ok(existsSync(join(root(f), "install-manifest.json")));
	const j = journal(f);
	assert.equal(j.step, "quarantine-rename-failed");
	assert.equal(j.snapshot.snapshotHash, before.active.snapshotHash);
	const resumed = invoke(f, "uninstall", { yes: true });
	assert.equal(resumed.code, 0);
	assert.equal(existsSync(root(f)), false);
});

for (const occurrence of [1, 2])
	test(`${occurrence === 1 ? "first" : "middle"} trash unlink failure resumes from journal progress`, () => {
		const f = installed(),
			before = manifest(f),
			result = invoke(
				f,
				"uninstall",
				{ yes: true },
				injected("trash-unlink", occurrence),
			);
		assert.equal(result.code, 5);
		assert.equal(result.status, "committed-stale-cleanup");
		assert.equal(publicSource(f), null);
		assert.equal(existsSync(join(root(f), before.active.path)), false);
		const names = trash(f);
		assert.equal(names.length, 1);
		const j = journal(f);
		assert.equal(j.trashPath, names[0]);
		assert.deepEqual(j.completed, ["trash-renamed"]);
		assert.equal(j.snapshot.snapshotHash, before.active.snapshotHash);
		assert.equal(j.deletedFiles.length, occurrence - 1);
		assert.ok(existsSync(join(root(f), names[0])));
		const resumed = invoke(f, "uninstall", { yes: true });
		assert.equal(resumed.code, 0);
		assert.equal(existsSync(root(f)), false);
	});

for (const selection of ["explicit", "default"])
for (const command of ["doctor", "install", "update", "uninstall"])
for (const state of ["known", "unknown", "failed", "changed-after-probe"])
	test(`${selection} ${command} recovers verified trash only with readable host state (${state})`, () => {
		const f = installed();
		f.env.PATH = `${join(f.root, "bin")}:/usr/bin:/bin`;
		const interrupted = invoke(f, "uninstall", { yes: true }, injected("trash-unlink"));
		assert.equal(interrupted.status, "committed-stale-cleanup");
		const saved = journal(f), trashPath = join(root(f), saved.trashPath);
		const remaining = saved.snapshot.ownedFiles.filter(file => existsSync(join(trashPath, file.path)));
		const journalPath = join(root(f), "operation-journal.json"), manifestPath = join(root(f), "install-manifest.json");
		const journalBefore = readFileSync(journalPath, "utf8"), manifestBefore = readFileSync(manifestPath, "utf8");
		const fake = join(f.root, "bin", "codex"), original = readFileSync(fake, "utf8");
		if (state === "unknown") writeFileSync(fake, original.replace('echo "MARKETPLACE         ROOT";', 'echo "MARKETPLACE ROOT"; echo "ccl-skills-npm relative/root";'), { mode: 0o755 });
		if (state === "failed") writeFileSync(fake, original.replace('if [ "$1 $2 $3" = "plugin marketplace list" ]; then', 'if [ "$1 $2 $3" = "plugin marketplace list" ]; then exit 9;'), { mode: 0o755 });
		if (state === "changed-after-probe") {
			const count = Number(readFileSync(`${f.state}.count.plugin_marketplace_list`, "utf8"));
			f.env.FAKE_COMMAND_FAILURES = `plugin marketplace list#${count + (selection === "explicit" ? 2 : 3)}`;
		}
		const resume = () => {
			if (selection === "explicit") return invoke(f, command, command === "uninstall" ? { yes: true } : {});
			const result = spawnSync(process.execPath, ["dist/cli.js", command, ...(command === "uninstall" ? ["--yes"] : []), "--json"], { encoding: "utf8", env: f.env });
			return { ...JSON.parse(result.stdout), code: result.status };
		};
		const before = calls(f);
		let resumed = resume();
		if (state !== "known") {
			assert.equal(resumed.code, 5, JSON.stringify(resumed));
			assert.equal(resumed.status, state === "changed-after-probe" ? "partial" : "partial-journal");
			assert.equal(readFileSync(journalPath, "utf8"), journalBefore);
			assert.equal(readFileSync(manifestPath, "utf8"), manifestBefore);
			for (const file of remaining) assert.ok(existsSync(join(trashPath, file.path)), file.path);
			writeFileSync(fake, original, { mode: 0o755 });
			resumed = resume();
		}
		assert.equal(resumed.code, 0, JSON.stringify(resumed));
		assert.equal(resumed.status, "uninstalled");
		assert.equal(existsSync(root(f)), false);
		assert.doesNotMatch(calls(f).slice(before.length), /marketplace (add|remove)|plugin (add|remove)/);
	});

for (const selection of ["explicit", "default"])
for (const state of ["unknown", "failed"])
	test(`${selection} uninstall retains pending update cleanup when host state is ${state}`, () => {
		const f = installed();
		f.env.PATH = `${join(f.root, "bin")}:/usr/bin:/bin`;
		release(f, "2.0.0");
		invoke(f, "update", { yes: true });
		release(f, "3.0.0");
		const interrupted = invoke(f, "update", { yes: true }, injected("trash-unlink"));
		assert.equal(interrupted.code, 5);
		const saved = journal(f), trashPath = join(root(f), saved.trashPath);
		assert.equal(saved.operation, "prune");
		const remaining = saved.snapshot.ownedFiles.filter(file => existsSync(join(trashPath, file.path)));
		const journalPath = join(root(f), "operation-journal.json"), manifestPath = join(root(f), "install-manifest.json");
		const journalBefore = readFileSync(journalPath, "utf8"), manifestBefore = readFileSync(manifestPath, "utf8");
		const fake = join(f.root, "bin", "codex"), original = readFileSync(fake, "utf8");
		writeFileSync(fake, state === "unknown"
			? original.replace('echo "MARKETPLACE         ROOT";', 'echo "MARKETPLACE ROOT"; echo "ccl-skills-npm relative/root";')
			: original.replace('if [ "$1 $2 $3" = "plugin marketplace list" ]; then', 'if [ "$1 $2 $3" = "plugin marketplace list" ]; then exit 9;'), { mode: 0o755 });
		const resume = () => {
			if (selection === "explicit") return invoke(f, "uninstall", { yes: true });
			const result = spawnSync(process.execPath, ["dist/cli.js", "uninstall", "--yes", "--json"], { encoding: "utf8", env: f.env });
			return { ...JSON.parse(result.stdout), code: result.status };
		};
		const before = calls(f), refused = resume();
		assert.equal(refused.code, 5, JSON.stringify(refused));
		assert.equal(readFileSync(journalPath, "utf8"), journalBefore);
		assert.equal(readFileSync(manifestPath, "utf8"), manifestBefore);
		for (const file of remaining) assert.ok(existsSync(join(trashPath, file.path)), file.path);
		assert.doesNotMatch(calls(f).slice(before.length), /marketplace (add|remove)|plugin (add|remove)/);
		assert.equal(refused.details.hostFailure.kind, state === "unknown" ? "state-unknown" : "probe-failed");
		writeFileSync(fake, original, { mode: 0o755 });
		assert.equal(resume().code, 0);
		assert.equal(existsSync(root(f)), false);
	});

test("unknown or mismatched trash fails closed", () => {
	const f = installed();
	mkdirSync(join(root(f), ".trash-unknown-deadbeef"));
	writeFileSync(join(root(f), ".trash-unknown-deadbeef/file"), "x");
	for (const command of ["doctor", "install"]) {
		const result = invoke(f, command);
		assert.equal(result.code, 5);
		assert.equal(result.status, "unknown-trash");
		assert.ok(existsSync(join(root(f), ".trash-unknown-deadbeef/file")));
	}
});

test("committed journal unlink failure is classified, doctor observes it, next install repairs without host mutation", () => {
	const f = installed();
	release(f, "2.0.0");
	const result = invoke(f, "update", { yes: true }, injected("journal-unlink"));
	const current = manifest(f);
	assert.equal(result.code, 5);
	assert.equal(result.status, "committed-stale-journal");
	assert.equal(current.active.version, "2.0.0");
	assert.equal(
		publicSource(f),
		join(root(f), current.active.path, "marketplace"),
	);
	assert.equal(journal(f).step, "journal-unlink-failed");
	const doctor = invoke(f, "doctor", {}, injected("journal-unlink"));
	assert.equal(doctor.status, "committed-stale-journal");
	const before = calls(f),
		repair = invoke(f, "install");
	assert.equal(repair.code, 3);
	assert.equal(repair.status, "installed-hooks-pending");
	assert.equal(existsSync(join(root(f), "operation-journal.json")), false);
	assert.equal(
		calls(f)
			.slice(before.length)
			.match(/marketplace (add|remove)|plugin (add|remove)/g),
		null,
	);
});

for (const operation of [
	"temp-file-fsync",
	"atomic-json-rename",
	"parent-dir-fsync",
])
	test(`journal ${operation} failure returns structured finality`, () => {
		const f = installed(),
			before = manifest(f),
			result = invoke(f, "uninstall", { yes: true }, injected(operation));
		assert.equal(result.code, 5);
		assert.equal(typeof result.status, "string");
		assert.deepEqual(manifest(f), before);
		assert.equal(
			publicSource(f),
			join(root(f), before.active.path, "marketplace"),
		);
	});

test("quarantine parent fsync failure records actual renamed trash and preserves evidence", () => {
	const f = installed(),
		before = manifest(f);
	let parentCalls = 0;
	const result = invoke(
		f,
		"uninstall",
		{ yes: true },
		{
			fault(operation) {
				if (operation === "parent-dir-fsync" && ++parentCalls === 5)
					throw Object.assign(new Error("injected EIO"), { code: "EIO" });
			},
		},
	);
	assert.equal(result.code, 5);
	assert.equal(publicSource(f), null);
	const j = journal(f);
	assert.equal(j.step, "trash-renamed");
	assert.equal(j.snapshot.snapshotHash, before.active.snapshotHash);
	assert.ok(j.trashPath);
	assert.equal(existsSync(join(root(f), j.trashPath)), true);
	assert.equal(existsSync(join(root(f), before.active.path)), false);
});
