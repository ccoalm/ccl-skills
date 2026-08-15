import { createHash } from "node:crypto";
import { spawnSync } from "node:child_process";
import {
	chmodSync,
	copyFileSync,
	existsSync,
	lstatSync,
	mkdirSync,
	readFileSync,
	readdirSync,
	renameSync,
	rmdirSync,
	rmSync,
	writeFileSync,
} from "node:fs";
import { dirname, isAbsolute, join, normalize, relative, resolve, sep } from "node:path";
import { fileURLToPath } from "node:url";
import { atomicJson, sha256 } from "./fs-safe.js";
import { readRelease } from "./manifest.js";
import type { Options, Result } from "./types.js";
import { compare } from "./version.js";

const PACKAGE = "@ccoalm/ccl-skills";
type Entry = { source: string; destination: string; sha256: string; mode: number };
type OpenManifest = {
	schema: 1;
	npmPackage: typeof PACKAGE;
	installedAt: string;
	version: string;
	sourceCommit: string;
	sourceKind: "bundled" | "override";
	snapshot: string;
	snapshotHash: string;
	entries: Entry[];
};

export interface OpenCodeContext {
	home?: string;
	assets?: string;
	env?: NodeJS.ProcessEnv;
	isInterrupted?: () => boolean;
	removeRoot?: (path: string) => void;
	copyShared?: (from: string, to: string) => void;
}

function paths(context: OpenCodeContext) {
	const rawHome = context.home ?? (context.env ? context.env.HOME : process.env.HOME);
	if (!rawHome || !isAbsolute(rawHome)) throw new Error("HOME is not set; refusing to guess a managed root");
	const home = resolve(rawHome),
		base = join(home, ".config", "opencode"),
		root = join(base, "ccl-skills-npm"),
		assets = resolve(context.assets || join(dirname(fileURLToPath(import.meta.url)), "assets"));
	return { home, base, root, manifest: join(root, "install-manifest.json"), assets };
}

class InterruptedOperation extends Error {}

function assertExclusiveRoot(base: string, root: string, createBase = false) {
	if (resolve(root) !== join(resolve(base), "ccl-skills-npm")) throw new Error("managed root is not canonical");
	if (createBase) mkdirSync(base, { recursive: true });
	for (const component of [base, root]) {
		if (!existsSync(component)) continue;
		const stat = lstatSync(component);
		if (!stat.isDirectory() || stat.isSymbolicLink()) throw new Error(`unsafe managed component: ${component}`);
	}
}

function safeRel(value: unknown, label: string) {
	if (typeof value !== "string" || !value || value.startsWith("/") || normalize(value).split(sep).includes("..") || value.includes("\\"))
		throw new Error(`unsafe ${label}`);
	return value;
}

function regular(path: string) {
	const stat = lstatSync(path);
	if (!stat.isFile() || stat.isSymbolicLink() || stat.nlink !== 1) throw new Error(`unsafe source file: ${path}`);
	return stat;
}

function walk(root: string, prefix: string, destinationPrefix: string): Entry[] {
	const output: Entry[] = [];
	function visit(directory: string) {
		for (const entry of readdirSync(directory, { withFileTypes: true })) {
			const path = join(directory, entry.name), stat = lstatSync(path);
			if (entry.isSymbolicLink() || (!entry.isDirectory() && !entry.isFile()) || (entry.isFile() && stat.nlink !== 1))
				throw new Error(`unsafe source entry: ${relative(root, path)}`);
			if (entry.isDirectory()) visit(path);
			else {
				const rel = relative(root, path);
				output.push({ source: join(prefix, rel), destination: join(destinationPrefix, rel), sha256: sha256(path), mode: stat.mode & 0o777 });
			}
		}
	}
	visit(root);
	return output;
}

function source(context: OpenCodeContext) {
	const p = paths(context), override = (context.env ?? process.env).CCL_SKILLS_REPO;
	const root = resolve(override || join(p.assets, "marketplace", "plugins", "ccl-skills"));
	if (override && (!existsSync(root) || lstatSync(root).isSymbolicLink() || !lstatSync(root).isDirectory()))
		throw new Error("invalid CCL_SKILLS_REPO: expected a real checkout directory");
	const skills = join(root, "skills"), plugin = join(root, "packages/opencode-plugin/ccl-skills.ts"), bootstrap = join(root, "agent-context/session-start.md"), commands = join(root, "packages/opencode-plugin/commands");
	if (!existsSync(skills) || !lstatSync(skills).isDirectory() || !existsSync(commands) || !lstatSync(commands).isDirectory())
		throw new Error("invalid CCL_SKILLS_REPO: skills or OpenCode commands are missing");
	regular(plugin); regular(bootstrap);
	const skillNames = readdirSync(skills, { withFileTypes: true }).filter((entry) => entry.isDirectory() && existsSync(join(skills, entry.name, "SKILL.md"))).map((entry) => entry.name).sort();
	if (!skillNames.length) throw new Error("invalid CCL_SKILLS_REPO: no skills found");
	let entries = walk(skills, "skills", "skills");
	entries.push({ source: "packages/opencode-plugin/ccl-skills.ts", destination: "plugins/ccl-skills.ts", sha256: sha256(plugin), mode: regular(plugin).mode & 0o777 });
	entries.push({ source: "agent-context/session-start.md", destination: "ccl-skills/bootstrap.md", sha256: sha256(bootstrap), mode: regular(bootstrap).mode & 0o777 });
	entries.push(...walk(commands, "packages/opencode-plugin/commands", "commands").filter((entry) => /^commands\/ccl-[^/]+\.md$/.test(entry.destination)));
	entries = entries.sort((a, b) => a.destination.localeCompare(b.destination));
	const snapshotHash = createHash("sha256").update(JSON.stringify(entries.map(({ source: s, sha256: hash, mode }) => ({ source: s, sha256: hash, mode })))).digest("hex");
	const release = readRelease(join(p.assets, "release.json"));
	let sourceCommit = release.sourceCommit;
	if (override) {
		const git = spawnSync("git", ["-C", root, "rev-parse", "HEAD"], { encoding: "utf8", env: context.env || process.env });
		sourceCommit = git.status === 0 && /^[0-9a-f]{40}\n?$/.test(git.stdout) ? git.stdout.trim() : "0".repeat(40);
	}
	return { root, entries, snapshotHash, version: release.version, sourceCommit, sourceKind: override ? "override" as const : "bundled" as const };
}

function allowedDestination(path: string) {
	return /^skills\/[^/]+\/.+/.test(path) || path === "plugins/ccl-skills.ts" || path === "ccl-skills/bootstrap.md" || /^commands\/ccl-[^/]+\.md$/.test(path);
}

function readManifest(path: string, root: string): OpenManifest | null {
	if (!existsSync(path)) return null;
	let value: unknown;
	try { value = JSON.parse(readFileSync(path, "utf8")); } catch { throw new Error("invalid OpenCode manifest JSON"); }
	if (!value || typeof value !== "object" || Array.isArray(value)) throw new Error("invalid OpenCode manifest");
	const raw = value as Partial<OpenManifest>;
	if (raw.schema !== 1 || raw.npmPackage !== PACKAGE || typeof raw.installedAt !== "string" || !Number.isFinite(Date.parse(raw.installedAt)) || typeof raw.version !== "string" || !/^\d+\.\d+\.\d+$/.test(raw.version) || typeof raw.sourceCommit !== "string" || !/^[0-9a-f]{40}$/.test(raw.sourceCommit) || !["bundled", "override"].includes(raw.sourceKind || "") || typeof raw.snapshotHash !== "string" || !/^[0-9a-f]{64}$/.test(raw.snapshotHash) || !Array.isArray(raw.entries))
		throw new Error("invalid OpenCode manifest identity");
	const snapshot = safeRel(raw.snapshot, "OpenCode snapshot"), expectedSnapshot = join("snapshots", raw.snapshotHash, "source");
	if (snapshot !== expectedSnapshot) throw new Error("invalid OpenCode snapshot pointer");
	const seen = new Set<string>(), entries = raw.entries.map((item) => {
		if (!item || typeof item !== "object") throw new Error("invalid OpenCode manifest entry");
		const entry = item as Entry, sourcePath = safeRel(entry.source, "OpenCode source"), destination = safeRel(entry.destination, "OpenCode destination");
		if (!allowedDestination(destination) || seen.has(destination) || typeof entry.sha256 !== "string" || !/^[0-9a-f]{64}$/.test(entry.sha256) || ![0o644, 0o755].includes(entry.mode))
			throw new Error("invalid OpenCode manifest entry");
		seen.add(destination);
		const file = join(root, snapshot, sourcePath); regular(file);
		if (sha256(file) !== entry.sha256) throw new Error("OpenCode snapshot does not authorize manifest entry");
		return { source: sourcePath, destination, sha256: entry.sha256, mode: entry.mode };
	}).sort((a, b) => a.destination.localeCompare(b.destination));
	return { schema: 1, npmPackage: PACKAGE, installedAt: raw.installedAt, version: raw.version, sourceCommit: raw.sourceCommit, sourceKind: raw.sourceKind as OpenManifest["sourceKind"], snapshot, snapshotHash: raw.snapshotHash, entries };
}

function hostAvailable(context: OpenCodeContext) {
	const result = spawnSync("opencode", ["--version"], { encoding: "utf8", env: context.env || process.env });
	return !result.error && result.status === 0;
}

function sharedPath(base: string, rel: string) {
	const path = resolve(base, safeRel(rel, "OpenCode destination"));
	if (!path.startsWith(`${resolve(base)}${sep}`)) throw new Error("OpenCode destination escaped its allowlist root");
	return path;
}

function assertSafeSharedParents(base: string, entries: Entry[]) {
	for (const entry of entries) {
		let cursor = resolve(base);
		for (const component of dirname(safeRel(entry.destination, "OpenCode destination")).split(sep)) {
			if (!component || component === ".") continue;
			cursor = join(cursor, component);
			if (!existsSync(cursor)) continue;
			const stat = lstatSync(cursor);
			if (stat.isSymbolicLink() || !stat.isDirectory()) throw new Error(`unsafe shared OpenCode component: ${cursor}`);
		}
	}
}

function missingDirectories(base: string, parent: string) {
	const missing: string[] = [], root = resolve(base);
	for (let cursor = resolve(parent); cursor !== root && cursor.startsWith(`${root}${sep}`); cursor = dirname(cursor)) {
		if (existsSync(cursor)) break;
		missing.push(cursor);
	}
	return missing;
}

function removeEmptyDirectories(directories: Iterable<string>) {
	for (const directory of [...new Set(directories)].sort((a, b) => b.length - a.length)) {
		try { rmdirSync(directory); }
		catch (error) {
			if (!["ENOENT", "ENOTEMPTY", "EEXIST"].includes((error as NodeJS.ErrnoException).code || "")) throw error;
		}
	}
}

function actualFiles(directory: string): string[] {
	if (!existsSync(directory)) return [];
	const output: string[] = [];
	function visit(path: string) {
		for (const entry of readdirSync(path, { withFileTypes: true })) {
			const full = join(path, entry.name), stat = lstatSync(full);
			if (entry.isSymbolicLink() || (!entry.isDirectory() && !entry.isFile()) || (entry.isFile() && stat.nlink !== 1)) throw new Error(`unsafe shared OpenCode entry: ${full}`);
			if (entry.isDirectory()) visit(full); else output.push(relative(directory, full));
		}
	}
	visit(directory);
	return output.sort();
}

function preflight(base: string, next: Entry[], old: OpenManifest | null) {
	assertSafeSharedParents(base, next);
	const previous = new Map((old?.entries || []).map((entry) => [entry.destination, entry]));
	if (old) {
		for (const entry of old.entries) {
			const path = sharedPath(base, entry.destination);
			if (!existsSync(path) || (regular(path).mode & 0o777) !== entry.mode || sha256(path) !== entry.sha256)
				throw new Error(`owned OpenCode file drifted: ${entry.destination}`);
		}
		const skillNames = new Set(old.entries.filter((entry) => entry.destination.startsWith("skills/")).map((entry) => entry.destination.split("/")[1]));
		for (const skill of skillNames) {
			const expected = old.entries.filter((entry) => entry.destination.startsWith(`skills/${skill}/`)).map((entry) => entry.destination.slice(`skills/${skill}/`.length)).sort();
			if (JSON.stringify(actualFiles(join(base, "skills", skill))) !== JSON.stringify(expected)) throw new Error(`owned OpenCode skill directory drifted: ${skill}`);
		}
	}
	const nextSkills = new Set(next.filter((entry) => entry.destination.startsWith("skills/")).map((entry) => entry.destination.split("/")[1]));
	if (!old) for (const skill of nextSkills) if (existsSync(join(base, "skills", skill))) throw new Error(`OpenCode skill collision: ${skill}`);
	for (const entry of next) if (!previous.has(entry.destination) && existsSync(sharedPath(base, entry.destination))) throw new Error(`OpenCode path collision: ${entry.destination}`);
}

function prepareSnapshot(p: ReturnType<typeof paths>, candidate: ReturnType<typeof source>) {
	const snapshotRel = join("snapshots", candidate.snapshotHash, "source"), snapshot = join(p.root, snapshotRel);
	if (!existsSync(snapshot)) {
		const staging = join(p.root, "snapshots", `.staging-${candidate.snapshotHash}-${process.pid}`, "source");
		rmSync(dirname(staging), { recursive: true, force: true });
		for (const entry of candidate.entries) {
			const from = join(candidate.root, entry.source), to = join(staging, entry.source);
			regular(from); mkdirSync(dirname(to), { recursive: true }); copyFileSync(from, to); chmodSync(to, entry.mode);
		}
		mkdirSync(dirname(snapshot), { recursive: true });
		renameSync(dirname(staging), dirname(snapshot));
	}
	for (const entry of candidate.entries) {
		const file = join(snapshot, entry.source); regular(file);
		if (sha256(file) !== entry.sha256) throw new Error(`OpenCode snapshot drifted: ${entry.source}`);
	}
	return { snapshotRel, snapshot };
}

function writeShared(p: ReturnType<typeof paths>, snapshot: string, entries: Entry[], old: OpenManifest | null, isInterrupted?: () => boolean, copyShared: (from: string, to: string) => void = (from, to) => copyFileSync(from, to)) {
	const backup = join(p.root, `.rollback-${process.pid}`), staging = join(p.root, ".shared-staging"), written: Entry[] = [], removed: Entry[] = [], createdDirectories = new Set<string>();
	rmSync(backup, { recursive: true, force: true });
	rmSync(staging, { recursive: true, force: true });
	mkdirSync(staging, { recursive: true });
	try {
		for (const entry of old?.entries || []) {
			const from = sharedPath(p.base, entry.destination), to = join(backup, entry.destination);
			mkdirSync(dirname(to), { recursive: true }); copyFileSync(from, to); chmodSync(to, entry.mode);
		}
		for (const entry of entries) {
			if (isInterrupted?.()) throw new InterruptedOperation("OpenCode operation interrupted");
			const from = join(snapshot, entry.source), to = sharedPath(p.base, entry.destination), temp = join(staging, createHash("sha256").update(entry.destination).digest("hex"));
			for (const directory of missingDirectories(p.base, dirname(to))) createdDirectories.add(directory);
			mkdirSync(dirname(to), { recursive: true }); copyShared(from, temp); chmodSync(temp, entry.mode); renameSync(temp, to); written.push(entry);
		}
		const next = new Set(entries.map((entry) => entry.destination));
		for (const entry of old?.entries || []) {
			if (next.has(entry.destination)) continue;
			if (isInterrupted?.()) throw new InterruptedOperation("OpenCode operation interrupted");
			rmSync(sharedPath(p.base, entry.destination));
			removed.push(entry);
		}
		if (isInterrupted?.()) throw new InterruptedOperation("OpenCode operation interrupted");
	} catch (error) {
		for (const entry of written.reverse()) {
			const to = sharedPath(p.base, entry.destination), saved = join(backup, entry.destination);
			if (existsSync(saved)) { copyFileSync(saved, to); chmodSync(to, lstatSync(saved).mode & 0o777); }
			else rmSync(to, { force: true });
		}
		for (const entry of removed) {
			const saved = join(backup, entry.destination), to = sharedPath(p.base, entry.destination);
			mkdirSync(dirname(to), { recursive: true }); copyFileSync(saved, to); chmodSync(to, entry.mode);
		}
		removeEmptyDirectories(createdDirectories);
		throw error;
	} finally { rmSync(backup, { recursive: true, force: true }); rmSync(staging, { recursive: true, force: true }); }
	const emptyOwnedDirectories: string[] = [];
	for (const entry of removed) {
		const category = join(p.base, entry.destination.split(sep)[0]);
		for (let cursor = dirname(sharedPath(p.base, entry.destination)); cursor !== category && cursor.startsWith(`${category}${sep}`); cursor = dirname(cursor)) emptyOwnedDirectories.push(cursor);
	}
	removeEmptyDirectories(emptyOwnedDirectories);
}

function doctor(context: OpenCodeContext): Result {
	const p = paths(context);
	assertExclusiveRoot(p.base, p.root);
	if (!hostAvailable(context)) return { code: 4, status: "host-missing", message: "OpenCode CLI is not installed" };
	const legacy = existsSync(join(p.base, "ccl-skills/install-manifest.json")), manifest = readManifest(p.manifest, p.root);
	if (legacy && manifest) return { code: 3, status: "double-install", message: "legacy checkout and npm OpenCode installs are both present; keep exactly one" };
	if (!manifest) {
		if (existsSync(join(p.base, "plugins/ccl-skills.ts")) || existsSync(join(p.base, "ccl-skills/bootstrap.md"))) return { code: 3, status: legacy ? "legacy-install" : "unowned-registration", message: "OpenCode ccl-skills files exist without an npm ownership receipt" };
		return { code: 3, status: "absent", message: "ccl-skills is not installed for OpenCode" };
	}
	const drift: string[] = [];
	for (const entry of manifest.entries) {
		const path = sharedPath(p.base, entry.destination);
		if (!existsSync(path) || sha256(path) !== entry.sha256) drift.push(entry.destination);
	}
	if (drift.length) return { code: 3, status: "shared-drift", message: "OpenCode shared files changed after npm install; they will never be auto-deleted", details: { drift } };
	return { code: 0, status: "healthy", message: `OpenCode uses @ccoalm/ccl-skills ${manifest.version}` };
}

function installOrUpdate(commandName: "install" | "update", options: Options, context: OpenCodeContext): Result {
	const p = paths(context);
	if (!hostAvailable(context)) return { code: 4, status: "host-missing", message: "OpenCode CLI is not installed" };
	let candidate: ReturnType<typeof source>;
	try { candidate = source(context); } catch (error) { return { code: 3, status: (context.env ?? process.env).CCL_SKILLS_REPO ? "invalid-source-override" : "safety-refusal", message: String(error) }; }
	assertExclusiveRoot(p.base, p.root);
	const old = readManifest(p.manifest, p.root);
	if (commandName === "update" && !old) return { code: 3, status: "not-installed", message: "update requires an existing owned OpenCode installation" };
	if (old) {
		const comparison = compare(candidate.version, old.version);
		if (comparison === 0 && candidate.snapshotHash === old.snapshotHash) return doctor(context);
		if (commandName === "install") return { code: 3, status: "use-update", message: "an owned OpenCode version exists; use update" };
		if (comparison < 0 && !options.allowDowngrade) return { code: 3, status: "downgrade-refused", message: "newer OpenCode assets are installed" };
	}
	try { preflight(p.base, candidate.entries, old); } catch (error) { return { code: 3, status: "collision", message: String(error) }; }
	if (commandName === "update" && !options.yes) return { code: 0, status: "dry-run", message: "OpenCode update preview", plan: ["validate source", "verify shared paths", "refresh unchanged npm-managed files", "preserve all shared files on uninstall"] };
	assertExclusiveRoot(p.base, p.root, true);
	try {
		const snapshot = prepareSnapshot(p, candidate);
		writeShared(p, snapshot.snapshot, candidate.entries, old, context.isInterrupted, context.copyShared);
		const manifest: OpenManifest = { schema: 1, npmPackage: PACKAGE, installedAt: new Date().toISOString(), version: candidate.version, sourceCommit: candidate.sourceCommit, sourceKind: candidate.sourceKind, snapshot: snapshot.snapshotRel, snapshotHash: candidate.snapshotHash, entries: candidate.entries };
		atomicJson(p.manifest, manifest);
		if (old && old.snapshotHash !== candidate.snapshotHash) {
			try { rmSync(join(p.root, dirname(old.snapshot)), { recursive: true, force: true }); }
			catch (error) { return { code: 5, status: "updated-stale-cleanup", message: `OpenCode update committed but superseded snapshot cleanup failed: ${String(error)}` }; }
		}
		return { code: 0, status: old ? "updated" : "installed", message: `OpenCode installed ${candidate.entries.filter((entry) => /\/SKILL\.md$/.test(entry.destination)).length} bundled skills from ${candidate.sourceKind}` };
	} catch (error) {
		if (error instanceof InterruptedOperation) return { code: 130, status: "interrupted", message: error.message, interrupted: true };
		return { code: 5, status: "partial", message: String(error) };
	}
}

function uninstall(options: Options, context: OpenCodeContext): Result {
	const p = paths(context);
	assertExclusiveRoot(p.base, p.root);
	const manifest = readManifest(p.manifest, p.root);
	if (!manifest) return { code: 0, status: "absent", message: "OpenCode npm install is already absent" };
	if (!options.yes) return { code: 0, status: "dry-run", message: "OpenCode uninstall preview", plan: [`retain ${manifest.entries.length} shared files`, "remove only the exclusive npm receipt and snapshots"] };
	if (context.isInterrupted?.()) return { code: 130, status: "interrupted", message: "OpenCode uninstall interrupted before metadata removal", interrupted: true };
	try {
		if (context.removeRoot) context.removeRoot(p.root);
		else rmSync(p.root, { recursive: true, force: true });
	} catch (error) {
		return { code: 5, status: "partial", message: `OpenCode shared files retained but exclusive metadata cleanup failed: ${String(error)}` };
	}
	return { code: 0, status: "uninstalled-shared-retained", message: `removed exclusive npm metadata; retained ${manifest.entries.length} shared OpenCode files for manual cleanup`, details: { retained: manifest.entries.map((entry) => entry.destination) } };
}

export function runOpenCode(commandName: string, options: Options = {}, context: OpenCodeContext = {}): Result {
	try {
		if (commandName === "doctor") return doctor(context);
		if (commandName === "install" || commandName === "update") return installOrUpdate(commandName, options, context);
		if (commandName === "uninstall") return uninstall(options, context);
		return { code: 2, status: "usage", message: "unknown OpenCode command" };
	} catch (error) {
		return { code: 3, status: "safety-refusal", message: error instanceof Error ? error.message : String(error) };
	}
}
