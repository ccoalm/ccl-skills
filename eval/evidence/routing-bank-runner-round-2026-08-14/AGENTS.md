# Agent Contract — eval/evidence/routing-bank-runner-round-2026-08-14

Concluded-round audit evidence for the bank/runner co-change round (the four
routed proposals: runner routing_surface self-identification, oncall
mixed-sentence decoy promotion, p3 sentinel disposition, opencode
combined-intent collision promotions). The authoritative narrative lives in
`docs/skill-taxonomy-optimization-plan.md` (section「bank/runner co-change
轮落地记录」) and `specs/020-bank-runner-round/plan.md`; parent contract:
`eval/AGENTS.md` — its advisory-by-construction rule applies here in full.

Rules:

- **The round is concluded; its data files are immutable.** `new-cases-rounds/`
  and `full-bank-rounds/` (round JSONs + `*.binding.json` sidecars) and
  `bank-new-cases.jsonl` are the audit record, pinned by `MANIFEST.json`
  `files_sha256`. A legitimate correction adds a `provenance_correction` entry
  to `MANIFEST.json`, re-hashes the touched files there, and records the
  reviewing chain — never rewrites history quietly.
- **Random-sampling numbers are not bit-reproducible.** Grader rounds are
  recomputable in method (invocation + grader identity are in `MANIFEST.json`)
  but per-round numbers differ on rerun. Never "refresh" a committed round file
  because a rerun disagreed. The frozen case `p3-log-plus-test` carries a
  machine-readable `stability` annotation in the bank itself: its flip is a
  characterized feature, not a regression.
- **Scripts here are audit artifacts, not shared library code.** Nothing in
  this directory may be imported or invoked by repo gates or product code; per
  the parent contract nothing here may become a merge gate.
  - `run-bound-round.sh <n> <bank> <outdir>` — the full-surface binding wrapper
    (inherited from the p3 round's checkout-independent revision) extended with
    the embedded-surface cross-check: the evaluator's own
    `routing_surface.descriptions_sha256` must match the wrapper's
    independently recomputed surface hash, or the round is invalid. Fails
    closed on invalid round numbers, unusable evaluator output, stale-output
    reuse, dirty skills tree, and embedded-surface mismatch.
  - `test-run-bound-round.sh` — 6-case stub-evaluator regression test for the
    wrapper's fail-closed guards (the p3 round's 4 cases plus missing/wrong
    embedded surface). Run it after any wrapper edit; not wired into
    `make test` (this directory is a concluded audit record, not live code).
- **Layering.** Scripts may read this directory, sibling concluded-round
  evidence under `eval/evidence/`, and repo files needed for the surface hash;
  they must not mutate anything outside their own output directory arguments.
