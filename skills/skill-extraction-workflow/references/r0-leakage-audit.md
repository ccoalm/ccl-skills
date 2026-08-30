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

### Shared Git and PR text

Git history and forge metadata are shared publication surfaces even when the
repository files are clean. The repository-owned
`skills/skill-extraction-workflow/scripts/shared_git_surface_gate.py` therefore
scans the exact candidate commit range, current branch name, and available PR
title/body text for AI session links or identifiers, model session/co-author
trailers, AI author/committer identities, generated footers,
conversation-process labels, and external-source provenance wording. Common
Markdown list (including GFM task lists), quote, heading, and nested wrappers
are presentation only and do not bypass any line-oriented class. The gate
reports only surface, locator, and category so neither a finding nor an error
diagnostic repeats the identifier, ref, path, or raw tool error it is blocking.
Candidate commit metadata is requested from Git as UTF-8 regardless of the
repository's ambient log-output encoding. Invalid UTF-8 or a Unicode
replacement character fails closed with only the commit locator and field
name, rather than silently erasing a CJK-only match. Each candidate's bounded
raw commit object is also checked before pretty formatting; an embedded NUL is
rejected because Git would otherwise truncate the visible message at that byte.
The batch response is length-parsed and bound one-for-one to the separately
enumerated full object IDs; abbreviated diagnostic locators are never used for
identity or ordering decisions.
`--repo` is the single repository identity. Every Git subprocess drops ambient
repository-routing variables that could replace its worktree, refs, object
store, ancestry, index, or namespace; a caller cannot point the gate at a clean
decoy with `GIT_DIR` while the prohibited candidate lives elsewhere. This gate
is a worktree pre-push/CI lane, not a receive-pack quarantine, so quarantine
object-store overrides are not accepted.
All object reads disable local replacement refs, which alter only the local
view and are not the bytes a push publishes. A non-empty legacy
`info/grafts` file likewise fails closed because it can rewrite the visible
parent chain without changing the commit objects sent by a push.

The base priority is explicit `--base-ref`, then the trusted PR event, then
`CCL_SKILL_BASE_REF`, then a repository-declared default; an unresolved selected
base is an error. The trusted event outranks ambient environment configuration
so a CI process variable cannot silently move the base forward and narrow the
event-defined candidate range. Only
history outside the selected `<merge-base>..<candidate-head>` range may be
`known_debt`; the merge-base itself is target-side history and is not a candidate
commit. Candidate commits, the current destination branch, and current PR text
have zero exceptions, including a violation hidden in an earlier candidate
commit behind a clean HEAD. CI runs the gate on direct pushes to `dev`/`main`
and on PR `edited` events because title/body changes do not require a new
commit. Before a PR is created or edited, pass its exact proposed title and
body through `--pr-text-file`; a local run with neither an event nor that file
has checked no PR text. The optional pre-push hook is early feedback; the
protected CI check is the merge boundary.

The repository command fallback `origin/dev` applies only to the normal
feature→dev lane. Promotion or any other target passes that target explicitly
(for example, `--base-ref origin/main` for dev→main); a default is not evidence
of the intended landing target. The pre-push hook uses an existing destination ref's remote SHA
as its base only when that destination is an actual landing target (`dev` or
`main`); ambient `CCL_SKILL_BASE_REF` cannot replace that SHA. The environment
base may delimit a new zero-OID landing target. Every non-delete pushed ref is
scanned at its own local object ID and destination name without checking it
out. An ordinary feature ref always uses an explicitly bound landing target or
the pushed remote's `dev` tracking ref; if that ref is absent, fetch it or set
`CCL_SKILL_BASE_REF`. Its existing remote feature tip is still candidate history
and must never become the base/`known_debt`. A new
`dev`/`main` destination without an explicit base fails closed. Provider aliases
are shared across the provider-shaped
surface patterns, but unknown future AI providers remain an enumerated-pattern
coverage risk; the shared prose prohibition is broader than the currently
recognized provider names.

Co-author detection also has an intentional precision boundary. An
unambiguous product display name such as `Claude Code` or `Codex`, a bounded
model/product-qualified form such as `Claude Sonnet`, `OpenAI Codex`, or
`ChatGPT-5`, or a known
provider GitHub App account carrying the `[bot]` suffix, is blocked with any
email. Account matching accepts GitHub slug separators, so `claude-code[bot]`
and `copilot-swe-agent[bot]` remain the same known-provider class. A known
provider `[bot]` account in the email local part is also sufficient when the
display name is neutral, with only the standard optional numeric GitHub ID
prefix accepted before that exact account. A provider token embedded as a
suffix inside another bot account is not treated as the provider. An exact
single-name alias that can also be a person's name needs an independent
`noreply`/`no-reply`/`bot` email signal. This keeps a human whose
real name matches an alias from being mechanically rejected, but it also means
an AI trailer that deliberately uses such an ambiguous name plus an ordinary
email is not detectable from the trailer alone. The root prohibition still
applies; proposed text with that ambiguity needs human readback rather than a
claim that the local gate proved every model co-author absent. Candidate author
and committer fields use a narrower rule: only unambiguous product names,
known-provider `[bot]` display names, or known-provider `[bot]` email accounts
with only an optional numeric GitHub ID prefix are blocked. A generic `noreply`
address is a normal human privacy setting there, so an ambiguous single-name
identity remains an explicit human-readback coverage gap; unrelated automation
bots and accounts that only end in a provider token are not reclassified as AI.

The current deterministic event surface does not fetch historical PR comments,
labels, or a platform-generated custom merge message. Those remain prohibited
by the root contract, but are an explicit coverage gap requiring forge-side
readback/enforcement; they are not reclassified as `known_debt` merely because
this local scanner cannot observe them. A pushed tag is scanned on every
surface the object graph carries: destination name, pointed-to commit range,
and each annotated tag-object layer's own message and tagger identity (nested
tags are peeled with a bounded depth, and an unresolvable or over-deep tag
chain fails closed).

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
