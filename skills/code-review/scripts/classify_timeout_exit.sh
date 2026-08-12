#!/usr/bin/env bash
# Return success only when an exit is attributable to the timeout supervisor.
set -u

[ "$#" -eq 3 ] || exit 2
run_rc="$1"
run_elapsed="$2"
timeout_limit="$3"
case "$run_rc:$run_elapsed:$timeout_limit" in
  *[!0-9:]*) exit 2 ;;
esac

[ "$run_rc" -eq 124 ] && exit 0
[ "$run_rc" -eq 137 ] && [ "$run_elapsed" -gt "$timeout_limit" ] && exit 0
exit 1
