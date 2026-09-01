#!/usr/bin/env python3
"""Mint and verify candidate-SHA-bound receipts of deterministic-gate output.

A gate receipt binds one deterministic command run to the exact committed
candidate state it ran against, so a historical-process claim ("the suite was
RED before the fix", "heavy lane was green at landing") can ride the review
packet as falsifiable evidence instead of implementer testimony.

Trust model (deliberately narrow — do not oversell in referencing surfaces):
- A receipt is candidate-bound, re-runnable CONSISTENCY evidence: anyone at
  the recorded commit can re-execute the command and compare exit code and
  output hash (`verify --rerun`).
- A receipt does NOT authenticate who ran the command or that the recorded
  output was not fabricated; the minter and the candidate author are the same
  party. Deterministic authority stays with CI re-running the gate on the
  actual branch. A receipt upgrades a process claim from "unverifiable" to
  "falsifiable"; it never substitutes for the CI lane.
- Minting refuses a dirty tree: an uncommitted candidate has no stable SHA to
  bind, and a receipt minted against drifting files would be unfalsifiable.

Commands run as given (argv, no shell). Receipts of RED runs are first-class:
`mint` records the exit code, it does not require success — a pre-fix RED
receipt is the canonical use case.

Usage:
  gate_receipt.py mint --out FILE [--tail-bytes N] [--timeout SECONDS] -- CMD [ARG...]
  gate_receipt.py verify FILE [--rerun [--exit-only] -- CMD [ARG...]]

A receipt is untrusted data, so `verify --rerun` NEVER executes the recorded
argv: the verifier supplies the command they intend to re-run, and the tool
compares it against the recorded argv (mismatch is a named rc 1) before
executing the verifier's own words. A hostile receipt can therefore misdescribe
a gate but cannot make the verifier run anything they did not type.

The receipt records the repository-relative working directory and re-runs
execute from it (same argv elsewhere is a different command). The candidate is
re-read after the run on both sides; HEAD or cleanliness moving mid-run refuses
a result. The output tail is OFF by default (--tail-bytes 0): exit code plus
output hash suffice for verification, and a verbatim excerpt would copy
whatever the gate printed — including a leaked token — into the ledger; opt in
deliberately, and receipts are created 0600.

Exit codes: 0 ok; 1 receipt fails verification (structural or rerun mismatch,
named reason on stderr); 2 usage/environment error (not a verdict on the
receipt: dirty tree, wrong checked-out candidate, timeout, bad invocation).
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import signal
import subprocess
import sys
import threading
import time
from datetime import datetime, timezone
from pathlib import Path

SCHEMA_VERSION = 1
KIND = "gate-receipt"
RECEIPT_KEYS = {
    "schema_version",
    "kind",
    "candidate_commit",
    "tree_clean",
    "cwd",
    "tail_bytes",
    "command",
    "exit_code",
    "output_bytes",
    "output_sha256",
    "output_tail",
    "minted_at",
}
MAX_RECEIPT_BYTES = 65536
MAX_TAIL_BYTES = 16384
COMMIT_RE = re.compile(r"^[0-9a-f]{40}([0-9a-f]{24})?$")
SHA256_RE = re.compile(r"^[0-9a-f]{64}$")
RFC3339_RE = re.compile(r"^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(\.\d+)?(Z|[+-]\d{2}:\d{2})$")


def infra(message: str) -> "int":
    print(f"gate_receipt_error: {message}", file=sys.stderr)
    return 2


def invalid(message: str) -> int:
    print(f"gate_receipt_invalid: {message}", file=sys.stderr)
    return 1


def git_output(args: list[str]) -> str:
    # Bytes in, tolerant decode out: with core.quotePath=false an untracked
    # filename holding invalid UTF-8 would make text-mode decoding raise, and
    # an uncaught decode error exits with the status reserved for a failed
    # receipt verdict. The callers only compare/strip this output, so
    # replacement characters are safe — non-empty stays non-empty.
    result = subprocess.run(["git", *args], capture_output=True, check=False)
    if result.returncode != 0:
        stderr = result.stderr.decode("utf-8", errors="replace").strip()
        raise RuntimeError(f"git {' '.join(args)} failed: {stderr}")
    return result.stdout.decode("utf-8", errors="replace")


def candidate_state() -> tuple[str, bool]:
    head = git_output(["rev-parse", "HEAD"]).strip()
    # Explicit flags: a repo config of status.showUntrackedFiles=no (or a
    # submodule-ignoring setting) would otherwise report clean while untracked
    # gate inputs exist — content absent from the recorded commit.
    porcelain = git_output(
        ["status", "--porcelain", "--untracked-files=all", "--ignore-submodules=none"]
    )
    return head, porcelain == ""


def repo_relative_cwd() -> str:
    """Current directory relative to the repository toplevel ('.' at the root).

    Recorded in the receipt so a re-run executes the command from the same
    place — the same argv from a different directory is a different command.
    """
    top = git_output(["rev-parse", "--show-toplevel"]).strip()
    rel = os.path.relpath(os.getcwd(), top)
    if rel == ".." or rel.startswith(".." + os.sep):
        raise RuntimeError("working directory escapes the repository toplevel")
    return rel


def bounded_utf8_tail(tail: bytes, budget: int) -> str:
    """Decode with replacement, then trim from the FRONT until the encoded
    UTF-8 size fits the budget — replacement characters can expand invalid
    bytes threefold, and a receipt whose own tail fails the verifier's size
    check would be minted broken."""
    text = tail.decode("utf-8", errors="replace")
    while text and len(text.encode("utf-8")) > budget:
        overshoot = len(text.encode("utf-8")) - budget
        text = text[max(1, overshoot // 4):]
    return text


def normalize_exit(code: int) -> int:
    """Map a signal-terminated child (negative Popen returncode) to the shell
    convention 128+N, so a legitimately RED signal-killed gate still yields a
    structurally valid receipt (0..255) and re-runs compare consistently."""
    if code < 0:
        return 128 + (-code)
    return code & 0xFF


def run_and_capture(command: list[str], tail_bytes: int, timeout: int, cwd: str | None = None):
    """Run argv, stream-hash combined stdout+stderr, keep a bounded tail.

    The child gets its own process group and /dev/null stdin; a reader thread
    drains the pipe while the main thread holds the deadline, so a silent
    hanging gate (or a descendant keeping the pipe open) cannot block past
    --timeout — on expiry the whole group is killed and no result is returned.
    """
    digest = hashlib.sha256()
    tail = bytearray()
    total = 0
    proc = subprocess.Popen(
        command,
        stdin=subprocess.DEVNULL,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        start_new_session=True,
        cwd=cwd,
    )
    assert proc.stdout is not None

    def drain() -> None:
        nonlocal total
        while True:
            chunk = proc.stdout.read(65536)
            if not chunk:
                break
            digest.update(chunk)
            total += len(chunk)
            tail.extend(chunk)
            if len(tail) > tail_bytes:
                del tail[: len(tail) - tail_bytes]

    reader = threading.Thread(target=drain, daemon=True)
    reader.start()
    deadline = time.monotonic() + timeout

    def kill_group() -> None:
        try:
            os.killpg(proc.pid, signal.SIGKILL)
        except (ProcessLookupError, PermissionError):
            proc.kill()

    try:
        exit_code = proc.wait(timeout=timeout)
    except subprocess.TimeoutExpired:
        kill_group()
        proc.wait()
        reader.join(timeout=10)
        raise
    # The child exited; the pipe closes only when every writer (including any
    # surviving descendant) has closed it. Give the reader the remaining
    # deadline, then treat a still-open pipe as a timeout: output would be
    # incomplete, so no receipt/verdict may be produced from it.
    reader.join(timeout=max(0.0, deadline - time.monotonic()))
    if reader.is_alive():
        kill_group()
        reader.join(timeout=10)
        raise subprocess.TimeoutExpired(command, timeout)
    return normalize_exit(exit_code), total, digest.hexdigest(), bytes(tail)


def mint(args: argparse.Namespace) -> int:
    out = Path(args.out)
    if not args.command:
        return infra("mint requires a command after --")
    if not (0 <= args.tail_bytes <= MAX_TAIL_BYTES):
        return infra(f"--tail-bytes must be in 0..{MAX_TAIL_BYTES}")
    try:
        head, clean = candidate_state()
        rel_cwd = repo_relative_cwd()
        top = git_output(["rev-parse", "--show-toplevel"]).strip()
    except RuntimeError as exc:
        return infra(str(exc))
    # The documented contract is receipts-outside-the-candidate-tree; enforce
    # it instead of trusting it. An in-tree receipt dirties the tree AFTER the
    # cleanliness checks ran (created last), so it would mint "successfully"
    # and then fail every re-run as dirty_tree — and a path under .git could
    # mutate repository metadata porcelain status never shows.
    out_abs = os.path.realpath(os.path.join(os.getcwd(), str(out)))
    top_real = os.path.realpath(top)
    if os.path.commonpath([top_real, out_abs]) == top_real:
        return infra(
            f"--out {out} resolves inside the candidate repository; "
            "write receipts OUTSIDE the tree (e.g. the chain ledger directory)"
        )
    if not clean:
        return infra(
            "tree not clean — a receipt binds to a committed candidate; "
            "commit first, then mint (and write receipts OUTSIDE the candidate "
            "tree, e.g. the chain ledger directory — an in-tree receipt dirties "
            "the tree it binds)"
        )
    try:
        exit_code, total, output_sha, tail = run_and_capture(
            args.command, args.tail_bytes, args.timeout
        )
    except FileNotFoundError as exc:
        return infra(f"command not found: {exc}")
    except subprocess.TimeoutExpired:
        return infra(f"command exceeded --timeout {args.timeout}s; no receipt minted")
    # Re-read the candidate AFTER the run: HEAD or cleanliness moving mid-run
    # (a concurrent checkout/rebase, or the gate itself committing) means the
    # output belongs to no single candidate — refuse rather than mislabel.
    try:
        head_after, clean_after = candidate_state()
    except RuntimeError as exc:
        return infra(str(exc))
    if head_after != head or not clean_after:
        return infra(
            "candidate changed during the run "
            f"(HEAD {head} -> {head_after}, clean={clean_after}); no receipt minted"
        )
    receipt = {
        "schema_version": SCHEMA_VERSION,
        "kind": KIND,
        "candidate_commit": head,
        "tree_clean": True,
        "cwd": rel_cwd,
        "command": list(args.command),
        "exit_code": exit_code,
        "output_bytes": total,
        "output_sha256": output_sha,
        "tail_bytes": args.tail_bytes,
        # Off by default: exit code + output hash suffice for verification, and
        # a verbatim tail would copy whatever the gate printed — including a
        # leaked token — into ledger/packet-adjacent evidence. Opt in with
        # --tail-bytes N when the excerpt is genuinely needed.
        "output_tail": bounded_utf8_tail(tail, args.tail_bytes) if args.tail_bytes else "",
        "minted_at": datetime.now(timezone.utc).isoformat(timespec="seconds"),
    }
    encoded = json.dumps(
        receipt, ensure_ascii=False, sort_keys=True, indent=1
    ).encode("utf-8")
    if len(encoded) + 1 > MAX_RECEIPT_BYTES:
        return infra(
            f"receipt would be {len(encoded) + 1} bytes, over the "
            f"{MAX_RECEIPT_BYTES} cap its own verifier enforces (oversized "
            "argv?); no receipt minted"
        )
    # Re-check containment AFTER the gate ran: a parent directory swapped to a
    # symlink into the repository between the pre-run check and this write
    # would otherwise land the receipt in-tree (O_NOFOLLOW guards only the
    # final component). A swap in the instant between this check and os.open
    # remains possible; anything able to race writes in the ledger directory
    # could already rewrite receipts, so that residue is inside the existing
    # trust boundary.
    out_abs = os.path.realpath(os.path.join(os.getcwd(), str(out)))
    if os.path.commonpath([top_real, out_abs]) == top_real:
        return infra(
            f"--out {out} resolves inside the candidate repository after the "
            "run (parent directory changed?); no receipt minted"
        )
    # Write a unique 0600 temp file in the destination directory, then publish
    # with a no-overwrite atomic link. A failed/partial write therefore never
    # occupies the final name (O_EXCL retries stay possible), and existence of
    # the final name is decided by the same syscall that creates it.
    tmp = Path(f"{out}.tmp.{os.getpid()}")
    open_flags = os.O_WRONLY | os.O_CREAT | os.O_EXCL
    open_flags |= getattr(os, "O_NOFOLLOW", 0)
    try:
        fd = os.open(tmp, open_flags, 0o600)
    except OSError as exc:
        return infra(f"cannot create temp receipt {tmp}: {exc}")
    publish_error: str | None = None
    try:
        with os.fdopen(fd, "wb") as handle:
            handle.write(encoded + b"\n")
        try:
            os.link(tmp, out)
        except FileExistsError:
            publish_error = f"--out {out} already exists; receipts are never overwritten"
        except OSError as exc:
            publish_error = f"cannot publish receipt {out}: {exc}"
    except OSError as exc:
        publish_error = f"failed to write receipt {tmp}: {exc}"
    finally:
        try:
            os.unlink(tmp)
        except OSError as exc:
            # Report honestly instead of claiming a clean state.
            cleanup_note = f"; temp file {tmp} could not be removed: {exc}"
            publish_error = (publish_error or "receipt published") + cleanup_note
            if publish_error.startswith("receipt published"):
                print(f"gate_receipt_warning: {cleanup_note.lstrip('; ')}", file=sys.stderr)
                publish_error = None
    if publish_error:
        return infra(publish_error)
    receipt_sha = hashlib.sha256(encoded + b"\n").hexdigest()
    print(
        f"gate_receipt_minted: {out} sha256={receipt_sha} "
        f"candidate={head} exit={exit_code}"
    )
    return 0


def load_receipt(path: Path) -> dict | int:
    """Return the parsed receipt dict, or an int exit code on failure."""
    if path.is_symlink() or not path.is_file():
        return infra(f"{path} must be a regular non-linked file")
    # Bounded no-follow read: never pull an oversized file into memory just to
    # discover it is over the cap.
    read_flags = os.O_RDONLY | getattr(os, "O_NOFOLLOW", 0)
    try:
        fd = os.open(path, read_flags)
    except OSError as exc:
        return infra(f"cannot open {path}: {exc}")
    with os.fdopen(fd, "rb") as handle:
        raw = handle.read(MAX_RECEIPT_BYTES + 1)
    if len(raw) > MAX_RECEIPT_BYTES:
        return invalid(f"receipt exceeds {MAX_RECEIPT_BYTES} bytes")
    try:
        payload = json.loads(raw.decode("utf-8"))
    except (UnicodeError, json.JSONDecodeError) as exc:
        return invalid(f"receipt is not valid UTF-8 JSON: {exc}")
    if not isinstance(payload, dict) or set(payload) != RECEIPT_KEYS:
        return invalid("receipt must contain exactly the gate-receipt key set")
    if payload["schema_version"] != SCHEMA_VERSION or type(payload["schema_version"]) is not int:
        return invalid("schema_version must be 1")
    if payload["kind"] != KIND:
        return invalid("kind must be gate-receipt")
    if not isinstance(payload["candidate_commit"], str) or not COMMIT_RE.match(
        payload["candidate_commit"]
    ):
        return invalid("candidate_commit must be a full lowercase git commit hash")
    if payload["tree_clean"] is not True:
        return invalid("tree_clean must be true — a dirty-tree receipt binds nothing")
    rel_cwd = payload["cwd"]
    if (
        not isinstance(rel_cwd, str)
        or not rel_cwd
        or os.path.isabs(rel_cwd)
        or ".." in rel_cwd.split("/")
    ):
        return invalid("cwd must be a repository-relative path with no parent escapes")
    command = payload["command"]
    if (
        not isinstance(command, list)
        or not command
        or not all(isinstance(part, str) for part in command)
        or not command[0]
    ):
        return invalid(
            "command must be a non-empty list of strings with a non-empty "
            "executable (later arguments may legitimately be empty)"
        )
    if type(payload["exit_code"]) is not int or not (0 <= payload["exit_code"] <= 255):
        return invalid("exit_code must be an integer in 0..255")
    if type(payload["output_bytes"]) is not int or payload["output_bytes"] < 0:
        return invalid("output_bytes must be a non-negative integer")
    if not isinstance(payload["output_sha256"], str) or not SHA256_RE.match(
        payload["output_sha256"]
    ):
        return invalid("output_sha256 must be 64 lowercase hex chars")
    tail_budget = payload["tail_bytes"]
    if type(tail_budget) is not int or not (0 <= tail_budget <= MAX_TAIL_BYTES):
        return invalid(f"tail_bytes must be an integer in 0..{MAX_TAIL_BYTES}")
    tail = payload["output_tail"]
    if not isinstance(tail, str) or len(tail.encode("utf-8")) > MAX_TAIL_BYTES:
        return invalid(f"output_tail must be a string of at most {MAX_TAIL_BYTES} UTF-8 bytes")
    if tail_budget == 0 and tail:
        return invalid("output_tail must be empty when tail_bytes is 0")
    if not isinstance(payload["minted_at"], str) or not RFC3339_RE.match(
        payload["minted_at"]
    ):
        return invalid("minted_at must be an RFC3339 timestamp")
    return payload


def verify(args: argparse.Namespace) -> int:
    path = Path(args.receipt)
    loaded = load_receipt(path)
    if isinstance(loaded, int):
        return loaded
    if not args.rerun:
        if args.exit_only:
            return infra("--exit-only requires --rerun")
        if args.command:
            return infra("a command after -- requires --rerun")
        print(f"gate_receipt_structural_ok: {path}")
        return 0
    # The receipt is untrusted input: never execute its recorded argv. The
    # verifier states the command; a mismatch against the record is a named
    # verification failure, and only the verifier-typed argv ever runs.
    supplied = list(args.command)
    if not supplied:
        return infra(
            "--rerun requires the expected gate command after -- ; "
            "re-running the receipt's own recorded argv would execute "
            "candidate-controlled input"
        )
    if supplied != loaded["command"]:
        return invalid(
            "command_mismatch: receipt records "
            f"{loaded['command']!r}, verifier supplied {supplied!r}"
        )
    try:
        head, clean = candidate_state()
    except RuntimeError as exc:
        return infra(str(exc))
    if head != loaded["candidate_commit"]:
        return infra(
            f"wrong_candidate: HEAD is {head}, receipt binds "
            f"{loaded['candidate_commit']} — check out the recorded commit to re-run"
        )
    if not clean:
        return infra("dirty_tree: re-run verification requires a clean tree")
    try:
        top = git_output(["rev-parse", "--show-toplevel"]).strip()
    except RuntimeError as exc:
        return infra(str(exc))
    rundir = os.path.normpath(os.path.join(top, loaded["cwd"]))
    # The recorded cwd is untrusted receipt data: resolve it and require the
    # REAL path to stay inside the repository — a committed in-repo symlink
    # pointing outside would otherwise make the verifier's relative argv
    # execute from an attacker-chosen external directory.
    top_real = os.path.realpath(top)
    rundir_real = os.path.realpath(rundir)
    if os.path.commonpath([top_real, rundir_real]) != top_real:
        return infra(
            f"recorded cwd resolves outside the repository: {loaded['cwd']}"
        )
    if not os.path.isdir(rundir_real):
        return infra(f"recorded cwd does not exist in this checkout: {loaded['cwd']}")
    try:
        # Capture the tail with the RECORDED budget so the reconstruction
        # below runs the exact pipeline mint ran — identical output bytes then
        # reconstruct byte-identically, with no window-shape divergence.
        exit_code, total, output_sha, observed_tail = run_and_capture(
            supplied, loaded["tail_bytes"], args.timeout, cwd=rundir
        )
    except FileNotFoundError as exc:
        return infra(f"command not found: {exc}")
    except subprocess.TimeoutExpired:
        return infra(f"re-run exceeded --timeout {args.timeout}s; no verdict")
    try:
        head_after, clean_after = candidate_state()
    except RuntimeError as exc:
        return infra(str(exc))
    if head_after != head or not clean_after:
        return infra(
            "candidate changed during the re-run "
            f"(HEAD {head} -> {head_after}, clean={clean_after}); no verdict"
        )
    if exit_code != loaded["exit_code"]:
        return invalid(
            f"exit_code_mismatch: observed {exit_code}, recorded {loaded['exit_code']}"
        )
    if not args.exit_only:
        if output_sha != loaded["output_sha256"]:
            return invalid(
                "output_hash_mismatch: observed "
                f"{output_sha}, recorded {loaded['output_sha256']} "
                f"(observed_bytes={total}, recorded_bytes={loaded['output_bytes']}); "
                "if the gate's output is legitimately nondeterministic, "
                "re-verify with --exit-only and say so in the referencing row"
            )
        # Every recorded field must be compared, or a forged value in it rides
        # a "full" pass: byte count exactly, and a non-empty recorded tail must
        # be a suffix of the observed output's decoded tail window.
        if total != loaded["output_bytes"]:
            return invalid(
                f"output_bytes_mismatch: observed {total}, "
                f"recorded {loaded['output_bytes']}"
            )
        # Reconstruct the tail with the SAME deterministic function and the
        # RECORDED budget, then require exact equality: a truncated, emptied,
        # or padded tail all fail — a suffix check would accept truncation and
        # an empty tail would skip comparison entirely.
        tail_budget = loaded["tail_bytes"]
        reconstructed = (
            bounded_utf8_tail(observed_tail, tail_budget) if tail_budget else ""
        )
        if reconstructed != loaded["output_tail"]:
            return invalid(
                "output_tail_mismatch: reconstructing the tail at the "
                f"recorded tail_bytes={tail_budget} does not reproduce the "
                "recorded output_tail (same capture window and trim pipeline "
                "as mint, so identical output implies identical tails)"
            )
    scope = "exit-only" if args.exit_only else "full"
    print(f"gate_receipt_rerun_ok: {path} scope={scope}")
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(prog="gate_receipt.py", add_help=True)
    sub = parser.add_subparsers(dest="mode", required=True)
    mint_parser = sub.add_parser("mint")
    mint_parser.add_argument("--out", required=True)
    mint_parser.add_argument("--tail-bytes", type=int, default=0)
    mint_parser.add_argument("--timeout", type=int, default=3600)
    verify_parser = sub.add_parser("verify")
    verify_parser.add_argument("receipt")
    verify_parser.add_argument("--rerun", action="store_true")
    verify_parser.add_argument("--exit-only", action="store_true")
    verify_parser.add_argument("--timeout", type=int, default=3600)
    # The gate command is everything after the first standalone `--`, split
    # BEFORE argparse sees it: argparse.REMAINDER is greedy and would swallow
    # flags like --rerun that appear between the positional and the `--`.
    argv = sys.argv[1:]
    command_tail: list[str] = []
    if "--" in argv:
        split_at = argv.index("--")
        command_tail = argv[split_at + 1:]
        argv = argv[:split_at]
    args = parser.parse_args(argv)
    args.command = command_tail
    # An environment failure (permission denied on the gate binary or the
    # receipt path, a vanished directory, a full disk) must never surface as
    # the exit status the CLI contract reserves for "the receipt failed
    # verification" — an uncaught traceback exits 1, which would be a false
    # verdict. Everything unexpected at the OS layer is rc 2, no verdict.
    try:
        if args.mode == "mint":
            return mint(args)
        return verify(args)
    except (OSError, UnicodeError) as exc:
        return infra(f"environment failure, no verdict: {exc}")


if __name__ == "__main__":
    sys.exit(main())
