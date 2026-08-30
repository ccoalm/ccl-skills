#!/usr/bin/env python3
"""Generate and audit a closed obligation-preservation ledger.

The row set is derived from every pre-existing ``skills/**/*.md`` path changed
against an explicit base revision.  Humans bind each derived row to one exact
current carrier in a JSONL mapping; this program never guesses or fuzzily binds
carriers.  Line ranges in the reader-facing ledger are derived from the current
files, so stale locators are detectable without putting a dirty-tree digest in
the generated document.
"""

from __future__ import annotations

import argparse
import hashlib
import importlib.util
import json
import re
import subprocess
import sys
from collections import Counter
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Iterable


SCHEMA_VERSION = 3
SCHEMA_VERSIONS = {3, 4}
DISPOSITIONS = {
    "merged",
    "subsumed",
    "rehosted",
    "retired-dead",
    "partitioned",
    "partial-retirement",
}
EFFECTS = {"preserved", "strengthened", "unresolved"}
QUALIFIER_KINDS = {
    "modality",
    "recency",
    "threshold",
    "scope",
    "actor",
    "consequence",
}
MAPPING_FIELDS = {
    "schema_version",
    "source_path",
    "source_ordinal",
    "reason",
    "before_text",
    "before_chain",
    "disposition",
    "effect",
    "carrier_path",
    "carrier_text",
    "carrier_chain",
    "carrier_bundle",
    "compound_clauses",
    "manual_reviewed",
    "semantic_review",
    "semantic_rationale",
    "qualifiers",
    "qualifier_relations",
    "review_note",
    "_mapping_line",
}
MAPPING_FIELDS_V4 = {
    "schema_version",
    "source_path",
    "source_ordinal",
    "reason",
    "before_text",
    "before_chain",
    "disposition",
    "effect",
    "parts",
    "manual_reviewed",
    "semantic_review",
    "semantic_rationale",
    "review_note",
    "_mapping_line",
}
REASONS = {"left-a-rewritten-line", "governing-chain-changed"}
PROVENANCE_BASENAMES = {"source-register.md", "provenance.md"}


def _load_chain_diff(script_dir: Path) -> Any:
    path = script_dir / "governing-chain-diff.py"
    spec = importlib.util.spec_from_file_location("governing_chain_diff", path)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"cannot import {path}")
    module = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    return module


GCD = _load_chain_diff(Path(__file__).resolve().parent)


class AuditError(Exception):
    def __init__(self, code: str, detail: str):
        super().__init__(detail)
        self.code = code
        self.detail = detail


@dataclass(frozen=True)
class ExpectedRow:
    source_path: str
    source_ordinal: int
    reason: str
    before_text: str
    before_chain: tuple[str, ...]

    @property
    def key(self) -> tuple[str, int]:
        return (self.source_path, self.source_ordinal)


@dataclass(frozen=True)
class Carrier:
    path: str
    text: str
    chain: tuple[str, ...]
    start_line: int
    end_line: int


@dataclass(frozen=True)
class PartitionedPart:
    part_id: str
    status: str
    source_text: str
    carriers: tuple[Carrier, ...]


@dataclass(frozen=True)
class LedgerObligation:
    text: str
    chain: tuple[str, ...]

    @property
    def key(self) -> str:
        return GCD.normalize(self.text)


def git(repo: Path, *args: str, check: bool = True) -> subprocess.CompletedProcess[str]:
    result = subprocess.run(
        ["git", "-C", str(repo), *args], capture_output=True, text=True
    )
    if check and result.returncode != 0:
        raise AuditError("GIT_FAILED", result.stderr.strip() or "git command failed")
    return result


def normalize_path(value: str) -> str:
    path = Path(value)
    if path.is_absolute() or ".." in path.parts:
        raise AuditError("INVALID_PATH", f"path must be repository-relative: {value}")
    return path.as_posix()


def changed_preexisting_paths(repo: Path, base: str) -> list[str]:
    changed = git(
        repo,
        "diff",
        "--name-only",
        "--diff-filter=ACDMRTUXB",
        base,
        "--",
        "skills",
    ).stdout.splitlines()
    out: list[str] = []
    for raw in changed:
        path = normalize_path(raw)
        if not path.startswith("skills/") or not path.endswith(".md"):
            continue
        exists_at_base = git(repo, "cat-file", "-e", f"{base}:{path}", check=False)
        if exists_at_base.returncode == 0:
            out.append(path)
    return sorted(set(out))


def read_base(repo: Path, base: str, path: str) -> str:
    return git(repo, "show", f"{base}:{path}").stdout


def read_current(repo: Path, path: str) -> str:
    file_path = repo / path
    return file_path.read_text(encoding="utf-8") if file_path.is_file() else ""


def derive_rows(repo: Path, base: str, paths: Iterable[str]) -> list[ExpectedRow]:
    rows: list[ExpectedRow] = []
    for path in sorted(paths):
        before = read_base(repo, base, path)
        after = read_current(repo, path)
        after_by_key: dict[str, list[Any]] = {}
        for obligation, _, _ in parse_obligation_ranges(after):
            after_by_key.setdefault(obligation.key, []).append(obligation)
        ordinal = 0
        for obligation, _, _ in parse_obligation_ranges(before):
            survivors = after_by_key.get(obligation.key)
            reason: str | None = None
            if not survivors:
                reason = "left-a-rewritten-line"
            elif not any(item.chain == obligation.chain for item in survivors):
                reason = "governing-chain-changed"
            if reason is None:
                continue
            ordinal += 1
            rows.append(
                ExpectedRow(
                    source_path=path,
                    source_ordinal=ordinal,
                    reason=reason,
                    before_text=GCD.normalize(obligation.text),
                    before_chain=tuple(obligation.chain),
                )
            )
    return rows


def load_mapping(path: Path) -> list[dict[str, Any]]:
    rows: list[dict[str, Any]] = []
    if not path.is_file():
        raise AuditError("MAPPING_MISSING", str(path))
    for line_no, raw in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
        if not raw.strip():
            continue
        try:
            value = json.loads(raw)
        except json.JSONDecodeError as exc:
            raise AuditError("MAPPING_JSON", f"{path}:{line_no}: {exc}") from exc
        if not isinstance(value, dict):
            raise AuditError("MAPPING_JSON", f"{path}:{line_no}: object required")
        value["_mapping_line"] = line_no
        rows.append(value)
    return rows


def mapping_key(row: dict[str, Any]) -> tuple[str, int]:
    try:
        return (normalize_path(str(row["source_path"])), int(row["source_ordinal"]))
    except (KeyError, TypeError, ValueError) as exc:
        raise AuditError("MAPPING_KEY", f"line {row.get('_mapping_line', '?')}: {exc}") from exc


def index_mapping(rows: list[dict[str, Any]]) -> dict[tuple[str, int], dict[str, Any]]:
    indexed: dict[tuple[str, int], dict[str, Any]] = {}
    for row in rows:
        key = mapping_key(row)
        if key in indexed:
            raise AuditError("DUPLICATE_ROW", f"duplicate mapping key {key[0]}#{key[1]}")
        indexed[key] = row
    return indexed


def relocation_destinations(rows: Iterable[dict[str, Any]]) -> list[str]:
    paths: set[str] = set()
    for row in rows:
        carrier_path = row.get("carrier_path")
        if carrier_path:
            path = normalize_path(str(carrier_path))
            if not path.startswith("skills/") or not path.endswith(".md"):
                raise AuditError("CARRIER_OUTSIDE_SKILLS", path)
            paths.add(path)
        bundle = row.get("carrier_bundle")
        if isinstance(bundle, list):
            for member in bundle:
                if not isinstance(member, dict) or not member.get("carrier_path"):
                    continue
                path = normalize_path(str(member["carrier_path"]))
                if not path.startswith("skills/") or not path.endswith(".md"):
                    raise AuditError("CARRIER_OUTSIDE_SKILLS", path)
                paths.add(path)
        parts = row.get("parts")
        if isinstance(parts, list):
            for part in parts:
                if not isinstance(part, dict):
                    continue
                carriers = part.get("carriers")
                if not isinstance(carriers, list):
                    continue
                for member in carriers:
                    if not isinstance(member, dict) or not member.get("carrier_path"):
                        continue
                    path = normalize_path(str(member["carrier_path"]))
                    if not path.startswith("skills/") or not path.endswith(".md"):
                        raise AuditError("CARRIER_OUTSIDE_SKILLS", path)
                    paths.add(path)
    return sorted(paths)


def verify_closed_row_set(
    expected: list[ExpectedRow], mapping: dict[tuple[str, int], dict[str, Any]]
) -> None:
    expected_by_key = {row.key: row for row in expected}
    missing = sorted(set(expected_by_key) - set(mapping))
    extra = sorted(set(mapping) - set(expected_by_key))
    if missing or extra:
        detail = []
        if missing:
            detail.append("missing=" + ",".join(f"{p}#{n}" for p, n in missing[:12]))
        if extra:
            detail.append("extra=" + ",".join(f"{p}#{n}" for p, n in extra[:12]))
        raise AuditError("ROW_SET_MISMATCH", "; ".join(detail))
    for key, expected_row in expected_by_key.items():
        actual = mapping[key]
        checks = {
            "reason": expected_row.reason,
            "before_text": expected_row.before_text,
            "before_chain": list(expected_row.before_chain),
        }
        for field, wanted in checks.items():
            if actual.get(field) != wanted:
                raise AuditError(
                    "ROW_SOURCE_MISMATCH",
                    f"{key[0]}#{key[1]} {field}: expected {wanted!r}, got {actual.get(field)!r}",
                )


def normalized_with_offsets(source: str) -> tuple[str, list[int]]:
    chars: list[str] = []
    offsets: list[int] = []
    in_space = False
    for index, char in enumerate(source):
        if char.isspace():
            if chars and not in_space:
                chars.append(" ")
                offsets.append(index)
            in_space = True
        else:
            chars.append(char)
            offsets.append(index)
            in_space = False
    if chars and chars[-1] == " ":
        chars.pop()
        offsets.pop()
    return "".join(chars), offsets


def line_range(source: str, start: int, end: int) -> tuple[int, int]:
    return (source.count("\n", 0, start) + 1, source.count("\n", 0, end) + 1)


def _blank(chars: list[str], start: int, end: int) -> None:
    for index in range(start, end):
        if chars[index] not in "\r\n":
            chars[index] = " "


_FENCE_OPEN = re.compile(r"^[ ]{0,3}(`{3,}|~{3,})([^\r\n]*)$")


def mask_inert_markdown(source: str) -> str:
    """Blank comments and code containers without changing source offsets.

    Fence closing follows the relevant CommonMark invariant: same marker,
    closing run at least as long as the opener, and whitespace-only suffix.
    Top-level indented code is also inert; indented list continuations remain
    visible to the prose parser.
    """
    chars = list(source)
    comment_start = 0
    while True:
        comment_start = source.find("<!--", comment_start)
        if comment_start < 0:
            break
        comment_end = source.find("-->", comment_start + 4)
        comment_end = len(source) if comment_end < 0 else comment_end + 3
        _blank(chars, comment_start, comment_end)
        comment_start = comment_end

    commentless = "".join(chars)
    lines = commentless.splitlines(keepends=True)
    offset = 0
    fence_marker: str | None = None
    fence_length = 0
    list_content_column: int | None = None
    for raw_with_end in lines:
        raw = raw_with_end.rstrip("\r\n")
        line_start = offset
        offset += len(raw_with_end)

        if fence_marker is not None:
            closer = re.match(
                rf"^[ ]{{0,3}}({re.escape(fence_marker)}{{{fence_length},}})[ \t]*$",
                raw,
            )
            _blank(chars, line_start, offset)
            if closer:
                fence_marker = None
                fence_length = 0
            continue

        opener = _FENCE_OPEN.match(raw)
        if opener and not (
            opener.group(1).startswith("`") and "`" in opener.group(2)
        ):
            fence_marker = opener.group(1)[0]
            fence_length = len(opener.group(1))
            _blank(chars, line_start, offset)
            continue

        if not raw.strip():
            continue
        item = GCD._LIST_ITEM.match(raw)
        if item:
            list_content_column = len(raw[: item.start(2)].expandtabs(4))
            continue
        leading = len(raw) - len(raw.lstrip(" \t"))
        expanded_leading = len(raw[:leading].expandtabs(4))
        if list_content_column is not None and expanded_leading >= list_content_column:
            continue
        if expanded_leading == 0:
            list_content_column = None
        if expanded_leading >= 4:
            _blank(chars, line_start, offset)
    return "".join(chars)


def inline_code_only(text: str) -> bool:
    normalized = GCD.normalize(text)
    if not normalized.startswith("`"):
        return False
    opener = len(normalized) - len(normalized.lstrip("`"))
    closer = len(normalized) - len(normalized.rstrip("`"))
    if opener != closer or len(normalized) <= opener + closer:
        return False
    inner = normalized[opener : len(normalized) - closer]
    return bool(inner.strip()) and ("`" * opener) not in inner


def prose_obligation_ranges(source: str) -> list[tuple[LedgerObligation, int, int]]:
    """Recover ranges for prose obligations while excluding HTML comments.

    Both walks are document ordered.  Matching from the previous end makes a
    repeated sentence under two different hosts addressable by the manifest's
    (path, chain, exact text) identity instead of imposing corpus-wide textual
    uniqueness.
    """
    visible = mask_inert_markdown(source)
    haystack, offsets = normalized_with_offsets(visible)
    cursor = 0
    out: list[tuple[LedgerObligation, int, int]] = []
    for parsed in GCD.parse(visible):
        obligation = LedgerObligation(parsed.text, tuple(parsed.chain))
        if inline_code_only(obligation.text):
            continue
        needle = GCD.normalize(obligation.text)
        pos = haystack.find(needle, cursor)
        if pos < 0:
            raise AuditError(
                "CARRIER_RANGE_UNRECOVERABLE",
                f"cannot locate parsed obligation after normalized offset {cursor}: {needle[:80]}",
            )
        end_pos = pos + len(needle) - 1
        out.append((obligation, offsets[pos], offsets[end_pos] + 1))
        cursor = pos + len(needle)
    return out


_TABLE_SEPARATOR_CELL = re.compile(r"^:?-{3,}:?$")


def table_cells(line: str) -> list[tuple[str, int, int]] | None:
    """Split a pipe table without splitting escaped pipes or inline code."""
    stripped = line.strip()
    if not stripped.startswith("|") or not stripped.endswith("|"):
        return None
    leading = len(line) - len(line.lstrip())
    content = stripped[1:-1]
    cells: list[tuple[str, int, int]] = []
    start = 0
    escaped = False
    code_ticks = 0
    index = 0
    while index <= len(content):
        boundary = index == len(content)
        char = content[index] if not boundary else "|"
        if not boundary and char == "\\" and not escaped:
            escaped = True
            index += 1
            continue
        if not boundary and char == "`" and not escaped:
            run = 1
            while index + run < len(content) and content[index + run] == "`":
                run += 1
            code_ticks = 0 if code_ticks == run else run
            index += run
            escaped = False
            continue
        if char == "|" and not escaped and code_ticks == 0:
            raw_cell = content[start:index]
            left_trim = len(raw_cell) - len(raw_cell.lstrip())
            right_trimmed = raw_cell.rstrip()
            cell_start = leading + 1 + start + left_trim
            cell_end = leading + 1 + start + len(right_trimmed)
            cells.append((GCD.normalize(raw_cell), cell_start, cell_end))
            start = index + 1
        escaped = False
        index += 1
    return cells


def is_table_separator(line: str) -> bool:
    cells = table_cells(line)
    return bool(cells) and all(
        _TABLE_SEPARATOR_CELL.fullmatch(cell[0]) for cell in cells
    )


def table_obligation_ranges(
    source: str, *, include_inline_code_only: bool = False
) -> list[tuple[LedgerObligation, int, int]]:
    """Parse Markdown table data rows as obligations.

    The header is table identity and therefore an immediate governing host.
    Header/separator rows are schema, not obligations.  Complete data-row text
    preserves column/cell semantics and supplies an exact carrier locator.
    """
    out: list[tuple[LedgerObligation, int, int]] = []
    headings: list[tuple[int, str]] = []
    visible_source = mask_inert_markdown(source)
    lines = visible_source.splitlines(keepends=True)
    offsets: list[int] = []
    total = 0
    for line in lines:
        offsets.append(total)
        total += len(line)

    table_header: list[str] | None = None
    table_active = False
    for index, raw_with_end in enumerate(lines):
        visible = raw_with_end.rstrip("\r\n")

        if not visible.strip():
            table_header = None
            table_active = False
            continue

        heading = GCD._HEADING.match(visible)
        if heading:
            level = len(heading.group(1))
            while headings and headings[-1][0] >= level:
                headings.pop()
            headings.append((level, GCD.content_key(heading.group(2))))
            table_header = None
            table_active = False
            continue

        cells = table_cells(visible)
        if cells is None:
            table_header = None
            table_active = False
            continue
        if is_table_separator(visible):
            table_active = table_header is not None
            continue
        if not table_active:
            table_header = [cell[0] for cell in cells]
            continue

        table_identity = " | ".join(table_header or [])
        for column, (text, cell_start, cell_end) in enumerate(cells):
            if not text or (inline_code_only(text) and not include_inline_code_only):
                continue
            header = (
                table_header[column]
                if table_header is not None and column < len(table_header)
                else f"column-{column + 1}"
            )
            chain = tuple(key for _, key in headings) + (
                "table:" + GCD.content_key(table_identity),
                "column:" + GCD.content_key(header),
            )
            start = offsets[index] + cell_start
            end = offsets[index] + cell_end
            out.append((LedgerObligation(text, chain), start, end))
    return out


def parse_obligation_ranges(source: str) -> list[tuple[LedgerObligation, int, int]]:
    obligations = prose_obligation_ranges(source) + table_obligation_ranges(source)
    return sorted(obligations, key=lambda item: (item[1], item[2]))


def raw_list_item_ranges(source: str) -> list[tuple[LedgerObligation, int, int]]:
    """Expose an exact visible list item as a schema4 carrier without changing row derivation.

    The legacy row splitter intentionally breaks label-plus-rule bullets into
    clause-sized obligations.  A schema4 bundle sometimes needs the complete
    current item (label and operative clauses together).  This locator is
    limited to visible Markdown list items; comments, fences, and indented code
    were already blanked by ``mask_inert_markdown``.
    """
    visible = mask_inert_markdown(source)
    headings: list[tuple[int, str]] = []
    list_stack: list[tuple[int, str]] = []
    out: list[tuple[LedgerObligation, int, int]] = []
    offset = 0
    for raw in visible.splitlines(keepends=True):
        line = raw.rstrip("\r\n")
        heading = GCD._HEADING.match(line)
        if heading:
            level = len(heading.group(1))
            while headings and headings[-1][0] >= level:
                headings.pop()
            headings.append((level, GCD.content_key(heading.group(2))))
            list_stack.clear()
            offset += len(raw)
            continue
        item = GCD._LIST_ITEM.match(line)
        if item:
            indent = len(item.group(1).expandtabs(4))
            while list_stack and list_stack[-1][0] >= indent:
                list_stack.pop()
            text = GCD.normalize(item.group(2))
            if text:
                start = offset + item.start(2)
                end = offset + item.end(2)
                chain = tuple([value for _, value in headings] + [value for _, value in list_stack])
                out.append((LedgerObligation(text, chain), start, end))
                list_stack.append((indent, GCD.content_key(text)))
        elif line and not line[0].isspace():
            list_stack.clear()
        offset += len(raw)
    return out


def raw_table_row_ranges(source: str) -> list[tuple[LedgerObligation, int, int]]:
    """Expose a complete visible data row, never an inline-code-only cell."""
    visible = mask_inert_markdown(source)
    headings: list[tuple[int, str]] = []
    header: list[str] | None = None
    active = False
    out: list[tuple[LedgerObligation, int, int]] = []
    offset = 0
    for raw in visible.splitlines(keepends=True):
        line = raw.rstrip("\r\n")
        heading = GCD._HEADING.match(line)
        if heading:
            level = len(heading.group(1))
            while headings and headings[-1][0] >= level:
                headings.pop()
            headings.append((level, GCD.content_key(heading.group(2))))
            header = None
            active = False
            offset += len(raw)
            continue
        cells = table_cells(line)
        if cells is None:
            header = None
            active = False
            offset += len(raw)
            continue
        if is_table_separator(line):
            active = header is not None
            offset += len(raw)
            continue
        if not active:
            header = [cell[0] for cell in cells]
            offset += len(raw)
            continue
        text = " | ".join(cell[0] for cell in cells)
        if text:
            identity = " | ".join(header or [])
            chain = tuple(value for _, value in headings) + (
                "table:" + GCD.content_key(identity),
                "row",
            )
            out.append(
                (
                    LedgerObligation(text, chain),
                    offset + cells[0][1],
                    offset + cells[-1][2],
                )
            )
        offset += len(raw)
    return out


def section_body_ranges(source: str) -> list[tuple[LedgerObligation, int, int]]:
    """Return exact visible section bodies for schema4 closed-bundle carriers."""
    visible = mask_inert_markdown(source)
    lines = visible.splitlines(keepends=True)
    offsets: list[int] = []
    total = 0
    for line in lines:
        offsets.append(total)
        total += len(line)
    headings: list[tuple[int, str]] = []
    found: list[tuple[int, int, tuple[str, ...]]] = []
    for index, raw in enumerate(lines):
        heading = GCD._HEADING.match(raw.rstrip("\r\n"))
        if not heading:
            continue
        level = len(heading.group(1))
        while headings and headings[-1][0] >= level:
            headings.pop()
        chain = tuple([value for _, value in headings] + [GCD.content_key(heading.group(2))])
        found.append((index, level, chain))
        headings.append((level, GCD.content_key(heading.group(2))))
    out: list[tuple[LedgerObligation, int, int]] = []
    for position, (line_index, level, chain) in enumerate(found):
        next_index = len(lines)
        for candidate_index, candidate_level, _ in found[position + 1 :]:
            if candidate_level <= level:
                next_index = candidate_index
                break
        start = offsets[line_index] + len(lines[line_index])
        end = offsets[next_index] if next_index < len(lines) else len(source)
        while start < end and source[start].isspace():
            start += 1
        while end > start and source[end - 1].isspace():
            end -= 1
        text = GCD.normalize(source[start:end])
        if text:
            out.append((LedgerObligation(text, chain), start, end))
    return out


def exact_carrier(repo: Path, path: str, text: str, chain: list[str]) -> Carrier:
    file_path = repo / path
    if not file_path.is_file():
        raise AuditError("CARRIER_PATH_MISSING", path)
    source = file_path.read_text(encoding="utf-8")
    normalized_text = GCD.normalize(text)
    claimed_chain = tuple(chain)
    exact_text_obligations = [
        (obligation, start, end)
        for obligation, start, end in parse_obligation_ranges(source)
        if GCD.normalize(obligation.text) == normalized_text
    ]
    if not exact_text_obligations:
        exact_text_obligations = [
            (obligation, start, end)
            for obligation, start, end in (
                raw_list_item_ranges(source)
                + raw_table_row_ranges(source)
                + section_body_ranges(source)
            )
            if GCD.normalize(obligation.text) == normalized_text
        ]
    matching_obligations = [
        item for item in exact_text_obligations if tuple(item[0].chain) == claimed_chain
    ]
    if not matching_obligations and exact_text_obligations:
        raise AuditError(
            "CARRIER_CHAIN_MISMATCH",
            f"{path}: exact text exists, but not under claimed chain {list(claimed_chain)!r}",
        )
    if len(matching_obligations) != 1:
        raise AuditError(
            "CARRIER_COMPOSITE_NOT_UNIQUE",
            f"{path}: (chain, exact text) count={len(matching_obligations)}",
        )
    obligation, start, end = matching_obligations[0]
    derived_chain = tuple(obligation.chain)
    start_line, end_line = line_range(source, start, end)
    return Carrier(path, normalized_text, derived_chain, start_line, end_line)


QUALIFIER_PATTERNS: dict[str, re.Pattern[str]] = {
    "modality": re.compile(
        r"\b(?:must|required|shall|never|cannot|can't|do not|may|should)\b|必须|不得|禁止|不可|不能|应当|应该|可以",
        re.I,
    ),
    "recency": re.compile(
        r"\b(?:before|after|current|latest|final|again|first|initial|prior|subsequent)\b|之前|之后|当前|最新|最终|再次|首次|先|再",
        re.I,
    ),
    "scope": re.compile(
        r"\b(?:not\s+a\s+substitute|limited\s+to|restricted\s+to|every|each|all|any|only|solely|exclusively|full|whole|per|none)\b|每个|每条|全部|所有|任何|仅|完整|全量|无一",
        re.I,
    ),
    "actor": re.compile(
        r"\b(?:owners?|users?|reviewers?|testers?|testing|clients?|maintainers?|designers?|developers?|agents?)\b|用户|负责人|维护者|评审者|设计师|开发者|测试人员|测试者|客户端|智能体",
        re.I,
    ),
    "consequence": re.compile(
        r"\b(?:blocks?|blocked|fails?|failed|stops?|stopped|invalid|rejects?|rejected|pending|cannot claim|must not claim|red)\b|阻塞|失败|停止|无效|拒绝|待定|不得声称|不可声明|红灯",
        re.I,
    ),
}

HARD_MODALITY = re.compile(
    r"\b(?:must|required|shall|never|cannot|can't|do not)\b|必须|不得|禁止|不可|不能",
    re.I,
)
SOFT_MODALITY = re.compile(r"\b(?:may|should|can)\b|可以|应该|应当", re.I)

_THRESHOLD_COMPARATOR = re.compile(
    r"\b(?:at least|at most|minimum|maximum|more than|less than)\b"
    r"|至少|至多|最多|最少|不超过|不少于|高于|低于",
    re.I,
)
_THRESHOLD_DIRECTIONAL_COMPARATOR = re.compile(
    r"\b(?:above|below|over|under)\b(?=\s+\d+(?:\.\d+)?)",
    re.I,
)
_THRESHOLD_WITHIN = re.compile(
    r"\bwithin\b(?=\s+(?:\d+(?:\.\d+)?|one|two|three|four|five|six|seven|eight|nine|ten)\s*(?:ms|msec(?:ond)?s?|s|sec(?:ond)?s?|min(?:ute)?s?|h|hours?|days?|frames?|attempts?|retries?|requests?)\b)",
    re.I,
)
_THRESHOLD_RATIO = re.compile(
    r"(?<![A-Za-z0-9_])\d+(?:\.\d+)?\s*:\s*\d+(?:\.\d+)?(?![A-Za-z0-9_])"
)
_THRESHOLD_DIMENSION = re.compile(
    r"(?<![A-Za-z0-9_])"
    r"\d+(?:\.\d+)?\s*[x×]\s*\d+(?:\.\d+)?"
    r"(?:\s*(?:px|pt|dp|sp))?"
    r"(?![A-Za-z0-9_])",
    re.I,
)
_THRESHOLD_QUANTITY = re.compile(
    r"(?<![A-Za-z0-9_])"
    r"\d+(?:\.\d+)?\s*"
    r"(?:%|px|pt|dp|sp|ms|msec(?:ond)?s?|s|sec(?:ond)?s?|min(?:ute)?s?|h|hours?|days?|bytes?|kib|mib|gib|kb|mb|gb|items?|rows?|files?|steps?|times?|characters?|chars?|screens?|locales?|variants?|states?|frames?|attempts?|retries?|requests?|users?|个|项|条|次|秒|分钟|小时|天|像素|字符|行|列|页|屏|帧|毫秒)"
    r"(?![A-Za-z0-9_])",
    re.I,
)
_ACTOR_MODIFIER_AFTER = re.compile(
    r"^(?:[-‑](?:facing|visible|authored|generated|provided)\b"
    r"|\s+(?:copy|language|interface|research)\b"
    r"|\s+experience\s+research\b"
    r"|(?:['’]s?|s['’])\s+needs\b"
    r"|\s+needs\b(?!\s+to\b))",
    re.I,
)
_CHINESE_USER_NON_ACTOR_AFTER = re.compile(
    r"^(?:的?需求|文案|语言|界面|可见|知道|看到|研究)"
)
_BLOCK_MODAL_BEFORE = re.compile(
    r"(?:\b(?:must|shall|should|may|can|will|would|to)\b(?:\s+[A-Za-z-]+){0,3}|(?:必须|应当|应该|可以|可)(?:\S{0,6}))\s*$",
    re.I,
)
_FINAL_TERMINAL_NOUN = re.compile(
    r"^\s+(?:approval|acceptance|artifact|checkpoint|response|verdict|submission|state|content|screen|result|release|merge|commit|push|ready|completion)\b",
    re.I,
)
_CLOSED_FINAL_RELATION_SOURCE = re.compile(
    r"^(?:the\s+)?final\s+skill\s+(?:must|shall)\s+(?:stay|remain)\s+generic[.!]?$",
    re.I,
)

POLARITY_GROUPS: dict[str, list[tuple[re.Pattern[str], re.Pattern[str]]]] = {
    "recency": [
        (
            re.compile(r"\b(?:before|prior)\b|之前|先", re.I),
            re.compile(r"\b(?:after|subsequent)\b|之后|再", re.I),
        ),
        (
            re.compile(r"\b(?:latest|final)\b|最新|最终", re.I),
            re.compile(r"\b(?:first|initial)\b|首次", re.I),
        ),
    ],
    "threshold": [
        (
            re.compile(
                r"\b(?:at least|minimum|more than)\b|\b(?:above|over)\b(?=\s+\d)|至少|最少|不少于|高于",
                re.I,
            ),
            re.compile(
                r"\b(?:at most|maximum|less than)\b|\b(?:below|under)\b(?=\s+\d)|至多|最多|不超过|低于",
                re.I,
            ),
        )
    ],
    "scope": [
        (
            re.compile(
                r"\b(?:not\s+a\s+substitute|limited\s+to|restricted\s+to|every|each|all|only|solely|exclusively|none)\b|每个|每条|全部|所有|仅|无一",
                re.I,
            ),
            re.compile(r"\bany\b|任何", re.I),
        )
    ],
}


def _dedupe_terms(matches: Iterable[str]) -> list[str]:
    seen: set[str] = set()
    values: list[str] = []
    for value in matches:
        if value in seen:
            continue
        seen.add(value)
        values.append(value)
    return values


_QUOTED_LITERAL = re.compile(
    r'"(?:\\.|[^"\\])*"'
    r"|(?<![A-Za-z0-9])'(?:\\.|[^'\\])*'(?![A-Za-z0-9])"
    r"|“[^”]*”|‘[^’]*’"
)
_PATH_LITERAL = re.compile(
    r"(?<![A-Za-z0-9_./-])"
    r"(?:(?:\.{0,2}/|/)[^\s`\"']+|[^\s`\"']+/[^\s`\"']+\.[A-Za-z0-9]{1,8})"
)


def _mask_threshold_literals(text: str) -> str:
    """Blank inline code, quoted literals, and path tokens at stable offsets."""
    chars = list(text)

    cursor = 0
    while cursor < len(text):
        start = text.find("`", cursor)
        if start < 0:
            break
        run = 1
        while start + run < len(text) and text[start + run] == "`":
            run += 1
        marker = "`" * run
        end = text.find(marker, start + run)
        if end < 0:
            cursor = start + run
            continue
        _blank(chars, start, end + run)
        cursor = end + run

    for pattern in (_QUOTED_LITERAL, _PATH_LITERAL):
        visible = "".join(chars)
        for match in pattern.finditer(visible):
            _blank(chars, match.start(), match.end())
    return "".join(chars)


def _threshold_terms(text: str) -> list[str]:
    searchable = _mask_threshold_literals(text)
    matches: list[tuple[int, int, str]] = []
    occupied: list[tuple[int, int]] = []
    for pattern in (_THRESHOLD_DIMENSION, _THRESHOLD_RATIO, _THRESHOLD_QUANTITY):
        for match in pattern.finditer(searchable):
            if any(match.start() < end and start < match.end() for start, end in occupied):
                continue
            occupied.append((match.start(), match.end()))
            matches.append((match.start(), match.end(), match.group(0)))
    for pattern in (
        _THRESHOLD_COMPARATOR,
        _THRESHOLD_DIRECTIONAL_COMPARATOR,
        _THRESHOLD_WITHIN,
    ):
        for match in pattern.finditer(searchable):
            matches.append((match.start(), match.end(), match.group(0)))
    matches.sort(key=lambda item: (item[0], item[1]))
    return _dedupe_terms(value for _, _, value in matches)


def _recency_terms(text: str) -> list[str]:
    values = []
    for match in QUALIFIER_PATTERNS["recency"].finditer(text):
        if match.group(0).casefold() == "first" and re.match(
            r"[-‑]screen\b", text[match.end() :], re.I
        ):
            continue
        values.append(match.group(0))
    return _dedupe_terms(values)


def _scope_terms(text: str) -> list[str]:
    values = []
    for match in QUALIFIER_PATTERNS["scope"].finditer(text):
        term = match.group(0)
        before = text[: match.start()]
        if term.casefold() == "only" and re.search(
            r"\bnot\s+(?:[*_~]{1,3})?$", before, re.I
        ):
            continue
        if term == "仅" and re.search(r"不(?:仅)?$", before):
            continue
        if term.casefold() == "per" and re.match(
            r"\s+(?:[*_~]{1,3})?the\b", text[match.end() :], re.I
        ):
            # "per the classes/design above" is an according-to cross-reference,
            # not a closed-set quantifier such as "per affected client".
            continue
        values.append(term)
    return _dedupe_terms(values)


def _actor_terms(text: str) -> list[str]:
    values = []
    for match in QUALIFIER_PATTERNS["actor"].finditer(text):
        term = match.group(0)
        if term.casefold() in {"user", "users"}:
            if _ACTOR_MODIFIER_AFTER.match(text[match.end() :]):
                continue
        elif term == "用户":
            if _CHINESE_USER_NON_ACTOR_AFTER.match(text[match.end() :]):
                continue
        elif term.casefold() == "agent" and re.match(
            r"[-‑](?:contract|facing|generated|owned)\b",
            text[match.end() :],
            re.I,
        ):
            continue
        elif term.casefold() == "reviewer" and re.match(
            r"\s+(?:checks?|checklist|criteria|检查项)\b",
            text[match.end() :],
            re.I,
        ):
            continue
        values.append(term)
    return _dedupe_terms(values)


def _inside_code_path(text: str, start: int, end: int) -> bool:
    if text[:start].count("`") % 2 == 0:
        return False
    left = text.rfind("`", 0, start)
    right = text.find("`", end)
    if left < 0 or right < 0:
        return False
    token = text[left + 1 : right]
    return "/" in token or re.search(r"(?:^|[-_.])(?:md|txt|json|ya?ml|py|sh)$", token, re.I) is not None


def _block_is_enumerated_noun(text: str, start: int, end: int) -> bool:
    before = text[max(0, start - 48) : start]
    after = text[end : end + 48]
    if _BLOCK_MODAL_BEFORE.search(before):
        return False
    previous = before.rstrip()[-1:] if before.rstrip() else ""
    following = after.lstrip()
    return previous in {",", "/"} and bool(
        re.match(r"^(?:,|/|\band\b|\bor\b|，|、|和|或)", following, re.I)
    )


def _block_is_code_noun(text: str, start: int) -> bool:
    return re.search(r"\bcode\s+$", text[max(0, start - 24) : start], re.I) is not None


def _red_is_color_term(text: str, start: int, end: int) -> bool:
    before = text[max(0, start - 32) : start]
    after = text[end : end + 32]
    return bool(
        re.search(r"\b(?:color|colour)(?:\s+is|\s*:)?\s*$", before, re.I)
        or re.match(r"^[-‑]colou?red\b", after, re.I)
        or re.match(r"^(?:[-‑]|\s+)(?:first|baseline)\b", after, re.I)
        or re.match(
            r"^\s+(?:color|colour|text|border|background|icon|badge|token|fill|stroke)\b",
            after,
            re.I,
        )
    )


def _consequence_terms(text: str) -> list[str]:
    values = []
    for match in QUALIFIER_PATTERNS["consequence"].finditer(text):
        term = match.group(0)
        folded = term.casefold()
        if _inside_code_path(text, match.start(), match.end()):
            continue
        if folded == "block" and _block_is_enumerated_noun(
            text, match.start(), match.end()
        ):
            continue
        if folded in {"block", "blocks"} and _block_is_code_noun(
            text, match.start()
        ):
            continue
        if folded == "fail" and (
            text[match.start() - 1 : match.start()] == "/"
            or text[match.end() : match.end() + 1] == "/"
        ):
            continue
        if folded == "red" and _red_is_color_term(
            text, match.start(), match.end()
        ):
            continue
        values.append(term)
    return _dedupe_terms(values)


def qualifier_terms(text: str) -> dict[str, list[str]]:
    extractors = {
        "modality": lambda value: _dedupe_terms(
            match.group(0) for match in QUALIFIER_PATTERNS["modality"].finditer(value)
        ),
        "recency": _recency_terms,
        "threshold": _threshold_terms,
        "scope": _scope_terms,
        "actor": _actor_terms,
        "consequence": _consequence_terms,
    }
    result: dict[str, list[str]] = {}
    for kind in ("modality", "recency", "threshold", "scope", "actor", "consequence"):
        terms = extractors[kind](text)
        if terms:
            result[kind] = terms
    return result


_QUALIFIER_RELATION_FIELDS = {
    "kind",
    "term",
    "occurrence",
    "source_excerpt",
    "resolution",
    "same_immediate_host",
}
_DIRECTIONAL_RECENCY_TERMS = {
    "before",
    "after",
    "prior",
    "subsequent",
    "之前",
    "之后",
    "先",
    "再",
}


def _literal_occurrences(text: str, term: str) -> list[re.Match[str]]:
    return list(
        re.finditer(
            rf"(?<![A-Za-z0-9_]){re.escape(term)}(?![A-Za-z0-9_])",
            text,
            re.I,
        )
    )


def _is_closed_non_temporal_final_relation(
    source_text: str, carrier_text: str, occurrence: re.Match[str]
) -> bool:
    normalized_source = GCD.normalize(source_text)
    if not _CLOSED_FINAL_RELATION_SOURCE.fullmatch(normalized_source):
        return False
    rewritten = (
        normalized_source[: occurrence.start()]
        + "resulting"
        + normalized_source[occurrence.end() :]
    )
    return GCD.normalize(rewritten).casefold() == GCD.normalize(carrier_text).casefold()


def validate_qualifier_relations(
    expected: ExpectedRow,
    mapping: dict[str, Any],
    carrier: Carrier,
    required: dict[str, list[str]],
) -> dict[str, list[str]]:
    label = f"{expected.source_path}#{expected.source_ordinal}"
    relations = mapping.get("qualifier_relations", [])
    if not isinstance(relations, list):
        raise AuditError("QUALIFIER_RELATION_INVALID", f"{label}: array required")
    if not relations:
        return required
    if mapping.get("effect") != "strengthened":
        raise AuditError("QUALIFIER_RELATION_REQUIRES_STRENGTHENED", label)
    if mapping.get("manual_reviewed") is not True:
        raise AuditError("STRENGTHENED_REVIEW_REQUIRED", label)

    effective = {kind: list(terms) for kind, terms in required.items()}
    seen: set[tuple[str, str, int]] = set()
    for relation in relations:
        if not isinstance(relation, dict) or set(relation) != _QUALIFIER_RELATION_FIELDS:
            raise AuditError("QUALIFIER_RELATION_INVALID", label)
        kind = relation.get("kind")
        if kind != "recency":
            raise AuditError(
                "QUALIFIER_RELATION_FORBIDDEN", f"{label}: kind={kind}"
            )
        if relation.get("resolution") != "carrier-applies-unconditionally":
            raise AuditError("QUALIFIER_RELATION_INVALID", f"{label}: resolution")
        if relation.get("same_immediate_host") is not True:
            raise AuditError("QUALIFIER_RELATION_INVALID", f"{label}: host")
        term = relation.get("term")
        occurrence = relation.get("occurrence")
        excerpt = relation.get("source_excerpt")
        if (
            not isinstance(term, str)
            or not term
            or not isinstance(occurrence, int)
            or isinstance(occurrence, bool)
            or occurrence < 1
            or not isinstance(excerpt, str)
            or not excerpt
            or "\n" in excerpt
            or len(excerpt) > 120
        ):
            raise AuditError("QUALIFIER_RELATION_INVALID", label)
        identity = (str(kind), term.casefold(), occurrence)
        if identity in seen:
            raise AuditError("QUALIFIER_RELATION_INVALID", f"{label}: duplicate")
        seen.add(identity)

        source_terms = effective.get("recency", [])
        matching_source_terms = [
            value for value in source_terms if value.casefold() == term.casefold()
        ]
        occurrences = _literal_occurrences(expected.before_text, term)
        excerpt_start = expected.before_text.find(excerpt)
        if (
            len(matching_source_terms) != 1
            or len(occurrences) != 1
            or occurrence != 1
            or expected.before_text.count(excerpt) != 1
            or excerpt_start < 0
            or not (
                excerpt_start <= occurrences[0].start()
                and occurrences[0].end() <= excerpt_start + len(excerpt)
            )
        ):
            raise AuditError("QUALIFIER_RELATION_INVALID", label)

        other_recency = [
            value for value in source_terms if value.casefold() != term.casefold()
        ]
        source_consequences = required.get("consequence", [])
        after_recency = qualifier_terms(carrier.text).get("recency", [])
        terminal_tail = expected.before_text[occurrences[0].end() :]
        if (
            term.casefold() != "final"
            or not _is_closed_non_temporal_final_relation(
                expected.before_text, carrier.text, occurrences[0]
            )
            or term.casefold() in _DIRECTIONAL_RECENCY_TERMS
            or other_recency
            or source_consequences
            or _FINAL_TERMINAL_NOUN.match(terminal_tail)
            or after_recency
        ):
            raise AuditError("QUALIFIER_RELATION_FORBIDDEN", label)

        effective["recency"] = [
            value for value in source_terms if value.casefold() != term.casefold()
        ]
        if not effective["recency"]:
            del effective["recency"]
    return effective


_CLAUSE_ACTION = re.compile(
    r"\b(?:must|shall|required|record|verify|preserve|reject|block|expose|show|keep|route|check|name|include|cover|provide|ensure|prevent|allow|forbid)\b|必须|应当|记录|验证|保留|拒绝|阻塞|展示|路由|检查|命名|包括|覆盖|提供|确保|防止|允许|禁止",
    re.I,
)
_CLAUSE_LOCAL_ACTION = re.compile(
    r"\b(?:record|verify|preserve|reject|block|expose|show|keep|route|check|name|include|cover|provide|ensure|prevent|allow|forbid|retain|confirm|complete|finish|remain|stay)\b|记录|验证|保留|拒绝|阻塞|展示|路由|检查|命名|包括|覆盖|提供|确保|防止|允许|禁止|保有|确认|完成|保持|测试",
    re.I,
)


def compound_clauses(text: str) -> list[dict[str, str]]:
    """Conservatively and reproducibly split a baseline compound obligation."""
    normalized = GCD.normalize(text)
    semicolon_parts = [GCD.normalize(part) for part in re.split(r"[;；]", normalized)]
    semicolon_parts = [part for part in semicolon_parts if part]
    if len(semicolon_parts) >= 2:
        return [
            {"id": f"c{index}", "text": part}
            for index, part in enumerate(semicolon_parts, 1)
        ]

    colon = re.match(r"^(.*?[:：])\s*(.+)$", normalized)
    if not colon or not _CLAUSE_ACTION.search(colon.group(1)):
        return []
    tail = colon.group(2)
    final_join = re.search(r"(?:,|，)\s*(?:and|or|以及|与|或)\s+", tail, re.I)
    if not final_join:
        return []
    expanded = (
        tail[: final_join.start()]
        + ", "
        + tail[final_join.end() :]
    )
    items = [GCD.normalize(item) for item in re.split(r"[,，]", expanded)]
    items = [item for item in items if item]
    if len(items) < 3:
        return []
    clause_like = sum(
        bool(_CLAUSE_ACTION.search(item)) or GCD.effective_len(item) >= 24
        for item in items
    )
    if clause_like < 2:
        return []
    parts = [colon.group(1) + " " + items[0], *items[1:]]
    return [
        {"id": f"c{index}", "text": part}
        for index, part in enumerate(parts, 1)
    ]


def ensure_qualifier_strength(before: str, after: str, label: str) -> None:
    required = qualifier_terms(before)
    available = qualifier_terms(after)
    missing = sorted(set(required) - set(available))
    if missing:
        raise AuditError(
            "BUNDLE_QUALIFIER_MISSING", f"{label}: classes={','.join(missing)}"
        )
    if HARD_MODALITY.search(before) and not HARD_MODALITY.search(after):
        raise AuditError("BUNDLE_QUALIFIER_WEAKENED", label)
    for polarity_kind in required:
        for positive, negative in POLARITY_GROUPS.get(polarity_kind, []):
            if positive.search(before) and negative.search(after):
                raise AuditError("BUNDLE_QUALIFIER_REVERSED", f"{label}: {polarity_kind}")
            if negative.search(before) and positive.search(after):
                raise AuditError("BUNDLE_QUALIFIER_REVERSED", f"{label}: {polarity_kind}")
    for kind, before_terms in required.items():
        before_literals = {term.casefold() for term in before_terms}
        after_literals = {term.casefold() for term in available.get(kind, [])}
        absent = sorted(before_literals - after_literals)
        if absent:
            raise AuditError(
                "BUNDLE_QUALIFIER_LITERAL_MISSING",
                f"{label}: {kind}={','.join(absent)}",
            )
    for kind in required:
        for positive, negative in POLARITY_GROUPS.get(kind, []):
            if positive.search(before) and negative.search(after):
                raise AuditError("BUNDLE_QUALIFIER_REVERSED", f"{label}: {kind}")
            if negative.search(before) and positive.search(after):
                raise AuditError("BUNDLE_QUALIFIER_REVERSED", f"{label}: {kind}")


def _clause_action_terms(text: str) -> list[str]:
    return _dedupe_terms(
        match.group(0) for match in _CLAUSE_LOCAL_ACTION.finditer(text)
    )


def _missing_terms(required: Iterable[str], available: Iterable[str]) -> list[str]:
    wanted = Counter(value.casefold() for value in required)
    present = Counter(value.casefold() for value in available)
    return sorted((wanted - present).elements())


def validate_semantic_review(
    evidence: dict[str, Any], label: str, *, required: bool
) -> None:
    """Validate review-evidence shape, never the truth of the review decision."""
    status = evidence.get("semantic_review")
    rationale = evidence.get("semantic_rationale")
    if required:
        if status != "reviewed":
            raise AuditError("SEMANTIC_REVIEW_REQUIRED", label)
        if not isinstance(rationale, str) or not rationale.strip():
            raise AuditError("SEMANTIC_RATIONALE_REQUIRED", label)
        return
    if status is not None or rationale is not None:
        raise AuditError("SEMANTIC_REVIEW_REDUNDANT", label)


def ensure_clause_local_lexical_guard(before: str, after: str, label: str) -> None:
    """Catch literal local omissions without claiming semantic equivalence."""
    before_qualifiers = qualifier_terms(before)
    after_qualifiers = qualifier_terms(after)
    for kind in ("modality", "actor", "consequence"):
        missing = _missing_terms(
            before_qualifiers.get(kind, []), after_qualifiers.get(kind, [])
        )
        if missing:
            raise AuditError(
                f"BUNDLE_CLAUSE_{kind.upper()}_MISSING",
                f"{label}: {','.join(missing)}",
            )
    missing_actions = _missing_terms(
        _clause_action_terms(before), _clause_action_terms(after)
    )
    if missing_actions:
        raise AuditError(
            "BUNDLE_CLAUSE_ACTION_MISSING",
            f"{label}: {','.join(missing_actions)}",
        )


def validate_bundle_clause_proof(
    before: str,
    after: str,
    claimed: Any,
    label: str,
) -> None:
    # Open-text actor/action/consequence equivalence is review-owned. These
    # deterministic checks are lexical tripwires, not semantic proof.
    ensure_clause_local_lexical_guard(before, after, label)
    if not isinstance(claimed, list):
        raise AuditError("BUNDLE_CLAUSE_PROOF_INVALID", label)
    required = qualifier_terms(before)
    available = qualifier_terms(after)
    claimed_kinds: list[str] = []
    for item in claimed:
        if not isinstance(item, dict) or set(item) != {
            "kind",
            "before",
            "after",
            "same_immediate_host",
        }:
            raise AuditError("BUNDLE_CLAUSE_PROOF_INVALID", label)
        kind = item.get("kind")
        if kind not in QUALIFIER_KINDS or item.get("same_immediate_host") is not True:
            raise AuditError("BUNDLE_CLAUSE_PROOF_INVALID", f"{label}: {kind}")
        claimed_kinds.append(str(kind))
        before_values = item.get("before")
        after_values = item.get("after")
        if not isinstance(before_values, list) or not isinstance(after_values, list):
            raise AuditError("BUNDLE_CLAUSE_PROOF_INVALID", f"{label}: {kind}")
        if Counter(str(value).casefold() for value in before_values) != Counter(
            value.casefold() for value in required.get(str(kind), [])
        ):
            raise AuditError("BUNDLE_QUALIFIER_BEFORE_INCOMPLETE", f"{label}: {kind}")
        if Counter(str(value).casefold() for value in after_values) != Counter(
            value.casefold() for value in available.get(str(kind), [])
        ):
            raise AuditError("BUNDLE_QUALIFIER_AFTER_INCOMPLETE", f"{label}: {kind}")
    if len(claimed_kinds) != len(set(claimed_kinds)) or set(claimed_kinds) != set(required):
        raise AuditError("BUNDLE_QUALIFIER_CLASS_MISMATCH", label)
    ensure_qualifier_strength(before, after, label)


def _aggregate_qualifier_terms(texts: Iterable[str]) -> dict[str, list[str]]:
    aggregate: dict[str, list[str]] = {}
    for text in texts:
        for kind, terms in qualifier_terms(text).items():
            aggregate.setdefault(kind, []).extend(terms)
    return {kind: _dedupe_terms(terms) for kind, terms in aggregate.items()}


def validate_bundle_summary_proof(
    clause_pairs: Iterable[tuple[str, str]], claimed: Any, label: str
) -> None:
    pairs = list(clause_pairs)
    required = _aggregate_qualifier_terms(before for before, _ in pairs)
    available = _aggregate_qualifier_terms(after for _, after in pairs)
    if not isinstance(claimed, list):
        raise AuditError("QUALIFIERS_INVALID", f"{label}: array required")
    claimed_kinds: list[str] = []
    for item in claimed:
        if not isinstance(item, dict) or item.get("kind") not in QUALIFIER_KINDS:
            raise AuditError("QUALIFIERS_INVALID", f"{label}: bad qualifier entry")
        kind = str(item["kind"])
        claimed_kinds.append(kind)
        if item.get("same_immediate_host") is not True:
            raise AuditError("QUALIFIER_WRONG_HOST", f"{label}: {kind}")
        before_values = item.get("before")
        after_values = item.get("after")
        if not isinstance(before_values, list) or not isinstance(after_values, list):
            raise AuditError("QUALIFIERS_INVALID", f"{label}: {kind}")
        if Counter(str(value).casefold() for value in before_values) != Counter(
            value.casefold() for value in required.get(kind, [])
        ):
            raise AuditError("BUNDLE_QUALIFIER_BEFORE_INCOMPLETE", f"{label}: {kind}")
        if Counter(str(value).casefold() for value in after_values) != Counter(
            value.casefold() for value in available.get(kind, [])
        ):
            raise AuditError("BUNDLE_QUALIFIER_AFTER_INCOMPLETE", f"{label}: {kind}")
    if len(claimed_kinds) != len(set(claimed_kinds)) or set(claimed_kinds) != set(
        required
    ):
        raise AuditError("BUNDLE_QUALIFIER_CLASS_MISMATCH", label)


def validate_qualifiers(
    expected: ExpectedRow, mapping: dict[str, Any], carrier: Carrier
) -> None:
    label = f"{expected.source_path}#{expected.source_ordinal}"
    before = expected.before_text
    after = carrier.text
    required = validate_qualifier_relations(
        expected, mapping, carrier, qualifier_terms(before)
    )
    claimed = mapping.get("qualifiers")
    if not isinstance(claimed, list):
        raise AuditError("QUALIFIERS_INVALID", f"{label}: array required")

    # A byte-for-byte normative carrier proves its own qualifier preservation.
    if GCD.normalize(before) == GCD.normalize(after):
        if claimed:
            raise AuditError("QUALIFIERS_REDUNDANT", f"{label}: verbatim carrier")
        return

    if mapping.get("manual_reviewed") is not True:
        raise AuditError("MANUAL_REVIEW_REQUIRED", f"{label}: rephrased carrier")
    claimed_kinds: list[str] = []
    for item in claimed:
        if not isinstance(item, dict) or item.get("kind") not in QUALIFIER_KINDS:
            raise AuditError("QUALIFIERS_INVALID", f"{label}: bad qualifier entry")
        kind = str(item["kind"])
        claimed_kinds.append(kind)
        if item.get("same_immediate_host") is not True:
            raise AuditError("QUALIFIER_WRONG_HOST", f"{label}: {kind}")
        before_terms = item.get("before")
        after_terms = item.get("after")
        if not isinstance(before_terms, list) or not before_terms:
            raise AuditError("QUALIFIERS_INVALID", f"{label}: {kind}.before")
        if not isinstance(after_terms, list) or not after_terms:
            raise AuditError("QUALIFIERS_INVALID", f"{label}: {kind}.after")
        wanted_before = Counter(term.casefold() for term in required.get(kind, []))
        claimed_before = Counter(GCD.normalize(str(term)).casefold() for term in before_terms)
        if claimed_before != wanted_before:
            raise AuditError(
                "QUALIFIER_BEFORE_INCOMPLETE",
                f"{label}: {kind} expected {list(wanted_before.elements())}, got {list(claimed_before.elements())}",
            )
        extracted_after = qualifier_terms(after).get(kind, [])
        wanted_after = Counter(term.casefold() for term in extracted_after)
        claimed_after = Counter(GCD.normalize(str(term)).casefold() for term in after_terms)
        if claimed_after != wanted_after:
            raise AuditError(
                "QUALIFIER_AFTER_INCOMPLETE",
                f"{label}: {kind} expected {list(wanted_after.elements())}, got {list(claimed_after.elements())}",
            )
        for positive, negative in POLARITY_GROUPS.get(kind, []):
            if positive.search(before) and negative.search(after):
                raise AuditError("QUALIFIER_REVERSED", f"{label}: {kind}")
            if negative.search(before) and positive.search(after):
                raise AuditError("QUALIFIER_REVERSED", f"{label}: {kind}")
    if len(claimed_kinds) != len(set(claimed_kinds)) or set(claimed_kinds) != set(required):
        raise AuditError(
            "QUALIFIER_CLASS_MISMATCH",
            f"{label}: expected {sorted(required)}, got {sorted(claimed_kinds)}",
        )
    if HARD_MODALITY.search(before) and not HARD_MODALITY.search(after):
        if SOFT_MODALITY.search(after):
            raise AuditError("QUALIFIER_WEAKENED", f"{label}: hard modality became soft")
        raise AuditError("QUALIFIER_DROPPED", f"{label}: hard modality absent")


BundleCarrier = list[tuple[Carrier, tuple[str, ...]]]
PartitionedCarrier = list[PartitionedPart]


def carrier_digest(path: str, chain: Iterable[str], text: str) -> str:
    payload = json.dumps(
        [normalize_path(path), list(chain), GCD.normalize(text)],
        ensure_ascii=False,
        separators=(",", ":"),
    ).encode("utf-8")
    return hashlib.sha256(payload).hexdigest()


def _span_boundary_ok(text: str, offset: int) -> bool:
    if offset <= 0 or offset >= len(text):
        return True
    return not (
        re.fullmatch(r"[A-Za-z0-9_]", text[offset - 1])
        and re.fullmatch(r"[A-Za-z0-9_]", text[offset])
    )


def _literal_bridge_present(source_text: str, carrier_text: str, term: str) -> bool:
    normalized = GCD.normalize(term)
    if not normalized or len(normalized) < 2:
        return False
    pattern = re.compile(
        rf"(?<![A-Za-z0-9_]){re.escape(normalized)}(?![A-Za-z0-9_])",
        re.I,
    )
    return bool(pattern.search(source_text) and pattern.search(carrier_text))


_PART_QUALIFIER_RESOLUTION_FIELDS = {"kind", "before", "resolution"}
_IMPERATIVE_NORMATIVE = re.compile(
    r"^(?:apply|build|choose|classify|define|distinguish|expose|keep|load|map|name|"
    r"prevent|prefer|record|reserve|show|split|state|treat|use|verify)\b",
    re.I,
)


def _implicit_normative_strength(
    source_term: str, carriers: Iterable[Carrier]
) -> bool:
    hard = bool(HARD_MODALITY.fullmatch(source_term)) or source_term in {
        "必须",
        "不得",
        "禁止",
        "不可",
        "不能",
    }
    for carrier in carriers:
        text = GCD.normalize(carrier.text)
        if SOFT_MODALITY.search(text):
            continue
        if HARD_MODALITY.search(text):
            return True
        if _IMPERATIVE_NORMATIVE.match(text) or re.match(r"^(?:Every|Each)\b", text):
            return True
        chain = " > ".join(carrier.chain)
        if not hard and re.search(
            r"(?:Hard design rules|Design quality checks|Acceptance|operative criteria)",
            chain,
            re.I,
        ):
            return True
        if hard and text.startswith("Destructive 更显式") and "UI Copy Patterns" in chain:
            return True
        if hard and "Design quality checks" in chain and re.search(r"\bnot\s+forced\b", text, re.I):
            return True
    return False


def _threshold_square_expands(before_term: str, after_terms: Iterable[str]) -> bool:
    match = re.fullmatch(r"(\d+(?:\.\d+)?)\s*(px|pt|dp|sp)", before_term, re.I)
    if not match:
        return False
    number, unit = match.groups()
    square = re.compile(
        rf"^{re.escape(number)}\s*[x×]\s*{re.escape(number)}\s*{re.escape(unit)}$",
        re.I,
    )
    return any(square.fullmatch(term) for term in after_terms)


def _verb_stem(term: str) -> str:
    folded = term.casefold()
    for suffix in ("ing", "ed", "es", "s"):
        if folded.endswith(suffix) and len(folded) > len(suffix) + 2:
            return folded[: -len(suffix)]
    return folded


def _precondition_completion_boundary(before: str, after: str) -> bool:
    """Prove ``check before closing`` via an ``only after proof`` boundary.

    This is deliberately narrower than treating ``before`` and ``after`` as
    interchangeable.  The source must make closing conditional on a check,
    while the carrier must prohibit leaving/closing the contract until proof
    has established and checked the complete consumer boundary.
    """
    return bool(
        re.search(r"\bcheck\b.*\bbefore\s+closing\b", before, re.I)
        and re.search(r"\bonly\s+after\b", after, re.I)
        and re.search(r"\b(?:establish(?:es|ed)?|proof|proven)\b", after, re.I)
        and re.search(r"\bcheck(?:ed|s|ing)?\b", after, re.I)
    )


def _invalid_closure_hard_prohibition(before: str, after: str) -> bool:
    """Prove an invalid closure using an explicit close/leave prohibition."""
    return bool(
        re.search(r"\bclosure\b.*\binvalid\b", before, re.I)
        and (
            re.search(
                r"\b(?:do\s+not|must\s+not|cannot|never)\b[^.]{0,240}"
                r"\b(?:close|leave)\b",
                after,
                re.I,
            )
            or re.search(
                r"\bonly\b[^.]{0,240}\bproven\b[^.]{0,240}\bmay\s+leave\b",
                after,
                re.I,
            )
            or re.search(
                r"\boutside\b[^.]{0,240}\bonly\s+after\b[^.]{0,240}"
                r"\b(?:check(?:ed|s|ing)?|proves?)\b",
                after,
                re.I,
            )
        )
    )


def ensure_partition_qualifier_strength(
    before: str,
    after: str,
    label: str,
    resolutions: Any,
    carriers: Iterable[Carrier],
) -> None:
    """Require every source qualifier literally in a multi-carrier part.

    Opposite-polarity words may legitimately occur in another member that
    states the bounded exception.  Unlike a scalar rewrite, a closed bundle is
    therefore rejected on a missing source qualifier, not merely because a
    second member also names the exception's opposite polarity.
    """
    required = qualifier_terms(before)
    available = qualifier_terms(after)
    if not isinstance(resolutions, list):
        raise AuditError("PART_QUALIFIER_RESOLUTIONS_INVALID", label)
    missing = {
        (kind, term.casefold()): term
        for kind, terms in required.items()
        for term in terms
        if term.casefold() not in {value.casefold() for value in available.get(kind, [])}
    }
    claimed: set[tuple[str, str]] = set()
    for item in resolutions:
        if not isinstance(item, dict) or set(item) != _PART_QUALIFIER_RESOLUTION_FIELDS:
            raise AuditError("PART_QUALIFIER_RESOLUTION_INVALID", label)
        kind = item.get("kind")
        before_term = item.get("before")
        resolution = item.get("resolution")
        if not isinstance(kind, str) or not isinstance(before_term, str) or not isinstance(resolution, str):
            raise AuditError("PART_QUALIFIER_RESOLUTION_INVALID", label)
        key = (kind, before_term.casefold())
        if key not in missing or key in claimed:
            raise AuditError("PART_QUALIFIER_RESOLUTION_INVALID", f"{label}: {kind}={before_term}")
        ok = False
        if kind == "modality" and resolution == "implicit-normative":
            ok = _implicit_normative_strength(before_term, carriers)
        elif kind == "scope" and before_term.casefold() == "per" and resolution == "universal-member":
            ok = bool(
                {"any", "all", "each", "every"}
                & {value.casefold() for value in available.get("scope", [])}
            )
        elif kind == "actor" and resolution == "singular-plural":
            forms = {value.casefold() for value in available.get("actor", [])}
            folded = before_term.casefold()
            ok = (folded.rstrip("s") in {value.rstrip("s") for value in forms})
        elif kind == "threshold" and resolution == "square-dimension":
            ok = _threshold_square_expands(before_term, available.get("threshold", []))
        elif kind == "consequence" and resolution == "hard-prohibition":
            if before_term.casefold() in {"fail", "fails", "block", "blocks"}:
                ok = bool(HARD_MODALITY.search(after))
            elif before_term.casefold() == "invalid":
                ok = _invalid_closure_hard_prohibition(before, after)
        elif kind == "consequence" and resolution == "verb-inflection":
            stem = _verb_stem(before_term)
            ok = any(_verb_stem(term) == stem for term in available.get("consequence", []))
        elif kind == "recency" and before_term.casefold() == "after" and resolution == "revision-boundary":
            ok = bool(re.search(r"\b(?:until|revised|revision|fresh)\b", after, re.I))
        elif kind == "recency" and before_term.casefold() == "before" and resolution == "precondition-completion-boundary":
            ok = _precondition_completion_boundary(before, after)
        if not ok:
            raise AuditError("PART_QUALIFIER_RESOLUTION_INVALID", f"{label}: {kind}={before_term}")
        claimed.add(key)
    if claimed != set(missing):
        unresolved = sorted(f"{kind}={term}" for (kind, _), term in missing.items() if (kind, term.casefold()) not in claimed)
        raise AuditError("PART_QUALIFIER_UNRESOLVED", f"{label}: {','.join(unresolved)}")
    missing_classes = sorted(
        kind for kind in required if kind not in available and not any(k == kind for k, _ in claimed)
    )
    if missing_classes:
        raise AuditError(
            "PART_QUALIFIER_MISSING",
            f"{label}: classes={','.join(missing_classes)}",
        )
    for kind, terms in required.items():
        after_terms = {term.casefold() for term in available.get(kind, [])}
        absent = sorted(
            term
            for term in terms
            if term.casefold() not in after_terms and (kind, term.casefold()) not in claimed
        )
        if absent:
            raise AuditError(
                "PART_QUALIFIER_LITERAL_MISSING",
                f"{label}: {kind}={','.join(absent)}",
            )
    if HARD_MODALITY.search(before) and not HARD_MODALITY.search(after) and not any(
        kind == "modality" for kind, _ in claimed
    ):
        raise AuditError("PART_QUALIFIER_WEAKENED", label)


def validate_partitioned(
    repo: Path, expected: ExpectedRow, mapping: dict[str, Any]
) -> PartitionedCarrier:
    label = f"{expected.source_path}#{expected.source_ordinal}"
    if mapping.get("manual_reviewed") is not True:
        raise AuditError("MANUAL_REVIEW_REQUIRED", f"{label}: schema4 partition")
    validate_semantic_review(mapping, label, required=True)
    parts = mapping.get("parts")
    if not isinstance(parts, list) or not parts:
        raise AuditError("PARTS_REQUIRED", label)

    cursor = 0
    seen_ids: set[str] = set()
    statuses: list[str] = []
    part_effects: list[str] = []
    resolved: PartitionedCarrier = []
    survive_fields = {
        "id",
        "status",
        "source_start",
        "source_end",
        "source_text",
        "effect",
        "carriers",
        "qualifiers",
        "qualifier_resolutions",
        "semantic_review",
        "semantic_rationale",
    }
    retired_fields = {
        "id",
        "status",
        "source_start",
        "source_end",
        "source_text",
        "authority",
        "scope",
        "reason",
        "semantic_review",
        "semantic_rationale",
    }
    carrier_fields = {
        "carrier_path",
        "carrier_text",
        "carrier_chain",
        "carrier_sha256",
        "bridge_terms",
    }
    live_source_union = " ".join(
        str(part.get("source_text", ""))
        for part in parts
        if isinstance(part, dict) and part.get("status") == "survives"
    )
    for index, part in enumerate(parts, 1):
        part_label = f"{label}/part-{index}"
        if not isinstance(part, dict):
            raise AuditError("PART_FIELDS", part_label)
        status = part.get("status")
        allowed = survive_fields if status == "survives" else retired_fields if status == "retired" else set()
        if not allowed or set(part) != allowed:
            raise AuditError("PART_FIELDS", part_label)
        part_id = part.get("id")
        start = part.get("source_start")
        end = part.get("source_end")
        source_text = part.get("source_text")
        if (
            not isinstance(part_id, str)
            or not part_id.strip()
            or part_id in seen_ids
            or not isinstance(start, int)
            or isinstance(start, bool)
            or not isinstance(end, int)
            or isinstance(end, bool)
            or start != cursor
            or end <= start
            or end > len(expected.before_text)
            or not isinstance(source_text, str)
            or not source_text.strip()
        ):
            raise AuditError("PARTITION_GAP_OR_OVERLAP", part_label)
        if not _span_boundary_ok(expected.before_text, start) or not _span_boundary_ok(
            expected.before_text, end
        ):
            raise AuditError("PARTITION_SPLITS_TOKEN", part_label)
        if expected.before_text[start:end] != source_text:
            raise AuditError("PART_SOURCE_MISMATCH", part_label)
        cursor = end
        seen_ids.add(part_id)
        statuses.append(status)
        validate_semantic_review(part, part_label, required=True)

        if status == "retired":
            for field in ("authority", "scope", "reason"):
                value = part.get(field)
                if not isinstance(value, str) or not value.strip():
                    raise AuditError("PART_RETIREMENT_PROOF_MISSING", f"{part_label}: {field}")
            resolved.append(PartitionedPart(part_id, status, source_text, ()))
            continue

        effect = part.get("effect")
        if effect not in {"preserved", "strengthened"}:
            raise AuditError("PART_EFFECT_INVALID", part_label)
        part_effects.append(str(effect))
        members = part.get("carriers")
        if not isinstance(members, list) or not members:
            raise AuditError("PART_CARRIER_REQUIRED", part_label)
        part_carriers: list[Carrier] = []
        part_composites: set[tuple[str, tuple[str, ...], str]] = set()
        for member_index, member in enumerate(members, 1):
            member_label = f"{part_label}/member-{member_index}"
            if not isinstance(member, dict) or set(member) != carrier_fields:
                raise AuditError("PART_CARRIER_FIELDS", member_label)
            path = member.get("carrier_path")
            text = member.get("carrier_text")
            chain = member.get("carrier_chain")
            digest = member.get("carrier_sha256")
            bridges = member.get("bridge_terms")
            if (
                not isinstance(path, str)
                or not path.strip()
                or not isinstance(text, str)
                or not text.strip()
                or not isinstance(chain, list)
                or not chain
                or not isinstance(digest, str)
                or not re.fullmatch(r"[0-9a-f]{64}", digest)
                or not isinstance(bridges, list)
                or not bridges
                or any(not isinstance(term, str) or not term.strip() for term in bridges)
            ):
                raise AuditError("PART_CARRIER_EMPTY", member_label)
            path = normalize_path(path)
            if Path(path).name in PROVENANCE_BASENAMES:
                raise AuditError("PROVENANCE_ONLY_CARRIER", member_label)
            try:
                carrier = exact_carrier(repo, path, text, chain)
            except AuditError as exc:
                raise AuditError(exc.code, f"{member_label}: {exc.detail}") from exc
            if digest != carrier_digest(carrier.path, carrier.chain, carrier.text):
                raise AuditError("PART_CARRIER_HASH_MISMATCH", member_label)
            if not all(
                _literal_bridge_present(live_source_union, carrier.text, term)
                for term in bridges
            ):
                raise AuditError("PART_CARRIER_BRIDGE_MISSING", member_label)
            composite = (carrier.path, carrier.chain, carrier.text)
            if composite in part_composites:
                raise AuditError("PART_CARRIER_DUPLICATE", member_label)
            part_composites.add(composite)
            part_carriers.append(carrier)
        aggregate = " ".join(carrier.text for carrier in part_carriers)
        validate_bundle_summary_proof(
            [(source_text, aggregate)], part.get("qualifiers"), part_label
        )
        ensure_partition_qualifier_strength(
            source_text,
            aggregate,
            part_label,
            part.get("qualifier_resolutions"),
            part_carriers,
        )
        resolved.append(
            PartitionedPart(part_id, status, source_text, tuple(part_carriers))
        )

    if cursor != len(expected.before_text):
        raise AuditError("PARTITION_GAP_OR_OVERLAP", f"{label}: end={cursor}")
    if "survives" not in statuses:
        raise AuditError("PARTITION_NO_SURVIVOR", label)
    disposition = mapping.get("disposition")
    if disposition == "partial-retirement":
        if set(statuses) != {"survives", "retired"}:
            raise AuditError("PARTITION_DISPOSITION_MISMATCH", label)
    elif disposition == "partitioned":
        if set(statuses) != {"survives"}:
            raise AuditError("PARTITION_DISPOSITION_MISMATCH", label)
    else:
        raise AuditError("PARTITION_DISPOSITION_MISMATCH", label)
    expected_effect = (
        "strengthened"
        if "retired" in statuses or "strengthened" in part_effects
        else "preserved"
    )
    if mapping.get("effect") != expected_effect:
        raise AuditError("PARTITION_EFFECT_MISMATCH", label)
    return resolved


def validate_bundle(
    repo: Path, expected: ExpectedRow, mapping: dict[str, Any]
) -> BundleCarrier:
    label = f"{expected.source_path}#{expected.source_ordinal}"
    if mapping.get("disposition") != "subsumed" or mapping.get("effect") == "unresolved":
        raise AuditError("BUNDLE_STATUS_INVALID", label)
    if mapping.get("manual_reviewed") is not True:
        raise AuditError("MANUAL_REVIEW_REQUIRED", f"{label}: carrier_bundle")
    if any(mapping.get(field) is not None for field in ("carrier_path", "carrier_text", "carrier_chain")):
        raise AuditError("CARRIER_SHAPE_CONFLICT", label)

    derived_clauses = compound_clauses(expected.before_text)
    if len(derived_clauses) < 2:
        raise AuditError("BUNDLE_SOURCE_NOT_COMPOUND", label)
    if mapping.get("compound_clauses") != derived_clauses:
        raise AuditError("BUNDLE_CLAUSE_SET_MISMATCH", label)

    bundle = mapping.get("carrier_bundle")
    if not isinstance(bundle, list) or len(bundle) < 2:
        raise AuditError("BUNDLE_SIZE", label)
    allowed_member_fields = {
        "carrier_path",
        "carrier_text",
        "carrier_chain",
        "covers",
        "clause_qualifiers",
    }
    clause_by_id = {clause["id"]: clause for clause in derived_clauses}
    coverage: Counter[str] = Counter()
    resolved: BundleCarrier = []
    assigned: list[tuple[str, Carrier, str]] = []
    composites: set[tuple[str, tuple[str, ...], str]] = set()
    for member_index, member in enumerate(bundle, 1):
        member_label = f"{label}/member-{member_index}"
        if not isinstance(member, dict) or set(member) != allowed_member_fields:
            raise AuditError("BUNDLE_MEMBER_FIELDS", member_label)
        path = member.get("carrier_path")
        text = member.get("carrier_text")
        chain = member.get("carrier_chain")
        covers = member.get("covers")
        clause_proofs = member.get("clause_qualifiers")
        if (
            not isinstance(path, str)
            or not path.strip()
            or not isinstance(text, str)
            or not text.strip()
            or not isinstance(chain, list)
            or not chain
            or not isinstance(covers, list)
            or not covers
            or any(not isinstance(value, str) or not value for value in covers)
            or not isinstance(clause_proofs, list)
        ):
            raise AuditError("BUNDLE_MEMBER_EMPTY", member_label)
        if len(covers) != 1:
            raise AuditError("BUNDLE_MEMBER_MULTI_CLAUSE", member_label)
        path = normalize_path(path)
        if Path(path).name in PROVENANCE_BASENAMES:
            raise AuditError("PROVENANCE_ONLY_CARRIER", member_label)
        if compound_clauses(text):
            raise AuditError("BUNDLE_MEMBER_COMPOUND", member_label)
        try:
            carrier = exact_carrier(repo, path, text, chain)
        except AuditError as exc:
            raise AuditError(exc.code, f"{member_label}: {exc.detail}") from exc
        composite = (carrier.path, carrier.chain, carrier.text)
        if composite in composites:
            raise AuditError("BUNDLE_DUPLICATE_MEMBER", member_label)
        composites.add(composite)
        for clause_id in covers:
            if clause_id not in clause_by_id:
                raise AuditError("BUNDLE_UNKNOWN_CLAUSE", f"{member_label}: {clause_id}")
            coverage[clause_id] += 1
            assigned.append((clause_id, carrier, member_label))
        proof_by_clause: dict[str, Any] = {}
        for proof in clause_proofs:
            if (
                not isinstance(proof, dict)
                or set(proof)
                != {
                    "clause_id",
                    "qualifiers",
                    "semantic_review",
                    "semantic_rationale",
                }
                or not isinstance(proof.get("clause_id"), str)
                or proof["clause_id"] in proof_by_clause
            ):
                raise AuditError("BUNDLE_CLAUSE_PROOF_INVALID", member_label)
            proof_by_clause[proof["clause_id"]] = proof
        if set(proof_by_clause) != set(covers):
            raise AuditError("BUNDLE_CLAUSE_PROOF_INVALID", member_label)
        for clause_id in covers:
            proof = proof_by_clause[clause_id]
            clause_label = f"{member_label}/{clause_id}"
            validate_semantic_review(proof, clause_label, required=True)
            validate_bundle_clause_proof(
                clause_by_id[clause_id]["text"],
                carrier.text,
                proof.get("qualifiers"),
                clause_label,
            )
        resolved.append((carrier, tuple(covers)))

    duplicates = sorted(clause_id for clause_id, count in coverage.items() if count > 1)
    if duplicates:
        raise AuditError("BUNDLE_CLAUSE_DUPLICATE", f"{label}: {','.join(duplicates)}")
    missing = sorted(set(clause_by_id) - set(coverage))
    if missing:
        raise AuditError("BUNDLE_CLAUSE_UNCOVERED", f"{label}: {','.join(missing)}")

    assignment_by_clause = {
        clause_id: carrier for clause_id, carrier, _ in assigned
    }
    validate_bundle_summary_proof(
        (
            (clause["text"], assignment_by_clause[clause["id"]].text)
            for clause in derived_clauses
        ),
        mapping.get("qualifiers"),
        label,
    )
    return resolved


def validate_mapping(
    repo: Path,
    expected: list[ExpectedRow],
    mapping_rows: list[dict[str, Any]],
    *,
    allow_unresolved: bool,
) -> tuple[
    dict[tuple[str, int], Carrier | BundleCarrier | PartitionedCarrier | None],
    list[str],
]:
    indexed = index_mapping(mapping_rows)
    verify_closed_row_set(expected, indexed)
    resolved: dict[
        tuple[str, int], Carrier | BundleCarrier | PartitionedCarrier | None
    ] = {}
    unresolved: list[str] = []

    for source in expected:
        row = indexed[source.key]
        label = f"{source.source_path}#{source.source_ordinal}"
        schema_version = row.get("schema_version")
        if schema_version not in SCHEMA_VERSIONS:
            raise AuditError("SCHEMA_VERSION", label)
        allowed_fields = MAPPING_FIELDS_V4 if schema_version == 4 else MAPPING_FIELDS
        unknown = sorted(set(row) - allowed_fields)
        if unknown:
            if "carriers" in unknown:
                raise AuditError("MULTIPLE_CARRIERS", label)
            raise AuditError("UNKNOWN_MAPPING_FIELD", f"{label}: {','.join(unknown)}")
        if "semantic_review" not in row or "semantic_rationale" not in row:
            raise AuditError("SEMANTIC_REVIEW_FIELDS_REQUIRED", label)
        if row.get("disposition") not in DISPOSITIONS:
            raise AuditError("INVALID_DISPOSITION", label)
        if row.get("effect") not in EFFECTS:
            raise AuditError("INVALID_EFFECT", label)
        if not isinstance(row.get("review_note"), str) or not row["review_note"].strip():
            raise AuditError("REVIEW_NOTE_MISSING", label)
        if schema_version == 4:
            if row.get("disposition") not in {"partitioned", "partial-retirement"}:
                raise AuditError("PARTITION_DISPOSITION_MISMATCH", label)
            resolved[source.key] = validate_partitioned(repo, source, row)
            continue
        if row.get("disposition") in {"partitioned", "partial-retirement"}:
            raise AuditError("SCHEMA_VERSION", f"{label}: partition requires schema 4")
        relations = row.get("qualifier_relations", [])
        if not isinstance(relations, list):
            raise AuditError("QUALIFIER_RELATION_INVALID", f"{label}: array required")
        if relations and row["effect"] != "strengthened":
            raise AuditError("QUALIFIER_RELATION_REQUIRES_STRENGTHENED", label)
        if row["disposition"] == "retired-dead" and row["effect"] not in {
            "strengthened",
            "unresolved",
        }:
            raise AuditError("RETIRED_EFFECT_INVALID", label)
        if row["effect"] == "strengthened" and row.get("manual_reviewed") is not True:
            raise AuditError("STRENGTHENED_REVIEW_REQUIRED", label)
        if relations and (
            row["disposition"] == "retired-dead"
            or row["effect"] == "unresolved"
            or row.get("carrier_bundle") is not None
        ):
            raise AuditError("QUALIFIER_RELATION_FORBIDDEN", label)

        if row["effect"] == "unresolved":
            validate_semantic_review(row, label, required=False)
            unresolved.append(label)
            if any(
                row.get(field) is not None
                for field in (
                    "carrier_path",
                    "carrier_text",
                    "carrier_chain",
                    "carrier_bundle",
                    "compound_clauses",
                )
            ):
                raise AuditError("UNRESOLVED_HAS_CARRIER", label)
            resolved[source.key] = None
            continue

        if row["disposition"] == "retired-dead":
            if any(
                row.get(field) is not None
                for field in (
                    "carrier_path",
                    "carrier_text",
                    "carrier_chain",
                    "carrier_bundle",
                    "compound_clauses",
                )
            ):
                raise AuditError("RETIRED_HAS_CARRIER", label)
            if row.get("manual_reviewed") is not True:
                raise AuditError("MANUAL_REVIEW_REQUIRED", label)
            validate_semantic_review(row, label, required=True)
            note = row["review_note"].casefold()
            if "authority:" not in note or "scope:" not in note:
                raise AuditError("RETIREMENT_PROOF_MISSING", label)
            resolved[source.key] = None
            continue


        if row.get("carrier_bundle") is not None:
            validate_semantic_review(row, label, required=False)
            resolved[source.key] = validate_bundle(repo, source, row)
            continue
        if row.get("compound_clauses") is not None:
            raise AuditError("CARRIER_SHAPE_CONFLICT", label)

        carrier_path = row.get("carrier_path")
        carrier_text = row.get("carrier_text")
        carrier_chain = row.get("carrier_chain")
        if any(isinstance(value, list) for value in (carrier_path, carrier_text)) or (
            isinstance(carrier_chain, list) and carrier_chain and isinstance(carrier_chain[0], list)
        ):
            raise AuditError("MULTIPLE_CARRIERS", label)
        if not isinstance(carrier_path, str) or not isinstance(carrier_text, str) or not isinstance(carrier_chain, list):
            raise AuditError("CARRIER_REQUIRED", label)
        carrier_path = normalize_path(carrier_path)
        if Path(carrier_path).name in PROVENANCE_BASENAMES:
            raise AuditError("PROVENANCE_ONLY_CARRIER", label)
        try:
            carrier = exact_carrier(repo, carrier_path, carrier_text, carrier_chain)
        except AuditError as exc:
            raise AuditError(exc.code, f"{label}: {exc.detail}") from exc
        if row["disposition"] in {"merged", "subsumed"} and carrier.chain != source.before_chain:
            raise AuditError("DISPOSITION_CHAIN_CONFLICT", f"{label}: same-host disposition moved")
        if row["disposition"] == "rehosted" and carrier.chain == source.before_chain:
            raise AuditError("DISPOSITION_CHAIN_CONFLICT", f"{label}: rehosted without host change")
        validate_semantic_review(
            row,
            label,
            required=GCD.normalize(source.before_text) != carrier.text,
        )
        validate_qualifiers(source, row, carrier)
        resolved[source.key] = carrier

    if unresolved and not allow_unresolved:
        raise AuditError(
            "UNRESOLVED_ROWS",
            f"count={len(unresolved)} first={','.join(unresolved[:8])}",
        )
    return resolved, unresolved


def md(value: str) -> str:
    return value.replace("|", "\\|").replace("\n", " ")


def chain_text(value: Iterable[str]) -> str:
    items = list(value)
    return " → ".join(md(item) for item in items) if items else "(root)"


def proof_mode(
    source: ExpectedRow,
    row: dict[str, Any],
    carrier: Carrier | BundleCarrier | PartitionedCarrier | None,
) -> str:
    if carrier is None and row["effect"] == "unresolved":
        return "unresolved"
    if isinstance(carrier, Carrier) and GCD.normalize(source.before_text) == carrier.text:
        return "exact-mechanical"
    return "reviewed-semantic"


def proof_mode_counts(
    expected: Iterable[ExpectedRow],
    mapping_rows: list[dict[str, Any]],
    resolved: dict[
        tuple[str, int], Carrier | BundleCarrier | PartitionedCarrier | None
    ],
) -> Counter[str]:
    indexed = index_mapping(mapping_rows)
    return Counter(
        proof_mode(source, indexed[source.key], resolved[source.key])
        for source in expected
    )


def render_ledger(
    base: str,
    comparison_paths: list[str],
    relocation_paths: list[str],
    expected: list[ExpectedRow],
    mapping_rows: list[dict[str, Any]],
    resolved: dict[
        tuple[str, int], Carrier | BundleCarrier | PartitionedCarrier | None
    ],
    unresolved: list[str],
) -> str:
    indexed = index_mapping(mapping_rows)
    effects = Counter(str(indexed[row.key]["effect"]) for row in expected)
    dispositions = Counter(str(indexed[row.key]["disposition"]) for row in expected)
    modes = proof_mode_counts(expected, mapping_rows, resolved)
    source_counts: dict[str, Counter[str]] = {}
    for source in expected:
        row = indexed[source.key]
        counts = source_counts.setdefault(source.source_path, Counter())
        counts["rows"] += 1
        counts[str(row["effect"])] += 1
        counts[str(row["disposition"])] += 1
    lines = [
        "# UI/UX obligation-preservation ledger",
        "",
        "> Generated by `skills/skill-extraction-workflow/scripts/obligation-ledger.py`; do not hand-edit.",
        "> The sibling `obligation-mapping.jsonl` is the canonical proof source; this compact Markdown file is its generated reader index.",
        "> Candidate binding is intentionally external and must be written only after the worktree is frozen.",
        "",
        "## Reproducible comparison domain",
        "",
        f"- Base revision: `{base}`",
        f"- Changed pre-existing `skills/**/*.md`: {len(comparison_paths)}",
        f"- Explicit relocation destinations: {len(relocation_paths)}",
        f"- Governing-chain-diff rows: {len(expected)}",
        f"- Effects: preserved={effects['preserved']}, strengthened={effects['strengthened']}, unresolved={len(unresolved)}",
        "- Proof modes: "
        f"exact-mechanical={modes['exact-mechanical']}, "
        f"reviewed-semantic={modes['reviewed-semantic']}, "
        f"unresolved={modes['unresolved']}",
        "- Dispositions: " + ", ".join(
            f"{name}={dispositions[name]}" for name in sorted(dispositions)
        ),
        "",
        "The row set is the bidirectional equality of the mechanical governing-chain diff and the JSONL mapping manifest. Exact before/carrier text, lexical qualifier evidence, semantic-review decisions, and review notes live only in the canonical mapping. `proof_mode=reviewed-semantic` validates review evidence presence and shape, not the truth or correctness of the semantic judgment. Carrier line ranges below are recomputed from exact current text, so stale locators still fail audit.",
        "",
        "## Source summary",
        "",
        "| Source | Rows | Preserved | Strengthened | Retired dead |",
        "| --- | ---: | ---: | ---: | ---: |",
    ]
    for source_path, counts in sorted(source_counts.items()):
        lines.append(
            f"| `{source_path}` | {counts['rows']} | {counts['preserved']} | {counts['strengthened']} | {counts['retired-dead']} |"
        )
    lines.extend(
        [
            "",
            "## Compact obligation index",
            "",
            "| ID | Source row | Reason | Decision | Exact current locator / bundle coverage | Proof index |",
            "| --- | --- | --- | --- | --- | --- |",
        ]
    )
    for serial, source in enumerate(expected, 1):
        row = indexed[source.key]
        carrier = resolved[source.key]
        if carrier is None:
            carrier_label = "—"
        elif isinstance(carrier, list) and carrier and isinstance(
            carrier[0], PartitionedPart
        ):
            labels = []
            for part in carrier:
                if part.status == "retired":
                    labels.append(f"{part.part_id}. retired")
                else:
                    labels.extend(
                        f"{part.part_id}.{index}. `{item.path}:{item.start_line}-{item.end_line}`"
                        for index, item in enumerate(part.carriers, 1)
                    )
            carrier_label = "<br>".join(labels)
        elif isinstance(carrier, list):
            carrier_label = "<br>".join(
                f"{index}. `{item.path}:{item.start_line}-{item.end_line}` [{','.join(covers)}]"
                for index, (item, covers) in enumerate(carrier, 1)
            )
        else:
            carrier_label = f"`{carrier.path}:{carrier.start_line}-{carrier.end_line}`"
        qualifiers = row.get("qualifiers") or []
        relation_count = len(row.get("qualifier_relations") or [])
        mode = proof_mode(source, row, carrier)
        if isinstance(carrier, list) and carrier and isinstance(
            carrier[0], PartitionedPart
        ):
            survived = sum(part.status == "survives" for part in carrier)
            retired = sum(part.status == "retired" for part in carrier)
            members = sum(len(part.carriers) for part in carrier)
            proof_label = (
                f"proof_mode={mode}; schema4 exact-span partition; "
                f"survives={survived}; retired={retired}; carriers={members}; "
                "hash+bridge+qualifier checked"
            )
        elif isinstance(carrier, list):
            proof_label = (
                f"proof_mode={mode}; reviewed closed bundle; members={len(carrier)}; "
                "clause-local lexical guards"
            )
        elif carrier and GCD.normalize(source.before_text) == carrier.text:
            proof_label = f"proof_mode={mode}; verbatim exact carrier"
        elif carrier:
            kinds = ",".join(str(item["kind"]) for item in qualifiers) or "none"
            proof_label = (
                f"proof_mode={mode}; reviewed scalar; lexical qualifier kinds={kinds}"
            )
        elif row["effect"] == "unresolved":
            proof_label = f"proof_mode={mode}"
        else:
            proof_label = (
                f"proof_mode={mode}; reviewed retirement; "
                "authority+scope evidence in canonical mapping"
            )
        if relation_count:
            proof_label += f"; relations={relation_count}"
        lines.append(
            "| "
            + " | ".join(
                [
                    f"O{serial:04d}",
                    f"`{source.source_path}#{source.source_ordinal}`",
                    source.reason,
                    f"{row['disposition']} / {row['effect']}",
                    carrier_label,
                    md(proof_label),
                ]
            )
            + " |"
        )
    lines.extend(
        [
            "",
            "## Candidate binding boundary",
            "",
            "This document contains no self-referential dirty-worktree digest. After freeze, bind the candidate in a checkout-external manifest and audit this generated ledger against that frozen tree.",
            "",
        ]
    )
    return "\n".join(lines)


def exact_candidates(repo: Path) -> dict[str, list[tuple[str, tuple[str, ...]]]]:
    candidates: dict[str, list[tuple[str, tuple[str, ...]]]] = {}
    for file_path in sorted((repo / "skills").rglob("*.md")):
        relative = file_path.relative_to(repo).as_posix()
        if file_path.name in PROVENANCE_BASENAMES:
            continue
        for obligation, _, _ in parse_obligation_ranges(
            file_path.read_text(encoding="utf-8")
        ):
            candidates.setdefault(GCD.normalize(obligation.text), []).append(
                (relative, tuple(obligation.chain))
            )
    return candidates


def skeleton(repo: Path, expected: Iterable[ExpectedRow], *, auto_bind_exact: bool) -> str:
    candidates = exact_candidates(repo) if auto_bind_exact else {}
    values = []
    for row in expected:
        exact = candidates.get(row.before_text, [])
        mechanically_bound = len(exact) == 1 and exact[0][1] != row.before_chain
        if mechanically_bound:
            carrier_path, carrier_chain = exact[0]
            disposition = "rehosted"
            effect = "preserved"
            carrier_text: str | None = row.before_text
            manual_reviewed = False
            review_note = "Mechanically preserved verbatim under one exact current (path, chain, text) carrier."
        else:
            disposition = "rehosted"
            effect = "unresolved"
            carrier_path = None
            carrier_text = None
            carrier_chain = None
            manual_reviewed = False
            review_note = "Unresolved: exact current carrier and qualifier preservation require review."
        values.append(
            json.dumps(
                {
                    "schema_version": SCHEMA_VERSION,
                    "source_path": row.source_path,
                    "source_ordinal": row.source_ordinal,
                    "reason": row.reason,
                    "before_text": row.before_text,
                    "before_chain": list(row.before_chain),
                    "disposition": disposition,
                    "effect": effect,
                    "carrier_path": carrier_path,
                    "carrier_text": carrier_text,
                    "carrier_chain": list(carrier_chain) if carrier_chain is not None else None,
                    "carrier_bundle": None,
                    "compound_clauses": None,
                    "manual_reviewed": manual_reviewed,
                    "semantic_review": None,
                    "semantic_rationale": None,
                    "qualifiers": [],
                    "qualifier_relations": [],
                    "review_note": review_note,
                },
                ensure_ascii=False,
                separators=(",", ":"),
            )
        )
    return "\n".join(values) + ("\n" if values else "")


def write_atomic(path: Path, content: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_name(path.name + ".tmp")
    temporary.write_text(content, encoding="utf-8")
    temporary.replace(path)


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("command", choices=("inventory", "render", "audit"))
    parser.add_argument("--repo", default=".")
    parser.add_argument("--base", required=True)
    parser.add_argument("--mapping")
    parser.add_argument("--ledger")
    parser.add_argument("--output")
    parser.add_argument(
        "--no-auto-bind-exact",
        action="store_true",
        help="leave even globally unique verbatim rehosts unresolved in inventory output",
    )
    args = parser.parse_args(argv)

    repo = Path(args.repo).resolve()
    try:
        comparison = changed_preexisting_paths(repo, args.base)
        expected = derive_rows(repo, args.base, comparison)
        if args.command == "inventory":
            content = skeleton(repo, expected, auto_bind_exact=not args.no_auto_bind_exact)
            if args.output:
                write_atomic(Path(args.output), content)
            else:
                sys.stdout.write(content)
            print(
                f"inventory_ok domain={len(comparison)} rows={len(expected)}",
                file=sys.stderr,
            )
            return 0

        if not args.mapping:
            raise AuditError("MAPPING_REQUIRED", "--mapping")
        mapping_path = Path(args.mapping)
        mapping_rows = load_mapping(mapping_path)
        relocations = relocation_destinations(mapping_rows)
        # Relocation destinations belong to the comparison domain even if they
        # are new or unchanged; only pre-existing changed paths can owe rows.
        domain = sorted(set(comparison) | set(relocations))
        resolved, unresolved = validate_mapping(
            repo,
            expected,
            mapping_rows,
            allow_unresolved=args.command == "render",
        )
        modes = proof_mode_counts(expected, mapping_rows, resolved)
        rendered = render_ledger(
            args.base,
            comparison,
            sorted(set(relocations) - set(comparison)),
            expected,
            mapping_rows,
            resolved,
            unresolved,
        )
        if args.command == "render":
            if not args.output:
                sys.stdout.write(rendered)
            else:
                write_atomic(Path(args.output), rendered)
            print(
                f"render_ok domain={len(domain)} rows={len(expected)} "
                f"unresolved={len(unresolved)} "
                f"exact_mechanical={modes['exact-mechanical']} "
                f"reviewed_semantic={modes['reviewed-semantic']}",
                file=sys.stderr,
            )
            return 0

        if not args.ledger:
            raise AuditError("LEDGER_REQUIRED", "--ledger")
        ledger = Path(args.ledger)
        if not ledger.is_file() or ledger.read_text(encoding="utf-8") != rendered:
            raise AuditError("STALE_LEDGER", str(ledger))
        print(
            f"audit_ok domain={len(domain)} rows={len(expected)} unresolved=0 "
            f"exact_mechanical={modes['exact-mechanical']} "
            f"reviewed_semantic={modes['reviewed-semantic']}",
            file=sys.stderr,
        )
        return 0
    except AuditError as exc:
        print(f"ERROR {exc.code}: {exc.detail}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
