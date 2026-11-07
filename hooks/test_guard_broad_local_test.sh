#!/usr/bin/env bash
# Behavior matrix for hooks/guard-broad-local-test.sh. Requires jq, because the
# hook degrades to allowing every command without it and a suite that ran that
# way would pass while proving nothing.
#
# Each row runs the hook on a command and states whether it must deny. Allowed
# rows sit beside denied rows that share their shape, so a tightening that
# over-fires turns a row red instead of shipping.
set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd -P)"
HOOK="${BROAD_TEST_HOOK:-$SCRIPT_DIR/guard-broad-local-test.sh}"
[ -f "$HOOK" ] || { echo "FAIL: hook not found: $HOOK" >&2; exit 1; }
command -v jq >/dev/null 2>&1 || { echo "FAIL: jq required for this suite" >&2; exit 1; }
bash -n "$HOOK" || { echo "FAIL: hook is not syntactically valid" >&2; exit 1; }

pass=0; fail=0
ERR=$(mktemp "${TMPDIR:-/tmp}/broad-test-suite-XXXXXX") || exit 1
trap 'rm -f "$ERR"' EXIT INT TERM

check() { # check <deny|allow> <command> [tool_name]
  local want="$1" cmd="$2" tool="${3:-Bash}" out rc got
  out=$(jq -nc --arg c "$cmd" --arg t "$tool" '{tool_name:$t,tool_input:{command:$c}}' \
    | bash "$HOOK" 2>"$ERR"); rc=$?
  if [ "$rc" -ne 0 ] || [ -s "$ERR" ]; then
    fail=$((fail+1)); printf 'FAIL  [exit=%s or stderr]  %s\n' "$rc" "$cmd" >&2; return
  fi
  got=allow
  if [ -n "$out" ]; then
    if [ "$(printf '%s' "$out" | jq -r '.hookSpecificOutput.permissionDecision')" = deny ] \
       && printf '%s' "$out" | jq -e '.hookSpecificOutput.permissionDecisionReason | test("CCL_BROAD_TEST_REASON=user-request")' >/dev/null; then
      got=deny
    else
      got=malformed
    fi
  fi
  if [ "$got" = "$want" ]; then pass=$((pass+1)); else
    fail=$((fail+1)); printf 'FAIL  [want %s, got %s]  %s\n' "$want" "$got" "$cmd" >&2
  fi
}

# Whole suites, across the stacks the guard covers.
check deny 'make test-scenario'
check deny 'make test-integration'
check deny 'make test'
check deny 'make -j4 test-e2e'
check deny 'GOLANGCI_LINT=/tmp/x make test-scenario'
check deny 'npm test'
check deny 'npm run test'
check deny 'npm run test:integration'
check deny 'npm --prefix app test'
check deny 'pnpm test'
check deny 'pnpm run test:e2e'
check deny 'yarn test'
check deny 'bun test'
check deny 'pytest'
check deny 'pytest -q'
check deny 'python -m pytest'
check deny 'uv run pytest -q'
check deny 'timeout 600 pytest'
check deny 'npx playwright test'
check deny 'node --test'
check deny 'node --test test/**/*.test.ts'
check deny 'go test ./...'
check deny 'go test -race -count=1 ./...'
check deny 'go test -tags scenario ./test/scenario/...'
check deny 'cd service && make test-scenario'
check deny 'make check; make test-scenario'

# A selector, file or package narrows the same runner.
check allow 'make test-scenario RUN=TestAnswers'
check allow 'make test-scenario FULL=1'
check allow 'go test -run TestX ./...'
check allow 'go test -run=TestX ./test/scenario/...'
check allow 'go test ./internal/card/...'
check allow 'go test ./internal/card'
check allow 'pytest -k billing'
check allow 'pytest tests/unit/test_card.py'
check allow 'pytest tests/unit'
check allow 'pytest tests/test_card.py::test_one'
check allow 'npm test -- test/unit/card.test.ts'
check allow 'npm run test:integration -- --test-name-pattern card'
check allow 'node --test test/unit/card.test.ts'
check allow 'npx playwright test e2e/login.spec.ts'
check allow 'npx playwright test --grep login'
check allow 'pnpm test -t card'
check allow 'pnpm -s test src/legacyHandoff'
check allow 'npm test -- card'
check deny  'npm test > test.log 2>&1'
check deny  'pnpm test 2>&1 | tail -20'
check deny  'pnpm test && git push'
check allow 'npx playwright test login'
check allow 'pytest src/widget'
check allow 'pytest -x src/widget/test_card.py'
check allow 'node --test smoke.js'
check deny  'pytest --tb short'
check deny  'node --test --test-reporter spec'
check allow 'pytest --tb short tests/unit/test_card.py'
# Accepted residual, pinned: a Playwright option value reads as a name filter.
check allow 'npx playwright test --reporter line'
check deny  'npm test > tests/output.log'
check deny  'npm test 2>&1 >tests/out.log'
check allow 'make -C tests check'
check deny  'make -C service test-scenario'
check allow 'npm install integration'
check deny  'npm --prefix app run test:e2e'
check deny  'npm run -s test:integration > out.log 2>&1'
check deny  'pnpm run --silent test:e2e'
check deny  'npm run test:integration -- --test-reporter=tap'
check allow 'npm run -s test:integration -- test/integration/card.test.ts'

# Stated exceptions pass; anything else in that slot does not.
check allow 'CCL_BROAD_TEST_REASON=user-request make test-scenario'
check allow 'CCL_BROAD_TEST_REASON=ci-failure npm test'
check allow 'CCL_BROAD_TEST_REASON=repo-wide pytest'
check allow 'CCL_BROAD_TEST_REASON=repo-required npm test'
check deny  'CCL_BROAD_TEST_REASON= make test-scenario'
check deny  'CCL_BROAD_TEST_REASON=because make test-scenario'
check deny  'FULL=0 pytest'
check deny  'make test-scenario FULL=false'

# Reading about tests is not running them.
check allow 'go test -list . ./...'
check allow 'pytest --collect-only'
check allow 'pytest --help'
check allow 'make -n test-scenario'

# Repository lanes and named subsets stay the repository's call.
check allow 'make check'
check allow 'make test-fast'
check allow 'make test-repo-gates'
check allow 'npm run verify'
check allow 'npm run test:unit'
check allow 'npm run test:contract'
check allow 'npm install'
check allow 'make build'

# Mentions are not runs.
check allow 'git commit -m "run make test-scenario and npm test"'
check allow 'git commit -m "fixed; npm test passes"'
check allow 'echo "\"; npm test; \""'
check allow 'git commit -m "summary
npm test
"'
check allow "git commit -m 'summary
make test-scenario
'"
check allow 'git commit -m "summary
pytest
"'
check allow "git commit -m 'summary
pytest
'"
check allow "git commit -F - <<'MSG'
Keep long suites off the local default

make test-integration and make test-scenario now need RUN
MSG"
# Accepted residual, pinned so it stays deliberate: nothing after a heredoc is checked.
check allow "cat > notes.txt <<'EOF'
EOF
make test-scenario"

check allow 'grep -n pytest pyproject.toml'
check allow 'cat pytest.ini'
check allow 'pip install pytest'
check allow 'which pytest'
check allow 'echo go test ./...'
check allow 'ls test/scenario'
check allow 'pytest-cov --version'

# Only the Bash tool is in scope, and an empty payload is not a failure.
check allow 'make test-scenario' Edit
out=$(printf '{}' | bash "$HOOK" 2>"$ERR"); rc=$?
if [ "$rc" -eq 0 ] && [ -z "$out" ] && [ ! -s "$ERR" ]; then pass=$((pass+1)); else
  fail=$((fail+1)); echo 'FAIL  empty payload must stay silent' >&2; fi

# Without jq the hook allows, so a missing tool cannot block a repository's tests.
NOJQ=$(mktemp -d "${TMPDIR:-/tmp}/broad-test-nojq-XXXXXX") || exit 1
for t in bash head sed grep tr; do ln -s "$(command -v "$t")" "$NOJQ/$t"; done
out=$(printf '{"tool_input":{"command":"make test-scenario"}}' | PATH="$NOJQ" bash "$HOOK" 2>"$ERR"); rc=$?
rm -rf "$NOJQ"
if [ "$rc" -eq 0 ] && [ -z "$out" ] && [ ! -s "$ERR" ]; then pass=$((pass+1)); else
  fail=$((fail+1)); echo 'FAIL  missing jq must allow' >&2; fi

# The same holds for any other tool the scan uses: here jq works and tr is gone.
NOTR=$(mktemp -d "${TMPDIR:-/tmp}/broad-test-notr-XXXXXX") || exit 1
for t in bash head sed grep awk jq; do ln -s "$(command -v "$t")" "$NOTR/$t"; done
out=$(printf '{"tool_input":{"command":"make test-scenario"}}' | PATH="$NOTR" bash "$HOOK" 2>"$ERR"); rc=$?
rm -rf "$NOTR"
if [ "$rc" -eq 0 ] && [ -z "$out" ] && [ ! -s "$ERR" ]; then pass=$((pass+1)); else
  fail=$((fail+1)); echo 'FAIL  missing tr must allow' >&2; fi

# A tool that is present but fails mid-scan must allow too.
BADTR=$(mktemp -d "${TMPDIR:-/tmp}/broad-test-badtr-XXXXXX") || exit 1
for t in bash head sed grep awk jq; do ln -s "$(command -v "$t")" "$BADTR/$t"; done
printf '#!/bin/sh\nexit 1\n' > "$BADTR/tr"; chmod +x "$BADTR/tr"
out=$(printf '{"tool_input":{"command":"npm test"}}' | PATH="$BADTR" bash "$HOOK" 2>"$ERR"); rc=$?
rm -rf "$BADTR"
if [ "$rc" -eq 0 ] && [ -z "$out" ] && [ ! -s "$ERR" ]; then pass=$((pass+1)); else
  fail=$((fail+1)); echo 'FAIL  failing tr must allow' >&2; fi

# A failure early in the file-selector pipeline must allow, not read as "no
# selector". This grep fails only for the -Ev stage and is real grep otherwise.
BADGREP=$(mktemp -d "${TMPDIR:-/tmp}/broad-test-badgrep-XXXXXX") || exit 1
for t in bash head sed awk jq tr; do ln -s "$(command -v "$t")" "$BADGREP/$t"; done
printf '#!/bin/sh\n[ "$1" = -Ev ] && { while read -r _; do :; done; exit 2; }\nexec %s "$@"\n' "$(command -v grep)" > "$BADGREP/grep"
chmod +x "$BADGREP/grep"
out=$(jq -nc '{tool_input:{command:"npm test -- --runInBand tests/unit/card.test.js"}}' | PATH="$BADGREP" bash "$HOOK" 2>"$ERR"); rc=$?
rm -rf "$BADGREP"
if [ "$rc" -eq 0 ] && [ -z "$out" ] && [ ! -s "$ERR" ]; then pass=$((pass+1)); else
  fail=$((fail+1)); echo 'FAIL  failing grep stage must allow' >&2; fi

printf 'guard-broad-local-test: %s passed, %s failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ] || exit 1
echo guard_broad_local_test_ok
