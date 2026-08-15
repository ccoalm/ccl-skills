#!/usr/bin/env bash
# Fast-lane containment for the impact-chain gate's date dependency.
#
# The gap this test closes at merge time: the gate's routing-surface
# `#description` locator evaluates `Date` inside `description_is_scalar`, and
# psych only sometimes loads date transitively (<=5.1 lazily, 5.2.0-5.2.5
# never, 5.2.6+ eagerly). Without the gate's own `require "date"`, a date-less
# host turns that NameError into a silent class refusal via `rescue
# StandardError` — the same commit judges green on one host and red on another.
# The deep three-leg differential lives in the heavy suite
# (test_check_ccl_impact_chain_refscripts.sh), which `make test` does not run;
# this fast test keeps the property enforced by every `make test` run using a
# minimal synthetic repo instead of a whole-repo clone.
#
# Legs: (1) fixed gate under a dateless shim stays GREEN; (2) a require-
# stripped mutant under the same shim goes RED for the guarded reason (with a
# cmp guard proving the mutation removed a line); (3) fixed gate with Date
# explicitly preloaded (-rdate) stays GREEN — a deterministic date-preloading
# control on any host, not an accident of the local psych version; (4) the SAME
# mutant with -rdate stays GREEN. Legs (2)x(4) are the differential that proves
# the defect class is host-dependence itself: one mutant, two hosts, two
# verdicts — exactly the masking this fix removes.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd -P)"
GATE="$SCRIPT_DIR/impact-chain-gate.rb"
[ -f "$GATE" ] || { echo "FAIL: gate not found: $GATE" >&2; exit 1; }

TMP="$(mktemp -d "${TMPDIR:-/tmp}/icdateless.XXXXXX")"
trap 'rc=$?; rm -rf "$TMP"; exit $rc' EXIT

fail() { echo "FAIL: $*" >&2; exit 1; }
assert_rc() { [ "$1" = "$2" ] || fail "expected rc=$2 got rc=$1 ($3)"; }
assert_contains() { case "$2" in *"$1"*) : ;; *) fail "expected output to contain '$1' ($3)";; esac; }

# Dateless-host shim: block psych's transitive `require "date"` while letting
# explicit requires through, reproducing the apt-ruby-3.2 / psych<=5.2.5 host
# class on any modern ruby (on such hosts the shim is a natural no-op).
SHIM="$TMP/dateless-require-shim.rb"
cat > "$SHIM" <<'RUBY'
module DatelessRequireShim
  def require(name)
    if name == "date" && caller.any? { |frame| frame.include?("/psych") || frame.include?("psych.rb") }
      return false
    end
    super
  end
end
Object.prepend(DatelessRequireShim)
RUBY

# Minimal synthetic repo: a curated upstream owner whose only change is its
# frontmatter description, plus the register row anchoring on #description —
# the exact shape whose verdict flips on a date-less host without the fix.
REPO="$TMP/repo"
mkdir -p "$REPO"
git -C "$REPO" init -q
git -C "$REPO" config user.email test@example.invalid
git -C "$REPO" config user.name "Test User"
mkdir -p "$REPO/skills/product-rd-workflow" "$REPO/skills/skill-extraction-workflow/references"
cat > "$REPO/skills/product-rd-workflow/SKILL.md" <<'MD'
---
name: product-rd-workflow
description: Fixture routing description for the dateless-host differential.
---

# Fixture Skill

Body content stays byte-identical across the case commit.
MD
printf '| Lesson | Downstream owner | Behavior | Status | Evidence |\n| --- | --- | --- | --- | --- |\n' \
  > "$REPO/skills/skill-extraction-workflow/references/source-register.md"
git -C "$REPO" add -A
git -C "$REPO" commit -qm "seed fixture base"
git -C "$REPO" branch fixture-base HEAD
git -C "$REPO" switch -q -C case-dateless fixture-base
git -C "$REPO" branch --set-upstream-to=fixture-base case-dateless >/dev/null 2>&1
perl -0pi -e 's/^(description: .+)$/$1 Fixture dateless trigger clause./m' "$REPO/skills/product-rd-workflow/SKILL.md"
printf '| Fixture dateless row | `downstream-executor` | behavioral-evidence: RED-baseline; observed-failure: yes; firing-path: file:skills/product-rd-workflow/SKILL.md#description | `updated` | `product-rd-workflow/SKILL.md` description-only fixture change |\n' \
  >> "$REPO/skills/skill-extraction-workflow/references/source-register.md"
git -C "$REPO" add -A
git -C "$REPO" commit -qm "description-only change with #description row"

run_gate() { # <gate-path> <RUBYOPT value or empty>
  set +e
  out="$(env -u ALIAS_AUDIT_CMD -u CCL_SKILL_BASE_REF RUBYOPT="$2" ruby "$1" "$REPO" 2>&1)"
  rc=$?
  set -e
}

# Leg 1: the fixed gate on a date-less host grants the class.
run_gate "$GATE" "-r$SHIM"
assert_rc "$rc" 0 "a date-less host must not refuse the routing-surface class"

# Leg 2: strip the gate's own require and the same fixture must show the
# refusal for the guarded reason. The cmp guard proves the mutation is real —
# if the require line is renamed away, this fails loudly instead of running a
# no-op differential that would false-green a broken shim.
MUTANT="$TMP/impact-chain-gate-dateless-mutant.rb"
grep -v '^require "date"$' "$GATE" > "$MUTANT"
cmp -s "$GATE" "$MUTANT" && fail "dateless mutation is a no-op: the gate no longer contains its require \"date\" line"
run_gate "$MUTANT" "-r$SHIM"
assert_rc "$rc" 1 "without its own require-date the gate must refuse on a date-less host"
assert_contains "impact_chain_firing_path_missing" "$out" "the mutant must fail for the guarded reason"
assert_contains "product-rd-workflow/SKILL.md" "$out" "the mutant must name the refused owner"

# Leg 3: date-preloading control — preload Date explicitly so this leg tests
# the psych-preloads-date host class deterministically on any host, instead of
# depending on the local psych's own behavior.
run_gate "$GATE" "-rdate"
assert_rc "$rc" 0 "a date-preloading host must grant the class unchanged"

# Leg 4: the SAME mutant on the date-preloading host stays green — with leg 2
# this is the two-host differential: identical gate bytes, opposite verdicts,
# which is the host-dependence defect this fix removes. Without this leg a
# broken mutant (one that fails everywhere) could masquerade as leg 2 evidence.
run_gate "$MUTANT" "-rdate"
assert_rc "$rc" 0 "the require-stripped mutant must still pass on a date-preloading host (the masking this fix removes)"

echo "test_impact_chain_gate_dateless_host: ok"
