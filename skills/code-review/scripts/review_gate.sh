#!/usr/bin/env bash
# Provider-neutral review/challenge entrypoint. The Python implementation owns
# packet freezing and the explicit Claude -> Codex -> Kimi -> OpenCode state machine.
set -euo pipefail
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
exec python3 "$script_dir/review_gate.py" "$@"
