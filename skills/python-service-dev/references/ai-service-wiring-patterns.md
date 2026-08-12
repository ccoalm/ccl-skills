# AI Service Wiring Patterns

Use this for Python implementation around LLM/RAG/inference calls after `llm-inference-integration` has defined the inference behavior.

## Wiring

- Keep provider adapters separate from route handlers and domain orchestration.
- Add timeout, retry, rate limit, circuit-breaker/backpressure, and cost/usage logging where needed.
- Handle streaming with cancellation, heartbeat, and terminal error events.
- Persist request, response, citation/source, and audit metadata only according to product privacy rules.
- For CPU/GPU-heavy local inference, isolate concurrency and memory limits.
- Use fakes for provider tests and mark live provider tests explicitly.

## Do Not

- Encode prompt policy, retrieval strategy, evaluation rubric, or model routing here; route those decisions to `llm-inference-integration`.
