#!/usr/bin/env bash
# Regression suite for check-mr-target-freshness.sh.
#
# Builds real synthetic git repos (a bare "origin" plus a clone) rather than
# stubbing git, so the ahead/behind arithmetic under test is the real thing.
#
# Includes a mutation check on the gate's own precision conjunct: with the
# `ahead -eq 0` test removed, the release-branch case must go RED. A suite that
# only exercises the happy path would keep passing if that conjunct were dropped,
# which is exactly the over-firing this gate is designed to avoid.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd -P)"
GATE="$SCRIPT_DIR/check-mr-target-freshness.sh"
[ -f "$GATE" ] || { echo "FAIL: gate not found: $GATE" >&2; exit 1; }

TMP="$(mktemp -d)"
trap 'rc=$?; set +e; rm -rf "$TMP"; exit $rc' EXIT

fail() { echo "FAIL: $*" >&2; exit 1; }

git_q() { git -c user.name=t -c user.email=t@t -c init.defaultBranch=main "$@" >/dev/null 2>&1; }

# Build: origin/main with N commits; branches derived from it per the case.
# $1 = workdir, $2 = commits on main, $3 = commits added to the side branch
build_repo() {
  local dir="$1" main_commits="$2" side_commits="$3" side="$4" fork_at="$5"
  mkdir -p "$dir/src" && git_q -C "$dir/src" init
  cd "$dir/src"
  for i in $(seq 1 "$fork_at"); do echo "$i" > f.txt; git_q add -A; git_q commit -m "c$i"; done
  git_q branch "$side"
  for i in $(seq $((fork_at + 1)) "$main_commits"); do echo "$i" > f.txt; git_q add -A; git_q commit -m "c$i"; done
  if [ "$side_commits" -gt 0 ]; then
    git_q checkout "$side"
    for i in $(seq 1 "$side_commits"); do echo "s$i" > s.txt; git_q add -A; git_q commit -m "s$i"; done
    git_q checkout main
  fi
  git_q clone --bare . "$dir/origin.git"
  mkdir -p "$dir/work" && git_q clone "$dir/origin.git" "$dir/work"
  cd - >/dev/null
}

# Every gate input is unset FIRST, so a real GitLab job environment cannot leak
# into a case. This bit for real: CI sets CI_MERGE_REQUEST_PROJECT_ID, which
# turned the partial-metadata case into a fork case and reddened the pipeline
# while the suite was green locally.
CLEAN_ENV=(env
  -u CI_MERGE_REQUEST_TARGET_BRANCH_NAME
  -u CI_DEFAULT_BRANCH
  -u CI_MERGE_REQUEST_SOURCE_PROJECT_ID
  -u CI_MERGE_REQUEST_PROJECT_ID
  -u MR_TARGET_FRESHNESS_ALLOW
  -u STALE_BEHIND_MIN
)

run_gate() { # $1=repo work dir, $2=target, rest=env assignments
  local work="$1" target="$2"; shift 2
  "${CLEAN_ENV[@]}" CI_MERGE_REQUEST_TARGET_BRANCH_NAME="$target" CI_DEFAULT_BRANCH=main "$@" \
    bash "$GATE" "$work" 2>&1
}

# --- Case 1: stale mirror (0 ahead, far behind) => BLOCK -------------------
build_repo "$TMP/c1" 60 0 dev 1
set +e
out="$(run_gate "$TMP/c1/work" dev)"; rc=$?
set -e
[ "$rc" -eq 1 ] || fail "stale target should block (got rc=$rc): $out"
case "$out" in *mr_target_freshness_stale*) : ;; *) fail "missing stale token: $out";; esac
case "$out" in *"ahead=0"*"behind=59"*) : ;; *) fail "wrong counts: $out";; esac

# --- Case 2: release branch with its own commits => PASS -------------------
# This is the precision case: it IS behind main, but carries its own work.
build_repo "$TMP/c2" 60 3 release 1
set +e
out="$(run_gate "$TMP/c2/work" release)"; rc=$?
set -e
[ "$rc" -eq 0 ] || fail "release branch with own commits must pass (rc=$rc): $out"
case "$out" in *mr_target_freshness_ok*) : ;; *) fail "missing ok token: $out";; esac

# --- Case 3: target IS the default branch => PASS -------------------------
build_repo "$TMP/c3" 60 0 dev 1
set +e
out="$(run_gate "$TMP/c3/work" main)"; rc=$?
set -e
[ "$rc" -eq 0 ] || fail "default target must pass (rc=$rc): $out"

# --- Case 4: slightly-behind mirror under threshold => PASS ---------------
build_repo "$TMP/c4" 10 0 dev 1
set +e
out="$(run_gate "$TMP/c4/work" dev)"; rc=$?
set -e
[ "$rc" -eq 0 ] || fail "9-behind target under threshold must pass (rc=$rc): $out"

# --- Case 5: threshold is honoured ---------------------------------------
set +e
out="$(run_gate "$TMP/c4/work" dev STALE_BEHIND_MIN=5)"; rc=$?
set -e
[ "$rc" -eq 1 ] || fail "lowered threshold should block (rc=$rc): $out"

# --- Case 6: not an MR pipeline => no-op ---------------------------------
set +e
out="$("${CLEAN_ENV[@]}" CI_DEFAULT_BRANCH=main bash "$GATE" "$TMP/c1/work" 2>&1)"; rc=$?
set -e
[ "$rc" -eq 0 ] || fail "non-MR pipeline must no-op (rc=$rc): $out"
case "$out" in *mr_target_freshness_skipped*) : ;; *) fail "missing skip token: $out";; esac

# --- Case 7: unresolvable target => fail CLOSED --------------------------
# Exiting 0 here would paint the CI job green while the log says "not a pass".
set +e
out="$(run_gate "$TMP/c1/work" no-such-branch)"; rc=$?
set -e
[ "$rc" -eq 1 ] || fail "unresolvable ref must fail closed (rc=$rc): $out"
case "$out" in *mr_target_freshness_unevaluated*) : ;; *) fail "missing unevaluated token: $out";; esac
case "$out" in *"NOT a pass"*) : ;; *) fail "unevaluated must say it is not a pass: $out";; esac

# --- Case 8: threshold boundary is inclusive (behind == threshold) --------
# Without this, flipping -ge to -gt would leave the whole suite green.
build_repo "$TMP/c8" 21 0 dev 1
set +e
out="$(run_gate "$TMP/c8/work" dev STALE_BEHIND_MIN=20)"; rc=$?
set -e
case "$out" in *"behind=20"*) : ;; *) fail "fixture is not exactly at the boundary: $out";; esac
[ "$rc" -eq 1 ] || fail "behind == threshold must block (-ge, not -gt) (rc=$rc): $out"

# --- Case 9: maintainer allowlist exempts a legitimately 0-ahead target ---
set +e
out="$(run_gate "$TMP/c1/work" dev MR_TARGET_FRESHNESS_ALLOW="release-1.2 dev")"; rc=$?
set -e
[ "$rc" -eq 0 ] || fail "allowlisted target must pass (rc=$rc): $out"
case "$out" in *"is in MR_TARGET_FRESHNESS_ALLOW"*) : ;; *) fail "allowlist pass must say why: $out";; esac
# ...and an allowlist that does NOT name this target still blocks.
set +e
out="$(run_gate "$TMP/c1/work" dev MR_TARGET_FRESHNESS_ALLOW="release-1.2 other")"; rc=$?
set -e
[ "$rc" -eq 1 ] || fail "non-matching allowlist must still block (rc=$rc): $out"

# --- Case 10: malformed threshold fails closed, never falls through to ok -
set +e
out="$(run_gate "$TMP/c1/work" dev STALE_BEHIND_MIN=50x)"; rc=$?
set -e
[ "$rc" -eq 1 ] || fail "malformed STALE_BEHIND_MIN must fail closed (rc=$rc): $out"
case "$out" in *mr_target_freshness_misconfigured*) : ;; *) fail "missing misconfigured token: $out";; esac
case "$out" in *mr_target_freshness_ok*) fail "malformed threshold must not reach the ok path: $out";; *) : ;; esac

# --- Case 11: a stale cached origin ref is refreshed, not trusted ---------
# Point origin/dev at an old tip, then let the gate run: it must re-fetch and
# score against the CURRENT topology.
build_repo "$TMP/c11" 60 2 dev 1
old_tip="$(git -C "$TMP/c11/work" rev-parse origin/dev)"
git_q -C "$TMP/c11/src" checkout dev
git_q -C "$TMP/c11/src" reset --hard HEAD~2      # dev loses its own commits upstream
git_q -C "$TMP/c11/src" push -f "$TMP/c11/origin.git" dev
git_q -C "$TMP/c11/work" update-ref refs/remotes/origin/dev "$old_tip"   # stale cache
set +e
out="$(run_gate "$TMP/c11/work" dev)"; rc=$?
set -e
[ "$rc" -eq 1 ] || fail "gate must re-fetch and see the CURRENT tip, not the cached one (rc=$rc): $out"
case "$out" in *"ahead=0"*) : ;; *) fail "stale cached ref was used for the count: $out";; esac

# --- Case 12: oversized digit-only threshold fails closed ----------------
# Digits alone are not enough: a value wider than a machine integer makes `-ge`
# abort with "integer expected", which set -e does not catch inside an `if`.
set +e
out="$(run_gate "$TMP/c1/work" dev STALE_BEHIND_MIN=999999999999999999999999999999999999)"; rc=$?
set -e
[ "$rc" -eq 1 ] || fail "oversized threshold must fail closed (rc=$rc): $out"
case "$out" in *mr_target_freshness_misconfigured*) : ;; *) fail "missing misconfigured token: $out";; esac
case "$out" in *mr_target_freshness_ok*) fail "oversized threshold reached the ok path: $out";; *) : ;; esac

# --- Case 13: undetermined default branch fails closed -------------------
# Guessing "main" would compare against a branch that may not be the default.
set +e
(cd "$TMP/c1/work" && git remote set-head origin --delete >/dev/null 2>&1) || true
out="$("${CLEAN_ENV[@]}" CI_MERGE_REQUEST_TARGET_BRANCH_NAME=dev bash "$GATE" "$TMP/c1/work" 2>&1)"; rc=$?
set -e
[ "$rc" -eq 1 ] || fail "undetermined default branch must fail closed (rc=$rc): $out"
case "$out" in *"default branch is undetermined"*) : ;; *) fail "missing undetermined-default message: $out";; esac

# --- Case 14: fork MR fails closed rather than measuring the fork --------
set +e
out="$(run_gate "$TMP/c1/work" dev CI_MERGE_REQUEST_SOURCE_PROJECT_ID=99 CI_MERGE_REQUEST_PROJECT_ID=1)"; rc=$?
set -e
[ "$rc" -eq 1 ] || fail "fork MR must fail closed (rc=$rc): $out"
case "$out" in *"fork merge request"*) : ;; *) fail "missing fork message: $out";; esac
# Same project ids => normal evaluation, not the fork path.
set +e
out="$(run_gate "$TMP/c2/work" release CI_MERGE_REQUEST_SOURCE_PROJECT_ID=1 CI_MERGE_REQUEST_PROJECT_ID=1)"; rc=$?
set -e
[ "$rc" -eq 0 ] || fail "same-project MR must evaluate normally (rc=$rc): $out"

# --- Case 15: allowlist is matched literally, not as a glob --------------
# The gate cd's into the repo, so `*` would expand against THAT directory. A
# file literally named after the target is what makes this case bite: without
# `set -f`, `*` expands to include `dev`, matches, and wrongly exempts it.
: > "$TMP/c1/work/dev"
set +e
out="$("${CLEAN_ENV[@]}" CI_MERGE_REQUEST_TARGET_BRANCH_NAME=dev CI_DEFAULT_BRANCH=main \
  MR_TARGET_FRESHNESS_ALLOW='*' bash "$GATE" "$TMP/c1/work" 2>&1)"; rc=$?
set -e
[ "$rc" -eq 1 ] || fail "a glob in the allowlist must not match the target by filename (rc=$rc): $out"
case "$out" in *"is in MR_TARGET_FRESHNESS_ALLOW"*) fail "glob was expanded into an allowlist match: $out";; *) : ;; esac
rm -f "$TMP/c1/work/dev"

# --- Case 16: the digit bound is exactly 9 -------------------------------
# 10 digits must be refused; 9 must be accepted. Without both halves, moving
# the bound to 10 would leave the suite green.
set +e
out="$(run_gate "$TMP/c1/work" dev STALE_BEHIND_MIN=1234567890)"; rc=$?   # 10 digits
set -e
[ "$rc" -eq 1 ] || fail "a 10-digit threshold must be refused (rc=$rc): $out"
case "$out" in *mr_target_freshness_misconfigured*) : ;; *) fail "10-digit refusal must use the misconfigured token: $out";; esac
set +e
out="$(run_gate "$TMP/c1/work" dev STALE_BEHIND_MIN=123456789)"; rc=$?    # 9 digits
set -e
case "$out" in *mr_target_freshness_misconfigured*) fail "a 9-digit threshold must be accepted: $out";; *) : ;; esac
[ "$rc" -eq 0 ] || fail "9-digit threshold is valid and 59 < it, so the gate should pass (rc=$rc): $out"

# --- Case 17: partial MR project metadata fails closed -------------------
set +e
out="$(run_gate "$TMP/c1/work" dev CI_MERGE_REQUEST_SOURCE_PROJECT_ID=7)"; rc=$?
set -e
[ "$rc" -eq 1 ] || fail "source project id without target id must fail closed (rc=$rc): $out"
case "$out" in *"incomplete merge-request project metadata"*) : ;; *) fail "missing partial-metadata message: $out";; esac
set +e
out="$(run_gate "$TMP/c1/work" dev CI_MERGE_REQUEST_PROJECT_ID=7)"; rc=$?
set -e
[ "$rc" -eq 1 ] || fail "target project id without source id must fail closed (rc=$rc): $out"

# --- Case 18: both refs are fetched in ONE git invocation ----------------
# A `git` shim on PATH records each invocation; two sequential fetches can
# observe two different moments, so the combined refspec is the contract.
shim="$TMP/shimbin"; mkdir -p "$shim"
cat > "$shim/git" <<'SHIM'
#!/usr/bin/env bash
for a in "$@"; do [ "$a" = "fetch" ] && { echo "fetch $*" >> "$GIT_SHIM_LOG"; break; }; done
exec /usr/bin/env -u PATH_SHIM "$REAL_GIT" "$@"
SHIM
chmod +x "$shim/git"
: > "$TMP/fetch.log"
set +e
out="$("${CLEAN_ENV[@]}" PATH="$shim:$PATH" REAL_GIT="$(command -v git)" GIT_SHIM_LOG="$TMP/fetch.log" \
  CI_MERGE_REQUEST_TARGET_BRANCH_NAME=dev CI_DEFAULT_BRANCH=main bash "$GATE" "$TMP/c1/work" 2>&1)"; rc=$?
set -e
fetches="$(grep -c '^fetch' "$TMP/fetch.log" || true)"
[ "$fetches" -eq 1 ] || fail "expected exactly one git fetch invocation, got $fetches"
grep -q 'refs/heads/dev' "$TMP/fetch.log" || fail "combined fetch is missing the target refspec"
grep -q 'refs/heads/main' "$TMP/fetch.log" || fail "combined fetch is missing the default refspec"


# --- Mutation: drop the 0-ahead conjunct => case 2 must go RED ------------
mutant="$TMP/mutant.sh"
sed 's/if \[ "\$ahead" -eq 0 \] && \[ "\$behind" -ge "\$stale_behind_min" \]; then/if [ "$behind" -ge "$stale_behind_min" ]; then/' "$GATE" > "$mutant"
grep -q 'if \[ "\$behind" -ge "\$stale_behind_min" \]; then' "$mutant" \
  || fail "mutation did not apply — the suite would not be testing the precision conjunct"
set +e
out="$("${CLEAN_ENV[@]}" CI_MERGE_REQUEST_TARGET_BRANCH_NAME=release CI_DEFAULT_BRANCH=main bash "$mutant" "$TMP/c2/work" 2>&1)"; rc=$?
set -e
[ "$rc" -eq 1 ] || fail "mutation check is blind: dropping the 0-ahead conjunct must make the release case block (rc=$rc)"
case "$out" in *mr_target_freshness_stale*) : ;; *) fail "mutant blocked for the wrong reason: $out";; esac

echo "test_check_mr_target_freshness: ok"
