# Agent Contract — eval/evidence/placement-face-2026-08-28/arms

Behavioral-differential fixtures and raw outputs for the placement-face
round. Parent contract: `../AGENTS.md` (candidate-bound, concluded) applies
in full; arm-specific rules:

- arm-old.txt / arm-new.txt are the scoring ground truth; SHA256SUMS pins
  them with every file under runs/. Changing an arm invalidates its scored
  runs — rerun and re-hash, never patch.
- build_prompts.sh reconstructs the exact prompts deterministically and
  refuses unreadable/empty arm files; keep that guard.
- grading.md binds every scored verdict to a runs/ file; archived batches
  (arm-stale, ctl-invalid) are disclosure context and enter no aggregate.
