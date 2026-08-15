# npm release

`@ccoalm/ccl-skills` is the only npm package for this repository. Releases are immutable, tag-driven, and built once in GitHub Actions from the tagged commit.

## One-time setup

Before the first release, complete these external controls:

1. Confirm that the repository and packed artifact both carry the Apache License 2.0 and that `package.json` declares the SPDX identifier `Apache-2.0`. Review third-party attribution before every release and add a `NOTICE` file when attribution material requires it.
2. Ensure the `ccoalm` npm account or organization owns `@ccoalm/ccl-skills`, requires two-factor authentication for maintainers, and has at least two maintainers for recovery.
3. Configure the package's npm Trusted Publisher with these exact values:
   - provider: GitHub Actions
   - organization or user: `ccoalm`
   - repository: `ccl-skills`
   - workflow filename: `npm-publish.yml`
   - environment: `npm`
   - allowed action: `npm publish`
4. Protect the GitHub `npm` environment with required reviewers, and restrict creation of `ccl-skills-v*` tags to release maintainers.

Trusted Publisher settings live on the npm package settings page. If npm does not expose that page before the package exists, the initial namespace bootstrap is a separate, explicitly authorized release operation: publish once with a human-controlled, two-factor-authenticated or short-lived granular credential, configure Trusted Publishing immediately, then revoke the bootstrap credential. Never add that credential to the workflow.

## Release contract

- The version in `packages/ccl-skills-npm/package.json` and `package-lock.json` is the source of truth. Releases currently accept only stable `MAJOR.MINOR.PATCH` versions; prerelease identifiers fail before build and publish.
- The release tag is exactly `ccl-skills-v<version>` and points to the reviewed commit on the protected default branch.
- `.github/workflows/npm-publish.yml` checks the tag, runs the full package and tarball tests, verifies `release.json` against the tagged SHA, and publishes that exact tarball through OIDC.
- No release job uses a long-lived npm token or dependency cache.
- Commit, push, merge, tag creation, npm configuration, and publication remain separate authorizations.

Local release rehearsal does not publish:

```bash
make npm-publish-dry
```

## Post-release verification

Verify registry metadata and install from a clean temporary HOME:

```bash
npm view @ccoalm/ccl-skills version dist.integrity repository --json
npx @ccoalm/ccl-skills@<version> --version
```

Then run the three-host lifecycle smoke with the published tarball or exact version. Confirm the npm package page shows provenance from `ccoalm/ccl-skills` and the expected workflow.

## Bad release

Published npm versions are immutable and cannot be reused. Prefer a fixed patch release and deprecate the bad version with a message that names the replacement:

```bash
npm deprecate @ccoalm/ccl-skills@<bad-version> "Use <fixed-version>: <reason>"
```

Unpublish only when the current npm unpublish policy allows it and a release owner explicitly approves it. Moving a dist-tag, deprecating, or unpublishing is an external registry mutation and is never implied by a code change.
