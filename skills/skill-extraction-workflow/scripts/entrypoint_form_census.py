#!/usr/bin/env python3
"""Count the guidance FORM of an entrypoint's rules, so form claims carry a ruler.

`references/rule-consolidation.md`'s form-by-failure table picks the guidance form
from the baseline failure a rule answers. Judging whether an entrypoint follows
its own table needs a number, and the number is worthless unless the next round
can recompute it: an earlier round recorded a prohibitive-token count with no
recorded method, and a later round counting the same file by a different method
got a different figure, so no trend could be claimed in either direction. That is
the failure this script exists to prevent -- not the counting itself, which is
easy, but the counting being reproducible.

What is counted, stated here because the definition IS the instrument:

- A `rule` is one top-level `- ` bullet inside `## Core Rules`, together with
  every continuation and sub-bullet line up to the next top-level bullet or the
  next heading. Sub-bullets are not separate rules; they are part of the rule
  whose form is being judged.
- A `prohibitive token` is a match of PROHIBITIVE_RE: the imperative-negative
  vocabulary the form table calls the right form for a discipline slip and the
  wrong form for every other baseline failure. Case is significant only where
  the capitalised spelling is itself the emphasis (MUST / NEVER / ALWAYS).
- A `named baseline failure` is a match of FAILURE_SHAPE_RE: the rule states the
  observed failure it answers, rather than only the prohibition. The form table
  needs the baseline failure to pick a form, so a prohibition with no named
  failure is a rule whose form was never derived from anything.

The reported diagnostic is `unanchored_prohibition_rules`: rules carrying at
least one prohibitive token and no named baseline failure. That is the set the
form table has something to say about; it is not a defect count, because a
discipline-slip rule is legitimately a prohibition -- it is the set a form pass
must classify one by one.

Exit status is 0 whenever the file parses; this is an instrument, not a gate.
Nothing here decides whether a form is right, and no threshold is encoded: a
threshold would make the ruler an argument for its own reading.
"""

from __future__ import annotations

import argparse
import json
import re
import statistics
import sys
from pathlib import Path

# The imperative-negative vocabulary. Ordered longest-first only for readability;
# matches are counted independently, so a phrase and a word inside it are both
# counted when both appear (e.g. "must not" contributes to `must` as well) --
# stated so the figure is read as token occurrences, never as distinct rules.
PROHIBITIVE_RE = re.compile(
    r"\bMUST NOT\b|\bMUST\b|\bNEVER\b|\bALWAYS\b"
    r"|\bmust not\b|\bmust\b|\bnever\b|\bcannot\b|\bcan not\b"
    r"|\bdo not\b|\bdon't\b|\bdoes not\b|\bmay not\b|\bshall not\b"
    r"|\bforbid(?:s|den)?\b|\bprohibit(?:s|ed)?\b|\bno[tn]-negotiable\b"
)

# The rule states the failure it answers. These are the phrasings this package
# already uses for that job; a rule that names its baseline failure some other
# way reads as unanchored here, which biases the diagnostic toward over-reporting
# rather than under-reporting -- the safe direction for a set meant to be walked.
FAILURE_SHAPE_RE = re.compile(
    r"failure shape|failure-shape|failure mode|the failure it prevents"
    r"|recurring shape|observed failure|the exact .{0,40}failure"
    r"|recurrence signal|the tell that|the defect this prevents"
    r"|failure it prevents|the dodge this prevents",
    re.IGNORECASE,
)

BOLD_RE = re.compile(r"\*\*[^*]+\*\*")
CORE_RULES_HEADING = "## Core Rules"


def parse_rules(text: str) -> list[dict]:
    """Return one record per top-level bullet inside `## Core Rules`."""
    lines = text.splitlines()
    try:
        start = next(i for i, l in enumerate(lines) if l.strip() == CORE_RULES_HEADING)
    except StopIteration:
        raise SystemExit(f"entrypoint_form_census_error: no {CORE_RULES_HEADING!r} heading")
    # The section ends at the next same-level heading.
    end = len(lines)
    for i in range(start + 1, len(lines)):
        if lines[i].startswith("## "):
            end = i
            break

    rules: list[dict] = []
    current: dict | None = None
    group = None
    for line in lines[start + 1 : end]:
        if line.startswith("### "):
            group = line[4:].strip()
            current = None
            continue
        if line.startswith("- "):
            current = {"group": group, "lines": [line]}
            rules.append(current)
            continue
        if current is not None:
            # A blank line does not close a rule: sub-bullets and continuations
            # are separated by blanks in this file, and treating a blank as a
            # terminator would split rules and inflate the rule count.
            current["lines"].append(line)
    return rules


def measure(rule: dict) -> dict:
    body = "\n".join(rule["lines"])
    prohibitions = PROHIBITIVE_RE.findall(body)
    named_failure = bool(FAILURE_SHAPE_RE.search(body))
    return {
        "group": rule["group"],
        "head": rule["lines"][0][2:][:80],
        "words": len(body.split()),
        "lines": len(rule["lines"]),
        "prohibitive_tokens": len(prohibitions),
        "bold_spans": len(BOLD_RE.findall(body)),
        "names_baseline_failure": named_failure,
        "unanchored_prohibition": bool(prohibitions) and not named_failure,
    }


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument(
        "path",
        nargs="?",
        default=str(Path(__file__).resolve().parent.parent / "SKILL.md"),
        help="entrypoint to measure (default: this package's own SKILL.md)",
    )
    ap.add_argument("--json", dest="json_path", help="write the full per-rule table here")
    args = ap.parse_args()

    text = Path(args.path).read_text(encoding="utf-8")
    records = [measure(r) for r in parse_rules(text)]
    if not records:
        raise SystemExit("entrypoint_form_census_error: no rules parsed")

    words = [r["words"] for r in records]
    unanchored = [r for r in records if r["unanchored_prohibition"]]
    summary = {
        "path": args.path,
        "rules": len(records),
        "rule_words_median": int(statistics.median(words)),
        "rule_words_max": max(words),
        "rules_over_300_words": sum(1 for w in words if w > 300),
        "prohibitive_tokens": sum(r["prohibitive_tokens"] for r in records),
        "bold_spans": sum(r["bold_spans"] for r in records),
        "rules_naming_baseline_failure": sum(1 for r in records if r["names_baseline_failure"]),
        "unanchored_prohibition_rules": len(unanchored),
    }
    for key, value in summary.items():
        print(f"{key}={value}")
    print("entrypoint_form_census_ok")

    if args.json_path:
        Path(args.json_path).write_text(
            json.dumps({"summary": summary, "rules": records}, ensure_ascii=False, indent=2) + "\n",
            encoding="utf-8",
        )
    return 0


if __name__ == "__main__":
    sys.exit(main())
