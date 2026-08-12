import { createHash } from "node:crypto"
import { chmodSync, cpSync, lstatSync, mkdirSync, readdirSync, readFileSync, rmSync, writeFileSync } from "node:fs"
import { dirname, join, relative, resolve } from "node:path"
import { fileURLToPath } from "node:url"
import { execFileSync } from "node:child_process"

const pkg=resolve(dirname(fileURLToPath(import.meta.url)),".."),repo=resolve(pkg,"../.."),out=join(pkg,"dist/assets"),market=join(out,"marketplace"),plugin=join(market,"plugins/ccl-skills")
rmSync(out,{recursive:true,force:true});mkdirSync(plugin,{recursive:true})
const roots=[".codex-plugin","agent-context/session-start.md","skills","hooks","scripts/owner-dispatch",".worktree-only"]
function git(args,options={}){return execFileSync("git",args,{cwd:repo,encoding:options.encoding??"utf8"})}
function gitAvailable(){try{git(["--version"]);return true}catch{return false}}
function ciCommit(){const value=process.env.GITHUB_SHA??process.env.CI_COMMIT_SHA;return value?.match(/^[0-9a-f]{40}$/)?.[0]??null}
function check(path){const st=lstatSync(path);if(st.isSymbolicLink()||(!st.isDirectory()&&!st.isFile())||(st.isFile()&&st.nlink!==1))throw Error(`unsafe asset: ${path}`);if(st.isDirectory())for(const name of readdirSync(path))check(join(path,name))}
const hasGit=gitAvailable()
function listTrackedFromGit(){return execFileSync("git",["ls-files","--stage","-z","--",...roots],{cwd:repo,encoding:"buffer"}).toString().split("\0").filter(Boolean).map(record=>{const tab=record.indexOf("\t"),metadata=record.slice(0,tab).split(" "),source=record.slice(tab+1),gitMode=metadata[0],mode=gitMode==="100644"?0o644:gitMode==="100755"?0o755:null;if(tab<0||mode===null)throw Error(`unsupported git mode: ${source||record}`);return{source,mode}})}
function listTrackedFromCiCheckout(){
	if(process.env.CI!=="true"||!ciCommit())throw Error("git is required outside a CI commit checkout")
	const entries=[]
	function walkRoot(rel){const abs=join(repo,rel),st=lstatSync(abs);check(abs);if(st.isFile()){const mode=(st.mode&0o111)?0o755:0o644;entries.push({source:rel,mode});return}for(const name of readdirSync(abs).sort())walkRoot(join(rel,name))}
	for(const root of roots)walkRoot(root)
	return entries
}
const tracked=hasGit?listTrackedFromGit():listTrackedFromCiCheckout()
if(!tracked.length)throw Error("tracked runtime closure is empty")
for(const {source,mode} of tracked){const src=join(repo,source),dst=join(plugin,source);check(src);const st=lstatSync(src);if(!st.isFile()||st.nlink!==1)throw Error(`tracked runtime entry is not a regular file: ${source}`);mkdirSync(dirname(dst),{recursive:true});cpSync(src,dst);chmodSync(dst,mode)}
function removeIgnored(path){for(const entry of readdirSync(path,{withFileTypes:true})){const full=join(path,entry.name);if(entry.name===".gitignore")rmSync(full,{force:true});else if(entry.isDirectory())removeIgnored(full)}}removeIgnored(out)
mkdirSync(join(market,".agents/plugins"),{recursive:true});writeFileSync(join(market,".agents/plugins/marketplace.json"),`${JSON.stringify({name:"ccl-skills-npm",plugins:[{name:"ccl-skills",source:{source:"local",path:"./plugins/ccl-skills"}}]},null,2)}\n`)
writeFileSync(join(market,"marketplace-manifest.json"),readFileSync(join(market,".agents/plugins/marketplace.json")))
chmodSync(join(market,".agents/plugins/marketplace.json"),0o644);chmodSync(join(market,"marketplace-manifest.json"),0o644)
const files=[];function walk(path){for(const entry of readdirSync(path,{withFileTypes:true})){const full=join(path,entry.name);if(entry.isDirectory())walk(full);else{const st=lstatSync(full),mode=st.mode&0o777;if(![0o644,0o755].includes(mode))throw Error(`unsupported runtime mode: ${relative(out,full)}`);files.push({path:relative(out,full),sha256:createHash("sha256").update(readFileSync(full)).digest("hex"),mode})}}}walk(out);files.sort((a,b)=>a.path.localeCompare(b.path))
const sourceCommit=ciCommit()??(hasGit?git(["rev-parse","HEAD"]).trim():null),sourceState=hasGit?git(["status","--porcelain","--",...roots]).trim()?"development-dirty":"clean":"clean",version=JSON.parse(readFileSync(join(pkg,"package.json"),"utf8")).version,snapshotHash=createHash("sha256").update(JSON.stringify({version,files})).digest("hex")
writeFileSync(join(out,"release.json"),`${JSON.stringify({schema:1,npmPackage:"@ccoalm/ccl-skills-codex",version,sourceCommit,sourceState,files,snapshotHash},null,2)}\n`)
