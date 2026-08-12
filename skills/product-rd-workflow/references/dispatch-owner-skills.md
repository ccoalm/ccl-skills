# Dispatch Owner Skills

Use this reference for the owner-dispatch discipline behind the technical design gate: the complete owner set loads during design substance production, the firing gate's two firing points, and the opt-in mechanical enforcement. The entrypoint keeps the gate names, firing points, and closeout-acquire rule; this file carries the rationale and the map-building discipline.

## Why the complete owner set loads at design time

When the technical design gate is triggered and the deliverable's substance spans more than one owning skill — backend/platform/architecture (`go-microservice-architecture` / `python-service-architecture` + the relevant `platform-*` skills), LLM/inference/RAG/eval (`llm-inference-integration`), the storage/data-contract owner, the client stack owner (`web-react-dev` / `app-cross-platform-dev` / `miniapp-product-dev`), `testing-strategy`, `product-ui-ux-design` — those owning skills own BOTH (a) producing the design substance and (b) the review. Invoking the router does not discharge them.

- Before producing or reviewing, enumerate the concerns the deliverable touches and load the COMPLETE owner set for those concerns during design, not only at review. Do not load owners for untouched concerns, and do not discover required owners one at a time mid-review — if a new touched concern appears, add it to the inventory and load its owner before continuing.
- A cold dispatched worker is the worst case (see `multi-agent-delegation`).
- An external model/tool is supplement-only: it runs under the CCL owner review, never as the substitute gate.
- Producing the design substance without loading the owner skills, using an external review as the gate, or patching owners one domain at a time (architecture, then later realizing connectivity / LLM / data was also needed) is the recurring routing defect — it treats the router invocation as if it had already dispatched the owners.
- Exemption: a narrow single-owner task (one bug fix, implementation-only, or visible-UI-only change). Durable changes to this lifecycle rule route through `skill-extraction-workflow`.

## Firing gate mechanics (non-exempt multi-owner designs only)

The owner-dispatch map gates the START of design-substance production, not only design completion — build it BEFORE drafting any design doc / test plan / architecture decision, and re-confirm it before the first implementation edit. The firing point is these two transitions, not a post-hoc completion check.

- Reaching either transition with the design substance produced by `product-rd-workflow` + an external/codex review but no COMPLETE applied owner-dispatch map is the exact recurring defect this gate catches: pause, invoke the owner skills, build the map, then proceed. A partial dispatch (only some owners invoked) does NOT satisfy it.
- Build and record the map per the owner-map discipline in `skill-extraction-workflow` — its rules on accountable owner-set coverage (including cross-cutting owners), provenance location (design artifact / private register, never the shared skill tree), and applied-evidence quality apply; don't restate them here.
- The design is `interim` until the map shows, for every touched concern, an owner with **applied** evidence — the owner rule actually used and the design decision/constraint/change it produced. A green router invocation, a merely-`loaded` owner, finished prose, or a passing external review does not substitute, and `product-rd-workflow` is never the owner of domain substance.
- An all-`N-A` map means no domain concern was touched → that is single-owner work: use the entrypoint's exemption risk inventory (which escalates unknown repos/clients/contracts/risk to `feature-risk-router`) instead.

## Mechanical firing (opt-in, per product repo)

This gate is enforceable in code, not only prose:

- The `owner-dispatch` PreToolUse hook gates the first product-code edit (and write-like Bash); the Stop hook gates session close when gated edits happened without a recorded boundary. `scripts/owner-dispatch/owner-dispatch.sh ci` is the host-agnostic merge/pre-commit backstop.
- A product repo opts in by committing `.owner-dispatch.json` (product globs + excludes); absent it, the gate stays prose-only.
- Installing the backstop in a delivery: `bash scripts/install-gates.sh <repo> --gates owner-dispatch`, then flip `enabled:true` in a separate config-only change.
- Default posture: `ask` (not block), fail-open, Claude-Code-hard / Codex-advisory — the in-session hook raises enforcement above prose where wired; the `ci` backstop is as strong as the CI job's own enforcement (pipelines-must-succeed + protected branch).
- After invoking the owners and building the map, record the boundary to unblock editing: `scripts/owner-dispatch/owner-dispatch.sh record --owners "…"`. See `scripts/owner-dispatch/README.md`.
- ccl-skills itself ships no config (its own edits are shared-skill/process edits, exempt from owner-load).

The closeout-acquire rule (`status` must read `opted-in: yes`, or install, or record why exempt) stays in the entrypoint because it is a closeout item, not a map mechanic.
