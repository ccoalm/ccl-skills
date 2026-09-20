# Review lane status and finding dispositions — round 151

## Lanes

The Claude lane is skipped at preflight as the implementer's own model family.
Codex and Kimi both reported exhaustion for roughly two hours; the Codex CLI
names its own reset time and the lane produced conclusive results immediately
after it, so every review and challenge recorded here ran through Codex. The
OpenCode lane returned two conclusive `passed` reviews on an early candidate and
then repeatedly returned `missing_final_text`; that cause was not isolated and
is recorded as unresolved rather than attributed to a component.

Five review rounds and five challenge rounds ran across four candidates. The
recorded pair is the last one, in `round1-review.json` and
`round2-challenge.json`; both lanes returned the same two findings, each already
dispositioned below, and no new defect class — which is the convergence this
round stops on.

## Findings and dispositions

### The classification thread, and why it ended in a deletion

Rounds one through four each broke the failed-probe classifier on a message the
previous fix had not considered:

| Round | Message that landed in the wrong class |
| --- | --- |
| 1 | `byte offset 429` read as quota — the digit boundary excluded `4290` but not an offset that is exactly `429` |
| 2 | `403 rate limit exceeded` fell through to auth, because rate-limit exhaustion was not in the wording that wins inside an auth envelope |
| 3 | `decode offset 429` read as quota — the required status word matched `code` inside `decode` |
| 4 | `403 IP not whitelisted … quota` read as quota (`hit` inside `whitelisted`), while `credits are exhausted` was missed entirely |

Each round's fix was correct about the case it was shown and wrong about the
next one. That is a predicate over a vocabulary this control does not own, which
`skills/code-review/scripts/AGENTS.md` already names as a failure class, and
four same-class rounds is the cue to ask whether the capability should exist.

Disposition: **withdrawn.** Every non-`EMFILE` probe failure returns to the one
capability reason, which is what the default branch ships. Nothing about the
gate changes — all the reasons involved were `die_inconclusive` and
cascade-eligible, so the split only ever decided an operator hint, and a wrong
hint is worse than none. The thirteen message fixtures stay, asserting the
single class, so the predicate cannot come back silently. The replacement, if
one is wanted, is a classifier over the structured error the probe already
streams, against a real sample — not a fifth regex.

### Findings kept open by evidence scope

| Finding | Disposition |
| --- | --- |
| The fallback's safety rests on the override working on a build that rejects the table, and the evidence covers one installed build | Accepted as scoped, no code change. The claim is written with its scope in the plan and is not asserted for every release. Where neither the table nor the override is honoured the watcher runs — which is what the default branch ships today, so the degraded path is not a regression, and the isolation boundary (the `[tools]` allowlist plus the tool_use scan) is untouched either way. |
| The strict-subset claim cannot be fully verified from the packet, which omits the generator's filtering code | Partly fixed, partly accepted. The fallback case now asserts the retry's config equals the first one with only the watcher table removed, which is the claim itself rather than a proxy; that the generator's own filtering is outside the diff is a property of the packet, not of the change. |
| An earlier version of this file excluded client, wrapper and parser causes for the OpenCode failure from a trivial-prompt success, then prescribed provider recovery as the unblock | Fixed here. The diagnosis is withdrawn; the cause is recorded as unresolved. |
