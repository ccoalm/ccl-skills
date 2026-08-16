# 023 — Preserve and classify OpenCode reviewer timeout evidence

## Artifact classification and entry state

`gate implementation` under
`product-rd-workflow/references/shared-gate-artifact-classification.md`.

The changed wrapper decides whether an independent review is usable and what
evidence survives an inconclusive lane, so this is a shared deterministic gate
change rather than an ordinary shell-script fix.

- Entry state: `local status` on
  `worktree-opencode-timeout-evidence`, based on `dev@673fece`.
- Risk tags: `shared-gate`, `external-integration`, and the change-triggered arm
  of `security-review` because failure evidence may contain reviewer output.
- Visible surface: no UI.
- Stop conditions: do not weaken fail-closed review semantics, automatically
  retry a stalled provider call, switch reviewer/provider, retain candidate
  prompts or diffs without an explicit bounded diagnostic contract, or include
  the separate Claude `terminal_slash_commands` compatibility defect.
- Landing state requested by the user: local implementation and verification
  only. Commit, push, merge, release, installation, and cleanup are separately
  authorized and remain out of scope.

## Extraction charter

| Field | Required answer |
| --- | --- |
| Purpose | Make a native owner-skill reviewer stall immediately diagnosable instead of collapsing it into an evidence-free `review_timeout`, while preserving fail-closed behavior. |
| Scope | The OpenCode review wrapper, its focused deterministic tests, and only the stable contract text needed to describe the new failure evidence. Sibling check: Claude's `terminal_slash_commands` incompatibility is recorded but excluded; Kimi/Codex/Claude wrappers are unchanged unless a shared helper is proven necessary. No project-local `covered-through` watermark exists for this new slice; this plan is the round authority. |
| Depth | Generator/tooling change: executable shared-gate wrapper plus RED/GREEN regression coverage. |
| Root cause | OpenCode 1.18.15 with a DeepSeek v4 Pro reviewer can stall in the native multi-owner-skill/profile call path until the outer timeout returns 124; the wrapper then deletes the run artifacts and reports only a generic timeout. Provider-internal causality is not locally observable and remains unknown. |
| RCA analysis | Widened below: the stream stall is the immediate external-interaction failure; unconditional cleanup and coarse classification are independent local control failures. The fix targets the two controllable wrapper failures and does not pretend to repair the opaque provider/runtime interaction. |
| Failure mode analysis | A future small or large review can hang identically; operators may waste time changing npm, auth, diff size, or timeout; retained raw artifacts could leak candidate content if preservation is unbounded; an over-specific reason could misclassify ordinary pre-init timeouts. |
| Lifecycle impact | Debugging, testing, shared review acceptance, and maintainer triage. Product intent, UI/UX, launch, deployment, and end-user runtime behavior are unaffected. |
| Evidence plan | Produced artifacts first: the preserved diagnostic copies and comparison results described by the user are the source category establishing the failure boundary, but their restricted raw paths/content are not copied into this distributed repository. Then inspect the current wrapper, parser/contract, focused wrapper tests, and nearest `AGENTS.md`; compare sibling cleanup/classification only to decide whether generalization is necessary. Use synthetic fixtures for committed tests. |
| Completion standard | A deterministic test is RED on `dev@673fece` and GREEN after the fix; success-path cleanup still passes; timeout evidence is bounded and permission-safe; generic pre-init timeout is not overclassified; focused and repository gates pass; independent review and adversarial challenge are recorded truthfully. Direct Claude CLI evidence may satisfy the independent review/challenge rows only when preserved and explicitly labelled as read-only/no-tools direct review, never as formal wrapper-gate success. |

Process deviation: a bounded symbol/file inventory was run before this charter was
persisted. No candidate file had been edited. This charter governs all subsequent
deep source reads and implementation.

## Source register

| Source group | Inclusion / minimum depth | Owner | Status | Completion evidence |
| --- | --- | --- | --- | --- |
| Produced diagnostic artifacts | Use the user's A/B conclusions; do not copy restricted raw logs, prompts, repository paths, or provider data into the shared tree | `defect-diagnosis` | `deep-read` | Immediate trigger, rejected hypotheses, cleanup gap, and unknown provider boundary are recorded above |
| OpenCode wrapper | Read cleanup trap, invocation, timeout, event/session/log handling, and emitted result paths | `code-review` | `deep-read` | `run_review_and_judge` deleted four per-run captures before returning and the EXIT trap deleted the isolated XDG runtime; `classify_run_failure` mapped every exit 124 to generic `review_timeout` |
| Focused tests | Read timeout, retry, cleanup, and native-skill fixtures; add a failing-first synthetic case | `testing-strategy` | `deep-read` | `test_opencode_review_retry.sh` produced four expected RED failures before implementation and now ends `opencode_review_retry_tests_ok` |
| Stable contracts | Read `SKILL.md`, timeout reference, and scripts `AGENTS.md`; edit only if executable behavior would otherwise be undocumented | `skill-extraction-workflow` | `deep-read` | Updated the timeout operational contract and local scripts contract; routing and `SKILL.md` hard rules are unchanged |
| Sibling wrappers | Inspect only cleanup and failure-evidence patterns needed for a no-sibling/generalize decision | `code-review` | `read` | No sibling change: wrapper transports and artifact shapes differ; the Claude compatibility defect is explicitly excluded rather than generalized into this fix |
| Claude compatibility defect | Separate `terminal_slash_commands` fail-closed issue | `code-review` | `excluded` | User explicitly bounded it out of this branch |

## Acceptance and test matrix

| ID | Acceptance point | Lowest sufficient evidence |
| --- | --- | --- |
| A1 | A timed-out owner-aware OpenCode review that has entered the native skill/profile stream remains inconclusive and emits a stable, more specific reason plus bounded diagnostic evidence. | Synthetic wrapper integration test, RED then GREEN |
| A2 | An ordinary timeout without proof of native skill/profile stream progress remains the generic timeout class. | Negative synthetic wrapper test |
| A3 | The default portable timeout summary is bounded and contains no raw text. Raw events/export/logs survive only under an explicit private diagnostic directory, use restrictive permissions, exclude credential bindings, and carry a sensitivity/retention marker. | Filesystem assertions plus security self-review |
| A4 | Successful and non-timeout paths retain their existing cleanup and result semantics. | Existing wrapper suite plus focused regression assertions |
| A5 | No automatic provider switch, timeout increase, retry, or conversion of an inconclusive review to pass is introduced. | Diff self-review and gate tests |
| A6 | Independent review/challenge evidence is labelled by the path actually used; direct Claude CLI output cannot claim formal wrapper-gate success. | Persisted review records and closeout wording check |

Test layers:

| Layer | Applies | Reason |
| --- | --- | --- |
| Unit / shell fixture | yes | Classification, cleanup, permissions, and bounded evidence are deterministic wrapper behavior |
| Contract / gate | yes | Stable reason and fail-closed semantics are consumed by the review gate |
| Live provider smoke | manual evidence only | Reproduces the external stream interaction but is nondeterministic and cannot prove the local fix |
| UI / browser / device E2E | no | No visible or client runtime surface |
| Release/deploy smoke | no | No release or installation is authorized |

## RCA and control map

| Contributing factor | Counterfactual | Control in this slice |
| --- | --- | --- |
| Native multi-owner-skill/profile stream can stall after the main review starts | Removing owner-skill/profile loading makes the same diff pass, so this is the observed trigger; provider-internal cause remains unknown | Detect only evidence-backed progress shape; do not claim provider repair |
| Timeout cleanup removes events/session/log | The stall still occurs, but operators can diagnose it without a temporary wrapper copy if evidence survives | Preserve a bounded, permission-safe diagnostic summary on failure |
| Generic `review_timeout` collapses pre-init and post-init stalls | The stall still occurs, but the next action is no longer misleading if the states are distinct | Stable reason classification with a negative pre-init case |
| Existing tests do not fail when timeout evidence disappears | Runtime behavior remains broken until a human instruments it | Failing-first synthetic regression in the normal focused suite |

## Structural minimality

| New concept | Current acceptance point / constraint | Simpler alternative | Decision |
| --- | --- | --- | --- |
| Bounded timeout diagnostic summary | A1/A3 and the observed cleanup gap | Keep all raw temp artifacts by default | Keep bounded summary; reject unbounded retention |
| Opt-in private raw diagnostic child | A1/A3 and the locally opaque provider boundary | Always retain the whole runtime or require a patched diagnostic wrapper | Keep curated timeout-only copies; caller owns the parent and retention |
| Specific post-init/native-skill stall reason | A1/A2 | Rename every timeout | Keep only when the wrapper has positive evidence; otherwise preserve generic reason |
| New provider retry/fallback | none | Existing fail-closed stop | Do not add |

## Verification and review

Behavioral evidence so far:

| Row | Result | Evidence |
| --- | --- | --- |
| RED baseline | passed | With the new assertions and the unmodified wrapper, the focused suite reported four failures: precise native-stream reason, bounded summary, explicit artifact retention, and successful parsing of the new option |
| GREEN focused wrapper | passed | `bash skills/code-review/scripts/test_opencode_review_retry.sh` → `opencode_review_retry_tests_ok`, including empty/invalid stream negatives and success cleanup |
| Parser | passed | `bash skills/code-review/scripts/test_parse_opencode_review.sh` → `ALL PASS` |
| Concurrency/isolation | passed | `bash skills/code-review/scripts/test_opencode_review_concurrency.sh` → `opencode_review_concurrency_tests_ok` |
| Cross-wrapper regression | passed | `bash skills/code-review/scripts/test_cli_review_wrappers.sh` → `cli_review_wrapper_tests_ok` |
| Gate semantics | passed | `bash skills/code-review/scripts/test_review_gate.sh` → `review_gate_tests_ok` |
| Client contract | passed | `python3 skills/code-review/scripts/test_review_client_compat.py` → 13 tests, `OK` |
| Repository contracts | passed | agent-contract coverage, public sanitization, Markdown links, spec references, and `git diff --check` all green |
| R0 | passed | `check-ccl-skills.sh .` → `alias_audit_ok`, `r0_status=private-ok`, `ccl_skill_check_clean_ok` |

The first combined focused-suite runner exceeded its 300-second context-mode RPC
limit and returned no usable per-command result. Its surviving child was allowed
to exit, no matching test processes remained, and every command was then rerun
separately to a readable terminal marker; the combined run is not counted above.

Independent review round 1 used Claude CLI 2.1.233 directly with safe mode,
empty setting sources/MCP/tools, plan permission mode, no session persistence,
structured output, and no repository tools. The raw JSON remains in a private
temporary evidence directory and is not copied into this repository. This row is
`direct-read-only review: findings`, not formal wrapper-gate success.

| Finding | Disposition |
| --- | --- |
| P1 sensitive diagnostic child could survive if result enrichment failed before its name was emitted | fixed: keep the internal full path, validate its generated prefix, delete the child on enrichment failure, and exercise the failure with a scoped Python test double |
| P2 any JSON object could overclassify a timeout as native-skill stream progress | fixed: require session id plus a non-empty structured stream `part.type`; empty, non-JSON, and session-only fixtures remain generic |
| P2 credential-exclusion assertion checked only the diagnostic root | fixed: recursive `auth.json`, credential sentinel, and symlink absence assertions |
| P2 event scan bounded parsed-object count rather than bytes read | fixed: read at most 1 MiB, inspect at most 1000 decoded lines, and report truncation |

Direct review round 2 returned four findings, all fixed: the manifest now claims
only that credential *files* are excluded and warns that log/stderr content may
still contain secrets; raw retention has per-file, aggregate-byte, and log-count
limits with explicit skip flags; the Bash 3.2 test environment is explicitly
exported/unset; and the summary contract is documented as best effort.

Direct review round 3 returned four P2 findings, all fixed: the oversized-log
fixture now allocates through bounded `head` rather than millions of `awk`
calls; contract wording matches structured stream-part evidence and whole-file
skip behavior; and diagnostic children are registered immediately, removed on
signal until their directory name is successfully written to stdout, with a
signal-during-copy firing-path test. An implementer follow-up also moved the
retention commit after successful stdout emission and masks signals only across
that final atomic handoff, closing the narrower post-enrichment/pre-output
window.

Direct review round 4 returned two P1 and two P2 findings. The two stated
multi-attempt timeout paths are unreachable under the current retry predicate,
which accepts only `unparseable_findings`, but the implementation no longer
depends on that invariant: a new retention replaces any prior unreported child,
and final retention is committed only when the emitted JSON names that exact
child. SIGPIPE now reaches the failed-write cleanup path, and failed manifest
read-back reports conservative truncation flags. Focused fixtures cover signal
during copy, closed stdout, and read-back failure. Implementer self-review also
bounded log-tree entry traversal and replaced destination-derived partial names
with random private temporary files. Round 9 later removed the separate manifest
read-back entirely, so that superseded fixture is no longer part of the suite.

Direct review round 5 returned three P2 findings, all fixed: a single rotating
or unreadable runtime log now marks a skip without destroying already copied
evidence; an explicit diagnostic parent must be owned by the invoking user and
must not be group/world-writable; and the complete `diagnostic_artifacts`
receipt surface is documented. Focused fixtures exercise both new failure
paths.

Direct review round 6 returned two P2 findings, both fixed: short unpadded octal
mode output is normalized before group/other write-bit inspection, including a
synthetic root-equivalent `70` fixture; and a legacy no-owner run that emits a
valid structured stream part now proves the owner-skill-count guard keeps the
generic timeout classification.

Direct review round 7 returned three P2 findings. Trailing slashes are now
removed before the non-symlink diagnostic-parent check and covered by a fixture.
The suggested profile-only owner classification was rejected because the
existing native binding contract fails that shape before inference; the output
field was renamed to the exact measured fact,
`native_owner_skills_requested`. The timeout reason and additive receipts now
flow through an end-to-end gate fallback fixture and a client-attempt contract
test. The first gate assertion incorrectly expected same-family Codex to run;
it was corrected to the actual fail-closed terminal state and the full gate
suite passed.

Direct review round 8 returned one P1 and two P2 findings, all fixed: permission
fixtures use a real GNU-first/BSD-fallback `stat` probe; diagnostic-child
creation and registration are one shell assignment command so a pending signal
cannot land between them; and the client contract test roots its `review_gate`
import at the script directory. Both direct invocation and unittest discovery
of the client suite pass.

Direct review round 9 returned four P2 findings. The proposed 124/quota conflict
is unreachable because raw 124 is classified before stderr signatures, but the
native reason and retention paths now also require the classified `timeout`
code. The diagnostic parent is revalidated immediately before `mktemp`, with a
firing-path that changes its observed mode after the review starts. One manifest
writer now produces both the retained booleans and a private handoff file read
with shell builtins, eliminating divergent Python read-backs. The contract now
warns that SIGKILL or host crash can strand an unnamed child and assigns parent
sweeping to the caller.

Review round 10 used Kimi K3 directly through its OpenAI-compatible API with no
tools and a frozen candidate SHA-256. The formal Kimi wrapper returned
`packet_too_large_for_inline`, while direct Kimi CLI startup independently
failed in its file watcher with `EMFILE`; neither inconclusive attempt is
reported as gate success. The API review returned one major and two minor
findings. The major `head -c` portability claim was rejected with first-hand
macOS evidence: `/usr/bin/head -c 1 /dev/null` succeeds and the installed BSD
manual documents `head [-c bytes]`. The signal-scope minor was accepted: ignored
signals are now confined to a subshell containing only the final builtin
`printf`, so parent cleanup retains normal signal handling. The final minor
explicitly required no change because umask 077, a mode-0700 parent, and
mode-0600 files already provide the stated protection. Raw provider output is
kept only in the private review evidence directory. A post-fix Kimi review and
the separate adversarial challenge remain pending.

The first post-fix Kimi review repeated the same blocking `head -c` claim; it
was again rejected because it contradicts the installed macOS executable and
manual. Its extended-ACL major was accepted: diagnostic-parent validation now
rejects an access-mode field carrying `+`, both before inference and on the
immediate pre-retention recheck, with firing-path fixtures for both stages. Its
minor test gap was also accepted: a generic pre-stream timeout with an explicit
diagnostic parent now proves the generic reason, bounded summary, and retained
artifact receipt together. A new post-fix Kimi review and the separate
adversarial challenge remain pending.

The next Kimi review passed the ACL-hardened candidate with no blocking or major
findings. Its two minors noted setgid group inheritance despite a mode-0700
child and SELinux labels that are not POSIX ACL grants; neither creates access
to the mode-0700 child or mode-0600 files. The same-SHA adversarial challenge
then found a real major: the signal mask ended after stdout but before the
parent committed `TIMEOUT_ARTIFACT_REPORTED`, so a signal in that gap could
delete an already reported child and emit a second JSON line. The handoff now
masks signals in the parent across both the builtin write and commit, installs a
silent post-handoff signal cleanup before unmasking, and has a DEBUG-trap
firing-path that sends TERM exactly at the commit assignment. The challenge's
receipt minor was also accepted: timeout-enrichment failure now adds the minimal
`requested:true`, `retained:false`, `error:retention_failed` receipt after
deleting the child. Its ACL portability minor remains an explicit limitation of
the standard C-locale `ls` access-mode marker rather than a claim that arbitrary
nonstandard `ls` builds can prove ACL absence. A final exact-candidate Kimi
review and challenge were then run as recorded below.

The first final-SHA Kimi review passed with no blocking or major findings. Its
fallback-receipt minor was accepted: if timeout-summary enrichment fails, the
minimal receipt now derives `requested` from the actual `--diagnostic-dir`
state, reports `retention_failed` only for a requested retention, and has
fixtures for both requested and unrequested paths. Its glob-pattern concern was
rejected because the caller-controlled prefix is already quoted and only the
generated suffix is a pattern. The same-SHA challenge repeated the disproven
macOS `head -c` claim without reconciling the target executable and manual; it
was rejected again. Its double-discard minor was removed by leaving failed
stdout cleanup solely to the existing EXIT cleanup path. A final post-fix Kimi
review and challenge were run against frozen SHA-256
`3a502ade83de2d4fabf6af949f75d6e088200c5b1457797a1d2cca77f05074cb`.
The challenge passed with no blocking or major findings. The review's sole major
was rejected as a direct source-reading error: it claimed `signal_cleanup`
emits no JSON while the reviewed source calls `emit_inconclusive` with
`operator_interrupt`, and the firing-path observes that receipt. Its remaining
items are documented residuals: a post-handoff signal deliberately exits 2
after the already-emitted result, sensitive retained content still requires
caller redaction, and SIGKILL/host-crash sweeping remains caller-owned. Raw Kimi
review and challenge responses remain mode-0600 files in the private evidence
directory and are not formal wrapper-gate receipts.

The formal Claude wrapper also remains unavailable for this candidate because
of the excluded `terminal_slash_commands` compatibility defect; direct results
are labelled by their actual path rather than wrapper-gate success.

Planned commands:

```bash
bash skills/code-review/scripts/test_opencode_review_retry.sh
bash skills/code-review/scripts/test_cli_review_wrappers.sh
bash skills/code-review/scripts/test_review_gate.sh
python3 skills/code-review/scripts/test_review_client_compat.py
bash skills/product-rd-workflow/scripts/check-agent-contract-coverage.sh --repo . --enforce
bash skills/skill-extraction-workflow/scripts/check-ccl-skills.sh .
python3 scripts/check-public-sanitization.py .
python3 scripts/check-markdown-links.py .
git diff --check
```

Completion evidence includes the mandatory R0 audit path surfaced by
`check-ccl-skills.sh`, implementer self-review over security/privacy, authority,
false-positive/false-negative, and evidence-loss axes, and the independent Kimi
review/challenge rounds above. Because the formal Claude wrapper has a separately
reproduced compatibility failure, all direct provider results remain labelled
as direct evidence rather than wrapper-gate success.
