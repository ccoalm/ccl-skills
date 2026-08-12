#!/usr/bin/env bash
# Behavior suite for check-ccl-skills.sh's `git_identity_predicate_scan` gate
# (recurring-anti-patterns-checklist.md, Anti-pattern 27).
#
# The gate exists because a path-shaped identity predicate fails OPEN and silently:
# nothing errors, no log line appears, and the owning suite stays green because its
# fixtures are all built in the conventional layout. So the gate's own value rests
# entirely on it being able to FAIL — a check that can only ever say "ok" is
# indistinguishable from a passing property. Every probe here therefore pins one
# direction of that: the planted-violation probes prove it fires, and the carve-out
# probes prove it does not fire on the legitimate spellings (a gate that flags the
# fix's own documentation, or a fixture's containment assertion, gets loosened by the
# next maintainer and stops catching anything).
#
#   bash skills/skill-extraction-workflow/scripts/test_git_identity_predicate_gate.sh
set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd -P)"
CHECKER="${CHECKER:-$SCRIPT_DIR/check-ccl-skills.sh}"
[ -f "$CHECKER" ] || { echo "FAIL: checker not found: $CHECKER" >&2; exit 1; }

pass=0; fail=0; skipped=0; skipped_labels=""
note() { fail=$((fail+1)); printf 'FAIL  %s\n' "$1" >&2; }
ok()   { pass=$((pass+1)); }
# Two probes need an unreadable path as their PRECONDITION. Some environments cannot
# produce one (root, or a filesystem/container that ignores the mode) — that is an
# environment capability, not a defect in the code under test, so failing there would
# red-line CI for the wrong reason. It must not become a silent skip either, so a skip
# is printed, counted, reported in the summary line, and allowed ONLY for these two
# named probes; any other probe reaching skip() is itself a failure.
skip() { # skip <label> <reason>
  case "$1" in
    p11|p11b) skipped=$((skipped+1)); skipped_labels="$skipped_labels $1"
              printf 'SKIP  %s: %s (uid=%s)\n' "$1" "$2" "$(id -u)" >&2 ;;
    *) note "$1: skip() is not permitted for this probe (reason was: $2)" ;;
  esac
}

TMP=$(mktemp -d "${TMPDIR:-/tmp}/git-identity-gate-test.XXXXXX") || exit 1
TMP=$(cd "$TMP" && pwd -P)
trap 'rm -rf "$TMP"' EXIT

# The gate is one section of a long checker, so run the section in isolation rather
# than standing up a whole synthetic skill tree: extract it and drive it with $root.
section=$TMP/gate-section.sh
{
  echo '#!/usr/bin/env bash'
  # MUST match the host checker's options. Running the section under laxer settings is
  # how a section that aborts the real checker (a bare `v=$(grep ...)` exiting on a
  # no-match under `set -e`) still passes every probe here.
  echo 'set -euo pipefail'
  echo 'root="$1"'
  awk '/^# Anti-pattern 27 —/{p=1} p; /^echo "git_identity_predicate_scan_ok"$/{if(p) exit}' "$CHECKER"
} > "$section"
grep -q 'git_identity_predicate_scan_ok' "$section" \
  || { echo "FAIL: could not extract the gate section from $CHECKER (anchor moved?)" >&2; exit 1; }
grep -q 'worktrees' "$section" \
  || { echo "FAIL: extracted section carries no predicate — extraction is bogus" >&2; exit 1; }

run_gate() { # run_gate <root> -> RC, OUT
  OUT=$( bash "$section" "$1" 2>&1 ); RC=$?
}

mk_root() { # mk_root <name> -> echoes a fresh root with empty hooks/ and scripts/
  local r="$TMP/$1"; mkdir -p "$r/hooks" "$r/scripts/nested"; printf '%s' "$r"
}

# --- P1: a clean tree passes ------------------------------------------------
r=$(mk_root clean)
printf '#!/usr/bin/env bash\ngd=$(git rev-parse --path-format=absolute --git-common-dir)\n' > "$r/hooks/ok.sh"
run_gate "$r"
if [ "$RC" -eq 0 ] && printf '%s' "$OUT" | grep -q 'git_identity_predicate_scan_ok'; then ok
else note "p1 clean tree must pass with the ok token (rc=$RC): $OUT"; fi

# --- P2: the violation fires (this is the gate's whole reason to exist) ------
r=$(mk_root violation)
printf '#!/usr/bin/env bash\ncase "$absgitdir" in\n  */worktrees/*) exit 0 ;;\nesac\n' > "$r/hooks/guard.sh"
run_gate "$r"
if [ "$RC" -ne 0 ] && printf '%s' "$OUT" | grep -q 'git_identity_predicate_scan_failed'; then ok
else note "p2 planted path-name predicate must FAIL the gate (rc=$RC): $OUT"; fi

# --- P2b: the report names the offending file and line ----------------------
if printf '%s' "$OUT" | grep -q 'hooks/guard.sh:2' || printf '%s' "$OUT" | grep -q 'hooks/guard.sh:3'; then ok
else note "p2b failure output must locate the hit (file:line), got: $OUT"; fi

# --- P2c: the QUOTED spelling is the same predicate and must also fire ------
# `*"/worktrees/"*` matches identically in bash, so a gate that only knows the
# bare spelling is bypassed by ordinary quoting style — not even deliberate evasion.
r=$(mk_root quoted)
printf '#!/usr/bin/env bash\ncase "$absgitdir" in *"/worktrees/"*) exit 0 ;; esac\n' > "$r/hooks/quoted.sh"
run_gate "$r"
if [ "$RC" -ne 0 ]; then ok; else note "p2c quoted glob spelling must fire (rc=$RC): $OUT"; fi

# --- P2d: an ordinary cleanup glob over a worktrees path is NOT a predicate --
# `.work/worktrees/*` is a path, not a match pattern; flagging it would make the
# gate unusable for the very teardown scripts this repo's worktree convention needs.
r=$(mk_root cleanup)
printf '#!/usr/bin/env bash\nrm -rf "$root"/.work/worktrees/*\nls .work/worktrees/*/\n' > "$r/scripts/cleanup.sh"
run_gate "$r"
if [ "$RC" -eq 0 ]; then ok; else note "p2d path glob over .work/worktrees/* must NOT fire (rc=$RC): $OUT"; fi

# --- P2e: DOCUMENTED SCOPE LIMIT — a backslash-continued pattern is not caught
# `*/worktrees/\<newline>*` is the same predicate to bash and does reproduce the
# defect, but matching is per physical line and joining continuations first would
# push every reported line number off the real source line. The gate declares this
# as recall limit #2 rather than pretending to cover it. This probe pins the CURRENT
# contract: if someone later adds continuation-joining, this probe must be updated
# deliberately — it must never drift silently in either direction.
r=$(mk_root continuation)
printf '#!/usr/bin/env bash\ncase "$gd" in\n  */worktrees/\\\n*) exit 0 ;;\nesac\n' > "$r/hooks/cont.sh"
run_gate "$r"
if [ "$RC" -eq 0 ]; then ok
else note "p2e continuation form is a DECLARED recall limit; the gate firing here means the declared contract is now wrong (rc=$RC): $OUT"; fi

# --- P3: the same violation under scripts/, incl. a nested dir --------------
r=$(mk_root nested)
printf '#!/usr/bin/env bash\n[[ "$gd" == */worktrees/* ]] && return 0\n' > "$r/scripts/nested/state.sh"
run_gate "$r"
if [ "$RC" -ne 0 ]; then ok; else note "p3 violation nested under scripts/ must fail (rc=$RC): $OUT"; fi

# --- P4: carve-out — a comment documenting the banned spelling is not a hit --
# The fix's own comment (and this checklist row) name the spelling; flagging them
# would make the gate unlandable and invite a maintainer to loosen the predicate.
r=$(mk_root comment)
printf '#!/usr/bin/env bash\n# never match */worktrees/* — use the common dir instead\n   # */worktrees/*\ngd=$(git rev-parse --git-common-dir)\n' > "$r/hooks/documented.sh"
run_gate "$r"
if [ "$RC" -eq 0 ]; then ok; else note "p4 comment-only mention must NOT fire (rc=$RC): $OUT"; fi

# --- P5: carve-out — a test fixture asserting containment is not a control ---
r=$(mk_root fixture)
printf '#!/usr/bin/env bash\ncase "$(git rev-parse --absolute-git-dir)" in\n  */worktrees/*) ;;\n  *) note "fixture premise broken" ;;\nesac\n' > "$r/hooks/test_thing.sh"
cp "$r/hooks/test_thing.sh" "$r/scripts/nested/test.sh"
run_gate "$r"
if [ "$RC" -eq 0 ]; then ok; else note "p5 test_*.sh / test.sh fixture must NOT fire (rc=$RC): $OUT"; fi

# --- P6: a violation in a NON-test file still fires when test files exist ----
# Guards against the carve-out being implemented as a whole-tree skip.
printf '#!/usr/bin/env bash\ncase "$gd" in */worktrees/*) exit 0 ;; esac\n' > "$r/hooks/real.sh"
run_gate "$r"
if [ "$RC" -ne 0 ]; then ok; else note "p6 carve-out must be per-file, not tree-wide (rc=$RC): $OUT"; fi

# --- P7: missing dirs are not an error (gate runs on partial trees) ---------
r="$TMP/empty"; mkdir -p "$r"
run_gate "$r"
if [ "$RC" -eq 0 ]; then ok; else note "p7 tree without hooks//scripts/ must pass quietly (rc=$RC): $OUT"; fi

# --- P8: the REAL repo is clean under this gate -----------------------------
# Pins the promoted class as actually eradicated, not merely described.
repo_root=$(cd "$SCRIPT_DIR/../../.." && pwd -P)
if [ -d "$repo_root/hooks" ]; then
  run_gate "$repo_root"
  if [ "$RC" -eq 0 ]; then ok; else note "p8 the repo itself must be clean under this gate (rc=$RC): $OUT"; fi
else
  note "p8 could not resolve the repo root from $SCRIPT_DIR (expected hooks/ at $repo_root)"
fi

# --- P9: a newline in a file name must not drop the file from the scan -----
# Newline-delimited traversal splits such a name into two non-existent paths and
# reports clean — a scan that never happened, wearing a pass.
r=$(mk_root newline)
nl_file=$(printf 'hooks/bad\nname.sh')
printf '#!/usr/bin/env bash\ncase "$g" in */worktrees/*) exit 0 ;; esac\n' > "$r/$nl_file" 2>/dev/null
if [ -f "$r/$nl_file" ]; then
  run_gate "$r"
  if [ "$RC" -ne 0 ]; then ok; else note "p9 file with a newline in its name must still be scanned (rc=$RC): $OUT"; fi
else
  note "p9 fixture: could not create a newline-named file (filesystem restriction)"
fi

# --- P10: a symlinked scan root must still be walked ------------------------
# `-type f` without `-L` skips symlinked dirs AND symlinked files, so an entire
# control surface can sit outside the scan while the gate reports ok.
r="$TMP/symlink"; mkdir -p "$r/real-hooks" "$r/scripts"
printf '#!/usr/bin/env bash\ncase "$g" in */worktrees/*) exit 0 ;; esac\n' > "$r/real-hooks/guard.sh"
ln -s "$r/real-hooks" "$r/hooks"
run_gate "$r"
if [ "$RC" -ne 0 ]; then ok; else note "p10 symlinked hooks/ dir must still be scanned (rc=$RC): $OUT"; fi

# --- P11: an unreadable file is UNKNOWN, never clean ------------------------
# grep exits 2; swallowing that prints the ok token for a file never inspected.
r=$(mk_root unreadable)
printf '#!/usr/bin/env bash\necho hi\n' > "$r/hooks/locked.sh"
chmod 000 "$r/hooks/locked.sh" 2>/dev/null
if [ -r "$r/hooks/locked.sh" ]; then
  skip p11 "file still readable after chmod 000; this environment cannot produce an unreadable path"
else
  run_gate "$r"
  if [ "$RC" -ne 0 ] && printf '%s' "$OUT" | grep -q 'git_identity_predicate_scan_error'; then ok
  else note "p11 unreadable file must raise a scan ERROR, not an ok (rc=$RC): $OUT"; fi
  chmod 644 "$r/hooks/locked.sh" 2>/dev/null
fi

# --- P11b: a FAILED walk is an error even when only one root exists ---------
# Gating the find-status check on "both roots exist" would silently accept an
# incomplete walk in the common single-root repo — the same fail-open shape the
# gate exists to stop.
# Fixture note: an UNREADABLE subdirectory is used rather than a symlink loop.
# Loop detection is find-implementation-dependent and was measured to be
# nondeterministic here (bfs is breadth-first: the same call returned 1 standalone
# and 0 moments later), so a loop fixture would be a flaky oracle — and a probe
# that intermittently passes for the wrong reason is worse than no probe.
r="$TMP/walkfail"; mkdir -p "$r/hooks/sub"
chmod 000 "$r/hooks/sub" 2>/dev/null
if find -L "$r/hooks" -name '*.sh' -type f >/dev/null 2>&1; then
  skip p11b "unreadable subdir did not make find fail; this environment cannot produce an unwalkable dir"
else
  run_gate "$r"
  if [ "$RC" -ne 0 ] && printf '%s' "$OUT" | grep -q 'git_identity_predicate_scan_error'; then ok
  else note "p11b incomplete walk (hooks/ only, unreadable subdir) must ERROR, not report clean (rc=$RC): $OUT"; fi
fi
chmod 755 "$r/hooks/sub" 2>/dev/null

# --- P12: the REAL checker entry actually reaches this gate -----------------
# Every probe above runs an extracted section. If control flow upstream in
# check-ccl-skills.sh ever returns before this gate (an early exit, a
# misplaced block), all of them stay green while the gate never runs in
# production — and the source-register row claims exactly that firing path
# (`command:...check-ccl-skills.sh`). Assert reachability through the real
# entry point. Only the token's presence is asserted, not the checker's overall
# exit code, so an unrelated gate failing elsewhere cannot make this flaky.
if [ -x "$repo_root/skills/skill-extraction-workflow/scripts/check-ccl-skills.sh" ] \
   || [ -f "$repo_root/skills/skill-extraction-workflow/scripts/check-ccl-skills.sh" ]; then
  real_out=$(cd "$repo_root" && bash skills/skill-extraction-workflow/scripts/check-ccl-skills.sh . 2>&1); real_rc=$?
  if printf '%s' "$real_out" | grep -q 'git_identity_predicate_scan_ok\|git_identity_predicate_scan_failed\|git_identity_predicate_scan_error'; then
    # A _failed/_error token that does not actually stop the checker would be a gate in
    # name only. The converse is NOT asserted: requiring rc=0 on _ok would make this probe
    # hostage to any unrelated gate elsewhere in the checker.
    if printf '%s' "$real_out" | grep -q 'git_identity_predicate_scan_failed\|git_identity_predicate_scan_error' && [ "$real_rc" -eq 0 ]; then
      note "p12 the real checker reported a gate violation but still exited 0 — the gate does not block"
    else ok; fi
  else note "p12 the real checker never reached this gate — the register's firing path is not live: $(printf '%s' "$real_out" | tail -3)"; fi
else
  note "p12 could not locate check-ccl-skills.sh at $repo_root to prove the firing path"
fi

# Self-pin: a deleted or commented-out probe must fail the suite, not shrink it.
EXPECTED_PROBES=17
actual_probes=$(grep -cE '^[[:space:]]*(ok$|ok;|if \[ "\$RC")' "$0")
echo "git_identity_predicate_gate: $pass passed, $fail failed, $skipped skipped${skipped_labels:+ ($skipped_labels )}"
[ "$((pass + fail + skipped))" -eq "$EXPECTED_PROBES" ] \
  || { echo "FAIL: suite self-pin: expected $EXPECTED_PROBES probe outcomes, accounted for $((pass + fail + skipped))" >&2; exit 1; }
[ "$fail" -eq 0 ] && echo "test_git_identity_predicate_gate_ok"
[ "$fail" -eq 0 ]
