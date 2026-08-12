# Extraction Lifecycle Handoff

The SKILL.md entrypoint states the principle: project-specific provenance never enters the shared skill tree. This file is the operational mechanism: what lives where in each lifecycle phase, what migrates between phases, what the shared-repo history (commits, branch refs, and the MR/PR record) is allowed to say, and how to handle existing dirty registers.

Sibling skills routing to "Extraction lifecycle handoff" (e.g. `python-service-architecture / dev`, `go-microservice-architecture / dev` source-evidence-map files) route to this rule as a whole.

## The Three Phases

| Phase | Lives in | Contents |
|---|---|---|
| **Work in progress** | per-host scratch `~/.<host>/skills/.extraction-work/` | charters tied to one Figma project / one codebase / one document set, source registers populated with that project's file keys and paths, batch findings, extraction reports, review packets, codex replies |
| **Closed batch — provenance archive** | per-host private alias `~/.<host>/.private-aliases/<project>.yaml` | file keys, project URLs, real subproject paths, real branches, dated re-extraction logs, known-debt list, sanitized-label dictionary |
| **Shared skill tree** | the ccl-skills repo | label-based capability rules only |

Working artifacts are NEVER committed to the shared skill tree. The shared tree only sees the rules abstracted from the work, not the work itself.

## Migration — Scratch → Private Alias

Once an extraction batch closes, its provenance migrates from the scratch folder into the private alias file:

- File keys, project URLs, real subproject paths, real branches, dated re-extraction logs, known-debt list all move into `~/.<host>/.private-aliases/<project>.yaml`.
- The matching shared-skill content keeps only label-based capability rules — no concrete artifact names, paths, or dates.
- The scratch folder can be deleted or kept for the maintainer's own reference; either way, the shared skill tree must not know it existed.

## Shared VCS-Surface Discipline (commit, branch, MR record)

Every shared surface the integration flow creates names only:

- The sanitized capability labels touched
- The target skill / reference path
- The private alias archive that holds the provenance (by alias label, not by real project name)

This applies to the commit message(s), the **feature branch name**, the eventual **merge/squash message**, and the **entire MR/PR record** (title, body, comments/discussion, labels/metadata) — not the commit body alone. Never name real source artifacts (real repo names, real Figma project names, real document titles, real branch/ticket names, real contributor names) in any of them. Git history, branch refs, and the MR record are all the shared skill tree's history — a sanitized commit under a source-shaped branch name or MR title still leaks, and leaks here are as severe as leaks in skill text. When unsure whether a surface is shared, treat it as shared and sanitize.

## R0 Audit Scope

The R0 leakage audit (see `references/r0-leakage-audit.md`) runs against the shared-skill content, NOT against the working artifacts in scratch. Scratch is the maintainer's private workspace; R0 has no jurisdiction there. R0's jurisdiction begins at the commit boundary into the shared repo.

## Generic Methodology Carve-Out

A generic, reusable register / template / methodology reference (one that documents the *shape* of charters, registers, evidence maps, or judgment matrices without naming any specific project's keys / paths) MAY live in the shared skill tree.

**Example**: a `references/source-register.md` that is a template / sample is allowed; it may also carry a source-neutral ledger zone, as long as it describes reusable columns, methodology, and shared impact-chain history without containing any project's actual rows.

The distinction is **shape vs content**: shape-documenting refs are shared, content-bearing artifacts are private.

## Grandfather Rule — Existing Dirty Registers

Any existing in-skill register that already contains real project provenance (concrete file keys, dated re-extraction logs, real repo names) is grandfathered as `known_debt`. It can stay in place temporarily but:

- It MUST be migrated to a private alias file before new project-specific provenance is added to it.
- Adding fresh project provenance to a grandfathered register is treated as a new R0 hit, not protected by the grandfather status.
- The grandfather status is for cleanup planning, not for indefinite tolerance.

## Authoring From a Plugin / Read-Only Install

When the workflow is consumed as a plugin (or any read-only install mechanism), skills load from a consumption cache, not from an editable checkout. To land an extraction you must author in the canonical source repo — and that repo is discoverable from the install itself, so do not guess a path or edit the wrong copy:

- **Discover the source URL from the install.** The plugin/marketplace registration that shipped with the install records it: the marketplace clone's git remote (`git -C <marketplace-clone> remote get-url origin`), the marketplace `source.url` in the host's plugin config/registry, and the install URLs documented in the consuming project's README each help identify the canonical repo. Cross-check them rather than trusting one — a README can be stale or absent, and an install/marketplace URL can differ from the canonical source repo (e.g. http vs ssh, or a mirror).
- **Author in one standing checkout — clone once, reuse.** Clone that URL a single time (or reuse an existing checkout) and reuse it for every later extraction. Do not clone per change.
- **Never edit the consumption copies.** The plugin cache and the marketplace-managed clone are overwritten on update; edits there are lost and never reach the repo. Author only in your own checkout, then land through the normal review/MR gates.
- **Isolate each change with a worktree, not a clone.** Make every extraction in a dedicated worktree off the standing checkout — worktrees share the object store and are not full repo copies — and remove it once the change lands (`git worktree remove`). This meets the concurrent-session isolation rule without proliferating repo copies.
- **Accumulation is consumption-side, not authoring.** Plugin caches on some hosts keep one directory per installed version, so old version dirs can linger after updates — unrelated to authoring. Prune them with the host's plugin prune command if disk matters.

After landing, the change reaches every install through the normal update path (marketplace refresh + plugin update); the exact update command lives in the consuming project's README, not in the shared skill tree.
