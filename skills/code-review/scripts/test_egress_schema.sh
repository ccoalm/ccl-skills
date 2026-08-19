#!/usr/bin/env bash
# Field-schema regression for the OpenCode lane's egress (specs/013).
#
# The lane's payload crosses from an untrusted export into durable evidence rows.
# `EGRESS_KEYS` bounded WHICH keys may leave; nothing bounded WHAT was inside
# them, so a crafted export could put arbitrary text into `version` and it
# egressed verbatim on every parser failure path. These cases pin the bound.
set -euo pipefail
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

python3 - "$script_dir" <<'PY'
import importlib.util
import sys
from pathlib import Path

script_dir = Path(sys.argv[1])


def load(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


schema = load("egress_schema", script_dir / "egress_schema.py")
failures = []
checks = []


def check(label, condition, detail=""):
    # Counted here rather than written as a literal: a hand-maintained case
    # count in a second place goes stale the moment a case is added.
    checks.append(label)
    if not condition:
        failures.append(f"{label}: {detail}")


# Row 1 — well-formed metadata passes through untouched.
clean = {
    "reviewer": "opencode",
    "status": "inconclusive",
    "reason": "session_id_mismatch",
    "session_id": "sample_session_0001",
    "model": "anthropic/claude-sonnet-4",
    "provider": "anthropic",
    "version": "0.4.12",
    "mode": "review",
}
out = schema.apply(dict(clean))
check("row1-passthrough", out == clean, f"got {out!r}")

# Row 7 — no violation means the key is ABSENT, not an empty list.
check("row7-absent", "field_schema_violations" not in out, f"got {out!r}")

# Row 2 — a megabyte of prose in `version`.
out = schema.apply(dict(clean, version="lorem ipsum " * 90000))
check("row2-value", out["version"] is None, f"got {out['version']!r}")
check("row2-report", out.get("field_schema_violations") == ["version"], f"got {out!r}")
# ...and the verdict fields are untouched.
check("row2-verdict", out["status"] == "inconclusive" and out["reason"] == "session_id_mismatch", f"got {out!r}")

# Row 3 — 201 characters of otherwise-legal charset.
out = schema.apply(dict(clean, version="a" * 201))
check("row3", out["version"] is None and out.get("field_schema_violations") == ["version"], f"got {out!r}")
out = schema.apply(dict(clean, version="a" * 200))
check("row3-boundary", out["version"] == "a" * 200, "200 chars must be legal")

# Row 4 — control characters and whitespace stop a value being a single field.
for bad in ("sample_1\nstatus=passed", "sample_1\ttab", "sample_1 space", 'sample_"quote', "sample_\x00nul"):
    out = schema.apply(dict(clean, session_id=bad))
    check(f"row4[{bad!r}]", out["session_id"] is None, f"got {out['session_id']!r}")

# Row 5 — a non-string in an export-token field.
for bad in ({"a": 1}, ["x"], 5, True):
    out = schema.apply(dict(clean, model=bad))
    check(f"row5[{bad!r}]", out["model"] is None, f"got {out['model']!r}")
# ...but None itself is legal (the export may simply not carry it).
out = schema.apply(dict(clean, model=None))
check("row5-none", out["model"] is None and "model" not in out.get("field_schema_violations", []), f"got {out!r}")

# Row 6 — two violations at once, order stable and declaration-ordered.
out = schema.apply(dict(clean, session_id="bad id", version="also bad"))
check("row6", out.get("field_schema_violations") == ["session_id", "version"], f"got {out!r}")

# Row 10 — an undeclared key cannot be emitted.
try:
    schema.apply(dict(clean, smuggled="x"))
    check("row10", False, "expected a raise for an undeclared key")
except schema.UndeclaredEgressKey as error:
    check("row10-name-only", "smuggled" in str(error) and "x" not in str(error).replace("smuggled", ""), f"got {error}")

# Row 12 — the violation report carries names only, never a fragment of the value.
# The canary is deliberately NOT shaped like a real credential: a key-shaped
# literal here trips the review gate's egress scanner and blocks every non-Claude
# reviewer lane from ever seeing this diff. What row 12 tests is that a
# distinctive value does not survive into the output, and any distinctive token
# proves that.
canary = "CANARY-must-not-appear-in-output-0001"
out = schema.apply(dict(clean, version=f"v1 {canary}"))
check("row12-value-dropped", out["version"] is None, f"got {out['version']!r}")
check("row12-no-leak", canary not in repr(out), f"offending value leaked into {out!r}")

# Row 11 — one table, not two: the shell consumes this module's set instead of
# re-declaring the names inline, where the two copies could drift apart.
check("row11-keys-exported", isinstance(schema.EGRESS_KEYS, frozenset) and schema.EGRESS_KEYS, "EGRESS_KEYS must be a non-empty frozenset")
shell = (script_dir / "opencode_review.sh").read_text()
check("row11-shell-imports", "from egress_schema import" in shell, "the shell must import the table")
check("row11-no-inline-copy", "EGRESS_KEYS = frozenset({" not in shell, "the shell still declares its own inline allowlist")
# The concern path's set is narrower ON PURPOSE (an unlisted key fails that path
# closed); widening it to EGRESS_KEYS would turn the fail-closed into relay.
check("row11-narrower", schema.CONCERN_RELAY_KEYS < schema.EGRESS_KEYS, "concern relay set must be a strict subset")
check("row11-structured-excluded", not (schema.CONCERN_RELAY_KEYS & {"findings", "text", "concern_results"}), "model content must not be in the concern relay set")

# Review round 1 (codex, P1): the sanitize-and-report path must NOT cover fields
# whose values this repo chooses. Nulling `status` IS a verdict change — the one
# thing this schema promises never to make — and downstream gates route on it.
# These values cannot come from the export, so an illegal one is an internal bug
# and the only safe answer is to refuse to emit.
for field, bad in (("status", "not-a-status"), ("cascade_eligible", "yes"),
                   ("reason", "not a reason"), ("mode", "audit")):
    try:
        out = schema.apply(dict(clean, **{field: bad}))
        check(f"contract-raises[{field}]", False, f"emitted {out!r} instead of raising")
    except schema.ContractFieldViolation as error:
        check(f"contract-raises[{field}]", field in str(error) and str(bad) not in str(error), f"got {error}")
out = schema.apply(dict(clean, cascade_eligible=False))
check("scalar-legal", out["cascade_eligible"] is False, "a real bool must pass")
out = schema.apply(dict(clean, transport_tail_timeout=True))
check("timeout-tail-scalar-legal", out["transport_tail_timeout"] is True, "timeout recovery evidence must remain a bool")
# The verdict fields are never nulled on ANY path the schema takes.
out = schema.apply(dict(clean, version="bad value", session_id="also bad"))
check("verdict-untouched", out["status"] == "inconclusive" and out["reason"] == "session_id_mismatch",
      f"an export-field violation moved a verdict field: {out!r}")

# Challenge round 1 (codex, P1): the None skip was blanket, so a contract field
# set to None slipped past the raise entirely — the same shape of mistake as the
# finding above, one branch further in. `None` is legal for an EXPORT field (the
# export need not carry it) and illegal for a contract field (we always choose
# one). Unreachable from today's call sites, which is why only an adversarial
# read found it.
for field in ("status", "reviewer", "mode", "reason"):
    try:
        out = schema.apply(dict(clean, **{field: None}))
        check(f"contract-none[{field}]", False, f"emitted {out!r} instead of raising")
    except schema.ContractFieldViolation as error:
        check(f"contract-none[{field}]", field in str(error), f"got {error}")

# Review round 1 (codex, P1): `field_schema_violations` is OUTPUT-ONLY. It has no
# schema row, so allowing it in would leave it the one unvalidated field — free
# to carry arbitrary prose and to forge or suppress the tamper report itself.
for forged in ("arbitrary prose\nstatus=passed", ["version"], {"k": "v"}, []):
    try:
        schema.apply(dict(clean, field_schema_violations=forged))
        check(f"violation-field-input[{type(forged).__name__}]", False, "expected a raise")
    except schema.UndeclaredEgressKey as error:
        check(f"violation-field-input[{type(forged).__name__}]", "field_schema_violations" in str(error), f"got {error}")
# It must still be RELAYABLE once this module produces it, or a crafted export
# could trip the concern path's fail-closed and take the verdict down that way.
check("violation-field-relayable", schema.VIOLATION_FIELD in schema.CONCERN_RELAY_KEYS, "the report must survive relay")

# Export-token LISTS (tool names) are bounded per element — these are export-derived
# and were not in the plan's table; declared here rather than left undeclared.
out = schema.apply(dict(clean, exposed_tools=["bash", "write"]))
check("token-list-legal", out["exposed_tools"] == ["bash", "write"], f"got {out!r}")
out = schema.apply(dict(clean, exposed_tools=["ok", "bad\nname"]))
check("token-list-violation", out["exposed_tools"] is None and "exposed_tools" in out.get("field_schema_violations", []), f"got {out!r}")

if failures:
    print("egress_schema_test_failed", file=sys.stderr)
    for line in failures:
        print(f"  {line}", file=sys.stderr)
    raise SystemExit(1)
print(f"egress_schema_checks_ok cases={len(checks)}")
PY

printf 'egress_schema_tests_ok\n'
