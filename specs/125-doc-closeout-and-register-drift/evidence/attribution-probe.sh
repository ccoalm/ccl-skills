#!/usr/bin/env bash
# Rebuild the per-case attribution matrix recorded in mutation-walk.txt.
#
# Why this exists: the shipped suite is fail-fast, so a guard mutation reds the
# earliest affected case and later cases never run — per-case attribution is
# impossible there. This builds ONE single-case copy per added case, applies one
# guard mutant at a time, and reports every cell. Three earlier attribution
# attempts were withdrawn because a cell was inferred instead of run, or because
# the probes were ephemeral and could not be checked.
#
# It never touches the caller's checkout. A first version did — fixed probe
# filenames written beside the live guard, deleted on exit whether or not they
# pre-existed, and the guard restored unconditionally from a start-of-run backup,
# which discards a concurrent edit and makes two overlapping runs collide. That
# was raised as a P1 in this round's review. Everything now happens inside a
# detached worktree of the commit under test, so the working tree is read once
# (to resolve the repository) and never written.
#
# Usage: bash specs/125-doc-closeout-and-register-drift/evidence/attribution-probe.sh [commit-ish]
# Default commit-ish is HEAD; uncommitted changes are deliberately NOT probed,
# because what the matrix attributes is the committed candidate.
set -euo pipefail

REF="${1:-HEAD}"
ROOT="$(git rev-parse --show-toplevel)"
COMMIT="$(git -C "$ROOT" rev-parse --verify "${REF}^{commit}")"

TMP="$(mktemp -d "${TMPDIR:-/tmp}/attrprobe.XXXXXX")"
WT="$TMP/tree"
cleanup() {
  git -C "$ROOT" worktree remove --force "$WT" >/dev/null 2>&1 || true
  rm -rf "$TMP"
}
trap cleanup EXIT

git -C "$ROOT" worktree add --detach --quiet "$WT" "$COMMIT"

SUITE="$WT/skills/skill-extraction-workflow/scripts/test_register_firing_path_resolution.sh"
GUARD="$WT/skills/skill-extraction-workflow/scripts/register-firing-path-resolution.rb"
[ -f "$SUITE" ] && [ -f "$GUARD" ] || { echo "FAIL: suite or guard not found at $COMMIT" >&2; exit 1; }
PRISTINE="$TMP/guard.pristine"; cp "$GUARD" "$PRISTINE"

# Probes live beside the guard INSIDE the disposable worktree; the suite
# resolves the guard from its own directory, so they cannot live elsewhere.
PROBE_DEL="$(dirname "$GUARD")/_attr_probe_deletion.sh"
PROBE_BND="$(dirname "$GUARD")/_attr_probe_boundary.sh"
# Containment is asserted as ONE invariant rather than enumerated per symlink
# shape. Three shapes were reported one at a time — a dangling link at the final
# component, a symlinked guard, then a symlinked PARENT directory that O_EXCL
# still resolves through — and each patch only closed the shape that was named.
# The property every one of them violates is the same: after resolution, every
# path this script reads or writes must sit beneath the disposable worktree.
# `realpath` resolves the whole chain, so parents, final components and the
# guard are covered by the single test below, and a shape nobody has thought of
# yet is covered too.
WT_REAL="$(cd "$WT" && pwd -P)" || { echo "FAIL: cannot resolve the probe worktree" >&2; exit 1; }
# Resolving the parent and then APPENDING the basename is not the invariant: a
# guard that is itself a symlink out of the tree yields a resolved-looking path
# that passes while `cp` and `open` follow the link. Both halves are required —
# the parent must resolve inside the tree AND the final component must not be a
# link — and together they constrain the whole path.
assert_inside_worktree() { # assert_inside_worktree <path> <what>
  local resolved
  resolved="$(cd "$(dirname "$1")" 2>/dev/null && pwd -P)" \
    || { echo "FAIL: cannot resolve the directory holding $2 ($1)" >&2; exit 1; }
  case "$resolved" in
    "$WT_REAL"|"$WT_REAL"/*) : ;;
    *) echo "FAIL: $2 sits outside the disposable worktree: $1 -> $resolved" >&2; exit 1 ;;
  esac
  if [ -L "$1" ]; then
    echo "FAIL: $2 is a symlink; refusing to follow it out of the worktree: $1" >&2; exit 1
  fi
}
assert_inside_worktree "$GUARD" "the guard"
assert_inside_worktree "$SUITE" "the suite"
for probe in "$PROBE_DEL" "$PROBE_BND"; do
  assert_inside_worktree "$probe" "a probe"
  if [ -e "$probe" ] || [ -L "$probe" ]; then
    echo "FAIL: refusing to overwrite $probe" >&2; exit 1
  fi
done

python3 - "$SUITE" "$PROBE_DEL" "$PROBE_BND" <<'PY'
import sys
suite, out_del, out_bnd = sys.argv[1], sys.argv[2], sys.argv[3]
s = open(suite).read()
head = s[:s.index('# ── 1. GREEN control')]
i = s.index('# ── N. RED: the anchored list rule DELETED outright')
k = s.index('# ── N+1. GREEN by design')
j = s.index('[ "$passed" -eq 59 ]')
tail = '[ "$passed" -eq 1 ] || fail "expected 1 assertion, saw $passed"\necho "isolated_case_ok ($passed)"\n'
# 'x' is O_CREAT|O_EXCL: it fails rather than following a symlink planted at
# the target path, so a probe can never be written outside this worktree.
with open(out_del, 'x') as fh:
    fh.write(head + s[i:k] + tail)
with open(out_bnd, 'x') as fh:
    fh.write(head + s[k:j] + tail)
PY

ORIG='        next if body.include?(anchor)'
MUT1='        next if body.lines.any? { |ln| ln.strip == anchor.strip }'
MUT2='        next # MUTANT: never report a missing anchor'

apply_mutant() {
  cp "$PRISTINE" "$GUARD"
  python3 - "$GUARD" "$ORIG" "$1" <<'PY'
import sys
p, old, new = sys.argv[1], sys.argv[2], sys.argv[3]
s = open(p).read()
assert s.count(old) == 1, f"expected exactly one occurrence of the mutated line, saw {s.count(old)}"
open(p, 'w').write(s.replace(old, new))
PY
}

# Every cell states the rc it must produce, and a mismatch is fatal. A first
# version only printed each cell and always exited 0, so a caller checking the
# exit status would read a matrix that never reproduced as success — raised in
# this round's review.
mismatches=0
# An exit code alone does not attribute a cell: a fixture that fails to build,
# or a pre-check that trips, also exits 1, and an earlier version counted that
# as a reproduced red. Each cell therefore also declares the diagnostic its own
# assertion must emit, so infrastructure failure cannot be read as attribution.
cell() { # cell <probe> <expected-rc> <expected-marker-regex>
  set +e
  out="$(bash "$1" 2>&1)"; rc=$?
  # grep exits 1 when the probe emitted no recognized marker at all (a syntax
  # error in the tested commit, say). Under `set -euo pipefail` that status
  # would kill this script mid-matrix and print nothing, so marker extraction
  # stays inside the relaxed region and an empty result is a MISMATCH, not a
  # silent abort.
  local mark="" line first_line
  line="$(printf '%s\n' "$out" | grep -E '^(FAIL|isolated_case_ok)' | head -1)"
  set -e
  if [ "$rc" != "$2" ]; then
    mark="  <-- MISMATCH: expected rc=$2"; mismatches=$((mismatches + 1))
  elif [ -z "$line" ]; then
    first_line="${out%%$'\n'*}"   # parameter expansion: no pipeline, so no SIGPIPE
    line="<no FAIL/isolated_case_ok line; first output line: ${first_line}>"
    mark="  <-- MISMATCH: the cell produced no recognized marker"
    mismatches=$((mismatches + 1))
  elif ! printf '%s\n' "$line" | grep -qE "$3"; then
    mark="  <-- MISMATCH: rc=$2 but the cell never reached its own assertion (expected /$3/)"
    mismatches=$((mismatches + 1))
  fi
  printf 'rc=%s  %s%s\n' "$rc" "$line" "$mark"
}
OK_MARK='^isolated_case_ok'
BND_RED='^FAIL: expected rc=0 got rc=1 \(gutting text outside the anchor'
DEL_RED='^FAIL: expected rc=1 got rc=0 \(deleting the anchored rule outright'

echo "== probing commit $COMMIT in a detached worktree =="
echo "== control =="
printf 'deletion  '; cell "$PROBE_DEL" 0 "$OK_MARK"
printf 'boundary  '; cell "$PROBE_BND" 0 "$OK_MARK"
echo "== mutant 1: substring match becomes whole-line equality =="
apply_mutant "$MUT1"; printf 'deletion  '; cell "$PROBE_DEL" 0 "$OK_MARK"; printf 'boundary  '; cell "$PROBE_BND" 1 "$BND_RED"
echo "== mutant 2: a missing anchor is never reported =="
apply_mutant "$MUT2"; printf 'deletion  '; cell "$PROBE_DEL" 1 "$DEL_RED"; printf 'boundary  '; cell "$PROBE_BND" 0 "$OK_MARK"
cp "$PRISTINE" "$GUARD"
echo "== restored =="
printf 'deletion  '; cell "$PROBE_DEL" 0 "$OK_MARK"
printf 'boundary  '; cell "$PROBE_BND" 0 "$OK_MARK"

if [ "$mismatches" -ne 0 ]; then
  echo "attribution_probe_failed: $mismatches cell(s) did not reproduce" >&2
  exit 1
fi
echo "attribution_probe_ok (8 cells reproduced)"
