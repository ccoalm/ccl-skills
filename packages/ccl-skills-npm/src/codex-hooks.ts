import { spawn, spawnSync, type SpawnSyncOptionsWithStringEncoding } from "node:child_process";
import { readFileSync } from "node:fs";
import { dirname, isAbsolute, join, relative, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { canonicalAlias, contained, verifyTree } from "./fs-safe.js";
import { MARKET, REF } from "./paths.js";
import type { OwnedFile } from "./types.js";

const TIMEOUT_MS = 10000;
const OUTPUT_LIMIT = 1024 * 1024;
type HookStatus = "trusted" | "managed" | "untrusted" | "modified" | "disabled" | "missing" | "unknown";
export interface HookInventory {
	status: HookStatus;
	expected: number;
	observed: number;
	runtime: "unverified";
	reason?: string;
}
interface ExpectedHook { eventName: string; matcher: string | null; command: string }
const record = (value: unknown): value is Record<string, unknown> => value !== null && typeof value === "object" && !Array.isArray(value);
const unknown = (reason: string, expected = 0, observed = 0): HookInventory => ({ status: "unknown", expected, observed, runtime: "unverified", reason });

// Compare native metadata with the verified package snapshot. Merely finding a
// similarly named plugin or one trusted handler cannot certify the installation.
export function parseHookInventory(value: unknown, cwd: string, pluginRoot: string, runtime?: { codexHome: string; files: OwnedFile[] }): HookInventory {
	let expected: ExpectedHook[] = [];
	try {
		const config: unknown = JSON.parse(readFileSync(join(pluginRoot, "hooks/hooks.json"), "utf8"));
		if (!record(config) || !record(config.hooks)) return unknown("invalid-owned-hooks");
		for (const [event, groups] of Object.entries(config.hooks)) {
			if (!Array.isArray(groups)) return unknown("invalid-owned-hooks");
			for (const group of groups) {
				if (!record(group) || !Array.isArray(group.hooks) || (group.matcher !== undefined && typeof group.matcher !== "string")) return unknown("invalid-owned-hooks");
				for (const hook of group.hooks) {
					if (!record(hook) || hook.type !== "command" || typeof hook.command !== "string" || !hook.command) return unknown("invalid-owned-hooks");
					expected.push({ eventName: event[0].toLowerCase() + event.slice(1), matcher: group.matcher as string | undefined ?? null, command: hook.command });
				}
			}
		}
	} catch { return unknown("invalid-owned-hooks"); }
	if (!expected.length) return unknown("empty-owned-hooks");
	const count = expected.length;
	if (!record(value) || !Array.isArray(value.data) || value.data.length !== 1) return unknown("malformed-inventory", count);
	const entry = value.data[0];
	if (!record(entry) || typeof entry.cwd !== "string" || !isAbsolute(entry.cwd) || canonicalAlias(resolve(entry.cwd)) !== canonicalAlias(resolve(cwd)) || !Array.isArray(entry.hooks)) return unknown("malformed-inventory", count);
	if (!Array.isArray(entry.errors) || !Array.isArray(entry.warnings) || entry.errors.length || entry.warnings.length) return unknown("inventory-diagnostics", count);
	const statuses: string[] = [], keys = new Set<string>();
	let disabled = false;
	const expectedSource = canonicalAlias(join(pluginRoot, "hooks/hooks.json"));
	const verifiedRoots = new Set<string>([canonicalAlias(pluginRoot)]);
	for (const hook of entry.hooks) {
		if (!record(hook)) return unknown("malformed-inventory", count);
		if (hook.pluginId !== REF) continue;
		if (hook.source !== "plugin" || typeof hook.sourcePath !== "string" || !isAbsolute(hook.sourcePath)) return unknown("hook-source-mismatch", count, statuses.length);
		const source = canonicalAlias(resolve(hook.sourcePath)), root = dirname(dirname(source));
		if (source !== expectedSource) {
			if (!runtime || source !== join(root, "hooks/hooks.json")) return unknown("hook-source-mismatch", count, statuses.length);
			const cache = canonicalAlias(join(runtime.codexHome, "plugins/cache", MARKET, "ccl-skills"));
			try {
				if (root === cache || contained(cache, relative(cache, root)) !== root) return unknown("hook-source-mismatch", count, statuses.length);
				if (!verifiedRoots.has(root)) {
					if (!runtime.files.length || verifyTree(root, runtime.files).length) return unknown("runtime-drift", count, statuses.length);
					verifiedRoots.add(root);
				}
			} catch { return unknown("hook-source-mismatch", count, statuses.length); }
		}
		if (hook.handlerType !== "command" || typeof hook.command !== "string" || typeof hook.eventName !== "string" || (hook.matcher !== null && typeof hook.matcher !== "string") || typeof hook.enabled !== "boolean" || typeof hook.key !== "string" || !hook.key || keys.has(hook.key) || !["trusted", "untrusted", "modified", "managed"].includes(String(hook.trustStatus))) return unknown("malformed-hook", count, statuses.length);
		keys.add(hook.key);
		const commandRoot = dirname(dirname(resolve(hook.sourcePath)));
		const index = expected.findIndex(item => item.eventName === hook.eventName && item.matcher === hook.matcher && item.command.replaceAll("${CLAUDE_PLUGIN_ROOT}", commandRoot).replaceAll("${CODEX_PLUGIN_ROOT}", commandRoot) === hook.command);
		if (index < 0) return unknown("hook-definition-mismatch", count, statuses.length);
		expected.splice(index, 1);
		statuses.push(String(hook.trustStatus));
		disabled ||= !hook.enabled;
	}
	const base = { expected: count, observed: statuses.length, runtime: "unverified" as const };
	if (expected.length) return { ...base, status: "missing", reason: "missing-package-hooks" };
	if (statuses.includes("modified")) return { ...base, status: "modified" };
	if (statuses.includes("untrusted")) return { ...base, status: "untrusted" };
	if (disabled) return { ...base, status: "disabled" };
	return { ...base, status: statuses.every(status => status === "managed") ? "managed" : "trusted" };
}

// The CLI's operation API is synchronous. Isolate the handshake in a short-lived
// helper so initialization completes before hooks/list, without starting a turn.
export function inspectHooks(codexHome: string, pluginRoot: string, files: OwnedFile[], cwd = process.cwd()): HookInventory {
	const result = spawnSync(process.execPath, [fileURLToPath(import.meta.url), "--inventory-worker", resolve(cwd)], {
		encoding: "utf8", env: { ...process.env, CODEX_HOME: codexHome },
		stdio: ["ignore", "pipe", "pipe"], detached: process.platform !== "win32",
		timeout: TIMEOUT_MS + 1000, killSignal: "SIGKILL", maxBuffer: OUTPUT_LIMIT,
	} as SpawnSyncOptionsWithStringEncoding & { detached: boolean });
	// The helper and its descendants share an isolated process group. This also
	// catches hosts which leave children alive or hold stdout open after exit.
	if (process.platform !== "win32" && result.pid) {
		try { process.kill(-result.pid, "SIGKILL"); } catch { /* group already gone */ }
	}
	if (result.error || result.status !== 0) return unknown((result.error as NodeJS.ErrnoException | undefined)?.code === "ETIMEDOUT" ? "timeout" : "unavailable");
	try {
		const payload: unknown = JSON.parse(result.stdout);
		if (!record(payload) || payload.ok !== true) return unknown(record(payload) && typeof payload.reason === "string" && ["timeout", "unavailable", "malformed-output", "output-limit", "unsupported"].includes(payload.reason) ? payload.reason : "malformed-output");
		return parseHookInventory(payload.result, cwd, pluginRoot, { codexHome, files });
	} catch { return unknown("malformed-output"); }
}

function inventoryWorker(cwd: string): void {
	const child = spawn("codex", ["app-server", "--stdio"], { stdio: ["pipe", "pipe", "pipe"] });
	let finished = false, initialized = false, received = 0, pending = "";
	const timer = setTimeout(() => finish({ ok: false, reason: "timeout" }), TIMEOUT_MS);
	function finish(value: unknown): void {
		if (finished) return;
		finished = true;
		clearTimeout(timer);
		child.kill("SIGKILL");
		child.stdin.destroy(); child.stdout.destroy(); child.stderr.destroy();
		process.stdout.write(JSON.stringify(value));
	}
	const send = (value: unknown) => child.stdin.write(`${JSON.stringify(value)}\n`);
	child.on("error", () => finish({ ok: false, reason: "unavailable" }));
	child.on("exit", () => finish({ ok: false, reason: "unavailable" }));
	child.stdin.on("error", () => finish({ ok: false, reason: "unavailable" }));
	child.stderr.on("data", (chunk: Buffer) => {
		received += chunk.length;
		if (received > OUTPUT_LIMIT) finish({ ok: false, reason: "output-limit" });
	});
	child.stdout.setEncoding("utf8");
	child.stdout.on("data", (chunk: string) => {
		received += Buffer.byteLength(chunk, "utf8");
		if (received > OUTPUT_LIMIT) return finish({ ok: false, reason: "output-limit" });
		pending += chunk;
		let newline: number;
		while (!finished && (newline = pending.indexOf("\n")) >= 0) {
			const line = pending.slice(0, newline); pending = pending.slice(newline + 1);
			let response: unknown;
			try { response = JSON.parse(line); } catch { return finish({ ok: false, reason: "malformed-output" }); }
			if (!record(response)) return finish({ ok: false, reason: "malformed-output" });
			if (!Object.hasOwn(response, "id") && typeof response.method === "string") continue;
			if (response.id !== (initialized ? 2 : 1)) return finish({ ok: false, reason: "malformed-output" });
			if (Object.hasOwn(response, "error")) return finish({ ok: false, reason: "unsupported" });
			if (!record(response.result)) return finish({ ok: false, reason: "malformed-output" });
			if (initialized) return finish({ ok: true, result: response.result });
			initialized = true;
			send({ method: "initialized", params: {} });
			send({ id: 2, method: "hooks/list", params: { cwds: [cwd] } });
		}
	});
	send({ id: 1, method: "initialize", params: { clientInfo: { name: "ccl_hook_audit", version: "1.0" }, capabilities: { experimentalApi: true } } });
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url) && process.argv[2] === "--inventory-worker" && isAbsolute(process.argv[3] ?? "")) inventoryWorker(process.argv[3]);
