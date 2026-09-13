import test from "node:test";
import assert from "node:assert/strict";
import { readFileSync, writeFileSync, renameSync, rmSync, mkdtempSync, mkdirSync, cpSync } from "node:fs";
import { join } from "node:path";
import { tmpdir } from "node:os";
import { spawnSync } from "node:child_process";
import { createHash } from "node:crypto";
import { fixture, cli } from "./helpers.mjs";
import { parseHookInventory } from "../dist/codex-hooks.js";

function hookFixture(t, mode = "trusted") {
	const f = fixture();
	t.after(() => rmSync(f.root, { recursive: true, force: true }));
	assert.equal(cli(f, ["install", "--json"]).status, 3);
	const binary = join(f.root, "bin/codex"), original = readFileSync(binary, "utf8");
	const server = join(f.root, "server.mjs");
	writeFileSync(server, `
import { createInterface } from 'node:readline';
import { readFileSync, appendFileSync } from 'node:fs';
import { spawn } from 'node:child_process';
const mode = process.env.HOOK_MODE;
appendFileSync(process.env.HOOK_REQUESTS + '.pids', process.pid + '\\n');
if (mode === 'timeout') {
 const descendant = spawn(process.execPath, ['-e', 'process.on("SIGTERM",()=>{});setInterval(()=>{},1000)'], {stdio:'inherit'});
 appendFileSync(process.env.HOOK_REQUESTS + '.pids', descendant.pid + '\\n');
 process.on('SIGTERM',()=>{});
 setInterval(()=>{},1000);
}
let initialized = false;
createInterface({ input: process.stdin }).on('line', line => {
 const request = JSON.parse(line);
 appendFileSync(process.env.HOOK_REQUESTS, JSON.stringify(request) + '\\n');
 if (mode === 'timeout') return;
 if (mode === 'unavailable') process.exit(2);
 if (mode === 'malformed') { process.stdout.write('broken json\\n'); return; }
 if (mode === 'overflow') { process.stdout.write('x'.repeat(1024 * 1024 + 1)); return; }
 if (mode === 'unsupported') { process.stdout.write(JSON.stringify({id:request.id,error:{code:-32601,message:'unsupported'}}) + '\\n'); return; }
 if (request.method === 'initialize') {
  process.stdout.write(JSON.stringify({id: request.id, result: {userAgent:'synthetic'}}) + '\\n');
 } else if (request.method === 'initialized') initialized = true;
 else if (request.method === 'hooks/list' && initialized) {
  const market = readFileSync(process.env.FAKE_STATE + '.market','utf8');
  const manifest = JSON.parse(readFileSync(market + '/plugins/ccl-skills/hooks/hooks.json','utf8'));
  const hooks = Object.entries(manifest.hooks).flatMap(([eventName, groups]) => groups.flatMap(group => group.hooks.map((hook, index) => ({
   pluginId: 'ccl-skills@ccl-skills-npm', enabled: true, trustStatus: mode,
   source: 'plugin', sourcePath: market + '/plugins/ccl-skills/hooks/hooks.json', handlerType:'command', matcher: group.matcher ?? null,
   command: hook.command.replaceAll('$' + '{CLAUDE_PLUGIN_ROOT}', market + '/plugins/ccl-skills'), eventName: eventName[0].toLowerCase() + eventName.slice(1), key: eventName + ':' + group.matcher + ':' + index + ':' + hook.command,
  }))));
  process.stdout.write(JSON.stringify({id: request.id, result: {data:[{cwd:request.params.cwds[0],hooks, warnings:[], errors:[]}]}}) + '\\n');
 } else process.exit(2);
});
`);
	renameSync(binary, `${binary}-original`);
	writeFileSync(binary, `#!/bin/sh\nif [ "$1" = app-server ]; then exec '${process.execPath}' '${server}'; fi\n${original.replace(/^#![^\n]*\n/, "")}`, { mode: 0o755 });
	f.env.HOOK_MODE = mode;
	f.env.HOOK_REQUESTS = join(f.root, "hook-requests");
	return f;
}

function assertStopped(f) {
	const pids = readFileSync(f.env.HOOK_REQUESTS + '.pids', 'utf8').trim().split('\n');
	for (const pid of pids) {
		const state = spawnSync('ps', ['-p', pid, '-o', 'stat='], {encoding:'utf8'});
		assert.ok(state.status !== 0 || state.stdout.trim().startsWith('Z'), `probe child ${pid} is still running`);
	}
	return pids.length;
}

test("doctor distinguishes trusted hook configuration from unverified execution", (t) => {
	const f = hookFixture(t);
	const result = cli(f, ["doctor", "--json"]);
	assert.equal(result.status, 0, result.stdout || result.stderr);
	const report = JSON.parse(result.stdout);
	assert.equal(report.status, "installed-hooks-trusted");
	assert.equal(report.details.hooks.status, "trusted");
	assert.equal(report.details.hooks.runtime, "unverified");
	assert.match(report.message, /execution.*not verified/i);
	const requests = readFileSync(f.env.HOOK_REQUESTS, "utf8").trim().split("\n").map(JSON.parse);
	assert.deepEqual(requests.map(request => request.method), ["initialize", "initialized", "hooks/list"]);
	assert.deepEqual(requests[0].params.capabilities, { experimentalApi: true });
	assert.deepEqual(requests[2].params, { cwds: [process.cwd()] });
	assert.equal(assertStopped(f), 1);
});

test("same-version install preserves the verified native trust message", (t) => {
	const f = hookFixture(t);
	const result = cli(f, ["install", "--json"]);
	const report = JSON.parse(result.stdout);
	assert.equal(result.status, 0, result.stdout || result.stderr);
	assert.equal(report.status, "installed-hooks-trusted");
	assert.match(report.message, /same version/);
	assert.match(report.message, /configured and trusted/);
	assert.doesNotMatch(report.message, /trust remains pending/);
	assert.equal(assertStopped(f), 1);
});

for (const status of ['managed','untrusted','modified']) {
	test(`doctor exposes native ${status} hook trust in its JSON result`, (t) => {
		const f = hookFixture(t,status), result = cli(f,['doctor','--json']);
		const report = JSON.parse(result.stdout);
		assert.equal(result.status,status === 'managed' ? 0 : 3);
		assert.equal(report.status,status === 'managed' ? 'installed-hooks-trusted' : 'installed-hooks-pending');
		assert.equal(report.details.hooks.status,status);
		assert.equal(report.details.hooks.runtime,'unverified');
		assert.equal(assertStopped(f),1);
	});
}

for (const [mode, reason] of [['unavailable','unavailable'], ['unsupported','unsupported'], ['malformed','malformed-output'], ['overflow','output-limit'], ['timeout','timeout']]) {
	test(`doctor reports unknown and cleans up a ${mode} app-server`, (t) => {
		const f = hookFixture(t, mode);
		const start = Date.now(), result = cli(f, ['doctor','--json']);
		assert.ok(Date.now() - start < 15000, 'inventory exceeded its bounded lifetime');
		assert.equal(result.status, 3, result.stdout || result.stderr);
		const report = JSON.parse(result.stdout);
		assert.equal(report.details.hooks.status, 'unknown');
		assert.equal(report.details.hooks.reason, reason);
		assert.equal(report.trust, 'pending-unverified');
		assert.equal(assertStopped(f), mode === 'timeout' ? 2 : 1);
	});
}

function metadataFixture(t) {
	const root = mkdtempSync(join(tmpdir(), 'ccl-hook-metadata-'));
	t.after(() => rmSync(root, {recursive:true, force:true}));
	const pluginRoot = join(root,'owned'), home = join(root,'home'), runtimeRoot = join(home,'plugins/cache/ccl-skills-npm/ccl-skills/local');
	mkdirSync(join(pluginRoot,'hooks'), {recursive:true});
	const config = {hooks:{SessionStart:[{matcher:'startup|resume',hooks:[{type:'command',command:'"${CLAUDE_PLUGIN_ROOT}/hooks/start.sh"'}]}],PreToolUse:[{matcher:'Edit',hooks:[{type:'command',command:'"${CLAUDE_PLUGIN_ROOT}/hooks/guard.sh"'}]}]}};
	const bodies = {'hooks/hooks.json':JSON.stringify(config),'hooks/start.sh':'#!/bin/sh\nexit 0\n','hooks/guard.sh':'#!/bin/sh\nexit 0\n'};
	const files = Object.entries(bodies).map(([path,body]) => {
		writeFileSync(join(pluginRoot,path),body,{mode:0o644});
		return {path, mode:0o644, sha256:createHash('sha256').update(body).digest('hex')};
	});
	cpSync(pluginRoot,runtimeRoot,{recursive:true});
	const hook = {pluginId:'ccl-skills@ccl-skills-npm', source:'plugin', sourcePath:join(pluginRoot,'hooks/hooks.json'), handlerType:'command', enabled:true, trustStatus:'trusted'};
	const value = {data:[{cwd:root,warnings:[],errors:[],hooks:[
		{...hook,key:'startup',eventName:'sessionStart',matcher:'startup|resume',command:`"${pluginRoot}/hooks/start.sh"`},
		{...hook,key:'guard',eventName:'preToolUse',matcher:'Edit',command:`"${pluginRoot}/hooks/guard.sh"`},
	]}]};
	return {root,pluginRoot,home,runtimeRoot,files,value,parse:()=>parseHookInventory(value,root,pluginRoot,{codexHome:home,files})};
}

for (const status of ['trusted','managed','untrusted','modified']) {
	test(`inventory preserves native ${status} state without execution proof`, (t) => {
		const f = metadataFixture(t);
		for (const hook of f.value.data[0].hooks) hook.trustStatus = status;
		assert.deepEqual(f.parse(), {status,expected:2,observed:2,runtime:'unverified'});
	});
}

for (const [name, mutate, status, reason] of [
	['no hooks',f=>{f.value.data[0].hooks=[]},'missing','missing-package-hooks'],
	['missing handler',f=>{f.value.data[0].hooks.pop()},'missing','missing-package-hooks'],
	['wrong plugin',f=>{f.value.data[0].hooks.forEach(hook=>{hook.pluginId='ccl-skills@ccl-skills'})},'missing','missing-package-hooks'],
	['similar plugin',f=>{f.value.data[0].hooks.forEach(hook=>{hook.pluginId+='-copy'})},'missing','missing-package-hooks'],
	['disabled handler',f=>{f.value.data[0].hooks[0].enabled=false},'disabled',undefined],
	['unknown trust',f=>{f.value.data[0].hooks[0].trustStatus='future'},'unknown','malformed-hook'],
	['nested handler',f=>{delete f.value.data[0].hooks[0].command},'unknown','malformed-hook'],
	['duplicate key',f=>{f.value.data[0].hooks[1].key='startup'},'unknown','malformed-hook'],
	['duplicate hook',f=>{f.value.data[0].hooks.push({...f.value.data[0].hooks[0],key:'duplicate'})},'unknown','hook-definition-mismatch'],
	['different command',f=>{f.value.data[0].hooks[0].command+='; echo unexpected'},'unknown','hook-definition-mismatch'],
	['different matcher',f=>{f.value.data[0].hooks[0].matcher='clear'},'unknown','hook-definition-mismatch'],
	['different source',f=>{f.value.data[0].hooks[0].source='project'},'unknown','hook-source-mismatch'],
	['different source path',f=>{f.value.data[0].hooks[0].sourcePath='/tmp/unowned/hooks/hooks.json'},'unknown','hook-source-mismatch'],
	['wrong cwd',f=>{f.value.data[0].cwd='/tmp/different-cwd'},'unknown','malformed-inventory'],
	['duplicate cwd',f=>{f.value.data.push(f.value.data[0])},'unknown','malformed-inventory'],
	['host warning',f=>{f.value.data[0].warnings.push('synthetic warning')},'unknown','inventory-diagnostics'],
	['host error',f=>{f.value.data[0].errors.push({message:'synthetic error'})},'unknown','inventory-diagnostics'],
]) {
	test(`inventory cannot report healthy for ${name}`, (t) => {
		const f = metadataFixture(t);
		mutate(f);
		const result = f.parse();
		assert.equal(result.status,status);
		assert.equal(result.reason,reason);
		assert.equal(result.runtime,'unverified');
	});
}

test('foreign hooks do not hide the complete trusted package inventory', (t) => {
	const f = metadataFixture(t);
	f.value.data[0].hooks.unshift({...f.value.data[0].hooks[0],pluginId:'other@community',trustStatus:'untrusted'});
	assert.equal(f.parse().status,'trusted');
});

for (const drift of [false,true]) {
	test(`runtime cache ${drift ? 'drift stays unknown' : 'is bound to the complete owned snapshot'}`, (t) => {
		const f = metadataFixture(t);
		for (const hook of f.value.data[0].hooks) {
			hook.sourcePath = join(f.runtimeRoot,'hooks/hooks.json');
			hook.command = hook.command.replace(f.pluginRoot,f.runtimeRoot);
		}
		if (drift) writeFileSync(join(f.runtimeRoot,'hooks/guard.sh'),'changed');
		assert.equal(f.parse().status,drift ? 'unknown' : 'trusted');
		assert.equal(f.parse().reason,drift ? 'runtime-drift' : undefined);
	});
}

for (const namespace of ['ccl-skills/ccl-skills-npm','ccl-skills/ccl-skills','ccl-skills-npm/other-plugin']) {
	test(`runtime cache rejects another namespace ${namespace}`, (t) => {
		const f = metadataFixture(t), foreignRoot = join(f.home,'plugins/cache',namespace,'local');
		cpSync(f.pluginRoot,foreignRoot,{recursive:true});
		for (const hook of f.value.data[0].hooks) {
			hook.sourcePath = join(foreignRoot,'hooks/hooks.json');
			hook.command = hook.command.replace(f.pluginRoot,foreignRoot);
		}
		assert.equal(f.parse().status,'unknown');
		assert.equal(f.parse().reason,'hook-source-mismatch');
	});
}
