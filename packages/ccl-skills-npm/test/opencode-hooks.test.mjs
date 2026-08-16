import test from "node:test";
import assert from "node:assert/strict";
import {
	cpSync,
	existsSync,
	mkdtempSync,
	mkdirSync,
	readFileSync,
	readdirSync,
	renameSync,
	writeFileSync,
} from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join, resolve } from "node:path";
import { pathToFileURL } from "node:url";
import { spawnSync } from "node:child_process";
import ts from "typescript";

const assets = resolve("dist/assets/marketplace/plugins/ccl-skills");

function copyRuntime(home) {
	const runtime = join(home, ".config/opencode/ccl-skills/runtime");
	mkdirSync(runtime, { recursive: true });
	for (const path of ["hooks", "scripts/owner-dispatch", "agent-context"]) {
		cpSync(join(assets, path), join(runtime, path), { recursive: true });
	}
	return runtime;
}

async function loadPlugin(home, directory, client = {}) {
	const source = readFileSync(join(assets, "packages/opencode-plugin/ccl-skills.ts"), "utf8");
	const output = ts.transpileModule(source, {
		compilerOptions: { module: ts.ModuleKind.ES2022, target: ts.ScriptTarget.ES2022 },
	}).outputText;
	const modulePath = join(mkdtempSync(join(tmpdir(), "ccl-opencode-plugin-")), "ccl-skills.mjs");
	writeFileSync(modulePath, output);
	const previousHome = process.env.HOME;
	process.env.HOME = home;
	try {
		const module = await import(`${pathToFileURL(modulePath).href}?v=${Date.now()}-${Math.random()}`);
		return { module, hooks: await module.CclSkills({ directory, worktree: directory, client }) };
	} finally {
		if (previousHome === undefined) delete process.env.HOME;
		else process.env.HOME = previousHome;
	}
}

function initProtectedRepo(root) {
	mkdirSync(root, { recursive: true });
	assert.equal(spawnSync("git", ["init", "-q", root]).status, 0);
	writeFileSync(join(root, ".worktree-only"), "\n");
}

function commandHooks() {
	const manifest = JSON.parse(readFileSync(join(assets, "hooks/hooks.json"), "utf8"));
	return [...new Set(Object.values(manifest.hooks)
		.flatMap((groups) => groups)
		.flatMap((group) => group.hooks)
		.map((hook) => hook.command.match(/hooks\/([^"/]+\.sh)/)?.[1])
		.filter(Boolean))].sort();
}

function traceRuntimeHooks(runtime) {
	for (const script of commandHooks()) {
		const installed = join(runtime, "hooks", script);
		renameSync(installed, `${installed}.real`);
		writeFileSync(installed, `#!/bin/sh\nprintf '%s\\n' '${script}' >> "$CCL_HOOK_TRACE"\nexec bash "$0.real"\n`, { mode: 0o755 });
	}
}

test("OpenCode binding inventory covers every command hook", async () => {
	const root = mkdtempSync(join(tmpdir(), "ccl-opencode-bindings-"));
	const home = join(root, "home"), project = join(root, "project");
	mkdirSync(home);
	mkdirSync(project);
	const { module } = await loadPlugin(home, project);
	assert.deepEqual(Object.keys(module.OPENCODE_HOOK_BINDINGS).sort(), commandHooks());
});

test("OpenCode blocks apply_patch targets in a protected primary checkout", async () => {
	const root = mkdtempSync(join(tmpdir(), "ccl-opencode-apply-patch-"));
	const home = join(root, "home"), project = join(root, "project");
	mkdirSync(home);
	initProtectedRepo(project);
	copyRuntime(home);
	const { hooks } = await loadPlugin(home, project);
	try {
		for (const [callID, patchText] of [
			["call-add", `*** Begin Patch\n*** Add File: ${join(project, "blocked.txt")}\n+blocked\n*** End Patch`],
			["call-move-out", `*** Begin Patch\n*** Update File: ${join(project, "source.txt")}\n*** Move to: ${join(root, "outside.txt")}\n@@\n-old\n+new\n*** End Patch`],
			["call-move-in", `*** Begin Patch\n*** Update File: ${join(root, "outside.txt")}\n*** Move to: ${join(project, "destination.txt")}\n@@\n-old\n+new\n*** End Patch`],
		]) {
			await assert.rejects(
				() => hooks["tool.execute.before"](
					{ tool: "apply_patch", sessionID: "apply-patch", callID },
					{ args: { patchText } },
				),
				/worktree guard blocked this edit/,
			);
		}
	} finally {
		await hooks.dispose();
	}
});

test("OpenCode fails closed when a safety hook runtime is unavailable", async () => {
	const root = mkdtempSync(join(tmpdir(), "ccl-opencode-missing-runtime-"));
	const home = join(root, "home"), project = join(root, "project");
	mkdirSync(home);
	mkdirSync(project);
	const { hooks } = await loadPlugin(home, project);
	await assert.rejects(
		() => hooks["tool.execute.before"](
			{ tool: "write", sessionID: "missing-runtime", callID: "call-1" },
			{ args: { filePath: join(project, "blocked.txt"), content: "blocked" } },
		),
		/hook runtime is unavailable|could not run/i,
	);
	await hooks.dispose();
});

test("OpenCode native events execute the installed CCL hook runtime", async () => {
	const root = mkdtempSync(join(tmpdir(), "ccl-opencode-runtime-"));
	const home = join(root, "home"), project = join(root, "project"), runtimeTmp = join(root, "tmp");
	mkdirSync(home);
	mkdirSync(project);
	mkdirSync(runtimeTmp);
	const runtime = copyRuntime(home);

	// Make the Stop behavior deterministic without depending on a repository-specific
	// owner-dispatch boundary; the adapter still executes the installed script path.
	writeFileSync(join(runtime, "hooks/owner-dispatch-stop.sh"), `#!/bin/sh
input=$(cat)
transcript=$(printf '%s' "$input" | jq -r '.transcript_path // empty')
file_path_seen=0
secret_seen=0
grep -q '"file_path":' "$transcript" && file_path_seen=1
grep -Eq 'super-secret-(prompt|file-content)' "$transcript" && secret_seen=1
printf '{"decision":"block","reason":"stop-backstop-fired:file_path=%s:secret=%s"}\\n' "$file_path_seen" "$secret_seen"
	`, { mode: 0o755 });
	writeFileSync(join(runtime, "hooks/skill-extraction-gate-stop.sh"), "#!/bin/sh\ncat >/dev/null\n", { mode: 0o755 });
	traceRuntimeHooks(runtime);

	const prompts = [];
	const client = { session: { promptAsync: async (value) => { prompts.push(value); } } };
	const previousTmp = process.env.TMPDIR;
	const previousTrace = process.env.CCL_HOOK_TRACE;
	const trace = join(root, "hook-trace.txt");
	process.env.TMPDIR = runtimeTmp;
	process.env.CCL_HOOK_TRACE = trace;
	let hooks;
	try {
		({ hooks } = await loadPlugin(home, project, client));
		const system = { system: [] };
		await hooks["experimental.chat.system.transform"]({ sessionID: "runtime-session" }, system);
		assert.match(system.system.join("\n"), /ccl-skills-routing/);

		await hooks["chat.message"](
			{ sessionID: "runtime-session" },
			{ message: { role: "user" }, parts: [{ type: "text", text: "合并" }] },
		);
		await hooks["tool.execute.before"](
			{ tool: "bash", sessionID: "runtime-session", callID: "merge-1" },
			{ args: { command: "gh pr merge 123 --merge" } },
		);

		await hooks["chat.message"](
			{ sessionID: "runtime-session" },
			{ message: { role: "user" }, parts: [{ type: "text", text: "继续检查 super-secret-prompt" }] },
		);
		await assert.rejects(
			() => hooks["tool.execute.before"](
				{ tool: "bash", sessionID: "runtime-session", callID: "merge-2" },
				{ args: { command: "gh pr merge 123 --merge" } },
			),
			/merge authorization|合并授权|blocked/i,
		);

		const blockedTask = { args: { description: "inspect", prompt: "Review the change" } };
		await assert.rejects(
			() => hooks["tool.execute.before"](
				{ tool: "task", sessionID: "runtime-session", callID: "task-blocked" },
				blockedTask,
			),
			/delegation-owner guard/i,
		);
		await hooks["tool.execute.before"](
			{ tool: "skill", sessionID: "runtime-session", callID: "skill-1" },
			{ args: { skill: "ccl-skills:multi-agent-delegation" } },
		);
		await hooks["tool.execute.after"](
			{ tool: "skill", sessionID: "runtime-session", callID: "skill-1", args: { skill: "ccl-skills:multi-agent-delegation" } },
			{ output: "loaded" },
		);
		const task = { args: { description: "inspect", prompt: "Review the change" } };
		await hooks["tool.execute.before"](
			{ tool: "task", sessionID: "runtime-session", callID: "task-1" },
			task,
		);
		assert.match(task.args.prompt, /ccl-skills-subagent-routing/);
		assert.match(task.args.prompt, /ccl-skills/);

		await hooks["tool.execute.before"](
			{ tool: "write", sessionID: "runtime-session", callID: "write-1" },
			{ args: { filePath: join(project, "evidence.txt"), content: "super-secret-file-content" } },
		);

		const after = { title: "merge", output: "merged", metadata: { exitCode: 0 } };
		await hooks["tool.execute.after"](
			{ tool: "bash", sessionID: "runtime-session", callID: "merge-1", args: { command: "gh pr merge 123 --merge" } },
			after,
		);
		assert.match(after.output, /worktree-isolation/);

		await hooks.event({ event: { type: "session.status", properties: { sessionID: "runtime-session", status: { type: "idle" } } } });
		assert.equal(prompts.length, 1);
		assert.match(JSON.stringify(prompts[0]), /stop-backstop-fired:file_path=1:secret=0/);
		assert.deepEqual([...new Set(readFileSync(trace, "utf8").trim().split("\n"))].sort(), commandHooks());
	} finally {
		if (hooks) await hooks.dispose();
		if (previousTmp === undefined) delete process.env.TMPDIR;
		else process.env.TMPDIR = previousTmp;
		if (previousTrace === undefined) delete process.env.CCL_HOOK_TRACE;
		else process.env.CCL_HOOK_TRACE = previousTrace;
	}
	assert.deepEqual(readdirSync(runtimeTmp).filter((entry) => entry.startsWith("ccl-skills-opencode-")), []);
});
