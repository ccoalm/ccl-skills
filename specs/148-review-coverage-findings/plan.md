# Review coverage with open findings

## Outcome and scope

The pull-request coverage reminder treats a local review receipt as covering
HEAD only when that review passed. A receipt that records findings on the
current HEAD now produces a reminder that names the receipt path and the
recorded status, instead of staying silent. A completion checkpoint that
disposes every finding records a passed receipt, so a correctly closed chain
returns to silence.

Before this change the reminder read the receipt's `status` only for display.
A review that returned findings, covered HEAD and saw a clean worktree was
indistinguishable from a passed review, so a pull request could be opened,
readied or merged with findings outstanding and no reminder.

Artifact classification: `gate implementation` — failure semantics of an
existing reminder change (a previously quiet input now reminds), and the
review controller records one additional receipt on an existing success path.
No verdict, budget, chain or authorization logic changes.
Risk tags: `shared-gate`. Visible surface: reminder text only.
Security posture: no change to credentials, provider access, egress or host
permission enforcement. The reminder stays non-blocking; it never denies or
asks, for the reason recorded in the hook header.

In scope:

- `hooks/remind-review-covers-head.sh`: the quiet branches require
  `status == "passed"`; any other recorded status on a covered HEAD reminds;
  every reminder names the receipt path it checked.
- `skills/code-review/scripts/review_gate.py`: `complete` joins the modes that
  sample the review anchor (same whole-worktree `--base`, no `--paths`
  condition), and a successful completion records the receipt.
- `hooks/test_remind_review_covers_head.sh`: the receipt helper takes a
  status; coverage-semantics cases use `passed`; new cases pin findings and
  unknown status.
- Controller regression for the completion receipt.

Out of scope: the cleanup reminder's masking of merge commands quoted inside
other command arguments (separate hook, declared out-of-scope spelling class);
making any reminder blocking.

## Acceptance decision table

| Receipt | HEAD vs receipt | Worktree clean at review | Command moves HEAD first | Decision |
| --- | --- | --- | --- | --- |
| absent or linked | — | — | — | remind: no conclusive review; names receipt path |
| `passed` | same commit | true | no | quiet |
| `passed` | same tree, different commit | true | no | quiet |
| `findings` | same commit | true | no | remind: findings outstanding; names status and path |
| `findings` | same tree, different commit | true | no | remind: findings outstanding |
| unknown or missing status | same commit | true | no | remind: status not passed |
| `passed` | same commit | false | no | remind: dirty worktree at review |
| any | ancestor, commits since | any | no | remind: unreviewed commits |
| any | not in history | any | no | remind: reviewed commit gone |
| any | any | any | yes | remind: HEAD moves before the PR operation |

Controller:

| Completion outcome | Anchor available | Receipt after run |
| --- | --- | --- |
| success, `--base` whole worktree | yes | `status: passed`, `mode: complete`, current HEAD |
| success, `--paths` or no `--base` | no | unchanged |
| failure (findings unresolved) | any | unchanged |

## Test and register coverage

- `hooks/test_remind_review_covers_head.sh` (registered in `make test`):
  one probe per hook row above, including the previously pinned quiet cases
  rewritten to `passed` and new `findings` / unknown-status rows; the
  reminder text assertion checks the receipt path.
- Mutation: removing the status predicate turns the findings rows red.
- Controller: completion-receipt regression beside the existing receipt cases in `skills/code-review/scripts/test_review_gate.sh`.

## Verification

Authoritative: `make test`; outside it, `bash skills/skill-extraction-workflow/scripts/test_check_ccl_regressions.sh --heavy-only`
and `python3 scripts/check-public-sanitization.py .`. Baseline recorded before
implementation.

## Status sync

No status source or version field changes in this slice.

## Review gate

`code-review` review then challenge on the whole-worktree candidate, risk tag
`shared-gate`, per `references/staged-review-contract.md`; findings verified
and dispositioned before the pull request.
