#!/usr/bin/env bash
# Regression tests for review_diff.py, the lean runner where the reviewer reads
# the diff itself read-only. Fake codex/claude/opencode/kimi executables stand in
# for the real CLIs; FAKE_* variables choose their behavior and they log what
# they saw.
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/../../.." && pwd)"
runner="$script_dir/review_diff.py"
hook="$repo_root/hooks/remind-review-covers-head.sh"
evidence_check="$repo_root/skills/skill-extraction-workflow/scripts/check_review_evidence_present.py"

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
fail=0

note_fail() {
  printf 'FAIL %s: %s\n' "$1" "$2" >&2
  fail=1
}

# Only fakes and the tools the runner needs are on PATH, so no test can reach a
# real reviewer CLI installed next to python3.
mkdir -p "$work/sysbin"
for tool in git python3; do ln -sf "$(command -v "$tool")" "$work/sysbin/$tool"; done
TEST_PATH="$work/bin:$work/sysbin:/usr/bin:/bin"
# The user's own OpenCode and Kimi configs are never read.
user_config="$work/user-config" user_data="$work/user-data"
export XDG_CONFIG_HOME="$user_config" XDG_DATA_HOME="$user_data" KIMI_CODE_HOME="$work/user-kimi"
unset OPENCODE_CONFIG OPENCODE_CONFIG_DIR OPENCODE_CONFIG_CONTENT OPENCODE_PERMISSION

make_fakes() {
  local bin="$work/bin"
  mkdir -p "$bin"
  cat >"$bin/codex" <<'EOF'
#!/usr/bin/env bash
out=""
args=("$@")
for ((i = 0; i < ${#args[@]}; i++)); do
  [ "${args[$i]}" = "-o" ] && out="${args[$((i + 1))]}"
done
prompt="$(cat)"
{
  printf 'args=%s\n' "$*"
  printf 'codex_home=%s\n' "${CODEX_HOME:-}"
} >>"$FAKE_LOG.codex"
printf '%s' "$prompt" >"$FAKE_LOG.codex.prompt"
diff_file="$(grep -o '/[^ `]*\.diff' "$FAKE_LOG.codex.prompt" | head -1)"
if [ -n "$diff_file" ] && grep -q '^diff --git' "$diff_file" 2>/dev/null; then echo yes >"$FAKE_LOG.codex.diff"; fi
[ -n "${CODEX_HOME:-}" ] && cp "$CODEX_HOME/config.toml" "$FAKE_LOG.codex.config" 2>/dev/null
[ -n "${CODEX_HOME:-}" ] && [ -L "$CODEX_HOME/auth.json" ] && readlink "$CODEX_HOME/auth.json" >"$FAKE_LOG.codex.auth"
case "${FAKE_CODEX:-findings}" in
  findings) printf '[P1] Reject the empty key — src/app.py:2\n\nAn empty key reaches the store.\n' >"$out" ;;
  passed) printf 'No findings.\n' >"$out" ;;
  garbage) printf 'I looked around and it seems fine overall.\n' >"$out" ;;
  empty) : >"$out" ;;
  slow) sleep 30 ;;
  interrupt) exit 130 ;;
  mutate) printf 'changed\n' >>"$FAKE_REPO/src/app.py"; printf 'No findings.\n' >"$out" ;;
  failclean) printf 'No findings.\n' >"$out"; exit 1 ;;
  failfinding) printf '[P1] Keep the guard — src/app.py:2\n\nThe guard is gone.\n' >"$out"; exit 1 ;;
  headeronly) printf '[P1] Example finding — src/app.py:1\n' >"$out" ;;
  leak) printf 'sk-leaked-token partial\n' >"$out"; sleep 30 ;;
  stderr) printf 'auth expired\n' >&2; exit 1 ;;
  quote) printf '[P1] Remove the hardcoded credential — src/app.py:2\n\nIt sets %s = "%s" and ships %s.\n' "pass""word" "hunt""er2hunter2" "ghp_""abcdefghijklmnopqrstuvwxyz0123456789" >"$out" ;;
  swaplinks) rm -f "$FAKE_REPO/a" "$FAKE_REPO/c"; ln -s x "$FAKE_REPO/a"; ln -s y "$FAKE_REPO/bc"; printf 'No findings.\n' >"$out" ;;
  unicode) printf 'more\n' >>"$FAKE_REPO/src/é.py"; printf 'No findings.\n' >"$out" ;;
  commit) git -C "$FAKE_REPO" commit -q --allow-empty -m during; printf 'No findings.\n' >"$out" ;;
  holdpipe) setsid sleep 30 & sleep 30 ;;
  orphan) sleep 60 >/dev/null 2>&1 & echo $! >"$FAKE_LOG.orphan"; exit 130 ;;
  hedged) printf 'The repository reads failed, so this review is incomplete.\nNo findings.\n' >"$out" ;;
  swapoc) sed -i.bak 's#deepseek/deepseek-chat#anthropic/claude-test#' "$FAKE_OC_CONFIG"; exit 1 ;;
esac
EOF
  cat >"$bin/claude" <<'EOF'
#!/usr/bin/env bash
cat >"$FAKE_LOG.claude.prompt"
printf 'args=%s\n' "$*" >>"$FAKE_LOG.claude"
diff_file="$(grep -o '/[^ `]*\.diff' "$FAKE_LOG.claude.prompt" | head -1)"
if [ -n "$diff_file" ] && grep -q '^diff --git' "$diff_file" 2>/dev/null; then echo yes >"$FAKE_LOG.claude.diff"; fi
case "${FAKE_CLAUDE:-passed}" in
  passed) printf 'No findings.\n' ;;
  findings) printf '[P2] Close the handle — src/app.py:1\n\nThe handle leaks.\n' ;;
  fail) exit 1 ;;
esac
EOF
  cat >"$bin/opencode" <<'EOF'
#!/usr/bin/env bash
cat >/dev/null
printf 'args=%s\n' "$*" >>"$FAKE_LOG.opencode"
oc_args=("$@")
for ((i = 0; i < ${#oc_args[@]}; i++)); do
  [ "${oc_args[$i]}" = "--dir" ] && oc_dir="${oc_args[$((i + 1))]}"
done
printf 'dir=%s\ntoplevel=%s\ndotopencode=%s\n' "${oc_dir:-}" "$(git -C "${oc_dir:-/nonexistent}" rev-parse --show-toplevel 2>/dev/null)" \
  "$(ls -A "${oc_dir:-/nonexistent}" 2>/dev/null | grep -c '^\.opencode$')" >"$FAKE_LOG.opencode.project"
printf '%s' "${@: -1}" >"$FAKE_LOG.opencode.prompt"
{
  printf 'xdg_config=%s\nxdg_data=%s\n' "$(printenv XDG_CONFIG_HOME)" "$(printenv XDG_DATA_HOME)"
  printf 'no_project=%s\nno_plugins=%s\npure=%s\n' "${OPENCODE_DISABLE_PROJECT_CONFIG:-}" "${OPENCODE_DISABLE_DEFAULT_PLUGINS:-}" "${OPENCODE_PURE:-}"
} >"$FAKE_LOG.opencode.env"
oc_config_dir="$(printenv XDG_CONFIG_HOME)" oc_data_dir="$(printenv XDG_DATA_HOME)"
cp "$oc_config_dir/opencode/opencode.json" "$FAKE_LOG.opencode.config" 2>/dev/null
[ -L "$oc_data_dir/opencode/auth.json" ] && readlink "$oc_data_dir/opencode/auth.json" >"$FAKE_LOG.opencode.auth"
diff_file="$(printf '%s' "${@: -1}" | grep -o '/[^ `]*\.diff' | head -1)"
if [ -n "$diff_file" ] && grep -q '^diff --git' "$diff_file" 2>/dev/null; then echo yes >"$FAKE_LOG.opencode.diff"; fi
case "${FAKE_OPENCODE:-passed}" in
  passed) printf 'No findings.\n' ;;
  findings) printf '[P2] Bound the loop — src/app.py:2\n\nThe loop never ends.\n' ;;
  fail) exit 1 ;;
esac
EOF
  cat >"$bin/kimi" <<'EOF'
#!/usr/bin/env bash
cat >/dev/null
args=("$@")
printf 'args=%s\n' "$*" >>"$FAKE_LOG.kimi"
printf 'trust=%s\nwatch=%s\n' "${KIMI_CODE_TRUST_WORKSPACE:-}" "${KIMI_CODE_WATCH:-}" >"$FAKE_LOG.kimi.env"
cp "$KIMI_CODE_HOME/config.toml" "$FAKE_LOG.kimi.config" 2>/dev/null
[ -L "$KIMI_CODE_HOME/credentials" ] && readlink "$KIMI_CODE_HOME/credentials" >"$FAKE_LOG.kimi.auth"
ls -A "$KIMI_CODE_HOME" >"$FAKE_LOG.kimi.home"
for ((i = 0; i < ${#args[@]}; i++)); do
  [ "${args[$i]}" = "-p" ] && prompt="${args[$((i + 1))]}"
done
diff_file="$(printf '%s' "${prompt:-}" | grep -o '/[^ `]*\.diff' | head -1)"
if [ -n "$diff_file" ] && grep -q '^diff --git' "$diff_file" 2>/dev/null; then echo yes >"$FAKE_LOG.kimi.diff"; fi
# Kimi's stream-json prints one event per message; only the last assistant
# message is the answer.
say() { python3 -c 'import json,sys; print(json.dumps({"role": "assistant", "content": sys.argv[1]}))' "$1"; }
printf '{"role": "meta", "type": "system.version", "version": "2"}\n'
printf '{"role": "assistant", "content": "Let me read the diff.", "tool_calls": [{"type": "function", "id": "t1", "function": {"name": "Read", "arguments": "{}"}}]}\n'
printf '{"role": "tool", "tool_call_id": "t1", "content": "diff"}\n'
case "${FAKE_KIMI:-passed}" in
  passed) say 'No findings.' ;;
  preamble) say 'I checked the loop and the config handling.'; say 'No findings.' ;;
  findings) say "$(printf '[P2] Close the file — src/app.py:1\n\nThe file stays open.')" ;;
  blocks) say 'Let me read the diff first.'; say "$(printf '[P2] Close the file — src/app.py:1\n\nThe file stays open.')" ;;
  truncated) say 'No findings.'; printf '{"role": "assistant", "content": "[P1] Keep the guard\n' ;;
  fail) exit 1 ;;
esac
printf '{"role": "meta", "type": "session.resume_hint", "content": "To resume this session"}\n'
EOF
  chmod +x "$bin/codex" "$bin/claude" "$bin/opencode" "$bin/kimi"
}

new_repo() {
  local repo="$work/repo-$1"
  rm -rf "$repo"
  mkdir -p "$repo/src"
  git -C "$repo" init -q -b main
  git -C "$repo" config user.email t@example.com
  git -C "$repo" config user.name t
  printf 'def get(key):\n    return store[key]\n' >"$repo/src/app.py"
  git -C "$repo" add -A
  git -C "$repo" commit -q -m base
  git -C "$repo" branch -q base-ref
  printf 'def get(key):\n    return store.get(key)\n' >"$repo/src/app.py"
  git -C "$repo" commit -q -am change
  printf '%s' "$repo"
}

# run_runner NAME REPO [ARGS...]: run with fakes on PATH; sets rc and out.
run_runner() {
  local name="$1" repo="$2"
  shift 2
  export FAKE_LOG="$work/log-$name" FAKE_REPO="$repo"
  rm -f "$FAKE_LOG".*
  out="$work/out-$name.json"
  set +e
  PATH="$TEST_PATH" CODEX_HOME="$work/user-codex-home" XDG_CACHE_HOME="$work/cache" timeout 60 python3 "$runner" \
    --cwd "$repo" --base base-ref --mode review --intent "Use get() for missing keys" \
    --out "$out" --timeout 5 "$@" >"$work/stdout-$name" 2>"$work/stderr-$name"
  rc=$?
  set -e
}

field() { python3 -c 'import json,sys; v=json.load(open(sys.argv[1]));
for k in sys.argv[2].split("."): v=v[int(k)] if isinstance(v,list) else v.get(k)
print("" if v is None else (json.dumps(v) if isinstance(v,(bool,list,dict)) else v))' "$1" "$2"; }

expect_eq() {
  local name="$1" got="$2" want="$3"
  [ "$got" = "$want" ] || note_fail "$name" "expected '$want', got '$got'"
}

[ -f "$runner" ] || { printf 'FAIL runner missing: %s\n' "$runner" >&2; exit 1; }
make_fakes
mkdir -p "$work/user-codex-home"
printf 'model = "m-test"\nmodel_reasoning_effort = "high"\n\n[mcp_servers.danger]\ncommand = "rm"\n\n[profiles.other]\nmodel = "table-model"\n\n[hooks.state."x"]\nenabled = true\n' >"$work/user-codex-home/config.toml"
printf '{}' >"$work/user-codex-home/auth.json"
mkdir -p "$user_config/opencode" "$user_data/opencode"
printf '{}' >"$user_data/opencode/auth.json"
write_opencode_config() {
  cat >"$user_config/opencode/opencode.json" <<EOF
{"model": "$1", "small_model": "openai/gpt-small",
 "provider": {"deepseek": {"options": {"apiKey": "k"}}, "anthropic": {"options": {}}},
 "mcp": {"danger": {"type": "local", "command": ["rm"]}}, "plugin": ["evil-plugin"],
 "agent": {"build": {"permission": {"bash": "allow"}}}, "permission": "allow"}
EOF
}
write_opencode_config deepseek/deepseek-chat
printf '{\n  // user theme\n  "$schema": "https://opencode.ai/config.json",\n  "plugin": ["other-plugin"],\n}\n' >"$user_config/opencode/opencode.jsonc"
mkdir -p "$KIMI_CODE_HOME/credentials" "$KIMI_CODE_HOME/oauth" "$KIMI_CODE_HOME/hooks"
printf '{}' >"$KIMI_CODE_HOME/mcp.json"
cat >"$KIMI_CODE_HOME/config.toml" <<'EOF'
default_model = "kimi-code/k3"
base_url = "https://gateway.invalid/v1"
extra_skill_dirs = [
  "/somewhere",
]

[providers."managed:kimi-code"]
type = "kimi"

[models."kimi-code/k3"]
provider = "managed:kimi-code"

[hooks.pre]
command = "touch danger"

[tools]
enabled = ["Bash"]
EOF

# 1. Findings from codex: parsed, envelope fields, receipt.
repo="$(new_repo findings)"
run_runner findings "$repo" --implementer-family claude
expect_eq findings-rc "$rc" 1
expect_eq findings-status "$(field "$out" status)" findings
expect_eq findings-schema "$(field "$out" schema_version)" 3
expect_eq findings-mode "$(field "$out" mode)" review
expect_eq findings-client "$(field "$out" selected_client)" codex
expect_eq findings-severity "$(field "$out" findings.0.severity)" P1
expect_eq findings-file "$(field "$out" findings.0.file)" src/app.py
expect_eq findings-line "$(field "$out" findings.0.line)" 2
receipt="$(git -C "$repo" rev-parse --absolute-git-dir)/ccl-code-review/last-review.json"
expect_eq findings-receipt-head "$(field "$receipt" head)" "$(git -C "$repo" rev-parse HEAD)"
expect_eq findings-receipt-status "$(field "$receipt" status)" findings
expect_eq findings-receipt-clean "$(field "$receipt" worktree_clean)" true
[ -n "$(field "$receipt" recorded_at)" ] || note_fail findings-receipt-time "recorded_at missing"
grep -q 'base-ref\|'"$(git -C "$repo" rev-parse base-ref)" "$FAKE_LOG.codex.prompt" || note_fail findings-prompt-base "prompt does not name the base"
grep -q 'Use get() for missing keys' "$FAKE_LOG.codex.prompt" || note_fail findings-prompt-intent "prompt lacks the intent"
grep -q 'including ones you could not fully confirm' "$FAKE_LOG.codex.prompt" || note_fail findings-prompt-suspected "review brief drops unconfirmed suspicions"
expect_eq codex-diff-file "$(cat "$FAKE_LOG.codex.diff" 2>/dev/null)" yes
if grep -q 'Run `git diff' "$FAKE_LOG.codex.prompt"; then note_fail codex-own-diff "codex told to build the diff itself"; fi
expect_eq codex-model "$(field "$out" attempts.0.model)" m-test

# 2. Codex runs read-only under a private home without MCP servers or hooks.
grep -q -- '-s read-only' "$FAKE_LOG.codex" || note_fail codex-sandbox "codex not run with -s read-only"
home_used="$(sed -n 's/^codex_home=//p' "$FAKE_LOG.codex" | head -1)"
[ -n "$home_used" ] && [ "$home_used" != "$work/user-codex-home" ] || note_fail codex-home "reviewer used the user's CODEX_HOME"
grep -q 'model = "m-test"' "$FAKE_LOG.codex.config" 2>/dev/null || note_fail codex-model "model preference not carried"
if grep -q -E 'mcp_servers|hooks' "$FAKE_LOG.codex.config" 2>/dev/null; then note_fail codex-isolation "mcp_servers or hooks leaked into the reviewer home"; fi
if grep -q 'table-model' "$FAKE_LOG.codex.config" 2>/dev/null; then note_fail codex-toplevel "a key inside a table was carried as top-level"; fi
expect_eq codex-auth-link "$(cat "$FAKE_LOG.codex.auth" 2>/dev/null)" "$work/user-codex-home/auth.json"
[ ! -e "$home_used" ] || note_fail codex-home-cleanup "private home left behind"
case "$home_used" in "$work/cache/ccl-code-review/"*) ;; *) note_fail codex-home-place "private home not under the cache dir: $home_used" ;; esac

# 3. Passed.
repo="$(new_repo passed)"
FAKE_CODEX=passed run_runner passed "$repo" --implementer-family claude
expect_eq passed-rc "$rc" 0
expect_eq passed-status "$(field "$out" status)" passed

# 4. Unparseable output is inconclusive.
repo="$(new_repo garbage)"
FAKE_CODEX=garbage run_runner garbage "$repo" --implementer-family kimi --client-order codex
expect_eq garbage-rc "$rc" 2
expect_eq garbage-status "$(field "$out" status)" inconclusive

# 5. A timeout is inconclusive.
repo="$(new_repo timeout)"
FAKE_CODEX=slow run_runner timeout "$repo" --implementer-family kimi --client-order codex --timeout 2
expect_eq timeout-rc "$rc" 2
expect_eq timeout-reason "$(field "$out" reason_code)" reviewer_timeout

# 5b. A timed-out answer is never read, and raw text stays out of the result.
repo="$(new_repo leak)"
FAKE_CODEX=leak run_runner leak "$repo" --implementer-family claude --client-order codex --timeout 2
if grep -q 'sk-leaked-token' "$out"; then note_fail leak-result "timed-out answer copied into the result"; fi
diag="$(field "$out" diagnostics_path)"
if [ -n "$diag" ] && grep -q 'sk-leaked-token' "$diag"; then note_fail leak-diag "timed-out answer kept in diagnostics"; fi

# 5c. Reviewer stderr goes to a private diagnostics file, not the result.
repo="$(new_repo stderr)"
FAKE_CODEX=stderr run_runner stderr "$repo" --implementer-family claude --client-order codex
expect_eq stderr-reason "$(field "$out" reason_code)" reviewer_failed
diag="$(field "$out" diagnostics_path)"
grep -q 'auth expired' "$diag" 2>/dev/null || note_fail stderr-diag "stderr not kept for diagnosis"
expect_eq stderr-mode "$(stat -c %a "$diag" 2>/dev/null || stat -f %Lp "$diag")" 600
if grep -q 'auth expired' "$out"; then note_fail stderr-result "stderr copied into the result"; fi

# 6. Empty output is inconclusive.
repo="$(new_repo empty)"
FAKE_CODEX=empty run_runner empty "$repo" --implementer-family kimi --client-order codex
expect_eq empty-reason "$(field "$out" reason_code)" empty_answer

# 7. Interrupt is terminal: no fallback.
repo="$(new_repo interrupt)"
FAKE_CODEX=interrupt run_runner interrupt "$repo" --implementer-family kimi
expect_eq interrupt-rc "$rc" 2
expect_eq interrupt-status "$(field "$out" status)" inconclusive
[ ! -e "$FAKE_LOG.claude" ] && [ ! -e "$FAKE_LOG.opencode" ] || note_fail interrupt-fallback "another reviewer ran after an interrupt"

# 8. Same-family reviewer is skipped; Claude runs with a read-only tool surface.
repo="$(new_repo samefamily)"
FAKE_CLAUDE=findings run_runner samefamily "$repo" --implementer-family codex
expect_eq samefamily-client "$(field "$out" selected_client)" claude
[ ! -e "$FAKE_LOG.codex" ] || note_fail samefamily-skip "same-family codex was run"
args="$(cat "$FAKE_LOG.claude" 2>/dev/null || true)"
for want in '--tools Read Grep Glob --' '--permission-mode dontAsk' '--strict-mcp-config' '--setting-sources' '--add-dir'; do
  case "$args" in *"$want"*) ;; *) note_fail claude-args "missing '$want' in: $args" ;; esac
done
case "$args" in *Edit*|*Write*|*Bash*) note_fail claude-write "write-capable tool offered: $args" ;; esac
expect_eq claude-diff-file "$(cat "$FAKE_LOG.claude.diff" 2>/dev/null)" yes

# 8b. Family aliases: an "openai" implementer still excludes Codex.
repo="$(new_repo alias)"
run_runner alias "$repo" --implementer-family OpenAI
expect_eq alias-client "$(field "$out" selected_client)" claude
[ ! -e "$FAKE_LOG.codex" ] || note_fail alias-skip "codex ran for an openai implementer"

# 8c. A failed exit never yields a verdict, even with a clean answer.
repo="$(new_repo failclean)"
FAKE_CODEX=failclean run_runner failclean "$repo" --implementer-family kimi --client-order codex
expect_eq failclean-status "$(field "$out" status)" inconclusive
expect_eq failclean-reason "$(field "$out" reason_code)" reviewer_failed

# 8d. A clean sentinel inside other text is not a pass.
repo="$(new_repo hedged)"
FAKE_CODEX=hedged run_runner hedged "$repo" --implementer-family claude --client-order codex
expect_eq hedged-status "$(field "$out" status)" inconclusive

# 8e. A failed run that wrote a finding is still inconclusive, never passed.
repo="$(new_repo failfinding)"
FAKE_CODEX=failfinding run_runner failfinding "$repo" --implementer-family kimi --client-order codex
expect_eq failfinding-status "$(field "$out" status)" inconclusive

# 8f. A finding header without its scenario is not a verdict.
repo="$(new_repo headeronly)"
FAKE_CODEX=headeronly run_runner headeronly "$repo" --implementer-family claude --client-order codex
expect_eq headeronly-status "$(field "$out" status)" inconclusive

# 8g. An implementer whose model family is unknown is refused before any review.
repo="$(new_repo ambiguous)"
run_runner ambiguous "$repo" --implementer-family opencode
expect_eq ambiguous-rc "$rc" 2
expect_eq ambiguous-reason "$(field "$out" reason_code)" implementer_family_ambiguous
[ ! -e "$FAKE_LOG.codex" ] && [ ! -e "$FAKE_LOG.claude" ] && [ ! -e "$FAKE_LOG.opencode" ] && [ ! -e "$FAKE_LOG.kimi" ] || note_fail ambiguous-run "a reviewer ran for an ambiguous family"

# 8h. A descendant holding the reviewer's pipes cannot stall the runner.
repo="$(new_repo holdpipe)"
t0=$(date +%s)
FAKE_CODEX=holdpipe run_runner holdpipe "$repo" --implementer-family kimi --client-order codex --timeout 2
[ $(( $(date +%s) - t0 )) -lt 20 ] || note_fail holdpipe-bound "runner waited on a descendant's pipe"
expect_eq holdpipe-reason "$(field "$out" reason_code)" reviewer_timeout

# 8i. An interrupted reviewer leaves no descendants behind.
repo="$(new_repo orphan)"
FAKE_CODEX=orphan run_runner orphan "$repo" --implementer-family kimi
sleep 0.5
if [ -s "$FAKE_LOG.orphan" ] && kill -0 "$(cat "$FAKE_LOG.orphan")" 2>/dev/null; then
  note_fail orphan-cleanup "reviewer child still running"; kill "$(cat "$FAKE_LOG.orphan")" 2>/dev/null || true
fi

# 9. Missing CLI is skipped.
repo="$(new_repo missing)"
rm "$work/bin/codex"
run_runner missing "$repo" --implementer-family kimi
expect_eq missing-client "$(field "$out" selected_client)" claude
make_fakes

clients() { python3 -c 'import json,sys; print(",".join(a["client"] for a in json.load(open(sys.argv[1]))["attempts"]))' "$1"; }

# 9b. A failed reviewer hands over to the next eligible one.
repo="$(new_repo trynext)"
FAKE_CODEX=slow run_runner trynext "$repo" --implementer-family kimi --timeout 2 --client-order codex,claude
expect_eq trynext-rc "$rc" 0
expect_eq trynext-status "$(field "$out" status)" passed
expect_eq trynext-client "$(field "$out" selected_client)" claude
expect_eq trynext-attempts "$(clients "$out")" codex,claude
expect_eq trynext-first "$(field "$out" attempts.0.status)" reviewer_timeout

# 9c. A failed run's finding never reaches the next reviewer's verdict.
repo="$(new_repo carried)"
FAKE_CODEX=failfinding run_runner carried "$repo" --implementer-family kimi --client-order codex,claude
expect_eq carried-status "$(field "$out" status)" passed
expect_eq carried-findings "$(field "$out" findings)" "[]"

# 9d. Default order puts OpenCode before Kimi; every failure moves on.
repo="$(new_repo allfail)"
FAKE_CODEX=failclean FAKE_OPENCODE=fail FAKE_KIMI=fail run_runner allfail "$repo" --implementer-family claude
expect_eq allfail-rc "$rc" 2
expect_eq allfail-attempts "$(clients "$out")" codex,opencode,kimi
expect_eq allfail-reason "$(field "$out" reason_code)" reviewer_failed

# 9e. OpenCode runs under a private config with read tools only.
repo="$(new_repo opencode)"
FAKE_CODEX=failclean run_runner opencode "$repo" --implementer-family claude
expect_eq opencode-client "$(field "$out" selected_client)" opencode
expect_eq opencode-family "$(field "$out" reviewer_family)" deepseek
expect_eq opencode-attempts "$(clients "$out")" codex,opencode
[ ! -e "$FAKE_LOG.kimi" ] || note_fail opencode-stop "kimi ran after opencode answered"
args="$(cat "$FAKE_LOG.opencode" 2>/dev/null || true)"
for want in 'run ' '--agent ccl-review' '-m deepseek/deepseek-chat' '--dir '; do
  case "$args" in *"$want"*) ;; *) note_fail opencode-args "missing '$want' in: $args" ;; esac
done
grep -q '^no_project=1$' "$FAKE_LOG.opencode.env" 2>/dev/null || note_fail opencode-project "project config not disabled"
grep -q '^no_plugins=1$' "$FAKE_LOG.opencode.env" 2>/dev/null || note_fail opencode-plugins "default plugins not disabled"
grep -q '^pure=1$' "$FAKE_LOG.opencode.env" 2>/dev/null || note_fail opencode-pure "external plugins not disabled"
# OpenCode imports .opencode/plugin code from its project and parents, so its
# project is a private empty git repository, never the candidate.
oc_dir="$(sed -n 's/^dir=//p' "$FAKE_LOG.opencode.project" 2>/dev/null || true)"
[ -n "$oc_dir" ] && [ "$oc_dir" != "$repo" ] || note_fail opencode-project-dir "opencode ran with the candidate as its project: $oc_dir"
expect_eq opencode-project-root "$(sed -n 's/^toplevel=//p' "$FAKE_LOG.opencode.project" 2>/dev/null || true)" "$oc_dir"
expect_eq opencode-project-empty "$(sed -n 's/^dotopencode=//p' "$FAKE_LOG.opencode.project" 2>/dev/null || true)" 0
grep -q "$repo" "$FAKE_LOG.opencode.prompt" 2>/dev/null || note_fail opencode-prompt-repo "prompt does not name the repository path"
oc_config_home="$(sed -n 's/^xdg_config=//p' "$FAKE_LOG.opencode.env" 2>/dev/null || true)"
[ -n "$oc_config_home" ] && [ "$oc_config_home" != "$user_config" ] || note_fail opencode-home "reviewer used the user's config dir"
[ ! -e "$oc_config_home" ] || note_fail opencode-cleanup "private config left behind"
expect_eq opencode-auth "$(cat "$FAKE_LOG.opencode.auth" 2>/dev/null)" "$user_data/opencode/auth.json"
expect_eq opencode-diff-file "$(cat "$FAKE_LOG.opencode.diff" 2>/dev/null)" yes
oc_check="$(python3 - "$FAKE_LOG.opencode.config" 2>/dev/null <<'PY' || echo config-missing
import json, sys
c = json.load(open(sys.argv[1]))
bad = [k for k in ("mcp", "plugin", "instructions") if k in c]
if c.get("model") != "deepseek/deepseek-chat" or c.get("small_model") != c.get("model"):
    bad.append("model")
if sorted(c.get("provider", {})) != ["deepseek"]:
    bad.append("provider")
for name, perm in (("top", c.get("permission")), ("agent", c.get("agent", {}).get("ccl-review", {}).get("permission"))):
    if not isinstance(perm, dict) or perm.get("*") != "deny":
        bad.append(name + ":default")
        continue
    allowed = sorted(k for k, v in perm.items() if v == "allow")
    if allowed != ["glob", "grep", "list", "read"]:
        bad.append(name + ":" + ",".join(allowed))
    ext = perm.get("external_directory", {})
    if ext.get("*") != "deny" or len([v for v in ext.values() if v == "allow"]) != 2:
        bad.append(name + ":external")
if set(c.get("agent", {})) != {"ccl-review"}:
    bad.append("agents")
print(" ".join(bad) or "ok")
PY
)"
expect_eq opencode-config "$oc_check" ok

# 9e2. A comma inside a config string value is not a trailing comma.
repo="$(new_repo occomma)"
python3 - "$user_config/opencode/opencode.json" <<'PY'
import json, sys
c = json.load(open(sys.argv[1])); c["provider"]["deepseek"]["options"]["apiKey"] = "tok,}"
open(sys.argv[1], "w").write(json.dumps(c))
PY
printf '{\n  "model": "deepseek/deepseek-other", // pinned\n  "plugin": ["x"], /* last */\n}\n' >"$user_config/opencode/opencode.jsonc"
FAKE_CODEX=failclean run_runner occomma "$repo" --implementer-family claude
expect_eq occomma-jsonc "$(field "$out" attempts.1.model 2>/dev/null || true)" deepseek/deepseek-other
printf '{\n  // user theme\n  "$schema": "https://opencode.ai/config.json",\n  "plugin": ["other-plugin"],\n}\n' >"$user_config/opencode/opencode.jsonc"
expect_eq occomma-key "$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["provider"]["deepseek"]["options"]["apiKey"])' "$FAKE_LOG.opencode.config" 2>/dev/null || true)" "tok,}"
write_opencode_config deepseek/deepseek-chat

# 9f. OpenCode's family comes from its model: same or unknown family is skipped.
repo="$(new_repo ocfamily)"
write_opencode_config anthropic/claude-test
FAKE_CODEX=failclean run_runner ocfamily "$repo" --implementer-family claude
expect_eq ocfamily-attempts "$(clients "$out")" codex,kimi
expect_eq ocfamily-skip "$(python3 -c 'import json,sys; print([s["reason"] for s in json.load(open(sys.argv[1]))["skipped"] if s["client"]=="opencode"])' "$out")" "['same_family']"
write_opencode_config acme/house-model
FAKE_CODEX=failclean run_runner ocunknown "$repo" --implementer-family claude
expect_eq ocunknown-attempts "$(clients "$out")" codex,kimi
write_opencode_config deepseek/deepseek-chat
run_runner deepseek "$repo" --implementer-family deepseek
expect_eq deepseek-client "$(field "$out" selected_client)" codex
[ ! -e "$FAKE_LOG.opencode" ] || note_fail deepseek-skip "same-family opencode ran"

# 9f1. The model id decides the family before the provider alias does.
repo="$(new_repo ocprovider)"
write_opencode_config openai/deepseek-chat
FAKE_CODEX=failclean FAKE_CLAUDE=fail run_runner ocprovider "$repo" --implementer-family deepseek
expect_eq ocprovider-attempts "$(clients "$out")" codex,claude,kimi
# A provider name never establishes the family of an unknown model.
write_opencode_config openai/house-model
FAKE_CODEX=failclean run_runner ochouse "$repo" --implementer-family claude
expect_eq ochouse-attempts "$(clients "$out")" codex,kimi
write_opencode_config deepseek/deepseek-chat

# 9f1b. Eligibility and launch use one config snapshot.
repo="$(new_repo ocsnapshot)"
FAKE_OC_CONFIG="$user_config/opencode/opencode.json" FAKE_CODEX=swapoc run_runner ocsnapshot "$repo" --implementer-family claude
case "$(cat "$FAKE_LOG.opencode" 2>/dev/null || true)" in
  *"-m deepseek/deepseek-chat"*) ;; *) note_fail ocsnapshot-model "opencode launched with a model other than the one judged independent" ;;
esac
expect_eq ocsnapshot-family "$(field "$out" reviewer_family)" deepseek
write_opencode_config deepseek/deepseek-chat

# 9f2. A reviewer whose private home cannot be built counts as a failed launch.
repo="$(new_repo setupfail)"
export FAKE_LOG="$work/log-setupfail" FAKE_REPO="$repo"
rm -f "$FAKE_LOG".*
set +e
FAKE_CODEX=failclean PATH="$TEST_PATH" CODEX_HOME="$work/user-codex-home" XDG_CACHE_HOME="$work/cache" timeout 60 python3 -c '
import importlib.util, sys
spec = importlib.util.spec_from_file_location("review_diff", sys.argv[1])
m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m)
def boom(*a, **k):
    raise OSError("no space left")
m.clients.private_opencode_root = boom
sys.exit(m.main(sys.argv[2:]))' "$runner" --cwd "$repo" --base base-ref --intent x --implementer-family claude \
  --out "$work/out-setupfail.json" >/dev/null 2>"$work/stderr-setupfail"
rc=$?
set -e
out="$work/out-setupfail.json"
expect_eq setupfail-rc "$rc" 0
expect_eq setupfail-attempts "$(clients "$out" 2>/dev/null || true)" codex,opencode,kimi
expect_eq setupfail-status "$(field "$out" attempts.1.status 2>/dev/null || true)" reviewer_launch_failed

# 9f3. Kimi's family comes from the model its alias selects; unknown is skipped.
repo="$(new_repo kimialias)"
cp "$KIMI_CODE_HOME/config.toml" "$work/kimi.saved"
printf 'default_model = "review"\n\n[models.review]\nmodel = "claude-test"\nprovider = "proxy"\n' >"$KIMI_CODE_HOME/config.toml"
FAKE_CODEX=failclean FAKE_OPENCODE=fail run_runner kimialias "$repo" --implementer-family claude
expect_eq kimialias-attempts "$(clients "$out")" codex,opencode
printf 'default_model = "house-model"\n\n[models.house-model]\nmodel = "house-1"\nprovider = "proxy"\n' >"$KIMI_CODE_HOME/config.toml"
FAKE_CODEX=failclean FAKE_OPENCODE=fail run_runner kimiunknown "$repo" --implementer-family claude
expect_eq kimiunknown-attempts "$(clients "$out")" codex,opencode
# An inline model table is read structurally, like a [models.<alias>] header.
printf 'default_model = "kimi-review"\n\n[models]\nkimi-review = { model = "claude-test", provider = "proxy" }\n' >"$KIMI_CODE_HOME/config.toml"
FAKE_CODEX=failclean FAKE_OPENCODE=fail run_runner kimiinline "$repo" --implementer-family claude
expect_eq kimiinline-attempts "$(clients "$out")" codex,opencode
# Dotted top-level model and provider assignments are carried like tables.
printf 'default_model = "r"\nproviders.p = { type = "kimi" }\nmodels.r = { model = "k9", provider = "p" }\n' >"$KIMI_CODE_HOME/config.toml"
FAKE_CODEX=failclean FAKE_OPENCODE=fail run_runner kimidotted "$repo" --implementer-family claude
expect_eq kimidotted-status "$(field "$out" status 2>/dev/null || true)" passed
grep -q '^models.r = ' "$FAKE_LOG.kimi.config" 2>/dev/null || note_fail kimidotted-carried "dotted model assignment not carried"
# A kimi-type provider on an endpoint outside Moonshot's own says nothing about the model.
printf 'default_model = "r"\n\n[models.r]\nmodel = "house-model"\nprovider = "p"\n\n[providers.p]\ntype = "kimi"\nbase_url = "https://gateway.invalid/v1"\n' >"$KIMI_CODE_HOME/config.toml"
FAKE_CODEX=failclean FAKE_OPENCODE=fail run_runner kimigateway "$repo" --implementer-family claude
expect_eq kimigateway-attempts "$(clients "$out")" codex,opencode
printf 'default_model = "r"\n\n[models.r]\nmodel = "k9"\nprovider = "p"\n\n[providers.p]\ntype = "kimi"\nbase_url = "https://api.moonshot.cn/v1"\n' >"$KIMI_CODE_HOME/config.toml"
FAKE_CODEX=failclean FAKE_OPENCODE=fail run_runner kimifirstparty "$repo" --implementer-family claude
expect_eq kimifirstparty-attempts "$(clients "$out")" codex,opencode,kimi
# Valid TOML of an unexpected shape skips only Kimi; the run still answers.
printf 'default_model = "r"\nmodels = "kimi-latest"\n' >"$KIMI_CODE_HOME/config.toml"
run_runner kimiscalar "$repo" --implementer-family claude
expect_eq kimiscalar-status "$(field "$out" status 2>/dev/null || true)" findings
printf 'default_model = 1\n' >"$KIMI_CODE_HOME/config.toml"
run_runner kimiint "$repo" --implementer-family claude
expect_eq kimiint-status "$(field "$out" status 2>/dev/null || true)" findings
# A config form the carried subset would change skips Kimi rather than launch with it.
printf 'default_model = "r"\n\n[models.r]\nmodel = "kimi-x"\n\n[notes]\ntext = """\n[models.q]\nmodel = "claude-test"\n[hooks]\n"""\n' >"$KIMI_CODE_HOME/config.toml"
FAKE_CODEX=failclean FAKE_OPENCODE=fail run_runner kimistring "$repo" --implementer-family claude
expect_eq kimistring-skip "$(python3 -c 'import json,sys; print([s["reason"] for s in json.load(open(sys.argv[1]))["skipped"] if s["client"]=="kimi"])' "$out" 2>/dev/null || true)" "['config_unreadable']"
# One read decides the family and the config the reviewer launches with.
single="$(python3 -c '
import importlib.util, sys
spec = importlib.util.spec_from_file_location("review_diff", sys.argv[1])
m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m)
texts = iter([
    "default_model = \"r\"\n\n[models.r]\nmodel = \"claude-test\"\nprovider = \"p\"\n",
    "default_model = \"r\"\n\n[models.r]\nmodel = \"deepseek-chat\"\nprovider = \"p\"\n",
] * 3)
m.clients.read_config = lambda path: next(texts)
family, alias, (model, kept) = m.clients.CLIENTS["kimi"].snapshot()
print(family, "claude-test" in "\n".join(kept))' "$runner" 2>&1 || true)"
expect_eq kimi-single-read "$single" "claude True"

# 9f4. An unreadable or malformed reviewer config skips only that reviewer.
printf 'default_model\n' >"$KIMI_CODE_HOME/config.toml"
run_runner kimimalformed "$repo" --implementer-family claude
expect_eq kimimalformed-status "$(field "$out" status 2>/dev/null || true)" findings
cp "$work/kimi.saved" "$KIMI_CODE_HOME/config.toml"
chmod 000 "$KIMI_CODE_HOME/config.toml"
run_runner kimiunreadable "$repo" --implementer-family claude
chmod 600 "$KIMI_CODE_HOME/config.toml"
expect_eq kimiunreadable-status "$(field "$out" status 2>/dev/null || true)" findings
expect_eq kimiunreadable-skip "$(python3 -c 'import json,sys; print([s["reason"] for s in json.load(open(sys.argv[1]))["skipped"] if s["client"]=="kimi"])' "$out" 2>/dev/null || true)" "['config_unreadable']"

# 9g. Kimi runs under a private home with read tools only; its bulleted answer parses.
repo="$(new_repo kimi)"
KIMI_CODE_TRUST_WORKSPACE=1 FAKE_CODEX=failclean FAKE_OPENCODE=fail FAKE_KIMI=findings run_runner kimi "$repo" --implementer-family claude
expect_eq kimi-status "$(field "$out" status)" findings
expect_eq kimi-title "$(field "$out" findings.0.title)" "Close the file"
expect_eq kimi-body "$(field "$out" findings.0.body)" "The file stays open."
args="$(cat "$FAKE_LOG.kimi" 2>/dev/null || true)"
for want in '--skills-dir' '--add-dir' '-m kimi-code/k3' '--output-format stream-json'; do
  case "$args" in *"$want"*) ;; *) note_fail kimi-args "missing '$want' in: $args" ;; esac
done
grep -q '^enabled = \["Read", "Grep", "Glob"\]$' "$FAKE_LOG.kimi.config" 2>/dev/null || note_fail kimi-tools "read-only tool allowlist missing"
grep -q '^default_model = "kimi-code/k3"$' "$FAKE_LOG.kimi.config" 2>/dev/null || note_fail kimi-model "default model not carried"
grep -q '^base_url = ' "$FAKE_LOG.kimi.config" 2>/dev/null || note_fail kimi-endpoint "top-level endpoint not carried"
grep -q '^\[models."kimi-code/k3"\]$' "$FAKE_LOG.kimi.config" 2>/dev/null || note_fail kimi-models "model table not carried"
if grep -q -E 'hooks|extra_skill_dirs|somewhere|Bash' "$FAKE_LOG.kimi.config" 2>/dev/null; then note_fail kimi-isolation "hooks, skill dirs or the user's tool list carried"; fi
if grep -q -x -E 'hooks|mcp.json' "$FAKE_LOG.kimi.home" 2>/dev/null; then note_fail kimi-home "hooks or MCP config in the private home"; fi
expect_eq kimi-auth "$(cat "$FAKE_LOG.kimi.auth" 2>/dev/null)" "$KIMI_CODE_HOME/credentials"
grep -q '^trust=$' "$FAKE_LOG.kimi.env" 2>/dev/null || note_fail kimi-trust "workspace trust passed to the reviewer"
expect_eq kimi-diff-file "$(cat "$FAKE_LOG.kimi.diff" 2>/dev/null)" yes
FAKE_CODEX=failclean FAKE_OPENCODE=fail run_runner kimipass "$repo" --implementer-family claude
expect_eq kimipass-status "$(field "$out" status)" passed
FAKE_CODEX=failclean FAKE_OPENCODE=fail FAKE_KIMI=blocks run_runner kimiblocks "$repo" --implementer-family claude
expect_eq kimiblocks-title "$(field "$out" findings.0.title 2>/dev/null || true)" "Close the file"
FAKE_CODEX=failclean FAKE_OPENCODE=fail FAKE_KIMI=truncated run_runner kimitruncated "$repo" --implementer-family claude
expect_eq kimitruncated-status "$(field "$out" status 2>/dev/null || true)" inconclusive
FAKE_CODEX=failclean FAKE_OPENCODE=fail FAKE_KIMI=preamble run_runner kimipreamble "$repo" --implementer-family claude
expect_eq kimipreamble-status "$(field "$out" status 2>/dev/null || true)" passed
grep -q 'read by a program' "$FAKE_LOG.codex.prompt" 2>/dev/null || note_fail prompt-final "prompt does not say the final message is parsed"

# 10. Untracked files are named; a dirty tree is reported as such.
repo="$(new_repo untracked)"
printf 'x = 1\n' >"$repo/src/new_module.py"
FAKE_CODEX=passed run_runner untracked "$repo" --implementer-family claude
grep -q 'src/new_module.py' "$FAKE_LOG.codex.prompt" || note_fail untracked-prompt "untracked file not named in the prompt"
expect_eq untracked-clean "$(field "$out" worktree_clean)" false
[ -n "$(field "$out" candidate_digest)" ] || note_fail untracked-digest "candidate digest missing"
new_blob="$(git -C "$repo" hash-object src/new_module.py)"
if git -C "$repo" cat-file -e "$new_blob" 2>/dev/null; then note_fail untracked-objects "the review wrote working-tree content into the object store"; fi

# 10b. Hidden-untracked config and a subdirectory --cwd still see every new file.
repo="$(new_repo hidden)"
git -C "$repo" config status.showUntrackedFiles no
mkdir -p "$repo/lib"
printf 'y = 2\n' >"$repo/lib/sibling.py"
export FAKE_LOG="$work/log-hidden" FAKE_REPO="$repo" FAKE_CODEX=passed
rm -f "$FAKE_LOG".*
set +e
PATH="$TEST_PATH" CODEX_HOME="$work/user-codex-home" XDG_CACHE_HOME="$work/cache" timeout 60 python3 "$runner" \
  --cwd "$repo/src" --base base-ref --intent x --implementer-family claude --out "$work/out-hidden.json" >/dev/null 2>&1
set -e
unset FAKE_CODEX
expect_eq hidden-clean "$(field "$work/out-hidden.json" worktree_clean)" false
grep -q 'lib/sibling.py' "$FAKE_LOG.codex.prompt" 2>/dev/null || note_fail hidden-untracked "sibling untracked file not named"

# 10c. Repository git config never executes candidate scripts.
repo="$(new_repo gitexec)"
printf '#!/bin/sh\ntouch "%s"\nexec cat\n' "$work/gitexec.marker" >"$repo/evil.sh"
printf '#!/bin/sh\ntouch "%s"\nexit 1\n' "$work/gitexec.marker" >"$repo/fsmon.sh"
chmod +x "$repo/evil.sh" "$repo/fsmon.sh"
git -C "$repo" add evil.sh fsmon.sh && git -C "$repo" commit -q -m evil
printf '*.py diff=evil filter=evil\n' >"$repo/.gitattributes"
git -C "$repo" config core.fsmonitor "$repo/fsmon.sh"
git -C "$repo" config diff.evil.textconv "$repo/evil.sh"
git -C "$repo" config filter.evil.clean "$repo/evil.sh"
git -C "$repo" config filter.evil.process "$repo/evil.sh"
git -C "$repo" config diff.external "$repo/evil.sh"
rm -f "$work/gitexec.marker"
FAKE_CODEX=passed run_runner gitexec "$repo" --implementer-family claude
[ ! -e "$work/gitexec.marker" ] || note_fail gitexec "a repository-configured script ran"

# 10d. A multi-line filter command does not abort the run.
repo="$(new_repo multiline)"
git -C "$repo" config filter.multi.clean "$(printf 'cat\n  \nexit 0')"
FAKE_CODEX=passed run_runner multiline "$repo" --implementer-family claude
expect_eq multiline-status "$(field "$out" status)" passed

# 10e. A non-ASCII untracked file is named and its edits are seen.
repo="$(new_repo unicode)"
printf 'z = 3\n' >"$repo/src/é.py"
FAKE_CODEX=unicode run_runner unicode "$repo" --implementer-family claude
grep -q 'src/é.py' "$FAKE_LOG.codex.prompt" || note_fail unicode-named "non-ASCII untracked file not named"
expect_eq unicode-reason "$(field "$out" reason_code)" candidate_changed

# 10f. A commit made during the review changes the candidate.
repo="$(new_repo commit)"
FAKE_CODEX=commit run_runner commit "$repo" --implementer-family claude
expect_eq commit-reason "$(field "$out" reason_code)" candidate_changed

# 10f2. Untracked entries are framed: moving bytes between two links is a change.
repo="$(new_repo swaplinks)"
ln -s xb "$repo/a"; ln -s y "$repo/c"
FAKE_CODEX=swaplinks run_runner swaplinks "$repo" --implementer-family claude
expect_eq swaplinks-reason "$(field "$out" reason_code)" candidate_changed

# 10f3. A finding that quotes a credential is redacted in the result and output.
repo="$(new_repo quote)"
FAKE_CODEX=quote run_runner quote "$repo" --implementer-family claude
expect_eq quote-status "$(field "$out" status)" findings
if grep -q 'hunter2hunter2\|abcdefghijklmnopqrstuvwxyz0123456789' "$out" "$work/stdout-quote"; then note_fail quote-redact "a quoted credential reached the result or output"; fi
expect_eq quote-flag "$(field "$out" findings.0.redacted)" true

# 10g. A non-UTF-8 text change does not crash the runner.
repo="$(new_repo latin1)"
printf 'caf\xe9 = 1\n' >"$repo/src/latin1.py"
git -C "$repo" add src/latin1.py && git -C "$repo" commit -q -m latin1
FAKE_CODEX=passed run_runner latin1 "$repo" --implementer-family claude
expect_eq latin1-status "$(field "$out" status)" passed

# 10h. An intent that is not valid UTF-8 (a byte cut mid-character) still runs.
repo="$(new_repo badintent)"
# The cut bytes reach the runner through an exec shim: some timeout builds
# (uutils on newer Ubuntu) refuse a non-UTF-8 argument of their own.
export FAKE_LOG="$work/log-badintent" FAKE_REPO="$repo" FAKE_CODEX=passed
out="$work/out-badintent.json"
set +e
PATH="$TEST_PATH" CODEX_HOME="$work/user-codex-home" XDG_CACHE_HOME="$work/cache" timeout 60 python3 -c '
import os, sys
os.execv(sys.executable, [sys.executable] + sys.argv[1:] + ["--intent", os.fsdecode(b"cut \xe4\xb8")])' \
  "$runner" --cwd "$repo" --base base-ref --implementer-family claude --out "$out" --timeout 5 \
  >"$work/stdout-badintent" 2>"$work/stderr-badintent"
rc=$?
set -e
unset FAKE_CODEX
expect_eq badintent-rc "$rc" 0
expect_eq badintent-status "$(field "$out" status 2>/dev/null || true)" passed

# 11. A candidate that changes during the review is inconclusive.
repo="$(new_repo mutate)"
FAKE_CODEX=mutate run_runner mutate "$repo" --implementer-family claude
expect_eq mutate-rc "$rc" 2
expect_eq mutate-reason "$(field "$out" reason_code)" candidate_changed

# 12. The CI evidence check accepts the result envelope.
repo="$(new_repo ci)"
FAKE_CODEX=findings run_runner ci "$repo" --implementer-family claude
accepted="$(python3 -c 'import importlib.util,sys
from pathlib import Path
s=importlib.util.spec_from_file_location("c", sys.argv[1]); m=importlib.util.module_from_spec(s); s.loader.exec_module(m)
p=Path(sys.argv[2]); print("yes" if m.load_result(p.parent, p.name) else "no")' "$evidence_check" "$out")"
expect_eq ci-envelope "$accepted" yes

# 12b. The result temp file is never written through a symlink.
repo="$(new_repo symlink)"
mkdir -p "$work/evid"
ln -sf "$repo/src/app.py" "$work/evid/out.json.tmp"
before="$(cat "$repo/src/app.py")"
export FAKE_LOG="$work/log-symlink" FAKE_REPO="$repo" FAKE_CODEX=passed
set +e
PATH="$TEST_PATH" CODEX_HOME="$work/user-codex-home" XDG_CACHE_HOME="$work/cache" timeout 60 python3 "$runner" \
  --cwd "$repo" --base base-ref --intent x --implementer-family claude --out "$work/evid/out.json" >/dev/null 2>&1
set -e
unset FAKE_CODEX
expect_eq symlink-untouched "$(cat "$repo/src/app.py")" "$before"

# 12c. A custom model provider keeps its definition in the private home.
repo="$(new_repo provider)"
cp "$work/user-codex-home/config.toml" "$work/config.saved"
printf 'model = "m-test"\nmodel_provider = "custom" # hosted endpoint\n\n[model_providers.custom] # hosted\nbase_url = "https://example.invalid/v1"\n\n[model_providers.other]\nbase_url = "https://other.invalid"\n\n[mcp_servers.danger]\ncommand = "rm"\n' >"$work/user-codex-home/config.toml"
FAKE_CODEX=passed run_runner provider "$repo" --implementer-family claude
grep -q 'example.invalid' "$FAKE_LOG.codex.config" || note_fail provider-kept "selected provider definition dropped"
grep -q '^\[model_providers.custom\]' "$FAKE_LOG.codex.config" || note_fail provider-header "provider table header dropped"
if grep -q -E 'other.invalid|mcp_servers' "$FAKE_LOG.codex.config"; then note_fail provider-only "unselected tables carried"; fi
cp "$work/config.saved" "$work/user-codex-home/config.toml"

# 12d. A top-level Codex config line without `=` is dropped, not a crash.
repo="$(new_repo codexbare)"
printf 'model = "m-test"\nmodel_provider\n' >"$work/user-codex-home/config.toml"
FAKE_CODEX=passed run_runner codexbare "$repo" --implementer-family claude
expect_eq codexbare-status "$(field "$out" status 2>/dev/null || true)" passed
if grep -q '^model_provider$' "$FAKE_LOG.codex.config" 2>/dev/null; then note_fail codexbare-dropped "a line without = was carried"; fi
cp "$work/config.saved" "$work/user-codex-home/config.toml"

# 13. The PR reminder hook stays quiet for a passed review of a clean HEAD.
repo="$(new_repo hook)"
FAKE_CODEX=passed run_runner hook "$repo" --implementer-family claude
if command -v jq >/dev/null 2>&1; then
  said="$(printf '{"tool_name":"Bash","tool_input":{"command":"gh pr create --fill"},"cwd":"%s"}' "$repo" | bash "$hook" 2>&1 || true)"
  [ -z "$said" ] || note_fail hook-quiet "reminder fired for a covered passed review: $said"
fi

# 14. What the person or agent running the review sees: stdout stays the
# machine-readable lines; progress, the summary and the next step go to stderr.
has_line() {  # NAME FILE REGEX: FILE has a line matching the extended REGEX
  grep -q -E -- "$3" "$2" 2>/dev/null || note_fail "$1" "no line matching '$3' in: $(cat "$2" 2>/dev/null)"
}
lacks_line() {
  if grep -q -E -- "$3" "$2" 2>/dev/null; then note_fail "$1" "unexpected line matching '$3'"; fi
}
err="$work/stderr-trynext"
has_line progress-start "$err" '^review: 1 file changed against [0-9a-f]{7}, head [0-9a-f]{7}$'
has_line progress-attempt "$err" '^review: codex reviewing \(timeout 2s\)$'
has_line progress-trynext "$err" '^review: codex timed out after [0-9]+s; trying claude$'
has_line progress-answered "$err" '^review: claude answered in [0-9]+s$'
has_line progress-passed "$err" '^review: passed, no findings from claude in [0-9]+s$'
has_line progress-result "$err" "^  result: $work/out-trynext.json\$"
has_line progress-skipped "$work/stderr-samefamily" '^review: skipped codex \(same family as the implementer\)$'
has_line summary-findings "$work/stderr-findings" '^review: findings: 1 \(1 P1\) from codex in [0-9]+s$'
has_line summary-failed "$work/stderr-stderr" '^review: inconclusive: no reviewer answered; the last one exited with an error$'
has_line summary-failed-next "$work/stderr-stderr" '^  next: read the diagnostics file'
has_line summary-failed-diag "$work/stderr-stderr" "^  diagnostics: .*/ccl-code-review/diagnostics/.* \\(private\\)\$"
has_line summary-empty-next "$work/stderr-empty" '^  next: the reviewer printed nothing'
lacks_line summary-empty-diag "$work/stderr-empty" '^  diagnostics: '
has_line summary-timeout "$work/stderr-timeout" '^review: inconclusive: no reviewer answered; the last one timed out$'
has_line summary-timeout-next "$work/stderr-timeout" '^  next: rerun with a larger --timeout'
has_line summary-ambiguous-next "$work/stderr-ambiguous" '^  next: pass the family of the model that wrote it'
has_line summary-changed "$work/stderr-mutate" '^review: inconclusive: the working tree changed during the review$'
has_line summary-interrupt "$work/stderr-interrupt" '^review: inconclusive: interrupted$'
lacks_line summary-interrupt-next "$work/stderr-interrupt" 'trying'
repo="$(new_repo noeligible)"
run_runner noeligible "$repo" --implementer-family kimi --client-order kimi
expect_eq noeligible-reason "$(field "$out" reason_code)" no_eligible_reviewer
has_line summary-noeligible "$work/stderr-noeligible" '^review: skipped kimi \(same family as the implementer: kimi-code/k3\)$'
has_line summary-noeligible-next "$work/stderr-noeligible" '^  next: install a reviewer CLI of another family'

# 14b. stdout: one JSON line, then one line per finding.
stdout_shape="$(python3 -c 'import json,sys
lines = open(sys.argv[1]).read().splitlines()
head = json.loads(lines[0])
print(sorted(head), head["status"], lines[1:])' "$work/stdout-findings" 2>&1 || true)"
expect_eq stdout-shape "$stdout_shape" "['elapsed_seconds', 'reason_code', 'result', 'reviewer', 'status'] findings ['[P1] Reject the empty key — src/app.py:2']"

# 14c. Challenge mode sends the challenge brief and the focus, not the review brief.
repo="$(new_repo challenge)"
FAKE_CODEX=passed run_runner challenge "$repo" --implementer-family claude --mode challenge --focus "the cache key"
expect_eq challenge-mode "$(field "$out" mode)" challenge
grep -q 'Think like an attacker' "$FAKE_LOG.codex.prompt" || note_fail challenge-brief "challenge brief missing"
grep -q '^Look hardest at: the cache key$' "$FAKE_LOG.codex.prompt" || note_fail challenge-focus "focus missing"
if grep -q 'Report every defect you suspect' "$FAKE_LOG.codex.prompt"; then note_fail challenge-review-brief "review brief sent in challenge mode"; fi
has_line challenge-progress "$work/stderr-challenge" '^challenge: passed, no findings from codex'

# 14d. A reader that closes stdout or stderr early does not change the exit code.
closed_run() {  # NAME REDIRECT-MODE: run a passing review with one stream closed
  local name="$1" mode="$2"
  repo="$(new_repo "$name")"
  export FAKE_LOG="$work/log-$name" FAKE_REPO="$repo" FAKE_CODEX=passed
  out="$work/out-$name.json"
  local cmd=(env PATH="$TEST_PATH" CODEX_HOME="$work/user-codex-home" XDG_CACHE_HOME="$work/cache" timeout 60
    python3 "$runner" --cwd "$repo" --base base-ref --intent x --implementer-family claude --out "$out" --timeout 5)
  set +e
  case "$mode" in
    stdout-pipe) "${cmd[@]}" 2>"$work/stderr-$name" | true; rc=${PIPESTATUS[0]} ;;
    stderr-pipe) { "${cmd[@]}" 2>&1 1>&3 | true; rc=${PIPESTATUS[0]}; } 3>"$work/stdout-$name" ;;
    stderr-closed) "${cmd[@]}" >"$work/stdout-$name" 2>&-; rc=$? ;;
    stdout-closed) "${cmd[@]}" >&- 2>"$work/stderr-$name"; rc=$? ;;
  esac
  set -e
  unset FAKE_CODEX
}
closed_run pipeout stdout-pipe
expect_eq pipeout-rc "$rc" 0
expect_eq pipeout-status "$(field "$out" status 2>/dev/null || true)" passed
lacks_line pipeout-traceback "$work/stderr-pipeout" 'BrokenPipeError|Traceback'
closed_run pipeerr stderr-pipe
expect_eq pipeerr-rc "$rc" 0
expect_eq pipeerr-stdout "$(python3 -c 'import json,sys; print(json.loads(open(sys.argv[1]).readline())["status"])' "$work/stdout-pipeerr" 2>&1 || true)" passed
closed_run noerr stderr-closed
expect_eq noerr-rc "$rc" 0
expect_eq noerr-stdout-lines "$(wc -l <"$work/stdout-noerr" | tr -d ' ')" 1
closed_run noout stdout-closed
expect_eq noout-rc "$rc" 0
expect_eq noout-status "$(field "$out" status 2>/dev/null || true)" passed

# 14e. A git failure before the review exits 2 with one line, never a traceback.
mkdir -p "$work/notrepo"
run_runner notrepo "$work/notrepo" --implementer-family claude
expect_eq notrepo-rc "$rc" 2
has_line notrepo-line "$work/stderr-notrepo" '^review: not run: .*not a git repository'
lacks_line notrepo-traceback "$work/stderr-notrepo" 'Traceback'
repo="$(new_repo badbase)"
run_runner badbase "$repo" --implementer-family claude --base no-such-ref
expect_eq badbase-rc "$rc" 2
has_line badbase-next "$work/stderr-badbase" '^  next: check that --cwd is inside a git repository and --base names a commit in it$'

# 14f. A result that cannot be written exits 2 with a next step, never 1.
repo="$(new_repo readonly)"
mkdir -p "$work/ro" && chmod 500 "$work/ro"
run_runner readonly "$repo" --implementer-family claude --out "$work/ro/sub/out.json"
chmod 700 "$work/ro"
expect_eq readonly-rc "$rc" 2
has_line readonly-line "$work/stderr-readonly" '^review: not recorded: '
lacks_line readonly-traceback "$work/stderr-readonly" 'Traceback'

# 14g. Any other unexpected error exits 2 with its traceback, never 1.
repo="$(new_repo crash)"
crash="$(PATH="$TEST_PATH" CODEX_HOME="$work/user-codex-home" XDG_CACHE_HOME="$work/cache" timeout 60 python3 -c '
import importlib.util, sys
spec = importlib.util.spec_from_file_location("review_diff", sys.argv[1])
m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m)
def boom(*a, **k):
    raise RuntimeError("boom")
m.build_prompt = boom
sys.argv = ["review_diff.py"] + sys.argv[2:]
print("rc", m.entry())' "$runner" --cwd "$repo" --base base-ref --intent x --implementer-family claude \
  --out "$work/out-crash.json" 2>"$work/stderr-crash" || true)"
expect_eq crash-rc "$crash" "rc 2"
has_line crash-line "$work/stderr-crash" '^review_diff: internal error, not a verdict$'

# 14h. The clients module next to the runner is the one loaded, whatever the
# caller's directory holds.
mkdir -p "$work/shadow"
printf 'raise SystemExit("shadow module loaded")\n' >"$work/shadow/review_diff_clients.py"
loaded="$(cd "$work/shadow" && python3 -c 'import importlib.util, sys
spec = importlib.util.spec_from_file_location("review_diff", sys.argv[1])
m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m)
print(m.clients.__file__)' "$runner" 2>&1 || true)"
expect_eq shadow-clients "$loaded" "$(dirname "$runner")/review_diff_clients.py"

if [ "$fail" -ne 0 ]; then
  exit 1
fi
printf 'test_review_diff: ok\n'
