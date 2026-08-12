# Replay Validation Runbook

Use replay when validating whether a reusable extraction rule really works on a task shape similar to the one that produced it.

## When to Use

- A retrospective, bug hunt, or review follow-up produced a reusable workflow rule.
- The rule is meant to generalize beyond one incident or one repository.
- The new rule needs a pressure test before being treated as durable guidance.

## Replay Goal

Drive the task shape through the workflow as explicit stages:

1. analysis
2. parse / decompose
3. fix
4. test / verification
5. challenge
6. replay

Replay succeeds only if the workflow also keeps the four outputs separate:

- project-level fix
- test / verification evidence
- challenge findings
- reusable workflow lesson

## Replay Inputs

- The original task shape or a close analog
- The proposed workflow rule
- The validation and challenge checks that close the extraction

## Acceptance Criteria

- The problem is decomposed before extraction, not folded into analysis.
- The test/verification evidence is distinct from the fix.
- The challenge result is distinct from the validation result.
- The reusable lesson is general enough to survive a second task with the same shape.

## Failure Modes

- Treating replay as a prose-only example instead of an actual validation step.
- Reusing a one-off evidence bundle as durable skill content.
- Collapsing parse/decompose back into analysis.
- Declaring the lesson landed before replay confirms the workflow still produces the expected outputs.
