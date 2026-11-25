# Update 生命周期细则

SKILL.md `### Update (需求变更 / 迭代补充)` 节的生命周期细则全文。正文保留变更分类表与各级硬规则摘要（级联时效、误标安全闸、键/镜像/漂移三原则）；本文件承载步骤与命令细节。何时读：执行功能废弃级联、处理无 TC ID 测试代码、误标恢复、多人编辑后的漂移检查前。

## 功能废弃 → 测试代码级联

废弃一条 TC 后，立即执行以下步骤，不要留到后续迭代：

1. 找该 TC 关联的测试：grep sidecar `test/results/tc-map.jsonl` 取测试名/路径；同时 grep 源码里的 `tc("<TC ID>")` / `tc.Mark(t, "<TC ID>")` / `tcTest([..."<TC ID>"]` / `@pytest.mark.tc("<TC ID>")` 找到 declaration 处
2. 判断该测试所覆盖的业务代码是否还有效（代码是否已删除或功能已下线）。用每端 dev skill 的"废弃级联：业务代码是否仍在用"段里的 import-graph 命令，不要只 grep：
   - 业务代码已删/功能已下线 → 在同一 commit 删除该测试函数
   - 业务代码仍有效 → 默认不处理（TC 可能是提前标废弃，代码尚未清理）
3. 一条测试同时关联多个 TC（如 `tc("TC-SY-001", "TC-SY-002")`），且只有部分废弃 → 从 marker/`tc(...)` 参数列表里去掉废弃 ID，不删整个测试
4. 没有 TC 关联的测试（既没 marker 也没 `tc(...)` 调用）不进入此流程（见下方「无 TC ID 测试代码」规则）

## 无 TC ID 测试代码

无 TC ID 的测试代码覆盖范围更广（单元逻辑、边界条件、内部不变式），默认不受 TC 废弃影响。
但当业务代码本身被删除或功能下线时，需额外检查：

1. grep 所有测试文件，找出覆盖已删业务代码的测试函数（无 `tc(...)` 调用）
2. 判断这些测试是否还有价值（测试目标是否已不存在）：
   - 测试目标已不存在 → **提示用户决定是否删除**，不自动删
   - 测试目标仍有效 → 不处理

## 误标恢复（废弃 → 未测试）

`废弃` 是逻辑上的"永久终态"，但人会误标。恢复路径：

```bash
python test/scripts/gen_report.py \
  --config test/.report-config.json \
  --unfreeze "TC-SY-001,TC-SY-003" \
  --unfreeze-reason "误标恢复：功能未下线"
```

执行结果：状态从 `废弃` → `未测试`；信息流转追加 `[<author> <date>] 误标恢复（误标恢复：功能未下线）：废弃 → 未测试`。
**`--unfreeze-reason` 必填**（脚本会 `parser.error` 阻止空 reason），日后审计要看到为什么"永久终态"被打开。已是 `未测试`/`通过`/等其他状态的 TC 会被跳过（只对 `废弃` 生效）。

**不要与 `--run-tests` 同跑** — `--unfreeze` 是 Bitable 写操作，gate 仅看 suite 命令退出码，不看测试结果内容。如果测试套件命令本身退 0 但内部有失败，`--unfreeze` 仍会执行。若需要"测红就不解冻"，先单独 `make test`，看通过后再单独 `--unfreeze`。

## update 操作原则

- 用例ID 是唯一稳定键，不能修改；匹配记录时以 用例ID 为准
- 信息流转是 rolling log：先读当前值，追加 `[姓名 日期] 内容`，再写回；写回时只保留最近 N 条（默认 100，`TC_INFO_KEEP` 可配；`=0` 表示无限——只受 Bitable 单字段长度限制）
- 状态字段修改前确认当前值，避免将「通过」误回滚为「未测试」
- 批量更新时先列出受影响的 用例ID 清单，与用户确认后再执行
- Bitable 是执行权威源；本地 md 是用例定义字段的可读镜像。md 只同步用例定义字段（用例ID、模块、功能点、优先级、测试层级、测试类型、前置条件、操作步骤、预期结果），不同步状态/跟进人/信息流转
- md 同步匹配必须以 用例ID 为唯一键；模块名或功能点相同不代表是同一条记录
- 若 md 先于 Bitable 被修改（如直接编辑文件），需将 md 变更反向同步到 Bitable，再按 update 工作流补信息流转
- **漂移检查**：定期运行 `python gen_report.py --config test/.report-config.json --diff-md test/cases/all.md` 显示 md 与 Bitable 的 added/removed/changed；废弃记录自动排除（不在 md 里属正常）；多人编辑后必跑一次再 commit
- **批量更新禁直写信息流转**：批量更新预检必须拒绝直写信息流转字段，仅允许通过 `信息流转追加` 走读后合并与 `TC_INFO_KEEP` 滚动保留，防止无条件 `+record-upsert` 覆盖历史审计记录
- **JUnit XML 损坏防覆盖**：`gen_report.py` 解析套件结果遇到截断、非法/不支持的多字节编码、XML 命名空间或非 `testsuite`/`testsuites` 根节点 XML 时，必须按基础设施失败记录缺失套件并保留既有 `last-run.json` 基线，不得覆盖完整快照
- **版本钉扎**：当仓内测试代码/脚本按某条 TC 实现时，在实现侧记录该 TC 的修订标识——用**定义字段的规范化快照哈希**（或 Bitable 的不可变 record 修订号，若可得）；`[姓名 日期]` 不够（同人同日二次修订会撞标识，钉住旧版仍比对相等）。实现前先比对，**回写/提测前再验一次，且回写本身走与认领相同的修订条件更新**（先验后写仍是两步——验证通过与写入之间的并发修改只有条件写能挡）——哈希只有相等性判断：**任何一次不一致都视为分歧，停下、先做源对账**（更新钉扎侧并使差异可评审后再继续）；「更新/更旧」的说法仅当平台提供不可变单调修订号时才可用；发现源记录 stale/自相矛盾时**停下先修源记录**，不得按旧版实现后事后补
- **认领防冲突**：多人/多 agent 并发按 TC 实现时，认领必须是**原子的修订条件更新**（仅当记录修订仍等于读取时的修订才写入——平台支持的 CAS/乐观锁语义）或走**串行化认领协调者**（单写入口）。「读空→写」是 TOCTOU；「写后回读」也不等价——A 回读成功后仍可被 B 顶掉、双方各自都验证通过。两种安全机制都不可得时，**并发认领在该表上不受支持：停下改走人工/单线分配，不得按回读结果继续**。字段已有他人活跃认领时不得覆盖，改为联系认领人或换条目
- `+record-upsert --record-id` 中的 record_id 是 Bitable 内部 ID，必须先用 `get_record_index()` 从 用例ID 查出，不能直接用 用例ID 代替

## update 工作流

1. **明确变更范围** — 哪些功能点变了？哪些用例受影响？列出 用例ID 清单
2. **拉取现有记录** — `lark-cli base +record-list` 查当前状态，见下方「Step 8: List and Search Existing Records」
3. **分类变更** — 对照变更分类表分类每条记录的操作
4. **执行更新** — 单条用 `+record-upsert --record-id`，批量用 Python 脚本，信息流转 rolling-append（默认保留最近 100 条）
5. **新增记录** — 新功能点调用 `+record-upsert`（无 --record-id），ID 从现有最大序号续编
6. **同步本地 md** — 对照变更分类表，在本地 md 对应模块中同步增/改/标废弃
7. **验收** — 检查受影响记录的状态和信息流转是否正确；确认本地 md 与 Bitable 一致

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
import os, subprocess, json

def _extract_page_items(stdout_text):
    data = json.loads(stdout_text)
    if not isinstance(data, dict) or not isinstance(data.get("data"), dict) or not isinstance(data["data"].get("items"), list):
        raise RuntimeError(f"Unexpected +record-list payload shape (missing data.items list): {stdout_text[:200]}")
    return data["data"]["items"]

def get_record_index(base_token, table_id):
    """Returns dict: {用例ID → record_id}. Raises on CLI/schema failure or duplicate 用例ID."""
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
        items = _extract_page_items(result.stdout)
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

### Append to 信息流转 (read-then-write, single-writer precondition, rolling retention)

- **Single-writer precondition**: `+record-upsert` performs an unconditional field PUT with no conditional-revision/ETag flag, so single-writer / serialized execution per table or record is a required precondition; do not run concurrent uncoordinated RMW updaters against the same record (route multi-editor updates through one serialized runner).
- **Paginated named-field read & rolling retention**: `+record-get` returns fields as a positional array, not by name — use `+record-list` with full pagination to read a known record's named fields and apply `TC_INFO_KEEP` rolling retention (`100` by default; `0` = unlimited):

```python
def get_record_fields(base_token, table_id, record_id):
    """Read fields of a specific record by record_id (paginates fully). Raises if not found or CLI/schema fails."""
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
        items = _extract_page_items(result.stdout)
        for rec in items:
            if rec["record_id"] == record_id:
                return rec["fields"]
        if len(items) < limit:
            break
        offset += limit
    raise LookupError(f"record_id '{record_id}' not found in table")

def format_rolling_info_log(current, entry):
    """Append entry to rolling 信息流转 log (retains last TC_INFO_KEEP entries, default 100; 0 = unlimited)."""
    keep = int(os.environ.get("TC_INFO_KEEP", "100"))
    lines = [ln for ln in (current or "").splitlines() if ln.strip()]
    lines.append(entry.strip())
    if keep > 0:
        lines = lines[-keep:]
    return "\n".join(lines)

def append_info_log(base_token, table_id, record_id, entry):
    """entry: '[姓名 2026-05-25] 内容'. Precondition: single serialized writer for record_id."""
    fields = get_record_fields(base_token, table_id, record_id)
    new_value = format_rolling_info_log(fields.get("信息流转", ""), entry)
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

# Precondition: single serialized writer for TABLE_ID. Reject direct 信息流转 overwrites,
# validate all target IDs up front, read/merge 信息流转追加, and send one +record-upsert per record.
direct_log_ids = [u.get("用例ID", "<missing>") for u in updates if "信息流转" in u]
if direct_log_ids:
    raise ValueError(f"Use '信息流转追加' instead of direct '信息流转' overwrite for: {direct_log_ids}")
index = get_record_index(BASE_TOKEN, TABLE_ID)
missing_ids = [u["用例ID"] for u in updates if u["用例ID"] not in index]
if missing_ids:
    raise LookupError(f"Target 用例ID not found in Bitable: {missing_ids}")

for u in updates:
    case_id = u["用例ID"]
    record_id = index[case_id]
    payload = {k: v for k, v in u.items() if k not in ("用例ID", "信息流转追加")}
    if "信息流转追加" in u:
        existing = get_record_fields(BASE_TOKEN, TABLE_ID, record_id)
        payload["信息流转"] = format_rolling_info_log(existing.get("信息流转", ""), u["信息流转追加"])
    if not payload:
        continue
    result = subprocess.run(
        ["lark-cli", "base", "+record-upsert",
         "--base-token", BASE_TOKEN,
         "--table-id", TABLE_ID,
         "--record-id", record_id,
         "--json", json.dumps(payload)],
        capture_output=True, text=True
    )
    if result.returncode != 0:
        raise RuntimeError(f"+record-upsert failed for {case_id} ({record_id}): {result.stderr}")
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
