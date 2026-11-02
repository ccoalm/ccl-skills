# Diff-First Runner

`scripts/review_diff.py` is the daily-development review and challenge
entrypoint. The reviewer reads `git diff` against the merge base and the
surrounding code itself, read-only, and answers in text. The runner only picks
an independent reviewer, binds the candidate, parses the answer and records
the result. Why it exists and what it replaced: `specs/diff-first-review/plan.md`.

## Use

```bash
python3 "$CODE_REVIEW_SKILL_DIR/scripts/review_diff.py" --cwd "$PWD" \
  --mode review --implementer-family claude --base origin/main \
  --intent "<requester's own words, then what the change does>"
```

- `--mode challenge` runs the adversarial pass on the candidate with the
  review's fixes applied; `--focus` names what to look at hardest.
- `--base` is any ref; the runner diffs the working tree against
  `git merge-base HEAD <ref>`, so uncommitted edits are covered and untracked
  files are named in the prompt. The default ref is `origin/HEAD`.
- `--implementer-family` accepts `claude`, `codex`, `kimi`, `opencode` and the
  aliases `openai`, `gpt`, `anthropic`; the reviewer of the same family is
  skipped.
- `--client-order` defaults to `codex,claude`. Kimi and OpenCode are not in
  this runner; use `review_gate.sh` when only they are independent.
- `--timeout` is per reviewer attempt (default 900 s). Set the host's own
  command timeout above it.
- `--out` names the result file, for example under the round's `evidence/`
  directory; the default is under `<git-dir>/ccl-code-review/results/`.

## Outcomes

| Exit | Status | Meaning |
| --- | --- | --- |
| 0 | `passed` | the whole answer was `No findings.` |
| 1 | `findings` | one or more `[P0-3] title — path:line` findings |
| 2 | `inconclusive` | see `reason_code` |

- A timeout, a launch failure, a non-zero exit or an empty answer gives the
  next eligible family one try. An interrupt (exit 130, 137 or 143, or a
  signal to the runner) ends the run without fallback.
- `unparseable_answer` keeps the answer in `raw_answer`; it often says why the
  reviewer could not finish. Fix that cause and rerun; never read it as a pass.
- `candidate_changed` means the working tree changed during the review;
  rerun on the settled candidate.

The result carries `schema_version: 3`, `mode`, `status` and `selected_client`
(the envelope `check_review_evidence_present.py` accepts) plus findings,
reviewer and implementer family, base, head, candidate tree, elapsed time and
attempts. The receipt `<git-dir>/ccl-code-review/last-review.json` carries the
fields `hooks/remind-review-covers-head.sh` reads.

## Boundary

- Codex runs `exec -s read-only --ephemeral` under a private `CODEX_HOME` that
  holds a link to `auth.json` and the user's top-level model keys plus the
  selected provider's table. MCP servers, hooks and plugins never load. The
  home lives under `$XDG_CACHE_HOME/ccl-code-review/` (default `~/.cache`),
  not the system temp dir, because Codex refuses to create its sandbox helper
  there.
- Claude gets `Read`, `Grep` and `Glob` only, `--add-dir` for the saved diff,
  `--permission-mode dontAsk`, no setting sources and no MCP servers. It has no
  shell, because git can write files (`git diff --output=...`).
- The reviewer can read what the user can read and sends it to its provider.
  The prompt tells it not to quote secret values.
