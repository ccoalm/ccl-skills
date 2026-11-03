# Let the reviewer read the diff itself

External review fails or stalls more often than the review itself warrants.
Most failures come from the intake contract around the reviewer (frozen
packets, a restricted packet tool, self-review schemas, chain indices), not
from the reviewing model. This plan adds a lean default runner: the reviewer
runs read-only in the repository, reads `git diff` and surrounding code
itself, and returns findings as text. It improves autonomy and efficiency:
fewer refused or inconclusive review calls, less wall time, and fewer review
rounds spent on packet mechanics.

## Charter and implementation boundary

| Field | Decision |
| --- | --- |
| Purpose | Stop external review from failing on intake mechanics; keep the independent second model that catches P0/P1. |
| Scope | New `skills/code-review/scripts/review_diff.py` runner, its tests, the code-review entry and completion walk pointing daily development at it. The skill-extraction lane, `--mode complete`, and the existing controller stay unchanged in this round. No iterative-program watermark applies. |
| Depth | Generator/tooling change plus routing text. |
| Result classification | Failure/correction: the user reports that Codex and other reviewers keep failing and questions the packet and tool restrictions. |
| Matching analysis | RCA below over review results, Claude transcripts and Codex transcripts on two machines; external benchmark below; paired probes of the lean shape on a real diff. |
| Failure boundary | Do not drop the independent-family rule, the receipt the PR reminder reads, or the evidence file CI checks. Do not let the reviewer write to the repository. |
| Lifecycle impact | Implementation and verification of every change that owes review, debugging of review failures, onboarding on other hosts. Product intent, design and launch acceptance are unchanged. |
| Evidence plan | Produced artifacts first: review result JSON and Codex/Claude session logs on both machines (2026-09-29 to 2026-11-02). Then current controller source, then the external packs' own files (installed copies, read directly). |
| Completion standard | RED tests before the runner exists, GREEN after; `make test`; heavy lane and sanitization; independent review and challenge; a live review through the new runner on a real diff from each family. |

Artifact classification: `gate implementation`; risk route: `shared-gate`.
Baseline `origin/main` on branch `feat/diff-first-review`.

## Root cause

Counted over deduplicated review results (one per packet and mode) and over
the sessions that called the controller.

- Inside Claude sessions the reviewer itself is reliable: Codex attempts were
  conclusive 94% (one machine) and 91% (the other). The leading failures were
  timeouts and `Codex supplied arguments outside the packet tool schema` (36),
  which exists only because the reviewer must read through a restricted
  packet tool.
- Inside Codex sessions, where Codex is the implementer, the controller
  refused far more calls than it ran: of calls that printed a status, 118 were
  `inconclusive` against 66 conclusive, with a median wall time of 2 s. The
  reasons are intake contract errors: missing controller-derived owners in the
  self-review (15), unknown flags such as `--print-candidate` (10), incomplete
  self-review or evidence (16), focus or evidence length limits (11), chain
  index rules (10), packet byte-order rules (6), size budget (4), relative
  `--cwd` (4).
- Counterfactual: removing the intake contract removes every listed refusal
  class; the reviewer-side timeout class remains and is reported as
  `inconclusive`.

Contributing factors: the controller grew to 221 KB with per-client wrappers
of 34–58 KB; each failure class was patched where it appeared, adding inputs
the next agent must get right; the restricted tool exists for boundedness, not
as a security boundary (`references/timeout-auth-and-capabilities.md`).

## Benchmark

Sources read directly: the official Claude `code-review` command, the Codex
system `review-agent` skill, superpowers `requesting-code-review` with its
reviewer template and `review-package` script, and gstack `review` (adversarial
and Codex passes).

| Mechanism | Source | Verdict | Disposition |
| --- | --- | --- | --- |
| Reviewer reads the diff itself (`git diff <merge-base>`) plus surrounding code | all four | M (we freeze a packet; `NO_HITS` for a repository-read reviewer path in daily review @ 68473be) | adopt as the default runner |
| Read-only by host sandbox (`codex exec -s read-only`) or permission mode, not a tool schema | gstack, Codex agent, superpowers (instruction) | W (we restrict tools for boundedness and fail on the restriction) | adopt; keep write tools unavailable |
| Findings as `[P0-3] title — path:line` plus a scenario; `No findings.` when clean | Codex agent | P(功能等价) (our JSON findings carry the same fields) | adopt the text form and parse it |
| Only defects introduced by the change, with a demonstrable scenario | Claude, Codex agent | P | keep |
| Separate validation of each finding before acting | Claude (validation subagents) | P(功能等价) (implementer verifies per development-completion step 3) | unchanged |
| Errors in an optional second opinion never block | gstack | I (an inconclusive lane blocks until remediated) | one run, reported as inconclusive with private diagnostics; the caller reruns; unchanged authority |
| Intent passed as plain text, never the session history | superpowers, Claude | P | keep, as a single `--intent` string |

## Design

`review_diff.py --cwd <repo> --mode review|challenge --intent <text>
--implementer-family <family> [--base <ref>] [--focus <text>] [--timeout <s>]
[--client-order codex,claude] [--out <path>]`

1. Resolve the repository root and the base as `git merge-base HEAD <ref>`;
   the default ref is the remote default branch. Review the working tree
   against it, so uncommitted changes are covered; untracked files are listed
   in the prompt because `git diff` omits them. Every git call switches off
   repository-configured programs (fsmonitor, filter drivers, textconv,
   external diff), because the candidate may carry them.
2. Bind the candidate: a digest of HEAD, `git diff --binary HEAD` and the
   untracked files' contents (listed with `-z`), taken before and after the
   run, with no objects written. A changed digest makes the result
   `inconclusive`.
3. Refuse an implementer family that names no model (`opencode`, `other`).
   Run the first client in `--client-order` whose family differs and whose
   CLI is installed, once. A timeout, launch failure, non-zero exit, empty
   output or interrupt ends the run as `inconclusive`; a failed run's text is
   never a verdict and a timed-out answer is never read.
4. Run it read-only in the repository. Codex: `codex exec -C <repo> -s
   read-only --ephemeral -o <file>` under a private `CODEX_HOME` holding only a
   link to `auth.json`, the user's top-level model keys and the selected
   provider's table, so MCP servers, hooks and plugins never load. Claude:
   `claude -p --tools Read Grep Glob --add-dir <saved diff> --permission-mode
   dontAsk --setting-sources "" --strict-mcp-config --no-session-persistence`:
   no shell (git can write files through `--output`), and settings or MCP
   servers cannot add tools. Both read the diff the runner saved with
   repository git programs off. The prompt names the base, the intent and,
   for challenge, the adversarial brief and optional focus.
5. Parse `[P0-3] title — path:line` lines, each followed by its scenario; an
   answer that is exactly `No findings.` is `passed`; anything else is
   `inconclusive` with the raw text kept.
6. Write the result JSON in the envelope CI reads (`schema_version: 3`,
   `mode`, `status`, `selected_client`) plus findings, reviewer family, base,
   head, candidate tree, worktree_clean, intent digest, elapsed seconds and
   attempts; and the receipt `<git-dir>/ccl-code-review/last-review.json` with
   the fields the PR reminder reads (`head`, `worktree_clean`, `mode`,
   `status`, `recorded_at`). The answer and the stderr tail go to a mode-600
   diagnostics file under the git dir, never into the result. Exit 0 on
   passed, 1 on findings, 2 on inconclusive. The runner is Python 3.9
   compatible.

Plan review (Codex, read-only, 552 s) raised six findings, all confirmed
against source and adopted above: Claude `--allowedTools` adds grants without
removing tools (`claude_review.sh:432`); Codex MCP servers and hooks run
outside `-s read-only` (`codex_review.sh:211`); the CI envelope fields
(`check_review_evidence_present.py:71`); untracked files
(`development-completion.md:27`); dirty-candidate binding
(`development-completion.md:9`); terminal interrupts (`client-routing.md:77`).

Secret handling: the reviewer can read the repository, as in every benchmarked
pack, so a diff-only secret scan no longer bounds what reaches the provider.
The prompt tells the reviewer not to quote secret values. This is an accepted
trade-off for repositories the user already sends to these providers; the
existing controller remains available where that is not acceptable.

Kimi and OpenCode are not in the lean runner this round: their conclusive
rates were 80–85% and 47–52%, and the existing wrappers stay available.

## Rollout

- This round: add the runner and make it the daily-development default in the
  code-review entry and completion walk. The existing controller stays the
  path for the skill-extraction lane, `--mode complete` and callers that need
  it.
- After two weeks: count inconclusive rate, wall time and passes per change
  for each runner from the result files; retire controller features with no
  remaining caller in a separate change.

## Validation

- RED: a test suite for the runner fails before the script exists.
- GREEN: `skills/code-review/scripts/test_review_diff.sh` runs the runner
  against fake `codex` and `claude` executables and covers each property in
  the design and in the review passes below.
- Live: one review through the runner with each family on a real diff.
- `make test`, the heavy lane, public sanitization, `git diff --check`,
  independent review and challenge.

## Review passes

| Pass | Reviewer | Result | Disposition |
| --- | --- | --- | --- |
| Plan review | Codex, read-only, 552 s | six findings | all confirmed and adopted (design above) |
| Review (`evidence/review.json`) | Codex through the runner, 302 s | six findings | all confirmed and fixed with RED tests: Claude shell removed in favor of a saved diff (`git diff --output` writes files), family aliases, a non-zero exit never yields a verdict, exclusive temp files, the bare `No findings.` sentinel, the selected provider table |
| Challenge (`evidence/challenge.json`) | Codex through the runner, 657 s | `inconclusive` (`candidate_changed`: the register row was edited during the run), ten findings | all confirmed and fixed with RED tests: repository git config (fsmonitor, filters, textconv, external diff) switched off; an implementer family that names no model is refused; untracked files seen under `status.showUntrackedFiles=no` and from a subdirectory; a failed attempt's findings survive a later clean answer; bounded pipe draining and process-group cleanup on every exit; a finding needs its scenario; TOML-quoted provider names. The interrupt-after-parse race is fixed by clearing the verdict in the interrupt handler; it has no deterministic test |
| Delta (`evidence/delta-review.json`) | Codex through the runner, 322 s | four findings | three confirmed and fixed with RED tests: the candidate is bound by a digest, because staging it with filters off would write plaintext of filtered files into the object store; a scenario-less header from a failed attempt is not carried; filter drivers are listed by name only. One refuted from source: a reviewer that exited 0 while a descendant held its pipes is answered by its own output, which passes only as the exact `No findings.` sentinel, and Codex's answer comes from its `-o` file |
| Extraction-lane review (`evidence/extraction-review.json`) | Codex through `extraction_review_gate.sh`, 594 s (its first run stopped in 0 s on `egress_denied`: a code comment reading `pass: "…"` matched the secret scan) | seven findings | led to the redesign below. Fixed with RED tests: one reviewer per run, so a timed-out answer and its findings can no longer leak into a later verdict; timed-out answers are never read; answer and stderr go to a private diagnostics file; HEAD and `-z` untracked paths enter the digest; a commented TOML table header is kept. The evidence-gap finding is answered by the live Claude run and the validation record below |
| Extraction-lane challenge (`evidence/extraction-challenge.json`) | Codex through `extraction_review_gate.sh`, 500 s (two earlier runs: every client timed out after 1456 s; then `--timeout` above the controller's 1200 s limit was refused) | five findings | four fixed with RED tests: both reviewers read the saved diff, since repository `diff.external` could empty Codex's own `git diff`; finding text is redacted with the controller's secret patterns; untracked digest entries are framed with length, type and mode; the Codex model and provider are recorded. The family-from-CLI-name limit is documented in the runner reference. The evidence-gap finding is answered by the live probes in the validation record |
| Delta 2 (`evidence/delta-review-2.json`) | Codex through the runner, 209 s | `passed` | the last external pass under the budget |

Live run also caught two defects no fake could: Codex refused to create its
sandbox helper under the system temp dir (the private home moved to the cache
dir), and an empty `diff.external` override broke plain `git diff` (removed;
`--no-ext-diff` covers it).

Every protected property was mutated in the runner and turned the suite red
for the named assertion; two broken mutants (one syntax error, one that
crashed the first case) were redone so the red came from the property.

## Deep self-review after five passes

Five conclusive passes still returned P1 findings, so review paused for a
design check. The 33 findings fall into five classes:

| Class | Passes | Decision |
| --- | --- | --- |
| Reviewer isolation (Claude tools, Codex MCP and hooks, repository git programs) | plan, review, challenge | keep: the boundary the runner exists to hold |
| Failure and fallback handling (non-zero exits, carried findings, timeouts dropping output, interrupts) | review, challenge, delta, extraction review | delete the fallback chain: each round found a new edge in it, Codex alone was conclusive 91–94% of the time, and gstack reports errors without retrying. One run per call; the caller reruns with another order |
| Candidate binding (dirty tree, untracked files, object store, HEAD moves, non-ASCII names) | challenge, delta, extraction review | keep and complete: the receipt claims what was reviewed |
| Hand-written TOML parsing | review, challenge, extraction review | narrow: top-level allowlist plus the selected provider table only |
| Diagnostics (stderr, raw answers) | extraction review | move raw text to a private file; the result keeps structured fields |

## Target-output map

| Owner | Direction | Status | Changed file or reason |
| --- | --- | --- | --- |
| `code-review` | target | updated | `SKILL.md`, `references/diff-first-runner.md`, `references/development-completion.md`, `references/manual-invocation-and-prompts.md` (moved consult note), `scripts/review_diff.py`, `scripts/test_review_diff.sh`, `scripts/AGENTS.md` |
| `skill-extraction-workflow` | sibling lane | unchanged | its lane keeps `extraction_review_gate.sh` over `review_gate.sh` (`SKILL.md` dual-track rule); only its source register gains the impact-chain row. No routing, extraction or validation miss exposed this failure, so no workflow prevention point is owed |
| `feature-risk-router` | upstream | unchanged | high-risk tags still route to `review_gate.sh` through development-completion step 4 |
| `product-rd-workflow` | upstream | unchanged | its completion gate delegates review to `code-review`; no entrypoint named in its text |
| `testing-strategy` | downstream | unchanged | test-layer choice unchanged; the runner suite is a script regression in the code-review lane |
| `hooks/remind-review-covers-head.sh` | downstream | unchanged | the runner writes the fields it reads; case 13 of the runner suite runs the hook against a passed receipt |
| CI `check_review_evidence_present.py` | downstream | unchanged | the runner writes `schema_version: 3`, `mode`, `status`, `selected_client`; case 12 loads a result through the checker |
| `agent-context/session-start.md` | always-on | unchanged | its completion line names `code-review` and `development-completion.md`, not an entrypoint script |
| Kimi / OpenCode wrappers | sibling clients | unchanged | not in the runner; `review_gate.sh` stays available for them |
| `scripts/AGENTS.md` (code-review) | directory contract | updated | the runner's read-only boundary is the one exception to the packet rule |
| External packs (Claude code-review, Codex review-agent, superpowers, gstack) | reference-only | routed | benchmark source only; nothing copied |

## Validation record

| Check | Result |
| --- | --- |
| `bash skills/code-review/scripts/test_review_diff.sh` | ok; each protected property mutated and observed red for its own assertion |
| Live Codex reviews through the runner | four conclusive passes (302–657 s) on earlier candidates of this change |
| Live Codex isolation probe | `codex mcp list` lists two MCP servers under the user's home and none under the runner's private home, which holds only `auth.json`, `config.toml` and Codex's own `tmp` |
| Live Claude boundary probe (`--implementer-family codex --client-order claude`) | conclusive in 66 s; read the saved diff with read tools only; its one P2 (non-UTF-8 diff crash) fixed with a RED test. Not an independent review: the implementer is also Claude |
| Extraction-lane passes through `extraction_review_gate.sh` | review conclusive after a reworded comment cleared an `egress_denied` false positive; challenge: see the passes table |
| `make test-repo-gates` | ok |
| `make test-regressions-fast` | ok on an idle rerun; a date-window census suite failed once when the 30-day window crossed the daylight-saving change while local and UTC dates differed, and passed alone and on the rerun |
| `make test-code-review-1`, `-2` | ok (`test_review_diff.sh` in shard 1) |
| `make test-code-review-abort-leak` | ok inside a private PID namespace (`unshare --user --pid --fork --mount-proc`). On the host it fails identically on the `origin/main` baseline: the session runs under a user service manager, so orphans reparent to it instead of PID 1, which the probe requires; CI runners meet that precondition |
| Heavy lane (`test_check_ccl_regressions.sh --heavy-only`) | ok, 9 suites |
| `check_review_evidence_present.py` against a fetched `origin/main` | ok |
| `python3 scripts/check-public-sanitization.py .`, `git diff --check`, `shared_git_surface_gate.py` | ok |
| Private R0 alias audit | `ccl_skill_check_clean_ok`, `r0_status=private-ok` on the final candidate |

Local environment notes: the default `python3` lacked PyYAML, the system one is
too old for `tarfile` filters, and the shell umask made checked-out files 600.
The lanes ran under a venv with `requirements-test.txt` and umask 022. Two
regression suites (a date-window census and a sync-pointer check) failed once
each while a controller challenge ran in parallel and passed alone and on the
idle rerun.
