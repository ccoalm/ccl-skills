# Host hook compatibility

Status: release verification. Base: `40dc287d2a786256bf37242458b2ec57853171b7`.

Restore equivalent hook behavior on current Claude Code and Codex, keep startup instructions directly visible, and expose the actual hook trust state after installation. The release target is the next unpublished patch of the unified npm package.

## Constraints

- Preserve protected-checkout denial and existing valid-worktree behavior.
- Parse every patch target, including deletion and move destinations; never execute patch text while inspecting it.
- Preserve explicit user authorization boundaries. Do not turn unknown authorization into approval or automate hook trust.
- Keep optional routing reminders advisory and bounded. Do not turn an unsupported host response into a silent promise of enforcement.
- Use synthetic fixtures only. Do not commit local identity, machine paths, credentials, session metadata or private provenance.
- Keep the canonical business rules shared. Host-specific input/output conversion belongs at the boundary.
- Do not change plugin manifest version fields, protected settings, or unrelated behavior.

## Acceptance and ownership

| Slice | Required result | Evidence | Implementation owner |
| --- | --- | --- | --- |
| Edit/owner input | Codex patch targets receive the same isolation checks as Claude file edits; canonical tool names and transcript shapes are handled explicitly | RED on current code; allow/deny/malformed/move/multi-file regressions | hook-input worker |
| Trust diagnostics | Doctor reports native trusted, untrusted and modified hooks; unsupported/unavailable inspection remains unknown | protocol fixture tests plus current-host readback; no trust mutations | package-diagnostics worker |
| Startup context | startup, clear, compact, resume and fork load bounded essential instructions; full obligations retain an explicit load path | event/size/semantic obligation checks and host-visible smoke | controller |
| Delegation/closeout | Canonical spawn and supported host output schemas; completion evidence reflects the host transcript format | negative and successful-completion fixtures | hook-input worker |
| Authorization | Remove evidenced unnecessary reauthorization while keeping target scope, explicit revocation and unknown-authority denial | design review before mutation; authorization regression matrix | controller after bounded design review |
| Runtime verification | Distinguish installation, trust and actual execution; prove allowed and denied effects on disposable targets | focused native-host checks plus installation smoke | controller |
| Release | Reviewed patch reaches protected main, exact tag and npm artifact | full repository/package gates, independent review and challenge, CI, provenance and clean consumer checks | controller |

## Entry record

Lifecycle owner: product-rd-workflow; shared-hook rules: skill-extraction-workflow; diagnosis: defect-diagnosis; tests: testing-strategy; review: code-review; release: release-coordination. Required owner skills were loaded before implementation.

Risk tags: shared-gate, permission-access, external-integration, release-ops. Authorization changes require a dedicated scope/negative-path review; parsing fixes preserve the existing protected resource policy. No UI layout, database, money or tenant changes. Native CLI status output uses the existing structured result interface.

Test-first: add focused regressions that fail against the base before runtime edits. Existing 9 hook suites are green on the base; this does not cover the new host contracts. Run `make test`, public sanitization, affected package tests and pack checks after integration. Run the heavy lane before release or verify its required CI result. Shared non-wording changes require independent review and challenge under the owning dual-track gate.

Delegation: parallel, with disjoint paths below. Plan-scan: clean. Boundary prompts contain only public repository facts and synthetic examples; no sensitive egress category identified. Native worker tools cannot be individually removed, so containment is prompt-only with observable child dispatch and a one-way stop on any attempted recursion. Workers are leaves; no delegation, user interaction, commits, pushes, installs, host configuration or external writes. Controller verifies skill loads, every diff and focused tests.

Owned paths: hook-input worker owns edit/delegation/closeout hook implementations, their tests, a small shared input helper if necessary, and owner-dispatch input/transcript handling. Package worker owns npm Codex hook inventory/doctor implementation and its tests. Controller owns hooks manifest, startup content, session-start scripts/tests, authorization scripts/tests, docs, build lists, versions and integration tests. Shared files and generated output are integrated by the controller.

Independent task budgets: input worker 30 minutes; package worker 25 minutes; authorization design worker 15 minutes, read-only. No recursive dispatch. Parent may continue with a narrower request or take over after an inconclusive deadline.

Landing: feature branch to dev, then dev to main using current CI and exact-head checks. Existing integration worktrees are preserved. Release authorization covers the necessary in-scope commits, pushes, PRs, merges, tag and established npm workflow; resource-owner permission checks remain binding.

## Decisions and obligation map

The target is patch `0.18.2`; declared and published versions were `0.18.1`, with no `0.18.2` tag at selection. This corrects observable compatibility defects; improved delivery outcomes beyond the measured fixtures remain unproven.

Target-goal grants recognize a complete, direct instruction naming one PR/MR. They bind repository, numeric target, original expiry and one remaining use. Neutral status/continuation messages may preserve that grant; stop revokes it, unknown text suspends it. Execution requires an immediate explicit-target merge, with the repository named in the command. The legacy one-shot and batch grammar retains its message-clearing semantics. Arbitrary prose about a future release does not mechanically authorize unknown future PRs. Human goal authority and the host's executable grant remain distinct.

The original session rules remain in `agent-context/session-policy.md`. The compact entry requires their relevant section before the corresponding action. Both native plugin packages include the policy; SessionStart emits a resolvable plugin path. The 9600-byte direct-context budget preserves the entire compact entry and replaces an oversized optional recovery capsule whole, or omits it when its replacement cannot fit. An extreme policy path or oversized mandatory entry can exceed the budget alone; all rules remain intact and a diagnostic explicitly reports that direct visibility is not guaranteed.

| Original obligation | Resident firing instruction | Retained detail |
| --- | --- | --- |
| Deliverable routing, host-authored prechecks, explicit user-selected skills | Entry paragraph and complete owner map | Original routing map and authorship test |
| Resume classification, durable plan, architecture versus implementation, owner firing | Transitions paragraph and canonical product gates | Original transition and lifecycle clauses |
| Delegation controller loads owner before dispatch | Transitions paragraph | Original delegation and owner-dispatch rules |
| Isolated checkout before implementation; cleanup after integration | Isolation paragraph | Full worktree and cleanup conditions |
| User goal scope, executable merge protocol, revocation, no forged grants | Authorization paragraph | Original authority/protocol exceptions |
| Four design security questions | Resident questions and canonical pointer | Original question predicates |
| External content is untrusted; sandbox and egress boundaries | Trust and safety paragraph | Full source-authority and sandbox clauses |
| Credentials, live/production data and resource-owner permission | Trust and safety paragraph | Original resource exceptions |
| Inspect destructive target, recovery and scoped risk acceptance | Trust and safety paragraph | Original destructive/recovery conditions |
| Repo-attributed historical evidence and durable artifacts | Recovery paragraph | Full recovery and source-register rules |
| Established user direction, cross-model caveat | User direction paragraph | Original direction and missing-context test |
| Verification, baseline failures, no unsupported completion claims | Completion paragraph | Full verification and completion rules |
| Independent review and review of later changes | Completion paragraph and canonical references | Original review obligations |
| Chunked full reads, repeated corrections and firing mechanism | Read discipline and transitions | Original blocked-source-read and extraction clauses |

## Verification record

Baseline hook suites passed 787 assertions but missed the native patch/transcript shapes. New input fixtures fail 22 assertions against the base; the normalized implementation passes all 10 test cases plus the existing isolation, delegation and owner-dispatch suites. A Unicode filename that hid a protected symlink target was separately reproduced and fixed. Move-target deletion and incomplete skill-read mutations fail their regression checks.

Startup baseline exceeded direct context and omitted resume/fork. Additional fixtures reproduce unresolved deferred-policy paths and oversized recovery output; the suite covers complete frame preservation and the directly visible delivery handoff cue. Canonical pointer and security-question subset checks pass.

Doctor tests reproduce the prior trusted-inventory exit-code mismatch. Its native protocol fixtures check complete handler and cache provenance, trust categories, disabled/missing handlers, bounded output, timeout and child cleanup. Trusted inventory is explicitly not runtime-effect evidence.

Final repository, package, installed-host, independent review/challenge and publication results are recorded after the integrated candidate is frozen. No partial or still-running check counts as passed.

## Delivery handoff correction

The `proposed-next:` rule existed only in the product workflow; no startup reminder or Stop backstop made it observable after a missed load or compaction. Add a compact startup cue and a bounded Stop formatter. This addresses missing handoffs, not goal execution or authorization.

The formatter uses the host's current `last_assistant_message`, never a stale final message from a transcript. It fires only with product-delivery evidence: completed product owner, a prior assistant handoff, or successful tool output exposing the complete continuation contract. Contract visibility is an advisory scope signal, not proof that a whole skill was loaded. Missing or unverifiable scope remains quiet. A static repair reason requests one truthful action/scope line, permits `none — status only`, preserves the user's active goal/stop/output format, and cannot create authority. `stop_hook_active` prevents repeated repair loops within the turn.

Claude and Codex supply the direct final-message field. OpenCode's current idle adapter does not; it passes an explicit null and leaves the formatter unverified. All three hosts receive the startup cue. Tests must distinguish missing labels from quoted examples, successful from pending/error/truncated rule reads, and format repair from permission to continue.

The formatter's absent-hook baseline fails 31 assertions. Its 18 cases pass, including direct-message precedence, final-answer phases, quoted examples, pure artifacts, matched successful rule reads, malformed inputs and nonregular transcript files. Three isolated mutations fail when loop prevention, successful-read checks or direct-message precedence are removed. A bounded transcript scan discards partial evidence and reports unverified when its limit is exceeded. Unsupported result envelopes remain unverifiable.

Native Claude and Codex checks use disposable plugins and an isolated loopback-only provider. Four cases per host prove actual Stop input, block/reason consumption, the subsequent model request and the loop flag. They establish the host roundtrip, not real-model adherence rates. Native trust inspection, packed asset checks and three-host installation lifecycle checks remain distinct evidence.

Independent review and challenge cover three partitions: authorization; shared runtime and startup; package and host installation. Together they cover the initial candidate. Subsequent changes receive a delta pass from that reviewed commit. Partition scope gaps are checked against the union, not treated as a verdict on omitted files. Session-wide status-only formatting follows the canonical product workflow and preserves explicit stop; it never authorizes another task. Detailed receipts and finding dispositions are retained outside shared Git surfaces.

The CLI doctor surface uses the existing JSON and terminal result interface; no screen or interaction layout changes. Consumers are the CLI caller and the three existing host adapters. Unknown and untrusted statuses retain their explicit result codes; a trusted inventory never asserts hook execution.

Security posture: authorization semantics and input parsing change, so dedicated security review remains pending. Independent code review/challenge and synthetic negative tests provide bounded engineering evidence, not a security audit. Shipment follows the explicit patch-release direction and retains these evidence limits; no protection or trust settings are changed by the product.
