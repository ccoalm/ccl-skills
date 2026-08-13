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
| contract-enum | `reviewer`, `status`, `mode`, `reason`, `reason_code`, `reviewer_family` | value ∈ the module's own declared set |
| contract-scalar | `cascade_eligible`, `candidate_ineligible`, `concern_evidence`, `runtime_isolation`, `credential_binding`, `transport_exit_code` | type only (bool / int / declared string) |
| export-token | `session_id`, `model`, `provider`, `version` | the grammar below |
| structured | `concern_results`, `findings`, `severities`, `locators` | shape-checked by their existing owners; unchanged here |

**export-token grammar**: `str` or `None`; length ≤ 200; every character in
`[A-Za-z0-9._:/@+-]`. That covers a provider-qualified model id, a semver, and an
opaque session id, and excludes newlines, control characters, quotes, and
whitespace — the shapes that let a value stop being a single field.

### On violation

The value is replaced with `None` and the **field name** is appended to a new
`field_schema_violations` list. Names come from the module's own declared set, so
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

| Layer | Rows | Command | State |
| --- | --- | --- | --- |
| unit (new) | 1-7, 10, 12 | `bash skills/code-review/scripts/test_egress_schema.sh` | add |
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

## Landing state

`plan drafted`. Branch `worktree-stale-records-fix`, cut from `dev`. No
implementation edits yet.
