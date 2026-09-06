import { spawnSync } from "node:child_process";

// Version discovery must not hold up other hosts or wait for interactive input.
const HOST_PROBE_TIMEOUT_MS = 10000;

export function probeHostVersion(command: string, env: NodeJS.ProcessEnv = process.env) {
	const result = spawnSync(command, ["--version"], {
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
				? `${command} --version timed out after ${HOST_PROBE_TIMEOUT_MS}ms`
				: kind === "missing"
					? `${command} CLI is unavailable (ENOENT)`
					: `${command} --version failed (${errorCode || (result.signal ? `signal ${result.signal}` : result.error ? "spawn error" : `exit ${result.status}`)})`,
		};
	}
	return { ok: true as const, output: `${result.stdout}\n${result.stderr}` };
}
