# Review lane status and finding dispositions — round 151

## Lanes

The Claude lane is skipped at preflight as the implementer's own model family.
Codex and Kimi both reported `quota` for roughly two hours; the Codex CLI names
its own reset time, and the lane produced conclusive results immediately after
it. The OpenCode lane returned two conclusive `passed` reviews on an earlier
candidate and then repeatedly returned `missing_final_text`; that cause was not
isolated and is recorded as unresolved rather than attributed to a component.
Kimi's own unavailability was reported through the classification this round
adds.

Recorded passes: `round1-review.json` (review) and `round2-challenge.json`
(challenge), both schema-3 controller envelopes bound to the same candidate.

## Findings and dispositions

The review returned four and the challenge three, overlapping on two.

| Finding | Disposition |
| --- | --- |
| A digit boundary keeps `4290` out but still reads an offset of exactly `429` as a status code, so `byte offset 429` classified as quota (both lanes) | Fixed. A number now classifies only with status context — a status word before it or its reason phrase after — and wording carries the rest. `capability_exact_offset` fails on the prior predicate; `capability_http_quota` and `capability_forbidden` hold the two forms that must keep classifying. |
| `403 rate limit exceeded` matched the quota pattern but the envelope exception sent it to the auth class (challenge) | Fixed. Rate-limit exhaustion joins the wording that wins inside an auth envelope, and one auth predicate now serves both the auth branch and that envelope test so they cannot drift. `capability_rate_limit_403` fails on the prior code. |
| The strict-subset claim cannot be verified from the packet: the fallback case asserted watcher absence and marker count, never compared the two configs (both lanes) | Fixed. The stub keeps every config it validated and the case asserts the retry's config equals the first one with only the watcher table removed. |
| The fallback's safety rests on the override working on a build that rejects the table, and the evidence covers one installed build (review) | Accepted as scoped, no code change. The claim is written with its scope in the plan and is not asserted for every release. The reason it is safe without that evidence is separate: where neither the table nor the override is honoured, the watcher runs — which is exactly what the default branch ships today, so the degraded path is not a regression, and the isolation boundary (the `[tools]` allowlist plus the tool_use scan) is untouched either way. |
| This status note excluded client, wrapper and parser causes for the OpenCode failure from a trivial-prompt success, then prescribed provider recovery as the unblock (review) | Fixed in this file. The diagnosis is withdrawn; the cause is recorded as unresolved. |
