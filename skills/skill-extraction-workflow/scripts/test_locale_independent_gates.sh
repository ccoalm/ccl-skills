#!/usr/bin/env bash
# Regression: the repository gates must not depend on the caller's locale.
# Under a POSIX/unset locale Ruby defaults to US-ASCII, so a gate that reads the
# UTF-8 skill text (or runs a `ruby -e` program with UTF-8 literals) crashed with
# "invalid byte sequence in US-ASCII" before checking anything, while CI (which
# runs C.UTF-8) stayed green. Each ruby-invoking script pins `RUBYOPT=-Ku`.
#   (1) every tracked live shell script (skills/, hooks/, scripts/) that invokes
#       ruby carries the pin; frozen evidence under specs/ and eval/ is exempt;
#   (2) validate-skill.sh passes on a UTF-8 fixture under LC_ALL=C;
#   (3) the same run with the pin deleted goes red for the encoding reason, so
#       leg (2) cannot pass vacuously.
set -euo pipefail
# Ruby takes its encoding from the locale; under a POSIX/unset locale it reads the UTF-8 skill text as US-ASCII and crashes. Pin UTF-8, as CI runs.
case " ${RUBYOPT:-} " in *" -Ku "*) ;; *) export RUBYOPT="-Ku${RUBYOPT:+ $RUBYOPT}" ;; esac

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd -P)"
ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd -P)"
PIN='case " ${RUBYOPT:-} " in *" -Ku "*) ;; *) export RUBYOPT="-Ku${RUBYOPT:+ $RUBYOPT}" ;; esac'
fail() { printf 'FAIL: %b\n' "$*" >&2; exit 1; }

# (1) Static coverage over tracked live shell scripts.
missing=""
while IFS= read -r rel; do
  grep -qE '(^|[^a-z_-])ruby( |$|")' "$ROOT/$rel" || continue
  grep -qxF "$PIN" "$ROOT/$rel" || missing="$missing\n  $rel"
done < <(git -C "$ROOT" ls-files -- 'skills/*.sh' 'hooks/*.sh' 'scripts/*.sh')
[ -z "$missing" ] || fail "ruby-invoking scripts without the RUBYOPT UTF-8 pin:$missing"

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
  fail "pin removed, yet validate-skill.sh still passed under LC_ALL=C (this host's Ruby does not reproduce the crash, so leg 2 proves nothing):\n$mout"
fi
case "$mout" in
  *"invalid byte sequence"*|*"invalid multibyte char"*) : ;;
  *) fail "pin removed: run failed, but not for the encoding reason:\n$mout" ;;
esac

echo "test_locale_independent_gates: ok"
