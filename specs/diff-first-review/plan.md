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

## Round 2: OpenCode, Kimi and the next reviewer on failure

The first round removed the fallback chain to converge (see the deep
self-review above). Direction since: OpenCode belongs in the runner ahead of
Kimi, and a failed run should move on to the next reviewer; extra model calls
are acceptable. The removal argued that each round found a new edge in the
chain. Those edges came from state shared between attempts (a timed-out answer
read later, findings carried from a failed run). Each attempt now builds its
own private home, reads its answer only when it exited 0, and is discarded
otherwise, so the chain is a plain loop over isolated attempts.

| Field | Decision |
| --- | --- |
| Purpose | Fewer inconclusive daily reviews: when one reviewer fails, another family answers in the same call. |
| Scope | `review_diff.py` clients (OpenCode, Kimi), its try-next loop, its tests and reference, the directory contract. The controller and wrappers stay unchanged. No watermark applies. |
| Depth | Generator/tooling change. |
| Result classification | Failure/correction: the user corrected the round-one decision to drop the fallback and to leave out OpenCode and Kimi. |
| Matching analysis | The deletion was the wrong lever for the user's goal (fewer failed reviews). Its stated cause, shared state between attempts, is removed structurally; the loop's own edges get RED tests: failed answers never carried, interrupt ends the chain, candidate change voids the verdict, same or unknown family skipped. |
| Failure boundary | No write-capable tool, shell or inherited MCP/plugin/hook config for any client; no verdict from a failed, timed-out or interrupted attempt; independence by model family, not by CLI name. |
| Lifecycle impact | Implementation and verification of every change that owes daily review; debugging of review failures. |
| Evidence plan | Live probes of OpenCode 1.19 and Kimi Code 2.2 under the private configs (read tools only, write attempt refused, answer format); the existing wrappers' isolation choices (`opencode_review.sh`, `kimi_review.sh`); then the runner suite. |
| Completion standard | RED tests first, GREEN after; mutation of each new protected property; `make test` lanes; a live review through the runner; review and challenge on this delta. |

Target-output map for this round:

| Owner | Direction | Status | Changed file or reason |
| --- | --- | --- | --- |
| `code-review` | target | updated | `scripts/review_diff.py`, `scripts/test_review_diff.sh`, `references/diff-first-runner.md`, `scripts/AGENTS.md` |
| `skill-extraction-workflow` | sibling lane | updated | source register gains this round's impact-chain row; its lane still runs `extraction_review_gate.sh` |
| Kimi / OpenCode wrappers | sibling clients | unchanged | `review_gate.sh` keeps them for the packet lanes; the runner builds its own private configs |
| `development-completion.md`, `SKILL.md` | upstream text | unchanged | they name the runner, not its client list |
| CI `check_review_evidence_present.py`, PR reminder hook | downstream | unchanged | envelope fields unchanged; `attempts` may now hold several entries and `skipped` is new, neither is read by them |
| `testing-strategy`, `product-rd-workflow`, `feature-risk-router` | upstream | unchanged | no layer, gate or risk-tag change |

Live probes for this round (OpenCode 1.19, Kimi Code 2.2, real models, a
synthetic repository):

| Probe | Result |
| --- | --- |
| OpenCode under the private config | resolved agent tools `read`, `glob`, `grep` only; read the saved diff and a repository file; a write request was refused |
| Kimi Code under the private home | read the diff and a file; a write request was refused (only `Read`, `Glob`, `Grep` exposed); text output bullets the first line and indents the rest, which the runner strips |
| Hostile repository: `opencode.json` allowing everything, a `ccl-review` agent override, `.opencode/plugin` and `.opencode/tool` code | tools stayed read-only, but the plugin file ran with project config disabled, and again with `OPENCODE_PURE=1`; run from a private empty git project with the repository as an outside read-only directory, nothing ran and reads and grep still worked |
| `.opencode/plugin` in a parent directory | ran from a plain project directory; did not run when the project is its own git repository |
| Hostile repository for Kimi: project `mcp.json`, `local.toml` and `config.toml` enabling `Bash` and hooks | untrusted workspace (the runner strips `KIMI_CODE_TRUST_WORKSPACE`): nothing ran and tools stayed read-only; the same run marked trusted started the project MCP server |

The suite's new cases failed on the previous runner and pass on the candidate.
Removing each protected line (try-next, failed-answer isolation, interrupt
stop, order, OpenCode project-config, pure, deny-all, agent, private project,
unknown and same family, setup-failure guard, Kimi tool allowlist, trust strip,
bullet strip, table filter) turned its own assertion red.

Passes on this round:

| Pass | Reviewer | Result | Disposition |
| --- | --- | --- | --- |
| Runner review (`review_diff.py`) | Codex, 330 s | three findings; the run itself voided by a commit made during it, answer read from its diagnostics | Kimi alias family, multi-block answers and unguarded discovery fixed with RED tests |
| Extraction review | Codex through `extraction_review_gate.sh`, 413 s | two P1, three P2 | provider/model order, Kimi alias, config snapshot and discovery fixed with RED tests; live probe evidence recorded in `evidence/round2-live-probes.md` |
| Extraction challenge | Codex, 366 s | two P1, one P2, all reviewer-family inference again | third round on one class, so the capability was narrowed: family only from the model id that runs, Kimi config parsed once with `tomllib`, unknown skipped |
| Live runner review through OpenCode | DeepSeek, 639 s | three P2 | Kimi top-level keys, dotted tables and a preamble before a clean answer fixed with RED tests |
| Live runner review through Kimi | Kimi, 832 s | unparseable: text mode printed the narration between tool calls before `No findings.` | Kimi read through stream-json, final message only; the prompt says the final message is parsed |
| Delta pass on the post-challenge fixes (last reviewer call) | Codex through `extraction_review_gate.sh`, 398 s | two P1, one P2 | `kimi`-type provider counted only on Moonshot's endpoint; a cut stream voids the answer; validation evidence recorded below |
| Live runner review through Kimi, stream-json | Kimi, 796 s, conclusive | one P2, one P3 | config shape checks and string-aware trailing-comma removal fixed with RED tests |

Replay against the packet controller on eight historical changes with known
defects, scored blind: `evidence/replay.md`. Review alone catches fewer known
defects in diff mode than packet review (7–8 against 12 of 27), challenge
alone catches more (11 against 9), and review then challenge ties at 12. The
concern walk and an inlined diff did not close the review gap.

The review brief: a replay arm with a brief that keeps unconfirmed suspicions
caught 15 of 30 known defects in review against 8 for the first brief and 14
for packet review, with less noise than packet review; it is now the review
brief (`evidence/replay.md`, "The review brief").

The brief change had its own review and challenge through the runner, both
conclusive with no findings (`evidence/brief-review.json`,
`evidence/brief-challenge.json`).

## Round 3: runner structure and terminal output

`review_diff.py` grew to one 765-line module that mixes six jobs: safe git and
candidate binding, the prompt, four reviewer clients with their private-home
builders and config readers, process control, answer parsing and redaction,
and result writing. Safe git state is a module-level list that
`neutralize_filters` mutates. A run prints nothing until it ends, which can
take an hour when every reviewer times out, and an inconclusive result
gives a reason code but no next step.

| Field | Decision |
| --- | --- |
| Purpose | People and agents running a daily review see which reviewer is working and why it moved on, and get one next step for every inconclusive result. A maintainer can change one reviewer client without reading the attempt loop. |
| Scope | `review_diff.py` split into the review flow and a new `review_diff_clients.py`; progress and a summary on stderr; exits that misreport the verdict; the runner suite; `references/diff-first-runner.md`; `scripts/AGENTS.md`. The controller, the wrappers and the review brief are out of scope. No iterative-program watermark applies. |
| Depth | Generator/tooling change. |
| Result classification | Failure/correction: the user asked for a clear architecture and domain model, clean code and a good terminal experience, judging the runner short of that. |
| Matching analysis | Each earlier round added a client or an edge fix where the code already was: nothing in the module or its directory contract named a boundary between policy and client mechanics, and no case looked at what a person sees during a run. Prevention: the two-module boundary with one client interface, a directory-contract line naming it, and suite cases that pin stderr and exit codes. Seams the suite reaches into: `main`, `reviewer_family`, `private_opencode_root`. |
| Failure boundary | Unchanged: the result envelope and its field order, the receipt, stdout, exit codes, prompt text, each client's argv, environment and private home, when each client reads its config, family rules and the try-next semantics. Any difference the differential run finds is a defect, not a design choice. Declared exceptions, all defect fixes for exits that misreport the verdict: a git failure before the review (not a repository, unknown base), a result that cannot be written and any unexpected error exit 2 with a message instead of a traceback and exit 1, and a closed stdout or stderr no longer turns the verdict's exit code into 120. |
| Lifecycle impact | Every daily review and challenge; debugging review failures. |
| Evidence plan | Differential run of the old and new runner over every suite scenario; the mutation walk ported to the new code; the suite; a live review through the new runner. |
| Completion standard | Suite assertions unchanged and green; the new output cases RED on the old runner and green after; differential identical; each ported mutant red on its own assertion; `make test` lanes; review and challenge through the runner. |

Owner skills applied: `python-service-architecture` (module boundary, state
ownership, error mapping in one place), `python-service-dev`,
`terminal-cli-dev` and `product-ui-ux-design` (stdout/stderr contract,
progress, recovery copy), `testing-strategy` (differential proof, killing
mutations), `code-review`. Visible surface: yes, stderr only.

### Domain model

| Concept | Where | Owns | Invariant |
| --- | --- | --- | --- |
| `Git` | `review_diff.py` | every git call: fsmonitor off, filter drivers replaced by pass-through, no external diff or textconv | no git call bypasses it; replaces the mutable `GIT_SAFETY` global |
| `Candidate` | `review_diff.py` | repository root, git dir, head, base, clean flag, untracked files, digest; saving the diff; detecting a change | bound once before the first attempt; a verdict is void when the digest moves |
| `Client` | `review_diff_clients.py`, one class per CLI | `snapshot()` reads the config that decides the family, once (OpenCode, Kimi); `run()` builds the private home, argv and environment, launches, extracts the answer and deletes the home | OpenCode and Kimi launch with the snapshot that judged eligibility; Codex still reads its config only when it launches; judging the answer is not the client's job |
| `Reviewer` | `review_diff_clients.py` | an eligible client, its family, model and snapshot | family by model id for OpenCode and Kimi, by CLI for Codex and Claude |
| `Run` | `review_diff_clients.py` | one process: outcome (`ran`, `timeout`, `interrupted`, `missing`), exit code, answer, stderr | a timed-out or interrupted run carries no answer; a failed exit keeps its text for the private diagnostics |
| `Attempt` | `review_diff.py` | one attempt's record in the result | holds only client and status when interrupted before the run returned |
| `Review` | `review_diff.py` | the outcome of the attempts: status, findings, reason, attempts, selected client and family | the reason is the last attempt's, or `no_eligible_reviewer` or `implementer_family_ambiguous` when none ran |
| `judge()` | `review_diff.py` | Run → status, findings, reason | only a clean exit with a non-empty, parseable answer yields a status |
| `Progress` | `review_diff.py` | stderr lines | never raises and never writes to stdout, so a closed or missing stderr changes neither the verdict nor its exit code |

`review_diff.py` loads `review_diff_clients.py` by path, as it already loads
the controller's secret patterns, so a module of that name in the caller's
directory or `sys.path` cannot stand in for it. The dependency points one way:
flow to clients; clients know nothing of verdicts or results.

Two modules, split by reason to change: clients change with CLI releases, the
flow with review policy. Rejected: one file with classes (keeps CLI churn and
policy in one place); a package with a module per client (an `AGENTS.md` and
import plumbing for four classes, with no current need).

### Terminal output

Users are an agent's shell tool, often under a command timeout, and a person
watching a terminal. stdout stays the machine contract: one JSON line, then
one line per finding. stderr gets plain ASCII lines prefixed with the mode, no
color, cursor movement or carriage returns, so pipes, CI logs, `NO_COLOR`,
`TERM=dumb` and captured tool output read the same.

| State | stderr |
| --- | --- |
| start | `review: 3 files changed against 1b2c3d4, head 3f2a1c9, uncommitted edits included` |
| skipped clients | `review: skipped claude (same family as the implementer), kimi (not installed)` |
| attempt starts | `review: codex reviewing (timeout 900s)`; OpenCode and Kimi also name their model |
| attempt fails | `review: codex timed out after 15m00s; trying opencode` |
| attempt answers | `review: opencode answered in 6m52s` |
| findings | `review: findings: 2 (1 P1, 1 P2) from opencode in 21m53s`, then `  result: <path>` |
| passed | `review: passed, no findings from codex in 3m02s`, then `  result: <path>` |
| inconclusive | `review: inconclusive: <plain reason>`, then `  next: <action>`, `  result: <path>` and, when written, `  diagnostics: <path> (private)` |
| result not written | `review: not recorded: <error>`, then `  next: check that the --out directory and the repository's git dir are writable, then rerun`; exit 2 |
| unexpected error | the traceback, then `review_diff: internal error, not a verdict`; exit 2 |

| Reason | Next step |
| --- | --- |
| `no_eligible_reviewer` | install a reviewer CLI of another family, or name one in `--client-order` (the skipped list says why each was skipped) |
| `implementer_family_ambiguous` | pass the family of the model that wrote the change |
| `reviewer_timeout` | rerun with a larger `--timeout`, or review a smaller change |
| `reviewer_failed`, `reviewer_launch_failed`, `empty_answer`, `unparseable_answer` | with a diagnostics file: read it, fix the cause (often login, quota or config) and rerun; without one, the reviewer printed nothing: check its login, quota and model config, then rerun |
| `operator_interrupt` | rerun when ready; nothing was recorded as reviewed |
| `candidate_changed` | let the working tree settle and rerun |
| git failure before the review | `review: not run: <git's error line>`, then `  next: check that --cwd is inside a git repository and --base names a commit in it`; exit 2, no result |

A consumer that closes stdout or stderr before reading it gets the same
verdict exit code: the result and receipt are already written. Today the
final flush fails with `BrokenPipeError` and the runner exits 120 whatever the
verdict. When stderr is closed at start, Python sets `sys.stderr` to `None`
and `print(file=None)` writes to stdout, so progress checks for that rather
than corrupting the machine-readable lines.

### Tests

| Case | Layer | Before |
| --- | --- | --- |
| existing suite (fake CLIs, real git) | script integration | pass; assertions unchanged, seams point at the clients module |
| progress for a try-next run: start, skipped, each attempt, final | script integration | fail: no stderr |
| summary and next step for each inconclusive reason, with and without a diagnostics file | script integration | fail |
| stdout: JSON line and finding lines | script integration | pass, now pinned |
| challenge mode with `--focus`: the challenge brief and the focus reach the reviewer, the review brief does not | script integration | pass, now pinned (no case ran challenge mode) |
| stdout closed early; stderr a closed pipe; stderr closed at start: verdict exit code, stdout unchanged, result and receipt written | script integration | fail |
| not a git repository, unknown `--base`: exit 2, one line, no traceback | script integration | fail |
| result directory not writable: exit 2, `not recorded`, no traceback | script integration | fail |
| an unexpected error inside the run: exit 2, `internal error, not a verdict` | script integration | fail (no entry guard) |
| a `review_diff_clients.py` in the caller's directory does not replace the real one | script integration | fail (no clients module) |
| old and new runner over every suite scenario plus a challenge run, with hostile ambient variables (`OPENCODE_CONFIG_CONTENT`, `OPENCODE_PERMISSION`, `KIMI_CODE_TRUST_WORKSPACE` and the like): result JSON, receipt, stdout, and each fake client's argv, environment, prompt, generated config and auth links equal after normalizing times and temp paths | scratch differential, not committed | — |
| each protected property mutated in the new code | scratch mutation walk | red on its own assertion |

Python 3.9: both modules compile and the suite runs under 3.9 except the Kimi
cases, which need `tomllib` (3.11).

Plan review: Codex through the runner, 454 s, seven P2 findings, all confirmed
and adopted above: failed-run text kept for diagnostics, Codex's config read at
launch, the exit-code fixes declared as exceptions, next steps that depend on
whether a diagnostics file exists, launch inputs and challenge prompts in the
differential, and the closed-stderr cases (checked: a closed stderr pipe turns
any verdict into exit 120, and a stderr closed at start makes `sys.stderr`
`None`).

Implementation boundary: baseline this section; mechanics owners
`python-service-dev` and `terminal-cli-dev`, design owner
`product-ui-ux-design` (the terminal output above is its brief), all loaded
before code. Risk tags `shared-gate` and `visible-ui`; `security-review` not
applicable, because no trust boundary, input surface or sink changes and
progress never prints answer or stderr text. Delegation: local, one coupled
slice; only the read-only replay judges run as agents.

### Round 3 evidence

| Check | Result |
| --- | --- |
| New suite cases on the previous runner | 33 assertions RED: progress, summaries and next steps, closed stdout, git failure, unwritable result, unexpected error, module shadowing. The stdout, challenge-prompt, closed-stderr and Codex bare-key pins pass on both runners |
| `bash skills/code-review/scripts/test_review_diff.sh` on the candidate | ok |
| Differential: a copy of the suite run once per runner with pinned commit dates, hostile `OPENCODE_CONFIG_CONTENT`, `OPENCODE_PERMISSION`, `OPENCODE_CONFIG_DIR` and `KIMI_CODE_TRUST_WORKSPACE`, and every fake client dumping its whole environment | 823 of 829 artifacts identical after normalizing times and temp paths: result envelopes in field order, receipts, stdout, and each client's argv, environment, prompt, private config and auth link. The six others are harness artifacts: one case commits a script containing the work-dir path, and diagnostics files of runs that share a repository collide within the same second |
| Mutation walk on the candidate | control clean; 67 of 67 protected properties red on their own assertion. Two needed more: the Codex config's bare-key guard is reachable only through Codex since Kimi's config is parsed first, so a Codex case now pins it; carrying every Kimi table is refused first by the carried-subset check, and with that check removed only `kimi-isolation` turns red |
| Python 3.9.25 | the suite passes except the Kimi cases and the lines naming Kimi as skipped, as expected without `tomllib` |

Passes on this round:

| Pass | Reviewer | Result | Disposition |
| --- | --- | --- | --- |
| Runner review (`evidence/round3-review.json`), candidate 26fb191 | Codex through the new runner, 370 s | one P2: with stdout closed at start, `sys.stdout` is `None` and the final flush made a recorded verdict exit 2 | confirmed and fixed with a RED case (`noout-rc`) |
| Extraction-lane review, candidate 26fb191 | Codex through `extraction_review_gate.sh`, 393 s | inconclusive: `tool_boundary_violation` (Codex sent arguments outside the packet tool schema) | not a result; rerun on the fixed candidate |
| Runner challenge (`evidence/round3-challenge.json`), candidate 79fe8af | Codex through the new runner, 512 s | one P2: the clients module loaded at import, outside the exit-2 guard, so a partial install exited 1 even for `--help` | confirmed and fixed with a RED case (`partial-rc`) |
| Extraction-lane review rerun (`evidence/round3-extraction-review.json`), candidate 79fe8af | Codex through `extraction_review_gate.sh`, 426 s | one P2 evidence gap: no current-candidate `make test`, heavy, sanitization or challenge results | accepted: those results are recorded in the validation table below on the final candidate |
| Runner delta (`evidence/round3-delta.json`), the challenge fix on 285df3a | Codex through the new runner, 83 s | passed | the last runner pass under the daily budget |
| Extraction-lane challenge (`evidence/round3-extraction-challenge.json`), candidate 285df3a | Codex through `extraction_review_gate.sh`, 320 s (a first call was refused before any review: its focus exceeded the controller's 1000-character limit) | passed | none needed |

Owner lenses: decided against, from the repeat and service-repository replay in
`evidence/replay.md` ("Repeat runs, owner lenses and other repositories"):
paired by case, lenses tied or traded wins with the plain brief inside one
arm's run-to-run spread.

Validation on the final candidate:

| Check | Result |
| --- | --- |
| `make test-code-review-1`, `-2` | ok |
| `make test-code-review-abort-leak` | ok inside a private PID namespace |
| `make test-repo-gates` | ok after the register gained a row for the review fixes: the impact-chain gate scopes rows per round, and those fixes landed after the round's first row |
| `make test-regressions-fast` | `test_governing_chain_diff.sh` failed intermittently here and on `origin/main` (one run in eight there), a different case each time, with the expected reason visible in the tool's output. Cause: the suite piped its output into `grep -q` under `pipefail`, so a writer still holding the pipe after the match died of SIGPIPE; reproduced in a fresh bash and fixed with here-strings. `test_reference_access_census.sh` carries the same pattern and is left for its own change |
| Heavy lane | two suites failed once each while other sessions held the host at load 11 to 25 (`test_check_ccl_r0_status.sh`, then `test_pinned_phrase_mutation_walk.sh`); both pass alone |
| `python3 scripts/check-public-sanitization.py .`, `git diff --check`, `shared_git_surface_gate.py`, `check_review_evidence_present.py` against fetched `origin/main` | ok |
| Private R0 alias audit | pending: the audit host is reached through a local tunnel that was down; the public fallback reports `ccl_skill_check_interim_ok`, which allows a push but not a clean-landing claim |

Not changed, noted: finding titles reach stdout as the reviewer wrote them, as
before this round; a title carrying terminal control sequences would reach a
terminal that prints stdout raw.
