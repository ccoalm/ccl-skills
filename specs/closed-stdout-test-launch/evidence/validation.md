# Validation

## CI reproduction

| Run | Image | Code | Closed-stdout case |
| --- | --- | --- | --- |
| PR #195, three runs | ubuntu-26.04 | branch | fail |
| PR #196 control | ubuntu-26.04 | main unchanged | fail |
| PR #197 probes 1–3 | ubuntu-26.04 | main plus probes | fail |
| PR #197 probe 4 | ubuntu-26.04 | main plus probes | pass (unexplained) |
| PR #198 probe | ubuntu-26.04 | main plus probe | fail; `env` launch 3/3 kept, direct launch 0/3 kept |
| main, 2026-10-09 | ubuntu-24.04 | main | pass |

#198 also printed `env` at `/usr/lib/cargo/bin/coreutils/env` and fd 1 of a
process started through it with a closed stdout as `/dev/null`.

Primary source: `library/std/src/sys/pal/unix/mod.rs` in rust-lang/rust calls
`sanitize_standard_fds()` at startup, which opens `/dev/null` for a closed
standard stream. Read on 2026-10-23.

## Local RED and GREEN

macOS, bash 5.3.15. "Rust-like env" is a scratch `env` placed first on PATH
that reopens closed fds 0–2 on an inheritable `/dev/null` and then execs the
system `env`. Each row ran the whole suite in a scratch copy.

| Harness | env | Result |
| --- | --- | --- |
| old (close before `env`) | Rust-like | RED: closed-stdout case only |
| old | system | GREEN (control, one variable) |
| new (close after `env`) | Rust-like | GREEN |
| new | system | GREEN |
| new without the close | Rust-like | RED: launcher precondition and closed-stdout case |

Rust-like env shim (scratch only, not committed):

```python
#!/usr/bin/python3
import os, sys
for fd in (0, 1, 2):
    try:
        os.fstat(fd)
    except OSError:
        os.set_inheritable(os.open("/dev/null", os.O_RDWR), True)
os.execv("/usr/bin/env", ["env"] + sys.argv[1:])
```

Each row ran `PATH=<shim dir>:$PATH bash <scratch copy>/test_opencode_review_retry.sh`
(system rows without the PATH prefix); the old harness is the file at
8bafd94, the mutant replaces `exec 1>&- && exec "$@"` with `exec "$@"`.

The first version of the precondition probe redirected the whole `if` into
its result file and so always saw fd 1 open; it failed on the fixed harness,
was traced to the probe, and now tests fd 1 before redirecting.

## Siblings

Shell redirections: `git grep -nE '(>&-|<&-|2>&-)' -- '*.sh' '*.py'` finds,
besides this case, only `hooks/test_task_entry.py:140`, which runs
`bash -c 'bash "$1" <&-'`: the closing bash execs the hook's bash directly,
with no other program between.

Programmatic closes: `git grep -nE 'os\.close\((0|1|2)\)|close\((STDIN|STDOUT|STDERR)_FILENO\)|exec [0-2]>&-|exec [0-2]<&-'`
over `*.sh *.py *.mjs *.ts *.rb *.go` finds only
`skills/skill-extraction-workflow/scripts/test_eval_runtime.py:52` and `:54`,
where a Python child closes its own fd 1 while it runs; no exec follows, so
nothing can reopen it.

## Review and challenge

Independent review (codex, 2 P2, no P0/P1): asked for the plain-env result of
the new harness, the shim and commands (added above) and for programmatic
descriptor closes in the sibling search (added above).

Challenge (codex, 1 P2, no P0/P1): a conditional `bash` stub under
`$WORK/bin` could satisfy both assertions without starting the wrapper.
Refuted from the suite: `$WORK/bin` holds only `cat`, `head`, `ls`,
`opencode`, `python3`, `stat` and `timeout`, so `bash` is the system shell;
`BASH_ENV` is set only inside a command substitution near line 573 and around
the post-write signal case after this one, where it is unset again.
