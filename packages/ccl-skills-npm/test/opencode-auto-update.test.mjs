import test from "node:test";
import assert from "node:assert/strict";
import { chmodSync, cpSync, existsSync, lstatSync, mkdirSync, mkdtempSync, readFileSync, readdirSync, realpathSync, rmSync, symlinkSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join, resolve } from "node:path";
import { createHash } from "node:crypto";
import { spawnSync } from "node:child_process";
import { pathToFileURL } from "node:url";
import { autoUpdate, runCommand, runScheduled } from "../dist/auto-update.js";
import { runOpenCode } from "../dist/opencode-adapter.js";

const assets = resolve("dist/assets"), sample = "skills/product-rd-workflow/SKILL.md";
const good = { code: 0, stdout: "", stderr: "" };
function fixture(t, install = true) {
	const temp = realpathSync(mkdtempSync(join(tmpdir(), "ccl-open-auto-")));
	t.after(() => rmSync(temp, { recursive: true, force: true }));
	const home = join(temp, "home ' & space"), bin = join(home, "bin"), base = join(home, ".config/opencode"), root = join(base, "ccl-skills-auto-update");
	mkdirSync(base, { recursive: true }); mkdirSync(bin);
	for (const name of ["opencode", "npm"]) writeFileSync(join(bin, name), "#!/bin/sh\necho 1.0.0\n", { mode: 0o755 });
	symlinkSync(process.execPath, join(bin, "node"));
	const env = { HOME: home, PATH: `${bin}:/usr/bin:/bin`, CODEX_HOME: join(home, "irrelevant"), CCL_SKILLS_REPO: "/not-allowed", NPM_CONFIG_REGISTRY: "https://invalid.example", NPM_TOKEN: "private-sentinel" };
	const context = { home, assets, env: { HOME: home, PATH: env.PATH } };
	if (install) assert.equal(runOpenCode("install", {}, context).status, "installed");
	const fetched = join(temp, "fetched");
	cpSync(resolve("dist"), join(fetched, "dist"), { recursive: true });
	// Model npm extraction, including files produced by a permissive-umask build.
	const normalizePackageModes = path => {
		const info = lstatSync(path);
		chmodSync(path, info.isDirectory() || (info.mode & 0o111) ? 0o755 : 0o644);
		if (info.isDirectory()) for (const entry of readdirSync(path)) normalizePackageModes(join(path, entry));
	};
	normalizePackageModes(fetched);
	const pkg = JSON.parse(readFileSync("package.json", "utf8"));
	pkg.version = "99.0.0"; writeFileSync(join(fetched, "package.json"), JSON.stringify(pkg));
	const releasePath = join(fetched, "dist/assets/release.json"), release = JSON.parse(readFileSync(releasePath, "utf8"));
	release.version = pkg.version;
	release.snapshotHash = createHash("sha256").update(JSON.stringify({ version: release.version, files: release.files })).digest("hex");
	writeFileSync(releasePath, JSON.stringify(release));
	const freshText = "# New registry skill content\n";
	writeFileSync(join(fetched, "dist/assets/marketplace/plugins/ccl-skills", sample), freshText);
	const calls = [], jobs = new Map();
	const command = async (file, args, childEnv, timeout, options) => {
		calls.push({ file, args, env: childEnv, timeout, options });
		if (file === "/bin/launchctl") {
			if (args[0] === "print") {
				const path = jobs.get(args[1].split("/").at(-1));
				return path ? { ...good, stdout: `path = ${path}\nstate = not running\n` } : { code: 113, stdout: "", stderr: "Could not find service" };
			}
			const label = args[2].split("/").at(-1).slice(0, -6);
			if (args[0] === "bootstrap") jobs.set(label, args[2]); else jobs.delete(label);
			return good;
		}
		if (file === join(bin, "npm")) {
			cpSync(fetched, join(args[args.indexOf("--prefix") + 1], "node_modules/@ccoalm/ccl-skills"), { recursive: true });
			return good;
		}
		return runCommand(file, args, childEnv, timeout, options);
	};
	return { temp, home, bin, base, root, env, fetched, context, calls, jobs, command, freshText,
		deps: { host: "opencode", env, platform: "darwin", command },
		manifest: () => JSON.parse(readFileSync(join(base, "ccl-skills-npm/install-manifest.json"), "utf8")),
		log: () => JSON.parse(readFileSync(join(root, "last-run.json"), "utf8")),
	};
}

test("OpenCode scheduled update uses fresh package content and preserves unrelated files", async t => {
	const f = fixture(t);
	const protectedFiles = [join(f.base, "opencode.json"), join(f.home, ".agents/skills/personal/SKILL.md"), join(f.base, "plugins/personal.ts")];
	for (const path of protectedFiles) { mkdirSync(dirname(path), { recursive: true }); writeFileSync(path, "personal sentinel"); }
	assert.equal((await autoUpdate("enable", f.deps)).code, 0);
	const result = await runScheduled(f.env, f.command, "opencode");
	assert.equal(result.code, 0, result.message);
	assert.equal(f.manifest().version, "99.0.0");
	assert.equal(f.manifest().sourceKind, "bundled");
	assert.equal(readFileSync(join(f.base, sample), "utf8"), f.freshText);
	for (const path of protectedFiles) assert.equal(readFileSync(path, "utf8"), "personal sentinel");
	assert.equal(existsSync(f.env.CODEX_HOME), false);
	assert.equal(f.log().status, "success");
	const npm = f.calls.find(call => call.file === join(f.bin, "npm"));
	assert.deepEqual(npm.args.filter(arg => arg.startsWith("--") || arg.startsWith("@")), ["--prefix", "--registry", "--userconfig", "--globalconfig", "--cache", "--ignore-scripts", "--no-bin-links", "--no-audit", "--no-fund", "--package-lock=false", "@ccoalm/ccl-skills@latest"]);
	assert.equal(npm.args[npm.args.indexOf("--registry") + 1], "https://registry.npmjs.org/");
	assert.equal(npm.options.cwd, npm.args[npm.args.indexOf("--prefix") + 1]);
	for (const call of f.calls) assert.deepEqual(Object.keys(call.env).sort(), ["CCL_SKILLS_NO_UPDATE_NOTIFIER", "CCL_SKILLS_SKIP_SELF_UPDATE", "HOME", "PATH"]);
	assert.deepEqual(readdirSync(f.root).filter(name => name.startsWith("refresh-")), []);
	assert.equal((await autoUpdate("disable", f.deps)).code, 0);
	assert.equal(f.jobs.size, 0);
	assert.equal((await runScheduled(f.env, f.command, "opencode")).status, "disabled");
});

for (const state of ["absent", "source-copy", "override", "drift"]) test(`OpenCode enable refuses ${state} without creating schedule`, async t => {
	const f = fixture(t, state !== "absent" && state !== "source-copy");
	if (state === "source-copy") { mkdirSync(join(f.base, "plugins")); writeFileSync(join(f.base, "plugins/ccl-skills.ts"), "source-copy"); }
	if (state === "override") { const manifest = f.manifest(); manifest.sourceKind = "override"; writeFileSync(join(f.base, "ccl-skills-npm/install-manifest.json"), JSON.stringify(manifest)); }
	if (state === "drift") writeFileSync(join(f.base, sample), "user change");
	const result = await autoUpdate("enable", f.deps);
	assert.equal(result.code, 5);
	assert.match(result.message, /healthy npm-managed bundled/);
	assert.equal(existsSync(f.root), false);
	assert.equal(f.jobs.size, 0);
});

for (const failure of ["fetch", "wrong-package", "symlink-package", "writable-package", "writable-file", "removed", "drift", "disabled"]) test(`OpenCode ${failure} before update preserves installed bytes`, async t => {
	const f = fixture(t), before = readFileSync(join(f.base, sample), "utf8");
	assert.equal((await autoUpdate("enable", f.deps)).code, 0);
	const command = async (file, args, env, timeout, options) => {
		if (file === join(f.bin, "npm")) {
			if (failure === "fetch") return { ...good, code: 1 };
			const result = await f.command(file, args, env, timeout, options);
			const pkgRoot = join(args[args.indexOf("--prefix") + 1], "node_modules/@ccoalm/ccl-skills");
			if (failure === "wrong-package") { const p = join(pkgRoot, "package.json"), value = JSON.parse(readFileSync(p, "utf8")); value.name = "unrelated"; writeFileSync(p, JSON.stringify(value)); }
			if (failure === "symlink-package") symlinkSync(f.temp, join(pkgRoot, "external"));
			if (failure === "writable-package") chmodSync(join(pkgRoot, "dist/assets"), 0o775);
			if (failure === "writable-file") chmodSync(join(pkgRoot, "dist/assets/release.json"), 0o664);
			if (failure === "removed") rmSync(join(f.base, "ccl-skills-npm"), { recursive: true });
			if (failure === "drift") writeFileSync(join(f.base, sample), "local edit");
			if (failure === "disabled") assert.equal((await autoUpdate("disable", f.deps)).code, 0);
			return result;
		}
		return f.command(file, args, env, timeout, options);
	};
	const result = await runScheduled(f.env, command, "opencode");
	assert.equal(result.code, 5, result.message);
	assert.equal(readFileSync(join(f.base, sample), "utf8"), failure === "drift" ? "local edit" : before);
	assert.equal(f.calls.some(call => call.args[1] === "update"), false);
	assert.equal(f.log().status, "failed");
	assert.deepEqual(readdirSync(f.root).filter(name => name.startsWith("refresh-")), []);
});

test("OpenCode retains a newer installed version", async t => {
	const f = fixture(t), manifest = f.manifest();
	manifest.version = "100.0.0"; writeFileSync(join(f.base, "ccl-skills-npm/install-manifest.json"), JSON.stringify(manifest));
	assert.equal((await autoUpdate("enable", f.deps)).code, 0);
	const result = await runScheduled(f.env, f.command, "opencode");
	assert.equal(result.code, 0, result.message);
	assert.match(result.message, /retains newer/);
	assert.equal(f.manifest().version, "100.0.0");
	assert.equal(f.calls.some(call => call.args[1] === "update"), false);
});

for (const fault of ["invalid-json", "bad-exit", "wrong-version", "override", "bad-status"]) test(`OpenCode post-doctor ${fault} cannot report success`, async t => {
	const f = fixture(t); let updated = false;
	assert.equal((await autoUpdate("enable", f.deps)).code, 0);
	const command = async (file, args, env, timeout, options) => {
		const result = await f.command(file, args, env, timeout, options);
		if (args[1] === "update") updated = true;
		if (updated && args[1] === "doctor") {
			if (fault === "invalid-json") return { ...good, stdout: "invalid" };
			const value = JSON.parse(result.stdout);
			if (fault === "wrong-version") value.details.version = "1.0.0";
			if (fault === "override") value.details.sourceKind = "override";
			if (fault === "bad-status") value.status = "absent";
			return { ...result, code: fault === "bad-exit" ? 1 : 0, stdout: JSON.stringify(value) };
		}
		return result;
	};
	const result = await runScheduled(f.env, command, "opencode");
	assert.equal(result.code, 5, result.message);
	assert.equal(f.log().status, "failed");
});

test("graceful command cancellation permits SIGINT cleanup", async t => {
	const temp = mkdtempSync(join(tmpdir(), "ccl-grace-")); t.after(() => rmSync(temp, { recursive: true, force: true }));
	const proof = join(temp, "cleanup");
	const result = await runCommand(process.execPath, ["-e", `process.on('SIGINT',()=>{require('node:fs').writeFileSync(${JSON.stringify(proof)},'rolled back');process.exit(130)});setInterval(()=>{},1000)`], {}, 500, { graceful: true });
	assert.equal(result.failure, "timeout");
	assert.equal(result.code, 130);
	assert.equal(readFileSync(proof, "utf8"), "rolled back");
});

test("graceful output cancellation keeps both buffers bounded", async () => {
	const result = await runCommand(process.execPath, ["-e", "process.on('SIGINT',()=>setTimeout(()=>process.exit(130),100));setInterval(()=>{process.stdout.write('x'.repeat(1048576));process.stderr.write('x'.repeat(65536))},1)"], {}, 2000, { graceful: true });
	assert.equal(result.failure, "output-limit");
	assert.ok(Buffer.byteLength(result.stdout) <= 4 * 1024 * 1024);
	assert.ok(Buffer.byteLength(result.stderr) <= 64 * 1024);
});

test("OpenCode saved runner executes independently using its absolute npm path", async t => {
	const f = fixture(t);
	writeFileSync(join(f.bin, "npm"), `#!${process.execPath}\nconst fs=require('node:fs'),path=require('node:path');const a=process.argv.slice(2);fs.cpSync(${JSON.stringify(f.fetched)},path.join(a[a.indexOf('--prefix')+1],'node_modules/@ccoalm/ccl-skills'),{recursive:true});\n`);
	assert.equal((await autoUpdate("enable", f.deps)).code, 0);
	const state = JSON.parse(readFileSync(join(f.root, "state.json"), "utf8"));
	assert.equal(state.npm, join(f.bin, "npm"));
	const result = await runCommand(state.node, [join(f.root, "runner.mjs"), "--run", "opencode"], { HOME: f.home, PATH: "/usr/bin:/bin" }, 20000);
	assert.equal(result.code, 0, result.stderr);
	assert.equal(f.manifest().version, "99.0.0");
	assert.equal(readFileSync(join(f.base, sample), "utf8"), f.freshText);
});

test("OpenCode and Codex schedules keep separate state and registration", async t => {
	const f = fixture(t); mkdirSync(f.env.CODEX_HOME);
	writeFileSync(join(f.bin, "codex"), "#!/bin/sh\nexit 0\n", { mode: 0o755 });
	const source = { sourceType: "git", source: "https://github.com/ccoalm/ccl-skills.git" };
	const command = async (file, args, env, timeout, options) => {
		if (file === join(f.bin, "codex")) return { ...good, stdout: JSON.stringify(args.includes("marketplace") ? { marketplaces: [{ name: "ccl-skills", marketplaceSource: source }] } : { installed: [{ pluginId: "ccl-skills@ccl-skills", marketplaceName: "ccl-skills", installed: true, enabled: true, source: { source: "git", url: source.source }, marketplaceSource: source }] }) };
		return f.command(file, args, env, timeout, options);
	};
	assert.equal((await autoUpdate("enable", f.deps)).code, 0);
	const codex = { ...f.deps, host: "codex", command };
	assert.equal((await autoUpdate("enable", codex)).code, 0);
	assert.equal(f.jobs.size, 2);
	assert.equal((await autoUpdate("disable", f.deps)).code, 0);
	assert.equal((await autoUpdate("status", codex)).status, "enabled");
	assert.equal(f.jobs.size, 1);
	assert.equal((await autoUpdate("disable", codex)).code, 0);
});

test("uncooperative graceful child reports forced unknown finality", async () => {
	const result = await runCommand(process.execPath, ["-e", "process.on('SIGINT',()=>{});setInterval(()=>{},1000)"], {}, 500, { graceful: true });
	assert.equal(result.failure, "timeout-forced-finality-unknown");
	assert.equal(result.code, null);
});

test("OpenCode package identity assertion rejects removal of its guard", t => {
	const scratch = mkdtempSync(join(tmpdir(), "ccl-open-mutant-"));
	t.after(() => rmSync(scratch, { recursive: true, force: true }));
	cpSync(resolve("dist"), join(scratch, "dist"), { recursive: true });
	cpSync(resolve("package.json"), join(scratch, "package.json"));
	mkdirSync(join(scratch, "test"));
	cpSync(resolve("test/opencode-auto-update.test.mjs"), join(scratch, "test/opencode-auto-update.test.mjs"));
	const env = { HOME: scratch, PATH: process.env.PATH };
	const args = ["--test", "--test-reporter=tap", "--test-name-pattern=^OpenCode wrong-package before update preserves installed bytes$", "test/opencode-auto-update.test.mjs"];
	const control = spawnSync(process.execPath, args, { cwd: scratch, env, encoding: "utf8", timeout: 30000 });
	assert.equal(control.status, 0, control.stdout + control.stderr);
	assert.match(control.stdout, /# pass 1\b/);
	const file = join(scratch, "dist/auto-update.js"), source = readFileSync(file, "utf8"), guard = "pkg.name !== PACKAGE || ";
	assert.equal(source.split(guard).length, 2);
	writeFileSync(file, source.replace(guard, ""));
	assert.equal(spawnSync(process.execPath, ["--check", file]).status, 0);
	const mutant = spawnSync(process.execPath, args, { cwd: scratch, env, encoding: "utf8", timeout: 30000 });
	assert.equal(mutant.status, 1, mutant.stdout + mutant.stderr);
	assert.match(mutant.stdout, /# fail 1\b/);
	assert.match(mutant.stdout, /ERR_ASSERTION/);
});

test("OpenCode signal at command boundary removes private refresh directory and lock", async t => {
	const f = fixture(t), before = readFileSync(join(f.base, sample), "utf8"), manifest = f.manifest();
	writeFileSync(join(f.bin, "npm"), `#!${process.execPath}\nconst fs=require('node:fs'),path=require('node:path');const a=process.argv.slice(2);fs.cpSync(${JSON.stringify(f.fetched)},path.join(a[a.indexOf('--prefix')+1],'node_modules/@ccoalm/ccl-skills'),{recursive:true});\n`);
	assert.equal((await autoUpdate("enable", f.deps)).code, 0);
	const moduleUrl = pathToFileURL(resolve("dist/auto-update.js")).href;
	const script = `import {runScheduled,runCommand} from ${JSON.stringify(moduleUrl)};
const before=['SIGINT','SIGTERM'].map(s=>process.listenerCount(s));let calls=[];
const result=await runScheduled(process.env,async (...args)=>{
 calls.push(args[1]);const result=await runCommand(...args);
 if(args[1][0]==='install'){process.kill(process.pid,'SIGTERM');await new Promise(setImmediate);}
 return result;
},'opencode');
console.log(JSON.stringify({result,calls,before,after:['SIGINT','SIGTERM'].map(s=>process.listenerCount(s))}));process.exitCode=result.code;`;
	const child = spawnSync(process.execPath, ["--input-type=module", "-e", script], { env: f.env, encoding: "utf8", timeout: 15000 });
	assert.deepEqual({ exit: child.status, signal: child.signal, lock: existsSync(join(f.root, "run.lock")), log: f.log().status, refresh: readdirSync(f.root).filter(name => name.startsWith("refresh-")).length }, { exit: 5, signal: null, lock: false, log: "failed", refresh: 0 }, child.stderr);
	const output = JSON.parse(child.stdout);
	assert.match(output.result.message, /interrupted/);
	assert.deepEqual(output.calls.map(args => args[0]), ["install"]);
	assert.deepEqual(output.after, output.before);
	assert.equal(f.log().status, "failed");
	assert.equal(existsSync(join(f.root, "run.lock")), false);
	assert.deepEqual(readdirSync(f.root).filter(name => name.startsWith("refresh-")), []);
	assert.equal(readFileSync(join(f.base, sample), "utf8"), before);
	assert.deepEqual(f.manifest(), manifest);
});

test("OpenCode real fetched CLI rolls back a write after scheduled SIGTERM", async t => {
	const f = fixture(t), manifest = f.manifest();
	const before = manifest.entries.map(entry => [entry.destination, readFileSync(join(f.base, entry.destination))]);
	const marker = join(f.temp, "copied"), ack = join(f.temp, "signal-ack"), preload = join(f.temp, "pause-copy.mjs");
	// Pause only after the actual shared rename; the CLI and worker stay unmodified.
	writeFileSync(preload, `import fs from 'node:fs';import {syncBuiltinESMExports} from 'node:module';import {isMainThread} from 'node:worker_threads';
if(isMainThread)process.on('SIGINT',()=>setImmediate(()=>fs.writeFileSync(${JSON.stringify(ack)},'received')));
else {const rename=fs.renameSync;let paused=false;fs.renameSync=(from,to)=>{rename(from,to);
 if(!paused && to===${JSON.stringify(join(f.base, sample))}){paused=true;fs.writeFileSync(${JSON.stringify(marker)},fs.readFileSync(to));
 const end=Date.now()+5000;while(!fs.existsSync(${JSON.stringify(ack)})){if(Date.now()>end)throw Error('signal acknowledgement timed out');Atomics.wait(new Int32Array(new SharedArrayBuffer(4)),0,0,10);}
 }};syncBuiltinESMExports();}`);
	writeFileSync(join(f.bin, "npm"), `#!${process.execPath}\nconst fs=require('node:fs'),path=require('node:path');const a=process.argv.slice(2);fs.cpSync(${JSON.stringify(f.fetched)},path.join(a[a.indexOf('--prefix')+1],'node_modules/@ccoalm/ccl-skills'),{recursive:true});\n`);
	assert.equal((await autoUpdate("enable", f.deps)).code, 0);
	const moduleUrl = pathToFileURL(resolve("dist/auto-update.js")).href;
	const script = `import {existsSync} from 'node:fs';import {runScheduled,runCommand} from ${JSON.stringify(moduleUrl)};
let update;const result=await runScheduled(process.env,async(file,args,env,timeout,options)=>{
 if(args[1]!=='update')return runCommand(file,args,env,timeout,options);
 const timer=setInterval(()=>{if(existsSync(${JSON.stringify(marker)})){clearInterval(timer);process.kill(process.pid,'SIGTERM');}},10);
 try{return update=await runCommand(file,['--import',${JSON.stringify(pathToFileURL(preload).href)},...args],env,timeout,options);}finally{clearInterval(timer);}
},'opencode');console.log(JSON.stringify({result,update}));process.exitCode=result.code;`;
	const child = spawnSync(process.execPath, ["--input-type=module", "-e", script], { env: f.env, encoding: "utf8", timeout: 20000 });
	assert.equal(child.signal, null, child.stderr);
	assert.equal(child.status, 5, child.stdout + child.stderr);
	const output = JSON.parse(child.stdout);
	assert.equal(readFileSync(marker, "utf8"), f.freshText);
	assert.equal(output.update.code, 130);
	assert.equal(output.update.failure, "interrupted");
	assert.equal(f.log().status, "failed");
	assert.deepEqual(f.manifest(), manifest, "interrupted update must preserve its previous manifest");
	for (const [destination, bytes] of before) assert.deepEqual(readFileSync(join(f.base, destination)), bytes, `rollback must restore ${destination}`);
	assert.equal(existsSync(join(f.root, "run.lock")), false);
	assert.deepEqual(readdirSync(f.root).filter(name => name.startsWith("refresh-")), []);
	assert.deepEqual(readdirSync(join(f.base, "ccl-skills-npm")).filter(name => name.startsWith(".rollback-") || name === ".shared-staging"), []);
});

test("scheduled rollback assertion detects missing worker cancellation propagation", t => {
	const scratch = mkdtempSync(join(tmpdir(), "ccl-open-abort-mutant-"));
	t.after(() => rmSync(scratch, { recursive: true, force: true }));
	cpSync(resolve("dist"), join(scratch, "dist"), { recursive: true });
	cpSync(resolve("package.json"), join(scratch, "package.json"));
	mkdirSync(join(scratch, "test"));
	cpSync(resolve("test/opencode-auto-update.test.mjs"), join(scratch, "test/opencode-auto-update.test.mjs"));
	const env = { HOME: scratch, PATH: process.env.PATH };
	const args = ["--test", "--test-reporter=tap", "--test-name-pattern=^OpenCode real fetched CLI rolls back a write after scheduled SIGTERM$", "test/opencode-auto-update.test.mjs"];
	const control = spawnSync(process.execPath, args, { cwd: scratch, env, encoding: "utf8", timeout: 30000 });
	assert.equal(control.status, 0, control.stdout + control.stderr);
	assert.match(control.stdout, /# pass 1\b/);
	const file = join(scratch, "dist/cli-worker.js"), source = readFileSync(file, "utf8"), guard = "Atomics.load(abort, 0) === 1";
	assert.equal(source.split(guard).length, 2);
	writeFileSync(file, source.replace(guard, "false"));
	assert.equal(spawnSync(process.execPath, ["--check", file]).status, 0);
	const mutant = spawnSync(process.execPath, args, { cwd: scratch, env, encoding: "utf8", timeout: 30000 });
	assert.equal(mutant.status, 1, mutant.stdout + mutant.stderr);
	assert.match(mutant.stdout, /# fail 1\b/);
	assert.match(mutant.stdout, /interrupted update must preserve its previous manifest/);
});
