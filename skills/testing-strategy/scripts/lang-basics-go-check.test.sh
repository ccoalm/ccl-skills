#!/usr/bin/env bash
# Test harness for lang-basics-go-check.go — builds the checker, then proves it flags
# context.Background()/TODO() outside entry funcs, exempts ONLY main/init (a production func
# named Test* is NOT exempt), resolves alias/dot imports, skips _test.go, and is inconclusive
# (not clean) on bad scope.
# Run: bash lang-basics-go-check.test.sh   (honors $TMPDIR; needs the Go toolchain)
set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
src="$here/lang-basics-go-check.go"
command -v go >/dev/null 2>&1 || { echo "go toolchain required" >&2; exit 2; }
base="${TMPDIR:-/tmp}"
tmp="$(mktemp -d "${base%/}/lbgo.XXXXXX")"
trap 'rm -rf "$tmp"' EXIT

bin="$tmp/lbgo"
go build -o "$bin" "$src"

pass=0 fail=0
assert_hit() { # <desc> <expect-substr> <path...>
  local desc="$1" want="$2"; shift 2
  set +e; local out rc; out="$("$bin" "$@" 2>/dev/null)"; rc=$?; set -e
  if [ "$rc" = 1 ] && printf '%s' "$out" | grep -qF "$want"; then
    pass=$((pass+1)); echo "ok   - $desc"
  else
    fail=$((fail+1)); echo "FAIL - $desc (rc=$rc, want '$want', out='$out')"
  fi
}
assert_exit() { # <desc> <expected-exit> <path...>
  local desc="$1" want="$2"; shift 2
  set +e; "$bin" "$@" >/dev/null 2>&1; local rc=$?; set -e
  if [ "$rc" = "$want" ]; then pass=$((pass+1)); echo "ok   - $desc"; else fail=$((fail+1)); echo "FAIL - $desc (want exit $want, got $rc)"; fi
}

mkdir -p "$tmp/svc" "$tmp/tonly"
cat > "$tmp/svc/positive.go" <<'EOF'
package svc
import "context"
func Handle() error { ctx := context.Background(); return do(ctx) }
func Repo() { _ = context.TODO() }
EOF
cat > "$tmp/svc/clean.go" <<'EOF'
package svc
import "context"
func Handle(ctx context.Context) error { return do(ctx) }
func main() { _ = context.Background() }
func init() { _ = context.TODO() }
EOF
cat > "$tmp/tonly/x_test.go" <<'EOF'
package svc
import "context"
func TestX() { _ = context.Background() }
EOF
mkdir -p "$tmp/extra"
cat > "$tmp/extra/alias.go" <<'EOF'
package svc
import ctx "context"
func Fetch() { _ = ctx.Background() }
EOF
cat > "$tmp/extra/dot.go" <<'EOF'
package svc2
import . "context"
func Fetch2() { _ = Background() }
EOF
cat > "$tmp/extra/prodtest.go" <<'EOF'
package svc3
import "context"
func TestConnection() { _ = context.Background() }
EOF
cat > "$tmp/extra/pkglevel.go" <<'EOF'
package svc4
import "context"
var bg = context.Background()
EOF
cat > "$tmp/extra/rawimport.go" <<'EOF'
package svc5
import `context`
func Fetch5() { _ = context.Background() }
EOF
# vendor-skip regression: a Background() inside vendor/ must NOT be reported on a parent scan
mkdir -p "$tmp/vend/vendor"
cat > "$tmp/vend/svc.go" <<'EOF'
package vend
import "context"
func Clean(ctx context.Context) { _ = ctx }
EOF
cat > "$tmp/vend/vendor/bad.go" <<'EOF'
package vendored
import "context"
func Bad() { _ = context.Background() }
EOF

assert_hit  "Background()/TODO() in non-entry funcs flagged" "context.Background()" "$tmp/svc/positive.go"
assert_hit  "aliased import (import ctx \"context\") caught"  "context.Background()" "$tmp/extra/alias.go"
assert_hit  "dot-import Background() caught"                  "dot-import"           "$tmp/extra/dot.go"
assert_hit  "production func named Test* NOT exempted"        "context.Background()" "$tmp/extra/prodtest.go"
assert_hit  "package-level var = context.Background() caught"  "package-level"       "$tmp/extra/pkglevel.go"
assert_hit  "raw-string import path (backticks) caught"       "context.Background()" "$tmp/extra/rawimport.go"
assert_exit "vendor/ Background not reported on parent scan"  0   "$tmp/vend"
assert_hit  "TODO() flagged too"                             "context.TODO()"       "$tmp/svc/positive.go"
assert_exit "dir scan: positive present -> 1"          1    "$tmp/svc"
assert_exit "clean (ctx param; main/init exempt) -> 0" 0    "$tmp/svc/clean.go"
assert_exit "dir with only _test.go -> inconclusive 2" 2    "$tmp/tonly"
assert_exit "explicit _test.go file arg -> (2)"        2    "$tmp/tonly/x_test.go"
assert_exit "missing path -> setup (2)"                2    "$tmp/svc/nope.go"

echo "----"
echo "passed=$pass failed=$fail"
[ "$fail" -eq 0 ]
