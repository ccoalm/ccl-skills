#!/usr/bin/env python3
"""Fail when a tracked Markdown file references a missing local path."""

from __future__ import annotations

import os
import re
import subprocess
import sys
from pathlib import Path
from urllib.parse import unquote


REFERENCE_RE = re.compile(r"^\s{0,3}\[[^\]]+\]:\s*(.+)$")
INLINE_CODE_RE = re.compile(r"(`+).*?\1")
FENCE_RE = re.compile(r"^\s{0,3}(`{3,}|~{3,})")
SCHEME_RE = re.compile(r"^[A-Za-z][A-Za-z0-9+.-]*:")



def display(text: str) -> str:
    """Render untrusted repo text safe to print on one physical line.

    A tracked filename may legally contain a newline, an ANSI escape, or (after
    os.fsdecode) a surrogate for a byte that is not valid UTF-8. Interpolated
    raw, one filename splits a finding across two physical lines, so anything
    reading this output line by line — a human, a CI annotation parser — sees a
    forged line. Escaping is display-only; the value used for resolution is
    untouched. Printable non-ASCII (an ordinary CJK filename) is preserved.
    """
    # Backslash FIRST, then every non-printable character including tab:
    # otherwise the encoding is not reversible — a real newline and a filename
    # containing a literal backslash-n both render as the same two characters,
    # so two distinct tracked paths produce an identical diagnostic. Printable
    # non-ASCII (an ordinary CJK filename) is preserved.
    escaped = text.replace("\\", "\\\\")
    return "".join(ch if ch.isprintable() else repr(ch)[1:-1] for ch in escaped)

def tracked_markdown_paths(root: Path) -> list[Path]:
    result = subprocess.run(
        ["git", "-C", str(root), "ls-files", "-z", "--", "*.md"],
        check=True,
        capture_output=True,
    )
    # os.fsdecode, not a strict decode: git tracks raw bytes and Linux allows a
    # filename that is not valid UTF-8, which made every one of these three
    # checkers crash with a traceback before scanning anything. macOS rejects
    # such names outright, so it is unreachable on this team's own machines and
    # reachable on the ubuntu CI runner. surrogateescape round-trips back to the
    # original bytes when the path is opened, so the file is still scanned.
    return [root / os.fsdecode(item) for item in result.stdout.split(b"\0") if item]


def destination(raw: str) -> str:
    value = raw.strip()
    if value.startswith("<"):
        end = value.find(">")
        return value[1:end] if end >= 0 else value
    return value.split(maxsplit=1)[0]


def inline_destinations(line: str) -> list[str]:
    """Return Markdown inline-link destinations, including balanced parentheses."""
    targets: list[str] = []
    offset = 0
    while True:
        marker = line.find("](", offset)
        if marker < 0:
            return targets

        cursor = marker + 2
        while cursor < len(line) and line[cursor].isspace():
            cursor += 1
        if cursor < len(line) and line[cursor] == "<":
            end = line.find(">", cursor + 1)
            if end >= 0:
                targets.append(line[cursor : end + 1])
                offset = end + 1
                continue

        value: list[str] = []
        depth = 0
        while cursor < len(line):
            character = line[cursor]
            if character == "\\" and cursor + 1 < len(line):
                value.append(line[cursor + 1])
                cursor += 2
                continue
            if character == "(":
                depth += 1
            elif character == ")":
                if depth == 0:
                    break
                depth -= 1
            elif character.isspace() and depth == 0:
                break
            value.append(character)
            cursor += 1

        if value:
            targets.append("".join(value))
        offset = max(cursor + 1, marker + 2)


def missing_local_target(root: Path, source: Path, target: str) -> bool:
    if not target or target.startswith(("#", "//")) or SCHEME_RE.match(target):
        return False
    local = unquote(target.split("#", 1)[0].split("?", 1)[0])
    if not local:
        return False
    resolved = (source.parent / local).resolve()
    try:
        relative = resolved.relative_to(root)
    except ValueError:
        return True
    current = root
    for part in relative.parts:
        try:
            names = {child.name for child in current.iterdir()}
        except OSError:
            return True
        if part not in names:
            return True
        current /= part
    return False


def broken_links(root: Path) -> list[tuple[str, int, str]]:
    root = root.resolve()
    findings: list[tuple[str, int, str]] = []
    for path in tracked_markdown_paths(root):
        relative = path.relative_to(root).as_posix()
        fence: str | None = None
        for line_number, original in enumerate(
            path.read_text(encoding="utf-8", errors="replace").splitlines(), 1
        ):
            fence_match = FENCE_RE.match(original)
            if fence is not None:
                if (
                    fence_match
                    and fence_match.group(1)[0] == fence[0]
                    and len(fence_match.group(1)) >= len(fence)
                    and not original[fence_match.end() :].strip()
                ):
                    fence = None
                continue
            if fence_match:
                fence = fence_match.group(1)
                continue
            if original.startswith(("    ", "\t")):
                continue

            line = INLINE_CODE_RE.sub("", original)
            raw_targets = inline_destinations(line)
            reference = REFERENCE_RE.match(line)
            if reference:
                raw_targets.append(reference.group(1))
            for raw_target in raw_targets:
                target = destination(raw_target)
                if missing_local_target(root, path, target):
                    findings.append((relative, line_number, target))
    return findings


def main() -> int:
    root = Path(sys.argv[1] if len(sys.argv) > 1 else ".").resolve()
    findings = broken_links(root)
    if findings:
        for path, line_number, target in findings:
            print(
                f"{display(path)}:{line_number}: missing local Markdown target: {display(target)}"
            )
        print(f"markdown_link_check_failed: {len(findings)} broken link(s)")
        return 1
    print("markdown_link_check_ok: tracked local Markdown targets exist")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
