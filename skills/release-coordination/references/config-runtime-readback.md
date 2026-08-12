# Config and Runtime Read-back

Production config/resource mutation belongs to `platform-release-engineering`; this coordinator only enforces the release-sequence and evidence gate.

Before any live config/resource change:

- Re-read the release document decision.
- Inspect current state read-only first.
- Identify only the intended key/resource/workload delta.
- Never print Secret values.
- Prefer key presence, value class, hash, revision, or effective-env proof over dumping full config.

For file-mounted or env-injected config, distinguish evidence layers:

1. Source key exists.
2. Deployment/runtime surface receives it.
3. Pod/container/process has the effective value or file.
4. The application behavior/log/metric confirms the process consumed it.

For worker decisions, keep multi-replica API pods separate from singleton/dedicated worker lanes, and read back replicas, image/digest, readiness, and relevant config key presence after rollout.
