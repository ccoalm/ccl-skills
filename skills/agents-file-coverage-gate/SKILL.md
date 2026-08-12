---
name: agents-file-coverage-gate
description: 在一个仓库跑「AGENTS.md 契约覆盖」gate——扫出根目录和每个源码目录是否都有 AGENTS.md,可一键补 stub 并接 CI 卡关。确定性脚本运行器,不做交付分类。触发:"查/跑 AGENTS 覆盖"、"查/跑/补 agent 覆盖地图"、"agent 契约覆盖"、"扫一下哪些目录缺 AGENTS.md"、"每个目录都有 agent 契约了吗"、"补缺失的 AGENTS.md"、"契约覆盖 gate"、"给这个仓初始化契约覆盖"、"装 AGENTS 的 pre-commit / CI 卡关"、"check AGENTS.md coverage"、"agents coverage"、"scaffold missing AGENTS.md"、"bootstrap agents coverage"、"do all dirs have an agent contract"。Skip:问「何时/是否」该更新契约或分层策略本身 → `product-rd-workflow` 的 spec/repo-contract sync gate;只是写某一个 AGENTS.md 的内容 → 直接编辑该文件;定义 agent 工具调用/函数的输入输出 schema 或调用契约(不是 AGENTS.md 文件覆盖)→ `llm-inference-integration`。
---

# AGENTS.md File Coverage Gate

On-demand runner for the agent-contract coverage gate: it verifies (and can scaffold) that a repo's **root and every source-code directory** carry an `AGENTS.md`. This skill RUNS the gate; the *policy* — when a delivery must update a contract, and the layering rules contracts encode — lives in `product-rd-workflow`'s spec / repo-contract sync gate. Do not re-decide policy here.

In a project health-check system, this is a deterministic check provider for repo-local contract coverage. It reports the coverage states implemented by this gate, and it becomes CI-enforceable only when the project wires the vendored script with `--enforce`; agent review still owns whether each contract's content correctly captures the directory boundary.

Contracts are **nearest-file-wins** (the closest `AGENTS.md` to the edited file applies; there is no root index). Scope is **every directory that contains a source file picked up by the scan** (tracked, or untracked-but-not-gitignored; outside a git work tree it falls back to a plain file scan), detected by extension — so Go packages like `dal`/`service`/`handler` with no manifest are covered.

The gate checks **one repository**. Before running, confirm `--repo` points at a single repo, not a **GitLab group / parent-of-repos** checkout (sibling repos cloned side by side under a parent folder, where the parent is not itself a git repo). Running it on a group parent would conflate sibling repos and report a spurious "missing root contract" — so the script now detects that case (target is not a git repo root yet contains nested repos) and **refuses with exit 2, listing the sub-repos to run per-repo**. For a group, loop the gate over each member repo.

## Run

The gate ships in this package at `product-rd-workflow/scripts/check-agent-contract-coverage.sh`. Resolve that script inside the installed ccl-skills plugin (the newest match under the plugin cache) and run it against the target repo (default `--repo .`). Never copy it into the repo just to run it; copying is only for CI.

1. **Scan** — `bash <script> --repo <dir> --check`. Lists every source directory missing a non-empty `AGENTS.md`. Exit 0 (guidance) — never blocks, safe on legacy repos.
2. **Scaffold** — when the user wants to close gaps: `--fix` writes a stub `AGENTS.md` in each missing directory. Additive only: it never edits or overwrites an existing file, and never follows a symlink.
3. **Fill** — replace each stub with the directory's real contract: role/responsibility; allowed and forbidden dependencies and layering rules (e.g. a logic layer must not access the database directly — go through the data-access layer); invariants; build/test commands; a link to the nearest parent contract. An empty stub still counts as a gap. **Edit only `AGENTS.md` files.** Keep every contract SHORT: Codex consumers (per current documented behavior — `project_doc_max_bytes`, default 32 KiB, version/config-dependent; primary source: the official Codex AGENTS.md guide at developers.openai.com/codex/guides/agents-md — verify against the installed version) build ONE instruction chain at session start from repo root down to cwd and stop appending on overflow (the guide documents the cap and the stop-adding behavior; no overflow warning is documented) — an oversized root/parent contract can therefore evict deeper overrides, and contracts outside the root→cwd path are not auto-loaded there at all (hosts implementing the agents.md convention apply nearest-file-wins per edited file — per the agents.md spec FAQ; the short-contract discipline serves both semantics).
4. **Enforce** — `--enforce` exits 1 on any missing / empty / symlinked contract. Wire it into `make lint`/CI once the repo is clean.

Tune scope per project/language: `--source-ext ".tf .razor"`, `--exclude "migrations gen"`, `--name <filename>`. See `bash <script> --help`.

**A clean result only covers the languages the scan recognizes.** Source dirs are detected *by file extension*; a directory whose source is a language outside the active `--source-ext` set is silently unscanned and contributes no gap — so a green `--enforce` on a repo whose source is in an unrecognized extension (e.g. `.tf` / `.razor` / `.zig`, or `Dockerfile` / `Makefile`) can be a false-negative for those dirs. (`--source-ext` *appends to* the built-in default set rather than replacing it, so common mainstream languages are already covered; the blind spot is the extensions neither in the defaults nor added.) Before trusting a clean result (or wiring `--enforce` as a blocking gate), confirm the active extension set covers every in-scope source language whose directories should count toward AGENTS coverage; widen it, or record the unscanned languages as a known coverage gap — do not read a green from a partial extension set as full contract coverage.

## Bootstrap a repo (one-time adoption)

To make coverage self-sustaining — enforced on every commit with no agent and no prompt — set a repo up once:

1. **Vendor the script** into the repo. This is the ONLY case where copying is correct: a git hook or CI runner cannot reach the plugin cache. Copy `check-agent-contract-coverage.sh` to e.g. `tools/`.
2. **Scaffold + fill** the current gaps — `--fix`, then fill each stub (Run step 3).
3. **Install the gate** as a git hook or CI step that runs `--enforce`:
   - pre-commit / pre-push: `bash tools/check-agent-contract-coverage.sh --enforce`. To share across the team, commit a `hooks/` dir AND have a setup/init script run `git config core.hooksPath hooks` (that config is local per clone, so it must be installed, not just committed).
   - or CI / `make lint`: the same command.
   During rollout run `--check` (warn-only, exit 0); flip to `--enforce` once the repo is clean so it blocks.

After bootstrap, every commit/CI run enforces coverage automatically; the on-demand path above is then only for ad-hoc checks. This skill can drive the bootstrap (vendor + scaffold + install hook); the running afterwards needs neither agent nor skill — just the vendored script.

## Boundary

- This skill is the **on-demand** path (a short ask → run the gate) plus **one-time bootstrap** (vendor + hook/CI). The steady-state automatic enforcement is the vendored script in a hook/CI, not this skill.
- It does not decide *when* contracts must change or what layering rules to impose — route those to `product-rd-workflow`'s sync gate.
