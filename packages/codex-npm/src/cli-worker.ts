import { isMainThread, parentPort, workerData } from "node:worker_threads";
import { run } from "./index.js";
import type { Options, Result } from "./types.js";
type Request = {
	protocol: number;
	command: string;
	options: Options;
	abortBuffer: SharedArrayBuffer;
};
function valid(x: unknown): x is Request {
	if (!x || typeof x !== "object") return false;
	const r = x as Request;
	return (
		r.protocol === 1 &&
		["install", "update", "doctor", "uninstall"].includes(r.command) &&
		r.options !== null &&
		typeof r.options === "object" &&
		r.abortBuffer instanceof SharedArrayBuffer &&
		r.abortBuffer.byteLength === Int32Array.BYTES_PER_ELEMENT
	);
}
if (!isMainThread) {
	let result: Result;
	try {
		if (!valid(workerData)) throw Error("invalid worker protocol");
		const abort = new Int32Array(workerData.abortBuffer);
		result = run(workerData.command, workerData.options, {
			isInterrupted: () => Atomics.load(abort, 0) === 1,
		});
	} catch {
		result = {
			code: 5,
			status: "worker-error",
			message: "worker failed with unknown finality",
		};
	}
	parentPort!.postMessage(result);
}
