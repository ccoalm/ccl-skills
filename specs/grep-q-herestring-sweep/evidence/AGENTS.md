# evidence Agent Contract

Measurement artifacts for the pipe-into-`grep -q` sweep, kept so the `RED-baseline` rows in `skill-extraction-workflow/references/source-register.md` can be rerun instead of taken on trust.

Rules:

- **Frozen once the round lands.** Do not edit or regenerate these files to fit a later claim. A new measurement goes in a new round's evidence directory.
- **`pipe-probe.sh` is an evidence tool, not a repository gate.** It is not wired into `make test` or CI. Run it as `bash pipe-probe.sh <source-root> [runs]` against a working tree or a `git archive` of an older commit; it writes only under its own `mktemp` directory.
- **Its cases read code by function name or `check` label.** If a renamed helper or label makes an extraction come back empty, the probe stops with exit 2 instead of passing.
- **Numbers are reported as measured**, with the host facts they depend on (bash version, `grep` implementation, pipe buffer size) stated in `validation.md`.
