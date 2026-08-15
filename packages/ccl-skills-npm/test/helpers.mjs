import { cpSync, mkdtempSync, mkdirSync, readFileSync, writeFileSync } from "node:fs"
import { join } from "node:path"
import { tmpdir } from "node:os"
import { spawnSync } from "node:child_process"
import { createHash } from "node:crypto"
export function fixture(options={}){const root=mkdtempSync(join(tmpdir(),"codex-npm-test-")),bin=join(root,"bin"),home=join(root,"home"),codexHome=join(home,".codex"),state=join(root,"state"),log=join(root,"calls");mkdirSync(bin);writeFileSync(join(bin,"codex"),`#!/bin/sh
echo "$*" >> "$FAKE_LOG"
count=$(wc -l < "$FAKE_LOG" | tr -d ' ')
fail=$(printf '%s' "$FAKE_FAILURES" | tr ',' '\n' | grep "^$count:" | cut -d: -f2-)
[ -n "$fail" ] && { echo "$fail" >&2; exit 9; }
key=$(printf '%s' "$*" | sed 's/[^A-Za-z0-9]/_/g')
counter="$FAKE_STATE.count.$key"
n=0; [ -f "$counter" ] && n=$(cat "$counter"); n=$((n + 1)); printf '%s' "$n" > "$counter"
rule="$*#$n"
printf '%s' "$FAKE_COMMAND_FAILURES" | tr '|' '\n' | grep -Fx "$rule" >/dev/null && { echo "injected failure: $rule" >&2; exit 9; }
if [ "$1" = --version ]; then echo "codex-cli ${options.version||"0.133.0"}"; exit 0; fi
market=0; plugin=0; [ -f "$FAKE_STATE.market" ] && market=1; [ -f "$FAKE_STATE.plugin" ] && plugin=1
if [ "$1 $2 $3" = "plugin marketplace list" ]; then echo "MARKETPLACE         ROOT"; [ $market = 1 ] && echo "ccl-skills-npm  $(cat "$FAKE_STATE.market")"; exit ${options.listFail?1:0}; fi
if [ "$1 $2" = "plugin list" ]; then if [ $plugin = 1 ]; then echo 'Marketplace \`ccl-skills-npm\`'; echo "$(cat "$FAKE_STATE.market")/.agents/plugins/marketplace.json"; echo; fi; echo "PLUGIN STATUS VERSION PATH"; [ $plugin = 1 ] && echo "ccl-skills@ccl-skills-npm  installed, enabled  local  /tmp/plugin"; ${options.legacy?"echo 'ccl-skills@ccl-skills  installed, enabled  local  /tmp/legacy';":""} exit ${options.listFail?1:0}; fi
if [ "$1 $2 $3" = "plugin marketplace add" ]; then ${options.marketAddFail?"exit 9":`${options.mutationSentinel?'touch "$FAKE_STATE.mutation-started"; ':''}printf '%s' "$4" > "$FAKE_STATE.market"; ${options.mutationSleep?`sleep ${options.mutationSleep}; `:''}${options.mutationSentinel?'touch "$FAKE_STATE.mutation-completed"; ':''}exit 0`}; fi
if [ "$1 $2 $3" = "plugin marketplace remove" ]; then ${options.rollbackFail?"exit 8":"rm -f \"$FAKE_STATE.market\"; exit 0"}; fi
if [ "$1 $2" = "plugin add" ]; then ${options.candidateDrift?"printf drift >> \"$(cat \"$FAKE_STATE.market\")/marketplace-manifest.json\";":""} ${options.candidateSymlink?"rm -f \"$(cat \"$FAKE_STATE.market\")/marketplace-manifest.json\"; ln -s /tmp \"$(cat \"$FAKE_STATE.market\")/marketplace-manifest.json\";":""} ${options.pluginAddFail?"exit 7":"touch \"$FAKE_STATE.plugin\"; exit 0"}; fi
if [ "$1 $2" = "plugin remove" ]; then rm -f "$FAKE_STATE.plugin"; exit 0; fi
exit 2
`,{mode:0o755});const env={...process.env,HOME:home,CODEX_HOME:codexHome,PATH:`${bin}:${process.env.PATH}`,FAKE_STATE:state,FAKE_LOG:log,FAKE_FAILURES:options.failures||"",FAKE_COMMAND_FAILURES:options.commandFailures||"",CCL_SKILLS_SKIP_SELF_UPDATE:"1"};delete env.NODE_TEST_CONTEXT;return{root,home,codexHome,state,log,env}}
export function cli(f,args){const selected=args.includes("--host")?args:[...args,"--host","codex"];return spawnSync(process.execPath,[f.assets?"test/run-with-assets.mjs":"dist/cli.js",...(f.assets?[f.assets]:[]),...selected],{cwd:process.cwd(),encoding:"utf8",env:f.env})}
export function release(f,version){const assets=join(f.root,`assets-${version}`);cpSync(join(process.cwd(),"dist/assets"),assets,{recursive:true});const r=JSON.parse(readFileSync(join(assets,"release.json"),"utf8"));r.version=version;r.snapshotHash=createHash("sha256").update(JSON.stringify({version,files:r.files})).digest("hex");writeFileSync(join(assets,"release.json"),JSON.stringify(r));f.assets=assets;return assets}
