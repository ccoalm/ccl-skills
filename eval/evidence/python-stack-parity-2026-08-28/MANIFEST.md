# python-stack parity gate — applied behavioral evidence (2026-08-28)

Round: worktree-065-python-stack-parity (base origin/dev@53adde2). This directory carries the
immutable transcripts the source-register rows for python-service-architecture /
go-microservice-architecture / skill-extraction-workflow reference, so a review packet can
verify the RED/GREEN/mutation claims without trusting candidate-authored summaries.

- Pre-fix candidate: the three commits' first parent chain (content commit authored on this
  branch); command: `./skills/skill-extraction-workflow/scripts/check-parallel-stack-parity.sh .`
- Superseded binding note: earlier capture referenced 6589a76174b673c019b26a8af9d29018037fcac8
- Legs:
  1. red-baseline-prefix.txt — gate v1 run on the PRE-reconcile tree: parity_drift on
     event-driven-architecture.md with 8 normalized-region diffs (incl. the model-freeze rule
     replaced by a pointer on the Go side), plus the multi-tenant routing-list divergence that
     motivated the list-collapse normalization; exit 1.
  2. mutation-red.txt — one-word applied mutation in the multi-tenant mirrored region: gate
     turns RED attributing exactly the mutated line; restore returns GREEN (v1 transcript;
     v2 re-run below).
  3. green-postfix.txt — v2 gate on the reconciled tree: parallel_stack_parity_ok, exit 0.

## v3 recapture (after the second dual-track round's fixes)
Binding is by content hash, not only commit id: BINDING.txt records the gate script's sha256 and
each pair file's sha256 at capture; green-postfix.txt re-runs the v3 gate, the regression suite,
and eval-routing on that exact tree; mutation-red.txt re-runs the applied-mutation leg under v3.
The v1-era transcripts (red-baseline-prefix.txt, the v1 section of mutation-red history) remain as
the pre-reconcile RED evidence; the v3 gate has no normalization left to mask them.
