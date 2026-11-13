# Review record

Every pass ran through `skills/skill-extraction-workflow/scripts/extraction_review_gate.sh`
against `origin/main` at stage `build` with risk tag `shared-gate`. The
implementer family was `anthropic`. Controller results are the JSON files in
this directory.

## Review pass

- Reviewed commit: `7af702b` (implementation), with the register row in `67dc89b`
- Reviewer: Codex; plan source `implementer-supplied`
- Findings: 7 (0 P0 / 0 P1 / 7 P2); result `review.json`

| Finding | Disposition |
| --- | --- |
| `host-input.py`: a write call inside a Python comment counts as a write and spends the attempt | Fixed. Inline code drops `#` (Python, Ruby) or `//` (node) comments before write calls are matched. Rows for both languages. A write call quoted inside a string literal still counts; recorded in the plan as an accepted precision gap. |
| `host-input.py`: `git rm -n`, `git mv -n` and `rsync --dry-run` count as writes | Fixed. Dry-run flags on `git mv`/`git rm` and `rsync` yield no target. Four rows. |
| `host-input.py`: `<<` inside a comment or quotes is taken as a heredoc and swallows the next line | Fixed. Only a `<<` that is live shell syntax (unquoted, before any comment) opens a heredoc. Two rows. |
| `host-input.py`: a `cd` inside `( … )` or a pipeline leaks into later commands | Fixed. A group restores the directory when it closes, and a pipeline member's `cd` does not reach later commands. Three rows, including a `cd` that must still apply inside its own group. |
| `host-input.py`: option arities shared across commands (`rsync -t`, `rm -r`) | Fixed. Each command has its own option-value set: `rsync -t` preserves times, and `rm -r` takes no value. Two rows, plus a `truncate -s` row that keeps the value arity. |
| `skill-loading.py`: the packet lacks the surrounding hook code, so dispatch, attempt sharing and precedence cannot be verified | Input defect, not a candidate defect. The challenge packet is widened with the full `hooks/skill-loading.py`, `hooks/owner-dispatch-guard.sh` and the `hooks.json` Bash matcher, and keeps `--base` so it binds the same candidate. |
| `plan.md`: verification commands are listed without outcomes | Fixed. `evidence/validation.md` records each command's result for each candidate. |

Each fix's rows failed first against `7af702b` (`red-review-fixes.txt`).
Each new mechanism has an applied mutation that fails only its owning rows
(`mutation-walk.md`). While doing this, the read-only control case was
changed to give each command a fresh actor. Before that, one false positive
spent the shared attempt and every later row passed vacuously, which hid
three of the new failures.

## Challenge pass

- Reviewed commit: `b3053e9` (the review fixes), with the register row last
- Packet: the candidate diff, then the full `hooks/skill-loading.py`,
  `hooks/owner-dispatch-guard.sh`, the `hooks.json` Bash routing entry and the
  unchanged path helpers, appended as context after the candidate
- Reviewer: Codex; findings: 7 (0 P0 / 0 P1 / 7 P2); result `challenge.json`

| Finding | Disposition |
| --- | --- |
| A write call inside a string literal of inline code (`print("open(…, 'w')")`) counts as a write | Fixed. A write call counts only where it is live code; strings and comments share one mask. |
| Glued punctuation (`(printf x)>file`, `printf x;>file`) hides the redirection | Fixed. Glued punctuation is split into separator and redirection tokens. |
| An attached script (`perl -pi -e's/…/'`, `sed -i -e's/…/'`) drops the file operand | Fixed. An attached `-e`/`-f` counts as the script. |
| `git mv FILE DIR/` yields only the directory | Fixed. A directory destination maps to `DIR/<source name>`, as for `mv`. |
| `bash -n -c '…'` is a syntax check but counts its inner writes | Fixed. `-n` before `-c` yields no target. |
| `env -C DIR cmd` resolves operands from the wrong directory | Fixed by yielding no target, since that directory is not tracked. |
| No evidence the hook stays inside the 10 s timeout for accepted large inputs | Fixed. One command yields at most 256 targets. Five adversarial inputs at the 64 KiB cap, each on a fresh actor so the deny path runs, take at most 0.43 s (`validation.md`). |

Each fix's rows failed first against `b3053e9` (`red-challenge-fixes.txt`) and
each fix has an applied mutation (`mutation-walk.md`).

**Recurring-class decision: narrow.** Both passes returned new instances of
one class: shell forms the target parser misreads. A false positive spends
the single attempt; a miss only falls back to the Stop backstop, which was
the behavior before this change. The parser therefore yields no target when
unsure (untracked directory, dry run, syntax check, text that only looks like
code), and later misses are recorded as known misses in the plan rather than
patched pass by pass. Delete was considered and rejected: the observed miss
(Bash writes reaching only Stop) is real, and the common forms are covered
with measured precision.
