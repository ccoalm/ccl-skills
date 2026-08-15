# Agent Contract — eval/evidence/routing-new-tighten-vs-owner-2026-08-15

Concluded-round audit evidence for the `new-tighten-vs-owner` independent
routing round (bound 3/10 RED baseline, maintainer-directed fix, final wording
10/10 with zero stable-neighbor regression). The authoritative narrative lives
in `docs/skill-taxonomy-optimization-plan.md` (section
"new-tighten-vs-owner 独立一轮落地记录"); parent contract: `eval/AGENTS.md` —
its advisory-by-construction rule applies here in full.

Rules:

- **The round is concluded; its data files are immutable.** The four arm
  directories (`baseline-rounds/`, `target-after-rounds/`, `neighbors-before/`,
  `neighbors-after/` — round JSONs + `*.binding.json` sidecars), the two bank
  extracts, and `aggregates-recomputed.json` are the audit record. Do not edit
  or regenerate them in place — every file is pinned by `MANIFEST.json`
  `files_sha256`, and a silent edit is a hash mismatch, not an update. A
  legitimate correction adds a `provenance_correction` entry to
  `MANIFEST.json`, re-hashes the touched files there, and records the
  reviewing chain — never rewrites history quietly.
- **Random-sampling numbers are not bit-reproducible.** The grader rounds are
  recomputable in method (invocation + grader identity are in `MANIFEST.json`)
  but per-round numbers will differ on rerun; the n=10 discipline exists for
  this. Never "refresh" a committed round file because a rerun disagreed.
- **Scripts here are audit artifacts, not shared library code.** Nothing in
  this directory may be imported or invoked by repo gates or product code; per
  the parent contract nothing here may become a merge gate.
  - `recompute-aggregates.py` — deterministic: rerun and `diff` against the
    committed `aggregates-recomputed.json` to verify every cited aggregate
    (it also fail-closes on any invalid sidecar or mixed HEAD/surface arm).
  - `test-bank-case-provenance.sh` — deterministic: proves both bank extracts
    are verbatim lines of the untouched frozen bank (ALL VERBATIM / nonzero).
  - `run-bound-round.sh <n> <bank> <outdir>` — the full-surface binding
    wrapper, verbatim from the bank-runner round's final generation (4
    sidecar legs incl. `results_match_bank`; fail-closed on invalid round
    numbers, unusable evaluator output, stale-output reuse, and pre-existing
    round artifacts).
  - `test-run-bound-round.sh` — the wrapper's 10-case stub regression suite,
    adapted here to the single-case bank; its duplicate fixture APPENDS the
    duplicate id because the inherited overwrite form degenerates to a valid
    full set on a 1-case bank (probe-blinding fixture class).
