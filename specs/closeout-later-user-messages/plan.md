# A request made mid-task never reached the closeout check

## Problem

An agent worked from a four-item handoff. While it was running, the user added one casual line: other repositories could serve as a reference, "especially" a named workflow, plus packaging, docs and eval research. The host delivered this line inside a running turn. The agent used the eval material and did not produce the named workflow. At closeout it reported against the four items. The user had to ask later whether the workflow had been added, and only then was it built.

The rule already existed. `session-start.md` says "before the final message check every requested item". It did not fire.

## Result class

failure/correction: the user pointed out the miss.

Disconfirming observation: the class would be wrong if the agent had listed the item or reported it as unbuilt before the user asked. The session transcript shows neither.

## Root cause, checked against the transcript

| Factor | Category | Counterfactual |
| --- | --- | --- |
| Closeout walked the list the agent was tracking, which was the handoff's four items. The message had no slot on it | process model | Necessary: on the list, it would not have been missed |
| A generic recheck fired at closeout and told the agent to finish "the remaining requested work". The agent answered that nothing remained | missing control | Necessary: rechecking against the same list cannot find what is not on it |
| The host delivered the message inside a running turn, and the agent made 45 tool calls before writing any prose | trigger | Contributes: five other messages of the same shape were acknowledged, so it is not sufficient alone |
| The wording read as material ("can be a reference") | knowledge | Contributes, and it cannot be judged mechanically |
| `none — status only` stops pass every other reminder | detection | Secondary |
| The same request appeared in an earlier session, and the handoff written from that session omitted it | latent | Probabilistic: one observation, and the earlier wording was broader |

Ruled out: context compaction. The session had none, so the message stayed in context throughout.

## Why the existing surfaces did not catch it

| Surface | What it checks | Why it missed |
| --- | --- | --- |
| `session-start.md` Handoffs | "every requested item" | The agent decides what counts as requested and walks its own list |
| `pre-final-continuation-gate.md` | Landing state, deferred evidence, continuation | Nothing looks at user messages |
| `delivery-lifecycle.md` Completion Evidence Gate | Evidence for claims made | A missing item is not a claim, so there is nothing to verify |
| `proposed-next-stop.sh` | Handoff labels and declared next actions | Reads the final message and never the messages before it |

## Change

One owner rule, one mechanical firing point:

1. **Rule.** Requested items include each later user message, however casually put. "Can reference X, especially Y" may ask for the agent's own Y or only point at material. When the agent cannot tell, used a message only as material, or left it open, it says so in one line instead of absorbing it silently.
2. **Firing point.** The Stop hook adds one recheck when a person's message was absorbed into a running turn and the agent then made 10 tool calls with no prose. It joins a reminder already firing and also covers a `none — status only` stop that would otherwise pass. It needs delivery evidence, counts messages, never reads or echoes their wording, and leaves the judgment to the agent. On a transcript past the scan limits it skips the delivery check, because the tail may have lost that evidence; the worst case is one extra continuation per message in a long session.

Boundary against noise:

- The hook does not classify wording. A phrasing test on this hook family has repeatedly failed, and whether "can reference X" asks for X only the agent can read.
- Answered questions, used authorizations, status checks and small talk need nothing. Finished items stay out of the report. When nothing is open, the agent says nothing about the recheck.
- A message counts only when its origin is a person. Peer agents and task notifications do not.

### Choosing the predicate

Offline replay over 271 interactive sessions from one maintainer's last 45 days, counts only:

| Predicate | Added continuations per session |
| --- | --- |
| Any message absorbed mid-turn | 2.19 (above the pre-registered limit of 2) |
| 10 or more tool calls with no prose after it | about 0.1 (28 firings) |

Of 797 absorbed messages, 41 waited for 10 or more tool calls or never got prose. Reading all 41: most are real requests, such as asking for a version bump after a fix, taking over a merge request, or limiting a change to one environment.

The threshold trades recall for quiet. A message acknowledged with unrelated prose inside 10 calls does not fire the hook, and only the rule covers it.

### Why both the rule and the hook

Replaying the real stop, with about 490,000 tokens of context, the base scored 1/5, the new text alone 2/5, and the text plus the recheck 5/5. In small synthetic worlds the text alone matched the full change (2/2, small n), where it sits close at hand. At that depth it did not. The rule still earns its place: it is all that other hosts have, and it covers messages the hook does not see. Details, void samples and limits are in `evidence/behavior-eval.md`.

## Target-output map

| Owner | Direction | Status | Reason |
| --- | --- | --- | --- |
| `agent-context/session-start.md` | always-on rule | updated | Canonical wording of what counts as requested |
| `hooks/host-input.py`, `hooks/test_proposed_next.py` | firing point | updated | The recheck and its tests |
| `product-rd-workflow` `pre-final-continuation-gate.md` | owner | updated | Documents the recheck and the walk |
| `product-rd-workflow` `delivery-lifecycle.md` | owner | updated | "Complete" also covers what was asked |
| `product-rd-workflow` `SKILL.md` | owner | unchanged | Entrypoint in size debt; its gate already routes to the reference |
| `agent-context/session-policy.md` | always-on detail | unchanged | Holds no closeout wording to align |
| `code-review` `staged-review-contract.md` | review | unchanged | All eight review passes in the session quoted only the requests the agent was tracking, so this safeguard failed too. But each pass reviews one slice's diff, and a request outside that slice would read as a false finding there. Closeout is the point that sees the whole task |
| `skill-extraction-workflow` `correction-routing-map.md` | this workflow | updated | Objective narrowing owes a prevention point here. A correction naming a dropped later request now routes to the recheck and first asks whether it fired |
| `skill-extraction-workflow` `dual-track-review-gate.md` | this workflow | updated | The marginal-cost check now says to replay a reminder's predicate over real transcripts; the first predicate here failed that check |
| Stack and testing skills | sibling | not applicable | Closeout is not stack-specific |

Compression that keeps `session-start.md` at its size (it loads in every session):

| Removed | Where the obligation lives |
| --- | --- |
| "Main is an integration baseline." | The sentence before it requires a separate git-dir and a named non-default branch; `worktree-isolation` owns the detail |
| "finish authorized work without scope expansion" shortened to "no scope expansion" | "finish what is authorized" stays in the Handoffs paragraph |
| "external independent review" shortened to "external review" | `code-review` and its `development-completion.md` define the independence requirement |
| "Details: product-rd `...`" shortened to "See `...`" | The file name still resolves uniquely |

Hosts: the recheck reads a Claude Code transcript record. No sampled Codex session showed an equivalent record, and OpenCode exposes no final message at idle, so on those hosts the rule stands alone.
