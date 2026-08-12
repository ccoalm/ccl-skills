# Watcher Discipline

Use watchers for long CI/build/deploy waits, but keep them bounded and read-only by default.

Watcher rules:

- Start only for a named object: MR/PR, pipeline, job, deploy, rollout, or health check.
- Record object id/ref/SHA and expected stop states.
- Poll with a timeout and a clear interval.
- Stop on success, failure, canceled, manual/action-required, timeout, or object replacement.
- Never play jobs, retry jobs, merge, push tags, mutate config, or delete branches from a watcher unless separately authorized for that exact action.
- Reconcile watcher output in the main release report; do not claim completion from a stale background result without a fresh read-back when the action is sensitive.

If a watcher times out, report the last observed state and the next safe action instead of continuing unbounded polling in the main thread.
