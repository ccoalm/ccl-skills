// Update notice: a terminal side channel, never primary output.
// Display is bound to eligibility, cache freshness, and cooldown; the network
// check runs detached so no invocation pays for it. Every failure path is
// swallowed — a version check must never change what the command itself does.
import { dirname, join } from "node:path";
import { mkdirSync, renameSync, unlinkSync, writeFileSync, readFileSync } from "node:fs";

export type Cache = {
	latest?: string;
	lastCheckedAt?: string;
	notifiedVersion?: string;
	notifiedAt?: string;
};
export type NoticeInput = {
	current: string;
	cache?: Cache;
	now: number;
	env: Record<string, string | undefined>;
	stdoutTTY: boolean;
	stderrTTY: boolean;
	columns?: number;
	json: boolean;
};
export type Verdict =
	| { show: false; reason: string }
	| { show: true; reason: "update-available"; latest: string };

export const TTL_MS = 24 * 60 * 60 * 1000;
export const CACHE_FILE = "version-check.json";
const MIN_COLUMNS = 60;
const OPT_OUT = ["CCL_SKILLS_NO_UPDATE_NOTIFIER", "NO_UPDATE_NOTIFIER"];
const CI_VARS = [
	"CI",
	"CONTINUOUS_INTEGRATION",
	"BUILD_NUMBER",
	"GITHUB_ACTIONS",
	"GITLAB_CI",
	"BUILDKITE",
	"CIRCLECI",
	"TRAVIS",
	"TEAMCITY_VERSION",
	"JENKINS_URL",
];
// Releases accept only stable MAJOR.MINOR.PATCH, so anything else — prerelease,
// build metadata, or a hostile string — is not a version we will ever suggest.
const STABLE = /^(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)$/;

const set = (env: NoticeInput["env"], names: string[]) =>
	names.some((name) => (env[name] ?? "") !== "");

/** Numeric precedence. Returns 0 when either side is not a stable version, so
 * an unparseable value can never be reported as newer. */
export function compareVersions(a: string, b: string): number {
	if (!STABLE.test(a) || !STABLE.test(b)) return 0;
	const left = a.split(".").map(Number), right = b.split(".").map(Number);
	for (let i = 0; i < 3; i++) if (left[i] !== right[i]) return left[i] - right[i];
	return 0;
}

export function pickLatest(packument: unknown): string | null {
	const tags = (packument as { "dist-tags"?: unknown })?.["dist-tags"];
	const latest = (tags as { latest?: unknown })?.latest;
	return typeof latest === "string" && STABLE.test(latest) ? latest : null;
}

/** Fails open toward refreshing: an absent, malformed, or future timestamp all
 * mean "check again", never "assume fresh". */
export function needsRefresh(cache: Cache | undefined, now: number, ttl = TTL_MS): boolean {
	const at = Date.parse(cache?.lastCheckedAt ?? "");
	return Number.isNaN(at) || at > now || now - at >= ttl;
}

/** The display gates that do not depend on cache contents. Shared by the notice
 * and the background check so `--json`, CI, and opt-out make no network call. */
function displayAllowed(input: NoticeInput): { ok: boolean; reason: string } {
	if (set(input.env, OPT_OUT)) return { ok: false, reason: "opt-out" };
	if (set(input.env, CI_VARS) || !input.stdoutTTY || !input.stderrTTY)
		return { ok: false, reason: "non-interactive" };
	if (input.json) return { ok: false, reason: "structured-output" };
	// A pty with no window size reports 0: that is "width unknown", not "zero
	// cells wide", so it must not be treated as a narrow terminal.
	if (input.columns !== undefined && input.columns > 0 && input.columns < MIN_COLUMNS)
		return { ok: false, reason: "narrow-terminal" };
	return { ok: true, reason: "eligible" };
}

export function refreshAllowed(input: NoticeInput): boolean {
	return displayAllowed(input).ok;
}

export function shouldNotify(input: NoticeInput): Verdict {
	const gate = displayAllowed(input);
	if (!gate.ok) return { show: false, reason: gate.reason };
	const latest = input.cache?.latest;
	if (!latest) return { show: false, reason: "no-cache" };
	if (compareVersions(latest, input.current) <= 0) return { show: false, reason: "up-to-date" };
	const notifiedAt = Date.parse(input.cache?.notifiedAt ?? "");
	if (
		input.cache?.notifiedVersion === latest &&
		!Number.isNaN(notifiedAt) &&
		input.now - notifiedAt < TTL_MS
	)
		return { show: false, reason: "cooldown" };
	return { show: true, reason: "update-available", latest };
}

/** Plain text only: colour is an enhancement, never the state carrier, and
 * every line fits the narrow-terminal floor this notice is gated on. */
export function formatNotice(current: string, latest: string): string {
	return [
		`Update available: ${current} -> ${latest}`,
		"Run: ccl-skills update --yes",
		"Silence: CCL_SKILLS_NO_UPDATE_NOTIFIER=1",
	].join("\n");
}

export function cachePath(root: string): string {
	return join(root, CACHE_FILE);
}

export type EmitDeps = { stderr: (text: string) => void; spawnCheck: () => void };

/** The only entry the CLI calls. It is handed a stderr writer and nothing that
 * can reach stdout, so the notice structurally cannot pollute primary output.
 * Returns the sanitized reason code; it never throws and never changes exit. */
export function emitNotice(input: NoticeInput, file: string, deps: EmitDeps): string {
	try {
		const cache = input.cache ?? readCache(file);
		const resolved = { ...input, cache };
		const verdict = shouldNotify(resolved);
		if (verdict.show) {
			deps.stderr(formatNotice(input.current, verdict.latest));
			writeCacheAtomic(file, {
				...cache,
				notifiedVersion: verdict.latest,
				notifiedAt: new Date(input.now).toISOString(),
			});
		}
		if (refreshAllowed(resolved) && needsRefresh(cache, input.now)) deps.spawnCheck();
		return verdict.reason;
	} catch {
		return "unavailable";
	}
}

export type RefreshOptions = {
	file: string;
	now?: number;
	fetchImpl?: (url: string, init: unknown) => Promise<{ ok: boolean; json: () => Promise<unknown> }>;
	timeoutMs?: number;
};
const REGISTRY = "https://registry.npmjs.org/@ccoalm%2fccl-skills";

/** Runs in a detached child, never on the caller's path. The check time is
 * stamped even on failure so an offline machine retries once per TTL, not once
 * per command; a failed check never erases a previously known version. */
export async function refresh(options: RefreshOptions): Promise<void> {
	const now = options.now ?? Date.now(),
		previous = readCache(options.file) ?? {};
	let latest: string | null = null;
	try {
		const response = await (options.fetchImpl ?? (fetch as RefreshOptions["fetchImpl"])!)(REGISTRY, {
			headers: { Accept: "application/vnd.npm.install-v1+json" },
			signal: AbortSignal.timeout(options.timeoutMs ?? 5000),
		});
		if (response.ok) latest = pickLatest(await response.json());
	} catch {
		/* offline, throttled, or malformed: keep the previous value */
	}
	writeCacheAtomic(options.file, {
		...previous,
		...(latest ? { latest } : {}),
		lastCheckedAt: new Date(now).toISOString(),
	});
}

export function readCache(path: string, read = readFileSync): Cache | undefined {
	try {
		const parsed = JSON.parse(read(path, "utf8") as string) as unknown;
		return parsed && typeof parsed === "object" && !Array.isArray(parsed)
			? (parsed as Cache)
			: undefined;
	} catch {
		return undefined;
	}
}

export type WriteDeps = {
	writeFileSync?: typeof writeFileSync;
	renameSync?: typeof renameSync;
	unlinkSync?: typeof unlinkSync;
	mkdirSync?: typeof mkdirSync;
};

/** Temp file in the target directory, then rename: a reader sees the old cache
 * or the whole new one, never a truncated one, and never an EXDEV failure. */
export function writeCacheAtomic(path: string, cache: Cache, deps: WriteDeps = {}): void {
	const write = deps.writeFileSync ?? writeFileSync,
		rename = deps.renameSync ?? renameSync,
		unlink = deps.unlinkSync ?? unlinkSync,
		temp = join(dirname(path), `.${CACHE_FILE}.tmp-${process.pid}`);
	try {
		// Without this the state root is absent until a host install runs, the
		// write fails every time, and the caller reschedules the check forever.
		(deps.mkdirSync ?? mkdirSync)(dirname(path), { recursive: true });
		write(temp, `${JSON.stringify(cache)}\n`, { encoding: "utf8", mode: 0o600 });
		rename(temp, path);
	} catch {
		try {
			unlink(temp);
		} catch {
			/* nothing to clean up */
		}
	}
}
