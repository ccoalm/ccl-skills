import { execFileSync } from "node:child_process"
import { createHash } from "node:crypto"
import { mkdtempSync, mkdirSync, readFileSync, renameSync, rmSync, writeFileSync } from "node:fs"
import { basename, join, resolve } from "node:path"
import { tmpdir } from "node:os"

const out=resolve(process.argv[2]||"artifacts"),pack=JSON.parse(execFileSync("npm",["pack","--json","--ignore-scripts"],{encoding:"utf8"}))[0],name=`ccl-skills-${pack.version}.tgz`,source=resolve(pack.filename),target=join(out,name)
mkdirSync(out,{recursive:true});renameSync(source,target)
const bytes=readFileSync(target),integrity=`sha512-${createHash("sha512").update(bytes).digest("base64")}`,shasum=createHash("sha1").update(bytes).digest("hex")
if(pack.integrity!==integrity||pack.shasum!==shasum)throw Error("npm pack metadata mismatch")
const extract=mkdtempSync(join(tmpdir(),"ccl-skills-pack-"));try{execFileSync("tar",["-xzf",target,"-C",extract]);execFileSync(process.execPath,[resolve("scripts/verify-packed.mjs"),join(extract,"package/dist/assets")],{stdio:"inherit"});const cli=join(extract,"package/dist/cli.js"),mode=(await import("node:fs")).statSync(cli).mode&0o777;if((mode&0o111)===0)throw Error("packed CLI is not executable")}finally{rmSync(extract,{recursive:true,force:true})}
writeFileSync(join(out,"pack-metadata.json"),`${JSON.stringify({schema:1,filename:name,version:pack.version,integrity,shasum},null,2)}\n`)
console.log(JSON.stringify({status:"artifact-packed",filename:name,integrity,shasum}))
