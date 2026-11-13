# Applied mutation walk

Each mutant was applied to its own copy of the tree (never the worktree),
after confirming the replaced text occurred exactly once. The unmodified copy
passed `hooks/test_skill_loading.py` first.

| Mutant | Failing cases | Owning case | Differential |
| --- | --- | --- | --- |
| drop the `Bash` lane | shared-surface writes (27 sub-cases), absolute write | both | yes |
| drop the loaded-owner skip | owner-loaded case | owner-loaded case | yes |
| drop the extension filter | read-only/off-surface (`echo {} > hooks/hooks.json`) | same | yes |
| give the shell a separate lane | write after an edit checkpoint | same | yes |
| stop hiding quoted metacharacters | read-only (`grep '>' …`) | same | yes |
| stop cutting heredoc bodies | shared-surface writes (`cat <<'EOF' >` with an apostrophe in the body; interpreter heredoc) | same | yes |
| take every quoted path in write code | read-only (read and write in one statement) | same | yes |
| stop stripping comments | read-only (`ls skills # then > hooks/gate.sh`) | same | yes |
| drop the 64 KiB cap | read-only (oversized command) | same | yes |
| stop counting `mv` sources | shared-surface writes (`mv skills/…/rule.md /tmp/`) | same | yes |
| treat `<<` in a comment or quotes as an operator | shared-surface writes (`# <<EOF`, `echo 'a <<EOF'`, each followed by a write) | same | yes |
| keep comments in inline code | read-only (`# open(…, 'w')` in Python, `// writeFileSync(…)` in node) | same | yes |
| ignore `git mv`/`git rm` dry runs | read-only (`git rm -n`, `git mv --dry-run`) | same | yes |
| ignore `rsync` dry runs | read-only (`rsync -n`, `rsync -av --dry-run`) | same | yes |
| give `rsync -t` the target-directory meaning | shared-surface writes (`rsync -t … hooks/gate.py`) | same | yes |
| let `rm -r` take a value | shared-surface writes (`rm -r hooks/gate.sh`) | same | yes |
| keep a `cd` after its `( … )` group closes | shared-surface writes (`(cd /tmp); printf x > hooks/gate.sh`) | same | yes |
| let a `cd` in a pipeline reach later commands | shared-surface writes (`cd /tmp \| true; …`) | same | yes |
| match write calls inside string literals and comments of inline code | read-only (`print("open(…, 'w')")`, and the two comment rows, which use the same live-code mask) | same | yes |
| leave glued punctuation such as `)>` unsplit | shared-surface writes (`(printf x)>…`, `printf x;>…`) | same | yes |
| recognise only a standalone `-e` script | shared-surface writes (`perl -pi -e's/…/'`, `sed -i -e's/…/'`) | same | yes |
| leave a `git mv` directory destination unmapped | shared-surface writes (`git mv /tmp/draft.py hooks/`) | same | yes |
| ignore `bash -n` | read-only (`bash -n -c '… > hooks/gate.py'`) | same | yes |
| ignore `env -C` / `--chdir` | read-only (`env -C /tmp touch …`, `env --chdir=/tmp touch …`) | same | yes |
| scan inline code line by line | shared-surface write (`open(` split across lines) and read-only (triple-quoted example) | same | yes |
| drop the operand cap | bounded-targets case (`touch` with 1,000 operands) | same | yes |
| drop the inline-code cap | bounded-targets case (1,000 write calls) | same | yes |
| drop the redirection cap | bounded-targets case (1,000 redirections) | same | yes |

The first run of the `mv` mutant deleted the line and left an empty `if`
body, which is a syntax error that failed every case. That is a failure for
the wrong reason and was not counted; the mutant was re-applied as `pass`,
and it then failed only its owning sub-case.

Rows 11 to 18 cover the review fixes, rows 19 to 24 the challenge fixes and rows 25 to 28 the delta-pass fixes.
Each fix's rows were run first against the candidate that pass reviewed and
failed there (`evidence/red-review-fixes.txt`, `evidence/red-challenge-fixes.txt`, `evidence/red-delta-fixes.txt`).
The "keep comments in inline code" mutant was run on `b3053e9`; on the final
candidate, comments and string literals share one mask, which the
string-literal mutant covers. The read-only control case gives every
command a fresh actor, so one false positive cannot spend the attempt that
later rows would otherwise pass on vacuously.

The git-commit heredoc row (`> see hooks/gate.sh` in a message body) is a
precision row that no listed mutant reds: tokenized as shell, that body's
redirection target is the word `see`, not the gate file. It stays as a
regression row for the documented heredoc behavior.
