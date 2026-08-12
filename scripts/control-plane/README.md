# control-plane — deterministic control-plane change detector

Mechanical-gate backlog ①. A verify gate cannot protect itself from a diff that edits the
gate: a candidate that changes the Makefile, CI, hooks, gate engines/configs, agent
contracts, or the toolchain-capture surface (Dockerfiles, lockfiles, `go.mod`/`go.sum`,
package manifests, test-runner plugins) is deciding *what future agents obey* — it must go
to explicit human authorization, never an auto path. This engine makes that classification
deterministic instead of prose judgment.

## Usage

```bash
# agent merge-confirmation card / local check (report only, exit 0):
bash scripts/control-plane/control-plane.sh check --base origin/main

# future auto-merge pipelines (exit 2 when the diff touches control plane):
bash scripts/control-plane/control-plane.sh enforce --base origin/main --head <branch>

# CI backstop (warn-only by default; add --enforce to block):
bash scripts/control-plane/control-plane.sh ci --base "$CI_MERGE_REQUEST_DIFF_BASE_SHA"

# machine output:
bash scripts/control-plane/control-plane.sh check --base origin/main --json
```

Exit codes: `0` ok / product-only · `2` control-plane touched (enforce modes only) ·
`3` usage or config error (fail-closed).

## Per-repo config — `.control-plane.json` (optional)

```json
{ "extend_globs": ["deploy/**"], "product_overrides": ["scripts/product-cli/**"] }
```

Defaults are built in and apply without any config. `extend_globs` adds repo-specific
control-plane paths; `product_overrides` declassifies DEFAULT matches the repo
deliberately treats as product code. Precedence: hard-pinned > extend_globs >
product_overrides > defaults — an override never cancels an extend_globs entry.

## Trust-root invariants

- **Baseline-config authority**: the config is read from the **merge-base tree**, never
  from the candidate — a diff cannot declassify itself, and any config change is itself
  flagged (the config file is hard-pinned).
- **Hard-pinned enforcement chain**: `.control-plane.json`, `scripts/control-plane/**`,
  `scripts/owner-dispatch/**`, `.owner-dispatch.json`, the vendored contract engine
  (`tools/check-agent-contract-coverage.sh`), secret-scan config (`.gitleaks.toml`,
  `.gitleaksignore`), CI files (`.gitlab-ci.yml`, `.gitlab/**`, `.github/**`, `ci/**`),
  hooks, and the ROOT make recipe (`Makefile` — the family's `make verify` entry) can
  never be overridden to product.
- **Fail-closed config**: malformed JSON or unknown keys exit 3 — a typo'd override key
  never silently no-ops into a pass. Three further exit-3 causes close the indirect
  rewrites of the same surface: a **non-blob entry** at `.control-plane.json` in either
  tree (gitlink/tree/symlink — a foreign gitlink makes `git show` fail, which used to read
  as "absent" and fall back to default rules; a symlink can point outside the tree), and a
  **malformed candidate config** in the head tree (syntax-gated on its own, while
  classification authority stays with the merge-base config).
- **Rename capture**: `--no-renames` shows a rename of a gated file as delete+add, so a
  move-out cannot smuggle a control-plane file below the classifier.
- **One repository identity**: when `--repo` is given it is the only answer to "which
  repository", so the ambient repo-routing variables (`GIT_DIR`, `GIT_WORK_TREE`,
  `GIT_COMMON_DIR`, `GIT_INDEX_FILE`, the object-store overrides, `GIT_NAMESPACE`,
  `GIT_CEILING_DIRECTORIES`) are cleared for that run — two competing answers is how a
  product-only verdict ends up authorizing an unrelated control-plane change. A
  receive-pack quarantine (`GIT_QUARANTINE_PATH` present) keeps its object-store variables:
  the pushed commit lives only there. **Without `--repo` nothing is cleared** — the gate has
  named no repository of its own, so git's normal discovery, environment included, is the
  caller's intent (this is how a git hook invokes it). Clearing there would not be safer; it
  would silently move the run from the caller's repository to whatever lies under cwd.
- **True objects only**: `git replace` refs and the legacy `.git/info/grafts` file are
  disabled, and `--base`/`--head` are pinned to commit OIDs once. Otherwise one OID can
  resolve to two different trees inside a single run — the diff and the candidate-config
  check would then describe different commits.
- **Bare repositories are supported**: they skip worktree-root normalization (they have no
  worktree and no subdirectory `--repo` to be confused by), so server-side hooks and mirror
  CI can classify.

## Trust boundary

**The adversary is the diff, not the environment — because against the environment there is
no defence to build.** This gate classifies what a change touches. On a developer machine the
same person sets the environment and runs the gate. In an MR pipeline the CI definition comes
from the candidate's own branch, so job-level `variables:` *are* candidate-controlled — but so
is the job itself: anyone who can inject an environment variable can delete the gate job in
the same commit. No amount of in-process hardening survives that, and pretending otherwise
just grows the script. What catches it is a human noticing that an MR touches CI files, which
is exactly why `.gitlab-ci.yml` and `ci/**` are hard-pinned control-plane paths.

So environment-borne redirection findings are **out of scope for this script**: they are
real, and they are handled one layer up (review of CI-file changes, protected branches), not
by another `unset`. Reviewers should close them as out-of-scope rather than reopen the arms
race — and treat any "the gate can be bypassed by editing CI config" finding as a statement
about MR review, not a bug here.

The environment handling that IS here — clearing repo-routing and config-injection variables
under an explicit `--repo`, disabling replace refs and grafts — is **accident protection plus
cheap defence-in-depth, not a security boundary**: an exported `GIT_DIR` left over in a shell,
or a repository legitimately carrying replace refs, would otherwise produce a silently wrong
verdict. Do not cite it as a defence against a hostile environment.

What IS in scope is everything the diff author controls: the changed file set, the candidate
`.control-plane.json`, renames and move-outs, and every path-shape trick in between.

Known limits:
- Classifies **committed** diffs only (merge-base → head); uncommitted working-tree
  changes are not seen — commit first.
- Paths travel as a NUL-delimited stream (`git diff -z`), so filenames with newlines,
  quotes, or non-UTF-8 bytes are matched by their exact bytes — no C-quoting mismatch.
  The verdict is carried by the exit code, never parsed from the printed report.
- `product_overrides` is reviewed policy: a broad override (e.g. `"**"`) disables the
  default classification (pins and `extend_globs` excepted). Reviewers of a
  `.control-plane.json` change should treat wide overrides as a red flag.

## Vendoring

Installed into product repos by `scripts/install-gates.sh` (gate name `control-plane`),
warn-only via `ci/agent-gates.gitlab-ci.yml`. Flipping warn → block (`--enforce`) is a
deliberate, separately-reviewed step, per install-gates philosophy.
