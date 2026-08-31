#!/usr/bin/env bash
# Oracle self-proof walk for the pinned-phrase gate families in
# check-ccl-skills.sh (heavy lane: each leg runs the full shipped gate against
# a fixture clone of the working tree).
#
# Why this exists (074): the pinned-phrase families are straight-line bash
# loops; an empty phrase list, a quoting regression, or a broken exit path
# would turn every one of them into an always-green check with no signal.
# None of the ~40 pinned phrases had ever been proven capable of going red.
# This walk applies one deletion mutation per gate family and requires the
# full gate to fail RED with that family's own token (differential
# attribution: the mutant leg must fail on the mutated family, and the
# unmutated control leg must show every family token green).
#
# MUST-HIT (one applied mutation per family -> expected red token):
#   W1 existing-project-assessment-report.md loses "Assessment launch checklist"
#        -> project_assessment_template_gate_missing
#   W2 skill-extraction-workflow/SKILL.md loses "would other teammates hit this"
#        -> skill_extraction_teammate_trigger_gate_missing
#   W3 testing-strategy/SKILL.md loses "先写测试用例"
#        -> testing_strategy_test_case_first_gate_missing
#   W4 product-rd-workflow/SKILL.md loses "### Pre-Final Continuation Gate"
#        -> product_rd_entrypoint_anchor_gate_missing
#   W5 contract-anchored reference loses its pinned discriminator sentence
#        -> contract_anchor_missing (via the delegated contract-anchor gate)
#
# MUST-NOT-HIT (control): the unmutated fixture run exits 0 and prints every
# family green token (project_assessment_template_gate_ok,
# task_retro_memory_escape_gate_ok, test_case_first_gate_ok,
# product_rd_entrypoint_anchor_gate_ok, contract_anchor_gate_ok).
#
# Coverage boundary (stated, not silent): one pin per family is mutated, so
# the walk attests each family's parse/exit path, not every individual phrase;
# per-family phrase-list non-vacuity is separately asserted by counting the
# `for required_phrase in` loops and requiring each mutated phrase to exist in
# the fixture before mutation. ALIAS_AUDIT_CMD is unset for determinism (the
# gate then takes the public-fallback R0 branch on every host).
set -u

script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)
repo_root=$(cd "$script_dir/../../.." && pwd -P)
gate_rel="skills/skill-extraction-workflow/scripts/check-ccl-skills.sh"
fail=0

note() { printf '%s\n' "$*"; }

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

# Fixture: faithful copy of the working tree (tracked + untracked-unignored),
# committed once so BASE_REF=HEAD yields an empty diff.
fixture="$tmp/fixture"
mkdir -p "$fixture"
(cd "$repo_root" && git ls-files --cached --others --exclude-standard -z \
  | tar --null -T - -cf - ) | tar -xf - -C "$fixture"
git -C "$fixture" init -q
git -C "$fixture" -c user.name=fixture -c user.email=fixture@invalid add -A
git -C "$fixture" -c user.name=fixture -c user.email=fixture@invalid commit -qm fixture
# The impact-chain gate resolves merge-bases against origin/main and origin/dev;
# point both at the fixture's single commit so diff-scoped gates see an empty
# scope instead of dying on a missing remote ref.
git -C "$fixture" update-ref refs/remotes/origin/main HEAD
git -C "$fixture" update-ref refs/remotes/origin/dev HEAD

# Vacuity guard: the shipped gate must still carry its pinned-phrase loops.
loop_count=$(grep -c 'for required_phrase in' "$fixture/$gate_rel")
if [[ "$loop_count" -lt 7 ]]; then
  note "FAIL vacuity-guard: expected >=7 'for required_phrase in' loops, found $loop_count"
  fail=1
fi

run_gate() { # run_gate -> sets got_rc/got_out (full gate inside the fixture)
  # CCL_SKILL_BASE_REF is deliberately NOT set: it would leak into child
  # validators' synthetic self-test repos (where HEAD always resolves and
  # turns their "no base -> degraded" legs into false passes). The fixture has
  # a single commit, so diff-scoped gates see an empty scope and the run lands
  # interim — the pinned-phrase families under test are tree scans and run
  # fully either way.
  got_out=$(cd "$fixture" && env -u ALIAS_AUDIT_CMD -u CCL_SKILL_BASE_REF \
    bash "$gate_rel" . 2>&1)
  got_rc=$?
}

restore_fixture() {
  git -C "$fixture" checkout -q -- .
}

mutate() { # mutate <repo-relative-file> <exact-phrase-to-delete>
  local file="$fixture/$1" phrase="$2"
  if ! grep -qF -- "$phrase" "$file"; then
    note "FAIL pre-mutation: phrase not present (walk out of sync): $phrase"
    fail=1
    return 1
  fi
  PHRASE="$phrase" perl -pi -e 's/\Q$ENV{PHRASE}\E/mutated-away/g' "$file"
}

walk() { # walk <case> <file> <phrase> <expected-red-token>
  local case_id="$1" file="$2" phrase="$3" token="$4"
  mutate "$file" "$phrase" || return
  run_gate
  if [[ "$got_rc" -eq 0 ]]; then
    note "FAIL $case_id: gate stayed green under applied mutation ($token never fired)"
    fail=1
  elif [[ "$got_out" != *"$token"* ]]; then
    note "FAIL $case_id: gate red but wrong reason (wanted $token)"
    note "$(tail -n 5 <<<"$got_out")"
    fail=1
  else
    note "ok $case_id ($token)"
  fi
  restore_fixture
}

# Control leg first: unmutated fixture must be green with every family token.
run_gate
if [[ "$got_rc" -ne 0 ]]; then
  note "FAIL control: unmutated fixture gate rc=$got_rc"
  note "$(tail -n 10 <<<"$got_out")"
  fail=1
else
  for token in \
    project_assessment_template_gate_ok \
    task_retro_memory_escape_gate_ok \
    test_case_first_gate_ok \
    product_rd_entrypoint_anchor_gate_ok \
    "contract_anchor_gate_ok ("; do
    if [[ "$got_out" != *"$token"* ]]; then
      note "FAIL control: green run missing family token $token"
      fail=1
    fi
  done
  [[ "$fail" -eq 0 ]] && note "ok control (all family tokens green)"
fi

walk W1 "skills/product-rd-workflow/references/existing-project-assessment-report.md" \
  "Assessment launch checklist" "project_assessment_template_gate_missing"
walk W2 "skills/skill-extraction-workflow/SKILL.md" \
  "would other teammates hit this" "skill_extraction_teammate_trigger_gate_missing"
walk W3 "skills/testing-strategy/SKILL.md" \
  "先写测试用例" "testing_strategy_test_case_first_gate_missing"
walk W4 "skills/product-rd-workflow/SKILL.md" \
  "### Pre-Final Continuation Gate" "product_rd_entrypoint_anchor_gate_missing"
walk W5 "skills/testing-strategy/references/ci-fixtures-and-flake-control.md" \
  "One discriminating predicate decides the verdict" "contract_anchor_missing"

if [[ "$fail" -ne 0 ]]; then
  echo "test_pinned_phrase_mutation_walk: FAIL"
  exit 1
fi
echo "test_pinned_phrase_mutation_walk: ok"
