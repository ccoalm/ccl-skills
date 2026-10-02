#!/usr/bin/env bash
# Regression: the repository gates must not depend on the caller's locale.
# Under a POSIX/unset locale Ruby defaults to US-ASCII, so a gate that reads the
# UTF-8 skill text (or runs a `ruby -e` program with UTF-8 literals) crashed with
# "invalid byte sequence in US-ASCII" before checking anything, while CI (which
# runs C.UTF-8) stayed green. Each ruby-invoking script pins `RUBYOPT=-Ku`.
#   (1) every tracked live shell script (skills/, hooks/, scripts/) that invokes
#       ruby carries the pin, and no other literal RUBYOPT mention drops it; the
#       classifier is held by pinned bypass and near-miss rows; frozen evidence
#       under specs/ and eval/ is exempt;
#   (2) validate-skill.sh passes on a UTF-8 fixture under LC_ALL=C;
#   (3) the same run with the pin deleted goes red for the encoding reason, which
#       shows the pin is what makes leg (2) pass; on a host whose C locale already
#       reads UTF-8 the pin is not load-bearing and leg (3) reports unevaluated.
set -euo pipefail
# Ruby takes its encoding from the locale; under a POSIX/unset locale it reads the UTF-8 skill text as US-ASCII and crashes. Pin UTF-8, as CI runs.
case " ${RUBYOPT:-} " in *" -Ku "*) ;; *) export RUBYOPT="-Ku${RUBYOPT:+ $RUBYOPT}" ;; esac

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd -P)"
ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd -P)"
PIN='case " ${RUBYOPT:-} " in *" -Ku "*) ;; *) export RUBYOPT="-Ku${RUBYOPT:+ $RUBYOPT}" ;; esac'
fail() { printf 'FAIL: %b\n' "$*" >&2; exit 1; }

# Closed contract over the idiom this repo owns: a RUBYOPT mention keeps the pin
# only as the pin line itself, the keep idiom RUBYOPT="${RUBYOPT:+$RUBYOPT }..."
# whose suffix holds only `-r<lib>` requires or variables, or an empty RUBYOPT=
# before `bash "$script"` (that script pins itself). Any other literal mention -
# replacing, clearing, unset, env -u, any other Ruby option - drops the pin.
# Ruby's option names are not this repo's to enumerate, so the suffix is
# allowlisted, never denylisted. Returns 0 when allowed.
KEEP_TOKEN='(-r[^[:space:]"\\]+|[$][{]?[A-Za-z_0-9]+[}]?)'
pin_kept() {
  local line="$1" rest
  [ "$line" = "$PIN" ] && return 0
  # An attribute builtin on the variable can unexport or rescope it even when
  # the value is the keep idiom.
  if printf '%s\n' "$line" | grep -qE '(^|[^A-Za-z_])(declare|typeset|local|readonly|export[[:space:]]+-n)[^;|&]*RUBYOPT'; then
    return 1
  fi
  rest="$(printf '%s\n' "$line" | sed -E \
    -e "s/^([^\"'\\\\]*)[[:space:]]#.*\$/\\1/" \
    -e "s/RUBYOPT=\"[\$][{]RUBYOPT:[+][\$]RUBYOPT [}](${KEEP_TOKEN}([[:space:]]+${KEEP_TOKEN})*)?\"//g" \
    -e 's/(^|[[:space:]])RUBYOPT=[[:space:]]+bash[[:space:]]+"[$][A-Za-z_{][^"]*"/\1/g')"
  case "$rest" in *RUBYOPT*) return 1 ;; esac
  return 0
}

# Every RUBYOPT line of one file that drops the pin, as "N:line". Whole-line
# comments are skipped; nothing else is pre-filtered, so a line that merely
# contains the pin text is still classified.
pin_drops() {
  local hit
  while IFS= read -r hit; do
    pin_kept "${hit#*:}" || printf '%s\n' "$hit"
  done < <(grep -nE 'RUBYOPT' "$1" | grep -vE '^[0-9]+:[[:space:]]*#' || true)
}

# (1a) The classifier itself: every bypass row must be flagged and every
# near-miss row must stay allowed, so a broken classifier cannot pass on a
# corpus that happens to hold only allowed shapes.
while IFS= read -r row; do
  [ -n "$row" ] || continue
  if pin_kept "$row"; then fail "classifier allowed a pin-dropping line: $row"; fi
done <<'ROWS'
RUBYOPT="-r$SHIM" ruby x.rb
RUBYOPT= ruby -e "p 1"
unset RUBYOPT
env -u RUBYOPT ruby -e 1
RUBYOPT="$RUBYOPT_EXTRA -rfoo" ruby -e 1
export RUBYOPT=
RUBYOPT=
RUBYOPT= LC_ALL=C ruby -e 1
LC_ALL=C RUBYOPT= LANG=C ruby -e 1
RUBYOPT= exec ruby -e 1
RUBYOPT= "${RUBY:-ruby}" -e 1
RUBYOPT= bash -c "ruby -e 1"
unset -v RUBYOPT
unset LANG RUBYOPT
env --unset=RUBYOPT ruby -e 1
env -uRUBYOPT ruby -e 1
RUBYOPT=-W0 ruby -e 1 "$RUBYOPT"
RUBYOPT="${RUBYOPT#-Ku}" ruby -e 1
RUBYOPT="" bash x.sh
export RUBYOPT=-W0
echo "a #b"; RUBYOPT=-Kn ruby -e 1
printf ' #' ; unset RUBYOPT
case " ${RUBYOPT:-} " in *" -Ku "*) ;; *) export RUBYOPT="-Ku${RUBYOPT:+ $RUBYOPT}" ;; esac; unset RUBYOPT
RUBYOPT="${RUBYOPT:+$RUBYOPT }-Kn" ruby x.rb
RUBYOPT="${RUBYOPT:+$RUBYOPT }-E ASCII" ruby x.rb
RUBYOPT="${RUBYOPT:+$RUBYOPT }--internal-encoding=US-ASCII" ruby x.rb
RUBYOPT="${RUBYOPT:+$RUBYOPT }--disable=rubyopt" ruby x.rb
RUBYOPT="${RUBYOPT:+$RUBYOPT }-r\" -Kn" ruby x.rb
export -n RUBYOPT="${RUBYOPT:+$RUBYOPT }-rdate"
declare +x RUBYOPT="${RUBYOPT:+$RUBYOPT }"
RUBYOPT="${RUBYOPT:+$RUBYOPT_EXTRA }" ruby x.rb
RUBYOPT="${RUBYOPT:+$RUBYOPT}-Kn" ruby x.rb
x=$#; unset RUBYOPT
echo a\ #b; unset RUBYOPT
local RUBYOPT
declare -x RUBYOPT=
ROWS
while IFS= read -r row; do
  [ -n "$row" ] || continue
  pin_kept "$row" || fail "classifier flagged an allowed line: $row"
done <<'ROWS'
out="$(RUBYOPT="${RUBYOPT:+$RUBYOPT }-rdate" ruby x.rb)"
env -u X LC_ALL=C RUBYOPT= bash "$SIZE_SCRIPT" "$REPO"
f() { # takes a RUBYOPT value
RUBYOPT= bash "$x"; ruby -e 1
RUBYOPT="${RUBYOPT:+$RUBYOPT }-r$SHIM -rdate" ruby x.rb
RUBYOPT="${RUBYOPT:+$RUBYOPT }$2" ruby "$1"
run_gate() { # <gate-path> <RUBYOPT value or empty>
ROWS

# (1b) Static coverage over tracked live shell scripts.
tracked="$(git -C "$ROOT" ls-files -- 'skills/*.sh' 'hooks/*.sh' 'scripts/*.sh')" \
  || fail "cannot list tracked scripts (not a git checkout?); leg 1 needs git ls-files"
[ -n "$tracked" ] || fail "git ls-files listed no tracked scripts under $ROOT; leg 1 would pass vacuously"
missing=""
dropped=""
while IFS= read -r rel; do
  # A bare `ruby` word: catches `ruby -e`, `ruby<<`, `ruby;`, `${RUBY:-ruby}`;
  # leaves `rubygems` / `ruby-build` alone. Over-matching only over-requires the pin.
  grep -qE '(^|[^a-z_])ruby([^a-z0-9_.-]|$)' "$ROOT/$rel" || continue
  grep -qxF "$PIN" "$ROOT/$rel" || missing="$missing\n  $rel"
  # This file names RUBYOPT in its own patterns and rows, so only its pin is checked.
  [ "$rel" = "skills/skill-extraction-workflow/scripts/test_locale_independent_gates.sh" ] && continue
  while IFS= read -r hit; do
    [ -n "$hit" ] && dropped="$dropped\n  $rel: $hit"
  done < <(pin_drops "$ROOT/$rel")
done <<<"$tracked"
[ -z "$missing" ] || fail "ruby-invoking scripts without the RUBYOPT UTF-8 pin:$missing"
[ -z "$dropped" ] || fail "RUBYOPT mentions that drop the UTF-8 pin (use the keep idiom):$dropped"

TMP="$(mktemp -d "${TMPDIR:-/tmp}/locale-gates.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

# (1c) The scan as a whole, on a fixture file: only a line that drops the pin is
# reported, including one that also contains the pin text.
{
  printf '%s\n' "$PIN"
  printf '%s; unset RUBYOPT\n' "$PIN"
  printf '# unset RUBYOPT in a comment\n'
  printf 'out="$(RUBYOPT="${RUBYOPT:+$RUBYOPT }-rdate" ruby x.rb)"\n'
} >"$TMP/scan-fixture.sh"
scan_out="$(pin_drops "$TMP/scan-fixture.sh")"
[ "${scan_out%%:*}" = "2" ] && [ "$(printf '%s\n' "$scan_out" | grep -c .)" = "1" ] \
  || fail "pin_drops must report only line 2 of the scan fixture, got:\n$scan_out"
mkdir -p "$TMP/skill/references"
cat >"$TMP/skill/SKILL.md" <<'EOF'
---
name: locale-fixture
description: 合成夹具 — synthetic fixture for locale independence.
---

# 夹具

见 `references/detail.md`。
EOF
printf '# 细节\n\n中文正文。\n' >"$TMP/skill/references/detail.md"

run_c_locale() { env -u LANGUAGE LC_ALL=C LANG=C RUBYOPT= bash "$1" "$TMP/skill"; }

# (2) The shipped gate passes under the C locale.
if ! out="$(run_c_locale "$SCRIPT_DIR/validate-skill.sh" 2>&1)"; then
  fail "validate-skill.sh failed under LC_ALL=C:\n$out"
fi
case "$out" in *markdown_references_ok*) : ;; *) fail "validate-skill.sh did not reach the reference check under LC_ALL=C:\n$out" ;; esac

# (3) Applied mutation: the same script without the pin reds for the encoding reason.
cp -R "$SCRIPT_DIR" "$TMP/scripts"
grep -vxF "$PIN" "$SCRIPT_DIR/validate-skill.sh" >"$TMP/scripts/validate-skill.sh"
if mout="$(run_c_locale "$TMP/scripts/validate-skill.sh" 2>&1)"; then
  # Unevaluated only when the host itself explains the pass: Ruby already reads
  # UTF-8 under the C locale, so the pin is not load-bearing here. Any other
  # reason the unpinned run passed means leg 2 may be vacuous.
  if ! env -u LANGUAGE LC_ALL=C LANG=C ruby -e 'exit(Encoding.find("locale") == Encoding::UTF_8 ? 0 : 1)'; then
    fail "pin removed, yet validate-skill.sh still passed under LC_ALL=C on a host whose Ruby reads US-ASCII there, so leg 2 proves nothing:\n$mout"
  fi
  echo "test_locale_independent_gates_leg3_unevaluated: this host's Ruby reads UTF-8 under LC_ALL=C, so removing the pin cannot be shown to matter here" >&2
  echo "test_locale_independent_gates: ok (legs 1-2; leg 3 unevaluated on this host)"
  exit 0
fi
case "$mout" in
  *"invalid byte sequence"*|*"invalid multibyte char"*) : ;;
  *) fail "pin removed: run failed, but not for the encoding reason:\n$mout" ;;
esac

echo "test_locale_independent_gates: ok"
