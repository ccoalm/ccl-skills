import { existsSync, readFileSync } from "node:fs"
import { join } from "node:path"
import { run } from "../dist/operations.js"
import { fixture, release } from "./helpers.mjs"

export function fault(code="EIO") { return Object.assign(new Error(`injected ${code}`), { code }) }
export function injected(name, occurrence=1, code="EIO") {
  let seen=0
  return { fault(operation) { if(operation===name&&++seen===occurrence) throw fault(code) } }
}
export function invoke(f,command,options={},context={}) {
  const prior={HOME:process.env.HOME,CODEX_HOME:process.env.CODEX_HOME,PATH:process.env.PATH,FAKE_STATE:process.env.FAKE_STATE,FAKE_LOG:process.env.FAKE_LOG,FAKE_FAILURES:process.env.FAKE_FAILURES,FAKE_COMMAND_FAILURES:process.env.FAKE_COMMAND_FAILURES}
  Object.assign(process.env,f.env)
  const normalized=typeof context.fault==="function"?{fs:context}:context
  try{return run(command,options,{assets:f.assets,...normalized})}finally{for(const [key,value] of Object.entries(prior))value===undefined?delete process.env[key]:process.env[key]=value}
}
export function installed(version="1.0.0") { const f=fixture();release(f,version);const result=invoke(f,"install");if(result.code!==3)throw Error(JSON.stringify(result));return f }
export function root(f){return join(f.codexHome,"ccl-skills-npm")}
export function manifest(f){return JSON.parse(readFileSync(join(root(f),"install-manifest.json"),"utf8"))}
export function journal(f){return JSON.parse(readFileSync(join(root(f),"operation-journal.json"),"utf8"))}
export function publicSource(f){return existsSync(`${f.state}.market`)?readFileSync(`${f.state}.market`,"utf8"):null}
export { release }
