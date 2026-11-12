# Method Grounding (Maintainer Source Map)

Read 2026-11-11. This file records which public sources the entry's method was checked against and what each check found. It is provenance, not required reading for design work: the rules live in `SKILL.md` and `service-design-rules.md`.

Each source below was opened and the cited passage read before the row was written. A row says what the source supports and where the skill's rule is narrower or broader than it. "Later candidate" marks something a source recommends that this skill does not yet require; it is recorded so a later round can decide on evidence, and is not a rule here.

## Scope of the claim

- The rules predate this check. They came from service code and delivery experience, and the sources were used afterwards to confirm, narrow, or contradict them. No rule was added because a source recommends it.
- A source supports the sentence it is cited for and nothing wider. Citing a pattern page does not adopt the rest of that author's method.
- No source contradicted a rule in this pass.

## Industry practice

| Method step | Rule checked | Source | Finding |
|---|---|---|---|
| 1 Boundary | Split a deployable service only for ownership, scaling, data, isolation, cadence, or rollback reasons; otherwise a modular monolith is valid | [Monolith First](https://martinfowler.com/bliki/MonolithFirst.html) (Fowler, 2015) | Confirmed. The author reports that almost all successful microservice stories he had heard of began as a monolith that was later split, and almost all systems he had heard of that were built as microservices from scratch ran into serious trouble. It is one practitioner's observation over the cases he heard of, not a measured result |
| 1 Boundary | Boundaries follow ownership and language, not technical layers; system structure follows communication structure | Bounded Context, Conway's Law, Hexagonal — cited with their borrowing limits in `go-architecture-playbook.md` and `python-architecture-playbook.md` | Already recorded there; not re-derived here |
| 2 Contracts | Evolve additively; never break field numbers | [Proto Best Practices](https://protobuf.dev/best-practices/dos-donts/) | Confirmed. The page says to reserve the tag numbers of deleted fields so they are never reused. Later candidate: reserving deleted field names as well |
| 3 Data | Each service owns its write model and schema; cross-service reads go through an API or read model | [Database per service](https://microservices.io/patterns/data/database-per-service.html) (Richardson) | Confirmed, and it narrows a common misreading: private tables or a private schema satisfy the pattern, a separate database server is not required. Later candidate: a database-level barrier (a per-service database user with grants) so the boundary is enforced rather than agreed |
| 4 Runtime | A state change that also publishes a message records both atomically (outbox); consumers are idempotent | [Transactional outbox](https://microservices.io/patterns/data/transactional-outbox.html) (Richardson) | Confirmed for that case only: the page publishes a message if and only if the database transaction commits, and states the relay may publish more than once, so the consumer must be idempotent. The skill's wider rule — durable side effects need atomic audit/outbox evidence *or* an explicit reconciliation/repair workflow — is local policy; this source supports the outbox alternative, not the requirement that every side effect use one |
| 4 Runtime | Config is environment-specific; secrets never live in code | [The Twelve-Factor App: Config](https://12factor.net/config) | Confirmed on strict separation of config from code. This skill is stricter on one point: Twelve-Factor stores config in environment variables, while the rule here resolves secrets through a secret provider and never from committed files |
| 4 Runtime | Shutdown deregisters, drains in-flight work, and exits in bounded time | [The Twelve-Factor App: Disposability](https://12factor.net/disposability) | Confirmed for the web process (stop listening, finish current requests, exit) and for workers (return the job to the queue). The page assumes requests last a few seconds; the capability-closure rule covers the case where they do not |
| 4 Runtime | Admission control — rate limits, load shedding, backpressure — is part of reliability design | [Handling Overload](https://sre.google/sre-book/handling-overload/) (Google SRE book, ch. 21) | Confirmed. The chapter treats degraded responses, per-customer limits, and client-side throttling as design work, not an afterthought |
| 4 Runtime | Internal trust rests on workload identity, not network location | [NIST SP 800-207, Zero Trust Architecture](https://csrc.nist.gov/pubs/sp/800/207/final) | Confirmed. The abstract states that no implicit trust is granted based solely on physical or network location |
| 6 Decision record | Record assumptions, alternatives, tradeoffs, acceptance checks, rollback, and handoffs | [Documenting Architecture Decisions](https://cognitect.com/blog/2011/11/15/documenting-architecture-decisions) (Nygard, 2011) | Compatible. Nygard's record has title, context, decision, status, and consequences; this skill's fields cover context, decision, and consequences and add acceptance checks and handoffs. Later candidate: the status field and the rule that a reversed decision is kept and marked superseded |
| 6 Decision record | State tradeoffs between quality needs | [ISO/IEC 25010 quality model](https://iso25000.com/index.php/en/iso-25000-standards/iso-25010); [ATAM collection](https://www.sei.cmu.edu/library/architecture-tradeoff-analysis-method-collection/) (SEI) | Compatible. ISO/IEC 25010 supplies a vocabulary of product quality characteristics; ATAM is a structured technique for understanding architectural tradeoffs. Later candidate: naming the quality characteristic each tradeoff concerns. Only the collection page was read, so nothing here relies on ATAM's detailed steps |
| Node.js / TypeScript | TypeScript types are erased at run time; keep a real type-check gate | [Node.js: Modules: TypeScript](https://nodejs.org/api/typescript.html) | Confirmed. Node.js strips erasable TypeScript syntax, performs no type checking, and ignores `tsconfig.json` |
| Node.js / TypeScript | Keep event-loop callbacks short; move measured CPU work off the request path | [Don't Block the Event Loop](https://nodejs.org/en/learn/asynchronous-work/dont-block-the-event-loop) | Confirmed. The remaining Node.js rules are derived from `nodejs-service-dev`, whose own source map lists their primary sources |

## Theory

| Method step | Rule checked | Source | Finding |
|---|---|---|---|
| 1 Boundary | Split by ownership and by what must be able to change independently, not by noun count or processing steps | Parnas, "On the Criteria To Be Used in Decomposing Systems into Modules", CACM 15(12), 1972 | Confirmed. The paper argues it is almost always incorrect to begin decomposition from a flowchart, and proposes starting from a list of difficult design decisions or decisions likely to change, each hidden inside one module. Later candidate: asking each proposed service to name the decision it hides |
| 4 Runtime | Prefer idempotency and durable acceptance over retry-only designs; do not assume a transaction spans services | Helland, "Life beyond Distributed Transactions: an Apostate's Opinion", CIDR 2007 | Confirmed. The paper holds that atomic transactions cannot span separately scaled scopes, that applications therefore live with at-least-once messaging, and that the recipient must remember processed messages so that a retry is harmless |
| 4 Runtime | End-to-end delivery guarantees are an application property | Saltzer, Reed, Clark, "End-to-End Arguments in System Design" — cited in `event-driven-architecture.md` | Already recorded there; not re-derived here |

## Skill form

| Property | Source | Finding |
|---|---|---|
| Entry carries trigger, routing, and the walk-list; detail is in references one level down | [Skill authoring best practices](https://platform.claude.com/docs/en/agents-and-tools/agent-skills/best-practices) (Anthropic) | Conforms. The checklist asks for a `SKILL.md` body under 500 lines, a description that says what the skill does and when to use it, references one level deep, and workflows with clear steps |
| Description length | Same | Conforms. The documented limit is 1,024 characters; this repository caps descriptions at 800 |

## Limits

- This pass checked rules against sources; it did not measure whether an agent using the skill designs better. That is a separate evaluation.
- Sources reflect their publication dates. The Node.js pages describe behavior that changes by release line; resolve the live documentation for the deployed line instead of relying on this table.
- Later candidates are unreviewed. Each needs its own evidence that it changes a design outcome before it becomes a rule.
