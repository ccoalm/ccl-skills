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
  class; the reviewer-side timeout class remains and is handled by one
  fallback to the next family.

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
| Errors in an optional second opinion never block | gstack | I (an inconclusive lane blocks until remediated) | one fallback to the next family, then report inconclusive; unchanged authority |
| Intent passed as plain text, never the session history | superpowers, Claude | P | keep, as a single `--intent` string |

## Design

`review_diff.py --cwd <repo> --mode review|challenge --intent <text>
--implementer-family <family> [--base <ref>] [--focus <text>] [--timeout <s>]
[--client-order codex,claude] [--out <path>]`

1. Resolve the base as `git merge-base HEAD <ref>`; the default ref is the
   remote default branch. Review the working tree against it, so uncommitted
   changes are covered; untracked files are listed in the prompt because
   `git diff` omits them.
2. Bind the candidate: write the working tree, untracked files included, into
   a temporary index and take its tree id before and after the run. A changed
   tree makes the result `inconclusive`.
3. Pick the first client in `--client-order` whose family differs from the
   implementer and whose CLI is installed. On timeout, a launch failure or
   empty output, try the next eligible client once. An interrupt (exit 130,
   137 or 143, or a signal to the runner) is terminal.
4. Run it read-only in the repository. Codex: `codex exec -C <repo> -s
   read-only --ephemeral -o <file>` under a private `CODEX_HOME` holding only a
   link to `auth.json` and the user's top-level model keys, so MCP servers,
   hooks and plugins from the user's home never load. Claude: `claude -p
   --tools Read Grep Glob Bash --allowedTools "Bash(git diff:*)" "Bash(git
   log:*)" "Bash(git show:*)" "Bash(git ls-files:*)" --permission-mode dontAsk
   --setting-sources "" --strict-mcp-config --no-session-persistence`, so no
   write tool exists, other shell commands are denied, and settings or MCP
   servers cannot add tools. The prompt names the base, the intent and, for
   challenge, the adversarial brief and optional focus.
5. Parse `[P0-3] title — path:line` lines; `No findings.` is `passed`;
   anything else is `inconclusive` with the raw text kept.
6. Write the result JSON in the envelope CI reads (`schema_version: 3`,
   `mode`, `status`, `selected_client`) plus findings, reviewer family, base,
   head, candidate tree, worktree_clean, intent digest, elapsed seconds and
   attempts; and the receipt `<git-dir>/ccl-code-review/last-review.json` with
   the fields the PR reminder reads (`head`, `worktree_clean`, `mode`,
   `status`, `recorded_at`). Exit 0 on passed, 1 on findings, 2 on
   inconclusive. The runner is Python 3.9 compatible.

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
- After two weeks: compare inconclusive rate, wall time and passes per change
  between runners with `review_yield_v2`-style counts; retire controller
  features with no remaining caller in a separate change.

## Validation

- RED: a test suite for the runner fails before the script exists.
- GREEN: fake `codex`/`claude` executables on `PATH` cover passed, findings,
  unparseable output, timeout with fallback, same-family skip, missing CLI,
  receipt fields read by the reminder hook, and dirty-tree coverage.
- Live: one review through the runner with each family on a real diff.
- `make test`, the heavy lane, public sanitization, `git diff --check`,
  independent review and challenge.
