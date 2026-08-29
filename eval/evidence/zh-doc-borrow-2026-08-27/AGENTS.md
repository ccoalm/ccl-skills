# Agent Contract — eval/evidence/zh-doc-borrow-2026-08-27

Concluded-round audit evidence for the zh-doc-borrow landing (tighten-doc
pronoun-disambiguation rule + delivery-face machine-check proxy boundary +
zero-loss consolidation; PR #66). The authoritative rows live in
`skills/skill-extraction-workflow/references/source-register.md`; parent
contract: `eval/AGENTS.md` — its advisory-by-construction rule applies here
in full.

Rules:

- **The round is concluded; its evidence is candidate-bound.** `REPLAY.md`,
  `obligation-report.txt`, and everything under `arms/` document the exact
  reviewed candidate. Do not edit or regenerate them in place after the round
  closes — a later correction adds a dated erratum note (the grading file
  already carries in-round errata) rather than rewriting history quietly.
- `gen_obligation_report.sh` is a fail-capable checker, not a formatter: it
  resolves the base to an immutable commit SHA, asserts every moved obligation
  exists in the base bullet and every carrier count matches, and exits nonzero
  on any mismatch. `--self-test` must keep both negative probes (invalid base,
  canary phrase) red-capable. Regenerate `obligation-report.txt` only from
  this checker, never by hand.
- Reproduction commands assume the repository root as cwd and a base ref that
  still resolves; when the recorded base ref ages out, pass the immutable SHA
  printed inside `obligation-report.txt` instead.
