#!/usr/bin/env bash
# Test harness for client-terminal-ansi-check.py (CB-1) — proves it catches hardcoded ANSI
# escape literals across forms/languages, exempts the allowlisted rendering module, does not
# false-positive on clean source, and is inconclusive (not clean) on bad scope.
# Run: bash client-terminal-ansi-check.test.sh   (honors $TMPDIR; needs python3)
set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
script="$here/client-terminal-ansi-check.py"
command -v python3 >/dev/null 2>&1 || { echo "python3 required" >&2; exit 2; }
base="${TMPDIR:-/tmp}"
tmp="$(mktemp -d "${base%/}/cbansi.XXXXXX")"
trap 'rm -rf "$tmp"' EXIT

pass=0 fail=0
assert_hit() { local desc="$1" want="$2"; shift 2
  set +e; local out rc; out="$(python3 "$script" "$@" 2>/dev/null)"; rc=$?; set -e
  if [ "$rc" = 1 ] && printf '%s' "$out" | grep -qF "$want"; then pass=$((pass+1)); echo "ok   - $desc"
  else fail=$((fail+1)); echo "FAIL - $desc (rc=$rc, want '$want', out='$out')"; fi; }
assert_exit() { local desc="$1" want="$2"; shift 2
  set +e; python3 "$script" "$@" >/dev/null 2>&1; local rc=$?; set -e
  if [ "$rc" = "$want" ]; then pass=$((pass+1)); echo "ok   - $desc"; else fail=$((fail+1)); echo "FAIL - $desc (want exit $want, got $rc)"; fi; }

mkdir -p "$tmp/src" "$tmp/render" "$tmp/empty"
# positive: each form on its own line, across languages
cat > "$tmp/src/colors.go" <<'EOF'
package x
const a = "\x1b[31m"
const b = "\033[0m"
const c = "\e[1m"
EOF
cat > "$tmp/src/colors.ts" <<'EOF'
const a = "[31m";
const b = "\u{1b}[0m";
EOF
# clean: routes through a lib, no literal escapes
cat > "$tmp/src/clean.go" <<'EOF'
package x
import "term"
func f() { term.Red("hi") } // no hardcoded escapes; [ alone is fine: a[0]
EOF
# allowlisted rendering module owns the escapes
cat > "$tmp/render/ansi.go" <<'EOF'
package render
const Reset = "\x1b[0m"
EOF
echo "not source" > "$tmp/empty/readme.md"

assert_hit  "Go \\x1b[ literal"                  "colors.go"   "$tmp/src/colors.go"
assert_hit  "Go \\033[ and \\e[ literals"        "hardcoded ANSI/OSC escape literal" "$tmp/src/colors.go"
assert_hit  "TS \\u001b[ and \\u{1b}[ literals"  "colors.ts"   "$tmp/src/colors.ts"
# exact count: colors.go has 3 escape lines, colors.ts has 2 → 5 over the dir
got=$(python3 "$script" "$tmp/src" 2>/dev/null | grep -c "client-ansi smell:" || true)
if [ "$got" = 5 ]; then pass=$((pass+1)); echo "ok   - src finding count == 5"; else fail=$((fail+1)); echo "FAIL - src count: want 5 got $got"; fi
# regression (challenge R1): OSC escapes (\x1b] — hyperlink / OSC-52 clipboard) must be caught, not just CSI
cat > "$tmp/osc.ts" <<'EOF'
const link = "\x1b]8;;https://x.test\x07label\x1b]8;;\x07"
const clip = "\033]52;c;BASE64\007"
EOF
assert_hit  "OSC \\x1b] hyperlink/clipboard escape caught" "hardcoded ANSI/OSC escape literal" "$tmp/osc.ts"
assert_exit "clean source -> no finding (0)"        0 "$tmp/src/clean.go"
assert_exit "allowlisted render module exempt (0)"  0 "$tmp/render/ansi.go" "--allow=/render/"
# regression (challenge R2): --allow segment-anchored, must NOT exempt substring match
cat > "$tmp/src/surrender.ts" <<'EOF'
const c = "\x1b[31m"
EOF
assert_hit  "--allow=render does NOT exempt surrender.ts" "hardcoded ANSI/OSC escape literal" "$tmp/src/surrender.ts" --allow=render
# regression (challenge R2): .mts scanned + padded-zero \u{001b} caught (printf %s keeps literal text)
printf '%s\n' 'const a = "\u{001b}[31m"' > "$tmp/mod.mts"
assert_hit  ".mts + padded \\u{001b} caught" "hardcoded ANSI/OSC escape literal" "$tmp/mod.mts"
assert_exit "missing path -> inconclusive (2)"      2 "$tmp/src/nope.go"
assert_exit "unsupported file -> inconclusive (2)"  2 "$tmp/empty/readme.md"
assert_exit "dir without source -> inconclusive (2)" 2 "$tmp/empty"

echo "----"; echo "passed=$pass failed=$fail"; [ "$fail" -eq 0 ]
