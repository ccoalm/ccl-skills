# verify-sandbox — trust-rooted, sandboxed `make verify`

Mechanical-gate backlog ③. `make verify` executes the candidate's test code — on the
host that means the candidate gets the host's network, env/tokens, HOME, and workspace.
This runner executes the same family verify suite inside a sandbox, from a trust root
the candidate cannot touch.

## Trust roots

1. **Runner outside the candidate**: lives in ccl-skills, invoked from its checkout —
   never vendored into product repos, so a candidate diff cannot weaken the sandbox.
   (Diffs editing the verify machinery itself are routed to humans by the sibling
   control-plane detector.)
2. **Committed state only**: the candidate is cloned (`--no-hardlinks`) into a throwaway
   dir and checked out at the resolved SHA — uncommitted edits are excluded; the host
   workspace is never written.
3. **Sandbox**: docker with `--network=none` for the verify phase, explicit minimal env
   (host env never passed through), `--cpus/--memory/--pids-limit`, tmpfs /tmp, host-side
   hard timeout, mount canary (fail closed on unshared work dirs).
4. **Secret scan on host**: gitleaks reads the clone without executing candidate code.

## Usage

```bash
# from the ccl-skills checkout:
bash scripts/verify-sandbox/verify-sandbox.sh /path/to/candidate-repo            # HEAD
bash scripts/verify-sandbox/verify-sandbox.sh /path/to/repo --ref origin/main    # a ref
```

Exit codes: `0` verify green · `2` verify failed (incl. secret-scan hit / timeout) ·
`3` runner/config error (fail closed).

## Per-stack flow

- **Go**: two phases. A **warm step on the HOST** (network on, host credentials, but NO
  candidate code — `go mod download` only fetches the modules named in `go.mod`) populates
  a throwaway per-repo cache, seeded from the host cache's own module store via a `file://`
  GOPROXY first (offline/reliable) then the host proxy for genuine misses. The **verify
  phase** then runs the family chain `fmt-check vet verify-module-graph test-race` in a
  container with `--network=none`, that per-repo cache mounted read-only. Credentialed
  network touches only the host warm step, never the sandbox; the sandbox that runs
  candidate code has no network at all.
- **Python**: warm phase (network on) apt-installs make/git and pip-installs deps inside
  a container that is then committed to a throwaway image; the verify phase runs
  `make check` from that image with `--network=none`. The sibling core repo is cloned
  beside the candidate when the Makefile references `../python`.

## What this gate is (and is NOT) — compositional trust boundary

verify-sandbox proves the candidate's verify suite runs **without host network, secrets,
workspace, or cross-project caches** — it sandboxes *execution*. It does NOT prove the
suite is *honest*: a candidate controls its own `Makefile` (it could `fmt-check: ; true`)
and its own `.gitleaks.toml`/`.gitleaksignore` (it could allowlist a real leak). Those are
**control-plane** files — the sibling `control-plane` detector hard-pins them, so a diff
that no-ops a target or widens a secret allowlist is routed to human review. Use the two
gates together: control-plane guards *what the suite is*, verify-sandbox guards *how it
runs*. A green from verify-sandbox alone is "ran cleanly in the sandbox", not "the suite is
trustworthy" — that's the control-plane gate's job on the pinned files.

## Known limits (recorded, not hidden)

- Images are pinned by tag, not digest (`--image` to override); tag drift is a residual.
- Python's warm phase runs pip build hooks (candidate `pyproject.toml`) with network on —
  inside the capped container, but a hostile build hook could reach the network there.
  Residual risk equal to today's CI; the offline verify phase is where tests run.
- Docker engines on macOS share limited host paths; the work dir defaults to
  `$HOME/.cache/verify-sandbox` and a mount canary fails closed if unshared
  (`VERIFY_SANDBOX_TMPDIR` overrides).
- The runner asserts the family make-verify baseline targets; repos not on the baseline
  are rejected (exit 3), not silently half-verified.
