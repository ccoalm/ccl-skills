#!/usr/bin/env bash
# Extraction-owned autonomous review wrapper: one review plus one challenge.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd -P)"
CONTROLLER="$SCRIPT_DIR/../../code-review/scripts/review_gate.sh"

for arg in "$@"; do
  case "$arg" in
    --challenge-b*)
      echo "extraction_review_gate_error: challenge budget is fixed at 1" >&2
      exit 2
      ;;
  esac
done

if [[ ! -x "$CONTROLLER" ]]; then
  echo "extraction_review_gate_error: code-review controller is unavailable" >&2
  exit 2
fi

exec bash "$CONTROLLER" --challenge-budget 1 "$@"
