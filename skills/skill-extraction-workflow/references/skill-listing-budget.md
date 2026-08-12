# Claude Code skill-listing budget — mechanism, cold-start trap, levers

Companion to the **budget-dropped** Core Rule in `SKILL.md` (under *Triggers, routing surfaces & isolation*). The Core Rule carries the gate (before fixing a routing miss with a trigger-word edit, check whether the description was even in the host listing; the evidence bar; the two host corollaries). This file carries the **mechanism detail and the remediation levers**. It adds no new gate.

## Mechanism

Claude Code always loads every skill *name*, but when many skills are installed it collapses the *descriptions* of the **least-invoked** skills to bare name-only to fit a skill-listing budget (default ~1% of the context window via `skillListingBudgetFraction`). `/doctor` shows the overflow and which skills lost their description.

While an entry is name-only, **trigger-word edits are invisible to description-based routing** — the skill is still reachable by explicit `/skill-name` or by name semantics, just not by the new keywords.

## The cold-start trap

A rarely-used gate skill can spiral: never invoked → description dropped → never auto-routed → never invoked. The trigger-word edit that was supposed to fix routing has no effect because the description it edits is not in the listing.

## Levers (once confirmed name-only)

- **Raise `skillListingBudgetFraction`** — applies to ALL skills incl. plugins, but it is a global per-turn context/cost tradeoff, not a default fix.
- **Disable unused plugins** via `/plugin` — note `skillOverrides: name-only` does NOT apply to plugin skills (personal/project only).
- **Invoke the skill once** — a single invocation lifts it out of the least-invoked set.
