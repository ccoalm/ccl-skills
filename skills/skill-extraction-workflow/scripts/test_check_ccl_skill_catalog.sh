#!/usr/bin/env bash
set -euo pipefail

# Catalog contract gate. docs/SKILLS.md is the single authoritative human catalog,
# and agent-context/session-start.md is the always-on entry routing layer. Nothing
# stops those two from drifting apart on the next skill added, so the gate below is
# the reason the catalog is allowed to exist at all (a hand-maintained skill index
# that can drift is exactly the artifact skill-extraction-workflow forbids).
#
# Cases:
#   c1  a skill missing from the catalog                     => skill_catalog_map_mismatch
#   c2  a "don't use" pointer naming a non-skill             => skill_catalog_dangling_pointer
#   c3  a catalog entry with no "don't use" line             => skill_catalog_missing_skip_line
#   c4  an `entry` skill absent from the routing region      => skill_bootstrap_entry_uncovered
#   c5  the routing region naming a non-skill                => skill_bootstrap_dangling_pointer
#   c6  the pristine tree                                    => passes
#   c7  a catalog with no entry/leaf rows                    => skill_catalog_missing_markers
#   c8  near-miss tokens in a 不用 line (precision)     => must NOT block
#   c9  the routing layer file is absent            => unevaluated, never contract_ok
#   c10 a row whose only clause is a redirect        => skill_catalog_missing_use_line
#   c11 a leaf routed in the always-on layer         => skill_bootstrap_leaf_in_region

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd -P)"
REPO_ROOT="$(git -C "$SCRIPT_DIR" rev-parse --show-toplevel)"
TEST_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/ccl-skill-catalog.XXXXXX")"
trap 'rm -rf "$TEST_ROOT"' EXIT

CASE_INDEX=0

# Each case gets its own clone so a mutation cannot leak into the next one.
new_case() {
  CASE_INDEX=$((CASE_INDEX + 1))
  CASE_DIR="$TEST_ROOT/case$CASE_INDEX"
  git clone --quiet --no-local "$REPO_ROOT" "$CASE_DIR"
  # The clone carries the default branch; copy the working-tree versions of the
  # three files under test so the gate runs against what is about to land.
  cp "$REPO_ROOT/docs/SKILLS.md" "$CASE_DIR/docs/SKILLS.md"
  cp "$REPO_ROOT/agent-context/session-start.md" "$CASE_DIR/agent-context/session-start.md"
  cp "$REPO_ROOT/skills/skill-extraction-workflow/scripts/check-ccl-skills.sh" \
    "$CASE_DIR/skills/skill-extraction-workflow/scripts/check-ccl-skills.sh"
}

run_case() {
  set +e
  CASE_OUTPUT="$(bash "$CASE_DIR/skills/skill-extraction-workflow/scripts/check-ccl-skills.sh" "$CASE_DIR" 2>&1)"
  CASE_STATUS=$?
  set -e
}

expect_block() {
  local label="$1" token="$2"
  [ "$CASE_STATUS" -ne 0 ] || {
    echo "FAIL[$label]: gate passed but should have blocked" >&2
    printf '%s\n' "$CASE_OUTPUT" >&2
    exit 1
  }
  printf '%s\n' "$CASE_OUTPUT" | grep -q "$token" || {
    echo "FAIL[$label]: gate blocked without naming $token" >&2
    printf '%s\n' "$CASE_OUTPUT" >&2
    exit 1
  }
}

# c1 — a skill present in skills/ but absent from the catalog.
new_case
sed -i.bak '/^- `product-rd-workflow`/,+1d' "$CASE_DIR/docs/SKILLS.md"
run_case
expect_block c1 'missing_in_catalog=.*product-rd-workflow'

# c2 — a "don't use" line redirecting to a skill that does not exist. Without this
# the catalog can send a reader to a name nobody owns; the pre-existing
# `extra = mentioned - skills` check could never catch it because `mentioned` was
# already filtered down to real skills, so it was dead code.
new_case
sed -i.bak 's|^\( *- 不用：.*\)`defect-diagnosis`|\1`defect-diagnoser`|' "$CASE_DIR/docs/SKILLS.md"
run_case
expect_block c2 'skill_catalog_dangling_pointer'

# c3 — an entry that says when to use it but never when not to. The "when not to"
# line is the whole point of the catalog: that information already exists in each
# description's Skip clause and was the part humans could not see.
new_case
sed -i.bak '/^- `tighten-doc` `entry`/{n;d;}' "$CASE_DIR/docs/SKILLS.md"
run_case
expect_block c3 'skill_catalog_missing_skip_line'

# c4 — a skill marked `entry` in the catalog but not reachable from the always-on
# routing layer. `leaf` skills are deliberately absent from that layer.
new_case
sed -i.bak 's|\*\*feature-risk-router\*\*|feature-risk-router|' \
  "$CASE_DIR/agent-context/session-start.md"
run_case
expect_block c4 'skill_bootstrap_entry_uncovered'

# c5 — the routing region pointing at a name that is not an installed skill.
new_case
sed -i.bak 's|\*\*tighten-doc\*\*|**tighten-docs**|' \
  "$CASE_DIR/agent-context/session-start.md"
run_case
expect_block c5 'skill_bootstrap_dangling_pointer'

# c6 — the tree as it will land. Guards against a gate that can only ever fail.
new_case
run_case
[ "$CASE_STATUS" -eq 0 ] || {
  echo "FAIL[c6]: pristine tree did not pass" >&2
  printf '%s\n' "$CASE_OUTPUT" >&2
  exit 1
}
printf '%s\n' "$CASE_OUTPUT" | grep -q 'skill_catalog_contract_ok' || {
  echo "FAIL[c6]: pristine tree passed without the contract marker" >&2
  printf '%s\n' "$CASE_OUTPUT" >&2
  exit 1
}

# c7 — a catalog with no entry/leaf rows must BLOCK. There is deliberately no
# legacy fallback: the old loose backtick scan counted a name mentioned in another
# row as coverage, so keeping it as a compatibility branch would preserve exactly
# the hole c1 exists to close, with no owner and no expiry date.
new_case
{
  echo '# Skill Catalog'
  echo
  for skill in "$REPO_ROOT"/skills/*/; do
    echo "- \`$(basename "$skill")\` — legacy one-line entry"
  done
} > "$CASE_DIR/docs/SKILLS.md"
run_case
expect_block c7 'skill_catalog_missing_markers'

# c8 — precision, not just recall. These backticked tokens sit inside 不用 lines and
# LOOK like the dangling-pointer class: a wildcard family, a phrase with spaces, and a
# hyphenless word. None is a skill name and none may be reported. Without this row a
# later tightening of the dangling regex over-fires on the real catalog and the suite
# still goes green, which is how a guard turns into an outage.
new_case
python3 - "$CASE_DIR/docs/SKILLS.md" <<'PY'
import sys
path = sys.argv[1]
text = open(path, encoding="utf-8").read()
anchor = "- `tighten-doc` `entry` "
head, sep, tail = text.partition(anchor)
assert sep, "c8 fixture anchor missing"
line, nl, rest = tail.partition("\n")
skip_line, nl2, rest2 = rest.partition("\n")
assert skip_line.lstrip().startswith("- 不用："), "c8 expected a 不用 line to extend"
skip_line += "近邻：`*-architecture` 家族、`visible surface: no` 这类短语、`writer` 这种无连字符的词，都不是技能名。"
open(path, "w", encoding="utf-8").write(head + anchor + line + nl + skip_line + nl2 + rest2)
PY
run_case
[ "$CASE_STATUS" -eq 0 ] || {
  echo "FAIL[c8]: near-miss tokens in a 不用 line were reported as dangling" >&2
  printf '%s\n' "$CASE_OUTPUT" >&2
  exit 1
}

# c9 — a missing routing layer is a SUPPORTED state (this checker also runs on repos
# with no always-on layer), so it must not fail the run. What it must not do is read
# as clean: marking a skill entry claims the layer routes to it, so with no layer that
# claim was never evaluated. The run stays rc 0 and reports unevaluated; claiming
# contract_ok over it would be a verdict structurally incapable of being red.
new_case
rm -f "$CASE_DIR/agent-context/session-start.md"
run_case
printf '%s\n' "$CASE_OUTPUT" | grep -q 'skill_catalog_entry_coverage_unevaluated' || {
  echo "FAIL[c9]: missing routing layer was not reported as unevaluated" >&2
  printf '%s\n' "$CASE_OUTPUT" >&2
  exit 1
}
printf '%s\n' "$CASE_OUTPUT" | grep -q 'skill_catalog_contract_ok' && {
  echo "FAIL[c9]: contract_ok claimed while entry coverage was never evaluated" >&2
  printf '%s\n' "$CASE_OUTPUT" >&2
  exit 1
}

# c10 — a row whose only clause is a redirect must NOT satisfy the two-line contract.
# `用：` is a substring of `不用：`, so a bare include? check passes a row that never
# says when to USE the skill.
new_case
sed -i.bak 's|^\(- `tighten-doc` `entry` \)— 用：|\1— 不用：|' "$CASE_DIR/docs/SKILLS.md"
run_case
expect_block c10 'skill_catalog_missing_use_line: tighten-doc'

# c11 — a skill marked leaf but routed in the always-on layer contradicts its own
# mark. The mark is what the catalog tells readers, so it must not be able to lie.
new_case
python3 - "$CASE_DIR/docs/SKILLS.md" <<'PYX'
import sys,re
p=sys.argv[1]; s=open(p,encoding="utf-8").read()
s=s.replace("- `tighten-doc` `entry` ","- `tighten-doc` `leaf` ",1)
open(p,"w",encoding="utf-8").write(s)
PYX
run_case
expect_block c11 'skill_bootstrap_leaf_in_region: tighten-doc'

echo "test_check_ccl_skill_catalog: ok"
