# Validation and review dispositions

Behavior candidate: `9611d67`; base: `404c29b2d42bda7a427676da5ba96b782c7d2f85`.
The remote main and source branch were checked before the final review passes.
Subsequent changes in this directory record evidence and status only.

## Deterministic acceptance

| Check | Result |
| --- | --- |
| Native Stop tests, `python3 -m unittest discover -s hooks -p test_proposed_next.py` | 32 passed. Five clause cases, four reminder cases and two no-work-evidence cases first reproduced the respective defects. |
| `bash skills/skill-extraction-workflow/scripts/test_body_compliance_grading.sh` | 57 grading cases plus CLI/stub checks passed. Unsafe continuing, contradictory outcomes and a sign-off marker without blocked fail the high-impact oracle. |
| `bash skills/skill-extraction-workflow/scripts/test_locale_independent_gates.sh` | Passed with current Bash and system Bash 3.2. Actual Make declarations run inert Ruby recipes; removing override or export fails the runtime assertion and static tracker. |
| `/usr/bin/make -n help` | GNU Make 3.81 parses the split export and target-specific override. The original combined declaration failed before any target ran. |
| Embedded process-liveness controls | A real live PID stays live with procfs unavailable; mocked missing PID and Linux zombie count as exited. The original helper failed the live-PID control on Darwin. |
| `make test CCL_SKILL_DEFAULT_BASE_REF=origin/main` | Exit 2 after repository gates passed and 43/44 fast suites passed. The inherited Make command-line override changed the default inspected by test_ci_checkout_ref_binding.sh. Its standalone rerun without that override passed; this is not recorded as a green aggregate invocation. |
| `make test-code-review` and remaining component runs | Shard 1 passed 8/9 suites in the sandbox. The process-state helper failed because macOS denies executing system ps there; its verified fixture-only host rerun passed all 11 assertions. Shard 2 passed all eight suites, including test_review_gate.sh and CLI wrapper regressions. `make test-code-review-abort-leak` passed on the host: leg 1 and both leg-2 clients. All required components have passing results; the earlier aggregate invocations remain recorded as failed. |
| Heavy regression lane | Eight suites passed initially. R0 status passed after entrypoint and owner-attribution corrections. The impact-chain verdict differential passed in the writable temporary clone: 64 integration points, 10 expected divergences, two replay cases. All ten suites therefore have passing results; the original aggregate exit was nonzero. |
| `python3 scripts/check-public-sanitization.py .` | Passed after the final review receipts were added. |
| Named private alias audit | Passed across the complete base-to-HEAD range and worktree using the process-retro profile and 12 private alias files. Public fallback tokens alone were not counted as private R0. |

Tests use synthetic data and an empty test HOME. Most run in a secret-free,
network-denied sandbox; macOS process-state probes need the system ps, which
cannot execute there. Those scripts were checked for fixture ownership and
temporary-path signal guards before host execution. The complete lane uses an
independent temporary clone with a named branch. Earlier
attempts exposed missing local test dependencies/HOME, denied writes for a test
that creates a temporary directory in its checkout, and a detached-HEAD shared
surface check. Static checks also caught entrypoint growth, missing ledger owner
keys and a removed registered pointer; each was corrected before its passing
rerun. Failed attempts are not green evidence. Local evidence does not replace
current-SHA CI.

## Independent review

The extraction-owned wrapper ran separate release-stage review and challenge
passes over the complete candidate, with the shared-gate risk tag and an
independent model family. `review.json` reports `passed`; `challenge.json`
retains its three P2 findings. Both are unchanged schema-3 controller outputs.

| Finding | Disposition and evidence |
| --- | --- |
| Make declaration and plan disagree | Fixed: separate export/override in the Makefile, regression and plan. |
| Empty Bash array under nounset fails on Bash 3.2 | Fixed and reproduced with system Bash; both Bash versions pass. |
| Status-only marker plus announced step bypasses work evidence | Fixed; two new no-evidence controls reproduced the false recheck. |
| Preparation-only scope was implicit | Explicit wording restored; paired preparation-only oracle added. |
| Missing-PID test depends on PID reuse timing | Fixed with ProcessLookupError injection; real live-PID and zombie controls retained. |
| Sign-off exemption could override explicit stricter rules | Fixed in entry and canonical reference; an explicit-signoff probe complements ordinary/additive and high-impact controls. |
| Chinese authority-blocker prose gets an announcement reminder | Source-refuted: the path returns the normal DECISION_RECHECK, one of the finding's accepted outcomes. Its reason explicitly names missing authority as a real blocker, preserves dependent-step blocking and grants no authority. |
| Replica concurrency should have a new maximum | Not adopted: replicas is an explicit caller-selected sample count, default one. Rate-limit failures remain ERROR. The advisory runner claims no automatic spending enforcement; a new CLI maximum is outside this repair. |
| Small tests need a new automatic cost threshold | Source-refuted as a scope bypass: every continuation clause requires the authorized task scope. An open-ended or large run does not become an in-scope small test by relabeling it. Explicit cost/count limits remain binding. This change adds no automatic spend-classification claim. |
| Compatibility exemption relies only on self-review | Source-refuted: the same canonical paragraph requires recorded deep self-review and external independent review; the design gate separately binds that review to the implementation diff. A reviewed interface diff plus compatibility decision remains required for external contract changes. |
| Full validation was still pending at review time | Closed after terminal results and targeted environment remediation were recorded above. Repository gates, all 44 fast suites, both review shards, all abort probes and all ten heavy suites have passing results before the shared branch update. |

## Advisory behavior samples

Three replicas across five ordinary-test/limit/high-impact probes yielded
10/15 and 8/15 strict marker passes in two model samples. Two replies in the
first sample exposed omitted implementation/acceptance prerequisites in the
small-test fixture; those preconditions are now explicit. In the second sample,
all prose chose the intended execution boundary, but seven replies missed the
strict output-marker contract. Preparation-only and explicit-signoff additions
have deterministic oracle coverage; they were not rerun against a live model.
These samples do not establish universal model compliance or actual environment
execution.

## Completion boundary

No merge, package publication or deployed-host update is included. The plan,
review receipts and this validation record describe a pull-request candidate.
The repository has structural/spec checks but no plan-activation validator;
the acceptance evidence above is the available executable proof.
