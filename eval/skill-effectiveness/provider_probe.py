#!/usr/bin/env python3
"""Real-provider capability probes for the advisory trial foundation."""

from __future__ import annotations

import json
import hashlib
import os
import re
import secrets
import selectors
import signal
import stat
import subprocess
import tempfile
import threading
import time
from pathlib import Path
from typing import Any, Mapping

import trial


MODEL_PATTERN = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._:/-]{0,127}$")
RESULT_CONTRACT = "skill-effectiveness-provider-capability-result-v1"
RUNNER_CONTRACT = "codex-cli-provider-probe-v1"
MAX_PROVIDER_MESSAGE_BYTES = 16 * 1024
MAX_PROVIDER_PROMPT_BYTES = 128 * 1024
MAX_EVENT_STREAM_BYTES = 64 * 1024
MAX_STDERR_TAIL_BYTES = 4 * 1024
MAX_VERSION_BYTES = 1024
PROVIDER_ENV_ALLOWLIST = {
    "ALL_PROXY",
    "HOME",
    "HTTPS_PROXY",
    "HTTP_PROXY",
    "LANG",
    "LC_ALL",
    "NO_PROXY",
    "OPENAI_API_KEY",
    "PATH",
    "SSL_CERT_DIR",
    "SSL_CERT_FILE",
    "TERM",
    "TMPDIR",
}
PROVIDER_TERMINATION_SIGNALS = (signal.SIGINT, signal.SIGTERM, signal.SIGHUP)


def _validate_model(model: str) -> str:
    if not isinstance(model, str) or MODEL_PATTERN.fullmatch(model) is None:
        raise ValueError("model must be an exact provider model identifier")
    return model


def _resolve_codex(executable: Path) -> Path:
    requested = Path(executable).expanduser()
    if not requested.is_absolute():
        raise ValueError("codex_path must be absolute")
    resolved = requested.resolve(strict=True)
    if not resolved.is_file():
        raise ValueError("codex executable is not a regular file")
    return resolved


def _provider_environment() -> dict[str, str]:
    return {
        key: os.environ[key]
        for key in sorted(PROVIDER_ENV_ALLOWLIST)
        if key in os.environ
    }


def _hash_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        while chunk := stream.read(1024 * 1024):
            digest.update(chunk)
    return "sha256:" + digest.hexdigest()


def _terminate_process_group(process: subprocess.Popen[bytes]) -> None:
    try:
        os.killpg(process.pid, signal.SIGTERM)
    except ProcessLookupError:
        return
    try:
        process.wait(timeout=1)
        return
    except subprocess.TimeoutExpired:
        pass
    try:
        os.killpg(process.pid, signal.SIGKILL)
    except ProcessLookupError:
        return
    process.wait()


def _run_bounded(
    argv: list[str],
    *,
    cwd: Path,
    timeout_seconds: int,
    stdin: bytes | None = None,
    capture_stdout: bool = False,
    stdout_path: Path | None = None,
    stderr_path: Path | None = None,
    environment: Mapping[str, str] | None = None,
    stdout_limit_bytes: int | None = None,
) -> bytes:
    if capture_stdout and stdout_path is not None:
        raise ValueError("stdout capture mode is ambiguous")
    stdout_stream = None
    stderr_stream = None
    process: subprocess.Popen[bytes] | None = None
    previous_signal_handlers: dict[int, Any] = {}
    cleanup_signal_mask: set[signal.Signals] | None = None
    pending_signal: int | None = None

    def exit_on_provider_signal(signum, _frame) -> None:
        nonlocal cleanup_signal_mask, pending_signal
        if pending_signal is None:
            pending_signal = signum
        if process is None:
            return
        cleanup_signal_mask = signal.pthread_sigmask(
            signal.SIG_BLOCK, PROVIDER_TERMINATION_SIGNALS
        )
        for managed_signum in PROVIDER_TERMINATION_SIGNALS:
            signal.signal(managed_signum, signal.SIG_IGN)
        if process.poll() is None:
            _terminate_process_group(process)
        raise SystemExit(128 + pending_signal)

    if stdout_path is not None:
        descriptor = os.open(
            stdout_path,
            os.O_WRONLY | os.O_CREAT | os.O_EXCL | getattr(os, "O_NOFOLLOW", 0),
            0o600,
        )
        stdout_stream = os.fdopen(descriptor, "wb")
    if stderr_path is not None:
        descriptor = os.open(
            stderr_path,
            os.O_WRONLY | os.O_CREAT | os.O_EXCL | getattr(os, "O_NOFOLLOW", 0),
            0o600,
        )
        stderr_stream = os.fdopen(descriptor, "wb")
    try:
        if threading.current_thread() is threading.main_thread():
            for signum in PROVIDER_TERMINATION_SIGNALS:
                previous_signal_handlers[signum] = signal.getsignal(signum)
                signal.signal(signum, exit_on_provider_signal)
        if pending_signal is not None:
            raise SystemExit(128 + pending_signal)
        try:
            process = subprocess.Popen(
                argv,
                cwd=cwd,
                stdin=subprocess.PIPE if stdin is not None else subprocess.DEVNULL,
                stdout=(
                    subprocess.PIPE
                    if capture_stdout or stdout_stream is not None
                    else subprocess.DEVNULL
                ),
                stderr=(
                    subprocess.PIPE if stderr_stream is not None else subprocess.DEVNULL
                ),
                env=dict(environment) if environment is not None else None,
                start_new_session=True,
            )
        except BaseException:
            if pending_signal is not None:
                raise SystemExit(128 + pending_signal) from None
            raise
        if pending_signal is not None:
            exit_on_provider_signal(pending_signal, None)
        if stdin is not None and process.stdin is not None:
            try:
                process.stdin.write(stdin)
                process.stdin.flush()
            except BrokenPipeError:
                pass
            finally:
                process.stdin.close()
        stdout_buffer = bytearray()
        stdout_count = 0
        stderr_count = 0
        deadline = time.monotonic() + timeout_seconds
        selector = selectors.DefaultSelector()
        if process.stdout is not None:
            selector.register(process.stdout, selectors.EVENT_READ, "stdout")
        if process.stderr is not None:
            selector.register(process.stderr, selectors.EVENT_READ, "stderr")
        try:
            while selector.get_map():
                remaining = deadline - time.monotonic()
                if remaining <= 0:
                    raise subprocess.TimeoutExpired(argv, timeout_seconds)
                ready = selector.select(remaining)
                if not ready:
                    raise subprocess.TimeoutExpired(argv, timeout_seconds)
                for key, _ in ready:
                    chunk = os.read(key.fileobj.fileno(), 8192)
                    if not chunk:
                        selector.unregister(key.fileobj)
                        key.fileobj.close()
                        continue
                    if key.data == "stdout":
                        stdout_count += len(chunk)
                        stdout_limit = stdout_limit_bytes or (
                            MAX_VERSION_BYTES
                            if capture_stdout
                            else MAX_EVENT_STREAM_BYTES
                        )
                        if stdout_count > stdout_limit:
                            raise ValueError("provider stdout exceeded limit")
                        if stdout_stream is not None:
                            stdout_stream.write(chunk)
                        else:
                            stdout_buffer.extend(chunk)
                    else:
                        stderr_count += len(chunk)
                        if stderr_count > MAX_STDERR_TAIL_BYTES:
                            raise ValueError("provider stderr exceeded limit")
                        stderr_stream.write(chunk)
            remaining = deadline - time.monotonic()
            if remaining <= 0:
                raise subprocess.TimeoutExpired(argv, timeout_seconds)
            process.wait(timeout=remaining)
        except subprocess.TimeoutExpired as exc:
            raise ValueError("provider process timed out") from exc
        except ValueError:
            raise
        finally:
            selector.close()
        if process.returncode != 0:
            if stdout_stream is not None:
                stdout_stream.flush()
            if stderr_stream is not None:
                stderr_stream.flush()
            reason = _classify_provider_failure(
                stderr_path=stderr_path,
                stdout_path=stdout_path,
            )
            raise ValueError(
                f"provider process failed: {reason} (exit code {process.returncode})"
            )
        return bytes(stdout_buffer)
    except BaseException:
        if process is not None and process.poll() is None:
            _terminate_process_group(process)
        raise
    finally:
        for signum, handler in previous_signal_handlers.items():
            signal.signal(signum, handler)
        if cleanup_signal_mask is not None:
            signal.pthread_sigmask(signal.SIG_SETMASK, cleanup_signal_mask)
        if stdout_stream is not None:
            stdout_stream.close()
        if stderr_stream is not None:
            stderr_stream.close()


def _classify_provider_failure(
    *, stderr_path: Path | None, stdout_path: Path | None
) -> str:
    chunks = []
    for path in (stderr_path, stdout_path):
        if path is None:
            continue
        with path.open("rb") as stream:
            chunks.append(stream.read(MAX_EVENT_STREAM_BYTES))
    text = b"\n".join(chunks).decode("utf-8", "replace").lower()
    if "unexpected argument" in text or "unrecognized option" in text:
        return "unsupported_flag"
    if "invalid_json_schema" in text or "invalid schema" in text:
        return "invalid_schema"
    if "unauthorized" in text or "authentication" in text or "login" in text:
        return "auth_unavailable"
    if (
        "429" in text
        or "rate limit" in text
        or "quota" in text
        or "usage limit" in text
        or "purchase more credits" in text
    ):
        return "quota_unavailable"
    if "operation not permitted" in text or "permission denied" in text:
        return "permission_denied"
    return "provider_error"


def _codex_version(
    executable: Path,
    cwd: Path,
    timeout_seconds: int,
    environment: Mapping[str, str],
) -> str:
    raw = _run_bounded(
        [str(executable), "--version"],
        cwd=cwd,
        timeout_seconds=min(timeout_seconds, 10),
        capture_stdout=True,
        environment=environment,
    )
    if len(raw) > MAX_VERSION_BYTES:
        raise ValueError("provider CLI version output is too large")
    try:
        version = raw.decode("utf-8").strip()
    except UnicodeDecodeError as exc:
        raise ValueError("provider CLI version output is not UTF-8") from exc
    if not version or "\n" in version or "\r" in version:
        raise ValueError("provider CLI version output is invalid")
    return version


def _parse_provider_message(message: str) -> Mapping[str, Any]:
    if len(message.encode("utf-8")) > MAX_PROVIDER_MESSAGE_BYTES:
        raise ValueError("provider last message is too large")
    try:
        payload = json.loads(message)
    except json.JSONDecodeError as exc:
        raise ValueError("provider last message is invalid JSON") from exc
    if not isinstance(payload, Mapping):
        raise ValueError("provider last message must be a JSON object")
    return payload


def _audit_codex_events(path: Path) -> str:
    try:
        path_stat = path.lstat()
    except FileNotFoundError as exc:
        raise ValueError("provider event stream is missing") from exc
    if not stat.S_ISREG(path_stat.st_mode):
        raise ValueError("provider event stream is not a regular file")
    if path_stat.st_size > MAX_EVENT_STREAM_BYTES:
        raise ValueError("provider event stream is too large")
    try:
        lines = path.read_bytes().decode("utf-8").splitlines()
    except UnicodeDecodeError as exc:
        raise ValueError("provider event stream is not UTF-8") from exc
    allowed_items = {"agent_message", "reasoning"}
    allowed_item_events = {"item.started", "item.updated", "item.completed"}
    allowed_lifecycle_events = {"thread.started", "turn.started", "turn.completed"}
    failed_lifecycle_events = {"turn.failed", "turn.cancelled", "error"}
    completed_messages: list[str] = []
    saw_completed_turn = False
    for raw_line in lines:
        if not raw_line.strip():
            continue
        try:
            event = json.loads(raw_line)
        except json.JSONDecodeError as exc:
            raise ValueError("provider event stream contains invalid JSON") from exc
        if not isinstance(event, Mapping):
            raise ValueError("provider event stream contains a non-object event")
        event_type = event.get("type")
        if event_type == "turn.completed":
            saw_completed_turn = True
        item = event.get("item")
        if not isinstance(item, Mapping):
            if event_type in failed_lifecycle_events:
                raise ValueError("provider event stream reports a failed lifecycle")
            if event_type in allowed_lifecycle_events:
                continue
            raise ValueError("provider event stream crossed the tool boundary")
        if event_type not in allowed_item_events:
            raise ValueError("provider event stream contains an unknown item event")
        item_type = item.get("type")
        if item_type == "error":
            raise ValueError("provider event stream reports an item error")
        if item_type not in allowed_items:
            raise ValueError("provider event stream contains tool activity")
        if event_type == "item.completed" and item_type == "agent_message":
            message = item.get("text")
            if not isinstance(message, str) or not message.strip():
                raise ValueError("provider completed message is empty")
            completed_messages.append(message)
    if len(completed_messages) != 1 or not saw_completed_turn:
        raise ValueError("provider event stream lacks positive completion evidence")
    return completed_messages[0]


def _phase_schema(phase: str) -> dict[str, Any]:
    response_field = "canary_received" if phase == "seed" else "prior_canary"
    response_schema: dict[str, Any]
    if phase == "seed":
        response_schema = {"type": "string"}
    else:
        response_schema = {
            "anyOf": [
                {"type": "string"},
                {"type": "null"},
            ]
        }
    return {
        "type": "object",
        "additionalProperties": False,
        "required": ["protocol_version", "phase", response_field],
        "properties": {
            "protocol_version": {"type": "integer", "enum": [1]},
            "phase": {"type": "string", "enum": [phase]},
            response_field: response_schema,
        },
    }


def _validate_phase_response(
    payload: Mapping[str, Any], phase: str, canary: str
) -> None:
    response_field = "canary_received" if phase == "seed" else "prior_canary"
    if set(payload) != {"protocol_version", "phase", response_field}:
        raise ValueError(f"provider {phase} response field set is invalid")
    if payload.get("protocol_version") != 1 or payload.get("phase") != phase:
        raise ValueError(f"provider {phase} response contract is invalid")
    response = payload.get(response_field)
    if phase == "seed" and response != canary:
        raise ValueError("provider did not acknowledge the seed canary")
    if phase == "recall" and response is not None and not isinstance(response, str):
        raise ValueError("provider recall response is not null or a string")


def invoke_codex_json_readonly(
    executable: Path,
    *,
    model: str,
    prompt: str,
    schema: Mapping[str, Any],
    timeout_seconds: int,
    environment: Mapping[str, str],
    session_prefix: str,
) -> Mapping[str, Any]:
    """Run one fresh, tool-free Codex session and return its JSON response."""

    if not isinstance(prompt, str) or not prompt:
        raise ValueError("provider prompt must be non-empty")
    if len(prompt.encode("utf-8")) > MAX_PROVIDER_PROMPT_BYTES:
        raise ValueError("provider prompt is too large")
    if not re.fullmatch(r"[a-z0-9-]{1,48}", session_prefix):
        raise ValueError("provider session prefix is invalid")
    if not isinstance(schema, Mapping):
        raise ValueError("provider response schema must be an object")
    with tempfile.TemporaryDirectory(
        prefix=f"ccl-skills-{session_prefix}-"
    ) as directory:
        session_root = Path(directory)
        session_root.chmod(0o700)
        schema_path = session_root / "response.schema.json"
        events_path = session_root / "events.jsonl"
        stderr_path = session_root / "stderr.log"
        session_environment = dict(environment)
        session_environment["TMPDIR"] = str(session_root)
        trial.write_json_atomic(schema_path, dict(schema))
        argv = [
            str(executable),
            "exec",
            "--ephemeral",
            "--ignore-user-config",
            "--skip-git-repo-check",
            "--sandbox",
            "read-only",
            "--color",
            "never",
            "--json",
            "--model",
            model,
            "--output-schema",
            str(schema_path),
            "-",
        ]
        _run_bounded(
            argv,
            cwd=session_root,
            timeout_seconds=timeout_seconds,
            stdin=prompt.encode("utf-8"),
            stdout_path=events_path,
            stderr_path=stderr_path,
            environment=session_environment,
        )
        message = _audit_codex_events(events_path)
        return dict(_parse_provider_message(message))


def _invoke_codex_phase(
    executable: Path,
    *,
    model: str,
    phase: str,
    canary: str,
    timeout_seconds: int,
    environment: Mapping[str, str],
) -> Mapping[str, Any]:
    if phase == "seed":
        prompt = (
            "SEED SESSION. This is an isolation canary, not a user task. "
            f"CANARY={canary} Return only the JSON object required by the schema, "
            "including the exact canary in canary_received."
        )
    else:
        prompt = (
            "RECALL SESSION. This is a fresh isolation probe. Return only the JSON "
            "object required by the schema. If you can recall an exact 64-character "
            "hex canary from a prior session, put it in prior_canary; otherwise use null."
        )
    payload = invoke_codex_json_readonly(
        executable,
        model=model,
        prompt=prompt,
        schema=_phase_schema(phase),
        timeout_seconds=timeout_seconds,
        environment=environment,
        session_prefix=f"codex-{phase}",
    )
    _validate_phase_response(payload, phase, canary)
    return dict(payload)


def _capability_entry(
    *,
    model: str,
    cli_version: str,
    executable_hash: str,
    canary_hash: str,
    cross_session_recall_detected: bool,
    task_family: str,
) -> dict[str, Any]:
    canary_digest = canary_hash.removeprefix("sha256:")
    evidence = {
        "mount_boundary": {
            "probe_id": "codex-read-only-sandbox-v1",
            "status": "unverified",
            "observations": {
                "outside_read_denied": False,
                "outside_write_denied": False,
            },
        },
        "access_audit": {
            "probe_id": "codex-access-audit-unavailable-v1",
            "status": "unverified",
            "observations": {
                "all_accesses_recorded": False,
                "tamper_check_passed": False,
            },
        },
        "memory_isolation": {
            "probe_id": f"codex-cross-session-canary-{canary_digest}",
            "status": (
                "contaminated" if cross_session_recall_detected else "unverified"
            ),
            "observations": {
                "fresh_session": True,
                "cross_session_recall_detected": cross_session_recall_detected,
            },
        },
    }
    runner_identity = trial.canonical_hash(
        {
            "cli_version": cli_version,
            "executable_hash": executable_hash,
        }
    )[7:19]
    entry = {
        "runner": f"{RUNNER_CONTRACT}-{runner_identity}",
        "provider": f"codex/{model}",
        "task_family": task_family,
        "evidence": evidence,
    }
    entry["evidence_hash"] = trial.canonical_hash(entry)
    return entry


def run_codex_probe(
    *,
    codex_path: Path,
    model: str,
    task_family: str,
    output_root: Path,
    timeout_seconds: int,
) -> dict[str, Any]:
    """Run a two-session Codex canary and persist an advisory capability matrix."""

    model = _validate_model(model)
    if task_family not in trial.TASK_FAMILIES:
        raise ValueError("task_family is invalid")
    if isinstance(timeout_seconds, bool) or not 1 <= timeout_seconds <= 600:
        raise ValueError("timeout_seconds must be between 1 and 600")
    trial.ensure_private_directory(output_root)
    lock_path = output_root / ".provider-probe.lock"
    try:
        lock_descriptor = os.open(
            lock_path,
            os.O_WRONLY | os.O_CREAT | os.O_EXCL | getattr(os, "O_NOFOLLOW", 0),
            0o600,
        )
    except FileExistsError as exc:
        raise ValueError("provider probe output root is already claimed") from exc
    os.close(lock_descriptor)
    report_path = output_root / "provider-probe-result.json"
    artifact_path = output_root / f"capability-probe-{task_family}.json"
    for path in (report_path, artifact_path):
        if path.exists() or path.is_symlink():
            raise ValueError(f"provider probe output already exists: {path.name}")

    executable = _resolve_codex(codex_path)
    environment = _provider_environment()
    executable_hash = _hash_file(executable)
    cli_version = _codex_version(executable, output_root, timeout_seconds, environment)
    canary = secrets.token_hex(32)
    seed_response = _invoke_codex_phase(
        executable,
        model=model,
        phase="seed",
        canary=canary,
        timeout_seconds=timeout_seconds,
        environment=environment,
    )
    recall_response = _invoke_codex_phase(
        executable,
        model=model,
        phase="recall",
        canary=canary,
        timeout_seconds=timeout_seconds,
        environment=environment,
    )
    recalled_value = recall_response["prior_canary"]
    recall_detected = recalled_value is not None
    canary_hash = trial.canonical_hash(canary)
    entry = _capability_entry(
        model=model,
        cli_version=cli_version,
        executable_hash=executable_hash,
        canary_hash=canary_hash,
        cross_session_recall_detected=recall_detected,
        task_family=task_family,
    )
    artifact = trial.write_capability_probe_artifact(artifact_path, entry)
    matrix = trial.assess_capability_matrix_from_artifacts([artifact_path])
    report = {
        "schema_version": 1,
        "artifact_contract": RESULT_CONTRACT,
        "execution_status": "completed",
        "provider": "codex",
        "provider_cli_version": cli_version,
        "provider_executable_hash": executable_hash,
        "provider_environment_keys": sorted(environment),
        "model": model,
        "task_family": task_family,
        "runner_contract": RUNNER_CONTRACT,
        "requested_session_mode": "ephemeral",
        "provider_persistence_declaration": "unverified",
        "isolation_outcome": (
            "contaminated" if recall_detected else "unresolved_isolation_threat"
        ),
        "cross_trial_canary": {
            "canary_hash": canary_hash,
            "seed_acknowledged": seed_response["canary_received"] == canary,
            "recall_probe_completed": True,
            "cross_session_recall_detected": recall_detected,
            "recalled_value_hash": (
                trial.canonical_hash(recalled_value)
                if recalled_value is not None
                else None
            ),
        },
        "capability_artifact": {
            "path": artifact_path.name,
            "entry_hash": artifact["entry_hash"],
        },
        "capability_matrix": matrix,
        "conclusion_boundary": "provider_capability_only_not_skill_effectiveness",
        "security_review_status": "pending-dedicated-review",
    }
    trial.write_json_atomic(report_path, report)
    persisted = trial.load_private_json(report_path)
    if persisted != report:
        raise ValueError("provider probe report read-back mismatch")
    return report
