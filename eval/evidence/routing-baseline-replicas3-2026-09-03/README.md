# Routing bank baseline — replicas 3, bank 158

A fresh absolute baseline for the Tier-2 routing bank. It is **not** a regression
comparison, and no comparison to the previous full-bank run exists.

## Why there is no comparison

The runner refuses to diff reports taken with different rulers: it compares the
baseline's `bank_sha256` and `replicas` against the current run and suppresses
the diff when either differs. Passing the 2026-08-14 report as `--baseline`
produced exactly that refusal:

```
⚠ baseline not compared — different ruler: bank content differs
  (baseline b30280289422… vs current 1bf0633717c2…)
```

The bank grew from 136 rows to 158 between the two runs, so the old ruler was
voided by a bank edit and no replica setting recovers the comparison. The
previous run also predates `--replicas` and counts as 1, so the two reports
differ on both axes the runner checks.

The consequence worth recording: **a bank edit silently orphans every prior
baseline, and nothing signals it.** Between the two runs the routing surface
moved (see `description-drift-vs-2026-08-14.txt`: six descriptions changed, one
skill added, 32 → 33) with no measurement able to see it.

## The ruler this run establishes

| Field | Value |
| --- | --- |
| grader model | `claude-haiku-4-5` |
| tasks | 158 |
| replicas | 3 |
| `bank_sha256` | `1bf0633717c2…` |
| `descriptions_sha256` | `c29f826e3812…` |
| skills in the surface | 33 |
| `desc_budget_chars` | none (plain arm) |
| `frozen_drift` | empty |

A later run is comparable to this one when it uses the same bank content and
`--replicas 3`. Pass `full-bank-replicas3.json` as `--baseline` and the runner
will either diff it or say why it cannot.

### Why this file is not byte-identical to the runner's output

The runner writes `JSON.pretty_generate`, which came to 180,399 bytes — enough
on its own to push this round's candidate past the binder's 200,000-byte packet
cap, so the gate could not freeze a candidate at all. The file here is that
report re-serialised without indentation (114,954 bytes). No value was edited,
added, or dropped: the transformation is `JSON.generate(JSON.parse(original))`,
and the parsed object graphs of the two files compare equal.

- sha256 of the runner's original pretty-printed output:
  `5e213f72787a83f2edf1c22e7e6c35e09318a14d8687e4ef545f4337755bd1f2`
- the original is retained in the round's private archive.

Recorded rather than left implicit because an evidence artifact that is not the
tool's literal output has to say so, and because the next round hitting the cap
should reach for this before reaching for a partition manifest — a manifest
costs a ledger per partition, which is a disproportionate answer to whitespace.

## Reading the result

`144/158 pass, 14 fail, 0 grader-error`; clarify on 36 of 474 verdicts,
low confidence (<0.5) on 9; replica top-1 agreement 143/158.

**Thirteen of the fourteen failures carry the `ownership_split` label** — the
three replicas did not agree on the top-1 skill, and the conservative consensus
(any valid replica FAIL ⇒ FAIL) reports the task as failing. These are not
deterministic misroutes; they are tasks whose ownership is unstable across
gradings of the same description text.

Exactly one failure is consistent across all three replicas:
`p3-resume-refactor` (expected `product-rd-workflow`, graded `none` three times
at confidence 0.3/0.3/0.25).

That split is the point of grading each utterance at least three times: a
single grading cannot distinguish an unstable task from a passing one, so a
one-replica report reads a coin flip as a verdict. The previous full-bank run
was taken at one replica, which is a further reason its numbers do not describe
this bank.

Neither the ownership splits nor the single consistent failure are dispositioned
here. This directory is the measurement; acting on the routing gaps is a
separate change to the routing surface, and changing a description while
holding a routing measurement in the same round is the co-change shape the
runner already warns about.
