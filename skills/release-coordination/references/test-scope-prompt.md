# Test Scope Prompt Handoff

After release scope is confirmed, emit a test-scope prompt that helps reviewers and QA see what must be proved before release. This is a handoff, not a full test strategy.

Build the prompt from the confirmed release diff:

- **Capability scope**: user-visible behavior, API/contract changes, admin/operator workflows, compatibility paths.
- **Operational scope**: config/defaults, migrations, scripts, jobs, workers, queues, dependencies, external integrations, deploy changes.
- **Risk scope**: auth/permission, tenant/user isolation, data mutation, money/quota, async finality, irreversible actions, high-traffic or degraded-mode paths.
- **Regression scope**: touched modules, direct consumers, known adjacent paths, frozen past failures, rollback-sensitive paths.
- **Evidence gaps**: layers not yet run, live-only checks, unavailable environments, manual smoke owners.

Output shape:

```text
Test-scope prompt:
- Must-cover capabilities: ...
- Operational checks: ...
- Regression focus: ...
- Suggested smoke: ...
- Requires testing-strategy handoff: yes/no, because ...
```

Route to `testing-strategy` when the user needs test-layer selection, scenario matrix, fixture/mock policy, E2E versus integration decisions, executable test code, or CI gate design. Do not mark release verification complete from this prompt alone.
