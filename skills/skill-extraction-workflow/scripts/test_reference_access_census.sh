#!/usr/bin/env bash
# Regression for reference-access-census.sh: synthetic transcripts only, no
# host logs are read. Proves (1) per-file session counts and the touching
# denominator, (2) the unevaluated sentinel when no transcript exists (never a
# zero table), (3) the privacy contract — output carries no transcript text,
# no absolute log path, no session id, (2b) input errors (an unreadable
# transcript) withhold the table with exit 2 instead of printing zeros or the ok
# token, (4) usage errors exit 2, and (5) the
# ARG_MAX regression: a candidate set larger than one xargs batch still counts
# (the first version silently reported 0 on a large window).
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CENSUS="$HERE/reference-access-census.sh"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
fail() { echo "FAIL: $*" >&2; exit 1; }

# --- fixture repo: one skill package with an entrypoint and three references ---
REPO="$TMP/repo"; mkdir -p "$REPO/skills/demo-skill/references"
git -C "$TMP" init -q repo 2>/dev/null || git init -q "$REPO"
printf '# demo\n' > "$REPO/skills/demo-skill/SKILL.md"
for r in alpha beta gamma; do printf '# %s\n' "$r" > "$REPO/skills/demo-skill/references/$r.md"; done
git -C "$REPO" add -A && git -C "$REPO" -c user.email=t@t -c user.name=t commit -qm fixture

# --- fixture transcripts: two log roots, distinct mention shapes ---
LOGS="$TMP/logs-claude"; mkdir -p "$LOGS/proj-a" "$TMP/logs-codex/2026/09"
SECRET_PROMPT="user-private-prompt-text-7f3a"
SESSION_ID="session-9c1e2d3b-secret"
# session 1 (claude shape): reads alpha and beta via a Read tool call
printf '{"type":"tool_use","name":"Read","input":{"file_path":"/abs/checkout/skills/demo-skill/references/alpha.md"},"prompt":"%s","session":"%s"}\n' "$SECRET_PROMPT" "$SESSION_ID" > "$LOGS/proj-a/one.jsonl"
printf '{"type":"tool_use","name":"Read","input":{"file_path":"/abs/checkout/skills/demo-skill/references/beta.md"}}\n' >> "$LOGS/proj-a/one.jsonl"
# session 2 (codex shape): shell command mentioning alpha twice (must count once)
printf '{"cmd":"sed -n 1,40p skills/demo-skill/references/alpha.md && cat skills/demo-skill/references/alpha.md"}\n' > "$TMP/logs-codex/2026/09/rollout-two.jsonl"
# session 3: touches the package (SKILL.md) but no reference
printf '{"cmd":"cat skills/demo-skill/SKILL.md"}\n' > "$TMP/logs-codex/2026/09/rollout-three.jsonl"
# session 4: unrelated transcript (must not count as touching)
printf '{"cmd":"ls skills/other-skill/"}\n' > "$LOGS/proj-a/four.jsonl"

# deterministic, differing mtimes so the last_touched column can be asserted exactly (newest wins)
touch -t "$(date -v-3d +%Y%m%d%H%M 2>/dev/null || date -d '3 days ago' +%Y%m%d%H%M)" "$LOGS/proj-a/one.jsonl"
touch -t "$(date -v-1d +%Y%m%d%H%M 2>/dev/null || date -d '1 day ago' +%Y%m%d%H%M)" "$TMP/logs-codex/2026/09/rollout-two.jsonl"
NEWEST="$(date -v-1d +%Y-%m-%d 2>/dev/null || date -d '1 day ago' +%Y-%m-%d)"
OLDER="$(date -v-3d +%Y-%m-%d 2>/dev/null || date -d '3 days ago' +%Y-%m-%d)"
# a stale transcript (older than the window) that mentions tracked files must not move any count, share, or date
printf '{"cmd":"cat skills/demo-skill/references/alpha.md skills/demo-skill/references/gamma.md"}\n' > "$LOGS/proj-a/stale.jsonl"
touch -t "$(date -v-45d +%Y%m%d%H%M 2>/dev/null || date -d '45 days ago' +%Y%m%d%H%M)" "$LOGS/proj-a/stale.jsonl"
run() { bash "$CENSUS" --repo-root "$REPO" --skill demo-skill --days 30 --logs "$LOGS,$TMP/logs-codex"; }
out="$(run)" || fail "census exited non-zero on a valid fixture"
# Checks read the output from a here-string, not a pipe: grep -q exits on the first
# match, and under pipefail a writer still holding the pipe dies of SIGPIPE.

# (1) counts and denominator
grep -qF 'transcripts=4 sessions_touching_package=3' <<<"$out" || fail "denominator wrong:\n$out"
grep -qF "references/alpha.md | 2 | $NEWEST | 66%" <<<"$out" || fail "alpha should count 2 sessions with the newest touching date $NEWEST:\n$out"
grep -qF "references/beta.md | 1 | $OLDER | 33%" <<<"$out" || fail "beta should count 1 session dated $OLDER:\n$out"
grep -qE '^references/gamma\.md \| 0 \| - \| 0%' <<<"$out" || fail "gamma should count 0 with no date:\n$out"
grep -qE '^SKILL\.md \| 1 \|' <<<"$out" || fail "SKILL.md should count 1 session:\n$out"
[ "$(printf '%s\n' "$out" | tail -1)" = "reference_access_census_ok" ] || fail "last token must be the ok marker"

# (3) privacy contract
grep -qF "$SECRET_PROMPT" <<<"$out" && fail "transcript text leaked into census output"
grep -qF "$SESSION_ID" <<<"$out" && fail "session id leaked into census output"
grep -qF "$LOGS" <<<"$out" && fail "absolute log path leaked into census output"
grep -qF "/abs/checkout" <<<"$out" && fail "absolute checkout path leaked into census output"

# (2) unevaluated sentinel: no transcripts at all
EMPTY="$TMP/empty-logs"; mkdir -p "$EMPTY"
eout="$(bash "$CENSUS" --repo-root "$REPO" --skill demo-skill --days 30 --logs "$EMPTY")" || fail "empty-log run must exit 0"
[ "$(printf '%s\n' "$eout" | tail -1)" = "reference_access_census_unevaluated: no transcripts within 30d under 1 log root(s); counts withheld" ] || fail "missing unevaluated sentinel:\n$eout"
grep -qE '\| 0 \|' <<<"$eout" && fail "an unevaluated run must not print a zero table"
grep -qF "$EMPTY" <<<"$eout" && fail "unevaluated sentinel leaked the log root path"
grep -qF "$TMP" <<<"$eout" && fail "unevaluated sentinel leaked an absolute path"

# (2b) input errors withhold the table: an unreadable transcript is exit 2 + unevaluated, never zeros or ok
UNREAD="$TMP/logs-unreadable"; mkdir -p "$UNREAD"
printf '{"cmd":"cat skills/demo-skill/references/alpha.md"}\n' > "$UNREAD/readable.jsonl"
printf '{"cmd":"cat skills/demo-skill/references/beta.md"}\n' > "$UNREAD/locked.jsonl"
chmod 000 "$UNREAD/locked.jsonl"
if [ -r "$UNREAD/locked.jsonl" ]; then
  echo "note: chmod 000 is readable here (root); skipping the unreadable-input leg"
else
  uout="$(bash "$CENSUS" --repo-root "$REPO" --skill demo-skill --days 30 --logs "$UNREAD" 2>"$TMP/unread.stderr")" && fail "unreadable transcript must exit non-zero"
  urc=$?
  uout="$(bash "$CENSUS" --repo-root "$REPO" --skill demo-skill --days 30 --logs "$UNREAD" 2>/dev/null || true)"
  bash "$CENSUS" --repo-root "$REPO" --skill demo-skill --days 30 --logs "$UNREAD" >/dev/null 2>&1 || [ $? -eq 2 ] || fail "unreadable transcript must exit 2"
  grep -qE 'reference_access_census_unevaluated: [0-9]+ input error\(s\)' <<<"$uout" || fail "unreadable transcript must withhold counts as unevaluated:\n$uout"
  grep -qF 'reference_access_census_ok' <<<"$uout" && fail "ok token printed after an input error"
  grep -qE '\| [0-9]+ \|' <<<"$uout" && fail "a table was printed after an input error"
  grep -qF "$UNREAD" <<<"$uout" && fail "input-error sentinel leaked the log path"
fi
chmod 644 "$UNREAD/locked.jsonl"

# (4) usage errors exit 2
if bash "$CENSUS" --repo-root "$REPO" --skill no-such-skill --logs "$LOGS" >/dev/null 2>&1; then fail "unknown skill must exit 2"; fi
bash "$CENSUS" --repo-root "$REPO" --skill no-such-skill --logs "$LOGS" >/dev/null 2>&1 || [ $? -eq 2 ] || fail "unknown skill must exit 2 exactly"
bash "$CENSUS" --repo-root "$REPO" --skill demo-skill --days abc --logs "$LOGS" >/dev/null 2>&1 || [ $? -eq 2 ] || fail "non-integer --days must exit 2"

# (5) ARG_MAX regression: the candidate path list must exceed THIS host's exec limit
# (getconf ARG_MAX) so that a `$(cat candidates)` expansion — the first version's shape,
# which silently reported 0 on a real 60-day window — cannot fit in one exec. The fixture
# size is derived from the limit, never a fixed byte figure; a host whose limit exceeds the
# fixture bound runs only the counting leg and says so. Verified RED by applying that exact
# mutation to a disposable copy of the script.
DPAD=""; i=0; while [ $i -lt 150 ]; do DPAD="${DPAD}d"; i=$((i+1)); done
BIG="$TMP/logs-big/$DPAD"; mkdir -p "$BIG"
PAD=""; i=0; while [ $i -lt 40 ]; do PAD="${PAD}x"; i=$((i+1)); done
arg_max="$(getconf ARG_MAX 2>/dev/null || echo 2097152)"
per_path=$(( ${#BIG} + 60 ))
need=$(( (arg_max + 262144) / per_path + 1 ))
[ "$need" -lt 11000 ] && need=11000
probe=1
if [ "$need" -gt 60000 ]; then
  echo "note: ARG_MAX=$arg_max would need $need fixture files; the E2BIG probe is skipped on this host and only the counting leg runs"
  need=11000; probe=0
fi
( cd "$BIG" && i=1; while [ $i -le $need ]; do : > "s$i-$PAD.jsonl"; i=$((i+1)); done )
find "$BIG" -type f -name '*.jsonl' > "$TMP/big-list"
inv_bytes=$(wc -c < "$TMP/big-list" | tr -d ' ')
if [ "$probe" -eq 1 ]; then
  erc=0; bash -c 'grep -lF "skills/demo-skill/" $(cat "$1") >/dev/null 2>&1' _ "$TMP/big-list" 2>"$TMP/e2big.err" || erc=$?
  [ "$erc" -eq 126 ] || grep -qi "argument list too long" "$TMP/e2big.err" || fail "ARG_MAX fixture ($inv_bytes bytes, ARG_MAX=$arg_max) does not exceed this host's exec limit (rc=$erc), so the leg cannot kill the single-exec mutation"
fi
for i in 7 5208 10999; do printf '{"cmd":"cat skills/demo-skill/references/gamma.md"}\n' > "$BIG/s$i-$PAD.jsonl"; done
bout="$(bash "$CENSUS" --repo-root "$REPO" --skill demo-skill --days 30 --logs "$BIG")" || fail "big run exited non-zero"
grep -qF "transcripts=$need sessions_touching_package=3" <<<"$bout" || fail "large candidate set miscounted (ARG_MAX regression):\n$bout"
grep -qE '^references/gamma\.md \| 3 \|' <<<"$bout" || fail "gamma should count 3 across xargs batches:\n$bout"

# (6) a flag without its value is a usage error (exit 2), not an unbound-variable abort
bash "$CENSUS" --repo-root "$REPO" --skill >/dev/null 2>&1 || [ $? -eq 2 ] || fail "flag without value must exit 2"

# (7) an unknown argument never echoes its value (an absolute path passed by mistake stays private)
uerr="$(bash "$CENSUS" --repo-root "$REPO" --skill demo-skill --logs "$LOGS" "/private/mistyped/path" 2>&1 >/dev/null || true)"
bash "$CENSUS" --repo-root "$REPO" --skill demo-skill --logs "$LOGS" "/private/mistyped/path" >/dev/null 2>&1 || [ $? -eq 2 ] || fail "unknown argument must exit 2"
grep -qF "/private/mistyped/path" <<<"$uerr" && fail "unknown-argument error echoed the caller's value"
grep -qF "unknown argument" <<<"$uerr" || fail "unknown-argument error must still say what went wrong"

# (8) an explicitly supplied log root that does not exist is an input error — alone or mixed with a valid root
for roots in "$TMP/no-such-root" "$TMP/no-such-root,$LOGS"; do
  mout="$(bash "$CENSUS" --repo-root "$REPO" --skill demo-skill --days 30 --logs "$roots" 2>/dev/null || true)"
  bash "$CENSUS" --repo-root "$REPO" --skill demo-skill --days 30 --logs "$roots" >/dev/null 2>&1 || [ $? -eq 2 ] || fail "missing explicit log root must exit 2 ($roots)"
  grep -qF 'reference_access_census_unevaluated: 1 input error(s)' <<<"$mout" || fail "missing explicit log root must withhold counts:\n$mout"
  grep -qF 'reference_access_census_ok' <<<"$mout" && fail "ok token printed with a missing explicit log root"
  grep -qE '\| [0-9]+ \|' <<<"$mout" && fail "a table was printed with a missing explicit log root"
  grep -qF "$TMP" <<<"$mout" && fail "missing-root sentinel leaked a path"
done
# a missing DEFAULT root stays normal: with no --logs and an empty HOME the result is the no-transcript sentinel, exit 0
dout="$(HOME="$TMP/empty-home" bash "$CENSUS" --repo-root "$REPO" --skill demo-skill --days 30)" || fail "absent default roots must not be an input error"
[ "$(printf '%s\n' "$dout" | tail -1)" = "reference_access_census_unevaluated: no transcripts within 30d under 2 log root(s); counts withheld" ] || fail "absent default roots must yield the no-transcript sentinel:\n$dout"

# (10) overlapping log roots (a root and its own subtree, or a root listed twice) count each transcript once
oout="$(bash "$CENSUS" --repo-root "$REPO" --skill demo-skill --days 30 --logs "$TMP/logs-codex,$TMP/logs-codex/2026,$TMP/logs-codex")" || fail "overlapping roots run exited non-zero"
grep -qF 'transcripts=2 sessions_touching_package=2' <<<"$oout" || fail "overlapping roots must not double-count transcripts:\n$oout"
grep -qE '^references/alpha\.md \| 1 \|' <<<"$oout" || fail "alpha must count once under overlapping roots:\n$oout"

# (11) an invalid --skill value is never echoed back (a mistyped private identifier stays private)
kerr="$(bash "$CENSUS" --repo-root "$REPO" --skill "acme-internal-secret-project" --logs "$LOGS" 2>&1 >/dev/null || true)"
grep -qF "acme-internal-secret-project" <<<"$kerr" && fail "unknown --skill error echoed the caller's value"
grep -qF "usage_error" <<<"$kerr" || fail "unknown --skill must still be reported as a usage error"

# (12) a transcript whose name contains a newline is one candidate, not two broken ones
NL="$TMP/logs-newline"; mkdir -p "$NL"; printf '{"cmd":"cat skills/demo-skill/references/beta.md"}\n' > "$NL/odd
name.jsonl"
nout="$(bash "$CENSUS" --repo-root "$REPO" --skill demo-skill --days 30 --logs "$NL")" || fail "newline-named transcript run exited non-zero"
grep -qF 'transcripts=1 sessions_touching_package=1' <<<"$nout" || fail "newline in a transcript name must not split the candidate:\n$nout"

# (13) HOME unset and no --logs: no default roots, the no-transcript sentinel, exit 0 (never an unbound-variable abort)
hout="$(env -u HOME bash "$CENSUS" --repo-root "$REPO" --skill demo-skill --days 30)" || fail "unset HOME must not abort the census"
[ "$(printf '%s\n' "$hout" | tail -1)" = "reference_access_census_unevaluated: no transcripts within 30d under 0 log root(s); counts withheld" ] || fail "unset HOME must yield the no-transcript sentinel:\n$hout"

# (14) a transcript-read error forced by a command shim (root-independent twin of the chmod leg)
GSHIM="$TMP/gshim"; mkdir -p "$GSHIM"
printf '#!/usr/bin/env bash\necho "grep: transcript: Input/output error" >&2\nexit 2\n' > "$GSHIM/grep"; chmod +x "$GSHIM/grep"
gout="$(PATH="$GSHIM:$PATH" bash "$CENSUS" --repo-root "$REPO" --skill demo-skill --days 30 --logs "$LOGS" 2>/dev/null || true)"
PATH="$GSHIM:$PATH" bash "$CENSUS" --repo-root "$REPO" --skill demo-skill --days 30 --logs "$LOGS" >/dev/null 2>&1 || [ $? -eq 2 ] || fail "a grep read error must exit 2"
grep -qF 'reference_access_census_unevaluated:' <<<"$gout" || fail "a grep read error must withhold counts:\n$gout"
grep -qF 'reference_access_census_ok' <<<"$gout" && fail "ok token printed after a grep read error"

# (15) a grep that fails silently (exit 2, no stderr) is still an input error: withhold, exit 2, no ok token
QSHIM="$TMP/qshim"; mkdir -p "$QSHIM"
printf '#!/usr/bin/env bash\nexit 2\n' > "$QSHIM/grep"; chmod +x "$QSHIM/grep"
qout="$(PATH="$QSHIM:$PATH" bash "$CENSUS" --repo-root "$REPO" --skill demo-skill --days 30 --logs "$LOGS" 2>/dev/null || true)"
PATH="$QSHIM:$PATH" bash "$CENSUS" --repo-root "$REPO" --skill demo-skill --days 30 --logs "$LOGS" >/dev/null 2>&1 || [ $? -eq 2 ] || fail "a silent grep failure must exit 2"
grep -qF 'reference_access_census_unevaluated:' <<<"$qout" || fail "a silent grep failure must withhold counts:\n$qout"
grep -qF 'reference_access_census_ok' <<<"$qout" && fail "ok token printed after a silent grep failure"

# (16) an inherited errexit (caller exported SHELLOPTS=errexit) must not turn an all-no-match batch into an input error
NM="$TMP/logs-nomatch"; mkdir -p "$NM"; printf '{"cmd":"ls skills/other-skill/"}\n' > "$NM/quiet.jsonl"
mout2="$(env SHELLOPTS=errexit bash "$CENSUS" --repo-root "$REPO" --skill demo-skill --days 30 --logs "$NM")" || fail "inherited errexit must not abort a valid census"
grep -qF 'transcripts=1 sessions_touching_package=0' <<<"$mout2" || fail "all-no-match batch under inherited errexit must be a valid zero census:\n$mout2"
[ "$(printf '%s\n' "$mout2" | tail -1)" = "reference_access_census_ok" ] || fail "inherited errexit must not withhold a valid census"

# (17) a find that fails silently (exit 2, no stderr) is an input error: withhold, exit 2, no ok token
FSHIM="$TMP/fshim"; mkdir -p "$FSHIM"
printf '#!/usr/bin/env bash\nexit 2\n' > "$FSHIM/find"; chmod +x "$FSHIM/find"
fout="$(PATH="$FSHIM:$PATH" bash "$CENSUS" --repo-root "$REPO" --skill demo-skill --days 30 --logs "$LOGS" 2>/dev/null || true)"
frc=0; PATH="$FSHIM:$PATH" bash "$CENSUS" --repo-root "$REPO" --skill demo-skill --days 30 --logs "$LOGS" >/dev/null 2>&1 || frc=$?
[ "$frc" -eq 2 ] || fail "a silent find failure must exit 2 (got $frc)"
grep -qE 'reference_access_census_unevaluated: [0-9]+ input error' <<<"$fout" || fail "a silent find failure must withhold counts as an input error, not the no-transcript sentinel:\n$fout"
grep -qF 'reference_access_census_ok' <<<"$fout" && fail "ok token printed after a silent find failure"

# (9) a failing stat (a transcript vanishing before the timestamp read) withholds the table with exit 2 —
# deterministic via a PATH shim, independent of filesystem permissions or root
SHIM="$TMP/shim"; mkdir -p "$SHIM"
printf '#!/usr/bin/env bash\necho "stat: cannot stat: No such file or directory" >&2\nexit 1\n' > "$SHIM/stat"; chmod +x "$SHIM/stat"
sout="$(PATH="$SHIM:$PATH" bash "$CENSUS" --repo-root "$REPO" --skill demo-skill --days 30 --logs "$LOGS,$TMP/logs-codex" 2>/dev/null || true)"
PATH="$SHIM:$PATH" bash "$CENSUS" --repo-root "$REPO" --skill demo-skill --days 30 --logs "$LOGS,$TMP/logs-codex" >/dev/null 2>&1 || [ $? -eq 2 ] || fail "failing stat must exit 2, not the pipeline status"
grep -qF 'reference_access_census_unevaluated:' <<<"$sout" || fail "failing stat must print the unevaluated sentinel:\n$sout"
grep -qF 'reference_access_census_ok' <<<"$sout" && fail "ok token printed after a failing stat"
grep -qE '\| [0-9]+ \|' <<<"$sout" && fail "a table was printed after a failing stat"

echo "test_reference_access_census_ok"
