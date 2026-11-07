# Validation

## Behavior matrix

`bash hooks/test_guard_broad_local_test.sh`: 107 passed, 0 failed. Rows cover whole suites per stack, the same runners narrowed by name, file, package, positional filter or variable, the four reasons and two invalid ones, read-only flags, repository lanes and named subsets, option values and package names that look like lane names, redirection targets under `tests/`, mentions in quoted text (including quotes that span lines), escaped quotes and heredoc bodies, `FULL=` values other than 1, a non-Bash tool, an empty payload, and hosts where `jq` or `tr` is missing, `tr` fails, or a grep stage of the file scan fails.

## Mutation walk

Each mutation was applied to a disposable copy of the hook and the suite pointed at it with `BROAD_TEST_HOOK`. The tracked file was never edited. 35 mutations: 34 red at the row that owns the predicate, 1 equivalent.

| Mutation | Suite | First failing row |
| --- | --- | --- |
| deny replaced by `additionalContext` | red | `make test-scenario` |
| command-position anchor widened to any word | red | `grep -n pytest pyproject.toml` |
| `uv`/`poetry run` prefix removed | red | `uv run pytest -q` |
| `timeout N` prefix removed | red | `timeout 600 pytest` |
| selector check removed | red | `make test-scenario RUN=TestAnswers` |
| file selector removed | red | `pytest tests/unit/test_card.py` |
| file selector accepts globs | red | `node --test test/**/*.test.ts` |
| file selector accepts `...` package trees | red | `go test -tags scenario ./test/scenario/...` |
| reason not checked against the four values | red | `CCL_BROAD_TEST_REASON= make test-scenario` |
| `repo-required` removed | red | `CCL_BROAD_TEST_REASON=repo-required npm test` |
| `FULL=` opt-in removed | red | `make test-scenario FULL=1` |
| read-only flags removed | red | `go test -list . ./...` |
| `make -n` removed | red | `make -n test-scenario` |
| Bash tool scope removed | red | `make test-scenario` as an Edit call |
| slow-lane words removed | red | `make test-scenario` |
| every `test*` name treated as whole | red | `make test-fast` |
| quote mask removed | red | `git commit -m "fixed; npm test passes"` |
| escaped characters kept | red | `echo "\"; npm test; \""` |
| redirection targets kept | red | `npm test > tests/output.log` |
| make `-C`/`-f` values kept | red | `make -C tests check` |
| package-runner prefix accepts any word | red | `npm install integration` |
| options after `run` not accepted | red | `npm run -s test:integration > out.log 2>&1` |
| non-JS positional filter removed | red | `npx playwright test login` |
| JS positional filter removed | red | `pnpm -s test src/legacyHandoff` |
| positional filter accepts globs | red | `node --test test/**/*.test.ts` |
| tool-presence check removed | red | missing `tr` must allow |
| `tr` failure not allowed | red | failing `tr` must allow |
| any `FULL=` value accepted | red | `FULL=0 pytest` |
| quote mask per line | red | multi-line `git commit -m "summary ...` |
| upstream grep failure not allowed | red | failing grep stage must allow |
| pytest and node accept any positional word | red | `pytest --tb short` |
| one-word quote mask spans the newline placeholder | red | multi-line `git commit -m "summary` with a one-word line |
| OpenCode enforces the guard when it cannot run | red | `OpenCode runs Bash when the broad-test guard fails and blocks on its deny` |
| `command -v jq` exit removed | green | equivalent: the tool-presence loop also exits when `jq` is missing |

## Transcript replay

Input: recorded agent Bash calls from one 18-day window, deduplicated by tool-use id (about 120,000), filtered to the 16,837 distinct command texts that mention a runner word. 3,000 were sampled and sent through the hook as PreToolUse payloads. The hook never wrote to stderr.

| Hook | Denied |
| --- | --- |
| first predicate | 160 |
| final predicate | 134 |

Every command the first predicate denied and the final one allows was checked by hand. They are all false fires of the first predicate:

- matches inside a heredoc body: commit messages, patch scripts and handoff prompts that name a runner;
- narrow runs whose filter is a positional argument, such as `pnpm test src/utils` or `pnpm test -- src/upgrade-modal`.

The commands still denied are a runner in command position with no selector: bare `npm test` and `pnpm test` (often under `timeout 900` to `timeout 3500`), `make test`, `make test-integration`, `go test -race ./...`, `node --test` with no file and `npm run test:integration`. Some of these are lanes a repository requires locally; those take `CCL_BROAD_TEST_REASON=repo-required` once per command.

An intermediate predicate let `npm run -s test:integration` through, because it accepted options only before `run`. The replay surfaced it; a row and a mutation now pin it.

## Review dispositions

The first independent review returned seven P2 findings and no P0 or P1. Each code finding got a row that was red on the reviewed commit and is green now:

| Finding | Disposition |
| --- | --- |
| escaped quote ends the mask early | fixed: escaped characters are dropped before masking |
| positional filters only for package runners | fixed: pytest, Playwright and `node --test` too, globs excluded |
| redirection target under `tests/` read as a selection | fixed: redirection targets are removed before scanning |
| option values and install arguments read as entries | fixed: make `-C`/`-f` values are removed; a package runner takes only options and `run` before the entry |
| a failing scan tool denies instead of allowing | fixed: tool-presence check, and every scan step allows on error |
| OpenCode helper and asset test not in the packet | evidence: the challenge packet carries `enforce`, `runHook` and the inventory test; rebuilt assets pass, and removing the entry fails the inventory test |
| required lanes and evidence counts | evidence: the repository-required lanes below; counts reconciled in this file |

The challenge on the fixed candidate returned five P2 and no P0 or P1:

| Finding | Disposition |
| --- | --- |
| OpenCode blocks every Bash call when the guard cannot run | fixed: the adapter enforces the guard only when it ran; a new adapter test was red before |
| multi-line quoted message fires | fixed: the mask runs over the whole command |
| `FULL=0` and `FULL=false` clear the guard | fixed: only `FULL=1` opts in |
| an upstream grep failure denies | fixed: the file scan allows unless its last stage found nothing and the stage before ran cleanly |
| an option value read as a positional filter lets a whole run through (`pytest --tb short`) | narrowed: pytest and `node --test` count only path-like words; Playwright, whose positional words are name filters, keeps it as a pinned residual |

The delta pass on those fixes found that the one-word quote mask let the newline placeholder through, so a one-word line inside a multi-line message fired; fixed, with a row red before. It repeated the option-value finding, answered by the narrowing above, and asked for wiring and gate evidence, recorded under Repository checks.

All three passes found new spellings of the same class: a string predicate over shell text misreading one more form. Following the design check for repeated same-class findings, the decision is to keep the deny and stop chasing spellings in the quiet direction. Every finding that blocks a legitimate command, or breaks fail-open, is fixed; a finding that only lets an unusual spelling run is recorded as a residual. The sibling advisory hook reached the same boundary after fifteen rounds of parser fixes.

## Repository checks

- Wiring, read from source: `hooks/hooks.json` and the OpenCode inventory each register the hook once; `make test-repo-gates` runs the suite; the adapter's `runHook` returns a non-`ok` status on a missing script, a timeout, a non-zero exit or unreadable output, and only an `ok` run is enforced.

- `bash skills/skill-extraction-workflow/scripts/check-ccl-skills.sh .`: `ccl_skill_check_interim_ok`. The private alias audit is not configured on this host (`r0_status=public-fallback`), so R0 is pending a maintainer audit.
- `packages/ccl-skills-npm`, rebuilt with `umask 022` (the host default `0077` makes the build reject its own output as unsafe): `node --test test/opencode-hooks.test.mjs test/host-adapters.test.mjs` passes, including the fail-open and deny test for this guard; removing the inventory entry from the built asset fails the inventory test.
