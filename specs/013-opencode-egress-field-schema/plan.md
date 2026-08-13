# 013 — A per-field output schema for the OpenCode reviewer's egress

## Artifact classification

`gate implementation` (per `product-rd-workflow/references/shared-gate-artifact-classification.md`).

No stop rule, cascade rule, or reason code changes. What changes is the **payload
contract** of every result the OpenCode lane emits — which keys may appear and
what may be inside them — and downstream controllers parse that payload. That is
shared-gate semantics, so this plan exists before any edit.

Risk tags (`feature-risk-router`): `shared-gate`, `api-contract`.
`security-review`: the change-triggered arm **applies and is not `not-applicable`**
— the OpenCode export is an untrusted-input surface, the durable evidence rows are
a sensitive sink, and this is itself a hardening change. All three blockers are
present, so `security posture unchanged` cannot be recorded.
`visible surface: no` — the wrapper renders no product UI.

Named by `010-review-concern-excerpt/plan.md` as out of scope there, with the
reason recorded: fixing only the concern-evidence path "would read as coverage
while every other verdict stayed unbounded."

## Defect

`010` bounded **what the model wrote**. It did not bound **what the export
carried**. Four values cross from the untrusted export into every durable evidence
row on the parser's failure paths, and none of them is validated at egress.

| Evidence | What it shows |
| --- | --- |
| `parse_opencode_review.py:236` | `version = info.get("version") or (export_obj.get("info") or {}).get("version")` — taken from the export, never checked anywhere |
| `parse_opencode_review.py:338-344` | `base` = `session_id`, `model`, `provider`, `version`, `mode`. Four of the five are export-derived |
| `parse_opencode_review.py:349-408` | ten `_result(...)` returns spread `**base` — every inconclusive exit on the parser side |
| `parse_opencode_review.py:81-88` | `_result` accepts arbitrary `**extra` and `out.update(extra)`. There is no declared key set and no value check at the emission point |
| `opencode_review.sh:650-660` | `EGRESS_KEYS` bounds **which keys** may leave — and only inside the concern-evidence branch. Every other path prints the parser's payload unchanged |

Two independent gaps, both named by `010`:

1. **Values are unbounded.** `EGRESS_KEYS` is a key allowlist. A crafted export
   can put a megabyte of arbitrary text — newlines, JSON, another model's prose —
   into `version` and it egresses verbatim, because `version` is on the list.
2. **The key allowlist covers one path.** It lives in a single `if` branch in the
   shell. The parser's ten inconclusive returns never pass through it.

**The binding checks do not close this.** `provider` and `model` are compared
against the resolved agent boundary (`:354-375`) and `session_id` against the
events file (`:348`) — but each check's **failure return emits the value that
failed it**. `session_id_mismatch` at `:349` carries exactly the crafted
`session_id` the check just rejected. Validation that gates the *lane* is not
validation that gates the *egress*.

Verified pre-existing, not introduced by `010`: the pre-`010` block re-emitted the
same payload through `jq -c '. + {…}'`, so these fields already egressed verbatim.

## Why a field schema converges where the prose denylist did not

`010` spent seven rounds proving that bounding untrusted text does **not**
converge, then removed the free-text path rather than patch the denylist an eighth
time. Reinstating a validator over untrusted content is the obvious objection to
this design, and it does not hold, because it is not the same problem:

- `010` was enumerating **what is bad inside arbitrary natural-language prose** —
  an open set, which is why every round found another credential shape.
- These four fields are **machine identifiers with a known grammar** —
  `ses_8f2a…`, `anthropic/claude-sonnet-4`, `0.4.12`. Enumerating **what is
  permitted in an identifier** is a closed set.

So the schema is an **allowlist over shape**, in the same direction as the fix
`010` converged on (build the verdict from contract-owned machine fields), one
level down: it bounds the fields that build was already allowed to carry. A
legitimate value that falls outside the grammar becomes a **visible violation**,
never a silent relay — the failure direction is toward dropping the value.

## Scope

In scope:

1. New shared helper `skills/code-review/scripts/egress_schema.py` — one declared
   table of every key the OpenCode lane may emit, its kind, and its bound.
2. `parse_opencode_review.py` — `_result()` applies the schema at the single
   emission choke point every parser result passes through.
3. `opencode_review.sh:650-660` — the concern-evidence branch consumes the same
   table instead of its own inline `EGRESS_KEYS`, so there is one authority rather
   than two that can drift.

Out of scope, named rather than silently dropped:

- The other lanes' wrappers (`codex`, `kimi`, `claude`). Their metadata does not
  come from an untrusted export of a third-party tool's session; whether they need
  the same treatment is a separate audit, not an assumption to act on here.
- `review_gate.py`'s own `record_attempt` rows. It stores what the wrapper hands
  it; bounding the wrapper is the fix, and widening to the gate would re-open the
  boundary `010` settled.
- A `findings`-status verdict still relays its text whole. That is reviewer prose
  about the diff — the class a schema-valid result already persists, per `010`'s
  recorded acceptance. Unchanged here.

## Design

### Where the schema binds

At `_result()` in the parser. It is the single choke point: all ten inconclusive
returns and the success return pass through it, and a future return added by a
later slice passes through it without anyone remembering to.

Rejected alternatives:

- **Per-call-site validation.** Ten sites today; the eleventh is added silently.
- **Shell-side only.** `010` already established that this shell "does not own the
  parser," which is exactly why its key allowlist covers one branch. Putting the
  value bound in the same place would inherit the same blind spot.
- **Validate at the gate instead.** Moves the boundary outward; the gate would then
  need a schema per wrapper.

### The table

Each key declares a kind. Two kinds carry no untrusted data and are checked for
type only:

| Kind | Keys | Check |
| --- | --- | --- |
| contract-enum | `reviewer`, `status`, `mode` | value ∈ the module's own declared set |
| contract-identifier | `reason`, `reason_code`, `reviewer_family`, `runtime_isolation`, `credential_binding` | `[A-Za-z0-9][A-Za-z0-9._-]{0,63}` |
| contract-boolean | `cascade_eligible`, `candidate_ineligible`, `concern_evidence` | `is True` / `is False` |
| contract-exit-code | `transport_exit_code` | `int` in −256…256, or ≤3 digits as a string |
| export-token | `session_id`, `model`, `provider`, `version` | the grammar below |
| export-token-list | `exposed_tools`, `missing_tools`, `missing_disabled_tools` | `list`, ≤64 elements, each an export-token |
| structured | `concern_results`, `findings`, `severities`, `locators`, `text` | shape-checked by their existing owners; unchanged here |

**export-token grammar**: `str` or `None`; length ≤ 200; every character in
`[A-Za-z0-9._:/@+-]`. That covers a provider-qualified model id, a semver, and an
opaque session id, and excludes newlines, control characters, quotes, and
whitespace — the shapes that let a value stop being a single field.

### On violation

**Revised after review round 1** — the original wording below applied one
response to every kind, which review found to be false advertising for the
contract kinds. Drop-and-report applies **only to export-derived fields**
(`export-token`, `export-token-list`). For contract fields the value cannot have
come from the export — every `reason` and `reason_code` is a literal in this
repo's scripts, and `reviewer_family` is a lookup *result* — so an illegal value
is an internal bug, and `apply` raises `ContractFieldViolation` rather than
emitting a nulled one. Nulling `status` would be precisely the verdict change
this schema promises never to make.

`field_schema_violations` is **output-only** and has no schema row, so it is
rejected on input: accepting a caller-supplied one leaves it the single
unvalidated field, free to carry arbitrary prose and to forge or suppress the
report that records tampering. It *is* carried in `CONCERN_RELAY_KEYS`, because
a report that trips the concern path's fail-closed would hand a crafted export a
verdict change through the back door.

For an export-derived field, the value is replaced with `None` and the
**field name** is appended to a new `field_schema_violations` list. Names come from the module's own declared set, so
nothing untrusted rides out on the violation report itself — the mistake `010`
made once, when the block reason quoted the text it was blocking.

**A violation never changes the verdict** — the same invariant `010` held: this
adds evidence to a stop; it never converts a stop into a cascade, nor a cascade
into a stop. The acceptance matrix carries it as a per-row check.

Rejected: **fail the whole result closed** on a violation. It hands anyone who can
craft an export a way to turn every review into a lane-fatal stop, and it destroys
the diagnosis of *why* the run failed. Dropping one field preserves both.

### On an undeclared key

`_result` raises rather than emitting it — the parser cannot emit a key the schema
does not declare. This matches what the shell already does at `:657-658` (an
unlisted key fails closed to `concern_audit_failed` for a human to classify) and
keeps the two ends behaving the same way now that they share one table.

## Acceptance matrix

| # | Input | Emitted payload | Verdict fields |
| --- | --- | --- | --- |
| 1 | export with well-formed metadata | all four values pass through unchanged | unchanged |
| 2 | `version` = 1 MB of prose | `version: null`, `field_schema_violations: ["version"]` | **unchanged** |
| 3 | `version` = 201 chars of legal charset | `version: null`, violation recorded | unchanged |
| 4 | `session_id` containing a newline / control char | `session_id: null`, violation recorded | unchanged |
| 5 | `model` = a non-string (dict, list, int) | `model: null`, violation recorded | unchanged |
| 6 | two fields violate at once | both null, both names in `field_schema_violations`, order stable | unchanged |
| 7 | no violation anywhere | `field_schema_violations` **absent**, not an empty list | unchanged |
| 8 | violation on the `session_id_mismatch` path | reason code still `session_id_mismatch`, `cascade_eligible` unchanged | unchanged |
| 9 | violation on the concern-evidence path | `concern_evidence` still `true`, `cascade_eligible` still `false` | unchanged |
| 10 | `_result` called with an undeclared key | raises; the shell's existing failure path emits `concern_audit_failed` | n/a |
| 11 | parser and shell disagree on the key set | impossible by construction — one table, asserted by a test that imports both | n/a |
| 12 | the violation report itself | contains only names from the declared set; no fragment of the offending value | — |

Invariant across every row: **no row changes a status, reason code, or cascade
decision.** A change to any of those is a defect in this slice, not an acceptable
side effect.

## Test / register coverage

Per `skills/code-review/scripts/AGENTS.md`: parser changes need tests with
positive, finding, malformed, and inconclusive cases.

A new suite that `make test` does not enumerate is not a gate. This repo's
Makefile lists every suite by name rather than globbing, so registering
`test_egress_schema.sh` there is part of this landing, not a follow-up — it was
initially missed and caught by reading the Makefile rather than by any check.

| Layer | Rows | Command | State |
| --- | --- | --- | --- |
| unit (new) | 1-7, 10-12 | `bash skills/code-review/scripts/test_egress_schema.sh` | landed, registered in `make test` |
| integration (parser) | 8, and every `**base` return | `bash skills/code-review/scripts/test_parse_opencode_review.sh` | add cases |
| integration (wrapper) | 9, 11 | `bash skills/code-review/scripts/test_opencode_review_retry.sh` | add cases |
| integration (gate) | payload still parses; stop still terminal | `bash skills/code-review/scripts/test_review_gate.sh` | run |
| contract | downstream payload compat | `python3 skills/code-review/scripts/test_review_client_compat.py` | run |
| repo gate | full deterministic suite | `make test` | run |
| E2E / live provider | — | — | not applicable: no live CLI runs on these paths under test |
| manual | — | — | not applicable |

Test-case-first: the RED assertions in `test_egress_schema.sh` land and run RED
before the helper exists.

**Mutation evidence is required, not optional** — every row above asserts an
outcome the unmodified parser can already produce for the *legal* inputs, so a
passing suite proves little by itself. At closeout, apply and record at least:
relax the charset to accept any string (rows 2-4 must flip), drop the length cap
(row 3 flips alone), emit `field_schema_violations: []` unconditionally (row 7
flips alone), and let the violation report include the offending value (row 12
flips alone). Each mutation applied in a disposable copy, restored, and
byte-compared against pristine.

## Status-sync target

This plan file, plus the `Follow-up disposition` section of
`specs/010-review-concern-excerpt/plan.md`, which names this work as its open
item. No external tracker, no cross-repo status surface, no release metadata.

## Review / challenge gate

`shared-gate` + `security-review` both require the dual track before shared-branch
push or MR merge:

- `review_gate.sh --mode review` and `--mode challenge`, `--stage release`,
  `--risk-tag shared-gate`, `--review-harness`, with `IMPLEMENTER_FAMILY=anthropic`
  so the Claude lane is excluded as same-family.
- Record reviewer/tool identity, concrete objections, and disposition.
- The challenge focus is the convergence argument above — whether a charset
  allowlist over these four fields is genuinely a closed set, or `010`'s
  non-converging denylist wearing a different hat.
- If the required review/challenge is unavailable after remediation, this slice
  stops at `interim` / pending-review, not `complete`.

Note the recursion, same as `010`: this edits the harness that would review it, so
the review runs with `--review-harness` and the reviewed identity is the packet
hash of this diff. It also edits **the OpenCode lane specifically** — if that lane
is the selected reviewer, its own verdict passes through the code under review.
Record the selected client; if it is `opencode`, re-run on another lane before
treating the review as independent.

Verifier discovery (repo agent contract + Makefile + CI): `check-ccl-skills.sh`,
`check-agent-contract-coverage.sh --enforce`, `check-public-sanitization.py`,
`check-markdown-links.py`, `make test`, `git diff --check`. All authoritative, all
run before the slice is claimed complete.

## Implementation deviations from this plan

Three things this plan got wrong, found while implementing it. Recorded here
rather than silently absorbed, because each one changes what the table means.

**1. The key table was incomplete — the plan under-enumerated its own subject.**
AST-walking every `_result` call site turned up four emitted keys the table never
mentions: `exposed_tools`, `missing_tools`, `missing_disabled_tools`, and `text`.
Since an undeclared key *raises*, shipping the table as written would have broken
the parser on its first isolation failure. The first three are lists of tool names
lifted from the export — untrusted, and exactly the kind of field this slice
exists to bound — so they became a new `export-token-list` kind checked per
element. `text` is the reviewer's raw prose, already owned elsewhere, so it is
`structured`.

The lesson is about method, not about four names: the table was written from the
plan's reading of the payload, and the payload was never enumerated mechanically.
An enumeration that decides what may leave has to be derived from the code, not
recalled from it.

**2. `reason` and `reason_code` are not closed sets, so they are not enums.**
The plan filed both under `contract-enum`. Their vocabulary is spread across five
scripts (21 distinct `reason` values in the parser alone, plus more built in the
shell, plus interpolated forms like `reviewer_exit_{code}`). An enum that fell out
of sync with any of them would blank a legitimate diagnostic on the exact failure
path a human is trying to read — trading an integrity bug for an availability one.
They are values *this repo* chooses, never the export's, so the honest bound is a
shape bound: `contract-identifier`. `reviewer_family`, `runtime_isolation`, and
`credential_binding` moved for the same reason. The three fields whose sets really
are closed and verifiable here (`reviewer`, `status`, `mode`) stayed enums.

**3. "One table, not two" cannot mean "one set".**
The plan's `:657-658` reading was right that the shell fails an unlisted key
closed, but wrong that the two ends can therefore share one set. The shell's list
is *deliberately narrower* than everything the parser may emit: on the
concern-audit enrichment path, a key outside it fails closed to
`concern_audit_failed` so a human classifies the new field. Importing the full
`EGRESS_KEYS` there would have converted that fail-closed into a pass-through for
five keys — a silent widening of the exact boundary this slice is supposed to
tighten. Resolved by declaring `CONCERN_RELAY_KEYS` in the same module, with an
import-time assertion that it stays a subset and a test that it stays a *strict*
one containing no model content. One file to edit, two sets with a checked
relation.

**Two gates fired only after the work was staged, and both were real.** The R0
leakage audit ran clean when invoked by hand and then failed inside `make test`
one commit later, because it reads the committed diff — an untracked new file is
outside its input entirely, so "I ran the audit" is not evidence until the file
is staged. It objected to the fixture session ids, whose opaque prefixed shape
read as real captured identifiers; they are now canonical `sample*` placeholders, which
costs the test nothing since the property under test is the *charset*, not the
prefix. The Makefile omission above is the same shape: both were caught by
running the gate against the real artifact rather than by reasoning about it.

## Mutation evidence

Five mutations, each applied to a disposable copy of `egress_schema.py` and
restored byte-identical afterwards (verified by comparison, not by re-reading):

| Mutation | Result | Flipped |
| --- | --- | --- |
| relax the export-token charset to any non-NUL string | CAUGHT | `row4` embedded-newline case |
| drop the 200-character length cap | CAUGHT | `row3` |
| emit `field_schema_violations` unconditionally | CAUGHT | `row1-passthrough` (row 7's property) |
| include the offending value in the violation report | CAUGHT | `row2-report` |
| accept an undeclared key instead of raising | CAUGHT | `row10` |
| check keys against `EGRESS_KEYS`, re-admitting the output-only field | CAUGHT | `violation-field-input[str]` |
| sanitize contract fields instead of refusing to emit | CAUGHT | `contract-raises[status]` |
| drop the violation report from the concern relay set | CAUGHT | `violation-field-relayable` |
| restore the blanket `None` skip | CAUGHT | `contract-none[status]` |

The last four re-create every defect the two review lanes found, so each finding
has a mutant that fails if its fix is ever undone.

Each flipped the case that owns the property, not merely *some* case — the check
that distinguishes a real sensitivity test from a suite that fails for an
unrelated reason.

## Executed review rounds

Recorded per lane NAME, not per round count — the closeout rule this repo added
after a slice landed with nine review rounds and zero challenge runs.

| # | Lane | Chain | Client | Outcome |
| --- | --- | --- | --- | --- |
| 0 | review | `egress-schema-013-r1` | none | `inconclusive` / `review_chain_invalid` — a tracked chain needs `--autonomous-review-index`; operator error, re-run |
| 1 | review | `egress-schema-013-r1` | none | `inconclusive` / `egress_denied` on codex, kimi *and* opencode; claude skipped `same_family_as_implementer`. **This was a real defect in this slice, not gate noise** — see below |
| 2 | review | `egress-schema-013-r2` | codex | `findings`, 2 × P1, both accepted and fixed |
| 3 | challenge | budget 1, index 1 | codex | `findings`, 1 × P1, accepted and fixed |

**Round 1's block was self-inflicted and is the transferable part.** The gate's
egress scanner found `aws_access_key_id` and `secret_assignment` in the diff:
the row-12 fixture used a credential-*shaped* literal to prove that an offending
value never reaches the violation report. It was a documentation-example key and
therefore harmless, but its SHAPE made the diff unreviewable by every non-Claude
lane, and the Claude lane was already excluded as same-family — so the slice had
no reviewer at all. `--allow-fallback-egress` exists and would have "fixed" it in
one flag; that would have approved shipping a key-shaped literal into the tree
to work around a gate that was doing its job. The fixture now uses a
non-credential-shaped canary, which tests the identical property. **A test that
needs a secret-shaped value should ask whether the property really needs that
shape** — here it did not.

Round 2's two findings, both P1, both accepted:

1. `apply()` subtracted `EGRESS_KEYS` rather than `SCHEMA`, and `EGRESS_KEYS`
   carries the output-only `field_schema_violations`. A payload arriving with
   that key was therefore treated as declared while having no schema row — the
   one field that could carry arbitrary content, and the one whose forgery would
   hide the tampering. Fixed by validating keys against `SCHEMA` alone.
2. The single violation branch nulled *any* invalid field including `status`,
   which contradicts this plan's own "a violation never changes the verdict"
   invariant — and the plan's test asserted the contradiction, so the suite was
   pinning the wrong behavior. Fixed by splitting contract fields (raise) from
   export fields (drop and report), with a case asserting the verdict fields
   survive an export-field violation.

The second finding is the instructive one: the invariant was stated in the plan,
implemented as its opposite, and then *locked in by a test I wrote to match the
implementation rather than the claim*. A written invariant is not evidence; the
case that would fail if it were violated is.

**Round 3 (challenge) found the same mistake one branch further in**, which is
why the second lane is not optional. The round-2 fix split violation *handling*
by provenance but left the `if value is None: continue` skip blanket — so a
contract field set to `None` bypassed the raise entirely and reached egress as a
null verdict. Accepted and fixed: `None` stays legal for an export field (the
export need not carry one) and raises for a contract field.

It is **unreachable from today's call sites** — AST-walking every `_result`
invocation shows no contract field is ever passed explicitly, so none can be
`None`. That is exactly why only an adversarial read found it, and why it was
still worth fixing: the review lane checked whether the code does what it says,
and the challenge lane checked what the code does at inputs no current caller
produces. A mutant restoring the blanket skip now fails `contract-none[status]`.

The transferable shape across rounds 2 and 3 is one thing seen twice: **a rule
applied uniformly across a boundary the design says is not uniform.** Both
findings were a blanket branch — one for violations, one for `None` — sitting
above a provenance split the module had already declared.

Both lanes have now run with recorded outcomes, and no lane is outstanding.

## Landing state

`implemented, both lanes run, all findings fixed`. Branch
`worktree-opencode-egress-schema`, cut from `dev` at `a632465`.

Landed: `skills/code-review/scripts/egress_schema.py` (new),
`test_egress_schema.sh` (new, ran RED before the helper existed),
`parse_opencode_review.py` (`_result` now the single choke point),
`opencode_review.sh` (inline allowlist replaced by the shared declaration).

Both lanes of the `## Review / challenge gate` have run with recorded outcomes
(see `## Executed review rounds`). The recursion note is satisfied by
observation rather than by argument: the reviewer selected on every scoring
round was **codex**, not `opencode`, so no verdict on this diff was produced by
the code under review. The claude lane was excluded throughout as
`same_family_as_implementer`.

Remaining before merge: this branch is not merged to `dev`, and merging to the
default branch is the user's call, not this plan's.
