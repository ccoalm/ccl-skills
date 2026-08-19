import { execFileSync, spawnSync } from "node:child_process"
import { readFileSync } from "node:fs"
import { resolve } from "node:path"

process.umask(0o002)
execFileSync(process.execPath,[resolve("scripts/build-assets.mjs")],{stdio:"inherit"})
const release=JSON.parse(readFileSync("dist/assets/release.json","utf8"))
for(const file of release.files){
  if(![0o644,0o755].includes(file.mode))throw Error(`non-canonical runtime mode: ${file.path}`)
}
execFileSync(process.execPath,[resolve("scripts/verify-packed.mjs"),resolve("dist/assets")],{stdio:"inherit"})
const ciGitCommit="fedcba9876543210fedcba9876543210fedcba98"
const githubCommit="abcdef0123456789abcdef0123456789abcdef01"
execFileSync(process.execPath,[resolve("scripts/build-assets.mjs")],{stdio:"inherit",env:{...process.env,CI:"true",GITHUB_SHA:githubCommit,CI_COMMIT_SHA:ciGitCommit}})
const ciGitRelease=JSON.parse(readFileSync("dist/assets/release.json","utf8"))
if(ciGitRelease.sourceCommit!==githubCommit)throw Error("CI git-present build did not prefer GITHUB_SHA")
const ciCommit="0123456789abcdef0123456789abcdef01234567"
const noGitEnv={...process.env,PATH:"/nonexistent",CI:"true",CI_COMMIT_SHA:ciCommit}
delete noGitEnv.GITHUB_SHA
const noGit=spawnSync(process.execPath,[resolve("scripts/build-assets.mjs")],{encoding:"utf8",env:noGitEnv})
if(noGit.status===0)throw Error("CI no-git build must fail closed")
if(!/git is required/.test(noGit.stderr))throw Error(`CI no-git failure was not attributable: ${noGit.stderr}`)
console.log(JSON.stringify({status:"build-modes-verified",umask:"0002",files:release.files.length}))
