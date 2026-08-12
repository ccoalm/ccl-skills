# R0 Leakage Audit — Mandatory Landing Gate

R0 is the mandatory landing gate enforced before every commit of a skill or reference change. The SKILL.md entrypoint states the rule in one sentence; this file is the operational mechanism. Sibling skills that reference "R0" route to this rule as a whole; the detail here is for the maintainer running the audit.

## What R0 Requires

Zero hits in the changed files across these categories:

- design-source file keys
- design-source URLs
- project / team identifiers
- real subproject paths or repository names
- real branch names
- contributor emails or names
- ticket or work-item ids
- internal domains or hostnames
- design-source node ids
- any non-distilled business or product nouns (in any language) that point to one specific organization rather than a reusable capability

A commit that has not run this audit, or that has not closed every hit, is not landed regardless of how the work is described.

## How To Run

The maintainer keeps one alias file per private source product at `~/.<host>/.private-aliases/<project>.yaml`:

- `<host>` is the directory chosen by the host runtime — commonly `.claude` for Claude Code or `.codex` for the Codex CLI. If multiple runtimes share the same machine, the maintainer canonicalises to one host and symlinks the others.
- `<project>` is the maintainer's short label for the private source product — typically one alias file per separate Figma / code / document corpus, named after the team or product line, never after a specific commit or release.

The alias file contains both the sanitized-label dictionary AND an `audit_cmd` block. The maintainer invokes that `audit_cmd` against the changed-file set before committing. Any non-zero hit must be either removed or explicitly recorded in the same alias file's `known_debt` list.

**Audit category definitions, scan patterns, and per-project allow-lists live ONLY in those private alias files.** Do not copy the patterns themselves into shared skill content — that would re-leak them.

### Generic process-retro profile

When the extraction source is the current task/session, a workflow failure, review/tooling behavior, or another process-retrospective source with no single private product corpus, the maintainer MUST use a generic private alias profile such as `~/.<host>/.private-aliases/process-retro.yaml` instead of hand-writing a one-off grep in chat. That profile's `audit_cmd` scans only changed shared-skill files for cross-session leakage classes: local absolute paths, real workspace/repo/worktree names, real branch names, model/session ids, internal domains/hosts/IPs, user or teammate identifiers, ticket/work-item ids, and any source-specific nouns that were observed only in the task transcript.

This generic profile is the fallback for process sources only. It does not replace a project-specific alias file when the source is a real product, Figma file, codebase, document corpus, incident, customer workflow, or team corpus. If a process-retro extraction also cites a concrete product artifact, run both the project-specific audit and the generic process-retro audit.

The closeout row must name which private profile was used: `project-alias`, `process-retro`, or `both`. If no matching alias/profile exists in the contributor's environment, the change may be committed/pushed only as `interim` (for example a Draft/WIP MR) with `R0 pending maintainer audit` recorded; it must not be marked `R0-clean`, merge-ready, or landing-clean until the private profile exists and passes, or a risk owner records an explicit waiver. An ad-hoc inline `grep` may diagnose leakage risk, but it is not the durable R0 gate for clean landing.

## known_debt Scope

Pre-existing leakage from earlier extractions may be tracked as `known_debt` in the alias YAML and explicitly excluded from blocking the current change. New or modified content MUST remain zero-hit — `known_debt` cannot waive a newly introduced label.

## Fail-Closed Clause — Maintainer Discipline

Every new sanitized label introduced in this commit (e.g. an angle-bracket capability token like `<some-capability>`, a class tier like `<class-A1>`, or any other invented short name that stands for a real source artifact) MUST exist in the maintainer's alias YAML before the commit lands.

A reference that uses a label not present in the alias file is treated as a hit, because the label is implicitly identifying to the source team and the audit cannot prove otherwise.

## Example-Identifier Clause

The audit also covers identifier-shaped tokens used as illustrative examples inside prose, code fences, anti-pattern descriptions, or rule wording — variable names, function names, class names, type names, theme-module names, file paths, package names.

When such an identifier is observed verbatim in the source codebase / design source, it carries the source's product noun into shared content even when no canonical leakage pattern in the alias YAML matches it.

The typical failure shape is a generic-looking compound name whose first half is a product role lifted verbatim from the source — a role-named theme / service / widget where the role word is the source app's name or domain.

### Two Safe Substitution Strategies

- **Generic placeholder syntax** — angle-bracket meta-token (`<AppTheme>`, `<ServiceName>`) or generic capitalized noun (`MyComponent`, `ExampleService`). Distinct from the alias-YAML-tracked sanitized label and need not be registered.
- **Clearly-fictional substitute** — names that universally read as placeholder (Acme*, Foo*, sample*) regardless of context.

Avoid any substitute that still carries a real product role.

### Adversarial Review Is The Practical Safety Net

Grep cannot detect this class of leak. Do not rely on R0 grep alone to catch source-shaped example identifiers — codex challenge or equivalent adversarial review is the practical safety net.

## Enforcement: Private Audit Is Authoritative, Generic Public Fallback Backstops It

`check-ccl-skills.sh` runs the alias-vs-label cross-check ONLY when the maintainer exports `ALIAS_AUDIT_CMD` pointing at their private audit script. That private audit is the strongest and the only clean-landing R0 evidence: it verifies every sanitized label and pattern against the private alias YAML across all file types. On success it prints `alias_audit_ok`, sets `r0_status=private-ok`, and the validator's final line is `ccl_skill_check_clean_ok`.

`ALIAS_AUDIT_CMD` is whitespace-split and executed directly as argv — it is NOT evaluated by a shell, so `;`/`&&`/pipes/substitutions in the variable have no effect (injection hardening). A leading `~/` in a word is expanded to `$HOME/` (no other shell expansion happens). Use the `<script-path> <args>` form; if the audit needs shell features, put them inside the script the variable points at.

When `ALIAS_AUDIT_CMD` is unset (a normal local machine), the validator no longer merely skips. It runs a deterministic PUBLIC fallback — `scripts/generic-r0-leak-scan.sh` — over the ADDED lines of the current git diff, restricted to shared-skill markdown surfaces (`skills/**/*.md`, `README.md`, `docs/**/*.md`, opencode command markdown). The fallback fails closed (`generic_r0_leak_scan_failed`, exit 1) on high-signal public leaks: absolute local paths (a user home directory, `/private/var/<seg>`, or a Windows drive path), RFC1918 private IPv4 literals (not loopback), internal-only hostnames (`.internal`/`.intranet`/`.corp`), and secret/token literals (key=concrete-value assignments and known vendor token prefixes). It is diff-scoped (never re-polices pre-existing known debt) and markdown-only (the private audit, not this fallback, is the comprehensive gate over scripts/YAML/other file types). On a clean run it prints `generic_r0_leak_scan_ok`, and the validator prints `alias_audit_unavailable`, `r0_status=public-fallback`, and a final line of `ccl_skill_check_interim_ok` (NOT the clean token).

**Probe before you conclude it is unset — "a normal local machine" describes the common case, it is NOT a licence to assume `ALIAS_AUDIT_CMD` is absent without checking.** Recording `alias_audit_unavailable` / choosing the public fallback is correct ONLY after you have *observed* it is actually unset. The authoritative probe is to run `check-ccl-skills.sh` and read which branch its output took (`r0_status=private-ok` vs `public-fallback`, plus the final token) — that reflects what the validator actually did and can't be asserted without producing the line; `printenv ALIAS_AUDIT_CMD` is only a quick pre-check. Treating "unset is normal" as a default and dropping straight to the interim fallback is a blocked-verification miss (the failure class: *assuming an environment-provided capability is absent because absent is common, without the one-command check* — and the priming cuts both ways: skipping the check can just as wrongly assume the audit IS there). "Configured" ≠ "works": a non-empty var means the private audit is *configured* and MUST be run, but availability is confirmed only when it actually executes and prints `alias_audit_ok`; a set-but-broken `ALIAS_AUDIT_CMD` (missing / non-executable / wrong-path script, or a run that errors) is itself a blocked-verification failure to fix or record an explicit risk-owner waiver for — it does NOT license the public fallback. Keep the two evidences distinct: the branch-read/probe gates *recording unavailable/fallback*; *asserting the private audit ran* requires the `alias_audit_ok` token, never the probe alone. (This is the R0-surface instance of the general blocked-verification rule — see the always-on R0 bullet and SKILL.md.)

The generic fallback is PUBLIC INTERIM evidence, not private-alias clean-landing evidence. It deliberately cannot detect the leaks only the private alias catches — source-shaped example identifiers, project/team nouns, real subproject/repo/branch names, ticket ids, and the maintainer's project-specific token set. So a passing fallback permits an interim commit/branch/Draft MR, but the maintainer or CI MUST still block clean merge/landing until the private audit runs clean (`alias_audit_ok`), a named private profile result is cited, or an explicit risk-owner waiver is recorded.

**Neither the deprecated `ccl_skill_check_ok`, the interim `ccl_skill_check_interim_ok`, nor `generic_r0_leak_scan_ok`/`alias_audit_unavailable` satisfies clean-landing R0.** The validator now ends on a machine-distinguishable token: `ccl_skill_check_clean_ok` (with `r0_status=private-ok`) only when the private alias audit ran clean, and `ccl_skill_check_interim_ok` (with `r0_status=public-fallback`) when only the public fallback ran. It still prints a deprecated `ccl_skill_check_ok` line for backward-compatible consumers, but that line is no longer the last line and no longer a sufficient clean-landing signal. The `r0_status=` line is an auxiliary R0 hint, not an overall validator-pass signal: it can appear before later blocking gates run, so clean-landing evidence still requires exit 0 plus the final `ccl_skill_check_clean_ok` token (or a named private-profile result / waiver in the review record). A reviewer who reads only the deprecated token, who treats `r0_status=private-ok` alone as a full pass, who treats `ccl_skill_check_interim_ok` as clean, or who treats the generic fallback as if it were the private audit, will mistake a run that never executed the private alias audit (or a later-failing run) for a clean R0 pass. Treat `alias_audit_unavailable` / `ccl_skill_check_interim_ok` anywhere in the output as **private R0 not run** — the change is `interim` / missing-clean-landing-evidence regardless of the trailing tokens and regardless of a clean generic fallback. That state may be committed or opened as a Draft/WIP MR only when the commit/MR record clearly says `R0 pending maintainer audit`; it must not be merged or described as landing-clean. A closeout or review record may cite R0 as satisfied ONLY when it cites `alias_audit_ok` (the private audit actually ran and found zero hits), a named private-profile result (`project-alias`, `process-retro`, or `both`, per the generic process-retro profile section above), or an explicit risk-owner waiver. A record that cites `ccl_skill_check_ok`, `ccl_skill_check_interim_ok`, `r0_status=private-ok`, or `generic_r0_leak_scan_ok` alone while the output shows `alias_audit_unavailable` is invalid clean-landing R0 evidence and must be redone with `ALIAS_AUDIT_CMD` exported (the output must exit 0 and show final `ccl_skill_check_clean_ok`) before the change can be called landing-clean.

## R0 vs Other Audits

- R0 is the leakage gate (this file). Failure class: source-domain content escapes into shared skills.
- Pre-draft example domain selection (see `references/example-domain-preselect.md`) preempts retroactive R0 cleanup cycles by choosing scenario domain before drafting examples.
- Two-source extraction adds source-specific category extensions on top of R0; see `references/two-source-extraction-pattern.md`.
- Incident / postmortem extraction adds incident-specific category extensions on top of R0; see `references/incident-postmortem-extraction.md`.
- Recurring anti-patterns checklist (see `references/recurring-anti-patterns-checklist.md`) is an orthogonal gate covering structural anti-patterns; it does NOT replace R0.
