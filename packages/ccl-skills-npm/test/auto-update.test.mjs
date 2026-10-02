import test from "node:test";
import assert from "node:assert/strict";
import { parseArgs } from "../dist/cli.js";

test("auto-update parser accepts explicit actions and JSON without changing update preview", () => {
	for (const action of ["enable", "disable", "status"]) {
		const parsed = parseArgs(["auto-update", action, "--json"]);
		assert.equal(parsed.direct, undefined);
		assert.equal(parsed.autoUpdateAction, action);
		assert.equal(parsed.json, true);
	}
	assert.equal(parseArgs(["update"]).options.yes, false);
});

import { autoUpdate, runScheduled, runCommand } from "../dist/auto-update.js";
import { spawnSync } from "node:child_process";
import { mkdtempSync, mkdirSync, readFileSync, writeFileSync, existsSync, readdirSync, rmSync, symlinkSync, linkSync, realpathSync, cpSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { createHash } from "node:crypto";
import { pathToFileURL } from "node:url";

const gitSource = "https://github.com/ccoalm/ccl-skills.git";
function fixture(t, options = {}) {
	const temp = realpathSync(mkdtempSync(join(tmpdir(), "ccl-auto-")));
	t.after(() => rmSync(temp, { recursive: true, force: true }));
	const home = join(temp, "home ' & <xml>"), codexHome = join(home, "profile with spaces"), bin = join(home, "bin"), calls = join(temp, "calls.jsonl"), control = join(temp, "control.json");
	mkdirSync(codexHome, { recursive: true }); mkdirSync(bin);
	writeFileSync(control, JSON.stringify(options));
	const codex = join(bin, "codex");
	writeFileSync(codex, `#!${process.execPath}
const fs = require('node:fs');
const args = process.argv.slice(2);
fs.appendFileSync(${JSON.stringify(calls)}, JSON.stringify({args, env: process.env})+'\\n');
const config = JSON.parse(fs.readFileSync(${JSON.stringify(control)}, 'utf8'));
const source = config.source || ${JSON.stringify(gitSource)};
const market = {name:'ccl-skills',root: ${JSON.stringify(join(codexHome, "market"))},marketplaceSource:{sourceType:config.sourceType || 'git',source}};
if(args.includes('--json')) {
 if(config.invalidJson) { process.stdout.write('invalid'); process.exit(0); }
 if(args.includes('marketplace')) console.log(JSON.stringify({marketplaces:config.missing ? [] : config.duplicate ? [market,market] : [market]}));
 else console.log(JSON.stringify({installed:[{pluginId:'ccl-skills@ccl-skills',name:'ccl-skills',marketplaceName:'ccl-skills',installed:true,enabled:!config.disabled,source:{source:"git",url:config.pluginSource || source},marketplaceSource:market.marketplaceSource}],available:[]}));
} else if(args.includes('upgrade')) { process.exitCode=config.upgradeExit || 0; }
else if(args.includes('add')) { process.exitCode=config.addExit || 0; }
else process.exitCode=7;
`, { mode: 0o755 });
	symlinkSync(process.execPath, join(bin, "node"));
	let registered = null, registrationFailure = false, bootstrapFailure = false, bootstrapRunner = false, lastExit = 0, bootstrapCount = 0, foreign = null, unloadFailure = false;
	const env = { HOME: home, CODEX_HOME: codexHome, PATH: `${bin}:/usr/bin:/bin`, SECRET_SHOULD_NOT_PERSIST: "secret-sentinel" };
	const root = join(codexHome, "ccl-skills-auto-update");
	const command = async (file, args, childEnv, timeout) => {
		if (file !== "/bin/launchctl") return runCommand(file, args, childEnv, timeout);
		if (args[0] === "print") return registrationFailure ? { code: 1, stdout: "", stderr: "permission denied" } : registered || foreign ? { code: 0, stdout: `path = ${foreign || registered}\nstate = not running\nlast exit code = ${lastExit}\n`, stderr: "" } : { code: 113, stdout: "", stderr: "Could not find service in domain for user gui" };
		if (args[0] === "bootstrap") {
			bootstrapCount++;
			if (bootstrapFailure) return { code: 5, stdout: "", stderr: "bootstrap failed" };
			registered = args[2];
			if (bootstrapRunner) {
				const state = JSON.parse(readFileSync(join(root, "state.json"), "utf8"));
				lastExit = spawnSync(state.node, [join(root, "runner.mjs"), "--run"], { env: childEnv, encoding: "utf8" }).status;
			}
			return { code: 0, stdout: "", stderr: "" };
		}
		if (unloadFailure) return { code: 5, stdout: "", stderr: "unload failed" };
		registered = null;
		return { code: 0, stdout: "", stderr: "" };
	};
	return { home, codexHome, root, bin, env, control, command,
		deps: { env, platform: "darwin", command },
		calls: () => existsSync(calls) ? readFileSync(calls, "utf8").trim().split("\n").filter(Boolean).map(JSON.parse) : [],
		state: () => JSON.parse(readFileSync(join(root, "state.json"), "utf8")),
		log: () => JSON.parse(readFileSync(join(root, "last-run.json"), "utf8")),
		plist: () => registered || join(home, "Library", "LaunchAgents", readdirSync(join(home, "Library", "LaunchAgents"))[0]),
		set bootstrapRunner(v) { bootstrapRunner = v; }, set bootstrapFailure(v) { bootstrapFailure = v; }, set registrationFailure(v) { registrationFailure = v; }, set lastExit(v) { lastExit = v; }, set foreign(v) { foreign = v; }, set unloadFailure(v) { unloadFailure = v; },
		get bootstrapCount() { return bootstrapCount; }, get registered() { return registered; },
	};
}

test("auto-update parser rejects omitted actions and unrelated flags", () => {
	for (const args of [[], ["enable", "--yes"], ["status", "--host", "claude"], ["run"], ["enable", "--json", "--json"]]) {
		assert.equal(parseArgs(["auto-update", ...args]).direct.code, 2);
	}
});

test("enable runs persisted runner during bootstrap, stays idempotent, and disables only its job", async t => {
	const f = fixture(t); f.bootstrapRunner = true;
	const result = await autoUpdate("enable", f.deps);
	assert.equal(result.code, 0, result.message);
	assert.equal(f.log().status, "success");
	assert.deepEqual(f.calls().filter(c => !c.args.includes("--json")).map(c => c.args), [
		["--no-daemon", "plugin", "marketplace", "upgrade", "ccl-skills"],
		["--no-daemon", "plugin", "add", "ccl-skills@ccl-skills"],
	]);
	const state = f.state(), runner = readFileSync(join(f.root, "runner.mjs"), "utf8"), job = f.plist(), xml = readFileSync(job, "utf8");
	assert.equal(state.node, join(f.bin, "node"));
	assert.equal(state.binary, join(f.bin, "codex"));
	assert.equal(xml.includes("&amp;"), true); assert.equal(xml.includes("&lt;xml&gt;"), true); assert.equal(xml.includes("&apos;"), true);
	assert.equal(xml.includes("secret-sentinel"), false);
	for (const call of f.calls()) {
		assert.deepEqual(Object.keys(call.env).filter(key => key !== "__CF_USER_TEXT_ENCODING").sort(), ["CODEX_HOME", "GIT_TERMINAL_PROMPT", "HOME", "PATH"]);
		assert.equal(call.env.CODEX_HOME, f.codexHome);
	}
	assert.equal((await autoUpdate("enable", f.deps)).code, 0);
	assert.equal(f.bootstrapCount, 1);
	assert.equal((await autoUpdate("status", f.deps)).status, "enabled");
	const unrelated = join(f.home, "Library", "LaunchAgents", "other.plist"); writeFileSync(unrelated, "unrelated");
	assert.equal((await autoUpdate("disable", f.deps)).status, "disabled");
	assert.equal(existsSync(job), false);
	assert.equal(readFileSync(unrelated, "utf8"), "unrelated");
	assert.equal(readFileSync(join(f.root, "runner.mjs"), "utf8"), runner);
	assert.equal(f.log().status, "success");
	assert.equal((await autoUpdate("status", f.deps)).status, "disabled");
	assert.equal((await runScheduled(f.env, f.command)).status, "disabled");
	assert.equal((await autoUpdate("enable", f.deps)).code, 0);
	assert.equal(f.bootstrapCount, 2);
});

for (const [name, options] of [
	["npm local source", {sourceType:"local"}], ["foreign Git source", {source:"https://github.com/other/project.git"}], ["foreign installed plugin source", {pluginSource:"https://github.com/other/project.git"}],
	["missing market", {missing:true}], ["duplicate market", {duplicate:true}], ["malformed JSON", {invalidJson:true}], ["disabled plugin", {disabled:true}],
]) test(`enable refuses ${name} without writing schedule state`, async t => {
	const f = fixture(t, options);
	assert.equal((await autoUpdate("enable", f.deps)).code, 5);
	assert.equal(existsSync(f.root), false);
	assert.equal(f.bootstrapCount, 0);
});
for (const source of ["git@github.com:ccoalm/ccl-skills.git", "ssh://git@github.com/ccoalm/ccl-skills.git"])
	test(`enable accepts canonical Git source ${source}`, async t => {
		const f = fixture(t, {source});
		assert.equal((await autoUpdate("enable", f.deps)).code, 0);
	});

test("unsupported platform is explicit without touching HOME", async () => {
	const result = await autoUpdate("enable", { platform:"linux", env:{} });
	assert.equal(result.code, 4); assert.equal(result.status, "unsupported-platform");
});

test("bootstrap failure stays visible and enable can recover", async t => {
	const f = fixture(t); f.bootstrapFailure = true;
	assert.equal((await autoUpdate("enable", f.deps)).code, 5);
	const failed = await autoUpdate("status", f.deps);
	assert.equal(failed.status, "scheduler-error"); assert.equal(failed.details.enabled, false);
	f.bootstrapFailure = false;
	assert.equal((await autoUpdate("enable", f.deps)).code, 0);
	assert.equal((await autoUpdate("status", f.deps)).status, "enabled");
});

test("unknown launchd state and foreign registration never get adopted", async t => {
	const f = fixture(t); f.registrationFailure = true;
	assert.equal((await autoUpdate("enable", f.deps)).code, 5);
	assert.equal(existsSync(f.root), false);
	f.registrationFailure = false; f.foreign = "/foreign/job.plist";
	assert.match((await autoUpdate("enable", f.deps)).message, /foreign launchd/);
	assert.equal(existsSync(f.root), false);
});

for (const [name, options, expected] of [["upgrade failure",{upgradeExit:8},1], ["add failure",{addExit:9},2]])
	test(`runner records ${name} and stops the command chain`, async t => {
		const f = fixture(t, options);
		assert.equal((await autoUpdate("enable", f.deps)).code, 0);
		assert.equal((await runScheduled(f.env, f.command)).code, 5);
		assert.equal(f.calls().filter(c => !c.args.includes("--json")).length, expected);
		assert.equal(f.log().status, "failed");
		assert.equal(existsSync(join(f.root, "run.lock")), false);
		assert.equal((await autoUpdate("status", f.deps)).status, "update-failed");
	});

test("runner rechecks provenance and does not update after source changes", async t => {
	const f = fixture(t); await autoUpdate("enable", f.deps);
	writeFileSync(f.control, JSON.stringify({ sourceType:"local" }));
	assert.equal((await runScheduled(f.env, f.command)).code, 5);
	assert.equal(f.calls().filter(c => !c.args.includes("--json")).length, 0);
	assert.equal(f.log().status, "failed");
});

test("runner skips a concurrent operation without replacing its log", async t => {
	const f = fixture(t); await autoUpdate("enable", f.deps);
	writeFileSync(join(f.root, "run.lock"), String(process.pid), {mode:0o600});
	assert.equal((await runScheduled(f.env, f.command)).status, "skipped");
	assert.equal(existsSync(join(f.root, "last-run.json")), false);
	assert.equal(f.calls().filter(c => !c.args.includes("--json")).length, 0);
});

test("disable fences execution even when launchd unload fails", async t => {
	const f = fixture(t); await autoUpdate("enable", f.deps); f.unloadFailure = true;
	assert.equal((await autoUpdate("disable", f.deps)).code, 5);
	assert.equal(f.state().enabled, false);
	assert.equal((await runScheduled(f.env, f.command)).status, "disabled");
	assert.equal((await autoUpdate("status", f.deps)).status, "scheduler-error");
	f.unloadFailure = false;
	assert.equal((await autoUpdate("disable", f.deps)).code, 0);
});

test("launchd failure overrides an old successful run record", async t => {
	const f = fixture(t); await autoUpdate("enable", f.deps); await runScheduled(f.env, f.command);
	f.lastExit = 9;
	const result = await autoUpdate("status", f.deps);
	assert.equal(result.status, "update-failed"); assert.equal(result.details.lastExit, 9);
});

for (const target of ["state.json", "runner.mjs", "last-run.json", "run.lock"])
	test(`managed ${target} symlink does not write outside the owned root`, async t => {
		const f = fixture(t); await autoUpdate("enable", f.deps);
		const sentinel = join(f.home, "sentinel"); writeFileSync(sentinel, "preserved");
		const path = join(f.root, target); rmSync(path, { force:true }); symlinkSync(sentinel, path);
		assert.equal((await runScheduled(f.env, f.command)).code, 5);
		assert.equal(readFileSync(sentinel, "utf8"), "preserved");
		assert.equal(f.calls().filter(c => !c.args.includes("--json")).length, 0);
	});

test("foreign plist survives disable refusal", async t => {
	const f = fixture(t); await autoUpdate("enable", f.deps);
	const path = f.plist(); writeFileSync(path, "foreign job");
	assert.equal((await autoUpdate("disable", f.deps)).code, 5);
	assert.equal(readFileSync(path, "utf8"), "foreign job");
});

test("hardlinked state survives disable refusal", async t => {
	const f = fixture(t); await autoUpdate("enable", f.deps);
	linkSync(join(f.root, "state.json"), join(f.home, "state-alias"));
	assert.equal((await autoUpdate("disable", f.deps)).code, 5);
	assert.equal(f.state().enabled, true);
});

test("forged profile and symlinked schedule ancestor are refused", async t => {
	const f = fixture(t); await autoUpdate("enable", f.deps);
	const state = f.state(); state.profile = "/foreign/profile";
	writeFileSync(join(f.root, "state.json"), JSON.stringify(state));
	assert.match((await autoUpdate("disable", f.deps)).message, /ownership record/);
	const other = fixture(t); symlinkSync(f.home, join(other.home, "Library"));
	assert.match((await autoUpdate("enable", other.deps)).message, /Unsafe ownership/);
	assert.equal(existsSync(other.root), false);
});

test("CLI emits one JSON result in non-TTY mode and documents opt-in", t => {
	const f = fixture(t);
	const result = spawnSync(process.execPath, ["dist/cli.js", "auto-update", "status", "--json"], { env:f.env, encoding:"utf8" });
	assert.equal(result.status, process.platform === "darwin" ? 0 : 4);
	assert.equal(JSON.parse(result.stdout).status, process.platform === "darwin" ? "disabled" : "unsupported-platform");
	assert.equal(result.stderr, ""); assert.equal(result.stdout.includes("\u001b"), false);
	const help = spawnSync(process.execPath, ["dist/cli.js", "--help"], { env:{...f.env,NO_COLOR:"1",TERM:"dumb"}, encoding:"utf8" });
	assert.match(help.stdout, /auto-update enable\|disable\|status/); assert.match(help.stdout, /macOS/);
});

test("concurrent initial enable cannot overwrite an enabled ownership record", async t => {
	const f = fixture(t);
	const results = await Promise.all([autoUpdate("enable", f.deps), autoUpdate("enable", f.deps)]);
	assert.equal(results.filter(r => r.code === 0).length, 1);
	assert.equal(f.state().enabled, true);
	assert.equal(f.bootstrapCount, 1);
});

test("disable during provenance check prevents subsequent update commands", async t => {
	const f = fixture(t); await autoUpdate("enable", f.deps);
	let disabled = false;
	const command = async (...args) => {
		const result = await f.command(...args);
		if (!disabled && args[1].includes("--json")) {
			disabled = true;
			assert.equal((await autoUpdate("disable", f.deps)).code, 0);
		}
		return result;
	};
	assert.equal((await runScheduled(f.env, command)).code, 5);
	assert.equal(f.calls().filter(c => !c.args.includes("--json")).length, 0);
});

test("timeout terminates the owned command process group", async t => {
	const f = fixture(t);
	const result = await runCommand(process.execPath, ["-e", "const {spawn}=require('node:child_process'); const c=spawn(process.execPath,['-e','setInterval(()=>{},1000)'],{stdio:'inherit'}); c.on('spawn',()=>console.log(c.pid)); setInterval(()=>{},1000)"], { HOME:f.home, PATH:f.env.PATH }, 400);
	assert.equal(result.failure, "timeout");
	assert.equal(result.code, null);
	const pid = Number(result.stdout.trim());
	assert.ok(Number.isSafeInteger(pid) && pid > 0);
	// A killed child can briefly remain a zombie until init reaps it; it cannot run.
	const processState = spawnSync("ps", ["-o", "stat=", "-p", String(pid)], {encoding:"utf8"});
	assert.ok(processState.status === 1 || processState.stdout.trim().startsWith("Z"), processState.stdout);
});

test("unparseable run record cannot report a healthy enabled state", async t => {
	const f = fixture(t); await autoUpdate("enable", f.deps);
	writeFileSync(join(f.root, "last-run.json"), '{}', {mode:0o600});
	assert.equal((await autoUpdate("status", f.deps)).code, 5);
});

test("source changes during upgrade prevent plugin add", async t => {
	const f = fixture(t); await autoUpdate("enable", f.deps);
	const command = async (...args) => {
		const result = await f.command(...args);
		if (args[1].includes("upgrade")) writeFileSync(f.control, JSON.stringify({sourceType:"local"}));
		return result;
	};
	assert.equal((await runScheduled(f.env, command)).code, 5);
	assert.deepEqual(f.calls().filter(c => !c.args.includes("--json")).map(c => c.args), [["--no-daemon", "plugin", "marketplace", "upgrade", "ccl-skills"]]);
});

test("stale runner lock fails visibly and remains intact for inspected recovery", async t => {
	const f = fixture(t); await autoUpdate("enable", f.deps);
	const exited = spawnSync(process.execPath, ["-e", ""], { encoding:"utf8" });
	assert.equal(exited.status, 0);
	const path = join(f.root, "run.lock"); writeFileSync(path, String(exited.pid), {mode:0o600});
	const result = await runScheduled(f.env, f.command);
	assert.equal(result.code, 5); assert.match(result.message, /Stale automatic-update lock/);
	assert.equal(readFileSync(path, "utf8"), String(exited.pid));
	assert.equal(f.log().status, "failed");
	const status = await autoUpdate("status", f.deps);
	assert.equal(status.status, "update-failed"); assert.equal(status.details.staleLock, true);
	assert.equal(f.calls().filter(c => !c.args.includes("--json")).length, 0);
});

test("registered job at the expected path without state is not adopted", async t => {
	const f = fixture(t);
	const hash = createHash("sha256").update(f.codexHome).digest("hex").slice(0,16);
	f.foreign = join(f.home, "Library", "LaunchAgents", `com.ccoalm.ccl-skills.codex.${hash}.plist`);
	const result = await autoUpdate("enable", f.deps);
	assert.match(result.message, /registered without our ownership record/);
	assert.equal(existsSync(f.root), false);
});

test("unset CODEX_HOME selects the default profile", async t => {
	const f = fixture(t); mkdirSync(join(f.home, ".codex"));
	const env = { ...f.env }; delete env.CODEX_HOME;
	const result = await autoUpdate("enable", { ...f.deps, env });
	assert.equal(result.code, 0, result.message);
	assert.equal(result.details.profile, join(f.home, ".codex"));
	assert.equal(existsSync(join(f.home, ".codex", "ccl-skills-auto-update", "runner.mjs")), true);
	assert.equal(existsSync(f.root), false);
});

test("SIGTERM during update records failure and releases runner lock", async t => {
	const f = fixture(t); await autoUpdate("enable", f.deps);
	const moduleUrl = pathToFileURL(join(process.cwd(), "dist", "auto-update.js")).href;
	const script = `import {runScheduled, runCommand} from ${JSON.stringify(moduleUrl)};
const result = await runScheduled(process.env, (file,args,env,timeout) => {
 if(args.includes('upgrade')) {
  process.nextTick(()=>process.kill(process.pid,'SIGTERM'));
  return runCommand(process.execPath,['-e','setInterval(()=>{},1000)'],env,5000);
 }
 return runCommand(file,args,env,timeout);
});
console.log(JSON.stringify(result)); process.exitCode=result.code;`;
	const result = spawnSync(process.execPath, ["--input-type=module", "-e", script], { env:f.env, encoding:"utf8", timeout:10000 });
	assert.equal(result.status, 5, result.stderr);
	assert.match(JSON.parse(result.stdout).message, /interrupted/);
	assert.equal(f.log().status, "failed");
	assert.equal(existsSync(join(f.root, "run.lock")), false);
});

// Each isolated mutant runs only its owning assertion, so unrelated failures
// cannot establish sensitivity. The fixture and entrypoint are the real ones.
test("disable ownership assertions reject guard-removal mutants", { skip: !!process.env.CCL_AUTO_MUTATION_CHILD }, t => {
	const scratch = realpathSync(mkdtempSync(join(tmpdir(), "ccl-auto-mutations-")));
	t.after(() => rmSync(scratch, {recursive:true,force:true}));
	mkdirSync(join(scratch,"dist")); mkdirSync(join(scratch,"test"));
	for (const name of readdirSync("dist").filter(name => name.endsWith(".js"))) cpSync(join("dist",name),join(scratch,"dist",name));
	cpSync("package.json",join(scratch,"package.json"));
	cpSync("test/auto-update.test.mjs",join(scratch,"test/auto-update.test.mjs"));
	const path = join(scratch,"dist","auto-update.js"), original = readFileSync(path,"utf8");
	const childEnv = { ...process.env, CCL_AUTO_MUTATION_CHILD: "1" };
	delete childEnv.NODE_TEST_CONTEXT;
	const mutations = [
		["foreign plist survives disable refusal", 'readFileSync(c.plist, "utf8") !== plist(c, s)', 'false'],
		["hardlinked state survives disable refusal", 's.nlink !== 1', 'false'],
	];
	for (const [name, anchor, replacement] of mutations) {
		assert.equal(original.split(anchor).length - 1, 1, `mutation anchor: ${name}`);
		const run = () => spawnSync(process.execPath,["--test",`--test-name-pattern=^${name}$`,"test/auto-update.test.mjs"], {cwd:scratch,encoding:"utf8",env:childEnv,timeout:10000});
		writeFileSync(path,original);
		const control = run();
		assert.equal(control.status,0,`control: ${name}`);
		assert.match(control.stdout,/pass 1|pass: 1/);
		writeFileSync(path,original.replace(anchor,replacement));
		assert.equal(spawnSync(process.execPath,["--check",path]).status,0,`syntax: ${name}`);
		const mutant = run();
		assert.equal(mutant.status,1,`mutant must fail: ${name}`);
		assert.match(mutant.stdout,/AssertionError|ERR_ASSERTION/);
		assert.match(mutant.stdout,/fail 1|fail: 1/);
	}
});

test("auto-update accepts explicit Codex or OpenCode and defaults to Codex", () => {
	for (const host of ["codex", "opencode"]) {
		const result = parseArgs(["auto-update", "enable", "--host", host, "--json"]);
		assert.equal(result.direct, undefined);
		assert.equal(result.options.host, host);
	}
	assert.equal(parseArgs(["auto-update", "status"]).options.host, "codex");
});
