#!/usr/bin/env bash
# Test harness for client-terminal-ansi-check.py (CB-1) — proves it catches hardcoded ANSI
# escape literals across forms/languages, exempts the allowlisted rendering module, does not
# false-positive on clean source, and is inconclusive (not clean) on bad scope.
# Run: bash client-terminal-ansi-check.test.sh   (honors $TMPDIR; needs python3)
set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
script="$here/client-terminal-ansi-check.py"
command -v python3 >/dev/null 2>&1 || { echo "python3 required" >&2; exit 2; }
tmp="$(mktemp -d "${TMPDIR:-/tmp}/cbansi.XXXXXX")"
trap 'rm -rf "$tmp"' EXIT

pass=0 fail=0
cp "$script" "$tmp/checker_copy.py"
if python3 -B -W error -m py_compile "$tmp/checker_copy.py" 2>"$tmp/pycompile.err"; then
  pass=$((pass+1)); echo "ok   - py_compile under -W error has zero SyntaxWarning"
else
  fail=$((fail+1)); echo "FAIL - py_compile under -W error: $(cat "$tmp/pycompile.err")"
fi
# Here-string, not a pipe: under pipefail `grep -q` exits on the first match and the
# writer can take SIGPIPE, turning a real match into a false failure.
assert_hit() { local desc="$1" want="$2"; shift 2
  set +e; local out rc; out="$(python3 -B -W error "$script" "$@" 2>/dev/null)"; rc=$?; set -e
  if [ "$rc" = 1 ] && grep -qF "$want" <<<"$out"; then pass=$((pass+1)); echo "ok   - $desc"
  else fail=$((fail+1)); echo "FAIL - $desc (rc=$rc, want '$want', out='$out')"; fi; }
assert_exit() { local desc="$1" want="$2"; shift 2
  set +e; python3 -B -W error "$script" "$@" >/dev/null 2>&1; local rc=$?; set -e
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
got=$(python3 -B -W error "$script" "$tmp/src" 2>/dev/null | grep -c "client-ansi smell:" || true)
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
# lexical segment normalization: .. traversal must NOT inherit parent segment exemption,
# --allow=.. / --allow=. must NOT wildcard relative paths, and --allow=./render must exempt render/ansi.go.
assert_hit  "--allow=render does NOT exempt render/../src/colors.go traversal" "hardcoded ANSI/OSC escape literal" "$tmp/render/../src/colors.go" --allow=render
if (cd "$tmp/render" && python3 -B -W error "$script" "../src/colors.go" --allow=.. >/dev/null 2>&1); then
  fail=$((fail+1)); echo "FAIL - --allow=.. exempted ../src/colors.go"
else
  rc=$?
  if [ "$rc" = 1 ]; then pass=$((pass+1)); echo "ok   - --allow=.. does NOT exempt ../src/colors.go"
  else fail=$((fail+1)); echo "FAIL - --allow=.. expected exit 1, got $rc"; fi
fi
if (cd "$tmp" && python3 -B -W error "$script" "render/ansi.go" --allow=./render >/dev/null 2>&1); then
  pass=$((pass+1)); echo "ok   - --allow=./render exempts render/ansi.go (0)"
else
  fail=$((fail+1)); echo "FAIL - --allow=./render rejected render/ansi.go"
fi
assert_hit  "--allow=. does NOT wildcard src/colors.go" "hardcoded ANSI/OSC escape literal" "$tmp/src/colors.go" --allow=.
assert_hit  "--allow=render/../src does NOT collapse to exempt src/" "hardcoded ANSI/OSC escape literal" "$tmp/src/colors.go" "--allow=render/../src"
mkdir -p "$tmp/other/nested" "$tmp/other/render"
cp "$tmp/src/colors.go" "$tmp/other/render/colors.go"
ln -s "$tmp/other/nested" "$tmp/src/link"
assert_hit  "symlink-parent src/link/../render/colors.go NOT exempted by --allow=src/render" "hardcoded ANSI/OSC escape literal" "$tmp/src/link/../render/colors.go" "--allow=src/render"
rm -f "$tmp/src/link"
# ancestor directory named `render` above the checkout must NOT exempt files outside the renderer
mkdir -p "$tmp/render/checkout/.git" "$tmp/render/checkout/src" "$tmp/render/checkout/render"
cp "$tmp/src/colors.go" "$tmp/render/checkout/src/colors.go"
cp "$tmp/render/ansi.go" "$tmp/render/checkout/render/ansi.go"
if (cd "$tmp/render/checkout" && python3 -B -W error "$script" "src/colors.go" --allow=render >/dev/null 2>&1); then
  fail=$((fail+1)); echo "FAIL - ancestor render/ exempted relative src/colors.go"
else
  rc=$?
  if [ "$rc" = 1 ]; then pass=$((pass+1)); echo "ok   - ancestor render/ does NOT exempt relative src/colors.go"
  else fail=$((fail+1)); echo "FAIL - ancestor render/ relative scan expected exit 1, got $rc"; fi
fi
assert_hit  "ancestor render/ does NOT exempt checkout/src/colors.go" "hardcoded ANSI/OSC escape literal" "$tmp/render/checkout/src/colors.go" --allow=render
assert_exit "checkout/render/ansi.go inside ancestor render/ still exempt (0)" 0 "$tmp/render/checkout/render/ansi.go" --allow=render
ln -s "$tmp/other/render" "$tmp/render/checkout/src/ext_render"
assert_hit  "symlink escaping checkout root NOT exempted by --allow=render" "hardcoded ANSI/OSC escape literal" "$tmp/render/checkout/src/ext_render/colors.go" --allow=render
rm -f "$tmp/render/checkout/src/ext_render"
ln -s "../src/colors.go" "$tmp/render/checkout/render/link_to_src.go"
assert_hit  "symlink render/link_to_src.go -> ../src/colors.go NOT exempted by --allow=render" "hardcoded ANSI/OSC escape literal" "$tmp/render/checkout/render/link_to_src.go" --allow=render
rm -f "$tmp/render/checkout/render/link_to_src.go"
ln -s "$tmp/src/colors.go" "$tmp/render/checkout/render/ext_link.go"
assert_hit  "symlink render/ext_link.go escaping checkout NOT exempted by --allow=render" "hardcoded ANSI/OSC escape literal" "$tmp/render/checkout/render/ext_link.go" --allow=render
rm -f "$tmp/render/checkout/render/ext_link.go"
mkdir -p "$tmp/ext_repo/.git" "$tmp/ext_repo/render"
cp "$tmp/src/colors.go" "$tmp/ext_repo/render/colors.go"
ln -s "$tmp/ext_repo" "$tmp/render/checkout/ext_dir_link"
assert_hit  "absolute symlinked directory checkout/ext_dir_link NOT exempted by --allow=render" "hardcoded ANSI/OSC escape literal" "$tmp/render/checkout/ext_dir_link" --allow=render
rm -f "$tmp/render/checkout/ext_dir_link"
mkdir -p "$tmp/markerless/render/nested" "$tmp/markerless/src"
cp "$tmp/render/ansi.go" "$tmp/markerless/render/nested/ansi.go"
cp "$tmp/src/clean.go" "$tmp/markerless/src/clean.go"
assert_exit "markerless parent directory scan exempts render/nested/ansi.go (0)" 0 "$tmp/markerless" --allow=render
assert_exit "markerless render directory scan exempts render/nested/ansi.go (0)" 0 "$tmp/markerless/render" --allow=render
assert_exit "markerless explicit nested file scan exempts render/nested/ansi.go (0)" 0 "$tmp/markerless/render/nested/ansi.go" --allow=render
cp "$tmp/src/colors.go" "$tmp/markerless/src/colors.go"
ln -s "../../src/colors.go" "$tmp/markerless/render/nested/escape.go"
assert_hit  "markerless symlink render/nested/escape.go -> ../../src/colors.go NOT exempted" "hardcoded ANSI/OSC escape literal" "$tmp/markerless/render/nested/escape.go" --allow=render
rm -f "$tmp/markerless/render/nested/escape.go"
rm -f "$tmp/markerless/src/colors.go"
ln -s "$tmp/other/render/colors.go" "$tmp/markerless/src/ext_sym.go"
assert_hit  "markerless directory scan does NOT exempt escaping symlink to sibling render/" "hardcoded ANSI/OSC escape literal" "$tmp/markerless" --allow=render
rm -f "$tmp/markerless/src/ext_sym.go"
bs_dir="$tmp/markerless_bs/render\\box"
mkdir -p "$bs_dir"
cp "$tmp/src/colors.go" "$bs_dir/colors.go"
assert_hit  "POSIX literal backslash in render\\box directory name NOT split as render/" "hardcoded ANSI/OSC escape literal" "$bs_dir/colors.go" --allow=render
# regression (challenge R2): .mts scanned + padded-zero \u{001b} caught (printf %s keeps literal text)
printf '%s\n' 'const a = "\u{001b}[31m"' > "$tmp/mod.mts"
assert_hit  ".mts + padded \\u{001b} caught" "hardcoded ANSI/OSC escape literal" "$tmp/mod.mts"
assert_exit "missing path -> inconclusive (2)"      2 "$tmp/src/nope.go"
assert_exit "unsupported file -> inconclusive (2)"  2 "$tmp/empty/readme.md"
assert_exit "dir without source -> inconclusive (2)" 2 "$tmp/empty"
walk_probe="$(python3 -B -W error - "$tmp/checker_copy.py" "$tmp/empty" <<'PY'
import contextlib, io, importlib.util, os, sys
spec = importlib.util.spec_from_file_location("cbansi", sys.argv[1])
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)
orig_walk = os.walk
def fake_walk(top, onerror=None, **kw):
    if onerror is not None:
        onerror(PermissionError(13, "Permission denied", top))
    return iter(())
os.walk = fake_walk
err = io.StringIO()
try:
    with contextlib.redirect_stderr(err):
        rc = mod.main([sys.argv[2]])
finally:
    os.walk = orig_walk
print(f"rc={rc} err={err.getvalue().strip()}")
PY
)"
if grep -q '^rc=2 ' <<<"$walk_probe" && grep -qF "cannot read part of scope" <<<"$walk_probe"; then
  pass=$((pass+1)); echo "ok   - deterministic walk_errs probe reports cannot read part of scope (2)"
else
  fail=$((fail+1)); echo "FAIL - deterministic walk_errs probe ($walk_probe)"
fi
if [ "$(id -u)" -ne 0 ]; then
  mkdir -p "$tmp/locked_parent/sub"
  cp "$tmp/src/colors.go" "$tmp/locked_parent/sub/colors.go"
  chmod 000 "$tmp/locked_parent/sub"
  set +e; lock_err="$(python3 -B -W error "$script" "$tmp/locked_parent" 2>&1 >/dev/null)"; lock_rc=$?; set -e
  chmod 700 "$tmp/locked_parent/sub"
  if [ "$lock_rc" = 2 ] && grep -qF "cannot read part of scope" <<<"$lock_err"; then
    pass=$((pass+1)); echo "ok   - unreadable subdir reports cannot read part of scope (2)"
  else
    fail=$((fail+1)); echo "FAIL - unreadable subdir diagnostic (rc=$lock_rc, err='$lock_err')"
  fi
fi

echo "----"; echo "passed=$pass failed=$fail"; [ "$fail" -eq 0 ]
