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
- `--implementer-family` names the model family that wrote the change:
  `claude`, `codex` or `kimi`, or the aliases `anthropic`, `openai`, `gpt`.
  The reviewer of the same family is skipped. A client that can run any model
  (`opencode`) or `other` is refused with `implementer_family_ambiguous`; pass
  the family of the model it ran.
- `--client-order` defaults to `codex,claude`; the first installed client of
  another family runs, once. To try the other family after an inconclusive
  run, rerun with the order swapped. Kimi and OpenCode are not in this runner;
  use `review_gate.sh` when only they are independent.
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

- `reviewer_timeout`, `reviewer_launch_failed`, `reviewer_failed` (non-zero
  exit), `empty_answer` and `operator_interrupt` (exit 130, 137 or 143, or a
  signal to the runner) end the run; a failed run's text is never a verdict,
  and a timed-out answer is never read.
- `unparseable_answer` means the answer was neither findings nor exactly
  `No findings.`; a finding line without its scenario counts too. It often
  says why the reviewer could not finish.
- For any of these, read `diagnostics_path`: a mode-600 file under
  `<git-dir>/ccl-code-review/diagnostics/` with the answer and the stderr
  tail. They stay out of the result because they can quote repository content
  or credentials. Fix the cause and rerun; never read inconclusive as a pass.
- `candidate_changed` means the working tree changed during the review, for
  example an edit or a generated file; rerun on the settled candidate.

The result carries `schema_version: 3`, `mode`, `status` and `selected_client`
(the envelope `check_review_evidence_present.py` accepts) plus findings,
reviewer and implementer family, base, head, candidate digest (of HEAD,
`git diff --binary HEAD` and untracked contents, written to no object store),
elapsed time and the one attempt. The receipt `<git-dir>/ccl-code-review/last-review.json` carries the
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
- Every git call the runner makes switches off repository-configured programs:
  fsmonitor, filter drivers (replaced by pass-through), textconv and external
  diff. A repository with an encrypting filter therefore shows its stored
  bytes against the working-tree bytes in the diff.
- The reviewer can read what the user can read and sends it to its provider.
  The prompt tells it not to quote secret values.
