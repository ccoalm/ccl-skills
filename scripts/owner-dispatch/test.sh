#!/usr/bin/env bash
# RED -> GREEN behavioral + adversarial suite for the owner-dispatch firing gate.
# Each case proves: WITHOUT the rule the action proceeds silently (baseline);
# WITH it the gate fires; and the safety invariants (fail-open, symlink-safe,
# per-session, no-trap, CI anti-bypass) hold.
set -u
ENGINE="$(cd "$(dirname "$0")" && pwd)/owner-dispatch.sh"
PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); printf '  ok   %s\n' "$1"; }
bad() { FAIL=$((FAIL+1)); printf '  FAIL %s\n     %s\n' "$1" "${2:-}"; }

WORK=$(mktemp -d) || { echo "FATAL: mktemp -d failed (no writable TMPDIR)"; exit 1; }
trap 'rm -rf "$WORK"' EXIT
REPO="$WORK/prod"; mkdir -p "$REPO/src"
git -C "$REPO" init -q
git -C "$REPO" config user.email t@t; git -C "$REPO" config user.name t
echo "package x" > "$REPO/src/foo.go"; echo "# readme" > "$REPO/README.md"
git -C "$REPO" add -A; git -C "$REPO" commit -qm init
BDIR="$(git -C "$REPO" rev-parse --absolute-git-dir)/owner-dispatch"

edit() { printf '{"tool_name":"Edit","tool_input":{"file_path":"%s"},"session_id":"%s"}' "$1" "${2:-S0}"; }
bashj(){ printf '{"tool_name":"Bash","tool_input":{"command":"%s"}}' "$1"; }
bashjs(){ printf '{"tool_name":"Bash","tool_input":{"command":"%s"},"session_id":"%s"}' "$1" "$2"; }
stopj(){ printf '{"session_id":"%s"}' "${1:-}"; }
# opt-in now requires the config to be TRACKED at the git top-level, so commit it.
config(){ cat > "$REPO/.owner-dispatch.json"; ( cd "$REPO" && git add .owner-dispatch.json && git commit -q -m cfg -- .owner-dispatch.json ) >/dev/null 2>&1 || true; }
decision(){ jq -r '.hookSpecificOutput.permissionDecision // "allow"' 2>/dev/null; }
sdecision(){ local o; o=$(cat); [ -z "$o" ] && { echo stop; return; }; printf '%s' "$o" | jq -r '.decision // "stop"' 2>/dev/null; }

echo "owner-dispatch suite"

# 1. RED baseline: no config => silent allow.
out=$(edit "$REPO/src/foo.go" | bash "$ENGINE" pretool)
[ -z "$out" ] && ok "baseline: no config => silent allow" || bad "baseline" "got:$out"

config <<'JSON'
{ "enabled": true, "strict": false, "gate_bash": true,
  "product_globs": ["src/**"], "exclude_globs": ["**/*_test.*"],
  "owner_hint": "product-rd-workflow + the stack *-dev owner" }
JSON

# 2. GREEN gated edit, no boundary => ask.
[ "$(edit "$REPO/src/foo.go" S1 | bash "$ENGINE" pretool | decision)" = ask ] && ok "gated edit, no boundary => ask" || bad "expected ask"
# 3. excluded test file => allow.
echo x > "$REPO/src/foo_test.go"
[ -z "$(edit "$REPO/src/foo_test.go" | bash "$ENGINE" pretool)" ] && ok "excluded *_test.* => allow" || bad "excluded"
# 4. non-product => allow.
[ -z "$(edit "$REPO/README.md" | bash "$ENGINE" pretool)" ] && ok "non-product README => allow" || bad "README"
# 5. boundary recorded => allow.
( cd "$REPO" && bash "$ENGINE" record --owners "product-rd-workflow,go-dev" >/dev/null )
[ -z "$(edit "$REPO/src/foo.go" | bash "$ENGINE" pretool)" ] && ok "boundary recorded => allow" || bad "boundary allow"
# 5b. boundary SURVIVES a FORWARD HEAD move. Validity requires ancestry, not equality: the gate
#     requires recording before the first gated edit, and a delivery's own commit lands
#     after that edit — so pinning invalidated every committing delivery's own boundary and
#     made Stop report it as "never recorded". This asserts the HEAD-independent lifetime
#     ONLY — it does not assert anything about actor identity, which the gate does not
#     enforce (see the residual note on boundary_valid).
git -C "$REPO" commit -q --allow-empty -m moved
out_v5=$(edit "$REPO/src/foo.go" | bash "$ENGINE" pretool); st_v5=$?
[ "$st_v5" = 0 ] && [ -z "$out_v5" ] \
  && ok "boundary survives HEAD move => allow" || bad "V5: HEAD move must not invalidate a boundary"
# 5b-2. …but only FORWARD. A history discontinuity (switch to an unrelated branch, or a
#       reset onto a divergent commit) is a different piece of work and must re-fire the
#       gate. Equality caught this incidentally; ancestry catches it on purpose.
_orig_branch=$(git -C "$REPO" symbolic-ref --short HEAD); _orig_head=$(git -C "$REPO" rev-parse HEAD)
# Build a genuine SIBLING line (fork from the commit before the current tip, then add its own
# commit). Simply checking out the recorded commit is not a discontinuity — it is the very
# point the boundary was recorded at, so ancestry legitimately still holds there.
git -C "$REPO" branch od-diverge "HEAD~1" >/dev/null 2>&1
git -C "$REPO" checkout -q od-diverge && git -C "$REPO" commit -q --allow-empty -m "divergent work"
git -C "$REPO" checkout -q "$_orig_branch"
( cd "$REPO" && bash "$ENGINE" record --owners "product-rd-workflow,go-dev" >/dev/null )  # record on THIS line
# POSITIVE CONTROL: prove the fresh record is actually valid HERE first. Without it, a
# broken/malformed record would also produce `ask` after the switch and the test would pass
# without demonstrating that the switch is what invalidated it.
[ -z "$(edit "$REPO/src/foo.go" | bash "$ENGINE" pretool)" ] \
  && ok "discontinuity control: fresh record valid on its own line => allow" || bad "V5b control: fresh record must be valid before the switch"
git -C "$REPO" checkout -q od-diverge                       # jump to the unrelated line
[ "$(edit "$REPO/src/foo.go" | bash "$ENGINE" pretool | decision)" = ask ] \
  && ok "boundary does NOT survive a history discontinuity => ask" || bad "V5b: divergent history must re-fire the gate"
# …and it is the discontinuity specifically, not a generic invalidation: the state must be
# reported as `discontinuous`, never collapsed into "never recorded".
( cd "$REPO" && bash "$ENGINE" status ) 2>/dev/null | grep -q "^boundary: discontinuous" \
  && ok "status: divergent-line boundary reported as discontinuous" || bad "V5b: must report discontinuous, not absent"
# 5b-4. A `git replace --graft` must NOT be able to manufacture the missing ancestry.
#       merge-base honours replacement refs by default, so without GIT_NO_REPLACE_OBJECTS a
#       graft turns this same divergent state back into "valid". Assert the real-object answer.
_rec_head=$(jq -r '.head' "$BDIR/boundary.json" 2>/dev/null)
if git -C "$REPO" replace --graft "$(git -C "$REPO" rev-parse HEAD)" "$_rec_head" >/dev/null 2>&1; then
  [ "$(edit "$REPO/src/foo.go" | bash "$ENGINE" pretool | decision)" = ask ] \
    && ok "graft cannot fake ancestry (replacement refs ignored)" || bad "V5d: replace --graft bypassed the continuity check"
  git -C "$REPO" replace -d "$(git -C "$REPO" rev-parse HEAD)" >/dev/null 2>&1
else
  ok "graft fixture unavailable on this git => skipped (not a pass for the graft path)"
fi
# 5b-5. …and the LEGACY graft path too. GIT_NO_REPLACE_OBJECTS does not disable
#       `.git/info/grafts` (verified on git 2.50) — only GIT_GRAFT_FILE does, so both are
#       load-bearing and this fixture is what keeps the second one from being dropped.
_gitdir=$(git -C "$REPO" rev-parse --absolute-git-dir)
mkdir -p "$_gitdir/info"
printf '%s %s\n' "$(git -C "$REPO" rev-parse HEAD)" "$_rec_head" > "$_gitdir/info/grafts"
[ "$(edit "$REPO/src/foo.go" | bash "$ENGINE" pretool | decision)" = ask ] \
  && ok "legacy info/grafts cannot fake ancestry either" || bad "V5e: info/grafts bypassed the continuity check"
rm -f "$_gitdir/info/grafts"
git -C "$REPO" checkout -q "$_orig_branch" && git -C "$REPO" reset -q --hard "$_orig_head"
git -C "$REPO" branch -qD od-diverge 2>/dev/null
# 5b-3. The ancestry probe must FAIL CLOSED on every unusable recorded head — a gc'd or
#       shallow-clone-missing object, a malformed value, or a missing field must re-fire the
#       gate, never silently satisfy it. (merge-base exits non-zero for both "not an
#       ancestor" and "bad object"; both must land on ask.)
( cd "$REPO" && bash "$ENGINE" record --owners "product-rd-workflow,go-dev" >/dev/null )
for _bad in '"0000000000000000000000000000000000000000"' '"not-a-sha"' '""' 'null'; do
  jq ".head = $_bad" "$BDIR/boundary.json" > "$BDIR/b.tmp" && mv "$BDIR/b.tmp" "$BDIR/boundary.json"
  [ "$(edit "$REPO/src/foo.go" | bash "$ENGINE" pretool | decision)" = ask ] \
    || { bad "V5c: unusable recorded head ($_bad) must fail closed"; _v5c_bad=1; }
done
[ -n "${_v5c_bad:-}" ] || ok "unusable recorded head fails closed (bad/malformed/empty/null)"
# 5c-2. …and it must be labelled `absent`, NOT `discontinuous`. A well-formed but nonexistent
#       sha (all-zero, gc'd, shallow-clone-missing) is an unusable record — reporting "a
#       branch switch moved HEAD off it" would be exactly the false diagnosis this change
#       set exists to remove, just relocated to a new state.
jq '.head = "0000000000000000000000000000000000000000"' "$BDIR/boundary.json" > "$BDIR/b.tmp" && mv "$BDIR/b.tmp" "$BDIR/boundary.json"
( cd "$REPO" && bash "$ENGINE" status ) 2>/dev/null | grep -q "^boundary: absent" \
  && ok "status: nonexistent recorded commit => absent, not discontinuous" || bad "V5c2: nonexistent sha must not claim discontinuity"
# 5c-3. UNBORN repo fails closed. This is a deliberate change from the old equality rule,
#       which ALLOWED here: unborn `rev-parse HEAD` prints "HEAD" on stdout and fails, so the
#       old helper produced "HEAD\nNO_HEAD" on both sides and they compared equal. An unborn
#       repo has no line of work to be continuous with, and orphan-branch switches must not
#       satisfy the gate. Uses its own throwaway repo so the shared fixture is untouched.
UB=$(mktemp -d); git init -q "$UB"; git -C "$UB" config user.email t@t; git -C "$UB" config user.name t
mkdir -p "$UB/src"; echo "package main" > "$UB/src/foo.go"
printf '%s' '{ "enabled": true, "product_globs": ["src/**"] }' > "$UB/.owner-dispatch.json"
git -C "$UB" add .owner-dispatch.json >/dev/null 2>&1      # tracked-in-index, never committed
( cd "$UB" && bash "$ENGINE" record --owners "product-rd-workflow" >/dev/null 2>&1 )
[ "$(edit "$UB/src/foo.go" | ( cd "$UB" && bash "$ENGINE" pretool ) | decision)" = ask ] \
  && ok "unborn repo fails closed even after record (was allow under equality)" || bad "V5c3: unborn repo must fail closed"
rm -rf "$UB"
# 5c. expired boundary (TTL) => ask. TTL is now the only bound on boundary reuse at the
#     PreToolUse layer, so it carries its own assertion. Leaves an INVALID boundary behind
#     on purpose — case 6 (strict => deny) depends on that state.
( cd "$REPO" && bash "$ENGINE" record --owners "product-rd-workflow,go-dev" --ttl 0 >/dev/null )
[ "$(edit "$REPO/src/foo.go" | bash "$ENGINE" pretool | decision)" = ask ] && ok "boundary expired (TTL) => ask" || bad "V3: expired boundary must ask"
# 5d. `status` reports the real state, not a valid/not-valid collapse. It is the command an
#     agent runs to diagnose a block, so it must separate expired from never-recorded.
( cd "$REPO" && bash "$ENGINE" status ) 2>/dev/null | grep -q "^boundary: expired" \
  && ok "status: expired boundary reported as expired" || bad "status must report expired"
rm -f "$BDIR/boundary.json"
( cd "$REPO" && bash "$ENGINE" status ) 2>/dev/null | grep -q "^boundary: absent" \
  && ok "status: no boundary reported as absent" || bad "status must report absent"
# 5e. a malformed/non-integer expiry is NOT "expired" — it is an unparseable record, so the
#     label must stay on the conservative side rather than implying a usable record existed.
( cd "$REPO" && bash "$ENGINE" record --owners "x" >/dev/null )
jq '.expires_at = true' "$BDIR/boundary.json" > "$BDIR/b.tmp" && mv "$BDIR/b.tmp" "$BDIR/boundary.json"
( cd "$REPO" && bash "$ENGINE" status ) 2>/dev/null | grep -q "^boundary: absent" \
  && ok "status: non-integer expires_at => absent, not expired" || bad "malformed expiry must not report expired"
[ "$(edit "$REPO/src/foo.go" | bash "$ENGINE" pretool | decision)" = ask ] \
  && ok "malformed expiry: gate fails closed (ask, never allow)" || bad "malformed expiry must ask"
rm -f "$BDIR/boundary.json"
( cd "$REPO" && bash "$ENGINE" record --owners "product-rd-workflow,go-dev" --ttl 0 >/dev/null )

# 6. strict => deny.
config <<'JSON'
{ "enabled": true, "strict": true, "product_globs": ["src/**"] }
JSON
[ "$(edit "$REPO/src/foo.go" | bash "$ENGINE" pretool | decision)" = deny ] && ok "strict => deny" || bad "strict deny"
# 6b. strict downgrades to ask when state dir is unsafe (symlinked).
rm -rf "$BDIR"; ln -s /nonexistent-target "$BDIR"
[ "$(edit "$REPO/src/foo.go" | bash "$ENGINE" pretool | decision)" = ask ] && ok "strict + unsafe state dir => downgrade to ask (no brick)" || bad "strict downgrade"
rm -f "$BDIR"
# 6c. strict deny has an escape: a per-session waiver lets a narrow exempt edit proceed.
mkdir -p "$BDIR"; touch "$BDIR/s.SX.waiver"
[ -z "$(edit "$REPO/src/foo.go" SX | bash "$ENGINE" pretool)" ] && ok "strict + per-session waiver => allow (escape, no brick)" || bad "strict waiver escape"
rm -rf "$BDIR"

# 7. Bash write-heuristic is RECORD-ONLY: it records the .bashwrite activity marker
#    and ALLOWS SILENTLY (no user `ask` popup); the Stop hook + ci are the gates.
config <<'JSON'
{ "enabled": true, "product_globs": ["src/**"], "gate_bash": true }
JSON
rm -rf "$BDIR"
[ -z "$( cd "$REPO" && bashjs "echo hi >> src/foo.go" S7 | bash "$ENGINE" pretool )" ] \
  && ok "bash write-heuristic => allow silently (no popup)" || bad "bash heuristic still prompts"
[ -r "$BDIR/s.S7.bashwrite" ] && ok "bash write-heuristic still records .bashwrite (Stop backstop)" || bad "bash heuristic did not record"
[ -z "$( cd "$REPO" && bashj "cat src/foo.go" | bash "$ENGINE" pretool )" ] && ok "bash read-only => allow" || bad "bash read"
rm -rf "$BDIR"

# 8. Stop per-session cap + cross-session isolation. Stop blocks only when this
#    session actually CHANGED a gated path vs the baseline captured at first touch
#    (PreToolUse fires BEFORE the edit, so: capture baseline THEN apply the edit).
rm -rf "$BDIR"
edit "$REPO/src/foo.go" S1 | bash "$ENGINE" pretool >/dev/null   # baseline (foo.go clean)
echo "// real gated edit" >> "$REPO/src/foo.go"                  # the edit applies => dirty
d1=$( cd "$REPO" && stopj S1 | bash "$ENGINE" stop | sdecision )
d2=$( cd "$REPO" && stopj S1 | bash "$ENGINE" stop | sdecision )
{ [ "$d1" = block ] && [ "$d2" = stop ]; } && ok "main Stop blocks once per session (cap)" || bad "stop cap" "$d1/$d2"
d3=$( cd "$REPO" && stopj S2 | bash "$ENGINE" stop | sdecision )
[ "$d3" = stop ] && ok "fresh session not starved by another session's marker" || bad "cross-session" "$d3"
git -C "$REPO" checkout -q -- . 2>/dev/null
# 8b. No session id => fail-open (never trap).
d=$( cd "$REPO" && stopj "" | bash "$ENGINE" stop | sdecision )
[ "$d" = stop ] && ok "no session id => stop fail-open" || bad "no-session stop" "$d"
# 8c. session-scoped waiver => allow (even with a real changed gated file).
rm -rf "$BDIR"
edit "$REPO/src/foo.go" S3 | bash "$ENGINE" pretool >/dev/null; echo "// e" >> "$REPO/src/foo.go"
touch "$BDIR/s.S3.waiver"
[ "$( cd "$REPO" && stopj S3 | bash "$ENGINE" stop | sdecision )" = stop ] && ok "session-scoped waiver => allow" || bad "waiver"
git -C "$REPO" checkout -q -- . 2>/dev/null; rm -rf "$BDIR"
# 8d. after record, a boundary supersedes markers => gated edit ALLOWED (pretool).
edit "$REPO/src/foo.go" S4 | bash "$ENGINE" pretool >/dev/null
( cd "$REPO" && bash "$ENGINE" record --owners "product-rd-workflow" >/dev/null )
[ -z "$(edit "$REPO/src/foo.go" S4 | bash "$ENGINE" pretool)" ] && ok "record boundary supersedes markers => allow" || bad "record supersede"
rm -rf "$BDIR"
# 8e. OVER-FIRE FIX: read-only/dispatch-only session (heuristic match, CLEAN tree)
#     records only the .bashwrite sentinel and must NOT block.
git -C "$REPO" checkout -q -- . 2>/dev/null; git -C "$REPO" clean -fdq 2>/dev/null
( cd "$REPO" && bashjs "cat src/foo.go | python3 -c 'print(1)'" S5 | bash "$ENGINE" pretool ) >/dev/null 2>&1
[ -r "$BDIR/s.S5.bashwrite" ] && [ ! -e "$BDIR/s.S5.touched" ] \
  && ok "read-only heuristic match records .bashwrite sentinel only" || bad "heuristic wrote wrong marker"
[ "$( cd "$REPO" && stopj S5 | bash "$ENGINE" stop | sdecision )" = stop ] \
  && ok "stop: read-only heuristic match + clean tree => allow (over-fire fix)" || bad "over-fire: clean tree blocked"
# 8f. heuristic session that DOES change a gated file => block.
echo "// real" >> "$REPO/src/foo.go"
[ "$( cd "$REPO" && stopj S5 | bash "$ENGINE" stop | sdecision )" = block ] \
  && ok "stop: heuristic session + changed gated path => block" || bad "true-positive lost"
git -C "$REPO" checkout -q -- . 2>/dev/null; rm -rf "$BDIR"
# 8g. config-shrink anti-bypass: a real gated edit still blocks even after the config
#     is shrunk to de-classify it (baseline globs are unioned with current globs).
edit "$REPO/src/foo.go" SG | bash "$ENGINE" pretool >/dev/null    # baseline globs incl. src/**
echo "// real gated edit" >> "$REPO/src/foo.go"
config <<'JSON'
{ "enabled": true, "product_globs": ["other/**"], "gate_bash": true }
JSON
[ "$( cd "$REPO" && stopj SG | bash "$ENGINE" stop | sdecision )" = block ] \
  && ok "stop: gated edit + config shrink => still block (baseline-glob union)" || bad "shrink false-negative"
git -C "$REPO" checkout -q -- . 2>/dev/null; rm -rf "$BDIR"
config <<'JSON'
{ "enabled": true, "strict": false, "gate_bash": true,
  "product_globs": ["src/**"], "owner_hint": "product-rd-workflow + the stack *-dev owner" }
JSON
# 8h. committed-in-session gated edit (clean tree) STILL blocks (baseline HEAD diff
#     sees the commit because `git diff <baseline-head>` compares to the work tree).
rm -rf "$BDIR"
edit "$REPO/src/foo.go" SH | bash "$ENGINE" pretool >/dev/null    # baseline = pre-edit HEAD
echo "// committed gated edit" >> "$REPO/src/foo.go"
git -C "$REPO" add -A; git -C "$REPO" commit -qm "committed in-session"   # tree clean, HEAD moved
[ "$( cd "$REPO" && stopj SH | bash "$ENGINE" stop | sdecision )" = block ] \
  && ok "stop: committed gated edit (clean tree) => still block (baseline HEAD diff)" || bad "commit false-pass"
rm -rf "$BDIR"
# 8h-2. Stop WORDING splits absent vs expired. Both still block; the message must not tell
#       an actor that recorded a boundary it "never recorded" one — that wording sent
#       diagnosis looking for a missing record when the record existed and had lapsed.
edit "$REPO/src/foo.go" SH2 | bash "$ENGINE" pretool >/dev/null
echo "// gated edit, no boundary at all" >> "$REPO/src/foo.go"
out_sh2=$( cd "$REPO" && stopj SH2 | bash "$ENGINE" stop 2>&1 )
# Assert the DECISION as well as the wording: grepping message text alone would pass on an
# allow response that happened to contain the same words.
[ "$(printf '%s' "$out_sh2" | sdecision)" = block ] \
  && printf '%s' "$out_sh2" | grep -q "never recorded an owner-dispatch boundary" \
  && ok "stop: absent boundary => block + 'never recorded' wording" || bad "S4 wording"
rm -rf "$BDIR"
edit "$REPO/src/foo.go" SH3 | bash "$ENGINE" pretool >/dev/null
echo "// gated edit, boundary recorded then expired" >> "$REPO/src/foo.go"
( cd "$REPO" && bash "$ENGINE" record --owners "product-rd-workflow" --ttl 0 >/dev/null )
out_sh3=$( cd "$REPO" && stopj SH3 | bash "$ENGINE" stop 2>&1 )
[ "$(printf '%s' "$out_sh3" | sdecision)" = block ] \
  && printf '%s' "$out_sh3" | grep -q "expired before this actor finished" \
  && ! printf '%s' "$out_sh3" | grep -q "never recorded an owner-dispatch boundary" \
  && ok "stop: expired boundary => block + 'expired' wording, not 'never recorded'" || bad "S5 wording"
rm -rf "$BDIR"
git -C "$REPO" checkout -q -- . 2>/dev/null
# 8i. rejected/undone edit => allow. PreToolUse records the marker+baseline, but the
#     edit never applies (tree stays at baseline) => no new gated change => no false block.
edit "$REPO/src/foo.go" SI | bash "$ENGINE" pretool >/dev/null    # marker+baseline; edit NOT applied
[ "$( cd "$REPO" && stopj SI | bash "$ENGINE" stop | sdecision )" = stop ] \
  && ok "stop: rejected/undone edit (tree at baseline) => allow (no false block)" || bad "rejected-edit false-block"
rm -rf "$BDIR"
# 8j. PRE-EXISTING dirty gated file (dirty BEFORE the session) + a heuristic match =>
#     allow: the baseline records it as pre-existing, not this session's work.
echo "// pre-existing dirt" >> "$REPO/src/foo.go"                 # dirty BEFORE any touch
( cd "$REPO" && bashjs "cat src/foo.go | python3 -c 'print(1)'" SJ | bash "$ENGINE" pretool ) >/dev/null 2>&1
[ "$( cd "$REPO" && stopj SJ | bash "$ENGINE" stop | sdecision )" = stop ] \
  && ok "stop: pre-existing dirty gated file + heuristic => allow (baseline excludes it)" || bad "pre-existing-dirty false-block"
git -C "$REPO" checkout -q -- . 2>/dev/null; rm -rf "$BDIR"
# 8k. edit reverted/stashed back to baseline => allow (nothing landed).
edit "$REPO/src/foo.go" SK | bash "$ENGINE" pretool >/dev/null
echo "// will be reverted" >> "$REPO/src/foo.go"
git -C "$REPO" checkout -q -- "src/foo.go"                        # revert to baseline content
[ "$( cd "$REPO" && stopj SK | bash "$ENGINE" stop | sdecision )" = stop ] \
  && ok "stop: edit reverted to baseline => allow (nothing landed)" || bad "revert false-block"
rm -rf "$BDIR"
# 8l. pre-existing dirty gated file that is FURTHER edited this session => block
#     (baseline records its content hash, so a re-edit is distinguishable from dirt).
echo "// pre-existing dirt" >> "$REPO/src/foo.go"                 # dirty BEFORE the session
edit "$REPO/src/foo.go" SL | bash "$ENGINE" pretool >/dev/null    # baseline hashes foo.go as-is
echo "// further session edit" >> "$REPO/src/foo.go"              # content now differs from baseline
[ "$( cd "$REPO" && stopj SL | bash "$ENGINE" stop | sdecision )" = block ] \
  && ok "stop: pre-existing dirty file FURTHER edited => block (content-hash baseline)" || bad "pre-existing re-edit false-pass"
git -C "$REPO" checkout -q -- . 2>/dev/null; rm -rf "$BDIR"
# 8m. exclude-widen anti-bypass: adding an exclude that covers the edited file after
#     the first touch still blocks (baseline classification is honored).
edit "$REPO/src/foo.go" SM | bash "$ENGINE" pretool >/dev/null    # baseline: src/** gated, no excl
echo "// real gated edit" >> "$REPO/src/foo.go"
config <<'JSON'
{ "enabled": true, "product_globs": ["src/**"], "exclude_globs": ["src/**"], "gate_bash": true }
JSON
[ "$( cd "$REPO" && stopj SM | bash "$ENGINE" stop | sdecision )" = block ] \
  && ok "stop: gated edit + exclude-widen => still block (baseline classification)" || bad "exclude-widen false-pass"
git -C "$REPO" checkout -q -- . 2>/dev/null; rm -rf "$BDIR"
config <<'JSON'
{ "enabled": true, "strict": false, "gate_bash": true,
  "product_globs": ["src/**"], "owner_hint": "product-rd-workflow + the stack *-dev owner" }
JSON

# 9. Symlink-safe: a planted symlink state file must NOT clobber its target.
rm -rf "$BDIR"; mkdir -p "$BDIR"
SENT="$WORK/sentinel"; echo "PRECIOUS" > "$SENT"
ln -s "$SENT" "$BDIR/boundary.json"
( cd "$REPO" && bash "$ENGINE" record --owners "x" >/dev/null )
[ "$(cat "$SENT")" = "PRECIOUS" ] && ok "symlink-safe: record did not clobber symlink target" || bad "symlink clobber" "sentinel=$(cat "$SENT")"
[ ! -L "$BDIR/boundary.json" ] && ok "symlink-safe: planted symlink replaced with real file" || bad "symlink not replaced"
rm -rf "$BDIR"

# 9b. A leading **/ glob means "zero or more directories" and MUST gate a
#     TOP-LEVEL (repo-root) product file too. bash `case` is not globstar-aware,
#     so **/*.go alone only matches paths WITH a slash — a repo whose product
#     code is top-level + ["**/*.go"] config silently gates NOTHING (observed:
#     a real adapter repo was a complete no-op until the glob was fixed).
config <<'JSON'
{ "enabled": true, "strict": false, "gate_bash": true,
  "product_globs": ["**/*.go"], "exclude_globs": ["**/*_test.go"] }
JSON
echo "package x" > "$REPO/root.go"
[ "$(edit "$REPO/root.go" S9 | bash "$ENGINE" pretool | decision)" = ask ] && ok "**/ glob gates top-level root.go (zero-or-more dirs)" || bad "top-level **/*.go NOT gated" "the no-op trap: a repo-root product file is ungated"
echo "package x" > "$REPO/root_test.go"
[ -z "$(edit "$REPO/root_test.go" | bash "$ENGINE" pretool)" ] && ok "**/ exclude still excludes top-level root_test.go" || bad "top-level **/*_test.go not excluded"
[ "$(edit "$REPO/src/foo.go" S9 | bash "$ENGINE" pretool | decision)" = ask ] && ok "**/ glob still gates subdir src/foo.go (no regression)" || bad "subdir regression under **/ glob"
rm -rf "$BDIR"

# ---- 10. CI backstop (raw config writes; commits managed explicitly per scenario) ----
rawcfg(){ cat > "$REPO/.owner-dispatch.json"; }
gc(){ git -C "$REPO" add -A; git -C "$REPO" commit -q -m "$1"; }
EN='{ "enabled": true, "product_globs": ["src/**"], "ci_artifact": "design/map.md" }'

# 10a. enabled, gated change, no artifact => fail.
printf '%s\n' "$EN" | rawcfg; gc cfg
base=$(git -C "$REPO" rev-parse HEAD)
echo "// change" >> "$REPO/src/foo.go"; gc change
( cd "$REPO" && bash "$ENGINE" ci --base "$base" >/dev/null 2>&1 ) && bad "ci no-artifact should fail" || ok "ci: gated change, no artifact => fail"
# 10b. artifact updated in the change => ok.
mkdir -p "$REPO/design"; echo "owners: x" > "$REPO/design/map.md"; gc map
( cd "$REPO" && bash "$ENGINE" ci --base "$base" >/dev/null 2>&1 ) && ok "ci: artifact updated in change => ok" || bad "ci ok"
# 10c. stale artifact (gated change without touching the map) => fail.
base2=$(git -C "$REPO" rev-parse HEAD)
echo "// more" >> "$REPO/src/foo.go"; gc change2
( cd "$REPO" && bash "$ENGINE" ci --base "$base2" >/dev/null 2>&1 ) && bad "ci stale should fail" || ok "ci: stale artifact => fail"
# 10d. unsafe ci_artifact path (+ gated change) => fail.
printf '%s\n' '{ "enabled": true, "product_globs": ["src/**"], "ci_artifact": "../evil" }' | rawcfg
echo "// c" >> "$REPO/src/foo.go"; gc badcfg
( cd "$REPO" && bash "$ENGINE" ci --base "$(git -C "$REPO" rev-parse HEAD~1)" >/dev/null 2>&1 ) && bad "ci unsafe should fail" || ok "ci: unsafe ci_artifact path => fail"
# 10e. shrink product_globs to dodge a gated change (base globs still apply) => fail.
printf '%s\n' "$EN" | rawcfg; gc reenable
shrinkbase=$(git -C "$REPO" rev-parse HEAD)
printf '%s\n' '{ "enabled": true, "product_globs": ["nonexistent/**"], "ci_artifact": "design/map.md" }' | rawcfg
echo "// dodge" >> "$REPO/src/foo.go"; gc shrink
( cd "$REPO" && bash "$ENGINE" ci --base "$shrinkbase" >/dev/null 2>&1 ) && bad "ci shrink-dodge should fail" || ok "ci: shrink product_globs to dodge => fail (base-glob union)"
# 10f. disable + gated change in one commit (from enabled base) => fail.
printf '%s\n' "$EN" | rawcfg; gc reenable2
enbase=$(git -C "$REPO" rev-parse HEAD)
printf '%s\n' '{ "enabled": false, "product_globs": ["src/**"] }' | rawcfg
echo "// sneaky" >> "$REPO/src/foo.go"; gc disable
( cd "$REPO" && bash "$ENGINE" ci --base "$enbase" >/dev/null 2>&1 ) && bad "ci disable+gated should fail" || ok "ci: disable gate + gated change => fail (anti-bypass)"
# 10g. clean decommit: config-only removal, no gated change => allowed (0).
printf '%s\n' "$EN" | rawcfg; echo "// x" >> "$REPO/src/foo.go"; gc reenable3
enbase2=$(git -C "$REPO" rev-parse HEAD)
git -C "$REPO" rm -q .owner-dispatch.json; git -C "$REPO" commit -q -m decommit
( cd "$REPO" && bash "$ENGINE" ci --base "$enbase2" >/dev/null 2>&1 ) && ok "ci: clean config-only decommit => allowed(0)" || bad "ci decommit"
# 10g2. ci_artifact pointing at product code (would self-satisfy) => fail.
printf '%s\n' "$EN" | rawcfg; gc reN
b_art=$(git -C "$REPO" rev-parse HEAD)
printf '%s\n' '{ "enabled": true, "product_globs": ["src/**"], "ci_artifact": "src/foo.go" }' | rawcfg
echo "// art" >> "$REPO/src/foo.go"; gc artbad
( cd "$REPO" && bash "$ENGINE" ci --base "$b_art" >/dev/null 2>&1 ) && bad "ci artifact=product should fail" || ok "ci: ci_artifact pointing at product code => fail"
# 10g3. enabled but schema-invalid config (product_globs not an array) => fail-closed.
printf '%s\n' "$EN" | rawcfg; gc reS
b_sch=$(git -C "$REPO" rev-parse HEAD)
printf '%s\n' '{ "enabled": true, "product_globs": "src/**" }' | rawcfg
echo "// s" >> "$REPO/src/foo.go"; gc schbad
( cd "$REPO" && bash "$ENGINE" ci --base "$b_sch" >/dev/null 2>&1 ) && bad "ci schema-invalid should fail" || ok "ci: enabled schema-invalid config => fail-closed"
# 10g5. tracked-but-malformed config + gated change (from a non-enabled base) => fail-closed.
git -C "$REPO" rm -q .owner-dispatch.json 2>/dev/null; gc noc
b_m=$(git -C "$REPO" rev-parse HEAD)
printf '%s' '{ bad json not closed' > "$REPO/.owner-dispatch.json"; echo "// m" >> "$REPO/src/foo.go"; gc malformed
( cd "$REPO" && bash "$ENGINE" ci --base "$b_m" >/dev/null 2>&1 ) && bad "ci malformed should fail" || ok "ci: tracked malformed config => fail-closed"
# 10g5b. tracked-but-non-object JSON is also malformed as a config => fail-closed.
printf '%s\n' "$EN" | rawcfg; gc reObj
b_obj=$(git -C "$REPO" rev-parse HEAD)
printf '%s\n' '[]' > "$REPO/.owner-dispatch.json"; gc nonobject
( cd "$REPO" && bash "$ENGINE" ci --base "$b_obj" >/dev/null 2>&1 ) && bad "ci non-object config should fail" || ok "ci: tracked non-object config => fail-closed"
# 10g6. ./-prefixed ci_artifact resolves to git path form => not false-failed.
printf '%s\n' '{ "enabled": true, "product_globs": ["src/**"], "ci_artifact": "./design/map.md" }' | rawcfg; gc reDot
b_dot=$(git -C "$REPO" rev-parse HEAD)
echo "// d" >> "$REPO/src/foo.go"; mkdir -p "$REPO/design"; echo owners > "$REPO/design/map.md"; gc dotchange
( cd "$REPO" && bash "$ENGINE" ci --base "$b_dot" >/dev/null 2>&1 ) && ok "ci: ./-prefixed ci_artifact matches => ok" || bad "ci dot-artifact false-fail"
# 10g6b. '..' inside a filename is safe; only '..' path components are unsafe.
printf '%s\n' '{ "enabled": true, "product_globs": ["src/**"], "ci_artifact": "design/v1..2-map.md" }' | rawcfg; gc reDotsName
b_dots_name=$(git -C "$REPO" rev-parse HEAD)
echo "// d2" >> "$REPO/src/foo.go"; mkdir -p "$REPO/design"; echo owners > "$REPO/design/v1..2-map.md"; gc dotsname
( cd "$REPO" && bash "$ENGINE" ci --base "$b_dots_name" >/dev/null 2>&1 ) && ok "ci: ci_artifact filename containing '..' => ok" || bad "ci dots-in-filename false-fail"
# 10g7. malforming an enabled config in a config-only change (no product change) => fail-closed.
printf '%s\n' "$EN" | rawcfg; gc reMM
b_mm=$(git -C "$REPO" rev-parse HEAD)
printf '%s' '{ bad' > "$REPO/.owner-dispatch.json"; gc malformonly
( cd "$REPO" && bash "$ENGINE" ci --base "$b_mm" >/dev/null 2>&1 ) && bad "malform-only should fail" || ok "ci: malform enabled config (config-only) => fail-closed (not decommit)"
# 10g4. a gated product path WITH A SPACE is classified correctly (no substring/split bug).
printf '%s\n' "$EN" | rawcfg; gc reSP
b_sp=$(git -C "$REPO" rev-parse HEAD)
echo "x" > "$REPO/src/a b.go"; gc spacefile
( cd "$REPO" && bash "$ENGINE" ci --base "$b_sp" >/dev/null 2>&1 ) && bad "ci space-path should fail (gated, no map)" || ok "ci: gated path with a space classified => fail"
# 10g8. CI fallback: a runner without jq but with python3 still verifies the same
#       backstop semantics instead of warning forever because a shared runner lacks jq.
NOJQBIN="$WORK/nojqbin"; mkdir -p "$NOJQBIN"
for _cmd in bash git python3 dirname basename; do ln -sf "$(command -v "$_cmd")" "$NOJQBIN/$_cmd"; done
EN_NJ='{ "enabled": true, "product_globs": ["src/**"], "ci_artifact": "design/nojq-map.md" }'
printf '%s\n' "$EN_NJ" | rawcfg; gc reNJ
b_nj=$(git -C "$REPO" rev-parse HEAD)
echo "// nojq fail" >> "$REPO/src/foo.go"; gc nojqfail
( cd "$REPO" && PATH="$NOJQBIN" bash "$ENGINE" ci --base "$b_nj" >/dev/null 2>&1 ) \
  && bad "ci no-jq no-artifact should fail" || ok "ci: no-jq fallback keeps no-artifact failure"
mkdir -p "$REPO/design"; printf 'owners nojq\n' > "$REPO/design/nojq-map.md"; gc nojqmap
( cd "$REPO" && PATH="$NOJQBIN" bash "$ENGINE" ci --base "$b_nj" >/dev/null 2>&1 ) \
  && ok "ci: no-jq fallback accepts updated artifact" || bad "ci no-jq fallback false-fail"
jq_rc=0; ( cd "$REPO" && bash "$ENGINE" ci --base "$b_nj" >/dev/null 2>&1 ) || jq_rc=$?
py_rc=0; ( cd "$REPO" && PATH="$NOJQBIN" bash "$ENGINE" ci --base "$b_nj" >/dev/null 2>&1 ) || py_rc=$?
[ "$jq_rc" = "$py_rc" ] && ok "ci: jq and no-jq verdicts match on same fixture ($jq_rc)" || bad "ci jq/no-jq parity" "jq=$jq_rc py=$py_rc"
EN_STAR='{ "enabled": true, "product_globs": ["src/*.go"], "ci_artifact": "design/star-map.md" }'
printf '%s\n' "$EN_STAR" | rawcfg; gc reStar
b_star=$(git -C "$REPO" rev-parse HEAD)
mkdir -p "$REPO/src/nested" "$REPO/design"; echo "package nested" > "$REPO/src/nested/b.go"; echo star > "$REPO/design/star-map.md"; gc starglob
jq_rc=0; ( cd "$REPO" && bash "$ENGINE" ci --base "$b_star" >/dev/null 2>&1 ) || jq_rc=$?
py_rc=0; ( cd "$REPO" && PATH="$NOJQBIN" bash "$ENGINE" ci --base "$b_star" >/dev/null 2>&1 ) || py_rc=$?
[ "$jq_rc" = "$py_rc" ] && ok "ci: jq/no-jq parity for single-star nested path ($jq_rc)" || bad "ci single-star parity" "jq=$jq_rc py=$py_rc"
EN_EXCL='{ "enabled": true, "product_globs": ["src/**"], "exclude_globs": ["src/*.go"], "ci_artifact": "design/exclude-map.md" }'
printf '%s\n' "$EN_EXCL" | rawcfg; gc reExcl
b_excl=$(git -C "$REPO" rev-parse HEAD)
echo "package excluded" > "$REPO/src/nested/excluded.go"; gc exclglob
jq_rc=0; ( cd "$REPO" && bash "$ENGINE" ci --base "$b_excl" >/dev/null 2>&1 ) || jq_rc=$?
py_rc=0; ( cd "$REPO" && PATH="$NOJQBIN" bash "$ENGINE" ci --base "$b_excl" >/dev/null 2>&1 ) || py_rc=$?
[ "$jq_rc" = "$py_rc" ] && ok "ci: jq/no-jq parity for exclude single-star nested path ($jq_rc)" || bad "ci exclude-star parity" "jq=$jq_rc py=$py_rc"
EN_ROOTTXT='{ "enabled": true, "product_globs": ["**/*.txt"], "ci_artifact": "design/root-txt-map.md" }'
printf '%s\n' "$EN_ROOTTXT" | rawcfg; gc reRootTxt
b_root_txt=$(git -C "$REPO" rev-parse HEAD)
echo root > "$REPO/root.txt"; gc roottxt
jq_rc=0; ( cd "$REPO" && bash "$ENGINE" ci --base "$b_root_txt" >/dev/null 2>&1 ) || jq_rc=$?
py_rc=0; ( cd "$REPO" && PATH="$NOJQBIN" bash "$ENGINE" ci --base "$b_root_txt" >/dev/null 2>&1 ) || py_rc=$?
[ "$jq_rc" = "$py_rc" ] && ok "ci: jq/no-jq parity for **/ product root path ($jq_rc)" || bad "ci root **/ product parity" "jq=$jq_rc py=$py_rc"
EN_ROOTMD='{ "enabled": true, "product_globs": ["**/*.md"], "ci_artifact": "design/root-md-map.md" }'
printf '%s\n' "$EN_ROOTMD" | rawcfg; gc reRootMd
b_root_md=$(git -C "$REPO" rev-parse HEAD)
echo root > "$REPO/root.md"; gc rootmd
jq_rc=0; ( cd "$REPO" && bash "$ENGINE" ci --base "$b_root_md" >/dev/null 2>&1 ) || jq_rc=$?
py_rc=0; ( cd "$REPO" && PATH="$NOJQBIN" bash "$ENGINE" ci --base "$b_root_md" >/dev/null 2>&1 ) || py_rc=$?
[ "$jq_rc" = "$py_rc" ] && ok "ci: jq/no-jq parity for default **/*.md root exclude ($jq_rc)" || bad "ci root md exclude parity" "jq=$jq_rc py=$py_rc"
EN_EMPTY_ART='{ "enabled": true, "product_globs": ["src/**"], "ci_artifact": "" }'
printf '%s\n' "$EN_EMPTY_ART" | rawcfg; gc reEmptyArt
b_empty_art=$(git -C "$REPO" rev-parse HEAD)
echo "// empty art" >> "$REPO/src/foo.go"; gc emptyart
jq_rc=0; ( cd "$REPO" && bash "$ENGINE" ci --base "$b_empty_art" >/dev/null 2>&1 ) || jq_rc=$?
py_rc=0; ( cd "$REPO" && PATH="$NOJQBIN" bash "$ENGINE" ci --base "$b_empty_art" >/dev/null 2>&1 ) || py_rc=$?
[ "$jq_rc" = "$py_rc" ] && ok "ci: jq/no-jq parity for empty ci_artifact ($jq_rc)" || bad "ci empty artifact parity" "jq=$jq_rc py=$py_rc"
EN_NULL_ART='{ "enabled": true, "product_globs": ["src/**"], "ci_artifact": null }'
printf '%s\n' "$EN_NULL_ART" | rawcfg; gc reNullArt
b_null_art=$(git -C "$REPO" rev-parse HEAD)
echo "// null art" >> "$REPO/src/foo.go"; mkdir -p "$REPO/design"; echo owners > "$REPO/design/owner-dispatch-map.md"; gc nullart
jq_rc=0; ( cd "$REPO" && bash "$ENGINE" ci --base "$b_null_art" >/dev/null 2>&1 ) || jq_rc=$?
py_rc=0; ( cd "$REPO" && PATH="$NOJQBIN" bash "$ENGINE" ci --base "$b_null_art" >/dev/null 2>&1 ) || py_rc=$?
[ "$jq_rc" = "$py_rc" ] && ok "ci: jq/no-jq parity for null ci_artifact default ($jq_rc)" || bad "ci null artifact parity" "jq=$jq_rc py=$py_rc"
EN_STRICT='{ "enabled": true, "strict": true, "gate_bash": false, "product_globs": ["src/**"], "ci_artifact": "design/strict-map.md" }'
printf '%s\n' "$EN_STRICT" | rawcfg; gc reStrict
b_strict=$(git -C "$REPO" rev-parse HEAD)
echo "// strict" >> "$REPO/src/foo.go"; echo strict > "$REPO/design/strict-map.md"; gc strictci
jq_rc=0; ( cd "$REPO" && bash "$ENGINE" ci --base "$b_strict" >/dev/null 2>&1 ) || jq_rc=$?
py_rc=0; ( cd "$REPO" && PATH="$NOJQBIN" bash "$ENGINE" ci --base "$b_strict" >/dev/null 2>&1 ) || py_rc=$?
[ "$jq_rc" = "$py_rc" ] && ok "ci: jq/no-jq parity for strict+gate_bash schema edge ($jq_rc)" || bad "ci strict/gate_bash parity" "jq=$jq_rc py=$py_rc"
EN_BAD_BOOL='{ "enabled": true, "strict": 1, "gate_bash": "false", "product_globs": ["src/**"], "ci_artifact": "design/bad-bool-map.md" }'
printf '%s\n' "$EN_BAD_BOOL" | rawcfg; gc reBadBool
b_bad_bool=$(git -C "$REPO" rev-parse HEAD)
echo "// bad bool" >> "$REPO/src/foo.go"; gc badbool
jq_rc=0; ( cd "$REPO" && bash "$ENGINE" ci --base "$b_bad_bool" >/dev/null 2>&1 ) || jq_rc=$?
py_rc=0; ( cd "$REPO" && PATH="$NOJQBIN" bash "$ENGINE" ci --base "$b_bad_bool" >/dev/null 2>&1 ) || py_rc=$?
[ "$jq_rc" = "$py_rc" ] && ok "ci: jq/no-jq parity for non-boolean strict/gate_bash ($jq_rc)" || bad "ci bad bool parity" "jq=$jq_rc py=$py_rc"
EN_EMPTY_BRANCH='{ "enabled": true, "product_globs": ["src/**"], "ci_artifact": "design/empty-branch-map.md" }'
printf '%s\n' "$EN_EMPTY_BRANCH" | rawcfg; gc reEmptyBranch
b_empty_branch=$(git -C "$REPO" rev-parse HEAD)
git -C "$REPO" update-ref refs/remotes/origin/main "$b_empty_branch"
echo "// empty branch" >> "$REPO/src/foo.go"; echo branch > "$REPO/design/empty-branch-map.md"; gc emptybranch
jq_rc=0; ( cd "$REPO" && CI_DEFAULT_BRANCH="" bash "$ENGINE" ci >/dev/null 2>&1 ) || jq_rc=$?
py_rc=0; ( cd "$REPO" && CI_DEFAULT_BRANCH="" PATH="$NOJQBIN" bash "$ENGINE" ci >/dev/null 2>&1 ) || py_rc=$?
[ "$jq_rc" = "$py_rc" ] && ok "ci: jq/no-jq parity for empty CI_DEFAULT_BRANCH fallback ($jq_rc)" || bad "ci empty CI_DEFAULT_BRANCH parity" "jq=$jq_rc py=$py_rc"
printf '%s\n' "$EN_NJ" | rawcfg; gc reNJS
b_njs=$(git -C "$REPO" rev-parse HEAD)
printf '%s\n' '{ "enabled": true, "product_globs": "src/**", "ci_artifact": "design/nojq-map.md" }' | rawcfg
echo "// nojq schema" >> "$REPO/src/foo.go"; gc nojqschema
py_rc=0; ( cd "$REPO" && PATH="$NOJQBIN" bash "$ENGINE" ci --base "$b_njs" >/dev/null 2>&1 ) || py_rc=$?
[ "$py_rc" = 2 ] && ok "ci: no-jq fallback schema-invalid => fail-closed(2)" || bad "ci no-jq schema rc" "py=$py_rc"
printf '%s\n' "$EN_NJ" | rawcfg; gc reNJD
b_njd=$(git -C "$REPO" rev-parse HEAD)
printf '%s\n' '{ "enabled": false, "product_globs": ["src/**"], "ci_artifact": "design/nojq-map.md" }' | rawcfg
echo "// nojq disable" >> "$REPO/src/foo.go"; gc nojqdisable
py_rc=0; ( cd "$REPO" && PATH="$NOJQBIN" bash "$ENGINE" ci --base "$b_njd" >/dev/null 2>&1 ) || py_rc=$?
[ "$py_rc" = 1 ] && ok "ci: no-jq fallback disable+gated => fail(1)" || bad "ci no-jq disable rc" "py=$py_rc"
printf '%s\n' "$EN_NJ" | rawcfg; gc reNJObj
b_njo=$(git -C "$REPO" rev-parse HEAD)
printf '%s\n' '[]' > "$REPO/.owner-dispatch.json"; gc nojqnonobject
jq_rc=0; ( cd "$REPO" && bash "$ENGINE" ci --base "$b_njo" >/dev/null 2>&1 ) || jq_rc=$?
py_rc=0; ( cd "$REPO" && PATH="$NOJQBIN" bash "$ENGINE" ci --base "$b_njo" >/dev/null 2>&1 ) || py_rc=$?
[ "$py_rc" = 2 ] && ok "ci: no-jq fallback non-object config => fail-closed(2)" || bad "ci no-jq non-object rc" "py=$py_rc"
[ "$jq_rc" = "$py_rc" ] && ok "ci: jq/no-jq parity for non-object config ($jq_rc)" || bad "ci non-object parity" "jq=$jq_rc py=$py_rc"
# 10h. never opted in (absent at base AND head) => skip(0).
git -C "$REPO" rm -q .owner-dispatch.json 2>/dev/null; gc rmfinal
nb=$(git -C "$REPO" rev-parse HEAD)
echo "// z" >> "$REPO/src/foo.go"; gc more
( cd "$REPO" && bash "$ENGINE" ci --base "$nb" >/dev/null 2>&1 ) && ok "ci: never opted in => skip(0)" || bad "ci skip"
# 10i. CI fails CLOSED when it cannot determine a base (no --base, no upstream).
if ( cd "$REPO" && bash "$ENGINE" ci >/dev/null 2>&1 ); then bad "ci no-base should fail-closed"; else ok "ci: no base => fail-closed (non-zero)"; fi

# ---- 11. SubagentStop: agent_id-scoped enforcement (the same engine handles Stop +
#         SubagentStop; agent_id is present only for the latter and scopes markers/cap). ----
rm -rf "$BDIR"
config <<'JSON'
{ "enabled": true, "strict": false, "gate_bash": true,
  "product_globs": ["src/**"], "owner_hint": "product-rd-workflow + the stack *-dev owner" }
JSON
# pretool/stop input variants that carry agent_id (subagent context).
edita() { printf '{"tool_name":"Edit","tool_input":{"file_path":"%s"},"session_id":"%s","agent_id":"%s"}' "$1" "$2" "$3"; }
stopa() { printf '{"session_id":"%s","agent_id":"%s"}' "$1" "$2"; }
# Mirror the engine's injective agent_id key (jq @base64 of the raw value, base64url-ized).
akey() { jq -nr --arg a "$1" '$a | @base64' | tr '+/' '-_'; }

# 11a. RED baseline: WITHOUT the subagent edit there is no per-agent activity => allow.
[ "$( cd "$REPO" && stopa SUB A1 | bash "$ENGINE" stop | sdecision )" = stop ] \
  && ok "SubagentStop baseline: no per-agent activity => allow" || bad "subagent baseline"
# 11b. subagent edits gated code => SubagentStop blocks ONCE for that agent.
edita "$REPO/src/foo.go" SUB A1 | bash "$ENGINE" pretool >/dev/null      # baseline + per-agent .touched
echo "// sub gated edit" >> "$REPO/src/foo.go"
s1=$( cd "$REPO" && stopa SUB A1 | bash "$ENGINE" stop | sdecision )
s2=$( cd "$REPO" && stopa SUB A1 | bash "$ENGINE" stop | sdecision )
{ [ "$s1" = block ] && [ "$s2" = stop ]; } && ok "SubagentStop: subagent gated edit => block once per agent" || bad "subagent cap" "$s1/$s2"
# 11c. a read-only sibling subagent (same session, no activity) is NOT starved/blocked.
[ "$( cd "$REPO" && stopa SUB A2 | bash "$ENGINE" stop | sdecision )" = stop ] \
  && ok "SubagentStop: read-only sibling subagent => allow (per-agent activity gate)" || bad "sibling subagent false-block"
# 11d. the MAIN Stop (no agent_id) has an INDEPENDENT cap — a subagent's block does not
#      consume the main session's nudge (markers exist at session scope too).
[ "$( cd "$REPO" && stopj SUB | bash "$ENGINE" stop | sdecision )" = block ] \
  && ok "Stop: main session blocks independently of the subagent's cap" || bad "main cap shared with subagent"
git -C "$REPO" checkout -q -- . 2>/dev/null; rm -rf "$BDIR"
# 11e. per-subagent waiver => allow (even with a real changed gated file).
edita "$REPO/src/foo.go" SUB A3 | bash "$ENGINE" pretool >/dev/null
echo "// gated" >> "$REPO/src/foo.go"
touch "$BDIR/s.SUB.a.$(akey A3).waiver"
[ "$( cd "$REPO" && stopa SUB A3 | bash "$ENGINE" stop | sdecision )" = stop ] \
  && ok "SubagentStop: per-subagent waiver => allow" || bad "subagent waiver"
git -C "$REPO" checkout -q -- . 2>/dev/null; rm -rf "$BDIR"
# 11f. a session-level waiver suppresses a subagent block too (broad escape hatch).
edita "$REPO/src/foo.go" SUB A5 | bash "$ENGINE" pretool >/dev/null
echo "// gated" >> "$REPO/src/foo.go"
touch "$BDIR/s.SUB.waiver"
[ "$( cd "$REPO" && stopa SUB A5 | bash "$ENGINE" stop | sdecision )" = stop ] \
  && ok "SubagentStop: session-level waiver suppresses subagent block" || bad "session waiver vs subagent"
git -C "$REPO" checkout -q -- . 2>/dev/null; rm -rf "$BDIR"
# 11g. PreToolUse still nudges a subagent editing gated code (ask), and records the
#      per-agent marker for the Stop backstop.
[ "$( edita "$REPO/src/foo.go" SUB A6 | bash "$ENGINE" pretool | decision )" = ask ] \
  && ok "PreToolUse: subagent gated edit => ask (fires in subagents)" || bad "subagent pretool ask"
[ -r "$BDIR/s.SUB.a.$(akey A6).touched" ] && ok "PreToolUse: subagent records per-agent .touched marker" || bad "no per-agent marker"
rm -rf "$BDIR"
# 11h. ACTOR-PRECISE attribution (the P1 fix): A1 attempts a gated edit (records a marker)
#      but does NOT change anything; A2 changes a DIFFERENT gated file. A1's SubagentStop
#      must ALLOW (not blamed for A2's change); A2's must BLOCK.
git -C "$REPO" checkout -q -- . 2>/dev/null; git -C "$REPO" clean -fdq 2>/dev/null
echo "package b" > "$REPO/src/b.go"; git -C "$REPO" add -A; git -C "$REPO" commit -qm addb
edita "$REPO/src/foo.go" SUB A1 | bash "$ENGINE" pretool >/dev/null   # A1 marker on foo.go; edit NOT applied
edita "$REPO/src/b.go"   SUB A2 | bash "$ENGINE" pretool >/dev/null   # A2 marker on b.go
echo "// only A2's file changes" >> "$REPO/src/b.go"                  # only b.go is dirty
[ "$( cd "$REPO" && stopa SUB A1 | bash "$ENGINE" stop | sdecision )" = stop ] \
  && ok "SubagentStop: A1 attempted-but-unchanged, sibling A2 changed => A1 allow (no cross-blame)" || bad "cross-agent false-block (P1)"
[ "$( cd "$REPO" && stopa SUB A2 | bash "$ENGINE" stop | sdecision )" = block ] \
  && ok "SubagentStop: A2 actually changed its gated file => A2 block (true positive kept)" || bad "A2 true-positive lost"
git -C "$REPO" checkout -q -- . 2>/dev/null; git -C "$REPO" clean -fdq 2>/dev/null; rm -rf "$BDIR"
# 11i. Bash-only subagent (heuristic sentinel, no .touched path list) is not path-
#      attributable => SubagentStop does NOT block (advisory Bash posture; session Stop/ci
#      remain the backstop). Even with a real gated change present.
echo "// pre" > "$REPO/src/foo.go"; git -C "$REPO" add -A; git -C "$REPO" commit -qm pre
( cd "$REPO" && printf '{"tool_name":"Bash","tool_input":{"command":"echo x >> src/foo.go"},"session_id":"SUB","agent_id":"A7"}' | bash "$ENGINE" pretool ) >/dev/null 2>&1
echo "// real change" >> "$REPO/src/foo.go"
[ -r "$BDIR/s.SUB.a.$(akey A7).bashwrite" ] && [ ! -e "$BDIR/s.SUB.a.$(akey A7).touched" ] \
  && ok "Bash-only subagent records per-agent .bashwrite sentinel only" || bad "bash-only subagent marker shape"
[ "$( cd "$REPO" && stopa SUB A7 | bash "$ENGINE" stop | sdecision )" = stop ] \
  && ok "SubagentStop: Bash-only subagent => allow (not path-attributable, by design)" || bad "bash-only subagent blocked"
git -C "$REPO" checkout -q -- . 2>/dev/null; git -C "$REPO" clean -fdq 2>/dev/null; rm -rf "$BDIR"
# 11j. CHALLENGE FIX: baseline state lost mid-session for a subagent => NOT attributable =>
#      allow. Must NOT fall back to the session-wide check (which would blame a sibling).
echo "// pre" > "$REPO/src/foo.go"; git -C "$REPO" add -A; git -C "$REPO" commit -qm prej
edita "$REPO/src/foo.go" SUB AJ | bash "$ENGINE" pretool >/dev/null    # captures baseline + AJ marker
rm -f "$BDIR/s.SUB.basehead"                                           # simulate lost/rolled state
echo "// a gated change exists" >> "$REPO/src/foo.go"
[ "$( cd "$REPO" && stopa SUB AJ | bash "$ENGINE" stop | sdecision )" = stop ] \
  && ok "SubagentStop: missing baseline => allow (no session-wide contamination fallback)" || bad "basehead-missing fallback contaminates"
git -C "$REPO" checkout -q -- . 2>/dev/null; git -C "$REPO" clean -fdq 2>/dev/null; rm -rf "$BDIR"
# 11k. CHALLENGE FIX: NUL-safe exact attribution — a subagent that touched a newline-
#      containing path is NOT cross-blamed when a sibling file whose name is a line-fragment
#      of it changes (the old grep -Fxq split the multi-line pattern and false-blocked).
nlpath=$'src/a\nb.go'
printf 'package x\n' > "$REPO/$nlpath"; printf 'package a\n' > "$REPO/src/a"
git -C "$REPO" add -A; git -C "$REPO" commit -qm nlfiles
jq -nc --arg fp "$REPO/$nlpath" '{tool_name:"Edit",tool_input:{file_path:$fp},session_id:"SUB",agent_id:"AK"}' \
  | bash "$ENGINE" pretool >/dev/null                                  # AK touched the newline path; not changed
echo "// only the line-fragment sibling changes" >> "$REPO/src/a"      # src/a (a line-fragment) changes
[ "$( cd "$REPO" && stopa SUB AK | bash "$ENGINE" stop | sdecision )" = stop ] \
  && ok "SubagentStop: newline-path touch not cross-blamed for sibling 'src/a' (NUL exact match)" || bad "newline-path line-fragment cross-attribution"
git -C "$REPO" checkout -q -- . 2>/dev/null; git -C "$REPO" clean -fdq 2>/dev/null; rm -rf "$BDIR"
# 11m. CHALLENGE FIX (id collision): two agent_ids that the lossy sid_safe would collapse to
#      the same key ("a/b" and "a:b" -> "a_b") get DISTINCT injective (percent-encoded)
#      markers, so their .touched/.blocked/.waiver never collide.
edita "$REPO/src/foo.go" SUB 'a/b' | bash "$ENGINE" pretool >/dev/null
[ -r "$BDIR/s.SUB.a.$(akey 'a/b').touched" ] && [ ! -e "$BDIR/s.SUB.a.$(akey 'a:b').touched" ] && [ "$(akey 'a/b')" != "$(akey 'a:b')" ] \
  && ok "agent_id key is injective ('a/b' ≠ 'a:b'; no marker collision)" || bad "agent_id key collision (lossy sid_safe)"
git -C "$REPO" checkout -q -- . 2>/dev/null; rm -rf "$BDIR"
# 11n. CHALLENGE FIX (concurrency): O_APPEND per-agent .touched does not lose entries when
#      the same subagent's PreToolUse fires in parallel (model emitting parallel Edits);
#      the old read-copy-rename dropped entries and could silently miss the real changed path.
for i in $(seq 1 20); do echo "package p" > "$REPO/src/c$i.go"; done
git -C "$REPO" add -A; git -C "$REPO" commit -qm cfiles
edita "$REPO/src/c1.go" SUB CC | bash "$ENGINE" pretool >/dev/null      # serial: capture baseline once
for i in $(seq 1 20); do edita "$REPO/src/c$i.go" SUB CC | bash "$ENGINE" pretool >/dev/null & done; wait
n=$(tr -cd '\0' < "$BDIR/s.SUB.a.$(akey CC).touched" 2>/dev/null | wc -c | tr -d ' ')
[ "${n:-0}" -ge 20 ] && ok "concurrent same-agent edits: all touched entries survive ($n, O_APPEND)" || bad "lost touched entries under concurrency: ${n:-0}/20"
git -C "$REPO" checkout -q -- . 2>/dev/null; git -C "$REPO" clean -fdq 2>/dev/null; rm -rf "$BDIR"

# ============================================================================
# INVOCATION EVIDENCE (name != invoke) — cross-check recorded owners against the
# skills actually invoked in the session transcript (backlog gate ⑥).
# ============================================================================
# Synthetic transcript: one JSONL line per invoked skill (matches the real format:
# message.content[] tool_use blocks with name=="Skill", input.skill=="plugin:name").
mktr() { # $1 out-file  rest: skill invocations (plugin:name or bare)
  local out="$1"; shift; : > "$out"
  printf 'malformed leading line not json\n' > "$out"    # BEFORE skills: must not truncate the stream
  local s
  for s in "$@"; do
    printf '{"type":"assistant","message":{"content":[{"type":"tool_use","name":"Skill","input":{"skill":"%s"}}]}}\n' "$s" >> "$out"
  done
  # a non-Skill line + a malformed line to prove tolerance
  printf '{"type":"user","message":{"content":[{"type":"tool_use","name":"Bash","input":{"command":"ls"}}]}}\n' >> "$out"
  printf 'not json at all\n' >> "$out"
}
stopjt(){ printf '{"session_id":"%s","transcript_path":"%s"}' "$1" "$2"; }
stopjat(){
  printf '{"session_id":"%s","agent_id":"%s","transcript_path":"%s","agent_transcript_path":"%s"}' \
    "$1" "$2" "$3" "$4"
}
stopja_legacy(){ printf '{"session_id":"%s","agent_id":"%s","transcript_path":"%s"}' "$1" "$2" "$3"; }

TR="$BDIR.transcript.jsonl"; mkdir -p "$(dirname "$TR")"

# VI-1: subcommand — an invoked skill-shaped owner passes (exit 0).
mktr "$TR" "ccl-skills:testing-strategy" "ccl-skills:worktree-isolation"
bash "$ENGINE" verify-invocations --owners "testing-strategy,worktree-isolation" --transcript "$TR" >/dev/null
[ $? -eq 0 ] && ok "verify-invocations: all invoked => exit 0" || bad "VI-1"

# VI-2: subcommand — a skill-shaped owner never invoked => exit 3 and is named.
out=$(bash "$ENGINE" verify-invocations --owners "testing-strategy,go-microservice-dev" --transcript "$TR"); rc=$?
[ "$rc" = 3 ] && printf '%s' "$out" | grep -q 'go-microservice-dev' \
  && ! printf '%s' "$out" | grep -q 'testing-strategy' \
  && ok "verify-invocations: un-invoked owner flagged (exit 3)" || bad "VI-2" "rc=$rc out=$out"

# VI-3: no transcript => unverifiable => fail-open exit 0.
bash "$ENGINE" verify-invocations --owners "anything" --transcript "$BDIR/nope.jsonl" >/dev/null
[ $? -eq 0 ] && ok "verify-invocations: no transcript => fail-open exit 0" || bad "VI-3"

# VI-4: free-text (non-skill-shaped) owner never flags, even when absent.
out=$(bash "$ENGINE" verify-invocations --owners "then the touched owner" --transcript "$TR"); rc=$?
[ "$rc" = 0 ] && ok "verify-invocations: free-text owner never flags" || bad "VI-4" "rc=$rc out=$out"

# --- Stop-hook wiring: the reliable firing point (transcript_path on stdin) ---
git -C "$REPO" checkout -q -- . 2>/dev/null; git -C "$REPO" clean -fdq 2>/dev/null; rm -rf "$BDIR"
echo "package x" > "$REPO/src/foo.go"; git -C "$REPO" add -A; git -C "$REPO" commit -qm reset

# VI-5: boundary recorded with an owner that was NEVER invoked + activity + transcript => Stop BLOCKS.
rm -f "$BDIR/boundary.json"
edit "$REPO/src/foo.go" SV1 | bash "$ENGINE" pretool >/dev/null          # capture baseline
echo "package x // SV1 change" > "$REPO/src/foo.go"          # real post-baseline gated change
( cd "$REPO" && bash "$ENGINE" record --owners "testing-strategy,go-microservice-dev" >/dev/null )
mktr "$TR" "ccl-skills:testing-strategy"                             # only testing-strategy invoked
d=$( cd "$REPO" && stopjt SV1 "$TR" | bash "$ENGINE" stop | sdecision )
[ "$d" = block ] && ok "Stop: recorded owner never invoked => block (name≠invoke)" || bad "VI-5 expected block, got $d"

# VI-6: fresh boundary, transcript shows BOTH owners invoked => Stop allows.
rm -f "$BDIR/boundary.json"
edit "$REPO/src/foo.go" SV2 | bash "$ENGINE" pretool >/dev/null
echo "package x // SV2 change" > "$REPO/src/foo.go"
( cd "$REPO" && bash "$ENGINE" record --owners "testing-strategy,go-microservice-dev" >/dev/null )
mktr "$TR" "ccl-skills:testing-strategy" "ccl-skills:go-microservice-dev"
d=$( cd "$REPO" && stopjt SV2 "$TR" | bash "$ENGINE" stop | sdecision )
[ "$d" = stop ] && ok "Stop: all recorded owners invoked => allow" || bad "VI-6 expected allow, got $d"

# VI-7: boundary recorded, NO transcript_path on stdin => fail-open allow.
rm -f "$BDIR/boundary.json"
edit "$REPO/src/foo.go" SV3 | bash "$ENGINE" pretool >/dev/null
( cd "$REPO" && bash "$ENGINE" record --owners "go-microservice-dev" >/dev/null )
d=$( cd "$REPO" && stopj SV3 | bash "$ENGINE" stop | sdecision )
[ "$d" = stop ] && ok "Stop: boundary recorded but no transcript => fail-open allow" || bad "VI-7 expected allow, got $d"

# VI-8: block fires AT MOST ONCE per actor (same safety as the boundary-missing block).
rm -f "$BDIR/boundary.json"
edit "$REPO/src/foo.go" SV4 | bash "$ENGINE" pretool >/dev/null
echo "package x // SV4 change" > "$REPO/src/foo.go"
( cd "$REPO" && bash "$ENGINE" record --owners "go-microservice-dev" >/dev/null )
mktr "$TR" "ccl-skills:testing-strategy"
d1=$( cd "$REPO" && stopjt SV4 "$TR" | bash "$ENGINE" stop | sdecision )
d2=$( cd "$REPO" && stopjt SV4 "$TR" | bash "$ENGINE" stop | sdecision )
[ "$d1" = block ] && [ "$d2" = stop ] && ok "Stop invocation-block fires at most once per actor" || bad "VI-8 d1=$d1 d2=$d2"
# VI-9: boundary + un-invoked owner but the actor made NO actual gated change this session
#       (edit then revert to baseline) => Stop must NOT block (no-trap safety preserved).
rm -f "$BDIR/boundary.json"
edit "$REPO/src/foo.go" SV5 | bash "$ENGINE" pretool >/dev/null            # .touched activity...
git -C "$REPO" checkout -q -- src/foo.go                                    # ...but reverted (no real change)
( cd "$REPO" && bash "$ENGINE" record --owners "go-microservice-dev" >/dev/null )
mktr "$TR" "ccl-skills:testing-strategy"                                # go-microservice-dev un-invoked
d=$( cd "$REPO" && stopjt SV5 "$TR" | bash "$ENGINE" stop | sdecision )
[ "$d" = stop ] && ok "Stop: un-invoked owner but NO actual gated change => allow (no-trap)" || bad "VI-9 expected allow, got $d"

# VI-10: transcript with NO Skill invocations at all (empty invoked set) => unverifiable =>
#        fail-open, never flag every owner.
: > "$TR"; printf '{"message":{"content":[{"type":"tool_use","name":"Bash","input":{"command":"ls"}}]}}\n' > "$TR"
printf 'garbage line\n' >> "$TR"
out=$(bash "$ENGINE" verify-invocations --owners "go-microservice-dev,testing-strategy" --transcript "$TR"); rc=$?
[ "$rc" = 0 ] && ok "verify-invocations: empty invoked set => fail-open (no flags)" || bad "VI-10" "rc=$rc out=$out"

# VI-11 (challenge R1): owner recorded in FULL "ccl-skills:foo" form still matches the
#        invoked base name (prefix normalized on both sides).
mktr "$TR" "ccl-skills:go-microservice-dev"
bash "$ENGINE" verify-invocations --owners "ccl-skills:go-microservice-dev" --transcript "$TR" >/dev/null
[ $? -eq 0 ] && ok "verify-invocations: full ccl-skills:owner matches invoked base" || bad "VI-11"

# VI-12 (challenge R1): a same-named skill from an UNTRUSTED plugin does NOT satisfy a
#        CCL owner (only ccl-skills: prefix is stripped for base matching).
: > "$TR"; printf '{"type":"assistant","message":{"content":[{"type":"tool_use","name":"Skill","input":{"skill":"evil-plugin:go-microservice-dev"}}]}}\n' > "$TR"
out=$(bash "$ENGINE" verify-invocations --owners "go-microservice-dev" --transcript "$TR"); rc=$?
[ "$rc" = 3 ] && printf '%s' "$out" | grep -q 'go-microservice-dev' \
  && ok "verify-invocations: untrusted-plugin same-name does NOT satisfy CCL owner" || bad "VI-12" "rc=$rc out=$out"

# VI-13 (challenge R1): a malformed Skill.input.skill (non-string) BEFORE a valid invocation
#        must not abort the stream — the valid invocation is still found (strings guard).
: > "$TR"
printf '{"type":"assistant","message":{"content":[{"type":"tool_use","name":"Skill","input":{"skill":123}}]}}\n' > "$TR"
printf '{"type":"assistant","message":{"content":[{"type":"tool_use","name":"Skill","input":{"skill":"ccl-skills:go-microservice-dev"}}]}}\n' >> "$TR"
bash "$ENGINE" verify-invocations --owners "go-microservice-dev" --transcript "$TR" >/dev/null
[ $? -eq 0 ] && ok "verify-invocations: non-string skill value skipped, later valid one found" || bad "VI-13"

# VI-14 (challenge R2): a Skill tool_use block in a NON-assistant (user-role) event must
#        not count as a real invocation (spoof resistance). A real assistant invocation is
#        present so the set is non-empty (not the fail-open path).
: > "$TR"
printf '{"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","name":"Skill","input":{"skill":"ccl-skills:testing-strategy"}}]}}\n' > "$TR"
printf '{"type":"user","message":{"role":"user","content":[{"type":"tool_use","name":"Skill","input":{"skill":"ccl-skills:go-microservice-dev"}}]}}\n' >> "$TR"
out=$(bash "$ENGINE" verify-invocations --owners "go-microservice-dev,testing-strategy" --transcript "$TR"); rc=$?
[ "$rc" = 3 ] && printf '%s' "$out" | grep -q 'go-microservice-dev' \
  && ! printf '%s' "$out" | grep -q 'testing-strategy' \
  && ok "verify-invocations: non-assistant Skill block does not satisfy owner" || bad "VI-14" "rc=$rc out=$out"

# VI-15 (challenge R2): PROACTIVE record — owners recorded BEFORE any edit, then a real
#        gated change, then Stop with a transcript missing an owner => still BLOCKS (the
#        pretool now captures the activity marker even under a valid boundary).
rm -f "$BDIR/boundary.json"
( cd "$REPO" && bash "$ENGINE" record --owners "go-microservice-dev" >/dev/null )   # record FIRST
edit "$REPO/src/foo.go" SV6 | bash "$ENGINE" pretool >/dev/null                     # THEN edit (marker captured despite valid boundary)
echo "package x // SV6 change" > "$REPO/src/foo.go"                                 # real gated change
mktr "$TR" "ccl-skills:testing-strategy"                                        # go-microservice-dev un-invoked
d=$( cd "$REPO" && stopjt SV6 "$TR" | bash "$ENGINE" stop | sdecision )
[ "$d" = block ] && ok "Stop: proactive-record path still caught (marker captured under valid boundary)" || bad "VI-15 expected block, got $d"

# VI-16: SubagentStop must inspect the WORKER transcript. Claude supplies the main
#        session transcript in transcript_path and the worker's own evidence in
#        agent_transcript_path. A skill loaded only by the controller cannot satisfy the worker.
git -C "$REPO" checkout -q -- . 2>/dev/null; git -C "$REPO" clean -fdq 2>/dev/null; rm -rf "$BDIR"
MAIN_TR="$BDIR.main.jsonl"; AGENT_TR="$BDIR.agent.jsonl"
edita "$REPO/src/foo.go" SV7 W7 | bash "$ENGINE" pretool >/dev/null
echo "package x // SV7 worker change" > "$REPO/src/foo.go"
( cd "$REPO" && bash "$ENGINE" record --owners "go-microservice-dev" >/dev/null )
mktr "$MAIN_TR" "ccl-skills:go-microservice-dev"    # controller loaded it
mktr "$AGENT_TR" "ccl-skills:testing-strategy"      # worker did not
d=$( cd "$REPO" && stopjat SV7 W7 "$MAIN_TR" "$AGENT_TR" | bash "$ENGINE" stop | sdecision )
[ "$d" = block ] && ok "SubagentStop: worker transcript wins over main transcript" || bad "VI-16 expected block, got $d"

# VI-17: a worker transcript with a verifiable tool-event shape but ZERO Skill invocations is evidence
#        of a cold worker, not transcript-format drift. Continue that worker once.
git -C "$REPO" checkout -q -- . 2>/dev/null; rm -rf "$BDIR"
edita "$REPO/src/foo.go" SV8 W8 | bash "$ENGINE" pretool >/dev/null
echo "package x // SV8 worker change" > "$REPO/src/foo.go"
( cd "$REPO" && bash "$ENGINE" record --owners "go-microservice-dev" >/dev/null )
mktr "$MAIN_TR" "ccl-skills:go-microservice-dev"
printf '{"type":"assistant","message":{"content":[{"type":"tool_use","name":"Bash","input":{"command":"go test ./..."}}]}}\n' > "$AGENT_TR"
d=$( cd "$REPO" && stopjat SV8 W8 "$MAIN_TR" "$AGENT_TR" | bash "$ENGINE" stop | sdecision )
[ "$d" = block ] && ok "SubagentStop: zero worker Skill invocations => block once" || bad "VI-17 expected block, got $d"

# VI-18/19: the standalone verifier exposes the same strict worker mode for host
#          adapters, while malformed-only evidence remains fail-open.
out=$(bash "$ENGINE" verify-invocations --owners "go-microservice-dev" --transcript "$AGENT_TR" --empty-is-missing); rc=$?
[ "$rc" = 3 ] && printf '%s' "$out" | grep -q 'go-microservice-dev' \
  && ok "verify-invocations: strict empty set flags required skill" || bad "VI-18" "rc=$rc out=$out"
printf 'not json\nstill not json\n' > "$AGENT_TR"
out=$(bash "$ENGINE" verify-invocations --owners "go-microservice-dev" --transcript "$AGENT_TR" --empty-is-missing); rc=$?
[ "$rc" = 0 ] && ok "verify-invocations: malformed-only transcript stays fail-open" || bad "VI-19" "rc=$rc out=$out"

# VI-20: valid JSONL is not enough to prove invocation absence. If the host still emits
#        assistant tool_use events but a Skill block's input shape drifted, strict worker
#        verification must fail open rather than falsely claiming every owner was skipped.
git -C "$REPO" checkout -q -- . 2>/dev/null; rm -rf "$BDIR"
edita "$REPO/src/foo.go" SV9 W9 | bash "$ENGINE" pretool >/dev/null
echo "package x // SV9 worker change" > "$REPO/src/foo.go"
( cd "$REPO" && bash "$ENGINE" record --owners "go-microservice-dev" >/dev/null )
printf '{"type":"assistant","message":{"content":[{"type":"tool_use","name":"Skill","input":{"arguments":{"skill":"ccl-skills:go-microservice-dev"}}},{"type":"tool_use","name":"Edit","input":{"file_path":"src/foo.go"}}]}}\n' > "$AGENT_TR"
d=$( cd "$REPO" && stopjat SV9 W9 "$MAIN_TR" "$AGENT_TR" | bash "$ENGINE" stop | sdecision )
[ "$d" = stop ] && ok "SubagentStop: drifted Skill event shape stays fail-open" || bad "VI-20 expected allow, got $d"

# VI-21: an older host may omit agent_transcript_path. The main transcript fallback is
#        orientation only and must retain legacy empty-set fail-open behavior; otherwise a
#        controller with no Skill calls is falsely attributed to the worker.
git -C "$REPO" checkout -q -- . 2>/dev/null; rm -rf "$BDIR"
edita "$REPO/src/foo.go" SV10 W10 | bash "$ENGINE" pretool >/dev/null
echo "package x // SV10 worker change" > "$REPO/src/foo.go"
( cd "$REPO" && bash "$ENGINE" record --owners "go-microservice-dev" >/dev/null )
printf '{"type":"assistant","message":{"content":[{"type":"tool_use","name":"Bash","input":{"command":"git status"}}]}}\n' > "$MAIN_TR"
d=$( cd "$REPO" && stopja_legacy SV10 W10 "$MAIN_TR" | bash "$ENGINE" stop | sdecision )
[ "$d" = stop ] && ok "SubagentStop: legacy main-transcript fallback keeps empty-set fail-open" || bad "VI-21 expected allow, got $d"

git -C "$REPO" checkout -q -- . 2>/dev/null; git -C "$REPO" clean -fdq 2>/dev/null; rm -rf "$BDIR" "$TR" "$MAIN_TR" "$AGENT_TR"

# ---- WORKTREE DIMENSION (issue #5) -------------------------------------------
# Every fixture above builds a PLAIN repo, so none of them can cross the axis where
# this gate actually runs: `worktree-isolation` mandates developing in a linked
# worktree, while the Stop hook resolves its repo from $PWD — which the harness
# routinely resets back to the main checkout. Keying boundary state on
# `--absolute-git-dir` puts the write in `.git/worktrees/<name>/` and the read in
# `.git/`, so the gate reports "never recorded" on the repo's OWN standard workflow
# and then trains everyone to ignore it. These probes pin read/write agreement
# across that boundary; without the fix W1 fails.
echo "--- worktree dimension ---"
WT="$WORK/prod-wt"
if git -C "$REPO" worktree add -q -b od-wt "$WT" >/dev/null 2>&1; then
  # W1: record INSIDE the worktree must be visible FROM the main checkout.
  rm -rf "$BDIR"
  ( cd "$WT" && bash "$ENGINE" record --owners "product-rd-workflow" >/dev/null )
  main_state=$(bash "$ENGINE" boundary-path "$REPO" 2>/dev/null)
  wt_state=$(bash "$ENGINE" boundary-path "$WT" 2>/dev/null)
  [ -n "$main_state" ] && [ "$main_state" = "$wt_state" ] \
    && ok "worktree: boundary path is identical from the worktree and the main checkout" \
    || bad "W1a: boundary path differs across worktrees" "main=$main_state wt=$wt_state"
  [ -r "$main_state/boundary.json" ] \
    && ok "worktree: a boundary recorded in the worktree is readable from the main checkout" \
    || bad "W1: record-in-worktree is invisible from the main checkout (issue #5)" "looked in $main_state"

  # W2: the shared path must be ABSOLUTE. `--git-common-dir` returns a RELATIVE
  #     `.git` when asked from the main checkout, so a naive swap would make the
  #     state dir depend on the caller's cwd — the same class of bug, re-introduced.
  case "$main_state" in
    /*) ok "worktree: boundary path is absolute from the main checkout (cwd-independent)" ;;
    *)  bad "W2: boundary path is relative => cwd-dependent state dir" "got=$main_state" ;;
  esac

  # W3: the gate itself must be satisfied — record in the worktree, Stop in the main
  #     checkout (exactly the shape the standard workflow produces).
  rm -rf "$BDIR"
  edit "$REPO/src/foo.go" SW1 | bash "$ENGINE" pretool >/dev/null
  echo "package x // SW1" > "$REPO/src/foo.go"
  ( cd "$WT" && bash "$ENGINE" record --owners "product-rd-workflow" >/dev/null )
  d=$( cd "$REPO" && stopj SW1 | bash "$ENGINE" stop | sdecision )
  [ "$d" = stop ] && ok "worktree: record-in-worktree satisfies a Stop resolved in the main checkout" \
    || bad "W3: Stop still blocks after a worktree record (issue #5 end-to-end)" "got $d"

  # W6: OLD GIT. `--path-format=absolute` needs git >= 2.31; without it the fallback
  #     builds the path itself, and that branch answers a LOGICAL path while git answers
  #     a PHYSICAL one. On a symlinked root (macOS /var -> /private/var, i.e. mktemp)
  #     the two disagree and the split returns — on exactly the hosts that cannot take
  #     the fast path. Shim git to reject the flag so the fallback is what runs.
  REALGIT=$(command -v git)
  SHIM="$WORK/shim"; mkdir -p "$SHIM"
  cat > "$SHIM/git" <<SH
#!/bin/sh
for a in "\$@"; do
  [ "\$a" = "--path-format=absolute" ] && { echo "error: unknown option \\\`path-format=absolute'" >&2; exit 129; }
done
exec "$REALGIT" "\$@"
SH
  chmod +x "$SHIM/git"
  old_main=$(PATH="$SHIM:$PATH" bash "$ENGINE" boundary-path "$REPO" 2>/dev/null)
  old_wt=$(PATH="$SHIM:$PATH" bash "$ENGINE" boundary-path "$WT" 2>/dev/null)
  [ -n "$old_main" ] && [ "$old_main" = "$old_wt" ] \
    && ok "worktree: path agrees across worktrees on git without --path-format (>=2.31 fallback)" \
    || bad "W6: fallback path differs across worktrees on old git" "main=$old_main wt=$old_wt"
  case "$old_main" in
    /*) ok "worktree: fallback path is absolute too" ;;
    *)  bad "W6b: fallback produced a relative path" "got=$old_main" ;;
  esac
  rm -rf "$SHIM"

  # W4: the recording worktree is REMOVED — the normal end of a delivery, since
  #     worktree-isolation says clean up the moment it is integrated. A boundary keyed
  #     on the worktree PATH cannot survive this (the path is gone and `git -C` on it
  #     fails), which is why identity is keyed on the common git dir instead.
  rm -rf "$BDIR"
  ( cd "$WT" && bash "$ENGINE" record --owners "product-rd-workflow" >/dev/null )
  git -C "$REPO" worktree remove --force "$WT" >/dev/null 2>&1
  [ -d "$WT" ] && bad "W4 fixture: worktree not actually removed" "$WT still exists"
  [ "$(cd "$REPO" && bash "$ENGINE" status | sed -n 's/^boundary: *//p')" = valid ] \
    && ok "worktree: boundary survives cleanup of the worktree that recorded it" \
    || bad "W4: boundary lost once the recording worktree was removed" "status=$(cd "$REPO" && bash "$ENGINE" status | sed -n 's/^boundary: *//p')"

  # W5: NEGATIVE — repository identity still has teeth. The path equality this change
  #     replaced was there to reject a boundary belonging to somewhere else; a boundary
  #     naming a DIFFERENT repo's git dir must still be refused, or the fix would have
  #     been a deletion wearing a replacement's clothes.
  OTHER="$WORK/other"; mkdir -p "$OTHER"
  git -C "$OTHER" init -q; git -C "$OTHER" config user.email t@t; git -C "$OTHER" config user.name t
  git -C "$OTHER" commit -q --allow-empty -m init
  other_gd=$(bash "$ENGINE" boundary-path "$OTHER")
  jq --arg gd "$other_gd" '.repo_git_dir=$gd' "$BDIR/boundary.json" > "$BDIR/boundary.json.tmp" \
    && mv "$BDIR/boundary.json.tmp" "$BDIR/boundary.json"
  [ "$(cd "$REPO" && bash "$ENGINE" status | sed -n 's/^boundary: *//p')" = absent ] \
    && ok "worktree: a boundary naming another repository is still refused" \
    || bad "W5: foreign-repo boundary accepted — identity check lost its teeth" "status=$(cd "$REPO" && bash "$ENGINE" status | sed -n 's/^boundary: *//p')"
  rm -rf "$OTHER"

  git -C "$REPO" checkout -q -- . 2>/dev/null
  git -C "$REPO" branch -qD od-wt >/dev/null 2>&1
  rm -rf "$BDIR"
else
  bad "W0: could not create a linked worktree — the worktree dimension went untested" "git worktree add failed"
fi

echo "---"; echo "PASS=$PASS FAIL=$FAIL"; [ "$FAIL" -eq 0 ]
