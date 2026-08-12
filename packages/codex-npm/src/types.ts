export type ExitCode = 0 | 1 | 2 | 3 | 4 | 5 | 130
export interface Result { code: ExitCode; status: string; message: string; plan?: string[]; trust?: "pending-unverified"; details?: Record<string, unknown>; interrupted?: boolean }
export interface Options { yes?: boolean; allowDowngrade?: boolean }
export interface OwnedFile { path: string; sha256: string; mode: number }
export interface Release { schema: number; npmPackage: string; version: string; sourceCommit: string; sourceState: "clean"|"development-dirty"; files: OwnedFile[]; snapshotHash: string }
export interface SnapshotMetadata { path: string; version: string; sourceCommit: string; sourceState: "clean"|"development-dirty"; snapshotHash: string; ownedFiles: OwnedFile[] }
export interface Manifest { schema: 2; active: SnapshotMetadata; previous: SnapshotMetadata|null }
export interface Journal { schema: 1; operation: string; step: string; startedAt: string; oldSource?: string|null; candidateSource?: string|null; completed?: string[]; error?: string; trashPath?: string; snapshot?: SnapshotMetadata; committed?: boolean; deletedFiles?: string[] }
