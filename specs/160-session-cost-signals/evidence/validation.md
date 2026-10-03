# Validation evidence

## Sources

A retrospective over Claude Code transcripts and Codex rollouts from one month
(one product line's repositories plus this one). Per-session metrics were
computed by script for every file; Codex threads were deduplicated on turn,
response and command ids (files over-stated them about threefold). Prices for
the dollar shares come from the bundled API price table; host behavior
(auto-compaction window, transcript retention) was checked against the primary
Claude Code documentation. Raw per-session data stays in a private archive.

## Measurements behind the round

| Measure | Value |
| --- | --- |
| Product-line Claude interactive sessions | 146, about 58k requests |
| Request context, median / p90 | about 453k / 821k tokens |
| Cost share of requests above 300k / 500k context | about 85% / 62% |
| Cost components | cache read 73%, 1h cache write 15%, output 10% |
| Base context at a session's first request | about 126k tokens |
| Task-entry injections on background notifications | 1,410 of 4,151 (34%) |
| Resumptions after ≥ 1h idle rewriting > 200k tokens | 83, about $5.5 each |
| Conclusive review runs on single changes (deep-read sample) | 13 to 49 |

## Reproduction on main (RED) and the change (GREEN)

| Change | RED on main | GREEN |
| --- | --- | --- |
| Context notice | `hooks/test_proposed_next.py`: the three new cases fail; 39 existing pass | 42 pass; a real 45 MB transcript prints the notice in 0.2 s and keeps the existing reminder text |
| Task-entry skip | `hooks/test_task_entry.py`: both notification prompts receive the entry; controls pass | 8 pass |
| Review-run count | the previous controller after six conclusive runs writes no count and returns no checkpoint | `test_review_gate.sh`: 310 checks ok, including the three new ones |

## Behavior replays

Pre-registered before running (rubric, arms and decision rule frozen; blind
grading by a separate call). Model `claude-opus-5-5`, tools disabled, hooks
disabled, no user settings, n = 6 per arm.

| Question | Arms | Result | Reading |
| --- | --- | --- | --- |
| Does the checkpoint object change the next action when only the latest finding is visible? | without / with `continuation_checkpoint` | 2/6 / 6/6 step back before patching | effect claimed (pre-registered threshold met) |
| Does the added same-class sentence change the next action when three same-area findings are listed? | old text / new text / new text plus object | 6/6 / 6/6 / 6/6 | ceiling; no claim |
| Would a session-history counting reference make a planner deduplicate? | without / with the reference | 6/6 / 6/6 | ceiling; the reference was withdrawn |

Deviation: the same-class sentence was drafted before its rubric was written;
the rubric judges only whether the chosen next action questions the classifier,
and grading was blind. The second measurement was registered after reading two
answers of the first and before any grading.
