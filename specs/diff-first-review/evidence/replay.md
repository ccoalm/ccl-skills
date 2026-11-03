# Replay: diff-first runner against the packet controller

Eight changes from this repository's history, each followed by a fix commit
that repaired defects it introduced (found by blaming the lines each fix
removed). Each change was reviewed again by both runners, in review and in
challenge mode, with Codex as the reviewer in every arm and the change's own
commit message as the intent. A separate judge, blind to which runner produced
which set, scored every finding set against the fix diffs: 27 known defects in
all.

| Arm | Known defects caught | Partial | Other real issues | Noise | Precision |
| --- | --- | --- | --- | --- | --- |
| diff review | 7 | 1 | 8 | 0 | 100% |
| packet review | 12 | 2 | 7 | 12 | 64% |
| diff challenge | 11 | 1 | 8 | 0 | 100% |
| packet challenge | 9 | 1 | 3 | 1 | 93% |
| diff review with the packet's concern walk | 7 | 2 | 12 | 2 | 91% |
| diff challenge with the concern walk | 10 | 3 | 15 | 2 | 93% |

Review then challenge, the daily-development flow, caught 12 of the 27 with
either runner (union per case); with the concern walk added, 11.

Conclusive runs: diff 16 of 16, packet 15 of 16 (one `tool_boundary_violation`).
Mean wall time: diff review 179 s, packet review 223 s, diff challenge 215 s,
packet challenge 171 s. An earlier harness cut two intents mid-character; the
packet controller refused them and the diff runner crashed, which the runner now
handles. Those two cases were rerun with whole-character intents for both.

A fourth arm put the whole saved diff inline in the diff runner's prompt
(repository access unchanged). Scored blind with the diff and packet arms in a
separate pass: diff review 8 caught, inline-diff review 7 caught plus 1 partial,
packet review 12 caught plus 2 partial; challenge 11, 10 and 9.

Review then challenge, union per case, in both blind passes that included
these arms:

| Flow | Known defects caught |
| --- | --- |
| diff review, diff challenge | 12 |
| packet review, packet challenge | 12 |
| packet review, diff challenge | 14 |
| diff review, diff challenge, plus a packet review | 15 |

Reading: in review mode the packet controller finds more of the known defects
and much more noise; in challenge mode the diff runner finds more with none.
Neither the concern walk nor inlining the diff closed the review gap, so it
comes from elsewhere in the packet path (its structured per-concern output, or
a reviewer confined to the diff). The two flows catch the same total, and the
two runners catch different defects, so pairing a packet review with a diff
challenge caught the most. Eight cases bound how far these numbers generalize.

## The review brief

The arms above share the runner's first review brief, which asked only for
defects the reviewer could show from the code and to skip speculation. A
relaxed brief asks for every suspected defect with its failing scenario,
including ones it could not fully confirm, and to say what it could not
confirm. Scored blind with the diff and packet review arms (30 known defects in
that pass):

| Review arm | Known defects caught | Other real issues | Noise | Precision |
| --- | --- | --- | --- | --- |
| diff review, first brief | 8 | 7 | 1 | 94% |
| diff review, relaxed brief | 15 | 13 | 9 | 76% |
| packet review | 14 | 4 | 15 | 55% |

The review gap came from the brief. The relaxed brief is now the runner's
review brief; the challenge brief is unchanged.

Two further arms, each scored blind with the diff and packet arms, did not
close the gap: owner skills as review lenses plus the packet's review method
and per-concern conclusions (review 8 caught, 2 partial), and the inlined diff
reported above.

## Repeat runs, owner lenses and other repositories

Each figure above came from one run per arm. To see the spread, the relaxed
review brief, the same brief with owner skills as review lenses (the selected
owners' `SKILL.md` paths named in the prompt, read before judging), and packet
review ran again: three runs, two and three on the eight cases here, and two,
two and one on ten changes from four Go and Python service repositories, each
also followed by a fix commit for defects it introduced. One judge per
repository set scored every run blind in one pass (32 and 27 known defects).

| Arm | This repository: caught per run | Noise per run | Service repositories: caught per run | Noise per run |
| --- | --- | --- | --- | --- |
| relaxed brief | 13, 13, 16 | 1, 0, 1 | 16, 15 | 1, 1 |
| relaxed brief with owner lenses | 13, 13 | 2, 3 | 16, 15 | 3, 2 |
| packet review | 12, 10, 11 | 13, 12, 12 | 7 | 17 |

- Owner lenses did not help. Paired by case they beat the plain brief on three
  changes and lost on four here, and tied on eight of ten service changes with
  the same totals, at slightly more noise. The runner names no owner skills.
- Run-to-run spread for one arm reached three caught defects over eight cases;
  a single run cannot separate arms closer than that.
- On the service repositories the diff runner caught about twice as many known
  defects as packet review with a fraction of the noise; packet review was
  inconclusive on three of ten (two `tool_boundary_violation`, one
  `egress_denied`), the diff runner on none.
- Limits: the ground truth is later bug fixes only, so lenses could still help
  where the defect is a broken contract or process rule that nobody later fixed
  in code; Codex was the reviewer in every arm.
