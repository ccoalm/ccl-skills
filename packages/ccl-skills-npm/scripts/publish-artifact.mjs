import { spawnSync } from "node:child_process";
import { verifyArtifact } from "./verify-artifact.mjs";

const { artifact, metadata } = verifyArtifact(process.argv[2]);
console.log(JSON.stringify({ status: "publishing-verified-artifact", filename: metadata.filename, integrity: metadata.integrity }));
const published = spawnSync("npm", ["publish", artifact, "--access", "public"], { stdio: "inherit" });
process.exit(published.status ?? 1);
