# Disposition — evidence for containment and dispatch is not in the packet

Occurrences: review round 1 finding 2 (P2) and challenge round 1 finding 2 (P2),
chain `122-codex-lane-repair`.

Disposition: **split — input defect in part, fixed in part.** Superseded in
part: after the same shape was raised a third time, the coverage gap below was
closed with a real-packet-read regression rather than dispositioned again.

## Input defect

Both findings note that the packet contains no `audit_codex` implementation and
no negative fixtures, so the reviewer cannot verify the containment claims the
diff relies on. That is a property of the packet, not of the candidate: the
audit lives in `parse_cli_review.py`, which this change does not touch, so a
base-derived diff packet cannot contain it. Per the packet-composition rule in
the `code-review` skill, a finding that the input is insufficient to judge the
change is widened in the packet rather than answered by editing the candidate.
The succession round composes its packet with the audit implementation
included.

## Closed coverage gap

The remaining ask — a regression combining plugin inheritance with an actual
packet read — is now closed by the `packet_read_plugin` behavior, which drives
the real packet server and replays its bytes through the parser while a
plugin-provided server is enabled. It is RED against the pre-change wrapper.
The other half of the ask, a pre-execution denial test for a non-packet tool,
is now covered differently: after the private home landed there is no foreign
tool to deny, and the suite asserts the stronger property instead — that the
home the CLI is handed carries no `mcp_servers` at all. The fake CLI emits a synthetic verdict rather than
driving a real packet read, so the suite proves configuration and preflight
behavior, not end-to-end tool execution. The end-to-end evidence for this round
is therefore the real-CLI run recorded in the round's plan, which is a manual
row rather than a suite assertion.

Closing this gap properly means the fake CLI has to execute the packet server
and replay its bytes, which the existing `packet_read` / `packet_search`
behaviors already do for the happy path; extending them to cover an inherited
server alongside is the follow-up. It is not attempted here because the
containment property those tests would assert is, per the sibling disposition,
an accepted residual rather than an invariant this round establishes.
