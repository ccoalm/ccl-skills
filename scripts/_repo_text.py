#!/usr/bin/env python3
"""Shared single-line diagnostic escaping for untrusted repository text."""

from __future__ import annotations


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
