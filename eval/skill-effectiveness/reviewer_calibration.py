#!/usr/bin/env python3
"""Collect raw live-reviewer calibration judgments for the advisory evaluator.

This module measures reviewer consistency and known-answer accuracy. It does not
run a skill-effectiveness trial, promote a candidate, or authorize repository
actions. Only committed generic calibration cases are sent to the provider; the
known-answer verdicts are withheld from every provider prompt.
"""

from __future__ import annotations

import json
import os
import re
import signal
from pathlib import Path
from typing import Any, Mapping, Sequence

import claude_provider
import kimi_provider
import opencode_provider
import provider_probe
import trial


RESULT_CONTRACT = "skill-effectiveness-reviewer-calibration-result-v1"
CODEX_RUNNER_CONTRACT = "codex-cli-reviewer-calibration-v1"
CLAUDE_RUNNER_CONTRACT = "claude-cli-reviewer-calibration-v1"
KIMI_RUNNER_CONTRACT = "kimi-cli-reviewer-calibration-v1"
OPENCODE_RUNNER_CONTRACT = "opencode-cli-reviewer-calibration-v1"
SAFE_ID_PATTERN = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$")
VERDICTS = ("A win", "tie", "B win")
CASE_FIELDS = {"case_id", "task", "rubric", "candidate_a", "candidate_b"}
MAX_CASE_TEXT_BYTES = 16 * 1024


def _load_json(path: Path) -> Mapping[str, Any]:
    with path.open(encoding="utf-8") as stream:
        payload = json.load(stream)
    if not isinstance(payload, Mapping):
        raise ValueError(f"fixture must contain a JSON object: {path.name}")
    return payload


def _safe_id(value: Any, field: str) -> str:
    if not isinstance(value, str) or SAFE_ID_PATTERN.fullmatch(value) is None:
        raise ValueError(f"{field} is invalid")
    return value


def _safe_text(value: Any, field: str) -> str:
    if not isinstance(value, str) or not value.strip():
        raise ValueError(f"{field} must be non-empty text")
    if len(value.encode("utf-8")) > MAX_CASE_TEXT_BYTES:
        raise ValueError(f"{field} is too large")
    return value


def _load_frozen_inputs(
    known_answers_path: Path, cases_path: Path, pilot_gates_path: Path
) -> tuple[list[dict[str, str]], list[dict[str, str]], Mapping[str, Any], str, str]:
    known_fixture = _load_json(known_answers_path)
    if set(known_fixture) != {"schema_version", "known_answers"}:
        raise ValueError("known-answer fixture field set is invalid")
    if known_fixture.get("schema_version") != 1:
        raise ValueError("known-answer fixture schema version is invalid")
    known_rows = known_fixture.get("known_answers")
    if not isinstance(known_rows, Sequence) or isinstance(known_rows, (str, bytes)):
        raise ValueError("known-answer rows must be a list")
    known_answers: list[dict[str, str]] = []
    truth_ids: set[str] = set()
    for row in known_rows:
        if not isinstance(row, Mapping) or set(row) != {
            "case_id",
            "expected_verdict",
        }:
            raise ValueError("known-answer row field set is invalid")
        case_id = _safe_id(row.get("case_id"), "known-answer case_id")
        verdict = row.get("expected_verdict")
        if case_id in truth_ids:
            raise ValueError("known-answer case_id is duplicated")
        if verdict not in VERDICTS:
            raise ValueError("known-answer verdict is invalid")
        truth_ids.add(case_id)
        known_answers.append({"case_id": case_id, "expected_verdict": verdict})
    if not known_answers:
        raise ValueError("known-answer fixture is empty")
    known_answer_hash = trial.canonical_hash(known_answers)

    case_fixture = _load_json(cases_path)
    if set(case_fixture) != {
        "schema_version",
        "known_answer_fixture_hash",
        "cases",
    }:
        raise ValueError("calibration case fixture field set is invalid")
    if case_fixture.get("schema_version") != 1:
        raise ValueError("calibration case fixture schema version is invalid")
    if case_fixture.get("known_answer_fixture_hash") != known_answer_hash:
        raise ValueError("calibration cases are not bound to the known answers")
    case_rows = case_fixture.get("cases")
    if not isinstance(case_rows, Sequence) or isinstance(case_rows, (str, bytes)):
        raise ValueError("calibration cases must be a list")
    cases: list[dict[str, str]] = []
    case_ids: set[str] = set()
    for row in case_rows:
        if not isinstance(row, Mapping) or set(row) != CASE_FIELDS:
            raise ValueError("calibration case field set is invalid")
        case_id = _safe_id(row.get("case_id"), "calibration case_id")
        if case_id in case_ids:
            raise ValueError("calibration case_id is duplicated")
        case_ids.add(case_id)
        cases.append(
            {
                "case_id": case_id,
                "task": _safe_text(row.get("task"), "case task"),
                "rubric": _safe_text(row.get("rubric"), "case rubric"),
                "candidate_a": _safe_text(row.get("candidate_a"), "candidate_a"),
                "candidate_b": _safe_text(row.get("candidate_b"), "candidate_b"),
            }
        )
    if case_ids != truth_ids:
        raise ValueError("calibration case set does not match the known answers")
    case_fixture_hash = trial.canonical_hash(
        {
            "schema_version": 1,
            "known_answer_fixture_hash": known_answer_hash,
            "cases": cases,
        }
    )

    pilot_gates = _load_json(pilot_gates_path)
    if pilot_gates.get("reviewer_calibration_fixture_hash") != known_answer_hash:
        raise ValueError("pilot gates are not bound to the known answers")
    if pilot_gates.get("reviewer_calibration_case_fixture_hash") != case_fixture_hash:
        raise ValueError("pilot gates are not bound to the calibration cases")
    return known_answers, cases, pilot_gates, known_answer_hash, case_fixture_hash


def _response_schema(case_ids: Sequence[str]) -> dict[str, Any]:
    return {
        "type": "object",
        "additionalProperties": False,
        "required": ["protocol_version", "judgments"],
        "properties": {
            "protocol_version": {"type": "integer", "enum": [1]},
            "judgments": {
                "type": "array",
                "minItems": len(case_ids),
                "maxItems": len(case_ids),
                "items": {
                    "type": "object",
                    "additionalProperties": False,
                    "required": ["case_id", "verdict"],
                    "properties": {
                        "case_id": {"type": "string", "enum": list(case_ids)},
                        "verdict": {"type": "string", "enum": list(VERDICTS)},
                    },
                },
            },
        },
    }


def _validate_judgments(
    payload: Mapping[str, Any], expected_case_ids: Sequence[str]
) -> list[dict[str, str]]:
    if set(payload) != {"protocol_version", "judgments"}:
        raise ValueError("reviewer response field set is invalid")
    if payload.get("protocol_version") != 1:
        raise ValueError("reviewer response protocol version is invalid")
    rows = payload.get("judgments")
    if not isinstance(rows, Sequence) or isinstance(rows, (str, bytes)):
        raise ValueError("reviewer judgments must be a list")
    expected = set(expected_case_ids)
    judgments: dict[str, str] = {}
    for row in rows:
        if not isinstance(row, Mapping) or set(row) != {"case_id", "verdict"}:
            raise ValueError("reviewer judgment field set is invalid")
        case_id = row.get("case_id")
        verdict = row.get("verdict")
        if case_id not in expected:
            raise ValueError("reviewer judgment case_id is invalid")
        if case_id in judgments:
            raise ValueError("reviewer judgment case_id is duplicated")
        if verdict not in VERDICTS:
            raise ValueError("reviewer judgment verdict is invalid")
        judgments[case_id] = verdict
    if set(judgments) != expected:
        raise ValueError("reviewer judgment case set is incomplete")
    return [
        {"case_id": case_id, "verdict": judgments[case_id]}
        for case_id in expected_case_ids
    ]


def _prompt(cases: Sequence[Mapping[str, str]]) -> str:
    request = {
        "protocol_version": 1,
        "instructions": (
            "Judge each A/B pair only against its task and rubric. Return A win, "
            "tie, or B win for every case. Do not inspect files or invoke "
            "filesystem, network, shell, or other external tools."
        ),
        "cases": list(cases),
    }
    return (
        "REVIEWER CALIBRATION. The expected verdicts are intentionally withheld. "
        "Return only the JSON object required by the response schema.\n"
        "CALIBRATION_INPUT="
        + json.dumps(request, sort_keys=True, separators=(",", ":"))
    )


def _publication_paths(output_root: Path) -> tuple[Path, Path, Path, Path]:
    report_path = output_root / "reviewer-calibration-result.json"
    evidence_path = output_root / "reviewer-calibration.json"
    staged_report_path = output_root / ".reviewer-calibration-result.pending.json"
    staged_evidence_path = output_root / ".reviewer-calibration.pending.json"
    return report_path, evidence_path, staged_report_path, staged_evidence_path


def _claim_output_root(output_root: Path) -> tuple[Path, Path, Path, Path]:
    trial.ensure_private_directory(output_root)
    lock_path = output_root / ".reviewer-calibration.lock"
    try:
        lock_descriptor = os.open(
            lock_path,
            os.O_WRONLY | os.O_CREAT | os.O_EXCL | getattr(os, "O_NOFOLLOW", 0),
            0o600,
        )
    except FileExistsError as exc:
        raise ValueError("reviewer calibration output root is already claimed") from exc
    os.close(lock_descriptor)
    paths = _publication_paths(output_root)
    for path in paths:
        if path.exists() or path.is_symlink():
            raise ValueError(f"reviewer calibration output already exists: {path.name}")
    return paths


def _build_calibration_documents(
    *,
    known_answers: list[dict[str, str]],
    known_hash: str,
    case_hash: str,
    pilot_gates: Mapping[str, Any],
    family: str,
    runs: list[list[dict[str, str]]],
    provider: str,
    cli_version: str,
    executable_hash: str,
    environment: Mapping[str, str],
    model: str,
    provider_binding: Mapping[str, Any] | None,
    runner_contract: str,
    runner_hash: str,
    requested_session_mode: str,
    tool_access: str,
    evidence_name: str,
) -> tuple[dict[str, Any], dict[str, Any]]:
    calibration = {
        "status": "evaluated",
        "known_answers": known_answers,
        "known_answer_fixture_hash": known_hash,
        "reviewers": [{"family": family, "runs": runs}],
    }
    evaluation = trial.evaluate_reviewer_calibration(calibration, pilot_gates)
    report = {
        "schema_version": 1,
        "artifact_contract": RESULT_CONTRACT,
        "execution_status": "completed",
        "calibration_status": evaluation["status"],
        "provider": provider,
        "provider_cli_version": cli_version,
        "provider_executable_hash": executable_hash,
        "provider_environment_keys": sorted(environment),
        "model": model,
        "reviewer_family": family,
        "repeat_count": len(runs),
        "case_count": len(known_answers),
        "known_answer_fixture_hash": known_hash,
        "case_fixture_hash": case_hash,
        "pilot_gates_hash": trial.canonical_hash(pilot_gates),
        "runner_contract": runner_contract,
        "runner_hash": runner_hash,
        "requested_session_mode": requested_session_mode,
        "tool_access": tool_access,
        "calibration_evidence": evidence_name,
        "calibration_evidence_hash": trial.canonical_hash(calibration),
        "calibration_evaluation": evaluation,
        "calibration_evaluation_hash": trial.canonical_hash(evaluation),
        "conclusion_boundary": "reviewer_calibration_only_not_skill_effectiveness",
        "enforcement": "advisory",
    }
    if provider_binding is not None:
        report["provider_binding"] = dict(provider_binding)
        report["provider_binding_hash"] = trial.canonical_hash(provider_binding)
    return report, calibration


def _persist_calibration(
    *,
    known_answers: list[dict[str, str]],
    known_hash: str,
    case_hash: str,
    pilot_gates: Mapping[str, Any],
    family: str,
    runs: list[list[dict[str, str]]],
    provider: str,
    cli_version: str,
    executable_hash: str,
    environment: Mapping[str, str],
    model: str,
    provider_binding: Mapping[str, Any] | None,
    runner_contract: str,
    runner_hash: str,
    requested_session_mode: str,
    tool_access: str,
    report_path: Path,
    evidence_path: Path,
    staged_report_path: Path,
    staged_evidence_path: Path,
) -> dict[str, Any]:
    report, calibration = _build_calibration_documents(
        known_answers=known_answers,
        known_hash=known_hash,
        case_hash=case_hash,
        pilot_gates=pilot_gates,
        family=family,
        runs=runs,
        provider=provider,
        cli_version=cli_version,
        executable_hash=executable_hash,
        environment=environment,
        model=model,
        provider_binding=provider_binding,
        runner_contract=runner_contract,
        runner_hash=runner_hash,
        requested_session_mode=requested_session_mode,
        tool_access=tool_access,
        evidence_name=evidence_path.name,
    )
    try:
        trial.write_json_atomic(staged_evidence_path, calibration)
        if trial.load_private_json(staged_evidence_path) != calibration:
            raise ValueError("reviewer calibration evidence read-back mismatch")
        trial.write_json_atomic(staged_report_path, report)
        if trial.load_private_json(staged_report_path) != report:
            raise ValueError("reviewer calibration report read-back mismatch")
        publication_signals = set(provider_probe.PROVIDER_TERMINATION_SIGNALS)
        previous_mask = signal.pthread_sigmask(signal.SIG_BLOCK, publication_signals)
        pending_signal: signal.Signals | None = None
        try:
            os.replace(staged_evidence_path, evidence_path)
            os.replace(staged_report_path, report_path)
        finally:
            pending = signal.sigpending().intersection(publication_signals)
            if pending:
                pending_signal = min(pending, key=int)
                for signum in sorted(pending, key=int):
                    signal.sigwait({signum})
            signal.pthread_sigmask(signal.SIG_SETMASK, previous_mask)
            if pending_signal is not None:
                raise SystemExit(128 + int(pending_signal))
    except BaseException:
        cleanup_error: OSError | None = None
        for path in (
            staged_evidence_path,
            staged_report_path,
            evidence_path,
            report_path,
        ):
            try:
                path.unlink(missing_ok=True)
            except OSError as exc:
                cleanup_error = cleanup_error or exc
        if cleanup_error is not None:
            raise ValueError(
                "reviewer calibration failed-publication cleanup failed"
            ) from cleanup_error
        raise
    return report


def run_codex_reviewer_calibration(
    *,
    codex_path: Path,
    model: str,
    reviewer_family: str,
    repeats: int,
    output_root: Path,
    timeout_seconds: int,
    known_answers_path: Path,
    cases_path: Path,
    pilot_gates_path: Path,
) -> dict[str, Any]:
    """Collect repeated raw judgments and persist their recomputed metrics."""

    family = _safe_id(reviewer_family, "reviewer_family")
    model = provider_probe._validate_model(model)
    if isinstance(repeats, bool) or not 2 <= repeats <= 5:
        raise ValueError("repeats must be between 2 and 5")
    if isinstance(timeout_seconds, bool) or not 1 <= timeout_seconds <= 600:
        raise ValueError("timeout_seconds must be between 1 and 600")
    known_answers, cases, pilot_gates, known_hash, case_hash = _load_frozen_inputs(
        known_answers_path, cases_path, pilot_gates_path
    )

    (
        report_path,
        evidence_path,
        staged_report_path,
        staged_evidence_path,
    ) = _claim_output_root(output_root)

    executable = provider_probe._resolve_codex(codex_path)
    environment = provider_probe._provider_environment()
    executable_hash = provider_probe._hash_file(executable)
    cli_version = provider_probe._codex_version(
        executable, output_root, timeout_seconds, environment
    )
    case_ids = [row["case_id"] for row in cases]
    schema = _response_schema(case_ids)
    prompt = _prompt(cases)
    runs: list[list[dict[str, str]]] = []
    for _ in range(repeats):
        payload = provider_probe.invoke_codex_json_readonly(
            executable,
            model=model,
            prompt=prompt,
            schema=schema,
            timeout_seconds=timeout_seconds,
            environment=environment,
            session_prefix="codex-reviewer-calibration",
        )
        runs.append(_validate_judgments(payload, case_ids))

    runner_hash = trial.canonical_hash(
        {
            "runner_contract": CODEX_RUNNER_CONTRACT,
            "module_hash": provider_probe._hash_file(Path(__file__).resolve()),
            "provider_adapter_hash": provider_probe._hash_file(
                Path(provider_probe.__file__).resolve()
            ),
        }
    )
    return _persist_calibration(
        known_answers=known_answers,
        known_hash=known_hash,
        case_hash=case_hash,
        pilot_gates=pilot_gates,
        family=family,
        runs=runs,
        provider="codex",
        cli_version=cli_version,
        executable_hash=executable_hash,
        environment=environment,
        model=model,
        provider_binding=None,
        runner_contract=CODEX_RUNNER_CONTRACT,
        runner_hash=runner_hash,
        requested_session_mode="ephemeral",
        tool_access="rejected",
        report_path=report_path,
        evidence_path=evidence_path,
        staged_report_path=staged_report_path,
        staged_evidence_path=staged_evidence_path,
    )


def run_claude_reviewer_calibration(
    *,
    claude_path: Path,
    runtime_validator_path: Path,
    model: str,
    reviewer_family: str,
    repeats: int,
    output_root: Path,
    timeout_seconds: int,
    known_answers_path: Path,
    cases_path: Path,
    pilot_gates_path: Path,
) -> dict[str, Any]:
    """Collect repeated judgments through an exact-model, no-tool Claude path."""

    family = _safe_id(reviewer_family, "reviewer_family")
    if family != "claude":
        raise ValueError("Claude reviewer_family must be the canonical claude family")
    model = provider_probe._validate_model(model)
    if isinstance(repeats, bool) or not 2 <= repeats <= 5:
        raise ValueError("repeats must be between 2 and 5")
    if isinstance(timeout_seconds, bool) or not 5 <= timeout_seconds <= 600:
        raise ValueError("timeout_seconds must be between 5 and 600 for Claude")
    known_answers, cases, pilot_gates, known_hash, case_hash = _load_frozen_inputs(
        known_answers_path, cases_path, pilot_gates_path
    )
    (
        report_path,
        evidence_path,
        staged_report_path,
        staged_evidence_path,
    ) = _claim_output_root(output_root)
    executable = claude_provider.resolve_executable(claude_path, "claude_path")
    runtime_validator = claude_provider.resolve_runtime_validator(
        runtime_validator_path
    )
    environment = claude_provider.provider_environment()
    executable_hash = provider_probe._hash_file(executable)
    cli_version = provider_probe._codex_version(
        executable, output_root, timeout_seconds, environment
    )
    case_ids = [row["case_id"] for row in cases]
    schema = _response_schema(case_ids)
    prompt = _prompt(cases)
    runs: list[list[dict[str, str]]] = []
    for _ in range(repeats):
        payload = claude_provider.invoke_json_no_tools(
            executable,
            model=model,
            prompt=prompt,
            schema=schema,
            timeout_seconds=timeout_seconds,
            environment=environment,
            runtime_validator=runtime_validator,
        )
        runs.append(_validate_judgments(payload, case_ids))
    runner_hash = trial.canonical_hash(
        {
            "runner_contract": CLAUDE_RUNNER_CONTRACT,
            "module_hash": provider_probe._hash_file(Path(__file__).resolve()),
            "provider_adapter_hash": provider_probe._hash_file(
                Path(claude_provider.__file__).resolve()
            ),
            "bounded_runner_hash": provider_probe._hash_file(
                Path(provider_probe.__file__).resolve()
            ),
            "runtime_validator_hash": provider_probe._hash_file(runtime_validator),
        }
    )
    return _persist_calibration(
        known_answers=known_answers,
        known_hash=known_hash,
        case_hash=case_hash,
        pilot_gates=pilot_gates,
        family=family,
        runs=runs,
        provider="claude",
        cli_version=cli_version,
        executable_hash=executable_hash,
        environment=environment,
        model=model,
        provider_binding=None,
        runner_contract=CLAUDE_RUNNER_CONTRACT,
        runner_hash=runner_hash,
        requested_session_mode="no-session-persistence",
        tool_access="verified-none",
        report_path=report_path,
        evidence_path=evidence_path,
        staged_report_path=staged_report_path,
        staged_evidence_path=staged_evidence_path,
    )


def run_opencode_reviewer_calibration(
    *,
    opencode_path: Path,
    model: str,
    reviewer_family: str,
    repeats: int,
    output_root: Path,
    timeout_seconds: int,
    known_answers_path: Path,
    cases_path: Path,
    pilot_gates_path: Path,
) -> dict[str, Any]:
    """Collect repeated judgments from bound, tool-free OpenCode sessions."""

    family = _safe_id(reviewer_family, "reviewer_family")
    provider_id, _ = opencode_provider.validate_expected_model(model)
    if family != provider_id:
        raise ValueError(
            "OpenCode reviewer_family must match the expected providerID"
        )
    if isinstance(repeats, bool) or not 2 <= repeats <= 5:
        raise ValueError("repeats must be between 2 and 5")
    if isinstance(timeout_seconds, bool) or not 5 <= timeout_seconds <= 600:
        raise ValueError("timeout_seconds must be between 5 and 600 for OpenCode")
    known_answers, cases, pilot_gates, known_hash, case_hash = _load_frozen_inputs(
        known_answers_path, cases_path, pilot_gates_path
    )
    (
        report_path,
        evidence_path,
        staged_report_path,
        staged_evidence_path,
    ) = _claim_output_root(output_root)
    executable = opencode_provider.resolve_executable(opencode_path)
    environment = opencode_provider.provider_environment()
    executable_hash = provider_probe._hash_file(executable)
    cli_version = provider_probe._codex_version(
        executable, output_root, timeout_seconds, environment
    )
    case_ids = [row["case_id"] for row in cases]
    response_schema = _response_schema(case_ids)
    prompt_prefix, calibration_input = _prompt(cases).split(
        "\nCALIBRATION_INPUT=", 1
    )
    prompt = (
        prompt_prefix
        + "\nRESPONSE_SCHEMA="
        + json.dumps(response_schema, sort_keys=True, separators=(",", ":"))
        + "\nCALIBRATION_INPUT="
        + calibration_input
    )
    runs: list[list[dict[str, str]]] = []
    for _ in range(repeats):
        payload = opencode_provider.invoke_json_no_tools(
            executable,
            model=model,
            prompt=prompt,
            timeout_seconds=timeout_seconds,
            environment=environment,
        )
        runs.append(_validate_judgments(payload, case_ids))
    runner_hash = trial.canonical_hash(
        {
            "runner_contract": OPENCODE_RUNNER_CONTRACT,
            "module_hash": provider_probe._hash_file(Path(__file__).resolve()),
            "provider_adapter_hash": provider_probe._hash_file(
                Path(opencode_provider.__file__).resolve()
            ),
            "bounded_runner_hash": provider_probe._hash_file(
                Path(provider_probe.__file__).resolve()
            ),
        }
    )
    return _persist_calibration(
        known_answers=known_answers,
        known_hash=known_hash,
        case_hash=case_hash,
        pilot_gates=pilot_gates,
        family=family,
        runs=runs,
        provider="opencode",
        cli_version=cli_version,
        executable_hash=executable_hash,
        environment=environment,
        model=model,
        provider_binding=None,
        runner_contract=OPENCODE_RUNNER_CONTRACT,
        runner_hash=runner_hash,
        requested_session_mode="private-xdg-explicit-model-export",
        tool_access="agent-disabled-observed-none",
        report_path=report_path,
        evidence_path=evidence_path,
        staged_report_path=staged_report_path,
        staged_evidence_path=staged_evidence_path,
    )


def run_kimi_reviewer_calibration(
    *,
    kimi_path: Path,
    model: str,
    reviewer_family: str,
    repeats: int,
    output_root: Path,
    timeout_seconds: int,
    known_answers_path: Path,
    cases_path: Path,
    pilot_gates_path: Path,
) -> dict[str, Any]:
    """Collect repeated judgments from private, stream-audited Kimi sessions."""

    family = _safe_id(reviewer_family, "reviewer_family")
    if family != "moonshot":
        raise ValueError("Kimi reviewer_family must be the canonical moonshot family")
    model = provider_probe._validate_model(model)
    if isinstance(repeats, bool) or not 2 <= repeats <= 5:
        raise ValueError("repeats must be between 2 and 5")
    if isinstance(timeout_seconds, bool) or not 5 <= timeout_seconds <= 600:
        raise ValueError("timeout_seconds must be between 5 and 600 for Kimi")
    known_answers, cases, pilot_gates, known_hash, case_hash = _load_frozen_inputs(
        known_answers_path, cases_path, pilot_gates_path
    )
    (
        report_path,
        evidence_path,
        staged_report_path,
        staged_evidence_path,
    ) = _claim_output_root(output_root)
    executable = kimi_provider.resolve_executable(kimi_path)
    environment = kimi_provider.provider_environment()
    source_home, selected_config, provider_binding = kimi_provider.prepare_runtime(
        model
    )
    provider_binding = {
        **provider_binding,
        "selected_config_hash": trial.canonical_hash(selected_config),
    }
    executable_hash = provider_probe._hash_file(executable)
    cli_version = provider_probe._codex_version(
        executable, output_root, timeout_seconds, environment
    )
    case_ids = [row["case_id"] for row in cases]
    response_schema = _response_schema(case_ids)
    prompt_prefix, calibration_input = _prompt(cases).split(
        "\nCALIBRATION_INPUT=", 1
    )
    prompt = (
        prompt_prefix
        + "\nRESPONSE_SCHEMA="
        + json.dumps(response_schema, sort_keys=True, separators=(",", ":"))
        + "\nCALIBRATION_INPUT="
        + calibration_input
    )
    runs: list[list[dict[str, str]]] = []
    session_ids: set[str] = set()
    for _ in range(repeats):
        payload, session_id = kimi_provider.invoke_json_no_tools(
            executable,
            model=model,
            prompt=prompt,
            timeout_seconds=timeout_seconds,
            environment=environment,
            source_home=source_home,
            selected_config=selected_config,
        )
        if session_id in session_ids:
            raise ValueError("Kimi repeats must use distinct session ids")
        session_ids.add(session_id)
        runs.append(_validate_judgments(payload, case_ids))
    runner_hash = trial.canonical_hash(
        {
            "runner_contract": KIMI_RUNNER_CONTRACT,
            "module_hash": provider_probe._hash_file(Path(__file__).resolve()),
            "provider_adapter_hash": provider_probe._hash_file(
                Path(kimi_provider.__file__).resolve()
            ),
            "bounded_runner_hash": provider_probe._hash_file(
                Path(provider_probe.__file__).resolve()
            ),
            "provider_binding_hash": trial.canonical_hash(provider_binding),
        }
    )
    return _persist_calibration(
        known_answers=known_answers,
        known_hash=known_hash,
        case_hash=case_hash,
        pilot_gates=pilot_gates,
        family=family,
        runs=runs,
        provider="kimi",
        cli_version=cli_version,
        executable_hash=executable_hash,
        environment=environment,
        model=model,
        provider_binding=provider_binding,
        runner_contract=KIMI_RUNNER_CONTRACT,
        runner_hash=runner_hash,
        requested_session_mode="private-kimi-home-explicit-model-stream",
        tool_access="config-denied-stream-audited-detection-only",
        report_path=report_path,
        evidence_path=evidence_path,
        staged_report_path=staged_report_path,
        staged_evidence_path=staged_evidence_path,
    )
