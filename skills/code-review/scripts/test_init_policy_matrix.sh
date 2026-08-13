#!/usr/bin/env bash
# Policy-matrix regression for the reviewer init gate.
#
# This is the self-audit oracle, not another example-based suite: it states the
# intended policy independently of the implementation and crosses it over the
# init-event shape space through both parse paths. Its own ability to fail is
# checked by mutation, not asserted: point it at a weakened parser (argv[1]) and
# it must report mismatches. The recorded scores for that walk live in
# init_policy_matrix.py's module docstring -- the only durable record of it.
# NOTE: that walk is not automated here, so an ordinary green run does not
# re-prove sensitivity; re-run it by hand when the policy changes.
set -euo pipefail
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
python3 "$script_dir/init_policy_matrix.py"
printf 'init_policy_matrix_ok\n'
