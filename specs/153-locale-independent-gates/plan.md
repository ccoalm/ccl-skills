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
  stack the flag and a caller's own `RUBYOPT` is appended. Under a UTF-8 locale
  this is what Ruby already does at default verbosity, so CI behaviour is
  unchanged. Three test lines that set `RUBYOPT` for a single ruby call now keep
  the exported value instead of replacing it.
- `test_locale_independent_gates.sh` (fast lane) holds the class:
  1. every live ruby-invoking shell script carries the pin; every other
     literal `RUBYOPT` mention is one of two allowed shapes — the keep idiom
     `RUBYOPT="${RUBYOPT:+$RUBYOPT }…"` whose suffix holds only `-r<lib>`
     requires or variables (Ruby's option names are not this repository's to
     enumerate, so the suffix is allowlisted), or an empty `RUBYOPT=` before
     `bash "$script"`, whose script pins itself — and anything else (replacing,
     clearing, `unset`, `env -u`, any other Ruby option) fails. The classifier
     is held by permanent rows in the suite — every bypass spelling review found
     must be flagged and every near-miss must stay allowed — and the whole scan
     runs once on a fixture file; the leg also fails rather than passing
     when `git ls-files` cannot list the tracked scripts. Three review rounds each
     found new shell spellings past a list of forbidden forms, so the check is an
     allowlist over the idiom this repository owns, not a denylist over shell
     syntax;
  2. `validate-skill.sh` passes on a UTF-8 fixture under `LC_ALL=C`;
  3. the same run with the pin removed fails for the encoding reason, which shows
     the pin is what makes leg 2 pass. When a probe (`Encoding.find("locale")`
     under `LC_ALL=C`) shows the host's C locale is already UTF-8, the pin is not
     load-bearing; leg 3 then prints
     `test_locale_independent_gates_leg3_unevaluated` and the suite reports
     legs 1-2 only.
- Frozen evidence scripts under the per-spec evidence directories and `eval/evidence/` are
  records, not live gates, and stay untouched.

## Acceptance

| Input | Expected |
| --- | --- |
| live ruby-invoking script without the pin | leg 1 fails, names the script |
| any `RUBYOPT` mention outside the pin, the keep idiom and `RUBYOPT= bash "$script"` | leg 1 fails, names the line |
| run outside a git checkout | leg 1 fails instead of passing on an empty list |
| fixture skill, shipped `validate-skill.sh`, `LC_ALL=C` | passes, prints `markdown_references_ok` |
| same, pin removed | fails with `invalid byte sequence` / `invalid multibyte char` |
| same, pin removed, host C locale reads UTF-8 | `…_leg3_unevaluated`; suite reports legs 1-2 |
| same, pin removed passes, host Ruby reads US-ASCII under C | leg 3 fails: leg 2 may be vacuous |
| `check-ccl-skills.sh .`, `LC_ALL=C` | `ccl_skill_check_interim_ok` (was: Ruby crash) |
| `make test`, `LC_ALL=C` and `C.UTF-8` | same verdicts as CI |

## Residual

- The Makefile `eval-*` targets call `ruby` directly; they are outside
  `make test` and keep the caller's locale.
- A caller that clears the environment (`env -i`) before invoking ruby inside a
  gate loses the pin; no live script does this today.
- Leg 1 finds ruby by the bare word `ruby`. A script that runs Ruby only through
  a variable (`"$RUBY"`) or executes a `.rb` file directly by its shebang would
  not be flagged; no live script does either today.
- Python callers (`test_eval_runtime.py` runs `eval-golden-trace.rb`) are not
  pinned. That suite passes under `LC_ALL=C`, but not because of Python's locale
  coercion, which `LC_ALL` disables. The script reads its input through
  `JSON.parse`, which handled UTF-8 under the C locale in a direct probe; an
  end-to-end run on UTF-8 trace input was not made.
- Leg 1 also misses `ruby.exe`; Windows hosts are not a target of these gates.
- Leg 1 is a scan of literal text. Spellings that drop the pin without the
  literal token (`unset RUBY''OPT`, `eval` of a built string, an indirect
  variable name) and `ruby --disable=rubyopt`, which ignores `RUBYOPT`
  entirely, pass it; no live script uses them.
- The allowlist is deliberately strict: a safe option such as `--disable-gems`
  after the keep idiom is flagged until it is expressed another way. A
  variable in the suffix (`$2`) is opaque; the live caller passes only
  `-r<lib>` values through it.
- The comment strip treats ` #` as a comment only when no quote or backslash
  precedes it on the line, so a trailing comment after a quoted value is
  scanned too (flagged if it names the variable).
- The allowed `RUBYOPT= bash "$script"` shape trusts that the script pins
  itself; a variable that expands to `-c`, or a generated script without the
  pin, would run Ruby unpinned.
- A caller `RUBYOPT` that sets a different external encoding (`-E ASCII`,
  `-EASCII-8BIT`) now conflicts with `-Ku` and Ruby refuses to start
  (`default_external already set`); `-EUTF-8` and `-U` still work, and a later
  caller `-Kn`/`-Ke` wins the source encoding.
- `-K` is legacy syntax: Ruby 3.3 no longer lists it in `ruby -h`, and with `-w`,
  `-W2` or `ruby -v` it prints a compatibility warning on stderr (default
  verbosity stays clean). A future Ruby that drops it would make every pinned
  gate fail loudly, CI included, not pass silently.

## Review

Independent review and adversarial challenge per the skill-extraction dual-track
gate; results are recorded in the pull request.
