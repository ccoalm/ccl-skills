#!/usr/bin/env bash
# Regression tests for register-firing-path-resolution.rb.
#
# The gap this gate closes: impact-chain-gate.rb is diff-scoped, so a register
# row's firing path is machine-checked exactly once — at the commit that added
# the row. Any later edit that MOVES or REWORDS the anchored rule voids that
# row's firing evidence while every gate stays green. Observed in an entrypoint-
# slimming change that relocated an anchored rule out of a SKILL.md and reworded
# it in the same commit.
#
# Each assertion below is mutation-verified: the fixture is built GREEN first,
# then exactly one property is broken and the gate must go RED naming that
# locator. A test that only ever asserts "clean stays clean" would pass with the
# whole detection deleted, so every RED case here has a paired GREEN control.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd -P)"
GATE="$SCRIPT_DIR/register-firing-path-resolution.rb"
[ -f "$GATE" ] || { echo "FAIL: gate not found: $GATE" >&2; exit 1; }

TMP="$(mktemp -d "${TMPDIR:-/tmp}/regfiring.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

passed=0
fail() { echo "FAIL: $*" >&2; exit 1; }
pass() { passed=$((passed + 1)); echo "PASS: $*"; }
assert_rc() { [ "$1" = "$2" ] || fail "expected rc=$2 got rc=$1 ($3)"; }
assert_contains() { case "$2" in *"$1"*) : ;; *) fail "expected output to contain '$1' ($3)";; esac; }
assert_not_contains() { case "$2" in *"$1"*) fail "expected output NOT to contain '$1' ($3)";; *) : ;; esac; }

REGDIR="skills/skill-extraction-workflow/references"

# Builds a fixture repo root whose register carries exactly the firing-path
# declarations passed as arguments (one per line, already formatted as a row).
new_fixture() {
  FIX="$TMP/$1"; shift
  rm -rf "$FIX"
  mkdir -p "$FIX/$REGDIR" "$FIX/skills/demo-skill/scripts"
  cat > "$FIX/skills/demo-skill/SKILL.md" <<'MD'
# Demo Skill

## Mechanical demo gate

1. Never bypass the demo isolation boundary when dispatching work.
MD
  printf '#!/usr/bin/env bash\nexit 0\n' > "$FIX/skills/demo-skill/scripts/demo.sh"
  chmod +x "$FIX/skills/demo-skill/scripts/demo.sh"
  { echo "| head | head | head |"; for row in "$@"; do echo "$row"; done; } \
    > "$FIX/$REGDIR/source-register.md"
}

# These fixtures build SYNTHETIC ledgers, which by construction contain none of
# the real repository's waived rows. The gate binds each waiver to its citing
# row's digest and fails closed when a recorded row is missing, so the fixtures
# inject their own (empty) digest table: no waiver is digest-bound here, which is
# the truth for a synthetic ledger. Production sets no such variable and enforces
# the built-in table unconditionally; the real-ledger digest and missing-row
# cases live in test_register_firing_path_wiring.sh, which drives a clone of the
# actual repository.
EMPTY_DIGEST_TABLE="$TMP/empty-exempt-digests.json"
printf '{}\n' > "$EMPTY_DIGEST_TABLE"

run_gate() {
  set +e
  out="$(REGISTER_FIRING_PATH_EXEMPT_DIGESTS="$EMPTY_DIGEST_TABLE" ruby "$GATE" "$1" 2>&1)"
  rc=$?
  set -e
}

LITERAL='| p | c | prose; behavioral-evidence: RED-baseline; observed-failure: yes; firing-path: file:skills/demo-skill/SKILL.md#Never bypass the demo isolation boundary | `updated` | demo |'
SLUG='| p | c | prose; firing-path: file:skills/demo-skill/SKILL.md#mechanical-demo-gate | `updated` | demo |'
CMD='| p | c | prose; firing-path: command:skills/demo-skill/scripts/demo.sh | `updated` | demo |'
MULTI='| p | c | prose; firing-path: command:skills/demo-skill/scripts/demo.sh,command:skills/demo-skill/scripts/second.sh | `updated` | demo |'

# ── 1. GREEN control: literal anchor present ─────────────────────────────────
new_fixture green "$LITERAL"
run_gate "$FIX"
assert_rc "$rc" 0 "literal anchor present must pass"
assert_contains "register_firing_path_resolution_ok" "$out" "green control"
pass "literal anchor that is present resolves"

# ── 2. RED: the observed failure — anchored rule reworded in place ───────────
new_fixture reworded "$LITERAL"
# The exact !483 shape: the rule survives but its wording changed.
sed -i.bak 's/Never bypass the demo isolation boundary/Never bypass the demo isolation perimeter/' \
  "$FIX/skills/demo-skill/SKILL.md"
run_gate "$FIX"
assert_rc "$rc" 1 "a reworded anchored rule must be caught"
assert_contains "anchor text absent from target" "$out" "reworded anchor"
assert_contains "Never bypass the demo isolation boundary" "$out" "names the dead locator"
pass "reworded anchored rule turns the gate RED"

# ── 3. RED: the anchored rule MOVED to another file ──────────────────────────
new_fixture moved "$LITERAL"
mkdir -p "$FIX/skills/demo-skill/references"
grep -v 'Never bypass' "$FIX/skills/demo-skill/SKILL.md" > "$FIX/skills/demo-skill/SKILL.md.new"
mv "$FIX/skills/demo-skill/SKILL.md.new" "$FIX/skills/demo-skill/SKILL.md"
echo "1. Never bypass the demo isolation boundary when dispatching work." \
  > "$FIX/skills/demo-skill/references/moved.md"
run_gate "$FIX"
assert_rc "$rc" 1 "relocating the anchored rule must be caught"
assert_contains "anchor text absent from target" "$out" "moved anchor"
pass "anchored rule moved to a reference turns the gate RED"

# ── 4. GREEN control: heading-slug anchor naming a real heading ──────────────
new_fixture slug_ok "$SLUG"
run_gate "$FIX"
assert_rc "$rc" 0 "a slug naming a real heading must not false-red"
pass "heading-slug anchor resolves against a real heading"

# ── 5. RED: heading-slug anchor whose heading was renamed ────────────────────
new_fixture slug_gone "$SLUG"
sed -i.bak 's/## Mechanical demo gate/## Mechanical demo checkpoint/' \
  "$FIX/skills/demo-skill/SKILL.md"
run_gate "$FIX"
assert_rc "$rc" 1 "a slug whose heading was renamed must be caught"
assert_contains "mechanical-demo-gate" "$out" "names the dead slug"
pass "heading-slug anchor whose heading vanished turns the gate RED"

# ── 6. RED: command locator whose executable was deleted ─────────────────────
new_fixture cmd_gone "$CMD"
rm "$FIX/skills/demo-skill/scripts/demo.sh"
run_gate "$FIX"
assert_rc "$rc" 1 "a deleted owner executable must be caught"
assert_contains "executable not found" "$out" "deleted executable"
pass "deleted owner executable turns the gate RED"

# ── 7. RED: command locator that lost its executable bit ─────────────────────
new_fixture cmd_noexec "$CMD"
chmod -x "$FIX/skills/demo-skill/scripts/demo.sh"
run_gate "$FIX"
assert_rc "$rc" 1 "a non-executable owner script must be caught"
assert_contains "not executable" "$out" "chmod -x"
pass "owner script that lost +x turns the gate RED"

# ── 8. RED: file locator whose target file is gone ───────────────────────────
new_fixture file_gone "$LITERAL"
rm "$FIX/skills/demo-skill/SKILL.md"
run_gate "$FIX"
assert_rc "$rc" 1 "a deleted target file must be caught"
assert_contains "file not found" "$out" "deleted target file"
pass "deleted target file turns the gate RED"

# ── 9. Comma-list: the SECOND locator is resolved, not just the first ────────
# Without comma splitting the whole value parses as one bogus locator and the
# second path is never checked — the silent-invalid shape this repo has hit
# before. Paired control: make the second valid and the gate must go green.
new_fixture multi_bad "$MULTI"
run_gate "$FIX"
assert_rc "$rc" 1 "a broken SECOND locator in a comma list must be caught"
assert_contains "second.sh" "$out" "names the second locator"
pass "second locator in a comma list is resolved independently"

new_fixture multi_ok "$MULTI"
printf '#!/usr/bin/env bash\nexit 0\n' > "$FIX/skills/demo-skill/scripts/second.sh"
chmod +x "$FIX/skills/demo-skill/scripts/second.sh"
run_gate "$FIX"
assert_rc "$rc" 0 "a comma list whose members all resolve must pass"
assert_not_contains "second.sh" "$out" "comma-list green control"
pass "comma list with all members present resolves green"

# ── 10. Whole-ledger scope: a HISTORICAL row is checked, not just a new one ──
# This is the gate's entire reason to exist. A broken row sitting behind many
# healthy rows must still be found.
# The broken row is LAST so the assertion cannot be satisfied by an
# implementation that only resolves the first declaration and counts the rest.
new_fixture historical "$CMD" "$SLUG" "$LITERAL"
sed -i.bak 's/Never bypass the demo isolation boundary/Never bypass the demo isolation perimeter/' \
  "$FIX/skills/demo-skill/SKILL.md"
run_gate "$FIX"
assert_rc "$rc" 1 "a broken row among healthy rows must be caught"
assert_contains "source-register.md:4" "$out" "reports the LAST row's line, not the first"
pass "whole-ledger scan catches a broken historical row among healthy ones"

# ── 11. The reported locator COUNT must be accurate, not merely present ──────
# Asserting "(0 locators resolved)" on an empty fixture is hollow: deleting the
# increment leaves it green. Pin an exact non-zero count so the counter itself
# has a killing mutation.
new_fixture counted "$LITERAL" "$CMD" "$SLUG"
run_gate "$FIX"
assert_rc "$rc" 0 "three healthy locators must pass"
assert_contains "(3 locators resolved)" "$out" "count must be accurate, not just printed"
pass "reported locator count is exact (kills a dropped counter increment)"

# ── 12. A file locator with no #anchor is rejected ───────────────────────────
# Otherwise the row is satisfied by mere file existence, and the anchored rule
# could be deleted outright without the gate noticing.
NOANCHOR='| p | c | prose; firing-path: file:skills/demo-skill/SKILL.md | `updated` | demo |'
new_fixture no_anchor "$NOANCHOR"
run_gate "$FIX"
assert_rc "$rc" 1 "an anchorless file locator must be rejected"
assert_contains "carries no #anchor" "$out" "anchorless locator"
pass "file locator with no anchor is rejected (file existence is not evidence)"

# ── 13. Containment: a locator may not escape the repository ─────────────────
for esc in '../outside.md#Never bypass isolation' '/etc/hosts#localhost'; do
  new_fixture "escape" "| p | c | prose; firing-path: file:$esc | \`updated\` | demo |"
  printf '1. Never bypass isolation.\n' > "$TMP/outside.md"
  run_gate "$FIX"
  assert_rc "$rc" 1 "locator '$esc' must not resolve outside the repo"
  assert_contains "escapes the repository" "$out" "containment for $esc"
done
pass "traversal and absolute-path locators are refused"

new_fixture symlink_escape "$LITERAL"
printf '1. Never bypass the demo isolation boundary when dispatching work.\n' > "$TMP/outside_sl.md"
rm "$FIX/skills/demo-skill/SKILL.md"
ln -s "$TMP/outside_sl.md" "$FIX/skills/demo-skill/SKILL.md"
run_gate "$FIX"
assert_rc "$rc" 1 "a symlink pointing outside the repo must not satisfy an anchor"
assert_contains "escapes the repository" "$out" "symlinked target"
pass "symlinked target outside the repo does not satisfy an anchor"

# ── 14. A declaration that parses to zero locators is malformed, not clean ───
MALFORMED='| p | c | prose; firing-path: see the owning script | `updated` | demo |'
new_fixture malformed "$MALFORMED"
run_gate "$FIX"
assert_rc "$rc" 1 "an unparseable firing-path declaration must not pass silently"
assert_contains "register_firing_path_malformed" "$out" "malformed declaration"
pass "declaration parsing to zero locators is reported, not silently skipped"

# ── 15. GREEN controls for the two shapes that must NOT count as declarations ─
# (a) an inline-code mention of the key in prose — this ledger's own methodology
# rows discuss `firing-path:` in running text; demanding a locator would false-red.
INLINE='| p | c | 本行讨论 `firing-path:` 这个键本身，不是声明 | `updated` | demo |'
new_fixture inline_mention "$INLINE" "$CMD"
run_gate "$FIX"
assert_rc "$rc" 0 "an inline-code mention of the key is prose, not a declaration"
assert_contains "(1 locators resolved)" "$out" "only the real declaration counts"
pass "inline-code mention of firing-path: is not treated as a declaration"

# (b) a fenced documentation example naming a placeholder path
new_fixture fenced "$CMD"
{ echo '```'; echo '| x | y | firing-path: file:skills/PLACEHOLDER/SKILL.md#example anchor | z |'; echo '```'; } \
  >> "$FIX/$REGDIR/source-register.md"
run_gate "$FIX"
assert_rc "$rc" 0 "a fenced example must not be resolved as a live locator"
pass "fenced documentation example is not resolved as a live locator"

# ── 16. Duplicate-heading slugs follow GitHub numbering exactly ──────────────
new_fixture slug_dup_absent '| p | c | prose; firing-path: file:skills/demo-skill/SKILL.md#mechanical-demo-gate-99 | `updated` | demo |'
run_gate "$FIX"
assert_rc "$rc" 1 "a -N suffix with no such duplicate heading must be rejected"
pass "slug suffix naming a nonexistent duplicate heading is rejected"

# ── 12. Commas INSIDE a literal anchor must not truncate it ─────────────────
# Anchors are natural-language rule text; three locators in the real ledger
# already contain a comma. A naive split-on-every-comma validates only the
# fragment before it, so deleting the rest of the sentence would still pass.
COMMA='| p | c | prose; firing-path: file:skills/demo-skill/SKILL.md#Never bypass the demo isolation boundary, especially when dispatching | `updated` | demo |'
new_fixture comma_anchor_ok "$COMMA"
sed -i.bak 's/boundary when dispatching work\./boundary, especially when dispatching work./' \
  "$FIX/skills/demo-skill/SKILL.md"
run_gate "$FIX"
assert_rc "$rc" 0 "a comma-bearing anchor that is fully present must pass"
pass "comma inside a literal anchor does not split the locator"

new_fixture comma_anchor_truncated "$COMMA"
# Keep the pre-comma fragment, drop the tail: a naive splitter reports GREEN here.
sed -i.bak 's/boundary when dispatching work\./boundary, but the tail is gone./' \
  "$FIX/skills/demo-skill/SKILL.md"
run_gate "$FIX"
assert_rc "$rc" 1 "deleting the post-comma tail of an anchor must be caught"
assert_contains "especially when dispatching" "$out" "names the full anchor, not the fragment"
pass "post-comma tail deletion turns the gate RED (no fragment-only validation)"

# ── 13. A directory is not an executable command locator ────────────────────
DIRCMD='| p | c | prose; firing-path: command:skills/demo-skill/scripts | `updated` | demo |'
new_fixture dir_cmd "$DIRCMD"
run_gate "$FIX"
assert_rc "$rc" 1 "a directory must not satisfy a command locator"
assert_contains "executable not found" "$out" "directory rejected"
pass "searchable directory does not pass as a command locator"

# ── 14. Duplicate-heading slug suffix must not false-red ────────────────────
DUP='| p | c | prose; firing-path: file:skills/demo-skill/SKILL.md#mechanical-demo-gate-1 | `updated` | demo |'
new_fixture slug_suffix "$DUP"
printf '\n## Mechanical demo gate\n\n1. A second same-named section.\n' >> "$FIX/skills/demo-skill/SKILL.md"
run_gate "$FIX"
assert_rc "$rc" 0 "a GitHub duplicate-heading suffix must resolve, not false-red"
pass "slug with a -N duplicate suffix resolves to the base heading"

# ── 17. An anchor surviving only inside a FENCED example is not a live carrier ─
# The gate's contract is that anchors point into living prose. A rule deleted
# from the operative text but still shown in a code sample must not satisfy it.
new_fixture fenced_carrier "$LITERAL"
cat > "$FIX/skills/demo-skill/SKILL.md" <<'MD'
# Demo Skill

The guard was removed; only this illustration remains:

```markdown
1. Never bypass the demo isolation boundary when dispatching work.
```
MD
run_gate "$FIX"
assert_rc "$rc" 1 "an anchor surviving only inside a fence is not a living carrier"
pass "anchor present only inside a fenced example does not resolve"

new_fixture fenced_heading "$SLUG"
cat > "$FIX/skills/demo-skill/SKILL.md" <<'MD'
# Demo Skill

```markdown
## Mechanical demo gate
```
MD
run_gate "$FIX"
assert_rc "$rc" 1 "a heading inside a fence is not a real heading"
pass "heading inside a fenced example does not satisfy a slug anchor"

# ── 18. Non-ASCII (CJK) headings slug correctly ──────────────────────────────
# Most headings in this repository are Chinese; collapsing them to an empty slug
# would false-red an unrewritable row.
# The heading must be MIXED script: a pure-CJK anchor is also a literal
# substring of the heading line, so it would resolve without ever reaching the
# slug path and the assertion would not discriminate. `机械门禁 gate` slugs to
# `机械门禁-gate`, which appears nowhere literally.
new_fixture cjk '| p | c | prose; firing-path: file:skills/demo-skill/SKILL.md#机械门禁-gate | `updated` | demo |'
printf '# Demo Skill\n\n## 机械门禁 gate\n\n1. 规则正文。\n' > "$FIX/skills/demo-skill/SKILL.md"
run_gate "$FIX"
assert_rc "$rc" 0 "a non-ASCII heading slug must resolve, not false-red"
pass "non-ASCII heading slug resolves (mixed-script, not literally present)"

# ── 19. Variable-length fences: a shorter inner run must not close a longer one ─
# A naive boolean toggle would close on the inner ``` , re-open on the real
# closing ```` , and then silently skip the live row that follows.
new_fixture longfence "$LITERAL"
python3 - "$FIX/$REGDIR/source-register.md" <<'PY'
import sys
p = sys.argv[1]
rows = open(p, encoding="utf-8").read().rstrip("\n").split("\n")
head, live = rows[0], rows[-1]
open(p, "w", encoding="utf-8").write(
    head + "\n````\n```\n````\n" + live + "\n")
PY
sed -i.bak 's/Never bypass the demo isolation boundary/Never bypass the demo isolation perimeter/' \
  "$FIX/skills/demo-skill/SKILL.md"
run_gate "$FIX"
assert_rc "$rc" 1 "a live row after a nested-fence block must still be checked"
pass "shorter inner fence run does not close a longer fence (live rows stay visible)"

# ── 25. A register that declares nothing resolves clean at zero ─────────────
# Both shapes that carry no live declaration — no marker at all, and a fenced
# illustration of one — must stay clean. This is the pair that two successive
# zero-locator "self-checks" each got wrong in the opposite direction, so it is
# pinned: a run adjudicating nothing is not evidence of a broken parser, and the
# gate must not grade its own eyesight at runtime.
new_fixture zero_declarations_plain
{
  echo "| head | head | head |"
  echo '| p | c | prose with no declaration at all | `updated` | demo |'
} > "$FIX/$REGDIR/source-register.md"
run_gate "$FIX"
assert_rc "$rc" 0 "a register with no firing-path declarations at all must stay clean"
assert_contains "register_firing_path_resolution_ok (0 locators resolved)" "$out" "empty register terminal line"
pass "declaration-free register resolves clean at zero locators"

new_fixture zero_declarations_fenced_example
{
  echo "| head | head | head |"
  echo '```'
  echo '| p | c | prose; firing-path: file:skills/demo-skill/SKILL.md#Never bypass the demo isolation boundary | `updated` | demo |'
  echo '```'
} > "$FIX/$REGDIR/source-register.md"
run_gate "$FIX"
assert_rc "$rc" 0 "a fenced example row is an illustration, not a live declaration"
pass "fenced declaration-looking example does not red a register with no live declarations"

[ "$passed" -eq 29 ] || fail "expected 29 assertions, saw $passed (a case was skipped or misplaced)"
echo "register_firing_path_resolution_tests_ok ($passed assertions)"
