# 017 — The repo-root checkers survive a filename git allows and UTF-8 does not

## Artifact classification

`gate implementation` (per
`product-rd-workflow/references/shared-gate-artifact-classification.md`): it
changes the failure behaviour of three mandatory, fail-closed gates. Risk tags
(`feature-risk-router`): `shared-gate`.

`security-review`: change-triggered arm is `not-applicable` — no trust boundary,
sink, or authority semantics change; the fix makes an existing enumeration
lossless. `visible surface: no`.

This discharges the follow-up `014` routed: it recorded that the three repo-root
checkers share their hostile-input exposures and that the decision belonged to
one round over all three, not to whichever gate was reviewed most recently.

## The defect, measured

`git ls-files -z` returns raw bytes, and Linux permits a tracked filename that is
not valid UTF-8. All three checkers decoded it strictly, so one such file made
each raise `UnicodeDecodeError` **before scanning anything** — a traceback
instead of a diagnostic, and every landing blocked for everyone.

Driven directly, because the filesystem path is unreachable here (below):

| Checker | Before | After |
| --- | --- | --- |
| `scripts/check-markdown-links.py` | `UnicodeDecodeError: invalid start byte` | survives, both entries returned |
| `scripts/check-public-sanitization.py` | `UnicodeDecodeError: invalid start byte` | survives |
| `scripts/check-spec-references.py` | `UnicodeDecodeError: invalid start byte` | survives |

## Reachability, and why the fix stays one line

This is the part that sizes the work, and it was measured rather than assumed:

- **On macOS it cannot happen.** APFS rejects the name outright — creating it
  fails with `Errno 92 Illegal byte sequence`. This team develops mainly on
  macOS, so no local commit can introduce one.
- **On CI it can.** `.github/workflows/ci.yml` runs on `ubuntu-latest` and
  invokes all three checkers directly, where such a name is legal.

So the hazard is real but low-probability: it needs a Linux-authored or crafted
commit. The fix is one line per checker (`os.fsdecode` instead of a strict
decode), which is cheap enough that the low probability does not argue against
it — and expensive to need under pressure, since it would surface as three
mandatory gates crashing at once.

`surrogateescape` round-trips back to the original bytes when the path is
opened, so the file is still *scanned* rather than merely tolerated.

## The second routed exposure: declined, then demonstrated, then fixed

`014` routed **two** shared exposures here. The second — control characters in
diagnostics — was declined in this plan's first draft on `014`'s reasoning (no
sibling escapes them) plus a failed reproduction attempt.

**The challenge lane was right to push back, and the reproduction settles it.** A
tracked filename may legally contain a newline — valid UTF-8, legal on macOS, no
exotic platform needed — and the finding then splits across two physical lines:

```
docs/inno
cent.md:1: spec citation does not resolve: ...
```

Anything reading that output line by line — a person, a CI annotation parser —
sees a forged line, and after `os.fsdecode` the same interpolation now also
carries surrogates for non-UTF-8 bytes. My earlier "did not reproduce" was about
a different vector (the citation *target*), so it did not license declining this
one.

All three checkers now escape untrusted text at the point of display, and only
there: the value used for resolution is untouched, and printable non-ASCII (an
ordinary CJK filename) is preserved. The sibling-inconsistency argument that
justified `014`'s decline no longer applies, because all three change together —
which is precisely why `014` routed it as one round.

## Review rounds

Reviewer `codex`, both lanes.

| Round | Finding | Disposition |
| --- | --- | --- |
| 1 (review + challenge) | the tests asserted only the entry COUNT, so a lossy decode would pass while breaking the round-trip the plan claimed | **accepted.** The assertions now require the bytes, and a lossy-decode mutant is caught per checker |
| 1 (challenge) | a filename may legally contain a newline, splitting a finding across physical lines — the declined exposure, unbacked by a reproduction | **accepted after reproducing it**; see the section above. Declining an exposure on a failed reproduction of a *different* vector was the error |
| 2 (review + challenge) | the `unreadable` diagnostic still interpolated the name and error raw — the same exposure one line away | **accepted, fixed.** Every print in all three checkers that interpolates untrusted text now routes through `display()`; an audit of the remaining interpolations found none left |
| 2 (review + challenge) | `display()` was not reversible: a real newline and a filename containing a literal backslash-n rendered identically, and tabs passed through raw | **accepted, fixed.** Backslash is escaped first, then every non-printable including tab; printable non-ASCII is preserved |

**A test that passed for the wrong reason, caught by mutation rather than by
reading it.** The first version of the unreadable case asserted the escaped name
was *somewhere in* the line — but `OSError`'s message repr()s the path, so an
escaped copy appears there even when the diagnostic's own name field was split.
The mutant went undetected until the walk said so; the assertion now requires the
escaped name to be the line's first field.

## Acceptance matrix

| # | Input | Before | Expected |
| --- | --- | --- | --- |
| 1 | tracked name that is not valid UTF-8, all three checkers | **crash** | enumerated, and the name round-trips to its original bytes so the file is still scanned |
| 2 | ordinary tracked names | pass | pass — unchanged |
| 3 | a filename containing a newline, in a finding | **two physical lines** | one line, escaped |
| 4 | a printable non-ASCII filename | pass | pass — not escaped |
| 5 | this repo at closeout | pass | pass |

## Test / register coverage

| Layer | Rows | Command | State |
| --- | --- | --- | --- |
| unit | 1-2 | the three `scripts/test_check_*.py` suites | add one case each |
| repo gates | 3 | the three checkers over this repo | run |
| wiring | gates still run | `make test` | run |

The enumeration is driven directly rather than through the filesystem, because
the name cannot be created on this platform — the test would silently pass by
never constructing its own input.

**Mutation evidence**, applied per checker in a disposable copy: reverting each
`os.fsdecode` to a strict decode makes that checker's own suite exit non-zero,
and so does replacing it with a LOSSY decode (`errors="replace"`) — the case the
first version of these tests would have missed, because asserting only the entry
count cannot tell a round-tripping decode from a mangling one. Dropping the
display escaping flips the newline case. Four mutants, four caught.

## Status-sync target

This plan, and `014`'s routed follow-up — its filename half is discharged here;
its control-character half stays accepted with the reasoning above.

## Extraction disposition

Round charter: discharge `014`'s routed follow-up; depth `targeted check` over one
enumeration function per checker.

RCA, widened rather than a single chain: the strict decode is in all three
because `tracked_files` is **copy-duplicated** across deliberately self-contained
scripts, so one defect replicated three times with no single owner to fix. `014`
saw that and routed it here rather than patching the newest gate alone.
Counterfactual: a shared helper would make it one fix, but it trades the repo's
self-contained-script idiom for coupling — not worth it for three lines.

Candidate reusable lesson — *a hazard unreachable on the team's dev platform is
still reachable on the CI platform* — is **discarded this round, with evidence**,
not landed:

| Check | Finding |
| --- | --- |
| observed how often | once (this round) — the bar for landing a durable rule is not met |
| existing owner | `testing-strategy` already lists device/browser/platform among its scenario dimensions; a second surface would fork the discipline |
| landing surface available | both candidate entrypoints are severe size debt, where the anti-monotonic-growth gate blocks an appended bullet — as it did in the previous round |
| always-land path | does not fire: this round is a planned follow-up discharge, not a routing miss, shallow retro, or validation gap |

If the class recurs, this plan is the evidence for landing it then. No
`source-register` row is added, because no skill package changes in this slice —
the durable record is this plan.

## Review / challenge gate

`shared-gate` requires both lanes before shared-branch push or MR merge:
`review_gate.sh --mode review` and `--mode challenge`, `--stage release`,
`--risk-tag shared-gate`, `IMPLEMENTER_FAMILY=anthropic`. Challenge focus: whether
`os.fsdecode` genuinely keeps the file scannable rather than merely non-crashing,
and whether declining the control-character half is defensible.

## Landing state

`local status`. Branch `worktree-repo-root-checker-hostile-input`, stacked on
`worktree-spec-ref-placeholder-bypass` because that branch also modifies
`scripts/check-spec-references.py`; unpushed.
