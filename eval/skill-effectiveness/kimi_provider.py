#!/usr/bin/env python3
"""Fail-closed Kimi CLI JSON transport for reviewer calibration."""

from __future__ import annotations

import json
import os
import re
import tempfile
from pathlib import Path
from typing import Any, Mapping, Sequence

import provider_probe


try:
    import tomllib as _tomllib
except ModuleNotFoundError:  # python < 3.11: TOML parsing unavailable; the
    _tomllib = None          # config paths below fail closed with a typed error.


def _require_tomllib():
    if _tomllib is None:
        raise ValueError("Kimi source config is unavailable (python < 3.11 lacks tomllib)")
    return _tomllib


MAX_CONFIG_BYTES = 256 * 1024
MAX_STREAM_BYTES = 64 * 1024
BARE_TOML_KEY = re.compile(r"^[A-Za-z0-9_-]+$")
ASSISTANT_FIELDS = {"role", "content", "tool_calls"}
RESUME_FIELDS = {"role", "type", "session_id", "command", "content"}
RETRY_FIELDS = {
    "role",
    "type",
    "failed_attempt",
    "next_attempt",
    "max_attempts",
    "delay_ms",
    "error_name",
    "error_message",
    "status_code",
}


def resolve_executable(path: Path) -> Path:
    requested = Path(path).expanduser()
    if not requested.is_absolute():
        raise ValueError("kimi_path must be absolute")
    resolved = requested.resolve(strict=True)
    if not resolved.is_file() or not os.access(resolved, os.X_OK):
        raise ValueError("kimi_path must name an executable regular file")
    return resolved


def provider_environment() -> dict[str, str]:
    environment = provider_probe._provider_environment()
    environment.pop("OPENAI_API_KEY", None)
    for key in ("USER", "LOGNAME"):
        if key in os.environ:
            environment[key] = os.environ[key]
    return environment


def _source_home() -> Path:
    configured = os.environ.get("KIMI_CODE_HOME")
    if configured:
        source_home = Path(configured).expanduser()
    else:
        home = os.environ.get("HOME")
        if not home:
            raise ValueError("HOME is required for Kimi config lookup")
        source_home = Path(home).expanduser() / ".kimi-code"
    if not source_home.is_absolute():
        raise ValueError("KIMI_CODE_HOME must be absolute")
    return source_home


def _read_source_config(source_home: Path) -> Mapping[str, Any]:
    path = source_home / "config.toml"
    try:
        raw = path.read_bytes()
    except OSError as exc:
        raise ValueError("Kimi source config is unavailable") from exc
    if not raw or len(raw) > MAX_CONFIG_BYTES:
        raise ValueError("Kimi source config is empty or too large")
    try:
        payload = _require_tomllib().loads(raw.decode("utf-8"))
    except (UnicodeDecodeError, _require_tomllib().TOMLDecodeError) as exc:
        raise ValueError("Kimi source config is invalid") from exc
    if not isinstance(payload, Mapping):
        raise ValueError("Kimi source config must be a TOML object")
    return payload


def _selected_config(
    source: Mapping[str, Any], model_alias: str
) -> dict[str, Any]:
    model_alias = provider_probe._validate_model(model_alias)
    models = source.get("models")
    providers = source.get("providers")
    if not isinstance(models, Mapping) or model_alias not in models:
        raise ValueError("Kimi model alias is not configured")
    model_config = models[model_alias]
    if not isinstance(model_config, Mapping):
        raise ValueError("Kimi model alias config is invalid")
    provider_id = model_config.get("provider")
    if (
        not isinstance(provider_id, str)
        or not provider_id
        or not isinstance(providers, Mapping)
        or provider_id not in providers
    ):
        raise ValueError("Kimi model provider binding is invalid")
    provider_config = providers[provider_id]
    if not isinstance(provider_config, Mapping) or provider_config.get("type") != "kimi":
        raise ValueError("Kimi model must bind a native Kimi provider")
    underlying_model = model_config.get("model")
    if not isinstance(underlying_model, str) or not underlying_model:
        raise ValueError("Kimi underlying model binding is invalid")
    return {
        "default_model": model_alias,
        "providers": {provider_id: dict(provider_config)},
        "models": {model_alias: dict(model_config)},
        "permission": {
            "rules": [
                {
                    "decision": "deny",
                    "scope": "user",
                    "pattern": "*",
                    "reason": "reviewer calibration disables every tool",
                }
            ]
        },
    }


def prepare_runtime(
    model_alias: str,
) -> tuple[Path, dict[str, Any], dict[str, str]]:
    """Freeze one source-home model/provider binding for all repeat sessions."""

    exact_alias = provider_probe._validate_model(model_alias)
    source_home = _source_home()
    selected_config = _selected_config(
        _read_source_config(source_home), exact_alias
    )
    model_config = selected_config["models"][exact_alias]
    return (
        source_home,
        selected_config,
        {
            "binding_type": "configured-alias",
            "model_alias": exact_alias,
            "provider_id": model_config["provider"],
            "underlying_model": model_config["model"],
        },
    )


def _toml_key(value: str) -> str:
    return value if BARE_TOML_KEY.fullmatch(value) else json.dumps(value)


def _toml_value(value: Any) -> str:
    if isinstance(value, bool):
        return "true" if value else "false"
    if isinstance(value, str):
        return json.dumps(value, ensure_ascii=False)
    if isinstance(value, int) and not isinstance(value, bool):
        return str(value)
    if isinstance(value, float):
        if value != value or value in {float("inf"), float("-inf")}:
            raise ValueError("Kimi selected config contains a non-finite number")
        return repr(value)
    if isinstance(value, Sequence) and not isinstance(value, (str, bytes)):
        if any(isinstance(item, Mapping) for item in value):
            raise ValueError("Kimi selected config contains an invalid inline table")
        return "[" + ", ".join(_toml_value(item) for item in value) + "]"
    raise ValueError("Kimi selected config contains an unsupported value")


def _table_name(path: Sequence[str], *, array: bool = False) -> str:
    name = ".".join(_toml_key(part) for part in path)
    return f"[[{name}]]" if array else f"[{name}]"


def _emit_table(
    lines: list[str], path: tuple[str, ...], payload: Mapping[str, Any]
) -> None:
    if path:
        lines.extend(("", _table_name(path)))
    for key, value in payload.items():
        if isinstance(value, Mapping):
            continue
        if (
            isinstance(value, Sequence)
            and not isinstance(value, (str, bytes))
            and any(isinstance(item, Mapping) for item in value)
        ):
            continue
        lines.append(f"{_toml_key(key)} = {_toml_value(value)}")
    for key, value in payload.items():
        if isinstance(value, Mapping):
            _emit_table(lines, path + (key,), value)
        elif (
            isinstance(value, Sequence)
            and not isinstance(value, (str, bytes))
            and any(isinstance(item, Mapping) for item in value)
        ):
            if any(not isinstance(item, Mapping) for item in value):
                raise ValueError("Kimi selected config contains a mixed table array")
            for item in value:
                lines.extend(("", _table_name(path + (key,), array=True)))
                for item_key, item_value in item.items():
                    if isinstance(item_value, Mapping):
                        raise ValueError(
                            "Kimi selected config contains a nested table array"
                        )
                    lines.append(
                        f"{_toml_key(item_key)} = {_toml_value(item_value)}"
                    )


def _serialize_config(payload: Mapping[str, Any]) -> bytes:
    lines: list[str] = []
    _emit_table(lines, (), payload)
    text = "\n".join(lines).lstrip("\n") + "\n"
    try:
        round_trip = _require_tomllib().loads(text)
    except _require_tomllib().TOMLDecodeError as exc:
        raise ValueError("Kimi selected config serialization is invalid") from exc
    if round_trip != payload:
        raise ValueError("Kimi selected config serialization changed the contract")
    return text.encode("utf-8")


def _write_private_config(path: Path, payload: Mapping[str, Any]) -> None:
    raw = _serialize_config(payload)
    descriptor = os.open(
        path,
        os.O_WRONLY | os.O_CREAT | os.O_EXCL | getattr(os, "O_NOFOLLOW", 0),
        0o600,
    )
    with os.fdopen(descriptor, "wb") as stream:
        stream.write(raw)


def _bind_login_state(source_home: Path, private_home: Path) -> dict[Path, Path]:
    bindings: dict[Path, Path] = {}
    for name, expected_directory in (
        ("credentials", True),
        ("oauth", True),
        ("device_id", False),
    ):
        source = source_home / name
        if not os.path.lexists(source):
            continue
        if expected_directory and not source.is_dir():
            raise ValueError(f"Kimi {name} binding source is invalid")
        if not expected_directory and not source.is_file():
            raise ValueError(f"Kimi {name} binding source is invalid")
        destination = private_home / name
        destination.symlink_to(source, target_is_directory=expected_directory)
        bindings[destination] = source
    return bindings


def _verify_login_bindings(bindings: Mapping[Path, Path]) -> None:
    if any(
        not destination.is_symlink()
        or os.readlink(destination) != str(source)
        for destination, source in bindings.items()
    ):
        raise ValueError("Kimi login binding was replaced")


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


def _strict_final_json_object(raw: str) -> Mapping[str, Any]:
    """Accept a bare object or Kimi's exact single JSON fence, never prose."""

    candidate = raw
    fence = re.fullmatch(r"```json\r?\n([\s\S]*)\r?\n```", raw)
    if fence is not None:
        candidate = fence.group(1)
    return _strict_json_object(candidate, "Kimi final assistant text")


def _audit_stream(path: Path) -> tuple[Mapping[str, Any], str]:
    try:
        raw = path.read_bytes()
    except OSError as exc:
        raise ValueError("Kimi event stream is unavailable") from exc
    if not raw or len(raw) > MAX_STREAM_BYTES:
        raise ValueError("Kimi event stream is empty or too large")
    try:
        lines = raw.decode("utf-8").splitlines()
    except UnicodeDecodeError as exc:
        raise ValueError("Kimi event stream is not UTF-8") from exc
    events = [
        _strict_json_object(line, "Kimi event stream")
        for line in lines
        if line.strip()
    ]
    assistant_payloads: list[tuple[int, str]] = []
    resume_payloads: list[tuple[int, str]] = []
    for index, event in enumerate(events):
        role = event.get("role")
        if role == "tool" or event.get("tool_calls"):
            raise ValueError("Kimi event stream contains tool activity")
        if role == "assistant":
            if set(event) - ASSISTANT_FIELDS:
                raise ValueError("Kimi assistant event shape is invalid")
            tool_calls = event.get("tool_calls", [])
            if not isinstance(tool_calls, list):
                raise ValueError("Kimi event stream contains tool activity")
            content = event.get("content")
            if not isinstance(content, str) or not content:
                raise ValueError("Kimi assistant response is invalid")
            assistant_payloads.append((index, content))
        elif role == "meta" and event.get("type") == "session.resume_hint":
            if set(event) != RESUME_FIELDS:
                raise ValueError("Kimi resume event shape is invalid")
            session_id = event.get("session_id")
            if (
                not isinstance(session_id, str)
                or not session_id
                or len(session_id.encode("utf-8")) > 256
                or not isinstance(event.get("command"), str)
                or not event["command"]
                or not isinstance(event.get("content"), str)
                or not event["content"]
            ):
                raise ValueError("Kimi resume event is invalid")
            resume_payloads.append((index, session_id))
        elif role == "meta" and event.get("type") == "turn.step.retrying":
            if set(event) - RETRY_FIELDS:
                raise ValueError("Kimi retry event shape is invalid")
        else:
            raise ValueError("Kimi event stream role is invalid")
    if len(assistant_payloads) != 1:
        raise ValueError("Kimi event stream must contain one assistant response")
    if (
        len(resume_payloads) != 1
        or resume_payloads[0][0] <= assistant_payloads[0][0]
    ):
        raise ValueError("Kimi event stream session binding is invalid")
    return (
        _strict_final_json_object(assistant_payloads[0][1]),
        resume_payloads[0][1],
    )


def invoke_json_no_tools(
    executable: Path,
    *,
    model: str,
    prompt: str,
    timeout_seconds: int,
    environment: Mapping[str, str],
    source_home: Path,
    selected_config: Mapping[str, Any],
) -> tuple[Mapping[str, Any], str]:
    """Run one fresh Kimi session and return its strict payload and session id."""

    if (
        not isinstance(prompt, str)
        or not prompt
        or len(prompt.encode("utf-8")) > provider_probe.MAX_PROVIDER_PROMPT_BYTES
    ):
        raise ValueError("provider prompt is empty or too large")
    source_home = Path(source_home)
    if not source_home.is_absolute():
        raise ValueError("Kimi source home must be absolute")
    frozen_config = _selected_config(selected_config, model)
    if frozen_config != selected_config:
        raise ValueError("Kimi selected config changed after runtime preparation")
    with tempfile.TemporaryDirectory(
        prefix="ccl-skills-kimi-reviewer-calibration-"
    ) as directory:
        session_root = Path(directory)
        session_root.chmod(0o700)
        private_home = session_root / "kimi-home"
        workspace = session_root / "workspace"
        empty_skills = session_root / "empty-skills"
        private_home.mkdir(mode=0o700)
        workspace.mkdir(mode=0o700)
        empty_skills.mkdir(mode=0o700)
        _write_private_config(private_home / "config.toml", frozen_config)
        bindings = _bind_login_state(source_home, private_home)
        session_environment = dict(environment)
        session_environment.update(
            {
                "KIMI_CODE_HOME": str(private_home),
                "KIMI_DISABLE_TELEMETRY": "1",
                "TMPDIR": str(session_root),
            }
        )
        events_path = session_root / "events.jsonl"
        stderr_path = session_root / "stderr.log"
        provider_probe._run_bounded(
            [
                str(executable),
                "--model",
                model,
                "--prompt",
                prompt,
                "--output-format",
                "stream-json",
                "--skills-dir",
                str(empty_skills),
            ],
            cwd=workspace,
            timeout_seconds=timeout_seconds,
            stdout_path=events_path,
            stderr_path=stderr_path,
            environment=session_environment,
        )
        _verify_login_bindings(bindings)
        return _audit_stream(events_path)
