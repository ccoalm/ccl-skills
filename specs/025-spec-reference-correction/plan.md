# 025 — A citation frozen in the append-only ledger gets a row-bound waiver, not a template exemption

This is a **correction slice**, bounded to one pre-existing defect. It does not
re-open, extend, or re-plan round 025's landed content (the selection-evidence
discipline and the output-shape firing point, commit `f11e75d`). It repairs the
one thing that round left behind: a mandatory gate that has been RED on `dev`
ever since.

## Frozen execution context

| Field | Value |
| --- | --- |
| Base SHA (local `dev`, worktree base) | `2146df2e338e15f552e08d53ceddadc7147cf5aa` |
| Branch | `worktree-025-spec-reference-correction` |
| Defect origin | `f11e75d` (round 025) appended register row 152 |

Observed RED, reproduced against the untouched worktree at the base SHA before
any edit, with the exit status read directly rather than through a pipe:

```
$ python3 scripts/check-spec-references.py .
skills/skill-extraction-workflow/references/source-register.md:152: spec citation does not resolve: specs/*/evidence/AGENTS.md
spec_reference_check_failed: a backticked specs/ citation must name a path in this repo. Describe a dead path instead of citing it; write a path TEMPLATE without the specs/ prefix inside the backticks, or in a fenced block, so it is not read as a citation.
EXIT=1
```

`make test` runs that command, so the whole suite is blocked on it.

## Scope extension, and why it is not scope creep

The slice was opened for the citation gate alone. Running the required full suite
on the candidate surfaced two failures in the `code-review` verifier family that
had nothing to do with the citation gate and everything to do with `make test`
being unable to reach green at all. Both reproduce at the frozen base.

The first response recorded them as pre-existing and out of scope. **The risk
owner rejected that disposition and authorized fixing them in this slice**, with
the explicit conditions that no failing test may be deleted, weakened, or
skipped, that the diagnosis run through `defect-diagnosis` with persistent
evidence before any fix, and that the plan, register rows, exact-candidate gates,
and dual-track packet all be updated to match. Everything below records that.
The `interim` disposition it replaces is left visible rather than rewritten,
because the wrong first call is part of the record.

Two consequences: `code-review` becomes a changed owner package this round, so
the impact-chain gate now has something to adjudicate (unlike the citation-gate
change, whose only `skills/` path was the ledger); and the slice's completion
standard is no longer "the citation gate is green" but "the suite is green".

## Extraction Charter

| Field | Answer |
| --- | --- |
| Task or extraction name | Row-bound waiver for a citation frozen in an append-only ledger |
| Purpose | A mandatory fail-closed gate is RED on a line that the ledger contract forbids anyone from editing. Left alone it stays RED forever and the next agent's cheapest exit is to re-introduce the template exemption that round 016 deleted, or to quietly rewrite ledger history. Both outcomes cost more than the defect. |
| Scope | Included: `scripts/check-spec-references.py`, its focused suite, two `code-review` verifier suites (see the scope extension below), appended register rows, this plan. Excluded: every C3 candidate file and worktree, 023 D1/E5, the round-025 rule content itself, unrelated cleanup, releases, remote state, and any change to protection or configuration. |
| Depth | Tooling change (gate implementation), two verifier-suite repairs, and four appended ledger rows (the fourth supersedes the defeated timeout-testing lesson without rewriting it). No source re-read of the round-025 corpus: the defect is a spelling in a landed row, not a wrong lesson. |
| Failure mode analysis | Two failures. (1) The gate stays RED, so `make test` cannot pass and every later round either works around a red gate or learns that red gates are negotiable. (2) The repair is done by widening acceptance — a glob/template exemption — which restores the attack surface 016 deleted after five distinct evasions. |
| Lifecycle impact | Implementation: the checker gains a waiver table. Testing: the focused suite gains positive, negative, non-bleed, and staleness cases. Onboarding/documentation: the checker's own docstring and this plan state when a waiver is legitimate. Intake/design/launch/iteration: no output — this slice changes no routing surface, no skill rule, and no release artifact. |
| Evidence plan | First-hand only, all repo-local: the checker source, its suite, the register's row-lifecycle contract and its two recorded bends, `016`'s rejected-alternatives list, and the two existing digest-pinned waiver tables in this repo (`check-ccl-skills.sh` `exempt_historical_routes`, `register-firing-path-resolution.rb` `EXEMPT`/`EXEMPT_ROW_DIGESTS`). No external source class: this slice makes no public-best-practice claim; it implements a convention this repository owns end to end. |
| Completion standard | The focused suite is RED on the frozen base and GREEN only with the repair; every protected predicate has an applied mutation that turns the suite RED for the right reason; the required repository gates and the full suite pass on the exact candidate; the independent review and the adversarial challenge both run against that exact candidate and return a usable verdict. |

## Target-output / owner map

Derived from lifecycle impact, not from memory. Every row's status is reconciled
against the actual diff at closeout.

| Owner | Direction | Status | Changed file, or the reason |
| --- | --- | --- | --- |
| repo-root `scripts/` | the changed artifact | updated | `scripts/check-spec-references.py`, `scripts/test_check_spec_references.py` |
| `skill-extraction-workflow` | ledger / provenance | updated | `references/source-register.md` — appended rows only; `SKILL.md` is the owner key and is unchanged |
| `code-review` | the changed verifier package (scope extension) | updated | `scripts/test_parse_review_json.sh`, `scripts/test_opencode_review_retry.sh`; `SKILL.md` unchanged |
| `defect-diagnosis` | method owner for D2/D3 | unchanged | Invoked and followed; both diagnoses fit its existing Phase A–C shape with no gap to close, so there is no rule to add. The records live in this plan. |
| `testing-strategy` | test-layer mechanics | routed | Two prevention items routed to it and recorded in D2/D3: a shared fake-help emitter, and "control time or observe the actual operands, then assert the invariant rather than a guessed timing range". Not landed here — this slice has no authority to widen into that skill. |
| `product-rd-workflow` | shared-gate classification | routed | The citation-gate change is classified in this plan as a `gate implementation` with the loosening operability check run; the two verifier fixes change no gate verdict, only fixtures and one test oracle. |
| `feature-risk-router` | risk tags | not-applicable | Tags are unchanged from the `shared-gate` classification this plan already carries; no new trust boundary, authority, or external surface. |
| design / UX / release / observability / security owners | lifecycle stages | not-applicable | No user-facing surface, no rollout, no telemetry, no trust boundary is touched. Reader-facing prose is confined to this plan and to comments in the changed files. |

## RCA

**Widened, not a single chain.** Contributing factors, each counterfactually
tested against "would the RED still have happened?":

| # | Factor | Category | Counterfactual | Weight |
| --- | --- | --- | --- | --- |
| 1 | Round 025's author wrote a path *template* in the one spelling the gate reserves for *citations* | authoring | Remove it and there is no RED | necessary |
| 2 | The gate is repo-wide and fail-closed by design, so it scans the ledger like any other tracked file | by-design | Remove it and the defect is invisible — which is the state 014 existed to end | necessary, and correct |
| 3 | The ledger is append-only, so the ordinary repair (respell the token) is unavailable | contract | Remove it and factor 1 is a one-line fix | necessary |
| 4 | Nothing runs the repo gate between authoring a register row and appending it | detection gap | The author would have seen the RED before landing | secondary control |
| 5 | The checker's error message names the two conforming spellings but nothing points an author at them *while writing a ledger row* | feedback gap | Weaker than 4; the message is already correct | probabilistic, one trace |

Factors 1–3 are jointly necessary and none is individually removable: 2 and 3
are the two contracts working as designed, and their intersection is the whole
defect. This is the shape the handoff anticipated — the contracts *look*
mutually impossible — and they are not: the repository already resolved this
exact class twice, for this exact file, with a digest-pinned row-bound waiver.

**Not a root cause:** "the author should have been more careful." Writing a
`*/evidence/AGENTS.md` glob under specs/ to mean "the per-spec evidence
contract" is the natural spelling — and note that this very sentence had to be
respelled once the plan was staged, which is the point: the conforming form is
learned from the gate, not from the ledger. The row is prose about a contract
rather than a pointer to a
file, and the gate's guidance lives in the gate, not in the ledger. The
mechanical control is factor 4, and it is out of scope here (recorded as a
follow-up, not silently dropped): it needs a pre-append hook decision that is its
own round.

## What row 152 actually means

The row records that round 025's local base/head observation is **not** a frozen
measurement, and names the standard it fails to meet: the per-spec evidence
contract, of which this repository currently has exactly one instance,
`specs/023-agent-native-repo-borrowing/evidence/AGENTS.md`. The referent is real;
the token is a glob standing for the class. Nothing about the row's meaning
requires a file at the literal path, and the row's claim is unaffected by this
slice — it stays byte-for-byte as landed.

## Design

**Chosen: a waiver keyed on (repo-relative path, exact citation token) and
pinned to (line number, SHA-256 of the stored line including its terminator).**
A finding is suppressed only when all four match. The waiver is printed, never
silent. If the pinned line stops existing at its pinned number in a scanned
waived file — edited, reflowed, moved, or deleted — the gate **fails closed**
with its own reason code rather than degrading to silence.

The line number and the terminator are both in the pin because independent
review defeated the version without them; see the review dispositions below.
Content alone identifies a line SHAPE rather than an occurrence, and
`splitlines()` discards the terminator, so a digest over the stripped line does
not in fact cover the bytes the pin advertises.

This is not a new mechanism. It is the third instance of one this repository
already runs against this same ledger file:

| Existing instance | Keyed by | Pinned by |
| --- | --- | --- |
| `exempt_historical_routes` in `skills/skill-extraction-workflow/scripts/check-ccl-skills.sh` | (path, token) | SHA-256 of each waived ledger line |
| `EXEMPT` / `EXEMPT_ROW_DIGESTS` in `skills/skill-extraction-workflow/scripts/register-firing-path-resolution.rb` | row | SHA-256 of the row |
| this slice | (path, token) | SHA-256 of the waived ledger line |

The first of those records the reasoning verbatim: *"the ledger must never be
edited, so a stale mention there has no legal fix and would otherwise hard-red
the gate forever."* That is precisely this case, and its recorded choice of
digests over occurrence counts — a count says "one row", never *which* row — is
adopted here for the same reason.

### Why this is not the alternative 016 rejected

016's rejected list contains **"Allowlist the two known template strings —
predicates the gate on a vocabulary it owns."** The distinction is load-bearing
and is what the challenge lane must attack:

| | 016's rejected allowlist | This waiver |
| --- | --- | --- |
| Predicate | the token *looks like* a template | this exact line's bytes were reviewed |
| Reach | every file, every line, every occurrence | one file, one line, one token |
| Same token elsewhere | passes | **blocks** |
| Same token after the line changes by one byte | passes | **blocks** |
| A different template spelling | passes | **blocks** |
| Grammar to evade | yes — five evasions were found | none: there is no grammar, only a byte comparison |

A glob has no special status in the changed checker. `CITATION_RE` is untouched,
`resolve_target` is untouched, containment is untouched. A backticked token
beginning `specs/` is still a citation and still must resolve; one immutable line
is exempted by identity, not by shape.

### Rejected alternatives

- **Respell the token in row 152.** Forbidden by the append-only contract, and
  explicitly out of bounds for this slice: the row must stay auditable and
  byte-stable. The two recorded bends of that contract do not cover this — the
  first retargets paths that *stopped* existing after a rename, the second
  removed a row asserting something *false*. Row 152 asserts nothing false and
  names nothing renamed.
- **Widen `CITATION_RE` so a glob is not a citation.** The deleted 016 exemption
  in new clothing. Rejected without further analysis; re-introducing it is the
  outcome this slice exists to prevent.
- **Create the literal path.** Back-filling a missing target is the anti-pattern
  register row 112 already records ("repair the pointer to what the repo actually
  does rather than back-filling the missing target"), and here it would mean a
  directory literally named `*`.
- **Append a correction row and leave the gate RED.** An appended row cannot
  change what a scanner sees on line 152. It is necessary and not sufficient, so
  it is done *as well*, not *instead*.

### Design-time operability check (this change LOOSENS a verdict)

Run before landing, per the rule that a loosening is checked hardest because it
removes evidence instead of adding a red.

| Leg | Finding |
| --- | --- |
| author-dogfood | The authoring workflow passes end to end under CI's base resolution: the repository gates and `make test` are run on the exact candidate, and the waiver's own line is printed by the gate it waives. |
| marginal-cost | Zero for the cheapest routine change. A round that adds an ordinary spec citation, a register row, or a skill edit never touches the table. The table is touched only when a *new* citation is frozen into an immutable line — twice in this repository's history before this slice. |
| trust-model fit | Exactly one byte-identical line stops owing resolution. Every other citation in every other file, and every other token on that same line, still owes it. The gate's declared trust model — an honest author citing a path that does not exist — is unchanged; a waiver requires editing a table whose diff is a mandatory review artifact, and applied waivers are printed on every run. |
| premise check | Not a pure loosening: it ships a **tightening** in the same change — a pinned digest that no longer matches any line in a scanned waived file fails the gate. A clean run on the current corpus is not evidence for that leg, so it carries its own applied mutation (see the mutation table). |

## Invariants and the negative cases that pin them

| # | Invariant | Case |
| --- | --- | --- |
| I1 | Row 152 stays byte-stable and auditable | `git diff` touches no line of the register except the appended row; `test_shipped_waivers_all_apply_to_this_repository` re-verifies the pin against the live file, so an edit or reflow of row 152 turns the suite RED on its own |
| I2 | A genuine unresolved `specs/` citation still fails | the pre-existing suite, run unmodified, plus `test_waiver_is_token_bound_on_the_pinned_line` |
| I3a | The waived token in a **different file** still fails | `test_waiver_does_not_bleed_to_another_file` |
| I3b | The waived token on a **different line of the waived file** still fails | `test_waiver_does_not_bleed_to_another_line`, `test_one_byte_change_to_the_pinned_line_stops_the_waiver` |
| I3c | A **different** glob/template spelling still fails everywhere | `test_other_template_spellings_still_fail` |
| I4 | The waiver is bound to one token and cannot suppress an unrelated bad citation **on the same waived line** | `test_waiver_is_token_bound_on_the_pinned_line` |
| I5 | Ordinary valid citations, locators, fragments, containment all unchanged | the pre-existing 43 cases, run unmodified |
| I6 | A stale pin fails closed rather than degrading to silence | `test_stale_pinned_digest_fails_closed`, `test_stale_pin_is_a_cli_failure` |
| I7 | A waiver for a path absent from the corpus is inert, not an error | `test_waiver_for_absent_file_is_inert` |
| I8 | Applied waivers are printed, never silent | `test_shipped_waiver_is_printed_by_the_cli` |
| I9 | A locator or fragment appended to the waived token is a **different** token and still fails | `test_waived_token_with_locator_still_fails` |
| I10 | The ledger row is machine-checked, on real attribution and with no fabricated owner claim | see the note below — the row is adjudicated by `register-firing-path-resolution.rb`, whose locator count moves 66 to 67, and whose oracle was shown to fail on this row |
| I11 | A waiver covers non-existence only; a citation that leaves the checkout is never waivable | `test_waiver_never_covers_a_containment_escape` |
| I12 | The waiver binds ONE occurrence: a verbatim copy of the pinned row elsewhere in the same file is still a finding, and the pinned row at a different number is not waived | `test_verbatim_duplicate_of_the_pinned_line_still_fails`, `test_pinned_row_moved_to_another_line_is_not_waived` |
| I13 | The pin covers the line's stored bytes, terminator included: an LF-to-CRLF rewrite or a dropped final newline breaks it | `test_crlf_terminator_change_breaks_the_waiver`, `test_missing_final_newline_breaks_the_waiver` |
| I14 | One waiver is spent by ONE citation: the same dead token twice on the pinned line leaves the second a finding | `test_waiver_is_spent_by_one_citation_on_the_pinned_line` |
| I15 | A waiver whose token is absent from its pinned line covers nothing and is stale, rather than sitting there matching a line and subject nobody has | `test_waiver_naming_a_token_absent_from_the_pinned_line_is_stale` |
| I16 | The two repaired `code-review` cases fail for the reason they NAME, not merely with the right exit code | the reason-code assertions in `test_parse_review_json.sh`, with a fixture mutation that flips them |
| I17 | "Covers something" is decided on PARSED citations, not raw text: a waiver token that is only a substring of a longer citation, or appears unbackticked in prose, still covers nothing and is stale | `test_waiver_token_that_is_only_a_substring_of_another_citation_is_stale`, `test_waiver_token_only_in_unbackticked_prose_is_stale` |
| I18 | A shipped waiver may not be voided by REMOVING its file: for the default table scanning its own repository, a waived path absent from the tracked corpus is stale and RED, while a foreign corpus or an explicitly passed table stays inert | `test_deleting_the_waived_path_is_stale_and_red`, `test_untracking_the_waived_path_is_stale_and_red`, with `test_control_waived_path_present_still_passes`, `test_foreign_corpus_without_the_waived_path_stays_inert` and `test_explicit_waiver_table_stays_inert_on_absence` as the compatibility positives |
| I19 | The formal OpenCode run budget is exactly the invocation's remaining lane budget minus the clamped export reserve; scheduler jitter changes the remaining operand, not the relation | `test_opencode_review_retry.sh` captures those two actual operands from a test-only wrapper trace and compares the emitted timeout to their difference; a double-reserve mutant fails exactly this case |

### Which gate actually adjudicates the appended row

Recorded because the first reading was wrong and a silent exit 0 would have been
taken as a pass.

`impact-chain-gate.rb` returns 0 with no output on this candidate, and that is
**correct rather than a skip**: `upstream_for_round` derives changed owners from
`skills/<owner>/...` paths and opens with `next nil if path == LEDGER_PATH`, so
the ledger is excluded from owner derivation by construction — otherwise every
round that appends a row would demand a row for `skill-extraction-workflow`
forever. The only path this slice touches under `skills/` **is** the ledger, so
this round changes no upstream owner and the gate has nothing to adjudicate. No
claim is made that it "accepted" the correction.

The gate that does adjudicate the row is
`skills/skill-extraction-workflow/scripts/register-firing-path-resolution.rb`,
which re-resolves every locator in the whole ledger on every run. Its count moves
**66 at the frozen base to 67 on the candidate** — the added locator is mine, and
it resolves. Its oracle was shown to be capable of failing on *this* row rather
than assumed: pointing the row's `command:` locator at a non-existent script, at
a path that escapes the repository, and at an empty declaration each exits 1 and
names `source-register.md:153`, with the unmutated control green at 67.

The gate is also diff-scoped over committed history, so an uncommitted candidate
cannot exercise it at all. That is why the synthetic commit and probe worktree in
the executed trace exist: without them a green run would only mean HEAD equals
base.

## Defect D2 — `test_parse_review_json.sh`: a fixture left behind by a wrapper's tightened contract

Owner: `defect-diagnosis` for the diagnosis, `code-review` for the artifact.
Complexity verdict: **complex** — the test layer is itself causal, and more than
one control failed.

| Field | Record |
| --- | --- |
| Symptom | The suite exits **2** with completely empty stdout and stderr. No assertion output, no failure name. |
| Reproduction | `bash skills/code-review/scripts/test_parse_review_json.sh` — exit 2, deterministic, 100%. Identical at the frozen base in a clean `git archive` copy, so it is pre-existing rather than candidate-induced. |
| Assertion evidence read first | The silence is `set -euo pipefail`: the failure is the command substitution on the first wrapper call, so the shell dies at that line before any `printf`. Traced with `bash -x`, the wrapper returned `{"status":"inconclusive","reason":"Claude CLI cannot prove that safe mode disables inherited Claude skills and customizations","reason_code":"capability_missing"}`. |
| Hypotheses | (a) the local real `claude` CLI leaks into the test — **rejected**: an argv-logging shim proved the only invocation was `claude -p --help`, served by the fixture on `PATH`; (b) the probe invocation's args drifted from what the fixture parses — **rejected**: the probe never ran; (c) the fixture's `-p --help` text cannot satisfy a newer wrapper predicate — **confirmed**. |
| Proven cause | `claude_review.sh` gates on `has_help_flag "--safe-mode" && safe_mode_disables_skills`. `safe_mode_disables_skills` parses the help text for a line *beginning* `--safe-mode` and reads its **description** for evidence that skills are disabled. All three fakes in this suite emitted the flag names as one flat space-separated line with no descriptions, so `capture` never fired, the accumulated text was empty, and the predicate could never return true. `has_help_flag` is field-based across lines and was satisfied, which is why every earlier gate passed and only this one failed. |
| Which side drifted | `git log -S safe_mode_disables_skills` gives one commit, `5bcd277 fix(code-review): harden provider review transports`. It added the predicate and touched ten sibling test files. Only **two** files in that package carry a fake `claude -p --help` surface at all — `test_claude_review_probe.sh` and `test_parse_review_json.sh` — and the commit updated the first and not the second, whose last touch is the repository's init commit. The wrapper is right and the fixture was missed. (An earlier draft of this row said "four sibling fixtures"; that counted touched test files rather than files carrying the surface the predicate reads, and is corrected here rather than left standing.) |
| Fix | The three fakes now emit one flag per line with descriptions, `--safe-mode` carrying the same skills-are-disabled wording the already-updated sibling uses as its passing form. The flag SET of each fake is unchanged, so each fake's intent is preserved. **The wrapper's predicate is untouched** — the fix is in the artifact that drifted. |
| Verification | Suite exits **0**, `parse_review_json_tests_ok`. |
| Second defect the fix exposed | The `tool_enabled` case asserted `rc = 2` and `inconclusive` and was **passing for the wrong reason** — it was rejected by the help-text gate, never reaching the tool-boundary check it exists to exercise. With the fixture repaired it is rejected with `reason_code=tool_boundary_violation`, `declared_tools=bash,structuredoutput; invoked_tools=bash`. The assertion now discriminates what it claims to. |
| Mutation control | Collapsing `--safe-mode` back to a bare flag name in the no-tools fake alone restores the original symptom. Recorded honestly: the first attempt at this mutation ran a copy of the suite from a temp directory, which exits 2 because it cannot resolve its sibling `parse_review_json.py` — a non-zero exit for the wrong reason, which is not evidence. It was redone in place. |
| Regression evidence | The repaired fixture *is* the regression control: it fails closed the moment the wrapper's help contract tightens again, because the fake's description is what the predicate reads. |
| 5 Whys / prevention | Failure → the fixture's help text cannot satisfy the predicate → the predicate was added and its fixtures swept in one commit, and this one was missed → nothing mechanically couples the wrapper's help-text contract to the fakes that must satisfy it, and each fake open-codes its own help → **the control that should have caught it did fire**: `make test` has been RED on `dev` since `5bcd277`. So the prevention is not a new gate. Two items are recorded and routed rather than built here: a shared fake-help emitter so one contract change cannot leave a fixture behind (routes to `testing-strategy` / the `code-review` scripts owner), and the question of how a red `make test` was allowed to persist on `dev`, which is a maintainer/landing-discipline question and not the agent's to answer. |

## Defect D3 — `test_opencode_review_retry.sh`: an assertion pinned to a wall clock

Owner: `defect-diagnosis` for the diagnosis, `code-review` for the artifact.
Complexity verdict: **complex** — intermittent, and timing is causal.

| Field | Record |
| --- | --- |
| Symptom | Intermittent single failure: `FAIL - OpenCode caps the pre-inference boundary probe and preserves the unspent formal budget`. Observed failing once in a batch run and passing on repeat. |
| Flake discipline | Not called flaky from the label. Measured: it failed under concurrent load and passed idle, and was then made **deterministic** — see reproduction — so the final classification is a timing-sensitive assertion, not an unexplained flake. |
| Not the cause | The same run's stderr carries `opencode_review.sh: line 1181: printf: write error: Bad file descriptor`, which is the tempting culprit. **Rejected**: that line is the wrapper's final stdout write and the identical message appears on runs that exit 0, so it is an unrelated exercised path, not this failure's mechanism. |
| Proven cause | The wrapper computes the formal budget as `remaining_lane_timeout() - export_reserve`, i.e. `TIMEOUT - elapsed - clamp(TIMEOUT/10, 3, 10)`. At `TIMEOUT=180` that is `170 - elapsed`, and `elapsed` is **whole seconds** from `SECONDS - LANE_BUDGET_STARTED`. The assertion grepped for the literal `170s opencode run`, which is true only while the boundary probe and everything around it finish inside one integer second. One second of jitter yields `169s` and the grep fails. |
| Deterministic reproduction | `STUB_BOUNDARY_DELAY_S=1 bash skills/code-review/scripts/test_opencode_review_retry.sh` → exit 1, failing **exactly and only** that check — the same single failure as the intermittent one. |
| First fix, later defeated | The literal `170` was replaced with `160 <= formal <= 170`. That removed the one-second cliff, but an exact-candidate review supplied a double-reserve mutant whose formal timeout is `160`; the widened assertion accepted it. The claim that "nothing else lands inside" the range was false. |
| Final fix | The deterministic probe cap stays an exact `60s`. For the formal budget, the test enables Bash xtrace only inside this synthetic wrapper invocation, captures the actual pre-reserve `run_timeout` and the final clamped `export_reserve`, and requires the timeout passed to `opencode run` to equal their difference. Wall-clock delay is already represented in the captured remaining operand, so no timing tolerance is needed. The production wrapper is untouched. |
| Mutation control | A temporary copy of the real wrapper changes the single subtraction to `remaining - reserve - reserve`. The focused execution reports exactly one failure, the named budget case (`fail_count=1`). The unmutated control records `remaining=180`, `reserve=10`, formal `170` and passes. This applied mutation replaces the earlier point evaluation, which proved only that the two bounds executed and not that they excluded arithmetic regressions. |
| Verification | The complete suite exits **0** with `opencode_review_retry_tests_ok`; the prior deterministic delay reproduction remains compatible because the oracle uses the invocation's actual remaining operand. |
| 5 Whys / prevention | Failure → an exact wall-clock-derived value was pinned → the first repair widened it to a guessed range → the range's lower endpoint was itself a plausible arithmetic bug → synthetic point values checked the predicate's edges but did not mutate the producer → **prevention is to control time or observe the producer's real operands and assert the semantic relation, then apply a producer mutation**. Routed to `testing-strategy`; not landed there in this bounded slice. |

## Acceptance matrix

| # | Input | Before | Expected |
| --- | --- | --- | --- |
| 1 | this repository at closeout | **fail** | pass |
| 2 | the waived token, waived file, pinned line | fail | pass — waived, and reported |
| 3 | the waived token, waived file, line altered by one byte | fail | fail |
| 4 | the waived token, a different tracked file | fail | fail |
| 5 | a second dead citation on the pinned line itself | fail | fail |
| 6 | a different glob spelling anywhere | fail | fail |
| 7 | the waived token plus `:12` locator on the pinned line | fail | fail |
| 8 | pinned digest matches nothing, waived file present | pass | **fail** — `spec_reference_waiver_stale` |
| 9 | pinned digest matches nothing, waived file absent | pass | pass — inert |
| 10 | a pinned line whose waived token escapes the checkout | fail | fail — containment is unwaivable |
| 11 | a verbatim copy of the pinned line on another line of the same file | fail | fail — only the pinned occurrence is waived |
| 12 | the pinned line present but at a different line number | fail | fail, and the pin goes stale |
| 13 | the pinned line rewritten LF to CRLF, or the final newline dropped | fail | fail, and the pin goes stale |
| 14 | the waived ledger file deleted, shipped table, own repository | pass | **fail** — `absent-from-tracked-corpus` |
| 15 | the waived ledger file untracked, shipped table, own repository | pass | **fail** — same |
| 16 | a foreign corpus lacking the waived path | pass | pass — inert |
| 17 | an explicit or empty waiver table against this repository | pass | pass — inert on absence |
| 18 | every pre-existing acceptance row (014/016) | as recorded | unchanged |

## Test / register coverage

| Layer | Rows | Command |
| --- | --- | --- |
| unit | 2-18 | `python3 scripts/test_check_spec_references.py` |
| repo gate | 1 | `python3 scripts/check-spec-references.py .` |
| owner gates | — | `check-agent-contract-coverage.sh`, `check-ccl-skills.sh`, `check-public-sanitization.py`, `check-markdown-links.py`, `make eval-routing`, `git diff --check` |
| full suite | — | the 38 `make test` recipe steps, run individually with direct exit statuses (see the environment-limit section) |
| verifier repairs | — | `test_parse_review_json.sh`, `test_opencode_review_retry.sh`, each also run directly on the exact candidate |

## Mutation / negative controls

Each protected predicate gets a mutation that is **applied**, observed to turn
the suite RED, and attributed differentially — the owning case fails, the
unmutated control is green.

| # | Mutation | Predicate it proves load-bearing | Expected owning failure |
| --- | --- | --- | --- |
| M1 | drop the pin comparison entirely, keying the waiver on (path, token) only | the pin, not the token, is what binds the waiver to one row | the different-line case stops failing |
| M2 | drop the path from the key | the waiver is file-bound | the other-file case stops failing |
| M3 | waive every finding on a pinned line instead of the waived token only | the waiver is token-bound | the same-line unrelated-citation case stops failing |
| M4 | make a missing pin a warning instead of an error | the staleness tightening is load-bearing | the stale-pin case stops failing |
| M5 | key the waiver on the resolved target rather than the raw token | a locator/fragment variant would inherit the waiver | the locator case stops failing |
| M6 | drop the not-escaped condition from the waiver guard | containment is unwaivable | the containment-escape case stops failing |
| M7 | drop the corpus-scope guard on staleness | a waiver is inert against a corpus that lacks its file | the absent-file case stops failing |
| M8 | compare pins by digest only, ignoring the line number | the waiver binds one occurrence | the duplicate and moved-row cases stop failing |
| M9 | normalize the terminator before digesting | the pin covers the stored bytes | the CRLF and missing-final-newline cases stop failing |
| M10 | match the waiver token against the line's raw text instead of its parsed citations | liveness is decided on parsed citations, never by substring | the substring, prose and locator cases stop failing |
| M11 | remove the spend key from the waiver guard | one waiver is spent by one citation | the repeated-token case stops failing |
| M12 | force the presence guard off | a shipped waiver's file must reach the corpus | the deleted and untracked cases stop failing |
| M13 | make the presence guard unconditional | inertness survives for a foreign corpus and an explicit table | the foreign-corpus, explicit-table and three pre-existing fixture cases start failing |

Thirteen mutations, control green, each owning case failing under its own mutant. M12 and M13 are a
PAIR by design: the presence guard has two conditions, and they must fail in opposite
directions — turning the guard off must break the two new failure paths, and making it
unconditional must break the compatibility positives. One mutation could only ever prove
half of it.
Three of these anchors had to be repaired when the guard became multi-line: they
reported `anchor not unique` and were **skipped**, which the harness prints
rather than counting as a pass — recorded because a skipped mutation silently
read as a covered one would be the same false-green class as the runner defect
below.

M9 is deliberately a terminator-NORMALIZING mutant rather than a
hash-the-stripped-line one: stripping would also break the positive waiver case,
so it would prove the digest is used at all without isolating terminator
sensitivity. Recorded because the first attempt made that mistake.

A second recording, because a mutant that fails for the wrong reason is not
evidence: M6's first form still referenced a variable this round had renamed, so
it raised and reddened thirteen cases. Its owning set became a single case once
the mutant actually compiled.

Results are recorded in the executed-trace section at closeout, not predicted
here.

### Coverage note, recorded rather than smoothed over

The mutation harness found a real defect in **this plan**: a backticked glob in
the RCA section that the repository gate could not see, because the file was
still untracked and `git ls-files` returns tracked paths only. It surfaced the
moment the harness staged its copy. Two consequences are kept: the sentence was
respelled in the conforming form, and every gate in this slice is run against a
**staged** worktree, since an unstaged candidate is a candidate this gate does
not scan.

## Declared scope, and the residual it accepts

- The waiver table is inside the repository it gates. So is every other control
  here, and the recorded trust model is explicit that machinery defending against
  the gated repository's own author defends against an adversary this gate
  already excludes. The reviewer-visible artifacts are the table's diff and the
  printed waiver lines.
- A pinned line that legitimately changes requires regenerating its digest and
  saying why in that commit. That is the intended cost, and the ledger's
  append-only rule makes it rare by construction.
- If the exact pinned line were duplicated verbatim elsewhere in the same file,
  both copies would be waived. Duplicating a 4567-byte ledger row verbatim
  carries no citation the waiver does not already cover, so this is accepted and
  recorded rather than defended against.
- Factor 4 of the RCA — nothing runs the repo gate between authoring a register
  row and appending it — is **not** closed here. It is a pre-append hook decision
  with its own blast radius and belongs to its own round.

## Not in scope, and why

- Round 025's landed rule content: correct, and unrelated to the spelling defect.
- The C3 candidate files and worktrees, and 023 D1/E5: different owners, deferred
  by the dispatching handoff.
- Any change to `CITATION_RE`, `resolve_target`, `escapes_root`, or the
  containment model: the defect is not in any of them, and 016's residual
  declaration still stands unamended.

## Review round 1 — findings and dispositions

Lane 1 ran through the `code-review` owner gate against packet
`a028d94a…`, reviewer **codex / OpenAI family**, `claude` skipped at preflight
as `same_family_as_implementer`, plan `implementer-supplied`, chain tracked,
`native_skill_binding=established`, all eight concerns answered. Verdict:
**findings**, two P1. Both were reproduced first-hand before anything was
changed, and both were real.

| # | Finding | Verified | Disposition |
| --- | --- | --- | --- |
| P1-1 | A verbatim copy of the pinned row elsewhere in the same file matches the same path, token and digest, so the copy is waived too and `seen_pins` collapses the two into one | Reproduced: two identical lines gave 0 findings and 2 waivers | **Fixed.** The pin now carries the line number, so only the pinned occurrence is waived. Two cases and mutation M8 |
| P1-2 | `splitlines()` discards the terminator before the digest, so an LF-to-CRLF rewrite keeps the pin matching although the stored bytes changed | Reproduced: a CRLF terminator left the row waived | **Fixed.** The digest is taken over the line as stored. Two cases and mutation M9 |

The plan had recorded P1-1's shape as an accepted residual, reasoning that a
byte-identical copy carries the same already-waived citation and so smuggles
nothing. That reasoning is intact but the disposition was wrong: the waiver's own
acceptance criterion says it binds one line, and it did not. Recorded rather than
quietly rewritten.

The same finding also flagged that the packet displayed row 152's SHA-256 as
`73d3e6f2…` while the shipped table pinned `3c59fffd…`, and inferred a bug. The
real explanation is that the packet's display hashed the row **with** its
trailing newline (`awk` re-appends one) while the table hashed it without —
both correct over different inputs. Under the fix the two agree, because the pin
is now the newline-inclusive digest. The reviewer reached a correct conclusion
from a partly wrong mechanism; the conclusion is what mattered.

## Review round 2 — findings and dispositions

Re-run against the hardened candidate, packet `4d8826c…`, same reviewer family
(codex / OpenAI), `claude` skipped as same-family, both lanes tracked on one
chain and bound to the same packet hash. Review returned two findings, the
adversarial challenge two more.

| # | Lane | Finding | Verified | Disposition |
| --- | --- | --- | --- | --- |
| R2-1 | review | The predicate runs per regex match with no consumption state, so the same dead token twice on the pinned line is waived twice — one reviewed waiver covering two unresolved citations | Reproduced: two identical citations on the pinned line gave 0 findings and 2 waivers | **Fixed.** A waiver is spent by one citation, keyed `(path, token, pin)`. Case plus mutation M11 |
| R2-2 | review | Acceptance claims about gates and the full suite are narrative in the packet, and the plan file the changed gate now cites is not shown to exist | Premise **refuted** on the file: the plan is present in the candidate tree and, being a new file, is added in full. The packet omitted it | **Input defect, not a candidate defect.** Packet widened to carry the plan's addition and machine-readable gate output bound to the candidate; the lane is rerun rather than the candidate edited |
| C-1 | challenge | Two halves. (a) the duplicate-token case above. (b) a pin is marked seen from line number and digest alone, so a mistyped or obsolete waiver token sits there covering nothing and never goes stale | (b) reproduced | **Fixed.** A pin is seen only when the entry's token is actually a citation on that line. Case plus mutation M10 |
| C-2 | challenge | The packet shows only the changed fake help text, so a reviewer cannot confirm the repaired assertion fails for the named reason rather than passing through another early gate | Fair on the packet | **Both halves taken.** Packet widened with the full predicate; and the constructive half is landed — the two cases now assert the exact `tool_boundary_violation` and `capability_missing` reason payloads, with a fixture mutation proving they flip |

**A controller self-audit finding, caught before spending the next round.** The
first fix for C-1(b) tested the waiver's token against the line's raw text, which
is a substring test: a token that is only part of a LONGER citation, or that
appears unbackticked in prose, would have marked the pin seen while the entry
covered no citation at all — the covering-nothing hole reopened one level down.
The line is now parsed once with `CITATION_RE` and the same parsed token set
feeds both the seen-marking and the scan, so the two cannot disagree. Two cases
and mutation M10. One existing expectation moved in the strict direction as a
result: the locator-variant case now also asserts the waiver is **stale**,
because a waiver naming a token that is not a citation on its pinned line covers
nothing.

A harness defect is recorded alongside: the evidence runner read
`REVIEW_CHAIN_ID` from the environment without exporting it, so a valid tracked
`findings` result raised `KeyError` and was reported as non-conclusive, which
would have thrown away a good review round. Fixed in the runner only — it is a
temporary evidence script, not a product artifact.

## Review round 3 — findings, dispositions, and the exhausted budget

Packet `56d52e1…` (79 KB, widened), candidate `920b417`, reviewer codex / OpenAI,
`claude` skipped as same-family, both lanes tracked on one chain and bound to the
same packet hash. This round consumed autonomous indices 1 and 2 of its chain;
across the task the Agent-autonomous budget is now **exhausted**
(`autonomous_reviews_remaining=0`, `autonomous_review_allowed=false`).

| # | Lane | Finding | Disposition |
| --- | --- | --- | --- |
| R3-1 | review | The candidate adds 465 lines to a plan the gate now cites, and the packet supplies none of its contents | **Input defect.** The packet now carries the full plan patch. Not a candidate edit |
| R3-2 | review | Row 152's raw bytes are absent and the displayed digest only repeats the value embedded in the waiver, so the packet cannot independently verify the pin, the parsed token, or its occurrence count | **Input defect.** The packet now carries row 152's raw bytes for base and candidate, byte lengths, independently reproducible digests, and the occurrence count, with the reproduction command |
| R3-3 | review | The appended ledger row claims 43-to-56, 13 added cases and seven mutations while the diff adds 21 methods, the suite reports 64 and the table lists eleven — durable false evidence in an append-only row | **Fixed, and the most valuable finding of the round.** Corrected to 43-to-64, 21 cases, eleven mutations with all four new mutants described. The same class was then swept: "updated four sibling fixtures" counted touched test files rather than files carrying the surface the predicate reads, and is corrected to ten touched files of which exactly two carry a fake help surface |
| R3-4 | challenge | No full-suite result and no direct results for the two repaired verifier scripts, so verifier fireability and the release gate stay unproven | **Valid and outstanding.** It is an evidence gap, not a code defect. Being closed by running every `make test` step individually with its direct exit status |

No code defect survived this round. Everything remaining is evidence the packet
did not carry.

**Why the review lanes stop here.** The gate's Agent-autonomous ceiling is the
initial review plus four challenges. Three external rounds were spent on real
candidates (one review, then a review-plus-challenge pair, then this pair);
`autonomous_review_allowed` is now false. Two earlier gate invocations returned
`self_review_incomplete` before any provider ran and consumed no round, and one
in-flight round was stopped before a provider started because its attestation
still described the pre-hardening pin — recorded so the count is auditable rather
than asserted. A fourth round is therefore **not** started autonomously; closure
is a `post_review_budget` deep self-review plus an exact-candidate `complete`
checkpoint, and any further external review is the risk owner's decision.

## The evidence runner's own false-green defect

Recorded because it nearly put fabricated passes into this plan, and because it
is the same failure class the slice exists to fix — a check that cannot fail.

The first per-step suite runner captured its status as
`local rc=${PIPESTATUS[0]}` followed by `rc=$?`. The second line reads the status
of the **assignment**, which is always 0, so every step recorded a pass whatever
it did. Three steps had already been reported green from that runner; those
results are **retracted**, not reinterpreted.

Three changes followed. The status is now captured by `rc=$?` as the first
statement after the command group with nothing preceding it. A `--control` mode
runs a deliberately failing step and a step exiting 7, and the ledger records 1
and 7 — so the recorder is shown able to record a failure before any result from
it is trusted. And the step list is no longer hand-copied: it is parsed from the
Makefile's `test:` recipe, with a `--verify` mode that diffs the executed
sequence against that recipe, so an omitted or reordered step is a mismatch
rather than silent coverage. The parse yields 38 steps against 38 tab-indented
recipe lines.

## Full-suite evidence, and the one environment limit on it

`make test` is run as its 38 recipe steps, each with its own direct exit status,
because a single aggregate run cannot complete here: every process in this
environment — foreground or background — is terminated at roughly ten minutes,
observed five times with `Terminated: 15` and a 144 exit. Per-step results are
also stronger evidence than one aggregate code, so this is not only a workaround.

The step list is parsed from the Makefile's `test:` recipe rather than
hand-copied, and `--verify` diffs the executed sequence against that recipe and
**exits non-zero** on any mismatch, duplicate, or non-zero step.

One step does not fit the cap by itself: recipe step 2,
`test_check_ccl_regressions.sh --fast`, is a loop over roughly twenty
sub-regressions that needs longer than ten minutes (its own timing lines show
`test_check_ccl_skill_catalog` at 54s and `test_check_ccl_route_drift` at 135s
among many). Whatever that step's row records is recorded honestly, including a
termination. Its substance is covered separately by running each test in its
`fast_tests` array individually with its own direct exit status, into a clearly
labelled supplementary ledger — the wrapper itself adds only the ordering, the
per-test timing lines, a terminal token, and an advisory listing tests that are
in neither array. That supplementary coverage is named as such and is **not**
presented as the aggregate step passing.

## Human-requested chain h1 — the omission bypass, and its fix

A fourth chain was **explicitly authorized by the user** for candidate `0d561a7`
after the autonomous budget was exhausted. It sits outside that budget: the gate
has no human-requested flag and allocates its counters per chain, so a fresh
chain necessarily starts at index 1, which is not a reset. Both lanes ran on
packet `dcf09164…`, reviewer codex / OpenAI, `claude` skipped as same-family.

| # | Lane | Finding | Verdict |
| --- | --- | --- | --- |
| h1-1 | review | the corpus is read with `Path.read_text()`, so universal-newline mode converts CRLF to LF, the CRLF row keeps the LF pin, and the CRLF case should fail | **REFUTED.** The checker contains zero `read_text(` and two `read_bytes(`; the corpus is read as bytes and decoded with surrogateescape, so no newline translation is possible. The CRLF case passes — the finding's own predicted failure does not occur — and an end-to-end probe with the shipped LF pin shows the LF row waived while the CRLF row is not waived, `stale=1`, `findings=1`, with a positive control |
| h1-2 | challenge | deleting, renaming or untracking the waived ledger file means `git ls-files` never yields it, so its pins are never checked and the gate exits 0 with the waiver covering nothing | **CONFIRMED for delete and untrack** (rename reds correctly, because the renamed file still carries the citation). Reproduced against the shipped table: deleted and untracked each gave `findings=0 waived=0 stale=0`, CLI exit 0 |

h1-2 is a genuine bypass by omission: the guard was voided by removing the file
rather than by satisfying it, breaking this plan's own claim that a waiver is
never left covering nothing. It does not let a dead citation pass — an unscanned
file suppresses nothing — but untracking the append-only ledger would drop it
from this gate's corpus entirely while the gate stayed green.

**Fixed, on explicit user authorization to repair it, with no further review
chain.** Absence is now an error under two conditions that must both hold: the
default shipped table is in use, and the scan root is the repository this checker
ships in. The inertness is kept exactly where it was written for — a foreign
corpus, or any caller passing an explicit or empty table — so this gate's own
fixtures are unaffected.

Evidence: 26 added focused cases, of which 25 are RED at the frozen base; the
26th is `test_foreign_corpus_without_the_waived_path_stays_inert`, which passes
at base **by construction** because it is a compatibility positive and the base
has no waiver table at all. The two new failure paths are RED against the
immediately preceding candidate `0d561a7` and green only with this fix, which is
the sharper baseline. M12 and M13 are a deliberate pair: turning the guard off
breaks the two failure paths, and making it unconditional breaks the
compatibility positives, so neither condition can be dropped silently.

The repair produced a new candidate, so the h1 authorization did not cover a
review of that new tree. The user later authorized one additional chain, h2.

## Human-requested chain h2 — the timeout verifier's false green

The h2 chain ran against pre-fix synthetic candidate `ab6aeda`, packet SHA-256
`5f26d973…`, reviewer codex / OpenAI family; Claude was skipped as the
implementer's model family. The review returned findings, so the owner gate
correctly stopped before challenge instead of treating an unresolved review as
a pass.

| # | Finding | Verdict |
| --- | --- | --- |
| h2-1 | The packet did not carry the raw ledger and machine completion evidence needed to independently verify every historical claim | **CONFIRMED as a review-input defect.** The next packet must embed those immutable bytes and direct exit records; it is not a candidate-code defect |
| h2-2 | The citation collector silently hides stale waivers when used without side-channel collectors | **REFUTED on the production call path.** The helper's contract is citation collection; the sole production caller supplies the stale and unreadable collectors, while collector-free calls are tests of citation behavior. No stale condition is dropped by the CLI |
| h2-3 | The `160..170` timeout assertion accepts a second subtraction of the ten-second export reserve | **CONFIRMED and fixed.** The applied double-reserve mutation yielded `160` and the old case passed. The new oracle captures the invocation's actual remaining budget and reserve and asserts their exact subtraction; the same mutant now fails exactly that case |

This fix changes the reviewed tree. The h2 authorization is consumed, its
challenge did not run because review returned findings, and no further external
review or challenge is inferred from the user's instruction to fix the defect.

## Review / challenge gate

A fresh exact-candidate review and challenge remain required before completion.
They run through the `code-review` owner gate with
`implementer-family=anthropic`, a complete frozen packet that includes the raw
ledger and machine completion evidence, and a reviewer from a different model
family. The challenge remains directed at gate-fireability and
bypass-by-omission, and now also at the timeout relation oracle. Starting that
new external chain requires separate user authorization.

## Landing state

`interim — uncommitted post-review repair; the timeout verifier's applied
double-reserve mutation is RED, both changed verifier suites and the required
repository gates are GREEN, including the private alias audit and the clean
skill-check terminal token; the exact repaired candidate still owes a refreshed
full-suite ledger and a newly authorized external review/challenge chain`.

Nothing is committed, merged, pushed, tagged, or cleaned up. The feature branch
has not moved from the frozen base; the candidate exists only as a synthetic
commit object parented to that base, with a tree equal to the uncommitted
worktree tree, and no branch or ref was updated to reach it.

## Executed trace

The machine-readable trace for the pre-h2 candidate — candidate identity, every
command with its direct exit status and log SHA-256, the applied-mutation table,
the per-step suite ledger, the recorder control, the R0 terminal tokens, and the
review lanes' attribution and verdicts — remains under
`/private/tmp/ccl-025-spec-reference-evidence/`. It is retained as history but is
not completion evidence for the repaired tree. The new focused and repository
gate logs are under its `fix/` child. The clean skill check is bound to the
actual local-dev parent SHA rather than the stale remote-tracking ref. The final
candidate identity and completion index are regenerated after this status edit;
counts are not copied here because they drift as soon as one case changes,
which is the defect an earlier review found in this slice's own ledger row.

What that trace must show for this slice to be more than interim: the 38 recipe
steps each exiting 0 with the executed sequence matching the recipe; the focused
suite green with its added cases RED at the frozen base; every applied mutation
RED against a green control; the private-R0 clean tokens; row 152 byte-identical
to base; and both review lanes conclusive on one frozen packet with every code
finding dispositioned.

## Human-requested chain h3 — independent oracles and shipped-entry semantics

The user authorized a direct manual Claude run. The first command used the
installed gate with `--review-harness`; it stopped at policy validation before
selecting a provider, so it is retained as an inconclusive invocation and is not
counted as review. The corrected h3b chain used the repository-local gate against
committed candidate `04b8b47` and one frozen packet, SHA-256
`b758023bad20890850b27a2f16b7daf63f83c09c21050fec29f8f7cef3dff876`.
Claude passed the fact/consistency review, then returned three challenge
findings. That review and challenge cover only the pre-fix candidate.

| # | Finding | Disposition |
| --- | --- | --- |
| h3-1 | The timeout test derived both operands of its semantic relation from wrapper-owned trace values, so a second subtraction inside the producer could move them together and pass | **Confirmed and fixed.** The test now anchors the remaining budget to the externally supplied timeout and the traced elapsed value before checking the reserve subtraction. The old assertion passes the applied producer mutant; the strengthened assertion fails exactly the named case; the unmutated suite passes |
| h3-2 | Passing the shipped waiver table explicitly applied the same entries but skipped the waived-path presence guard | **Confirmed and fixed.** Presence is now decided per entry by equality with the shipped table's key and value under the owning repository, not by whether the optional argument was omitted. The new test covers both the shipped object and an equal copy |
| h3-3 | Comparing the resolved scan root with the checker's owning root can be bypassed by subdirectory, symlink, nested-checkout, or bind-mount invocation | **Refuted for this contract.** The supported repository gate scans `.`; a subdirectory is deliberately a partial or foreign corpus and must not inherit root-wide presence obligations. A symlink spelling resolves to the owning root and keeps the guard. A separate checkout or a bind mount of both script and root has its own matching owner root. No code changed for this finding |

### Remediation charter and RCA

| Field | Decision |
| --- | --- |
| Purpose | Prevent two verifier false greens: producer-owned values drifting together, and a shipped safety entry losing its semantics when supplied explicitly |
| Scope | The two confirmed h3 findings, their focused tests, the 025 plan, and the append-only impact-chain register. F3, production timeout behavior, routing, release, and repository-root semantics are out of scope |
| Depth | Targeted review-follow-up with applied killing mutations; no new skill rule or routing change |
| Root cause | F1's oracle compared values from one producer. F2 represented semantic identity with a call-site omission sentinel |
| Failure mode | A wrapper can spend the reserve twice while its verifier passes; a caller can apply a shipped waiver entry while silently dropping its deletion guard |
| Lifecycle impact | Implementation and testing only. Product intent, UI, release, onboarding, and source-less use are unchanged |
| Evidence plan | h3b review/challenge JSON, focused RED/GREEN logs, one killing mutation per confirmed finding, the F3 root-semantics probes, repository gates, and a fresh exact-candidate dual-track run |
| Completion standard | Both controls pass, both mutants fail for the named assertion, all required repository gates pass, and a newly authorized review/challenge pair is conclusive on one later frozen candidate |

The widened RCA found two latent controls rather than an implementer-diligence
problem. For F1, the test name promised budget preservation while its oracle
could not disagree with a self-consistent producer; fixing the independent
input-to-intermediate relation is necessary and the existing mutation walk is
the confirming feedback. For F2, using `None` was locally convenient because it
preserved custom-table fixtures, but it conflated invocation shape with entry
identity; per-entry shipped-content matching is the narrower control and keeps
custom entries plus foreign corpora inert. The dual-track gate itself needs no
change: its adversarial pass found both gaps before landing.

### Target-output map

| Target | Decision | Reason or firing point |
| --- | --- | --- |
| `skills/code-review/scripts/test_opencode_review_retry.sh` | updated | F1 now checks external timeout minus observed elapsed before checking remaining minus reserve; the applied producer mutant kills this assertion |
| `scripts/check-spec-references.py` and its focused test | updated | F2 keeps shipped-entry presence semantics for the shipped object and an equal copy; the guard-removal mutant kills the new case |
| `specs/025-spec-reference-correction/plan.md` | updated | Records the h3 chain, dispositions, RCA, evidence boundary, and current authorization state |
| `skills/skill-extraction-workflow/references/source-register.md` | updated | Adds append-only behavioral-evidence rows for both confirmed failure classes |
| `testing-strategy` | unchanged | Its existing core rule already rejects expectations derived from the same source and requires a killing mutation; the repaired tests are the mechanical firing points |
| `product-rd-workflow` and `code-review/SKILL.md` | unchanged | The required challenge fired and found the defects; no lifecycle or reviewer-routing rule failed |

| Source mechanism | Executable landing | Test owner | Status |
| --- | --- | --- | --- |
| A producer mutation can move all values used by its own oracle | Timeout verifier asserts an external-input relation before the downstream subtraction | `test_opencode_review_retry.sh` control plus producer mutant | landed |
| A shipped table entry must retain its guard when supplied explicitly | Checker classifies each matching shipped entry by table content under the owning root | `test_check_spec_references.py` object/copy case plus guard-removal mutant | landed |

## Current landing state after h3 findings

`interim — the h3 review is clean for the pre-fix candidate; the challenge's two
confirmed findings have focused RED/GREEN and killing-mutation evidence; and the
third finding is refuted with root-semantics probes. The focused suites and all
required repository gates pass, including private R0 with the process-retro
profile and the final ccl_skill_check_clean_ok token. The code-bearing candidate
`aaf3e9c8` has a complete 38-step ledger under the trace's
`fix/full-aaf3e9c-h3-v2` directory: 38 zero exits, command-order and log-hash
agreement, a passing recorder control, unchanged register row 152, and private
R0 clean tokens. The only later tree delta is this landing-state text. It owes
the affected Markdown, citation, sanitization, diff, coverage, and skill checks,
not a second run of unrelated runtime and hook suites. Once those incremental
checks pass, the five-file findings fix still owes only a newly authorized fresh
review/challenge pair before it can be called complete or committed.`

The first full-run attempt used a login Bash that selected the system Ruby and
failed before candidate tests; a later exact-tree replay was stopped after step
1 when the risk owner challenged the value of rerunning all 38 steps for a
status-only Markdown delta. Both attempts remain diagnostic evidence and neither
is counted as a candidate pass.

No h3 findings fix is committed, merged, pushed, tagged, released, or cleaned
up. The prior `04b8b47` commit remains the feature-branch HEAD; h3b is not review
coverage for the dirty worktree tree.

## Human-requested chain h4b — trace operands from different calls

The h4b fact/consistency review ran through the repository-local Claude gate on
the cumulative six-file packet, SHA-256
`37bba283f683c0aaeb5508d4707ff667a12d7a54d113cabba8124a980fc4ec1e`.
It returned one P2 finding and therefore did not open the challenge round.

The finding is **confirmed**. The boundary probe calls
`remaining_lane_timeout` before `run_opencode` calls it again. The test selected
the first traced elapsed value but the first `run_timeout` assignment, so a
one-second boundary delay paired elapsed `0` from the boundary call with the
later run budget and failed a correct wrapper. A disposable copy with only that
delay made exactly the named budget case RED.

The repaired case now fixes the one-second difference into its ordinary control,
records the first boundary elapsed value, and selects the most recent elapsed
value preceding the first `run_timeout` assignment. It requires the paired
elapsed value to exceed the boundary value before checking both production
relations. The complete unmutated verifier suite exits 0; the earlier producer
mutant still makes exactly the named case fail. `opencode_review.sh` remains
unchanged.

This is a new candidate. The prior 38-step ledger still covers every unchanged
runtime, hook, and gate path; the new delta is one verifier case plus this plan
and one appended source-register row. It owes the changed verifier suite, the
required repository gates, and a fresh cumulative review/challenge pair. It does
not re-owe unrelated runtime suites solely because evidence prose changed.

## Current landing state after h4b

`interim — h4b finding confirmed and repaired with a deterministic RED control,
a green complete verifier suite, and the original producer mutant still RED.
The repair is uncommitted and h4b has no challenge pass. Submission and local-dev
merge remain authorized but blocked until the refreshed gates and a new exact
candidate Claude review/challenge pair pass.`

Nothing has been merged, pushed, tagged, released, deployed, or cleaned up.

## Human-requested chains h5 and h6 — candidate binding and independent time

The h5 fact/consistency review used cumulative packet
`123f183010f63c490f76caf1b30d0e4fcd1e5bf8e79cee30552f569af6270902`
and returned one P2 evidence finding: the final candidate ledger did not contain
direct runs of all three changed tests. Those tests were run against synthetic
candidate `2971d71f`; all exited zero, with candidate, source, raw-log, and bound
transcript hashes recorded. This closed the missing-run gap, but deterministic
test output remained byte-identical to an older run.

The h6 fact/consistency review passed packet
`100128345b2166e7a270949725ec8fcf39d53ddb5513e2790b9fd64d61af9770`.
Its challenge returned four P2 findings. All four are confirmed:

| Finding | Disposition |
| --- | --- |
| The timeout oracle still trusted the producer's elapsed value | Replaced producer trace operands with monotonic timestamps written by the test stub at the boundary and formal-run entrypoints. The charged elapsed time must stay within the independently observed gap, allowing only one second on either side for integer-second quantization |
| A near-copy waiver with the shipped key but changed metadata could waive the citation while dropping the path-presence guard | Presence now follows membership of the shipped key, not equality of mutable reason or pin metadata. A changed-reason near-copy is the focused RED case |
| Selecting the latest trace value before the first run assignment inferred call identity from position | Eliminated the trace and positional pairing entirely; the external boundary/run entrypoints are the pairing surface |
| A self-written transcript header did not prove which test bytes executed | Accepted as an evidence-runner defect. The next candidate ledger must compute the test source hash inside the same captured command that executes that test; old headers are not completion evidence |

The waiver test was RED before the checker change: 70 tests ran and only
`test_explicit_shipped_table_still_requires_its_waived_path` failed. The fixed
suite exits zero. The new timeout control exits zero on the production wrapper.
A disposable mutant that adds ten seconds only when `TIMEOUT=180` makes exactly
the named formal-budget case fail; the other cases remain green. An earlier
unscoped mutant changed every short-timeout path and caused 24 failures, so it is
retained as invalid attribution evidence rather than counted.

## Current landing state after h6

`interim — the four h6 challenge findings have confirmed dispositions and the
two code/test changes have focused control and RED evidence. The candidate is
still uncommitted. It owes documentation closeout, the exact-candidate affected
tests and required repository gates with in-command source hashes, and one fresh
cumulative Claude review/challenge pair. No prior review covers this later tree.`

Nothing has been merged, pushed, tagged, released, deployed, or cleaned up.

## Human-requested chain h7 — bounded interval and executable receipts

The h7 fact/consistency review ran against candidate `3ea38fec` with packet
SHA-256 `e9109616ee581ab7f10a6ae5618f3da171c7a3ea43a1a0cbf5c8fdab471e4f60`.
It returned two P2 findings and did not open a challenge round. Both are
confirmed.

First, the parse-review receipt misspelled `parse_review_json.py` with a hyphen.
Because the compound `bash -c` command did not enable `set -e`, `shasum` failed
but the later passing test supplied the row's zero exit. The corrected runner
uses the real underscore path and `set -euo pipefail`, so a missing hash target
cannot be overwritten by a later command.

Second, the timeout verifier used boundary-entry to run-entry time for both
sides of its bound. Lane accounting starts just before the boundary timeout is
prepared, so scheduling between lane start and the stub's boundary entry is
legitimately charged but absent from that interval. The revised verifier uses
two controller-owned intervals: boundary-entry to run-entry is the lower bound
that proves the three-second boundary delay was charged; controller-before-
wrapper-launch to run-entry is the upper bound that includes all legitimate
pre-boundary work. One second on either side covers integer-second
quantization. The production-wrapper control passes, while the scoped
elapsed-plus-ten mutant still makes exactly the named case fail.

## Current landing state after h7

`interim — both h7 findings are fixed. The code remains uncommitted and the h7
review covers only its earlier candidate. The later tree owes one exact-candidate
source-bound focused ledger, required repository gates, documentation closeout,
and a fresh cumulative review/challenge pair.`

Nothing has been merged, pushed, tagged, released, deployed, or cleaned up.

## Human-requested chains h8 and h8b — historical counts and scan state

The h8 review used candidate `1d13ee35` and packet
`0a80d6dd3af0f4745fa4fe7366a152fe38286bb82079826ac438eb5e8481c72e`.
Its first P2 finding treated register row 153's 69-case count as a current total.
That reading is refuted by the register's per-round contract and a clean local
clone at the row-introducing commit `04b8b47`: the suite exits zero after 69
tests. Its second P2 finding is confirmed: three review-plan evidence strings
still named the h7 candidate. The h8b packet corrected those strings and carried
the historical checkout evidence.

The h8b review used packet
`6ea38ae2fdef13fd145abb9747a9cb4a4c00101fc530d89a9ab5df240bb9f0af`.
It returned two P2 findings. The count concern is resolved without rewriting
append-only history: a superseding row now states the cumulative progression.
Row 153 remains accurate for its own round; the accumulated suite has since
grown from 43 to 71 cases through 28 additions. Twenty-five historical RED
cases plus the later changed-reason and tracked-symlink RED cases make 27
observed RED additions across their respective pre-fix baselines.

The second h8b finding is confirmed for tracked symlinks and read failures; its
NUL example does not apply because this checker decodes bytes with
`surrogateescape` rather than skipping them. Previously, a tracked waived path
that could not be scanned received the deletion/untracking suffix
`absent-from-tracked-corpus`. A new symlink test runs 71 cases and fails only
because `present-but-unscanned` is missing. The checker now records waived paths
when `git ls-files` yields them, separately records successfully scanned paths,
and emits `present-but-unscanned` for the former-minus-latter set. The verdict
stays fail-closed; only the operator diagnosis becomes accurate.

## Current landing state after h8b

`interim — both h8b findings are closed with a superseding count row and a
focused diagnostic RED/fix. The later candidate remains uncommitted and owes
the exact-candidate focused tests, required gates, documentation closeout, and a
fresh cumulative review/challenge pair.`

Nothing has been merged, pushed, tagged, released, deployed, or cleaned up.

## Human-requested chain h9 — lane-clock identity and guarded inputs

The h9 fact/consistency review passed candidate `0a805ef9` with packet
`b7c89303f281147e4563e9127ea50ff29d67af18ac10499d70d781344224552f`.
Its challenge returned three P2 findings, all in the formal-budget test fixture.

The prior controller-before-wrapper upper interval included setup that the lane
clock does not charge, so small elapsed inflation could hide inside that slack.
The fixture now installs a test-only `BASH_ENV` DEBUG hook that records monotonic
time immediately before the production wrapper executes its
`LANE_BUDGET_STARTED` assignment. The allowed interval is therefore lane-start
to first formal-run entry; boundary-entry to that same run remains the required
lower interval. The only tolerance is Bash's one-second `SECONDS` quantization.
The production control passes, while a scoped two-second elapsed mutant makes
exactly the named case fail.

The other findings are confirmed fixture robustness defects. Clock files and
the extracted formal timeout are validated before arithmetic; a missing value
sets `budget_inputs_ok=false` and reaches the named assertion instead of
aborting the shell. Run timestamps are appended, the verifier selects the first,
and the case requires exactly one `opencode run` timeout. A disposable stub that
omits only this case's run timestamp exits with exactly the named failure and no
shell error.

## Current landing state after h9

`interim — all three h9 challenge findings are fixed with a green control, a
two-second producer mutant RED, and a missing-input named RED. The later tree is
uncommitted and owes exact-candidate focused tests, required repository gates,
documentation closeout, and a fresh cumulative review/challenge pair.`

Nothing has been merged, pushed, tagged, released, deployed, or cleaned up.

## Human-requested chain h10 — live-corpus evidence and variable identity

The h10 review used candidate `03ab5ae4` and packet
`547cc3f325fffc288123bf38bed878a646577e7d8fd93cfe0dca550ef0d18380`.
It returned two P2 findings and did not open a challenge round.

Both are confirmed. The spec-reference suite imports the checker but also reads
the live source register and specs tree, so equal checker/test hashes do not make
an older result candidate-equivalent after those corpus files change. The next
ledger must run that suite directly on the current candidate. Separately, the
seen-pin loop reused `path` for a waiver-key string while the outer file loop
used it for a `Path`. No current statement read the outer value afterward, but
the shadowing made a later use type-unsafe. The inner names are now
`waived_path` and `waived_token`; behavior is unchanged.

## Current landing state after h10

`interim — both h10 findings are fixed. The later candidate remains uncommitted
and owes a direct current-corpus spec suite, affected source-bound evidence,
required repository gates, documentation closeout, and a fresh cumulative
review/challenge pair.`

Nothing has been merged, pushed, tagged, released, deployed, or cleaned up.

## Human-requested chain h11 — exact shell clock and tracked fixtures

The h11 fact/consistency review passed candidate `3d5bce0c` with packet
`8c8b4779892418af6d6a70451c0d7a2d4921a89e1447b84a34d7acd37149309e`.
Its challenge returned five P2 findings.

Three timeout-fixture findings are confirmed and handled together. The DEBUG
hook now uses `set -T` so it observes function bodies and appends the wrapper
shell's own integer `SECONDS` value at both the unique lane assignment and the
elapsed calculation whose caller is `run_opencode`. The verifier requires one
numeric lane, elapsed, boundary, and run observation, plus one formal timeout,
before arithmetic. Charged elapsed must equal the exact observed shell-clock
difference; there is no broad timing interval. The production control passes.
Scoped `+1s`, missing-run-clock, and duplicate-boundary mutants each fail exactly
the named case and leave every other case green.

The root-equality finding is refuted under the already decided whole-repository
contract. A partial root is a partial or foreign corpus and must not acquire a
root-wide presence obligation. A copied checkout that carries the checker moves
`__file__` and its owning root together; `clone_candidate` is that positive and
its deletion/untracking cases are RED. Pointing the original checker at a second
checkout is deliberately foreign-corpus behavior.

The fixture-hermeticity finding is confirmed. `clone_candidate` no longer uses
`shutil.copytree` on the live specs directory. It enumerates `git ls-files -z --
specs` and copies only those tracked worktree bytes, preserving symlinks. An
untracked or ignored scratch citation can no longer pollute the synthetic
control, while current tracked candidate content remains under test. The
71-case control exits zero.

## Current landing state after h11

`interim — four confirmed h11 findings are fixed and the root-scope finding is
refuted against the established contract. The later tree is uncommitted and
owes exact-candidate affected tests, required gates, documentation closeout, and
a fresh cumulative review/challenge pair.`

Nothing has been merged, pushed, tagged, released, deployed, or cleaned up.

## Human-requested chain h12 — pre/post shell-clock brackets

The h12 fact/consistency review used candidate `20522c95` with packet
`f0cb70d0be5e1937596b5effa5c3c6eb14d2dd608002facc8b7b6926a75fb2e0`.
It returned one P2 finding and did not open a challenge round.

The finding is confirmed. Sampling `SECONDS` only before each producer command
still leaves a second-boundary race: the lane-start command can run after its
sample's second and the elapsed command can run after its sample's second, so an
exact pre-sample difference can reject a correct wrapper. The DEBUG hook now
appends a pre sample at each uniquely identified command and a post sample at
the next DEBUG event. The verifier requires exactly one numeric observation in
all six streams and accepts the charged elapsed only inside the resulting
controller-observed interval, from elapsed-pre minus lane-post through
elapsed-post minus lane-pre. This is a bracket over the two producer reads, not
a guessed timing tolerance.

The production-wrapper control exits zero with `opencode_review_retry_tests_ok`.
Scoped `+1s`, missing-run-clock, and duplicate-boundary mutants each leave every
other case green and fail exactly the named budget case. Production
`opencode_review.sh` remains unchanged.

## Review-entry state after h12

`At review entry, the h12 finding is fixed with a green control and three
differential RED probes. The tree is uncommitted; landing remains gated on one
frozen-candidate focused ledger, the required repository gates, and a fresh
cumulative Claude review/challenge pair.`

Nothing has been merged, pushed, tagged, released, deployed, or cleaned up.

## Human-requested chain h13b — reject ambiguous clock samples

The h13b fact/consistency review used candidate `92eb31c0` with packet
`0b3419866506e83bd9ae9b5c48069fe1b97bad34509c601983ac9fee30d3ce84`.
It returned two P2 findings and did not open a challenge round. Both are
confirmed.

First, accepting the whole pre/post interval removed the h12 false RED but
could hide a `+1s` producer regression whenever either bracket widened by one.
The fixture now treats a widened bracket as ambiguous instead of passing it. It
retries only this isolated probe up to three times and accepts a sample only
when both pre/post pairs are zero-width; exhaustion reaches the named failure.
The control deliberately widens the first elapsed-post sample, so the retry is
not an unexercised fallback. Its second sample is stable and the complete suite
passes. Against the same deterministic first ambiguity, a scoped `+1s` producer
mutant fails exactly the named budget case. Missing-run-clock and
duplicate-boundary mutants do the same.

Second, the h13b packet reported each mutant's one-failure count but omitted the
actual `FAIL -` line. The underlying logs do name the same budget case in all
three runs. The replacement packet must embed those lines so a reviewer can
verify attribution without leaving the bounded packet.

## Review-entry state after h13b

`At review entry, both h13b findings are closed: ambiguous timing samples are
boundedly resampled rather than admitted, and the next packet includes named
mutant failures. The uncommitted tree remains gated on source-bound evidence,
required repository gates, and one fresh cumulative Claude review/challenge
pair.`

Nothing has been merged, pushed, tagged, released, deployed, or cleaned up.

## Human-requested chain h14 — retry outcome, not attempt index

The h14 fact/consistency review used candidate `e6b6cb11` with packet
`c8442182fff94676b5dd7a7bbecaf2ceb83e72c3d9940efec9472827af16163e`.
It returned one P2 finding and did not open a challenge round. The finding is
confirmed.

The first ambiguous sample is forced, but the second sample can independently
cross a real second boundary. The loop correctly permits a stable third sample;
requiring `budget_attempt == 2` nevertheless rejected that recovered outcome.
The assertion now proves that the forced-ambiguity marker was consumed and that
at least one retry occurred. It does not pin which later attempt succeeds.
Cardinality, zero-width bracket, bounded exhaustion, exact charged elapsed, and
all external boundary/run checks remain unchanged.

## Review-entry state after h14

`At review entry, the h14 false-RED path is closed without weakening the
semantic oracle. The uncommitted tree remains gated on a fresh frozen candidate,
source-bound verification, and one cumulative Claude review/challenge pair.`

Nothing has been merged, pushed, tagged, released, deployed, or cleaned up.

## Human-requested chain h15b — discriminating failures and root invocation

The h15b fact/consistency review passed candidate `1aaa6f39` with packet
`c636eb584742f7a073b313850cd55a955732cc1d29ddc49936b4facfe0594f2b`.
Its challenge returned three P2 findings.

The timeout attribution finding is confirmed. Observation validity, stable
sampling, and elapsed arithmetic now have separate mutually exclusive checks.
The semantic check is not evaluated as a failure when an earlier prerequisite
is unavailable. The correct wrapper passes; scoped `+1s` fails only the
arithmetic check, missing-run and duplicate-boundary fail only observation
completeness, and forced three-attempt ambiguity fails only stable sampling.

The fixture finding is confirmed only for tracked worktree deletions. A tracked
name can be absent from disk, so the tracked-corpus copier now preserves that
absence instead of raising before the copied checker can diagnose the candidate.
The separately copied waived ledger follows the same conditional rule, and its
parent remains available to mutation cases. The positive control also requires
the terminal `spec_reference_check_ok` token. The claim that an omitted
unstaged plan could make the suite look attributed is refuted: the positive
control already requires exit zero, so an unrelated unresolved citation makes
the suite RED.

The root-scope finding is refuted as a request to change the established
whole-repository contract. Mandatory invocations in both Makefile and CI are
`python3 scripts/check-spec-references.py .`; a new focused case pins those
exact argv and the checker's owning-root identity. Partial and foreign corpus
scans deliberately retain inert shipped-presence semantics. The focused suite
now runs 72 tests.

## Review-entry state after h15b

`At review entry, the two confirmed challenge findings are fixed and the root
scope is pinned to the actual mandatory invocations without semantic expansion.
The uncommitted tree remains gated on a fresh frozen candidate, source-bound
verification, and one cumulative Claude review/challenge pair.`

Nothing has been merged, pushed, tagged, released, deployed, or cleaned up.

## Human-requested chain h16 — pure arithmetic attribution

The h16 fact/consistency review passed candidate `fed81efb` with packet
`1546a8a2c49478e7cd561f8d90e2fd87085c4ef532d06d244c97a062e03aa798`.
Its challenge returned four P2 findings.

The remaining attribution finding is confirmed. Controller exit, forced retry,
boundary ordering, minimum charged work, and the exact 60-second boundary cap
now have their own named check. The arithmetic label contains only equality
between charged elapsed and the independently observed stable value. Five
parallel runs are discriminating: the correct wrapper passes; `+1s` fails only
arithmetic; missing and duplicate observations fail only completeness; and
three-attempt ambiguity fails only stability.

The request to copy an untracked plan is refuted because it conflicts with the
already decided VCS-corpus boundary. Ambient untracked files must not enter a
synthetic candidate. If the checker depends on a target outside that corpus,
the positive control's required zero exit makes the suite RED; it cannot make
the mutants appear attributed.

The success-token concern is an evidence gap, not a production defect. The
checker's existing return precedes the token whenever `stale` is non-empty. A
stale-only CLI regression now also asserts that `spec_reference_check_ok` is
absent, making the ordering explicit in the focused suite.

The root-invocation execution concern is confirmed. In addition to pinning the
Makefile and CI text, the focused case now runs their exact argv from the
resolved repository root, requires exit zero, and requires the success token.
The shipped presence guard therefore remains bound to the actual mandatory
whole-repository invocation without changing partial or foreign scans.

## Review-entry state after h16

`At review entry, three confirmed h16 findings are closed and the untracked-file
proposal is refuted against the tracked-only fixture contract. The uncommitted
tree remains gated on a fresh frozen candidate, source-bound verification, and
one cumulative Claude review/challenge pair.`

Nothing has been merged, pushed, tagged, released, deployed, or cleaned up.

## Human-requested chain h17 — symmetric elapsed attribution

The h17 fact/consistency review passed candidate `c713297a` with packet
`0ce0e8a4f7d17ee982725572aa6814bc4ef2cde06edb60eed537a0f5a4aeeea2`.
Its challenge returned three P2 findings.

The external-checker finding is refuted under the established owner-root
contract. The supported gate is the checker shipped inside and invoked from its
own repository; a copied checker moves with a copied checkout. Installing that
checker in an unrelated tools directory and pointing it back at this repository
is neither a mandatory invocation nor a supported foreign-corpus form, and it
must not extend the shipped waiver table's reach.

The recipe-binding finding is confirmed without invoking the entire `make test`
suite. The focused test now extracts the command from the Makefile `test` target
and the CI `repository-gates` job's named Spec reference gate step, rejects any
effective workflow/job working directory, then executes the exact `python3`
argv from the resolved owner root and requires the success token.

The asymmetric attribution finding is confirmed. Controller evidence no longer
uses the producer-derived charged elapsed for its three-second floor; it uses
the independent monotonic interval between boundary and run stubs. A new
`-1s` producer mutant complements `+1s`. Both fail only pure arithmetic, while
missing, duplicate, and exhaustion retain their unique labels. The correct
wrapper passes; six parallel runs have no collateral failures.

## Review-entry state after h17

`At review entry, the two confirmed h17 findings are fixed and the external
checker proposal is refuted against the owner-root contract. The uncommitted
tree remains gated on a fresh frozen candidate, source-bound verification, and
one cumulative Claude review/challenge pair.`

Nothing has been merged, pushed, tagged, released, deployed, or cleaned up.

## Human-requested chain h18 — exact Make target anchor

The h18 fact/consistency review used candidate `78bd3d16` with packet
`7d732d5409d6b1c4fd851dabbe23f9881e05995130e9ecc8e99e682f1b56780a`.
It returned one P2 finding and did not open a challenge round. The finding is
confirmed.

The Makefile extractor still split on a bare `test:` substring, so an earlier
`fast-test:` or comment could redirect it to an unrelated block. It now finds
the first line whose text starts exactly with `test:`, then consumes only its
immediately following tab-indented recipe lines. The exact spec-check command
must be one of those lines. CI job/step scoping, working-directory checks, and
the executed owner-root argv remain unchanged. The 72-case suite exits zero.

## Review-entry state after h18

`At review entry, the h18 configuration false green is closed with exact target
line and recipe boundaries. The uncommitted tree remains gated on a fresh frozen
candidate, source-bound verification, and one cumulative Claude
review/challenge pair.`

Nothing has been merged, pushed, tagged, released, deployed, or cleaned up.

## Human-requested chain h19 — effective CI enablement and waivable liveness

The h19 fact/consistency review passed candidate `5d50d3d0` with packet
`365973f3c9151ef8ab86e0897405a2fea874fe31b72205c0984ab91ceeca184d`.
Its challenge returned three P2 findings. All are confirmed.

Effective CI cwd is now checked independently of YAML key order. The test scans
every top-level `defaults` block wherever it appears and rejects a run working
directory there, while separately rejecting any working directory inside the
`repository-gates` job. An initial whole-file prohibition correctly failed on
the unrelated npm job and was narrowed rather than weakening that job. The
repository-gates job header and the named Spec reference gate step also reject
an `if:` key, so the mandatory command cannot remain textually present while
being disabled.

Waiver liveness now uses the same hard boundary as waiver application. A pin is
seen only when its parsed token resolves to a non-escaping target. A pinned
containment escape therefore remains an ordinary finding and also makes the
covering-nothing waiver stale. The focused containment case now asserts both
outcomes. The 72-case suite exits zero.

## Review-entry state after h19

`At review entry, all three h19 findings are closed: effective CI cwd and
enablement are pinned, and containment-only waivers cannot appear live. The
uncommitted tree remains gated on a fresh frozen candidate, source-bound
verification, and one cumulative Claude review/challenge pair.`

Nothing has been merged, pushed, tagged, released, deployed, or cleaned up.

## Human-requested chain h20 — fail-closed CI keys

The h20 fact/consistency review used final candidate `2290ee60` with chained
packet `61e203396fdfa3b7ab378f7b230bcffac82f1bf9cb618d9cff4d64ea30cea9ab`.
It returned one P2 finding and did not open a challenge round. The finding is
confirmed.

Job-level YAML keys are order-independent just like top-level defaults. The
test now rejects a four-space `if:` anywhere in the full `repository-gates` job
rather than only before `steps`. It also rejects job-level
`continue-on-error`, and the named Spec reference gate step rejects its own
eight-space `if:` and `continue-on-error`. These indentation-specific checks do
not prohibit unrelated steps or jobs from using their own controls. The
72-case suite exits zero.

## Review-entry state after h20

`At review entry, the h20 CI-disable paths are closed while unrelated job
configuration remains allowed. The uncommitted tree remains gated on a fresh
frozen candidate, source-bound verification, and one cumulative Claude
review/challenge pair.`

Nothing has been merged, pushed, tagged, released, deployed, or cleaned up.

## Human-requested chains h21/h21b — resolver domain and CI reachability

The h21 fact/consistency review used candidate `f941616a` with packet
`504f0acbfd2385a172afbac3328dd95031817f43811be69eae67638dc8d1d819`.
Its sole P2 assumed `resolve_target` could return `None`; the function is
str-only and the scanner skips its only false value, an empty string, before
waiver application. The repository bytes were unchanged for the evidence-only
h21b packet `17744ccd3a968b114e35412d60e9573660b459457c51ec3e8aab8090f03f20e5`;
review passed, then challenge returned three P2 findings.

The first challenge example remains unreachable under the production citation
grammar, whose matches always start with a non-empty `specs/` prefix. The guard
nevertheless now states the complete invariant with `bool(waived_target)`, and
a widened-parser regression proves an empty-resolving token cannot make a pin
live. This prevents a later grammar change from splitting application and
liveness semantics.

The other two findings are confirmed. The mandatory CI assertion now pins the
workflow entry contract—unconditional pull requests and the established
push-to-main branch—and rejects a `needs` dependency on `repository-gates` in
addition to cwd, `if`, and `continue-on-error` overrides. The source register
also corrects its h17 evidence wording: missing-run and duplicate-boundary are
different mutants in the same observation-completeness failure class, so they
intentionally share one label. The focused suite now runs 73 tests.

## Review-entry state after h21b

`At review entry, the h21b findings are either closed or source-refuted: empty
targets cannot mark waivers live, workflow entry and job dependencies are
pinned, and timeout attribution is described per failure class. The
uncommitted tree remains gated on a fresh frozen candidate, source-bound
verification, and one cumulative Claude review/challenge pair.`

Nothing has been merged, pushed, tagged, released, deployed, or cleaned up.

## Human-requested chain h22 — semantic trigger contract and shared waiver predicate

The h22 fact/consistency review passed candidate `506e3f4a` with packet
`022cbeaf0f3b14ef0ce67e42404726b4fcac2c1ed297d1fa0fb45329b7a63144`.
Its challenge returned four P2 findings. All are confirmed as delivery-evidence
or maintainability defects rather than changes to the accepted product scope.

The final evidence must be embedded in the packet body, not only summarized in
the review plan beside an older evidence block. Waiver application and
liveness now call the same `waiver_can_apply_to_target` predicate, and its test
pins empty, escaping, and eligible resolved targets directly instead of
mocking one hypothetical parser. This removes both the split semantic and the
test's dependence on a second citation grammar.

Workflow entry is now checked semantically with PyYAML's BaseLoader. Equivalent
spellings—quoted `on`, comments, inline event lists, legitimate event types,
and branch filters that retain `main`—stay green. Missing pull-request or push
events, path filters, exclusion of `main`, and pull-request type lists without
`opened` and `synchronize` fail with a specific message. The existing job and
step checks still reject `needs`, cwd overrides, `if`, and
`continue-on-error`. Positive and negative trigger tables bring the focused
suite to 75 tests.

## Review-entry state after h22

`At review entry, all h22 findings are closed: final logs are required inside
the next packet, waiver application and liveness share one directly tested
predicate, and CI entry is semantic without locking valid YAML formatting. The
uncommitted tree remains gated on a fresh frozen candidate, source-bound
verification, and one cumulative Claude review/challenge pair.`

Nothing has been merged, pushed, tagged, released, deployed, or cleaned up.

## Human-requested chain h23 — declared semantic-test dependency

The h23 fact/consistency review used candidate `a41cdb9d` with packet
`6016303cb57381b3c15f379a94a33ba83f2bff4e4df6ee9a6b1a63aa8b2d29af`.
It returned one P2 finding and did not open a challenge round. The finding is
confirmed.

The semantic workflow check imports PyYAML at module load, while the repository
previously declared that dependency only as duplicated CI install arguments.
`requirements-test.txt` now names the existing `pytest` and `pyyaml` test
dependencies. Both CI jobs install from that file, and the contribution guide
uses the same command for local setup. The trigger contract remains mandatory;
it is not conditionally skipped when dependencies are missing.

## Review-entry state after h23

`At review entry, the h23 dependency gap is closed through one contributor-and-
CI manifest. The uncommitted tree remains gated on a fresh frozen candidate,
source-bound verification, and one cumulative Claude review/challenge pair.`

Nothing has been merged, pushed, tagged, released, deployed, or cleaned up.

## Human-requested chain h24b — staged manifest and executable dependency wiring

The corrected h24b candidate `ba3d26c1` explicitly included the previously
untracked requirements manifest and used packet
`548fd48d3838b53992c40e8998de1c20144168e48d51c276c7f3309fe4b88161`.
Fact/consistency review passed; challenge returned one P1 and three P2
findings. All are confirmed as delivery-chain or evidence gaps.

The real commit path must stage `requirements-test.txt`; a synthetic tree is
not enough. Before final review, the exact candidate paths are staged and the
manifest is verified with `git ls-files --error-unmatch`, so a tracked-only
commit cannot omit the file CI now consumes.

The dependency contract now has a permanent firing point. The 76th focused
case reads the manifest, requires exactly `pytest` and `pyyaml`, checks checkout
precedes the named install step in both CI jobs, rejects install/job cwd
overrides, and confirms CONTRIBUTING uses the same root command. A separate
`pip install --dry-run --ignore-installed` resolves the clean would-install set
instead of reporting only packages already present in the developer
environment.

## Review-entry state after h24b

`At review entry, all h24b findings are closed: the manifest is part of the
real staged candidate, dependency wiring and step order are mutation-sensitive,
and clean resolution has ignore-installed evidence. The candidate remains
gated on source-bound verification and one cumulative Claude review/challenge
pair.`

Nothing has been merged, pushed, tagged, released, deployed, or cleaned up.

## Human-requested chain h25 — diagnostic semantic anchors

The h25 fact/consistency review used staged candidate `d1df90cf` with packet
`9c83378b0f216eab30679ed6d0b2e898c7d2d62629b03f6454e58c7a508358ce`.
It returned one P2 finding and did not open a challenge round. The finding is
confirmed.

The dependency-wiring case no longer locates checkout by exact action version
or installation by a mutable step label. It accepts any `actions/checkout@*`
version, locates the exact manifest command, and fails missing anchors with
job-specific messages instead of bare `StopIteration`. A disposable checkout
v5 plus renamed-install control remains green; missing-checkout and missing-
manifest-install probes each fail with their named diagnostic. The production
suite remains 76 tests.

## Review-entry state after h25

`At review entry, the h25 false-red and opaque-diagnostic paths are closed
without weakening checkout-before-install semantics. The staged candidate
remains gated on source-bound verification and one cumulative Claude
review/challenge pair.`

Nothing has been merged, pushed, tagged, released, deployed, or cleaned up.

## Human-requested chain h26b — executable install-line recognition

The compact h26b closure review passed candidate `8e8eb624` with packet
`f50f3ed2899ddade669b27d3f2e6de33ba75d216c813e9406595d5aab48efe12`.
Its challenge returned one P1 and three P2 findings. All describe the same
confirmed root defect: substring matching proves a textual mention, not an
executed dependency command.

`step_runs_exact_command` now accepts only a non-comment `run` line whose
stripped text exactly equals the required command and treats null or non-string
run values as non-matches. The owning test also rejects step-level `if` and
`continue-on-error`. A permanent decoy table covers echo, comment, null, and
list values, bringing the focused suite to 77 cases. The install step still
accepts benign label changes and checkout action-version upgrades.

## Review-entry state after h26b

`At review entry, the h26b false-green and opaque-TypeError paths are closed by
one permanently tested executable-line predicate. The staged candidate remains
gated on source-bound verification and one Claude closure review/challenge
pair.`

Nothing has been merged, pushed, tagged, released, deployed, or cleaned up.

## Human-requested chain h27 — full dependency execution hierarchy

The compact h27 closure review passed candidate `7d05d7b6` with packet
`9d2d35ff904f9c01c8c027dcecc2b1a56ba3a7d60148e85e09ffcef3147c7248`.
Its challenge returned one P1 and four P2 findings. They share one confirmed
cause: step-level matching alone does not prove the job and workflow preserve
owner-root execution.

Each CI job now has a separate, single-command Python dependency step. The
shared `dependency_wiring_violation` validates root and job run defaults,
job-level `if`, `continue-on-error`, and `needs`, exactly one checkout-family
step with no disabling or alternate-path options, checkout-before-install
ordering, exactly one whole-step manifest command, and no install-step
disabling or cwd controls. Its permanent workflow table covers every rejected
class plus the echo decoy; a checkout-v5/arbitrary-label workflow is the
positive control. The focused suite now runs 78 tests.

## Review-entry state after h27

`At review entry, the h27 root/job/checkout/install bypass classes are closed
through one production-used validator and a permanent positive/negative table.
The staged candidate remains gated on source-bound verification and one Claude
closure review/challenge pair.`

Nothing has been merged, pushed, tagged, released, deployed, or cleaned up.

## Human-requested chain h28 — exhaustive hierarchy mutants

The h28 closure review used candidate `6f4c454a` with packet
`f2c29066f5bdee996311f1f3e2fe6bb909da3f9c1f9cc744a5ffda2a20d4ff3c`.
It returned one P2 finding and did not open a challenge round. The finding is
confirmed: five implemented validator branches were missing from the permanent
matrix even though the history called it exhaustive.

The rejected workflow table now also covers checkout
`continue-on-error`, checkout `sparse-checkout`, install
`working-directory`, install `continue-on-error`, and install-before-checkout
ordering. Each subcase asserts its branch-specific diagnostic. Production
behavior is unchanged and the 78-test suite exits zero.

## Review-entry state after h28

`At review entry, every root/job/checkout/install rejection branch named by the
dependency hierarchy has a permanent mutant. The staged candidate remains
gated on source-bound verification and one Claude closure review/challenge
pair.`

Nothing has been merged, pushed, tagged, released, deployed, or cleaned up.

## Human-requested chain h29 — bounded evidence and prospective matrix rule

The h29 closure review passed candidate `cc27d866` with packet
`9df06e065aa5df4a70d0ed4ff0a50852c976b5a4232a021a57fca2ebd50c5747`.
Its challenge returned four P2 findings: the compact packet omitted the
validator and the first half of the matrix, the append-only register used
future-unstable exhaustive wording, and reused-test identity lacked blob/tree
hashes. These are confirmed evidence defects; production logic is unchanged.

The durable register rule is now prospective: every new rejection branch must
land with its branch-specific permanent mutant. The next closure packet must
include the complete validator and matrix, not selected line ranges, and bind
dependency reuse to the requirements blob plus code-review reuse to the whole
subtree hash at both prior and final candidates.

## Review-entry state after h29

`At review entry, h29 evidence scope is explicit and future-stable: the packet
must show complete source plus prior/final object identity, while later
validator growth carries its own mutant obligation. The staged candidate
remains gated on one Claude closure review/challenge pair.`

Nothing has been merged, pushed, tagged, released, deployed, or cleaned up.

## Human-requested chain h30 — structural matrix and executable identity gates

The h30 evidence-closure review passed candidate `dc25bb40` with packet
`0e9e0b2ec1c87105da7bb3ff23c2362d873aed620e21637d8cd88cccf6fbf6d5`.
Its challenge returned one P1 and three P2 findings. The identity commands
produced empty logs, the full source exposed unmutated structure/cardinality
branches and the default two-job path, and the latest register evidence still
contained a completed-coverage sentence. All are confirmed evidence defects.

Identity gates must print prior and final object IDs before comparing them. The
matrix now includes invalid YAML and document shapes, non-mapping defaults/jobs/
steps/checkout options, missing and duplicate checkout/install steps, and a
default two-job case where only `regression-heavy` is disabled. The register
keeps only the prospective obligation; it makes no permanent completeness
claim for the current table.

## Review-entry state after h30

`At review entry, h30 identity evidence is required to be non-empty and
machine-compared, while every newly identified structure/cardinality path has a
candidate-bound mutant. The staged candidate remains gated on one Claude
closure review/challenge pair.`

Nothing has been merged, pushed, tagged, released, deployed, or cleaned up.

## Human-requested chain h31 — prove both object-comparison directions

The h31 closure review used candidate `3868dfb8` with packet
`2f0604c3ece1a59547efe043e92e05f71a1e1521662ebef77cf9051003fc9278`.
It returned one P2 finding and did not open a challenge round: the packet
showed equal prior/final object IDs and a zero gate exit, but did not show the
comparison command or prove that unequal objects make the same predicate fail.
The finding is confirmed; production and test behavior remain unchanged.

The reusable evidence command is:

```bash
compare_blob() {
  prior_blob=$(git rev-parse "$1:$3") || return
  final_blob=$(git rev-parse "$2:$3") || return
  printf 'path=%s prior=%s final=%s\n' "$3" "$prior_blob" "$final_blob"
  test "$prior_blob" = "$final_blob"
}
```

Against prior `d1df90c` and candidate `3868dfb8`, applying it to unchanged
`requirements-test.txt` printed equal blob IDs and exited `0`. Applying the
same function to changed `scripts/test_check_spec_references.py` printed
`15e217415013497b0033104239e81df5d3dec708` versus
`b7de7c64c2f8b309e33b17673fb9e5caf8ed63ce` and exited `1`; the enclosing
harness required that non-zero result and then exited `0`. Reuse is therefore
decided by an executable equality predicate whose passing and failing
directions are both observed.

## Review-entry state after h31

`At review entry, object-identity reuse is bound to a printed equality command
with candidate-specific positive and negative executions. The staged candidate
remains gated on one Claude closure review/challenge pair.`

Nothing has been merged, pushed, tagged, released, deployed, or cleaned up.

## Human-requested chain h32 — retire reuse instead of growing a permanent gate

The h32 review passed candidate `15bf30fe` with packet
`7b617413d7569f7bc2b58286b3a43f1e39024ba680f344a73fc919ff47e8011b`.
Its challenge returned two P1 and two P2 findings. Three correctly identify
that the one-time comparison evidence was incomplete: the negative pair was
not the pair named by the closure chain, not every reused object had an
individual executable result, and the packet omitted the enclosing assertion.
The fourth asks for a permanent checked-in object-comparison gate.

Candidate `81b9a40c` no longer relies on object identity or reused results, so
none of those comparison predicates adjudicates its completion. The three
affected commands were run directly against that staged candidate tree:

| Gate | Exit | Log SHA-256 |
| --- | ---: | --- |
| `python3 -m pip install --dry-run --ignore-installed -r requirements-test.txt` | 0 | `b17b873b96faf6bda1136e7760153955ea9a98196b0403b2e151b9e9a6703bed` |
| `bash skills/code-review/scripts/test_parse_review_json.sh` | 0 | `3f1a5ceb837fa8124e377f2ec62181356fba29b1765bfaf41f9bf18ccbbd02b5` |
| `bash skills/code-review/scripts/test_opencode_review_retry.sh` | 0 | `3f29d4ae7f8f0092b7e433131f903ef2c46bbfe26c6e879da477a707bf83225a` |

A permanent Git-object comparison script is intentionally not added. It would
not prove that a future review actually ran the relevant behavioral command,
and the current completion decision no longer consumes reuse evidence. Any
future candidate that chooses reuse must supply its own candidate-bound
adjudication; this candidate uses direct executions instead. Production code,
tests, CI, and dependency bytes are unchanged from h32.

## Review-entry state after h32

`At review entry, all previously reused checks have direct final-candidate
executions, so object-comparison evidence is historical and does not adjudicate
completion. The staged candidate remains gated on one Claude closure
review/challenge pair.`

Nothing has been merged, pushed, tagged, released, deployed, or cleaned up.

## Human-requested chains h33–h35 — deterministic evidence boundary

The h33 review used candidate `81b9a40c` and packet
`11968eaa7b3fb90998282a25bca24aa9dac0818bff506cfabaf35944ca605f2b`.
It returned one P2 transcription finding: the plan retained the 90-second
duration from the preceding run while the h33 result recorded 91 seconds.

The h34 review passed candidate `45782242` with packet
`e16845d2f518e23cdcf59510e8e434d46a8c2a9580bc4779b8926518d6de2f18`.
Its challenge returned three P2 findings: direct executions were not explicitly
attributed to `81b9a40c`, wall-clock durations were treated as durable facts,
and the packet asserted candidate identity without literal Git output.

The h35 review passed candidate `700654ac` with packet
`ef28d53810625cda69cfff4972b1988ec4c8a087e29e75fe5b5e7e2d7f623efe`.
Its challenge returned two P1 and two P2 findings: raw-log hashes can drift with
time and tool-version output; the no-executable-change claim needed an
executable path comparison from `81b9a40c`; the equality command was
paraphrased; and the durable history ended at h32.

This row supersedes the h32 review-entry wording. The three behavioral commands
ran directly on `81b9a40c` (tree
`d37f78d0353a70a467349e89d972b639b0707310`); their hashes identify those
recorded logs only and are not reproducibility predicates. For candidate
`212d852a`, the executed `git diff --name-only 81b9a40c 212d852a` returned
exactly this plan path, and the index tree equaled its candidate tree. This is a
historical candidate fact, not a gate or evidence inherited by future
candidates. Any future executable change must run its relevant behavioral
checks. Exit codes and inspected log content adjudicate the h33 run; elapsed
time and future raw-log hash equality do not.

## Review-entry state after h35

`At review entry, behavioral evidence is attributed to candidate 81b9a40c and
the h36 candidate-specific plan-only comparison is historical evidence only.
No future candidate inherits it. The staged candidate remains gated on one
Claude closure review/challenge pair.`

Nothing has been merged, pushed, tagged, released, deployed, or cleaned up.

## Human-requested chain h36 — bound history without a permanent gate

The h36 review passed candidate `212d852a` with packet
`6de869764acf7e1c4617278617609856276e875c6bb07c3a81072172ab90cb7d`.
Its challenge returned one P1 and three P2 findings. They correctly distinguish
a candidate-specific evidence command from a permanent repository gate: the
plan must not promise a checked-in future gate, a loose synthetic commit should
not become a required long-lived ref, ignored files are outside the existing
non-ignored-untracked assertion, and future candidates cannot be described as
already plan-only.

The h36 facts remain candidate-specific and record the tested tree ID rather
than requiring the loose commit to remain reachable. At that run, Git listed
29 ignored files, all under `.pytest_cache/` or `__pycache__/`, and zero
non-ignored untracked paths. Those generated caches are explicitly outside the
clean-source assertion; the next packet enumerates them and confirms there is
no ignored `.env`, `sitecustomize.py`, `conftest.py`, or requirements copy.
Nothing here creates a permanent CI rule or lets a later candidate inherit the
h33 behavioral result.

The synthetic h33 commit and tree may become unreachable after branch/worktree
cleanup and Git garbage collection. Their hashes are historical run
identifiers, not a promise that a future checkout can resolve those objects.

## Review-entry state after h36

`At review entry, h33 behavioral results bind to their recorded tree; h36 Git
checks are historical candidate evidence, not a future gate. Ignored generated
caches are enumerated separately from the zero non-ignored-untracked claim.
The staged candidate remains gated on one Claude closure review/challenge
pair.`

Nothing has been merged, pushed, tagged, released, deployed, or cleaned up.

## Human-requested chain h37 — visible predicates and repository-root scope

The h37 review passed candidate `2f5eb5be` with packet
`415f0079ede192cb9d4bd114dd2b643e59836c469fb5988631f7985ecf1f387b`.
Its challenge returned two P1 and two P2 findings. The packet must show the
literal candidate-binding and ignored-path predicates, plus a negative
allowlist execution; exit labels alone are not reviewable. The object
durability finding is addressed above by explicitly allowing the historical
synthetic objects to become unreachable.

The remaining `.work` finding is rejected by first-hand path evidence. The Git
top level for the candidate is the feature worktree itself; the parent
integration checkout's `.work/` directory is outside that root. All h37 gate
artifacts are under `/private/tmp/ccl-025-h37-gates.2f5eb5b`, also outside the
candidate root. Therefore their absence from `git ls-files --others` is
expected and does not show pruning. The 29-path inventory covers files beneath
the candidate Git root, which is the stated scope.

## Review-entry state after h37

`At review entry, the packet must include literal command bodies and raw output
for candidate binding and ignored-path checks, including a deliberately denied
synthetic path. Historical object hashes may become unreachable. The ignored
inventory is scoped to the candidate Git root, with external evidence paths
reported separately. The staged candidate remains gated on one Claude closure
review/challenge pair.`

Nothing has been merged, pushed, tagged, released, deployed, or cleaned up.
