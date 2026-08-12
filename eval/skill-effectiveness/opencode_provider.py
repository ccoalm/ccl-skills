#!/usr/bin/env python3
"""Fail-closed OpenCode JSON transport for reviewer calibration."""

from __future__ import annotations

import json
import os
import tempfile
from pathlib import Path
from typing import Any, Mapping, Sequence

import provider_probe


MAX_EVENTS_BYTES = 64 * 1024
MAX_EXPORT_BYTES = 128 * 1024
TOOL_TYPE_MARKERS = ("tool", "command_execution", "command-execution")


def resolve_executable(path: Path) -> Path:
    requested = Path(path).expanduser()
    if not requested.is_absolute():
        raise ValueError("opencode_path must be absolute")
    resolved = requested.resolve(strict=True)
    if not resolved.is_file() or not os.access(resolved, os.X_OK):
        raise ValueError("opencode_path must name an executable regular file")
    return resolved


def provider_environment() -> dict[str, str]:
    environment = provider_probe._provider_environment()
    environment.pop("OPENAI_API_KEY", None)
    for key in ("USER", "LOGNAME"):
        if key in os.environ:
            environment[key] = os.environ[key]
    return environment


def validate_expected_model(model: str) -> tuple[str, str]:
    exact_model = provider_probe._validate_model(model)
    provider_id, separator, model_id = exact_model.partition("/")
    if not separator or not provider_id or not model_id:
        raise ValueError("OpenCode model must use exact providerID/modelID form")
    return provider_id, model_id


def _strict_json_object(raw: str, field: str) -> Mapping[str, Any]:
    def reject_duplicate_keys(pairs: list[tuple[str, Any]]) -> dict[str, Any]:
        payload: dict[str, Any] = {}
        for key, value in pairs:
            if key in payload:
                raise ValueError(f"{field} contains duplicate JSON keys")
            payload[key] = value
        return payload

    try:
        payload = json.loads(raw, object_pairs_hook=reject_duplicate_keys)
    except json.JSONDecodeError as exc:
        raise ValueError(f"{field} contains invalid JSON") from exc
    if not isinstance(payload, Mapping):
        raise ValueError(f"{field} must be a JSON object")
    return payload


def _read_text(path: Path, field: str, limit: int) -> str:
    try:
        raw = path.read_bytes()
    except OSError as exc:
        raise ValueError(f"{field} is unavailable") from exc
    if not raw or len(raw) > limit:
        raise ValueError(f"{field} is empty or too large")
    try:
        return raw.decode("utf-8")
    except UnicodeDecodeError as exc:
        raise ValueError(f"{field} is not UTF-8") from exc


def _has_tool_activity(value: Any) -> bool:
    if isinstance(value, Mapping):
        event_type = value.get("type")
        if isinstance(event_type, str):
            normalized = event_type.lower().replace("_", "-")
            if "tool" in normalized or normalized in TOOL_TYPE_MARKERS:
                return True
        return any(_has_tool_activity(child) for child in value.values())
    if isinstance(value, Sequence) and not isinstance(value, (str, bytes)):
        return any(_has_tool_activity(child) for child in value)
    return False


def _model_identity(value: Any, field: str) -> tuple[str, str]:
    if not isinstance(value, Mapping):
        raise ValueError(f"{field} is invalid")
    provider_id = value.get("providerID")
    model_id = value.get("modelID")
    if (
        not isinstance(provider_id, str)
        or not provider_id
        or not isinstance(model_id, str)
        or not model_id
    ):
        raise ValueError(f"{field} is invalid")
    return provider_id, model_id


def _session_model_identity(value: Any) -> tuple[str, str]:
    if not isinstance(value, Mapping):
        raise ValueError("OpenCode session model attribution is invalid")
    provider_id = value.get("providerID")
    model_id = value.get("id")
    if (
        not isinstance(provider_id, str)
        or not provider_id
        or not isinstance(model_id, str)
        or not model_id
    ):
        raise ValueError("OpenCode session model attribution is invalid")
    return provider_id, model_id


def _audit_events(path: Path) -> str:
    text = _read_text(path, "OpenCode event stream", MAX_EVENTS_BYTES)
    events = [
        _strict_json_object(line, "OpenCode event stream")
        for line in text.splitlines()
        if line.strip()
    ]
    if not events:
        raise ValueError("OpenCode event stream is empty")
    if any(_has_tool_activity(event) for event in events):
        raise ValueError("OpenCode event stream contains tool activity")
    session_ids = {
        event.get("sessionID")
        for event in events
        if isinstance(event.get("sessionID"), str) and event.get("sessionID")
    }
    if len(session_ids) != 1:
        raise ValueError("OpenCode event stream session binding is invalid")
    return session_ids.pop()


def _audit_export(
    path: Path,
    *,
    expected_session_id: str,
    expected_model: tuple[str, str],
) -> Mapping[str, Any]:
    payload = _strict_json_object(
        _read_text(path, "OpenCode session export", MAX_EXPORT_BYTES),
        "OpenCode session export",
    )
    session_info = payload.get("info")
    if (
        not isinstance(session_info, Mapping)
        or session_info.get("id") != expected_session_id
    ):
        raise ValueError("OpenCode exported session does not match the event stream")
    if session_info.get("agent") != "reviewer-calibration":
        raise ValueError("OpenCode exported session agent is invalid")
    if _session_model_identity(session_info.get("model")) != expected_model:
        raise ValueError("OpenCode model evidence does not match the expected model")
    messages = payload.get("messages")
    if not isinstance(messages, Sequence) or isinstance(messages, (str, bytes)):
        raise ValueError("OpenCode session export messages are invalid")
    assistant_messages: list[Mapping[str, Any]] = []
    for message in messages:
        if not isinstance(message, Mapping):
            raise ValueError("OpenCode session export message is invalid")
        info = message.get("info")
        parts = message.get("parts")
        if not isinstance(info, Mapping) or not isinstance(parts, Sequence) or isinstance(
            parts, (str, bytes)
        ):
            raise ValueError("OpenCode session export message shape is invalid")
        if _has_tool_activity(parts):
            raise ValueError("OpenCode export contains tool activity")
        if info.get("sessionID") != expected_session_id or any(
            not isinstance(part, Mapping)
            or part.get("sessionID") != expected_session_id
            for part in parts
        ):
            raise ValueError("OpenCode exported message session binding is invalid")
        if info.get("role") == "assistant":
            if info.get("agent") != "reviewer-calibration":
                raise ValueError("OpenCode exported assistant agent is invalid")
            observed_model = _model_identity(
                info, "OpenCode assistant model attribution"
            )
            if observed_model != expected_model:
                raise ValueError(
                    "OpenCode model evidence does not match the expected model"
                )
            assistant_messages.append(message)
    if not assistant_messages:
        raise ValueError("OpenCode export lacks an assistant message")
    final_parts = assistant_messages[-1]["parts"]
    finish_parts = [
        part
        for part in final_parts
        if isinstance(part, Mapping) and part.get("type") == "step-finish"
    ]
    if len(finish_parts) != 1 or finish_parts[0].get("reason") != "stop":
        raise ValueError("OpenCode final assistant turn did not stop cleanly")
    text_parts = [
        part.get("text")
        for part in final_parts
        if isinstance(part, Mapping) and part.get("type") == "text"
    ]
    if len(text_parts) != 1 or not isinstance(text_parts[0], str) or not text_parts[0]:
        raise ValueError("OpenCode final assistant text is invalid")
    return _strict_json_object(text_parts[0], "OpenCode final assistant text")


def _source_auth_path() -> Path:
    configured = os.environ.get("XDG_DATA_HOME")
    if configured:
        source_data = Path(configured).expanduser()
        if not source_data.is_absolute():
            raise ValueError("XDG_DATA_HOME must be absolute for OpenCode auth binding")
    else:
        home = os.environ.get("HOME")
        if not home:
            raise ValueError("HOME is required for OpenCode auth lookup")
        home_path = Path(home).expanduser()
        if not home_path.is_absolute():
            raise ValueError("HOME must be absolute for OpenCode auth binding")
        source_data = home_path / ".local" / "share"
    return source_data / "opencode" / "auth.json"


def _bind_auth(source_auth: Path, private_auth: Path) -> bool:
    if not os.path.lexists(source_auth):
        return False
    if not source_auth.is_file() or not os.access(source_auth, os.R_OK):
        raise ValueError("OpenCode auth binding source is invalid")
    private_auth.symlink_to(source_auth)
    return True


def _verify_auth_binding(
    source_auth: Path, private_auth: Path, binding_required: bool
) -> None:
    if not binding_required:
        return
    if not private_auth.is_symlink() or os.readlink(private_auth) != str(source_auth):
        raise ValueError("OpenCode auth binding was replaced")


def _agent_definition() -> str:
    return """---
description: Isolated reviewer calibration
mode: primary
tools:
  "*": false
permission:
  "*": deny
---
Judge only the calibration cases in the message. Do not use tools. Return only the requested JSON object.
"""


def invoke_json_no_tools(
    executable: Path,
    *,
    model: str,
    prompt: str,
    timeout_seconds: int,
    environment: Mapping[str, str],
) -> Mapping[str, Any]:
    """Run one fresh OpenCode session and return its bound JSON payload."""

    expected_model = validate_expected_model(model)
    if (
        not isinstance(prompt, str)
        or not prompt
        or len(prompt.encode("utf-8")) > provider_probe.MAX_PROVIDER_PROMPT_BYTES
    ):
        raise ValueError("provider prompt is empty or too large")
    with tempfile.TemporaryDirectory(
        prefix="ccl-skills-opencode-reviewer-calibration-"
    ) as directory:
        session_root = Path(directory)
        session_root.chmod(0o700)
        project = session_root / "project"
        agent_root = project / ".opencode" / "agent"
        private_data = session_root / "xdg-data"
        private_state = session_root / "xdg-state"
        private_auth = private_data / "opencode" / "auth.json"
        agent_root.mkdir(parents=True, mode=0o700)
        private_auth.parent.mkdir(parents=True, mode=0o700)
        private_state.mkdir(mode=0o700)
        (agent_root / "reviewer-calibration.md").write_text(
            _agent_definition(), encoding="utf-8"
        )
        source_auth = _source_auth_path()
        binding_required = _bind_auth(source_auth, private_auth)
        session_environment = dict(environment)
        session_environment.update(
            {
                "TMPDIR": str(session_root),
                "XDG_DATA_HOME": str(private_data),
                "XDG_STATE_HOME": str(private_state),
            }
        )

        events_path = session_root / "events.jsonl"
        run_stderr_path = session_root / "run-stderr.log"
        provider_probe._run_bounded(
            [
                str(executable),
                "run",
                "--dir",
                str(project),
                "--agent",
                "reviewer-calibration",
                "--model",
                model,
                "--format",
                "json",
                prompt,
            ],
            cwd=project,
            timeout_seconds=timeout_seconds,
            stdout_path=events_path,
            stderr_path=run_stderr_path,
            environment=session_environment,
        )
        _verify_auth_binding(source_auth, private_auth, binding_required)
        session_id = _audit_events(events_path)

        export_path = session_root / "session-export.json"
        export_stderr_path = session_root / "export-stderr.log"
        provider_probe._run_bounded(
            [str(executable), "export", session_id],
            cwd=project,
            timeout_seconds=timeout_seconds,
            stdout_path=export_path,
            stderr_path=export_stderr_path,
            environment=session_environment,
        )
        _verify_auth_binding(source_auth, private_auth, binding_required)
        return dict(
            _audit_export(
                export_path,
                expected_session_id=session_id,
                expected_model=expected_model,
            )
        )
