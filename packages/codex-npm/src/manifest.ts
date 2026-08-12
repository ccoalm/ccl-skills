import { createHash } from "node:crypto";
import { existsSync, readFileSync } from "node:fs";
import { isAbsolute, normalize, sep } from "node:path";
import type {
	Manifest,
	OwnedFile,
	Release,
	SnapshotMetadata,
} from "./types.js";

export class MetadataError extends Error {}
const HEX40 = /^[0-9a-f]{40}$/,
	HEX64 = /^[0-9a-f]{64}$/,
	SEMVER = /^(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)$/;
function object(value: unknown, label: string): Record<string, unknown> {
	if (!value || typeof value !== "object" || Array.isArray(value))
		throw new MetadataError(`invalid ${label}`);
	return value as Record<string, unknown>;
}
function safeRel(value: unknown, label: string): string {
	if (
		typeof value !== "string" ||
		!value ||
		isAbsolute(value) ||
		normalize(value).split(sep).includes("..") ||
		value.includes("\\")
	)
		throw new MetadataError(`unsafe ${label}`);
	return value;
}
function files(value: unknown): OwnedFile[] {
	if (!Array.isArray(value) || !value.length)
		throw new MetadataError("invalid owned files");
	const seen = new Set<string>();
	return value
		.map((raw) => {
			const f = object(raw, "owned file"),
				path = safeRel(f.path, "owned path");
			if (seen.has(path))
				throw new MetadataError(`duplicate owned path: ${path}`);
			seen.add(path);
			if (typeof f.sha256 !== "string" || !HEX64.test(f.sha256))
				throw new MetadataError(`invalid hash: ${path}`);
			if (
				!Number.isInteger(f.mode) ||
				![0o600, 0o644, 0o700, 0o755].includes(f.mode as number)
			)
				throw new MetadataError(`invalid mode: ${path}`);
			return { path, sha256: f.sha256, mode: f.mode as number };
		})
		.sort((a, b) => a.path.localeCompare(b.path));
}
function parse(path: string, label: string): Record<string, unknown> {
	try {
		return object(JSON.parse(readFileSync(path, "utf8")), label);
	} catch (error) {
		if (error instanceof MetadataError) throw error;
		throw new MetadataError(`invalid ${label} JSON`);
	}
}
export function snapshotIdentity(
	version: string,
	ownedFiles: OwnedFile[],
): string {
	return createHash("sha256")
		.update(JSON.stringify({ version, files: ownedFiles }))
		.digest("hex");
}
export function readRelease(path: string): Release {
	const r = parse(path, "release");
	const owned = files(r.files);
	if (
		r.schema !== 1 ||
		r.npmPackage !== "@ccoalm/ccl-skills-codex" ||
		typeof r.version !== "string" ||
		!SEMVER.test(r.version) ||
		typeof r.sourceCommit !== "string" ||
		!HEX40.test(r.sourceCommit) ||
		!["clean", "development-dirty"].includes(r.sourceState as string) ||
		typeof r.snapshotHash !== "string" ||
		!HEX64.test(r.snapshotHash) ||
		snapshotIdentity(r.version, owned) !== r.snapshotHash
	)
		throw new MetadataError("invalid release identity");
	return {
		schema: 1,
		npmPackage: r.npmPackage,
		version: r.version,
		sourceCommit: r.sourceCommit,
		sourceState: r.sourceState as Release["sourceState"],
		files: owned,
		snapshotHash: r.snapshotHash,
	};
}
function snapshotRel(value: unknown, label: string): string | null {
	if (value === null) return null;
	const rel = safeRel(value, label);
	if (!/^snapshots\/[0-9a-f]{64}$/.test(rel))
		throw new MetadataError(`invalid ${label}`);
	return rel;
}
function snapshot(value: unknown, label: string): SnapshotMetadata | null {
	if (value === null) return null;
	const s = object(value, label),
		path = snapshotRel(s.path, `${label} path`),
		owned = files(s.ownedFiles);
	if (
		!path ||
		typeof s.version !== "string" ||
		!SEMVER.test(s.version) ||
		typeof s.sourceCommit !== "string" ||
		!HEX40.test(s.sourceCommit) ||
		!["clean", "development-dirty"].includes(s.sourceState as string) ||
		typeof s.snapshotHash !== "string" ||
		!HEX64.test(s.snapshotHash) ||
		path.slice(10) !== s.snapshotHash ||
		snapshotIdentity(s.version, owned) !== s.snapshotHash
	)
		throw new MetadataError(`invalid ${label} identity`);
	return {
		path,
		version: s.version,
		sourceCommit: s.sourceCommit,
		sourceState: s.sourceState as SnapshotMetadata["sourceState"],
		snapshotHash: s.snapshotHash,
		ownedFiles: owned,
	};
}
export function readManifest(path: string): Manifest | null {
	if (!existsSync(path)) return null;
	const m = parse(path, "manifest");
	if (m.schema !== 2) throw new MetadataError("invalid manifest schema");
	const active = snapshot(m.active, "active");
	if (!active) throw new MetadataError("invalid active snapshot");
	return { schema: 2, active, previous: snapshot(m.previous, "previous") };
}
export function snapshotFor(r: Release, path: string): SnapshotMetadata {
	return {
		path,
		version: r.version,
		sourceCommit: r.sourceCommit,
		sourceState: r.sourceState,
		snapshotHash: r.snapshotHash,
		ownedFiles: r.files,
	};
}
export function manifestFor(
	r: Release,
	active: string,
	previous: SnapshotMetadata | null,
): Manifest {
	return { schema: 2, active: snapshotFor(r, active), previous };
}
