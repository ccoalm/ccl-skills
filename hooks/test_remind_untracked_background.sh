#!/usr/bin/env bash
# Deterministic behavior suite for hooks/remind-untracked-background.sh.
# Registered in the Makefile `test` target; requires jq (without jq the hook
# degrades to silence, so this suite fails loudly instead of false-greening).
set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd -P)"
HOOK="${UNTRACKED_BG_HOOK:-$SCRIPT_DIR/remind-untracked-background.sh}"
[ -f "$HOOK" ] || { echo "FAIL: hook not found: $HOOK" >&2; exit 1; }
command -v jq >/dev/null 2>&1 || { echo "FAIL: jq required for this suite" >&2; exit 1; }
bash -n "$HOOK" || { echo "FAIL: hook is not syntactically valid" >&2; exit 1; }

pass=0; fail=0
ERR="$(mktemp "${TMPDIR:-/tmp}/untracked-bg-err.XXXXXX")"
trap 'rm -f "$ERR"' EXIT

# expect <remind|quiet> <label> <command>
expect() {
  local want="$1" label="$2" command="$3" payload out rc errbytes got
  payload=$(jq -nc --arg c "$command" '{session_id:"s1",tool_name:"Bash",tool_input:{command:$c}}')
  out=$(printf '%s' "$payload" | bash "$HOOK" 2>"$ERR"); rc=$?
  errbytes=$(wc -c <"$ERR" | tr -d ' ')
  if [ "$rc" != 0 ] || [ "$errbytes" != 0 ]; then
    echo "FAIL [$label]: hook must exit 0 with silent stderr (rc=$rc, stderr=${errbytes}B)"; fail=$((fail + 1)); return
  fi
  if [ -z "$out" ]; then
    got=quiet
  elif printf '%s' "$out" | jq -e '.hookSpecificOutput.hookEventName == "PreToolUse" and (.hookSpecificOutput.additionalContext | contains("run_in_background"))' >/dev/null 2>&1; then
    got=remind
  else
    echo "FAIL [$label]: output is not the advisory JSON: $out"; fail=$((fail + 1)); return
  fi
  if [ "$got" = "$want" ]; then pass=$((pass + 1)); else echo "FAIL [$label]: expected $want, got $got"; fail=$((fail + 1)); fi
}

# The observed shape and its siblings.
expect remind "subshell nohup lane" '(nohup make test > "$S/mt.log" 2>&1; echo "make_exit=$?" >> "$S/mt.log") &'
expect remind "plain nohup" 'nohup bash run.sh >log 2>&1 &'
expect remind "after a separator" 'cd /x && nohup make test &'
expect remind "setsid" 'setsid make test >log 2>&1 < /dev/null &'
expect remind "disown" 'make test >log 2>&1 & disown'
expect remind "path-qualified launcher" '/usr/bin/nohup make test >log 2>&1 &'
expect remind "adjacent redirection" 'nohup>log make test &'
expect remind "multi-line script" $'S=/tmp/x\nnohup make test >"$S/log" 2>&1 &'

# Mentions that are not a detach.
expect quiet "no detach" 'make test'
expect quiet "plain background ampersand" 'sleep 1 &'
expect quiet "nohup output file" 'tail -5 nohup.out'
expect quiet "word inside double quotes" 'git commit -m "stop using nohup for lanes"'
expect quiet "word inside single quotes" "grep -n 'nohup' hooks/*.sh"
expect quiet "longer word" 'echo nohupx setsidy'
expect quiet "multi-line double-quoted message" $'git commit -m "notes\nnohup is discouraged for lanes\n"'
expect quiet "multi-line single-quoted message" $'git commit -m \'notes\nnohup is discouraged\n\''
expect quiet "escaped quote inside double quotes" 'echo "say \"hi\" then nohup stays text"'
expect remind "detach after a quoted argument" 'nohup bash -c "make test" >log 2>&1 &'

# Payloads that carry no command stay silent.
for payload in '{}' '{"tool_input":{}}' 'not json'; do
  out=$(printf '%s' "$payload" | bash "$HOOK" 2>"$ERR"); rc=$?
  if [ "$rc" = 0 ] && [ -z "$out" ] && [ ! -s "$ERR" ]; then pass=$((pass + 1)); else
    echo "FAIL [payload $payload]: must be silent (rc=$rc, out=$out)"; fail=$((fail + 1)); fi
done

# Wired in both hosts: Claude Code hooks.json and the OpenCode binding table.
ROOT="$(cd "$SCRIPT_DIR/.." && pwd -P)"
if jq -e '[.hooks.PreToolUse[] | select(.matcher == "Bash") | .hooks[].command] | any(contains("remind-untracked-background.sh"))' "$ROOT/hooks/hooks.json" >/dev/null; then
  pass=$((pass + 1)); else echo "FAIL: hooks.json does not run the hook before Bash"; fail=$((fail + 1)); fi
if grep -q '"remind-untracked-background.sh": "tool.execute.before:bash"' "$ROOT/packages/opencode-plugin/ccl-skills.ts" \
   && grep -q 'runHook(hooksRoot, "remind-untracked-background.sh"' "$ROOT/packages/opencode-plugin/ccl-skills.ts"; then
  pass=$((pass + 1)); else echo "FAIL: OpenCode plugin does not bind and run the hook"; fail=$((fail + 1)); fi

echo "remind_untracked_background: pass=$pass fail=$fail"
[ "$fail" = 0 ] || exit 1
echo "test_remind_untracked_background_ok"
