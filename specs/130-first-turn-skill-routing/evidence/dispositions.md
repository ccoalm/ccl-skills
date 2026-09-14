# Review coverage and remaining findings

| Pass | Reviewed commit | Result |
| --- | --- | --- |
| [Independent review](review-1.json) | `22b5a99238c221fc25eebb66c79481e5f74b8b1e` | One P2 |
| [Independent challenge](challenge-1.json) | `22b5a99238c221fc25eebb66c79481e5f74b8b1e` | Two P2 findings; one repeats the review |
| [Delta challenge](delta-1.json) | `af115de0492251c49750d54b8c19f58b7de79c18`, delta from `22b5a99238c221fc25eebb66c79481e5f74b8b1e` | Two P2 findings; no P0/P1 |

All three processes exited 0 with established native skill binding. The receipts retain the complete findings and candidate/packet digests. Only non-executable records in this evidence directory follow the final reviewed commit.

## Initial findings

- Controller lane selection on an ordinary candidate: the delta requires controller-derived extraction ownership. Review and challenge fixtures refuse an ordinary source candidate even when the plan declares that owner. Removing the predicate makes the ownership assertion fail. This resolves the plain-candidate path; the mixed-path limitation below remains open.
- Blocked or waiting handoffs received an extra continuation reminder: the delta recognizes concrete `blocked:` declarations and `none` with a dash explanation. Focused fixtures and the blocked/waiting mutations verify these cases. Contradictory text within such a declaration remains a separate limitation below.

## Open P2 findings

These retain the reviewer's P2 severity and are non-blocking under the review lane. No risk-owner waiver, full semantic verification or new authorization guarantee is claimed.

1. **Mixed candidates can select extraction cadence.** A candidate containing `src/example.py` plus an extraction register path derives extraction ownership. A direct paired probe confirmed that the source path alone does not. Candidate paths establish routing evidence, not trusted caller identity. The separate review and challenge obligation remains explicit in the staged contract and extraction owner; a review receipt never satisfies the separate challenge. Reopen under the code-review owner if a consumer credits an extraction review as completed staged review, or when mixed-candidate eligibility becomes a required mechanical property.
2. **Contradictory text within a status marker is not semantically classified.** A direct probe returned actionable for `run the migration and push`, but non-actionable for `none - run the migration and push` and `blocked: none, I will now run the full suite`. The hook recognizes declarations; it does not determine whether an explanation is truthful or authorized. A separate action marker is still rechecked. Reopen under the product-workflow owner if the reminder must interpret status explanations across languages or such a contradiction causes an observed delivery miss. Permission checks remain separate.

## Recurrence assessment

Keep the candidate-path consistency check and explicit status declarations at their documented scope. Deleting them would restore the ordinary-candidate routing and valid-blocker failures. A stricter path allowlist would reject legitimate package/runtime extraction changes in this candidate. Replacing declaration recognition with an English action/status word list would not validate explanations in other languages or authenticate a blocker. No capability is cut, no mandatory gate is weakened, and no P0/P1 is deferred. The remaining P2 observations stay visible for maintainer review rather than being relabelled as fixed.

## Advisory diagnostic repair

The extraction Stop check now reports oversized history, unreadable history and an unavailable local helper separately, with a short statement that the auxiliary failure does not block the task. Oversized history still discards partial evidence. Five pre-change assertions failed; all 55 host-input/Stop tests passed after the repair. Four diagnostic mutations failed their named assertions after a passing control. The delta challenge reported no diagnostic-specific finding; native UI rendering and installed-plugin activation remain separate from these protocol tests.
