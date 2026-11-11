# Product-rd and stack dev skill usage audit

This round measures which parts of `product-rd-workflow` and the stack implementation skills agents actually load, read and cite in daily development, and turns that into a slimming proposal. It edits no skill text; the proposal goes to the owner for review before any change.

## Charter

| Field | Decision |
| --- | --- |
| Purpose | Prevent process text from crowding out engineering-hazard guidance at the moment code is written, without dropping a gate that actually holds. Local evidence: `product-rd-workflow` (73 KB entrypoint) was loaded before the first edit in 24 of 39 daily-development sessions with review, while the go, python and node implementation skills were loaded before the first edit in 9 to 11; the most frequent reported P0/P1 classes were failure paths, concurrency and retry/idempotency, which the implementation skills cover and the coordinator mostly does not. |
| Scope | In: `product-rd-workflow` (`SKILL.md` and `references/`), `go-microservice-dev`, `python-service-dev`, `nodejs-service-dev`, and the always-on routing line in `agent-context/session-start.md` that sends work to them. Source classes: every local Claude transcript on this machine (2026-10-21 to 2026-10-23, its whole history), the skills' own section structure, test pins and hooks that reference their text. Out: editing any skill text (later step, after owner review); `code-review` and `testing-strategy` slimming; the review-budget trial; other users' machines. Not an iterative program, so no `covered-through` watermark applies. |
| Depth | Node/artifact inventory: section-level census of loads, reads and citations, plus the mechanical anchors (pins, hooks, always-on references) per section. No skill edit. |
| Result classification | Failure/correction. The owner reported that agent-written code still carries many problems and asked whether the skills help; the review-result counts (P0/P1 classes) and load counts above support it. |
| Matching analysis | Widened RCA, each factor a hypothesis this census tests: (1) routing: the always-on layer sends nearly all delivery work through the coordinator first, and the implementation skills are reached later or not at all; (2) stale process model: each correction appended a gate, so the coordinator grew while its share of engineering content fell; (3) missing feedback: nothing measures whether a loaded section is applied; (4) detection over prevention: hazards are found by review after the code exists; (5) attention budget: joint satisfaction of many co-resident rules degrades (`references/external-practice-controls.md#instruction-following-mechanisms`). Counterfactual to test: if a section is never read, cited or pinned across a broad enough corpus, removing it from the entrypoint would not change observed behavior. Prevention is chosen only after the census. |
| Failure mode or success boundary | Weak extraction would delete a load-bearing gate because its read count is low: read count is not value, and a gate that fires through a hook or pin may never be "read" yet still hold. It would also mistake "loaded" for "applied", or count reads of a section that only the always-on layer quotes. A single-user, three-day corpus from a few repositories cannot show rare-but-critical paths (release, destructive change); those sections are judged by mechanism, not frequency. |
| Lifecycle impact | Implementation (primary), product intent and design (coordinator gates), testing (routing to `testing-strategy`), launch (release routing), onboarding (entrypoint readability). Use without source access: not applicable, these are agent skills. |
| Evidence plan | (1) Section inventory of each in-scope `SKILL.md` and its references (headings, bytes). (2) Transcript census: Skill tool loads, Read/Bash reads of skill files and line ranges, grep hits inside skill files, and assistant text that quotes a section heading or rule anchor, per session, before and after the first source edit. (3) Mechanical anchors: test pins, hooks and always-on lines that quote each section. (4) Review-result categories already counted (P0/P1 classes). Excluded this round with reason: Codex transcripts (different record format; pending); other users' sessions (unavailable). External grounding: not applicable, the claim is about this repository's own usage, not industry practice. |
| Completion standard | A census table per section (loads, reads, citations, anchors), a keep / merge / move-to-reference / delete proposal per section with a draft zero-loss obligation map, and the owner's review of that proposal. No dual-track gate is owed for this step because no skill text changes; the later edit step owes the full gate. |

## Target-output map

| Owner | Direction | Status | Reason |
| --- | --- | --- | --- |
| product-rd-workflow | self | pending | Proposal only this round. |
| go-microservice-dev, python-service-dev, nodejs-service-dev | downstream executors | pending | Census decides whether their firing point moves earlier. |
| agent-context/session-start.md | always-on routing | pending | Routing line may change with the proposal. |
| code-review, testing-strategy | siblings | routed | Out of scope this round; same method applies later. |
| skill-extraction-workflow | process owner | unchanged | Its attention-budget rules already exist; the census may add evidence for them. |
| feature-risk-router | upstream | unchanged | Not affected by a usage census. |
