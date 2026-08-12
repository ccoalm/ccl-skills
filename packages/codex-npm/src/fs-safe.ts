import { createHash } from "node:crypto";
import {
	closeSync,
	copyFileSync,
	existsSync,
	fsyncSync,
	lstatSync,
	mkdirSync,
	openSync,
	readFileSync,
	readdirSync,
	realpathSync,
	renameSync,
	rmSync,
	unlinkSync,
	writeFileSync,
} from "node:fs";
import { dirname, join, normalize, relative, resolve, sep } from "node:path";
import type { OwnedFile } from "./types.js";

export const sha256 = (path: string) =>
	createHash("sha256").update(readFileSync(path)).digest("hex");
export interface FsDependencies {
	fsync: (fd: number) => void;
	rename: (from: string, to: string) => void;
	unlink: (path: string) => void;
	fault?: (operation: string) => void;
}
const nativeFs: FsDependencies = {
	fsync: fsyncSync,
	rename: renameSync,
	unlink: unlinkSync,
};
export function fsyncDirectory(
	path: string,
	deps: Partial<FsDependencies> = {},
): void {
	const fs = { ...nativeFs, ...deps };
	const fd = openSync(path, "r");
	try {
		fs.fault?.("parent-dir-fsync");
		fs.fsync(fd);
	} catch (error) {
		const code = (error as NodeJS.ErrnoException).code;
		if (code !== "EINVAL" && code !== "ENOTSUP" && code !== "EISDIR")
			throw error;
	} finally {
		closeSync(fd);
	}
}
export function atomicJson(
	path: string,
	value: unknown,
	deps: Partial<FsDependencies> = {},
): void {
	const fs = { ...nativeFs, ...deps };
	mkdirSync(dirname(path), { recursive: true });
	const tmp = join(
		dirname(path),
		`.${relative(dirname(path), path)}.tmp-${process.pid}-${Date.now()}`,
	);
	const fd = openSync(tmp, "wx", 0o600);
	try {
		writeFileSync(fd, `${JSON.stringify(value, null, 2)}\n`);
		fs.fault?.("temp-file-fsync");
		fs.fsync(fd);
	} finally {
		closeSync(fd);
	}
	fs.fault?.("atomic-json-rename");
	fs.rename(tmp, path);
	fsyncDirectory(dirname(path), deps);
}
export function durableUnlink(
	path: string,
	deps: Partial<FsDependencies> = {},
	operation = "durable-unlink",
): void {
	const fs = { ...nativeFs, ...deps };
	fs.fault?.(operation);
	fs.unlink(path);
	fsyncDirectory(dirname(path), deps);
}
export function durableRename(
	from: string,
	to: string,
	deps: Partial<FsDependencies> = {},
	operation = "durable-rename",
): void {
	const fs = { ...nativeFs, ...deps };
	fs.fault?.(operation);
	fs.rename(from, to);
	fsyncDirectory(dirname(to), deps);
}
export function canonicalAlias(path: string): string {
	const p = resolve(path);
	return p === "/var" || p.startsWith("/var/") ? `/private${p}` : p;
}

function verifyExistingComponents(path: string): void {
	const target = resolve(path);
	const parts: string[] = [];
	let cursor = target;
	while (!existsSync(cursor)) {
		parts.push(cursor);
		const parent = dirname(cursor);
		if (parent === cursor) break;
		cursor = parent;
	}
	const chain: string[] = [];
	for (let current = cursor; ; current = dirname(current)) {
		chain.push(current);
		if (dirname(current) === current) break;
	}
	for (const component of chain.reverse()) {
		const expected = canonicalAlias(component),
			actual = canonicalAlias(realpathSync(component));
		if (lstatSync(component).isSymbolicLink() && actual !== expected)
			throw new Error(`symlinked managed component: ${component}`);
		if (actual !== expected)
			throw new Error(`non-canonical managed component: ${component}`);
	}
	for (const component of parts.reverse())
		if (existsSync(component)) {
			const expected = canonicalAlias(component),
				actual = canonicalAlias(realpathSync(component));
			if (lstatSync(component).isSymbolicLink() && actual !== expected)
				throw new Error(`symlinked managed component: ${component}`);
			if (actual !== expected)
				throw new Error(`non-canonical managed component: ${component}`);
		}
}

export function assertSafeRoot(
	codexHome: string,
	managed: string,
	createHome = false,
): void {
	const home = resolve(codexHome),
		root = resolve(managed);
	if (root !== join(home, "ccl-skills-npm"))
		throw new Error("managed root is not canonical");
	verifyExistingComponents(home);
	if (createHome) {
		mkdirSync(home, { recursive: true });
		verifyExistingComponents(home);
	}
	verifyExistingComponents(root);
}
export function contained(root: string, rel: string): string {
	if (!rel || rel.startsWith("/") || normalize(rel).split(sep).includes(".."))
		throw new Error(`unsafe manifest path: ${rel}`);
	const p = resolve(root, rel);
	if (p !== root && !p.startsWith(`${root}${sep}`))
		throw new Error(`path escape: ${rel}`);
	return p;
}
export function copyRegularTree(src: string, dst: string): OwnedFile[] {
	const files: OwnedFile[] = [];
	function walk(s: string, d: string, base: string) {
		for (const e of readdirSync(s, { withFileTypes: true })) {
			const a = join(s, e.name),
				b = join(d, e.name),
				st = lstatSync(a);
			if (
				st.isSymbolicLink() ||
				(!st.isDirectory() && !st.isFile()) ||
				(st.isFile() && st.nlink !== 1)
			)
				throw new Error(`unsafe asset: ${relative(base, a)}`);
			if (st.isDirectory()) {
				mkdirSync(b, { recursive: true });
				walk(a, b, base);
			} else {
				mkdirSync(dirname(b), { recursive: true });
				copyFileSync(a, b);
				files.push({
					path: relative(dst, b),
					sha256: sha256(b),
					mode: st.mode & 0o777,
				});
			}
		}
	}
	mkdirSync(dst, { recursive: true });
	walk(src, dst, src);
	return files.sort((a, b) => a.path.localeCompare(b.path));
}
export function verifyFiles(root: string, files: OwnedFile[]): string[] {
	const errors: string[] = [];
	for (const f of files) {
		try {
			const p = contained(root, f.path);
			if (!existsSync(p)) {
				errors.push(`${f.path}: missing`);
				continue;
			}
			const st = lstatSync(p);
			if (!st.isFile() || st.isSymbolicLink() || st.nlink !== 1) {
				errors.push(`${f.path}: unsafe type`);
				continue;
			}
			if (sha256(p) !== f.sha256) errors.push(`${f.path}: hash mismatch`);
			if ((st.mode & 0o777) !== f.mode) errors.push(`${f.path}: mode mismatch`);
		} catch (e) {
			errors.push(`${f.path}: ${e instanceof Error ? e.message : String(e)}`);
		}
	}
	return errors;
}
export function verifyTree(root: string, files: OwnedFile[]): string[] {
	const errors = verifyFiles(root, files),
		actual: string[] = [];
	if (!existsSync(root)) return ["snapshot: missing"];
	const walk = (dir: string) => {
		for (const entry of readdirSync(dir, { withFileTypes: true })) {
			const path = join(dir, entry.name),
				stat = lstatSync(path),
				rel = relative(root, path);
			if (
				entry.isSymbolicLink() ||
				(!entry.isDirectory() && !entry.isFile()) ||
				(entry.isFile() && stat.nlink !== 1)
			)
				errors.push(`${rel}: unsafe type`);
			else if (entry.isDirectory()) walk(path);
			else actual.push(rel);
		}
	};
	walk(root);
	const expected = new Set(files.map((f) => f.path));
	for (const path of actual)
		if (!expected.has(path)) errors.push(`${path}: unowned`);
	return errors;
}
export function deleteOwned(root: string, files: OwnedFile[]): string[] {
	const errors = verifyFiles(root, files);
	if (errors.length) return errors;
	for (const f of [...files].sort((a, b) => b.path.length - a.path.length))
		unlinkSync(contained(root, f.path));
	const dirs = new Set(files.map((f) => dirname(contained(root, f.path))));
	for (const d of [...dirs].sort((a, b) => b.length - a.length)) {
		try {
			rmSync(d, { recursive: false });
		} catch {}
	}
	return [];
}
export function deleteVerifiedTree(root: string, files: OwnedFile[]): string[] {
	const errors = verifyTree(root, files);
	if (errors.length) return errors;
	const actual: string[] = [];
	const walk = (dir: string): void => {
		for (const entry of readdirSync(dir, { withFileTypes: true })) {
			const path = join(dir, entry.name);
			const stat = lstatSync(path);
			if (
				entry.isSymbolicLink() ||
				(!entry.isDirectory() && !entry.isFile()) ||
				(entry.isFile() && stat.nlink !== 1)
			) {
				errors.push(`${relative(root, path)}: unsafe type`);
			} else if (entry.isDirectory()) walk(path);
			else actual.push(relative(root, path));
		}
	};
	walk(root);
	const expected = new Set(files.map((file) => file.path));
	for (const path of actual)
		if (!expected.has(path)) errors.push(`${path}: unowned`);
	if (errors.length) return errors;
	return deleteOwned(root, files);
}
export function acquireLock(path: string): () => void {
	mkdirSync(dirname(path), { recursive: true });
	const fd = openSync(path, "wx", 0o600);
	return () => {
		closeSync(fd);
		rmSync(path, { force: true });
	};
}
