# 016 — Delete the template exemption; a backticked specs/ token is a citation

## Artifact classification

`gate implementation` (per
`product-rd-workflow/references/shared-gate-artifact-classification.md`). It
changes the failure semantics of a mandatory, fail-closed gate: tokens that
passed now fail. Risk tags (`feature-risk-router`): `shared-gate`.

`security-review`: change-triggered arm is `not-applicable` — the gate reads this
repo's own tracked files, adds no trust boundary, sink, or authority semantics,
and this change only removes an exemption. `visible surface: no`.

**Process note, recorded rather than smoothed over:** the first version of this
plan was written after the test-case-first RED and the fix, not before. The
shared-gate rule requires the persistent artifact first because the change alters
failure semantics. The ordering was wrong; nothing here is backdated to hide it.

## Defect this closes

`014` landed its gate with the review lane run and **the challenge lane never
run** — no chain in the local evidence store, and no packet in it touches
`check-spec-references`. Its plan still read `Landing state: plan drafted` while
the gate was live in `make test` and CI.

Running the missing challenge found a bypass, confirmed first-hand against the
landed checker: `PLACEHOLDER_RE` matched any angle bracket anywhere in the **raw**
token, **before** the fragment and locator were resolved, so one character
anywhere in a citation skipped resolution entirely.

| Tracked content | Landed gate | Correct |
| --- | --- | --- |
| a dead spec path plus a bracketed fragment | **passes** | fail |
| a dead spec path with a trailing unmatched bracket | **passes** | fail |
| a dead spec path with a bracketed line locator | **passes** | fail |
| a dead spec path with a bracketed note after the filename | **passes** | fail |
| the same dead path with no bracket (control) | fails | fail |

A mandatory gate with a one-character opt-out is not a gate.

## Design: the exemption is deleted, not re-grammared

The first two rounds tightened the exemption instead of questioning it, and each
tightening was followed by another way through. Five distinct evasions of one
exemption were found:

| # | Evasion | Round |
| --- | --- | --- |
| 1 | raw-token test, run before the fragment and locator were resolved | 0 |
| 2 | one valid placeholder segment licensing a malformed sibling | 1 |
| 3 | a zero-width character passing as a placeholder body | 1 |
| 4 | the marker suppressing the **containment** check, not just existence | 1 |
| 5 | `..` cancelling the placeholder so a contained dead path read as a shape | 2 |

Five instances of one class is this repo's recorded signal to ask whether the
capability should exist. **Decision: delete.**

The ambiguity was never about paths. **Backticks were overloaded** — marking both
"a real path you can open" and "a shape you cannot" — and no gate can separate
those from syntax alone. Every grammar that tried was an adjudication of an
ambiguity that did not need to exist. So the overload is gone instead: a
backticked token beginning `specs/` is a citation and must resolve, with no
exemption to evade.

**How a template is written now**, neither of which renders as one path:

- name the shape without the prefix and leave the prefix in prose — a
  `<NNN>-<slug>/plan.md` file under specs/;
- or put the whole path in a fenced block.

Keeping the backticks matters: an unbackticked angle bracket is swallowed as an
HTML tag when Markdown renders, so "just remove the backticks" would silently
delete the placeholder from the rendered page.

**A third form was tried, then abandoned twice over.** Splitting the prefix out
of the code span renders as one concrete path while starting the backtick after
the prefix, so a token-only pattern never sees it — the deleted exemption in new
syntax. The checker was extended to rejoin it; the next round then found three
more spellings that render as a path and evade a line pattern (a backticked
prefix with a plain suffix, a padded span CommonMark trims, and a false positive
on an unrelated `api-specs/` path). Completing that chase means writing an
inline-Markdown parser inside a repo gate, so the extension was **reverted** and
the scope declared instead — see the residual below.

Rejected alternatives:

- **Keep the tightened grammar.** It is now mutation-covered and may well be
  correct, but it remains the gate's entire attack surface, and the cost of being
  wrong is a mandatory gate silently reporting success.
- **Allowlist the two known template strings.** Predicates the gate on a
  vocabulary it owns — the exact anti-pattern this repo's ledger already carries.

## Corpus migration

Nine occurrences of two forms, all rewritten in this slice; the repository gate
is the mechanical proof that none was missed, because it scans every tracked file
and is green.

| Form | Occurrences | Now written |
| --- | --- | --- |
| a two-placeholder segment under specs/ | 7 | shape backticked, prefix in prose |
| a whole-segment placeholder under specs/ | 2 | shape backticked, prefix in prose |

Migrated twice: first to the split-prefix spelling, then off it again once the
challenge showed that spelling was itself an opt-out.

## Acceptance matrix

| # | Input | Before | Expected |
| --- | --- | --- | --- |
| 1 | a backticked template with the specs/ prefix inside | pass | **fail** — it is a citation like any other |
| 2 | the shape backticked with the prefix in prose | pass | pass — does not render as one path |
| 3 | the same template inside a fenced block | pass | pass — not a citation |
| 3a | a citation longer than the filesystem name limit | **crash** | fail — closed, without raising |
| 3b | a citation whose target is a symlink to a file outside the repo | pass | fail — containment is resolved-path based |
| 4 | dead base + bracketed fragment | **pass** | fail |
| 5 | dead base + trailing unmatched bracket | **pass** | fail |
| 6 | dead base + bracketed line locator | **pass** | fail |
| 7 | dead base + bracketed note after the filename | **pass** | fail |
| 8 | a bracket-bearing path that traverses outside the repo | **pass** | fail — containment |
| 9 | a bracket-bearing path whose `..` cancels the placeholder | **pass** | fail |
| 10 | abbreviation with an elided slug | fail | fail — unchanged |
| 11 | this repo at closeout | pass | pass |

## Test / register coverage

| Layer | Rows | Command | State |
| --- | --- | --- | --- |
| unit | 1-11 | `python3 scripts/test_check_spec_references.py` | 37 cases |
| repo gate | 11 | `python3 scripts/check-spec-references.py .` | run |
| wiring | the gate still runs | `make test` | run |

Test-case-first: the bypass cases landed and ran RED against the unmodified
checker (4 failures) before any fix.

**Behavioral evidence for the deletion.** Three cases that asserted a template is
IGNORED now assert it is reported — a deliberate policy change, recorded rather
than a weakened assertion — and two new cases pin the supported template forms as
not-citations. The deletion's own sensitivity is structural: with the exemption
removed there is no predicate left to mutate, and the tests that would fail if it
were reintroduced are exactly rows 1-3.

The intermediate grammar's mutation walk is retained as history rather than
evidence for the landed design, because that code no longer exists: reverting to
the raw-token check flipped all eight bracket cases, `any`-instead-of-`all`
flipped the sibling-composition and stray-bracket cases, a permissive placeholder
body flipped exactly the zero-width case, and evaluating the exemption before
containment flipped both traversal cases. One of those mutations first reported
"flips: NOTHING" because its anchor failed to apply rather than because the
property was uncovered — recorded because the two are indistinguishable from the
output unless the application is checked.

**The author-dogfood leg fired twice and both times it was the finding.** With the
tightened grammar, this checker's own comment failed the gate because it *cited*
the dead examples in backticks — and one of those mentions predated the change,
surviving on the exemption being removed. With the exemption deleted, the same
leg caught the corpus migration: every remaining template citation had to move
its prefix outside the backticks, and the gate is what proved none was missed.

## Review rounds

Reviewer `codex`, both lanes (`IMPLEMENTER_FAMILY=anthropic` excludes the Claude
lane).

| Round | Finding | Disposition |
| --- | --- | --- |
| 1 (review) | one valid template segment licensed a malformed sibling | **accepted**, then superseded: the grammar it fixed no longer exists |
| 1 (challenge) | a zero-width placeholder body satisfied the grammar | **accepted**, then superseded by the deletion |
| 1 (challenge) | the marker suppressed **containment**, not just existence | **accepted and retained** — containment is still checked, unconditionally, and is independent of any exemption |
| 1 (review) | no corpus inventory backed the compatibility claim | **accepted as the premise-check leg, and run** — it produced the enumeration that made the deletion's migration cost knowable |
| 2 (challenge) | `..` cancelled the placeholder so a contained dead path read as a shape | **accepted**, and it was the fifth instance — the trigger for deleting rather than patching |
| 2 (review) | repeat of the compatibility concern | **dispositioned with evidence**: the corpus-level contract is the repo gate itself, which runs over every tracked file in `make test` and is green |
| 3 (review + challenge) | the split-prefix migration form renders as one concrete path but starts the backtick after the prefix, so the pattern never sees it — a dead path, or one traversing out of the repo, passes | **accepted, and it was mine**: I deleted a grammar-based exemption and introduced a syntax-based one in the same landing. The corpus was migrated off that form and the documentation no longer offers it. Detecting it was implemented, then **reverted in round 4** — see below |
| 4 (review + challenge) | three more spellings render as a path and evade a line pattern: a backticked prefix with a plain suffix, a padded code span that CommonMark trims, and a false positive on an unrelated `api-specs/` path | **decision, not another patch.** Each round of chasing rendered-path spellings produced another spelling; finishing it means an inline-Markdown parser inside a repo gate. The trust-model leg decides it: this gate defends against an honest author citing a path that does not exist — the defect that motivated it — not an adversary crafting an evasion. The split detection is reverted, the scope is declared in the checker, and the residual is stated rather than half-built. The `api-specs/` false positive disappears with the revert |
| 3 (review + challenge) | the packet cannot confirm containment is resolved-path based rather than lexical, and no case creates an in-repo symlink to a file that really exists outside | **accepted as an evidence gap and closed with a test**, not with prose: a citation targeting a symlink that points outside the repo is now asserted to be reported. It passes, which refutes the lexical-containment hypothesis with evidence rather than assertion |
| 3 (dogfood, self-caught) | the new split pattern matched from INSIDE the ordinary token `specs/`, capturing hundreds of characters to the next backtick — and that target then raised `ENAMETOOLONG` from `exists()`, crashing the gate mid-run | **both fixed, and this is the false-positive sweep the rules require after widening a validator**: the pattern gained a lookbehind and excludes whitespace, `exists()` fails closed on `OSError`, and the pattern is assembled from fragments because spelled out it matched its own source. Regression cases pin all three |
| 5 (review) | **no findings** — the review lane passed on the declared-scope candidate |
| 5 (challenge) | a multi-backtick code span is a canonical citation the single-backtick pattern would miss | **refuted on the merits, measured.** A path contains no backtick, so in a multi-backtick span the innermost pair always matches: the existing pattern already reports double- and triple-backtick citations. A run-matching version was implemented, then reverted when its own mutation flipped nothing — the honest reading of a mutation that changes no verdict. Two double-backtick cases are kept as pins |
| 5 (challenge) | a symlink loop could raise from the containment check, outside the new `OSError` handler | **guard added, and its status recorded honestly as `unverified`.** `escapes_root` now also catches `RuntimeError`, but on this runtime a loop does not reach that branch — resolution returns and the existence check reports the finding — so the mutation removing it flips nothing. The loop case itself IS covered by a test; the extra except is defence-in-depth for older interpreters, not a property this suite proves |
| 2 (challenge) | the register's firing path is a bold list item, not a heading, so a Markdown anchor cannot reach it | **refuted from the gate's source.** That locator is consumed by `impact-chain-gate.rb`, whose `enforcing_file_locator_valid` requires the anchor to sit on a changed **list-rule line carrying normative vocabulary** and rejects headings. The suggested fix would make the gate fail |

## Status-sync target

This plan; `014`'s plan (its challenge lane recorded, its `Landing state`
corrected, and its row 12 exemption marked superseded here); and the extraction
rule in `skill-extraction-workflow/references/dual-track-review-gate.md`.

## Declared scope, and the residual it accepts

The unit is the canonical backticked token, not everything a renderer might
display as a path. Spellings that RENDER as one path without being one token —
the prefix split across a code span, a padded span CommonMark trims — are **not**
detected. Three rounds of chasing them each produced another spelling, and the
trust-model leg says stop: this gate exists because an honest author cited a path
that never existed, not because an author is trying to evade it. The corpus uses
none of those spellings, an unbackticked prose mention was already out of scope
(014 row 7), and this residual is its neighbour.

## Not in scope, and why

The same lanes re-reported that a tracked filename containing an invalid UTF-8
byte crashes the checker at `item.decode("utf-8")`. `014` already recorded that
as an accepted residual and routed it to a dedicated round over all three
repo-root checkers, which share the identical exposure. It stays there.

One sharpening belongs to that round: `014`'s row 22 uses a **valid** UTF-8 name,
so it cannot detect the invalid-byte case it appears to cover.

## Review / challenge gate

`shared-gate` requires both lanes before shared-branch push or MR merge:
`review_gate.sh --mode review` and `--mode challenge`, `--stage release`,
`--risk-tag shared-gate`, `IMPLEMENTER_FAMILY=anthropic`. The challenge focus is
whether deleting the exemption strands any legitimate way of writing a path shape,
and whether the migrated corpus forms are genuinely outside the citation pattern.

## Landing state

`local status`. Branch `worktree-spec-ref-placeholder-bypass`, cut from `main`,
unpushed.
