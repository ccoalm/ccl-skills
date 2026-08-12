# AGENTS.md — scripts/control-plane (gate engine source)

Deterministic control-plane change detector (mechanical-gate backlog ①): classifies a
base..head diff's files as CONTROL-PLANE (anything deciding how future changes are
verified/gated/installed/resolved/executed) vs product code, so control-plane diffs are
routed to explicit human authorization and never an auto-merge path.

Constraints:
- This is the CANONICAL source; product repos get a vendored copy via
  `scripts/install-gates.sh` (marker-managed, refreshed on rerun). Fix here, re-vendor —
  never patch the vendored copies.
- Trust-root invariants are load-bearing and must survive any edit: per-repo config is read
  from the MERGE-BASE tree (a candidate cannot self-declassify); the enforcement chain
  (config file, this engine, sibling gate engines/configs incl. secret-scan config and the
  vendored contract engine, CI files, hooks, and the ROOT make recipe) is hard-pinned and
  never overridable; malformed/unknown-key config fails closed (exit 3, never a silent
  pass); `--no-renames` so renames of gated files stay visible.
- Exit-code contract (consumed by CI and future auto-merge pipelines): 0 = product-only /
  warn-only report; 2 = control-plane touched under enforce; 3 = usage/config error.
  Do not repurpose these.
- Bash 3.2-safe (macOS /bin/bash): no heredoc inside command substitution, no associative
  arrays. Python3 core owns config parsing + `**` glob matching.
- Required verification: `bash scripts/control-plane/test.sh` (registered in the repo
  Makefile `test` target). Any semantic change to defaults/pins/overrides needs a
  matching RED-first case there.

Parent contract: `../AGENTS.md`, root `AGENTS.md`.
