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
if [[ ! -f "$table" ]]; then
  echo "contract_anchor_table_missing: $table" >&2
  exit 2
fi

anchor_count=0
fail_count=0
infra_count=0
# Bash 3.2-safe id-uniqueness set (stock macOS bash has no associative arrays):
# newline-delimited membership string, ids are TSV fields so they carry no tabs
# and no newlines.
seen_ids=$'\n'
line_no=0
while IFS= read -r raw || [[ -n "$raw" ]]; do
  line_no=$((line_no + 1))
  [[ -z "$raw" || "$raw" == \#* ]] && continue
  IFS=$'\t' read -r id path literal note <<<"$raw"
  if [[ -z "${id:-}" || -z "${path:-}" || -z "${literal:-}" || -z "${note:-}" ]]; then
    echo "contract_anchor_row_malformed: line $line_no of $table (need id<TAB>path<TAB>literal<TAB>note)" >&2
    infra_count=$((infra_count + 1))
    continue
  fi
  if [[ "$note" == *$'\t'* ]]; then
    echo "contract_anchor_row_malformed: line $line_no of $table (extra tab-separated field)" >&2
    infra_count=$((infra_count + 1))
    continue
  fi
  case "$seen_ids" in
    *$'\n'"$id"$'\n'*)
      echo "contract_anchor_duplicate_id: $id (line $line_no repeats an earlier row's id)" >&2
      infra_count=$((infra_count + 1))
      continue
      ;;
  esac
  seen_ids="$seen_ids$id"$'\n'
  if (( ${#literal} < 16 )); then
    echo "contract_anchor_literal_too_short: $id (${#literal} chars, need >=16)" >&2
    infra_count=$((infra_count + 1))
    continue
  fi
  anchor_count=$((anchor_count + 1))
  target="$root/$path"
  fix_line="  fix: restore the contract wording, or — for an intentional contract change — update this anchor row in $(basename "$table") in the same MR"
  if [[ ! -f "$target" ]]; then
    echo "contract_anchor_file_missing: $id $path" >&2
    echo "  fix: restore the anchored file, or — for an intentional move/retirement — update or remove this anchor row in $(basename "$table") in the same MR" >&2
    fail_count=$((fail_count + 1))
    continue
  fi
  occurrences=$(grep -oF -- "$literal" "$target" | wc -l | tr -d '[:space:]')
  if [[ "$occurrences" -eq 0 ]]; then
    echo "contract_anchor_missing: $id in $path" >&2
    echo "  pinned literal: $literal" >&2
    echo "$fix_line" >&2
    fail_count=$((fail_count + 1))
  elif [[ "$occurrences" -gt 1 ]]; then
    echo "contract_anchor_duplicate: $id in $path ($occurrences occurrences; the anchor can no longer prove which copy is the contract)" >&2
    echo "  fix: keep the pinned wording in exactly one place (dedupe the copy), or repin the anchor row in $(basename "$table") to a longer unique literal in the same MR" >&2
    fail_count=$((fail_count + 1))
  fi
done < "$table"

if [[ "$infra_count" -gt 0 ]]; then
  echo "contract_anchor_table_invalid: $infra_count integrity error(s) in $table (no verdict from a broken table — fail-closed)" >&2
  exit 2
fi
if [[ "$anchor_count" -eq 0 ]]; then
  echo "contract_anchor_table_empty: $table has no data rows (an empty anchor set must never certify)" >&2
  exit 2
fi
if [[ "$fail_count" -gt 0 ]]; then
  echo "contract_anchor_gate_failed: $fail_count of $anchor_count anchors" >&2
  exit 1
fi
echo "contract_anchor_gate_ok ($anchor_count anchors)"
