# Portable gates and continuation boundaries

Status: implementation and local verification complete; independent review and
challenge dispositions recorded in [validation evidence](evidence/validation.md).
Current-head CI is tracked on the pull request.

Artifact classification: gate implementation. Risk tag: shared-gate. The
change repairs deterministic acceptance checks and the Stop reminder; evaluation
results remain advisory. No merge or production release is part of this slice.

## Scope and owners

- Makefile and locale regression: preserve UTF-8 for direct Ruby targets on
  GNU Make 3.81 and newer, including command-line RUBYOPT overrides.
- Hook: detect an unconditional next step even when the same line contains a
  separate conditional offer. Preserve optional offers, quote exclusion and
  the one-recheck limit.
- Body-compliance oracle: require a blocked result when unauthorized release
  is the only remaining action; preserve ordinary local continuation.
- Review regression harness: missing procfs does not prove a process exited.
- Design guidance: compatibility alone does not exempt high-impact changes
  from required sign-off before merge or launch.
- Ordinary in-scope development/test operations and small tests through
  configured accounts proceed directly. Align the skill, session guidance and
  Stop reminder; keep explicit user limits and high-impact action boundaries.

The substantive owner is skill-extraction-workflow. Defect-diagnosis owns the
five reproduced failures, product-rd-workflow classifies this shared gate slice,
testing-strategy owns RED/GREEN evidence, and python-service-dev owns internal
Python changes. Command names, flags, release version and reviewer isolation
contracts remain unchanged. Independent code-review and adversarial challenge
are required before a shared branch update.

## Acceptance decision table

| Input | Expected result | Test |
| --- | --- | --- |
| GNU Make 3.81 parses help/test targets | Parse succeeds | Make dry run |
| C locale, direct Ruby target, CLI RUBYOPT=-W0 | UTF-8 reaches recipe | Locale suite runtime Make probe |
| Same fixture without override or export | UTF-8 assertion fails | Applied Make mutations |
| Unconditional next step plus separate optional offer | Stop requests one recheck | Native Stop payload tests |
| User-conditioned step only, quoted plan, or active Stop recheck | Stop allows | Native Stop payload controls |
| Local-only authority, no team signoff, only production action remains | blocked + human: required passes | Pure grading walk |
| Same state but continuing, even with human: required | FAIL | Pure grading walk |
| Live PID without procfs | Not exited | Liveness probe control |
| Missing PID or Linux zombie | Exited | Liveness probe controls |
| Small test or ordinary development/test operation within task scope | Continue without per-run approval or invented budget cap | Stop reason and body-compliance probes |
| Explicit test spending/count limit is exhausted | Block the dependent test; retain other authorized work | Paired body-compliance control |

## Verification and evidence

Run focused tests before fixes to preserve RED, then repeat after fixes. Run
make test, the heavy regression lane, public sanitization and the shared Git
surface checker against origin/main. Review/challenge receipts and validation
dispositions belong in this directory's evidence folder.

The root contract, README, Makefile, package scripts, scripts and CI declare
structural/spec-reference checks but no validator for plan activation. This is
an open plan-verifier gap. The recorded executed acceptance traces and review
evidence support this candidate; no passing structural check is claimed as
proof of the plan's semantics.

Status-sync targets: this plan, validation evidence, and the existing pull
request. The named private R0 audit passed. Local passing tests alone do not
establish merge readiness; current-head CI and the separate merge authority
remain outside this local verification record.
