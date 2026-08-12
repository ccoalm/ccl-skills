# Agent tool-dispatch framework

Reusable mechanics for the **tool layer** of an agent runtime: how a model's requested tool calls are registered, discovered, routed to handlers, executed (including in parallel), and shaped back into model-visible results. This is the registry/router/execution plumbing — distinct from the policy engine that decides *whether* a given execution is allowed.

Use this when building or reviewing an agent's tool system. It sits beside:
- `agent-turn-lifecycle.md` — owns the loop that *calls* the dispatcher and consumes results.
- `agent-command-sandbox.md` — owns approval → sandbox → escalation for an individual command/exec tool. The dispatcher delegates the *enforcement* of a tool call to that engine; do not re-implement it here.
- `agent-lifecycle-hooks.md` — owns the pre/post-tool hook points the dispatcher fires around each call.

## Registry and the tool contract

Define one runtime contract every locally-executed tool implements. Keep it small and uniform:

- **execute** — run the call, return a typed result.
- **kind match** — which payload shapes this tool accepts (plain function call, search-surfaced call, etc.).
- optional metadata the runtime needs: telemetry tags, post-tool-hook payload shaping, tool-search descriptor, argument-diff consumer.

A uniform contract is what lets the router treat first-party tools, MCP/remote tools, and extension tools identically. Normalize tool **names** to one canonical form at the boundary (flatten namespacing) so dispatch, telemetry, and hook-matching all key off the same string.

## Tool discovery: static vs dynamic (searchable) tools

Not every tool should be in the model's context at once — large tool sets blow the context window and degrade selection. Split the active set:

- **Static** tools: always present in the tool spec.
- **Dynamic** tools: surfaced on demand via a **tool-search** entry. The model is given a lightweight search/discovery tool; matching tools are then injected into the active set only when needed. Track each tool's **origin** (static vs dynamically surfaced) so you can reason about why a tool is callable, and define its **eviction policy explicitly** (e.g. stays for the rest of the turn, LRU cap on the dynamic set, or explicit removal) rather than leaving lifetime implicit.

This is the standard answer to "I have hundreds of tools": expose a searchable index, load schemas lazily. The dispatcher must accept a call to a tool that entered the set dynamically exactly as it would a static one. Keep the searchable index **curated/trusted**, not built from user- or content-supplied free text — a poisoned index could surface a malicious tool to the model.

## Routing

The router maps an incoming tool call (name + call id + arguments payload) to the registered handler:

- Resolve by canonical name; a truly unknown tool is a typed `function_call_error`, never a panic — return it to the model so it can correct, don't crash the turn. **Distinguish "unknown" from "known but currently inactive"**: a tool that was dynamically evicted mid-turn is a race, not a model mistake — re-surface/re-activate it and dispatch, rather than telling the model it doesn't exist.
- Carry the **call id** through end to end; results must be correlated back to the specific call (critical for parallel execution and for tool-call↔result pairing in history). **Detect duplicate call ids within a turn** (a model can reuse an id across parallel calls); reject or disambiguate rather than mispairing results.
- Validate arguments against the tool's schema at the boundary; malformed arguments are a typed error result, not an exception.
- Distinguish a tool *execution error* (tool ran, failed) from a *dispatch error* (no such tool, bad args) — they read differently to the model.

## Parallel execution

When the model requests multiple tool calls in one response and the model/runtime supports it, execute them concurrently:

- Each in-flight call gets a child of the turn's cancellation token, so a turn abort cancels all of them. On abort, explicitly cancel **and join** each call's work (where the runtime cancels on drop, dropping the handle suffices; otherwise cancel-then-await) — a cancelled tool must stop, not detach and keep running.
- Share a single **turn-diff tracker** (or equivalent accumulator) across the parallel calls so concurrent effects are observed coherently, with synchronization on that shared state. **The tracker is not a substitute for resource-level safety**: two calls editing the *same* file/row concurrently corrupt or lose writes regardless of tracker locking. Run tools in parallel only across **disjoint resources**; serialize calls that touch the same resource (per-path/per-key lock) or detect and reject write conflicts.
- Results must be paired to their call ids and recorded in history in the **model's requested call order** (the order the calls appeared in the response), not completion order — completion order is nondeterministic and would make history non-reproducible.
- **Bound the parallelism** — don't fan out unboundedly across many tool calls (resource exhaustion). Respect the model's parallel-tool-calls capability flag; serialize when it's off or when tools declare ordering dependencies.
- Tools with side effects that may be interrupted/retried need the idempotency discipline from `agent-turn-lifecycle.md` (a cancelled-then-retried parallel batch must not double-apply).

## Result shaping and post-processing

- Convert each tool result into the model-visible output payload, and separately into the **post-tool-hook payload** (tool name, tool-use id, input, response) for observers.
- Apply post-tool hooks; let them inject additional context, treated as untrusted (see `agent-lifecycle-hooks.md`).
- Emit per-call telemetry (tool name, decision source, duration, outcome) keyed by call id.
- Bound result size fed back to the model; truncate large tool output **visibly and structure-aware** — truncating in the middle of structured (JSON) output yields unparseable downstream content. Use structure-aware markers or summarize, don't byte-chop.

## Code-mode: tools as a code/exec runtime (optional advanced pattern)

An alternative to many discrete tool calls: expose a single **exec** tool that runs model-authored code in a controlled runtime, where the code calls the other tools as nested in-process functions. Observed mechanics worth reusing:

- **Render each tool's JSON schema into the runtime's language types** (e.g. JSON-schema → TypeScript signatures) so the model writes correctly-typed calls against a familiar surface instead of emitting raw tool-call JSON.
- **Nested tool calls** from inside the exec runtime route back through the same router/registry — one dispatch path. Nested calls must still pass the **same pre/post-tool hooks and approval/sandbox gates** as top-level calls; an in-process nested call that skips them is a policy bypass.
- **Forbid or depth-bound re-entrant exec.** If the exec tool is itself callable from inside exec (`exec(exec(...))`), unbounded recursion blows the stack/process. Either exclude the exec tool from the nested tool set or cap recursion depth.
- **Yield/wait semantics**: long-running exec yields control (with a yield timeout) and can be resumed via a wait call, so the agent loop isn't blocked on a single long execution.
- **Per-exec output-token budget**: cap the tokens a single exec call can emit back to the model; large stdout must be truncated/bounded like any tool output.
- **Guard the host↔runtime numeric boundary for precision-critical integers.** When the runtime language has a narrower exact-integer range than the host (a JS/TypeScript runtime is exact only up to 2^53−1), precision-sensitive integers crossing the boundary — schema-projected id/count parameters, runtime-config fields like timeouts/token caps, and integer tool results — must be range-validated (on both inbound args and outbound tool results, before they enter the narrower runtime) or carried as a canonical decimal string or a typed int64/bigint where the transport and runtime support it (note bigint is not JSON-serializable; a free-form string invites later unsafe interpolation, so pin a canonical/branded form). A host integer past the runtime's safe range silently loses precision (and may wrap/truncate in bindings that coerce to narrower integer types), so the code executes against a *different value than the model intended*; reject out-of-range numeric inputs at the boundary rather than coercing them. (Ordinary floats like a temperature/probability map naturally to the runtime's double and don't need this — it's the exact-integer cases that bite.)
- **Don't assume fire-and-forget async survives a short-lived exec teardown.** If the exec runtime is short-lived and the host tears it down (or cancels the isolate) when top-level evaluation returns, any not-yet-awaited promise / pending task / timer may be cancelled or dropped — often with no model-visible error. Model code that fires off work without awaiting it (a write, a nested tool call, a flush) can lose that work. Document the teardown contract, and for effects that must complete, require the code to await them — or keep the cell alive (yield/wait) until they settle, but only *within the exec deadline / cancellation budget* (an await on a never-settling nested call must still be cut off by the section's wallclock/cancellation limits, not block the exec slot forever). (Longer-lived runtimes may instead keep the loop alive or surface an unhandled-rejection warning; the failure mode depends on the teardown contract, so state it explicitly.)

Code-mode runs **model-authored code** — it is not "a tool call that needs sandboxing", it is arbitrary code execution and demands the full treatment: the OS sandbox of `agent-command-sandbox.md` *plus* resource limits (CPU/memory/wallclock), egress control, and a per-nested-call policy check. Model code can otherwise loop forever, read secrets, or exfiltrate via a nested network tool. It trades more powerful composition (loops, conditionals, data flow between tools without a model round-trip) for that much larger attack/runtime surface — adopt it only when tool-call chaining is a real bottleneck.

## Anti-patterns

- Panicking on an unknown tool or malformed arguments instead of returning a typed error to the model (crashes the turn; model can't self-correct).
- Putting every tool in the model's context at once (context bloat, worse tool selection). Use static/dynamic split with tool search.
- Losing the call id across dispatch (results can't be paired; parallel execution corrupts history).
- Parallel tool futures that aren't cancelled+joined on abort (cancelled tools keep running; resource leak).
- Running tools that touch the *same* resource in parallel (lost writes/corruption; a shared diff tracker does not prevent this). Parallelize across disjoint resources only; lock or conflict-detect same-resource calls.
- Recording parallel results in completion order instead of the model's requested call order (non-reproducible history).
- Unbounded parallel fan-out, or ignoring the model's parallel-capability flag (resource exhaustion; calls the model can't handle).
- Sharing mutable cross-call state (diff tracker, history) without synchronization in the parallel path.
- Duplicate call ids within a turn going undetected (mispaired results).
- Conflating dispatch errors (no such tool / bad args) with execution errors (tool ran and failed) — the model needs to tell them apart.
- Re-implementing approval/sandbox logic in the router instead of delegating to the command-sandbox engine (drift between two enforcement paths).
- Adopting code-mode for its own sake when discrete tool calls suffice (extra runtime + sandbox surface for no real composition need).
- Treating code-mode as "just sandbox it" rather than full arbitrary-code-execution defense (resource limits, egress control, per-nested-call policy).
- Re-entrant exec with no depth bound (recursion blowup).
- Nested code-mode calls that skip the hooks/approval applied to top-level calls (policy bypass).
- Passing precision-critical host integers outside the runtime/transport safe-integer range without validation (silent precision loss → code runs on the wrong value).
- Assuming fire-and-forget async survives a short-lived exec teardown (it may be cancelled/dropped with no model-visible error; await it or hold the cell open).
- Building the dynamic tool-search index from untrusted/free-text content (poisoned tool surfaced to the model).
- Byte-truncating structured tool output (unparseable downstream). Truncate structure-aware or summarize.
- Feeding unbounded tool/exec output back into context (overflow; cost). Bound and mark truncation.
- Hardcoding a **cross-tool reference to a maybe-absent *concrete* tool in a tool's static schema description** — one tool's description naming another concrete callable, e.g. "prefer `<other_tool>` for X". When `<other_tool>` is absent in this deployment (disabled toolset, missing credential/API key, or simply not in the active / dynamically-surfaced set), the description steers the model to call a tool that isn't callable → a hallucinated call. Even with typed dispatch errors returned to the model for self-correction (per Routing above), it wastes a turn, degrades selection, and can leak through to the user. Fix: keep static descriptions self-contained, and add a concrete cross-tool hint only into the **rendered tool-definition snapshot for the turn, bound to the same tool-set / capability generation dispatch keys off** (not by mutating a description ad hoc between otherwise-identical turns — that churns the prompt cache; see `llm-client-gateway.md`), and only when the referenced tool is in the active set. Fine (not this anti-pattern): naming an always-present core tool, an atomically-bundled tool pair, or pointing at the tool-search/discovery capability for adjacent tools (a capability-level handoff, not a concrete absent callable). (The skill-design analog — a skill description referencing a maybe-uninstalled skill — is owned by `skill-extraction-workflow`'s "if installed, route to X; otherwise apply the principle inline" rule.)

## Persisted tool-output artifacts

Treat persisted tool-output artifacts as model-visible evidence substitutions, not ordinary temporary files or proof that the full result was read. When a tool, connector, resource reader, fetcher, or per-message budget path replaces raw output with a preview, saved artifact reference, typed marker, or read instructions, bind the artifact to principal/session/workspace, tool-call id, tool/source trust identity, schema or format label, content type class, original-size estimate, preview size and truncation state, output snapshot or digest where feasible, transcript replacement record, privacy/source-scope labels, permission/policy generation, and cleanup or retention policy; high-risk or mutable artifacts need an immutable digest, snapshot, or locked generation before replay, resume, or readback claims can rely on them. Previews, saved-path messages, and binary artifact notices are evidence of availability only; the agent must not summarize, analyze, or claim absence from the full output until it has read the needed chunks or explicitly states the unread portion. Large structured output needs a format/schema label and chunk/search strategy; binary output needs a conservative content-type to extension/viewer dispatch and a fallback when persistence, decoding, or viewer support fails. Empty tool results need a typed completion marker so model turns do not infer hidden content or stop ambiguity. Replacement decisions must be stable across resume, replay, prompt-cache reuse, and aggregate-budget enforcement: already-replaced results reapply the same model-visible marker, already-unreplaced results are not silently replaced later, and failed persistence falls back to a clearly labeled truncated or unavailable state rather than fabricating a full artifact. Persisted artifacts inherit the source tool's authorization, source labels, and untrusted-data status; converting output into a local file must not widen read permissions, erase connector/resource provenance, bypass compaction floors, or make raw output eligible for logs, telemetry, prompts, or user-visible summaries without redaction.

## Tool exposure vs tool authorization

Review tool exposure separately from tool authorization: the model-visible tool pool, deferred/searchable tools, external protocol tools, deny/allow/ask rules, and human or policy approval must be independently inspectable.

## Dynamic tool catalogs and external connectors

For dynamic tool catalogs or external connectors, verify prompt-cache partitioning by principal/session, tool source/server identity, manifest version, authorization policy version, and connector trust level; handle tool-name collisions, server/source trust boundaries, and capability-change reauthorization explicitly.

## External tool servers and connector channels

External tool servers and connector channels need a separate auth and consent contract before they become model-visible or approval-capable. Validate auth metadata schema and secure transport before use. Bind stored credentials and discovery state to server identity plus a canonical config digest, audience/resource identity, principal, account, tenant, organization, workspace, connector source, and auth-policy generation; when a product lacks one of those scopes, bind an explicit none marker instead of omitting it; never reuse credentials after server identity, config digest, URL, headers, source, audience, principal, account, tenant, organization, workspace, or auth-policy generation drift. Dynamic header helpers, environment expansion, channel bridges, and connector-provided prompts are untrusted executable or control inputs: gate workspace/local helpers on trust, bound runtime and output schema, redact secrets before logs or prompts, and fail closed for missing required credentials. Permission relay over a connector requires an active connection, explicit allowlist or policy grant, declared capability support for both conversation relay and permission relay, a structured pending request id, one-shot delete-before-resolve semantics, duplicate/unknown reply rejection, and final allow/deny binding to the original tool-call tuple including connector identity, server identity, canonical config digest, server URL, header/config digest, connector source, audience/resource identity, principal, account, tenant, organization, workspace, policy version, tool-call id, tool schema version, and normalized invocation digest. User elicitations from a connector need abort handling, hook result validation, completion notification binding to server plus elicitation id, and cancellation on malformed, late, or untrusted completion.

## Cached tool manifests and planned tool calls

Cached prompts, tool manifests, model outputs, or planned tool calls must never bypass fresh execution-time authorization.

## Remote permission/control responses as untrusted input

Treat remote permission/control responses as untrusted input: validate the discriminant and payload shape, bind each allow/deny/cancel response to the pending request id plus principal/account, session or transport incarnation, session generation, tool-call id, action/resource scope, policy version, tool source/server identity, manifest/tool schema version, and exact normalized invocation/argument digest, and reject stale responses after cancellation, account switch, reconnect generation change, policy change, or capability change.

## Tool execution side-effect authorization

Treat every tool execution as a side-effect authorization boundary. Bind allow, deny, ask, hook, classifier, and cached approval results to the exact pending tool-use id, normalized arguments, invocation digest, working directory, permission mode, policy version, principal/session identity, capability generation, tool source/server identity, and tool schema version. Re-run authorization after any hook-supplied input change, user edit, permission update, mode change, working-directory change, abort/cancel/retry, capability reload, or policy refresh; stale decisions must fail closed and must not be reused across a different invocation. The approving user or policy engine must see the final normalized invocation and resource set after all input transforms. Persisted approvals need narrowest-reusable scope, explicit revocation handling, and expiration or revalidation when policy, principal, capability, workspace, or tool schema changes.

## Search, glob, file-suggestion, and symbol discovery

Treat search, glob, file-suggestion, symbol, reference, definition, hover, and other code-discovery results as model-visible evidence control planes, not ordinary text output. Bind every discovery request to query or pattern digest, requested path or scope, type/mode/filter flags, principal/session/workspace, workspace or root-set generation, privacy/source-scope policy, tool-source identity, and capability generation before execution; run read permission and canonical containment checks before searching, indexing, or asking a code-intelligence server, and fail closed on network-path or unverifiable-containment inputs that could leak credentials or widen scope. Returned evidence needs source labels, normalized workspace-relative paths or bounded opaque labels, snapshot or index generation, freshness or partial-index state, worktree/source state where applicable, local/VCS/global/policy ignore-rule policy, hidden/binary/generated/vendor/plugin-cache exclusion policy, result mode, count, truncation, pagination offset, timeout/abort state, and whether deleted or inaccessible files were skipped during scan/stat reconciliation. A truncated, paginated, partial, timed-out, aborted, permission-filtered, stale-index, stale-server, or ignore-filtered discovery result must be labeled as incomplete and cannot support "not found", "only", "all", or absence claims without a complete fresh scan for the same tuple. File-suggestion indexes and cached discovery lists must invalidate or generation-fence after workspace/root, privacy, policy, ignore-file, source-control index, tracked/untracked file, settings, capability, or plugin/source change; background merges of untracked or newly indexed files may update suggestions only when the original cache generation still matches, otherwise discard as stale. Code-intelligence results require file snapshot/open-state proof, server initialization and generation binding, path/URI and line/column normalization, maximum file-size handling, ignored-result filtering for location queries, malformed-location rejection, and stale-server rejection after file, workspace, policy, or server-generation drift. Diagnostics may expose bounded categories, counts, incomplete-state markers, and non-reversible digests, but not raw local paths, sensitive project structure, query text, matched content, filenames, branch names, credentials, command arguments, or free-form server errors.
