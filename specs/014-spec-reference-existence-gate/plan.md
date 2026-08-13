# 014 — A deterministic gate for `specs/` references

## Artifact classification

`gate design` + `gate implementation` (per
`product-rd-workflow/references/shared-gate-artifact-classification.md`). This
adds a new deterministic gate to `make test` and CI, so it defines failure
semantics that decide whether future work may land — the plan exists before the
edit.

Risk tags (`feature-risk-router`): `shared-gate`.
`security-review`: change-triggered arm is `not-applicable` — `security posture
unchanged`. Ruling out each blocker: no trust boundary (the gate reads this
repo's own tracked files, the same corpus `make test` already reads), no
untrusted-input surface, no sensitive sink, no auth/authorization semantics, no
data-visibility change, no secret handling, and it is neither a hardening nor a
vulnerability fix.
`visible surface: no`.

## Defect this closes

`013`'s sibling round repaired two references to a validation log under a
specs/009-claude-review-tool-boundary directory that never existed here. Neither was reachable by any control:

| Control | Why it missed |
| --- | --- |
| `check-markdown-links.py` | resolves only Markdown **inline-link destinations** (`](…)`) in tracked `*.md`. A backticked path in prose is invisible even inside Markdown |
| `tighten-doc`'s inbound-reference recipe | keys off "a heading you delete or rename". Nothing was renamed — the target was absent from the start |
| naming it out-of-scope in `010`'s Scope | prose in a spec that then landed. Nothing carried it forward, and only one of its two copies was ever found |

The extraction round for that repair recorded the residual risk as accepted:
this class stays caught by review, not by a verifier. This slice removes that
residual.

## Why `specs/`-scoped, measured rather than assumed

A general "every backticked path must resolve" check was prototyped and
**dogfooded first**, and it fails:

| Scope | Non-resolving | Dominant class |
| --- | --- | --- |
| all backticked path-shaped tokens (1167 total) | 139 occurrences / 75 paths | **correct content** — a product-agnostic skill naming a path in the *consuming* product repo (`test/.report-config.json`, `.feishu/project.yaml`, `ci/agent-gates.gitlab-ci.yml`), plus deliberate test fixtures |
| backticked citations under specs/ only | **2 occurrences** | both are prose *about* the dead path (`010`'s record and the register row citing it) |

The discriminator is ownership: `specs/` is a directory only this repo has and
whose contents are enumerable, so a reference into it is always checkable. Paths
in the consuming product repo are not this repo's to resolve, which is why the
broad check produced noise that would train readers to ignore the gate.

## Design

**Rule**: in any tracked file, a backticked token beginning `specs/` must resolve
to a path that exists. A trailing `:N` or `:N-M` line locator is stripped before
resolution.

**No exclusion list, no config — but two structural exemptions, both found by
dogfooding rather than designed up front.** A dead path is *described*, not
backticked as though a reader could open it, so historical mentions are rewritten
instead of registered. On top of that:

- **angle brackets mark a shape.** A path template is not a citation. **SUPERSEDED
  by 016**: this exemption was the gate's whole attack surface — five separate
  evasions across two review rounds — and is deleted. A template now names the
  shape without the prefix, or lives in a fenced block.
- **there is deliberately NO test-file exemption.** A first version skipped
  every test-named file so this gate's own fixtures would not trip it.
  Independent review killed it: one of the two dead pointers that motivated this
  gate lived in `skills/code-review/scripts/test_init_policy_matrix.sh`, so the
  exemption would have blinded the gate to its own motivating case. The suite
  assembles its fixture citations from fragments instead — one helper, and the
  corpus stays whole. Verified against the motivating case directly:
  reintroducing the original dead citation into that file makes the gate exit 1.

An abbreviation is deliberately NOT exempt: it still points a reader somewhere.

Rejected alternatives:

- **Allow-list the two paths.** This is the cross-landing anti-pattern the
  extraction ledger already names: predicating a control on a vocabulary the
  control does not own. The list would need an entry per future dead reference,
  which is exactly the class the gate exists to prevent.
- **A per-line opt-out marker.** New machinery, and it makes the escape cheaper
  than the fix.
- **Fold it into `check-markdown-links.py`.** That script's contract is Markdown
  link resolution over `*.md`; this check spans every tracked text file, which is
  the whole point — the shell-script copy is what survived. Widening it would
  make its name a lie.

## Design-time operability check

Required for any new mechanical gate.

| Leg | Result |
| --- | --- |
| author dogfood | **failed twice before passing, and the revisions are the finding.** Run 1 (untracked candidate): falsely clean — the corpus is tracked files, so a new spec is invisible until staged. Run 2 (staged): 22 findings, of which 17 were this gate's own test fixtures and 5 were this plan's own matrix rows. That is the leg working: a gate whose spec and suite cannot pass it is not operable. First resolution exempted fixtures by basename; independent review then showed that exemption blinded the gate to its own motivating case, so it was removed and the suite now assembles fixture citations from fragments. Matrix rows describe their input rather than embedding it. Final candidate: zero findings |
| marginal cost | zero for the routine change: a new spec citing `specs/012-challenge-index-default/plan.md` resolves. Cost is paid only when deliberately citing a path that does not exist, which is the case that should be visible |
| trust-model fit | defends against a reference whose target never existed or was removed. It does **not** defend against a reference that resolves but is semantically wrong — stated so the gate is not read as broader than it is. As a MANDATORY gate it must also be safe to run on hostile input: it never follows tracked symlinks, never resolves outside the checkout, and decodes losslessly rather than skipping a file it cannot decode |
| premise check (tightening) | a clean run on the current corpus is not evidence; the mutation rows below are |

## Acceptance matrix

| # | Input | Expected |
| --- | --- | --- |
| 1 | `` `specs/012-challenge-index-default/plan.md` `` and the file exists | pass |
| 2 | a citation whose target is absent, in a tracked `.md` (literal input in `test_absent_reference_in_markdown_fails`) | fail, naming file, line, and target |
| 3 | the same reference in a tracked **`.sh`** | fail — this is the copy every doc linter missed |
| 4 | `` `specs/010-review-concern-excerpt/plan.md:63` `` and the file exists | pass — the `:N` locator is stripped |
| 5 | `` `specs/010-review-concern-excerpt/plan.md:63-70` `` and the file exists | pass |
| 6 | a `specs/` directory reference that exists, with or without a trailing `/` | pass |
| 7 | a specs/ path in prose **without** backticks | pass — the gate's unit is the citation, not every mention |
| 8 | an untracked file containing a dead reference | pass — the gate's corpus is tracked files, matching `check-markdown-links.py` |
| 9 | a path starting `specs` but not `specs/` (`specsheet.md`) | pass — no false positive on the prefix |
| 10 | multiple dead references in one file | all reported, not just the first |
| 11 | this repo as it stands at closeout | zero findings |
| 12 | a backticked template carrying the specs/ prefix | ~~pass~~ → **fail, superseded by 016**: the exemption is deleted, so write the prefix outside the backticks |
| 13 | an abbreviated citation whose target is absent (literal input in `test_abbreviated_citation_is_not_exempt`) | fail — an abbreviation still points a reader somewhere, so it is a citation |
| 14 | a dead citation inside a tracked `test_*` file | **fail** — no test-file exemption; this is the shape of the surviving original |
| 15 | a tracked file carrying an invalid UTF-8 byte **and** a dead citation | fail — decoding is lossless, so one bad byte cannot silently remove a file from the corpus |
| 16 | a citation that traverses outside the repository to a file that really exists there | fail — containment is checked on the resolved path |
| 17 | a citation that traverses but stays inside the repository | pass |
| 18 | `plan.md#acceptance-matrix` where the base file exists | pass — path-plus-anchor is ordinary syntax; a false positive here would block every landing |
| 19 | the same shape where the base file is absent | fail — a fragment does not rescue a missing base |
| 20 | a fragment whose base file is absent but whose parent directory exists | fail — stripping the fragment must not eat the filename with it |
| 21 | a tracked symlink pointing outside the checkout at a file with a dead citation | pass — symlinks are not followed; a mandatory gate must not read data outside the repo, nor hang on a link to a device or a huge file |
| 22 | a non-ASCII tracked filename under a C locale | pass — `ls-files` output is split as bytes and decoded per entry, so the gate does not depend on the runner's locale |

Rows 12-13 were **not** in the first draft of this matrix. Dogfooding the
implementation against this repo produced six findings where the pre-measurement
had predicted two: the measurement's regex required a strict path charset and so
never saw the template class at all. Recorded rather than quietly folded in,
because the gap is the point — the pre-measurement in the table above was
narrower than the corpus, and only running the real gate exposed it.

## Test / register coverage

| Layer | Rows | Command | State |
| --- | --- | --- | --- |
| unit (new) | 1-10, 12-22 | `python3 scripts/test_check_spec_references.py` | add |
| repo gate | 11 | `python3 scripts/check-spec-references.py .` | add |
| wiring | the gate actually runs | `make test`; CI step beside the other two checkers | add |
| E2E / live | — | — | not applicable: no network, no external CLI |

Test-case-first: the RED assertions land and run RED before the checker exists.

**Mutation evidence** — executed, each applied in a disposable copy, restored,
and byte-compared against pristine (`sha256` equal). Control green. Every
mutation flipped its owning test; attribution is differential, since each owning
case passes in the control and fails only under its own mutant.

| Mutation | Observed |
| --- | --- |
| drop the `:N` stripping | `test_line_locator_is_stripped` |
| restrict the corpus to `*.md` | `test_absent_reference_in_shell_script_fails`, `test_test_named_file_is_not_exempt` |
| anchor the prefix loosely | `test_prefix_is_anchored_on_the_separator` |
| return after the first finding | `test_all_findings_are_reported` |
| drop the angle-bracket exemption | `test_angle_bracket_placeholder_is_ignored` |
| widen the exemption to any non-path char | `test_abbreviated_citation_is_not_exempt`, `test_fragment_does_not_rescue_a_missing_base` |
| re-add a test-file exemption | `test_test_named_file_is_not_exempt` |
| skip files that fail a strict decode | `test_invalid_utf8_file_is_still_scanned` |
| drop the containment check | `test_traversal_outside_the_repo_is_rejected` |
| drop fragment stripping | `test_fragment_is_stripped_when_base_exists` |
| follow tracked symlinks | `test_tracked_symlink_is_not_followed` |
| decode the whole `ls-files` stream first (`text=True`) | `test_non_ascii_filename_survives_a_c_locale` |
| strip the fragment and its base together | `test_fragment_stripping_does_not_eat_the_filename` |

The `*.md`-only mutation flips two cases because rows 3 and 14 both use non-`.md`
fixtures. Recorded as collateral rather than smoothed over; the owning flip is
present in both.

**The containment row was falsely green when first written, and the walk is what
caught it.** Row 16's first version cited a specs/../../../../etc/passwd path,
which resolves to nothing at a temp-directory depth — so the ordinary existence check
rejected it and the containment logic was never reached. Dropping the containment
check flipped **nothing**, which is the only reason the hole was visible. The row
now traverses through a real `specs/` directory to a file that genuinely exists
outside the repo. A mutation that flips nothing is a finding about the test, not
a clean result.

**It happened a third time, for the `ls-files` decode order.** The fix landed
with no row covering it, so reverting it flipped nothing — and the difference is
real: under `LC_ALL=C` with `PYTHONUTF8=0`, `text=True` raises on a non-ASCII
tracked filename while byte-split-then-decode does not. Measured before the row
was written, rather than argued.

**It happened a second time, for the fragment logic.** Rows 18-19 both survived a
mutation that strips the fragment *and the filename with it*, because 18's parent
directory exists and 19's does not — so neither row could see the over-strip. Row
20 was added for exactly that: a fragment whose base file is absent inside a
directory that exists. Two independent instances of the same lesson: a row that
passes proves nothing until a mutation shows it can fail.

Row 11 is not mutation-testable — it asserts the corpus is clean, so it can only
ever go red by regression. Recorded as a dogfood row, not sensitivity evidence.

## Status-sync target

This plan, plus the residual-risk sentence in the `code-review` register row from
the prior round, which this slice retires.

## Review / challenge gate

`shared-gate` requires both lanes before shared-branch push or MR merge:
`review_gate.sh --mode review` and `--mode challenge`, `--stage release`,
`--risk-tag shared-gate`, `IMPLEMENTER_FAMILY=anthropic`. The challenge focus is
the no-exclusion-list decision — whether rewriting the two historical mentions is
a legitimate design consequence or a checker being fitted to the corpus.

Verifier discovery: `check-ccl-skills.sh`, `check-agent-contract-coverage.sh
--enforce`, `check-public-sanitization.py`, `check-markdown-links.py`,
`make test`, `git diff --check`.

## Same-class recurrence decision: `keep`, with a scope discipline

Five findings across rounds 4-8 are **one class**: untrusted repository content
flowing through a gate that is mandatory, fail-closed, and whole-corpus. The
class is open-ended, so the decision is about SHAPE, not about the next patch.

Options weighed, each with its cost stated rather than implied:

| Option | Effect | Cost |
| --- | --- | --- |
| `narrow` — scan only files in the diff | most of the hostile surface disappears | loses the case where a spec is DELETED and inbound citations go stale — the near relative of the defect that motivated all of this |
| `weaken` — report without blocking | hostile input stops being fatal | it stops being a gate; a new dead citation can be ignored |
| **`keep`** | retains deletion detection and blocking | the gate's complexity comes from its blast radius rather than its job |

**Decided `keep`**, by the risk owner, because deletion detection is the
capability closest to the original defect.

**But `keep` is not a licence to fix every finding**, and the discriminator is
whether a fix ALIGNS WITH or EXCEEDS what this repo already holds itself to.
Measured against the two sibling gates in `scripts/`:

| Finding | Sibling behaviour | Disposition |
| --- | --- | --- |
| skip-on-decode-error | both siblings decode losslessly (`errors="replace"` / `"ignore"`) and never skip | **fixed** — the original was worse than both |
| `git ls-files` decode order | both split NUL as bytes, then decode per entry | **fixed** — `text=True` deviated from the established idiom and was strictly worse |
| following tracked symlinks | `check-public-sanitization.py:66` already guards it | **fixed** — matches the norm |
| resolving outside the checkout | no sibling resolves arbitrary target paths | **fixed** — specific to this checker's job |
| control characters in diagnostics | **neither sibling escapes them** | **NOT fixed here.** A guard was written, tested, and then reverted: holding the newest gate to a standard no other gate meets buys inconsistency, not safety |

Residual risks recorded rather than resolved, and routed as ONE follow-up so a
decision is made for all three gates at once rather than accreting in whichever
one was reviewed most recently: **the repo-root checkers share the same
hostile-input exposures — control characters in diagnostics, and a tracked
filename that is not valid UTF-8 (all three raise on `.decode("utf-8")`).**
Whether to defend either belongs to a dedicated round over `check-spec-references.py`,
`check-markdown-links.py`, and `check-public-sanitization.py` together.

## Review rounds

Reviewer `codex` (non-same-family; `IMPLEMENTER_FAMILY=anthropic` excludes the
Claude lane). Every round ran on a fresh full-scope packet, never a
confirm-my-fixes pass.

| Round | Finding | Disposition |
| --- | --- | --- |
| 1 | the recipe's newly cited plan path is not evidenced by the bounded packet | **refuted on the merits, packet widened.** The path exists and is tracked at the candidate revision, and this very slice adds the gate that proves it — but the packet was scoped to three files and excluded that gate, so the reviewer could not see it. Scoping error, not a code defect |
| 2 | the test-file exemption blinds the gate to its own motivating case | **accepted.** One of the two dead pointers lived in `skills/code-review/scripts/test_init_policy_matrix.sh`. Exemption removed; the suite assembles fixture citations from fragments. Verified directly: reintroducing the original dead citation into that file makes the gate exit 1 |
| 3 | a strict decode makes one invalid byte silently drop a file from the corpus | **accepted.** Lossless `surrogateescape` decode; an `OSError` now fails the run instead of being skipped |
| 3 | a citation may traverse outside the repository | **accepted.** Containment checked on the resolved path |
| 3 | this plan's mutation evidence contradicted the diff | **accepted.** A stale sentence survived a design change and described a row the matrix no longer had. The table above is now generated from the executed walk rather than written alongside it |

## Challenge lane, run late

This slice's own gate above requires **both** lanes before a shared-branch push
or MR merge. Only the review lane ran; the challenge lane did not, and the gate
landed anyway. Confirmed rather than assumed: no chain in the local review-
evidence store corresponds to this slice, and no packet in it touches
`check-spec-references`.

Run afterwards, against the landed diff, it found in one round what nine
review-mode rounds had not: the template exemption tested the raw token for any
angle bracket, before the fragment and locator were resolved, so a dead citation
carrying a bracket anywhere skipped resolution and this mandatory gate reported
success. Both lanes found it independently, and it reproduced first-hand against
the landed checker.

Fixed in specs/016-spec-citation-template-exemption/plan.md. The lesson is about
the gate that was skipped, not only the bug: a review lane answers "is this
correct", a challenge lane answers "how would this break", and the bypass lived
squarely in the second question.

The same run re-reported the invalid-UTF-8 filename crash this plan already
records below as an accepted residual routed to the three-checker round. It stays
routed there — with one correction owed to that round: row 22 uses a *valid*
UTF-8 name, so it cannot detect the invalid-byte case it appears to cover.

## Landing state

`landed` — the gate runs in `make test` and CI as of the commit that introduced
`scripts/check-spec-references.py`. This line previously read `plan drafted`,
which was stale from the moment the slice landed; corrected here.
