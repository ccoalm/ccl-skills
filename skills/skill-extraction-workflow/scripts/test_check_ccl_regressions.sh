#!/usr/bin/env bash
# Aggregate deterministic shell regressions for check-ccl-skills wrappers.
#
# Default / local layer: --fast. CI runs the two layers as parallel jobs
# (regression-fast --fast, regression-heavy --heavy-only); --full remains the
# local aggregate (`make test-check-ccl-regressions`). Makefile and CI both call
# this single entrypoint instead of copying test lists.
#
# Usage:
#   bash skills/skill-extraction-workflow/scripts/test_check_ccl_regressions.sh [--fast|--full|--heavy-only]
#
# --fast runs the quick/mid wrapper regressions:
#   - test_ai_coding_implementation_gates.sh
#   - test_controlled_escalation_pins.sh
#   - test_check_ccl_size_budget.sh
#   - test_check_ccl_skill_catalog.sh
#   - test_check_ccl_parallel_stack_parity.sh
#   - test_generic_r0_leak_scan.sh
#   - test_shared_git_surface_gate.sh
#   - test_extraction_review_gate.sh
#   - test_validate_extraction_review_state.sh
#   - test_check_ccl_route_drift.sh
#   - test_check_sync_pointers.sh
#   - test_check_ccl_register_pending_exclusion.sh
#   - test_eval_routing_bank_grader_diagnostics.sh
#   - test_eval_routing_bank_surface_binding.sh
#   - test_eval_routing_prose_target.sh
#   - test_validate_skill_credential_cwd.sh
#   - test_validate_skill_root_depth.sh
#   - test_regression_runner_registration.sh
#   - test_uiux_delivery_contract.sh
#   - test_uiux_loading_budget.sh
#   - test_obligation_ledger.sh
# --full runs --fast plus the heavy full-checker regressions:
#   - test_check_ccl_r0_status.sh
#   - test_check_ccl_source_register_lifecycle.sh
#   - test_check_ccl_impact_chain_refscripts.sh
#   - test_register_firing_path_wiring.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd -P)"
REPO_ROOT="$(git -C "$SCRIPT_DIR" rev-parse --show-toplevel 2>/dev/null || { cd "$SCRIPT_DIR/../../.." && pwd -P; })"
# REGRESSION_SCRIPTS_DIR redirects the whole runner (execution and audit) at a
# fixture tree, so the lane-semantics regression can prove mode dispatch with
# stub suites instead of the real multi-minute ones.
SCRIPTS_DIR="${REGRESSION_SCRIPTS_DIR:-$REPO_ROOT/skills/skill-extraction-workflow/scripts}"

usage() {
  cat <<'EOF'
Usage: test_check_ccl_regressions.sh [--fast|--full|--heavy-only]

Runs deterministic shell regressions for check-ccl-skills wrapper behavior.
Default is --fast to keep local `make test` light. CI runs --fast and
--heavy-only as parallel jobs; --full is the local aggregate.

Modes:
  --fast  the quick/mid wrapper regressions (exact set = the fast_tests array below / the list above)
  --full  fast layer plus R0 status and source-register lifecycle regressions
  --heavy-only  only the heavy full-checker regressions (the heavy_tests array);
          gives CI a heavy execution surface that does not repeat the fast layer
  --list-unregistered  print sibling test_*.sh NOT in fast_tests/heavy_tests (one per
          line) and exit 0; used by the registration guard test so a new test cannot
          silently skip CI. REGRESSION_SCRIPTS_DIR overrides the scanned directory.
EOF
}

mode="fast"
case "${1:-}" in
  ""|--fast) mode="fast" ;;
  --full) mode="full" ;;
  --heavy-only) mode="heavy-only" ;;
  --list-unregistered) mode="list-unregistered" ;;
  -h|--help) usage; exit 0 ;;
  *) usage >&2; exit 2 ;;
esac

if [ "$#" -gt 1 ]; then
  usage >&2
  exit 2
fi

# Lanes execute through the shared bounded-concurrency runner: these suites are
# dominated by waiting (process timeouts, stub sleeps) and by independent
# subprocesses, so serial execution burned wall-clock the runner host was not
# using. The runner owns the missing-file precondition, the per-suite timing
# line, in-order output replay, and failure propagation; assertions inside the
# suites are untouched. `SUITE_JOBS=1` restores serial execution for debugging a
# suspected concurrency interaction. See specs/037-ci-intra-job-parallel/plan.md
# for the per-lane shared-state audit that makes this safe.
PARALLEL_RUNNER="$REPO_ROOT/scripts/run-parallel-suites.sh"

run_lane() {
  local label="$1"; shift
  local paths=() entry
  for entry in "$@"; do paths+=("$SCRIPTS_DIR/$entry"); done
  [ -f "$PARALLEL_RUNNER" ] || {
    echo "FAIL: missing parallel suite runner: $PARALLEL_RUNNER" >&2
    exit 1
  }
  bash "$PARALLEL_RUNNER" --label "$label" "${paths[@]}"
}

fast_tests=(
  test_ai_coding_implementation_gates.sh
  # Reproducible RED-baseline for the controlled-escalation pin family: parses
  # family 8 out of the fixture above and proves each pin reds under its own
  # applied deletion mutation in a throwaway copy (spec 031 review disposition).
  test_controlled_escalation_pins.sh
  test_check_ccl_size_budget.sh
  test_check_ccl_skill_catalog.sh
  test_check_ccl_parallel_stack_parity.sh
  test_check_mr_target_freshness.sh
  test_generic_r0_leak_scan.sh
  test_shared_git_surface_gate.sh
  test_extraction_review_gate.sh
  test_validate_extraction_review_state.sh
  # Candidate-SHA-bound gate receipts (mint/verify): own throwaway git repo,
  # no clone, seconds — belongs in the lane every run exercises.
  test_gate_receipt.sh
  test_check_ccl_route_drift.sh
  test_check_sync_pointers.sh
  test_check_ccl_register_pending_exclusion.sh
  test_register_firing_path_resolution.sh
  # Merge-time containment for the gate's date dependency; the deep three-leg
  # differential stays in the heavy suite, but a require-date regression must
  # go RED in every `make test`, not only under --full.
  test_impact_chain_gate_dateless_host.sh
  # Row-ownership attribution probes: a control leg plus the refusals the gate
  # owes on a surviving row that vouches for an unchanged owner, a row citing a
  # package path other than SKILL.md, a row resolving to two selected owners,
  # and the two shapes that must keep their prior silent skip (an unrelated
  # five-column register table, a non-curated owner). Synthetic repos only, no
  # clone, so it belongs in the lane every run exercises.
  test_impact_chain_round_attribution.sh
  test_eval_routing_bank_grader_diagnostics.sh
  test_eval_routing_bank_surface_binding.sh
  test_eval_routing_prose_target.sh
  test_validate_skill_credential_cwd.sh
  test_validate_skill_root_depth.sh
  test_validate_skill_cross_refs.sh
  test_git_identity_predicate_gate.sh
  test_liveness_predicate_gate.sh
  # 074: contract-anchor gate self-proof (tmp fixtures + one real-repo leg,
  # seconds) and the anti-patterns panel structural check (awk over one file).
  test_check_contract_anchors.sh
  test_antipattern_grep_panel.sh
  # 075: body-compliance grading contract (grade() walk, fail-closed --ids legs,
  # stub-model denominator/forbidden_hit legs; deterministic, seconds).
  test_body_compliance_grading.sh
  test_regression_runner_registration.sh
  # Harness binding for the gate lanes themselves: the impact-chain gate's
  # round walk needs the branch's own first-parent chain, which the default
  # refs/pull/N/merge checkout does not provide. Cheap, no clone, and a
  # regression here is otherwise invisible until it refuses an unrelated PR.
  test_ci_checkout_ref_binding.sh
  # Lane-semantics guard for this runner itself (036 challenge P2): proves
  # --heavy-only / --fast / --full each run exactly their lane against a stub
  # fixture via REGRESSION_SCRIPTS_DIR, and that a red heavy stub propagates.
  test_regression_runner_lanes.sh
  test_routing_pointer_integrity.sh
  test_routing_bank_integrity.sh
  # 077: frozen-case sanctity (regressions-are-sacred) — base-relative guard
  # that a deleted/re-scoped bank case or golden trace names its adjudication
  # row; degrades to an explicit skip token without CCL_SKILL_BASE_REF. The
  # selfproof lane proves the oracle fails for the right reason (synthetic
  # repo: deletion/re-scope/nested-trace mutants red, forged-credit legs red,
  # adjudicated and control legs green).
  test_frozen_case_sanctity.sh
  test_frozen_case_sanctity_selfproof.sh
  test_uiux_delivery_contract.sh
  test_uiux_loading_budget.sh
  test_governing_chain_diff.sh
  test_obligation_ledger.sh
  # Owned by another skill package; run_test resolves it relative to SCRIPTS_DIR.
  # Registered here because this runner is the repo's only regression lane —
  # a skill-local test left unregistered is the false-green this file guards.
  ../../testing-strategy/scripts/test_mutation_backup_recipe.sh
)

heavy_tests=(
  test_check_ccl_r0_status.sh
  test_entrypoint_domain_scan_terms.sh
  # Audits the REAL specs/065 mapping/ledger against the base SHA pinned in
  # the ledger header. Catches carrier drift the synthetic obligation-ledger
  # fixtures cannot see. Needs full history and walks a 1240-row real corpus,
  # so it stays out of the pre-commit lane; CI --full enforces it.
  test_obligation_ledger_repo_audit.sh
  test_check_ccl_source_register_lifecycle.sh
  # Clones the whole repo once; impact-chain cases call the standalone gate and
  # retain one full-checker wiring case. Still kept out of the pre-commit lane.
  test_check_ccl_impact_chain_refscripts.sh
  # Same reason: clones the repo and drives the full checker TWICE (~26s, the
  # slowest entry the lane had). Its sibling
  # `test_register_firing_path_resolution.sh` keeps the gate's behaviour in the
  # fast lane; this one only proves the checker WIRING, which cannot drift from a
  # local edit without also changing the checker. CI runs `--full`, so moving it
  # here costs no enforcement — it only stops charging every pre-commit run for a
  # repo clone, and stops a slow entry competing for the runner host.
  test_register_firing_path_wiring.sh
  # No-verdict-regression differential: materializes twelve pinned integration
  # points as detached worktrees and runs both the baseline and candidate gate
  # against each. Proves the other half of a gate change — that it did not start
  # refusing what it used to accept — which is the half that blocks every author
  # when it goes wrong. Worktree-per-point makes it far too slow for pre-commit.
  # source-refuted 证据类的滥用面：16 条合成用例，每条一条分支，且整仓 clone 一次
  # 作 fixture 底座。它测的正是「这个类会不会变成通用豁免」——七轮独立评审各击穿过
  # 一版门槛，所以负向用例（真行为变更披标签、抵消式新增、路径穿越、子串锚、改权限、
  # 对照表不交代被删内容）必须每轮都跑。clone + 16 分支对 pre-commit 太慢，进 heavy。
  test_impact_chain_source_refuted.sh
  test_impact_chain_gate_verdict_differential.sh
  # 045：两个触发器（routing 面改动欠 bank 证据、台账行欠 result-class）的十条决策表
  # 用例。同样是整仓 clone + 一 case 一分支的形态，故与上面两套同进 heavy。它钉的是
  # 「跳过义务会不会留下可检出的缺席」——044 连续五轮 challenge 都停在这一点上，负向
  # 用例（缺证据、非枚举值、降范围无留痕）必须每轮都跑，否则触发器会悄悄退化成声称。
  test_impact_chain_self_adjudication.sh
  # 074: one applied deletion mutation per pinned-phrase gate family, each leg
  # running the FULL shipped checker against a committed fixture copy of the
  # working tree (6 full-gate runs — far too slow for pre-commit). Proves the
  # ~40 required_phrase pins and the contract-anchor delegation can actually
  # go red for the right reason; the fast lane keeps the checker-level
  # self-proof in test_check_contract_anchors.sh.
  test_pinned_phrase_mutation_walk.sh
)

# Registration self-audit: every sibling test_*.sh must appear in fast_tests or
# heavy_tests, else CI silently skips it (a false-green — the class that let
# test_validate_skill_credential_cwd.sh ship unrun). Compute the gap here so both
# --list-unregistered (for the guard test) and the normal-run advisory share it.
# REGRESSION_SCRIPTS_DIR overrides the scanned dir so the guard test can point at
# a fixture. Bash 3.2-safe (string-set membership, no associative arrays).
self_name="$(basename "$0")"
audit_dir="${REGRESSION_SCRIPTS_DIR:-$SCRIPTS_DIR}"
registered=" ${fast_tests[*]} ${heavy_tests[*]} "
unregistered=""
for audit_f in "$audit_dir"/test_*.sh; do
  [ -e "$audit_f" ] || continue           # literal glob when no match
  audit_b="$(basename "$audit_f")"
  [ "$audit_b" = "$self_name" ] && continue   # the runner never registers itself
  case "$registered" in *" $audit_b "*) continue ;; esac
  unregistered="$unregistered $audit_b"
done
unregistered="${unregistered# }"

if [ "$mode" = "list-unregistered" ]; then
  [ -n "$unregistered" ] && printf '%s\n' $unregistered
  exit 0
fi

# Unregistered siblings hard-fail every execution mode (036 challenge P1): the
# old advisory-only tail made enforcement depend on the registration guard test
# itself staying registered — removing it from fast_tests silenced the only red
# path. Failing here keeps enforcement independent of any one array entry.
if [ -n "$unregistered" ]; then
  echo "FAIL: test_*.sh not registered in fast_tests/heavy_tests (CI would silently skip them):$unregistered" >&2
  exit 1
fi

if [ "$mode" != "heavy-only" ]; then
  run_lane regression_fast_lane "${fast_tests[@]}"
fi

if [ "$mode" = "full" ] || [ "$mode" = "heavy-only" ]; then
  run_lane regression_heavy_lane "${heavy_tests[@]}"
fi

case "$mode" in
  full) echo "test_check_ccl_regressions_full_ok" ;;
  heavy-only) echo "test_check_ccl_regressions_heavy_only_ok" ;;
  *) echo "test_check_ccl_regressions_fast_ok" ;;
esac
