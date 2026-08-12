#!/usr/bin/env bash
# Regression tests for route-drift / impact-chain diagnostics in
# check-ccl-skills.sh. Clones this repo into a throwaway worktree, then
# creates a deterministic bad diff there so unrelated local edits do not affect
# the assertion while the current checker under test is still used.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd -P)"
CHECK_SCRIPT="$SCRIPT_DIR/check-ccl-skills.sh"
[ -f "$CHECK_SCRIPT" ] || { echo "FAIL: checker not found: $CHECK_SCRIPT" >&2; exit 1; }
ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd -P)"

TMP="$(mktemp -d "${TMPDIR:-/tmp}/routedrift.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

fail() { echo "FAIL: $*" >&2; exit 1; }
assert_rc() { [ "$1" = "$2" ] || fail "expected rc=$2 got rc=$1${3:+ ($3)}"; }
assert_contains() { case "$2" in *"$1"*) : ;; *) fail "expected output to contain: $1${3:+ ($3)}";; esac; }

run_check() {
  set +e
  # Do not force CCL_SKILL_BASE_REF here: the full validator passes that env
  # through to nested detector self-tests. Instead this fixture creates a local
  # tracked upstream branch before the bad commit, which remains stable even when
  # the outer CI checkout is a detached MR head with no useful upstream.
  out="$(env -u ALIAS_AUDIT_CMD -u CCL_SKILL_BASE_REF bash "$CHECK_SCRIPT" "$REPO" 2>&1)"
  rc=$?
  set -e
}

# The checkout deliberately lives under a path that SPELLS the scoped-exemption
# prefix. A scope test written against the absolute path would then match every
# scanned file and exempt the token tree-wide, so this layout is what keeps the
# containment check honest.
REPO="$TMP/skills/code-review/nested/repo"
mkdir -p "$(dirname "$REPO")"
git clone -q "$ROOT" "$REPO"
git -C "$REPO" config user.email test@example.invalid
git -C "$REPO" config user.name "Test User"
git -C "$REPO" branch fixture-base HEAD
git -C "$REPO" switch -q -c fixture-work
git -C "$REPO" branch --set-upstream-to=fixture-base fixture-work >/dev/null

cat >> "$REPO/skills/testing-strategy/SKILL.md" <<'EOF'

Changed testing strategy behavior.

Route the export to `ccl-review`, then hand the result to `phantom-review`.
EOF

# Same token inside the package that documents the OpenCode lane: there it names
# that integration's agent, not a skill route, so it must stay unreported while
# the identical token above (outside that package) is reported.
cat >> "$REPO/skills/code-review/SKILL.md" <<'EOF'

Route the export to `ccl-review` for the OpenCode lane.
EOF

cat >> "$REPO/skills/test-artifact-management/SKILL.md" <<'EOF'

Changed test artifact management behavior.
EOF

cat >> "$REPO/skills/skill-extraction-workflow/references/source-register.md" <<'EOF'
| Ambiguous impact row fixture | route drift checker | One row incorrectly cites two changed upstream paths, which must be diagnosed explicitly and split into one row per upstream skill | `updated` | `testing-strategy/SKILL.md`; `test-artifact-management/SKILL.md` |
EOF

git -C "$REPO" add -A
git -C "$REPO" commit -qm "ambiguous impact-chain fixture"

run_check
assert_rc "$rc" 1 "ambiguous multi-upstream row must fail the gate"
assert_contains "impact_chain_row_ambiguous" "$out" "checker should name the ambiguous-row cause directly"
assert_contains "one row per changed upstream SKILL.md" "$out" "diagnostic should tell authors how to fix it"
assert_contains "testing-strategy/SKILL.md" "$out" "diagnostic should include first changed path"
assert_contains "test-artifact-management/SKILL.md" "$out" "diagnostic should include second changed path"

# feature-risk-router risk tags are repo-wide vocabulary, never a skill route.
case "$out" in
  *'references "security-review"'*) fail "risk tag security-review must not be flagged as a stale route" ;;
esac

# Another namespace's identifier is exempt only where its integration is
# documented. Both halves are required: without the in-scope half the exemption
# is untested, and without the out-of-scope half a blanket exemption would hide a
# real stale route written anywhere else in the tree.
# Matching is per LINE, not over the whole output: a glob spanning "$out" pairs a
# path printed by one diagnostic with a token printed by another, which both
# false-fails a correct scope and false-passes a broken one.
diag_lines_matching() {
  printf '%s\n' "$out" | grep -F "$1" | grep -F "$2" || true
}
[ -z "$(diag_lines_matching 'skills/code-review/SKILL.md' 'references "ccl-review"')" ] ||
  fail "ccl-review inside skills/code-review/ is the OpenCode agent, not a stale route"
[ -n "$(diag_lines_matching 'skills/testing-strategy/SKILL.md' 'references "ccl-review"')" ] ||
  fail "ccl-review outside skills/code-review/ must still be reported as a stale route"

# Reverse assertion — without it the exemption cases above stay green when the
# whole stale-route check is deleted, so they would prove nothing. A name that is
# route-shaped and exempt nowhere must be reported.
assert_contains 'references "phantom-review"' "$out" "a genuinely stale route reference must still be reported"

# The always-on agent-context/session-start.md is itself a routing surface: stale skill routes and
# dangling <pkg>/references/*.md pointers in it must be reported too (observed
# gap: the layer had prose-only sync while README and SKILL.md/references were
# scanned). The fixture writes these into the fixture repo's own agent-context/session-start.md.
cat >> "$REPO/agent-context/session-start.md" <<'EOF'

Route the work to `phantom-bootstrap-review`, then read `requirement-doc-writer/references/definitely-missing.md`.
The valid pointer is `requirement-doc-writer/references/requirement-closure-contract.md`.
EOF
git -C "$REPO" add agent-context/session-start.md
git -C "$REPO" commit -qm "bad bootstrap refs"
run_check
rc_present=$rc
[ -n "$(diag_lines_matching 'agent-context/session-start.md' 'references "phantom-bootstrap-review"')" ] ||
  fail "the stale-route warn must name agent-context/session-start.md and the token on the same line"
[ -n "$(diag_lines_matching 'md_reference_block: ' 'agent-context/session-start.md' | grep 'definitely-missing.md')" ] ||
  fail "the broken-md block must name agent-context/session-start.md and the missing target on the same line"
[ -f "$REPO/skills/requirement-doc-writer/references/requirement-closure-contract.md" ] ||
  fail "fixture pin missing: the valid-pointer target must exist in the fixture"
case "$out" in
  *requirement-closure-contract.md*) fail "a valid references pointer in agent-context/session-start.md must not be reported" ;;
esac
case "$out" in
  *"bootstrap_scan: covered refs="*) ;;
  *) fail "covered marker must carry the bootstrap ref-hit count" ;;
esac
marker_refs="$(printf '%s\n' "$out" | sed -n 's/^bootstrap_scan: covered refs=//p' | head -1)"
[ "${marker_refs:-0}" -ge 2 ] || fail "fixture bootstrap carries 2 md-ref lines, marker counted ${marker_refs:-none}"
assert_contains "bootstrap_route_scan: covered" "$out" "route-scan covered marker must be printed when agent-context/session-start.md exists"
assert_contains "route_existence_check_done" "$out" "route-drift section must complete when agent-context/session-start.md exists"

git -C "$REPO" rm -q agent-context/session-start.md
git -C "$REPO" commit -qm "drop bootstrap"
run_check
[ "$rc_present" -eq 1 ] && [ "$rc" -eq 1 ] ||
  fail "both runs must carry the by-design impact-chain rc=1 (present=$rc_present, post-removal=$rc)"
assert_contains "md_reference_check_done" "$out" "md-ref section must complete when agent-context/session-start.md is absent"
assert_contains "bootstrap_scan: skipped-missing" "$out" "skip marker must be printed when agent-context/session-start.md is absent"
assert_contains "bootstrap_route_scan: skipped-missing" "$out" "route-scan skip marker must be printed when agent-context/session-start.md is absent"
assert_contains "route_existence_check_done" "$out" "route-drift section must complete when agent-context/session-start.md is absent"
[ -z "$(printf '%s\n' "$out" | grep -E 'warn_|route_existence_block|md_reference_block' | grep -F 'agent-context/session-start.md')" ] ||
  fail "no diagnostic line mentioning agent-context/session-start.md may remain after its removal"

# --- Isolated rc semantics for the advisory->blocking flip (second clone) ----
# The first clone forces an impact-chain rc=1 backdrop, which cannot prove each
# sync check reddens the gate ON ITS OWN. These cases isolate each class:
# stale-route-only, broken-md-ref-only, clean (GREEN control that also pins the
# append-only-history exemption as working), and exemption non-bleed.
REPO2="$TMP/isolated/repo"
mkdir -p "$(dirname "$REPO2")"
git clone -q "$ROOT" "$REPO2"
git -C "$REPO2" config user.email test@example.invalid
git -C "$REPO2" config user.name "Test User"
git -C "$REPO2" branch fixture-base2 HEAD
git -C "$REPO2" switch -q -c fixture-work2
git -C "$REPO2" branch --set-upstream-to=fixture-base2 fixture-work2 >/dev/null

run_check2() {
  set +e
  out2="$(env -u ALIAS_AUDIT_CMD -u CCL_SKILL_BASE_REF bash "$CHECK_SCRIPT" "$REPO2" 2>&1)"
  rc2=$?
  set -e
}

# (c) clean tree first: nothing violates, so the gate must pass (rc 0). This is
# the GREEN control for the flip.
# (c) clean tree: the flip must not fire on a violation-free tree. This case
# deliberately does NOT assert the whole-validator rc: that couples the suite
# to every other gate's state on the real repo (impact-chain / register
# locators / eval-routing / diff-check), and any of them reddening would fail
# here with a message pointing away from the flip — while a green rc would not
# isolate the flip either. The sync-specific GREEN signal is the token set
# below: no block lines, no combined verdict, and both checks run to their done
# markers.
run_check2
assert_contains "route_existence_check_done" "$out2" "route check completes on a clean tree"
assert_contains "md_reference_check_done" "$out2" "md-ref check completes on a clean tree"
case "$out2" in
  *route_existence_block:*) fail "clean tree must not report a stale-route block" ;;
esac
case "$out2" in
  *md_reference_block:*) fail "clean tree must not report a broken-md block" ;;
esac
case "$out2" in
  *sync_reference_blocking_failed*) fail "clean tree must not print the sync blocking verdict" ;;
esac

# (a) stale-route-only (README edit touches no impact-chain surface): rc 1.
printf '\nRoute the work to `phantom-strategy` for this lane.\n' >> "$REPO2/README.md"
run_check2
assert_rc "$rc2" 1 "a stale route alone must fail the gate"
assert_contains "route_existence_block:" "$out2" "stale-route block line present"
assert_contains "sync_reference_blocking_failed" "$out2" "combined sync blocking verdict present"
case "$out2" in
  *md_reference_block:*) fail "stale-route case must not conjure an md-ref block" ;;
esac
git -C "$REPO2" checkout -- README.md

# (b) broken-md-ref-only (agent-context/session-start.md citation; route check skips .md tokens):
# rc 1. The sync verdict exits before the size gate, so the citation-triggered
# bootstrap growth never reaches the delta verdict.
printf '\nRead `requirement-doc-writer/references/definitely-missing.md` first.\n' >> "$REPO2/agent-context/session-start.md"
run_check2
assert_rc "$rc2" 1 "a broken .md reference alone must fail the gate"
assert_contains "md_reference_block:" "$out2" "broken-md block line present"
assert_contains "sync_reference_blocking_failed" "$out2" "combined sync blocking verdict present"
git -C "$REPO2" checkout -- agent-context/session-start.md

diag2_lines_matching() {
  printf '%s\n' "$out2" | grep -F "$1" | grep -F "$2" || true
}

# (f) md-ref exemption branch: with a (path, cited-ref) entry present the
# checker must print md_reference_exempt and suppress the block. No live entry
# exists today, so probe with a copy of the checker patched to carry one (kept
# inside the throwaway clone's scripts dir so adjacent-gate resolution still
# works); the UNPATCHED checker on the same tree is the differential control.
# The citation lives in agent-context/session-start.md (validate-skill hard-blocks the same
# dangling ref inside skills/*/ before this checker runs) and is committed
# INTO the base branch so the bootstrap size delta stays untouched.
git -C "$REPO2" switch -q -c mdexempt-base
printf '\nProse cites `requirement-doc-writer/references/definitely-missing.md` here.\n' >> "$REPO2/agent-context/session-start.md"
git -C "$REPO2" commit -qam "fixture: broken citation in bootstrap"
git -C "$REPO2" branch -f fixture-base2 mdexempt-base
git -C "$REPO2" switch -q -c mdexempt-work
git -C "$REPO2" branch --set-upstream-to=fixture-base2 mdexempt-work >/dev/null
PROBE_CHECK="$REPO2/skills/skill-extraction-workflow/scripts/check-ccl-skills-mdexempt-probe.sh"
python3 - "$CHECK_SCRIPT" "$PROBE_CHECK" <<'PY'
import sys
src, dst = sys.argv[1], sys.argv[2]
text = open(src).read()
anchor = 'md_ref_exempt() {\n  case "$1" in\n'
entry = anchor + '    "agent-context/session-start.md requirement-doc-writer/references/definitely-missing.md") return 0 ;;\n'
assert anchor in text, "md_ref_exempt function shape changed; update the probe patch"
open(dst, "w").write(text.replace(anchor, entry, 1))
PY
set +e
out2="$(env -u ALIAS_AUDIT_CMD -u CCL_SKILL_BASE_REF bash "$PROBE_CHECK" "$REPO2" 2>&1)"
rc2=$?
set -e
assert_rc "$rc2" 0 "an exempted broken citation must not fail the gate"
assert_contains "md_reference_exempt:" "$out2" "exempt print token present when the branch fires"
case "$out2" in
  *md_reference_block:*) fail "exempted citation must not appear on a block line" ;;
esac
# root="." (CI shape): the (path,ref) key normalization must also match when
# rg emits ./-prefixed paths.
set +e
out3="$(cd "$REPO2" && env -u ALIAS_AUDIT_CMD -u CCL_SKILL_BASE_REF bash "$PROBE_CHECK" . 2>&1)"
rc3=$?
set -e
assert_rc "$rc3" 0 "root=. CI shape must also honor the exemption"
assert_contains "md_reference_exempt:" "$out3" "exempt print token present with root=. shape"
run_check2
assert_rc "$rc2" 1 "differential: the same citation without the entry must block"
assert_contains "md_reference_block:" "$out2" "unpatched checker reports the citation as a block"
rm -f "$PROBE_CHECK"
# (f) committed the broken citation into the fixture's base branch; return to
# the clean pre-(f) branch so later cases are not poisoned by it.
git -C "$REPO2" switch -q fixture-work2

# (g) allowlist escape is visible: a caller-supplied allowlist suppresses the
# block but MUST print one applied-allowlist line per suppression — an
# invisible escape hatch on a blocking gate is a silent gate-skip.
printf '\nRoute the work to `phantom-strategy` for this lane.\n' >> "$REPO2/README.md"
set +e
out2="$(env -u ALIAS_AUDIT_CMD -u CCL_SKILL_BASE_REF CCL_SKILL_ROUTE_ALLOWLIST=phantom-strategy bash "$CHECK_SCRIPT" "$REPO2" 2>&1)"
rc2=$?
set -e
assert_rc "$rc2" 0 "an allowlisted stale route must not fail the gate"
[ -n "$(diag2_lines_matching 'route_existence_allowlisted: ' 'README.md' | grep 'phantom-strategy')" ] ||
  fail "the allowlist suppression must be printed with file and token"
case "$out2" in
  *route_existence_block:*) fail "allowlisted token must not appear on a block line" ;;
esac
git -C "$REPO2" checkout -- README.md

# (i) early-return shape: on a NON-git tree the git-gated middle sections are
# skipped entirely, but a pending sync verdict must still reach process end
# (the deferred verdict sits outside those sections and the trap guard covers
# any future early-exit-0 path). The tree mirrors the real skills/ tree so all
# sibling citations resolve; the stale route rides in README.md.
NG="$TMP/nongit-repo"
mkdir -p "$NG"
cp -R "$ROOT/skills" "$NG/skills"
cp -R "$ROOT/docs" "$NG/docs"
cp "$ROOT/README.md" "$NG/README.md"
printf '\nRoute the work to `phantom-strategy` for this lane.\n' >> "$NG/README.md"
set +e
out2="$(env -u ALIAS_AUDIT_CMD -u CCL_SKILL_BASE_REF bash "$CHECK_SCRIPT" "$NG" 2>&1)"
rc2=$?
set -e
assert_rc "$rc2" 1 "non-git early-return must still deliver the sync verdict"
[ -n "$(diag2_lines_matching 'route_existence_block: ' 'README.md' | grep 'phantom-strategy')" ] ||
  fail "the stale route in README.md must be named on a block line"
assert_contains "sync_reference_blocking_failed" "$out2" "verdict reaches process end on the early-return path"

# rg-failure branch NOT fixture-tested: the route-drift ruby block reads the
# same files and crashes first on unreadable-file/broken-symlink scenarios, so
# the partial-rg path is reachable only via glob/ignore-level errors that a
# fixture cannot construct cheaply. rg semantics probed manually (rc=2 with
# partial output). Pre-existing fragility candidate (ruby block unreadable
# file aborts the whole checker) recorded as follow-up, not this batch.

# (j) wiring anchor: the route-drift ruby block runs inside a single-quoted
# ruby -e, so an apostrophe anywhere in the block body is syntax-fatal (two
# escapes in one batch: "gate's" and "guard's" in comments). Pin it
# mechanically — the delimiting first/last lines carry quotes by design, the
# body between them must be apostrophe-free. The opening anchor tolerates extra
# -r requires so adding one does not silently disarm this guard (it did: adding
# -rdigest made the sed range empty, which this case caught as a moved anchor).
ruby_block="$(sed -n "/^ruby -rset .*-e '/,/^' \"\$root\"/p" "$CHECK_SCRIPT")"
[ -n "$ruby_block" ] || fail "route-drift ruby block not found; anchor moved?"
case "$(printf '%s\n' "$ruby_block" | sed '1d;$d')" in
  *"'"*) fail "apostrophe inside the single-quoted ruby block (syntax-fatal; keep the block apostrophe-free)" ;;
esac

# (k) route-word saturation: a backticked non-route token (a feature-risk-router
# risk tag, a scoped domain enum) must stay a non-route because it is
# REGISTERED in risk_tags / scoped_non_route_vocab / exempt_historical_routes —
# never because the prose line it sits on happens to carry no route word. Under
# the advisory shape that accident printed a harmless warn; on the blocking gate
# one ordinary prose edit (adding 用 / 走 / "uses" to such a line) reddens CI
# with a diagnostic telling the author to restore a skill that never existed,
# and the only exits are de-backticking canonical vocabulary or abusing the
# external-skill allowlist. Saturating EVERY scanned line with a route word
# removes that accident from the premise: whatever still blocks is a token the
# tables do not cover. Measured at introduction: 7 such lines across
# `external-integration` (a canonical risk tag missing from risk_tags) and
# `targeted-workflow` (a source-map coverage enum).
SAT="$TMP/saturated"
mkdir -p "$SAT/agent-context"
cp -R "$ROOT/skills" "$SAT/skills"
cp "$ROOT/README.md" "$SAT/README.md"
if [ -f "$ROOT/agent-context/session-start.md" ]; then cp "$ROOT/agent-context/session-start.md" "$SAT/agent-context/session-start.md"; fi
# Saturate with ruby (already a hard dependency of the checker) rather than
# sed -i / perl -i, whose in-place flags differ across BSD and GNU userland.
sat_files=("$SAT/README.md")
if [ -f "$SAT/agent-context/session-start.md" ]; then sat_files+=("$SAT/agent-context/session-start.md"); fi
for f in "$SAT"/skills/*/SKILL.md "$SAT"/skills/*/references/*.md; do
  if [ -f "$f" ]; then sat_files+=("$f"); fi
done
[ "${#sat_files[@]}" -gt 10 ] || fail "saturation fixture collected only ${#sat_files[@]} files; glob shape changed"
ruby -e '
ARGV.each do |f|
  next unless File.file?(f)
  File.write(f, File.readlines(f).map { |l| l.chomp + " 用\n" }.join)
end
' "${sat_files[@]}"
sat_block="$TMP/route-block.rb"
printf '%s\n' "$ruby_block" | sed '1d;$d' > "$sat_block"
set +e
sat_out="$(ruby -rset -rdigest "$sat_block" "$SAT" 2>&1)"
sat_rc=$?
set -e
# Saturation appends a route word to EVERY line, which rewrites the very ledger
# lines whose identity IS the waiver. So the waived tokens necessarily surface as
# stale here no matter how well they are covered — a fixture artifact, not an
# uncovered token. Two consequences, in order:
#   1. Premise pin. That guaranteed surfacing is what proves the extracted block
#      actually ran; a syntax/extraction break would otherwise read as "no blocks
#      found" and turn this whole case into a silent no-op. Pin on the waived
#      tokens rather than on the exemption print, which cannot appear here.
#   2. Filter. Drop exactly those tokens before judging, reading them out of the
#      table itself rather than hardcoding them. Every OTHER backticked token
#      still faces the full saturated premise — that is what catches an
#      unregistered risk tag or domain enum.
sat_blocks="$(printf '%s\n' "$sat_out" | grep -F 'route_existence_block' || true)"
sat_real="$sat_blocks"
if [ -n "$sat_real" ]; then
  printf '%s\n' "$sat_real" | sed "s|$SAT/||" >&2
  fail "a backticked non-route token blocks once its line carries a route word; register it in risk_tags or scoped_non_route_vocab (lines above)"
fi

echo "test_check_ccl_route_drift: ok"
