# 124 — The transport's error channel is not stderr

## Artifact classification

`gate implementation` (per
`product-rd-workflow/references/shared-gate-artifact-classification.md`), owner
`code-review`. The changed artifact decides which `reason_code` a failed
reviewer lane reports, and `review_gate.py` routes on that code to either
cascade to the next reviewer or stop the lane, so the failure semantics of a
shared gate change here.

Risk tags (`feature-risk-router`): `shared-gate`, `security-review`,
`external-integration`.

`security-review`: **triggered**, on two paths.

1. The classifier's new input is a stream the reviewed packet can influence.
   The event stream carries model-authored text, and the packet is untrusted
   candidate data, so a diff containing `429 rate limit` could otherwise forge a
   `quota` verdict and steer the controller into cascading away from the
   reviewer it selected. The change reads only the transport's own top-level
   error events for this reason, and a fixture proves packet-derived text
   cannot reach the classifier.
2. The receipt is committed as round evidence, so anything the round puts in it
   crosses an egress boundary. The design this round finally lands answers that
   by bounding what may enter rather than by filtering what does: raw process
   output stays in the preserved run directory and never reaches the receipt.
   The redaction that remains covers a narrow, CLI-authored input and is defence
   in depth. The superseded excerpt design, and why three review chains were
   needed to reject it, are recorded under *The change*.

`visible surface: no` — a wrapper's failure classification, two receipt fields,
and the lifetime of a run directory.

## The defect

`codex_review.sh` classifies a failed run by grepping `$STDERR_FILE`:

```bash
if grep -qiE '429|rate.?limit|quota' "$STDERR_FILE"; then
  die_inconclusive codex_quota quota true "$run_rc"
```

`codex exec --json` does not report that class of failure on stderr. It reports
it as a structured event on stdout, which the wrapper redirects to `$EVENTS`.
Measured on a reproduction at 20KB of packet, exit code 1, 30s elapsed:

| stream | content | classifier regex |
| --- | --- | --- |
| `stderr.log` | `codex_models_manager: failed to refresh available models` | no match |
| `events.jsonl` | `{"type":"error","message":"You've hit your usage limit…"}` | matches |

So a quota exhaustion falls through every classifier to the terminal branch:

```bash
die_inconclusive codex_run_failed unknown_client_failure false "$run_rc"
```

Two consequences follow, and both were paid for in delivery time.

1. **The lane stops instead of cascading.** `review_gate.py` admits a cascade
   only for a `reason_code` in `CANDIDATE_LOCAL_CODES` carrying
   `cascade_eligible: true`. `quota` is in that set; `unknown_client_failure` is
   not, so the gate emits `next_action: stop_reviewer_lane`. A routine,
   self-healing supply condition is reported as an unknown client fault, and the
   recovery it forces is an operator reordering the clients by hand.
2. **The failure leaves no evidence.** The terminal branch reports
   `transport_exit_code` and nothing else, and the `EXIT` trap removes
   `$RUN_ROOT` with both captured streams inside it. Rounds 122 and 123 carry
   six receipts between them and not one codex record; the streams that named
   the cause were deleted at the moment the cause became interesting. A packet
   size hypothesis stood unfalsified across three rounds because nothing in the
   receipt could contradict it, and a 20KB reproduction refutes it.

The second consequence is the one that made the first expensive. A wrong
classification is recoverable when the receipt still says what happened.

## The change

### Classify from the transport's own error events

Extract, from `$EVENTS`, the messages of **top-level** events whose `type` is
`error` or ends in `.failed`, reading `message` or `error.message`. Write them
to a run-scoped file and give the existing quota and auth classifiers that file
in addition to `$STDERR_FILE`.

The restriction to top-level events is the security boundary, not a parsing
convenience. Model-authored content arrives nested under `item`, as
`{"type":"item.completed","item":{"type":"error",…}}`; the transport's own
failures arrive unnested. Grepping the raw stream would let the reviewed diff
choose the reviewer lane's verdict.

Classifier order and every existing reason code stay as they are. This change
adds an input to two predicates; it does not reorder or redefine them.

### Keep the streams instead of an excerpt of them

The first version of this section prescribed a redacted excerpt of both streams
in the receipt. Three review chains refuted it and it is recorded here as
superseded rather than quietly replaced, because the refutation is the reusable
part: each chain found a different escape from the same filter -- a key name the
list lacked, an assignment form the shape rule lacked, and URL userinfo, which
is not an assignment at all. Replacing the name list with a shape rule was
recorded at the time as an invariant change and was not one; names and shapes
are both enumerations of how a secret might look. The input was arbitrary
process output, and "nothing secret-shaped survives" is not a decidable property
of arbitrary text.

The original defect was also misread. The streams were not missing because the
receipt was too small. They were missing because the `EXIT` trap deletes
`$RUN_ROOT`. So:

- On a transport failure the run directory **survives**, and the receipt carries
  its path as `transport_run_dir`. It is mode 0700 under `TMPDIR` and holds
  exactly what it held while the run was in flight, so nothing is exposed that
  was not already; reclaiming it stays the platform's temp-directory lifetime. A
  path under `$HOME` is recorded with `$HOME` replaced, so a committed receipt
  carries no username. A successful run still deletes the directory and carries
  neither field.
- `transport_diagnostic` carries **only** the transport's own top-level error
  messages, deduplicated, one line, at most 600 bytes with a truncation marker.
  Raw stderr has no path into it. When no error event was captured the field
  says so and points at the directory, so key presence never has to be read as
  a success signal.

Redaction remains over that narrow, CLI-authored input -- `$HOME` and run-root
paths, URL userinfo and query strings, `sk-`, `Bearer`, JWT shapes, and the
value of any `key=value` or quoted `"key": "value"` pair whatever the key is
called. It is defence in depth, not the control the safety rests on: a provider
error can still echo a bad key. What makes the receipt safe is that the
unbounded input no longer reaches it.

Both fields are emitted on classified failures too, not only on the terminal
branch. A classified failure that is classified *wrongly* is the shape this
round is repairing, and it is invisible unless the receipt keeps what the
classifier saw.

`review_gate.py` relays unknown wrapper keys unchanged, and `egress_schema.py`
governs the opencode lane only, so no schema edit is required and none is made.

## Acceptance matrix

One independently-failable behavior per row. Each row names the stub input and
the single verdict it must produce.

| # | Input | Verdict |
| --- | --- | --- |
| A1 | usage-limit text in a top-level `error` event, exit 1 | `reason_code: quota`, `cascade_eligible: true` |
| A2 | usage-limit text in a top-level `turn.failed` error, exit 1 | `reason_code: quota`, `cascade_eligible: true` |
| A3 | authentication text in a top-level `error` event, exit 1 | `reason_code: provider_unavailable`, `cascade_eligible: true` |
| A4 | quota text only inside an `item.completed` agent message, exit 1 | `reason_code: unknown_client_failure`, `cascade_eligible: false` |
| A5 | quota text on stderr, exit 1 | `reason_code: quota` — today's behavior, unchanged |
| A6 | a failure matching no pattern, exit 1 | `reason_code: unknown_client_failure`, `cascade_eligible: false` |
| A7 | any exit-1 failure | receipt carries `transport_diagnostic`, at most 600 bytes, single line |
| A8 | an error event carrying `$HOME`, the run root, and credential-shaped values, whatever the key is called | none of them appear in `transport_diagnostic` |
| A9 | an agent message carrying a unique marker | the marker does not appear in `transport_diagnostic` |
| A13 | a marker written only to stderr | it does not appear in `transport_diagnostic` at all |
| A14 | any exit-1 failure | the run directory survives, is mode 0700, still holds `stderr.log`, and its path is in `transport_run_dir` |
| A10 | exit 124 past the deadline | `reason_code: timeout` — today's behavior, unchanged |
| A11 | a run that succeeds | receipt carries neither field, and the run directory is deleted as before |
| A12 | a wrapper receipt carrying A1's codes | `review_gate.py` emits a cascade, not `stop_reviewer_lane` |

## Verification plan

- **RED baseline, applied rather than argued.** A1 through A4 and A7 through A9
  are written and run against the unchanged wrapper first, and each must fail
  for the reason the row names before any wrapper edit. A4 and A9 are the rows
  that fail if the implementation reaches for the raw event stream, so they are
  the ones that must be seen red for the *right* reason, not merely red.
- **Mutation, per protected predicate.** Remove the top-level restriction and
  A4 plus A9 must turn red; remove the redaction and A8 must turn red; remove
  the bound and A7 must turn red; restore the raw-stderr fallback and A13 must
  turn red; delete the run directory on failure again and A14 must turn red;
  drop the URL-userinfo strip or the quoted-value alternation and the shape row
  must turn red. A predicate whose removal breaks nothing is not carrying the
  invariant it claims.
- `bash skills/code-review/scripts/test_cli_review_wrappers.sh`
- `bash skills/code-review/scripts/test_review_gate.sh`
- `make test-code-review`
- `make test` plus the heavy lane, since `make test` excludes it.

## Test and register coverage

New behaviors extend the existing codex stub in
`skills/code-review/scripts/test_cli_review_wrappers.sh`, which already drives
the wrapper through `STUB_BEHAVIOR` and already exercises exit-1 transport
paths. No new test file is introduced, so no runner registration changes; the
suite is already in `make test-code-review`.

## Status sync

The round's own review ledger and the landing register row. No product or
release status document tracks reviewer-lane classification.

## Review and challenge gate

Required, per the `shared-gate` tag: an independent review and a challenge on
the same candidate. The codex client is unavailable to review this round — its
account quota resets after the round's expected close — so the lane runs on
kimi, and the unavailability is recorded rather than reported as a passing gate.

## Non-goals

- **The kimi lane's identical shape is not swept here.** `kimi_review.sh`
  splits its streams the same way and classifies from stderr only, but whether
  that CLI reports quota on its event stream is untested, and the codex finding
  does not establish it. Testing it needs a forced failure against a live
  account. Recorded as a follow-up, not assumed to be the same defect.
- Restoring codex availability. The quota window is an account condition, not a
  repository one.
- Making the remaining redaction provably complete. It is not completable over
  arbitrary text, which is why the arbitrary text was removed from its input
  instead. A CLI-authored error message can still echo a credential, and that
  residual is stated rather than closed.
- Widening `CANDIDATE_LOCAL_CODES` or changing what any existing reason code
  means.
