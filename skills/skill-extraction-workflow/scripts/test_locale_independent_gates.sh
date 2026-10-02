#!/usr/bin/env bash
# Regression: the repository gates must not depend on the caller's locale.
# Under a POSIX/unset locale Ruby defaults to US-ASCII, so a gate that reads the
# UTF-8 skill text (or runs a `ruby -e` program with UTF-8 literals) crashed with
# "invalid byte sequence in US-ASCII" before checking anything, while CI (which
# runs C.UTF-8) stayed green. Each ruby-invoking script pins `RUBYOPT=-Ku`.
#   (1) every tracked live shell script (skills/, hooks/, scripts/) that invokes
#       ruby carries the pin, and no per-command RUBYOPT= assignment drops it;
#       frozen evidence under specs/ and eval/ is exempt;
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

# (1) Static coverage over tracked live shell scripts.
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
  # A per-command RUBYOPT=... replaces the exported pin unless it keeps $RUBYOPT.
  while IFS= read -r hit; do
    case "$hit" in *'$RUBYOPT'*|*'${RUBYOPT'*) ;; *) dropped="$dropped\n  $rel: $hit" ;; esac
  done < <(grep -nE 'RUBYOPT[=][^ ]' "$ROOT/$rel" | grep -vF "$PIN" | grep -vE '^[0-9]+:[[:space:]]*#' || true)
done <<<"$tracked"
[ -z "$missing" ] || fail "ruby-invoking scripts without the RUBYOPT UTF-8 pin:$missing"
[ -z "$dropped" ] || fail "RUBYOPT assignments that drop the UTF-8 pin (keep \$RUBYOPT):$dropped"

TMP="$(mktemp -d "${TMPDIR:-/tmp}/locale-gates.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
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
  # Leg 2 already proved the gate works here; without the crash the pin is simply
  # not load-bearing on this host, so say so instead of reporting a full pass.
  echo "test_locale_independent_gates_leg3_unevaluated: this host's Ruby reads UTF-8 under LC_ALL=C, so removing the pin cannot be shown to matter here" >&2
  echo "test_locale_independent_gates: ok (legs 1-2; leg 3 unevaluated on this host)"
  exit 0
fi
case "$mout" in
  *"invalid byte sequence"*|*"invalid multibyte char"*) : ;;
  *) fail "pin removed: run failed, but not for the encoding reason:\n$mout" ;;
esac

echo "test_locale_independent_gates: ok"
