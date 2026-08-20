# 026 — A firing-path digest must identify reachable Ruby code

## Extraction charter

| Field | Decision |
| --- | --- |
| Purpose | Prevent an unreachable Ruby guard from satisfying a source-register firing path merely because its exact line and code tokens still exist. |
| Scope | Included: `register-firing-path-resolution.rb`, its focused regression suite, an append-only source-register disposition, and this plan. Excluded: C3 word-budget or evidence grading, D1, E5, other locator kinds or languages, release state, remote state, and unrelated cleanup. |
| Depth | One resolver verdict change with a pre-change RED reproduction, focused positive and negative controls, mutation evidence, repository gates, and exact-candidate independent review plus challenge. |
| RCA baseline | `line-sha256` proves exact trimmed bytes and a Ruby code token on the physical line. It never asks whether Ruby can execute that line. Therefore `if false ... end` and an uncalled lambda preserve the digest while removing the registered runtime path. |
| Failure modes | A reachability check may reject valid conditional guards, accept another inert construct, depend on unsafe execution, or silently widen non-Ruby support. The repair must stay static, deterministic, Ruby-only, and fail closed when reachability cannot be established. |
| Lifecycle impact | Implementation and testing only. No trigger, routing, host configuration, install, release, or deployment behavior changes. |
| Evidence plan | Reproduce both bypasses against the untouched base; make permanent fixtures fail before the repair and pass after it; mutate each new protected predicate and require the focused suite to turn RED; run the repository gates on the exact candidate. |
| Completion standard | The resolver rejects a digest found only under a statically unreachable branch or an uncalled lambda, accepts the existing live Ruby anchors, reports a stable fail-closed reason, and passes focused plus repository validation. Independent review and adversarial challenge must be conclusive on the final bytes. |

## Frozen execution context

| Field | Value |
| --- | --- |
| Base | local `dev@6437abee61f9c41f3f890d75165aee701dfbbc65` |
| Branch | `worktree-resolver-reachability` |
| Worktree | `.work/worktrees/resolver-reachability` |
| Registered finding | Source-register row 214 records the `if false ... end` bypass as open and assigns it to a separate resolver-design round. |

## Target-output map

| Owner | Status | Output |
| --- | --- | --- |
| `skill-extraction-workflow` resolver | implemented | Reject exact-line matches under literal-dead branches or inside a lambda with no live local entry call. |
| `skill-extraction-workflow` focused suite | implemented | Pin the reported bypasses, their immediate variants, and live-code precision controls. |
| `skill-extraction-workflow` ledger | implemented | Row 215 supersedes the open row without editing ledger history. |
| `testing-strategy` | applied | RED-first focused coverage, benign precision controls, and a seventeen-predicate killing-mutation walk bind the resolver behavior. |
| `terminal-cli-dev` | applied | Preserve the validator's one-shot arguments, stdout success token, exit-code convention, and stderr diagnostic envelope. |
| Other skills and lifecycle owners | unchanged | No shared rule, route, trigger, host, release, or product surface changes. |

## Batch and verification plan

This round is one batch:

1. Reproduce the `if false` and uncalled-lambda bypasses on the frozen base.
2. Add permanent tests that are RED against the base behavior.
3. Implement the smallest static Ruby reachability rule that closes those cases without executing target code.
4. Run the focused suites, required repository gates, and mutation checks.
5. Persist the exact changed-file self-review, then run independent review and adversarial challenge against that candidate.

## Baseline evidence

The two reported bypasses reproduced separately before the resolver changed:

| Fixture added to the focused suite | Untouched resolver result | Required result |
| --- | --- | --- |
| Exact guard line under `if false ... end` | exit 0 | exit 1 |
| Exact guard line inside an assigned, uncalled lambda | exit 0 | exit 1 |

Both failures occurred after the preceding 33 focused assertions had passed, so
the RED is attributed to the new reachability checks rather than an earlier
fixture failure.

## Implemented design

The resolver still hashes and lexes unmodified source bytes. For a matching Ruby
line it now adds two static checks:

1. Ripper AST ranges mark bodies under literal-dead `if`, `elsif`, `unless`,
   precondition `while`, and precondition `until` forms unreachable. A
   `begin ... end while/until` postcondition body remains eligible because Ruby
   executes it once before checking the condition. The parser builder appends a
   location child to semantic nodes so tokenless sexp forms such as `return0`,
   `zsuper`, `yield0`, and an empty array still contribute their physical line.
   Dead bodies then include every Ruby code line between the condition or lambda
   header and the body's semantic end, covering multiline statement starts.
2. A lambda body is eligible only when the same local binding has a later direct
   `.call` before the next assignment. Calls under a literal-dead branch or
   inside a lambda do not count. Calls inside a top-level method count only when
   a later live top-level bare call reaches that method through direct bare
   calls; calls inside an uncalled method do not. An inline lambda counts only
   when the receiver itself,
   after removing parentheses, is the lambda; a lambda nested in a receiver
   argument does not.

An exact digest on a code-token line that fails either check reports
`line-sha256 source line is not statically reachable`. Missing bytes, comments,
heredocs, word-list content, and other non-code matches keep the existing
`source line absent` reason. A matching code line in Ruby that does not parse
reports `line-sha256 target Ruby did not parse` instead of being mislabeled
unreachable. Both a nil AST and a non-nil partial AST carrying the builder's
parse-error state fail closed.

The resolver is not a general control-flow prover and does not execute target
code. Acceptance means that this classifier found no proven-dead carrier; it
does not prove that production executed the line or resolve arbitrary dynamic
dispatch.

## Current deterministic evidence

| Check | Result |
| --- | --- |
| Resolver syntax | `ruby -c` passed |
| Focused resolution suite | `register_firing_path_resolution_tests_ok (57 assertions)` |
| Current repository ledger | `register_firing_path_resolution_ok (129 locators resolved)` |
| Applied mutation matrix | Seventeen mutations each exited 1 at its owning assertion: parser-event positions erased; dead-body span fill erased; literal truthiness disabled; `elsif` classification erased; every lambda admitted; dead call counted; every method treated reachable; live-method reachability erased; transitive method-call propagation erased; reassignment ignored; dead reassignment counted; postcondition exception erased; unreachable diagnostic erased; nested receiver recursively admitted; parenthesized receiver unwrapping erased; parse diagnostic erased; partial-parse error state ignored |
| Wiring suite | `register_firing_path_wiring_tests_ok (14 assertions)` |
| Shared-skill gate | `ccl_skill_check_clean_ok`; private R0 audit passed; routing had zero blocking or advisory findings |
| Required root gates | Agent-contract coverage, public sanitization, Markdown links, and `git diff --check` passed |
| Full repository suite | `make test` reached the C3 candidate gate after `check-ccl-skills` passed, then exited 2 because the resolver, focused test, and source register are intentionally dirty control-plane paths. Its prescribed unblock is commit or discard; neither is authorized in this round. No full-suite pass is claimed. |

## Review evidence

The first tracked-review launch is not credited. Its host execution reached a
terminal exit 2, but the caller used `set -e` and deleted the temporary JSON
before persisting it. No reviewer, reason code, or verdict is inferred from that
missing result. The remediated launch must use a fresh chain, preserve JSON on
every terminal exit, and bind the updated packet.

The second launch stopped in deterministic preflight with
`self_review_incomplete`: the controller derived `testing-strategy` and
`terminal-cli-dev`, but the packet credited only the primary owner. No provider
ran and no review or challenge budget was consumed. The next launch adds the
two missing sub-owner rows and uses another fresh chain.

The third launch also stopped in deterministic preflight before provider
execution: its added sub-owner rows duplicated existing concern ids, which the
review-plan schema rejects. The corrected packet assigns the existing
`tests_evidence` and `compatibility` rows to those owners, retains one row per
concern, and uses a new chain.

The fourth chain reached an independent reviewer and returned three P2s. The
postcondition-loop finding reproduced: `begin ... end while false` executes once
but the classifier marked it dead. A new positive fixture was RED before the
fix. The called-method finding also reproduced: a lambda directly called inside
a top-level method that is itself directly called was rejected; its positive
fixture was RED before the method-call analysis. Both are fixed and mutation
checked. The ledger-scope finding was valid as a reader-risk: the current row
now says explicitly that ordinary lines in uncalled method bodies remain
eligible instead of implying general Ruby reachability. Because candidate bytes
changed, no `r4` verdict carries forward; the next review starts a fresh chain.

The fifth chain returned two P2s, both reproduced. An unparseable Ruby target
with the digest line present reused the unreachable diagnostic; the new
diagnostic assertion was RED before the fix. A lambda nested as an argument in
`wrap(...).call` was recursively marked invoked; its new negative fixture was
also RED. Receiver classification now unwraps parentheses only, with a positive
inline-lambda control, and parse failure has its own fail-closed reason. Candidate
bytes changed again, so `r5` does not carry forward.

The sixth chain found one P2 in the literal-dead class: Ripper's ordinary sexp
omits positions from tokenless nodes such as `return0`, so those body lines were
not added to the dead-line set. The proposed “last element is a position” rule
does not hold for those nodes themselves. The repair instead uses a Ripper
builder that appends an inert event location without changing existing child
indexes. A four-shape `return` / `super` / `yield` / `[]` fixture was RED before
the repair. Implementer follow-up also found that event locations identify a
multiline statement's end, so the dead-body span now fills intervening code
lines; a multiline `return(` start was RED before that repair. Both predicates
are mutation checked. Candidate bytes changed, so `r6` does not carry forward.

The seventh chain found one P2 in method reachability: the classifier seeded
methods only from top-level bare calls and did not propagate direct calls inside
an already reachable method. The positive `main -> run_worker -> lambda.call`
fixture was RED before the fixed-point repair. Reachability now carries the
top-level entry line through direct method calls until no new definition is
found, and removing that propagation makes the new fixture RED. Candidate bytes
changed, so `r7` does not carry forward.

The eighth chain found one P2 in the same literal-dead class: Ripper represents
`elsif` as its own node, so `elsif false` bypassed the `if` case. The focused
fixture was RED before repair. `elsif` now shares `if` branch semantics, and
removing that node type makes the new fixture RED. Candidate bytes changed, so
`r8` does not carry forward.

The ninth chain found one P1 in parse failure handling: `SexpBuilderPP#parse`
can return a partial AST while `builder.error?` is true. The focused trailing-
operator fixture was GREEN before repair despite invalid Ruby. The resolver now
rejects nil ASTs and error-bearing partial ASTs with the same parse diagnostic;
removing the error-state check makes the fixture RED. The tokenless `yield` and
`super` controls were also moved into a called method so they remain valid Ruby
and still prove dead-branch positioning. Candidate bytes changed, so `r9` does
not carry forward.

The tenth chain produced no reviewer verdict. Claude returned an expired OAuth
401 envelope; the controller classified the lane `inconclusive` with
`reason_code=local_tool_failure` and `next_action=stop_reviewer_lane`. No pass,
finding, or challenge credit is inferred. The next fresh chain uses the allowed
independent-client subset and keeps the candidate otherwise unchanged.

The eleventh through thirteenth chains also produced no reviewer verdict. In
`r11`, Kimi returned `kimi_host_resource_exhausted` and OpenCode/DeepSeek
returned `missing_final_text`. OpenCode-only `r12` repeated the missing-final-
text result, and Kimi-only `r13` repeated host-resource exhaustion. Each chain
ended `inconclusive` with `next_action=stop_reviewer_lane`; no findings or pass
credit are inferred. Review, challenge, and completion therefore remain blocked
on an external reviewer client becoming usable.

## Implementer self-review

| Field | Result |
| --- | --- |
| Acceptance criteria | The two base bypasses are RED; literal-dead equivalents including `elsif false`, tokenless and multiline statement starts, a self-call, an uncalled-method call, a dead call, a post-reassignment call, and a lambda nested in another receiver are also RED. Existing top-level anchors, literal postcondition-loop bodies, a dead reassignment followed by a live call, a directly or parenthesized-inline called lambda, and a lambda called through a finite direct-method chain from live top-level code remain GREEN. Nil and partial-error Ruby parses share a distinct fail-closed diagnostic. |
| Changed-file scope | `skills/skill-extraction-workflow/scripts/register-firing-path-resolution.rb`; `skills/skill-extraction-workflow/scripts/test_register_firing_path_resolution.sh`; `skills/skill-extraction-workflow/references/source-register.md`; `specs/026-register-firing-reachability/plan.md`. |
| Edge and failure paths | Reviewed nil and partial-error Ruby parses, duplicate digest lines, comments and literal content, literal-dead `if` / `elsif` / `unless` variants including tokenless sexp nodes and multiline statement starts, precondition versus postcondition loops, live versus literal-dead rebinding, self-calls, calls under dead branches, uncalled methods, top-level methods reached directly and transitively by a later bare call, direct and parenthesized inline receivers, and a lambda nested in a receiver argument. Parser failure leaves no line reachable and uses its own reason. |
| Security, privacy, authority, and data loss | The resolver uses `Ripper.lex` and `Ripper.sexp` only; it does not evaluate or load target Ruby. Fixtures are synthetic. No credential, remote, release, install, merge, or cleanup surface changes. |
| Known residual risks | Static local analysis cannot prove production execution or arbitrary Ruby control flow. Ordinary lines inside uncalled method bodies remain eligible. Aliased lambdas, callback passing, `worker.()` / `worker[]`, singleton or class methods, and dynamic dispatch remain outside the direct local-call proof; some live forms can therefore be rejected while syntactically live but dynamically inert forms can still be accepted. Runtime execution evidence remains outside this locator. |

### Sub-owner self-review

| Owner | Result |
| --- | --- |
| `testing-strategy` | The existing focused harness is the lowest layer that exercises both the real Ruby parser and resolver. It recorded the original bypasses and reviewer-found false positives RED before their fixes, keeps live top-level, postcondition-loop, dead-reassignment, direct-lambda, parenthesized-inline, and direct/transitive called-method cases as precision controls, covers `elsif`, tokenless, multiline, nil-parse, and partial-parse AST shapes, and killed seventeen independent implementation mutations. The whole-ledger wiring suite covers integration; no additional runtime layer can prove this static classifier. The blocked `make test` result is reported as blocked rather than green. |
| `terminal-cli-dev` | The command remains a non-interactive, one-shot plain-text validator. Its arguments, success output, and 0/non-zero convention are unchanged. Unreachable, parse-failure, and existing absent-line reasons travel through the same stderr failure envelope and remain distinguishable; no prompt, TTY, ANSI, streaming, durable-output, or terminal-state surface is introduced. |
