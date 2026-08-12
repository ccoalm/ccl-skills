#!/usr/bin/env python3
"""Executable spec for the row-set predicate in references/rule-consolidation.md.

The obligation-preservation table's row set is defined there as: every obligation
whose GOVERNING CHAIN differs before vs after, plus every obligation whose own
text left a rewritten line. That predicate is prose an agent applies by hand, so
this file computes it mechanically over two revisions of a markdown file and
prints the derived row set — making the rule reproducible instead of asserted,
and giving the challenge's "independently recompute the row set" obligation a
tool it can actually run.

The governing chain of an obligation is the ordered stack of normative ancestors
it hangs under: the enclosing headings (outermost first) then any enclosing list
items, each taken by NORMATIVE CONTENT rather than by label or position — so a
parent that keeps its wording but moves does not count as changed, while one that
keeps its position and rewrites its condition does.

Usage:
    governing-chain-diff.py BEFORE_FILE AFTER_FILE
    governing-chain-diff.py --rev BEFORE_REV AFTER_REV PATH [--repo DIR]

Exit status:
    0  the derived row set is empty (no obligation changed chain or left a line)
    1  the derived row set is non-empty (those obligations owe table rows)
    2  usage or input error
"""

from __future__ import annotations

import argparse
import re
import subprocess
import sys
from dataclasses import dataclass

# A heading line: capture level and text.
_HEADING = re.compile(r"^(#{1,6})\s+(.*\S)\s*$")
# A list item: capture indent width, and the text after the bullet/number marker.
_LIST_ITEM = re.compile(r"^(\s*)(?:[-*+]|\d+[.)])\s+(.*\S)\s*$")
# A markdown table row (leading pipe); these are data rows, not prose obligations.
_TABLE_ROW = re.compile(r"^\s*\|")
# A fenced code block delimiter.
_FENCE = re.compile(r"^\s*(?:```|~~~)")


def normalize(text: str) -> str:
    """Collapse whitespace so cosmetic rewrapping is not read as a change."""
    return " ".join(text.split())


def content_key(text: str, *, chars: int = 120) -> str:
    """Identity of an ancestor BY NORMATIVE CONTENT, not by label or position.

    A bounded prefix is used so that appending a clause to a parent counts as the
    same host while rewriting its opening condition does not. The bound is part
    of the spec: `test_governing_chain_diff.sh` pins both directions.
    """
    return normalize(text)[:chars]


@dataclass(frozen=True)
class Obligation:
    text: str
    chain: tuple[str, ...]

    @property
    def key(self) -> str:
        return normalize(self.text)


# Sentence boundary: an ASCII terminator followed by whitespace, OR a CJK
# terminator (。；：！？) with no whitespace requirement — CJK sentences abut
# directly. Deliberately simple — it only has to split dense prose into
# clause-sized units, and both revisions are split the same way, so a boundary
# this misplaces still compares equal. Without the CJK arm, a dense CJK bullet
# is one unsplittable block and a qualifier migrating between its sentences is
# invisible — the exact failure this tool exists to catch. Known limitation:
# ，、 are NOT split points (they are the dominant CJK clause separator and
# splitting there would multiply micro-obligations into noise); a qualifier
# moving between comma-joined clauses still surfaces, but as coarser
# left-a-rewritten-line / governing-chain-changed rows on the enclosing block.
_SENTENCE = re.compile(r"(?<=[.;:!?])\s+|(?<=[。；：！？])")

# CJK ideograph/kana chars count double toward the obligation-length floor:
# normalize() counts characters, and 25 ASCII chars is a short clause while 25
# CJK chars is a full multi-clause rule, so an unweighted floor silently drops
# short CJK gates (e.g. an 18-char blast-radius question) from the derived row
# set. The floor itself scales down for ideograph-bearing text (min_chars*2//3,
# default 25 → 16 effective chars ≈ 8 CJK chars) because CJK packs a complete
# gate into far fewer characters; English text is unaffected (zero ideographs →
# effective length == len, floor min_chars unchanged). Punctuation ranges
# (U+3000-303F, U+FF00-FFEF) are deliberately EXCLUDED: one fullwidth mark in
# an otherwise-English block must not flip the floor or inflate the length.
# The sentence splitter above still treats 。；：！？ as terminators — that is
# about boundary placement, not about length weighting.
_CJK = re.compile(r"[぀-ヿ㐀-䶿一-鿿豈-﫿𠀀-𪛟]")


def effective_len(text: str) -> int:
    return len(text) + len(_CJK.findall(text))


def length_floor(text: str, min_chars: int) -> int:
    # Scaled, not hardcoded: a flat 16 would make the min_chars knob inert on
    # CJK text (raising it filters nothing) and would RAISE the floor when a
    # caller lowers it below 16 to catch shorter gates — a silent row-set loss
    # on the merge-blocking deriver. 2//3 tracks the CJK density ratio.
    return (min_chars * 2 // 3) if _CJK.search(text) else min_chars


def split_obligations(block: str, chain: tuple[str, ...], min_chars: int) -> list[Obligation]:
    """Decompose one item/paragraph into sentence-level obligations.

    Granularity matters: in a dense entrypoint a single bullet can be thousands of
    bytes and carry several distinct gates, and the failure this whole rule exists
    for — a qualifier drifting from the rule it modified onto the neighbouring one
    — happens BETWEEN sentences of two such bullets. A line-granular walk sees only
    "both bullets changed" and never surfaces the clause that moved.

    The block's FIRST sentence is what gives the block its normative identity, so
    it carries the enclosing chain unchanged and becomes the immediate host of
    every later sentence in the same block.
    """
    parts = [p.strip() for p in _SENTENCE.split(block) if effective_len(normalize(p)) >= length_floor(normalize(p), min_chars)]
    if not parts:
        return []
    out = [Obligation(text=parts[0], chain=chain)]
    host = chain + (content_key(parts[0]),)
    out.extend(Obligation(text=p, chain=host) for p in parts[1:])
    return out


def parse(source: str, *, min_chars: int = 25) -> list[Obligation]:
    """Extract obligations with their governing chains.

    An obligation is a list item or a standalone prose paragraph long enough to
    carry a gate (`min_chars` after normalization). Table rows and fenced code are
    skipped: they are data, not obligations that can be re-parented.
    """
    obligations: list[Obligation] = []
    headings: list[tuple[int, str]] = []  # (level, content_key)
    list_stack: list[tuple[int, str]] = []  # (indent, content_key)
    paragraph: list[str] = []
    in_fence = False
    # A list item may wrap across several lines. Its continuation lines belong to
    # the item, not to a following paragraph — folding them in is what makes a
    # cosmetic rewrap compare equal instead of reading as a rewritten line.
    pending_item: list[str] | None = None
    pending_indent = 0

    def chain_now() -> tuple[str, ...]:
        return tuple([key for _, key in headings] + [key for _, key in list_stack])

    def flush_item() -> None:
        nonlocal pending_item
        if pending_item is None:
            return
        text = " ".join(pending_item)
        obligations.extend(split_obligations(text, chain_now(), min_chars))
        list_stack.append((pending_indent, content_key(text)))
        pending_item = None

    def flush_paragraph() -> None:
        if not paragraph:
            return
        text = " ".join(paragraph)
        obligations.extend(split_obligations(text, chain_now(), min_chars))
        paragraph.clear()

    for raw in source.split("\n"):
        if _FENCE.match(raw):
            flush_item()
            flush_paragraph()
            in_fence = not in_fence
            continue
        if in_fence:
            continue

        if not raw.strip():
            flush_item()
            flush_paragraph()
            # A blank line ends a paragraph but not the enclosing list context;
            # markdown allows loose lists, so the stack is popped by indentation.
            continue

        if _TABLE_ROW.match(raw):
            flush_item()
            flush_paragraph()
            continue

        heading = _HEADING.match(raw)
        if heading:
            flush_item()
            flush_paragraph()
            level = len(heading.group(1))
            while headings and headings[-1][0] >= level:
                headings.pop()
            headings.append((level, content_key(heading.group(2))))
            list_stack.clear()
            continue

        item = _LIST_ITEM.match(raw)
        if item:
            flush_item()
            flush_paragraph()
            indent = len(item.group(1).expandtabs(4))
            while list_stack and list_stack[-1][0] >= indent:
                list_stack.pop()
            pending_item = [item.group(2)]
            pending_indent = indent
            continue

        # An indented non-item line directly under an open item continues it.
        if pending_item is not None and (
            len(raw) - len(raw.lstrip())
        ) > pending_indent:
            pending_item.append(raw.strip())
            continue

        flush_item()
        # An UNINDENTED paragraph closes the list: in markdown it is a sibling of
        # the list, not a child of its last item. Without this the paragraph would
        # inherit whichever item happened to come last, so editing that item would
        # report every following paragraph as re-parented — a false positive that
        # is worse than a miss here, because it buries the real rows in noise.
        if not raw[: len(raw) - len(raw.lstrip())]:
            list_stack.clear()
        paragraph.append(raw.strip())

    flush_item()
    flush_paragraph()
    return obligations


@dataclass(frozen=True)
class Row:
    reason: str  # "left-a-rewritten-line" | "governing-chain-changed"
    text: str
    before_chain: tuple[str, ...] = ()
    after_chain: tuple[str, ...] = ()


def derive_row_set(before: str, after: str) -> list[Row]:
    """Apply the row-set predicate: chain changed, or own text left a line."""
    before_obligations = parse(before)
    after_obligations = parse(after)
    after_by_key: dict[str, list[Obligation]] = {}
    for obligation in after_obligations:
        after_by_key.setdefault(obligation.key, []).append(obligation)

    rows: list[Row] = []
    for obligation in before_obligations:
        survivors = after_by_key.get(obligation.key)
        if not survivors:
            rows.append(Row(reason="left-a-rewritten-line", text=obligation.text))
            continue
        # Survives verbatim: it owes a row only if its governing chain moved.
        # Compare against the closest surviving chain so a duplicated obligation
        # is not reported as re-parented merely because a copy sits elsewhere.
        if any(s.chain == obligation.chain for s in survivors):
            continue
        rows.append(
            Row(
                reason="governing-chain-changed",
                text=obligation.text,
                before_chain=obligation.chain,
                after_chain=survivors[0].chain,
            )
        )
    return rows


def read_rev(repo: str, rev: str, path: str) -> str:
    result = subprocess.run(
        ["git", "-C", repo, "show", f"{rev}:{path}"],
        capture_output=True,
        text=True,
    )
    if result.returncode != 0:
        print(f"error: cannot read {rev}:{path}", file=sys.stderr)
        raise SystemExit(2)
    return result.stdout


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(add_help=True, description=__doc__)
    parser.add_argument("--rev", nargs=3, metavar=("BEFORE_REV", "AFTER_REV", "PATH"))
    parser.add_argument("--repo", default=".")
    parser.add_argument("files", nargs="*", metavar="BEFORE_FILE AFTER_FILE")
    args = parser.parse_args(argv)

    if args.rev:
        before_rev, after_rev, path = args.rev
        before = read_rev(args.repo, before_rev, path)
        after = read_rev(args.repo, after_rev, path)
        label = path
    elif len(args.files) == 2:
        try:
            before = open(args.files[0], encoding="utf-8").read()
            after = open(args.files[1], encoding="utf-8").read()
        except OSError as exc:
            print(f"error: {exc}", file=sys.stderr)
            return 2
        label = args.files[1]
    else:
        parser.print_usage(sys.stderr)
        return 2

    rows = derive_row_set(before, after)
    print(f"governing-chain-diff: {label}")
    print(f"derived row set: {len(rows)}")
    for row in rows:
        print(f"  [{row.reason}] {normalize(row.text)[:110]}")
        if row.reason == "governing-chain-changed":
            print(f"      before chain: {' > '.join(c[:44] for c in row.before_chain)}")
            print(f"      after  chain: {' > '.join(c[:44] for c in row.after_chain)}")
    return 1 if rows else 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
