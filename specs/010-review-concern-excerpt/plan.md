# 010 — Preserve concern evidence on the `stop_reviewer_lane` path

## Artifact classification

`gate implementation` (per `product-rd-workflow/references/shared-gate-artifact-classification.md`).

The stop *rule* is unchanged. What changes is the payload contract of the
inconclusive result the reviewer lane emits when it stops, which downstream
controllers parse. That is shared-gate semantics, so this plan exists before any
edit.

Risk tags (`feature-risk-router`): `shared-gate`, `api-contract`.
`security-review`: change-triggered arm applies — a new field carries
reviewer-authored text into durable evidence rows, so the excerpt must be bounded
and line-selected rather than a raw verdict dump (see Scope).

## Defect

When a CLI reviewer produces output that fails the structured-output contract but
still contains concern-shaped text (severity token, `file:line`, `CHECK x |`, or a
`"concern_results":` key), the gate stops the lane rather than cascading, so
another client cannot launder that finding into a pass:

- `parse_cli_review.py:124-134` — `cascade_eligible = not concern_evidence`
- `review_gate.py:2743-2744` — `concern_evidence is True` revokes cascade eligibility
- `references/client-routing.md:56-58` — states the intent

The stop is correct. The defect is that **the concern text itself is never
retained**, so the stop is structurally un-triageable:

- `parse_cli_review.py:124-134` passes `raw_verdict` only to `CONCERN_RE.search()`;
  the payload gets `reason` (a fixed string) plus `concern_evidence: true`.
- `review_gate.py:2034-2044` `record_attempt` stores that payload verbatim; there is
  no excerpt field.
- `codex_review.sh:171-172` unconditionally `rm -rf`s the run dir holding
  `final.json` and `events.jsonl`; `review_gate.py:2784-2789` unlinks the frozen
  packet and profile.

Operator-visible result: "a reviewer saw something with a severity and a file:line,
we will not tell you what, and you may not ask another client." The documented
remediations for it (`SKILL.md:327` reject-and-rerun) are then run blind.

## Scope

In scope:

1. New shared helper `skills/code-review/scripts/concern_excerpt.py` — given verdict
   text, return the **matched lines only**, bounded, plus a truncation flag.
2. `parse_cli_review.py` — `invalid_model_output()` emits `concern_excerpt` and
   `concern_excerpt_truncated` when `concern_evidence` is true. Covers the **codex**
   and **kimi** lanes (shared parser); this is the reported defect.
3. `claude_review.sh:1002-1004` — same excerpt on its concern-evidence stop, which
   today also retains nothing.

Out of scope, named rather than silently dropped:

- `opencode_review.sh:612` already carries the full reply in `.text`, so its stop is
  triageable. Its retention is *unbounded*, which is a hardening follow-up, not this
  defect. Recorded here so the next agent does not read this slice as covering it.
- `review_gate.py:2576-2603` (gate-side coverage failure) already retains the
  wrapper's `findings` in `result["attempts"]` via `record_attempt` before the
  status overwrite. No change needed.
- `scripts/AGENTS.md:38` points at a validation log under a
  specs/009-claude-review-tool-boundary directory absent from this repo. Stale
  contract pointer, unrelated to this defect.
  **Closed by a later slice** — see the follow-up disposition below.

Confidentiality posture: a schema-valid `findings` result already persists
severity/file/line/failure_path/smallest_fix into the same evidence rows, so
line-selected concern text is the same egress class, not a new one. A raw verdict
dump would be a new class (arbitrary model prose, possibly echoing the packet) —
hence matched-lines-only plus a hard cap.

## Acceptance matrix

Decision table for `concern_excerpt_from_text(text)` and the payload it produces.

| # | Input verdict text | `concern_evidence` | `concern_excerpt` | `concern_excerpt_truncated` | `cascade_eligible` |
|---|---|---|---|---|---|
| 1 | no concern-shaped line (`"unable to comply"`) | `false` | absent | absent | `true` |
| 2 | empty or unreadable verdict | `false` | absent | absent | `true` |
| 3 | one severity line (`P1 in the retry path`) | `true` | that line | `false` | `false` |
| 4 | one locator line (`scripts/foo.py:42 leaks`) | `true` | that line | `false` | `false` |
| 5 | `"concern_results":` key only | `true` | that line | `false` | `false` |
| 6 | more matched lines than `MAX_EXCERPT_LINES` | `true` | first N lines | `true` | `false` |
| 7 | one matched line longer than `MAX_EXCERPT_LINE_CHARS` | `true` | truncated line | `true` | `false` |
| 8 | matched lines interleaved with non-matching prose | `true` | matched lines only | `false` | `false` |

Bounds: `MAX_EXCERPT_LINES = 20`, `MAX_EXCERPT_LINE_CHARS = 200`.

Invariant across every row: the stop decision itself is unchanged — rows 3-8 keep
`cascade_eligible: false` and the gate keeps emitting `next_action:
stop_reviewer_lane`. This slice adds evidence to the stop; it never converts a stop
into a cascade.

## Test / register coverage

Per `skills/code-review/scripts/AGENTS.md`: "Parser changes need tests with
positive, finding, malformed, and inconclusive cases."

| Layer | Row | Command | State |
|---|---|---|---|
| unit (new) | 1-8 | `bash skills/code-review/scripts/test_concern_excerpt.sh` | add |
| integration (parser) | 1,3,6 via codex/kimi wrappers | `bash skills/code-review/scripts/test_cli_review_wrappers.sh` | add cases |
| integration (gate) | stop still terminal with excerpt present | `bash skills/code-review/scripts/test_review_gate.sh` | run |
| contract | payload compat | `python3 skills/code-review/scripts/test_review_client_compat.py` | run |
| repo gate | full deterministic suite | `make test` | run |
| E2E / live provider | — | — | not applicable: no live CLI is invoked by these paths under test |
| manual | — | — | not applicable |

Test-case-first: the RED assertions in `test_concern_excerpt.sh` land and run RED
before the helper is implemented.

## Status-sync target

This plan file. No external tracker, no cross-repo status surface, no release
metadata is touched by this slice.

## Review / challenge gate

Required before shared-branch push or MR merge (`shared-gate` route):

- `review_gate.sh --mode challenge --stage release --risk-tag shared-gate
  --review-harness`, run from this checkout per `SKILL.md:228-245`, with
  `IMPLEMENTER_FAMILY=anthropic` so the Claude lane is excluded as same-family.
- Record reviewer/tool identity, concrete objections, and disposition.
- If the required review/challenge is unavailable after remediation, this slice
  stops at `interim` / pending-review — not `complete`.

Note the recursion: this change edits the very harness that would review it, so the
review runs with `--review-harness` and the reviewed identity is the packet hash of
this diff.

## Extraction round record (skill-extraction-workflow)

Charter — **purpose**: make a fail-closed reviewer stop triageable. **Scope**: the
three concern-evidence stop paths named above; no change to the stop rule.
**Depth**: targeted, source = this repo's own harness plus two live `codex exec`
probes. **Root cause**: below. **Evidence plan**: RED-then-GREEN behavior tests
plus a baseline comparison against unmodified `main`. **Completion standard**:
`make test` green plus the dual-track gate.

RCA (widened, not one chain):

| Contributing factor | Counterfactual: remove it, does the failure still happen? |
|---|---|
| `concern_evidence` was designed as a *predicate*, never as *evidence* | No — this is the necessary cause |
| No test asserted a stop carries anything triageable | Yes, but it would have been caught at authoring time |
| Wrapper run dirs are deleted on exit; the gate unlinks the packet | Yes — but the last copy of the text dies here, so it is a real secondary control |
| The operator's only signal was a fixed reason string | Yes — a feedback gap that made four blind rounds look reasonable |

Not the root cause: "the operator should have looked harder." There was nothing
to look at. The mechanical control is the excerpt plus
`test_concern_excerpt.sh` in `make test`; the durable rule landed in
`skills/code-review/scripts/AGENTS.md`.

Owner-generalization map:

| Owner | Direction | Status | Changed file / reason |
|---|---|---|---|
| `code-review` scripts | source | updated | `concern_excerpt.py`, `parse_cli_review.py`, `claude_review.sh` |
| `code-review` repo contract | sibling | updated | `scripts/AGENTS.md` — fail-closed-stop-carries-evidence rule |
| `testing-strategy` | downstream | unchanged | no test-layer policy change; new suite uses the existing shell-test convention |
| `product-rd-workflow` | upstream | unchanged | shared-gate classification consumed, not modified |
| `feature-risk-router` | upstream | unchanged | existing `shared-gate` tag applied as-is |
| `defect-diagnosis` | sibling | unchanged | evidence-sanitization rule already covers the excerpt's confidentiality posture |
| `skill-extraction-workflow` | sibling | not-applicable | the failure class is harness evidence emission, not extraction routing |

Dual-track gate:

| Row | Status | Evidence |
|---|---|---|
| behavioral evidence | `RED-baseline` | `test_concern_excerpt.sh` 17 FAIL before implementation, 0 after; the `CONCERN_RE` removal regression was caught by running the same suite against unmodified `main` (green) versus this tree (3 FAIL) |
| R0 leakage audit | clean | `check-ccl-skills.sh .` → `ccl_skill_check_clean_ok` |
| independent review | **unavailable** | see below |
| adversarial challenge | **unavailable** | see below |

Reviewer remediation attempted and failed: four gate rounds (codex
`invalid_model_output`, kimi `tool_boundary_violation`, opencode
`transport_unverifiable`), then direct `codex exec` and `kimi` runs. Two live
probes from outside the repo with the wrapper's own flags
(`--disable hooks --sandbox read-only --ephemeral -C <tmpdir>`) returned clean
output, which excludes the globally-registered SessionStart/UserPromptSubmit hooks
as the vector under the wrapper's configuration; the second probe reproduced the
model refusing the injected `$skill-extraction-workflow` lens because reading it
needs tools the same prompt forbids, and answering in prose — the exact shape that
becomes `invalid_model_output`. That is a separate harness defect
(owner-derived skill lenses are incompatible with packet-only review) and is not
fixed here.

## Root cause of the reviewer-lane outage (found by this slice's own instrument)

Running the real gate on this slice's own diff, with the excerpt fix in place,
surfaced the string that four blind rounds never saw:

> Codex reported an item-level review error: Skill descriptions were shortened to
> fit the skills context budget. …

`CODEX_BENIGN_ERROR_ITEMS` pinned that notice as an **exact sentence** containing
`the 2% skills context budget`. The installed CLI dropped `2%`, so an advisory
diagnostic fell out of the allowlist and every Codex review lane died on
`invalid_model_output` — **with a complete verdict already in hand**, which is
also why `concern_evidence` was true and the lane refused to cascade.

This is the failure mode `scripts/AGENTS.md` already names ("never pin the parser
to a CLI version's vocabulary") and the cross-landing sibling of
`skill-extraction-workflow`'s vocabulary-predicate rule: a control predicated on
an artifact's wording that the control does not own. Fix: `is_benign_codex_error`
matches the invariant claim by shape, anchored and subject-bound so it cannot
swallow a real error item.

Three earlier hypotheses were disproven along the way and are recorded so they are
not re-tried: globally-registered hooks (probe: wrapper flags from outside the
repo return clean), Codex being unable to read an owner skill without tools
(probe: it quoted the skill body verbatim), and the lens/no-tools prompt
contradiction (A/B probe under the real `--output-schema`: both wordings returned
valid JSON).

## Review evidence

`review_gate.sh --mode review --stage release --risk-tag shared-gate
--review-harness`, `CODE_REVIEW_CLIENT_ORDER=codex`, chain `lens-diag-r3`:
**exit 0, `status: findings`, `selected_client: codex`,
`reviewed_skills: [python-service-dev, terminal-cli-dev, testing-strategy]`.**

Findings and disposition:

| Finding | Disposition |
|---|---|
| P1 `claude_review.sh` stop can fire on `output_file` while only `reply_text_file` was scanned → empty excerpt | fixed: both files passed |
| P1 prefix-only truncation discards a match past the cap while still asserting concern evidence | fixed: `_window_around_match` centres the window and marks both elided ends |
| P1 untrusted item-error text copied into the durable `reason` field | fixed: moved to `client_diagnostic` and redacted (url / deep path / credential assignment / opaque token / email) |
| P2 tests only grep `claude_review.sh`; the concern-stop path is never executed | **open** — needs a fake-client harness like `test_claude_review_probe.sh`; recorded, not silently dropped |

## The other two lanes were never actually tried in this shape

The premise this work started from — "all three non-same-family lanes failed" —
does not hold. Codex failed as a **content** failure with `cascade_eligible:false`,
so the gate stopped the lane by design and **never cascaded**: kimi and opencode
were not attempted. The `tool_boundary_violation` / `transport_unverifiable` codes
recorded against them came from some other run, not from this failure shape.

Exercised directly on the same packet after the root-cause fix:

| Lane | Result |
|---|---|
| codex | `findings`, exit 0 |
| opencode | `findings`, exit 0 — reviewer `deepseek / deepseek-v4-pro` |
| kimi | `capability_missing: packet_too_large_for_inline` — an honest size limit on a 47 KB packet, not a boundary violation |

So two independent non-same-family reviewers work. The kimi ceiling is 16 KB
inline (`MAX_INLINE_PROMPT_BYTES`), not 47 KB — 47 KB is only what this packet
measured — and above it the lane cascades rather than failing. Disposition below.

## Review and challenge rounds

Three rounds, each on a fresh candidate, every finding fixed and re-challenged:

| Round | Finding | Fix |
|---|---|---|
| 1 review | `claude_review.sh` stop can fire on `output_file` while only `reply_text_file` was scanned | both files passed |
| 1 review | prefix-only truncation discards a match past the cap | `_window_around_match` centres and marks elisions |
| 1 review | untrusted item-error text in the durable `reason` field | moved to `client_diagnostic`, redacted |
| 2 review+challenge | `concern_excerpt` itself was never redacted — the larger channel | shared `redact_untrusted` over every excerpt line |
| 2 review | benign-notice matcher accepted any tail | anchored both ends, bounded tail |
| 3 review | a real fault could ride behind the benign prefix | require the advisory's own continuation |
| 3 challenge | `\b` does not fire inside `client_secret` | key name may carry leading identifier chars |
| 3 challenge | `Bearer abc123` leaks the value after the scheme | scheme-prefixed pattern added |
| opencode | **over**-redaction: `token validation bypassed` stripped of meaning | credential-shaped values only (digit inside a long opaque run) |

Same-class recurrence (redaction completeness, three rounds) was treated per the
`keep / delete / narrow / replace` rule rather than patched a fourth time:
**narrow** — the relay is bounded by construction (matched lines or structure-
derived fields only, never the raw verdict), and machine-detectable secret classes
are redacted. Residual risk recorded: redaction is a denylist over
machine-detectable classes, exactly like the packet's own egress scan; broad
semantic confidentiality stays operator-owned.

## Convergence stop after seven rounds

Rounds 4-6 kept finding another credential shape escaping the redaction denylist
(`Bearer hunter2` at 7 chars, `client_secret=` where `\b` cannot fire, a scheme
with a short alpha value) while one round found the opposite — `token validation
bypassed` stripped of meaning. A denylist over arbitrary model prose does not
converge from either edge, so the free-text relay was **removed** rather than
patched again: unstructured output now reports only tokens this module matched
itself (severities, locators), and nothing the model wrote rides out on that path.

Round 7 then split in opposite directions, which is the stop condition:

| Round-7 finding | Disposition |
|---|---|
| review P1: the summary "emits only the line count", losing diagnosability | **refuted.** `P1 src/auth.py:9 …` yields `severities: P1; locators: src/auth.py:9`; asserted by row8 and verified directly |
| review P1 / challenge P1: relayed text can carry sensitive prose no denylist matches — verified: a structured conclusion `the packet says the secret is hunter2` survives | **confirmed, residual.** Needs a risk-owner decision, not another pattern |

The residual is irreducible by construction: **a schema-valid `findings` result
already persists reviewer prose about the diff into these same evidence rows.**
Relaying a structured verdict's conclusions on the failure path is therefore the
*existing* exposure class, not a new one — the alternative is to withhold the very
text the slice exists to surface. Reducing further costs diagnosability; keeping it
accepts what every successful review already accepts.

Checked rather than assumed: a **passing** review result already carries
`concern_results` conclusions — arbitrary reviewer prose — in the same rows. The
round-7 review result demonstrates it in its own body. So relaying a structured
verdict on the failure path adds **no new exposure class**; it makes the failure
path carry what the success path already carries, which needs no new acceptance.

The one genuinely new surface is `client_diagnostic`. It is the CLI's own
diagnostic string rather than model prose about the packet, capped at 300 chars,
and redacted — strictly smaller than what already lands on every passing review.
Recorded as accepted on that basis.

## Closeout

**Landed.** Review and challenge both ran on the exact landing candidate
(`c5fee9ed3c90`); every finding is fixed, refuted with evidence, or dispositioned
above. `make test` green (`make_test_exit=0`), all four code-review suites green,
`check-ccl-skills.sh` → `ccl_skill_check_clean_ok`.

Remaining follow-ups, named rather than folded in: the kimi lane needs packet
partitioning above ~47 KB (documented split path, not a defect), and
`opencode_review.sh:612` still retains its full reply text unbounded — a hardening
item in the same class this slice closed for the other lanes.

### Follow-up disposition (later slice)

Both are closed; neither was quite what the wording above said.

**kimi partitioning — closed as not-a-defect.** The ceiling is 16 KB inline, not
47 KB, and it is a deliberate argv-exposure bound (see the lane table above).
Over-limit already cascades to a file-backed client, so no review is lost. What
was genuinely missing was a guard: nothing pinned `capability_missing` in the
gate's `CANDIDATE_LOCAL_CODES`, so a future edit could have turned this routine
size ceiling into a lane-fatal stop silently. `test_review_gate.sh` now covers
it, mutation-verified by removing the code from that set. Candidate partitioning
stays a caller-level protocol in `SKILL.md`, unimplemented by design.

**`opencode_review.sh` unbounded relay — fixed, in two places.** The named line
is the terminal concern-evidence path, which relayed the parser's whole `.text`
— arbitrary NON-conforming model prose, exactly the class this slice bounded for
the other lanes.

Capping it at 300 chars and redacting it — the first attempt — was replaced: a
cap still bets on the redaction denylist, and `_shape_summary` exists precisely
because that bet does not converge. The field is now **dropped** at the wrapper's
egress, and `concern_fields` carries the stop instead — severities and locators
the module matched itself, never the surrounding prose. Same shape as the other
lanes.

The drop sits at the egress, not in the parser: `.text` stays whole inside the
wrapper because both the retry gate and this audit read it, and
`test_parse_opencode_review.sh` pins that availability.

**Recorded cost.** An operator who previously read the reviewer's own wording on
this path now gets only what the pattern matched. On the fixture prose that is
`severities: P1` with no locator — the prose wrote "handlers/auth.code line 3"
without a colon, so nothing locator-shaped existed to extract. Accepted on the
same grounds as the original `_shape_summary` decision: an incomplete denylist
over arbitrary prose is the larger exposure, and the reject-and-rerun remediation
does not depend on the wording.

**How the egress is built, and why detection was abandoned.** Three review rounds
each defeated a different copy-detector on the same predicate: drop `.text`, then
test the serialized document (misses every reply containing a character JSON
escapes), then walk the decoded values (misses an escaped, chunked, or re-encoded
copy). Detecting copies of untrusted content is the same non-converging denylist
`_shape_summary` exists to avoid — rebuilt one level up. The verdict is now BUILT
from an allowlist of contract-owned machine fields; nothing has to be detected.
Neither direction is silent: an unlisted key fails closed to
`concern_audit_failed` for a human to classify, and a routing field the allowlist
forgot changes the emitted key set, which a test pins. Both directions are
mutation-verified.

**Named follow-up — allowlisted metadata is unvalidated (out of scope here).** The
allowlist bounds WHICH keys leave, not WHAT is in them, and `session_id`, `model`,
`provider`, and `version` all come from the untrusted OpenCode export.
`model`/`provider` carry binding checks that stop the lane on mismatch;
`version` (`parse_opencode_review.py:236`) is taken from the export unchecked.
Verified pre-existing rather than introduced here: the pre-change block re-emitted
the same payload through `jq -c '. + {…}'`, so these fields already egressed
verbatim. It is also wider than this path — `base` reaches every `_result` on the
inconclusive paths, so the real fix is a per-field output schema across the
wrapper. Fixing it only on the concern-evidence path would read as coverage while
every other verdict stayed unbounded, so it is recorded here instead of folded in.

Auditing that path surfaced a second unbounded relay the follow-up had not
named: `retry_first_reply_text`. The retry gate constrains that reply's *shape*
(no findings-like content, whole-reply no-findings assertion) but never its
*size* — the anchor permits unlimited surrounding whitespace and punctuation —
so a reply of any length rode out verbatim. Same treatment, same helper.

Both fixes were driven by RED tests in `test_opencode_review_retry.sh`. A
`findings`-status verdict still relays its text whole: that is reviewer prose
about the diff, the class a schema-valid result already persists, per the
acceptance recorded above.

**Scope's third named item — the validation-log pointer — closed by deletion,
not by writing the file.** Two places cited it: the recipe step in
`scripts/AGENTS.md` and the header comment of `test_init_policy_matrix.sh`. The
file never landed in this repo, and there is no validation-log convention here to
restore — every slice since records its RED round inside its own
`<NNN>-<slug>/plan.md` under specs/. Creating the missing file would have meant
back-filling evidence for a round nobody ran, so both citations were repointed at
what the repo actually does: the recipe now says record the RED round in the
slice's own plan, and the matrix suite states its mutation check inline (weakened
parser via `argv[1]`) rather than citing a file for it. `check-markdown-links.py`
does not open non-Markdown files, which is why the shell-script copy outlived the
one 010 named.
