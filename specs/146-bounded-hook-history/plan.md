# Bounded Stop checks

Status: implemented; verification and release in progress. Artifact: gate implementation.

## Outcome and scope

Stop checks should avoid repeating an unchanged incomplete-check notice and
recover useful evidence after a long conversation is compacted. Publish the
repair as the next available npm patch release through the existing workflow.

The affected members are the extraction and handoff Stop hooks on repeated
arrivals, including native Claude and Codex transcript shapes. The shipped hook
configuration enumerates these callers. The whole-session transcript command
and all permission, edit-isolation and delegation gates retain their contracts.
No workflow policy, public hook payload schema or host configuration changes.

## Design

- Reject files already larger than the whole-session byte budget before parsing.
- Keep the whole-session audit strict: truncated evidence never becomes a pass.
- On overflow, the Stop callers may inspect the existing bounded current-context
  reader. Only positive evidence from a complete current context can discharge
  extraction invocation or establish handoff eligibility. Absence in that
  context cannot establish absence in the whole session and stays unknown.
- Deduplicate each incomplete-check notice for a session, actor and transcript
  identity using the existing owned-directory and atomic attempt mechanism.
  Notice state cannot skip scanning, establish verification or authorize work.
  A different transcript identity or another session permits a fresh notice.
- Missing identity or unavailable/unsafe state falls back to the truthful notice.
  Do not echo transcript text, identities or filesystem paths in notices.

Full-history summary caching is excluded: it would require a new persistent
evidence format and invalidation protocol. Tail-only absence checks are rejected
because they could turn omitted invocation evidence into a false violation.

File identity uses the canonical path, device and inode. Reusing the same inode
at the same path can retain notice suppression; scans still run. Modification
and change times are excluded because ordinary transcript appends change them
and would restore the repeated notices this patch removes.

Extraction preserves the existing invocation contract: a native Claude Skill
request counts as invocation, including a pending or failed result. Codex reads
require a successful, complete source result. Handoff eligibility requires a
completed owner or the existing handoff evidence; a pending request is insufficient.

## Acceptance and test register

All rows are in scope. Owner: testing-strategy for coverage; hooks for behavior.
Inputs below select one observable outcome rather than an inferred success.

| ID | Input | Expected outcome | Layer / command | Baseline |
| --- | --- | --- | --- | --- |
| H1 | Oversized history, same session/actor/file, repeated Stop | First incomplete notice only; later empty output, no block | subprocess / `python3 hooks/test_host_input.py` | fail |
| H2 | Overflow followed by native compaction and proven extraction invocation | Extraction Stop quiet; strict transcript audit still incomplete | subprocess / same | fail |
| H3 | Overflow followed by native compaction and completed delivery owner or prior handoff | Handoff repair reminder, preserving stop-loop guard | subprocess / same | fail |
| H4 | Overflow without a complete current context or with only a pending/failed read | Unknown notice; no inferred pass or missing-owner block | subprocess / same | pass-existing |
| H5 | New session, actor or different transcript file identity after a notice | Independent first notice | subprocess / same | pass-existing |
| H6 | Notice state exists, then valid blocking evidence arrives | Actual check still runs and blocks where required | subprocess / same | pass-existing |
| H7 | Missing identity, unsafe state or absent optional state helper | Truthful fail-open notice, no arbitrary writes | subprocess / same | pass-existing |
| H8 | Whole-session byte budget exceeded | Reject before any record is parsed | unit / same | fail |
| H9 | Packaged hooks | Same behavior from built assets; host lifecycle smoke succeeds | package / `make npm-publish-dry`, `make npm-host-smoke` | pending |
| H10 | Reviewed patch release | Tag resolves to default-branch commit; registry version, provenance and installed bytes agree | release workflow and registry readback | pending |

The outcome classes are positive (H2/H3), negative (H4/H7), recovered (H5/H6)
and ambiguous success (H1/H4/H8). The open-ended arrival population is handled
on every Stop: notification suppression never suppresses subsequent checks.
Unverifiable full histories remain explicitly unknown; this repair does not
claim an unbounded whole-session audit.

## Entry and risk record

- Baseline: current development branch; independent `fix/bounded-hook-history`
  worktree, verified by worktree-status before edits.
- Implementation owner: skill-extraction-workflow; shared hook behavior is
  outside the product-stack owner-load requirement.
- Risk tags: shared-gate, release-ops. Required: regression RED, focused tests,
  full repository and package checks, independent review and challenge.
- Security posture: existing local-owned state protections are reused;
  notification markers carry no permission or verification authority.
- Safety inputs: session/actor/path are caller-controlled; forged values can
  affect advisory deduplication only. Trusted root is the installed helper plus
  OS ownership/no-follow checks. H7 covers a symlinked state destination.
- Visible UI: no rendered layout or control changes; the host renders the same
  JSON notice protocol. Output eligibility is verified at the subprocess layer.
- Delegation: one coupled implementation slice; no independent worker dispatch.
- Tests: unit and subprocess contract layers run; packaged host smoke runs;
  browser/device/manual UI layers are not applicable to these command hooks.
- Status sync: this plan and its eventual verification record. The authoritative
  plan-reference verifier is `python3 scripts/check-spec-references.py .`.
- Independent review/challenge will assess the original acceptance points,
  positive-evidence boundary, false positives/negatives and current diff.

## Structural minimality

| Concept | Current need | Simpler alternative / decision |
| --- | --- | --- |
| Notice attempt marker | H1/H5, repeated notices across hook processes | Reuse existing secure state helper; no new state service or evidence cache |
| Current-context fallback | H2/H3 | Reuse existing reader; do not implement another transcript parser |

## Delivery sequence

1. Write and run H1–H8 regression cases RED on the baseline.
2. Implement the bounded fallback and notice deduplication; run focused checks.
3. Select the patch version, run full/package checks and independent review.
4. Merge through the development and default-branch PR paths, publish the tag,
   verify npm and installed contents, then clean up this temporary worktree.
