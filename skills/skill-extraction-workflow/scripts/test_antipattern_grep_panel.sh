#!/usr/bin/env bash
# Structural completeness check for the recurring-anti-patterns grep panel.
#
# Invariant pinned (074): every `## Anti-pattern N — ...` section in
# references/recurring-anti-patterns-checklist.md carries a `**Grep**` line —
# the runnable-or-manual detection recipe the panel's "How to use" contract
# promises per entry. A new anti-pattern landed without its Grep recipe is the
# drift this catches; the panel itself stays manual-by-design (its own
# "Promoting a symptom to a mechanical gate" growth rule), so this test does
# NOT execute or compile the grep patterns. Pattern-compilation validation was
# considered and discarded: the recipes mix GNU-BRE commands with prose
# instructions by design, so a compile check would false-red on platform
# regex-dialect differences without protecting a real contract.
#
# Self-proof (mutant must-hit): a fixture copy with one Grep line removed must
# turn this check red for exactly that section; a fixture with an extra
# non-anti-pattern section stays green (benign neighbor).
set -u

script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)
checklist="$script_dir/../references/recurring-anti-patterns-checklist.md"
fail=0

check_panel() { # check_panel <file>; prints missing sections, returns 1 if any
  awk '
    /^## Anti-pattern / {
      if (in_section && !seen_grep) { print "missing_grep_line: " section; bad = 1 }
      in_section = 1; seen_grep = 0; section = $0; count += 1; next
    }
    /^## / {
      if (in_section && !seen_grep) { print "missing_grep_line: " section; bad = 1 }
      in_section = 0; next
    }
    /^\*\*Grep\*\*/ { if (in_section) seen_grep = 1 }
    END {
      if (in_section && !seen_grep) { print "missing_grep_line: " section; bad = 1 }
      if (count == 0) { print "no_anti_pattern_sections_found"; bad = 1 }
      exit bad
    }
  ' "$1"
}

if [[ ! -f "$checklist" ]]; then
  echo "test_antipattern_grep_panel: FAIL (checklist missing: $checklist)"
  exit 1
fi

# Real-panel leg
if ! out=$(check_panel "$checklist"); then
  echo "$out"
  echo "test_antipattern_grep_panel: FAIL (panel section without a Grep recipe)"
  exit 1
fi
echo "ok panel ($(grep -c '^## Anti-pattern ' "$checklist") sections, each with a Grep recipe)"

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

# Mutant must-hit: strip the Grep line from Anti-pattern 27 -> must red on it
awk '/^## Anti-pattern 27 /{inap=1} inap && /^\*\*Grep\*\*/{inap=0; next} {print}' \
  "$checklist" > "$tmp/mutant.md"
if out=$(check_panel "$tmp/mutant.md"); then
  echo "test_antipattern_grep_panel: FAIL (mutant with stripped Grep line passed)"
  exit 1
fi
if [[ "$out" != *"Anti-pattern 27"* ]]; then
  echo "test_antipattern_grep_panel: FAIL (mutant red but wrong section: $out)"
  exit 1
fi
echo "ok mutant (stripped Grep line detected on the right section)"

# Benign neighbor: an extra non-anti-pattern section must stay green
{ cat "$checklist"; printf '\n## A closing note\n\nProse only.\n'; } > "$tmp/benign.md"
if ! check_panel "$tmp/benign.md" >/dev/null; then
  echo "test_antipattern_grep_panel: FAIL (benign extra section turned the check red)"
  exit 1
fi
echo "ok benign (non-anti-pattern section ignored)"

echo "test_antipattern_grep_panel: ok"
