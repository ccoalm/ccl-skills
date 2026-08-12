# Agent lifecycle hooks framework

Reusable mechanics for a **user-extensible hook surface**: how an agent runtime lets operators inject external logic (a command, a script, an in-process callback) at fixed points in the turn/tool lifecycle to observe, gate, modify, or block agent behavior — without forking the runtime.

Use this when building or reviewing a hook/extension system for an agent. It sits beside:
- `agent-turn-lifecycle.md` — owns *where* in the loop each hook fires (session start, pre/post tool, pre/post compact, stop).
- `agent-command-sandbox.md` — owns the approval/sandbox engine that a permission hook can short-circuit.
- `agent-tool-dispatch.md` — owns the tool router whose pre/post points the tool hooks wrap.

## The event surface

Define a closed, named set of lifecycle events. A representative, well-covered set:

| Event | Fires | Can gate? | Typical scope |
|---|---|---|---|
| SessionStart | session/thread begins | no (observe + inject context) | thread |
| UserPromptSubmit | user input accepted, before sampling | yes (block/inject) | turn |
| PreToolUse | before a tool executes | **yes** (allow/deny/ask) | turn |
| PermissionRequest | when a tool needs approval | **yes** (allow/deny) | turn |
| PostToolUse | after a tool returns | no (observe + inject) | turn |
| PreCompact | before context compaction | yes (influence/abort) | turn |
| PostCompact | after compaction | no (observe) | turn |
| SubagentStart | a sub-agent/child turn begins | no (observe + inject) | thread |
| SubagentStop | a sub-agent finishes | **yes** (block to continue) | turn |
| Stop | turn is about to complete | **yes** (block to continue) | turn |

Two design rules from this table:
- **Not every event takes a matcher.** Tool-scoped events (pre/post tool, permission, compact, subagent) match against a target (tool name, compaction trigger, source); prompt-submit and stop fire unconditionally. Encode which events have meaningful matchers so config that puts a matcher on a non-matching event is ignored predictably rather than silently mis-dispatched.
- **Scope matters for state keying.** Session/subagent-start hooks are thread-scoped (they set up state for the whole thread); the rest are turn-scoped. Key any persisted hook state by event scope so a turn-scoped hook's state doesn't leak across the thread.

## Dispatch semantics

When an event fires, select and run the matching handlers:

1. **Select** handlers whose configured event matches and whose matcher (a regex over the target, e.g. `Write|Edit|apply_patch`) matches the input. Events without matchers select all their handlers.
2. **Dedupe per handler.** If one handler's matcher has several alias branches that all match the same target, run it **once**, not once per alias. (A `Write|Edit` hook fires a single time for one edit call.)
3. **Run handlers concurrently but report in deterministic configured order.** Launch selected handlers in parallel for latency, but sort results back into configuration order before applying them — operators expect "first hook wins" to mean *first in config*, not *first to finish*. Track completion order separately if you need it for telemetry. Concurrent execution only orders the *decision aggregation*, not handler **side effects**: two hooks that each mutate external state still race. Require hook handlers to be side-effect-independent (ideally idempotent); provide an explicit **sequential mode** for the rare case where handlers have ordering dependencies, rather than pretending config-order result sorting serializes their effects.
4. **Aggregate decisions by precedence** (see decision model). With multiple gating hooks on one event, a safe default is: any **Deny** wins over **Ask**, which wins over **Allow**; ties broken by configured order. Make the precedence explicit and documented — "see below" is not a spec; operators must be able to predict the outcome when two hooks disagree.

**Bound hook fan-out.** N matching handlers spawned concurrently, times every tool call in a tight loop, is a subprocess storm (effectively a fork bomb). Cap concurrent hook processes with a pool/semaphore and cap handlers-per-event; queue or reject beyond the cap rather than spawning unboundedly.

### Decision model

A gating hook returns one of: **Allow**, **Deny(reason)**, **Ask** (escalate to user), or **Block** (for Stop: refuse to stop and continue with an injected prompt). Plus, most hooks can return **additional context** to inject into the turn regardless of decision. Normalize synonyms (e.g. `Block`→`Deny` for tool gating) into a single internal enum so call sites branch on one type.

- A **deny must carry a reason** that becomes model-visible — the model needs to know *why* a tool was blocked to adapt, not just that it failed. **Bound repeated identical denied calls per turn**: a deny that the model answers by retrying the exact same call is an infinite loop; after a small repeat count, escalate to a hard turn-level stop rather than re-denying forever (see `agent-turn-lifecycle.md` outer-loop bound).
- **A permission hook outranks the built-in *interactive* approval flow, but not a non-overridable policy.** If a `PermissionRequest` hook returns a decision, honor it and skip the normal user/guardian prompt; only fall through to the standard approval path when no hook decides. This lets an operator pre-authorize or hard-forbid classes of actions non-interactively. A hook **Allow** must not, however, escalate past a hard/forbidden policy denial — a hook can waive an interactive prompt, not a non-overridable safety rule. Deny always composes (a hook Deny stands even if policy would allow).
- For `Stop` / `SubagentStop` hooks, a block must supply a continuation prompt; a block with no prompt is a no-op (warn and proceed to stop) — otherwise the turn hangs unable to either stop or continue. Cap consecutive stop-block continuations (see `agent-turn-lifecycle.md` outer-loop bound).

## Running external command hooks safely

The most common handler type shells out to a user command. Treat that command as **untrusted, slow, and failure-prone**:

- **Pass event data as JSON on stdin**, not as argv (avoids quoting/injection and argv length limits). Emit a **stable, versioned wire shape** (snake_case keys, RFC3339 timestamps) — operators script against it, so changing it silently breaks their hooks.
- **Always time-bound** each command (per-handler timeout) and **kill on drop / kill on timeout** so a hung hook can't wedge the turn. A timed-out hook is a captured error, not a crash.
- **Capture, never panic.** Spawn failure, stdin-write failure, non-zero exit, timeout, and malformed output are all *results* with an error field — one bad hook must not take down the runtime. Decide per event whether a hook failure is `fail-continue` (run the rest, proceed) or `fail-abort` (stop the operation): gating events lean fail-closed for safety-relevant denials, observation events lean fail-open.
- **Bound the captured output.** Hook stdout/stderr can be arbitrarily large; spill/truncate to a cap before storing or feeding any of it back into context, or a chatty hook blows up memory and the context window. Truncation must be visible (marked), not silent.
- **Parse output defensively.** A hook's stdout is parsed into the decision/reason/additional-context structure; malformed JSON is a handled parse error (treated as "no decision"), never a trust-the-bytes path.
- **Treat hook-injected additional context as untrusted, model-visible data — the prompt-injection vector.** A command hook can echo attacker-controlled bytes (file contents, web responses) as additional context; injected verbatim it becomes a prompt-injection / agent-hijack path. Subject it to the same injection-trust handling as tool output: sanitize/quote it, mark its provenance, and gate how much weight it carries by the hook's trust level. Never inject raw hook stdout straight into the model turn.
- **Run hooks in a defined working directory and a minimal, explicit environment.** Pass an allowlisted env so behavior is reproducible and a third-party hook can't inherit ambient state — and in particular **do not forward secrets (API keys, tokens) into hook commands by default**; an untrusted hook with the agent's credentials in its env can exfiltrate them.
- **Kill the hook's whole process group, not just the parent.** A hook that spawns children leaves orphaned grandchildren when only the parent is killed on timeout/drop. Run each hook in its own process group and terminate the group.

## Anti-patterns

- An open-ended/implicit event set (operators can't know what they can hook; runtime can't validate config). Close the set and name it.
- Dispatching in completion order rather than configured order (nondeterministic "which hook won").
- Running a matcher-aliased hook once per alias branch (duplicate side effects for one tool call).
- Letting a hook command run unbounded (no timeout, no kill-on-drop) — one hung hook freezes every turn.
- Feeding raw, unbounded hook stdout back into context (memory blowup; context poisoning via untrusted hook output).
- A deny decision with no model-visible reason (model can't adapt; retries the same blocked action).
- A `Stop`-block with no continuation prompt and no cap (turn can neither stop nor progress).
- Panicking on hook failure instead of capturing it as a typed result (one operator's broken script crashes the agent).
- Changing the hook payload wire shape without versioning (silently breaks every operator's scripts).
- Treating a permission-hook decision as advisory while still prompting the user (defeats non-interactive pre-authorization; double-gates) — or the reverse, letting a hook Allow override a hard/non-overridable policy denial.
- Spawning all matching handlers with no concurrency cap (subprocess storm under a tight tool loop). Pool/semaphore the fan-out.
- Forwarding the agent's full environment (including secrets) into untrusted hook commands. Pass a minimal allowlist.
- Killing only the hook's parent process on timeout (orphaned grandchildren). Kill the process group.
- Injecting raw hook stdout as model-visible context (prompt-injection vector). Sanitize and gate by trust.
- Assuming config-order result sorting serializes side-effecting hooks (it doesn't — only decisions are ordered). Require independent/idempotent handlers or a sequential mode.
- Leaving a deny→model-retries-identical-call loop unbounded. Cap repeated identical denied calls per turn.

## Hook and classifier outputs as untrusted

Hook, prompt-hook, agent-hook, and automatic-classifier outputs are untrusted control-plane inputs, not authority. Validate result discriminants and schema, bind each response to the pending request and abort signal, time-bound execution, reject late results after cancellation or generation/policy/input changes, and let explicit deny/ask rules override hook or classifier allow results. A hook may narrow, ask, deny, add context, or provide a reviewed input transform; it must not silently widen permission scope, persist a broad allow rule, inject executable instructions, leak environment secrets into headers/prompts/logs, or override system, developer, current-user, managed-policy, or explicit-deny constraints.

## Post-turn hooks and follow-on background work

Treat post-turn hooks and follow-on background work as a continuation-finality boundary. Capture the turn context once, bind hook execution to principal/session/workspace, entrypoint mode, query source, agent identity, permission mode, hook-set generation, abort signal, transcript/message snapshot, and capability/policy generation, and restrict cache-safe context snapshots or background bookkeeping to entrypoints allowed to own that state. Background suggestions, memory extraction, classification, cleanup, or other post-turn jobs must be mode-gated, excluded from subagent or noninteractive timelines unless explicitly supported, isolated from the main transcript unless they produce an authorized message, and fenced so late results after abort, new input, root/workspace switch, or session/agent drift cannot mutate state. Stop, task-completed, idle, or similar continuation hooks need deterministic ordering, per-hook progress/effect identity, bounded output aggregation, explicit blocker versus nonblocking-error finality, and a model-visible blocker only when continuation is actually prevented. If a hook prevents continuation, aborts, or is canceled, return a durable continuation state rather than relying on UI notification; if hook orchestration itself fails, surface a degraded warning without inventing a blocker. Summaries, notifications, and diagnostics may expose bounded counts, categories, durations, and sanitized reason codes, but not raw hook commands, prompts, task or team names, outputs, local paths, credentials, telemetry ids, or free-form errors.

## Runtime hook configuration control plane

Treat runtime hook configuration as a mutable control plane, not a passive preference file. Build the effective hook set from declared source precedence and trust policy, with managed or policy-locked sources able to restrict lower-trust sources but never the reverse. Capture an immutable hook-set generation for each model turn, tool invocation, background task, watcher, and session-scoped callback registration; when configuration changes, reset stale settings caches, recompute the effective set from one authoritative source snapshot, validate it, and publish the new generation only through serialization or compare-and-swap. Failed or partial refresh keeps the prior valid generation, and the runtime must not report hook changes as applied until atomic publication succeeds. Either keep the old generation isolated for already-running work or force an explicit reload/restart/generation change before new hooks can affect model-visible context, permission decisions, environment mutation, filesystem watching, or tool output mutation. Late hook results, callback successes, dynamic watch paths, environment edits, permission updates, and additional context from an old generation must be discarded or re-authorized after hook-set, policy, workspace, principal, session, capability, or sandbox drift. Session-only function callbacks and hook-injected tools need bounded execution, cleanup on removal/abort/shutdown, no persistence unless explicitly declared safe, and no authority to outlive the session that registered them. Network or model-backed hooks are external control inputs: enforce allowlists, proxy/sandbox policy, SSRF and header-injection defenses, timeout/abort cleanup, output schema validation, no recursive hook triggering, and redaction before prompts, transcripts, logs, telemetry, or user-visible summaries. Outbound hook payloads need an explicit allowlisted schema, default-deny sensitive fields, size bounds, environment/header allowlist intersection, and no raw prompts, tool bodies, file contents, local paths, credentials, URLs, headers, or diagnostic strings unless that exact field class is authorized for that hook purpose. Hook-driven file watching and working-directory callbacks must validate watch paths against the current authorized workspace/root set, clear stale environment artifacts on directory change, close old watchers before replacing them, and treat watcher or cleanup failure as degraded control-plane state rather than proof that a hook was applied.
