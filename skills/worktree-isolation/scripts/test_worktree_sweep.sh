#!/usr/bin/env bash
# Deterministic behavior suite for skills/worktree-isolation/scripts/worktree-sweep.sh.
#
# The worktree-isolation skill's cleanup rule leans on sweep's has_local_state
# as the mechanical arm ("对任何 ignored/未跟踪/脏文件机械判 KEEP"). This suite
# pins that property (and the inverse) on synthetic repos so the claim the rule
# cites stays behavior-true. Probes pin: exit codes, KEEP/REMOVE lines, and
# that dry-run never mutates. Requires git >= 2.32.
set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd -P)"
SWEEP="${SWEEP:-$SCRIPT_DIR/worktree-sweep.sh}"
[ -f "$SWEEP" ] || { echo "FAIL: sweep not found: $SWEEP" >&2; exit 1; }
command -v git >/dev/null 2>&1 || { echo "FAIL: git required" >&2; exit 1; }

export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_CEILING_DIRECTORIES

ROOT=$(mktemp -d "${SUITE_TMPDIR:-/tmp}/worktree-sweep-test.XXXXXX") || exit 1
ROOT=$(cd "$ROOT" && pwd -P)
trap 'rm -rf "$ROOT"' EXIT
pass=0; fail=0
note() { fail=$((fail+1)); PROBE_BAD=1; printf 'FAIL  %s\n' "$1" >&2; }
ok()   { [ "${PROBE_BAD:-0}" -eq 0 ] && pass=$((pass+1)); }
begin() { PROBE_BAD=0; }

# mk_repo <dir> — repo with two commits on main plus a fake origin/HEAD so the
# sweep can confirm the default branch. Sets R_SHA2.
#
# `dev` MUST be strictly AHEAD of main, not a second name for main's tip: the
# sweep classifies any target whose commit equals the default-branch commit as a
# DEFAULT target, empties SWEEP_TARGETS, and short-circuits every candidate at the
# conservative "default target requires platform MR evidence" KEEP — before
# has_local_state and before the ancestor check ever run. With dev==main every
# probe below would pass for the wrong reason (verified: the suite stayed green
# with merged_into_any stubbed to always-true). commit-tree keeps this
# identity-independent and needs no worktree.
mk_repo() {
  git init -q -b main "$1" || return 1
  git -C "$1" -c user.email=t@t -c user.name=t commit -q --allow-empty -m c1
  C1=$(git -C "$1" rev-parse HEAD)
  git -C "$1" -c user.email=t@t -c user.name=t commit -q --allow-empty -m c2
  R_SHA2=$(git -C "$1" rev-parse HEAD)
  git -C "$1" update-ref refs/remotes/origin/main "$R_SHA2"
  git -C "$1" symbolic-ref refs/remotes/origin/HEAD refs/remotes/origin/main
  DEV_SHA=$(git -C "$1" -c user.email=t@t -c user.name=t commit-tree \
    "$(git -C "$1" rev-parse "$R_SHA2^{tree}")" -p "$R_SHA2" -m dev-ahead) || return 1
  [ -n "$DEV_SHA" ] || return 1
  git -C "$1" update-ref refs/heads/dev "$DEV_SHA"
  # Guard the fixture invariant itself: a dev that collapses onto main silently
  # re-degrades every probe into the default-target branch.
  [ "$DEV_SHA" != "$R_SHA2" ] || return 1
}

# add_side <repo> — worktree whose branch tip is an ancestor of dev (sweepable
# candidate). Uses C1 so it is behind.
add_side() {
  git -C "$1" worktree add -q -b side "$1-side" "$C1"
}

# assert_keep <probe> <path> <reason-regex> <output> — the candidate path itself
# must carry a KEEP line with the expected reason. A bare `grep -q KEEP` is
# always satisfied by the main worktree's own KEEP line, so it proves nothing.
assert_keep() {
  printf '%s\n' "$4" | grep -q "^ *KEEP  *$2 .*$3" \
    || note "$1: no KEEP for $2 matching /$3/: $4"
}

# P1: ignored file blocks removal (the property the skill rule cites)
begin
d1="$ROOT/p1"; mk_repo "$d1" || exit 1
add_side "$d1"
echo 'data' > "$d1-side/out.dat" && printf 'out.dat\n' > "$d1-side/.gitignore"
OUT=$(cd "$d1" && bash "$SWEEP" dev 2>&1); RC=$?
[ "$RC" -eq 0 ] || note "p1: dry-run exit $RC on ignored-only worktree, want 0"
assert_keep p1 "$d1-side" 'ignored' "$OUT"
[ -d "$d1-side" ] || note "p1: dry-run removed an ignored-file worktree"
ok

# P1b: same ignored-file property under --apply (removal mode): the candidate is
# KEEP'd for the ignored-file reason and nothing is removed. Per the script's
# contract a blocked worktree is skipped per-worktree, not batch-aborting, so the
# rest of the sweep is expected to keep running.
begin
d1b="$ROOT/p1b"; mk_repo "$d1b" || exit 1
add_side "$d1b"
echo 'data' > "$d1b-side/out.dat" && printf 'out.dat\n' > "$d1b-side/.gitignore"
OUT=$(cd "$d1b" && bash "$SWEEP" dev --apply 2>&1); RC=$?
[ "$RC" -eq 0 ] || note "p1b: --apply exit $RC, want 0"
assert_keep p1b "$d1b-side" 'ignored' "$OUT"
[ -d "$d1b-side" ] || note "p1b: --apply removed an ignored-file worktree"
case "$OUT" in *"removed=0"*) : ;; *) note "p1b: expected removed=0: $OUT" ;; esac
ok

# P1c: --include-ignored is the script's own bypass of the ignored-file KEEP and
# it DOES destroy gitignored data products. Pinned so the 收尾 rule's ban on
# reaching for it stays behavior-grounded rather than prose-only.
begin
d1c="$ROOT/p1c"; mk_repo "$d1c" || exit 1
git -C "$d1c" worktree add -q -b side "$d1c-side" "$C1"
printf 'out.dat\n' > "$d1c-side/.gitignore"
git -C "$d1c-side" add .gitignore
git -C "$d1c-side" -c user.email=t@t -c user.name=t commit -q -m gitignore
# dev must still contain side's tip, so the only thing left blocking is the ignored file
side_tip=$(git -C "$d1c-side" rev-parse HEAD)
dev_tip=$(git -C "$d1c" -c user.email=t@t -c user.name=t commit-tree \
  "$(git -C "$d1c" rev-parse "$side_tip^{tree}")" -p "$side_tip" -m dev-ahead)
[ -n "$dev_tip" ] || { note "p1c fixture: commit-tree produced empty dev_tip"; exit 1; }
git -C "$d1c" update-ref refs/heads/dev "$dev_tip"
echo 'precious' > "$d1c-side/out.dat"
OUT=$(cd "$d1c" && bash "$SWEEP" dev --apply 2>&1); RC=$?
[ "$RC" -eq 0 ] || note "p1c: default --apply exit $RC, want 0"
assert_keep p1c "$d1c-side" 'ignored' "$OUT"
[ -d "$d1c-side" ] || note "p1c: default --apply removed an ignored-only worktree"
OUT=$(cd "$d1c" && bash "$SWEEP" dev --apply --include-ignored 2>&1); RC=$?
[ "$RC" -eq 0 ] || note "p1c: --include-ignored --apply exit $RC, want 0 (documented success contract)"
[ -e "$d1c-side/out.dat" ] && note "p1c: --include-ignored did NOT delete the ignored product; the rule's ban assumes it does: $OUT"
case "$OUT" in *"removed=1"*) : ;; *) note "p1c: --include-ignored expected removed=1: $OUT" ;; esac
ok

# P1d: the KEEP line for an ignored/dirty worktree must SHOW the offending entries.
# The cleanup rule asks the operator to grade what is there by recompute cost before
# reaching for --include-ignored; a bare "ignored files present" reason gives them
# nothing to grade, which is what makes a batch-wide waiver blind.
begin
d1d="$ROOT/p1d"; mk_repo "$d1d" || exit 1
add_side "$d1d"
printf 'big.feather\n' > "$d1d-side/.gitignore"
echo 'expensive' > "$d1d-side/big.feather"
OUT=$(cd "$d1d" && bash "$SWEEP" dev 2>&1); RC=$?
[ "$RC" -eq 0 ] || note "p1d: dry-run exit $RC, want 0"
printf '%s\n' "$OUT" | grep -q 'big\.feather' \
  || note "p1d: KEEP output does not name the ignored entry, so recompute cost cannot be judged from it: $OUT"
ok

# P1e: --include-ignored is batch-wide BY DESIGN — it is not a per-worktree picker.
# Pinned deliberately, not as an aspiration: the risk owner chose usability here
# (nearly every project's tests emit ignored artifacts, so per-item confirmation
# would gate every cleanup). The mitigation is P1d's visible KEEP detail plus the
# rule's read-before-you-sweep step, NOT a selection prompt. If someone later adds
# per-worktree selection, this probe is the one that must be rewritten on purpose.
begin
d1e="$ROOT/p1e"; mk_repo "$d1e" || exit 1
git -C "$d1e" worktree add -q -b cache-only "$d1e-cache" "$C1"
git -C "$d1e" worktree add -q -b data-only "$d1e-data" "$C1"
printf 'node_modules/\ndata/\n' > "$d1e/.gitignore"
git -C "$d1e" add .gitignore
git -C "$d1e" -c user.email=t@t -c user.name=t commit -q -m gitignore
for b in cache-only data-only; do
  git -C "$d1e" branch -f "$b" main >/dev/null 2>&1
done
git -C "$d1e-cache" checkout -q cache-only 2>/dev/null; git -C "$d1e-cache" reset -q --hard main
git -C "$d1e-data" checkout -q data-only 2>/dev/null; git -C "$d1e-data" reset -q --hard main
mkdir -p "$d1e-cache/node_modules" && echo x > "$d1e-cache/node_modules/dep.js"
mkdir -p "$d1e-data/data" && echo 'expensive' > "$d1e-data/data/big.feather"
dev_tip=$(git -C "$d1e" -c user.email=t@t -c user.name=t commit-tree \
  "$(git -C "$d1e" rev-parse 'main^{tree}')" -p "$(git -C "$d1e" rev-parse main)" -m dev-ahead)
[ -n "$dev_tip" ] || { note "p1e fixture: empty dev_tip"; exit 1; }
git -C "$d1e" update-ref refs/heads/dev "$dev_tip"
OUT=$(cd "$d1e" && bash "$SWEEP" dev 2>&1); RC=$?
[ "$RC" -eq 0 ] || note "p1e: dry-run exit $RC, want 0"
# Default run: both kept, and both name their ignored payload so the operator can tell them apart.
printf '%s\n' "$OUT" | grep -q 'node_modules' || note "p1e: cache worktree payload not shown: $OUT"
printf '%s\n' "$OUT" | grep -q 'data/' || note "p1e: data worktree payload not shown: $OUT"
OUT=$(cd "$d1e" && bash "$SWEEP" dev --apply --include-ignored 2>&1); RC=$?
[ "$RC" -eq 0 ] || note "p1e: --include-ignored --apply exit $RC, want 0"
[ -d "$d1e-cache" ] && note "p1e: cache-only worktree survived --include-ignored: $OUT"
[ -d "$d1e-data" ] && note "p1e: ACCEPTED-RISK CHANGED — the data worktree now survives --include-ignored; if that is intended, rewrite this probe and the SKILL.md criterion together: $OUT"
ok

# P2: dirty untracked (not ignored) blocks removal
begin
d2="$ROOT/p2"; mk_repo "$d2" || exit 1
add_side "$d2"
echo 'x' > "$d2-side/loose.txt"
OUT=$(cd "$d2" && bash "$SWEEP" dev --apply 2>&1); RC=$?
[ "$RC" -eq 0 ] || note "p2: --apply exit $RC, want 0 (non-zero = unscanned, stop)"
assert_keep p2 "$d2-side" 'untracked' "$OUT"
[ -d "$d2-side" ] || note "p2: worktree removed despite untracked file"
# --include-ignored relaxes ONLY the ignored class; real untracked work must still
# block, otherwise that flag would silently discard uncommitted work too.
OUT=$(cd "$d2" && bash "$SWEEP" dev --apply --include-ignored 2>&1); RC=$?
[ "$RC" -eq 0 ] || note "p2: --include-ignored --apply exit $RC, want 0"
assert_keep p2 "$d2-side" 'untracked' "$OUT"
[ -e "$d2-side/loose.txt" ] || note "p2: --include-ignored discarded a real untracked file"
ok

# P2b: an UNSCANNABLE worktree (git status fails) must be KEEP, never read as
# clean. Empty output from a failed scan is the false negative the manual
# pre-scan rule forbids ("必须 exit 0"); sweep's built-in check must match it,
# because the 收尾 rule exempts sweep runs from the manual pre-scan.
begin
d2b="$ROOT/p2b"; mk_repo "$d2b" || exit 1
add_side "$d2b"
printf 'out.dat\n' > "$d2b-side/.gitignore"
echo 'precious' > "$d2b-side/out.dat"
side_gitdir=$(git -C "$d2b-side" rev-parse --absolute-git-dir)
printf 'GARBAGE' > "$side_gitdir/index"     # corrupt index -> status exits non-zero, empty stdout
git -C "$d2b-side" status --porcelain >/dev/null 2>&1 \
  && note "p2b fixture: git status still succeeds, unscannable case not reproduced"
if [ "${PROBE_BAD:-0}" -eq 0 ]; then
  OUT=$(cd "$d2b" && bash "$SWEEP" dev 2>&1); RC=$?
  [ "$RC" -eq 0 ] || note "p2b: dry-run exit $RC, want 0"
  assert_keep p2b "$d2b-side" 'unscannable' "$OUT"
  printf '%s\n' "$OUT" | grep -q 'WOULD-REMOVE' \
    && note "p2b: unscannable worktree listed as WOULD-REMOVE (dry-run KEEP list is the preservation surface): $OUT"
  [ -e "$d2b-side/out.dat" ] || note "p2b: dry-run destroyed the ignored product"
fi
ok

# P3: clean integrated worktree IS removed (the removal arm works).
begin
# side's own commit must sit on dev but NOT on main (else it is a conservative
# default-target KEEP by design).
d3="$ROOT/p3"; mk_repo "$d3" || exit 1
git -C "$d3" worktree add -q -b side "$d3-side" "$C1"
git -C "$d3-side" -c user.email=t@t -c user.name=t commit -q --allow-empty -m side-only
side_tip=$(git -C "$d3-side" rev-parse HEAD)
dev_tip=$(git -C "$d3" -c user.email=t@t -c user.name=t commit-tree "$(git -C "$d3" rev-parse "$side_tip^{tree}")" -p "$side_tip" -m dev-ahead)
[ -n "$dev_tip" ] || { note "p3 fixture: commit-tree produced empty dev_tip"; exit 1; }
git -C "$d3" update-ref refs/heads/dev "$dev_tip"
OUT=$(cd "$d3" && bash "$SWEEP" dev --apply 2>&1); RC=$?
[ "$RC" -eq 0 ] || note "p3: --apply exit $RC, want 0 (documented success contract)"
[ -d "$d3-side" ] && note "p3: clean integrated worktree not removed: $OUT"
case "$OUT" in *"removed=1"*) ok ;; *) note "p3: expected removed=1: $OUT" ;; esac

# P4: dry-run mutates nothing — with a REAL removal candidate present (clean +
# integrated), so "nothing happened" is a property of dry-run, not of an empty
# candidate set.
begin
d4="$ROOT/p4"; mk_repo "$d4" || exit 1
add_side "$d4"
before=$(git -C "$d4" worktree list --porcelain | grep -c '^worktree ')
OUT=$(cd "$d4" && bash "$SWEEP" dev 2>&1); RC=$?
[ "$RC" -eq 0 ] || note "p4: dry-run exit $RC"
printf '%s\n' "$OUT" | grep -q "^ *WOULD-REMOVE  *$d4-side " \
  || note "p4: no WOULD-REMOVE for the candidate, so dry-run had nothing to withhold: $OUT"
after=$(git -C "$d4" worktree list --porcelain | grep -c '^worktree ')
[ "$before" = "$after" ] || note "p4: dry-run changed worktree count $before -> $after"
[ -d "$d4-side" ] || note "p4: dry-run removed the candidate"
ok

# P5: not-integrated worktree is kept (ancestor check has teeth). `feature` is
# ahead of dev, and dev is a non-default target, so merged_into_any is the
# predicate that must produce the KEEP — anchored on its own reason text.
begin
d5="$ROOT/p5"; mk_repo "$d5" || exit 1
git -C "$d5" worktree add -q -b feature "$d5-side"
git -C "$d5-side" -c user.email=t@t -c user.name=t commit -q --allow-empty -m ahead
OUT=$(cd "$d5" && bash "$SWEEP" dev --apply 2>&1); RC=$?
[ "$RC" -eq 0 ] || note "p5: --apply exit $RC, want 0 (non-zero = unscanned, stop)"
[ -d "$d5-side" ] || note "p5: not-integrated worktree removed"
assert_keep p5 "$d5-side" 'not merged' "$OUT"
ok

# P6a: an explicit DEFAULT-branch target is conservatively KEEP even when the
# candidate is clean and an ancestor (needs platform MR evidence, not ancestry).
begin
d6a="$ROOT/p6a"; mk_repo "$d6a" || exit 1
add_side "$d6a"
OUT=$(cd "$d6a" && bash "$SWEEP" main --apply 2>&1); RC=$?
[ "$RC" -eq 0 ] || note "p6a: --apply exit $RC, want 0 (non-zero = unscanned, stop)"
[ -d "$d6a-side" ] || note "p6a: default-target worktree removed (must be conservative KEEP)"
assert_keep p6a "$d6a-side" 'MR evidence' "$OUT"
ok

# P6b: removal never touches remote-tracking refs (绝不碰远端)
begin
d6b="$ROOT/p6b"; mk_repo "$d6b" || exit 1
git -C "$d6b" worktree add -q -b side "$d6b-side" "$C1"
git -C "$d6b-side" -c user.email=t@t -c user.name=t commit -q --allow-empty -m side-only
side_tip=$(git -C "$d6b-side" rev-parse HEAD)
dev_tip=$(git -C "$d6b" -c user.email=t@t -c user.name=t commit-tree "$(git -C "$d6b" rev-parse "$side_tip^{tree}")" -p "$side_tip" -m dev-ahead)
[ -n "$dev_tip" ] || { note "p6b fixture: commit-tree produced empty dev_tip"; exit 1; }
git -C "$d6b" update-ref refs/heads/dev "$dev_tip"
origin_main_before=$(git -C "$d6b" rev-parse refs/remotes/origin/main)
OUT=$(cd "$d6b" && bash "$SWEEP" dev --apply 2>&1); RC=$?
[ "$RC" -eq 0 ] || note "p6b: --apply exit $RC, want 0 (documented success contract)"
[ -d "$d6b-side" ] && note "p6b fixture: side not removed, remote check moot: $OUT"
if [ "${PROBE_BAD:-0}" -eq 0 ]; then
[ "$(git -C "$d6b" rev-parse refs/remotes/origin/main)" = "$origin_main_before" ] \
  || note "p6b: remote-tracking ref moved (sweep must not touch remotes)"
git -C "$d6b" rev-parse --verify --quiet refs/remotes/origin/main >/dev/null \
  || note "p6b: remote-tracking ref deleted (sweep must not touch remotes)"
grep -qE '^\s*git push' "$SWEEP" && note "p6b: sweep contains a push command"
fi
ok

# P6c: a release-named branch is never auto-removed, and the probe is differential:
# the SAME repo also holds an ordinary merged feature worktree that MUST be removed.
# Without that control the probe would pass under any blanket-KEEP regression (e.g.
# the conservative default-target path swallowing everything), proving nothing about
# the release predicate. `dev` is the non-default target so both candidates reach the
# ancestor check; both are merged, so the only thing separating them is the name.
begin
d6c="$ROOT/p6c"; mk_repo "$d6c" || exit 1
git -C "$d6c" worktree add -q -b release/v2 "$d6c-rel" "$C1"
git -C "$d6c" worktree add -q -b feature-x "$d6c-feat" "$C1"
rel_dev=$(git -C "$d6c" -c user.email=t@t -c user.name=t commit-tree "$(git -C "$d6c" rev-parse "$C1^{tree}")" -p "$C1" -m dev-ahead)
[ -n "$rel_dev" ] || { note "p6c fixture: commit-tree produced empty dev tip"; exit 1; }
git -C "$d6c" update-ref refs/heads/dev "$rel_dev"
OUT=$(cd "$d6c" && bash "$SWEEP" dev --apply 2>&1); RC=$?
[ "$RC" -eq 0 ] || note "p6c: --apply exit $RC, want 0"
[ -d "$d6c-rel" ] || note "p6c: release-named worktree was removed — release branches are never auto-deleted"
assert_keep p6c "$d6c-rel" 'release-named' "$OUT"
[ -d "$d6c-feat" ] && note "p6c: control feature worktree survived — the probe cannot tell a release KEEP from a blanket KEEP: $OUT"
ok

# P6d: the release predicate is name-based, case-insensitive, and matches anywhere in
# the branch name — pinned so a later tightening to a `release/*` prefix or a
# case-sensitive compare cannot silently narrow it.
begin
d6d="$ROOT/p6d"; mk_repo "$d6d" || exit 1
git -C "$d6d" worktree add -q -b hotfix-RELEASE-1.2 "$d6d-side" "$C1"
side_dev=$(git -C "$d6d" -c user.email=t@t -c user.name=t commit-tree "$(git -C "$d6d" rev-parse "$C1^{tree}")" -p "$C1" -m dev-ahead)
git -C "$d6d" update-ref refs/heads/dev "$side_dev"
OUT=$(cd "$d6d" && bash "$SWEEP" dev --apply 2>&1); RC=$?
[ "$RC" -eq 0 ] || note "p6d: --apply exit $RC, want 0"
[ -d "$d6d-side" ] || note "p6d: mixed-case substring release name was removed"
assert_keep p6d "$d6d-side" 'release-named' "$OUT"
ok

# P6e: the keyword set is deliberately NOT extensible — an `rc/` branch is swept.
# Pinned on purpose so a later "just make it configurable" re-add has to face the
# travel problem first (three adversarial rounds each found a config source that
# does not reach a fresh clone).
begin
d6e="$ROOT/p6e"; mk_repo "$d6e" || exit 1
git -C "$d6e" worktree add -q -b rc/1.2 "$d6e-side" "$C1"
rc_dev=$(git -C "$d6e" -c user.email=t@t -c user.name=t commit-tree "$(git -C "$d6e" rev-parse "$C1^{tree}")" -p "$C1" -m dev-ahead)
git -C "$d6e" update-ref refs/heads/dev "$rc_dev"
OUT=$(cd "$d6e" && bash "$SWEEP" dev 2>&1)
printf '%s\n' "$OUT" | grep -q "WOULD-REMOVE $d6e-side" \
  || note "p6e: rc/1.2 was protected — the keyword set must stay exactly the one documented keyword: $OUT"
ok

# P6: setup failure exits 2 with a visible message (no silent no-op)
begin
d6="$ROOT/p6"; mkdir -p "$d6"
OUT=$(cd "$d6" && bash "$SWEEP" dev --apply 2>&1); RC=$?
[ "$RC" -eq 2 ] || note "p6: non-repo exit $RC, want 2"
[ -n "$OUT" ] || note "p6: setup failure produced no message"
ok

# P7: suite self-sensitivity. The probes above only prove the CURRENT script
# behaves; they do not prove the suite would NOTICE if it stopped. That gap is
# not hypothetical here: an earlier revision of this suite stayed fully green
# with merged_into_any stubbed to always-true, because the fixture made `dev`
# equal to main's tip and every probe short-circuited at the default-target KEEP.
# So the mutation check is part of the suite, not a one-off local ritual: each
# mutant must make this same suite fail FOR THE RIGHT REASON. A bare non-zero exit
# is not that reason — a mutant that breaks syntax or fixture setup also exits
# non-zero, and banking that as "the suite is sensitive" is a false green wearing a
# RED's clothes. So each mutant must still parse (`bash -n`) AND the child's
# failure must name the probe that owns the mutated predicate. Child runs skip P7
# (no recursion) and their expected FAIL output is captured, not printed.
if [ "${SWEEP_SUITE_MUTATION_CHILD:-0}" = "0" ]; then
  MUT_DIR="$ROOT/mutants"; mkdir -p "$MUT_DIR"

  # mk_mutant <name> <literal-anchor-line> <line-to-insert-after-anchor>
  # Anchor matching is a literal substring test (index), not a regex, so the
  # shell-function anchors below need no escaping and cannot silently mis-match.
  mk_mutant() {
    awk -v anchor="$2" -v inject="$3" '
      { print }
      index($0, anchor) && !seen { print inject; seen = 1 }
    ' "$SWEEP" > "$MUT_DIR/$1.sh" || return 1
    # A refactor that moves the anchor must fail loudly, not silently produce a
    # mutant identical to the original (which would pass and prove nothing).
    grep -Fq -- "$3" "$MUT_DIR/$1.sh"
  }

  begin
  mk_mutant has_local_state_never_blocks 'has_local_state() {' '  return 1  # MUTANT' \
    || note "p7: could not build has_local_state mutant (anchor moved?)"
  mk_mutant merged_into_any_always_true 'merged_into_any() {' '  return 0  # MUTANT' \
    || note "p7: could not build merged_into_any mutant (anchor moved?)"
  # Drop the fail-closed branch by making its condition unreachable.
  sed 's/\[ "\$rc" -ne 0 \]/[ "$rc" -lt 0 ]/' "$SWEEP" > "$MUT_DIR/no_fail_closed.sh"
  cmp -s "$SWEEP" "$MUT_DIR/no_fail_closed.sh" \
    && note "p7: fail-closed mutation did not change the script (anchor moved?)"
  # The remaining protected predicates. The rule this suite implements says to iterate
  # EVERY protected predicate, not a memorable subset: three of them (the --include-ignored
  # relaxation, the KEEP payload listing, and the conservative default-target guard) each
  # decide whether a worktree gets deleted or its contents shown, and each could regress
  # with the earlier three-mutant loop still green.
  sed 's|out="$(git -C "$1" status --porcelain --untracked-files=all 2>/dev/null)"; rc=$?|out="$(git -C "$1" status --porcelain --untracked-files=all --ignored 2>/dev/null)"; rc=$?|' \
    "$SWEEP" > "$MUT_DIR/include_ignored_noop.sh"
  cmp -s "$SWEEP" "$MUT_DIR/include_ignored_noop.sh" \
    && note "p7: --include-ignored mutation did not change the script (anchor moved?)"
  sed 's|\[ -n "$HAS_LOCAL_STATE_SAMPLE" \] && printf|false \&\& printf|' \
    "$SWEEP" > "$MUT_DIR/state_sample_suppressed.sh"
  cmp -s "$SWEEP" "$MUT_DIR/state_sample_suppressed.sh" \
    && note "p7: state-sample mutation did not change the script (anchor moved?)"
  sed 's|elif \[ "${#SWEEP_TARGETS\[@\]}" -eq 0 \]; then|elif false; then|' \
    "$SWEEP" > "$MUT_DIR/default_target_guard_dropped.sh"
  cmp -s "$SWEEP" "$MUT_DIR/default_target_guard_dropped.sh" \
    && note "p7: default-target-guard mutation did not change the script (anchor moved?)"
  # Drop the release-name KEEP: release-named worktrees must then reach the removal
  # path, which p6c/p6d own. Replacing the predicate (not the branch) keeps the
  # mutation semantic — a commented-out line would break syntax and bank a broken
  # build as sensitivity.
  sed 's|^is_release_named() {|is_release_named() { return 1  # MUTANT|' \
    "$SWEEP" > "$MUT_DIR/release_guard_dropped.sh"
  cmp -s "$SWEEP" "$MUT_DIR/release_guard_dropped.sh" \
    && note "p7: release-guard mutation did not change the script (anchor moved?)"

  # <mutant> owns <probe-ids>: the probes that actually assert the mutated
  # predicate. Attribution is DIFFERENTIAL, not a substring match on aggregate
  # output — an unrelated probe or a collapsed teardown can fail while the owning
  # assertion still passes, and its name can appear in the log anyway. So the
  # mutant must flip EXACTLY these: every probe that fails under it must be in the
  # owning set (and at least one must be). The control side is this very run —
  # P7 only runs after the probes above, so requiring zero failures so far proves
  # the owning probes PASS unmutated.
  # Widen this set ONLY for a probe that genuinely asserts the mutated predicate
  # (p1c and p1e were added because both turn on the ignored-file KEEP and the
  # payload it prints — the differential check found them). Adding a probe that
  # does NOT assert the predicate, just to silence a foreign-failure report, is
  # the maintenance trap this whole mechanism exists to prevent: it re-blinds the
  # check while looking like a fix. If a mutant breaks something outside its
  # predicate, the mutant or the predicate is wrong — not this table.
  mutant_owner() {
    case "$1" in
      has_local_state_never_blocks)  printf 'p1 p1b p1c p1d p1e p2 p2b' ;;
      merged_into_any_always_true)   printf 'p5' ;;
      no_fail_closed)                printf 'p2b' ;;
      include_ignored_noop)          printf 'p1c p1e' ;;
      state_sample_suppressed)       printf 'p1d p1e' ;;
      default_target_guard_dropped)  printf 'p6a' ;;
      release_guard_dropped)         printf 'p6c p6d' ;;  # NOT p6e: it asserts rc/ IS swept, so it passes under this mutant either way
    esac
  }
  # A declared owner that no longer EXISTS must fail closed. Checking declarations only
  # against the IDs that failed is not enough: rename or delete an owning probe and, as
  # long as one other listed owner still fails, owned_hit stays 1 and foreign stays empty,
  # so the mutant is accepted while the declaration silently rots. The suite is its own
  # registry here — every probe reports through `note "<id>: …"`.
  owner_exists() { grep -q "note \"$1:" "$0"; }
  # Control run: if anything already failed, the owning probes are not known-good
  # unmutated and no attribution below means anything.
  [ "$fail" -eq 0 ] || note "p7: control run already has $fail failure(s) — differential attribution is meaningless until the clean suite is green"

  for mutant in has_local_state_never_blocks merged_into_any_always_true no_fail_closed \
                include_ignored_noop state_sample_suppressed default_target_guard_dropped \
                release_guard_dropped; do
    [ -s "$MUT_DIR/$mutant.sh" ] || continue
    # Fail closed on a stale declaration before trusting anything it says.
    for id in $(mutant_owner "$mutant"); do
      owner_exists "$id" \
        || note "p7: mutant '$mutant' declares owner '$id', which no longer exists in this suite — stale mapping, attribution cannot be trusted"
    done
    # A mutant that does not even parse proves nothing about the suite.
    bash -n "$MUT_DIR/$mutant.sh" 2>/dev/null \
      || { note "p7: mutant '$mutant' does not parse — a syntax-broken mutant cannot prove sensitivity"; continue; }
    SWEEP_SUITE_MUTATION_CHILD=1 SWEEP="$MUT_DIR/$mutant.sh" SUITE_TMPDIR="$MUT_DIR" \
      bash "$0" > "$MUT_DIR/$mutant.log" 2>&1
    child_rc=$?
    # Probe ids that actually failed under the mutant.
    failed_ids=$(sed -n 's/^FAIL  \([a-z0-9]*\):.*/\1/p' "$MUT_DIR/$mutant.log" | sort -u | tr '\n' ' ')
    owners=" $(mutant_owner "$mutant") "
    owned_hit=0; foreign=""
    for id in $failed_ids; do
      case "$owners" in *" $id "*) owned_hit=1 ;; *) foreign="$foreign $id" ;; esac
    done
    if [ "$child_rc" -eq 0 ]; then
      note "p7: mutant '$mutant' left the suite GREEN — the suite is blind to that predicate"
    elif [ "$owned_hit" -eq 0 ]; then
      note "p7: mutant '$mutant' failed the suite, but no OWNING probe (${owners# }) reported it — collateral failure, not sensitivity (failed:${failed_ids:-none})"
    fi
    [ -z "$foreign" ] \
      || note "p7: mutant '$mutant' also broke non-owning probe(s)$foreign — it flips more than its predicate, so the RED is not attributable"
    # A mutant must not collapse the fixtures: the child still has to RUN the suite.
    grep -q '^worktree_sweep: ' "$MUT_DIR/$mutant.log" \
      || note "p7: mutant '$mutant' never reached the suite summary — fixtures collapsed, so the RED is not attributable"
  done
  ok
fi

echo "worktree_sweep: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
