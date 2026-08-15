import {
	copyFileSync,
	existsSync,
	lstatSync,
	mkdirSync,
	readFileSync,
	readdirSync,
	renameSync,
	rmSync,
	rmdirSync,
} from "node:fs";
import { dirname, join, relative, resolve, sep } from "node:path";
import {
	acquireLock,
	assertSafeRoot,
	atomicJson,
	canonicalAlias,
	contained,
	copyRegularTree,
	durableRename,
	durableUnlink,
	sha256,
	verifyTree,
} from "./fs-safe.js";
import {
	checkHost,
	marketplaceAdd,
	marketplaceRemove,
	pluginAdd,
	pluginRemove,
	publicState,
} from "./codex-host.js";
import {
	manifestFor,
	MetadataError,
	readManifest,
	readRelease,
} from "./manifest.js";
import {
	paths,
	type InterruptionCheckpoint,
	type PathContext,
} from "./paths.js";
import type { Journal, Manifest, Options, OwnedFile, Result } from "./types.js";
import { compare } from "./version.js";

const pending = (
	message: string,
	details: Record<string, unknown> = {},
): Result => ({
	code: 3,
	status: "installed-hooks-pending",
	message,
	trust: "pending-unverified",
	details,
});
const activePath = (root: string, active: string): string => join(root, active);
const marketPath = (root: string, active: string): string =>
	join(activePath(root, active), "marketplace");

function writeJournal(
	path: string,
	value: Omit<Journal, "schema" | "startedAt">,
	context: PathContext = {},
): void {
	atomicJson(
		path,
		{ schema: 1, startedAt: new Date().toISOString(), ...value },
		context.fs,
	);
}

function journal(path: string, root: string): Journal | null {
	try {
		const value = JSON.parse(readFileSync(path, "utf8")) as Journal;
		if (
			value.schema !== 1 ||
			typeof value.operation !== "string" ||
			typeof value.step !== "string" ||
			typeof value.startedAt !== "string"
		)
			return null;
		if (
			value.completed &&
			!value.completed.every((item) => typeof item === "string")
		)
			return null;
		if (
			value.deletedFiles &&
			!value.deletedFiles.every(
				(item) =>
					typeof item === "string" &&
					!item.startsWith("/") &&
					!item.split(sep).includes(".."),
			)
		)
			return null;
		if (
			value.trashPath &&
			(!value.trashPath.startsWith(".trash-") ||
				value.trashPath.includes(sep) ||
				contained(root, value.trashPath) !== join(root, value.trashPath))
		)
			return null;
		return value;
	} catch {
		return null;
	}
}
function interrupted(
	context: PathContext,
	name: InterruptionCheckpoint,
): boolean {
	return (
		context.checkpoint?.(name) === true ||
		context.isInterrupted?.(name) === true
	);
}
function interruption(result: Result): Result {
	return { ...result, code: 130, interrupted: true };
}

function symlinkBelow(root: string): string | null {
	if (!existsSync(root)) return null;
	for (const entry of readdirSync(root, { withFileTypes: true })) {
		const path = join(root, entry.name);
		if (lstatSync(path).isSymbolicLink()) return path;
		if (entry.isDirectory()) {
			const found = symlinkBelow(path);
			if (found) return found;
		}
	}
	return null;
}

function exactState(
	codexHome: string,
	source: string | null,
	plugin: boolean,
): boolean {
	const state = publicState(codexHome);
	return (
		state.status === "known" &&
		(state.marketplaceSource
			? canonicalAlias(state.marketplaceSource)
			: null) === (source ? canonicalAlias(resolve(source)) : null) &&
		state.plugin === plugin
	);
}

function removeRegistration(codexHome: string): boolean {
	const state = publicState(codexHome);
	if (state.status === "unknown") return false;
	if (state.plugin && pluginRemove(codexHome).status !== 0) return false;
	const afterPlugin = publicState(codexHome);
	if (afterPlugin.status === "unknown") return false;
	if (afterPlugin.marketplace && marketplaceRemove(codexHome).status !== 0)
		return false;
	return exactState(codexHome, null, false);
}

function restoreOld(codexHome: string, source: string): boolean {
	if (!removeRegistration(codexHome)) return false;
	if (marketplaceAdd(source, codexHome).status !== 0) return false;
	if (pluginAdd(codexHome).status !== 0) return false;
	return exactState(codexHome, source, true);
}

function removeEmptyTree(root: string, files: OwnedFile[]): void {
	const dirs = new Set(files.map((f) => dirname(join(root, f.path))));
	for (const dir of [...dirs].sort((a, b) => b.length - a.length)) {
		try {
			rmdirSync(dir);
		} catch {}
	}
	try {
		rmdirSync(root);
	} catch {}
}
function remainingErrors(
	root: string,
	snapshot: NonNullable<Manifest["previous"]>,
	deleted: string[],
): string[] {
	const deletedSet = new Set(deleted),
		remaining = snapshot.ownedFiles.filter(
			(file) => !deletedSet.has(file.path),
		),
		errors = verifyTree(root, remaining);
	for (const file of deleted)
		if (existsSync(contained(root, file)))
			errors.push(`${file}: recorded deleted but exists`);
	return errors;
}
function deleteTrash(
	path: string,
	snapshot: NonNullable<Manifest["previous"]>,
	operation: string,
	committed: boolean,
	deleted: string[],
	context: PathContext,
): string[] {
	const p = paths(context),
		errors: string[] = [];
	for (const file of [...snapshot.ownedFiles].sort(
		(a, b) => b.path.length - a.path.length,
	)) {
		if (deleted.includes(file.path)) continue;
		const target = contained(path, file.path);
		try {
			durableUnlink(target, context.fs, "trash-unlink");
			deleted.push(file.path);
			writeJournal(
				p.journal,
				{
					operation,
					step: "trash-deleting",
					trashPath: relative(p.root, path),
					snapshot,
					completed: ["trash-renamed"],
					deletedFiles: [...deleted],
					committed,
				},
				context,
			);
		} catch (error) {
			errors.push(`${file.path}: ${String(error)}`);
			break;
		}
	}
	if (!errors.length) removeEmptyTree(path, snapshot.ownedFiles);
	return errors;
}
function quarantine(
	path: string,
	snapshot: NonNullable<Manifest["previous"]>,
	operation: string,
	context: PathContext,
): { errors: string[]; trash?: string } {
	if (!existsSync(path)) return { errors: [] };
	const errors = verifyTree(path, snapshot.ownedFiles);
	if (errors.length) return { errors };
	const p = paths(context),
		trashRel = `.trash-${operation}-${snapshot.snapshotHash}`,
		trash = contained(p.root, trashRel),
		committed = operation === "prune";
	if (existsSync(trash)) return { errors: ["trash path already exists"] };
	try {
		durableRename(path, trash, context.fs, "quarantine-rename");
	} catch (error) {
		const renamed = !existsSync(path) && existsSync(trash);
		writeJournal(
			p.journal,
			{
				operation,
				step: renamed ? "trash-renamed" : "quarantine-rename-failed",
				trashPath: renamed ? trashRel : undefined,
				snapshot,
				completed: renamed ? ["trash-renamed"] : [],
				deletedFiles: [],
				error: String(error),
				committed,
			},
			context,
		);
		return { errors: [String(error)], trash: renamed ? trash : undefined };
	}
	writeJournal(
		p.journal,
		{
			operation,
			step: "trash-renamed",
			trashPath: trashRel,
			snapshot,
			completed: ["trash-renamed"],
			deletedFiles: [],
			committed,
		},
		context,
	);
	return {
		errors: deleteTrash(trash, snapshot, operation, committed, [], context),
		trash,
	};
}
function cleanupCandidate(
	path: string,
	files: OwnedFile[],
	context: PathContext,
): string[] {
	if (!existsSync(path)) return [];
	const errors = verifyTree(path, files);
	if (errors.length) return errors;
	for (const file of [...files].sort((a, b) => b.path.length - a.path.length))
		try {
			durableUnlink(contained(path, file.path), context.fs);
		} catch (error) {
			return [`${file.path}: ${String(error)}`];
		}
	removeEmptyTree(path, files);
	return [];
}
function resumeJournal(context: PathContext): Result | null {
	const p = paths(context),
		j = journal(p.journal, p.root);
	if (!j)
		return {
			code: 5,
			status: "partial-journal",
			message: "operation journal is malformed",
		};
	if (j.step === "committed" || j.step === "journal-unlink-failed") {
		if (j.operation !== "install" && j.operation !== "update")
			return {
				code: 5,
				status: "partial-journal",
				message: "committed journal operation is invalid",
			};
		const manifest = readManifest(p.manifest);
		if (
			!manifest ||
			!exactState(p.codexHome, marketPath(p.root, manifest.active.path), true)
		)
			return {
				code: 5,
				status: "partial-journal",
				message: "committed journal does not match public and manifest state",
			};
		try {
			durableUnlink(p.journal, context.fs, "journal-unlink");
			return null;
		} catch (error) {
			return {
				code: 5,
				status: "committed-stale-journal",
				message: "committed state is intact; stale journal cleanup failed",
				details: { error: String(error) },
			};
		}
	}
	if (
		j.operation === "uninstall" &&
		j.step === "quarantine-rename-failed" &&
		j.snapshot
	) {
		if (!exactState(p.codexHome, null, false))
			return {
				code: 5,
				status: "partial",
				message: "uninstall resume requires absent public state",
			};
		const q = quarantine(
			activePath(p.root, j.snapshot.path),
			j.snapshot,
			"uninstall",
			context,
		);
		if (q.errors.length)
			return {
				code: 5,
				status: "partial",
				message: "registration removed; local cleanup requires resume",
				details: { errors: q.errors, trashPath: q.trash },
			};
		try {
			if (existsSync(p.manifest))
				durableUnlink(p.manifest, context.fs, "manifest-unlink");
			durableUnlink(p.journal, context.fs, "journal-unlink");
			rmSync(p.root, { recursive: true });
			return {
				code: 0,
				status: "uninstalled",
				message: "resumed verified uninstall cleanup",
			};
		} catch (error) {
			return {
				code: 5,
				status: "partial",
				message: "uninstall cleanup completed but metadata remains",
				details: { error: String(error) },
			};
		}
	}
	if (j.trashPath && j.snapshot) {
		const trash = contained(p.root, j.trashPath),
			deleted = j.deletedFiles || [],
			errors = remainingErrors(trash, j.snapshot, deleted);
		if (errors.length)
			return {
				code: 5,
				status: "unknown-trash",
				message: "trash metadata verification failed",
				details: { errors },
			};
		const deletion = deleteTrash(
			trash,
			j.snapshot,
			j.operation,
			!!j.committed,
			[...deleted],
			context,
		);
		if (deletion.length)
			return {
				code: 5,
				status: j.committed ? "committed-stale-cleanup" : "partial",
				message: "trash cleanup remains incomplete",
				details: { errors: deletion },
			};
		if (j.operation === "uninstall") {
			try {
				if (existsSync(p.manifest))
					durableUnlink(p.manifest, context.fs, "manifest-unlink");
				durableUnlink(p.journal, context.fs, "journal-unlink");
				rmSync(p.root, { recursive: true });
				return {
					code: 0,
					status: "uninstalled",
					message: "resumed verified uninstall cleanup",
				};
			} catch (error) {
				return {
					code: 5,
					status: "partial",
					message: "uninstall cleanup completed but metadata remains",
					details: { error: String(error) },
				};
			}
		}
		try {
			durableUnlink(p.journal, context.fs, "journal-unlink");
		} catch (error) {
			return {
				code: 5,
				status: j.committed ? "committed-stale-journal" : "partial",
				message: "cleanup completed but journal remains",
				details: { error: String(error) },
			};
		}
		return null;
	}
	return {
		code: 5,
		status: "partial-journal",
		message: "an incomplete operation journal requires repair",
	};
}

function rollbackResult(
	operation: string,
	old: Manifest | null,
	candidate: string,
	candidateFiles: OwnedFile[],
	error: string,
	context: PathContext,
): Result {
	const p = paths(context);
	const oldSource = old ? marketPath(p.root, old.active.path) : null;
	const restored =
		old && oldSource
			? restoreOld(p.codexHome, oldSource)
			: removeRegistration(p.codexHome);
	if (!restored) {
		writeJournal(p.journal, {
			operation,
			step: "rollback-partial",
			oldSource,
			candidateSource: join(candidate, "marketplace"),
			error,
		});
		return {
			code: 5,
			status: "partial",
			message: `${operation} failed and rollback finality is unknown`,
		};
	}
	const cleanup = cleanupCandidate(candidate, candidateFiles, context);
	if (cleanup.length === 0) {
		rmSync(p.journal, { force: true });
		return {
			code: 1,
			status: "rolled-back",
			message: `${operation} failed; prior public state was restored`,
		};
	}
	writeJournal(p.journal, {
		operation,
		step: "rollback-partial",
		oldSource,
		candidateSource: join(candidate, "marketplace"),
		error: `${error}${cleanup.length ? `; cleanup: ${cleanup.join(", ")}` : ""}`,
	});
	return {
		code: 5,
		status: "partial",
		message: `${operation} failed and rollback finality is unknown`,
	};
}

function conflict(command: string, context: PathContext): Result | null {
	const p = paths(context),
		manifest = readManifest(p.manifest),
		state = publicState(p.codexHome);
	if (state.status === "unknown")
		return {
			code: 3,
			status: "host-state-unknown",
			message: "Codex public state could not be verified",
		};
	if (state.legacy)
		return {
			code: 3,
			status: "legacy-plugin-conflict",
			message: "Git-backed ccl-skills plugin is installed",
		};
	const legacy = symlinkBelow(join(p.codexHome, "skills"));
	if (legacy && /ccl-skills/.test(legacy))
		return {
			code: 3,
			status: "legacy-skill-symlink",
			message: `legacy ccl-skills symlink exists: ${legacy}`,
		};
	const managed = symlinkBelow(p.root);
	if (managed)
		return {
			code: 3,
			status: "symlink-conflict",
			message: `managed path contains symlink: ${managed}`,
		};
	if (!manifest && (state.marketplace || state.plugin))
		return {
			code: 3,
			status: "unowned-registration",
			message: "ccl-skills-npm is registered without an owned manifest",
		};
	if (command !== "doctor" && existsSync(p.journal))
		return {
			code: 5,
			status: "partial-journal",
			message: "an incomplete operation journal requires repair",
		};
	return null;
}

function doctor(context: PathContext): Result {
	const p = paths(context);
	try {
		assertSafeRoot(p.codexHome, p.root);
	} catch (error) {
		return { code: 3, status: "safety-refusal", message: String(error) };
	}
	const host = checkHost(p.codexHome);
	if (!host.ok)
		return { code: 4, status: `host-${host.kind}`, message: host.message };
	if (existsSync(p.journal)) {
		const repair = resumeJournal(context);
		if (repair) return repair;
	}
	const unknownTrash = existsSync(p.root)
		? readdirSync(p.root).filter((name) => name.startsWith(".trash-"))
		: [];
	if (unknownTrash.length)
		return {
			code: 5,
			status: "unknown-trash",
			message: "unreferenced trash requires manual ownership verification",
			details: { trash: unknownTrash },
		};
	const problem = conflict("doctor", context);
	if (problem) return problem;
	const manifest = readManifest(p.manifest);
	if (!manifest)
		return {
			code: 3,
			status: "absent",
			message: "ccl-skills is not installed",
			trust: "pending-unverified",
		};
	const drift = verifyTree(
		activePath(p.root, manifest.active.path),
		manifest.active.ownedFiles,
	);
	if (drift.length)
		return {
			code: 3,
			status: "owned-drift",
			message: "owned files are missing or modified",
			details: { drift },
		};
	if (!exactState(p.codexHome, marketPath(p.root, manifest.active.path), true))
		return {
			code: 3,
			status: "public-state-mismatch",
			message:
				"owned files exist but Codex registration does not match the manifest",
		};
	return pending("plugin is installed; hooks trust is pending/unverified", {
		version: manifest.active.version,
	});
}

function installOrUpdate(
	command: "install" | "update",
	options: Options,
	context: PathContext,
): Result {
	const p = paths(context);
	try {
		assertSafeRoot(p.codexHome, p.root, true);
	} catch (error) {
		return { code: 3, status: "safety-refusal", message: String(error) };
	}
	const host = checkHost(p.codexHome);
	if (!host.ok)
		return { code: 4, status: `host-${host.kind}`, message: host.message };
	if (existsSync(p.journal)) {
		const repair = resumeJournal(context);
		if (repair) return repair;
	}
	const problem = conflict(command, context);
	if (problem) return problem;
	const old = readManifest(p.manifest),
		release = readRelease(p.release);
	if (command === "update" && !old)
		return {
			code: 3,
			status: "not-installed",
			message: "update requires an existing owned installation",
		};
	if (old) {
		const drift = verifyTree(
			activePath(p.root, old.active.path),
			old.active.ownedFiles,
		);
		if (drift.length)
			return {
				code: 3,
				status: "owned-drift",
				message: "owned files drifted",
				details: { drift },
			};
		if (!exactState(p.codexHome, marketPath(p.root, old.active.path), true))
			return {
				code: 3,
				status: "public-state-mismatch",
				message: "public state does not match the owned manifest",
			};
		const comparison = compare(release.version, old.active.version);
		if (comparison === 0)
			return command === "install"
				? {
						...doctor(context),
						message:
							"same version is already installed; hooks trust remains pending/unverified",
					}
				: doctor(context);
		if (command === "install")
			return {
				code: 3,
				status: "use-update",
				message: "an owned version exists; use update",
			};
		if (comparison < 0 && !options.allowDowngrade)
			return {
				code: 3,
				status: "downgrade-refused",
				message: "newer version is installed; pass --allow-downgrade --yes",
			};
	}
	if (command === "update" && !options.yes)
		return {
			code: 0,
			status: "dry-run",
			message: "update preview",
			plan: [
				"prepare immutable snapshot",
				"replace Codex registration",
				"verify exact candidate source",
				"commit active/previous manifest pointers",
			],
		};
	if (options.allowDowngrade && !options.yes)
		return {
			code: 2,
			status: "usage",
			message: "--allow-downgrade requires --yes",
		};
	const snapshotRel = join("snapshots", release.snapshotHash),
		snapshot = contained(p.root, snapshotRel);
	let unlock: () => void;
	try {
		unlock = acquireLock(p.lock);
	} catch {
		return {
			code: 3,
			status: "lock-contended",
			message: "another operation holds the lock",
		};
	}
	let candidateCreated = false;
	try {
		if (interrupted(context, "before-first-mutation"))
			return interruption({
				code: 1,
				status: "rolled-back",
				message: "interrupted before mutation",
			});
		mkdirSync(p.root, { recursive: true });
		if (existsSync(snapshot)) {
			const drift = verifyTree(snapshot, release.files);
			if (drift.length)
				return {
					code: 3,
					status: "snapshot-drift",
					message: "existing snapshot failed verification",
					details: { drift },
				};
		} else {
			const staging = contained(
				p.root,
				join("snapshots", `.staging-${release.snapshotHash}-${process.pid}`),
			);
			rmSync(staging, { recursive: true, force: true });
			copyRegularTree(
				join(p.assets, "marketplace"),
				join(staging, "marketplace"),
			);
			const drift = verifyTree(staging, release.files);
			if (drift.length) {
				rmSync(staging, { recursive: true, force: true });
				return {
					code: 3,
					status: "safety-refusal",
					message: "staged snapshot failed verification",
					details: { drift },
				};
			}
			renameSync(staging, snapshot);
			candidateCreated = true;
		}
		const candidateMarket = join(snapshot, "marketplace"),
			hidden = join(candidateMarket, ".agents/plugins/marketplace.json"),
			carrier = join(candidateMarket, "marketplace-manifest.json");
		if (!existsSync(hidden)) {
			if (!existsSync(carrier))
				throw new Error("packed marketplace manifest carrier is missing");
			mkdirSync(join(candidateMarket, ".agents/plugins"), { recursive: true });
			copyFileSync(carrier, hidden);
		}
		const oldSource = old ? marketPath(p.root, old.active.path) : null;
		writeJournal(p.journal, {
			operation: command,
			step: "candidate-prepared",
			oldSource,
			candidateSource: candidateMarket,
			completed: ["candidate-prepared"],
		});
		if (old && pluginRemove(p.codexHome).status !== 0)
			return rollbackResult(
				command,
				old,
				snapshot,
				release.files,
				"old plugin remove failed",
				context,
			);
		if (old)
			writeJournal(p.journal, {
				operation: command,
				step: "old-plugin-removed",
				oldSource,
				candidateSource: candidateMarket,
				completed: ["candidate-prepared", "old-plugin-removed"],
			});
		if (old && interrupted(context, "after-old-plugin-remove"))
			return interruption(
				rollbackResult(
					command,
					old,
					snapshot,
					release.files,
					"interrupted after old plugin remove",
					context,
				),
			);
		if (old && marketplaceRemove(p.codexHome).status !== 0)
			return rollbackResult(
				command,
				old,
				snapshot,
				release.files,
				"old marketplace remove failed",
				context,
			);
		if (old)
			writeJournal(p.journal, {
				operation: command,
				step: "old-marketplace-removed",
				oldSource,
				candidateSource: candidateMarket,
				completed: [
					"candidate-prepared",
					"old-plugin-removed",
					"old-marketplace-removed",
				],
			});
		if (old && interrupted(context, "after-old-marketplace-remove"))
			return interruption(
				rollbackResult(
					command,
					old,
					snapshot,
					release.files,
					"interrupted after old marketplace remove",
					context,
				),
			);
		if (marketplaceAdd(candidateMarket, p.codexHome).status !== 0)
			return rollbackResult(
				command,
				old,
				snapshot,
				release.files,
				"candidate marketplace add failed",
				context,
			);
		writeJournal(p.journal, {
			operation: command,
			step: "candidate-marketplace-added",
			oldSource,
			candidateSource: candidateMarket,
			completed: [
				"candidate-prepared",
				"old-plugin-removed",
				"old-marketplace-removed",
				"candidate-marketplace-added",
			],
		});
		if (interrupted(context, "after-candidate-marketplace-add"))
			return interruption(
				rollbackResult(
					command,
					old,
					snapshot,
					release.files,
					"interrupted after candidate marketplace add",
					context,
				),
			);
		if (pluginAdd(p.codexHome).status !== 0)
			return rollbackResult(
				command,
				old,
				snapshot,
				release.files,
				"candidate plugin add failed",
				context,
			);
		writeJournal(p.journal, {
			operation: command,
			step: "candidate-plugin-added",
			oldSource,
			candidateSource: candidateMarket,
			completed: [
				"candidate-prepared",
				"old-plugin-removed",
				"old-marketplace-removed",
				"candidate-marketplace-added",
				"candidate-plugin-added",
			],
		});
		if (interrupted(context, "after-candidate-plugin-add"))
			return interruption(
				rollbackResult(
					command,
					old,
					snapshot,
					release.files,
					"interrupted after candidate plugin add",
					context,
				),
			);
		if (!exactState(p.codexHome, candidateMarket, true))
			return rollbackResult(
				command,
				old,
				snapshot,
				release.files,
				"candidate public verification failed",
				context,
			);
		writeJournal(p.journal, {
			operation: command,
			step: "candidate-verified",
			oldSource,
			candidateSource: candidateMarket,
			completed: [
				"candidate-prepared",
				"old-removed",
				"candidate-added",
				"candidate-verified",
			],
		});
		if (interrupted(context, "after-public-verify-before-manifest"))
			return interruption(
				rollbackResult(
					command,
					old,
					snapshot,
					release.files,
					"interrupted before manifest commit",
					context,
				),
			);
		try {
			atomicJson(
				p.manifest,
				manifestFor(release, snapshotRel, old?.active || null),
				context.fs,
			);
		} catch (error) {
			return {
				code: 5,
				status: "partial",
				message: "manifest durability is unknown; journal retained",
				details: { error: String(error) },
			};
		}
		writeJournal(
			p.journal,
			{
				operation: command,
				step: "committed",
				oldSource,
				candidateSource: candidateMarket,
				completed: ["manifest-committed"],
				committed: true,
			},
			context,
		);
		const interruptedAfterCommit = interrupted(
			context,
			"after-manifest-commit",
		);
		const retainedDrift: string[] = [];
		if (old?.previous) {
			const obsolete = activePath(p.root, old.previous.path);
			const errors = verifyTree(obsolete, old.previous.ownedFiles);
			if (errors.length) {
				retainedDrift.push(...errors);
				atomicJson(
					join(p.root, "ownership-evidence.json"),
					{ schema: 1, snapshot: old.previous, drift: errors },
					context.fs,
				);
			} else {
				const q = quarantine(obsolete, old.previous, "prune", context);
				if (q.errors.length)
					return {
						code: 5,
						status: "committed-stale-cleanup",
						message:
							"new version committed; obsolete snapshot cleanup requires resume",
						details: { errors: q.errors, trashPath: q.trash },
					};
			}
		}
		try {
			durableUnlink(p.journal, context.fs, "journal-unlink");
		} catch (error) {
			writeJournal(
				p.journal,
				{
					operation: command,
					step: "journal-unlink-failed",
					committed: true,
					error: String(error),
				},
				context,
			);
			return {
				code: 5,
				status: "committed-stale-journal",
				message: "new version committed; stale journal requires cleanup",
			};
		}
		const result = pending(
			"plugin installed and publicly verified; hooks trust is pending/unverified",
			{ version: release.version, retainedDrift },
		);
		return interruptedAfterCommit
			? interruption({
					...result,
					status: "committed",
					message:
						"interrupted after manifest commit; new state remains active",
				})
			: result;
	} catch (error) {
		if (!candidateCreated)
			writeJournal(p.journal, {
				operation: command,
				step: "exception",
				error: String(error),
			});
		return rollbackResult(
			command,
			old,
			snapshot,
			release.files,
			String(error),
			context,
		);
	} finally {
		unlock!();
	}
}

function uninstall(options: Options, context: PathContext): Result {
	const p = paths(context);
	if (!options.yes)
		return {
			code: 0,
			status: "dry-run",
			message: "uninstall preview",
			plan: [
				"verify ownership and exact public state",
				"remove plugin and marketplace",
				"verify absent",
				"delete only verified owned files",
			],
		};
	try {
		assertSafeRoot(p.codexHome, p.root);
	} catch (error) {
		return { code: 3, status: "safety-refusal", message: String(error) };
	}
	if (existsSync(p.journal)) {
		const repair = resumeJournal(context);
		if (repair) return repair;
	}
	const problem = conflict("uninstall", context);
	if (problem) return problem;
	const manifest = readManifest(p.manifest);
	if (!manifest)
		return { code: 0, status: "absent", message: "nothing to uninstall" };
	const active = activePath(p.root, manifest.active.path),
		source = marketPath(p.root, manifest.active.path),
		drift = verifyTree(active, manifest.active.ownedFiles);
	if (drift.length)
		return {
			code: 3,
			status: "modified-owned-files",
			message: "modified owned files were retained with ownership evidence",
			details: { drift },
		};
	if (!exactState(p.codexHome, source, true))
		return {
			code: 3,
			status: "public-state-mismatch",
			message: "public state does not match the owned manifest",
		};
	let unlock: () => void;
	try {
		unlock = acquireLock(p.lock);
	} catch {
		return {
			code: 3,
			status: "lock-contended",
			message: "another operation holds the lock",
		};
	}
	try {
		writeJournal(
			p.journal,
			{
				operation: "uninstall",
				step: "started",
				oldSource: source,
				completed: [],
			},
			context,
		);
		const rollback = (wasInterrupted: boolean): Result => {
			const restored = restoreOld(p.codexHome, source);
			let result: Result;
			if (restored) {
				rmSync(p.journal, { force: true });
				result = {
					code: 1,
					status: "rolled-back",
					message: `uninstall ${wasInterrupted ? "interrupted" : "failed"}; prior public state was restored`,
				};
			} else {
				writeJournal(
					p.journal,
					{
						operation: "uninstall",
						step: "restore-partial",
						oldSource: source,
						error: "public removal or restore failed",
					},
					context,
				);
				result = {
					code: 5,
					status: "partial",
					message: `uninstall ${wasInterrupted ? "interrupted" : "failed"} and restore finality is unknown`,
				};
			}
			return wasInterrupted ? interruption(result) : result;
		};
		if (pluginRemove(p.codexHome).status !== 0) return rollback(false);
		writeJournal(
			p.journal,
			{
				operation: "uninstall",
				step: "old-plugin-removed",
				oldSource: source,
				completed: ["old-plugin-removed"],
			},
			context,
		);
		if (interrupted(context, "after-uninstall-plugin-remove"))
			return rollback(true);
		if (marketplaceRemove(p.codexHome).status !== 0) return rollback(false);
		writeJournal(
			p.journal,
			{
				operation: "uninstall",
				step: "old-marketplace-removed",
				oldSource: source,
				completed: ["old-plugin-removed", "old-marketplace-removed"],
			},
			context,
		);
		if (interrupted(context, "after-uninstall-marketplace-remove"))
			return rollback(true);
		if (!exactState(p.codexHome, null, false)) {
			const restored = restoreOld(p.codexHome, source);
			if (restored) {
				rmSync(p.journal, { force: true });
				return {
					code: 1,
					status: "rolled-back",
					message: "uninstall failed; prior public state was restored",
				};
			}
			writeJournal(p.journal, {
				operation: "uninstall",
				step: "restore-partial",
				oldSource: source,
				error: "public removal or restore failed",
			});
			return {
				code: 5,
				status: "partial",
				message: "uninstall failed and restore finality is unknown",
			};
		}
		writeJournal(
			p.journal,
			{
				operation: "uninstall",
				step: "public-absent-committed",
				oldSource: source,
				completed: [
					"old-plugin-removed",
					"old-marketplace-removed",
					"public-absent-committed",
				],
				committed: true,
			},
			context,
		);
		const interruptedCommitted = interrupted(
			context,
			"after-uninstall-public-absent-commit",
		);
		const snapshots = [manifest.active, manifest.previous].filter(
			Boolean,
		) as Array<NonNullable<typeof manifest.previous>>;
		for (const snapshot of snapshots) {
			const q = quarantine(
				activePath(p.root, snapshot.path),
				snapshot,
				"uninstall",
				context,
			);
			if (q.errors.length) {
				const stale: Result = {
					code: 5,
					status: "committed-stale-cleanup",
					message:
						"registration removal committed; local cleanup requires resume",
					details: { errors: q.errors, trashPath: q.trash },
				};
				return interruptedCommitted ? interruption(stale) : stale;
			}
		}
		durableUnlink(p.manifest, context.fs);
		durableUnlink(p.journal, context.fs);
		rmSync(p.root, { recursive: true });
		const result: Result = {
			code: 0,
			status: "uninstalled",
			message: "Codex registration removed and verified owned files deleted",
		};
		return interruptedCommitted ? interruption(result) : result;
	} finally {
		unlock!();
	}
}

export function run(
	command: string,
	options: Options = {},
	context: PathContext = {},
): Result {
	try {
		if (command === "doctor") return doctor(context);
		if (command === "install")
			return installOrUpdate("install", options, context);
		if (command === "update")
			return installOrUpdate("update", options, context);
		if (command === "uninstall") return uninstall(options, context);
		return { code: 2, status: "usage", message: "unknown command" };
	} catch (error) {
		if (error instanceof MetadataError)
			return { code: 3, status: "safety-refusal", message: error.message };
		return { code: 5, status: "partial", message: String(error) };
	}
}
