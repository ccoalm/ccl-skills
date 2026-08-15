import { spawnSync } from "node:child_process";
import {
	existsSync,
	lstatSync,
	mkdirSync,
	renameSync,
	rmSync,
} from "node:fs";
import { dirname, isAbsolute, join, resolve, sep } from "node:path";
import { fileURLToPath } from "node:url";
import { atomicJson, canonicalAlias, copyRegularTree, verifyTree } from "./fs-safe.js";
import { manifestFor, readManifest, readRelease } from "./manifest.js";
import type { Manifest, Options, Result } from "./types.js";
import { compare } from "./version.js";

const MARKET = "ccl-skills-npm", REF = `ccl-skills@${MARKET}`;

export interface ClaudeContext {
	home?: string;
	assets?: string;
	env?: NodeJS.ProcessEnv;
	isInterrupted?: () => boolean;
	removeRoot?: (path: string) => void;
}

function paths(context: ClaudeContext) {
	const rawHome = context.home ?? (context.env ? context.env.HOME : process.env.HOME);
	if (!rawHome || !isAbsolute(rawHome)) throw new Error("HOME is not set; refusing to guess a managed root");
	const home = resolve(rawHome),
		claudeHome = join(home, ".claude"),
		root = join(claudeHome, MARKET),
		assets = resolve(context.assets || join(dirname(fileURLToPath(import.meta.url)), "assets"));
	return { home, claudeHome, root, manifest: join(root, "install-manifest.json"), assets, release: join(assets, "release.json") };
}

class InterruptedOperation extends Error {}
function throwIfInterrupted(context: ClaudeContext) {
	if (context.isInterrupted?.()) throw new InterruptedOperation("Claude operation interrupted");
}
const samePath = (left: string, right: string) => canonicalAlias(resolve(left)) === canonicalAlias(resolve(right));

function assertExclusiveRoot(base: string, root: string, createBase = false) {
	if (resolve(root) !== join(resolve(base), MARKET)) throw new Error("managed root is not canonical");
	if (createBase) mkdirSync(base, { recursive: true });
	let cursor = resolve(base);
	for (const component of [cursor, root, join(root, "snapshots")]) {
		if (!existsSync(component)) continue;
		const stat = lstatSync(component);
		if (!stat.isDirectory() || stat.isSymbolicLink()) throw new Error(`unsafe managed component: ${component}`);
	}
}

function command(args: string[], context: ClaudeContext, allowFailure = false) {
	const result = spawnSync("claude", args, {
		encoding: "utf8",
		env: context.env || process.env,
	});
	if (result.error && !allowFailure) throw result.error;
	if (result.status !== 0 && !allowFailure)
		throw new Error(`claude ${args.slice(0, 3).join(" ")} failed (${result.status}): ${(result.stderr || result.stdout).trim()}`);
	return result;
}

type ClaudeState = { host: boolean; marketplace: string | null; plugin: boolean; legacy: boolean };
function state(context: ClaudeContext): ClaudeState {
	const version = command(["--version"], context, true);
	if (version.status !== 0) return { host: false, marketplace: null, plugin: false, legacy: false };
	const marketsRaw = command(["plugin", "marketplace", "list", "--json"], context),
		pluginsRaw = command(["plugin", "list", "--json"], context);
	let markets: unknown, plugins: unknown;
	try {
		markets = JSON.parse(marketsRaw.stdout);
		plugins = JSON.parse(pluginsRaw.stdout);
	} catch {
		throw new Error("Claude plugin state is not valid JSON");
	}
	if (!Array.isArray(markets) || !Array.isArray(plugins)) throw new Error("Claude plugin state has an invalid shape");
	const targetMarkets = markets.filter((entry) => entry && typeof entry === "object" && (entry as { name?: unknown }).name === MARKET);
	if (targetMarkets.length > 1) throw new Error("duplicate Claude npm marketplace");
	const marketplace = targetMarkets.length
		? String((targetMarkets[0] as { installLocation?: unknown; path?: unknown }).installLocation || (targetMarkets[0] as { path?: unknown }).path || "")
		: null;
	const ids = plugins.map((entry) => entry && typeof entry === "object" ? (entry as { id?: unknown }).id : null);
	return {
		host: true,
		marketplace,
		plugin: ids.includes(REF),
		legacy: ids.includes("ccl-skills@ccl-skills") || markets.some((entry) => entry && typeof entry === "object" && (entry as { name?: unknown }).name === "ccl-skills"),
	};
}

function prepare(context: ClaudeContext, old: Manifest | null) {
	const p = paths(context), release = readRelease(p.release), rel = join("snapshots", release.snapshotHash), snapshot = join(p.root, rel), snapshots = join(p.root, "snapshots");
	assertExclusiveRoot(p.claudeHome, p.root, true);
	mkdirSync(snapshots, { recursive: true });
	assertExclusiveRoot(p.claudeHome, p.root);
	if (!existsSync(snapshot)) {
		const staging = join(snapshots, `.staging-${release.snapshotHash}-${process.pid}`);
		rmSync(staging, { recursive: true, force: true });
		copyRegularTree(join(p.assets, "marketplace"), join(staging, "marketplace"));
		const errors = verifyTree(staging, release.files);
		if (errors.length) {
			rmSync(staging, { recursive: true, force: true });
			throw new Error(`staged Claude snapshot failed verification: ${errors.join("; ")}`);
		}
		mkdirSync(dirname(snapshot), { recursive: true });
		renameSync(staging, snapshot);
	} else {
		const errors = verifyTree(snapshot, release.files);
		if (errors.length) throw new Error(`Claude snapshot drifted: ${errors.join("; ")}`);
	}
	return { p, release, rel, snapshot, manifest: manifestFor(release, rel, old?.active || null) };
}

function removeRegistration(context: ClaudeContext) {
	const current = state(context);
	if (current.plugin) command(["plugin", "uninstall", REF, "--scope", "user"], context);
	if (current.marketplace) command(["plugin", "marketplace", "remove", MARKET, "--scope", "user"], context);
}

function installRegistration(marketplace: string, context: ClaudeContext) {
	command(["plugin", "marketplace", "add", marketplace, "--scope", "user"], context);
	command(["plugin", "install", REF, "--scope", "user"], context);
	const current = state(context);
	if (!current.plugin || !samePath(current.marketplace || "", marketplace))
		throw new Error("Claude did not expose the exact npm marketplace candidate");
}

function doctor(context: ClaudeContext): Result {
	const p = paths(context);
	assertExclusiveRoot(p.claudeHome, p.root);
	const current = state(context);
	if (!current.host) return { code: 4, status: "host-missing", message: "Claude CLI is not installed" };
	if (current.legacy) return { code: 3, status: "double-install", message: "Git marketplace and npm marketplace are both present; keep exactly one" };
	const manifest = readManifest(p.manifest);
	if (!manifest) {
		if (current.plugin || current.marketplace) return { code: 3, status: "unowned-registration", message: "Claude npm registration exists without an owned manifest" };
		return { code: 3, status: "absent", message: "ccl-skills is not installed for Claude" };
	}
	const snapshot = join(p.root, manifest.active.path), errors = verifyTree(snapshot, manifest.active.ownedFiles), expected = join(snapshot, "marketplace");
	if (errors.length) return { code: 3, status: "owned-drift", message: "Claude owned snapshot drifted", details: { errors } };
	if (!current.plugin || !samePath(current.marketplace || "", expected))
		return { code: 3, status: "public-state-mismatch", message: "Claude public state does not match the owned manifest" };
	return { code: 0, status: "healthy", message: `Claude uses @ccoalm/ccl-skills ${manifest.active.version}` };
}

function installOrUpdate(commandName: "install" | "update", options: Options, context: ClaudeContext): Result {
	const p = paths(context);
	assertExclusiveRoot(p.claudeHome, p.root, true);
	const current = state(context);
	if (!current.host) return { code: 4, status: "host-missing", message: "Claude CLI is not installed" };
	if (current.legacy) return { code: 3, status: "double-install", message: "Remove the Git marketplace install or choose it instead of npm" };
	const old = readManifest(p.manifest), release = readRelease(p.release);
	if (!old && (current.plugin || current.marketplace))
		return { code: 3, status: "unowned-registration", message: "refusing to replace a Claude npm registration without an owned manifest" };
	if (commandName === "update" && !old) return { code: 3, status: "not-installed", message: "update requires an existing owned Claude installation" };
	if (old) {
		const snapshot = join(p.root, old.active.path), errors = verifyTree(snapshot, old.active.ownedFiles), expectedMarket = join(snapshot, "marketplace");
		if (errors.length) return { code: 3, status: "owned-drift", message: "Claude owned snapshot drifted", details: { errors } };
		if (!current.plugin || !samePath(current.marketplace || "", expectedMarket))
			return { code: 3, status: "public-state-mismatch", message: "refusing to replace Claude state that does not match the owned manifest" };
		const comparison = compare(release.version, old.active.version);
		if (comparison === 0) return doctor(context);
		if (commandName === "install") return { code: 3, status: "use-update", message: "an owned Claude version exists; use update" };
		if (comparison < 0 && !options.allowDowngrade) return { code: 3, status: "downgrade-refused", message: "newer Claude assets are installed" };
	}
	if (commandName === "update" && !options.yes)
		return { code: 0, status: "dry-run", message: "Claude update preview", plan: ["stage immutable marketplace", "replace user registration", "verify exact local source"] };
	const candidate = prepare(context, old), candidateMarket = join(candidate.snapshot, "marketplace"), oldMarket = old ? join(p.root, old.active.path, "marketplace") : null;
	if (context.isInterrupted?.()) return { code: 130, status: "interrupted", message: "Claude operation interrupted before public mutation", interrupted: true };
	try {
		if (current.plugin || current.marketplace) removeRegistration(context);
		throwIfInterrupted(context);
		installRegistration(candidateMarket, context);
		throwIfInterrupted(context);
		atomicJson(p.manifest, candidate.manifest);
		if (old?.previous) {
			try { rmSync(join(p.root, old.previous.path), { recursive: true, force: true }); }
			catch (error) { return { code: 5, status: "updated-stale-cleanup", message: `Claude update committed but superseded snapshot cleanup failed: ${String(error)}` }; }
		}
		return { code: 0, status: old ? "updated" : "installed", message: `Claude now uses @ccoalm/ccl-skills ${candidate.release.version}` };
	} catch (error) {
		const interrupted = error instanceof InterruptedOperation;
		try {
			removeRegistration(context);
			if (oldMarket) installRegistration(oldMarket, context);
			return { code: interrupted ? 130 : 1, status: interrupted && !oldMarket ? "interrupted" : "rolled-back", message: String(error), ...(interrupted ? { interrupted: true } : {}) };
		} catch (rollbackError) {
			return { code: interrupted ? 130 : 5, status: "partial", message: `${String(error)}; rollback failed: ${String(rollbackError)}`, ...(interrupted ? { interrupted: true } : {}) };
		}
	}
}

function uninstall(options: Options, context: ClaudeContext): Result {
	const p = paths(context);
	assertExclusiveRoot(p.claudeHome, p.root);
	const manifest = readManifest(p.manifest), current = state(context);
	if (!manifest && !current.plugin && !current.marketplace) return { code: 0, status: "absent", message: "Claude npm install is already absent" };
	if (!manifest) return { code: 3, status: "unowned-registration", message: "refusing to remove an unowned Claude registration" };
	if (!current.host) return { code: 4, status: "host-missing", message: "Claude CLI is not installed; refusing to drop ownership evidence while registration cannot be verified" };
	if (!options.yes) return { code: 0, status: "dry-run", message: "Claude uninstall preview", plan: ["remove npm plugin", "remove npm marketplace", "delete exclusive owned snapshots"] };
	if (context.isInterrupted?.()) return { code: 130, status: "interrupted", message: "Claude uninstall interrupted before registration mutation", interrupted: true };
	removeRegistration(context);
	const after = state(context);
	if (after.plugin || after.marketplace) return { code: 5, status: "partial", message: "Claude registration remains after uninstall" };
	try {
		if (context.removeRoot) context.removeRoot(p.root);
		else rmSync(p.root, { recursive: true, force: true });
	} catch (error) {
		return { code: 5, status: "partial", message: `Claude registration removed but owned snapshot cleanup failed: ${String(error)}` };
	}
	return { code: 0, status: "uninstalled", message: "Claude npm registration and exclusive snapshots removed" };
}

export function runClaude(commandName: string, options: Options = {}, context: ClaudeContext = {}): Result {
	try {
		if (commandName === "doctor") return doctor(context);
		if (commandName === "install" || commandName === "update") return installOrUpdate(commandName, options, context);
		if (commandName === "uninstall") return uninstall(options, context);
		return { code: 2, status: "usage", message: "unknown Claude command" };
	} catch (error) {
		return { code: 3, status: "safety-refusal", message: error instanceof Error ? error.message : String(error) };
	}
}
