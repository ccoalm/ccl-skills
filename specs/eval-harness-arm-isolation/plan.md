# Eval harness arm isolation

The behavior A/B tool (`skill-behavior-eval.py`) and the golden-trace replay (`eval-golden-trace.rb`) say their agents run with read-only tools. They do not. This round reproduces the three isolation defects found during the TypeScript skill's paired evaluation (PR #225), fixes the ones that reproduce, and corrects the documentation that made the claim.

## Charter

| Field | Answer |
| --- | --- |
| Purpose | Stop the two evaluation tools from producing samples in which the tested agent ran shell commands, wrote files, or read the other arm's saved answers or the fixture rubric while the tool and its reference text say the agent was read-only. |
| Scope | In: `skills/skill-extraction-workflow/scripts/skill-behavior-eval.py` (`run_agent`, `run_judge`, `_headless_claude`), `scripts/eval-golden-trace.rb` (`run_agent`, `parse_transcript`), their regression suite `scripts/test_eval_runtime.py`, `references/harness-patterns-and-eval.md` §3.3 and `references/eval-routing.md` Tier-3, and one source-register row. Out: `skill-paired-eval.py` (a different tier that grants Bash on purpose, already strips inherited `CLAUDE*` variables and uses `--strict-mcp-config`, and already states it has no mount isolation); the PR #225 harness (`specs/typescript-dev-skill/evidence/behavior-eval/harness/`); adding a mount-namespace dependency to the tools (see Decision). Iterative-program watermark: not applicable, single round. |
| Depth | Generator/tooling change: reproduction of three named defects on the current code with paired controls, a fix to two scripts, regression tests, and documentation corrections. |
| Result classification | Failure. Each defect was observed in PR #225's smoke run and is re-run here on the current code (Diagnosis). Defect 2 does not reproduce and is closed without a change. |
| Matching analysis | Widened RCA with counterfactual controls per defect (Diagnosis, Root cause). |
| Failure mode | A weak fix would swap `--allowedTools` for `--tools` and stop there: plugin MCP tools would still run shell commands (observed below), the agent would still start in the caller's directory next to the saved answers, and nothing in a run would show that the boundary held. Over-reaching fixes would strip all user settings from the `current` arm (it would stop measuring the installed configuration) or add a Linux-only `bwrap` dependency to an advisory tool used once. |
| Lifecycle impact | Testing/validation of skill changes only (the §3.2 and §3.3 evaluation tiers). Product intent, design, implementation guidance, release and onboarding are unaffected. Users without source access do not run these tools. |
| Evidence plan | (1) The PR #225 summary's tool-defect section (`specs/typescript-dev-skill/evidence/behavior-eval/summary.md`) and its harness in the same directory. (2) Current tool source. (3) `claude --help` 2.1.322 for `--tools`, `--allowedTools`, `--strict-mcp-config`, `--restricted`, `--setting-sources`. (4) Live probes on this host that drive the tool's own `run_agent` argv, each against a control that differs in one variable. (5) The host's permission rules, which turned out to explain two of the three original observations. |
| Completion standard | New regression tests fail on the base code and pass on the fix; a live run with the fixed argv shows no shell, write or MCP tool and no read of the saved answers; the repository lanes that cover the touched files pass; extraction review and challenge reach no unresolved P0/P1; the source-register row passes the impact-chain gate. |

## Diagnosis

Probe harness: a scratch script imports the tool, captures the exact argv `run_agent` builds, runs it against `claude` 2.1.322 (`--model claude-haiku-5-5` to save cost; tool availability and permissions are decided by the CLI, not the model) in an empty directory, and records tool calls, tool results, permission denials and files created. Raw streams stay in the session scratch area. Host facts that matter: user settings carry unscoped `Read`, `Glob` and `Grep` allow rules, `Edit` allow rules over the session temp tree, and `Bash(echo *)`-style allow rules; the child's `permissionMode` is `default`.

| Probe | Variable | Result |
| --- | --- | --- |
| D1 write, tool argv, inherited env | baseline | Bash and Write both ran; `bash_probe.txt` and `write_probe.txt` created |
| D1 write, `--tools` in place of `--allowedTools` | flag | Bash and Write are not offered, but the agent called the context-mode plugin's MCP `ctx_execute` and created `bash_probe.txt` |
| D1 write, `--tools` + `--strict-mcp-config` | MCP | init event lists only `Glob Grep Read Skill`, 0 MCP tools; Bash/Write calls answer "No such tool"; nothing created; plugins and skills still load |
| D2 Write/Read into the parent session's scratch dir, user settings excluded, `dontAsk` | inherited vs stripped `CLAUDE*` env | denied in both arms; the earlier "allowed" result came from the user `Edit(//tmp/...)` allow rule, present with or without the inherited env |
| D3 read a canary outside cwd and the fixture rubric, tool argv | baseline | both read |
| D3 same, user settings excluded, `dontAsk`, with and without `--add-dir` | allow rules | Glob and Read denied |
| D3 in-cwd: tool argv, user settings excluded, `dontAsk`, cwd holds `behavior-eval-out/F1.candidate.s1.txt` | strictest permissions | the agent globbed and read the saved answer |
| `--restricted` | candidate fix for D3 | confines reads, but ignores user settings, so the installed plugins do not load; unusable for the `current` arm |
| skill reference read under `dontAsk` with no allow rule | permission mode | Read of the invoked skill's own `references/` file denied; forcing `dontAsk` would break the `current` arm on hosts without a broad Read rule |
| judge argv + `--tools ""` + `--strict-mcp-config` | judge tools | init `tools: []`; attempted Bash call has no effect |

Conclusions:

- **Defect 1 reproduces.** `--allowedTools` pre-approves; it does not limit what is offered, so whatever the host's rules or mode allow runs. `--tools` limits only built-in tools; plugin MCP tools stay unless `--strict-mcp-config` is also given. The judge run had no tool limit at all and reads untrusted answers. `eval-golden-trace.rb` uses the same argv and runs in the repository root.
- **Defect 2 does not reproduce** with Claude Code 2.1.322: stripping the inherited `CLAUDE*` variables changes neither the permission mode nor which paths are allowed. Closed without a change. The PR #225 observation is explained by this host's allow rules (paired control above).
- **Defect 3 reproduces in a narrower form than reported.** Out-of-cwd reads succeed because of the host's broad allow rules (or a bypass mode), which the `current` arm loads by design. Independent of any rule, the tool starts every agent in the caller's working directory, where the default `--out` holds both arms' saved answers and a repository checkout holds the rubric; reads there are always allowed.

## Root cause

Widened across categories:

- Stale process model (primary): the authors read `--allowedTools` as an allowlist of available tools ("Allowlist (not denylist)", "truly side-effect-free"). The CLI's own help separates `--tools` (availability) from `--allowedTools` (permission). Counterfactual: with `--tools` from the start, Bash and Write would never have run. The repository's named-convention rule (verify a tool's config contract against its primary source before building) existed and did not fire when these scripts were written.
- Missing control on MCP: even the correct built-in flag leaves plugin MCP tools, which can run shell commands. Counterfactual: `--tools` alone still produced a written file.
- Latent condition: the agent's working directory is the caller's, and the output directory defaults under it.
- Detection gap: neither tool checks what the run actually offered the agent. The stream's init event lists the available tools, so a run can verify its own boundary; the code-review wrapper already treats a missing tool or MCP boundary as inconclusive. The tests asserted stream parsing only, never the argv or the boundary.
- Not a cause: inherited environment (falsified above).

Prevention as controls on the class, not diligence:

1. Both tools restrict availability with `--tools` plus `--strict-mcp-config`; the judge gets `--tools ""`.
2. Each run fails closed unless the stream's init event lists only the expected tools (`tool_boundary_violated` or `missing_tool_boundary`). If a future CLI changes what these flags mean, the samples stop instead of silently widening.
3. `skill-behavior-eval.py` starts each agent and judge in a fresh empty directory and removes it afterwards.
4. The sample signature carries a launch-boundary version, so a resumed run re-runs samples saved under the old argv instead of banking them.
5. Regression tests fail on the old argv, on a missing or widened init tool list, on an agent started in the caller's directory, and on a signature that would reuse an old sample.
6. The reference text stops claiming read-only or isolated arms and names the remaining gap and its remedy.

## Decision: no mount-namespace dependency in the tools

Only a mount namespace can guarantee that one arm cannot read another arm's tree, the rubric or local checkouts when host rules allow broad reads (PR #225 used `bwrap`). It is not added to the tools in this round: there is one observed use; it is Linux-only and needs user namespaces; the §3.3 tool is advisory and rarely run; and the `current` arm's purpose (the installed configuration with its user settings) conflicts with hiding the host. Instead the reference text says what the tools guarantee (tool availability, a fresh working directory, a verified boundary) and what they do not (filesystem view), and directs a run whose conclusion depends on what an arm can see to a mount namespace, citing the PR #225 harness pattern in prose. Revisit if a second evaluation needs it.

## Target-output map

| Owner | Direction | Status | File or reason |
| --- | --- | --- | --- |
| `skill-extraction-workflow` | owner | updated | `scripts/skill-behavior-eval.py`, `scripts/eval-golden-trace.rb`, `scripts/test_eval_runtime.py`, `references/harness-patterns-and-eval.md` §3.3, `references/eval-routing.md` Tier-3, one source-register row |
| `skill-paired-eval.py` (same skill, §3.1 tier) | sibling | unchanged | Grants Bash on purpose inside a synthetic world; already passes `--strict-mcp-config`, strips `CLAUDE*`/`GIT_*`, and its docstring already states there is no mount isolation |
| `code-review` (Claude review wrapper) | sibling | unchanged | Already uses `--tools`, `--strict-mcp-config` and treats a missing boundary as inconclusive; its text about `--allowedTools` is already correct |
| `llm-inference-integration` | sibling (agent sandbox guidance) | unchanged | No text there claims `--allowedTools` restricts tools (repository search for `allowedTools` hits only the files above and `code-review`) |
| `testing-strategy` | downstream (test policy) | updated (test-only) | No test-layer or gate policy change; its mutation-walk rule is applied as written. `scripts/lang-basics-go-check.test.sh` gets a one-line flake fix because it failed the required local lane on this candidate (see validation.md, Repository checks); the other suites with the same pipe pattern are a follow-up |
| `defect-diagnosis` | method | unchanged | Used as written: paired controls falsified defect 2 and narrowed defect 3 |
| `product-rd-workflow` | upstream | not-applicable | No delivery-stage gate or routing change |

## Security check (design-time four questions)

1. Caller-controllable inputs: fixture prompts and rubrics, the candidate contract, and the tested agent's own output (untrusted, fed to the judge).
2. Blast radius if abused: before the fix, a fixture or an answer could make the agent or judge run shell commands with the operator's permissions and host allow rules, or read local files; after it, the agent is limited to Read/Grep/Glob/Skill and the judge to no tools, and reads stay governed by host rules (documented residual).
3. Trust root: the CLI's own init event, not the tool's argv or the agent's claims, decides whether the boundary held.
4. Negative cases: an init event that offers Bash or any MCP tool, or that is missing, rejects the sample; a prompt asking for Bash produces no file (live check).

## Verification plan

- Local: `test_eval_runtime.py` under the repo venv (new cases RED on base, GREEN on fix); `check-ccl-skills.sh` with the private alias audit; the repo-gates and fast-regression lanes that cover these scripts; a live rerun of the write and in-cwd probes against the fixed `run_agent`.
- External: extraction review gate (review, then challenge on the fixed candidate, then one delta pass if later code changes).
- CI: the pull request's normal lanes.
