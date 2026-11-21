#!/usr/bin/env bash
# install-antigravity.sh against a fake `agy` that, like the real CLI, replaces
# the whole ~/.gemini/config/plugins/<name> directory on install.
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd -P)"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/ccl-agy-install-test.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT
FAIL=0
pass() { printf 'ok   %s\n' "$1"; }
fail() { printf 'FAIL %s\n' "$1"; FAIL=1; }

mkdir -p "$WORK/bin"
cat >"$WORK/bin/agy" <<'AGY'
#!/usr/bin/env bash
set -eu
echo "$*" >>"$FAKE_AGY_LOG"
[ "$1 $2" = "plugin install" ] || exit 2
[ -n "${FAKE_AGY_NOOP:-}" ] && exit 0
name=$(python3 -I -c 'import json,sys; print(json.load(open(sys.argv[1]))["name"])' "$3/.antigravity-plugin/plugin.json")
dest="$HOME/.gemini/config/plugins/$name"
rm -rf "$dest"; mkdir -p "$(dirname "$dest")"; cp -a "$3" "$dest"
AGY
chmod +x "$WORK/bin/agy"

run_installer() {  # <installer> <home> [args]
  local installer=$1 home=$2; shift 2
  HOME="$home" PATH="$WORK/bin:$PATH" FAKE_AGY_LOG="$home.log" TMPDIR="$WORK" bash "$installer" "$@" >"$home.out" 2>&1
}

# 1. Fresh install stages only the tracked runtime closure.
H1="$WORK/h1"; mkdir -p "$H1"
if run_installer "$ROOT/scripts/install-antigravity.sh" "$H1"; then
  P="$H1/.gemini/config/plugins/ccl-skills"
  [ -f "$P/.antigravity-plugin/plugin.json" ] && [ -f "$P/hooks.json" ] && [ -f "$P/hooks/agy-bridge.py" ] \
    && [ -f "$P/skills/skill-extraction-workflow/SKILL.md" ] && [ -f "$P/agent-context/session-start.md" ] \
    && pass "fresh install carries manifest, hooks.json, bridge, skills and context" || fail "fresh install contents"
  [ ! -e "$P/specs" ] && [ ! -e "$P/eval" ] && [ ! -e "$P/packages" ] && [ ! -e "$P/AGENTS.md" ] \
    && pass "fresh install excludes specs, eval, packages and the repository contract" || fail "fresh install excludes"
  python3 -I -c 'import json,sys; d=json.load(open(sys.argv[1])); sys.exit(d["installer"]!="scripts/install-antigravity.sh")' "$P/.ccl-skills-install.json" \
    && pass "ownership marker written" || fail "ownership marker"
else
  fail "fresh install exited non-zero: $(cat "$H1.out")"
fi

# 2. An unmodified owned install is refreshed; one changed after install is left alone.
if run_installer "$ROOT/scripts/install-antigravity.sh" "$H1" && grep -q "plugin install" "$H1.log"; then
  pass "unmodified owned install is refreshed"
else
  fail "owned install refresh: $(cat "$H1.out")"
fi
echo "my local skill" >"$H1/.gemini/config/plugins/ccl-skills/LOCAL_ADDITION"
: >"$H1.log"
run_installer "$ROOT/scripts/install-antigravity.sh" "$H1"
[ $? -eq 3 ] && [ -f "$H1/.gemini/config/plugins/ccl-skills/LOCAL_ADDITION" ] && [ ! -s "$H1.log" ] \
  && pass "owned install changed after install is left untouched" || fail "edited owned install: $(cat "$H1.out")"

# 3. Must not touch: an unmarked plugin directory (hand-made clone, npm copy).
unowned_case() {  # <installer> <home> -> 0 when the unowned directory survived byte-for-byte and agy was not called
  local installer=$1 home=$2 dir="$2/.gemini/config/plugins/ccl-skills"
  mkdir -p "$dir/.antigravity-plugin"
  echo '{"name":"ccl-skills"}' >"$dir/.antigravity-plugin/plugin.json"
  echo "local work" >"$dir/LOCAL_EDIT"
  run_installer "$installer" "$home"
  local status=$?
  [ "$status" -eq 3 ] && [ "$(cat "$dir/LOCAL_EDIT" 2>/dev/null)" = "local work" ] && [ ! -s "$home.log" ]
}
H2="$WORK/h2"; mkdir -p "$H2"
unowned_case "$ROOT/scripts/install-antigravity.sh" "$H2" && pass "unowned plugin directory is left untouched (exit 3)" \
  || fail "unowned plugin directory was modified: $(cat "$H2.out")"

# 3b. A marker naming another installer is not ownership.
H3="$WORK/h3"; mkdir -p "$H3/.gemini/config/plugins/ccl-skills"
echo '{"installer":"something-else"}' >"$H3/.gemini/config/plugins/ccl-skills/.ccl-skills-install.json"
echo keep >"$H3/.gemini/config/plugins/ccl-skills/KEEP"
run_installer "$ROOT/scripts/install-antigravity.sh" "$H3"
[ $? -eq 3 ] && [ -f "$H3/.gemini/config/plugins/ccl-skills/KEEP" ] && pass "foreign marker is not ownership" || fail "foreign marker"

# Scratch checkout: a git repo holding this checkout's tracked runtime files and the installer.
scratch_checkout() {  # <dir>
  local dir=$1
  mkdir -p "$dir"
  git -C "$ROOT" ls-files -z -- .antigravity-plugin hooks.json agent-context skills hooks scripts/owner-dispatch scripts/install-antigravity.sh \
    | (cd "$ROOT" && tar --null -T - -cf -) | tar -xf - -C "$dir"
  git -C "$dir" init -q && git -C "$dir" add -A \
    && git -C "$dir" -c user.name=t -c user.email=t@example.invalid commit -qm fixture
}

# 4. Sensitivity: with the ownership predicate removed, the unowned directory must be
#    replaced through a real fake-host install (a mutant that dies early proves nothing).
C4="$WORK/c4"; scratch_checkout "$C4"
sed "s/^  if ! python3 -I -c '\$/  if false \&\& python3 -I -c '/" "$C4/scripts/install-antigravity.sh" >"$C4/mutant.sh"
if cmp -s "$C4/mutant.sh" "$C4/scripts/install-antigravity.sh"; then
  fail "mutation probe did not apply"
else
  cp "$C4/mutant.sh" "$C4/scripts/install-antigravity.sh"
  H4="$WORK/h4"; mkdir -p "$H4"
  unowned_case "$C4/scripts/install-antigravity.sh" "$H4"
  if grep -q "plugin install" "$H4.log" 2>/dev/null && [ ! -e "$H4/.gemini/config/plugins/ccl-skills/LOCAL_EDIT" ] \
     && [ -f "$H4/.gemini/config/plugins/ccl-skills/hooks/agy-bridge.py" ]; then
    pass "ownership predicate is what protects the unowned directory"
  else
    fail "ownership mutant did not reach a host install (probe is blind): $(cat "$H4.out")"
  fi
fi

# 6. A renamed staged manifest is refused before agy runs (ownership was checked for ccl-skills only).
C6="$WORK/c6"; scratch_checkout "$C6"
python3 -I -c 'import json,sys; p=sys.argv[1]; d=json.load(open(p)); d["name"]="other-plugin"; json.dump(d,open(p,"w"))' "$C6/.antigravity-plugin/plugin.json"
H6="$WORK/h6"; mkdir -p "$H6/.gemini/config/plugins/other-plugin"; echo keep >"$H6/.gemini/config/plugins/other-plugin/KEEP"
run_installer "$C6/scripts/install-antigravity.sh" "$H6"
[ $? -ne 0 ] && [ ! -s "$H6.log" ] && [ -f "$H6/.gemini/config/plugins/other-plugin/KEEP" ] \
  && pass "renamed manifest refused before any host call" || fail "renamed manifest: $(cat "$H6.out")"

# 7. A tracked file replaced by a directory (with untracked content) stops staging.
C7="$WORK/c7"; scratch_checkout "$C7"
rm "$C7/hooks.json"; mkdir "$C7/hooks.json"; echo untracked >"$C7/hooks.json/SENTINEL"
H7="$WORK/h7"; mkdir -p "$H7"
run_installer "$C7/scripts/install-antigravity.sh" "$H7"
[ $? -ne 0 ] && [ ! -s "$H7.log" ] && pass "type-changed tracked path is refused" || fail "type-changed tracked path: $(cat "$H7.out")"

# 8. A host that reports success without replacing the tree is not reported as installed.
C8="$WORK/c8"; scratch_checkout "$C8"
H8="$WORK/h8"; mkdir -p "$H8"
run_installer "$C8/scripts/install-antigravity.sh" "$H8" || fail "c8 initial install"
echo "# changed" >>"$C8/hooks/agy-bridge.py"
HOME="$H8" PATH="$WORK/bin:$PATH" FAKE_AGY_LOG="$H8.log" FAKE_AGY_NOOP=1 TMPDIR="$WORK" \
  bash "$C8/scripts/install-antigravity.sh" >"$H8.out" 2>&1
[ $? -ne 0 ] && grep -q "does not match the staged plugin" "$H8.out" \
  && pass "no-op host install is detected" || fail "no-op host install: $(cat "$H8.out")"

# 9. A held installer lock (shared with the npm adapter) stops the install before any host call.
H9="$WORK/h9"; mkdir -p "$H9/.gemini"; : >"$H9/.gemini/ccl-skills-plugin.lock"
run_installer "$ROOT/scripts/install-antigravity.sh" "$H9"
[ $? -eq 3 ] && [ ! -s "$H9.log" ] && [ -f "$H9/.gemini/ccl-skills-plugin.lock" ] \
  && pass "held lock stops the install and is left in place" || fail "held lock: $(cat "$H9.out")"

# 5. Dry run does not call agy.
H5="$WORK/h5"; mkdir -p "$H5"
run_installer "$ROOT/scripts/install-antigravity.sh" "$H5" --dry-run && [ ! -s "$H5.log" ] \
  && [ ! -e "$H5/.gemini/config/plugins/ccl-skills" ] && pass "dry run makes no change" || fail "dry run"

exit "$FAIL"
