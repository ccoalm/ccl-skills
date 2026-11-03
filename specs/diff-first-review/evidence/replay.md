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
