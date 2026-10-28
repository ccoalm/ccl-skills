# Terminal record

Classification: `narrow-visible`. One one-shot command loses a subcommand, and the installer gains one warning line. No structure, navigation or interaction changes. Both outputs go to stderr as plain text.

| Surface | Before | After |
| --- | --- | --- |
| `owner-dispatch.sh ci` | ran the map check; exit 0, 1 or 2 | prints the removal and the repair; exit 2 |
| `install-gates.sh` on a target whose pipeline still runs `owner-dispatch.sh ci` | no message | a warning names the file and says to delete the job |

## Copy criteria

- The removal message states what happened (the subcommand was removed), the repair (delete the CI job that runs it), and where the gate runs now.
- The installer warning states the file, the cause (the job runs a subcommand that no longer exists), the repair (delete that job) and the consequence (the refreshed engine exits 2 on it).
- The warning carries a symbol and text; the colour is not the only state carrier.
- The installer emits its ANSI colour codes unconditionally, also off a TTY. That behaviour predates this change and is out of scope here.

## Transcripts

Command: `bash scripts/owner-dispatch/owner-dispatch.sh ci --base HEAD` in a scratch repository, non-TTY:

```text
owner-dispatch: the ci subcommand was removed; delete the CI job that runs it. The gate now runs only in the session hooks.
exit=2
```

Command: `bash scripts/install-gates.sh <scratch repo>` with an edited `ci/agent-gates.gitlab-ci.yml` that keeps the old job, stderr, non-TTY. Colour codes are shown stripped:

```text
⚠ ci/agent-gates.gitlab-ci.yml exists and was edited (no install-gates marker) — left untouched. Delete it to regenerate.
⚠ ci/agent-gates.gitlab-ci.yml still runs 'owner-dispatch.sh ci', which no longer exists — delete that job; the refreshed engine exits 2 on it.
```

The same two behaviours are pinned by `scripts/owner-dispatch/test.sh` (section 10) and `scripts/test_install_gates_runtime.py`.
