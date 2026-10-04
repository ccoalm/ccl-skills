#!/usr/bin/env bash
# Applied-mutation walk for the worktree teardown guard (family 9 in
# test_ai_coding_implementation_gates.sh). The pinned recipes guard an
# irreversible removal, so the walk runs in CI instead of living in a review
# note: in a throwaway copy, every pin row is deleted (an order row is
# reordered inside its section) and the fixture must red on that row's own
# label, with the unmutated copy green before and after. Relocation probes move
# a scoped phrase out of its section or line. The sweep gets decoy surfaces in
# every scanned root: a removal without the scan, without its exit-0
# requirement, or with a pointer that does not name the canonical reference
# must red it, including from a new top-level directory; a compliant decoy, a
# package-relative pointer inside the canonical package, a prune-only mention,
# ignored or local-only paths, round records, evaluation inputs and a register
# row must not; an unreadable file must red it too. The copy is a git
# repository, so the sweep enumerates it the way it does in CI; one leg removes
# the repository to exercise the plain-copy fallback, including an unreadable
# directory.
# Rows are parsed from the fixture, so a new row enters this walk unasked; a
# teardown assertion written outside the row table is not walked, which is why
# the fixture keeps them all as rows.
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
repo_root="$(cd "$script_dir/../../.." && pwd -P)"
fixture_rel="skills/skill-extraction-workflow/scripts/test_ai_coding_implementation_gates.sh"

fail() { printf 'FAIL: %s\n' "$1" >&2; exit 1; }

tmp_root="$(mktemp -d "${TMPDIR:-/tmp}/teardown-guard-pins.XXXXXX")"
# The unreadable probes chmod parts of the copy to 000; restore access first so
# cleanup cannot leave them behind after a failure.
trap 'chmod -R u+rwX "$tmp_root" 2>/dev/null; rm -rf "$tmp_root"' EXIT
# The fixture reads the skills, the always-on layer, the docs and the root
# contract. The copy is not a git checkout, so the fixture derives its root
# from the copied script location; the isolation probe below proves it does.
cp -R "$repo_root/skills" "$tmp_root/skills"
cp -R "$repo_root/agent-context" "$tmp_root/agent-context"
cp -R "$repo_root/docs" "$tmp_root/docs"
cp "$repo_root/AGENTS.md" "$tmp_root/AGENTS.md"
cp "$repo_root/.gitignore" "$tmp_root/.gitignore"
git -C "$tmp_root" init -q
git -C "$tmp_root" add -A
git -C "$tmp_root" -c user.name=walk -c user.email=walk@invalid commit -qm copy
copy_fixture="$tmp_root/$fixture_rel"
[[ -f "$copy_fixture" ]] || fail "copy is missing the fixture"

rows_file="$tmp_root/rows.txt"
python3 - "$repo_root/$fixture_rel" "$rows_file" <<'PY'
import re, sys
text = open(sys.argv[1], encoding="utf-8").read()
m = re.search(r"TEARDOWN_PINS=\"\$\(cat <<'PINS'\n(.*?)\nPINS\n", text, re.S)
if not m:
    sys.exit("TEARDOWN_PINS block not found in the fixture")
rows = [r for r in m.group(1).split("\n") if r.strip()]
bad = [r for r in rows if r.count("|") != 4]
if bad:
    sys.exit(f"malformed teardown pin row: {bad[0]}")
open(sys.argv[2], "w", encoding="utf-8").write("\n".join(rows) + "\n")
PY
row_count="$(wc -l < "$rows_file" | tr -d ' ')"
(( row_count >= 20 )) || fail "parsed only $row_count teardown pin rows"

# Fixture temp files land in the copy, so the trap removes them even after an
# interrupted run.
run_copy() { TMPDIR="$tmp_root" bash "$copy_fixture" 2>&1; }

# Mutate one row in place. Exit 3 when the mutation cannot land exactly once,
# so a moved or duplicated phrase fails the walk instead of passing unmutated.
# Modes: mutate (delete, or reorder an order row) and relocate (move the phrase,
# or an order row's first line, out of its scope to a decoy heading at the end).
mutate() { # <mutate|relocate> <kind> <file> <scope> <phrase>
  python3 - "$@" <<'PY'
import sys
mode, kind, path, scope, phrase = sys.argv[1:6]
text = open(path, encoding="utf-8").read()
lines = text.split("\n")
def bail(msg):
    sys.stderr.write(msg + "\n")
    sys.exit(3)
def section_bounds(heading):
    if lines.count(heading) != 1:
        bail(f"section heading occurs {lines.count(heading)} times: {heading}")
    start = lines.index(heading)
    end = next((i for i in range(start + 1, len(lines)) if lines[i].startswith("#")), len(lines))
    return start, end
moved = phrase
if kind == "section":
    start, end = section_bounds(scope)
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
    if " ⟶ " not in phrase:
        bail("order row must read 'first ⟶ second'")
    first_lit, second_lit = phrase.split(" ⟶ ", 1)
    start, end = section_bounds(scope)
    first = [i for i in range(start + 1, end) if first_lit in lines[i]]
    second = [i for i in range(start + 1, end) if second_lit in lines[i]]
    if len(first) != 1 or len(second) != 1:
        bail(f"order literals must each sit on one line of the section (got {len(first)} and {len(second)})")
    if first[0] >= second[0]:
        bail("order literals are already reversed in the pristine copy")
    moved = lines.pop(first[0])
    if mode == "mutate":
        lines.insert(second[0], moved)  # lands right after the second literal's line
else:
    bail(f"unknown pin kind: {kind}")
if mode == "relocate":
    decoy = ["## Relocation decoy", "", moved, ""]
    if kind == "order":
        # Ahead of the section: a file-wide comparison still sees the scan
        # before the removal there, so only a section-scoped check reds.
        lines = decoy + lines
    else:
        lines += [""] + decoy
mutant = "\n".join(lines)
if mutant == text:
    bail("mutation left the file unchanged")
open(path, "w", encoding="utf-8").write(mutant)
PY
}

control_out="$(run_copy)" || fail "pre-control not green: $control_out"

applied=0
pristine="$tmp_root/pristine.tmp"
while IFS='|' read -r kind rel scope phrase label; do
  target="$tmp_root/$rel"
  [[ -f "$target" ]] || fail "row target missing from the copy: $rel"
  cp "$target" "$pristine"
  mutate mutate "$kind" "$target" "$scope" "$phrase" || fail "mutation did not land for row: $label"
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
# grep. For the first row of each kind, move its phrase under a decoy heading at
# the end of the file, or an order row's first line to a decoy heading ahead of
# the section; a scoped check reds on its row, a whole-file one stays green.
relocations=0
relocate() { # <kind>
  local want="$1" kind rel scope phrase label out
  while IFS='|' read -r kind rel scope phrase label; do
    [[ "$kind" == "$want" ]] && break
  done < "$rows_file"
  [[ "$kind" == "$want" ]] || fail "no $want row to relocate"
  cp "$tmp_root/$rel" "$pristine"
  mutate relocate "$kind" "$tmp_root/$rel" "$scope" "$phrase" || fail "relocation did not land for row: $label"
  if out="$(run_copy)"; then
    fail "relocation probe: row stayed green with its phrase outside its $kind scope: $label"
  fi
  case "$(printf '%s\n' "$out" | tail -1)" in
    "FAIL: teardown guard: $label:"*) : ;;
    *) fail "relocation probe red on the wrong assertion for row: $label: $(printf '%s\n' "$out" | tail -1)" ;;
  esac
  cp "$pristine" "$tmp_root/$rel"
  relocations=$((relocations + 1))
}
relocate section
relocate line
relocate order

# Sweep decoys: each is planted alone, judged, then removed.
canonical='`worktree-isolation/references/merge-and-teardown.md`'
recipe_no_scan=$'```bash\ngit worktree remove <path>\n```\n'
recipe_no_exit="See $canonical."$'\n\n```bash\ngit -C <path> status --ignored -s\ngit worktree remove <path>\n```\n'
recipe_exit_elsewhere="See $canonical."$'\n\n```bash\ngit -C <path> status --ignored -s\ngit worktree remove <path>\n```\n\nThe health check must exit 0 before release.\n'
recipe_no_pointer=$'```bash\ngit -C <path> status --ignored -s   # must exit 0\ngit worktree remove <path>\n```\n'
recipe_basename_pointer=$'See `references/merge-and-teardown.md`.\n\n```bash\ngit -C <path> status --ignored -s   # must exit 0\ngit worktree remove <path>\n```\n'
recipe_compliant="See $canonical."$'\n\n```bash\ngit -C <path> status --ignored -s   # must exit 0\ngit worktree remove <path>\n```\n'
reds=0
greens=0
decoy() { # <copy-relative path> <content> <red|green> [expected offender text]
  local rel="$1" content="$2" expect="$3" want="${4:-}" out last
  mkdir -p "$(dirname "$tmp_root/$rel")"
  printf '%s' "$content" > "$tmp_root/$rel"
  if out="$(run_copy)"; then
    [[ "$expect" == green ]] || fail "sweep decoy stayed green: $rel"
    greens=$((greens + 1))
  else
    [[ "$expect" == red ]] || fail "precision decoy redded the fixture: $rel: $(printf '%s\n' "$out" | tail -1)"
    last="$(printf '%s\n' "$out" | tail -1)"
    case "$last" in
      "FAIL: teardown guard sweep: "*"$rel: $want"*) : ;;
      *) fail "sweep decoy $rel red for the wrong reason, expected [$rel: $want], got: $last" ;;
    esac
    reds=$((reds + 1))
  fi
  rm -f "$tmp_root/$rel"
}
decoy "skills/zz-teardown-decoy/references/recipe.md" "$recipe_no_scan" red "no ignored-output scan"
decoy "docs/zz-teardown-decoy.md" "$recipe_no_pointer" red "no pointer to the canonical teardown"
decoy "docs/zz-no-exit.md" "$recipe_no_exit" red "no exit-0 requirement on the scan line"
decoy "docs/zz-exit-elsewhere.md" "$recipe_exit_elsewhere" red "no exit-0 requirement on the scan line"
decoy "zz-new-root/guide.md" "$recipe_no_scan" red "no ignored-output scan"
rm -rf "$tmp_root/zz-new-root"
decoy "docs/zz-basename-pointer.md" "$recipe_basename_pointer" red "no pointer to the canonical teardown"
decoy "docs/zz-teardown-compliant.md" "$recipe_compliant" green
decoy "skills/worktree-isolation/references/zz-package-relative.md" "$recipe_basename_pointer" green
decoy "skills/zz-teardown-decoy/references/prune.md" $'```bash\ngit worktree prune\n```\n' green
decoy "skills/zz-teardown-decoy/node_modules/pkg/README.md" "$recipe_no_scan" green
decoy ".work/zz-local.md" "$recipe_no_scan" green
decoy "specs/zz-round/plan.md" "$recipe_no_scan" green
decoy "eval/zz-input.md" "$recipe_no_scan" green
rm -rf "$tmp_root/skills/zz-teardown-decoy" "$tmp_root/specs" "$tmp_root/eval"
# The append-only register describes defects, removal commands included, and
# the sweep skips it; a register row naming the command must stay green.
register="$tmp_root/skills/skill-extraction-workflow/references/source-register.md"
cp "$register" "$pristine"
printf '%s\n' '| decoy row | `decoy` | listed only `git worktree remove <path>` | n/a | n/a |' >> "$register"
if ! out="$(run_copy)"; then
  fail "precision decoy in the source register redded the fixture: $(printf '%s\n' "$out" | tail -1)"
fi
cp "$pristine" "$register"
greens=$((greens + 1))

# A read error must fail the sweep rather than skip a file it could not see.
# Permissions do not bind root, so the unreadable probes are skipped there.
as_root=0
[[ "$(id -u)" != 0 ]] || as_root=1
unreadable="permission probes skipped as root"
if (( ! as_root )); then
  locked_file="$tmp_root/docs/zz-unreadable.md"
  printf '%s' "$recipe_no_scan" > "$locked_file"
  chmod 000 "$locked_file"
  if out="$(run_copy)"; then
    fail "an unreadable file left the sweep green"
  fi
  chmod 644 "$locked_file"
  case "$(printf '%s\n' "$out" | tail -1)" in
    "FAIL: teardown guard sweep: could not read docs/zz-unreadable.md"*) : ;;
    *) fail "unreadable file red for the wrong reason: $(printf '%s\n' "$out" | tail -1)" ;;
  esac
  rm -f "$locked_file"
  # A listing failure must fail the sweep too: an unreadable index stops git.
  chmod 000 "$tmp_root/.git/index"
  if out="$(run_copy)"; then
    fail "a failed repository listing left the sweep green"
  fi
  chmod 644 "$tmp_root/.git/index"
  case "$(printf '%s\n' "$out" | tail -1)" in
    "FAIL: teardown guard sweep: could not list the repository's Markdown"*) : ;;
    *) fail "failed listing red for the wrong reason: $(printf '%s\n' "$out" | tail -1)" ;;
  esac
fi
# A classification pass that dies must fail the sweep, not pass it.
mkdir -p "$tmp_root/shim"
printf '#!/bin/sh\nexit 1\n' > "$tmp_root/shim/python3"
chmod +x "$tmp_root/shim/python3"
if out="$(PATH="$tmp_root/shim:$PATH" TMPDIR="$tmp_root" bash "$copy_fixture" 2>&1)"; then
  fail "a failed classification pass left the sweep green"
fi
case "$(printf '%s\n' "$out" | tail -1)" in
  "FAIL: teardown guard sweep: the classification pass failed"*) : ;;
  *) fail "failed classification red for the wrong reason: $(printf '%s\n' "$out" | tail -1)" ;;
esac
rm -rf "$tmp_root/shim"

# Plain-copy fallback: without the repository the sweep lists files itself, so
# it must still reach a new top-level directory, still skip local-only paths,
# and fail on a directory it cannot list.
mkdir -p "$tmp_root/.work"
mv "$tmp_root/.git" "$tmp_root/.work/git-off"
run_copy >/dev/null || fail "plain-copy control not green"
decoy "zz-new-root/guide.md" "$recipe_no_scan" red "no ignored-output scan"
rm -rf "$tmp_root/zz-new-root"
decoy ".work/zz-local.md" "$recipe_no_scan" green
decoy "packages/zz-pkg/dist/README.md" "$recipe_no_scan" green
rm -rf "$tmp_root/packages"
if (( ! as_root )); then
  locked="$tmp_root/hooks/zz-unreadable"
  mkdir -p "$locked"
  printf '%s' "$recipe_no_scan" > "$locked/README.md"
  chmod 000 "$locked"
  if out="$(run_copy)"; then
    fail "an unreadable directory left the plain-copy sweep green"
  fi
  chmod 755 "$locked"
  case "$(printf '%s\n' "$out" | tail -1)" in
    "FAIL: teardown guard sweep: could not list Markdown under the copy"*) : ;;
    *) fail "unreadable directory red for the wrong reason: $(printf '%s\n' "$out" | tail -1)" ;;
  esac
  rm -rf "$tmp_root/hooks"
  unreadable="3 unreadable or unlistable probes red"
fi
mv "$tmp_root/.work/git-off" "$tmp_root/.git"

# Post-control green, then tree isolation: a mutated copy reds while the live
# tree's own fixture stays green, so the walk above read the copy.
run_copy >/dev/null || fail "post-control not green"
first_row="$(head -1 "$rows_file")"
IFS='|' read -r kind rel scope phrase label <<< "$first_row"
cp "$tmp_root/$rel" "$pristine"
mutate mutate "$kind" "$tmp_root/$rel" "$scope" "$phrase" || fail "isolation mutation did not land"
if run_copy >/dev/null; then fail "tree-isolation probe: mutated copy stayed green"; fi
TMPDIR="$tmp_root" bash "$repo_root/$fixture_rel" >/dev/null 2>&1 || fail "tree-isolation probe: live tree fixture not green"
cp "$pristine" "$tmp_root/$rel"

echo "test_teardown_guard_pins: ok ($applied applied mutations, each red on its own row; $relocations relocations red; $reds sweep decoys red, $greens precision decoys green; $unreadable; failed classification red; controls green)"
