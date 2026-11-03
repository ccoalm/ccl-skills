# Diff-First Runner

`scripts/review_diff.py` is the daily-development review and challenge
entrypoint. The reviewer reads the diff against the merge base and the
surrounding code itself, read-only, and answers in text. The runner only picks
independent reviewers, moves on to the next when one fails, binds the
candidate, parses the answer and records the result. Why it exists and what it replaced: `specs/diff-first-review/plan.md`.

## Use

```bash
python3 "$CODE_REVIEW_SKILL_DIR/scripts/review_diff.py" --cwd "$PWD" \
  --mode review --implementer-family claude --base origin/main \
  --intent "<requester's own words, then what the change does>"
```

- `--mode challenge` runs the adversarial pass on the candidate with the
  review's fixes applied; `--focus` names what to look at hardest.
- `--base` is any ref; the runner saves the diff of the working tree against
  `git merge-base HEAD <ref>`, so uncommitted edits are covered, and names
  untracked files in the prompt. Every reviewer reads that saved diff rather
  than running `git diff` themselves, because repository git config could
  replace their output. The default ref is `origin/HEAD`.
- `--implementer-family` names the model family that wrote the change:
  `claude`, `codex`, `kimi`, `deepseek`, `gemini`, `qwen` or `glm`, or the
  aliases `anthropic`, `openai`, `gpt`, `moonshot`. A reviewer of the same
  family is skipped. A client that can run any model (`opencode`) or `other`
  is refused with `implementer_family_ambiguous`; pass the family of the model
  it ran.
- `--client-order` defaults to `codex,claude,opencode,kimi`. Installed clients
  of another family run in that order until one answers: a timeout, failed
  exit, empty or unparseable answer moves on to the next. An interrupt or a
  changed candidate ends the run. OpenCode's family comes from the model in
  the user's OpenCode config (`anthropic/...` is Claude, `deepseek/...` is
  DeepSeek); a model id naming no known family is skipped. Kimi's comes from
  its `default_model`, Kimi when unnamed. The result lists skipped clients
  and why under `skipped`.
- `--timeout` is per reviewer attempt (default 900 s), so a run that tries all
  four can take four times that. Set the host's own command timeout above it,
  or pass a shorter `--client-order`.
- `--out` names the result file, for example under the round's `evidence/`
  directory; the default is under `<git-dir>/ccl-code-review/results/`.

## Outcomes

| Exit | Status | Meaning |
| --- | --- | --- |
| 0 | `passed` | the whole answer was `No findings.` |
| 1 | `findings` | one or more `[P0-3] title — path:line` findings |
| 2 | `inconclusive` | see `reason_code` |

- `reason_code` is the last attempt's: `reviewer_timeout`,
  `reviewer_launch_failed`, `reviewer_failed` (non-zero exit), `empty_answer`
  or `unparseable_answer` when every reviewer failed, `operator_interrupt`
  (exit 130, 137 or 143, or a signal to the runner), or `no_eligible_reviewer`.
  Each attempt's own status is in `attempts`. A failed attempt's text is never
  a verdict and never reaches the next one, and a timed-out answer is never
  read.
- `unparseable_answer` means the answer was neither findings nor exactly
  `No findings.`; a finding line without its scenario counts too. It often
  says why the reviewer could not finish.
- For any of these, read `diagnostics_path`: a mode-600 file under
  `<git-dir>/ccl-code-review/diagnostics/` with each attempt's answer and
  stderr tail. They stay out of the result because they can quote repository content
  or credentials. Fix the cause and rerun; never read inconclusive as a pass.
- `candidate_changed` means the working tree changed during the review, for
  example an edit or a generated file; rerun on the settled candidate.

The result carries `schema_version: 3`, `mode`, `status` and `selected_client`
(the envelope `check_review_evidence_present.py` accepts) plus findings,
reviewer and implementer family, base, head, candidate digest (of HEAD,
`git diff --binary HEAD` and untracked contents, written to no object store),
elapsed time, every attempt (with the model it ran, and Codex's provider) and
the skipped clients.
Finding text is passed through the controller's secret patterns; a match is
replaced by `[REDACTED]` and the finding carries `redacted: true`. The receipt `<git-dir>/ccl-code-review/last-review.json` carries the
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
- OpenCode runs `opencode run --agent ccl-review -m <model>` with private
  config, data and state dirs. The config carries only the model, its
  provider's table and a `ccl-review` agent whose permissions deny everything
  except `read`, `grep`, `glob`, `list` and reading the repository and the
  saved diff's directory; project config, default and external plugins,
  Claude Code files, MCP servers and the user's plugins never load.
  `auth.json` is a link to the user's own. OpenCode imports `.opencode/plugin`
  code from its project directory and each parent up to the git root, and no
  flag turns that off, so its project is a private empty git repository and
  the repository under review is read as an outside directory by path.
- Kimi Code runs `kimi -p` under a private `KIMI_CODE_HOME` with links to the
  credential files, the model, provider and thinking tables, and a global tool
  allowlist of `Read`, `Grep` and `Glob`; hooks, MCP servers, plugins and skill
  dirs stay out, and the workspace is never marked trusted, so project-level
  MCP servers stay off.
- Every git call the runner makes switches off repository-configured programs:
  fsmonitor, filter drivers (replaced by pass-through), textconv and external
  diff. A repository with an encrypting filter therefore shows its stored
  bytes against the working-tree bytes in the diff.
- The reviewer can read what the user can read and sends it to its provider.
  The prompt tells it not to quote secret values.
- Codex and Claude count as their own family whatever model they are
  configured with; OpenCode and Kimi count by model id. A provider alias that
  hides the real model (a proxy named after nothing) is skipped as unknown,
  or counted by the word it does contain; check `attempts[].model` when that
  matters.
