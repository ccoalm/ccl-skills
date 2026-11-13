# Bash-written edits at the first source-edit checkpoint

First written before any hook or test edit, after the extraction charter was
recorded in per-host scratch. It was then updated with the fixes from an
independent design critique, before review.

## Outcome and scope

The first source-edit checkpoint (`hooks/skill-loading.py`) fires on
`Edit`, `Write`, `MultiEdit`, `NotebookEdit` and `apply_patch`. A shell command
that writes into a ccl-skills checkout's `skills/`, `hooks/` or `scripts/`
surface reached only the extraction stop backstop, after the work was done.

After this change a `Bash` call whose command writes a source-extension or
markdown file on that shared surface reaches the same checkpoint, when
`skill-extraction-workflow` is not loaded in the current context. It is the
same lane as the edit tools, so the actor still gets one denial per context in
total, not one per tool. A `Bash` call that only reads, writes elsewhere, or
writes there with the extraction owner already loaded is not checkpointed and
does not spend the attempt.

Artifact classification: `gate implementation` — a previously quiet input
(`Bash`) now reaches an existing deny-once checkpoint. Denials per actor and
context do not change.
Risk tags: `shared-gate`. Visible surface: checkpoint reason text.
Security posture: no change to credentials, egress or permission enforcement.
The checkpoint stays one bounded replan, not approval. The parser never
evaluates the command: it tokenizes with `shlex` and reads literal words.

### Reuse decision

- Shared-surface scope: reuse `shared_skill_paths` and the markdown/source
  extension rule unchanged, so the edit tools and `Bash` share one definition.
- Attempt cap and context proof: reuse the `implementation` lane and its
  `claim_attempt` epoch.
- Write detection: the owner-dispatch engine's `Bash` branch has a write-verb
  regex, but it only says "some write happened somewhere" and is record-only
  because it matches read-only commands (`>/dev/null`, `python -c`, heredocs).
  It yields no target, so it cannot scope to the shared surface. The
  `guard-broad-local-test.sh` tokenizer is sed-based and strips redirections.
  Neither yields write targets, so a small target extractor is added next to
  the existing `paths()` normalizer in `hooks/host-input.py`, built on stdlib
  `shlex` like `skill_reads`. It is not a shell parser: it reads literal words
  of known write forms and returns nothing for anything else.

### Recognised write forms

| Form | Target |
| --- | --- |
| `>`, `>>`, `>\|`, `&>`, `N>` redirection | the next word, unless `/dev/null` or an fd duplication |
| `tee [-a] FILE...` | each file operand |
| `sed -i…` / `--in-place` | file operands after the script |
| `perl -i…` (bundled flags such as `-pi`) | file operands |
| `cp`, `mv`, `install`, `ln`, `rsync` | the destination (`-t DIR` or last operand); a directory destination maps to `DIR/<source name>`; `mv` also counts its sources, which it removes |
| `touch`, `truncate`, `rm`, `unlink`, `git mv`, `git rm` | each file operand (a `git mv` directory destination maps to `DIR/<source name>`); option values follow each command's own arity (`truncate -s N`, `touch -r REF`; `rm -r` takes none) |
| `git mv`/`git rm -n`, `--dry-run`; `rsync -n`, `--dry-run` | none: a dry run writes nothing |
| `python…`, `node`, `ruby` with `-c`/`-e` code, or with a heredoc body | only the literal a write call writes to: `open(LIT, 'w'/'a'/'x'/'+')` (also `mode=`), `Path(LIT).write_text/write_bytes/touch/unlink/open('w')`, `writeFile*/appendFile*/unlink*/rm*(LIT`, `File.write(LIT`, `os.remove/unlink(LIT`, the second argument of `shutil.copy*/move` and `os.replace/rename` |
| `bash -c` / `sh -c` | the inner command, one level |
| `cd DIR` earlier in the same command | later relative targets resolve from `DIR`, except after the `( … )` group holding the `cd` closes, or when the `cd` is a pipeline member |

Leading `NAME=value` assignments and `sudo`, `env`, `command`, `nohup`, `time`
wrappers (with their options, e.g. `sudo -u root`) are skipped. Heredoc
bodies are cut out before tokenizing; they are code only when the segment's
command is an interpreter, and data otherwise. A `<<` inside quotes or a
comment is text, not an operator. Quoted or escaped shell metacharacters are
hidden before tokenizing, so `grep '>' file` is not a redirection. An unquoted
`#` starting a word comments out the rest of its line. In inline code, a
write call counts only where the call itself is live code: one inside a
string literal or a `#` (Python, Ruby) or `//` (node) comment is text. Glued
punctuation such as `)>` or `;>` is split into its separator and its
redirection. `sed`/`perl` scripts attached to `-e` (`-e's/a/b/'`) count as
the script. `bash -n -c` writes nothing. A command run through `env -C DIR` or
`--chdir` yields no target, because its directory is not tracked. Commands
over 64 KiB yield no target, and one command yields at most 256 targets; at
that cap the hook's worst measured run is 0.43 s (`evidence/validation.md`).

Known misses (stay on the stop backstop, quiet side): words containing `$` or
backticks, `git -C`, `find -exec`, `xargs`, `git apply`/`checkout`/`restore`,
extension-less targets such as `cp -r dir skills/`, scripts that write
internally, a path bound to a variable and written later, and any command
`shlex` cannot tokenize.

### Precision first, recall best effort

A false positive spends the context's single attempt and costs a later real
edit its checkpoint; a miss leaves the write where it was before this change,
on the Stop backstop. So a form that could be read as a write but may not be
one (an untracked directory, a dry run, a syntax check, text that only looks
like code) yields no target. Both review passes returned new instances of the
same class, parser edge forms. Each pass's instances were fixed with a row and
a mutant; a further miss is recorded here as a known miss, not patched pass by
pass.

### Deliberate differences from the edit-tool path

- Scope. An edit tool reaches the checkpoint for any source-extension path; a
  `Bash` command only for the shared surface. A shell false positive spends
  the context's single attempt, so a later real edit would get no checkpoint.
  Limiting the shell lane to the shared surface bounds that cost.
- Loaded owner. With the extraction owner loaded, an edit-tool write still
  gets the generic deny once; a `Bash` write gets none and keeps the attempt.
  The shell lane exists only to carry the extraction owner, and the generic
  owner-load message for an edit tool is unchanged.
- Reason text. The first sentence reads "this shell command writes a file and
  did not execute"; the shared-surface clause names the first target, as for
  edit tools.

## Acceptance decision table

| Command | Target on shared surface | Extraction owner loaded | Attempt spent | Decision |
| --- | --- | --- | --- | --- |
| any recognised write form above | yes (`.md` or source extension) | no | no | deny once; reason names the extraction owner and the charter |
| same | yes | yes | no | no checkpoint; attempt not spent |
| same | target is a non-source, non-markdown file (e.g. `.json`) | no | no | no checkpoint |
| `cat`, `grep`, `sed -n`, `git diff`, `ls` on shared files | — | no | no | no checkpoint |
| read on shared files, redirect to `/tmp` or `/dev/null` | no | no | no | no checkpoint |
| interpreter reads a shared file and writes elsewhere, even in one statement | no | no | no | no checkpoint |
| write into a checkout without the marker, a plugin cache or a `.codex` copy | no | any | no | no checkpoint |
| any write on the shared surface | yes | no | yes (an edit-tool denial in this context) | no checkpoint |
| unbalanced quotes | — | any | no | no checkpoint |

The stop backstop is unchanged and remains the late backstop.

## Test and register coverage

`hooks/test_skill_loading.py` (already registered in `make test`) covers every
row above: each write form in the first row is a sub-case, and the no-checkpoint
rows are sub-cases of one control case that also asserts no attempt was spent.
Each first-row sub-case is run against
the unmodified hook first and must fail there (RED baseline,
`evidence/red-baseline.txt`). Applied mutations on copies, each expected to
fail only its owning cases (`evidence/mutation-walk.md`): drop the `Bash`
lane; drop the loaded-owner skip; drop the extension filter; give the shell a
separate lane; stop hiding quoted metacharacters; stop cutting heredoc
bodies; take every quoted path in code that contains a write call; stop
stripping comments; drop the length cap; stop counting `mv` sources.

## Declared-but-unenforced gate class

No mechanical trigger lands for this class. The measured candidates and the
reopen condition are in
`specs/bash-write-checkpoint/evidence/declared-unenforced-class.md`.

## Verification

`make test`, `test_check_ccl_regressions.sh --heavy-only`,
`check-public-sanitization.py`, `git diff --check`, `check-ccl-skills.sh` with
`CCL_SKILL_BASE_REF=origin/main`. Outcomes per candidate:
`evidence/validation.md`.

## Status sync

No status source or version field changes.

## Review gate

One review and one challenge through
`skills/skill-extraction-workflow/scripts/extraction_review_gate.sh`, risk tag
`shared-gate`; later fixes get one batched delta pass; findings verified and
dispositioned before the pull request.
