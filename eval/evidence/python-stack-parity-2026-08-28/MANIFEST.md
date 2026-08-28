# python-stack parity gate — applied behavioral evidence (2026-08-28)

Round: worktree-065-python-stack-parity (base origin/dev@53adde2). This directory carries the
immutable transcripts the source-register rows for python-service-architecture /
go-microservice-architecture / skill-extraction-workflow reference, so a review packet can
verify the RED/GREEN/mutation claims without trusting candidate-authored summaries.

- Pre-fix candidate: the three commits' first parent chain (content commit authored on this
  branch); command: `./skills/skill-extraction-workflow/scripts/check-parallel-stack-parity.sh .`
- Post-fix candidate at transcript capture: 6589a76174b673c019b26a8af9d29018037fcac8
- Legs:
  1. red-baseline-prefix.txt — gate v1 run on the PRE-reconcile tree: parity_drift on
     event-driven-architecture.md with 8 normalized-region diffs (incl. the model-freeze rule
     replaced by a pointer on the Go side), plus the multi-tenant routing-list divergence that
     motivated the list-collapse normalization; exit 1.
  2. mutation-red.txt — one-word applied mutation in the multi-tenant mirrored region: gate
     turns RED attributing exactly the mutated line; restore returns GREEN (v1 transcript;
     v2 re-run below).
  3. green-postfix.txt — v2 gate on the reconciled tree: parallel_stack_parity_ok, exit 0.
