#!/usr/bin/env python3
"""Count, in saved paired-eval runs, how often a deliverable names people who were never
mentioned and how often the reply ends waiting on the requester.

Reads the private output root of `skill-paired-eval.py` (never writes to it) and, for every
valid run whose completion check passed, reports three numbers:

  role_mentions   occurrences in the deliverable document of an organisational role, a
                  sign-off or an approver (负责人, 审批人, 签字, sign-off, approver, ...),
                  excluding lines that bind the role to the requester or say the role
                  is not needed, and table header rows.
  open_questions  list items or table rows under a heading that leaves questions for the
                  requester (待确认, 开放问题, 未决, open questions, ...).
  ends_waiting    1 when the tail of the final reply asks the requester to confirm, approve,
                  review or decide before the work counts as done or goes on.

What these numbers are NOT:

  - They are fixed regular expressions over free text, not a judgment. A role the request
    itself names (a "管理员" the feature is about) is not on the list, but a document that
    quotes the requirement's own wording of a listed word is still counted.
  - A line that names one invented role and denies another is skipped whole, so the count
    errs low on such lines.
  - `role_mentions` cannot tell an invented approver from a role the repository really
    requires; the tasks this was written for name no team, so every hit there is invented.
  - `ends_waiting` reads only the last TAIL_CHARS characters of the last result. A reply that
    waits earlier and ends on a summary is missed; a closing offer phrased as a statement
    ("下一步可以……") is deliberately not counted.
  - `open_questions` counts items, not whether each one could have been decided from the
    material at hand.
  - Nothing here measures the quality of the deliverable.

Exit status is non-zero only when the scan itself failed, never because the numbers look bad.
"""
import argparse
import json
import re
import sys
from pathlib import Path

TAIL_CHARS = 400

ROLE = re.compile(
    r"负责人|审批人|(?<!待)审批(?!流)|签字|签署|会签|签收|评审人|评审委员会|拍板人|决策人|把关人"
    r"|(?:产品|算法|研发|测试|数据|项目|安全|运维|业务|运营|法务|合规|架构)(?:团队|同学|经理|主管|侧确认|方确认)"
    r"|sign-?off|signoff|approver|decider|accountable owner|risk owner|security owner"
    r"|(?:product|engineering|security|qa|data|project) (?:owner|lead|manager|team)",
    re.IGNORECASE)
# A bare "you" is not a binding: "You need sign-off from the security owner" names an outside signer.
REQUESTER = re.compile(r"请求者|请求方|你本人|你自己|你一个人|本人|你作为|由你|你是|requester|you alone|you are the",
                       re.IGNORECASE)
NEGATED = re.compile(r"不设|不安排|不需要|无需|不用|没有|代替|跳过|可以省|不走|不写|不列|不新造|no (?:other )?(?:approver|sign-?off|reviewer)"
                     r"|without|not needed|not required", re.IGNORECASE)

QUESTION_HEADING = re.compile(
    r"^#{1,6}\s.*(?:待确认|待你确认|待决|未决|开放问题|开放点|遗留问题|需要你|需.{0,6}确认|需.{0,6}决定|待.{0,4}拍板"
    r"|open questions?|open issues?|to confirm|needs? (?:your )?(?:decision|confirmation))",
    re.IGNORECASE)
HEADING = re.compile(r"^#{1,6}\s")
ITEM = re.compile(r"^\s*(?:[-*+]|\d+[.、)])\s+\S")
TABLE_ROW = re.compile(r"^\s*\|")
TABLE_RULE = re.compile(r"^\s*\|\s*:?-{2,}")

WAITING = re.compile(
    r"(?:请|麻烦)(?:你|您)?[^。！？\n]{0,6}(?:确认|批准|审批|评审|签字|拍板|定夺|答复|回复|决定|过目|审阅)"
    r"|(?:需要?|等|待)(?:你|您|请求方)[^。！？\n]{0,14}(?:确认|批准|审批|评审|签字|拍板|定夺|答复|回复|决定|过目|审阅)"
    r"|(?:确认|批准|评审|签字|拍板|答复|回复)(?:之?后|完|了)[^。！？\n]{0,24}(?:再|才|即可|就|继续|进入|开始)"
    r"|(?:你|您)(?:确认|确定|回复|答复|决定|定下|拍板|补充|告诉我)[^。！？\n]{0,40}(?:之后|以后|后[，,我再])"
    r"|收到[^。！？\n]{0,20}(?:之后|以后|后)|(?:要|等|由)(?:你|您)(?:先|来)?(?:决定|确认|拍板|定)|卡在(?:你|您)"
    r"|(?:是否|要不要|需不需要)[^。！？\n]{0,30}[?？]"
    r"|(?:你|您)(?:看|觉得|希望|想|倾向)[^。！？\n]{0,30}[?？]"
    r"|await(?:ing)? (?:your )?(?:confirmation|approval|sign-?off|review|decision|reply)"
    r"|wait(?:ing)? for (?:your |the )?(?:confirmation|approval|sign-?off|review|decision|reply)"
    r"|please (?:confirm|approve|review|decide)|let me know (?:if|whether|which|how)"
    r"|(?:shall|should) i [^.?\n]{0,60}\?|do you want [^.?\n]{0,60}\?",
    re.IGNORECASE)


def role_mentions(document):
    """Roles on a line that neither binds them to the requester nor says they are not needed.
    A table header row is skipped: its cells, not its column title, say who is named."""
    lines = document.splitlines()
    count = 0
    for index, line in enumerate(lines):
        hits = len(ROLE.findall(line))
        if not hits or REQUESTER.search(line) or NEGATED.search(line):
            continue
        if TABLE_ROW.match(line) and index + 1 < len(lines) and TABLE_RULE.match(lines[index + 1]):
            continue
        count += hits
    return count


def open_questions(document):
    """Items under a question heading: list items, and table rows after the header and rule."""
    count, inside, table_rows = 0, False, 0
    for line in document.splitlines():
        if HEADING.match(line):
            inside, table_rows = bool(QUESTION_HEADING.match(line)), 0
            continue
        if not inside:
            continue
        if TABLE_ROW.match(line):
            if not TABLE_RULE.match(line):
                table_rows += 1
                if table_rows > 1:
                    count += 1
            continue
        table_rows = 0
        if ITEM.match(line):
            count += 1
    return count


# The denial must sit in the same clause, right before the wait: "还没做完，等你确认" still waits.
DENIAL_BEFORE = re.compile(r"[不无没][^。！？\n，,、；;：:]{0,3}$")


def ends_waiting(reply):
    """A match right after a denial ("不需要你逐条确认", "不再是等你确认") is not a wait."""
    tail = reply[-TAIL_CHARS:]
    return 1 if any(not DENIAL_BEFORE.search(tail[:m.start()]) for m in WAITING.finditer(tail)) else 0


def final_reply(stream_path):
    last = ""
    for line in stream_path.read_text(encoding="utf-8", errors="replace").splitlines():
        try:
            event = json.loads(line)
        except ValueError:
            continue
        if isinstance(event, dict) and event.get("type") == "result" and isinstance(event.get("result"), str):
            last = event["result"]
    return last


def completion_checks(task):
    return [c for c in task.get("checks", []) if c.get("role") == "completion"]


def document_path(task):
    for check in completion_checks(task):
        if check.get("kind") == "path_present":
            return check["path"]
    return None


def completion_passed(task, record):
    graded = record.get("checks") if isinstance(record.get("checks"), dict) else {}
    wanted = [c["id"] for c in completion_checks(task)]
    return bool(wanted) and all((graded.get(i) or {}).get("result") == "pass" for i in wanted)


def scan(runs_root, tasks_dir):
    rows = []
    for record_path in sorted(Path(runs_root).glob("runs/*/*/*/record.json")):
        record = json.loads(record_path.read_text(encoding="utf-8"))
        sample_dir = record_path.parent
        task_file = Path(tasks_dir) / f"{record['task']}.json"
        if not task_file.is_file():
            continue
        task = json.loads(task_file.read_text(encoding="utf-8"))
        relative = document_path(task)
        row = {"task": record["task"], "arm": record["arm"], "sample": record["sample"], "counted": False}
        document = sample_dir / "world" / relative if relative else None
        if record.get("valid") and completion_passed(task, record) and document is not None and document.is_file():
            text = document.read_text(encoding="utf-8", errors="replace")
            row.update(counted=True, role_mentions=role_mentions(text), open_questions=open_questions(text),
                       ends_waiting=ends_waiting(final_reply(sample_dir / "stream.jsonl")))
        rows.append(row)
    return rows


def summarize(rows):
    groups = {}
    for row in rows:
        group = groups.setdefault((row["task"], row["arm"]),
                                  {"runs": 0, "counted": 0, "role_mentions": 0, "runs_with_roles": 0,
                                   "open_questions": 0, "ends_waiting": 0})
        group["runs"] += 1
        if row["counted"]:
            group["counted"] += 1
            group["role_mentions"] += row["role_mentions"]
            group["runs_with_roles"] += 1 if row["role_mentions"] else 0
            group["open_questions"] += row["open_questions"]
            group["ends_waiting"] += row["ends_waiting"]
    return groups


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    parser.add_argument("--runs", type=Path, action="append", required=True,
                        help="private output root of skill-paired-eval.py; repeat for several batches")
    parser.add_argument("--tasks-dir", type=Path, default=Path(__file__).resolve().parent / "paired-tasks")
    parser.add_argument("--json", action="store_true", help="print one JSON object per run instead of the table")
    args = parser.parse_args(argv)
    rows = []
    for root in args.runs:
        if not (root / "runs").is_dir():
            print(f"owner-role-audit: no runs/ under {root}", file=sys.stderr)
            return 2
        rows.extend(scan(root, args.tasks_dir))
    if args.json:
        for row in rows:
            print(json.dumps(row, ensure_ascii=False))
        return 0
    print("| task | arm | counted/runs | role mentions | runs with a role | open questions | ends waiting |")
    print("| --- | --- | --- | --- | --- | --- | --- |")
    for (task, arm), g in sorted(summarize(rows).items()):
        print(f"| {task} | {arm} | {g['counted']}/{g['runs']} | {g['role_mentions']} | {g['runs_with_roles']} "
              f"| {g['open_questions']} | {g['ends_waiting']} |")
    return 0


if __name__ == "__main__":
    sys.exit(main())
