import { spawnSync } from "node:child_process";
import { existsSync, lstatSync, mkdirSync, mkdtempSync, readdirSync, readFileSync, rmdirSync, rmSync } from "node:fs";
import { dirname, isAbsolute, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { acquireLock, atomicJson, canonicalAlias, copyRegularTree, durableUnlink, verifyTree } from "./fs-safe.js";
import { readRelease } from "./manifest.js";
import type { OwnedFile, Options, Result } from "./types.js";
import { compare } from "./version.js";
import { probeHostVersion } from "./host-probe.js";

// `agy plugin install` copies a plugin directory into ~/.gemini/config/plugins/<name>
// and replaces that whole directory on reinstall, so nothing here needs to persist
// beyond a receipt: the version and the exact file inventory npm installed.
// Ownership means the installed directory is byte-identical to that receipt. The
// package's own bundled plugin is the install source; an update keeps a verified
// temporary backup of the current install for rollback. A journal records only
// that an operation was in flight: recovery compares the installed tree with the
// current package and the existing receipt, never with anything the journal says.
const NAME = "ccl-skills", OWNED = "ccl-skills-npm", PLUGIN_PREFIX = "marketplace/plugins/ccl-skills/";
const HOST_TIMEOUT_MS = 120_000;
const ROOT_ENTRIES = new Set(["install-receipt.json", "operation-journal.json"]);

export interface AntigravityContext {
	home?: string;
	assets?: string;
	env?: NodeJS.ProcessEnv;
	isInterrupted?: () => boolean;
}

interface Receipt { schema: 1; npmPackage: string; version: string; sourceCommit: string; files: OwnedFile[] }

function paths(context: AntigravityContext) {
	const rawHome = context.home ?? (context.env ? context.env.HOME : process.env.HOME);
	if (!rawHome || !isAbsolute(rawHome)) throw new Error("HOME is not set; refusing to guess a managed root");
	const home = resolve(rawHome), gemini = join(home, ".gemini"), root = join(gemini, OWNED),
		assets = resolve(context.assets || join(dirname(fileURLToPath(import.meta.url)), "assets"));
	return { gemini, root, receipt: join(root, "install-receipt.json"), journal: join(root, "operation-journal.json"),
		// Shared with scripts/install-antigravity.sh so the two installers never interleave.
		lock: join(gemini, "ccl-skills-plugin.lock"),
		installed: join(gemini, "config/plugins", NAME), assets, source: join(assets, "marketplace/plugins", NAME), release: join(assets, "release.json") };
}
type Paths = ReturnType<typeof paths>;

class InterruptedOperation extends Error {}
function throwIfInterrupted(context: AntigravityContext) {
	if (context.isInterrupted?.()) throw new InterruptedOperation("Antigravity operation interrupted");
}
const samePath = (left: string, right: string) => canonicalAlias(resolve(left)) === canonicalAlias(resolve(right));

function assertExclusiveRoot(p: Paths) {
	for (const component of [p.gemini, p.root]) {
		if (!existsSync(component)) continue;
		const stat = lstatSync(component);
		if (!stat.isDirectory() || stat.isSymbolicLink()) throw new Error(`unsafe managed component: ${component}`);
	}
	// Never adopt a directory that holds anything this adapter did not create.
	if (existsSync(p.root)) {
		const foreign = readdirSync(p.root).filter((entry) => !ROOT_ENTRIES.has(entry));
		if (foreign.length) throw new Error(`managed root holds unexpected entries: ${foreign.join(", ")}`);
	}
}

function agy(args: string[], context: AntigravityContext) {
	const result = spawnSync("agy", args, { encoding: "utf8", env: context.env || process.env, timeout: HOST_TIMEOUT_MS, killSignal: "SIGKILL", stdio: ["ignore", "pipe", "pipe"] });
	if (result.error) throw result.error;
	if (result.status !== 0) throw new Error(`agy ${args.slice(0, 2).join(" ")} failed (${result.status ?? result.signal}): ${(result.stderr || result.stdout).trim()}`);
	return result;
}

/** The plugin files inside a release, relative to the plugin directory. */
export function pluginFiles(files: OwnedFile[]): OwnedFile[] {
	return files.filter((file) => file.path.startsWith(PLUGIN_PREFIX)).map((file) => ({ ...file, path: file.path.slice(PLUGIN_PREFIX.length) }));
}

type HostState = { host: true; path: string | null; enabled: boolean } | { host: false; hostFailure: Result };
function state(context: AntigravityContext): HostState {
	const version = probeHostVersion("agy", context.env || process.env);
	if (!version.ok) return { host: false, hostFailure: { code: 4, status: `host-${version.kind}`, message: version.message } };
	let plugins: unknown;
	try {
		plugins = JSON.parse(agy(["plugin", "list", "--json"], context).stdout);
	} catch (error) {
		throw new Error(`Antigravity plugin state is not readable: ${String(error)}`);
	}
	if (!Array.isArray(plugins) || plugins.some((entry) => !entry || typeof entry !== "object" || typeof (entry as { name?: unknown }).name !== "string"))
		throw new Error("Antigravity plugin state has an invalid shape");
	const matches = plugins.filter((entry) => (entry as { name: string }).name === NAME) as Array<{ path?: unknown; enabled?: unknown }>;
	if (matches.length > 1) throw new Error("duplicate Antigravity ccl-skills plugins");
	if (!matches.length) return { host: true, path: null, enabled: false };
	if (typeof matches[0].path !== "string") throw new Error("Antigravity ccl-skills plugin has no path");
	return { host: true, path: matches[0].path, enabled: matches[0].enabled !== false };
}

/** True only when the destination provably does not exist (ENOENT); any other error is not proof. */
function destinationAbsent(p: Paths) {
	try { lstatSync(p.installed); return false; }
	catch (error) {
		if ((error as NodeJS.ErrnoException).code === "ENOENT") return true;
		throw error;
	}
}

function matches(p: Paths, current: HostState, files: OwnedFile[]) {
	return current.host && current.path !== null && samePath(current.path, p.installed) && verifyTree(p.installed, files).length === 0;
}

function readReceipt(p: Paths): Receipt | null {
	if (!existsSync(p.receipt)) return null;
	const value = JSON.parse(readFileSync(p.receipt, "utf8")) as Receipt;
	if (value?.schema !== 1 || typeof value.version !== "string" || !Array.isArray(value.files)
		|| value.files.some((file) => typeof file?.path !== "string" || file.path.startsWith("/") || file.path.split("/").includes("..")
			|| typeof file.sha256 !== "string" || typeof file.mode !== "number"))
		throw new Error("install receipt is malformed");
	return value;
}

function releaseReceipt(p: Paths): Receipt {
	const release = readRelease(p.release);
	return { schema: 1, npmPackage: release.npmPackage, version: release.version, sourceCommit: release.sourceCommit, files: pluginFiles(release.files) };
}

function unlinkIfPresent(path: string) {
	if (existsSync(path)) durableUnlink(path);
}

/** Settle an operation a previous run left unfinished. Mutates only with `apply`. */
function reconcile(p: Paths, context: AntigravityContext, apply: boolean): Result | null {
	if (!existsSync(p.journal)) return null;
	const pending: Result = { code: 3, status: "recovery-pending", message: "an interrupted Antigravity operation needs reconciling; rerun the same command with --yes or run install" };
	if (!apply) return pending;
	const current = state(context);
	if (!current.host) return current.hostFailure;
	const receipt = readReceipt(p), candidate = releaseReceipt(p);
	if (matches(p, current, candidate.files)) atomicJson(p.receipt, candidate);
	else if (receipt && matches(p, current, receipt.files)) { /* the old install is intact; keep its receipt */ }
	else if (current.path === null && destinationAbsent(p)) unlinkIfPresent(p.receipt);
	else return { code: 3, status: "state-unknown", message: "an interrupted Antigravity operation left a plugin that matches neither the installed receipt nor this package; inspect it, then `agy plugin uninstall ccl-skills`", details: { journal: p.journal } };
	unlinkIfPresent(p.journal);
	return null;
}

function install(p: Paths, source: string, files: OwnedFile[], context: AntigravityContext) {
	agy(["plugin", "install", source], context);
	const current = state(context);
	if (!current.host) throw new Error(current.hostFailure.message);
	if (!matches(p, current, files)) throw new Error("Antigravity did not install the exact packaged plugin");
}

function withLock(p: Paths, run: () => Result): Result {
	mkdirSync(p.gemini, { recursive: true });
	let unlock: (() => void) | null = null;
	try { unlock = acquireLock(p.lock); }
	catch { return { code: 3, status: "busy", message: `another ccl-skills Antigravity install holds ${p.lock}; if none is running, remove that file and retry` }; }
	try { return run(); } finally { unlock(); }
}

function doctor(context: AntigravityContext): Result {
	const p = paths(context);
	assertExclusiveRoot(p);
	const pending = reconcile(p, context, false);
	if (pending) return pending;
	const current = state(context);
	if (!current.host) return current.hostFailure;
	const receipt = readReceipt(p);
	if (!receipt) {
		if (current.path !== null || !destinationAbsent(p)) return { code: 3, status: "unowned-registration", message: "an Antigravity ccl-skills plugin exists without an npm install receipt" };
		return { code: 3, status: "absent", message: "ccl-skills is not installed for Antigravity" };
	}
	if (!matches(p, current, receipt.files))
		return { code: 3, status: "public-state-mismatch", message: "the installed Antigravity plugin does not match the npm install receipt" };
	if (current.host && !current.enabled) return { code: 3, status: "disabled", message: "the npm-owned Antigravity plugin is installed but disabled; run `agy plugin enable ccl-skills`" };
	return { code: 0, status: "healthy", message: `Antigravity uses @ccoalm/ccl-skills ${receipt.version}` };
}

function installOrUpdate(commandName: "install" | "update", options: Options, context: AntigravityContext): Result {
	const p = paths(context);
	assertExclusiveRoot(p);
	const settled = reconcile(p, context, commandName === "install" || Boolean(options.yes));
	if (settled) return settled;
	const current = state(context);
	if (!current.host) return current.hostFailure;
	const old = readReceipt(p), candidate = releaseReceipt(p);
	if (!old && (current.path !== null || !destinationAbsent(p)))
		return { code: 3, status: "unowned-registration", message: "refusing to replace an Antigravity ccl-skills plugin that npm did not install; inspect it, then `agy plugin uninstall ccl-skills`" };
	if (commandName === "update" && !old) return { code: 3, status: "not-installed", message: "update requires an existing npm-owned Antigravity installation" };
	if (old) {
		if (!matches(p, current, old.files))
			return { code: 3, status: "public-state-mismatch", message: "refusing to replace an Antigravity plugin that differs from the npm install receipt" };
		const comparison = compare(candidate.version, old.version);
		if (comparison === 0) return doctor(context);
		if (commandName === "install") return { code: 3, status: "use-update", message: "an npm-owned Antigravity version exists; use update" };
		if (comparison < 0 && !options.allowDowngrade) return { code: 3, status: "downgrade-refused", message: "newer Antigravity assets are installed" };
	}
	if (commandName === "update" && !options.yes)
		return { code: 0, status: "dry-run", message: "Antigravity update preview", plan: ["back up the current install", "agy plugin install from the package", "verify the installed copy byte-for-byte"] };
	const sourceErrors = verifyTree(p.source, candidate.files);
	if (sourceErrors.length) return { code: 3, status: "package-drift", message: "the packaged plugin does not match its release manifest", details: { errors: sourceErrors } };
	if (context.isInterrupted?.()) return { code: 130, status: "interrupted", message: "Antigravity operation interrupted before public mutation", interrupted: true };
	const backupRoot = old ? mkdtempSync(join(p.gemini, ".ccl-skills-backup-")) : null, backup = backupRoot ? join(backupRoot, NAME) : null;
	try {
		if (backup && old) {
			copyRegularTree(p.installed, backup);
			if (verifyTree(backup, old.files).length) throw new Error("the current install changed while it was backed up");
		}
		mkdirSync(p.root, { recursive: true });
		atomicJson(p.journal, { schema: 1, operation: commandName, version: candidate.version });
		try {
			install(p, p.source, candidate.files, context);
			throwIfInterrupted(context);
			atomicJson(p.receipt, candidate);
			unlinkIfPresent(p.journal);
		} catch (error) {
			const interrupted = error instanceof InterruptedOperation;
			try {
				// Compensate only for state this attempt produced, then prove the result.
				const now = state(context);
				if (!now.host) throw new Error(now.hostFailure.message);
				const ours = matches(p, now, candidate.files), gone = now.path === null && destinationAbsent(p);
				if (old && backup) {
					if (ours || gone) install(p, backup, old.files, context);
					else if (!matches(p, now, old.files)) throw new Error("the plugin directory holds content this operation did not install");
				} else if (ours) {
					agy(["plugin", "uninstall", NAME], context);
					const after = state(context);
					if (!after.host || after.path !== null || !destinationAbsent(p)) throw new Error("the plugin is still present after compensation");
				} else if (!gone) throw new Error("the plugin directory holds content this operation did not install");
				unlinkIfPresent(p.journal);
				if (!old) unlinkIfPresent(p.receipt);
				return { code: interrupted ? 130 : 1, status: interrupted && !old ? "interrupted" : "rolled-back", message: String(error), ...(interrupted ? { interrupted: true } : {}) };
			} catch (rollbackError) {
				return { code: interrupted ? 130 : 5, status: "partial", message: `${String(error)}; rollback failed: ${String(rollbackError)}`, details: { journal: p.journal, ...(backup ? { backup } : {}) }, ...(interrupted ? { interrupted: true } : {}) };
			}
		}
	} catch (error) {
		return { code: 1, status: "rolled-back", message: String(error) };
	} finally {
		// The backup is kept only when a partial result names it for manual recovery.
		if (backupRoot && existsSync(p.journal) === false) rmSync(backupRoot, { recursive: true, force: true });
	}
	const after = state(context);
	const note = after.host && !after.enabled ? "; the plugin is disabled in Antigravity, run `agy plugin enable ccl-skills`" : "";
	return { code: 0, status: old ? "updated" : "installed", message: `Antigravity now uses @ccoalm/ccl-skills ${candidate.version}${note}` };
}

function uninstall(options: Options, context: AntigravityContext): Result {
	const p = paths(context);
	assertExclusiveRoot(p);
	const settled = reconcile(p, context, Boolean(options.yes));
	if (settled) return settled;
	const receipt = readReceipt(p), current = state(context);
	if (!current.host) return { ...current.hostFailure, message: `${current.hostFailure.message}; refusing to drop the install receipt while the plugin cannot be verified` };
	if (!receipt && current.path === null && destinationAbsent(p)) return { code: 0, status: "absent", message: "Antigravity npm install is already absent" };
	if (!receipt) return { code: 3, status: "unowned-registration", message: "refusing to remove an Antigravity plugin that npm did not install" };
	if ((current.path !== null || !destinationAbsent(p)) && !matches(p, current, receipt.files))
		return { code: 3, status: "public-state-mismatch", message: "refusing to remove an Antigravity plugin that differs from the npm install receipt" };
	if (!options.yes) return { code: 0, status: "dry-run", message: "Antigravity uninstall preview", plan: ["agy plugin uninstall ccl-skills", "remove the npm install receipt"] };
	if (context.isInterrupted?.()) return { code: 130, status: "interrupted", message: "Antigravity uninstall interrupted before mutation", interrupted: true };
	atomicJson(p.journal, { schema: 1, operation: "uninstall", version: receipt.version });
	if (current.path !== null) agy(["plugin", "uninstall", NAME], context);
	const after = state(context);
	if (!after.host) return { code: 5, status: "partial", message: `${after.hostFailure.message}; uninstall state is unverified, keeping the install receipt` };
	if (after.path !== null || !destinationAbsent(p)) return { code: 5, status: "partial", message: "the Antigravity plugin remains after uninstall" };
	unlinkIfPresent(p.receipt);
	unlinkIfPresent(p.journal);
	try { if (!readdirSync(p.root).length) rmdirSync(p.root); } catch { /* an empty managed directory is harmless */ }
	return { code: 0, status: "uninstalled", message: "Antigravity npm plugin and its install receipt removed" };
}

export function antigravityOwned(home: string | undefined): boolean {
	return Boolean(home) && existsSync(join(resolve(home as string), ".gemini", OWNED, "install-receipt.json"));
}

export function runAntigravity(commandName: string, options: Options = {}, context: AntigravityContext = {}): Result {
	try {
		if (commandName === "doctor") return doctor(context);
		const p = paths(context);
		if (commandName === "install" || commandName === "update") return withLock(p, () => installOrUpdate(commandName, options, context));
		if (commandName === "uninstall") return withLock(p, () => uninstall(options, context));
		return { code: 2, status: "usage", message: "unknown Antigravity command" };
	} catch (error) {
		return { code: 3, status: "safety-refusal", message: error instanceof Error ? error.message : String(error) };
	}
}
