#!/bin/bash
# Regression test for run-bound-round.sh's output-validation guard (chain r3 review P1).
# Stubs the ruby evaluator via PATH (no model call): asserts the wrapper fails
# closed (nonzero exit, binding_valid=false) when the evaluator exits 0 without
# producing usable output or writes malformed JSON, and passes (exit 0,
# binding_valid=true) when the stub writes a structurally valid round file.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd -P)"
WRAP="$HERE/run-bound-round.sh"
BANK="$HERE/bank-single.jsonl"
TMP="$(mktemp -d)" || exit 1
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/bin"
fail=0

run() { PATH="$TMP/bin:$PATH" bash "$WRAP" "$1" "$BANK" "$2"; }

# case 1: evaluator exits 0, writes nothing -> must fail closed
cat > "$TMP/bin/ruby" <<'EOF'
#!/bin/bash
exit 0
EOF
chmod +x "$TMP/bin/ruby"
run 1 "$TMP/out-c1" >/dev/null 2>&1; rc=$?
if grep -q '"binding_valid": false' "$TMP/out-c1/round-1.json.binding.json" && [ "$rc" != "0" ]; then :; else
  echo "FAIL case1: rc=$rc (missing evaluator output must not be accepted)"; fail=1
fi

# case 2: evaluator exits 0, writes malformed JSON -> must fail closed
cat > "$TMP/bin/ruby" <<'EOF'
#!/bin/bash
prev=""
for a in "$@"; do
  if [ "$prev" = "--json" ]; then echo '{not json' > "$a"; fi
  prev="$a"
done
exit 0
EOF
chmod +x "$TMP/bin/ruby"
run 2 "$TMP/out-c2" >/dev/null 2>&1; rc=$?
if grep -q '"binding_valid": false' "$TMP/out-c2/round-2.json.binding.json" && [ "$rc" != "0" ]; then :; else
  echo "FAIL case2: rc=$rc (malformed evaluator output must not be accepted)"; fail=1
fi

# case 3: evaluator writes structurally valid JSON -> wrapper passes
cat > "$TMP/bin/ruby" <<'EOF'
#!/bin/bash
prev=""
for a in "$@"; do
  if [ "$prev" = "--json" ]; then printf '{"results":[{"id":"x","status":"PASS","selected":"y"}]}' > "$a"; fi
  prev="$a"
done
exit 0
EOF
chmod +x "$TMP/bin/ruby"
run 3 "$TMP/out-c3" >/dev/null 2>&1; rc=$?
if grep -q '"binding_valid": true' "$TMP/out-c3/round-3.json.binding.json" && [ "$rc" = "0" ]; then :; else
  echo "FAIL case3: rc=$rc (structurally valid output must pass)"; fail=1
fi

if [ "$fail" = "0" ]; then echo "PASS: all 3 cases"; else echo "FAILURES present"; fi
exit $fail
