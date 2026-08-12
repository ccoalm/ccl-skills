#!/usr/bin/env python3
"""Single-sample reviewer-calibration machine protocol.

`sample` starts exactly one explicitly configured, read-only Codex model
call. `finalize` never starts a model; it validates the exact frozen sample set
and publishes the existing reviewer-calibration evidence/result pair.
"""

from __future__ import annotations

import contextlib
import errno
import fcntl
import hashlib
import json
import os
import re
import secrets
import stat
import sys
from pathlib import Path
from typing import Any, Mapping, Sequence

import provider_probe
import reviewer_calibration
import trial


HERE = Path(__file__).resolve().parent
SOURCE_CHECKOUT = HERE.parents[1]
REQUEST_SCHEMA = "skill-effectiveness.reviewer-calibration.request.v1"
RESPONSE_SCHEMA = "skill-effectiveness.reviewer-calibration.response.v1"
PROTOCOL_REVISION = "skill-effectiveness.reviewer-calibration.v1"
SAMPLE_CONTRACT = "skill-effectiveness-reviewer-calibration-sample-v1"
SAMPLE_LEDGER_CONTRACT = (
    "skill-effectiveness-reviewer-calibration-sample-ledger-entry-v2"
)
FINALIZATION_CONTRACT = (
    "skill-effectiveness-reviewer-calibration-finalization-intent-v1"
)
RUNNER_CONTRACT = "codex-cli-reviewer-calibration-single-sample-v1"
SUPPORTED_ACTIONS = ("probe", "sample", "finalize")
SUPPORTED_PROVIDERS = ("codex",)
# The closed reason-code set a consumer may pin. It is published by `probe`,
# mirrored by the response schema, and bound to the raise sites by a
# conformance test, so a new code cannot ship without appearing here.
REASON_CODES = (
    "artifact_root_mismatch",
    "artifact_root_quarantined",
    "finalization_recovery_required",
    "finalize_already_started",
    "fixture_drift",
    "fixture_invalid",
    "internal_error",
    "invalid_artifact_root",
    "invalid_cost_policy",
    "invalid_executable",
    "invalid_field",
    "invalid_json",
    "invalid_payload",
    "invalid_provider_configuration",
    "invalid_request",
    "invalid_request_id",
    "invalid_sample_set",
    "invalid_timeout",
    "model_call_unresolved",
    "protocol_mismatch",
    "provider_identity_unavailable",
    "request_too_large",
    "runtime_drift",
    "runtime_manifest_unavailable",
    "sample_already_exists",
    "sample_binding_mismatch",
    "sample_finality_unknown",
    "sample_intent_mismatch",
    "sample_invalid",
    "sample_lock_unavailable",
    "sample_publication_failed",
    "sample_set_mismatch",
    "unsupported_action",
    "unsupported_provider",
)
SAFE_REQUEST_ID = re.compile(r"^[A-Za-z0-9._-]{1,128}$")
MAX_REQUEST_BYTES = 1_048_576
EXIT_OK = 0
EXIT_INVALID = 2
EXIT_BLOCKED = 3
EXIT_INTERNAL = 4
MANIFEST_PATHS = (
    "claude_provider.py",
    "fixtures/reviewer-calibration-cases.json",
    "fixtures/reviewer-calibration-known-answers.json",
    "kimi_provider.py",
    "opencode_provider.py",
    "pilot-gates.json",
    "protocol/reviewer-calibration-request-v1.schema.json",
    "protocol/reviewer-calibration-response-v1.schema.json",
    "provider_probe.py",
    "reviewer_calibration.py",
    "reviewer_calibration_protocol.py",
    "trial.py",
)
SAMPLE_FIELDS = {
    "schema_version",
    "artifact_contract",
    "sample_id",
    "artifact_root_hash",
    "provider",
    "provider_cli_version",
    "provider_executable_hash",
    "provider_environment_keys",
    "model",
    "reviewer_family",
    "timeout_seconds",
    "max_model_calls",
    "runtime_manifest_hash",
    "known_answer_fixture_hash",
    "case_fixture_hash",
    "runner_contract",
    "runner_hash",
    "requested_session_mode",
    "tool_access",
    "judgments",
}
INTENT_FIELDS = {
    "schema_version",
    "sample_id",
    "artifact_root_hash",
    "provider",
    "provider_cli_version",
    "provider_executable_hash",
    "model",
    "reviewer_family",
    "timeout_seconds",
    "max_model_calls",
    "runtime_manifest_hash",
    "known_answer_fixture_hash",
    "case_fixture_hash",
    "runner_hash",
    "state",
    "sample_hash",
}
SAMPLE_LEDGER_FIELDS = {
    "schema_version",
    "artifact_contract",
    "sample_id",
    "artifact_root_hash",
    "state",
}


def _valid_completed_ledger(
    ledger: Any,
    *,
    sample_id: str,
) -> bool:
    """Only a stateful v2 ledger evidences that the model call started."""

    if not isinstance(ledger, Mapping):
        return False
    return (
        ledger.get("schema_version") == 1
        and ledger.get("sample_id") == sample_id
        and ledger.get("artifact_contract") == SAMPLE_LEDGER_CONTRACT
        and set(ledger) == SAMPLE_LEDGER_FIELDS
        and ledger.get("state") == "model_call_started"
    )


def _recoverable_orphan_ledger(
    *,
    artifact_root: Path,
    ledger_root: Path,
    sample_id: str,
    actual_ids: set[str],
    intent_ids: set[str],
    ledger_ids: set[str],
) -> bool:
    if (
        sample_id in actual_ids
        or actual_ids != intent_ids
        or ledger_ids != actual_ids | {sample_id}
    ):
        return False
    try:
        ledger = trial.load_private_json(ledger_root / f"{sample_id}.json")
    except (OSError, ValueError):
        return False
    return (
        isinstance(ledger, Mapping)
        and set(ledger) == SAMPLE_LEDGER_FIELDS
        and ledger.get("schema_version") == 1
        and ledger.get("artifact_contract") == SAMPLE_LEDGER_CONTRACT
        and ledger.get("sample_id") == sample_id
        and ledger.get("artifact_root_hash") == _artifact_root_hash(artifact_root)
        and ledger.get("state") == "reserved"
    )


def _has_unresolved_attempts(
    *,
    artifact_root: Path,
    samples_root: Path,
    ledger_root: Path,
    actual_ids: set[str],
    intent_ids: set[str],
    ledger_ids: set[str],
    validate_completed_intents: bool = False,
) -> bool:
    if intent_ids != actual_ids or ledger_ids != actual_ids:
        return True
    if not validate_completed_intents:
        return False
    artifact_root_hash = _artifact_root_hash(artifact_root)
    for sample_id in actual_ids:
        try:
            intent = trial.load_private_json(samples_root / f".{sample_id}.intent.json")
            sample = trial.load_private_json(samples_root / f"{sample_id}.json")
            ledger = trial.load_private_json(ledger_root / f"{sample_id}.json")
        except (OSError, ValueError):
            return True
        if not isinstance(sample, Mapping) or set(sample) != SAMPLE_FIELDS:
            return True
        if (
            not isinstance(intent, Mapping)
            or set(intent) != INTENT_FIELDS
            or intent.get("sample_id") != sample_id
            or intent.get("artifact_root_hash") != artifact_root_hash
            or intent.get("state") != "completed"
            or intent.get("sample_hash") != trial.canonical_hash(sample)
            or not _valid_completed_ledger(
                ledger,
                sample_id=sample_id,
            )
            or ledger.get("artifact_root_hash") != artifact_root_hash
        ):
            return True
    return False


class ProtocolError(Exception):
    exit_code = EXIT_INVALID
    status = "invalid"

    def __init__(self, reason_code: str) -> None:
        super().__init__(reason_code)
        self.reason_code = reason_code


class InvalidRequest(ProtocolError):
    pass


class Blocked(ProtocolError):
    exit_code = EXIT_BLOCKED
    status = "blocked"


class InternalFailure(ProtocolError):
    exit_code = EXIT_INTERNAL
    status = "error"


def _canonical_json(value: Any) -> bytes:
    return json.dumps(
        value,
        ensure_ascii=False,
        sort_keys=True,
        separators=(",", ":"),
        allow_nan=False,
    ).encode("utf-8")


def _hash(value: Any) -> str:
    payload = value if isinstance(value, bytes) else _canonical_json(value)
    return "sha256:" + hashlib.sha256(payload).hexdigest()


def _artifact_root_hash(artifact_root: Path) -> str:
    return _hash({"artifact_root": str(artifact_root)})


def _manifest_entry(relative_path: str) -> dict[str, Any]:
    path = HERE / relative_path
    try:
        info = path.lstat()
    except OSError as exc:
        raise InternalFailure("runtime_manifest_unavailable") from exc
    if stat.S_ISLNK(info.st_mode) or not stat.S_ISREG(info.st_mode):
        raise InternalFailure("runtime_manifest_unavailable")
    if info.st_mode & (stat.S_IWGRP | stat.S_IWOTH):
        raise InternalFailure("runtime_manifest_unavailable")
    payload = path.read_bytes()
    return {
        "path": relative_path,
        "sha256": "sha256:" + hashlib.sha256(payload).hexdigest(),
        "size": len(payload),
    }


def _runtime_manifest() -> dict[str, Any]:
    try:
        interpreter_path = Path(sys.executable).resolve(strict=True)
        interpreter_info = interpreter_path.lstat()
    except OSError as exc:
        raise InternalFailure("runtime_manifest_unavailable") from exc
    if not stat.S_ISREG(interpreter_info.st_mode) or interpreter_info.st_mode & (
        stat.S_IWGRP | stat.S_IWOTH
    ):
        raise InternalFailure("runtime_manifest_unavailable")
    core = {
        "schema_version": 1,
        "protocol_revision": PROTOCOL_REVISION,
        "interpreter": {
            "implementation": sys.implementation.name,
            "version": "{}.{}.{}".format(*sys.version_info[:3]),
            "executable_hash": provider_probe._hash_file(interpreter_path),
        },
        "entries": [_manifest_entry(path) for path in MANIFEST_PATHS],
    }
    return {**core, "manifest_hash": _hash(core)}


def _safe_id(value: Any, field: str) -> str:
    try:
        return reviewer_calibration._safe_id(value, field)
    except ValueError as exc:
        raise InvalidRequest("invalid_field") from exc


def _artifact_root(value: Any) -> Path:
    if not isinstance(value, str) or not value:
        raise InvalidRequest("invalid_artifact_root")
    requested = Path(value)
    if not requested.is_absolute():
        raise InvalidRequest("invalid_artifact_root")
    resolved = requested.resolve(strict=False)
    try:
        resolved.relative_to(SOURCE_CHECKOUT)
    except ValueError:
        pass
    else:
        raise InvalidRequest("invalid_artifact_root")
    try:
        SOURCE_CHECKOUT.relative_to(resolved)
    except ValueError:
        pass
    else:
        raise InvalidRequest("invalid_artifact_root")
    try:
        trial.ensure_private_directory(resolved)
    except ValueError as exc:
        raise InvalidRequest("invalid_artifact_root") from exc
    return resolved


@contextlib.contextmanager
def _sample_root_lock(artifact_root: Path):
    lock_path = artifact_root / ".sample.lock"
    flags = os.O_RDWR | os.O_CREAT | getattr(os, "O_NOFOLLOW", 0)
    try:
        descriptor = os.open(lock_path, flags, 0o600)
    except OSError as exc:
        reason_code = (
            "artifact_root_quarantined"
            if exc.errno in {errno.EISDIR, errno.ELOOP}
            else "sample_lock_unavailable"
        )
        raise Blocked(reason_code) from exc
    try:
        try:
            info = os.fstat(descriptor)
            fcntl.flock(descriptor, fcntl.LOCK_EX)
        except OSError as exc:
            raise Blocked("sample_lock_unavailable") from exc
        if (
            not stat.S_ISREG(info.st_mode)
            or info.st_uid != os.geteuid()
            or info.st_mode & (stat.S_IRWXG | stat.S_IRWXO)
        ):
            raise Blocked("artifact_root_quarantined")
        yield
    finally:
        os.close(descriptor)


def _load_cases_without_truth() -> tuple[list[dict[str, str]], str, str]:
    fixture = reviewer_calibration._load_json(
        HERE / "fixtures" / "reviewer-calibration-cases.json"
    )
    if set(fixture) != {
        "schema_version",
        "known_answer_fixture_hash",
        "cases",
    }:
        raise InternalFailure("fixture_invalid")
    if fixture.get("schema_version") != 1:
        raise InternalFailure("fixture_invalid")
    known_hash = fixture.get("known_answer_fixture_hash")
    if (
        not isinstance(known_hash, str)
        or re.fullmatch(r"sha256:[0-9a-f]{64}", known_hash) is None
    ):
        raise InternalFailure("fixture_invalid")
    rows = fixture.get("cases")
    if not isinstance(rows, Sequence) or isinstance(rows, (str, bytes)):
        raise InternalFailure("fixture_invalid")
    cases: list[dict[str, str]] = []
    seen: set[str] = set()
    try:
        for row in rows:
            if (
                not isinstance(row, Mapping)
                or set(row) != reviewer_calibration.CASE_FIELDS
            ):
                raise ValueError
            case_id = reviewer_calibration._safe_id(
                row.get("case_id"), "calibration case_id"
            )
            if case_id in seen:
                raise ValueError
            seen.add(case_id)
            cases.append(
                {
                    "case_id": case_id,
                    "task": reviewer_calibration._safe_text(row.get("task"), "task"),
                    "rubric": reviewer_calibration._safe_text(
                        row.get("rubric"), "rubric"
                    ),
                    "candidate_a": reviewer_calibration._safe_text(
                        row.get("candidate_a"), "candidate_a"
                    ),
                    "candidate_b": reviewer_calibration._safe_text(
                        row.get("candidate_b"), "candidate_b"
                    ),
                }
            )
    except ValueError as exc:
        raise InternalFailure("fixture_invalid") from exc
    if not cases:
        raise InternalFailure("fixture_invalid")
    case_hash = trial.canonical_hash(
        {
            "schema_version": 1,
            "known_answer_fixture_hash": known_hash,
            "cases": cases,
        }
    )
    return cases, known_hash, case_hash


def _validate_manifest_hash(payload: Mapping[str, Any]) -> dict[str, Any]:
    manifest = _runtime_manifest()
    if payload.get("runtime_manifest_hash") != manifest["manifest_hash"]:
        raise Blocked("runtime_drift")
    return manifest


def _write_exclusive_json(
    path: Path,
    payload: Mapping[str, Any],
    *,
    exists_reason: str = "sample_already_exists",
) -> None:
    flags = os.O_WRONLY | os.O_CREAT | os.O_EXCL | getattr(os, "O_NOFOLLOW", 0)
    try:
        descriptor = os.open(path, flags, 0o600)
    except FileExistsError as exc:
        raise Blocked(exists_reason) from exc
    try:
        raw = _canonical_json(payload) + b"\n"
        with os.fdopen(descriptor, "wb") as stream:
            stream.write(raw)
            stream.flush()
            os.fsync(stream.fileno())
    except BaseException:
        try:
            path.unlink(missing_ok=True)
        finally:
            raise


def _sample(payload: Any, artifact_root_value: Any) -> dict[str, Any]:
    if not isinstance(payload, Mapping) or set(payload) != {
        "sample_id",
        "provider",
        "executable",
        "model",
        "reviewer_family",
        "timeout_seconds",
        "max_model_calls",
        "runtime_manifest_hash",
    }:
        raise InvalidRequest("invalid_payload")
    if payload.get("provider") not in SUPPORTED_PROVIDERS:
        raise InvalidRequest("unsupported_provider")
    executable_value = payload.get("executable")
    if (
        not isinstance(executable_value, str)
        or not Path(executable_value).is_absolute()
    ):
        raise InvalidRequest("invalid_executable")
    try:
        executable = provider_probe._resolve_codex(Path(executable_value))
        model = provider_probe._validate_model(payload.get("model"))
    except (OSError, ValueError) as exc:
        raise InvalidRequest("invalid_provider_configuration") from exc
    family = _safe_id(payload.get("reviewer_family"), "reviewer_family")
    timeout_seconds = payload.get("timeout_seconds")
    if (
        isinstance(timeout_seconds, bool)
        or not isinstance(timeout_seconds, int)
        or not 1 <= timeout_seconds <= 600
    ):
        raise InvalidRequest("invalid_timeout")
    if payload.get("max_model_calls") != 1:
        raise InvalidRequest("invalid_cost_policy")
    manifest = _validate_manifest_hash(payload)
    artifact_root = _artifact_root(artifact_root_value)
    with _sample_root_lock(artifact_root):
        return _sample_locked(
            payload,
            artifact_root=artifact_root,
            executable=executable,
            model=model,
            family=family,
            timeout_seconds=timeout_seconds,
            manifest=manifest,
        )


def _sample_locked(
    payload: Mapping[str, Any],
    *,
    artifact_root: Path,
    executable: Path,
    model: str,
    family: str,
    timeout_seconds: int,
    manifest: Mapping[str, Any],
) -> dict[str, Any]:
    sample_id = _safe_id(payload.get("sample_id"), "sample_id")
    finalization_path = artifact_root / ".finalization.intent.json"
    if finalization_path.is_symlink():
        raise Blocked("artifact_root_quarantined")
    if finalization_path.exists():
        raise Blocked("finalize_already_started")
    samples_root = artifact_root / "samples"
    trial.ensure_private_directory(samples_root, artifact_root)
    ledger_root = artifact_root / "sample-ledger"
    trial.ensure_private_directory(ledger_root, artifact_root)
    actual_ids = {
        path.stem
        for path in samples_root.glob("*.json")
        if not path.name.startswith(".")
    }
    intent_suffix = ".intent.json"
    intent_ids = {
        path.name[1 : -len(intent_suffix)]
        for path in samples_root.glob(f".*{intent_suffix}")
    }
    ledger_ids = {path.stem for path in ledger_root.glob("*.json")}
    recovering_orphan_ledger = _recoverable_orphan_ledger(
        artifact_root=artifact_root,
        ledger_root=ledger_root,
        sample_id=sample_id,
        actual_ids=actual_ids,
        intent_ids=intent_ids,
        ledger_ids=ledger_ids,
    )
    resolved_ledger_ids = (
        ledger_ids - {sample_id} if recovering_orphan_ledger else ledger_ids
    )
    if _has_unresolved_attempts(
        artifact_root=artifact_root,
        samples_root=samples_root,
        ledger_root=ledger_root,
        actual_ids=actual_ids,
        intent_ids=intent_ids,
        ledger_ids=resolved_ledger_ids,
        validate_completed_intents=True,
    ):
        raise Blocked("artifact_root_quarantined")
    intent_path = samples_root / f".{sample_id}.intent.json"
    sample_path = samples_root / f"{sample_id}.json"
    ledger_path = ledger_root / f"{sample_id}.json"
    if (
        sample_path.exists()
        or sample_path.is_symlink()
        or intent_path.exists()
        or intent_path.is_symlink()
    ):
        raise Blocked("sample_already_exists")
    artifact_root_hash = _artifact_root_hash(artifact_root)

    cases, known_hash, case_hash = _load_cases_without_truth()
    environment = provider_probe._provider_environment()
    executable_hash = provider_probe._hash_file(executable)
    try:
        cli_version = provider_probe._codex_version(
            executable, artifact_root, timeout_seconds, environment
        )
    except (OSError, ValueError) as exc:
        raise Blocked("provider_identity_unavailable") from exc
    runner_hash = trial.canonical_hash(
        {
            "runner_contract": RUNNER_CONTRACT,
            "runtime_manifest_hash": manifest["manifest_hash"],
            "provider_executable_hash": executable_hash,
        }
    )
    intent = {
        "schema_version": 1,
        "sample_id": sample_id,
        "artifact_root_hash": artifact_root_hash,
        "provider": "codex",
        "provider_cli_version": cli_version,
        "provider_executable_hash": executable_hash,
        "model": model,
        "reviewer_family": family,
        "timeout_seconds": timeout_seconds,
        "max_model_calls": 1,
        "runtime_manifest_hash": manifest["manifest_hash"],
        "known_answer_fixture_hash": known_hash,
        "case_fixture_hash": case_hash,
        "runner_hash": runner_hash,
        "state": "model_call_started",
    }
    reserved_ledger = {
        "schema_version": 1,
        "artifact_contract": SAMPLE_LEDGER_CONTRACT,
        "sample_id": sample_id,
        "artifact_root_hash": artifact_root_hash,
        "state": "reserved",
    }
    if not recovering_orphan_ledger:
        _write_exclusive_json(ledger_path, reserved_ledger)
    _write_exclusive_json(intent_path, intent)
    started_ledger = {**reserved_ledger, "state": "model_call_started"}
    try:
        trial.write_json_atomic(ledger_path, started_ledger)
        if trial.load_private_json(ledger_path) != started_ledger:
            raise ValueError("sample ledger read-back mismatch")
    except (OSError, ValueError) as exc:
        raise Blocked("artifact_root_quarantined") from exc
    case_ids = [row["case_id"] for row in cases]
    try:
        response = provider_probe.invoke_codex_json_readonly(
            executable,
            model=model,
            prompt=reviewer_calibration._prompt(cases),
            schema=reviewer_calibration._response_schema(case_ids),
            timeout_seconds=timeout_seconds,
            environment=environment,
            session_prefix="codex-reviewer-calibration",
        )
        judgments = reviewer_calibration._validate_judgments(response, case_ids)
        if provider_probe._hash_file(executable) != executable_hash:
            raise ValueError("provider executable drifted")
        if (
            provider_probe._codex_version(
                executable, artifact_root, timeout_seconds, environment
            )
            != cli_version
        ):
            raise ValueError("provider version drifted")
        if _runtime_manifest()["manifest_hash"] != manifest["manifest_hash"]:
            raise ValueError("runtime drifted")
    except BaseException as exc:
        if isinstance(exc, (KeyboardInterrupt, SystemExit)):
            raise
        raise Blocked("model_call_unresolved") from exc
    sample = {
        "schema_version": 1,
        "artifact_contract": SAMPLE_CONTRACT,
        "sample_id": sample_id,
        "artifact_root_hash": artifact_root_hash,
        "provider": "codex",
        "provider_cli_version": cli_version,
        "provider_executable_hash": executable_hash,
        "provider_environment_keys": sorted(environment),
        "model": model,
        "reviewer_family": family,
        "timeout_seconds": timeout_seconds,
        "max_model_calls": 1,
        "runtime_manifest_hash": manifest["manifest_hash"],
        "known_answer_fixture_hash": known_hash,
        "case_fixture_hash": case_hash,
        "runner_contract": RUNNER_CONTRACT,
        "runner_hash": runner_hash,
        "requested_session_mode": "ephemeral",
        "tool_access": "read-only-observed-none",
        "judgments": judgments,
    }
    sample_hash = trial.canonical_hash(sample)
    try:
        trial.write_json_atomic(sample_path, sample)
        if trial.load_private_json(sample_path) != sample:
            raise ValueError("sample read-back mismatch")
        completed_intent = {
            **intent,
            "state": "completed",
            "sample_hash": sample_hash,
        }
        trial.write_json_atomic(intent_path, completed_intent)
        if trial.load_private_json(intent_path) != completed_intent:
            raise ValueError("sample intent read-back mismatch")
    except BaseException as exc:
        sample_path.unlink(missing_ok=True)
        if isinstance(exc, (KeyboardInterrupt, SystemExit)):
            raise
        raise Blocked("sample_publication_failed") from exc
    return {
        "sample_id": sample_id,
        "sample_artifact": sample_path.name,
        "sample_hash": sample_hash,
        "runtime_manifest_hash": manifest["manifest_hash"],
        "model_call_count": 1,
    }


def _load_samples(artifact_root: Path, sample_ids: list[str]) -> list[dict[str, Any]]:
    samples_root = artifact_root / "samples"
    if not samples_root.is_dir() or samples_root.is_symlink():
        raise Blocked("sample_set_mismatch")
    ledger_root = artifact_root / "sample-ledger"
    if not ledger_root.is_dir() or ledger_root.is_symlink():
        raise Blocked("sample_set_mismatch")
    actual_ids = {
        path.stem
        for path in samples_root.glob("*.json")
        if not path.name.startswith(".")
    }
    intent_suffix = ".intent.json"
    intent_ids = {
        path.name[1 : -len(intent_suffix)]
        for path in samples_root.glob(f".*{intent_suffix}")
    }
    ledger_ids = {path.stem for path in ledger_root.glob("*.json")}
    expected_ids = set(sample_ids)
    if _has_unresolved_attempts(
        artifact_root=artifact_root,
        samples_root=samples_root,
        ledger_root=ledger_root,
        actual_ids=actual_ids,
        intent_ids=intent_ids,
        ledger_ids=ledger_ids,
    ):
        raise Blocked("artifact_root_quarantined")
    if (
        actual_ids != expected_ids
        or intent_ids != expected_ids
        or ledger_ids != expected_ids
    ):
        raise Blocked("sample_set_mismatch")
    artifact_root_hash = _artifact_root_hash(artifact_root)
    samples: list[dict[str, Any]] = []
    for sample_id in sample_ids:
        try:
            sample = trial.load_private_json(samples_root / f"{sample_id}.json")
            intent = trial.load_private_json(samples_root / f".{sample_id}.intent.json")
            ledger = trial.load_private_json(ledger_root / f"{sample_id}.json")
        except (OSError, ValueError) as exc:
            raise Blocked("sample_invalid") from exc
        if not isinstance(sample, Mapping) or set(sample) != SAMPLE_FIELDS:
            raise Blocked("sample_invalid")
        if sample.get("sample_id") != sample_id:
            raise Blocked("sample_invalid")
        if not isinstance(intent, Mapping) or set(intent) != INTENT_FIELDS:
            raise Blocked("sample_finality_unknown")
        if not _valid_completed_ledger(
            ledger,
            sample_id=sample_id,
        ):
            raise Blocked("sample_invalid")
        if any(
            value.get("artifact_root_hash") != artifact_root_hash
            for value in (sample, intent, ledger)
        ):
            raise Blocked("artifact_root_mismatch")
        if (
            intent.get("state") != "completed"
            or intent.get("sample_id") != sample_id
            or intent.get("sample_hash") != trial.canonical_hash(sample)
        ):
            raise Blocked("sample_finality_unknown")
        intent_binding_fields = (
            "provider",
            "artifact_root_hash",
            "provider_cli_version",
            "provider_executable_hash",
            "model",
            "reviewer_family",
            "timeout_seconds",
            "max_model_calls",
            "runtime_manifest_hash",
            "known_answer_fixture_hash",
            "case_fixture_hash",
            "runner_hash",
        )
        if any(
            intent.get(field) != sample.get(field) for field in intent_binding_fields
        ):
            raise Blocked("sample_intent_mismatch")
        samples.append(dict(sample))
    return samples


def _finalize(payload: Any, artifact_root_value: Any) -> dict[str, Any]:
    if not isinstance(payload, Mapping) or set(payload) != {
        "sample_ids",
        "runtime_manifest_hash",
    }:
        raise InvalidRequest("invalid_payload")
    manifest = _validate_manifest_hash(payload)
    raw_ids = payload.get("sample_ids")
    if (
        not isinstance(raw_ids, Sequence)
        or isinstance(raw_ids, (str, bytes))
        or not 2 <= len(raw_ids) <= 5
    ):
        raise InvalidRequest("invalid_sample_set")
    sample_ids = [_safe_id(value, "sample_id") for value in raw_ids]
    if len(set(sample_ids)) != len(sample_ids):
        raise InvalidRequest("invalid_sample_set")
    artifact_root = _artifact_root(artifact_root_value)
    with _sample_root_lock(artifact_root):
        return _finalize_locked(
            sample_ids,
            artifact_root=artifact_root,
            manifest=manifest,
        )


def _load_owner_private_json(path: Path) -> Any:
    info = path.lstat()
    if (
        stat.S_ISLNK(info.st_mode)
        or not stat.S_ISREG(info.st_mode)
        or info.st_uid != os.geteuid()
        or stat.S_IMODE(info.st_mode) != 0o600
    ):
        raise ValueError("publication artifact is not owner-private")
    return trial.load_private_json(path)


def _ensure_calibration_root(calibration_root: Path, artifact_root: Path) -> None:
    try:
        trial.ensure_private_directory(calibration_root, artifact_root)
    except (OSError, ValueError) as exc:
        raise Blocked("finalization_recovery_required") from exc


def _claim_or_resume_finalization(
    finalization_path: Path,
    finalization_intent: Mapping[str, Any],
    calibration_root: Path,
    artifact_root: Path,
) -> tuple[str, str, bool]:
    if finalization_path.is_symlink():
        raise Blocked("artifact_root_quarantined")
    if not finalization_path.exists():
        _ensure_calibration_root(calibration_root, artifact_root)
        claim_token = secrets.token_hex(32)
        stored = {**finalization_intent, "claim_token": claim_token}
        _write_exclusive_json(
            finalization_path,
            stored,
            exists_reason="finalize_already_started",
        )
    else:
        try:
            stored = trial.load_private_json(finalization_path)
        except (OSError, ValueError) as exc:
            raise Blocked("finalize_already_started") from exc
        claim_token = stored.get("claim_token") if isinstance(stored, Mapping) else None
        if (
            not isinstance(claim_token, str)
            or re.fullmatch(r"[0-9a-f]{64}", claim_token) is None
        ):
            raise Blocked("finalize_already_started")
        publication_started_intent = {
            **finalization_intent,
            "claim_token": claim_token,
        }
        output_claimed_intent = {
            **publication_started_intent,
            "state": "output_claimed",
        }
        if stored == publication_started_intent:
            pass
        elif stored == output_claimed_intent:
            pass
        else:
            raise Blocked("finalize_already_started")
        _ensure_calibration_root(calibration_root, artifact_root)
    stored_state = stored["state"]
    publication_paths = reviewer_calibration._publication_paths(
        calibration_root
    )
    if stored_state == "publication_started" and any(
        path.exists() or path.is_symlink() for path in publication_paths
    ):
        raise Blocked("finalization_recovery_required")
    lock_path = calibration_root / ".reviewer-calibration.lock"
    lock_exists = lock_path.exists() or lock_path.is_symlink()
    if stored_state == "output_claimed":
        for path in publication_paths:
            if not path.exists() and not path.is_symlink():
                continue
            try:
                _load_owner_private_json(path)
            except (OSError, ValueError) as exc:
                raise Blocked("finalization_recovery_required") from exc
    if not lock_exists:
        return stored_state, claim_token, False
    try:
        lock = _load_owner_private_json(lock_path)
    except OSError as exc:
        raise Blocked("finalization_recovery_required") from exc
    except ValueError as exc:
        raise Blocked("finalization_recovery_required") from exc
    if lock != {"claim_token": claim_token}:
        raise Blocked("finalization_recovery_required")
    return stored_state, claim_token, True


def _finalize_locked(
    sample_ids: list[str],
    *,
    artifact_root: Path,
    manifest: Mapping[str, Any],
) -> dict[str, Any]:
    samples = _load_samples(artifact_root, sample_ids)
    binding_fields = (
        "provider",
        "provider_cli_version",
        "provider_executable_hash",
        "provider_environment_keys",
        "model",
        "reviewer_family",
        "runtime_manifest_hash",
        "known_answer_fixture_hash",
        "case_fixture_hash",
        "runner_contract",
        "runner_hash",
        "requested_session_mode",
        "tool_access",
    )
    first = samples[0]
    if any(
        any(sample.get(field) != first.get(field) for field in binding_fields)
        for sample in samples[1:]
    ):
        raise Blocked("sample_binding_mismatch")
    if first["runtime_manifest_hash"] != manifest["manifest_hash"]:
        raise Blocked("runtime_drift")
    known_answers, cases, pilot_gates, known_hash, case_hash = (
        reviewer_calibration._load_frozen_inputs(
            HERE / "fixtures" / "reviewer-calibration-known-answers.json",
            HERE / "fixtures" / "reviewer-calibration-cases.json",
            HERE / "pilot-gates.json",
        )
    )
    if (
        first["known_answer_fixture_hash"] != known_hash
        or first["case_fixture_hash"] != case_hash
    ):
        raise Blocked("fixture_drift")
    case_ids = [row["case_id"] for row in cases]
    runs = [
        reviewer_calibration._validate_judgments(
            {"protocol_version": 1, "judgments": sample["judgments"]}, case_ids
        )
        for sample in samples
    ]
    finalization_path = artifact_root / ".finalization.intent.json"
    finalization_intent = {
        "schema_version": 1,
        "artifact_contract": FINALIZATION_CONTRACT,
        "artifact_root_hash": _artifact_root_hash(artifact_root),
        "runtime_manifest_hash": manifest["manifest_hash"],
        "sample_ids": sample_ids,
        "sample_hashes": [trial.canonical_hash(sample) for sample in samples],
        "state": "publication_started",
        "published_pair_hash": None,
    }
    calibration_root = artifact_root / "calibration"
    finalization_state, claim_token, lock_exists = _claim_or_resume_finalization(
        finalization_path,
        finalization_intent,
        calibration_root,
        artifact_root,
    )
    paths = reviewer_calibration._publication_paths(
        calibration_root
    )
    document_args = {
        "known_answers": known_answers,
        "known_hash": known_hash,
        "case_hash": case_hash,
        "pilot_gates": pilot_gates,
        "family": first["reviewer_family"],
        "runs": runs,
        "provider": first["provider"],
        "cli_version": first["provider_cli_version"],
        "executable_hash": first["provider_executable_hash"],
        "environment": {
            key: "" for key in first["provider_environment_keys"]
        },
        "model": first["model"],
        "provider_binding": {
            "runtime_manifest_hash": manifest["manifest_hash"],
            "sample_ids": sample_ids,
        },
        "runner_contract": first["runner_contract"],
        "runner_hash": first["runner_hash"],
        "requested_session_mode": first["requested_session_mode"],
        "tool_access": first["tool_access"],
    }
    try:
        expected_report, expected_evidence = (
            reviewer_calibration._build_calibration_documents(
                **document_args,
                evidence_name=paths[1].name,
            )
        )
        complete_canonical_pair = paths[0].exists() and paths[1].exists()
        pair_already_published = (
            complete_canonical_pair
            and _load_owner_private_json(paths[0]) == expected_report
            and _load_owner_private_json(paths[1]) == expected_evidence
        )
        if complete_canonical_pair and not pair_already_published:
            raise Blocked("finalize_already_started")
        staged_paths: list[Path] = []
        if pair_already_published:
            staged_paths = [
                path
                for path in paths[2:]
                if path.exists() or path.is_symlink()
            ]
            expected_staged = {
                paths[2]: expected_report,
                paths[3]: expected_evidence,
            }
            for path in staged_paths:
                if _load_owner_private_json(path) != expected_staged[path]:
                    raise Blocked("finalization_recovery_required")
        if not lock_exists:
            _write_exclusive_json(
                calibration_root / ".reviewer-calibration.lock",
                {"claim_token": claim_token},
                exists_reason="finalization_recovery_required",
            )
        if finalization_state == "publication_started":
            output_claimed_intent = {
                **finalization_intent,
                "claim_token": claim_token,
                "state": "output_claimed",
            }
            trial.write_json_atomic(finalization_path, output_claimed_intent)
            if (
                trial.load_private_json(finalization_path)
                != output_claimed_intent
            ):
                raise ValueError("finalization output claim read-back mismatch")
        if pair_already_published:
            for path in staged_paths:
                path.unlink()
            report = expected_report
        else:
            report = reviewer_calibration._persist_calibration(
                **document_args,
                report_path=paths[0],
                evidence_path=paths[1],
                staged_report_path=paths[2],
                staged_evidence_path=paths[3],
            )
            if (
                _load_owner_private_json(paths[0]) != expected_report
                or _load_owner_private_json(paths[1]) != expected_evidence
            ):
                raise ValueError("published calibration pair mismatch")
        published_pair_hash = _hash(
            {
                "result": trial.canonical_hash(expected_report),
                "evidence": trial.canonical_hash(expected_evidence),
            }
        )
        completed_finalization = {
            **finalization_intent,
            "claim_token": claim_token,
            "state": "completed",
            "published_pair_hash": published_pair_hash,
        }
        trial.write_json_atomic(finalization_path, completed_finalization)
        if trial.load_private_json(finalization_path) != completed_finalization:
            raise ValueError("finalization intent read-back mismatch")
    except BaseException as exc:
        if isinstance(exc, (Blocked, KeyboardInterrupt, SystemExit)):
            raise
        raise Blocked("finalization_recovery_required") from exc
    return {
        "calibration_status": report["calibration_status"],
        "calibration_evidence": report["calibration_evidence"],
        "calibration_result": "reviewer-calibration-result.json",
        "runtime_manifest_hash": manifest["manifest_hash"],
        "model_call_count": 0,
    }


def _dispatch(request: Any) -> tuple[str, dict[str, Any]]:
    if not isinstance(request, Mapping):
        raise InvalidRequest("invalid_request")
    action = request.get("action")
    expected_fields = (
        {"schema", "request_id", "action", "payload"}
        if action == "probe"
        else {"schema", "request_id", "action", "artifact_root", "payload"}
    )
    if set(request) != expected_fields:
        raise InvalidRequest("invalid_request")
    if request.get("schema") != REQUEST_SCHEMA:
        raise InvalidRequest("protocol_mismatch")
    request_id = request.get("request_id")
    if not isinstance(request_id, str) or SAFE_REQUEST_ID.fullmatch(request_id) is None:
        raise InvalidRequest("invalid_request_id")
    if action not in SUPPORTED_ACTIONS:
        raise InvalidRequest("unsupported_action")
    payload = request.get("payload")
    if action == "probe":
        if payload != {}:
            raise InvalidRequest("invalid_payload")
        manifest = _runtime_manifest()
        result = {
            "protocol_revision": PROTOCOL_REVISION,
            "supported_actions": list(SUPPORTED_ACTIONS),
            "supported_providers": list(SUPPORTED_PROVIDERS),
            "reason_codes": list(REASON_CODES),
            "runtime_manifest": manifest,
            "runtime_manifest_hash": manifest["manifest_hash"],
            "sample_model_call_limit": 1,
            "finalize_model_call_count": 0,
        }
    elif action == "sample":
        result = _sample(payload, request.get("artifact_root"))
    else:
        result = _finalize(payload, request.get("artifact_root"))
    return request_id, result


def _response(
    request_id: str,
    *,
    status: str,
    action: str | None,
    result: Mapping[str, Any] | None = None,
    reason_code: str | None = None,
) -> dict[str, Any]:
    response: dict[str, Any] = {
        "schema": RESPONSE_SCHEMA,
        "request_id": request_id,
        "status": status,
    }
    if action in SUPPORTED_ACTIONS:
        response["action"] = action
    if result is not None:
        response["result"] = dict(result)
    if reason_code is not None:
        response["reason_code"] = reason_code
    return response


def main() -> int:
    request_id = "redacted-invalid-request-id"
    action: str | None = None
    try:
        raw = sys.stdin.buffer.read(MAX_REQUEST_BYTES + 1)
        if len(raw) > MAX_REQUEST_BYTES:
            raise InvalidRequest("request_too_large")
        request = json.loads(raw)
        if isinstance(request, Mapping):
            candidate = request.get("request_id")
            if isinstance(candidate, str) and SAFE_REQUEST_ID.fullmatch(candidate):
                request_id = candidate
            candidate_action = request.get("action")
            if isinstance(candidate_action, str):
                action = candidate_action
        request_id, result = _dispatch(request)
        response = _response(request_id, status="ok", action=action, result=result)
        exit_code = EXIT_OK
    except (UnicodeDecodeError, json.JSONDecodeError, InvalidRequest) as exc:
        reason = exc.reason_code if isinstance(exc, InvalidRequest) else "invalid_json"
        response = _response(
            request_id,
            status="invalid",
            action=action,
            reason_code=reason,
        )
        exit_code = EXIT_INVALID
    except ProtocolError as exc:
        response = _response(
            request_id,
            status=exc.status,
            action=action,
            reason_code=exc.reason_code,
        )
        exit_code = exc.exit_code
    except BaseException:
        response = _response(
            request_id,
            status="error",
            action=action,
            reason_code="internal_error",
        )
        exit_code = EXIT_INTERNAL
    sys.stdout.buffer.write(_canonical_json(response) + b"\n")
    sys.stdout.buffer.flush()
    return exit_code


if __name__ == "__main__":
    raise SystemExit(main())
