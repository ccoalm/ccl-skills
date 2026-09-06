import { probeHostVersion } from "./host-probe.js";
import { existsSync } from "node:fs";
import { join, resolve } from "node:path";
import { runClaude } from "./claude-adapter.js";
import { run as runCodex } from "./operations.js";
import { runOpenCode } from "./opencode-adapter.js";
import type { PathContext } from "./paths.js";
import type { Host, Options, Result } from "./types.js";

function owned(host: Host) {
	const home = process.env.HOME;
	if (!home) return false;
	const manifest = host === "claude"
		? join(resolve(home), ".claude/ccl-skills-npm/install-manifest.json")
		: host === "opencode"
			? join(resolve(home), ".config/opencode/ccl-skills-npm/install-manifest.json")
			: join(resolve(process.env.CODEX_HOME || join(home, ".codex")), "ccl-skills-npm/install-manifest.json");
	return existsSync(manifest);
}

function dispatch(host: Host, command: string, options: Options, codexContext: PathContext): Result {
	if (host === "claude") return runClaude(command, options, codexContext);
	if (host === "opencode") return runOpenCode(command, options, codexContext);
	return runCodex(command, options, codexContext);
}

export function runHostSequence(hosts: Host[], invoke: (host: Host) => Result): Result {
	const results: Array<{ host: Host; result: Result }> = [];
	for (const host of hosts) {
		const result = invoke(host);
		results.push({ host, result });
		if (result.code === 5 || result.code === 130) break;
	}
	if (hosts.length === 1) return results[0].result;
	const failed = results.filter(({ result }) => result.code !== 0);
	const code = failed.some(({ result }) => result.code === 130)
		? 130
		: failed.some(({ result }) => result.code === 5)
			? 5
			: failed.length
				? failed[0].result.code
				: 0;
	return {
		code,
		status: failed.length ? "multi-host-partial" : "multi-host-complete",
		message: results.map(({ host, result }) => `${host}: ${result.status}`).join("; "),
		details: { hosts: Object.fromEntries(results.map(({ host, result }) => [host, result])) },
		...(code === 130 ? { interrupted: true } : {}),
	};
}

export function runUnified(command: string, options: Options = {}, codexContext: PathContext = {}): Result {
	if (options.host) return dispatch(options.host, command, options, codexContext);
	const includeOwned = command === "doctor" || command === "uninstall";
	const candidates = (["claude", "codex", "opencode"] as Host[]).filter((host) => command !== "update" || owned(host));
	const probes = candidates.map((host) => ({ host, probe: probeHostVersion(host) }));
	const hosts = probes.filter(({ host, probe }) => probe.ok || probe.kind !== "missing" || (includeOwned && owned(host))).map(({ host }) => host);
	if (!hosts.length) return { code: 4, status: "host-missing", message: "no Claude Code, Codex, or OpenCode CLI is available" };
	return runHostSequence(hosts, (host) => {
		const probe = probes.find((entry) => entry.host === host)!.probe;
		if (!probe.ok && probe.kind !== "missing") return { code: 4, status: `host-${probe.kind}`, message: probe.message };
		return dispatch(host, command, { ...options, host }, codexContext);
	});
}
