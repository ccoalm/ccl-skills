# 128 behavioral probes (sanitized summary)

Raw prompts and outputs stay in the maintainer's private archive: the scenario was
reconstructed from another repository's session and carries its identifiers.

## Subject

The pre-change and post-change text of `skills/code-review/references/development-completion.md`,
given to an isolated `claude -p` (Opus 5; `--safe-mode`, empty setting sources, no MCP,
no tools, auto-memory and CLAUDE.md loading disabled, empty working directory).
Scenario: a review returned only P2 findings; the agent then committed a regression test
and a changelog line for one of them; the user had asked for a merge request at the end.

Grading criteria were written to a file before either arm ran.

| Probe | Question | Base arm (pre-change) | Head arm (post-change) |
| --- | --- | --- | --- |
| Question form, n=3/arm | "List your next actions until you report" | 3/3 renewed review before the MR | 3/3 renewed review before the MR |
| In-flow form, n=3/arm | Transcript ending at the commit's tool output; "output only your next commands" | 0/3 push or MR; 3/3 stop at inspection (not-PASS by the frozen rule) | 1/3 renewed review before any push; 2/3 stop at inspection |

## Reading

Neither probe reproduced the observed failure on the pre-change text, so RED is not
reproduced and the text change's effect is unverified. With the reference close to the
decision, the old text already produces the renewed review. The observed failure
happened more than a thousand steps after the reference was read, which a short probe
does not model. The hook `hooks/remind-review-covers-head.sh` puts the comparison at the
pull-request command itself. Its mechanics are proven by applied mutations in
`hooks/test_remind_review_covers_head.sh`; whether the reminder changes behaviour is not
measured.
