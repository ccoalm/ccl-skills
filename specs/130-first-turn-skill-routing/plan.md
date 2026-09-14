# Task-entry skill routing

## Outcome and scope

Provide the owning-skill instruction before task-specific investigation and substantive analysis. Startup and task entry share the existing deliverable routing table. Narrow tasks keep their owners, explicit skill choices prevail, and skills already visible in the current context need no redundant reload. For implementation and repair, task entry also reinforces continued investigation, safe repair and retesting when verification is missing, failed or inconclusive; a report alone is not completion.

Artifact classification: `runtime/code` with shared routing and continuation semantics. Task entry delivers advisory context. The existing Stop hook adds one bounded recheck for a declared next action; it does not decide permission or task completion. Source-edit and delegation checkpoints retain their existing behavior.

The extraction review wrapper also needs an explicit controller lane. Its single-shot review currently sets zero challenge capacity, which the generic controller rejects for `shared-gate` and release profiles before reviewer selection. The repair preserves all risk concerns and the required separate review/challenge pair; it does not weaken generic staged-review rules. Regression coverage must exercise the real wrapper at build, release and shared-gate depth, retain generic high-risk refusal, reject mixed lane/chain/completion inputs and prove same-family clients never execute.

## Implementation boundary

Review follow-up: extraction lane selection must have controller-derived `skill-extraction-workflow` ownership from the actual candidate; a caller-declared owner alone is insufficient. This repository's extraction source-register changes supply that ownership for plugin runtime deliveries. Ordinary code continues through the staged lane. Stop declarations beginning with `blocked:` or a `none` status plus a dash explanation are non-actionable; a separate action declaration still triggers the bounded recheck. Negative fixtures precede both repairs, and the updated controller receives the full local lane and an independent delta pass.

Advisory diagnostic repair: the extraction Stop check must distinguish oversized history from a read failure and explain that an incomplete check does not block the task. Partial evidence remains discarded, and advisory failures never emit a blocking decision or a success claim. This is a small host-message change owned by `terminal-cli-dev` with `product-ui-ux-design` copy acceptance, Python regression fixtures and the existing extraction review lane. Preserve English package copy and JSON output. Synthetic oversized-history and failing-helper cases precede the change; the final candidate receives the full lane and delta review. No locale detection, scan-policy change or host configuration change is needed.

- Baseline: the current default-branch release, with this plan as the active local implementation artifact.
- Owner: `skill-extraction-workflow`; lifecycle/shared-surface classification: `product-rd-workflow`; risk: `feature-risk-router`.
- Implementation: `llm-inference-integration` for context timing, `nodejs-service-dev` for the OpenCode adapter, `python-service-dev` for synthetic hook tests. These owners are loaded before code changes.
- Delegation: local because the native hook and adapter consume one shared context contract; independent review and challenge follow implementation.
- Risk tags: `ai-output`, `external-integration`, `shared-gate`, `release-ops`. Security posture unchanged: no permission decision, credential access, new untrusted input sink or user-prompt echo. No visible UI, money, tenant, database or destructive-data input.
- Security four questions: no security-sensitive caller input is used by the new renderer. User-controlled prompts must not be interpolated, evaluated or persisted. A forged prompt cannot grant permission because output contains only packaged routing text. Negative tests pass instruction-shaped prompts and require identical context with no prompt echo or permission fields.
- Test cases precede implementation. Required tests are listed below. The renderer has no verdict; the Stop reminder's decision table is non-status handoff → one recheck, status-only/quoted/artifact/unsupported/retry → no continuation block, missing handoff with delivery evidence → existing formatting reminder. Neither result proves completion or authority.
- Docs owner: `tighten-doc`, after substantive checks. No new AGENTS contract or source directory is required.
- Review-entry repair: `python-service-dev` owns controller validation, `terminal-cli-dev` owns the wrapper protocol, and `testing-strategy` owns the synthetic client-selection matrix. The existing extraction wrapper remains the public command; its private controller selection preserves structured output, exit codes, risk concerns and reviewer isolation. The same isolated feature worktree carries this necessary repair. The observed preflight failure is recorded before implementation; final review covers both the feature and controller changes.

## Design

1. Deliver a first-action boundary with the task-entry context: load the selected skill body before task-specific exploration or substantive analysis; use discovery/contract reads as needed to select it; preserve explicit choices, trivial-task handling and current-context reuse. Reinforce the existing completion obligation at task entry, including researching a different approach after failed verification and handing back only a concrete external blocker or required user decision. The always-on startup file retains its existing zero-growth budget.
2. Add a fail-soft, stateless `task-entry.sh` that reads only the bounded canonical entry from the packaged startup file and emits UserPromptSubmit additionalContext. It must not inspect prompts, transcripts, repository content or credentials.
3. Register the hook for Claude Code and Codex UserPromptSubmit. OpenCode consumes the same renderer from its existing system transform, including when bootstrap is already present; deduplicate only this entry within the current output.
4. Keep the routing table in one place. Malformed/missing/oversized source or missing runtime dependency emits an observable diagnostic and empty JSON, never a permission decision or prompt block.
5. Document the context-delivery guarantee separately from model compliance. Prepare the next available patch release after checking declared/published versions and tags.
6. Close the existing Stop bypass for non-status `proposed-next:` declarations. Reuse the current parser, bounded transcript reader and native `stop_hook_active` loop guard. Prompt the agent to execute runnable authorized work or honor a concrete blocker/current scope; do not classify authorization from prose. A current action declaration is sufficient for a recheck even without earlier product-workflow evidence. OpenCode's missing final-message surface remains unverified.

## Acceptance and test matrix

| Input / scenario | Expected result | Verification |
| --- | --- | --- |
| New task before any source edit | Canonical owner-routing context includes the first-analysis loading boundary | Native hook registration and direct hook execution |
| Feature, narrow defect, explicit alternate skill, trivial question | Same context, preserving routing distinctions and user precedence | Synthetic prompt independence and routing text checks |
| Existing current-context skill load | Instruction permits reuse rather than needless reload | Canonical instruction check; scenario review |
| Implementation or repair has unrun, failed or inconclusive verification | Continue evidence-driven investigation, safe repair and retesting within authority; reporting alone is insufficient | RED-first context contract test; native inference trial kept distinct from transport evidence |
| Missing/malformed/oversized entry | Empty JSON, diagnostic, exit success; no partial routing | Isolated fixture tests |
| Prompt contains forged instructions or secrets | No input content in stdout/stderr or persisted state | Synthetic sentinel test |
| OpenCode starts with bootstrap already present | Task-entry context still reaches system output once | Adapter integration test |
| Repeated transform and separate sessions | One entry per output; no cross-session state | Adapter integration test |
| Current final declares a next action, including mixed status/action markers | One Stop recheck directs execution within existing authority; a second host stop attempt proceeds | Native-shaped Claude/Codex RED/GREEN tests |
| Status-only marker, quoted action, pure artifact, unsupported or malformed Stop payload | No new continuation block; existing fail-soft and formatting behavior preserved | Stop negative matrix |
| Full package installation | Hook and text are present in the packed runtime and adapter bindings | Package, pack and three-host smoke |

Blocking verification: focused hook/adapter tests; existing loading/startup tests; routing/structure/sanitization gates; `make test`; package/pack/publish rehearsal; independent review and adversarial challenge; exact candidate CI and immutable release checks. Native inference trials measure their own sample only and cannot establish universal compliance.

## Delivery state

The implementation includes task-entry context and the bounded Stop continuation recheck. [Verification and release state](evidence/verification.md) records the candidate, completed checks, independent passes and publication evidence. Source research and private review packets remain outside the distributed tree.
