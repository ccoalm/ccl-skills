# Test Report Config Schema

Each project keeps `test/.report-config.json` committed in the repo (resource IDs only, no secrets).
`base_token` and `table_id` are Bitable resource IDs, not auth credentials —
they come from the Bitable URL and are populated automatically via `--init`.

## Schema

```json
{
  "base_token": "",
  "table_id": "",
  "folder_token": "",
  "report_doc_url": "",
  "test_suites": [
    {
      "name": "API tests",
      "layer": "contract",
      "test_type": "api-automation",
      "command": "pytest tests/api/ --junit-xml=test/results/api.xml --cov --cov-report=xml:test/results/api-cov.xml -q",
      "results_file": "test/results/api.xml",
      "coverage_file": "test/results/api-cov.xml"
    },
    {
      "name": "Go service",
      "layer": "unit",
      "test_type": "api-automation",
      "command": "go test ./... -coverprofile=test/results/go.cov -v 2>&1 | go-junit-report -set-exit-code > test/results/go.xml",
      "results_file": "test/results/go.xml"
    }
  ]
}
```

| Field | Required | How to populate |
|---|---|---|
| `base_token` | optional | Bitable mode: auto-parsed from URL by `--init --bitable-url`. Leave empty for **minimal mode** (no Bitable; JUnit-summary report only — see Usage Step 1 below). |
| `table_id` | optional | Same as above. Both fields together gate Bitable mode: both set → Bitable mode; both empty → minimal mode; one set + one empty → config error. |
| `folder_token` | no | Feishu folder for first-time doc creation; `""` = personal space; set manually if needed |
| `report_doc_url` | no | Written automatically after first report run; commit this value for CI reuse |
| `test_suites` | no | List of test commands; each `results_file` is a JUnit XML path; optional `coverage_file` is a cobertura.xml path (pytest-cov / vitest --coverage / jest --coverage / cobertura-formatted Go cover) — gen_report.py sums `lines-covered` / `lines-valid` across suites and shows code coverage in the report 总览 |
| `test_suites[].layer` | optional | Enables layer evidence for `--validate-matrix`; configured layers are checked only when matrix validation runs, and CI hard-fails only with `--matrix-drift-gate=fail` |
| `test_suites[].test_type` | optional | Report-only grouping field for execution form: `ui-automation`, `api-automation`, `device-automation`, `contract-validation`, `llm-eval`, or `manual-verification`. It does not drive matrix validation, but it powers report breakdowns and makes no-Bitable mode comparable to structured TC reports. |
| `test_suites[].matrix_gate` | optional | Default `true`; set `false` for live/device/slow suites that are documented outside the fast matrix gate |

Optional per-suite `layer` enables scenario-specific matrix enforcement. Use it
when the project wants `test/cases/test-matrix.md` to be a machine-checked
health gate, not just a planning artifact.

What report-only mode checks is a two-way presence check: every TC ID in the
matrix exists in Bitable and is not `废弃`, and every active Bitable TC appears
in at least one matrix cell. The blocking behaviour of each target, the backup
protocol, and the exit-code contract are specified together further down (see
"`make report-validate-matrix` and `make report-validate-matrix-report` are
report-only …").

Allowed normalized layers:

| Layer | Meaning |
| --- | --- |
| `unit` | fast unit/component-level assertions that do not cross runtime boundaries |
| `contract` | API/schema/client/server contract suites |
| `integration` | DB/cache/queue/service-client/container-backed suites |
| `e2e` | browser/device/host/API-smoke real-flow suites |

Suite `layer` aliases such as `api`, `api-contract`, `browser`, `host-smoke`,
and `device` normalize into the four layers above. Matrix headers remain
canonical only: use `unit`, `contract`, `integration`, `e2e`, `manual`, and
`blocked`; columns such as `smoke` or `host` are not treated as layer claims.
Projects may extend the matrix with additional columns for specialist concerns
(mutation / fuzz / property / chaos): `parse_matrix_tcs` ignores unknown layer
headers — it neither breaks on nor validates them.
If no canonical layer header is found, validation reports a matrix parse error
instead of treating every active Bitable TC as missing from the matrix.
If no parsed suite has a `layer`, matrix validation still checks TC existence
and Bitable sync, but skips layer enforcement. Once any suite declares `layer`, run the suites before
`--validate-matrix` and add `layer` to every suite that carries matrix-linked
TCs; missing JUnit XML for a gate-participating layered suite fails
`--matrix-drift-gate=fail` as missing evidence, and unlabeled linked TCs are
reported as matrix drift when existing JUnit evidence is available for that
layer.
`make report-validate-matrix` and `make report-validate-matrix-report` are
report-only and must not be used as merge gates. `make
report-validate-matrix-gate` owns the full blocking run:
`gen_report.py --run-tests` requires Bitable config and at least one fast-gate
suite, moves configured fast-gate `results_file` paths to timestamped
`.pre-gate-bak-*` backups, runs configured fast-gate
`test_suites` (`matrix_gate` not false), and then validates with
`--matrix-drift-gate=fail`. If a suite does not regenerate its configured
`results_file`, the pre-gate backup is restored and the gate fails; if it does
regenerate, the backup is removed.
If a CI stage already ran suites and should only aggregate artifacts, use
`make report-validate-matrix-report` or raw `--validate-matrix`; the blocking
target always reruns and backs up fast-gate results itself. The report-only
targets and raw warn mode without `--run-tests` always exit 0 for matrix drift
and missing XML. If a caller explicitly combines warn mode with `--run-tests`,
suite command failures can still affect exit status.
Raw `--validate-matrix` is report-only by default. Raw fail mode must use
`--run-tests` in the same invocation; fail-mode `--run-tests` backs up configured
fast-gate `results_file` paths before running suites. Fast-gate commands must
write the exact configured `results_file`; otherwise the gate fails as missing
XML / config-or-execution failure instead of reusing stale evidence. The
backup protocol only prevents accidental reuse of a pre-existing path — the
suite command itself remains the trust boundary and must genuinely run the
tests rather than copy cached XML. Fail mode applies the matrix drift gate
first (matrix / Bitable / layer-coverage drift), then the standard result gate
(suite failure, failed or blocked linked TCs, missing fast-gate XML, missing
gate-layer XML).
Every gate-participating layered suite must produce its JUnit XML from its
configured `test_suites[].command` at the exact configured `results_file` path
(recommended under `test/results/`); for suites
intentionally outside the fast gate, set `matrix_gate: false` and keep their
owner/release decision in the matrix as manual or blocked evidence, not in an
automated layer column.
List every TC ID explicitly in matrix cells; range shorthand such as
`TC-PY-001..005` is not parsed as multiple TCs.
Unconfigured or missing-evidence matrix layers are printed as unverified instead
of being treated as checked. Without any configured suite `layer`, even fail
mode enforces TC presence / Bitable sync only; layer evidence becomes blocking
after a project opts in by declaring at least one gate-participating suite
`layer`. Empty automated layer columns do not trigger layer enforcement; only
automated layer cells with TC IDs need matching fast-gate evidence. Matrix drift exits non-zero only when validation is run with
`--matrix-drift-gate=fail`; in fail mode, configured suites that do
not produce JUnit XML also exit non-zero as missing evidence.

Recommended `test_type` values:

| Test type | Meaning |
| --- | --- |
| `ui-automation` | browser/admin-web rendered interaction automation |
| `api-automation` | API/service assertions driven by test code |
| `device-automation` | mobile/miniapp/device or host-runtime automation |
| `contract-validation` | schema/proto/GraphQL/OpenAPI compatibility validation |
| `llm-eval` | replay/eval/model/prompt/inference harness checks |
| `manual-verification` | human-only evidence or manually executed acceptance |

**vs-last-run delta**: after each non-dry-run, gen_report.py writes
`test/results/last-run.json` (path overridable via `TC_LAST_RUN` env). On the
next run, the report's "vs 上次跑" section lists 🔴 newly-failing / 🟢 fixed /
status flips / no-longer-seen. The snapshot is gitignored. For CI cross-run
persistence, use the cache action (GitHub Actions `actions/cache`, GitLab
`cache:paths`) keyed by branch+unit so the diff survives ephemeral runners.

**TC ID linking** — tests register their TC IDs via a per-stack helper, which
appends a JSONL line to `test/results/tc-map.jsonl`. `gen_report.py` joins JUnit
XML against the sidecar by test name. Function names stay clean — TC linking is
metadata, not part of the test identifier.

```python
# Python
from tc import tc

def test_login_success():
    tc("TC-SY-001")

def test_bulk_import_partial_failure():
    tc("TC-SY-001", "TC-SY-002")
```
```go
// Go
func TestLoginSuccess(t *testing.T) {
    tc.Mark(t, "TC-SY-001")
}
```

Helper files live in `tc_helpers/`; see `tc-marker-conventions.md` for install,
multi-TC tests, CI integration, and `TC_SIDECAR` overrides.

One TC covered by multiple tests passes only if **all** tests pass; pessimistic
merge across suites (`失败 > 阻塞 > 跳过 > 通过`).

Tests **without** `tc(...)` calls are silently excluded from Bitable sync — by
design, for unit tests, boundary checks, and internal logic that has no
corresponding TC. The report still surfaces their count under
"未链接 TC 的测试" so code-quality signal stays visible.

## Usage

### Step 0: Vendor the script (one-time)

Copy this skill's `references/gen_report.py` into the project as
`test/scripts/gen_report.py` and commit it. Every command below (and the
Makefile `GEN_REPORT` default and CI templates) calls the vendored copy, so CI
never depends on a skill being installed on the runner.

### Step 1: Init config (one-time, local)

**Bitable mode** (TC management in Bitable):

```bash
python test/scripts/gen_report.py \
  --config test/.report-config.json \
  --init \
  --bitable-url "https://xxx.feishu.cn/base/BASxxx?table=tblxxx"
```

Parses `base_token` and `table_id` from the URL (fetches table list if `table`
param is absent). Writes config file.

**Minimal mode** (no TC management — just JUnit-summary reports):

```bash
python test/scripts/gen_report.py \
  --config test/.report-config.json --init
```

Writes a config skeleton with empty Bitable fields. The report will print to
stdout unless `report_doc_url` is set to a Feishu doc.

### Step 2: Generate / update report (local)

```bash
python test/scripts/gen_report.py --run-tests
```

Defaults: `--config test/.report-config.json` (falls back to `.report-config.json`), author from `git config user.name`,
source auto-detected as `本地`, version from `git describe --tags --always`.
First run creates the Feishu doc and saves its URL into config. Subsequent runs replace in place.

### CI (GitHub Actions example)

```yaml
- name: Setup lark-cli bot auth
  run: |
    echo "${{ secrets.LARK_BOT_APP_SECRET }}" | \
      lark-cli config init \
        --app-id "${{ secrets.LARK_BOT_APP_ID }}" \
        --app-secret-stdin \
        --brand feishu

- name: Run tests and generate report
  run: |
    python test/scripts/gen_report.py \
      --run-tests --as bot
```

`--as bot` is the only required flag in CI. Source (`CI`), version (`git describe`),
and author (`CI`) are all auto-detected. `report_doc_url` in the committed config
acts as the stable doc pointer — set once after the first local run, then commit.

### Dry run (preview Markdown without writing to Feishu)

```bash
python gen_report.py --config test/.report-config.json --dry-run
```

## Required Auth Scopes

```bash
lark-cli auth login --domain base --scope "base:record:read"
lark-cli auth login --domain docs --scope "docx:document:create docx:document:update"
```

Verify:

```bash
lark-cli auth check --scope "base:record:read"
lark-cli auth check --scope "docx:document:create docx:document:update"
```

## Report Structure

1. **Header** — author, source (CI/本地), version, timestamp
2. **总览** — total / pass / fail / blocked / skip / untested / pass rate / P0 pass rate
3. **按模块统计** — per-module breakdown table
4. **按测试层级统计** — per-layer (unit / contract / integration / e2e / manual) breakdown
5. **按测试类型统计** — per-type breakdown
6. **P0 未通过明细** — P0 failures and blocks with last 信息流转 entry
7. **失败/阻塞明细（P1/P2）** — non-P0 failures
8. **发布建议** — ❌ / ⚠️ / ✅ based on P0 pass status

This is the core ordered set emitted by `gen_report.py`. `gen_report.py` also emits **mode-/condition-specific** sections when applicable — e.g. `手动测试说明`, `未链接 TC 的测试`, `孤儿 TC ID`, `📋 覆盖与残余风险`, `废弃记录`, `vs 上次跑`, and (minimal mode) `按套件统计` — see `gen_report.py` for the full conditional set.
