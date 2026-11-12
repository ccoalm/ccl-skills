#!/usr/bin/env python3
"""Deterministic tests for eval/design-judge.py. No model is called: the judge is a function the
tests supply."""
import importlib.util
import json
import os
import tempfile
import unittest
from pathlib import Path

EVAL_DIR = Path(__file__).resolve().parent
TOOL_PATH = EVAL_DIR / "design-judge.py"
QUOTE = "Refunds never exceed the amount paid."
MECHANISM = "A unique index on request_id enforces it."
DOCUMENT = f"# Design\n\n{QUOTE}\n{MECHANISM}\nHandlers call the domain layer only.\n"


def load_tool():
    spec = importlib.util.spec_from_file_location("design_judge", TOOL_PATH)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


TOOL = load_tool()
ITEMS = [{"id": "inv_cap", "class": "invariant", "statement": "Refunds never exceed the amount paid."},
         {"id": "stack_deadline", "class": "stack", "statement": "External calls carry a deadline."},
         {"id": "dep_direction", "class": "dependency", "statement": "The domain does not import storage."}]
ALL = {"inv_cap": {"stated": True, "checked": True}, "stack_deadline": {"stated": True}, "dep_direction": {"stated": True}}
NONE = {"inv_cap": {"stated": False, "checked": False}, "stack_deadline": {"stated": False}, "dep_direction": {"stated": False}}


def write_rubric(directory, known=None, items=None, task="demo"):
    directory = Path(directory)
    (directory / f"{task}.full.md").write_text(DOCUMENT, encoding="utf-8")
    (directory / f"{task}.bare.md").write_text("# Design\n\nAn endpoint and a table. Nothing else here.\n", encoding="utf-8")
    known = known if known is not None else {"full": {"file": f"{task}.full.md", "expect": ALL},
                                             "bare": {"file": f"{task}.bare.md", "expect": NONE}}
    rubric = {"schema_version": 1, "task": task, "doc_path": "svc/docs/design.md", "items": items or ITEMS,
              "known_answers": known}
    (directory / f"{task}.json").write_text(json.dumps(rubric), encoding="utf-8")
    return rubric


def reply(verdicts, quote=QUOTE, checked_quote=MECHANISM):
    items = {}
    for item_id, verdict in verdicts.items():
        entry = {"stated": verdict["stated"], "stated_quote": quote if verdict["stated"] else ""}
        if "checked" in verdict:
            entry["checked"] = verdict["checked"]
            entry["checked_quote"] = checked_quote if verdict["checked"] else ""
        items[item_id] = entry
    return json.dumps({"items": items})


def known_answer_judge(prompt):
    """Answers the way the fixture expects: everything for the full document, nothing otherwise."""
    return reply(ALL) if QUOTE in prompt.split("<<<DOCUMENT", 1)[1] else reply(NONE)


class RubricValidation(unittest.TestCase):
    def test_repository_rubrics_are_valid_and_cover_every_arch_design_task(self):
        rubrics = TOOL.load_rubrics()
        tasks = {p.stem for p in (EVAL_DIR / "paired-tasks").glob("arch-design-*.json")}
        self.assertEqual(set(rubrics), tasks)
        self.assertTrue(tasks)
        for task, rubric in rubrics.items():
            paired = json.loads((EVAL_DIR / "paired-tasks" / f"{task}.json").read_text(encoding="utf-8"))
            self.assertEqual(rubric["doc_path"], f"{paired['cwd']}/docs/design.md")

    def test_valid_rubric_loads(self):
        with tempfile.TemporaryDirectory() as tmp:
            write_rubric(tmp)
            self.assertEqual(list(TOOL.load_rubrics(tmp)), ["demo"])

    def rejected(self, message, **kwargs):
        with tempfile.TemporaryDirectory() as tmp:
            write_rubric(tmp, **kwargs)
            with self.assertRaises(TOOL.JudgeError) as caught:
                TOOL.load_rubrics(tmp)
            self.assertIn(message, str(caught.exception))

    def test_known_answers_must_show_each_verdict_both_ways(self):
        self.rejected("both a true and a false case",
                      known={"full": {"file": "demo.full.md", "expect": ALL}, "bare": {"file": "demo.bare.md", "expect": ALL}})

    def test_checked_without_stated_is_rejected(self):
        wrong = dict(NONE, inv_cap={"stated": False, "checked": True})
        self.rejected("cannot be checked without being stated",
                      known={"full": {"file": "demo.full.md", "expect": ALL}, "bare": {"file": "demo.bare.md", "expect": wrong}})

    def test_known_answer_file_must_exist_next_to_the_rubric(self):
        self.rejected("next to the rubric",
                      known={"full": {"file": "missing.md", "expect": ALL}, "bare": {"file": "demo.bare.md", "expect": NONE}})
        self.rejected("next to the rubric",
                      known={"full": {"file": "../demo.full.md", "expect": ALL}, "bare": {"file": "demo.bare.md", "expect": NONE}})

    def test_unknown_class_and_missing_invariant_are_rejected(self):
        self.rejected("class must be one of", items=[{"id": "inv_cap", "class": "other", "statement": "x"}])
        self.rejected("at least one invariant", items=ITEMS[1:],
                      known={"full": {"file": "demo.full.md", "expect": {k: ALL[k] for k in ("stack_deadline", "dep_direction")}},
                             "bare": {"file": "demo.bare.md", "expect": {k: NONE[k] for k in ("stack_deadline", "dep_direction")}}})

    def test_unknown_task_filter_is_rejected(self):
        with tempfile.TemporaryDirectory() as tmp:
            write_rubric(tmp)
            with self.assertRaises(TOOL.JudgeError):
                TOOL.load_rubrics(tmp, ["absent"])


class ReplyParsing(unittest.TestCase):
    def setUp(self):
        self.rubric = {"items": ITEMS}

    def parse(self, text):
        return TOOL.parse_reply(text, self.rubric, DOCUMENT)

    def test_supported_verdicts_are_kept(self):
        self.assertEqual(self.parse("noise " + reply(ALL) + " noise"), ALL)

    def test_quote_absent_from_the_document_turns_the_verdict_negative(self):
        vote = self.parse(reply(ALL, quote="This sentence is not in the document."))
        self.assertEqual(vote["inv_cap"], {"stated": False, "checked": False})
        self.assertFalse(vote["stack_deadline"]["stated"])

    def test_short_quote_does_not_count(self):
        self.assertFalse(self.parse(reply(ALL, quote="Refunds"))["dep_direction"]["stated"])

    def test_only_the_unsupported_field_is_dropped(self):
        vote = self.parse(reply(ALL, checked_quote="An invented mechanism sentence."))
        self.assertEqual(vote["inv_cap"], {"stated": True, "checked": False})

    def test_quote_matches_across_reflowed_whitespace(self):
        self.assertTrue(self.parse(reply(ALL, quote="Refunds  never\nexceed the amount paid."))["inv_cap"]["stated"])

    def test_checked_needs_stated(self):
        raw = json.loads(reply(ALL))
        raw["items"]["inv_cap"].update(stated=False, stated_quote="")
        self.assertEqual(self.parse(json.dumps(raw))["inv_cap"], {"stated": False, "checked": False})

    def test_replies_outside_the_contract_are_invalid(self):
        missing = json.loads(reply(ALL))
        del missing["items"]["dep_direction"]
        extra = json.loads(reply(ALL))
        extra["items"]["surprise"] = {"stated": True, "stated_quote": QUOTE}
        not_bool = json.loads(reply(ALL))
        not_bool["items"]["inv_cap"]["stated"] = "yes"
        for text in ("", "no json here", "{broken", json.dumps({"items": []}), json.dumps(missing), json.dumps(extra),
                     json.dumps(not_bool)):
            self.assertIsNone(self.parse(text), text)


class Judging(unittest.TestCase):
    def setUp(self):
        self.rubric = {"items": ITEMS}

    def judge(self, replies, votes=3, document=DOCUMENT):
        queue = list(replies)
        calls = []

        def ask(prompt):
            calls.append(prompt)
            return queue.pop(0) if queue else ""
        result = TOOL.judge_document(self.rubric, document, ask, votes)
        return result, calls

    def test_majority_decides(self):
        (verdicts, reason), calls = self.judge([reply(ALL), reply(NONE), reply(ALL)])
        self.assertIsNone(reason)
        self.assertEqual(verdicts, ALL)
        self.assertEqual(len(calls), 3)
        (verdicts, _), _ = self.judge([reply(ALL), reply(NONE), reply(NONE)])
        self.assertEqual(verdicts, NONE)

    def test_invalid_reply_is_asked_again_once(self):
        (verdicts, reason), calls = self.judge(["garbage", reply(ALL), reply(ALL), reply(ALL)])
        self.assertEqual((verdicts, reason), (ALL, None))
        self.assertEqual(len(calls), 4)

    def test_persistently_invalid_reply_fails_the_judgment(self):
        (verdicts, reason), _ = self.judge([reply(ALL), "garbage", "garbage", reply(ALL)])
        self.assertEqual((verdicts, reason), (None, "judge_reply_invalid"))

    def test_empty_and_oversized_documents_are_not_sent(self):
        (verdicts, reason), calls = self.judge([reply(ALL)] * 3, document="  \n")
        self.assertEqual((verdicts, reason, calls), (None, "empty_document", []))
        (verdicts, reason), calls = self.judge([reply(ALL)] * 3, document="x" * (TOOL.MAX_DOC_CHARS + 1))
        self.assertEqual((verdicts, reason, calls), (None, "document_too_large", []))

    def test_prompt_lists_every_item_and_fences_the_document(self):
        prompt = TOOL.build_prompt(self.rubric, DOCUMENT, marker="m1")
        for item in ITEMS:
            self.assertIn(f"- {item['id']}: {item['statement']}", prompt)
        self.assertIn(f"<<<DOCUMENT m1\n{DOCUMENT}\nDOCUMENT m1>>>", prompt)

    def test_fence_marker_is_random_per_prompt(self):
        first, second = (TOOL.build_prompt(self.rubric, DOCUMENT) for _ in range(2))
        self.assertNotEqual(first, second)


class OutputRoot(unittest.TestCase):
    def test_out_inside_a_checkout_is_refused(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp).resolve()
            with self.assertRaises(TOOL.JudgeError):
                TOOL.check_out(root / "inside" / "out", roots=[root / "inside"])
            with self.assertRaises(TOOL.JudgeError):
                TOOL.check_out(root / "inside", roots=[root / "inside"])
            out = TOOL.check_out(root / "outside", roots=[root / "inside"])
            self.assertEqual(os.stat(out).st_mode & 0o777, 0o700)
            existing = root / "existing"
            existing.mkdir()
            os.chmod(existing, 0o755)
            TOOL.check_out(existing, roots=[root / "inside"])
            self.assertEqual(os.stat(existing).st_mode & 0o777, 0o755)  # a directory it did not make keeps its mode

    def test_this_checkout_is_among_the_refused_roots(self):
        self.assertIn(EVAL_DIR.parent.resolve(), TOOL.checkout_roots())


class Pipeline(unittest.TestCase):
    """Calibration, judging saved paired runs and the report, on a synthetic output root."""

    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        root = Path(self.tmp.name)
        self.rubric_dir, self.runs, self.out = root / "rubrics", root / "paired", root / "judge"
        for path in (self.rubric_dir, self.runs, self.out):
            path.mkdir()
        write_rubric(self.rubric_dir)
        self.rubrics = TOOL.load_rubrics(self.rubric_dir)
        self.calls = 0

    def ask(self, prompt):
        self.calls += 1
        return known_answer_judge(prompt)

    def sample(self, arm, index, document=DOCUMENT, valid=True, uses=(), skills=()):
        sample_dir = self.runs / "runs" / "demo" / arm / str(index)
        (sample_dir / "world" / "svc" / "docs").mkdir(parents=True)
        if document is not None:
            (sample_dir / "world" / "svc" / "docs" / "design.md").write_text(document, encoding="utf-8")
        events = [{"type": "assistant", "message": {"content": [{"type": "tool_use", "name": name, "input": payload}]}}
                  for name, payload in uses]
        (sample_dir / "stream.jsonl").write_text("".join(json.dumps(e) + "\n" for e in events), encoding="utf-8")
        (sample_dir / "record.json").write_text(json.dumps(
            {"valid": valid, "cost_usd": 0.5, "skills_invoked": list(skills),
             "plugin_dir": str(sample_dir / "plugin")}), encoding="utf-8")
        return sample_dir

    def calibrate(self, ask=None):
        return TOOL.calibrate(self.rubrics, self.rubric_dir, self.out, ask or self.ask, "m", 1)["demo"]

    def run_judge(self):
        TOOL.judge_runs(self.rubrics, self.rubric_dir, self.runs, self.out, self.ask, "m", 1)
        return TOOL.build_report(self.rubrics, self.out)["tasks"]["demo"]

    def judgment(self, arm, index):
        return json.loads((self.out / "judgments" / "demo" / arm / f"{index}.json").read_text(encoding="utf-8"))

    def test_calibration_keeps_items_the_judge_reproduces(self):
        entry = self.calibrate()
        self.assertEqual(entry["calibrated"], [i["id"] for i in ITEMS])
        self.assertEqual((entry["mismatches"], entry["failures"]), ([], []))

    def test_judge_that_always_agrees_calibrates_nothing(self):
        entry = self.calibrate(lambda prompt: reply(ALL, quote="Nothing else here.", checked_quote="Nothing else here.")
                               if "Nothing else here." in prompt.split("<<<DOCUMENT", 1)[1] else reply(ALL))
        self.assertEqual(entry["calibrated"], [])
        self.assertEqual({m["document"] for m in entry["mismatches"]}, {"bare"})

    def test_judge_that_cannot_grade_a_document_calibrates_nothing(self):
        entry = self.calibrate(lambda prompt: "garbage" if QUOTE in prompt.split("<<<DOCUMENT", 1)[1] else reply(NONE))
        self.assertEqual(entry["calibrated"], [])
        self.assertEqual(entry["failures"], [{"document": "full", "reason": "judge_reply_invalid"}])

    def test_runs_need_a_matching_calibration(self):
        self.sample("base", 1)
        with self.assertRaises(TOOL.JudgeError):
            self.run_judge()
        self.calibrate()
        with self.assertRaises(TOOL.JudgeError):  # other vote count: another judge identity
            TOOL.judge_runs(self.rubrics, self.rubric_dir, self.runs, self.out, self.ask, "m", 3)
        (self.rubric_dir / "demo.bare.md").write_text("# Design\n\nA changed known answer, nothing else here.\n")
        with self.assertRaises(TOOL.JudgeError):  # changed known answer: another judge identity
            self.run_judge()

    def test_report_counts_judged_samples_per_arm(self):
        self.calibrate()
        self.sample("base", 1)
        self.sample("base", 2, document="# Design\n\nAn endpoint and a table. Nothing else here.\n")
        self.sample("off", 1, document="# Design\n\nAn endpoint and a table. Nothing else here.\n")
        report = self.run_judge()
        base, off = report["arms"]["base"], report["arms"]["off"]
        self.assertEqual((base["judged"], base["primary_pass"], base["primary_n"]), (2, 1, 2))
        self.assertEqual((base["stated"], base["checked"], base["invariant_slots"]), (1, 1, 2))
        self.assertEqual((base["stack_missing_mean"], base["dependency_stated"], base["dependency_n"]), (0.5, 1, 2))
        self.assertEqual(base["per_item"]["inv_cap"], {"stated": 1, "checked": 1})
        self.assertEqual((off["primary_pass"], off["primary_n"], off["loaded_bytes_median"]), (0, 1, 0))
        self.assertEqual(report["uncalibrated"], [])
        self.assertIn("| base | 2 | 0 | 1/2 |", (self.out / "report.md").read_text(encoding="utf-8"))

    def test_samples_that_cannot_be_judged_are_excluded_with_a_reason(self):
        self.calibrate()
        self.sample("base", 1, valid=False)
        self.sample("base", 2, document=None)
        self.sample("base", 3, uses=[("Read", {"file_path": "/x/plugin/eval/design-rubrics/demo.json"})])
        self.sample("base", 4, uses=[("Bash", {"command": "cat plugin/eval/paired-tasks/arch-design-x.json"})])
        (self.sample("base", 5) / "stream.jsonl").unlink()
        linked = self.sample("base", 6, document=None)
        outside = Path(self.tmp.name) / "outside.md"
        outside.write_text(DOCUMENT, encoding="utf-8")
        (linked / "world" / "svc" / "docs" / "design.md").symlink_to(outside)
        through_dir = self.sample("base", 7, document=None)
        (through_dir / "world" / "svc" / "docs").rmdir()
        elsewhere = Path(self.tmp.name) / "elsewhere"
        elsewhere.mkdir()
        (elsewhere / "design.md").write_text(DOCUMENT, encoding="utf-8")
        (through_dir / "world" / "svc" / "docs").symlink_to(elsewhere)
        calls_before = self.calls
        report = self.run_judge()
        self.assertEqual(self.calls, calls_before)  # nothing was sent to the judge
        self.assertEqual([self.judgment("base", i)["excluded"] for i in range(1, 8)],
                         ["run_invalid", "no_document", "contaminated", "contaminated", "stream_missing", "no_document",
                          "no_document"])
        self.assertEqual(report["arms"]["base"]["judged"], 0)
        self.assertEqual(report["arms"]["base"]["excluded"],
                         {"run_invalid": 1, "no_document": 3, "contaminated": 2, "stream_missing": 1})

    def test_text_the_agent_wrote_is_not_contamination(self):
        self.calibrate()
        self.sample("base", 1, uses=[("Write", {"file_path": "docs/design.md", "content": "see eval/design-rubrics"}),
                                     ("Edit", {"file_path": "docs/design.md", "old_string": "design-judge", "new_string": "x"})])
        self.assertEqual(self.run_judge()["arms"]["base"]["judged"], 1)

    def test_uncalibrated_items_are_left_out_of_every_number(self):
        calibration = {"demo": {"judge_hash": TOOL.judge_hash(self.rubric_dir, "demo", "m", 1),
                                "calibrated": ["stack_deadline"], "mismatches": [], "failures": []}}
        (self.out / "calibration.json").write_text(json.dumps(calibration), encoding="utf-8")
        self.sample("base", 1)
        report = self.run_judge()
        row = report["arms"]["base"]
        self.assertEqual(report["uncalibrated"], ["inv_cap", "dep_direction"])
        self.assertEqual((row["primary_pass"], row["primary_n"], row["invariant_slots"], row["dependency_n"]), (0, 0, 0, 0))
        self.assertEqual(list(row["per_item"]), ["stack_deadline"])

    def test_saved_judgments_are_reused_until_the_record_changes(self):
        self.calibrate()
        sample_dir = self.sample("base", 1)
        self.run_judge()
        calls = self.calls
        self.run_judge()
        self.assertEqual(self.calls, calls)
        (sample_dir / "record.json").write_text(json.dumps({"valid": True, "cost_usd": 0.7, "skills_invoked": []}))
        self.run_judge()
        self.assertEqual(self.calls, calls + 1)

    def test_loaded_bytes_come_from_the_arm_export(self):
        self.calibrate()
        skill = self.runs / "arms" / "base" / "skills" / "software-architecture"
        (skill / "references").mkdir(parents=True)
        (skill / "SKILL.md").write_text("a" * 100, encoding="utf-8")
        (skill / "references" / "rules.md").write_text("b" * 40, encoding="utf-8")
        plugin = lambda index: str(self.runs / "runs" / "demo" / "base" / str(index) / "plugin")
        read = ("Read", {"file_path": plugin(1) + "/skills/software-architecture/references/rules.md"})
        world_read = ("Read", {"file_path": "/elsewhere/skills/software-architecture/references/rules.md"})
        self.sample("base", 1, uses=[read, world_read], skills=["ccl-skills:software-architecture", "simplify"])
        self.sample("base", 2, uses=[("Read", {"file_path": plugin(2) + "/skills/absent/SKILL.md"})])
        self.sample("base", 3, uses=[("Read", {"file_path": plugin(3) + "/skills/../../secret"})])
        self.sample("candidate", 1, skills=["ccl-skills:software-architecture"])  # no export for this arm
        self.run_judge()
        self.assertEqual(self.judgment("base", 1)["loaded_bytes"], 140)  # host skill and non-plugin path not counted
        self.assertIsNone(self.judgment("base", 2)["loaded_bytes"])
        self.assertIsNone(self.judgment("base", 3)["loaded_bytes"])
        self.assertIsNone(self.judgment("candidate", 1)["loaded_bytes"])


class CommandLine(unittest.TestCase):
    def test_check_fixtures_and_argument_errors(self):
        self.assertEqual(TOOL.main(["--check-fixtures"]), 0)
        self.assertEqual(TOOL.main(["--calibrate"]), 2)  # no --out
        self.assertEqual(TOOL.main(["--tasks", "absent", "--check-fixtures"]), 2)
        with tempfile.TemporaryDirectory() as tmp:
            self.assertEqual(TOOL.main(["--out", tmp, "--calibrate", "--votes", "2"]), 2)
            self.assertEqual(TOOL.main(["--out", tmp]), 2)  # no step chosen
        self.assertEqual(TOOL.main(["--out", str(EVAL_DIR / "x"), "--report-only"]), 2)  # inside the checkout
        self.assertFalse((EVAL_DIR / "x").exists())


if __name__ == "__main__":
    unittest.main()
