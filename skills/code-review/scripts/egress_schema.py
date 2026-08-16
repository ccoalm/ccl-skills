#!/usr/bin/env python3
"""Field schema for the OpenCode reviewer lane's egress payload (specs/013).

The lane already bounded WHICH keys may leave (`EGRESS_KEYS` in
`opencode_review.sh`). Nothing bounded WHAT was inside them. `session_id`,
`model`, `provider`, and `version` are read straight out of the OpenCode
export — an untrusted artifact — and were relayed verbatim into durable
evidence rows on every parser path, so a crafted export could put a megabyte
of prose, a newline, or a fabricated `status=passed` line into a field the
reader treats as machine metadata.

Two properties hold here and are the reason to read this file before editing:

1. A violation NEVER changes the verdict. The value becomes `None` and the
   field NAME is appended to `field_schema_violations`; `status`, `reason`,
   and the cascade fields are decided elsewhere and are not touched. A schema
   that could downgrade a verdict would be a new way to suppress a review.
2. The violation report carries NAMES ONLY. Echoing the offending value would
   re-open the exact hole the bound closes — the report itself egresses.

Undeclared keys raise rather than pass through: this table and the shell's
allowlist are the same table (`EGRESS_KEYS` below), so a new field must be
classified here before it can leave.
"""

import re

# --- kinds ---------------------------------------------------------------
#
# CONTRACT fields are values this repo's own code chooses (the shell, the
# parser). EXPORT fields come from the reviewer's export and are hostile until
# proven otherwise. The kinds below differ in how tightly each can be bounded.

ENUM = "contract-enum"                # closed set, exhaustively known here
IDENTIFIER = "contract-identifier"    # our own vocabulary, shape-bounded
BOOLEAN = "contract-boolean"
EXIT_CODE = "contract-exit-code"
TOKEN = "export-token"                # untrusted scalar, charset + length
TOKEN_LIST = "export-token-list"      # untrusted list, per-element token
STRUCTURED = "structured"             # owner-validated elsewhere; not bounded here

# `reason` and `reason_code` are deliberately NOT enums. Their vocabulary is
# spread across five scripts, and an enum that fell out of sync would blank a
# legitimate diagnostic — trading an integrity bug for an availability one.
# They are ours, not the export's, so a shape bound is the honest bound.
IDENTIFIER_RE = re.compile(r"[A-Za-z0-9][A-Za-z0-9._-]{0,63}\Z")

# Export-token grammar (specs/013): no whitespace, no control characters, no
# quotes — a value that cannot stop being a single field in any reader.
TOKEN_RE = re.compile(r"[A-Za-z0-9._:/@+-]{1,200}\Z")
TOKEN_LIST_MAX = 64

# --- the table -----------------------------------------------------------
#
# Declaration order is the order violations are reported in.

SCHEMA = {
    "reviewer": (ENUM, frozenset({"opencode"})),
    "status": (ENUM, frozenset({"passed", "findings", "inconclusive"})),
    "mode": (ENUM, frozenset({"review", "challenge"})),
    "reason": (IDENTIFIER, None),
    "reason_code": (IDENTIFIER, None),
    "reviewer_family": (IDENTIFIER, None),
    "runtime_isolation": (IDENTIFIER, None),
    "credential_binding": (IDENTIFIER, None),
    "cascade_eligible": (BOOLEAN, None),
    "candidate_ineligible": (BOOLEAN, None),
    "concern_evidence": (BOOLEAN, None),
    "transport_tail_timeout": (BOOLEAN, None),
    "transport_exit_code": (EXIT_CODE, None),
    "session_id": (TOKEN, None),
    "model": (TOKEN, None),
    "provider": (TOKEN, None),
    "version": (TOKEN, None),
    # Export-derived tool-name lists. The plan's table did not enumerate these;
    # they are emitted by the isolation checks in `parse_opencode_review.py` and
    # carry names lifted from the export, so they are bounded per element.
    "exposed_tools": (TOKEN_LIST, None),
    "missing_tools": (TOKEN_LIST, None),
    "missing_disabled_tools": (TOKEN_LIST, None),
    # Validated by their own owners before they get here; bounding their prose
    # is a different job than bounding a metadata scalar.
    "concern_results": (STRUCTURED, None),
    "findings": (STRUCTURED, None),
    "severities": (STRUCTURED, None),
    "locators": (STRUCTURED, None),
    "text": (STRUCTURED, None),
}

VIOLATION_FIELD = "field_schema_violations"

# Kinds whose values this repo's own code chooses. An invalid one cannot come
# from the export — every `reason` and `reason_code` is a literal in our
# scripts, and `reviewer_family` is a lookup RESULT, not export text — so an
# invalid value here is an internal bug, and the only safe response is to refuse
# to emit rather than to null the field. Nulling `status` would itself be the
# verdict change this schema promises never to make.
CONTRACT_KINDS = frozenset({ENUM, IDENTIFIER, BOOLEAN, EXIT_CODE})

# The shell consumes this instead of keeping a second inline allowlist. The
# violation report is included because it must survive relay: making a crafted
# export able to trip the concern path's fail-closed would hand it a verdict
# change through the back door.
EGRESS_KEYS = frozenset(SCHEMA) | {VIOLATION_FIELD}

# The concern-audit enrichment path in `opencode_review.sh` relays a DELIBERATELY
# NARROWER set: anything outside it fails that path closed to
# `concern_audit_failed` so a human classifies the new field rather than having it
# silently relayed. Widening this to `EGRESS_KEYS` would turn that fail-closed
# into a pass-through, so the two sets stay distinct — "one table" means one file
# to edit, not one set. The assertion below is what keeps them from drifting.
CONCERN_RELAY_KEYS = frozenset({
    "reviewer", "status", "reason", "reason_code", "cascade_eligible",
    "candidate_ineligible", "transport_tail_timeout", "session_id", "model", "provider", "version",
    "mode", "reviewer_family", "runtime_isolation", "credential_binding",
    VIOLATION_FIELD,
})
assert CONCERN_RELAY_KEYS <= EGRESS_KEYS, "concern relay set escaped the schema"


class UndeclaredEgressKey(Exception):
    """A key reached egress without a row in SCHEMA. Classify it there first."""


class ContractFieldViolation(Exception):
    """A field this repo's own code owns held a value it cannot legally hold.

    Raised rather than sanitized: these values never come from the export, so
    this is an internal bug, and emitting a nulled `status` would corrupt the
    verdict that downstream gates route on.
    """


def _token_ok(value):
    return isinstance(value, str) and bool(TOKEN_RE.fullmatch(value))


def _value_ok(kind, allowed, value):
    if kind is ENUM:
        return value in allowed
    if kind is IDENTIFIER:
        return isinstance(value, str) and bool(IDENTIFIER_RE.fullmatch(value))
    if kind is BOOLEAN:
        # `isinstance(True, int)` is why this is an identity check.
        return value is True or value is False
    if kind is EXIT_CODE:
        if value is True or value is False:
            return False
        if isinstance(value, int):
            return -256 <= value <= 256
        return isinstance(value, str) and value.isdigit() and len(value) <= 3
    if kind is TOKEN:
        return _token_ok(value)
    if kind is TOKEN_LIST:
        return (
            isinstance(value, list)
            and len(value) <= TOKEN_LIST_MAX
            and all(_token_ok(item) for item in value)
        )
    if kind is STRUCTURED:
        return True
    raise AssertionError(f"unhandled kind: {kind!r}")


def apply(payload):
    """Return `payload` with out-of-schema values dropped to `None`.

    Violating field names are appended to `field_schema_violations` in table
    order. The key is absent when there are none — an empty list would read as
    "the schema ran and found nothing" in exactly the rows where it did not run
    at all.

    Raises `UndeclaredEgressKey` for any key not in `SCHEMA` — including
    `field_schema_violations` itself, which is OUTPUT-ONLY: accepting a
    caller-supplied one would let a crafted payload forge or suppress the very
    report that records it was tampered with. Raises `ContractFieldViolation`
    when a field this repo owns holds an illegal value.
    """
    # Checked against SCHEMA, not EGRESS_KEYS: the latter carries the
    # output-only violation field, which has no row and so would never be
    # validated if it were allowed in.
    undeclared = sorted(set(payload) - frozenset(SCHEMA))
    if undeclared:
        # Names only: the value is what we are refusing to relay.
        raise UndeclaredEgressKey(f"undeclared egress key(s): {', '.join(undeclared)}")

    violations = []
    for field, (kind, allowed) in SCHEMA.items():
        if field not in payload:
            continue
        value = payload[field]
        if value is None:
            # For an EXPORT field a missing value is not a malformed one — the
            # export may simply not carry it, and blanking an already-blank
            # field is not a finding. A contract field is different: this repo
            # always chooses one, so `None` means the verdict lost a value it is
            # required to carry, and letting it through unchecked would be the
            # same blanket-rule mistake this split exists to avoid.
            # (Challenge round 1 found this skip applied to both.)
            if kind in CONTRACT_KINDS:
                raise ContractFieldViolation(f"contract field is None: {field}")
            continue
        if _value_ok(kind, allowed, value):
            continue
        if kind in CONTRACT_KINDS:
            # Name only, again — even an internal bug's value must not egress
            # through an exception message a caller may log.
            raise ContractFieldViolation(f"illegal value in contract field: {field}")
        payload[field] = None
        violations.append(field)

    if violations:
        payload[VIOLATION_FIELD] = violations
    return payload
