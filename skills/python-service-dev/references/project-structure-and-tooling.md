# Project Structure And Tooling

Use this for Python package layout, dependency management, imports, linting, and type checking.

## Discovery

- Find `pyproject.toml`, `uv.lock`, `poetry.lock`, `requirements.txt`, `setup.py`, and workspace configuration.
- Identify package mode: app package, `src/` layout, namespace package, Django project, generated client, or script-only project.
- Use the repo's configured commands before inventing new ones.

## Tooling Defaults

- Prefer `pyproject.toml` for pytest, ruff, mypy/pyright, and package metadata.
- Keep runtime and dev dependency groups separate.
- Use lockfiles for deployable services.
- Use `pytest --import-mode=importlib` when the repo standard sets it.
- Do not rely on developer-local absolute paths or implicit `PYTHONPATH` in durable commands.
- **`uv` (Astral, Rust-based) is the current default-recommendation single-tool stack for most pure-Python service workflows** — covers the pip + pip-tools + virtualenv + pipx + (most of) poetry + pyenv use cases with one static binary. Per Astral docs: ~10-100x faster than pip on resolve/install; built-in Python version management (`uv python install`), Cargo-style workspaces, cross-platform `uv.lock` reproducible builds. Drop-in pip-compatible interface via `uv pip` for migration. **Validate per-project edge cases before declaring full replacement**: editable installs in deeply nested monorepos (workspace path resolution rules differ from poetry / pip), private PyPI index auth (`.netrc` / keyring / index-url env precedence), post-install hooks (`pip install` script-execution semantics), conda-managed environments (uv does not replace conda's binary-package channel), vendored wheel directories used as offline indexes, Debian/RHEL system-Python policies (uv-installed Python lives parallel to system Python, which can confuse system service managers expecting `/usr/bin/python3`). When picking up an existing project: keep its established stack (poetry / pip-tools / pdm / rye / hatch) rather than forced-migrate during normal feature work; schedule the uv switch as its own slice with lockfile parity verified. The "single tool replaces N tools" framing means CI pipelines, Dockerfiles, dev-onboarding docs, and CI cache configs all need to flip together — not piecemeal.
- **PEP 723 inline script metadata + `uv run script.py`** for one-off scripts, batch tools, ad-hoc data jobs, repair scripts, and report generators — replaces "create a venv just to run this" and `requirements.txt` siblings. Inline format: `# /// script` block at top of file declaring `requires-python` and `dependencies = [...]`, then `uv run script.py` auto-creates the ephemeral environment per PEP 723. **Reproducibility is NOT automatic**: `uv run` without an explicit lock will re-resolve dependencies each run against the latest matching versions — fine for ad-hoc local use, NOT for CI or production replay. Pin reproducibility by running `uv lock --script script.py` to produce `script.py.lock` adjacent to the script AND committing the sidecar lock to source control; CI should run `uv run --script script.py` against the committed lock. **Scope**: single-file scripts where the cost of a project skeleton (pyproject.toml + venv + install) outweighs the script's value. PEP 723 scripts CANNOT import internal first-party packages unless those packages are published to a private index (declared in `[tool.uv.sources]` inline) or referenced via `--with-editable` workspace paths — for scripts that need internal-package access, promote them to a proper project rather than fighting the inline format. Anything that grows past one file or gets imported by other code → promote to a proper project.

## Generated And Vendored Code

- Exclude generated clients, vendored libraries, migration output, and typings from strict lint/type rules when the repo already does so.
- Do not edit vendored third-party code to satisfy project style checks.
