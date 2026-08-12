import { createHash } from "node:crypto"
import { lstatSync, readFileSync, readdirSync } from "node:fs"
import { dirname, join, relative, resolve } from "node:path"
import { fileURLToPath } from "node:url"
const root=resolve(process.argv[2]||dirname(fileURLToPath(import.meta.url)),process.argv[2]?"":"../dist/assets"),release=JSON.parse(readFileSync(join(root,"release.json"),"utf8")),fail=m=>{throw new Error(m)}
if(release.schema!==1||release.npmPackage!=="@ccoalm/ccl-skills-codex"||!/^[0-9a-f]{40}$/.test(release.sourceCommit))fail("invalid release metadata")
if(process.env.REQUIRE_CLEAN_RELEASE==="1"&&release.sourceState!=="clean")fail("release source is not clean")
if(process.env.EXPECT_SOURCE_COMMIT&&release.sourceCommit!==process.env.EXPECT_SOURCE_COMMIT)fail("release source commit mismatch")
const files=[];function walk(p){for(const e of readdirSync(p,{withFileTypes:true})){const q=join(p,e.name),rel=relative(root,q);if(rel==="release.json")continue;const st=lstatSync(q);if(st.isSymbolicLink()||(!st.isDirectory()&&!st.isFile()))fail(`unsafe packed entry: ${rel}`);if(st.isDirectory())walk(q);else files.push({path:rel,sha256:createHash("sha256").update(readFileSync(q)).digest("hex"),mode:st.mode&0o777})}}walk(root);files.sort((a,b)=>a.path.localeCompare(b.path))
if(JSON.stringify(files)!==JSON.stringify(release.files))fail("packed file set/hash/mode mismatch")
if(createHash("sha256").update(JSON.stringify({version:release.version,files})).digest("hex")!==release.snapshotHash)fail("snapshot hash mismatch")
const required=["marketplace/.agents/plugins/marketplace.json","marketplace/plugins/ccl-skills/.codex-plugin/plugin.json","marketplace/plugins/ccl-skills/agent-context/session-start.md","marketplace/plugins/ccl-skills/.worktree-only","marketplace/plugins/ccl-skills/hooks/hooks.json","marketplace/plugins/ccl-skills/scripts/owner-dispatch/owner-dispatch.sh"]
for(const p of required)if(!files.some(f=>f.path===p))fail(`missing runtime closure: ${p}`)
const marketplace=JSON.parse(readFileSync(join(root,required[0]),"utf8"));if(marketplace.name!=="ccl-skills-npm"||marketplace.plugins?.[0]?.source?.path!=="./plugins/ccl-skills")fail("marketplace target mismatch")
const plugin=JSON.parse(readFileSync(join(root,required[1]),"utf8"));if(Object.hasOwn(plugin,"version"))fail("plugin.json must not contain version")
console.log(JSON.stringify({status:"packed-verified",files:files.length,snapshotHash:release.snapshotHash,sourceState:release.sourceState}))
