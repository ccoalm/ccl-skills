import { spawn } from "node:child_process";
import { createHash, randomUUID } from "node:crypto";
import { accessSync, constants, existsSync, lstatSync, mkdirSync, mkdtempSync, readdirSync, rmSync, openSync, closeSync, fsyncSync, readFileSync, realpathSync, renameSync, unlinkSync, writeFileSync } from "node:fs";
import { dirname, isAbsolute, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import type { Result } from "./types.js";

const OWNER = "ccl-skills-auto-update-v1";
const SOURCES = new Set(["https://github.com/ccoalm/ccl-skills.git", "git@github.com:ccoalm/ccl-skills.git", "ssh://git@github.com/ccoalm/ccl-skills.git"]);
const REF = "ccl-skills@ccl-skills";
const LAUNCHCTL = "/bin/launchctl";
const MAX_LOCK_AGE_MS = 15 * 60 * 1000;
const digest = (text: string) => createHash("sha256").update(text).digest("hex");
const clean = (value: string) => value.length > 0 && !/[\x00-\x1f\x7f]/.test(value);
export type AutoUpdateAction = "enable" | "disable" | "status";
export interface CommandResult { code: number | null; stdout: string; stderr: string; failure?: string }
export interface CommandOptions { cwd?: string; graceful?: boolean }
export type Command = (file: string, args: string[], env: NodeJS.ProcessEnv, timeout: number, options?: CommandOptions) => Promise<CommandResult>;
export type AutoUpdateHost = "codex" | "opencode";
export interface AutoUpdateDeps { host?: AutoUpdateHost; env?: NodeJS.ProcessEnv; platform?: string; command?: Command; node?: string }
interface Context { host: AutoUpdateHost; home: string; profile: string; root: string; label: string; plist: string; runner: string; config: string; log: string; uid: number }
interface State { host: AutoUpdateHost; npm?: string; owner: string; schema: 1; home: string; profile: string; uid: number; label: string; node: string; binary: string; path: string; runnerHash: string; enabled: boolean }

/** Kill the owned process group on timeout/cancellation, including Git children.
 * Output is bounded and never persisted: child diagnostics can contain secrets. */
export const runCommand: Command = (file, args, env, timeout, options = {}) => new Promise((done) => {
	const child = spawn(file, args, { env, cwd: options.cwd, stdio: ["ignore", "pipe", "pipe"], detached: true });
	const stdout: Buffer[] = [], stderr: Buffer[] = [];
	let stdoutBytes = 0, stderrBytes = 0, failure: string | undefined;
	let grace: NodeJS.Timeout | undefined;
	const signalGroup = (signal: NodeJS.Signals) => {
		if (child.pid) { try { process.kill(-child.pid, signal); } catch { child.kill(signal); } }
	};
	const kill = (reason: string) => {
		if (failure) return;
		failure = reason;
		if (options.graceful) {
			signalGroup("SIGINT");
			grace = setTimeout(() => { failure = `${reason}-forced-finality-unknown`; signalGroup("SIGKILL"); }, 10000);
		} else signalGroup("SIGKILL");
	};
	const interrupt = () => kill("interrupted");
	process.once("SIGINT", interrupt);
	process.once("SIGTERM", interrupt);
	const timer = setTimeout(() => kill("timeout"), timeout);
	child.stdout.on("data", (chunk: Buffer) => {
		if (stdoutBytes + chunk.length > 4 * 1024 * 1024) { kill("output-limit"); return; }
		stdoutBytes += chunk.length; stdout.push(chunk);
	});
	child.stderr.on("data", (chunk: Buffer) => {
		if (stderrBytes + chunk.length > 64 * 1024) { kill("output-limit"); return; }
		stderrBytes += chunk.length; stderr.push(chunk);
	});
	child.on("error", () => { failure ||= "unavailable"; });
	child.on("close", (code) => {
		clearTimeout(timer); if (grace) clearTimeout(grace);
		process.removeListener("SIGINT", interrupt); process.removeListener("SIGTERM", interrupt);
		done({ code, stdout: Buffer.concat(stdout).toString(), stderr: Buffer.concat(stderr).toString(), ...(failure ? { failure } : {}) });
	});
});

// Child cancellation belongs to runCommand; this scope also covers the gaps
// between children and keeps repeated signals from bypassing owned cleanup.
function interruptionScope(execute: Command) {
	let interrupted = false;
	const interrupt = () => { interrupted = true; };
	const check = () => {
		if (interrupted) throw new Error("Automatic-update operation interrupted; inspect host state before retrying");
	};
	process.on("SIGINT", interrupt);
	process.on("SIGTERM", interrupt);
	const command: Command = async (...args) => {
		check();
		const result = await execute(...args);
		// Promise continuations can outrun queued signal callbacks. Yield to the
		// event loop before accepting a result or starting another command.
		await new Promise<void>(resolve => setImmediate(resolve));
		// Preserve child failures, including forced termination's unknown finality.
		if (!result.failure) check();
		return result;
	};
	return { command, dispose: () => {
		process.removeListener("SIGINT", interrupt);
		process.removeListener("SIGTERM", interrupt);
	} };
}

function owned(path: string, directory = false): boolean {
	try {
		const s = lstatSync(path);
		if (s.isSymbolicLink() || (directory ? !s.isDirectory() : !s.isFile() || s.nlink !== 1) || s.uid !== process.getuid?.() || (s.mode & 0o022))
			throw new Error(`Unsafe ownership or file type: ${path}`);
		return true;
	} catch (error) { if ((error as NodeJS.ErrnoException).code === "ENOENT") return false; throw error; }
}
function directory(path: string) {
	if (owned(path, true)) return;
	directory(dirname(path));
	mkdirSync(path, { mode: 0o700 });
}
function atomic(path: string, contents: string) {
	owned(dirname(path), true); owned(path);
	const temp = `${path}.${randomUUID()}.tmp`;
	const fd = openSync(temp, "wx", 0o600);
	try {
		try { writeFileSync(fd, contents); fsyncSync(fd); } finally { closeSync(fd); }
		owned(path); renameSync(temp, path);
	} finally { if (existsSync(temp)) unlinkSync(temp); }
}
function context(env: NodeJS.ProcessEnv, host: AutoUpdateHost = "codex"): Context {
	if (host !== "codex" && host !== "opencode") throw new Error("Unsupported auto-update host");
	if (!env.HOME || !isAbsolute(env.HOME) || !clean(env.HOME)) throw new Error("HOME must be an existing absolute directory");
	const home = realpathSync(env.HOME), profileInput = host === "codex" ? env.CODEX_HOME || join(home, ".codex") : join(home, ".config", "opencode");
	if (!isAbsolute(profileInput) || !clean(profileInput)) throw new Error("Host profile must be an existing absolute directory");
	if (!existsSync(profileInput)) throw new Error(`${host} profile is absent; install CCL for this host before enabling automatic updates`);
	const profile = realpathSync(profileInput), uid = process.getuid?.();
	if (!clean(home) || !clean(profile)) throw new Error("Canonical HOME and host profile paths must not contain control characters");
	if (uid === undefined || uid === 0) throw new Error("Automatic updates require a non-root user");
	owned(home, true); owned(profile, true);
	owned(join(home, "Library"), true); owned(join(home, "Library", "LaunchAgents"), true);
	const root = join(profile, "ccl-skills-auto-update"), label = `com.ccoalm.ccl-skills.${host}.${digest(profile).slice(0, 16)}`;
	return { host, home, profile, uid, root, label, plist: join(home, "Library", "LaunchAgents", `${label}.plist`), runner: join(root, "runner.mjs"), config: join(root, "state.json"), log: join(root, "last-run.json") };
}
function readState(c: Context): State | null {
	if (!owned(c.root, true)) return null;
	if (!owned(c.config)) throw new Error("Automatic-update directory has no ownership record; leave it intact and inspect it manually");
	const s = JSON.parse(readFileSync(c.config, "utf8")) as State;
	const keys = ["host", ...(c.host === "opencode" ? ["npm"] : []), "owner", "schema", "home", "profile", "uid", "label", "node", "binary", "path", "runnerHash", "enabled"];
	if (Object.keys(s).sort().join() !== keys.sort().join() || s.host !== c.host || s.owner !== OWNER || s.schema !== 1 || s.home !== c.home || s.profile !== c.profile || s.uid !== c.uid || s.label !== c.label || typeof s.enabled !== "boolean" || !/^[a-f0-9]{64}$/.test(s.runnerHash) || ![s.node, s.binary, s.path].every(v => typeof v === "string" && clean(v)) || !isAbsolute(s.node) || !isAbsolute(s.binary) || !s.path.split(":").every(isAbsolute) || (c.host === "opencode" && (typeof s.npm !== "string" || !clean(s.npm) || !isAbsolute(s.npm))))
		throw new Error("Invalid automatic-update ownership record; no files were changed");
	return s;
}
function executable(name: string, path: string) {
	for (const dir of path.split(":")) {
		const file = join(dir, name);
		try { accessSync(file, constants.X_OK); if (lstatSync(realpathSync(file)).isFile()) return file; } catch { /* try the next PATH entry */ }
	}
	throw new Error(`${name} executable unavailable; install it and rerun auto-update enable`);
}
const runtimeEnv = (s: State): NodeJS.ProcessEnv => s.host === "codex" ? { HOME: s.home, CODEX_HOME: s.profile, PATH: s.path, GIT_TERMINAL_PROMPT: "0" } : { HOME: s.home, PATH: s.path, CCL_SKILLS_SKIP_SELF_UPDATE: "1", CCL_SKILLS_NO_UPDATE_NOTIFIER: "1" };
const xml = (text: string) => text.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;").replace(/"/g, "&quot;").replace(/'/g, "&apos;");
function plist(c: Context, s: State): string {
	const string = (v: string) => `<string>${xml(v)}</string>`;
	return `<?xml version="1.0" encoding="UTF-8"?>\n<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">\n<plist version="1.0"><dict>\n<key>Label</key>${string(c.label)}\n<key>ProgramArguments</key><array>${[s.node, c.runner, "--run", s.host].map(string).join("")}</array>\n<key>EnvironmentVariables</key><dict>${Object.entries(runtimeEnv(s)).map(([k,v]) => `<key>${k}</key>${string(v!)}`).join("")}</dict>\n<key>ExitTimeOut</key><integer>30</integer>\n<key>StartInterval</key><integer>86400</integer>\n<key>RunAtLoad</key><true/>\n<key>WorkingDirectory</key>${string(c.home)}\n<key>StandardOutPath</key><string>/dev/null</string>\n<key>StandardErrorPath</key><string>/dev/null</string>\n</dict></plist>\n`;
}
function verifyFiles(c: Context, s: State) {
	if (owned(c.runner) && digest(readFileSync(c.runner, "utf8")) !== s.runnerHash) throw new Error("Automatic-update runner changed; refusing to replace it");
	if (owned(c.plist) && readFileSync(c.plist, "utf8") !== plist(c, s)) throw new Error("Schedule is not the owned automatic-update job; refusing to change it");
}
async function registration(c: Context, s: State, command: Command): Promise<{ registered: boolean; running?: boolean; lastExit?: number }> {
	const r = await command(LAUNCHCTL, ["print", `gui/${c.uid}/${c.label}`], runtimeEnv(s), 10000);
	if (r.failure) throw new Error(`launchctl inspection failed (${r.failure}); registration is unknown`);
	if (r.code !== 0) {
		if (/Could not find service|service could not be found/i.test(r.stderr)) return { registered: false };
		throw new Error("launchctl inspection failed; registration is unknown. Run from your logged-in macOS session");
	}
	const match = r.stdout.match(/^\s*path = (.+)$/m);
	if (!match || match[1] !== c.plist) throw new Error("A foreign launchd job uses this label; no scheduling changes made");
	const exit = r.stdout.match(/^\s*last exit code = (\d+)/m);
	return { registered: true, running: /^\s*state = running\s*$/m.test(r.stdout), ...(exit ? { lastExit: Number(exit[1]) } : {}) };
}
async function validateCodex(s: State, command: Command) {
	const query = async (args: string[]) => {
		const r = await command(s.binary, ["--no-daemon", "plugin", ...args, "--json"], runtimeEnv(s), 10000);
		if (r.failure || r.code !== 0) throw new Error("Codex public JSON query failed; install a Codex CLI supporting --no-daemon and plugin JSON queries, then retry");
		try { return JSON.parse(r.stdout); } catch { throw new Error("Codex returned invalid JSON; plugin source is unknown"); }
	};
	const markets = await query(["marketplace", "list"]);
	if (!Array.isArray(markets.marketplaces)) throw new Error("Codex marketplace state is unknown");
	const matches = markets.marketplaces.filter((m: any) => m.name === "ccl-skills");
	if (matches.length !== 1) throw new Error("Requires an existing Git marketplace named ccl-skills. npm snapshots are not supported; use ccl-skills update --yes for npm-managed installs");
	const source = matches[0].marketplaceSource;
	if (source?.sourceType !== "git" || !SOURCES.has(source.source)) throw new Error("Requires the canonical ccl-skills Git marketplace. npm/local snapshots cannot auto-update; use ccl-skills update --yes or explicitly migrate to the Git install described in the README");
	const plugins = await query(["list", "--marketplace", "ccl-skills"]);
	if (!Array.isArray(plugins.installed)) throw new Error("Codex installed plugin state is unknown");
	const installed = plugins.installed.filter((p: any) => p.pluginId === REF);
	if (installed.length !== 1 || installed[0].installed !== true || installed[0].enabled !== true || installed[0].marketplaceName !== "ccl-skills" || installed[0].source?.source !== "git" || !SOURCES.has(installed[0].source?.url) || installed[0].marketplaceSource?.sourceType !== "git" || !SOURCES.has(installed[0].marketplaceSource?.source))
		throw new Error("ccl-skills@ccl-skills must be installed and enabled from the canonical Git marketplace before enabling updates");
}
const PACKAGE = "@ccoalm/ccl-skills";
const REGISTRY = "https://registry.npmjs.org/";
const stableVersion = (value: unknown): value is string => typeof value === "string" && /^\d+\.\d+\.\d+$/.test(value);
function compareVersions(left: string, right: string): number {
	const a = left.split(".").map(BigInt), b = right.split(".").map(BigInt);
	for (let i = 0; i < 3; i++) if (a[i] !== b[i]) return a[i] > b[i] ? 1 : -1;
	return 0;
}
async function packageCommand(s: State, cli: string, action: "doctor" | "update", command: Command, cwd = s.home): Promise<Result> {
	const args = [cli, action, "--host", "opencode", ...(action === "update" ? ["--yes"] : []), "--json"];
	const result = await command(s.node, args, runtimeEnv(s), action === "update" ? 120000 : 30000, { cwd, graceful: action === "update" });
	if (result.failure) throw new Error(`OpenCode ${action} ${result.failure}; inspect installed assets before retrying`);
	let value: Result;
	try { value = JSON.parse(result.stdout); } catch { throw new Error(`OpenCode ${action} returned invalid JSON; finality is unknown`); }
	if (!value || typeof value !== "object" || ![0,1,2,3,4,5,130].includes(value.code) || result.code !== value.code || typeof value.message !== "string" || typeof value.status !== "string" || !/^[a-z-]+$/.test(value.status))
		throw new Error(`OpenCode ${action} returned an invalid result; finality is unknown`);
	return value;
}
function healthyOpenCode(result: Result, expected?: string): string {
	if (result.code !== 0 || result.status !== "healthy" || result.details?.sourceKind !== "bundled" || !stableVersion(result.details?.version))
		throw new Error(`OpenCode requires a healthy npm-managed bundled CCL installation (${result.status}). Repair drift first; for source-copy installs, back up the existing CCL files and explicitly migrate with the npm installer before enabling updates`);
	if (expected && result.details.version !== expected) throw new Error("OpenCode post-update version does not match the fetched package; finality is unknown");
	return result.details.version;
}
async function validateInstallation(s: State, command: Command) {
	if (s.host === "codex") return validateCodex(s, command);
	const cli = fileURLToPath(new URL("./cli.js", import.meta.url));
	healthyOpenCode(await packageCommand(s, cli, "doctor", command));
}
function jsonFile(path: string): any {
	if (!owned(path) || lstatSync(path).size > 1024 * 1024) throw new Error("Fetched package metadata is missing or oversized");
	return JSON.parse(readFileSync(path, "utf8"));
}
function verifyPrivateTree(root: string) {
	owned(root, true);
	for (const entry of readdirSync(root, { withFileTypes: true })) {
		const path = join(root, entry.name);
		if (entry.isDirectory()) verifyPrivateTree(path); else owned(path);
	}
}
async function updateOpenCode(c: Context, s: State, command: Command): Promise<string> {
	const pending = mkdtempSync(join(c.root, "refresh-"));
	try {
		const prefix = join(pending, "package"), cache = join(pending, "cache");
		directory(prefix); directory(cache);
		const userConfig = join(pending, "user.npmrc"), globalConfig = join(pending, "global.npmrc");
		atomic(userConfig, ""); atomic(globalConfig, "");
		atomic(join(prefix, "package.json"), JSON.stringify({ private: true }));
		const result = await command(s.npm!, ["install", "--prefix", prefix, "--registry", REGISTRY, "--userconfig", userConfig, "--globalconfig", globalConfig, "--cache", cache, "--ignore-scripts", "--no-bin-links", "--no-audit", "--no-fund", "--package-lock=false", `${PACKAGE}@latest`], runtimeEnv(s), 180000, { cwd: prefix });
		if (result.failure || result.code !== 0) throw new Error(`OpenCode package refresh failed (${result.failure || `exit ${result.code}`}); installed assets were not changed`);
		verifyPrivateTree(prefix);
		const packageRoot = join(prefix, "node_modules", "@ccoalm", "ccl-skills"), pkg = jsonFile(join(packageRoot, "package.json")), release = jsonFile(join(packageRoot, "dist", "assets", "release.json"));
		if (pkg.name !== PACKAGE || !stableVersion(pkg.version) || pkg.type !== "module" || pkg.bin?.["ccl-skills"] !== "dist/cli.js" || release.npmPackage !== PACKAGE || release.version !== pkg.version)
			throw new Error("Fetched OpenCode package identity is invalid; installed assets were not changed");
		const cli = join(packageRoot, "dist", "cli.js");
		if (!owned(cli)) throw new Error("Fetched package CLI is missing");
		const current = healthyOpenCode(await packageCommand(s, cli, "doctor", command, prefix));
		if (compareVersions(pkg.version, current) < 0) return `OpenCode retains newer installed CCL ${current}; registry latest is ${pkg.version}`;
		if (!readState(c)?.enabled) throw new Error("Schedule was disabled; OpenCode assets were not changed");
		const updated = await packageCommand(s, cli, "update", command, prefix);
		if (updated.code !== 0 || !["updated", "healthy"].includes(updated.status)) throw new Error(`OpenCode update returned ${updated.status}; inspect installed assets before retrying`);
		healthyOpenCode(await packageCommand(s, cli, "doctor", command, prefix), pkg.version);
		return `OpenCode CCL assets updated to ${pkg.version}; restart OpenCode to load changes`;
	} finally {
		// Only this invocation's exclusive, freshly created prefix is removed.
		owned(c.root, true); owned(pending, true);
		rmSync(pending, { recursive: true, force: true });
	}
}
function lastRun(c: Context): unknown {
	if (!owned(c.log)) return null;
	const text = readFileSync(c.log, "utf8");
	if (text.length > 16384) throw new Error("Automatic-update run record exceeds its size limit");
	const record = JSON.parse(text);
	if (!record || record.owner !== OWNER || !["running", "success", "failed"].includes(record.status) || typeof record.message !== "string" || typeof record.finishedAt !== "string") throw new Error("Invalid automatic-update run record; inspect the log before retrying");
	return record;
}
function lockState(path: string): "absent" | "active" | "stale" | "uncertain" {
	if (!owned(path)) return "absent";
	const pid = Number(readFileSync(path, "utf8"));
	if (!Number.isSafeInteger(pid) || pid <= 0) throw new Error(`Invalid automatic-update lock: ${path}; inspect it manually`);
	// PID liveness cannot establish process identity after a crash and reuse.
	// A bounded age prevents indefinite healthy overlap; never reclaim the lock.
	if (Math.abs(Date.now() - lstatSync(path).mtimeMs) >= MAX_LOCK_AGE_MS) return "uncertain";
	try { process.kill(pid, 0); return "active"; }
	catch (error) { if ((error as NodeJS.ErrnoException).code === "ESRCH") return "stale"; throw error; }
}
function lock(c: Context, name = "run.lock"): () => void {
	const path = join(c.root, name), state = lockState(path);
	if (state === "stale") throw new Error(`Stale automatic-update lock: ${path}. Confirm its PID has exited, remove only this lock file, then retry`);
	if (state === "uncertain") throw new Error(`Automatic-update lock is older than 15 minutes or its timestamp is uncertain: ${path}. Inspect the PID and job; remove only this lock after confirming no updater owns it`);
	if (state === "active") throw new Error("Automatic-update operation already running; retry after it finishes");
	try {
		const fd = openSync(path, "wx", 0o600);
		try { writeFileSync(fd, String(process.pid)); } finally { closeSync(fd); }
	} catch (error) {
		if ((error as NodeJS.ErrnoException).code === "EEXIST") throw new Error("Automatic-update operation already running; retry after it finishes");
		throw error;
	}
	return () => { if (owned(path) && readFileSync(path, "utf8") === String(process.pid)) unlinkSync(path); };
}

export async function autoUpdate(action: AutoUpdateAction, deps: AutoUpdateDeps = {}): Promise<Result> {
	if ((deps.platform || process.platform) !== "darwin") return { code: 4, status: "unsupported-platform", message: "Automatic updates currently require macOS launchd. Use the documented manual update commands on other platforms." };
	const env = deps.env || process.env;
	const scope = interruptionScope(deps.command || runCommand), command = scope.command;
	let release: (() => void) | undefined;
	try {
		const c = context(env, deps.host);
		const name = c.host === "codex" ? "Codex" : "OpenCode";
		let s = readState(c);
		if (!s && action !== "enable") return { code: 0, status: "disabled", message: `${name} automatic updates are not configured for this profile.` };
		if (s) verifyFiles(c, s);
		if (action === "status") {
			const registrationState = await registration(c, s!, command), registered = registrationState.registered, last = lastRun(c) as { status?: string } | null;
			const enabled = s!.enabled && registered && owned(c.runner) && owned(c.plist);
			const runLock = lockState(join(c.root, "run.lock"));
			const manageLock = lockState(join(c.root, "manage.lock"));
			const staleLock = runLock === "stale" || manageLock === "stale";
			const uncertainLock = runLock === "uncertain" || manageLock === "uncertain";
			const running = registrationState.running || runLock === "active";
			const failed = staleLock || uncertainLock || last?.status === "failed" || !!registrationState.lastExit || (last?.status === "running" && !running);
			const details = { registered, enabled, running, staleLock, uncertainLock, lastExit: registrationState.lastExit, profile: c.profile, label: c.label, log: c.log, lastRun: last };
			if (!enabled) {
				if (registered || s!.enabled) return { code: 5, status: "scheduler-error", message: "Schedule registration is incomplete; rerun auto-update enable or disable to recover.", details };
				return { code: 0, status: "disabled", message: `${name} automatic updates are disabled.`, details };
			}
			let summary = last?.status || "not yet recorded";
			if (running) summary = "running";
			if (failed) summary = "failed or interrupted; inspect the run log";
			if (staleLock) summary = "stale lock; confirm its PID has exited, remove only that lock file, then retry";
			if (uncertainLock) summary = "lock older than 15 minutes or timestamp uncertain; inspect its PID and job before recovery, never remove a running updater's lock";
			return { code: failed ? 5 : 0, status: failed ? "update-failed" : "enabled", message: `${name} automatic updates are scheduled every 24 hours. Last run: ${summary}. Log: ${c.log}`, details };
		}
		if (!s) {
			if (owned(c.plist)) throw new Error("A schedule already exists without our ownership record; refusing to replace it");
			const path = (env.PATH || "/usr/bin:/bin").split(":").filter(p => isAbsolute(p) && clean(p)).join(":");
			const source = readFileSync(fileURLToPath(import.meta.url), "utf8");
			s = { host: c.host, ...(c.host === "opencode" ? { npm: executable("npm", path) } : {}), owner: OWNER, schema: 1, home: c.home, profile: c.profile, uid: c.uid, label: c.label, node: deps.node || executable("node", path), binary: executable(c.host, path), path, runnerHash: digest(source), enabled: false };
			await validateInstallation(s, command);
			if ((await registration(c, s, command)).registered) throw new Error("A schedule is registered without our ownership record; refusing to change it");
			mkdirSync(c.root, { mode: 0o700 });
			atomic(c.config, JSON.stringify(s));
		}
		release = lock(c, "manage.lock");
		s = readState(c)!;
		verifyFiles(c, s);
		const registered = (await registration(c, s, command)).registered;
		if (action === "disable") {
			s.enabled = false;
			atomic(c.config, JSON.stringify(s));
			if (registered) {
				const result = await command(LAUNCHCTL, ["bootout", `gui/${c.uid}`, c.plist], runtimeEnv(s), 10000);
				if (result.failure || result.code !== 0) throw new Error("Schedule was fenced but unload failed; rerun auto-update disable from your logged-in session");
			}
			if ((await registration(c, s, command)).registered) throw new Error("Schedule remains registered; disabling is incomplete");
			if (owned(c.plist)) unlinkSync(c.plist);
			return { code: 0, status: "disabled", message: `${name} automatic updates are disabled. Runner and log retained at ${c.root}.` };
		}
		await validateInstallation(s, command);
		if (registered && s.enabled && owned(c.runner) && owned(c.plist)) return { code: 0, status: "enabled", message: `${name} automatic updates are already scheduled every 24 hours. Log: ${c.log}`, details: { label: c.label, log: c.log } };
		if (registered) throw new Error("An incomplete schedule remains registered; run auto-update disable, then enable");
		const source = readFileSync(fileURLToPath(import.meta.url), "utf8");
		if (!owned(c.runner)) {
			if (s.runnerHash !== digest(source)) throw new Error("Saved runner is missing and belongs to a different package version; restore the saved runner before retrying");
			atomic(c.runner, source);
		}
		directory(dirname(c.plist));
		atomic(c.plist, plist(c, s));
		s.enabled = true;
		atomic(c.config, JSON.stringify(s));
		const result = await command(LAUNCHCTL, ["bootstrap", `gui/${c.uid}`, c.plist], runtimeEnv(s), 10000);
		if (result.failure || result.code !== 0 || !(await registration(c, s, command)).registered) throw new Error("Schedule registration failed; files retained for recovery. Rerun auto-update enable from your logged-in macOS session");
		return { code: 0, status: "enabled", message: `${name} automatic updates are scheduled every 24 hours and at login. Log: ${c.log}`, details: { label: c.label, profile: c.profile, log: c.log } };
	} catch (error) {
		return { code: 5, status: "auto-update-error", message: error instanceof Error ? error.message : "Automatic-update operation failed" };
	} finally {
		try { release?.(); } finally { scope.dispose(); }
	}
}

export async function runScheduled(env: NodeJS.ProcessEnv = process.env, execute: Command = runCommand, host: AutoUpdateHost = "codex"): Promise<Result> {
	const scope = interruptionScope(execute), command = scope.command;
	let release: (() => void) | undefined, c: Context | undefined;
	try {
		c = context(env, host);
		let s = readState(c);
		if (!s || !s.enabled) return { code: 0, status: "disabled", message: "Schedule disabled; no update performed" };
		verifyFiles(c, s);
		release = lock(c);
		s = readState(c);
		if (!s?.enabled) return { code: 0, status: "disabled", message: "Schedule disabled; no update performed" };
		const startedAt = new Date().toISOString();
		const record = (status: string, message: string) => atomic(c!.log, JSON.stringify({ owner: OWNER, status, startedAt, finishedAt: new Date().toISOString(), message }));
		record("running", `Checking the installed ${s.host} CCL assets`);
		try {
			if (s.host === "opencode") {
				const message = await updateOpenCode(c, s, command);
				record("success", message);
				return { code: 0, status: "updated", message };
			}
			await validateCodex(s, command);
			for (const args of [["marketplace", "upgrade", "ccl-skills"], ["add", REF]]) {
				if (!readState(c)?.enabled) throw new Error("Schedule was disabled; no further update commands performed");
				const result = await command(s.binary, ["--no-daemon", "plugin", ...args], runtimeEnv(s), 120000);
				if (result.failure || result.code !== 0) throw new Error(`${args[0]} failed (${result.failure || `exit ${result.code}`}); inspect Codex and retry on the next scheduled run`);
				await validateCodex(s, command);
			}
			record("success", "Git marketplace refreshed and ccl-skills plugin installed; restart Codex to load changes");
			return { code: 0, status: "updated", message: "ccl-skills Git plugin updated" };
		} catch (error) {
			const message = error instanceof Error ? error.message : "Scheduled update failed";
			record("failed", message);
			return { code: 5, status: "update-failed", message };
		}
	} catch (error) {
		const message = error instanceof Error ? error.message : "Scheduled update failed";
		if (message.includes("already running")) return { code: 0, status: "skipped", message };
		if (release && c) {
			try { atomic(c.log, JSON.stringify({ owner: OWNER, status: "failed", finishedAt: new Date().toISOString(), message })); } catch { /* launchd last exit remains the independent failure signal */ }
		}
		return { code: 5, status: "auto-update-error", message };
	}
	finally {
		try { release?.(); } finally { scope.dispose(); }
	}
}
if (process.argv[2] === "--run" && process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
	runScheduled(process.env, runCommand, process.argv[3] as AutoUpdateHost || "codex").then(result => { process.exitCode = result.code; });
}
