import { execFileSync } from "node:child_process";
import { createHash } from "node:crypto";
import { mkdtempSync, readFileSync, rmSync, statSync } from "node:fs";
import { basename, dirname, join, resolve } from "node:path";
import { tmpdir } from "node:os";
import { fileURLToPath } from "node:url";

const digest = (algorithm, bytes, encoding) => createHash(algorithm).update(bytes).digest(encoding);

export function verifyArtifact(metadataFile = "artifacts/pack-metadata.json") {
	const metadataPath = resolve(metadataFile), metadata = JSON.parse(readFileSync(metadataPath, "utf8"));
	if (metadata.schema !== 1 || typeof metadata.filename !== "string" || basename(metadata.filename) !== metadata.filename || !/^ccl-skills-\d+\.\d+\.\d+\.tgz$/.test(metadata.filename))
		throw new Error("invalid artifact metadata");
	const artifact = join(dirname(metadataPath), metadata.filename), bytes = readFileSync(artifact),
		integrity = `sha512-${digest("sha512", bytes, "base64")}`, shasum = digest("sha1", bytes, "hex");
	if (metadata.integrity !== integrity || metadata.shasum !== shasum) throw new Error("artifact integrity mismatch");
	const extract = mkdtempSync(join(tmpdir(), "ccl-skills-artifact-"));
	try {
		execFileSync("tar", ["-xzf", artifact, "-C", extract]);
		execFileSync(process.execPath, [resolve("scripts/verify-packed.mjs"), join(extract, "package/dist/assets")], { stdio: "inherit", env: process.env });
		if ((statSync(join(extract, "package/dist/cli.js")).mode & 0o111) === 0) throw new Error("packed CLI is not executable");
	} finally {
		rmSync(extract, { recursive: true, force: true });
	}
	return { metadata, artifact };
}

if (process.argv[1] && fileURLToPath(import.meta.url) === resolve(process.argv[1])) {
	const { metadata } = verifyArtifact(process.argv[2]);
	console.log(JSON.stringify({ status: "artifact-verified", filename: metadata.filename, integrity: metadata.integrity, shasum: metadata.shasum }));
}
