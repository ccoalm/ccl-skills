#!/usr/bin/env bash
# Self-proof suite for check-contract-anchors.sh.
#
# Oracle self-proof tables (the gate is trusted only because every row below
# was APPLIED and observed):
#
# MUST-HIT (mutant -> expected red token, expected rc):
#   M1 pinned literal deleted from anchored file  -> contract_anchor_missing        rc 1
#   M2 pinned literal duplicated in anchored file -> contract_anchor_duplicate      rc 1
#   M3 anchored file removed                      -> contract_anchor_file_missing   rc 1
#   M4 table emptied (comments only)              -> contract_anchor_table_empty    rc 2
#   M5 malformed row (3 fields)                   -> contract_anchor_row_malformed  rc 2
#   M6 literal under 16 chars                     -> contract_anchor_literal_too_short rc 2
#   M7 duplicate anchor id                        -> contract_anchor_duplicate_id   rc 2
#   M8 table file missing                         -> contract_anchor_table_missing  rc 2
#   M9 malformed row + drifted anchor in one table -> BOTH reported, rc 2
#      (integrity errors are collected, well-formed rows still evaluated,
#       and a broken table yields no verdict — fail-closed over the drift)
#
# MUST-NOT-HIT (benign neighbor -> stays green, rc 0):
#   B1 wording adjacent to the pinned literal edited (same line, outside the pin)
#   B2 unrelated file in the tree edited freely
#   B3 anchored file grows new content elsewhere
#
# DIFFERENTIAL ATTRIBUTION:
#   D1 two anchors, one broken -> output names exactly the broken id, rc 1,
#      and the healthy id is not reported
#
# REAL-REPO LEG:
#   R1 shipped table against the repo root -> rc 0 and pinned output grammar
#      "contract_anchor_gate_ok (<N> anchors)"
set -u

script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)
checker="$script_dir/check-contract-anchors.sh"
repo_root=$(cd "$script_dir/../../.." && pwd -P)
fail=0

note() { printf '%s\n' "$*"; }
expect() { # expect <case> <want_rc> <got_rc> <want_token> <output>
  local case_id="$1" want_rc="$2" got_rc="$3" want_token="$4" output="$5"
  if [[ "$got_rc" -ne "$want_rc" ]]; then
    note "FAIL $case_id: rc=$got_rc want=$want_rc"
    note "$output"
    fail=1
    return
  fi
  if [[ -n "$want_token" && "$output" != *"$want_token"* ]]; then
    note "FAIL $case_id: missing token '$want_token' in output"
    note "$output"
    fail=1
    return
  fi
  note "ok $case_id"
}

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

make_fixture() { # rebuild a fresh fixture tree + table under $tmp/fx
  rm -rf "$tmp/fx"
  mkdir -p "$tmp/fx/docs"
  cat > "$tmp/fx/docs/sample-contract.md" <<'MD'
# Sample contract

The sample verdict is decided by exactly one discriminating predicate here.
Unrelated surrounding prose that may change freely.
MD
  cat > "$tmp/fx/docs/other.md" <<'MD'
Free-floating document with no anchors at all.
MD
  printf '%s\t%s\t%s\t%s\n' \
    "sample-discriminator" "docs/sample-contract.md" \
    "decided by exactly one discriminating predicate" "fixture row" \
    > "$tmp/fx/anchors.tsv"
}

run() { # run <root> <table>; sets got_rc/got_out
  got_out=$(bash "$checker" "$1" --table "$2" 2>&1)
  got_rc=$?
}

# R1: shipped table against the real repo
run "$repo_root" "$script_dir/contract-anchors.tsv"
expect R1 0 "$got_rc" "contract_anchor_gate_ok (" "$got_out"
if ! grep -qE '^contract_anchor_gate_ok \([0-9]+ anchors\)$' <<<"$got_out"; then
  note "FAIL R1-grammar: green output grammar drifted: $got_out"
  fail=1
else
  note "ok R1-grammar"
fi

# Green fixture control (precondition for every mutant below)
make_fixture
run "$tmp/fx" "$tmp/fx/anchors.tsv"
expect C0 0 "$got_rc" "contract_anchor_gate_ok (1 anchors)" "$got_out"

# M1 literal deleted
make_fixture
perl -pi -e 's/decided by exactly one discriminating predicate/decided case by case/' "$tmp/fx/docs/sample-contract.md"
run "$tmp/fx" "$tmp/fx/anchors.tsv"
expect M1 1 "$got_rc" "contract_anchor_missing: sample-discriminator" "$got_out"

# M2 literal duplicated
make_fixture
printf '\nA second copy: decided by exactly one discriminating predicate.\n' >> "$tmp/fx/docs/sample-contract.md"
run "$tmp/fx" "$tmp/fx/anchors.tsv"
expect M2 1 "$got_rc" "contract_anchor_duplicate: sample-discriminator" "$got_out"

# M3 anchored file removed
make_fixture
rm "$tmp/fx/docs/sample-contract.md"
run "$tmp/fx" "$tmp/fx/anchors.tsv"
expect M3 1 "$got_rc" "contract_anchor_file_missing: sample-discriminator" "$got_out"

# M4 table emptied
make_fixture
printf '# only comments\n\n' > "$tmp/fx/anchors.tsv"
run "$tmp/fx" "$tmp/fx/anchors.tsv"
expect M4 2 "$got_rc" "contract_anchor_table_empty" "$got_out"

# M5 malformed row
make_fixture
printf 'bad-row\tdocs/sample-contract.md\tonly three fields\n' > "$tmp/fx/anchors.tsv"
run "$tmp/fx" "$tmp/fx/anchors.tsv"
expect M5 2 "$got_rc" "contract_anchor_row_malformed" "$got_out"

# M6 short literal
make_fixture
printf 'short\tdocs/sample-contract.md\ttiny pin\tnote\n' > "$tmp/fx/anchors.tsv"
run "$tmp/fx" "$tmp/fx/anchors.tsv"
expect M6 2 "$got_rc" "contract_anchor_literal_too_short" "$got_out"

# M7 duplicate id
make_fixture
printf '%s\t%s\t%s\t%s\n' "sample-discriminator" "docs/sample-contract.md" \
  "Unrelated surrounding prose that may change" "second row same id" >> "$tmp/fx/anchors.tsv"
run "$tmp/fx" "$tmp/fx/anchors.tsv"
expect M7 2 "$got_rc" "contract_anchor_duplicate_id" "$got_out"

# M8 table missing
make_fixture
run "$tmp/fx" "$tmp/fx/missing.tsv"
expect M8 2 "$got_rc" "contract_anchor_table_missing" "$got_out"

# M9 malformed row + drifted anchor: both reported in one run, rc 2
make_fixture
printf 'bad-row\tdocs/sample-contract.md\tonly three fields\n' >> "$tmp/fx/anchors.tsv"
perl -pi -e 's/decided by exactly one discriminating predicate/decided informally/' "$tmp/fx/docs/sample-contract.md"
run "$tmp/fx" "$tmp/fx/anchors.tsv"
expect M9 2 "$got_rc" "contract_anchor_table_invalid" "$got_out"
if [[ "$got_out" != *"contract_anchor_row_malformed"* || "$got_out" != *"contract_anchor_missing: sample-discriminator"* ]]; then
  note "FAIL M9-completeness: expected both the integrity error and the drift finding in one run"
  note "$got_out"
  fail=1
else
  note "ok M9-completeness"
fi

# B1 benign neighbor: same line, outside the pinned span
make_fixture
perl -pi -e 's/predicate here\./predicate here, with a clarifying tail./' "$tmp/fx/docs/sample-contract.md"
run "$tmp/fx" "$tmp/fx/anchors.tsv"
expect B1 0 "$got_rc" "contract_anchor_gate_ok" "$got_out"

# B2 unrelated file edited
make_fixture
printf 'More free text.\n' >> "$tmp/fx/docs/other.md"
run "$tmp/fx" "$tmp/fx/anchors.tsv"
expect B2 0 "$got_rc" "contract_anchor_gate_ok" "$got_out"

# B3 anchored file grows elsewhere
make_fixture
printf '\n## New unrelated section\n\nNew prose.\n' >> "$tmp/fx/docs/sample-contract.md"
run "$tmp/fx" "$tmp/fx/anchors.tsv"
expect B3 0 "$got_rc" "contract_anchor_gate_ok" "$got_out"

# D1 differential attribution: two anchors, one broken
make_fixture
printf '%s\t%s\t%s\t%s\n' "healthy-anchor" "docs/sample-contract.md" \
  "Unrelated surrounding prose that may change freely." "healthy row" >> "$tmp/fx/anchors.tsv"
perl -pi -e 's/decided by exactly one discriminating predicate/decided informally/' "$tmp/fx/docs/sample-contract.md"
run "$tmp/fx" "$tmp/fx/anchors.tsv"
expect D1 1 "$got_rc" "contract_anchor_missing: sample-discriminator" "$got_out"
if [[ "$got_out" == *"healthy-anchor"* ]]; then
  note "FAIL D1-attribution: healthy anchor reported in failure output"
  fail=1
else
  note "ok D1-attribution"
fi

if [[ "$fail" -ne 0 ]]; then
  echo "test_check_contract_anchors: FAIL"
  exit 1
fi
echo "test_check_contract_anchors: ok"
