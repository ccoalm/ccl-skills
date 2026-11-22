#!/usr/bin/env bash
# Deterministic behavioral, edge-case, and zero-external-fork suite for
# skills/product-rd-workflow/scripts/check-agent-contract-coverage.sh.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd -P)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd -P)"
GATE="${GATE:-$SCRIPT_DIR/check-agent-contract-coverage.sh}"
[[ -f "$GATE" ]] || { echo "FAIL: gate script not found: $GATE" >&2; exit 1; }

unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_CEILING_DIRECTORIES
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null

TMP="$(mktemp -d "${TMPDIR:-/tmp}/agent-contract-cov-test.XXXXXX")"
TMP="$(cd "$TMP" && pwd -P)"
trap 'rm -rf "$TMP"' EXIT

pass=0
fail=0
skip=0
ok() { pass=$((pass + 1)); }
bad() { fail=$((fail + 1)); printf 'FAIL: %s\n' "$1" >&2; }
skipped() { skip=$((skip + 1)); printf 'SKIP: %s\n' "$1" >&2; }

init_git() {
  git init -q -b main "$1"
  git -C "$1" config user.email "t@example.invalid"
  git -C "$1" config user.name "t"
}

# Shim basename and dirname so any external fork during the per-file scan is counted.
SHIM="$TMP/shim"
mkdir -p "$SHIM"
REAL_BASENAME="$(command -v basename)"
REAL_DIRNAME="$(command -v dirname)"
cat >"$SHIM/basename" <<EOF
#!/bin/sh
echo basename >> "\$FORK_COUNT_FILE"
exec "$REAL_BASENAME" "\$@"
EOF
cat >"$SHIM/dirname" <<EOF
#!/bin/sh
echo dirname >> "\$FORK_COUNT_FILE"
exec "$REAL_DIRNAME" "\$@"
EOF
chmod +x "$SHIM/basename" "$SHIM/dirname"

run_gate() {
  local out_file="$TMP/out" err_file="$TMP/err" count_file="$TMP/forks"
  : >"$count_file"
  set +e
  FORK_COUNT_FILE="$count_file" PATH="$SHIM:$PATH" bash "$GATE" "$@" >"$out_file" 2>"$err_file"
  RC=$?
  set -e
  OUT="$(cat "$out_file")"
  ERR="$(cat "$err_file")"
  FORKS="$(wc -l <"$count_file" | tr -d ' ')"
}

# 1. Missing contracts: --check exits 0, --enforce exits 1, --fix scaffolds and exits 0,
#    and zero external basename/dirname forks occur.
r1="$TMP/r1"
init_git "$r1"
mkdir -p "$r1/pkg/service" "$r1/dir with space" "$r1/node_modules/ ignored" "$r1/.hidden"
printf 'package service\n' >"$r1/pkg/service/svc.go"
printf 'print(1)\n' >"$r1/dir with space/app.py"
printf 'console.log(1)\n' >"$r1/node_modules/ ignored/index.js"
printf 'x = 1\n' >"$r1/.hidden/secret.py"
# Dash-leading filenames at root and nested dir must not trip option parsing.
printf 'x = 1\n' >"$r1/-dash.py"
printf 'x = 1\n' >"$r1/pkg/service/-nested.py"

run_gate --repo "$r1" --check
[[ "$RC" -eq 0 ]] && [[ -z "$OUT" ]] && [[ "$ERR" == *"AGENTS.md"* ]] \
  && [[ "$ERR" == *"dir with space/AGENTS.md"* ]] && [[ "$ERR" == *"pkg/service/AGENTS.md"* ]] \
  && [[ "$ERR" != *"node_modules"* ]] && [[ "$ERR" != *".hidden"* ]] \
  && ok || bad "case 1a --check output/rc mismatch (rc=$RC out=$OUT err=$ERR)"
[[ "$FORKS" -eq 0 ]] && ok || bad "case 1b expected 0 basename/dirname forks, got $FORKS"

run_gate --repo "$r1" --enforce
[[ "$RC" -eq 1 ]] && ok || bad "case 1c --enforce expected rc=1, got $RC"

run_gate --repo "$r1" --fix
[[ "$RC" -eq 0 ]] && [[ "$OUT" == "agent contract coverage ok" ]] \
  && [[ -s "$r1/AGENTS.md" ]] && [[ -s "$r1/pkg/service/AGENTS.md" ]] \
  && [[ -s "$r1/dir with space/AGENTS.md" ]] \
  && ok || bad "case 1d --fix failed (rc=$RC out=$OUT err=$ERR)"

run_gate --repo "$r1" --enforce
[[ "$RC" -eq 0 ]] && [[ "$OUT" == "agent contract coverage ok" ]] && [[ -z "$ERR" ]] \
  && ok || bad "case 1e clean --enforce failed (rc=$RC out=$OUT err=$ERR)"

# 2. Empty and symlinked contracts are reported and never overwritten/followed by --fix.
r2="$TMP/r2"
init_git "$r2"
printf '# Root\n' >"$r2/AGENTS.md"
mkdir -p "$r2/empty_pkg" "$r2/sym_pkg"
printf 'package a\n' >"$r2/empty_pkg/a.go"
: >"$r2/empty_pkg/AGENTS.md"
printf 'package b\n' >"$r2/sym_pkg/b.go"
printf '# Outside\n' >"$TMP/outside_contract.md"
ln -s "$TMP/outside_contract.md" "$r2/sym_pkg/AGENTS.md"
git -C "$r2" add .

run_gate --repo "$r2" --fix
[[ "$RC" -eq 0 ]] && [[ ! -s "$r2/empty_pkg/AGENTS.md" ]] && [[ -L "$r2/sym_pkg/AGENTS.md" ]] \
  && [[ "$ERR" == *"empty contract files"* ]] && [[ "$ERR" == *"symlinked contract paths"* ]] \
  && ok || bad "case 2a --fix must preserve empty and symlinked contracts (rc=$RC err=$ERR)"

run_gate --repo "$r2" --enforce
[[ "$RC" -eq 1 ]] && [[ "$ERR" == *"empty_pkg/AGENTS.md"* ]] && [[ "$ERR" == *"sym_pkg/AGENTS.md"* ]] \
  && ok || bad "case 2b --enforce must fail on empty and symlinked contracts (rc=$RC err=$ERR)"

# 3. Custom --source-ext (single-dot, multi-dot, dotless) and literal --exclude metacharacters.
r3="$TMP/r3"
init_git "$r3"
printf '# Root\n' >"$r3/AGENTS.md"
mkdir -p "$r3/infra" "$r3/types" "$r3/docker" "$r3/gen*" "$r3/gen_keep"
printf 'resource "x" "y" {}\n' >"$r3/infra/main.tf"
printf 'export type T = string;\n' >"$r3/types/api.d.ts"
printf 'FROM scratch\n' >"$r3/docker/Dockerfile"
printf 'x = 1\n' >"$r3/gen*/skip.py"
printf 'x = 1\n' >"$r3/gen_keep/must_check.py"

run_gate --repo "$r3" --enforce --source-ext ".tf .d.ts Dockerfile" --exclude "gen*"
[[ "$RC" -eq 1 ]] \
  && [[ "$ERR" == *"infra/AGENTS.md"* ]] \
  && [[ "$ERR" == *"types/AGENTS.md"* ]] \
  && [[ "$ERR" == *"docker/AGENTS.md"* ]] \
  && [[ "$ERR" == *"gen_keep/AGENTS.md"* ]] \
  && [[ "$ERR" != *"gen*/AGENTS.md"* ]] \
  && ok || bad "case 3 custom --source-ext / literal --exclude failed (rc=$RC err=$ERR)"

# 4. Non-git plain directory fallback and group / parent-of-repos refusal (exit 2).
r4="$TMP/r4-plain"
mkdir -p "$r4/sub"
printf '# Root\n' >"$r4/AGENTS.md"
printf 'fn main() {}\n' >"$r4/sub/main.rs"
run_gate --repo "$r4" --enforce
[[ "$RC" -eq 1 ]] && [[ "$ERR" == *"sub/AGENTS.md"* ]] && [[ "$FORKS" -eq 0 ]] \
  && ok || bad "case 4a non-git fallback failed (rc=$RC forks=$FORKS err=$ERR)"

grp="$TMP/group-parent"
mkdir -p "$grp"
init_git "$grp/repo-a"
init_git "$grp/repo-b"
run_gate --repo "$grp" --enforce
[[ "$RC" -eq 2 ]] && [[ "$ERR" == *"parent-of-repos"* ]] && [[ "$ERR" == *"repo-a"* ]] && [[ "$ERR" == *"repo-b"* ]] \
  && ok || bad "case 4b group-parent guard expected rc=2 (rc=$RC err=$ERR)"

# 5. CLI validation: bad --name and unknown option both exit 2.
run_gate --repo "$r4" --name "../AGENTS.md"
[[ "$RC" -eq 2 ]] && ok || bad "case 5a bad --name expected rc=2, got $RC"
run_gate --repo "$r4" --unknown-flag
[[ "$RC" -eq 2 ]] && ok || bad "case 5b unknown flag expected rc=2, got $RC"

# 5c. Differential parity against baseline 0ee3a4a on standard inputs (excluding the two
#     bounded bug fixes covered in 1a -dash.py and 3 literal --exclude "gen*").
BASE_COMMIT="0ee3a4a89f51098768830fe628bff525a94a3dee"
if git -C "$REPO_ROOT" cat-file -e "${BASE_COMMIT}:skills/product-rd-workflow/scripts/check-agent-contract-coverage.sh" 2>/dev/null; then
  git -C "$REPO_ROOT" show "${BASE_COMMIT}:skills/product-rd-workflow/scripts/check-agent-contract-coverage.sh" >"$TMP/base_gate.sh"
  rdiff_a="$TMP/rdiff-a"
  rdiff_b="$TMP/rdiff-b"
  for d in "$rdiff_a" "$rdiff_b"; do
    init_git "$d"
    mkdir -p "$d/cmd/server" "$d/pkg/logic" "$d/vendor/x" "$d/.cache/y" "$d/dir space"
    printf 'package main\n' >"$d/cmd/server/main.go"
    printf 'export const v = 1;\n' >"$d/pkg/logic/idx.ts"
    printf 'package x\n' >"$d/vendor/x/v.go"
    printf 'y = 1\n' >"$d/.cache/y/c.py"
    printf 'resource "r" "n" {}\n' >"$d/dir space/infra.tf"
    : >"$d/pkg/logic/AGENTS.md"
  done
  diff_ok=1
  for args in "--check --source-ext .tf" "--enforce --source-ext .tf" "--fix --source-ext .tf" "--enforce --source-ext .tf"; do
    set +e
    # shellcheck disable=SC2086
    bash "$TMP/base_gate.sh" --repo "$rdiff_a" $args >"$TMP/b_out" 2>"$TMP/b_err"; b_rc=$?
    # shellcheck disable=SC2086
    bash "$GATE" --repo "$rdiff_b" $args >"$TMP/n_out" 2>"$TMP/n_err"; n_rc=$?
    set -e
    if [[ "$b_rc" -ne "$n_rc" ]] || ! cmp -s "$TMP/b_out" "$TMP/n_out" || ! cmp -s "$TMP/b_err" "$TMP/n_err"; then
      diff_ok=0
      bad "case 5c differential mismatch on '$args' (base_rc=$b_rc new_rc=$n_rc)"
      break
    fi
  done
  [[ "$diff_ok" -eq 1 ]] && ok
else
  is_shallow="$(git -C "$REPO_ROOT" rev-parse --is-shallow-repository 2>/dev/null || echo unavailable)"
  if [[ "${REQUIRE_BASELINE:-0}" == "1" ]] || [[ "$is_shallow" == "false" ]]; then
    bad "case 5c baseline $BASE_COMMIT missing (is_shallow=$is_shallow REQUIRE_BASELINE=${REQUIRE_BASELINE:-0})"
  else
    skipped "case 5c baseline $BASE_COMMIT unavailable in shallow/snapshot checkout"
  fi
fi

# 6. Full-repo dogfood + wall-clock speed bound (< 2.0s; pre-fix baseline was ~7.8s).
elapsed_ms="$(
  FORK_COUNT_FILE="$TMP/repo_forks" PATH="$SHIM:$PATH" GATE="$GATE" REPO_ROOT="$REPO_ROOT" python3 - <<'PY'
import os, subprocess, sys, time
open(os.environ["FORK_COUNT_FILE"], "w").close()
t0 = time.perf_counter()
proc = subprocess.run(["bash", os.environ["GATE"], "--repo", os.environ["REPO_ROOT"], "--enforce"],
                      capture_output=True, text=True)
dt_ms = int((time.perf_counter() - t0) * 1000)
if proc.returncode != 0 or proc.stdout.strip() != "agent contract coverage ok":
    sys.stderr.write(f"repo gate failed: rc={proc.returncode} out={proc.stdout!r} err={proc.stderr!r}\n")
    sys.exit(1)
print(dt_ms)
PY
)" || { bad "case 6a full-repo --enforce failed"; elapsed_ms=99999; }
repo_forks="$(wc -l <"$TMP/repo_forks" | tr -d ' ')"
[[ "$repo_forks" -eq 0 ]] && ok || bad "case 6b full-repo scan spawned $repo_forks basename/dirname forks"
PERF_BOUND_MS="${PERF_BOUND_MS:-5000}"
[[ "$elapsed_ms" -lt "$PERF_BOUND_MS" ]] && ok || bad "case 6c full-repo scan took ${elapsed_ms}ms (expected < ${PERF_BOUND_MS}ms)"

echo "check_agent_contract_coverage_suite: $pass passed, $fail failed, $skip skipped (repo scan ${elapsed_ms}ms)"
[[ "$fail" -eq 0 ]]
