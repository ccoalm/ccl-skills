# Staged Review Contract

The controller has three modes:

- `review`: initial independent external review;
- `challenge`: a focused adversarial external round;
- `complete`: a local deep-self-review checkpoint that calls no reviewer.

Explore/build may configure `challenge_budget=0..4`; release/high-risk requires
at least one challenge unless the exact candidate qualifies for the
proof-bound wording-only single-review exception below. The initial review consumes Agent round 1, so total
Agent-autonomous external review is at most five rounds. Human-requested review
is outside this budget and must be attributed by the consuming trusted platform.
The budget is a ceiling, not a quota: after a clean tracked challenge, local
`complete` may close the chain early. It preserves unused-round count but sets
`autonomous_review_allowed=false`; release/high-risk still requires at least one
challenge before this early close is eligible.

## Plan and owner binding

The plan is optional for `review` and `challenge` and required for `complete`.
When supplied, the bounded UTF-8 plan contains exactly intent, acceptance,
self-review, and evidence. When omitted for review/challenge, the controller
synthesizes a schema-valid derived default (generic intent/acceptance/evidence
plus self-review rows covering the required concerns) and stamps
`review_plan_source=derived-default` on the result so it is never mistaken for a
hand-attested plan (`review_plan_source=implementer-supplied` otherwise).
Self-review accumulates stage concerns: explore covers correctness and
safety; build adds failure paths, tests, and compatibility; release adds rollout
and operations. High-risk input raises depth to release and adds
`high_risk_boundary`.

The serialized plan is at most 32,000 bytes and `intent` is 8..4,000
characters. Those are validation limits, not permission for a caller to slice a
longer value into shape: the gate can validate only the final value it receives
and cannot detect that a caller discarded the newest scope transition first.
Call `scripts/update_review_plan_intent.py` to mutate an existing plan. It checks
an optional expected SHA-256, opens bounded inputs without following links,
writes atomically, preserves ordinary POSIX permission bits, rejects duplicate
JSON object keys before mutation, and leaves the plan byte-identical on
validation or overflow failure. When the plan producer first
chooses the stable core, it persists one reserved evidence row with
`id=review-plan-intent-stable-core-v1` and result
`chars=<character-count>;sha256=<UTF-8-SHA-256>`. On overflow, pass that exact
core and the latest transition as separate files: the helper requires both the
character count and digest to match the persisted identity, requires latest to
be absent from the current intent, and joins them with one fixed blank line.
Before replacing the visible intent, it archives the exact removed suffix in a
reserved, ordered base64 evidence group. That group's manifest binds the prior
intent character count and SHA-256, core length, suffix byte count and SHA-256,
encoding, and part count; if the plan or evidence-row cap cannot hold the group,
compaction fails without changing the file. These rows preserve bytes but do not
classify their meaning. A matching arbitrary prefix is therefore insufficient. Existing plans without
the reserved row remain appendable but cannot compact until their producer has
explicitly established the identity; the helper returns
`intent_core_identity_missing` instead of guessing. The identity proves the
recorded text boundary, not semantic correctness or protection from a caller
that rewrites the whole plan outside the helper. Keep semantic dispositions in
ordinary evidence rows and ordered prior-review results; the byte archive is a
loss-prevention carrier, not a substitute. Never use prefix/tail truncation as
compaction. One final line ending is treated as a file delimiter; other outer
whitespace is rejected.

The expected digest is a stale-at-open guard, not a lock: callers serialize
writers and provide a trusted, stable parent directory for the read-check-replace
interval. Plans are caller-owned, singly linked regular files; ACLs, extended
attributes, ownership, and special mode bits are outside this replacement
contract. A post-rename directory-sync failure reports
`plan_committed_durability_unknown` with the new digest: re-read before deciding
whether to retry, because the target has already changed. A stdout pipe that
closes before the success receipt is delivered likewise reports
`plan_committed_receipt_lost` on stderr with a nonzero exit: the update is
committed, only the receipt was lost, so re-read the plan instead of retrying.

Each self-review row may name a direct sibling skill. Omission selects the
`code-review` baseline. The controller also derives owners deterministically
from changed `skills/<name>/` paths, test paths, and supported source extensions.
With an implementer-supplied plan, every derived owner must have a self-review
row before provider execution, and missing owners are incomplete self-review. A
derived-default plan carries no implementer attestation to check against, so it
waives that pre-attestation requirement while still selecting and loading the
derived owners for the reviewer. The controller binds regular `SKILL.md` plus
recursive `references/**/*.md` and reports
`owner_selection_source=controller-derived+implementer-declared` when derivation
participates. Linked, inaccessible, or non-regular owner/controller content is a
terminal local integrity error.

Owner-aware wrappers receive only the canonical registry root, selected names,
and their frozen hashes. They verify that binding, use the already-installed
CCL skill registry through each client-native mechanism, and explicitly
name the selected owners: Claude `--plugin-dir`, Kimi `--skills-dir`, OpenCode
`skills.paths`, or Codex `$skill-name`. Skill bodies are never copied into the
review profile or prompt. A client unable to establish this native binding is
ineligible for the owner-aware lane. Each successful owner-aware wrapper adds a
post-parse `native_skill_binding=established` receipt; absence fails closed
before the controller claims usage. Receipt injection itself is part of the
trusted wrapper path: a local serialization or output failure is terminal
`local_tool_failure`, never an empty or apparently successful result. After a
valid verdict, `reviewed_skills` contains only the selected owners passed
through the client-native invocation;
the general `code-review` baseline remains in `selected_skills` but is not
reported as natively invoked. The installed registry may remain visible. For
Codex, an independently updated installed package must exist and pass the same
safe-package validation, but its bytes need not equal an older candidate
branch; `$skill-name` binds the selected identity. The frozen source hash still
binds controller routing and review-chain reuse, not the host release version.
For Claude, the public init surface must register the `ccl-skills` plugin while
the wrapper separately verifies the selected package hashes and explicitly
names the owners. Current init does not enumerate the selected plugin skills or
commands; plugin registration is binding evidence, not proof that the model
read a skill body. If init begins enumerating ccl-registry skills or
`ccl-skills:` commands, every selected owner must appear in those lists or
the wrapper fails closed; built-in entries alone do not imply plugin enumeration.
An owner name that collides with an audited Claude built-in is not representable
on this surface and is rejected before a binding receipt.
`skill_usage_evidence` records
native explicit invocation with `observed=false`; only a public client
event/export may populate `observed_skill_usage`. Reviewer prose and private
client databases do not count as observation evidence.

For every client, `native_skill_binding=established` means the wrapper verified
the frozen selected packages and emitted that client's native explicit-invocation
syntax. It does not assert internal activation; that stronger claim belongs only
in `observed_skill_usage`.

This binding check also applies to direct wrapper calls. If a native-installed
profile selects owners but the matching registry root or owner arguments are
omitted, every wrapper returns terminal `binding_mismatch` before inference.

Owner-aware Claude requires `--safe-mode` with the explicit `--plugin-dir`, so
ambient customizations stay disabled while the full installed plugin supplies
skills and normal OAuth/keychain authentication remains available. The wrapper
must not add `--bare`, because that flag disables the ordinary OAuth/keychain
path and turns a logged-in CLI into an auth failure unless a separate API key is
injected.
The Claude wrapper also validates the installed plugin manifest before launch:
its skills entrypoint must be `./skills`, and top-level agents, commands, hooks,
or MCP servers make the plugin ineligible for this bounded review lane.

Wrappers keep an explicit selected-owner count instead of testing empty Bash
arrays under `set -u`, preserving the no-owner lane on Bash 3.2.

## Base-derived packet input boundary

`--base` freezes the tracked diff plus every non-ignored untracked path in
scope. Exact-candidate binding means the controller never skips an untracked
path or replaces its contents with a placeholder. An untracked path containing
a Unicode control or line-separator character, symlink, hardlink, other
non-regular file, NUL-bearing file, non-UTF-8 file, or file over 200,000 bytes
makes the whole lane fail before provider execution with
`reason_code=invalid_input`. The same result applies when rendered untracked
content or the combined tracked-plus-untracked packet exceeds 200,000 bytes.

Move an out-of-scope path outside the candidate or add a correct ignore rule;
commit an in-scope path when Git should represent it; or compose complete
`--diff-file` partitions when the candidate must be split. Never omit a path
and report the remaining packet as the whole candidate.

## Proof-bound wording-only single review

The wording-only exception is one untracked `review` with
`challenge_budget=0`; it is not a chain, challenge, or `complete` checkpoint.
Supply `--wording-only-proof-file` to bind the exception to the exact packet.
Without that proof, an explore/build budget-zero review remains an ordinary
single review and cannot be recorded as the wording-only exception;
release/high-risk budget zero fails before inference.

At release depth, including depth raised by a high-risk tag, only a
controller-proved `markdown-punctuation-only` check may use this exception.
`markdown-token-replacement` remains available for explore/build budget-zero
review, but it cannot waive the release/high-risk challenge: byte-exact token
replacement does not prove that the old and new tokens have the same meaning.

The proof is a single-link regular UTF-8 JSON file of at most 16,000 bytes:

```json
{"schema_version":1,"candidate_sha256":"<packet-sha256>","check":{"kind":"markdown-punctuation-only"}}
```

The other fixed check is
`markdown-token-replacement`, whose `check` also contains `old_token`,
`new_token`, and integer `expected_count` (1..100). The controller never trusts
a caller-supplied pass result. It reparses the frozen packet and derives the
status, files, changed-line count, replacement count, and scope SHA-256.

The accepted packet is deliberately narrow: a canonical full-context unified
Git diff, LF-terminated, at most 200,000 bytes, changing existing regular
Markdown files inside exactly one existing non-linked skill package. Every
file's first hunk starts at line 1 so frontmatter is inspectable. Adds,
deletes, renames, multi-skill changes, frontmatter or `description` edits,
non-regular Git modes, custom/compact packets, extra context outside the diff,
and files without a final newline fail closed. `markdown-punctuation-only`
accepts only one-for-one plain-prose line replacements whose non-punctuation
characters remain identical; numeric tokens must additionally survive
byte-for-byte (deleting the dot in `5.5` is a threshold change, not
punctuation), and a question mark may not be added or removed (a statement
turned into a question is a meaning change). Lines must start at column zero
and contain prose; line adds/deletes, Markdown headings, lists, block quotes,
links, tables, inline code, fenced or indented code, and raw HTML `pre`/`code`
containers fail closed. `markdown-token-replacement` requires every changed
line pair to differ only by the named whole-token replacement, with the exact
total count, and rejects packets whose changed lines touch a Markdown or HTML
code container.

This recipe produces the exact packet and proof without a second parser or a
pretend verifier command. Set `WORDING_KIND=markdown-punctuation-only`, or set
`WORDING_KIND=markdown-token-replacement` plus `WORDING_OLD`, `WORDING_NEW`, and
`WORDING_COUNT`:

```bash
: "${CODE_REVIEW_SKILL_DIR:?set the installed code-review skill directory}"
: "${REPO_ROOT:?set the absolute repository root}"
: "${REVIEW_BASE:?set the exact base ref}"
: "${SKILL_NAME:?set the one existing skill package name}"
: "${REVIEW_STAGE:?set explore, build, or release}"
: "${IMPLEMENTER_FAMILY:?set the implementer model family}"
: "${REVIEW_PLAN_FILE:?set the absolute review-plan JSON path}"
: "${REVIEW_EVIDENCE_DIR:?set an existing durable private evidence directory}"
: "${WORDING_KIND:?set one supported wording-only check kind}"

umask 077
WORDING_RUN_DIR="$(mktemp -d "$REVIEW_EVIDENCE_DIR/wording-review.XXXXXX")" || exit 1
WORDING_DIFF="$WORDING_RUN_DIR/candidate.diff"
WORDING_PROOF="$WORDING_RUN_DIR/proof.json"
WORDING_RESULT="$WORDING_RUN_DIR/review.json"

git -C "$REPO_ROOT" diff --no-color --no-ext-diff --no-textconv --full-index \
  --src-prefix=a/ --dst-prefix=b/ --unified=1000000 \
  "$REVIEW_BASE" -- "skills/$SKILL_NAME" >"$WORDING_DIFF" || exit 1

python3 - "$WORDING_DIFF" "$WORDING_PROOF" "$WORDING_KIND" \
  "${WORDING_OLD:-}" "${WORDING_NEW:-}" "${WORDING_COUNT:-0}" <<'PY'
import hashlib
import json
import sys
from pathlib import Path

diff_path, proof_path = map(Path, sys.argv[1:3])
kind, old, new, count = sys.argv[3:]
check = {"kind": kind}
if kind == "markdown-token-replacement":
    check.update(old_token=old, new_token=new, expected_count=int(count))
elif kind != "markdown-punctuation-only":
    raise SystemExit("unsupported WORDING_KIND")
payload = {
    "schema_version": 1,
    "candidate_sha256": hashlib.sha256(diff_path.read_bytes()).hexdigest(),
    "check": check,
}
proof_path.write_text(
    json.dumps(payload, ensure_ascii=False, separators=(",", ":")) + "\n",
    encoding="utf-8",
)
PY

WORDING_RISK_ARGS=()
for tag in ${REVIEW_RISK_TAGS:-}; do WORDING_RISK_ARGS+=(--risk-tag "$tag"); done
if ! bash "$CODE_REVIEW_SKILL_DIR/scripts/review_gate.sh" \
  --mode review --stage "$REVIEW_STAGE" --challenge-budget 0 \
  --cwd "$REPO_ROOT" --diff-file "$WORDING_DIFF" \
  --review-plan-file "$REVIEW_PLAN_FILE" \
  --wording-only-proof-file "$WORDING_PROOF" \
  ${WORDING_RISK_ARGS[@]+"${WORDING_RISK_ARGS[@]}"} \
  --implementer-family "$IMPLEMENTER_FAMILY" >"$WORDING_RESULT"; then
  cat "$WORDING_RESULT" >&2
  exit 1
fi
cat "$WORDING_RESULT"
```

A valid result carries `wording_only_proof_sha256`, controller-derived
`wording_only_scope.status=passed`, and a reviewed
`wording_only_boundary` concern. That concern independently confirms the edit
changes no trigger, scope, routing, validation, acceptance, rule, threshold,
boundary, frontmatter, description, or other meaning. If it is missing,
inconclusive, or reports a possible semantic change, the wording-only exception
does not apply: use the normal challenge and behavioral-evidence path. Any
candidate edit regenerates the packet and proof and requires a new review.
Keep the diff, proof, and result together; a digest whose source artifact was
deleted is not independently auditable evidence.

## Agent review chain

Multi-round Agent automation supplies `review_chain_id`, a contiguous
`autonomous_review_index` in `1..5`, and every earlier result through ordered
`--prior-review-result-file` arguments. Prior rounds may contain findings and
older candidate hashes; they remain consumed. Candidate edits, commits, plan
refreshes, mode changes, and renamed invocations do not reset Agent authority.
An initial `review` with positive challenge capacity must start this chain at
index 1; an untracked initial review is single-round and therefore uses budget 0.

The chain binds task scope, candidate identity per round, result hashes, mode,
status, challenge focus, controller, and selected owners. The opaque
`review_scope_sha256` always hashes normalized intent, acceptance, stage/depth,
risk tags, challenge budget, and the wording-only proof/scope digests (both
`null` outside that exception); chain identity is validated separately. This
prevents deleting or nulling the top-level wording-only fields from reclassifying
that receipt as a normal completion input. Every result also carries the
canonical `review_scope` object that digest is taken over — intent and
acceptance appear only as `intent_sha256` / `acceptance_sha256`, never as raw
plan text, because results are logged and archived independently of the plan. A prior result is accepted only when its
recorded `review_scope` reproduces its own `review_scope_sha256` and that digest
matches the current scope, so copying a digest onto a differently-scoped result
no longer passes. This binding proves internal consistency, not authority: prior
result files are unauthenticated, so a caller able to rewrite an entire envelope
consistently is still accepted, per this gate's trusted-local-agent trust model.
Envelope `schema_version` is `3`; a legacy `2` envelope predates the recorded
scope and is rejected, which requires restarting an in-flight chain. Every
prior round must retain the same controller digest, owner-selection source,
selected owner names, and selected-owner digest. Missing, substituted,
inconclusive, reordered, renamed-chain, or fourth-round input fails before any
provider runs. Scope drift returns `review_scope_changed` and requires deep
self-review plus explicit task reframing; it does not silently create a new
Agent budget. An untracked challenge is one-off advisory evidence; it cannot
enter a later Agent round or satisfy the local completion checkpoint.

The controller is stateless and prevents accidental/cooperative resets only. A
trusted host or platform must retain the ledger when hostile local callers are in
scope; a repository-local counter cannot authenticate human authority.

## Mechanical self-review gate

Every stable result that reaches the gate's composite stage includes
controller-owned `self_review_gate` (a freeze-stage argument-validation
envelope — for example `invalid_input`, or the argument-combination variant of
`completion_checkpoint_invalid` raised before profile freeze — carries
`schema_version` but may omit `self_review_gate`, `review_state`, `stage`, and
`attempts`; consumers must not read those fields unconditionally on every
exit-2 result):

- `required_triggers`: outstanding deep-self-review checkpoints;
- `satisfied_triggers`: checkpoints validated by the current plan;
- `blocks`: only the next external review and/or a completion claim;
- `allowed_next_actions`: productive work that remains legal.

The controller fires at these boundaries: before external review, findings
returned, candidate change in a tracked chain, risk/scope escalation, post-budget
checkpoint, and before a completion claim. Findings never produce a blind
review-fix-review loop: they block another reviewer call, return to implementer
triage, and still allow implementation, tests, and independent runnable work.

A passed final external round returns
`next_action=deep_self_review_before_completion` and remains
`completion_gated=true`. `--mode complete` accepts one exact-candidate passed
review result plus the current self-review plan, calls no reviewer, rejects stale
candidate/controller/owner bindings and changed intent or acceptance, while
allowing refreshed self-review conclusions and evidence, and is the Agent path to
`completion_gated=false`. Its result preserves the verified chain id, scope,
round index, prior-result hashes, and prior challenge focuses. It is not a human
waiver or merge authorization.

## Human and failure boundary

Only an external authenticated platform action may prove human request, stop,
resume, waiver, commit, or merge authority. A `review_waiver` clears only the
review-process gate. A distinct exact-candidate `merge_authorization` is the
human's final decision: CI may keep running and reporting every failed/pending
gate, but none may block that authorized merge. Report
`merge_authorized_by_human` / `failed_but_human_overridden`, never `passed`.

Provider/input/integrity failures stop that reviewer lane, not the whole task.
Their stable action is `stop_reviewer_lane`, never the ambiguous `stop`.
Budget exhaustion likewise stops only automatic reviewer calls. Continue local
fixes, self-review, tests, and independent work; park only decision-dependent
work. Enter `awaiting_human` only when no independent runnable work remains.

The current result envelope is schema 3. The generic per-invocation `--timeout`
keeps its 600-second default and accepts 5..1200 seconds; direct wrappers clamp
higher decimal values, including values beyond shell integer range, to 1200.
Wrapper-internal sub-mode limits such as Kimi inline mode's 120-second cap stay
separate. The controller bounds cumulative reviewer-lane execution with `--total-timeout`
(default 2400 seconds, accepted range 5..3600). Setup time reduces the budget,
and git preflight subprocesses share its deadline; direct filesystem reads
remain subject to the host's outer timeout. Each client receives the smaller of the requested per-invocation
timeout and `(remaining total budget - ten controller seconds) / maximum mode
invocations`; review reserves two invocations and challenge one. If that
allowance is below five seconds, the gate returns inconclusive `gate_timeout`
and starts no later client. Each wrapper lane is separately bounded by its
mode-adjusted allowance plus controller headroom. A lane timeout gets bounded
TERM/KILL/final-reap cleanup and may cascade while total budget remains; killed
or partial output is never a verdict. A verdict that arrives after total expiry
is cleared; prior findings remain only in diagnostic `unbound_findings`, which
must not be treated as a verdict. Before setup overhead, the practical minimum that can
start a lane is 21 seconds for review and 16 for challenge; smaller accepted
values intentionally fail closed.
