#!/usr/bin/env bash
# Regression for receipt-bound extraction review terminal-state validation.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd -P)"
VALIDATOR="$SCRIPT_DIR/validate_extraction_review_state.py"
[ -f "$VALIDATOR" ] || { echo "FAIL: validator not found: $VALIDATOR" >&2; exit 1; }

TMP="$(mktemp -d "${TMPDIR:-/tmp}/extraction-review-state.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

python3 - "$VALIDATOR" "$TMP" <<'PY'
import copy
import hashlib
import json
import os
import subprocess
import sys
from pathlib import Path

validator = Path(sys.argv[1])
root = Path(sys.argv[2])
A, B, C = (character * 40 for character in "abc")
CANDIDATE = "d" * 64
OTHER_CANDIDATE = "e" * 64
CLOSED_DISPOSITIONS = {
    "fixed",
    "source_refuted",
    "accepted_tradeoff",
    "pre_existing_out_of_scope",
}


def canonical_hash(value):
    encoded = json.dumps(
        value, ensure_ascii=False, sort_keys=True, separators=(",", ":")
    ).encode()
    return hashlib.sha256(encoded).hexdigest()


def write_json(name, payload):
    encoded = (json.dumps(payload, ensure_ascii=False, indent=2) + "\n").encode()
    (root / name).write_bytes(encoded)
    return hashlib.sha256(encoded).hexdigest()


def encode_duplicate_key(payload, field, first_value):
    pairs = []
    for key, value in payload.items():
        if key == field:
            pairs.append((key, first_value))
        pairs.append((key, value))
    return (
        "{"
        + ",".join(
            f"{json.dumps(key)}:{json.dumps(value, ensure_ascii=False)}"
            for key, value in pairs
        )
        + "}\n"
    ).encode()


def write_duplicate_json(name, payload, field, first_value):
    encoded = encode_duplicate_key(payload, field, first_value)
    (root / name).write_bytes(encoded)
    return hashlib.sha256(encoded).hexdigest()


def write_base_evidence(name, base_sha, ref="refs/heads/dev"):
    encoded = f"{base_sha}\t{ref}\n".encode()
    (root / name).write_bytes(encoded)
    return hashlib.sha256(encoded).hexdigest()


def occurrence_ref(occurrence):
    return {
        "receipt_sha256": occurrence["receipt_sha256"],
        "finding_sha256": occurrence["finding_sha256"],
    }


def bind_disposition_evidence(name, occurrence, *, resolves=None, evidence=None):
    if resolves is None:
        resolves = [occurrence_ref(occurrence)]
    if evidence is None:
        evidence = [
            f"synthetic {occurrence['disposition']} evidence for the current candidate"
        ]
    payload = {
        "schema_version": 1,
        "candidate_sha256": CANDIDATE,
        "receipt_sha256": occurrence["receipt_sha256"],
        "finding_sha256": occurrence["finding_sha256"],
        "disposition": occurrence["disposition"],
        "resolves_occurrences": copy.deepcopy(resolves),
        "evidence": list(evidence),
    }
    evidence_hash = write_json(name, payload)
    occurrence.update(
        disposition_evidence_file=name,
        disposition_evidence_sha256=evidence_hash,
    )
    return payload


def clear_disposition_evidence(occurrence):
    occurrence.pop("disposition_evidence_file", None)
    occurrence.pop("disposition_evidence_sha256", None)


def mutate_disposition_evidence(occurrence, mutator):
    evidence_path = root / occurrence["disposition_evidence_file"]
    payload = json.loads(evidence_path.read_text(encoding="utf-8"))
    mutator(payload)
    occurrence["disposition_evidence_sha256"] = write_json(
        occurrence["disposition_evidence_file"], payload
    )


def duplicate_disposition_evidence_key(occurrence, field, first_value):
    evidence_path = root / occurrence["disposition_evidence_file"]
    payload = json.loads(evidence_path.read_text(encoding="utf-8"))
    encoded = encode_duplicate_key(payload, field, first_value)
    evidence_path.write_bytes(encoded)
    occurrence["disposition_evidence_sha256"] = hashlib.sha256(encoded).hexdigest()


def finding(number):
    return {
        "severity": "P1",
        "title": f"receipt-bound finding {number}",
        "body": f"failure path {number}",
    }


def make_fixture(
    name,
    *,
    receipt_findings=None,
    receipt_mutators=None,
    completion=True,
    completion_mutator=None,
    budget=1,
    base_shas=None,
    closeout=None,
    unmatched=0,
    open_last=False,
    succession=False,
):
    if receipt_findings is None:
        receipt_findings = [[finding(1)], []]
    receipt_mutators = receipt_mutators or {}
    rounds = len(receipt_findings)
    scope = {
        "schema_version": 3,
        "intent_sha256": "1" * 64,
        "acceptance_sha256": "2" * 64,
        "stage": "release",
        "review_depth": "release",
        "risk_tags": ["shared-gate"],
        "challenge_budget": budget,
        "wording_only_proof_sha256": None,
        "wording_only_scope_sha256": None,
    }
    scope_sha = canonical_hash(scope)
    receipts = []
    receipt_hashes = []
    receipt_refs = []
    for index, findings in enumerate(receipt_findings, start=1):
        # With a succession the LAST round opens a second chain: its own chain
        # arithmetic restarts at one while its lane position keeps counting.
        is_succession = succession and index == rounds
        chain_position = 1 if is_succession else index
        mode = "challenge" if is_succession else "review" if index == 1 else "challenge"
        status = "findings" if findings else "passed"
        remaining = 2 - chain_position
        if status == "findings":
            state = "post_review_budget" if chain_position == 2 else "findings_pending"
        else:
            state = "reviewed"
        receipt = {
            "schema_version": 3,
            "mode": mode,
            "status": status,
            "findings": copy.deepcopy(findings),
            "review_chain_tracked": True,
            "review_chain_id": (
                "extraction-succession" if is_succession else "extraction-chain"
            ),
            "autonomous_review_index": chain_position,
            "autonomous_review_budget": 2,
            "autonomous_reviews_remaining": remaining,
            "autonomous_review_allowed": remaining > 0,
            "challenge_index": 1 if is_succession else 0 if index == 1 else index - 1,
            "challenge_budget": budget,
            "prior_review_result_sha256": [] if is_succession else list(receipt_hashes),
            "predecessor_chain_id": "extraction-chain" if is_succession else None,
            "predecessor_result_sha256": (
                receipt_hashes[-1] if is_succession and receipt_hashes else None
            ),
            "predecessor_candidate_sha256": OTHER_CANDIDATE if is_succession else None,
            "candidate_sha256": (
                OTHER_CANDIDATE if succession and not is_succession else CANDIDATE
            ),
            "packet_sha256": (
                OTHER_CANDIDATE if succession and not is_succession else CANDIDATE
            ),
            "review_scope": copy.deepcopy(scope),
            "review_scope_sha256": scope_sha,
            "wording_only_proof_sha256": None,
            "wording_only_scope": None,
            "stage": "release",
            "review_depth": "release",
            "risk_tags": ["shared-gate"],
            "review_state": state,
            "human_decision_required": state == "post_review_budget",
        }
        mutator = receipt_mutators.get(index)
        if mutator is not None:
            mutator(receipt)
        receipt_name = f"{name}-round-{index}.json"
        receipt_hash = write_json(receipt_name, receipt)
        receipts.append(receipt)
        receipt_hashes.append(receipt_hash)
        receipt_refs.append(
            {"sequence": index, "file": receipt_name, "sha256": receipt_hash}
        )

    completion_ref = None
    if completion:
        final = receipts[-1]
        complete = {
            "schema_version": 3,
            "mode": "complete",
            "status": "passed",
            "findings": [],
            "review_chain_tracked": True,
            "review_chain_id": final["review_chain_id"],
            "autonomous_review_index": final["autonomous_review_index"],
            "autonomous_review_budget": 2,
            "autonomous_reviews_remaining": final["autonomous_reviews_remaining"],
            "autonomous_review_allowed": False,
            "challenge_budget": budget,
            "prior_review_result_sha256": copy.deepcopy(
                final["prior_review_result_sha256"]
            ),
            "candidate_sha256": final["candidate_sha256"],
            "packet_sha256": final["packet_sha256"],
            "review_scope": copy.deepcopy(final["review_scope"]),
            "review_scope_sha256": final["review_scope_sha256"],
            "wording_only_proof_sha256": None,
            "wording_only_scope": None,
            "stage": final["stage"],
            "review_depth": final["review_depth"],
            "risk_tags": copy.deepcopy(final["risk_tags"]),
            "review_state": "self_reviewed",
            "completion_gated": False,
            "completion_review_result_sha256": receipt_hashes[-1],
            "next_action": "complete",
        }
        if completion_mutator is not None:
            completion_mutator(complete)
        complete_name = f"{name}-complete.json"
        complete_hash = write_json(complete_name, complete)
        completion_ref = {"file": complete_name, "sha256": complete_hash}

    if base_shas is None:
        base_shas = [A] * rounds
    attestations = []
    for sequence, base_sha in enumerate(base_shas, start=1):
        evidence_name = f"{name}-base-{sequence}.txt"
        evidence_hash = write_base_evidence(evidence_name, base_sha)
        attestations.append(
            {
                "sequence": sequence,
                "remote": "origin",
                "ref": "refs/heads/dev",
                "sha": base_sha,
                "confirmed_at": f"2026-08-29T12:{sequence:02d}:00Z",
                "controller_receipt_sha256": (
                    receipt_hashes[sequence - 1] if sequence <= rounds else None
                ),
                "evidence_file": evidence_name,
                "evidence_sha256": evidence_hash,
            }
        )

    occurrences = []
    for receipt, receipt_hash in zip(receipts, receipt_hashes):
        for item in receipt["findings"]:
            occurrences.append(
                {
                    "receipt_sha256": receipt_hash,
                    "finding_sha256": canonical_hash(item),
                    "disposition": "fixed",
                }
            )
    if open_last and occurrences:
        occurrences[-1]["disposition"] = "open"
    for occurrence_index, occurrence in enumerate(occurrences, start=1):
        if occurrence["disposition"] in CLOSED_DISPOSITIONS:
            bind_disposition_evidence(
                f"{name}-disposition-{occurrence_index}.json",
                occurrence,
            )

    classes = []
    if occurrences:
        sweep = None
        if len(occurrences) >= 3:
            searched_set = [
                "skills/code-review",
                "skills/skill-extraction-workflow",
            ]
            unmatched_items = [f"unmatched-{index}" for index in range(unmatched)]
            manifest = {
                "schema_version": 1,
                "candidate_sha256": CANDIDATE,
                "searched_set": searched_set,
                "unmatched_instances": unmatched_items,
            }
            manifest_name = f"{name}-sweep.json"
            manifest_hash = write_json(manifest_name, manifest)
            sweep = {
                "candidate_sha256": CANDIDATE,
                "manifest_file": manifest_name,
                "manifest_sha256": manifest_hash,
                "searched_set": searched_set,
                "unmatched_instances": unmatched,
            }
        classes.append(
            {
                "key": "receipt-binding",
                "root_cause_predicate": "A closeout field is accepted without controller evidence.",
                "affected_surface": "extraction closeout ledger",
                "occurrences": occurrences,
                "authoritative_sweep": sweep,
            }
        )

    if closeout is None:
        closeout = (
            "ready_for_human_decision"
            if completion
            else "continuation_authorization_required"
        )
    controller_state = (
        "self_reviewed" if completion else receipts[-1]["review_state"]
    )
    ledger = {
        "schema_version": 3,
        "candidate_sha256": CANDIDATE,
        "controller_receipts": receipt_refs,
        "completion_receipt": completion_ref,
        "base_attestations": attestations,
        "autonomous_round": rounds,
        "controller_review_state": controller_state,
        "finding_classes": classes,
        "unreviewed_delta": [],
        "closeout_state": closeout,
    }
    return {
        "ledger": ledger,
        "receipts": receipts,
        "receipt_hashes": receipt_hashes,
    }


def invoke_encoded(name, encoded):
    path = root / f"{name}-ledger.json"
    path.write_bytes(encoded)
    try:
        return subprocess.run(
            [sys.executable, str(validator), str(path)],
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
            check=False,
            timeout=5,
        )
    except subprocess.TimeoutExpired as exc:
        raise AssertionError((name, "validator blocked", exc)) from exc


def invoke(name, payload):
    encoded = (json.dumps(payload, indent=2) + "\n").encode()
    return invoke_encoded(name, encoded)


def run(name, payload, expected_rc, token):
    result = invoke(name, payload)
    assert result.returncode == expected_rc, (name, result.returncode, result.stdout)
    assert token in result.stdout, (name, token, result.stdout)
    assert "Traceback" not in result.stdout, (name, result.stdout)


ready = make_fixture("ready")
run("ready", ready["ledger"], 0, "closeout_state=ready_for_human_decision")

schema_v3 = make_fixture("schema-v3")
schema_v3["ledger"]["schema_version"] = 3
legacy_v2 = make_fixture("legacy-v2")
legacy_v2["ledger"]["schema_version"] = 2
schema_results = [
    ("schema-v3", invoke("schema-v3", schema_v3["ledger"])),
    ("legacy-v2", invoke("legacy-v2", legacy_v2["ledger"])),
]
assert [
    (result.returncode, expected_token in result.stdout, "Traceback" in result.stdout)
    for (name, result), expected_token in zip(
        schema_results,
        ("closeout_state=ready_for_human_decision", "schema_version must be 3"),
        strict=True,
    )
] == [(0, True, False), (1, True, False)], [
    (name, result.returncode, result.stdout) for name, result in schema_results
]

bad_digest = make_fixture("bad-digest")
bad_digest["ledger"]["controller_receipts"][0]["sha256"] = "f" * 64
run("bad-digest", bad_digest["ledger"], 1, "digest does not match")

# JSON floats equal to the expected integers must not satisfy integer guards.
float_schema = make_fixture("float-schema")
float_schema["ledger"]["schema_version"] = 3.0
run("float-schema", float_schema["ledger"], 1, "schema_version must be 3")

float_budget = make_fixture(
    "float-budget",
    receipt_mutators={2: lambda row: row.update(challenge_budget=1.0)},
)
run("float-budget", float_budget["ledger"], 1, "challenge_budget must be 1")

nan_schema = make_fixture("nan-schema")
nan_schema["ledger"]["schema_version"] = float("nan")
run("nan-schema", nan_schema["ledger"], 1, "non-standard JSON constant")

control_chain = make_fixture(
    "control-chain",
    receipt_mutators={
        2: lambda row: row.update(review_chain_id="chain\x1b[31mred")
    },
)
run("control-chain", control_chain["ledger"], 1, "must not contain control characters")

# C1 controls and Unicode line/paragraph separators forge diagnostic line
# breaks just like C0 escapes; each must be rejected, not echoed.
for label, hostile in (
    ("c1-csi", "chain\x9bred"),
    ("c1-nel", "chain\x85red"),
    ("line-sep", "chain\u2028red"),
    ("para-sep", "chain\u2029red"),
):
    hostile_chain = make_fixture(
        f"hostile-{label}",
        receipt_mutators={2: lambda row, value=hostile: row.update(review_chain_id=value)},
    )
    run(
        f"hostile-{label}",
        hostile_chain["ledger"],
        1,
        "must not contain control characters",
    )

# A float completion schema_version must not satisfy the completion guard.
float_completion = make_fixture(
    "float-completion",
    completion_mutator=lambda row: row.update(schema_version=3.0),
)
run(
    "float-completion",
    float_completion["ledger"],
    1,
    "completion receipt must be a passed self_reviewed complete result",
)

wrong_chain = make_fixture(
    "wrong-chain",
    receipt_mutators={2: lambda row: row.update(review_chain_id="other-chain")},
)
run("wrong-chain", wrong_chain["ledger"], 1, "review_chain_id")

wrong_mode = make_fixture(
    "wrong-mode", receipt_mutators={2: lambda row: row.update(mode="review")}
)
run("wrong-mode", wrong_mode["ledger"], 1, "mode challenge")

wrong_prior = make_fixture(
    "wrong-prior",
    receipt_mutators={
        2: lambda row: row.update(prior_review_result_sha256=["f" * 64])
    },
)
run("wrong-prior", wrong_prior["ledger"], 1, "prior_review_result_sha256")

packet_mismatch = make_fixture(
    "packet-mismatch",
    receipt_mutators={2: lambda row: row.update(packet_sha256=OTHER_CANDIDATE)},
)
run("packet-mismatch", packet_mismatch["ledger"], 1, "packet_sha256 must equal candidate_sha256")

def drift_scope(row):
    row["review_scope"]["stage"] = "build"
    row["review_scope_sha256"] = canonical_hash(row["review_scope"])
    row["stage"] = "build"


scope_mismatch = make_fixture("scope-mismatch", receipt_mutators={2: drift_scope})
run("scope-mismatch", scope_mismatch["ledger"], 1, "review scope changed")

budget_four = make_fixture("budget-four", budget=4)
run("budget-four", budget_four["ledger"], 1, "challenge_budget must be 1")

review_only = make_fixture("review-only", receipt_findings=[[]])
run("review-only", review_only["ledger"], 1, "ready requires at least one tracked challenge")

# A caller must not out-run the wrapper budget by supplying extra receipts: a
# third receipt under budget 1 claims a negative remaining count and would
# otherwise reach completion validation as a ready-state budget bypass.
over_budget = make_fixture("over-budget", receipt_findings=[[], [], []])
run("over-budget", over_budget["ledger"], 1, "exceeds the wrapper budget")

# Chain succession. A fix that edits the reviewed owner package ends its chain, so
# the landing candidate can only be challenged in a succeeding chain. The lane then
# spans two chains and three rounds, and the succession round is the only one that
# binds what actually lands.
succession_ready = make_fixture(
    "succession-ready", receipt_findings=[[finding(1)], [], []], succession=True
)
run("succession-ready", succession_ready["ledger"], 0, "closeout_state=ready_for_human_decision")

# The failure this whole mechanism exists to make visible: the fix batch moved the
# candidate and no round ever inspected what lands.
succession_absent = make_fixture(
    "succession-absent",
    receipt_findings=[[finding(1)], []],
    receipt_mutators={
        1: lambda row: row.update(
            candidate_sha256=OTHER_CANDIDATE, packet_sha256=OTHER_CANDIDATE
        ),
        2: lambda row: row.update(
            candidate_sha256=OTHER_CANDIDATE, packet_sha256=OTHER_CANDIDATE
        ),
    },
)
run("succession-absent", succession_absent["ledger"], 1, "does not bind the ledger candidate")

# A succession whose predecessor saw the same candidate reviewed nothing new.
succession_unmoved = make_fixture(
    "succession-unmoved",
    receipt_findings=[[finding(1)], [], []],
    succession=True,
    receipt_mutators={
        1: lambda row: row.update(candidate_sha256=CANDIDATE, packet_sha256=CANDIDATE),
        2: lambda row: row.update(candidate_sha256=CANDIDATE, packet_sha256=CANDIDATE),
        3: lambda row: row.update(predecessor_candidate_sha256=CANDIDATE),
    },
)
run(
    "succession-unmoved",
    succession_unmoved["ledger"],
    1,
    "must bind a candidate the wrapper chain never saw",
)

succession_foreign_terminal = make_fixture(
    "succession-foreign-terminal",
    receipt_findings=[[finding(1)], [], []],
    succession=True,
    receipt_mutators={3: lambda row: row.update(predecessor_result_sha256="f" * 64)},
)
run(
    "succession-foreign-terminal",
    succession_foreign_terminal["ledger"],
    1,
    "does not bind the succeeded chain's terminal receipt",
)

succession_self = make_fixture(
    "succession-self",
    receipt_findings=[[finding(1)], [], []],
    succession=True,
    receipt_mutators={3: lambda row: row.update(review_chain_id="extraction-chain")},
)
run("succession-self", succession_self["ledger"], 1, "succeeds its own chain")

succession_misplaced = make_fixture(
    "succession-misplaced",
    receipt_findings=[[finding(1)], [], []],
    succession=True,
    receipt_mutators={
        2: lambda row: row.update(predecessor_chain_id="extraction-chain"),
    },
)
run(
    "succession-misplaced",
    succession_misplaced["ledger"],
    1,
    "must be the lane's final round",
)

succession_over_lane = make_fixture(
    "succession-over-lane",
    receipt_findings=[[finding(1)], [], [], []],
    succession=True,
)
run(
    "succession-over-lane",
    succession_over_lane["ledger"],
    1,
    "controller_receipts must contain one to 3 ordered Agent rounds",
)

missing_complete = make_fixture("missing-complete")
missing_complete["ledger"]["completion_receipt"] = None
run("missing-complete", missing_complete["ledger"], 1, "requires a completion receipt")

bad_complete_state = make_fixture(
    "bad-complete-state",
    completion_mutator=lambda row: row.update(review_state="reviewed"),
)
run("bad-complete-state", bad_complete_state["ledger"], 1, "passed self_reviewed")

bad_complete_hash = make_fixture(
    "bad-complete-hash",
    completion_mutator=lambda row: row.update(
        completion_review_result_sha256="f" * 64
    ),
)
run("bad-complete-hash", bad_complete_hash["ledger"], 1, "completion_review_result_sha256")

bad_complete_candidate = make_fixture(
    "bad-complete-candidate",
    completion_mutator=lambda row: row.update(
        candidate_sha256=OTHER_CANDIDATE, packet_sha256=OTHER_CANDIDATE
    ),
)
run("bad-complete-candidate", bad_complete_candidate["ledger"], 1, "exact final candidate")

bad_complete_remaining = make_fixture(
    "bad-complete-remaining",
    completion_mutator=lambda row: row.update(autonomous_reviews_remaining=2),
)
run(
    "bad-complete-remaining",
    bad_complete_remaining["ledger"],
    1,
    "autonomous_reviews_remaining",
)

continuation = make_fixture(
    "continuation",
    receipt_findings=[[finding(1)], [finding(2)]],
    completion=False,
    open_last=True,
)
run(
    "continuation",
    continuation["ledger"],
    0,
    "closeout_state=continuation_authorization_required",
)

continuation_unconsumed_first_drift = make_fixture(
    "continuation-unconsumed-first-drift",
    receipt_findings=[[finding(1)], [finding(2)]],
    completion=False,
    open_last=True,
    base_shas=[A, A, B],
)
run(
    "continuation-unconsumed-first-drift",
    continuation_unconsumed_first_drift["ledger"],
    1,
    "final controller receipt does not consume the latest attested base",
)

continuation_candidate = make_fixture(
    "continuation-candidate",
    receipt_findings=[[finding(1)], [finding(2)]],
    completion=False,
    open_last=True,
)
continuation_candidate["ledger"]["candidate_sha256"] = OTHER_CANDIDATE
run(
    "continuation-candidate",
    continuation_candidate["ledger"],
    1,
    "controller receipt 1 does not bind the ledger candidate",
)

# A chain whose FIRST round reviewed a different candidate must not close out
# a ledger for the final candidate, even when the final round binds it.
drifted_round = make_fixture(
    "drifted-round-candidate",
    receipt_mutators={
        1: lambda row: row.update(
            candidate_sha256=OTHER_CANDIDATE, packet_sha256=OTHER_CANDIDATE
        )
    },
)
run(
    "drifted-round-candidate",
    drifted_round["ledger"],
    1,
    "controller receipt 1 does not bind the ledger candidate",
)

unknown_state = make_fixture(
    "unknown-state",
    receipt_findings=[[finding(1)], [finding(2)]],
    receipt_mutators={2: lambda row: row.update(review_state="potato")},
    completion=False,
    open_last=True,
)
unknown_state["ledger"]["controller_review_state"] = "potato"
run("unknown-state", unknown_state["ledger"], 1, "unknown controller review_state")

passed_continuation = make_fixture(
    "passed-continuation",
    receipt_findings=[[finding(1)], []],
    completion=False,
)
run("passed-continuation", passed_continuation["ledger"], 1, "findings in post_review_budget")

bad_finding_hash = make_fixture("bad-finding-hash")
bad_finding_hash["ledger"]["finding_classes"][0]["occurrences"][0][
    "finding_sha256"
] = "f" * 64
run("bad-finding-hash", bad_finding_hash["ledger"], 1, "does not identify a finding")

omitted_finding = make_fixture("omitted-finding")
omitted_finding["ledger"]["finding_classes"] = []
run("omitted-finding", omitted_finding["ledger"], 1, "omits controller findings")

reordered_findings = make_fixture(
    "reordered-findings", receipt_findings=[[finding(1), finding(2)], []]
)
reordered_findings["ledger"]["finding_classes"][0]["occurrences"].reverse()
run("reordered-findings", reordered_findings["ledger"], 1, "not in controller receipt order")

fixed_without_evidence = make_fixture("fixed-without-evidence")
clear_disposition_evidence(
    fixed_without_evidence["ledger"]["finding_classes"][0]["occurrences"][-1]
)
run(
    "fixed-without-evidence",
    fixed_without_evidence["ledger"],
    1,
    "disposition_evidence_file",
)

for disposition in ("accepted_tradeoff", "pre_existing_out_of_scope"):
    case_name = f"{disposition.replace('_', '-')}-without-evidence"
    without_evidence = make_fixture(case_name)
    without_evidence_occurrence = without_evidence["ledger"]["finding_classes"][0][
        "occurrences"
    ][-1]
    without_evidence_occurrence["disposition"] = disposition
    clear_disposition_evidence(without_evidence_occurrence)
    run(case_name, without_evidence["ledger"], 1, "disposition_evidence_file")

    bound_case_name = f"{disposition.replace('_', '-')}-bound"
    bound = make_fixture(bound_case_name)
    bound_occurrence = bound["ledger"]["finding_classes"][0]["occurrences"][-1]
    bound_occurrence["disposition"] = disposition
    bind_disposition_evidence(
        f"{bound_case_name}-disposition.json",
        bound_occurrence,
    )
    run(bound_case_name, bound["ledger"], 0, "ready_for_human_decision")

stale_disposition_evidence = make_fixture("stale-disposition-evidence")
stale_disposition_evidence_occurrence = stale_disposition_evidence["ledger"][
    "finding_classes"
][0]["occurrences"][-1]
mutate_disposition_evidence(
    stale_disposition_evidence_occurrence,
    lambda evidence: evidence.update(candidate_sha256=OTHER_CANDIDATE),
)
run(
    "stale-disposition-evidence",
    stale_disposition_evidence["ledger"],
    1,
    "stale for the current candidate",
)

wrong_disposition_evidence = make_fixture("wrong-disposition-evidence")
wrong_disposition_evidence_occurrence = wrong_disposition_evidence["ledger"][
    "finding_classes"
][0]["occurrences"][-1]
mutate_disposition_evidence(
    wrong_disposition_evidence_occurrence,
    lambda evidence: evidence.update(disposition="accepted_tradeoff"),
)
run(
    "wrong-disposition-evidence",
    wrong_disposition_evidence["ledger"],
    1,
    "does not bind its disposition",
)

duplicate_key_cases = []
for case_name, field, first_value in (
    ("duplicate-candidate-evidence", "candidate_sha256", OTHER_CANDIDATE),
    ("duplicate-disposition-evidence", "disposition", "accepted_tradeoff"),
):
    duplicate_case = make_fixture(case_name)
    duplicate_occurrence = duplicate_case["ledger"]["finding_classes"][0][
        "occurrences"
    ][-1]
    duplicate_disposition_evidence_key(duplicate_occurrence, field, first_value)
    duplicate_result = invoke(case_name, duplicate_case["ledger"])
    duplicate_key_cases.append(
        (
            case_name,
            duplicate_result.returncode,
            f"duplicate object key: {field}" in duplicate_result.stdout,
            "Traceback" in duplicate_result.stdout,
            duplicate_result.stdout,
        )
    )
assert [item[1:4] for item in duplicate_key_cases] == [
    (1, True, False),
    (1, True, False),
], duplicate_key_cases

wrong_receipt_evidence = make_fixture("wrong-receipt-evidence")
wrong_receipt_evidence_occurrence = wrong_receipt_evidence["ledger"][
    "finding_classes"
][0]["occurrences"][-1]
mutate_disposition_evidence(
    wrong_receipt_evidence_occurrence,
    lambda evidence: evidence.update(receipt_sha256="f" * 64),
)
run(
    "wrong-receipt-evidence",
    wrong_receipt_evidence["ledger"],
    1,
    "does not bind its controller receipt",
)

wrong_finding_evidence = make_fixture("wrong-finding-evidence")
wrong_finding_evidence_occurrence = wrong_finding_evidence["ledger"][
    "finding_classes"
][0]["occurrences"][-1]
mutate_disposition_evidence(
    wrong_finding_evidence_occurrence,
    lambda evidence: evidence.update(finding_sha256="f" * 64),
)
run(
    "wrong-finding-evidence",
    wrong_finding_evidence["ledger"],
    1,
    "does not bind its controller finding",
)

historical_open = make_fixture(
    "historical-open",
    receipt_findings=[[finding(1), finding(2)], []],
)
historical_open["ledger"]["finding_classes"][0]["occurrences"][0][
    "disposition"
] = "open"
clear_disposition_evidence(
    historical_open["ledger"]["finding_classes"][0]["occurrences"][0]
)
run("historical-open", historical_open["ledger"], 1, "unresolved finding occurrence")

historical_open_linked = make_fixture(
    "historical-open-linked",
    receipt_findings=[[finding(1), finding(2)], []],
)
historical_open_linked_occurrences = historical_open_linked["ledger"][
    "finding_classes"
][0]["occurrences"]
historical_open_linked_occurrences[0]["disposition"] = "open"
clear_disposition_evidence(historical_open_linked_occurrences[0])
bind_disposition_evidence(
    "historical-open-linked-disposition.json",
    historical_open_linked_occurrences[1],
    resolves=[
        occurrence_ref(historical_open_linked_occurrences[0]),
        occurrence_ref(historical_open_linked_occurrences[1]),
    ],
)
run(
    "historical-open-linked",
    historical_open_linked["ledger"],
    0,
    "ready_for_human_decision",
)

source_refuted_without_evidence = make_fixture("source-refuted-without-evidence")
source_refuted_without_evidence_occurrence = source_refuted_without_evidence["ledger"][
    "finding_classes"
][0]["occurrences"][-1]
source_refuted_without_evidence_occurrence["disposition"] = "source_refuted"
clear_disposition_evidence(source_refuted_without_evidence_occurrence)
run(
    "source-refuted-without-evidence",
    source_refuted_without_evidence["ledger"],
    1,
    "disposition_evidence_file",
)

source_refuted = make_fixture("source-refuted")
source_refuted_occurrence = source_refuted["ledger"]["finding_classes"][0][
    "occurrences"
][-1]
source_refuted_occurrence["disposition"] = "source_refuted"
bind_disposition_evidence(
    "source-refuted-evidence.json",
    source_refuted_occurrence,
    evidence=["synthetic first-hand source evidence"],
)
run("source-refuted", source_refuted["ledger"], 0, "ready_for_human_decision")

source_refuted_bad_hash = copy.deepcopy(source_refuted["ledger"])
source_refuted_bad_hash["finding_classes"][0]["occurrences"][-1][
    "disposition_evidence_sha256"
] = "f" * 64
run(
    "source-refuted-bad-hash",
    source_refuted_bad_hash,
    1,
    "digest does not match",
)

needs_human = make_fixture("needs-human")
needs_human["ledger"]["finding_classes"][0]["occurrences"][-1][
    "disposition"
] = "needs_human_decision"
clear_disposition_evidence(
    needs_human["ledger"]["finding_classes"][0]["occurrences"][-1]
)
run("needs-human", needs_human["ledger"], 1, "unresolved finding occurrence")

third_occurrence = make_fixture(
    "third-occurrence",
    receipt_findings=[[finding(1), finding(2)], [finding(3)]],
    completion=False,
    unmatched=1,
    open_last=True,
)
run("third-occurrence", third_occurrence["ledger"], 0, "continuation_authorization_required")

split_predicate = copy.deepcopy(third_occurrence["ledger"])
original_class = split_predicate["finding_classes"][0]
predicate_variants = [
    "A closeout field is accepted without controller evidence.",
    "a   closeout field is accepted without controller evidence.",
    "A closeout field is accepted without controller evidence.",
]
split_predicate["finding_classes"] = [
    {
        "key": f"receipt-binding-{index}",
        "root_cause_predicate": predicate_variants[index - 1],
        "affected_surface": original_class["affected_surface"],
        "occurrences": [copy.deepcopy(occurrence)],
        "authoritative_sweep": None,
    }
    for index, occurrence in enumerate(original_class["occurrences"], start=1)
]
run(
    "split-predicate",
    split_predicate,
    1,
    "duplicate normalized root_cause_predicate",
)

distinct_predicates = copy.deepcopy(split_predicate)
for index, row in enumerate(distinct_predicates["finding_classes"], start=1):
    row["root_cause_predicate"] = (
        f"Distinct controller-evidence failure predicate {index}."
    )
run(
    "distinct-predicates",
    distinct_predicates,
    0,
    "closeout_state=continuation_authorization_required",
)

missing_sweep = copy.deepcopy(third_occurrence["ledger"])
missing_sweep["finding_classes"][0]["authoritative_sweep"] = None
run("missing-sweep", missing_sweep, 1, "authoritative_sweep")

bad_sweep_set = copy.deepcopy(third_occurrence["ledger"])
bad_sweep_set["finding_classes"][0]["authoritative_sweep"]["searched_set"] = [
    "skills/code-review"
]
run("bad-sweep-set", bad_sweep_set, 1, "searched_set does not match")

ready_unmatched = make_fixture(
    "ready-unmatched",
    receipt_findings=[[finding(1), finding(2), finding(3)], []],
    unmatched=1,
)
run("ready-unmatched", ready_unmatched["ledger"], 1, "ready sweep must report zero unmatched")

wrong_remote = make_fixture("wrong-remote")
wrong_remote["ledger"]["base_attestations"][1]["remote"] = "upstream"
run("wrong-remote", wrong_remote["ledger"], 1, "same remote and ref")

bad_sequence = make_fixture("bad-sequence")
bad_sequence["ledger"]["base_attestations"][1]["sequence"] = 3
run("bad-sequence", bad_sequence["ledger"], 1, "sequence must be contiguous")

bad_time = make_fixture("bad-time")
bad_time["ledger"]["base_attestations"][1]["confirmed_at"] = "2026-08-29T12:01:00Z"
run("bad-time", bad_time["ledger"], 1, "strictly increase")

invalid_time = make_fixture("invalid-time")
invalid_time["ledger"]["base_attestations"][0]["confirmed_at"] = "2026-08-29 12:00:00"
run("invalid-time", invalid_time["ledger"], 1, "strict RFC3339")

missing_mapping = make_fixture("missing-mapping")
missing_mapping["ledger"]["base_attestations"][1]["controller_receipt_sha256"] = None
run("missing-mapping", missing_mapping["ledger"], 1, "map every controller receipt")

consumed_first_drift = make_fixture("consumed-first-drift", base_shas=[A, B])
run(
    "consumed-first-drift",
    consumed_first_drift["ledger"],
    0,
    "closeout_state=ready_for_human_decision",
)

stable_trailing_recheck = make_fixture(
    "stable-trailing-recheck", base_shas=[A, A, A]
)
run(
    "stable-trailing-recheck",
    stable_trailing_recheck["ledger"],
    0,
    "closeout_state=ready_for_human_decision",
)

unconsumed_first_drift = make_fixture(
    "unconsumed-first-drift", base_shas=[A, A, B]
)
run(
    "unconsumed-first-drift",
    unconsumed_first_drift["ledger"],
    1,
    "final controller receipt does not consume the latest attested base",
)

bad_evidence = make_fixture("bad-evidence")
bad_evidence["ledger"]["base_attestations"][0]["evidence_sha256"] = "f" * 64
run("bad-evidence", bad_evidence["ledger"], 1, "digest does not match")

bad_evidence_content = make_fixture("bad-evidence-content")
bad_evidence_row = bad_evidence_content["ledger"]["base_attestations"][0]
bad_evidence_path = root / bad_evidence_row["evidence_file"]
bad_evidence_path.write_text(f"{A}\trefs/heads/other\n", encoding="utf-8")
bad_evidence_row["evidence_sha256"] = hashlib.sha256(
    bad_evidence_path.read_bytes()
).hexdigest()
run(
    "bad-evidence-content",
    bad_evidence_content["ledger"],
    1,
    "canonical ls-remote output",
)

surrogate = make_fixture("surrogate")
surrogate["ledger"]["controller_review_state"] = "\ud800"
run("surrogate", surrogate["ledger"], 1, "valid UTF-8 text")

fifo = make_fixture("fifo")
fifo_name = "controller-receipt.fifo"
os.mkfifo(root / fifo_name)
fifo["ledger"]["controller_receipts"][0]["file"] = fifo_name
fifo["ledger"]["controller_receipts"][0]["sha256"] = "f" * 64
run("fifo", fifo["ledger"], 1, "singly linked regular file")

second_drift_wrong = make_fixture("second-drift-wrong", base_shas=[A, B, A])
run("second-drift-wrong", second_drift_wrong["ledger"], 1, "second base drift")

flip_flop = make_fixture(
    "flip-flop",
    completion=False,
    base_shas=[A, B, A],
    closeout="baseline_race",
)
flip_flop["ledger"]["unreviewed_delta"] = ["target returned to its first SHA"]
run("flip-flop", flip_flop["ledger"], 0, "base_changes=2")

one_round_race = make_fixture(
    "one-round-race",
    receipt_findings=[[]],
    completion=False,
    base_shas=[A, B, C],
    closeout="baseline_race",
)
one_round_race["ledger"]["unreviewed_delta"] = ["second target drift after round 1"]
run("one-round-race", one_round_race["ledger"], 0, "base_changes=2")

post_race_round = make_fixture(
    "post-race-round",
    completion=False,
    base_shas=[A, B, C],
    closeout="baseline_race",
)
post_race_round["ledger"]["base_attestations"][1][
    "controller_receipt_sha256"
] = None
post_race_round["ledger"]["base_attestations"][2][
    "controller_receipt_sha256"
] = post_race_round["receipt_hashes"][1]
post_race_round["ledger"]["unreviewed_delta"] = [
    "round 2 was started after the second target drift"
]
run(
    "post-race-round",
    post_race_round["ledger"],
    1,
    "controller receipt is mapped at or after the second base drift",
)

race_with_complete = make_fixture(
    "race-with-complete", base_shas=[A, B, C], closeout="baseline_race"
)
race_with_complete["ledger"]["unreviewed_delta"] = ["second target drift"]
run("race-with-complete", race_with_complete["ledger"], 1, "cannot carry a completion receipt")

race_without_delta = make_fixture(
    "race-without-delta",
    completion=False,
    base_shas=[A, B, C],
    closeout="baseline_race",
)
run("race-without-delta", race_without_delta["ledger"], 1, "non-empty unreviewed_delta")

race_candidate = make_fixture(
    "race-candidate",
    completion=False,
    base_shas=[A, B, C],
    closeout="baseline_race",
)
race_candidate["ledger"]["candidate_sha256"] = OTHER_CANDIDATE
race_candidate["ledger"]["unreviewed_delta"] = ["second target drift"]
run(
    "race-candidate",
    race_candidate["ledger"],
    1,
    "controller receipt 1 does not bind the ledger candidate",
)

false_race = make_fixture(
    "false-race", completion=False, closeout="baseline_race"
)
run("false-race", false_race["ledger"], 1, "baseline_race requires two ordered base changes")

needs_human_resolution_results = []
for closing_disposition in sorted(CLOSED_DISPOSITIONS):
    case_name = f"historical-needs-human-{closing_disposition.replace('_', '-')}"
    historical_needs_human_linked = make_fixture(
        case_name,
        receipt_findings=[[finding(1), finding(2)], []],
    )
    historical_needs_human_occurrences = historical_needs_human_linked["ledger"][
        "finding_classes"
    ][0]["occurrences"]
    historical_needs_human_occurrences[0]["disposition"] = "needs_human_decision"
    clear_disposition_evidence(historical_needs_human_occurrences[0])
    historical_needs_human_occurrences[1]["disposition"] = closing_disposition
    bind_disposition_evidence(
        f"{case_name}-disposition.json",
        historical_needs_human_occurrences[1],
        resolves=[
            occurrence_ref(historical_needs_human_occurrences[0]),
            occurrence_ref(historical_needs_human_occurrences[1]),
        ],
    )
    needs_human_resolution_results.append(
        (case_name, invoke(case_name, historical_needs_human_linked["ledger"]))
    )

duplicate_ledger = make_fixture("duplicate-ledger")
duplicate_ledger_result = invoke_encoded(
    "duplicate-ledger",
    encode_duplicate_key(duplicate_ledger["ledger"], "schema_version", 2),
)

duplicate_controller = make_fixture("duplicate-controller")
duplicate_controller_ledger = duplicate_controller["ledger"]
duplicate_controller_name = duplicate_controller_ledger["controller_receipts"][-1][
    "file"
]
duplicate_controller_payload = json.loads(
    (root / duplicate_controller_name).read_text(encoding="utf-8")
)
duplicate_controller_hash = write_duplicate_json(
    duplicate_controller_name,
    duplicate_controller_payload,
    "status",
    "findings",
)
duplicate_controller_ledger["controller_receipts"][-1][
    "sha256"
] = duplicate_controller_hash
duplicate_controller_ledger["base_attestations"][-1][
    "controller_receipt_sha256"
] = duplicate_controller_hash
duplicate_controller_complete_name = duplicate_controller_ledger[
    "completion_receipt"
]["file"]
duplicate_controller_complete = json.loads(
    (root / duplicate_controller_complete_name).read_text(encoding="utf-8")
)
duplicate_controller_complete[
    "completion_review_result_sha256"
] = duplicate_controller_hash
duplicate_controller_ledger["completion_receipt"]["sha256"] = write_json(
    duplicate_controller_complete_name,
    duplicate_controller_complete,
)
duplicate_controller_result = invoke(
    "duplicate-controller",
    duplicate_controller_ledger,
)

duplicate_completion = make_fixture("duplicate-completion")
duplicate_completion_ledger = duplicate_completion["ledger"]
duplicate_completion_name = duplicate_completion_ledger["completion_receipt"]["file"]
duplicate_completion_payload = json.loads(
    (root / duplicate_completion_name).read_text(encoding="utf-8")
)
duplicate_completion_ledger["completion_receipt"]["sha256"] = write_duplicate_json(
    duplicate_completion_name,
    duplicate_completion_payload,
    "review_state",
    "reviewed",
)
duplicate_completion_result = invoke(
    "duplicate-completion",
    duplicate_completion_ledger,
)

duplicate_sweep = make_fixture(
    "duplicate-sweep",
    receipt_findings=[[finding(1), finding(2)], [finding(3)]],
    completion=False,
    open_last=True,
)
duplicate_sweep_ledger = duplicate_sweep["ledger"]
duplicate_sweep_row = duplicate_sweep_ledger["finding_classes"][0][
    "authoritative_sweep"
]
duplicate_sweep_payload = json.loads(
    (root / duplicate_sweep_row["manifest_file"]).read_text(encoding="utf-8")
)
duplicate_sweep_row["manifest_sha256"] = write_duplicate_json(
    duplicate_sweep_row["manifest_file"],
    duplicate_sweep_payload,
    "candidate_sha256",
    OTHER_CANDIDATE,
)
duplicate_sweep_result = invoke("duplicate-sweep", duplicate_sweep_ledger)

new_regressions = [
    *[
        (
            case_name,
            result,
            "cannot resolve a needs_human_decision occurrence",
        )
        for case_name, result in needs_human_resolution_results
    ],
    ("duplicate-ledger", duplicate_ledger_result, "duplicate object key: schema_version"),
    ("duplicate-controller", duplicate_controller_result, "duplicate object key: status"),
    (
        "duplicate-completion",
        duplicate_completion_result,
        "duplicate object key: review_state",
    ),
    ("duplicate-sweep", duplicate_sweep_result, "duplicate object key: candidate_sha256"),
]
assert [
    (name, result.returncode, token in result.stdout, "Traceback" in result.stdout)
    for name, result, token in new_regressions
] == [(name, 1, True, False) for name, _result, _token in new_regressions], [
    (name, result.returncode, result.stdout) for name, result, _token in new_regressions
]

print("test_validate_extraction_review_state: ok")
PY
