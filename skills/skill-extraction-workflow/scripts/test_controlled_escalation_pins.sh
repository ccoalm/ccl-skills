#!/usr/bin/env bash
# Self-contained RED-baseline for the controlled-escalation pin family (family 8
# in test_ai_coding_implementation_gates.sh). Review rounds ua4/ua5 (spec 031)
# found that prose claims of mutation evidence are unverifiable from a bounded
# review packet; this test makes the walk reproducible in CI and visible in the
# diff: for EVERY family-8 pin, an applied deletion mutation in a throwaway copy
# must red the fixture on that pin's own assertion (differential attribution —
# the fixture exits at first failure, so every earlier assertion passed under
# the mutant), with green unmutated controls before and after and a
# tree-isolation probe proving the harness read the mutated copy, not the live
# tree. The pin list is parsed from the fixture itself so a new pin cannot be
# added without automatically entering this walk.
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
repo_root="$(cd "$script_dir/../../.." && pwd -P)"
fixture_rel="skills/skill-extraction-workflow/scripts/test_ai_coding_implementation_gates.sh"
ref_rel="skills/skill-extraction-workflow/references/source-to-skill-extraction.md"

fail() { printf 'FAIL: %s\n' "$1" >&2; exit 1; }

tmp_root="$(mktemp -d "${TMPDIR:-/tmp}/controlled-escalation-pins.XXXXXX")"
trap 'rm -rf "$tmp_root"' EXIT
# The fixture asserts only on files under skills/, and derives its repo root
# from its own location three levels up — copying skills/ preserves both.
cp -R "$repo_root/skills" "$tmp_root/skills"
copy_fixture="$tmp_root/$fixture_rel"
copy_ref="$tmp_root/$ref_rel"
[[ -f "$copy_fixture" && -f "$copy_ref" ]] || fail "copy is missing the fixture or the reference"

# Parse family-8 pins out of the fixture: each call is
#   assert_in_section "$EXTRACTION_METHOD_REF" "$BLOCKED_VERIFICATION_SECTION" <quoted phrase> \
#     "<label>"
# The phrase may be single- or double-quoted (one pin contains an apostrophe).
pins_file="$tmp_root/pins.tsv"
python3 - "$repo_root/$fixture_rel" "$pins_file" <<'PY'
import re, sys
src, out = sys.argv[1], sys.argv[2]
text = open(src).read()
pattern = re.compile(
    r'assert_in_section "\$EXTRACTION_METHOD_REF" "\$BLOCKED_VERIFICATION_SECTION" '
    r"(?:'([^']+)'|\"([^\"]+)\") \\\n\s+\"([^\"]+)\"",
)
rows = []
for m in pattern.finditer(text):
    phrase = m.group(1) or m.group(2)
    rows.append((phrase, m.group(3)))
if len(rows) < 14:
    sys.exit(f"parsed only {len(rows)} family-8 pins; parser or fixture drifted")
with open(out, "w") as f:
    for phrase, label in rows:
        f.write(f"{phrase}\t{label}\n")
print(len(rows))
PY
pin_count="$(wc -l < "$pins_file" | tr -d ' ')"
# Parser-completeness check (round ua21 P2): the regex must account for EVERY
# family-8 assertion in the fixture — a call whose syntax the regex does not
# recognize would silently drop out of the walk. The raw call count is the
# oracle the parse must match.
raw_count="$(grep -c 'assert_in_section "\$EXTRACTION_METHOD_REF" "\$BLOCKED_VERIFICATION_SECTION"' "$repo_root/$fixture_rel")"
[[ "$pin_count" == "$raw_count" ]] || fail "parser dropped family-8 assertions: parsed $pin_count of $raw_count calls"

run_copy() { bash "$copy_fixture" 2>&1; }

# Control: the unmutated copy is green, proving the harness reads the copy.
control_out="$(run_copy)" || fail "pre-control not green: $control_out"

pristine="$tmp_root/ref.pristine"
cp "$copy_ref" "$pristine"

while IFS=$'\t' read -r phrase label; do
  count="$(python3 - "$pristine" "$phrase" <<'PY'
import sys
print(open(sys.argv[1]).read().count(sys.argv[2]))
PY
)"
  [[ "$count" == "1" ]] || fail "pin phrase not unique in reference ($count hits): $phrase"
  python3 - "$pristine" "$copy_ref" "$phrase" <<'PY'
import sys
src, dst, phrase = sys.argv[1], sys.argv[2], sys.argv[3]
open(dst, "w").write(open(src).read().replace(phrase, "", 1))
PY
  if out="$(run_copy)"; then
    fail "mutant stayed green (deleted: $phrase)"
  fi
  last="$(printf '%s\n' "$out" | tail -1)"
  case "$last" in
    *"$label"*) : ;;
    *) fail "mutant red on the wrong assertion — expected [$label], got: $last" ;;
  esac
  cp "$pristine" "$copy_ref"
done < "$pins_file"

# Relocation probe (round ua8 P2): a deletion mutant cannot distinguish a
# section-bound helper from a whole-file grep. Move the lead phrase OUT of the
# Blocked Verification section to a decoy heading at the end of the file: a
# whole-file search would stay green, a section-bound one must red on the
# owning assertion.
python3 - "$pristine" "$copy_ref" <<'PY'
import sys
src, dst = sys.argv[1], sys.argv[2]
phrase = "Sandbox-denial triage precedes any escalation"
text = open(src).read()
assert text.count(phrase) == 1
open(dst, "w").write(text.replace(phrase, "", 1) + "\n## Relocation decoy\n\n" + phrase + "\n")
PY
if out="$(run_copy)"; then
  fail "relocation probe: section-bound assertion stayed green with the phrase outside its section"
fi
case "$(printf '%s\n' "$out" | tail -1)" in
  *"controlled escalation (invariant: triage before escalation"*) : ;;
  *) fail "relocation probe: red on the wrong assertion: $(printf '%s\n' "$out" | tail -1)" ;;
esac
cp "$pristine" "$copy_ref"

# Reachability probe (round ua15 P2): family 8 also carries an
# assert_same_bullet pin routing the entrypoint to the owning section; that pin
# is not an assert_in_section call, so it gets its own applied mutation here —
# strip the section anchor from the entrypoint bullet and require the fixture
# to red on the reachability assertion.
copy_skill="$tmp_root/skills/skill-extraction-workflow/SKILL.md"
skill_pristine="$tmp_root/skill.pristine"
cp "$copy_skill" "$skill_pristine"
python3 - "$skill_pristine" "$copy_skill" <<'PY'
import sys
src, dst = sys.argv[1], sys.argv[2]
anchor = "references/source-to-skill-extraction.md#blocked-verification-and-source-read-remediation"
text = open(src).read()
if anchor not in text:
    sys.exit("entrypoint anchor not found; reachability probe cannot run")
open(dst, "w").write(text.replace(anchor, "references/source-to-skill-extraction.md", 1))
PY
if out="$(run_copy)"; then
  fail "reachability probe: fixture stayed green with the entrypoint route removed"
fi
case "$(printf '%s\n' "$out" | tail -1)" in
  *"reachability: entrypoint routes to the Blocked Verification section"*) : ;;
  *) fail "reachability probe: red on the wrong assertion: $(printf '%s\n' "$out" | tail -1)" ;;
esac
cp "$skill_pristine" "$copy_skill"

# Post-control green, and tree isolation: a mutated copy reds while the live
# tree's own fixture stays green.
run_copy >/dev/null || fail "post-control not green"
python3 - "$pristine" "$copy_ref" <<'PY'
import sys
src, dst = sys.argv[1], sys.argv[2]
open(dst, "w").write(open(src).read().replace("Sandbox-denial triage precedes any escalation", "", 1))
PY
if run_copy >/dev/null; then fail "tree-isolation probe: mutated copy stayed green"; fi
bash "$repo_root/$fixture_rel" >/dev/null || fail "tree-isolation probe: live tree fixture not green"
cp "$pristine" "$copy_ref"

echo "test_controlled_escalation_pins: ok ($pin_count applied mutations, each red on its owning assertion; controls green)"
