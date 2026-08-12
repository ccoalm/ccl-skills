# AGENTS.md — scripts/verify-sandbox (gate engine source)

Trust-rooted sandboxed `make verify` runner (mechanical-gate backlog ③). Executes a
candidate repo's verify suite inside docker with network=none, minimal explicit env,
CPU/memory/pids caps, and a host timeout — from a throwaway clone of the COMMITTED state,
so uncommitted edits are excluded and the host workspace is never touched.

Constraints:
- This runner is deliberately NOT vendored into product repos: the trust root is that it
  runs from the ccl-skills checkout, outside the candidate tree, where a candidate
  diff cannot alter the sandbox constraints. Do not add it to install-gates.
- Load-bearing invariants that must survive any edit: committed-state-only clone
  (`--no-hardlinks`, detached checkout of the resolved SHA); the sandbox that RUNS
  candidate code has `--network=none` for BOTH stacks — for Go, credentialed module
  fetches happen only in a HOST warm step (`go mod download`, no candidate code) into a
  throwaway per-repo cache mounted read-only (never the whole host GOMODCACHE — that would
  expose other projects' private modules); python's warm phase (apt/pip, network on, NO
  candidate source mounted) runs in a container committed to a throwaway image so the
  offline verify phase keeps the warmed state; the mount canary fails closed when the
  docker engine does not share the work dir (an unshared path mounts as an EMPTY dir with
  no error); host gitleaks scan is read-only and never executes candidate code; exit
  contract 0/2/3 (3 = fail closed).
- Family coupling is intentional: the runner asserts the make-verify baseline targets
  (go: fmt-check/vet/verify-module-graph/test-race; python: check) instead of silently
  running something else.
- Required verification: `make test-verify-sandbox` (docker required — deliberately NOT
  part of the default `make test`); plus real-repo dogfood for both stacks on changes to
  phase logic. On a docker-less host the suite SKIPs (exit 0) but that is NOT a pass —
  set `VERIFY_SANDBOX_REQUIRE_DOCKER=1` (CI does) to turn the skip into a hard failure so
  a docker-less runner cannot green a "required" gate.
- Accepted design boundary (not a bug): a repo can declassify its own `go.mod`/`pyproject`
  from control-plane via `.control-plane.json` `product_overrides` — but `.control-plane.json`
  itself is hard-pinned, so that declassification is a human-reviewed control-plane change.
  This is the intended escape hatch for repos that treat dependency manifests as product;
  the review requirement is preserved.

Parent contract: `../AGENTS.md`, root `AGENTS.md`.
