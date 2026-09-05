# 117 — Gate rounds partition the same way before and after a merge; chain evidence is read from the landing tree

## Classification

Shared deterministic gate change (product-rd shared-gate class, security-review tag). Two gates that every pull request and every promotion runs:

- `skills/skill-extraction-workflow/scripts/impact-chain-gate.rb` — how history is cut into rounds.
- `skills/skill-extraction-workflow/scripts/review_ledger_binding.py` — where the first-parent chain looks for a round's review evidence.

No skill entrypoint, reference rule, or published artifact content changes. The npm version is unchanged (0.15.0 was moved by the previous round and is not yet published).

## Observed failure

The promotion pull request of the integration branch went red on `repository-gates` and `regression-heavy` for two independent reasons, reproduced locally against the target branch:

1. `impact_chain_firing_path_missing` on a register row from an earlier round whose firing path is the routing-surface `#description` anchor. That anchor is valid only when the owner's whole round diff is the description entry. On the branch, the commit that appended the row changed only the description, so the pull request was green (15 rounds along the branch head). After the merge the whole branch is one first-parent step, the owner's merged diff also carries a body rule and a reference edit from sibling commits, and the anchor is refused. The integration branch's own push build had been red since that merge; nothing about the row had changed.
2. `review_ledger_binding_failed: rejected chain -> round … does not bind at its own base: no accepted review evidence`. A two-file round had merged with the binder red. The chain rebinds each round in a detached checkout of the round's head and looked for evidence only inside that checkout, so no later review of those bytes could ever bind it.

## Measurement

| Shape | Previous gates | This candidate |
| --- | --- | --- |
| Integration head against the target (real promotion) — impact-chain | rc=1, `impact_chain_firing_path_missing` | rc=0 |
| Earlier round's merge against its own base — impact-chain | rc=1 | rc=0 |
| Earlier round's branch head against its own base — impact-chain | rc=0 (15 rounds) | rc=0 (same rounds) |
| Round scoping 8: row appended before the work, branch view vs merged view | branch rc=1, merged rc=0 (disagree) | branch rc=1, merged rc=1 (equal) |
| Round scoping 13: body round then description-only round, merged | merged rc=1 (anchor refused) | rc=0, equal to the branch view |
| Round scoping 14: merge whose tree is not the automatic merge | one boundary, rc=0 | one boundary, rc=0 (not expanded) |
| Verdict differential over every pinned integration point | — | 64 points; 6 newly refused, each named by sha with `impact_chain_gate_missing`; 0 newly accepted |
| Chain: round merged without its ledger, closeout for its exact candidate committed later as its own round | refused (evidence read from the round's checkout) | binds |
| Chain: same, closeout for a different digest | refused | refused |

The six newly refused integration points all predate the CI change that checks out the branch head; three of them are refused on their own branch head by the previous gate as well, and the other three are promotions or syncs whose second parent is the integration branch, where the same shapes sit one merge deeper. They are named individually in the differential with one direction and one diagnostic each.

## Design

### Impact-chain gate: expand merges git can rebuild

Rounds are still cut at the commits that touch the ledger along a first-parent line, and each round still spans from the previous boundary. Walking a line, a two-parent merge is expanded when git itself reproduces it — its tree equals `git merge-tree --write-tree` of its parents, and its second parent is neither already on the base nor already on the line (a sync merge brings nothing that needs a round). Expansion replaces the merge with the rounds of its second parent's line, walked from the fork point (`merge-base` of the parents) with the same rule, recursively, to a bounded depth; direct commits on the outer line before the merge form their own span; the merge itself becomes the next span's base. A merge git cannot rebuild — a hand resolution, a conflict, an octopus — keeps today's single boundary at the merge, so content that came from neither parent is never left in no round. The partition still comes from git alone.

Why this and not the earlier refused attempt ("follow the second parent when the first parent is on the base"): that rule keyed on the base, so it could not tell a pull request's synthetic merge from a landed worktree round, and a fixture pinned the landed-round collapse as load-bearing. The property this round installs is different and checkable: the same history must partition the same way on either side of its merge. The collapse leniency that fixture protected was reachable only after a merge, which is exactly the class the round-scoping design already names as a defect ("a row's verdict must not move after it lands"). Round scoping 8 now asserts the equality on one fixture instead of the collapse.

### Review-ledger binder: chain evidence from the landing tree

`bind_chain` already judges every historical round with the landing tree's controller and validator. It now also enumerates evidence from the landing tree instead of the round's detached checkout. Nothing about what counts as evidence changes: a closeout must be validator-accepted and its `candidate_sha256` must equal the round's packet hash as computed by the landing tree's controller from the round's own bytes at its own base. A ledger committed later for exactly those bytes binds; a ledger for any other digest binds nothing, wherever it sits. Because a direct commit on the integration branch is refused by the chain, a retrospective ledger lands as a round of its own whose only change is receipt-shaped evidence — the binder's existing "no reviewed-path change" outcome.

## Security answers

1. **Does expansion accept anything a pull request could not land?** No. The branch view is what pull-request CI already evaluates; expansion makes the merged view equal to it. Where git cannot rebuild the merge, the previous single-boundary treatment stays, so hand-carried content still sits in the merge's round (and the binder refuses a non-automatic merge on any promotion chain).
2. **Can an author steer the partition?** No more than before: boundaries are ledger commits and merges, and whether a merge is expanded is decided by `merge-tree --write-tree` equality and ancestry — facts of git, not declarations. Depth is bounded and exceeding it fails closed with a named diagnostic.
3. **Can a later commit forge evidence for an old round?** The trust boundary is unchanged: the validator plus the candidate hash. A hand-written JSON that the validator rejects, or that names any other digest, does not bind. The same file committed in the round's own pull request would have been judged by the same two checks.
4. **Does reading evidence from the landing tree weaken the freeze?** No. The round's packet is still frozen from the round's own checkout at its own base with the landing tree's controller; only the enumeration of ledgers moves. The packet excludes are still derived from the round's own added receipts, so a later ledger's absence in the round checkout does not change the round's hash.

### Fail-closed edges of the expansion

- The sync test is made against the line being walked, not only the outer base: a merge whose second parent is below the current line's base is a sync of what that line was cut from (the target advancing under a branch). Judging it against the outer base alone expanded such a sync during promotion and stranded the branch's earlier work in a rowless span; round scoping 18 pins the branch and promotion verdicts equal on that shape.
- The fork-point lookup fails closed like every other git read: an errored `merge-base` would otherwise read as "no fork point", skip the expansion and hand the merge the collapsed span. Exit 1 (no common ancestor) means there is nothing to expand from; any other failure aborts with `impact_chain_git_failed`. Rounds scoping 16 and 17 inject a failing `merge-tree` and a failing fork lookup through a `git` shim and assert the abort; round scoping 15 nests nine automatic merges and asserts `impact_chain_round_walk_too_deep`.

## Executed evidence (on the committed candidate)

Output lines are quoted from the runs on this candidate; the reviewer packet excludes receipt-shaped JSON by the binder's own rule, so what follows is the artifact record for the checks the packet cannot show.

- `test_check_ccl_impact_chain_refscripts.sh` → `test_check_ccl_impact_chain_refscripts: ok` with 97 standalone gate runs (round scoping 8 rewritten as an equality; 13–18 added). On the previous gate the same suite stops at round scoping 8 with `FAIL: expected rc=1 got rc=0 (the merge of that branch is judged exactly as the branch was)`.
- `test_impact_chain_gate_verdict_differential.sh` → `impact_chain_gate_verdict_differential: ok (64 integration points, 10 named expected divergences, 2 replay cases incl. one baseline-red; no unexpected verdict change in either direction)`. Before the six pre-branch-head points were named: `6/64 integration points and 0 replay cases changed verdict unexpectedly`, all `newly refused` with `impact_chain_gate_missing`; three of the six (`b9de13869`, `8cea35e6d`, `c0561c74e`) are rc=1 with the same diagnostic on their own branch head under the previous gate.
- `test_impact_chain_round_attribution.sh` → `ok (all forms closed)`; `test_impact_chain_source_refuted.sh` → green; `test_impact_chain_self_adjudication.sh` → `legs_failed=0`; `test_impact_chain_gate_dateless_host.sh` → `ok`.
- Real promotion shape with this gate from the integration checkout: base `origin/main` rc=0, base `dfbba83` rc=0, base `4d7f5c2` rc=0; with the previous gate base `origin/main` rc=1 (`impact_chain_firing_path_missing`, `incomplete: product-rd-workflow/SKILL.md`), and the earlier round's merge at its own base rc=1 while its branch head at the same base is rc=0 with 15 ledger rounds.
- `test_review_ledger_binding.sh` → `test_review_ledger_binding: ok`, including `a later closeout for a different digest does not bind the unbound round`, `a later closeout for the right digest that the validator rejects does not bind the unbound round, and is listed as rejected`, `an uncommitted closeout in the landing tree is refused before any round is bound`, `a validator-accepted closeout for the round's own candidate, committed on the integration branch after the merge, binds it through the chain`, and `the round's candidate hash is unchanged by evidence committed later in the landing tree`. On the previous binder the "binds it through the chain" case is the one failing case.
- Retrospective review of the two-file round (`evidence/retro-round/`): `--print-candidate` from a detached checkout of its head at its own base prints `95fc8543870e35c8f8adba3adc3c309ec84831337571f0a4bb5a0c7b9d159ea8` with this binder; review and challenge receipts (`status: passed`, 0 findings each) and the completion receipt carry that hash; `validate_extraction_review_state.py closeout.json` → `extraction_review_state_ok: closeout_state=ready_for_human_decision finding_classes=0 base_changes=0`; `bind_candidate` on that round's detached checkout with this tree as `tools_root` and `evidence_tree` → the proof line names the retro-round closeout as binding the landing candidate `95fc8543870e...`.
- `CCL_SKILL_BASE_REF=origin/dev make test-repo-gates` → `ccl_skill_check_clean_ok`, `r0_status=private-ok`, `spec_reference_check_ok`, `release_version_ok`, `entrypoint_word_budget_blocking_ok`, Python suites `PASS=125 FAIL=0` and `PASS=20 FAIL=0`.
- `make test-regressions-fast` → `regression_fast_lane_ok: 44 suites, jobs=8`; `test_check_ccl_regressions.sh --heavy-only` → `regression_heavy_lane_ok: 10 suites, jobs=8`.

## Review chain record

Extraction lane: one review, one challenge on the same frozen candidate, then one succession challenge bound to the landing candidate. The first succession ran on an intermediate candidate that then moved once more (a plan citation that tripped the spec-reference gate, and tighter shim assertions plus pinned bases in the fixtures it had questioned); the lane's closeout can carry exactly one succession and that round must bind the landing candidate, so the maintainer authorized one further succession on the landing candidate. The intermediate succession's receipt is retained under `evidence/retained/` and is not counted; its two findings are addressed in the landing candidate (assertion precision, pinned bases) and in the packet-excludes-receipts class recorded in the closeout.

## Out of scope

- Any rewrite of integration or target history. Three rewrite shapes were tested and are closed by the binder's own invariants (automatic-merge tree, per-round packets, base attestations).
- The CI checkout ref binding stays: the branch head is still what the ledger binder freezes and what lands.
- Merge-queue aggregation remains unsolved, as before.
