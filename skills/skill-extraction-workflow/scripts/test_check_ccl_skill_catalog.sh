#!/usr/bin/env bash
set -euo pipefail

# Caller Git routing must never override any fixture `git -C` operation. The
# c12 hostile-context wrapper reintroduces synthetic values only around checker
# subprocesses, then restores this clean baseline before later ref mutations.
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_OBJECT_DIRECTORY \
  GIT_ALTERNATE_OBJECT_DIRECTORIES GIT_COMMON_DIR GIT_CEILING_DIRECTORIES \
  GIT_NAMESPACE

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
#   c12 unset base override covers upstream/fallback x empty/changed diff

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
  # This suite owns catalog mutations, not the source repo's accumulated
  # impact-chain diff. Pin each clone to the exact source tree so unrelated
  # branch ancestry cannot make the pristine catalog case red.
  source_head="$(git -C "$REPO_ROOT" rev-parse HEAD)"
  git -C "$CASE_DIR" fetch --quiet --no-tags "$REPO_ROOT" HEAD
  [ "$(git -C "$CASE_DIR" rev-parse FETCH_HEAD)" = "$source_head" ] || {
    echo "catalog fixture fetched the wrong source HEAD" >&2
    exit 1
  }
  git -C "$CASE_DIR" update-ref refs/heads/ccl-test-base FETCH_HEAD
  # The clone carries the default branch; copy the working-tree versions of the
  # three files under test so the gate runs against what is about to land.
  cp "$REPO_ROOT/docs/SKILLS.md" "$CASE_DIR/docs/SKILLS.md"
  cp "$REPO_ROOT/agent-context/session-start.md" "$CASE_DIR/agent-context/session-start.md"
  cp "$REPO_ROOT/skills/skill-extraction-workflow/scripts/check-ccl-skills.sh" \
    "$CASE_DIR/skills/skill-extraction-workflow/scripts/check-ccl-skills.sh"
}

run_case() {
  set +e
  CASE_OUTPUT="$(
    unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_OBJECT_DIRECTORY \
      GIT_ALTERNATE_OBJECT_DIRECTORIES GIT_COMMON_DIR GIT_CEILING_DIRECTORIES \
      GIT_NAMESPACE
    CCL_SKILL_BASE_REF=ccl-test-base \
      bash "$CASE_DIR/skills/skill-extraction-workflow/scripts/check-ccl-skills.sh" "$CASE_DIR" 2>&1
  )"
  CASE_STATUS=$?
  set -e
}

run_case_with_default_base() {
  set +e
  CASE_OUTPUT="$(
    unset CCL_SKILL_BASE_REF GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE \
      GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES GIT_COMMON_DIR \
      GIT_CEILING_DIRECTORIES GIT_NAMESPACE
    bash "$CASE_DIR/skills/skill-extraction-workflow/scripts/check-ccl-skills.sh" "$CASE_DIR" 2>&1
  )"
  CASE_STATUS=$?
  set -e
  return "$CASE_STATUS"
}

run_case_with_base() {
  local base="$1"
  set +e
  CASE_OUTPUT="$(
    unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_OBJECT_DIRECTORY \
      GIT_ALTERNATE_OBJECT_DIRECTORIES GIT_COMMON_DIR GIT_CEILING_DIRECTORIES \
      GIT_NAMESPACE
    CCL_SKILL_BASE_REF="$base" \
      bash "$CASE_DIR/skills/skill-extraction-workflow/scripts/check-ccl-skills.sh" "$CASE_DIR" 2>&1
  )"
  CASE_STATUS=$?
  set -e
  return "$CASE_STATUS"
}

run_with_hostile_git_context() {
  local git_dir_was_set="${GIT_DIR+x}" git_dir_before="${GIT_DIR-}"
  local git_work_tree_was_set="${GIT_WORK_TREE+x}" git_work_tree_before="${GIT_WORK_TREE-}"
  local git_index_was_set="${GIT_INDEX_FILE+x}" git_index_before="${GIT_INDEX_FILE-}"
  local status

  export GIT_DIR="$HOSTILE_GIT_DIR"
  export GIT_WORK_TREE="$HOSTILE_GIT_WORK_TREE"
  export GIT_INDEX_FILE="$HOSTILE_GIT_INDEX"
  if "$@"; then
    status=0
  else
    status=$?
  fi

  if [ "$git_dir_was_set" = x ]; then export GIT_DIR="$git_dir_before"; else unset GIT_DIR; fi
  if [ "$git_work_tree_was_set" = x ]; then export GIT_WORK_TREE="$git_work_tree_before"; else unset GIT_WORK_TREE; fi
  if [ "$git_index_was_set" = x ]; then export GIT_INDEX_FILE="$git_index_before"; else unset GIT_INDEX_FILE; fi
  return "$status"
}

retain_only_ref_at_oid() {
  local oid="$1" expected_ref="$2" label="$3"
  local refs_at_oid expected_label ref_name
  refs_at_oid="$(git -C "$CASE_DIR" for-each-ref --points-at "$oid" --format='%(refname)')"
  while read -r ref_name; do
    if [ -n "$ref_name" ] && [ "$ref_name" != "$expected_ref" ]; then
      git -C "$CASE_DIR" update-ref --no-deref -d "$ref_name"
    fi
  done <<<"$refs_at_oid"
  refs_at_oid="$(git -C "$CASE_DIR" for-each-ref --points-at "$oid" --format='%(refname)')"
  expected_label="${expected_ref:-no ref}"
  [ "$refs_at_oid" = "$expected_ref" ] || {
    echo "FAIL[$label]: expected $expected_label at the fixture base" >&2
    printf '%s\n' "$refs_at_oid" >&2
    exit 1
  }
}

seed_base_alias_tags() {
  local oid="$1" label="$2"
  git -C "$CASE_DIR" \
    -c user.name='CCL Fixture' \
    -c user.email=fixture@example.invalid \
    tag -a "catalog-fixture-annotated-$label" \
    -m "catalog fixture annotated alias $label" "$oid"
  git -C "$CASE_DIR" \
    -c advice.nestedTag=false \
    -c user.name='CCL Fixture' \
    -c user.email=fixture@example.invalid \
    tag -a "catalog-fixture-nested-$label" \
    -m "catalog fixture nested alias $label" \
    "refs/tags/catalog-fixture-annotated-$label"
}

expect_base_alias_tags_removed() {
  local label="$1" ref
  for ref in \
    "refs/tags/catalog-fixture-annotated-$label" \
    "refs/tags/catalog-fixture-nested-$label"; do
    if git -C "$CASE_DIR" show-ref --verify --quiet "$ref"; then
      echo "FAIL[$label]: peeled fixture alias survived ref cleanup: $ref" >&2
      exit 1
    fi
  done
}

expect_changed_entrypoint_warning() {
  local label="$1" skill="$2"
  [ "$CASE_STATUS" -eq 0 ] || {
    echo "FAIL[$label]: checker failed before the changed-entrypoint oracle" >&2
    printf '%s\n' "$CASE_OUTPUT" >&2
    exit 1
  }
  grep -q \
    "$skill: entrypoint_body_above_recommended_for_changed_file" \
    <<<"$CASE_OUTPUT" || {
    echo "FAIL[$label]: changed-entrypoint warning missing" >&2
    printf '%s\n' "$CASE_OUTPUT" >&2
    exit 1
  }
}

expect_no_changed_entrypoint_warning() {
  local label="$1" skill="$2"
  [ "$CASE_STATUS" -eq 0 ] || {
    echo "FAIL[$label]: checker failed before the unchanged-entrypoint oracle" >&2
    printf '%s\n' "$CASE_OUTPUT" >&2
    exit 1
  }
  if grep -q \
    "$skill: entrypoint_body_above_recommended_for_changed_file" \
    <<<"$CASE_OUTPUT"; then
    echo "FAIL[$label]: unchanged entrypoint was reported as changed" >&2
    printf '%s\n' "$CASE_OUTPUT" >&2
    exit 1
  fi
}

expect_block() {
  local label="$1" token="$2"
  [ "$CASE_STATUS" -ne 0 ] || {
    echo "FAIL[$label]: gate passed but should have blocked" >&2
    printf '%s\n' "$CASE_OUTPUT" >&2
    exit 1
  }
  # SIGPIPE-safe match; see the note at the first such comparison below.
  # `=~`, not a glob: callers pass REGEX tokens (c1 uses `.*`), so a literal
  # substring test would reject a correct gate message.
  [[ "$CASE_OUTPUT" =~ $token ]] || {
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
# Pure-bash substring match, not `printf | grep -q`: grep -q exits on its first
# hit, the producer takes SIGPIPE, and under `set -o pipefail` the SUCCESS path
# then reports failure. Timing-dependent, so it stayed latent until this lane
# ran concurrently (specs/037-ci-intra-job-parallel/plan.md).
[[ "$CASE_OUTPUT" == *skill_catalog_contract_ok* ]] || {
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
[[ "$CASE_OUTPUT" == *skill_catalog_entry_coverage_unevaluated* ]] || {
  echo "FAIL[c9]: missing routing layer was not reported as unevaluated" >&2
  printf '%s\n' "$CASE_OUTPUT" >&2
  exit 1
}
[[ "$CASE_OUTPUT" == *skill_catalog_contract_ok* ]] && {
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

# c12 — exercise both default-base branches without depending on the source
# repository's ancestry. For upstream and origin/main fallback alike, run an
# empty-diff arm at H and a changed-diff arm at B. The checker must track that
# matrix with the override unset; a no-base path that marks everything changed
# or a wrong-ref path cannot satisfy all four arms.
new_case
DEFAULT_CHANGED_SKILL=catalog-default-base-fixture
mkdir -p "$CASE_DIR/skills/$DEFAULT_CHANGED_SKILL/agents"
python3 - \
  "$CASE_DIR/skills/$DEFAULT_CHANGED_SKILL/SKILL.md" \
  "$CASE_DIR/skills/$DEFAULT_CHANGED_SKILL/agents/openai.yaml" \
  "$CASE_DIR/docs/SKILLS.md" <<'PYBASE'
import re
import sys

skill_path, overlay_path, catalog_path = sys.argv[1:]
body = (
    "# Catalog Default-Base Fixture\n\n"
    "fixture-state-base\n\n"
    + "fixture-line\n" * 420
)
assert len(body.encode("utf-8")) > 5000, "c12 baseline body must exceed the warning threshold"
frontmatter = """---
name: catalog-default-base-fixture
description: "Synthetic skill used only inside the catalog default-base regression clone. Skip: never route it in real work."
---
"""
open(skill_path, "w", encoding="utf-8").write(frontmatter + body)
open(overlay_path, "w", encoding="utf-8").write(
    """interface:
  display_name: "Catalog Default-Base Fixture"
  short_description: "Synthetic default-base regression fixture"
  default_prompt: "Use $catalog-default-base-fixture only inside its generated regression clone."
"""
)
catalog_text = open(catalog_path, encoding="utf-8").read()
anchor = re.search(r"(?m)^- `[a-z0-9-]+` `leaf` ", catalog_text)
assert anchor, "c12 catalog has no leaf row anchor"
fixture_row = (
    "- `catalog-default-base-fixture` `leaf` — 用：仅供 catalog default-base 合成回归夹具。\n"
    "  - 不用：真实任务一律不路由到这个合成技能。\n"
)
open(catalog_path, "w", encoding="utf-8").write(
    catalog_text[: anchor.start()] + fixture_row + catalog_text[anchor.start() :]
)
PYBASE
git -C "$CASE_DIR" add \
  "skills/$DEFAULT_CHANGED_SKILL/SKILL.md" \
  "skills/$DEFAULT_CHANGED_SKILL/agents/openai.yaml" \
  docs/SKILLS.md
git -C "$CASE_DIR" \
  -c user.name='CCL Fixture' \
  -c user.email=fixture@example.invalid \
  commit --quiet -m 'catalog default-base baseline'
DEFAULT_BASE_OID="$(git -C "$CASE_DIR" rev-parse HEAD)"
git -C "$CASE_DIR" update-ref refs/heads/catalog-fixture-base "$DEFAULT_BASE_OID"
git -C "$CASE_DIR" checkout --quiet -B catalog-default-base "$DEFAULT_BASE_OID"
git -C "$CASE_DIR" branch --set-upstream-to=catalog-fixture-base catalog-default-base >/dev/null
python3 - "$CASE_DIR/skills/$DEFAULT_CHANGED_SKILL/SKILL.md" <<'PYBASE'
import sys

path = sys.argv[1]
text = open(path, encoding="utf-8").read()
assert text.count("fixture-state-base") == 1, "c12 baseline state marker missing or duplicated"
updated = text.replace("fixture-state-base", "fixture-state-head")
assert len(updated.encode("utf-8")) == len(text.encode("utf-8")), "c12 state change must be size neutral"
open(path, "w", encoding="utf-8").write(updated)
PYBASE
git -C "$CASE_DIR" add "skills/$DEFAULT_CHANGED_SKILL/SKILL.md"
git -C "$CASE_DIR" \
  -c user.name='CCL Fixture' \
  -c user.email='fixture@example.invalid' \
  commit --quiet -m 'catalog default-base fixture'
DEFAULT_HEAD_OID="$(git -C "$CASE_DIR" rev-parse HEAD)"
git -C "$CASE_DIR" update-ref refs/remotes/origin/main "$DEFAULT_HEAD_OID"
HOSTILE_GIT_DIR="$TEST_ROOT/hostile.git"
HOSTILE_GIT_WORK_TREE="$TEST_ROOT/hostile-worktree"
HOSTILE_GIT_INDEX="$TEST_ROOT/hostile-index"
mkdir -p "$HOSTILE_GIT_WORK_TREE"
git init --bare --quiet "$HOSTILE_GIT_DIR"

# Calibrate the observable independently of default discovery. If the size
# metric or fixture contract changes, fail under this explicit base label
# instead of misreporting a resolver regression in one of the four arms.
# The wrapper propagates the checker rc only after restoring Git routing. The
# next assertion owns the diagnostic and reads the same rc from CASE_STATUS.
run_with_hostile_git_context run_case_with_base "$DEFAULT_BASE_OID" || :
expect_changed_entrypoint_warning c12-explicit-base-calibration "$DEFAULT_CHANGED_SKILL"

# Upstream, empty diff: the sole configured upstream resolves to H.
git -C "$CASE_DIR" update-ref refs/heads/catalog-fixture-base "$DEFAULT_HEAD_OID"
seed_base_alias_tags "$DEFAULT_BASE_OID" c12-upstream-empty
retain_only_ref_at_oid "$DEFAULT_BASE_OID" '' c12-upstream-empty
expect_base_alias_tags_removed c12-upstream-empty
[ "$(git -C "$CASE_DIR" merge-base '@{upstream}' HEAD)" = "$DEFAULT_HEAD_OID" ] || {
  echo 'FAIL[c12]: empty-diff upstream does not resolve to fixture HEAD' >&2
  exit 1
}
run_with_hostile_git_context run_case_with_default_base || :
expect_no_changed_entrypoint_warning c12-upstream-empty "$DEFAULT_CHANGED_SKILL"

# Upstream, changed diff: the sole B-valued ref is the configured upstream.
git -C "$CASE_DIR" update-ref refs/heads/catalog-fixture-base "$DEFAULT_BASE_OID"
seed_base_alias_tags "$DEFAULT_BASE_OID" c12-upstream-changed
retain_only_ref_at_oid \
  "$DEFAULT_BASE_OID" refs/heads/catalog-fixture-base c12-upstream-changed
expect_base_alias_tags_removed c12-upstream-changed
[ "$(git -C "$CASE_DIR" merge-base '@{upstream}' HEAD)" = "$DEFAULT_BASE_OID" ] || {
  echo 'FAIL[c12]: changed-diff upstream does not resolve to fixture base' >&2
  exit 1
}
run_with_hostile_git_context run_case_with_default_base || :
expect_changed_entrypoint_warning c12-upstream-changed "$DEFAULT_CHANGED_SKILL"

# Fallback, empty diff: no upstream exists and origin/main resolves to H.
git -C "$CASE_DIR" branch --unset-upstream
git -C "$CASE_DIR" update-ref refs/remotes/origin/main "$DEFAULT_HEAD_OID"
seed_base_alias_tags "$DEFAULT_BASE_OID" c12-fallback-empty
retain_only_ref_at_oid "$DEFAULT_BASE_OID" '' c12-fallback-empty
expect_base_alias_tags_removed c12-fallback-empty
git -C "$CASE_DIR" rev-parse '@{upstream}' >/dev/null 2>&1 && {
  echo 'FAIL[c12]: fallback arm still has an upstream' >&2
  exit 1
}
[ "$(git -C "$CASE_DIR" merge-base origin/main HEAD)" = "$DEFAULT_HEAD_OID" ] || {
  echo 'FAIL[c12]: empty-diff origin/main does not resolve to fixture HEAD' >&2
  exit 1
}
run_with_hostile_git_context run_case_with_default_base || :
expect_no_changed_entrypoint_warning c12-fallback-empty "$DEFAULT_CHANGED_SKILL"

# Fallback, changed diff: the sole B-valued ref is origin/main.
git -C "$CASE_DIR" update-ref refs/remotes/origin/main "$DEFAULT_BASE_OID"
seed_base_alias_tags "$DEFAULT_BASE_OID" c12-fallback-changed
retain_only_ref_at_oid \
  "$DEFAULT_BASE_OID" refs/remotes/origin/main c12-fallback-changed
expect_base_alias_tags_removed c12-fallback-changed
[ "$(git -C "$CASE_DIR" merge-base origin/main HEAD)" = "$DEFAULT_BASE_OID" ] || {
  echo 'FAIL[c12]: changed-diff origin/main does not resolve to fixture base' >&2
  exit 1
}
run_with_hostile_git_context run_case_with_default_base || :
expect_changed_entrypoint_warning c12-fallback-changed "$DEFAULT_CHANGED_SKILL"

echo "test_check_ccl_skill_catalog: ok"
