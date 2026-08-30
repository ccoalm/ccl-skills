#!/usr/bin/env bash
# Regression: validate-skill.sh must flag a DANGLING cross-package markdown
# reference (`<pkg>/references/...`) when the sibling package exists but the
# target file does not — a renamed/deleted canonical reference must not leave
# sibling skills pointing at nothing while every gate stays green (observed:
# the 安全 4 问 canonical convergence put five cross-package pointers into four
# skills with no existence check anywhere).
#
# Recall limit pinned here too: a cross-package path whose package directory
# does NOT exist is skipped (it may point outside the skills tree), and a
# backticked in-package `references/...` keeps the existing behavior.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd -P)"
VALIDATE="$SCRIPT_DIR/validate-skill.sh"
[ -f "$VALIDATE" ] || { echo "FAIL: validate script not found: $VALIDATE" >&2; exit 1; }

fail() { echo "FAIL: $*" >&2; exit 1; }

TMP="$(mktemp -d "${TMPDIR:-/tmp}/valxref.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/skills/skill-a" "$TMP/skills/skill-b/references"

cat > "$TMP/skills/skill-a/SKILL.md" <<'EOF'
---
name: skill-a
description: fixture skill for the cross-package reference regression test.
---

Body references the sibling canonical: `skill-b/references/ok.md` and the
sibling missing file: `skill-b/references/missing.md`.
EOF
cat > "$TMP/skills/skill-b/SKILL.md" <<'EOF'
---
name: skill-b
description: fixture owner skill for the cross-package reference regression test.
---

Owner body.
EOF
cat > "$TMP/skills/skill-b/references/ok.md" <<'EOF'
# ok
EOF

# (1) Dangling cross-package reference inside an existing sibling package => flagged.
set +e
out="$(bash "$VALIDATE" "$TMP/skills/skill-a" 2>&1)"; rc=$?
set -e
[ "$rc" -ne 0 ] || fail "dangling cross-package reference must fail validation:\n$out"
case "$out" in
  *missing_markdown_references*skill-b/references/missing.md*) ;;
  *) fail "dangling cross-package reference not reported as missing:\n$out" ;;
esac

# (2) Existing cross-package reference => passes.
cat > "$TMP/skills/skill-a/SKILL.md" <<'EOF'
---
name: skill-a
description: fixture skill for the cross-package reference regression test.
---

Body references only the existing sibling file: `skill-b/references/ok.md`.
EOF
set +e
out="$(bash "$VALIDATE" "$TMP/skills/skill-a" 2>&1)"; rc=$?
set -e
[ "$rc" -eq 0 ] || fail "existing cross-package reference should pass; rc=$rc\n$out"

# (3) Cross-package path whose package dir is absent => skipped (recall limit).
cat > "$TMP/skills/skill-a/SKILL.md" <<'EOF'
---
name: skill-a
description: fixture skill for the cross-package reference regression test.
---

Body references an outside-tree path: `other-repo/references/anything.md`.
EOF
set +e
out="$(bash "$VALIDATE" "$TMP/skills/skill-a" 2>&1)"; rc=$?
set -e
[ "$rc" -eq 0 ] || fail "absent-package cross path must be skipped, not flagged; rc=$rc\n$out"

# (4) Brace-glob cross-package reference names a set => skipped like `*` patterns.
cat > "$TMP/skills/skill-a/SKILL.md" <<'EOF'
---
name: skill-a
description: fixture skill for the cross-package reference regression test.
---

Body references a sibling set: `skill-b/references/{ok,other}.md`.
EOF
set +e
out="$(bash "$VALIDATE" "$TMP/skills/skill-a" 2>&1)"; rc=$?
set -e
[ "$rc" -eq 0 ] || fail "brace-glob cross-package reference must be skipped; rc=$rc\n$out"

# (5) A relative reference inside references/*.md resolves from that Markdown
# file's directory, matching normal Markdown navigation rather than SKILL root.
mkdir -p "$TMP/skills/skill-a/references"
cat > "$TMP/skills/skill-a/references/nested.md" <<'EOF'
# Nested reference

The sibling canonical is `../../skill-b/references/ok.md`.
EOF
set +e
out="$(bash "$VALIDATE" "$TMP/skills/skill-a" 2>&1)"; rc=$?
set -e
[ "$rc" -eq 0 ] || fail "existing nested relative reference should pass; rc=$rc\n$out"

# (6) The same source-relative rule still rejects a missing target.
cat > "$TMP/skills/skill-a/references/nested.md" <<'EOF'
# Nested reference

The missing sibling file is `../../skill-b/references/missing.md`.
EOF
set +e
out="$(bash "$VALIDATE" "$TMP/skills/skill-a" 2>&1)"; rc=$?
set -e
[ "$rc" -ne 0 ] || fail "dangling nested relative reference must fail validation"
case "$out" in
  *missing_markdown_references*../../skill-b/references/missing.md*) ;;
  *) fail "dangling nested relative reference not reported as missing:\n$out" ;;
esac

rm "$TMP/skills/skill-a/references/nested.md"

# (7) Self-check: the harness can fail (re-run case 1 shape).
cat > "$TMP/skills/skill-a/SKILL.md" <<'EOF'
---
name: skill-a
description: fixture skill for the cross-package reference regression test.
---

Dangling again: `skill-b/references/missing.md`.
EOF
set +e
out="$(bash "$VALIDATE" "$TMP/skills/skill-a" 2>&1)"; rc=$?
set -e
[ "$rc" -ne 0 ] || fail "harness self-check: dangling fixture must be caught"

echo "validate-skill cross-package references: PASS"
