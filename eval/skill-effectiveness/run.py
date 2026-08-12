#!/usr/bin/env python3
"""Advisory trial-foundation, capability and reviewer-calibration CLI.

The `smoke` command is deliberately synthetic: it exercises manifest freezing,
artifact creation/resume, access-audit evaluation, multi-sample scheduling and
the frozen E10 gate without making a model/provider call.  Provider adapters
must supply equivalent evidence before any causal-core run can start.
Exit 3 means contract-complete but intentionally not evaluated, exit 1 means a
gate or execution failure, and exit 2 means invalid input or an internal contract
error. Synthetic smoke, provider probes and reviewer calibration can never
produce an effectiveness pass; they only establish narrower evaluator evidence.
"""

from __future__ import annotations

import argparse
import json
import secrets
import sys
from pathlib import Path


HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))

import active_control  # noqa: E402
import provider_probe  # noqa: E402
import reviewer_calibration  # noqa: E402
import trial  # noqa: E402


DEFAULT_PILOT_GATES = HERE / "pilot-gates.json"
DEFAULT_CALIBRATION_ANSWERS = (
    HERE / "fixtures" / "reviewer-calibration-known-answers.json"
)
DEFAULT_CALIBRATION_CASES = HERE / "fixtures" / "reviewer-calibration-cases.json"
DEFAULT_CLAUDE_RUNTIME_VALIDATOR = (
    HERE.parent.parent / "skills" / "code-review" / "scripts" / "parse_probe_result.py"
)
ARM_TEMPLATE_DIR = HERE / "arms"
MATCHED_CALL_COMMANDS = {
    "active-control-matched-call",
    "active-control-matched-call-verify",
}


def _redact_matched_call_error(message: str, args: argparse.Namespace) -> str:
    """Remove controller-private CLI paths while preserving the failure reason."""

    candidates: set[str] = set()
    for attribute in (
        "out",
        "selection",
        "measurement",
        "owner_reference",
        "evidence",
    ):
        value = getattr(args, attribute, None)
        if value is None:
            continue
        path = Path(value)
        candidate_paths = [path, path.parent] if path.is_absolute() else []
        try:
            resolved = path.resolve()
        except (OSError, RuntimeError):
            resolved = None
        if resolved is not None:
            candidate_paths.extend((resolved, resolved.parent))
        for candidate_path in candidate_paths:
            candidate = str(candidate_path)
            if candidate_path.is_absolute() and candidate != "/":
                candidates.add(candidate)
    for candidate in sorted(candidates, key=len, reverse=True):
        message = message.replace(candidate, "<controller-private-path>")
    return message


def current_runner_hash() -> str:
    return trial.canonical_hash(
        {
            "active_control.py": trial.canonical_hash(
                (HERE / "active_control.py").read_bytes()
            ),
            "trial.py": trial.canonical_hash((HERE / "trial.py").read_bytes()),
            "run.py": trial.canonical_hash((HERE / "run.py").read_bytes()),
        }
    )


def load_json(path: Path):
    with path.open(encoding="utf-8") as stream:
        return json.load(stream)


def load_external_private_json(path: Path, label: str):
    path = trial._external_private_path(path, label, create_parent=False)
    return trial.load_private_json(path)


def load_external_private_text(path: Path, label: str) -> str:
    path = trial._external_private_path(path, label, create_parent=False)
    try:
        return trial._read_private_file(path).decode("utf-8")
    except UnicodeDecodeError as exc:
        raise ValueError(f"{label} must be UTF-8") from exc


def load_preregistered_template(template_ref: str):
    if not isinstance(template_ref, str) or not template_ref:
        raise ValueError("arm template_ref is required")
    template_path = (HERE / template_ref).resolve(strict=True)
    try:
        relative = template_path.relative_to(ARM_TEMPLATE_DIR.resolve())
    except ValueError as exc:
        raise ValueError("arm template_ref must resolve under arms/") from exc
    if len(relative.parts) != 1 or template_path.suffix != ".json":
        raise ValueError("arm template_ref must name one arms/*.json file")
    return load_json(template_path)


def load_jsonl(path: Path):
    return trial.load_private_jsonl(path)


def validated_output_root(path: Path) -> Path:
    expanded = path.expanduser()
    if expanded.is_symlink():
        raise ValueError("output root must not be a symlink")
    output_root = expanded.resolve(strict=False)
    source_root = HERE.parents[1].resolve()
    if output_root in {Path("/").resolve(), Path.home().resolve()}:
        raise ValueError("output root is too broad")
    try:
        output_root.relative_to(source_root)
    except ValueError:
        pass
    else:
        raise ValueError("output root must stay outside the source checkout")
    try:
        source_root.relative_to(output_root)
    except ValueError:
        return output_root
    raise ValueError("output root must not contain the source checkout")


def trial_binding(trial_artifact, schedule_row, task_row):
    runtime = trial_artifact["runtime"]
    fingerprint_input = {
        "task": task_row,
        "manifest_hash": trial_artifact["manifest_hash"],
        "runtime": runtime,
        "budget": trial_artifact["budget"],
        "sample_index": trial_artifact["sample_index"],
        "trial_location_hash": trial_artifact["trial_location_hash"],
    }
    if trial.canonical_hash(fingerprint_input) != trial_artifact["trial_fingerprint"]:
        raise ValueError("trial artifact fingerprint cannot be replayed")
    return {
        "task_id": schedule_row["task_id"],
        "arm_id": schedule_row["arm_id"],
        "sample_index": schedule_row["sample_index"],
        "run_order": schedule_row["run_order"],
        "task_hash": trial_artifact["task"]["task_hash"],
        "manifest_hash": trial_artifact["manifest_hash"],
        "runtime_hash": trial.canonical_hash(runtime),
        "runner_hash": runtime["runner_hash"],
        "experiment_plan_hash": runtime["experiment_plan_hash"],
        "trial_fingerprint": trial_artifact["trial_fingerprint"],
        "task_reference": trial_artifact["task"],
        "runtime": runtime,
        "fingerprint_input": fingerprint_input,
    }


def synthetic_record(
    task_row,
    manifest_diff_valid,
    isolation,
    trial_dir,
    schedule_row,
):
    events = load_jsonl(trial_dir / "events.jsonl")
    outcome_path = trial_dir / "outcome" / "result.json"
    outcome = trial.load_private_json(outcome_path) if outcome_path.exists() else None
    trial_artifact = trial.load_private_json(trial_dir / "trial.json")
    event_contract_ok = bool(events) and all(
        event.get("event_contract") == "synthetic-skill-events-v1"
        and isinstance(event.get("skills_invoked"), list)
        for event in events
    )
    outcome_contract_ok = (
        isinstance(outcome, dict)
        and outcome.get("fixture") is True
        and outcome.get("task_id") == task_row["task_id"]
        and outcome.get("sample_index") == trial_artifact.get("sample_index")
        and isinstance(outcome.get("judge_payload"), dict)
    )
    file_isolation_failed = isolation["file_access_status"] != "ok"
    memory_isolation_failed = isolation["memory_isolation_status"] != "ok"
    return {
        **trial_binding(trial_artifact, schedule_row, task_row),
        "task_family": task_row["task_family"],
        "runner_completed": (
            trial_artifact.get("status") == "completed"
            and event_contract_ok
            and outcome_contract_ok
        ),
        "manifest_diff_valid": manifest_diff_valid,
        # Manifest residuals are evaluated directly from frozen manifests.
        # This synthetic runner has no independent host observation.
        "off_ccl_residual": None,
        "skill_events_verifiable": None,
        "skill_event_shape": "synthetic-skill-events-v1",
        "synthetic_skill_event_contract_ok": event_contract_ok,
        "synthetic_outcome_contract_ok": outcome_contract_ok,
        # This runner writes its own events. It may exercise the event shape,
        # but only a provider/host audit may claim matched-call compliance.
        "matched_call_compliant": None,
        "blinding_leak": None,
        "deterministic_replay_match": None,
        "contaminated": (
            True if file_isolation_failed or memory_isolation_failed else None
        ),
        "budget_complete": None,
        "access_audit_ok": False if file_isolation_failed else None,
        "memory_isolation_ok": False if memory_isolation_failed else None,
        "synthetic_isolation_contract_status": isolation["status"],
        "evidence_source": "synthetic_runner",
    }


def run_smoke(fixture_path: Path, output_root: Path, gate_path: Path) -> int:
    output_root = validated_output_root(output_root)
    trial.ensure_private_directory(output_root)
    if output_root.is_symlink() or output_root.resolve(strict=True) != output_root:
        raise ValueError("output root changed after validation")
    result_path = output_root / "smoke-result.json"
    trial.archive_private_file(result_path, output_root / "history", "smoke-result")
    runner_hash = current_runner_hash()
    fixture = load_json(fixture_path)
    gates = load_json(gate_path)
    # The committed E10 smoke fixture is the original S0/S1/S2 skill-content
    # contract.  The real pilot may select the paired-profile advisory tier,
    # but that must not silently reinterpret this causal synthetic fixture.
    committed_evidence_tier = gates.pop("evidence_tier", None)
    if fixture.get("schema_version") != 1:
        raise ValueError("smoke fixture schema_version must be 1")
    if fixture.get("live_model_calls") is not False:
        raise ValueError("the committed smoke fixture must disable live model calls")

    tasks = fixture.get("tasks")
    if not isinstance(tasks, list) or not tasks:
        raise ValueError("smoke fixture needs tasks")
    for task_row in tasks:
        errors = trial.validate_task_record(task_row, committed=True)
        if errors:
            raise ValueError(f"invalid smoke task {task_row.get('task_id')}: {errors}")

    frozen_arms = []
    preregistered_templates = {}
    for arm_row in fixture.get("arms", []):
        if set(arm_row) != {"template_ref", "components"}:
            raise ValueError("smoke arm rows allow only template_ref and components")
        template = load_preregistered_template(arm_row["template_ref"])
        frozen = trial.freeze_arm_manifest(template, arm_row["components"])
        frozen_arms.append(frozen)
        preregistered_templates[frozen["arm_id"]] = load_preregistered_template(
            arm_row["template_ref"]
        )
    if not frozen_arms:
        raise ValueError("smoke fixture needs arm manifests")
    by_id = {arm["arm_id"]: arm for arm in frozen_arms}
    if len(by_id) != len(frozen_arms):
        raise ValueError("duplicate arm_id in smoke fixture")
    off_arms = [arm for arm in frozen_arms if arm["treatment"] == "off"]
    if len(off_arms) != 1:
        raise ValueError("synthetic smoke requires exactly one OFF arm")
    off = off_arms[0]
    experiment_plan_hash = trial.canonical_hash(
        {
            "fixture": fixture,
            "gates": gates,
            "preregistered_templates": preregistered_templates,
        }
    )
    manifest_errors = {
        off["arm_id"]: trial.validate_manifest_preregistration(
            off, preregistered_templates[off["arm_id"]]
        ),
    }
    manifest_errors.update(
        {
            arm["arm_id"]: trial.compare_arm_to_off(
                off,
                arm,
                preregistered_templates[off["arm_id"]],
                preregistered_templates[arm["arm_id"]],
            )
            for arm in frozen_arms
            if arm is not off
        }
    )

    samples = fixture.get("samples")
    seed = fixture.get("seed")
    if not isinstance(samples, int) or not isinstance(seed, int):
        raise ValueError("smoke samples and seed must be integers")
    schedule = trial.build_schedule(tasks, list(by_id), samples=samples, seed=seed)
    task_by_id = {task_row["task_id"]: task_row for task_row in tasks}
    records = []
    planned_trials = []
    trial_root = output_root / "trials"
    checkout_root = output_root / "task-checkouts"
    trial.ensure_private_directory(trial_root)
    trial.ensure_private_directory(checkout_root)

    for row in schedule:
        task_row = task_by_id[row["task_id"]]
        arm = by_id[row["arm_id"]]
        sample_index = row["sample_index"]
        checkout = (
            checkout_root
            / row["task_id"]
            / row["arm_id"]
            / f"sample-{sample_index:03d}"
        )
        trial.ensure_private_directory(checkout, checkout_root)
        # Controller setup happens before the tested-agent access-audit window.
        trial.write_json_atomic(
            checkout / "task.json", trial.task_artifact_reference(task_row)
        )
        runtime = {
            "provider": "fixture",
            "model": "deterministic-no-model-call",
            "session_id": (
                f"fresh-{row['task_id']}-{row['arm_id']}-{sample_index:03d}"
            ),
            "isolation_config_hash": trial.canonical_hash(
                fixture["isolation_evidence"]
            ),
            "runner_hash": runner_hash,
            "experiment_plan_hash": experiment_plan_hash,
        }
        planned_trial_dir = (
            trial_root / row["task_id"] / row["arm_id"] / f"sample-{sample_index:03d}"
        )
        prepared = trial.prepare_trial(
            trial_root,
            task_row,
            arm,
            runtime,
            gates["budgets"],
            sample_index=sample_index,
            expected_isolation_evidence=fixture["isolation_evidence"],
            expected_read_allow_roots=[checkout],
            expected_write_allow_roots=[planned_trial_dir / "outcome"],
        )
        trial_dir = Path(prepared["trial_dir"])
        planned_trial_artifact = trial.load_private_json(trial_dir / "trial.json")
        planned_trials.append(trial_binding(planned_trial_artifact, row, task_row))
        intended_access_events = [
            {
                "actor": "tested-agent",
                "operation": "read",
                "path": str(checkout / "task.json"),
            },
            {
                "actor": "tested-agent",
                "operation": "write",
                "path": str(trial_dir / "outcome" / "result.json"),
            },
        ]
        extra_access_events = fixture.get("synthetic_extra_access_events", [])
        if not isinstance(extra_access_events, list):
            raise ValueError("synthetic_extra_access_events must be a list")
        intended_access_events.extend(extra_access_events)
        persisted_access_events = load_jsonl(trial_dir / "access-audit.jsonl")
        persisted_skill_events = load_jsonl(trial_dir / "events.jsonl")
        if prepared["mode"] == "complete":
            access_events = persisted_access_events
        else:
            access_events = list(persisted_access_events)
            for event in intended_access_events:
                if event not in access_events:
                    access_events.append(event)
        isolation = trial.assess_isolation(
            fixture["isolation_evidence"],
            access_events,
            [checkout],
            [trial_dir / "outcome"],
            forbidden_write_paths=[
                trial_dir / "trial.json",
                trial_dir / "events.jsonl",
                trial_dir / "access-audit.jsonl",
            ],
        )
        invoked = []
        if arm["treatment"] == "oracle":
            invoked = task_row["expected_owners"]
        elif arm["treatment"] == "full":
            invoked = task_row["expected_owners"]
        if prepared["mode"] != "complete":
            trial.write_jsonl_atomic(trial_dir / "access-audit.jsonl", access_events)
            skill_events = list(persisted_skill_events)
            synthetic_skill_event = {
                "event_contract": "synthetic-skill-events-v1",
                "skills_invoked": invoked,
            }
            if isolation["status"] == "ok":
                if synthetic_skill_event not in skill_events:
                    skill_events.append(synthetic_skill_event)
                trial.write_jsonl_atomic(
                    trial_dir / "events.jsonl",
                    skill_events,
                )
                outcome_payload = {
                    "fixture": True,
                    "task_id": row["task_id"],
                    "sample_index": sample_index,
                    "judge_payload": {"answer": "synthetic deterministic outcome"},
                }
                trial.write_json_atomic(
                    trial_dir / "outcome" / "result.json", outcome_payload
                )
                trial.checkpoint_trial(
                    trial_dir,
                    status="completed",
                    isolation_evidence=fixture["isolation_evidence"],
                    read_allow_roots=[checkout],
                    write_allow_roots=[trial_dir / "outcome"],
                    expected_state_version=prepared["state_version"],
                )
            else:
                trial.checkpoint_trial(
                    trial_dir,
                    status="contaminated",
                    stop_reason="trial_isolation_failed",
                    expected_state_version=prepared["state_version"],
                )
        manifest_ok = not manifest_errors.get(arm["arm_id"], [])
        records.append(
            synthetic_record(
                task_row,
                manifest_ok,
                isolation,
                trial_dir,
                row,
            )
        )

    capability_contract = trial.assess_capability_matrix(fixture["capability_matrix"])
    capability_matrix = dict(capability_contract)
    capability_matrix["synthetic_contract_status"] = capability_contract["status"]
    capability_matrix["status"] = "not_evaluated_synthetic"
    capability_matrix["causal_task_families"] = []
    capability_matrix["conclusion_boundary"] = "shadow_noncausal_only"
    pilot_gate = trial.evaluate_pilot_gate(
        records,
        fixture["calibration"],
        gates,
        expected_tasks={
            task_id: task_row["task_family"] for task_id, task_row in task_by_id.items()
        },
        expected_manifests=by_id,
        expected_trials=planned_trials,
        synthetic=True,
    )
    pilot_gate["not_evaluated_checks"].append("provider_capability_matrix")
    pilot_gate["not_evaluated_checks"] = list(
        dict.fromkeys(pilot_gate["not_evaluated_checks"])
    )
    if committed_evidence_tier is not None:
        pilot_gate["evidence_tier_overridden_from"] = committed_evidence_tier
    if pilot_gate["failures"]:
        pilot_gate["status"] = "fail"
    execution_status = (
        "completed"
        if records and all(record["runner_completed"] is True for record in records)
        else "incomplete"
    )
    result = {
        "schema_version": 1,
        "fixture": str(fixture_path),
        "enforcement": "advisory",
        "live_model_calls": False,
        "manifest_hashes": {arm["arm_id"]: arm["manifest_hash"] for arm in frozen_arms},
        "manifest_errors": manifest_errors,
        "runner_hash": runner_hash,
        "experiment_plan_hash": experiment_plan_hash,
        "schedule_count": len(schedule),
        "capability_matrix": capability_matrix,
        "pilot_gate": pilot_gate,
        "execution_status": execution_status,
        "conclusion_boundary": "runner_validity_not_skill_effectiveness",
    }
    trial.write_json_atomic(result_path, result)
    print(f"execution_status={execution_status}")
    print(f"pilot_gate_status={pilot_gate['status']}")
    print(f"trials={len(schedule)} live_model_calls=false enforcement=advisory")
    print(f"result={result_path}")
    if execution_status != "completed":
        return 1
    if pilot_gate["status"] == "not_evaluated_synthetic":
        return 3
    if pilot_gate["status"] == "fail":
        return 1
    raise ValueError("synthetic smoke produced an invalid pilot gate status")


def run_provider_probe(
    provider: str,
    codex_path: Path,
    model: str,
    task_family: str,
    output_root: Path,
    timeout_seconds: int,
) -> int:
    output_root = validated_output_root(output_root)
    if provider != "codex":
        raise ValueError("unsupported provider probe")
    report = provider_probe.run_codex_probe(
        codex_path=codex_path,
        model=model,
        task_family=task_family,
        output_root=output_root,
        timeout_seconds=timeout_seconds,
    )
    print(f"execution_status={report['execution_status']}")
    print(f"capability_matrix_status={report['capability_matrix']['status']}")
    print(f"isolation_outcome={report['isolation_outcome']}")
    print(
        "cross_session_recall_detected="
        f"{str(report['cross_trial_canary']['cross_session_recall_detected']).lower()}"
    )
    print(f"result={output_root / 'provider-probe-result.json'}")
    return 0


def run_reviewer_calibration(
    provider: str,
    codex_path: Path | None,
    claude_path: Path | None,
    opencode_path: Path | None,
    kimi_path: Path | None,
    model: str,
    reviewer_family: str,
    repeats: int,
    output_root: Path,
    timeout_seconds: int,
) -> int:
    output_root = validated_output_root(output_root)
    if provider == "codex":
        if (
            codex_path is None
            or claude_path is not None
            or opencode_path is not None
            or kimi_path is not None
        ):
            raise ValueError("Codex calibration requires only --codex-path")
        report = reviewer_calibration.run_codex_reviewer_calibration(
            codex_path=codex_path,
            model=model,
            reviewer_family=reviewer_family,
            repeats=repeats,
            output_root=output_root,
            timeout_seconds=timeout_seconds,
            known_answers_path=DEFAULT_CALIBRATION_ANSWERS,
            cases_path=DEFAULT_CALIBRATION_CASES,
            pilot_gates_path=DEFAULT_PILOT_GATES,
        )
    elif provider == "claude":
        if (
            claude_path is None
            or codex_path is not None
            or opencode_path is not None
            or kimi_path is not None
        ):
            raise ValueError("Claude calibration requires only --claude-path")
        report = reviewer_calibration.run_claude_reviewer_calibration(
            claude_path=claude_path,
            runtime_validator_path=DEFAULT_CLAUDE_RUNTIME_VALIDATOR,
            model=model,
            reviewer_family=reviewer_family,
            repeats=repeats,
            output_root=output_root,
            timeout_seconds=timeout_seconds,
            known_answers_path=DEFAULT_CALIBRATION_ANSWERS,
            cases_path=DEFAULT_CALIBRATION_CASES,
            pilot_gates_path=DEFAULT_PILOT_GATES,
        )
    elif provider == "opencode":
        if (
            opencode_path is None
            or codex_path is not None
            or claude_path is not None
            or kimi_path is not None
        ):
            raise ValueError("OpenCode calibration requires only --opencode-path")
        report = reviewer_calibration.run_opencode_reviewer_calibration(
            opencode_path=opencode_path,
            model=model,
            reviewer_family=reviewer_family,
            repeats=repeats,
            output_root=output_root,
            timeout_seconds=timeout_seconds,
            known_answers_path=DEFAULT_CALIBRATION_ANSWERS,
            cases_path=DEFAULT_CALIBRATION_CASES,
            pilot_gates_path=DEFAULT_PILOT_GATES,
        )
    elif provider == "kimi":
        if (
            kimi_path is None
            or codex_path is not None
            or claude_path is not None
            or opencode_path is not None
        ):
            raise ValueError("Kimi calibration requires only --kimi-path")
        report = reviewer_calibration.run_kimi_reviewer_calibration(
            kimi_path=kimi_path,
            model=model,
            reviewer_family=reviewer_family,
            repeats=repeats,
            output_root=output_root,
            timeout_seconds=timeout_seconds,
            known_answers_path=DEFAULT_CALIBRATION_ANSWERS,
            cases_path=DEFAULT_CALIBRATION_CASES,
            pilot_gates_path=DEFAULT_PILOT_GATES,
        )
    else:
        raise ValueError("unsupported reviewer calibration provider")
    print(f"execution_status={report['execution_status']}")
    print(f"calibration_status={report['calibration_status']}")
    print(f"reviewer_family={report['reviewer_family']}")
    print(f"repeat_count={report['repeat_count']}")
    print(f"result={output_root / 'reviewer-calibration-result.json'}")
    return 0 if report["calibration_status"] == "pass" else 1


def run_active_control_prepare(
    brief_path: Path,
    rubric_path: Path,
    constraints_path: Path,
    owner_reference_path: Path,
    candidate_paths: list[Path],
    output_root: Path,
) -> int:
    """Freeze one controller-private blinded selection request."""

    output_root = validated_output_root(output_root)
    opaque_order: list[str] = []
    while len(opaque_order) < 2:
        opaque_id = f"slot-{secrets.token_hex(8)}"
        if opaque_id not in opaque_order:
            opaque_order.append(opaque_id)
    selector_input = active_control.prepare_active_control(
        output_root=output_root,
        brief=load_json(brief_path),
        rubric=load_json(rubric_path),
        constraint_spec=load_json(constraints_path),
        owner_reference=load_external_private_json(
            owner_reference_path, "owner reference"
        ),
        candidate_packages=[
            load_external_private_json(path, "active-control candidate")
            for path in candidate_paths
        ],
        opaque_order=opaque_order,
    )
    print("execution_status=prepared")
    print(f"selector_input_hash={selector_input['selector_input_hash']}")
    print(f"selector_input={output_root / 'selector-input.json'}")
    return 0


def run_active_control_freeze_owner_reference(
    subagent_path: Path, main_path: Path, output_path: Path
) -> int:
    """Freeze two private Oracle scope files into one sealed reference."""

    reference = active_control.freeze_owner_reference(
        scope_contents={
            "subagent": load_external_private_text(
                subagent_path, "subagent owner content"
            ),
            "main": load_external_private_text(main_path, "main owner content"),
        }
    )
    output_path = trial._external_private_path(output_path, "owner reference")
    active_control._write_json_exclusive(
        output_path, reference, "owner reference"
    )
    print("execution_status=owner-reference-frozen")
    print(f"reference_hash={reference['reference_hash']}")
    print(f"owner_reference={output_path}")
    return 0


def run_active_control_finalize(
    output_root: Path, decision_path: Path
) -> int:
    """Bind one blind selector decision into the one-shot selection artifact."""

    output_root = validated_output_root(output_root)
    selection = active_control.finalize_active_control(
        output_root,
        load_external_private_json(decision_path, "active-control decision"),
    )
    print("execution_status=finalized")
    print(f"artifact_hash={selection['artifact_hash']}")
    print(f"selection={output_root / 'active-control-selection.json'}")
    return 0


def run_active_control_verify(selection_path: Path) -> int:
    """Strictly read back one sealed active-control selection."""

    selection = active_control.load_active_control_selection(selection_path)
    print("verification_status=valid")
    print(f"artifact_hash={selection['artifact_hash']}")
    print(f"selected_package_hash={selection['selected_package_hash']}")
    return 0


def run_active_control_measure(output_root: Path, owner_reference_path: Path) -> int:
    """Publish one deterministic owner-relative measurement."""

    output_root = validated_output_root(output_root)
    measurement = active_control.measure_owner_relative(
        output_root,
        load_external_private_json(owner_reference_path, "owner reference"),
    )
    print(f"execution_status=measured-{measurement['status']}")
    print(f"measurement_hash={measurement['measurement_hash']}")
    print(f"measurement={output_root / 'owner-relative-measurement.json'}")
    return 0 if measurement["status"] == "pass" else 1


def run_active_control_measure_verify(
    selection_path: Path, owner_reference_path: Path, measurement_path: Path
) -> int:
    """Strictly verify one owner-relative artifact and both source bindings."""

    measurement = active_control.load_owner_relative_measurement(
        measurement_path,
        selection=active_control.load_active_control_selection(selection_path),
        owner_reference=load_external_private_json(
            owner_reference_path, "owner reference"
        ),
    )
    print("verification_status=valid")
    print(f"measurement_hash={measurement['measurement_hash']}")
    return 0


def run_active_control_matched_call(
    output_root: Path,
    selection_path: Path,
    measurement_path: Path,
    owner_reference_path: Path,
    scope: str,
    active_bundle_id: str,
    oracle_bundle_id: str,
) -> int:
    """Publish paired deterministic matched-call contract evidence."""

    output_root = validated_output_root(output_root)
    selection = active_control.load_active_control_selection(selection_path)
    owner_reference = load_external_private_json(
        owner_reference_path, "owner reference"
    )
    measurement = active_control.load_owner_relative_measurement(
        measurement_path,
        selection=selection,
        owner_reference=owner_reference,
    )
    evidence = active_control.freeze_matched_call_evidence(
        output_root,
        selection=selection,
        measurement=measurement,
        owner_reference=owner_reference,
        scope=scope,
        active_bundle_id=active_bundle_id,
        oracle_bundle_id=oracle_bundle_id,
    )
    print("execution_status=matched-call-contract-declared-no-observation")
    print("artifact_write_status=created")
    print("matched_call_gate=NOT_SATISFIED")
    print(f"observation_status={evidence['observation_status']}")
    print(f"artifact_hash={evidence['artifact_hash']}")
    print(f"evidence={active_control.MATCHED_CALL_EVIDENCE_FILENAMES[scope]}")
    return 3


def run_active_control_matched_call_verify(
    selection_path: Path,
    measurement_path: Path,
    owner_reference_path: Path,
    evidence_path: Path,
) -> int:
    """Strictly verify paired matched-call evidence and source bindings."""

    selection = active_control.load_active_control_selection(selection_path)
    owner_reference = load_external_private_json(
        owner_reference_path, "owner reference"
    )
    measurement = active_control.load_owner_relative_measurement(
        measurement_path,
        selection=selection,
        owner_reference=owner_reference,
    )
    evidence = active_control.load_matched_call_evidence(
        evidence_path,
        selection=selection,
        measurement=measurement,
        owner_reference=owner_reference,
    )
    print("verification_status=fixture-contract-valid-no-observation")
    print("artifact_write_status=not-applicable-read-only")
    print("matched_call_gate=NOT_SATISFIED")
    print(f"observation_status={evidence['observation_status']}")
    print(f"artifact_hash={evidence['artifact_hash']}")
    return 4


def main(argv=None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    subparsers = parser.add_subparsers(dest="command", required=True)
    smoke = subparsers.add_parser("smoke", help="run synthetic E10 foundation smoke")
    smoke.add_argument("--fixture", type=Path, required=True)
    smoke.add_argument("--out", type=Path, required=True)
    smoke.add_argument("--pilot-gates", type=Path, default=DEFAULT_PILOT_GATES)
    provider = subparsers.add_parser(
        "provider-probe", help="run a real provider capability canary"
    )
    provider.add_argument("--provider", choices=("codex",), required=True)
    provider.add_argument("--codex-path", type=Path, required=True)
    provider.add_argument("--model", required=True)
    provider.add_argument(
        "--task-family", choices=sorted(trial.TASK_FAMILIES), required=True
    )
    provider.add_argument("--out", type=Path, required=True)
    provider.add_argument("--timeout-seconds", type=int, default=220)
    reviewer = subparsers.add_parser(
        "reviewer-calibration",
        help="collect repeated raw judgments from a live reviewer family",
    )
    reviewer.add_argument(
        "--provider",
        choices=("codex", "claude", "opencode", "kimi"),
        required=True,
    )
    reviewer.add_argument("--codex-path", type=Path)
    reviewer.add_argument("--claude-path", type=Path)
    reviewer.add_argument("--opencode-path", type=Path)
    reviewer.add_argument("--kimi-path", type=Path)
    reviewer.add_argument("--model", required=True)
    reviewer.add_argument("--reviewer-family", required=True)
    reviewer.add_argument("--repeats", type=int, default=2)
    reviewer.add_argument("--out", type=Path, required=True)
    reviewer.add_argument("--timeout-seconds", type=int, default=220)
    active_prepare = subparsers.add_parser(
        "active-control-prepare",
        help="freeze a private blinded active-control selector packet",
    )
    active_prepare.add_argument("--brief", type=Path, required=True)
    active_prepare.add_argument("--rubric", type=Path, required=True)
    active_prepare.add_argument("--constraints", type=Path, required=True)
    active_prepare.add_argument("--owner-reference", type=Path, required=True)
    active_prepare.add_argument(
        "--candidate", type=Path, action="append", required=True
    )
    active_prepare.add_argument("--out", type=Path, required=True)
    owner_reference = subparsers.add_parser(
        "active-control-freeze-owner-reference",
        help="freeze two private Oracle scope files before active-control selection",
    )
    owner_reference.add_argument("--subagent", type=Path, required=True)
    owner_reference.add_argument("--main", type=Path, required=True)
    owner_reference.add_argument("--out", type=Path, required=True)
    active_finalize = subparsers.add_parser(
        "active-control-finalize",
        help="seal one blind selector decision into an active-control selection",
    )
    active_finalize.add_argument("--out", type=Path, required=True)
    active_finalize.add_argument("--decision", type=Path, required=True)
    active_verify = subparsers.add_parser(
        "active-control-verify",
        help="strictly read back a sealed active-control selection",
    )
    active_verify.add_argument("--selection", type=Path, required=True)
    active_measure = subparsers.add_parser(
        "active-control-measure",
        help="measure a sealed selection against a private owner reference",
    )
    active_measure.add_argument("--out", type=Path, required=True)
    active_measure.add_argument("--owner-reference", type=Path, required=True)
    active_measure_verify = subparsers.add_parser(
        "active-control-measure-verify",
        help="verify owner-relative measurement and source bindings",
    )
    active_measure_verify.add_argument("--selection", type=Path, required=True)
    active_measure_verify.add_argument(
        "--owner-reference", type=Path, required=True
    )
    active_measure_verify.add_argument("--measurement", type=Path, required=True)
    active_matched_call = subparsers.add_parser(
        "active-control-matched-call",
        help="freeze a paired deterministic matched-call contract artifact",
    )
    active_matched_call.add_argument("--out", type=Path, required=True)
    active_matched_call.add_argument("--selection", type=Path, required=True)
    active_matched_call.add_argument("--measurement", type=Path, required=True)
    active_matched_call.add_argument(
        "--owner-reference", type=Path, required=True
    )
    active_matched_call.add_argument(
        "--scope", choices=active_control.SCOPES, required=True
    )
    active_matched_call.add_argument("--active-bundle-id", required=True)
    active_matched_call.add_argument("--oracle-bundle-id", required=True)
    active_matched_call_verify = subparsers.add_parser(
        "active-control-matched-call-verify",
        help="verify matched-call evidence and all source bindings",
    )
    active_matched_call_verify.add_argument(
        "--selection", type=Path, required=True
    )
    active_matched_call_verify.add_argument(
        "--measurement", type=Path, required=True
    )
    active_matched_call_verify.add_argument(
        "--owner-reference", type=Path, required=True
    )
    active_matched_call_verify.add_argument(
        "--evidence", type=Path, required=True
    )
    args = parser.parse_args(argv)
    try:
        if args.command == "smoke":
            return run_smoke(args.fixture, args.out, args.pilot_gates)
        if args.command == "provider-probe":
            return run_provider_probe(
                args.provider,
                args.codex_path,
                args.model,
                args.task_family,
                args.out,
                args.timeout_seconds,
            )
        if args.command == "reviewer-calibration":
            return run_reviewer_calibration(
                args.provider,
                args.codex_path,
                args.claude_path,
                args.opencode_path,
                args.kimi_path,
                args.model,
                args.reviewer_family,
                args.repeats,
                args.out,
                args.timeout_seconds,
            )
        if args.command == "active-control-prepare":
            return run_active_control_prepare(
                args.brief,
                args.rubric,
                args.constraints,
                args.owner_reference,
                args.candidate,
                args.out,
            )
        if args.command == "active-control-freeze-owner-reference":
            return run_active_control_freeze_owner_reference(
                args.subagent, args.main, args.out
            )
        if args.command == "active-control-finalize":
            return run_active_control_finalize(args.out, args.decision)
        if args.command == "active-control-verify":
            return run_active_control_verify(args.selection)
        if args.command == "active-control-measure":
            return run_active_control_measure(args.out, args.owner_reference)
        if args.command == "active-control-measure-verify":
            return run_active_control_measure_verify(
                args.selection, args.owner_reference, args.measurement
            )
        if args.command == "active-control-matched-call":
            return run_active_control_matched_call(
                args.out,
                args.selection,
                args.measurement,
                args.owner_reference,
                args.scope,
                args.active_bundle_id,
                args.oracle_bundle_id,
            )
        if args.command == "active-control-matched-call-verify":
            return run_active_control_matched_call_verify(
                args.selection,
                args.measurement,
                args.owner_reference,
                args.evidence,
            )
    except (OSError, ValueError, KeyError, json.JSONDecodeError) as exc:
        message = str(exc)
        if getattr(args, "command", None) in MATCHED_CALL_COMMANDS:
            message = _redact_matched_call_error(message, args)
            print("matched_call_gate=NOT_SATISFIED")
        print(f"skill_effectiveness_trial: {message}", file=sys.stderr)
        return 2
    except Exception as exc:
        if getattr(args, "command", None) not in MATCHED_CALL_COMMANDS:
            raise
        message = _redact_matched_call_error(str(exc), args)
        print("matched_call_gate=NOT_SATISFIED")
        print(f"skill_effectiveness_trial: {message}", file=sys.stderr)
        return 2
    return 2


if __name__ == "__main__":
    raise SystemExit(main())
