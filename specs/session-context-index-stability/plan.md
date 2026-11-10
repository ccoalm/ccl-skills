# Preserve the Git index during session startup

## Change

SessionStart collects repository status without refreshing Git's cached file metadata. The `status` invocation in `hooks/session-context.sh` uses `--no-optional-locks`; modified and untracked files remain visible in the recovery context.

Refreshing `.git/index` can change a Git-backed plugin's content fingerprint even when its source files are unchanged. This fix covers that startup-query path. It does not attribute historical approval failures to a particular writer or prevent other processes from modifying the bundle.

## Release

Package version: `0.18.16`, the next patch after the declared and published `0.18.15`. Source baseline: `b0adadacb2b29c02bd8f622aa2e21a2d272db4d5` on `main`.

- Git installations receive the change when their marketplace and installed plugin snapshot are refreshed.
- npm installations receive it through the patch package and host-asset update.
- Installer behavior, automatic updates, filesystem permissions and host trust policy are unchanged. The host can still require approval for a genuine plugin update.
- No configuration migration, new dependency or persistent state is introduced.
- A rollback uses an immutable previous package or a new corrective patch; published versions are never overwritten. Returning to `0.18.15` also restores the index-refresh behavior.

## Verification

The shell integration regression exercises the real SessionStart hook in an ordinary checkout and a linked worktree. It compares index bytes, checks modified/untracked reporting and complete recovery framing, and confirms that an ordinary writable Git status can still refresh the fixture index. Chosen old timestamps make the fixture deterministic without sleeps.

| Check | Observed result |
| --- | --- |
| Existing startup suite | 33 passed |
| Added regressions before the fix | 37 passed; exactly 2 index-preservation failures |
| Startup suite after the fix | 39 passed |
| Independent implementation review | Passed; no findings |
| Adversarial review including package version | Passed; no findings |
| Repository, fast-regression and review-shard lanes in `make test` | Passed in an isolated Linux container |
| `make test-code-review-abort-leak` | All three probes passed in an isolated macOS environment |
| `make npm-publish-dry` | Passed on Linux: 431 tests passed, 3 platform skips; 11 pack tests passed |
| `make npm-pack-verify` | 11 tests passed on macOS |
| `make npm-host-smoke` with the candidate tarball | Codex, Claude Code and OpenCode lifecycle checks passed on macOS |

The required local lanes are covered across Linux and macOS. The Linux VM's boot-time value changed by one second during a cleanup probe, so that lane was rerun in full on macOS using the system process-query utility without its elevation bit. No test assertion or repository runtime was changed for the test environment.

Publication follows the [npm release procedure](../../docs/npm-release.md): required PR checks, a release tag on reviewed `main`, registry readback and verification of the published artifact.

Controller result excerpts are recorded under `evidence/`; local paths and transport diagnostics are omitted. Runtime changes are limited to the status query, with regression coverage in `hooks/test_session_start.sh`.
