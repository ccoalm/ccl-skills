# Repository gates run under any locale

Under a POSIX or unset locale, `make test` stopped at its first step:
`check-ccl-skills.sh` → `validate-skill.sh` raised `invalid byte sequence in
US-ASCII` from a `ruby -e` block before checking anything. Ruby takes both its
default external encoding and the source encoding of `-e` programs from the
locale, and the skill text is UTF-8. CI runs C.UTF-8, so it never saw the crash;
containers and minimal shells that leave the locale unset did, and an agent
following the repository contract had to diagnose the gate instead of running it.

Artifact classification: `gate implementation`, semantics-preserving. No gate
rule, scope, threshold, verdict or output token changes; the fix only makes the
existing gates evaluate where they previously crashed. Risk tags: `shared-gate`.
Security posture: unchanged — no input, authority or data path is touched.

## Baseline

On the base commit, with `LANG=` and `LC_CTYPE=POSIX`:

- `make test` exits 2 at the first `ruby -e` block in `validate-skill.sh`;
- `bash skills/skill-extraction-workflow/scripts/check-ccl-skills.sh .` exits
  non-zero with the same error;
- the new `test_locale_independent_gates.sh` fails its static leg, listing every
  ruby-invoking script.

Probes on Ruby 3.3: `RUBYOPT=-EUTF-8` fixes file reads but not `-e` programs
containing UTF-8 literals (`invalid multibyte char (US-ASCII)`); `RUBYOPT=-Ku`
fixes both; `LC_ALL=C.UTF-8` fixes both but depends on the locale being
installed and also changes collation and other tools' character handling.

## Change

- Each tracked shell script under `skills/`, `hooks/` and `scripts/` that invokes
  ruby (24, all in `skills/skill-extraction-workflow/scripts/`) pins
  `RUBYOPT=-Ku` right after its `set` line, idempotently, so nested scripts do not
  stack the flag and a caller's own `RUBYOPT` is kept. Under a UTF-8 locale this
  is what Ruby already does, so CI behaviour is unchanged.
- `test_locale_independent_gates.sh` (fast lane) holds the class:
  1. every live ruby-invoking shell script carries the pin;
  2. `validate-skill.sh` passes on a UTF-8 fixture under `LC_ALL=C`;
  3. the same run with the pin removed fails for the encoding reason, so leg 2
     cannot pass vacuously.
- Frozen evidence scripts under the per-spec evidence directories and `eval/evidence/` are
  records, not live gates, and stay untouched.

## Acceptance

| Input | Expected |
| --- | --- |
| live ruby-invoking script without the pin | leg 1 fails, names the script |
| fixture skill, shipped `validate-skill.sh`, `LC_ALL=C` | passes, prints `markdown_references_ok` |
| same, pin removed | fails with `invalid byte sequence` / `invalid multibyte char` |
| `check-ccl-skills.sh .`, `LC_ALL=C` | `ccl_skill_check_interim_ok` (was: Ruby crash) |
| `make test`, `LC_ALL=C` and `C.UTF-8` | same verdicts as CI |

## Residual

- The Makefile `eval-*` targets call `ruby` directly; they are outside
  `make test` and keep the caller's locale.
- A caller that clears the environment (`env -i`) before invoking ruby inside a
  gate loses the pin; no live script does this today.

## Review

Independent review and adversarial challenge per the skill-extraction dual-track
gate; results are recorded in the pull request.
