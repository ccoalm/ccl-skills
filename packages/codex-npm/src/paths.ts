import { dirname, join, resolve } from "node:path"
import { fileURLToPath } from "node:url"
export const PACKAGE="@ccoalm/ccl-skills-codex", MARKET="ccl-skills-npm", REF="ccl-skills@ccl-skills-npm", LEGACY_REF="ccl-skills@ccl-skills"
import type { FsDependencies } from "./fs-safe.js"
export type InterruptionCheckpoint="before-first-mutation"|"after-old-plugin-remove"|"after-old-marketplace-remove"|"after-candidate-marketplace-add"|"after-candidate-plugin-add"|"after-public-verify-before-manifest"|"after-manifest-commit"|"after-uninstall-plugin-remove"|"after-uninstall-marketplace-remove"|"after-uninstall-public-absent-commit"
export type PathContext={assets?:string;fs?:Partial<FsDependencies>;isInterrupted?:(checkpoint?:InterruptionCheckpoint)=>boolean;checkpoint?:(name:InterruptionCheckpoint)=>boolean}
export function paths(context:PathContext={}){const home=process.env.HOME||"",codexHome=resolve(process.env.CODEX_HOME||join(home,".codex")),root=join(codexHome,"ccl-skills-npm"),assets=resolve(context.assets||join(dirname(fileURLToPath(import.meta.url)),"assets"));return{home,codexHome,root,snapshots:join(root,"snapshots"),manifest:join(root,"install-manifest.json"),journal:join(root,"operation-journal.json"),lock:`${root}.lock`,assets,release:join(assets,"release.json")}}
