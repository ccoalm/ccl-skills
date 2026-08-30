#!/usr/bin/env python3
"""Append or compact bounded intent without lossy truncation.

The caller owns writer serialization and provides a trusted, stable parent
directory. ``--expected-sha256`` rejects input that was already stale when
opened; it is not a lock against concurrent writers.
"""

from __future__ import annotations

import argparse
import base64
import hashlib
import json
import os
import re
import stat
import sys
import tempfile
from pathlib import Path
from typing import NoReturn


MIN_INTENT_CHARS = 8
MAX_INTENT_CHARS = 4000
MAX_PLAN_BYTES = 32_000
PLAN_FIELDS = {"intent", "acceptance", "self_review", "evidence"}
SHA256_RE = re.compile(r"[0-9a-f]{64}")
STABLE_CORE_EVIDENCE_ID = "review-plan-intent-stable-core-v1"
STABLE_CORE_RESULT_RE = re.compile(r"chars=([1-9][0-9]{0,3});sha256=([0-9a-f]{64})")
HISTORY_EVIDENCE_PREFIX = "review-plan-intent-history-v1"
HISTORY_BASE64_CHUNK_CHARS = 1800
MAX_EVIDENCE_ROWS = 50


class UpdateError(Exception):
    def __init__(self, reason: str, detail: str) -> None:
        super().__init__(detail)
        self.reason = reason
        self.detail = detail


class DuplicateKeyError(ValueError):
    pass


def reject_duplicate_keys(pairs: list[tuple[str, object]]) -> dict[str, object]:
    result: dict[str, object] = {}
    for key, value in pairs:
        if key in result:
            raise DuplicateKeyError
        result[key] = value
    return result


def fail(reason: str, detail: str) -> NoReturn:
    raise UpdateError(reason, detail)


def read_regular(path: Path, *, label: str, max_bytes: int) -> tuple[bytes, int]:
    if not hasattr(os, "O_NOFOLLOW") or not hasattr(os, "O_NONBLOCK"):
        fail(
            f"{label}_unsupported",
            "this platform cannot safely open files without following links or blocking on special files",
        )
    flags = os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK | getattr(os, "O_CLOEXEC", 0)
    fd = -1
    try:
        fd = os.open(path, flags)
    except OSError as exc:
        fail(f"{label}_unreadable", str(exc))
    try:
        info = os.fstat(fd)
        if not stat.S_ISREG(info.st_mode):
            fail(f"{label}_not_regular", "expected a regular, non-symlink file")
        if info.st_nlink != 1:
            fail(f"{label}_hardlinked", "refusing a multiply-linked file")
        if label == "plan" and hasattr(os, "geteuid") and info.st_uid != os.geteuid():
            fail("plan_not_owned", "the plan must be owned by the current user")
        if info.st_size > max_bytes:
            fail(f"{label}_too_large", f"maximum is {max_bytes} bytes")
        with os.fdopen(fd, "rb") as handle:
            fd = -1
            chunks: list[bytes] = []
            remaining = max_bytes + 1
            while remaining:
                chunk = handle.read(min(65_536, remaining))
                if not chunk:
                    break
                chunks.append(chunk)
                remaining -= len(chunk)
            data = b"".join(chunks)
    except OSError as exc:
        fail(f"{label}_unreadable", str(exc))
    finally:
        if fd >= 0:
            os.close(fd)
    if len(data) > max_bytes:
        fail(f"{label}_too_large", f"maximum is {max_bytes} bytes")
    return data, stat.S_IMODE(info.st_mode)


def decode_utf8(data: bytes, *, label: str) -> str:
    try:
        return data.decode("utf-8")
    except UnicodeDecodeError as exc:
        fail(f"{label}_invalid_utf8", f"invalid UTF-8 at byte {exc.start}")


def digest(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def normalized_intent(
    value: object, *, reason_prefix: str, minimum: int = MIN_INTENT_CHARS
) -> str:
    if not isinstance(value, str):
        fail(f"{reason_prefix}_not_string", "intent must be a string")
    stripped = value.strip()
    if value != stripped:
        fail(f"{reason_prefix}_not_normalized", "intent must not have outer whitespace")
    if len(value) < minimum:
        fail(f"{reason_prefix}_too_short", f"minimum is {minimum} characters")
    return value


def remove_file_line_ending(value: str) -> str:
    """Remove only the one line ending used as a text-file delimiter."""
    if value.endswith("\r\n"):
        return value[:-2]
    if value.endswith(("\n", "\r")):
        return value[:-1]
    return value


def render_plan(plan: dict[str, object]) -> bytes:
    try:
        encoded = (json.dumps(plan, ensure_ascii=False, indent=2) + "\n").encode(
            "utf-8"
        )
    except UnicodeEncodeError as exc:
        fail("updated_plan_invalid_unicode", f"cannot encode UTF-8 at character {exc.start}")
    if len(encoded) > MAX_PLAN_BYTES:
        fail("updated_plan_too_large", f"maximum is {MAX_PLAN_BYTES} bytes")
    return encoded


def stable_core_identity(plan: dict[str, object]) -> tuple[int, str]:
    evidence = plan.get("evidence")
    if not isinstance(evidence, list):
        fail("intent_core_identity_missing", "plan evidence has no stable-core identity")
    records = [
        item
        for item in evidence
        if isinstance(item, dict) and item.get("id") == STABLE_CORE_EVIDENCE_ID
    ]
    if not records:
        fail("intent_core_identity_missing", "plan evidence has no stable-core identity")
    if len(records) != 1:
        fail("intent_core_identity_invalid", "plan must contain exactly one stable-core identity")
    record = records[0]
    if set(record) != {"id", "result"} or not isinstance(record.get("result"), str):
        fail("intent_core_identity_invalid", "stable-core identity has an invalid schema")
    match = STABLE_CORE_RESULT_RE.fullmatch(record["result"])
    if match is None:
        fail("intent_core_identity_invalid", "stable-core identity has an invalid encoding")
    core_chars = int(match.group(1))
    if not MIN_INTENT_CHARS <= core_chars <= MAX_INTENT_CHARS:
        fail(
            "intent_core_identity_invalid",
            f"stable-core character length must be between {MIN_INTENT_CHARS} and {MAX_INTENT_CHARS}",
        )
    return core_chars, match.group(2)


def text_digest(value: str, *, reason: str, label: str) -> str:
    try:
        return digest(value.encode("utf-8"))
    except UnicodeEncodeError as exc:
        fail(reason, f"{label} cannot encode as UTF-8 at character {exc.start}")


def archive_discarded_intent(
    plan: dict[str, object], *, old_intent: str, core: str
) -> None:
    """Retain the exact old intent bytes before compacting its visible field."""
    suffix = old_intent[len(core) :]
    if not suffix:
        return
    evidence = plan.get("evidence")
    if not isinstance(evidence, list):
        fail("intent_history_invalid", "plan evidence must be an array")
    used_ids = {
        item.get("id")
        for item in evidence
        if isinstance(item, dict) and isinstance(item.get("id"), str)
    }
    group = None
    for group_number in range(1, MAX_EVIDENCE_ROWS + 1):
        candidate_group = f"{group_number:04d}"
        candidate_prefix = f"{HISTORY_EVIDENCE_PREFIX}-{candidate_group}"
        if not any(
            evidence_id == f"{candidate_prefix}-manifest"
            or evidence_id.startswith(f"{candidate_prefix}-part-")
            for evidence_id in used_ids
        ):
            group = candidate_group
            break
    if group is None:
        fail("intent_history_full", "no unique intent-history evidence group remains")
    try:
        old_bytes = old_intent.encode("utf-8")
        suffix_bytes = suffix.encode("utf-8")
    except UnicodeEncodeError as exc:
        fail(
            "intent_history_invalid_unicode",
            f"old intent cannot encode as UTF-8 at character {exc.start}",
        )
    encoded_suffix = base64.b64encode(suffix_bytes).decode("ascii")
    chunks = [
        encoded_suffix[index : index + HISTORY_BASE64_CHUNK_CHARS]
        for index in range(0, len(encoded_suffix), HISTORY_BASE64_CHUNK_CHARS)
    ]
    prefix = f"{HISTORY_EVIDENCE_PREFIX}-{group}"
    rows: list[dict[str, str]] = [
        {
            "id": f"{prefix}-manifest",
            "result": (
                f"format={HISTORY_EVIDENCE_PREFIX};"
                f"old_chars={len(old_intent)};"
                f"old_sha256={hashlib.sha256(old_bytes).hexdigest()};"
                f"core_chars={len(core)};"
                f"suffix_bytes={len(suffix_bytes)};"
                f"suffix_sha256={hashlib.sha256(suffix_bytes).hexdigest()};"
                f"encoding=base64-utf8;parts={len(chunks)}"
            ),
        }
    ]
    rows.extend(
        {
            "id": f"{prefix}-part-{part_number:04d}",
            "result": (
                f"format={HISTORY_EVIDENCE_PREFIX};group={group};"
                f"part={part_number}/{len(chunks)};data={chunk}"
            ),
        }
        for part_number, chunk in enumerate(chunks, start=1)
    )
    if len(evidence) + len(rows) > MAX_EVIDENCE_ROWS:
        fail(
            "intent_history_evidence_overflow",
            f"zero-loss compaction needs {len(rows)} history rows but the plan "
            f"would exceed {MAX_EVIDENCE_ROWS} evidence rows",
        )
    plan["evidence"] = [*evidence, *rows]


def atomic_replace(path: Path, data: bytes, mode: int) -> None:
    fd = -1
    temp_path: Path | None = None
    try:
        try:
            fd, raw_temp = tempfile.mkstemp(prefix=f".{path.name}.", dir=path.parent)
            temp_path = Path(raw_temp)
            with os.fdopen(fd, "wb") as handle:
                fd = -1
                handle.write(data)
                handle.flush()
                os.fchmod(handle.fileno(), mode)
                os.fsync(handle.fileno())
        except OSError as exc:
            fail("plan_write_failed", str(exc))
        try:
            os.replace(temp_path, path)
            temp_path = None
        except OSError as exc:
            fail("plan_write_failed", str(exc))
        try:
            directory_flags = (
                os.O_RDONLY
                | getattr(os, "O_DIRECTORY", 0)
                | getattr(os, "O_CLOEXEC", 0)
            )
            directory_fd = os.open(path.parent, directory_flags)
            try:
                os.fsync(directory_fd)
            finally:
                os.close(directory_fd)
        except OSError as exc:
            fail(
                "plan_committed_durability_unknown",
                f"the target was replaced with sha256={digest(data)} but directory sync failed ({exc}); re-read the plan and do not retry blindly",
            )
    finally:
        cleanup_errors: list[str] = []
        if fd >= 0:
            try:
                os.close(fd)
            except OSError as exc:
                cleanup_errors.append(f"close failed: {exc}")
        if temp_path is not None:
            try:
                temp_path.unlink()
            except FileNotFoundError:
                pass
            except OSError as exc:
                cleanup_errors.append(f"temporary-file removal failed: {exc}")
        if cleanup_errors:
            active_error = sys.exc_info()[1]
            detail = "; ".join(cleanup_errors)
            if isinstance(active_error, UpdateError):
                detail = (
                    f"{detail}; original failure was {active_error.reason}: "
                    f"{active_error.detail}"
                )
            raise UpdateError("plan_cleanup_failed", detail)


def parse_args(argv: list[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description=(
            "Update a review plan intent without lossy truncation. Overflow is "
            "an error and leaves the plan unchanged."
        )
    )
    parser.add_argument("--plan", required=True, type=Path)
    parser.add_argument("--append-intent-file", type=Path)
    parser.add_argument("--compact-core-intent-file", type=Path)
    parser.add_argument("--latest-intent-file", type=Path)
    parser.add_argument(
        "--expected-sha256",
        help="optional stale-input guard for the current plan bytes",
    )
    return parser.parse_args(argv)


def run(argv: list[str]) -> int:
    args = parse_args(argv)
    append_mode = args.append_intent_file is not None
    compact_mode = (
        args.compact_core_intent_file is not None or args.latest_intent_file is not None
    )
    if append_mode == compact_mode or (
        compact_mode
        and (
            args.compact_core_intent_file is None
            or args.latest_intent_file is None
        )
    ):
        fail(
            "intent_update_mode_invalid",
            "choose append, or supply both compact core and latest intent files",
        )
    plan_bytes, plan_mode = read_regular(
        args.plan, label="plan", max_bytes=MAX_PLAN_BYTES
    )
    if plan_mode & 0o7000:
        fail("plan_mode_unsupported", "setuid, setgid, and sticky plan modes are unsupported")
    plan_mode &= 0o777
    current_digest = digest(plan_bytes)
    if args.expected_sha256 is not None:
        expected = args.expected_sha256.lower()
        if SHA256_RE.fullmatch(expected) is None:
            fail("expected_sha256_invalid", "expected exactly 64 hexadecimal characters")
        if expected != current_digest:
            fail("plan_digest_mismatch", "the plan changed after the caller read it")

    try:
        plan = json.loads(
            decode_utf8(plan_bytes, label="plan"),
            object_pairs_hook=reject_duplicate_keys,
        )
    except DuplicateKeyError:
        fail("plan_duplicate_key", "duplicate JSON object keys are unsupported")
    except json.JSONDecodeError as exc:
        fail("plan_invalid_json", f"JSON parse failed at line {exc.lineno} column {exc.colno}")
    if not isinstance(plan, dict) or set(plan) != PLAN_FIELDS:
        fail("plan_schema_invalid", "top-level fields must be intent, acceptance, self_review, evidence")
    old_intent = normalized_intent(plan["intent"], reason_prefix="plan_intent")

    if append_mode:
        if len(old_intent) > MAX_INTENT_CHARS:
            fail("plan_intent_overflow", f"maximum is {MAX_INTENT_CHARS} characters")
        incoming_bytes, _ = read_regular(
            args.append_intent_file, label="intent_input", max_bytes=MAX_PLAN_BYTES
        )
        incoming = remove_file_line_ending(
            decode_utf8(incoming_bytes, label="intent_input")
        )
        if not incoming:
            fail("intent_append_empty", "append input must not be empty")
        candidate = old_intent + incoming
        reason_prefix = "intent_append"
    else:
        core_bytes, _ = read_regular(
            args.compact_core_intent_file,
            label="intent_core",
            max_bytes=MAX_PLAN_BYTES,
        )
        latest_bytes, _ = read_regular(
            args.latest_intent_file,
            label="intent_latest",
            max_bytes=MAX_PLAN_BYTES,
        )
        core = normalized_intent(
            remove_file_line_ending(decode_utf8(core_bytes, label="intent_core")),
            reason_prefix="intent_core",
        )
        latest = normalized_intent(
            remove_file_line_ending(decode_utf8(latest_bytes, label="intent_latest")),
            reason_prefix="intent_latest",
            minimum=1,
        )
        if not old_intent.startswith(core):
            fail(
                "intent_core_not_preserved",
                "compact core must be an exact prefix of the current intent",
            )
        if latest in old_intent:
            fail(
                "intent_latest_not_new",
                "latest transition is already present in the current intent",
            )
        core_chars, core_sha256 = stable_core_identity(plan)
        if len(old_intent) < core_chars:
            fail(
                "plan_core_identity_mismatch",
                "current intent is shorter than its persisted stable-core identity",
            )
        persisted_core = old_intent[:core_chars]
        if text_digest(
            persisted_core,
            reason="plan_core_identity_mismatch",
            label="persisted stable core",
        ) != core_sha256:
            fail(
                "plan_core_identity_mismatch",
                "persisted stable-core identity does not match the current intent",
            )
        if len(core) != core_chars or text_digest(
            core,
            reason="intent_core_identity_mismatch",
            label="compact core",
        ) != core_sha256:
            fail(
                "intent_core_identity_mismatch",
                "compact core does not match the plan's persisted stable-core identity",
            )
        archive_discarded_intent(plan, old_intent=old_intent, core=core)
        candidate = f"{core}\n\n{latest}"
        reason_prefix = "intent_compact"

    candidate = normalized_intent(candidate, reason_prefix=reason_prefix)
    if len(candidate) > MAX_INTENT_CHARS:
        fail(
            f"{reason_prefix}_overflow",
            f"candidate has {len(candidate)} characters; maximum is {MAX_INTENT_CHARS}; rebuild intent as core + latest and keep history in evidence/prior results",
        )

    plan["intent"] = candidate
    updated = render_plan(plan)
    atomic_replace(args.plan, updated, plan_mode)
    # flush inside the guarded path: without it the receipt sits in the stdout
    # buffer and a closed pipe only surfaces BrokenPipeError at interpreter
    # shutdown, after main() returned rc 0 and past its handler.
    print(
        "review_plan_intent_updated "
        f"mode={'append' if append_mode else 'compact'} "
        f"chars={len(candidate)} old_sha256={current_digest} new_sha256={digest(updated)}",
        flush=True,
    )
    return 0


def main() -> int:
    try:
        return run(sys.argv[1:])
    except UpdateError as exc:
        print(
            f"review_plan_intent_error: reason={exc.reason} detail={exc.detail}",
            file=sys.stderr,
        )
        return 2
    except (BrokenPipeError, OSError):
        # The success receipt is printed (flushing) only after atomic_replace
        # committed, and every other file operation converts its OSError to
        # UpdateError, so an OS-level error here means the receipt was lost on
        # a closed/broken stdout — not that the update failed. rc 0 with no
        # receipt would read as "no update happened"; report the committed-but-
        # unreported state the same way a failed durability sync does.
        try:
            print(
                "review_plan_intent_error: reason=plan_committed_receipt_lost "
                "detail=stdout closed before the success receipt was delivered; "
                "re-read the plan for the committed state and do not retry blindly",
                file=sys.stderr,
            )
            sys.stderr.flush()
        except (BrokenPipeError, OSError):
            pass
        # Point stdout at devnull so the interpreter's shutdown flush of the
        # broken pipe cannot override this exit status with 120.
        try:
            devnull = os.open(os.devnull, os.O_WRONLY)
            os.dup2(devnull, sys.stdout.fileno())
            os.close(devnull)
        except (OSError, ValueError):
            pass
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
