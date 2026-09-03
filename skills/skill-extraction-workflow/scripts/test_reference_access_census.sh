#!/usr/bin/env bash
# Regression for reference-access-census.sh: synthetic transcripts only, no
# host logs are read. Proves (1) per-file session counts and the touching
# denominator, (2) the unevaluated sentinel when no transcript exists (never a
# zero table), (3) the privacy contract — output carries no transcript text,
# no absolute log path, no session id, (4) usage errors exit 2, and (5) the
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

run() { bash "$CENSUS" --repo-root "$REPO" --skill demo-skill --days 30 --logs "$LOGS,$TMP/logs-codex"; }
out="$(run)" || fail "census exited non-zero on a valid fixture"

# (1) counts and denominator
printf '%s\n' "$out" | grep -qF 'transcripts=4 sessions_touching_package=3' || fail "denominator wrong:\n$out"
printf '%s\n' "$out" | grep -qE '^references/alpha\.md \| 2 \|' || fail "alpha should count 2 sessions (codex double-mention counts once):\n$out"
printf '%s\n' "$out" | grep -qE '^references/beta\.md \| 1 \|' || fail "beta should count 1 session:\n$out"
printf '%s\n' "$out" | grep -qE '^references/gamma\.md \| 0 \| - \| 0%' || fail "gamma should count 0 with no date:\n$out"
printf '%s\n' "$out" | grep -qE '^SKILL\.md \| 1 \|' || fail "SKILL.md should count 1 session:\n$out"
[ "$(printf '%s\n' "$out" | tail -1)" = "reference_access_census_ok" ] || fail "last token must be the ok marker"

# (3) privacy contract
printf '%s\n' "$out" | grep -qF "$SECRET_PROMPT" && fail "transcript text leaked into census output"
printf '%s\n' "$out" | grep -qF "$SESSION_ID" && fail "session id leaked into census output"
printf '%s\n' "$out" | grep -qF "$LOGS" && fail "absolute log path leaked into census output"
printf '%s\n' "$out" | grep -qF "/abs/checkout" && fail "absolute checkout path leaked into census output"

# (2) unevaluated sentinel: no transcripts at all
EMPTY="$TMP/empty-logs"; mkdir -p "$EMPTY"
eout="$(bash "$CENSUS" --repo-root "$REPO" --skill demo-skill --days 30 --logs "$EMPTY")" || fail "empty-log run must exit 0"
[ "$(printf '%s\n' "$eout" | tail -1)" = "reference_access_census_unevaluated: no transcripts under $EMPTY within 30 days" ] || fail "missing unevaluated sentinel:\n$eout"
printf '%s\n' "$eout" | grep -qE '\| 0 \|' && fail "an unevaluated run must not print a zero table"

# (4) usage errors exit 2
if bash "$CENSUS" --repo-root "$REPO" --skill no-such-skill --logs "$LOGS" >/dev/null 2>&1; then fail "unknown skill must exit 2"; fi
bash "$CENSUS" --repo-root "$REPO" --skill no-such-skill --logs "$LOGS" >/dev/null 2>&1 || [ $? -eq 2 ] || fail "unknown skill must exit 2 exactly"
bash "$CENSUS" --repo-root "$REPO" --skill demo-skill --days abc --logs "$LOGS" >/dev/null 2>&1 || [ $? -eq 2 ] || fail "non-integer --days must exit 2"

# (5) ARG_MAX regression: 450 transcripts (> one xargs batch of 200), 3 of which touch gamma
BIG="$TMP/logs-big"; mkdir -p "$BIG"
for i in $(seq 1 450); do printf '{"cmd":"noise %s"}\n' "$i" > "$BIG/s$i.jsonl"; done
for i in 7 208 449; do printf '{"cmd":"cat skills/demo-skill/references/gamma.md"}\n' > "$BIG/s$i.jsonl"; done
bout="$(bash "$CENSUS" --repo-root "$REPO" --skill demo-skill --days 30 --logs "$BIG")" || fail "big run exited non-zero"
printf '%s\n' "$bout" | grep -qF 'transcripts=450 sessions_touching_package=3' || fail "large candidate set miscounted (ARG_MAX regression):\n$bout"
printf '%s\n' "$bout" | grep -qE '^references/gamma\.md \| 3 \|' || fail "gamma should count 3 across xargs batches:\n$bout"

echo "test_reference_access_census_ok"
