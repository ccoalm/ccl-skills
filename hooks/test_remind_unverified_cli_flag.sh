#!/usr/bin/env bash
# Deterministic behavior suite for hooks/remind-unverified-cli-flag.sh.
# Registered in the Makefile `test` target; requires jq (the hook's dependency —
# without jq the hook degrades to silence, so this suite requires it and fails
# loudly instead of false-greening).
#
# The hook deliberately does NOT parse shell, so this suite does not probe shell
# forms. It probes the three things the hook actually asserts — tool-word match,
# long-flag presence, per-session dedup — plus the two contracts it must never
# break (exit 0 / valid JSON / silent stderr) and the marker-safety guards. The
# documented FALSE FIRES are asserted too, so they stay intentional rather than
# drifting into accidents.
set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd -P)"
HOOK="${CLI_FLAG_HOOK:-$SCRIPT_DIR/remind-unverified-cli-flag.sh}"
[ -f "$HOOK" ] || { echo "FAIL: hook not found: $HOOK" >&2; exit 1; }
command -v jq >/dev/null 2>&1 || { echo "FAIL: jq required for this suite" >&2; exit 1; }
# Fail LOUDLY on a hook syntax error rather than as a wall of mysterious probe
# failures — one stray apostrophe inside an embedded program did exactly that.
bash -n "$HOOK" 2>/dev/null || { echo "FAIL: hook is not syntactically valid" >&2; bash -n "$HOOK"; exit 1; }

pass=0; fail=0; probe_n=0

# Isolate the hook's dedup markers into a per-RUN directory. Without this the
# suite self-poisoned across runs: sessions derive from `$$`, the hook persists
# markers, and after PID reuse a stale one silently turned an expected `remind`
# into `quiet`.
MARKER_DIR=$(mktemp -d "${TMPDIR:-/tmp}/cliflag-suite-XXXXXX") || {
  echo "FAIL: cannot create isolated marker dir" >&2; exit 1; }
trap 'rm -rf "$MARKER_DIR"' EXIT INT TERM
export TMPDIR="$MARKER_DIR"

# The hook's core promise is that it never disturbs the Bash call: exit 0, valid
# JSON, silent stderr. All three were discarded by an earlier version of this
# suite, so a nonzero exit or a stray diagnostic passed every assertion.
contract_check() {
  local out="$1" rc="$2" label="$3" errbytes
  if [ -n "${PROBE_ERR:-}" ] && [ -f "$PROBE_ERR" ]; then
    errbytes=$(wc -c < "$PROBE_ERR" | tr -d ' ')
    if [ "$errbytes" != "0" ]; then
      fail=$((fail+1)); printf 'FAIL  [wrote %s bytes to stderr]  %s\n' "$errbytes" "$label" >&2
      printf '        %s\n' "$(head -1 "$PROBE_ERR")" >&2; return
    fi
  fi
  if [ "$rc" -ne 0 ]; then
    fail=$((fail+1)); printf 'FAIL  [exit=%s, must be 0]  %s\n' "$rc" "$label" >&2; return
  fi
  if [ -n "$out" ] && ! printf '%s' "$out" | jq -e . >/dev/null 2>&1; then
    fail=$((fail+1)); printf 'FAIL  [output is not valid JSON]  %s\n' "$label" >&2; return
  fi
  pass=$((pass+1))
}

run_hook() { # run_hook <command> <session>; sets HOOK_OUT / HOOK_RC
  PROBE_ERR=$(mktemp "${MARKER_DIR}/err-XXXXXX")
  HOOK_OUT=$(jq -nc --arg c "$1" --arg s "$2" \
    '{tool_input:{command:$c},session_id:$s,cwd:"/tmp"}' | bash "$HOOK" 2>"$PROBE_ERR"); HOOK_RC=$?
  contract_check "$HOOK_OUT" "$HOOK_RC" "$1"
  rm -f "$PROBE_ERR"; PROBE_ERR=""
}

# probe <remind|quiet> <command> [session]
probe() {
  local expect="$1" cmd="$2" sess="${3:-}" got
  probe_n=$((probe_n+1)); [ -n "$sess" ] || sess="probe-$$-$probe_n"
  run_hook "$cmd" "$sess"
  got="quiet"
  # Assert the STRUCTURE the PreToolUse consumer reads, not just the key name: a
  # top-level `additionalContext` is valid JSON the host ignores.
  printf '%s' "$HOOK_OUT" | jq -e \
    '.hookSpecificOutput.hookEventName == "PreToolUse"
     and (.hookSpecificOutput.additionalContext | type) == "string"
     and (.hookSpecificOutput.additionalContext | length) > 0' >/dev/null 2>&1 && got="remind"
  if [ "$got" = "$expect" ]; then pass=$((pass+1))
  else fail=$((fail+1)); printf 'FAIL  [want=%s got=%s]  %s\n' "$expect" "$got" "$cmd" >&2; fi
}

# attrib <expected tool> <command> — which tool the advisory names.
attrib() {
  local want="$1" cmd="$2" got
  probe_n=$((probe_n+1))
  run_hook "$cmd" "attrib-$$-$probe_n"
  got=$(printf '%s' "$HOOK_OUT" | jq -r '.hookSpecificOutput.additionalContext // ""' 2>/dev/null \
        | grep -o '`[^`]*`' | head -1 | tr -d '`')
  if [ "$got" = "$want" ]; then pass=$((pass+1))
  else fail=$((fail+1)); printf 'FAIL  [want-attrib=%s got=%s]  %s\n' "$want" "${got:-<none>}" "$cmd" >&2; fi
}

# --- FIRES: the recorded failure shapes this hook exists to catch ---
probe remind 'glab mr list --state opened'
probe remind 'glab ci list --branch dev'
probe remind 'glab pipeline view 21852 --output json'
probe remind 'gh pr list --state open'
probe remind 'lark-cli schema tbl --jq .fields'
probe remind 'uv publish --check-url https://example.invalid/simple'
attrib 'glab' 'glab mr list --state opened'
attrib 'uv'   'uv publish --check-url https://example.invalid/simple'
# No shell parsing means every spelling of the same invocation behaves alike —
# this is the property the fifteen-round parser was failing to achieve.
probe remind 'cd /some/path && glab mr list --state merged'
probe remind 'GITLAB_HOST=x glab mr list --state opened'
probe remind 'env GITLAB_HOST=x glab mr list --state opened'
probe remind 'command glab mr list --state opened'
probe remind 'gh --repo=owner/repo pr list --state open'
probe remind 'gh -R owner/repo pr list --state open'
probe remind 'glab mr list \
  --state opened'
probe remind 'git --help && glab mr list --state opened'

# --- QUIET: no long flag means nothing to guess ---
probe quiet 'glab mr view 123'
probe quiet 'gh pr list'
probe quiet 'uv sync'
# --- QUIET: tools outside the list are a documented NON-fire ---
probe quiet 'git log --oneline --graph'
probe quiet 'kubectl get pods --all-namespaces'
probe quiet 'npm install --save-dev typescript'
# --- QUIET: the tool name must appear as a WORD ---
probe quiet 'echo glabber --state opened'
probe quiet './myglab --state opened'
# --- QUIET: whitespace-bearing quoted prose is masked ---
probe quiet 'git commit -m "note that glab mr list --state is unsupported"'
probe quiet 'git log --grep="glab mr list --state"'
# --- QUIET: a help request whose FIRST WORD is the tool ---
probe quiet 'glab mr list --help'
probe quiet 'glab mr list -h'
probe quiet 'glab help mr list --json'
# A bare `help` counts only in the SUBCOMMAND slot: as a positional argument it
# is an endpoint name, not a help request, and suppressing there swallowed the
# advisory for a genuine flag.
probe remind 'gh api help --paginate'
probe quiet 'gh pr merge --help'
# A standalone `--` hands the rest of the line to another program, so a `--help`
# after it is that program's, not this tool's — the flag before it still needs
# the advisory.
probe remind 'uv run --python 3.12 -- python --help'
# ...but suppression must NOT extend to a compound command: the first word is
# still the tool while the unrelated `--help` belongs to something else, and the
# whole-command grep swallowed the advisory for a genuine invocation.
probe remind 'glab mr list --state opened && git --help'
probe remind 'glab mr list --state opened; gh pr list --help'
# A NEWLINE separates commands exactly as `;` does, and grep is line-oriented so
# a character class can never see one — a two-line command read as "simple" and
# the second line's `--help` suppressed the advisory for the first line.
probe remind 'glab mr list --state opened
git --help'

# --- DOCUMENTED FALSE FIRES (asserted so they stay intentional) ---
# A mention inside a heredoc body fires once for that session. Accepted: chasing
# it is what produced the fifteen-round parser.
probe remind 'cat <<EOF
glab mr list --state opened
EOF'
# A help request that is not the command's first word still fires.
probe remind 'cd /x && glab mr list --help'
# A payload inside a whitespace-bearing quoted string is masked away and stays
# QUIET. The mask cannot separate a launcher payload from a commit message
# without parsing, which is exactly what this hook refuses to do; asserted so the
# trade-off stays deliberate rather than drifting into an accident.
probe quiet "sh -c 'glab mr list --state opened'"
probe quiet 'bash -c "glab mr list --state opened"'

# --- DEDUP: once per (session, tool); a different tool still fires ---
d="dedup-$$"
probe remind 'glab mr list --state opened' "$d"
probe quiet  'glab ci list --branch dev'   "$d"
probe remind 'gh pr list --state open'     "$d"
probe remind 'glab mr list --state opened' "${d}-other"
# A tool that always TRAILS another in the same command must still get its own
# advisory: taking only the first tool word meant `gh` stayed silent for the
# whole session once `glab` was deduped.
m="mask-$$"
probe  remind 'glab mr list --state opened'                            "$m"
attrib_in_session() { # attrib_in_session <expected tool> <cmd> <session>
  probe_n=$((probe_n+1)); run_hook "$2" "$3"
  local got
  got=$(printf '%s' "$HOOK_OUT" | jq -r '.hookSpecificOutput.additionalContext // ""' 2>/dev/null \
        | grep -o '`[^`]*`' | head -1 | tr -d '`')
  if [ "$got" = "$1" ]; then pass=$((pass+1))
  else fail=$((fail+1)); printf 'FAIL  [want-attrib=%s got=%s]  %s\n' "$1" "${got:-<none>}" "$2" >&2; fi
}
attrib_in_session 'gh' 'glab mr list --state opened && gh pr list --state open' "$m"
probe quiet 'glab mr list --state opened && gh pr list --state open'   "$m"

# --- UNSAFE TEMP ROOT: the marker TOCTOU cannot be closed from bash, so where
#     the temp root is group/world-writable and NOT sticky the hook must decline
#     to dedup rather than pretend the window is shut. Sticky is what makes a
#     shared /tmp safe; a per-user temp root is not other-writable at all, so
#     neither normal case is affected. ---
unsafe_root=$(mktemp -d "${MARKER_DIR}/unsafe-XXXXXX")
chmod 777 "$unsafe_root"; chmod -t "$unsafe_root" 2>/dev/null || true
u_in=$(mktemp "${MARKER_DIR}/in-XXXXXX")
jq -nc --arg c 'glab mr list --state opened' --arg s 'unsafe-sess' \
   '{tool_input:{command:$c},session_id:$s,cwd:"/tmp"}' > "$u_in"
u1=$(TMPDIR="$unsafe_root" bash "$HOOK" < "$u_in" 2>/dev/null)
u2=$(TMPDIR="$unsafe_root" bash "$HOOK" < "$u_in" 2>/dev/null)
rm -f "$u_in"
if printf '%s' "$u1" | grep -q additionalContext && printf '%s' "$u2" | grep -q additionalContext; then
  pass=$((pass+1))
else
  fail=$((fail+1)); printf 'FAIL  [unsafe temp root: dedup was applied instead of skipped]\n' >&2
fi
if [ ! -e "$unsafe_root/ccl-skills-cliflag" ]; then pass=$((pass+1))
else fail=$((fail+1)); printf 'FAIL  [unsafe temp root: marker directory was created]\n' >&2; fi

# Sticky exempts a writable directory only when we or root own it, so a
# self-owned sticky temp root must STILL dedup (the common shared-/tmp shape).
own_sticky=$(mktemp -d "${MARKER_DIR}/own-XXXXXX"); chmod 1777 "$own_sticky"
o_in=$(mktemp "${MARKER_DIR}/in-XXXXXX")
jq -nc --arg c 'glab mr list --state opened' --arg s 'own-sess' \
   '{tool_input:{command:$c},session_id:$s,cwd:"/tmp"}' > "$o_in"
o1=$(TMPDIR="$own_sticky" bash "$HOOK" < "$o_in" 2>/dev/null)
o2=$(TMPDIR="$own_sticky" bash "$HOOK" < "$o_in" 2>/dev/null)
rm -f "$o_in"
if printf '%s' "$o1" | grep -q additionalContext && ! printf '%s' "$o2" | grep -q additionalContext; then
  pass=$((pass+1))
else
  fail=$((fail+1)); printf 'FAIL  [self-owned sticky temp root: dedup was skipped]\n' >&2
fi

# The walk must use the PHYSICAL path: `dirname` on a logical path resolves
# neither symlinks nor `..`, so a TMPDIR that merely POINTS at a hostile-ancestor
# directory walked a chain that does not exist on disk.
sym_parent=$(mktemp -d "${MARKER_DIR}/sym-XXXXXX")
chmod 777 "$sym_parent"; chmod -t "$sym_parent" 2>/dev/null || true
sym_real="$sym_parent/inner"; mkdir -p "$sym_real"; chmod 700 "$sym_real"
sym_link="${MARKER_DIR}/symlink-root-$$"; ln -s "$sym_real" "$sym_link"
s_in=$(mktemp "${MARKER_DIR}/in-XXXXXX")
jq -nc --arg c 'glab mr list --state opened' --arg s 'sym-sess' \
   '{tool_input:{command:$c},session_id:$s,cwd:"/tmp"}' > "$s_in"
s1=$(TMPDIR="$sym_link" bash "$HOOK" < "$s_in" 2>/dev/null)
s2=$(TMPDIR="$sym_link" bash "$HOOK" < "$s_in" 2>/dev/null)
rm -f "$s_in"
if printf '%s' "$s1" | grep -q additionalContext && printf '%s' "$s2" | grep -q additionalContext; then
  pass=$((pass+1))
else
  fail=$((fail+1)); printf 'FAIL  [symlinked temp root to hostile ancestor: dedup was applied]\n' >&2
fi

# A mode-0700 temp root under a world-writable NON-STICKY parent is swappable
# wholesale, so checking only the temp root itself proves nothing about the path.
anc_parent=$(mktemp -d "${MARKER_DIR}/anc-XXXXXX")
chmod 777 "$anc_parent"; chmod -t "$anc_parent" 2>/dev/null || true
anc_root="$anc_parent/inner"; mkdir -p "$anc_root"; chmod 700 "$anc_root"
a_in=$(mktemp "${MARKER_DIR}/in-XXXXXX")
jq -nc --arg c 'glab mr list --state opened' --arg s 'anc-sess' \
   '{tool_input:{command:$c},session_id:$s,cwd:"/tmp"}' > "$a_in"
a1=$(TMPDIR="$anc_root" bash "$HOOK" < "$a_in" 2>/dev/null)
a2=$(TMPDIR="$anc_root" bash "$HOOK" < "$a_in" 2>/dev/null)
rm -f "$a_in"
if printf '%s' "$a1" | grep -q additionalContext && printf '%s' "$a2" | grep -q additionalContext \
   && [ ! -e "$anc_root/ccl-skills-cliflag" ]; then
  pass=$((pass+1))
else
  fail=$((fail+1)); printf 'FAIL  [unsafe ANCESTOR of temp root: dedup was applied]\n' >&2
fi

# --- BOUNDED INPUT: past the 1 MiB read cap the payload is ignored entirely.
#     Deterministic, not a timing bound: a timing probe could not fail at a
#     CI-safe size, so it was removed rather than shipped. ---
big_in=$(mktemp "${MARKER_DIR}/big-XXXXXX")
awk 'BEGIN{printf "{\"tool_input\":{\"command\":\"glab mr list --state opened "; for(i=0;i<2200000;i++)printf "x"; printf "\"},\"session_id\":\"bigpay\",\"cwd\":\"/tmp\"}"}' > "$big_in"
big_out=$(bash "$HOOK" < "$big_in" 2>/dev/null); big_rc=$?
if [ "$big_rc" -ne 0 ]; then
  fail=$((fail+1)); printf 'FAIL  [oversized payload: rc=%s]\n' "$big_rc" >&2
elif printf '%s' "$big_out" | grep -q additionalContext; then
  fail=$((fail+1)); printf 'FAIL  [oversized payload parsed past the 1MiB read cap]\n' >&2
else pass=$((pass+1)); fi
rm -f "$big_in"

# --- MARKER SAFETY. Every attack here was reproduced first-hand before its fix.
#     Each plant targets BOTH the current directory layout AND the pre-hardening
#     flat path: planting only at the current path made this whole group vacuous
#     (a mutation reverting the layout passed all of it). ---
FLAT='ccl-skills-cliflag-hostile-sess'
DIRP='ccl-skills-cliflag'

run_bounded() { # run_bounded <seconds> <input-file> <cmd...>
  # `timeout` is NOT installed on stock macOS; calling it there returns 127 and
  # would fail every probe here on a Darwin runner with a correct hook.
  local limit="$1" infile="$2"; shift 2
  local outfile pid waited=0
  outfile=$(mktemp "${MARKER_DIR}/bounded-XXXXXX")
  "$@" <"$infile" >"$outfile" 2>/dev/null & pid=$!
  while kill -0 "$pid" 2>/dev/null && [ "$waited" -lt "$limit" ]; do sleep 1; waited=$((waited+1)); done
  if kill -0 "$pid" 2>/dev/null; then kill -9 "$pid" 2>/dev/null; wait "$pid" 2>/dev/null; BOUNDED_RC=124
  else wait "$pid"; BOUNDED_RC=$?; fi
  BOUNDED_OUT=$(cat "$outfile"); rm -f "$outfile"
}

hostile() { # hostile <label> <plant-fn>; publishes HOSTILE_SANDBOX
  local label="$1" plant="$2" sandbox infile start elapsed
  sandbox=$(mktemp -d "${MARKER_DIR}/hostile-XXXXXX") || { fail=$((fail+1)); return; }
  "$plant" "$sandbox"
  infile=$(mktemp "${MARKER_DIR}/in-XXXXXX")
  jq -nc --arg c 'glab mr list --state opened' --arg s 'hostile-sess' \
     '{tool_input:{command:$c},session_id:$s,cwd:"/tmp"}' > "$infile"
  start=$(date +%s)
  TMPDIR="$sandbox" run_bounded 8 "$infile" bash "$HOOK"
  elapsed=$(( $(date +%s) - start )); rm -f "$infile"
  if [ "$BOUNDED_RC" -ne 0 ] || [ "$elapsed" -ge 5 ]; then
    fail=$((fail+1)); printf 'FAIL  [hostile %s: rc=%s elapsed=%ss]\n' "$label" "$BOUNDED_RC" "$elapsed" >&2
  elif ! printf '%s' "$BOUNDED_OUT" | grep -q 'additionalContext'; then
    fail=$((fail+1)); printf 'FAIL  [hostile %s: advisory suppressed]\n' "$label" >&2
  else pass=$((pass+1)); fi
  HOSTILE_SANDBOX="$sandbox"
}

victim_intact() { # victim_intact <label>
  if [ -f "$HOSTILE_SANDBOX/victim.txt" ] \
     && [ "$(cat "$HOSTILE_SANDBOX/victim.txt")" = 'original content' ]; then
    pass=$((pass+1))
  else
    fail=$((fail+1)); printf 'FAIL  [hostile %s: victim file was written through]\n' "$1" >&2
  fi
}

plant_symlink()    { echo 'original content' > "$1/victim.txt"
                     ln -s "$1/victim.txt" "$1/$DIRP"; ln -s "$1/victim.txt" "$1/$FLAT"; }
plant_fifo()       { mkfifo "$1/$DIRP" 2>/dev/null || true; mkfifo "$1/$FLAT" 2>/dev/null || true; }
# NOT an ownership probe: it creates the directory as the SAME uid, so `-O`
# stays true and that rejection is never reached. What it covers is a
# PRE-EXISTING marker directory being reused without incident, plus the flat
# hostile object. Cross-uid `-O` has no executable probe here.
plant_preexisting(){ mkdir -p "$1/$DIRP"; chmod 700 "$1/$DIRP"; mkfifo "$1/$FLAT" 2>/dev/null || true; }
plant_inner_fifo() { mkdir -p -m 700 "$1/$DIRP"; mkfifo "$1/$DIRP/hostile-sess" 2>/dev/null || true
                     mkfifo "$1/$FLAT" 2>/dev/null || true; }
plant_inner_link() { mkdir -p -m 700 "$1/$DIRP"; echo 'original content' > "$1/victim.txt"
                     ln -s "$1/victim.txt" "$1/$DIRP/hostile-sess"; ln -s "$1/victim.txt" "$1/$FLAT"; }
# A HARD LINK passes -f, -O and the symlink test alike; reachable when the marker
# directory pre-existed group/world-writable.
plant_inner_hard() { mkdir -p "$1/$DIRP"; chmod 777 "$1/$DIRP"
                     echo 'original content' > "$1/victim.txt"
                     ln "$1/victim.txt" "$1/$DIRP/hostile-sess"
                     ln "$1/victim.txt" "$1/$FLAT" 2>/dev/null || true; }

hostile 'symlink at marker dir' plant_symlink;        victim_intact 'symlink at marker dir'
hostile 'FIFO at marker dir' plant_fifo
hostile 'pre-existing marker dir' plant_preexisting
hostile 'FIFO as marker file' plant_inner_fifo
hostile 'symlink as marker file' plant_inner_link;    victim_intact 'symlink as marker file'
hostile 'hard link as marker file' plant_inner_hard;  victim_intact 'hard link as marker file'

# A pre-existing world-writable marker directory must be TIGHTENED, not merely
# accepted: `mkdir -p -m 700` does not touch an existing directory's mode.
mode_sb=$(mktemp -d "${MARKER_DIR}/mode-XXXXXX")
mkdir -p "$mode_sb/$DIRP"; chmod 777 "$mode_sb/$DIRP"
mode_in=$(mktemp "${MARKER_DIR}/in-XXXXXX")
jq -nc --arg c 'glab mr list --state opened' --arg s 'mode-sess' \
   '{tool_input:{command:$c},session_id:$s,cwd:"/tmp"}' > "$mode_in"
TMPDIR="$mode_sb" run_bounded 8 "$mode_in" bash "$HOOK"; rm -f "$mode_in"
if [ "$BOUNDED_RC" -eq 0 ] && [ "$(ls -ld "$mode_sb/$DIRP" | cut -c1-10)" = 'drwx------' ]; then
  pass=$((pass+1))
else
  fail=$((fail+1)); printf 'FAIL  [world-writable marker dir not tightened]\n' >&2
fi

# An OVERSIZED marker must be neither read nor written, in BOTH shapes. The size
# cap was once removed on the argument that the line-count bound already covered
# this — an argument checked only against the many-line shape, where it holds. A
# single enormous LINE has a line count of 1, sails past that bound, and gets
# appended to. Probing one dimension and concluding over both is the mistake;
# both shapes are asserted here so the removal cannot recur on the same reasoning.
big_sb=$(mktemp -d "${MARKER_DIR}/bigm-XXXXXX")
mkdir -p -m 700 "$big_sb/ccl-skills-cliflag"
awk 'BEGIN{for(i=0;i<5000;i++)print "junk"}' > "$big_sb/ccl-skills-cliflag/big-sess"
# ...and the single-enormous-line shape, which the line-count bound does not see.
awk 'BEGIN{for(i=0;i<300000;i++)printf "x"; print ""}' > "$big_sb/ccl-skills-cliflag/one-sess"
b_in=$(mktemp "${MARKER_DIR}/in-XXXXXX")
jq -nc --arg c 'glab mr list --state opened' --arg s 'big-sess' \
   '{tool_input:{command:$c},session_id:$s,cwd:"/tmp"}' > "$b_in"
b1=$(TMPDIR="$big_sb" bash "$HOOK" < "$b_in" 2>/dev/null)
b2=$(TMPDIR="$big_sb" bash "$HOOK" < "$b_in" 2>/dev/null)
rm -f "$b_in"
if printf '%s' "$b1" | grep -q additionalContext && printf '%s' "$b2" | grep -q additionalContext \
   && [ "$(wc -l < "$big_sb/ccl-skills-cliflag/big-sess" | tr -d ' ')" = "5000" ]; then
  pass=$((pass+1))
else
  fail=$((fail+1)); printf 'FAIL  [oversized many-line marker: appended to or dedup applied]\n' >&2
fi
o_in=$(mktemp "${MARKER_DIR}/in-XXXXXX")
jq -nc --arg c 'glab mr list --state opened' --arg s 'one-sess' \
   '{tool_input:{command:$c},session_id:$s,cwd:"/tmp"}' > "$o_in"
o1=$(TMPDIR="$big_sb" bash "$HOOK" < "$o_in" 2>/dev/null)
rm -f "$o_in"
if printf '%s' "$o1" | grep -q additionalContext \
   && [ "$(wc -l < "$big_sb/ccl-skills-cliflag/one-sess" | tr -d ' ')" = "1" ]; then
  pass=$((pass+1))
else
  fail=$((fail+1)); printf 'FAIL  [oversized single-line marker: was appended to]\n' >&2
fi

# An EMPTY marker: `grep -c ''` prints 0 but exits 1, which produced "0\n0" and a
# stderr diagnostic from the numeric test.
empty_sb=$(mktemp -d "${MARKER_DIR}/empty-XXXXXX")
mkdir -p -m 700 "$empty_sb/$DIRP"; : > "$empty_sb/$DIRP/probe-empty"
PROBE_ERR=$(mktemp "${MARKER_DIR}/err-XXXXXX")
e_out=$(TMPDIR="$empty_sb" jq -nc --arg c 'glab mr list --state opened' --arg s 'probe-empty' \
      '{tool_input:{command:$c},session_id:$s,cwd:"/tmp"}' \
      | TMPDIR="$empty_sb" bash "$HOOK" 2>"$PROBE_ERR"); e_rc=$?
contract_check "$e_out" "$e_rc" 'empty marker file'
rm -f "$PROBE_ERR"; PROBE_ERR=""

# A marker that is owned and single-link but NOT WRITABLE: the append is
# attempted and must fail SILENTLY. This is the probe that covers the subshell —
# an explicit `-w` check used to short-circuit here, which is why removing the
# subshell used to change nothing observable.
# Skipped as root: `chmod 400` does not stop uid 0 from appending, so under a
# container CI running as root this probe would pass without exercising anything.
# Recording the skip beats a vacuous pass.
if [ "$(id -u)" = "0" ]; then
  printf 'SKIP  [read-only marker probe: running as root, chmod 400 is not a barrier]\n' >&2
else
ro_sb=$(mktemp -d "${MARKER_DIR}/ro-XXXXXX")
mkdir -p -m 700 "$ro_sb/$DIRP"; : > "$ro_sb/$DIRP/ro-sess"; chmod 400 "$ro_sb/$DIRP/ro-sess"
PROBE_ERR=$(mktemp "${MARKER_DIR}/err-XXXXXX")
r_out=$(TMPDIR="$ro_sb" jq -nc --arg c 'glab mr list --state opened' --arg s 'ro-sess' \
      '{tool_input:{command:$c},session_id:$s,cwd:"/tmp"}' \
      | TMPDIR="$ro_sb" bash "$HOOK" 2>"$PROBE_ERR"); r_rc=$?
contract_check "$r_out" "$r_rc" 'read-only marker file'
rm -f "$PROBE_ERR"; PROBE_ERR=""
fi

# An over-long session id became an over-long filename and the failed open
# printed `File name too long` to real stderr.
long_sess=$(awk 'BEGIN{for(i=0;i<400;i++)printf "s"}')
probe remind 'glab mr list --state opened' "$long_sess"
# ...and the capped name must still DEDUP; without the cap the marker can never
# be written and the advisory repeats forever.
probe quiet  'glab ci list --branch dev'   "$long_sess"

# A TMPDIR that looks like an OPTION (`-P`, `-L`) must not send `cd` to HOME and
# plant the marker directory there.
# NEVER delete anything this suite did not create. An earlier version removed
# `$HOME/ccl-skills-cliflag` on failure — and this suite runs in `make test`, so
# a developer whose real marker directory happened to sit there would have had it
# destroyed by a test run. If the path already exists, the probe cannot attribute
# what it finds and SKIPS rather than guess.
if [ -e "$HOME/ccl-skills-cliflag" ]; then
  printf 'SKIP  [option-shaped TMPDIR probe: %s pre-exists, refusing to touch it]\n' \
    "$HOME/ccl-skills-cliflag" >&2
else
  opt_in=$(mktemp "${MARKER_DIR}/in-XXXXXX")
  jq -nc --arg c 'glab mr list --state opened' --arg s 'opt-sess' \
     '{tool_input:{command:$c},session_id:$s,cwd:"/tmp"}' > "$opt_in"
  TMPDIR=-P bash "$HOOK" < "$opt_in" >/dev/null 2>&1
  TMPDIR=-L bash "$HOOK" < "$opt_in" >/dev/null 2>&1
  rm -f "$opt_in"
  if [ ! -e "$HOME/ccl-skills-cliflag" ]; then
    pass=$((pass+1))
  else
    fail=$((fail+1))
    # DO NOT REMOVE IT. "It was absent a moment ago, so this probe must have made
    # it" is an inference, not attribution — a concurrent process can create the
    # path inside that window, and this suite runs in `make test` on machines
    # that are doing other things. A test does not delete anything it did not
    # certainly create; reporting the path and leaving it is the correct end.
    printf 'FAIL  [option-shaped TMPDIR: %s now exists; NOT removed, inspect it yourself]\n' \
      "$HOME/ccl-skills-cliflag" >&2
  fi
fi

# --- PRESENCE, NOT BEHAVIOR. Two guards cannot be reached by any portable probe
#     here (both need a second user id), and this suite says so. That honesty has
#     a cost the review named: a later change could delete either one and stay
#     green. These checks close only that half — they assert the guard is still
#     WRITTEN, never that it works. A green here is not evidence of behavior, and
#     must not be cited as if it were. If a guard is deliberately removed, delete
#     its check in the same change and say why in the header. ---
for guard in '-O "$marker_dir"' '"$dir_owner" != "root"'; do
  # `--` because the first guard string starts with `-O`, which grep would
  # otherwise take as an option — the check then always failed, on a clean hook.
  if grep -Fq -- "$guard" "$HOOK"; then
    pass=$((pass+1))
  else
    fail=$((fail+1))
    printf 'FAIL  [unprobed guard vanished from the hook: %s]\n' "$guard" >&2
  fi
done

printf '\n%s: pass=%d fail=%d\n' "$(basename "$0")" "$pass" "$fail"
[ "$fail" -eq 0 ] || exit 1
