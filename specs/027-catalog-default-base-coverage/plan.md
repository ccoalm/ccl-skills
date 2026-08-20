# Catalog Fixture Default-Base Coverage

Status: r14 challenge triaged; `GIT_NAMESPACE` fix applied; Bash 3.2 focused, fast, and repository gates passed with private R0; final dual-track rerun pending

## Charter

| Field | Decision |
| --- | --- |
| Purpose | Prevent the catalog suite from going green while every case bypasses `check-ccl-skills.sh` default base discovery. |
| Scope | Cover both unset-`CCL_SKILL_BASE_REF` paths in `test_check_ccl_skill_catalog.sh`: select `@{upstream}` when present and fall back to `origin/main` when absent. Keep the existing catalog mutations and production base-selection code unchanged. Do not change CI, release behavior, or other suites. No earlier `covered-through` watermark applies. |
| Depth | Targeted tooling change with a deterministic Git fixture. |
| Root cause | The suite pins `CCL_SKILL_BASE_REF=ccl-test-base` for every case. That removed ancestry-dependent failures, but it also removed the only plausible execution path for default base discovery. |
| RCA analysis | Active gap: `run_case` always injects the override. Missing control: no case makes upstream selection observable. Latent condition: the old default-path shape depended on the caller repository's branch graph. If only the override is removed, the gap closes at the cost of reintroducing that instability. A synthetic upstream and decoy fallback isolate the behavior from the caller graph. |
| Failure mode analysis | A regression that ignores the current branch upstream and falls back to another ref would remain undetected until a real checkout reports the wrong changed-entrypoint set. |
| Lifecycle impact | Implementation and testing only. Product intent, design, launch, onboarding, and no-source-access use are not affected. |
| Evidence plan | Produced artifacts: this plan and the catalog test script. Primary sources: the base-selection block in `check-ccl-skills.sh`, the current catalog fixture, and focused test output. External sources are not applicable because this change tests a repository-local contract. |
| Completion standard | Record the pre-change uncovered-path probe, make the synthetic default-base case pass, run the focused suite and repository gates, then record independent review and challenge outcomes. |

## Target-output map

| Target | Direction | Status | File or reason |
| --- | --- | --- | --- |
| Catalog fixture | downstream test | updated | `skills/skill-extraction-workflow/scripts/test_check_ccl_skill_catalog.sh` |
| Default base resolver | owner implementation | unchanged | `check-ccl-skills.sh` already selects `@{upstream}` before `origin/main`; this round proves that path. |
| CI base injection | upstream caller | unchanged | CI intentionally supplies an exact candidate base; it is not the default-path oracle. |
| Other regression suites | sibling tests | unchanged | The catalog fixture can own the narrow proof without duplicating it across suites. |
| Shared-skill prose | owner guidance | unchanged | The failure is executable coverage, not a missing prose rule. |

## Resolver contract under test

The production resolver is unchanged in this round. The test targets this exact branch order from `check-ccl-skills.sh`:

```ruby
base = ENV.fetch("CCL_SKILL_BASE_REF", "").strip
if base.empty?
  upstream_ref = IO.popen(["git", "-C", root, "rev-parse", "--abbrev-ref", "--symbolic-full-name", "@{upstream}", err: File::NULL], &:read).strip
  base = upstream_ref.empty? ? "origin/main" : upstream_ref
end
merge_base = IO.popen(["git", "-C", root, "merge-base", base, "HEAD"], &:read).strip
```

Catalog row position is not part of bootstrap membership. The unchanged checker reads routed skill names only from the marked region in `agent-context/session-start.md`, then intersects that set with catalog names marked leaf:

```ruby
region = File.read(bootstrap_path)[/ccl:entry-routing:start -->(.*?)<!-- ccl:entry-routing:end/m, 1]
routed = region.scan(/\*\*([a-z0-9-]+)\*\*/).flatten.select { |name| name.match?(skill_token) }.uniq
leaf_in_region = routed & (names - entry_names)
```

## Test design

The existing catalog cases keep their exact `ccl-test-base` override. One additional case:

1. Clears caller repository-routing Git environment variables before any fixture Git command, then unsets them again with `CCL_SKILL_BASE_REF` inside each checker process. c12 reintroduces a deliberately hostile outer Git context made only from a scratch bare repo, worktree, and index under `TEST_ROOT` for all five checker calls, keeping cleanup load-bearing without exposing the developer repository.
2. Creates and commits a dedicated leaf skill plus its overlay and inserts its catalog row before the first row matching the catalog's generic leaf grammar; that commit is synthetic base `B`.
3. Changes one same-length state marker in the fixture skill and commits synthetic head `H`, so the body is deterministically above the warning threshold with zero size growth.
4. Calibrates the observable once with explicit base `B`; fixture/threshold failure is therefore distinct from default-discovery failure.
5. With the upstream present, runs an empty-diff arm at `H` that must suppress the warning and a changed-diff arm at `B` that must emit it.
6. Removes the upstream and repeats the empty/changed pair through `origin/main` fallback.
7. Before every arm, controls the peeled `for-each-ref` set at `B`: no ref may remain there for empty-diff arms, and only the expected resolver ref may remain there for changed-diff arms.

The warning appears only when discovery selects the synthetic base. Selecting the decoy produces an empty committed diff and must fail the assertion. Both refs and their ancestry are created inside the case clone, and inherited Git routing is removed inside each checker subprocess, so the caller repository's topology cannot decide the result. The dedicated fixture skill exists in `B`, stays above the threshold in both commits, and changes size-neutrally in `H`; no unrelated real skill's name, existence, or body size decides the result.

## Design-time operability

| Leg | Decision |
| --- | --- |
| Author dogfood | Run the case through the same `check-ccl-skills.sh` entrypoint used by the suite. Fixture assertions verify both merge bases before the checker runs. |
| Marginal cost | One extra case clone, two local commits, one explicit-base calibration, and four default-base checker invocations for the upstream/fallback by empty/changed matrix. No extra dependency, network call, or evidence regeneration is required. |
| Trust-model fit | Protects against accidental test bypass and wrong fallback selection by repository contributors. It does not claim protection from an author who rewrites both implementation and oracle. |
| Premise or loosening check | No production verdict changes. The oracle distinguishes the decoy from the synthetic base, then exercises both branches of the current default resolver. |

## Implementer self-review

| Field | Result |
| --- | --- |
| Acceptance criteria | Override-driven c1-c11 remain unchanged; c12 unsets inherited overrides, covers upstream/fallback by empty/changed diff, removes every direct or peeled annotated-tag ref at `B` for empty arms, retains only the intended direct ref at `B` for changed arms, and uses only commits and refs created inside its clone. |
| Changed-file scope | `skills/skill-extraction-workflow/scripts/test_check_ccl_skill_catalog.sh`; `skills/skill-extraction-workflow/references/source-register.md`; `specs/027-catalog-default-base-coverage/plan.md`. No generated files are excluded. |
| Edge and failure paths | Caller Git routing is cleared before `REPO_ROOT` discovery and every fixture `git -C` operation, then removed again inside checker subshells. The hostile outer `GIT_DIR`, `GIT_WORK_TREE`, and `GIT_INDEX_FILE` all point into `TEST_ROOT`; even a cleanup regression can touch only disposable scratch state, never the developer repository or its live index. The helper stores checker rc in `CASE_STATUS` and returns the same rc; the wrapper invokes it conditionally, restores every routed value, then propagates that status. Each caller suppresses only the outer `set -e` exit so the immediately following warning helper can report `CASE_OUTPUT` and assert the same `CASE_STATUS`. This does not rely on version-dependent function-call assignment scope. An explicit-B calibration proves the fixture and current size metric emit the observable before default discovery is tested. Empty-diff default arms prove the warning is not emitted by a no-base or all-changed degeneration; changed-diff arms prove the selected base exposes the committed skill change. Every arm also requires checker exit 0. Merge bases are asserted. Before every arm, named annotated and nested tags are recreated at `B`; the shared helper snapshots the peeled `for-each-ref --points-at B` set before deletion, and an independent named-ref assertion proves both aliases are gone. Fallback arms prove no upstream remains. The dedicated skill removes dependence on unrelated skill size, and its catalog insertion fails early only when the catalog has no leaf row at all. Per-case clones and the existing trap contain mutations. Warning helpers receive the skill name explicitly, use an `if` for the expected negative `grep -q` miss under `set -e`, and read output through here-strings so `pipefail` cannot turn grep's early success into writer SIGPIPE. |
| Known residual risks | The suite proves Git ref selection through an observable changed-entrypoint warning; it does not unit-test Git command failures or redefine how an invalid explicit override should behave. Pseudorefs are not inputs to the production resolver: in this graph B is created after `FETCH_HEAD`, same-commit `checkout -B` did not create `ORIG_HEAD`, and the empty/changed symmetry rejects a resolver that always chooses either `B` or `H`. Caller `GIT_NAMESPACE` is cleared because it changes ref visibility; user/system Git configuration remains host-owned like the existing c1-c11 fixture and is not redefined by this narrow ancestry-isolation case. c12 adds five real checker invocations; the latest fast lane measured catalog at 116 seconds, below route-drift at 141 seconds. Final R0 status requires a fresh repository-gate run. |

## Pre-review evidence snapshot

This table freezes the state before the final deterministic and dual-track reruns. Their result files stay outside the candidate so recording them cannot change the reviewed hash. Reviews r2 and r3 found the same ref-alias false-green class in opposite arms; r4 then found that positive-only default assertions could miss a no-base/all-changed degeneration. The final design is one shared ref-isolation helper plus a 2x2 matrix.

| Evidence | Status | Result |
| --- | --- | --- |
| Pre-change default-path coverage probe | RED-baseline | `rg` found no checker invocation that unsets `CCL_SKILL_BASE_REF`; probe exited 1 with `RED: catalog suite has no invocation with CCL_SKILL_BASE_REF unset`. |
| Focused catalog suite | passed | System `/bin/bash 3.2.57` ran the namespace-fixed script to `test_check_ccl_skill_catalog: ok`. |
| Fast regression lane | passed | The namespace-fixed `test_check_ccl_regressions.sh --fast` ended with `test_check_ccl_regressions_fast_ok`; catalog took 115 seconds and route-drift took 131 seconds. |
| Required repository gates | passed, private R0 | Contract coverage, `check-ccl-skills.sh`, public sanitization, Markdown links, and `git diff --check` exited 0 on the namespace-fixed candidate. `check-ccl-skills.sh` reported `r0_status=private-ok`, `ccl_skill_check_ok`, and `ccl_skill_check_clean_ok`. |
| Implementer self-review | recorded | Acceptance, exact changed-file scope, failure paths, and residual risks are recorded above before external review. |
| Independent review | passed, invalidated by fix | Tracked r14 review passed with no findings on candidate `9a6b21e27696d63f66ade03aade4248b273aa6fea4dd7a10c7addd796151114a`; the later namespace fix invalidated it. |
| Adversarial challenge | findings triaged; rerun pending | r14 challenge repeated the already controlled hostile-wrapper and out-of-contract pseudoref premises; both are rejected. Its `GIT_NAMESPACE` subfinding is accepted and fixed. Global Git config isolation is outside this narrow ref/ancestry fixture and unchanged from c1-c11. |
