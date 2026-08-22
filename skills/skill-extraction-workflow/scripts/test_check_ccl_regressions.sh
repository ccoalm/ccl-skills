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
#   - test_generic_r0_leak_scan.sh
#   - test_check_ccl_route_drift.sh
#   - test_check_sync_pointers.sh
#   - test_check_ccl_register_pending_exclusion.sh
#   - test_eval_routing_bank_grader_diagnostics.sh
#   - test_eval_routing_bank_surface_binding.sh
#   - test_eval_routing_prose_target.sh
#   - test_validate_skill_credential_cwd.sh
#   - test_validate_skill_root_depth.sh
#   - test_regression_runner_registration.sh
# --full runs --fast plus the heavy full-checker regressions:
#   - test_check_ccl_r0_status.sh
#   - test_check_ccl_source_register_lifecycle.sh
#   - test_check_ccl_impact_chain_refscripts.sh
#   - test_register_firing_path_wiring.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd -P)"
REPO_ROOT="$(git -C "$SCRIPT_DIR" rev-parse --show-toplevel 2>/dev/null || { cd "$SCRIPT_DIR/../../.." && pwd -P; })"
SCRIPTS_DIR="$REPO_ROOT/skills/skill-extraction-workflow/scripts"

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

run_test() {
  local test_name="$1"
  local test_path="$SCRIPTS_DIR/$test_name"
  local started_at ended_at rc
  [ -f "$test_path" ] || { echo "FAIL: missing regression test: $test_path" >&2; exit 1; }
  started_at="$(date +%s)"
  if bash "$test_path"; then
    rc=0
  else
    rc=$?
  fi
  ended_at="$(date +%s)"
  echo "regression_test_timing: test=$test_name seconds=$((ended_at - started_at)) status=$rc"
  return "$rc"
}

fast_tests=(
  test_ai_coding_implementation_gates.sh
  # Reproducible RED-baseline for the controlled-escalation pin family: parses
  # family 8 out of the fixture above and proves each pin reds under its own
  # applied deletion mutation in a throwaway copy (spec 031 review disposition).
  test_controlled_escalation_pins.sh
  test_check_ccl_size_budget.sh
  test_check_ccl_skill_catalog.sh
  test_check_mr_target_freshness.sh
  test_generic_r0_leak_scan.sh
  test_check_ccl_route_drift.sh
  test_check_sync_pointers.sh
  test_check_ccl_register_pending_exclusion.sh
  test_register_firing_path_resolution.sh
  # Merge-time containment for the gate's date dependency; the deep three-leg
  # differential stays in the heavy suite, but a require-date regression must
  # go RED in every `make test`, not only under --full.
  test_impact_chain_gate_dateless_host.sh
  test_eval_routing_bank_grader_diagnostics.sh
  test_eval_routing_bank_surface_binding.sh
  test_eval_routing_prose_target.sh
  test_validate_skill_credential_cwd.sh
  test_validate_skill_root_depth.sh
  test_validate_skill_cross_refs.sh
  test_git_identity_predicate_gate.sh
  test_regression_runner_registration.sh
  test_routing_pointer_integrity.sh
  test_routing_bank_integrity.sh
  test_governing_chain_diff.sh
  # Owned by another skill package; run_test resolves it relative to SCRIPTS_DIR.
  # Registered here because this runner is the repo's only regression lane —
  # a skill-local test left unregistered is the false-green this file guards.
  ../../testing-strategy/scripts/test_mutation_backup_recipe.sh
)

heavy_tests=(
  test_check_ccl_r0_status.sh
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

if [ "$mode" != "heavy-only" ]; then
  for test_name in "${fast_tests[@]}"; do
    run_test "$test_name"
  done
fi

if [ "$mode" = "full" ] || [ "$mode" = "heavy-only" ]; then
  for test_name in "${heavy_tests[@]}"; do
    run_test "$test_name"
  done
fi

case "$mode" in
  full) echo "test_check_ccl_regressions_full_ok" ;;
  heavy-only) echo "test_check_ccl_regressions_heavy_only_ok" ;;
  *) echo "test_check_ccl_regressions_fast_ok" ;;
esac

if [ -n "$unregistered" ]; then
  echo "regression_runner_unregistered_tests_advisory: not in fast_tests/heavy_tests, CI will NOT run them:$unregistered" >&2
fi
