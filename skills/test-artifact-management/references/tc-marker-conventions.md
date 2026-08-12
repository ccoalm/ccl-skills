# TC Marker Conventions

Tests link to Bitable TC IDs via a tiny per-stack helper. Each call appends one
JSON line to `test/results/tc-map.jsonl`; `gen_report.py` joins JUnit XML against
that sidecar by test name.

The function name stays clean — TC linking is metadata, not coupling.

## Sidecar format

`test/results/tc-map.jsonl` — line-delimited JSON, append-only, one entry per
`tc(...)` call:

```jsonl
{"test": "tests/test_auth.py::test_login_success", "tc_ids": ["TC-SY-001"]}
{"test": "tests/test_auth.py::test_bulk_import", "tc_ids": ["TC-SY-001", "TC-SY-002"]}
{"test": "TestLoginSuccess", "tc_ids": ["TC-SY-001"]}
```

Truncate before each test run (the Makefile template does this automatically).
Stale entries from deleted tests must not survive a clean run.

## Test-name conventions per stack

Each helper writes a sidecar key that survives collisions across files/packages
by prefixing the file (or package, for Go) path.

| Stack | Sidecar key the helper writes | Matching JUnit attrs |
|---|---|---|
| pytest | nodeid from `PYTEST_CURRENT_TEST` (e.g. `tests/test_auth.py::test_login`) | `classname="tests.test_auth"` `name="test_login"` |
| Go (`go test`) | `<package-path>::<t.Name()>` via `runtime.FuncForPC` (e.g. `github.com/foo/pkg::TestLogin` or `…::TestParent/sub`) | `classname="<package path>"` `name="TestLogin"` |
| Vitest / Jest | `<file relative to cwd>::<full nested name>` via Error.stack (e.g. `test/auth.test.ts::Auth > login success`) | `classname="<file>"` `name="<full nested name>"` |
| Dart / Flutter | `<file relative to cwd>::<description>` via StackTrace.current (e.g. `test/auth_test.dart::login success`) | varies by reporter |

`gen_report.py` builds candidate keys for each JUnit `<testcase>` (`name`,
`classname::name`, `classname.name`, etc.) and looks them up in the sidecar.
Multiple sidecar entries for the same key are MERGED (union of TC IDs) — so the
marker form and the in-body form may register the same test without losing IDs
from either. Tests not registered at all are silently excluded from Bitable sync.

### Strict mode (recommended in CI)

By default, sidecar write failures (permissions, full disk, read-only mount)
are best-effort — the test still passes, but the TC mapping is missing, so
Bitable goes stale while CI reports green. Set `TC_SIDECAR_STRICT=1` so the
helper fails the test on a write error instead:

```bash
# In CI environment / Makefile / GitLab job:
export TC_SIDECAR_STRICT=1
```

All four helpers honor this env var. Recommended for CI; leave off locally so
a developer's permission/disk hiccup doesn't fail their inner-loop tests.

## Per-stack install

### Python (pytest)

1. Copy `tc.py` from `tc_helpers/` into the project (e.g. `<project>/test/tc.py`).
2. Make it importable AND load it as a pytest plugin. In `pyproject.toml`:

   ```toml
   [tool.pytest.ini_options]
   pythonpath = ["test"]
   addopts = ["-p", "tc"]
   ```

   or in `pytest.ini`:

   ```ini
   [pytest]
   pythonpath = test
   addopts = -p tc
   ```

   (The `-p tc` makes pytest load the plugin so the `@pytest.mark.tc` marker
   and collection-time sidecar write work.)

3. Use the `@pytest.mark.tc(...)` marker:

   ```python
   import pytest

   @pytest.mark.tc("TC-SY-001")
   def test_login_success():
       # ... assertions

   @pytest.mark.tc("TC-SY-002")
   @pytest.mark.skipif(sys.platform != "linux", reason="requires linux")
   def test_env_only():
       # body never runs on non-linux, but TC-SY-002 still maps to 阻塞
       # via reason-keyword heuristic ("requires") in gen_report.py

   @pytest.mark.tc("TC-SY-003", "TC-SY-004")
   def test_bulk_import_partial_failure():
       # ... assertions
   ```

   The plugin reads markers at collection time and writes the sidecar BEFORE
   any test body runs — so `@skip`, `@skipif`, `xfail`, and fixture-failure
   cases all register correctly.

4. For TC IDs computed at runtime (rare — property-based tests, etc.):

   ```python
   from tc import tc
   def test_dynamic():
       tc(decide_tc_id())
       # ... assertions
   ```

   Only useful when the ID isn't knowable at collection time. Reaches the
   sidecar only when the body actually runs; skipped tests are NOT registered
   via this form.

### Go

1. Copy `tc.go` from `tc_helpers/` into a shared test-only package, e.g.
   `internal/testkit/tc/tc.go` (or `gopkg/testkit/tc/tc.go`).
2. **`tc.Mark` must be the first non-comment line in the test, BEFORE any
   `t.Skip` / `t.Skipf` / setup that may call `t.Fatal`** — otherwise the
   sidecar entry isn't written for skipped tests.

   ```go
   import "<your-module>/internal/testkit/tc"

   func TestLoginSuccess(t *testing.T) {
       tc.Mark(t, "TC-SY-001")        // first
       // ... assertions
   }

   func TestEnvOnly(t *testing.T) {
       tc.Mark(t, "TC-SY-002")        // ← BEFORE t.Skip
       if runtime.GOOS != "linux" {
           t.Skip("requires linux")
       }
       // ... body
   }

   func TestBulkImportPartialFailure(t *testing.T) {
       tc.Mark(t, "TC-SY-001", "TC-SY-002")
       // ... assertions
   }
   ```

`Mark` is safe under `t.Parallel()`. No `TestMain` needed; each call appends.

**Wrapping `Mark` in a project helper:** the package-path detection reads the
caller's PC, so a naïve wrapper like `func Smoke(t, ids){ Mark(t, ids...) }`
would record `<wrapper-pkg>::<test>` instead of `<test-pkg>::<test>` and never
join JUnit. Use `tc.MarkAt(t, extraSkip, ids...)` and tell it how many frames
sit between MarkAt and the user's test:

```go
// Single-level wrapper:
func Smoke(t *testing.T, ids ...string) {
    t.Helper()
    tc.MarkAt(t, 1, ids...)   // skip Smoke → user test
}
```

If `extraSkip` is wrong, the resolved function will not contain a
`Test*`/`Benchmark*`/`Example*`/`Fuzz*` segment; the helper warns via
`t.Logf` (visible only with `go test -v`) and — under `TC_SIDECAR_STRICT=1`
— fails the test with `t.Fatalf`. **CI templates set `TC_SIDECAR_STRICT=1`
so misattribution fails the build there**; locally, run with `-v` to see
the warning before pushing.

### Vitest / Jest

1. Copy `tc.ts` from `tc_helpers/` into the project, e.g. `test/tc.ts`.
2. **Wrapper form (preferred — required for `test.skip` / `skipIf` / `todo`):**

   ```typescript
   import { test, describe } from 'vitest'              // or '@jest/globals' for Jest
   import { createTcSuite } from './tc'
   const { tcTest, tcDescribe } = createTcSuite(test, describe)

   tcDescribe('Auth', () => {
     tcTest('TC-SY-001', 'login success', () => {
       expect(...).toBe(...)
     })

     tcTest(['TC-SY-001', 'TC-SY-002'], 'bulk import', () => { /* ... */ })

     // Skipped tests still register their TC IDs because tcTest writes the
     // sidecar at registration time, BEFORE the runner decides to skip.
     tcTest.skip('TC-SY-003', 'wip feature', () => { /* never runs */ })
     tcTest.skipIf(!process.env.LIVE)('TC-SY-004', 'live only', () => { /* ... */ })
     tcTest.todo('TC-SY-006', 'pending')

     tcDescribe('nested', () => {
       tcTest('TC-SY-008', 'deep test', () => { /* ... */ })
     })
   })

   // Top-level (no surrounding describe) also works
   tcTest('TC-SY-007', 'standalone', () => { /* ... */ })
   ```

   **Use `tcDescribe` (not plain `describe`) so the helper can build the full
   nested path** ("Auth > nested > deep test"). Vitest emits this exact string
   in JUnit `<testcase name>`, so sidecar key = JUnit name → exact match.

**`.each` limitations**:
- Only the array-table form `tcTest.each(table)(ids, name, fn)` is supported.
  Vitest 1.6+ tagged-template form (`tcTest.each\`a | b\n${1} | ${2}\``) is NOT
  wrapped — use the array form for parameterised tests, or fall back to plain
  `test.each` + in-body `tc(...)` (skipped rows won't register that way).
- Name template substitution covers the common cases: printf-style `%s` `%d`
  `%i` `%f` `%j` `%o` `%#`, and object-row `$key` (missing key → literal
  `"undefined"` matching Vitest/Jest output). NOT covered: positional `$0`
  (array-row index), nested `$a.b`, and `%$` — if your name template uses
  these advanced forms, sidecar keys may diverge from JUnit names; register
  each row individually with plain `tcTest(...)`.

3. For TC IDs computed at runtime (rare — derived from test input):

   ```typescript
   import { test, expect } from 'vitest'
   import { tc } from './tc'

   test('login success', () => {
     tc(decideTcId())
     expect(...).toBe(...)
   })
   ```

   Only useful when the ID isn't knowable at registration time. Reaches the
   sidecar only when the body actually runs; skipped tests are NOT registered
   via this form.

### Dart / Flutter

`test()` does not expose the current test name inside the body, so the helper
wraps `test()` and records by description at registration time — **this means
skipped tests register correctly by design** (no extra setup needed).

1. Copy `tc.dart` from `tc_helpers/` into the project, e.g. `test/tc.dart`.
2. In test files:

   ```dart
   import 'tc.dart';

   void main() {
     tcTest(['TC-SY-001'], 'login success', () {
       // ... assertions
     });

     tcTest(['TC-SY-001', 'TC-SY-002'], 'bulk import partial failure', () {
       // ... assertions
     });

     // Skipped tests still register — the wrapper writes sidecar before
     // dart-test evaluates the skip parameter.
     tcTest(['TC-SY-003'], 'wip feature', () {
       // never runs
     }, skip: 'wip');
   }
   ```

For Flutter widget tests, uncomment the `tcTestWidgets` block in `tc.dart`
(it requires `package:flutter_test/flutter_test.dart`).

## Multi-TC tests

Pass all relevant TC IDs in a single call:

```python
def test_bulk_import_partial_failure():
    tc("TC-SY-001", "TC-SY-002", "TC-SY-003")
```

The report fans out the test's status to each TC ID; if the test fails,
all linked TCs become `失败`. If multiple tests cover the same TC, the
merge is pessimistic (`失败 > 阻塞 > 跳过 > 通过`).

## CI

- The Makefile `test` target truncates `test/results/tc-map.jsonl` before
  each run. CI inherits this for free when using `make test`.
- For non-Makefile CI runners, add `rm -f test/results/tc-map.jsonl` (or
  `rm -f "$TC_SIDECAR"` if overridden) before the test command.
- The sidecar file is generated output; add `test/results/` to `.gitignore`.

## Overriding the sidecar path

Set `TC_SIDECAR` to redirect (e.g. for multi-stack repos that run suites
from different working directories):

```bash
TC_SIDECAR=test/results/tc-map.go.jsonl go test ./...
TC_SIDECAR=test/results/tc-map.py.jsonl pytest tests/
```

`gen_report.py` reads only one sidecar at a time. For multi-stack repos
that want one Feishu report, merge fragments first:

```bash
cat test/results/tc-map.*.jsonl > test/results/tc-map.jsonl
```

(Append-only JSONL concatenates safely.)

## Discovery (grep-friendly)

Search for tests linked to a TC ID:

```bash
grep -rn '"TC-SY-001"' test/results/tc-map.jsonl    # exact, sidecar-based
grep -rn 'tc.*TC-SY-001\|Mark.*TC-SY-001' .          # source-based (any stack)
```

The sidecar grep is authoritative for "which tests currently link to this TC";
the source grep finds the registration site for editing.
