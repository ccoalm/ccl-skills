#!/usr/bin/env bash
# Regression tests for the impact-chain gate: owner-path coverage, required
# behavioral evidence, observed-failure firing paths, and upstream-owner routing.
# An upstream owner's references/ and scripts/ ship decision-surface / operational
# behavior just like its SKILL.md, so editing them must also require a complete
# source-register impact-chain row.
#
# Clones this repo into a throwaway worktree, then drives deterministic diffs on
# per-case branches so unrelated local edits do not affect the assertions while the
# current checker under test is still used.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd -P)"
CHECK_SCRIPT="${CHECK_SCRIPT_UNDER_TEST:-$SCRIPT_DIR/check-ccl-skills.sh}"
[ -f "$CHECK_SCRIPT" ] || { echo "FAIL: checker not found: $CHECK_SCRIPT" >&2; exit 1; }
CHECK_SCRIPT_DIR="$(ruby -e 'puts File.dirname(File.realpath(ARGV.fetch(0)))' "$CHECK_SCRIPT")"
GATE_SCRIPT="$CHECK_SCRIPT_DIR/impact-chain-gate.rb"
[ -f "$GATE_SCRIPT" ] || { echo "FAIL: impact-chain gate not found: $GATE_SCRIPT" >&2; exit 1; }
ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd -P)"

TMP="$(mktemp -d "${TMPDIR:-/tmp}/icrefscripts.XXXXXX")"
# Preserve the script's exit status across cleanup: on macOS bash 3.2 a bare
# `rm -rf` EXIT trap OVERWRITES a set -u/-e abort status with 0, turning a
# mid-suite crash into a false green.
trap 'rc=$?; rm -rf "$TMP"; exit $rc' EXIT

fail() { echo "FAIL: $*" >&2; exit 1; }
assert_rc() { [ "$1" = "$2" ] || fail "expected rc=$2 got rc=$1${3:+ ($3)}"; }
assert_contains() { case "$2" in *"$1"*) : ;; *) fail "expected output to contain: $1${3:+ ($3)}";; esac; }
assert_not_contains() { case "$2" in *"$1"*) fail "expected output NOT to contain: $1${3:+ ($3)}";; *) : ;; esac; }

REPO="$TMP/repo"
git clone -q "$ROOT" "$REPO"
git -C "$REPO" config user.email test@example.invalid
git -C "$REPO" config user.name "Test User"
# A throwaway upstream-owner reference committed to the base, so a later case can
# MOVE it out of skills/ (the rename/move-out bypass). Nothing else references it,
# so moving it does not trip the broken-.md-reference check.
MOVEOUT_REL="skills/product-rd-workflow/references/zz-fixture-moveout.md"
printf '# fixture move-out reference\n\nNeutral placeholder content for the impact-chain move-out test.\n' > "$REPO/$MOVEOUT_REL"
# A committed (unchanged-in-cases) sentence for the stale-anchor case: long
# enough to pass the 16-char minimum, so that case tests added-line binding.
printf '\n- Stale anchor fixture sentence must stay unchanged for coverage.\n' >> "$REPO/skills/product-rd-workflow/references/adr-convention.md"
# A file whose NAME carries the owner's slug, so a later case can rename the owner
# and its slug-named file together the way a real rename does.
printf '# fixture slug-named reference\n\nNeutral placeholder for the inner-rename test.\n' > "$REPO/skills/platform-observability/references/platform-observability-playbook.md"
# A script mentioning the renameable slug, so a later case can retarget it PURELY
# and isolate the prose-only guard from the reproduction check.
printf '# fixture slug mention: platform-observability\n' >> "$REPO/skills/product-rd-workflow/scripts/check-agent-contract-coverage.sh"
printf '\nFixture eligible sibling mention: platform-observability.\n' >> "$REPO/skills/product-rd-workflow/references/adr-convention.md"
git -C "$REPO" add -A
git -C "$REPO" commit -qm "seed throwaway upstream reference"
git -C "$REPO" branch fixture-base HEAD
fixture_base_revision="$(git -C "$REPO" rev-parse fixture-base)"

REGISTER="$REPO/skills/skill-extraction-workflow/references/source-register.md"
UPSTREAM_REF="skills/product-rd-workflow/references/adr-convention.md"    # an upstream owner's reference
UPSTREAM_SCRIPT="skills/product-rd-workflow/scripts/check-agent-contract-coverage.sh"  # an upstream owner's script
[ -f "$REPO/$UPSTREAM_REF" ] || fail "fixture reference missing: $UPSTREAM_REF"
[ -f "$REPO/$UPSTREAM_SCRIPT" ] || fail "fixture script missing: $UPSTREAM_SCRIPT"

# Fresh per-case branch off fixture-base, with upstream set so the checker's
# base-ref detection resolves to a stable local ref (independent of a detached CI
# checkout head).
new_case() {
  git -C "$REPO" switch -q -C "$1" fixture-base
  git -C "$REPO" branch --set-upstream-to=fixture-base "$1" >/dev/null 2>&1
}
commit_case() { git -C "$REPO" add -A; git -C "$REPO" commit -qm "$1"; }
full_check_runs=0
gate_runs=0
run_full_check() {
  full_check_runs=$((full_check_runs + 1))
  set +e
  out="$(env -u ALIAS_AUDIT_CMD -u CCL_SKILL_BASE_REF bash "$CHECK_SCRIPT" "$REPO" 2>&1)"
  rc=$?
  set -e
}
# A real rename retargets EVERY mention, including the agents/ overlay's prompt
# token. Leaving one behind is what a stale-reference bug looks like, and the
# identifier-rename class is supposed to refuse it, so the fixture must retarget
# as completely as the real thing does.
retarget_all() {
  for target in "$@"; do
    find "$target" -type f -exec perl -pi -e 's/platform-observability/platform-signal-evidence/g' {} +
  done
}
run_gate() {
  gate_runs=$((gate_runs + 1))
  set +e
  out="$(env -u ALIAS_AUDIT_CMD -u CCL_SKILL_BASE_REF ruby "$GATE_SCRIPT" "$REPO" 2>&1)"
  rc=$?
  set -e
}

# Case 1: an upstream owner's REFERENCE changed with NO impact-chain row -> block.
new_case case-ref-no-row
printf '\nFixture reference edit for the impact-chain refscripts gate.\n' >> "$REPO/$UPSTREAM_REF"
commit_case "ref edit, no impact-chain row"
run_full_check
assert_rc "$rc" 1 "reference edit without a row must fail the gate"
assert_contains "impact_chain_gate_missing" "$out" "checker should name the missing-row cause"
assert_contains "product-rd-workflow/SKILL.md" "$out" "diagnostic should name the changed upstream owner"
assert_contains "references/ and scripts/" "$out" "diagnostic should explain reference/scripts now count"

# Case 2: a matching impact-chain row without behavioral evidence is still
# incomplete. The previous gate accepted the row because it only checked the
# owner path, so "the rule is already covered" could close with no replay or
# firing-path proof.
new_case case-ref-row-without-behavior-evidence
printf '\nFixture reference edit for the impact-chain behavior-evidence gate.\n' >> "$REPO/$UPSTREAM_REF"
printf '| Fixture row without behavior evidence | `downstream-executor` | Executor applies the reference behavior | `updated` | `product-rd-workflow/SKILL.md` reference edit |\n' >> "$REGISTER"
commit_case "ref edit with row but no behavior evidence"
run_gate
assert_rc "$rc" 1 "an impact-chain row without behavioral evidence must fail"
assert_contains "impact_chain_behavior_evidence_missing" "$out" "checker should require the behavior-evidence record"


# A genuinely normative rule phrased with "Never" (not in the older verb list)
# must be accepted as an enforcing firing-path line.
new_case case-ref-never-verb-firing-path
printf '\n- Never bypass the fixture upstream rule for this gate.\n' >> "$REPO/$UPSTREAM_REF"
printf '| Fixture never-verb rule | `downstream-executor` | behavioral-evidence: RED-baseline; observed-failure: yes; firing-path: file:skills/product-rd-workflow/references/adr-convention.md#Never bypass the fixture upstream rule | `updated` | `product-rd-workflow/SKILL.md` reference edit |\n' >> "$REGISTER"
commit_case "never-verb normative firing path"
run_gate
assert_not_contains "impact_chain_firing_path_missing" "$out" "a never-phrased normative rule should satisfy the firing-path gate"
assert_rc "$rc" 0 "a never-phrased normative list rule must be accepted"

# A purely DESCRIPTIVE list line ("always exposes" — no imperative/prohibitive
# verb) is not an enforcing rule; the widened verb list must not admit it.
new_case case-ref-descriptive-always-firing-path
printf '\n- The host always exposes this delegation capability surface.\n' >> "$REPO/$UPSTREAM_REF"
printf '| Fixture descriptive always line | `downstream-executor` | behavioral-evidence: RED-baseline; observed-failure: yes; firing-path: file:skills/product-rd-workflow/references/adr-convention.md#always exposes this delegation capability | `updated` | `product-rd-workflow/SKILL.md` reference edit |\n' >> "$REGISTER"
commit_case "descriptive always line as firing path"
run_gate
assert_rc "$rc" 1 "a descriptive list line must not satisfy the firing-path gate"
assert_contains "impact_chain_firing_path_missing" "$out" "checker should reject a descriptive (non-normative) anchor line"

# An HTML comment can smuggle normative vocabulary past the verb heuristic; a
# comment-carrying anchor line is never an enforcing rule surface.
new_case case-ref-html-comment-firing-path
printf '\n- <!-- must enforce this hidden fixture directive --> bookkeeping note.\n' >> "$REPO/$UPSTREAM_REF"
printf '| Fixture html-comment firing path | `downstream-executor` | behavioral-evidence: RED-baseline; observed-failure: yes; firing-path: file:skills/product-rd-workflow/references/adr-convention.md#must enforce this hidden fixture directive | `updated` | `product-rd-workflow/SKILL.md` reference edit |\n' >> "$REGISTER"
commit_case "html-comment line as firing path"
run_gate
assert_rc "$rc" 1 "an HTML-comment anchor line must not satisfy the firing-path gate"
assert_contains "impact_chain_firing_path_missing" "$out" "checker should reject comment-smuggled normative vocabulary"

# A changed executable-bit file without a shebang (e.g. a chmod'ed Markdown
# file) is not an executable firing surface.
new_case case-ref-noshebang-command-firing-path
printf '\nFixture reference edit for the shebang command gate.\n' >> "$REPO/$UPSTREAM_REF"
printf '# fixture executable-bit markdown\n' > "$REPO/skills/product-rd-workflow/scripts/zz-fixture-noshebang.md"
chmod +x "$REPO/skills/product-rd-workflow/scripts/zz-fixture-noshebang.md"
printf '| Fixture no-shebang command | `downstream-executor` | behavioral-evidence: RED-baseline; observed-failure: yes; firing-path: command:skills/product-rd-workflow/scripts/zz-fixture-noshebang.md | `updated` | `product-rd-workflow/SKILL.md` reference edit |\n' >> "$REGISTER"
commit_case "executable-bit file without shebang as firing path"
run_gate
assert_rc "$rc" 1 "a shebang-less executable-bit file must not satisfy a command firing path"
assert_contains "impact_chain_firing_path_missing" "$out" "checker should require a shebang on command firing surfaces"

# Positive command-locator coverage: a genuinely changed 100755 shebang script
# under the owner must be ACCEPTED as a firing surface (rejection-only coverage
# would let an implementation that refuses every command: locator pass).
new_case case-ref-command-firing-path-accepted
printf '\nFixture reference edit for the accepted command firing path.\n' >> "$REPO/$UPSTREAM_REF"
printf '#!/usr/bin/env bash\nprintf "fixture owner enforcement script\\n"\n' > "$REPO/skills/product-rd-workflow/scripts/zz-fixture-owner-command.sh"
chmod +x "$REPO/skills/product-rd-workflow/scripts/zz-fixture-owner-command.sh"
printf '| Fixture accepted command firing path | `downstream-executor` | behavioral-evidence: RED-baseline; observed-failure: yes; firing-path: command:skills/product-rd-workflow/scripts/zz-fixture-owner-command.sh | `updated` | `product-rd-workflow/SKILL.md` reference edit |\n' >> "$REGISTER"
commit_case "changed shebang owner executable as firing path"
run_gate
assert_not_contains "impact_chain_firing_path_missing" "$out" "a changed shebang owner executable should satisfy the firing-path gate"
assert_rc "$rc" 0 "a complete RED row with a changed owner executable must pass"

# A malformed impact-chain-looking row (wrong cell count) is warned but stays
# advisory: hard-blocking would false-positive on the register's many other
# legitimate table shapes, and deliberate mangling is outside the trust model
# (review owns that residual). The complete sibling row satisfies the gate.
new_case case-ref-malformed-row-advisory
printf '\n- MUST enforce Fixture reference edit for the malformed-row gate.\n' >> "$REPO/$UPSTREAM_REF"
printf '| Fixture complete sibling row | `downstream-executor` | behavioral-evidence: RED-baseline; observed-failure: yes; firing-path: file:skills/product-rd-workflow/references/adr-convention.md#Fixture reference edit | `updated` | `product-rd-workflow/SKILL.md` reference edit |\n' >> "$REGISTER"
printf '| Fixture malformed row | `downstream-executor` | prose with an unescaped | pipe inside a cell | `updated` | `product-rd-workflow/SKILL.md` second disposition |\n' >> "$REGISTER"
commit_case "complete row plus malformed sibling row"
run_gate
assert_contains "impact_chain_row_malformed" "$out" "checker should warn about the malformed row"
assert_rc "$rc" 0 "a malformed row stays advisory when a complete sibling row satisfies the gate"

# A semantic-control label alone cannot close a non-wording owner diff: the
# owner package needs at least one RED-baseline row, else an author could
# label every change "stable" and self-clear the package.
new_case case-ref-semantic-control-alone
printf '\n- MUST enforce Fixture reference edit for semantic-control firing-path coverage.\n' >> "$REPO/$UPSTREAM_REF"
printf '| Fixture semantic control self-adjudication | `downstream-executor` | behavioral-evidence: semantic-control; observed-failure: no; firing-path: file:skills/product-rd-workflow/references/adr-convention.md#Fixture reference edit | `updated` | `product-rd-workflow/SKILL.md` reference edit |\n' >> "$REGISTER"
commit_case "semantic control label alone"
run_gate
assert_rc "$rc" 1 "a semantic-control-only owner package must fail"
assert_contains "impact_chain_behavior_evidence_missing" "$out" "checker should require at least one RED-baseline row per non-wording owner"

# A stable semantic-control row may supplement a RED-baseline row for the same
# non-wording owner; the RED row satisfies the owner-level floor.
new_case case-ref-semantic-control-with-owner-red
printf '\n- MUST enforce Fixture reference edit for semantic-control plus owner RED validation.\n' >> "$REPO/$UPSTREAM_REF"
printf '| Fixture stable semantic control | `downstream-executor` | behavioral-evidence: semantic-control; observed-failure: no; firing-path: file:skills/product-rd-workflow/references/adr-convention.md#Fixture reference edit | `updated` | `product-rd-workflow/SKILL.md` stable control |\n' >> "$REGISTER"
printf '| Fixture owner behavior delta | `downstream-executor` | behavioral-evidence: RED-baseline; observed-failure: yes; firing-path: file:skills/product-rd-workflow/references/adr-convention.md#Fixture reference edit | `updated` | `product-rd-workflow/SKILL.md` changed behavior |\n' >> "$REGISTER"
commit_case "semantic control supplemented by owner RED"
run_gate
assert_not_contains "impact_chain_behavior_evidence_missing" "$out" "valid owner RED should permit a supplementary stable semantic-control row"
assert_rc "$rc" 0 "semantic-control plus a valid owner RED row should pass"

# Case 2a: an observed failure with RED evidence but no named firing path is not
# closed. This is the exact "rule existed but did not execute" regression.
new_case case-ref-observed-without-firing-path
printf '\nFixture reference edit for the impact-chain firing-path gate.\n' >> "$REPO/$UPSTREAM_REF"
printf '| Fixture observed failure without firing path | `downstream-executor` | behavioral-evidence: RED-baseline; observed-failure: yes | `updated` | `product-rd-workflow/SKILL.md` reference edit |\n' >> "$REGISTER"
commit_case "ref edit with observed failure but no firing path"
run_gate
assert_rc "$rc" 1 "an observed failure without a firing path must fail"
assert_contains "impact_chain_firing_path_missing" "$out" "checker should name the missing firing-path proof"

# Whitespace is not a firing path either.
new_case case-ref-observed-with-empty-firing-path
printf '\nFixture reference edit for the empty firing-path gate.\n' >> "$REPO/$UPSTREAM_REF"
printf '| Fixture observed failure with empty firing path | `downstream-executor` | behavioral-evidence: RED-baseline; observed-failure: yes; firing-path: ; | `updated` | `product-rd-workflow/SKILL.md` reference edit |\n' >> "$REGISTER"
commit_case "ref edit with empty firing path"
run_gate
assert_rc "$rc" 1 "an empty firing path must fail"
assert_contains "impact_chain_firing_path_missing" "$out" "checker should reject whitespace-only firing paths"

# Non-placeholder prose is still not a resolvable firing mechanism.
new_case case-ref-observed-with-unresolvable-firing-path
printf '\nFixture reference edit for the resolvable firing-path gate.\n' >> "$REPO/$UPSTREAM_REF"
printf '| Fixture observed failure with prose firing path | `downstream-executor` | behavioral-evidence: RED-baseline; observed-failure: yes; firing-path: the existing rule | `updated` | `product-rd-workflow/SKILL.md` reference edit |\n' >> "$REGISTER"
commit_case "ref edit with unresolvable firing path"
run_gate
assert_rc "$rc" 1 "an arbitrary prose firing path must fail"
assert_contains "impact_chain_firing_path_missing" "$out" "checker should require a resolvable firing mechanism"

# A real executable in another owner's directory is not this owner's firing
# mechanism, even though it exists and is changed by the checker under test.
new_case case-ref-cross-owner-firing-path
printf '\nFixture reference edit for owner-scoped firing paths.\n' >> "$REPO/$UPSTREAM_REF"
mkdir -p "$REPO/skills/grill-me/scripts"
printf '#!/usr/bin/env bash\nprintf "fixture cross-owner executable\\n"\n' > "$REPO/skills/grill-me/scripts/zz-fixture-crossowner.sh"
chmod +x "$REPO/skills/grill-me/scripts/zz-fixture-crossowner.sh"
printf '| Fixture cross-owner firing path | `downstream-executor` | behavioral-evidence: RED-baseline; observed-failure: yes; firing-path: command:skills/grill-me/scripts/zz-fixture-crossowner.sh | `updated` | `product-rd-workflow/SKILL.md` reference edit |\n' >> "$REGISTER"
commit_case "ref edit with cross-owner firing path"
run_gate
assert_rc "$rc" 1 "a cross-owner firing mechanism must fail"
assert_contains "impact_chain_firing_path_missing" "$out" "checker should bind firing paths to the changed owner"

# Merely adding a uniquely-addressable prose bullet under the owner is still the
# original content-without-enforcement failure. A file firing path must land on a
# normative numbered/list rule, not decorative bookkeeping text.
new_case case-ref-decorative-owner-prose-firing-path
printf '\nFixture reference edit for enforcing firing-path coverage.\n' >> "$REPO/$UPSTREAM_REF"
printf '\n- This row is recorded for ledger bookkeeping only.\n' >> "$REPO/skills/product-rd-workflow/SKILL.md"
printf '| Fixture decorative firing path | `downstream-executor` | behavioral-evidence: RED-baseline; observed-failure: yes; firing-path: file:skills/product-rd-workflow/SKILL.md#This row is recorded for ledger bookkeeping only | `updated` | `product-rd-workflow/SKILL.md` reference edit |\n' >> "$REGISTER"
commit_case "ref edit with decorative owner prose firing path"
run_gate
assert_rc "$rc" 1 "decorative owner prose must not satisfy a firing path"
assert_contains "impact_chain_firing_path_missing" "$out" "checker should require an enforcing checklist or rule line"

# A token that exists only in old content is not a newly landed firing point.
new_case case-ref-stale-anchor-firing-path
printf '\nFixture reference edit for changed-anchor coverage.\n' >> "$REPO/$UPSTREAM_REF"
printf '| Fixture stale-anchor firing path | `downstream-executor` | behavioral-evidence: RED-baseline; observed-failure: yes; firing-path: file:skills/product-rd-workflow/references/adr-convention.md#Stale anchor fixture sentence must stay unchanged | `updated` | `product-rd-workflow/SKILL.md` reference edit |\n' >> "$REGISTER"
commit_case "ref edit with stale anchor firing path"
run_gate
assert_rc "$rc" 1 "an unchanged anchor must fail"
assert_contains "impact_chain_firing_path_missing" "$out" "checker should require a changed-line anchor"

# Case 2b: same reference change WITH a complete matching impact-chain row ->
# gate satisfied.
new_case case-ref-with-row
printf '\n- MUST enforce Fixture reference edit for the impact-chain refscripts gate.\n' >> "$REPO/$UPSTREAM_REF"
printf '| Fixture reference-path rule | `downstream-executor` | Executor applies the reference behavior; behavioral-evidence: RED-baseline; observed-failure: yes; firing-path: file:skills/product-rd-workflow/references/adr-convention.md#Fixture reference edit | `updated` | `product-rd-workflow/SKILL.md` reference edit |\n' >> "$REGISTER"
commit_case "ref edit with matching impact-chain row"
run_gate
assert_not_contains "impact_chain_gate_missing" "$out" "a matching row must satisfy the gate for a reference edit"
assert_not_contains "impact_chain_behavior_evidence_missing" "$out" "complete behavior evidence must satisfy the gate"
assert_not_contains "impact_chain_firing_path_missing" "$out" "a named firing path must satisfy the observed-failure gate"
assert_rc "$rc" 0 "reference edit with a valid row should pass"

# Every added row must be complete. One boilerplate-complete row must not mask a
# second bare disposition for the same owner.
new_case case-ref-complete-row-masks-incomplete-row
printf '\n- MUST enforce Fixture reference edit for per-row behavior evidence.\n' >> "$REPO/$UPSTREAM_REF"
printf '| Fixture complete row | `downstream-executor` | behavioral-evidence: RED-baseline; observed-failure: yes; firing-path: file:skills/product-rd-workflow/references/adr-convention.md#Fixture reference edit | `updated` | `product-rd-workflow/SKILL.md` reference edit |\n' >> "$REGISTER"
printf '| Fixture incomplete sibling row | `downstream-executor` | Bare owner citation only | `updated` | `product-rd-workflow/SKILL.md` second disposition |\n' >> "$REGISTER"
commit_case "one complete row cannot mask one incomplete row"
run_gate
assert_rc "$rc" 1 "every added row for an owner must carry complete behavior evidence"
assert_contains "impact_chain_behavior_evidence_missing" "$out" "checker should reject the incomplete sibling row"

# Case 3: an upstream owner's SCRIPT changed with NO impact-chain row -> block.
new_case case-script-no-row
printf '\n# fixture script edit for the impact-chain refscripts gate\n' >> "$REPO/$UPSTREAM_SCRIPT"
commit_case "script edit, no impact-chain row"
run_gate
assert_rc "$rc" 1 "script edit without a row must fail the gate"
assert_contains "impact_chain_gate_missing" "$out" "checker should name the missing-row cause for a script edit"
assert_contains "product-rd-workflow/SKILL.md" "$out" "diagnostic should name the changed upstream owner"

# Case 2c: an INDENTED impact-chain evidence row (valid Markdown, ≤3 leading
# spaces) must still count — it must not be falsely blocked. Guards the parser
# normalization that keeps item-1 and item-2 consistent.
new_case case-ref-indented-row
UPSTREAM_REF2="skills/test-artifact-management/references/gen_report.py"    # a NON-.md upstream reference
[ -f "$REPO/$UPSTREAM_REF2" ] || fail "fixture non-md reference missing: $UPSTREAM_REF2"
printf '\n- MUST enforce Fixture reference edit for the impact-chain refscripts gate.\n' >> "$REPO/$UPSTREAM_REF"
printf ' | Fixture indented row | `downstream-executor` | Executor applies the reference behavior; behavioral-evidence: RED-baseline; observed-failure: yes; firing-path: file:skills/product-rd-workflow/references/adr-convention.md#Fixture reference edit | `updated` | `product-rd-workflow/SKILL.md` reference edit |\n' >> "$REGISTER"
commit_case "ref edit with an indented (valid) impact-chain row"
run_gate
assert_not_contains "impact_chain_gate_missing" "$out" "an indented but valid evidence row must count"
assert_rc "$rc" 0 "indented valid row should pass"

# Deterministically wording-only rows are the sole no-firing-path exception.
new_case case-ref-wording-only-row
printf '\n' >> "$REPO/$UPSTREAM_REF"
printf '| Fixture formatting-only row | `downstream-executor` | behavioral-evidence: not-required wording-only; artifact: diff:product-rd-workflow/SKILL.md; observed-failure: no | `updated` | `product-rd-workflow/SKILL.md` formatting-only edit |\n' >> "$REGISTER"
commit_case "formatting-only edit with explicit evidence"
run_gate
assert_not_contains "impact_chain_behavior_evidence_missing" "$out" "wording-only row with artifact should satisfy behavior record"
assert_not_contains "impact_chain_firing_path_missing" "$out" "wording-only row does not need a firing path"
assert_rc "$rc" 0 "deterministically wording-only row should pass"

# A substantive change cannot self-label as wording-only to skip the firing path.
new_case case-ref-substantive-mislabeled-wording-only
printf '\nSubstantive fixture behavior change.\n' >> "$REPO/$UPSTREAM_REF"
printf '| Fixture mislabeled wording-only row | `downstream-executor` | behavioral-evidence: not-required wording-only; artifact: diff:product-rd-workflow/SKILL.md; observed-failure: no | `updated` | `product-rd-workflow/SKILL.md` substantive edit |\n' >> "$REGISTER"
commit_case "substantive edit mislabeled wording-only"
run_gate
assert_rc "$rc" 1 "a substantive edit mislabeled wording-only must fail"
assert_contains "impact_chain_behavior_evidence_missing" "$out" "checker should reject self-adjudicated wording-only classification"

# Adding a firing-path string does not rescue the false classification; a real
# non-wording change must use RED-baseline or semantic-control.
new_case case-ref-substantive-mislabeled-wording-only-with-path
printf '\nAnother substantive fixture behavior change.\n' >> "$REPO/$UPSTREAM_REF"
printf '| Fixture mislabeled wording-only row with path | `downstream-executor` | behavioral-evidence: not-required wording-only; artifact: diff:product-rd-workflow/SKILL.md; observed-failure: no; firing-path: file:skills/product-rd-workflow/references/adr-convention.md#Fixture reference edit | `updated` | `product-rd-workflow/SKILL.md` substantive edit |\n' >> "$REGISTER"
commit_case "substantive edit mislabeled wording-only with path"
run_gate
assert_rc "$rc" 1 "a firing path must not rescue a false wording-only label"
assert_contains "impact_chain_behavior_evidence_missing" "$out" "checker should require a non-wording behavioral status"

# Wording-only is computed across every changed file in the owner package. A
# blank-only reference hunk cannot hide a substantive SKILL.md hunk.
new_case case-owner-multifile-substantive-mislabeled-wording-only
printf '\n' >> "$REPO/$UPSTREAM_REF"
printf '\nSubstantive multi-file owner behavior change.\n' >> "$REPO/skills/product-rd-workflow/SKILL.md"
printf '| Fixture multi-file mislabeled wording-only row | `downstream-executor` | behavioral-evidence: not-required wording-only; artifact: diff:product-rd-workflow/SKILL.md; observed-failure: no | `updated` | `product-rd-workflow/SKILL.md` multi-file substantive edit |\n' >> "$REGISTER"
commit_case "multi-file substantive owner edit mislabeled wording-only"
run_gate
assert_rc "$rc" 1 "wording-only must be false when any owner file has letter or digit deltas"
assert_contains "impact_chain_behavior_evidence_missing" "$out" "checker should aggregate the full owner package diff"

# The wording-only class applies only to Markdown prose: a punctuation-only
# edit in a runnable non-.md reference can change behavior (a deleted paren),
# so it must not be classifiable as wording-only.
new_case case-ref-nonmd-punctuation-mislabeled-wording-only
printf '\n#\n' >> "$REPO/$UPSTREAM_REF2"
printf '| Fixture non-md punctuation wording-only row | `downstream-executor` | behavioral-evidence: not-required wording-only; observed-failure: no | `updated` | `test-artifact-management/SKILL.md` runnable reference edit |\n' >> "$REGISTER"
commit_case "punctuation-only edit to a runnable reference mislabeled wording-only"
run_gate
assert_rc "$rc" 1 "a non-md owner file change must never classify as wording-only"
assert_contains "impact_chain_behavior_evidence_missing" "$out" "checker should restrict wording-only to Markdown prose"

# A declaration key embedded mid-prose is not a declaration: each field must
# start its own semicolon-delimited fragment.
new_case case-ref-embedded-declaration-key
printf '\n- MUST enforce Fixture reference edit for the embedded-key gate.\n' >> "$REPO/$UPSTREAM_REF"
printf '| Fixture embedded key row | `downstream-executor` | there is no behavioral-evidence: RED-baseline here; observed-failure: yes; firing-path: file:skills/product-rd-workflow/references/adr-convention.md#Fixture reference edit | `updated` | `product-rd-workflow/SKILL.md` reference edit |\n' >> "$REGISTER"
commit_case "declaration key embedded in prose"
run_gate
assert_rc "$rc" 1 "an embedded declaration key must not parse as a declaration"
assert_contains "impact_chain_behavior_evidence_missing" "$out" "checker should require fragment-anchored declarations"

# A failing git diff must FAIL CLOSED: empty output from a broken subprocess
# must never read as "no changed owners".
new_case case-git-diff-failure-fails-closed
printf '\nFixture reference edit for the git fail-closed gate.\n' >> "$REPO/$UPSTREAM_REF"
commit_case "ref edit behind a failing git diff"
GIT_SHIM_DIR="$TMP/git-shim"
mkdir -p "$GIT_SHIM_DIR"
REAL_GIT="$(command -v git)"
printf '#!/usr/bin/env bash\ncase "$*" in *"--no-renames -z"*) exit 1 ;; esac\nexec "%s" "$@"\n' "$REAL_GIT" > "$GIT_SHIM_DIR/git"
chmod +x "$GIT_SHIM_DIR/git"
set +e
gate_runs=$((gate_runs + 1))
out="$(env -u ALIAS_AUDIT_CMD -u CCL_SKILL_BASE_REF PATH="$GIT_SHIM_DIR:$PATH" ruby "$GATE_SCRIPT" "$REPO" 2>&1)"
rc=$?
set -e
assert_rc "$rc" 1 "a failing changed-path diff must fail the gate closed"
assert_contains "impact_chain_git_failed" "$out" "checker should name the failed git subprocess"

# Case 2d: multi-perspective-research is an upstream evidence/coverage owner.
# Editing it without an impact-chain row must not bypass the gate.
new_case case-research-owner-no-row
printf '\nFixture research-owner edit for impact-chain coverage.\n' >> "$REPO/skills/multi-perspective-research/SKILL.md"
commit_case "research owner edit, no impact-chain row"
run_gate
assert_rc "$rc" 1 "a research-owner edit without an impact-chain row must fail"
assert_contains "impact_chain_gate_missing" "$out" "research evidence owner must trigger the impact-chain gate"
assert_contains "multi-perspective-research/SKILL.md" "$out" "diagnostic should name the research owner"

# skill-extraction-workflow is itself an upstream owner. Its checker/rules cannot
# escape the same impact-chain row requirement that they impose on other owners.
new_case case-extraction-owner-no-row
printf '\n- MUST enforce fixture extraction-owner behavior.\n' >> "$REPO/skills/skill-extraction-workflow/SKILL.md"
commit_case "skill-extraction owner edit, no impact-chain row"
run_gate
assert_rc "$rc" 1 "the extraction owner must require its own impact-chain row"
assert_contains "impact_chain_gate_missing" "$out" "extraction owner must trigger the impact-chain gate"
assert_contains "skill-extraction-workflow/SKILL.md" "$out" "diagnostic should name the extraction owner"

# Case 3a2: a NON-.md file under an upstream owner's references/ (e.g. a runnable
# helper) also ships behavior and must require a row. Guards the references/.+ fix.
new_case case-nonmd-ref-no-row
printf '\n# fixture edit to a non-md upstream reference helper\n' >> "$REPO/$UPSTREAM_REF2"
commit_case "non-md reference edit, no impact-chain row"
run_gate
assert_rc "$rc" 1 "a non-.md reference edit without a row must fail the gate"
assert_contains "impact_chain_gate_missing" "$out" "non-.md reference edits must not bypass the gate"
assert_contains "test-artifact-management/SKILL.md" "$out" "diagnostic should name the owner of the non-md reference"

# Case 3b: MOVING an upstream owner's reference OUT of skills/ (a rename git would
# otherwise collapse to the destination) must still trigger the gate via the old
# path. Guards the --no-renames fix.
new_case case-ref-moveout
git -C "$REPO" mv "$MOVEOUT_REL" "docs/zz-fixture-moveout.md"
commit_case "move an upstream reference out of skills/ with no row"
run_gate
assert_rc "$rc" 1 "moving an upstream reference out of skills/ without a row must fail"
assert_contains "impact_chain_gate_missing" "$out" "a move-out must not evade the gate"
assert_contains "product-rd-workflow/SKILL.md" "$out" "diagnostic should name the owner whose reference moved out"

# Deleting an owner reference can close when a changed surviving rule provides
# the firing path — legitimate rule replacement stays possible while the
# move-out itself still demands a row.
new_case case-ref-moveout-with-replacement-row
git -C "$REPO" mv "$MOVEOUT_REL" "docs/zz-fixture-moveout.md"
printf '\n- MUST enforce Fixture replacement rule after deleting an owner reference.\n' >> "$REPO/skills/product-rd-workflow/SKILL.md"
printf '| Fixture move-out replacement row | `downstream-executor` | behavioral-evidence: RED-baseline; observed-failure: yes; firing-path: file:skills/product-rd-workflow/SKILL.md#Fixture replacement rule after deleting an owner reference | `updated` | `product-rd-workflow/SKILL.md` replacement rule |\n' >> "$REGISTER"
commit_case "move an upstream reference out with replacement evidence"
run_gate
assert_not_contains "impact_chain_behavior_evidence_missing" "$out" "a deletion covered by a surviving changed firing path should validate"
assert_not_contains "impact_chain_firing_path_missing" "$out" "replacement rule should provide the changed firing path"
assert_rc "$rc" 0 "move-out with complete deleted-subject evidence should pass"

# Case 4: the source-register itself is the ledger and is EXCLUDED — appending a
# row to it (with no other upstream change) must NOT demand a self-referential row.
new_case case-register-only
printf '\n<!-- fixture: benign ledger note, no upstream change -->\n' >> "$REGISTER"
commit_case "register-only edit is excluded"
run_gate
assert_not_contains "impact_chain_gate_missing" "$out" "editing only the ledger must not trigger the gate"
assert_rc "$rc" 0 "register-only edit should pass"

# The exact shared ledger path is excluded even when the upstream owner is
# skill-extraction-workflow itself; the surviving owner SKILL remains bound.
new_case case-extraction-owner-ledger-exclusion
printf '\n- MUST enforce Fixture extraction owner ledger exclusion.\n' >> "$REPO/skills/skill-extraction-workflow/SKILL.md"
printf '| Fixture extraction ledger exclusion | `downstream-executor` | behavioral-evidence: RED-baseline; observed-failure: yes; firing-path: file:skills/skill-extraction-workflow/SKILL.md#Fixture extraction owner ledger exclusion | `updated` | `skill-extraction-workflow/SKILL.md` fixture rule |\n' >> "$REGISTER"
git -C "$REPO" add -A
git -C "$REPO" commit -qm "extraction owner ledger exclusion"
run_gate
assert_not_contains "impact_chain_behavior_evidence_missing" "$out" "shared ledger should be excluded from extraction-owner subjects"
assert_rc "$rc" 0 "extraction owner change plus ledger row should pass"

# Case 5: RENAMING a whole upstream owner package. --no-renames surfaces the old
# package path as a delete, so the subject set used to demand a row for an owner
# whose SKILL.md no longer exists — while the evidence check rejects any row that
# cites a missing SKILL.md. The gate asked for exactly the row it refused, leaving
# a rename with no honest way to pass. The surviving name carries the row instead.
new_case case-owner-package-renamed
git -C "$REPO" mv skills/platform-observability skills/platform-signal-evidence
printf '\n- MUST enforce Fixture renamed owner rule.\n' >> "$REPO/skills/platform-signal-evidence/SKILL.md"
printf '| Fixture renamed owner row | `downstream-executor` | behavioral-evidence: RED-baseline; observed-failure: yes; firing-path: file:skills/platform-signal-evidence/SKILL.md#Fixture renamed owner rule | `updated` | `platform-signal-evidence/SKILL.md` renamed owner |\n' >> "$REGISTER"
commit_case "rename an upstream owner package with a row on the surviving name"
run_gate
assert_not_contains "platform-observability/SKILL.md" "$out" "the renamed-away path must not be demanded as a row subject"
assert_not_contains "impact_chain_gate_missing" "$out" "a renamed owner covered on its surviving name must not block"
assert_rc "$rc" 0 "renaming an owner package with a row on the new name should pass"

# The exclusion is scoped to packages that are actually gone: a LIVE owner still
# owes its row, so the rename fix cannot be reused to skip a normal edit.
new_case case-owner-package-renamed-live-owner-still-bound
git -C "$REPO" mv skills/platform-observability skills/platform-signal-evidence
printf '\nFixture reference edit alongside an unrelated owner rename.\n' >> "$REPO/$UPSTREAM_REF"
commit_case "rename one owner while editing another owner's reference, no row"
run_gate
assert_rc "$rc" 1 "a live owner's reference edit must still demand a row"
assert_contains "impact_chain_gate_missing" "$out" "the live owner must still be named"
assert_contains "product-rd-workflow/SKILL.md" "$out" "diagnostic should name the live owner"
assert_not_contains "platform-observability/SKILL.md" "$out" "the renamed-away path must stay out of the subject set"

# Case 6: an owner that only RETARGETS its pointers at a renamed skill. Its diff
# is reproduced byte-for-byte by applying the rename to the base bytes, so there
# is no observed delta to declare and no changed normative rule to anchor a
# firing path on. The RED floor used to demand one anyway, which only a fabricated
# row could satisfy.
new_case case-identifier-rename-retarget
git -C "$REPO" mv skills/platform-observability skills/platform-signal-evidence
retarget_all "$REPO/skills/platform-signal-evidence" "$REPO/skills/defect-diagnosis"
printf '| Fixture retarget row | `downstream-executor` | behavioral-evidence: not-required identifier-rename; observed-failure: no | `updated` | `defect-diagnosis/SKILL.md` pointer retarget |\n' >> "$REGISTER"
printf '| Fixture renamed owner row | `downstream-executor` | behavioral-evidence: not-required identifier-rename; observed-failure: no | `updated` | `platform-signal-evidence/SKILL.md` renamed owner |\n' >> "$REGISTER"
commit_case "retarget a pointer at a renamed skill"
run_gate
assert_rc "$rc" 1 "the renamed owner itself must not take the no-behaviour class"
assert_contains "platform-signal-evidence/SKILL.md" "$out" "the rename destination owes real evidence"
assert_not_contains "defect-diagnosis/SKILL.md" "$out" "a dependent owner that only retargets pointers still qualifies"

# The killing mutation: smuggle ONE unrelated line in alongside the retarget. The
# base bytes no longer reproduce HEAD, so the class must be refused and the
# normal evidence bar must reappear. Without this, the class would be a waiver.
new_case case-identifier-rename-smuggled-content
git -C "$REPO" mv skills/platform-observability skills/platform-signal-evidence
retarget_all "$REPO/skills/platform-signal-evidence" "$REPO/skills/defect-diagnosis"
printf '\n- Smuggled fixture rule that must never ride in on a rename.\n' >> "$REPO/skills/defect-diagnosis/SKILL.md"
printf '| Fixture smuggled row | `downstream-executor` | behavioral-evidence: not-required identifier-rename; observed-failure: no | `updated` | `defect-diagnosis/SKILL.md` pointer retarget |\n' >> "$REGISTER"
printf '| Fixture renamed owner row | `downstream-executor` | behavioral-evidence: not-required identifier-rename; observed-failure: no | `updated` | `platform-signal-evidence/SKILL.md` renamed owner |\n' >> "$REGISTER"
commit_case "smuggle content alongside a retarget"
run_gate
assert_rc "$rc" 1 "content smuggled alongside a retarget must lose the class"
assert_contains "defect-diagnosis/SKILL.md" "$out" "the smuggling owner must be named"

# Declaring the class when nothing was renamed at all must not pass either: with
# no rename pairs there is no transform that could reproduce the bytes.
new_case case-identifier-rename-declared-without-any-rename
printf '\n- Fixture rule added with no rename anywhere in the diff.\n' >> "$REPO/skills/defect-diagnosis/SKILL.md"
printf '| Fixture bogus rename row | `downstream-executor` | behavioral-evidence: not-required identifier-rename; observed-failure: no | `updated` | `defect-diagnosis/SKILL.md` no rename happened |\n' >> "$REGISTER"
commit_case "declare identifier-rename with no rename in the diff"
run_gate
assert_rc "$rc" 1 "the class must be refused when the diff contains no rename"

# DELETING an upstream owner outright is not the rename case and must still demand
# a declaration. Excluding every missing path would let removal of a decision owner
# — the larger change of the two — pass with no ledger row at all: a hole the old
# self-contradicting gate did not have, because that one failed closed.
new_case case-owner-package-deleted-still-bound
git -C "$REPO" rm -rq skills/platform-observability
commit_case "delete an upstream owner package outright with no row"
run_gate
assert_rc "$rc" 1 "deleting an upstream owner without a row must still block"
assert_contains "platform-observability/SKILL.md" "$out" "the deleted owner must stay a subject"

# The bijection must bite on a DEPENDENT owner, which is the only kind that can
# still hold the class. Retarget its pointers cleanly but delete one of its files:
# the changed set names only the edited file, so without comparing the complete
# package the deletion is invisible and every surviving file still reproduces.
new_case case-identifier-rename-dependent-drops-a-file
git -C "$REPO" mv skills/platform-observability skills/platform-signal-evidence
retarget_all "$REPO/skills/platform-signal-evidence" "$REPO/skills/defect-diagnosis"
rm -f "$REPO/skills/defect-diagnosis/agents/openai.yaml"
# The destination owes real evidence now, so give it a valid owner-scoped anchor;
# otherwise the gate stops on that row and never reaches the dependent owner.
printf '\n- Never skip the fixture renamed-owner rule for this gate.\n' >> "$REPO/skills/platform-signal-evidence/SKILL.md"
printf '| Fixture dependent row | `downstream-executor` | behavioral-evidence: not-required identifier-rename; observed-failure: no | `updated` | `defect-diagnosis/SKILL.md` pointer retarget |\n' >> "$REGISTER"
printf '| Fixture renamed owner row | `downstream-executor` | behavioral-evidence: RED-baseline; observed-failure: no; firing-path: file:skills/platform-signal-evidence/SKILL.md#Never skip the fixture renamed-owner rule | `updated` | `platform-signal-evidence/SKILL.md` renamed owner |\n' >> "$REGISTER"
commit_case "a dependent owner drops a file while retargeting"
run_gate
assert_rc "$rc" 1 "a dependent owner that drops a package file must lose the class"
assert_contains "defect-diagnosis/SKILL.md" "$out" "the dependent owner must be named as incomplete"

# Dropping the renamed-away path is only sound when the SUCCESSOR is a selected
# subject. Renaming a curated owner to a slug absent from the curated list leaves
# neither name selected, so the rename of a decision owner would escape entirely.
new_case case-rename-to-unselected-slug-still-bound
git -C "$REPO" mv skills/tighten-doc skills/zz-fixture-unselected
find "$REPO/skills/zz-fixture-unselected" -type f -exec perl -pi -e 's/tighten-doc/zz-fixture-unselected/g' {} +
commit_case "rename a curated owner to a slug nobody added to the curated list"
run_gate
assert_rc "$rc" 1 "a curated owner renamed out of the curated list must not escape the gate"
assert_contains "tighten-doc/SKILL.md" "$out" "the curated source name must stay a subject when its successor is unselected"

# Contents and names alone are not the package's identity. Drop the executable bit
# from a dependent owner's script and every byte still reproduces, yet a gate or
# hook that silently stops being runnable is exactly the behaviour change this
# class must never certify.
new_case case-identifier-rename-dependent-drops-exec-bit
git -C "$REPO" mv skills/platform-observability skills/platform-signal-evidence
retarget_all "$REPO/skills/platform-signal-evidence" "$REPO/skills/product-rd-workflow"
chmod -x "$REPO/$UPSTREAM_SCRIPT"
printf '\n- Never skip the fixture renamed-owner rule for this gate.\n' >> "$REPO/skills/platform-signal-evidence/SKILL.md"
printf '| Fixture exec-bit row | `downstream-executor` | behavioral-evidence: not-required identifier-rename; observed-failure: no | `updated` | `product-rd-workflow/SKILL.md` pointer retarget |\n' >> "$REGISTER"
printf '| Fixture renamed owner row | `downstream-executor` | behavioral-evidence: RED-baseline; observed-failure: no; firing-path: file:skills/platform-signal-evidence/SKILL.md#Never skip the fixture renamed-owner rule | `updated` | `platform-signal-evidence/SKILL.md` renamed owner |\n' >> "$REGISTER"
commit_case "a dependent owner loses a script's executable bit while retargeting"
run_gate
assert_rc "$rc" 1 "dropping an executable bit must lose the class"
assert_contains "product-rd-workflow/SKILL.md" "$out" "the owner whose script stopped being runnable must be named"

# A package may legitimately track a blob that is not valid UTF-8. Comparing bytes
# must not depend on decoding them, or one stray byte crashes the gate mid-run.
new_case case-identifier-rename-binary-blob-in-package
git -C "$REPO" mv skills/platform-observability skills/platform-signal-evidence
retarget_all "$REPO/skills/platform-signal-evidence" "$REPO/skills/defect-diagnosis"
printf '\377\376 not utf-8 \377' > "$REPO/skills/defect-diagnosis/zz-fixture-binary.bin"
printf '\n- Never skip the fixture renamed-owner rule for this gate.\n' >> "$REPO/skills/platform-signal-evidence/SKILL.md"
printf '| Fixture binary row | `downstream-executor` | behavioral-evidence: not-required identifier-rename; observed-failure: no | `updated` | `defect-diagnosis/SKILL.md` pointer retarget |\n' >> "$REGISTER"
printf '| Fixture renamed owner row | `downstream-executor` | behavioral-evidence: RED-baseline; observed-failure: no; firing-path: file:skills/platform-signal-evidence/SKILL.md#Never skip the fixture renamed-owner rule | `updated` | `platform-signal-evidence/SKILL.md` renamed owner |\n' >> "$REGISTER"
commit_case "a dependent owner package tracks a non-UTF-8 blob"
run_gate
assert_not_contains "invalid byte sequence" "$out" "a non-UTF-8 blob must not crash the comparison"
assert_rc "$rc" 1 "an added binary file is not a pure retarget, so the class is refused cleanly"

# A rename usually carries filenames with it — a skill's own playbook reference is
# named after the skill. Mapping only the directory would leave those paths
# unmatched, so an honest rename would look like a changed file set and lose the
# drop the whole class depends on.
new_case case-identifier-rename-with-renamed-inner-file
git -C "$REPO" mv skills/platform-observability skills/platform-signal-evidence
git -C "$REPO" mv skills/platform-signal-evidence/references/platform-observability-playbook.md \
                  skills/platform-signal-evidence/references/platform-signal-evidence-playbook.md
retarget_all "$REPO/skills/platform-signal-evidence" "$REPO/skills/defect-diagnosis"
printf '\n- Never skip the fixture renamed-owner rule for this gate.\n' >> "$REPO/skills/platform-signal-evidence/SKILL.md"
printf '| Fixture inner-rename dependent row | `downstream-executor` | behavioral-evidence: not-required identifier-rename; observed-failure: no | `updated` | `defect-diagnosis/SKILL.md` pointer retarget |\n' >> "$REGISTER"
printf '| Fixture inner-rename owner row | `downstream-executor` | behavioral-evidence: RED-baseline; observed-failure: no; firing-path: file:skills/platform-signal-evidence/SKILL.md#Never skip the fixture renamed-owner rule | `updated` | `platform-signal-evidence/SKILL.md` renamed owner |\n' >> "$REGISTER"
commit_case "rename an owner whose inner filename carries the slug"
run_gate
assert_not_contains "platform-observability/SKILL.md" "$out" "an inner filename carrying the slug must not break the move proof"
assert_rc "$rc" 0 "a rename that also renames a slug-named inner file should still land"

# A routing-surface-only change edits the frontmatter `description` and nothing
# else, so it has no changed numbered/list rule for the firing-path anchor to bind
# to. It is NOT exempted: a description edit decides which requests reach the skill,
# so it keeps the RED-baseline bar and the anchor is allowed to land on the changed
# description entry instead. Exempting it would drop the evidence requirement from
# the class carrying the most behaviour.
new_case case-routing-surface-description-anchor
perl -0pi -e 's/^(description: .+)$/$1 Fixture routing-surface trigger clause./m' \
  "$REPO/skills/product-rd-workflow/SKILL.md"
printf '| Fixture routing-surface row | `downstream-executor` | behavioral-evidence: RED-baseline; observed-failure: yes; firing-path: file:skills/product-rd-workflow/SKILL.md#description | `updated` | `product-rd-workflow/SKILL.md` description-only |\n' >> "$REGISTER"
commit_case "routing-surface: anchor bound to the changed description"
run_gate
assert_not_contains "impact_chain_firing_path_missing" "$out" "a changed description must be an anchorable firing path when it is the owner's whole change"
assert_rc "$rc" 0 "a description-only owner may anchor its firing path on the changed description"

# The widening is bounded by the same byte-exact predicate. The moment anything
# rides along — body content, a sibling file in the package, or a second
# frontmatter key — the owner keeps the ORDINARY anchor bar, which that
# description line cannot meet. Each case varies exactly one of the three arms;
# without the third, the non-description frontmatter comparison stays unmeasured.
new_case case-routing-surface-anchor-refused-with-body-edit
perl -0pi -e 's/^(description: .+)$/$1 Fixture routing-surface trigger clause./m' \
  "$REPO/skills/product-rd-workflow/SKILL.md"
printf '\n- Never skip the smuggled fixture body rule for this gate.\n' >> "$REPO/skills/product-rd-workflow/SKILL.md"
printf '| Fixture routing-surface body row | `downstream-executor` | behavioral-evidence: RED-baseline; observed-failure: yes; firing-path: file:skills/product-rd-workflow/SKILL.md#description | `updated` | `product-rd-workflow/SKILL.md` description plus body |\n' >> "$REGISTER"
commit_case "routing-surface: body content beside the description"
run_gate
assert_rc "$rc" 1 "a body edit riding along must take back the ordinary anchor bar"

new_case case-routing-surface-anchor-refused-with-reference-edit
perl -0pi -e 's/^(description: .+)$/$1 Fixture routing-surface trigger clause./m' \
  "$REPO/skills/product-rd-workflow/SKILL.md"
printf '\n- Never skip the smuggled fixture reference rule for this gate.\n' >> "$REPO/$UPSTREAM_REF"
printf '| Fixture routing-surface reference row | `downstream-executor` | behavioral-evidence: RED-baseline; observed-failure: yes; firing-path: file:skills/product-rd-workflow/SKILL.md#description | `updated` | `product-rd-workflow/SKILL.md` description plus reference |\n' >> "$REGISTER"
commit_case "routing-surface: sibling reference beside the description"
run_gate
assert_rc "$rc" 1 "a sibling reference edit must take back the ordinary anchor bar"

new_case case-routing-surface-anchor-refused-with-frontmatter-key
perl -0pi -e 's/^(description: .+)$/$1 Fixture routing-surface trigger clause./m' \
  "$REPO/skills/product-rd-workflow/SKILL.md"
perl -0pi -e 's/^(name: product-rd-workflow)$/$1\nfixture_extra_key: smuggled/m' \
  "$REPO/skills/product-rd-workflow/SKILL.md"
printf '| Fixture routing-surface frontmatter row | `downstream-executor` | behavioral-evidence: RED-baseline; observed-failure: yes; firing-path: file:skills/product-rd-workflow/SKILL.md#description | `updated` | `product-rd-workflow/SKILL.md` description plus another frontmatter key |\n' >> "$REGISTER"
commit_case "routing-surface: second frontmatter key beside the description"
run_gate
assert_rc "$rc" 1 "a second frontmatter key must take back the ordinary anchor bar"

# A folded/block scalar spreads one description value over continuation lines.
# The predicate accepts it (one entry, same body, same other keys), so the anchor
# must be able to land on a continuation line too — requiring the `description:`
# prefix would leave exactly these owners unanchorable, which is the problem this
# widening exists to solve.
new_case case-routing-surface-anchor-on-continuation-line
perl -0pi -e 's/^description: (.+)$/description: >-\n  $1\n  Fixture routing-surface trigger clause./m' \
  "$REPO/skills/product-rd-workflow/SKILL.md"
printf '| Fixture routing-surface folded row | `downstream-executor` | behavioral-evidence: RED-baseline; observed-failure: yes; firing-path: file:skills/product-rd-workflow/SKILL.md#description | `updated` | `product-rd-workflow/SKILL.md` folded description |\n' >> "$REGISTER"
commit_case "routing-surface: anchor on a folded-scalar continuation line"
run_gate
assert_rc "$rc" 0 "an anchor inside a folded description entry must bind"

# A change that only DELETES a continuation line adds no line at all. The base
# must therefore ALREADY carry the folded description, or the diff still contains
# the additions and the case would not test what it claims.
git -C "$REPO" switch -q -C fixture-folded fixture-base
perl -0pi -e 's/^description: (.+)$/description: >-\n  $1\n  Fixture routing-surface trigger clause.\n  Fixture routing-surface second clause./m' \
  "$REPO/skills/product-rd-workflow/SKILL.md"
git -C "$REPO" add -A; git -C "$REPO" commit -qm "seed folded description base"
git -C "$REPO" switch -q -C case-routing-surface-anchor-after-deletion fixture-folded
git -C "$REPO" branch --set-upstream-to=fixture-folded case-routing-surface-anchor-after-deletion >/dev/null 2>&1
perl -0pi -e 's/\n  Fixture routing-surface second clause\.//' "$REPO/skills/product-rd-workflow/SKILL.md"
[ -z "$(git -C "$REPO" diff fixture-folded -- skills/product-rd-workflow/SKILL.md | grep -E '^\+[^+]')" ] \
  || fail "deletion fixture must add no line to the owner entrypoint"
printf '| Fixture routing-surface deletion row | `downstream-executor` | behavioral-evidence: RED-baseline; observed-failure: yes; firing-path: file:skills/product-rd-workflow/SKILL.md#description | `updated` | `product-rd-workflow/SKILL.md` deleted continuation line |\n' >> "$REGISTER"
commit_case "routing-surface: continuation line deleted, nothing added"
run_gate
assert_rc "$rc" 0 "a description change that only deletes a continuation line must still qualify"

# Turning the description into a nested MAPPING would let arbitrary frontmatter
# ride inside the entry — and even carry the anchor — if the entry boundary were
# the only check. The value must still be a string.
new_case case-routing-surface-nested-mapping-refused
perl -0pi -e 's/^description: .+$/description:\n  hidden_key: Fixture routing-surface trigger clause/m' \
  "$REPO/skills/product-rd-workflow/SKILL.md"
printf '| Fixture routing-surface nested row | `downstream-executor` | behavioral-evidence: RED-baseline; observed-failure: yes; firing-path: file:skills/product-rd-workflow/SKILL.md#description | `updated` | `product-rd-workflow/SKILL.md` nested description |\n' >> "$REGISTER"
commit_case "routing-surface: description turned into a nested mapping"
run_gate
assert_rc "$rc" 1 "a description that is not a string must lose the anchor widening"

# A folded scalar may contain a blank line between paragraphs. Stopping the entry
# at the blank line would push the later paragraph into the "other keys" set and
# refuse an ordinary description edit.
new_case case-routing-surface-blank-line-in-folded-description
perl -0pi -e 's/^description: (.+)$/description: >-\n  $1\n\n  Fixture routing-surface trigger clause./m' \
  "$REPO/skills/product-rd-workflow/SKILL.md"
printf '| Fixture routing-surface blank-line row | `downstream-executor` | behavioral-evidence: RED-baseline; observed-failure: yes; firing-path: file:skills/product-rd-workflow/SKILL.md#description | `updated` | `product-rd-workflow/SKILL.md` folded description with blank line |\n' >> "$REGISTER"
commit_case "routing-surface: folded description containing a blank line"
run_gate
assert_rc "$rc" 0 "a blank line inside a folded description must not break the entry boundary"

# The locator for this class is the canonical field name. A free-text substring
# that merely SURVIVED the edit identifies nothing, so it must not be accepted.
new_case case-routing-surface-surviving-substring-locator-refused
perl -0pi -e 's/^(description: .+)$/$1 Fixture routing-surface trigger clause./m' \
  "$REPO/skills/product-rd-workflow/SKILL.md"
printf '| Fixture routing-surface substring row | `downstream-executor` | behavioral-evidence: RED-baseline; observed-failure: yes; firing-path: file:skills/product-rd-workflow/SKILL.md#Fixture routing-surface trigger clause | `updated` | `product-rd-workflow/SKILL.md` substring locator |\n' >> "$REGISTER"
commit_case "routing-surface: free-text substring locator"
run_gate
assert_rc "$rc" 1 "a free-text substring must not serve as the locator for this class"

# A quoted top-level key is valid YAML; refusing it would block a legitimate
# description-only change with no satisfiable anchor.
new_case case-routing-surface-quoted-key
perl -0pi -e 's/^description: (.+)$/"description": $1 Fixture routing-surface trigger clause./m' \
  "$REPO/skills/product-rd-workflow/SKILL.md"
printf '| Fixture routing-surface quoted row | `downstream-executor` | behavioral-evidence: RED-baseline; observed-failure: yes; firing-path: file:skills/product-rd-workflow/SKILL.md#description | `updated` | `product-rd-workflow/SKILL.md` quoted description key |\n' >> "$REGISTER"
commit_case "routing-surface: quoted description key"
run_gate
assert_rc "$rc" 0 "a quoted description key must still qualify"

# A sibling frontmatter key that deserializes to a Date (or uses an alias) must
# not refuse the class: this check cares only about the description value.
new_case case-routing-surface-date-sibling-key
perl -0pi -e 's/^(name: product-rd-workflow)$/$1\nreleased: 2026-08-11/m' "$REPO/skills/product-rd-workflow/SKILL.md"
git -C "$REPO" add -A; git -C "$REPO" commit -qm "seed date sibling key"
git -C "$REPO" branch -f fixture-dated HEAD
git -C "$REPO" switch -q -C case-routing-surface-date-sibling-key fixture-dated
git -C "$REPO" branch --set-upstream-to=fixture-dated case-routing-surface-date-sibling-key >/dev/null 2>&1
perl -0pi -e 's/^(description: .+)$/$1 Fixture routing-surface trigger clause./m' "$REPO/skills/product-rd-workflow/SKILL.md"
printf '| Fixture routing-surface dated row | `downstream-executor` | behavioral-evidence: RED-baseline; observed-failure: yes; firing-path: file:skills/product-rd-workflow/SKILL.md#description | `updated` | `product-rd-workflow/SKILL.md` description beside a date key |\n' >> "$REGISTER"
commit_case "routing-surface: date-valued sibling frontmatter key"
run_gate
assert_rc "$rc" 0 "a date-valued sibling key must not refuse the class"

# A date-less host must not change any verdict. On hosts where `require "yaml"`
# leaves Date undefined (apt ruby 3.2 / psych <= 5.2.5: psych loads date lazily
# or not at all), a gate that rides on psych's transitive load raises NameError
# at `permitted_classes: [Date, Time]`, which `rescue StandardError` folds into
# "not a scalar description" — silently refusing the routing-surface class on
# one host while granting it on another. The gate must declare `require "date"`
# itself. The shim reproduces that host class on any modern ruby: it blocks
# psych's transitive date require while letting explicit ones through.
DATELESS_SHIM="$TMP/dateless-require-shim.rb"
cat > "$DATELESS_SHIM" <<'RUBY'
module DatelessRequireShim
  def require(name)
    if name == "date" && caller.any? { |frame| frame.include?("/psych") || frame.include?("psych.rb") }
      return false
    end
    super
  end
end
Object.prepend(DatelessRequireShim)
RUBY
run_gate_dateless() {
  gate_runs=$((gate_runs + 1))
  set +e
  out="$(env -u ALIAS_AUDIT_CMD -u CCL_SKILL_BASE_REF RUBYOPT="-r$DATELESS_SHIM" ruby "$GATE_SCRIPT" "$REPO" 2>&1)"
  rc=$?
  set -e
}
new_case case-routing-surface-dateless-host
perl -0pi -e 's/^(description: .+)$/$1 Fixture routing-surface trigger clause./m' "$REPO/skills/product-rd-workflow/SKILL.md"
printf '| Fixture routing-surface dateless row | `downstream-executor` | behavioral-evidence: RED-baseline; observed-failure: yes; firing-path: file:skills/product-rd-workflow/SKILL.md#description | `updated` | `product-rd-workflow/SKILL.md` description judged on a date-less host |\n' >> "$REGISTER"
commit_case "routing-surface: description-only change judged on a date-less host"
run_gate_dateless
assert_rc "$rc" 0 "a date-less host must not refuse the routing-surface class"

# Mutation attribution for the property this case names: strip the gate's own
# `require "date"` and the same fixture must show the date-less refusal. The
# cmp guard proves the mutation actually removed a line — if the require is
# ever renamed or dropped, this fails loudly instead of running a no-op
# differential that would false-green a broken shim or a regressed gate.
GATE_DATELESS_MUTANT="$TMP/impact-chain-gate-dateless-mutant.rb"
grep -v '^require "date"$' "$GATE_SCRIPT" > "$GATE_DATELESS_MUTANT"
cmp -s "$GATE_SCRIPT" "$GATE_DATELESS_MUTANT" && fail "dateless mutation is a no-op: the gate no longer contains its require \"date\" line"
run_gate_dateless_mutant() {
  gate_runs=$((gate_runs + 1))
  set +e
  out="$(env -u ALIAS_AUDIT_CMD -u CCL_SKILL_BASE_REF RUBYOPT="-r$DATELESS_SHIM" ruby "$GATE_DATELESS_MUTANT" "$REPO" 2>&1)"
  rc=$?
  set -e
}
run_gate_dateless_mutant
assert_rc "$rc" 1 "without its own require-date the gate must show the date-less refusal this case guards against"
assert_contains "impact_chain_firing_path_missing" "$out" "the mutant must fail for the guarded reason, not some other error"
assert_contains "product-rd-workflow/SKILL.md" "$out" "the mutant must name the refused owner"

# The deepest Date-dependent path on a date-less host: safe_load must actually
# instantiate a Date for the sibling key, so this proves the explicit require
# makes the constant real, not merely referenceable.
git -C "$REPO" switch -q -C case-routing-surface-dateless-dated-sibling fixture-dated
git -C "$REPO" branch --set-upstream-to=fixture-dated case-routing-surface-dateless-dated-sibling >/dev/null 2>&1
perl -0pi -e 's/^(description: .+)$/$1 Fixture routing-surface trigger clause./m' "$REPO/skills/product-rd-workflow/SKILL.md"
printf '| Fixture routing-surface dateless dated row | `downstream-executor` | behavioral-evidence: RED-baseline; observed-failure: yes; firing-path: file:skills/product-rd-workflow/SKILL.md#description | `updated` | `product-rd-workflow/SKILL.md` dated sibling on a date-less host |\n' >> "$REGISTER"
commit_case "routing-surface: date-valued sibling judged on a date-less host"
run_gate_dateless
assert_rc "$rc" 0 "parsing a date-valued sibling on a date-less host must still qualify"

# A file MOVED OUT of the owner package must take back the ordinary bar: the diff
# is read with --no-renames, so the vacated path still counts as an owner change.
new_case case-routing-surface-file-moved-out
perl -0pi -e 's/^(description: .+)$/$1 Fixture routing-surface trigger clause./m' "$REPO/skills/product-rd-workflow/SKILL.md"
mkdir -p "$REPO/docs"
git -C "$REPO" mv "$MOVEOUT_REL" docs/zz-fixture-moveout.md
printf '| Fixture routing-surface moveout row | `downstream-executor` | behavioral-evidence: RED-baseline; observed-failure: yes; firing-path: file:skills/product-rd-workflow/SKILL.md#description | `updated` | `product-rd-workflow/SKILL.md` description plus a file moved out |\n' >> "$REGISTER"
commit_case "routing-surface: owner file moved out of the package"
run_gate
assert_rc "$rc" 1 "a file moved out of the package must take back the ordinary bar"

# The entrypoint's MODE is part of its identity: bytes alone would let a chmod
# ride along with a description edit and still read as description-only.
new_case case-routing-surface-mode-change-refused
perl -0pi -e 's/^(description: .+)$/$1 Fixture routing-surface trigger clause./m' "$REPO/skills/product-rd-workflow/SKILL.md"
chmod +x "$REPO/skills/product-rd-workflow/SKILL.md"
printf '| Fixture routing-surface mode row | `downstream-executor` | behavioral-evidence: RED-baseline; observed-failure: yes; firing-path: file:skills/product-rd-workflow/SKILL.md#description | `updated` | `product-rd-workflow/SKILL.md` description plus mode change |\n' >> "$REGISTER"
commit_case "routing-surface: entrypoint mode changed alongside the description"
run_gate
assert_rc "$rc" 1 "a mode change riding along must take back the ordinary bar"

# An owner whose entrypoint changed only its description, while the REST of its
# package changed only by a rename retarget, still carries exactly one behaviour:
# the description. The retarget is already a machine-proven no-behaviour class, so
# refusing the locator here would refuse an owner with nothing else to evidence —
# and on an integration branch that accumulates rounds, that is the normal shape.
new_case case-routing-surface-with-retargeted-sibling
git -C "$REPO" mv skills/platform-observability skills/platform-signal-evidence
git -C "$REPO" mv skills/platform-signal-evidence/references/platform-observability-playbook.md \
                  skills/platform-signal-evidence/references/platform-signal-evidence-playbook.md
retarget_all "$REPO/skills/platform-signal-evidence" "$REPO/skills/defect-diagnosis" "$REPO/skills/product-rd-workflow"
perl -0pi -e 's/^(description: .+)$/$1 Fixture routing-surface trigger clause./m' "$REPO/skills/product-rd-workflow/SKILL.md"
printf '\n- Never skip the fixture renamed-owner rule for this gate.\n' >> "$REPO/skills/platform-signal-evidence/SKILL.md"
printf '| Fixture retargeted-sibling row | `downstream-executor` | behavioral-evidence: RED-baseline; observed-failure: yes; firing-path: file:skills/product-rd-workflow/SKILL.md#description | `updated` | `product-rd-workflow/SKILL.md` description beside retargeted references |\n' >> "$REGISTER"
printf '| Fixture retargeted-sibling dependent row | `downstream-executor` | behavioral-evidence: not-required identifier-rename; observed-failure: no | `updated` | `defect-diagnosis/SKILL.md` pointer retarget only |\n' >> "$REGISTER"
printf '| Fixture retargeted-sibling owner row | `downstream-executor` | behavioral-evidence: RED-baseline; observed-failure: no; firing-path: file:skills/platform-signal-evidence/SKILL.md#Never skip the fixture renamed-owner rule | `updated` | `platform-signal-evidence/SKILL.md` renamed owner |\n' >> "$REGISTER"
# Keep this case's only script untouched so it varies exactly one thing.
git -C "$REPO" checkout fixture-base -- skills/product-rd-workflow/scripts/check-agent-contract-coverage.sh
[ -n "$(git -C "$REPO" diff --name-only fixture-base -- 'skills/product-rd-workflow/references/*.md')" ] \
  || fail "positive case must actually retarget an eligible .md sibling"
commit_case "routing-surface: description beside a pure rename retarget in the same package"
run_gate
assert_rc "$rc" 0 "a package whose non-entrypoint changes are a proven retarget must not lose the locator"

# The composition is bounded by the SAME byte-exact reproduction: a sibling file
# carrying real content beside the retarget still takes the locator away.
new_case case-routing-surface-retarget-plus-real-edit
git -C "$REPO" mv skills/platform-observability skills/platform-signal-evidence
git -C "$REPO" mv skills/platform-signal-evidence/references/platform-observability-playbook.md \
                  skills/platform-signal-evidence/references/platform-signal-evidence-playbook.md
retarget_all "$REPO/skills/platform-signal-evidence" "$REPO/skills/defect-diagnosis" "$REPO/skills/product-rd-workflow"
perl -0pi -e 's/^(description: .+)$/$1 Fixture routing-surface trigger clause./m' "$REPO/skills/product-rd-workflow/SKILL.md"
printf '\n- Never skip the smuggled fixture rule beside the retarget.\n' >> "$REPO/$UPSTREAM_REF"
printf '\n- Never skip the fixture renamed-owner rule for this gate.\n' >> "$REPO/skills/platform-signal-evidence/SKILL.md"
printf '| Fixture retarget-plus-edit row | `downstream-executor` | behavioral-evidence: RED-baseline; observed-failure: yes; firing-path: file:skills/product-rd-workflow/SKILL.md#description | `updated` | `product-rd-workflow/SKILL.md` description plus a real sibling edit |\n' >> "$REGISTER"
printf '| Fixture retarget-plus-edit dependent row | `downstream-executor` | behavioral-evidence: not-required identifier-rename; observed-failure: no | `updated` | `defect-diagnosis/SKILL.md` pointer retarget only |\n' >> "$REGISTER"
printf '| Fixture retarget-plus-edit owner row | `downstream-executor` | behavioral-evidence: RED-baseline; observed-failure: no; firing-path: file:skills/platform-signal-evidence/SKILL.md#Never skip the fixture renamed-owner rule | `updated` | `platform-signal-evidence/SKILL.md` renamed owner |\n' >> "$REGISTER"
# Keep this case's only script untouched so it varies exactly one thing.
git -C "$REPO" checkout fixture-base -- skills/product-rd-workflow/scripts/check-agent-contract-coverage.sh
commit_case "routing-surface: real sibling edit beside the retarget"
run_gate
assert_rc "$rc" 1 "real content beside the retarget must still take the locator away"

# A script reproducing under the substitution proves nothing about whether
# rewriting that identifier was safe there — some occurrences of an old slug are
# deliberately kept. Prose only.
new_case case-routing-surface-retargeted-script-refused
git -C "$REPO" mv skills/platform-observability skills/platform-signal-evidence
git -C "$REPO" mv skills/platform-signal-evidence/references/platform-observability-playbook.md \
                  skills/platform-signal-evidence/references/platform-signal-evidence-playbook.md
retarget_all "$REPO/skills/platform-signal-evidence" "$REPO/skills/defect-diagnosis" "$REPO/skills/product-rd-workflow"
perl -0pi -e 's/^(description: .+)$/$1 Fixture routing-surface trigger clause./m' "$REPO/skills/product-rd-workflow/SKILL.md"
printf '\n- Never skip the fixture renamed-owner rule for this gate.\n' >> "$REPO/skills/platform-signal-evidence/SKILL.md"
printf '| Fixture retargeted-script row | `downstream-executor` | behavioral-evidence: RED-baseline; observed-failure: yes; firing-path: file:skills/product-rd-workflow/SKILL.md#description | `updated` | `product-rd-workflow/SKILL.md` description beside a changed script |\n' >> "$REGISTER"
printf '| Fixture retargeted-script dependent row | `downstream-executor` | behavioral-evidence: not-required identifier-rename; observed-failure: no | `updated` | `defect-diagnosis/SKILL.md` pointer retarget only |\n' >> "$REGISTER"
printf '| Fixture retargeted-script owner row | `downstream-executor` | behavioral-evidence: RED-baseline; observed-failure: no; firing-path: file:skills/platform-signal-evidence/SKILL.md#Never skip the fixture renamed-owner rule | `updated` | `platform-signal-evidence/SKILL.md` renamed owner |\n' >> "$REGISTER"
commit_case "routing-surface: a changed script in the package"
run_gate
assert_rc "$rc" 1 "a changed script must take the locator away even under a retarget"

# A `.md` SYMLINK's blob is its target, so a retargeted target reproduces under
# the substitution while what the path resolves to changes. Regular files only.
git -C "$REPO" switch -q -C fixture-symlink fixture-base
ln -s ../../platform-observability/SKILL.md "$REPO/skills/product-rd-workflow/references/zz-fixture-link.md"
git -C "$REPO" add -A; git -C "$REPO" commit -qm "seed pre-rename symlink"
git -C "$REPO" switch -q -C case-routing-surface-retargeted-symlink-refused fixture-symlink
git -C "$REPO" branch --set-upstream-to=fixture-symlink case-routing-surface-retargeted-symlink-refused >/dev/null 2>&1
rm -f "$REPO/skills/product-rd-workflow/references/zz-fixture-link.md"
git -C "$REPO" mv skills/platform-observability skills/platform-signal-evidence
git -C "$REPO" mv skills/platform-signal-evidence/references/platform-observability-playbook.md \
                  skills/platform-signal-evidence/references/platform-signal-evidence-playbook.md
retarget_all "$REPO/skills/platform-signal-evidence" "$REPO/skills/defect-diagnosis" "$REPO/skills/product-rd-workflow"
git -C "$REPO" checkout fixture-base -- skills/product-rd-workflow/scripts/check-agent-contract-coverage.sh
ln -s ../../platform-signal-evidence/SKILL.md "$REPO/skills/product-rd-workflow/references/zz-fixture-link.md"
perl -0pi -e 's/^(description: .+)$/$1 Fixture routing-surface trigger clause./m' "$REPO/skills/product-rd-workflow/SKILL.md"
printf '\n- Never skip the fixture renamed-owner rule for this gate.\n' >> "$REPO/skills/platform-signal-evidence/SKILL.md"
printf '| Fixture symlink row | `downstream-executor` | behavioral-evidence: RED-baseline; observed-failure: yes; firing-path: file:skills/product-rd-workflow/SKILL.md#description | `updated` | `product-rd-workflow/SKILL.md` description beside a retargeted symlink |\n' >> "$REGISTER"
printf '| Fixture symlink dependent row | `downstream-executor` | behavioral-evidence: not-required identifier-rename; observed-failure: no | `updated` | `defect-diagnosis/SKILL.md` pointer retarget only |\n' >> "$REGISTER"
printf '| Fixture symlink owner row | `downstream-executor` | behavioral-evidence: RED-baseline; observed-failure: no; firing-path: file:skills/platform-signal-evidence/SKILL.md#Never skip the fixture renamed-owner rule | `updated` | `platform-signal-evidence/SKILL.md` renamed owner |\n' >> "$REGISTER"
commit_case "routing-surface: a retargeted .md symlink in the package"
run_gate
assert_rc "$rc" 1 "a retargeted .md symlink must take the locator away"

# --- Round scoping -----------------------------------------------------------
# Every case above lands in ONE commit, so it exercises a single round and cannot
# see the defect these two cover: the classifiers used to read the whole
# base..HEAD range while each row is authored against one round's diff. Both
# cases below FAIL against the range-scoped gate and pass against the
# round-scoped one, which is what makes them a baseline rather than a restatement.

# Round scoping 1: a row's verdict must not move after it lands. Round 1 is a
# genuinely punctuation-only edit declared `not-required wording-only`; round 2
# then edits the SAME owner substantively. Judged against the accumulating range
# the round-1 row turns red retroactively, which is what forced the ledger's
# superseded-row notes.
new_case case-round-scope-verdict-stability
printf '\n***\n' >> "$REPO/$UPSTREAM_REF"
printf '| Fixture round-1 punctuation edit | `downstream-executor` | behavioral-evidence: not-required wording-only; observed-failure: no | `updated` | `product-rd-workflow/SKILL.md` punctuation-only round |\n' >> "$REGISTER"
commit_case "round 1: punctuation-only edit declared wording-only"
printf '\n- Never bypass the fixture round-scope rule for this gate.\n' >> "$REPO/$UPSTREAM_REF"
printf '| Fixture round-2 substantive edit | `downstream-executor` | behavioral-evidence: RED-baseline; observed-failure: yes; firing-path: file:skills/product-rd-workflow/references/adr-convention.md#Never bypass the fixture round-scope rule | `updated` | `product-rd-workflow/SKILL.md` substantive round |\n' >> "$REGISTER"
commit_case "round 2: substantive edit to the same owner"
run_gate
assert_rc "$rc" 0 "a landed wording-only row must not be re-judged against a later round"
assert_not_contains "impact_chain_behavior_evidence_missing" "$out" "the round-1 row stays valid in its own round"

# Round scoping 2: a description-only round must keep its locator even when an
# EARLIER round edited the same owner's body. Against the accumulating range the
# routing-surface class sees a changed body and refuses the anchor, which is why
# a real round had to drop its product-rd-workflow row before landing.
new_case case-round-scope-description-after-body
printf '\n- Never skip the fixture body-round rule for this gate.\n' >> "$REPO/skills/product-rd-workflow/SKILL.md"
printf '| Fixture body round | `downstream-executor` | behavioral-evidence: RED-baseline; observed-failure: yes; firing-path: file:skills/product-rd-workflow/SKILL.md#Never skip the fixture body-round rule | `updated` | `product-rd-workflow/SKILL.md` body round |\n' >> "$REGISTER"
commit_case "round 1: body rule added to the entrypoint"
perl -0pi -e 's/^(description: .+)$/$1 Fixture round-scope routing clause./m' "$REPO/skills/product-rd-workflow/SKILL.md"
printf '| Fixture description round | `downstream-executor` | behavioral-evidence: RED-baseline; observed-failure: yes; firing-path: file:skills/product-rd-workflow/SKILL.md#description | `updated` | `product-rd-workflow/SKILL.md` description-only round |\n' >> "$REGISTER"
commit_case "round 2: description-only edit to the same owner"
run_gate
assert_rc "$rc" 0 "a description-only round keeps its locator after an earlier body round"
assert_not_contains "impact_chain_firing_path_missing" "$out" "the description anchor must bind in its own round"

# Round scoping 3: the narrowing must not become a laundering route. Owner work
# committed AFTER the last ledger append sits in the trailing round, which holds
# no rows — an earlier round's row must not cover it.
new_case case-round-scope-trailing-work-uncovered
printf '\n- Never skip the fixture trailing rule for this gate.\n' >> "$REPO/skills/platform-observability/SKILL.md"
printf '| Fixture trailing round 1 | `downstream-executor` | behavioral-evidence: RED-baseline; observed-failure: yes; firing-path: file:skills/platform-observability/SKILL.md#Never skip the fixture trailing rule | `updated` | `platform-observability/SKILL.md` declared round |\n' >> "$REGISTER"
commit_case "round 1: declared owner change"
printf '\nFixture undeclared trailing edit that no row covers.\n' >> "$REPO/skills/platform-observability/references/platform-observability-playbook.md"
commit_case "trailing round: owner edit with no ledger append"
run_gate
assert_rc "$rc" 1 "owner work in the trailing round must not ride on an earlier round's row"

# Round scoping 4: a row must SURVIVE at HEAD to count. Round scoping alone reads
# each round's added lines, so a row appended in round 1 and deleted in round 2
# still looked "added" — the cumulative read this replaced saw a net zero and
# failed closed. Without this the narrowing becomes an append-then-drop laundering
# route, which is the shape a loosening change has to be checked hardest for.
new_case case-round-scope-deleted-row-does-not-count
printf '\n- Never skip the fixture survival rule for this gate.\n' >> "$REPO/skills/platform-observability/SKILL.md"
printf '| Fixture survival row | `downstream-executor` | behavioral-evidence: RED-baseline; observed-failure: yes; firing-path: file:skills/platform-observability/SKILL.md#Never skip the fixture survival rule | `updated` | `platform-observability/SKILL.md` declared round |\n' >> "$REGISTER"
commit_case "round 1: owner change with its row"
perl -ni -e 'print unless /Fixture survival row/' "$REGISTER"
commit_case "round 2: delete the row that vouched for it"
run_gate
assert_rc "$rc" 1 "a row deleted in a later round must not still vouch for the owner"
assert_contains "impact_chain_gate_missing" "$out" "a deleted row leaves the owner undeclared"

# Round scoping 5: survival is a MULTISET, not a set. When the row text ALREADY
# exists at base, appending a duplicate in the round that needs a row and dropping
# one copy in a later ledger-only round leaves the ledger byte-identical — a
# net-zero the cumulative read rejected. A boolean "text exists at HEAD" check
# would read the transient duplicate as surviving, so the budget is HEAD's
# occurrence count minus base's.
new_case case-round-scope-duplicate-row-laundering
printf '| Fixture duplicate row | `downstream-executor` | behavioral-evidence: RED-baseline; observed-failure: yes; firing-path: file:skills/platform-observability/SKILL.md#Never skip the fixture duplicate rule | `updated` | `platform-observability/SKILL.md` pre-existing row |\n' >> "$REGISTER"
printf '\n- Never skip the fixture duplicate rule for this gate.\n' >> "$REPO/skills/platform-observability/SKILL.md"
commit_case "base: an owner change and its row, both already landed"
git -C "$REPO" branch -q -f dup-base HEAD
git -C "$REPO" branch --set-upstream-to=dup-base case-round-scope-duplicate-row-laundering >/dev/null 2>&1
printf '\nFixture second substantive edit that owes its own row.\n' >> "$REPO/skills/platform-observability/references/platform-observability-playbook.md"
printf '| Fixture duplicate row | `downstream-executor` | behavioral-evidence: RED-baseline; observed-failure: yes; firing-path: file:skills/platform-observability/SKILL.md#Never skip the fixture duplicate rule | `updated` | `platform-observability/SKILL.md` pre-existing row |\n' >> "$REGISTER"
commit_case "round 1: new owner bytes plus a duplicate of the existing row"
perl -ni -e 'BEGIN{$n=0} if (/Fixture duplicate row/) { $n++; next if $n == 1 } print' "$REGISTER"
commit_case "round 2: drop one copy so the ledger ends unchanged"
run_gate
assert_rc "$rc" 1 "a duplicated-then-dropped row must not vouch for new owner bytes"
assert_contains "impact_chain_gate_missing" "$out" "the net-zero ledger leaves the owner undeclared"

# Round scoping 6: the partition's central claim is that ONE MERGED worktree round
# is ONE boundary — and this repo's integration branch is nothing but merge commits,
# so a linear-only fixture set proves nothing about the shape the gate actually runs
# on. `git rev-list --first-parent -- <path>` applies history simplification, so the
# merge is a boundary only when it is not TREESAME to its first parent. These two
# cases pin that behaviour instead of asserting it in a comment.
new_case case-round-scope-merged-worktree-round
git -C "$REPO" switch -q -c feature-round-merged
printf '\n- Never skip the fixture merged-round rule for this gate.\n' >> "$REPO/skills/platform-observability/SKILL.md"
commit_case "worktree round: owner work"
printf '| Fixture merged round | `downstream-executor` | behavioral-evidence: RED-baseline; observed-failure: yes; firing-path: file:skills/platform-observability/SKILL.md#Never skip the fixture merged-round rule | `updated` | `platform-observability/SKILL.md` merged round |\n' >> "$REGISTER"
commit_case "worktree round: its ledger append"
git -C "$REPO" switch -q case-round-scope-merged-worktree-round
git -C "$REPO" merge -q --no-ff -m "Merge branch 'feature-round-merged': one worktree round" feature-round-merged
run_gate
assert_rc "$rc" 0 "a merged worktree round must resolve to one boundary covering its own work"

# The same shape, with undeclared work committed AFTER the merge: the trailing round
# holds no rows, so the merged round's row must not reach forward to cover it.
new_case case-round-scope-after-merged-round
git -C "$REPO" switch -q -c feature-round-merged-2
printf '\n- Never skip the fixture merged-round rule for this gate.\n' >> "$REPO/skills/platform-observability/SKILL.md"
printf '| Fixture merged round 2 | `downstream-executor` | behavioral-evidence: RED-baseline; observed-failure: yes; firing-path: file:skills/platform-observability/SKILL.md#Never skip the fixture merged-round rule | `updated` | `platform-observability/SKILL.md` merged round |\n' >> "$REGISTER"
commit_case "worktree round: owner work and its ledger append"
git -C "$REPO" switch -q case-round-scope-after-merged-round
git -C "$REPO" merge -q --no-ff -m "Merge branch 'feature-round-merged-2': one worktree round" feature-round-merged-2
printf '\nFixture undeclared edit committed after the merged round.\n' >> "$REPO/skills/platform-observability/references/platform-observability-playbook.md"
commit_case "after the merge: undeclared owner edit"
run_gate
assert_rc "$rc" 1 "work committed after a merged round must not ride on that round's row"

# Round scoping 7: a renamed-away owner must not escape the rounds BEFORE its
# rename. Round 1 substantively changes an owner and a ledger append closes that
# round with no row for it; round 2 renames the owner away with a row on the
# surviving name. The cumulative pass rightly excuses the old name for the
# RENAME round — but the pre-rename round still owes the row, and since the
# evidence check reads each row against its own round head that row was never
# impossible to write.
new_case case-round-scope-renamed-away-pre-rename-round
printf '\n- Never skip the fixture pre-rename rule for this gate.\n' >> "$REPO/skills/platform-observability/SKILL.md"
commit_case "round 1: owner work with no row"
printf 'Fixture ledger note closing round one without the owner row.\n' >> "$REGISTER"
commit_case "round 1 boundary: ledger append without the owner row"
git -C "$REPO" mv skills/platform-observability skills/platform-signal-evidence
printf '\n- MUST enforce Fixture renamed owner rule.\n' >> "$REPO/skills/platform-signal-evidence/SKILL.md"
printf '| Fixture renamed owner row | `downstream-executor` | behavioral-evidence: RED-baseline; observed-failure: yes; firing-path: file:skills/platform-signal-evidence/SKILL.md#Fixture renamed owner rule | `updated` | `platform-signal-evidence/SKILL.md` renamed owner |\n' >> "$REGISTER"
commit_case "round 2: rename the owner with a row on the surviving name"
run_gate
assert_rc "$rc" 1 "owner work in a pre-rename round must not escape with the later rename"
assert_contains "impact_chain_gate_missing" "$out" "the pre-rename round's work is undeclared"
assert_contains "platform-observability/SKILL.md" "$out" "the missing row must name the owner under its pre-rename name"

# The legitimate counterpart: the pre-rename round DID carry its row, citing the
# owner name that existed at that round's head. The rename must not retroactively
# invalidate it — rejecting it would demand a row no honest author could write.
new_case case-round-scope-renamed-away-row-at-round-head
printf '\n- Never skip the fixture pre-rename declared rule for this gate.\n' >> "$REPO/skills/platform-observability/SKILL.md"
printf '| Fixture pre-rename declared row | `downstream-executor` | behavioral-evidence: RED-baseline; observed-failure: yes; firing-path: file:skills/platform-observability/SKILL.md#Never skip the fixture pre-rename declared rule | `updated` | `platform-observability/SKILL.md` pre-rename round |\n' >> "$REGISTER"
commit_case "round 1: owner work with its row"
git -C "$REPO" mv skills/platform-observability skills/platform-signal-evidence
printf '\n- MUST enforce Fixture renamed owner rule.\n' >> "$REPO/skills/platform-signal-evidence/SKILL.md"
printf '| Fixture renamed owner row | `downstream-executor` | behavioral-evidence: RED-baseline; observed-failure: yes; firing-path: file:skills/platform-signal-evidence/SKILL.md#Fixture renamed owner rule | `updated` | `platform-signal-evidence/SKILL.md` renamed owner |\n' >> "$REGISTER"
commit_case "round 2: rename the owner with a row on the surviving name"
run_gate
assert_rc "$rc" 0 "a pre-rename round declared against its own round head must pass"
assert_not_contains "impact_chain_evidence_missing_file" "$out" "a row citing the name that existed at its round head is valid evidence"

# Round scoping 8: the --first-parent discriminator. On the branch the ledger
# append lands BEFORE the owner work; first-parent collapses the merged branch
# to one boundary (the merge), so row and work share a round. A full walk would
# instead cut the round at the branch's ledger commit, stranding the work in a
# rowless later round — so this fixture goes red if --first-parent is dropped,
# which is what proves the flag load-bearing.
new_case case-round-scope-merged-row-before-work
git -C "$REPO" switch -q -c feature-round-row-first
printf '| Fixture row-first merged round | `downstream-executor` | behavioral-evidence: RED-baseline; observed-failure: yes; firing-path: file:skills/platform-observability/SKILL.md#Never skip the fixture row-first rule | `updated` | `platform-observability/SKILL.md` merged round |\n' >> "$REGISTER"
commit_case "worktree round: ledger append first"
printf '\n- Never skip the fixture row-first rule for this gate.\n' >> "$REPO/skills/platform-observability/SKILL.md"
commit_case "worktree round: owner work after the append"
git -C "$REPO" switch -q case-round-scope-merged-row-before-work
git -C "$REPO" merge -q --no-ff -m "Merge branch 'feature-round-row-first': one worktree round" feature-round-row-first
run_gate
assert_rc "$rc" 0 "a merged worktree round collapses to one boundary even when the row precedes the work"

# Round scoping 9: a TRANSIENT intermediate rename hop must not launder work.
# X renames to Y (declared), a later round substantively changes Y with no row,
# then Y renames to Z (declared). The cumulative diff sees only X and Z, so Y is
# in neither the cumulative selection nor the excused set — selection must follow
# the rename lineage through each round's own pairs, or the Y round escapes.
new_case case-round-scope-transient-rename-hop-undeclared
git -C "$REPO" mv skills/platform-observability skills/platform-signal-evidence
printf '\n- MUST enforce Fixture renamed owner rule.\n' >> "$REPO/skills/platform-signal-evidence/SKILL.md"
printf '| Fixture renamed owner row | `downstream-executor` | behavioral-evidence: RED-baseline; observed-failure: yes; firing-path: file:skills/platform-signal-evidence/SKILL.md#Fixture renamed owner rule | `updated` | `platform-signal-evidence/SKILL.md` renamed owner |\n' >> "$REGISTER"
commit_case "round A: rename X to Y with a row on the surviving name"
printf '\n- Never skip the fixture transient-hop rule for this gate.\n' >> "$REPO/skills/platform-signal-evidence/SKILL.md"
printf 'Fixture ledger note closing the transient round without the owner row.\n' >> "$REGISTER"
commit_case "round B: substantive Y edit closed with no Y row"
git -C "$REPO" mv skills/platform-signal-evidence skills/platform-telemetry-evidence
printf '\n- MUST enforce Fixture final renamed owner rule.\n' >> "$REPO/skills/platform-telemetry-evidence/SKILL.md"
printf '| Fixture final renamed owner row | `downstream-executor` | behavioral-evidence: RED-baseline; observed-failure: yes; firing-path: file:skills/platform-telemetry-evidence/SKILL.md#Fixture final renamed owner rule | `updated` | `platform-telemetry-evidence/SKILL.md` renamed owner |\n' >> "$REGISTER"
commit_case "round C: rename Y to Z with a row on the surviving name"
run_gate
assert_rc "$rc" 1 "a substantive round on a transient rename hop must not escape undeclared"
assert_contains "impact_chain_gate_missing" "$out" "the transient-hop round's work is undeclared"
assert_contains "platform-signal-evidence/SKILL.md" "$out" "the missing row must name the transient owner"

# The declared counterpart: the transient-hop round carries its own row citing
# the name that existed at that round's head; the whole chain must pass.
new_case case-round-scope-transient-rename-hop-declared
git -C "$REPO" mv skills/platform-observability skills/platform-signal-evidence
printf '\n- MUST enforce Fixture renamed owner rule.\n' >> "$REPO/skills/platform-signal-evidence/SKILL.md"
printf '| Fixture renamed owner row | `downstream-executor` | behavioral-evidence: RED-baseline; observed-failure: yes; firing-path: file:skills/platform-signal-evidence/SKILL.md#Fixture renamed owner rule | `updated` | `platform-signal-evidence/SKILL.md` renamed owner |\n' >> "$REGISTER"
commit_case "round A: rename X to Y with a row on the surviving name"
printf '\n- Never skip the fixture transient-hop rule for this gate.\n' >> "$REPO/skills/platform-signal-evidence/SKILL.md"
printf '| Fixture transient hop row | `downstream-executor` | behavioral-evidence: RED-baseline; observed-failure: yes; firing-path: file:skills/platform-signal-evidence/SKILL.md#Never skip the fixture transient-hop rule | `updated` | `platform-signal-evidence/SKILL.md` transient round |\n' >> "$REGISTER"
commit_case "round B: substantive Y edit with its own Y row"
git -C "$REPO" mv skills/platform-signal-evidence skills/platform-telemetry-evidence
printf '\n- MUST enforce Fixture final renamed owner rule.\n' >> "$REPO/skills/platform-telemetry-evidence/SKILL.md"
printf '| Fixture final renamed owner row | `downstream-executor` | behavioral-evidence: RED-baseline; observed-failure: yes; firing-path: file:skills/platform-telemetry-evidence/SKILL.md#Fixture final renamed owner rule | `updated` | `platform-telemetry-evidence/SKILL.md` renamed owner |\n' >> "$REGISTER"
commit_case "round C: rename Y to Z with a row on the surviving name"
run_gate
assert_rc "$rc" 0 "a declared transient-hop chain must pass end to end"
assert_not_contains "impact_chain_evidence_missing_file" "$out" "rows citing each hop's round-head name are valid evidence"

# Round scoping 10: deleting an owner in one round and recreating a lookalike
# under a new name in a LATER round must stay a deletion, not become a rename.
# The cumulative endpoints pair the delete with the later add, but no single
# round's own pairs contain the source — the excuse requires an atomic in-round
# rename, so the cross-round split keeps the deletion fail-closed.
new_case case-round-scope-delete-then-recreate-lookalike
cp -R "$REPO/skills/platform-observability" "$TMP/stash-lookalike"
git -C "$REPO" rm -qr skills/platform-observability
printf 'Fixture ledger note closing the deletion round without the owner row.\n' >> "$REGISTER"
commit_case "round A: delete the owner with no row"
cp -R "$TMP/stash-lookalike" "$REPO/skills/platform-signal-evidence"
retarget_all "$REPO/skills/platform-signal-evidence"
printf '\n- MUST enforce Fixture recreated owner rule.\n' >> "$REPO/skills/platform-signal-evidence/SKILL.md"
printf '| Fixture recreated owner row | `downstream-executor` | behavioral-evidence: RED-baseline; observed-failure: yes; firing-path: file:skills/platform-signal-evidence/SKILL.md#Fixture recreated owner rule | `updated` | `platform-signal-evidence/SKILL.md` recreated owner |\n' >> "$REGISTER"
commit_case "round B: recreate a lookalike under a new name with its own row"
run_gate
assert_rc "$rc" 1 "a cross-round delete-then-recreate must stay an undeclared deletion"
assert_contains "platform-observability/SKILL.md" "$out" "the deleted owner must stay a subject"

# Round scoping 11: a declared rename CYCLE (A to B, then B back to A) is an
# honest, fully-declared shape — each round's row cites the name that existed at
# its own round head. Demanding an A row in the round that renamed A away would
# ask for a row the evidence check must then refuse.
new_case case-round-scope-declared-rename-cycle
git -C "$REPO" mv skills/platform-observability skills/platform-signal-evidence
printf '\n- MUST enforce Fixture renamed owner rule.\n' >> "$REPO/skills/platform-signal-evidence/SKILL.md"
printf '| Fixture renamed owner row | `downstream-executor` | behavioral-evidence: RED-baseline; observed-failure: yes; firing-path: file:skills/platform-signal-evidence/SKILL.md#Fixture renamed owner rule | `updated` | `platform-signal-evidence/SKILL.md` renamed owner |\n' >> "$REGISTER"
commit_case "round 1: rename A to B with a row on the surviving name"
git -C "$REPO" mv skills/platform-signal-evidence skills/platform-observability
printf '\n- MUST enforce Fixture reverted owner rule.\n' >> "$REPO/skills/platform-observability/SKILL.md"
printf '| Fixture reverted owner row | `downstream-executor` | behavioral-evidence: RED-baseline; observed-failure: yes; firing-path: file:skills/platform-observability/SKILL.md#Fixture reverted owner rule | `updated` | `platform-observability/SKILL.md` reverted owner |\n' >> "$REGISTER"
commit_case "round 2: rename B back to A with a row on the surviving name"
run_gate
assert_rc "$rc" 0 "a fully-declared rename cycle must pass"
assert_not_contains "impact_chain_evidence_missing_file" "$out" "each round's row cites the name real at its own head"

# The undeclared half of the cycle: no row for B in the round that created it.
new_case case-round-scope-undeclared-rename-cycle
git -C "$REPO" mv skills/platform-observability skills/platform-signal-evidence
printf '\n- MUST enforce Fixture renamed owner rule.\n' >> "$REPO/skills/platform-signal-evidence/SKILL.md"
printf 'Fixture ledger note closing the outbound rename round without a row.\n' >> "$REGISTER"
commit_case "round 1: rename A to B with no row"
git -C "$REPO" mv skills/platform-signal-evidence skills/platform-observability
printf '\n- MUST enforce Fixture reverted owner rule.\n' >> "$REPO/skills/platform-observability/SKILL.md"
printf '| Fixture reverted owner row | `downstream-executor` | behavioral-evidence: RED-baseline; observed-failure: yes; firing-path: file:skills/platform-observability/SKILL.md#Fixture reverted owner rule | `updated` | `platform-observability/SKILL.md` reverted owner |\n' >> "$REGISTER"
commit_case "round 2: rename B back to A with a row on the surviving name"
run_gate
assert_rc "$rc" 1 "the round that created the transient name still owes its row"
assert_contains "platform-signal-evidence/SKILL.md" "$out" "the undeclared transient name must be demanded"

# Round scoping 12: a DIRECTORY masquerading as SKILL.md must read as absence.
# `git show ref:path` succeeds for a tree, so replacing the entrypoint with a
# same-named directory and vouching through a nested-file anchor would let a
# row certify an owner whose entrypoint was effectively deleted — existence at
# a round head must mean a regular blob, and everything else falls through to
# the deletion fail-closed path.
new_case case-round-scope-skillmd-directory-masquerade
git -C "$REPO" rm -q skills/platform-observability/SKILL.md
mkdir -p "$REPO/skills/platform-observability/SKILL.md"
printf -- '- MUST enforce Fixture masquerade rule.\n' > "$REPO/skills/platform-observability/SKILL.md/rules.md"
printf '| Fixture masquerade row | `downstream-executor` | behavioral-evidence: RED-baseline; observed-failure: yes; firing-path: file:skills/platform-observability/SKILL.md/rules.md#Fixture masquerade rule | `updated` | `platform-observability/SKILL.md` masquerade |\n' >> "$REGISTER"
commit_case "replace the entrypoint with a same-named directory and vouch via a nested anchor"
run_gate
assert_rc "$rc" 1 "a directory masquerading as SKILL.md must not read as a present entrypoint"
assert_contains "platform-observability/SKILL.md" "$out" "the masqueraded owner must be named"

assert_rc "$full_check_runs" 1 "fixture suite must retain exactly one full checker wiring case"
assert_rc "$gate_runs" 80 "all remaining impact-chain fixtures must run the standalone gate"

echo "test_check_ccl_impact_chain_refscripts: ok"
