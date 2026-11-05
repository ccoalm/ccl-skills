# Liveness gate pipe race

`check-ccl-skills.sh`'s liveness-predicate gate sometimes reports a violation on a line it should clear. The cleared-by-state check at line 695 pipes the window into `grep -q` under `set -euo pipefail`: `if printf '%s' "$liveness_win" | grep -qE '\-o[[:space:]]*stat='; then continue`. When the window still has text after the `ps -o stat=` line, `grep -q` can exit on its match before the writer finishes, the writer dies of SIGPIPE, `pipefail` fails the pipeline, and the check reads a miss. `specs/obligation-ledger-pipe-race/plan.md` recorded this site under Residual risk. This round fixes it.

## Charter

| Field | Answer |
| --- | --- |
| Purpose | Stop false reds from the liveness-predicate gate. It is one step of `check-ccl-skills.sh`, which every skill change runs and which blocks `make test` and CI. A false red names a correct line as a liveness defect, costs a rerun, and pushes maintainers to loosen a gate that is right. |
| Scope | In: the cleared-by-state check at `check-ccl-skills.sh:695`, plus one regression case in `test_liveness_predicate_gate.sh`. Out: the gate's predicate, window, helper check and messages; the same-shape grammar check at line 1392 (see Residual risk); other suites with the same shape; the obligation-ledger round. No watermark applies; this is not an iterative-program source. |
| Depth | Targeted check plus a one-line gate change (line 695 before the change, 698 after). One named defect, reproduced and fixed. No skill text changes. |
| Result classification | Failure. The gate's own suite failed 1 of 3 standalone runs at case p10b (recorded in the obligation-ledger round), and this round measured 10 false reds in 300 runs of the extracted gate section on p10b's fixture. |
| Matching analysis | A paired control on the gate section that differs only in line 695 (Diagnosis), a fixture that makes the race deterministic, and an applied mutation that restores the pipe (`evidence/validation.md`). |
| Failure mode | A weak fix would rerun until green, widen the waiver (for example match `stat=` anywhere in the file), or drop the waiver and let the helper path clear these lines. The first hides the class. The other two change what the gate accepts. |
| Lifecycle impact | Testing and CI only. The gate's accept and reject sets are unchanged, so product intent, design, implementation, release and onboarding are unaffected. |
| Evidence plan | The p10b failure recorded in `specs/obligation-ledger-pipe-race/plan.md`, the gate source, a paired probe on the extracted gate section, repeated standalone suite runs, and an applied mutation of the fixed line. |
| Completion standard | The new case fails on every run with the pipe on this host and passes with the fix. Every other case stays green with the fix; with the pipe, only cases the waiver decides may fail. Repeated standalone suite runs pass under load. Local lanes pass on the exact candidate. Extraction review and challenge run, plus a delta pass for any later change. |

## Shared-gate classification

| Item | Decision |
| --- | --- |
| Artifact class | `gate implementation`, on the shared skill checker. |
| Risk route (`feature-risk-router`) | `shared-gate`. Required: the owning workflow (`skill-extraction-workflow`), `testing-strategy` for the regression case and mutation, and an independent review and challenge before push. No other tag applies: no data, permission, contract, money or release-ops path. |
| Semantics | Unchanged. The here-string gives `grep` the same window plus one trailing newline. The pattern is not anchored to the end, so the match set is the same. Only the false-miss path goes away. |
| Plan and status verifiers | `check-ccl-skills.sh` (spec references, impact chain, register rows) and `make test-repo-gates`, run on the candidate. Neither ran before the edit; the first checker run came after it. |
| Status-sync target | Pull request #208's body and this plan's Validation section. |

## Implementation boundary

| Gate | Decision |
| --- | --- |
| Active baseline | This plan. |
| Mechanics owners | `skill-extraction-workflow` owns the checker; `testing-strategy` owns the regression case and the mutation. The shell has no dedicated development skill. `terminal-cli-dev` is not applicable: the gate's output, exit codes and messages do not change. |
| Delegation | Local. One line and one test case leave nothing to run in parallel. |
| Visible surface | No. |
| Risk inventory | `shared-gate` (Shared-gate classification). |
| Test case first | p10c is written and run red against the unfixed checker before line 695 changes. |

## Diagnosis

| Hypothesis | Prediction | Probe | Result |
| --- | --- | --- | --- |
| p10b's fixture or the gate's predicate is wrong | the extracted section fails p10b's fixture on every run | 300 runs of the section on p10b's fixture | rejected: 10 of 300 false reds, not 300 |
| SIGPIPE under `pipefail` at line 695 | the fixed line alone removes the false reds; a window with a long tail after the `stat=` line fails on every run with the pipe | paired control, both sections built from the same checker and differing only in line 695, on p10b's fixture (300 runs each) and on a fixture whose window carries a 1 MiB line after the `stat=` line (30 runs each) | confirmed: pipe 10/300 and 30/30 false reds; here-string 0/300 and 0/30. The red is the gate's own `liveness_predicate_scan_failed` on the probe line |

Why a long tail makes the old form fail on every run here: the state read is the window's first non-comment line, and `grep -q` stops reading once a line matches. The 1 MiB tail is much larger than a default Linux pipe buffer (64 KiB), so the writer is still writing when the reader exits. This assumes a `grep -q` that stops at its first match. On this host `grep` is ugrep 7.8.4. A `grep` that read all its input before matching would let the old form pass p10c. The fixed form does not depend on this and passes p10c with any `grep`.

The race is in the waiver, so it fails in the strict direction. A missed waiver falls through to the helper check, which clears the line only through a named state helper. The race can turn a cleared line red. It cannot clear a real violation.

## Change

Line 695 reads the window from a here-string: `if grep -qE '\-o[[:space:]]*stat=' <<<"$liveness_win"; then`. This is the form the same file already uses at line 1541 (1538 before this change), for the reason that comment gives.

| Gate input | Before | After |
| --- | --- | --- |
| No banned ppid read in the file | `liveness_predicate_scan_ok` | same |
| Banned read, `ps -o stat=` read in the window, short tail | cleared, with intermittent false reds | cleared |
| Banned read, `ps -o stat=` read in the window, 1 MiB tail | false red on every run on this host | cleared |
| Banned read, only a bare `stat=` assignment in the window | `liveness_predicate_scan_failed` | same |
| Banned read, no state read and no state helper | `liveness_predicate_scan_failed` | same |
| Banned read, window calls a helper whose body reads `ps -o stat=` | cleared | same |

## Test cases

| Case | Layer | Assertion | Before | After |
| --- | --- | --- | --- | --- |
| p10c, new | gate section | a `ps -o stat=` read followed in its window by a 1 MiB line still clears the banned read: the section exits 0 | fails on every run on this host | passes |
| existing p1 to p14 | gate section | unchanged | green, except cases the waiver decides, which fail intermittently (p3, p10b and p13 seen) | green |
| suite under load | suite | consecutive green standalone runs | p10b intermittent | see Validation |

## Target-output map

| Owner | Direction | Status | File or reason |
| --- | --- | --- | --- |
| `skill-extraction-workflow` | owner | updated | `scripts/check-ccl-skills.sh`, `scripts/test_liveness_predicate_gate.sh` |
| `testing-strategy` | sibling | unchanged | Its flake rules already require diagnosis before rerun and a deterministic regression; applied as written. |
| `defect-diagnosis` | sibling | unchanged | Applied as written: paired control on one variable, falsifier run before the fix. |
| `product-rd-workflow` | upstream | unchanged | Its shared-gate classification was applied (above); no routing or gate policy changes. |

## Root cause and prevention

Contributing factors: (1) `grep -q` on a pipe under `pipefail`, a shape whose failure depends on scheduling; (2) a window that is usually short, so the race is rare and reads as load-related; (3) earlier rounds (`specs/regression-suite-flakes/plan.md`, `specs/obligation-ledger-pipe-race/plan.md`) converted this shape one suite at a time and listed the rest as residual, so this site waited for its own failure. No check flags the shape when it is written. A static check for pipe-into-`grep -q` in `pipefail` scripts would be the class control. It is a new blocking gate with its own false-positive design, for example `grep -q` reading a process substitution or a script without `pipefail`, so it is recorded here as a proposal for its own change, not landed.

## Residual risk

Line 1392 (1389 before this change) has the same shape: `printf '%s\n' "$contract_anchor_out" | grep -qE '^contract_anchor_gate_ok …$'`. It is not exposed today. The pattern matches only the producer's final line, which `check-contract-anchors.sh` writes with its last `echo`, so nothing remains to write after the match. It becomes exposed if that producer ever prints after its ok line.

## Validation

Results on the final candidate, the review passes and the commits they reviewed: `evidence/validation.md`.
