#!/usr/bin/env python3
"""Fail-closed preparation artifacts for the Sg/Mg active controls.

This module validates and blinds two human-authored generic-guidance packages.
It does not generate candidates, decide that authors are independent, run an
effectiveness trial, or prove that selection happened before every possible
external outcome.  Hashes and one-shot private artifacts enforce only the
controller-visible byte and ordering contract.
"""

from __future__ import annotations

import json
import os
import re
import sys
import tempfile
from pathlib import Path
from typing import Any, Mapping, Sequence


HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))

import trial  # noqa: E402


CANDIDATE_CONTRACT = "skill-effectiveness-active-control-candidate-v1"
SELECTOR_INPUT_CONTRACT = "skill-effectiveness-active-control-selector-input-v1"
DECISION_CONTRACT = "skill-effectiveness-active-control-decision-v1"
CLAIM_CONTRACT = "skill-effectiveness-active-control-claim-v1"
CONTROLLER_STATE_CONTRACT = "skill-effectiveness-active-control-state-v1"
SELECTION_CONTRACT = "skill-effectiveness-active-control-selection-v1"
OWNER_REFERENCE_CONTRACT = (
    "skill-effectiveness-active-control-owner-reference-v1"
)
OWNER_RELATIVE_MEASUREMENT_CONTRACT = (
    "skill-effectiveness-active-control-owner-relative-measurement-v1"
)
MATCHED_CALL_EVIDENCE_CONTRACT = trial.MATCHED_CALL_EVIDENCE_CONTRACT
MATCHED_CALL_EVENT_CONTRACT = "skill-events-v2"
SCOPES = ("subagent", "main")
MATCHED_CALL_EVIDENCE_FILENAMES = {
    scope: f"matched-call-evidence-{scope}.json" for scope in SCOPES
}
OPAQUE_ID = re.compile(r"^slot-[0-9a-f]{16}$")
BUNDLE_ID = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._:-]{0,127}$")
MATCHED_CALL_DECLARATION_STATUS = trial.MATCHED_CALL_DECLARATION_STATUS
MATCHED_CALL_BOUNDARY = (
    "deterministic-fixtures-no-observed-call-history-or-live-host-enforcement"
)
BRIEF_FIELDS = {"schema_version", "task_families", "instruction"}
RUBRIC_FIELDS = {"schema_version", "criteria"}
RUBRIC_CRITERIA = ("readability", "actionability", "information_density")
RESERVED_CONTENT = (
    "ccl-skills:",
    "agents.md",
    "session-start.md",
    "held-out",
    "held_out",
    "grader_truth",
    "expected_output",
    "ccl_layer",
    "controller_state",
    "generation_evidence",
    "provenance",
    "provider",
    "model",
    "author",
    "commitment",
    "attestation",
)
CANDIDATE_FIELDS = {
    "schema_version",
    "artifact_contract",
    "brief_hash",
    "scope_contents",
    "scope_hashes",
    "generation_evidence",
    "package_hash",
}
GENERATION_EVIDENCE_FIELDS = {
    "source_kind",
    "author_commitment_hash",
    "independence_attestation_hash",
    "input_hash",
    "output_hash",
}
CONSTRAINT_FIELDS = {
    "schema_version",
    "scopes",
    "minimum_characters_per_scope",
    "maximum_characters_per_scope",
}
SELECTOR_INPUT_FIELDS = {
    "schema_version",
    "artifact_contract",
    "brief",
    "brief_hash",
    "rubric",
    "rubric_hash",
    "constraint_spec",
    "constraint_spec_hash",
    "opaque_order",
    "candidates",
    "selector_input_hash",
}
DECISION_FIELDS = {
    "schema_version",
    "artifact_contract",
    "selector_input_hash",
    "rubric_hash",
    "selected_opaque_id",
}
CONTROLLER_STATE_FIELDS = {
    "schema_version",
    "artifact_contract",
    "selector_input_hash",
    "candidate_packages",
    "opaque_mapping",
    "owner_reference_hash",
    "request_hash",
    "controller_state_hash",
}
SELECTION_FIELDS = {
    "schema_version",
    "artifact_contract",
    "brief_hash",
    "rubric",
    "rubric_hash",
    "constraint_spec",
    "constraint_spec_hash",
    "candidate_packages",
    "candidate_package_hashes",
    "opaque_order",
    "opaque_mapping",
    "selector_input",
    "selector_input_hash",
    "owner_reference_hash",
    "request_hash",
    "decision",
    "selected_package_hash",
    "selected_scope_hashes",
    "selected_scope_contents",
    "independence_status",
    "independence_boundary",
    "temporal_boundary",
    "artifact_hash",
}
OWNER_REFERENCE_FIELDS = {
    "schema_version",
    "artifact_contract",
    "scope_contents",
    "scope_hashes",
    "reference_hash",
}
OWNER_RELATIVE_MEASUREMENT_FIELDS = {
    "schema_version",
    "artifact_contract",
    "selection_artifact_hash",
    "selected_package_hash",
    "owner_reference_hash",
    "request_hash",
    "measurement_contracts",
    "scopes",
    "status",
    "boundary",
    "measurement_hash",
}
MEASUREMENT_CONTRACTS = {
    "paragraph_count": "normalized-newline-ascii-blank-line-v1",
    "instruction_count": "markdown-list-item-line-v1",
    "token_count": (
        "ascii-word-run-or-single-unicode-nonwhitespace-codepoint-v1"
    ),
    "tolerance": "inclusive-integer-cross-multiplication-9-to-11-over-10-v1",
}
METRIC_FIELDS = {"paragraph_count", "instruction_count", "token_count"}
MAX_MATCHED_CALL_INVOCATIONS = 1024
MAX_MATCHED_CALL_TOOL_USE_ID_CHARACTERS = 256
MAX_MATCHED_CALL_EVENT_INDEX = 1_000_000_000
MATCHED_CALL_FIXTURE_EXPECTED_OUTCOMES = {
    "missing": ["deny", "matched_call_required"],
    "wrong_target": ["deny", "matched_call_required"],
    "incomplete": ["deny", "matched_call_required"],
    "degraded": ["deny", "event_contract_unverifiable"],
    "missing_task_tool_index": ["deny", "event_contract_unverifiable"],
    "completed": ["fixture-pass", "fixture_matched_call_satisfied"],
    "late_after_task_tool": ["deny", "matched_call_late"],
}
MATCHED_CALL_DENY_TEMPLATE = (
    "complete-required-bundle-before-trial-unlock:{target_bundle_id}"
)
MATCHED_CALL_FIXTURE_RESULT_CONTRACT = {
    "observation_status": "none-fixtures-only",
    "live_gate_eligible": False,
    "deny_message_semantics": "frozen-deny-template-for-deny-else-null",
}
MATCHED_CALL_GATE_SPEC = {
    "schema_version": 1,
    "event_contract_version": MATCHED_CALL_EVENT_CONTRACT,
    "deny_template": MATCHED_CALL_DENY_TEMPLATE,
    "gate_phase": "before-first-task-tool",
    "fixture_pass_semantics": (
        "completed-exact-target-call-before-task-tool-passes-fixture"
    ),
    "unknown_event_semantics": "deny-as-event-contract-unverifiable",
    "matching_semantics": "exact-bundle-id-and-successful-matching-tool-result",
    "ordering_semantics": (
        "matching-call-index-strictly-before-first-task-tool-index"
    ),
    "event_index_uniqueness_semantics": (
        "skill-and-first-task-tool-indexes-globally-unique"
    ),
    "tool_use_id_uniqueness_semantics": (
        "globally-unique-across-skill-invocations"
    ),
    "ordering_window_semantics": (
        "first-task-index-at-most-max-invocation-index-plus-one"
    ),
    "event_index_trust_boundary": "fixture-asserted-not-live-host-attested",
    "live_gate_eligibility": (
        "ineligible-requires-authenticated-single-monotonic-host-stream"
    ),
    "live_gate_migration": "new-versioned-live-contract-and-artifact-required",
    "fixture_expected_outcomes": MATCHED_CALL_FIXTURE_EXPECTED_OUTCOMES,
    "fixture_result_contract": MATCHED_CALL_FIXTURE_RESULT_CONTRACT,
    "matched_call_gate_satisfied": False,
    "max_skill_invocations": MAX_MATCHED_CALL_INVOCATIONS,
    "max_tool_use_id_characters": MAX_MATCHED_CALL_TOOL_USE_ID_CHARACTERS,
    "max_event_index": MAX_MATCHED_CALL_EVENT_INDEX,
}
MATCHED_CALL_GATE_CONTRACT_HASH = trial.canonical_hash(MATCHED_CALL_GATE_SPEC)
MATCHED_CALL_EVIDENCE_FIELDS = {
    "schema_version",
    "artifact_contract",
    "selection_artifact_hash",
    "owner_relative_measurement_hash",
    "owner_reference_hash",
    "scope",
    "gate_contract",
    "gate_contract_hash",
    "allowed_target_differences",
    "targets",
    "fixture_results",
    "observation_status",
    "matched_call_gate_satisfied",
    "status",
    "boundary",
    "artifact_hash",
}


def _require_object(value: Any, label: str) -> Mapping[str, Any]:
    if not isinstance(value, Mapping):
        raise ValueError(f"{label} must be an object")
    return value


def _require_exact_fields(
    value: Mapping[str, Any], expected: set[str], label: str
) -> None:
    if set(value) != expected:
        raise ValueError(f"{label} field set is invalid")


def _require_hash(value: Any, label: str) -> str:
    if not isinstance(value, str) or not trial.HASH_PATTERN.fullmatch(value):
        raise ValueError(f"{label} must be a sha256 hash")
    return value


def _hash_body(value: Mapping[str, Any], hash_field: str) -> str:
    return trial.canonical_hash(
        {key: child for key, child in value.items() if key != hash_field}
    )


def _reject_selector_metadata(value: Any, label: str) -> None:
    if isinstance(value, Mapping):
        for key, child in value.items():
            if not isinstance(key, str):
                raise ValueError(f"{label} keys must be strings")
            lowered_key = key.casefold()
            if any(token in lowered_key for token in RESERVED_CONTENT):
                raise ValueError(f"{label} contains reserved metadata")
            _reject_selector_metadata(child, label)
        return
    if isinstance(value, list):
        for child in value:
            _reject_selector_metadata(child, label)
        return
    if isinstance(value, str):
        lowered = value.casefold()
        if any(token in lowered for token in RESERVED_CONTENT):
            raise ValueError(f"{label} contains reserved metadata")


def _validate_brief(value: Any) -> dict[str, Any]:
    brief = _require_object(value, "selector brief")
    _require_exact_fields(brief, BRIEF_FIELDS, "selector brief")
    if brief.get("schema_version") != 1:
        raise ValueError("selector brief schema version is invalid")
    task_families = brief.get("task_families")
    if not isinstance(task_families, list) or not task_families:
        raise ValueError("selector brief task families are invalid")
    if any(
        not isinstance(family, str) or family not in trial.TASK_FAMILIES
        for family in task_families
    ):
        raise ValueError("selector brief task families are invalid")
    if task_families != sorted(task_families) or len(set(task_families)) != len(
        task_families
    ):
        raise ValueError("selector brief task families are invalid")
    instruction = brief.get("instruction")
    if not isinstance(instruction, str) or not instruction.strip():
        raise ValueError("selector brief instruction is invalid")
    _reject_selector_metadata(brief, "selector brief")
    return json.loads(trial.canonical_json(brief))


def _validate_rubric(value: Any) -> dict[str, Any]:
    rubric = _require_object(value, "selector rubric")
    _require_exact_fields(rubric, RUBRIC_FIELDS, "selector rubric")
    if rubric.get("schema_version") != 1 or rubric.get("criteria") != list(
        RUBRIC_CRITERIA
    ):
        raise ValueError("selector rubric contract is invalid")
    _reject_selector_metadata(rubric, "selector rubric")
    return json.loads(trial.canonical_json(rubric))


def _validate_scope_contents(value: Any) -> dict[str, str]:
    contents = _require_object(value, "candidate scope_contents")
    if set(contents) != set(SCOPES):
        raise ValueError("candidate scope set is invalid")
    normalized: dict[str, str] = {}
    for scope in SCOPES:
        content = contents.get(scope)
        if not isinstance(content, str) or not content.strip():
            raise ValueError(f"candidate scope content is invalid: {scope}")
        lowered = content.casefold()
        if any(token in lowered for token in RESERVED_CONTENT):
            raise ValueError(f"candidate scope content contains reserved surface: {scope}")
        normalized[scope] = content
    return normalized


def _validate_generation_evidence(
    value: Any, *, brief_hash: str, scope_contents: Mapping[str, str]
) -> dict[str, Any]:
    evidence = _require_object(value, "generation_evidence")
    _require_exact_fields(
        evidence, GENERATION_EVIDENCE_FIELDS, "generation_evidence"
    )
    if evidence.get("source_kind") != "human-author":
        raise ValueError("active-control candidates require human authors")
    for field in (
        "author_commitment_hash",
        "independence_attestation_hash",
        "input_hash",
        "output_hash",
    ):
        _require_hash(evidence.get(field), f"generation_evidence.{field}")
    if evidence["input_hash"] != brief_hash:
        raise ValueError("candidate input hash does not match brief")
    if evidence["output_hash"] != trial.canonical_hash(dict(scope_contents)):
        raise ValueError("candidate output hash does not match scope contents")
    return dict(evidence)


def freeze_active_control_candidate(
    *,
    brief: Mapping[str, Any],
    scope_contents: Mapping[str, str],
    generation_evidence: Mapping[str, Any],
) -> dict[str, Any]:
    """Freeze one human-authored two-scope candidate package."""

    brief = _validate_brief(brief)
    contents = _validate_scope_contents(scope_contents)
    brief_hash = trial.canonical_hash(dict(brief))
    evidence = _validate_generation_evidence(
        generation_evidence,
        brief_hash=brief_hash,
        scope_contents=contents,
    )
    body = {
        "schema_version": 1,
        "artifact_contract": CANDIDATE_CONTRACT,
        "brief_hash": brief_hash,
        "scope_contents": contents,
        "scope_hashes": {
            scope: trial.canonical_hash(contents[scope]) for scope in SCOPES
        },
        "generation_evidence": evidence,
    }
    return {**body, "package_hash": trial.canonical_hash(body)}


def _validate_candidate_package(
    value: Any, *, expected_brief_hash: str | None = None
) -> dict[str, Any]:
    package = _require_object(value, "candidate package")
    _require_exact_fields(package, CANDIDATE_FIELDS, "candidate package")
    if (
        package.get("schema_version") != 1
        or package.get("artifact_contract") != CANDIDATE_CONTRACT
    ):
        raise ValueError("candidate package contract is invalid")
    brief_hash = _require_hash(package.get("brief_hash"), "candidate brief_hash")
    if expected_brief_hash is not None and brief_hash != expected_brief_hash:
        raise ValueError("candidate package brief hash mismatch")
    contents = _validate_scope_contents(package.get("scope_contents"))
    scope_hashes = _require_object(package.get("scope_hashes"), "scope_hashes")
    if set(scope_hashes) != set(SCOPES):
        raise ValueError("candidate scope hash set is invalid")
    expected_scope_hashes = {
        scope: trial.canonical_hash(contents[scope]) for scope in SCOPES
    }
    if dict(scope_hashes) != expected_scope_hashes:
        raise ValueError("candidate scope hash mismatch")
    _validate_generation_evidence(
        package.get("generation_evidence"),
        brief_hash=brief_hash,
        scope_contents=contents,
    )
    package_hash = _require_hash(package.get("package_hash"), "candidate package_hash")
    if package_hash != _hash_body(package, "package_hash"):
        raise ValueError("candidate package hash mismatch")
    return json.loads(trial.canonical_json(package))


def _validate_constraint_spec(value: Any) -> dict[str, Any]:
    spec = _require_object(value, "constraint_spec")
    _require_exact_fields(spec, CONSTRAINT_FIELDS, "constraint_spec")
    if spec.get("schema_version") != 1 or spec.get("scopes") != list(SCOPES):
        raise ValueError("constraint_spec scope contract is invalid")
    minimum = spec.get("minimum_characters_per_scope")
    maximum = spec.get("maximum_characters_per_scope")
    if (
        not isinstance(minimum, int)
        or isinstance(minimum, bool)
        or not isinstance(maximum, int)
        or isinstance(maximum, bool)
        or minimum <= 0
        or maximum < minimum
    ):
        raise ValueError("constraint_spec character bounds are invalid")
    return dict(spec)


def _validate_candidate_pair(
    candidates: Sequence[Mapping[str, Any]],
    *,
    brief_hash: str,
    constraints: Mapping[str, Any],
) -> list[dict[str, Any]]:
    if not isinstance(candidates, Sequence) or isinstance(candidates, (str, bytes)):
        raise ValueError("candidate packages must be a sequence")
    if len(candidates) != 2:
        raise ValueError("exactly two candidate packages are required")
    validated = [
        _validate_candidate_package(candidate, expected_brief_hash=brief_hash)
        for candidate in candidates
    ]
    minimum = constraints["minimum_characters_per_scope"]
    maximum = constraints["maximum_characters_per_scope"]
    for scope in SCOPES:
        scope_values = [candidate["scope_contents"][scope] for candidate in validated]
        if scope_values[0] == scope_values[1]:
            raise ValueError(f"candidate scope content must differ: {scope}")
        for content in scope_values:
            if not minimum <= len(content) <= maximum:
                raise ValueError(f"candidate scope content length is invalid: {scope}")
    commitments = [
        candidate["generation_evidence"]["author_commitment_hash"]
        for candidate in validated
    ]
    attestations = [
        candidate["generation_evidence"]["independence_attestation_hash"]
        for candidate in validated
    ]
    if len(set(commitments)) != 2 or len(set(attestations)) != 2:
        raise ValueError("candidate authorship commitments must be distinct")
    if (
        validated[0]["generation_evidence"]["input_hash"]
        != validated[1]["generation_evidence"]["input_hash"]
    ):
        raise ValueError("candidate input hashes must match")
    return validated


def _validate_opaque_order(value: Any) -> list[str]:
    if (
        not isinstance(value, list)
        or len(value) != 2
        or len(set(value)) != 2
        or any(not isinstance(slot, str) or not OPAQUE_ID.fullmatch(slot) for slot in value)
    ):
        raise ValueError("opaque_order must contain two distinct opaque ids")
    return list(value)


def _selection_root(output_root: Path) -> Path:
    root = Path(output_root).expanduser()
    if root.is_symlink():
        raise ValueError("active-control output root must not be a symlink")
    resolved = root.resolve(strict=False)
    if resolved in {Path("/").resolve(), Path.home().resolve()}:
        raise ValueError("active-control output root is too broad")
    trial._external_private_path(
        resolved / "active-control-claim.json", "active-control claim"
    )
    if resolved.is_symlink() or resolved.resolve(strict=True) != resolved:
        raise ValueError("active-control output root changed after validation")
    return resolved


def _write_json_exclusive(path: Path, value: Mapping[str, Any], label: str) -> None:
    payload = trial.canonical_json(value) + b"\n"
    descriptor, temp_name = tempfile.mkstemp(
        prefix=f".{path.name}.", dir=path.parent
    )
    temp_path = Path(temp_name)
    try:
        os.fchmod(descriptor, 0o600)
        with os.fdopen(descriptor, "wb") as stream:
            descriptor = -1
            stream.write(payload)
            stream.flush()
            os.fsync(stream.fileno())
        try:
            os.link(temp_path, path)
        except FileExistsError as exc:
            raise ValueError(f"{label} already exists") from exc
    finally:
        if descriptor >= 0:
            os.close(descriptor)
        temp_path.unlink(missing_ok=True)


def _validate_selector_input(value: Any) -> dict[str, Any]:
    selector_input = _require_object(value, "selector input")
    _require_exact_fields(selector_input, SELECTOR_INPUT_FIELDS, "selector input")
    if (
        selector_input.get("schema_version") != 1
        or selector_input.get("artifact_contract") != SELECTOR_INPUT_CONTRACT
    ):
        raise ValueError("selector input contract is invalid")
    brief = _validate_brief(selector_input.get("brief"))
    rubric = _validate_rubric(selector_input.get("rubric"))
    constraints = _validate_constraint_spec(selector_input.get("constraint_spec"))
    if selector_input.get("brief_hash") != trial.canonical_hash(dict(brief)):
        raise ValueError("selector input brief hash mismatch")
    if selector_input.get("rubric_hash") != trial.canonical_hash(dict(rubric)):
        raise ValueError("selector input rubric hash mismatch")
    if selector_input.get("constraint_spec_hash") != trial.canonical_hash(constraints):
        raise ValueError("selector input constraint hash mismatch")
    opaque_order = _validate_opaque_order(selector_input.get("opaque_order"))
    candidates = selector_input.get("candidates")
    if not isinstance(candidates, list) or len(candidates) != 2:
        raise ValueError("selector input needs two candidates")
    expected_candidate_fields = {"opaque_id", "scope_contents", "scope_hashes"}
    seen: list[str] = []
    for candidate in candidates:
        candidate = _require_object(candidate, "selector candidate")
        _require_exact_fields(candidate, expected_candidate_fields, "selector candidate")
        opaque_id = candidate.get("opaque_id")
        if not isinstance(opaque_id, str) or not OPAQUE_ID.fullmatch(opaque_id):
            raise ValueError("selector candidate opaque id is invalid")
        seen.append(opaque_id)
        contents = _validate_scope_contents(candidate.get("scope_contents"))
        expected_hashes = {
            scope: trial.canonical_hash(contents[scope]) for scope in SCOPES
        }
        if candidate.get("scope_hashes") != expected_hashes:
            raise ValueError("selector candidate scope hash mismatch")
    if seen != opaque_order:
        raise ValueError("selector candidate order mismatch")
    selector_hash = _require_hash(
        selector_input.get("selector_input_hash"), "selector_input_hash"
    )
    if selector_hash != _hash_body(selector_input, "selector_input_hash"):
        raise ValueError("selector input hash mismatch")
    return json.loads(trial.canonical_json(selector_input))


def prepare_active_control(
    *,
    output_root: Path,
    brief: Mapping[str, Any],
    rubric: Mapping[str, Any],
    constraint_spec: Mapping[str, Any],
    owner_reference: Mapping[str, Any],
    candidate_packages: Sequence[Mapping[str, Any]],
    opaque_order: list[str],
) -> dict[str, Any]:
    """Create one blinded selector packet and controller-only mapping."""

    brief = _validate_brief(brief)
    rubric = _validate_rubric(rubric)
    constraints = _validate_constraint_spec(constraint_spec)
    owner = _validate_owner_reference(owner_reference)
    brief_hash = trial.canonical_hash(dict(brief))
    candidates = _validate_candidate_pair(
        candidate_packages,
        brief_hash=brief_hash,
        constraints=constraints,
    )
    opaque_order = _validate_opaque_order(opaque_order)
    selector_core = {
        "schema_version": 1,
        "artifact_contract": SELECTOR_INPUT_CONTRACT,
        "brief": dict(brief),
        "brief_hash": brief_hash,
        "rubric": dict(rubric),
        "rubric_hash": trial.canonical_hash(dict(rubric)),
        "constraint_spec": constraints,
        "constraint_spec_hash": trial.canonical_hash(constraints),
        "opaque_order": opaque_order,
        "candidates": [
            {
                "opaque_id": opaque_order[index],
                "scope_contents": candidates[index]["scope_contents"],
                "scope_hashes": candidates[index]["scope_hashes"],
            }
            for index in range(2)
        ],
    }
    selector_input = {
        **selector_core,
        "selector_input_hash": trial.canonical_hash(selector_core),
    }
    _validate_selector_input(selector_input)
    opaque_mapping = {
        opaque_order[index]: candidates[index]["package_hash"] for index in range(2)
    }
    request = {
        "selector_input_hash": selector_input["selector_input_hash"],
        "candidate_package_hashes": [
            candidate["package_hash"] for candidate in candidates
        ],
        "opaque_mapping": opaque_mapping,
        "owner_reference_hash": owner["reference_hash"],
    }
    request_hash = trial.canonical_hash(request)
    claim = {
        "schema_version": 1,
        "artifact_contract": CLAIM_CONTRACT,
        "owner_reference_hash": owner["reference_hash"],
        "request_hash": request_hash,
    }
    state_core = {
        "schema_version": 1,
        "artifact_contract": CONTROLLER_STATE_CONTRACT,
        "selector_input_hash": selector_input["selector_input_hash"],
        "candidate_packages": candidates,
        "opaque_mapping": opaque_mapping,
        "owner_reference_hash": owner["reference_hash"],
        "request_hash": request_hash,
    }
    controller_state = {
        **state_core,
        "controller_state_hash": trial.canonical_hash(state_core),
    }
    root = _selection_root(output_root)
    if any(root.iterdir()):
        raise ValueError("active-control output root is not empty")
    _write_json_exclusive(root / "active-control-claim.json", claim, "claim")
    _write_json_exclusive(
        root / "controller-state.json", controller_state, "controller state"
    )
    _write_json_exclusive(root / "selector-input.json", selector_input, "selector input")
    return selector_input


def _validate_controller_state(value: Any) -> dict[str, Any]:
    state = _require_object(value, "controller state")
    _require_exact_fields(state, CONTROLLER_STATE_FIELDS, "controller state")
    if (
        state.get("schema_version") != 1
        or state.get("artifact_contract") != CONTROLLER_STATE_CONTRACT
    ):
        raise ValueError("controller state contract is invalid")
    state_hash = _require_hash(
        state.get("controller_state_hash"), "controller_state_hash"
    )
    if state_hash != _hash_body(state, "controller_state_hash"):
        raise ValueError("controller state hash mismatch")
    candidates = state.get("candidate_packages")
    if not isinstance(candidates, list) or len(candidates) != 2:
        raise ValueError("controller state candidate set is invalid")
    validated_candidates = [_validate_candidate_package(item) for item in candidates]
    mapping = _require_object(state.get("opaque_mapping"), "opaque_mapping")
    if set(mapping) == set() or len(mapping) != 2:
        raise ValueError("opaque mapping is invalid")
    for opaque_id, package_hash in mapping.items():
        if not isinstance(opaque_id, str) or not OPAQUE_ID.fullmatch(opaque_id):
            raise ValueError("opaque mapping id is invalid")
        _require_hash(package_hash, "opaque mapping package hash")
    package_hashes = {candidate["package_hash"] for candidate in validated_candidates}
    if set(mapping.values()) != package_hashes:
        raise ValueError("opaque mapping package set mismatch")
    _require_hash(state.get("selector_input_hash"), "state selector_input_hash")
    _require_hash(
        state.get("owner_reference_hash"), "state owner_reference_hash"
    )
    _require_hash(state.get("request_hash"), "state request_hash")
    return json.loads(trial.canonical_json(state))


def _validate_decision(
    value: Any, *, selector_input_hash: str, rubric_hash: str, opaque_ids: set[str]
) -> dict[str, Any]:
    decision = _require_object(value, "selector decision")
    _require_exact_fields(decision, DECISION_FIELDS, "selector decision")
    if (
        decision.get("schema_version") != 1
        or decision.get("artifact_contract") != DECISION_CONTRACT
    ):
        raise ValueError("selector decision contract is invalid")
    if decision.get("selector_input_hash") != selector_input_hash:
        raise ValueError("selector decision input hash mismatch")
    if decision.get("rubric_hash") != rubric_hash:
        raise ValueError("selector decision rubric hash mismatch")
    if decision.get("selected_opaque_id") not in opaque_ids:
        raise ValueError("selector decision selected id is invalid")
    return dict(decision)


def finalize_active_control(
    output_root: Path, selector_decision: Mapping[str, Any]
) -> dict[str, Any]:
    """Validate a blind decision and publish one sealed selection envelope."""

    root = _selection_root(output_root)
    selection_path = root / "active-control-selection.json"
    if selection_path.exists() or selection_path.is_symlink():
        raise ValueError("active-control selection is already finalized")
    expected_files = {
        "active-control-claim.json",
        "selector-input.json",
        "controller-state.json",
    }
    if {path.name for path in root.iterdir()} != expected_files:
        raise ValueError("active-control preparation artifact set is incomplete")
    claim = trial.load_private_json(root / "active-control-claim.json")
    if (
        not isinstance(claim, Mapping)
        or set(claim)
        != {
            "schema_version",
            "artifact_contract",
            "owner_reference_hash",
            "request_hash",
        }
        or claim.get("schema_version") != 1
        or claim.get("artifact_contract") != CLAIM_CONTRACT
    ):
        raise ValueError("active-control claim is invalid")
    selector_input = _validate_selector_input(
        trial.load_private_json(root / "selector-input.json")
    )
    state = _validate_controller_state(
        trial.load_private_json(root / "controller-state.json")
    )
    if state["selector_input_hash"] != selector_input["selector_input_hash"]:
        raise ValueError("controller state selector input mismatch")
    request = {
        "selector_input_hash": state["selector_input_hash"],
        "candidate_package_hashes": [
            candidate["package_hash"] for candidate in state["candidate_packages"]
        ],
        "opaque_mapping": state["opaque_mapping"],
        "owner_reference_hash": state["owner_reference_hash"],
    }
    if (
        state["request_hash"] != trial.canonical_hash(request)
        or claim.get("request_hash") != state["request_hash"]
        or claim.get("owner_reference_hash") != state["owner_reference_hash"]
    ):
        raise ValueError("active-control request hash mismatch")
    decision = _validate_decision(
        selector_decision,
        selector_input_hash=selector_input["selector_input_hash"],
        rubric_hash=selector_input["rubric_hash"],
        opaque_ids=set(state["opaque_mapping"]),
    )
    selected_package_hash = state["opaque_mapping"][decision["selected_opaque_id"]]
    selected_package = next(
        candidate
        for candidate in state["candidate_packages"]
        if candidate["package_hash"] == selected_package_hash
    )
    selection_core = {
        "schema_version": 1,
        "artifact_contract": SELECTION_CONTRACT,
        "brief_hash": selector_input["brief_hash"],
        "rubric": selector_input["rubric"],
        "rubric_hash": selector_input["rubric_hash"],
        "constraint_spec": selector_input["constraint_spec"],
        "constraint_spec_hash": selector_input["constraint_spec_hash"],
        "candidate_packages": state["candidate_packages"],
        "candidate_package_hashes": [
            candidate["package_hash"] for candidate in state["candidate_packages"]
        ],
        "opaque_order": selector_input["opaque_order"],
        "opaque_mapping": state["opaque_mapping"],
        "selector_input": selector_input,
        "selector_input_hash": selector_input["selector_input_hash"],
        "owner_reference_hash": state["owner_reference_hash"],
        "request_hash": state["request_hash"],
        "decision": decision,
        "selected_package_hash": selected_package_hash,
        "selected_scope_hashes": selected_package["scope_hashes"],
        "selected_scope_contents": selected_package["scope_contents"],
        "independence_status": "human-authorship-attested",
        "independence_boundary": (
            "commitments-and-attestations-do-not-prove-real-world-independence"
        ),
        "temporal_boundary": "controller-ordering-only-not-external-timestamp-proof",
    }
    selection = {
        **selection_core,
        "artifact_hash": trial.canonical_hash(selection_core),
    }
    _validate_selection_payload(selection)
    _write_json_exclusive(selection_path, selection, "active-control selection")
    return selection


def _validate_selection_payload(value: Any) -> dict[str, Any]:
    selection = _require_object(value, "active-control selection")
    _require_exact_fields(selection, SELECTION_FIELDS, "active-control selection")
    if (
        selection.get("schema_version") != 1
        or selection.get("artifact_contract") != SELECTION_CONTRACT
    ):
        raise ValueError("active-control selection contract is invalid")
    artifact_hash = _require_hash(selection.get("artifact_hash"), "artifact_hash")
    if artifact_hash != _hash_body(selection, "artifact_hash"):
        raise ValueError("active-control selection artifact hash mismatch")
    selector_input = _validate_selector_input(selection.get("selector_input"))
    if selection.get("selector_input_hash") != selector_input["selector_input_hash"]:
        raise ValueError("selection selector input hash mismatch")
    for field in (
        "brief_hash",
        "rubric_hash",
        "constraint_spec_hash",
        "opaque_order",
    ):
        if selection.get(field) != selector_input.get(field):
            raise ValueError(f"selection selector binding mismatch: {field}")
    candidates = selection.get("candidate_packages")
    if not isinstance(candidates, list) or len(candidates) != 2:
        raise ValueError("selection candidate set is invalid")
    validated_candidates = [
        _validate_candidate_package(candidate, expected_brief_hash=selection["brief_hash"])
        for candidate in candidates
    ]
    expected_package_hashes = [
        candidate["package_hash"] for candidate in validated_candidates
    ]
    if selection.get("candidate_package_hashes") != expected_package_hashes:
        raise ValueError("selection candidate package hash mismatch")
    mapping = _require_object(selection.get("opaque_mapping"), "selection mapping")
    if set(mapping) != set(selection["opaque_order"]):
        raise ValueError("selection opaque mapping id mismatch")
    if set(mapping.values()) != set(expected_package_hashes):
        raise ValueError("selection opaque mapping package mismatch")
    owner_reference_hash = _require_hash(
        selection.get("owner_reference_hash"), "selection owner_reference_hash"
    )
    request = {
        "selector_input_hash": selection["selector_input_hash"],
        "candidate_package_hashes": expected_package_hashes,
        "opaque_mapping": dict(mapping),
        "owner_reference_hash": owner_reference_hash,
    }
    request_hash = _require_hash(selection.get("request_hash"), "selection request_hash")
    if request_hash != trial.canonical_hash(request):
        raise ValueError("selection request hash mismatch")
    decision = _validate_decision(
        selection.get("decision"),
        selector_input_hash=selection["selector_input_hash"],
        rubric_hash=selection["rubric_hash"],
        opaque_ids=set(mapping),
    )
    expected_selected_hash = mapping[decision["selected_opaque_id"]]
    if selection.get("selected_package_hash") != expected_selected_hash:
        raise ValueError("selection selected package mismatch")
    selected_package = next(
        candidate
        for candidate in validated_candidates
        if candidate["package_hash"] == expected_selected_hash
    )
    if selection.get("selected_scope_hashes") != selected_package["scope_hashes"]:
        raise ValueError("selection selected scope hash mismatch")
    if selection.get("selected_scope_contents") != selected_package["scope_contents"]:
        raise ValueError("selection selected scope content mismatch")
    if selection.get("rubric") != selector_input["rubric"]:
        raise ValueError("selection rubric mismatch")
    if selection.get("constraint_spec") != selector_input["constraint_spec"]:
        raise ValueError("selection constraint spec mismatch")
    if selection.get("independence_status") != "human-authorship-attested":
        raise ValueError("selection independence status is invalid")
    if selection.get("independence_boundary") != (
        "commitments-and-attestations-do-not-prove-real-world-independence"
    ):
        raise ValueError("selection independence boundary is invalid")
    if selection.get("temporal_boundary") != (
        "controller-ordering-only-not-external-timestamp-proof"
    ):
        raise ValueError("selection temporal boundary is invalid")
    return json.loads(trial.canonical_json(selection))


def load_active_control_selection(path: Path) -> dict[str, Any]:
    """Load and strictly verify one owner-private selection envelope."""

    path = trial._external_private_path(
        Path(path), "active-control selection", create_parent=False
    )
    return _validate_selection_payload(trial.load_private_json(path))


def _validate_owner_commitment_root(
    root: Path, selection: Mapping[str, Any]
) -> None:
    """Verify the pre-selection owner commitment retained beside a selection."""

    sealed = _validate_selection_payload(selection)
    claim = trial.load_private_json(root / "active-control-claim.json")
    if (
        not isinstance(claim, Mapping)
        or set(claim)
        != {
            "schema_version",
            "artifact_contract",
            "owner_reference_hash",
            "request_hash",
        }
        or claim.get("schema_version") != 1
        or claim.get("artifact_contract") != CLAIM_CONTRACT
    ):
        raise ValueError("active-control owner commitment claim is invalid")
    state = _validate_controller_state(
        trial.load_private_json(root / "controller-state.json")
    )
    request = {
        "selector_input_hash": state["selector_input_hash"],
        "candidate_package_hashes": [
            candidate["package_hash"] for candidate in state["candidate_packages"]
        ],
        "opaque_mapping": state["opaque_mapping"],
        "owner_reference_hash": state["owner_reference_hash"],
    }
    if state["request_hash"] != trial.canonical_hash(request):
        raise ValueError("active-control owner commitment request is invalid")
    for field in ("owner_reference_hash", "request_hash"):
        if claim.get(field) != sealed.get(field):
            raise ValueError("active-control owner commitment does not match selection")
    for field in ("owner_reference_hash", "request_hash", "selector_input_hash"):
        if state.get(field) != sealed.get(field):
            raise ValueError("active-control owner commitment does not match selection")


def _validate_owner_scope_contents(value: Any) -> dict[str, str]:
    contents = _require_object(value, "owner reference scope_contents")
    if set(contents) != set(SCOPES):
        raise ValueError("owner reference scope set is invalid")
    normalized: dict[str, str] = {}
    for scope in SCOPES:
        content = contents.get(scope)
        if not isinstance(content, str) or not content.strip():
            raise ValueError(f"owner reference scope content is invalid: {scope}")
        normalized[scope] = content
    return normalized


def freeze_owner_reference(*, scope_contents: Mapping[str, str]) -> dict[str, Any]:
    """Freeze private Oracle contents without copying them into measurements."""

    contents = _validate_owner_scope_contents(scope_contents)
    body = {
        "schema_version": 1,
        "artifact_contract": OWNER_REFERENCE_CONTRACT,
        "scope_contents": contents,
        "scope_hashes": {
            scope: trial.canonical_hash(contents[scope]) for scope in SCOPES
        },
    }
    return {**body, "reference_hash": trial.canonical_hash(body)}


def _validate_owner_reference(value: Any) -> dict[str, Any]:
    reference = _require_object(value, "owner reference")
    _require_exact_fields(reference, OWNER_REFERENCE_FIELDS, "owner reference")
    if (
        reference.get("schema_version") != 1
        or reference.get("artifact_contract") != OWNER_REFERENCE_CONTRACT
    ):
        raise ValueError("owner reference contract is invalid")
    contents = _validate_owner_scope_contents(reference.get("scope_contents"))
    expected_hashes = {
        scope: trial.canonical_hash(contents[scope]) for scope in SCOPES
    }
    if reference.get("scope_hashes") != expected_hashes:
        raise ValueError("owner reference scope hash mismatch")
    reference_hash = _require_hash(
        reference.get("reference_hash"), "owner reference_hash"
    )
    if reference_hash != _hash_body(reference, "reference_hash"):
        raise ValueError("owner reference hash mismatch")
    return json.loads(trial.canonical_json(reference))


def _content_metrics(content: str) -> dict[str, int]:
    normalized = content.replace("\r\n", "\n").replace("\r", "\n")
    paragraphs = [
        block
        for block in re.split(r"\n[ \t]*\n", normalized.strip())
        if block.strip()
    ]
    instructions = [
        line
        for line in normalized.splitlines()
        if re.match(r"^[ \t]*(?:[-*+]|[0-9]+[.)])[ \t]+\S", line)
    ]
    tokens = re.findall(r"[A-Za-z0-9_]+|[^\sA-Za-z0-9_]", normalized)
    return {
        "paragraph_count": len(paragraphs),
        "instruction_count": len(instructions),
        "token_count": len(tokens),
    }


def _within_owner_tolerance(selected: int, owner: int) -> bool:
    """Return inclusive ±10% without floating-point rounding."""

    return owner > 0 and selected * 10 >= owner * 9 and selected * 10 <= owner * 11


def _validate_measurement_payload(
    value: Any,
    *,
    selection: Mapping[str, Any] | None = None,
    owner_reference: Mapping[str, Any] | None = None,
) -> dict[str, Any]:
    measurement = _require_object(value, "owner-relative measurement")
    _require_exact_fields(
        measurement,
        OWNER_RELATIVE_MEASUREMENT_FIELDS,
        "owner-relative measurement",
    )
    if (
        measurement.get("schema_version") != 1
        or measurement.get("artifact_contract")
        != OWNER_RELATIVE_MEASUREMENT_CONTRACT
    ):
        raise ValueError("owner-relative measurement contract is invalid")
    if measurement.get("measurement_contracts") != MEASUREMENT_CONTRACTS:
        raise ValueError("owner-relative measurement algorithms are invalid")
    if measurement.get("status") not in {"pass", "fail"}:
        raise ValueError("owner-relative measurement status is invalid")
    if measurement.get("boundary") != (
        "structural-counts-do-not-prove-semantic-equivalence"
    ):
        raise ValueError("owner-relative measurement boundary is invalid")
    for field in (
        "selection_artifact_hash",
        "selected_package_hash",
        "owner_reference_hash",
        "request_hash",
        "measurement_hash",
    ):
        _require_hash(measurement.get(field), f"owner-relative {field}")
    if measurement["measurement_hash"] != _hash_body(
        measurement, "measurement_hash"
    ):
        raise ValueError("owner-relative measurement hash mismatch")
    scopes = _require_object(measurement.get("scopes"), "measurement scopes")
    if set(scopes) != set(SCOPES):
        raise ValueError("owner-relative measurement scope set is invalid")
    scope_statuses: list[str] = []
    for scope in SCOPES:
        record = _require_object(scopes[scope], f"measurement scope {scope}")
        expected_fields = {
            "selected_scope_content_hash",
            "owner_scope_content_hash",
            "selected",
            "owner",
            "checks",
            "status",
        }
        _require_exact_fields(record, expected_fields, f"measurement scope {scope}")
        _require_hash(
            record.get("selected_scope_content_hash"),
            f"measurement selected content {scope}",
        )
        _require_hash(
            record.get("owner_scope_content_hash"),
            f"measurement owner content {scope}",
        )
        selected_metrics = _require_object(
            record.get("selected"), f"measurement selected metrics {scope}"
        )
        owner_metrics = _require_object(
            record.get("owner"), f"measurement owner metrics {scope}"
        )
        checks = _require_object(record.get("checks"), f"measurement checks {scope}")
        if (
            set(selected_metrics) != METRIC_FIELDS
            or set(owner_metrics) != METRIC_FIELDS
            or set(checks) != METRIC_FIELDS
        ):
            raise ValueError(f"owner-relative metric field set is invalid: {scope}")
        for metric in METRIC_FIELDS:
            selected_count = selected_metrics[metric]
            owner_count = owner_metrics[metric]
            if (
                not isinstance(selected_count, int)
                or isinstance(selected_count, bool)
                or selected_count < 0
                or not isinstance(owner_count, int)
                or isinstance(owner_count, bool)
                or owner_count < 0
            ):
                raise ValueError(f"owner-relative metric count is invalid: {scope}")
            expected_check = _within_owner_tolerance(selected_count, owner_count)
            if checks[metric] is not expected_check:
                raise ValueError(f"owner-relative metric check mismatch: {scope}")
        expected_scope_status = "pass" if all(checks.values()) else "fail"
        if record.get("status") != expected_scope_status:
            raise ValueError(f"owner-relative scope status is invalid: {scope}")
        scope_statuses.append(expected_scope_status)
    expected_status = "pass" if all(
        status == "pass" for status in scope_statuses
    ) else "fail"
    if measurement["status"] != expected_status:
        raise ValueError("owner-relative measurement summary is invalid")
    if selection is not None:
        sealed = _validate_selection_payload(selection)
        if (
            measurement["selection_artifact_hash"] != sealed["artifact_hash"]
            or measurement["selected_package_hash"]
            != sealed["selected_package_hash"]
            or measurement["owner_reference_hash"]
            != sealed["owner_reference_hash"]
            or measurement["request_hash"] != sealed["request_hash"]
        ):
            raise ValueError("owner-relative selection binding mismatch")
        for scope in SCOPES:
            if (
                scopes[scope]["selected_scope_content_hash"]
                != sealed["selected_scope_hashes"][scope]
            ):
                raise ValueError("owner-relative selected scope binding mismatch")
            if scopes[scope]["selected"] != _content_metrics(
                sealed["selected_scope_contents"][scope]
            ):
                raise ValueError("owner-relative selected metrics mismatch")
    if owner_reference is not None:
        owner = _validate_owner_reference(owner_reference)
        if measurement["owner_reference_hash"] != owner["reference_hash"]:
            raise ValueError("owner-relative owner reference binding mismatch")
        for scope in SCOPES:
            if (
                scopes[scope]["owner_scope_content_hash"]
                != owner["scope_hashes"][scope]
            ):
                raise ValueError("owner-relative owner scope binding mismatch")
            if scopes[scope]["owner"] != _content_metrics(
                owner["scope_contents"][scope]
            ):
                raise ValueError("owner-relative owner metrics mismatch")
    return json.loads(trial.canonical_json(measurement))


def measure_owner_relative(
    output_root: Path, owner_reference: Mapping[str, Any]
) -> dict[str, Any]:
    """Measure the sealed selection against a private Oracle reference."""

    root = _selection_root(output_root)
    measurement_path = root / "owner-relative-measurement.json"
    expected_files = {
        "active-control-claim.json",
        "selector-input.json",
        "controller-state.json",
        "active-control-selection.json",
    }
    actual_files = {path.name for path in root.iterdir()}
    if actual_files != expected_files:
        if measurement_path.exists() or measurement_path.is_symlink():
            raise ValueError("owner-relative measurement already exists")
        missing = sorted(expected_files - actual_files)
        if missing:
            raise ValueError(
                f"active-control finalized artifact set is incomplete: {missing}"
            )
        extra = sorted(actual_files - expected_files)
        raise ValueError(f"active-control root contains unexpected artifact: {extra}")
    selection = load_active_control_selection(root / "active-control-selection.json")
    _validate_owner_commitment_root(root, selection)
    owner = _validate_owner_reference(owner_reference)
    if owner["reference_hash"] != selection["owner_reference_hash"]:
        raise ValueError("owner reference does not match committed owner reference")
    scope_records: dict[str, Any] = {}
    for scope in SCOPES:
        selected_metrics = _content_metrics(selection["selected_scope_contents"][scope])
        owner_metrics = _content_metrics(owner["scope_contents"][scope])
        checks = {
            metric: _within_owner_tolerance(
                selected_metrics[metric], owner_metrics[metric]
            )
            for metric in sorted(METRIC_FIELDS)
        }
        scope_records[scope] = {
            "selected_scope_content_hash": selection["selected_scope_hashes"][scope],
            "owner_scope_content_hash": owner["scope_hashes"][scope],
            "selected": selected_metrics,
            "owner": owner_metrics,
            "checks": checks,
            "status": "pass" if all(checks.values()) else "fail",
        }
    measurement_status = (
        "pass"
        if all(record["status"] == "pass" for record in scope_records.values())
        else "fail"
    )
    body = {
        "schema_version": 1,
        "artifact_contract": OWNER_RELATIVE_MEASUREMENT_CONTRACT,
        "selection_artifact_hash": selection["artifact_hash"],
        "selected_package_hash": selection["selected_package_hash"],
        "owner_reference_hash": owner["reference_hash"],
        "request_hash": selection["request_hash"],
        "measurement_contracts": MEASUREMENT_CONTRACTS,
        "scopes": scope_records,
        "status": measurement_status,
        "boundary": "structural-counts-do-not-prove-semantic-equivalence",
    }
    measurement = {
        **body,
        "measurement_hash": trial.canonical_hash(body),
    }
    _validate_measurement_payload(
        measurement, selection=selection, owner_reference=owner
    )
    _write_json_exclusive(
        measurement_path, measurement, "owner-relative measurement"
    )
    return measurement


def load_owner_relative_measurement(
    path: Path,
    *,
    selection: Mapping[str, Any],
    owner_reference: Mapping[str, Any],
) -> dict[str, Any]:
    """Strictly load a private owner-relative measurement and its bindings."""

    path = trial._external_private_path(
        Path(path), "owner-relative measurement", create_parent=False
    )
    _validate_owner_commitment_root(path.parent, selection)
    return _validate_measurement_payload(
        trial.load_private_json(path),
        selection=selection,
        owner_reference=owner_reference,
    )


def _require_bundle_id(value: Any, label: str) -> str:
    if not isinstance(value, str) or not BUNDLE_ID.fullmatch(value):
        raise ValueError(f"{label} is invalid")
    return value


def _evaluate_matched_call_fixture(
    events: Mapping[str, Any], *, target_bundle_id: str
) -> dict[str, Any]:
    """Evaluate one synthetic ordered fixture; never return a live-gate allow."""

    target_bundle_id_is_valid = isinstance(
        target_bundle_id, str
    ) and BUNDLE_ID.fullmatch(target_bundle_id)
    reported_target_bundle_id = (
        target_bundle_id if target_bundle_id_is_valid else "invalid-target"
    )

    def result(decision: str, reason_code: str) -> dict[str, Any]:
        return {
            "schema_version": 1,
            "gate_contract_hash": MATCHED_CALL_GATE_CONTRACT_HASH,
            "target_bundle_id": reported_target_bundle_id,
            "decision": decision,
            "reason_code": reason_code,
            "deny_message": (
                MATCHED_CALL_DENY_TEMPLATE.format(
                    target_bundle_id=reported_target_bundle_id
                )
                if decision == "deny" and target_bundle_id_is_valid
                else None
            ),
        }

    try:
        target_bundle_id = _require_bundle_id(target_bundle_id, "target bundle id")
        record = _require_object(events, "matched-call event record")
        _require_exact_fields(
            record,
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
            "matched-call event record",
        )
        if record.get("schema_version") != 1:
            raise ValueError("matched-call event schema version is invalid")
        status = record.get("event_contract_status")
        available = record.get("skill_events_available")
        task_tools_available = record.get("task_tool_events_available")
        if (
            status not in {"stable", "degraded"}
            or not isinstance(available, bool)
            or not isinstance(task_tools_available, bool)
        ):
            raise ValueError("matched-call event contract state is invalid")
        if (
            record.get("event_contract_version") != MATCHED_CALL_EVENT_CONTRACT
            or status != "stable"
            or not available
            or not task_tools_available
        ):
            return result("deny", "event_contract_unverifiable")
        first_task_tool_index = record.get("first_task_tool_event_index")
        if (
            record.get("event_index_source")
            != "fixture-modeled-single-monotonic-stream"
        ):
            return result("deny", "event_contract_unverifiable")
        if (
            not isinstance(first_task_tool_index, int)
            or isinstance(first_task_tool_index, bool)
            or first_task_tool_index < 0
            or first_task_tool_index > MAX_MATCHED_CALL_EVENT_INDEX
        ):
            raise ValueError("matched-call first task-tool index is invalid")
        invocations = record.get("skills_invoked")
        if (
            not isinstance(invocations, list)
            or len(invocations) > MAX_MATCHED_CALL_INVOCATIONS
        ):
            raise ValueError("matched-call skills_invoked must be a list")
        completed = False
        late = False
        seen_event_indexes: set[int] = set()
        seen_tool_use_ids: set[str] = set()
        for item in invocations:
            invocation = _require_object(item, "matched-call invocation")
            _require_exact_fields(
                invocation,
                {
                    "skill",
                    "event_index",
                    "tool_use_id",
                    "matching_tool_result",
                    "completed",
                },
                "matched-call invocation",
            )
            skill = _require_bundle_id(invocation.get("skill"), "invoked bundle id")
            event_index = invocation.get("event_index")
            if (
                not isinstance(event_index, int)
                or isinstance(event_index, bool)
                or event_index < 0
                or event_index > MAX_MATCHED_CALL_EVENT_INDEX
                or event_index in seen_event_indexes
                or event_index == first_task_tool_index
            ):
                raise ValueError("matched-call invocation event_index is invalid")
            seen_event_indexes.add(event_index)
            tool_use_id = invocation.get("tool_use_id")
            if (
                not isinstance(tool_use_id, str)
                or not tool_use_id
                or len(tool_use_id) > MAX_MATCHED_CALL_TOOL_USE_ID_CHARACTERS
                or tool_use_id in seen_tool_use_ids
            ):
                raise ValueError("matched-call tool_use_id is invalid")
            seen_tool_use_ids.add(tool_use_id)
            matching_result = invocation.get("matching_tool_result")
            invocation_completed = invocation.get("completed")
            if not isinstance(matching_result, bool) or not isinstance(
                invocation_completed, bool
            ):
                raise ValueError("matched-call invocation result state is invalid")
            if invocation_completed and not matching_result:
                raise ValueError("matched-call completed invocation lacks matching result")
            matching_completed = (
                skill == target_bundle_id
                and matching_result
                and invocation_completed
            )
            if matching_completed:
                if event_index < first_task_tool_index:
                    completed = True
                else:
                    late = True
        if first_task_tool_index > max(seen_event_indexes, default=-1) + 1:
            raise ValueError("matched-call fixture ordering window is invalid")
    except Exception:
        return result("deny", "event_contract_unverifiable")
    if completed:
        return result("fixture-pass", "fixture_matched_call_satisfied")
    if late:
        return result("deny", "matched_call_late")
    return result("deny", "matched_call_required")


def _matched_call_fixture_results(target_bundle_id: str) -> dict[str, Any]:
    target_bundle_id = _require_bundle_id(target_bundle_id, "target bundle id")
    wrong_bundle_id = "fixture-wrong-bundle"
    if wrong_bundle_id == target_bundle_id:
        wrong_bundle_id = "fixture-wrong-bundle-0"
    stable = {
        "schema_version": 1,
        "event_contract_version": MATCHED_CALL_EVENT_CONTRACT,
        "event_contract_status": "stable",
        "skill_events_available": True,
        "task_tool_events_available": True,
        "first_task_tool_event_index": 0,
        "event_index_source": "fixture-modeled-single-monotonic-stream",
        "skills_invoked": [],
    }

    def result(events: Mapping[str, Any]) -> dict[str, Any]:
        evaluated = _evaluate_matched_call_fixture(
            events, target_bundle_id=target_bundle_id
        )
        return {
            "decision": evaluated["decision"],
            "reason_code": evaluated["reason_code"],
            "deny_message": evaluated["deny_message"],
            "observation_status": "none-fixtures-only",
            "live_gate_eligible": False,
        }

    invoked = {
        "skill": target_bundle_id,
        "event_index": 0,
        "tool_use_id": "fixture-target-call",
        "matching_tool_result": True,
        "completed": True,
    }
    invoked_stable = {**stable, "first_task_tool_event_index": 1}
    wrong = {
        **invoked,
        "skill": wrong_bundle_id,
        "event_index": 0,
        "tool_use_id": "fixture-wrong-call",
    }
    incomplete = {**invoked, "completed": False}
    results = {
        "missing": result(stable),
        "wrong_target": result({**invoked_stable, "skills_invoked": [wrong]}),
        "incomplete": result({**invoked_stable, "skills_invoked": [incomplete]}),
        "degraded": result({**stable, "event_contract_status": "degraded"}),
        "missing_task_tool_index": result(
            {**stable, "first_task_tool_event_index": None}
        ),
        "completed": result({**invoked_stable, "skills_invoked": [invoked]}),
        "late_after_task_tool": result(
            {
                **stable,
                "skills_invoked": [{**invoked, "event_index": 2}],
            }
        ),
    }
    if results != _expected_matched_call_fixture_results(target_bundle_id):
        raise ValueError("matched-call fixture outcome contract mismatch")
    return results


def _expected_matched_call_fixture_results(
    target_bundle_id: str,
) -> dict[str, Any]:
    """Build the full fixture payload from frozen literals, not the evaluator."""

    target_bundle_id = _require_bundle_id(target_bundle_id, "target bundle id")
    results = {}
    for name, outcome in MATCHED_CALL_FIXTURE_EXPECTED_OUTCOMES.items():
        decision, reason_code = outcome
        results[name] = {
            "decision": decision,
            "reason_code": reason_code,
            "deny_message": (
                MATCHED_CALL_DENY_TEMPLATE.format(target_bundle_id=target_bundle_id)
                if decision == "deny"
                else None
            ),
            "observation_status": MATCHED_CALL_FIXTURE_RESULT_CONTRACT[
                "observation_status"
            ],
            "live_gate_eligible": MATCHED_CALL_FIXTURE_RESULT_CONTRACT[
                "live_gate_eligible"
            ],
        }
    return results


def _validate_matched_call_evidence(
    value: Any,
    *,
    selection: Mapping[str, Any],
    measurement: Mapping[str, Any],
    owner_reference: Mapping[str, Any],
) -> dict[str, Any]:
    evidence = _require_object(value, "matched-call evidence")
    _require_exact_fields(
        evidence, MATCHED_CALL_EVIDENCE_FIELDS, "matched-call evidence"
    )
    if (
        evidence.get("schema_version") != 1
        or evidence.get("artifact_contract") != MATCHED_CALL_EVIDENCE_CONTRACT
    ):
        raise ValueError("matched-call evidence contract is invalid")
    if evidence.get("scope") not in SCOPES:
        raise ValueError("matched-call evidence scope is invalid")
    gate_contract = dict(
        _require_object(evidence.get("gate_contract"), "matched-call gate contract")
    )
    if gate_contract != MATCHED_CALL_GATE_SPEC:
        raise ValueError("matched-call gate contract is invalid")
    embedded_gate_contract_hash = trial.canonical_hash(gate_contract)
    if (
        evidence.get("gate_contract_hash") != embedded_gate_contract_hash
        or embedded_gate_contract_hash != MATCHED_CALL_GATE_CONTRACT_HASH
    ):
        raise ValueError("matched-call gate contract hash mismatch")
    if evidence.get("allowed_target_differences") != ["bundle_id", "content_hash"]:
        raise ValueError("matched-call allowed target differences are invalid")
    if evidence.get("status") != MATCHED_CALL_DECLARATION_STATUS:
        raise ValueError("matched-call evidence status is invalid")
    if evidence.get("observation_status") != "none-fixtures-only":
        raise ValueError("matched-call evidence observation status is invalid")
    if evidence.get("matched_call_gate_satisfied") is not False:
        raise ValueError("matched-call evidence gate status is invalid")
    if evidence.get("boundary") != MATCHED_CALL_BOUNDARY:
        raise ValueError("matched-call evidence boundary is invalid")
    for field in (
        "selection_artifact_hash",
        "owner_relative_measurement_hash",
        "owner_reference_hash",
        "artifact_hash",
    ):
        _require_hash(evidence.get(field), f"matched-call {field}")
    if evidence["artifact_hash"] != _hash_body(evidence, "artifact_hash"):
        raise ValueError("matched-call evidence hash mismatch")
    targets = _require_object(evidence.get("targets"), "matched-call targets")
    if set(targets) != {"active_control", "oracle"}:
        raise ValueError("matched-call target set is invalid")
    for target_kind in ("active_control", "oracle"):
        target = _require_object(
            targets[target_kind], f"matched-call {target_kind} target"
        )
        _require_exact_fields(
            target,
            {"bundle_id", "content_hash"},
            f"matched-call {target_kind} target",
        )
        _require_bundle_id(target.get("bundle_id"), f"{target_kind} bundle id")
        _require_hash(target.get("content_hash"), f"{target_kind} content hash")
    if targets["active_control"]["bundle_id"] == targets["oracle"]["bundle_id"]:
        raise ValueError("matched-call target bundle ids must differ")
    expected_results = {
        target_kind: _expected_matched_call_fixture_results(
            targets[target_kind]["bundle_id"]
        )
        for target_kind in ("active_control", "oracle")
    }
    if evidence.get("fixture_results") != expected_results:
        raise ValueError("matched-call fixture results mismatch")
    sealed = _validate_selection_payload(selection)
    scope = evidence["scope"]
    expected_active_bundle_id = (
        f"{sealed['decision']['selected_opaque_id']}-{scope}"
    )
    if targets["active_control"]["bundle_id"] != expected_active_bundle_id:
        raise ValueError(
            "active-control bundle id must match selected opaque id and scope"
        )
    if targets["oracle"]["bundle_id"] != f"oracle-owner-{scope}":
        raise ValueError("oracle bundle id must match scope")
    if targets["active_control"]["content_hash"] == targets["oracle"]["content_hash"]:
        raise ValueError("matched-call target content hashes must differ")
    if evidence["selection_artifact_hash"] != sealed["artifact_hash"]:
        raise ValueError("matched-call selection binding mismatch")
    if (
        targets["active_control"]["content_hash"]
        != sealed["selected_scope_hashes"][scope]
    ):
        raise ValueError("active-control target content hash mismatch")
    owner = _validate_owner_reference(owner_reference)
    if evidence["owner_reference_hash"] != owner["reference_hash"]:
        raise ValueError("matched-call owner reference binding mismatch")
    if targets["oracle"]["content_hash"] != owner["scope_hashes"][scope]:
        raise ValueError("oracle target content hash mismatch")
    measured = _validate_measurement_payload(
        measurement,
        selection=sealed,
        owner_reference=owner,
    )
    if measured["status"] != "pass":
        raise ValueError("matched-call evidence requires passing measurement")
    if (
        evidence["owner_relative_measurement_hash"]
        != measured["measurement_hash"]
    ):
        raise ValueError("matched-call measurement binding mismatch")
    return json.loads(trial.canonical_json(evidence))


def freeze_matched_call_evidence(
    output_root: Path,
    *,
    selection: Mapping[str, Any],
    measurement: Mapping[str, Any],
    owner_reference: Mapping[str, Any],
    scope: str,
    active_bundle_id: str,
    oracle_bundle_id: str,
) -> dict[str, Any]:
    """Publish one paired deterministic matched-call contract artifact."""

    root = _selection_root(output_root)
    if scope not in SCOPES:
        raise ValueError("matched-call evidence scope is invalid")
    evidence_path = root / MATCHED_CALL_EVIDENCE_FILENAMES[scope]
    expected_files = {
        "active-control-claim.json",
        "selector-input.json",
        "controller-state.json",
        "active-control-selection.json",
        "owner-relative-measurement.json",
    }
    actual_files = {path.name for path in root.iterdir()}
    evidence_files = set(MATCHED_CALL_EVIDENCE_FILENAMES.values())
    missing = sorted(expected_files - actual_files)
    unexpected = sorted(actual_files - expected_files - evidence_files)
    if missing:
        raise ValueError(f"matched-call source artifact set is incomplete: {missing}")
    if unexpected:
        raise ValueError(
            f"active-control root contains unexpected artifact: {unexpected}"
        )
    if evidence_path.name in actual_files:
        raise ValueError("matched-call evidence already exists")
    sealed = _validate_selection_payload(selection)
    owner = _validate_owner_reference(owner_reference)
    measured = _validate_measurement_payload(
        measurement, selection=sealed, owner_reference=owner
    )
    canonical_selection = load_active_control_selection(
        root / "active-control-selection.json"
    )
    if sealed != canonical_selection:
        raise ValueError("matched-call selection does not match canonical artifact")
    canonical_measurement = load_owner_relative_measurement(
        root / "owner-relative-measurement.json",
        selection=canonical_selection,
        owner_reference=owner,
    )
    if measured != canonical_measurement:
        raise ValueError("matched-call measurement does not match canonical artifact")
    if measured["status"] != "pass":
        raise ValueError("matched-call evidence requires passing measurement")
    for existing_scope, existing_name in MATCHED_CALL_EVIDENCE_FILENAMES.items():
        if existing_name not in actual_files:
            continue
        existing_evidence = _require_object(
            trial.load_private_json(root / existing_name),
            "matched-call evidence",
        )
        if existing_evidence.get("scope") != existing_scope:
            raise ValueError("matched-call evidence filename scope mismatch")
        _validate_matched_call_evidence(
            existing_evidence,
            selection=sealed,
            measurement=measured,
            owner_reference=owner,
        )
    active_bundle_id = _require_bundle_id(active_bundle_id, "active-control bundle id")
    oracle_bundle_id = _require_bundle_id(oracle_bundle_id, "oracle bundle id")
    expected_active_bundle_id = f"{sealed['decision']['selected_opaque_id']}-{scope}"
    if active_bundle_id != expected_active_bundle_id:
        raise ValueError(
            "active-control bundle id must match selected opaque id and scope"
        )
    if oracle_bundle_id != f"oracle-owner-{scope}":
        raise ValueError("oracle bundle id must match scope")
    targets = {
        "active_control": {
            "bundle_id": active_bundle_id,
            "content_hash": sealed["selected_scope_hashes"][scope],
        },
        "oracle": {
            "bundle_id": oracle_bundle_id,
            "content_hash": owner["scope_hashes"][scope],
        },
    }
    body = {
        "schema_version": 1,
        "artifact_contract": MATCHED_CALL_EVIDENCE_CONTRACT,
        "selection_artifact_hash": sealed["artifact_hash"],
        "owner_relative_measurement_hash": measured["measurement_hash"],
        "owner_reference_hash": owner["reference_hash"],
        "scope": scope,
        "gate_contract": json.loads(trial.canonical_json(MATCHED_CALL_GATE_SPEC)),
        "gate_contract_hash": MATCHED_CALL_GATE_CONTRACT_HASH,
        "allowed_target_differences": ["bundle_id", "content_hash"],
        "targets": targets,
        "fixture_results": {
            target_kind: _matched_call_fixture_results(target["bundle_id"])
            for target_kind, target in targets.items()
        },
        "observation_status": "none-fixtures-only",
        "matched_call_gate_satisfied": False,
        "status": MATCHED_CALL_DECLARATION_STATUS,
        "boundary": MATCHED_CALL_BOUNDARY,
    }
    evidence = {**body, "artifact_hash": trial.canonical_hash(body)}
    _validate_matched_call_evidence(
        evidence,
        selection=sealed,
        measurement=measured,
        owner_reference=owner,
    )
    _write_json_exclusive(evidence_path, evidence, "matched-call evidence")
    return evidence


def load_matched_call_evidence(
    path: Path,
    *,
    selection: Mapping[str, Any],
    measurement: Mapping[str, Any],
    owner_reference: Mapping[str, Any],
) -> dict[str, Any]:
    """Strictly load paired matched-call evidence and all source bindings."""

    path = trial._external_private_path(
        Path(path), "matched-call evidence", create_parent=False
    )
    root = _selection_root(path.parent)
    scope = next(
        (
            candidate_scope
            for candidate_scope, filename in MATCHED_CALL_EVIDENCE_FILENAMES.items()
            if path == root / filename
        ),
        None,
    )
    if scope is None:
        raise ValueError("matched-call evidence must use its canonical private root")
    expected_files = {
        "active-control-claim.json",
        "selector-input.json",
        "controller-state.json",
        "active-control-selection.json",
        "owner-relative-measurement.json",
    }
    allowed_files = expected_files | set(MATCHED_CALL_EVIDENCE_FILENAMES.values())
    actual_files = {child.name for child in root.iterdir()}
    if (
        not expected_files.issubset(actual_files)
        or path.name not in actual_files
        or not actual_files.issubset(allowed_files)
    ):
        raise ValueError("matched-call canonical artifact set is invalid")
    sealed = _validate_selection_payload(selection)
    canonical_selection = load_active_control_selection(
        root / "active-control-selection.json"
    )
    if sealed != canonical_selection:
        raise ValueError("matched-call selection does not match canonical artifact")
    owner = _validate_owner_reference(owner_reference)
    measured = _validate_measurement_payload(
        measurement, selection=sealed, owner_reference=owner
    )
    canonical_measurement = load_owner_relative_measurement(
        root / "owner-relative-measurement.json",
        selection=canonical_selection,
        owner_reference=owner,
    )
    if measured != canonical_measurement:
        raise ValueError("matched-call measurement does not match canonical artifact")
    requested_evidence: dict[str, Any] | None = None
    for existing_scope, existing_name in MATCHED_CALL_EVIDENCE_FILENAMES.items():
        if existing_name not in actual_files:
            continue
        evidence = _require_object(
            trial.load_private_json(root / existing_name),
            "matched-call evidence",
        )
        if evidence.get("scope") != existing_scope:
            raise ValueError("matched-call evidence filename scope mismatch")
        validated = _validate_matched_call_evidence(
            evidence,
            selection=canonical_selection,
            measurement=canonical_measurement,
            owner_reference=owner,
        )
        if existing_scope == scope:
            requested_evidence = validated
    if requested_evidence is None:
        raise ValueError("matched-call requested evidence is missing")
    return requested_evidence


def active_control_manifest_binding(
    selection: Mapping[str, Any],
    *,
    scope: str,
    measurement: Mapping[str, Any] | None = None,
    owner_reference: Mapping[str, Any] | None = None,
) -> dict[str, Any]:
    """Return the exact selected-arm template fields for one scope."""

    selection = _validate_selection_payload(selection)
    if scope not in SCOPES:
        raise ValueError("selected active-control scope is invalid")
    binding = {
        "status": "selected",
        "artifact_hash": selection["artifact_hash"],
        "selected_package_hash": selection["selected_package_hash"],
        "selected_scope": scope,
        "selected_scope_content_hash": selection["selected_scope_hashes"][scope],
    }
    if measurement is None:
        raise ValueError("selected active-control requires owner-relative measurement")
    if owner_reference is None:
        raise ValueError("owner-relative measurement requires owner reference")
    measured = _validate_measurement_payload(
        measurement, selection=selection, owner_reference=owner_reference
    )
    if measured["status"] != "pass":
        raise ValueError("selected active-control requires passing owner-relative measurement")
    return {
        **binding,
        "status": "owner-relative-verified",
        "owner_relative_measurement_hash": measured["measurement_hash"],
        "owner_reference_hash": measured["owner_reference_hash"],
        "owner_commitment_request_hash": measured["request_hash"],
    }
