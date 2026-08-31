# R&D Standards Doc Family Checklist

Use this checklist for R&D standards, specs, guidelines, or Feishu/wiki doc families before marking docs done.

## Checklist

1. Classify the layer: overview/index, product or requirements Spec, stack/service guideline, repo-local execution Spec, ADR, checklist, or evidence report.
2. If any child doc, second stack/service, or cross-doc product-goal reference exists, create or update a parent overview/index first and link child docs.
3. Scope evidence must name the parent node(s) or repo scope searched, include the product Spec surface checked, list candidate child locations, and attach concrete enumeration evidence: command/output, node list, or two independent manual passes listing parent index URL plus each checked child node title/link when no programmatic tool exists. If scoped evidence is absent, mark `blocked: family enumeration unverified`, with no sign-off.
4. Only when step 3 evidence shows zero child docs may a single existing doc be treated as its own overview/index; cite that evidence and record its path/link and authority statement.
5. Multi-doc families require an authority statement plus sync-gate rule before child docs are marked done.
6. If the family defines any implementation, stack, service, client, CI, harness, release, or QA norm, include or update a testing standard child doc. It must cover test deliverables, unit/contract/integration/E2E/manual layers, harness, CI gates, high-risk coverage, evidence format, and stack handoff; route the template to `testing-strategy`.
7. If the family will drive project health checks, add a conformance appendix or sibling checklist that maps each rule to `deterministic`, `agent_review`, `manual`, or `not_automatable_yet`, with severity, evidence, command/prompt owner, and CI behavior. Route architecture fitness functions to `testing-strategy`; route directory-contract coverage to `agents-file-coverage-gate`; route stack mechanics to the owning stack skills.
8. Before invoking `tighten-doc`, record `owner-ready` with the authority statement, doc-family layer, enumeration evidence, and conformance mapping evidence when applicable, or `blocked: family enumeration unverified`.
9. Re-confirm the doc-set enumeration at completion/sign-off, or add the sync gate if the family has grown.
10. Layer authority and write-back: when an execution-layer doc (runbook, repo-local execution Spec, checklist) conflicts with its governing Spec/guideline, the Spec wins the ruling AND the execution doc is corrected in the same change; when the execution doc is outside the change's write scope (other repo/owner), record the correction as a routed follow-up with an owner before treating the ruling as landed — a ruling without write-back (or a routed owner) re-creates the drift on the next read. Superseded rules inside a living doc are marked deprecated **with a date** and a replacement pointer, not silently deleted, so a reader can tell "current" from "was once true" (append-only ledgers keep their own stricter rules).

## Architecture / System-Overview Honesty Pass

For an architecture or system-overview doc, one that describes how an already-built system works, run a current-state-honesty pass before sign-off:

- For each load-bearing "enforced / automated / already does X" maturity claim, record claim → evidence source → status (`implemented`, `convention-or-target`, or `unknown`) verified against real code, CI, or hooks. Non-load-bearing prose does not trigger a repo audit.
- Give a diagram for nontrivial multi-component runtime, dependency, or data-flow concepts where prose alone would mislead. A simple doc may record one doc-level "diagram not needed".
- Align terminology to a named external standard only when the doc invokes one.
- Frame any "advanced" or "best-practice" claim as alignment with an external standard plus honest gaps, never as self-praise of own components.
- The independent review must check claims against the real repository, including code, CI, and hooks, not only wording. A wording-only review can pass prose that misstates system maturity.

This is the substance/honesty axis. Readability and jargon are the `tighten-doc` axis; run both.
