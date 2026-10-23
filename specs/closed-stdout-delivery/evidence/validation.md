# Validation

> **Withdrawn.** The cause below (fd 1 reused by an open inside the wrapper)
> was never observed; a later comparison on the failing image showed that the
> test's `env` reopened the closed stdout on `/dev/null` instead. The wrapper
> change was reverted. See `specs/closed-stdout-test-launch/plan.md`.

## Reproduction

| Run | Image | Code | Closed-stdout case |
| --- | --- | --- | --- |
| PR #195, two runs | ubuntu-26.04 | branch | fail |
| PR #196 control | ubuntu-26.04 | main unchanged | fail |
| PR #197 probes 1–3 | ubuntu-26.04 | main plus probes | fail |
| PR #197 probe 4 | ubuntu-26.04 | main plus probes | pass (intermittent) |
| main, 2026-10-09 | ubuntu-24.04 | main | pass |

Probe findings on ubuntu-26.04 (bash 5.3.9, uutils coreutils 0.10.0): exit 2,
the diagnostic directory kept with files written during the run, and a
`bash -x` trace showing `TIMEOUT_ARTIFACT_REPORTED=true`; a minimal script
started with stdout closed gets a failing `printf`.

## RED and GREEN

`bash skills/code-review/scripts/test_opencode_review_retry.sh` on macOS
(bash 5.3.15):

- Before the fix: the new reuse case failed with exit 2, the diagnostic
  directory kept and 894 bytes of result written into the reused file.
- After the fix: all cases pass, including the original closed-stdout case
  and the post-write signal case.

## Applied mutations

Each ran the whole suite in a scratch copy of the scripts directory.

| Mutation | Result |
| --- | --- |
| wrapper from `origin/main` | RED: reuse case, held case |
| drop `exec 1>/dev/null` | RED: held case |
| drop the delivery flag from the final write | RED: original closed-stdout case, reuse case |
| detection always reports open | RED: reuse case, held case |

The first anchor (matching the final write) made the reuse case vacuous after
the fix, because the write no longer runs; the held case exposed it and the
anchor moved to the line before the write.

## Siblings

Search boundary: every non-test shell script in `skills/code-review/scripts/`
(`classify_timeout_exit.sh`, `claude_review.sh`, `codex_review.sh`,
`kimi_review.sh`, `normalize_review_timeout.sh`, `opencode_review.sh`,
`review_gate.sh`), searched for the reported flag and the `--diagnostic-dir`
option. Only `opencode_review.sh` matches (7 lines); the others keep no
diagnostic directory, so no delivery decision depends on their final write.

## Review and challenge

Independent review (codex, 3 P2, no P0/P1): two asked for wider packet
context and candidate-bound lanes (recorded below and in the pull request);
one asked for the sibling inventory (added above).

Challenge (codex, 3 P2, no P0/P1):

- Linux evidence for the fixed candidate → the required lane on the pull
  request runs this suite on ubuntu-26.04; open-stdout callers through a pipe
  are every other case of the suite. A tty or socket stdout is not exercised;
  `[ -e /dev/fd/1 ]` is true for any open descriptor, so they take the
  unchanged path.
- BASH_ENV reaches child bash processes, so the trap was not limited to the
  wrapper → a PID guard now restricts it to the wrapper; RED on the `main`
  wrapper and GREEN on the fix were rerun with the guard.
- Packet context for cleanup and signal paths → unchanged code, covered by
  the existing closed-stdout and post-write signal cases, both green.

Delta pass on the PID guard (codex, 3 P2, no P0/P1): a skipped injection
already fails the held-on-/dev/null case, which is how the first, vacuous
anchor was caught; the other two ask for lane results, recorded in the pull
request with the commit they covered.
