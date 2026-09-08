# Disposition — a replaced credential link discards a refreshed token

Occurrence: final-candidate review finding 1 (P2), against
`skills/code-review/scripts/codex_review.sh`.

Disposition: **accepted, fail-closed retained.** Not refuted; not fixed.

## The finding

The run reaches the user's credential through a symlink so an in-place refresh
lands in the user's own file. If the CLI instead *replaces* the link with a
regular file — an atomic write rather than an in-place one — the refreshed
credential exists only inside the run directory, which is deleted on exit. The
post-run guard refuses the run (`codex_runtime_home_credential_moved` /
`binding_mismatch`) but does not preserve that file, so a rotation performed
that way is lost, and if the rotation invalidated the previous token the user's
own credential is now stale.

## Why it is accepted rather than fixed

Writing to the user's `auth.json` from a failure path is the more dangerous
option. At that point the run knows only that the file is not the link it
created; it cannot tell a legitimate rotation from a partial write, an
unrelated process, or a corrupted token, and copying the wrong bytes over a
working credential breaks authentication outright rather than requiring one
re-login.

The sibling Kimi lane already resolves this the same way: it links validated
credential directories back to their user-owned paths, and a replaced or
missing link after the run is terminal `binding_mismatch`. Diverging here would
give the two lanes different credential-handling contracts for the same
situation.

Observed, not assumed: across every real-CLI run in this round the link
survived, with `readlink` still naming the source file after the run. The
failure this finding describes has not been observed on this CLI; the fixture
that exercises the guard replaces the link synthetically.

## Residual, stated plainly

If a future CLI release rotates by replacement, the first review run after that
change fails closed and the user must re-authenticate. That is a recoverable
interruption, and it is loud. The alternative — silently copying an
unverifiable file over the user's credential — is neither.

Reopen if a real run is observed replacing the link, or if the operator wants
the refreshed file preserved outside the run directory for manual recovery
rather than discarded.
