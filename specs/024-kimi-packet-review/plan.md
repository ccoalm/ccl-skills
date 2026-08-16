# 024 — Make Kimi and OpenCode formal review lanes usable and classify Claude failures

## Artifact classification and entry state

- Artifact: `gate implementation` under the shared-gate classification.
- Baseline: local `dev@8cea35e` in an isolated feature worktree after rebasing
  the authorized checkpoint commit.
- Risk tags: `shared-gate`, `external-integration`, and change-triggered `security-review` because the wrapper controls model egress and reviewer tool access.
- Visible surface: no.
- Landing scope: local implementation, verification, commit, and merge into
  local `dev`. Push, release, install, and cleanup remain unauthorized.

## Problem and scope

The selected Kimi model/API can return valid review and challenge verdicts, but
the formal wrapper previously rejected a composed prompt above its 16 KiB inline
ceiling before inference. The wrapper also silently reduced a controller-granted
timeout to 120 seconds. Both defects are now fixed. A separate Kimi CLI startup
may fail with a host file watcher `EMFILE`; that is a CLI/runtime failure and
must not be reported as an OAuth or model failure.

OpenCode had several independent wrapper/runtime defects: its boundary probe silently
reduced the granted timeout to 30 seconds, a completed exported verdict was
discarded when the process tail timed out, and its packet-only agent could spend
the lane budget loading unrelated skills and exploring the workspace. Those
paths are now bounded and covered by regression tests. Kimi and OpenCode both
produce formal passed verdicts on the same small real diff. The complete current
candidate exposed two further boundary failures after the checkpoint: OpenCode
returned a structured provider HTTP 402 billing error that the wrapper lost
because it inspected only stderr. Its first structured-event classifier could
also lose an earlier 401/402/429 when a later event had another status. Kimi
cannot place an over-inline,
template-bearing packet in either argv or an agent template. This continuation adds
exact classifications and a controller-owned, single-packet read channel; it
does not claim that large-candidate review is complete until a new
exact-candidate verdict exists.

Claude has two independent states. An earlier live call reached the provider
and correctly classified the weekly limit as fallback-eligible `quota`; later
calls after quota became available produced formal review verdicts.
Separately, Claude Code 2.1.233 added built-in commands and
`terminal_slash_commands`; the static runtime snapshot rejected a synthetic
successful owner-aware stream before it could produce a formal verdict. The
wrapper now binds host vocabulary to a same-executable, same-version, no-plugin
baseline instead of requiring a repository update for each built-in name.

In scope:

- reproduce the current packet construction and size decision;
- use Kimi's explicit agent-file input only to install a packet-reader agent,
  without embedding candidate bytes at system-prompt authority;
- for every large packet, expose only one controller-owned stdio
  MCP tool whose schema has no path parameter and whose server is bound to the
  frozen packet path and SHA-256;
- preserve exact candidate bytes when Kimi agent-template variables occur;
- reproduce and isolate the Kimi formal timeout after successful packet delivery;
- reproduce and isolate OpenCode's native-skill stream timeout, including the
  boundary between inference completion, event parsing, and result export;
- classify structured OpenCode provider errors from its event stream when
  stderr is empty, including HTTP 402/429 quota or billing exhaustion;
- make both wrappers honor one bounded controller budget and return a valid
  formal verdict when their client has already produced sufficient evidence;
- repair Claude owner-aware runtime validation without accepting tools,
  plugins, MCP, permission drift, or unreviewed schema changes;
- preserve the distinction between Claude provider quota and wrapper failure;
- add failing-first wrapper/gate tests and synchronize the stable contract.

Out of scope:

- raw API output as a substitute for a formal wrapper receipt;
- automatic model/provider selection or changes to user credentials;
- weakening fail-closed parsing, packet hashing, egress scanning, same-family
  exclusion, or review/challenge separation;
- fixing Kimi's host file-watcher implementation, changing a Claude account's
  quota, accepting arbitrary future Claude protocol changes, or unrelated Codex
  authentication/model-family behavior.

## RCA

| Factor | Evidence state | Counterfactual | Control target |
| --- | --- | --- | --- |
| Kimi formal prompt included the complete packet inline and rejected over 16 KiB before invocation | RED baseline reproduced; deterministic and live GREEN complete | a pathless, hash-bound packet reader lets the same frozen packet reach inference without argv or system-prompt exposure | Kimi transport contract, parser receipt, wrapper regression, and live formal pass |
| Current docs require caller-level partitioning but the gate has no executable partition support | source-confirmed | manual skill text cannot make the ordinary wrapper usable for agents that call one gate command | wrapper-owned executable path or a precise terminal result if no safe path exists |
| CLI host resource failures are easy to conflate with model/provider health | prior recorded observation; not reproduced in current live runs; exact fixtures GREEN | structured layer classification prevents a local `EMFILE` from becoming an auth/model verdict | wrapper result fields and probe/formal fixtures |
| Existing oversize fixture asserted only the rejection | RED baseline recorded and replaced | the suite now fails unless a large packet reaches the stubbed formal client through the pathless MCP | agent marker, exact tool frontmatter, and no-packet-in-prompt assertions |
| Kimi truncated every formal invocation to 120 seconds, while removing the cap also lengthened inline argv exposure | source-confirmed plus exact-candidate finding; split timeout regressions GREEN | the bounded capability probe is charged against one granted lane budget; MCP review may consume the remainder up to 600 seconds, while inline review retains a 120-second exposure cap | delivery-specific timeout forwarding, probe-accounting, and forced-kill regressions |
| OpenCode discarded a complete verdict solely because `opencode run` timed out, while export-only recovery could accept a partial run | RED fixtures and parser regression GREEN | both the event stream's terminal event and the bound export must prove `step-finish: stop`, and a profile-bound recovery must include the exact frozen set of required concern conclusions; export-only, incomplete-contract, and legacy no-profile completion remain timeout | OpenCode event/export parser, required-concern binding, and `transport_tail_timeout` receipt |
| OpenCode treated a timed-out run with an idless or invalid export as a terminal parser failure | RED fixtures and retry regression GREEN | an incomplete export remains a fallback-eligible timeout, while an explicit different-session export remains terminal | OpenCode timeout finality and session binding |
| OpenCode's boundary probe used a brittle 30-second cap, while removing the cap entirely let a hung local probe consume a long lane | RED timeout-argument fixtures and GREEN | the probe may use up to 60 seconds, its elapsed time is charged against later calls, and each model run reserves 3–10 seconds for the export needed to prove timeout-tail completion | bounded boundary timeout, remaining-budget forwarding, and timeout-tail recovery fixtures |
| OpenCode's packet-only agent could load arbitrary skills and inspect the workspace | live diagnostic showed skill, invalid/bash, glob, grep, and read attempts; post-fix live trace no longer loops through tools | wildcard-deny every capability and allow only controller-selected review skills | generated agent permissions, resolved-surface check, parser check, and regressions |
| OpenCode returned HTTP 402 `Insufficient Balance` in a structured error event while stderr was empty, and an early provider error could be hidden by a later event | exact-candidate private diagnostic replay; RED single-event and multi-event fixtures recorded | classifying every event in the bounded stream preserves authentication, billing, and quota semantics and lets the controller continue fallback | structured-event classifier and wrapper regression |
| Kimi agent files template-expand `${NAME}` placeholders, builtin `Read` can access arbitrary absolute paths, and revealing the packet receipt in the user prompt bypasses the agent-file tail check | official Kimi config/MCP/tool source plus exact-candidate reviews and RED fixtures | a generated stdio MCP server with no path argument can return only exact byte chunks of the one hash-bound packet; non-inline prompts do not reveal the tail receipt | server unit tests, generated config/agent assertions, prompt receipt assertions, parser coverage, and live exact-candidate attempt |
| Kimi interpolated controller-selected skill names into its generated agent without independently enforcing the package-name grammar, and its parser repeated the server's chunk-size literal | exact-candidate review plus instruction-shaped name fixture and shared-constant check | reject non-package-shaped skill names before inference and import the MCP server's single chunk-size constant in the parser | wrapper name-boundary regression and parser/server shared constant |
| Embedding a template-free candidate in the explicit agent body promoted untrusted diff bytes to system-prompt authority | exact-candidate independent review plus RED transport fixture | every over-inline packet stays in the private packet file and reaches the model only through the pathless reader | wrapper transport regression and exact-candidate rebind |
| MCP delivery skipped the cooperative forbidden-tool probe before exposing a large candidate | exact-candidate adversarial challenge plus wrapper coverage | run the same Read/Glob/Grep canary in both delivery modes before the formal packet send | capability-probe fixtures and exact-candidate rebind |
| OpenCode zero-owner agents deny every skill name, but the boundary and parser did not consistently enforce `skill=false` | exact-candidate findings independently verified in source; RED fixtures recorded | require `skill` only when the controller selected owner skills and reject it otherwise | resolved-boundary fixture, parser flag fixture, and legacy zero-owner wrapper regression |
| The original MCP line pager could not safely carry a physical line above its 48 KiB result bound | exact-candidate Kimi challenge plus RED server/wrapper fixtures | return UTF-8-safe byte chunks with explicit ranges and require the parser to match every chunk against frozen packet bytes | server chunk test, wrapper long-line fixture, and exact-candidate rebind |
| A reviewer that read the full packet and then requested the exact end offset was stopped as a tool-boundary breach, while the byte-equality and contiguous-coverage checks lacked negative integration fixtures | exact-end, altered-body, and gapped-range RED fixtures; focused GREEN | return one bound empty chunk at exact EOF only, continue rejecting offsets beyond EOF, and require every non-empty chunk to match and cover the frozen bytes contiguously | server, parser, and wrapper regressions |
| Claude small-diff review returned a weekly quota response | current live probe, correctly normalized to `reason_code=quota` and fallback-eligible | no local code change can create provider quota; the lane must preserve the external failure class and continue fallback when another family is available | existing Claude envelope classification and controller cascade |
| Claude Code 2.1.233 added host commands and `terminal_slash_commands`; a synthetic successful owner-aware stream was rejected by the static snapshot, while trusting every baseline skill could launder a leaked user capability and the compatibility baseline could extend the caller's deadline by 30 seconds | live init capture plus deterministic RED replay, baseline-only skill refusal, and delayed-baseline timeout fixture | obtain command vocabulary from the same resolved binary under no-tool, no-plugin safe mode, require the formal init to match its CLI version, never use baseline skills as formal authority, and deduct baseline plus validation elapsed time from the formal timeout | wrapper baseline probe, parser checks, policy matrix, timeout accounting, and end-to-end fixtures |

## Acceptance decision table

| Input / observed state | Required verdict | Required evidence |
| --- | --- | --- |
| packet within inline ceiling; valid Kimi result; packet/profile/binding checks pass | `passed` or `findings` | existing wrapper parse and binding receipt |
| packet above inline ceiling but within the global bound and the private MCP cannot be validated | fallback-eligible `inconclusive` before invocation | negative server/config/binding fixture; no Kimi invocation |
| packet above inline ceiling and the private packet MCP validates | exact `passed` or `findings` after complete byte-range coverage | server hash check, exact MCP/agent allowlists, parser byte matching, and packet hash before/after |
| MCP packet contains a physical line larger than one bounded tool result | continue over deterministic UTF-8-safe chunks | server long-line test plus wrapper invocation fixture |
| packet above inline ceiling and no safe complete transport/partition is available | `inconclusive`, capability-specific and fallback-eligible | negative fixture; no Kimi invocation |
| Kimi CLI exits with host watcher/resource evidence before a valid result | `inconclusive`, CLI/host-runtime classification; never auth/model success or failure | safe local replay or synthetic exact fixture |
| packet/profile/hash/tool/native-skill binding changes or cannot be proved | terminal `inconclusive`, no cascade laundering | existing and focused negative tests |
| model output is malformed but contains bounded concern evidence | terminal `inconclusive` with concern excerpt | existing concern-evidence tests |
| Kimi is granted more than 120 seconds by the controller | after the bounded capability probe, MCP review may use the remaining timeout up to 600 seconds; inline argv review remains capped at 120 seconds | delivery-specific timeout-argument and probe-accounting fixtures plus live formal verdict |
| Kimi asks for the exact EOF after already covering the packet | accept only a bound empty `PACKET_CHUNK`; any beyond-EOF request, altered body, or uncovered byte remains non-passing | server, parser, and wrapper exact-end/body/gap fixtures |
| OpenCode has emitted a terminal stop event and exported a matching complete formal answer before its process deadline | parse the complete bounded answer, require every frozen concern conclusion for profile-bound timeout recovery, and terminate without waiting for unrelated runtime tail work | event-plus-export and missing/complete concern RED/GREEN fixtures plus packet receipt |
| OpenCode exits nonzero and any structured event reports HTTP 402 or 429 while stderr is empty | quota/billing `inconclusive`, cascade eligible | RED/GREEN single-event and multi-event fixtures plus exact-candidate diagnostic evidence |
| OpenCode exits nonzero and any structured event reports HTTP 401 while stderr is empty | provider-auth `inconclusive`, cascade eligible | RED/GREEN multi-event fixture |
| OpenCode starts without any controller-selected owner skill | no capability except inert `invalid` may be enabled; `skill=false` is required | zero-owner generated-agent, boundary, parser, and wrapper fixtures |
| OpenCode packet-only review starts | only the selected review-skill names may be invoked; read, glob, grep, shell, write, network, task, and unknown plugin/MCP tools remain denied | generated-agent fixture, resolved-boundary fixture, and live no-tool-loop trace |
| Claude returns a provider quota envelope | fallback-eligible `inconclusive` with `reason_code=quota` | live small-diff probe and existing client-order coverage |
| Claude owner-aware init adds a built-in command present in the same-version safe-mode baseline captured from an empty independent cwd, and the installed CLI documents that safe mode disables skills | continue formal parsing without a static command allowlist edit | Claude 2.1.233 replay, cwd isolation, help-contract refusal, and wrapper fixture |
| Claude baseline and formal init both report a new skill that is neither pinned nor controller-selected | fallback-eligible `inconclusive`; the baseline is drift evidence, not capability authority | baseline-only skill policy row, mutation, and wrapper fixture |
| Claude baseline exposes a tool/plugin/MCP/permission change, an unknown non-bare command/skill name, or another proven customization | terminal `inconclusive`; no fallback laundering; a previously pinned non-bare built-in remains usable | real 2.1.233 replay plus negative baseline, tool, namespaced-name, and customization fixtures |
| Claude formal init reports a different version or an unbaselined bare host identifier | fallback-eligible `inconclusive`; the lane cannot verify one same-version vocabulary snapshot | version-mismatch, formal-only command, and policy-matrix fixtures |

## Test and register coverage

| Layer | Decision | Planned evidence |
| --- | --- | --- |
| unit / wrapper fixture | RED recorded; GREEN | `bash skills/code-review/scripts/test_cli_review_wrappers.sh` → `cli_review_wrapper_tests_ok` |
| parser contract | GREEN | `python3 -m unittest skills/code-review/scripts/test_review_client_compat.py` → 13 passed |
| controller / contract | GREEN | `test_review_gate.sh` → `review_gate_tests_ok`; no controller result vocabulary change because `EMFILE` uses existing `client_unavailable` |
| live safe host smoke | GREEN on the same small real diff for both repaired lanes | Kimi returned formal `passed` in about 21 seconds; OpenCode 1.18.15 with DeepSeek v4 Pro returned formal `passed` in about 90 seconds; both receipts bind the same candidate hash |
| Claude deterministic compatibility | GREEN; live formal review available | real 2.1.233 init replay and wrapper fixtures accept same-version built-ins, version or safe-mode skill-isolation contract drift cascades, baseline tool exposure stays terminal, and exact-candidate partitions produced formal verdicts |
| final exact-candidate partition coverage | required before commit | when the composed packet exceeds 200 KB, every semantic partition requires its own hash-bound review and challenge; no partition result is a candidate-wide verdict |
| UI/browser/device | not applicable | no visible surface |
| release/install | not applicable | not authorized and no packaging surface expected |

The non-wording shared-skill change requires a `RED-baseline` row, implementer
self-review, independent fact/consistency review, adversarial challenge, R0
status, and the repository's mandatory validation commands.

## Source register

| Source | Minimum depth | Status | Completion evidence |
| --- | --- | --- | --- |
| prior produced review/CLI evidence | read the persisted plan boundary and current local artifacts without copying sensitive raw output | `read` | model/API success, wrapper rejection, and CLI `EMFILE` remain separate observations |
| Kimi wrapper and parser | packet construction, tool boundary, transport, parse/coverage, result receipt | `implemented` | inline/MCP switch, first-line receipt, packet and generated-artifact mutation checks |
| review controller | freeze, global bound, fallback, result normalization | `read` | existing `client_unavailable` cascade applies to Kimi host resource exhaustion |
| focused tests | oversize, template exactness, malformed concern, host error, timeout tail, boundary budget, OpenCode permissions, no-invocation cases | `green` | wrapper, OpenCode retry/concurrency/parser, egress-schema, controller, and parser-compatibility suites |
| stable contracts | `SKILL.md`, client routing, timeout/auth notes, scripts contract | `updated` | client routing now matches Kimi's exact packet transports, OpenCode's skill boundary and timeout-tail recovery, Claude's same-version host baseline, and `EMFILE` classification |
| Claude wrapper, init parser, and controller | host vocabulary, executable/tool/authority binding, provider envelope, quota normalization | `implemented` | live 2.1.233 init reproduced both quota and available-provider paths; same-version baseline fixtures pass, version drift cascades, and unsafe tool/authority/customization surfaces stay terminal |

## Owner and impact map

| Owner | Status | Reason |
| --- | --- | --- |
| `code-review` | update | owns the provider-neutral gate and all repaired client wrappers, including Claude's runtime baseline |
| `skill-extraction-workflow` | register updated | the required impact-chain rows record the reusable transport, timeout-tail, and packet-only tool-boundary rules |
| `product-rd-workflow` | routed | classifies this as gate implementation |
| `testing-strategy` | apply | owns RED baseline, mutation sensitivity, and layer matrix |
| release/docs/install | not applicable | no downstream behavior outside the shipped wrapper contract is requested |

## Stop conditions and review gate

Stop implementation and report `interim` if the only apparent fix requires:

- placing an over-inline packet in process argv instead of the private agent or
  packet-MCP transport;
- enabling packet-external reads, shell, network, subagents, or writes; the
  generated MCP exception may expose only exact byte chunks of the
  already-frozen packet and must accept no path;
- accepting partial packet coverage, free-form output, or a raw API response as
  a formal verdict;
- silently partitioning while losing cross-partition findings or candidate-wide
  identity;
- weakening a terminal boundary failure into a cascade-eligible failure.

Before any completion claim, run focused tests, the mandatory repository gates,
and a hash-bound review/challenge pair for every partition of the unchanged
candidate. No single partition may stand in for candidate-wide coverage.
