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
source edit on that surface only. The extraction stop backstop keeps its behavior except for the
every-component scope alignment below, and remains the late backstop.

Artifact classification: `gate implementation` — the checkpoint now also fires
for markdown edits on the shared surface (a previously quiet input), and its
reason text changes for shared-surface edits. The number of checkpoint denials
per actor and context does not change.
Risk tags: `shared-gate`. Visible surface: checkpoint reason text.
Security posture: no change to credentials, egress or host permission
enforcement. The checkpoint stays one bounded replan, not approval.

Independent review of the first candidate returned two P2 findings, both
reproduced and fixed here: the marker was probed only at the first `skills/`,
`hooks/` or `scripts/` component, so a checkout under an ancestor carrying one
of those names was never recognised; and the `/.codex/` half of the cache
exclusion had no fixture. The stop backstop carried the same
first-component limitation and is aligned in the same landing.

In scope: `hooks/skill-loading.py`, `hooks/skill-extraction-gate-stop.sh`,
`hooks/test_skill_loading.py`, `hooks/test_host_input.py`,
`skills/skill-extraction-workflow/references/firing-point-placement.md`, one
impact-chain row.

Out of scope: Bash-written edits (unchanged known gap), making the checkpoint
verify that a charter exists, stop backstop behavior beyond its scope guard, and the declared-but-unenforced
gate class (pending for `testing-strategy`).

## Acceptance decision table

| Target path | `skill-extraction-workflow` loaded in context | Checkpoint attempt already spent | Decision |
| --- | --- | --- | --- |
| Source-extension file on the shared surface of a ccl-skills checkout | no | no | deny once; reason names the extraction owner and the charter |
| Markdown file on that shared surface | no | no | deny once; reason names the extraction owner |
| Shared-surface file | yes | no | deny once; generic reason |
| Markdown outside a ccl-skills checkout, including a `skills/` tree without the marker | any | no | no checkpoint; attempt not spent |
| Path under a plugin cache that carries the marker | any | no | no checkpoint; attempt not spent |
| Shared-surface file in a checkout under an ancestor named `skills`, `hooks` or `scripts` | no | no | deny once; reason names the extraction owner |
| Path under a `.codex` install copy carrying the marker | any | no | no checkpoint; attempt not spent |
| Any source edit | any | yes | no checkpoint |

The stop backstop (`hooks/skill-extraction-gate-stop.sh`) blocks the stop once
per session for the same scope, now including the ancestor case.

## Test and register coverage

`hooks/test_skill_loading.py` (registered in `make test`): six cases, one per
new row above; the spent-attempt row is covered by the existing single-attempt
cases. `hooks/test_host_input.py` adds the stop backstop's ancestor case.
Applied mutations on copies, each failing only its owning cases: restrict the
marker probe to the first component; remove the markdown clause, the owner
reason, the plugin-cache disjunct, the `.codex` disjunct, or the loaded-owner
check; and restore the stop backstop's prior scope.

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
