import test from "node:test";
import assert from "node:assert/strict";
import { mkdtempSync, readdirSync, readFileSync, renameSync, writeFileSync } from "node:fs";
import { join } from "node:path";
import { tmpdir } from "node:os";
import {
	compareVersions,
	emitNotice,
	formatNotice,
	needsRefresh,
	refresh,
	pickLatest,
	refreshAllowed,
	shouldNotify,
	writeCacheAtomic,
} from "../dist/update-notice.js";

const HOUR = 3600 * 1000;
const NOW = Date.parse("2026-08-24T12:00:00.000Z");

// An input where every eligibility condition is satisfied. Each negative case
// below mutates exactly one field, so a failing row names the gate that broke.
function eligible(overrides = {}) {
	return {
		current: "0.2.0",
		cache: { latest: "0.3.0", lastCheckedAt: new Date(NOW - HOUR).toISOString() },
		now: NOW,
		env: {},
		stdoutTTY: true,
		stderrTTY: true,
		columns: 80,
		json: false,
		...overrides,
	};
}

test("notifies when every eligibility condition holds", () => {
	assert.deepEqual(shouldNotify(eligible()), {
		show: true,
		reason: "update-available",
		latest: "0.3.0",
	});
});

test("suppression reasons are sanitized codes, one per gate", () => {
	const cases = [
		["opt-out", { env: { CCL_SKILLS_NO_UPDATE_NOTIFIER: "1" } }],
		["opt-out", { env: { NO_UPDATE_NOTIFIER: "1" } }],
		["non-interactive", { env: { CI: "true" } }],
		["non-interactive", { env: { GITHUB_ACTIONS: "true" } }],
		["non-interactive", { stdoutTTY: false }],
		["non-interactive", { stderrTTY: false }],
		["structured-output", { json: true }],
		["narrow-terminal", { columns: 59 }],
		["no-cache", { cache: undefined }],
		["no-cache", { cache: {} }],
		["up-to-date", { cache: { latest: "0.2.0", lastCheckedAt: "x" } }],
		["up-to-date", { cache: { latest: "0.1.9", lastCheckedAt: "x" } }],
	];
	for (const [reason, override] of cases) {
		const got = shouldNotify(eligible(override));
		assert.equal(got.show, false, `${reason}: ${JSON.stringify(override)}`);
		assert.equal(got.reason, reason, JSON.stringify(override));
	}
});

test("suppression never leaks the notice body or local context", () => {
	const got = shouldNotify(eligible({ json: true }));
	assert.equal(got.latest, undefined);
	assert.equal(Object.keys(got).join(","), "show,reason");
});

// Precision rows: inputs that look like a suppressed case but must still notify.
test("near-miss inputs still notify", () => {
	assert.equal(shouldNotify(eligible({ columns: 60 })).show, true, "width floor is inclusive");
	assert.equal(shouldNotify(eligible({ env: { CI: "" } })).show, true, "empty CI is not CI");
	assert.equal(
		shouldNotify(eligible({ columns: undefined })).show,
		true,
		"unknown width is not narrow",
	);
	// A pty with no window size reports 0 columns. Node uses that for "unknown",
	// not for "zero cells wide"; treating it as narrow silences every such run.
	assert.equal(shouldNotify(eligible({ columns: 0 })).show, true, "0 columns means unknown");
});

test("cooldown suppresses a repeat notice for the same version", () => {
	const notified = {
		latest: "0.3.0",
		lastCheckedAt: new Date(NOW - HOUR).toISOString(),
		notifiedVersion: "0.3.0",
		notifiedAt: new Date(NOW - HOUR).toISOString(),
	};
	assert.equal(shouldNotify(eligible({ cache: notified })).reason, "cooldown");

	const stale = { ...notified, notifiedAt: new Date(NOW - 25 * HOUR).toISOString() };
	assert.equal(shouldNotify(eligible({ cache: stale })).show, true, "cooldown expires");

	const otherVersion = { ...notified, latest: "0.4.0" };
	assert.equal(
		shouldNotify(eligible({ cache: otherVersion })).show,
		true,
		"a newer version is not covered by the previous cooldown",
	);
});

test("the background check is gated by the same opt-out and automation rules", () => {
	assert.equal(refreshAllowed(eligible()), true);
	assert.equal(refreshAllowed(eligible({ env: { CCL_SKILLS_NO_UPDATE_NOTIFIER: "1" } })), false);
	assert.equal(refreshAllowed(eligible({ env: { NO_UPDATE_NOTIFIER: "1" } })), false);
	assert.equal(refreshAllowed(eligible({ env: { CI: "true" } })), false, "no network in CI");
	assert.equal(refreshAllowed(eligible({ stdoutTTY: false })), false);
	assert.equal(refreshAllowed(eligible({ json: true })), false, "no network for --json");
	assert.equal(
		refreshAllowed(eligible({ cache: undefined })),
		true,
		"a missing cache does not block the refresh that would populate it",
	);
	assert.equal(
		refreshAllowed(eligible({ cache: { latest: "0.2.0", lastCheckedAt: "x" } })),
		true,
		"being up to date does not block the next periodic refresh",
	);
});

test("compareVersions orders numerically, not lexically", () => {
	assert.equal(compareVersions("0.10.0", "0.9.0") > 0, true);
	assert.equal(compareVersions("1.0.0", "0.999.999") > 0, true);
	assert.equal(compareVersions("0.2.0", "0.2.0"), 0);
	assert.equal(compareVersions("0.2.0", "bogus"), 0, "unparseable compares equal, never newer");
});

test("needsRefresh fails open toward refreshing, never toward notifying", () => {
	assert.equal(needsRefresh(undefined, NOW), true, "no cache");
	assert.equal(needsRefresh({}, NOW), true, "no timestamp");
	assert.equal(needsRefresh({ lastCheckedAt: "not-a-date" }, NOW), true, "unparseable");
	assert.equal(
		needsRefresh({ lastCheckedAt: new Date(NOW - 25 * HOUR).toISOString() }, NOW),
		true,
		"older than the 24h TTL",
	);
	assert.equal(
		needsRefresh({ lastCheckedAt: new Date(NOW - HOUR).toISOString() }, NOW),
		false,
		"fresh",
	);
	assert.equal(
		needsRefresh({ lastCheckedAt: new Date(NOW + 48 * HOUR).toISOString() }, NOW),
		true,
		"a future timestamp is not treated as fresh",
	);
});

test("notice names both versions, the command, and the opt-out, with no ANSI", () => {
	const text = formatNotice("0.2.0", "0.3.0");
	assert.match(text, /0\.2\.0/);
	assert.match(text, /0\.3\.0/);
	assert.match(text, /ccl-skills update --yes/);
	assert.match(text, /CCL_SKILLS_NO_UPDATE_NOTIFIER/);
	// eslint-disable-next-line no-control-regex
	assert.equal(/\[/.test(text), false, "colour must not be the state carrier");
	for (const line of text.split("\n"))
		assert.equal(line.length <= 60, true, `line exceeds the 60-cell floor: ${line}`);
});

test("pickLatest accepts only a stable version string from dist-tags", () => {
	assert.equal(pickLatest({ "dist-tags": { latest: "0.3.0" } }), "0.3.0");
	assert.equal(pickLatest({ "dist-tags": {} }), null);
	assert.equal(pickLatest({}), null);
	assert.equal(pickLatest(null), null);
	assert.equal(pickLatest({ "dist-tags": { latest: 3 } }), null);
	assert.equal(pickLatest({ "dist-tags": { latest: "0.3.0-rc.1" } }), null, "prerelease");
	assert.equal(pickLatest({ "dist-tags": { latest: "../../etc/passwd" } }), null);
});

test("cache writes are atomic and leave no temp file behind", () => {
	const dir = mkdtempSync(join(tmpdir(), "ccl-notice-"));
	const target = join(dir, "version-check.json");
	const calls = [];
	const deps = {
		writeFileSync: (p, d, o) => {
			calls.push(["write", p]);
			return writeFileSync(p, d, o);
		},
		renameSync: (a, b) => {
			calls.push(["rename", a, b]);
			return renameSync(a, b);
		},
	};
	writeCacheAtomic(target, { latest: "0.3.0" }, deps);

	const [write, rename] = calls;
	assert.equal(write[0], "write");
	assert.notEqual(write[1], target, "must not write the target in place");
	assert.equal(rename[0], "rename");
	assert.equal(rename[2], target);
	assert.equal(
		write[1].startsWith(`${dir}/`),
		true,
		"temp file must live in the target directory so rename stays atomic",
	);
	assert.deepEqual(JSON.parse(readFileSync(target, "utf8")).latest, "0.3.0");
	assert.deepEqual(readdirSync(dir), ["version-check.json"], "no temp residue");
});

test("emitNotice writes to the side channel only, and records the cooldown", () => {
	const dir = mkdtempSync(join(tmpdir(), "ccl-notice-"));
	const file = join(dir, "version-check.json");
	const lines = [];
	let spawned = 0;
	const reason = emitNotice(eligible(), file, {
		stderr: (t) => lines.push(t),
		spawnCheck: () => spawned++,
	});

	assert.equal(reason, "update-available");
	assert.deepEqual(lines, [formatNotice("0.2.0", "0.3.0")]);
	assert.equal(spawned, 0, "a fresh cache needs no background check");
	const saved = JSON.parse(readFileSync(file, "utf8"));
	assert.equal(saved.notifiedVersion, "0.3.0");
	assert.equal(saved.latest, "0.3.0", "the refresh result must survive the cooldown write");
	assert.equal(Number.isNaN(Date.parse(saved.notifiedAt)), false);
});

test("emitNotice schedules the background check only when it is both stale and allowed", () => {
	const dir = mkdtempSync(join(tmpdir(), "ccl-notice-"));
	const file = join(dir, "version-check.json");
	const run = (overrides) => {
		let spawned = 0;
		emitNotice(eligible(overrides), file, { stderr: () => {}, spawnCheck: () => spawned++ });
		return spawned;
	};
	const stale = { latest: "0.3.0", lastCheckedAt: new Date(NOW - 25 * HOUR).toISOString() };
	assert.equal(run({ cache: stale }), 1, "stale cache refreshes");
	assert.equal(run({ cache: undefined }), 1, "absent cache refreshes");
	assert.equal(run({ cache: stale, env: { CI: "true" } }), 0, "never in CI");
	assert.equal(
		run({ cache: stale, env: { CCL_SKILLS_NO_UPDATE_NOTIFIER: "1" } }),
		0,
		"never when opted out",
	);
	assert.equal(run({ cache: stale, json: true }), 0, "never for --json");
});

test("emitNotice swallows every failure", () => {
	assert.doesNotThrow(() =>
		emitNotice(eligible(), "/nonexistent-root-dir-ccl/version-check.json", {
			stderr: () => {
				throw new Error("stream is gone");
			},
			spawnCheck: () => {
				throw new Error("spawn refused");
			},
		}),
	);
});

test("refresh stamps the check time even when the registry call fails", async () => {
	const dir = mkdtempSync(join(tmpdir(), "ccl-notice-"));
	const file = join(dir, "version-check.json");
	writeCacheAtomic(file, { latest: "0.2.0", notifiedVersion: "0.2.0", notifiedAt: "keep-me" });

	await refresh({
		file,
		now: NOW,
		fetchImpl: async () => {
			throw new Error("offline");
		},
	});
	let saved = JSON.parse(readFileSync(file, "utf8"));
	assert.equal(saved.lastCheckedAt, new Date(NOW).toISOString(), "no retry storm on failure");
	assert.equal(saved.latest, "0.2.0", "a failed check must not erase the known version");
	assert.equal(saved.notifiedVersion, "0.2.0", "cooldown survives a refresh");

	await refresh({
		file,
		now: NOW + HOUR,
		fetchImpl: async () => ({ ok: true, json: async () => ({ "dist-tags": { latest: "0.4.0" } }) }),
	});
	saved = JSON.parse(readFileSync(file, "utf8"));
	assert.equal(saved.latest, "0.4.0");
	assert.equal(saved.notifiedAt, "keep-me", "an unrelated field is preserved");
});

test("refresh ignores a non-ok response and an unusable payload", async () => {
	const dir = mkdtempSync(join(tmpdir(), "ccl-notice-"));
	const file = join(dir, "version-check.json");
	for (const fetchImpl of [
		async () => ({ ok: false, json: async () => ({ "dist-tags": { latest: "9.9.9" } }) }),
		async () => ({ ok: true, json: async () => ({ "dist-tags": { latest: "9.9.9-rc.1" } }) }),
		async () => ({ ok: true, json: async () => "not an object" }),
	]) {
		await refresh({ file, now: NOW, fetchImpl });
		assert.equal(JSON.parse(readFileSync(file, "utf8")).latest, undefined);
	}
});

test("the state directory is created, so a never-installed host still caches", () => {
	const dir = join(mkdtempSync(join(tmpdir(), "ccl-notice-")), "absent-root");
	const target = join(dir, "version-check.json");
	writeCacheAtomic(target, { latest: "0.3.0" });
	assert.equal(JSON.parse(readFileSync(target, "utf8")).latest, "0.3.0");
});

test("cache write failures are swallowed", () => {
	assert.doesNotThrow(() =>
		writeCacheAtomic("/nonexistent-root-dir-ccl/version-check.json", { latest: "0.3.0" }),
	);
});
