#!/usr/bin/env python3
import importlib.util
import json
import re
import tempfile
import unittest
from pathlib import Path


EVAL_DIR = Path(__file__).resolve().parent
FIXTURE_PATH = EVAL_DIR / "skill-event-fixtures-v1.json"
AUDIT_PATH = EVAL_DIR / "subagent-owner-audit.py"


def load_audit_module():
    spec = importlib.util.spec_from_file_location("subagent_owner_audit", AUDIT_PATH)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def write_transcript(directory, case):
    path = Path(directory) / f"{case['id']}.jsonl"
    path.write_text(
        "".join(json.dumps(event, ensure_ascii=False) + "\n" for event in case["events"]),
        encoding="utf-8",
    )
    return path


class OwnerAuditV2Test(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.audit = load_audit_module()
        cls.fixture = json.loads(FIXTURE_PATH.read_text(encoding="utf-8"))

    def test_A1_A2_A3_and_D6_known_answer_fixtures(self):
        self.assertEqual("skill-events-v1", self.fixture["event_contract_version"])
        self.assertIn("never generated from parser output", self.fixture["known_answer_source"])

        with tempfile.TemporaryDirectory() as directory:
            for case in self.fixture["cases"]:
                with self.subTest(case=case["id"]):
                    path = write_transcript(directory, case)
                    row = self.audit.runtime_record(path, brief=case["brief"])
                    self.assertEqual(2, row["schema_version"])
                    self.assertEqual("skill-events-v1", row["event_contract_version"])
                    self.assertRegex(row["transcript_shape_id"], r"^sha256:[0-9a-f]{64}$")
                    for key, expected in case["expected"].items():
                        self.assertEqual(expected, row[key], key)

    def test_A1_records_completion_without_promoting_arbitrary_skill_to_ccl_owner(self):
        case = self.fixture["cases"][0]
        with tempfile.TemporaryDirectory() as directory:
            row = self.audit.runtime_record(
                write_transcript(directory, case), brief=case["brief"]
            )
        self.assertEqual(
            [
                {
                    "skill": "superpowers:brainstorming",
                    "tool_use_id": "toolu_generic",
                    "matching_tool_result": True,
                    "completed": True,
                },
                {
                    "skill": "ccl-skills:multi-agent-delegation",
                    "tool_use_id": "toolu_owner",
                    "matching_tool_result": True,
                    "completed": True,
                },
            ],
            row["skill_invocations"],
        )
        self.assertNotIn("superpowers:brainstorming", row["ccl_skills_invoked"])

    def test_A3_malformed_required_skills_is_unverifiable_not_missing(self):
        case = self.fixture["cases"][3]
        with tempfile.TemporaryDirectory() as directory:
            path = write_transcript(directory, case)
            for brief in (
                "Review.\nrequired_skills: ccl-skills:testing-strategy",
                "Review.\nrequired_skills: ['ccl-skills:testing-strategy\"]",
            ):
                with self.subTest(brief=brief):
                    row = self.audit.runtime_record(path, brief=brief)
                    self.assertFalse(row["declared_required_skills_available"])
                    self.assertEqual("unverifiable", row["declared_owner_match_status"])

    def test_A4_runtime_record_excludes_eval_oracle_fields(self):
        case = self.fixture["cases"][0]
        with tempfile.TemporaryDirectory() as directory:
            row = self.audit.runtime_record(
                write_transcript(directory, case), brief=case["brief"]
            )
        for forbidden in (
            "expected_owners",
            "expected_owners_completed",
            "unexpected_ccl_skills_invoked",
            "oracle_owner_status",
            "owner_application_status",
        ):
            self.assertNotIn(forbidden, row)

    def test_A5_report_names_invocation_metrics_without_quality_claim(self):
        rows = []
        with tempfile.TemporaryDirectory() as directory:
            for case in self.fixture["cases"]:
                row = self.audit.runtime_record(
                    write_transcript(directory, case), brief=case["brief"]
                )
                row["kind"] = self.audit.classify_brief(case["brief"])
                rows.append(row)
        report = self.audit.build_report(rows, days=30)
        rendered = self.audit.render_report(report)
        lowered = rendered.lower()
        for forbidden in ("quality improvement", "improved quality", "质量提升", "结果更好"):
            self.assertNotIn(forbidden, lowered)
        for required in (
            "no_skill_tool_use",
            "no_ccl_skill_use",
            "declared_owner_missing",
            "required_skills_not_declared",
            "unverifiable",
        ):
            self.assertIn(required, rendered)
        self.assertNotIn("unowned", rendered)
        self.assertEqual(1, report["metrics"]["declared_owner_not_required"])
        self.assertEqual(2, report["metrics"]["declared_owner_complete"])
        self.assertEqual(
            5,
            report["metrics"]["denominators"][
                "declared_ccl_owner_verifiable"
            ],
        )
        self.assertEqual(1, report["metrics"]["judgment_no_ccl_skill_use"])
        self.assertIn("denominator=skill_events_available", rendered)
        self.assertIn("denominator=judgment_skill_events_available", rendered)

    def test_D7_unknown_shape_has_visible_degraded_and_recovery_record(self):
        case = next(case for case in self.fixture["cases"] if case["id"] == "skill-input-shape-drift")
        with tempfile.TemporaryDirectory() as directory:
            row = self.audit.runtime_record(
                write_transcript(directory, case), brief=case["brief"]
            )
        self.assertEqual("unknown_transcript_shape", row["degraded_reason"])
        self.assertEqual(
            {
                "add_sanitized_known_answer_fixture": True,
                "rerun_d6": True,
                "manual_recovery_required": True,
            },
            row["recovery_record"],
        )

        report = self.audit.build_report([row], days=30)
        self.assertTrue(report["metrics"]["owner_gate_degraded"])
        self.assertEqual(1, report["metrics"]["unverifiable"])
        self.assertEqual([row["transcript_shape_id"]], report["metrics"]["unknown_transcript_shape_ids"])

    def test_v2_compatibility_metrics_are_explicitly_named(self):
        case = self.fixture["cases"][2]
        with tempfile.TemporaryDirectory() as directory:
            row = self.audit.runtime_record(
                write_transcript(directory, case), brief=case["brief"]
            )
        compat = row["compatibility_v1"]
        self.assertEqual(
            {"no_skill_tool_use": False, "required_skills_not_declared": True},
            compat,
        )
        self.assertFalse(any(re.search(r"(^|_)unowned($|_)", key) for key in compat))


if __name__ == "__main__":
    unittest.main()
