import test from "node:test";
import assert from "node:assert/strict";
import { existsSync, mkdtempSync, mkdirSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import childProcess, { spawnSync } from "node:child_process";
import { syncBuiltinESMExports } from "node:module";
import { probeHostVersion } from "../dist/host-probe.js";
import { runHostSequence } from "../dist/unified.js";
import { manifestFor, readManifest } from "../dist/manifest.js";

function ownedClaudeReceipt(home) {
	const root = join(home, ".claude/ccl-skills-npm"), path = join(root, "install-manifest.json");
	const release = JSON.parse(readFileSync("dist/assets/release.json", "utf8"));
	mkdirSync(root, { recursive: true });
	const content = JSON.stringify(manifestFor(release, `snapshots/${release.snapshotHash}`, null));
	writeFileSync(path, content);
	assert.notEqual(readManifest(path), null);
	return { path, content };
}

const cases = [
	["default discovery", "claude", ["update", "--json"], true],
	["Claude install", "claude", ["install", "--host", "claude", "--json"]],
	["OpenCode install", "opencode", ["install", "--host", "opencode", "--json"]],
	["Codex doctor", "codex", ["doctor", "--host", "codex", "--json"]],
];

for (const [name, host, args, owned] of cases) {
	test(`${name} kills a stalled version probe without waiting for its late effect`, () => {
		const root = mkdtempSync(join(tmpdir(), "ccl-probe-timeout-"));
		const bin = join(root, "bin"), home = join(root, "home");
		mkdirSync(bin); mkdirSync(home);
		const receipt = owned ? ownedClaudeReceipt(home) : null;
		const pidPath = join(root, "pid"), late = join(root, "late"), mutation = join(root, "mutation");
		writeFileSync(join(bin, host), `#!${process.execPath}
const fs = require('node:fs');
if (process.argv[2] !== '--version') {
  fs.writeFileSync(${JSON.stringify(mutation)}, process.argv.slice(2).join(' '));
  process.exit(2);
}
process.on('SIGTERM', () => {});
fs.writeFileSync(${JSON.stringify(pidPath)}, String(process.pid));
setTimeout(() => {
  fs.writeFileSync(${JSON.stringify(late)}, 'late version probe effect');
  console.log('1.0.0');
  process.exit(0);
}, 15000);
`, { mode: 0o755 });
		try {
			const start = performance.now();
			const child = spawnSync(process.execPath, ["dist/cli.js", ...args], {
				encoding: "utf8", timeout: 25000, killSignal: "SIGKILL",
				env: { HOME: home, CODEX_HOME: join(home, ".codex"), PATH: bin },
			});
			const elapsed = performance.now() - start;
			assert.equal(child.error, undefined, child.error?.message);
			assert.equal(child.status, 4, child.stderr || child.stdout);
			assert.ok(elapsed < 13500, `version probe took ${elapsed}ms`);
			assert.equal(existsSync(late), false, "probe performed its late effect");
			assert.equal(existsSync(mutation), false, "host commands ran after the failed probe");
			for (const path of [".claude/ccl-skills-npm/install-manifest.json", ".config/opencode/ccl-skills-npm/install-manifest.json", ".codex/ccl-skills-npm/install-manifest.json"])
				assert.equal(existsSync(join(home, path)), join(home, path) === receipt?.path, "failed probe changed receipt presence");
			if (receipt) assert.equal(readFileSync(receipt.path, "utf8"), receipt.content, "failed probe refreshed an owned receipt");
			const pid = Number(readFileSync(pidPath, "utf8"));
			assert.throws(() => process.kill(pid, 0), { code: "ESRCH" }, "probe remains alive");
			const result = JSON.parse(child.stdout);
			assert.equal(result.code, 4);
			assert.equal(result.status, "host-timeout");
			assert.match(result.message, /timed out/i);
		} finally {
			rmSync(root, { recursive: true, force: true });
		}
	});
}

function mixedFixture(t, { ownedClaude = false, openCodeMissing = false, probeFailure = "ETIMEDOUT", failingHost = "claude" } = {}) {
	const root = mkdtempSync(join(tmpdir(), "ccl-mixed-probes-"));
	t.after(() => rmSync(root, { recursive: true, force: true }));
	const home = join(root, "home"), bin = join(root, "bin"), preload = join(root, "probe.cjs"), npmMarker = join(root, "npm-called"), calls = join(root, "calls");
	mkdirSync(home); mkdirSync(bin);
	// Inject only subprocess outcomes. The actual CLI, worker, selection,
	// adapters, manifest checks, aggregation, and self-update preflight run.
	writeFileSync(preload, `const cp = require('node:child_process');
const fs = require('node:fs');
cp.spawnSync = (command, args) => {
  fs.appendFileSync(${JSON.stringify(calls)}, command + ' ' + args.join(' ') + '\\n');
  if (command === 'npm') {
    fs.writeFileSync(${JSON.stringify(npmMarker)}, 'synthetic npm invocation');
    return {status: 42, stdout: '', stderr: 'synthetic npm failure'};
  }
  if (args[0] === '--version') {
    if (command === (process.env.FAILING_HOST || 'claude') && process.env.OPEN_CODE_MISSING !== '1') {
      if (process.env.PROBE_FAILURE === 'EXIT_2') return {status: 2, stdout: '', stderr: 'synthetic version failure'};
      const code = process.env.PROBE_FAILURE || 'ETIMEDOUT';
      return {status: null, error: Object.assign(new Error(code), {code}), stdout: '', stderr: ''};
    }
    if (command === 'opencode' && process.env.OPEN_CODE_MISSING !== '1') return {status: 0, stdout: '1.0.0', stderr: ''};
    const code = 'ENOENT';
    return {status: null, error: Object.assign(new Error(code), {code}), stdout: '', stderr: ''};
  }
  return {status: 1, stdout: '', stderr: 'unexpected synthetic host command'};
};
require('node:module').syncBuiltinESMExports();
`);
	const env = { HOME: home, CODEX_HOME: join(home, ".codex"), PATH: bin, CI: "1", NODE_OPTIONS: `--require ${JSON.stringify(preload)}` };
	const run = (args, extra = {}) => {
		// This bound includes installing the full asset bundle; probe timing is
		// asserted separately above with an actual stalled child process.
		const child = spawnSync(process.execPath, ["dist/cli.js", ...args, "--json"], { encoding: "utf8", timeout: 60000, env: { ...env, ...extra } });
		assert.equal(child.error, undefined, child.error?.message);
		return { code: child.status, result: JSON.parse(child.stdout) };
	};
	assert.equal(run(["install", "--host", "opencode"]).code, 0);
	if (ownedClaude) ownedClaudeReceipt(home);
	writeFileSync(calls, "");
	return { run: (args) => run(args, { PROBE_FAILURE: probeFailure, FAILING_HOST: failingHost, ...(openCodeMissing ? { OPEN_CODE_MISSING: "1" } : {}) }), home, npmMarker, calls };
}

test("version observation distinguishes absent, timeout, and execution failure", (t) => {
	let outcome;
	const stub = t.mock.method(childProcess, "spawnSync", () => outcome);
	syncBuiltinESMExports();
	try {
		for (const code of ["ENOENT", "ETIMEDOUT", "EACCES", "EMFILE", "ENOMEM"]) {
			outcome = { status: null, error: Object.assign(new Error(code), { code }), stdout: "", stderr: "" };
			const result = probeHostVersion("synthetic", {});
			assert.equal(result.kind, code === "ENOENT" ? "missing" : code === "ETIMEDOUT" ? "timeout" : "probe-failed", code);
			if (!["ENOENT", "ETIMEDOUT"].includes(code)) assert.match(result.message, new RegExp(code));
		}
		for (const result of [{ status: 2 }, { status: null, signal: "SIGTERM" }]) {
			outcome = { ...result, stdout: "", stderr: "" };
			assert.equal(probeHostVersion("synthetic", {}).kind, "probe-failed");
		}
		outcome = { status: 0, stdout: "1.0.0", stderr: "" };
		assert.equal(probeHostVersion("synthetic", {}).ok, true);
	} finally {
		stub.mock.restore();
		syncBuiltinESMExports();
	}
});

for (const host of ["claude", "codex", "opencode"]) {
	test(`version observation failure stays explicit in selected ${host} adapter`, (t) => {
		const f = mixedFixture(t, { ownedClaude: true, probeFailure: "EACCES", failingHost: host });
		const { code, result } = f.run(["doctor", "--host", host]);
		assert.equal(code, 4);
		assert.equal(result.status, "host-probe-failed");
		assert.match(result.message, /EACCES/);
		assert.match(readFileSync(f.calls, "utf8"), new RegExp(`^${host} --version\\n$`));
	});
}

for (const [command, ownedClaude, probeFailure] of [["install", false, "EACCES"], ["update", true, "EXIT_2"]]) {
	test(`version observation failure in mixed ${command} retains the failed host`, (t) => {
		const f = mixedFixture(t, { ownedClaude, probeFailure });
		const { code, result } = f.run([command]);
		assert.equal(code, 4);
		assert.equal(result.status, "multi-host-partial");
		assert.equal(result.details.hosts.claude.status, "host-probe-failed");
		assert.equal(result.details.hosts.opencode.code, 0);
	});
}

test("version observation true absence remains optional beside a healthy host", (t) => {
	const f = mixedFixture(t, { probeFailure: "ENOENT" });
	assert.equal(f.run(["install"]).code, 0);
});

test("version observation failure does not select an unowned host for update", (t) => {
	const f = mixedFixture(t, { probeFailure: "EACCES" });
	assert.equal(f.run(["update"]).code, 0);
	assert.doesNotMatch(readFileSync(f.calls, "utf8"), /claude/);
});

test("version observation failure prevents owned update npm self-update", (t) => {
	const f = mixedFixture(t, { ownedClaude: true, probeFailure: "EMFILE" });
	const { code, result } = f.run(["update", "--yes"]);
	assert.equal(code, 4);
	assert.equal(result.details.hosts.claude.status, "host-probe-failed");
	assert.equal(existsSync(f.npmMarker), false);
});

for (const [command, ownedClaude] of [["update", true], ["install", false]]) {
	test(`mixed host ${command} retains a timed-out selected host and completes the healthy host`, (t) => {
		const f = mixedFixture(t, { ownedClaude });
		const { code, result } = f.run([command]);
		assert.equal(code, 4);
		assert.equal(result.status, "multi-host-partial");
		assert.equal(result.details.hosts.claude.status, "host-timeout");
		assert.equal(result.details.hosts.opencode.code, 0);
	});
}

test("mixed host update excludes an unowned timed-out host", (t) => {
	const f = mixedFixture(t);
	const { code, result } = f.run(["update"]);
	assert.equal(code, 0);
	assert.equal(result.status, "healthy");
	assert.doesNotMatch(readFileSync(f.calls, "utf8"), /claude/);
});

test("selected host update ignores another owned host timeout", (t) => {
	const f = mixedFixture(t, { ownedClaude: true });
	assert.equal(f.run(["update", "--host", "opencode"]).code, 0);
	assert.doesNotMatch(readFileSync(f.calls, "utf8"), /claude/);
});

test("selected host update preserves its own timeout", (t) => {
	const f = mixedFixture(t, { ownedClaude: true });
	const { code, result } = f.run(["update", "--host", "claude"]);
	assert.equal(code, 4);
	assert.equal(result.status, "host-timeout");
	assert.doesNotMatch(readFileSync(f.calls, "utf8"), /opencode/);
});

for (const [command, expectedCode, expectedStatus] of [["doctor", 4, "host-missing"], ["uninstall", 0, "dry-run"]]) {
	test(`mixed host ${command} keeps owned missing-host handling in its adapter`, (t) => {
		const f = mixedFixture(t, { openCodeMissing: true });
		const { code, result } = f.run([command]);
		assert.equal(code, expectedCode);
		assert.equal(result.status, expectedStatus);
		assert.equal(existsSync(join(f.home, ".config/opencode/ccl-skills-npm/install-manifest.json")), true);
	});
}

test("mixed host update --yes cannot self-update npm after an owned timeout", (t) => {
	const f = mixedFixture(t, { ownedClaude: true });
	const { code, result } = f.run(["update", "--yes"]);
	assert.equal(code, 4);
	assert.equal(result.status, "multi-host-partial");
	assert.equal(existsSync(f.npmMarker), false);
});

test("selected host update --yes reaches npm after its healthy preflight", (t) => {
	const f = mixedFixture(t, { ownedClaude: true });
	const { code, result } = f.run(["update", "--host", "opencode", "--yes"]);
	assert.equal(code, 5);
	assert.equal(result.status, "package-update-failed");
	assert.equal(existsSync(f.npmMarker), true);
	assert.doesNotMatch(readFileSync(f.calls, "utf8"), /claude/);
});

for (const code of [5, 130]) {
	test(`mixed host timeout preserves terminal code ${code} and stops later hosts`, () => {
		const called = [];
		const result = runHostSequence(["claude", "codex", "opencode"], (host) => {
			called.push(host);
			return host === "claude"
				? { code: 4, status: "host-timeout", message: "synthetic timeout" }
				: { code, status: "partial", message: "synthetic terminal result" };
		});
		assert.equal(result.code, code);
		assert.deepEqual(called, ["claude", "codex"]);
	});
}
