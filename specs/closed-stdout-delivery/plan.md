# Report delivery only to the caller's stdout

> **Withdrawn.** The cause below (fd 1 reused by an open inside the wrapper)
> was never observed; a later comparison on the failing image showed that the
> test's `env` reopened the closed stdout on `/dev/null` instead. The wrapper
> change was reverted. See `specs/closed-stdout-test-launch/plan.md`.

`code-review-regressions-1` fails intermittently on the `ubuntu-26.04` runner
image (`ubuntu-latest` moved from 24.04): "closed stdout cannot strand an
unreported diagnostic child" in `test_opencode_review_retry.sh`. Main's own
code fails the same way, so every pull request is blocked by it.

## Charter

| Field | Decision |
| --- | --- |
| Purpose | The OpenCode review wrapper must treat its result as delivered only when it reached the caller's stdout, so an undelivered timeout diagnostic is removed and no result is written into an unrelated file. |
| Scope | `skills/code-review/scripts/opencode_review.sh` final delivery check and its suite. Pinning the runner image and other wrappers' delivery paths are out of scope; the latter are checked as siblings below. No iterative-program watermark applies. |
| Depth | Generator/tooling change. |
| Result classification | Failure/correction: required CI lane red on the current runner image, reproduced on a control branch with main's code. |
| Matching analysis | Diagnosis below; prevention is a delivery check that does not depend on the write's return code. |
| Failure boundary | A wrapper started with an open stdout keeps today's behaviour, including signal handling after a successful write. The fix must not hide a closed stdout as success. |
| Lifecycle impact | Implementation (wrapper), testing (suite), CI health. No product, UI, release-process or onboarding change. |
| Evidence plan | CI logs of the failing job on PRs #195, #196 (main control) and the diagnostic runs on #197; the wrapper's exit path; the suite's existing signal and closed-stdout cases. Produced artifacts: the diagnostic runs' logs, read above. |
| Completion standard | A deterministic regression test RED before the fix and GREEN after, the existing suite green, `make test`, review and challenge, the required lane green on the pull request. |

Artifact classification: `gate implementation`; risk route: `shared-gate`.
Owners: `defect-diagnosis` (cause and regression), `skill-extraction-workflow`
(shared script change), `testing-strategy` (suite).

## Diagnosis

Observed on `ubuntu-26.04` (bash 5.3.9, uutils coreutils 0.10.0):

- In failing runs the wrapper exits 2 and leaves its timeout diagnostic
  directory with every file written during the run; nothing is written later.
- A `bash -x` trace of the wrapper started with stdout closed shows
  `TIMEOUT_ARTIFACT_REPORTED=true`, so its final `printf '%s\n' "$OUT"`
  returned success. A minimal script started the same way gets a failing
  `printf`, so fd 1 was reused by something inside the wrapper before that
  write.
- The failure is intermittent: one diagnostic run passed.

Cause: the wrapper decides "delivered" from the write's return code. With
the caller's stdout closed, fd 1 is the lowest free descriptor and can be
taken by a later open in the wrapper, so the write succeeds into that file.
The result is then reported as delivered although the caller never saw it,
the diagnostic directory is kept, and the result lands in an unrelated file.
Which open takes fd 1 on this image is not identified (hypothesis); the fix
does not depend on it.

## Design

At startup, before anything else opens a file, test whether fd 1 is open
(`[ -e /dev/fd/1 ]`, which bash evaluates as "descriptor 1 is open" on every
platform). When it is closed, hold fd 1 on `/dev/null` so no later open can
take it and no write lands in an unrelated file, and skip the final write so
the run takes the undelivered path (exit 2, diagnostic directory removed).
An open stdout keeps the existing path.

The reuse is simulated in the suite with a `BASH_ENV` DEBUG trap that
reopens fd 1 on the line before the final write; anchoring on that line
rather than on the write keeps the simulation firing after the fix, which
skips the write.

Security four questions: the input is the caller's file descriptor table;
a forged state can only cause a result to be withheld. No identity, tenant
or permission decision. Negative case: the reuse simulation must leave the
reused file empty.

## Target-output map

| owner | direction | status | changed file or reason |
| --- | --- | --- | --- |
| code-review OpenCode wrapper | executor | updated | `skills/code-review/scripts/opencode_review.sh`, `skills/code-review/scripts/test_opencode_review_retry.sh` |
| other code-review wrappers | sibling | unchanged | only `opencode_review.sh` keeps a diagnostic depending on delivery (`grep` for the reported flag and the guarded write found no other wrapper) |
| testing-strategy | coordinator | unchanged | no layer policy change |
| platform-release-engineering | downstream | unchanged | runner image pinning not chosen |

## Acceptance

| ID | Scenario | Expected after | Baseline |
| --- | --- | --- | --- |
| C1 | stdout closed, fd 1 reused before the final write | exit 2, no diagnostic child, reused file empty | diagnostic child kept, result written to the reused file |
| C2 | stdout closed, no reuse | exit 2, no diagnostic child | same |
| C3 | stdout open, signal after the write | reported child kept, one output line | same |
| C4 | stdout closed | fd 1 held on /dev/null for the rest of the run | fd 1 left free |
