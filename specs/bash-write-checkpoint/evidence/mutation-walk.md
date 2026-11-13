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

The first run of the `mv` mutant deleted the line and left an empty `if`
body, which is a syntax error that failed every case. That is a failure for
the wrong reason and was not counted; the mutant was re-applied as `pass`,
and it then failed only its owning sub-case.

The git-commit heredoc row (`> see hooks/gate.sh` in a message body) is a
precision row that no listed mutant reds: tokenized as shell, that body's
redirection target is the word `see`, not the gate file. It stays as a
regression row for the documented heredoc behavior.
