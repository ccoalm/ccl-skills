import { spawnSync } from "node:child_process";
import { accessSync } from "node:fs";
import { delimiter, resolve } from "node:path";

// Host discovery must not hold up other hosts or wait for interactive input.
const HOST_PROBE_TIMEOUT_MS = 10000;

// Presence only: do not execute a candidate or inspect its configuration.
export function isHostCommandMissing(command: string, env: NodeJS.ProcessEnv = process.env): boolean {
	const candidates = command.includes("/")
		? [command]
		: (env.PATH ?? "/usr/bin:/bin").split(delimiter).map((dir) => resolve(dir, command));
	let uncertain = false;
	for (const candidate of candidates) {
		try {
			accessSync(candidate);
			return false;
		} catch (error) {
			const code = (error as NodeJS.ErrnoException).code;
			if (code !== "ENOENT" && code !== "ENOTDIR") uncertain = true;
		}
	}
	return !uncertain;
}

export function probeHostVersion(command: string, env: NodeJS.ProcessEnv = process.env) {
	return probeHostCommand(command, ["--version"], env);
}

export function probeHostCommand(command: string, args: string[], env: NodeJS.ProcessEnv = process.env) {
	const result = spawnSync(command, args, {
		encoding: "utf8",
		env,
		stdio: ["ignore", "pipe", "pipe"],
		timeout: HOST_PROBE_TIMEOUT_MS,
		// spawnSync still waits if a child catches SIGTERM and does not exit.
		killSignal: "SIGKILL",
	});
	if (result.error || result.status !== 0) {
		const errorCode = (result.error as NodeJS.ErrnoException | undefined)?.code;
		const kind = errorCode === "ETIMEDOUT" ? "timeout" : errorCode === "ENOENT" ? "missing" : "probe-failed";
		return {
			ok: false as const,
			kind,
			message: kind === "timeout"
				? `${command} ${args.join(" ")} timed out after ${HOST_PROBE_TIMEOUT_MS}ms`
				: kind === "missing"
					? `${command} CLI is unavailable (ENOENT)`
					: `${command} ${args.join(" ")} failed (${errorCode || (result.signal ? `signal ${result.signal}` : result.error ? "spawn error" : `exit ${result.status}`)})`,
		};
	}
	return { ok: true as const, output: `${result.stdout}\n${result.stderr}`, stdout: result.stdout };
}
