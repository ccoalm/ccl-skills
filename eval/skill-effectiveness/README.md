# Skill-effectiveness trial foundation

This directory contains the advisory runtime foundation for `spec 011` Slice 4.
It freezes treatment inputs, prepares private trial artifacts, checks isolation
evidence, builds blinded A/B inputs, schedules repeated trials and evaluates the
pre-registered E10 pilot gate.

The foundation primitives do not call a model, choose a reviewer family,
enforce a merge gate, or promote a candidate. Two explicit live commands remain
narrow: `provider-probe` sends an isolation canary, while
`reviewer-calibration` sends only committed generic known-answer cases. Neither
command runs a skill-effectiveness trial.

## Active-control preparation

`active-control.py` and the eight `active-control-*` commands prepare the
`Sg/Mg` generic-guidance selection without making a model call. They do not
create a candidate, decide that two authors are independent, prove an external
pre-outcome timestamp, or make either arm runnable.

Two people who did not write the evaluated skill first use the same frozen
brief to create separate candidate packages with
`freeze_active_control_candidate`. Each package contains both `subagent` and
`main` guidance plus controller-private hashes for the author's commitment and
independence attestation. Those hashes record declarations; they do not prove
identity or real-world cognitive independence. Keep candidate packages in 0600
files outside the source checkout.

Before selection, freeze both Oracle scope contents with
`freeze_owner_reference` and keep that 0600 JSON outside the checkout. After
the controller has validated both candidates, create the blinded selector
packet in a new private root:

```bash
python3 eval/skill-effectiveness/run.py active-control-freeze-owner-reference \
  --subagent /private/path/oracle-subagent.md \
  --main /private/path/oracle-main.md \
  --out /private/path/owner-reference.json
python3 eval/skill-effectiveness/run.py active-control-prepare \
  --brief /private/path/brief.json \
  --rubric /private/path/rubric.json \
  --constraints /private/path/constraints.json \
  --owner-reference /private/path/owner-reference.json \
  --candidate /private/path/candidate-a.json \
  --candidate /private/path/candidate-b.json \
  --out /private/tmp/ccl-skills-active-control
```

Give the calibrator only `selector-input.json`. Do not give it
`controller-state.json`, candidate provenance, CCL skills, held-out data,
trial artifacts or outcomes. The returned 0600 decision must contain exactly
the selector input hash, rubric hash and one opaque id. Seal and read it back:

```bash
python3 eval/skill-effectiveness/run.py active-control-finalize \
  --out /private/tmp/ccl-skills-active-control \
  --decision /private/path/selector-decision.json
python3 eval/skill-effectiveness/run.py active-control-verify \
  --selection /private/tmp/ccl-skills-active-control/active-control-selection.json
```

After selection, publish and verify the owner-relative measurement with that
same precommitted Oracle reference:

```bash
python3 eval/skill-effectiveness/run.py active-control-measure \
  --out /private/tmp/ccl-skills-active-control \
  --owner-reference /private/path/owner-reference.json
python3 eval/skill-effectiveness/run.py active-control-measure-verify \
  --selection /private/tmp/ccl-skills-active-control/active-control-selection.json \
  --owner-reference /private/path/owner-reference.json \
  --measurement /private/tmp/ccl-skills-active-control/owner-relative-measurement.json
```

Then freeze and verify the paired matched-call contract for one scope. Both
targets use the same fixture evaluator, event contract, denial template and
fixture-pass semantics. The seven full expected result shapes are frozen inside
the gate spec, including decision/reason, rendered denial, observation status
and live-gate eligibility; only the bundle id and frozen content hash may differ:

```bash
python3 eval/skill-effectiveness/run.py active-control-matched-call \
  --out /private/tmp/ccl-skills-active-control \
  --selection /private/tmp/ccl-skills-active-control/active-control-selection.json \
  --measurement /private/tmp/ccl-skills-active-control/owner-relative-measurement.json \
  --owner-reference /private/path/owner-reference.json \
  --scope subagent \
  --active-bundle-id "${SELECTED_OPAQUE_ID}-subagent" \
  --oracle-bundle-id oracle-owner-subagent \
  || test "$?" -eq 3
python3 eval/skill-effectiveness/run.py active-control-matched-call-verify \
  --selection /private/tmp/ccl-skills-active-control/active-control-selection.json \
  --measurement /private/tmp/ccl-skills-active-control/owner-relative-measurement.json \
  --owner-reference /private/path/owner-reference.json \
  --evidence /private/tmp/ccl-skills-active-control/matched-call-evidence-subagent.json \
  || test "$?" -eq 4
```

Set `SELECTED_OPAQUE_ID` to the exact `decision.selected_opaque_id` from the
sealed selection. The active bundle id must be that opaque id plus `-<scope>`;
the Oracle id must be exactly `oracle-owner-<scope>`. Free-form labels are
rejected so author provenance cannot re-enter the frozen manifest. The ordered
`skill-events-v2` projection requires stable skill and task-tool event streams,
an event index on every invocation, and the first task-tool index. Those indexes
share one namespace and must be globally unique. The evaluator
returns `fixture-pass` only when the completed exact target call is strictly
earlier; it never returns a live-gate `allow`. Degenerate ordering windows are
rejected. Invocation `tool_use_id` values are also globally unique. Every deny
for a valid target bundle id renders the hash-bound denial template with its
exact bundle id, including when the event record is malformed. Malformed target
bundle ids fail closed without a rendered denial. The record must declare
`fixture-modeled-single-monotonic-stream`; the
hash-bound contract recomputes the embedded gate-contract hash and marks its
indexes as fixture-asserted and live-gate-ineligible. The
artifact status is `matched-call-contract-declared-no-observation` and its
`observation_status` is `none-fixtures-only`; the explicit machine field
`matched_call_gate_satisfied` is `false`. It records a deterministic
contract declaration, not observed call behavior, and is never copied into an
arm manifest. A successful freeze emits `artifact_write_status=created`; do not
retry it, because publication is intentionally one-shot. Its `evidence=` output
contains only the scope filename, not the controller-private root; matched-call
error output also redacts every controller-private path argument. Freezing or
verifying this artifact emits `matched_call_gate=NOT_SATISFIED`; freeze exits
`3`, while read-only verify reports
`artifact_write_status=not-applicable-read-only` and exits `4`. A valid fixture
artifact therefore cannot be mistaken for entry-gate satisfaction by an
exit-code-only controller. Every embedded fixture result repeats
`observation_status=none-fixtures-only` and `live_gate_eligible=false`; consumers
cannot treat a bare `fixture-pass` as gate satisfaction. A future live gate
requires a new versioned contract and artifact rather than mutating this fixture
contract.
Run the freeze command once per scope; the same private root can hold
`matched-call-evidence-subagent.json` and `matched-call-evidence-main.json`,
and each file is bound to its filename scope.

Preparation requires exactly two different, same-brief, two-scope packages,
distinct author commitments and attestations, bounded content and no known
reserved organization surface. The brief accepts only `schema_version`, sorted
`task_families` and one neutral `instruction`; the rubric is fixed to
readability, actionability and information density. Reserved provenance,
provider, model and controller metadata is rejected recursively. The command
creates random opaque ids, strips generation evidence from selector input,
binds every candidate/rubric/constraint/decision hash plus the Oracle reference
hash, and permits one final selection. Canonical files are staged and published exclusively; controller
state is durable before `selector-input.json` becomes visible. A selected arm
manifest requires a passing sealed measurement and binds the selection,
precommitted Oracle reference, request and exact selected scope content hashes.

The measurement requires both scopes to pass all three inclusive ±10% checks.
CRLF and CR first normalize to LF. Paragraphs are non-empty blocks separated by
ASCII blank lines, instructions are Markdown list-item lines, and tokens are
contiguous ASCII word runs or each remaining Unicode non-whitespace code point. Integer
cross-multiplication avoids float drift. The
artifact records algorithm versions, hashes and counts, but not Oracle content.
Within one preallocated, intact controller-private root, the first measurement attempt is
exclusive: pass or fail is written as a 0600 artifact. Deleting that artifact
invalidates the evidence set; it is not an append-only ledger. The prepare-time
commitment prevents retrying with a different Oracle reference in that root.
Creating another root for the same candidate pair is policy-invalid, but an
intact copied root is locally indistinguishable: detecting cross-root reuse
requires an external registry. This local protocol is not a boundary against a
malicious controller.
These structural checks do not prove semantic equivalence or absence of
ccl-specific guidance. Matched-call evidence proves only the deterministic
contract and paired fixture behavior; it does not prove that a real host
installed or enforced the gate. No real candidates or live host enforcement
evidence exist, so committed `Sg/Mg` templates remain `pending` and
non-runnable, and `causal_core_unavailable` continues to block real trials.

## Synthetic smoke

Run the deterministic foundation smoke without provider credentials or model
calls:

```bash
python3 eval/skill-effectiveness/run.py smoke \
  --fixture eval/skill-effectiveness/fixtures/e10-smoke.json \
  --out /private/tmp/ccl-skills-e10-smoke
```

The smoke creates 18 synthetic trials: two known-regression tasks, three arms
(`S0/S1/S2`) and three samples. Artifact construction is reported as
`execution_status=completed`; it is not a gate pass. Automated reviewer
calibration, provider capability, host access/memory audit, matched-call,
blinded replay and real budget evidence are reported under
`pilot_gate_status=not_evaluated_synthetic`, never as passing values. The
command intentionally exits `3` so an exit-code-only caller cannot mistake the
result for a green gate. `live_model_calls` remains `false` and the output is
always `advisory`. The gate evaluator permits synthetic not-evaluated semantics
only when the caller explicitly sets synthetic mode; a calibration label alone
cannot downgrade missing evidence. Synthetic access/memory success and a zero
contamination rate also remain not evaluated; an injected path or memory
violation still fails the smoke instead of being hidden by that boundary.

## Codex provider capability probe

Run the probe with an exact model id and a new private output root outside the
source checkout:

```bash
python3 eval/skill-effectiveness/run.py provider-probe \
  --provider codex \
  --codex-path /absolute/path/to/codex \
  --model <exact-model-id> \
  --task-family plan \
  --out /private/tmp/ccl-skills-provider-probe
```

The command starts two independent `codex exec` processes with `read-only`,
`ephemeral`, ignored user configuration, no resume path and JSON event auditing.
The first process acknowledges a random canary. The second prompt does not
contain that canary and reports whether it can recall one. Prompts travel on
stdin. Adapter-owned prompts, event streams and model messages are deleted with
the temporary session directories; the phase `TMPDIR` also points there. The
CLI still receives `HOME` for local authentication, so host/provider persistence
remains unverified. The persisted 0600 report contains only the canary hash, an
optional recalled-value hash, exact executable hash, provider/model/CLI binding,
environment-key allowlist, observations and the capability-matrix result. Each
output root is one-shot: a 0600 exclusive claim prevents concurrent probes or
retries from mixing evidence. Use a new root after any completed, failed or
interrupted attempt.

Provider stdout and stderr are drained while the child runs and stopped at
fixed byte limits; this prevents an untrusted provider process from filling the
host before post-run validation. Failed lifecycle events and stderr are mapped
to bounded reason codes such as `quota_unavailable`; raw provider errors are not
copied into the report or CLI error. The CLI and report expose
`isolation_outcome=contaminated` when any prior canary is returned, otherwise
`isolation_outcome=unresolved_isolation_threat`. A clean observation is not an
isolation proof.

Exit `0` means the probe and artifact read-back completed. It does not mean the
task family is eligible: a no-leak observation remains
`causal_core_unavailable` while mount denial, complete access auditing or
provider-side persistence disabling is unproved. A detected leak is also a
completed negative observation, not a tool crash.

Some restricted parent sandboxes block Codex's stdin app-server initialization.
In that case, rerun the unchanged command through the approved host execution
path. Do not move the canary to argv to bypass the restriction.

## Reviewer calibration

Collect two repeated raw judgment sets from one explicitly named reviewer
family. The Codex path is:

```bash
python3 eval/skill-effectiveness/run.py reviewer-calibration \
  --provider codex \
  --codex-path /absolute/path/to/codex \
  --model <exact-model-id> \
  --reviewer-family <stable-family-id> \
  --repeats 2 \
  --out /private/tmp/ccl-skills-reviewer-calibration
```

The Claude path requires the canonical `claude` family and an exact model id:

```bash
python3 eval/skill-effectiveness/run.py reviewer-calibration \
  --provider claude \
  --claude-path /absolute/path/to/claude \
  --model <exact-model-id> \
  --reviewer-family claude \
  --repeats 2 \
  --out /private/tmp/ccl-skills-claude-calibration
```

The OpenCode path requires an explicit `providerID/modelID`; the reviewer
family is the provider id:

```bash
python3 eval/skill-effectiveness/run.py reviewer-calibration \
  --provider opencode \
  --opencode-path /absolute/path/to/opencode \
  --model <provider-id>/<exact-model-id> \
  --reviewer-family <provider-id> \
  --repeats 2 \
  --out /private/tmp/ccl-skills-opencode-calibration
```

The Kimi path requires a model alias present in the logged-in Kimi config and
uses the canonical `moonshot` reviewer family:

```bash
python3 eval/skill-effectiveness/run.py reviewer-calibration \
  --provider kimi \
  --kimi-path /absolute/path/to/kimi \
  --model <configured-model-alias> \
  --reviewer-family moonshot \
  --repeats 2 \
  --out /private/tmp/ccl-skills-kimi-calibration
```

The command uses the committed case and truth fixtures plus the committed pilot
thresholds. Only case tasks, rubrics and A/B candidates enter the prompt;
`expected_verdict` rows stay controller-side. Each repeat runs in a fresh
`--ephemeral`, `read-only` Codex process with ignored user configuration and JSON
event auditing. Any tool event, missing or duplicated case, invalid verdict,
provider failure or incomplete response stops without a success report.

The Claude adapter follows the existing `code-review` safety contract without
calling its fixed review/consult wrapper. It requires no tools except Claude's
internal `StructuredOutput`, strict empty MCP configuration and setting
sources, safe mode, disabled skills/commands, `--no-session-persistence`,
structured stream capture and the committed `code-review` runtime-surface
validator. The prompt travels on stdin. Every stream init must report the exact
requested model; an alias expansion, fallback, missing isolation flag, unknown
runtime surface or extra tool fails closed. `USER` and `LOGNAME` are retained
alongside `HOME` so the macOS OAuth/Keychain login path remains available;
reports record environment key names, never credential values.
The report label `provider=claude` identifies the Claude CLI/client path; it
does not by itself prove the upstream API backend, regional routing or data
residency.

The OpenCode adapter is independent of `code-review` response parsing. It
creates a temporary `reviewer-calibration` agent with every tool disabled,
passes the requested model explicitly, and gives each repeat private XDG
data/state roots. If the normal OpenCode `auth.json` exists, only that file is
linked into the private data root so an existing login remains usable. The
committed calibration schema and cases travel in the generic CLI prompt; truth
does not. The adapter then binds the public event stream to `opencode export`,
requires the dedicated agent and exact provider/model on the exported session
and every assistant message, rejects tool activity or a non-`stop` finish, and
parses the final text as one strict JSON object. It neither invokes the
`code-review` finding parser nor derives a model from `ccl-review`.

The Kimi adapter borrows only the bounded CLI transport lessons from
`code-review`; it does not invoke `kimi_review.sh` or its review-result parser.
Each repeat gets a private `KIMI_CODE_HOME`, workspace and empty skills
directory. The adapter freezes one selected model/provider config for every
repeat, prepends
a deny-all permission rule, links only the existing login-state paths, passes
the configured model alias explicitly and audits every `stream-json` event.
Unrelated provider credentials such as `OPENAI_API_KEY` are removed from Kimi
and OpenCode child environments. The Kimi result seals the alias, local
provider id, underlying model and selected-config hash; the loader recomputes
the binding hash before accepting it.
Tool calls/results, unknown roles, reused sessions, partial output and prose
around the final payload fail closed. `tool_access` is recorded as
`config-denied-stream-audited-detection-only`: deny-all config requests
prevention, but post-run stream auditing cannot prove that an attempted tool
caused no side effect before detection. The final payload may be a bare JSON
object or Kimi's exact single `json` code fence; duplicate keys and any text
outside that fence remain invalid. Kimi CLI 0.27 does not expose stable
service-side actual-model attribution in this stream, so the report proves the
requested alias and sanitized local provider binding, not the upstream model
selected by the service.

The private one-shot output contains the raw judgments, recomputed
self-consistency and known-answer accuracy, and hashes binding the cases, truth,
pilot gates, runner, executable, CLI and exact model. The canonical case hash is
also frozen in `pilot-gates.json`, so another syntactically valid case fixture
cannot be substituted at collection or sealed read-back. Parent termination is
latched across the process-start window, reaps the provider process group and
does not leave successful artifacts; the child starts with the caller's normal
signal mask so graceful provider shutdown remains available. Exit `0` means that this
reviewer family passed the frozen calibration thresholds; exit `1` persists a
completed but failed calibration; exit `2` is an input, provider or contract
failure. A calibration pass is reviewer-validity evidence only. It does not open
the causal core, prove skill effectiveness, authorize a candidate, or authorize
merge, push, release or deployment.

Evidence and result publication is fail-closed as a pair. Both objects are
written and read back under hidden staged names before either canonical name is
published. A validation or publication exception removes both staged files and
any partially published canonical file; only the permanent one-shot claim may
remain. Trappable termination signals are blocked across the two canonical
renames; a signal observed in that window is consumed, both files are removed,
and operator termination is re-raised. A signal arriving after both renames may
leave a complete valid pair. `SIGKILL` or host crash cannot be trapped and may
leave a partial pair; sealed loading rejects it because both canonical files
are required.

### Single-sample calibration protocol

`reviewer_calibration_protocol.py` is the machine interface for controllers
that schedule one reviewer call at a time. It is separate from the
multi-repeat command above and from the model-free evaluator bridge. Requests
and responses are JSON on stdin/stdout; diagnostics never share stdout.

- `probe` returns the supported actions/providers and a runtime manifest binding
  the interpreter, protocol code, provider adapters, schemas, cases, known
  answers and pilot gates.
- `sample` currently accepts only Codex. The request fixes an absolute
  executable, exact model, reviewer family, timeout, runtime manifest and
  one-call cost limit. A successful request starts one fresh ephemeral,
  read-only call. The prompt contains only committed cases, rubrics and A/B
  candidates. Its receipt uses `tool_access=read-only-observed-none`: read-only
  is the requested configuration, while observed-none means the audited event
  stream contained no tool event. It does not claim that an attempted tool was
  prevented before an effect.
- Each sample uses exclusive 0600 ledger and intent records under a 0700
  artifact root. New v2 ledgers move from `reserved` to
  `model_call_started` before provider invocation. The same sample may reclaim
  only its valid ledger-only `reserved` state; a started ledger or intent never
  retries the model. Completed legacy v1 ledgers remain readable but cannot
  authorize recovery. A private owner-only lock serializes complete sample and
  finalize lifecycles for that root. Once finalization starts, later samples
  return `finalize_already_started`. The completed intent binds the sample
  hash; replay, unresolved finality, runtime drift and binding mismatch fail
  closed without another model call.
- `sample_lock_unavailable` is a recoverable lock-acquisition failure: resolve
  the local filesystem condition and retry on the same root.
  `artifact_root_quarantined` remains reserved for unsafe lock artifacts or
  inconsistent receipt state.
- `model_call_unresolved` and `sample_publication_failed` permanently quarantine
  that artifact root. Mismatched ledger/sample/intent ID sets and unreadable,
  invalid or non-completed sample intents do the same. A later sample returns
  `artifact_root_quarantined` before another model call; finalize returns the
  same reason for mismatched receipt sets. Keep the root as evidence and restart
  the complete calibration in a new private root. Do not delete receipts or
  reuse completed samples from the quarantined root.
- `finalize` starts no model. It requires two to five exact sample ids with one
  runtime/reviewer binding, loads the known answers locally, recomputes the
  frozen gates and publishes the existing evidence/result pair.
- `finalization_recovery_required` means publication or its final confirmation
  did not complete. An exact retry may resume a matching
  `publication_started` intent before output claim while all publication files
  are absent. The intent's random claim token must match the owner-private lock.
  For a matching `output_claimed` intent, retry validates the private
  `calibration/` directory and the four exact staged/canonical JSON paths. An
  exact complete canonical pair is preserved byte-for-byte and only the intent
  advances to completed; otherwise valid owner-private partials may be
  overwritten through the same staged fail-closed publication step without a
  model call. A symlinked `calibration/` directory remains blocked. A
  pre-existing `calibration/` directory must be owned by the caller and have
  mode `0700`; repair it or use a new private root before retrying. A symlinked,
  non-regular, non-owner-private or invalid JSON file remains blocked and
  untouched. While
  the intent is still `publication_started`, keep an owner-private lock whose
  `claim_token` matches the intent. Resolve or remove only a malformed,
  external or token-mismatched pre-claim lock before retrying. A matching
  `output_claimed` intent recreates a missing token-bound lock. An exact
  canonical pair removes validated
  owner-private staged leftovers before completing. If either
  `.reviewer-calibration-result.pending.json` or
  `.reviewer-calibration.pending.json` is unsafe, repair or remove that exact
  path before retrying; recovery leaves it untouched. There is no migration
  path for a finalization intent without a claim token: it returns
  `finalize_already_started` and requires a new private root. A complete
  mismatched pair returns the same terminal reason.

The wire schemas are
`protocol/reviewer-calibration-request-v1.schema.json` and
`protocol/reviewer-calibration-response-v1.schema.json`. Exit `0` is `ok`, exit
`2` is invalid input, exit `3` is a typed blocked result and exit `4` is an
internal failure. Responses expose opaque artifact names and hashes, not
absolute artifact paths, prompts, judgments or credentials.

## Local evidence entrypoints

The foundation read-back APIs remain offline and provider-neutral. A controller
writes probe, plan and pilot evidence under its private output root, then calls
the matching API:

- `write_capability_probe_artifact` followed by
  `assess_capability_matrix_from_artifacts`;
- `write_arm_registry_plan` before outcomes, then `blind_pair` or
  `build_pair_mapping` with `registry_plan_path`; and
- `write_pilot_evidence_bundle` followed by
  `evaluate_pilot_gate_from_artifacts`.

`reviewer-calibration` produces the raw `reviewer-calibration.json` object that
the later private pilot bundle consumes; its companion result records provider
provenance and the independently recomputed calibration metrics.

The in-memory capability and non-synthetic E10 entrypoints validate shapes but
cannot return `ready` or `pass`. Synthetic smoke keeps its direct in-memory
path and exit `3`. These read-back APIs require no provider allowlist, network
service, signature, human approval or credential. Explicit live adapters use
the caller's existing local CLI authentication.

The trust boundary is the current OS user, the controller code and its private
local artifact root. The contracts prevent accidental self-attestation,
evidence mixing and partial read-back. They do not defend against the local
owner deliberately changing the artifacts or evaluator code; that owner can
always bypass a local-only system.

## Evaluator bridge

`bridge.py` is the deterministic process interface an external controller uses.
It reads one JSON request on stdin, writes one JSON response on stdout, keeps
diagnostics on stderr, and exits `0` for `ok`, `3` for a typed `blocked` result,
`2` for invalid input and `4` for an I/O or internal failure. The wire contract
lives in `protocol/request-v1.schema.json` and `protocol/response-v1.schema.json`;
`test_skill_effectiveness_bridge.py` asserts that those files and the
implementation agree on actions, statuses and the closed reason-code set.

Start-up is two-phase, so nothing evaluator-owned is imported before the caller
has pinned it:

1. `probe` with `{"phase": "manifest"}` enumerates and hashes every evaluator
   code and configuration file as bytes and imports no evaluator module. The
   caller re-hashes each returned entry itself before pinning it.
2. `probe` with `{"phase": "full", "pinned_manifest": …}` revalidates the pinned
   entries against disk, loads `trial.py` by absolute path — so no ambient
   `PYTHONPATH` package can replace it — and only then returns configuration
   identity and supported actions. Any drift is `unsupported_evaluator`.

`prepare`, `checkpoint` and `evaluate` reuse `trial.py` under a validated
absolute private `artifact_root` outside this checkout. `evaluate` does not
serve reviewer calibration: `reviewer_calibration_prompt` and
`reviewer_calibration_finalize` are both rejected with `protocol_mismatch`
before any calibration artifact is created. Calibration is served only by
`reviewer_calibration_protocol.py`, whose `sample` starts at most one model call
and whose `finalize` starts none, so one control invocation keeps its
one-model-call bound. `evaluate` evaluates a completed pilot evidence
bundle. Repeating a
request id with an identical binding replays the stored receipt with
`replayed_receipt: true`; a different payload under the same id is `stale_state`.
Responses carry no absolute private-store path, and reason codes carry no path,
prompt, task content, model output or source text.

`checkpoint` binds its evidence tier to the registry contract already frozen in
the trial artifact: skill-content remains causal, while paired-profile uses the
closed advisory waiver set. The trial library enforces this binding on
checkpoint and completed replay; neither a caller-supplied nor persisted
advisory tier can weaken a skill-content trial. Every completed checkpoint must
explicitly provide both `access_audit_complete` and
`access_roots_enforced`. Omitting either field is a protocol error; omission
never claims that proof is complete. Setting `access_audit_complete: false`
lists that proof gap in `coverage_limitations`, and the audit file may be empty
instead of inventing an observation. Provider-side persistence that cannot be
proved disabled is reported the same way. A trusted full-access runner may set
`access_roots_enforced: false` and leave unmeasured memory/canary fields null;
the receipt names both proof gaps instead of treating declared roots or absent
measurements as enforcement. Explicitly observed false fresh-session or enabled
fork, recall, cache, memory or provider persistence is contamination. Observed
path escape, memory recall or canary leak is never waivable.
Current-format completed trials bind their terminal state, isolation receipt,
events and access audit with `completion_binding_hash`; replay rejects ordinary
local drift. Outcome mutation stays on the existing evaluator path so smoke can
report an incomplete result. Pre-tier causal artifacts remain readable. The
hash is an integrity check inside the trusted-local-owner boundary, not a
signature.

The bridge calls no model, selects no provider, starts no shell, opens no
socket, and changes no skill. Interpreter and manifest entries must be regular
non-symlink files that are not group- or world-writable; manifest entries must
be owned by the local user and the interpreter by the local user or root.

## Paired-profile arms and evidence tiers

`profile-arms/*.json` are the pre-registered templates for the second registry
contract. A paired-profile registry freezes exactly one `off` arm (the built-in
profile), one `full` arm (the candidate) and an optional frozen `reference` arm,
all in one scope. The only allowlisted treatment component is the profile
payload; the task-builder template, task, driver, model, prompt template and
permission profile are pinned identical across the pair, so the measured
difference is the profile and nothing else. `write_profile_arm_registry_plan`
freezes that registry before outcomes exist, and one plan may never mix this
contract with the skill-content registry.

A frozen plan may declare a typed `evidence_tier`. Omitting it keeps the
original causal contract, where every isolation-evidence item is required. An
`advisory-paired` request may waive exactly six items — mount evidence,
complete access audit, access-root enforcement, memory-isolation proof,
provider-side persistence proof and the live matched-call gate — and the verdict
then enumerates each waived item that was actually absent in
`evidence_tier.coverage_limitations`. A waiver covers missing proof only: an
observed access, memory-isolation, provider-persistence, contamination or
blinding failure still fails the trial. Checkpoint and completed replay derive
the only valid tier from the frozen registry. A causal request that lacks that
evidence stays non-passing and reports
`causal_core_unavailable`. Synthetic runs satisfy neither tier and report
`synthetic_not_a_tier`.

`replicated-advisory` is deliberately not a verdict here: it is a class-level
property that only several machines' terminal verdict summaries can establish,
and this repository never aggregates verdicts.

## Evidence model

- `arms/*.json` are pre-registered treatment templates. A runner loads the
  committed template independently, resolves every component, freezes the
  template hash and rejects a candidate that self-declares a broader diff.
- `pilot-gates.json` freezes thresholds, budgets, one primary outcome per task
  family and minimum meaningful effects before outcomes are visible. All four
  budget dimensions default to explicit `null` (unlimited); a caller may freeze
  a positive finite limit for any dimension.
- Every real runner/provider path supplies a capability-matrix row. A task
  family enters the causal core only when mount isolation, file-access audit and
  cross-trial memory isolation all have structured probe observations. The
  controller persists each probe outside the source checkout, and the evaluator
  reads it back before checking the hash over observations, runner, provider and
  task family. In-memory declarations, booleans, a detached syntactic hash and
  `provider=none` cannot make a row eligible. An empty eligible matrix yields
  `causal_core_unavailable`; only non-causal shadow work may continue.
- Each task-arm-sample gets an independent task checkout and output directory.
  Artifacts are 0700/0600 and bind the arm, full controller-side task, experiment
  plan, runtime, budgets and current runner-code hash. The tested-agent task hash
  covers only its public task reference; it cannot be used as an oracle-owner
  hash. Resume revalidates the private directory tree, fixed `trial.json` fields,
  fingerprint and evidence shapes. Completed resume also requires the caller's
  authoritative isolation snapshot and read/write roots to match the stored
  evidence. A budget stop is persisted as `interim-budget-stop` with cumulative
  consumption for every frozen budget dimension; resume exposes only the
  remaining allowance for finite limits and rejects rollback or exhaustion.
  The same allowance survives a process restart after the state returns to
  `running`. First publication is serialized before the absent-file check, so
  competing sessions cannot both claim `created`. Checkpoints use a separate
  private lock and increment a compare-and-swap `state_version`, so a stale
  controller cannot overwrite a terminal transition. Finite-budget running and
  completed artifacts must retain their consumption cursor. Unlimited
  dimensions retain `null` remaining allowance while still recording
  consumption. Completion also persists normalized isolation evidence and
  operation-specific roots, then replays the access audit on every completed
  resume; `completed`, `contaminated` and `failed` are terminal.
- `access-audit.jsonl` covers normalized reads, opens and directory enumeration
  as well as writes during the tested-agent window. Controller setup writes are
  outside that audit window, and every event must identify
  `actor=tested-agent`. Read roots and write roots are separate: the tested
  agent may read only its task checkout and write only `outcome/`; it may not
  read or overwrite `trial.json`, event/audit logs, mappings or controller
  secrets. The roots must not overlap. An `open` event must declare read/write
  mode, and any path outside the operation-specific allowlist contaminates the
  trial.
- File access cannot prove provider-side memory is off. Fresh-session,
  no-fork, disabled recall/cache and a path-level canary are separate required
  evidence. `--ephemeral` proves only that local session files are not persisted;
  it is not a provider-side persistence declaration. Missing proof keeps the
  path out of the causal core even when the canary does not leak.
- `blind_pair` exposes only a detached, validated `judge_payload`; arm id,
  manifest hash and Skill events stay in a separate mapping unavailable to the
  judge. Before outcomes exist, the controller persists the complete frozen arm
  registry containing the required OFF, oracle and full treatments. A subset
  cannot become a plan, and each outcome binds that plan and its registered
  manifest. Pair identity binds the registry, outcome identity and detached
  payload content; identity and A/B order use a controller-held 256-bit HMAC
  key. The 0600 key and mapping must live outside every tested-agent read/write
  root and must never enter the judge input, trial report or repository. Concurrent
  controllers publish the key with an exclusive atomic hard link, so they
  converge on one persisted key instead of overwriting one another.
- E10 receives the frozen task-family map, frozen arm manifests and exact
  planned trial identities from a private local evidence bundle. It verifies
  the bundle, config and plan hashes before reading records and calibration,
  replays the task reference, runtime hash, runner/experiment-plan hashes and
  full trial fingerprint from frozen source content, and requires records in
  the registered run order. It also
  validates each manifest and derives treatment and OFF-component residuals
  from that frozen input rather than a runner's self-declared label. Each
  treatment manifest's actual component diff must exactly equal its allowlist.
  Missing, duplicated, reordered or mismatched records fail; host-observed OFF
  residual evidence remains an independent required check.

## Automated learning loop

The intended controller loop is fully agent-operated:

1. an agent proposes a candidate and expected improvement;
2. the controller freezes its content, task set, budgets and rollback point;
3. one or more reviewer families calibrate on the same frozen known-answer
   corpus;
4. isolated trials and blinded graders produce deterministic and calibrated
   reviewer evidence;
5. the controller automatically continues, repairs/retries, rejects or rolls
   back according to frozen gates; and
6. the result and failure class become input to the next candidate iteration.

A single reviewer family may proceed after repeated self-consistency and
known-answer accuracy pass. E10 accepts raw repeated judgments and the frozen
known-answer rows, verifies their committed fixture hash and recomputes every
metric; scalar self-reports are invalid. With two or more families, every family
pair must also pass raw-agreement and kappa thresholds. Codex, Claude and Kimi CLI are
examples of reviewer families, not hard-coded authorities. Human intervention
is optional for conflict escalation, policy override or sampled audit; its
absence is never an E10 failure. Automatic candidate promotion remains
advisory and does not authorize repository merge, push, release or deployment.

## Corpus and grader boundaries

- `tasks-regression.jsonl` references existing known-regression fixtures.
- `heldout-manifest.schema.json` permits metadata and private `corpus://`
  references only. Held-out prompts, hidden tests and grader truth are never
  committed or mounted into the tested agent. Positive tasks require at least
  one expected owner; negative controls require `should_invoke=false`,
  `negative_control=true` and an empty owner list so over-invocation cells remain
  schedulable without inventing an oracle owner.
- Deterministic and blinded pairwise schemas live under `graders/`. Calibrated
  automated reviewers are the default subjective grader; deterministic safety,
  permission and data-loss failures always override reviewer preference. The
  deterministic schema requires top-level `passed` to equal the conjunction of
  all check results; the runtime validator applies the same invariant. The
  human-adjudication schema is an optional intervention artifact, not a gate.
  Pair ids use the opaque `pair-<64 hex>` format and the escalation field is
  consistently named `needs_adjudication`.
- `Sg/Mg` are intentionally non-runnable. The preparation protocol can bind two
  human-authored generic-guidance candidates and a blinded selection, but no
  real candidates have been accepted. Owner-relative ±10% measurement and the
  deterministic matched-call contract are implemented, but live host
  enforcement evidence is still required. Until every entry gate passes, the
  system may compare owner bundles but cannot claim a ccl-specific content
  effect.

Real trial output belongs under an explicit private `--out` root outside the
source checkout. The ignored `eval/skill-effectiveness/out/` path is only
defense-in-depth against accidental manual output; the runner rejects it. Do not
commit outputs, held-out content, local paths, credentials, transcripts or
identity-bearing audit events.

A new output directory is created as 0700. An existing output directory is
accepted only when it is already a real 0700 directory; the runner never
silently changes permissions on a caller-owned path. Group/world-writable
ancestors are rejected unless sticky-bit rename protection applies, preserving
safe `/private/tmp` use while rejecting replaceable shared parents. Before each
attempt, an existing canonical report is copied to content-addressed
`history/`; an aborted attempt leaves no stale `smoke-result.json` while
preserving prior evidence.
