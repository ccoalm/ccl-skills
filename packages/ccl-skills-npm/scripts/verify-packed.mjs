import { createHash } from "node:crypto"
import { lstatSync, readFileSync, readdirSync } from "node:fs"
import { dirname, join, relative, resolve } from "node:path"
import { fileURLToPath } from "node:url"
const root=resolve(process.argv[2]||dirname(fileURLToPath(import.meta.url)),process.argv[2]?"":"../dist/assets"),release=JSON.parse(readFileSync(join(root,"release.json"),"utf8")),fail=m=>{throw new Error(m)}
if(release.schema!==1||release.npmPackage!=="@ccoalm/ccl-skills"||!/^[0-9a-f]{40}$/.test(release.sourceCommit))fail("invalid release metadata")
if(process.env.REQUIRE_CLEAN_RELEASE==="1"&&release.sourceState!=="clean")fail("release source is not clean")
if(process.env.EXPECT_SOURCE_COMMIT&&release.sourceCommit!==process.env.EXPECT_SOURCE_COMMIT)fail("release source commit mismatch")
const files=[];function walk(p){for(const e of readdirSync(p,{withFileTypes:true})){const q=join(p,e.name),rel=relative(root,q);if(rel==="release.json")continue;const st=lstatSync(q);if(st.isSymbolicLink()||(!st.isDirectory()&&!st.isFile()))fail(`unsafe packed entry: ${rel}`);if(st.isDirectory())walk(q);else files.push({path:rel,sha256:createHash("sha256").update(readFileSync(q)).digest("hex"),mode:st.mode&0o777})}}walk(root);files.sort((a,b)=>a.path.localeCompare(b.path))
if(JSON.stringify(files)!==JSON.stringify(release.files))fail("packed file set/hash/mode mismatch")
const dist=dirname(root),runtime=[];function walkRuntime(p){for(const e of readdirSync(p,{withFileTypes:true})){const q=join(p,e.name);if(q===root)continue;const rel=relative(dist,q),st=lstatSync(q);if(st.isSymbolicLink()||(!st.isDirectory()&&!st.isFile()))fail(`unsafe packed runtime: ${rel}`);if(st.isDirectory())walkRuntime(q);else runtime.push({path:rel,sha256:createHash("sha256").update(readFileSync(q)).digest("hex"),mode:st.mode&0o777})}}walkRuntime(dist);runtime.sort((a,b)=>a.path.localeCompare(b.path));if(JSON.stringify(runtime)!==JSON.stringify(release.runtime))fail("packed runtime file set/hash/mode mismatch")
if(createHash("sha256").update(JSON.stringify({version:release.version,files})).digest("hex")!==release.snapshotHash)fail("snapshot hash mismatch")
const required=["marketplace/.agents/plugins/marketplace.json","marketplace/.claude-plugin/marketplace.json","marketplace/plugins/ccl-skills/.claude-plugin/plugin.json","marketplace/plugins/ccl-skills/.codex-plugin/plugin.json","marketplace/plugins/ccl-skills/agent-context/session-start.md","marketplace/plugins/ccl-skills/agent-context/subagent-start.md","marketplace/plugins/ccl-skills/.worktree-only","marketplace/plugins/ccl-skills/hooks/hooks.json","marketplace/plugins/ccl-skills/packages/opencode-plugin/ccl-skills.ts","marketplace/plugins/ccl-skills/scripts/owner-dispatch/owner-dispatch.sh","marketplace/plugins/ccl-skills/skills/code-review/scripts/normalize_review_timeout.sh","marketplace/plugins/ccl-skills/skills/code-review/scripts/update_review_plan_intent.py"]
for(const p of required)if(!files.some(f=>f.path===p))fail(`missing runtime closure: ${p}`)
const marketplace=JSON.parse(readFileSync(join(root,required[0]),"utf8"));if(marketplace.name!=="ccl-skills-npm"||marketplace.plugins?.[0]?.source?.path!=="./plugins/ccl-skills")fail("marketplace target mismatch")
const claudeMarketplace=JSON.parse(readFileSync(join(root,required[1]),"utf8"));if(claudeMarketplace.name!=="ccl-skills-npm"||claudeMarketplace.plugins?.[0]?.source!=="./plugins/ccl-skills")fail("Claude marketplace target mismatch")
// Version authority is package.json -> release.json, and nothing else. A `version` in
// plugin.json would be a second authority AND would change host behaviour: Claude Code
// resolves a plugin's version from plugin.json first and, once set, "the plugin is pinned
// to this string and users only receive updates when it changes" - so a pointer that drifts
// from package.json silently freezes updates for anyone installing through the marketplace,
// while `ccl-skills update` kept working. Omitting it leaves this plugin on resolution step 5
// ("unknown, for npm sources or local directories not inside a git repository"), which is
// correct here: updates are owned by the CLI's own release.json/snapshotHash comparison.
//   source:   docs.claude.com/en/docs/claude-code/plugins-reference, "Version management"
//             (resolution order) + plugin-marketplaces, marketplace entry `version` field.
//   verified: 2026-09-01, against those pages as published that day and against Claude
//             Code 2.1.235 locally. Upstream does not version its docs, so the revision
//             is pinned by date; the pages date their own behaviour changes inline
//             ("Before v2.1.222 ...", "Before v2.1.239 ..."), which is how a later
//             reader can tell whether the contract moved under this annotation.
//   invalidated by: a Claude Code release whose notes touch plugin version resolution or
//             marketplace entry fields (re-read both pages and re-date this block); this
//             package distributing through a git-hosted marketplace or the `/plugin
//             update` path instead of the CLI; or the resolution order changing. Each
//             makes an absent version the wrong default, not merely a redundant one.
// Both host manifests are checked. The ban previously read only required[3] (the Codex one),
// leaving the Claude manifest - the one the resolution order above makes load-bearing -
// unguarded; both happened to be clean, so nothing had surfaced it.
for(const manifest of [required[2],required[3]]){const plugin=JSON.parse(readFileSync(join(root,manifest),"utf8"));if(Object.hasOwn(plugin,"version"))fail(`${manifest} must not contain version`)}
console.log(JSON.stringify({status:"packed-verified",files:files.length,snapshotHash:release.snapshotHash,sourceState:release.sourceState}))
