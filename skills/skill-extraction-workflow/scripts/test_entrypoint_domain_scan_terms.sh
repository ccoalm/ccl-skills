#!/usr/bin/env bash
# Regression test for the entrypoint/reference DOMAIN leak scan inside
# check-ccl-skills.sh (distinct from generic-r0-leak-scan.sh, which is
# credential-shaped and has its own suite).
#
# Why this exists: that scan's predicate is a list of ANOTHER domain's ordinary
# vocabulary, so it decays — a term goes stale when the project it proxied for
# does, and until then it blocks legitimate prose. A term was retired for exactly
# that reason, and nothing in the repo would have turned red if the retirement
# had also deleted a live term or the whole scan. This pins both directions.
#
# Design: read-only over the real repo (the sibling checker tests' convention).
#   Leg 1 (wiring)   : the real checker runs the scan and reports it clean here.
#   Leg 2 (predicate): the retained terms still MATCH — the scan can still fail.
#   Leg 3 (predicate): the retired term does NOT match — the retirement holds.
# Legs 2-3 read the pattern out of the real script, so they cannot drift away
# from what ships; extraction failure is a hard error, never a silent pass.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd -P)"
CHECK_SCRIPT="$SCRIPT_DIR/check-ccl-skills.sh"
# scripts -> skill-extraction-workflow -> skills -> repo root
ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd -P)"
[ -f "$CHECK_SCRIPT" ] || { echo "FAIL: check script not found: $CHECK_SCRIPT" >&2; exit 1; }
[ -d "$ROOT/skills" ] || { echo "FAIL: repo root has no skills/ dir: $ROOT" >&2; exit 1; }

fail() { echo "FAIL: $*" >&2; exit 1; }
command -v rg >/dev/null 2>&1 || fail "rg not available; the scan under test needs it"

# --- Leg 1: wiring. The scan runs in the real checker and is clean on this tree.
set +e
out="$(bash "$CHECK_SCRIPT" "$ROOT" 2>&1)"
set -e
case "$out" in
  *entrypoint_and_reference_domain_scan_ok*) : ;;
  *) fail "domain scan did not report clean on the real tree; is it still wired?\n$out" ;;
esac

# --- Extract the shipped pattern (single source of truth: the script itself).
# lane on an rg built without it, on machines where the checker itself runs fine.
pattern="$(
  awk 'index($0, "rg -n \047") > 0 {
    rest = substr($0, index($0, "rg -n \047") + 7)
    j = index(rest, "\047 \"$root\""); if (j == 0) next
    print substr(rest, 1, j - 1); exit
  }' "$CHECK_SCRIPT"
)"
[ -n "$pattern" ] || fail "could not extract the domain-scan pattern from $CHECK_SCRIPT (line shape changed?)"

matches() { # <text> -> rc 0 when the shipped pattern matches
  printf '%s\n' "$1" | rg -q "$pattern"
}

# --- Leg 2: the scan can still fail. Every retained term must match.
#     Written as escapes so this file never carries the literal vocabulary.
retained=(
  $'教师' $'学生' $'考试' $'学校'
  $'阅卷' $'出卷' $'学情'
)
for term in "${retained[@]}"; do
  matches "x ${term} y" || fail "retained domain term no longer matches — the scan was widened/broken, not narrowed"
done
# Non-vocabulary alternatives in the same pattern must also still bite.
matches 'see code.example-host.internal for details' \
  || fail "host-style leak alternative no longer matches"
matches 'ref 123456789' || fail "long-digit alternative no longer matches"

# --- Leg 3: the retired term must NOT match, in ordinary prose.
retired=$'扫描'
! matches "先跑一遍${retired}再判" \
  || fail "retired term still blocks ordinary prose; the retirement did not land"

# --- Leg 4: the checker must still FAIL end-to-end on a planted leak.
#     Legs 1-3 alone cannot see a broken conditional: leg 1 only proves the clean
#     sentinel prints, legs 2-3 exercise the regex in isolation. Without this leg
#     an inverted or bypassed failure branch would keep the whole suite green.
#     Runs against a throwaway --shared clone so the real tree is never written.
TMP="$(mktemp -d "${TMPDIR:-/tmp}/domscan.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
git clone --shared --quiet "$ROOT" "$TMP/repo" \
  || fail "could not build the throwaway clone for the end-to-end leg"
# Control leg on the SAME clone before planting: without it, a removed exit 1
# plus any unrelated later failure on this clone would still yield non-zero
# plus the scan's token, and leg 4 would pass on a broken gate.
set +e
ctl="$(bash "$CHECK_SCRIPT" "$TMP/repo" 2>&1)"
ctl_rc=$?
set -e
[ "$ctl_rc" -eq 0 ] || fail "clean clone did not pass; leg 4 cannot attribute a failure to the probe\n$ctl"
case "$ctl" in
  *entrypoint_and_reference_domain_scan_ok*) : ;;
  *) fail "clean clone did not report the domain scan clean; attribution unsafe\n$ctl" ;;
esac
probe_dir="$TMP/repo/skills/tighten-doc/references"
[ -d "$probe_dir" ] || fail "clone has no reference dir to plant the probe in: $probe_dir"
printf '# probe\n\nx %s y\n' "${retained[0]}" > "$probe_dir/_domain_scan_probe.md"
set +e
e2e="$(bash "$CHECK_SCRIPT" "$TMP/repo" 2>&1)"
e2e_rc=$?
set -e
[ "$e2e_rc" -ne 0 ] || fail "checker exited 0 with a planted domain leak — the failure branch does not fire"
case "$e2e" in
  *entrypoint_or_reference_domain_scan_failed*) : ;;
  *) fail "planted leak did not raise the domain-scan failure token (something else failed first?)\n$e2e" ;;
esac
case "$e2e" in
  *_domain_scan_probe.md*) : ;;
  *) fail "failure did not name the planted probe file — attribution is not this leg's scan" ;;
esac
# The property worth pinning is NOT "execution stopped at that line" — a black-box
# test cannot see control flow, and every token-order proxy for it has a hole.
# It is: a leak in the scanned surface must PREVENT CERTIFICATION. So require the
# terminal success tokens to be absent; combined with the scan token and the probe
# filename above, that attributes the withheld certification to this scan.
case "$e2e" in
  *ccl_skill_check_ok*|*ccl_skill_check_clean_ok*|*ccl_skill_check_interim_ok*)
    fail "checker still certified a tree carrying a planted domain leak" ;;
  *) : ;;
esac

echo "test_entrypoint_domain_scan_terms: ok"
