# Post-R11 Deep Self-Review and Approach Decision

Status: **review paused**. The branch has had 11 review rounds plus one challenge, which exceeds the repository's 5-round limit for a high-risk line. No R12 runs until the approach below is accepted, implemented and verified locally.

Decision: **replace** the reimplementation approach with an orchestrator that runs the original hook scripts, keeping the performance goal (see [Replacement approach](#replacement-approach)).

> **Superseded.** Later measurement narrowed this decision, and the orchestrator below is no longer the plan.
>
> - Claude Code runs hooks in parallel.
> - Most per-hook time is `jq` start-up.
> - The orchestrator's design review returned 28 findings.
>
> The current plan is [`plan.md`](plan.md): one `jq` read per hook, with no dispatcher. Sections 1–4 still hold as the record of R1–R11.

## 1. Findings history (R1–R11, C1)

119 findings: 35 P1, 84 P2. R1–R10 (111) are recorded as closed. R11 #1–#5 were fixed in `6ae8038`; R11 #6–#8 (evidence gaps in `validation.md`) are still open.

| Surface | Findings | What the findings were about |
|---|---:|---|
| `hooks/pretool-dispatch.sh` (python3-free path) | 32 | awk/jq JSON decoding, UTF-8/NUL checks, shell continuation and heredoc lexing, mutator classification, `bash -n` exemption, wrapper arity (`sudo`/`env`), process-group supervision |
| `validation.md` / receipt | 24 | Claims that went beyond the evidence in the packet, stale counts, contradictory closing lines |
| `hooks/pretool-dispatch.py` | 22 | Merge-candidate lexing (quotes, comments, heredocs, here-strings), merge-guard failure handling, RFC-8259 number/surrogate/NUL strictness, ported edit isolation |
| `packages/opencode-plugin/ccl-skills.ts` | 13 | Forwarding of context/systemMessage, matching edits that arrive without a callID (cohort matching) |
| Installers (`install-opencode.sh`, `opencode-adapter.ts`) | 12 | Required-file lists (in scope), symlinked path components (hardening beyond main) |
| `hooks/guard-edit-isolation.sh`, `guard-merge-authorization.sh` | 7 | Python-free paths of the rewritten standalone guards |
| Tests | 9 | Assertions too weak to catch the regression they named |

P1 and P2 counts did not converge. Per round: R6 had 6, R7 8, R8 8, R9 13, R10 9, R11 8. Every round from R6 to R11 still had 1–3 P1s.

## 2. Root causes

1. **Each guard's logic exists more than once.** The original scripts still exist, `pretool-dispatch.py` ports part of them, and `pretool-dispatch.sh` ports them again in awk/jq for hosts without python3. Each fallback mode (python, awk, jq-only, neither) multiplies the surface, and most P1s from R4 onward are differences between modes, not defects in the original guards.
2. **The fixes create the next findings.** The later rounds review code written to close the previous round:
   - R9.6: the jq-only path denied `bash -n`.
   - R10.1: the exemption added for that accepted a newline.
   - R11.1: the fix for R10.1 accepted any binary whose basename looks like a shell.

   The same shape appears in the installer chain (R9.8 → R10.4 → R11.3, and R10.2 → R11.2) and in callID-less edit matching (R3.12 → R4.5 → R5.5 → R6.4 → R7.4 → R10.5 → R11.5).
3. **The scope grew past the goal.** The goal is to cut process startup, while keeping every existing gate. Main has none of the following, and the branch added them in response to findings:
   - 2 MiB wire caps;
   - RFC-8259/UTF-8/surrogate/finite-number strictness;
   - a python3-free path that does more than main's visible degrade;
   - Dulmage-Mendelsohn cohort matching for a callID mismatch that already exists on main;
   - symlink-component hardening in the installers.
4. **The prefilter is a full shell lexer.** Skipping the merge guard when a command is not a landing candidate is the right performance idea. Deciding that with an exact lexer turns every shell-syntax edge case into a possible bypass.
5. **The evidence document is too large.** `validation.md` has about 500 lines of closure claims, and each claim can be checked against a packet that does not contain its proof. That accounts for 24 findings.

## 3. Assumptions checked against main (`3ae87ae`, then `origin/main` `788470c`)

| Assumption | Main behavior | Consequence |
|---|---|---|
| Hosts without python3 must stay fully enforced | `guard-edit-isolation.sh`, `owner-dispatch-guard.sh`, `guard-delegation-owner.sh` and `guard-broad-local-test.sh` already need python3. Without it they show a degrade message, and `guard-edit-isolation.sh` denies apply_patch | The python3-free path only has to match main's degrade behavior, not reimplement the guards |
| The dispatcher must validate the wire strictly | There are no size caps and no RFC strictness; each hook parses input with `jq` | Out of scope. If wanted, file it as a separate hardening item |
| Edits without a callID must be matched exactly in OpenCode | Main uses a `call-<timestamp>` key before the call and `unknown-call` after it, so notices are already lost | This is an existing bug, not a regression. Keep main's behavior and file it separately |
| Installers must reject symlinked path components | Main checks only backup and staging leaves | Out of scope. Only the required-file lists for new files are in scope |
| The merge-candidate prefilter must be exact | Main runs the full merge guard on every Bash call | The prefilter only has to over-approximate. A false positive costs main's latency, not correctness |
| Running the hooks in a fixed order is new | Claude Code runs matching hooks in parallel, so a grant could be consumed while another hook denies (C1.3, R2.7) | Keep it: sequential order is a cheap, real improvement |
| PR #230 does not interact with this branch | `hooks/agy-bridge.py` runs the original scripts in `hooks.json` order, applies deny > ask > allow, and fails closed. It also relies on every hook in `hooks/hooks.json` appearing in its `DISPATCH` table | After rebase, a single-entry `hooks.json` breaks that invariant. Main already has an orchestrator, so this design should share it rather than add a third |

## 4. Options

| Option | Remaining risk | Cost |
|---|---|---|
| **Keep**: fix R11 #6–#8 and run R12 | The trend shows no convergence. Each fix to the awk/lexer/installer code produces findings at the same rate, and the 5-round limit is already exceeded | Low per round, but there is no point at which it stops |
| **Simplify in place**: delete the python3-free reimplementation and the out-of-scope hardening, keep the Python ports | Ports such as the merge-candidate lexer and edit isolation still need a parity argument against the original guards | Medium |
| **Replace** (chosen): orchestrate the original scripts, skip a script only when a sound prefilter proves it would do nothing, and port only where measurement requires it, backed by a differential test | Prefilter soundness, which a property test can check mechanically | Medium: most of the current branch is discarded, but its regression cases are reused as the test corpus |

**Why replace.** It removes root causes 1, 3 and 4 by construction, because guard semantics stay in the guards that already passed review on main. Main's agy-bridge already uses this pattern. Reviewers only need to check composition order and prefilter soundness, not shell-parsing parity.

**If this choice is wrong**, it costs latency on commands the prefilter cannot rule out, which then run at main's speed. It does not cost enforcement. The current branch keeps its history and can be restored from `6ae8038`.

## Replacement approach

### Components

- **One core**, `hooks/pretool_chain.py` (name to be settled in the plan). It holds:
  - the ordered chain per tool class;
  - the fail-closed set;
  - the composition rule (deny > ask > allow; `additionalContext` and `systemMessage` concatenated);
  - an optional `may_act(payload)` prefilter per script.

  Claude Code (`hooks/hooks.json` → `pretool-dispatch.sh` → core), OpenCode (one dispatcher call per tool call) and Antigravity (`agy-bridge.py` imports the chain table instead of its own copy) all use it.
- **Chain order** keeps main's `hooks.json` order. The one exception is that the merge guard runs after the hooks that can deny a call: owner-dispatch, broad-local-test and the shared-skill checkpoint. This stops a grant being consumed on a call that is then denied.
- **Prefilter contract.** A prefilter only decides whether a script can be skipped. Its soundness is checked by a property test: for every corpus input where `may_act` returns false, the original script's output must be empty. Prefilters work on normalized substrings, with quotes, backslashes and newlines removed and case folded; they never parse shell. For example, the merge-guard prefilter skips only when no landing keyword from the guard's vocabulary appears.
- **Ports** are allowed only when measurement shows a hook on the hot path cannot be prefiltered cheaply. The expected case is `remind-unverified-cli-flag.sh`. Each port has a differential test asserting the port's output equals the original script's output on the corpus.
- **Without python3**, `pretool-dispatch.sh` runs the original scripts in chain order and composes their output with a small jq combiner. This matches main's degrade behavior and adds no lexing.
- **What is discarded**:
  - RFC-8259/2 MiB wire strictness;
  - the awk/jq lexers and classifiers;
  - the custom process-group supervisor (replaced by `subprocess` timeouts);
  - callID-less cohort matching;
  - installer symlink-component hardening;
  - the rewrites of `guard-edit-isolation.sh` and `guard-merge-authorization.sh`.

  Main bugs found along the way (R9.5 SHA-256 git health check, R3.12 callID mismatch) become separate backlog items.
- **What is kept**:
  - the single `hooks.json` registration;
  - one OpenCode call per tool call, with the apply_patch body sent once;
  - forwarding of `additionalContext`/`systemMessage` on block (R3.11, R4.7);
  - required-file lists in installers for the new files;
  - the benchmark harness;
  - the regression inputs from all findings, reused as the corpus.

### Security questions

1. **Caller-controlled inputs:** the tool payload (command, file paths, patch body), written by the model.
2. **Damage if a value is forged:** an unauthorized merge, or an edit in the primary checkout.
3. **Where trust comes from:** the original guards, unchanged. The dispatcher only decides whether a script is skipped, and the property test checks that skip.
4. **Negative tests:** `git "pu""sh" origin main`, `glab mr "ac""cept"` and a continuation-split `git pu\<newline>sh` must reach the merge guard and be denied. A forged prefilter skip must be caught by the property test.

### Tests

| Layer | Decision | How |
|---|---|---|
| unit | add | Composition order and fail-closed behavior on missing, crashing or timed-out scripts; prefilter property test; port differential test (`python3 hooks/test_pretool_dispatch.py`) |
| integration | run + adapt | OpenCode hooks and host adapters (`npm test`); the agy-bridge suite after rebase (`python3 hooks/test_agy_bridge.py`); installer migration test |
| host smoke | run | `npm run smoke:host`, `make test CCL_BROAD_TEST_REASON=repo-required`, `make npm-publish-dry`, `check_review_evidence_present.py` |
| performance | run | The existing benchmark harness against main and against the current branch's medians. Budget: routine and CLI-flag Bash, OpenCode Bash and 10-file apply_patch within 1.2× the current branch; Edit no slower than main |

### Review plan

R12 is a **full-scope review** of the replacement candidate, not a delta, followed by a challenge. This does not reset the round count. If R12 plus the challenge still leave a blocking finding, stop again and do another self-review instead of patching.

## 5. Next steps

1. Rebase onto `origin/main`. Write the replacement plan into `plan.md` and get it reviewed (design review) before any code edit.
2. Implement on this branch, using the boundary record from the re-entry gate. The removed code stays recoverable from `6ae8038`.
3. Rewrite `validation.md` in short form: commands, receipt and one line per invariant. This replaces the 500-line closure log and makes R11 #6–#8 moot.
4. Run local verification, then R12 (full scope) and the challenge, then the push/PR gate.
