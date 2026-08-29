# AI Service Wiring Patterns

Use this for Python implementation around LLM/RAG/inference calls after `llm-inference-integration` has defined the inference behavior.

## Wiring

- Keep provider adapters separate from route handlers and domain orchestration.
- Add timeout, retry, rate limit, circuit-breaker/backpressure, and cost/usage logging where needed.
- Handle streaming with cancellation, heartbeat, and terminal error events.
- Persist request, response, citation/source, and audit metadata only according to product privacy rules.
- For CPU/GPU-heavy local inference, isolate concurrency and memory limits.
- Use fakes for provider tests and mark live provider tests explicitly.

## Streaming And Session Mechanics

- Reject a new turn while a prior turn for the same session/conversation is in-flight: check-and-claim the session at the boundary (lock or idempotency marker) and return a typed busy error; do not silently interleave two generations into one conversation state.
- Persist partial state on a timer during long streams (partial transcript, token counts) so a crash mid-stream can resume or at least account for cost; the cadence is a product decision, the mechanism belongs here.
- Close stream readers deterministically on every exit path — client disconnect, deadline, terminal error — via async context managers or cancellation handlers, or provider connections leak until pool exhaustion.
- Record token/cost usage after completion, or on terminal failure with the partial count, never only at request start; tie the usage record to the same request/session id the logs carry.
- Mark terminal vs recoverable stream states explicitly (completed / cancelled / provider-error / resumable); a consumer that cannot distinguish them retries unresumable streams.

## Do Not

- Encode prompt policy, retrieval strategy, evaluation rubric, or model routing here; route those decisions to `llm-inference-integration`.
