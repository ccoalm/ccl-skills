# Antigravity host support

Add Google Antigravity (the `agy` CLI, the Antigravity IDE and app) as a first-class host next to Claude Code, Codex and OpenCode: the same skills, the same session and task-entry routing, and the same runtime guards, delivered through a native Antigravity plugin.

## Charter

| Field | Answer |
| --- | --- |
| Purpose | An Antigravity user who installs this repository today gets a lossy conversion: the guards run with a payload shape they do not read and silently allow, five hook events are dropped, and the tracked `hooks/hooks.json` is deleted from the installed copy. This round makes Antigravity load the repository as a native plugin whose hooks speak the Antigravity protocol, so the edit-isolation, merge-authorization, owner-dispatch, task-entry and stop backstops behave on Antigravity as they do on the other hosts. |
| Scope | In: a native manifest; a root `hooks.json`; a protocol bridge from Antigravity hook payloads to the existing hook scripts; Antigravity transcript evidence for skill loading and edited paths; the Antigravity plugin directory in the shared-skill path exemptions; checkout and npm install paths; README, architecture and contract text. Out: changing what any existing hook decides; Antigravity marketplace listing (it needs a manifest `version`, see Decisions); shrinking skill bodies under the 24,000-byte activation cap; Windows `cmd /c` hook execution; workspace-level `.agents/plugins/` installs. No watermark applies; this is not an iterative-program source. |
| Depth | Generator/tooling change: new runtime adapter, installer paths and tests; no skill text changes. |
| Result classification | Failure. Installing the current tree into Antigravity (scratch `HOME`) converts it as a Claude extension; the converted edit-isolation hook receives an Antigravity payload, prints nothing and exits 0 on an edit that the same script denies when given a Claude payload (Baseline below). |
| Matching analysis | Contributing factors: (1) no native manifest, so `agy plugin install` takes the Claude-extension conversion path; (2) the conversion maps matchers but not payloads, so every guard reads empty `tool_name`/`tool_input` and allows; (3) the conversion drops events Antigravity does not have (`UserPromptSubmit`, `SubagentStart`, `SubagentStop`, `PreCompact`, `PostCompact`), so task entry and merge-authorization arming never run; (4) Antigravity's stdout contract (`decision`, `injectSteps`) differs from the Claude contract the scripts emit; (5) no test pins the host binding set, so a new host can ship with guards silently inactive. Prevention: a native manifest so conversion never runs, one bridge that owns both directions of the protocol, a binding inventory tested one-to-one against `hooks/hooks.json` (the control OpenCode already uses), and a paired differential matrix (same scenario through the Claude payload and through the bridge must reach the same decision). |
| Failure mode | A weak port would copy the prototype's fail-open catch-all (any bridge exception allows the tool), count any partial `read_file` of a `SKILL.md` as a full skill load, replace a user's existing `~/.gemini/config/plugins/ccl-skills` directory on install, or pass Claude-only output shapes through, which Antigravity rejects. |
| Lifecycle impact | Implementation and debugging on Antigravity (guards and routing now fire); testing (new unit, contract and host-smoke layers); launch and onboarding (README install table, npm `--host antigravity`); use without source access (npm install path). Product intent and design/UX: no change. |
| Evidence plan | Primary sources, read locally and kept out of the repository: Antigravity's bundled customization guide (plugins, hooks, skills, JSON configs), `agy plugin --help`, `agy plugin validate --help`, `agy --help`; the `agy` binary's tool-schema strings for tool and argument names; local Antigravity CLI transcripts for step and result shapes. Repository sources: `hooks/hooks.json`, the OpenCode adapter and its binding test, `hooks/host-input.py`, the stop and guard scripts, the npm package's Claude adapter and asset builder. A previously working local prototype is a hypothesis-grade input: every behavior it encodes is re-derived against the primary sources and re-tested. |
| Completion standard | `agy plugin validate` reports 0 errors on the tree and on the packed npm asset; the bridge's binding inventory equals `hooks/hooks.json`; the differential matrix passes; a real `agy -p` smoke run with the candidate shows the session bootstrap, a denied primary-checkout edit and a Stop pass; `make test`, the npm package tests and `check-public-sanitization.py` pass on the exact candidate; extraction review and challenge run, plus a delta pass for later changes. |

## Baseline (RED)

Recorded in `evidence/validation.md` with the commands.

| Probe | Without this change | Expected with it |
| --- | --- | --- |
| `agy plugin validate .` | 1 error: no `plugin.json` at the root, `.antigravity-plugin` or `.gemini-plugin` | 0 errors |
| `agy plugin install <tree>` (scratch `HOME`) | Converted as a Claude extension: `hooks/hooks.json` removed from the copy; `UserPromptSubmit`, `SubagentStart`, `SubagentStop`, `PreCompact`, `PostCompact` skipped | Native install, byte-identical copy, `source: antigravity` |
| Converted `guard-edit-isolation.sh` given an Antigravity `PreToolUse` payload for a write into a `.worktree-only` primary checkout | empty stdout, exit 0 (allow) | `{"decision":"deny",…}` |
| Control: the same script given the equivalent Claude payload | deny | deny (unchanged) |

## Decisions

| Decision | Choice | Rejected alternative and why |
| --- | --- | --- |
| Manifest location | `.antigravity-plugin/plugin.json` | Root `plugin.json`: a root file named `plugin.json` is easy to confuse with the Claude and Codex manifests and offers nothing extra. |
| Manifest `version` | Omitted, like the Claude and Codex manifests | Adding one: it is needed only for Antigravity marketplace listing, which this round does not do, and a second hand-maintained version site would drift from the npm version. `agy plugin validate` reports a warning, not an error. |
| Hook file | Root `hooks.json` in Antigravity's grouped format, every handler running `python3 -I ./hooks/agy-bridge.py <Event>` | Converting `hooks/hooks.json` at install time: that is the lossy path this round removes. Claude and Codex keep reading `hooks/hooks.json`; Antigravity reads only the root file, so the two never collide. |
| Bridge language | Python 3, standard library only | Node: the hook runtime already needs `python3` for `host-input.py` and `skill-loading.py`, so Python adds no new dependency. |
| Binding source of truth | The bridge's dispatch lists, with per-script failure policy; `--bindings` prints the inventory derived from them, tested one-to-one against `hooks/hooks.json` (both in `hooks/` and in the npm package) | Deriving bindings from `hooks/hooks.json` at run time: matchers would map, but the failure policy (fail-closed vs advisory) is per script and has to be written down anyway; OpenCode uses the same inventory-plus-test control. |
| Failure policy | Edit isolation, owner dispatch and delegation guards fail closed (a guard that cannot run denies), as in the OpenCode adapter. A merge-authorization guard that cannot run blocks every command, stricter than OpenCode's landing-pattern check, because shell text cannot be classified reliably (quoting, encoding and indirection hide a subcommand). The broad-test guard and the reminders fail open; a bridge exception in `PreToolUse` denies | The prototype's catch-all allow: it turns any bridge bug into a silent bypass of every guard. |
| Events Antigravity lacks | `UserPromptSubmit` → first `PreInvocation` of each user turn (task entry and merge-authorization arming); `SubagentStart` → `PreToolUse` on `invoke_subagent`, prepending the context to `Prompt` through `overwrite`; `PreCompact`/`PostCompact`/`SubagentStop` → recorded as `unsupported` in the inventory | Dropping them silently, as the conversion does. |
| Advisory context | `PreToolUse`/`PostToolUse` `additionalContext` is queued and delivered as a `systemMessage` at the next `PreInvocation` | Returning it in `reason`: Antigravity shows `reason` but does not add it to the model context on allow. |
| Skill-load evidence | A `read_file` of a skill's `SKILL.md` counts only when the file is byte-identical to the bundled skill, each result is `DONE` and unambiguously paired with its call, and the results' numbered lines cover and match every line | The prototype's "any `read_file` of `SKILL.md` is a load": a 20-line read of a 300-line skill would pass the checkpoint that exists to require a full read. |
| Shadow transcript | Rebuilt for each event in a private per-user directory (0700, files 0600) at one stable path per conversation, so hook state keyed on that path stays stable; a per-conversation lock holds it steady while the hooks read it, and it is deleted when the event ends. User prompt text and tool output are not copied; commands, delegated prompts and assistant prose are, because the guards and stop hooks read them | Copying the full Antigravity transcript: a second, longer-lived copy of user content with no consumer. |
| Install ownership | Ownership means the installed directory still matches the inventory its installer recorded. The checkout installer stages verified tracked files and writes a marker with every file's hash; npm writes an install receipt (version and file hashes) under `~/.gemini/ccl-skills-npm/` and installs from the package's bundled plugin, keeping a verified temporary backup only for update rollback. Both take one shared lock and refuse a plugin they did not install or that changed after install | Plain `agy plugin install`: it replaces the whole directory, including a user's own clone with local edits. |

## Security four questions

Applies: the bridge decides allow/deny for edits, merges and delegation.

1. Caller-controllable inputs: every field of the hook stdin (`conversationId`, `cwd`, `workspacePaths`, `transcriptPath`, `toolCall.args`, `lastUserInput`), and the transcript file contents the model's tools produced.
2. Blast radius if forged: an attacker who controls stdin already controls the host process, so the bridge does not defend against the host. What it must not do is turn malformed or hostile *content* into a pass: an unparsable payload, an unknown argument shape, a missing target path or an oversized transcript must not reach "allow" for a guarded tool; a forged transcript line must not count as a skill load; `conversationId` must not become a path traversal.
3. Trust roots: policy decisions come from the existing hook scripts; the bridge owns only protocol errors, failure defaults and verdict aggregation. Skill-load evidence trusts the integrity of the host's transcript; the byte comparison rejects incomplete or mismatched reads, not a forged transcript. `conversationId` reaches the file system only through a SHA-256 digest or a strict token pattern.
4. Negative cases in the test register: unknown edit-tool argument shape → deny; bridge exception on a guarded tool → deny; partial skill read → no evidence; mismatched skill bytes → no evidence; `conversationId` containing `../` → hashed; FIFO or oversized `transcriptPath` → no read, no hang.

## Risk inventory (`feature-risk-router`)

| Tag | Applies | Gate |
| --- | --- | --- |
| `shared-gate` | yes: the bridge decides whether the shared guards fire on a new host | binding inventory test, differential matrix, extraction review and challenge |
| `security-review` | yes, change-triggered: new untrusted-input surface (hook stdin, transcript parsing) and authorization mapping | `security-first-pass-only` triage recorded in validation; no dedicated security owner is available |
| `permission-access` | yes: edit isolation and merge authorization semantics on a new host | negative cases above; parity with the Claude path |
| `external-integration` | yes: the `agy` CLI | fake-CLI tests in the npm package plus a real `agy -p` smoke |
| `write-finality` | yes: install replaces `~/.gemini/config/plugins/ccl-skills` | must-not-touch cases (unowned directory kept) with an applied mutation of the ownership predicate |
| `release-ops` | no: no version bump, tag or publish in this round | — |
| `api-contract`, `money-quota`, `data-migration`, `ai-output`, `ai-action`, `visible-ui` | no | — |

Stop reasons: none. All verification uses scratch `HOME` directories and synthetic repositories.

## Implementation boundary record

| Field | Value |
| --- | --- |
| Baseline | This plan, on branch `ccoalm/antigravity-host-support` (active delivery branch, unmerged) |
| Scope | Files in the target-output map below |
| Implementation owners | `python-service-dev` (bridge, tests), `nodejs-service-dev` + `typescript-dev` (npm adapter), loaded in this session; shell installer follows repository conventions; shared-skill gates follow `skill-extraction-workflow` (loaded) |
| Delegation | `local`: the bridge, the installers and the npm adapter share one contract (manifest layout, root `hooks.json`, bridge flags) and are designed together; no slice is independent |
| Visible UI | `visible surface: no` (CLI hook runtime and installers) |
| Risk inventory | Above |
| Test-case-first | Register below. T12 ran red before its patch; for T1–T11 the RED is the base tree having no Antigravity handler at all, since the suite was written after the first bridge draft (`evidence/validation.md`) |

## Test-case register

| ID | Scenario | Layer | Command | Expected before |
| --- | --- | --- | --- | --- |
| T1 | Bridge binding inventory equals every command hook in `hooks/hooks.json` | unit | `python3 hooks/test_agy_bridge.py` | fail (no bridge) |
| T2 | Write/edit/patch into a `.worktree-only` primary checkout via the bridge → `deny`; same file from a linked worktree → `allow`; differential against the Claude payload | integration (real hook scripts, synthetic git repos) | same | fail |
| T3 | Edit tool with no extractable path → `deny`; bridge exception on a guarded tool → `deny` | unit | same | fail |
| T4 | Possible landing command when the merge guard cannot run → `deny`; ordinary command → `allow` | unit | same | fail |
| T5 | `SessionStart` → `injectSteps[0].systemMessage.systemMessage` carries the bootstrap; every handler's stdout parses as one JSON object of the event's documented shape | contract | same | fail |
| T6 | `PreInvocation` runs task entry once per user turn, not on each model call | unit | same | fail |
| T7 | Advisory context from `PreToolUse`/`PostToolUse` is delivered once at the next `PreInvocation`; `PostToolUse` prints `{}` | unit | same | fail |
| T8 | `Stop`: `continuationActive` or a non-`NO_TOOL_CALL` reason → `allow`; a blocking stop hook → `continue` with its reason | unit | same | fail |
| T9 | Skill evidence only for full, byte-matching coverage; partial read, mismatched copy or forged result lines → none | unit | same | fail |
| T10 | `invoke_subagent` is denied until the delegation owner is loaded, then gets delegation and subagent context prepended through `overwrite.Prompt` | integration (real hook scripts) | same | fail |
| T11 | `conversationId` with `../`, FIFO `transcriptPath`, oversized transcript → no traversal, no hang, bounded read | unit | same | fail |
| T12 | `/.gemini/config/plugins/` path is exempt from the shared-skill edit scope, like `/plugins/cache/` | unit (both scope guards, ordinary-checkout control) | `python3 hooks/test_agy_bridge.py` (`ScopeExemptionTests`) | fail |
| T13 | npm: binding inventory reported by the bridge equals `hooks/hooks.json` | contract | `npm --prefix packages/ccl-skills-npm test` | fail |
| T14 | npm `--host antigravity` with a fake `agy`: install, doctor, update, downgrade, uninstall; unowned plugin or root refused and left untouched; rollback after a host change; journal reconciliation; disabled plugin reported | integration (fake CLI) | same | fail |
| T15 | Packed asset contains the native manifest, root `hooks.json` and bridge, and passes `agy plugin validate` with 0 errors | package | `npm … run test:pack`; `agy plugin validate` | fail |
| T16 | Checkout installer: stages verified tracked files only, refuses an unmarked existing plugin or a renamed manifest, replaces a marked one, detects a host that did not replace the tree | integration (fake `agy`) | `bash scripts/test_install_antigravity.sh` | fail |
| T17 | Real host: `agy -p` with the candidate shows the bootstrap, denies a primary-checkout write, and passes Stop | E2E host smoke | recorded in `evidence/validation.md` | n/a (manual, live) |

## Target-output map

| Owner / file | Direction | Status | Change or reason |
| --- | --- | --- | --- |
| `.antigravity-plugin/plugin.json`, `hooks.json` | new host surface | updated | native manifest and Antigravity hook file |
| `hooks/agy-bridge.py`, `hooks/test_agy_bridge.py` | runtime | updated | protocol bridge and its tests |
| `hooks/skill-loading.py`, `hooks/skill-extraction-gate-stop.sh` and their tests | runtime | updated | Antigravity plugin directory exempt from shared-skill edit scope |
| `hooks/AGENTS.md` | contract | updated | bridge and root `hooks.json` contract |
| `AGENTS.md` (Host 配置) | contract | updated | manifest `version` rule covers the Antigravity manifest |
| `scripts/install.sh`, `scripts/install-antigravity.sh`, test, `Makefile` | install | updated | checkout install/update |
| `packages/ccl-skills-npm` (adapter, CLI, unified dispatch, asset roots, packed-file check, tests, README) | install | updated | `--host antigravity` |
| `README.md`, `docs/ARCHITECTURE.md`, `docs/CONTRIBUTING.md` | docs | updated | host table, layout, verification |
| `packages/opencode-plugin` | sibling adapter | unchanged | no behavior change; it remains the parity reference |
| `agent-context/*` | routing | unchanged | host-neutral; delivered by the bridge |
| `skills/**` | skills | unchanged | no skill text change; the 24,000-byte activation cap is a known limitation (README) |
| `product-rd-workflow`, `testing-strategy`, `code-review` | process owners | unchanged | applied as written |
| `.github/workflows/ci.yml` | CI | unchanged | the new tests run inside the existing `make test` and npm jobs |

## Residual risk

- `agy plugin validate` warnings remain: missing `version` (marketplace listing), root `AGENTS.md` and `hooks/hooks.json` "never loaded" (intended: they serve other hosts), and 18 skill bodies above the 24,000-byte activation cap. Agents still read the full `SKILL.md` through `read_file`, which is what the skill-load evidence counts.
- `send_command_input` can type into a running shell; no host exposes that to the merge guard today.
- Antigravity has no compaction or subagent-stop event, so those two backstops do not run there.
