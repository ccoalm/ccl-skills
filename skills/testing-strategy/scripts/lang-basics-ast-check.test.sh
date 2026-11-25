#!/usr/bin/env bash
# Test harness for lang-basics-ast-check.py — proves it catches the grep-bypass forms,
# does not false-positive on legit returns, and is inconclusive (not clean) on bad scope.
# Run: bash lang-basics-ast-check.test.sh   (honors $TMPDIR; needs python3)
set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
script="$here/lang-basics-ast-check.py"
command -v python3 >/dev/null 2>&1 || { echo "python3 required" >&2; exit 2; }
tmp="$(mktemp -d "${TMPDIR:-/tmp}/lbast.XXXXXX")"
trap 'rm -rf "$tmp"' EXIT

pass=0 fail=0
cp "$script" "$tmp/checker_copy.py"
if python3 -B -W error -m py_compile "$tmp/checker_copy.py" 2>"$tmp/pycompile.err"; then
  pass=$((pass+1)); echo "ok   - py_compile under -W error has zero SyntaxWarning"
else
  fail=$((fail+1)); echo "FAIL - py_compile under -W error: $(cat "$tmp/pycompile.err")"
fi
assert_hit() { # <desc> <expect-substr> <path...>
  local desc="$1" want="$2"; shift 2
  set +e; local out rc; out="$(python3 -B -W error "$script" "$@" 2>/dev/null)"; rc=$?; set -e
  # Here-string, not a pipe: under pipefail `grep -q` exits on the first match and the
  # writer can take SIGPIPE, turning a real match into a false failure.
  if [ "$rc" = 1 ] && grep -qF "$want" <<<"$out"; then
    pass=$((pass+1)); echo "ok   - $desc"
  else
    fail=$((fail+1)); echo "FAIL - $desc (rc=$rc, want '$want', out='$out')"
  fi
}
assert_exit() { # <desc> <expected-exit> <path...>
  local desc="$1" want="$2"; shift 2
  set +e; python3 -B -W error "$script" "$@" >/dev/null 2>&1; local rc=$?; set -e
  if [ "$rc" = "$want" ]; then pass=$((pass+1)); echo "ok   - $desc"; else fail=$((fail+1)); echo "FAIL - $desc (want exit $want, got $rc)"; fi
}

mkdir -p "$tmp/t" "$tmp/empty"
cat > "$tmp/t/bypasses.py" <<'EOF'
def a(): return {"success": False}
def b(): return {'success': False}
def c(): return dict(success=False)
def d(): return {SUCCESS: False}
def e(): return {"ok": False, "error": msg}
def f(): return (None, msg)
def g(): return data, err
def i(): return {"success": False, "note": "# lb-allow: ignored-by-ast"}
def j(): return JSONResponse({"success": False, "error": "x"})
def o(): return JSONResponse(dict(success=False))
def p(): return {"success": False}, 400
EOF
cat > "$tmp/t/wrapped.py" <<'EOF'
def w(): return JSONResponse({"success": False})
EOF
cat > "$tmp/t/clean.py" <<'EOF'
def a(): raise DomainError(code=400, message="bad")
def b(): return {"data": items, "total": n}
def c(): return Result.err("x")
def d(): return lat, lng
def e(): return {"code": 200, "message": "ok", "data": d}
def f(): return None
def g(): return None, None
def h(): return {"ok": 0, "data": []}
def i(): return {"success": None}
def j(): return None, default
def k(): return None, fallback_value
def l(): return {"items": [{"success": False}]}
def r(): return {"items": [{"success": False}]}, 200
def m(): return {ok: False}
def n():
    # return {"success": False}  <- a comment, must be ignored
    s = "{'success': False}"
    return {"data": s}
def q(flag): return {"data": 1} if flag else {"data": 2}
EOF
cat > "$tmp/t/ternary.py" <<'EOF'
def t1(flag): return {"ok": True} if flag else {"ok": False}
def t2(flag): return {"success": False} if flag else {"data": 1}
def t3(flag): return JSONResponse({"ok": False} if flag else {"data": 1})
def t4(flag): return JSONResponse({"data": 1} if flag else {"ok": False})
EOF
cat > "$tmp/t/wrapped_orelse.py" <<'EOF'
def w_else(flag): return JSONResponse({"data": 1} if flag else {"ok": False})
EOF
printf 'def broken(:\n' > "$tmp/t/syntax.py"
echo "not python" > "$tmp/empty/readme.md"

assert_hit  "dict success/ok=False (any quote, constant key)" "dict success/ok=False" "$tmp/t/bypasses.py"
assert_hit  "dict(success=False) call form"                   "dict(success=False)"   "$tmp/t/bypasses.py"
assert_hit  "error tuple (data,err)/(None,msg)"               "error-tuple"           "$tmp/t/bypasses.py"
assert_hit  "constructor-wrapped fake dict (direct, by label)" "fake dict (constructor-wrapped)" "$tmp/t/wrapped.py"
assert_hit  "(body, status) tuple boundary response"         "(body, status) tuple"  "$tmp/t/bypasses.py"
# exact-count guard: bypasses.py has 11 fake-return lines (a,b,c,d,e,f,g,i,j,o,p); each → 1 finding.
got=$(python3 -B -W error "$script" "$tmp/t/bypasses.py" 2>/dev/null | grep -c "lang-basics-ast smell:" || true)
if [ "$got" = 11 ]; then pass=$((pass+1)); echo "ok   - bypasses.py finding count == 11"; else fail=$((fail+1)); echo "FAIL - bypasses.py count: want 11 got $got"; fi
assert_exit "clean returns -> no finding (0)"            0    "$tmp/t/clean.py"
assert_exit "syntax error -> inconclusive (2)"          2    "$tmp/t/syntax.py"
assert_exit "missing path -> setup (2)"                 2    "$tmp/t/nope.py"
assert_exit "non-.py file -> setup (2)"                 2    "$tmp/empty/readme.md"
assert_exit "dir without py -> setup (2)"               2    "$tmp/empty"
assert_exit "multi-scope w/ one empty dir -> (2)"       2    "$tmp/t" "$tmp/empty"
assert_hit  "IfExp ternary fake-success dict caught"    "dict success/ok=False" "$tmp/t/ternary.py"
assert_hit  "constructor-wrapped IfExp ternary fake dict caught" "fake dict (constructor-wrapped)" "$tmp/t/ternary.py"
assert_hit  "constructor-wrapped IfExp false-branch fake dict caught" "fake dict (constructor-wrapped)" "$tmp/t/wrapped_orelse.py"
tgot=$(python3 -B -W error "$script" "$tmp/t/ternary.py" 2>/dev/null | grep -c "lang-basics-ast smell:" || true)
if [ "$tgot" = 4 ]; then pass=$((pass+1)); echo "ok   - ternary.py finding count == 4"; else fail=$((fail+1)); echo "FAIL - ternary.py count: want 4 got $tgot"; fi
walk_probe="$(python3 -B -W error - "$tmp/checker_copy.py" "$tmp/empty" <<'PY'
import contextlib, io, importlib.util, os, sys
spec = importlib.util.spec_from_file_location("lbast", sys.argv[1])
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
  mkdir -p "$tmp/locked_py/sub"
  cp "$tmp/t/clean.py" "$tmp/locked_py/sub/clean.py"
  chmod 000 "$tmp/locked_py/sub"
  set +e; lock_err="$(python3 "$script" "$tmp/locked_py" 2>&1 >/dev/null)"; lock_rc=$?; set -e
  chmod 700 "$tmp/locked_py/sub"
  if [ "$lock_rc" = 2 ] && grep -qF "cannot read part of scope" <<<"$lock_err"; then
    pass=$((pass+1)); echo "ok   - unreadable subdir reports cannot read part of scope (2)"
  else
    fail=$((fail+1)); echo "FAIL - unreadable subdir diagnostic (rc=$lock_rc, err='$lock_err')"
  fi
fi

echo "----"
echo "passed=$pass failed=$fail"
[ "$fail" -eq 0 ]
