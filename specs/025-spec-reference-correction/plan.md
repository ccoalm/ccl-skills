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
