#!/usr/bin/env python3
"""Validate a receipt-bound terminal ledger for an extraction review lane."""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import stat
import sys
import unicodedata
from datetime import datetime
from pathlib import Path
from typing import Any, NoReturn

MAX_LEDGER_BYTES = 128_000
MAX_RESULT_BYTES = 1_000_000
MAX_EVIDENCE_BYTES = 128_000
OBJECT_ID_RE = re.compile(r"(?:[0-9a-f]{40}|[0-9a-f]{64})")
SHA256_RE = re.compile(r"[0-9a-f]{64}")
RFC3339_RE = re.compile(
    r"\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d+)?(?:Z|[+-]\d{2}:\d{2})"
)
TERMINAL_STATES = {
    "ready_for_human_decision",
    "continuation_authorization_required",
    "baseline_race",
}
EXTERNAL_REVIEW_STATES = {"reviewed", "findings_pending", "post_review_budget"}
KNOWN_REVIEW_STATES = EXTERNAL_REVIEW_STATES | {"self_reviewed"}
DISPOSITIONS = {
    "fixed",
    "source_refuted",
    "accepted_tradeoff",
    "pre_existing_out_of_scope",
    "needs_human_decision",
    "open",
}
RESOLVED_DISPOSITIONS = {
    "fixed",
    "source_refuted",
    "accepted_tradeoff",
    "pre_existing_out_of_scope",
}


class StateError(Exception):
    pass


def fail(message: str) -> NoReturn:
    raise StateError(message)


def bounded_text(value: object, field: str, maximum: int = 1000) -> str:
    if not isinstance(value, str) or value != value.strip() or not value:
        fail(f"{field} must be a non-empty normalized string")
    # Interior control characters would otherwise be echoed into stderr
    # diagnostics (terminal-escape injection on the error path). C1 controls
    # (NEL, CSI) and Unicode line/paragraph separators forge line breaks too.
    if any(
        ord(char) < 0x20 or 0x7F <= ord(char) <= 0x9F or char in "\u2028\u2029"
        for char in value
    ):
        fail(f"{field} must not contain control characters")
    # Default-ignorable format characters (ZWSP, word joiner, bidi controls)
    # let visually identical class keys or predicates register as distinct,
    # splitting one recurrence class below its sweep threshold.
    if any(unicodedata.category(char) == "Cf" for char in value):
        fail(f"{field} must not contain format characters")
    try:
        value.encode("utf-8")
    except UnicodeEncodeError:
        fail(f"{field} must be valid UTF-8 text")
    if len(value) > maximum:
        fail(f"{field} exceeds {maximum} characters")
    return value


def object_id(value: object, field: str) -> str:
    text = bounded_text(value, field, 64)
    if OBJECT_ID_RE.fullmatch(text) is None:
        fail(f"{field} must be a lowercase 40- or 64-character hexadecimal object id")
    return text


def sha256(value: object, field: str) -> str:
    text = bounded_text(value, field, 64)
    if SHA256_RE.fullmatch(text) is None:
        fail(f"{field} must be a lowercase 64-character SHA-256 digest")
    return text


def exact_object(value: object, fields: set[str], label: str) -> dict[str, Any]:
    if not isinstance(value, dict) or set(value) != fields:
        fail(f"{label} must contain exactly: {', '.join(sorted(fields))}")
    return value


def read_regular(path: Path, *, label: str, maximum: int) -> bytes:
    if not hasattr(os, "O_NOFOLLOW") or not hasattr(os, "O_NONBLOCK"):
        fail(f"platform cannot open {label} with no-follow and non-blocking safety")
    try:
        fd = os.open(
            path,
            os.O_RDONLY
            | os.O_NOFOLLOW
            | getattr(os, "O_CLOEXEC", 0)
            | os.O_NONBLOCK,
        )
    except (OSError, UnicodeError, ValueError) as exc:
        fail(f"{label} is unreadable: {exc}")
    try:
        try:
            info = os.fstat(fd)
        except OSError as exc:
            fail(f"cannot inspect {label}: {exc}")
        if not stat.S_ISREG(info.st_mode) or info.st_nlink != 1:
            fail(f"{label} must be a singly linked regular file")
        if info.st_size > maximum:
            fail(f"{label} exceeds {maximum} bytes")
        chunks: list[bytes] = []
        remaining = maximum + 1
        while remaining:
            try:
                chunk = os.read(fd, remaining)
            except OSError as exc:
                fail(f"cannot read {label}: {exc}")
            if not chunk:
                break
            chunks.append(chunk)
            remaining -= len(chunk)
        raw = b"".join(chunks)
    finally:
        try:
            os.close(fd)
        except OSError:
            pass
    if len(raw) > maximum:
        fail(f"{label} exceeds {maximum} bytes")
    return raw


def decode_json(raw: bytes, *, label: str) -> dict[str, Any]:
    def unique_object(pairs: list[tuple[str, Any]]) -> dict[str, Any]:
        value: dict[str, Any] = {}
        for key, item in pairs:
            if key in value:
                fail(f"{label} contains duplicate object key: {key}")
            value[key] = item
        return value

    def reject_constant(constant: str) -> NoReturn:
        fail(f"{label} contains a non-standard JSON constant: {constant}")

    try:
        value = json.loads(
            raw.decode("utf-8"),
            object_pairs_hook=unique_object,
            parse_constant=reject_constant,
        )
    except StateError:
        raise
    except (UnicodeError, json.JSONDecodeError) as exc:
        fail(f"{label} must be UTF-8 JSON: {exc}")
    if not isinstance(value, dict):
        fail(f"{label} must be a JSON object")
    return value


def sibling_name(value: object, field: str) -> str:
    name = bounded_text(value, field, 255)
    if Path(name).is_absolute() or Path(name).name != name or "/" in name or "\\" in name:
        fail(f"{field} must name a file in the ledger directory")
    return name


def load_sibling(
    ledger_dir: Path,
    *,
    file_value: object,
    digest_value: object,
    label: str,
    maximum: int,
) -> bytes:
    name = sibling_name(file_value, f"{label}.file")
    expected = sha256(digest_value, f"{label}.sha256")
    raw = read_regular(ledger_dir / name, label=label, maximum=maximum)
    actual = hashlib.sha256(raw).hexdigest()
    if actual != expected:
        fail(f"{label} digest does not match {name}")
    return raw


def canonical_hash(value: object, label: str) -> str:
    try:
        encoded = json.dumps(
            value,
            ensure_ascii=False,
            sort_keys=True,
            separators=(",", ":"),
        ).encode()
    except (TypeError, ValueError, UnicodeError) as exc:
        fail(f"{label} is not canonical JSON: {exc}")
    return hashlib.sha256(encoded).hexdigest()


def parse_rfc3339(value: object, field: str) -> datetime:
    text = bounded_text(value, field, 100)
    if RFC3339_RE.fullmatch(text) is None:
        fail(f"{field} must be a strict RFC3339 timestamp")
    try:
        parsed = datetime.fromisoformat(text[:-1] + "+00:00" if text.endswith("Z") else text)
    except ValueError as exc:
        fail(f"{field} must be a valid RFC3339 timestamp: {exc}")
    if parsed.utcoffset() is None:
        fail(f"{field} must include an RFC3339 UTC offset")
    return parsed


def load(path: Path) -> tuple[dict[str, Any], Path]:
    raw = read_regular(path, label="ledger", maximum=MAX_LEDGER_BYTES)
    value = decode_json(raw, label="ledger")
    payload = exact_object(
        value,
        {
            "schema_version",
            "candidate_sha256",
            "controller_receipts",
            "completion_receipt",
            "base_attestations",
            "autonomous_round",
            "controller_review_state",
            "finding_classes",
            "unreviewed_delta",
            "closeout_state",
        },
        "ledger",
    )
    return payload, path.absolute().parent


def validate_scope(receipt: dict[str, Any], label: str) -> str:
    scope = exact_object(
        receipt.get("review_scope"),
        {
            "schema_version",
            "intent_sha256",
            "acceptance_sha256",
            "stage",
            "review_depth",
            "risk_tags",
            "challenge_budget",
            "wording_only_proof_sha256",
            "wording_only_scope_sha256",
        },
        f"{label}.review_scope",
    )
    if scope["schema_version"] != 3 or type(scope["schema_version"]) is not int:
        fail(f"{label}.review_scope.schema_version must be 3")
    sha256(scope["intent_sha256"], f"{label}.review_scope.intent_sha256")
    sha256(scope["acceptance_sha256"], f"{label}.review_scope.acceptance_sha256")
    stage = bounded_text(scope["stage"], f"{label}.review_scope.stage", 80)
    depth = bounded_text(scope["review_depth"], f"{label}.review_scope.review_depth", 80)
    risks = scope["risk_tags"]
    if not isinstance(risks, list):
        fail(f"{label}.review_scope.risk_tags must be an array")
    normalized_risks = [
        bounded_text(item, f"{label}.review_scope.risk_tags", 100) for item in risks
    ]
    if len(normalized_risks) != len(set(normalized_risks)):
        fail(f"{label}.review_scope.risk_tags contains duplicates")
    if scope["challenge_budget"] != 2 or type(scope["challenge_budget"]) is not int:
        fail(f"{label}.review_scope.challenge_budget must be 2")
    if (
        scope["wording_only_proof_sha256"] is not None
        or scope["wording_only_scope_sha256"] is not None
        or "wording_only_proof_sha256" not in receipt
        or receipt["wording_only_proof_sha256"] is not None
        or "wording_only_scope" not in receipt
        or receipt["wording_only_scope"] is not None
    ):
        fail(f"{label} must bind the non-wording extraction scope")
    recorded = sha256(receipt.get("review_scope_sha256"), f"{label}.review_scope_sha256")
    if canonical_hash(scope, f"{label}.review_scope") != recorded:
        fail(f"{label}.review_scope_sha256 does not reproduce review_scope")
    if (
        receipt.get("stage") != stage
        or receipt.get("review_depth") != depth
        or receipt.get("risk_tags") != normalized_risks
    ):
        fail(f"{label} top-level scope fields contradict review_scope")
    return recorded


def validate_controller_receipts(
    payload: dict[str, Any], ledger_dir: Path
) -> tuple[list[dict[str, Any]], list[str], dict[str, list[str]], str, str]:
    refs = payload["controller_receipts"]
    if not isinstance(refs, list) or not 1 <= len(refs) <= 3:
        fail("controller_receipts must contain one to three ordered Agent rounds")
    if payload["autonomous_round"] != len(refs) or type(payload["autonomous_round"]) is not int:
        fail("autonomous_round must equal the ordered controller receipt count")

    receipts: list[dict[str, Any]] = []
    receipt_hashes: list[str] = []
    finding_hashes: dict[str, list[str]] = {}
    chain_id: str | None = None
    scope_hash: str | None = None
    ledger_candidate = sha256(
        payload["candidate_sha256"], "ledger.candidate_sha256"
    )
    for expected_index, value in enumerate(refs, start=1):
        ref = exact_object(
            value, {"sequence", "file", "sha256"}, f"controller_receipts[{expected_index - 1}]"
        )
        if ref["sequence"] != expected_index or type(ref["sequence"]) is not int:
            fail("controller receipt sequence must be contiguous from 1")
        receipt_hash = sha256(ref["sha256"], f"controller_receipts[{expected_index - 1}].sha256")
        raw = load_sibling(
            ledger_dir,
            file_value=ref["file"],
            digest_value=receipt_hash,
            label=f"controller receipt {expected_index}",
            maximum=MAX_RESULT_BYTES,
        )
        receipt = decode_json(raw, label=f"controller receipt {expected_index}")
        if receipt.get("schema_version") != 3 or type(receipt.get("schema_version")) is not int:
            fail(f"controller receipt {expected_index} schema_version must be 3")
        expected_mode = "review" if expected_index == 1 else "challenge"
        if receipt.get("mode") != expected_mode:
            fail(f"controller receipt {expected_index} must have mode {expected_mode}")
        if receipt.get("status") not in {"passed", "findings"}:
            fail(f"controller receipt {expected_index} must have status passed or findings")
        if receipt.get("review_chain_tracked") is not True:
            fail(f"controller receipt {expected_index} must belong to a tracked chain")
        current_chain = bounded_text(
            receipt.get("review_chain_id"), f"controller receipt {expected_index}.review_chain_id", 120
        )
        if chain_id is None:
            chain_id = current_chain
        elif current_chain != chain_id:
            fail(f"controller receipt {expected_index} review_chain_id changed")
        if receipt.get("autonomous_review_index") != expected_index or type(
            receipt.get("autonomous_review_index")
        ) is not int:
            fail(f"controller receipt {expected_index} autonomous_review_index is not contiguous")
        expected_challenge_index = 0 if expected_index == 1 else expected_index - 1
        if receipt.get("challenge_index") != expected_challenge_index or type(
            receipt.get("challenge_index")
        ) is not int:
            fail(f"controller receipt {expected_index} challenge_index is invalid")
        if receipt.get("challenge_budget") != 2 or type(receipt.get("challenge_budget")) is not int:
            fail(f"controller receipt {expected_index} challenge_budget must be 2")
        if receipt.get("autonomous_review_budget") != 3 or type(
            receipt.get("autonomous_review_budget")
        ) is not int:
            fail(f"controller receipt {expected_index} autonomous_review_budget must be 3")
        expected_remaining = 3 - expected_index
        if receipt.get("autonomous_reviews_remaining") != expected_remaining or type(
            receipt.get("autonomous_reviews_remaining")
        ) is not int:
            fail(f"controller receipt {expected_index} autonomous_reviews_remaining is invalid")
        if receipt.get("autonomous_review_allowed") is not (expected_remaining > 0):
            fail(f"controller receipt {expected_index} autonomous_review_allowed is invalid")
        prior = receipt.get("prior_review_result_sha256")
        if prior != receipt_hashes:
            fail(f"controller receipt {expected_index} prior_review_result_sha256 is not the complete ordered prefix")
        candidate = sha256(
            receipt.get("candidate_sha256"), f"controller receipt {expected_index}.candidate_sha256"
        )
        packet = sha256(
            receipt.get("packet_sha256"), f"controller receipt {expected_index}.packet_sha256"
        )
        if packet != candidate:
            fail(f"controller receipt {expected_index} packet_sha256 must equal candidate_sha256")
        # Every counted round must have inspected the exact final candidate;
        # a chain whose review round saw an earlier candidate is not a review
        # of the candidate this ledger closes out.
        if candidate != ledger_candidate:
            fail(
                f"controller receipt {expected_index} does not bind the ledger candidate"
            )
        current_scope_hash = validate_scope(receipt, f"controller receipt {expected_index}")
        if scope_hash is None:
            scope_hash = current_scope_hash
        elif current_scope_hash != scope_hash:
            fail(f"controller receipt {expected_index} review scope changed")

        findings = receipt.get("findings")
        if not isinstance(findings, list):
            fail(f"controller receipt {expected_index}.findings must be an array")
        current_findings: list[str] = []
        current_finding_set: set[str] = set()
        for finding_index, finding in enumerate(findings):
            if not isinstance(finding, dict):
                fail(f"controller receipt {expected_index}.findings[{finding_index}] must be an object")
            finding_hash = canonical_hash(
                finding, f"controller receipt {expected_index}.findings[{finding_index}]"
            )
            if finding_hash in current_finding_set:
                fail(f"controller receipt {expected_index} repeats a canonical finding")
            current_finding_set.add(finding_hash)
            current_findings.append(finding_hash)
        if receipt["status"] == "passed" and findings:
            fail(f"controller receipt {expected_index} passed status cannot carry findings")
        if receipt["status"] == "findings" and not findings:
            fail(f"controller receipt {expected_index} findings status requires findings")
        state = bounded_text(
            receipt.get("review_state"), f"controller receipt {expected_index}.review_state", 80
        )
        if state not in EXTERNAL_REVIEW_STATES:
            fail(f"controller receipt {expected_index} has unknown controller review_state {state}")
        expected_state = (
            "post_review_budget"
            if receipt["status"] == "findings" and expected_index == 3
            else "findings_pending"
            if receipt["status"] == "findings"
            else "reviewed"
        )
        if state != expected_state:
            fail(f"controller receipt {expected_index} review_state contradicts status and round")
        if receipt.get("human_decision_required") is not (state == "post_review_budget"):
            fail(f"controller receipt {expected_index} human_decision_required contradicts review_state")

        receipts.append(receipt)
        receipt_hashes.append(receipt_hash)
        finding_hashes[receipt_hash] = current_findings

    if chain_id is None or scope_hash is None:
        fail("controller receipt chain is empty")
    return receipts, receipt_hashes, finding_hashes, chain_id, scope_hash


def validate_completion_receipt(
    value: object,
    ledger_dir: Path,
    receipts: list[dict[str, Any]],
    receipt_hashes: list[str],
    chain_id: str,
    scope_hash: str,
) -> dict[str, Any] | None:
    if value is None:
        return None
    ref = exact_object(value, {"file", "sha256"}, "completion_receipt")
    raw = load_sibling(
        ledger_dir,
        file_value=ref["file"],
        digest_value=ref["sha256"],
        label="completion receipt",
        maximum=MAX_RESULT_BYTES,
    )
    receipt = decode_json(raw, label="completion receipt")
    final = receipts[-1]
    if (
        receipt.get("schema_version") != 3
        or type(receipt.get("schema_version")) is not int
        or receipt.get("mode") != "complete"
        or receipt.get("status") != "passed"
        or receipt.get("review_state") != "self_reviewed"
        or receipt.get("completion_gated") is not False
        or receipt.get("next_action") != "complete"
        or receipt.get("findings") != []
    ):
        fail("completion receipt must be a passed self_reviewed complete result")
    if final.get("status") != "passed" or final.get("findings") != []:
        fail("completion receipt cannot close a final external receipt with findings")
    if receipt.get("review_chain_tracked") is not True or receipt.get("review_chain_id") != chain_id:
        fail("completion receipt review_chain_id does not match the controller chain")
    if receipt.get("challenge_budget") != 2 or type(receipt.get("challenge_budget")) is not int:
        fail("completion receipt challenge_budget must be 2")
    if receipt.get("autonomous_review_budget") != 3 or type(
        receipt.get("autonomous_review_budget")
    ) is not int:
        fail("completion receipt autonomous_review_budget must be 3")
    if receipt.get("autonomous_review_index") != len(receipts) or type(
        receipt.get("autonomous_review_index")
    ) is not int:
        fail("completion receipt autonomous_review_index does not match the final round")
    expected_remaining = 3 - len(receipts)
    if receipt.get("autonomous_reviews_remaining") != expected_remaining or type(
        receipt.get("autonomous_reviews_remaining")
    ) is not int:
        fail("completion receipt autonomous_reviews_remaining does not match the final round")
    if receipt.get("autonomous_review_allowed") is not False:
        fail("completion receipt must disable further autonomous review")
    if receipt.get("prior_review_result_sha256") != receipt_hashes[:-1]:
        fail("completion receipt prior_review_result_sha256 does not match the final external receipt")
    if receipt.get("completion_review_result_sha256") != receipt_hashes[-1]:
        fail("completion receipt completion_review_result_sha256 does not identify the final external receipt")
    candidate = sha256(receipt.get("candidate_sha256"), "completion receipt.candidate_sha256")
    packet = sha256(receipt.get("packet_sha256"), "completion receipt.packet_sha256")
    if packet != candidate or candidate != final.get("candidate_sha256"):
        fail("completion receipt does not bind the exact final candidate")
    if validate_scope(receipt, "completion receipt") != scope_hash:
        fail("completion receipt review scope changed")
    return receipt


def validate_base_attestations(
    payload: dict[str, Any],
    ledger_dir: Path,
    receipt_hashes: list[str],
    closeout: str,
) -> int:
    attestations = payload["base_attestations"]
    if not isinstance(attestations, list) or not attestations:
        fail("base_attestations must be a non-empty array")
    base_shas: list[str] = []
    mapped_receipts: list[str] = []
    mapped_receipt_bases: list[str] = []
    expected_remote: str | None = None
    expected_ref: str | None = None
    previous_time: datetime | None = None
    base_changes = 0
    second_drift_sequence: int | None = None
    for index, item in enumerate(attestations, start=1):
        row = exact_object(
            item,
            {
                "sequence",
                "remote",
                "ref",
                "sha",
                "confirmed_at",
                "controller_receipt_sha256",
                "evidence_file",
                "evidence_sha256",
            },
            f"base_attestations[{index - 1}]",
        )
        if row["sequence"] != index or type(row["sequence"]) is not int:
            fail("base attestation sequence must be contiguous from 1")
        remote = bounded_text(row["remote"], f"base_attestations[{index - 1}].remote", 200)
        ref = bounded_text(row["ref"], f"base_attestations[{index - 1}].ref", 300)
        if expected_remote is None:
            expected_remote, expected_ref = remote, ref
        elif remote != expected_remote or ref != expected_ref:
            fail("base attestations must use the same remote and ref")
        base_sha = object_id(row["sha"], f"base_attestations[{index - 1}].sha")
        if base_shas and base_sha != base_shas[-1]:
            base_changes += 1
            if base_changes == 2:
                second_drift_sequence = index
        confirmed = parse_rfc3339(
            row["confirmed_at"], f"base_attestations[{index - 1}].confirmed_at"
        )
        if previous_time is not None and confirmed <= previous_time:
            fail("base attestation confirmed_at values must strictly increase")
        previous_time = confirmed
        raw = load_sibling(
            ledger_dir,
            file_value=row["evidence_file"],
            digest_value=row["evidence_sha256"],
            label=f"base attestation {index} evidence",
            maximum=MAX_EVIDENCE_BYTES,
        )
        expected_raw = f"{base_sha}\t{ref}\n".encode()
        if raw != expected_raw:
            fail(f"base attestation {index} evidence does not contain canonical ls-remote output")
        receipt_hash_value = row["controller_receipt_sha256"]
        if receipt_hash_value is not None:
            if second_drift_sequence is not None:
                fail(
                    "a controller receipt is mapped at or after the second base drift"
                )
            mapped_receipts.append(
                sha256(
                    receipt_hash_value,
                    f"base_attestations[{index - 1}].controller_receipt_sha256",
                )
            )
            mapped_receipt_bases.append(base_sha)
        base_shas.append(base_sha)
    if mapped_receipts != receipt_hashes:
        fail("base attestations must map every controller receipt exactly once in order")
    second_drift = base_changes >= 2
    if second_drift != (closeout == "baseline_race"):
        fail("the second base drift must terminate as baseline_race, and baseline_race requires two ordered base changes")
    if (
        closeout != "baseline_race"
        and mapped_receipt_bases[-1] != base_shas[-1]
    ):
        fail(
            "the final controller receipt does not consume the latest attested base"
        )
    return base_changes


def validate_disposition_evidence(
    ledger_dir: Path,
    *,
    file_value: object,
    digest_value: object,
    candidate: str,
    receipt_hash: str,
    finding_hash: str,
    disposition: str,
    class_key: str,
    occurrence_index: int,
    class_pairs: list[tuple[str, str]],
    unresolved_pairs: set[tuple[str, str]],
) -> list[tuple[str, str]]:
    label = f"finding class {class_key} disposition evidence {occurrence_index + 1}"
    raw = load_sibling(
        ledger_dir,
        file_value=file_value,
        digest_value=digest_value,
        label=label,
        maximum=MAX_EVIDENCE_BYTES,
    )
    evidence = exact_object(
        decode_json(raw, label=label),
        {
            "schema_version",
            "candidate_sha256",
            "receipt_sha256",
            "finding_sha256",
            "disposition",
            "resolves_occurrences",
            "evidence",
        },
        label,
    )
    if evidence["schema_version"] != 1 or type(evidence["schema_version"]) is not int:
        fail(f"{label}.schema_version must be 1")
    if sha256(evidence["candidate_sha256"], f"{label}.candidate_sha256") != candidate:
        fail(f"{label} is stale for the current candidate")
    if sha256(evidence["receipt_sha256"], f"{label}.receipt_sha256") != receipt_hash:
        fail(f"{label} does not bind its controller receipt")
    if sha256(evidence["finding_sha256"], f"{label}.finding_sha256") != finding_hash:
        fail(f"{label} does not bind its controller finding")
    if bounded_text(evidence["disposition"], f"{label}.disposition", 80) != disposition:
        fail(f"{label} does not bind its disposition")

    refs = evidence["resolves_occurrences"]
    if not isinstance(refs, list) or not refs:
        fail(f"{label}.resolves_occurrences must be a non-empty array")
    resolved_pairs: list[tuple[str, str]] = []
    seen_resolved: set[tuple[str, str]] = set()
    for resolved_index, value in enumerate(refs):
        resolved = exact_object(
            value,
            {"receipt_sha256", "finding_sha256"},
            f"{label}.resolves_occurrences[{resolved_index}]",
        )
        pair = (
            sha256(
                resolved["receipt_sha256"],
                f"{label}.resolves_occurrences[{resolved_index}].receipt_sha256",
            ),
            sha256(
                resolved["finding_sha256"],
                f"{label}.resolves_occurrences[{resolved_index}].finding_sha256",
            ),
        )
        if pair in seen_resolved:
            fail(f"{label} repeats a resolved occurrence")
        if pair not in class_pairs:
            fail(f"{label} resolves an occurrence outside the current class prefix")
        if pair not in unresolved_pairs:
            fail(f"{label} resolves an occurrence that is not currently unresolved")
        seen_resolved.add(pair)
        resolved_pairs.append(pair)
    current_pair = (receipt_hash, finding_hash)
    if current_pair not in seen_resolved:
        fail(f"{label} must resolve its current occurrence")
    expected_order = [pair for pair in class_pairs if pair in seen_resolved]
    if resolved_pairs != expected_order:
        fail(f"{label}.resolves_occurrences must follow finding class order")

    evidence_items = evidence["evidence"]
    if not isinstance(evidence_items, list) or not evidence_items:
        fail(f"{label}.evidence must be a non-empty array")
    normalized_evidence = [
        bounded_text(value, f"{label}.evidence[{index}]", 1000)
        for index, value in enumerate(evidence_items)
    ]
    if len(normalized_evidence) != len(set(normalized_evidence)):
        fail(f"{label}.evidence contains duplicates")
    return resolved_pairs


def validate_finding_classes(
    payload: dict[str, Any],
    ledger_dir: Path,
    receipt_findings: dict[str, list[str]],
    candidate: str,
    closeout: str,
) -> bool:
    classes = payload["finding_classes"]
    if not isinstance(classes, list):
        fail("finding_classes must be an array")
    expected_pairs = {
        (receipt_hash, finding_hash)
        for receipt_hash, findings in receipt_findings.items()
        for finding_hash in findings
    }
    seen_pairs: set[tuple[str, str]] = set()
    seen_keys: set[str] = set()
    seen_predicates: dict[str, str] = {}
    any_unresolved = False
    finding_order = {
        (receipt_hash, finding_hash): (receipt_index, finding_index)
        for receipt_index, (receipt_hash, findings) in enumerate(receipt_findings.items())
        for finding_index, finding_hash in enumerate(findings)
    }
    for class_index, item in enumerate(classes):
        row = exact_object(
            item,
            {"key", "root_cause_predicate", "affected_surface", "occurrences", "authoritative_sweep"},
            f"finding_classes[{class_index}]",
        )
        key = bounded_text(row["key"], f"finding_classes[{class_index}].key", 120)
        if key in seen_keys:
            fail(f"duplicate finding class key: {key}")
        seen_keys.add(key)
        predicate = bounded_text(
            row["root_cause_predicate"],
            f"finding_classes[{class_index}].root_cause_predicate",
            2000,
        )
        normalized_predicate = " ".join(predicate.casefold().split())
        prior_key = seen_predicates.get(normalized_predicate)
        if prior_key is not None:
            fail(
                "duplicate normalized root_cause_predicate across finding classes: "
                f"{prior_key}, {key}"
            )
        seen_predicates[normalized_predicate] = key
        bounded_text(
            row["affected_surface"], f"finding_classes[{class_index}].affected_surface", 500
        )
        occurrences = row["occurrences"]
        if not isinstance(occurrences, list) or not occurrences:
            fail(f"finding_classes[{class_index}].occurrences must be non-empty")
        class_order: list[tuple[int, int]] = []
        class_pairs: list[tuple[str, str]] = []
        unresolved_pairs: set[tuple[str, str]] = set()
        human_decision_pairs: set[tuple[str, str]] = set()
        for occurrence_index, occurrence in enumerate(occurrences):
            occurrence_label = (
                f"finding_classes[{class_index}].occurrences[{occurrence_index}]"
            )
            if not isinstance(occurrence, dict):
                fail(f"{occurrence_label} must be an object")
            disposition = bounded_text(
                occurrence.get("disposition"),
                f"{occurrence_label}.disposition",
                80,
            )
            if disposition not in DISPOSITIONS:
                fail(f"finding class {key} has an unknown disposition")
            occurrence_fields = {
                "receipt_sha256",
                "finding_sha256",
                "disposition",
            }
            if disposition in RESOLVED_DISPOSITIONS:
                occurrence_fields |= {
                    "disposition_evidence_file",
                    "disposition_evidence_sha256",
                }
            occurrence_row = exact_object(
                occurrence,
                occurrence_fields,
                occurrence_label,
            )
            receipt_hash = sha256(
                occurrence_row["receipt_sha256"],
                f"finding_classes[{class_index}].occurrences[{occurrence_index}].receipt_sha256",
            )
            finding_hash = sha256(
                occurrence_row["finding_sha256"],
                f"finding_classes[{class_index}].occurrences[{occurrence_index}].finding_sha256",
            )
            pair = (receipt_hash, finding_hash)
            if pair not in expected_pairs:
                fail(f"finding class {key} occurrence does not identify a finding in its controller receipt")
            if pair in seen_pairs:
                fail(f"controller finding {finding_hash} is classified more than once")
            seen_pairs.add(pair)
            class_order.append(finding_order[pair])
            class_pairs.append(pair)
            unresolved_pairs.add(pair)
            if disposition == "needs_human_decision":
                human_decision_pairs.add(pair)
            if disposition in RESOLVED_DISPOSITIONS:
                resolved_pairs = validate_disposition_evidence(
                    ledger_dir,
                    file_value=occurrence_row["disposition_evidence_file"],
                    digest_value=occurrence_row["disposition_evidence_sha256"],
                    candidate=candidate,
                    receipt_hash=receipt_hash,
                    finding_hash=finding_hash,
                    disposition=disposition,
                    class_key=key,
                    occurrence_index=occurrence_index,
                    class_pairs=class_pairs,
                    unresolved_pairs=unresolved_pairs,
                )
                if human_decision_pairs.intersection(resolved_pairs):
                    fail(
                        f"finding class {key} local evidence cannot resolve a "
                        "needs_human_decision occurrence"
                    )
                unresolved_pairs.difference_update(resolved_pairs)
        if class_order != sorted(class_order):
            fail(f"finding class {key} occurrences are not in controller receipt order")
        any_unresolved |= bool(unresolved_pairs)

        sweep = row["authoritative_sweep"]
        if len(occurrences) >= 3:
            sweep_row = exact_object(
                sweep,
                {
                    "candidate_sha256",
                    "manifest_file",
                    "manifest_sha256",
                    "searched_set",
                    "unmatched_instances",
                },
                f"finding_classes[{class_index}].authoritative_sweep",
            )
            if sha256(
                sweep_row["candidate_sha256"],
                f"finding_classes[{class_index}].authoritative_sweep.candidate_sha256",
            ) != candidate:
                fail(f"finding class {key} sweep is stale for the current candidate")
            searched = sweep_row["searched_set"]
            if not isinstance(searched, list) or not searched:
                fail(f"finding class {key} third occurrence requires a non-empty searched_set")
            normalized = [
                bounded_text(value, f"finding class {key} searched_set", 500)
                for value in searched
            ]
            if len(normalized) != len(set(normalized)):
                fail(f"finding class {key} searched_set contains duplicates")
            unmatched = sweep_row["unmatched_instances"]
            if type(unmatched) is not int or unmatched < 0:
                fail(f"finding class {key} unmatched_instances must be a non-negative integer")
            manifest_raw = load_sibling(
                ledger_dir,
                file_value=sweep_row["manifest_file"],
                digest_value=sweep_row["manifest_sha256"],
                label=f"finding class {key} sweep manifest",
                maximum=MAX_EVIDENCE_BYTES,
            )
            manifest = exact_object(
                decode_json(manifest_raw, label=f"finding class {key} sweep manifest"),
                {"schema_version", "candidate_sha256", "searched_set", "unmatched_instances"},
                f"finding class {key} sweep manifest",
            )
            if manifest["schema_version"] != 1 or type(manifest["schema_version"]) is not int:
                fail(f"finding class {key} sweep manifest schema_version must be 1")
            if sha256(manifest["candidate_sha256"], f"finding class {key} sweep manifest candidate") != candidate:
                fail(f"finding class {key} sweep manifest is stale")
            if manifest["searched_set"] != normalized:
                fail(f"finding class {key} searched_set does not match its sweep manifest")
            unmatched_items = manifest["unmatched_instances"]
            if not isinstance(unmatched_items, list):
                fail(f"finding class {key} sweep manifest unmatched_instances must be an array")
            normalized_unmatched = [
                bounded_text(value, f"finding class {key} unmatched instance", 500)
                for value in unmatched_items
            ]
            if len(normalized_unmatched) != len(set(normalized_unmatched)):
                fail(f"finding class {key} sweep manifest repeats an unmatched instance")
            if len(normalized_unmatched) != unmatched:
                fail(f"finding class {key} unmatched_instances count does not match its sweep manifest")
            if closeout == "ready_for_human_decision" and unmatched != 0:
                fail(f"finding class {key} ready sweep must report zero unmatched instances")
        elif sweep is not None:
            fail(f"finding class {key} has a sweep before its third occurrence")
    if seen_pairs != expected_pairs:
        fail("finding_classes omits controller findings")
    return any_unresolved


def validate(payload: dict[str, Any], ledger_dir: Path) -> tuple[str, int, int]:
    if payload["schema_version"] != 3 or type(payload["schema_version"]) is not int:
        fail("schema_version must be 3")
    candidate = sha256(payload["candidate_sha256"], "candidate_sha256")
    closeout = bounded_text(payload["closeout_state"], "closeout_state", 80)
    if closeout not in TERMINAL_STATES:
        fail("closeout_state is not an extraction terminal state")

    receipts, receipt_hashes, receipt_findings, chain_id, scope_hash = (
        validate_controller_receipts(payload, ledger_dir)
    )
    if receipts[-1]["candidate_sha256"] != candidate:
        fail("candidate_sha256 must equal the final controller receipt candidate")
    completion = validate_completion_receipt(
        payload["completion_receipt"],
        ledger_dir,
        receipts,
        receipt_hashes,
        chain_id,
        scope_hash,
    )
    base_changes = validate_base_attestations(
        payload, ledger_dir, receipt_hashes, closeout
    )
    any_unresolved = validate_finding_classes(
        payload, ledger_dir, receipt_findings, candidate, closeout
    )

    delta = payload["unreviewed_delta"]
    if not isinstance(delta, list):
        fail("unreviewed_delta must be an array")
    for index, value in enumerate(delta):
        bounded_text(value, f"unreviewed_delta[{index}]", 500)

    if closeout == "ready_for_human_decision" and completion is None:
        fail("ready_for_human_decision requires a completion receipt")
    if closeout == "continuation_authorization_required" and completion is not None:
        fail("continuation_authorization_required cannot carry a completion receipt")
    if closeout == "baseline_race" and completion is not None:
        fail("baseline_race cannot carry a completion receipt")

    controller_state = bounded_text(
        payload["controller_review_state"], "controller_review_state", 80
    )
    if controller_state not in KNOWN_REVIEW_STATES:
        fail(f"unknown controller review_state {controller_state}")
    derived_state = completion["review_state"] if completion is not None else receipts[-1]["review_state"]
    if controller_state != derived_state:
        fail("controller_review_state does not match the referenced final receipt")

    if closeout == "ready_for_human_decision":
        if len(receipts) < 2:
            fail("ready_for_human_decision ready requires at least one tracked challenge")
        if completion is None:
            fail("ready_for_human_decision requires a completion receipt")
        if completion["candidate_sha256"] != candidate or receipts[-1]["candidate_sha256"] != candidate:
            fail("ready_for_human_decision completion receipt must bind the exact final candidate")
        if any_unresolved or delta:
            fail("ready_for_human_decision requires no unresolved finding occurrence and no unreviewed delta")
    elif closeout == "continuation_authorization_required":
        final = receipts[-1]
        if (
            len(receipts) != 3
            or final.get("status") != "findings"
            or final.get("review_state") != "post_review_budget"
            or final.get("human_decision_required") is not True
        ):
            fail("continuation_authorization_required requires round 3 findings in post_review_budget")
    elif closeout == "baseline_race" and not delta:
        fail("baseline_race requires a non-empty unreviewed_delta")

    return closeout, len(payload["finding_classes"]), base_changes


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("state_file", type=Path)
    args = parser.parse_args()
    try:
        payload, ledger_dir = load(args.state_file)
        state, class_count, base_changes = validate(payload, ledger_dir)
    except StateError as exc:
        print(f"extraction_review_state_invalid: {exc}", file=sys.stderr)
        return 1
    except (OSError, UnicodeError, ValueError):
        print(
            "extraction_review_state_invalid: local evidence read or encoding failed",
            file=sys.stderr,
        )
        return 1
    print(
        "extraction_review_state_ok: "
        f"closeout_state={state} finding_classes={class_count} base_changes={base_changes}"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
