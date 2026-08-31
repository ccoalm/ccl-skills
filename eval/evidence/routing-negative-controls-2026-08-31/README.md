# Evidence — negative-control / coverage-gap bank rows + replica metrics (2026-08-31)

Live-instrument evidence for the routing-bank extension landed in this round
(none sentinel, acceptable[], --replicas, clarify/low-confidence/agreement
metrics, absorbed/ownership_split labels). Cited by the round's
source-register row for the bank owner. What these numbers are NOT: a
regression verdict over the full bank (no description changed this round; a
different (bank, replicas) configuration is a different ruler).

## Invocation (identical for all three runs except the bank snapshot)

```
ruby skills/skill-extraction-workflow/scripts/eval-routing-bank.rb <repo-root> \
  --bank <the five new rows extracted to a scratch file> \
  --replicas 2 --timeout 90 --json <artifact>
```

- Grader model: `claude-haiku-4-5` (recorded in each report's `model` field).
- Candidate identity: worktree at round base `6f85950` (origin/dev) with the
  round's working tree; each report's `routing_surface.bank_sha256` /
  `catalog_sha256` fingerprints the exact graded surface.
- Raw per-replica verdicts are in each report's `results[].verdicts`.

## Runner provenance

The shipped runner is the one in this change set; `probe-r4-shipped-runner.json`
is its artifact (report carries the full final field set: `error_verdicts`,
`partial_error_tasks`, `baseline_comparable`, …). `probe-r1`–`probe-r3` were
produced by mid-round iterations of the runner while the instrument was being
built — they are kept ONLY for the correction narrative below and predate the
final report schema; do not read them as artifacts of the shipped runner.

## Shipped-runner artifact

`probe-r4-shipped-runner.json` (grader `claude-haiku-4-5`, `--replicas 2`,
`CCL_SKILL_BASE_REF=origin/dev`): 5/5 pass, replica agreement 4/5, clarify
1/10, low-confidence 0/10.

## The three mid-round runs (correction narrative, kept deliberately)

| run | bank snapshot | outcome |
|---|---|---|
| `probe-r1-gap-frozen-none.json` | gap probes frozen as `expected: none` | negative controls 6/6 `none`; **both gap probes absorbed**: one replica answered `none`, the other pulled each into a coordinator skill — `absorbed` + `ownership_split` labels fired on real grader output |
| `probe-r2-gap-coordinator.json` | gap expectations corrected to coordinator-expected | 4/5; residual defensible split (coordinator vs `none`) on one probe — evidence that BOTH outcomes are right for a hole |
| `probe-r3-final-acceptable.json` | final: coordinator expected, `acceptable: ["none"]` | **5/5 pass, replica agreement 4/5, clarify 2/10, low-confidence 0/10** — the shipped expectations |

Lesson recorded in the round register: freezing a coverage-gap probe as pure
`none` mislabels defensible coordinator intake as failure; the pair
(expected + acceptable) is the honest ground truth.

## Integrity-lane red/green differential

`integrity-red-green-transcript.txt`: four applied bank mutants (sentinel in
must_not, acceptable restating expected, unknown acceptable target,
acceptable∩must_not) each red on their own named assertion; unmutated control
green; exit differential red=1 / green=0.

## Deterministic gates at the round commit

`make test-repo-gates` with `CCL_SKILL_BASE_REF=origin/dev` exit 0;
`check-ccl-skills.sh` at `ccl_skill_check_clean_ok`; `git diff --check` clean.
