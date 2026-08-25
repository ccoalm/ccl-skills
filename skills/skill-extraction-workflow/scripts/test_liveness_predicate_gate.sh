#!/usr/bin/env bash
# Behavior suite for check-ccl-skills.sh's `liveness_predicate_scan` gate
# (recurring-anti-patterns-checklist.md, Anti-pattern 28).
#
# The gate exists because an existence-test liveness predicate fails in the direction
# that looks like a real defect: the probe reds, names the code under test, and the code
# under test was fine. Its value therefore rests on two properties that must BOTH be
# pinned — it fires on the shape that actually shipped, and it stays silent on the
# legitimate spellings. A gate that also flagged a ppid read used to identify a parent,
# or the fix's own documentation, is one a later maintainer loosens after the first false
# positive, and a loosened gate catches nothing.
#
#   bash skills/skill-extraction-workflow/scripts/test_liveness_predicate_gate.sh
set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd -P)"
CHECKER="${CHECKER:-$SCRIPT_DIR/check-ccl-skills.sh}"
[ -f "$CHECKER" ] || { echo "FAIL: checker not found: $CHECKER" >&2; exit 1; }

pass=0; fail=0
note() { fail=$((fail+1)); printf 'FAIL  %s\n' "$1" >&2; }
ok()   { pass=$((pass+1)); }

TMP=$(mktemp -d "${TMPDIR:-/tmp}/liveness-gate-test.XXXXXX") || exit 1
TMP=$(cd "$TMP" && pwd -P)
trap 'rm -rf "$TMP"' EXIT

# Run the gate section in isolation rather than standing up a whole synthetic skill tree.
section=$TMP/gate-section.sh
{
  echo '#!/usr/bin/env bash'
  # MUST match the host checker's options, or a section that aborts the real checker
  # still passes every probe here.
  echo 'set -euo pipefail'
  echo 'root="$1"'
  awk '/^# Anti-pattern 28 —/{p=1} p; /^echo "liveness_predicate_scan_ok"$/{if(p) exit}' "$CHECKER"
} > "$section"
grep -q 'liveness_predicate_scan_ok' "$section" \
  || { echo "FAIL: could not extract the gate section from $CHECKER (anchor moved?)" >&2; exit 1; }
grep -q 'ppid=' "$section" \
  || { echo "FAIL: extracted section carries no predicate — extraction is bogus" >&2; exit 1; }

run_gate() { # run_gate <root> -> RC, OUT
  OUT=$( bash "$section" "$1" 2>&1 ); RC=$?
}
mk_root() { local r="$TMP/$1"; mkdir -p "$r/scripts"; printf '%s' "$r"; }

# The banned spelling is assembled at runtime, never written literally in this file:
# this suite is itself a `test_*.sh` inside the scanned tree, so a literal would make the
# repo's own gate flag its regression test. (The scanner-matches-itself trap.)
PPID_READ='ps -o ppid= -p "$pid"'
VIOLATION='[ "$('"$PPID_READ"' 2>/dev/null | tr -d " ")" = "1" ] && echo orphan'

# --- P1: a clean tree passes ------------------------------------------------
r=$(mk_root clean)
printf '#!/usr/bin/env bash\necho hello\n' > "$r/scripts/test_clean.sh"
run_gate "$r"
if [ "$RC" -eq 0 ] && printf '%s' "$OUT" | grep -q 'liveness_predicate_scan_ok'; then ok
else note "p1 clean tree must pass with the ok token (rc=$RC): $OUT"; fi

# --- P2: the violation fires (the gate's whole reason to exist) -------------
r=$(mk_root violation)
printf '#!/usr/bin/env bash\n%s\n' "$VIOLATION" > "$r/scripts/test_probe.sh"
run_gate "$r"
if [ "$RC" -ne 0 ] && printf '%s' "$OUT" | grep -q 'liveness_predicate_scan_failed'; then ok
else note "p2 planted orphan-oracle must FAIL the gate (rc=$RC): $OUT"; fi

# --- P2b: the report names the offending file and line ----------------------
if printf '%s' "$OUT" | grep -q 'scripts/test_probe.sh:2'; then ok
else note "p2b failure output must locate the hit (file:line), got: $OUT"; fi

# --- P2c: the hit and the diagnosis must not run together on one line -------
# The sorted-hit list loses its trailing newline to command substitution; without an
# explicit one the last hit and the message concatenate and neither greps cleanly.
if printf '%s' "$OUT" | grep -q '^liveness_predicate_scan_failed'; then ok
else note "p2c the diagnosis must start its own line, got: $OUT"; fi

# --- P3: consulting process state clears it (this IS the documented fix) ----
r=$(mk_root fixed)
{ printf '#!/usr/bin/env bash\n'
  printf 'st="$(ps -o stat= -p "$pid")"\n'
  printf '%s\n' "$VIOLATION"
} > "$r/scripts/test_probe.sh"
run_gate "$r"
if [ "$RC" -eq 0 ]; then ok
else note "p3 a state consult within the window must clear the line (rc=$RC): $OUT"; fi

# --- P3b: a *_state helper THIS FILE DEFINES over process state clears it ---
# The real fix's shape: one helper, defined in the same file, reading `ps -o stat=`.
r=$(mk_root fixed_helper)
{ printf '#!/usr/bin/env bash\n'
  printf 'wrapper_state() {\n  ps -o stat= -p "$1"\n}\n'
  printf 'case "$(wrapper_state "$pid")" in live) : ;; esac\n'
  printf '%s\n' "$VIOLATION"
} > "$r/scripts/test_probe.sh"
run_gate "$r"
if [ "$RC" -eq 0 ]; then ok
else note "p3b a file-defined state helper must clear the line (rc=$RC): $OUT"; fi

# --- P3c: an unrelated *_state call is NOT remediation ----------------------
# Found by adversarial review: accepting any `*_state` token let a bookkeeping helper
# that never reads process state clear a real hit, so the blocking gate printed ok.
r=$(mk_root fake_helper)
{ printf '#!/usr/bin/env bash\n'
  printf 'record_state "$other_pid"\n'
  printf '%s\n' "$VIOLATION"
} > "$r/scripts/test_probe.sh"
run_gate "$r"
if [ "$RC" -ne 0 ] && printf '%s' "$OUT" | grep -q 'liveness_predicate_scan_failed'; then ok
else note "p3c an unrelated *_state call must NOT clear the violation (rc=$RC): $OUT"; fi

# --- P3d: a defined helper that does NOT read process state is not remediation
r=$(mk_root hollow_helper)
{ printf '#!/usr/bin/env bash\n'
  printf 'record_state() {\n  echo "$1" >>"$log"\n}\n'
  printf 'record_state "$other_pid"\n'
  printf '%s\n' "$VIOLATION"
} > "$r/scripts/test_probe.sh"
run_gate "$r"
if [ "$RC" -ne 0 ]; then ok
else note "p3d a defined helper that never reads process state must not clear it (rc=$RC): $OUT"; fi

# --- P4: a whole-line comment carrying the spelling is documentation --------
# The checklist row and the gate's own comment block name the banned spelling; a gate
# that flags its own documentation gets loosened.
r=$(mk_root commented)
printf '#!/usr/bin/env bash\n# %s\n' "$VIOLATION" > "$r/scripts/test_doc.sh"
run_gate "$r"
if [ "$RC" -eq 0 ]; then ok
else note "p4 a whole-line comment must not be flagged (rc=$RC): $OUT"; fi

# --- P5: scope is test scripts — a signalling guard elsewhere is legitimate --
# Outside a test, asking whether a pid exists before signalling it is the right
# question; flagging it would trade a real false-positive cost for nothing.
r=$(mk_root nontest)
printf '#!/usr/bin/env bash\n%s\n' "$VIOLATION" > "$r/scripts/helper.sh"
run_gate "$r"
if [ "$RC" -eq 0 ]; then ok
else note "p5 non-test shell is out of scope and must not fire (rc=$RC): $OUT"; fi

# --- P6: a ppid read that IDENTIFIES a parent is not an orphan oracle -------
# The common, correct use. Flagging it is what would make precision collapse.
r=$(mk_root identify)
{ printf '#!/usr/bin/env bash\n'
  printf 'parent="$(%s 2>/dev/null | tr -d " ")"\n' "$PPID_READ"
  printf 'cmd="$(ps -o command= -p "$parent")"\n'
} > "$r/scripts/test_identify.sh"
run_gate "$r"
if [ "$RC" -eq 0 ]; then ok
else note "p6 a ppid read used for parent identity must not fire (rc=$RC): $OUT"; fi

# --- P7: a COMMENT naming the helper must not clear a real violation ---------
# The waiver has to be code that consults process state, not a note saying someone
# should. Found by adversarial review of this gate: the window grep read raw text, so a
# TODO beside the violation made the blocking checker print ok for a line it had found.
r=$(mk_root comment_waiver)
{ printf '#!/usr/bin/env bash\n'
  printf '# TODO: use wrapper_state here instead\n'
  printf '%s\n' "$VIOLATION"
} > "$r/scripts/test_probe.sh"
run_gate "$r"
if [ "$RC" -ne 0 ] && printf '%s' "$OUT" | grep -q 'liveness_predicate_scan_failed'; then ok
else note "p7 a comment mentioning the helper must NOT clear the violation (rc=$RC): $OUT"; fi

# --- P8: parameter expansion carrying '#' must not be mistaken for a comment --
# Stripping trailing comments with a naive `#`-to-end rule would truncate `${var#pre}`
# and could drop the real state consult that follows it, turning the fix into a hit.
r=$(mk_root hash_expansion)
{ printf '#!/usr/bin/env bash\n'
  printf 'rel="${path#"$root"/}"; st="$(ps -o stat= -p "$pid")"\n'
  printf '%s\n' "$VIOLATION"
} > "$r/scripts/test_probe.sh"
run_gate "$r"
if [ "$RC" -eq 0 ]; then ok
else note "p8 a '#' inside parameter expansion must not void the state consult (rc=$RC): $OUT"; fi

# --- P9: the NEGATED assertion is the opposite check and must not fire ------
# `!= "1"` asserts a process is NOT reparented. An unrestricted `.*=` in the predicate
# swallowed the `!`, so the gate flagged the very check that does the right thing —
# found by adversarial review, and the false-positive direction this gate must avoid.
r=$(mk_root negated)
{ printf '#!/usr/bin/env bash\n'
  printf '[ "$(%s 2>/dev/null | tr -d " ")" != "1" ] && echo still-parented\n' "$PPID_READ"
} > "$r/scripts/test_probe.sh"
run_gate "$r"
if [ "$RC" -eq 0 ]; then ok
else note "p9 a negated ppid assertion must NOT fire (rc=$RC): $OUT"; fi

# --- P9b: the positive oracle still fires with the tightened operator match --
# Guards the tightening itself: narrowing the operator must not blunt the real catch.
r=$(mk_root still_fires)
printf '#!/usr/bin/env bash\n%s\n' "$VIOLATION" > "$r/scripts/test_probe.sh"
run_gate "$r"
if [ "$RC" -ne 0 ] && printf '%s' "$OUT" | grep -q 'liveness_predicate_scan_failed'; then ok
else note "p9b the real orphan oracle must still fire after tightening (rc=$RC): $OUT"; fi

# --- P10: a bare `stat=` assignment is not a process-state read ---------------
# Found by adversarial review: the waiver grepped bare `stat=`, so an unrelated
# assignment two lines away cleared a genuine hit and the blocking gate printed ok.
r=$(mk_root fake_stat)
{ printf '#!/usr/bin/env bash\n'
  printf 'stat=unknown\n'
  printf '%s\n' "$VIOLATION"
} > "$r/scripts/test_probe.sh"
run_gate "$r"
if [ "$RC" -ne 0 ] && printf '%s' "$OUT" | grep -q 'liveness_predicate_scan_failed'; then ok
else note "p10 a bare stat= assignment must NOT clear the violation (rc=$RC): $OUT"; fi

# --- P10b: the genuine `ps -o stat=` read still clears it --------------------
r=$(mk_root real_stat)
{ printf '#!/usr/bin/env bash\n'
  printf 'st="$(ps -o stat= -p "$pid")"\n'
  printf '%s\n' "$VIOLATION"
} > "$r/scripts/test_probe.sh"
run_gate "$r"
if [ "$RC" -eq 0 ]; then ok
else note "p10b a real ps -o stat= read must still clear the line (rc=$RC): $OUT"; fi

# --- P11: a HOLLOW helper plus an unrelated state read elsewhere is not a fix --
# Found by adversarial review: "the file defines *_state" and "the file reads process
# state somewhere" were checked independently, so the two were never tied together and a
# do-nothing helper borrowed an unrelated read to clear a real hit.
r=$(mk_root hollow_plus_elsewhere)
{ printf '#!/usr/bin/env bash\n'
  printf 'wrapper_state() {\n  echo unknown\n}\n'
  printf 'other() {\n  ps -o stat= -p "$1"\n}\n'
  printf 'case "$(wrapper_state "$pid")" in live) : ;; esac\n'
  printf '%s\n' "$VIOLATION"
} > "$r/scripts/test_probe.sh"
run_gate "$r"
if [ "$RC" -ne 0 ] && printf '%s' "$OUT" | grep -q 'liveness_predicate_scan_failed'; then ok
else note "p11 a hollow helper must NOT borrow an unrelated state read (rc=$RC): $OUT"; fi

# --- P12: a ONE-LINE hollow helper must not borrow a later function's read -----
# Found by the adversarial challenge: the awk rule set inbody and ran `next`, so a
# definition that opens and closes on one line never met its `}` and stayed "in body"
# across the following functions, crediting their state read to the hollow helper.
r=$(mk_root oneline_hollow)
{ printf '#!/usr/bin/env bash\n'
  printf 'wrapper_state() { echo live; }\n'
  printf 'other() {\n  ps -o stat= -p "$other_pid"\n}\n'
  printf 'case "$(wrapper_state "$pid")" in live) : ;; esac\n'
  printf '%s\n' "$VIOLATION"
} > "$r/scripts/test_probe.sh"
run_gate "$r"
if [ "$RC" -ne 0 ] && printf '%s' "$OUT" | grep -q 'liveness_predicate_scan_failed'; then ok
else note "p12 a one-line hollow helper must NOT borrow a later read (rc=$RC): $OUT"; fi

# --- P12b: a genuine ONE-LINE helper that does read state still clears it ------
r=$(mk_root oneline_real)
{ printf '#!/usr/bin/env bash\n'
  printf 'wrapper_state() { ps -o stat= -p "$1"; }\n'
  printf 'case "$(wrapper_state "$pid")" in live) : ;; esac\n'
  printf '%s\n' "$VIOLATION"
} > "$r/scripts/test_probe.sh"
run_gate "$r"
if [ "$RC" -eq 0 ]; then ok
else note "p12b a real one-line state helper must clear the line (rc=$RC): $OUT"; fi

printf 'liveness_predicate_gate: pass=%s fail=%s\n' "$pass" "$fail"
[ "$fail" -eq 0 ] || exit 1
echo "liveness_predicate_gate_ok"
