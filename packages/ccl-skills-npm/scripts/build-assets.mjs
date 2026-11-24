import { createHash } from "node:crypto"
import { chmodSync, cpSync, lstatSync, mkdirSync, readdirSync, readFileSync, rmSync, writeFileSync } from "node:fs"
import { dirname, join, relative, resolve } from "node:path"
import { fileURLToPath } from "node:url"
import { execFileSync } from "node:child_process"

const pkg=resolve(dirname(fileURLToPath(import.meta.url)),".."),repo=resolve(pkg,"../.."),out=join(pkg,"dist/assets"),market=join(out,"marketplace"),plugin=join(market,"plugins/ccl-skills")
const roots=[".claude-plugin",".codex-plugin",".antigravity-plugin","hooks.json","agent-context","skills","hooks","packages/opencode-plugin","scripts/owner-dispatch",".worktree-only"],sourceRoots=[...roots,"packages/ccl-skills-npm"]
function git(args,options={}){return execFileSync("git",args,{cwd:repo,encoding:options.encoding??"utf8"})}
function gitAvailable(){try{git(["--version"]);return true}catch{return false}}
function ciCommit(){const value=process.env.GITHUB_SHA??process.env.CI_COMMIT_SHA;return value?.match(/^[0-9a-f]{40}$/)?.[0]??null}
function check(path){const st=lstatSync(path);if(st.isSymbolicLink()||(!st.isDirectory()&&!st.isFile())||(st.isFile()&&st.nlink!==1))throw Error(`unsafe asset: ${path}`);if(st.isDirectory())for(const name of readdirSync(path))check(join(path,name))}
const hasGit=gitAvailable()
if(!hasGit)throw Error("git is required to build the tracked runtime closure")
rmSync(out,{recursive:true,force:true});mkdirSync(plugin,{recursive:true})
const REPO_TEST_ASSET_RE=/^(?:hooks\/test_[^/]+|scripts\/owner-dispatch\/test\.sh|skills\/[^/]+\/scripts\/(?:test_[^/]+|[^/]+\.test\.sh))$/
function listTrackedFromGit(){return execFileSync("git",["ls-files","--stage","-z","--",...roots],{cwd:repo,encoding:"buffer"}).toString().split("\0").filter(Boolean).map(record=>{const tab=record.indexOf("\t"),metadata=record.slice(0,tab).split(" "),source=record.slice(tab+1),gitMode=metadata[0],mode=gitMode==="100644"?0o644:gitMode==="100755"?0o755:null;if(tab<0||mode===null)throw Error(`unsupported git mode: ${source||record}`);return{source,mode}}).filter(({source})=>!REPO_TEST_ASSET_RE.test(source))}
const tracked=listTrackedFromGit()
if(!tracked.length)throw Error("tracked runtime closure is empty")
const files=[]
function writeAsset(dst,buf,mode){mkdirSync(dirname(dst),{recursive:true});writeFileSync(dst,buf);chmodSync(dst,mode);const st=lstatSync(dst),actualMode=st.mode&0o777;if(![0o644,0o755].includes(actualMode))throw Error(`unsupported runtime mode: ${relative(out,dst)}`);files.push({path:relative(out,dst),sha256:createHash("sha256").update(buf).digest("hex"),mode:actualMode})}
for(const {source,mode} of tracked){const src=join(repo,source);check(src);const st=lstatSync(src);if(!st.isFile()||st.nlink!==1)throw Error(`tracked runtime entry is not a regular file: ${source}`);if(source.split("/").includes(".gitignore"))continue;writeAsset(join(plugin,source),readFileSync(src),mode)}
const codexMarketBuf=Buffer.from(`${JSON.stringify({name:"ccl-skills-npm",plugins:[{name:"ccl-skills",source:{source:"local",path:"./plugins/ccl-skills"}}]},null,2)}\n`)
const claudeMarketBuf=Buffer.from(`${JSON.stringify({name:"ccl-skills-npm",owner:{name:"ccl-skills maintainers"},plugins:[{name:"ccl-skills",source:"./plugins/ccl-skills",description:"CCL engineering skills and repository guardrails"}]},null,2)}\n`)
writeAsset(join(market,".agents/plugins/marketplace.json"),codexMarketBuf,0o644)
writeAsset(join(market,".claude-plugin/marketplace.json"),claudeMarketBuf,0o644)
writeAsset(join(market,"marketplace-manifest.json"),codexMarketBuf,0o644)
files.sort((a,b)=>a.path.localeCompare(b.path))
const dist=dirname(out),runtime=[];function walkRuntime(path){for(const entry of readdirSync(path,{withFileTypes:true})){const full=join(path,entry.name);if(full===out)continue;if(entry.isDirectory())walkRuntime(full);else{const st=lstatSync(full),mode=st.mode&0o777;if(st.isSymbolicLink()||!st.isFile()||st.nlink!==1||![0o644,0o755].includes(mode))throw Error(`unsafe package runtime: ${relative(dist,full)}`);runtime.push({path:relative(dist,full),sha256:createHash("sha256").update(readFileSync(full)).digest("hex"),mode})}}}walkRuntime(dist);runtime.sort((a,b)=>a.path.localeCompare(b.path));if(!runtime.length)throw Error("compiled package runtime is empty")
const sourceCommit=ciCommit()??(hasGit?git(["rev-parse","HEAD"]).trim():null),sourceState=hasGit?git(["status","--porcelain","--",...sourceRoots]).trim()?"development-dirty":"clean":"clean",version=JSON.parse(readFileSync(join(pkg,"package.json"),"utf8")).version,snapshotHash=createHash("sha256").update(JSON.stringify({version,files})).digest("hex")
writeFileSync(join(out,"release.json"),`${JSON.stringify({schema:1,npmPackage:"@ccoalm/ccl-skills",version,sourceCommit,sourceState,files,runtime,snapshotHash},null,2)}\n`)
