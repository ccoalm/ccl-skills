# Extraction owner at the first shared-skill edit

Written after the hook commit `5c38ec4`, not before it. The extraction charter
for this round was recorded before any source read, in per-host scratch; this
repository plan was not, and the closeout records that gap.

## Outcome and scope

The default source-edit checkpoint already denies the first source edit once
per actor and context so the agent can load its owner. When the edit targets a
ccl-skills checkout's `skills/`, `hooks/` or root `scripts/` surface and
`skill-extraction-workflow` is not loaded in the current context, the reason
now names that owner and the charter-before-editing step. Markdown counts as a
source edit on that surface only. The extraction stop backstop is unchanged and
remains the late backstop.

Artifact classification: `gate implementation` — the checkpoint now also fires
for markdown edits on the shared surface (a previously quiet input), and its
reason text changes for shared-surface edits. The number of checkpoint denials
per actor and context does not change.
Risk tags: `shared-gate`. Visible surface: checkpoint reason text.
Security posture: no change to credentials, egress or host permission
enforcement. The checkpoint stays one bounded replan, not approval.

In scope: `hooks/skill-loading.py`, `hooks/test_skill_loading.py`,
`skills/skill-extraction-workflow/references/firing-point-placement.md`, one
impact-chain row.

Out of scope: Bash-written edits (unchanged known gap), making the checkpoint
verify that a charter exists, the stop backstop, and the declared-but-unenforced
gate class (pending for `testing-strategy`).

## Acceptance decision table

| Target path | `skill-extraction-workflow` loaded in context | Checkpoint attempt already spent | Decision |
| --- | --- | --- | --- |
| Source-extension file on the shared surface of a ccl-skills checkout | no | no | deny once; reason names the extraction owner and the charter |
| Markdown file on that shared surface | no | no | deny once; reason names the extraction owner |
| Shared-surface file | yes | no | deny once; generic reason |
| Markdown outside a ccl-skills checkout, including a `skills/` tree without the marker | any | no | no checkpoint; attempt not spent |
| Path under a plugin cache that carries the marker | any | no | no checkpoint; attempt not spent |
| Any source edit | any | yes | no checkpoint |

## Test and register coverage

`hooks/test_skill_loading.py` (registered in `make test`): four cases, one per
new row above; the last row is covered by the existing single-attempt cases.
Applied mutations on copies: removing the markdown clause, the owner reason, the
cache exclusion, or the loaded-owner check each fails only its owning case.

## Verification

`make test`, `test_check_ccl_regressions.sh --heavy-only`,
`check-public-sanitization.py`, `git diff --check`, `check-ccl-skills.sh` with a
base ref.

## Status sync

No status source or version field changes.

## Review gate

One review and one challenge through
`skills/skill-extraction-workflow/scripts/extraction_review_gate.sh`, risk tag
`shared-gate`; findings verified and dispositioned before the pull request.
