# Pre-Draft Example Domain Selection

A complement to R0 (`references/r0-leakage-audit.md`). R0 catches **identifier leakage** at audit time (a name's role lifted from source); this rule preempts **scenario-domain leakage** at drafting time. Without pre-draft selection, the R0 example-identifier audit fires repeatedly on bare common nouns drawn from the workspace's source-domain shape — and rework is more expensive than upfront choice.

## Why Scenario-Domain Leakage Happens

The R0 example-identifier audit fires on bare common nouns drawn from the workspace's source-domain shape — transaction / membership / payment vocabulary in a commerce workspace, stage / grade / curriculum vocabulary in an education workspace, claim / billing / policy vocabulary in an insurance workspace. The reason: *scenario-domain shape* (entities + verbs + invariants) reads as source-shaped to adversarial review even when identifiers are sanitized.

## Two-Axis Substitution — Not Interchangeable

The two leakage classes need two different substitution disciplines:

| Axis | Leakage class | Substitution discipline |
|---|---|---|
| **R0 placeholder** (`Acme*` / `Foo*` / `sample*`) | identifier leakage — a name's role lifted from source | Replace the identifier at audit / review time |
| **Pre-draft domain selection** | scenario-domain leakage — entities + verbs + invariants together read as source-shaped | Choose scenario domain BEFORE drafting examples |

`AcmeOrderService` is identifier-clean but scenario-leaked if "Order" is the source domain. **Apply both axes.** Neither alone is sufficient.

## Threshold — When Pre-Selection Is REQUIRED

Pre-selection is REQUIRED whenever the changed extraction unit contains an **example set**, defined as:

- Two or more new / edited examples total across the changed files, OR
- Any multi-line / code-fence example

Only when the changed unit has at most ONE new / edited one-line example total may the canonical placeholder pattern (`Acme*` / `Foo*` / `sample*`) be used without pre-selection.

**Anti-bypass rule**: agents cannot split examples across separate one-liners and claim each is individually exempt. The threshold is cumulative across the changed extraction unit.

## How To Pick A Neutral Domain

**"Neutral" is relative to the source artifact, not the whole workspace.**

- **Source artifact** = the specific corpus / file / design / code slice being mined for THIS extraction. Not the workspace as a whole.
- In generic or multi-domain repos, "neutral" means a domain distant from THAT source artifact's domain, not the whole repo.

Suggested neutral domains (file export retention, auth / token flow, document preview, generic ordered list) are *examples, not safe defaults*. In a SaaS workspace, auth / export themselves can read source-shaped — choose a domain distant from BOTH the workspace business model AND the changed skill's target.

## Validation Row — Durable, Not Chat-Only

For any non-wording extraction (as defined in the dual-track gate) that includes new examples, record this row in the durable extraction trace (commit message body, source map, or per-host scratch artifact per `references/source-to-skill-extraction.md`):

```
example-domain preselect: selected=<domains>; rejected source domain=<the workspace domain>; changed examples checked=<file:line>
```

Without the durable row, pre-selection is unverifiable and the work is `interim`. Final-chat-only rows do not satisfy the gate.

## Row Accuracy — Not Just Durability

The row must accurately describe what is in the changed content. Claiming "no concrete domain examples used" while the changed bullet still contains literal source-domain vocabulary fails the gate even if the row is durable.

- Reread the changed lines before writing the row.
- Verify each `rejected source domain=` claim against actual diff content.

## Narrate The Rejected Domain Abstractly

Write the row as:

```
rejected source domain=[the workspace's primary business domain literal vocabulary]
```

Do NOT write:

```
rejected source domain=[finance / commerce / education / etc literal vocabulary]
```

Naming the workspace's industry category in the row body propagates a soft domain hint into commit messages and other durable traces (observed recurring). The row records THAT a domain was rejected, not WHICH.

## Relationship To Adversarial Review

Pre-draft selection reduces the rework cycle; it does NOT replace the safety net.

- Codex / adversarial review remains the safety net per the R0 rule.
- Pre-selection is *input* to adversarial review, not a substitute for it.
- Passing pre-selection does not authorize skipping the dual-track gate.
