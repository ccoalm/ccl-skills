#!/usr/bin/env bash
# Regression tests for review_diff.py, the lean runner where the reviewer reads
# the diff itself read-only. Fake codex/claude executables stand in for the
# real CLIs; FAKE_* variables choose their behavior and they log what they saw.
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
  holdpipe) setsid sleep 30 & sleep 30 ;;
  orphan) sleep 60 >/dev/null 2>&1 & echo $! >"$FAKE_LOG.orphan"; exit 130 ;;
  hedged) printf 'The repository reads failed, so this review is incomplete.\nNo findings.\n' >"$out" ;;
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
esac
EOF
  chmod +x "$bin/codex" "$bin/claude"
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
  PATH="$work/bin:$PATH" CODEX_HOME="$work/user-codex-home" XDG_CACHE_HOME="$work/cache" timeout 60 python3 "$runner" \
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

# 4. Unparseable output is inconclusive and does not fall back.
repo="$(new_repo garbage)"
FAKE_CODEX=garbage run_runner garbage "$repo" --implementer-family kimi
expect_eq garbage-rc "$rc" 2
expect_eq garbage-status "$(field "$out" status)" inconclusive
[ ! -e "$FAKE_LOG.claude" ] || note_fail garbage-fallback "fell back on unparseable output"

# 5. Timeout falls back once to the next eligible family.
repo="$(new_repo timeout)"
FAKE_CODEX=slow run_runner timeout "$repo" --implementer-family kimi --timeout 2
expect_eq timeout-rc "$rc" 0
expect_eq timeout-client "$(field "$out" selected_client)" claude
expect_eq timeout-attempt0 "$(field "$out" attempts.0.status)" timeout

# 6. Empty output falls back as well.
repo="$(new_repo empty)"
FAKE_CODEX=empty run_runner empty "$repo" --implementer-family kimi
expect_eq empty-client "$(field "$out" selected_client)" claude

# 7. Interrupt is terminal: no fallback.
repo="$(new_repo interrupt)"
FAKE_CODEX=interrupt run_runner interrupt "$repo" --implementer-family kimi
expect_eq interrupt-rc "$rc" 2
expect_eq interrupt-status "$(field "$out" status)" inconclusive
[ ! -e "$FAKE_LOG.claude" ] || note_fail interrupt-fallback "fell back after an interrupt"

# 8. Same-family reviewer is skipped; Claude runs with a read-only tool surface.
repo="$(new_repo samefamily)"
FAKE_CLAUDE=findings run_runner samefamily "$repo" --implementer-family codex
expect_eq samefamily-client "$(field "$out" selected_client)" claude
[ ! -e "$FAKE_LOG.codex" ] || note_fail samefamily-skip "same-family codex was run"
args="$(cat "$FAKE_LOG.claude" 2>/dev/null)"
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

# 8c. A failed exit never yields a verdict, even with a clean answer; it falls back.
repo="$(new_repo failclean)"
FAKE_CODEX=failclean FAKE_CLAUDE=findings run_runner failclean "$repo" --implementer-family kimi
expect_eq failclean-client "$(field "$out" selected_client)" claude
expect_eq failclean-attempt0 "$(field "$out" attempts.0.status)" failed

# 8d. A clean sentinel inside other text is not a pass.
repo="$(new_repo hedged)"
FAKE_CODEX=hedged run_runner hedged "$repo" --implementer-family claude
expect_eq hedged-status "$(field "$out" status)" inconclusive

# 8e. A finding from a failed attempt survives a later clean answer.
repo="$(new_repo failfinding)"
FAKE_CODEX=failfinding FAKE_CLAUDE=passed run_runner failfinding "$repo" --implementer-family kimi
expect_eq failfinding-status "$(field "$out" status)" findings
expect_eq failfinding-title "$(field "$out" findings.0.title)" "Keep the guard"

# 8f. A finding header without its scenario is not a verdict.
repo="$(new_repo headeronly)"
FAKE_CODEX=headeronly run_runner headeronly "$repo" --implementer-family claude
expect_eq headeronly-status "$(field "$out" status)" inconclusive

# 8g. An implementer whose model family is unknown is refused before any review.
repo="$(new_repo ambiguous)"
run_runner ambiguous "$repo" --implementer-family opencode
expect_eq ambiguous-rc "$rc" 2
expect_eq ambiguous-reason "$(field "$out" reason_code)" implementer_family_ambiguous
[ ! -e "$FAKE_LOG.codex" ] && [ ! -e "$FAKE_LOG.claude" ] || note_fail ambiguous-run "a reviewer ran for an ambiguous family"

# 8h. A descendant holding the reviewer's pipes cannot stall the runner.
repo="$(new_repo holdpipe)"
t0=$(date +%s)
FAKE_CODEX=holdpipe run_runner holdpipe "$repo" --implementer-family kimi --timeout 2
[ $(( $(date +%s) - t0 )) -lt 20 ] || note_fail holdpipe-bound "runner waited on a descendant's pipe"
expect_eq holdpipe-fallback "$(field "$out" selected_client)" claude

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

# 10. Untracked files are named; a dirty tree is reported as such.
repo="$(new_repo untracked)"
printf 'x = 1\n' >"$repo/src/new_module.py"
FAKE_CODEX=passed run_runner untracked "$repo" --implementer-family claude
grep -q 'src/new_module.py' "$FAKE_LOG.codex.prompt" || note_fail untracked-prompt "untracked file not named in the prompt"
expect_eq untracked-clean "$(field "$out" worktree_clean)" false
[ -n "$(field "$out" candidate_tree)" ] || note_fail untracked-tree "candidate tree missing"

# 10b. Hidden-untracked config and a subdirectory --cwd still see every new file.
repo="$(new_repo hidden)"
git -C "$repo" config status.showUntrackedFiles no
mkdir -p "$repo/lib"
printf 'y = 2\n' >"$repo/lib/sibling.py"
export FAKE_LOG="$work/log-hidden" FAKE_REPO="$repo" FAKE_CODEX=passed
rm -f "$FAKE_LOG".*
set +e
PATH="$work/bin:$PATH" CODEX_HOME="$work/user-codex-home" XDG_CACHE_HOME="$work/cache" timeout 60 python3 "$runner" \
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
PATH="$work/bin:$PATH" CODEX_HOME="$work/user-codex-home" XDG_CACHE_HOME="$work/cache" timeout 60 python3 "$runner" \
  --cwd "$repo" --base base-ref --intent x --implementer-family claude --out "$work/evid/out.json" >/dev/null 2>&1
set -e
unset FAKE_CODEX
expect_eq symlink-untouched "$(cat "$repo/src/app.py")" "$before"

# 12c. A custom model provider keeps its definition in the private home.
repo="$(new_repo provider)"
cp "$work/user-codex-home/config.toml" "$work/config.saved"
printf 'model = "m-test"\nmodel_provider = "custom" # hosted endpoint\n\n[model_providers.custom]\nbase_url = "https://example.invalid/v1"\n\n[model_providers.other]\nbase_url = "https://other.invalid"\n\n[mcp_servers.danger]\ncommand = "rm"\n' >"$work/user-codex-home/config.toml"
FAKE_CODEX=passed run_runner provider "$repo" --implementer-family claude
grep -q 'example.invalid' "$FAKE_LOG.codex.config" || note_fail provider-kept "selected provider definition dropped"
grep -q '^\[model_providers.custom\]$' "$FAKE_LOG.codex.config" || note_fail provider-header "provider table header dropped"
if grep -q -E 'other.invalid|mcp_servers' "$FAKE_LOG.codex.config"; then note_fail provider-only "unselected tables carried"; fi
cp "$work/config.saved" "$work/user-codex-home/config.toml"

# 13. The PR reminder hook stays quiet for a passed review of a clean HEAD.
repo="$(new_repo hook)"
FAKE_CODEX=passed run_runner hook "$repo" --implementer-family claude
if command -v jq >/dev/null 2>&1; then
  said="$(printf '{"tool_name":"Bash","tool_input":{"command":"gh pr create --fill"},"cwd":"%s"}' "$repo" | bash "$hook" 2>&1 || true)"
  [ -z "$said" ] || note_fail hook-quiet "reminder fired for a covered passed review: $said"
fi

if [ "$fail" -ne 0 ]; then
  exit 1
fi
printf 'test_review_diff: ok\n'
