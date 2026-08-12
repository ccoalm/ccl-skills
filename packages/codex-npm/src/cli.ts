#!/usr/bin/env node
import { readFileSync, realpathSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { Worker } from "node:worker_threads";
import type { Options, Result } from "./types.js";
const pkg = JSON.parse(
	readFileSync(
		fileURLToPath(new URL("../package.json", import.meta.url)),
		"utf8",
	),
) as { version: string };
const HELP = `ccl-skills-codex — npm manager for the ccl-skills Codex local marketplace\n\nUsage:\n  ccl-skills-codex install [--json]\n  ccl-skills-codex update [--yes] [--allow-downgrade] [--json]\n  ccl-skills-codex doctor [--json]\n  ccl-skills-codex uninstall [--yes] [--json]\n\nUpdate and uninstall are dry-run unless --yes is supplied.\nCodex >=0.133.0 is required.`;
type Parsed = {
	direct?: { code: number; stream: "stdout" | "stderr"; text: string };
	command?: string;
	options?: Options;
	json?: boolean;
};
export function parseArgs(args: string[]): Parsed {
	if (
		!args.length ||
		args.includes("--help") ||
		args.includes("-h") ||
		args[0] === "help"
	)
		return { direct: { code: 0, stream: "stdout", text: HELP } };
	if (args.includes("--version"))
		return { direct: { code: 0, stream: "stdout", text: pkg.version } };
	const command = args[0],
		flags = args.slice(1),
		allowed = new Set(["--yes", "-y", "--json", "--allow-downgrade"]);
	if (
		!["install", "update", "doctor", "uninstall"].includes(command) ||
		flags.some((x) => !allowed.has(x))
	)
		return {
			direct: {
				code: 2,
				stream: "stderr",
				text: "Invalid command or option. Run --help.",
			},
		};
	const yes = flags.includes("--yes") || flags.includes("-y"),
		allowDowngrade = flags.includes("--allow-downgrade");
	if (allowDowngrade && (command !== "update" || !yes))
		return {
			direct: {
				code: 2,
				stream: "stderr",
				text: "--allow-downgrade is valid only with update --yes.",
			},
		};
	if (command === "install" && yes)
		return {
			direct: {
				code: 2,
				stream: "stderr",
				text: "install does not accept --yes; it executes after safety checks.",
			},
		};
	return {
		command,
		options: { yes, allowDowngrade },
		json: flags.includes("--json"),
	};
}
const validResult = (x: unknown): x is Result =>
	!!x &&
	typeof x === "object" &&
	[0, 1, 2, 3, 4, 5, 130].includes((x as Result).code) &&
	typeof (x as Result).status === "string" &&
	typeof (x as Result).message === "string";
export type SupervisorDeps = {
	workerFactory?: (data: unknown) => Pick<Worker, "once" | "on">;
	onSignal?: (fn: () => void) => () => void;
};
export async function supervise(
	command: string,
	options: Options,
	deps: SupervisorDeps = {},
): Promise<Result> {
	const abortBuffer = new SharedArrayBuffer(Int32Array.BYTES_PER_ELEMENT),
		abort = new Int32Array(abortBuffer);
	let signalled = false,
		settled = false,
		messages = 0;
	const worker =
		deps.workerFactory?.({ protocol: 1, command, options, abortBuffer }) ||
		new Worker(new URL("./cli-worker.js", import.meta.url), {
			workerData: { protocol: 1, command, options, abortBuffer },
		});
	const remove = (
		deps.onSignal ||
		((fn) => {
			process.on("SIGINT", fn);
			return () => process.removeListener("SIGINT", fn);
		})
	)(() => {
		signalled = true;
		Atomics.store(abort, 0, 1);
	});
	return await new Promise((resolve) => {
		const finish = (r: Result) => {
			if (settled) return;
			settled = true;
			remove();
			resolve(
				signalled && r.code !== 5 ? { ...r, code: 130, interrupted: true } : r,
			);
		};
		worker.on("message", (x) => {
			messages++;
			if (messages > 1 || !validResult(x))
				finish({
					code: 5,
					status: "worker-error",
					message: "worker protocol returned an invalid result",
				});
			else
				queueMicrotask(() => {
					if (messages === 1) finish(x);
				});
		});
		worker.once("error", () =>
			finish({
				code: 5,
				status: "worker-error",
				message: "worker failed with unknown finality",
			}),
		);
		worker.once("exit", (code) => {
			if (!settled && code !== 0)
				finish({
					code: 5,
					status: "worker-error",
					message: "worker exited without a result; finality is unknown",
				});
			else if (!settled)
				queueMicrotask(() => {
					if (!settled)
						finish({
							code: 5,
							status: "worker-error",
							message: "worker exited without a result; finality is unknown",
						});
				});
		});
	});
}
function write(stream: NodeJS.WriteStream, text: string) {
	try {
		stream.write(`${text}\n`);
	} catch (e) {
		if (
			!["EPIPE", "ERR_STREAM_DESTROYED"].includes(
				(e as NodeJS.ErrnoException).code || "",
			)
		)
			throw e;
	}
}
export async function main(args: string[]): Promise<number> {
	const parsed = parseArgs(args);
	if (parsed.direct) {
		write(
			parsed.direct.stream === "stdout" ? process.stdout : process.stderr,
			parsed.direct.text,
		);
		return parsed.direct.code;
	}
	const result = await supervise(parsed.command!, parsed.options!);
	write(
		process.stdout,
		parsed.json
			? JSON.stringify(result)
			: `${result.status}: ${result.message}${result.plan ? `\n${result.plan.map((x) => `- ${x}`).join("\n")}` : ""}`,
	);
	return result.code;
}
export function isDirectEntrypoint(
	importMetaUrl: string,
	argv1: string | undefined,
): boolean {
	if (!argv1) return false;
	try {
		return realpathSync(fileURLToPath(importMetaUrl)) === realpathSync(argv1);
	} catch {
		return false;
	}
}
process.stdout.on("error", (e) => {
	if ((e as NodeJS.ErrnoException).code === "EPIPE") process.exitCode = 0;
	else throw e;
});
process.stderr.on("error", (e) => {
	if ((e as NodeJS.ErrnoException).code === "EPIPE") process.exitCode = 0;
	else throw e;
});
if (isDirectEntrypoint(import.meta.url, process.argv[1]))
	main(process.argv.slice(2)).then((code) => {
		process.exitCode = code;
	});
