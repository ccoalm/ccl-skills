#!/usr/bin/env bash

# Print the normalized per-invocation timeout. The input is compared by digit
# count before any arithmetic so an arbitrarily long decimal cannot overflow
# Bash's integer parser.
normalize_review_timeout() {
  local value="${1:-}" digits

  case "$value" in
    ""|0*|*[!0-9]*) return 2 ;;
    1|2|3|4) return 2 ;;
  esac

  digits=${#value}
  if [ "$digits" -gt 4 ] || {
    [ "$digits" -eq 4 ] && [ "$value" -gt 1200 ]
  }; then
    printf '%s\n' 1200
  else
    printf '%s\n' "$value"
  fi
}
