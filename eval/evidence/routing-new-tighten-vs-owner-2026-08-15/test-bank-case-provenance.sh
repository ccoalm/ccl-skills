#!/bin/bash
# Deterministic provenance check for this round's bank extracts, answering the
# runner's co-change advisory ("verify the bank was not edited to pass"):
# 1) the frozen bank eval/routing-tasks.jsonl is byte-identical to dev's copy;
# 2) every line of bank-single.jsonl and bank-neighbors.jsonl appears verbatim
#    (byte-identical whole line) in the frozen bank at this worktree's HEAD.
# Prints ALL VERBATIM and exits 0 only when both hold; any mismatch is fatal.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd -P)"
WT="$(git -C "$HERE" rev-parse --show-toplevel)" || exit 1
FROZEN="$WT/eval/routing-tasks.jsonl"

# Pin the comparison to the round's frozen fork point and the bank's exact
# content hash (chain r1a challenge P2): comparing against the mutable dev ref
# would go stale-green if dev itself later carried an edited bank.
FORK_SHA=c0561c74e0f7249b8041f7c5800a8d6deadf496f
FROZEN_SHA256=b30280289422e9c7b92679a70fa63df69a14c1eef43f1d6aaab43746f1eddc70

if ! git -C "$WT" diff --quiet "$FORK_SHA" -- eval/routing-tasks.jsonl; then
  echo "FAIL: eval/routing-tasks.jsonl differs from the frozen fork point $FORK_SHA" >&2
  exit 1
fi
if [ "$(shasum -a 256 "$FROZEN" | awk '{print $1}')" != "$FROZEN_SHA256" ]; then
  echo "FAIL: frozen bank sha256 does not match the pinned value" >&2
  exit 1
fi

fail=0
checked=0
for bank in "$HERE/bank-single.jsonl" "$HERE/bank-neighbors.jsonl"; do
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    checked=$((checked + 1))
    if ! grep -qxF -- "$line" "$FROZEN"; then
      echo "FAIL: line not found verbatim in frozen bank ($(basename "$bank")): $line" >&2
      fail=1
    fi
  done < "$bank"
done

[ "$checked" -eq 12 ] || { echo "FAIL: expected 12 extracted lines (1 target + 11 neighbors), checked $checked" >&2; fail=1; }
[ "$fail" -eq 0 ] || exit 1
echo "ALL VERBATIM: $checked extracted bank lines byte-identical to frozen bank; frozen bank identical to fork $FORK_SHA with pinned sha256"
