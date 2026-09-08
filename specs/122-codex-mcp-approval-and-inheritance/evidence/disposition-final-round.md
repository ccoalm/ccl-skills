# Disposition — final review/challenge round

Chain `122-ship-4`, candidate `b8141a87`, review and challenge on the same
frozen packet (diff plus `audit_codex` and the packet server this change
auto-approves). Receipts alongside this file.

## Review

**R-F1 — a replaced credential link discards a refreshed token.** Recurrence of
an already-recorded decision; see `disposition-credential-link-replacement.md`.
Accepted, fail-closed retained. It will be raised again by any future review:
the review gate's completion checkpoint accepts only `source_refuted`
dispositions, so an accepted tradeoff has no machine-readable closure there.

**R-F2 — the fake CLI cannot prove real-CLI behavior.** Input boundary, not a
candidate defect. A packet-bounded reviewer sees a diff; no artifact placed in
a diff can prove that a live invocation happened, because the artifact is text
the author supplied. The packet was widened twice in response to this class
(the audit implementation, then the packet server), and the real-CLI
measurements are recorded in `real-cli-observations.md` rather than left in
prose. The residue — that those measurements are attested rather than replayed
— is a property of packet-bounded review and is stated in that file.

## Challenge

**C-C1 — `model_providers` is copied as a whole subtree.** Valid narrowing of
the allowlist claim: the carry-over is described as model identity, but this
one key's value is unbounded, and the packet supplies no provider loader
proving the subtree is passive. Not changed in this round. The subtree is
copied from the user's own configuration into a private home that this run
deletes, so it grants a provider definition the host already had; it does not
introduce a server, tool, hook, or skill. Recorded as the first follow-up
below, because tightening it correctly means deciding what a custom-provider
host should do when its provider cannot be carried — fail closed and cascade,
or lose the provider — and that decision deserves its own round rather than a
late edit here.

**C-C2 — changing `CODEX_HOME` does not by itself prove every discovery source
is excluded.** Correct as stated. What is verified: no MCP server is reachable
(measured), hooks are disabled through a capability probe that fails closed,
the shell tool is disabled the same way, and the working directory is an empty
run-scoped workspace. What is not verified: whether the CLI consults any
discovery root outside `CODEX_HOME` and the working directory for skills. That
is the second follow-up.

**C-C3 — the outcome clause demands a terminal result unconditionally.** Real,
and the second occurrence of over-broad absolutes in this round's own
continuation-gate text (the first was polling a persistent process forever).
Not changed here: the surrounding stop-condition list already permits a
`blocked:` outcome for a required environment unavailable after remediation,
so an agent whose suite hangs and whose handle is lost is not actually trapped.
The clause should still name that case explicitly. Third follow-up.

## Follow-ups

1. Narrow or drop the `model_providers` carry-over, with an explicit decision
   for custom-provider hosts.
2. Establish whether skill or hook discovery reaches outside `CODEX_HOME` and
   the working directory; extend the private home or the containment claim
   accordingly.
3. Name the unobtainable-terminal-result case in the outcome clause.
4. Closed in this round, but not the way it was first framed. `--mode complete`
   refusing `accepted_tradeoff` is a deliberate, test-protected decision, not a
   contradiction: the gate binds structure and provenance and cannot tell a
   human acceptance from an agent labelling its own findings accepted. A
   widening was drafted and reverted when `test_unresolved_or_accepted_risk_
   cannot_complete` refused it — the guard worked. What was actually wrong is
   the contract text, which read as though `complete` were the general closure
   path; it now states that a chain whose findings are accepted, out of scope,
   or input defects ends at its `findings` result with per-occurrence
   dispositions and is not thereby unfinished. Two mechanics discovered only by
   experiment are recorded with it: `--stage`/`--risk-tag` must be passed to
   `complete` rather than omitted, and a round editing the review harness
   cannot bind its own earlier rounds because the controller hash covers those
   scripts.
