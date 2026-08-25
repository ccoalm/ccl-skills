#!/usr/bin/env bash
# No-verdict-regression differential for the impact-chain gate.
#
# The probe suite proves the gate refuses what it should. This proves it did not
# start refusing anything it used to accept — the other half, and the half that
# blocks every author when it goes wrong. A shared merge gate cannot ship a
# tightening on an asserted "I checked": the check has to be re-runnable by
# whoever reviews or reverts it.
#
# Method: for each pinned integration point M on the integration branch, the
# gate's real input was (base = M's first parent, HEAD = M) — that is the merge
# result CI evaluates. Replay exactly that for the BASELINE gate blob and for the
# working-tree gate, and compare exit verdicts. A range that the baseline accepted
# and the candidate refuses is a regression and fails this test.
#
# Refs are pinned by SHA, not by branch name, so this keeps testing the same
# history after the branch moves. Missing refs FAIL rather than skip: a
# differential that silently tests nothing is worse than no differential.
#
# TWO INPUT SETS, because the pins alone can only prove one direction. Every
# pinned integration point is baseline-GREEN — asserted per point, not assumed,
# since a baseline that failed for an EXECUTION reason (missing runtime,
# incompatible checkout, moved path) is otherwise indistinguishable from a
# candidate refusing for a POLICY reason: both nonzero, no mismatch recorded, a
# green run certifying nothing. But an all-green input set makes the
# newly-accepted arm unreachable, so a loosened candidate would clear all twelve
# and the run would still claim "no change in either direction".
#
# The synthetic replay cases at the bottom carry the other half: one is
# baseline-RED by construction (an owner changed with no ledger row), so a
# candidate that stopped refusing it is caught there and nowhere else. Each case
# declares the verdict the baseline must produce, and a refusal must also carry
# its expected diagnostic token — that token is what separates a policy refusal
# from a broken fixture, which would otherwise be banked as evidence.
#
# Oracle: an always-refuse candidate fails on the pins; an always-accept
# candidate fails on the baseline-red case. Both arms are exercised.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd -P)"
CANDIDATE_GATE="$SCRIPT_DIR/impact-chain-gate.rb"
[ -f "$CANDIDATE_GATE" ] || { echo "FAIL: gate not found: $CANDIDATE_GATE" >&2; exit 1; }

REPO_ROOT="$(git -C "$SCRIPT_DIR" rev-parse --show-toplevel)" || exit 1

# The gate as it stood before the row-ownership change, pinned by the commit it
# last shipped in. Update this together with the integration points below only
# when re-baselining deliberately, and say so in the commit that does it.
BASELINE_GATE_COMMIT="5146b3b315c487f93ba352584a0b27af9414676b"
GATE_PATH="skills/skill-extraction-workflow/scripts/impact-chain-gate.rb"

# Integration points, newest first: EVERY merge commit reachable from
# BASELINE_GATE_COMMIT — the whole integration history this gate has judged, not
# a window into it. The list is asserted against git's own answer below, so a pin
# quietly dropped or left stale after a history rewrite fails the test instead of
# shrinking its coverage silently.
INTEGRATION_POINTS="
5146b3b315c487f93ba352584a0b27af9414676b
b9de138694624df13cba05ec9bdb4c99c3cc8ef5
17db43bcb4083423ba071de26071041d3b3c1c67
1b21d2efda0e64da47ab468d338a671be483bc0b
73a62ca2da1f41bfe7bb9fb728315bdc0b9d0f27
f7b11522e7e46fce2dee5ed2d6fc2b73b04eb6ac
e645ea975e922bdb0a7036f853a2ecfdd19bb184
d767d2ff6ed80ff91b05a5dcd1fe946eea0e785c
af3f5e7d1410f62b7eaafe88bdff915af5d41831
2b11657630e1a3c4cb8650b4d1f5f8282bcf0a16
ff31d0ca0bd79405ac2dded54647c3a743511425
4b7afd22a1001769ce970de4dfb41be28da578fc
d4c9b092655e284e511855c4306ed7a9d1b0aa10
f03b1140fc4c2b304411eb67d7771479c82874bf
d2d6337e26493e762a3af3db624894e300008081
a04f9a0bea97a1c53b3cab95ce7337cccec2583c
76e8b8ccbd3178fc2341b674c8486356e63081d9
c5d2d35e2e7c9b6725c2b533dd480bda3a9bacbf
1b0c6fb0683d86fb9c6458a61beb32516c63f3cc
408e11104c2cf5e47dcfe170243a260ffb5e8165
93d09c563ff7bfe7ccc6c20b8b0d2f9c1758c031
4516e30952cc429e2d0e5dbb7971a4e64796feae
1ab0af0966044b1a1875a8737a448e394566db15
6437abee61f9c41f3f890d75165aee701dfbbc65
bd9d01b3b909f85529b5ef87539c6e73a7fa0be9
e8c128d178ae2df94454859081ab0cad5ef52206
b05b74d6796a511f88208673872990aa20027675
61f5b2e1937c87ed4eeb763c1adf883fdbc97d79
98735e027f10dcda57a6649534b9f6af3a451a71
989cf5f9a0e4f33c4cf8ccb839b01da78b94af18
c84beaf47805c4187714dbbf9010b04c08b0a585
138ce664f1e40ccd563b3be896652b8335988003
06163ecb1a2448deef50ff91527849b22a89fbfd
9f233728a3b9deac9ba9a8c12d1d4fd3693bf2e6
8cea35e6dba34a8af6eba3746d14b89efacc147a
31d3b3f1ba130622fd888c2a6e35ba1b6eaafd1e
34d504bec2dc5ec9935a9896fff71872359042fa
759dc6030e9ae6ba8dca06d77a4afdb93231b12a
2205292a900ad609f92d2d89d4ed9fbdc5f9456d
673fece3cf3d893ed6707119f60cd656f3ae6331
95f06b2e6057c4f070ab072f42ef959042a44036
0fd26e7aeed9832307b7a6724855f31269c71b5f
19a04b6a3e4c3025185690470fd501ba82f126d8
8b0f44be666b894af319cecf823fca64ba448631
fb551574b0d8cfac7022c406daa847717f46cc46
37faff720a4786eaeeda328605a046cc1d66189d
c0561c74e0f7249b8041f7c5800a8d6deadf496f
7f114e56d9893f78834dc4f3bca2e2cfc6dfb320
d249ab85d17705e4a30935759a15ff613a38a05c
d63ac44bd37b9375309515c8ff62bc91d3f78072
2aa8cd3d92efe18cb7a18990488481664f6b1286
48e9eb627be2ee9f484f7b11a966ce8d4b146958
1ecc8558da485eb8784030d629b0bb21547c07cb
2a0ec222a847fb1a71396d0dcbd439004dfc1c0c
6a795af5690a30bcef598e37886dd0cf06d9dc15
87d42560005030dca3bef7a7aa0ef21e340059ae
b332b01059eb7322a32d3ef186fd8bbb25e0037e
a63246578f53d849e0a5cb41cb65763a5cdf4fcc
fad480296eb0334291d804cdc3f1f7f0928d802d
90ec533e172acdda8c6b42a20b572488bfe29b59
ba0a1cc44d28f17ae1aafed390518655eaf7598c
046612652f4613ae8f569a1f3287afcbd7509de6
4c0904bf7c7d342bac0deafced16a8ba157d40d5
15a89e95b7fc6ba0112fdb777545b55cc683f90b
"

TMP="$(mktemp -d "${TMPDIR:-/tmp}/icverdict.XXXXXX")"
cleanup() {
  rc=$?
  git -C "$REPO_ROOT" worktree remove --force "$TMP/probe" >/dev/null 2>&1 || true
  rm -rf "$TMP"
  exit $rc
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

BASELINE_GATE="$TMP/impact-chain-gate-baseline.rb"
git -C "$REPO_ROOT" show "$BASELINE_GATE_COMMIT:$GATE_PATH" > "$BASELINE_GATE" 2>/dev/null || {
  echo "FAIL: baseline gate blob is unreachable at $BASELINE_GATE_COMMIT:$GATE_PATH" >&2
  echo "      fetch the integration branch's history, or re-baseline deliberately" >&2
  exit 1
}

# EXPECTED DIVERGENCES. Four landings back-filled a ledger row by corrective
# rewrite — the repair for a round that merged with this gate red — so the owner
# change sits below their base and the row cites an owner the range does not
# touch. The candidate refuses that shape by design and deliberately offers no
# author-declared escape, so these four historical ranges diverge. The gate is
# diff-scoped and never re-judges landed history, so nothing operational depends
# on them; this differential is the only thing that replays them.
#
# Each exemption is constrained to ONE direction and ONE diagnostic. A blanket
# "any mismatch at this SHA is fine" would also swallow the opposite direction —
# a loosening — which is the failure this whole suite exists to catch. Entries are
# named individually, never matched by pattern, and an entry that stops diverging
# is reported as stale rather than tolerated.
EXPECTED_DIVERGENCE_SHAS="f03b1140f 93d09c563 9f233728a 046612652"
EXPECTED_DIVERGENCE_DIRECTION="newly refused"
EXPECTED_DIVERGENCE_TOKEN="impact_chain_row_vouches_for_unchanged_owner"
expected_divergence() { # <full sha> <direction> <candidate output>
  local short="${1:0:9}" direction="$2" out="$3" known
  [ "$direction" = "$EXPECTED_DIVERGENCE_DIRECTION" ] || return 1
  case "$out" in *"$EXPECTED_DIVERGENCE_TOKEN"*) : ;; *) return 1 ;; esac
  for known in $EXPECTED_DIVERGENCE_SHAS; do
    [ "$known" = "$short" ] && return 0
  done
  return 1
}

# A no-op differential would pass vacuously and certify nothing. With expected
# divergences configured it is worse than vacuous: identical gates cannot produce
# them, so the exemptions are stale and the run would pass while silently failing
# the staleness check it never reaches.
if cmp -s "$BASELINE_GATE" "$CANDIDATE_GATE"; then
  if [ -n "$(printf '%s' "$EXPECTED_DIVERGENCE_SHAS" | tr -d '[:space:]')" ]; then
    echo "FAIL: baseline and candidate are byte-identical, yet expected divergences are configured" >&2
    echo "      identical gates cannot diverge — the exemptions are stale and must be removed" >&2
    exit 1
  fi
  echo "impact_chain_gate_verdict_differential: baseline and candidate are byte-identical — nothing to compare"
  exit 0
fi

# Completeness assertion: the pinned list must be exactly every merge commit
# reachable from the baseline, which is the whole integration history this gate
# has ever judged. Without it the list is a hand sample that can lose points
# silently while still reporting a clean run.
expected_pins="$(git -C "$REPO_ROOT" rev-list --merges "$BASELINE_GATE_COMMIT" | tr -d ' ')"
actual_pins="$(printf '%s\n' $INTEGRATION_POINTS)"
if [ "$expected_pins" != "$actual_pins" ]; then
  echo "FAIL: the pinned set is not every merge commit reachable from $BASELINE_GATE_COMMIT" >&2
  echo "      re-baselining is a deliberate edit: regenerate the list and say so in the commit" >&2
  diff <(printf '%s\n' "$expected_pins") <(printf '%s\n' "$actual_pins") | head -20 | sed 's/^/      | /' >&2
  exit 1
fi

regressions=0
expected_seen=0
compared=0
for point in $INTEGRATION_POINTS; do
  git -C "$REPO_ROOT" rev-parse -q --verify "$point^{commit}" >/dev/null || {
    echo "FAIL: pinned integration point is not present: $point" >&2
    exit 1
  }
  parent="$(git -C "$REPO_ROOT" rev-parse "$point^1")"
  subject="$(git -C "$REPO_ROOT" log --format=%s -n 1 "$point" | cut -c1-46)"
  git -C "$REPO_ROOT" worktree remove --force "$TMP/probe" >/dev/null 2>&1 || true
  git -C "$REPO_ROOT" worktree add --detach -q "$TMP/probe" "$point" >/dev/null 2>&1 || {
    echo "FAIL: could not materialize $point" >&2
    exit 1
  }
  set +e
  baseline_out="$(env -u ALIAS_AUDIT_CMD CCL_SKILL_BASE_REF="$parent" ruby "$BASELINE_GATE" "$TMP/probe" 2>&1)"
  baseline_rc=$?
  set -e
  # A nonzero baseline is only usable as a verdict when it is a POLICY refusal.
  # An execution failure — missing runtime, incompatible checkout, moved path —
  # also exits nonzero, and treating it as "the baseline refused" would let it
  # mask a real candidate regression on the same point. The gate names every
  # refusal it makes, so requiring one of those names is what separates the two.
  if [ "$baseline_rc" != 0 ]; then
    case "$baseline_out" in
      *impact_chain_*) : ;;
      *)
        echo "FAIL: baseline exited $baseline_rc on $point without naming a gate refusal" >&2
        echo "      that is an execution failure, not a verdict; fix the environment or re-baseline" >&2
        printf '%s\n' "$baseline_out" | head -10 | sed 's/^/      | /' >&2
        exit 1
        ;;
    esac
  fi
  set +e
  candidate_out="$(env -u ALIAS_AUDIT_CMD CCL_SKILL_BASE_REF="$parent" ruby "$CANDIDATE_GATE" "$TMP/probe" 2>&1)"
  candidate_rc=$?
  set -e
  compared=$((compared + 1))
  # The same rule on the candidate side. Comparing exit codes alone counts
  # "both nonzero" as agreement, so a candidate that CRASHES on a point the
  # baseline legitimately refuses reads as unchanged — the one place a real
  # regression could hide behind a matching number.
  if [ "$candidate_rc" != 0 ]; then
    case "$candidate_out" in
      *impact_chain_*) : ;;
      *)
        echo "FAIL: candidate exited $candidate_rc on $point without naming a gate refusal" >&2
        echo "      that is an execution failure, not a verdict" >&2
        printf '%s\n' "$candidate_out" | head -10 | sed 's/^/      | /' >&2
        exit 1
        ;;
    esac
  fi
  # EITHER direction is a mismatch. Reporting only the tighten-side drift would
  # let a loosening pass the very evidence a tightening-only change offers: a
  # point the baseline refused and the candidate now accepts is a silently
  # widened gate, which on a shared merge gate is the worse of the two failures.
  # An intended verdict change re-baselines the pins deliberately and says so;
  # it does not slip through as an informational line.
  flag=""
  direction=""
  if [ "$baseline_rc" = 0 ] && [ "$candidate_rc" != 0 ]; then
    direction="newly refused"
  elif [ "$baseline_rc" != 0 ] && [ "$candidate_rc" = 0 ]; then
    direction="newly accepted"
  fi
  if [ -n "$direction" ]; then
    if expected_divergence "$point" "$direction" "$candidate_out"; then
      flag="  (expected divergence: corrective-rewrite back-fill, $direction)"
      expected_seen=$((expected_seen + 1))
    else
      flag="  <== VERDICT MISMATCH: $direction"
      regressions=$((regressions + 1))
    fi
  fi
  # Only mismatches are printed: 64 agreeing lines is noise that hides the one
  # line that matters.
  if [ -n "$flag" ]; then
    printf '%-10s %-10s rc=%-4s rc=%-4s %s%s\n' \
      "${point:0:9}" "${parent:0:9}" "$baseline_rc" "$candidate_rc" "$subject" "$flag"
  fi
  if [ -n "$flag" ] && [ "$candidate_rc" != 0 ]; then
    printf '%s\n' "$candidate_out" | head -8 | sed 's/^/       | /'
  fi
done



# ---------------------------------------------------------------------------
# BASELINE-RED REPLAY CASES.
#
# Every pinned integration point is baseline-green, and the assertion above
# exits on any that is not. That makes the newly-accepted arm unreachable over
# the pins alone: an always-accept candidate would clear all twelve and the run
# would still report "no change in either direction" — a claim wider than the
# evidence. The refusals the replaced gate made are the other half of its
# behavior and need their own cases.
#
# Each case declares the verdict the BASELINE must produce and, for a refusal,
# the diagnostic token that refusal must carry. Asserting the token is what
# keeps a policy refusal distinguishable from an execution failure: a ruby
# crash, a missing path, or a broken fixture also exits nonzero, and counting
# that as "the baseline refused" would bank a broken setup as evidence.
# ---------------------------------------------------------------------------
LEDGER_REL="skills/skill-extraction-workflow/references/source-register.md"

seed_case() { # <dir>
  local repo="$1"
  mkdir -p "$repo/skills/product-rd-workflow" "$repo/skills/skill-extraction-workflow/references"
  git -C "$repo" init -q -b trunk
  git -C "$repo" config user.email test@example.invalid
  git -C "$repo" config user.name "Test User"
  git -C "$repo" config commit.gpgsign false
  cat > "$repo/skills/product-rd-workflow/SKILL.md" <<'MD'
---
name: product-rd-workflow
description: Fixture owner for the verdict differential's baseline-red cases.
---

# Fixture Owner

## Rules

- Baseline rule line present before the case commit.
MD
  printf '| Lesson | Downstream owner | Behavior | Status | Evidence |\n| --- | --- | --- | --- | --- |\n' \
    > "$repo/$LEDGER_REL"
  git -C "$repo" add -A
  git -C "$repo" commit -qm "seed"
  git -C "$repo" branch fixture-base HEAD
  git -C "$repo" switch -q -c case fixture-base
  printf -- '- Rule DIFFERENTIAL-CASE must be recorded before the round lands.\n' \
    >> "$repo/skills/product-rd-workflow/SKILL.md"
}

case_failures=0
run_case() { # <name> <expected-baseline-rc> <expected-token-or-empty> <declare:yes|no>
  local name="$1" want_rc="$2" want_token="$3" declare_row="$4"
  local repo="$TMP/case-$name"
  seed_case "$repo"
  if [ "$declare_row" = yes ]; then
    printf '| Fixture differential row | `downstream-executor` | behavioral-evidence: RED-baseline; observed-failure: yes; result-class: failure; firing-path: file:skills/product-rd-workflow/SKILL.md#DIFFERENTIAL-CASE | `updated` | `product-rd-workflow/SKILL.md` fixture change |\n' \
      >> "$repo/$LEDGER_REL"
  fi
  git -C "$repo" add -A
  git -C "$repo" commit -qm "case commit"

  set +e
  local b_out c_out b_rc c_rc
  b_out="$(env -u ALIAS_AUDIT_CMD CCL_SKILL_BASE_REF=fixture-base ruby "$BASELINE_GATE" "$repo" 2>&1)"
  b_rc=$?
  c_out="$(env -u ALIAS_AUDIT_CMD CCL_SKILL_BASE_REF=fixture-base ruby "$CANDIDATE_GATE" "$repo" 2>&1)"
  c_rc=$?
  set -e

  # The baseline must produce the verdict this case exists to pin. Anything else
  # is a broken fixture or environment, and continuing would compare against it.
  if [ "$b_rc" != "$want_rc" ]; then
    echo "FAIL: case '$name' expected baseline rc=$want_rc, got rc=$b_rc" >&2
    printf '%s\n' "$b_out" | head -6 | sed 's/^/      | /' >&2
    exit 1
  fi
  if [ -n "$want_token" ]; then
    case "$b_out" in
      *"$want_token"*) : ;;
      *)
        echo "FAIL: case '$name' baseline refused, but not for '$want_token' — treat as setup failure, not policy" >&2
        printf '%s\n' "$b_out" | head -6 | sed 's/^/      | /' >&2
        exit 1
        ;;
    esac
  fi

  # Same rule on the candidate as on the baseline: a nonzero exit only counts as
  # a verdict when it names a refusal. Comparing exit codes alone lets a candidate
  # that CRASHES on the baseline-red case match rc=1 and read as agreement — the
  # one place this case could certify nothing while looking green.
  if [ "$c_rc" != 0 ]; then
    case "$c_out" in
      *impact_chain_*) : ;;
      *)
        echo "FAIL: case '$name' candidate exited $c_rc without naming a gate refusal" >&2
        echo "      that is an execution failure, not a verdict" >&2
        printf '%s\n' "$c_out" | head -6 | sed 's/^/      | /' >&2
        exit 1
        ;;
    esac
  fi
  local flag=""
  if [ "$b_rc" = 0 ] && [ "$c_rc" != 0 ]; then
    flag="  <== VERDICT MISMATCH: newly refused"; case_failures=$((case_failures + 1))
  elif [ "$b_rc" != 0 ] && [ "$c_rc" = 0 ]; then
    flag="  <== VERDICT MISMATCH: newly accepted"; case_failures=$((case_failures + 1))
  fi
  printf '%-28s rc=%-4s rc=%-4s %s%s\n' "$name" "$b_rc" "$c_rc" "(expected baseline rc=$want_rc)" "$flag"
  if [ -n "$flag" ]; then
    printf '%s\n' "$c_out" | head -6 | sed 's/^/       | /'
  fi
}

echo
printf '%-28s %-7s %-7s %s\n' CASE BASELINE CANDIDATE EXPECTATION
# Baseline-RED: an owner changed with no ledger row. This is the case that makes
# the newly-accepted arm reachable — a candidate that stopped refusing it would
# be caught here and nowhere else.
run_case "undeclared-owner-change" 1 "impact_chain_gate_missing" no
# Baseline-GREEN control on the same fixture shape, so a case that fails does so
# because of the missing declaration and not because the shape itself is refused.
run_case "declared-owner-change" 0 "" yes

echo
total_failures=$((regressions + case_failures))
if [ "$total_failures" -gt 0 ]; then
  echo "impact_chain_gate_verdict_differential: $regressions/$compared integration points and $case_failures replay cases changed verdict unexpectedly" >&2
  exit 1
fi
# An expected divergence that stops diverging means the exemption is stale and
# should be removed, so it is reported rather than silently tolerated.
expected_total="$(for e in $EXPECTED_DIVERGENCE_SHAS; do echo "$e"; done | wc -l | tr -d ' ')"
if [ "$expected_seen" != "$expected_total" ]; then
  echo "FAIL: $expected_seen of $expected_total expected divergences actually diverged" >&2
  echo "      an exemption that no longer fires is stale — remove it" >&2
  exit 1
fi
echo "impact_chain_gate_verdict_differential: ok ($compared integration points, $expected_seen named expected divergences, 2 replay cases incl. one baseline-red; no unexpected verdict change in either direction)"
