# Release Closeout Evidence

Do not say “release complete” unless the required evidence surfaces for this release have been read back.

Closeout report sections:

- **Completed**: action → read-back evidence.
- **Waiting / blocked**: object/status → next required action or authorization.
- **Production state**: tags, pipelines/jobs, images/digests, deployments, config/runtime, worker state, and smoke/log/metric evidence actually inspected.
- **Deferred / intentionally not done**: scripts, workers, queues, flags, migrations, or integrations not enabled or not run, with residual risk.
- **Required user decisions**: exact MR/tag/job/config/resource plus current id/SHA/status.

Evidence depth labels:

- `read-back`: platform/API/CLI state was inspected.
- `runtime-verified`: running workload or behavior was checked.
- `documented-only`: release doc says so, but runtime/platform proof was not inspected.
- `not-run`: explicitly not executed.

Partial evidence is acceptable only when labeled honestly with the missing surfaces.
