#!/usr/bin/env bash
# Applied-mutation walk for the worktree teardown guard (family 9 in
# test_ai_coding_implementation_gates.sh). The pinned recipes guard an
# irreversible removal, so the walk runs in CI instead of living in a review
# note: in a throwaway copy, every pin row is deleted (an order row is
# reordered) and the fixture must red on that row's own label, with the
# unmutated copy green before and after. The sweep gets decoy surfaces: a
# removal without the scan or without the canonical pointer must red it from
# skills/, docs/ and the root; a compliant decoy, a prune-only mention and a
# vendored dependency file must not. Rows are parsed from the fixture, so a new
# row enters this walk unasked; a teardown assertion written outside the row
# table is not walked, which is why the fixture keeps them all as rows.
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
repo_root="$(cd "$script_dir/../../.." && pwd -P)"
fixture_rel="skills/skill-extraction-workflow/scripts/test_ai_coding_implementation_gates.sh"

fail() { printf 'FAIL: %s\n' "$1" >&2; exit 1; }

tmp_root="$(mktemp -d "${TMPDIR:-/tmp}/teardown-guard-pins.XXXXXX")"
trap 'rm -rf "$tmp_root"' EXIT
# The fixture reads the skills, the always-on layer, the docs and the root
# contract. The copy is not a git checkout, so the fixture derives its root
# from the copied script location; the isolation probe below proves it does.
cp -R "$repo_root/skills" "$tmp_root/skills"
cp -R "$repo_root/agent-context" "$tmp_root/agent-context"
cp -R "$repo_root/docs" "$tmp_root/docs"
cp "$repo_root/AGENTS.md" "$tmp_root/AGENTS.md"
copy_fixture="$tmp_root/$fixture_rel"
[[ -f "$copy_fixture" ]] || fail "copy is missing the fixture"

rows_file="$tmp_root/rows.txt"
python3 - "$repo_root/$fixture_rel" "$rows_file" <<'PY'
import re, sys
text = open(sys.argv[1]).read()
m = re.search(r"TEARDOWN_PINS=\"\$\(cat <<'PINS'\n(.*?)\nPINS\n", text, re.S)
if not m:
    sys.exit("TEARDOWN_PINS block not found in the fixture")
rows = [r for r in m.group(1).split("\n") if r.strip()]
bad = [r for r in rows if r.count("|") != 4]
if bad:
    sys.exit(f"malformed teardown pin row: {bad[0]}")
open(sys.argv[2], "w").write("\n".join(rows) + "\n")
PY
row_count="$(wc -l < "$rows_file" | tr -d ' ')"
(( row_count >= 20 )) || fail "parsed only $row_count teardown pin rows"

run_copy() { bash "$copy_fixture" 2>&1; }

# Mutate one row in place. Exit 3 when the mutation cannot land exactly once,
# so a moved or duplicated phrase fails the walk instead of passing unmutated.
mutate() { # <kind> <file> <scope> <phrase>
  python3 - "$@" <<'PY'
import sys
kind, path, scope, phrase = sys.argv[1:5]
text = open(path).read()
lines = text.split("\n")
def bail(msg):
    sys.stderr.write(msg + "\n")
    sys.exit(3)
if kind == "section":
    if lines.count(scope) != 1:
        bail(f"section heading occurs {lines.count(scope)} times: {scope}")
    start = lines.index(scope)
    end = next((i for i in range(start + 1, len(lines)) if lines[i].startswith("#")), len(lines))
    body = "\n".join(lines[start + 1:end])
    if body.count(phrase) != 1:
        bail(f"phrase occurs {body.count(phrase)} times in its section: {phrase}")
    lines[start + 1:end] = body.replace(phrase, "", 1).split("\n")
elif kind == "line":
    hits = [i for i, line in enumerate(lines) if scope in line]
    if len(hits) != 1:
        bail(f"line anchor occurs on {len(hits)} lines: {scope}")
    if lines[hits[0]].count(phrase) != 1:
        bail(f"phrase occurs {lines[hits[0]].count(phrase)} times on its anchor line: {phrase}")
    lines[hits[0]] = lines[hits[0]].replace(phrase, "", 1)
elif kind == "order":
    first = [i for i, line in enumerate(lines) if scope in line]
    second = [i for i, line in enumerate(lines) if phrase in line]
    if len(first) != 1 or len(second) != 1:
        bail(f"order literals must each sit on one line (got {len(first)} and {len(second)})")
    if first[0] >= second[0]:
        bail("order literals are already reversed in the pristine copy")
    moved = lines.pop(first[0])
    lines.insert(second[0], moved)  # lands right after the second literal's line
else:
    bail(f"unknown pin kind: {kind}")
mutant = "\n".join(lines)
if mutant == text:
    bail("mutation left the file unchanged")
open(path, "w").write(mutant)
PY
}

control_out="$(run_copy)" || fail "pre-control not green: $control_out"

applied=0
pristine="$tmp_root/pristine.tmp"
while IFS='|' read -r kind rel scope phrase label; do
  target="$tmp_root/$rel"
  [[ -f "$target" ]] || fail "row target missing from the copy: $rel"
  cp "$target" "$pristine"
  mutate "$kind" "$target" "$scope" "$phrase" || fail "mutation did not land for row: $label"
  if out="$(run_copy)"; then
    fail "mutant stayed green (row: $label)"
  fi
  last="$(printf '%s\n' "$out" | tail -1)"
  case "$last" in
    "FAIL: teardown guard: $label:"*) : ;;
    *) fail "mutant red on the wrong assertion — expected [teardown guard: $label], got: $last" ;;
  esac
  cp "$pristine" "$target"
  applied=$((applied + 1))
done < "$rows_file"
[[ "$applied" == "$row_count" ]] || fail "walked $applied of $row_count rows"

# Relocation: a deletion mutant cannot tell a scoped check from a whole-file
# grep. Move the first section row's phrase under a decoy heading and the first
# line row's phrase onto a line of its own, both at the end of the file; a
# scoped check reds on its row, a whole-file one would stay green.
relocate() { # <kind>
  local want="$1" kind rel scope phrase label out
  while IFS='|' read -r kind rel scope phrase label; do
    [[ "$kind" == "$want" ]] && break
  done < "$rows_file"
  [[ "$kind" == "$want" ]] || fail "no $want row to relocate"
  cp "$tmp_root/$rel" "$pristine"
  mutate "$kind" "$tmp_root/$rel" "$scope" "$phrase" || fail "relocation: removal did not land for row: $label"
  printf '\n## Relocation decoy\n\n%s\n' "$phrase" >> "$tmp_root/$rel"
  if out="$(run_copy)"; then
    fail "relocation probe: row stayed green with its phrase outside its $kind: $label"
  fi
  case "$(printf '%s\n' "$out" | tail -1)" in
    "FAIL: teardown guard: $label:"*) : ;;
    *) fail "relocation probe red on the wrong assertion for row: $label: $(printf '%s\n' "$out" | tail -1)" ;;
  esac
  cp "$pristine" "$tmp_root/$rel"
}
relocate section
relocate line

# Sweep decoys: each is planted alone, judged, then removed.
recipe_no_scan=$'```bash\ngit worktree remove <path>\n```\n'
recipe_no_pointer=$'```bash\ngit -C <path> status --ignored -s\ngit worktree remove <path>\n```\n'
recipe_compliant=$'See the teardown section in `references/merge-and-teardown.md`.\n\n```bash\ngit -C <path> status --ignored -s\ngit worktree remove <path>\n```\n'
decoy() { # <copy-relative path> <content> <red|green> [expected offender text]
  local rel="$1" content="$2" expect="$3" want="${4:-}" out last
  mkdir -p "$(dirname "$tmp_root/$rel")"
  printf '%s' "$content" > "$tmp_root/$rel"
  if out="$(run_copy)"; then
    [[ "$expect" == green ]] || fail "sweep decoy stayed green: $rel"
  else
    [[ "$expect" == red ]] || fail "precision decoy redded the fixture: $rel: $(printf '%s\n' "$out" | tail -1)"
    last="$(printf '%s\n' "$out" | tail -1)"
    case "$last" in
      "FAIL: teardown guard sweep: "*"$rel: $want"*) : ;;
      *) fail "sweep decoy $rel red for the wrong reason, expected [$rel: $want], got: $last" ;;
    esac
  fi
  rm -f "$tmp_root/$rel"
}
decoy "skills/zz-teardown-decoy/references/recipe.md" "$recipe_no_scan" red "no ignored-output scan"
decoy "docs/zz-teardown-decoy.md" "$recipe_no_pointer" red "no pointer to the canonical teardown"
decoy "zz-teardown-decoy.md" "$recipe_no_scan" red "no ignored-output scan"
decoy "agent-context/zz-teardown-decoy.md" "$recipe_no_pointer" red "no pointer to the canonical teardown"
for root in hooks scripts packages .opencode; do
  decoy "$root/zz-teardown-decoy/README.md" "$recipe_no_scan" red "no ignored-output scan"
  rm -rf "$tmp_root/$root/zz-teardown-decoy"
done
decoy "docs/zz-teardown-compliant.md" "$recipe_compliant" green
decoy "skills/zz-teardown-decoy/references/prune.md" $'```bash\ngit worktree prune\n```\n' green
decoy "skills/zz-teardown-decoy/node_modules/pkg/README.md" "$recipe_no_scan" green
rm -rf "$tmp_root/skills/zz-teardown-decoy"

# Post-control green, then tree isolation: a mutated copy reds while the live
# tree's own fixture stays green, so the walk above read the copy.
run_copy >/dev/null || fail "post-control not green"
first_row="$(head -1 "$rows_file")"
IFS='|' read -r kind rel scope phrase label <<< "$first_row"
cp "$tmp_root/$rel" "$pristine"
mutate "$kind" "$tmp_root/$rel" "$scope" "$phrase" || fail "isolation mutation did not land"
if run_copy >/dev/null; then fail "tree-isolation probe: mutated copy stayed green"; fi
bash "$repo_root/$fixture_rel" >/dev/null 2>&1 || fail "tree-isolation probe: live tree fixture not green"
cp "$pristine" "$tmp_root/$rel"

echo "test_teardown_guard_pins: ok ($applied applied mutations, each red on its own row; 2 relocations red; 8 sweep decoys red, 3 precision decoys green; controls green)"
