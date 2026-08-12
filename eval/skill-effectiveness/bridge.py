#!/usr/bin/env python3
"""Deterministic process bridge for one external trial controller.

This is the only cross-repository surface of the skill-effectiveness
foundation.  It reads one JSON request from stdin, reuses `trial.py`, and writes
one JSON response to stdout.  It does not call a model, select a provider, start
a shell, open a socket, modify skills, or decide that a candidate is effective.

Evidence limits, stated where a reader looks before citing this:

* The pinned runtime manifest proves the bytes of every enumerated evaluator
  code and configuration file at spawn.  It does not intercept arbitrary reads
  performed by an imported module, so it is a closure declaration plus a byte
  check, not a sandbox.
* A returned `ok` proves the deterministic action completed, never that a trial
  is isolated, a reviewer is calibrated, or a profile improves anything.
* Reason codes are a closed set and never carry a path, prompt, task content,
  model output, or source text.
"""

from __future__ import annotations

import hashlib
import importlib.util
import json
import os
import re
import stat
import sys
from pathlib import Path
from typing import Any, Mapping


HERE = Path(__file__).resolve().parent
SOURCE_CHECKOUT = HERE.parents[1]
PROTOCOL_REVISION = "skill-effectiveness.bridge.v1"
REQUEST_SCHEMA = "skill-effectiveness.bridge.request.v1"
RESPONSE_SCHEMA = "skill-effectiveness.bridge.response.v1"
RECEIPT_CONTRACT = "skill-effectiveness-bridge-receipt-v1"
SUPPORTED_ACTIONS = ("probe", "prepare", "checkpoint", "evaluate")
REASON_CODES = (
    "artifact_mismatch",
    "artifact_missing",
    "cancelled",
    "capability_unavailable",
    "causal_core_unavailable",
    "cost_policy_exceeded",
    "cost_policy_required",
    "evidence_invalid",
    "invocation_unverifiable",
    "isolation_violation",
    "no_progress",
    "protocol_mismatch",
    "reviewer_calibration_failed",
    "stale_state",
    "timeout",
    "trial_budget_exceeded",
    "unknown_finality",
    "unsupported_evaluator",
)
# The closure the manifest governs: every evaluator code and configuration file
# this bridge or `trial.py` may read from the checkout.  `active_control.py` is
# listed because `trial.py` can reach it through a lazy import.
MANIFEST_PATHS = (
    "active_control.py",
    "bridge.py",
    "pilot-gates.json",
    "profile-arms/profile-full.json",
    "profile-arms/profile-off.json",
    "profile-arms/profile-reference.json",
    "protocol/request-v1.schema.json",
    "protocol/response-v1.schema.json",
    "trial.py",
)
PINNED_MODULES = {"trial.py": "trial", "active_control.py": "active_control"}
REQUEST_FIELDS = {"schema", "request_id", "action", "artifact_root", "payload"}
SAFE_REQUEST_ID = re.compile(r"^[A-Za-z0-9._-]{1,128}$")
REDACTED_REQUEST_ID = "redacted-invalid-request-id"
MAX_REQUEST_BYTES = 1_048_576
MAX_RESPONSE_BYTES = 1_048_576
EXIT_OK = 0
EXIT_INVALID = 2
EXIT_BLOCKED = 3
EXIT_INTERNAL = 4


class BridgeError(Exception):
    """A typed, payload-free failure with its own exit code."""

    exit_code = EXIT_INVALID

    def __init__(self, reason_code: str, detail: str = "") -> None:
        if reason_code not in REASON_CODES:
            raise AssertionError(f"undeclared reason code: {reason_code}")
        super().__init__(reason_code)
        self.reason_code = reason_code
        self.detail = detail


class InvalidRequest(BridgeError):
    exit_code = EXIT_INVALID


class Blocked(BridgeError):
    exit_code = EXIT_BLOCKED


class InternalFailure(BridgeError):
    exit_code = EXIT_INTERNAL


def canonical_json(value: Any) -> bytes:
    return json.dumps(
        value,
        ensure_ascii=False,
        sort_keys=True,
        separators=(",", ":"),
        allow_nan=False,
    ).encode("utf-8")


def canonical_hash(value: Any) -> str:
    if isinstance(value, bytes):
        payload = value
    elif isinstance(value, str):
        payload = value.encode("utf-8")
    else:
        payload = canonical_json(value)
    return "sha256:" + hashlib.sha256(payload).hexdigest()


def _reject_shared_write_access(path: Path, reason_code: str) -> os.stat_result:
    """Fail closed unless one regular non-symlink file is owner-private."""

    try:
        info = path.lstat()
    except OSError as exc:
        raise Blocked(reason_code, "manifest entry is unreadable") from exc
    if stat.S_ISLNK(info.st_mode) or not stat.S_ISREG(info.st_mode):
        raise Blocked(reason_code, "manifest entry is not a regular file")
    if info.st_mode & (stat.S_IWGRP | stat.S_IWOTH):
        raise Blocked(reason_code, "manifest entry is group or world writable")
    return info


def _interpreter_identity() -> dict[str, Any]:
    configured = Path(sys.executable)
    resolved = configured.resolve(strict=False)
    info = _reject_shared_write_access(resolved, "unsupported_evaluator")
    # Deviation from the plan text, recorded in the Slice 1 validation log: the
    # interpreter may be owned by the local user or by root.  A root-owned
    # system interpreter is not attacker-writable, and requiring local-user
    # ownership would reject every standard system installation.
    if info.st_uid not in {os.getuid(), 0}:
        raise Blocked("unsupported_evaluator", "interpreter owner is untrusted")
    return {
        "configured_executable": str(configured),
        "resolved_executable": str(resolved),
        "version": "{}.{}.{}".format(*sys.version_info[:3]),
        "implementation": sys.implementation.name,
        "user_site_disabled": bool(sys.flags.no_user_site),
    }


def _manifest_entry(relative_path: str) -> dict[str, Any]:
    path = HERE / relative_path
    info = _reject_shared_write_access(path, "unsupported_evaluator")
    if info.st_uid != os.getuid():
        raise Blocked("unsupported_evaluator", "manifest entry owner is untrusted")
    payload = path.read_bytes()
    return {
        "path": relative_path,
        "sha256": "sha256:" + hashlib.sha256(payload).hexdigest(),
        "size": len(payload),
    }


def _local_runtime_manifest() -> dict[str, Any]:
    """Enumerate and hash the closure as bytes; import nothing."""

    entries = [_manifest_entry(relative) for relative in MANIFEST_PATHS]
    core = {"schema_version": 1, "entries": entries}
    return {**core, "manifest_hash": canonical_hash(core)}


def _verify_pinned_manifest(pinned: Any) -> dict[str, Any]:
    local = _local_runtime_manifest()
    if not isinstance(pinned, Mapping) or set(pinned) != {
        "schema_version",
        "entries",
        "manifest_hash",
    }:
        raise Blocked("unsupported_evaluator", "pinned manifest field set is invalid")
    if pinned.get("schema_version") != 1:
        raise Blocked("unsupported_evaluator", "pinned manifest version is invalid")
    if pinned.get("manifest_hash") != local["manifest_hash"]:
        raise Blocked("unsupported_evaluator", "pinned manifest does not match disk")
    core = {"schema_version": 1, "entries": pinned.get("entries")}
    if canonical_hash(core) != local["manifest_hash"]:
        raise Blocked("unsupported_evaluator", "pinned manifest hash is inconsistent")
    return local


def _load_pinned_modules() -> Any:
    """Load `trial.py` by absolute path so no ambient package can replace it."""

    module_name = "skill_effectiveness_bridge_trial"
    spec = importlib.util.spec_from_file_location(module_name, HERE / "trial.py")
    if spec is None or spec.loader is None:
        raise InternalFailure("unsupported_evaluator", "trial runtime is unloadable")
    module = importlib.util.module_from_spec(spec)
    sys.modules[module_name] = module
    spec.loader.exec_module(module)
    return module


def _loaded_checkout_modules() -> list[str]:
    loaded = set()
    for module in list(sys.modules.values()):
        origin = getattr(module, "__file__", None)
        if not origin:
            continue
        try:
            relative = Path(origin).resolve().relative_to(HERE)
        except (ValueError, OSError):
            continue
        loaded.add(str(relative))
    return sorted(loaded)


def _configuration(trial: Any) -> dict[str, Any]:
    gates = json.loads((HERE / "pilot-gates.json").read_text(encoding="utf-8"))
    templates = {}
    for relative in MANIFEST_PATHS:
        if not relative.startswith("profile-arms/"):
            continue
        template = json.loads((HERE / relative).read_text(encoding="utf-8"))
        templates[template["arm_id"]] = trial.canonical_hash(template)
    return {
        "pilot_gates_hash": trial.canonical_hash(gates),
        "profile_arm_templates": templates,
        "registry_schemas": sorted(
            {trial.SKILL_CONTENT_REGISTRY_SCHEMA, trial.PROFILE_REGISTRY_SCHEMA}
        ),
        "evidence_tiers": sorted(trial.EVIDENCE_TIERS),
        "advisory_waivable_items": sorted(trial.ADVISORY_WAIVABLE_ITEMS),
        "checkpoint_evidence_tiers": {
            registry_schema: trial.checkpoint_evidence_tier(registry_schema)
            for registry_schema in (
                trial.PROFILE_REGISTRY_SCHEMA,
                trial.SKILL_CONTENT_REGISTRY_SCHEMA,
            )
        },
        "profile_arm_registry_plan_contract": (
            trial.PROFILE_ARM_REGISTRY_PLAN_CONTRACT
        ),
    }


def _require_object(value: Any, reason_code: str, label: str) -> Mapping[str, Any]:
    if not isinstance(value, Mapping):
        raise InvalidRequest(reason_code, f"{label} must be an object")
    return value


def _require_fields(
    payload: Mapping[str, Any],
    required: set[str],
    optional: set[str],
    label: str,
) -> None:
    missing = required - set(payload)
    extra = set(payload) - (required | optional)
    if missing or extra:
        raise InvalidRequest("protocol_mismatch", f"{label} field set is invalid")


def _validated_artifact_root(raw: Any) -> Path:
    if not isinstance(raw, str) or not raw:
        raise Blocked("evidence_invalid", "artifact_root is required for this action")
    root = Path(raw)
    if not root.is_absolute():
        raise Blocked("evidence_invalid", "artifact_root must be absolute")
    if root.is_symlink():
        raise Blocked("evidence_invalid", "artifact_root must not be a symlink")
    resolved = root.expanduser().resolve(strict=False)
    for outer, inner in ((SOURCE_CHECKOUT, resolved), (resolved, SOURCE_CHECKOUT)):
        try:
            inner.relative_to(outer)
        except ValueError:
            continue
        raise Blocked("evidence_invalid", "artifact_root overlaps the source checkout")
    if not resolved.is_dir():
        raise Blocked("evidence_invalid", "artifact_root must be an existing directory")
    return resolved


def _validated_relative_path(root: Path, raw: Any, label: str) -> Path:
    if not isinstance(raw, str) or not raw:
        raise Blocked("evidence_invalid", f"{label} is required")
    candidate = Path(raw)
    if candidate.is_absolute() or any(
        part in {"", ".", ".."} for part in candidate.parts
    ):
        raise Blocked("evidence_invalid", f"{label} must be a safe relative path")
    resolved = (root / candidate).resolve(strict=False)
    try:
        resolved.relative_to(root)
    except ValueError as exc:
        raise Blocked("evidence_invalid", f"{label} escapes the artifact root") from exc
    return resolved


def _receipt_path(root: Path, request_id: str) -> Path:
    return root / "bridge-receipts" / f"{request_id}.json"


def _load_receipt(path: Path) -> dict[str, Any] | None:
    if not path.exists():
        return None
    try:
        stored = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, ValueError) as exc:
        raise InternalFailure("artifact_mismatch", "receipt is unreadable") from exc
    if (
        not isinstance(stored, Mapping)
        or stored.get("artifact_contract") != RECEIPT_CONTRACT
    ):
        raise InternalFailure("artifact_mismatch", "receipt contract is invalid")
    return dict(stored)


def _store_receipt(path: Path, payload: Mapping[str, Any]) -> None:
    path.parent.mkdir(mode=0o700, parents=True, exist_ok=True)
    temporary = path.with_name(path.name + ".partial")
    descriptor = os.open(
        temporary, os.O_WRONLY | os.O_CREAT | os.O_TRUNC | os.O_NOFOLLOW, 0o600
    )
    with os.fdopen(descriptor, "wb") as handle:
        handle.write(canonical_json(payload))
        handle.flush()
        os.fsync(handle.fileno())
    os.replace(temporary, path)


def _probe(request: Mapping[str, Any]) -> tuple[dict[str, Any], dict[str, Any]]:
    if request.get("artifact_root") is not None:
        raise InvalidRequest("protocol_mismatch", "probe takes no artifact_root")
    payload = _require_object(request.get("payload"), "protocol_mismatch", "payload")
    _require_fields(payload, {"phase"}, {"pinned_manifest"}, "probe payload")
    phase = payload.get("phase")
    interpreter = _interpreter_identity()
    if phase == "manifest":
        if "pinned_manifest" in payload:
            raise InvalidRequest(
                "protocol_mismatch", "the first probe accepts no pinned manifest"
            )
        manifest = _local_runtime_manifest()
        binding = {
            "protocol_revision": PROTOCOL_REVISION,
            "phase": "manifest",
            "bridge_hash": next(
                entry["sha256"]
                for entry in manifest["entries"]
                if entry["path"] == "bridge.py"
            ),
            "manifest_hash": manifest["manifest_hash"],
            "interpreter": interpreter,
        }
        return binding, {"phase": "manifest", "runtime_manifest": manifest}
    if phase != "full":
        raise InvalidRequest("protocol_mismatch", "probe phase is invalid")
    if "pinned_manifest" not in payload:
        raise InvalidRequest(
            "protocol_mismatch", "the second probe requires the pinned manifest"
        )
    manifest = _verify_pinned_manifest(payload.get("pinned_manifest"))
    trial = _load_pinned_modules()
    if trial.canonical_hash({"probe": "self-check"}) != canonical_hash(
        {"probe": "self-check"}
    ):
        raise Blocked("unsupported_evaluator", "canonical hashing disagrees")
    configuration = _configuration(trial)
    binding = {
        "protocol_revision": PROTOCOL_REVISION,
        "phase": "full",
        "bridge_hash": next(
            entry["sha256"]
            for entry in manifest["entries"]
            if entry["path"] == "bridge.py"
        ),
        "manifest_hash": manifest["manifest_hash"],
        "configuration_hash": canonical_hash(configuration),
        "interpreter": interpreter,
    }
    result = {
        "phase": "full",
        "supported_actions": list(SUPPORTED_ACTIONS),
        "reason_codes": list(REASON_CODES),
        "configuration": configuration,
        "loaded_checkout_modules": _loaded_checkout_modules(),
    }
    return binding, result


def _action_binding(trial: Any) -> dict[str, Any]:
    manifest = _local_runtime_manifest()
    return {
        "protocol_revision": PROTOCOL_REVISION,
        "phase": "full",
        "bridge_hash": next(
            entry["sha256"]
            for entry in manifest["entries"]
            if entry["path"] == "bridge.py"
        ),
        "manifest_hash": manifest["manifest_hash"],
        "configuration_hash": canonical_hash(_configuration(trial)),
        "interpreter": _interpreter_identity(),
    }


def _bound_manifest(trial: Any, payload: Mapping[str, Any]) -> Mapping[str, Any]:
    manifest = _require_object(
        payload.get("manifest"), "evidence_invalid", "arm manifest"
    )
    declared = payload.get("registry_schema")
    try:
        actual = trial.manifest_registry_schema(manifest)
    except ValueError as exc:
        raise Blocked("evidence_invalid", "arm registry schema is unsupported") from exc
    if declared != actual:
        raise Blocked(
            "evidence_invalid", "plan and manifest name different registry contracts"
        )
    return manifest


def _prepare(trial: Any, root: Path, payload: Mapping[str, Any]) -> dict[str, Any]:
    _require_fields(
        payload,
        {"registry_schema", "task", "manifest", "runtime", "budget", "sample_index"},
        {
            "expected_isolation_evidence",
            "expected_read_allow_roots",
            "expected_write_allow_roots",
        },
        "prepare payload",
    )
    manifest = _bound_manifest(trial, payload)
    trials_root = root / "trials"
    trial.ensure_private_directory(trials_root)
    try:
        artifact = trial.prepare_trial(
            trials_root,
            payload["task"],
            manifest,
            payload["runtime"],
            payload["budget"],
            payload["sample_index"],
            expected_isolation_evidence=payload.get("expected_isolation_evidence"),
            expected_read_allow_roots=payload.get("expected_read_allow_roots", ()),
            expected_write_allow_roots=payload.get("expected_write_allow_roots", ()),
        )
    except ValueError as exc:
        raise Blocked("evidence_invalid", "trial preparation rejected the plan") from exc
    trial_path = "{}/{}/sample-{:03d}".format(
        payload["task"]["task_id"], manifest["arm_id"], payload["sample_index"]
    )
    # `trial_dir` is dropped on purpose: the response carries the caller-relative
    # location only, never an absolute private-store path.
    return {
        "trial_path": trial_path,
        "mode": artifact["mode"],
        "state_version": artifact["state_version"],
    }


def _checkpoint(trial: Any, root: Path, payload: Mapping[str, Any]) -> dict[str, Any]:
    is_completion = payload.get("status") == "completed"
    completion_declarations = (
        {"access_audit_complete", "access_roots_enforced"}
        if is_completion
        else set()
    )
    _require_fields(
        payload,
        {"trial_path", "status"} | completion_declarations,
        {
            "resume_cursor",
            "stop_reason",
            "isolation_evidence",
            "read_allow_roots",
            "write_allow_roots",
            "expected_state_version",
            "access_audit_complete",
            "access_roots_enforced",
        },
        "checkpoint payload",
    )
    if is_completion and any(
        not isinstance(payload[field], bool)
        for field in ("access_audit_complete", "access_roots_enforced")
    ):
        raise Blocked(
            "evidence_invalid",
            "completion audit declarations must be boolean",
        )
    trial_dir = _validated_relative_path(
        root / "trials", payload.get("trial_path"), "trial_path"
    )
    if not trial_dir.is_dir():
        raise Blocked("artifact_missing", "trial artifact directory is absent")
    try:
        trial_artifact = trial.load_private_json(trial_dir / "trial.json")
        registry_schema = trial_artifact.get("registry_schema")
        evidence_tier = (
            None
            if registry_schema is None and not is_completion
            else trial.checkpoint_evidence_tier(registry_schema)
        )
    except (OSError, ValueError) as exc:
        raise Blocked(
            "evidence_invalid",
            "checkpoint evidence contract is invalid",
        ) from exc
    try:
        state_version = trial.checkpoint_trial(
            trial_dir,
            payload["status"],
            payload.get("resume_cursor"),
            payload.get("stop_reason"),
            isolation_evidence=payload.get("isolation_evidence"),
            read_allow_roots=payload.get("read_allow_roots", ()),
            write_allow_roots=payload.get("write_allow_roots", ()),
            expected_state_version=payload.get("expected_state_version"),
            evidence_tier=evidence_tier,
            access_audit_complete=(
                payload["access_audit_complete"] if is_completion else False
            ),
            access_roots_enforced=(
                payload["access_roots_enforced"] if is_completion else False
            ),
        )
    except ValueError as exc:
        raise Blocked("stale_state", "checkpoint transition was rejected") from exc
    coverage_limitations = None
    if is_completion:
        try:
            completed_artifact = trial.load_private_json(trial_dir / "trial.json")
            completion_isolation = completed_artifact.get("completion_isolation")
            if not isinstance(completion_isolation, Mapping):
                raise ValueError("completion isolation evidence is missing")
            persisted_limitations = completion_isolation.get("coverage_limitations")
            if not isinstance(persisted_limitations, list) or any(
                not isinstance(item, str) for item in persisted_limitations
            ):
                raise ValueError("completion limitations are invalid")
            coverage_limitations = list(persisted_limitations)
        except (OSError, ValueError) as exc:
            raise Blocked(
                "evidence_invalid",
                "completed checkpoint evidence is invalid",
            ) from exc
    return {
        "state_version": state_version,
        "evidence_tier": evidence_tier,
        "coverage_limitations": coverage_limitations,
    }


def _evaluate(trial: Any, root: Path, payload: Mapping[str, Any]) -> dict[str, Any]:
    _require_fields(
        payload,
        {
            "registry_schema",
            "evidence_path",
            "config",
            "expected_tasks",
            "expected_manifests",
            "expected_trials",
        },
        set(),
        "evaluate payload",
    )
    evidence_root = _validated_relative_path(
        root, payload.get("evidence_path"), "evidence_path"
    )
    manifests = _require_object(
        payload.get("expected_manifests"), "evidence_invalid", "expected_manifests"
    )
    declared = payload.get("registry_schema")
    for manifest in manifests.values():
        try:
            actual = trial.manifest_registry_schema(manifest)
        except ValueError as exc:
            raise Blocked(
                "evidence_invalid", "arm registry schema is unsupported"
            ) from exc
        if actual != declared:
            raise Blocked(
                "evidence_invalid",
                "plan and manifest name different registry contracts",
            )
    try:
        verdict = trial.evaluate_pilot_gate_from_artifacts(
            evidence_root,
            payload["config"],
            payload["expected_tasks"],
            manifests,
            payload["expected_trials"],
        )
    except FileNotFoundError as exc:
        raise Blocked("artifact_missing", "evidence bundle is absent") from exc
    except ValueError as exc:
        raise Blocked("evidence_invalid", "evidence bundle failed its binding") from exc
    return {"verdict": verdict}


def _run_artifact_action(
    action: str, request: Mapping[str, Any]
) -> tuple[dict[str, Any], dict[str, Any]]:
    root = _validated_artifact_root(request.get("artifact_root"))
    payload = _require_object(request.get("payload"), "protocol_mismatch", "payload")
    trial = _load_pinned_modules()
    binding = _action_binding(trial)
    receipt_path = _receipt_path(root, str(request["request_id"]))
    request_hash = canonical_hash(dict(request))
    stored = _load_receipt(receipt_path)
    if stored is not None:
        if stored.get("request_hash") != request_hash:
            raise Blocked("stale_state", "request id is bound to a different request")
        if stored.get("runtime_binding") != binding:
            raise Blocked("stale_state", "receipt is bound to a different runtime")
        result = dict(stored.get("result", {}))
        result["replayed_receipt"] = True
        return binding, result
    if action == "prepare":
        result = _prepare(trial, root, payload)
    elif action == "checkpoint":
        result = _checkpoint(trial, root, payload)
    else:
        result = _evaluate(trial, root, payload)
    result["replayed_receipt"] = False
    _store_receipt(
        receipt_path,
        {
            "schema_version": 1,
            "artifact_contract": RECEIPT_CONTRACT,
            "request_id": request["request_id"],
            "request_hash": request_hash,
            "runtime_binding": binding,
            "result": result,
        },
    )
    return binding, result


def _validated_request(raw: str) -> dict[str, Any]:
    if len(raw.encode("utf-8")) > MAX_REQUEST_BYTES:
        raise InvalidRequest("protocol_mismatch", "request exceeds the size bound")
    if not raw.strip():
        raise InvalidRequest("protocol_mismatch", "request is empty")
    try:
        request = json.loads(raw)
    except ValueError as exc:
        raise InvalidRequest("protocol_mismatch", "request is not one JSON object") from exc
    if not isinstance(request, dict) or set(request) != REQUEST_FIELDS:
        raise InvalidRequest("protocol_mismatch", "request field set is invalid")
    if request.get("schema") != REQUEST_SCHEMA:
        raise InvalidRequest("protocol_mismatch", "request schema is unsupported")
    request_id = request.get("request_id")
    if not isinstance(request_id, str) or not SAFE_REQUEST_ID.fullmatch(request_id):
        raise InvalidRequest("protocol_mismatch", "request id is invalid")
    if request.get("action") not in SUPPORTED_ACTIONS:
        raise InvalidRequest("protocol_mismatch", "action is unsupported")
    if not isinstance(request.get("payload"), dict):
        raise InvalidRequest("protocol_mismatch", "payload must be an object")
    return request


def _emit(
    request_id: str,
    status: str,
    reason_code: str | None,
    runtime_binding: Mapping[str, Any],
    result: Mapping[str, Any],
    exit_code: int,
) -> int:
    response = {
        "schema": RESPONSE_SCHEMA,
        "request_id": request_id,
        "status": status,
        "reason_code": reason_code,
        "runtime_binding": dict(runtime_binding),
        "result": dict(result),
    }
    encoded = canonical_json(response)
    if len(encoded) > MAX_RESPONSE_BYTES:
        response = {
            "schema": RESPONSE_SCHEMA,
            "request_id": request_id,
            "status": "error",
            "reason_code": "evidence_invalid",
            "runtime_binding": {},
            "result": {},
        }
        encoded = canonical_json(response)
        exit_code = EXIT_INTERNAL
    sys.stdout.write(encoded.decode("utf-8") + "\n")
    sys.stdout.flush()
    return exit_code


def main(argv: list[str] | None = None) -> int:
    if argv:
        sys.stderr.write("bridge takes no arguments\n")
        return _emit(
            REDACTED_REQUEST_ID, "error", "protocol_mismatch", {}, {}, EXIT_INVALID
        )
    request_id = REDACTED_REQUEST_ID
    try:
        raw = sys.stdin.read(MAX_REQUEST_BYTES + 1)
    except (OSError, UnicodeDecodeError):
        sys.stderr.write("stdin is unreadable\n")
        return _emit(request_id, "error", "protocol_mismatch", {}, {}, EXIT_INVALID)
    try:
        request = _validated_request(raw)
        request_id = str(request["request_id"])
        action = str(request["action"])
        if action == "probe":
            binding, result = _probe(request)
        else:
            binding, result = _run_artifact_action(action, request)
        return _emit(request_id, "ok", None, binding, result, EXIT_OK)
    except BridgeError as error:
        sys.stderr.write(f"{error.reason_code}: {error.detail}\n")
        status = "blocked" if error.exit_code == EXIT_BLOCKED else "error"
        return _emit(request_id, status, error.reason_code, {}, {}, error.exit_code)
    except Exception:  # noqa: BLE001 - unknown finality must stay typed
        sys.stderr.write("unknown_finality: the action did not reach a typed result\n")
        return _emit(
            request_id, "error", "unknown_finality", {}, {}, EXIT_INTERNAL
        )


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
