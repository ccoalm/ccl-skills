#!/usr/bin/env python3
from __future__ import annotations

import subprocess
import sys

CAPTURE_SIGNAL_EXIT = 198
CAPTURE_TIMEOUT_EXIT = 199


def main() -> int:
    if len(sys.argv) < 6:
        print(
            "usage: run_claude_capture.py TIMEOUT OUT ERR PROMPT_FILE COMMAND...",
            file=sys.stderr,
        )
        return 64

    timeout_s = float(sys.argv[1])
    output_file = sys.argv[2]
    err_file = sys.argv[3]
    prompt_file = sys.argv[4]
    cmd = sys.argv[5:]

    try:
        with open(prompt_file, "r", encoding="utf-8") as fh:
            prompt = fh.read()
    except OSError as exc:
        write_result(output_file, err_file, "", f"failed to read prompt file: {exc}")
        return 127

    try:
        result = subprocess.run(
            cmd,
            input=prompt,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=timeout_s,
            check=False,
        )
    except subprocess.TimeoutExpired as exc:
        stdout = exc.stdout or ""
        stderr = exc.stderr or ""
        if isinstance(stdout, bytes):
            stdout = stdout.decode("utf-8", errors="replace")
        if isinstance(stderr, bytes):
            stderr = stderr.decode("utf-8", errors="replace")
        write_result(output_file, err_file, stdout, stderr)
        return CAPTURE_TIMEOUT_EXIT
    except OSError as exc:
        write_result(output_file, err_file, "", str(exc))
        return 127

    write_result(output_file, err_file, result.stdout, result.stderr)
    if result.returncode < 0:
        with open(err_file, "a", encoding="utf-8") as err:
            err.write(f"\nClaude process terminated by signal {-result.returncode}\n")
        return CAPTURE_SIGNAL_EXIT
    return result.returncode


def write_result(output_file: str, err_file: str, stdout: str, stderr: str) -> None:
    with open(output_file, "w", encoding="utf-8") as out:
        out.write(stdout)
    with open(err_file, "w", encoding="utf-8") as err:
        err.write(stderr)


if __name__ == "__main__":
    raise SystemExit(main())
