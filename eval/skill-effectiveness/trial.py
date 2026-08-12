#!/usr/bin/env python3
"""Deterministic, advisory-only primitives for skill-effectiveness trials.

This module does not call a model, select a reviewer, or decide that a skill is
effective.  It freezes treatment manifests, builds isolated trial artifacts,
checks evidence supplied by a runner, and evaluates pre-registered pilot gates.
Provider-specific launchers and candidate promotion remain outside this
foundation; human intervention is optional and is never an E10 dependency.

Security and evidence limits:

* A manifest hash proves which declared inputs were assigned; it does not prove
  the host loaded them.
* A file-access audit proves only the events the host or sandbox emitted; it
  does not prove provider-side memory is disabled.
* A passing pilot gate proves the runner/eval path is usable, not that CCL
  skills improve quality.
"""

from __future__ import annotations

import fcntl
import hashlib
import hmac
import json
import math
import os
import random
import re
import secrets
import stat
import tempfile
from collections import Counter, defaultdict
from contextlib import contextmanager
from pathlib import Path
from typing import Any, Iterable, Mapping, Sequence


HASH_PATTERN = re.compile(r"^sha256:[0-9a-f]{64}$")
SAFE_ID = re.compile(r"^[A-Za-z0-9._-]+$")
MATCHED_CALL_EVIDENCE_CONTRACT = (
    "skill-effectiveness-active-control-matched-call-evidence-v1"
)
MATCHED_CALL_DECLARATION_STATUS = (
    "matched-call-contract-declared-no-observation"
)
SOURCE_CHECKOUT = Path(__file__).resolve().parents[2]
REQUIRED_COMPONENTS = (
    "system_prompt",
    "bootstrap",
    "skill_inventory",
    "tool_schema",
    "hook_command_config",
    "repo_instructions",
    "ccl_layer",
)
OFF_EMPTY_COMPONENTS = (
    "bootstrap",
    "skill_inventory",
    "hook_command_config",
    "ccl_layer",
)
REQUIRED_BUDGETS = ("tokens", "wall_time_seconds", "tool_calls", "cost_units")
PILOT_RATE_THRESHOLDS = {
    "arm_contamination_gap_max",
    "contamination_rate_max",
    "matched_call_smoke_rate_min",
    "reviewer_known_answer_accuracy_min",
    "reviewer_pairwise_agreement_min",
    "reviewer_pairwise_kappa_min",
    "reviewer_self_consistency_min",
    "runner_completion_rate_min",
    "skill_event_unverifiable_rate_max",
}
PILOT_COUNT_THRESHOLDS = {
    "missing_shape_task_family_stop_count",
    "reviewer_family_count_min",
    "samples_per_task_arm_min",
    "smoke_tasks_per_arm_min",
}
REQUIRED_TASK_FIELDS = (
    "task_id",
    "task_family",
    "cohort",
    "prompt_ref",
    "expected_owners",
    "frozen_at_sha",
    "corpus_version",
)
HELDOUT_TASK_FIELDS = {
    "task_id",
    "task_family",
    "cohort",
    "skill_content_cutoff",
    "curator_independent",
    "prompt_ref",
    "repo_snapshot",
    "expected_owners",
    "should_invoke",
    "risk_tags",
    "graders",
    "negative_control",
    "execution_mode",
    "frozen_at_sha",
    "corpus_version",
}
TASK_FAMILIES = {
    "implementation",
    "review",
    "diagnosis",
    "plan",
    "shared_gate",
    "delegation",
}
TREATMENTS = {"off", "active_control", "oracle", "full"}
REQUIRED_CAUSAL_TREATMENTS = {"off", "oracle", "full"}
ARM_TEMPLATE_REQUIRED_FIELDS = {
    "schema_version",
    "arm_id",
    "scope",
    "treatment",
    "allowlisted_diff",
    "runnable",
    "active_control_selection",
}
ARM_TEMPLATE_OPTIONAL_FIELDS = {"bundle_policy"}
FROZEN_MANIFEST_FIELDS = {"template_hash", "component_hashes", "manifest_hash"}
JUDGE_METADATA_KEYS = {
    "arm",
    "arm_id",
    "manifest",
    "manifest_hash",
    "skill_invocations",
    "skills_invoked",
    "treatment",
}
JUDGE_METADATA_KEYS_COMPACT = {key.replace("_", "") for key in JUDGE_METADATA_KEYS}
JUDGE_METADATA_TOKEN = re.compile(
    r"sha256:[0-9a-f]{64}|ccl-skills:|manifest[_ -]?hash|skills[_ -]?invoked|"
    r"(?:^|\b)arm[_ -]?id(?:\s*[:=]\s*|\s+)[A-Za-z0-9._-]+",
    re.IGNORECASE,
)
ACCESS_OPERATIONS = {"read", "open", "enumerate", "write"}
ACCESS_ACTOR = "tested-agent"
ISOLATION_EVIDENCE_FIELDS = (
    "fresh_session",
    "forked_from_existing",
    "auto_memory_enabled",
    "vector_retrieval_enabled",
    "session_recall_enabled",
    "cross_session_cache_enabled",
    "provider_persistence",
    "canary_leak_detected",
)
TRIAL_STATUSES = {
    "prepared",
    "running",
    "interim-budget-stop",
    "completed",
    "contaminated",
    "failed",
}
CALIBRATION_VERDICTS = {"A win", "tie", "B win"}
TRIAL_BINDING_FIELDS = (
    "task_hash",
    "manifest_hash",
    "runtime_hash",
    "runner_hash",
    "experiment_plan_hash",
    "trial_fingerprint",
)
CAPABILITY_EVIDENCE_FIELDS = {
    "mount_boundary",
    "access_audit",
    "memory_isolation",
}
CAPABILITY_PROBE_FIELDS = {"probe_id", "status", "observations"}
CAPABILITY_OBSERVATIONS = {
    "mount_boundary": {
        "outside_read_denied": True,
        "outside_write_denied": True,
    },
    "access_audit": {
        "all_accesses_recorded": True,
        "tamper_check_passed": True,
    },
    "memory_isolation": {
        "fresh_session": True,
        "cross_session_recall_detected": False,
    },
}
SKILL_CONTENT_REGISTRY_SCHEMA = "skill-content"
PROFILE_REGISTRY_SCHEMA = "paired-profile"
PROFILE_TREATMENTS = {"off", "full", "reference"}
REQUIRED_PROFILE_TREATMENTS = {"off", "full"}
PROFILE_REQUIRED_COMPONENTS = (
    "task_builder_template",
    "task",
    "driver",
    "model",
    "prompt_template",
    "permission_profile",
    "profile_payload",
)
PROFILE_TREATMENT_COMPONENT = "profile_payload"
PROFILE_ARM_TEMPLATE_REQUIRED_FIELDS = {
    "schema_version",
    "registry_schema",
    "arm_id",
    "scope",
    "treatment",
    "allowlisted_diff",
    "runnable",
}
# A real paired verdict carries exactly one closed tier.  `replicated-advisory`
# is a class-level property over several machines' summaries, never a third
# verdict, so it is deliberately absent here.
EVIDENCE_TIERS = {"advisory-paired", "causal"}
DEFAULT_EVIDENCE_TIER = "causal"
ADVISORY_WAIVABLE_ITEMS = (
    "access_root_enforcement",
    "complete_access_audit",
    "live_matched_call_gate",
    "memory_isolation_proof",
    "mount_evidence",
    "provider_side_persistence_proof",
)
# Each waivable item names the gate check whose *absence* it excuses.  A waiver
# covers missing proof only: an observed breach still fails at either tier, and
# `mount_evidence` has no per-record check because it is capability-matrix
# evidence, so its waiver is declaration-level.
ADVISORY_WAIVED_GATE_CHECKS = {
    "access_root_enforcement": "trial_file_isolation",
    "complete_access_audit": "trial_file_isolation",
    "live_matched_call_gate": "matched_call_compliance",
    "memory_isolation_proof": "cross_trial_memory_isolation",
    "mount_evidence": None,
    "provider_side_persistence_proof": "cross_trial_memory_isolation",
}
EVIDENCE_TIER_DECLARATION_FIELDS = {
    "schema_version",
    "requested_tier",
    "waived_items",
}
ARM_REGISTRY_PLAN_CONTRACT = "skill-effectiveness-arm-registry-plan-v1"
PROFILE_ARM_REGISTRY_PLAN_CONTRACT = (
    "skill-effectiveness-profile-arm-registry-plan-v1"
)
CAPABILITY_PROBE_CONTRACT = "skill-effectiveness-capability-probe-v1"
PILOT_EVIDENCE_CONTRACT = "skill-effectiveness-pilot-evidence-v1"
REVIEWER_CALIBRATION_RESULT_CONTRACT = (
    "skill-effectiveness-reviewer-calibration-result-v1"
)


def _is_safe_id(value: Any) -> bool:
    return (
        isinstance(value, str)
        and value not in {".", ".."}
        and SAFE_ID.fullmatch(value) is not None
    )


def canonical_json(value: Any) -> bytes:
    """Return stable UTF-8 JSON bytes for hashing and persisted fingerprints."""

    return json.dumps(
        value,
        ensure_ascii=False,
        sort_keys=True,
        separators=(",", ":"),
        allow_nan=False,
    ).encode("utf-8")


def canonical_hash(value: Any) -> str:
    """Hash bytes/text directly and structured values through canonical JSON."""

    if isinstance(value, bytes):
        payload = value
    elif isinstance(value, str):
        payload = value.encode("utf-8")
    else:
        payload = canonical_json(value)
    return "sha256:" + hashlib.sha256(payload).hexdigest()


def validate_deterministic_grade(grade: Mapping[str, Any]) -> list[str]:
    """Validate deterministic-grade shape and summary/check consistency."""

    errors: list[str] = []
    if not isinstance(grade, Mapping):
        return ["deterministic_grade_not_object"]
    if set(grade) != {"task_id", "trial_fingerprint", "checks", "passed"}:
        errors.append("deterministic_grade_field_set")
    if not _is_safe_id(grade.get("task_id")):
        errors.append("deterministic_grade_task_id")
    fingerprint = grade.get("trial_fingerprint")
    if not isinstance(fingerprint, str) or not HASH_PATTERN.fullmatch(fingerprint):
        errors.append("deterministic_grade_trial_fingerprint")
    checks = grade.get("checks")
    check_results: list[bool] = []
    if (
        not isinstance(checks, Sequence)
        or isinstance(checks, (str, bytes))
        or not checks
    ):
        errors.append("deterministic_grade_checks")
    else:
        for index, check in enumerate(checks):
            if not isinstance(check, Mapping) or set(check) != {
                "name",
                "passed",
                "evidence",
            }:
                errors.append(f"deterministic_grade_check_shape:{index}")
                continue
            if not isinstance(check.get("name"), str) or not check["name"]:
                errors.append(f"deterministic_grade_check_name:{index}")
            if not isinstance(check.get("evidence"), str) or not check["evidence"]:
                errors.append(f"deterministic_grade_check_evidence:{index}")
            if not isinstance(check.get("passed"), bool):
                errors.append(f"deterministic_grade_check_passed:{index}")
            else:
                check_results.append(check["passed"])
    passed = grade.get("passed")
    if not isinstance(passed, bool):
        errors.append("deterministic_grade_passed")
    elif len(check_results) == len(checks or ()) and passed is not all(check_results):
        errors.append("deterministic_grade_summary_mismatch")
    return errors


def _manifest_body(manifest: Mapping[str, Any]) -> dict[str, Any]:
    return {key: value for key, value in manifest.items() if key != "manifest_hash"}


def _validate_arm_template(
    template: Mapping[str, Any], *, allow_frozen_fields: bool = False
) -> None:
    allowed_fields = ARM_TEMPLATE_REQUIRED_FIELDS | ARM_TEMPLATE_OPTIONAL_FIELDS
    if allow_frozen_fields:
        allowed_fields |= FROZEN_MANIFEST_FIELDS
    missing_fields = ARM_TEMPLATE_REQUIRED_FIELDS - set(template)
    extra_fields = set(template) - allowed_fields
    if missing_fields or extra_fields:
        raise ValueError(
            f"arm template field mismatch: missing={sorted(missing_fields)}, "
            f"extra={sorted(extra_fields)}"
        )
    if "bundle_policy" in template and (
        not isinstance(template["bundle_policy"], str) or not template["bundle_policy"]
    ):
        raise ValueError("bundle_policy must be a non-empty string")
    if template.get("schema_version") != 1:
        raise ValueError("arm manifest schema_version must be 1")
    arm_id = template.get("arm_id")
    if not _is_safe_id(arm_id):
        raise ValueError("arm_id must match [A-Za-z0-9._-]+")
    if template.get("scope") not in {"subagent", "main"}:
        raise ValueError("arm scope must be subagent or main")
    treatment = template.get("treatment")
    if treatment not in TREATMENTS:
        raise ValueError(f"unsupported arm treatment: {treatment!r}")
    allowlisted = template.get("allowlisted_diff")
    if not isinstance(allowlisted, list) or any(
        item not in REQUIRED_COMPONENTS for item in allowlisted
    ):
        raise ValueError("allowlisted_diff must name known component keys")
    if len(set(allowlisted)) != len(allowlisted):
        raise ValueError("allowlisted_diff must not contain duplicates")
    if treatment == "off" and allowlisted:
        raise ValueError("OFF arm must not allow treatment diffs")
    if treatment != "off" and not allowlisted:
        raise ValueError("treatment arm must allow at least one component diff")
    selection = template.get("active_control_selection")
    if isinstance(selection, dict) and (
        selection.get("artifact_contract") == MATCHED_CALL_EVIDENCE_CONTRACT
        or selection.get("status") == MATCHED_CALL_DECLARATION_STATUS
        or selection.get("matched_call_gate_satisfied") is False
    ):
        raise ValueError("matched-call fixture evidence cannot enter an arm manifest")
    if not isinstance(selection, dict) or selection.get("status") not in {
        "not-applicable",
        "pending",
        "owner-relative-verified",
    }:
        raise ValueError("active_control_selection.status is invalid")
    if selection["status"] == "pending" and set(selection) != {
            "status",
            "required_independent_candidates",
            "selection_blinded_before_outcomes",
        }:
        raise ValueError("pending active-control selection field set is invalid")
    if selection["status"] == "pending" and (
        not isinstance(selection["required_independent_candidates"], int)
        or isinstance(selection["required_independent_candidates"], bool)
        or selection["required_independent_candidates"] != 2
        or selection["selection_blinded_before_outcomes"] is not True
    ):
        raise ValueError("pending active-control selection values are invalid")
    if selection["status"] == "not-applicable" and set(selection) != {"status"}:
        raise ValueError("not-applicable active-control selection field set is invalid")
    owner_relative_fields = {
        "status",
        "artifact_hash",
        "selected_package_hash",
        "selected_scope",
        "selected_scope_content_hash",
        "owner_relative_measurement_hash",
        "owner_reference_hash",
        "owner_commitment_request_hash",
    }
    if (
        selection["status"] == "owner-relative-verified"
        and set(selection) != owner_relative_fields
    ):
        raise ValueError("selected active-control binding field set is invalid")
    if treatment == "active_control":
        if selection["status"] == "owner-relative-verified":
            for field in (
                "artifact_hash",
                "selected_package_hash",
                "selected_scope_content_hash",
            ):
                value = selection.get(field)
                if not isinstance(value, str) or not HASH_PATTERN.fullmatch(value):
                    raise ValueError(f"selected active-control {field} is invalid")
            for field in (
                "owner_relative_measurement_hash",
                "owner_reference_hash",
                "owner_commitment_request_hash",
            ):
                value = selection.get(field)
                if not isinstance(value, str) or not HASH_PATTERN.fullmatch(value):
                    raise ValueError(f"selected active-control {field} is invalid")
            if selection.get("selected_scope") != template.get("scope"):
                raise ValueError("selected active-control scope does not match arm scope")
            if template.get("runnable") is not False:
                raise ValueError("active-control matched-call gate is pending")
        elif template.get("runnable") is not False:
            raise ValueError("pending active-control arms must be non-runnable")
    elif selection["status"] != "not-applicable":
        raise ValueError("non-control arm must mark active control not-applicable")


def freeze_arm_manifest(
    template: Mapping[str, Any],
    components: Mapping[str, bytes | str | Any],
    *,
    active_control_selection_artifact: Mapping[str, Any] | None = None,
    active_control_measurement_artifact: Mapping[str, Any] | None = None,
    active_control_owner_reference_artifact: Mapping[str, Any] | None = None,
) -> dict[str, Any]:
    """Freeze all treatment-affecting inputs into a content-addressed manifest."""

    _validate_arm_template(template)
    missing = [name for name in REQUIRED_COMPONENTS if name not in components]
    extra = sorted(set(components) - set(REQUIRED_COMPONENTS))
    if missing or extra:
        raise ValueError(f"component set mismatch: missing={missing}, extra={extra}")
    frozen = dict(template)
    frozen["template_hash"] = canonical_hash(dict(template))
    frozen["component_hashes"] = {
        name: canonical_hash(components[name]) for name in REQUIRED_COMPONENTS
    }
    if (
        frozen["treatment"] == "active_control"
        and frozen["active_control_selection"]["status"]
        == "owner-relative-verified"
    ):
        if active_control_selection_artifact is None:
            raise ValueError("selected arm requires a sealed active-control selection")
        import active_control

        expected_binding = active_control.active_control_manifest_binding(
            active_control_selection_artifact,
            scope=frozen["scope"],
            measurement=active_control_measurement_artifact,
            owner_reference=active_control_owner_reference_artifact,
        )
        if frozen["active_control_selection"] != expected_binding:
            raise ValueError("selected active-control binding does not match sealed artifact")
        selected_hash = frozen["active_control_selection"][
            "selected_scope_content_hash"
        ]
        if selected_hash != frozen["component_hashes"]["ccl_layer"]:
            raise ValueError(
                "selected active-control hash does not match ccl_layer"
            )
    elif (
        active_control_selection_artifact is not None
        or active_control_measurement_artifact is not None
        or active_control_owner_reference_artifact is not None
    ):
        raise ValueError("sealed active-control selection is only valid for selected arms")
    frozen["manifest_hash"] = canonical_hash(frozen)
    return frozen


def validate_frozen_manifest(manifest: Mapping[str, Any]) -> list[str]:
    """Return machine-readable validation errors without mutating the manifest."""

    errors: list[str] = []
    try:
        _validate_arm_template(manifest, allow_frozen_fields=True)
    except ValueError as exc:
        errors.append(str(exc))
    components = manifest.get("component_hashes")
    if not isinstance(components, dict):
        errors.append("component_hashes_missing")
    else:
        if set(components) != set(REQUIRED_COMPONENTS):
            errors.append("component_hashes_set_mismatch")
        for name in REQUIRED_COMPONENTS:
            value = components.get(name)
            if not isinstance(value, str) or not HASH_PATTERN.fullmatch(value):
                errors.append(f"component_hash_invalid:{name}")
    template_hash = manifest.get("template_hash")
    if not isinstance(template_hash, str) or not HASH_PATTERN.fullmatch(template_hash):
        errors.append("template_hash_invalid")
    manifest_hash = manifest.get("manifest_hash")
    if not isinstance(manifest_hash, str) or not HASH_PATTERN.fullmatch(manifest_hash):
        errors.append("manifest_hash_invalid")
    elif manifest_hash != canonical_hash(_manifest_body(manifest)):
        errors.append("manifest_hash_mismatch")
    return errors


def validate_manifest_preregistration(
    manifest: Mapping[str, Any], preregistered_template: Mapping[str, Any]
) -> list[str]:
    """Bind one frozen manifest to an independently loaded arm template."""

    errors = validate_frozen_manifest(manifest)
    try:
        _validate_arm_template(preregistered_template)
    except ValueError as exc:
        errors.append(f"preregistered_template_invalid:{exc}")
        return errors
    if manifest.get("template_hash") != canonical_hash(dict(preregistered_template)):
        errors.append("preregistered_template_hash_mismatch")
    template_fields = (
        "schema_version",
        "arm_id",
        "scope",
        "treatment",
        "allowlisted_diff",
        "runnable",
        "active_control_selection",
    )
    for field in template_fields:
        if manifest.get(field) != preregistered_template.get(field):
            errors.append(f"preregistered_template_field_mismatch:{field}")
    return errors


def compare_arm_to_off(
    off_manifest: Mapping[str, Any],
    candidate_manifest: Mapping[str, Any],
    off_preregistered_template: Mapping[str, Any],
    candidate_preregistered_template: Mapping[str, Any],
) -> list[str]:
    """Verify an arm against OFF and an independently loaded preregistration."""

    errors = [
        f"off:{error}"
        for error in validate_manifest_preregistration(
            off_manifest, off_preregistered_template
        )
    ]
    errors += validate_manifest_preregistration(
        candidate_manifest, candidate_preregistered_template
    )
    if errors:
        return errors
    if off_manifest.get("treatment") != "off":
        errors.append("baseline_is_not_off")
    if off_manifest.get("scope") != candidate_manifest.get("scope"):
        errors.append("scope_mismatch")
    base = off_manifest["component_hashes"]
    other = candidate_manifest["component_hashes"]
    actual = {name for name in REQUIRED_COMPONENTS if base[name] != other[name]}
    allowed = set(candidate_manifest.get("allowlisted_diff", []))
    for name in sorted(actual - allowed):
        errors.append(f"unallowlisted_diff:{name}")
    for name in sorted(allowed - actual):
        errors.append(f"allowlisted_diff_not_realized:{name}")
    return errors


def off_residual_components(manifest: Mapping[str, Any]) -> list[str]:
    """Return governed surfaces that are non-empty in an OFF manifest."""

    if manifest_registry_schema(manifest) == PROFILE_REGISTRY_SCHEMA:
        # A paired-profile OFF arm binds the built-in profile, which is
        # intentionally non-empty.  Empty-surface residual is a skill-content
        # concept and does not transfer to this registry.
        return []
    components = manifest.get("component_hashes")
    if not isinstance(components, Mapping):
        return list(OFF_EMPTY_COMPONENTS)
    empty_hash = canonical_hash("")
    return [name for name in OFF_EMPTY_COMPONENTS if components.get(name) != empty_hash]


def manifest_registry_schema(manifest: Mapping[str, Any]) -> str:
    """Name which arm-registry contract one template or manifest declares."""

    if not isinstance(manifest, Mapping):
        raise ValueError("arm manifest must be an object")
    declared = manifest.get("registry_schema", SKILL_CONTENT_REGISTRY_SCHEMA)
    if declared not in {SKILL_CONTENT_REGISTRY_SCHEMA, PROFILE_REGISTRY_SCHEMA}:
        raise ValueError(f"unsupported arm registry schema: {declared!r}")
    return declared


def registry_components(registry_schema: str) -> tuple[str, ...]:
    """Return the frozen component set one registry schema pins."""

    if registry_schema == PROFILE_REGISTRY_SCHEMA:
        return PROFILE_REQUIRED_COMPONENTS
    if registry_schema == SKILL_CONTENT_REGISTRY_SCHEMA:
        return REQUIRED_COMPONENTS
    raise ValueError(f"unsupported arm registry schema: {registry_schema!r}")


def _validate_profile_arm_template(
    template: Mapping[str, Any], *, allow_frozen_fields: bool = False
) -> None:
    allowed_fields = set(PROFILE_ARM_TEMPLATE_REQUIRED_FIELDS)
    if allow_frozen_fields:
        allowed_fields |= FROZEN_MANIFEST_FIELDS
    missing_fields = PROFILE_ARM_TEMPLATE_REQUIRED_FIELDS - set(template)
    extra_fields = set(template) - allowed_fields
    if missing_fields or extra_fields:
        raise ValueError(
            f"profile arm template field mismatch: missing={sorted(missing_fields)}, "
            f"extra={sorted(extra_fields)}"
        )
    if template.get("schema_version") != 1:
        raise ValueError("profile arm manifest schema_version must be 1")
    if template.get("registry_schema") != PROFILE_REGISTRY_SCHEMA:
        raise ValueError("profile arm template must declare the paired-profile schema")
    if not _is_safe_id(template.get("arm_id")):
        raise ValueError("arm_id must match [A-Za-z0-9._-]+")
    if template.get("scope") not in {"subagent", "main"}:
        raise ValueError("arm scope must be subagent or main")
    treatment = template.get("treatment")
    if treatment not in PROFILE_TREATMENTS:
        raise ValueError(f"unsupported profile arm treatment: {treatment!r}")
    if template.get("runnable") is not True:
        raise ValueError("profile arm manifest must be runnable")
    allowlisted = template.get("allowlisted_diff")
    if not isinstance(allowlisted, list) or len(set(allowlisted)) != len(allowlisted):
        raise ValueError("allowlisted_diff must be a list without duplicates")
    if treatment == "off":
        if allowlisted:
            raise ValueError("paired OFF arm must not allow treatment diffs")
    elif allowlisted != [PROFILE_TREATMENT_COMPONENT]:
        raise ValueError(
            "a profile arm may differ from OFF only in the profile payload"
        )


def freeze_profile_arm_manifest(
    template: Mapping[str, Any],
    components: Mapping[str, bytes | str | Any],
) -> dict[str, Any]:
    """Freeze one paired-profile arm; every input but the profile is pinned."""

    _validate_profile_arm_template(template)
    missing = [name for name in PROFILE_REQUIRED_COMPONENTS if name not in components]
    extra = sorted(set(components) - set(PROFILE_REQUIRED_COMPONENTS))
    if missing or extra:
        raise ValueError(f"component set mismatch: missing={missing}, extra={extra}")
    frozen = dict(template)
    frozen["template_hash"] = canonical_hash(dict(template))
    frozen["component_hashes"] = {
        name: canonical_hash(components[name]) for name in PROFILE_REQUIRED_COMPONENTS
    }
    frozen["manifest_hash"] = canonical_hash(frozen)
    return frozen


def validate_frozen_profile_manifest(manifest: Mapping[str, Any]) -> list[str]:
    """Return machine-readable errors for one frozen paired-profile manifest."""

    errors: list[str] = []
    try:
        _validate_profile_arm_template(manifest, allow_frozen_fields=True)
    except ValueError as exc:
        errors.append(str(exc))
    components = manifest.get("component_hashes")
    if not isinstance(components, dict):
        errors.append("component_hashes_missing")
    else:
        if set(components) != set(PROFILE_REQUIRED_COMPONENTS):
            errors.append("component_hashes_set_mismatch")
        for name in PROFILE_REQUIRED_COMPONENTS:
            value = components.get(name)
            if not isinstance(value, str) or not HASH_PATTERN.fullmatch(value):
                errors.append(f"component_hash_invalid:{name}")
    template_hash = manifest.get("template_hash")
    if not isinstance(template_hash, str) or not HASH_PATTERN.fullmatch(template_hash):
        errors.append("template_hash_invalid")
    manifest_hash = manifest.get("manifest_hash")
    if not isinstance(manifest_hash, str) or not HASH_PATTERN.fullmatch(manifest_hash):
        errors.append("manifest_hash_invalid")
    elif manifest_hash != canonical_hash(_manifest_body(manifest)):
        errors.append("manifest_hash_mismatch")
    return errors


def validate_any_frozen_manifest(manifest: Mapping[str, Any]) -> list[str]:
    """Validate one frozen manifest under the registry schema it declares."""

    if manifest_registry_schema(manifest) == PROFILE_REGISTRY_SCHEMA:
        return validate_frozen_profile_manifest(manifest)
    return validate_frozen_manifest(manifest)


def validate_profile_manifest_preregistration(
    manifest: Mapping[str, Any], preregistered_template: Mapping[str, Any]
) -> list[str]:
    """Bind one frozen profile manifest to an independently loaded template."""

    errors = validate_frozen_profile_manifest(manifest)
    try:
        _validate_profile_arm_template(preregistered_template)
    except ValueError as exc:
        errors.append(f"preregistered_template_invalid:{exc}")
        return errors
    if manifest.get("template_hash") != canonical_hash(dict(preregistered_template)):
        errors.append("preregistered_template_hash_mismatch")
    for field in sorted(PROFILE_ARM_TEMPLATE_REQUIRED_FIELDS):
        if manifest.get(field) != preregistered_template.get(field):
            errors.append(f"preregistered_template_field_mismatch:{field}")
    return errors


def compare_profile_arm_to_off(
    off_manifest: Mapping[str, Any],
    candidate_manifest: Mapping[str, Any],
    off_preregistered_template: Mapping[str, Any],
    candidate_preregistered_template: Mapping[str, Any],
) -> list[str]:
    """Verify one profile arm differs from OFF only in the profile payload."""

    errors = [
        f"off:{error}"
        for error in validate_profile_manifest_preregistration(
            off_manifest, off_preregistered_template
        )
    ]
    errors += validate_profile_manifest_preregistration(
        candidate_manifest, candidate_preregistered_template
    )
    if errors:
        return errors
    if off_manifest.get("treatment") != "off":
        errors.append("baseline_is_not_off")
    if off_manifest.get("scope") != candidate_manifest.get("scope"):
        errors.append("scope_mismatch")
    base = off_manifest["component_hashes"]
    other = candidate_manifest["component_hashes"]
    actual = {
        name for name in PROFILE_REQUIRED_COMPONENTS if base[name] != other[name]
    }
    allowed = set(candidate_manifest.get("allowlisted_diff", []))
    for name in sorted(actual - allowed):
        errors.append(f"unallowlisted_diff:{name}")
    for name in sorted(allowed - actual):
        errors.append(f"allowlisted_diff_not_realized:{name}")
    return errors


def _normalized_path(path: str | os.PathLike[str]) -> Path:
    return Path(path).expanduser().resolve(strict=False)


def _is_within(path: Path, roots: Sequence[Path]) -> bool:
    for root in roots:
        try:
            path.relative_to(root)
            return True
        except ValueError:
            continue
    return False


def assess_isolation(
    evidence: Mapping[str, Any],
    access_events: Iterable[Mapping[str, Any]],
    read_allow_roots: Sequence[str | os.PathLike[str]],
    write_allow_roots: Sequence[str | os.PathLike[str]],
    *,
    forbidden_write_paths: Sequence[str | os.PathLike[str]] = (),
) -> dict[str, Any]:
    """Assess supplied isolation evidence; absent evidence never passes by default."""

    reasons: list[str] = []
    memory_reasons: list[str] = []
    normalized_read_roots = [_normalized_path(root) for root in read_allow_roots]
    normalized_write_roots = [_normalized_path(root) for root in write_allow_roots]
    normalized_forbidden_write_paths = [
        _normalized_path(path) for path in forbidden_write_paths
    ]
    if not normalized_read_roots:
        reasons.append("read_allowlist_missing")
    if not normalized_write_roots:
        reasons.append("write_allowlist_missing")
    broad_roots = {Path("/").resolve(), Path.home().resolve()}
    for root in normalized_read_roots + normalized_write_roots:
        if root in broad_roots:
            reasons.append(f"allow_root_too_broad:{root}")
    if any(
        _is_within(read_root, [write_root]) or _is_within(write_root, [read_root])
        for read_root in normalized_read_roots
        for write_root in normalized_write_roots
    ):
        reasons.append("read_write_allow_roots_overlap")
    for forbidden_path in normalized_forbidden_write_paths:
        if _is_within(forbidden_path, normalized_write_roots):
            reasons.append(f"write_allowlist_contains_control_path:{forbidden_path}")
    required_false = (
        "forked_from_existing",
        "auto_memory_enabled",
        "vector_retrieval_enabled",
        "session_recall_enabled",
        "cross_session_cache_enabled",
    )
    confirmed_memory_reasons: list[str] = []
    if evidence.get("fresh_session") is False:
        confirmed_memory_reasons.append("fresh_session_unproven")
    elif evidence.get("fresh_session") is not True:
        memory_reasons.append("fresh_session_unproven")
    for field in required_false:
        if evidence.get(field) is True:
            confirmed_memory_reasons.append(f"{field}_not_disabled")
        elif evidence.get(field) is not False:
            memory_reasons.append(f"{field}_not_disabled")
    if evidence.get("canary_leak_detected") is True:
        confirmed_memory_reasons.append("canary_leak_detected")
    elif evidence.get("canary_leak_detected") is not False:
        memory_reasons.append("canary_leak_evidence_missing")
    provider_persistence = evidence.get("provider_persistence")
    if provider_persistence == "enabled":
        confirmed_memory_reasons.append("provider_persistence_not_disabled")
    elif provider_persistence != "disabled":
        memory_reasons.append("provider_persistence_not_disabled")

    access_count = 0
    for index, event in enumerate(access_events):
        access_count += 1
        raw_path = event.get("path")
        if not isinstance(raw_path, str) or not raw_path:
            reasons.append(f"access_event_path_missing:{index}")
            continue
        operation = event.get("operation")
        if operation not in ACCESS_OPERATIONS:
            reasons.append(f"access_event_operation_invalid:{index}")
        effective_operation = operation
        if operation == "open":
            effective_operation = event.get("access_mode")
            if effective_operation not in {"read", "write"}:
                reasons.append(f"access_event_open_mode_invalid:{index}")
        if event.get("actor") != ACCESS_ACTOR:
            reasons.append(f"access_event_actor_invalid:{index}")
        if not Path(raw_path).expanduser().is_absolute():
            reasons.append(f"access_event_path_not_absolute:{index}")
            continue
        path = _normalized_path(raw_path)
        allowed_roots = (
            normalized_write_roots
            if effective_operation == "write"
            else normalized_read_roots
        )
        if not _is_within(path, allowed_roots):
            reasons.append(f"path_outside_allowlist:{path}")
    if access_count == 0:
        reasons.append("access_audit_missing")

    if reasons or confirmed_memory_reasons:
        status = "contaminated"
    elif memory_reasons:
        status = "unresolved_isolation_threat"
    else:
        status = "ok"
    return {
        "status": status,
        "file_access_status": "contaminated" if reasons else "ok",
        "memory_isolation_status": (
            "contaminated"
            if confirmed_memory_reasons
            else "unresolved_isolation_threat"
            if memory_reasons
            else "ok"
        ),
        "file_reasons": reasons,
        "memory_reasons": confirmed_memory_reasons + memory_reasons,
        "reasons": reasons + confirmed_memory_reasons + memory_reasons,
        "normalized_read_allow_roots": [str(root) for root in normalized_read_roots],
        "normalized_write_allow_roots": [str(root) for root in normalized_write_roots],
        "access_event_count": access_count,
    }


def validate_task_record(task: Mapping[str, Any], committed: bool) -> list[str]:
    errors: list[str] = []
    for field in REQUIRED_TASK_FIELDS:
        if (
            field not in task
            or task[field] in (None, "")
            or (task[field] == [] and field != "expected_owners")
        ):
            errors.append(f"required_field_missing:{field}")
    task_id = task.get("task_id")
    if not _is_safe_id(task_id):
        errors.append("task_id_invalid")
    if task.get("task_family") not in TASK_FAMILIES:
        errors.append("task_family_invalid")
    cohort = task.get("cohort")
    if cohort not in {"known-regression", "held-out-generalization"}:
        errors.append("cohort_invalid")
    owners = task.get("expected_owners")
    if not isinstance(owners, list) or any(
        not isinstance(owner, str) or not owner.startswith("ccl-skills:")
        for owner in owners or []
    ):
        errors.append("expected_owners_invalid")
    elif len(set(owners)) != len(owners):
        errors.append("expected_owners_duplicate")
    else:
        negative_control = task.get("negative_control") is True
        should_not_invoke = task.get("should_invoke") is False
        explicit_negative = negative_control and should_not_invoke
        if not owners and not explicit_negative:
            errors.append("expected_owners_empty_for_positive_task")
        if owners and (negative_control or should_not_invoke):
            errors.append("expected_owners_present_for_negative_control")
    if isinstance(task.get("should_invoke"), bool) and isinstance(
        task.get("negative_control"), bool
    ):
        if task["should_invoke"] == task["negative_control"]:
            errors.append("negative_control_flags_inconsistent")
    if not isinstance(task.get("prompt_ref"), str):
        errors.append("prompt_ref_invalid")
    if (committed or "execution_mode" in task) and task.get(
        "execution_mode"
    ) != "answer_only":
        errors.append("execution_mode_invalid")
    if not isinstance(task.get("corpus_version"), str):
        errors.append("corpus_version_invalid")
    frozen_at_sha = task.get("frozen_at_sha")
    if not isinstance(frozen_at_sha, str) or (
        frozen_at_sha != "root" and not re.fullmatch(r"[0-9a-f]{40,64}", frozen_at_sha)
    ):
        errors.append("frozen_at_sha_invalid")
    if cohort == "held-out-generalization":
        if task.get("curator_independent") is not True:
            errors.append("heldout_curator_not_independent")
        prompt_ref = task.get("prompt_ref")
        if not isinstance(prompt_ref, str) or not prompt_ref.startswith("corpus://"):
            errors.append("heldout_prompt_ref_must_use_private_corpus")
        if committed:
            extra_fields = set(task) - HELDOUT_TASK_FIELDS
            for field in sorted(extra_fields):
                errors.append(f"heldout_committed_field_forbidden:{field}")
            missing_fields = HELDOUT_TASK_FIELDS - set(task)
            for field in sorted(missing_fields):
                errors.append(f"heldout_committed_field_missing:{field}")
            repo_snapshot = task.get("repo_snapshot")
            if not isinstance(repo_snapshot, str) or not HASH_PATTERN.fullmatch(
                repo_snapshot
            ):
                errors.append("heldout_repo_snapshot_invalid")
            for field in ("should_invoke", "negative_control"):
                if not isinstance(task.get(field), bool):
                    errors.append(f"heldout_{field}_invalid")
            for field in ("risk_tags", "graders"):
                values = task.get(field)
                if (
                    not isinstance(values, list)
                    or any(not isinstance(value, str) for value in values)
                    or len(set(values)) != len(values)
                    or (field == "graders" and not values)
                ):
                    errors.append(f"heldout_{field}_invalid")
            if not isinstance(task.get("skill_content_cutoff"), str) or not task.get(
                "skill_content_cutoff"
            ):
                errors.append("heldout_skill_content_cutoff_invalid")
    return errors


def _validate_budget(budget: Mapping[str, Any]) -> None:
    if not isinstance(budget, Mapping):
        raise ValueError("budget must be an object")
    if set(budget) != set(REQUIRED_BUDGETS):
        raise ValueError("budget field set is invalid")
    missing = [
        field
        for field in REQUIRED_BUDGETS
        if budget[field] is not None
        and (
            not isinstance(budget[field], (int, float))
            or isinstance(budget[field], bool)
            or not math.isfinite(budget[field])
            or budget[field] <= 0
        )
    ]
    if missing:
        raise ValueError(f"budget limits must be null or positive: {missing}")


def _validated_consumed_budget(
    resume_cursor: Mapping[str, Any] | None, budget: Mapping[str, Any]
) -> dict[str, float]:
    if not isinstance(resume_cursor, Mapping):
        raise ValueError("budget-stop resume cursor must be an object")
    next_run_order = resume_cursor.get("next_run_order")
    if (
        not isinstance(next_run_order, int)
        or isinstance(next_run_order, bool)
        or next_run_order < 1
    ):
        raise ValueError("budget-stop next_run_order must be positive")
    consumed = resume_cursor.get("consumed_budget")
    if not isinstance(consumed, Mapping) or set(consumed) != set(REQUIRED_BUDGETS):
        raise ValueError("budget-stop consumed_budget field set is invalid")
    normalized: dict[str, float] = {}
    for field in REQUIRED_BUDGETS:
        value = consumed[field]
        limit = budget[field]
        if (
            not isinstance(value, (int, float))
            or isinstance(value, bool)
            or not math.isfinite(value)
            or value < 0
            or (limit is not None and value > limit)
        ):
            raise ValueError(f"budget-stop consumed value is invalid: {field}")
        normalized[field] = value
    return normalized


def _remaining_budget(
    budget: Mapping[str, Any], resume_cursor: Mapping[str, Any] | None
) -> dict[str, float | None]:
    consumed = (
        _validated_consumed_budget(resume_cursor, budget)
        if isinstance(resume_cursor, Mapping) and "consumed_budget" in resume_cursor
        else {field: 0 for field in REQUIRED_BUDGETS}
    )
    remaining = {
        field: None if budget[field] is None else budget[field] - consumed[field]
        for field in REQUIRED_BUDGETS
    }
    exhausted = [
        field for field, value in remaining.items() if value is not None and value <= 0
    ]
    if exhausted:
        raise ValueError(f"trial budget exhausted: {exhausted}")
    return remaining


def _validate_pilot_config(config: Mapping[str, Any]) -> Mapping[str, Any]:
    if not isinstance(config, Mapping) or config.get("schema_version") != 1:
        raise ValueError("pilot gate config is not schema version 1")
    if config.get("enforcement") != "advisory":
        raise ValueError("pilot gate config must remain advisory")
    if config.get("meaning") != "runner_eval_validity_only":
        raise ValueError("pilot gate meaning is invalid")
    if config.get("frozen_before_outcomes") is not True:
        raise ValueError("pilot gate must be frozen before outcomes")
    calibration_fixture_hash = config.get("reviewer_calibration_fixture_hash")
    if not isinstance(calibration_fixture_hash, str) or not HASH_PATTERN.fullmatch(
        calibration_fixture_hash
    ):
        raise ValueError("pilot calibration fixture hash is invalid")
    case_fixture_hash = config.get("reviewer_calibration_case_fixture_hash")
    if not isinstance(case_fixture_hash, str) or not HASH_PATTERN.fullmatch(
        case_fixture_hash
    ):
        raise ValueError("pilot calibration case fixture hash is invalid")

    thresholds = config.get("thresholds")
    required_thresholds = PILOT_RATE_THRESHOLDS | PILOT_COUNT_THRESHOLDS
    if not isinstance(thresholds, Mapping) or set(thresholds) != required_thresholds:
        raise ValueError("pilot gate threshold set is invalid")
    for field in PILOT_RATE_THRESHOLDS:
        value = thresholds[field]
        if (
            not isinstance(value, (int, float))
            or isinstance(value, bool)
            or not math.isfinite(value)
            or not 0 <= value <= 1
        ):
            raise ValueError(f"pilot rate threshold is invalid: {field}")
    for field in PILOT_COUNT_THRESHOLDS:
        value = thresholds[field]
        if not isinstance(value, int) or isinstance(value, bool) or value < 1:
            raise ValueError(f"pilot count threshold is invalid: {field}")

    budgets = config.get("budgets")
    if not isinstance(budgets, Mapping):
        raise ValueError("pilot gate budgets are missing")
    _validate_budget(budgets)
    primary_outcomes = config.get("primary_outcomes")
    minimum_effects = config.get("minimum_effects")
    if (
        not isinstance(primary_outcomes, Mapping)
        or set(primary_outcomes) != TASK_FAMILIES
    ):
        raise ValueError("pilot primary outcome task-family set is invalid")
    if any(
        not isinstance(value, str) or not value for value in primary_outcomes.values()
    ):
        raise ValueError("pilot primary outcome value is invalid")
    if (
        not isinstance(minimum_effects, Mapping)
        or set(minimum_effects) != TASK_FAMILIES
    ):
        raise ValueError("pilot minimum-effect task-family set is invalid")
    if any(
        not isinstance(value, (int, float))
        or isinstance(value, bool)
        or not math.isfinite(value)
        or value <= 0
        for value in minimum_effects.values()
    ):
        raise ValueError("pilot minimum effect must be positive")
    return thresholds


def evidence_tier_declaration(config: Mapping[str, Any]) -> dict[str, Any]:
    """Read the typed evidence-tier declaration a frozen plan may carry.

    The field is a versioned addition: a plan without it keeps the original
    causal contract, where every isolation-evidence item is required.
    """

    if not isinstance(config, Mapping):
        raise ValueError("pilot gate config must be an object")
    declaration = config.get("evidence_tier")
    if declaration is None:
        return {
            "schema_version": 1,
            "requested_tier": DEFAULT_EVIDENCE_TIER,
            "waived_items": [],
        }
    if (
        not isinstance(declaration, Mapping)
        or set(declaration) != EVIDENCE_TIER_DECLARATION_FIELDS
    ):
        raise ValueError("evidence tier declaration field set is invalid")
    if declaration.get("schema_version") != 1:
        raise ValueError("evidence tier declaration schema_version must be 1")
    requested_tier = declaration.get("requested_tier")
    if requested_tier not in EVIDENCE_TIERS:
        raise ValueError(f"unsupported evidence tier: {requested_tier!r}")
    waived_items = declaration.get("waived_items")
    if not isinstance(waived_items, list) or any(
        item not in ADVISORY_WAIVABLE_ITEMS for item in waived_items
    ):
        raise ValueError("waived_items must name known advisory-waivable items")
    if len(set(waived_items)) != len(waived_items):
        raise ValueError("waived_items must not repeat an item")
    if requested_tier == "causal" and waived_items:
        raise ValueError("a causal request may not waive isolation evidence")
    return {
        "schema_version": 1,
        "requested_tier": requested_tier,
        "waived_items": sorted(waived_items),
    }


def checkpoint_evidence_tier(registry_schema: str) -> dict[str, Any]:
    """Return the frozen completion tier for one registry contract."""

    if registry_schema == PROFILE_REGISTRY_SCHEMA:
        return {
            "schema_version": 1,
            "requested_tier": "advisory-paired",
            "waived_items": sorted(ADVISORY_WAIVABLE_ITEMS),
        }
    if registry_schema == SKILL_CONTENT_REGISTRY_SCHEMA:
        return {
            "schema_version": 1,
            "requested_tier": DEFAULT_EVIDENCE_TIER,
            "waived_items": [],
        }
    raise ValueError(f"unsupported arm registry schema: {registry_schema!r}")


def _safe_segment(value: str, label: str) -> str:
    if not _is_safe_id(value):
        raise ValueError(f"unsafe {label}: {value!r}")
    return value


def _reject_symlink(path: Path) -> None:
    try:
        mode = path.lstat().st_mode
    except FileNotFoundError:
        return
    if stat.S_ISLNK(mode):
        raise ValueError(f"private artifact path must not be a symlink: {path}")


def _path_exists(path: Path) -> bool:
    try:
        path.lstat()
    except FileNotFoundError:
        return False
    return True


def _read_private_file(path: Path) -> bytes:
    _reject_symlink(path)
    try:
        file_stat = path.stat()
    except FileNotFoundError as exc:
        raise ValueError(f"private artifact file is missing: {path}") from exc
    if not stat.S_ISREG(file_stat.st_mode):
        raise ValueError(f"private artifact path is not a regular file: {path}")
    if file_stat.st_mode & 0o777 != 0o600:
        raise ValueError(f"private artifact file must be 0600: {path}")
    return path.read_bytes()


def _validate_replacement_safe_ancestors(path: Path) -> None:
    """Reject writable ancestors unless sticky-bit rename protection applies."""

    starts = [Path(path)]
    resolved = Path(path).resolve(strict=True)
    if resolved != starts[0]:
        starts.append(resolved)
    checked = set()
    for start in starts:
        current = start
        while current not in checked:
            checked.add(current)
            try:
                mode = current.lstat().st_mode
            except FileNotFoundError:
                pass
            else:
                if stat.S_ISLNK(mode):
                    pass
                elif not stat.S_ISDIR(mode):
                    raise ValueError(
                        f"private artifact ancestor is not a directory: {current}"
                    )
                else:
                    writable_by_others = mode & (stat.S_IWGRP | stat.S_IWOTH)
                    if writable_by_others and not mode & stat.S_ISVTX:
                        raise ValueError(
                            "private artifact ancestor is writable without sticky-bit "
                            f"rename protection: {current}"
                        )
            if current.parent == current:
                break
            current = current.parent


def _ensure_private_directory(path: Path, trusted_root: Path | None = None) -> None:
    path = Path(path)
    if trusted_root is None:
        _reject_symlink(path)
        missing_paths = []
        current = path
        while not current.exists():
            missing_paths.append(current)
            current = current.parent
        _reject_symlink(current)
        if not current.is_dir():
            raise ValueError(f"private artifact parent is not a directory: {current}")
        _validate_replacement_safe_ancestors(current)
        for missing_path in reversed(missing_paths):
            _reject_symlink(missing_path)
            missing_path.mkdir(mode=0o700)
            missing_path.chmod(0o700)
        _reject_symlink(path)
        if not path.is_dir():
            raise ValueError(f"private artifact path is not a directory: {path}")
        path_stat = path.stat()
        if path_stat.st_uid != os.geteuid():
            raise ValueError(
                f"private artifact directory must be owned by caller: {path}"
            )
        mode = path_stat.st_mode & 0o777
        if not missing_paths and mode != 0o700:
            raise ValueError(
                f"existing private artifact directory must already be 0700: {path}"
            )
        return

    root = Path(trusted_root).resolve(strict=False)
    _ensure_private_directory(root)
    try:
        relative = path.relative_to(root)
    except ValueError as exc:
        raise ValueError("private artifact path escapes trusted root") from exc
    if any(segment in {".", ".."} for segment in relative.parts):
        raise ValueError("private artifact path escapes trusted root")
    resolved_path = path.resolve(strict=False)
    try:
        resolved_path.relative_to(root)
    except ValueError as exc:
        raise ValueError("private artifact path escapes trusted root") from exc
    current = root
    for segment in relative.parts:
        current = current / segment
        _reject_symlink(current)
        created = False
        try:
            current.mkdir(mode=0o700)
            created = True
        except FileExistsError:
            pass
        _reject_symlink(current)
        if not current.is_dir():
            raise ValueError(f"private artifact path is not a directory: {current}")
        current_stat = current.stat()
        if current_stat.st_uid != os.geteuid():
            raise ValueError(
                f"private artifact directory must be owned by caller: {current}"
            )
        mode = current_stat.st_mode & 0o777
        if created:
            current.chmod(0o700)
        elif mode != 0o700:
            raise ValueError(
                f"existing private artifact directory must already be 0700: {current}"
            )


def ensure_private_directory(path: Path, trusted_root: Path | None = None) -> None:
    """Create/chmod an explicit trial output directory to owner-only access."""

    _ensure_private_directory(Path(path), trusted_root)


def _atomic_write(path: Path, payload: bytes) -> None:
    _ensure_private_directory(path.parent)
    _reject_symlink(path)
    descriptor, temp_name = tempfile.mkstemp(prefix=f".{path.name}.", dir=path.parent)
    temp_path = Path(temp_name)
    try:
        os.fchmod(descriptor, 0o600)
        with os.fdopen(descriptor, "wb") as stream:
            stream.write(payload)
            stream.flush()
            os.fsync(stream.fileno())
        os.replace(temp_path, path)
        path.chmod(0o600)
    except Exception:
        try:
            temp_path.unlink(missing_ok=True)
        finally:
            raise


def write_json_atomic(path: Path, value: Any) -> None:
    _atomic_write(path, canonical_json(value) + b"\n")


def write_jsonl_atomic(path: Path, rows: Iterable[Mapping[str, Any]]) -> None:
    payload = b"".join(canonical_json(row) + b"\n" for row in rows)
    _atomic_write(path, payload)


def load_private_json(path: Path) -> Any:
    """Read JSON only from an owner-private regular artifact file."""

    try:
        return json.loads(_read_private_file(Path(path)))
    except (UnicodeDecodeError, ValueError) as exc:
        raise ValueError(f"private JSON artifact is invalid: {path}") from exc


def load_private_jsonl(path: Path) -> list[dict[str, Any]]:
    """Read object-only JSONL from an owner-private regular artifact file."""

    try:
        payload = _read_private_file(Path(path)).decode("utf-8")
        rows = []
        for line in payload.splitlines():
            if not line.strip():
                continue
            row = json.loads(line)
            if not isinstance(row, dict):
                raise ValueError("private JSONL rows must be objects")
            rows.append(row)
        return rows
    except (UnicodeDecodeError, ValueError) as exc:
        raise ValueError(f"private JSONL artifact is invalid: {path}") from exc


def _external_private_path(
    path: Path, label: str, *, create_parent: bool = True
) -> Path:
    """Resolve one owner-private artifact path outside the source checkout."""

    resolved = Path(path).expanduser()
    _reject_symlink(resolved)
    resolved = resolved.resolve(strict=False)
    try:
        resolved.relative_to(SOURCE_CHECKOUT)
    except ValueError:
        pass
    else:
        raise ValueError(f"{label} must stay outside the source checkout")
    if not create_parent and not resolved.parent.exists():
        raise ValueError(f"{label} parent does not exist")
    _ensure_private_directory(resolved.parent)
    return resolved


def _write_private_json_once(
    path: Path, payload: Mapping[str, Any], label: str
) -> None:
    """Create an idempotent local evidence artifact without replacing evidence."""

    path = _external_private_path(path, label)
    if _path_exists(path):
        if load_private_json(path) != payload:
            raise ValueError(f"existing {label} differs from requested content")
        return
    write_json_atomic(path, payload)


def load_or_create_blinding_key(controller_root: Path) -> bytes:
    """Return a stable controller-only 256-bit key for blinded pair identity."""

    controller_root = Path(controller_root).expanduser()
    _reject_symlink(controller_root)
    controller_root = controller_root.resolve(strict=False)
    _ensure_private_directory(controller_root)
    key_path = controller_root / "blinding.key"
    if _path_exists(key_path):
        key = _read_private_file(key_path)
        if len(key) != 32:
            raise ValueError("blinding key must contain exactly 32 bytes")
        return key
    key = secrets.token_bytes(32)
    descriptor, temp_name = tempfile.mkstemp(
        prefix=".blinding.key.", dir=controller_root
    )
    temp_path = Path(temp_name)
    try:
        with os.fdopen(descriptor, "wb") as stream:
            os.fchmod(stream.fileno(), 0o600)
            stream.write(key)
            stream.flush()
            os.fsync(stream.fileno())
        try:
            os.link(temp_path, key_path, follow_symlinks=False)
        except FileExistsError:
            existing = _read_private_file(key_path)
            if len(existing) != 32:
                raise ValueError("blinding key must contain exactly 32 bytes")
            return existing
        return key
    finally:
        temp_path.unlink(missing_ok=True)


def archive_private_file(
    path: Path, archive_root: Path, filename_prefix: str
) -> Path | None:
    """Content-address one private file before replacing its canonical path."""

    path = Path(path)
    if not _path_exists(path):
        return None
    if not _is_safe_id(filename_prefix):
        raise ValueError("archive filename_prefix is unsafe")
    payload = _read_private_file(path)
    archive_root = Path(archive_root)
    _ensure_private_directory(archive_root)
    digest = canonical_hash(payload).removeprefix("sha256:")
    archived = archive_root / f"{filename_prefix}-{digest}.json"
    if _path_exists(archived):
        if _read_private_file(archived) != payload:
            raise ValueError("content-addressed archive collision")
    else:
        _atomic_write(archived, payload)
    path.unlink()
    return archived


def task_artifact_reference(task: Mapping[str, Any]) -> dict[str, Any]:
    """Return evaluator-safe task metadata without owner or grader truth."""

    reference = {
        "task_id": task["task_id"],
        "task_family": task["task_family"],
        "cohort": task["cohort"],
        "prompt_ref": task["prompt_ref"],
        "frozen_at_sha": task["frozen_at_sha"],
        "corpus_version": task["corpus_version"],
    }
    if "execution_mode" in task:
        reference["execution_mode"] = task["execution_mode"]
    reference["task_hash"] = canonical_hash(reference)
    return reference


def prepare_trial(
    output_root: Path,
    task: Mapping[str, Any],
    manifest: Mapping[str, Any],
    runtime: Mapping[str, Any],
    budget: Mapping[str, Any],
    sample_index: int,
    *,
    expected_isolation_evidence: Mapping[str, Any] | None = None,
    expected_read_allow_roots: Sequence[str | os.PathLike[str]] = (),
    expected_write_allow_roots: Sequence[str | os.PathLike[str]] = (),
) -> dict[str, Any]:
    """Create or safely resume one content-bound trial artifact directory."""

    task_errors = validate_task_record(task, committed=False)
    if task_errors:
        raise ValueError(f"invalid task: {task_errors}")
    manifest_errors = validate_any_frozen_manifest(manifest)
    if manifest_errors:
        raise ValueError(f"invalid manifest: {manifest_errors}")
    if manifest.get("runnable") is not True:
        raise ValueError("arm manifest is not runnable")
    _validate_budget(budget)
    if (
        not isinstance(sample_index, int)
        or isinstance(sample_index, bool)
        or sample_index < 1
    ):
        raise ValueError("sample_index must be a positive integer")
    if not isinstance(runtime, Mapping):
        raise ValueError("runtime must be an object")
    for field in (
        "provider",
        "model",
        "session_id",
        "isolation_config_hash",
        "runner_hash",
        "experiment_plan_hash",
    ):
        if not isinstance(runtime.get(field), str) or not runtime[field]:
            raise ValueError(f"runtime field missing: {field}")
    if not HASH_PATTERN.fullmatch(runtime["isolation_config_hash"]):
        raise ValueError("runtime isolation_config_hash is invalid")
    if not HASH_PATTERN.fullmatch(runtime["runner_hash"]):
        raise ValueError("runtime runner_hash is invalid")
    if not HASH_PATTERN.fullmatch(runtime["experiment_plan_hash"]):
        raise ValueError("runtime experiment_plan_hash is invalid")

    task_id = _safe_segment(task["task_id"], "task_id")
    arm_id = _safe_segment(manifest["arm_id"], "arm_id")
    output_root = Path(output_root).expanduser()
    _reject_symlink(output_root)
    output_root = output_root.resolve(strict=False)
    try:
        output_root.relative_to(SOURCE_CHECKOUT)
    except ValueError:
        pass
    else:
        raise ValueError("trial output root must stay outside the source checkout")
    try:
        SOURCE_CHECKOUT.relative_to(output_root)
    except ValueError:
        pass
    else:
        raise ValueError("trial output root must not contain the source checkout")
    _ensure_private_directory(output_root)
    trial_dir = output_root / task_id / arm_id / f"sample-{sample_index:03d}"
    trial_file = trial_dir / "trial.json"
    trial_location_hash = canonical_hash(str(trial_dir))
    fingerprint = canonical_hash(
        {
            "task": task,
            "manifest_hash": manifest["manifest_hash"],
            "runtime": runtime,
            "budget": budget,
            "sample_index": sample_index,
            "trial_location_hash": trial_location_hash,
        }
    )
    fixed_artifact_fields = {
        "schema_version": 1,
        "artifact_contract": "skill-effectiveness-trial-v1",
        "enforcement": "advisory",
        "registry_schema": manifest_registry_schema(manifest),
        "task": task_artifact_reference(task),
        "arm_id": arm_id,
        "manifest_hash": manifest["manifest_hash"],
        "runtime": dict(runtime),
        "budget": dict(budget),
        "sample_index": sample_index,
        "trial_location_hash": trial_location_hash,
        "trial_fingerprint": fingerprint,
    }
    with _prepare_lock(trial_dir, output_root):
        return _prepare_trial_artifact_locked(
            output_root=output_root,
            trial_dir=trial_dir,
            trial_file=trial_file,
            fixed_artifact_fields=fixed_artifact_fields,
            fingerprint=fingerprint,
            budget=budget,
            expected_isolation_evidence=expected_isolation_evidence,
            expected_read_allow_roots=expected_read_allow_roots,
            expected_write_allow_roots=expected_write_allow_roots,
        )


def _completion_evidence_missing(
    trial_dir: Path, *, allow_empty_access_audit: bool = False
) -> list[str]:
    missing = []
    for name in ("events.jsonl", "access-audit.jsonl"):
        path = Path(trial_dir) / name
        if not _path_exists(path):
            missing.append(name)
            continue
        parsed_rows = 0
        try:
            payload = _read_private_file(path).decode("utf-8")
            for line in payload.splitlines():
                if not line.strip():
                    continue
                row = json.loads(line)
                if not isinstance(row, dict):
                    raise ValueError("JSONL row must be an object")
                if name == "events.jsonl" and not isinstance(
                    row.get("event_contract"), str
                ):
                    raise ValueError("event_contract is required")
                if name == "access-audit.jsonl" and (
                    row.get("actor") != ACCESS_ACTOR
                    or row.get("operation") not in ACCESS_OPERATIONS
                    or (
                        row.get("operation") == "open"
                        and row.get("access_mode") not in {"read", "write"}
                    )
                    or not isinstance(row.get("path"), str)
                    or not Path(row["path"]).expanduser().is_absolute()
                ):
                    raise ValueError("access audit row is invalid")
                parsed_rows += 1
        except (OSError, UnicodeDecodeError, ValueError):
            missing.append(f"{name}:invalid_jsonl")
        else:
            if parsed_rows == 0 and not (
                name == "access-audit.jsonl" and allow_empty_access_audit
            ):
                missing.append(f"{name}:empty")
    outcome_path = Path(trial_dir) / "outcome" / "result.json"
    if not _path_exists(outcome_path):
        missing.append("outcome/result.json")
    else:
        try:
            outcome = json.loads(_read_private_file(outcome_path))
            if not isinstance(outcome, dict) or not outcome:
                raise ValueError("outcome must be a non-empty object")
        except (OSError, UnicodeDecodeError, ValueError):
            missing.append("outcome/result.json:invalid")
    return missing


def _build_completion_isolation(
    trial_dir: Path,
    evidence: Mapping[str, Any] | None,
    read_allow_roots: Sequence[str | os.PathLike[str]],
    write_allow_roots: Sequence[str | os.PathLike[str]],
    *,
    evidence_tier: Mapping[str, Any] | None = None,
    access_audit_complete: bool = True,
    access_roots_enforced: bool = True,
) -> dict[str, Any]:
    if not isinstance(evidence, Mapping):
        raise ValueError("completion requires isolation evidence")
    if not isinstance(access_audit_complete, bool):
        raise ValueError("access_audit_complete must be boolean")
    if not isinstance(access_roots_enforced, bool):
        raise ValueError("access_roots_enforced must be boolean")
    tier = evidence_tier_declaration(
        {} if evidence_tier is None else {"evidence_tier": evidence_tier}
    )
    for roots, label in (
        (read_allow_roots, "read"),
        (write_allow_roots, "write"),
    ):
        if isinstance(roots, (str, bytes)) or not isinstance(roots, Sequence):
            raise ValueError(f"completion {label} roots must be a sequence")
    evidence_snapshot = {
        field: evidence.get(field) for field in ISOLATION_EVIDENCE_FIELDS
    }
    access_events = load_private_jsonl(Path(trial_dir) / "access-audit.jsonl")
    assessment = assess_isolation(
        evidence_snapshot,
        access_events,
        read_allow_roots,
        write_allow_roots,
        forbidden_write_paths=[
            Path(trial_dir) / "trial.json",
            Path(trial_dir) / "events.jsonl",
            Path(trial_dir) / "access-audit.jsonl",
        ],
    )
    limitations: list[str] = []
    waived_items = set(tier["waived_items"])
    access_missing_is_waived = (
        not access_audit_complete
        and tier["requested_tier"] == "advisory-paired"
        and "complete_access_audit" in waived_items
        and set(assessment["file_reasons"]) <= {"access_audit_missing"}
    )
    if assessment["file_access_status"] != "ok" and not access_missing_is_waived:
        raise ValueError(f"completion isolation check failed: {assessment['reasons']}")
    if not access_audit_complete:
        if (
            tier["requested_tier"] != "advisory-paired"
            or "complete_access_audit" not in waived_items
        ):
            raise ValueError("completion isolation check failed: access audit incomplete")
        limitations.append("complete_access_audit")
    if not access_roots_enforced:
        if (
            tier["requested_tier"] != "advisory-paired"
            or "access_root_enforcement" not in waived_items
        ):
            raise ValueError("completion isolation check failed: access roots unenforced")
        limitations.append("access_root_enforcement")
    if assessment["memory_isolation_status"] == "contaminated":
        raise ValueError(f"completion isolation check failed: {assessment['reasons']}")
    if assessment["memory_isolation_status"] != "ok":
        if tier["requested_tier"] != "advisory-paired":
            raise ValueError(
                f"completion isolation check failed: {assessment['reasons']}"
            )
        memory_reasons = set(assessment["memory_reasons"])
        if "provider_persistence_not_disabled" in memory_reasons:
            if "provider_side_persistence_proof" not in waived_items:
                raise ValueError(
                    f"completion isolation check failed: {assessment['reasons']}"
                )
            limitations.append("provider_side_persistence_proof")
            memory_reasons.remove("provider_persistence_not_disabled")
        if memory_reasons:
            if "memory_isolation_proof" not in waived_items:
                raise ValueError(
                    f"completion isolation check failed: {assessment['reasons']}"
                )
            limitations.append("memory_isolation_proof")
    limitations.sort()
    return {
        "schema_version": 1,
        "evidence": evidence_snapshot,
        "evidence_hash": canonical_hash(evidence_snapshot),
        "read_allow_roots": assessment["normalized_read_allow_roots"],
        "write_allow_roots": assessment["normalized_write_allow_roots"],
        "status": "advisory_limited" if limitations else "ok",
        "file_access_status": (
            assessment["file_access_status"]
            if access_audit_complete and access_roots_enforced
            else "unverified"
        ),
        "memory_isolation_status": (
            "unverified"
            if {"memory_isolation_proof", "provider_side_persistence_proof"}
            & set(limitations)
            else assessment["memory_isolation_status"]
        ),
        "evidence_tier": tier,
        "coverage_limitations": limitations,
    }


def _completion_binding_hash(
    trial_dir: Path,
    payload: Mapping[str, Any],
) -> str:
    evidence_files = {
        name: canonical_hash(_read_private_file(Path(trial_dir) / name))
        for name in (
            "events.jsonl",
            "access-audit.jsonl",
            "outcome/result.json",
        )
    }
    return canonical_hash(
        {
            "artifact_contract": "skill-effectiveness-completion-binding-v1",
            "trial_fingerprint": payload.get("trial_fingerprint"),
            "status": payload.get("status"),
            "state_version": payload.get("state_version"),
            "completion_claim": payload.get("completion_claim"),
            "resume_cursor": payload.get("resume_cursor"),
            "completion_isolation": payload.get("completion_isolation"),
            "evidence_files": evidence_files,
        }
    )


@contextmanager
def _checkpoint_lock(trial_dir: Path):
    trial_dir = Path(trial_dir)
    _ensure_private_directory(trial_dir)
    lock_path = trial_dir / ".trial.lock"
    _reject_symlink(lock_path)
    flags = os.O_CREAT | os.O_RDWR | getattr(os, "O_NOFOLLOW", 0)
    descriptor = os.open(lock_path, flags, 0o600)
    try:
        lock_stat = os.fstat(descriptor)
        if not stat.S_ISREG(lock_stat.st_mode):
            raise ValueError("trial checkpoint lock is not a regular file")
        if lock_stat.st_uid != os.geteuid():
            raise ValueError("trial checkpoint lock must be owned by caller")
        os.fchmod(descriptor, 0o600)
        fcntl.flock(descriptor, fcntl.LOCK_EX)
        yield
    finally:
        try:
            fcntl.flock(descriptor, fcntl.LOCK_UN)
        finally:
            os.close(descriptor)


@contextmanager
def _prepare_lock(trial_dir: Path, output_root: Path):
    """Serialize first publication for one deterministic trial identity."""

    trial_dir = Path(trial_dir)
    parent = trial_dir.parent
    _ensure_private_directory(parent, output_root)
    lock_path = parent / f".{trial_dir.name}.prepare.lock"
    _reject_symlink(lock_path)
    flags = os.O_CREAT | os.O_RDWR | getattr(os, "O_NOFOLLOW", 0)
    descriptor = os.open(lock_path, flags, 0o600)
    try:
        lock_stat = os.fstat(descriptor)
        if not stat.S_ISREG(lock_stat.st_mode):
            raise ValueError("trial prepare lock is not a regular file")
        if lock_stat.st_uid != os.geteuid():
            raise ValueError("trial prepare lock must be owned by caller")
        os.fchmod(descriptor, 0o600)
        fcntl.flock(descriptor, fcntl.LOCK_EX)
        yield
    finally:
        try:
            fcntl.flock(descriptor, fcntl.LOCK_UN)
        finally:
            os.close(descriptor)


def _prepare_trial_artifact_locked(
    *,
    output_root: Path,
    trial_dir: Path,
    trial_file: Path,
    fixed_artifact_fields: Mapping[str, Any],
    fingerprint: str,
    budget: Mapping[str, Any],
    expected_isolation_evidence: Mapping[str, Any] | None,
    expected_read_allow_roots: Sequence[str | os.PathLike[str]],
    expected_write_allow_roots: Sequence[str | os.PathLike[str]],
) -> dict[str, Any]:
    if _path_exists(trial_file):
        _ensure_private_directory(trial_dir, output_root)
        _ensure_private_directory(trial_dir / "outcome", output_root)
        trial_payload = _read_private_file(trial_file)
        try:
            existing = json.loads(trial_payload)
        except (UnicodeDecodeError, ValueError) as exc:
            raise ValueError("existing trial artifact is unreadable") from exc
        if not isinstance(existing, dict):
            raise ValueError("existing trial artifact must be an object")
        allowed_artifact_fields = set(fixed_artifact_fields) | {
            "status",
            "state_version",
            "completion_claim",
            "resume_cursor",
            "stop_reason",
            "completion_isolation",
            "completion_binding_hash",
        }
        if set(existing) - allowed_artifact_fields:
            raise ValueError("existing trial artifact has unknown fields")
        if any(
            existing.get(field) != value
            for field, value in fixed_artifact_fields.items()
        ):
            if existing.get("trial_fingerprint") != fingerprint:
                raise ValueError("existing trial fingerprint mismatch")
            raise ValueError(
                "existing trial fixed fields do not match fingerprint inputs"
            )
        existing_status = existing.get("status")
        if existing_status not in TRIAL_STATUSES:
            raise ValueError("existing trial status is invalid")
        state_version = existing.get("state_version")
        if (
            not isinstance(state_version, int)
            or isinstance(state_version, bool)
            or state_version < 0
        ):
            raise ValueError("existing trial state_version is invalid")
        if existing.get("completion_claim") is not (existing_status == "completed"):
            raise ValueError("existing trial completion claim is inconsistent")
        if existing_status == "completed":
            if any(value is not None for value in budget.values()):
                completion_cursor = existing.get("resume_cursor")
                if (
                    not isinstance(completion_cursor, Mapping)
                    or "consumed_budget" not in completion_cursor
                ):
                    raise ValueError("completed trial consumption cursor is missing")
                _validated_consumed_budget(completion_cursor, budget)
            completion_isolation = existing.get("completion_isolation")
            if not isinstance(completion_isolation, Mapping):
                raise ValueError("completed trial isolation evidence is missing")
            has_evidence_tier = "evidence_tier" in completion_isolation
            has_coverage_limitations = "coverage_limitations" in completion_isolation
            if has_evidence_tier is not has_coverage_limitations:
                raise ValueError("completed trial isolation evidence is inconsistent")
            expected_evidence_tier = checkpoint_evidence_tier(
                existing.get("registry_schema")
            )
            if completion_isolation.get("evidence_tier") != expected_evidence_tier:
                raise ValueError("completed trial evidence tier does not match registry")
            coverage_limitations = completion_isolation.get(
                "coverage_limitations", ()
            )
            missing = _completion_evidence_missing(
                trial_dir,
                allow_empty_access_audit=(
                    "complete_access_audit" in coverage_limitations
                ),
            )
            if missing:
                raise ValueError(f"completed trial evidence missing: {missing}")
            completion_binding_hash = existing.get("completion_binding_hash")
            if completion_binding_hash is None:
                raise ValueError("completed trial completion binding is missing")
            if (
                not isinstance(completion_binding_hash, str)
                or not HASH_PATTERN.fullmatch(completion_binding_hash)
                or completion_binding_hash
                != _completion_binding_hash(trial_dir, existing)
            ):
                raise ValueError("completed trial completion binding mismatch")
            if not isinstance(expected_isolation_evidence, Mapping):
                raise ValueError(
                    "completed trial expected isolation evidence is missing"
                )
            if not expected_read_allow_roots or not expected_write_allow_roots:
                raise ValueError("completed trial expected isolation roots are missing")
            replayed_isolation = _build_completion_isolation(
                trial_dir,
                expected_isolation_evidence,
                expected_read_allow_roots,
                expected_write_allow_roots,
                evidence_tier=completion_isolation.get("evidence_tier"),
                access_audit_complete=(
                    "complete_access_audit"
                    not in completion_isolation.get("coverage_limitations", ())
                ),
                access_roots_enforced=(
                    "access_root_enforcement" not in coverage_limitations
                ),
            )
            if replayed_isolation != completion_isolation:
                raise ValueError("completed trial isolation evidence is inconsistent")
            return {
                "mode": "complete",
                "trial_dir": str(trial_dir),
                "state_version": state_version,
            }
        if existing_status in {"contaminated", "failed"}:
            raise ValueError(f"trial is terminal: {existing_status}")
        if existing_status in {"running", "interim-budget-stop"} and (
            not isinstance(existing.get("resume_cursor"), Mapping)
            or "consumed_budget" not in existing["resume_cursor"]
        ):
            label = "running trial" if existing_status == "running" else "budget-stop"
            raise ValueError(f"{label} resume cursor is missing consumption")
        return {
            "mode": "resume",
            "trial_dir": str(trial_dir),
            "state_version": state_version,
            "remaining_budget": _remaining_budget(
                budget, existing.get("resume_cursor")
            ),
        }

    if _path_exists(trial_dir):
        _reject_symlink(trial_dir)
        raise ValueError("incomplete trial directory exists without trial.json")

    _ensure_private_directory(trial_dir, output_root)
    _ensure_private_directory(trial_dir / "outcome", output_root)
    payload = {
        **fixed_artifact_fields,
        "status": "prepared",
        "state_version": 0,
        "completion_claim": False,
    }
    write_json_atomic(trial_file, payload)
    write_jsonl_atomic(trial_dir / "events.jsonl", [])
    write_jsonl_atomic(trial_dir / "access-audit.jsonl", [])
    return {"mode": "created", "trial_dir": str(trial_dir), "state_version": 0}


def _checkpoint_trial_locked(
    trial_dir: Path,
    status: str,
    resume_cursor: Mapping[str, Any] | None = None,
    stop_reason: str | None = None,
    *,
    isolation_evidence: Mapping[str, Any] | None = None,
    read_allow_roots: Sequence[str | os.PathLike[str]] = (),
    write_allow_roots: Sequence[str | os.PathLike[str]] = (),
    expected_state_version: int | None = None,
    evidence_tier: Mapping[str, Any] | None = None,
    access_audit_complete: bool = True,
    access_roots_enforced: bool = True,
) -> int:

    allowed_statuses = TRIAL_STATUSES - {"prepared"}
    if status not in allowed_statuses:
        raise ValueError(f"invalid trial checkpoint status: {status}")
    trial_file = Path(trial_dir) / "trial.json"
    try:
        payload = json.loads(_read_private_file(trial_file))
    except (OSError, UnicodeDecodeError, ValueError) as exc:
        raise ValueError("trial artifact is unreadable") from exc
    if not isinstance(payload, dict):
        raise ValueError("trial artifact must be an object")
    if not HASH_PATTERN.fullmatch(str(payload.get("trial_fingerprint", ""))):
        raise ValueError("trial fingerprint is missing")
    state_version = payload.get("state_version")
    if (
        not isinstance(state_version, int)
        or isinstance(state_version, bool)
        or state_version < 0
    ):
        raise ValueError("trial state_version is invalid")
    if expected_state_version is not None:
        if (
            not isinstance(expected_state_version, int)
            or isinstance(expected_state_version, bool)
            or expected_state_version < 0
        ):
            raise ValueError("expected_state_version is invalid")
        if expected_state_version != state_version:
            raise ValueError(
                "trial state version mismatch: "
                f"expected={expected_state_version} actual={state_version}"
            )
    current_status = payload.get("status")
    if current_status not in TRIAL_STATUSES:
        raise ValueError("trial status is invalid")
    if payload.get("completion_claim") is not (current_status == "completed"):
        raise ValueError("trial completion claim is inconsistent")
    if current_status in {"completed", "contaminated", "failed"}:
        raise ValueError(f"terminal trial cannot transition from {current_status}")
    if resume_cursor is not None and not isinstance(resume_cursor, Mapping):
        raise ValueError("resume_cursor must be an object")
    next_cursor = dict(
        resume_cursor if resume_cursor is not None else payload.get("resume_cursor", {})
    )
    previous_consumed = None
    previous_cursor = payload.get("resume_cursor")
    if isinstance(previous_cursor, Mapping) and "consumed_budget" in previous_cursor:
        previous_consumed = _validated_consumed_budget(
            previous_cursor, payload["budget"]
        )
    elif current_status == "interim-budget-stop":
        raise ValueError("budget-stop resume cursor is missing consumption")
    if status == "completed" and any(
        value is not None for value in payload["budget"].values()
    ):
        if "consumed_budget" not in next_cursor:
            raise ValueError("finite-budget completion requires a consumption cursor")
        _validated_consumed_budget(next_cursor, payload["budget"])
    if status == "running" and previous_consumed is None:
        _validated_consumed_budget(next_cursor, payload["budget"])
    if status == "interim-budget-stop":
        next_consumed = _validated_consumed_budget(next_cursor, payload["budget"])
        if previous_consumed is not None:
            if any(
                next_consumed[field] < previous_consumed[field]
                for field in REQUIRED_BUDGETS
            ):
                raise ValueError("budget-stop consumed values must be monotonic")
            if all(
                next_consumed[field] == previous_consumed[field]
                for field in REQUIRED_BUDGETS
            ):
                raise ValueError("budget-stop checkpoint must advance consumption")
    elif previous_consumed is not None:
        next_consumed = _validated_consumed_budget(next_cursor, payload["budget"])
        if any(
            next_consumed[field] < previous_consumed[field]
            for field in REQUIRED_BUDGETS
        ):
            raise ValueError("budget-stop consumed values must be monotonic")
    if previous_consumed is not None and (
        next_cursor["next_run_order"] < previous_cursor["next_run_order"]
    ):
        raise ValueError("budget-stop next_run_order must be monotonic")
    if status == "completed":
        normalized_tier = evidence_tier_declaration(
            {} if evidence_tier is None else {"evidence_tier": evidence_tier}
        )
        expected_tier = checkpoint_evidence_tier(payload.get("registry_schema"))
        if normalized_tier != expected_tier:
            raise ValueError("checkpoint evidence tier does not match registry")
        allow_empty_access_audit = (
            not access_audit_complete
            and normalized_tier["requested_tier"] == "advisory-paired"
            and "complete_access_audit" in normalized_tier["waived_items"]
        )
        missing = _completion_evidence_missing(
            Path(trial_dir),
            allow_empty_access_audit=allow_empty_access_audit,
        )
        if missing:
            raise ValueError(f"completion evidence missing: {missing}")
        completion_isolation = _build_completion_isolation(
            trial_dir,
            isolation_evidence,
            read_allow_roots,
            write_allow_roots,
            evidence_tier=evidence_tier,
            access_audit_complete=access_audit_complete,
            access_roots_enforced=access_roots_enforced,
        )
    else:
        completion_isolation = None
    payload["status"] = status
    payload["state_version"] = state_version + 1
    payload["completion_claim"] = status == "completed"
    payload["resume_cursor"] = next_cursor
    if stop_reason:
        payload["stop_reason"] = stop_reason
    else:
        payload.pop("stop_reason", None)
    if completion_isolation is None:
        payload.pop("completion_isolation", None)
        payload.pop("completion_binding_hash", None)
    else:
        payload["completion_isolation"] = completion_isolation
        payload["completion_binding_hash"] = _completion_binding_hash(
            trial_dir,
            payload,
        )
    write_json_atomic(trial_file, payload)
    return payload["state_version"]


def checkpoint_trial(
    trial_dir: Path,
    status: str,
    resume_cursor: Mapping[str, Any] | None = None,
    stop_reason: str | None = None,
    *,
    isolation_evidence: Mapping[str, Any] | None = None,
    read_allow_roots: Sequence[str | os.PathLike[str]] = (),
    write_allow_roots: Sequence[str | os.PathLike[str]] = (),
    expected_state_version: int | None = None,
    evidence_tier: Mapping[str, Any] | None = None,
    access_audit_complete: bool = True,
    access_roots_enforced: bool = True,
) -> int:
    """Persist one serialized, optionally compare-and-swap state transition."""

    with _checkpoint_lock(Path(trial_dir)):
        return _checkpoint_trial_locked(
            trial_dir,
            status,
            resume_cursor,
            stop_reason,
            isolation_evidence=isolation_evidence,
            read_allow_roots=read_allow_roots,
            write_allow_roots=write_allow_roots,
            expected_state_version=expected_state_version,
            evidence_tier=evidence_tier,
            access_audit_complete=access_audit_complete,
            access_roots_enforced=access_roots_enforced,
        )


def _validate_judge_text(
    value: str, forbidden_arm_ids: frozenset[str], path: str
) -> None:
    if JUDGE_METADATA_TOKEN.search(value):
        raise ValueError(f"judge metadata token leak at {path}")
    for arm_id in forbidden_arm_ids:
        if re.search(
            rf"(?<![A-Za-z0-9._-]){re.escape(arm_id)}(?![A-Za-z0-9._-])",
            value,
        ):
            raise ValueError(f"judge arm id leak at {path}")


def _validate_judge_payload(
    value: Any,
    forbidden_arm_ids: frozenset[str],
    path: str = "judge_payload",
) -> None:
    if isinstance(value, dict):
        for key, child in value.items():
            key_text = str(key)
            _validate_judge_text(key_text, forbidden_arm_ids, f"{path}.<key>")
            snake_key = re.sub(r"([a-z0-9])([A-Z])", r"\1_\2", key_text)
            normalized_key = re.sub(r"[^a-z0-9]+", "_", snake_key.lower()).strip("_")
            if (
                normalized_key in JUDGE_METADATA_KEYS
                or normalized_key.replace("_", "") in JUDGE_METADATA_KEYS_COMPACT
            ):
                raise ValueError(f"judge metadata leak at {path}.{key}")
            _validate_judge_payload(child, forbidden_arm_ids, f"{path}.{key}")
    elif isinstance(value, list):
        for index, child in enumerate(value):
            _validate_judge_payload(child, forbidden_arm_ids, f"{path}[{index}]")
    elif isinstance(value, str):
        _validate_judge_text(value, forbidden_arm_ids, path)


def arm_registry_hash(
    registered_manifests: Mapping[str, Mapping[str, Any]],
) -> str:
    """Hash the complete frozen arm registry used by a blinding plan."""

    if not isinstance(registered_manifests, Mapping) or not registered_manifests:
        raise ValueError("registered_manifests must be a non-empty mapping")
    manifest_hashes: dict[str, str] = {}
    for arm_id, manifest in registered_manifests.items():
        safe_arm_id = _safe_segment(arm_id, "registered arm_id")
        if not isinstance(manifest, Mapping):
            raise ValueError(f"registered manifest is not an object: {safe_arm_id}")
        errors = validate_frozen_manifest(manifest)
        if errors:
            raise ValueError(f"registered manifest is invalid: {safe_arm_id}: {errors}")
        if manifest.get("arm_id") != safe_arm_id:
            raise ValueError(f"registered manifest arm_id mismatch: {safe_arm_id}")
        manifest_hashes[safe_arm_id] = manifest["manifest_hash"]
    return canonical_hash({"schema_version": 1, "arm_manifest_hashes": manifest_hashes})


def write_arm_registry_plan(
    path: Path,
    registered_manifests: Mapping[str, Mapping[str, Any]],
) -> dict[str, Any]:
    """Freeze the complete local arm registry before outcomes are blinded."""

    treatments = {
        manifest.get("treatment") for manifest in registered_manifests.values()
    }
    missing_treatments = REQUIRED_CAUSAL_TREATMENTS - treatments
    if missing_treatments:
        raise ValueError(
            f"arm registry is missing required treatments: {sorted(missing_treatments)}"
        )
    registry_hash = arm_registry_hash(registered_manifests)
    core = {
        "schema_version": 1,
        "artifact_contract": ARM_REGISTRY_PLAN_CONTRACT,
        "arm_manifest_hashes": {
            arm_id: registered_manifests[arm_id]["manifest_hash"]
            for arm_id in sorted(registered_manifests)
        },
        "arm_registry_hash": registry_hash,
    }
    payload = {**core, "plan_hash": canonical_hash(core)}
    _write_private_json_once(path, payload, "arm registry plan")
    return payload


def _validated_profile_registry(
    registered_manifests: Mapping[str, Mapping[str, Any]],
) -> dict[str, Mapping[str, Any]]:
    if not isinstance(registered_manifests, Mapping) or not registered_manifests:
        raise ValueError("registered_manifests must be a non-empty mapping")
    validated: dict[str, Mapping[str, Any]] = {}
    treatments: Counter[str] = Counter()
    scopes: set[str] = set()
    for arm_id, manifest in registered_manifests.items():
        safe_arm_id = _safe_segment(arm_id, "registered arm_id")
        if not isinstance(manifest, Mapping):
            raise ValueError(f"registered manifest is not an object: {safe_arm_id}")
        if manifest_registry_schema(manifest) != PROFILE_REGISTRY_SCHEMA:
            raise ValueError(
                f"profile registry rejects a skill-content manifest: {safe_arm_id}"
            )
        errors = validate_frozen_profile_manifest(manifest)
        if errors:
            raise ValueError(f"registered manifest is invalid: {safe_arm_id}: {errors}")
        if manifest.get("arm_id") != safe_arm_id:
            raise ValueError(f"registered manifest arm_id mismatch: {safe_arm_id}")
        treatments[str(manifest["treatment"])] += 1
        scopes.add(str(manifest["scope"]))
        validated[safe_arm_id] = manifest
    missing = REQUIRED_PROFILE_TREATMENTS - set(treatments)
    if missing:
        raise ValueError(
            f"profile registry is missing required treatments: {sorted(missing)}"
        )
    if treatments["off"] != 1 or treatments["full"] != 1:
        raise ValueError("profile registry needs exactly one OFF and one FULL arm")
    if treatments.get("reference", 0) > 1:
        raise ValueError("profile registry allows at most one reference arm")
    if len(scopes) != 1:
        raise ValueError("profile registry arms must share one scope")
    return validated


def profile_arm_registry_hash(
    registered_manifests: Mapping[str, Mapping[str, Any]],
) -> str:
    """Hash the complete frozen paired-profile registry used by a plan."""

    validated = _validated_profile_registry(registered_manifests)
    return canonical_hash(
        {
            "schema_version": 1,
            "registry_schema": PROFILE_REGISTRY_SCHEMA,
            "arm_manifest_hashes": {
                arm_id: validated[arm_id]["manifest_hash"] for arm_id in validated
            },
        }
    )


def write_profile_arm_registry_plan(
    path: Path,
    registered_manifests: Mapping[str, Mapping[str, Any]],
) -> dict[str, Any]:
    """Freeze the paired-profile registry before any outcome exists."""

    validated = _validated_profile_registry(registered_manifests)
    core = {
        "schema_version": 1,
        "artifact_contract": PROFILE_ARM_REGISTRY_PLAN_CONTRACT,
        "registry_schema": PROFILE_REGISTRY_SCHEMA,
        "arm_manifest_hashes": {
            arm_id: validated[arm_id]["manifest_hash"] for arm_id in sorted(validated)
        },
        "arm_registry_hash": profile_arm_registry_hash(registered_manifests),
    }
    payload = {**core, "plan_hash": canonical_hash(core)}
    _write_private_json_once(path, payload, "profile arm registry plan")
    return payload


def load_profile_arm_registry_plan(
    path: Path,
    registered_manifests: Mapping[str, Mapping[str, Any]],
) -> dict[str, Any]:
    """Read back one frozen paired-profile registry plan and bind it."""

    validated = _validated_profile_registry(registered_manifests)
    path = _external_private_path(
        path, "profile arm registry plan", create_parent=False
    )
    payload = load_private_json(path)
    expected_fields = {
        "schema_version",
        "artifact_contract",
        "registry_schema",
        "arm_manifest_hashes",
        "arm_registry_hash",
        "plan_hash",
    }
    if not isinstance(payload, Mapping) or set(payload) != expected_fields:
        raise ValueError("frozen profile registry plan field set is invalid")
    core = {field: payload[field] for field in expected_fields - {"plan_hash"}}
    if (
        payload.get("schema_version") != 1
        or payload.get("artifact_contract") != PROFILE_ARM_REGISTRY_PLAN_CONTRACT
        or payload.get("registry_schema") != PROFILE_REGISTRY_SCHEMA
        or payload.get("plan_hash") != canonical_hash(core)
    ):
        raise ValueError("frozen profile registry plan hash is invalid")
    expected_manifest_hashes = {
        arm_id: validated[arm_id]["manifest_hash"] for arm_id in sorted(validated)
    }
    if (
        payload.get("arm_manifest_hashes") != expected_manifest_hashes
        or payload.get("arm_registry_hash")
        != profile_arm_registry_hash(registered_manifests)
    ):
        raise ValueError("frozen profile registry plan mismatch")
    return dict(payload)


def _load_arm_registry_plan(
    path: Path,
    registered_manifests: Mapping[str, Mapping[str, Any]],
) -> dict[str, Any]:
    treatments = {
        manifest.get("treatment") for manifest in registered_manifests.values()
    }
    missing_treatments = REQUIRED_CAUSAL_TREATMENTS - treatments
    if missing_treatments:
        raise ValueError(
            f"arm registry is missing required treatments: {sorted(missing_treatments)}"
        )
    path = _external_private_path(path, "arm registry plan", create_parent=False)
    payload = load_private_json(path)
    expected_fields = {
        "schema_version",
        "artifact_contract",
        "arm_manifest_hashes",
        "arm_registry_hash",
        "plan_hash",
    }
    if not isinstance(payload, Mapping) or set(payload) != expected_fields:
        raise ValueError("frozen registry plan field set is invalid")
    core = {field: payload[field] for field in expected_fields - {"plan_hash"}}
    if (
        payload.get("schema_version") != 1
        or payload.get("artifact_contract") != ARM_REGISTRY_PLAN_CONTRACT
        or payload.get("plan_hash") != canonical_hash(core)
    ):
        raise ValueError("frozen registry plan hash is invalid")
    expected_manifest_hashes = {
        arm_id: registered_manifests[arm_id]["manifest_hash"]
        for arm_id in sorted(registered_manifests)
    }
    expected_registry_hash = arm_registry_hash(registered_manifests)
    if (
        payload.get("arm_manifest_hashes") != expected_manifest_hashes
        or payload.get("arm_registry_hash") != expected_registry_hash
    ):
        raise ValueError("frozen registry plan mismatch")
    return dict(payload)


def _blind_pair_parts(
    left: Mapping[str, Any],
    right: Mapping[str, Any],
    blinding_key: bytes,
    registered_manifests: Mapping[str, Mapping[str, Any]],
    registry_plan_path: Path,
) -> tuple[dict[str, Any], dict[str, Any]]:
    if not isinstance(blinding_key, bytes) or len(blinding_key) < 32:
        raise ValueError("blinding_key must contain at least 32 secret bytes")

    registry_plan = _load_arm_registry_plan(registry_plan_path, registered_manifests)
    expected_registry_hash = registry_plan["arm_registry_hash"]
    expected_plan_hash = registry_plan["plan_hash"]
    forbidden_arm_ids = frozenset(registered_manifests)

    outcomes = [left, right]
    arm_ids = []
    outcome_ids = []
    judge_payloads = []
    pair_members = []
    for outcome in outcomes:
        outcome_id = outcome.get("outcome_id")
        if not _is_safe_id(outcome_id):
            raise ValueError("outcome_id must match [A-Za-z0-9._-]+")
        outcome_ids.append(outcome_id)
        arm_id = _safe_segment(outcome.get("arm_id"), "arm_id")
        arm_ids.append(arm_id)
        if arm_id not in registered_manifests:
            raise ValueError("pair arm ids must belong to registered_arm_ids")
        manifest_hash = outcome.get("manifest_hash")
        if manifest_hash != registered_manifests[arm_id]["manifest_hash"]:
            raise ValueError("outcome manifest binding mismatch")
        if outcome.get("arm_registry_plan_hash") != expected_plan_hash:
            raise ValueError("outcome arm registry plan binding mismatch")
        if "judge_payload" not in outcome:
            raise ValueError("judge_payload is required")
        try:
            judge_payloads.append(json.loads(canonical_json(outcome["judge_payload"])))
        except (TypeError, ValueError) as exc:
            raise ValueError("judge_payload must be canonical JSON") from exc
    if len(set(arm_ids)) != 2:
        raise ValueError("blind_pair requires two distinct arm ids")
    if not set(arm_ids).issubset(forbidden_arm_ids):
        raise ValueError("pair arm ids must belong to registered_arm_ids")
    if len(set(outcome_ids)) != 2:
        raise ValueError("blind_pair requires two distinct outcome ids")
    for judge_payload in judge_payloads:
        _validate_judge_payload(judge_payload, forbidden_arm_ids)
    for index, outcome_id in enumerate(outcome_ids):
        pair_members.append(
            {
                "outcome_id": outcome_id,
                "arm_id": arm_ids[index],
                "manifest_hash": registered_manifests[arm_ids[index]]["manifest_hash"],
                "judge_payload_hash": canonical_hash(judge_payloads[index]),
            }
        )
    pair_members.sort(key=lambda member: member["outcome_id"])
    pair_id = (
        "pair-"
        + hmac.new(
            blinding_key,
            canonical_json(
                {
                    "arm_registry_hash": expected_registry_hash,
                    "arm_registry_plan_hash": expected_plan_hash,
                    "members": pair_members,
                }
            ),
            hashlib.sha256,
        ).hexdigest()
    )
    order = sorted(
        range(2),
        key=lambda index: hmac.new(
            blinding_key,
            canonical_json(
                {
                    "pair_id": pair_id,
                    "outcome_id": outcome_ids[index],
                }
            ),
            hashlib.sha256,
        ).hexdigest(),
    )
    labels = {"A": order[0], "B": order[1]}
    judge_input = {
        "schema_version": 1,
        "pair_id": pair_id,
        "A": judge_payloads[labels["A"]],
        "B": judge_payloads[labels["B"]],
    }
    mapping = {
        "schema_version": 1,
        "pair_id": pair_id,
        "arm_registry_hash": expected_registry_hash,
        "arm_registry_plan_hash": expected_plan_hash,
        "mapping": {
            "A": outcome_ids[labels["A"]],
            "B": outcome_ids[labels["B"]],
        },
    }
    return judge_input, mapping


def blind_pair(
    left: Mapping[str, Any],
    right: Mapping[str, Any],
    blinding_key: bytes,
    registered_manifests: Mapping[str, Mapping[str, Any]],
    registry_plan_path: Path,
) -> dict[str, Any]:
    """Return only judge-visible A/B content; identity mapping is separate."""

    judge_input, _ = _blind_pair_parts(
        left,
        right,
        blinding_key,
        registered_manifests,
        registry_plan_path,
    )
    return judge_input


def build_pair_mapping(
    left: Mapping[str, Any],
    right: Mapping[str, Any],
    blinding_key: bytes,
    registered_manifests: Mapping[str, Mapping[str, Any]],
    registry_plan_path: Path,
) -> dict[str, Any]:
    """Return the controller-only identity mapping, never judge content."""

    _, mapping = _blind_pair_parts(
        left,
        right,
        blinding_key,
        registered_manifests,
        registry_plan_path,
    )
    return mapping


def build_schedule(
    tasks: Sequence[Mapping[str, Any]],
    arm_ids: Sequence[str],
    samples: int,
    seed: int,
) -> list[dict[str, Any]]:
    if not isinstance(samples, int) or isinstance(samples, bool) or samples < 3:
        raise ValueError(
            "causal trial plans require at least three samples per task-arm"
        )
    if not isinstance(seed, int) or isinstance(seed, bool):
        raise ValueError("schedule seed must be an integer")
    if not tasks or not arm_ids:
        raise ValueError("schedule requires tasks and arms")
    task_ids = []
    for task in tasks:
        task_ids.append(_safe_segment(task.get("task_id"), "task_id"))
        if task.get("task_family") not in TASK_FAMILIES:
            raise ValueError("schedule task_family is invalid")
    if len(set(task_ids)) != len(task_ids):
        raise ValueError("duplicate task_id")
    safe_arms = [_safe_segment(arm_id, "arm_id") for arm_id in arm_ids]
    if len(set(safe_arms)) != len(safe_arms):
        raise ValueError("duplicate arm_id")
    rows = [
        {
            "task_id": task["task_id"],
            "task_family": task["task_family"],
            "arm_id": arm_id,
            "sample_index": sample_index,
        }
        for sample_index in range(1, samples + 1)
        for task in tasks
        for arm_id in safe_arms
    ]
    random.Random(seed).shuffle(rows)
    for index, row in enumerate(rows, start=1):
        row["run_order"] = index
    return rows


def _assess_capability_matrix_entries(
    entries: Sequence[Mapping[str, Any]],
) -> dict[str, Any]:
    """Select causal-core task families from runner/provider isolation evidence."""

    normalized = []
    causal_families = set()
    for index, entry in enumerate(entries):
        reasons = []
        if not isinstance(entry, Mapping):
            normalized.append(
                {
                    "matrix_index": index,
                    "eligible": False,
                    "reasons": ["entry_not_object"],
                }
            )
            continue
        runner = entry.get("runner")
        provider = entry.get("provider")
        family = entry.get("task_family")
        if set(entry) != {
            "runner",
            "provider",
            "task_family",
            "evidence",
            "evidence_hash",
        }:
            reasons.append("entry_field_set_invalid")
        if not isinstance(runner, str) or not runner:
            reasons.append("runner_missing")
        if not isinstance(provider, str) or not provider:
            reasons.append("provider_missing")
        elif provider == "none":
            reasons.append("provider_unavailable")
        if family not in TASK_FAMILIES:
            reasons.append("task_family_invalid")
        evidence = entry.get("evidence")
        if not isinstance(evidence, Mapping):
            reasons.append("evidence_missing")
            evidence = {}
        elif set(evidence) != CAPABILITY_EVIDENCE_FIELDS:
            reasons.append("evidence_field_set_invalid")
        for field in sorted(CAPABILITY_EVIDENCE_FIELDS):
            probe = evidence.get(field)
            if not isinstance(probe, Mapping) or set(probe) != CAPABILITY_PROBE_FIELDS:
                reasons.append(f"capability_evidence_invalid:{field}")
                continue
            if not _is_safe_id(probe.get("probe_id")):
                reasons.append(f"capability_probe_id_invalid:{field}")
            observations = probe.get("observations")
            expected_observations = CAPABILITY_OBSERVATIONS[field]
            if (
                not isinstance(observations, Mapping)
                or set(observations) != set(expected_observations)
                or any(not isinstance(value, bool) for value in observations.values())
            ):
                reasons.append(f"capability_observations_invalid:{field}")
            elif probe.get("status") != "verified" or any(
                observations[name] is not expected
                for name, expected in expected_observations.items()
            ):
                reasons.append(f"{field}_unproven")
        evidence_hash = entry.get("evidence_hash")
        if not isinstance(evidence_hash, str) or not HASH_PATTERN.fullmatch(
            evidence_hash
        ):
            reasons.append("evidence_hash_invalid")
        elif isinstance(evidence, Mapping):
            evidence_envelope = {
                "runner": runner,
                "provider": provider,
                "task_family": family,
                "evidence": evidence,
            }
            if evidence_hash != canonical_hash(evidence_envelope):
                reasons.append("evidence_hash_mismatch")
        row = dict(entry)
        row["matrix_index"] = index
        row["eligible"] = not reasons
        row["reasons"] = reasons
        normalized.append(row)
        if not reasons:
            causal_families.add(family)
    return {
        "schema_version": 1,
        "status": "ready" if causal_families else "causal_core_unavailable",
        "causal_task_families": sorted(causal_families),
        "entries": normalized,
        "conclusion_boundary": (
            "causal_core_only" if causal_families else "shadow_noncausal_only"
        ),
    }


def assess_capability_matrix(
    entries: Sequence[Mapping[str, Any]],
) -> dict[str, Any]:
    """Validate declarations, but never promote in-memory evidence to ready."""

    result = _assess_capability_matrix_entries(entries)
    for row in result["entries"]:
        if row["eligible"]:
            row["eligible"] = False
            row["reasons"].append("local_probe_artifact_required")
    result["status"] = "causal_core_unavailable"
    result["causal_task_families"] = []
    result["conclusion_boundary"] = "shadow_noncausal_only"
    result["evidence_source"] = "untrusted_in_memory"
    return result


def write_capability_probe_artifact(
    path: Path,
    entry: Mapping[str, Any],
) -> dict[str, Any]:
    """Persist one local provider/runner probe result for evaluator read-back."""

    payload = {
        "schema_version": 1,
        "artifact_contract": CAPABILITY_PROBE_CONTRACT,
        "entry": dict(entry),
        "entry_hash": canonical_hash(entry),
    }
    _write_private_json_once(path, payload, "capability probe artifact")
    return payload


def assess_capability_matrix_from_artifacts(
    artifact_paths: Sequence[Path],
) -> dict[str, Any]:
    """Assess locally persisted probe artifacts without a provider whitelist."""

    entries = []
    expected_fields = {
        "schema_version",
        "artifact_contract",
        "entry",
        "entry_hash",
    }
    for path in artifact_paths:
        artifact_path = _external_private_path(
            path, "capability probe artifact", create_parent=False
        )
        payload = load_private_json(artifact_path)
        if not isinstance(payload, Mapping) or set(payload) != expected_fields:
            raise ValueError("capability probe artifact field set is invalid")
        entry = payload.get("entry")
        if (
            payload.get("schema_version") != 1
            or payload.get("artifact_contract") != CAPABILITY_PROBE_CONTRACT
            or not isinstance(entry, Mapping)
            or payload.get("entry_hash") != canonical_hash(entry)
        ):
            raise ValueError("capability probe artifact hash is invalid")
        entries.append(dict(entry))
    result = _assess_capability_matrix_entries(entries)
    result["evidence_source"] = "local_probe_artifacts"
    return result


def _rate(records: Sequence[Mapping[str, Any]], field: str) -> float:
    if not records:
        return 0.0
    return sum(record.get(field) is True for record in records) / len(records)


def _cohen_kappa(left: Sequence[str], right: Sequence[str]) -> tuple[float, float]:
    if len(left) != len(right) or not left:
        raise ValueError("pairwise calibration vectors must be non-empty and aligned")
    sample_count = len(left)
    raw_agreement = sum(a == b for a, b in zip(left, right, strict=True)) / sample_count
    left_counts = Counter(left)
    right_counts = Counter(right)
    expected_agreement = sum(
        (left_counts[value] / sample_count) * (right_counts[value] / sample_count)
        for value in CALIBRATION_VERDICTS
    )
    if expected_agreement == 1.0:
        kappa = 1.0 if raw_agreement == 1.0 else 0.0
    else:
        kappa = (raw_agreement - expected_agreement) / (1.0 - expected_agreement)
    return raw_agreement, kappa


def _evaluate_calibration(
    calibration: Mapping[str, Any],
    expected_fixture_hash: str,
    thresholds: Mapping[str, Any],
) -> dict[str, Any]:
    valid = True
    if set(calibration) != {
        "status",
        "known_answers",
        "known_answer_fixture_hash",
        "reviewers",
    }:
        valid = False
    fixture_hash = calibration.get("known_answer_fixture_hash")
    known_answers = calibration.get("known_answers")
    if (
        not isinstance(fixture_hash, str)
        or fixture_hash != expected_fixture_hash
        or not isinstance(known_answers, Sequence)
        or isinstance(known_answers, (str, bytes))
        or not known_answers
    ):
        valid = False
        known_answers = []

    truth: dict[str, str] = {}
    normalized_answers: list[dict[str, str]] = []
    for row in known_answers:
        if (
            not isinstance(row, Mapping)
            or set(row) != {"case_id", "expected_verdict"}
            or not _is_safe_id(row.get("case_id"))
            or row.get("case_id") in truth
            or row.get("expected_verdict") not in CALIBRATION_VERDICTS
        ):
            valid = False
            continue
        case_id = row["case_id"]
        verdict = row["expected_verdict"]
        truth[case_id] = verdict
        normalized_answers.append({"case_id": case_id, "expected_verdict": verdict})
    if canonical_hash(normalized_answers) != expected_fixture_hash:
        valid = False

    reviewers = calibration.get("reviewers")
    if not isinstance(reviewers, Sequence) or isinstance(reviewers, (str, bytes)):
        valid = False
        reviewers = []
    reviewer_statuses: dict[str, str] = {}
    reviewer_metrics: dict[str, dict[str, Any]] = {}
    reviewer_vectors: dict[str, list[str]] = {}
    for reviewer in reviewers:
        if (
            not isinstance(reviewer, Mapping)
            or set(reviewer) != {"family", "runs"}
            or not _is_safe_id(reviewer.get("family"))
            or reviewer.get("family") in reviewer_statuses
        ):
            valid = False
            continue
        family = reviewer["family"]
        runs = reviewer.get("runs")
        if (
            not isinstance(runs, Sequence)
            or isinstance(runs, (str, bytes))
            or len(runs) < 2
        ):
            valid = False
            continue
        normalized_runs: list[dict[str, str]] = []
        accurate = 0
        judgment_count = 0
        for run in runs:
            if not isinstance(run, Sequence) or isinstance(run, (str, bytes)):
                valid = False
                continue
            judgments: dict[str, str] = {}
            for judgment in run:
                if (
                    not isinstance(judgment, Mapping)
                    or set(judgment) != {"case_id", "verdict"}
                    or judgment.get("case_id") not in truth
                    or judgment.get("case_id") in judgments
                    or judgment.get("verdict") not in CALIBRATION_VERDICTS
                ):
                    valid = False
                    continue
                case_id = judgment["case_id"]
                verdict = judgment["verdict"]
                judgments[case_id] = verdict
                accurate += verdict == truth[case_id]
                judgment_count += 1
            if set(judgments) != set(truth):
                valid = False
                continue
            normalized_runs.append(judgments)
        if len(normalized_runs) != len(runs) or judgment_count != len(truth) * len(
            runs
        ):
            valid = False
            continue
        consistent_cases = 0
        consensus: list[str] = []
        for case_id in truth:
            verdicts = [run[case_id] for run in normalized_runs]
            counts = Counter(verdicts)
            max_count = max(counts.values())
            winners = sorted(
                verdict for verdict, count in counts.items() if count == max_count
            )
            if len(set(verdicts)) == 1:
                consistent_cases += 1
            if len(winners) != 1:
                valid = False
                consensus = []
                break
            consensus.append(winners[0])
        self_consistency = consistent_cases / len(truth) if truth else 0.0
        known_answer_accuracy = accurate / judgment_count if judgment_count else 0.0
        reviewer_statuses[family] = (
            "pass"
            if self_consistency >= thresholds["reviewer_self_consistency_min"]
            and known_answer_accuracy
            >= thresholds["reviewer_known_answer_accuracy_min"]
            else "fail"
        )
        reviewer_metrics[family] = {
            "repeat_count": len(runs),
            "case_count": len(truth),
            "self_consistency": self_consistency,
            "known_answer_accuracy": known_answer_accuracy,
        }
        if consensus:
            reviewer_vectors[family] = consensus

    pairwise_metrics: list[dict[str, Any]] = []
    mutual_status = "not_applicable_single_reviewer"
    families = sorted(reviewer_statuses)
    if len(families) >= 2:
        mutual_status = "pass"
        for index, left in enumerate(families):
            for right in families[index + 1 :]:
                if left not in reviewer_vectors or right not in reviewer_vectors:
                    valid = False
                    mutual_status = "invalid"
                    continue
                raw_agreement, kappa = _cohen_kappa(
                    reviewer_vectors[left], reviewer_vectors[right]
                )
                pairwise_metrics.append(
                    {
                        "families": [left, right],
                        "sample_count": len(truth),
                        "raw_agreement": raw_agreement,
                        "kappa": kappa,
                    }
                )
                if (
                    raw_agreement < thresholds["reviewer_pairwise_agreement_min"]
                    or kappa < thresholds["reviewer_pairwise_kappa_min"]
                ):
                    mutual_status = "fail"

    return {
        "valid": valid,
        "reviewer_statuses": reviewer_statuses,
        "reviewer_metrics": reviewer_metrics,
        "reviewer_families": families,
        "pairwise_metrics": pairwise_metrics,
        "mutual_status": mutual_status,
    }


def evaluate_reviewer_calibration(
    calibration: Mapping[str, Any], config: Mapping[str, Any]
) -> dict[str, Any]:
    """Evaluate raw reviewer judgments without running the rest of E10."""

    thresholds = _validate_pilot_config(config)
    failures: list[str] = []
    if not isinstance(calibration, Mapping) or calibration.get("status") != "evaluated":
        return {
            "status": "fail",
            "failures": ["calibration_status_invalid"],
            "valid": False,
            "reviewer_statuses": {},
            "reviewer_metrics": {},
            "reviewer_families": [],
            "pairwise_metrics": [],
            "mutual_status": "invalid",
        }
    result = _evaluate_calibration(
        calibration,
        config["reviewer_calibration_fixture_hash"],
        thresholds,
    )
    if len(result["reviewer_families"]) < thresholds["reviewer_family_count_min"]:
        failures.append("reviewer_calibration_family_count")
    if not result["valid"]:
        failures.append("calibration_evidence_invalid")
    if any(status == "fail" for status in result["reviewer_statuses"].values()):
        failures.append("reviewer_self_calibration")
    if result["mutual_status"] == "invalid":
        failures.append("calibration_evidence_invalid")
    elif result["mutual_status"] == "fail":
        failures.append("reviewer_mutual_calibration")
    return {
        "status": "pass" if not failures else "fail",
        "failures": list(dict.fromkeys(failures)),
        **result,
    }


def _evaluate_pilot_gate_records(
    records: Sequence[Mapping[str, Any]],
    calibration: Mapping[str, Any],
    config: Mapping[str, Any],
    expected_tasks: Mapping[str, str],
    expected_manifests: Mapping[str, Mapping[str, Any]],
    expected_trials: Sequence[Mapping[str, Any]],
    *,
    synthetic: bool = False,
) -> dict[str, Any]:
    """Evaluate the frozen E10 runner-validity gate over supplied trial records."""

    thresholds = _validate_pilot_config(config)
    tier_declaration = evidence_tier_declaration(config)
    requested_tier = tier_declaration["requested_tier"]
    waived_items = list(tier_declaration["waived_items"])
    waived_gate_checks = {
        ADVISORY_WAIVED_GATE_CHECKS[item]
        for item in waived_items
        if ADVISORY_WAIVED_GATE_CHECKS[item] is not None
    }
    if not isinstance(calibration, Mapping):
        raise ValueError("calibration must be an object")
    if any(not isinstance(record, Mapping) for record in records):
        raise ValueError("trial records must be objects")

    failures: list[str] = []
    warnings: list[str] = []
    not_evaluated_checks: list[str] = []
    if not isinstance(expected_tasks, Mapping) or not expected_tasks:
        raise ValueError("expected_tasks must be a non-empty mapping")
    if not isinstance(expected_manifests, Mapping) or not expected_manifests:
        raise ValueError("expected_manifests must be a non-empty mapping")
    planned_tasks = {
        _safe_segment(task_id, "task_id"): family
        for task_id, family in expected_tasks.items()
    }
    if any(family not in TASK_FAMILIES for family in planned_tasks.values()):
        raise ValueError("expected task family is invalid")
    planned_manifests: dict[str, Mapping[str, Any]] = {}
    planned_arms: dict[str, str] = {}
    planned_registry_schemas: set[str] = set()
    for arm_id, manifest in expected_manifests.items():
        safe_arm_id = _safe_segment(arm_id, "arm_id")
        if not isinstance(manifest, Mapping):
            raise ValueError(f"expected manifest is not an object: {safe_arm_id}")
        registry_schema = manifest_registry_schema(manifest)
        planned_registry_schemas.add(registry_schema)
        manifest_errors = validate_any_frozen_manifest(manifest)
        if manifest_errors:
            raise ValueError(
                f"expected manifest is invalid: {safe_arm_id}: {manifest_errors}"
            )
        if manifest.get("arm_id") != safe_arm_id:
            raise ValueError(f"expected manifest arm_id mismatch: {safe_arm_id}")
        treatment = manifest.get("treatment")
        allowed_treatments = (
            PROFILE_TREATMENTS
            if registry_schema == PROFILE_REGISTRY_SCHEMA
            else TREATMENTS
        )
        if treatment not in allowed_treatments:
            raise ValueError(f"expected arm treatment is invalid: {safe_arm_id}")
        planned_manifests[safe_arm_id] = manifest
        planned_arms[safe_arm_id] = treatment
    if len(planned_registry_schemas) != 1:
        raise ValueError("one plan may not mix two arm-registry contracts")
    plan_registry_schema = next(iter(planned_registry_schemas))
    plan_components = registry_components(plan_registry_schema)
    if (
        requested_tier == "advisory-paired"
        and plan_registry_schema != PROFILE_REGISTRY_SCHEMA
    ):
        raise ValueError("an advisory-paired request requires the paired-profile registry")
    if (
        requested_tier == "causal"
        and plan_registry_schema != SKILL_CONTENT_REGISTRY_SCHEMA
    ):
        raise ValueError("a causal request requires the skill-content registry")

    off_by_scope: dict[str, list[Mapping[str, Any]]] = defaultdict(list)
    manifest_plan_diff_errors: dict[str, dict[str, list[str]]] = {}
    for manifest in planned_manifests.values():
        if manifest["treatment"] == "off":
            off_by_scope[str(manifest["scope"])].append(manifest)
    for arm_id, manifest in planned_manifests.items():
        scope_off = off_by_scope.get(str(manifest["scope"]), [])
        if len(scope_off) != 1:
            raise ValueError(f"expected exactly one OFF manifest per scope: {arm_id}")
        if manifest["treatment"] == "off":
            continue
        off_components = scope_off[0]["component_hashes"]
        treatment_components = manifest["component_hashes"]
        actual_diff = {
            name
            for name in plan_components
            if off_components[name] != treatment_components[name]
        }
        if actual_diff != set(manifest["allowlisted_diff"]):
            manifest_plan_diff_errors[arm_id] = {
                "actual": sorted(actual_diff),
                "allowlisted": sorted(manifest["allowlisted_diff"]),
            }
    if manifest_plan_diff_errors:
        failures.append("manifest_allowlisted_diff")

    planned_trial_keys: Counter[tuple[str, str, int]] = Counter()
    planned_by_task_arm: Counter[tuple[str, str]] = Counter()
    planned_trial_bindings: dict[tuple[str, str, int], dict[str, Any]] = {}
    planned_run_orders: set[int] = set()
    if not isinstance(expected_trials, Sequence) or isinstance(
        expected_trials, (str, bytes)
    ):
        raise ValueError("expected_trials must be a sequence of objects")
    for row in expected_trials:
        if not isinstance(row, Mapping):
            raise ValueError("expected trial row must be an object")
        expected_trial_fields = {
            "task_id",
            "arm_id",
            "sample_index",
            "run_order",
            *TRIAL_BINDING_FIELDS,
            "task_reference",
            "runtime",
            "fingerprint_input",
        }
        if set(row) != expected_trial_fields:
            raise ValueError("expected trial row field set is invalid")
        task_id = _safe_segment(row.get("task_id"), "task_id")
        arm_id = _safe_segment(row.get("arm_id"), "arm_id")
        sample_index = row.get("sample_index")
        if (
            not isinstance(sample_index, int)
            or isinstance(sample_index, bool)
            or sample_index < 1
        ):
            raise ValueError("expected sample_index must be a positive integer")
        if task_id not in planned_tasks or arm_id not in planned_arms:
            raise ValueError("expected trial row is outside the registered plan")
        task_reference = row.get("task_reference")
        runtime = row.get("runtime")
        fingerprint_input = row.get("fingerprint_input")
        if not isinstance(task_reference, Mapping):
            raise ValueError("expected task reference must be an object")
        if not isinstance(runtime, Mapping):
            raise ValueError("expected runtime must be an object")
        if not isinstance(fingerprint_input, Mapping) or set(fingerprint_input) != {
            "task",
            "manifest_hash",
            "runtime",
            "budget",
            "sample_index",
            "trial_location_hash",
        }:
            raise ValueError("expected fingerprint input is invalid")
        source_task = fingerprint_input.get("task")
        if not isinstance(source_task, Mapping):
            raise ValueError("expected fingerprint task must be an object")
        task_errors = validate_task_record(source_task, committed=False)
        if task_errors:
            raise ValueError(f"expected fingerprint task is invalid: {task_errors}")
        if (
            source_task.get("task_id") != task_id
            or source_task.get("task_family") != planned_tasks[task_id]
        ):
            raise ValueError("expected fingerprint task binding mismatch")
        if task_reference != task_artifact_reference(source_task):
            raise ValueError("expected task reference binding mismatch")
        if row.get("task_hash") != task_reference.get("task_hash"):
            raise ValueError("expected task hash mismatch")
        if runtime != fingerprint_input.get("runtime"):
            raise ValueError("expected runtime binding mismatch")
        for field in (
            "provider",
            "model",
            "session_id",
            "isolation_config_hash",
            "runner_hash",
            "experiment_plan_hash",
        ):
            if not isinstance(runtime.get(field), str) or not runtime[field]:
                raise ValueError(f"expected runtime field missing: {field}")
        for field in (
            "isolation_config_hash",
            "runner_hash",
            "experiment_plan_hash",
        ):
            if not HASH_PATTERN.fullmatch(runtime[field]):
                raise ValueError(f"expected runtime hash field is invalid: {field}")
        if row.get("runtime_hash") != canonical_hash(runtime):
            raise ValueError("expected runtime hash mismatch")
        if row.get("runner_hash") != runtime["runner_hash"]:
            raise ValueError("expected runner hash mismatch")
        if row.get("experiment_plan_hash") != runtime["experiment_plan_hash"]:
            raise ValueError("expected experiment plan hash mismatch")
        if fingerprint_input.get("manifest_hash") != row.get("manifest_hash"):
            raise ValueError("expected fingerprint manifest binding mismatch")
        if fingerprint_input.get("sample_index") != sample_index:
            raise ValueError("expected fingerprint sample binding mismatch")
        _validate_budget(fingerprint_input.get("budget"))
        trial_location_hash = fingerprint_input.get("trial_location_hash")
        if not isinstance(trial_location_hash, str) or not HASH_PATTERN.fullmatch(
            trial_location_hash
        ):
            raise ValueError("expected trial location hash is invalid")
        if row.get("trial_fingerprint") != canonical_hash(fingerprint_input):
            raise ValueError("expected trial fingerprint mismatch")
        run_order = row.get("run_order")
        if (
            not isinstance(run_order, int)
            or isinstance(run_order, bool)
            or run_order < 1
            or run_order in planned_run_orders
        ):
            raise ValueError("expected run_order must be positive and unique")
        binding = {"run_order": run_order}
        for field in TRIAL_BINDING_FIELDS:
            value = row.get(field)
            if not isinstance(value, str) or not HASH_PATTERN.fullmatch(value):
                raise ValueError(f"expected trial binding is invalid: {field}")
            binding[field] = value
        if binding["manifest_hash"] != planned_manifests[arm_id]["manifest_hash"]:
            raise ValueError("expected trial manifest binding mismatch")
        trial_key = (task_id, arm_id, sample_index)
        planned_trial_keys[trial_key] += 1
        planned_trial_bindings[trial_key] = binding
        planned_run_orders.add(run_order)
        planned_by_task_arm[(task_id, arm_id)] += 1
    if not planned_trial_keys or any(
        count != 1 for count in planned_trial_keys.values()
    ):
        raise ValueError("expected trial identities must be non-empty and unique")
    if planned_run_orders != set(range(1, len(planned_trial_keys) + 1)):
        raise ValueError("expected run_order must be contiguous from one")
    if requested_tier == "advisory-paired":
        planned_sessions = [row["runtime"]["session_id"] for row in expected_trials]
        if len(set(planned_sessions)) != len(planned_sessions):
            failures.append("advisory_fresh_session_per_sample")
    if any(
        planned_by_task_arm[(task_id, arm_id)] < thresholds["samples_per_task_arm_min"]
        for task_id in planned_tasks
        for arm_id in planned_arms
    ):
        raise ValueError("expected trial plan is below the samples-per-cell minimum")
    if not records:
        failures.append("no_trial_records")
    completion_rate = _rate(records, "runner_completed")
    if completion_rate < thresholds["runner_completion_rate_min"]:
        failures.append("runner_completion_rate")

    by_arm: dict[str, list[Mapping[str, Any]]] = defaultdict(list)
    by_task_arm: Counter[tuple[str, str]] = Counter()
    observed_trial_keys: Counter[tuple[str, str, int]] = Counter()
    observed_run_orders: list[int] = []
    task_ids = set()
    for index, record in enumerate(records):
        task_id = record.get("task_id")
        arm_id = record.get("arm_id")
        sample_index = record.get("sample_index")
        if (
            not _is_safe_id(task_id)
            or not _is_safe_id(arm_id)
            or not isinstance(sample_index, int)
            or isinstance(sample_index, bool)
            or sample_index < 1
        ):
            failures.append(f"trial_record_identity_invalid:{index}")
            continue
        task_ids.add(task_id)
        by_arm[arm_id].append(record)
        by_task_arm[(task_id, arm_id)] += 1
        trial_key = (task_id, arm_id, sample_index)
        observed_trial_keys[trial_key] += 1
        if record.get("task_family") != planned_tasks.get(task_id):
            failures.append("trial_task_family_mismatch")
        expected_binding = planned_trial_bindings.get(trial_key)
        if expected_binding is None or any(
            record.get(field) != expected_binding[field]
            for field in ("run_order", *TRIAL_BINDING_FIELDS)
        ):
            failures.append("trial_evidence_binding")
        run_order = record.get("run_order")
        if isinstance(run_order, int) and not isinstance(run_order, bool):
            observed_run_orders.append(run_order)
    if any(count != 1 for count in observed_trial_keys.values()):
        failures.append("duplicate_trial_record")
    if observed_trial_keys != planned_trial_keys:
        failures.append("trial_plan_membership_mismatch")
    if observed_run_orders != sorted(planned_run_orders):
        failures.append("trial_execution_order")
    if task_ids != set(planned_tasks) or set(by_arm) != set(planned_arms):
        failures.append("trial_plan_membership_mismatch")
    if any(
        by_task_arm[(task_id, arm_id)] < thresholds["samples_per_task_arm_min"]
        for task_id in planned_tasks
        for arm_id in planned_arms
    ):
        failures.append("insufficient_task_arm_samples")
    if any(
        len({str(row.get("task_id")) for row in rows})
        < thresholds["smoke_tasks_per_arm_min"]
        for rows in by_arm.values()
    ):
        failures.append("insufficient_smoke_tasks_per_arm")
    if any(_rate(rows, "runner_completed") == 0.0 for rows in by_arm.values()):
        failures.append("arm_systemic_runner_failure")
    if any(
        _rate(rows, "runner_completed") < thresholds["runner_completion_rate_min"]
        for rows in by_arm.values()
    ):
        failures.append("arm_runner_completion_rate")
    if any(record.get("manifest_diff_valid") is not True for record in records):
        failures.append("manifest_allowlisted_diff")
    off_arm_ids = {
        arm_id for arm_id, treatment in planned_arms.items() if treatment == "off"
    }
    off_manifest_residual_components = {
        arm_id: off_residual_components(planned_manifests[arm_id])
        for arm_id in sorted(off_arm_ids)
    }
    if any(off_manifest_residual_components.values()):
        failures.append("off_ccl_layer_residual")
    off_residual_values = [
        record.get("off_ccl_residual")
        for record in records
        if record.get("arm_id") in off_arm_ids
    ]
    if not off_residual_values or any(
        not isinstance(value, bool) for value in off_residual_values
    ):
        not_evaluated_checks.append("off_runtime_residual_evidence")
    elif any(value is True for value in off_residual_values):
        failures.append("off_ccl_layer_residual")

    skill_event_values = [record.get("skill_events_verifiable") for record in records]
    if all(isinstance(value, bool) for value in skill_event_values):
        unverifiable = [
            record
            for record in records
            if record.get("skill_events_verifiable") is False
        ]
        telemetry_unverifiable_rate = (
            len(unverifiable) / len(records) if records else 1.0
        )
        arm_unverifiable_rate = {
            arm: sum(row.get("skill_events_verifiable") is False for row in rows)
            / len(rows)
            for arm, rows in by_arm.items()
        }
        if (
            telemetry_unverifiable_rate
            > thresholds["skill_event_unverifiable_rate_max"]
        ):
            failures.append("skill_event_unverifiable_rate")
        if any(
            rate > thresholds["skill_event_unverifiable_rate_max"]
            for rate in arm_unverifiable_rate.values()
        ):
            failures.append("skill_event_unverifiable_rate")
        shapes: dict[str, set[str]] = defaultdict(set)
        for record in unverifiable:
            shapes[str(record.get("skill_event_shape", "missing"))].add(
                str(record.get("task_family", "unknown"))
            )
        if any(
            len(families) >= thresholds["missing_shape_task_family_stop_count"]
            for families in shapes.values()
        ):
            failures.append("skill_event_shape_cross_family")
    else:
        telemetry_unverifiable_rate = None
        arm_unverifiable_rate = {arm: None for arm in by_arm}
        not_evaluated_checks.append("skill_event_verifiability")
    failure_reasons: dict[str, set[str]] = defaultdict(set)
    for record in records:
        reason = record.get("runner_failure_reason")
        if isinstance(reason, str) and reason:
            failure_reasons[reason].add(str(record.get("task_family", "unknown")))
    if any(
        len(families) >= thresholds["missing_shape_task_family_stop_count"]
        for families in failure_reasons.values()
    ):
        failures.append("runner_failure_reason_cross_family")

    matched_arm_ids = {
        arm_id
        for arm_id, treatment in planned_arms.items()
        if treatment in {"active_control", "oracle"}
    }
    matched = [record for record in records if record.get("arm_id") in matched_arm_ids]
    matched_values = [record.get("matched_call_compliant") for record in matched]
    if not matched or any(not isinstance(value, bool) for value in matched_values):
        not_evaluated_checks.append("matched_call_compliance")
    elif (
        matched
        and _rate(matched, "matched_call_compliant")
        < thresholds["matched_call_smoke_rate_min"]
    ):
        failures.append("matched_call_compliance")
    blinding_values = [record.get("blinding_leak") for record in records]
    if any(value is True for value in blinding_values):
        failures.append("blinding_leak")
    if any(not isinstance(value, bool) for value in blinding_values):
        not_evaluated_checks.append("blinding_leak")
    replay_values = [record.get("deterministic_replay_match") for record in records]
    if any(value is False for value in replay_values):
        failures.append("deterministic_grader_replay")
    if any(not isinstance(value, bool) for value in replay_values):
        not_evaluated_checks.append("deterministic_grader_replay")

    calibration_status = calibration.get("status", "evaluated")
    reviewer_statuses: dict[str, str] = {}
    reviewer_families: list[str] = []
    reviewer_metrics: dict[str, dict[str, Any]] = {}
    pairwise_metrics: list[dict[str, Any]] = []
    mutual_calibration_status = "not_applicable_single_reviewer"
    if calibration_status == "not_evaluated_synthetic":
        mutual_calibration_status = "not_evaluated_synthetic"
        warnings.append("reviewer_calibration_not_evaluated_synthetic")
        if not synthetic:
            failures.append("synthetic_calibration_on_non_synthetic_run")
    elif calibration_status != "evaluated":
        failures.append("calibration_status_invalid")
        mutual_calibration_status = "invalid"
    else:
        calibration_result = _evaluate_calibration(
            calibration,
            config["reviewer_calibration_fixture_hash"],
            thresholds,
        )
        reviewer_statuses = calibration_result["reviewer_statuses"]
        reviewer_families = calibration_result["reviewer_families"]
        reviewer_metrics = calibration_result["reviewer_metrics"]
        pairwise_metrics = calibration_result["pairwise_metrics"]
        mutual_calibration_status = calibration_result["mutual_status"]
        if len(reviewer_families) < thresholds["reviewer_family_count_min"]:
            failures.append("reviewer_calibration_family_count")
        if not calibration_result["valid"]:
            failures.append("calibration_evidence_invalid")
        if any(status == "fail" for status in reviewer_statuses.values()):
            failures.append("reviewer_self_calibration")
        if mutual_calibration_status == "invalid":
            failures.append("calibration_evidence_invalid")
        elif mutual_calibration_status == "fail":
            failures.append("reviewer_mutual_calibration")

    contamination_values = [record.get("contaminated") for record in records]
    contamination_evaluated = all(
        isinstance(value, bool) for value in contamination_values
    )
    if contamination_evaluated:
        contaminated = [value for value in contamination_values if value is True]
        contamination_rate = len(contaminated) / len(records) if records else 1.0
        arm_contamination = {
            arm: sum(row.get("contaminated") is True for row in rows) / len(rows)
            for arm, rows in by_arm.items()
        }
        if contamination_rate > thresholds["contamination_rate_max"]:
            failures.append("total_contamination_rate")
        if arm_contamination and (
            max(arm_contamination.values()) - min(arm_contamination.values())
            >= thresholds["arm_contamination_gap_max"]
        ):
            failures.append("arm_contamination_gap")
    else:
        contamination_rate = None
        arm_contamination = {arm: None for arm in by_arm}
        not_evaluated_checks.append("contamination")
    if synthetic:
        not_evaluated_checks.append("contamination")
    budget_values = [record.get("budget_complete") for record in records]
    if any(value is False for value in budget_values):
        failures.append("budget_missing")
    if any(not isinstance(value, bool) for value in budget_values):
        not_evaluated_checks.append("budget_complete")
    access_values = [record.get("access_audit_ok") for record in records]
    if any(value is False for value in access_values):
        failures.append("trial_file_isolation")
    if synthetic or any(not isinstance(value, bool) for value in access_values):
        not_evaluated_checks.append("trial_file_isolation")
    memory_values = [record.get("memory_isolation_ok") for record in records]
    if any(value is False for value in memory_values):
        failures.append("cross_trial_memory_isolation")
    if synthetic or any(not isinstance(value, bool) for value in memory_values):
        not_evaluated_checks.append("cross_trial_memory_isolation")

    not_evaluated_checks = list(dict.fromkeys(not_evaluated_checks))
    # A waived item excuses *missing* evidence only.  Observed breaches were
    # already appended to `failures` above and stay fatal at either tier.
    unwaived_not_evaluated = [
        check for check in not_evaluated_checks if check not in waived_gate_checks
    ]
    coverage_limitations = sorted(
        item
        for item in waived_items
        if ADVISORY_WAIVED_GATE_CHECKS[item] is None
        or ADVISORY_WAIVED_GATE_CHECKS[item] in not_evaluated_checks
    )
    if unwaived_not_evaluated and not synthetic:
        failures.append("required_evidence_not_evaluated")
    if (
        requested_tier == "causal"
        and not synthetic
        and any(
            check in not_evaluated_checks
            for check in ADVISORY_WAIVED_GATE_CHECKS.values()
            if check is not None
        )
    ):
        # `causal_core_unavailable` stays non-passing for every causal request;
        # the advisory tier is the only path that may proceed without it.
        failures.append("causal_core_unavailable")
    failures = list(dict.fromkeys(failures))
    if failures:
        status = "fail"
    elif synthetic:
        status = "not_evaluated_synthetic"
    else:
        status = "pass"
    if synthetic:
        tier_status = "synthetic_not_a_tier"
        verdict_tier = None
    elif status == "pass":
        tier_status = "eligible"
        verdict_tier = requested_tier
    else:
        tier_status = "not_eligible"
        verdict_tier = None
    if status == "pass":
        next_action = "continue_automated_trial"
    elif status == "not_evaluated_synthetic":
        next_action = "collect_live_evidence"
    else:
        next_action = "repair_before_retry"
    return {
        "schema_version": 1,
        "status": status,
        "meaning": "runner_eval_validity_only",
        "failures": failures,
        "warnings": warnings,
        "not_evaluated_checks": not_evaluated_checks,
        "evidence_tier": {
            "schema_version": 1,
            "requested_tier": requested_tier,
            "verdict_tier": verdict_tier,
            "tier_status": tier_status,
            "declared_waivers": list(waived_items),
            "coverage_limitations": coverage_limitations,
            "registry_schema": plan_registry_schema,
            "boundary": (
                "advisory_verdicts_never_aggregate_into_a_causal_claim"
            ),
        },
        "metrics": {
            "trial_count": len(records),
            "runner_completion_rate": completion_rate,
            "skill_event_unverifiable_rate": telemetry_unverifiable_rate,
            "arm_skill_event_unverifiable_rate": arm_unverifiable_rate,
            "contamination_rate": contamination_rate,
            "arm_contamination_rate": arm_contamination,
            "off_manifest_residual_components": off_manifest_residual_components,
            "manifest_plan_diff_errors": manifest_plan_diff_errors,
        },
        "calibration": {
            "input_status": calibration_status,
            "reviewers": reviewer_statuses,
            "reviewer_families": sorted(reviewer_families),
            "reviewer_metrics": reviewer_metrics,
            "pairwise_metrics": pairwise_metrics,
            "mutual": mutual_calibration_status,
            "human_intervention": "optional_not_gate",
        },
        "decision": {
            "mode": "automated",
            "human_required": False,
            "next_action": next_action,
        },
    }


def _pilot_plan_binding_hash(
    config: Mapping[str, Any],
    expected_tasks: Mapping[str, str],
    expected_manifests: Mapping[str, Mapping[str, Any]],
    expected_trials: Sequence[Mapping[str, Any]],
) -> str:
    return canonical_hash(
        {
            "config_hash": canonical_hash(config),
            "expected_tasks": dict(expected_tasks),
            "expected_manifest_hashes": {
                arm_id: expected_manifests[arm_id]["manifest_hash"]
                for arm_id in sorted(expected_manifests)
            },
            "expected_trials": list(expected_trials),
        }
    )


def load_reviewer_calibration_result(
    result_path: Path, config: Mapping[str, Any]
) -> tuple[dict[str, Any], dict[str, Any]]:
    """Load a sealed live calibration result and its bound raw judgments."""

    result_path = _external_private_path(
        result_path, "reviewer calibration result", create_parent=False
    )
    result = load_private_json(result_path)
    expected_fields = {
        "schema_version",
        "artifact_contract",
        "execution_status",
        "calibration_status",
        "provider",
        "provider_cli_version",
        "provider_executable_hash",
        "provider_environment_keys",
        "model",
        "reviewer_family",
        "repeat_count",
        "case_count",
        "known_answer_fixture_hash",
        "case_fixture_hash",
        "pilot_gates_hash",
        "runner_contract",
        "runner_hash",
        "requested_session_mode",
        "tool_access",
        "calibration_evidence",
        "calibration_evidence_hash",
        "calibration_evaluation",
        "calibration_evaluation_hash",
        "conclusion_boundary",
        "enforcement",
    }
    provider_name = result.get("provider") if isinstance(result, Mapping) else None
    if provider_name == "kimi":
        expected_fields.update({"provider_binding", "provider_binding_hash"})
    if not isinstance(result, Mapping) or set(result) != expected_fields:
        raise ValueError("reviewer calibration result field set is invalid")
    hash_fields = {
        "provider_executable_hash",
        "known_answer_fixture_hash",
        "case_fixture_hash",
        "pilot_gates_hash",
        "runner_hash",
        "calibration_evidence_hash",
        "calibration_evaluation_hash",
    }
    if provider_name == "kimi":
        hash_fields.add("provider_binding_hash")
    if any(
        not isinstance(result.get(field), str)
        or HASH_PATTERN.fullmatch(result[field]) is None
        for field in hash_fields
    ):
        raise ValueError("reviewer calibration result hash field is invalid")
    evidence_name = result.get("calibration_evidence")
    if (
        not isinstance(evidence_name, str)
        or Path(evidence_name).name != evidence_name
        or evidence_name != "reviewer-calibration.json"
    ):
        raise ValueError("reviewer calibration evidence path is invalid")
    calibration = load_private_json(result_path.parent / evidence_name)
    evaluation = evaluate_reviewer_calibration(calibration, config)
    reviewer_rows = (
        calibration.get("reviewers") if isinstance(calibration, Mapping) else None
    )
    if (
        not isinstance(reviewer_rows, Sequence)
        or isinstance(reviewer_rows, (str, bytes))
        or len(reviewer_rows) != 1
        or not isinstance(reviewer_rows[0], Mapping)
    ):
        raise ValueError("reviewer calibration result must bind one reviewer family")
    runs = reviewer_rows[0].get("runs")
    known_answers = calibration.get("known_answers")
    provider_contracts = {
        "codex": {
            "runner_contract": "codex-cli-reviewer-calibration-v1",
            "requested_session_mode": "ephemeral",
            "tool_access": "rejected",
            "reviewer_family": None,
        },
        "claude": {
            "runner_contract": "claude-cli-reviewer-calibration-v1",
            "requested_session_mode": "no-session-persistence",
            "tool_access": "verified-none",
            "reviewer_family": "claude",
        },
        "opencode": {
            "runner_contract": "opencode-cli-reviewer-calibration-v1",
            "requested_session_mode": "private-xdg-explicit-model-export",
            "tool_access": "agent-disabled-observed-none",
            "reviewer_family": None,
        },
        "kimi": {
            "runner_contract": "kimi-cli-reviewer-calibration-v1",
            "requested_session_mode": "private-kimi-home-explicit-model-stream",
            "tool_access": "config-denied-stream-audited-detection-only",
            "reviewer_family": "moonshot",
        },
    }
    provider_contract = (
        provider_contracts.get(provider_name)
        if isinstance(provider_name, str)
        else None
    )
    provider_binding = result.get("provider_binding")
    provider_binding_valid = provider_name != "kimi"
    if provider_name == "kimi" and isinstance(provider_binding, Mapping):
        provider_binding_valid = (
            set(provider_binding)
            == {
                "binding_type",
                "model_alias",
                "provider_id",
                "underlying_model",
                "selected_config_hash",
            }
            and provider_binding.get("binding_type") == "configured-alias"
            and provider_binding.get("model_alias") == result.get("model")
            and isinstance(provider_binding.get("provider_id"), str)
            and bool(provider_binding["provider_id"])
            and isinstance(provider_binding.get("underlying_model"), str)
            and bool(provider_binding["underlying_model"])
            and isinstance(provider_binding.get("selected_config_hash"), str)
            and HASH_PATTERN.fullmatch(provider_binding["selected_config_hash"])
            is not None
        )
    if (
        result.get("schema_version") != 1
        or result.get("artifact_contract") != REVIEWER_CALIBRATION_RESULT_CONTRACT
        or result.get("execution_status") != "completed"
        or provider_contract is None
        or not provider_binding_valid
        or (
            provider_name == "kimi"
            and result.get("provider_binding_hash")
            != canonical_hash(provider_binding)
        )
        or not isinstance(result.get("provider_cli_version"), str)
        or not result["provider_cli_version"]
        or not isinstance(result.get("provider_environment_keys"), list)
        or any(not isinstance(key, str) for key in result["provider_environment_keys"])
        or not isinstance(result.get("model"), str)
        or not result["model"]
        or result.get("reviewer_family") != reviewer_rows[0].get("family")
        or (
            provider_contract["reviewer_family"] is not None
            and result.get("reviewer_family") != provider_contract["reviewer_family"]
        )
        or (
            provider_name == "opencode"
            and (
                result["model"].partition("/")[1] != "/"
                or not result["model"].partition("/")[2]
                or not result["model"].partition("/")[0]
                or (
                    provider_name == "opencode"
                    and result["model"].partition("/")[0]
                    != result.get("reviewer_family")
                )
            )
        )
        or result.get("repeat_count") != len(runs or [])
        or result.get("case_count") != len(known_answers or [])
        or result.get("known_answer_fixture_hash")
        != calibration.get("known_answer_fixture_hash")
        or result.get("known_answer_fixture_hash")
        != config.get("reviewer_calibration_fixture_hash")
        or result.get("case_fixture_hash")
        != config.get("reviewer_calibration_case_fixture_hash")
        or result.get("pilot_gates_hash") != canonical_hash(config)
        or result.get("runner_contract") != provider_contract["runner_contract"]
        or result.get("requested_session_mode")
        != provider_contract["requested_session_mode"]
        or result.get("tool_access") != provider_contract["tool_access"]
        or result.get("calibration_evidence_hash") != canonical_hash(calibration)
        or result.get("calibration_evaluation") != evaluation
        or result.get("calibration_evaluation_hash") != canonical_hash(evaluation)
        or result.get("calibration_status") != evaluation["status"]
        or result.get("conclusion_boundary")
        != "reviewer_calibration_only_not_skill_effectiveness"
        or result.get("enforcement") != "advisory"
    ):
        raise ValueError("reviewer calibration result binding is invalid")
    return dict(calibration), dict(result)


def write_pilot_evidence_bundle(
    evidence_root: Path,
    records: Sequence[Mapping[str, Any]],
    calibration_result_path: Path,
    config: Mapping[str, Any],
    expected_tasks: Mapping[str, str],
    expected_manifests: Mapping[str, Mapping[str, Any]],
    expected_trials: Sequence[Mapping[str, Any]],
) -> dict[str, Any]:
    """Persist local E10 inputs so evaluation must read back durable evidence."""

    root = _external_private_path(
        Path(evidence_root) / "bundle.json", "pilot evidence bundle"
    ).parent
    record_rows = [dict(record) for record in records]
    records_path = root / "trial-records.jsonl"
    if _path_exists(records_path):
        if load_private_jsonl(records_path) != record_rows:
            raise ValueError("existing pilot records differ from requested content")
    else:
        write_jsonl_atomic(records_path, record_rows)
    calibration_payload, calibration_result = load_reviewer_calibration_result(
        calibration_result_path, config
    )
    _write_private_json_once(
        root / "reviewer-calibration.json",
        calibration_payload,
        "pilot calibration artifact",
    )
    _write_private_json_once(
        root / "reviewer-calibration-result.json",
        calibration_result,
        "pilot calibration result",
    )
    core = {
        "schema_version": 1,
        "artifact_contract": PILOT_EVIDENCE_CONTRACT,
        "records_hash": canonical_hash(record_rows),
        "record_count": len(record_rows),
        "calibration_hash": canonical_hash(calibration_payload),
        "calibration_result_hash": canonical_hash(calibration_result),
        "config_hash": canonical_hash(config),
        "plan_binding_hash": _pilot_plan_binding_hash(
            config, expected_tasks, expected_manifests, expected_trials
        ),
    }
    payload = {**core, "bundle_hash": canonical_hash(core)}
    _write_private_json_once(root / "bundle.json", payload, "pilot evidence bundle")
    return payload


def evaluate_pilot_gate_from_artifacts(
    evidence_root: Path,
    config: Mapping[str, Any],
    expected_tasks: Mapping[str, str],
    expected_manifests: Mapping[str, Mapping[str, Any]],
    expected_trials: Sequence[Mapping[str, Any]],
) -> dict[str, Any]:
    """Evaluate a non-synthetic pilot from an owner-private local bundle."""

    root = _external_private_path(
        Path(evidence_root) / "bundle.json",
        "pilot evidence bundle",
        create_parent=False,
    ).parent
    bundle = load_private_json(root / "bundle.json")
    expected_fields = {
        "schema_version",
        "artifact_contract",
        "records_hash",
        "record_count",
        "calibration_hash",
        "calibration_result_hash",
        "config_hash",
        "plan_binding_hash",
        "bundle_hash",
    }
    if not isinstance(bundle, Mapping) or set(bundle) != expected_fields:
        raise ValueError("pilot evidence bundle field set is invalid")
    core = {field: bundle[field] for field in expected_fields - {"bundle_hash"}}
    if (
        bundle.get("schema_version") != 1
        or bundle.get("artifact_contract") != PILOT_EVIDENCE_CONTRACT
        or bundle.get("bundle_hash") != canonical_hash(core)
    ):
        raise ValueError("pilot evidence bundle hash is invalid")
    records = load_private_jsonl(root / "trial-records.jsonl")
    calibration, calibration_result = load_reviewer_calibration_result(
        root / "reviewer-calibration-result.json", config
    )
    if bundle.get("records_hash") != canonical_hash(records):
        raise ValueError("pilot evidence records hash mismatch")
    if bundle.get("record_count") != len(records):
        raise ValueError("pilot evidence record count mismatch")
    if bundle.get("calibration_hash") != canonical_hash(calibration):
        raise ValueError("pilot evidence calibration hash mismatch")
    if bundle.get("calibration_result_hash") != canonical_hash(calibration_result):
        raise ValueError("pilot evidence calibration result hash mismatch")
    if bundle.get("config_hash") != canonical_hash(config):
        raise ValueError("pilot evidence config hash mismatch")
    if bundle.get("plan_binding_hash") != _pilot_plan_binding_hash(
        config, expected_tasks, expected_manifests, expected_trials
    ):
        raise ValueError("pilot evidence plan binding mismatch")
    result = _evaluate_pilot_gate_records(
        records,
        calibration,
        config,
        expected_tasks,
        expected_manifests,
        expected_trials,
        synthetic=False,
    )
    result["evidence_source"] = "local_artifact_bundle"
    return result


def evaluate_pilot_gate(
    records: Sequence[Mapping[str, Any]],
    calibration: Mapping[str, Any],
    config: Mapping[str, Any],
    expected_tasks: Mapping[str, str],
    expected_manifests: Mapping[str, Mapping[str, Any]],
    expected_trials: Sequence[Mapping[str, Any]],
    *,
    synthetic: bool = False,
) -> dict[str, Any]:
    """Evaluate synthetic inputs; live inputs must use the artifact entrypoint."""

    result = _evaluate_pilot_gate_records(
        records,
        calibration,
        config,
        expected_tasks,
        expected_manifests,
        expected_trials,
        synthetic=synthetic,
    )
    if synthetic:
        result["evidence_source"] = "synthetic_in_memory"
        return result
    if "local_evidence_bundle_required" not in result["failures"]:
        result["failures"].append("local_evidence_bundle_required")
    result["status"] = "fail"
    result["decision"]["next_action"] = "persist_local_evidence_before_retry"
    result["evidence_source"] = "untrusted_in_memory"
    return result
