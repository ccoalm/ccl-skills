# Finding dispositions — 125

Most findings below were acted on and fixed and none was refuted, with two
exceptions stated plainly rather than folded into a blanket claim: the
`auth3 c1 / auth5 r1 / auth6 r1` row is PARTLY fixed and says so, and the
landing chain's third finding is an input defect left open (see the last
table).
Rounds are listed in the order they ran; each fix moved the landing candidate,
which is why the receipts that bind the final tree come from the last chain only.

| Chain / round | Severity | Finding | Disposition |
| --- | --- | --- | --- |
| c1 r1 | P2 | The RED narrative mutated the register-drift anchor, not the live-document trigger; removing the trigger left every locator intact | Split into per-rule ledger rows, each with its own locator and applied mutation |
| c1 r1 | P2 | No durable owner-generalization map in the packet | `evidence/owner-map.md`, ten owners with explicit dispositions (the map carried eight when this round closed and grew to ten later; the count here is the committed one) |
| c1 c1 | P2 | The trigger locator stopped before the obligation; replacing the suffix kept the literal while deleting it. Deleting the register-check bullets also left every locator intact | Anchor extended through the obligation; a third row pins the check step; both bypasses replayed as mutations |
| auth r1 | P2 | No locator covered sentence isolation or the pre-edit comparison the check depends on | Both steps made normative rules with their own rows and locators (rows D and E) |
| auth r1 | P2 | The owner map claimed a `contract-anchors.tsv` change this round does not make, and the plan named the wrong guard | Map and plan corrected to the guard that actually enforces the locators |
| auth c1 | P2 | Locator E pinned only the prohibition; swapping the comparison target to a glossary preserved every literal | Locator E widened to span the comparison target, prohibition and candidate definition |
| auth2 r1 | P2 | The mutation walk was narrated, not reproducible from the packet | Walk captured to `evidence/mutation-walk.txt` with the guard's own output |
| auth2 c1 | P2 | The walk's search strings were abbreviated with ellipses, so they matched nothing literally | Every search and replacement string recorded in full |
| auth2 c1 | P2 | Locator E started after `逐个术语查它`, so narrowing the traversal escaped it | Locator E extended to start at the traversal |
| auth2 c1 | P2 | The plan claimed receipts were committed while the dispositions record said none bound the tree | Plan states receipts are committed only after the binding round |
| auth3 c1 · auth5 r1 · auth6 r1 | P2 | The packet carries the walk's claimed output but not the guard implementation, so its behavior cannot be verified from the packet alone. Two attempts to answer this failed on their own terms: pinning the guard by path and blob does not reach a packet-bounded reviewer, and a risk-owner acceptance written into the candidate cannot assert human authority from inside the thing under review | Partly fixed. `scripts/test_register_firing_path_resolution.sh` now asserts the mutation classes this round relies on, so the packet carries the assertions, their exit codes and their expected diagnostics instead of only a transcript. The guard and the suite's helpers are unchanged and stay outside a diff-scoped packet, so whether those assertions hold is still settled by running the suite, not by reading the packet. Stated this way after the round twice labelled a narrower result as fully fixed |
| auth7 c1 | P2 | The added boundary case used `sed`, which succeeds silently when its target is absent, so fixture drift would let the case pass against unmutated text; and the disposition still called the boundary a checked fact in the packet | Both added cases now assert their target is present before the edit and that the edit changed the file — verified by a probe that breaks the pre-check and makes the case fail with `fixture drift` instead of passing; the wording is narrowed to what the packet actually carries |
| auth9 c1 | P2 | The guard-test row's RED baseline renamed a guard diagnostic, which trips the pre-existing reworded-anchor case and exits before either added case runs, so it attributed nothing to them | Re-attributed on an isolated path: a temporary copy carrying the helpers and only the two added cases. Two guard mutations each flip exactly one of them — whole-line equality flips the boundary case, never-reporting-a-missing-anchor flips the deletion case — with control and restored green. Recorded as a second walk in `mutation-walk.txt`, with the fail-fast reason the shipped suite cannot do per-case attribution |
| auth10 c1 | P2 | The isolated copy held both added cases, and the deletion case runs first, so under the mutant that reds it the boundary case never executed — the transcript could not support 'flips only this one' | Re-run as a 2×3 matrix with one case per probe; every cell, including both no-flip cells, is now an observed run |
| auth11 c1 | P2 | The matrix came from temporary single-case copies whose construction and invocation were absent from the packet, and the shipped suite never emits the token they print | The probe is committed as `evidence/attribution-probe.sh` and reproduces every cell in one command; its verbatim output is pasted into the walk |
| auth12 r1 | **P1** | The committed probe wrote fixed-name files into the caller's live checkout, deleted them on exit whether or not they pre-existed, and restored the guard unconditionally from a start-of-run backup — discarding a concurrent edit, and colliding when two runs overlap | Rewritten to run inside a disposable detached worktree of the commit under test: the caller's checkout is never written, probe names are refused if they already exist, and the guard is only ever mutated inside the throwaway tree. Verified by running it and observing `git status` clean and the temporary worktree removed |
| auth13 r1 | P2 | The probe printed each cell but always exited 0, so a caller checking the exit status would read a matrix that never reproduced as success | Each cell now declares its expected rc and a mismatch exits non-zero with `attribution_probe_failed`; proven by inverting one expectation and observing rc=1 |
| auth3 c1 | P2 | This table stopped at the first chain while the plan and ledger referenced later rounds | This table now covers every round |

## Re-running the walk

The guard is committed in this repository and is unchanged by this round, which
is why a diff-scoped review packet does not carry it:

- path: `skills/skill-extraction-workflow/scripts/register-firing-path-resolution.rb`
- blob at this round's HEAD: `a488c0255a2fb932a9ab74061111f8060f599dc4`
- command: `ruby skills/skill-extraction-workflow/scripts/register-firing-path-resolution.rb <repo-root>`

With the tree restored it prints `register_firing_path_resolution_ok` and exits
0; each mutation in `mutation-walk.txt` makes it exit 1 and name the locator
that stopped resolving.

## Landing chain (chain `ccl125bindb`, candidate frozen at base f1e3892)

Run to satisfy the ledger binder, which had never executed in CI because the
agent-contract coverage gate failed earlier in the same job. Round 1 review
passed with no findings (opencode). Round 2 challenge (codex) returned three P2
findings, all verified against the tree before being acted on.

| Round | Severity | Finding | Disposition |
| --- | --- | --- | --- |
| r2 c1 | P2 | The guarantee "a rule that is deleted or rewritten reds the gate" exceeds what the locators check: changing the check's lead-in to "only run this when the user asks" makes the whole register-drift check optional while all six locators still resolve | Fixed by narrowing the claim, not by adding a seventh anchor -- fourth occurrence of this class, and the class signal is that a substring anchor binds letters. Reproduced first: with that lead-in replaced the gate reports `register_firing_path_resolution_ok (525 locators resolved)`, rc=0. Both the register row and `evidence/AGENTS.md` now say the anchor covers the anchored span only, and that a change to a rule's applicability is a semantic change this gate cannot see |
| r2 c1 | P2 | `evidence/AGENTS.md` said the first walk mutates six locators once each; it is seven mutations over five file locators, and the sixth (command) locator is not mutated there at all. It also said eight owners where `owner-map.md` carries ten, and that eight-owner count had been copied into two register rows | Fixed: the walk description now states seven mutations over five file locators and points at the attribution probe for the sixth; every eight-owner claim corrected to ten |
| r2 c1 | P2 | The blanket "every finding was fixed" line contradicted the `auth3` row, which says partly fixed; and the packet carries neither the guard nor the suite helpers, so the assertions cannot be independently confirmed from the packet alone | Split. The blanket claim is fixed above. The packet half is an INPUT DEFECT, not a candidate defect: the remedy is a widened packet for that lane, and the contract says not to edit the candidate to satisfy it. Left OPEN and carried into the closeout rather than silently closed |

Reviewer-lane failures during this chain, recorded because they cost real time
and are not verdicts: codex returned `codex_quota` twice from its own event
stream (account limit, later lifted); opencode returned `missing_final_text`
twice in challenge mode though it completed the review round; kimi timed out
twice at the 1200-second per-invocation ceiling and once produced a verdict
before finishing the packet. None was treated as approval.

One mechanical trap worth keeping: the binder excludes receipt JSON from the
candidate hash, but `review_gate.sh` invoked with `--base` and no `--paths` does
NOT. Committing round 1's receipt before running round 2 moved the candidate out
from under the pair. Receipts go in after every round of the chain has run.

## Standing boundary

One limitation stands: a substring locator binds letters, not meaning. The
second test case added this round encodes exactly that — text outside the anchor
is gutted and the gate stays green. Say what that is worth without inflating it,
since this round inflated it twice already: the packet carries the assertion, so
a reviewer can read what is claimed; running it, and therefore confirming the
claim, needs repository access. Both added cases now check that their mutation
actually applied, so a fixture that drifts fails the case instead of passing it
against unmutated text. Three challenge rounds each
found a different way to satisfy a locator while gutting what it pins; the
ledger rows say so rather than claiming semantic protection.
