import test from "node:test";
import assert from "node:assert/strict";
import { existsSync, readFileSync } from "node:fs";
import { join } from "node:path";
import { spawn } from "node:child_process";
import { EventEmitter } from "node:events";
import { supervise } from "../dist/cli.js";
import { fixture, release } from "./helpers.mjs";
import {
	invoke,
	installed,
	manifest,
	publicSource,
	root,
} from "./fault-harness.mjs";

const journalPath = (f) => join(root(f), "operation-journal.json");
const manifestPath = (f) => join(root(f), "install-manifest.json");
const interruptAt = (name) => ({
	isInterrupted: (checkpoint) => checkpoint === name,
});

function updateFixture() {
	const f = installed();
	release(f, "2.0.0");
	return f;
}

test("update interruption before first mutation preserves v1", () => {
	const f = updateFixture(),
		before = readFileSync(manifestPath(f), "utf8"),
		source = publicSource(f),
		calls = existsSync(f.log) ? readFileSync(f.log, "utf8") : "";
	const result = invoke(
		f,
		"update",
		{ yes: true },
		interruptAt("before-first-mutation"),
	);
	assert.equal(result.code, 130);
	assert.equal(result.interrupted, true);
	assert.equal(result.status, "rolled-back");
	assert.equal(readFileSync(manifestPath(f), "utf8"), before);
	assert.equal(publicSource(f), source);
	assert.equal(
		readFileSync(f.log, "utf8")
			.slice(calls.length)
			.match(/marketplace (add|remove)|plugin (add|remove)/g),
		null,
	);
});

for (const checkpoint of [
	"after-old-plugin-remove",
	"after-old-marketplace-remove",
	"after-candidate-marketplace-add",
	"after-candidate-plugin-add",
	"after-public-verify-before-manifest",
]) {
	test(`update interruption ${checkpoint} rolls back to v1`, () => {
		const f = updateFixture(),
			before = readFileSync(manifestPath(f), "utf8"),
			source = publicSource(f);
		const result = invoke(f, "update", { yes: true }, interruptAt(checkpoint));
		assert.equal(result.code, 130);
		assert.equal(result.interrupted, true);
		assert.equal(result.status, "rolled-back");
		assert.equal(readFileSync(manifestPath(f), "utf8"), before);
		assert.equal(publicSource(f), source);
		assert.equal(existsSync(`${f.state}.plugin`), true);
		assert.equal(existsSync(journalPath(f)), false);
	});
}

test("rollback failure remains partial and retains candidate journal", () => {
	const f = fixture({ rollbackFail: true });
	release(f, "2.0.0");
	const result = invoke(
		f,
		"install",
		{},
		interruptAt("after-candidate-marketplace-add"),
	);
	assert.equal(result.code, 130);
	assert.equal(result.interrupted, true);
	assert.equal(result.status, "partial");
	assert.equal(existsSync(journalPath(f)), true);
	const journal = JSON.parse(readFileSync(journalPath(f), "utf8"));
	assert.equal(existsSync(journal.candidateSource), true);
});

test("post-manifest interruption keeps committed v2", () => {
	const f = updateFixture(),
		old = manifest(f);
	const result = invoke(
		f,
		"update",
		{ yes: true },
		interruptAt("after-manifest-commit"),
	);
	assert.equal(result.code, 130);
	assert.equal(result.interrupted, true);
	assert.match(result.status, /^committed(?:-stale-.*)?$/);
	assert.equal(manifest(f).active.version, "2.0.0");
	assert.notEqual(
		publicSource(f),
		join(root(f), old.active.path, "marketplace"),
	);
});

test("fresh install interruption before mutation remains absent", () => {
	const f = fixture(),
		result = invoke(f, "install", {}, interruptAt("before-first-mutation"));
	assert.equal(result.code, 130);
	assert.equal(result.interrupted, true);
	assert.equal(existsSync(manifestPath(f)), false);
	assert.equal(publicSource(f), null);
});

for (const checkpoint of [
	"after-candidate-marketplace-add",
	"after-candidate-plugin-add",
]) {
	test(`fresh install ${checkpoint} removes registration`, () => {
		const f = fixture(),
			result = invoke(f, "install", {}, interruptAt(checkpoint));
		assert.equal(result.code, 130);
		assert.equal(result.interrupted, true);
		assert.equal(result.status, "rolled-back");
		assert.equal(publicSource(f), null);
		assert.equal(existsSync(`${f.state}.plugin`), false);
		assert.equal(existsSync(journalPath(f)), false);
	});
}

test("real SIGINT during blocking Codex mutation exits 130 with one JSON", async () => {
	const f = fixture({ mutationSleep: 0.25, mutationSentinel: true });
	const child = spawn(process.execPath, ["dist/cli.js", "install", "--host", "codex", "--json"], {
		cwd: process.cwd(),
		env: f.env,
		stdio: ["ignore", "pipe", "pipe"],
		detached: true,
	});
	let stdout = "",
		stderr = "";
	child.stdout.on("data", (x) => (stdout += x));
	child.stderr.on("data", (x) => (stderr += x));
	const closed = new Promise((resolve) => child.on("close", resolve)),
		deadline = Date.now() + 5000;
	while (!existsSync(`${f.state}.mutation-started`)) {
		if (Date.now() > deadline) {
			child.kill("SIGKILL");
			throw Error("mutation sentinel timeout");
		}
		await new Promise((r) => setTimeout(r, 10));
	}
	process.kill(-child.pid, "SIGINT");
	const code = await closed;
	assert.equal(code, 130);
	const lines = stdout.trim().split("\n");
	assert.equal(lines.length, 1);
	const result = JSON.parse(lines[0]);
	assert.equal(result.interrupted, true);
	assert.equal(result.status, "rolled-back");
	assert.equal(stderr, "");
	assert.equal(publicSource(f), null);
	assert.equal(existsSync(`${f.state}.mutation-completed`), true);
	assert.equal(existsSync(journalPath(f)), false);
	assert.equal(existsSync(`${root(f)}.lock`), false);
});

for (const checkpoint of [
	"after-uninstall-plugin-remove",
	"after-uninstall-marketplace-remove",
]) {
	test(`uninstall ${checkpoint} restores installation`, () => {
		const f = installed(),
			source = publicSource(f),
			result = invoke(f, "uninstall", { yes: true }, interruptAt(checkpoint));
		assert.equal(result.code, 130);
		assert.equal(result.status, "rolled-back");
		assert.equal(publicSource(f), source);
		assert.equal(existsSync(`${f.state}.plugin`), true);
		assert.equal(existsSync(journalPath(f)), false);
	});
}
test("uninstall interruption after absent commit never restores old", () => {
	const f = installed(),
		result = invoke(
			f,
			"uninstall",
			{ yes: true },
			interruptAt("after-uninstall-public-absent-commit"),
		);
	assert.equal(result.code, 130);
	assert.equal(result.status, "uninstalled");
	assert.equal(publicSource(f), null);
	assert.equal(existsSync(manifestPath(f)), false);
});
test("uninstall cleanup fault after interrupt preserves committed evidence", () => {
	const f = installed(),
		context = {
			...interruptAt("after-uninstall-public-absent-commit"),
			fs: {
				fault(operation) {
					if (operation === "quarantine-rename")
						throw Error("injected cleanup fault");
				},
			},
		},
		result = invoke(f, "uninstall", { yes: true }, context);
	assert.equal(result.code, 130);
	assert.equal(result.interrupted, true);
	assert.equal(result.status, "committed-stale-cleanup");
	assert.equal(publicSource(f), null);
	assert.equal(existsSync(journalPath(f)), true);
});
test("uninstall rollback restore failure is partial", () => {
	const f = fixture();
	assert.equal(invoke(f, "install").code, 3);
	f.env.FAKE_COMMAND_FAILURES =
		"plugin marketplace add " + publicSource(f) + "#2";
	const result = invoke(
		f,
		"uninstall",
		{ yes: true },
		interruptAt("after-uninstall-plugin-remove"),
	);
	assert.equal(result.code, 130);
	assert.equal(result.status, "partial");
	assert.equal(existsSync(journalPath(f)), true);
});

function supervisorCase(
	result,
	{ signal = true, malformed = false, duplicate = false, crash = false } = {},
) {
	let fire;
	const worker = new EventEmitter();
	worker.once = worker.once.bind(worker);
	const promise = supervise(
		"install",
		{},
		{
			workerFactory: (data) => {
				assert.equal(data.protocol, 1);
				assert.ok(data.abortBuffer instanceof SharedArrayBuffer);
				queueMicrotask(() => {
					if (signal) fire();
					if (crash) worker.emit("error", Error("boom"));
					else {
						worker.emit("message", malformed ? {} : result);
						if (duplicate) worker.emit("message", result);
					}
				});
				return worker;
			},
			onSignal: (fn) => {
				fire = fn;
				return () => {};
			},
		},
	);
	return promise;
}
test("supervisor wraps rolled-back and committed finality after signal", async () => {
	for (const status of ["rolled-back", "committed"]) {
		const result = await supervisorCase({
			code: status === "rolled-back" ? 1 : 3,
			status,
			message: "known",
		});
		assert.equal(result.code, 130);
		assert.equal(result.interrupted, true);
		assert.equal(result.status, status);
	}
});
test("supervisor fails closed for crash and malformed result", async () => {
	assert.equal((await supervisorCase(null, { crash: true })).code, 5);
	assert.equal((await supervisorCase(null, { malformed: true })).code, 5);
});
test("supervisor fails closed for duplicate result", async () => {
	assert.equal(
		(
			await supervisorCase(
				{ code: 1, status: "rolled-back", message: "known" },
				{ duplicate: true },
			)
		).code,
		5,
	);
});
