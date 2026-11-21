import test from "node:test";
import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { createHash } from "node:crypto";
import { appendFileSync, cpSync, existsSync, mkdirSync, mkdtempSync, readdirSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { runAntigravity } from "../dist/antigravity-adapter.js";

const assets = join(process.cwd(), "dist/assets"), plugin = join(assets, "marketplace/plugins/ccl-skills");

test("Antigravity bridge binding inventory covers every command hook", () => {
	const manifest = JSON.parse(readFileSync(join(plugin, "hooks/hooks.json"), "utf8"));
	const scripts = new Set(Object.values(manifest.hooks).flatMap((groups) => groups).flatMap((group) => group.hooks)
		.map((hook) => hook.command.match(/hooks\/([^"/\s]+\.sh)/)?.[1]).filter(Boolean));
	const printed = spawnSync("python3", ["-I", join(plugin, "hooks/agy-bridge.py"), "--bindings"], { encoding: "utf8" });
	assert.equal(printed.status, 0, printed.stderr);
	assert.deepEqual(Object.keys(JSON.parse(printed.stdout)).sort(), [...scripts].sort());
});

test("Packaged plugin carries the native Antigravity manifest and hook file", () => {
	const native = JSON.parse(readFileSync(join(plugin, ".antigravity-plugin/plugin.json"), "utf8"));
	assert.equal(native.name, "ccl-skills");
	assert.equal("version" in native, false);
	const hooks = JSON.parse(readFileSync(join(plugin, "hooks.json"), "utf8"))["ccl-skills"];
	assert.deepEqual(Object.keys(hooks).sort(), ["PostToolUse", "PreInvocation", "PreToolUse", "SessionStart", "Stop"]);
	assert.equal(existsSync(join(plugin, "hooks/agy-bridge.py")), true);
});

function fixture() {
	const root = mkdtempSync(join(tmpdir(), "ccl-agy-npm-")), bin = join(root, "bin"), home = join(root, "home");
	mkdirSync(bin); mkdirSync(home);
	writeFileSync(join(bin, "agy"), `#!/bin/sh
echo "$*" >> "$FAKE_AGY_LOG"
dest="$HOME/.gemini/config/plugins/ccl-skills"
case "$1 $2" in
  "--version "*) echo 1.5.14 ;;
  "plugin list") if [ -n "$FAKE_AGY_BAD_LIST" ]; then echo '[{"path":"x"}]'; exit 0; fi
    enabled=true; if [ -n "$FAKE_AGY_DISABLED" ]; then enabled=false; fi
    if [ -d "$dest" ] && [ -z "$FAKE_AGY_UNLISTED" ]; then printf '[{"name":"ccl-skills","enabled":%s,"source":"antigravity","path":"%s"}]\\n' "$enabled" "$dest"; else echo '[]'; fi ;;
  "plugin install") if [ -n "$FAKE_AGY_FAIL_INSTALL" ]; then echo boom >&2; exit 9; fi
    rm -rf "$dest"; mkdir -p "$(dirname "$dest")"; cp -a "$3" "$dest"
    if [ -n "$FAKE_AGY_FAIL_AFTER_INSTALL" ] && [ ! -e "$FAKE_AGY_LOG.failed-once" ]; then : > "$FAKE_AGY_LOG.failed-once"; echo "boom after copy" >&2; exit 9; fi ;;
  "plugin uninstall") rm -rf "$dest" ;;
  *) exit 2 ;;
esac
`, { mode: 0o755 });
	const env = { ...process.env, HOME: home, PATH: `${bin}:${process.env.PATH}`, FAKE_AGY_LOG: join(root, "calls"),
		FAKE_AGY_FAIL_INSTALL: "", FAKE_AGY_FAIL_AFTER_INSTALL: "", FAKE_AGY_DISABLED: "", FAKE_AGY_UNLISTED: "", FAKE_AGY_BAD_LIST: "" };
	const run = (command, options = {}, extra = {}, assetDir = assets) => runAntigravity(command, options, { home, assets: assetDir, env: { ...env, ...extra } });
	return { root, home, env, run, installed: join(home, ".gemini/config/plugins/ccl-skills"),
		managed: join(home, ".gemini/ccl-skills-npm"), calls: () => existsSync(env.FAKE_AGY_LOG) ? readFileSync(env.FAKE_AGY_LOG, "utf8") : "" };
}

function release(f, version) {
	const dir = join(f.root, `assets-${version}`);
	cpSync(assets, dir, { recursive: true });
	const r = JSON.parse(readFileSync(join(dir, "release.json"), "utf8"));
	r.version = version;
	r.snapshotHash = createHash("sha256").update(JSON.stringify({ version, files: r.files })).digest("hex");
	writeFileSync(join(dir, "release.json"), JSON.stringify(r));
	return dir;
}
const receiptOf = (f) => JSON.parse(readFileSync(join(f.managed, "install-receipt.json"), "utf8"));
const backups = (f) => readdirSync(join(f.home, ".gemini")).filter((name) => name.startsWith(".ccl-skills-backup-"));

test("Antigravity install, doctor, uninstall preview and uninstall round-trip", () => {
	const f = fixture();
	assert.equal(f.run("doctor").status, "absent");
	const installed = f.run("install");
	assert.equal(installed.code, 0, installed.message);
	assert.equal(installed.status, "installed");
	assert.equal(existsSync(join(f.installed, "hooks.json")), true);
	assert.equal(f.run("doctor").status, "healthy");
	assert.equal(f.run("install").status, "healthy");
	assert.equal(f.run("uninstall").status, "dry-run");
	assert.equal(existsSync(f.installed), true);
	const removed = f.run("uninstall", { yes: true });
	assert.equal(removed.status, "uninstalled", removed.message);
	assert.equal(existsSync(f.installed), false);
	assert.equal(existsSync(f.managed), false);
});

test("Antigravity refuses to replace or remove a plugin npm did not install", () => {
	const f = fixture();
	mkdirSync(join(f.installed, ".antigravity-plugin"), { recursive: true });
	writeFileSync(join(f.installed, ".antigravity-plugin/plugin.json"), '{"name":"ccl-skills"}');
	writeFileSync(join(f.installed, "LOCAL_EDIT"), "local work");
	assert.equal(f.run("install").status, "unowned-registration");
	assert.equal(f.run("uninstall", { yes: true }).status, "unowned-registration");
	assert.equal(f.run("doctor").status, "unowned-registration");
	assert.equal(readFileSync(join(f.installed, "LOCAL_EDIT"), "utf8"), "local work");
	assert.doesNotMatch(f.calls(), /plugin (install|uninstall)/);
});

test("Antigravity detects a drifted install and will not replace or remove it", () => {
	const f = fixture();
	assert.equal(f.run("install").status, "installed");
	appendFileSync(join(f.installed, "hooks.json"), "\n");
	assert.equal(f.run("doctor").status, "public-state-mismatch");
	assert.equal(f.run("uninstall", { yes: true }).status, "public-state-mismatch");
	assert.equal(f.run("update", { yes: true, allowDowngrade: true }, {}, release(f, "1.0.0")).status, "public-state-mismatch");
	assert.equal(existsSync(f.installed), true);
});

test("Antigravity install failure before any host change reports rolled-back and leaves nothing", () => {
	const f = fixture();
	const result = f.run("install", {}, { FAKE_AGY_FAIL_INSTALL: "1" });
	assert.equal(result.status, "rolled-back", result.message);
	assert.equal(existsSync(f.installed), false);
	assert.equal(existsSync(join(f.managed, "install-receipt.json")), false);
	assert.equal(existsSync(join(f.managed, "operation-journal.json")), false);
});

test("Antigravity compensates a host install that changed state and then failed", () => {
	const f = fixture();
	const result = f.run("install", {}, { FAKE_AGY_FAIL_AFTER_INSTALL: "1" });
	assert.equal(result.code, 1, result.message);
	assert.equal(result.status, "rolled-back");
	assert.equal(existsSync(f.installed), false, "the copied plugin must be removed");
	assert.match(f.calls(), /plugin uninstall ccl-skills/);
	assert.equal(f.run("doctor").status, "absent");
});

test("Antigravity update, downgrade and failed update keep a healthy owned install", () => {
	const f = fixture(), a = release(f, "90.0.0"), b = release(f, "90.0.1");
	assert.equal(f.run("install", {}, {}, a).status, "installed");
	assert.equal(f.run("update", {}, {}, b).status, "dry-run");
	assert.equal(f.run("update", { yes: true }, {}, b).status, "updated");
	assert.equal(receiptOf(f).version, "90.0.1");
	assert.equal(f.run("doctor", {}, {}, b).status, "healthy");
	assert.equal(f.run("update", { yes: true }, {}, a).status, "downgrade-refused");
	const down = f.run("update", { yes: true, allowDowngrade: true }, {}, a);
	assert.equal(down.status, "updated", down.message);
	assert.equal(receiptOf(f).version, "90.0.0");
	assert.equal(f.run("doctor", {}, {}, a).status, "healthy");
	const failed = f.run("update", { yes: true }, { FAKE_AGY_FAIL_AFTER_INSTALL: "1" }, b);
	assert.equal(failed.status, "rolled-back", failed.message);
	assert.match(f.calls().split("\n").filter((line) => line.startsWith("plugin install")).at(-1), /\.ccl-skills-backup-/, "rollback reinstalls from the backup");
	assert.equal(receiptOf(f).version, "90.0.0", "rollback keeps the prior receipt");
	assert.equal(f.run("doctor", {}, {}, a).status, "healthy", "rollback restores the prior install");
	assert.deepEqual(backups(f), [], "update backups are removed once the outcome is settled");
	assert.deepEqual(readdirSync(f.managed), ["install-receipt.json"]);
});

test("Antigravity reconciles an operation that died between host install and receipt commit", () => {
	const f = fixture();
	assert.equal(f.run("install").status, "installed");
	rmSync(join(f.managed, "install-receipt.json"));
	writeFileSync(join(f.managed, "operation-journal.json"), JSON.stringify({ schema: 1, operation: "install", version: "x" }));
	assert.equal(f.run("doctor").status, "recovery-pending");
	assert.equal(f.run("uninstall").status, "recovery-pending", "a preview never mutates recovery state");
	assert.equal(existsSync(join(f.managed, "operation-journal.json")), true);
	assert.equal(f.run("install").status, "healthy");
	assert.equal(existsSync(join(f.managed, "operation-journal.json")), false);
});

test("A journal never makes a hand-installed plugin look npm-owned", () => {
	const f = fixture();
	mkdirSync(join(f.installed, ".antigravity-plugin"), { recursive: true });
	writeFileSync(join(f.installed, ".antigravity-plugin/plugin.json"), '{"name":"ccl-skills"}');
	writeFileSync(join(f.installed, "LOCAL"), "local");
	mkdirSync(f.managed, { recursive: true });
	writeFileSync(join(f.managed, "operation-journal.json"), JSON.stringify({ schema: 1, operation: "install", intended: { forged: true } }));
	assert.equal(f.run("install").status, "state-unknown");
	assert.equal(f.run("uninstall", { yes: true }).status, "state-unknown");
	assert.equal(readFileSync(join(f.installed, "LOCAL"), "utf8"), "local");
	assert.doesNotMatch(f.calls(), /plugin (install|uninstall)/);
});

test("Antigravity never adopts an unmanaged root or an unlisted plugin directory", () => {
	for (const entry of ["notes.txt", "snapshots/backup/keep"]) {
		const f = fixture(), target = join(f.managed, entry);
		mkdirSync(join(target, ".."), { recursive: true });
		writeFileSync(target, "mine");
		assert.equal(f.run("install").status, "safety-refusal", entry);
		assert.equal(readFileSync(target, "utf8"), "mine", entry);
	}
	const g = fixture();
	mkdirSync(g.installed, { recursive: true });
	writeFileSync(join(g.installed, "LOCAL"), "local");
	assert.equal(g.run("install", {}, { FAKE_AGY_UNLISTED: "1" }).status, "unowned-registration");
	assert.equal(readFileSync(join(g.installed, "LOCAL"), "utf8"), "local");
	assert.doesNotMatch(g.calls(), /plugin install/);
});

test("Antigravity install waits for the shared installer lock", () => {
	const f = fixture();
	mkdirSync(join(f.home, ".gemini"), { recursive: true });
	writeFileSync(join(f.home, ".gemini/ccl-skills-plugin.lock"), "");
	assert.equal(f.run("install").status, "busy");
	assert.doesNotMatch(f.calls(), /plugin install/);
});

test("Antigravity reports a disabled plugin and rejects a malformed host list", () => {
	const f = fixture();
	assert.equal(f.run("install").status, "installed");
	assert.equal(f.run("doctor", {}, { FAKE_AGY_DISABLED: "1" }).status, "disabled");
	assert.equal(f.run("doctor", {}, { FAKE_AGY_BAD_LIST: "1" }).status, "safety-refusal");
});

test("Antigravity reports a missing agy CLI as host-missing", () => {
	const f = fixture();
	const result = runAntigravity("doctor", {}, { home: f.home, assets, env: { ...f.env, PATH: "/nonexistent" } });
	assert.equal(result.code, 4);
	assert.equal(result.status, "host-missing");
});
