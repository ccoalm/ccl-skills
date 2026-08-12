# Protobuf HTTP Contract Signals

Use this when deciding whether an HTTP surface is routine JSON/OpenAPI or protobuf-backed HTTP.

## Authoritative Record

The wire-format decision must be owner-authored or owner-approved and locatable in at least one of:

- shared IDL / IDLGen contract metadata
- generated client or server package metadata
- backend architecture document
- backend repo contract
- MR description that records the architecture decision and carries an owner sign-off or approval reference distinct from the change author's own assertion

API docs can support the decision, but do not replace the authoritative record when protobuf may be in scope. Verbal owner guidance counts only after it is captured in a quotable, locatable record. Agent-authored notes can cite owner records, but cannot substitute for owner confirmation.

Owner approval must be checkable from an artifact outside the diff under review. Acceptable signals include an explicit owner sign-off line in an external approval system, approval reference, contract-owner field from an existing contract-owner registry, IDL/IDLGen owner metadata from a prior commit or published artifact, generated package provenance, or a linked approval record. Author-written MR text alone is unconfirmed; in-diff sign-off text never proves ownership or approval.

Classify owner approval with this decision list:

- Existing surface with pre-existing owner record, and implementation author matches that recorded owner: `owner-confirmed`; self-authored MR prose is not the evidence, the pre-existing owner record is.
- Existing surface with pre-existing owner record, and implementation author is not that owner: require a checkable approval from the recorded owner or owner delegate; missing approval is `pending-contract-owner`.
- Existing surface with owner metadata or generated provenance added or regenerated only by the same diff: `pending-contract-owner`; same-diff metadata cannot establish ownership.
- Genuinely new surface: the same diff may introduce the first contract-owner record only when it is paired with a checkable external approval reference or a verified gate record outside the diff. If the approver is distinct from the implementation author, record `owner-confirmed`; if the implementation author is the new recorded owner and no distinct approver exists, record `pending-external-approval-check` until a checkable external gate or human owner process proves owner self-approval is accepted for first introduction.
- If a required approval reference is missing: `pending-contract-owner`.
- If only the external identity or self-approval gate is inaccessible to the agent: `pending-external-approval-check`; this blocks the wire-format / owner-confirmation claim, not unrelated implementation work.
- Default: unresolved owner state is non-pass; do not report it as owner-confirmed.

`Unclear wire format` means no authoritative record is locatable for a surface that is in this wire-format gate.

A surface enters the gate when any of these are true:

- the new or modified surface has a protobuf signal, cross-language/shared-IDL requirement, binary transport, or protobuf-generated artifact boundary
- the diff changes contract source, protobuf or binary payload content-type/media type, protobuf response serialization, protobuf/binary marshaling config, wire format, protobuf-generated client, or protobuf-generated schema

A surface does not enter the gate when any of these are true:

- existing unchanged JSON/OpenAPI or protobuf-backed surfaces are only touched by unrelated work, and the diff shows no contract source, protobuf or binary payload content-type/media type, protobuf response serialization, protobuf/binary marshaling config, wire format, protobuf-generated client, or protobuf-generated schema change
- routine JSON/OpenAPI services, public API surfaces, backend integrations, request/response shape, endpoint, status/error, JSON serialization, or OpenAPI-generated client/schema changes have no protobuf signal, cross-language/shared-IDL requirement, binary transport, protobuf/binary content-type/media-type change, protobuf response serialization change, protobuf/binary marshaling config change, or protobuf-generated artifact change

A standing protobuf signal on an unchanged surface does not pull unrelated work into this gate.

Out-of-scope classification needs evidence. Cite the specific diff lines or unchanged generated artifacts that prove the changed slice did not alter any in-scope trigger above. If that proof is unavailable, classify as pending owner/wire-format evidence instead of out of scope.

## Protobuf Signal

Treat protobuf as in scope when any of these are present. This signal list is not a standalone approval trigger; apply the gate above to distinguish changed surfaces from unrelated work on unchanged surfaces.

- IDL / IDLGen metadata mentions the HTTP surface
- protobuf generated client, server, schema, or package is imported or published for the surface
- protobuf generation config or generation command covers the surface
- request or response uses a protobuf content type or documented binary SDK path
- existing client code serializes or parses protobuf-generated message types for the surface
- backend owner guidance captured in an architecture doc, repo contract, or MR description says the surface uses protobuf as contract source or wire format; MR-description guidance counts only when it carries the same checkable owner signal required by Authoritative Record

The signal list is intentionally shared across Go, Python, web, mini-program, and testing skills. Do not redefine it per stack.

## Decision Rules

- New services, public API surfaces, and backend integrations require a contract-definition record before implementation. They require positive contract-owner confirmation of wire format only when there is a protobuf signal, cross-language/shared-IDL requirement, binary transport, or protobuf-generated artifact boundary. Routine JSON/OpenAPI services, public surfaces, and endpoints may use the contract-definition record when none of those triggers exists. JSON-only choices that do need owner confirmation require a checkable owner signal; an agent-authored inline note is not enough.
- For modified HTTP surfaces, first prove whether the diff changes contract source, protobuf or binary payload content-type/media type, protobuf response serialization, protobuf/binary marshaling config, wire format, protobuf-generated client, or protobuf-generated schema. If yes, record the wire format before implementation; missing records route to the contract owner and block approval.
- Existing unchanged JSON/OpenAPI or protobuf-backed surfaces preserve current behavior for unrelated work when the diff proves no contract or wire-behavior change. Missing records in that case do not block the unrelated change, but the work must not claim backend contract conformance.
- If the client stack cannot reach the backend record or owner, an assumed-wire-format note never unblocks a wire-format change. Any change touching contract source, protobuf or binary payload content-type/media type, protobuf response serialization, protobuf/binary marshaling config, wire format, protobuf-generated client, or protobuf-generated schema stays blocked until the contract owner confirms the wire format.
- Never change an existing wire format because documentation is missing. Preserve current client behavior, add the missing record, then require an explicit consumer-migration decision before changing the format.
