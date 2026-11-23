# AGENTS.md

`scripts/` contains deterministic build, pack-verification, and isolated host-smoke helpers.

## Directory contract

- Build the runtime closure only from tracked files selected by the explicit allowlist; never recursively copy the working tree.
- Produce and verify one exact tgz artifact before CI publishes that same artifact; keep source commit, file hashes, and registry integrity bound together.
- Keep scripts non-interactive and fail closed on malformed metadata, unexpected file types, path escapes, or missing host capabilities.
- Use temporary `HOME`, `CODEX_HOME`, and `XDG_*_HOME` directories and unset `CLAUDE_CONFIG_DIR`, every `CLAUDE_CODE_PLUGIN_*` variable, `OPENCODE_CONFIG*`, `CCL_SKILLS_REPO`, ambient `GIT_*` variables, and outer CI / release-binding variables (`CI`, `CI_*`, `GITHUB_*`, `GITLAB_CI`, `EXPECT_SOURCE_COMMIT`, `REQUIRE_CLEAN_RELEASE`, and peer CI indicators) for host smoke; never mutate the user's real Codex, Claude, OpenCode, or Antigravity state.
- Stage the host smoke's synthetic source from tracked regular files under the same top-level roots as `build-assets.mjs`.
- Never print registry credentials, auth configuration, secrets, or machine-local private data.

## Validation

- Run `npm test` (including `test/host-smoke.test.mjs`) and `npm run test:pack` from `packages/ccl-skills-npm/` after changing build, pack, or smoke scripts.
- Run `npm run smoke:host` after changing host lifecycle behavior.
