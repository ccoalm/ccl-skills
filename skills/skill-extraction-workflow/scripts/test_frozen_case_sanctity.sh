#!/usr/bin/env bash
# Frozen-case sanctity gate (regressions-are-sacred, deterministic half).
#
# SCOPE — read this before citing the lane as evidence. A frozen eval case
# (routing task-bank row, golden trace) is a pinned judgment: deleting it or
# rewriting its judgment fields makes a red disappear without anyone ruling on
# it. This lane makes that trade VISIBLE: any base-relative deletion or
# judgment-field change of a frozen case must be named by an ADDED
# source-register line carrying `case-retired: <id>` or `case-rescoped: <id>`.
# It does NOT judge whether the retirement/rescope is justified — that ruling
# belongs to the round's independent review (the register row is what puts it
# in front of the reviewer). Like the impact-chain gate, it trusts the author
# to write the declaration; it defends against SILENT trades, not forged ones.
# Without CCL_SKILL_BASE_REF (or an unresolvable base) it degrades to an
# explicit skip token — a skipped run is not a passed run.
set -u

ROOT="${SANCTITY_ROOT:-$(cd "$(dirname "$0")/../../.." && pwd)}"
[ -n "${SANCTITY_ROOT:-}" ] && echo "NOTICE: SANCTITY_ROOT set — testing tree: $ROOT" >&2
REGISTER="skills/skill-extraction-workflow/references/source-register.md"
BANK="eval/routing-tasks.jsonl"
TRACES_DIR="eval/golden-traces"

BASE="${CCL_SKILL_BASE_REF:-}"
if [ -z "$BASE" ]; then
  echo "frozen_case_sanctity_skipped no-base-ref (set CCL_SKILL_BASE_REF to enable; skipped is not passed)"
  exit 0
fi
if ! git -C "$ROOT" rev-parse --verify --quiet "${BASE}^{commit}" >/dev/null; then
  echo "frozen_case_sanctity_skipped base-unresolvable ($BASE; skipped is not passed)"
  exit 0
fi

TMPDIR_SANCTITY="$(mktemp -d)"
trap 'rm -rf "$TMPDIR_SANCTITY"' EXIT

# Base snapshots; a path absent at base means every current case is new (no
# violation possible on that surface).
git -C "$ROOT" show "$BASE:$BANK" > "$TMPDIR_SANCTITY/base-bank.jsonl" 2>/dev/null || : > "$TMPDIR_SANCTITY/base-bank.jsonl"
git -C "$ROOT" show "$BASE:$REGISTER" > "$TMPDIR_SANCTITY/base-register.md" 2>/dev/null || : > "$TMPDIR_SANCTITY/base-register.md"
mkdir -p "$TMPDIR_SANCTITY/base-traces"
# -r: enumerate blobs recursively so a trace in a subdirectory is still guarded
# (the head-side walk below recurses symmetrically).
n=0
git -C "$ROOT" ls-tree -r --name-only "$BASE" -- "$TRACES_DIR/" 2>/dev/null | while IFS= read -r tp; do
  case "$tp" in
    *.json)
      n=$((n+1))
      git -C "$ROOT" show "$BASE:$tp" > "$TMPDIR_SANCTITY/base-traces/trace-$n-$(basename "$tp")" 2>/dev/null || true ;;
  esac
done

python3 - "$ROOT" "$TMPDIR_SANCTITY" "$REGISTER" "$BANK" "$TRACES_DIR" <<'PY'
import json, os, sys

root, tmp, register_rel, bank_rel, traces_rel = sys.argv[1:6]
fail = 0

def bad(msg):
    global fail
    print(f"FAIL: {msg}", file=sys.stderr)
    fail = 1

def load_bank(path):
    rows = {}
    if not os.path.exists(path):
        return rows
    with open(path, encoding="utf-8") as fh:
        for raw in fh:
            raw = raw.strip()
            if not raw:
                continue
            try:
                row = json.loads(raw)
            except json.JSONDecodeError:
                continue  # malformed rows are the integrity lane's finding, not ours
            rid = row.get("id")
            if rid:
                rows[rid] = row
    return rows

def judgment(row):
    # The judgment surface of a bank case: what outcome passes or fails it.
    # Provenance/commentary fields (source, why_expected, frozen_at_sha) may
    # change without re-scoping the case.
    return (
        row.get("expected_skill"),
        sorted(row.get("acceptable") or []) if isinstance(row.get("acceptable"), list) else row.get("acceptable"),
        sorted(row.get("must_not_route_to") or []) if isinstance(row.get("must_not_route_to"), list) else row.get("must_not_route_to"),
    )

base_bank = load_bank(os.path.join(tmp, "base-bank.jsonl"))
head_bank = load_bank(os.path.join(root, bank_rel))

violations = []  # (kind, id)
for rid, row in base_bank.items():
    if rid not in head_bank:
        violations.append(("deleted bank case", rid))
    elif judgment(row) != judgment(head_bank[rid]):
        violations.append(("re-scoped bank case (judgment fields changed)", rid))

def load_trace(path):
    try:
        with open(path, encoding="utf-8") as fh:
            return json.load(fh)
    except (OSError, json.JSONDecodeError):
        return None

base_traces = {}
base_dir = os.path.join(tmp, "base-traces")
for name in sorted(os.listdir(base_dir)):
    data = load_trace(os.path.join(base_dir, name))
    if isinstance(data, dict) and data.get("id"):
        base_traces[data["id"]] = data

head_traces = {}
head_dir = os.path.join(root, traces_rel)
if os.path.isdir(head_dir):
    for dirpath, _dirnames, filenames in os.walk(head_dir):
        for name in sorted(filenames):
            if not name.endswith(".json"):
                continue
            data = load_trace(os.path.join(dirpath, name))
            if isinstance(data, dict) and data.get("id"):
                head_traces[data["id"]] = data

for tid, data in base_traces.items():
    if tid not in head_traces:
        violations.append(("deleted golden trace", tid))
    elif data.get("assert") != head_traces[tid].get("assert"):
        violations.append(("re-scoped golden trace (assert block changed)", tid))

# Added register lines = head lines not present at base (the register is
# append-only, so a set diff is the added-row surface). Only added Markdown
# TABLE ROWS may carry adjudication credit — an adjudication is a register row
# a reviewer rules on, so an HTML comment or loose prose that merely mentions
# the token mints nothing.
with open(os.path.join(tmp, "base-register.md"), encoding="utf-8") as fh:
    base_lines = set(fh.read().splitlines())
register_path = os.path.join(root, register_rel)
added_rows = []
if os.path.exists(register_path):
    with open(register_path, encoding="utf-8") as fh:
        added_rows = [
            ln for ln in fh.read().splitlines()
            if ln not in base_lines and ln.lstrip().startswith("|")
        ]
added_blob = "\n".join(added_rows)

import re
def adjudicated(case_id):
    # Token-bounded: `case-retired: foo` must not be credited by
    # `case-retired: foobar` (ids use [A-Za-z0-9_-]).
    pattern = re.compile(
        r"case-(?:retired|rescoped):\s*" + re.escape(case_id) + r"(?![A-Za-z0-9_-])"
    )
    return bool(pattern.search(added_blob))

for kind, cid in violations:
    if adjudicated(cid):
        continue
    bad(
        f"{kind} '{cid}' with no adjudication row — a frozen case may not be "
        f"silently traded away; add a source-register row this round containing "
        f"`case-retired: {cid}` or `case-rescoped: {cid}` (with the why), so the "
        f"independent review rules on it"
    )

if fail:
    sys.exit(1)
print(f"frozen_case_sanctity_ok bank_base={len(base_bank)} traces_base={len(base_traces)} violations=0")
PY
status=$?
if [ $status -ne 0 ]; then
  echo "frozen_case_sanctity_failed" >&2
  exit 1
fi
exit 0
