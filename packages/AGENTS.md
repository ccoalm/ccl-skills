# packages Agent Contract

`packages/` holds everything this repository ships to other machines: the two
npm distribution shells (`codex-npm`, `opencode-npm`) and the standalone
OpenCode plugin source (`opencode-plugin`). The boundary is *distributable*, not
*npm package* — a subdirectory belongs here when its content is copied or
published to a host outside this checkout.

Rules:

- Do not put host-convention directories here. `.claude-plugin/`,
  `.codex-plugin/`, `.opencode/` and `opencode.json` stay at the repository root
  because their location is pinned by the host, not by us.
- This is not an npm workspace. The repository root has no `package.json` and no
  `workspaces` field; a non-package subdirectory here breaks no build.
- Build steps copy source assets out of the repository. When a source path
  moves, update the copying script in the same change — a stale source path
  fails the build, but a stale *destination* name silently ships the wrong
  layout.
- Installed artifact names are a separate contract from repository paths.
  `agent-context/session-start.md` ships as `bootstrap.md` on purpose: uninstall
  manifests and the installed plugin runtime key on that name.

Validation:

- `make npm-verify`, `make npm-pack-dry`, `make codex-npm-pack-verify`
- `bash skills/skill-extraction-workflow/scripts/check-ccl-skills.sh .`
