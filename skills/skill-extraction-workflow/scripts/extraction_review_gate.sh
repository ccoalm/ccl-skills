#!/usr/bin/env bash
# Extraction-owned review wrapper: every call is one single-shot pass.
#
# A non-wording extraction owes one review and one challenge, plus a delta pass
# per fixed P0/P1 (references/dual-track-review-gate.md). None of them is bound
# to another pass or to one candidate hash, so this wrapper fixes the controller
# options that make a pass single-shot and refuses the options that would open a
# tracked review chain. The generic controller keeps its chain mode for other
# callers; this lane does not use it.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd -P)"
CONTROLLER="$SCRIPT_DIR/../../code-review/scripts/review_gate.sh"

fail() {
  echo "extraction_review_gate_error: $*" >&2
  exit 2
}

mode=""
expect_mode=0
for arg in "$@"; do
  if [[ "$expect_mode" == 1 ]]; then
    mode="$arg"
    expect_mode=0
    continue
  fi
  case "$arg" in
    --mode) expect_mode=1 ;;
    --mode=*) mode="${arg#--mode=}" ;;
    # Prefixes cover the controller's unambiguous abbreviations as well as the
    # full spellings, so a shortened flag cannot reopen a chain.
    --challenge-b*|--challenge-i*)
      fail "the extraction lane fixes the challenge budget and index; do not pass $arg" ;;
    --review-c*|--au*|--prio*|--pre*|--com*)
      fail "the extraction lane is single-shot; review-chain option $arg is not accepted" ;;
  esac
done

case "$mode" in
  review) fixed=(--challenge-budget 0) ;;
  challenge) fixed=(--challenge-budget 1 --challenge-index 1) ;;
  "") fail "pass --mode review or --mode challenge" ;;
  *) fail "the extraction lane runs only --mode review or --mode challenge, not $mode" ;;
esac

if [[ ! -x "$CONTROLLER" ]]; then
  fail "code-review controller is unavailable"
fi

exec bash "$CONTROLLER" "${fixed[@]}" "$@"
