#!/usr/bin/env python3
import argparse
import importlib.util
import json
import os
import signal
import subprocess
import sys
import tempfile
import threading
import time
import unittest
from collections import Counter

try:
    import tomllib as _tomllib_available_check  # noqa: F401
    _TOMLLIB_AVAILABLE = True
except ModuleNotFoundError:
    _TOMLLIB_AVAILABLE = False
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path
from unittest import mock


EVAL_DIR = Path(__file__).resolve().parent
TRIAL_DIR = EVAL_DIR / "skill-effectiveness"
TRIAL_PATH = TRIAL_DIR / "trial.py"
RUN_PATH = TRIAL_DIR / "run.py"
ACTIVE_CONTROL_PATH = TRIAL_DIR / "active_control.py"
OPENCODE_PROVIDER_PATH = TRIAL_DIR / "opencode_provider.py"
KIMI_PROVIDER_PATH = TRIAL_DIR / "kimi_provider.py"
PILOT_GATES_PATH = TRIAL_DIR / "pilot-gates.json"
SMOKE_FIXTURE_PATH = TRIAL_DIR / "fixtures" / "e10-smoke.json"
CALIBRATION_FIXTURE_PATH = (
    TRIAL_DIR / "fixtures" / "reviewer-calibration-known-answers.json"
)
CALIBRATION_CASES_PATH = TRIAL_DIR / "fixtures" / "reviewer-calibration-cases.json"
CASE_FIELDS = {"case_id", "task", "rubric", "candidate_a", "candidate_b"}
ARM_DIR = TRIAL_DIR / "arms"
HELDOUT_SCHEMA_PATH = TRIAL_DIR / "heldout-manifest.schema.json"
TASKS_REGRESSION_PATH = TRIAL_DIR / "tasks-regression.jsonl"
GRADER_DIR = TRIAL_DIR / "graders"
BLINDING_KEY = b"k" * 32


def load_trial_module():
    spec = importlib.util.spec_from_file_location(
        "skill_effectiveness_trial", TRIAL_PATH
    )
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def load_run_module():
    spec = importlib.util.spec_from_file_location("skill_effectiveness_run", RUN_PATH)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def load_active_control_module():
    spec = importlib.util.spec_from_file_location(
        "skill_effectiveness_active_control", ACTIVE_CONTROL_PATH
    )
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def arm_template(arm_id, treatment, allowlisted_diff):
    return {
        "schema_version": 1,
        "arm_id": arm_id,
        "scope": "subagent",
        "treatment": treatment,
        "allowlisted_diff": allowlisted_diff,
        "runnable": True,
        "active_control_selection": {"status": "not-applicable"},
    }


def common_components(ccl_layer):
    return {
        "system_prompt": b"synthetic-system",
        "bootstrap": b"",
        "skill_inventory": b"",
        "tool_schema": b"synthetic-tools",
        "hook_command_config": b"",
        "repo_instructions": b"synthetic-repo-contract",
        "ccl_layer": ccl_layer,
    }


def passing_record(expected_trial, family):
    return {
        **expected_trial,
        "task_family": family,
        "runner_completed": True,
        "manifest_diff_valid": True,
        "off_ccl_residual": False,
        "skill_events_verifiable": True,
        "skill_event_shape": "skill-events-v1",
        "matched_call_compliant": True,
        "blinding_leak": False,
        "deterministic_replay_match": True,
        "contaminated": False,
        "budget_complete": True,
        "access_audit_ok": True,
        "memory_isolation_ok": True,
    }


def expected_trial_rows(trial, tasks, arms, samples=3):
    runner_hash = "sha256:" + "d" * 64
    isolation_config_hash = "sha256:" + "c" * 64
    experiment_plan_hash = trial.canonical_hash(
        {
            "tasks": tasks,
            "manifests": {
                arm_id: manifest["manifest_hash"] for arm_id, manifest in arms.items()
            },
            "samples": samples,
        }
    )
    budget = {
        "tokens": None,
        "wall_time_seconds": None,
        "tool_calls": None,
        "cost_units": None,
    }
    rows = []
    for task_id, family in tasks.items():
        task = {
            "task_id": task_id,
            "task_family": family,
            "cohort": "known-regression",
            "prompt_ref": f"fixture://{task_id}",
            "expected_owners": ["ccl-skills:testing-strategy"],
            "frozen_at_sha": "a" * 40,
            "corpus_version": "test-v1",
        }
        task_reference = trial.task_artifact_reference(task)
        for arm_id, manifest in arms.items():
            for sample_index in range(1, samples + 1):
                runtime = {
                    "provider": "fixture",
                    "model": "deterministic",
                    "session_id": f"fresh-{task_id}-{arm_id}-{sample_index}",
                    "isolation_config_hash": isolation_config_hash,
                    "runner_hash": runner_hash,
                    "experiment_plan_hash": experiment_plan_hash,
                }
                trial_location_hash = trial.canonical_hash(
                    f"/synthetic/{task_id}/{arm_id}/{sample_index}"
                )
                fingerprint_input = {
                    "task": task,
                    "manifest_hash": manifest["manifest_hash"],
                    "runtime": runtime,
                    "budget": budget,
                    "sample_index": sample_index,
                    "trial_location_hash": trial_location_hash,
                }
                row = {
                    "task_id": task_id,
                    "arm_id": arm_id,
                    "sample_index": sample_index,
                    "run_order": len(rows) + 1,
                    "task_hash": task_reference["task_hash"],
                    "manifest_hash": manifest["manifest_hash"],
                    "runtime_hash": trial.canonical_hash(runtime),
                    "runner_hash": runner_hash,
                    "experiment_plan_hash": experiment_plan_hash,
                    "task_reference": task_reference,
                    "runtime": runtime,
                    "fingerprint_input": fingerprint_input,
                }
                row["trial_fingerprint"] = trial.canonical_hash(fingerprint_input)
                rows.append(row)
    return rows


def capability_evidence(*, mount_verified=True):
    return {
        "mount_boundary": {
            "probe_id": "filesystem-boundary-v1",
            "status": "verified",
            "observations": {
                "outside_read_denied": mount_verified,
                "outside_write_denied": mount_verified,
            },
        },
        "access_audit": {
            "probe_id": "access-audit-replay-v1",
            "status": "verified",
            "observations": {
                "all_accesses_recorded": True,
                "tamper_check_passed": True,
            },
        },
        "memory_isolation": {
            "probe_id": "fresh-session-canary-v1",
            "status": "verified",
            "observations": {
                "fresh_session": True,
                "cross_session_recall_detected": False,
            },
        },
    }


def capability_evidence_hash(trial, runner, provider, task_family, evidence):
    return trial.canonical_hash(
        {
            "runner": runner,
            "provider": provider,
            "task_family": task_family,
            "evidence": evidence,
        }
    )


def raw_calibration(trial, families=("codex", "claude")):
    fixture = json.loads(CALIBRATION_FIXTURE_PATH.read_text(encoding="utf-8"))
    known_answers = fixture["known_answers"]
    fixture_hash = trial.canonical_hash(known_answers)
    reviewers = []
    for family in families:
        runs = []
        for _ in range(3):
            runs.append(
                [
                    {"case_id": row["case_id"], "verdict": row["expected_verdict"]}
                    for row in known_answers
                ]
            )
        reviewers.append({"family": family, "runs": runs})
    return {
        "status": "evaluated",
        "known_answers": known_answers,
        "known_answer_fixture_hash": fixture_hash,
        "reviewers": reviewers,
    }, fixture_hash


def write_sealed_calibration_result(trial, root, calibration, config):
    root = Path(root)
    root.mkdir(mode=0o700)
    if len(calibration["reviewers"]) != 1:
        raise ValueError("test calibration result requires one reviewer family")
    evaluation = trial.evaluate_reviewer_calibration(calibration, config)
    reviewer = calibration["reviewers"][0]
    evidence_path = root / "reviewer-calibration.json"
    result_path = root / "reviewer-calibration-result.json"
    trial.write_json_atomic(evidence_path, calibration)
    result = {
        "schema_version": 1,
        "artifact_contract": "skill-effectiveness-reviewer-calibration-result-v1",
        "execution_status": "completed",
        "calibration_status": evaluation["status"],
        "provider": "codex",
        "provider_cli_version": "codex-cli test-1.0",
        "provider_executable_hash": "sha256:" + "a" * 64,
        "provider_environment_keys": [],
        "model": "gpt-test-exact",
        "reviewer_family": reviewer["family"],
        "repeat_count": len(reviewer["runs"]),
        "case_count": len(calibration["known_answers"]),
        "known_answer_fixture_hash": calibration["known_answer_fixture_hash"],
        "case_fixture_hash": config["reviewer_calibration_case_fixture_hash"],
        "pilot_gates_hash": trial.canonical_hash(config),
        "runner_contract": "codex-cli-reviewer-calibration-v1",
        "runner_hash": "sha256:" + "c" * 64,
        "requested_session_mode": "ephemeral",
        "tool_access": "rejected",
        "calibration_evidence": evidence_path.name,
        "calibration_evidence_hash": trial.canonical_hash(calibration),
        "calibration_evaluation": evaluation,
        "calibration_evaluation_hash": trial.canonical_hash(evaluation),
        "conclusion_boundary": "reviewer_calibration_only_not_skill_effectiveness",
        "enforcement": "advisory",
    }
    trial.write_json_atomic(result_path, result)
    return result_path


class TrialFoundationTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.trial = load_trial_module()

    def test_committed_regression_tasks_bind_answer_only_execution(self):
        tasks = [
            json.loads(line)
            for line in TASKS_REGRESSION_PATH.read_text(encoding="utf-8").splitlines()
            if line.strip()
        ]

        for task in tasks:
            self.assertEqual("answer_only", task["execution_mode"])
            missing = dict(task)
            missing.pop("execution_mode")
            self.assertIn(
                "execution_mode_invalid",
                self.trial.validate_task_record(missing, committed=True),
            )
            self.assertIn(
                "execution_mode_invalid",
                self.trial.validate_task_record(
                    dict(task, execution_mode="workspace_write"), committed=True
                ),
            )
            reference = self.trial.task_artifact_reference(task)
            self.assertEqual("answer_only", reference["execution_mode"])
            changed = dict(task, execution_mode="workspace_write")
            self.assertNotEqual(
                reference["task_hash"],
                self.trial.task_artifact_reference(changed)["task_hash"],
            )

    def test_manifest_hash_is_stable_and_only_ccl_layer_may_differ(self):
        off_template = arm_template("S0", "off", [])
        oracle_template = arm_template("S1", "oracle", ["ccl_layer"])
        off = self.trial.freeze_arm_manifest(off_template, common_components(b""))
        oracle = self.trial.freeze_arm_manifest(
            oracle_template, common_components(b"frozen-owner-bundle")
        )

        self.assertEqual(
            self.trial.canonical_hash(oracle), self.trial.canonical_hash(oracle)
        )
        self.assertRegex(oracle["manifest_hash"], r"^sha256:[0-9a-f]{64}$")
        self.assertEqual(
            [],
            self.trial.compare_arm_to_off(off, oracle, off_template, oracle_template),
        )

        drifted_components = common_components(b"frozen-owner-bundle")
        drifted_components["tool_schema"] = b"different-tools"
        drifted = self.trial.freeze_arm_manifest(
            arm_template("S1", "oracle", ["ccl_layer"]), drifted_components
        )
        self.assertIn(
            "unallowlisted_diff:tool_schema",
            self.trial.compare_arm_to_off(off, drifted, off_template, oracle_template),
        )

        self_declared = arm_template("S1", "oracle", ["ccl_layer", "tool_schema"])
        self_declared_manifest = self.trial.freeze_arm_manifest(
            self_declared, drifted_components
        )
        self.assertIn(
            "preregistered_template_hash_mismatch",
            self.trial.compare_arm_to_off(
                off,
                self_declared_manifest,
                off_template,
                oracle_template,
            ),
        )

        self_declared_off_template = dict(
            off_template, allowlisted_diff=["ccl_layer"]
        )
        with self.assertRaisesRegex(ValueError, "OFF arm must not allow"):
            self.trial.freeze_arm_manifest(
                self_declared_off_template, common_components(b"")
            )

        extra_component_manifest = dict(oracle)
        extra_component_manifest["component_hashes"] = dict(
            oracle["component_hashes"], undeclared_component="sha256:" + "f" * 64
        )
        extra_component_manifest["manifest_hash"] = self.trial.canonical_hash(
            {
                key: value
                for key, value in extra_component_manifest.items()
                if key != "manifest_hash"
            }
        )
        self.assertIn(
            "component_hashes_set_mismatch",
            self.trial.validate_frozen_manifest(extra_component_manifest),
        )

        duplicate_allowlist = arm_template(
            "S1", "oracle", ["ccl_layer", "ccl_layer"]
        )
        with self.assertRaisesRegex(ValueError, "must not contain duplicates"):
            self.trial.freeze_arm_manifest(
                duplicate_allowlist, common_components(b"frozen-owner-bundle")
            )

        polluted_off_components = common_components(b"")
        polluted_off_components["bootstrap"] = b"CCL bootstrap residual"
        polluted_off = self.trial.freeze_arm_manifest(
            off_template, polluted_off_components
        )
        self.assertEqual(
            ["bootstrap"], self.trial.off_residual_components(polluted_off)
        )

        hidden_manifest_field = dict(oracle, hidden_prompt="unregistered input")
        hidden_manifest_field["manifest_hash"] = self.trial.canonical_hash(
            {
                key: value
                for key, value in hidden_manifest_field.items()
                if key != "manifest_hash"
            }
        )
        self.assertTrue(
            any(
                "extra=['hidden_prompt']" in error
                for error in self.trial.validate_manifest_preregistration(
                    hidden_manifest_field, oracle_template
                )
            )
        )

        with self.assertRaises(ValueError):
            self.trial.canonical_json({"non_finite": float("nan")})
        with self.assertRaisesRegex(
            ValueError, "treatment arm must allow at least one component diff"
        ):
            self.trial.freeze_arm_manifest(
                arm_template("S1", "oracle", []), common_components(b"")
            )

    def test_active_control_selection_is_blinded_hash_bound_and_one_shot(self):
        active_control = load_active_control_module()
        brief = {
            "schema_version": 1,
            "task_families": sorted(self.trial.TASK_FAMILIES),
            "instruction": "Produce neutral execution guidance for both scopes.",
        }
        rubric = {
            "schema_version": 1,
            "criteria": [
                "readability",
                "actionability",
                "information_density",
            ],
        }
        constraints = {
            "schema_version": 1,
            "scopes": ["subagent", "main"],
            "minimum_characters_per_scope": 20,
            "maximum_characters_per_scope": 2000,
        }
        owner_reference = active_control.freeze_owner_reference(
            scope_contents={
                "subagent": "- Review scope closely.\n- Record assumptions clearly.\n\n- Validate evidence before reporting.",
                "main": "- Review scope closely.\n- Limit execution clearly.\n\n- Validate evidence before reporting.",
            }
        )
        input_hash = self.trial.canonical_hash(brief)

        def candidate(author_marker, attestation_marker, subagent_text, main_text):
            scope_contents = {
                "subagent": subagent_text,
                "main": main_text,
            }
            return active_control.freeze_active_control_candidate(
                brief=brief,
                scope_contents=scope_contents,
                generation_evidence={
                    "source_kind": "human-author",
                    "author_commitment_hash": self.trial.canonical_hash(
                        author_marker
                    ),
                    "independence_attestation_hash": self.trial.canonical_hash(
                        attestation_marker
                    ),
                    "input_hash": input_hash,
                    "output_hash": self.trial.canonical_hash(scope_contents),
                },
            )

        candidate_a = candidate(
            "author-alpha",
            "attestation-alpha",
            "Inspect the task, state assumptions, implement narrowly, and verify evidence.",
            "Inspect the task, state assumptions, execute a bounded plan, and verify evidence.",
        )
        candidate_b = candidate(
            "author-beta",
            "attestation-beta",
            "Clarify the outcome, isolate work, check failure paths, and report verification.",
            "Clarify the outcome, isolate work, follow checkpoints, and report verification.",
        )

        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory) / "active-control"
            selector_input = active_control.prepare_active_control(
                output_root=root,
                brief=brief,
                rubric=rubric,
                constraint_spec=constraints,
                owner_reference=owner_reference,
                candidate_packages=[candidate_a, candidate_b],
                opaque_order=["slot-1111111111111111", "slot-2222222222222222"],
            )
            selector_text = self.trial.canonical_json(selector_input).decode("utf-8")
            for hidden in (
                "author-alpha",
                "author-beta",
                "attestation-alpha",
                "attestation-beta",
                "generation_evidence",
                "author_commitment_hash",
                "independence_attestation_hash",
            ):
                self.assertNotIn(hidden, selector_text)

            decision = {
                "schema_version": 1,
                "artifact_contract": "skill-effectiveness-active-control-decision-v1",
                "selector_input_hash": selector_input["selector_input_hash"],
                "rubric_hash": selector_input["rubric_hash"],
                "selected_opaque_id": "slot-1111111111111111",
            }
            selection = active_control.finalize_active_control(root, decision)
            loaded = active_control.load_active_control_selection(
                root / "active-control-selection.json"
            )
            self.assertEqual(selection, loaded)
            self.assertEqual(
                candidate_a["package_hash"], selection["selected_package_hash"]
            )
            self.assertEqual(
                candidate_a["scope_hashes"], selection["selected_scope_hashes"]
            )
            self.assertEqual(
                "human-authorship-attested", selection["independence_status"]
            )
            self.assertEqual(0o600, (root / "active-control-selection.json").stat().st_mode & 0o777)
            with self.assertRaisesRegex(ValueError, "already finalized"):
                active_control.finalize_active_control(root, decision)

        with tempfile.TemporaryDirectory() as duplicate_directory:
            with self.assertRaisesRegex(ValueError, "candidate scope content must differ"):
                active_control.prepare_active_control(
                    output_root=Path(duplicate_directory) / "active-control",
                    brief=brief,
                    rubric=rubric,
                    constraint_spec=constraints,
                    owner_reference=owner_reference,
                    candidate_packages=[candidate_a, candidate_a],
                    opaque_order=["slot-3333333333333333", "slot-4444444444444444"],
                )

        with tempfile.TemporaryDirectory() as hash_directory:
            with self.assertRaisesRegex(ValueError, "candidate package hash mismatch"):
                active_control.prepare_active_control(
                    output_root=Path(hash_directory) / "active-control",
                    brief=brief,
                    rubric=rubric,
                    constraint_spec=constraints,
                    owner_reference=owner_reference,
                    candidate_packages=[
                        dict(candidate_a, package_hash="sha256:" + "f" * 64),
                        candidate_b,
                    ],
                    opaque_order=["slot-3333333333333333", "slot-4444444444444444"],
                )

        with tempfile.TemporaryDirectory() as atomic_directory:
            artifact_path = Path(atomic_directory) / "artifact.json"
            with (
                mock.patch.object(
                    active_control.os, "link", side_effect=OSError("injected link failure")
                ),
                self.assertRaisesRegex(OSError, "injected link failure"),
            ):
                active_control._write_json_exclusive(
                    artifact_path, {"status": "staged"}, "test artifact"
                )
            self.assertFalse(artifact_path.exists())
            self.assertEqual([], list(Path(atomic_directory).iterdir()))

        with tempfile.TemporaryDirectory() as partial_directory:
            root = Path(partial_directory) / "active-control"
            original_writer = active_control._write_json_exclusive

            def fail_controller_state(path, value, label):
                if label == "controller state":
                    raise OSError("injected controller-state failure")
                return original_writer(path, value, label)

            with (
                mock.patch.object(
                    active_control,
                    "_write_json_exclusive",
                    side_effect=fail_controller_state,
                ),
                self.assertRaisesRegex(OSError, "controller-state failure"),
            ):
                active_control.prepare_active_control(
                    output_root=root,
                    brief=brief,
                    rubric=rubric,
                    constraint_spec=constraints,
                    owner_reference=owner_reference,
                    candidate_packages=[candidate_a, candidate_b],
                    opaque_order=["slot-3333333333333333", "slot-4444444444444444"],
                )
            self.assertTrue((root / "active-control-claim.json").exists())
            self.assertFalse((root / "controller-state.json").exists())
            self.assertFalse((root / "selector-input.json").exists())

        with tempfile.TemporaryDirectory() as decision_directory:
            root = Path(decision_directory) / "active-control"
            selector_input = active_control.prepare_active_control(
                output_root=root,
                brief=brief,
                rubric=rubric,
                constraint_spec=constraints,
                owner_reference=owner_reference,
                candidate_packages=[candidate_a, candidate_b],
                opaque_order=["slot-3333333333333333", "slot-4444444444444444"],
            )
            decision = {
                "schema_version": 1,
                "artifact_contract": "skill-effectiveness-active-control-decision-v1",
                "selector_input_hash": selector_input["selector_input_hash"],
                "rubric_hash": selector_input["rubric_hash"],
                "selected_opaque_id": "slot-9999999999999999",
            }
            with self.assertRaisesRegex(ValueError, "selected id is invalid"):
                active_control.finalize_active_control(root, decision)
            self.assertFalse((root / "active-control-selection.json").exists())
            (root / "controller-state.json").unlink()
            with self.assertRaisesRegex(ValueError, "artifact set is incomplete"):
                active_control.finalize_active_control(
                    root,
                    dict(
                        decision,
                        selected_opaque_id=selector_input["opaque_order"][0],
                    ),
                )

        with tempfile.TemporaryDirectory() as tamper_directory:
            root = Path(tamper_directory) / "active-control"
            selector_input = active_control.prepare_active_control(
                output_root=root,
                brief=brief,
                rubric=rubric,
                constraint_spec=constraints,
                owner_reference=owner_reference,
                candidate_packages=[candidate_a, candidate_b],
                opaque_order=["slot-5555555555555555", "slot-6666666666666666"],
            )
            tampered = dict(selector_input, rubric_hash="sha256:" + "f" * 64)
            self.trial.write_json_atomic(root / "selector-input.json", tampered)
            with self.assertRaisesRegex(ValueError, "selector input"):
                active_control.finalize_active_control(
                    root,
                    {
                        "schema_version": 1,
                        "artifact_contract": "skill-effectiveness-active-control-decision-v1",
                        "selector_input_hash": selector_input["selector_input_hash"],
                        "rubric_hash": selector_input["rubric_hash"],
                        "selected_opaque_id": "slot-5555555555555555",
                    },
                )
            self.assertFalse((root / "active-control-selection.json").exists())

    def test_selected_active_control_manifest_requires_sealed_scope_binding(self):
        active_control = load_active_control_module()
        brief = {
            "schema_version": 1,
            "task_families": sorted(self.trial.TASK_FAMILIES),
            "instruction": "Produce neutral guidance.",
        }
        rubric = {
            "schema_version": 1,
            "criteria": ["readability", "actionability", "information_density"],
        }
        constraints = {
            "schema_version": 1,
            "scopes": ["subagent", "main"],
            "minimum_characters_per_scope": 20,
            "maximum_characters_per_scope": 2000,
        }
        owner_reference = active_control.freeze_owner_reference(
            scope_contents={
                "subagent": "- Review scope closely.\n- Record assumptions clearly.\n\n- Validate evidence before reporting.",
                "main": "- Review scope closely.\n- Limit execution clearly.\n\n- Validate evidence before reporting.",
            }
        )

        def candidate(author, subagent_text, main_text):
            scope_contents = {"subagent": subagent_text, "main": main_text}
            return active_control.freeze_active_control_candidate(
                brief=brief,
                scope_contents=scope_contents,
                generation_evidence={
                    "source_kind": "human-author",
                    "author_commitment_hash": self.trial.canonical_hash(author),
                    "independence_attestation_hash": self.trial.canonical_hash(
                        f"attestation-{author}"
                    ),
                    "input_hash": self.trial.canonical_hash(brief),
                    "output_hash": self.trial.canonical_hash(scope_contents),
                },
            )

        candidate_a = candidate(
            "author-a",
            "- Inspect scope carefully.\n- State assumptions clearly.\n\n- Verify evidence before reporting.",
            "- Inspect scope carefully.\n- Bound execution clearly.\n\n- Verify evidence before reporting.",
        )
        candidate_b = candidate(
            "author-b",
            "Alternative subagent guidance with explicit checks.",
            "Alternative main-agent guidance with explicit checks.",
        )
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory) / "active-control"
            selector_input = active_control.prepare_active_control(
                output_root=root,
                brief=brief,
                rubric=rubric,
                constraint_spec=constraints,
                owner_reference=owner_reference,
                candidate_packages=[candidate_a, candidate_b],
                opaque_order=["slot-7777777777777777", "slot-8888888888888888"],
            )
            selection = active_control.finalize_active_control(
                root,
                {
                    "schema_version": 1,
                    "artifact_contract": "skill-effectiveness-active-control-decision-v1",
                    "selector_input_hash": selector_input["selector_input_hash"],
                    "rubric_hash": selector_input["rubric_hash"],
                    "selected_opaque_id": "slot-7777777777777777",
                },
            )
            claim_path = root / "active-control-claim.json"
            claim = self.trial.load_private_json(claim_path)
            self.trial.write_json_atomic(
                claim_path,
                dict(claim, owner_reference_hash="sha256:" + "f" * 64),
            )
            with self.assertRaisesRegex(ValueError, "commitment"):
                active_control.measure_owner_relative(root, owner_reference)
            self.assertFalse((root / "owner-relative-measurement.json").exists())
            self.trial.write_json_atomic(claim_path, claim)

            zero_instruction_owner = active_control.freeze_owner_reference(
                scope_contents={
                    "subagent": "Review scope and validate evidence.",
                    "main": "Review scope and validate evidence.",
                }
            )
            with self.assertRaisesRegex(ValueError, "committed owner reference"):
                active_control.measure_owner_relative(root, zero_instruction_owner)
            self.assertFalse((root / "owner-relative-measurement.json").exists())
            unexpected_path = root / "unexpected.json"
            self.trial.write_json_atomic(unexpected_path, {"unexpected": True})
            with self.assertRaisesRegex(ValueError, "unexpected artifact"):
                active_control.measure_owner_relative(root, owner_reference)
            unexpected_path.unlink()
            measurement = active_control.measure_owner_relative(
                root, owner_reference
            )
            self.assertEqual("pass", measurement["status"])
            self.assertEqual(
                {
                    "paragraph_count": (
                        "normalized-newline-ascii-blank-line-v1"
                    ),
                    "instruction_count": "markdown-list-item-line-v1",
                    "token_count": (
                        "ascii-word-run-or-single-unicode-nonwhitespace-codepoint-v1"
                    ),
                    "tolerance": (
                        "inclusive-integer-cross-multiplication-9-to-11-over-10-v1"
                    ),
                },
                measurement["measurement_contracts"],
            )
            self.assertEqual(
                measurement,
                active_control.load_owner_relative_measurement(
                    root / "owner-relative-measurement.json",
                    selection=selection,
                    owner_reference=owner_reference,
                ),
            )
            self.assertEqual(
                0o600,
                (root / "owner-relative-measurement.json").stat().st_mode & 0o777,
            )
            with self.assertRaisesRegex(ValueError, "already exists"):
                active_control.measure_owner_relative(root, owner_reference)

            tampered_measurement = json.loads(
                self.trial.canonical_json(measurement)
            )
            tampered_measurement["scopes"]["subagent"]["selected"][
                "token_count"
            ] -= 1
            tampered_measurement["measurement_hash"] = self.trial.canonical_hash(
                {
                    key: value
                    for key, value in tampered_measurement.items()
                    if key != "measurement_hash"
                }
            )
            tampered_measurement_path = Path(directory) / "tampered-measurement.json"
            self.trial.write_json_atomic(
                tampered_measurement_path, tampered_measurement
            )
            with self.assertRaisesRegex(ValueError, "selected metrics mismatch"):
                active_control._validate_measurement_payload(
                    self.trial.load_private_json(tampered_measurement_path),
                    selection=selection,
                    owner_reference=owner_reference,
                )
            failed_root = Path(directory) / "failed-active-control"
            failed_selector = active_control.prepare_active_control(
                output_root=failed_root,
                brief=brief,
                rubric=rubric,
                constraint_spec=constraints,
                owner_reference=zero_instruction_owner,
                candidate_packages=[candidate_a, candidate_b],
                opaque_order=["slot-9999999999999998", "slot-9999999999999999"],
            )
            failed_selection = active_control.finalize_active_control(
                failed_root,
                {
                    "schema_version": 1,
                    "artifact_contract": (
                        "skill-effectiveness-active-control-decision-v1"
                    ),
                    "selector_input_hash": failed_selector["selector_input_hash"],
                    "rubric_hash": failed_selector["rubric_hash"],
                    "selected_opaque_id": "slot-9999999999999998",
                },
            )
            failed_measurement = active_control.measure_owner_relative(
                failed_root, zero_instruction_owner
            )
            self.assertEqual("fail", failed_measurement["status"])
            self.assertEqual(
                failed_measurement,
                active_control.load_owner_relative_measurement(
                    failed_root / "owner-relative-measurement.json",
                    selection=failed_selection,
                    owner_reference=zero_instruction_owner,
                ),
            )
            with self.assertRaisesRegex(
                ValueError, "passing owner-relative measurement"
            ):
                active_control.active_control_manifest_binding(
                    failed_selection,
                    scope="subagent",
                    measurement=failed_measurement,
                    owner_reference=zero_instruction_owner,
                )
            with self.assertRaisesRegex(ValueError, "already exists"):
                active_control.measure_owner_relative(failed_root, owner_reference)
            canonical_measurement_path = root / "owner-relative-measurement.json"
            tampered_root_measurement = dict(
                measurement,
                boundary="tampered-root-measurement",
            )
            self.trial.write_json_atomic(
                canonical_measurement_path, tampered_root_measurement
            )
            with self.assertRaisesRegex(
                ValueError, "owner-relative measurement boundary is invalid"
            ):
                active_control.freeze_matched_call_evidence(
                    root,
                    selection=selection,
                    measurement=measurement,
                    owner_reference=owner_reference,
                    scope="subagent",
                    active_bundle_id="generic-guidance-subagent",
                    oracle_bundle_id="oracle-owner-subagent",
                )
            self.trial.write_json_atomic(canonical_measurement_path, measurement)
            collision_results = active_control._matched_call_fixture_results(
                "fixture-wrong-bundle"
            )
            self.assertEqual(
                {
                    "decision": "deny",
                    "reason_code": "matched_call_required",
                    "deny_message": (
                        "complete-required-bundle-before-trial-unlock:"
                        "fixture-wrong-bundle"
                    ),
                    "observation_status": "none-fixtures-only",
                    "live_gate_eligible": False,
                },
                collision_results["wrong_target"],
            )
            fallback_collision_results = active_control._matched_call_fixture_results(
                "fixture-wrong-bundle-0"
            )
            self.assertEqual(
                {
                    "decision": "deny",
                    "reason_code": "matched_call_required",
                    "deny_message": (
                        "complete-required-bundle-before-trial-unlock:"
                        "fixture-wrong-bundle-0"
                    ),
                    "observation_status": "none-fixtures-only",
                    "live_gate_eligible": False,
                },
                fallback_collision_results["wrong_target"],
            )
            self.assertEqual(
                "before-first-task-tool",
                active_control.MATCHED_CALL_GATE_SPEC["gate_phase"],
            )
            self.assertEqual(
                "matching-call-index-strictly-before-first-task-tool-index",
                active_control.MATCHED_CALL_GATE_SPEC["ordering_semantics"],
            )
            self.assertEqual(
                "skill-and-first-task-tool-indexes-globally-unique",
                active_control.MATCHED_CALL_GATE_SPEC[
                    "event_index_uniqueness_semantics"
                ],
            )
            self.assertEqual(
                "fixture-asserted-not-live-host-attested",
                active_control.MATCHED_CALL_GATE_SPEC["event_index_trust_boundary"],
            )
            self.assertEqual(
                "ineligible-requires-authenticated-single-monotonic-host-stream",
                active_control.MATCHED_CALL_GATE_SPEC["live_gate_eligibility"],
            )
            self.assertEqual(
                "new-versioned-live-contract-and-artifact-required",
                active_control.MATCHED_CALL_GATE_SPEC["live_gate_migration"],
            )
            self.assertEqual(
                "globally-unique-across-skill-invocations",
                active_control.MATCHED_CALL_GATE_SPEC[
                    "tool_use_id_uniqueness_semantics"
                ],
            )
            self.assertEqual(
                {
                    "missing": ["deny", "matched_call_required"],
                    "wrong_target": ["deny", "matched_call_required"],
                    "incomplete": ["deny", "matched_call_required"],
                    "degraded": ["deny", "event_contract_unverifiable"],
                    "missing_task_tool_index": [
                        "deny",
                        "event_contract_unverifiable",
                    ],
                    "completed": [
                        "fixture-pass",
                        "fixture_matched_call_satisfied",
                    ],
                    "late_after_task_tool": ["deny", "matched_call_late"],
                },
                active_control.MATCHED_CALL_GATE_SPEC["fixture_expected_outcomes"],
            )
            identical_root = Path(directory) / "identical-content-active-control"
            identical_candidate = candidate(
                "author-identical",
                "- Review scope closely.\n- Record assumptions clearly.\n\n- Validate evidence before reporting.",
                "- Review scope closely.\n- Limit execution clearly.\n\n- Validate evidence before reporting.",
            )
            identical_selector = active_control.prepare_active_control(
                output_root=identical_root,
                brief=brief,
                rubric=rubric,
                constraint_spec=constraints,
                owner_reference=owner_reference,
                candidate_packages=[identical_candidate, candidate_b],
                opaque_order=["slot-6666666666666666", "slot-9999999999999997"],
            )
            identical_selection = active_control.finalize_active_control(
                identical_root,
                {
                    "schema_version": 1,
                    "artifact_contract": (
                        "skill-effectiveness-active-control-decision-v1"
                    ),
                    "selector_input_hash": identical_selector["selector_input_hash"],
                    "rubric_hash": identical_selector["rubric_hash"],
                    "selected_opaque_id": "slot-6666666666666666",
                },
            )
            identical_measurement = active_control.measure_owner_relative(
                identical_root, owner_reference
            )
            with self.assertRaisesRegex(
                ValueError, "active-control bundle id must match selected opaque id"
            ):
                active_control.freeze_matched_call_evidence(
                    identical_root,
                    selection=identical_selection,
                    measurement=identical_measurement,
                    owner_reference=owner_reference,
                    scope="subagent",
                    active_bundle_id="author-identifying-guidance",
                    oracle_bundle_id="oracle-owner-subagent",
                )
            with self.assertRaisesRegex(ValueError, "content hashes must differ"):
                active_control.freeze_matched_call_evidence(
                    identical_root,
                    selection=identical_selection,
                    measurement=identical_measurement,
                    owner_reference=owner_reference,
                    scope="subagent",
                    active_bundle_id="slot-6666666666666666-subagent",
                    oracle_bundle_id="oracle-owner-subagent",
                )
            with self.assertRaisesRegex(
                ValueError, "oracle bundle id must match scope"
            ):
                active_control.freeze_matched_call_evidence(
                    root,
                    selection=selection,
                    measurement=measurement,
                    owner_reference=owner_reference,
                    scope="subagent",
                    active_bundle_id="slot-7777777777777777-subagent",
                    oracle_bundle_id="author-identifying-oracle",
                )
            matched_call_evidence = active_control.freeze_matched_call_evidence(
                root,
                selection=selection,
                measurement=measurement,
                owner_reference=owner_reference,
                scope="subagent",
                active_bundle_id="slot-7777777777777777-subagent",
                oracle_bundle_id="oracle-owner-subagent",
            )
            self.assertEqual(
                "matched-call-contract-declared-no-observation",
                matched_call_evidence["status"],
            )
            self.assertEqual(
                (
                    "deterministic-fixtures-no-observed-call-history-"
                    "or-live-host-enforcement"
                ),
                matched_call_evidence["boundary"],
            )
            self.assertEqual(
                "none-fixtures-only",
                matched_call_evidence["observation_status"],
            )
            self.assertIs(False, matched_call_evidence["matched_call_gate_satisfied"])
            self.assertEqual(
                matched_call_evidence,
                active_control.load_matched_call_evidence(
                    root / "matched-call-evidence-subagent.json",
                    selection=selection,
                    measurement=measurement,
                    owner_reference=owner_reference,
                ),
            )
            mutated_gate_spec = {
                **active_control.MATCHED_CALL_GATE_SPEC,
                "runtime_mutation_probe": "must-not-retain-stale-hash",
            }
            mutated_gate_evidence = {
                **matched_call_evidence,
                "gate_contract": mutated_gate_spec,
            }
            mutated_gate_evidence["artifact_hash"] = self.trial.canonical_hash(
                {
                    key: value
                    for key, value in mutated_gate_evidence.items()
                    if key != "artifact_hash"
                }
            )
            with mock.patch.object(
                active_control, "MATCHED_CALL_GATE_SPEC", mutated_gate_spec
            ):
                with self.assertRaisesRegex(
                    ValueError, "matched-call gate contract hash mismatch"
                ):
                    active_control._validate_matched_call_evidence(
                        mutated_gate_evidence,
                        selection=selection,
                        measurement=measurement,
                        owner_reference=owner_reference,
                    )
            with mock.patch.object(
                active_control,
                "MATCHED_CALL_FIXTURE_EXPECTED_OUTCOMES",
                {"missing": ["fixture-pass", "wrong"]},
            ):
                with self.assertRaisesRegex(
                    ValueError, "matched-call fixture outcome contract mismatch"
                ):
                    active_control._matched_call_fixture_results(
                        "fixture-contract-drift"
                    )
            drifted_fixture_evidence = json.loads(
                self.trial.canonical_json(matched_call_evidence)
            )
            for target_kind in ("active_control", "oracle"):
                drifted_fixture_evidence["fixture_results"][target_kind][
                    "missing"
                ]["deny_message"] = "runtime-drifted-denial"
            drifted_fixture_evidence["artifact_hash"] = self.trial.canonical_hash(
                {
                    key: value
                    for key, value in drifted_fixture_evidence.items()
                    if key != "artifact_hash"
                }
            )
            original_fixture_results = active_control._matched_call_fixture_results

            def drifted_fixture_results(target_bundle_id):
                results = original_fixture_results(target_bundle_id)
                results["missing"]["deny_message"] = "runtime-drifted-denial"
                return results

            with mock.patch.object(
                active_control,
                "_matched_call_fixture_results",
                side_effect=drifted_fixture_results,
            ):
                with self.assertRaisesRegex(
                    ValueError, "matched-call fixture results mismatch"
                ):
                    active_control._validate_matched_call_evidence(
                        drifted_fixture_evidence,
                        selection=selection,
                        measurement=measurement,
                        owner_reference=owner_reference,
                    )
            self.assertEqual(
                0o600,
                (root / "matched-call-evidence-subagent.json").stat().st_mode
                & 0o777,
            )
            main_matched_call_evidence = active_control.freeze_matched_call_evidence(
                root,
                selection=selection,
                measurement=measurement,
                owner_reference=owner_reference,
                scope="main",
                active_bundle_id="slot-7777777777777777-main",
                oracle_bundle_id="oracle-owner-main",
            )
            self.assertEqual("main", main_matched_call_evidence["scope"])
            self.assertEqual(
                main_matched_call_evidence,
                active_control.load_matched_call_evidence(
                    root / "matched-call-evidence-main.json",
                    selection=selection,
                    measurement=measurement,
                    owner_reference=owner_reference,
                ),
            )
            with self.assertRaisesRegex(ValueError, "already exists"):
                active_control.freeze_matched_call_evidence(
                    root,
                    selection=selection,
                    measurement=measurement,
                    owner_reference=owner_reference,
                    scope="subagent",
                    active_bundle_id="generic-guidance-subagent",
                    oracle_bundle_id="oracle-owner-subagent",
                )
            self.trial.write_json_atomic(root / "unexpected.json", {"extra": True})
            with self.assertRaisesRegex(ValueError, "unexpected artifact"):
                active_control.freeze_matched_call_evidence(
                    root,
                    selection=selection,
                    measurement=measurement,
                    owner_reference=owner_reference,
                    scope="subagent",
                    active_bundle_id="slot-7777777777777777-subagent",
                    oracle_bundle_id="oracle-owner-subagent",
                )
            (root / "unexpected.json").unlink()

            stable_events = {
                "schema_version": 1,
                "event_contract_version": "skill-events-v2",
                "event_contract_status": "stable",
                "skill_events_available": True,
                "task_tool_events_available": True,
                "first_task_tool_event_index": 0,
                "event_index_source": "fixture-modeled-single-monotonic-stream",
                "skills_invoked": [],
            }
            denied = active_control._evaluate_matched_call_fixture(
                stable_events, target_bundle_id="generic-guidance-subagent"
            )
            self.assertEqual(
                ("deny", "matched_call_required"),
                (denied["decision"], denied["reason_code"]),
            )
            with mock.patch.object(
                active_control,
                "MATCHED_CALL_GATE_SPEC",
                {
                    **active_control.MATCHED_CALL_GATE_SPEC,
                    "deny_template": "mutated-template:{target_bundle_id}",
                },
            ):
                frozen_template_denial = (
                    active_control._evaluate_matched_call_fixture(
                        stable_events,
                        target_bundle_id="generic-guidance-subagent",
                    )
                )
            self.assertEqual(
                "complete-required-bundle-before-trial-unlock:"
                "generic-guidance-subagent",
                frozen_template_denial["deny_message"],
            )
            empty_degenerate_window = dict(
                stable_events,
                first_task_tool_event_index=1_000_000_000,
            )
            self.assertEqual(
                ("deny", "event_contract_unverifiable"),
                tuple(
                    active_control._evaluate_matched_call_fixture(
                        empty_degenerate_window,
                        target_bundle_id="generic-guidance-subagent",
                    )[field]
                    for field in ("decision", "reason_code")
                ),
            )
            invalid_target = active_control._evaluate_matched_call_fixture(
                stable_events, target_bundle_id="invalid target id"
            )
            self.assertEqual(
                ("deny", "event_contract_unverifiable"),
                (invalid_target["decision"], invalid_target["reason_code"]),
            )
            self.assertEqual("invalid-target", invalid_target["target_bundle_id"])
            self.assertIsNone(invalid_target["deny_message"])
            missing_task_tool_index = dict(
                stable_events, first_task_tool_event_index=None
            )
            self.assertEqual(
                ("deny", "event_contract_unverifiable"),
                tuple(
                    active_control._evaluate_matched_call_fixture(
                        missing_task_tool_index,
                        target_bundle_id="generic-guidance-subagent",
                    )[field]
                    for field in ("decision", "reason_code")
                ),
            )
            duplicate_tool_use_ids = dict(
                stable_events,
                skills_invoked=[
                    {
                        "skill": "different-bundle",
                        "event_index": 0,
                        "tool_use_id": "toolu-duplicate-id",
                        "matching_tool_result": True,
                        "completed": True,
                    },
                    {
                        "skill": "generic-guidance-subagent",
                        "event_index": 2,
                        "tool_use_id": "toolu-duplicate-id",
                        "matching_tool_result": True,
                        "completed": True,
                    },
                ],
            )
            self.assertEqual(
                ("deny", "event_contract_unverifiable"),
                tuple(
                    active_control._evaluate_matched_call_fixture(
                        duplicate_tool_use_ids,
                        target_bundle_id="generic-guidance-subagent",
                    )[field]
                    for field in ("decision", "reason_code")
                ),
            )
            unshared_event_stream = dict(
                stable_events,
                event_index_source="independent-self-reported-streams",
            )
            self.assertEqual(
                ("deny", "event_contract_unverifiable"),
                tuple(
                    active_control._evaluate_matched_call_fixture(
                        unshared_event_stream,
                        target_bundle_id="generic-guidance-subagent",
                    )[field]
                    for field in ("decision", "reason_code")
                ),
            )

            class ExplodingEventRecord(dict):
                def get(self, key, default=None):
                    raise RuntimeError("synthetic event decoder failure")

            self.assertEqual(
                ("deny", "event_contract_unverifiable"),
                tuple(
                    active_control._evaluate_matched_call_fixture(
                        ExplodingEventRecord(stable_events),
                        target_bundle_id="generic-guidance-subagent",
                    )[field]
                    for field in ("decision", "reason_code")
                ),
            )
            wrong_target = dict(
                stable_events,
                skills_invoked=[
                    {
                        "skill": "different-bundle",
                        "event_index": 0,
                        "tool_use_id": "toolu-wrong",
                        "matching_tool_result": True,
                        "completed": True,
                    }
                ],
            )
            self.assertEqual(
                "deny",
                active_control._evaluate_matched_call_fixture(
                    wrong_target,
                    target_bundle_id="generic-guidance-subagent",
                )["decision"],
            )
            incomplete = dict(
                stable_events,
                skills_invoked=[
                    {
                        "skill": "generic-guidance-subagent",
                        "event_index": 0,
                        "tool_use_id": "toolu-incomplete",
                        "matching_tool_result": True,
                        "completed": False,
                    }
                ],
            )
            self.assertEqual(
                "deny",
                active_control._evaluate_matched_call_fixture(
                    incomplete,
                    target_bundle_id="generic-guidance-subagent",
                )["decision"],
            )
            degraded = dict(stable_events, event_contract_status="degraded")
            self.assertEqual(
                ("deny", "event_contract_unverifiable"),
                tuple(
                    active_control._evaluate_matched_call_fixture(
                        degraded,
                        target_bundle_id="generic-guidance-subagent",
                    )[field]
                    for field in ("decision", "reason_code")
                ),
            )
            duplicate_indexes = dict(
                stable_events,
                skills_invoked=[
                    {
                        "skill": "different-bundle",
                        "event_index": 0,
                        "tool_use_id": "toolu-first",
                        "matching_tool_result": True,
                        "completed": True,
                    },
                    {
                        "skill": "generic-guidance-subagent",
                        "event_index": 0,
                        "tool_use_id": "toolu-duplicate",
                        "matching_tool_result": True,
                        "completed": True,
                    },
                ],
            )
            self.assertEqual(
                ("deny", "event_contract_unverifiable"),
                tuple(
                    active_control._evaluate_matched_call_fixture(
                        duplicate_indexes,
                        target_bundle_id="generic-guidance-subagent",
                    )[field]
                    for field in ("decision", "reason_code")
                ),
            )
            malformed = dict(
                stable_events,
                skills_invoked=[{"skill": "generic-guidance-subagent"}],
            )
            self.assertEqual(
                ("deny", "event_contract_unverifiable"),
                tuple(
                    active_control._evaluate_matched_call_fixture(
                        malformed,
                        target_bundle_id="generic-guidance-subagent",
                    )[field]
                    for field in ("decision", "reason_code")
                ),
            )
            oversized = dict(
                stable_events,
                skills_invoked=[
                    {
                        "skill": "different-bundle",
                        "event_index": index,
                        "tool_use_id": f"toolu-{index}",
                        "matching_tool_result": True,
                        "completed": True,
                    }
                    for index in range(1025)
                ],
            )
            self.assertEqual(
                ("deny", "event_contract_unverifiable"),
                tuple(
                    active_control._evaluate_matched_call_fixture(
                        oversized,
                        target_bundle_id="generic-guidance-subagent",
                    )[field]
                    for field in ("decision", "reason_code")
                ),
            )
            completed = dict(
                stable_events,
                first_task_tool_event_index=1,
                skills_invoked=[
                    {
                        "skill": "generic-guidance-subagent",
                        "event_index": 0,
                        "tool_use_id": "toolu-complete",
                        "matching_tool_result": True,
                        "completed": True,
                    }
                ],
            )
            self.assertEqual(
                ("fixture-pass", "fixture_matched_call_satisfied"),
                tuple(
                    active_control._evaluate_matched_call_fixture(
                        completed,
                        target_bundle_id="generic-guidance-subagent",
                    )[field]
                    for field in ("decision", "reason_code")
                ),
            )
            task_tool_index_collision = dict(
                completed,
                skills_invoked=[
                    *completed["skills_invoked"],
                    {
                        "skill": "different-bundle",
                        "event_index": 1,
                        "tool_use_id": "toolu-task-index-collision",
                        "matching_tool_result": True,
                        "completed": True,
                    },
                ],
            )
            self.assertEqual(
                ("deny", "event_contract_unverifiable"),
                tuple(
                    active_control._evaluate_matched_call_fixture(
                        task_tool_index_collision,
                        target_bundle_id="generic-guidance-subagent",
                    )[field]
                    for field in ("decision", "reason_code")
                ),
            )
            degenerate_window = dict(
                completed,
                first_task_tool_event_index=1_000_000_000,
            )
            self.assertEqual(
                ("deny", "event_contract_unverifiable"),
                tuple(
                    active_control._evaluate_matched_call_fixture(
                        degenerate_window,
                        target_bundle_id="generic-guidance-subagent",
                    )[field]
                    for field in ("decision", "reason_code")
                ),
            )
            late = dict(
                stable_events,
                skills_invoked=[
                    {
                        "skill": "generic-guidance-subagent",
                        "event_index": 2,
                        "tool_use_id": "toolu-late",
                        "matching_tool_result": True,
                        "completed": True,
                    }
                ],
            )
            self.assertEqual(
                ("deny", "matched_call_late"),
                tuple(
                    active_control._evaluate_matched_call_fixture(
                        late,
                        target_bundle_id="generic-guidance-subagent",
                    )[field]
                    for field in ("decision", "reason_code")
                ),
            )

            tampered_evidence = json.loads(
                self.trial.canonical_json(matched_call_evidence)
            )
            tampered_evidence["targets"]["active_control"]["content_hash"] = (
                "sha256:" + "f" * 64
            )
            tampered_evidence["artifact_hash"] = self.trial.canonical_hash(
                {
                    key: value
                    for key, value in tampered_evidence.items()
                    if key != "artifact_hash"
                }
            )
            tampered_path = Path(directory) / "tampered-matched-call.json"
            self.trial.write_json_atomic(tampered_path, tampered_evidence)
            with self.assertRaisesRegex(ValueError, "canonical private root"):
                active_control.load_matched_call_evidence(
                    tampered_path,
                    selection=selection,
                    measurement=measurement,
                    owner_reference=owner_reference,
                )
            with self.assertRaisesRegex(
                ValueError, "active-control target content hash mismatch"
            ):
                active_control._validate_matched_call_evidence(
                    tampered_evidence,
                    selection=selection,
                    measurement=measurement,
                    owner_reference=owner_reference,
                )
            with self.assertRaises(TypeError):
                active_control._validate_matched_call_evidence(
                    matched_call_evidence
                )
        binding = active_control.active_control_manifest_binding(
            selection,
            measurement=measurement,
            owner_reference=owner_reference,
            scope="subagent",
        )
        with self.assertRaisesRegex(ValueError, "requires owner-relative measurement"):
            active_control.active_control_manifest_binding(
                selection, scope="subagent"
            )
        template = {
            "schema_version": 1,
            "arm_id": "Sg",
            "scope": "subagent",
            "treatment": "active_control",
            "allowlisted_diff": ["ccl_layer"],
            "runnable": True,
            "active_control_selection": binding,
        }
        content = candidate_a["scope_contents"]["subagent"].encode("utf-8")
        with self.assertRaisesRegex(
            ValueError, "matched-call fixture evidence cannot enter an arm manifest"
        ):
            self.trial.freeze_arm_manifest(
                {
                    **template,
                    "runnable": False,
                    "active_control_selection": matched_call_evidence,
                },
                common_components(content),
            )
        disguised_matched_call_evidence = {
            "status": "pending",
            "gate_contract": matched_call_evidence["gate_contract"],
            "targets": matched_call_evidence["targets"],
            "boundary": matched_call_evidence["boundary"],
        }
        with self.assertRaisesRegex(
            ValueError, "pending active-control selection field set is invalid"
        ):
            self.trial.freeze_arm_manifest(
                {
                    **template,
                    "runnable": False,
                    "active_control_selection": disguised_matched_call_evidence,
                },
                common_components(content),
            )
        disguised_owner_relative_evidence = {
            **binding,
            "gate_contract": matched_call_evidence["gate_contract"],
            "fixture_results": matched_call_evidence["fixture_results"],
        }
        with self.assertRaisesRegex(
            ValueError, "selected active-control binding field set is invalid"
        ):
            self.trial.freeze_arm_manifest(
                {
                    **template,
                    "runnable": False,
                    "active_control_selection": disguised_owner_relative_evidence,
                },
                common_components(content),
            )
        with self.assertRaisesRegex(
            ValueError, "selected active-control binding field set is invalid"
        ):
            self.trial.freeze_arm_manifest(
                {
                    **arm_template("S0", "off", []),
                    "active_control_selection": disguised_owner_relative_evidence,
                },
                common_components(b""),
            )
        with self.assertRaisesRegex(
            ValueError, "active-control matched-call gate is pending"
        ):
            self.trial.freeze_arm_manifest(
                template,
                common_components(content),
                active_control_selection_artifact=selection,
                active_control_measurement_artifact=measurement,
                active_control_owner_reference_artifact=owner_reference,
            )

        template["runnable"] = False
        manifest = self.trial.freeze_arm_manifest(
            template,
            common_components(content),
            active_control_selection_artifact=selection,
            active_control_measurement_artifact=measurement,
            active_control_owner_reference_artifact=owner_reference,
        )
        self.assertEqual(
            selection["artifact_hash"],
            manifest["active_control_selection"]["artifact_hash"],
        )

        with self.assertRaisesRegex(ValueError, "sealed active-control selection"):
            self.trial.freeze_arm_manifest(template, common_components(content))
        with self.assertRaisesRegex(ValueError, "selected active-control scope"):
            self.trial.freeze_arm_manifest(
                dict(template, scope="main"),
                common_components(content),
                active_control_selection_artifact=selection,
            )
        with self.assertRaisesRegex(ValueError, "selected active-control hash"):
            self.trial.freeze_arm_manifest(
                template,
                common_components(b"different generic guidance"),
                active_control_selection_artifact=selection,
                active_control_measurement_artifact=measurement,
                active_control_owner_reference_artifact=owner_reference,
            )

        for selected, owner, expected in (
            (9, 10, True),
            (11, 10, True),
            (8, 10, False),
            (12, 10, False),
        ):
            self.assertEqual(
                expected,
                active_control._within_owner_tolerance(selected, owner),
            )

        lf_content = (
            "- Alpha 一.\n+ Beta.\n* Gamma.\n1. Delta.\n2) Epsilon.\n"
            "• Zeta.\n\nTail"
        )
        expected_metrics = {
            "paragraph_count": 2,
            "instruction_count": 5,
            "token_count": 22,
        }
        for content in (
            lf_content,
            lf_content.replace("\n", "\r\n"),
            lf_content.replace("\n", "\r"),
        ):
            self.assertEqual(
                expected_metrics,
                active_control._content_metrics(content),
            )
        for unicode_space in ("\u00a0", "\u3000"):
            self.assertEqual(
                2,
                active_control._content_metrics(
                    f"Alpha{unicode_space}Beta"
                )["token_count"],
            )

    def test_active_control_cli_prepares_finalizes_and_verifies_private_artifact(self):
        active_control = load_active_control_module()
        run_module = load_run_module()
        with self.assertRaisesRegex(ValueError, "outside the source checkout"):
            run_module.load_external_private_json(
                ACTIVE_CONTROL_PATH, "active-control candidate"
            )
        with self.assertRaisesRegex(ValueError, "outside the source checkout"):
            run_module.load_external_private_json(
                ACTIVE_CONTROL_PATH, "active-control decision"
            )
        brief = {
            "schema_version": 1,
            "task_families": sorted(self.trial.TASK_FAMILIES),
            "instruction": "Produce neutral guidance.",
        }
        rubric = {
            "schema_version": 1,
            "criteria": ["readability", "actionability", "information_density"],
        }
        constraints = {
            "schema_version": 1,
            "scopes": ["subagent", "main"],
            "minimum_characters_per_scope": 20,
            "maximum_characters_per_scope": 2000,
        }

        def candidate(author, subagent_text, main_text):
            scope_contents = {"subagent": subagent_text, "main": main_text}
            return active_control.freeze_active_control_candidate(
                brief=brief,
                scope_contents=scope_contents,
                generation_evidence={
                    "source_kind": "human-author",
                    "author_commitment_hash": self.trial.canonical_hash(author),
                    "independence_attestation_hash": self.trial.canonical_hash(
                        f"attestation-{author}"
                    ),
                    "input_hash": self.trial.canonical_hash(brief),
                    "output_hash": self.trial.canonical_hash(scope_contents),
                },
            )

        candidates = [
            candidate(
                "author-a",
                "- Inspect scope carefully.\n- State assumptions clearly.\n\n- Verify evidence before reporting.",
                "- Inspect scope carefully.\n- Bound execution clearly.\n\n- Verify evidence before reporting.",
            ),
            candidate(
                "author-b",
                "Alternative subagent guidance with explicit checks.",
                "Alternative main-agent guidance with explicit checks.",
            ),
        ]
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            input_root = root / "inputs"
            input_root.mkdir(mode=0o700)
            paths = {
                "brief": input_root / "brief.json",
                "rubric": input_root / "rubric.json",
                "constraints": input_root / "constraints.json",
                "candidate-a": input_root / "candidate-a.json",
                "candidate-b": input_root / "candidate-b.json",
            }
            for name, value in (
                ("brief", brief),
                ("rubric", rubric),
                ("constraints", constraints),
                ("candidate-a", candidates[0]),
                ("candidate-b", candidates[1]),
            ):
                self.trial.write_json_atomic(paths[name], value)
            owner_contents = {
                "subagent": "- Review scope closely.\n- Record assumptions clearly.\n\n- Validate evidence before reporting.",
                "main": "- Review scope closely.\n- Limit execution clearly.\n\n- Validate evidence before reporting.",
            }
            owner_scope_paths = {
                scope: input_root / f"owner-{scope}.md"
                for scope in ("subagent", "main")
            }
            for scope, path in owner_scope_paths.items():
                self.trial._atomic_write(path, owner_contents[scope].encode("utf-8"))
            owner_reference_path = input_root / "owner-reference.json"
            self.assertEqual(
                0,
                run_module.main(
                    [
                        "active-control-freeze-owner-reference",
                        "--subagent",
                        str(owner_scope_paths["subagent"]),
                        "--main",
                        str(owner_scope_paths["main"]),
                        "--out",
                        str(owner_reference_path),
                    ]
                ),
            )
            owner_reference = self.trial.load_private_json(owner_reference_path)
            self.assertEqual(
                active_control.freeze_owner_reference(
                    scope_contents=owner_contents
                ),
                owner_reference,
            )

            bad_inputs = (
                (
                    "brief-provenance",
                    dict(brief, provenance={"author": "hidden-author"}),
                    rubric,
                    "selector brief field set",
                ),
                (
                    "rubric-provider",
                    brief,
                    dict(rubric, provider="hidden-provider"),
                    "selector rubric field set",
                ),
            )
            for case_name, bad_brief, bad_rubric, expected_error in bad_inputs:
                bad_brief_path = input_root / f"{case_name}-brief.json"
                bad_rubric_path = input_root / f"{case_name}-rubric.json"
                self.trial.write_json_atomic(bad_brief_path, bad_brief)
                self.trial.write_json_atomic(bad_rubric_path, bad_rubric)
                bad_output = root / case_name
                with tempfile.TemporaryFile(mode="w+") as stderr:
                    with mock.patch("sys.stderr", stderr):
                        exit_code = run_module.main(
                            [
                                "active-control-prepare",
                                "--brief",
                                str(bad_brief_path),
                                "--rubric",
                                str(bad_rubric_path),
                                "--constraints",
                                str(paths["constraints"]),
                                "--owner-reference",
                                str(owner_reference_path),
                                "--candidate",
                                str(paths["candidate-a"]),
                                "--candidate",
                                str(paths["candidate-b"]),
                                "--out",
                                str(bad_output),
                            ]
                        )
                    stderr.seek(0)
                    error_text = stderr.read()
                self.assertEqual(2, exit_code)
                self.assertIn(expected_error, error_text)
                self.assertFalse((bad_output / "selector-input.json").exists())

            output_root = root / "active-control"
            self.assertEqual(
                0,
                run_module.main(
                    [
                        "active-control-prepare",
                        "--brief",
                        str(paths["brief"]),
                        "--rubric",
                        str(paths["rubric"]),
                        "--constraints",
                        str(paths["constraints"]),
                        "--owner-reference",
                        str(owner_reference_path),
                        "--candidate",
                        str(paths["candidate-a"]),
                        "--candidate",
                        str(paths["candidate-b"]),
                        "--out",
                        str(output_root),
                    ]
                ),
            )
            selector_input = self.trial.load_private_json(
                output_root / "selector-input.json"
            )
            self.assertEqual(2, len(set(selector_input["opaque_order"])))
            decision = {
                "schema_version": 1,
                "artifact_contract": "skill-effectiveness-active-control-decision-v1",
                "selector_input_hash": selector_input["selector_input_hash"],
                "rubric_hash": selector_input["rubric_hash"],
                "selected_opaque_id": selector_input["opaque_order"][0],
            }
            decision_path = input_root / "decision.json"
            self.trial.write_json_atomic(decision_path, decision)
            self.assertEqual(
                0,
                run_module.main(
                    [
                        "active-control-finalize",
                        "--out",
                        str(output_root),
                        "--decision",
                        str(decision_path),
                    ]
                ),
            )
            selection_path = output_root / "active-control-selection.json"
            self.assertEqual(
                0,
                run_module.main(
                    ["active-control-verify", "--selection", str(selection_path)]
                ),
            )
            self.assertEqual(0o600, selection_path.stat().st_mode & 0o777)
            self.assertEqual(
                0,
                run_module.main(
                    [
                        "active-control-measure",
                        "--out",
                        str(output_root),
                        "--owner-reference",
                        str(owner_reference_path),
                    ]
                ),
            )
            measurement_path = output_root / "owner-relative-measurement.json"
            self.assertEqual(
                0,
                run_module.main(
                    [
                        "active-control-measure-verify",
                        "--selection",
                        str(selection_path),
                        "--owner-reference",
                        str(owner_reference_path),
                        "--measurement",
                        str(measurement_path),
                    ]
                ),
            )
            self.assertEqual(0o600, measurement_path.stat().st_mode & 0o777)
            with tempfile.TemporaryFile(mode="w+") as stdout:
                with mock.patch("sys.stdout", stdout):
                    freeze_exit = run_module.main(
                    [
                        "active-control-matched-call",
                        "--out",
                        str(output_root),
                        "--selection",
                        str(selection_path),
                        "--measurement",
                        str(measurement_path),
                        "--owner-reference",
                        str(owner_reference_path),
                        "--scope",
                        "subagent",
                        "--active-bundle-id",
                        f"{decision['selected_opaque_id']}-subagent",
                        "--oracle-bundle-id",
                        "oracle-owner-subagent",
                    ]
                    )
                stdout.seek(0)
                freeze_output = stdout.read()
            self.assertEqual(3, freeze_exit)
            self.assertIn("artifact_write_status=created", freeze_output)
            self.assertIn("matched_call_gate=NOT_SATISFIED", freeze_output)
            self.assertIn("observation_status=none-fixtures-only", freeze_output)
            self.assertIn(
                "evidence=matched-call-evidence-subagent.json", freeze_output
            )
            self.assertNotIn(str(output_root), freeze_output)
            matched_call_path = (
                output_root / "matched-call-evidence-subagent.json"
            )
            with tempfile.TemporaryFile(mode="w+") as stdout:
                with mock.patch("sys.stdout", stdout):
                    verify_exit = run_module.main(
                        [
                            "active-control-matched-call-verify",
                            "--selection",
                            str(selection_path),
                            "--measurement",
                            str(measurement_path),
                            "--owner-reference",
                            str(owner_reference_path),
                            "--evidence",
                            str(matched_call_path),
                        ]
                    )
                stdout.seek(0)
                verify_output = stdout.read()
            self.assertEqual(4, verify_exit)
            self.assertIn(
                "verification_status=fixture-contract-valid-no-observation",
                verify_output,
            )
            self.assertIn(
                "artifact_write_status=not-applicable-read-only", verify_output
            )
            self.assertIn("matched_call_gate=NOT_SATISFIED", verify_output)
            self.assertIn("observation_status=none-fixtures-only", verify_output)
            self.assertEqual(0o600, matched_call_path.stat().st_mode & 0o777)
            self.trial.write_json_atomic(matched_call_path, [])
            with tempfile.TemporaryFile(mode="w+") as stderr:
                with mock.patch("sys.stderr", stderr):
                    malformed_exit = run_module.main(
                        [
                            "active-control-matched-call-verify",
                            "--selection",
                            str(selection_path),
                            "--measurement",
                            str(measurement_path),
                            "--owner-reference",
                            str(owner_reference_path),
                            "--evidence",
                            str(matched_call_path),
                        ]
                    )
                stderr.seek(0)
                malformed_error = stderr.read()
            self.assertEqual(2, malformed_exit)
            self.assertIn("matched-call evidence must be an object", malformed_error)
            matched_call_path.write_text("{", encoding="utf-8")
            with tempfile.TemporaryFile(mode="w+") as stderr:
                with mock.patch("sys.stderr", stderr):
                    invalid_json_exit = run_module.main(
                        [
                            "active-control-matched-call-verify",
                            "--selection",
                            str(selection_path),
                            "--measurement",
                            str(measurement_path),
                            "--owner-reference",
                            str(owner_reference_path),
                            "--evidence",
                            str(matched_call_path),
                        ]
                    )
                stderr.seek(0)
                invalid_json_error = stderr.read()
            self.assertEqual(2, invalid_json_exit)
            self.assertNotIn(str(output_root), invalid_json_error)
            with mock.patch.object(
                run_module,
                "run_active_control_matched_call_verify",
                side_effect=TypeError(f"unexpected type at {matched_call_path}"),
            ):
                with (
                    tempfile.TemporaryFile(mode="w+") as stdout,
                    tempfile.TemporaryFile(mode="w+") as stderr,
                ):
                    with (
                        mock.patch("sys.stdout", stdout),
                        mock.patch("sys.stderr", stderr),
                    ):
                        unexpected_exit = run_module.main(
                            [
                                "active-control-matched-call-verify",
                                "--selection",
                                str(selection_path),
                                "--measurement",
                                str(measurement_path),
                                "--owner-reference",
                                str(owner_reference_path),
                                "--evidence",
                                str(matched_call_path),
                            ]
                        )
                    stdout.seek(0)
                    unexpected_output = stdout.read()
                    stderr.seek(0)
                    unexpected_error = stderr.read()
            self.assertEqual(2, unexpected_exit)
            self.assertIn("matched_call_gate=NOT_SATISFIED", unexpected_output)
            self.assertIn("unexpected type", unexpected_error)
            self.assertNotIn(str(output_root), unexpected_error)
            redaction_args = argparse.Namespace(
                out=output_root,
                selection=selection_path,
                measurement=measurement_path,
                owner_reference=owner_reference_path,
                evidence=matched_call_path,
            )
            with mock.patch.object(
                Path, "resolve", side_effect=OSError("symlink loop")
            ):
                redacted_error = run_module._redact_matched_call_error(
                    f"invalid artifact at {matched_call_path}", redaction_args
                )
            self.assertNotIn(str(output_root), redacted_error)
            relative_redaction_args = argparse.Namespace(
                out=Path("out"),
                selection=Path("s"),
                measurement=None,
                owner_reference=None,
                evidence=None,
            )
            relative_message = "output remains useful without short-path mangling"
            self.assertEqual(
                relative_message,
                run_module._redact_matched_call_error(
                    relative_message, relative_redaction_args
                ),
            )
            short_absolute_args = argparse.Namespace(
                out=Path("/tmp/ac"),
                selection=None,
                measurement=None,
                owner_reference=None,
                evidence=None,
            )
            self.assertNotIn(
                "/tmp/ac",
                run_module._redact_matched_call_error(
                    "invalid private root: /tmp/ac", short_absolute_args
                ),
            )
            self.assertEqual(
                2,
                run_module.main(
                    [
                        "active-control-prepare",
                        "--brief",
                        str(paths["brief"]),
                        "--rubric",
                        str(paths["rubric"]),
                        "--constraints",
                        str(paths["constraints"]),
                        "--owner-reference",
                        str(owner_reference_path),
                        "--candidate",
                        str(paths["candidate-a"]),
                        "--out",
                        str(root / "missing-candidate"),
                    ]
                ),
            )

    def test_isolation_assessment_fails_closed_on_memory_or_path_escape(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            checkout = root / "checkout"
            output = root / "output"
            checkout.mkdir()
            output.mkdir()
            evidence = {
                "fresh_session": True,
                "forked_from_existing": False,
                "auto_memory_enabled": False,
                "vector_retrieval_enabled": False,
                "session_recall_enabled": False,
                "cross_session_cache_enabled": False,
                "provider_persistence": "disabled",
                "canary_leak_detected": False,
            }
            audit = [
                {
                    "actor": "tested-agent",
                    "operation": "read",
                    "path": str(checkout / "task.txt"),
                },
                {
                    "actor": "tested-agent",
                    "operation": "write",
                    "path": str(output / "answer.txt"),
                },
            ]
            ok = self.trial.assess_isolation(evidence, audit, [checkout], [output])
            self.assertEqual("ok", ok["status"])

            for field, value in (
                ("fresh_session", False),
                ("forked_from_existing", True),
                ("auto_memory_enabled", True),
                ("vector_retrieval_enabled", True),
                ("session_recall_enabled", True),
                ("cross_session_cache_enabled", True),
                ("provider_persistence", "enabled"),
            ):
                observed_memory_breach = self.trial.assess_isolation(
                    dict(evidence, **{field: value}),
                    audit,
                    [checkout],
                    [output],
                )
                self.assertEqual(
                    "contaminated",
                    observed_memory_breach["memory_isolation_status"],
                    field,
                )

            missing_memory_proof = self.trial.assess_isolation(
                dict(evidence, session_recall_enabled=None),
                audit,
                [checkout],
                [output],
            )
            self.assertEqual(
                "unresolved_isolation_threat",
                missing_memory_proof["memory_isolation_status"],
            )

            canary_leak = self.trial.assess_isolation(
                dict(evidence, canary_leak_detected=True),
                audit,
                [checkout],
                [output],
            )
            self.assertEqual("contaminated", canary_leak["status"])
            self.assertEqual("ok", canary_leak["file_access_status"])
            self.assertEqual("contaminated", canary_leak["memory_isolation_status"])
            self.assertIn("canary_leak_detected", canary_leak["reasons"])

            escaped = audit + [
                {
                    "actor": "tested-agent",
                    "operation": "read",
                    "path": str(root / "runner-secret.txt"),
                }
            ]
            contaminated = self.trial.assess_isolation(
                evidence, escaped, [checkout], [output]
            )
            self.assertEqual("contaminated", contaminated["status"])
            self.assertTrue(
                any(
                    "path_outside_allowlist" in reason
                    for reason in contaminated["reasons"]
                )
            )
            combined = self.trial.assess_isolation(
                dict(evidence, session_recall_enabled=True),
                escaped,
                [checkout],
                [output],
            )
            self.assertEqual("contaminated", combined["status"])
            self.assertEqual("contaminated", combined["file_access_status"])
            self.assertEqual(
                "contaminated",
                combined["memory_isolation_status"],
            )

            relative = self.trial.assess_isolation(
                evidence,
                [
                    {
                        "actor": "tested-agent",
                        "operation": "read",
                        "path": "relative.txt",
                    }
                ],
                [checkout],
                [output],
            )
            self.assertEqual("contaminated", relative["status"])
            self.assertIn("access_event_path_not_absolute:0", relative["reasons"])

            broad = self.trial.assess_isolation(evidence, audit, [Path("/")], [output])
            self.assertEqual("contaminated", broad["status"])
            self.assertIn("allow_root_too_broad:/", broad["reasons"])

            output_read = self.trial.assess_isolation(
                evidence,
                [
                    {
                        "actor": "tested-agent",
                        "operation": "read",
                        "path": str(output / "answer.txt"),
                    }
                ],
                [checkout],
                [output],
            )
            self.assertEqual("contaminated", output_read["status"])

            wrong_actor = [dict(audit[0], actor="controller"), audit[1]]
            actor_failure = self.trial.assess_isolation(
                evidence, wrong_actor, [checkout], [output]
            )
            self.assertEqual("contaminated", actor_failure["status"])
            self.assertIn("access_event_actor_invalid:0", actor_failure["reasons"])

            overlapping = self.trial.assess_isolation(
                evidence, audit, [checkout, output], [output]
            )
            self.assertEqual("contaminated", overlapping["status"])
            self.assertIn("read_write_allow_roots_overlap", overlapping["reasons"])

            control_write = self.trial.assess_isolation(
                evidence,
                audit,
                [checkout],
                [output],
                forbidden_write_paths=[output / "trial.json"],
            )
            self.assertEqual("contaminated", control_write["status"])
            self.assertTrue(
                any(
                    reason.startswith("write_allowlist_contains_control_path:")
                    for reason in control_write["reasons"]
                )
            )

            ambiguous_open = self.trial.assess_isolation(
                evidence,
                [
                    {
                        "actor": "tested-agent",
                        "operation": "open",
                        "path": str(output / "answer.txt"),
                    }
                ],
                [checkout],
                [output],
            )
            self.assertIn("access_event_open_mode_invalid:0", ambiguous_open["reasons"])

            write_open = self.trial.assess_isolation(
                evidence,
                [
                    {
                        "actor": "tested-agent",
                        "operation": "open",
                        "access_mode": "write",
                        "path": str(root / "controller" / "trial.json"),
                    }
                ],
                [checkout],
                [output],
            )
            self.assertTrue(
                any(
                    "path_outside_allowlist" in reason
                    for reason in write_open["reasons"]
                )
            )

    def test_trial_artifact_is_hash_bound_atomic_and_resumable(self):
        manifest = self.trial.freeze_arm_manifest(
            arm_template("S0", "off", []), common_components(b"")
        )
        task = {
            "task_id": "fixture-review-1",
            "task_family": "review",
            "cohort": "known-regression",
            "prompt_ref": "fixture://F8",
            "expected_owners": ["ccl-skills:testing-strategy"],
            "frozen_at_sha": "a" * 40,
            "corpus_version": "synthetic-v1",
        }
        runtime = {
            "provider": "fixture",
            "model": "deterministic",
            "session_id": "fresh-session-1",
            "isolation_config_hash": "sha256:" + "b" * 64,
            "runner_hash": "sha256:" + "d" * 64,
            "experiment_plan_hash": "sha256:" + "e" * 64,
        }
        budget = {
            "tokens": 1000,
            "wall_time_seconds": 60,
            "tool_calls": 8,
            "cost_units": 1,
        }

        pending_control = self.trial.freeze_arm_manifest(
            {
                "schema_version": 1,
                "arm_id": "Sg",
                "scope": "subagent",
                "treatment": "active_control",
                "allowlisted_diff": ["ccl_layer"],
                "runnable": False,
                "active_control_selection": {
                    "status": "pending",
                    "required_independent_candidates": 2,
                    "selection_blinded_before_outcomes": True,
                },
            },
            common_components(b"pending-generic-guidance"),
        )
        with self.assertRaisesRegex(ValueError, "arm_id must match"):
            self.trial.freeze_arm_manifest(
                arm_template("..", "off", []), common_components(b"")
            )
        with tempfile.TemporaryDirectory() as pending_directory:
            with self.assertRaisesRegex(ValueError, "arm manifest is not runnable"):
                self.trial.prepare_trial(
                    Path(pending_directory),
                    task,
                    pending_control,
                    runtime,
                    budget,
                    sample_index=1,
                )

        with tempfile.TemporaryDirectory() as missing_directory:
            missing_runner_hash = dict(runtime)
            missing_runner_hash.pop("runner_hash")
            with self.assertRaisesRegex(
                ValueError, "runtime field missing: runner_hash"
            ):
                self.trial.prepare_trial(
                    Path(missing_directory),
                    task,
                    manifest,
                    missing_runner_hash,
                    budget,
                    sample_index=1,
                )

        with tempfile.TemporaryDirectory() as direct_completion_directory:
            direct_completion = self.trial.prepare_trial(
                Path(direct_completion_directory),
                task,
                manifest,
                runtime,
                budget,
                sample_index=1,
            )
            with self.assertRaisesRegex(
                ValueError, "finite-budget completion requires a consumption cursor"
            ):
                self.trial.checkpoint_trial(
                    Path(direct_completion["trial_dir"]), status="completed"
                )

        with tempfile.TemporaryDirectory() as missing_cursor_directory:
            missing_cursor = self.trial.prepare_trial(
                Path(missing_cursor_directory),
                task,
                manifest,
                runtime,
                budget,
                sample_index=1,
            )
            missing_cursor_path = Path(missing_cursor["trial_dir"]) / "trial.json"
            missing_cursor_payload = self.trial.load_private_json(missing_cursor_path)
            missing_cursor_payload["status"] = "running"
            missing_cursor_payload["state_version"] = 1
            self.trial.write_json_atomic(missing_cursor_path, missing_cursor_payload)
            with self.assertRaisesRegex(
                ValueError, "running trial resume cursor is missing consumption"
            ):
                self.trial.prepare_trial(
                    Path(missing_cursor_directory),
                    task,
                    manifest,
                    runtime,
                    budget,
                    sample_index=1,
                )

        with tempfile.TemporaryDirectory() as directory:
            created = self.trial.prepare_trial(
                Path(directory), task, manifest, runtime, budget, sample_index=1
            )
            self.assertEqual("created", created["mode"])
            self.assertEqual(0, created["state_version"])
            trial_path = Path(created["trial_dir"]) / "trial.json"
            payload = json.loads(trial_path.read_text(encoding="utf-8"))
            self.assertEqual(manifest["manifest_hash"], payload["manifest_hash"])
            self.assertNotIn("expected_owners", payload["task"])
            alternate_task = dict(
                task, expected_owners=["ccl-skills:defect-diagnosis"]
            )
            self.assertEqual(
                self.trial.task_artifact_reference(task),
                self.trial.task_artifact_reference(alternate_task),
            )
            self.assertEqual(0o600, trial_path.stat().st_mode & 0o777)
            trial_dir = Path(created["trial_dir"])
            self.assertEqual(0o700, trial_dir.parent.stat().st_mode & 0o777)
            self.assertEqual(0o700, trial_dir.parent.parent.stat().st_mode & 0o777)

            resumed = self.trial.prepare_trial(
                Path(directory), task, manifest, runtime, budget, sample_index=1
            )
            self.assertEqual("resume", resumed["mode"])

            checkpoint_version = self.trial.checkpoint_trial(
                Path(created["trial_dir"]),
                status="interim-budget-stop",
                resume_cursor={
                    "next_run_order": 4,
                    "consumed_budget": {
                        "tokens": 200,
                        "wall_time_seconds": 10,
                        "tool_calls": 2,
                        "cost_units": 0.25,
                    },
                },
                stop_reason="budget_threshold",
                expected_state_version=created["state_version"],
            )
            self.assertEqual(1, checkpoint_version)
            checkpoint = json.loads(trial_path.read_text(encoding="utf-8"))
            self.assertEqual("interim-budget-stop", checkpoint["status"])
            self.assertFalse(checkpoint["completion_claim"])
            self.assertEqual(4, checkpoint["resume_cursor"]["next_run_order"])
            budget_resume = self.trial.prepare_trial(
                Path(directory), task, manifest, runtime, budget, sample_index=1
            )
            self.assertEqual("resume", budget_resume["mode"])
            self.assertEqual(800, budget_resume["remaining_budget"]["tokens"])
            self.assertEqual(0.75, budget_resume["remaining_budget"]["cost_units"])
            with self.assertRaisesRegex(
                ValueError, "budget-stop checkpoint must advance consumption"
            ):
                self.trial.checkpoint_trial(
                    trial_dir,
                    status="interim-budget-stop",
                    resume_cursor=checkpoint["resume_cursor"],
                )
            rolled_back_cursor = json.loads(json.dumps(checkpoint["resume_cursor"]))
            rolled_back_cursor["consumed_budget"]["tokens"] = 199
            with self.assertRaisesRegex(ValueError, "must be monotonic"):
                self.trial.checkpoint_trial(
                    trial_dir,
                    status="interim-budget-stop",
                    resume_cursor=rolled_back_cursor,
                )
            with self.assertRaisesRegex(ValueError, "must be monotonic"):
                self.trial.checkpoint_trial(
                    trial_dir,
                    status="running",
                    resume_cursor=rolled_back_cursor,
                )
            order_rollback_cursor = json.loads(json.dumps(checkpoint["resume_cursor"]))
            order_rollback_cursor["next_run_order"] = 3
            with self.assertRaisesRegex(ValueError, "next_run_order must be monotonic"):
                self.trial.checkpoint_trial(
                    trial_dir,
                    status="running",
                    resume_cursor=order_rollback_cursor,
                )
            running_version = self.trial.checkpoint_trial(
                trial_dir,
                status="running",
                expected_state_version=checkpoint["state_version"],
            )
            self.assertEqual(2, running_version)
            running_resume = self.trial.prepare_trial(
                Path(directory), task, manifest, runtime, budget, sample_index=1
            )
            self.assertEqual(800, running_resume["remaining_budget"]["tokens"])
            self.assertEqual(2, running_resume["state_version"])
            with self.assertRaisesRegex(ValueError, "must be monotonic"):
                self.trial.checkpoint_trial(
                    trial_dir,
                    status="interim-budget-stop",
                    resume_cursor=rolled_back_cursor,
                )
            advanced_cursor = json.loads(json.dumps(checkpoint["resume_cursor"]))
            advanced_cursor["next_run_order"] = 5
            advanced_cursor["consumed_budget"]["tokens"] = 250
            self.trial.checkpoint_trial(
                trial_dir,
                status="interim-budget-stop",
                resume_cursor=advanced_cursor,
            )

            with self.assertRaisesRegex(ValueError, "completion evidence missing"):
                self.trial.checkpoint_trial(
                    Path(created["trial_dir"]), status="completed"
                )
            self.trial.write_jsonl_atomic(trial_dir / "events.jsonl", [])
            self.trial.write_jsonl_atomic(
                trial_dir / "access-audit.jsonl",
                [
                    {
                        "actor": "tested-agent",
                        "operation": "read",
                        "path": str(Path(directory) / "agent-checkout" / "task.json"),
                    },
                    {
                        "actor": "tested-agent",
                        "operation": "write",
                        "path": str(trial_dir / "outcome" / "result.json"),
                    },
                ],
            )
            (Path(directory) / "agent-checkout").mkdir(mode=0o700)
            self.trial.write_json_atomic(
                trial_dir / "outcome" / "result.json", {"passed": True}
            )
            with self.assertRaisesRegex(ValueError, "events.jsonl:empty"):
                self.trial.checkpoint_trial(trial_dir, status="completed")
            self.trial.write_jsonl_atomic(trial_dir / "events.jsonl", [{}])
            with self.assertRaisesRegex(ValueError, "events.jsonl:invalid_jsonl"):
                self.trial.checkpoint_trial(trial_dir, status="completed")
            self.trial.write_jsonl_atomic(
                trial_dir / "events.jsonl",
                [
                    {
                        "event_contract": "trial-lifecycle-v1",
                        "type": "runner-complete",
                        "skills_invoked": [],
                    }
                ],
            )
            clean_isolation_evidence = {
                "fresh_session": True,
                "forked_from_existing": False,
                "auto_memory_enabled": False,
                "vector_retrieval_enabled": False,
                "session_recall_enabled": False,
                "cross_session_cache_enabled": False,
                "provider_persistence": "disabled",
                "canary_leak_detected": False,
            }
            valid_access_events = self.trial.load_private_jsonl(
                trial_dir / "access-audit.jsonl"
            )
            self.trial.write_jsonl_atomic(
                trial_dir / "access-audit.jsonl",
                valid_access_events
                + [
                    {
                        "actor": "tested-agent",
                        "operation": "read",
                        "path": str(Path(directory) / "controller-secret.json"),
                    }
                ],
            )
            with self.assertRaisesRegex(ValueError, "isolation check failed"):
                self.trial.checkpoint_trial(
                    trial_dir,
                    status="completed",
                    isolation_evidence=clean_isolation_evidence,
                    read_allow_roots=[Path(directory) / "agent-checkout"],
                    write_allow_roots=[trial_dir / "outcome"],
                )
            self.trial.write_jsonl_atomic(
                trial_dir / "access-audit.jsonl", valid_access_events
            )
            with self.assertRaisesRegex(ValueError, "isolation check failed"):
                self.trial.checkpoint_trial(
                    trial_dir,
                    status="completed",
                    isolation_evidence=clean_isolation_evidence,
                    read_allow_roots=[Path(directory) / "agent-checkout"],
                    write_allow_roots=[trial_dir],
                )
            self.trial.checkpoint_trial(
                trial_dir,
                status="completed",
                isolation_evidence=clean_isolation_evidence,
                read_allow_roots=[Path(directory) / "agent-checkout"],
                write_allow_roots=[trial_dir / "outcome"],
            )
            with self.assertRaisesRegex(
                ValueError, "expected isolation roots are missing"
            ):
                self.trial.prepare_trial(
                    Path(directory),
                    task,
                    manifest,
                    runtime,
                    budget,
                    sample_index=1,
                    expected_isolation_evidence=clean_isolation_evidence,
                )
            with self.assertRaisesRegex(
                ValueError, "expected isolation evidence is missing"
            ):
                self.trial.prepare_trial(
                    Path(directory),
                    task,
                    manifest,
                    runtime,
                    budget,
                    sample_index=1,
                    expected_read_allow_roots=[Path(directory) / "agent-checkout"],
                    expected_write_allow_roots=[trial_dir / "outcome"],
                )
            complete = self.trial.prepare_trial(
                Path(directory),
                task,
                manifest,
                runtime,
                budget,
                sample_index=1,
                expected_isolation_evidence=clean_isolation_evidence,
                expected_read_allow_roots=[Path(directory) / "agent-checkout"],
                expected_write_allow_roots=[trial_dir / "outcome"],
            )
            self.assertEqual("complete", complete["mode"])
            with self.assertRaisesRegex(
                ValueError, "terminal trial cannot transition from completed"
            ):
                self.trial.checkpoint_trial(
                    trial_dir,
                    status="completed",
                    isolation_evidence=clean_isolation_evidence,
                    read_allow_roots=[Path(directory) / "agent-checkout"],
                    write_allow_roots=[trial_dir / "outcome"],
                )

            completed_payload = json.loads(trial_path.read_text(encoding="utf-8"))
            downgraded_current_payload = json.loads(json.dumps(completed_payload))
            downgraded_current_payload.pop("completion_binding_hash")
            downgraded_current_isolation = downgraded_current_payload[
                "completion_isolation"
            ]
            downgraded_current_isolation.pop("evidence_tier")
            downgraded_current_isolation.pop("coverage_limitations")
            self.trial.write_json_atomic(trial_path, downgraded_current_payload)
            with self.assertRaisesRegex(
                ValueError, "completed trial evidence tier does not match registry"
            ):
                self.trial.prepare_trial(
                    Path(directory),
                    task,
                    manifest,
                    runtime,
                    budget,
                    sample_index=1,
                    expected_isolation_evidence=clean_isolation_evidence,
                    expected_read_allow_roots=[Path(directory) / "agent-checkout"],
                    expected_write_allow_roots=[trial_dir / "outcome"],
                )

            legacy_completed_payload = json.loads(json.dumps(completed_payload))
            legacy_completed_payload.pop("registry_schema")
            legacy_completed_payload.pop("completion_binding_hash")
            legacy_isolation = legacy_completed_payload["completion_isolation"]
            legacy_isolation.pop("evidence_tier")
            legacy_isolation.pop("coverage_limitations")
            self.trial.write_json_atomic(trial_path, legacy_completed_payload)
            with self.assertRaisesRegex(ValueError, "fixed fields do not match"):
                self.trial.prepare_trial(
                    Path(directory),
                    task,
                    manifest,
                    runtime,
                    budget,
                    sample_index=1,
                    expected_isolation_evidence=clean_isolation_evidence,
                    expected_read_allow_roots=[Path(directory) / "agent-checkout"],
                    expected_write_allow_roots=[trial_dir / "outcome"],
                )

            partial_tier_payload = json.loads(json.dumps(completed_payload))
            partial_tier_payload["completion_isolation"].pop(
                "coverage_limitations"
            )
            self.trial.write_json_atomic(trial_path, partial_tier_payload)
            with self.assertRaisesRegex(
                ValueError, "isolation evidence is inconsistent"
            ):
                self.trial.prepare_trial(
                    Path(directory),
                    task,
                    manifest,
                    runtime,
                    budget,
                    sample_index=1,
                    expected_isolation_evidence=clean_isolation_evidence,
                    expected_read_allow_roots=[Path(directory) / "agent-checkout"],
                    expected_write_allow_roots=[trial_dir / "outcome"],
                )
            self.trial.write_json_atomic(trial_path, completed_payload)

            mismatched_tier_payload = json.loads(json.dumps(completed_payload))
            mismatched_tier_payload["completion_isolation"]["evidence_tier"] = (
                self.trial.checkpoint_evidence_tier("paired-profile")
            )
            self.trial.write_json_atomic(trial_path, mismatched_tier_payload)
            with self.assertRaisesRegex(
                ValueError, "evidence tier does not match registry"
            ):
                self.trial.prepare_trial(
                    Path(directory),
                    task,
                    manifest,
                    runtime,
                    budget,
                    sample_index=1,
                    expected_isolation_evidence=clean_isolation_evidence,
                    expected_read_allow_roots=[Path(directory) / "agent-checkout"],
                    expected_write_allow_roots=[trial_dir / "outcome"],
                )
            self.trial.write_json_atomic(trial_path, completed_payload)

            missing_completion_cursor = json.loads(json.dumps(completed_payload))
            missing_completion_cursor.pop("resume_cursor", None)
            self.trial.write_json_atomic(trial_path, missing_completion_cursor)
            with self.assertRaisesRegex(
                ValueError, "completed trial consumption cursor is missing"
            ):
                self.trial.prepare_trial(
                    Path(directory),
                    task,
                    manifest,
                    runtime,
                    budget,
                    sample_index=1,
                    expected_isolation_evidence=clean_isolation_evidence,
                    expected_read_allow_roots=[Path(directory) / "agent-checkout"],
                    expected_write_allow_roots=[trial_dir / "outcome"],
                )
            self.trial.write_json_atomic(trial_path, completed_payload)

            broader_roots = json.loads(json.dumps(completed_payload))
            broader_roots["completion_isolation"]["read_allow_roots"] = [directory]
            broader_roots["completion_isolation"]["evidence_hash"] = completed_payload[
                "completion_isolation"
            ]["evidence_hash"]
            self.trial.write_json_atomic(trial_path, broader_roots)
            with self.assertRaisesRegex(
                ValueError, "completion binding mismatch"
            ):
                self.trial.prepare_trial(
                    Path(directory),
                    task,
                    manifest,
                    runtime,
                    budget,
                    sample_index=1,
                    expected_isolation_evidence=clean_isolation_evidence,
                    expected_read_allow_roots=[Path(directory) / "agent-checkout"],
                    expected_write_allow_roots=[trial_dir / "outcome"],
                )
            self.trial.write_json_atomic(trial_path, completed_payload)

            tampered_evidence = json.loads(json.dumps(completed_payload))
            tampered_evidence["completion_isolation"]["evidence"][
                "auto_memory_enabled"
            ] = True
            tampered_evidence["completion_isolation"]["evidence_hash"] = (
                self.trial.canonical_hash(
                    tampered_evidence["completion_isolation"]["evidence"]
                )
            )
            self.trial.write_json_atomic(trial_path, tampered_evidence)
            with self.assertRaisesRegex(
                ValueError, "completion binding mismatch"
            ):
                self.trial.prepare_trial(
                    Path(directory),
                    task,
                    manifest,
                    runtime,
                    budget,
                    sample_index=1,
                    expected_isolation_evidence=clean_isolation_evidence,
                    expected_read_allow_roots=[Path(directory) / "agent-checkout"],
                    expected_write_allow_roots=[trial_dir / "outcome"],
                )
            self.trial.write_json_atomic(trial_path, completed_payload)

            outcome_path = trial_dir / "outcome" / "result.json"
            original_outcome = self.trial.load_private_json(outcome_path)
            self.trial.write_json_atomic(
                outcome_path,
                dict(
                    original_outcome,
                    passed=not original_outcome.get("passed", False),
                ),
            )
            with self.assertRaisesRegex(ValueError, "completion binding mismatch"):
                self.trial.prepare_trial(
                    Path(directory),
                    task,
                    manifest,
                    runtime,
                    budget,
                    sample_index=1,
                    expected_isolation_evidence=clean_isolation_evidence,
                    expected_read_allow_roots=[Path(directory) / "agent-checkout"],
                    expected_write_allow_roots=[trial_dir / "outcome"],
                )
            self.trial.write_json_atomic(outcome_path, original_outcome)

            outcome_dir = trial_dir / "outcome"
            outcome_dir.chmod(0o755)
            with self.assertRaisesRegex(ValueError, "must already be 0700"):
                self.trial.prepare_trial(
                    Path(directory), task, manifest, runtime, budget, sample_index=1
                )
            outcome_dir.chmod(0o700)

            self.trial.write_json_atomic(
                trial_path, dict(completed_payload, arm_id="tampered-arm")
            )
            with self.assertRaisesRegex(ValueError, "fixed fields do not match"):
                self.trial.prepare_trial(
                    Path(directory), task, manifest, runtime, budget, sample_index=1
                )
            self.trial.write_json_atomic(trial_path, completed_payload)

            changed_runtime = dict(runtime, model="changed")
            with self.assertRaisesRegex(
                ValueError, "existing trial fingerprint mismatch"
            ):
                self.trial.prepare_trial(
                    Path(directory),
                    task,
                    manifest,
                    changed_runtime,
                    budget,
                    sample_index=1,
                )

            with self.assertRaisesRegex(
                ValueError, "budget limits must be null or positive"
            ):
                self.trial.prepare_trial(
                    Path(directory),
                    task,
                    manifest,
                    runtime,
                    dict(budget, tokens=float("nan")),
                    sample_index=4,
                )

            with self.assertRaisesRegex(
                ValueError, "existing trial fingerprint mismatch"
            ):
                self.trial.prepare_trial(
                    Path(directory),
                    alternate_task,
                    manifest,
                    runtime,
                    budget,
                    sample_index=1,
                )

            terminal = self.trial.prepare_trial(
                Path(directory), task, manifest, runtime, budget, sample_index=2
            )
            terminal_dir = Path(terminal["trial_dir"])
            self.trial.checkpoint_trial(terminal_dir, status="contaminated")
            with self.assertRaisesRegex(
                ValueError, "terminal trial cannot transition from contaminated"
            ):
                self.trial.checkpoint_trial(terminal_dir, status="completed")
            with self.assertRaisesRegex(ValueError, "trial is terminal: contaminated"):
                self.trial.prepare_trial(
                    Path(directory), task, manifest, runtime, budget, sample_index=2
                )

            exhausted = self.trial.prepare_trial(
                Path(directory), task, manifest, runtime, budget, sample_index=4
            )
            self.trial.checkpoint_trial(
                Path(exhausted["trial_dir"]),
                status="interim-budget-stop",
                resume_cursor={
                    "next_run_order": 9,
                    "consumed_budget": dict(budget),
                },
            )
            with self.assertRaisesRegex(ValueError, "trial budget exhausted"):
                self.trial.prepare_trial(
                    Path(directory), task, manifest, runtime, budget, sample_index=4
                )

            unlimited_budget = {field: None for field in budget}
            unlimited = self.trial.prepare_trial(
                Path(directory),
                task,
                manifest,
                runtime,
                unlimited_budget,
                sample_index=5,
            )
            self.trial.checkpoint_trial(
                Path(unlimited["trial_dir"]),
                status="interim-budget-stop",
                resume_cursor={
                    "next_run_order": 100,
                    "consumed_budget": {
                        "tokens": 50000,
                        "wall_time_seconds": 5000,
                        "tool_calls": 500,
                        "cost_units": 500,
                    },
                },
            )
            unlimited_resume = self.trial.prepare_trial(
                Path(directory),
                task,
                manifest,
                runtime,
                unlimited_budget,
                sample_index=5,
            )
            self.assertEqual(
                {field: None for field in budget},
                unlimited_resume["remaining_budget"],
            )

            outside = Path(directory) / "outside"
            outside.mkdir()
            symlink_trial = (
                Path(directory) / task["task_id"] / manifest["arm_id"] / "sample-003"
            )
            symlink_trial.symlink_to(outside, target_is_directory=True)
            with self.assertRaisesRegex(ValueError, "must not be a symlink"):
                self.trial.prepare_trial(
                    Path(directory), task, manifest, runtime, budget, sample_index=3
                )

        with tempfile.TemporaryDirectory() as directory:
            original_root = Path(directory) / "original-root"
            self.trial.prepare_trial(
                original_root, task, manifest, runtime, budget, sample_index=1
            )
            moved_root = Path(directory) / "moved-root"
            original_root.rename(moved_root)
            with self.assertRaisesRegex(
                ValueError, "existing trial fingerprint mismatch"
            ):
                self.trial.prepare_trial(
                    moved_root, task, manifest, runtime, budget, sample_index=1
                )

        with tempfile.TemporaryDirectory() as directory:
            container = Path(directory) / "shared"
            container.mkdir(mode=0o755)
            with self.assertRaisesRegex(ValueError, "must already be 0700"):
                self.trial.ensure_private_directory(container)
            self.assertEqual(0o755, container.stat().st_mode & 0o777)

            unsafe_parent = container / "unsafe-shared"
            unsafe_parent.mkdir(mode=0o700)
            unsafe_parent.chmod(0o777)
            with self.assertRaisesRegex(ValueError, "writable without sticky-bit"):
                self.trial.ensure_private_directory(unsafe_parent / "private-out")
            self.assertFalse((unsafe_parent / "private-out").exists())
            nested_output = container / "private-parent" / "nested-out"
            self.trial.ensure_private_directory(nested_output)
            self.assertEqual(0o700, nested_output.parent.stat().st_mode & 0o777)
            self.assertEqual(0o700, nested_output.stat().st_mode & 0o777)
            with mock.patch.object(
                self.trial.os,
                "geteuid",
                return_value=nested_output.stat().st_uid + 1,
            ):
                with self.assertRaisesRegex(ValueError, "must be owned by caller"):
                    self.trial.ensure_private_directory(nested_output)
            output = container / "out"
            self.trial.ensure_private_directory(output)
            with self.assertRaisesRegex(ValueError, "escapes trusted root"):
                self.trial.ensure_private_directory(output / ".." / "escaped", output)
            self.assertFalse((container / "escaped").exists())
            self.assertEqual(0o755, container.stat().st_mode & 0o777)

            invalid_task = dict(task, task_id="..")
            with self.assertRaisesRegex(ValueError, "task_id_invalid"):
                self.trial.prepare_trial(
                    output, invalid_task, manifest, runtime, budget, sample_index=1
                )

            source_output = TRIAL_DIR / "out" / "primitive-negative"
            self.assertFalse(source_output.exists())
            with self.assertRaisesRegex(ValueError, "outside the source checkout"):
                self.trial.prepare_trial(
                    source_output,
                    task,
                    manifest,
                    runtime,
                    budget,
                    sample_index=1,
                )
            self.assertFalse(source_output.exists())

    def test_advisory_checkpoint_records_missing_proof_without_waiving_a_breach(self):
        manifest = self.trial.freeze_profile_arm_manifest(
            profile_arm_template("profile-off", "off", []),
            profile_components(b"built-in-profile-text"),
        )
        task = {
            "task_id": "advisory-checkpoint",
            "task_family": "review",
            "cohort": "known-regression",
            "prompt_ref": "fixture://advisory-checkpoint",
            "expected_owners": ["ccl-skills:testing-strategy"],
            "frozen_at_sha": "a" * 40,
            "corpus_version": "synthetic-v1",
        }
        runtime = {
            "provider": "fixture",
            "model": "deterministic",
            "session_id": "fresh-advisory-checkpoint",
            "isolation_config_hash": "sha256:" + "b" * 64,
            "runner_hash": "sha256:" + "d" * 64,
            "experiment_plan_hash": "sha256:" + "e" * 64,
        }
        budget = {
            "tokens": None,
            "wall_time_seconds": None,
            "tool_calls": None,
            "cost_units": None,
        }
        advisory_tier = self.trial.checkpoint_evidence_tier("paired-profile")
        isolation_evidence = {
            "fresh_session": True,
            "forked_from_existing": False,
            "auto_memory_enabled": False,
            "vector_retrieval_enabled": False,
            "session_recall_enabled": False,
            "cross_session_cache_enabled": False,
            "provider_persistence": "unverified",
            "canary_leak_detected": False,
        }

        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            checkout = root / "agent-checkout"
            checkout.mkdir(mode=0o700)
            created = self.trial.prepare_trial(
                root, task, manifest, runtime, budget, sample_index=1
            )
            trial_dir = Path(created["trial_dir"])
            self.trial.write_jsonl_atomic(
                trial_dir / "events.jsonl",
                [
                    {
                        "event_contract": "trial-lifecycle-v1",
                        "type": "runner-complete",
                        "skills_invoked": [],
                    }
                ],
            )
            self.trial.write_jsonl_atomic(trial_dir / "access-audit.jsonl", [])
            self.trial.write_json_atomic(
                trial_dir / "outcome" / "result.json", {"passed": True}
            )

            self.trial.checkpoint_trial(
                trial_dir,
                status="completed",
                isolation_evidence=isolation_evidence,
                read_allow_roots=[checkout],
                write_allow_roots=[trial_dir / "outcome"],
                evidence_tier=advisory_tier,
                access_audit_complete=False,
                access_roots_enforced=False,
            )
            completed = self.trial.load_private_json(trial_dir / "trial.json")
            isolation = completed["completion_isolation"]
            self.assertEqual("advisory_limited", isolation["status"])
            self.assertEqual(advisory_tier, isolation["evidence_tier"])
            self.assertEqual(
                [
                    "access_root_enforcement",
                    "complete_access_audit",
                    "provider_side_persistence_proof",
                ],
                isolation["coverage_limitations"],
            )
            replay = self.trial.prepare_trial(
                root,
                task,
                manifest,
                runtime,
                budget,
                sample_index=1,
                expected_isolation_evidence=isolation_evidence,
                expected_read_allow_roots=[checkout],
                expected_write_allow_roots=[trial_dir / "outcome"],
            )
            self.assertEqual("complete", replay["mode"])

            tampered = json.loads(json.dumps(completed))
            tampered_isolation = tampered["completion_isolation"]
            tampered_isolation["evidence"]["fresh_session"] = None
            tampered_isolation["evidence_hash"] = self.trial.canonical_hash(
                tampered_isolation["evidence"]
            )
            tampered_isolation["coverage_limitations"].append(
                "memory_isolation_proof"
            )
            tampered_isolation["coverage_limitations"].sort()
            self.trial.write_json_atomic(trial_dir / "trial.json", tampered)
            with self.assertRaisesRegex(ValueError, "completion binding mismatch"):
                self.trial.prepare_trial(
                    root,
                    task,
                    manifest,
                    runtime,
                    budget,
                    sample_index=1,
                    expected_isolation_evidence=dict(
                        isolation_evidence,
                        fresh_session=None,
                    ),
                    expected_read_allow_roots=[checkout],
                    expected_write_allow_roots=[trial_dir / "outcome"],
                )
            self.trial.write_json_atomic(trial_dir / "trial.json", completed)
            self.trial.write_jsonl_atomic(
                trial_dir / "access-audit.jsonl",
                [
                    {
                        "actor": "tested-agent",
                        "operation": "read",
                        "path": str(checkout / "task.json"),
                    }
                ],
            )
            with self.assertRaisesRegex(ValueError, "completion binding mismatch"):
                self.trial.prepare_trial(
                    root,
                    task,
                    manifest,
                    runtime,
                    budget,
                    sample_index=1,
                    expected_isolation_evidence=isolation_evidence,
                    expected_read_allow_roots=[checkout],
                    expected_write_allow_roots=[trial_dir / "outcome"],
                )
            self.trial.write_jsonl_atomic(trial_dir / "access-audit.jsonl", [])

            breached = self.trial.prepare_trial(
                root, task, manifest, runtime, budget, sample_index=2
            )
            breached_dir = Path(breached["trial_dir"])
            self.trial.write_jsonl_atomic(
                breached_dir / "events.jsonl",
                [
                    {
                        "event_contract": "trial-lifecycle-v1",
                        "type": "runner-complete",
                        "skills_invoked": [],
                    }
                ],
            )
            self.trial.write_jsonl_atomic(
                breached_dir / "access-audit.jsonl",
                [
                    {
                        "actor": "tested-agent",
                        "operation": "read",
                        "path": str(root / "controller-secret.json"),
                    },
                ],
            )
            self.trial.write_json_atomic(
                breached_dir / "outcome" / "result.json", {"passed": True}
            )
            with self.assertRaisesRegex(ValueError, "isolation check failed"):
                self.trial.checkpoint_trial(
                    breached_dir,
                    status="completed",
                    isolation_evidence=isolation_evidence,
                    read_allow_roots=[checkout],
                    write_allow_roots=[breached_dir / "outcome"],
                    evidence_tier=advisory_tier,
                    access_audit_complete=False,
                    access_roots_enforced=False,
                )

            causal_manifest = self.trial.freeze_arm_manifest(
                arm_template("S0", "off", []), common_components(b"")
            )
            causal = self.trial.prepare_trial(
                root, task, causal_manifest, runtime, budget, sample_index=3
            )
            causal_dir = Path(causal["trial_dir"])
            self.trial.write_jsonl_atomic(
                causal_dir / "events.jsonl",
                [
                    {
                        "event_contract": "trial-lifecycle-v1",
                        "type": "runner-complete",
                        "skills_invoked": [],
                    }
                ],
            )
            self.trial.write_jsonl_atomic(causal_dir / "access-audit.jsonl", [])
            self.trial.write_json_atomic(
                causal_dir / "outcome" / "result.json", {"passed": True}
            )
            with self.assertRaisesRegex(ValueError, "does not match registry"):
                self.trial.checkpoint_trial(
                    causal_dir,
                    status="completed",
                    isolation_evidence=isolation_evidence,
                    read_allow_roots=[checkout],
                    write_allow_roots=[causal_dir / "outcome"],
                    evidence_tier=advisory_tier,
                    access_audit_complete=False,
                    access_roots_enforced=False,
                )

            omitted_tier = self.trial.prepare_trial(
                root, task, manifest, runtime, budget, sample_index=4
            )
            with self.assertRaisesRegex(ValueError, "does not match registry"):
                self.trial.checkpoint_trial(
                    Path(omitted_tier["trial_dir"]),
                    status="completed",
                )

            for sample_index, breach in (
                (5, {"auto_memory_enabled": True}),
                (6, {"provider_persistence": "enabled"}),
            ):
                with self.subTest(breach=breach):
                    memory_breached = self.trial.prepare_trial(
                        root,
                        task,
                        manifest,
                        runtime,
                        budget,
                        sample_index=sample_index,
                    )
                    memory_breached_dir = Path(memory_breached["trial_dir"])
                    self.trial.write_jsonl_atomic(
                        memory_breached_dir / "events.jsonl",
                        [
                            {
                                "event_contract": "trial-lifecycle-v1",
                                "type": "runner-complete",
                                "skills_invoked": [],
                            }
                        ],
                    )
                    self.trial.write_jsonl_atomic(
                        memory_breached_dir / "access-audit.jsonl", []
                    )
                    self.trial.write_json_atomic(
                        memory_breached_dir / "outcome" / "result.json",
                        {"passed": True},
                    )
                    with self.assertRaisesRegex(
                        ValueError, "isolation check failed"
                    ):
                        self.trial.checkpoint_trial(
                            memory_breached_dir,
                            status="completed",
                            isolation_evidence=dict(isolation_evidence, **breach),
                            read_allow_roots=[checkout],
                            write_allow_roots=[memory_breached_dir / "outcome"],
                            evidence_tier=advisory_tier,
                            access_audit_complete=False,
                            access_roots_enforced=False,
                        )

    def test_checkpoint_state_version_rejects_stale_concurrent_writer(self):
        manifest = self.trial.freeze_arm_manifest(
            arm_template("S0", "off", []), common_components(b"")
        )
        task = {
            "task_id": "checkpoint-race",
            "task_family": "review",
            "cohort": "known-regression",
            "prompt_ref": "fixture://checkpoint-race",
            "expected_owners": ["ccl-skills:testing-strategy"],
            "frozen_at_sha": "a" * 40,
            "corpus_version": "synthetic-v1",
        }
        runtime = {
            "provider": "fixture",
            "model": "deterministic",
            "session_id": "fresh-checkpoint-race",
            "isolation_config_hash": "sha256:" + "b" * 64,
            "runner_hash": "sha256:" + "d" * 64,
            "experiment_plan_hash": "sha256:" + "e" * 64,
        }
        budget = {
            "tokens": 1000,
            "wall_time_seconds": 60,
            "tool_calls": 8,
            "cost_units": 1,
        }
        zero_cursor = {
            "next_run_order": 1,
            "consumed_budget": {
                "tokens": 0,
                "wall_time_seconds": 0,
                "tool_calls": 0,
                "cost_units": 0,
            },
        }

        with tempfile.TemporaryDirectory() as directory:
            created = self.trial.prepare_trial(
                Path(directory), task, manifest, runtime, budget, sample_index=1
            )
            barrier = threading.Barrier(2)

            def transition(status):
                barrier.wait()
                try:
                    version = self.trial.checkpoint_trial(
                        Path(created["trial_dir"]),
                        status=status,
                        resume_cursor=zero_cursor,
                        expected_state_version=created["state_version"],
                    )
                    return ("ok", status, version)
                except ValueError as exc:
                    return ("error", status, str(exc))

            with ThreadPoolExecutor(max_workers=2) as pool:
                results = list(pool.map(transition, ("running", "failed")))
            self.assertEqual(1, sum(result[0] == "ok" for result in results))
            self.assertEqual(1, sum(result[0] == "error" for result in results))
            self.assertTrue(
                any(
                    result[0] == "error" and "state version mismatch" in result[2]
                    for result in results
                )
            )

            trial_dir = Path(created["trial_dir"])
            payload = self.trial.load_private_json(trial_dir / "trial.json")
            if payload["status"] == "running":
                next_version = self.trial.checkpoint_trial(
                    trial_dir,
                    status="failed",
                    resume_cursor=zero_cursor,
                    expected_state_version=payload["state_version"],
                )
                payload = self.trial.load_private_json(trial_dir / "trial.json")
                self.assertEqual(next_version, payload["state_version"])
            self.assertEqual("failed", payload["status"])
            with self.assertRaisesRegex(ValueError, "terminal trial cannot transition"):
                self.trial.checkpoint_trial(
                    trial_dir,
                    status="running",
                    resume_cursor=zero_cursor,
                    expected_state_version=payload["state_version"],
                )

    def test_prepare_trial_serializes_first_creation(self):
        manifest = self.trial.freeze_arm_manifest(
            arm_template("S0", "off", []), common_components(b"")
        )
        task = {
            "task_id": "prepare-race",
            "task_family": "review",
            "cohort": "known-regression",
            "prompt_ref": "fixture://prepare-race",
            "expected_owners": ["ccl-skills:testing-strategy"],
            "frozen_at_sha": "a" * 40,
            "corpus_version": "synthetic-v1",
        }
        budget = {
            "tokens": None,
            "wall_time_seconds": None,
            "tool_calls": None,
            "cost_units": None,
        }
        runtime = {
            "provider": "fixture",
            "model": "deterministic",
            "session_id": "session-a",
            "isolation_config_hash": "sha256:" + "b" * 64,
            "runner_hash": "sha256:" + "d" * 64,
            "experiment_plan_hash": "sha256:" + "e" * 64,
        }

        with tempfile.TemporaryDirectory() as directory:
            original_path_exists = self.trial._path_exists
            rendezvous = threading.Barrier(2)

            def synchronized_absence_check(path):
                exists = original_path_exists(path)
                if Path(path).name == "trial.json" and not exists:
                    try:
                        rendezvous.wait(timeout=0.25)
                    except threading.BrokenBarrierError:
                        pass
                return exists

            def prepare(session_id):
                candidate_runtime = dict(runtime, session_id=session_id)
                try:
                    result = self.trial.prepare_trial(
                        Path(directory),
                        task,
                        manifest,
                        candidate_runtime,
                        budget,
                        sample_index=1,
                    )
                    return ("ok", session_id, result["mode"])
                except ValueError as exc:
                    return ("error", session_id, str(exc))

            with mock.patch.object(
                self.trial, "_path_exists", side_effect=synchronized_absence_check
            ):
                with ThreadPoolExecutor(max_workers=2) as pool:
                    results = list(pool.map(prepare, ("session-a", "session-b")))

            self.assertEqual(1, sum(result[0] == "ok" for result in results))
            self.assertEqual(1, sum(result[0] == "error" for result in results))
            self.assertEqual(
                {"created"},
                {result[2] for result in results if result[0] == "ok"},
            )
            self.assertTrue(
                any(
                    result[0] == "error" and "fingerprint mismatch" in result[2]
                    for result in results
                )
            )

    def test_blinding_keeps_arm_and_manifest_metadata_out_of_judge_input(self):
        registered_manifests = {
            "S0": self.trial.freeze_arm_manifest(
                arm_template("S0", "off", []), common_components(b"")
            ),
            "S1": self.trial.freeze_arm_manifest(
                arm_template("S1", "oracle", ["ccl_layer"]),
                common_components(b"owner"),
            ),
            "S2": self.trial.freeze_arm_manifest(
                arm_template("S2", "full", ["ccl_layer"]),
                common_components(b"full"),
            ),
            "control-x": self.trial.freeze_arm_manifest(
                arm_template("control-x", "oracle", ["ccl_layer"]),
                common_components(b"control"),
            ),
        }
        plan_directory = tempfile.TemporaryDirectory()
        self.addCleanup(plan_directory.cleanup)
        registry_plan_path = Path(plan_directory.name) / "experiment-plan.json"
        registry_plan = self.trial.write_arm_registry_plan(
            registry_plan_path, registered_manifests
        )
        left = {
            "outcome_id": "outcome-left",
            "arm_id": "S0",
            "manifest_hash": registered_manifests["S0"]["manifest_hash"],
            "arm_registry_plan_hash": registry_plan["plan_hash"],
            "skills_invoked": [],
            "judge_payload": {"answer": "first answer", "tests": ["ok"]},
        }
        right = {
            "outcome_id": "outcome-right",
            "arm_id": "S1",
            "manifest_hash": registered_manifests["S1"]["manifest_hash"],
            "arm_registry_plan_hash": registry_plan["plan_hash"],
            "skills_invoked": ["ccl-skills:testing-strategy"],
            "judge_payload": {"answer": "second answer", "tests": ["ok"]},
        }

        def blind_pair(
            left_outcome,
            right_outcome,
            key=BLINDING_KEY,
            manifests=registered_manifests,
        ):
            return self.trial.blind_pair(
                left_outcome,
                right_outcome,
                blinding_key=key,
                registered_manifests=manifests,
                registry_plan_path=registry_plan_path,
            )

        def build_pair_mapping(
            left_outcome, right_outcome, manifests=registered_manifests
        ):
            return self.trial.build_pair_mapping(
                left_outcome,
                right_outcome,
                blinding_key=BLINDING_KEY,
                registered_manifests=manifests,
                registry_plan_path=registry_plan_path,
            )

        pair = blind_pair(left, right)
        repeated = blind_pair(left, right)
        self.assertEqual(pair, repeated)
        self.assertEqual(
            pair,
            blind_pair(right, left),
        )
        mapping = build_pair_mapping(left, right)
        self.assertEqual(
            mapping,
            build_pair_mapping(right, left),
        )
        subset = {key: registered_manifests[key] for key in ("S0", "S1")}
        with self.assertRaisesRegex(ValueError, "required treatments"):
            blind_pair(left, right, manifests=subset)
        mismatched_manifest = dict(left, manifest_hash="sha256:" + "f" * 64)
        with self.assertRaisesRegex(ValueError, "outcome manifest binding mismatch"):
            blind_pair(mismatched_manifest, right)
        rendered = json.dumps(pair, sort_keys=True)
        for forbidden in (
            "S0",
            "S1",
            "manifest_hash",
            "skills_invoked",
            "ccl-skills:",
        ):
            self.assertNotIn(forbidden, rendered)
        self.assertEqual({"A", "B"}, set(mapping["mapping"]))
        self.assertNotIn("outcome-left", rendered)
        self.assertNotIn("outcome-right", rendered)
        self.assertRegex(pair["pair_id"], r"^pair-[0-9a-f]{64}$")

        left["judge_payload"]["answer"] = "mutated after blinding"
        self.assertNotIn("mutated after blinding", json.dumps(pair, sort_keys=True))
        left["judge_payload"]["answer"] = "first answer"

        leaked = dict(
            right,
            judge_payload={"answer": "I loaded ccl-skills:testing-strategy"},
        )
        with self.assertRaisesRegex(ValueError, "judge metadata token leak"):
            blind_pair(left, leaked)

        camel_case_leak = dict(
            right, judge_payload={"answer": "clean", "manifestHash": "secret"}
        )
        with self.assertRaisesRegex(ValueError, "judge metadata token leak"):
            blind_pair(left, camel_case_leak)

        legitimate_token = dict(
            right, judge_payload={"answer": "The M1 processor passed its tests"}
        )
        blind_pair(left, legitimate_token)

        arm_text_leak = dict(right, judge_payload={"answer": "I am arm S1 speaking"})
        with self.assertRaisesRegex(ValueError, "judge arm id leak"):
            blind_pair(left, arm_text_leak)

        arm_key_leak = dict(
            right,
            judge_payload={"S1": {"answer": "identity hidden in a key"}},
        )
        with self.assertRaisesRegex(ValueError, "judge arm id leak"):
            blind_pair(left, arm_key_leak)

        skill_key_leak = dict(
            right,
            judge_payload={"ccl-skills:testing-strategy": "loaded"},
        )
        with self.assertRaisesRegex(ValueError, "judge metadata token leak"):
            blind_pair(left, skill_key_leak)

        benign_arm_text = dict(
            right,
            judge_payload={"answer": "The arm of the loop runs on an ARM CPU"},
        )
        blind_pair(left, benign_arm_text)

        arbitrary_arm = dict(
            right,
            arm_id="control-x",
            manifest_hash=registered_manifests["control-x"]["manifest_hash"],
            judge_payload={"answer": "result from control-x"},
        )
        with self.assertRaisesRegex(ValueError, "judge arm id leak"):
            blind_pair(left, arbitrary_arm)

        third_arm_leak = dict(
            right,
            judge_payload={"answer": "The hidden baseline was S2"},
        )
        with self.assertRaisesRegex(ValueError, "judge arm id leak"):
            blind_pair(left, third_arm_leak)

        hash_leak = dict(
            right,
            judge_payload={"answer": "artifact sha256:" + "a" * 64},
        )
        with self.assertRaisesRegex(ValueError, "judge metadata token leak"):
            blind_pair(left, hash_leak)

        left_in_a = set()
        for index in range(12):
            varied_left = dict(left, outcome_id=f"left-{index}")
            varied_right = dict(right, outcome_id=f"right-{index}")
            varied = build_pair_mapping(varied_left, varied_right)
            left_in_a.add(varied["mapping"]["A"] == f"left-{index}")
        self.assertEqual({False, True}, left_in_a)

        with self.assertRaisesRegex(ValueError, "at least 32 secret bytes"):
            blind_pair(left, right, key=b"too-short")

        with tempfile.TemporaryDirectory() as directory:
            controller_root = Path(directory) / "controller"
            key = self.trial.load_or_create_blinding_key(controller_root)
            self.assertEqual(32, len(key))
            self.assertEqual(
                key, self.trial.load_or_create_blinding_key(controller_root)
            )
            key_path = controller_root / "blinding.key"
            self.assertEqual(0o600, key_path.stat().st_mode & 0o777)
            self.assertNotIn(key.hex(), json.dumps(pair, sort_keys=True))

            key_path.write_bytes(b"short")
            key_path.chmod(0o600)
            with self.assertRaisesRegex(ValueError, "exactly 32 bytes"):
                self.trial.load_or_create_blinding_key(controller_root)

        with tempfile.TemporaryDirectory() as directory:
            controller_root = Path(directory) / "concurrent-controller"
            controller_root.mkdir(mode=0o700)
            barrier = threading.Barrier(8)
            counter_lock = threading.Lock()
            call_counter = 0

            def competing_key(length):
                nonlocal call_counter
                with counter_lock:
                    call_counter += 1
                    value = call_counter
                barrier.wait()
                return bytes([value]) * length

            with mock.patch.object(
                self.trial.secrets, "token_bytes", side_effect=competing_key
            ):
                with ThreadPoolExecutor(max_workers=8) as pool:
                    keys = list(
                        pool.map(
                            lambda _: self.trial.load_or_create_blinding_key(
                                controller_root
                            ),
                            range(8),
                        )
                    )
            self.assertEqual(1, len(set(keys)))
            self.assertEqual(
                keys[0], self.trial.load_or_create_blinding_key(controller_root)
            )
            self.assertEqual([], list(controller_root.glob(".blinding.key.*")))

        with tempfile.TemporaryDirectory() as directory:
            real_controller = Path(directory) / "real-controller"
            real_controller.mkdir(mode=0o700)
            controller_link = Path(directory) / "controller-link"
            controller_link.symlink_to(real_controller, target_is_directory=True)
            with self.assertRaisesRegex(ValueError, "must not be a symlink"):
                self.trial.load_or_create_blinding_key(controller_link)

    def test_blinding_uses_a_persisted_complete_registry_plan(self):
        registered_manifests = {
            "S0": self.trial.freeze_arm_manifest(
                arm_template("S0", "off", []), common_components(b"")
            ),
            "S1": self.trial.freeze_arm_manifest(
                arm_template("S1", "oracle", ["ccl_layer"]),
                common_components(b"owner"),
            ),
            "S2": self.trial.freeze_arm_manifest(
                arm_template("S2", "full", ["ccl_layer"]),
                common_components(b"full"),
            ),
        }
        with tempfile.TemporaryDirectory() as directory:
            plan_path = Path(directory) / "experiment-plan.json"
            plan = self.trial.write_arm_registry_plan(plan_path, registered_manifests)
            self.assertEqual(0o600, plan_path.stat().st_mode & 0o777)
            left = {
                "outcome_id": "outcome-left",
                "arm_id": "S0",
                "manifest_hash": registered_manifests["S0"]["manifest_hash"],
                "arm_registry_plan_hash": plan["plan_hash"],
                "judge_payload": {"answer": "first"},
            }
            right = {
                "outcome_id": "outcome-right",
                "arm_id": "S1",
                "manifest_hash": registered_manifests["S1"]["manifest_hash"],
                "arm_registry_plan_hash": plan["plan_hash"],
                "judge_payload": {"answer": "second"},
            }
            pair = self.trial.blind_pair(
                left,
                right,
                blinding_key=BLINDING_KEY,
                registered_manifests=registered_manifests,
                registry_plan_path=plan_path,
            )
            self.assertRegex(pair["pair_id"], r"^pair-[0-9a-f]{64}$")

            subset = {arm_id: registered_manifests[arm_id] for arm_id in ("S0", "S1")}
            subset_path = Path(directory) / "subset-plan.json"
            with self.assertRaisesRegex(ValueError, "required treatments"):
                self.trial.write_arm_registry_plan(subset_path, subset)
            self.assertFalse(subset_path.exists())

    def test_schedule_is_deterministic_interleaved_and_has_three_samples(self):
        tasks = [
            {"task_id": "t1", "task_family": "review"},
            {"task_id": "t2", "task_family": "diagnosis"},
        ]
        schedule = self.trial.build_schedule(
            tasks, ["S0", "S1", "S2"], samples=3, seed=9
        )
        self.assertEqual(
            schedule,
            self.trial.build_schedule(tasks, ["S0", "S1", "S2"], samples=3, seed=9),
        )
        counts = Counter((row["task_id"], row["arm_id"]) for row in schedule)
        self.assertEqual({3}, set(counts.values()))
        self.assertEqual(18, len(schedule))
        self.assertGreater(len({row["arm_id"] for row in schedule[:6]}), 1)
        with self.assertRaisesRegex(ValueError, "at least three samples"):
            self.trial.build_schedule(tasks, ["S0"], samples=True, seed=9)
        with self.assertRaisesRegex(ValueError, "seed must be an integer"):
            self.trial.build_schedule(tasks, ["S0"], samples=3, seed=True)

    def test_capability_matrix_blocks_an_empty_causal_core(self):
        review_evidence = capability_evidence()
        diagnosis_evidence = capability_evidence(mount_verified=False)
        ready_entries = [
            {
                "runner": "fixture",
                "provider": "fixture-provider",
                "task_family": "review",
                "evidence": review_evidence,
                "evidence_hash": capability_evidence_hash(
                    self.trial,
                    "fixture",
                    "fixture-provider",
                    "review",
                    review_evidence,
                ),
            },
            {
                "runner": "fixture",
                "provider": "fixture-provider",
                "task_family": "diagnosis",
                "evidence": diagnosis_evidence,
                "evidence_hash": capability_evidence_hash(
                    self.trial,
                    "fixture",
                    "fixture-provider",
                    "diagnosis",
                    diagnosis_evidence,
                ),
            },
        ]
        with tempfile.TemporaryDirectory() as directory:
            artifact_paths = []
            for index, entry in enumerate(ready_entries):
                artifact_path = Path(directory) / f"capability-{index}.json"
                self.trial.write_capability_probe_artifact(artifact_path, entry)
                artifact_paths.append(artifact_path)
            ready = self.trial.assess_capability_matrix_from_artifacts(artifact_paths)
        self.assertEqual("ready", ready["status"])
        self.assertEqual(["review"], ready["causal_task_families"])

        blocked_evidence = capability_evidence(mount_verified=False)
        blocked = self.trial.assess_capability_matrix(
            [
                {
                    "runner": "fixture",
                    "provider": "fixture-provider",
                    "task_family": "review",
                    "evidence": blocked_evidence,
                    "evidence_hash": capability_evidence_hash(
                        self.trial,
                        "fixture",
                        "fixture-provider",
                        "review",
                        blocked_evidence,
                    ),
                }
            ]
        )
        self.assertEqual("causal_core_unavailable", blocked["status"])
        self.assertEqual([], blocked["causal_task_families"])

        declaration_only = self.trial.assess_capability_matrix(
            [
                {
                    "runner": "fixture",
                    "provider": "none",
                    "task_family": "review",
                    "mount_boundary": True,
                    "access_audit": True,
                    "memory_isolation": True,
                    "evidence_hash": "sha256:" + "4" * 64,
                }
            ]
        )
        self.assertEqual("causal_core_unavailable", declaration_only["status"])
        self.assertIn("evidence_missing", declaration_only["entries"][0]["reasons"])

        nested_declarations = {
            "mount_boundary": True,
            "access_audit": True,
            "memory_isolation": True,
        }
        content_free = self.trial.assess_capability_matrix(
            [
                {
                    "runner": "fixture",
                    "provider": "fixture-provider",
                    "task_family": "review",
                    "evidence": nested_declarations,
                    "evidence_hash": capability_evidence_hash(
                        self.trial,
                        "fixture",
                        "fixture-provider",
                        "review",
                        nested_declarations,
                    ),
                }
            ]
        )
        self.assertEqual("causal_core_unavailable", content_free["status"])
        self.assertTrue(
            any(
                reason.startswith("capability_evidence_invalid:")
                for reason in content_free["entries"][0]["reasons"]
            )
        )

        tampered_hash = self.trial.assess_capability_matrix(
            [
                {
                    "runner": "fixture",
                    "provider": "fixture-provider",
                    "task_family": "review",
                    "evidence": review_evidence,
                    "evidence_hash": "sha256:" + "4" * 64,
                }
            ]
        )
        self.assertIn("evidence_hash_mismatch", tampered_hash["entries"][0]["reasons"])

    def test_capability_ready_requires_local_probe_artifacts(self):
        evidence = capability_evidence()
        entry = {
            "runner": "local-runner",
            "provider": "local-provider",
            "task_family": "review",
            "evidence": evidence,
            "evidence_hash": capability_evidence_hash(
                self.trial,
                "local-runner",
                "local-provider",
                "review",
                evidence,
            ),
        }
        in_memory = self.trial.assess_capability_matrix([entry])
        self.assertEqual("causal_core_unavailable", in_memory["status"])
        self.assertIn(
            "local_probe_artifact_required", in_memory["entries"][0]["reasons"]
        )

        with tempfile.TemporaryDirectory() as directory:
            artifact_path = Path(directory) / "review-capability.json"
            self.trial.write_capability_probe_artifact(artifact_path, entry)
            self.assertEqual(0o600, artifact_path.stat().st_mode & 0o777)
            artifact_backed = self.trial.assess_capability_matrix_from_artifacts(
                [artifact_path]
            )
            self.assertEqual("ready", artifact_backed["status"])
            self.assertEqual(["review"], artifact_backed["causal_task_families"])

    def test_committed_heldout_manifest_cannot_contain_prompt_or_truth(self):
        valid = {
            "task_id": "heldout-review-1",
            "task_family": "review",
            "cohort": "held-out-generalization",
            "skill_content_cutoff": "2026-07-19",
            "curator_independent": True,
            "prompt_ref": "corpus://heldout-v1/review-1",
            "execution_mode": "answer_only",
            "repo_snapshot": "sha256:" + "3" * 64,
            "expected_owners": ["ccl-skills:testing-strategy"],
            "should_invoke": True,
            "risk_tags": [],
            "graders": ["review-truth-v1"],
            "negative_control": False,
            "frozen_at_sha": "c" * 40,
            "corpus_version": "heldout-v1",
        }
        self.assertEqual([], self.trial.validate_task_record(valid, committed=True))
        leaked = dict(
            valid, prompt="secret held-out prompt", grader_truth={"defects": []}
        )
        errors = self.trial.validate_task_record(leaked, committed=True)
        self.assertIn("heldout_committed_field_forbidden:prompt", errors)
        self.assertIn("heldout_committed_field_forbidden:grader_truth", errors)
        fake_independence = dict(valid, curator_independent="yes")
        self.assertIn(
            "heldout_curator_not_independent",
            self.trial.validate_task_record(fake_independence, committed=True),
        )
        negative_control = dict(
            valid,
            expected_owners=[],
            should_invoke=False,
            negative_control=True,
        )
        self.assertEqual(
            [], self.trial.validate_task_record(negative_control, committed=True)
        )
        inconsistent_negative = dict(negative_control, should_invoke=True)
        inconsistent_errors = self.trial.validate_task_record(
            inconsistent_negative, committed=True
        )
        self.assertIn("negative_control_flags_inconsistent", inconsistent_errors)
        missing_negative_flag = dict(negative_control)
        missing_negative_flag.pop("negative_control")
        self.assertIn(
            "expected_owners_empty_for_positive_task",
            self.trial.validate_task_record(missing_negative_flag, committed=True),
        )
        positive_without_owner = dict(valid, expected_owners=[])
        self.assertIn(
            "expected_owners_empty_for_positive_task",
            self.trial.validate_task_record(positive_without_owner, committed=True),
        )

    def test_e10_gate_is_frozen_and_fails_on_off_residual(self):
        config = json.loads(PILOT_GATES_PATH.read_text(encoding="utf-8"))
        config.pop("evidence_tier", None)
        for required in (
            "thresholds",
            "budgets",
            "primary_outcomes",
            "minimum_effects",
        ):
            self.assertTrue(config[required])

        expected_tasks = {"t1": "review", "t2": "diagnosis"}
        expected_manifests = {
            "S0": self.trial.freeze_arm_manifest(
                arm_template("S0", "off", []), common_components(b"")
            ),
            "S1": self.trial.freeze_arm_manifest(
                arm_template("S1", "oracle", ["ccl_layer"]),
                common_components(b"frozen-owner-bundle"),
            ),
            "S2": self.trial.freeze_arm_manifest(
                arm_template("S2", "full", ["ccl_layer"]),
                common_components(b"frozen-full-bundle"),
            ),
        }
        expected_trials = expected_trial_rows(
            self.trial, expected_tasks, expected_manifests
        )
        records = [
            passing_record(row, expected_tasks[row["task_id"]])
            for row in expected_trials
        ]
        calibration, fixture_hash = raw_calibration(self.trial)
        self.assertEqual(config["reviewer_calibration_fixture_hash"], fixture_hash)
        bundle_directory = tempfile.TemporaryDirectory()
        self.addCleanup(bundle_directory.cleanup)
        bundle_counter = 0

        def evaluate_artifact_backed(
            candidate_records,
            candidate_calibration,
            manifests=expected_manifests,
            trials=expected_trials,
        ):
            nonlocal bundle_counter
            bundle_counter += 1
            bundle_root = Path(bundle_directory.name) / f"bundle-{bundle_counter}"
            calibration_result_path = write_sealed_calibration_result(
                self.trial,
                Path(bundle_directory.name) / f"calibration-{bundle_counter}",
                candidate_calibration,
                config,
            )
            self.trial.write_pilot_evidence_bundle(
                bundle_root,
                candidate_records,
                calibration_result_path,
                config,
                expected_tasks,
                manifests,
                trials,
            )
            return self.trial.evaluate_pilot_gate_from_artifacts(
                bundle_root,
                config,
                expected_tasks,
                manifests,
                trials,
            )

        identical_treatment_manifests = dict(expected_manifests)
        identical_treatment_manifests["S2"] = self.trial.freeze_arm_manifest(
            arm_template("S2", "full", ["ccl_layer"]), common_components(b"")
        )
        identical_treatment_trials = expected_trial_rows(
            self.trial, expected_tasks, identical_treatment_manifests
        )
        identical_treatment_records = [
            passing_record(row, expected_tasks[row["task_id"]])
            for row in identical_treatment_trials
        ]
        identical_treatment = self.trial.evaluate_pilot_gate(
            identical_treatment_records,
            calibration,
            config,
            expected_tasks,
            identical_treatment_manifests,
            identical_treatment_trials,
        )
        self.assertIn("manifest_allowlisted_diff", identical_treatment["failures"])
        self.assertEqual(
            {"S2": {"actual": [], "allowlisted": ["ccl_layer"]}},
            identical_treatment["metrics"]["manifest_plan_diff_errors"],
        )
        single_reviewer = json.loads(json.dumps(calibration))
        single_reviewer["reviewers"] = single_reviewer["reviewers"][:1]
        passed = evaluate_artifact_backed(records, single_reviewer)
        self.assertEqual("pass", passed["status"])
        self.assertEqual(
            "not_applicable_single_reviewer", passed["calibration"]["mutual"]
        )
        self.assertEqual(
            {"codex": "pass"},
            passed["calibration"]["reviewers"],
        )
        self.assertEqual(
            "optional_not_gate", passed["calibration"]["human_intervention"]
        )
        self.assertEqual(
            {
                "mode": "automated",
                "human_required": False,
                "next_action": "continue_automated_trial",
            },
            passed["decision"],
        )

        self.assertFalse(passed["decision"]["human_required"])

        synthetic_clean = self.trial.evaluate_pilot_gate(
            records,
            calibration,
            config,
            expected_tasks,
            expected_manifests,
            expected_trials,
            synthetic=True,
        )
        self.assertEqual("not_evaluated_synthetic", synthetic_clean["status"])
        self.assertTrue(
            {
                "contamination",
                "trial_file_isolation",
                "cross_trial_memory_isolation",
            }.issubset(synthetic_clean["not_evaluated_checks"])
        )

        weakened_config = json.loads(json.dumps(config))
        weakened_config["thresholds"]["runner_completion_rate_min"] = -1
        with self.assertRaisesRegex(ValueError, "rate threshold is invalid"):
            self.trial.evaluate_pilot_gate(
                records,
                calibration,
                weakened_config,
                expected_tasks,
                expected_manifests,
                expected_trials,
            )

        scalar_only_calibration = {
            "status": "evaluated",
            "known_answer_fixture_hash": fixture_hash,
            "reviewers": [
                {
                    "family": "codex",
                    "repeat_count": 3,
                    "self_consistency": 1.0,
                    "known_answer_accuracy": 1.0,
                }
            ],
        }
        invalid_calibration = self.trial.evaluate_pilot_gate(
            records,
            scalar_only_calibration,
            config,
            expected_tasks,
            expected_manifests,
            expected_trials,
        )
        self.assertIn("calibration_evidence_invalid", invalid_calibration["failures"])

        tampered_truth = json.loads(json.dumps(calibration))
        tampered_truth["known_answers"][0]["expected_verdict"] = "B win"
        tampered_result = self.trial.evaluate_pilot_gate(
            records,
            tampered_truth,
            config,
            expected_tasks,
            expected_manifests,
            expected_trials,
        )
        self.assertIn("calibration_evidence_invalid", tampered_result["failures"])

        self_calibration_failed = json.loads(json.dumps(single_reviewer))
        for run in self_calibration_failed["reviewers"][0]["runs"]:
            run[0]["verdict"] = "B win"
            run[1]["verdict"] = "A win"
        self_failed = self.trial.evaluate_pilot_gate(
            records,
            self_calibration_failed,
            config,
            expected_tasks,
            expected_manifests,
            expected_trials,
        )
        self.assertIn("reviewer_self_calibration", self_failed["failures"])

        mutual_failed = json.loads(json.dumps(calibration))
        for run in mutual_failed["reviewers"][0]["runs"]:
            run[0]["verdict"] = "B win"
        for run in mutual_failed["reviewers"][1]["runs"]:
            run[1]["verdict"] = "A win"
        mutual_result = self.trial.evaluate_pilot_gate(
            records,
            mutual_failed,
            config,
            expected_tasks,
            expected_manifests,
            expected_trials,
        )
        self.assertIn("reviewer_mutual_calibration", mutual_result["failures"])

        incomplete_runs = json.loads(json.dumps(single_reviewer))
        incomplete_runs["reviewers"][0]["runs"][0].pop()
        incomplete_result = self.trial.evaluate_pilot_gate(
            records,
            incomplete_runs,
            config,
            expected_tasks,
            expected_manifests,
            expected_trials,
        )
        self.assertIn("calibration_evidence_invalid", incomplete_result["failures"])

        synthetic_calibration = {"status": "not_evaluated_synthetic"}
        non_synthetic = self.trial.evaluate_pilot_gate(
            records,
            synthetic_calibration,
            config,
            expected_tasks,
            expected_manifests,
            expected_trials,
        )
        self.assertEqual("fail", non_synthetic["status"])
        self.assertIn(
            "synthetic_calibration_on_non_synthetic_run",
            non_synthetic["failures"],
        )

        unbound_records = json.loads(json.dumps(records))
        unbound_records[0].pop("manifest_hash")
        unbound = self.trial.evaluate_pilot_gate(
            unbound_records,
            calibration,
            config,
            expected_tasks,
            expected_manifests,
            expected_trials,
        )
        self.assertIn("trial_evidence_binding", unbound["failures"])

        forged_trials = json.loads(json.dumps(expected_trials))
        forged_records = json.loads(json.dumps(records))
        forged_trials[0]["runtime_hash"] = "sha256:" + "e" * 64
        forged_records[0]["runtime_hash"] = forged_trials[0]["runtime_hash"]
        with self.assertRaisesRegex(ValueError, "expected runtime hash mismatch"):
            self.trial.evaluate_pilot_gate(
                forged_records,
                calibration,
                config,
                expected_tasks,
                expected_manifests,
                forged_trials,
            )

        reordered_records = list(records)
        reordered_records[0], reordered_records[1] = (
            reordered_records[1],
            reordered_records[0],
        )
        reordered = self.trial.evaluate_pilot_gate(
            reordered_records,
            calibration,
            config,
            expected_tasks,
            expected_manifests,
            expected_trials,
        )
        self.assertIn("trial_execution_order", reordered["failures"])

        no_matched_call = [
            dict(
                record,
                matched_call_required=False,
                matched_call_compliant=(None if record["arm_id"] == "S1" else True),
            )
            for record in records
        ]
        missing_matched_call = self.trial.evaluate_pilot_gate(
            no_matched_call,
            calibration,
            config,
            expected_tasks,
            expected_manifests,
            expected_trials,
        )
        self.assertEqual("fail", missing_matched_call["status"])
        self.assertIn(
            "matched_call_compliance",
            missing_matched_call["not_evaluated_checks"],
        )
        self.assertIn(
            "required_evidence_not_evaluated",
            missing_matched_call["failures"],
        )

        insufficient = self.trial.evaluate_pilot_gate(
            records[1:],
            calibration,
            config,
            expected_tasks,
            expected_manifests,
            expected_trials,
        )
        self.assertEqual("fail", insufficient["status"])
        self.assertIn("insufficient_task_arm_samples", insufficient["failures"])

        records[0]["off_ccl_residual"] = True
        failed = self.trial.evaluate_pilot_gate(
            records,
            calibration,
            config,
            expected_tasks,
            expected_manifests,
            expected_trials,
        )
        self.assertEqual("fail", failed["status"])
        self.assertIn("off_ccl_layer_residual", failed["failures"])

        records[0]["off_ccl_residual"] = False
        polluted_components = common_components(b"")
        polluted_components["bootstrap"] = b"residual bootstrap"
        polluted_manifests = dict(expected_manifests)
        polluted_manifests["S0"] = self.trial.freeze_arm_manifest(
            arm_template("S0", "off", []), polluted_components
        )
        polluted_trials = expected_trial_rows(
            self.trial, expected_tasks, polluted_manifests
        )
        polluted_records = [
            passing_record(row, expected_tasks[row["task_id"]])
            for row in polluted_trials
        ]
        manifest_failed = self.trial.evaluate_pilot_gate(
            polluted_records,
            calibration,
            config,
            expected_tasks,
            polluted_manifests,
            polluted_trials,
        )
        self.assertIn("off_ccl_layer_residual", manifest_failed["failures"])
        self.assertEqual(
            {"S0": ["bootstrap"]},
            manifest_failed["metrics"]["off_manifest_residual_components"],
        )

        missing_task = [row for row in records if row["task_id"] != "t2"]
        missing = self.trial.evaluate_pilot_gate(
            missing_task,
            calibration,
            config,
            expected_tasks,
            expected_manifests,
            expected_trials,
        )
        self.assertIn("trial_plan_membership_mismatch", missing["failures"])
        self.assertIn("insufficient_task_arm_samples", missing["failures"])

        arm_rows = [row for row in records if row["arm_id"] == "S0"]
        arm_rows[0]["skill_events_verifiable"] = False
        unverifiable = self.trial.evaluate_pilot_gate(
            records,
            calibration,
            config,
            expected_tasks,
            expected_manifests,
            expected_trials,
        )
        self.assertIn("skill_event_unverifiable_rate", unverifiable["failures"])
        arm_rows[0]["skill_events_verifiable"] = True

        arm_rows[0]["contaminated"] = True
        contaminated = self.trial.evaluate_pilot_gate(
            records,
            calibration,
            config,
            expected_tasks,
            expected_manifests,
            expected_trials,
        )
        self.assertIn("arm_contamination_gap", contaminated["failures"])

        arm_rows[0]["contaminated"] = False
        duplicated = records[1:] + [dict(records[1])]
        duplicate_result = self.trial.evaluate_pilot_gate(
            duplicated,
            calibration,
            config,
            expected_tasks,
            expected_manifests,
            expected_trials,
        )
        self.assertIn("duplicate_trial_record", duplicate_result["failures"])
        self.assertIn("trial_plan_membership_mismatch", duplicate_result["failures"])

        wrong_family = [dict(record) for record in records]
        wrong_family[0]["task_family"] = "plan"
        family_result = self.trial.evaluate_pilot_gate(
            wrong_family,
            calibration,
            config,
            expected_tasks,
            expected_manifests,
            expected_trials,
        )
        self.assertIn("trial_task_family_mismatch", family_result["failures"])

    def test_non_synthetic_pilot_pass_requires_local_evidence_bundle(self):
        config = json.loads(PILOT_GATES_PATH.read_text(encoding="utf-8"))
        config.pop("evidence_tier", None)
        expected_tasks = {"t1": "review", "t2": "diagnosis"}
        expected_manifests = {
            "S0": self.trial.freeze_arm_manifest(
                arm_template("S0", "off", []), common_components(b"")
            ),
            "S1": self.trial.freeze_arm_manifest(
                arm_template("S1", "oracle", ["ccl_layer"]),
                common_components(b"frozen-owner-bundle"),
            ),
            "S2": self.trial.freeze_arm_manifest(
                arm_template("S2", "full", ["ccl_layer"]),
                common_components(b"frozen-full-bundle"),
            ),
        }
        expected_trials = expected_trial_rows(
            self.trial, expected_tasks, expected_manifests
        )
        records = [
            passing_record(row, expected_tasks[row["task_id"]])
            for row in expected_trials
        ]
        calibration, _ = raw_calibration(self.trial, families=("codex",))

        in_memory = self.trial.evaluate_pilot_gate(
            records,
            calibration,
            config,
            expected_tasks,
            expected_manifests,
            expected_trials,
        )
        self.assertEqual("fail", in_memory["status"])
        self.assertIn("local_evidence_bundle_required", in_memory["failures"])

        with tempfile.TemporaryDirectory() as directory:
            bundle_root = Path(directory) / "pilot-evidence"
            calibration_result_path = write_sealed_calibration_result(
                self.trial,
                Path(directory) / "calibration-source",
                calibration,
                config,
            )
            self.trial.write_pilot_evidence_bundle(
                bundle_root,
                records,
                calibration_result_path,
                config,
                expected_tasks,
                expected_manifests,
                expected_trials,
            )
            self.assertEqual(0o700, bundle_root.stat().st_mode & 0o777)
            for artifact_path in bundle_root.iterdir():
                self.assertEqual(0o600, artifact_path.stat().st_mode & 0o777)
            artifact_backed = self.trial.evaluate_pilot_gate_from_artifacts(
                bundle_root,
                config,
                expected_tasks,
                expected_manifests,
                expected_trials,
            )
            self.assertEqual("pass", artifact_backed["status"])
            self.assertEqual(
                "local_artifact_bundle", artifact_backed["evidence_source"]
            )

            records_path = bundle_root / "trial-records.jsonl"
            persisted_records = records_path.read_text(encoding="utf-8")
            records_path.write_text(persisted_records + "{}\n", encoding="utf-8")
            records_path.chmod(0o600)
            with self.assertRaisesRegex(ValueError, "records hash mismatch"):
                self.trial.evaluate_pilot_gate_from_artifacts(
                    bundle_root,
                    config,
                    expected_tasks,
                    expected_manifests,
                    expected_trials,
                )

            missing_root = Path(directory) / "missing-evidence"
            with self.assertRaisesRegex(ValueError, "does not exist"):
                self.trial.evaluate_pilot_gate_from_artifacts(
                    missing_root,
                    config,
                    expected_tasks,
                    expected_manifests,
                    expected_trials,
                )
            self.assertFalse(missing_root.exists())

    def test_committed_templates_keep_active_controls_pending_and_corpora_separate(
        self,
    ):
        expected_arms = {
            "subagent-off.json",
            "subagent-active-control.json",
            "subagent-oracle-owner.json",
            "subagent-full.json",
            "main-off.json",
            "main-active-control.json",
            "main-oracle-owners.json",
            "main-full.json",
        }
        self.assertEqual(expected_arms, {path.name for path in ARM_DIR.glob("*.json")})
        for path in ARM_DIR.glob("*.json"):
            arm = json.loads(path.read_text(encoding="utf-8"))
            self.trial._validate_arm_template(arm)
            if arm["treatment"] == "active_control":
                self.assertEqual(
                    {
                        "status": "pending",
                        "required_independent_candidates": 2,
                        "selection_blinded_before_outcomes": True,
                    },
                    arm["active_control_selection"],
                )
                missing_pending_contract = {
                    **arm,
                    "active_control_selection": {"status": "pending"},
                }
                with self.assertRaisesRegex(
                    ValueError,
                    "pending active-control selection field set is invalid",
                ):
                    self.trial._validate_arm_template(missing_pending_contract)
                invalid_pending_values = {
                    **arm,
                    "active_control_selection": {
                        "status": "pending",
                        "required_independent_candidates": 0,
                        "selection_blinded_before_outcomes": False,
                    },
                }
                with self.assertRaisesRegex(
                    ValueError,
                    "pending active-control selection values are invalid",
                ):
                    self.trial._validate_arm_template(invalid_pending_values)
            self.assertEqual(1, arm["schema_version"])
            if arm["treatment"] == "active_control":
                self.assertFalse(arm["runnable"])
                self.assertEqual("pending", arm["active_control_selection"]["status"])
                self.assertNotIn(
                    "selected_content_hash", arm["active_control_selection"]
                )
            else:
                self.assertEqual(
                    "not-applicable", arm["active_control_selection"]["status"]
                )

        heldout_schema = json.loads(HELDOUT_SCHEMA_PATH.read_text(encoding="utf-8"))
        self.assertEqual(False, heldout_schema["additionalProperties"])
        for forbidden in ("prompt", "grader_truth", "expected_output", "hidden_tests"):
            self.assertNotIn(forbidden, heldout_schema["properties"])

        rows = [
            json.loads(line)
            for line in TASKS_REGRESSION_PATH.read_text(encoding="utf-8").splitlines()
            if line.strip()
        ]
        self.assertGreaterEqual(len(rows), 2)
        for row in rows:
            self.assertEqual("known-regression", row["cohort"])
            self.assertEqual([], self.trial.validate_task_record(row, committed=True))

        for name in (
            "deterministic.schema.json",
            "pairwise-rubric-template.json",
            "human-adjudication.schema.json",
        ):
            payload = json.loads((GRADER_DIR / name).read_text(encoding="utf-8"))
            self.assertEqual(1, payload["schema_version"])

        rubric = json.loads(
            (GRADER_DIR / "pairwise-rubric-template.json").read_text(encoding="utf-8")
        )
        human_schema = json.loads(
            (GRADER_DIR / "human-adjudication.schema.json").read_text(encoding="utf-8")
        )
        deterministic_schema = json.loads(
            (GRADER_DIR / "deterministic.schema.json").read_text(encoding="utf-8")
        )
        self.assertIn("needs_adjudication", rubric["required_fields"])
        self.assertNotIn("needs_human", rubric["required_fields"])
        self.assertIn("confidence", human_schema["required"])
        self.assertIn("needs_adjudication", human_schema["required"])
        self.assertEqual(1, deterministic_schema["properties"]["checks"]["minItems"])
        deterministic_check = deterministic_schema["properties"]["checks"]["items"][
            "properties"
        ]
        self.assertEqual(1, deterministic_check["name"]["minLength"])
        self.assertEqual(1, deterministic_check["evidence"]["minLength"])
        self.assertTrue(deterministic_schema["allOf"])
        valid_grade = {
            "task_id": "t1",
            "trial_fingerprint": "sha256:" + "a" * 64,
            "checks": [
                {"name": "hidden-tests", "passed": True, "evidence": "all pass"}
            ],
            "passed": True,
        }
        self.assertEqual([], self.trial.validate_deterministic_grade(valid_grade))
        contradictory_grade = json.loads(json.dumps(valid_grade))
        contradictory_grade["checks"][0]["passed"] = False
        self.assertIn(
            "deterministic_grade_summary_mismatch",
            self.trial.validate_deterministic_grade(contradictory_grade),
        )
        consistent_failure = json.loads(json.dumps(contradictory_grade))
        consistent_failure["passed"] = False
        self.assertEqual(
            [], self.trial.validate_deterministic_grade(consistent_failure)
        )
        self.assertEqual(
            r"^pair-[0-9a-f]{64}$",
            human_schema["properties"]["pair_id"]["pattern"],
        )

    def test_cli_smoke_creates_advisory_artifacts_without_live_model_calls(self):
        with tempfile.TemporaryDirectory() as directory:
            output_root = Path(directory) / "private-output"
            result = subprocess.run(
                [
                    sys.executable,
                    str(RUN_PATH),
                    "smoke",
                    "--fixture",
                    str(SMOKE_FIXTURE_PATH),
                    "--out",
                    str(output_root),
                ],
                text=True,
                capture_output=True,
                check=False,
            )
            self.assertEqual(3, result.returncode, result.stderr)
            self.assertIn("execution_status=completed", result.stdout)
            self.assertIn("pilot_gate_status=not_evaluated_synthetic", result.stdout)
            report = json.loads(
                (output_root / "smoke-result.json").read_text(encoding="utf-8")
            )
            self.assertEqual(0o700, output_root.stat().st_mode & 0o777)
            self.assertEqual("completed", report["execution_status"])
            self.assertEqual("not_evaluated_synthetic", report["pilot_gate"]["status"])
            self.assertEqual(
                "causal", report["pilot_gate"]["evidence_tier"]["requested_tier"]
            )
            committed_gates = json.loads(
                PILOT_GATES_PATH.read_text(encoding="utf-8")
            )
            self.assertEqual(
                committed_gates["evidence_tier"],
                report["pilot_gate"]["evidence_tier_overridden_from"],
            )
            self.assertEqual(
                {
                    "off_runtime_residual_evidence",
                    "matched_call_compliance",
                    "skill_event_verifiability",
                    "blinding_leak",
                    "deterministic_grader_replay",
                    "contamination",
                    "budget_complete",
                    "trial_file_isolation",
                    "cross_trial_memory_isolation",
                    "provider_capability_matrix",
                },
                set(report["pilot_gate"]["not_evaluated_checks"]),
            )
            self.assertEqual(
                "not_evaluated_synthetic",
                report["pilot_gate"]["calibration"]["mutual"],
            )
            self.assertEqual(
                "optional_not_gate",
                report["pilot_gate"]["calibration"]["human_intervention"],
            )
            self.assertFalse(report["pilot_gate"]["decision"]["human_required"])
            self.assertEqual(
                "collect_live_evidence",
                report["pilot_gate"]["decision"]["next_action"],
            )
            self.assertEqual(
                "not_evaluated_synthetic", report["capability_matrix"]["status"]
            )
            self.assertEqual(
                "causal_core_unavailable",
                report["capability_matrix"]["synthetic_contract_status"],
            )
            self.assertEqual([], report["capability_matrix"]["causal_task_families"])
            self.assertEqual({"S0", "S1", "S2"}, set(report["manifest_errors"]))
            self.assertEqual([], report["manifest_errors"]["S0"])
            self.assertFalse(report["live_model_calls"])
            self.assertEqual("advisory", report["enforcement"])
            self.assertRegex(report["runner_hash"], r"^sha256:[0-9a-f]{64}$")
            for arm_id in ("S0", "S1", "S2"):
                self.assertTrue(
                    (
                        output_root
                        / "task-checkouts"
                        / "smoke-review"
                        / arm_id
                        / "sample-001"
                    ).is_dir()
                )

            resumed = subprocess.run(
                [
                    sys.executable,
                    str(RUN_PATH),
                    "smoke",
                    "--fixture",
                    str(SMOKE_FIXTURE_PATH),
                    "--out",
                    str(output_root),
                ],
                text=True,
                capture_output=True,
                check=False,
            )
            self.assertEqual(3, resumed.returncode, resumed.stderr)
            self.assertEqual(
                1, len(list((output_root / "history").glob("smoke-result-*.json")))
            )

            outcome_path = (
                output_root
                / "trials"
                / "smoke-review"
                / "S0"
                / "sample-001"
                / "outcome"
                / "result.json"
            )
            outcome = json.loads(outcome_path.read_text(encoding="utf-8"))
            outcome["fixture"] = False
            outcome_path.write_text(json.dumps(outcome), encoding="utf-8")
            tampered = subprocess.run(
                [
                    sys.executable,
                    str(RUN_PATH),
                    "smoke",
                    "--fixture",
                    str(SMOKE_FIXTURE_PATH),
                    "--out",
                    str(output_root),
                ],
                text=True,
                capture_output=True,
                check=False,
            )
            self.assertEqual(2, tampered.returncode, tampered.stderr)
            self.assertIn("completion binding mismatch", tampered.stderr)

        with tempfile.TemporaryDirectory() as directory:
            fixture = json.loads(SMOKE_FIXTURE_PATH.read_text(encoding="utf-8"))
            fixture["isolation_evidence"]["auto_memory_enabled"] = True
            fixture_path = Path(directory) / "contaminated.json"
            fixture_path.write_text(json.dumps(fixture), encoding="utf-8")
            output_root = Path(directory) / "contaminated-output"
            incomplete = subprocess.run(
                [
                    sys.executable,
                    str(RUN_PATH),
                    "smoke",
                    "--fixture",
                    str(fixture_path),
                    "--out",
                    str(output_root),
                ],
                text=True,
                capture_output=True,
                check=False,
            )
            self.assertEqual(1, incomplete.returncode, incomplete.stderr)
            incomplete_report = json.loads(
                (output_root / "smoke-result.json").read_text(encoding="utf-8")
            )
            self.assertEqual("incomplete", incomplete_report["execution_status"])
            self.assertIn(
                "runner_completion_rate",
                incomplete_report["pilot_gate"]["failures"],
            )

        with tempfile.TemporaryDirectory() as directory:
            fixture = json.loads(SMOKE_FIXTURE_PATH.read_text(encoding="utf-8"))
            fixture["arms"][0]["components"]["ccl_layer"] = "off-residual"
            fixture_path = Path(directory) / "off-residual.json"
            fixture_path.write_text(json.dumps(fixture), encoding="utf-8")
            output_root = Path(directory) / "off-residual-output"
            result = subprocess.run(
                [
                    sys.executable,
                    str(RUN_PATH),
                    "smoke",
                    "--fixture",
                    str(fixture_path),
                    "--out",
                    str(output_root),
                ],
                text=True,
                capture_output=True,
                check=False,
            )
            self.assertEqual(1, result.returncode, result.stderr)
            report = json.loads(
                (output_root / "smoke-result.json").read_text(encoding="utf-8")
            )
            self.assertIn(
                "off_ccl_layer_residual", report["pilot_gate"]["failures"]
            )

        with tempfile.TemporaryDirectory() as directory:
            fixture = json.loads(SMOKE_FIXTURE_PATH.read_text(encoding="utf-8"))
            fixture["arms"][0]["template"] = arm_template("S0", "off", [])
            fixture_path = Path(directory) / "self-declared-template.json"
            fixture_path.write_text(json.dumps(fixture), encoding="utf-8")
            result = subprocess.run(
                [
                    sys.executable,
                    str(RUN_PATH),
                    "smoke",
                    "--fixture",
                    str(fixture_path),
                    "--out",
                    str(Path(directory) / "self-declared-output"),
                ],
                text=True,
                capture_output=True,
                check=False,
            )
            self.assertEqual(2, result.returncode)
            self.assertIn(
                "smoke arm rows allow only template_ref and components",
                result.stderr,
            )

        with tempfile.TemporaryDirectory() as directory:
            fixture = json.loads(SMOKE_FIXTURE_PATH.read_text(encoding="utf-8"))
            fixture["synthetic_extra_access_events"] = [
                {
                    "actor": "tested-agent",
                    "operation": "read",
                    "path": str(Path(directory) / "outside-allowlist.txt"),
                }
            ]
            fixture_path = Path(directory) / "contaminated.json"
            fixture_path.write_text(json.dumps(fixture), encoding="utf-8")
            output_root = Path(directory) / "contaminated-output"
            result = subprocess.run(
                [
                    sys.executable,
                    str(RUN_PATH),
                    "smoke",
                    "--fixture",
                    str(fixture_path),
                    "--out",
                    str(output_root),
                ],
                text=True,
                capture_output=True,
                check=False,
            )
            self.assertEqual(1, result.returncode, result.stderr)
            report = json.loads(
                (output_root / "smoke-result.json").read_text(encoding="utf-8")
            )
            self.assertIn("trial_file_isolation", report["pilot_gate"]["failures"])
            self.assertIn("total_contamination_rate", report["pilot_gate"]["failures"])
            contaminated_trial = json.loads(
                (
                    output_root
                    / "trials"
                    / "smoke-review"
                    / "S0"
                    / "sample-001"
                    / "trial.json"
                ).read_text(encoding="utf-8")
            )
            self.assertEqual("contaminated", contaminated_trial["status"])
            self.assertFalse(contaminated_trial["completion_claim"])
            contaminated_dir = (
                output_root / "trials" / "smoke-review" / "S0" / "sample-001"
            )
            self.assertFalse((contaminated_dir / "outcome" / "result.json").exists())
            self.assertEqual(
                [],
                self.trial.load_private_jsonl(contaminated_dir / "events.jsonl"),
            )
            resumed = subprocess.run(
                [
                    sys.executable,
                    str(RUN_PATH),
                    "smoke",
                    "--fixture",
                    str(fixture_path),
                    "--out",
                    str(output_root),
                ],
                text=True,
                capture_output=True,
                check=False,
            )
            self.assertEqual(2, resumed.returncode, resumed.stderr)
            self.assertIn("trial is terminal: contaminated", resumed.stderr)
            self.assertFalse((output_root / "smoke-result.json").exists())
            archived_reports = list(
                (output_root / "history").glob("smoke-result-*.json")
            )
            self.assertEqual(1, len(archived_reports))
            archived_report = json.loads(
                archived_reports[0].read_text(encoding="utf-8")
            )
            self.assertIn(
                "trial_file_isolation", archived_report["pilot_gate"]["failures"]
            )

        with tempfile.TemporaryDirectory() as directory:
            fixture = json.loads(SMOKE_FIXTURE_PATH.read_text(encoding="utf-8"))
            output_root = Path(directory) / "controller-write-output"
            fixture["synthetic_extra_access_events"] = [
                {
                    "actor": "tested-agent",
                    "operation": "write",
                    "path": str(
                        output_root
                        / "trials"
                        / "smoke-review"
                        / "S0"
                        / "sample-001"
                        / "trial.json"
                    ),
                }
            ]
            fixture_path = Path(directory) / "controller-write.json"
            fixture_path.write_text(json.dumps(fixture), encoding="utf-8")
            result = subprocess.run(
                [
                    sys.executable,
                    str(RUN_PATH),
                    "smoke",
                    "--fixture",
                    str(fixture_path),
                    "--out",
                    str(output_root),
                ],
                text=True,
                capture_output=True,
                check=False,
            )
            self.assertEqual(1, result.returncode, result.stderr)
            report = json.loads(
                (output_root / "smoke-result.json").read_text(encoding="utf-8")
            )
            self.assertIn("trial_file_isolation", report["pilot_gate"]["failures"])

        with tempfile.TemporaryDirectory() as directory:
            fixture = json.loads(SMOKE_FIXTURE_PATH.read_text(encoding="utf-8"))
            fixture["isolation_evidence"]["session_recall_enabled"] = True
            fixture_path = Path(directory) / "memory-contaminated.json"
            fixture_path.write_text(json.dumps(fixture), encoding="utf-8")
            output_root = Path(directory) / "memory-contaminated-output"
            result = subprocess.run(
                [
                    sys.executable,
                    str(RUN_PATH),
                    "smoke",
                    "--fixture",
                    str(fixture_path),
                    "--out",
                    str(output_root),
                ],
                text=True,
                capture_output=True,
                check=False,
            )
            self.assertEqual(1, result.returncode, result.stderr)
            report = json.loads(
                (output_root / "smoke-result.json").read_text(encoding="utf-8")
            )
            self.assertIn(
                "cross_trial_memory_isolation", report["pilot_gate"]["failures"]
            )
            self.assertIn("total_contamination_rate", report["pilot_gate"]["failures"])

        with tempfile.TemporaryDirectory() as directory:
            real_output = Path(directory) / "real-output"
            real_output.mkdir(mode=0o700)
            output_link = Path(directory) / "output-link"
            output_link.symlink_to(real_output, target_is_directory=True)
            result = subprocess.run(
                [
                    sys.executable,
                    str(RUN_PATH),
                    "smoke",
                    "--fixture",
                    str(SMOKE_FIXTURE_PATH),
                    "--out",
                    str(output_link),
                ],
                text=True,
                capture_output=True,
                check=False,
            )
            self.assertEqual(2, result.returncode)
            self.assertIn("output root must not be a symlink", result.stderr)

        with tempfile.TemporaryDirectory() as directory:
            output_root = Path(directory) / "private-output"
            output_root.mkdir(mode=0o700)
            external = Path(directory) / "external.json"
            external.write_text("preserve-me", encoding="utf-8")
            (output_root / "smoke-result.json").symlink_to(external)
            result = subprocess.run(
                [
                    sys.executable,
                    str(RUN_PATH),
                    "smoke",
                    "--fixture",
                    str(SMOKE_FIXTURE_PATH),
                    "--out",
                    str(output_root),
                ],
                text=True,
                capture_output=True,
                check=False,
            )
            self.assertEqual(2, result.returncode)
            self.assertIn("must not be a symlink", result.stderr)
            self.assertEqual("preserve-me", external.read_text(encoding="utf-8"))

        with tempfile.TemporaryDirectory(dir=TRIAL_DIR) as directory:
            result = subprocess.run(
                [
                    sys.executable,
                    str(RUN_PATH),
                    "smoke",
                    "--fixture",
                    str(SMOKE_FIXTURE_PATH),
                    "--out",
                    directory,
                ],
                text=True,
                capture_output=True,
                check=False,
            )
            self.assertEqual(2, result.returncode)
            self.assertIn(
                "output root must stay outside the source checkout", result.stderr
            )
            self.assertFalse((Path(directory) / "smoke-result.json").exists())

        checkout_ancestor = EVAL_DIR.parent.parent
        run_module = load_run_module()
        with self.assertRaisesRegex(
            ValueError, "output root must not contain the source checkout"
        ):
            run_module.validated_output_root(checkout_ancestor)

    def _write_fake_codex(self, directory, *, behavior="no-leak"):
        fake_bin = Path(directory) / "bin"
        fake_bin.mkdir(exist_ok=True)
        fake_codex = fake_bin / "codex"
        script = """#!/usr/bin/env python3
import json
import os
import re
import signal
import sys
import time
from pathlib import Path

behavior = "__FAKE_BEHAVIOR__"
test_root = Path(__file__).resolve().parent.parent
if sys.argv[1:] == ["--version"]:
    print("codex-cli test-1.0")
    raise SystemExit(0)
if not sys.argv[1:] or sys.argv[1] != "exec":
    raise SystemExit(64)
if behavior == "nonzero":
    print("provider failed", file=sys.stderr)
    raise SystemExit(7)
if behavior == "unsupported":
    print("error: unexpected argument '--ignore-user-config'", file=sys.stderr)
    raise SystemExit(2)
if behavior == "usage-limit":
    print(json.dumps({
        "type": "error",
        "message": "You've hit your usage limit. Purchase more credits.",
    }))
    print(json.dumps({
        "type": "turn.failed",
        "error": {"message": "You've hit your usage limit."},
    }))
    raise SystemExit(1)
if behavior == "timeout":
    time.sleep(5)
if behavior == "delay":
    time.sleep(0.4)
if behavior == "event-flood":
    sys.stdout.write("x" * 70000)
    sys.stdout.flush()
    time.sleep(5)
    raise SystemExit(0)

prompt = sys.stdin.read()
log_path = test_root / "fake-codex.jsonl"
with log_path.open("a", encoding="utf-8") as stream:
    if behavior in {"signal-wait", "signal-hard-wait"}:
        time.sleep(0.1)
    stream.write(json.dumps({
        "argv": sys.argv[1:],
        "prompt": prompt,
        "env_keys": sorted(os.environ),
        "tmpdir_is_cwd": Path(os.environ["TMPDIR"]).resolve() == Path.cwd().resolve(),
        "cwd": os.getcwd(),
        "pid": os.getpid(),
        "blocked_signals": sorted(
            int(signum)
            for signum in signal.pthread_sigmask(signal.SIG_BLOCK, [])
        ),
    }) + "\\n")
if behavior == "signal-hard-wait":
    signal.signal(signal.SIGTERM, signal.SIG_IGN)
    signal.signal(signal.SIGHUP, signal.SIG_IGN)
if behavior in {"signal-wait", "signal-hard-wait"}:
    time.sleep(30)
state_path = test_root / "fake-codex-state"
if "REVIEWER CALIBRATION" in prompt:
    request = json.loads(prompt.split("CALIBRATION_INPUT=", 1)[1])
    verdicts = {
        "k1": "A win",
        "k2": "B win",
        "k3": "tie",
        "k4": "A win",
        "k5": "B win",
    }
    judgments = [
        {"case_id": row["case_id"], "verdict": verdicts[row["case_id"]]}
        for row in request["cases"]
    ]
    if behavior == "calibration-missing":
        judgments.pop()
    elif behavior == "calibration-invalid":
        judgments[0]["verdict"] = "left"
    elif behavior == "calibration-wrong":
        for judgment in judgments:
            judgment["verdict"] = "tie"
    payload = {
        "protocol_version": 1,
        "judgments": judgments,
    }
elif "SEED SESSION" in prompt:
    canary = re.search(r"CANARY=([a-f0-9]{64})", prompt).group(1)
    state_path.write_text(canary, encoding="utf-8")
    payload = {
        "protocol_version": 1,
        "phase": "seed",
        "canary_received": canary,
    }
else:
    prior = None
    if behavior == "leak":
        prior = state_path.read_text(encoding="utf-8")
    elif behavior == "foreign-leak":
        prior = "f" * 64
    elif behavior == "near-miss-leak":
        prior = "remembered:" + state_path.read_text(encoding="utf-8").upper()
    elif behavior == "bad-shape":
        prior = []
    payload = {
        "protocol_version": 1,
        "phase": "recall",
        "prior_canary": prior,
    }
if behavior == "malformed":
    output_text = "not-json"
elif behavior == "oversized":
    output_text = "x" * 20000
else:
    output_text = json.dumps(payload)
print(json.dumps({"type": "thread.started", "thread_id": "test-thread"}))
print(json.dumps({"type": "turn.started"}))
item_type = (
    "command_execution"
    if behavior == "tool"
    else "agent_message"
)
print(json.dumps({
    "type": "item.completed",
    "item": {"type": item_type, "text": output_text},
}))
print(json.dumps({"type": "turn.completed"}))
"""
        fake_codex.write_text(
            script.replace("__FAKE_BEHAVIOR__", behavior), encoding="utf-8"
        )
        fake_codex.chmod(0o700)
        return fake_bin

    def _write_fake_claude(self, directory, *, behavior="pass"):
        test_root = Path(directory)
        fake_bin = test_root / "claude-bin"
        fake_bin.mkdir(exist_ok=True)
        fake_claude = fake_bin / "claude"
        script = """#!/usr/bin/env python3
import json
import os
import sys
from pathlib import Path

behavior = "__FAKE_BEHAVIOR__"
test_root = Path(__file__).resolve().parent.parent
args = sys.argv[1:]
if args == ["--version"]:
    print("claude-code test-1.0")
    raise SystemExit(0)
if "--help" in args:
    flags = [
        "--print", "--tools", "--strict-mcp-config", "--mcp-config",
        "--setting-sources", "--safe-mode", "--disable-slash-commands",
        "--no-session-persistence", "--effort", "--output-format",
        "--verbose", "--json-schema", "--model",
    ]
    if behavior == "missing-session-flag":
        flags.remove("--no-session-persistence")
    print(" ".join(flags))
    raise SystemExit(0)

prompt = sys.stdin.read()
with (test_root / "fake-claude.jsonl").open("a", encoding="utf-8") as stream:
    stream.write(json.dumps({
        "argv": args,
        "prompt": prompt,
        "cwd": os.getcwd(),
        "env_keys": sorted(os.environ),
        "tmpdir_is_cwd": Path(os.environ["TMPDIR"]).resolve() == Path.cwd().resolve(),
    }) + "\\n")
if behavior == "quota":
    print(json.dumps({
        "type": "result",
        "subtype": "error",
        "is_error": True,
        "api_error_status": 429,
        "result": "quota exceeded",
    }))
    raise SystemExit(1)

request = json.loads(prompt.split("CALIBRATION_INPUT=", 1)[1])
verdicts = {
    "k1": "A win",
    "k2": "B win",
    "k3": "tie",
    "k4": "A win",
    "k5": "B win",
}
judgments = [
    {"case_id": row["case_id"], "verdict": verdicts[row["case_id"]]}
    for row in request["cases"]
]
if behavior == "wrong":
    for judgment in judgments:
        judgment["verdict"] = "tie"
payload = {"protocol_version": 1, "judgments": judgments}
model = args[args.index("--model") + 1]
if behavior == "model-mismatch":
    model = "claude-other-exact"
elif behavior == "model-shape":
    model = []
tools = ["StructuredOutput"]
if behavior == "toolful":
    tools.append("Bash")
print(json.dumps({
    "type": "system",
    "subtype": "init",
    "permissionMode": "default",
    "model": model,
    "tools": tools,
    "mcp_servers": [],
    "slash_commands": [],
    "skills": [],
    "plugins": [],
}))
print(json.dumps({
    "type": "result",
    "subtype": "success",
    "is_error": False,
    "terminal_reason": "completed",
    "permission_denials": [],
    "structured_output": payload,
}))
"""
        fake_claude.write_text(
            script.replace("__FAKE_BEHAVIOR__", behavior), encoding="utf-8"
        )
        fake_claude.chmod(0o700)
        return fake_bin

    def _write_fake_opencode(self, directory, *, behavior="pass"):
        test_root = Path(directory)
        fake_bin = test_root / "opencode-bin"
        fake_bin.mkdir(exist_ok=True)
        fake_opencode = fake_bin / "opencode"
        script = '''#!/usr/bin/env python3
import json
import os
import sys
from pathlib import Path

behavior = "__FAKE_BEHAVIOR__"
test_root = Path(__file__).resolve().parent.parent
args = sys.argv[1:]
if args == ["--version"]:
    print("1.18.0-test")
    raise SystemExit(0)

xdg_data = Path(os.environ["XDG_DATA_HOME"])
xdg_state = Path(os.environ["XDG_STATE_HOME"])
auth_path = xdg_data / "opencode" / "auth.json"
agent_path = Path.cwd() / ".opencode" / "agent" / "reviewer-calibration.md"
record = {
    "argv": args,
    "cwd": os.getcwd(),
    "xdg_data_home": str(xdg_data),
    "xdg_state_home": str(xdg_state),
    "auth_is_link": auth_path.is_symlink(),
    "auth_target": os.readlink(auth_path) if auth_path.is_symlink() else None,
    "env_keys": sorted(os.environ),
    "agent_text": agent_path.read_text(encoding="utf-8") if agent_path.exists() else None,
}
with (test_root / "fake-opencode.jsonl").open("a", encoding="utf-8") as stream:
    stream.write(json.dumps(record) + "\\n")

if args and args[0] == "run":
    if behavior == "quota":
        print("429 quota exceeded", file=sys.stderr)
        raise SystemExit(1)
    prompt = args[-1]
    requested_provider, requested_model = args[args.index("--model") + 1].split(
        "/", 1
    )
    provider_id = requested_provider
    model_id = requested_model
    if behavior == "model-mismatch":
        model_id = "deepseek-other"
    request = json.loads(prompt.split("CALIBRATION_INPUT=", 1)[1])
    verdicts = {
        "k1": "A win",
        "k2": "B win",
        "k3": "tie",
        "k4": "A win",
        "k5": "B win",
    }
    judgments = [
        {"case_id": row["case_id"], "verdict": verdicts[row["case_id"]]}
        for row in request["cases"]
    ]
    if behavior == "wrong":
        for judgment in judgments:
            judgment["verdict"] = "tie"
    payload = {"protocol_version": 1, "judgments": judgments}
    response_text = json.dumps(payload)
    if behavior == "invalid-json":
        response_text = "not-json"
    session_id = "ses-" + xdg_data.parent.name
    assistant_messages = []
    if behavior == "model-switch":
        assistant_messages.append({
            "info": {
                "role": "assistant",
                "providerID": provider_id,
                "modelID": "deepseek-other",
                "sessionID": session_id,
                "agent": "reviewer-calibration",
            },
            "parts": [
                {"type": "text", "text": "intermediate", "sessionID": session_id}
            ],
        })
    parts = [
        {"type": "text", "text": response_text, "sessionID": session_id},
        {"type": "step-finish", "reason": "stop", "sessionID": session_id},
    ]
    if behavior == "tool-export":
        parts.insert(0, {"type": "tool", "tool": "bash"})
    if behavior == "non-stop":
        parts[-1]["reason"] = "tool-calls"
    assistant_messages.append({
        "info": {
            "role": "assistant",
            "providerID": provider_id,
            "modelID": model_id,
            "sessionID": session_id,
            "agent": "reviewer-calibration",
        },
        "parts": parts,
    })
    export_payload = {
        "info": {
            "id": session_id,
            "agent": "reviewer-calibration",
            "model": {"providerID": provider_id, "id": model_id},
        },
        "messages": assistant_messages,
    }
    if behavior == "agent-mismatch":
        export_payload["info"]["agent"] = "other-agent"
    if behavior == "message-session-mismatch":
        export_payload["messages"][-1]["info"]["sessionID"] = "ses-other"
    if behavior == "export-mismatch":
        export_payload["info"]["id"] = "ses-other"
    export_path = xdg_data / "opencode" / "test-export.json"
    export_path.write_text(json.dumps(export_payload), encoding="utf-8")
    print(json.dumps({
        "type": "step_start",
        "sessionID": session_id,
        "part": {"type": "step-start"},
    }))
    if behavior == "tool-event":
        print(json.dumps({
            "type": "tool",
            "sessionID": session_id,
            "part": {"type": "tool", "tool": "bash"},
        }))
    if behavior == "multiple-sessions":
        print(json.dumps({"type": "step_start", "sessionID": "ses-other"}))
    raise SystemExit(0)

if args and args[0] == "export":
    export_path = xdg_data / "opencode" / "test-export.json"
    print(export_path.read_text(encoding="utf-8"))
    raise SystemExit(0)

print("unsupported fake opencode invocation", file=sys.stderr)
raise SystemExit(2)
'''
        fake_opencode.write_text(
            script.replace("__FAKE_BEHAVIOR__", behavior), encoding="utf-8"
        )
        fake_opencode.chmod(0o700)
        return fake_bin

    def _write_fake_kimi(self, directory, *, behavior="pass"):
        test_root = Path(directory)
        fake_bin = test_root / "kimi-bin"
        fake_bin.mkdir(exist_ok=True)
        fake_kimi = fake_bin / "kimi"
        script = '''#!/usr/bin/env python3
import json
import os
import sys
from pathlib import Path

behavior = "__FAKE_BEHAVIOR__"
test_root = Path(__file__).resolve().parent.parent
args = sys.argv[1:]
if args == ["--version"]:
    print("0.27.0-test")
    raise SystemExit(0)

kimi_home = Path(os.environ["KIMI_CODE_HOME"])
config_text = (kimi_home / "config.toml").read_text(encoding="utf-8")
credentials = kimi_home / "credentials"
oauth = kimi_home / "oauth"
device_id = kimi_home / "device_id"
record = {
    "argv": args,
    "cwd": os.getcwd(),
    "kimi_code_home": str(kimi_home),
    "config_text": config_text,
    "credentials_is_link": credentials.is_symlink(),
    "oauth_is_link": oauth.is_symlink(),
    "device_id_is_link": device_id.is_symlink(),
    "env_keys": sorted(os.environ),
}
with (test_root / "fake-kimi.jsonl").open("a", encoding="utf-8") as stream:
    stream.write(json.dumps(record) + "\\n")

if behavior == "quota":
    print("429 quota exceeded", file=sys.stderr)
    raise SystemExit(1)

prompt = args[args.index("--prompt") + 1]
request = json.loads(prompt.split("CALIBRATION_INPUT=", 1)[1])
verdicts = {
    "k1": "A win",
    "k2": "B win",
    "k3": "tie",
    "k4": "A win",
    "k5": "B win",
}
judgments = [
    {"case_id": row["case_id"], "verdict": verdicts[row["case_id"]]}
    for row in request["cases"]
]
if behavior == "wrong":
    for judgment in judgments:
        judgment["verdict"] = "tie"
content = json.dumps({"protocol_version": 1, "judgments": judgments})
if behavior == "pass":
    content = "```json\\n" + content + "\\n```"
if behavior == "invalid-json":
    content = "not-json"
if behavior == "fenced-extra-text":
    content = "result:\\n```json\\n" + content + "\\n```"
session_id = "kimi-" + kimi_home.parent.name
if behavior == "tool":
    print(json.dumps({
        "role": "assistant",
        "content": "",
        "tool_calls": [{
            "type": "function",
            "id": "tool-1",
            "function": {"name": "Shell", "arguments": "{}"},
        }],
    }))
elif behavior == "tool-result":
    print(json.dumps({"role": "tool", "tool_call_id": "tool-1", "content": "x"}))
elif behavior == "unknown-event":
    print(json.dumps({"role": "user", "content": "unexpected"}))
else:
    if behavior == "multiple-assistant":
        print(json.dumps({"role": "assistant", "content": "intermediate"}))
    print(json.dumps({"role": "assistant", "content": content, "tool_calls": []}))

if behavior != "no-resume":
    print(json.dumps({
        "role": "meta",
        "type": "session.resume_hint",
        "session_id": session_id,
        "command": "kimi -S " + session_id,
        "content": "To resume this session",
    }))
if behavior == "multiple-sessions":
    print(json.dumps({
        "role": "meta",
        "type": "session.resume_hint",
        "session_id": "kimi-other",
        "command": "kimi -S kimi-other",
        "content": "To resume this session",
    }))
'''
        fake_kimi.write_text(
            script.replace("__FAKE_BEHAVIOR__", behavior), encoding="utf-8"
        )
        fake_kimi.chmod(0o700)
        return fake_bin

    def _run_provider_probe(
        self, directory, *, behavior="no-leak", timeout_seconds=5, output_root=None
    ):
        fake_bin = self._write_fake_codex(directory, behavior=behavior)
        output_root = output_root or Path(directory) / "provider-output"
        log_path = Path(directory) / "fake-codex.jsonl"
        environment = os.environ.copy()
        environment.update(
            {
                "PATH": str(fake_bin) + os.pathsep + environment.get("PATH", ""),
                "CODEX_HOME": str(Path(directory) / "ambient-codex-home"),
                "OPENAI_BASE_URL": "https://ambient.invalid",
                "FAKE_SHOULD_NOT_LEAK": "1",
            }
        )
        result = subprocess.run(
            [
                sys.executable,
                str(RUN_PATH),
                "provider-probe",
                "--provider",
                "codex",
                "--codex-path",
                str(fake_bin / "codex"),
                "--model",
                "gpt-test-exact",
                "--task-family",
                "plan",
                "--out",
                str(output_root),
                "--timeout-seconds",
                str(timeout_seconds),
            ],
            text=True,
            capture_output=True,
            check=False,
            env=environment,
        )
        return result, output_root, log_path

    def _run_reviewer_calibration(
        self, directory, *, behavior="no-leak", repeats=2, output_root=None
    ):
        fake_bin = self._write_fake_codex(directory, behavior=behavior)
        output_root = output_root or Path(directory) / "reviewer-calibration-output"
        log_path = Path(directory) / "fake-codex.jsonl"
        result = subprocess.run(
            [
                sys.executable,
                str(RUN_PATH),
                "reviewer-calibration",
                "--provider",
                "codex",
                "--codex-path",
                str(fake_bin / "codex"),
                "--model",
                "gpt-test-exact",
                "--reviewer-family",
                "codex-test",
                "--repeats",
                str(repeats),
                "--out",
                str(output_root),
                "--timeout-seconds",
                "5",
            ],
            text=True,
            capture_output=True,
            check=False,
        )
        return result, output_root, log_path

    def _run_claude_reviewer_calibration(
        self, directory, *, behavior="pass", repeats=2, output_root=None
    ):
        fake_bin = self._write_fake_claude(directory, behavior=behavior)
        output_root = output_root or Path(directory) / "claude-calibration-output"
        log_path = Path(directory) / "fake-claude.jsonl"
        environment = os.environ.copy()
        environment.update(
            {
                "USER": "calibration-test-user",
                "LOGNAME": "calibration-test-user",
                "OPENAI_API_KEY": "must-not-cross-provider-boundary",
                "FAKE_SHOULD_NOT_LEAK": "1",
            }
        )
        result = subprocess.run(
            [
                sys.executable,
                str(RUN_PATH),
                "reviewer-calibration",
                "--provider",
                "claude",
                "--claude-path",
                str(fake_bin / "claude"),
                "--model",
                "claude-test-exact",
                "--reviewer-family",
                "claude",
                "--repeats",
                str(repeats),
                "--out",
                str(output_root),
                "--timeout-seconds",
                "5",
            ],
            text=True,
            capture_output=True,
            check=False,
            env=environment,
        )
        return result, output_root, log_path

    def _run_opencode_reviewer_calibration(
        self, directory, *, behavior="pass", repeats=2, output_root=None
    ):
        root = Path(directory)
        fake_bin = self._write_fake_opencode(directory, behavior=behavior)
        output_root = output_root or root / "opencode-calibration-output"
        log_path = root / "fake-opencode.jsonl"
        ambient_data = root / "ambient-xdg-data"
        auth_root = ambient_data / "opencode"
        auth_root.mkdir(parents=True, exist_ok=True)
        (auth_root / "auth.json").write_text(
            '{"deepseek":{"type":"oauth","refresh":"secret"}}',
            encoding="utf-8",
        )
        environment = os.environ.copy()
        environment.update(
            {
                "XDG_DATA_HOME": str(ambient_data),
                "OPENAI_API_KEY": "must-not-cross-provider-boundary",
                "FAKE_SHOULD_NOT_LEAK": "1",
            }
        )
        result = subprocess.run(
            [
                sys.executable,
                str(RUN_PATH),
                "reviewer-calibration",
                "--provider",
                "opencode",
                "--opencode-path",
                str(fake_bin / "opencode"),
                "--model",
                "deepseek/deepseek-v4-pro",
                "--reviewer-family",
                "deepseek",
                "--repeats",
                str(repeats),
                "--out",
                str(output_root),
                "--timeout-seconds",
                "5",
            ],
            text=True,
            capture_output=True,
            check=False,
            env=environment,
        )
        return result, output_root, log_path

    def _run_kimi_reviewer_calibration(
        self,
        directory,
        *,
        behavior="pass",
        repeats=2,
        model="kimi-code/kimi-for-coding",
        output_root=None,
    ):
        root = Path(directory)
        fake_bin = self._write_fake_kimi(directory, behavior=behavior)
        output_root = output_root or root / "kimi-calibration-output"
        log_path = root / "fake-kimi.jsonl"
        source_home = root / "ambient-kimi-home"
        (source_home / "credentials").mkdir(parents=True)
        (source_home / "oauth").mkdir()
        (source_home / "credentials" / "kimi-code.json").write_text(
            '{"token":"secret"}', encoding="utf-8"
        )
        (source_home / "oauth" / "kimi-code").write_text(
            "secret", encoding="utf-8"
        )
        (source_home / "device_id").write_text("device-secret", encoding="utf-8")
        (source_home / "config.toml").write_text(
            '''default_model = "kimi-code/k3"
extra_skill_dirs = ["/ambient/skill"]

[providers."managed:kimi-code"]
type = "kimi"
api_key = "oauth:kimi-code"
base_url = "https://example.invalid"

[providers."managed:kimi-code".oauth]
storage = "file"
key = "kimi-code"

[models."kimi-code/k3"]
provider = "managed:kimi-code"
model = "k3"
max_context_size = 100000
capabilities = ["tool_use"]

[models."kimi-code/kimi-for-coding"]
provider = "managed:kimi-code"
model = "kimi-for-coding"
max_context_size = 100000
capabilities = ["tool_use"]

[models.reviewer-kimi]
provider = "managed:kimi-code"
model = "kimi-for-coding"
max_context_size = 100000
capabilities = ["tool_use"]

[[hooks]]
event = "UserPromptSubmit"
command = "ambient-hook"
''',
            encoding="utf-8",
        )
        environment = os.environ.copy()
        environment.update(
            {
                "KIMI_CODE_HOME": str(source_home),
                "OPENAI_API_KEY": "must-not-cross-provider-boundary",
                "FAKE_SHOULD_NOT_LEAK": "1",
            }
        )
        result = subprocess.run(
            [
                sys.executable,
                str(RUN_PATH),
                "reviewer-calibration",
                "--provider",
                "kimi",
                "--kimi-path",
                str(fake_bin / "kimi"),
                "--model",
                model,
                "--reviewer-family",
                "moonshot",
                "--repeats",
                str(repeats),
                "--out",
                str(output_root),
                "--timeout-seconds",
                "5",
            ],
            text=True,
            capture_output=True,
            check=False,
            env=environment,
        )
        return result, output_root, log_path

    def test_claude_reviewer_calibration_reuses_code_review_safety_contract(self):
        with tempfile.TemporaryDirectory() as directory:
            result, output_root, log_path = self._run_claude_reviewer_calibration(
                directory
            )
            self.assertEqual(0, result.returncode, result.stderr)
            self.assertIn("calibration_status=pass", result.stdout)
            report_path = output_root / "reviewer-calibration-result.json"
            evidence_path = output_root / "reviewer-calibration.json"
            report = json.loads(report_path.read_text(encoding="utf-8"))
            evidence = json.loads(evidence_path.read_text(encoding="utf-8"))
            self.assertEqual("claude", report["provider"])
            self.assertEqual("claude-code test-1.0", report["provider_cli_version"])
            self.assertEqual("claude-test-exact", report["model"])
            self.assertEqual(
                "claude-cli-reviewer-calibration-v1",
                report["runner_contract"],
            )
            self.assertEqual("no-session-persistence", report["requested_session_mode"])
            self.assertEqual("verified-none", report["tool_access"])
            self.assertEqual("pass", report["calibration_evaluation"]["status"])
            self.trial.load_reviewer_calibration_result(
                report_path,
                json.loads(PILOT_GATES_PATH.read_text(encoding="utf-8")),
            )
            self.assertEqual("evaluated", evidence["status"])

            invocations = [
                json.loads(line)
                for line in log_path.read_text(encoding="utf-8").splitlines()
            ]
            self.assertEqual(2, len(invocations))
            expected_cases = json.loads(
                CALIBRATION_CASES_PATH.read_text(encoding="utf-8")
            )["cases"]
            for invocation in invocations:
                argv = invocation["argv"]
                self.assertIn("--tools", argv)
                self.assertEqual("", argv[argv.index("--tools") + 1])
                self.assertIn("--strict-mcp-config", argv)
                self.assertIn("--setting-sources", argv)
                self.assertIn("--safe-mode", argv)
                self.assertIn("--disable-slash-commands", argv)
                self.assertIn("--no-session-persistence", argv)
                self.assertIn("stream-json", argv)
                self.assertIn("--json-schema", argv)
                self.assertEqual("claude-test-exact", argv[argv.index("--model") + 1])
                self.assertTrue(invocation["tmpdir_is_cwd"])
                self.assertTrue({"USER", "LOGNAME"} <= set(invocation["env_keys"]))
                self.assertNotIn("OPENAI_API_KEY", invocation["env_keys"])
                self.assertNotIn("FAKE_SHOULD_NOT_LEAK", invocation["env_keys"])
                self.assertNotIn("REVIEWER CALIBRATION", " ".join(argv))
                self.assertNotIn("expected_verdict", invocation["prompt"])
                request = json.loads(
                    invocation["prompt"].split("CALIBRATION_INPUT=", 1)[1]
                )
                self.assertEqual(expected_cases, request["cases"])

    def test_claude_reviewer_calibration_fails_closed_on_runtime_or_model_drift(self):
        for behavior, expected_error in (
            ("quota", "provider process failed: quota_unavailable"),
            ("toolful", "Claude runtime isolation verification failed"),
            ("model-mismatch", "Claude runtime model does not match"),
            ("model-shape", "Claude runtime isolation verification failed"),
            ("missing-session-flag", "required Claude CLI flag is unavailable"),
        ):
            with (
                self.subTest(behavior=behavior),
                tempfile.TemporaryDirectory() as directory,
            ):
                result, output_root, _ = self._run_claude_reviewer_calibration(
                    directory, behavior=behavior
                )
                self.assertEqual(2, result.returncode)
                self.assertIn(expected_error, result.stderr)
                self.assertFalse(
                    (output_root / "reviewer-calibration-result.json").exists()
                )
                self.assertFalse((output_root / "reviewer-calibration.json").exists())

    def test_opencode_reviewer_calibration_uses_native_session_evidence_without_review_parser(
        self,
    ):
        with tempfile.TemporaryDirectory() as directory:
            result, output_root, log_path = self._run_opencode_reviewer_calibration(
                directory
            )
            self.assertEqual(0, result.returncode, result.stderr)
            self.assertIn("calibration_status=pass", result.stdout)
            report_path = output_root / "reviewer-calibration-result.json"
            report = json.loads(report_path.read_text(encoding="utf-8"))
            self.assertEqual("opencode", report["provider"])
            self.assertEqual("1.18.0-test", report["provider_cli_version"])
            self.assertEqual("deepseek/deepseek-v4-pro", report["model"])
            self.assertEqual("deepseek", report["reviewer_family"])
            self.assertEqual(
                "opencode-cli-reviewer-calibration-v1",
                report["runner_contract"],
            )
            self.assertEqual(
                "private-xdg-explicit-model-export",
                report["requested_session_mode"],
            )
            self.assertEqual("agent-disabled-observed-none", report["tool_access"])
            self.assertNotIn("OPENAI_API_KEY", report["provider_environment_keys"])
            self.trial.load_reviewer_calibration_result(
                report_path,
                json.loads(PILOT_GATES_PATH.read_text(encoding="utf-8")),
            )

            provider_source = OPENCODE_PROVIDER_PATH.read_text(encoding="utf-8")
            self.assertNotIn("parse_opencode_review", provider_source)
            self.assertNotIn("review model", provider_source.lower())
            self.assertNotIn("ccl-review", provider_source)
            invocations = [
                json.loads(line)
                for line in log_path.read_text(encoding="utf-8").splitlines()
            ]
            self.assertEqual(4, len(invocations))
            runs = [row for row in invocations if row["argv"][0] == "run"]
            self.assertEqual(2, len(runs))
            expected_cases = json.loads(
                CALIBRATION_CASES_PATH.read_text(encoding="utf-8")
            )["cases"]
            for invocation in runs:
                argv = invocation["argv"]
                self.assertEqual(
                    "deepseek/deepseek-v4-pro", argv[argv.index("--model") + 1]
                )
                self.assertEqual(
                    "reviewer-calibration", argv[argv.index("--agent") + 1]
                )
                self.assertEqual("json", argv[argv.index("--format") + 1])
                prompt = argv[-1]
                self.assertNotIn("expected_verdict", prompt)
                response_schema = json.loads(
                    prompt.split("RESPONSE_SCHEMA=", 1)[1].split(
                        "\nCALIBRATION_INPUT=", 1
                    )[0]
                )
                self.assertEqual(False, response_schema["additionalProperties"])
                self.assertEqual(
                    ["protocol_version", "judgments"],
                    response_schema["required"],
                )
                request = json.loads(prompt.split("CALIBRATION_INPUT=", 1)[1])
                self.assertEqual(expected_cases, request["cases"])
            self.assertEqual(2, len({row["xdg_data_home"] for row in runs}))
            self.assertEqual(2, len({row["cwd"] for row in runs}))
            expected_auth = str(
                Path(directory) / "ambient-xdg-data" / "opencode" / "auth.json"
            )
            for invocation in invocations:
                self.assertTrue(invocation["auth_is_link"])
                self.assertEqual(expected_auth, invocation["auth_target"])
                self.assertNotIn("FAKE_SHOULD_NOT_LEAK", invocation["env_keys"])
                self.assertNotIn("OPENAI_API_KEY", invocation["env_keys"])
                self.assertIn('"*": false', invocation["agent_text"])
                self.assertNotIn("ccl-review", invocation["agent_text"])
            tampered = dict(report)
            tampered["model"] = "deepseek"
            report_path.write_text(json.dumps(tampered), encoding="utf-8")
            with self.assertRaisesRegex(ValueError, "result binding is invalid"):
                self.trial.load_reviewer_calibration_result(
                    report_path,
                    json.loads(PILOT_GATES_PATH.read_text(encoding="utf-8")),
                )

    def test_opencode_reviewer_calibration_fails_closed_on_unbound_runtime(self):
        for behavior, expected_error in (
            ("model-mismatch", "OpenCode model evidence does not match"),
            ("model-switch", "OpenCode model evidence does not match"),
            ("agent-mismatch", "OpenCode exported session agent is invalid"),
            (
                "message-session-mismatch",
                "OpenCode exported message session binding is invalid",
            ),
            ("tool-event", "OpenCode event stream contains tool activity"),
            ("tool-export", "OpenCode export contains tool activity"),
            (
                "multiple-sessions",
                "OpenCode event stream session binding is invalid",
            ),
            ("export-mismatch", "OpenCode exported session does not match"),
            (
                "non-stop",
                "OpenCode final assistant turn did not stop cleanly",
            ),
            (
                "invalid-json",
                "OpenCode final assistant text contains invalid JSON",
            ),
            ("quota", "provider process failed: quota_unavailable"),
        ):
            with (
                self.subTest(behavior=behavior),
                tempfile.TemporaryDirectory() as directory,
            ):
                result, output_root, _ = self._run_opencode_reviewer_calibration(
                    directory, behavior=behavior
                )
                self.assertEqual(2, result.returncode)
                self.assertIn(expected_error, result.stderr)
                self.assertFalse(
                    (output_root / "reviewer-calibration-result.json").exists()
                )
                self.assertFalse((output_root / "reviewer-calibration.json").exists())

    @unittest.skipUnless(_TOMLLIB_AVAILABLE, "python < 3.11 lacks tomllib; kimi TOML config paths unavailable")
    def test_kimi_reviewer_calibration_uses_private_native_stream_without_review_parser(
        self,
    ):
        with tempfile.TemporaryDirectory() as directory:
            result, output_root, log_path = self._run_kimi_reviewer_calibration(
                directory
            )
            self.assertEqual(0, result.returncode, result.stderr)
            self.assertIn("calibration_status=pass", result.stdout)
            report_path = output_root / "reviewer-calibration-result.json"
            report = json.loads(report_path.read_text(encoding="utf-8"))
            self.assertEqual("kimi", report["provider"])
            self.assertEqual("0.27.0-test", report["provider_cli_version"])
            self.assertEqual("kimi-code/kimi-for-coding", report["model"])
            self.assertEqual("moonshot", report["reviewer_family"])
            self.assertEqual(
                "kimi-cli-reviewer-calibration-v1", report["runner_contract"]
            )
            self.assertEqual(
                "private-kimi-home-explicit-model-stream",
                report["requested_session_mode"],
            )
            self.assertEqual(
                "config-denied-stream-audited-detection-only",
                report["tool_access"],
            )
            self.assertEqual(
                {
                    "binding_type": "configured-alias",
                    "model_alias": "kimi-code/kimi-for-coding",
                    "provider_id": "managed:kimi-code",
                    "underlying_model": "kimi-for-coding",
                    "selected_config_hash": report["provider_binding"][
                        "selected_config_hash"
                    ],
                },
                report["provider_binding"],
            )
            self.assertRegex(
                report["provider_binding"]["selected_config_hash"],
                r"^sha256:[0-9a-f]{64}$",
            )
            self.assertEqual(
                self.trial.canonical_hash(report["provider_binding"]),
                report["provider_binding_hash"],
            )
            self.assertNotIn("OPENAI_API_KEY", report["provider_environment_keys"])
            self.trial.load_reviewer_calibration_result(
                report_path,
                json.loads(PILOT_GATES_PATH.read_text(encoding="utf-8")),
            )

            provider_source = KIMI_PROVIDER_PATH.read_text(encoding="utf-8")
            self.assertNotIn("parse_cli_review", provider_source)
            self.assertNotIn("kimi_review.sh", provider_source)
            invocations = [
                json.loads(line)
                for line in log_path.read_text(encoding="utf-8").splitlines()
            ]
            self.assertEqual(2, len(invocations))
            self.assertEqual(2, len({row["kimi_code_home"] for row in invocations}))
            self.assertEqual(2, len({row["cwd"] for row in invocations}))
            self.assertEqual(1, len({row["config_text"] for row in invocations}))
            expected_cases = json.loads(
                CALIBRATION_CASES_PATH.read_text(encoding="utf-8")
            )["cases"]
            for invocation in invocations:
                argv = invocation["argv"]
                self.assertEqual(
                    "kimi-code/kimi-for-coding", argv[argv.index("--model") + 1]
                )
                self.assertEqual(
                    "stream-json", argv[argv.index("--output-format") + 1]
                )
                self.assertIn("--skills-dir", argv)
                prompt = argv[argv.index("--prompt") + 1]
                self.assertNotIn("expected_verdict", prompt)
                response_schema = json.loads(
                    prompt.split("RESPONSE_SCHEMA=", 1)[1].split(
                        "\nCALIBRATION_INPUT=", 1
                    )[0]
                )
                self.assertEqual(False, response_schema["additionalProperties"])
                request = json.loads(prompt.split("CALIBRATION_INPUT=", 1)[1])
                self.assertEqual(expected_cases, request["cases"])
                config_text = invocation["config_text"]
                self.assertNotIn("extra_skill_dirs", config_text)
                self.assertNotIn("[[hooks]]", config_text)
                self.assertNotIn('models."kimi-code/k3"', config_text)
                self.assertIn('models."kimi-code/kimi-for-coding"', config_text)
                self.assertIn('decision = "deny"', config_text)
                self.assertIn('pattern = "*"', config_text)
                self.assertTrue(invocation["credentials_is_link"])
                self.assertTrue(invocation["oauth_is_link"])
                self.assertTrue(invocation["device_id_is_link"])
                self.assertNotIn("FAKE_SHOULD_NOT_LEAK", invocation["env_keys"])
                self.assertNotIn("OPENAI_API_KEY", invocation["env_keys"])

            tampered = dict(report)
            tampered["provider_binding"] = {
                **report["provider_binding"],
                "underlying_model": "other-model",
            }
            report_path.write_text(json.dumps(tampered), encoding="utf-8")
            report_path.chmod(0o600)
            with self.assertRaisesRegex(ValueError, "result binding is invalid"):
                self.trial.load_reviewer_calibration_result(
                    report_path,
                    json.loads(PILOT_GATES_PATH.read_text(encoding="utf-8")),
                )

    @unittest.skipUnless(_TOMLLIB_AVAILABLE, "python < 3.11 lacks tomllib; kimi TOML config paths unavailable")
    def test_kimi_reviewer_calibration_fails_closed_on_stream_or_config_drift(self):
        for behavior, expected_error in (
            ("tool", "Kimi event stream contains tool activity"),
            ("tool-result", "Kimi event stream contains tool activity"),
            ("unknown-event", "Kimi event stream role is invalid"),
            (
                "multiple-assistant",
                "Kimi event stream must contain one assistant response",
            ),
            ("no-resume", "Kimi event stream session binding is invalid"),
            ("multiple-sessions", "Kimi event stream session binding is invalid"),
            ("invalid-json", "Kimi final assistant text contains invalid JSON"),
            (
                "fenced-extra-text",
                "Kimi final assistant text contains invalid JSON",
            ),
            ("quota", "provider process failed: quota_unavailable"),
        ):
            with (
                self.subTest(behavior=behavior),
                tempfile.TemporaryDirectory() as directory,
            ):
                result, output_root, _ = self._run_kimi_reviewer_calibration(
                    directory, behavior=behavior
                )
                self.assertEqual(2, result.returncode)
                self.assertIn(expected_error, result.stderr)
                self.assertFalse(
                    (output_root / "reviewer-calibration-result.json").exists()
                )
                self.assertFalse((output_root / "reviewer-calibration.json").exists())

        with tempfile.TemporaryDirectory() as directory:
            result, output_root, log_path = self._run_kimi_reviewer_calibration(
                directory, model="kimi-code/missing"
            )
            self.assertEqual(2, result.returncode)
            self.assertIn("Kimi model alias is not configured", result.stderr)
            self.assertFalse(log_path.exists())
            self.assertFalse(
                (output_root / "reviewer-calibration-result.json").exists()
            )

        with tempfile.TemporaryDirectory() as directory:
            result, output_root, _ = self._run_kimi_reviewer_calibration(
                directory, model="reviewer-kimi"
            )
            self.assertEqual(0, result.returncode, result.stderr)
            report_path = output_root / "reviewer-calibration-result.json"
            report = json.loads(report_path.read_text(encoding="utf-8"))
            self.assertEqual("reviewer-kimi", report["model"])
            self.assertEqual(
                "reviewer-kimi", report["provider_binding"]["model_alias"]
            )
            self.trial.load_reviewer_calibration_result(
                report_path,
                json.loads(PILOT_GATES_PATH.read_text(encoding="utf-8")),
            )

    def test_reviewer_calibration_collects_raw_runs_without_truth_leakage(self):
        with tempfile.TemporaryDirectory() as directory:
            result, output_root, log_path = self._run_reviewer_calibration(directory)
            self.assertEqual(0, result.returncode, result.stderr)
            self.assertIn("calibration_status=pass", result.stdout)
            report_path = output_root / "reviewer-calibration-result.json"
            evidence_path = output_root / "reviewer-calibration.json"
            self.assertEqual(0o600, report_path.stat().st_mode & 0o777)
            self.assertEqual(0o600, evidence_path.stat().st_mode & 0o777)
            report = json.loads(report_path.read_text(encoding="utf-8"))
            evidence = json.loads(evidence_path.read_text(encoding="utf-8"))
            self.assertEqual("completed", report["execution_status"])
            self.assertEqual("pass", report["calibration_evaluation"]["status"])
            self.assertEqual(
                1.0,
                report["calibration_evaluation"]["reviewer_metrics"]["codex-test"][
                    "known_answer_accuracy"
                ],
            )
            self.assertRegex(report["case_fixture_hash"], r"^sha256:[0-9a-f]{64}$")
            self.assertRegex(report["pilot_gates_hash"], r"^sha256:[0-9a-f]{64}$")
            self.assertEqual("evaluated", evidence["status"])
            self.assertEqual(2, len(evidence["reviewers"][0]["runs"]))
            self.assertEqual(
                {"k1", "k2", "k3", "k4", "k5"},
                {
                    row["case_id"]
                    for run in evidence["reviewers"][0]["runs"]
                    for row in run
                },
            )
            invocations = [
                json.loads(line)
                for line in log_path.read_text(encoding="utf-8").splitlines()
            ]
            self.assertEqual(2, len(invocations))
            prompts = [row["prompt"] for row in invocations if row["prompt"]]
            self.assertEqual(2, len(prompts))
            expected_cases = json.loads(
                CALIBRATION_CASES_PATH.read_text(encoding="utf-8")
            )["cases"]
            self.assertTrue(all("REVIEWER CALIBRATION" in row for row in prompts))
            self.assertTrue(all("expected_verdict" not in row for row in prompts))
            self.assertTrue(all('"k1":"A win"' not in row for row in prompts))
            self.assertTrue(all('"k2":"B win"' not in row for row in prompts))
            for prompt in prompts:
                request = json.loads(prompt.split("CALIBRATION_INPUT=", 1)[1])
                self.assertEqual(
                    {"protocol_version", "instructions", "cases"}, set(request)
                )
                self.assertEqual(expected_cases, request["cases"])
                self.assertTrue(
                    all(set(row) == CASE_FIELDS for row in request["cases"])
                )
            self.assertTrue(all("--ephemeral" in row["argv"] for row in invocations))
            self.assertTrue(all("read-only" in row["argv"] for row in invocations))
            self.assertTrue(all(row["tmpdir_is_cwd"] for row in invocations))
            self.assertEqual(2, len({row["cwd"] for row in invocations}))

    def test_reviewer_calibration_persists_failed_metrics_without_false_pass(self):
        with tempfile.TemporaryDirectory() as directory:
            result, output_root, _ = self._run_reviewer_calibration(
                directory, behavior="calibration-wrong"
            )
            self.assertEqual(1, result.returncode, result.stderr)
            self.assertIn("calibration_status=fail", result.stdout)
            report = json.loads(
                (output_root / "reviewer-calibration-result.json").read_text(
                    encoding="utf-8"
                )
            )
            self.assertEqual("fail", report["calibration_evaluation"]["status"])
            self.assertIn(
                "reviewer_self_calibration",
                report["calibration_evaluation"]["failures"],
            )
            self.assertTrue((output_root / "reviewer-calibration.json").exists())

    def test_reviewer_calibration_output_root_is_one_shot(self):
        with tempfile.TemporaryDirectory() as directory:
            first, output_root, _ = self._run_reviewer_calibration(directory)
            self.assertEqual(0, first.returncode, first.stderr)
            second, _, _ = self._run_reviewer_calibration(
                directory, output_root=output_root
            )
            self.assertEqual(2, second.returncode)
            self.assertIn("output root is already claimed", second.stderr)

    def test_provider_subprocess_is_reaped_on_parent_signals(self):
        for signum in (signal.SIGINT, signal.SIGTERM, signal.SIGHUP):
            with (
                self.subTest(signum=signum),
                tempfile.TemporaryDirectory() as directory,
            ):
                fake_bin = self._write_fake_codex(directory, behavior="signal-wait")
                output_root = Path(directory) / "signal-output"
                log_path = Path(directory) / "fake-codex.jsonl"
                process = subprocess.Popen(
                    [
                        sys.executable,
                        str(RUN_PATH),
                        "reviewer-calibration",
                        "--provider",
                        "codex",
                        "--codex-path",
                        str(fake_bin / "codex"),
                        "--model",
                        "gpt-test-exact",
                        "--reviewer-family",
                        "codex-test",
                        "--repeats",
                        "2",
                        "--out",
                        str(output_root),
                        "--timeout-seconds",
                        "60",
                    ],
                    text=True,
                    stdout=subprocess.PIPE,
                    stderr=subprocess.PIPE,
                )
                try:
                    deadline = time.monotonic() + 5
                    log_lines = []
                    while time.monotonic() < deadline:
                        if log_path.exists():
                            log_lines = log_path.read_text(
                                encoding="utf-8"
                            ).splitlines()
                            if log_lines:
                                break
                        time.sleep(0.02)
                    self.assertTrue(
                        log_lines, "provider child did not publish a log record"
                    )
                    child_record = json.loads(log_lines[-1])
                    child_pid = child_record["pid"]
                    self.assertTrue(
                        set(child_record["blocked_signals"]).isdisjoint(
                            {signal.SIGINT, signal.SIGTERM, signal.SIGHUP}
                        )
                    )
                    os.kill(process.pid, signum)
                    process.communicate(timeout=5)
                    self.assertEqual(128 + signum, process.returncode)
                    child_alive = True
                    for _ in range(40):
                        try:
                            os.kill(child_pid, 0)
                        except ProcessLookupError:
                            child_alive = False
                            break
                        time.sleep(0.05)
                    self.assertFalse(
                        child_alive, "provider child survived parent signal"
                    )
                    self.assertFalse(
                        (output_root / "reviewer-calibration-result.json").exists()
                    )
                    self.assertFalse(
                        (output_root / "reviewer-calibration.json").exists()
                    )
                finally:
                    if process.poll() is None:
                        process.kill()
                        process.wait()

        with tempfile.TemporaryDirectory() as directory:
            fake_bin = self._write_fake_codex(directory, behavior="signal-hard-wait")
            output_root = Path(directory) / "repeated-signal-output"
            log_path = Path(directory) / "fake-codex.jsonl"
            process = subprocess.Popen(
                [
                    sys.executable,
                    str(RUN_PATH),
                    "reviewer-calibration",
                    "--provider",
                    "codex",
                    "--codex-path",
                    str(fake_bin / "codex"),
                    "--model",
                    "gpt-test-exact",
                    "--reviewer-family",
                    "codex-test",
                    "--repeats",
                    "2",
                    "--out",
                    str(output_root),
                    "--timeout-seconds",
                    "60",
                ],
                text=True,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
            )
            try:
                deadline = time.monotonic() + 5
                log_lines = []
                while time.monotonic() < deadline:
                    if log_path.exists():
                        log_lines = log_path.read_text(
                            encoding="utf-8"
                        ).splitlines()
                        if log_lines:
                            break
                    time.sleep(0.02)
                self.assertTrue(
                    log_lines, "provider child did not publish a log record"
                )
                child_record = json.loads(log_lines[-1])
                child_pid = child_record["pid"]
                self.assertTrue(
                    set(child_record["blocked_signals"]).isdisjoint(
                        {signal.SIGINT, signal.SIGTERM, signal.SIGHUP}
                    )
                )
                os.kill(process.pid, signal.SIGTERM)
                time.sleep(0.2)
                os.kill(process.pid, signal.SIGHUP)
                process.communicate(timeout=5)
                # Death-by-our-signal is reported as exit code 143 on some
                # platforms and as -signum on others; on this runner SIGTERM
                # may not land first, so accept death by either sent signal.
                self.assertIn(
                    process.returncode,
                    {128 + signal.SIGTERM, -signal.SIGTERM, -signal.SIGHUP},
                )
                with self.assertRaises(ProcessLookupError):
                    os.kill(child_pid, 0)
                self.assertFalse(
                    (output_root / "reviewer-calibration-result.json").exists()
                )
                self.assertFalse((output_root / "reviewer-calibration.json").exists())
            finally:
                if process.poll() is None:
                    process.kill()
                    process.wait()

    def test_provider_subprocess_is_reaped_in_popen_signal_window(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            ready_path = root / "child-ready"
            pid_path = root / "child-pid"
            child_path = root / "child.py"
            child_path.write_text(
                "\n".join(
                    (
                        "import signal",
                        "import sys",
                        "import time",
                        "from pathlib import Path",
                        "signal.signal(signal.SIGTERM, signal.SIG_IGN)",
                        "signal.signal(signal.SIGHUP, signal.SIG_IGN)",
                        "blocked = sorted(",
                        "    int(signum)",
                        "    for signum in signal.pthread_sigmask(signal.SIG_BLOCK, [])",
                        ")",
                        "Path(sys.argv[1]).write_text(str(blocked), encoding='utf-8')",
                        "time.sleep(30)",
                    )
                ),
                encoding="utf-8",
            )
            driver_path = root / "driver.py"
            driver_path.write_text(
                "\n".join(
                    (
                        "import os",
                        "import signal",
                        "import sys",
                        "import time",
                        "from pathlib import Path",
                        f"sys.path.insert(0, {str(TRIAL_DIR)!r})",
                        "import provider_probe",
                        "real_popen = provider_probe.subprocess.Popen",
                        f"ready_path = Path({str(ready_path)!r})",
                        f"pid_path = Path({str(pid_path)!r})",
                        "def race_popen(*args, **kwargs):",
                        "    child = real_popen(*args, **kwargs)",
                        "    deadline = time.monotonic() + 5",
                        "    while time.monotonic() < deadline and not ready_path.exists():",
                        "        time.sleep(0.01)",
                        "    pid_path.write_text(str(child.pid), encoding='utf-8')",
                        "    os.kill(os.getpid(), signal.SIGTERM)",
                        "    return child",
                        "provider_probe.subprocess.Popen = race_popen",
                        "provider_probe._run_bounded(",
                        f"    [sys.executable, {str(child_path)!r}, {str(ready_path)!r}],",
                        f"    cwd=Path({str(root)!r}),",
                        "    timeout_seconds=60,",
                        ")",
                    )
                ),
                encoding="utf-8",
            )
            process = subprocess.run(
                [sys.executable, str(driver_path)],
                text=True,
                capture_output=True,
                check=False,
                timeout=10,
            )
            self.assertEqual(128 + signal.SIGTERM, process.returncode, process.stderr)
            self.assertTrue(pid_path.exists(), "race child pid was not recorded")
            self.assertEqual("[]", ready_path.read_text(encoding="utf-8"))
            child_pid = int(pid_path.read_text(encoding="utf-8"))
            child_alive = True
            try:
                for _ in range(40):
                    try:
                        os.kill(child_pid, 0)
                    except ProcessLookupError:
                        child_alive = False
                        break
                    time.sleep(0.05)
                self.assertFalse(child_alive, "provider child survived Popen signal")
            finally:
                if child_alive:
                    try:
                        os.killpg(child_pid, signal.SIGKILL)
                    except ProcessLookupError:
                        pass

    def test_provider_signal_wins_over_popen_failure(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            driver_path = root / "driver.py"
            driver_path.write_text(
                "\n".join(
                    (
                        "import os",
                        "import signal",
                        "import sys",
                        "from pathlib import Path",
                        f"sys.path.insert(0, {str(TRIAL_DIR)!r})",
                        "import provider_probe",
                        "def failing_popen(*args, **kwargs):",
                        "    os.kill(os.getpid(), signal.SIGTERM)",
                        "    raise OSError('spawn failed')",
                        "provider_probe.subprocess.Popen = failing_popen",
                        "provider_probe._run_bounded(",
                        "    [sys.executable, '-c', 'pass'],",
                        f"    cwd=Path({str(root)!r}),",
                        "    timeout_seconds=60,",
                        ")",
                    )
                ),
                encoding="utf-8",
            )
            process = subprocess.run(
                [sys.executable, str(driver_path)],
                text=True,
                capture_output=True,
                check=False,
                timeout=10,
            )
            self.assertEqual(128 + signal.SIGTERM, process.returncode, process.stderr)
            self.assertNotIn("spawn failed", process.stderr)

    def test_live_calibration_bundle_rejects_swapped_or_unbound_evidence(self):
        config = json.loads(PILOT_GATES_PATH.read_text(encoding="utf-8"))
        with tempfile.TemporaryDirectory() as directory:
            passed, passed_root, _ = self._run_reviewer_calibration(
                directory, output_root=Path(directory) / "passed"
            )
            failed, failed_root, _ = self._run_reviewer_calibration(
                directory,
                behavior="calibration-wrong",
                output_root=Path(directory) / "failed",
            )
            self.assertEqual(0, passed.returncode, passed.stderr)
            self.assertEqual(1, failed.returncode, failed.stderr)
            result_path = passed_root / "reviewer-calibration-result.json"
            self.trial.load_reviewer_calibration_result(result_path, config)

            evidence_path = passed_root / "reviewer-calibration.json"
            original_evidence = evidence_path.read_bytes()
            original_result = result_path.read_bytes()
            evidence_path.write_bytes(
                (failed_root / "reviewer-calibration.json").read_bytes()
            )
            evidence_path.chmod(0o600)
            with self.assertRaisesRegex(ValueError, "result binding is invalid"):
                self.trial.load_reviewer_calibration_result(result_path, config)

            evidence_path.write_bytes(original_evidence)
            evidence_path.chmod(0o600)
            result = json.loads(original_result)
            result["case_fixture_hash"] = "sha256:" + "d" * 64
            result_path.write_text(json.dumps(result), encoding="utf-8")
            result_path.chmod(0o600)
            with self.assertRaisesRegex(ValueError, "result binding is invalid"):
                self.trial.load_reviewer_calibration_result(result_path, config)

            result = json.loads(original_result)
            result.pop("calibration_evidence_hash")
            result_path.write_text(json.dumps(result), encoding="utf-8")
            result_path.chmod(0o600)
            with self.assertRaisesRegex(ValueError, "field set is invalid"):
                self.trial.load_reviewer_calibration_result(result_path, config)

            result = json.loads(original_result)
            result["provider"] = []
            result_path.write_text(json.dumps(result), encoding="utf-8")
            result_path.chmod(0o600)
            with self.assertRaisesRegex(ValueError, "result binding is invalid"):
                self.trial.load_reviewer_calibration_result(result_path, config)

    def test_live_calibration_rejects_removed_controller_result_contract(self):
        config = json.loads(PILOT_GATES_PATH.read_text(encoding="utf-8"))
        calibration, _ = raw_calibration(self.trial, families=("codex",))
        with tempfile.TemporaryDirectory() as directory:
            result_path = write_sealed_calibration_result(
                self.trial,
                Path(directory) / "calibration",
                calibration,
                config,
            )
            result = self.trial.load_private_json(result_path)
            for field in (
                "provider_cli_version",
                "provider_executable_hash",
                "provider_environment_keys",
                "runner_contract",
                "runner_hash",
                "requested_session_mode",
                "tool_access",
            ):
                result.pop(field)
            result.update(
                {
                    "artifact_contract": (
                        "skill-effectiveness-controller-calibration-result-v1"
                    ),
                    "runtime_binding": "sha256:" + "d" * 64,
                    "side_effect_visibility": "partial",
                }
            )
            self.trial.write_json_atomic(result_path, result)

            with self.assertRaisesRegex(ValueError, "field set is invalid"):
                self.trial.load_reviewer_calibration_result(result_path, config)

    def test_reviewer_calibration_readback_failure_never_leaves_success_report(self):
        with tempfile.TemporaryDirectory() as directory:
            fake_bin = self._write_fake_codex(directory)
            output_root = Path(directory) / "readback-failure"
            module = load_run_module().reviewer_calibration
            original_loader = module.trial.load_private_json

            def fail_evidence_readback(path):
                if Path(path).name == ".reviewer-calibration.pending.json":
                    raise ValueError("injected evidence read-back failure")
                return original_loader(path)

            with (
                mock.patch.object(
                    module.trial,
                    "load_private_json",
                    side_effect=fail_evidence_readback,
                ),
                self.assertRaisesRegex(
                    ValueError, "injected evidence read-back failure"
                ),
            ):
                module.run_codex_reviewer_calibration(
                    codex_path=fake_bin / "codex",
                    model="gpt-test-exact",
                    reviewer_family="codex-test",
                    repeats=2,
                    output_root=output_root,
                    timeout_seconds=5,
                    known_answers_path=CALIBRATION_FIXTURE_PATH,
                    cases_path=CALIBRATION_CASES_PATH,
                    pilot_gates_path=PILOT_GATES_PATH,
                )
            self.assertFalse((output_root / "reviewer-calibration.json").exists())
            self.assertFalse(
                (output_root / "reviewer-calibration-result.json").exists()
            )
            self.assertFalse(
                (output_root / ".reviewer-calibration.pending.json").exists()
            )
            self.assertFalse(
                (
                    output_root
                    / ".reviewer-calibration-result.pending.json"
                ).exists()
            )

    def test_reviewer_calibration_publication_signal_never_leaves_half_pair(self):
        with tempfile.TemporaryDirectory() as directory:
            fake_bin = self._write_fake_codex(directory)
            output_root = Path(directory) / "publication-signal"
            module = load_run_module().reviewer_calibration
            original_replace = module.os.replace
            original_handler = signal.getsignal(signal.SIGTERM)

            def signal_after_evidence_publish(source, destination):
                original_replace(source, destination)
                if Path(destination).name == "reviewer-calibration.json":
                    os.kill(os.getpid(), signal.SIGTERM)

            signal.signal(signal.SIGTERM, lambda _signum, _frame: None)
            try:
                with (
                    mock.patch.object(
                        module.os,
                        "replace",
                        side_effect=signal_after_evidence_publish,
                    ),
                    self.assertRaises(SystemExit),
                ):
                    module.run_codex_reviewer_calibration(
                        codex_path=fake_bin / "codex",
                        model="gpt-test-exact",
                        reviewer_family="codex-test",
                        repeats=2,
                        output_root=output_root,
                        timeout_seconds=5,
                        known_answers_path=CALIBRATION_FIXTURE_PATH,
                        cases_path=CALIBRATION_CASES_PATH,
                        pilot_gates_path=PILOT_GATES_PATH,
                    )
            finally:
                signal.signal(signal.SIGTERM, original_handler)
            for name in (
                "reviewer-calibration.json",
                "reviewer-calibration-result.json",
                ".reviewer-calibration.pending.json",
                ".reviewer-calibration-result.pending.json",
            ):
                self.assertFalse((output_root / name).exists(), name)

    def test_reviewer_calibration_rejects_partial_or_invalid_judgments(self):
        for behavior in ("calibration-missing", "calibration-invalid"):
            with (
                self.subTest(behavior=behavior),
                tempfile.TemporaryDirectory() as directory,
            ):
                result, output_root, _ = self._run_reviewer_calibration(
                    directory, behavior=behavior
                )
                self.assertEqual(2, result.returncode)
                expected_error = (
                    "judgment case set is incomplete"
                    if behavior == "calibration-missing"
                    else "judgment verdict is invalid"
                )
                self.assertIn(expected_error, result.stderr)
                self.assertFalse(
                    (output_root / "reviewer-calibration-result.json").exists()
                )
                self.assertFalse((output_root / "reviewer-calibration.json").exists())

    def test_reviewer_calibration_rejects_tool_activity_and_single_run(self):
        with tempfile.TemporaryDirectory() as directory:
            result, output_root, _ = self._run_reviewer_calibration(
                directory, behavior="tool"
            )
            self.assertEqual(2, result.returncode)
            self.assertIn("tool activity", result.stderr)
            self.assertFalse((output_root / "reviewer-calibration.json").exists())
            self.assertFalse(
                (output_root / "reviewer-calibration-result.json").exists()
            )
            retry, _, _ = self._run_reviewer_calibration(
                directory, output_root=output_root
            )
            self.assertEqual(2, retry.returncode)
            self.assertIn("output root is already claimed", retry.stderr)

        for repeats in (1, 6):
            with (
                self.subTest(repeats=repeats),
                tempfile.TemporaryDirectory() as directory,
            ):
                result, output_root, _ = self._run_reviewer_calibration(
                    directory, repeats=repeats
                )
                self.assertEqual(2, result.returncode)
                self.assertIn("repeats must be between 2 and 5", result.stderr)
                self.assertFalse((output_root / "reviewer-calibration.json").exists())

        with tempfile.TemporaryDirectory() as directory:
            result, output_root, _ = self._run_reviewer_calibration(
                directory, behavior="nonzero"
            )
            self.assertEqual(2, result.returncode)
            self.assertFalse((output_root / "reviewer-calibration.json").exists())
            self.assertFalse(
                (output_root / "reviewer-calibration-result.json").exists()
            )

    def test_provider_probe_persists_no_leak_evidence_without_false_promotion(self):
        with tempfile.TemporaryDirectory() as directory:
            result, output_root, log_path = self._run_provider_probe(directory)
            self.assertEqual(0, result.returncode, result.stderr)
            self.assertIn(
                "isolation_outcome=unresolved_isolation_threat", result.stdout
            )
            report_path = output_root / "provider-probe-result.json"
            artifact_path = output_root / "capability-probe-plan.json"
            self.assertEqual(0o600, report_path.stat().st_mode & 0o777)
            self.assertEqual(0o600, artifact_path.stat().st_mode & 0o777)
            report_text = report_path.read_text(encoding="utf-8")
            report = json.loads(report_text)
            artifact = json.loads(artifact_path.read_text(encoding="utf-8"))
            self.assertEqual("completed", report["execution_status"])
            self.assertEqual("codex", report["provider"])
            self.assertEqual("gpt-test-exact", report["model"])
            self.assertEqual("codex-cli test-1.0", report["provider_cli_version"])
            self.assertRegex(
                report["provider_executable_hash"], r"^sha256:[0-9a-f]{64}$"
            )
            runner_suffix = self.trial.canonical_hash(
                {
                    "cli_version": report["provider_cli_version"],
                    "executable_hash": report["provider_executable_hash"],
                }
            )[7:19]
            self.assertEqual(
                f"codex-cli-provider-probe-v1-{runner_suffix}",
                artifact["entry"]["runner"],
            )
            self.assertTrue(report["cross_trial_canary"]["seed_acknowledged"])
            self.assertTrue(report["cross_trial_canary"]["recall_probe_completed"])
            self.assertFalse(
                report["cross_trial_canary"]["cross_session_recall_detected"]
            )
            self.assertEqual("unresolved_isolation_threat", report["isolation_outcome"])
            self.assertEqual("unverified", report["provider_persistence_declaration"])
            self.assertEqual("ephemeral", report["requested_session_mode"])
            self.assertEqual(
                "causal_core_unavailable", report["capability_matrix"]["status"]
            )
            reasons = report["capability_matrix"]["entries"][0]["reasons"]
            self.assertIn("mount_boundary_unproven", reasons)
            self.assertIn("access_audit_unproven", reasons)
            self.assertIn("memory_isolation_unproven", reasons)
            invocations = [
                json.loads(line)
                for line in log_path.read_text(encoding="utf-8").splitlines()
            ]
            self.assertEqual(2, len(invocations))
            self.assertNotEqual(invocations[0]["cwd"], invocations[1]["cwd"])
            for invocation in invocations:
                argv = invocation["argv"]
                self.assertIn("--ephemeral", argv)
                self.assertIn("--ignore-user-config", argv)
                self.assertNotIn("--strict-config", argv)
                self.assertIn("--skip-git-repo-check", argv)
                self.assertIn("read-only", argv)
                self.assertIn("gpt-test-exact", argv)
                self.assertIn("--json", argv)
                self.assertIn("--output-schema", argv)
                self.assertNotIn("--output-last-message", argv)
                self.assertNotIn("resume", argv)
                self.assertNotIn("CODEX_HOME", invocation["env_keys"])
                self.assertNotIn("OPENAI_BASE_URL", invocation["env_keys"])
                self.assertNotIn("FAKE_SHOULD_NOT_LEAK", invocation["env_keys"])
                self.assertTrue(invocation["tmpdir_is_cwd"])
            seed_canary = invocations[0]["prompt"].split("CANARY=", 1)[1].split()[0]
            self.assertEqual(64, len(seed_canary))
            self.assertNotIn(seed_canary, invocations[1]["prompt"])
            self.assertNotIn(seed_canary, report_text)

    def test_provider_probe_records_detected_cross_session_leak(self):
        with tempfile.TemporaryDirectory() as directory:
            result, output_root, _ = self._run_provider_probe(
                directory, behavior="leak"
            )
            self.assertEqual(0, result.returncode, result.stderr)
            self.assertIn("isolation_outcome=contaminated", result.stdout)
            report = json.loads(
                (output_root / "provider-probe-result.json").read_text(encoding="utf-8")
            )
            self.assertTrue(
                report["cross_trial_canary"]["cross_session_recall_detected"]
            )
            self.assertEqual("contaminated", report["isolation_outcome"])
            self.assertEqual(
                "causal_core_unavailable", report["capability_matrix"]["status"]
            )

    def test_provider_probe_records_a_foreign_historical_canary_as_a_leak(self):
        with tempfile.TemporaryDirectory() as directory:
            result, output_root, _ = self._run_provider_probe(
                directory, behavior="foreign-leak"
            )
            self.assertEqual(0, result.returncode, result.stderr)
            report_text = (output_root / "provider-probe-result.json").read_text(
                encoding="utf-8"
            )
            report = json.loads(report_text)
            self.assertTrue(
                report["cross_trial_canary"]["cross_session_recall_detected"]
            )
            self.assertRegex(
                report["cross_trial_canary"]["recalled_value_hash"],
                r"^sha256:[0-9a-f]{64}$",
            )
            self.assertNotIn("f" * 64, report_text)

    def test_provider_probe_records_a_reformatted_canary_as_a_leak(self):
        with tempfile.TemporaryDirectory() as directory:
            result, output_root, _ = self._run_provider_probe(
                directory, behavior="near-miss-leak"
            )
            self.assertEqual(0, result.returncode, result.stderr)
            report_text = (output_root / "provider-probe-result.json").read_text(
                encoding="utf-8"
            )
            report = json.loads(report_text)
            self.assertTrue(
                report["cross_trial_canary"]["cross_session_recall_detected"]
            )
            self.assertNotIn("remembered:", report_text)

    def test_provider_probe_schema_uses_explicit_supported_types(self):
        provider_probe = load_run_module().provider_probe
        for phase in ("seed", "recall"):
            schema = provider_probe._phase_schema(phase)
            properties = schema["properties"]
            self.assertEqual(
                {"type": "integer", "enum": [1]},
                properties["protocol_version"],
            )
            self.assertEqual({"type": "string", "enum": [phase]}, properties["phase"])

    def test_provider_probe_requires_exact_model_and_avoids_partial_report(self):
        with tempfile.TemporaryDirectory() as directory:
            output_root = Path(directory) / "provider-output"
            result = subprocess.run(
                [
                    sys.executable,
                    str(RUN_PATH),
                    "provider-probe",
                    "--provider",
                    "codex",
                    "--task-family",
                    "plan",
                    "--out",
                    str(output_root),
                ],
                text=True,
                capture_output=True,
                check=False,
            )
            self.assertEqual(2, result.returncode)
            self.assertIn("--model", result.stderr)
            self.assertFalse((output_root / "provider-probe-result.json").exists())

    def test_provider_probe_requires_an_explicit_codex_path(self):
        with tempfile.TemporaryDirectory() as directory:
            fake_bin = self._write_fake_codex(directory)
            output_root = Path(directory) / "provider-output"
            environment = os.environ.copy()
            environment["PATH"] = (
                str(fake_bin) + os.pathsep + environment.get("PATH", "")
            )
            result = subprocess.run(
                [
                    sys.executable,
                    str(RUN_PATH),
                    "provider-probe",
                    "--provider",
                    "codex",
                    "--model",
                    "gpt-test-exact",
                    "--task-family",
                    "plan",
                    "--out",
                    str(output_root),
                ],
                text=True,
                capture_output=True,
                check=False,
                env=environment,
            )
            self.assertEqual(2, result.returncode)
            self.assertIn("--codex-path", result.stderr)
            self.assertFalse((output_root / "provider-probe-result.json").exists())

    def test_provider_probe_nonzero_provider_exit_avoids_partial_report(self):
        with tempfile.TemporaryDirectory() as directory:
            result, output_root, _ = self._run_provider_probe(
                directory, behavior="nonzero"
            )
            self.assertEqual(2, result.returncode)
            self.assertIn("provider process failed", result.stderr)
            self.assertFalse((output_root / "provider-probe-result.json").exists())

    def test_provider_probe_classifies_unsupported_flag_without_raw_stderr(self):
        with tempfile.TemporaryDirectory() as directory:
            result, output_root, _ = self._run_provider_probe(
                directory, behavior="unsupported"
            )
            self.assertEqual(2, result.returncode)
            self.assertIn("unsupported_flag", result.stderr)
            self.assertNotIn("--ignore-user-config", result.stderr)
            self.assertFalse((output_root / "provider-probe-result.json").exists())

    def test_provider_probe_classifies_usage_limit_from_event_stream(self):
        with tempfile.TemporaryDirectory() as directory:
            result, output_root, _ = self._run_provider_probe(
                directory, behavior="usage-limit"
            )
            self.assertEqual(2, result.returncode)
            self.assertIn("quota_unavailable", result.stderr)
            self.assertNotIn("purchase more credits", result.stderr.lower())
            self.assertFalse((output_root / "provider-probe-result.json").exists())

    def test_provider_probe_rejects_codex_tool_activity(self):
        with tempfile.TemporaryDirectory() as directory:
            result, output_root, _ = self._run_provider_probe(
                directory, behavior="tool"
            )
            self.assertEqual(2, result.returncode)
            self.assertIn("tool activity", result.stderr)
            self.assertFalse((output_root / "provider-probe-result.json").exists())

    def test_provider_probe_kills_an_oversized_event_stream(self):
        with tempfile.TemporaryDirectory() as directory:
            result, output_root, _ = self._run_provider_probe(
                directory, behavior="event-flood"
            )
            self.assertEqual(2, result.returncode)
            self.assertIn("stdout exceeded limit", result.stderr)
            self.assertFalse((output_root / "provider-probe-result.json").exists())

    def test_provider_probe_rejects_malformed_and_oversized_messages(self):
        for behavior, expected in (
            ("malformed", "invalid JSON"),
            ("oversized", "too large"),
        ):
            with (
                self.subTest(behavior=behavior),
                tempfile.TemporaryDirectory() as directory,
            ):
                result, output_root, _ = self._run_provider_probe(
                    directory, behavior=behavior
                )
                self.assertEqual(2, result.returncode)
                self.assertIn(expected, result.stderr)
                self.assertFalse((output_root / "provider-probe-result.json").exists())

    def test_provider_probe_rejects_non_scalar_recall_without_traceback(self):
        with tempfile.TemporaryDirectory() as directory:
            result, output_root, _ = self._run_provider_probe(
                directory, behavior="bad-shape"
            )
            self.assertEqual(2, result.returncode)
            self.assertIn("not null or a string", result.stderr)
            self.assertNotIn("Traceback", result.stderr)
            self.assertFalse((output_root / "provider-probe-result.json").exists())

    def test_provider_probe_times_out_and_rejects_symlink_output_root(self):
        with tempfile.TemporaryDirectory() as directory:
            result, output_root, _ = self._run_provider_probe(
                directory, behavior="timeout", timeout_seconds=1
            )
            self.assertEqual(2, result.returncode)
            self.assertIn("timed out", result.stderr)
            self.assertFalse((output_root / "provider-probe-result.json").exists())

        with tempfile.TemporaryDirectory() as directory:
            real_output = Path(directory) / "real-output"
            real_output.mkdir(mode=0o700)
            output_link = Path(directory) / "output-link"
            output_link.symlink_to(real_output, target_is_directory=True)
            result, _, _ = self._run_provider_probe(directory, output_root=output_link)
            self.assertEqual(2, result.returncode)
            self.assertIn("output root must not be a symlink", result.stderr)
            self.assertFalse((real_output / "provider-probe-result.json").exists())

    def test_provider_probe_serializes_one_output_root(self):
        with tempfile.TemporaryDirectory() as directory:
            fake_bin = self._write_fake_codex(directory, behavior="delay")
            output_root = Path(directory) / "provider-output"
            output_root.mkdir(mode=0o700)
            environment = os.environ.copy()
            environment.update(
                {
                    "PATH": str(fake_bin) + os.pathsep + environment.get("PATH", ""),
                }
            )
            command = [
                sys.executable,
                str(RUN_PATH),
                "provider-probe",
                "--provider",
                "codex",
                "--codex-path",
                str(fake_bin / "codex"),
                "--model",
                "gpt-test-exact",
                "--task-family",
                "plan",
                "--out",
                str(output_root),
                "--timeout-seconds",
                "5",
            ]

            def invoke():
                return subprocess.run(
                    command,
                    text=True,
                    capture_output=True,
                    check=False,
                    env=environment,
                )

            with ThreadPoolExecutor(max_workers=2) as pool:
                results = list(pool.map(lambda _: invoke(), range(2)))
            self.assertEqual([0, 2], sorted(result.returncode for result in results))
            failed = next(result for result in results if result.returncode == 2)
            self.assertIn(
                "provider probe output root is already claimed", failed.stderr
            )
            self.assertTrue((output_root / "provider-probe-result.json").exists())


def profile_arm_template(arm_id, treatment, allowlisted_diff, scope="main"):
    return {
        "schema_version": 1,
        "registry_schema": "paired-profile",
        "arm_id": arm_id,
        "scope": scope,
        "treatment": treatment,
        "allowlisted_diff": allowlisted_diff,
        "runnable": True,
    }


def profile_components(profile_payload):
    return {
        "task_builder_template": b"task-builder-revision-1",
        "task": b"synthetic-analysis-task",
        "driver": b"fixture-driver",
        "model": b"deterministic-no-model-call",
        "prompt_template": b"prompt-template-v1",
        "permission_profile": b"analysis-read-only",
        "profile_payload": profile_payload,
    }


def advisory_record(expected_trial, family):
    record = passing_record(expected_trial, family)
    # The advisory tier waives isolation-evidence proof, so the runner reports
    # no observation instead of a fabricated boolean.
    record["access_audit_ok"] = None
    record["memory_isolation_ok"] = None
    record.pop("matched_call_compliant", None)
    return record


def rebind_row_session(trial, row, session_id):
    """Rebuild one planned row against a different session id."""

    runtime = dict(row["runtime"], session_id=session_id)
    fingerprint_input = dict(row["fingerprint_input"], runtime=runtime)
    rebound = dict(
        row,
        runtime=runtime,
        runtime_hash=trial.canonical_hash(runtime),
        fingerprint_input=fingerprint_input,
    )
    rebound["trial_fingerprint"] = trial.canonical_hash(fingerprint_input)
    return rebound


class ProfileRegistryAndEvidenceTierTest(unittest.TestCase):
    """Slice 1 additions: paired-profile registry and tiered verdicts."""

    @classmethod
    def setUpClass(cls):
        cls.trial = load_trial_module()

    def frozen_pair(self, candidate=b"candidate-profile-text"):
        off = self.trial.freeze_profile_arm_manifest(
            profile_arm_template("profile-off", "off", []),
            profile_components(b"built-in-profile-text"),
        )
        full = self.trial.freeze_profile_arm_manifest(
            profile_arm_template("profile-full", "full", ["profile_payload"]),
            profile_components(candidate),
        )
        return off, full

    def test_committed_advisory_gates_bind_the_paired_profile_tier(self):
        config = json.loads(PILOT_GATES_PATH.read_text(encoding="utf-8"))

        self.assertEqual("advisory", config["enforcement"])
        self.assertEqual(
            self.trial.checkpoint_evidence_tier("paired-profile"),
            self.trial.evidence_tier_declaration(config),
        )

    def test_profile_arm_template_rejects_skill_content_contracts(self):
        trial = self.trial
        off, full = self.frozen_pair()
        self.assertEqual([], trial.validate_frozen_profile_manifest(off))
        self.assertEqual([], trial.validate_frozen_profile_manifest(full))
        self.assertEqual("paired-profile", trial.manifest_registry_schema(off))
        self.assertEqual(
            "skill-content",
            trial.manifest_registry_schema(
                trial.freeze_arm_manifest(
                    arm_template("S0", "off", []), common_components(b"")
                )
            ),
        )
        for treatment in ("oracle", "active_control"):
            with self.assertRaises(ValueError):
                trial.freeze_profile_arm_manifest(
                    profile_arm_template("profile-x", treatment, ["profile_payload"]),
                    profile_components(b"x"),
                )
        with self.assertRaises(ValueError):
            trial.freeze_profile_arm_manifest(
                profile_arm_template("profile-full", "full", ["prompt_template"]),
                profile_components(b"x"),
            )
        missing_schema = profile_arm_template("profile-off", "off", [])
        missing_schema.pop("registry_schema")
        with self.assertRaises(ValueError):
            trial.freeze_profile_arm_manifest(
                missing_schema, profile_components(b"built-in-profile-text")
            )
        skill_content_fields = profile_arm_template("profile-off", "off", [])
        skill_content_fields["active_control_selection"] = {"status": "not-applicable"}
        with self.assertRaises(ValueError):
            trial.freeze_profile_arm_manifest(
                skill_content_fields, profile_components(b"built-in-profile-text")
            )

    def test_profile_arm_differs_from_paired_arm_only_in_profile_payload(self):
        trial = self.trial
        off, full = self.frozen_pair()
        self.assertEqual(
            [],
            trial.compare_profile_arm_to_off(
                off,
                full,
                profile_arm_template("profile-off", "off", []),
                profile_arm_template("profile-full", "full", ["profile_payload"]),
            ),
        )
        drifted_components = profile_components(b"candidate-profile-text")
        drifted_components["prompt_template"] = b"prompt-template-v2"
        drifted = trial.freeze_profile_arm_manifest(
            profile_arm_template("profile-full", "full", ["profile_payload"]),
            drifted_components,
        )
        errors = trial.compare_profile_arm_to_off(
            off,
            drifted,
            profile_arm_template("profile-off", "off", []),
            profile_arm_template("profile-full", "full", ["profile_payload"]),
        )
        self.assertIn("unallowlisted_diff:prompt_template", errors)
        identical = trial.freeze_profile_arm_manifest(
            profile_arm_template("profile-full", "full", ["profile_payload"]),
            profile_components(b"built-in-profile-text"),
        )
        self.assertIn(
            "allowlisted_diff_not_realized:profile_payload",
            trial.compare_profile_arm_to_off(
                off,
                identical,
                profile_arm_template("profile-off", "off", []),
                profile_arm_template("profile-full", "full", ["profile_payload"]),
            ),
        )

    def test_profile_registry_plan_freezes_the_paired_registry_once(self):
        trial = self.trial
        off, full = self.frozen_pair()
        registry = {"profile-off": off, "profile-full": full}
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "profile-arm-registry-plan.json"
            payload = trial.write_profile_arm_registry_plan(path, registry)
            self.assertEqual(
                "skill-effectiveness-profile-arm-registry-plan-v1",
                payload["artifact_contract"],
            )
            self.assertEqual(
                trial.profile_arm_registry_hash(registry),
                payload["arm_registry_hash"],
            )
            self.assertEqual(0o600, path.stat().st_mode & 0o777)
            # An identical rewrite is a safe resume; a different registry at the
            # same path must never replace frozen evidence.
            self.assertEqual(
                payload, trial.write_profile_arm_registry_plan(path, registry)
            )
            self.assertEqual(
                payload, trial.load_profile_arm_registry_plan(path, registry)
            )
            replaced = dict(registry)
            replaced["profile-full"] = trial.freeze_profile_arm_manifest(
                profile_arm_template("profile-full", "full", ["profile_payload"]),
                profile_components(b"another-candidate"),
            )
            with self.assertRaises(ValueError):
                trial.write_profile_arm_registry_plan(path, replaced)
            with self.assertRaises(ValueError):
                trial.load_profile_arm_registry_plan(path, replaced)
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "plan.json"
            with self.assertRaises(ValueError):
                trial.write_profile_arm_registry_plan(path, {"profile-off": off})
            mixed = {
                "profile-off": off,
                "S1": trial.freeze_arm_manifest(
                    arm_template("S1", "full", ["ccl_layer"]),
                    common_components(b"bundle"),
                ),
            }
            with self.assertRaises(ValueError):
                trial.write_profile_arm_registry_plan(path, mixed)
            second_off = trial.freeze_profile_arm_manifest(
                profile_arm_template("profile-off-2", "off", []),
                profile_components(b"another-built-in"),
            )
            with self.assertRaises(ValueError):
                trial.write_profile_arm_registry_plan(
                    path,
                    {"profile-off": off, "profile-full": full, "profile-off-2": second_off},
                )

    def advisory_inputs(self, waived=None, tier=None):
        trial = self.trial
        config = json.loads(PILOT_GATES_PATH.read_text(encoding="utf-8"))
        if tier is not None:
            config = dict(
                config,
                evidence_tier={
                    "schema_version": 1,
                    "requested_tier": tier,
                    "waived_items": (
                        list(trial.ADVISORY_WAIVABLE_ITEMS) if waived is None else waived
                    ),
                },
            )
        off, full = self.frozen_pair()
        manifests = {"profile-off": off, "profile-full": full}
        tasks = {"t1": "review", "t2": "diagnosis"}
        rows = expected_trial_rows(trial, tasks, manifests)
        records = [advisory_record(row, tasks[row["task_id"]]) for row in rows]
        return config, tasks, manifests, rows, records

    def evaluate_bundle(self, config, tasks, manifests, rows, records):
        trial = self.trial
        calibration, _ = raw_calibration(trial, families=("codex",))
        with tempfile.TemporaryDirectory() as directory:
            calibration_result_path = write_sealed_calibration_result(
                trial, Path(directory) / "calibration", calibration, config
            )
            bundle_root = Path(directory) / "bundle"
            trial.write_pilot_evidence_bundle(
                bundle_root,
                records,
                calibration_result_path,
                config,
                tasks,
                manifests,
                rows,
            )
            return trial.evaluate_pilot_gate_from_artifacts(
                bundle_root, config, tasks, manifests, rows
            )

    def test_advisory_tier_passes_and_enumerates_every_waived_item(self):
        result = self.evaluate_bundle(*self.advisory_inputs())
        self.assertEqual("pass", result["status"], result["failures"])
        tier = result["evidence_tier"]
        self.assertEqual("advisory-paired", tier["requested_tier"])
        self.assertEqual("advisory-paired", tier["verdict_tier"])
        self.assertEqual(
            sorted(self.trial.ADVISORY_WAIVABLE_ITEMS),
            tier["coverage_limitations"],
        )
        self.assertEqual("paired-profile", tier["registry_schema"])

    def test_observed_isolation_breach_fails_at_the_advisory_tier(self):
        config, tasks, manifests, rows, records = self.advisory_inputs()
        breached = [dict(record) for record in records]
        breached[0]["access_audit_ok"] = False
        breached[1]["memory_isolation_ok"] = False
        result = self.evaluate_bundle(config, tasks, manifests, rows, breached)
        self.assertEqual("fail", result["status"])
        self.assertIn("trial_file_isolation", result["failures"])
        self.assertIn("cross_trial_memory_isolation", result["failures"])
        self.assertIsNone(result["evidence_tier"]["verdict_tier"])

    def test_causal_request_without_core_evidence_never_passes(self):
        trial = self.trial
        config, tasks, _, _, _ = self.advisory_inputs(waived=[], tier="causal")
        manifests = {
            "S0": trial.freeze_arm_manifest(
                arm_template("S0", "off", []), common_components(b"")
            ),
            "S1": trial.freeze_arm_manifest(
                arm_template("S1", "oracle", ["ccl_layer"]),
                common_components(b"frozen-owner-bundle"),
            ),
            "S2": trial.freeze_arm_manifest(
                arm_template("S2", "full", ["ccl_layer"]),
                common_components(b"frozen-full-bundle"),
            ),
        }
        rows = expected_trial_rows(trial, tasks, manifests)
        records = []
        for row in rows:
            record = passing_record(row, tasks[row["task_id"]])
            record["access_audit_ok"] = None
            record["memory_isolation_ok"] = None
            records.append(record)
        result = self.evaluate_bundle(config, tasks, manifests, rows, records)
        self.assertEqual("fail", result["status"])
        self.assertIn("causal_core_unavailable", result["failures"])
        self.assertIsNone(result["evidence_tier"]["verdict_tier"])
        with self.assertRaises(ValueError):
            self.trial.evidence_tier_declaration(
                dict(
                    config,
                    evidence_tier={
                        "schema_version": 1,
                        "requested_tier": "causal",
                        "waived_items": ["mount_evidence"],
                    },
                )
            )
        with self.assertRaises(ValueError):
            self.trial.evidence_tier_declaration(
                dict(
                    config,
                    evidence_tier={
                        "schema_version": 1,
                        "requested_tier": "replicated-advisory",
                        "waived_items": [],
                    },
                )
            )

    def test_synthetic_run_satisfies_neither_tier(self):
        config, tasks, manifests, rows, records = self.advisory_inputs()
        calibration = {"status": "not_evaluated_synthetic"}
        result = self.trial.evaluate_pilot_gate(
            records, calibration, config, tasks, manifests, rows, synthetic=True
        )
        self.assertEqual("not_evaluated_synthetic", result["status"])
        self.assertIsNone(result["evidence_tier"]["verdict_tier"])
        self.assertEqual(
            "synthetic_not_a_tier", result["evidence_tier"]["tier_status"]
        )

    def test_advisory_tier_requires_the_paired_profile_registry(self):
        trial = self.trial
        config, tasks, _, _, _ = self.advisory_inputs()
        skill_manifests = {
            "S0": trial.freeze_arm_manifest(
                arm_template("S0", "off", []), common_components(b"")
            ),
            "S2": trial.freeze_arm_manifest(
                arm_template("S2", "full", ["ccl_layer"]),
                common_components(b"frozen-full-bundle"),
            ),
        }
        rows = expected_trial_rows(trial, tasks, skill_manifests)
        records = [passing_record(row, tasks[row["task_id"]]) for row in rows]
        with self.assertRaises(ValueError):
            trial.evaluate_pilot_gate(
                records,
                raw_calibration(trial, families=("codex",))[0],
                config,
                tasks,
                skill_manifests,
                rows,
                synthetic=True,
            )

    def test_advisory_tier_requires_a_fresh_session_per_sample(self):
        config, tasks, manifests, rows, _ = self.advisory_inputs()
        shared_session = rows[0]["runtime"]["session_id"]
        reused_rows = [rows[0]] + [
            rebind_row_session(self.trial, row, shared_session) for row in rows[1:]
        ]
        reused_records = [
            advisory_record(row, tasks[row["task_id"]]) for row in reused_rows
        ]
        result = self.evaluate_bundle(
            config, tasks, manifests, reused_rows, reused_records
        )
        self.assertEqual("fail", result["status"])
        self.assertIn("advisory_fresh_session_per_sample", result["failures"])


class SkillEventsV2FixtureTest(unittest.TestCase):
    """The v2 transcript known answers `agent-quality` pins in Slice 2."""

    @classmethod
    def setUpClass(cls):
        cls.active_control = load_active_control_module()
        cls.fixture = json.loads(
            (EVAL_DIR / "skill-event-fixtures-v2.json").read_text(encoding="utf-8")
        )

    def transcript_tool_uses(self, case):
        """Collect the sanitized tool topology one transcript actually carries.

        Each registered driver records invocations differently, so the checker
        dispatches on the driver instead of assuming one shape.  It returns
        `(skill_calls, task_seen)` where a skill call is normalized to
        `(tool_use_id, skill, succeeded)`.
        """

        driver = case["driver"]
        if driver == "claude-code":
            calls, results, task_seen = [], {}, False
            for row in case["transcript"]:
                content = (row.get("message") or {}).get("content")
                if not isinstance(content, list):
                    continue
                for block in content:
                    if block.get("type") == "tool_use":
                        if block.get("name") == "Task":
                            task_seen = True
                        elif block.get("name") == "Skill" and "id" in block:
                            calls.append(
                                (block["id"], block["input"]["skill"], None)
                            )
                    elif block.get("type") == "tool_result":
                        results[block.get("tool_use_id")] = not block.get(
                            "is_error", False
                        )
            return (
                [
                    (call_id, skill, results.get(call_id, False))
                    for call_id, skill, _ in calls
                ],
                task_seen,
            )
        if driver == "opencode":
            calls, task_seen = [], False
            for row in case["transcript"]:
                if row.get("type") != "tool":
                    continue
                if row.get("tool") == "task":
                    task_seen = True
                elif row.get("tool") == "skill":
                    state = row["state"]
                    calls.append(
                        (
                            row["callID"],
                            state["input"]["name"],
                            state["status"] == "completed",
                        )
                    )
            return calls, task_seen
        raise AssertionError(f"no transcript checker for driver {driver!r}")

    def test_fixture_declares_a_versioned_hand_authored_contract(self):
        self.assertEqual("skill-events-v2", self.fixture["event_contract_version"])
        self.assertIn("hand-authored", self.fixture["known_answer_source"])
        self.assertEqual(
            ["claude-code", "opencode"], self.fixture["registered_drivers"]
        )
        identifiers = [case["id"] for case in self.fixture["cases"]]
        self.assertEqual(len(identifiers), len(set(identifiers)))
        # Every registered driver needs its recorded shape note and at least one
        # known answer, so registering a driver cannot be a listing-only edit.
        notes = self.fixture["driver_notes"]
        for driver in self.fixture["registered_drivers"]:
            self.assertIn(driver, notes)
            self.assertTrue(
                any(
                    case["driver"] == driver and case.get("expected")
                    for case in self.fixture["cases"]
                ),
                driver,
            )
        self.assertTrue(notes["open_decisions"])

    def test_every_projection_reproduces_its_recorded_matched_call_verdict(self):
        evaluated = 0
        for case in self.fixture["cases"]:
            projection = case.get("expected")
            if projection is None:
                continue
            with self.subTest(case=case["id"]):
                self.assertIn(case["driver"], self.fixture["registered_drivers"])
                self.assertEqual(
                    {
                        "schema_version",
                        "event_contract_version",
                        "event_contract_status",
                        "skill_events_available",
                        "task_tool_events_available",
                        "first_task_tool_event_index",
                        "event_index_source",
                        "skills_invoked",
                    },
                    set(projection),
                )
                verdict = self.active_control._evaluate_matched_call_fixture(
                    projection, target_bundle_id=case["target_bundle_id"]
                )
                self.assertEqual(
                    case["expected_matched_call"]["decision"], verdict["decision"]
                )
                self.assertEqual(
                    case["expected_matched_call"]["reason_code"],
                    verdict["reason_code"],
                )
                evaluated += 1
        self.assertGreaterEqual(evaluated, 5)

    def test_projections_stay_consistent_with_their_transcripts(self):
        for case in self.fixture["cases"]:
            projection = case.get("expected")
            if projection is None:
                continue
            with self.subTest(case=case["id"]):
                calls, task_seen = self.transcript_tool_uses(case)
                self.assertTrue(
                    task_seen,
                    "a projection with a first task-tool index needs a task tool",
                )
                indexes = [row["event_index"] for row in projection["skills_invoked"]]
                self.assertEqual(len(indexes), len(set(indexes)))
                self.assertNotIn(projection["first_task_tool_event_index"], indexes)
                identifiers = [
                    row["tool_use_id"] for row in projection["skills_invoked"]
                ]
                if case.get("open_decision") == "tool_use_id_uniqueness_scope":
                    # This case exists precisely because a real driver repeats a
                    # literal id; the contract's own evaluator must reject it.
                    self.assertLess(len(set(identifiers)), len(identifiers))
                    self.assertEqual(
                        "event_contract_unverifiable",
                        case["expected_matched_call"]["reason_code"],
                    )
                else:
                    self.assertEqual(len(identifiers), len(set(identifiers)))
                for row in projection["skills_invoked"]:
                    match = [c for c in calls if c[0] == row["tool_use_id"]]
                    self.assertTrue(match, row["tool_use_id"])
                    skills = {c[1] for c in match}
                    self.assertIn(row["skill"], skills)
                    succeeded = [c[2] for c in match if c[1] == row["skill"]]
                    self.assertTrue(succeeded)
                    self.assertEqual(succeeded[0], row["matching_tool_result"])
                    # `completed` means one call plus its matching non-error
                    # outcome; it may never outrun that evidence.
                    self.assertEqual(succeeded[0], row["completed"])
                if projection["event_contract_status"] == "degraded":
                    self.assertEqual([], projection["skills_invoked"])
                    self.assertEqual(
                        "invocation_unverifiable", case["degradation"]["status"]
                    )

    def test_unregistered_driver_shapes_degrade_instead_of_passing(self):
        degraded = [case for case in self.fixture["cases"] if "degradation" in case]
        self.assertGreaterEqual(len(degraded), 3)
        for case in degraded:
            with self.subTest(case=case["id"]):
                self.assertEqual(
                    "invocation_unverifiable", case["degradation"]["status"]
                )
                self.assertIn(
                    case["degradation"]["reason"],
                    {"driver_shape_unregistered", "missing_invocation_field"},
                )
                if case["degradation"]["reason"] == "driver_shape_unregistered":
                    self.assertNotIn(
                        case["driver"], self.fixture["registered_drivers"]
                    )
                    self.assertNotIn("expected", case)


if __name__ == "__main__":
    unittest.main()
