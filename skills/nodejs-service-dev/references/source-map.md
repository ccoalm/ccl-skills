# Maintainer Source Map

Inspected 2026-08-30. This file records provenance and extraction limits; it is not required reading for ordinary Node.js implementation work.

## Primary Node.js and npm sources

| Decision surface | Inspected source | Extracted constraint |
|---|---|---|
| production runtime | [Node.js releases](https://nodejs.org/en/about/previous-releases), [release schedule](https://github.com/nodejs/Release/blob/main/schedule.json), [2026 schedule announcement](https://nodejs.org/en/blog/announcements/evolving-the-nodejs-release-schedule) | production uses supported LTS; live schedule beats memorized odd/even rules; Node.js 27 begins the announced annual model |
| packages/modules | [Packages API](https://nodejs.org/api/packages.html) | make module intent explicit; ambiguous `.js` syntax detection is not a project contract |
| TypeScript | [TypeScript API](https://nodejs.org/api/typescript.html) | built-in stripping is stable on documented lines but performs no type checking, ignores `tsconfig`, and supports erasable syntax only |
| tests | [Test runner API](https://nodejs.org/api/test.html), [CLI API](https://nodejs.org/api/cli.html) | `node:test` is capable but individual coverage/CLI features remain version-gated; preserve the repo runner and verify the supported matrix |
| concurrency/context | [Worker threads](https://nodejs.org/api/worker_threads.html), [async context](https://nodejs.org/api/async_context.html) | workers suit CPU-intensive JavaScript, not ordinary I/O; prefer optimized `AsyncLocalStorage` over custom `async_hooks` context machinery |
| event loop / DoS | [Don't block the event loop](https://nodejs.org/en/learn/asynchronous-work/dont-block-the-event-loop) | long event-loop or worker-pool work reduces throughput and can create denial-of-service paths |
| cancellation/streams | [Global Abort APIs](https://nodejs.org/api/globals.html), [Streams API](https://nodejs.org/api/stream.html) | propagate cancellation to underlying work; pipeline/backpressure owns teardown for large data |
| fatal errors / shutdown | [Process API](https://nodejs.org/api/process.html), [HTTP API](https://nodejs.org/api/http.html) | unknown uncaught failures are not safe recovery points; connection-closing behavior is version- and protocol-sensitive |
| diagnostics | [Heap snapshots](https://nodejs.org/en/learn/diagnostics/memory/using-heap-snapshot), [flame graphs](https://nodejs.org/en/learn/diagnostics/flame-graphs) | performance claims need profiles/measurements; heap snapshots can stop the main thread and exhaust memory |
| security | [Node.js security best practices](https://nodejs.org/en/learn/getting-started/security-best-practices) | bound input work, harden dependencies, and use runtime permissions only as defense in depth |
| reproducible install / provenance | [npm ci](https://docs.npmjs.com/cli/v11/commands/npm-ci/), [npm provenance](https://docs.npmjs.com/generating-provenance-statements) | frozen lockfile install is the verification contract; provenance proves origin/build linkage, not code safety |

## Independent industry controls

- [OWASP NodeJS Security Cheat Sheet](https://cheatsheetseries.owasp.org/cheatsheets/Nodejs_Security_Cheat_Sheet.html): used to challenge missing web/runtime security axes. Framework- or version-specific prescriptions were not copied without Node.js primary-source support.
- [OpenSSF npm supply-chain guidance](https://openssf.org/blog/2022/09/01/npm-best-practices-for-the-supply-chain/): used to challenge lockfile, install-script, dependency, CI, and provenance handling. Supply-chain release governance remains routed to existing CCL owners.
- [Node.js Best Practices](https://github.com/goldbergyoni/nodebestpractices): broad practitioner checklist consulted as coverage input only; its July 2024 edition and library preferences are not treated as current runtime authority.

## Evaluation-method sources

- [Anthropic, Demystifying evals for AI agents](https://www.anthropic.com/engineering/demystifying-evals-for-ai-agents): grounds the split between a task's inputs and success criteria, multiple trials for variable outputs, combined code/model/human graders, and review of both outcomes and transcripts. This supports separate routing and body-effect measurements; it does not make either one a merge gate.
- [OpenAI, How evals drive the next chapter in AI for businesses](https://openai.com/index/evals-drive-next-chapter-of-ai/): grounds the specify → measure → improve loop and contextual evals tied to the actual workflow rather than generic benchmark scores.
- [OpenAI, A shared playbook for trustworthy third party evaluations](https://openai.com/index/trustworthy-third-party-evaluations-foundations/): grounds binding claims to the tested system, harness, task distribution, budget, elicitation method, and validity checks. A skill-content result must therefore identify the exact skill snapshot and host conditions it tested.
- [On Randomness in Agentic Evals](https://arxiv.org/abs/2602.07150): large-sample evidence that agent trajectories vary even at temperature zero; a future effectiveness claim needs repeated independent trials and uncertainty, not one favorable answer.
- [Judging the Judges: A Systematic Study of Position Bias in LLM-as-a-Judge](https://aclanthology.org/2025.ijcnlp-long.18/): supports balanced answer order and human inspection for pairwise model judgments. An LLM preference is advisory evidence, not an oracle.

## Extraction limits

- This is a source-backed design, not proof that every rule improves agent behavior in production. The deterministic RED/GREEN baseline proves discovery/routing registration and repository conformance only.
- The Node.js body fixtures freeze tasks and rubrics for later paired evaluation. Until repeated with/without runs bind the same model, host, tools, budget, skill snapshot, and blind grading procedure, their result class remains `insufficient-evidence`.
- Runtime and CLI stability can change. The skill deliberately tells the agent to resolve the live release/support matrix instead of hardcoding Node.js 24/26.
- Framework-specific internals were not generalized. Express, Fastify, NestJS, Hono, and other frameworks retain their repository-local lifecycle and security contracts.
- No peer-skill text was copied as authoritative runtime guidance; public peer skills were used for structure and collision analysis, while technical claims were checked against primary Node.js/npm sources. Snapshot details stay in the extraction register rather than the distributed runtime skill.
