#!/usr/bin/env python3
"""Fail-closed, no-tool Claude JSON adapter for reviewer calibration."""

from __future__ import annotations

import json
import os
import sys
import tempfile
from pathlib import Path
from typing import Any, Mapping

import provider_probe


REQUIRED_FLAGS = {
    "--print",
    "--tools",
    "--strict-mcp-config",
    "--mcp-config",
    "--setting-sources",
    "--safe-mode",
    "--disable-slash-commands",
    "--no-session-persistence",
    "--output-format",
    "--verbose",
    "--json-schema",
    "--model",
}
MAX_HELP_BYTES = 64 * 1024
MAX_STREAM_BYTES = 64 * 1024


def resolve_executable(path: Path, field: str) -> Path:
    requested = Path(path).expanduser()
    if not requested.is_absolute():
        raise ValueError(f"{field} must be absolute")
    resolved = requested.resolve(strict=True)
    if not resolved.is_file() or not os.access(resolved, os.X_OK):
        raise ValueError(f"{field} must name an executable regular file")
    return resolved


def resolve_runtime_validator(path: Path) -> Path:
    requested = Path(path).expanduser()
    if not requested.is_absolute():
        raise ValueError("Claude runtime validator path must be absolute")
    resolved = requested.resolve(strict=True)
    if not resolved.is_file():
        raise ValueError("Claude runtime validator must be a regular file")
    return resolved


def provider_environment() -> dict[str, str]:
    environment = provider_probe._provider_environment()
    environment.pop("OPENAI_API_KEY", None)
    for key in ("USER", "LOGNAME"):
        if key in os.environ:
            environment[key] = os.environ[key]
    if "ANTHROPIC_API_KEY" in os.environ:
        environment["ANTHROPIC_API_KEY"] = os.environ["ANTHROPIC_API_KEY"]
    environment["CLAUDE_CODE_DISABLE_AUTO_MEMORY"] = "1"
    environment["CLAUDE_CODE_DISABLE_CLAUDE_MDS"] = "1"
    return environment


def _help_flags(
    executable: Path,
    *,
    cwd: Path,
    timeout_seconds: int,
    environment: Mapping[str, str],
) -> set[str]:
    raw = provider_probe._run_bounded(
        [str(executable), "-p", "--help"],
        cwd=cwd,
        timeout_seconds=min(timeout_seconds, 10),
        capture_stdout=True,
        stdout_limit_bytes=MAX_HELP_BYTES,
        environment=environment,
    )
    try:
        help_text = raw.decode("utf-8")
    except UnicodeDecodeError as exc:
        raise ValueError("Claude CLI help is not UTF-8") from exc
    flags: set[str] = set()
    for token in help_text.split():
        normalized = token.rstrip(",").split("=", 1)[0]
        if normalized.startswith("--"):
            flags.add(normalized)
    missing = sorted(REQUIRED_FLAGS - flags)
    if missing:
        raise ValueError(
            "required Claude CLI flag is unavailable: " + ",".join(missing)
        )
    return flags


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


def _audit_stream(path: Path, expected_model: str) -> Mapping[str, Any]:
    try:
        raw = path.read_bytes()
    except OSError as exc:
        raise ValueError("Claude event stream is unavailable") from exc
    if len(raw) > MAX_STREAM_BYTES:
        raise ValueError("Claude event stream is too large")
    try:
        lines = raw.decode("utf-8").splitlines()
    except UnicodeDecodeError as exc:
        raise ValueError("Claude event stream is not UTF-8") from exc
    events = [
        _strict_json_object(line, "Claude event stream")
        for line in lines
        if line.strip()
    ]
    init_events = [
        event
        for event in events
        if event.get("type") == "system" and event.get("subtype") == "init"
    ]
    if not init_events:
        raise ValueError("Claude event stream lacks init model evidence")
    model_values = [event.get("model") for event in init_events]
    if any(not isinstance(value, str) or not value for value in model_values):
        raise ValueError("Claude event stream contains invalid init model evidence")
    observed_models = set(model_values)
    if observed_models != {expected_model}:
        raise ValueError(
            "Claude runtime model does not match the requested exact model"
        )
    results = [event for event in events if event.get("type") == "result"]
    if len(results) != 1:
        raise ValueError("Claude event stream lacks one terminal result")
    result = results[0]
    if (
        result.get("subtype") != "success"
        or result.get("is_error") is not False
        or result.get("terminal_reason") not in {None, "completed"}
        or result.get("api_error_status") is not None
        or result.get("permission_denials")
    ):
        raise ValueError("Claude result envelope is not clean")
    structured = result.get("structured_output")
    if not isinstance(structured, Mapping):
        raise ValueError("Claude result lacks structured output")
    return structured


def _verify_runtime_surface(
    validator: Path,
    *,
    events_path: Path,
    stderr_path: Path,
    cwd: Path,
    timeout_seconds: int,
    environment: Mapping[str, str],
) -> None:
    argv = [
        sys.executable,
        str(validator),
        "0",
        str(events_path),
        str(stderr_path),
        "--require-empty-init",
        "--expected-tools",
        "StructuredOutput",
        "--allow-expected-tool-use",
        "--runtime-surface-only",
    ]
    try:
        provider_probe._run_bounded(
            argv,
            cwd=cwd,
            timeout_seconds=min(timeout_seconds, 10),
            capture_stdout=True,
            stdout_limit_bytes=16 * 1024,
            environment=environment,
        )
    except ValueError as exc:
        raise ValueError("Claude runtime isolation verification failed") from exc


def invoke_json_no_tools(
    executable: Path,
    *,
    model: str,
    prompt: str,
    schema: Mapping[str, Any],
    timeout_seconds: int,
    environment: Mapping[str, str],
    runtime_validator: Path,
) -> Mapping[str, Any]:
    """Run one fresh Claude process and return its exact-model JSON payload."""

    model = provider_probe._validate_model(model)
    if (
        not prompt
        or len(prompt.encode("utf-8")) > provider_probe.MAX_PROVIDER_PROMPT_BYTES
    ):
        raise ValueError("provider prompt is empty or too large")
    if not isinstance(schema, Mapping):
        raise ValueError("provider response schema must be an object")
    with tempfile.TemporaryDirectory(
        prefix="ccl-skills-claude-reviewer-calibration-"
    ) as directory:
        session_root = Path(directory)
        session_root.chmod(0o700)
        session_environment = dict(environment)
        session_environment["TMPDIR"] = str(session_root)
        available_flags = _help_flags(
            executable,
            cwd=session_root,
            timeout_seconds=timeout_seconds,
            environment=session_environment,
        )
        events_path = session_root / "events.jsonl"
        stderr_path = session_root / "stderr.log"
        argv = [
            str(executable),
            "--print",
            "--tools",
            "",
            "--strict-mcp-config",
            "--mcp-config",
            '{"mcpServers":{}}',
            "--setting-sources",
            "",
            "--safe-mode",
            "--disable-slash-commands",
            "--no-session-persistence",
            "--output-format",
            "stream-json",
            "--verbose",
            "--json-schema",
            json.dumps(dict(schema), sort_keys=True, separators=(",", ":")),
            "--model",
            model,
        ]
        if "--effort" in available_flags:
            argv.extend(["--effort", "low"])
        provider_probe._run_bounded(
            argv,
            cwd=session_root,
            timeout_seconds=timeout_seconds,
            stdin=prompt.encode("utf-8"),
            stdout_path=events_path,
            stderr_path=stderr_path,
            environment=session_environment,
        )
        _verify_runtime_surface(
            runtime_validator,
            events_path=events_path,
            stderr_path=stderr_path,
            cwd=session_root,
            timeout_seconds=timeout_seconds,
            environment=session_environment,
        )
        return dict(_audit_stream(events_path, model))
