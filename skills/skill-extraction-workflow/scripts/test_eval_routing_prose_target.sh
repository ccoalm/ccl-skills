#!/usr/bin/env bash
# Regression test for the prose_redirect_target ADVISORY in eval-routing.rb.
#
# A Skip redirect that names an "owner"/"reviewer" but resolves to no backticked
# installed skill is an unresolvable prose dead-end — the exact class that let
# grill-me's "→ the adversarial or delete-code review owner" slip past the gate
# (the arrow regex captured bare "the" and dropped it as generic English). The
# finding is ADVISORY: reported, NEVER blocks.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd -P)"
EVAL="$SCRIPT_DIR/eval-routing.rb"
[ -f "$EVAL" ] || { echo "FAIL: eval-routing.rb not found: $EVAL" >&2; exit 1; }
command -v ruby >/dev/null 2>&1 || { echo "test_eval_routing_prose_target: SKIP (ruby unavailable)"; exit 0; }

TMP="$(mktemp -d "${TMPDIR:-/tmp}/proseadv.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
fail() { echo "FAIL: $*" >&2; exit 1; }

# A resolvable owner: the clause carries a backticked installed skill -> must NOT fire.
mkdir -p "$TMP/skills/resolvable"
cat > "$TMP/skills/resolvable/SKILL.md" <<'EOF'
---
name: resolvable
description: resolvable / aaa — fixture. Skip code review → `dead-end`'s review owner; done.
---
body
EOF

# The dead-end: prose owner, no backticked skill -> MUST fire.
mkdir -p "$TMP/skills/dead-end"
cat > "$TMP/skills/dead-end/SKILL.md" <<'EOF'
---
name: dead-end
description: dead-end / bbb — fixture. Skip code review → the adversarial or delete-code review owner; tests → testing.
---
body
EOF

# A generic non-owner bare redirect (no owner/reviewer noun) -> must NOT fire.
mkdir -p "$TMP/skills/generic"
cat > "$TMP/skills/generic/SKILL.md" <<'EOF'
---
name: generic
description: generic / ccc — fixture. Skip implementation → the relevant stack/dev skill; done.
---
body
EOF

# A CHAINED redirect: a prose owner FOLLOWED by a second arrow to a backticked
# skill. The clause must stop at the second arrow, so the prose dead-end still
# fires (a later backticked skill must not suppress an earlier prose target).
mkdir -p "$TMP/skills/chained"
cat > "$TMP/skills/chained/SKILL.md" <<'EOF'
---
name: chained
description: chained / ddd — fixture. Skip review → the review owner → `dead-end`; done.
---
body
EOF

JSON="$TMP/out.json"
set +e
out="$(ruby "$EVAL" "$TMP" --json "$JSON" 2>&1)"; rc=$?
set -e

# (1) Advisory NEVER blocks.
[ "$rc" -eq 0 ] || fail "prose advisory must not block (rc=$rc)\n$out"
[ -f "$JSON" ] || fail "no JSON report written\n$out"

# (2) Fires for the dead-end skill.
grep -q '"type": "prose_redirect_target"' "$JSON" || fail "expected a prose_redirect_target finding\n$(cat "$JSON")"
grep -q 'dead-end skip redirect' "$JSON" || fail "dead-end skill not named in the finding\n$(cat "$JSON")"

# (3) Fires for the CHAINED prose owner even though a later arrow points at a
# backticked skill (the clause must stop at the second arrow).
grep -q 'chained skip redirect' "$JSON" || fail "chained prose dead-end not flagged (clause spilled past the next arrow?)\n$(cat "$JSON")"

# (4) No false positive on the backticked-resolvable owner or the generic
# non-owner redirect. Grep the whole report for each skill's detail text — in
# pretty JSON "type" and "detail" are on SEPARATE lines, so a naive
# `grep type | grep detail` would be vacuous and always pass.
grep -q '"resolvable skip redirect' "$JSON" && fail "false positive: backticked-resolvable owner flagged\n$(cat "$JSON")"
grep -q '"generic skip redirect' "$JSON" && fail "false positive: generic non-owner redirect flagged\n$(cat "$JSON")"

echo "test_eval_routing_prose_target: ok"
