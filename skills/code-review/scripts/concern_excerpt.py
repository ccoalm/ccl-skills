#!/usr/bin/env python3
"""Bounded excerpt of concern-shaped text in a reviewer's malformed output.

A reviewer whose output fails the structured contract but still names a severity
or a `file:line` may be carrying a real finding, so the lane stops rather than
letting another client launder it into a pass. Without the text, that stop says
only "a finding exists, we will not tell you which" — the operator can neither
triage it nor recognize a false positive, and the documented reject-and-rerun
remediation runs blind.

The bound is the point. A raw verdict dump would be a new egress class: arbitrary
model prose that may echo the packet. Matched lines only, capped in count and
width, keeps the excerpt inside the class a schema-valid `findings` result already
persists (severity, file, line, failure path, smallest fix).

This module owns the concern pattern; `parse_cli_review.py` imports it rather than
keeping a second copy.
"""

from __future__ import annotations

import json
from pathlib import Path
import re
import sys

MAX_EXCERPT_LINES = 20
MAX_EXCERPT_LINE_CHARS = 200

CONCERN_RE = re.compile(
    r"(^|[^a-z0-9])(p[0-3]|blocker|critical|major|minor|high|medium|low)([^a-z0-9]|$)"
    r"|[a-z0-9_.-]*[./][a-z0-9_./-]*:[0-9]+"
    r"|(^|[^a-z0-9_./-])[a-z_][a-z0-9_.-]*:[0-9]+"
    r"|^CHECK\s+[a-z][a-z0-9_]*\s+\|"
    r'|"concern_results"\s*:',
    re.IGNORECASE | re.MULTILINE,
)


MAX_REASON_DETAIL_CHARS = 300


# A client error item can quote the frozen packet back at us, so anything
# relayed from one into durable evidence is redacted first. These cover the
# machine-detectable classes; broad semantic confidentiality stays operator-owned
# exactly as it is for the packet itself.
REDACTION_RES = (
    (re.compile(r"[a-z][a-z0-9+.-]*://\S+", re.IGNORECASE), "[url]"),
    (re.compile(r"(?<![\w/])/(?:[\w.-]+/){2,}[\w.-]*"), "[path]"),
    # Scheme-prefixed credentials first: `Authorization: Bearer abc123` puts a
    # space between the scheme and the secret, so an assignment pattern that
    # stops at the first whitespace redacts the label and leaves the token.
    # The value must look like a credential, not like the next English word:
    # `token validation bypassed` is diagnostic prose and must survive, while
    # `Bearer abc123def456` must not. Requiring a digit inside a long opaque run
    # separates them without a vocabulary list.
    (
        re.compile(
            r"\b(?:bearer|basic|token)\s+(?=[A-Za-z0-9._~+/=-]*\d)[A-Za-z0-9._~+/=-]{8,}",
            re.IGNORECASE,
        ),
        "[redacted]",
    ),
    # `\b` does not fire inside `client_secret` because `_` is a word character,
    # so the key name may carry any leading identifier characters.
    (
        re.compile(
            r"[\w.-]*(?:token|secret|password|passwd|api[_-]?key|authorization|bearer)"
            # An auth scheme may sit between the key and its value
            # (`Authorization: Bearer hunter2`); stopping at the first whitespace
            # redacts the scheme and leaves the credential, at any value length.
            r"\s*[:=]\s*(?:(?:bearer|basic|token)\s+)?\S+",
            re.IGNORECASE,
        ),
        "[redacted]",
    ),
    (re.compile(r"\b[A-Za-z0-9+/_-]{32,}={0,2}\b"), "[token]"),
    (re.compile(r"\b[\w.+-]+@[\w-]+\.[\w.-]+\b"), "[email]"),
)


def redact_untrusted(text: str) -> str:
    """Strip machine-detectable secret material from relayed client text."""
    for pattern, placeholder in REDACTION_RES:
        text = pattern.sub(placeholder, text)
    return text


def bounded_reason_detail(value: object) -> str:
    """A short, redacted, single-line rendering of untrusted client text.

    The point is to NAME the failure — which class of error item stopped the
    lane — not to relay a payload. Without it the operator gets "an item-level
    review error" and the events file is already gone; with it unredacted, a
    message echoing the packet would carry credentials into a durable evidence
    row the packet's own egress scan never covers.
    """
    if not isinstance(value, str) or not value.strip():
        return "(no message)"
    flattened = redact_untrusted(" ".join(value.split()))
    if len(flattened) > MAX_REASON_DETAIL_CHARS:
        return flattened[:MAX_REASON_DETAIL_CHARS] + "…"
    return flattened


def _json_concern_lines(text: str) -> list[str] | None:
    """Split a structured verdict into per-concern / per-finding lines.

    A reviewer that answers in one line of JSON would otherwise yield a single
    excerpt line clipped mid-sentence — the shape observed on the first real run
    this helper was used to diagnose. Splitting on the structure keeps every
    conclusion readable inside the same bounds.
    """
    stripped = text.strip()
    if not stripped.startswith("{"):
        return None
    try:
        payload = json.loads(stripped)
    except ValueError:
        return None
    if not isinstance(payload, dict):
        return None
    # Clients wrap the verdict in a transport envelope. Unwrap one layer so a
    # stream event carrying the verdict splits like a bare verdict does.
    for wrapper in ("structured_output", "result"):
        inner = payload.get(wrapper)
        if isinstance(inner, dict) and (
            "concern_results" in inner or "findings" in inner
        ):
            payload = inner
            break
    lines: list[str] = []
    results = payload.get("concern_results")
    if isinstance(results, list):
        for item in results:
            if isinstance(item, dict):
                lines.append(
                    f"{item.get('concern', '?')}: {item.get('conclusion', '')}".strip()
                )
    findings = payload.get("findings")
    if isinstance(findings, list):
        for item in findings:
            if isinstance(item, dict):
                lines.append(
                    " ".join(
                        str(item.get(key, ""))
                        for key in ("severity", "file", "line", "failure_path")
                    ).strip()
                )
    return [line for line in lines if line] or None


def _window_around_match(line: str) -> str:
    """Clip an over-long line to a window centred on what made it match.

    Taking the prefix is what a first draft does, and on a serialized event or
    JSONL line the match sits far past the cap — so the excerpt keeps the
    irrelevant framing and drops the finding, while still reporting concern
    evidence. Centre on the match instead, and mark both elided ends.
    """
    match = CONCERN_RE.search(line)
    if match is None:
        return line[:MAX_EXCERPT_LINE_CHARS]
    span = max(match.end() - match.start(), 1)
    padding = max((MAX_EXCERPT_LINE_CHARS - span) // 2, 0)
    start = max(match.start() - padding, 0)
    end = min(start + MAX_EXCERPT_LINE_CHARS, len(line))
    start = max(min(start, end - MAX_EXCERPT_LINE_CHARS), 0)
    window = line[start:end]
    return ("…" if start > 0 else "") + window + ("…" if end < len(line) else "")


SEVERITY_RE = re.compile(
    r"(?:^|[^a-z0-9])(p[0-3]|blocker|critical|major|minor|high|medium|low)"
    r"(?:[^a-z0-9]|$)",
    re.IGNORECASE,
)
LOCATOR_RE = re.compile(r"[a-z0-9_.-]*[./][a-z0-9_./-]*:[0-9]+", re.IGNORECASE)


def _shape_summary(lines: list[str]) -> list[str]:
    """Describe unstructured concern-shaped output without relaying its text.

    Five review rounds each found another credential shape surviving the redaction
    denylist (`Bearer hunter2`, `client_secret=…`, a scheme with a short value),
    while a sixth found the opposite — benign prose stripped of meaning. Chasing
    both edges of a denylist over arbitrary model prose does not converge, so the
    free-text relay is removed instead: when the client did NOT emit a structured
    verdict, report only tokens this module itself matched — severities and
    locators — never the surrounding text. Nothing the model wrote can ride out
    on this path, so no denylist has to be complete.

    A structured verdict still relays verbatim: that text is reviewer prose about
    the diff, the same class a schema-valid `findings` result already persists.
    """
    severities: list[str] = []
    locators: list[str] = []
    for line in lines:
        for match in SEVERITY_RE.finditer(line):
            token = match.group(1).upper()
            if token not in severities:
                severities.append(token)
        for match in LOCATOR_RE.finditer(line):
            token = match.group(0)
            if token not in locators and len(locators) < MAX_EXCERPT_LINES:
                locators.append(token)
    parts = [f"{len(lines)} concern-shaped line(s), text withheld"]
    if severities:
        parts.append("severities: " + ", ".join(severities[:MAX_EXCERPT_LINES]))
    if locators:
        parts.append("locators: " + ", ".join(redact_untrusted(x) for x in locators))
    return ["; ".join(parts)]


def concern_excerpt(text: str) -> tuple[list[str], bool]:
    """Return (excerpt lines, truncated) for `text`.

    Truncation is reported for both axes — dropped lines and clipped width — so a
    reader never mistakes a capped excerpt for the whole concern.
    """
    structured = _json_concern_lines(text or "")
    if structured is None:
        # A JSONL transcript is not one JSON document, so split each line that is
        # one. Without this the whole event line becomes a single clipped excerpt.
        collected: list[str] = []
        for raw in (text or "").splitlines():
            per_line = _json_concern_lines(raw)
            if per_line:
                collected.extend(per_line)
        structured = collected or None

    if structured is None:
        matched = [
            line.strip()
            for line in (text or "").splitlines()
            if line.strip() and CONCERN_RE.search(line)
        ]
        if not matched:
            return [], False
        return _shape_summary(matched), True

    lines: list[str] = []
    truncated = False
    for raw in structured:
        line = redact_untrusted(raw.strip())
        if not line:
            continue
        if len(lines) >= MAX_EXCERPT_LINES:
            truncated = True
            break
        if len(line) > MAX_EXCERPT_LINE_CHARS:
            line = _window_around_match(line)
            truncated = True
        lines.append(line)
    return lines, truncated


def concern_fields(text: str) -> dict[str, object]:
    """Payload fields for a concern-evidence stop.

    `concern_evidence` stays a union of the line scan and a whole-text scan: the
    two agree on every shape the pattern can express, but a stop that the old
    whole-text scan would have raised must never be downgraded by a change whose
    only job is to add evidence to it.
    """
    excerpt, truncated = concern_excerpt(text)
    evidence = bool(excerpt) or bool(CONCERN_RE.search(text or ""))
    fields: dict[str, object] = {"concern_evidence": evidence}
    if excerpt:
        fields["concern_excerpt"] = excerpt
        fields["concern_excerpt_truncated"] = truncated
    return fields


def main(argv: list[str]) -> int:
    """Read the verdict from the named files, or stdin when none are given."""
    if argv:
        chunks = []
        for name in argv:
            try:
                chunks.append(Path(name).read_text(encoding="utf-8", errors="replace"))
            except OSError:
                continue
        text = "\n".join(chunks)
    else:
        text = sys.stdin.read()
    fields = concern_fields(text)
    fields.setdefault("concern_excerpt", [])
    fields.setdefault("concern_excerpt_truncated", False)
    print(json.dumps(fields, ensure_ascii=False, separators=(",", ":")))
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
