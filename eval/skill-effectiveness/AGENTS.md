# skill-effectiveness Agent Contract

This directory implements the causal-evaluation foundation: frozen arms and
gates, private trial artifacts, blinded comparisons, isolation checks, and the
explicit Codex capability probe. It inherits `../AGENTS.md`; only local deltas
follow.

## Boundaries

- Treat `arms/`, fixtures, schemas, task sets, and `pilot-gates.json` as
  pre-registered protocol inputs. Freeze them before outcomes are visible; do
  not weaken missing evidence into a passing status.
- Persist trial output only under an explicit private root outside the source
  checkout. Preserve the 0700/0600 and separate read/write-root contracts; an
  out-of-scope access or cross-trial canary leak contaminates the trial.
- `provider-probe` is the only live capability adapter here. It sends only an
  isolation canary, uses an exact executable/model and independent read-only
  ephemeral sessions, audits the JSON event stream, and rejects tool activity.
  A completed no-recall observation must remain
  `isolation_outcome=unresolved_isolation_threat` and
  `causal_core_unavailable`; never report it as isolated or passing. Changing
  either mapping or its locking test requires independent review/challenge
  evidence.
- `reviewer-calibration` is a separate advisory live adapter for committed
  generic A/B cases. Codex, Claude, OpenCode and Kimi paths must keep exact
  executable/model binding, fresh non-persistent sessions, provider-side truth
  withholding and tool-surface auditing. Codex and Claude prompts stay on
  stdin. Claude must reuse the
  `code-review` runtime validator, require `--no-session-persistence`, and bind
  every init event to the requested exact model; do not substitute the
  default-model consult wrapper. OpenCode must use its dedicated
  `reviewer-calibration` agent, an explicit `providerID/modelID`, private XDG
  data/state roots, the shared login file only, and public `run`/`export`
  evidence. Its strict calibration JSON is parsed locally; do not import the
  `code-review` finding parser or derive the model from `ccl-review`.
  Kimi must use an explicit configured model alias, a private
  `KIMI_CODE_HOME`, a sanitized one-model/one-provider config with a first-match
  deny-all permission rule, empty skills, and strict `stream-json` auditing.
  Only login-state paths may be linked from the normal Kimi home. Accept at
  most one bare JSON object or one exact JSON code fence with no surrounding
  text; do not import the `code-review` finding parser or call its Kimi wrapper.
  Freeze the selected Kimi config once for every repeat, seal its provider id,
  underlying model and config hash, and strip credentials for unrelated
  providers from OpenCode/Kimi child environments. Kimi aliases need not use
  OpenCode's `providerID/modelID` slash form. Label Kimi tool evidence as
  detection-only: deny-all config is a prevention request, while stream audit
  proves only observed events and cannot prove a rejected tool caused no prior
  side effect.
- `reviewer_calibration_protocol.py` is the controller-facing single-sample
  interface and currently supports only Codex. `sample` must validate the
  absolute executable, exact model/family, timeout, one-call cost limit and
  runtime manifest before starting one model call. Persist an exclusive 0600
  v2 ledger reservation and intent before the call, transition the ledger to
  `model_call_started` before invoking the provider, and bind the completed
  intent to the 0600 sample hash. Only the same sample may reclaim a valid,
  ledger-only `reserved` entry; legacy v1 ledgers are accepted only with an
  already completed intent and sample. A `model_call_started` ledger or intent
  never authorizes retry.
  Codex sample and final receipts must record
  `tool_access=read-only-observed-none`: the sandbox flag is requested
  configuration and the stream proves only that no tool event was observed.
  Serialize the complete `sample` and `finalize` lifecycles per artifact root
  with one private owner-only file lock, so receipt-set validation observes a
  quiescent root rather than another invocation's ledger/intent transition.
  A finalization intent closes the root to later samples. Transient lock
  acquisition failures return `sample_lock_unavailable`; reserve
  `artifact_root_quarantined` for unsafe lock artifacts or inconsistent
  receipts.
  Reject every new sample before provider invocation when ledger, sample and
  intent ID sets differ outside the single reserved-ledger recovery case, or an
  existing ledger/sample/intent set is unreadable, invalid or not completed.
  `finalize` starts no model and accepts only the exact two-to-five sample set
  with one runtime/reviewer binding. Unknown finality, replay, drift, binding
  mismatch or an unowned partial pair fails closed. An exact finalize retry may
  resume `publication_started` before output claim while all publication files
  are absent. The intent's random claim token must match the owner-private lock.
  After a verified `output_claimed` intent, an exact complete canonical pair
  only advances the intent to completed; otherwise valid owner-private partials
  may be overwritten through the same staged fail-closed publication step
  without a model call. A symlinked calibration directory, invalid, symlinked or
  non-private publication file, completed finalization and a different binding
  never republish. There is no migration path for a finalization intent without
  a claim token; it returns `finalize_already_started` and requires a new private
  root. A complete mismatched pair returns the same terminal reason. A matching
  `output_claimed` intent may recreate its missing token-bound lock; an exact
  canonical pair may remove validated owner-private staged leftovers before
  completing. If either fixed pending path is unsafe, repair or remove that
  exact path before retrying; recovery never touches it. JSON stdout and typed
  errors must not expose paths, prompts, judgments or credentials.
- Publish reviewer evidence and its result as one fail-closed pair: validate
  both hidden staged files first, then expose canonical names. Any exception
  before both canonical files exist must remove staged and partial canonical
  artifacts; the one-shot claim may remain. Block trappable termination signals
  across the two renames and consume a signal observed in that critical window
  before cleanup. `SIGKILL` or host crash can still leave a partial pair, which
  is invalid because sealed loading requires both canonical files.
- Preserve synthetic-smoke semantics: it makes no live model calls and exits
  `3` when contract-complete but intentionally not evaluated.
- Active-control candidates must come from two people who did not write the
  evaluated skill and must bind the same brief plus both `subagent` and `main`
  scopes. Collaboration subagents that loaded CCL skills may review the
  protocol but must not author candidates or perform the blind selection.
  Keep candidate provenance and controller state outside selector input; a
  selected manifest requires the sealed selection artifact and exact scope
  content hash. Hashes bind recorded bytes and declarations, not real-world
  identity, independence or external pre-outcome time. Matched-call evidence
  must use one evaluator and event contract for Active-control and Oracle; only
  target bundle ids and content hashes may differ. Its deterministic fixtures
  do not prove live host installation or enforcement. The machine contract must
  produce fixture-pass only when an ordered matching call precedes the first
  task-tool event; skill invocation indexes and that first task-tool index must
  be globally unique, and invocation `tool_use_id` values must not repeat. It
  must never expose a live-gate allow. The
  active-control bundle id must derive from the selected opaque slot plus scope;
  the Oracle id must derive from its scope. Fixture-only contract artifacts must
  not become arm-manifest statuses and do **not** satisfy the Oracle-equivalent
  matched-call entry gate. That gate stays unsatisfied until authenticated live
  host enforcement evidence exists. Keep committed `Sg/Mg` pending until real
  candidates, blind selection, owner-relative checks, that live matched-call
  gate and provider capability all satisfy the frozen gates.

- The **advisory verdict is a distinct typed verdict kind**, never a weakened
  causal one. `causal_core_unavailable` stays non-passing for every causal
  request; only an `advisory-paired` request may proceed without the enumerated
  isolation evidence, and it must carry its coverage limitations verbatim in
  every receipt, report and activation record. Exactly six items are waivable —
  mount evidence, complete access audit, access-root enforcement,
  memory-isolation proof, provider-side persistence proof and the live
  matched-call gate — and a waiver covers **missing proof only**: an
  observed `isolation_violation`, contamination or blinding leak fails the trial
  at either tier. `replicated-advisory` is a class-level property over several
  machines' terminal verdict summaries, never a third verdict kind, and a
  verdict's tier is immutable: advisory results may never be relabeled,
  aggregated or averaged into a causal claim, and a synthetic run satisfies
  neither tier. A trial that requests the advisory tier must use the
  paired-profile registry; a causal request must use the skill-content registry.
  Enforce that registry-to-tier binding inside both trial checkpoint and
  completed-replay paths as well as in any bridge or controller, so neither a
  direct caller nor a persisted isolation record can select a weaker tier.
  Current-format completion also binds the terminal state, isolation receipt,
  events and access audit with `completion_binding_hash`; replay rejects drift.
  This detects accidental local mutation, not a hostile trusted-owner rewrite.
  Explicitly observed memory or persistence state — false fresh-session,
  enabled fork/recall/cache/memory, or enabled provider persistence — is
  contamination and cannot use an advisory waiver. Only absent, null or
  unverified proof may become a coverage limitation.
  Until this amendment is in force, implementations reject advisory verdicts.
- The **paired-profile arm registry** is a separate contract from the
  skill-content registry, which stays unchanged with its required causal
  treatments. A profile registry freezes exactly one `off` (the built-in
  profile) and one `full` (the candidate), plus an optional frozen `reference`
  arm, all in one scope; the only allowlisted treatment component is the profile
  payload, and every other input — task-builder template, task, driver, model,
  prompt template, permission profile — is pinned identical across the pair. One
  plan may never mix the two registry contracts. Reviewers stay blinded: arm
  identity, profile text and manifest hashes never enter a judge payload, even
  though the tested agent necessarily sees the profile, which is the treatment.
- `bridge.py` is the only cross-repository surface. It reads one JSON request on
  stdin, writes one JSON response on stdout, keeps diagnostics on stderr, and
  exits `0`/`3`/`2`/`4` for ok/blocked/invalid-input/internal failure. It reuses
  `trial.py` and must never call a model, select a provider, start a shell, open
  a socket, or modify skills. Its reason codes are a closed set and carry no
  path, prompt, task content, model output or source text; responses carry no
  absolute private-store path. The pinned runtime manifest enumerates every
  evaluator code and configuration file: the first probe only enumerates and
  hashes bytes without importing an evaluator module, the host re-hashes each
  entry before pinning it, and configuration plus supported actions are accepted
  only from a second probe under that pinned manifest. Manifest drift is
  `unsupported_evaluator`. Repeating a request id with an identical binding
  replays the stored receipt; a different payload under that id is `stale_state`.
  A completed checkpoint must explicitly declare both
  `access_audit_complete` and `access_roots_enforced`; omission must not imply
  that either proof is complete.
- `skill-event-fixtures-v2.json` holds the hand-authored `skill-events-v2`
  transcript known answers that external extractors pin. Expected values are
  never generated from parser output, transcripts stay sanitized, and each
  driver keeps its own shape: `claude-code` pairs a skill tool call with a
  separate result, `opencode` records the call and its terminal status in one
  entry. Any unregistered shape, or a missing invocation field, degrades to
  `invocation_unverifiable` and never becomes a compliance pass. Registering a
  driver requires a sanitized known-answer case authored from an observed
  transcript plus a recorded shape note — a listing-only edit is rejected by the
  fixture test — and unregistered never asserts that a driver emits no
  observable invocation evidence. Two contract questions stay open and are
  pinned by boundary cases rather than silently resolved: skill identities are
  namespaced on one driver and bare on another, and this contract's global
  `tool_use_id` uniqueness rule is violated by a real driver that reuses a short
  literal id across sessions.

## Validation

After the root validation block passes, run these local checks from the
repository root:

```bash
(
set -euo pipefail
python3 -m unittest -v eval.test_skill_effectiveness_trial
python3 -m unittest eval.test_skill_effectiveness_bridge
python3 -m unittest eval.test_reviewer_calibration_protocol
python3 -m unittest \
  eval.test_skill_effectiveness_trial.ProfileRegistryAndEvidenceTierTest
python3 -m unittest \
  eval.test_skill_effectiveness_trial.SkillEventsV2FixtureTest
python3 -m unittest \
  eval.test_skill_effectiveness_trial.TrialFoundationTest.test_provider_probe_persists_no_leak_evidence_without_false_promotion
python3 -m unittest \
  eval.test_skill_effectiveness_trial.TrialFoundationTest.test_claude_reviewer_calibration_reuses_code_review_safety_contract
python3 -m unittest \
  eval.test_skill_effectiveness_trial.TrialFoundationTest.test_opencode_reviewer_calibration_uses_native_session_evidence_without_review_parser
python3 -m unittest \
  eval.test_skill_effectiveness_trial.TrialFoundationTest.test_kimi_reviewer_calibration_uses_private_native_stream_without_review_parser
python3 -m unittest \
  eval.test_skill_effectiveness_trial.TrialFoundationTest.test_active_control_cli_prepares_finalizes_and_verifies_private_artifact
smoke_out="$(mktemp -d "${TMPDIR:-/tmp}/ccl-skills-e10-smoke.XXXXXX")"
smoke_rc=0
python3 eval/skill-effectiveness/run.py smoke \
  --fixture eval/skill-effectiveness/fixtures/e10-smoke.json \
  --out "$smoke_out" || smoke_rc=$?
test "$smoke_rc" -eq 3
)
```

The bridge suite spawns the real interpreter, because import-level tests would
prove nothing about the process contract the external consumer depends on. The
two focused classes lock the paired-profile registry, the tiered verdict path
and the `skill-events-v2` known answers.

The full suite drives fake Codex, Claude, OpenCode and Kimi executables, including
exact model binding, runtime-surface validation and tool-event rejection. The
focused tests lock the no-recall status mapping, Claude safety contract and
OpenCode/Kimi session contracts plus the active-control one-shot CLI without a
live model call. The final assertion locks smoke exit `3` for the committed fixture. See
`eval/skill-effectiveness/README.md` for the full contract.
