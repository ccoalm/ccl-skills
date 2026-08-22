# Agent Capability Composition (Seams, Providers, Reversible Registration)

How an agent runtime packages its capabilities so they can be swapped, unloaded, and extended
without a privileged core: the decomposition unit, the registration lifecycle, and the sub-agent
provider seam. This is the composition layer *around* the frameworks the sibling references own —
`agent-tool-dispatch.md` owns how a call reaches a handler; `agent-runtime-bootstrap.md` owns
config/trust at startup; this reference owns how the handler's capability is packaged, installed,
and torn down.

Patterns observed in one agent-native product repository (an evolving portfolio — treat as one
industry form, not a standard) and consistent with general plugin-architecture practice. Use when
designing or reviewing an agent runtime's module boundaries, plugin/extension system, or sub-agent
integration; skip for a single-purpose agent whose capabilities never vary by deployment.

## 1. A swappable capability is three parts — seam, provider, model-facing tool

- When a capability must vary by deployment (local vs sandboxed filesystem, real vs replay model
  transport, in-process vs external sub-agent), decompose it into three separately-packaged roles:
  the **seam** (the service contract: abstract interface + vocabulary types), one or more
  **providers** (implementations of the seam), and the **model-facing tool** (a *consumer* of the
  seam that renders it into the model's tool surface). Consumers — tools, policies, other
  capabilities — depend only on the seam; a provider is selected at assembly time. The tool is not
  the implementation and never reaches around the seam into one.
- Verify the decomposition by the swap test: a new provider (remote store, different vendor,
  fault-injection fake) must drop in without touching the seam's consumers or the tool. If adding a
  provider forces edits in consumers, the contract leaked implementation detail.
- Design the seam's contract for **all current consumers**, not the loudest one: a method shaped for
  a single consumer's UI/transport/private need does not belong on the shared contract. A public
  seam method with exactly one internal caller is API surface without a second user — prefer a
  capability closure injected at construction into the one consumer that needs it.
- Keep role vocabulary honest in reviews: "the tool does X" is a smell when X is storage, policy, or
  enforcement — those belong to a provider or a policy plugin, and the tool only surfaces them.
  (Worked instances of the split: the spill store vs spill policy split in `agent-tool-dispatch.md`
  §Result shaping; the sandbox policy-resolution vs enforcement-backend split in
  `agent-command-sandbox.md` §2.)

## 2. Registration is reversible; teardown is scope disposal, not per-plugin cleanup

- Every registration-like effect a capability performs at install time (registering a tool, an
  event listener, a provider, a background worker) must carry its inverse, and the runtime — not
  each plugin author — owns applying inverses on unload. Model installation as effects recorded
  into an **ownership scope**; teardown = dispose the scope, which replays the inverses in reverse
  order. Correct unload is then guaranteed by one abstraction instead of N hand-written uninstall
  paths, and a plugin author cannot forget it.
- Hot-swap/reload is dispose-old-then-install-new under the same rule — never patch-in-place, which
  accumulates the old registration's residue. The failure half needs a contract too: preflight the
  new provider in an isolated scope *before* disposing the old one where the capability tolerates
  brief coexistence. Where it does not, know what rollback can and cannot promise: registration
  inverses reverse *local* effects only — disposal may have released a lease, port, credential, or
  other external resource that reinstallation cannot reacquire — so a non-coexistent cutover either
  uses an atomic/preflightable swap mechanism, or retains the old install descriptor and
  rollback-critical resources until the new install commits, and when the install fails *and*
  rollback also fails, the seam enters a **typed, surfaced unavailable state** (fail closed), never
  a silent half-registered one. Verify with an install → dispose → re-install cycle asserting no
  duplicate handlers, no leaked listeners, and no orphaned background work — plus failure injection
  through BOTH layers: new provider's install throws (capability ends served by old or new where
  the swap mechanism can guarantee it), and restoration fails too (capability ends in the typed
  unavailable state, observably, rather than asserting never-neither for a path that cannot
  guarantee it).
- Disposal order matters: dispose in reverse registration order so dependents release before their
  dependencies, and make disposal idempotent so a crash-then-cleanup path cannot double-free.
- This composes with (does not replace) the trust and generation rules in
  `agent-runtime-bootstrap.md`: a reversible registration that loads untrusted code is still gated
  by trust state, and a reload still invalidates the caches keyed to the old generation.

## 3. Policy plugins decide; providers enforce; absence has a declared default

- When a rule about *when/whether* to act is separable from the mechanics of acting (when to spill
  an oversized result, whether an edit target is stale, when to compact), package the rule as a
  swappable **policy plugin** over the capability seam rather than hard-coding it into the
  provider. The provider keeps the atomic enforcement check at the moment of action (freshness,
  no-clobber, bounds) because a policy's observation can be stale by the time the action runs.
- Declare what happens when the policy plugin is absent, and the declared default must fail toward
  the safe direction for that capability's risk class — for a destructive-capable capability
  (file overwrite, deletion, spend), absence means deny or require explicit approval, never a
  silent degrade to the unguarded behavior. The cautionary shape: a runtime whose read-before-edit
  observation policy is merely a removable plugin, with nothing beneath it, silently degrades to
  unconditional overwrite when the plugin is missing — which is why the enforcement-layer
  freshness/no-clobber check (`agent-command-sandbox.md` §Filesystem write authorization) stays
  mandatory regardless of which policy plugins are installed, and a deployment-level opt-out of a
  safety default must be explicit, never implied by absence.
- Do not let advisory policy observations become authority: a policy that watches tool traffic to
  derive guard state (which files were read, which calls repeated) produces *hints and gates*, and
  the enforcement layer re-validates at execution time.

## 4. Sub-agent integration is a provider seam, not a hardcoded runner

- Expose sub-agent execution through the same seam/provider decomposition (§1), with one shape
  difference: sub-agent providers are **named and co-resident** — a registry of concurrently
  available providers selected per spawn (in-process fork, spawned worker, an external vendor
  agent CLI) — unlike a single-selected executor seam. External vendor agent CLIs integrate as
  first-class providers behind the seam, so consumers do not care whether a child is in-process or
  a different vendor's product.
- Split the contract by lifecycle: a **one-shot** run (spawn → result) and a **continuable**
  session (spawn → handle → further turns → teardown) are different APIs; do not overload one call
  shape with both. For continuable children, the child-side provider emits only a **creation
  spec**; the parent-side runtime owns handle allocation, turn delivery, and teardown — a provider
  that never sees handles cannot leak or forge them.
- Make **fulfillment the single publish/ownership-transfer boundary**: a spawned child becomes
  visible to consumers only when the provider fulfills the creation, and ownership (who tears it
  down, whose scope disposes it) transfers exactly there — before fulfillment the provider owns
  cleanup on failure; after, the runtime's scope does (§2). Two owners or zero owners at any point
  is a leak or a double-free.
- This reference owns the seam shape only. Spawn-depth/live-count caps, capability intersection,
  and cascade-cancel live in `retrieval-agent-safety.md` §Agent SDK Building Blocks; task-state
  finality and recovery live in `agent-task-orchestration.md`; both apply in full to every
  provider, including external-CLI children.

## Non-negotiables

- A model-facing tool never depends on a concrete provider; consumers import the seam only.
- Every registration carries its inverse; unload correctness is owned once by scope disposal, and
  hot-swap is dispose-then-reinstall, never patch-in-place.
- A policy plugin's absence has a declared, deliberate default; policy observations are advisory
  and the provider re-checks atomically at action time.
- One-shot and continuable sub-agent APIs stay separate; fulfillment is the only ownership-transfer
  point, and continuable child providers emit creation specs, never handles.
- These are composition patterns from one industry form — apply the swap/dispose/ownership tests
  above as design gates, but do not cargo-cult the package layout onto a runtime whose capabilities
  genuinely never vary.

## Routing

- Tool registry/dispatch mechanics, result shaping, and output spill policy → `agent-tool-dispatch.md`.
- Startup trust, config generations, and cache invalidation on reload → `agent-runtime-bootstrap.md`.
- Sandbox policy resolution vs enforcement backends → `agent-command-sandbox.md`.
- Sub-agent spawn bounds and capability scoping → `retrieval-agent-safety.md`; task control plane → `agent-task-orchestration.md`.
- Session/scope persistence of what was installed when (for replay) → `agent-session-persistence.md`.
