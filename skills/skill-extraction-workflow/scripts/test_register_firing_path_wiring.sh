#!/usr/bin/env bash
# Production-wiring regression for the register firing-path gate.
#
# test_register_firing_path_resolution.sh exercises the Ruby gate DIRECTLY, so it
# stays green even if the `ruby "$firing_path_gate" "$root"` line is deleted from
# check-ccl-skills.sh — the gate would be unreachable in production while its
# own suite reported success. That is the same unregistered-suite false green this
# repository has hit before, one layer up: registered, passing, and enforcing
# nothing. This test closes it by driving the checker ENTRYPOINT.
#
# ALIAS_AUDIT_CMD=true stands in for a passing private R0 audit so the assertion
# isolates firing-path enforcement from the separate R0 interim path.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd -P)"
CHECK_SCRIPT="$SCRIPT_DIR/check-ccl-skills.sh"
[ -f "$CHECK_SCRIPT" ] || { echo "FAIL: checker not found: $CHECK_SCRIPT" >&2; exit 1; }
ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd -P)"

TMP="$(mktemp -d "${TMPDIR:-/tmp}/regfiringwire.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

passed=0
fail() { echo "FAIL: $*" >&2; exit 1; }
pass() { passed=$((passed + 1)); echo "PASS: $*"; }

REPO="$TMP/repo"
git clone -q "$ROOT" "$REPO"
git -C "$REPO" config user.email test@example.invalid
git -C "$REPO" config user.name "Test User"
# Give the clone its own base branch and upstream, the same fixture shape the
# sibling register tests use. The checker resolves its diff base from
# `@{upstream}` and falls back to `origin/main`; a clone made while CI has the
# project checked out at a DETACHED HEAD carries neither, so impact-chain fails
# closed with `impact_chain_merge_base_missing: origin/main` and this test would
# red for a reason unrelated to the wiring it asserts. Pinning
# CCL_SKILL_BASE_REF=HEAD instead is NOT equivalent: it makes the
# evidence-card detector's self-test take its no-base branch and fail
# (`no-base clean changed-scope should be degraded`). A real branch with a real
# upstream keeps every other gate on its normal path.
git -C "$REPO" branch -f fixture-base HEAD
git -C "$REPO" switch -q -C fixture-work fixture-base
git -C "$REPO" branch --set-upstream-to=fixture-base fixture-work >/dev/null 2>&1
REGISTER="$REPO/skills/skill-extraction-workflow/references/source-register.md"
[ -f "$REGISTER" ] || fail "cloned register missing: $REGISTER"

# The distributed register starts as a source-neutral template. Add one live,
# repository-local locator to this clone so the wiring test can mutate a real
# anchor without shipping task provenance in the published repository.
printf '%s\n' \
  '| wiring fixture | firing-path: file:README.md#Reusable Agent Skills and host integrations | `updated` | synthetic test |' \
  >> "$REGISTER"
git -C "$REPO" add "$REGISTER"
git -C "$REPO" commit -qm "Add wiring fixture"
git -C "$REPO" branch -f fixture-base HEAD

run_check() {
  set +e
  out="$(env -u CCL_SKILL_BASE_REF ALIAS_AUDIT_CMD='true' bash "$CHECK_SCRIPT" "$REPO" 2>&1)"
  rc=$?
  set -e
}

# Always show the checker's own output when an assertion fails; without this a
# CI red says only "got rc=1" and the actual cause has to be re-derived by hand.
dump() { printf '%s\n' "--- checker output (rc=$rc) ---" "$out" | tail -25 >&2; }

# ── Control: the pristine clone passes and the gate's token is emitted ───────
run_check
[ "$rc" = "0" ] || { dump; fail "pristine clone should pass the checker, got rc=$rc"; }
case "$out" in
  *register_firing_path_resolution_ok*) : ;;
  *) dump; fail "checker did not emit the firing-path gate token — the gate is not wired in" ;;
esac
pass "checker entrypoint runs the firing-path gate on a clean tree"

# ── RED: break a historical anchor; the CHECKER (not just the gate) must fail ─
# Reproduces the observed shape: an anchored rule reworded after its row landed.
anchor_line="$(grep -m1 -o 'firing-path: file:[^|;]*#[^|;]*' "$REGISTER")"
[ -n "$anchor_line" ] || fail "no file: anchor found in the cloned register"
target_rel="${anchor_line#firing-path: file:}"; target_rel="${target_rel%%#*}"
anchor_text="${anchor_line#*#}"
target="$REPO/$target_rel"
[ -f "$target" ] || fail "anchor target missing in clone: $target"
python3 - "$target" "$anchor_text" <<'PY'
import sys
p, anchor = sys.argv[1], sys.argv[2].strip()
s = open(p, encoding="utf-8").read()
assert anchor in s, "fixture precondition failed: anchor not present before mutation"
# Rewrite the anchor's TAIL. Appending would leave the original anchor intact as
# a substring, so the fixture would assert nothing while looking like a mutation.
assert len(anchor) > 12, "anchor too short to mutate safely"
mutated = anchor[:-8] + "ZZQXZZQX"
s2 = s.replace(anchor, mutated, 1)
assert anchor not in s2, "fixture failed to remove the anchor — mutation is a no-op"
open(p, "w", encoding="utf-8").write(s2)
PY
run_check
[ "$rc" != "0" ] || { dump; fail "checker must FAIL when a historical firing-path anchor no longer resolves"; }
case "$out" in
  *register_firing_path_unresolved*) : ;;
  *) dump; fail "checker failed, but not via the firing-path gate (wrong-reason RED)" ;;
esac
pass "reworded historical anchor turns the CHECKER ENTRYPOINT red for the right reason"

# ── RED: rc=0 without the gate's terminal token must NOT read as a pass ──────
# A clean rc has to pair with a clean terminal line. A gate that dies quietly
# after `set -e` is disarmed inside it, or whose token gets reworded, still
# exits 0 — and a bare `ruby "$gate" "$root"` call site cannot tell that apart
# from a real clean run, so the checker certifies a gate that never adjudicated
# anything. The stub reproduces exactly that: exit 0, print nothing.
#
# The call site resolves the gate from the CHECKER's own directory, not from
# $root, so stubbing the clone's copy would be a no-op — the fixture has to
# drive a checker whose sibling scripts dir it owns.
STUB_SCRIPTS="$TMP/stubscripts"
cp -R "$SCRIPT_DIR" "$STUB_SCRIPTS"
STUB_CHECK="$STUB_SCRIPTS/check-ccl-skills.sh"
STUB_GATE="$STUB_SCRIPTS/register-firing-path-resolution.rb"
[ -f "$STUB_GATE" ] || fail "stub scripts dir missing the firing-path gate: $STUB_GATE"
printf '%s\n' '#!/usr/bin/env ruby' 'exit 0' > "$STUB_GATE"

run_stub_check() {
  set +e
  out="$(env -u CCL_SKILL_BASE_REF ALIAS_AUDIT_CMD='true' bash "$STUB_CHECK" "$REPO" 2>&1)"
  rc=$?
  set -e
}

# The clone still carries the r1 anchor mutation from the RED above; restore it
# so this assertion isolates the silent-rc-0 path from the unresolved-anchor one.
git -C "$REPO" checkout -- . >/dev/null 2>&1 || fail "could not restore the clone before the stub case"
run_stub_check
[ "$rc" = "2" ] || { dump; fail "a gate exiting 0 with no terminal token must fail closed as rc=2, got rc=$rc"; }
case "$out" in
  *register_firing_path_terminal_missing*) : ;;
  *) dump; fail "checker rejected the silent gate, but not via the terminal-token contract (wrong-reason RED)" ;;
esac
case "$out" in
  *ccl_skill_check_clean_ok*) dump; fail "a silent gate must never yield a clean-landing token" ;;
  *) : ;;
esac
pass "gate rc=0 without its terminal token fails closed instead of certifying a pass"

# ── RED: a non-git root must not print a clean-landing token ─────────────────
# Every gate above (impact-chain, firing-path resolution, register pending
# status, diff --check) sits inside `if git rev-parse --is-inside-work-tree`.
# On an exported copy / build artifact directory that branch is simply skipped,
# and with nothing marking the skip the run still reaches the clean token — four
# gates silently not run, reported as a clean landing. Skip must never read as
# clean (same honesty shape as the size gate's `*_unevaluated` token).
NONGIT="$TMP/nongit"
mkdir -p "$NONGIT"
git -C "$REPO" archive HEAD | tar -x -C "$NONGIT"
[ -d "$NONGIT/skills" ] || fail "non-git fixture export produced no skills/ tree"
[ ! -e "$NONGIT/.git" ] || fail "non-git fixture is still a git work tree"

set +e
out="$(env -u CCL_SKILL_BASE_REF ALIAS_AUDIT_CMD='true' bash "$CHECK_SCRIPT" "$NONGIT" 2>&1)"
rc=$?
set -e
case "$out" in
  *ccl_skill_check_clean_ok*) dump; fail "a non-git root skips the git-dependent gates — it must not report a clean landing" ;;
  *) : ;;
esac
case "$out" in
  *ccl_skill_check_interim_ok*) : ;;
  *) dump; fail "a non-git root should downgrade to interim, saw neither clean nor interim token" ;;
esac
case "$out" in
  *"not a git work tree"*) : ;;
  *) dump; fail "the interim downgrade must name the skipped git-dependent gates" ;;
esac
pass "non-git root downgrades to interim instead of silently reporting clean"

# ── RED: an export nested INSIDE another checkout is not a clean landing ─────
# `--is-inside-work-tree` answers true for a directory that merely sits under
# some other repository, so a bare inside-work-tree predicate lets the four
# git-dependent gates adjudicate the ENCLOSING repository's state while reading
# this directory's files — the wrong tree, reported clean. $root must be the
# work tree's own top level.
NESTED="$REPO/nested-export-fixture"
mkdir -p "$NESTED"
git -C "$REPO" archive HEAD | tar -x -C "$NESTED"
[ -d "$NESTED/skills" ] || fail "nested fixture export produced no skills/ tree"
[ "$(git -C "$NESTED" rev-parse --is-inside-work-tree 2>/dev/null)" = "true" ] \
  || fail "nested fixture precondition failed: git does not consider it inside a work tree"
[ "$(git -C "$NESTED" rev-parse --show-toplevel 2>/dev/null)" != "$NESTED" ] \
  || fail "nested fixture precondition failed: it IS its own toplevel, so nothing is being tested"

set +e
out="$(env -u CCL_SKILL_BASE_REF ALIAS_AUDIT_CMD='true' bash "$CHECK_SCRIPT" "$NESTED" 2>&1)"
rc=$?
set -e
case "$out" in
  *ccl_skill_check_clean_ok*) dump; fail "an export nested inside another checkout must not report a clean landing" ;;
  *) : ;;
esac
case "$out" in
  *"not a git work tree root"*) : ;;
  *) dump; fail "the nested-export downgrade must name the skipped git-dependent gates" ;;
esac
# "Downgraded" means it reached a SUCCESSFUL interim verdict. Asserting only the
# absence of the clean token would also accept an unrelated hard failure.
[ "$rc" = "0" ] || { dump; fail "the nested-export downgrade must still succeed, got rc=$rc"; }
case "$out" in
  *ccl_skill_check_interim_ok*) : ;;
  *) dump; fail "the nested-export run must end on the interim token, not merely lack the clean one" ;;
esac
pass "export nested inside another checkout downgrades instead of adjudicating the enclosing repo"

# ── RED: a TRUNCATED terminal line is a malfunction, not a pass ──────────────
# The shape a gate crashing mid-print actually produces. An unanchored substring
# check accepts it, which would defeat the terminal-token contract above.
printf '%s\n' '#!/usr/bin/env ruby' \
  'print "register_firing_path_resolution_ok (269 locators resolved"' \
  'exit 0' > "$STUB_GATE"
run_stub_check
[ "$rc" = "2" ] || { dump; fail "a truncated terminal line must fail closed as rc=2, got rc=$rc"; }
assert_out_has_terminal_missing() {
  case "$out" in
    *register_firing_path_terminal_missing*) : ;;
    *) dump; fail "truncated terminal line rejected, but not via the terminal-token contract" ;;
  esac
}
assert_out_has_terminal_missing
pass "truncated gate terminal line fails closed instead of matching as a substring"

# ── RED: bulk output BEFORE a valid token must NOT read as missing ──────────
# The false-RED direction of the contract. Under `pipefail`, a `printf | grep -q`
# form has the writer take SIGPIPE once grep short-circuits, so the pipeline
# reports 141 and a gate that DID emit its token gets rejected as malfunctioning.
# The bulk goes BEFORE the token because the terminal line must stay last — the
# two properties are checked together on purpose, so neither can be satisfied by
# weakening the other. 50k lines is 4,538,890 bytes (measured), well past the
# 64 KiB pipe buffer where SIGPIPE starts.
printf '%s\n' '#!/usr/bin/env ruby' \
  '50_000.times { |i| puts "leading diagnostic line #{i} " + ("x" * 60) }' \
  'puts "register_firing_path_resolution_ok (271 locators resolved)"' \
  'exit 0' > "$STUB_GATE"
run_stub_check
case "$out" in
  *register_firing_path_terminal_missing*) dump; fail "a complete terminal line preceded by bulk output must not be reported as missing (SIGPIPE false RED)" ;;
  *) : ;;
esac
# Assert the SUCCESS, not merely the absence of rc=2: `!= 2` would also accept a
# false red arriving as 1/126/127/141 — including the very SIGPIPE status this
# case exists to rule out.
[ "$rc" = "0" ] || { dump; fail "bulk output preceding a valid terminal line must still pass, got rc=$rc"; }
case "$out" in
  *ccl_skill_check_clean_ok*) : ;;
  *) dump; fail "a valid terminal line plus bulk output must still reach the clean-landing token" ;;
esac
pass "valid terminal line survives bulk preceding output (no pipefail/SIGPIPE false RED)"

# ── RED: a token that is NOT the last line must not certify a clean run ─────
# The shape of a gate that reached its terminal line and then died on a later
# path. An any-line match accepts it; the last-line contract does not.
printf '%s\n' '#!/usr/bin/env ruby' \
  'puts "register_firing_path_resolution_ok (271 locators resolved)"' \
  'puts "post-terminal work continued and produced this"' \
  'exit 0' > "$STUB_GATE"
run_stub_check
[ "$rc" = "2" ] || { dump; fail "a token followed by further stdout must fail closed as rc=2, got rc=$rc"; }
case "$out" in
  *register_firing_path_terminal_missing*) : ;;
  *) dump; fail "non-terminal token rejected, but not via the terminal-token contract" ;;
esac
pass "a token that is not the last stdout line fails closed"

# ── RED: an undiagnosed non-zero rc is infra failure, not a ledger violation ─
# A Ruby syntax error, an uncaught exception, and a silent `exit 1` all arrive
# as rc=1. Forwarding that as rc=1 tells CI "the ledger is wrong" when the truth
# is "the gate did not run" — and leaves no diagnosable cause in the log.
printf '%s\n' '#!/usr/bin/env ruby' 'exit 1' > "$STUB_GATE"
run_stub_check
[ "$rc" = "2" ] || { dump; fail "a silent rc=1 must be re-tiered to rc=2, got rc=$rc"; }
case "$out" in
  *register_firing_path_gate_failed*) : ;;
  *) dump; fail "silent rc=1 rejected, but not via the gate-failure tier" ;;
esac
pass "undiagnosed non-zero rc is re-tiered as gate failure, not a ledger violation"

# GREEN control: a DIAGNOSED rc=1 must still pass through as a rule failure, so
# the re-tiering above cannot be satisfied by mapping every failure to rc=2.
printf '%s\n' '#!/usr/bin/env ruby' \
  'warn "register_firing_path_unresolved: a recorded firing path no longer resolves"' \
  'warn "  fixture-source.md:1: anchor text absent from target: file:demo#anchor"' \
  'exit 1' > "$STUB_GATE"
run_stub_check
[ "$rc" = "1" ] || { dump; fail "a diagnosed ledger violation must stay rc=1, got rc=$rc"; }
pass "diagnosed rc=1 still surfaces as a ledger violation"

# ── RED: failing to create the capture directory is infra, not a violation ──
# The checker cannot run the gate at all if it has nowhere to capture output.
# An unchecked `mktemp` would exit with whatever status it happened to have —
# typically 1, indistinguishable from an adjudicated ledger violation — so CI
# would read "the ledger is wrong" when the truth is "the checker could not
# start". A PATH shim fails only THIS mktemp so the rest of the checker keeps
# its normal path; setting TMPDIR to a bad directory would instead trip an
# earlier, unrelated mktemp and test nothing about this call site.
REAL_MKTEMP="$(command -v mktemp)"
[ -n "$REAL_MKTEMP" ] || fail "mktemp not found; cannot build the shim"
SHIM_DIR="$TMP/shimbin"
mkdir -p "$SHIM_DIR"
{
  echo '#!/usr/bin/env bash'
  echo 'case "$*" in *firingpath*) echo "mktemp: shimmed failure" >&2; exit 1;; esac'
  echo "exec $REAL_MKTEMP \"\$@\""
} > "$SHIM_DIR/mktemp"
chmod +x "$SHIM_DIR/mktemp"
# Confirm the shim actually discriminates before trusting a RED it produces.
PATH="$SHIM_DIR:$PATH" mktemp -d "${TMPDIR:-/tmp}/firingpath.XXXXXX" >/dev/null 2>&1 \
  && fail "shim precondition failed: the firingpath template should have failed"
shim_passthrough="$(PATH="$SHIM_DIR:$PATH" mktemp -d "${TMPDIR:-/tmp}/shimprobe.XXXXXX")" \
  || fail "shim precondition failed: unrelated templates must still succeed"
rm -rf "$shim_passthrough"

# Restore the real gate: this case is about the checker's own capture setup.
cp "$SCRIPT_DIR/register-firing-path-resolution.rb" "$STUB_GATE"
set +e
out="$(env -u CCL_SKILL_BASE_REF ALIAS_AUDIT_CMD='true' PATH="$SHIM_DIR:$PATH" bash "$STUB_CHECK" "$REPO" 2>&1)"
rc=$?
set -e
[ "$rc" = "2" ] || { dump; fail "a failed capture-directory creation must fail closed as rc=2, got rc=$rc"; }
case "$out" in
  *register_firing_path_gate_failed*) : ;;
  *) dump; fail "capture-setup failure rejected, but not via the gate-failure tier" ;;
esac
pass "capture-directory creation failure is reported as infrastructure, not a ledger violation"

# ── RED: the digest-table seam must never yield a clean landing ─────────────
# The injected table exists so a fixture can describe its own synthetic ledger,
# but an injected table can only ever be weaker than the built-in one for the
# real ledger. If the seam were silent, an inherited test environment would
# disable the digest and missing-row layers on a real run and still report a
# clean landing — the exact false-green shape this whole change exists to close.
git -C "$REPO" checkout -- . >/dev/null 2>&1 || fail "could not restore the clone before the seam case"
SEAM_TABLE="$TMP/injected-exempt-digests.json"
printf '{}\n' > "$SEAM_TABLE"
set +e
out="$(env -u CCL_SKILL_BASE_REF ALIAS_AUDIT_CMD='true' \
  REGISTER_FIRING_PATH_EXEMPT_DIGESTS="$SEAM_TABLE" bash "$CHECK_SCRIPT" "$REPO" 2>&1)"
rc=$?
set -e
[ "$rc" = "0" ] || { dump; fail "an injected digest table is a downgrade, not a failure, got rc=$rc"; }
case "$out" in
  *ccl_skill_check_clean_ok*) dump; fail "a run with an injected EXEMPT digest table must not report a clean landing" ;;
  *) : ;;
esac
case "$out" in
  *ccl_skill_check_interim_ok*) : ;;
  *) dump; fail "the injected-table run must end on the interim token" ;;
esac
case "$out" in
  *register_firing_path_exempt_digests_injected*) : ;;
  *) dump; fail "the gate must announce that its waiver-row bindings were replaced" ;;
esac
pass "injected EXEMPT digest table downgrades to interim instead of silently bypassing"

# ── RED: a failure while the cleanup trap is armed must keep its status ─────
# The narrow window between arming the temp-dir cleanup trap and disarming it.
# `rm -rf` succeeds inside the trap and overwrites the pending exit status, so a
# trap that does not save and restore `$?` first converts this block's rc=2 for
# an unreadable capture into rc=0 — a failure reported as success.
CAT_SHIM_DIR="$TMP/catshim"
mkdir -p "$CAT_SHIM_DIR"
REAL_CAT="$(command -v cat)"
[ -n "$REAL_CAT" ] || fail "cat not found; cannot build the shim"
{
  echo '#!/usr/bin/env bash'
  echo 'case "$*" in *firingpath*/out|*firingpath*/err) echo "cat: shimmed failure" >&2; exit 1;; esac'
  echo "exec $REAL_CAT \"\$@\""
} > "$CAT_SHIM_DIR/cat"
chmod +x "$CAT_SHIM_DIR/cat"
PATH="$CAT_SHIM_DIR:$PATH" cat /dev/null >/dev/null 2>&1 \
  || fail "shim precondition failed: unrelated cat invocations must still work"

git -C "$REPO" checkout -- . >/dev/null 2>&1 || fail "could not restore the clone before the trap-status case"
cp "$SCRIPT_DIR/register-firing-path-resolution.rb" "$STUB_GATE"
set +e
out="$(env -u CCL_SKILL_BASE_REF ALIAS_AUDIT_CMD='true' PATH="$CAT_SHIM_DIR:$PATH" \
  bash "$STUB_CHECK" "$REPO" 2>&1)"
rc=$?
set -e
[ "$rc" = "2" ] || { dump; fail "an unreadable capture must keep its rc=2 through the cleanup trap, got rc=$rc"; }
case "$out" in
  *register_firing_path_gate_failed*) : ;;
  *) dump; fail "capture read failure rejected, but not via the gate-failure tier" ;;
esac
pass "a failure inside the cleanup-trap window keeps its exit status"

[ "$passed" -eq 16 ] || fail "expected 16 assertions, saw $passed"
echo "register_firing_path_wiring_tests_ok ($passed assertions)"
