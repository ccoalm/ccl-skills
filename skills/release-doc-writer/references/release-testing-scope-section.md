# Release Testing Scope Section

When writing a release document, include a testing-scope section whenever the document has release scope, verification, or handoff sections.

Derive it from confirmed diff evidence, not branch names or memory. If `release-coordination` already produced a test-scope prompt, import it and adapt it to the document structure.

Recommended fields:

- **Must-cover capabilities**: changed user journeys, APIs/contracts, admin/operator paths, compatibility modes.
- **Operational checks**: config/defaults, migrations, scripts, jobs, workers, queues, dependencies, external integrations, deploy surfaces.
- **Regression focus**: touched modules, direct consumers, adjacent paths, frozen past failures, rollback-sensitive paths.
- **Smoke suggestions**: minimal pre-release/post-release smoke needed for confidence.
- **Open gaps**: live-only checks, unavailable environments, manual owners, or items needing `testing-strategy`.

Do not write the testing-scope section as verification evidence. Verification evidence must cite actual runs or observations. If the user asks for layer choice, scenario matrix, mocks/fixtures, E2E versus integration choice, executable tests, or CI gate design, route to `testing-strategy`.
