# Feishu Bitable Setup Reference

This reference covers `lark-base`/lark-cli operations and auth scopes for initializing the testcase table and delivering testcase records. `test-artifact-management` owns this resource end to end; it does not create unrelated Wiki nodes or project tables.

## Required Auth Scopes

Authorize these before starting Bitable operations:

```
base:app:create
base:table:read
base:table:create
base:field:read
base:field:create
base:field:update
base:view:write_only
base:record:create
base:record:read
base:record:update
```

Authorize via device flow login. Prefer one-shot full-scope login:

```bash
lark-cli auth login --domain base --scope "base:app:create base:table:read base:table:create base:field:read base:field:create base:field:update base:view:write_only base:record:create base:record:read base:record:update"
```

For the report doc (Feishu Docs domain):

```bash
lark-cli auth login --domain docs --scope "docx:document:create docx:document:update"
```

Before any Base write, verify the current token against the server, then check the scopes needed by the operation:

```bash
lark-cli auth status --json --verify
lark-cli auth check --scope "base:app:create base:table:read base:table:create base:field:read base:field:create base:field:update base:view:write_only base:record:create base:record:read base:record:update"
```

If token verification fails or the server cannot be reached, stop before mutation and follow `lark-shared` authentication recovery. If a command reports a scope error, re-login adding the missing scope. The single full-scope login above covers every Bitable operation in this guide.

Interactive setup uses the user identity. If CI will later sync results with the bot credentials from `references/ci_templates/`, grant that app access to the target Base before enabling the job. For a Base mounted under Wiki, apply the resource-level app grant to both the Base and its Wiki parent; granting only the embedded Base view can leave bot writes failing with `91403`. Verify the bot can resolve the Base and read its records before treating CI setup as complete. On `91403`, stop identity swapping and follow `lark-shared` permission recovery for the actual resource.

## Step 1: Reuse or create the testcase Base

1. If the user provides a Base URL, resolve its base token and table ID and inspect it with `lark-base`.
2. If `.feishu/project.yaml` exists and contains valid `测试用例集` identifiers, reuse them as an optional compatibility input.
3. Before creating anything, run `lark-cli base +title-resolve --title "测试用例" --as user` and inspect exact-title candidates. Reuse only after confirming the candidate with the user; if several Bases match, present their URLs/locations and do not choose by title alone.
4. If no confirmed candidate exists, use `lark-base` to create one Base named `测试用例`; create it under a specific folder only when the user requests that placement.
5. Never create a project Wiki tree or unrelated requirement, batch, report, bug, or release-document tables as a side effect.

Do not create a second testcase Base merely because fields are missing. Add only missing canonical fields, merge missing select options, and preserve unknown fields, options, views, and records. A conflicting field type requires an explicit schema decision; never delete or auto-convert it.

CLI equivalent for Base creation. Supplying the initial table and primary field avoids the platform default example schema; the later steps add only the remaining canonical fields:

```bash
lark-cli base +base-create --name "测试用例" \
  --table-name "测试用例" \
  --fields '[{"name":"用例ID","type":"text"}]' \
  --folder-token "<folder_token>"
```

- Run the same command with `--dry-run` first and inspect the returned API plan and target folder; remove `--dry-run` only after they match the request. Use `lark-base` rather than substituting a raw Base-creation endpoint.
- `folder_token`: from the Feishu folder URL. For root "我的空间" use `""` or omit.
- Returns: `base_token` (used for all subsequent operations as `--base-token`)
- If creation returns a Base token but a later table/schema step fails, inspect that Base with `+base-get` and `+table-list`, then resume or reuse it; do not retry by creating another Base. `lark-base` does not delete an entire Base. If the user explicitly wants the partial Base removed, hand the confirmed resource to `lark-drive` or the Feishu UI and keep deletion behind explicit user confirmation.

## Step 2: Resolve the testcase table

```bash
lark-cli base +table-list --base-token "<base_token>"
```

Select the table whose exact name is `测试用例` and use its ID. Do not assume
the first/default table is correct: if platform-default cleanup failed, both a
sample table and the intended table may exist. If no exact match exists, or
more than one table has that name, stop for an explicit resolution decision;
do not create another table or add fields to an arbitrary result.

Report any other tables and leave them untouched. Delete a non-canonical table
only after inspecting its records, identifying the exact table, and obtaining
the user's explicit deletion approval.

For a legacy `测试用例集` Base containing separate `功能` / `接口` / `单测`
tables and no exact `测试用例` table, present three choices and wait for the
user's migration decision: keep the legacy tables accessible but unmanaged by
this workflow; designate and explicitly rename one table after a schema review;
or create a new canonical table and migrate records through `lark-base` under
an approved field mapping. Never merge, delete, or choose among legacy tables
automatically.

## Step 3: Ensure required fields

List existing fields first. Add the missing fields below one by one. If a field exists with a conflicting type, stop and ask for a schema decision; do not auto-convert or delete it. For select fields, preserve existing options and append only missing canonical options.

Updating an existing field is a high-risk full-state `PUT`, not a patch. Before
appending select options or changing any other property:

1. Read the exact field with `+field-get` and use its full writable definition
   as the baseline.
2. Merge only the requested change into that definition. For a select field,
   retain every existing option object and other returned configuration, then
   append only the missing canonical options. Never submit a canonical-only
   option list.
3. Preview the merged target with `+field-update --dry-run`; verify the Base,
   table, field, type, and retained options/configuration. Then submit the same
   full target with `+field-update ... --yes`. Follow the current `lark-base`
   field-update guide for writable JSON shape; do not send read-only response
   metadata back to the API.

`lark-base` exposes no ETag/CAS guard for field updates, so this procedure can
reduce but not eliminate the race window. Coordinate one schema-mutation
session; if exclusive editing cannot be established with other operators, stop
instead of writing. Immediately before the PUT, read the field again and
compare it with the merge baseline; if it changed, stop and rebuild the merge.
Read it again after the PUT and verify the intended change plus all retained
configuration. Report the residual read-to-write race as a known limitation.

### Add 模块 (single select)

```bash
lark-cli base +field-create --base-token "<base_token>" --table-id "<table_id>" \
  --json '{"name":"模块","type":"select","options":[
    {"name":"<module_1>","color":0},
    {"name":"<module_2>","color":1},
    {"name":"<module_3>","color":2}
  ]}'
```

Determine module names from the actual requirements source. Color index 0–14 cycles through Feishu's preset colors.

### Add 功能点

```bash
lark-cli base +field-create --base-token "<base_token>" --table-id "<table_id>" \
  --json '{"name":"功能点","type":"text"}'
```

### Add 优先级 (single select)

```bash
lark-cli base +field-create --base-token "<base_token>" --table-id "<table_id>" \
  --json '{"name":"优先级","type":"select","options":[
    {"name":"P0","color":1},
    {"name":"P1","color":3},
    {"name":"P2","color":0}
  ]}'
```

### Add 测试层级 (single select)

```bash
lark-cli base +field-create --base-token "<base_token>" --table-id "<table_id>" \
  --json '{"name":"测试层级","type":"select","options":[
    {"name":"unit","color":0},
    {"name":"contract","color":5},
    {"name":"integration","color":3},
    {"name":"e2e","color":1},
    {"name":"manual","color":7}
  ]}'
```

This field records **where the primary proof lives**. Keep it aligned with the TC author's chosen main proof layer; matrix columns remain the detailed multi-layer planning artifact.

### Add 测试类型 (single select)

```bash
lark-cli base +field-create --base-token "<base_token>" --table-id "<table_id>" \
  --json '{"name":"测试类型","type":"select","options":[
    {"name":"ui-automation","color":1},
    {"name":"api-automation","color":3},
    {"name":"device-automation","color":4},
    {"name":"contract-validation","color":5},
    {"name":"llm-eval","color":6},
    {"name":"manual-verification","color":7}
  ]}'
```

This field records **how the scenario is exercised**. Keep it orthogonal to `测试层级`: for example `e2e + ui-automation`, `contract + contract-validation`, or `manual + manual-verification`.

### Add 前置条件

```bash
lark-cli base +field-create --base-token "<base_token>" --table-id "<table_id>" \
  --json '{"name":"前置条件","type":"text"}'
```

### Add 操作步骤

```bash
lark-cli base +field-create --base-token "<base_token>" --table-id "<table_id>" \
  --json '{"name":"操作步骤","type":"text"}'
```

### Add 预期结果

```bash
lark-cli base +field-create --base-token "<base_token>" --table-id "<table_id>" \
  --json '{"name":"预期结果","type":"text"}'
```

### Add 状态 (single select)

```bash
lark-cli base +field-create --base-token "<base_token>" --table-id "<table_id>" \
  --json '{"name":"状态","type":"select","options":[
    {"name":"未测试","color":0},
    {"name":"通过","color":3},
    {"name":"失败","color":1},
    {"name":"阻塞","color":4},
    {"name":"跳过","color":6},
    {"name":"废弃","color":2}
  ]}'
```

`废弃` 表示功能已永久下线，用例不再有效。废弃记录保留在 Bitable 中（不删除），不计入统计总数和通过率。与`跳过`区别：`跳过`是临时排除，可恢复；`废弃`是永久终态。

**`跳过` 与 `阻塞` 语义边界**（gen_report.py 自动映射 JUnit `<skipped>` 元素）：

| Bitable 状态 | 含义 | 何时产出 |
|---|---|---|
| `阻塞` | 依赖未就绪、等环境 | pytest `@skip(reason="requires linux")` / `@skipif(not driver)` / `@skip("needs docker")` 等环境性 skip — reason 含 `environment / platform / windows / linux / darwin / requires / needs / no driver / no device / service unavailable / credential / fixture not ready` 等关键词 |
| `跳过` | 人工临时排除，可恢复 | 其他所有 JUnit `<skipped>`（写 reason 描述业务决定，例如 `manually disabled for this iteration` / `excluded pending product confirmation`） |
| `废弃` | 功能永久下线 | **不会**由 JUnit 自动产出；只能手动在 Bitable 设置，automation 不得修改（`gen_report.py --unfreeze` 是唯一恢复路径） |

含义不同直接影响发布建议：`阻塞` 进 P0/P1 release-blocking 集，`跳过` 不进。所以 reason 字段写清楚，不要混。

### Add 跟进人 (user field)

```bash
lark-cli base +field-create --base-token "<base_token>" --table-id "<table_id>" \
  --json '{"name":"跟进人","type":"user"}'
```

### Add 信息流转

```bash
lark-cli base +field-create --base-token "<base_token>" --table-id "<table_id>" \
  --json '{"name":"信息流转","type":"text"}'
```

## Step 4: Ensure the primary field is 用例ID

A Base created by Step 1 already has this field; do not rename it again. For a
reused Base, first confirm that `用例ID` is the primary field. If `用例ID`
already exists as a non-primary field while the primary field has another name,
stop for an explicit migration decision; do not delete either field or attempt
an ordered delete-and-rename automatically. If `用例ID` is missing, list fields
and confirm that the existing primary text field is the intended testcase
identifier. Only then rename it; if the primary field contains another business
key or has a conflicting type, stop for an explicit schema decision.

First, list fields to get the default field's ID:

```bash
lark-cli base +field-list --base-token "<base_token>" --table-id "<table_id>"
```

Then rename it. Read the field again with `+field-get`, preserve its complete
writable definition, and change only `name`; preview that target before the
confirmed high-risk write:

```bash
lark-cli base +field-get --base-token "<base_token>" --table-id "<table_id>" \
  --field-id "<first_field_id>"
lark-cli base +field-update --base-token "<base_token>" --table-id "<table_id>" \
  --field-id "<first_field_id>" \
  --json '<complete_writable_field_definition_with_name_set_to_用例ID>' --dry-run
lark-cli base +field-update --base-token "<base_token>" --table-id "<table_id>" \
  --field-id "<first_field_id>" \
  --json '<same_verified_complete_writable_field_definition>' --yes
```

## Step 5: Batch Create Records

### Avoid TC ID collisions before batch-create

When multiple people work on the same Bitable in parallel, both may pick the
same next sequence number (e.g. two devs both choose `TC-SY-008`). Always check
the current max per module first:

```bash
python test/scripts/gen_report.py \
  --config test/.report-config.json --next-id
# Prints: TC-SY-006  (current max: TC-SY-005)
#         TC-AU-011  (current max: TC-AU-010)
```

Use the printed next-ID as the starting point. For atomic reservation in a
shared workspace, batch-create with the planned IDs immediately and rely on
Bitable's eventual `build_index` duplicate-check (raises on collision) as the
backstop. If a collision is detected, re-run `--next-id` and pick fresh IDs.

### Batch insert

Use `+record-batch-create` for large sets. The `--json` payload uses a tabular format:

```bash
lark-cli base +record-batch-create --base-token "<base_token>" --table-id "<table_id>" \
  --json '{"fields":["用例ID","模块","功能点","优先级","测试层级","测试类型","状态","信息流转"],
           "rows":[
             ["TC-MOD-001","模块名","功能描述","P0","e2e","ui-automation","未测试","[创建人 2026-05-25] 用例初始化"],
             ["TC-MOD-002","模块名","功能描述2","P1","contract","api-automation","未测试","[创建人 2026-05-25] 用例初始化"]
           ]}'
```

For complex or multi-line fields, use `+record-upsert` per record instead:

```python
import subprocess, json

records = [
    {
        "用例ID": "TC-MOD-001",
        "模块": "模块名",
        "功能点": "功能描述",
        "优先级": "P0",
        "测试层级": "e2e",
        "测试类型": "ui-automation",
        "前置条件": "前置状态",
        "操作步骤": "1. 步骤一\n2. 步骤二",
        "预期结果": "预期结果描述",
        "状态": "未测试",
        "信息流转": "[创建人 2026-05-25] 用例初始化"
    },
    # ... more records
]

for r in records:
    result = subprocess.run(
        ["lark-cli", "base", "+record-upsert",
         "--base-token", BASE_TOKEN,
         "--table-id", TABLE_ID,
         "--json", json.dumps(r)],
        capture_output=True, text=True
    )
    if result.returncode != 0:
        print(f"ERROR: {result.stderr}")
    else:
        print(result.stdout)
```

For select fields: pass the option name as a plain string.
For user fields: pass `{"id": "<open_id>"}` or leave empty for unassigned.

Recommended defaulting rule when authors are creating rows in bulk:
- Visible browser/admin journey → `测试层级=e2e`, `测试类型=ui-automation`
- Service/API behavior → `测试层级=contract` or `integration`, `测试类型=api-automation`
- Published schema / proto compatibility → `测试层级=contract`, `测试类型=contract-validation`
- Device or host-runtime proof → `测试层级=e2e`, `测试类型=device-automation`
- Human-only acceptance → `测试层级=manual`, `测试类型=manual-verification`

## Step 6: Rename default view + create Grouped View

A freshly-created Bitable's default view is named "Grid View" (English) — rename it
to Chinese first so the UI is consistent:

```bash
# Rename "Grid View" → "全部用例" (the default catch-all view)
lark-cli base +view-rename --base-token "<base_token>" --table-id "<table_id>" \
  --view-id "Grid View" --name "全部用例"
```

Then create the grouped view used as a mind-map substitute:

```bash
lark-cli base +view-create --base-token "<base_token>" --table-id "<table_id>" \
  --json '{"name":"按模块分组","type":"grid"}'

# Configure grouping by 模块 field
lark-cli base +view-set-group --base-token "<base_token>" --table-id "<table_id>" \
  --view-id "按模块分组" --json '{"field_name":"模块","desc":false}'
```

Recommended baseline views:
- `全部用例` (default; flat list, no grouping)
- `按模块分组` (grouped by 模块)
- `P0 关注` (filtered by 优先级 = P0; add via `+view-create` + `+view-set-filter` if needed)

## Step 7: Set Sharing Permissions

No lark-cli command is available for org-wide sharing. Do this manually:

1. Open the Bitable URL in Feishu
2. Click "分享" → "组织内可编辑" (or appropriate permission level)

## Step 8: List and Search Existing Records

需要 scope: `base:record:read`

```bash
lark-cli auth login --domain base --scope "base:record:read base:record:update"
```

### List all records (paginated)

```bash
lark-cli base +record-list --base-token "<base_token>" --table-id "<table_id>" \
  --limit 200 --format json
```

`+record-list` uses `--limit` (max 200) and `--offset` for pagination. Default output is markdown; pass `--format json` for machine-readable output.

### Python: 按 用例ID 建查找索引

```python
import subprocess, json

def get_record_index(base_token, table_id):
    """Returns dict: {用例ID → record_id}. Raises on CLI failure or duplicate 用例ID."""
    index = {}
    offset = 0
    limit = 200
    while True:
        result = subprocess.run(
            ["lark-cli", "base", "+record-list",
             "--base-token", base_token,
             "--table-id", table_id,
             "--limit", str(limit),
             "--offset", str(offset),
             "--format", "json"],
            capture_output=True, text=True
        )
        if result.returncode != 0:
            raise RuntimeError(f"+record-list failed: {result.stderr}")
        data = json.loads(result.stdout)
        items = data.get("data", {}).get("items", [])
        for record in items:
            case_id = record["fields"].get("用例ID", "")
            if case_id:
                if case_id in index:
                    raise ValueError(f"Duplicate 用例ID '{case_id}' found; fix Bitable before updating")
                index[case_id] = record["record_id"]
        if len(items) < limit:
            break
        offset += limit
    return index
```

## Step 9: Update Records

### Update a single record

```bash
lark-cli base +record-upsert --base-token "<base_token>" --table-id "<table_id>" \
  --record-id "<record_id>" \
  --json '{"状态": "通过"}'
```

`--json` payload is the fields dict directly (not wrapped in `{"fields": ...}`).
`record_id` is the internal ID from `+record-list`; never use 用例ID directly as record_id.

### Append to 信息流转 (read-then-write, never overwrite)

`+record-get` returns fields as a positional array, not by name. Use `+record-list` with full pagination to read a known record's named fields:

```python
def get_record_fields(base_token, table_id, record_id):
    """Read fields of a specific record by record_id (paginates fully). Raises if not found or CLI fails."""
    offset = 0
    limit = 200
    while True:
        result = subprocess.run(
            ["lark-cli", "base", "+record-list",
             "--base-token", base_token,
             "--table-id", table_id,
             "--limit", str(limit),
             "--offset", str(offset),
             "--format", "json"],
            capture_output=True, text=True
        )
        if result.returncode != 0:
            raise RuntimeError(f"+record-list failed: {result.stderr}")
        data = json.loads(result.stdout)
        items = data.get("data", {}).get("items", [])
        for rec in items:
            if rec["record_id"] == record_id:
                return rec["fields"]
        if len(items) < limit:
            break
        offset += limit
    raise LookupError(f"record_id '{record_id}' not found in table")

def append_info_log(base_token, table_id, record_id, entry):
    """entry: '[姓名 2026-05-25] 内容'. Raises if read fails (never overwrites on error)."""
    # 1. read current value — raises on failure to prevent silent overwrite
    fields = get_record_fields(base_token, table_id, record_id)
    current = fields.get("信息流转", "")
    new_value = (current + "\n" + entry).strip()

    # 2. write back
    result = subprocess.run(
        ["lark-cli", "base", "+record-upsert",
         "--base-token", base_token,
         "--table-id", table_id,
         "--record-id", record_id,
         "--json", json.dumps({"信息流转": new_value})],
        capture_output=True, text=True
    )
    if result.returncode != 0:
        raise RuntimeError(f"信息流转 write failed for {record_id}: {result.stderr}")
```

### Python: batch update records by 用例ID

```python
updates = [
    {"用例ID": "TC-SY-001", "状态": "通过",  "信息流转追加": "[张三 2026-05-28] 测试通过"},
    {"用例ID": "TC-SY-003", "状态": "失败",  "信息流转追加": "[张三 2026-05-28] 步骤2预期结果不符"},
    {"用例ID": "TC-SY-007", "状态": "跳过",  "信息流转追加": "[李四 2026-05-28] 功能已废弃"},
]

index = get_record_index(BASE_TOKEN, TABLE_ID)

for u in updates:
    case_id = u["用例ID"]
    record_id = index.get(case_id)
    if not record_id:
        print(f"WARNING: {case_id} not found in Bitable")
        continue

    fields = {k: v for k, v in u.items() if k not in ("用例ID", "信息流转追加")}
    field_ok = True
    if fields:
        result = subprocess.run(
            ["lark-cli", "base", "+record-upsert",
             "--base-token", BASE_TOKEN,
             "--table-id", TABLE_ID,
             "--record-id", record_id,
             "--json", json.dumps(fields)],
            capture_output=True, text=True
        )
        if result.returncode != 0:
            print(f"ERROR updating {case_id}: {result.stderr}")
            field_ok = False

    if field_ok and "信息流转追加" in u:
        append_info_log(BASE_TOKEN, TABLE_ID, record_id, u["信息流转追加"])
```

### Python: update test case content (requirement changed)

```python
content_updates = [
    {
        "用例ID": "TC-SY-002",
        "操作步骤": "1. 新步骤一\n2. 新步骤二",
        "预期结果": "新预期结果",
        "信息流转追加": "[产品 2026-05-28] 需求变更：步骤和预期结果已更新"
    },
]
# same loop as batch update above
```

## Common Errors

| Error | Cause | Fix |
|---|---|---|
| `field type invalid` | Used wrong type string | Use `"text"`, `"select"`, `"user"` (not `"person"`, `"dropdown"`) |
| `table already exists` | First `+table-create` call half-created a table | Use `+table-list` to find and reuse the existing table |
| `options format error` | Nested `property` key | Pass options as direct array: `{"name":"x","type":"select","options":[...]}` |
| `record_id not found` | Using 用例ID instead of record_id for update | Use `+record-list` to build `{用例ID → record_id}` index first |
| 信息流转 overwritten | Writing new value without reading current first | Always read → append → write; never write unconditionally |
| `base:record:update` permission denied | Scope not authorized | Run `lark-cli auth login --domain base --scope "base:record:read base:record:update"`, verify with `lark-cli auth check --scope "base:record:read base:record:update"` |
| `unknown command +record-update` | Command does not exist | Use `+record-upsert --record-id <id>` for updates |
| `unknown flag --app-token` on any command | All Base commands use a different flag | Use `--base-token` (not `--app-token`) for all `lark-cli base` commands |
| `unknown command +app-create` | Command renamed | Use `+base-create`; it returns `base_token`, not `app_token` |
| `unknown flag --page-size` / `--page-token` | `+record-list` uses different pagination flags | Use `--limit` (max 200) and `--offset`; add `--format json` for JSON output |
| `json.loads()` fails on record-list output | Default output is markdown, not JSON | Add `--format json` to all `+record-list` calls used in Python scripts |
| `unknown flag --field` on field-create | Wrong flag name | Use `--json '{"name":"...","type":"..."}'` |
| `unknown flag --name` / `--type` on field-update or view-create | Wrong flag names | Use `--json` with the full object; `+field-update` uses full PUT semantics |
| Select field read back as `["P1"]` not `"P1"` | API wraps select values in array | Write as plain string `"P1"`; when reading, guard with `value[0] if isinstance(value, list) else value` |
