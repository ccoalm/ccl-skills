# Make the design brief name its visual-system source before the first edit

## Change

A design brief for a new screen could cite only a behavior plan as its design source, classify the whole visual layer as design freedom, and still be complete. The screen was then built from generic library components, and its renders were judged on their own, in one theme. The design skill already says a component library is rendering vocabulary and not a design system; nothing made that rule apply when the brief was written or when the renders were judged.

This round puts the rule on three steps every visible slice already passes through:

- A new brief field, `visual_source`, lists visual-system sources apart from behavior sources, after a search that does not end at the first source found.
- A second new field, `visual_conformance`, maps each changed visible treatment to the source rule it follows. A treatment may be design freedom only when every source found is listed, inspected and silent. The brief is incomplete without either field, so Phase 0 and the client entry cannot start.
- For a `visual_conformance` criterion, the Phase 0 oracle is a comparison with the reference surface in every shipped theme. A candidate capture judged alone does not count.

## Charter

| Field | Decision |
| --- | --- |
| Purpose | Prevent a visible slice from shipping against the product's visual system because the brief never named that system's source. |
| Scope | `product-ui-ux-design` (delivery contract, entrypoint), `testing-strategy` (Phase 0 rule), the contract's regression suite. The four client owners are checked and left unchanged. No product repository changes. Not an iterative program; no watermark. |
| Depth | Targeted check: one recorded correction, the current owner text, and the contract suite. |
| Result classification | Failure/correction. A user rejected a delivered screen as inconsistent with the product's design while the design skill was loaded. |
| Matching analysis | See "Root cause" below. |
| Failure mode | A weak fix would add another paragraph of prose to the design skill. The existing prose rule was loaded and did not apply, so more prose would not apply either. |
| Lifecycle impact | Design (brief), implementation (client entry consumes the brief's criteria), testing (Phase 0 oracle, Phase 1 results), acceptance (verdict per criterion). Product intent, launch and iteration are unaffected. |
| Evidence plan | Produced artifacts: the private root-cause record of the correction (private archive, alias `design-visual-source-miss`). Current owner text: the delivery contract, the design entrypoint, the four client entrypoints, the testing matrices. The contract regression suite. No external best-practice claim is made, so no external source class is needed. |
| Completion standard | The contract suite fails without each new obligation and passes with it; a paired run of the failure scenario on base and candidate; the full lane; one review and one challenge. |

## Root cause

| Factor | Class | If removed, would the failure still happen? |
| --- | --- | --- |
| `design_source` accepts any source, so a behavior plan alone fills it | Missing mechanical control | No. A required `visual_source` field forces the search that finds the visual direction. |
| The entrypoint's `design-freedom` class lists "visual language" and "component treatment" without a condition | Stale rule text | Likely yes on its own, but it is the text that made the classification look correct. |
| The library-is-vocabulary rule sits in the entrypoint's opening prose and is not attached to any step | Missing firing point | Yes. It stays as rationale. |
| Renders were judged alone and in one theme | Missing feedback | The defect would have been made, and then caught before handoff. |
| A new screen's author verdict is `candidate` until the user decides | Secondary safeguard | It worked as designed: the user rejected the screen. It fires after the work is done. |

"The author should have read the visual direction" is rejected as a cause: no step asked for it.

## Proposals and dispositions

| Proposal | Disposition |
| --- | --- |
| 1. Delivery contract: separate visual sources, a conformance table before the first edit, side-by-side evidence in the primary theme | Landed in `skills/product-ui-ux-design/references/delivery-contract.md`: the `visual_source` and `visual_conformance` rows, the brief-completeness rule, and the Phase 0 `oracle` row. The entrypoint gains one sentence after its `design-freedom` class and one after its pre-edit sentence. The visual source is its own field and not part of `design_source`, because an earlier obligation ledger cites the `design_source` cell verbatim. |
| 2. The app client entry quotes the conformance rows it implements | Not landed as a new field. Each sourced row is a blocking criterion, and all four client owners already map the brief's criteria to code before their first edit, so the rows reach the implementer through an existing step. A new `client_entry` field would change four entrypoints and the suite's pinned oracle for a second copy of that step. |
| 3. Testing Phase 0: side by side with the reference surface, both themes | Landed. The oracle is defined once in the contract's Phase 0 table, and `skills/testing-strategy/references/client-runtime-test-matrices.md` treats Phase 0 as incomplete without it. "Both themes" is written as every shipped theme. |
| 4. Record the failure class in the extraction workflow | Landed as ledger rows and suite cases, with no new workflow rule. The workflow already requires a firing mechanism when an existing rule did not apply; this round is an application of that rule. |

## Target-output map

| Target | Direction | Status | Diff or reason |
| --- | --- | --- | --- |
| `product-ui-ux-design` | owner | updated | `references/delivery-contract.md`, `SKILL.md` |
| `testing-strategy` | downstream | updated | `references/client-runtime-test-matrices.md` |
| `skill-extraction-workflow` | self | updated | `scripts/test_uiux_delivery_contract.sh`, `references/source-register.md` |
| `app-cross-platform-dev` | downstream | unchanged | Its pre-edit step consumes the full brief and maps its criteria; sourced conformance rows are criteria. |
| `web-react-dev` | sibling | unchanged | Same step, same wording as the app owner. |
| `miniapp-product-dev` | sibling | unchanged | Same step, same wording. |
| `terminal-cli-dev` | sibling | unchanged | Same step, same wording. A terminal surface's color, border and emphasis treatments fall under the same rows. |
| `product-rd-workflow` | coordinator | unchanged | It routes visible work to the delivery contract and copies none of its fields. |
| `design:*` skills (installed external pack) | external | reference-only | They critique and hand off designs; none owns this repository's delivery record. |
| `eval/paired-tasks` | measurement | unchanged | A task for the failure scenario was written and run twice; both runs passed on base and candidate alike, so it is not added to the bank. See "Verification". |
| `code-review` | gate | unchanged | The read bound is handled by the change this branch is stacked on. See "Review controller read bound". |

Sibling check: the four client entrypoints carry the same two pre-edit sentences (load the contract and consume the brief; add the canonical `client_entry`). The gap was in the brief they all consume, so one change to the brief covers the four stacks.

## Review controller read bound

The round's ledger rows take `skills/skill-extraction-workflow/references/source-register.md` past 1,048,576 bytes, the bound under which the review controller read each file of a selected skill. On the base commit the register was 350 bytes under it, so the controller refused this round's first review pass before choosing a reviewer.

A separate change removes that per-file bound (`specs/review-skill-file-bound/plan.md`). This branch is stacked on it and changes nothing in the controller. The first three passes below ran with a local one-constant workaround that is no longer in the branch.

## Verification

### The failure scenario against the new text

The scenario: a new screen and its entry row; the brief cites the behavior plan as `design_source`, calls the visual layer design freedom, and the repository holds a visual direction document and an accepted screen.

| Step | Base text | New text |
| --- | --- | --- |
| Name the sources | The behavior plan fills `design_source`. | `visual_source` is a separate field that a behavior plan cannot fill. The search covers the visual direction, design files, tokens and accepted surfaces, and does not end at the first source found, so the visual direction document is listed. |
| Classify the outlined card and the bold button | `design-freedom`, with no condition. | Each needs a `visual_conformance` row. `design-freedom` is valid only if every listed source is silent on it; the visual direction is not silent, so the rows cite its rules and become blocking criteria. A library default is not a source rule. |
| Start Phase 0 and the client entry | Both start. | Both wait until `visual_source` and the rows exist. |
| Judge the renders | Captures judged alone, one theme. | The oracle is a comparison with the reference surface at the same runtime and size in every shipped theme. Testing treats Phase 0 as incomplete without it. |
| No visual source exists anywhere | Not distinguished. | The brief records `visual_source: none` with the locations searched; rows are marked `source-light` and the verdict goes to the user or an independent design owner. |

This table reads the text. It shows what the contract now asks for at each step, not what an agent will do.

### Checks

| Check | Observed result |
| --- | --- |
| `test_uiux_delivery_contract.sh` on an export of the base tree | Three `FAIL` lines, one per new validator; the first new mutation then aborts because its needle is absent. |
| `test_uiux_delivery_contract.sh` on the candidate | `uiux_delivery_contract_ok`. The mutation helper aborts unless its needle occurs exactly once and reports a mutation that its validator accepts, so this result means each of the 18 new mutations was applied and rejected. |
| `test_extraction_review_gate.sh` with this round's register rows on the main-branch controller | Fails: the real controller returns `selected skill file exceeds 1048576 bytes`. |
| `test_extraction_review_gate.sh` on the candidate, stacked on the bound change | `test_extraction_review_gate: ok`. |
| `check-ccl-skills.sh` with `CCL_SKILL_BASE_REF=origin/main` | `ccl_skill_check_clean_ok` (`r0_status=private-ok`). |
| `check-public-sanitization.py`, `git diff --check` | Pass. |
| `test_uiux_loading_budget.sh` | Passes with 76 bytes left under the 110% cap for the design entrypoint, router and contract together (71,864 of 71,940). The first wording exceeded the cap and was shortened. |
| `test_obligation_ledger_repo_audit.sh` | Passes after `specs/065-uiux-evidence-delivery/obligation-preservation.md` was re-rendered with its own pinned base and head: two inserted contract rows shift the line numbers it cites. No cited text changed. |
| `make test` on a Linux host, commit c022c7b, `CCL_SKILL_BASE_REF=origin/main` | Exit 0: repository gates, fast regressions and the code-review suites. |
| `test_check_ccl_regressions.sh --heavy-only`, same host and commit | `regression_heavy_lane_ok: 9 suites`, exit 0. |

### Paired runs

A paired task asked for a design brief from a behavior plan alone and checked whether the committed brief names the repository's visual source. Model `claude-opus-5-5`, plugin exports of the base commit and of the candidate, five samples per arm.

| World | Base | Candidate |
| --- | --- | --- |
| Visual direction document in a five-file repository | 5/5 | 5/5 |
| Visual rules in one chapter of a ten-chapter handbook that the plan and README do not mention | 4/4 (one invalid sample) | 5/5 |

Both runs show no difference. In repositories this small the agent reads the visual source without being told to, so the task cannot show the failure, and it is not added to the task bank. Whether the new text changes agent behavior in a large repository is not measured.

Behavioral evidence: `RED-baseline`. The baseline is a recorded incident (private archive, alias `design-visual-source-miss`): a user rejected the delivered screen. The executable part is the contract suite, red on the base text and green on the candidate.

## Review

Results are under `evidence/`. Every pass ran on another model family (OpenAI) through the extraction review wrapper, with risk tag `shared-gate`.

## Review pass
- Reviewed commit: c110d5a
- Findings: 6 total (0 P0 / 0 P1 / 6 P2)
- R0 evidence: `ccl_skill_check_clean_ok` (`r0_status=private-ok`)
- Dispositions: no P0/P1. P2 "a treatment with no visual source has no `difference_class`": fixed, it stays `design-freedom` and is marked `source-light`. P2 "the pre-edit sentence also binds copy-only records": fixed, scoped to full records. P2 "no mutation covers the source-light verdict owner": fixed. P2 "the packet does not show the bound's enforcement code": withdrawn with its subject; the constant change it concerned is no longer in the branch. P2 "the unchanged client entrypoints are not in the packet": not a defect in the change; the four entrypoints carry the same pre-edit sentences, quoted in the sibling check above. P2 "verification is not filled in": fixed by this section.

## Challenge pass
- Reviewed commit: dfe9301
- Findings: 3 total (0 P0 / 0 P1 / 3 P2)
- Gate-fireability applicability: no — the change adds no hook or always-on text; Item 9 exercised: n/a
- Dispositions: no P0/P1. P2 "one silent token contract lets library defaults pass as free while a visual direction document goes unread": fixed, the search lists every source found and freedom needs all of them silent. P2 "no mutation covers the oracle's fallback or the same runtime and size": fixed. P2 "the packet does not show the bound's enforcement code": same as in the review pass.

## Delta pass
- Reviewed commit: a71c894; packet: git diff dfe9301..a71c894
- Findings: 1 total (0 P0 / 0 P1 / 1 P2), an evidence gap: the packet does not show the mutation helper or per-mutation results.
- Dispositions: no P0/P1. P2 answered by the second row of "Checks".

## Delta pass 2
- Reviewed commit: 68fa4ff; packet: git diff a71c894..68fa4ff without the re-rendered 065 ledger, which exceeds the packet size and changes line numbers only
- Findings: 3 total (0 P0 / 1 P1 / 2 P2)
- Dispositions: P1 "the shortened wording no longer requires listing every source found or inspecting the listed ones": fixed; both obligations are back in the contract, each with a validator needle and a mutation. P2 "the packet omits helper and consumer excerpts": same evidence gap as before, answered by "Checks" and the sibling check. P2 "the record has a placeholder and a stale landing sentence": fixed in this record.

## Delta pass 3
- Reviewed commit: c022c7b; packet: git diff 68fa4ff..c022c7b for the contract, the suite, the register and this record. Controller files are left out: they equal the separately reviewed change this branch is stacked on.
- Findings: 2 total (0 P0 / 0 P1 / 2 P2), both evidence gaps: the packet omits the completeness guard, the Phase 0 oracle, the client consumers and the mutation helper.
- Dispositions: no P0/P1. Both answered by "Checks" and the sibling check; the lane result is recorded there.

## Post-review delta

After c022c7b: the result of delta pass 3 and the lane rows in this record. No skill text or script changed.

The reviewed commits c110d5a, dfe9301, a71c894 and 68fa4ff were squashed and restacked, so that the register rows and the owner changes sit in one commit on top of the bound change. The paired task file that existed in the first three was removed, which returns `eval/` to its base content.
