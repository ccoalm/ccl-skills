#!/usr/bin/env bash
# Contract-anchor gate: declarative wording-existence pinning for load-bearing
# prose contracts that no structural check would otherwise protect.
#
# Problem class (observed, 074 RED-baseline probes): a skill reference's
# load-bearing contract sentence — a verdict-taxonomy discriminator, a
# stop-condition predicate, an externally verified numeric tier — can be
# deleted, semantically inverted, or numerically falsified while every
# structural gate stays green, because structural gates check shape and
# references, never the survival of specific contract wording.
#
# Mechanism: a sidecar TSV table (contract-anchors.tsv, same directory) lists
# one anchor per row:  id <TAB> repo-relative path <TAB> pinned literal <TAB> note
#   - the literal must occur EXACTLY ONCE in the named file (fixed-string match).
#     0 occurrences  => contract_anchor_missing    (drift/deletion)      exit 1
#     >1 occurrences => contract_anchor_duplicate  (decoy/ambiguity;
#       an anchor that matches twice can no longer prove which copy is the
#       contract — same rule as the sync-pointer registry)                exit 1
#   - a missing anchored file is a broken contract, not infrastructure:
#     contract_anchor_file_missing                                        exit 1
# Table integrity is fail-closed (exit 2, infra): unreadable/empty table
# (an empty list scanning nothing must never certify), malformed row,
# duplicate id, or a literal under 16 characters (too weak to be unique —
# same floor as firing-path anchors).
#
# All rows are scanned before any exit: anchor-drift findings (rc 1) and
# row-integrity findings (rc 2) are each collected across the whole table, so
# one run reports every problem; when both classes are present the run exits 2
# (a broken table means no verdict can be trusted). Green output grammar is
# pinned for the caller:
#   contract_anchor_gate_ok (N anchors)
# Exemptions: none, and deliberately no environment override — an anchor is
# removed or reworded only by editing the table in the same MR that changes
# the pinned wording (reject-and-instruct failure message points there).
#
# Intentional-change recipe (printed on failure): edit the contract sentence
# AND its table row together; the diff then shows the contract change
# explicitly instead of a silent drift.
set -u

script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)
root="${1:-.}"
table="$script_dir/contract-anchors.tsv"
if [[ "${2:-}" == "--table" && -n "${3:-}" ]]; then
  table="$3"
fi

if [[ ! -d "$root" ]]; then
  echo "contract_anchor_root_missing: $root" >&2
  exit 2
fi
if [[ ! -f "$table" || ! -r "$table" ]]; then
  echo "contract_anchor_table_missing: $table" >&2
  exit 2
fi

exec python3 - "$root" "$table" <<'PY'
import os
import sys

root, table = sys.argv[1], sys.argv[2]
real_root = os.path.realpath(root)
table_base = os.path.basename(table)
anchor_count = 0
fail_count = 0
infra_count = 0
seen_ids = set()
file_cache = {}

try:
    with open(table, "rb") as fh:
        raw_lines = fh.read().decode("utf-8", errors="surrogateescape").split("\n")
except OSError:
    print(f"contract_anchor_table_missing: {table}", file=sys.stderr)
    raise SystemExit(2)

if raw_lines and raw_lines[-1] == "":
    raw_lines.pop()

fix_line = (
    f"  fix: restore the contract wording, or — for an intentional contract change — "
    f"update this anchor row in {table_base} in the same MR"
)

for idx, raw in enumerate(raw_lines):
    line_no = idx + 1
    if raw.endswith("\r"):
        raw = raw[:-1]
    if not raw or raw.startswith("#"):
        continue

    fields = raw.split("\t")
    if len(fields) < 4 or any(f == "" for f in fields[:4]):
        print(
            f"contract_anchor_row_malformed: line {line_no} of {table} (need id<TAB>path<TAB>literal<TAB>note)",
            file=sys.stderr,
        )
        infra_count += 1
        continue
    if len(fields) > 4:
        print(
            f"contract_anchor_row_malformed: line {line_no} of {table} (extra tab-separated field)",
            file=sys.stderr,
        )
        infra_count += 1
        continue

    anchor_id, rel_path, literal, _note = fields
    if anchor_id in seen_ids:
        print(
            f"contract_anchor_duplicate_id: {anchor_id} (line {line_no} repeats an earlier row's id)",
            file=sys.stderr,
        )
        infra_count += 1
        continue
    seen_ids.add(anchor_id)

    if len(literal) < 16:
        print(
            f"contract_anchor_literal_too_short: {anchor_id} ({len(literal)} chars, need >=16)",
            file=sys.stderr,
        )
        infra_count += 1
        continue

    rel_parts = rel_path.replace("\\", "/").split("/")
    if os.path.isabs(rel_path) or rel_path.startswith("/") or ".." in rel_parts:
        print(
            f"contract_anchor_row_malformed: line {line_no} of {table} (path must stay relative inside root: {rel_path})",
            file=sys.stderr,
        )
        infra_count += 1
        continue

    target = os.path.join(root, rel_path)
    real_target = os.path.realpath(target)
    if real_target == real_root or not real_target.startswith(real_root + os.sep):
        print(
            f"contract_anchor_row_malformed: line {line_no} of {table} (path escapes root: {rel_path})",
            file=sys.stderr,
        )
        infra_count += 1
        continue

    anchor_count += 1
    if not os.path.isfile(target) or os.path.islink(target):
        print(f"contract_anchor_file_missing: {anchor_id} {rel_path}", file=sys.stderr)
        print(
            f"  fix: restore the anchored file, or — for an intentional move/retirement — "
            f"update or remove this anchor row in {table_base} in the same MR",
            file=sys.stderr,
        )
        fail_count += 1
        continue

    content = file_cache.get(target)
    if content is None:
        try:
            with open(target, "rb") as fh:
                content = fh.read()
        except OSError:
            print(f"contract_anchor_file_unreadable: {anchor_id} {rel_path}", file=sys.stderr)
            infra_count += 1
            continue
        file_cache[target] = content

    lit_bytes = literal.encode("utf-8", errors="surrogateescape")
    occurrences = content.count(lit_bytes)
    if occurrences == 0:
        print(f"contract_anchor_missing: {anchor_id} in {rel_path}", file=sys.stderr)
        print(f"  pinned literal: {literal}", file=sys.stderr)
        print(fix_line, file=sys.stderr)
        fail_count += 1
    elif occurrences > 1:
        print(
            f"contract_anchor_duplicate: {anchor_id} in {rel_path} "
            f"({occurrences} occurrences; the anchor can no longer prove which copy is the contract)",
            file=sys.stderr,
        )
        print(
            f"  fix: keep the pinned wording in exactly one place (dedupe the copy), or repin the anchor row "
            f"in {table_base} to a longer unique literal in the same MR",
            file=sys.stderr,
        )
        fail_count += 1

if infra_count > 0:
    print(
        f"contract_anchor_table_invalid: {infra_count} integrity error(s) in {table} "
        f"(no verdict from a broken table — fail-closed)",
        file=sys.stderr,
    )
    raise SystemExit(2)
if anchor_count == 0:
    print(
        f"contract_anchor_table_empty: {table} has no data rows (an empty anchor set must never certify)",
        file=sys.stderr,
    )
    raise SystemExit(2)
if fail_count > 0:
    print(f"contract_anchor_gate_failed: {fail_count} of {anchor_count} anchors", file=sys.stderr)
    raise SystemExit(1)
print(f"contract_anchor_gate_ok ({anchor_count} anchors)")
PY
