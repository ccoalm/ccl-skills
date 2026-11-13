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
