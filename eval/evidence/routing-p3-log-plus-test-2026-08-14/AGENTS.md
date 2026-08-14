# Agent Contract — eval/evidence/routing-p3-log-plus-test-2026-08-14

Concluded-round audit evidence for the `p3-log-plus-test` independent routing
round (bound 8/10 baseline, non-stable-failure NO-EDIT disposition). The
authoritative narrative lives in `docs/skill-taxonomy-optimization-plan.md`
(section "p3-log-plus-test 独立一轮落地记录"); parent contract:
`eval/AGENTS.md` — its advisory-by-construction rule applies here in full.

Rules:

- **The round is concluded; its data files are immutable.** `baseline-rounds/`
  (round JSONs + `*.binding.json` sidecars), the two bank files, and
  `aggregates-recomputed.json` are the audit record. Do not edit or regenerate
  them in place — every file is pinned by `MANIFEST.json` `files_sha256`, and a
  silent edit is a hash mismatch, not an update. A legitimate correction adds a
  `provenance_correction` entry to `MANIFEST.json`, re-hashes the touched files
  there, and records the reviewing chain — never rewrites history quietly.
- **Random-sampling numbers are not bit-reproducible.** The grader rounds are
  recomputable in method (invocation + grader identity are in `MANIFEST.json`)
  but per-round numbers will differ on rerun; the n=10 discipline exists for
  this. Never "refresh" a committed round file because a rerun disagreed.
- **Scripts here are audit artifacts, not shared library code.** Nothing in
  this directory may be imported or invoked by repo gates or product code; per
  the parent contract nothing here may become a merge gate.
  - `recompute-aggregates.py` — deterministic: rerun and `diff` against the
    committed `aggregates-recomputed.json` to verify every cited aggregate.
  - `run-bound-round.sh <n> <bank> <outdir>` — the full-surface binding wrapper
    (checkout-independent revision). Fails closed on invalid round numbers,
    unusable evaluator output, and stale-output reuse; sidecars record the
    routing-surface hash before/after, repo HEAD, and skills-tree cleanliness.
  - `test-run-bound-round.sh` — 4-case stub-evaluator regression test for the
    wrapper's fail-closed guards. Run it after any wrapper edit; it is not
    wired into `make test` (a deliberate boundary: this directory is a
    concluded audit record, not live code).
- **Layering.** Scripts may read this directory, the sibling concluded-round
  evidence under `eval/evidence/`, and repo files needed for the surface hash;
  they must not mutate anything outside their own output directory arguments.
