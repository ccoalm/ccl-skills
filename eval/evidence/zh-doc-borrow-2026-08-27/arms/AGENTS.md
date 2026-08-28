# Agent Contract — eval/evidence/zh-doc-borrow-2026-08-27/arms

Behavioral-differential fixtures and raw outputs for the zh-doc-borrow round.
Parent contract: `../AGENTS.md` (candidate-bound, concluded round) applies in
full; this file adds the arm-specific rules.

Rules:

- **Arm snapshots are the scoring ground truth.** `armA-*.txt` / `armB-*.txt`
  must stay byte-identical to the texts the scored runs saw; `SHA256SUMS`
  pins them together with every file under `runs/`. Any change to an arm
  invalidates the runs scored against it — rerun and re-hash, never patch.
- `build_prompts.sh` reconstructs the exact prompts deterministically from the
  arm files (modes: A, A2, B2 × old/new). It refuses unreadable or empty arm
  files; keep that guard — an empty rule list silently reproduces nothing.
- `grading.md` binds every scored verdict to a file under `runs/`. Runs marked
  `raw-lost` or `supplementary/prefinal` are archived context and enter no
  aggregate claim; do not promote them.
- Rerunning the instruments is a fresh sample of a random variable: report
  spreads alongside the recorded results, do not overwrite the recorded ones.
