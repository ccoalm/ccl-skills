#!/usr/bin/env bash
# Regression tests for check-sync-pointers.sh (semantic tier of the sync
# family: declared pinned pairs + the security-four-questions subset
# registry). Clones this repo, then mutates ONE side of a registered pair /
# registry at a time. The checker is invoked DIRECTLY (not through
# check-ccl-skills.sh) so rc semantics belong to this unit alone.
# All in-place file mutations go through python3 — BSD `sed -i ''` is not
# portable to GNU sed (Linux CI), and a red suite there would be a harness
# defect, not evidence.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd -P)"
SYNC_SCRIPT="$SCRIPT_DIR/check-sync-pointers.sh"
[ -f "$SYNC_SCRIPT" ] || { echo "FAIL: sync checker not found: $SYNC_SCRIPT" >&2; exit 1; }
ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd -P)"

TMP="$(mktemp -d "${TMPDIR:-/tmp}/syncpointers.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

fail() { echo "FAIL: $*" >&2; exit 1; }
assert_rc() { [ "$1" = "$2" ] || fail "expected rc=$2 got rc=$1${3:+ ($3)}"; }
assert_contains() { case "$2" in *"$1"*) : ;; *) fail "expected output to contain: $1${3:+ ($3)}";; esac; }
assert_not_contains() { case "$2" in *"$1"*) fail "expected output NOT to contain: $1${3:+ ($3)}";; *) : ;; esac; }

# replace_in_file <file> <old> <new> — fails loudly when the anchor is absent.
replace_in_file() {
  python3 - "$1" "$2" "$3" <<'PY'
import sys
path, old, new = sys.argv[1], sys.argv[2], sys.argv[3]
text = open(path).read()
assert old in text, f"fixture anchor missing in {path}: {old!r}"
open(path, "w").write(text.replace(old, new, 1))
PY
}

run_sync() {
  set +e
  out="$(bash "$SYNC_SCRIPT" "$REPO" 2>&1)"
  rc=$?
  set -e
}

REPO="$TMP/repo"
git clone -q "$ROOT" "$REPO"
git -C "$REPO" config user.email test@example.invalid
git -C "$REPO" config user.name "Test User"
# Give the clone its own base branch and upstream — the same fixture shape the
# sibling e2e (test_register_firing_path_wiring.sh) documents. The two
# end-to-end cases below run the FULL validator, whose diff base comes from
# `@{upstream}` with an `origin/main` fallback. A clone taken while CI has the
# project at a DETACHED HEAD carries neither, so the impact-chain gate exits 1
# with `impact_chain_merge_base_missing: origin/main` BEFORE the run reaches the
# combined sync verdict — and because the deferred-verdict EXIT trap only fires
# on an otherwise-clean exit (by design: an already-red run is not re-verdicted),
# `sync_reference_blocking_failed` would never be printed. rc would still be 1,
# so only the token assertion reds: a CI-only harness defect that says nothing
# about the wiring under test. Reproduced first-hand against a detached-HEAD
# clone before this line existed.
git -C "$REPO" branch -f fixture-base HEAD
git -C "$REPO" switch -q -C fixture-work fixture-base
git -C "$REPO" branch --set-upstream-to=fixture-base fixture-work >/dev/null 2>&1
WT="$REPO/skills/worktree-isolation/SKILL.md"
SEC4="$REPO/skills/requirement-doc-writer/references/security-four-questions.md"
DTREF="$REPO/skills/skill-extraction-workflow/references/dual-track-review-gate.md"

# GREEN: the unmutated clone must pass — both tiers run to their done markers.
run_sync
assert_rc "$rc" 0 "unmutated clone must pass the semantic sync gate"
assert_contains "sync_pointer_check_done" "$out" "pointer tier completes"
assert_contains "sync_subset_check_done" "$out" "subset tier completes"
assert_contains "sync_semantic_check_ok" "$out" "final ok token present"

# s1 RED: canonical section label reworded => the always-on pointer dangles.
replace_in_file "$WT" "合并执行协议（canonical" "合并落地协议（canonical"
run_sync
assert_rc "$rc" 1 "reworded canonical section must block"
assert_contains "sync_pointer_block: merge-exec-protocol-section" "$out" "block names the pair"
git -C "$REPO" checkout -- skills/worktree-isolation/SKILL.md

# s2 RED: section heading renamed => 收尾节 pointer dangles (the pinned
# literal carries the colon so a longer heading cannot substring-satisfy it).
replace_in_file "$WT" "## 收尾：" "## 收尾清理："
run_sync
assert_rc "$rc" 1 "renamed teardown heading must block"
assert_contains "sync_pointer_block: worktree-teardown-section" "$out" "block names the pair"
git -C "$REPO" checkout -- skills/worktree-isolation/SKILL.md

# s3 RED: bootstrap side reworded => pointer literal lost on the source side.
replace_in_file "$REPO/agent-context/session-start.md" "「合并执行协议」" "「合并协议」"
run_sync
assert_rc "$rc" 1 "reworded always-on pointer must block"
assert_contains "sync_pointer_block: merge-exec-protocol-section: agent-context/session-start.md lost the registered pointer literal" "$out" "block names the source side"
git -C "$REPO" checkout -- agent-context/session-start.md

# s4 RED: canonical reference file deleted => bare-filename pointer dangles
# (a blocking violation, NOT an infra error).
rm -f "$DTREF"
run_sync
assert_rc "$rc" 1 "deleted canonical reference must block"
assert_contains "sync_pointer_block: dual-track-review-gate-ref" "$out" "block names the pair"
git -C "$REPO" checkout -- skills/skill-extraction-workflow/references/dual-track-review-gate.md

# s5 RED: canonical predicate removed from the registry => the extracted
# bootstrap table escapes the (shrunk) canonical set.
replace_in_file "$SEC4" "q2-canonical: 伪造,篡改,重放,越权,重复提交,误删,覆盖" "q2-canonical: 伪造,重放,越权,重复提交,误删,覆盖"
run_sync
assert_rc "$rc" 1 "bootstrap superset of the registry must block"
assert_contains "escapes the canonical predicate set" "$out" "block names the escape"
git -C "$REPO" checkout -- skills/requirement-doc-writer/references/security-four-questions.md

# s6 RED: registry-only canonical token (absent from its anchored list region).
replace_in_file "$SEC4" "q2-canonical: 伪造,篡改,重放,越权,重复提交,误删,覆盖" "q2-canonical: 伪造,篡改,重放,越权,重复提交,误删,覆盖,抵赖"
run_sync
assert_rc "$rc" 1 "registry-only canonical token must block"
assert_contains "absent from its list region" "$out" "block names the registry/region mismatch"
git -C "$REPO" checkout -- skills/requirement-doc-writer/references/security-four-questions.md

# s7 RED: alias dropped => trigger lists no longer reconcile.
replace_in_file "$SEC4" "alias: 租户或用户隔离=租户/用户隔离" "alias:"
run_sync
assert_rc "$rc" 1 "dropped alias must block"
assert_contains "sync_subset_block:" "$out" "subset block present"
git -C "$REPO" checkout -- skills/requirement-doc-writer/references/security-four-questions.md

# s8 infra: registry block removed entirely => fail-closed rc 2, no ok token.
python3 - "$SEC4" <<'PY'
import re, sys
p = sys.argv[1]
text = open(p).read()
text2 = re.sub(r'<!--\s*sync-registry:v1\s*.*?-->', '', text, flags=re.S)
assert text2 != text, "fixture premise: registry block exists"
open(p, 'w').write(text2)
PY
run_sync
assert_rc "$rc" 2 "missing registry must fail closed as infra"
assert_contains "sync_subset_infra" "$out" "infra marker present"
assert_not_contains "sync_semantic_check_ok" "$out" "no ok token on infra failure"
git -C "$REPO" checkout -- skills/requirement-doc-writer/references/security-four-questions.md

# s9 wiring anchors: the validator must invoke the gate, propagate rc=1 into
# the deferred verdict, fail closed on rc>=2, and treat a missing script as a
# broken checkout (never a skippable advisory). Each anchor must be FIRABLE:
# assert the grepped line exists before judging its content.
validator="$SCRIPT_DIR/check-ccl-skills.sh"
grep -q '|| sync_pointer_rc=\$?' "$validator" || fail "validator no longer records sync-gate rc"
grep -q 'sync_pointer_infra_failed' "$validator" || fail "validator missing infra fail-closed branch"
grep -qF 'sync_pointer_script="$checker_scripts_dir/check-sync-pointers.sh"' "$validator" || fail "validator must resolve the semantic gate beside itself (an in-tree copy could be doctored to exit 0)"
grep -qF 'check-sync-pointers.sh missing or not a regular file beside the validator' "$validator" || fail "validator missing the beside-itself existence guard"
wiring_line="$(grep -F 'bash "$sync_pointer_script" "$root"' "$validator" || true)"
[ -n "$wiring_line" ] || fail "validator sync-gate invocation line not found (wiring anchor moved?)"
case "$wiring_line" in
  *"|| true"*) fail "validator demoted the semantic sync gate back to || true advisory" ;;
esac
# skip-degradation wiring anchors (the e2e of the skip state is not
# constructible in a full clone — a package removal reddens the route gate
# first — so these pins are firable greps, not behavioral fixtures):
grep -qF 'sync_pointer_skipped=1' "$validator" || fail "validator lost the skip-marker detection branch"
grep -qF '"${sync_pointer_skipped:-0}" != "1"' "$validator" || fail "validator lost the clean-token downgrade condition"
grep -qF 'semantic sync checks were partially skipped' "$validator" || fail "validator lost the skip interim notice"

# s10: agent-context/session-start.md deleted from an otherwise-FULL tree is an always-on-layer
# deletion (it bypasses every pin) and must BLOCK; only a genuinely partial
# tree (no canonical packages at all) gets the marked skip. The skip-marker
# degradation wiring is exercised via wiring anchors (s9): a package removal in
# a full clone turns its backticked mentions into stale routes and the route
# gate reddens first, so a full-validator e2e of the skip state is not
# constructible in a clone — recorded, not silently skipped.
git -C "$REPO" rm -q agent-context/session-start.md
run_sync
assert_rc "$rc" 1 "deleting agent-context/session-start.md from a full tree must block"
assert_contains "agent-context/session-start.md missing while pinned canonical packages are present" "$out" "block names the always-on-layer deletion"
assert_not_contains "sync_semantic_check_ok" "$out" "no ok token on a block"
git -C "$REPO" checkout HEAD -- agent-context/session-start.md

# s11 RED: bootstrap Q2 grows a superset token whose string still CONTAINS the
# old literal — only real extraction (not a substring include?) catches it.
replace_in_file "$REPO/agent-context/session-start.md" "若某值被伪造/篡改爆炸半径" "若某值被伪造/篡改/滥用爆炸半径"
run_sync
assert_rc "$rc" 1 "a superset token in the bootstrap table must block"
assert_contains "sync_subset_block: bootstrap q2 table" "$out" "block names the escaping token"
assert_contains "滥用" "$out" "the escaping token is named"
git -C "$REPO" checkout -- agent-context/session-start.md

# s12 RED: bootstrap trigger anchor reworded => extraction fails closed as a
# block (reword the reflection and the anchors together).
replace_in_file "$REPO/agent-context/session-start.md" "触及 身份·计费·配额" "触及：身份·计费·配额"
run_sync
assert_rc "$rc" 1 "a destroyed extraction anchor must block"
assert_contains "no longer matches the registered anchor shape" "$out" "block names the anchor loss"
git -C "$REPO" checkout -- agent-context/session-start.md

# s13 RED: q2/q4 extraction anchor loss must also block (the /若某值被…爆炸半径/
# and /写一条…负向用例/ shapes were previously unpinned).
replace_in_file "$REPO/agent-context/session-start.md" "若某值被伪造/篡改爆炸半径" "若某值被伪造/篡改的影响半径"
run_sync
assert_rc "$rc" 1 "a destroyed q2 anchor must block"
assert_contains "agent-context/session-start.md compressed q2 table no longer matches the registered anchor shape" "$out" "block names the q2 anchor loss"
git -C "$REPO" checkout -- agent-context/session-start.md

# s14 RED: a token dropped from the bootstrap trigger list (anchor intact)
# must block on the missing branch.
replace_in_file "$REPO/agent-context/session-start.md" "权限·删除·覆盖 时" "权限·删除 时"
run_sync
assert_rc "$rc" 1 "a dropped trigger token must block"
assert_contains "not reflected in the bootstrap list" "$out" "block names the missing-token branch"
git -C "$REPO" checkout -- agent-context/session-start.md

# s15: package availability ladder — a wholesale-missing package with the
# always-on layer ALIVE blocks (bypass-by-omission); the marked skip exists
# only for a genuinely partial tree (bootstrap also absent); a file lost
# inside a present package blocks.
mv "$REPO/skills/tighten-doc" "$TMP/tighten-doc-parked"
run_sync
assert_rc "$rc" 1 "an absent package with the always-on layer alive must block"
assert_contains "sync_pointer_block: cross-model-caveat: canonical package tighten-doc missing while the always-on layer is present" "$out" "block names the wholesale bypass"
git -C "$REPO" rm -q agent-context/session-start.md
run_sync
assert_rc "$rc" 1 "bootstrap gone with other pinned packages still present must block"
assert_contains "agent-context/session-start.md missing while pinned canonical packages are present" "$out" "block names the omission bypass"
git -C "$REPO" checkout HEAD -- agent-context/session-start.md
mv "$TMP/tighten-doc-parked" "$REPO/skills/tighten-doc"
# The marked skip exists only for a tree with NO pinned package at all —
# exercised on a synthetic mini tree (in a full clone every package removal
# reddens an earlier gate first).
TINY="$TMP/tiny-tree"
mkdir -p "$TINY/skills/demo-skill"
printf -- '---\nname: demo-skill\ndescription: tiny tree fixture.\n---\n\nbody\n' > "$TINY/skills/demo-skill/SKILL.md"
set +e
out="$(bash "$SYNC_SCRIPT" "$TINY" 2>&1)"
rc=$?
set -e
assert_rc "$rc" 0 "a tree with no pinned package and no bootstrap must skip, not block"
assert_contains "sync_pointer_check_skipped: agent-context/session-start.md missing" "$out" "skip marker present"
assert_not_contains "sync_semantic_check_ok" "$out" "no ok token on a skip"
rm -f "$REPO/skills/tighten-doc/SKILL.md"
run_sync
assert_rc "$rc" 1 "a file lost inside a present package must block"
assert_contains "sync_pointer_block: cross-model-caveat" "$out" "block names the pair with the lost target"
git -C "$REPO" checkout -- skills/tighten-doc/SKILL.md

# s16 RED: the canonical registry file deleted while its package is present.
rm -f "$SEC4"
run_sync
assert_rc "$rc" 1 "deleted canonical registry file must block"
assert_contains "canonical registry file missing inside a present package" "$out" "block names the registry loss"
git -C "$REPO" checkout -- skills/requirement-doc-writer/references/security-four-questions.md

# s17 RED: the agent-command-sandbox canonical reference file removed (the
# pair pins the dedicated file, not a recursive mention).
rm -f "$REPO/skills/llm-inference-integration/references/agent-command-sandbox.md"
run_sync
assert_rc "$rc" 1 "deleted agent-command-sandbox reference must block"
assert_contains "sync_pointer_block: agent-command-sandbox" "$out" "block names the pair"
git -C "$REPO" checkout -- skills/llm-inference-integration/references/agent-command-sandbox.md

# s18 infra: a second sync-registry:v1 block shadows the real one => rc 2.
python3 - "$SEC4" <<'PY'
import re, sys
p = sys.argv[1]
text = open(p).read()
shadow = "<!-- sync-registry:v1\ntrigger-canonical: 身份\nq2-canonical: 伪造\nq4-canonical: 伪造\n-->\n"
assert len(re.findall(r'<!--\s*sync-registry:v1', text)) == 1, "fixture premise: exactly one registry block"
open(p, "w").write(shadow + text)
PY
run_sync
assert_rc "$rc" 2 "a second registry block must fail closed as infra"
assert_contains "sync-registry:v1 blocks" "$out" "infra marker names the shadow block"
git -C "$REPO" checkout -- skills/requirement-doc-writer/references/security-four-questions.md

# s19 infra: duplicate key inside the registry => rc 2 (last-wins override
# would be invisible).
replace_in_file "$SEC4" "q2-canonical: 伪造,篡改,重放,越权,重复提交,误删,覆盖" $'q2-canonical: 伪造,篡改\nq2-canonical: 伪造'
run_sync
assert_rc "$rc" 2 "a duplicate registry key must fail closed as infra"
assert_contains "duplicate registry key" "$out" "infra marker names the duplicate"
git -C "$REPO" checkout -- skills/requirement-doc-writer/references/security-four-questions.md

# s20 RED: alias whose right side is not a canonical trigger token (mapping
# INTO an uncarried token) must block.
replace_in_file "$SEC4" "alias: 租户或用户隔离=租户/用户隔离" "alias: 租户或用户隔离=租户与用户隔离"
run_sync
assert_rc "$rc" 1 "alias mapping into an uncarried canonical token must block"
assert_contains "alias right side" "$out" "block names the alias right side"
git -C "$REPO" checkout -- skills/requirement-doc-writer/references/security-four-questions.md

# s21 RED: alias whose left side is not in the extracted bootstrap trigger
# list (an unattested alias) must block.
replace_in_file "$SEC4" "alias: 租户或用户隔离=租户/用户隔离" "alias: 租户或用户隔离=租户/用户隔离,滥用=覆盖"
run_sync
assert_rc "$rc" 1 "an unattested alias left side must block"
assert_contains "alias left side" "$out" "block names the alias left side"
git -C "$REPO" checkout -- skills/requirement-doc-writer/references/security-four-questions.md

# s22 RED (end-to-end): a sync violation must redden the FULL validator
# through the deferred verdict — the static wiring anchors alone cannot prove
# the rc path fires, and a deleted `|| [ "$sync_pointer_rc" -eq 1 ]` leg must
# not go green.
replace_in_file "$REPO/agent-context/session-start.md" "「合并执行协议」" "「合并协议」"
set +e
out="$(env -u ALIAS_AUDIT_CMD -u CCL_SKILL_BASE_REF bash "$validator" "$REPO" 2>&1)"
rc=$?
set -e
assert_rc "$rc" 1 "a sync violation must fail the full validator"
assert_contains "sync_reference_blocking_failed" "$out" "combined verdict present end-to-end"
assert_not_contains "ccl_skill_check_clean_ok" "$out" "no clean token next to a sync block"
git -C "$REPO" checkout -- agent-context/session-start.md

# s23 RED: renaming the real canonical section while keeping a narrative
# mention of the label must still block (the pinned literal carries the
# structural prefix, so a demoted label no longer matches).
replace_in_file "$WT" "**合并执行协议（canonical——" "（既往）合并执行协议（canonical——"
run_sync
assert_rc "$rc" 1 "a demoted-to-narrative section label must block"
assert_contains "sync_pointer_block: merge-exec-protocol-section" "$out" "block names the pair"
git -C "$REPO" checkout -- skills/worktree-isolation/SKILL.md

# s24 RED: a compliant decoy line inserted before the real reflection makes
# the extraction anchor ambiguous (scan requires exactly one hit).
replace_in_file "$REPO/agent-context/session-start.md" "② 若某值被伪造/篡改爆炸半径" "触及 身份·计费·配额·租户或用户隔离·权限·删除·覆盖 时\n② 若某值被伪造/篡改爆炸半径"
run_sync
assert_rc "$rc" 1 "a decoy anchor line must block"
assert_contains "decoy/duplicate anchor" "$out" "block names the ambiguity"
git -C "$REPO" checkout -- agent-context/session-start.md

# s25 RED: alias laundering — an escaping token added to the bootstrap trigger
# list plus an alias onto an already-carried canonical token must block (an
# alias must be the sole attestation of its canonical token).
replace_in_file "$REPO/agent-context/session-start.md" "权限·删除·覆盖 时" "权限·滥用·删除·覆盖 时"
replace_in_file "$SEC4" "alias: 租户或用户隔离=租户/用户隔离" "alias: 租户或用户隔离=租户/用户隔离,滥用=权限"
run_sync
assert_rc "$rc" 1 "alias laundering must block"
assert_contains "sole attestation" "$out" "block names the sole-attestation rule"
git -C "$REPO" checkout -- agent-context/session-start.md skills/requirement-doc-writer/references/security-four-questions.md

# s26 RED: the bootstrap pointer demoted to a narrative mention (bare name
# survives, structural literal gone) must block on the source side.
replace_in_file "$REPO/agent-context/session-start.md" "「合并执行协议」（canonical" "（见合并执行协议）"
run_sync
assert_rc "$rc" 1 "a demoted bootstrap pointer must block"
assert_contains "sync_pointer_block: merge-exec-protocol-section: agent-context/session-start.md lost the registered pointer literal" "$out" "block names the source-side loss"
git -C "$REPO" checkout -- agent-context/session-start.md

# s27 RED: shedding a floor predicate from the bootstrap Q2 table (anchor
# intact, still a canonical subset) must block on the registered min floor.
replace_in_file "$REPO/agent-context/session-start.md" "若某值被伪造/篡改爆炸半径" "若某值被伪造爆炸半径"
run_sync
assert_rc "$rc" 1 "shedding a floor predicate must block"
assert_contains "below the registered q2-bootstrap-min floor" "$out" "block names the floor breach"
git -C "$REPO" checkout -- agent-context/session-start.md

# s28 RED: both sides of a pair drifted in the same run must BOTH be reported
# (no early return on the source side).
replace_in_file "$REPO/agent-context/session-start.md" "「合并执行协议」（canonical" "（见合并执行协议）"
replace_in_file "$WT" "**合并执行协议（canonical——" "（既往）合并执行协议（canonical——"
run_sync
assert_rc "$rc" 1 "two-sided drift must block"
assert_contains "agent-context/session-start.md lost the registered pointer literal" "$out" "source side reported"
assert_contains "canonical target" "$out" "target side reported in the same run"
git -C "$REPO" checkout -- agent-context/session-start.md skills/worktree-isolation/SKILL.md

# s29a: the semantic gate resolves beside the validator, so pruning the IN-TREE
# copy changes nothing — on a clean tree the validator still evaluates with its
# own copy (rc 0, done markers present). Removing the whole in-tree scripts
# dir still dies on missing_validate_script (rc 2, $root-based guard).
rm -f "$REPO/skills/skill-extraction-workflow/scripts/check-sync-pointers.sh"
set +e
out="$(env -u ALIAS_AUDIT_CMD -u CCL_SKILL_BASE_REF bash "$validator" "$REPO" 2>&1)"
rc=$?
set -e
assert_rc "$rc" 0 "pruning the in-tree copy must not matter (validator uses its own)"
assert_contains "sync_pointer_check_done" "$out" "the validator's own gate copy ran"
git -C "$REPO" checkout HEAD -- skills/skill-extraction-workflow/scripts/check-sync-pointers.sh
rm -rf "$REPO/skills/skill-extraction-workflow/scripts"
set +e
out="$(env -u ALIAS_AUDIT_CMD -u CCL_SKILL_BASE_REF bash "$validator" "$REPO" 2>&1)"
rc=$?
set -e
assert_rc "$rc" 2 "a pruned scripts dir must fail even earlier (validate-skill)"
assert_contains "missing_validate_script" "$out" "validate-skill absence beats the semantic tier"
git -C "$REPO" checkout HEAD -- skills/skill-extraction-workflow/scripts

# replace_all_in_file <file> <old> <new> — every occurrence.
replace_all_in_file() {
  python3 - "$1" "$2" "$3" <<'PY'
import sys
path, old, new = sys.argv[1], sys.argv[2], sys.argv[3]
text = open(path).read()
assert old in text, f"fixture anchor missing in {path}: {old!r}"
open(path, "w").write(text.replace(old, new))
PY
}

# s30 RED: the three pointer pairs whose bootstrap literal is a bare mention
# must block when the directive is demoted to narrative (structural literal
# gone, bare token surviving).
replace_in_file "$REPO/agent-context/session-start.md" "详见 tighten-doc cross-model caveat" "（见 cross-model caveat）"
run_sync
assert_rc "$rc" 1 "a demoted cross-model pointer must block"
assert_contains "sync_pointer_block: cross-model-caveat: agent-context/session-start.md lost the registered pointer literal" "$out" "block names the demoted pointer"
git -C "$REPO" checkout -- agent-context/session-start.md
replace_in_file "$REPO/agent-context/session-start.md" "细则归 \`llm-inference-integration\` agent-command-sandbox" "（见 agent-command-sandbox）"
run_sync
assert_rc "$rc" 1 "a demoted sandbox pointer must block"
assert_contains "sync_pointer_block: agent-command-sandbox: agent-context/session-start.md lost the registered pointer literal" "$out" "block names the demoted pointer"
git -C "$REPO" checkout -- agent-context/session-start.md
replace_all_in_file "$REPO/agent-context/session-start.md" "详见 product-rd 验证门 + skill-extraction \`dual-track-review-gate.md\`" "（见 dual-track-review-gate.md）"
run_sync
assert_rc "$rc" 1 "a demoted dual-track pointer must block"
assert_contains "sync_pointer_block: dual-track-review-gate-ref: agent-context/session-start.md lost the registered pointer literal" "$out" "block names the demoted pointer"
git -C "$REPO" checkout -- agent-context/session-start.md

# s31 RED: a canonical token surviving only as a SUPERSTRING of a different
# word must not attest (list-item equality, not substring).
replace_in_file "$SEC4" "身份、计费、配额、租户/用户隔离、权限、删除、覆盖" "身份、计费、配额、租户/用户隔离、权限模型、删除、覆盖"
run_sync
assert_rc "$rc" 1 "a superstring-only token must not attest"
assert_contains "absent from its list region" "$out" "block names the attestation failure"
git -C "$REPO" checkout -- skills/requirement-doc-writer/references/security-four-questions.md

# s32 GREEN: a legal rewording that inserts a comma before the anchor tail
# must NOT false-red (edge punctuation is trimmed from extracted items).
replace_in_file "$REPO/agent-context/session-start.md" "若某值被伪造/篡改爆炸半径" "若某值被伪造/篡改，爆炸半径"
run_sync
assert_rc "$rc" 0 "an inserted comma before the anchor tail must not false-red"
assert_contains "sync_semantic_check_ok" "$out" "clean verdict survives the rewording"
git -C "$REPO" checkout -- agent-context/session-start.md

# s29: substitution immunity — the semantic gate resolves beside the
# validator, so doctoring the in-tree copy to `exit 0` must NOT launder a real
# violation: the full validator still reds on a planted pointer loss.
printf '#!/usr/bin/env bash\nexit 0\n' > "$REPO/skills/skill-extraction-workflow/scripts/check-sync-pointers.sh"
replace_in_file "$REPO/agent-context/session-start.md" "「合并执行协议」（canonical" "（见合并执行协议）"
set +e
out="$(env -u ALIAS_AUDIT_CMD -u CCL_SKILL_BASE_REF bash "$validator" "$REPO" 2>&1)"
rc=$?
set -e
assert_rc "$rc" 1 "a doctored in-tree gate must not launder a real violation"
assert_contains "sync_reference_blocking_failed" "$out" "validator still reaches the sync verdict via its own gate copy"
git -C "$REPO" checkout HEAD -- agent-context/session-start.md skills/skill-extraction-workflow/scripts/check-sync-pointers.sh

# s33 infra: deleting a registered min-floor key disables the anti-shrink
# guard — the key is required, so its absence fails closed (rc 2).
python3 - "$SEC4" <<'PY'
import sys
p = sys.argv[1]
lines = open(p).readlines()
assert any(l.startswith("q2-bootstrap-min:") for l in lines), "fixture premise: floor key exists"
open(p, "w").writelines(l for l in lines if not l.startswith("q2-bootstrap-min:"))
PY
run_sync
assert_rc "$rc" 2 "a deleted min-floor key must fail closed as infra"
assert_contains "registry missing key q2-bootstrap-min" "$out" "infra marker names the missing floor key"
git -C "$REPO" checkout -- skills/requirement-doc-writer/references/security-four-questions.md

# s34 RED: the trigger list restructured across lines — the region must not
# reach past its own line to attest tokens ([^。\n] bound).
replace_in_file "$SEC4" "触及：身份、计费、配额、租户/用户隔离、权限、删除、覆盖。" $'触及：身份、计费、配额、租户/用户隔离、权限\n删除、覆盖。'
run_sync
assert_rc "$rc" 1 "a cross-line restructured trigger list must block"
assert_contains "absent from its list region" "$out" "block names the out-of-line attestation"
git -C "$REPO" checkout -- skills/requirement-doc-writer/references/security-four-questions.md

# s35 RED: a decoy DUPLICATE of a registered literal (real directive kept,
# same text also pasted into an unrelated line) makes the pointer
# unverifiable — each literal must occur exactly once on its side.
replace_in_file "$REPO/agent-context/session-start.md" "② 若某值被伪造/篡改爆炸半径" "（示例：详见 tighten-doc cross-model caveat）\n② 若某值被伪造/篡改爆炸半径"
run_sync
assert_rc "$rc" 1 "a duplicate of the literal must block"
assert_contains "2 times" "$out" "block names the duplicate count"
git -C "$REPO" checkout -- agent-context/session-start.md

# s36 RED (e2e infra): an infra condition in the tree (registry block deleted)
# must fail the FULL validator closed at rc 2 — never as a clean/advisory pass.
# (The deletion trims trailing blank lines: a whitespace-error diff dies on an
# earlier gate and would never reach the semantic tier.)
python3 - "$SEC4" <<'PY'
import re, sys
p = sys.argv[1]
text = open(p).read()
text2 = re.sub(r'<!--\s*sync-registry:v1\s*.*?-->\n?', '', text, flags=re.S)
assert text2 != text, "fixture premise: registry block exists"
open(p, 'w').write(text2.rstrip("\n") + "\n")
PY
set +e
out="$(env -u ALIAS_AUDIT_CMD -u CCL_SKILL_BASE_REF bash "$validator" "$REPO" 2>&1)"
rc=$?
set -e
assert_rc "$rc" 2 "an infra condition must fail the full validator at rc 2"
assert_contains "sync_pointer_infra_failed" "$out" "validator propagates the infra failure"
assert_not_contains "ccl_skill_check_ok" "$out" "no ok token at all on an infra failure"
git -C "$REPO" checkout -- skills/requirement-doc-writer/references/security-four-questions.md

# s37: an ABORTED subset interpreter must never be reported as a policy
# verdict. Ruby exits 1 on any uncaught exception (missing interpreter,
# non-UTF-8 locale, syntax error in the embedded program), and rc 1 out of this
# gate is what the validator folds into "reword both sides of a registered
# pair" — so collapsing the two would let a check that evaluated ZERO rules
# masquerade as a registry violation. Declared violations exit 3 internally;
# everything else is infra. A stub `ruby` on PATH reproduces the abort without
# mutating the gate under test.
stub_bin="$TMP/stub-bin"
mkdir -p "$stub_bin"
printf '#!/bin/sh\necho "ruby: simulated interpreter abort" >&2\nexit 1\n' > "$stub_bin/ruby"
chmod +x "$stub_bin/ruby"
set +e
out="$(PATH="$stub_bin:$PATH" bash "$SYNC_SCRIPT" "$REPO" 2>&1)"
rc=$?
set -e
assert_rc "$rc" 2 "an aborted subset interpreter must fail closed as infra, not as a registry violation"
assert_contains "sync_subset_infra_failed rc=1" "$out" "infra marker names the aborted interpreter"
assert_not_contains "sync_semantic_blocking_failed" "$out" "an abort must not be diagnosed as a policy violation"
assert_not_contains "sync_semantic_check_ok" "$out" "no ok token when the subset tier never ran"
# An exit STATUS is not evidence the tier ran, in EITHER direction: a silent rc 0
# would print the clean-landing token for zero evaluated rules (gate-did-not-judge
# read as gate-judged-and-passed), and a silent rc 3 would recreate the very
# rc-confusion the split removes. Each accepted status must carry the tier's own
# terminal token, so walk every status a stub can return.
for stub_rc in 0 3 2; do
  printf '#!/bin/sh\nexit %s\n' "$stub_rc" > "$stub_bin/ruby"
  set +e
  out="$(PATH="$stub_bin:$PATH" bash "$SYNC_SCRIPT" "$REPO" 2>&1)"
  rc=$?
  set -e
  assert_rc "$rc" 2 "a silent subset interpreter exiting $stub_rc must fail closed as infra"
  assert_contains "sync_subset_infra_failed rc=$stub_rc" "$out" "infra marker names the unattested status $stub_rc"
  assert_not_contains "sync_semantic_check_ok" "$out" "no ok token when the subset tier emitted no terminal token (rc $stub_rc)"
  assert_not_contains "sync_semantic_blocking_failed" "$out" "an unattested status $stub_rc must not be diagnosed as a policy violation"
done
# Counterpart: a genuine declared violation still lands on rc 1 with the
# blocking verdict, so the split did not turn real findings into infra.
replace_in_file "$SEC4" "q2-canonical: 伪造,篡改," "q2-canonical: "
run_sync
assert_rc "$rc" 1 "a declared subset violation must still block at rc 1"
assert_contains "escapes the canonical predicate set" "$out" "the declared violation is named"
assert_contains "sync_semantic_blocking_failed" "$out" "the blocking verdict is still emitted"
git -C "$REPO" checkout -- skills/requirement-doc-writer/references/security-four-questions.md

echo "test_check_sync_pointers: ok"
