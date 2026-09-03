#!/usr/bin/env bash
# Regression for the entrypoint form census. The census is an instrument whose
# only value is that a later round recomputes the same quantity, so the cases
# below pin the definitions the script documents -- what counts as one rule,
# what counts as a prohibition, and what counts as a named baseline failure --
# rather than the figures of any particular entrypoint, which move every round.
set -uo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
CENSUS="$DIR/entrypoint_form_census.py"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/entrypoint-form-census.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT

fails=0
check() { if eval "$2"; then echo "ok   - $1"; else echo "FAIL - $1"; fails=$((fails+1)); fi; }

[ -f "$CENSUS" ] || { echo "FAIL: census missing: $CENSUS" >&2; exit 1; }

field() { printf '%s\n' "$1" | sed -n "s/^$2=//p"; }

# One rule per top-level bullet: the sub-bullet and the continuation line belong
# to the rule above them, and the blank line between them does not close it.
# Getting this wrong inflates every per-rule figure the census reports.
# The prohibitions are placed in the continuation and the sub-bullet, never in
# the bullet's own first line: a rule COUNT cannot detect a parser that drops
# continuations, because a dropped continuation is still not a new top-level
# bullet. The token total is the quantity that moves when the defect is present,
# so that is what the case asserts.
cat >"$WORK/one-rule.md" <<'MD'
# Entry

## Core Rules

### A group

- A rule head with no imperative of its own.

  A continuation line that must hold.

  - A sub-bullet that must also hold.

## After

- A bullet outside Core Rules that must not be counted.
MD
out="$(python3 "$CENSUS" "$WORK/one-rule.md")"; rc=$?
check "sub-bullets and continuations separated by blank lines stay inside one rule" \
  '[ "$rc" = 0 ] && [ "$(field "$out" rules)" = 1 ] && [ "$(field "$out" prohibitive_tokens)" = 2 ]'
# This case owns the section boundary alone: a parser that ran past `## After`
# would report two rules, so the rule count is the quantity that moves here.
check "the census stops at the next same-level heading" \
  '[ "$(field "$out" rules)" = 1 ]'

# A prohibition with no named baseline failure is the diagnostic set; the same
# rule with its failure named must leave that set. The pair is the control: if
# the failure-shape vocabulary stopped matching, the first case would still pass
# and only the second would fail, which is what makes the pair informative.
cat >"$WORK/unanchored.md" <<'MD'
# Entry

## Core Rules

### A group

- A rule that must never be skipped.
MD
out="$(python3 "$CENSUS" "$WORK/unanchored.md")"
check "a prohibition with no named baseline failure is reported unanchored" \
  '[ "$(field "$out" unanchored_prohibition_rules)" = 1 ] && [ "$(field "$out" rules_naming_baseline_failure)" = 0 ]'

cat >"$WORK/anchored.md" <<'MD'
# Entry

## Core Rules

### A group

- A rule that must never be skipped. Failure shape: the step is skipped under time pressure.
MD
out="$(python3 "$CENSUS" "$WORK/anchored.md")"
check "the same prohibition with its baseline failure named leaves the unanchored set" \
  '[ "$(field "$out" unanchored_prohibition_rules)" = 0 ] && [ "$(field "$out" rules_naming_baseline_failure)" = 1 ]'

# A rule with no prohibitive token is not in the diagnostic set whether or not it
# names a failure: the set is prohibitions the form table has something to say
# about, not every rule that omits a rationale.
cat >"$WORK/no-prohibition.md" <<'MD'
# Entry

## Core Rules

### A group

- State the artifact's parts, in order.
MD
out="$(python3 "$CENSUS" "$WORK/no-prohibition.md")"
check "a rule carrying no prohibitive token is outside the diagnostic set" \
  '[ "$(field "$out" prohibitive_tokens)" = 0 ] && [ "$(field "$out" unanchored_prohibition_rules)" = 0 ]'

# The capitalised spellings are emphasis in this package and are counted; a word
# that merely contains one of them is not a token.
cat >"$WORK/tokens.md" <<'MD'
# Entry

## Core Rules

### A group

- This MUST hold and NEVER lapses, and the mustard and nevertheless here are not tokens.
MD
out="$(python3 "$CENSUS" "$WORK/tokens.md")"
check "capitalised emphasis counts as prohibitive and a word merely containing one does not" \
  '[ "$(field "$out" prohibitive_tokens)" = 2 ]'

# The alternation is leftmost and non-overlapping, so a phrase absorbs the words
# inside it. Two independent review lenses read the previous comment as promising
# the opposite, which is exactly the failure this case now pins: the documented
# counting rule and the reported figure have to be the same ruler.
cat >"$WORK/overlap.md" <<'MD'
# Entry

## Core Rules

### A group

- This must not be counted twice, and this cannot be either.
MD
out="$(python3 "$CENSUS" "$WORK/overlap.md")"
check "a phrase absorbs the word inside it: 'must not' is one token, not two" \
  '[ "$(field "$out" prohibitive_tokens)" = 2 ]'

# An existing but empty Core Rules section is an error, not a zero-rule census:
# a section that lost its rules must not report as a clean sheet either.
cat >"$WORK/empty-core.md" <<'MD'
# Entry

## Core Rules

### A group

Prose with no top-level bullet.

## After

- A bullet outside Core Rules.
MD
out="$(python3 "$CENSUS" "$WORK/empty-core.md" 2>&1)"; rc=$?
check "an existing but empty Core Rules section is an error, never a zero-rule census" \
  '[ "$rc" != 0 ] && case "$out" in *entrypoint_form_census_error*) true;; *) false;; esac'

# An entrypoint with no Core Rules section is an error, not a zero: reporting
# zero rules would let a renamed or moved section read as a clean sheet.
cat >"$WORK/no-core.md" <<'MD'
# Entry

## Something Else

- A bullet.
MD
out="$(python3 "$CENSUS" "$WORK/no-core.md" 2>&1)"; rc=$?
check "a file with no Core Rules heading is an error, never an empty census" \
  '[ "$rc" != 0 ] && case "$out" in *entrypoint_form_census_error*) true;; *) false;; esac'

# The shipped entrypoint must parse, or the instrument silently stops measuring
# the only file it exists for.
out="$(python3 "$CENSUS" "$DIR/../SKILL.md")"; rc=$?
check "the shipped entrypoint parses and reports a non-zero rule count" \
  '[ "$rc" = 0 ] && [ "$(field "$out" rules)" -gt 0 ] && case "$out" in *entrypoint_form_census_ok*) true;; *) false;; esac'

if [ "$fails" -ne 0 ]; then
  echo "test_entrypoint_form_census: $fails failing case(s)"
  exit 1
fi
echo "test_entrypoint_form_census: ok"
