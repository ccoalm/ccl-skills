# Prevention Routing

Use this when deciding what should change after a defect.

## Prevention Types

- Contract prevention: schema, protobuf, API validation, enum default, required field, compatibility test.
- Data prevention: DB constraint, transaction boundary, migration check, unique key, retention policy.
- Runtime prevention: timeout, rate limit, circuit breaker, lock lease, idempotency record, alert.
- Test prevention: regression test, boundary case, contract test, integration test, replay check, generated-file drift check.
- Review prevention: checklist item for security, data integrity, permission, concurrency, migration, or release.
- Tooling prevention: deterministic generator, non-interactive command, safer default, file overwrite guard.
- Skill prevention: concise rule in the smallest relevant skill/reference.

## Skill Update Decision

Add or update a skill only when all are true:

- the lesson is product-agnostic.
- it would change future behavior.
- it can be stated as a short rule, checklist item, or workflow step.
- it belongs to a clear owner skill.

Discard or keep local when:

- it depends on one business domain or one legacy repository.
- it is already covered by an existing rule.
- it is a temporary workaround rather than a durable pattern.
- it would make a skill longer without improving future execution.

## Examples

- Missed protobuf or OpenAPI/Pydantic compatibility break -> architecture contract rule plus dev contract test rule.
- Deleted failing test to pass CI -> defect-diagnosis rule plus development test-quality reference.
- Repeated unclear acceptance criteria -> product-rd-workflow shaping checklist.
- Missing Redis lock value comparison -> stack-specific Redis implementation reference, not product workflow.
