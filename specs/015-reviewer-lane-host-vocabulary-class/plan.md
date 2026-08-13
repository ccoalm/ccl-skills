# 015 — Host vocabulary is unverifiable, not a proven breach

## Artifact classification

`gate design` + `gate implementation` (per
`product-rd-workflow/references/shared-gate-artifact-classification.md`). This
changes the failure semantics of the reviewer-lane isolation classifier, which
decides whether an independent review can be produced at all — and this repo
requires a recorded independent review before any shared-gate change lands. The
plan exists before the edit.

Risk tags (`feature-risk-router`): `shared-gate`, `security-review`.

`security-review`: **triggered**, not `not-applicable`. The change alters how a
failure of a *trust-boundary verifier* is routed, so `security posture
unchanged` is not honestly claimable even though no isolation approval is
widened. The four design-time questions are answered below.

`visible surface: no` — no rendered surface; the artifact is a classifier and a
routing table.

## Defect this closes

The prior round (`b58a8ad`) registered `import` in
`KNOWN_SAFE_BUILTIN_SLASH_COMMANDS` and recorded itself as a **stopgap**, in the
code comment and in the `code-review` register row: the allowlist is a snapshot
of host built-ins, so the next CLI release breaks the lane again.

The defect is not the missing name. It is the **class**: an identifier the
allowlist does not recognise is treated as a *proven* user customization, and
that class is terminal and non-cascadable. So one upstream CLI release removes
the entire review capability — `fallback_eligible: False`,
`next_action: stop_reviewer_lane`, one attempt, no client selected, kimi and
opencode never tried — including for the change that would fix it.

**A predicate that cannot tell host vocabulary from user customization must not
report the unclassifiable case as the proven one.**

## Measured, not assumed

Both live invocation shapes were captured from the real CLI at
`claude_code_version 2.1.220`, using the exact flag set `claude_review.sh`
builds:

| Shape | `slash_commands` | `skills` | Exposure |
| --- | --- | --- | --- |
| `--plugin-dir` (review-skill mode) | 46 entries, **all host built-ins** | 16 entries, **all host built-ins** | every entry is host vocabulary, so drift in either field is an outage |
| `--disable-slash-commands` | 0 | 0 | the strict "any entry is a breach" branch cannot fire spuriously |

Two consequences the measurement decides rather than argues:

- **The defect is not `slash_commands`-specific.** `skills` is populated by the
  same host-vocabulary snapshot on the same path, and
  `KNOWN_SAFE_BUILTIN_SKILLS` is in sync today only by luck. Fixing one field
  and leaving the other would leave the identical defect live, so scope is both.
- **`plugins` is out of scope and stays strictly terminal.** Plugins are
  user-installed by definition, not host vocabulary; the expected set is exactly
  `ccl-skills`, which the repo owns.

Corroborating evidence that the target class already works as intended: this
same live init carries `fast_mode_disabled_reason`, an unknown field absent from
`KNOWN_SAFE_INIT_METADATA_FIELDS`, which arrives as a scalar and is correctly
tolerated by the existing drift policy.

## Design

**Rule**: in `slash_commands` and `skills`, a disallowed entry whose identifier
is **bare** is `unclassifiable host vocabulary` — reported, refused, and
**fallback-eligible**. Everything else in those fields stays a terminal breach.

"Bare" means the identifier carries no namespace and no path: it matches
`[a-z0-9][a-z0-9_.-]*` after `customization_entry_identifier` normalization.
Therefore these all stay **terminal**:

- **namespaced** (`evil-plugin:pwn`) — a namespace proves a plugin surface
  beyond the one expected surface, which is a customization, not host vocabulary.
- **path-shaped** (`dir/cmd`) — no host built-in is spelled this way.
- **`<unidentified>`** — the sentinel for an entry that fails the charset or is
  not a string/dict. An unparseable entry is not evidence of host vocabulary.
- **duplicate identifiers** in one field — a spoofing signal, not drift.
- anything in `plugins`, and anything on the no-expected-skills path where the
  measurement above shows the surfaces are empty.

**The refusal is not weakened; only the next action is.** In both the old and
the new behavior the Claude lane *fails* on an unrecognised entry — it never
returns findings and never claims isolation was verified. What changes is
`stop_reviewer_lane` → `fallback`: the review routes to another client instead
of the capability being destroyed. This is the same treatment the file already
gives `unverifiable_authority` ("we cannot show the reviewer was elevated, only
that we can no longer show it was not"), and the class it lands in is the
existing one rather than a new mechanism.

**Both parse paths and the routing table move together.** The reason text is
load-bearing: `claude_review.sh`'s `emit_runtime_inconclusive` routes on
substrings, its terminal arm matches `runtime isolation` / `runtime capability`,
and its drift arm matches the literal `unrecognized surface-shaped init field`.
The new class gets its own literal phrase, `unclassifiable host-vocabulary
entry`, and its own arm placed **before** the terminal arm. Reusing the
surface-shaped phrase was rejected: an unrecognised *identifier* is not an
unrecognised *field*, and this repo has already paid for a diagnostic that
described something other than what fired. Relying on the late
`*"init"*` catch-all arm was also rejected — that is precisely the "routing
depends on `case`-arm order alone" failure the existing comment warns against.

Rejected alternatives:

- **Keep registering names.** This is the vocabulary-predicate anti-pattern the
  ledger already carries twice; it needs one entry per future CLI release and
  the escape stays cheaper than the fix.
- **Tolerate unclassifiable bare entries** (let the lane proceed). This would
  genuinely weaken isolation: a user-authored bare command is a real
  customization that can carry instructions to the reviewer. Refusal is kept;
  only cascade is granted.
- **Remove `import` from the allowlist now that the class cascades.** Rejected:
  the entry is factually correct host vocabulary, and keeping it means the
  Claude lane keeps *working* rather than degrading to fallback. The allowlist
  survives as a preference optimization, not as the capability's load-bearing
  predicate — which is the whole point of the change. The stopgap comment is
  rewritten to say so.

## Design-time operability check

The change modifies existing machinery rather than adding new enforcement, but
the three legs are recorded because it alters gate semantics.

| Leg | Result |
| --- | --- |
| author dogfood | the real CLI was invoked in both live shapes before the design was written, and the RED table below was reproduced first-hand against the unmodified parser. After the change the lane must be re-run end to end against the real CLI, not only against fixtures |
| marginal cost | **negative for the defect, measurably positive for the suite.** The routine change gets cheaper: a CLI release costs a reviewer-client switch instead of the whole review capability, and no artifact needs regenerating. But the mutation walk this slice automates is not free — measured on this machine, the oracle alone runs 5s and the control-plus-eight-mutant walk runs 50s, so `make test` grows by roughly 45s. Recorded rather than waved past: it is proportionate against sibling checks in the same suite that take 139s and 52s, and it replaces a hand-maintained number that silently went stale, but the cost is real and grows linearly with each mutation added |
| trust-model fit | defends the *availability* of the reviewer capability against upstream vocabulary drift, under a trust model where the inspected CLI is untrusted. It does **not** defend against a hostile CLI choosing its own reported vocabulary — stated so the class is not read as broader than it is, and bounded in Q2 below |

## Security four questions

1. **Caller-controlled inputs**: the entire stream-json init event from the
   inspected CLI — field names, values, and every customization identifier.
2. **Blast radius if forged**: a hostile or compromised CLI can emit a bare
   unrecognised identifier to obtain `fallback` instead of `stop_reviewer_lane`,
   i.e. it can **steer which reviewer client is used**. It cannot obtain a
   passed review, cannot have isolation reported as verified, and cannot make
   the Claude lane return findings — the lane still fails closed. The same
   steering is already reachable today via `unknown_fields` and
   `unverifiable_authority`, so the change widens the *inputs* to an existing
   exposure, not the exposure itself. Recorded and accepted, with the bound
   stated: no path reaches TOLERATED that did not before.
3. **Trust root**: isolation approval continues to derive only from the exact
   `tools` allowlist, the `tool_use` scan, and the value-pinned
   `permissionMode`. None of the three is touched, and no identifier from the
   customization lists can grant anything.
4. **Negative cases in the acceptance matrix**: forged namespaced entry stays
   terminal (row D); breach plus bare-unknown stays terminal (rows E, F);
   `<unidentified>` stays terminal (row G); a forged identifier cannot spell a
   routing phrase (rows N) — `safe_identifier` already restricts the charset and
   the oracle's steering rows are extended to the new arm.

## Acceptance matrix

Verdict classes are the wrapper's: `TOLERATED` (run accepted), `FALLBACK`
(refused, review routes to another client), `TERMINAL` (refused, lane stops).
Rows A–F are executed first-hand against the unmodified parser; the RED column
is measured, not predicted.

| # | Input (review-skill mode unless stated) | Now | Expected |
| --- | --- | --- | --- |
| A | host built-ins only | TOLERATED | TOLERATED — unchanged |
| B | a new **bare** built-in command | **TERMINAL** | **FALLBACK** |
| C | a new **bare** built-in skill | **TERMINAL** | **FALLBACK** |
| D | a **namespaced** foreign command (`evil-plugin:pwn`) | TERMINAL | TERMINAL — unchanged |
| E | bare unknown **plus** a declared tool breach | TERMINAL | TERMINAL — breach beats unverifiable |
| F | bare unknown **plus** `permissionMode: bypassPermissions` | TERMINAL | TERMINAL — proven unsafe beats unverifiable |
| G | an entry that normalizes to `<unidentified>` | TERMINAL | TERMINAL — unparseable is not host vocabulary |
| H | a **path-shaped** identifier (`dir/cmd`) | TERMINAL | TERMINAL |
| I | duplicate identifiers in one field | TERMINAL | TERMINAL |
| J | a bare unknown entry in `plugins` | TERMINAL | TERMINAL — plugins are not host vocabulary |
| K | any entry on the **no-expected-skills** path | TERMINAL | TERMINAL — measured empty in that shape |
| L | bare unknown **plus** an unknown non-empty container | — | FALLBACK — both are unverifiable, neither is a breach |
| M | a later init event adding a bare unknown entry | — | FALLBACK — evaluated per event, not on the union |
| N | every routing phrase used as a bare identifier | — | must not reach a softer arm than its own class |
| O | this repo's live init at closeout | TOLERATED | TOLERATED — no regression on the real CLI |
| P | a **structured** (dict) entry whose reported `name` is bare | — | TERMINAL — a sibling key may carry proof the soft class would ignore |
| Q | a structured entry whose `name` is an **allowed built-in**, carrying a path-shaped sibling key | **ACCEPTED** (reproduced) | TERMINAL — the shape gate runs before the allowlist |
| R | `plugins` carrying its normal dict entry | TOLERATED | TOLERATED — the gate must not spread to the field that legitimately uses dicts |

## Test / register coverage

| Layer | Rows | Command | State |
| --- | --- | --- | --- |
| policy oracle (every invocation shape × both parse paths, through the wrapper's routing table) | A–N | `bash skills/code-review/scripts/test_init_policy_matrix.sh` | add |
| parser unit | B, C, D, G, H, I | `bash skills/code-review/scripts/test_parse_probe_result.sh` | add |
| wrapper routing arm | B, C | `bash skills/code-review/scripts/test_claude_review_probe.sh` | add |
| repo gate | full suite | `make test` | run |
| live CLI | O | real `claude_review.sh` run against the real CLI | run |
| E2E / live infra | — | — | not applicable: no network service, no external host beyond the local CLI |

Test-case-first: the oracle rows for B and C land and run RED before the parser
changes.

### The oracle was blind to the branch that broke

`init_policy_matrix.py` crosses 82 cases over both parse paths, and every one of
them runs with `--expected-tools ""` and **no** `--expected-native-skills`. That
is the `--disable-slash-commands` shape. The outage happened in the
`expected_native_skills` branch — review-skill mode — which the oracle never
exercised. This is why 164 green cases did not catch `/import`, and it is a
finding about the oracle rather than about the parser.

So this slice adds a **third path** to `PATHS`, carrying the native-skill flags
the wrapper really passes, and the existing cases are crossed over it too. The
fixture must use a selected skill whose name is *not* also a built-in skill
name, or the ambiguous-selected-owner guard fires on every row and masks the
verdict under test — observed while building the RED table above.

### Riding along: the oracle's sensitivity claim becomes executable

`test_init_policy_matrix.sh` states in its own header that the mutation walk
proving the oracle can fail "is not automated here … re-run it by hand when the
policy changes". **This slice changes the policy, so that note fires now.** Its
recorded scores (`54 / 16 / 8 / 2 / 1`) are prose in a module docstring, and
adding rows invalidates them — leaving the choice between updating numbers that
drift again or making the claim executable.

The check is made executable: the suite applies a small set of named weakenings
to a disposable copy of the parser, asserts the oracle reports mismatches for
each, restores, and byte-compares against pristine. A self-audit oracle whose
own sensitivity is unproven is one refactor away from being vacuous, and the
new class needs its own mutant — dropping the bare-identifier restriction must
flip a row, or nothing distinguishes this change from tolerating everything.

## Status-sync target

This plan, the stopgap comment in
`skills/code-review/scripts/parse_probe_result.py`, and the `code-review`
register row from the prior round, whose "tracked as its own slice" resolution
this slice discharges.

## Implementer self-review

Persisted before the independent review, in this artifact rather than in the
landing commit, because the dual-track gate requires the review to precede the
landing commit.

**Load-bearing invariants**, each with the mutation that makes it RED (all
applied, not imagined — the walk is in `test_init_policy_matrix.sh`):

| # | Invariant | Killing mutation | Observed |
| --- | --- | --- | --- |
| I1 | no input that used to be refused becomes ACCEPTED | remove the new set from `stream_probe_passed`'s refusal condition | this was a real defect while implementing: the first version left the set out of that gate, and the parser crashed on the 6-tuple unpack before it could accept anything. Fixed, and the set now refuses there |
| I2 | breach beats unverifiable — a run that is both reports the breach | drop `and not surface_breached` (probe path); drop `or vocabulary` from the main predicate | `drop-host-vocabulary-breach-guard` → 11 mismatches; `drop-host-vocabulary-from-main-path` → 13 |
| I3 | the soft class is reachable only from a BARE identifier in a host-vocabulary field | `is_bare_host_identifier` → `return True` | `widen-host-vocabulary-to-any-entry` → 14 mismatches |
| I4 | the class is actually reachable, i.e. the fix is load-bearing | `is_bare_host_identifier` → `return False` | `terminalize-host-vocabulary` → 28 mismatches |
| I5 | no CLI-supplied text selects a softer routing arm | drop the field-name sanitizer | `drop-field-name-sanitizer` → 6 mismatches; plus 16 `steer-vocab-*` rows crossing every routing phrase through both parse paths |
| I6 | both parse paths reach the same class for the same input | — | the new `skill-probe` path exists to check this; 252/252 agree |
| I9 | **nothing is discarded to reach a verdict** — no dict key, no truncated suffix, and no surrounding whitespace: the entry's value, case-folded with at most one leading `/` removed, must reproduce the identifier the decision uses | replace the comparison with `return True`; or re-introduce `.strip()` | `drop-whole-value-gate` → 40; `weaken-whole-value-gate-to-shape-only` → 32; `strip-before-the-whole-value-comparison` → 10. One predicate subsuming what had been three separate guards, each of which had let the same class through |
| I7 | a structured entry in a host-vocabulary field is never cleared, **including when its `name` is an allowed built-in** — so unread evidence in a sibling key can neither launder a customization into the soft class nor reach acceptance | drop the shape gate | `drop-structured-entry-shape-gate` → 8 mismatches; the two smuggled rows report `got tolerated`, i.e. the acceptance class. Added for review round 1 and then moved ahead of the allowlist for round 5, which is where the same class resurfaced |
| I8 | the wrapper's real routing table agrees with the mirrored one the oracle reads | delete the routing arm from `claude_review.sh` | the probe suite goes RED: the wrapper falls to its default arm, `reason_code: unknown` / `stop_reviewer_lane` |

**Enumeration set-diff** (axis 6 — the change defines a set, so the check is a
set-diff against the authoritative source, not a taste call).
`HOST_VOCABULARY_FIELDS` is diffed against `REQUIRED_EMPTY_INIT_FIELDS`:

| Field | In host-vocabulary set? | Why |
| --- | --- | --- |
| `slash_commands` | yes | populated entirely by host built-ins (measured above) |
| `skills` | yes | same, and stale by luck rather than by design |
| `plugins` | **no** | user-installed by definition; the expected set is the one this repo owns |
| `mcp_servers` | **no** | pinned empty by `--strict-mcp-config --mcp-config '{}'`, and not in the customization map at all |

**Changed files vs the active artifact** — five files, all in scope for this
plan: `parse_probe_result.py` (the class), `claude_review.sh` (its routing arm),
`init_policy_matrix.py` (policy G + the two review-skill paths),
`test_parse_probe_result.sh` (unit rows), `test_init_policy_matrix.sh` (the
mutation walk). No file outside `skills/code-review/scripts/` plus this spec.

**Named regression evidence**: `init_policy_matrix.py` rows
`host-vocab-new-command` / `host-vocab-new-skill` fail against the unmodified
parser (measured: 14 mismatches over the new rows) and pass after (250 cases /
0 mismatches). This RED is pre-change, not mutation-induced.

**A pre-existing assertion changed verdict, and was repointed rather than
relaxed.** `test_parse_probe_result.sh`'s owner-aware fixture used a bare
`unrelated-skill` to prove the main path reports a breach rather than the soft
drift reason. Under policy G that identifier is no longer a proven
customization, so the fixture was repointed to a namespaced
`other-plugin:unrelated-skill` — which still is one — and the bare variant added
as its own row asserting the opposite verdict. The assertion was not weakened;
its input was corrected, and both directions are now pinned.

**Deterministic gates run, and what each proves**: `check-ccl-skills.sh`,
`check-agent-contract-coverage.sh --enforce`, `check-public-sanitization.py`,
`check-markdown-links.py`, `check-spec-references.py` (repo contract and
citation integrity — run green on this branch before implementation);
`test_parse_probe_result.sh` (per-input classification); the policy oracle
(cross-path class agreement); the mutation walk (that the oracle can fail);
`make test` (no regression elsewhere). Live CLI: the real captured init is still
accepted, a synthetic new built-in cascades, a namespaced foreign entry stays
terminal.

**Known residual risks**, recorded rather than resolved:

- A hostile CLI can steer *which reviewer client* serves the review by emitting
  a bare unrecognised name. It cannot reach ACCEPTED, and the same steering is
  already reachable through `unknown_fields` / `unverifiable_authority`; the
  change widens the inputs to that existing exposure, not the exposure.
- A user-authored bare command is indistinguishable from a host built-in and so
  gets the soft class. It is still refused; only cascade is granted.
- The main path emits the broader drift phrase when the new class co-occurs with
  schema drift or an unverifiable authority knob. Pre-existing imprecision on
  that path, deliberately not widened here.

## Review / challenge gate

`shared-gate` requires both lanes before shared-branch push or MR merge:
`review_gate.sh --mode review` and `--mode challenge`, `--stage release`,
`--risk-tag shared-gate`, `IMPLEMENTER_FAMILY=anthropic` (which excludes the
Claude lane, so the reviewer is non-same-family by construction).

The challenge focus is the security boundary: whether "refusal preserved, only
cascade granted" survives adversarial reading, and whether bare-vs-namespaced is
a real discriminator or a predicate fitted to the one name that broke.

Verifier discovery (run green on this branch before implementation):
`check-agent-contract-coverage.sh --enforce`, `check-ccl-skills.sh`,
`check-public-sanitization.py`, `check-markdown-links.py`,
`check-spec-references.py`, then `make test`.

## Executed evidence

Both lanes objected that the packet asserted green suites without carrying their
output, so the results are recorded here rather than claimed. Every command was
run from the worktree by absolute path — a relative invocation can silently
evaluate the primary checkout, which is clean and would pass while proving
nothing — and the suite log's first line records the tree it ran in.

| Command | Observed | Status |
| --- | --- | --- |
| `make test` | `MAKE_TEST_RC=0`, log line 1 = the worktree path | pass |
| `test_init_policy_matrix.sh` | `cases: 278  mismatches: 0`; guard self-check rejects a broken mutant *for the right reason*; then 11 mutants each detected — `tolerate-all-unknown-containers` 18, `drop-authority-name-guard` 10, `drop-authority-presence-requirement` 6, `drop-field-name-sanitizer` 6, `widen-host-vocabulary-to-any-entry` 12, `terminalize-host-vocabulary` 12, `drop-whole-value-gate` 40, `weaken-whole-value-gate-to-shape-only` 32, `strip-before-the-whole-value-comparison` 10, `drop-host-vocabulary-breach-guard` 4, `drop-host-vocabulary-from-main-path` 5 | pass |
| whitespace probes against the real parser | `"import "`, `" import"`, `"\timport"`, `"verify "` → TERMINAL; `"brand-new"` → cascade; baseline and `ccl-skills:<selected>` → ACCEPTED | pass |
| `test_parse_probe_result.sh` | `parse_probe_result_tests_ok` | pass |
| `test_claude_review_probe.sh` | `claude_review_runtime_tests_ok`, including the two new end-to-end wrapper routing cases | pass |
| routing arm deleted (disposable mutation, wrapper restored byte-identically) | the wrapper falls to its default arm — `reason_code: unknown`, `next_action: stop_reviewer_lane` — and the new assertion goes RED | sensitivity proven |
| shape gate removed (disposable mutation) | 8 mismatches, and the two smuggled rows report `got tolerated` — the acceptance class, not merely a softer refusal | sensitivity proven |
| the five verifiers named below | each exit 0 | pass |
| real CLI init, as captured at 2.1.220 | still ACCEPTED — no regression | pass |
| same init + one new host built-in command | FALLBACK / cascade | pass |
| same init + one new host built-in skill | FALLBACK / cascade | pass |
| same init + a namespaced foreign command | TERMINAL / stop_reviewer_lane | pass |

**One fixture was contaminated, and differential attribution is what caught it.**
The first version of the two smuggled-entry rows reused a name already present in
the base list (`init`), so the duplicate-identifier check made them terminal for
an unrelated reason — removing the shape gate flipped *nothing* on those rows.
That is a finding about the test, not a clean result. The rows now smuggle under
an allowed built-in absent from the base list, and the mutation flips all eight.

Two honest bounds on the above. **The digest cannot bind to itself**: this table
is part of the candidate, so it names the results it was written from rather than
a digest computed after writing it — the reviewed candidate and the landed tree
differ only by this section's own text, and the commands are re-runnable from the
landing commit. **The counts are recorded once**, here, and deliberately not
copied into the register row: a count kept in two places drifts from the
candidate as soon as a case is added, which a prior round in this repo already
caught between two versions of a row.

## Review rounds

Reviewer `codex` (non-same-family; `IMPLEMENTER_FAMILY=anthropic` excludes the
Claude lane). Chain `host-vocab-r2` — the first chain attempt was abandoned
because the gate correctly rejected it: a tracked chain binds `--focus` and
`--challenge-budget` into its scope digest, and the review and challenge lanes
had been invoked with different ones, which reads as a mid-chain scope change.

| Round | Finding | Disposition |
| --- | --- | --- |
| 2 (review, fresh full scope) | the mutation walk accepted ANY nonzero exit as sensitivity, so a mutant that crashed instead of being detected would bank as proof | **accepted — and this is the rule I had read and still broke.** The dual-track reference states it outright: a mutant that breaks syntax or fixture setup also exits nonzero, so the exit code alone is not attribution. The walk now requires positive evidence: the same case count as the control, a parsed positive mismatch total, no `got unparseable` verdict, and at least one MISMATCH naming a real verdict class. **The guard then got its own self-check**, because a guard whose failure path is untested is the same defect one level up: the walk applies a deliberately broken mutant and asserts it is REJECTED, and that check runs before any mutant result is trusted. Widening the check also false-positived immediately — a bare `unparseable` substring test rejected a good mutant because a legitimate fixture is *named* `unparseable-identifier` — so the needle is anchored to the verdict token |
| 10 (review + challenge, fresh full scope) | **no findings in either lane** — the first clean round, on candidate `a113db4f6533` | Converged. The two preceding rounds' remediations (the table-terminating blank line, and the surviving `head -1` in the walk's success path) carried no new findings, so the gate is discharged for this candidate. Reviewer `codex` in both lanes |
| 9 (review + challenge) | the blank line before the newest register row terminated the Markdown table again, and `printf \| head -1` in the walk's SUCCESS path could still take SIGPIPE under `pipefail` | **both accepted, both mine, both reintroductions of defects this same slice had already fixed once** — the table break by inserting a row after the earlier fix, the pipeline by fixing every early-exit consumer except the success line. Fixed with the structural forms already chosen for their siblings: the row is contiguous, and the first line comes from parameter expansion |
| 9 (review **and** challenge, independently) | `host_entry_is_whole` called `.strip()`, so surrounding whitespace was erased before the comparison: `"import "` compared equal to the identifier, was declared whole, and the **allowlist then ACCEPTED it with isolation reported verified** | **accepted — the fourth instance of the class, this time reproduced inside the fix meant to end it.** The whole-value premise was right; my implementation inherited the very lossy call it was written to reject. `.strip()` is gone, so surrounding whitespace now disqualifies an entry, and both directions were verified first-hand: `"import "`, `" import"`, `"\timport"` and `"verify "` all terminal, a clean unknown name still cascades, the baseline and legitimate namespaced entries still accepted. Pre-existing as an allowlist bypass, so the round closed a hole that predated the slice as well. A mutant now re-introduces the strip and must flip |
| 6 (challenge) | a plain string such as `"brand-new evil-plugin:pwn"` truncates to `brand-new`, so the discarded suffix — the very proof of a customization — was never read, and the entry reached the soft class | **accepted, reproduced, and this is where the class was finally fixed at its premise.** Third instance of one shape: a dict's sibling key, a dict under an allowed name, and now a whitespace-hidden suffix. Patching a third instance was the wrong move; the shared premise was that the classification consumed the identifier helper's output, which is deliberately lossy (first token, or a dict's `name`) because it exists for DIAGNOSTICS. The decision now requires the entry's whole normalized value to reproduce that identifier exactly, so any remainder or other shape disqualifies it — one predicate covering all three instances, checked before the allowlist because the allowlist reads the same lossy token. Legitimate namespaced entries are unaffected: their whole value *is* their identifier, pinned by a row so the gate cannot be tightened into rejecting the surface review-skill mode depends on |
| 6 (review) | the register row recorded a case count that later rows made stale, contradicting the plan | **accepted, fixed by removing the duplicate rather than re-syncing it** — which is this repo's own recorded lesson about counts kept in two places, now demonstrated on the very row that restated it |
| 5 (review) | `customization_entry_allowed` runs BEFORE the plain-string check, so a structured entry whose `name` is an ALLOWED built-in cleared the allowlist outright, its other keys were never inspected, and the run reached **ACCEPTED with isolation reported verified** | **accepted, and reproduced first-hand before fixing** — with the caveat that the reviewer's own example did not reproduce: it used `help`, which is not in this repo's allowlist, so `customization_entry_allowed` returned False and the entry was already refused. Substituting a genuinely allowed name (`init`) reproduced it exactly: `{"name":"init","command":"/x/y","extra":["Bash"]}` was ACCEPTED. **This is the round-1 class returning in the other branch**, so per the same-class rule the fix is not a second patch: one shape gate now runs BEFORE the allowlist for host-vocabulary fields, covering the allowed and disallowed branches together. Pre-existing rather than introduced here, but adjacent to this diff, more severe than round 1 (it reaches acceptance), and required by this slice's own stated policy. `plugins` legitimately carries dicts and is pinned as such so the gate cannot spread to it |
| 5 (review + challenge) | under `pipefail`, `printf … \| grep -q` can fail from SIGPIPE when the consumer exits early, so the walk's guard could report the wrong rejection reason nondeterministically | **accepted, fixed structurally rather than per-pipeline**: the parsing and matching now use bash's own regex and substring tests, with no producer/consumer pipe at all. The same hazard applied to an assignment under `set -e`, which would have aborted the script outright |
| 5 (challenge) | the oracle mirrors the wrapper's routing table by reading its source; no test invoked the real wrapper, so a divergence between bash pattern matching and the mirror could launder a breach while the oracle stayed green | **accepted, closed with an end-to-end test** through the real wrapper: an unrecognised bare built-in must cascade (`capability_missing` / `fallback`), and the same init carrying a namespaced breach must stay terminal (`tool_boundary_violation` / `stop_reviewer_lane`) with the new phrase absent. **Proven able to fail**: deleting the routing arm makes the wrapper fall to its default arm (`reason_code: unknown`, `stop_reviewer_lane`) and the assertion goes red — which also settles a design question, since the reason does **not** match the late `*"init"*` catch-all, so relying on that instead of an explicit arm would have been terminal, not fallback |
| 2 (review) | the packet carries test definitions and prose but no command output, so release-stage acceptance cannot be independently established from it | **accepted as an evidence-recording gap, not a code defect.** The runs existed but lived outside the packet, so the Executed-evidence section above now carries them. Not fixed by widening the packet: the reviewer is packet-only by design, and shipping raw suite logs into it would trade that bound for volume |
| 3 (review **and** challenge, independently) | the plan *claimed* an executed-evidence section that did not exist in the packet, so a failing suite was indistinguishable from the asserted green state | **accepted — this was a live overclaim in my own document**, not a packaging nit: round 2's disposition said the section "now records" the results while no such section had been written. Both lanes caught the same thing on the same candidate. The section exists as of this round, with the two bounds it cannot escape stated in it |
| 3 (review) | the outer guard self-check treated ANY nonzero return as proof the broken mutant was rejected, so a moved anchor or a failed copy would print success without the guard ever being exercised | **accepted — the same defect the round-2 fix addressed, reproduced one level up in the fix itself.** The self-check now requires the specific rejection reason in stderr, and the distinction was verified by construction: breaking the self-check's own anchor makes the script exit 1 reporting `failed for the WRONG reason`, instead of claiming the guard works |
| 3 (review) | a stale blank line before the two added register rows terminated the Markdown table, so the new rows rendered outside it | **accepted, fixed.** The blank line predated the insertion point; the rows are now contiguous with the table they belong to |
| 1 (review) | a structured entry such as `{"name":"brand-new-builtin","command":"/x/y"}` is classified on its bare `name`, so a sibling key carrying path-shaped proof of a real customization is ignored and the entry reaches the softer class | **accepted, and it sharpened the policy rather than only patching it.** The plan had recorded this as an accepted residual on the grounds that no path reaches acceptance. That defence was too weak: this class is for entries whose customization status *cannot be shown*, and here it was shown and merely unread. The soft class is now restricted to plain string entries. Cost measured before accepting the fix rather than assumed — the real CLI emits both host-vocabulary fields as plain strings and uses dicts only for `plugins`, which was already excluded, so the restriction costs nothing operationally. Row P and a dedicated mutant were added; the residual-risk bullet is retired rather than reworded |

## The ledger gate caught a process violation, not a code defect

Worth recording because it was self-inflicted and mechanically caught. Across
rounds I kept **editing** the register row I had already appended, to fold each
round's disposition into it. The ledger is append-only by contract — "never
edit/delete a row", supersede by pointer — and `impact-chain-gate.rb` enforces
that structurally: a row counts for a round only if its exact text is NEW at HEAD
relative to base, with a per-text budget so a re-added row cannot be reused. My
edits changed the text of a row two later rounds were relying on, so those rounds
ended up with no surviving row and the gate failed closed with `changed:
code-review/SKILL.md / missing evidence path`.

Diagnosing it took four wrong guesses — staging, base ref, cell parsing, round
partition — each of which the evidence refuted before the gate's own source
settled it. The fix was to comply rather than work around: the branch is
unpushed, so the owner-code commits were consolidated into one round that carries
all four appended rows, leaving the three documentation commits intact so the
self-review row still provably predates the reviews.

## Landing state

`local status` — implemented, suites green, and the dual-track gate **discharged**:
review and challenge both returned no findings on candidate `a113db4f6533`, after
nine rounds that did. Branch
`worktree-claude-lane-bare-vocabulary`, cut from `main`, unpushed. Not merged and
not authorized for merge: a shared-branch push or MR is a separate step, and
merging requires the user's explicit instruction for that MR.

Sibling item deliberately **not** folded in: the prior round also routed a
generalizable half — an out-of-scope item named in a spec needs an owner or it
rots — to `product-rd-workflow` plan authoring, pending its own dual-track round.
That is a different owner with a different reviewer focus, so mixing it into a
reviewer-isolation security change would blur both packets. It stays open and
named rather than silently absorbed here.
