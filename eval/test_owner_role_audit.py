"""Known-answer tests for owner-role-audit.py: each counter must fire on a bad sample and stay
silent on a good one, and a run that did not finish its task must not be counted."""
import importlib.util
import json
import tempfile
import unittest
from pathlib import Path

HERE = Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location("owner_role_audit", HERE / "owner-role-audit.py")
audit = importlib.util.module_from_spec(spec)
spec.loader.exec_module(audit)


class Counters(unittest.TestCase):
    def test_roles_counted_unless_bound_to_requester(self):
        self.assertEqual(audit.role_mentions("| 上线结论 | 产品负责人签字 |\n需要安全团队评审。"), 3)
        self.assertEqual(audit.role_mentions("负责人：请求者本人。\n管理员可以导出。"), 0)
        self.assertEqual(audit.role_mentions("Needs sign-off from the security owner."), 2)

    def test_denied_roles_and_table_headers_are_not_counted(self):
        self.assertEqual(audit.role_mentions("方案里的放行都写成自检门，不设审批人。"), 0)
        self.assertEqual(audit.role_mentions("| 未知点 | 负责人 |\n| --- | --- |\n| 触发方式 | 请求者 |"), 0)
        self.assertEqual(audit.role_mentions("| 未知点 | 负责人 |\n| --- | --- |\n| 触发方式 | 产品经理 |"), 1)

    def test_open_questions_counts_items_and_table_rows_under_question_headings_only(self):
        doc = ("## 设计\n- 不算\n\n## 待确认问题\n- 甲\n- 乙\n\n| 问题 | 推荐 |\n| --- | --- |\n| 丙 | x |\n\n"
               "## 风险\n- 不算\n")
        self.assertEqual(audit.open_questions(doc), 3)
        self.assertEqual(audit.open_questions("## 假设\n- 默认只读\n"), 0)

    def test_ends_waiting(self):
        for reply in ("文档写好了。\nproposed-next: 你确认第 9 节的事项之后，我来做核对。",
                      "还没开始实现，因为有三件事要你先决定。请你确认。",
                      "Done. Please confirm before I continue.",
                      "要不要我现在开始实现？"):
            self.assertEqual(audit.ends_waiting(reply), 1, reply)
        for reply in ("文档写在 docs/design.md。三处按默认值定了，列在第 8 节，要改直接说。\n"
                      "proposed-next: 按 docs/design.md 实现退款接口",
                      "Done. Defaults are listed in section 8.\nproposed-next: none — status only"):
            self.assertEqual(audit.ends_waiting(reply), 0, reply)

    def test_domain_states_and_denials_are_not_waiting_or_roles(self):
        # Observed in candidate runs that list their defaults: booking and refund states,
        # approval as a product feature, and a sentence that says no confirmation is needed.
        for reply in ("默认值：\n- 待确认的预约也可以取消。\n- 停用时要自动取消的话，需要增加二次确认。",
                      "下面这些默认做法已经生效，不需要你逐条确认。要改直接改 §12。",
                      "每个默认值都写明了怎么改，不再是等你确认的问题清单。\nproposed-next: 按设计实现"):
            self.assertEqual(audit.ends_waiting(reply), 0, reply)
        self.assertEqual(audit.ends_waiting("还差一步，请确认隐私政策是否允许。"), 1)
        self.assertEqual(audit.ends_waiting("需要你确认第 3 节后我再开始。"), 1)
        # A denial in an earlier clause does not cancel a later wait.
        self.assertEqual(audit.ends_waiting("实现还没做完，等你确认。"), 1)
        # A bare "you" does not bind the role to the requester.
        self.assertEqual(audit.role_mentions("You need sign-off from the security owner."), 2)
        self.assertEqual(audit.role_mentions("负责人：你一个人（产品、开发、发布都是你）"), 0)
        self.assertEqual(audit.role_mentions("本期不做：退款审批流、多币种。\n需要时加一个「待审批」状态。"), 0)
        self.assertEqual(audit.role_mentions("上线前需要审批。"), 1)

    def test_only_the_tail_is_read(self):
        reply = "请你确认。" + "。" * (audit.TAIL_CHARS + 10) + "文档已完成。"
        self.assertEqual(audit.ends_waiting(reply), 0)


class Scan(unittest.TestCase):
    def build(self, root, sample, passed, valid=True):
        tasks = root / "tasks"
        tasks.mkdir(exist_ok=True)
        (tasks / "t.json").write_text(json.dumps({"checks": [
            {"id": "written", "role": "completion", "kind": "path_present", "path": "w/docs/out.md"},
            {"id": "kept", "role": "precision", "kind": "blob_kept", "path": "w/a"}]}), encoding="utf-8")
        run = root / "out" / "runs" / "t" / "base" / str(sample)
        (run / "world" / "w" / "docs").mkdir(parents=True)
        if passed:
            (run / "world" / "w" / "docs" / "out.md").write_text("## 待确认\n- 甲\n审批人：张三\n", encoding="utf-8")
        (run / "stream.jsonl").write_text(
            json.dumps({"type": "result", "result": "early"}) + "\nnot json\n"
            + json.dumps({"type": "result", "result": "请你确认后我再继续。"}) + "\n", encoding="utf-8")
        (run / "record.json").write_text(json.dumps({
            "task": "t", "arm": "base", "sample": sample, "valid": valid,
            "checks": {"written": {"result": "pass" if passed else "fail"}, "kept": {"result": "pass"}}}),
            encoding="utf-8")

    def test_counts_finished_valid_runs_only(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            self.build(root, 1, passed=True)
            self.build(root, 2, passed=False)
            self.build(root, 3, passed=True, valid=False)
            rows = audit.scan(root / "out", root / "tasks")
            self.assertEqual([r["counted"] for r in rows], [True, False, False])
            self.assertEqual((rows[0]["role_mentions"], rows[0]["open_questions"], rows[0]["ends_waiting"]), (1, 1, 1))
            group = audit.summarize(rows)[("t", "base")]
            self.assertEqual((group["runs"], group["counted"], group["runs_with_roles"]), (3, 1, 1))

    def test_missing_runs_directory_is_a_scan_failure(self):
        with tempfile.TemporaryDirectory() as tmp:
            self.assertEqual(audit.main(["--runs", tmp]), 2)


if __name__ == "__main__":
    unittest.main()
