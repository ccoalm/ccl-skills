# @ccoalm/ccl-skills-codex

npm-managed local marketplace installer for CCL Skills on Codex. The package includes its runtime assets, so installation does not require a Git checkout.

## Requirements

- Node.js 20 or later
- Codex 0.133.0 or later
- macOS or Linux

## Commands

```bash
npx @ccoalm/ccl-skills-codex install
npx @ccoalm/ccl-skills-codex@latest doctor
npx @ccoalm/ccl-skills-codex@latest update
npx @ccoalm/ccl-skills-codex@latest update --yes
npx @ccoalm/ccl-skills-codex@latest uninstall
npx @ccoalm/ccl-skills-codex@latest uninstall --yes
```

`update` and `uninstall` are previews unless `--yes` is supplied. A downgrade also requires `--allow-downgrade`.

The CLI validates the local marketplace registration and files recorded in its ownership manifest. It does not edit Codex configuration, cache, or hook-trust settings. Confirm hook trust in Codex when the command reports `installed-hooks-pending`.

## Build and test

```bash
npm ci
npm test
npm run build
```
