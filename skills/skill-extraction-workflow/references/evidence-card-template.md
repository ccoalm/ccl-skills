# Evidence Card Template

Phase 1 material (design source: `docs/skill-extraction-optimization-design.md`). An evidence card is the lightweight, structured record produced during step 2 of the five-step analysis (see `references/l0-l1-l2-routing.md`). It keeps a conclusion from arriving before its evidence and makes a later re-check cheap.

A card is required for an L0 capture and for the short-form evidence record of an L1 change; an L2 change uses it as the entry point into the full source register.

## Template

```markdown
## Evidence Card

- Trigger / context:
- Observed failure or opportunity:
- First-hand evidence:
  - transcript / diff / test output / incident / command output:
- Reusable pattern:
- Proposed skill effect:
- Scope:
  - Applies when:
  - Does not apply when:
- Risk:
  - Routing impact: yes/no
  - Privacy/leakage risk: yes/no
  - User-authority impact: yes/no
  - Validation impact: yes/no
- Behavioral cases:
  - Should trigger:
  - Should not trigger:
- Recommended path: L0 / L1 / L2
- Owner / follow-up:
```

## Why each field exists

- **First-hand evidence** blocks extraction-by-vibe: a transcript, diff, test output, incident, or command output must exist before any RCA. "An LLM said so" is hypothesis-grade, not first-hand (see the Core Rules on LLM-consultation evidence). If the only evidence is second-hand, record the gap rather than inventing a card.
- **Applies / does not apply** keeps the rule from over-generalizing — a rule with no stated boundary tends to over-fire.
- **Should trigger / should not trigger** feed directly into behavioral regression cases for L1/L2.
- **Risk (routing / privacy / authority / validation)** decides escalation: any `yes` on routing, authorization, or validation pushes the card toward L2 (see the L2 trigger list).

## How to fill a card (abstract walkthrough — no persisted capture)

This describes HOW each field gets filled; it deliberately uses **no concrete values, no tier verdict, and no real quotes**. A real card — with filled fields and a `Recommended path` conclusion — lives in per-host scratch / a private alias and is **never persisted under `skills/**`**, so this reference keeps only the blank template above. Reading this is not a precedent for committing a card into the shared tree.

- Fill *trigger / context* with the situation that surfaced the lesson (for a process-meta case, the workflow step where it appeared).
- Fill *observed failure or opportunity* with what actually went wrong, or what could be better.
- Fill *first-hand evidence* with the concrete artifact — a transcript, diff, test output, command output, or incident — never "an LLM said so".
- Fill *reusable pattern* with the generalization, only if the case abstracts beyond itself.
- Fill *scope* with the applies / does-not-apply boundary.
- Fill *risk* by marking the routing / privacy / authority / validation axes yes or no.
- Fill *behavioral cases* by describing the should-trigger and should-not-trigger conditions (described, not transcribed).
- The *tier decision* then follows from risk: if routing, authorization, or validation reads yes, the recommended path escalates toward the higher tiers; otherwise it stays low. Record the chosen path in the private card, not here.
