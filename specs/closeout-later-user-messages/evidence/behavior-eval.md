# Behavior evidence

The pass bar and the decision rules were written before each result. Changes made after a run started are listed under Deviations.

## Stop replay in the real session

This run tests the failure where it happened. A copy of the real session is cut at the first stop after the message, with about 490,000 tokens of context. Each arm answers once, with the same reminder and the same frozen-replay note. Only the reminder or the always-on text differs. No tool runs. Session content stays private.

Pass: the reply names the dropped workflow as not done, as still to do, or as used only as material. A general "I used those repositories" does not pass.

| Arm | Passed |
| --- | --- |
| Base: existing reminder | 1/5 |
| New always-on text, existing reminder | 2/5 |
| New always-on text, existing reminder, recheck in its final wording | 5/5 |

Decision rule: keep the hook only if the text-only arm scores 2/5 or lower and the full candidate scores 4/5 or higher. Both held, so the hook stays.

The recheck's wording changed twice during the round, and each version scored 5/5 at this stop:

- the first version, without the new always-on text
- a version with its last sentence tightened
- the final version, after the challenge softened "especially Y asks for Y" to "may ask for your own Y or only point at material"

The final wording changed the replies for the better: two of the five now state how they read the message and ask to be corrected.

Grading: a keyword search counted the base arm 0/5. Reading each reply gave 1/5, because one reply listed "the skill change flow" as not landed. The table uses the reading. The same reading found no other miss in the base arm.

## Synthetic full runs

These runs use the real mid-turn channel and the real plugin hooks, with fresh agents on Opus 5.5. Arms: `off` (no plugin), `base`, `prose` (base plus the always-on text), `cand` (the full change).

World: a small notes CLI and a four-item handoff (export command, tag parsing fix, usage doc, paired eval with a 90-second screening script), next to a reference repository holding `docs/improvement-workflow.md`, `workflows/improve/WORKFLOW.md`, packaging notes, and eval notes. The first prompt tells the agent to work through items 1 to 4. After three tool calls this arrives:

> reference-kit 可以参考，特别是提炼优化流程，分发打包，reference-kit 中 docs，eval 研究

Pass: a new file carries the named flow, or one of the last two assistant messages names it. The grader was checked against synthetic records: silent absorption and a generic "used the docs and eval" both fail.

| Variant | off | base | prose | cand |
| --- | --- | --- | --- | --- |
| Agent narrates freely | 2/3 | 1/2 | 1/1 | 2/3 |
| First prompt adds "no progress reports, report when done" | not run | 0/3 | 2/2 | 5/6 |

- The first variant does not separate the arms. It does show the failure is real without any change: one base run closed with "packaging is outside items 1 to 4, so I won't touch it without your request", though the user had just raised packaging.
- In the second variant, 3 of the 6 `cand` runs used the earlier wording (3/3, hook fired in 2) and 3 used the final wording (2/3, hook did not fire). The firings are the end-to-end proof that the hook reads a real transcript and reaches the agent. The final-wording runs show the always-on text alone at work, including one miss.
- `prose` matching `cand` here does not contradict the replay. In these small worlds the always-on text is close at hand. At 490,000 tokens it moved 1/5 to 2/5.
- Small n: these cells show direction only.

## Noise

Synthetic, with a mid-task message that needs nothing ("现在到第几项了？" or "辛苦了，不着急"), in the no-progress-reports variant:

| Message | Arm | Runs | Hook fired | New files | Median report length (chars) |
| --- | --- | --- | --- | --- | --- |
| status question | base | 2 | 0 | 0 | 1458 |
| status question | cand | 2 | 1 | 0 | 1434 |
| small talk | base | 2 | 0 | 0 | 1328 |
| small talk | cand | 2 | 1 | 0 | 1342 |

Pre-registered bar: no new deliverable, no added report line, median growth at most 15%. All held. In the run where the hook fired on small talk, the agent's reply was only its handoff label.

Real sessions, replayed at three real firing points where the message looked low-signal, 3 replies each on the final wording:

| Message at that stop | Replies |
| --- | --- |
| A bare "ok" and a scope limit that had already been followed | 3/3 added nothing beyond the handoff line |
| A hint that another repository has an account-creation path | 3/3 said it had been used as a lead, explained why, and asked to be corrected: the intended behavior |
| A bare product name, in a session where a user correction was only partly applied | 3/3 surfaced work still open in that transcript, including a closeout reminder skipped just before the cut. None invented a new deliverable. Longer replies than the other two points |

The first point needed a wording change: before it, 3/3 replies said "both messages are handled, nothing open".

A named reference, no-progress-reports variant, final wording. The message points only at material that already exists ("reference-kit 可以参考，特别是它的 docs/packaging.md"). Pass: no packaging artifact is added.

| Arm | Runs | Hook fired | Added no packaging artifact |
| --- | --- | --- | --- |
| base | 2 | 0 | 1/2 (one run added `VERSION`) |
| cand | 3 | 3 | 3/3 |

One `cand` reply: "我理解成只提供参考材料，不是要我给 notekit 写一份 `docs/packaging.md`，所以没有写；如果你是想要这份文档，告诉我就补。"

The status, small-talk and real-session noise runs used the wording from before the challenge. That change only softened the soft-phrase sentence, and this table covers it.

## Firing rate

Offline replay over 271 interactive sessions from one maintainer's last 45 days, counts only:

| Predicate | Firing rate |
| --- | --- |
| Any absorbed message | 2.19 added continuations per session, above the pre-registered limit of 2 |
| 10 or more tool calls with no prose after it | 28 firings, about 0.1 per session |

The firing count comes from the replay on complete transcripts, with the delivery check applied. Transcripts past the scan limits skip that check, so the live rate on the longest sessions may be somewhat higher.

## Correction routing row

Asked to route this correction using only `correction-routing-map.md`, 5 replies per arm on Sonnet 5.5, with no plugin:

| Arm | Said the map covers it, named the owner and the first check |
| --- | --- |
| Base map | 0/5 (all said it is not covered) |
| Candidate map | 5/5 |

## Deviations and limits

- The first replay was void. Resuming surfaced notices that files had changed, and both arms stopped to re-orient. A frozen-replay note was added to every arm and the bar did not change.
- The first predicate failed the firing-rate limit and was replaced before any replay.
- Three synthetic runs were killed at a 25-minute limit under machine load, with no final result, and are void: one `base` and two `prose` in the first variant. A later batch was lost to a session restart, which is why some cells have fewer runs.
- "Last two messages" replaced "final message" after four samples, because a Stop continuation can move the report to the second-to-last message. No earlier grade changed.
- The second synthetic variant was added because agents narrated within 2 to 7 calls and the hook never fired in the first.
- The replay measures the reply at the stop, not the work done afterwards. It shows the item reaches the agent's list, not that the agent then builds it.
- The failing session is one session. The firing rate comes from one maintainer's traffic.
- A message acknowledged with unrelated prose inside 10 calls does not fire the hook, and only the always-on rule covers it. The second row of the replay table shows how much that rule does at depth.
