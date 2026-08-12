#!/usr/bin/env bash
# Policy-matrix regression for the reviewer init gate.
#
# This is the self-audit oracle, not another example-based suite: it states the
# intended policy independently of the implementation and crosses it over the
# init-event shape space through both parse paths. Its own ability to fail is
# recorded in specs/009-claude-review-tool-boundary/validation-log.md -- point it
# at a weakened parser (argv[1]) and it must report mismatches.
set -euo pipefail
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
python3 "$script_dir/init_policy_matrix.py"
printf 'init_policy_matrix_ok\n'
