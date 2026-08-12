"""Pytest suite for gen_report.py — covers pure functions that do not touch
lark-cli/Bitable/Feishu (those need subprocess mocking and live in a follow-up).

Run from this directory:
    pytest test_gen_report.py -q

Or from the repo root:
    pytest <skill-dir>/references/test_gen_report.py -q
"""

from __future__ import annotations

import json
import os
import sys
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).parent))
import gen_report as g  # noqa: E402


# ── Sidecar ────────────────────────────────────────────────────────────────────

def test_load_sidecar_empty(tmp_path):
    assert g.load_sidecar(tmp_path / "missing.jsonl") == {}


def test_load_sidecar_parses_and_normalizes(tmp_path):
    p = tmp_path / "tc-map.jsonl"
    p.write_text(
        '{"test": "tests/auth.py::test_login", "tc_ids": ["TC-SY-001"]}\n'
        '{"test": "TestBulk", "tc_ids": ["TC_SY_002", "TC-SY-003"]}\n'
        '\n'  # blank line tolerated
        'not-json line\n'  # skipped
    )
    m = g.load_sidecar(p)
    assert m == {
        "tests/auth.py::test_login": ["TC-SY-001"],
        "TestBulk": ["TC-SY-002", "TC-SY-003"],  # underscores normalized
    }


def test_load_sidecar_merges_duplicate_keys(tmp_path):
    """Marker form + in-body form may both register the same test — merge,
    don't overwrite."""
    p = tmp_path / "tc-map.jsonl"
    p.write_text(
        '{"test": "x", "tc_ids": ["TC-A-001"]}\n'
        '{"test": "x", "tc_ids": ["TC-B-002", "TC-A-001"]}\n'  # second contains A, B
        '{"test": "x", "tc_ids": ["TC-C-003"]}\n'              # adds C
    )
    # Union, first-seen order preserved
    assert g.load_sidecar(p) == {"x": ["TC-A-001", "TC-B-002", "TC-C-003"]}


def test_load_sidecar_merge_normalizes_underscores(tmp_path):
    p = tmp_path / "tc-map.jsonl"
    p.write_text(
        '{"test": "x", "tc_ids": ["TC_A_001"]}\n'
        '{"test": "x", "tc_ids": ["TC-A-001"]}\n'  # same after normalisation
    )
    assert g.load_sidecar(p) == {"x": ["TC-A-001"]}  # de-duplicated


# ── Truncate 信息流转 ─────────────────────────────────────────────────────────

def test_truncate_info_default_keeps_100(monkeypatch):
    monkeypatch.delenv("TC_INFO_KEEP", raising=False)
    info = "\n".join(f"[u {i}] line {i}" for i in range(150))
    out = g._truncate_info(info)
    lines = out.split("\n")
    assert len(lines) == 100
    assert lines[0] == "[u 50] line 50"
    assert lines[-1] == "[u 149] line 149"


def test_truncate_info_unbounded_when_zero(monkeypatch):
    monkeypatch.setenv("TC_INFO_KEEP", "0")
    info = "\n".join(f"line {i}" for i in range(5000))
    out = g._truncate_info(info)
    assert len(out.split("\n")) == 5000  # unbounded


def test_str_handles_rich_text_segments():
    # Bitable rich-text list of segments
    assert g._str([{"type": "text", "text": "Hello "}, {"type": "text", "text": "world"}]) == "Hello world"


def test_str_handles_string_list():
    assert g._str(["alpha", "beta"]) == "alphabeta"


def test_str_handles_select_option_dict():
    assert g._str({"name": "P0"}) == "P0"


def test_str_handles_scalar_and_empty():
    assert g._str("plain") == "plain"
    assert g._str("") == ""
    assert g._str(None) == ""
    assert g._str(42) == "42"


def test_truncate_info_honors_env(monkeypatch):
    monkeypatch.setenv("TC_INFO_KEEP", "5")
    info = "\n".join(f"e{i}" for i in range(10))
    assert g._truncate_info(info).split("\n") == ["e5", "e6", "e7", "e8", "e9"]


def test_truncate_info_short_unchanged(monkeypatch):
    monkeypatch.delenv("TC_INFO_KEEP", raising=False)
    info = "a\nb\nc"
    assert g._truncate_info(info) == "a\nb\nc"


def test_truncate_info_invalid_env_falls_back_to_default(monkeypatch):
    monkeypatch.setenv("TC_INFO_KEEP", "not-a-number")
    info = "\n".join(str(i) for i in range(200))
    assert len(g._truncate_info(info).split("\n")) == 100


# ── JUnit status mapping ──────────────────────────────────────────────────────

import xml.etree.ElementTree as ET  # noqa: E402


def _testcase(name="t", classname="m", inner_xml=""):
    return ET.fromstring(f'<testcase classname="{classname}" name="{name}">{inner_xml}</testcase>')


@pytest.mark.parametrize("reason,expected", [
    ("requires linux", "阻塞"),
    ("needs docker", "阻塞"),
    ("no device available", "阻塞"),
    ("service unavailable", "阻塞"),
    ("credential not set", "阻塞"),
    ("excluded for this iteration", "跳过"),
    ("deprecated feature", "跳过"),
    ("manually disabled", "跳过"),
])
def test_junit_status_skip_heuristic(reason, expected):
    el = _testcase(inner_xml=f'<skipped message="{reason}"/>')
    assert g._junit_status(el) == expected


def test_junit_status_failure():
    assert g._junit_status(_testcase(inner_xml="<failure>x</failure>")) == "失败"


def test_junit_status_error():
    assert g._junit_status(_testcase(inner_xml="<error>x</error>")) == "失败"


def test_junit_status_pass():
    assert g._junit_status(_testcase()) == "通过"


# ── parse_junit + sidecar join ────────────────────────────────────────────────

def test_parse_junit_sidecar_match_by_pytest_nodeid(tmp_path):
    j = tmp_path / "j.xml"
    j.write_text("""<?xml version="1.0"?>
<testsuites>
  <testsuite name="s">
    <testcase classname="tests.test_auth" name="test_login"/>
    <testcase classname="pkg" name="TestBulk"><failure>x</failure></testcase>
  </testsuite>
</testsuites>
""")
    sidecar = {
        "tests/test_auth.py::test_login": ["TC-SY-001"],
        "TestBulk": ["TC-SY-002"],
    }
    out = g.parse_junit(str(j), sidecar)
    assert out == {
        "linked": {"TC-SY-001": "通过", "TC-SY-002": "失败"},
        "untracked": [],
    }


def test_parse_junit_untracked(tmp_path):
    j = tmp_path / "j.xml"
    j.write_text("""<?xml version="1.0"?>
<testsuite name="s">
  <testcase classname="m" name="orphan_test"/>
  <testcase classname="m" name="another"><failure>x</failure></testcase>
</testsuite>""")
    out = g.parse_junit(str(j), {})
    assert out["linked"] == {}
    assert {u["name"] for u in out["untracked"]} == {"orphan_test", "another"}
    assert {u["status"] for u in out["untracked"]} == {"通过", "失败"}


def test_parse_junit_pessimistic_merge_within_suite(tmp_path):
    j = tmp_path / "j.xml"
    j.write_text("""<?xml version="1.0"?>
<testsuite name="s">
  <testcase classname="m" name="a"/>
  <testcase classname="m" name="b"><failure>x</failure></testcase>
</testsuite>""")
    sidecar = {"a": ["TC-X-001"], "b": ["TC-X-001"]}
    out = g.parse_junit(str(j), sidecar)
    assert out["linked"] == {"TC-X-001": "失败"}


def test_parse_junit_missing_file_returns_empty(capsys):
    out = g.parse_junit("/nonexistent/path.xml", {})
    assert out == {"linked": {}, "untracked": []}


# ── Coverage parsing ──────────────────────────────────────────────────────────

def test_parse_coverage_lines(tmp_path):
    p = tmp_path / "c.xml"
    p.write_text('<coverage line-rate="0.85" lines-covered="170" lines-valid="200"/>')
    assert g.parse_coverage(str(p)) == {"covered": 170, "valid": 200, "rate": 0.85}


def test_parse_coverage_rate_only(tmp_path):
    p = tmp_path / "c.xml"
    p.write_text('<coverage line-rate="0.92"/>')
    assert g.parse_coverage(str(p)) == {"rate": 0.92}


def test_parse_coverage_missing_file():
    assert g.parse_coverage("/nonexistent/c.xml") is None


def test_parse_coverage_malformed_xml(tmp_path):
    p = tmp_path / "c.xml"
    p.write_text("<not-xml")
    assert g.parse_coverage(str(p)) is None


def test_collect_coverage_sums_lines(tmp_path):
    c1 = tmp_path / "c1.xml"
    c1.write_text('<coverage lines-covered="100" lines-valid="200"/>')
    c2 = tmp_path / "c2.xml"
    c2.write_text('<coverage lines-covered="80" lines-valid="100"/>')
    suites = [{"coverage_file": str(c1)}, {"coverage_file": str(c2)}]
    agg = g.collect_coverage(suites)
    assert agg["covered"] == 180
    assert agg["valid"] == 300
    assert abs(agg["rate"] - 0.6) < 1e-9


def test_collect_coverage_line_based_wins_over_rate_only(tmp_path):
    c1 = tmp_path / "c1.xml"
    c1.write_text('<coverage lines-covered="50" lines-valid="100"/>')
    c2 = tmp_path / "c2.xml"
    c2.write_text('<coverage line-rate="0.99"/>')  # rate-only ignored when lines present
    agg = g.collect_coverage([{"coverage_file": str(c1)}, {"coverage_file": str(c2)}])
    assert agg == {"covered": 50, "valid": 100, "rate": 0.5}


def test_collect_coverage_none_when_no_files():
    assert g.collect_coverage([{}, {"coverage_file": "/nonexistent.xml"}]) is None


# ── md parser ─────────────────────────────────────────────────────────────────

SAMPLE_MD = """# Some doc

Intro text — should be ignored.

| 用例ID | 模块 | 功能点 | 优先级 | 测试层级 | 测试类型 | 前置条件 | 操作步骤 | 预期结果 |
|---|---|---|---|---|---|---|---|---|
| TC-SY-001 | 系统 | 登录 | P0 | e2e | ui-automation | 已注册 | 1. 输入<br>2. 提交 | 跳转 |
| TC-SY-002 | 系统 | 含 \\| 转义 | P1 | contract | api-automation |  |  |  |

Trailing text — ignored.
"""


def test_parse_md_table(tmp_path):
    p = tmp_path / "cases.md"
    p.write_text(SAMPLE_MD)
    rows = g.parse_md_table(str(p))
    assert set(rows) == {"TC-SY-001", "TC-SY-002"}
    assert rows["TC-SY-001"]["操作步骤"] == "1. 输入\n2. 提交"
    assert rows["TC-SY-001"]["测试层级"] == "e2e"
    assert rows["TC-SY-002"]["测试类型"] == "api-automation"
    assert rows["TC-SY-002"]["功能点"] == "含 | 转义"


def test_parse_old_md_table_does_not_invent_new_definition_fields(tmp_path):
    p = tmp_path / "old-cases.md"
    p.write_text(
        "| 用例ID | 模块 | 功能点 | 优先级 | 前置条件 | 操作步骤 | 预期结果 |\n"
        "|---|---|---|---|---|---|---|\n"
        "| TC-OLD-001 | 系统 | 登录 | P0 | 已注册 | 提交 | 跳转 |\n"
    )
    rows = g.parse_md_table(str(p))
    assert "测试层级" not in rows["TC-OLD-001"]
    assert "测试类型" not in rows["TC-OLD-001"]
    assert rows.definition_fields_present == {"模块", "功能点", "优先级", "前置条件", "操作步骤", "预期结果"}


def test_parse_md_table_no_header_warns(tmp_path, capsys):
    p = tmp_path / "x.md"
    p.write_text("no tables here, just prose")
    assert g.parse_md_table(str(p)) == {}
    err = capsys.readouterr().err
    assert "no markdown table header" in err


def test_split_md_row_handles_escape():
    cells = g._split_md_row("| a | b \\| c | d |")
    assert cells == ["a", "b | c", "d"]


def test_md_cell_escapes_pipe_and_newline():
    assert g._md_cell("a|b") == "a\\|b"
    assert g._md_cell("a\nb") == "a<br>b"
    assert g._md_cell("a\r\nb") == "a<br>b"
    assert g._md_cell("") == ""
    assert g._md_cell("plain") == "plain"


def test_md_cell_roundtrip_through_parser():
    # Emit with _md_cell, parse with _split_md_row, original pipe survives
    line = "| " + " | ".join(g._md_cell(c) for c in ["a|x", "b", "c"]) + " |"
    assert g._split_md_row(line) == ["a|x", "b", "c"]


# ── diff_md_vs_bitable ────────────────────────────────────────────────────────

def _rec(tc_id, status="未测试", **fields):
    f = {"用例ID": tc_id, "状态": status, "模块": "", "功能点": "",
         "优先级": "", "测试层级": "", "测试类型": "", "前置条件": "", "操作步骤": "", "预期结果": ""}
    f.update(fields)
    return {"record_id": f"r-{tc_id}", "fields": f}


def test_diff_added_removed_changed_and_deprecated_exclusion():
    md = {
        "TC-1": {"模块": "M", "功能点": "f1", "优先级": "P0", "前置条件": "", "操作步骤": "step", "预期结果": "ok"},
        "TC-2": {"模块": "M", "功能点": "f2", "优先级": "P1", "前置条件": "", "操作步骤": "step", "预期结果": "ok md"},
        "TC-3": {"模块": "M", "功能点": "f3", "优先级": "P2", "前置条件": "", "操作步骤": "", "预期结果": ""},
    }
    records = [
        _rec("TC-1", 模块="M", 功能点="f1", 优先级="P0", 前置条件="", 操作步骤="step", 预期结果="ok"),
        _rec("TC-2", 模块="M", 功能点="f2", 优先级="P1", 前置条件="", 操作步骤="step", 预期结果="ok BITABLE"),
        # TC-3 missing from Bitable → added
        _rec("TC-4", 模块="M", 功能点="f4", 优先级="P0"),  # in Bitable, not md → removed
        _rec("TC-5", status="废弃", 模块="M", 功能点="f5"),  # 废弃 → excluded from removed
    ]
    diff = g.diff_md_vs_bitable(md, records)
    assert [a["tc_id"] for a in diff["added"]] == ["TC-3"]
    assert [r["tc_id"] for r in diff["removed"]] == ["TC-4"]  # TC-5 excluded
    assert [(c["tc_id"], c["field"]) for c in diff["changed"]] == [("TC-2", "预期结果")]


def test_diff_whitespace_normalized():
    md = {"TC-1": {"模块": "M", "功能点": "f", "优先级": "P0", "前置条件": "", "操作步骤": "  a   b\n  c  ", "预期结果": ""}}
    records = [_rec("TC-1", 模块="M", 功能点="f", 优先级="P0", 操作步骤="a b c")]
    diff = g.diff_md_vs_bitable(md, records)
    assert diff["changed"] == []  # whitespace differences ignored


def test_diff_detects_test_layer_and_test_type_changes():
    md = {
        "TC-1": {
            "模块": "M",
            "功能点": "f",
            "优先级": "P0",
            "测试层级": "e2e",
            "测试类型": "ui-automation",
            "前置条件": "",
            "操作步骤": "step",
            "预期结果": "ok",
        }
    }
    records = [
        _rec("TC-1", 模块="M", 功能点="f", 优先级="P0",
             测试层级="contract", 测试类型="api-automation",
             前置条件="", 操作步骤="step", 预期结果="ok")
    ]
    diff = g.diff_md_vs_bitable(md, records)
    assert [(c["tc_id"], c["field"]) for c in diff["changed"]] == [
        ("TC-1", "测试层级"),
        ("TC-1", "测试类型"),
    ]


def test_diff_skips_new_definition_fields_when_old_md_lacks_columns():
    md = g.MdTable({
        "TC-1": {
            "模块": "M",
            "功能点": "f",
            "优先级": "P0",
            "前置条件": "",
            "操作步骤": "step",
            "预期结果": "ok",
        }
    }, definition_fields_present={"模块", "功能点", "优先级", "前置条件", "操作步骤", "预期结果"})
    records = [
        _rec("TC-1", 模块="M", 功能点="f", 优先级="P0",
             测试层级="e2e", 测试类型="ui-automation",
             前置条件="", 操作步骤="step", 预期结果="ok")
    ]
    diff = g.diff_md_vs_bitable(md, records)
    assert diff["changed"] == []


def test_diff_detects_missing_new_fields_when_md_schema_unknown():
    md = {
        "TC-1": {
            "模块": "M",
            "功能点": "f",
            "优先级": "P0",
            "前置条件": "",
            "操作步骤": "step",
            "预期结果": "ok",
        }
    }
    records = [
        _rec("TC-1", 模块="M", 功能点="f", 优先级="P0",
             测试层级="e2e", 测试类型="ui-automation",
             前置条件="", 操作步骤="step", 预期结果="ok")
    ]
    diff = g.diff_md_vs_bitable(md, records)
    assert [(c["tc_id"], c["field"]) for c in diff["changed"]] == [
        ("TC-1", "测试层级"),
        ("TC-1", "测试类型"),
    ]


# ── detect_orphans ────────────────────────────────────────────────────────────

def test_detect_orphans():
    records = [
        _rec("TC-A", status="通过"),
        _rec("TC-B", status="废弃"),
    ]
    results = {"TC-A": "通过", "TC-B": "失败", "TC-C": "通过"}
    o = g.detect_orphans(records, results)
    assert o["deprecated_in_tests"] == ["TC-B"]
    assert o["missing_in_bitable"] == ["TC-C"]


def test_detect_orphans_clean():
    records = [_rec("TC-A", status="通过")]
    o = g.detect_orphans(records, {"TC-A": "通过"})
    assert o == {"deprecated_in_tests": [], "missing_in_bitable": []}


# ── aggregate ─────────────────────────────────────────────────────────────────

def test_aggregate_excludes_deprecated_from_total():
    records = [
        _rec("TC-1", status="通过", 模块="M", 优先级="P0"),
        _rec("TC-2", status="失败", 模块="M", 优先级="P1"),
        _rec("TC-3", status="废弃", 模块="M", 优先级="P2"),
    ]
    agg = g.aggregate(records)
    assert agg["total"] == 2  # 废弃 not counted
    assert agg["deprecated_count"] == 1
    assert agg["by_status"]["通过"] == 1
    assert agg["by_status"]["失败"] == 1
    assert agg["pass_rate"] == "50.0%"


def test_aggregate_p0_rate():
    records = [
        _rec("TC-1", status="通过", 优先级="P0"),
        _rec("TC-2", status="通过", 优先级="P0"),
        _rec("TC-3", status="失败", 优先级="P0"),
        _rec("TC-4", status="通过", 优先级="P1"),
    ]
    agg = g.aggregate(records)
    assert agg["p0_total"] == 3
    assert agg["p0_pass"] == 2
    assert agg["p0_pass_rate"] == "66.7%"


# ── print_inventory / next_id (capsys) ────────────────────────────────────────

def test_print_inventory_human(capsys):
    records = [
        _rec("TC-SY-001", status="通过", 模块="系统", 功能点="登录", 优先级="P0"),
        _rec("TC-SY-002", status="未测试", 模块="系统", 功能点="注销", 优先级="P1"),
        _rec("TC-OLD-001", status="废弃", 模块="系统", 功能点="旧"),
    ]
    g.print_inventory(records, as_md=False)
    out = capsys.readouterr().out
    assert "active: 2" in out
    assert "废弃: 1" in out
    assert "TC-SY-001" in out
    assert "TC-OLD-001" in out  # in deprecated section


def test_print_inventory_md(capsys):
    records = [_rec("TC-X-001", status="通过", 模块="X", 功能点="f", 优先级="P0",
                    测试层级="e2e", 测试类型="ui-automation",
                    操作步骤="a\nb")]
    g.print_inventory(records, as_md=True)
    out = capsys.readouterr().out
    assert "| 用例ID | 模块" in out
    assert "TC-X-001 | X | f" in out
    assert "e2e | ui-automation" in out
    assert "a<br>b" in out  # newlines collapsed for md cell


def test_aggregate_tracks_layer_and_test_type_breakdowns():
    records = [
        _rec("TC-1", status="通过", 模块="M", 优先级="P0", 测试层级="e2e", 测试类型="ui-automation"),
        _rec("TC-2", status="失败", 模块="M", 优先级="P1", 测试层级="contract", 测试类型="api-automation"),
        _rec("TC-3", status="未测试", 模块="N", 优先级="P2", 测试层级="manual", 测试类型="manual-verification"),
    ]
    agg = g.aggregate(records)
    assert agg["by_layer"]["e2e"]["通过"] == 1
    assert agg["by_layer"]["contract"]["失败"] == 1
    assert agg["by_test_type"]["ui-automation"]["通过"] == 1
    assert agg["by_test_type"]["manual-verification"]["未测试"] == 1


def test_aggregate_omits_layer_and_test_type_sections_when_fields_missing():
    agg = g.aggregate([
        _rec("TC-1", status="通过", 模块="M", 优先级="P0"),
        _rec("TC-2", status="失败", 模块="M", 优先级="P1"),
    ])
    assert agg["by_layer"] == {}
    assert agg["by_test_type"] == {}
    md = g.build_markdown(agg, "alice", "本地", "v1")
    assert "按测试层级统计" not in md
    assert "按测试类型统计" not in md


def test_print_next_ids(capsys):
    records = [
        _rec("TC-SY-005"),
        _rec("TC-AU-010"),
        _rec("weird-id"),
    ]
    g.print_next_ids(records)
    out = capsys.readouterr().out
    assert "TC-AU-011" in out
    assert "TC-SY-006" in out
    assert "weird-id" in out  # surfaced as non-canonical


# ── vs-last-run diff ──────────────────────────────────────────────────────────

def test_diff_vs_last_run_first_time():
    diff = g.diff_vs_last_run({"TC-A": "通过"}, {})
    assert diff["had_previous"] is False
    assert diff["newly_seen"] == ["TC-A"]
    assert diff["new_failures"] == []


def test_diff_vs_last_run_new_failure():
    prev = {"linked": {"TC-A": "通过", "TC-B": "通过"}}
    cur = {"TC-A": "通过", "TC-B": "失败"}
    diff = g.diff_vs_last_run(cur, prev)
    assert diff["new_failures"] == ["TC-B"]
    assert diff["fixed"] == []
    assert diff["flips"] == []


def test_diff_vs_last_run_fixed():
    prev = {"linked": {"TC-A": "失败"}}
    diff = g.diff_vs_last_run({"TC-A": "通过"}, prev)
    assert diff["fixed"] == ["TC-A"]


def test_diff_vs_last_run_flip_other():
    prev = {"linked": {"TC-A": "通过"}}
    diff = g.diff_vs_last_run({"TC-A": "跳过"}, prev)
    assert diff["new_failures"] == []
    assert diff["fixed"] == []
    assert diff["flips"] == [{"tc_id": "TC-A", "from": "通过", "to": "跳过"}]


def test_diff_vs_last_run_no_longer_seen():
    prev = {"linked": {"TC-A": "通过", "TC-B": "通过"}}
    diff = g.diff_vs_last_run({"TC-A": "通过"}, prev)
    assert diff["no_longer_seen"] == ["TC-B"]


def test_diff_vs_last_run_newly_seen_failing():
    prev = {"linked": {"TC-A": "通过"}}
    diff = g.diff_vs_last_run({"TC-A": "通过", "TC-B": "失败"}, prev)
    assert diff["newly_seen"] == ["TC-B"]
    assert diff["new_failures"] == ["TC-B"]  # newly seen AND failing counts as new failure


def test_save_and_load_last_run(tmp_path):
    p = tmp_path / "last.json"
    g.save_last_run(p, {"TC-A": "通过", "TC-B": "失败"})
    assert p.exists()
    loaded = g.load_last_run(p)
    assert loaded["linked"] == {"TC-A": "通过", "TC-B": "失败"}
    assert "timestamp" in loaded


def test_load_last_run_missing_file_returns_empty(tmp_path):
    assert g.load_last_run(tmp_path / "missing.json") == {}


def test_load_last_run_corrupt_file_returns_empty(tmp_path):
    p = tmp_path / "corrupt.json"
    p.write_text("not valid json {")
    assert g.load_last_run(p) == {}


def test_load_last_run_rejects_old_schema(tmp_path):
    """Snapshots without schema_version (or with an older one) are treated as
    cold-start so a schema change (e.g. minimal-mode namespace prefixes) won't
    flood the next report with phantom newly_seen / no_longer_seen entries."""
    p = tmp_path / "old.json"
    # Old format: no schema_version field
    p.write_text(json.dumps({"timestamp": "x", "linked": {"TC-A": "通过"}}))
    assert g.load_last_run(p) == {}


def test_save_last_run_writes_current_schema(tmp_path):
    p = tmp_path / "lr.json"
    g.save_last_run(p, {"TC-A": "通过"})
    snap = json.loads(p.read_text())
    assert snap["schema_version"] == g.LAST_RUN_SCHEMA_VERSION


def test_load_config_rejects_half_populated_bitable(tmp_path):
    p = tmp_path / ".report-config.json"
    p.write_text(json.dumps({"base_token": "BAS123", "table_id": ""}))
    with pytest.raises(ValueError, match="both be set"):
        g.load_config(str(p))


def test_load_config_accepts_minimal_mode(tmp_path):
    p = tmp_path / ".report-config.json"
    p.write_text(json.dumps({"base_token": "", "table_id": "", "test_suites": []}))
    cfg = g.load_config(str(p))
    assert cfg == {"base_token": "", "table_id": "", "test_suites": []}


def test_collect_results_flags_missing_files(tmp_path, monkeypatch):
    """Suites configured but JUnit XML missing → tracked in missing_files for the gate."""
    monkeypatch.setenv("TC_SIDECAR", str(tmp_path / "tc-map.jsonl"))
    suites = [
        {"name": "s1", "results_file": str(tmp_path / "exists.xml")},
        {"name": "s2", "results_file": str(tmp_path / "absent.xml")},
    ]
    (tmp_path / "exists.xml").write_text(
        '<?xml version="1.0"?><testsuite name="s1"><testcase classname="m" name="t1"/></testsuite>'
    )
    r = g.collect_results(suites)
    assert r["parsed_suites"] == 1
    assert r["missing_files"] == [str(tmp_path / "absent.xml")]


def test_residual_risk_section_all_green():
    agg = {"by_module": {}, "by_status": {}, "p0_total": 0, "p0_pass": 0, "p0_blocking": []}
    md = "\n".join(g._residual_risk_section(agg, [], {"missing_files": []}))
    assert "覆盖与残余风险" in md
    assert "所有活跃模块均无失败" in md


def test_residual_risk_section_surfaces_weak_modules():
    agg = {
        "by_module": {"系统": {"_total": 5, "通过": 3, "失败": 1, "未测试": 1}},
        "by_status": {}, "p0_total": 0, "p0_pass": 0, "p0_blocking": [],
    }
    md = "\n".join(g._residual_risk_section(agg, [], {"missing_files": []}))
    assert "模块未达「绿色」标准" in md
    assert "系统" in md


def test_residual_risk_section_calls_out_infra_failure():
    agg = {"by_module": {}, "by_status": {}, "p0_total": 0, "p0_pass": 0, "p0_blocking": []}
    md = "\n".join(g._residual_risk_section(agg, [], {"missing_files": ["/a.xml", "/b.xml"]}))
    assert "🚨 基础设施失败" in md
    assert "/a.xml" in md
    assert "/b.xml" in md


def test_parse_matrix_tcs(tmp_path):
    p = tmp_path / "test-matrix.md"
    p.write_text("""# Test Matrix

| 模块 | unit | contract | integration | e2e | manual | blocked |
|---|---|---|---|---|---|---|
| 登录 | TC-SY-001 | — | TC-SY-002 | TC-SY-003 | — | — |
| 支付 | TC-PY-001, TC-PY-002 | TC-PY-006 | — | — | TC-PY-008 | TC-PY-009 (wait sandbox · @alice) |
""")
    out = g.parse_matrix_tcs(str(p))
    assert "TC-SY-001" in out["unit"]
    assert "TC-PY-001" in out["unit"] and "TC-PY-002" in out["unit"]
    assert out["e2e"] == ["TC-SY-003"]
    assert out["blocked"] == ["TC-PY-009"]
    assert out.get("contract") == ["TC-PY-006"]


def test_validate_matrix_drift(tmp_path):
    p = tmp_path / "matrix.md"
    p.write_text("""
| 模块 | unit | integration |
|---|---|---|
| sys | TC-SY-001, TC-SY-999 | TC-SY-003 |
""")
    records = [
        _rec("TC-SY-001"),                  # in matrix + bitable → ok
        _rec("TC-SY-002"),                  # in bitable, NOT in matrix
        _rec("TC-SY-003", status="废弃"),   # in matrix but 废弃
        # TC-SY-999 absent everywhere except matrix
    ]
    r = g.validate_matrix(str(p), records)
    assert r["in_matrix_not_bitable"] == ["TC-SY-999"]
    assert r["in_bitable_not_matrix"] == ["TC-SY-002"]
    assert r["deprecated_in_matrix"] == ["TC-SY-003"]
    assert r["layer_mismatches"] == []


def test_validate_matrix_layer_enforcement_is_optional(tmp_path):
    p = tmp_path / "matrix.md"
    p.write_text("""
| 模块 | unit | e2e |
|---|---|---|
| sys | TC-SY-001 | TC-SY-002 |
""")
    records = [_rec("TC-SY-001"), _rec("TC-SY-002")]
    r = g.validate_matrix(str(p), records)
    assert r["layer_mismatches"] == []
    assert r["actual_tcs_by_layer"] == {}
    assert r["unverified_layers"] == ["e2e", "unit"]


def test_validate_matrix_configured_layers_require_evidence(tmp_path):
    p = tmp_path / "matrix.md"
    p.write_text("""
| 模块 | unit |
|---|---|
| sys | TC-SY-001 |
""")
    records = [_rec("TC-SY-001")]
    r = g.validate_matrix(str(p), records, actual_layers={}, configured_layers=["unit"])
    assert r["configured_layers"] == ["unit"]
    assert r["layer_mismatches"] == [
        {"tc_id": "TC-SY-001", "declared": "unit", "actual": []},
    ]


def test_validate_matrix_only_enforces_configured_layers(tmp_path):
    p = tmp_path / "matrix.md"
    p.write_text("""
| 模块 | unit | e2e |
|---|---|---|
| sys | TC-SY-001 | TC-SY-002 |
""")
    records = [_rec("TC-SY-001"), _rec("TC-SY-002")]
    r = g.validate_matrix(str(p), records, actual_layers={"unit": ["TC-SY-001"]}, configured_layers=["unit"])
    assert r["configured_layers"] == ["unit"]
    assert r["layer_mismatches"] == []
    assert r["unverified_layers"] == ["e2e"]


def test_validate_matrix_layer_mismatch_when_actual_layers_configured(tmp_path):
    p = tmp_path / "matrix.md"
    p.write_text("""
| 模块 | unit | e2e | manual | blocked |
|---|---|---|---|---|
| sys | TC-SY-001 | TC-SY-002 | TC-SY-003 | TC-SY-004 |
""")
    records = [_rec("TC-SY-001"), _rec("TC-SY-002"), _rec("TC-SY-003"), _rec("TC-SY-004")]
    r = g.validate_matrix(
        str(p),
        records,
        {"unit": ["TC-SY-001"], "contract": ["TC-SY-002"]},
        configured_layers=["unit", "e2e"],
    )
    assert r["layer_mismatches"] == [
        {"tc_id": "TC-SY-002", "declared": "e2e", "actual": ["contract"]},
    ]


def test_validate_matrix_layer_aliases(tmp_path):
    p = tmp_path / "matrix.md"
    p.write_text("""
| 模块 | contract | e2e |
|---|---|---|
| sys | TC-SY-001 | TC-SY-002 |
""")
    records = [_rec("TC-SY-001"), _rec("TC-SY-002")]
    r = g.validate_matrix(str(p), records, {"api": ["TC-SY-001"], "host-smoke": ["TC-SY-002"]})
    assert r["matrix_tcs_by_layer"] == {"contract": ["TC-SY-001"], "e2e": ["TC-SY-002"]}
    assert r["layer_mismatches"] == []


def test_parse_matrix_tcs_does_not_treat_suite_alias_headers_as_layer_claims(tmp_path):
    p = tmp_path / "matrix.md"
    p.write_text("""
| 模块 | smoke | host | api |
|---|---|---|
| sys | TC-SY-001 | TC-SY-002 | TC-SY-003 |
""")
    assert g.parse_matrix_tcs(str(p)) == {}


def test_extra_matrix_columns_count_for_presence_not_layer_enforcement(tmp_path):
    p = tmp_path / "matrix.md"
    p.write_text("""
| 模块 | unit | fuzz |
|---|---|---|
| sys | TC-SY-001 | TC-SY-002 |
""")
    r = g.validate_matrix(str(p), [_rec("TC-SY-001"), _rec("TC-SY-002")])
    assert r["matrix_tcs_by_layer"] == {"unit": ["TC-SY-001"]}
    assert r["in_bitable_not_matrix"] == []


def test_non_evidence_matrix_columns_do_not_count_for_presence(tmp_path):
    p = tmp_path / "matrix.md"
    p.write_text("""
| 模块 | unit | 备注 |
|---|---|---|
| sys | TC-SY-001 | renamed from TC-SY-OLD |
""")
    r = g.validate_matrix(str(p), [_rec("TC-SY-001")])
    assert r["in_matrix_not_bitable"] == []


def test_validate_matrix_unparseable_header_is_parse_error_not_total_missing(tmp_path):
    p = tmp_path / "matrix.md"
    p.write_text("""
| 模块 | 冒烟 | 主机 |
|---|---|---|
| sys | TC-SY-001 | TC-SY-002 |
""")
    r = g.validate_matrix(str(p), [_rec("TC-SY-001"), _rec("TC-SY-002")])
    assert r["parse_error"] == "no canonical matrix layer header found"
    assert r["in_bitable_not_matrix"] == []
    assert g._matrix_validation_has_drift(r)


def test_validate_matrix_row_cell_count_mismatch_is_parse_error(tmp_path):
    p = tmp_path / "matrix.md"
    p.write_text("""
| 模块 | unit |
|---|---|
| sys | TC-SY-001 | TC-SY-002 |
""")
    r = g.validate_matrix(str(p), [_rec("TC-SY-001"), _rec("TC-SY-002")])
    assert r["parse_error"] == "matrix row 4 has 3 cells; header has 2"
    assert r["in_bitable_not_matrix"] == []
    assert g._matrix_validation_has_drift(r)


def test_validate_matrix_ragged_row_with_missing_trailing_cells_is_valid(tmp_path):
    p = tmp_path / "matrix.md"
    p.write_text("""
| 模块 | unit | contract | integration | e2e | manual | blocked |
|---|---|---|---|---|---|---|
| 登录 | TC-SY-001 |
""")
    r = g.validate_matrix(str(p), [_rec("TC-SY-001")])
    assert r["parse_error"] == ""
    assert r["matrix_tcs_by_layer"] == {"unit": ["TC-SY-001"]}
    assert r["in_bitable_not_matrix"] == []


def test_validate_matrix_escaped_pipe_in_cell_does_not_split_column(tmp_path):
    p = tmp_path / "matrix.md"
    p.write_text(r"""
| 模块 | unit | manual |
|---|---|---|
| pay | TC-PY-001 (cert a\|b) | TC-PY-002 |
""")
    r = g.validate_matrix(str(p), [_rec("TC-PY-001"), _rec("TC-PY-002")])
    assert r["parse_error"] == ""
    assert r["matrix_tcs_by_layer"] == {"unit": ["TC-PY-001"], "manual": ["TC-PY-002"]}
    assert r["in_bitable_not_matrix"] == []


def test_validate_matrix_multiple_tables_do_not_share_header(tmp_path):
    p = tmp_path / "matrix.md"
    p.write_text("""
| 模块 | unit |
|---|---|
| sys | TC-SY-001 |

| 模块 | unit | e2e |
|---|---|---|
| pay | TC-PY-001 | TC-PY-002 |
""")
    r = g.validate_matrix(str(p), [_rec("TC-SY-001"), _rec("TC-PY-001"), _rec("TC-PY-002")])
    assert r["parse_error"] == ""
    assert r["in_bitable_not_matrix"] == []


def test_validate_matrix_adjacent_tables_without_blank_line_do_not_share_header(tmp_path):
    p = tmp_path / "matrix.md"
    p.write_text("""
| 模块 | unit |
|---|---|
| sys | TC-SY-001 |
| 模块 | e2e |
|---|---|
| pay | TC-PY-002 |
""")
    r = g.validate_matrix(str(p), [_rec("TC-SY-001"), _rec("TC-PY-002")])
    assert r["parse_error"] == ""
    assert r["matrix_tcs_by_layer"] == {"unit": ["TC-SY-001"], "e2e": ["TC-PY-002"]}
    assert r["in_bitable_not_matrix"] == []


def test_validate_matrix_data_cell_named_like_layer_is_not_header(tmp_path):
    p = tmp_path / "matrix.md"
    p.write_text("""
| 模块 | unit | 备注 |
|---|---|---|
| sys | TC-SY-001 | e2e |
| pay | TC-PY-001 | manual |
""")
    r = g.validate_matrix(str(p), [_rec("TC-SY-001"), _rec("TC-PY-001")])
    assert r["parse_error"] == ""
    assert r["in_bitable_not_matrix"] == []
    assert r["matrix_tcs_by_layer"] == {"unit": ["TC-SY-001", "TC-PY-001"]}


def test_validate_matrix_bare_layer_words_in_data_row_do_not_reset_header(tmp_path):
    p = tmp_path / "matrix.md"
    p.write_text("""
| 模块 | unit | e2e |
|---|---|---|
| pay | manual | blocked |
| auth | TC-SY-001 | TC-SY-002 |
""")
    r = g.validate_matrix(str(p), [_rec("TC-SY-001"), _rec("TC-SY-002")])
    assert r["parse_error"] == ""
    assert r["matrix_tcs_by_layer"] == {"unit": ["TC-SY-001"], "e2e": ["TC-SY-002"]}
    assert r["in_bitable_not_matrix"] == []


def test_validate_matrix_single_layer_header_with_noncanonical_subject(tmp_path):
    p = tmp_path / "matrix.md"
    p.write_text("""
| 服务 | unit |
|---|---|
| auth | TC-SY-001 |
""")
    r = g.validate_matrix(str(p), [_rec("TC-SY-001")])
    assert r["parse_error"] == ""
    assert r["matrix_tcs_by_layer"] == {"unit": ["TC-SY-001"]}
    assert r["in_bitable_not_matrix"] == []


def test_validate_matrix_empty_declared_layer_is_not_unverified(tmp_path):
    p = tmp_path / "matrix.md"
    p.write_text("""
| 模块 | unit | e2e |
|---|---|---|
| sys | TC-SY-001 | — |
""")
    r = g.validate_matrix(str(p), [_rec("TC-SY-001")], configured_layers=["unit"])
    assert r["unverified_layers"] == []


def test_validate_matrix_missing_file_is_parse_error(tmp_path):
    r = g.validate_matrix(str(tmp_path / "missing.md"), [_rec("TC-SY-001")])
    assert r["parse_error"] == "matrix file not found"
    assert r["in_bitable_not_matrix"] == []
    assert g._matrix_validation_has_drift(r)


def test_validate_matrix_empty_canonical_matrix_reports_missing_tcs(tmp_path):
    p = tmp_path / "matrix.md"
    p.write_text("""
| 模块 | unit | e2e |
|---|---|---|
""")
    r = g.validate_matrix(str(p), [_rec("TC-SY-001"), _rec("TC-SY-002")])
    assert r["parse_error"] == ""
    assert r["in_bitable_not_matrix"] == ["TC-SY-001", "TC-SY-002"]


def test_validate_matrix_unlabeled_suite_evidence_is_reported(tmp_path):
    p = tmp_path / "matrix.md"
    p.write_text("""
| 模块 | unit |
|---|---|
| sys | TC-SY-001 |
""")
    records = [_rec("TC-SY-001")]
    r = g.validate_matrix(
        str(p),
        records,
        actual_layers={},
        configured_layers=["unit"],
        unlayered_tcs=["TC-SY-001"],
    )
    assert r["layer_mismatches"] == [
        {"tc_id": "TC-SY-001", "declared": "unit", "actual": ["unlabeled-suite"]},
    ]


def test_matrix_validation_has_drift():
    assert not g._matrix_validation_has_drift({
        "in_matrix_not_bitable": [],
        "in_bitable_not_matrix": [],
        "deprecated_in_matrix": [],
        "layer_mismatches": [],
    })
    assert g._matrix_validation_has_drift({
        "in_matrix_not_bitable": [],
        "in_bitable_not_matrix": [],
        "deprecated_in_matrix": [],
        "layer_mismatches": [{"tc_id": "TC-SY-001"}],
    })
    assert not g._matrix_validation_has_drift({
        "in_matrix_not_bitable": [],
        "in_bitable_not_matrix": [],
        "deprecated_in_matrix": [],
        "layer_mismatches": [],
        "unverified_layers": ["e2e"],
    })


def test_matrix_gate_should_fail_on_missing_results():
    report = {
        "in_matrix_not_bitable": [],
        "in_bitable_not_matrix": [],
        "deprecated_in_matrix": [],
        "layer_mismatches": [],
        "unverified_layers": ["e2e"],
    }
    report["matrix_tcs_by_layer"] = {"e2e": ["TC-SY-001"]}
    assert g._matrix_gate_should_fail(report, {"missing_layered_layers": ["e2e"], "missing_layered_files": ["missing.xml"]})
    assert not g._matrix_gate_should_fail(report, {"missing_layered_files": [], "missing_files": []})
    configured_report = dict(report)
    configured_report["configured_layers"] = ["unit"]
    assert g._matrix_gate_should_fail(configured_report, {"missing_layered_files": [], "missing_files": []})
    clean_report = dict(report)
    clean_report["unverified_layers"] = []
    assert g._matrix_gate_should_fail(clean_report, {"missing_layered_files": [], "missing_files": ["other.xml"]})


def test_matrix_gate_does_not_fail_excluded_layer_when_fast_layer_exists():
    report = {
        "in_matrix_not_bitable": [],
        "in_bitable_not_matrix": [],
        "deprecated_in_matrix": [],
        "layer_mismatches": [],
        "matrix_tcs_by_layer": {"e2e": ["TC-SY-001"]},
        "configured_layers": ["e2e"],
    }
    results = {"excluded_layered_layers": ["e2e"], "missing_layered_layers": []}
    assert not g._matrix_gate_should_fail(report, results)


def test_validate_matrix_empty_configured_layers_disables_layer_enforcement(tmp_path):
    p = tmp_path / "matrix.md"
    p.write_text("""
| 模块 | e2e |
|---|---|
| sys | TC-SY-001 |
""")
    records = [_rec("TC-SY-001")]
    r = g.validate_matrix(
        str(p),
        records,
        actual_layers={"unit": ["TC-SY-001"]},
        configured_layers=[],
    )
    assert r["configured_layers"] == []
    assert r["actual_tcs_by_layer"] == {"unit": ["TC-SY-001"]}
    assert r["layer_mismatches"] == []
    assert r["unverified_layers"] == ["e2e"]


def test_print_matrix_validation_does_not_print_green_when_layers_unverified(capsys):
    g.print_matrix_validation({
        "in_matrix_not_bitable": [],
        "in_bitable_not_matrix": [],
        "deprecated_in_matrix": [],
        "layer_mismatches": [],
        "matrix_tcs_by_layer": {"e2e": ["TC-SY-001"]},
        "actual_tcs_by_layer": {},
        "configured_layers": ["unit"],
        "unverified_layers": ["e2e"],
    })
    out = capsys.readouterr().out
    assert "Unverified matrix layers: e2e" in out
    assert "✅ test-matrix.md and Bitable are in sync." not in out


def test_print_matrix_validation_warning_when_unverified_layers_are_nonblocking(capsys):
    g.print_matrix_validation({
        "in_matrix_not_bitable": [],
        "in_bitable_not_matrix": [],
        "deprecated_in_matrix": [],
        "layer_mismatches": [],
        "matrix_tcs_by_layer": {"e2e": ["TC-SY-001"]},
        "actual_tcs_by_layer": {},
        "configured_layers": [],
        "unverified_layers": ["e2e"],
    })
    out = capsys.readouterr().out
    assert "Unverified matrix layers: e2e" in out
    assert "⚠ test-matrix.md and Bitable TC presence are in sync; layer coverage is unverified." in out
    assert "✅ test-matrix.md and Bitable" not in out


def test_print_matrix_validation_parse_error_has_actionable_message(capsys):
    g.print_matrix_validation({
        "in_matrix_not_bitable": [],
        "in_bitable_not_matrix": [],
        "deprecated_in_matrix": [],
        "layer_mismatches": [],
        "matrix_tcs_by_layer": {},
        "actual_tcs_by_layer": {},
        "configured_layers": [],
        "unverified_layers": [],
        "parse_error": "no canonical matrix layer header found",
    })
    out = capsys.readouterr().out
    assert "Matrix parse error: no canonical matrix layer header found" in out
    assert "Use canonical headers: unit, contract, integration, e2e, manual, blocked." in out
    assert "✅ test-matrix.md and Bitable are in sync." not in out


def test_print_matrix_validation_reports_excluded_claimed_layers(capsys):
    g.print_matrix_validation({
        "in_matrix_not_bitable": [],
        "in_bitable_not_matrix": [],
        "deprecated_in_matrix": [],
        "layer_mismatches": [],
        "matrix_tcs_by_layer": {"e2e": ["TC-SY-001"]},
        "actual_tcs_by_layer": {},
        "configured_layers": [],
        "unverified_layers": ["e2e"],
        "parse_error": "",
    }, {"excluded_layered_layers": ["e2e"]})
    out = capsys.readouterr().out
    assert "Excluded matrix-gate layers still claimed in matrix: e2e" in out
    assert "Matrix claims automated layers that are excluded from the matrix gate" in out
    assert "✅ test-matrix.md and Bitable" not in out


def test_print_matrix_validation_ignores_excluded_layer_when_fast_layer_configured(capsys):
    g.print_matrix_validation({
        "in_matrix_not_bitable": [],
        "in_bitable_not_matrix": [],
        "deprecated_in_matrix": [],
        "layer_mismatches": [],
        "matrix_tcs_by_layer": {"e2e": ["TC-SY-001"]},
        "actual_tcs_by_layer": {"e2e": ["TC-SY-001"]},
        "configured_layers": ["e2e"],
        "unverified_layers": [],
        "parse_error": "",
    }, {"excluded_layered_layers": ["e2e"]})
    out = capsys.readouterr().out
    assert "Excluded matrix-gate layers still claimed" not in out
    assert "✅ test-matrix.md and Bitable are in sync." in out


def test_print_matrix_validation_does_not_print_green_when_layered_xml_missing(capsys):
    g.print_matrix_validation({
        "in_matrix_not_bitable": [],
        "in_bitable_not_matrix": [],
        "deprecated_in_matrix": [],
        "layer_mismatches": [],
        "matrix_tcs_by_layer": {"e2e": ["TC-SY-001"]},
        "actual_tcs_by_layer": {},
        "configured_layers": ["e2e"],
        "unverified_layers": [],
    }, {"missing_layered_files": ["missing.xml"]})
    out = capsys.readouterr().out
    assert "Missing layered JUnit XML: 1 file(s)" in out
    assert "Configured layer suites did not produce JUnit XML" in out
    assert "✅ test-matrix.md and Bitable are in sync." not in out


def test_print_matrix_validation_does_not_print_green_when_xml_missing(capsys):
    g.print_matrix_validation({
        "in_matrix_not_bitable": [],
        "in_bitable_not_matrix": [],
        "deprecated_in_matrix": [],
        "layer_mismatches": [],
        "matrix_tcs_by_layer": {"unit": ["TC-SY-001"]},
        "actual_tcs_by_layer": {},
        "configured_layers": [],
        "unverified_layers": ["unit"],
    }, {"missing_files": ["missing.xml"]})
    out = capsys.readouterr().out
    assert "Missing JUnit XML: 1 file(s)" in out
    assert "Configured suites did not produce JUnit XML" in out
    assert "✅ test-matrix.md and Bitable" not in out


def test_collect_results_records_optional_suite_layers(tmp_path, monkeypatch):
    sidecar = tmp_path / "tc-map.jsonl"
    sidecar.write_text(
        '{"test": "t_unit", "tc_ids": ["TC-SY-001"]}\n'
        '{"test": "t_e2e", "tc_ids": ["TC-SY-002"]}\n'
    )
    monkeypatch.setenv("TC_SIDECAR", str(sidecar))
    unit = tmp_path / "unit.xml"
    unit.write_text('<testsuite name="s"><testcase classname="m" name="t_unit"/></testsuite>')
    e2e = tmp_path / "e2e.xml"
    e2e.write_text('<testsuite name="s"><testcase classname="m" name="t_e2e"/></testsuite>')
    r = g.collect_results([
        {"name": "unit", "layer": "unit", "results_file": str(unit)},
        {"name": "browser", "layer": "browser", "results_file": str(e2e)},
    ])
    assert r["tc_layers"] == {"e2e": ["TC-SY-002"], "unit": ["TC-SY-001"]}
    assert r["configured_layers"] == ["e2e", "unit"]
    assert r["unlayered_tcs"] == []


def test_collect_results_failed_tc_is_not_layer_evidence(tmp_path, monkeypatch):
    sidecar = tmp_path / "tc-map.jsonl"
    sidecar.write_text('{"test": "t_e2e", "tc_ids": ["TC-SY-001"]}\n')
    monkeypatch.setenv("TC_SIDECAR", str(sidecar))
    e2e = tmp_path / "e2e.xml"
    e2e.write_text(
        '<testsuite name="s"><testcase classname="m" name="t_e2e">'
        '<failure message="boom"/></testcase></testsuite>'
    )
    r = g.collect_results([
        {"name": "browser", "layer": "e2e", "results_file": str(e2e)},
    ])
    assert r["linked"] == {"TC-SY-001": "失败"}
    assert r["tc_layers"] == {}
    assert r["configured_layers"] == ["e2e"]
    assert r["unlayered_tcs"] == []
    matrix = tmp_path / "matrix.md"
    matrix.write_text("""
| 模块 | e2e |
|---|---|
| sys | TC-SY-001 |
""")
    validation = g.validate_matrix(
        str(matrix),
        [_rec("TC-SY-001")],
        r["tc_layers"],
        r["configured_layers"],
        r["unlayered_tcs"],
    )
    assert validation["layer_mismatches"] == [
        {"tc_id": "TC-SY-001", "declared": "e2e", "actual": []},
    ]


def test_collect_results_missing_layered_suite_is_configured_missing_evidence(tmp_path, monkeypatch):
    monkeypatch.setenv("TC_SIDECAR", str(tmp_path / "missing-sidecar.jsonl"))
    r = g.collect_results([
        {"name": "browser", "layer": "e2e", "results_file": str(tmp_path / "missing.xml")},
    ])
    assert r["tc_layers"] == {}
    assert r["configured_layers"] == ["e2e"]
    assert r["missing_files"] == [str(tmp_path / "missing.xml")]
    assert r["missing_layered_files"] == [str(tmp_path / "missing.xml")]
    assert r["missing_layered_layers"] == ["e2e"]
    matrix = tmp_path / "matrix.md"
    matrix.write_text("""
| 模块 | e2e |
|---|---|
| sys | TC-SY-001 |
""")
    validation = g.validate_matrix(
        str(matrix),
        [_rec("TC-SY-001")],
        r["tc_layers"],
        r["configured_layers"],
        r["unlayered_tcs"],
    )
    assert validation["layer_mismatches"] == [
        {"tc_id": "TC-SY-001", "declared": "e2e", "actual": []},
    ]
    assert validation["unverified_layers"] == []


def test_collect_results_matrix_gate_false_excludes_slow_layer_from_gate(tmp_path, monkeypatch):
    monkeypatch.setenv("TC_SIDECAR", str(tmp_path / "missing-sidecar.jsonl"))
    r = g.collect_results([
        {"name": "device", "layer": "e2e", "matrix_gate": False, "results_file": str(tmp_path / "missing.xml")},
    ])
    assert r["missing_files"] == []
    assert r["excluded_missing_files"] == [str(tmp_path / "missing.xml")]
    assert r["missing_layered_files"] == []
    assert r["missing_layered_layers"] == []


def test_collect_results_matrix_gate_string_false_excludes_slow_layer(tmp_path, monkeypatch):
    monkeypatch.setenv("TC_SIDECAR", str(tmp_path / "missing-sidecar.jsonl"))
    r = g.collect_results([
        {"name": "device", "layer": "e2e", "matrix_gate": "false", "results_file": str(tmp_path / "missing.xml")},
        {"name": "host", "layer": "e2e", "matrix_gate": 0, "results_file": str(tmp_path / "missing2.xml")},
    ])
    assert r["missing_files"] == []
    assert sorted(r["excluded_missing_files"]) == [str(tmp_path / "missing.xml"), str(tmp_path / "missing2.xml")]
    assert r["missing_layered_files"] == []
    assert r["missing_layered_layers"] == []


def test_collect_results_matrix_gate_null_defaults_to_enabled(tmp_path, monkeypatch):
    monkeypatch.setenv("TC_SIDECAR", str(tmp_path / "missing-sidecar.jsonl"))
    missing = tmp_path / "missing.xml"
    r = g.collect_results([
        {"name": "unit", "layer": "unit", "matrix_gate": None, "results_file": str(missing)},
    ])
    assert r["missing_files"] == [str(missing)]
    assert r["missing_layered_layers"] == ["unit"]


def test_clear_suite_result_files_removes_configured_xml(tmp_path):
    xml = tmp_path / "unit.xml"
    xml.write_text('<testsuite name="s"></testsuite>')

    backups = g._clear_suite_result_files([
        {"name": "unit", "results_file": str(xml)},
        {"name": "duplicate", "results_file": str(xml)},
    ])

    assert not xml.exists()
    assert list(tmp_path.glob("unit.xml.pre-gate-bak-*"))
    assert backups[str(xml)].exists()


def test_clear_suite_result_files_only_uses_neutral_backup_suffix(tmp_path):
    xml = tmp_path / "unit.xml"
    user_backup = tmp_path / "unit.xml.pre-gate-user"
    user_backup.write_text("keep")
    xml.write_text("<testsuite name='s'></testsuite>")
    g._clear_suite_result_files([
        {"name": "unit", "results_file": str(xml)},
    ])

    assert user_backup.exists()
    assert list(tmp_path.glob("unit.xml.pre-gate-bak-*"))


def test_clear_suite_result_files_dedupes_same_real_path(tmp_path):
    xml = tmp_path / "unit.xml"
    alias = tmp_path / "alias.xml"
    xml.write_text("<testsuite name='s'></testsuite>")
    alias.symlink_to(xml)

    backups = g._clear_suite_result_files([
        {"name": "unit", "results_file": str(xml)},
        {"name": "alias", "results_file": str(alias)},
    ])

    assert list(backups) == [str(xml)]
    assert len(list(tmp_path.glob("unit.xml.pre-gate-bak-*"))) == 1


def test_restore_missing_suite_results_restores_backup(tmp_path):
    xml = tmp_path / "unit.xml"
    xml.write_text("<testsuite name='s'></testsuite>")
    backups = g._clear_suite_result_files([
        {"name": "unit", "results_file": str(xml)},
    ])

    restored = g._restore_missing_suite_results(backups)

    assert restored == [str(xml)]
    assert xml.exists()


def test_restore_missing_suite_results_removes_backup_when_xml_regenerated(tmp_path):
    xml = tmp_path / "unit.xml"
    xml.write_text("<testsuite name='old'></testsuite>")
    backups = g._clear_suite_result_files([
        {"name": "unit", "results_file": str(xml)},
    ])
    backup = backups[str(xml)]
    xml.write_text("<testsuite name='new'></testsuite>")

    restored = g._restore_missing_suite_results(backups)

    assert restored == []
    assert xml.read_text() == "<testsuite name='new'></testsuite>"
    assert not backup.exists()


def test_collect_results_treats_restored_stale_xml_as_missing(tmp_path, monkeypatch):
    sidecar = tmp_path / "tc-map.jsonl"
    sidecar.write_text('{"test": "t_unit", "tc_ids": ["TC-SY-001"]}\n')
    monkeypatch.setenv("TC_SIDECAR", str(sidecar))
    xml = tmp_path / "unit.xml"
    xml.write_text('<testsuite name="s"><testcase classname="m" name="t_unit"/></testsuite>')

    r = g.collect_results([
        {"name": "unit", "layer": "unit", "results_file": str(xml)},
    ], stale_result_files={str(xml)})

    assert r["linked"] == {}
    assert r["missing_files"] == [str(xml)]
    assert r["missing_layered_layers"] == ["unit"]


def test_clear_suite_result_files_rejects_directory(tmp_path):
    with pytest.raises(RuntimeError, match="results_file is not a file"):
        g._clear_suite_result_files([
            {"name": "bad", "results_file": str(tmp_path)},
        ])


def test_clear_suite_result_files_validates_all_paths_before_moving(tmp_path):
    xml = tmp_path / "unit.xml"
    xml.write_text("<testsuite name='s'></testsuite>")
    bad_dir = tmp_path / "bad"
    bad_dir.mkdir()

    with pytest.raises(RuntimeError, match="results_file is not a file"):
        g._clear_suite_result_files([
            {"name": "unit", "results_file": str(xml)},
            {"name": "bad", "results_file": str(bad_dir)},
        ])

    assert xml.exists()
    assert not list(tmp_path.glob("unit.xml.pre-gate-bak-*"))


def test_restore_missing_suite_results_accepts_byte_identical_regeneration(tmp_path):
    xml = tmp_path / "unit.xml"
    xml.write_text("<testsuite name='old'></testsuite>")
    backups = g._clear_suite_result_files([
        {"name": "unit", "results_file": str(xml)},
    ])
    backup = backups[str(xml)]
    xml.write_text("<testsuite name='old'></testsuite>")

    restored = g._restore_missing_suite_results(backups)

    assert restored == []
    assert xml.read_text() == "<testsuite name='old'></testsuite>"
    assert not backup.exists()


def test_restore_missing_suite_results_accepts_regeneration_with_old_mtime(tmp_path):
    xml = tmp_path / "unit.xml"
    xml.write_text("<testsuite name='old'></testsuite>")
    old_time = 1_700_000_000
    os.utime(xml, (old_time, old_time))
    backups = g._clear_suite_result_files([
        {"name": "unit", "results_file": str(xml)},
    ])
    backup = backups[str(xml)]
    xml.write_text("<testsuite name='new'></testsuite>")
    os.utime(xml, (old_time - 1, old_time - 1))

    restored = g._restore_missing_suite_results(backups)

    assert restored == []
    assert xml.read_text() == "<testsuite name='new'></testsuite>"
    assert not backup.exists()


def test_run_suites_and_restore_backups_restores_on_exception(tmp_path, monkeypatch):
    xml = tmp_path / "unit.xml"
    xml.write_text("<testsuite name='old'></testsuite>")
    backups = g._clear_suite_result_files([
        {"name": "unit", "results_file": str(xml)},
    ])

    def boom(_suite):
        raise OSError("runner crashed")

    monkeypatch.setattr(g, "run_suite", boom)
    with pytest.raises(OSError, match="runner crashed"):
        g._run_suites_and_restore_backups([{"name": "unit"}], backups)

    assert xml.exists()
    assert xml.read_text() == "<testsuite name='old'></testsuite>"
    assert not list(tmp_path.glob("unit.xml.pre-gate-bak-*"))


def test_sweep_pre_gate_backups_restores_missing_original(tmp_path):
    xml = tmp_path / "unit.xml"
    old = tmp_path / "unit.xml.pre-gate-bak-20200101000000000000"
    new = tmp_path / "unit.xml.pre-gate-bak-20200102000000000000"
    old.write_text("<testsuite name='old'></testsuite>")
    new.write_text("<testsuite name='new'></testsuite>")

    restored = g._sweep_pre_gate_backups([
        {"name": "unit", "results_file": str(xml)},
    ])

    assert restored == [str(xml)]
    assert xml.read_text() == "<testsuite name='new'></testsuite>"
    assert not old.exists()
    assert not new.exists()


def test_sweep_pre_gate_backups_removes_orphans_when_original_exists(tmp_path):
    xml = tmp_path / "unit.xml"
    xml.write_text("<testsuite name='current'></testsuite>")
    backup = tmp_path / "unit.xml.pre-gate-bak-20200101000000000000"
    backup.write_text("<testsuite name='backup'></testsuite>")

    restored = g._sweep_pre_gate_backups([
        {"name": "unit", "results_file": str(xml)},
    ])

    assert restored == []
    assert xml.read_text() == "<testsuite name='current'></testsuite>"
    assert not backup.exists()


def test_collect_results_matrix_gate_false_excludes_positive_layer_evidence(tmp_path, monkeypatch):
    sidecar = tmp_path / "tc-map.jsonl"
    sidecar.write_text('{"test": "t_device", "tc_ids": ["TC-SY-001"]}\n')
    monkeypatch.setenv("TC_SIDECAR", str(sidecar))
    device = tmp_path / "device.xml"
    device.write_text('<testsuite name="s"><testcase classname="m" name="t_device"/></testsuite>')
    r = g.collect_results([
        {"name": "device", "layer": "e2e", "matrix_gate": False, "results_file": str(device)},
    ])
    assert r["linked"] == {"TC-SY-001": "通过"}
    assert r["tc_layers"] == {}
    assert r["configured_layers"] == []
    assert r["unlayered_tcs"] == []
    assert r["excluded_layered_layers"] == ["e2e"]
    assert g._matrix_gate_should_fail(
        {"matrix_tcs_by_layer": {"e2e": ["TC-SY-001"]}},
        r,
    )


def test_collect_results_can_skip_excluded_stale_xml(tmp_path, monkeypatch):
    sidecar = tmp_path / "tc-map.jsonl"
    sidecar.write_text('{"test": "t_device", "tc_ids": ["TC-SY-001"]}\n')
    monkeypatch.setenv("TC_SIDECAR", str(sidecar))
    device = tmp_path / "device.xml"
    device.write_text('<testsuite name="s"><testcase classname="m" name="t_device"/></testsuite>')

    r = g.collect_results([
        {"name": "device", "layer": "e2e", "matrix_gate": False, "results_file": str(device)},
    ], parse_excluded=False)

    assert r["linked"] == {}
    assert r["tc_layers"] == {}
    assert r["excluded_layered_layers"] == ["e2e"]


def test_collect_results_invalid_layer_config_fails_gate(tmp_path, monkeypatch):
    sidecar = tmp_path / "tc-map.jsonl"
    sidecar.write_text('{"test": "t_unit", "tc_ids": ["TC-SY-001"]}\n')
    monkeypatch.setenv("TC_SIDECAR", str(sidecar))
    xml = tmp_path / "unit.xml"
    xml.write_text('<testsuite name="s"><testcase classname="m" name="t_unit"/></testsuite>')

    r = g.collect_results([
        {"name": "typo", "layer": "uint", "results_file": str(xml)},
    ])

    assert r["invalid_layer_suites"] == [{"suite": "typo", "layer": "uint"}]
    assert g._matrix_gate_should_fail({"matrix_tcs_by_layer": {}}, r)


def test_collect_results_layered_suite_without_results_file_is_missing_evidence(monkeypatch, tmp_path):
    monkeypatch.setenv("TC_SIDECAR", str(tmp_path / "missing-sidecar.jsonl"))
    r = g.collect_results([
        {"name": "unit", "layer": "unit"},
    ])
    assert r["configured_layers"] == ["unit"]
    assert r["missing_files"] == ["unit: results_file missing"]
    assert r["missing_layered_files"] == ["unit: results_file missing"]
    assert r["missing_layered_layers"] == ["unit"]
    assert r["invalid_layer_suites"] == []
    assert g._matrix_gate_should_fail({"matrix_tcs_by_layer": {"unit": ["TC-SY-001"]}}, r)


def test_collect_results_blank_layer_is_unlabeled(tmp_path, monkeypatch):
    sidecar = tmp_path / "tc-map.jsonl"
    sidecar.write_text('{"test": "t_unit", "tc_ids": ["TC-SY-001"]}\n')
    monkeypatch.setenv("TC_SIDECAR", str(sidecar))
    xml = tmp_path / "unit.xml"
    xml.write_text('<testsuite name="s"><testcase classname="m" name="t_unit"/></testsuite>')

    r = g.collect_results([
        {"name": "blank", "layer": " ", "results_file": str(xml)},
    ])

    assert r["invalid_layer_suites"] == []
    assert r["unlayered_tcs"] == ["TC-SY-001"]


def test_collect_results_records_unlayered_tcs(tmp_path, monkeypatch):
    sidecar = tmp_path / "tc-map.jsonl"
    sidecar.write_text('{"test": "t_unit", "tc_ids": ["TC-SY-001"]}\n')
    monkeypatch.setenv("TC_SIDECAR", str(sidecar))
    unit = tmp_path / "unit.xml"
    unit.write_text('<testsuite name="s"><testcase classname="m" name="t_unit"/></testsuite>')
    r = g.collect_results([
        {"name": "unlabeled", "results_file": str(unit)},
    ])
    assert r["tc_layers"] == {}
    assert r["configured_layers"] == []
    assert r["unlayered_tcs"] == ["TC-SY-001"]


def test_collect_results_failed_unlayered_tc_is_not_evidence(tmp_path, monkeypatch):
    sidecar = tmp_path / "tc-map.jsonl"
    sidecar.write_text('{"test": "t_unit", "tc_ids": ["TC-SY-001"]}\n')
    monkeypatch.setenv("TC_SIDECAR", str(sidecar))
    unit = tmp_path / "unit.xml"
    unit.write_text(
        '<testsuite name="s"><testcase classname="m" name="t_unit">'
        '<failure message="boom"/></testcase></testsuite>'
    )
    r = g.collect_results([
        {"name": "unlabeled", "results_file": str(unit)},
    ])
    assert r["linked"] == {"TC-SY-001": "失败"}
    assert r["unlayered_tcs"] == []


def test_collect_results_manual_layer_is_not_unlabeled_evidence(tmp_path, monkeypatch):
    sidecar = tmp_path / "tc-map.jsonl"
    sidecar.write_text('{"test": "t_manual", "tc_ids": ["TC-SY-001"]}\n')
    monkeypatch.setenv("TC_SIDECAR", str(sidecar))
    manual = tmp_path / "manual.xml"
    manual.write_text('<testsuite name="s"><testcase classname="m" name="t_manual"/></testsuite>')
    r = g.collect_results([
        {"name": "manual", "layer": "manual", "results_file": str(manual)},
    ])
    assert r["linked"] == {"TC-SY-001": "通过"}
    assert r["unlayered_tcs"] == []


def test_collect_results_tracks_test_type_breakdown(tmp_path, monkeypatch):
    sidecar = tmp_path / "tc-map.jsonl"
    sidecar.write_text('{"test": "t_api", "tc_ids": ["TC-SY-001"]}\n')
    monkeypatch.setenv("TC_SIDECAR", str(sidecar))
    api = tmp_path / "api.xml"
    api.write_text(
        '<testsuite name="api">'
        '<testcase classname="svc" name="t_api"/>'
        '<testcase classname="svc" name="t_untracked"><failure message="boom"/></testcase>'
        '</testsuite>'
    )
    r = g.collect_results([
        {"name": "api", "test_type": "api-automation", "results_file": str(api)},
    ])
    assert r["linked"] == {"TC-SY-001": "通过"}
    assert r["linked_test_types"] == {"TC-SY-001": "api-automation"}
    assert r["by_test_type"]["api-automation"]["通过"] == 1
    assert "失败" not in r["by_test_type"]["api-automation"]
    assert r["by_test_type"]["api-automation"]["_total"] == 1
    assert r["untracked"][0]["test_type"] == "api-automation"


def test_collect_results_conflicting_test_types_are_not_normal_buckets(tmp_path, monkeypatch):
    sidecar = tmp_path / "tc-map.jsonl"
    sidecar.write_text('{"test": "t_shared", "tc_ids": ["TC-SY-001"]}\n')
    monkeypatch.setenv("TC_SIDECAR", str(sidecar))
    api = tmp_path / "api.xml"
    api.write_text('<testsuite name="api"><testcase classname="svc" name="t_shared"/></testsuite>')
    ui = tmp_path / "ui.xml"
    ui.write_text('<testsuite name="ui"><testcase classname="web" name="t_shared"/></testsuite>')
    r = g.collect_results([
        {"name": "api", "test_type": "api-automation", "results_file": str(api)},
        {"name": "ui", "test_type": "ui-automation", "results_file": str(ui)},
    ])
    assert r["linked"] == {"TC-SY-001": "通过"}
    assert r["linked_test_types"] == {"TC-SY-001": "（多种测试类型）"}
    assert r["test_type_conflicts"] == ["TC-SY-001"]
    assert "（多种测试类型）" not in r["by_test_type"]
    assert r["by_test_type"] == {}


def test_residual_risk_section_lists_failed_untracked_tests():
    agg = {"by_module": {}, "by_status": {}, "p0_total": 0, "p0_pass": 0, "p0_blocking": []}
    untracked = [{"classname": "m", "name": "t_a", "status": "失败"},
                 {"classname": "m", "name": "t_b", "status": "通过"}]
    md = "\n".join(g._residual_risk_section(agg, untracked, {"missing_files": []}))
    assert "未链接 TC 但失败的测试" in md
    assert "t_a" in md
    # t_b is passing → not listed
    assert "t_b" not in md


def test_compute_exit_code_fails_on_missing_files():
    r = {"linked": {}, "untracked": [], "missing_files": ["/x.xml"], "parsed_suites": 0}
    assert g._compute_exit_code("any", False, r) == 1
    assert g._compute_exit_code("suite-only", False, r) == 1
    assert g._compute_exit_code("tc-failures", False, r) == 0  # tc-failures policy ignores infra
    assert g._compute_exit_code("never", False, r) == 0


def test_last_run_section_empty_when_no_previous():
    diff = {"had_previous": False, "new_failures": [], "fixed": [],
            "flips": [], "newly_seen": [], "no_longer_seen": []}
    assert g._last_run_section(diff) == []


def test_build_pr_summary_first_time():
    results = {"linked": {"TC-A": "通过", "TC-B": "失败"}, "untracked": []}
    summary = g.build_pr_summary(results, None, None)
    assert "🧪 自动化测试结果" in summary
    assert "通过 **1**" in summary
    assert "失败 **1**" in summary
    # no last-run section since no diff provided
    assert "新增失败" not in summary


def test_build_pr_summary_with_regression():
    results = {"linked": {"TC-A": "失败"}, "untracked": []}
    diff = {"had_previous": True, "new_failures": ["TC-A"], "fixed": [],
            "flips": [], "newly_seen": [], "no_longer_seen": []}
    summary = g.build_pr_summary(results, None, diff)
    assert "新增失败 / 阻塞（1）" in summary
    assert "TC-A" in summary


def test_build_pr_summary_clean_run_with_previous():
    results = {"linked": {"TC-A": "通过"}, "untracked": []}
    diff = {"had_previous": True, "new_failures": [], "fixed": [],
            "flips": [], "newly_seen": [], "no_longer_seen": []}
    summary = g.build_pr_summary(results, None, diff)
    assert "无新增失败或修复" in summary


def test_build_pr_summary_truncates_long_lists():
    results = {"linked": {f"TC-{i}": "失败" for i in range(30)}, "untracked": []}
    diff = {"had_previous": True,
            "new_failures": [f"TC-{i}" for i in range(30)],
            "fixed": [], "flips": [], "newly_seen": [], "no_longer_seen": []}
    summary = g.build_pr_summary(results, None, diff)
    assert "另外 10 个" in summary  # 30 total, shows 20, "另外 10"


def test_build_pr_summary_includes_coverage():
    results = {"linked": {"TC-A": "通过"}, "untracked": []}
    cov = {"covered": 80, "valid": 100, "rate": 0.8}
    summary = g.build_pr_summary(results, cov, None)
    assert "覆盖率 80.0%" in summary


def test_last_run_section_renders_failures_and_fixes():
    diff = {"had_previous": True,
            "new_failures": ["TC-A"], "fixed": ["TC-B"],
            "flips": [{"tc_id": "TC-C", "from": "通过", "to": "跳过"}],
            "newly_seen": [], "no_longer_seen": ["TC-X"]}
    md = "\n".join(g._last_run_section(diff))
    assert "新增失败" in md and "TC-A" in md
    assert "修复" in md and "TC-B" in md
    assert "状态翻转" in md and "TC-C" in md
    assert "上次有结果但本次未跑" in md and "TC-X" in md


# ── build_minimal_markdown smoke ──────────────────────────────────────────────

# ── CI exit gate ──────────────────────────────────────────────────────────────

@pytest.mark.parametrize("fail_on,suite_failed,results,expected", [
    ("any", False, {"linked": {"TC-A": "通过"}, "untracked": []}, 0),
    ("any", True,  {"linked": {"TC-A": "通过"}, "untracked": []}, 1),  # suite failed
    ("any", False, {"linked": {"TC-A": "失败"}, "untracked": []}, 1),  # TC failed
    ("any", False, {"linked": {"TC-A": "阻塞"}, "untracked": []}, 1),  # TC blocked
    ("any", False, {"linked": {}, "untracked": [{"status": "失败"}]}, 1),  # untracked failed
    ("tc-failures", True, {"linked": {"TC-A": "通过"}, "untracked": []}, 0),  # suite failed but ignored
    ("tc-failures", False, {"linked": {"TC-A": "失败"}, "untracked": []}, 1),
    ("suite-only", False, {"linked": {"TC-A": "失败"}, "untracked": []}, 0),  # TC failure ignored
    ("suite-only", True, {"linked": {"TC-A": "通过"}, "untracked": []}, 1),
    ("never", True, {"linked": {"TC-A": "失败"}, "untracked": []}, 0),
])
def test_compute_exit_code(fail_on, suite_failed, results, expected):
    assert g._compute_exit_code(fail_on, suite_failed, results) == expected


def test_exit_with_gate_saves_when_results_present(tmp_path, monkeypatch):
    """Non-dry-run + suite produced parseable XML → save_last_run runs.
    Independent of --run-tests (Makefile chain may run tests externally)."""
    monkeypatch.setenv("TC_LAST_RUN", str(tmp_path / "lr.json"))
    args = type("Args", (), {"run_tests": False, "dry_run": False, "fail_on": "any"})
    snapshot = {"TC-A": "通过"}
    results = {"linked": snapshot, "untracked": [], "missing_files": [], "parsed_suites": 1}
    with pytest.raises(SystemExit) as ei:
        g._exit_with_gate(args, False, results, snapshot)
    assert ei.value.code == 0
    assert (tmp_path / "lr.json").exists()


def test_exit_with_gate_preserves_baseline_on_infra_failure(tmp_path, monkeypatch, capsys):
    """All configured suites had no JUnit XML → infra hard-fail → preserve baseline."""
    monkeypatch.setenv("TC_LAST_RUN", str(tmp_path / "lr.json"))
    (tmp_path / "lr.json").write_text(json.dumps({
        "schema_version": g.LAST_RUN_SCHEMA_VERSION,
        "timestamp": "x", "linked": {"TC-OLD": "通过"},
    }))
    args = type("Args", (), {"run_tests": False, "dry_run": False, "fail_on": "any"})
    results = {"linked": {}, "untracked": [], "missing_files": ["/x.xml"], "parsed_suites": 0}
    with pytest.raises(SystemExit) as ei:
        g._exit_with_gate(args, False, results, {})
    assert ei.value.code == 1  # infra failure flags as exit 1
    saved = json.loads((tmp_path / "lr.json").read_text())
    assert saved["linked"] == {"TC-OLD": "通过"}  # untouched
    assert "infra failure" in capsys.readouterr().err


def test_exit_with_gate_saves_when_parsed_but_no_tcs(tmp_path, monkeypatch):
    """JUnit parsed OK but project has no markers yet → empty `linked` is a valid
    baseline; should save (distinguishable from infra failure via parsed_suites > 0)."""
    monkeypatch.setenv("TC_LAST_RUN", str(tmp_path / "lr.json"))
    args = type("Args", (), {"run_tests": False, "dry_run": False, "fail_on": "any"})
    results = {"linked": {}, "untracked": [{"name": "t1", "classname": "m", "status": "通过"}],
               "missing_files": [], "parsed_suites": 1}
    with pytest.raises(SystemExit) as ei:
        g._exit_with_gate(args, False, results, {})
    assert ei.value.code == 0
    assert (tmp_path / "lr.json").exists()  # empty snapshot saved (legitimate)


def test_exit_with_gate_dry_run_never_saves(tmp_path, monkeypatch):
    monkeypatch.setenv("TC_LAST_RUN", str(tmp_path / "lr.json"))
    args = type("Args", (), {"run_tests": False, "dry_run": True, "fail_on": "any"})
    results = {"linked": {"TC-A": "通过"}, "untracked": [], "missing_files": [], "parsed_suites": 1}
    with pytest.raises(SystemExit):
        g._exit_with_gate(args, False, results, {"TC-A": "通过"})
    assert not (tmp_path / "lr.json").exists()


def test_compute_exit_code_handles_none_results():
    assert g._compute_exit_code("any", False, None) == 0
    assert g._compute_exit_code("any", True, None) == 1


# ── subprocess-mocked lark-cli wrappers ──────────────────────────────────────

from unittest.mock import MagicMock  # noqa: E402


def _fake_run(returncode=0, stdout="", stderr=""):
    """Build a subprocess.run-like return value."""
    m = MagicMock()
    m.returncode = returncode
    m.stdout = stdout
    m.stderr = stderr
    return m


def test_parse_bitable_url_with_table():
    base, table = g.parse_bitable_url("https://xxx.feishu.cn/base/BAS01234567abc?table=tblXYZ123")
    assert base == "BAS01234567abc"
    assert table == "tblXYZ123"


def test_parse_bitable_url_without_table():
    base, table = g.parse_bitable_url("https://xxx.feishu.cn/base/BAS01234567abc")
    assert base == "BAS01234567abc"
    assert table == ""


def test_parse_bitable_url_invalid_raises():
    with pytest.raises(ValueError, match="Could not parse base_token"):
        g.parse_bitable_url("https://xxx.feishu.cn/base/short")


def test_fetch_first_table_id_success(monkeypatch):
    payload = json.dumps({"data": {"tables": [
        {"id": "tblFIRST", "name": "数据表"}, {"id": "tblOTHER", "name": "其他"}]}})
    monkeypatch.setattr(g.subprocess, "run", lambda *a, **k: _fake_run(stdout=payload))
    assert g.fetch_first_table_id("base", "user") == "tblFIRST"


def test_fetch_first_table_id_no_tables(monkeypatch):
    payload = json.dumps({"data": {"tables": []}})
    monkeypatch.setattr(g.subprocess, "run", lambda *a, **k: _fake_run(stdout=payload))
    with pytest.raises(RuntimeError, match="No tables found"):
        g.fetch_first_table_id("base", "user")


def test_fetch_first_table_id_cli_failure(monkeypatch):
    monkeypatch.setattr(g.subprocess, "run",
                        lambda *a, **k: _fake_run(returncode=1, stderr="auth failed"))
    with pytest.raises(RuntimeError, match="\\+table-list failed"):
        g.fetch_first_table_id("base", "user")


def test_record_list_raises_on_failure(monkeypatch):
    monkeypatch.setattr(g.subprocess, "run",
                        lambda *a, **k: _fake_run(returncode=1, stderr="scope denied"))
    with pytest.raises(RuntimeError, match="\\+record-list failed"):
        g.record_list("base", "tbl", "user")


def test_record_list_columnar_schema(monkeypatch):
    """lark-cli ~1.0.44 returns columnar data.data + fields + record_id_list;
    record_list must normalise it to [{record_id, fields:{name: value}}]."""
    payload = json.dumps({"data": {
        "fields": ["用例ID", "状态", "信息流转"],
        "data": [["TC-X-001", ["通过"], "init"],
                 ["TC-X-002", ["未测试"], "init2"]],
        "record_id_list": ["recA", "recB"],
        "has_more": False,
    }})
    monkeypatch.setattr(g.subprocess, "run", lambda *a, **k: _fake_run(stdout=payload))
    recs = g.record_list("base", "tbl", "user")
    assert len(recs) == 2
    assert recs[0]["record_id"] == "recA"
    assert g._str(recs[0]["fields"]["用例ID"]) == "TC-X-001"
    assert g._str(recs[0]["fields"]["状态"]) == "通过"
    assert recs[1]["record_id"] == "recB"
    assert g._str(recs[1]["fields"]["状态"]) == "未测试"


def test_record_list_columnar_paginates_via_has_more(monkeypatch):
    """Columnar pagination is driven by has_more, advancing offset by page size."""
    def fake(cmd, capture_output, text):
        offset = int(cmd[cmd.index("--offset") + 1])
        if offset == 0:
            rows = [[f"TC-X-{i:03d}", ["通过"]] for i in range(200)]
            rids = [f"r{i}" for i in range(200)]
            has_more = True
        else:
            rows = [[f"TC-X-{i:03d}", ["通过"]] for i in range(200, 230)]
            rids = [f"r{i}" for i in range(200, 230)]
            has_more = False
        return _fake_run(stdout=json.dumps({"data": {
            "fields": ["用例ID", "状态"], "data": rows,
            "record_id_list": rids, "has_more": has_more}}))
    monkeypatch.setattr(g.subprocess, "run", fake)
    recs = g.record_list("base", "tbl", "user")
    assert len(recs) == 230
    assert g._str(recs[229]["fields"]["用例ID"]) == "TC-X-229"


def test_save_doc_url_round_trip(tmp_path):
    p = tmp_path / ".report-config.json"
    p.write_text(json.dumps({"base_token": "b", "table_id": "t"}))
    g.save_doc_url(str(p), "https://feishu.cn/docx/X1234")
    saved = json.loads(p.read_text())
    assert saved["report_doc_url"] == "https://feishu.cn/docx/X1234"
    # other fields preserved
    assert saved["base_token"] == "b"


def test_init_minimal_config_creates_skeleton(tmp_path):
    p = tmp_path / ".report-config.json"
    g.init_minimal_config(str(p))
    assert p.exists()
    cfg = json.loads(p.read_text())
    assert cfg["base_token"] == ""
    assert cfg["table_id"] == ""
    assert cfg["test_suites"] == []


def test_init_minimal_config_preserves_existing_fields(tmp_path):
    p = tmp_path / ".report-config.json"
    p.write_text(json.dumps({"test_suites": [{"name": "x"}], "custom_key": "keep_me"}))
    g.init_minimal_config(str(p))
    cfg = json.loads(p.read_text())
    assert cfg["test_suites"] == [{"name": "x"}]
    assert cfg["custom_key"] == "keep_me"
    assert cfg["base_token"] == ""  # added


def test_init_config_with_table_in_url(tmp_path, monkeypatch):
    """When table_id is in the URL, no +table-list call needed."""
    called = []
    monkeypatch.setattr(g.subprocess, "run", lambda *a, **k: called.append(a) or _fake_run())
    p = tmp_path / ".report-config.json"
    g.init_config(str(p), "https://x.feishu.cn/base/BAS01234567abc?table=tblXYZ", "user")
    assert called == []  # no subprocess call
    cfg = json.loads(p.read_text())
    assert cfg["base_token"] == "BAS01234567abc"
    assert cfg["table_id"] == "tblXYZ"


def test_init_config_fetches_table_when_missing(tmp_path, monkeypatch):
    """When URL has no ?table=, falls back to +table-list."""
    payload = json.dumps({"data": {"tables": [{"id": "tblFROM_LIST", "name": "数据表"}]}})
    monkeypatch.setattr(g.subprocess, "run", lambda *a, **k: _fake_run(stdout=payload))
    p = tmp_path / ".report-config.json"
    g.init_config(str(p), "https://x.feishu.cn/base/BAS01234567abc", "user")
    cfg = json.loads(p.read_text())
    assert cfg["table_id"] == "tblFROM_LIST"


def test_create_doc_success(monkeypatch):
    """Markdown URL returned on stdout."""
    monkeypatch.setattr(g.subprocess, "run",
                        lambda *a, **k: _fake_run(stdout="https://feishu.cn/docx/X12345\n"))
    url = g.create_doc("Title", "# md", "", "user")
    assert url == "https://feishu.cn/docx/X12345"


def test_create_doc_json_output(monkeypatch):
    monkeypatch.setattr(g.subprocess, "run",
                        lambda *a, **k: _fake_run(stdout=json.dumps({"data": {"url": "https://feishu.cn/docx/J999"}})))
    url = g.create_doc("Title", "# md", "folder", "user")
    assert url == "https://feishu.cn/docx/J999"


def test_create_doc_failure_raises(monkeypatch):
    monkeypatch.setattr(g.subprocess, "run",
                        lambda *a, **k: _fake_run(returncode=1, stderr="scope denied"))
    with pytest.raises(RuntimeError, match="docs \\+create failed"):
        g.create_doc("t", "m", "", "user")


def test_create_doc_empty_url_raises(monkeypatch):
    monkeypatch.setattr(g.subprocess, "run", lambda *a, **k: _fake_run(stdout=""))
    with pytest.raises(RuntimeError, match="no URL found"):
        g.create_doc("t", "m", "", "user")


def test_update_doc_success(monkeypatch):
    calls = []
    def fake(cmd, capture_output, text):
        calls.append(list(cmd))
        return _fake_run()
    monkeypatch.setattr(g.subprocess, "run", fake)
    g.update_doc("https://feishu.cn/docx/X1", "# md", "user")
    assert "+update" in calls[0]
    assert "replace_all" in calls[0]


def test_update_doc_failure_raises(monkeypatch):
    monkeypatch.setattr(g.subprocess, "run",
                        lambda *a, **k: _fake_run(returncode=1, stderr="not found"))
    with pytest.raises(RuntimeError, match="docs \\+update failed"):
        g.update_doc("https://x", "m", "user")


def test_sync_results_with_append_skips_deprecated(monkeypatch):
    """A TC marked 废弃 in Bitable must NOT be overwritten by automation."""
    calls = []
    monkeypatch.setattr(g.subprocess, "run", lambda *a, **k: calls.append(a) or _fake_run())
    records = [_rec("TC-A", status="废弃")]
    n = g.sync_results_with_append("b", "t", "user", records, {"TC-A": "失败"}, "alice")
    assert n == 0
    assert calls == []  # no +record-upsert call made


def test_sync_results_with_append_skips_unchanged(monkeypatch):
    calls = []
    monkeypatch.setattr(g.subprocess, "run", lambda *a, **k: calls.append(a) or _fake_run())
    records = [_rec("TC-A", status="通过")]
    n = g.sync_results_with_append("b", "t", "user", records, {"TC-A": "通过"}, "alice")
    assert n == 0
    assert calls == []


def test_sync_results_with_append_updates_and_appends_info(monkeypatch):
    captured: list[dict] = []
    def fake(cmd, capture_output, text):
        # capture --json payload
        idx = cmd.index("--json") + 1
        captured.append(json.loads(cmd[idx]))
        return _fake_run()
    monkeypatch.setattr(g.subprocess, "run", fake)
    records = [
        {"record_id": "rA", "fields": {"用例ID": "TC-A", "状态": "通过",
                                          "信息流转": "[prev 2026-01-01] 之前的事"}},
    ]
    n = g.sync_results_with_append("b", "t", "user", records, {"TC-A": "失败"}, "alice")
    assert n == 1
    assert captured[0]["状态"] == "失败"
    assert "自动化测试：失败" in captured[0]["信息流转"]
    assert "[prev 2026-01-01] 之前的事" in captured[0]["信息流转"]  # preserved


def test_sync_results_with_append_skips_missing_tc(monkeypatch, capsys):
    monkeypatch.setattr(g.subprocess, "run", lambda *a, **k: _fake_run())
    records = [_rec("TC-A")]
    n = g.sync_results_with_append("b", "t", "user", records, {"TC-MISSING": "失败"}, "alice")
    assert n == 0
    assert "TC-MISSING not found in Bitable" in capsys.readouterr().err


def test_sync_results_continues_on_single_failure(monkeypatch):
    """One failure should not abort the rest."""
    call_count = [0]
    def fake(cmd, capture_output, text):
        call_count[0] += 1
        # First call fails, others succeed
        return _fake_run(returncode=1 if call_count[0] == 1 else 0,
                          stderr="api error" if call_count[0] == 1 else "")
    monkeypatch.setattr(g.subprocess, "run", fake)
    records = [_rec("TC-A", status="未测试"), _rec("TC-B", status="未测试")]
    n = g.sync_results_with_append("b", "t", "user", records,
                                    {"TC-A": "失败", "TC-B": "通过"}, "alice")
    assert n == 1  # only TC-B succeeded
    assert call_count[0] == 2


def test_unfreeze_tc_only_affects_deprecated(monkeypatch):
    captured = []
    def fake(cmd, capture_output, text):
        idx = cmd.index("--json") + 1
        captured.append(json.loads(cmd[idx]))
        return _fake_run()
    monkeypatch.setattr(g.subprocess, "run", fake)
    records = [
        _rec("TC-A", status="废弃"),
        _rec("TC-B", status="通过"),  # not 废弃 → skipped
    ]
    n = g.unfreeze_tc("b", "t", "user", records, ["TC-A", "TC-B"], "alice", reason="误标")
    assert n == 1
    assert len(captured) == 1
    assert captured[0]["状态"] == "未测试"
    assert "误标" in captured[0]["信息流转"]
    assert "废弃 → 未测试" in captured[0]["信息流转"]


def test_unfreeze_tc_skips_missing(monkeypatch, capsys):
    monkeypatch.setattr(g.subprocess, "run", lambda *a, **k: _fake_run())
    records = [_rec("TC-A", status="废弃")]
    n = g.unfreeze_tc("b", "t", "user", records, ["TC-MISSING"], "alice")
    assert n == 0
    assert "TC-MISSING not found" in capsys.readouterr().err


def test_build_minimal_markdown_smoke():
    results = {
        "linked": {"TC-X-001": "通过"},
        "untracked": [
            {"name": "t_a", "classname": "m", "status": "通过", "suite": "unit"},
            {"name": "t_b", "classname": "m", "status": "失败", "suite": "unit"},
        ],
        "by_test_type": {
            "api-automation": {"_total": 2, "通过": 1, "失败": 1},
        },
    }
    md = g.build_minimal_markdown(results, "alice", "本地", "v1", coverage={"covered": 80, "valid": 100, "rate": 0.8})
    assert "代码覆盖率 | 80.0%（80 / 100 行）" in md
    assert "按测试类型统计" in md
    assert "api-automation" in md
    assert "失败 / 阻塞明细" in md
    assert "t_b" in md
    assert "需先解决再发布" in md


def test_build_markdown_renders_layer_and_test_type_sections():
    agg = g.aggregate([
        _rec("TC-1", status="通过", 模块="登录", 功能点="主链路", 优先级="P0",
             测试层级="e2e", 测试类型="ui-automation"),
        _rec("TC-2", status="失败", 模块="接口", 功能点="契约校验", 优先级="P1",
             测试层级="contract", 测试类型="api-automation"),
    ])
    md = g.build_markdown(agg, "alice", "本地", "v1")
    assert "## 按测试层级统计" in md
    assert "## 按测试类型统计" in md
    assert "| 测试层级 | 总数 | 通过 | 失败 | 阻塞 | 跳过 | 未测试 | 通过率 |" in md
    assert "ui-automation" in md
    assert "api-automation" in md
