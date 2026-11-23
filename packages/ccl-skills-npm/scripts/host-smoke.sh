#!/usr/bin/env bash
set -Eeuo pipefail
umask 022
stage=bootstrap
on_error(){ rc=$?; trap - ERR; printf 'host-smoke failed at stage=%s exit=%s\n' "$stage" "$rc" >&2; exit "$rc"; }
trap on_error ERR
pkg_dir=$(cd "$(dirname "$0")/.." && pwd)
repo_root=$(cd "$pkg_dir/../.." && pwd)
command -v codex >/dev/null || { echo "codex missing" >&2; exit 4; }
command -v claude >/dev/null || { echo "claude missing" >&2; exit 4; }
command -v opencode >/dev/null || { echo "opencode missing" >&2; exit 4; }
command -v agy >/dev/null || { echo "agy missing" >&2; exit 4; }
command -v git >/dev/null || { echo "git missing" >&2; exit 4; }
tmp=$(mktemp -d); cleanup(){ rm -rf "$tmp"; }; trap cleanup EXIT
mkdir -p \
  "$tmp/home/.codex" \
  "$tmp/home/.config" \
  "$tmp/home/.local/share" \
  "$tmp/home/.local/state" \
  "$tmp/home/.cache" \
  "$tmp/workspace" \
  "$tmp/install-v1" \
  "$tmp/install-v2"
export HOME="$tmp/home"
export CODEX_HOME="$tmp/home/.codex"
export XDG_CONFIG_HOME="$tmp/home/.config"
export XDG_DATA_HOME="$tmp/home/.local/share"
export XDG_STATE_HOME="$tmp/home/.local/state"
export XDG_CACHE_HOME="$tmp/home/.cache"
unset npm_config_allow_scripts NPM_CONFIG_ALLOW_SCRIPTS OPENCODE_CONFIG OPENCODE_CONFIG_DIR OPENCODE_CONFIG_CONTENT CCL_SKILLS_REPO
# Scrub host profile/plugin overrides and Git routing/config overrides so the
# smoke never reads or mutates caller state or resolves another repository.
unset exported           # an inherited export would pass the list to every child
exported=$(compgen -e)   # an assignment, so set -e stops the smoke if this fails
for var in $exported; do
  case "$var" in
    CLAUDE_CONFIG_DIR|CLAUDE_CODE_PLUGIN_*|OPENCODE_CONFIG*|GIT_DIR|GIT_WORK_TREE|GIT_IMPLICIT_WORK_TREE|GIT_INDEX_FILE|GIT_COMMON_DIR|GIT_NAMESPACE|GIT_OBJECT_DIRECTORY|GIT_ALTERNATE_OBJECT_DIRECTORIES|GIT_CEILING_DIRECTORIES|GIT_DISCOVERY_ACROSS_FILESYSTEM|GIT_GRAFT_FILE|GIT_SHALLOW_FILE|GIT_NO_REPLACE_OBJECTS|GIT_REPLACE_REF_BASE|GIT_PREFIX|GIT_INTERNAL_SUPER_PREFIX|GIT_QUARANTINE_PATH|GIT_GLOB_PATHSPECS|GIT_NOGLOB_PATHSPECS|GIT_LITERAL_PATHSPECS|GIT_ICASE_PATHSPECS|GIT_EXTERNAL_DIFF|GIT_DIFF_OPTS|GIT_TEMPLATE_DIR|GIT_CONFIG|GIT_CONFIG_*)
      unset "$var"
      ;;
  esac
done
export GIT_CONFIG_NOSYSTEM=1
export GIT_CONFIG_GLOBAL=/dev/null
export GIT_CONFIG_SYSTEM=/dev/null
export NPM_CONFIG_USERCONFIG="$tmp/home/.npmrc"
export NPM_CONFIG_CACHE="$tmp/npm-cache"
export npm_config_userconfig="$tmp/home/.npmrc"
export npm_config_cache="$tmp/npm-cache"
export CCL_SKILLS_SKIP_SELF_UPDATE=1

stage_tracked_source() {
  node - "$repo_root" "$1" <<'EOF'
const { execFileSync } = require("node:child_process");
const { chmodSync, cpSync, lstatSync, mkdirSync } = require("node:fs");
const { dirname, join } = require("node:path");
const [repo, dest] = process.argv.slice(2);
const sourceRoots = [
  ".claude-plugin",
  ".codex-plugin",
  ".antigravity-plugin",
  "hooks.json",
  "agent-context",
  "skills",
  "hooks",
  "packages/opencode-plugin",
  "scripts/owner-dispatch",
  ".worktree-only",
  "packages/ccl-skills-npm",
];
const out = execFileSync("git", ["-C", repo, "ls-files", "--stage", "-z", "--", ...sourceRoots], { encoding: "buffer" });
const entries = out.toString("utf8").split("\0").filter(Boolean);
if (!entries.length) throw new Error("tracked runtime closure is empty");
for (const rec of entries) {
  const tab = rec.indexOf("\t");
  const gitMode = rec.slice(0, tab).split(" ")[0];
  const rel = rec.slice(tab + 1);
  const mode = gitMode === "100644" ? 0o644 : gitMode === "100755" ? 0o755 : null;
  if (tab < 0 || mode === null) throw new Error("unsupported git mode: " + (rel || rec));
  const src = join(repo, rel);
  const st = lstatSync(src);
  if (!st.isFile() || st.isSymbolicLink() || st.nlink !== 1) {
    throw new Error("tracked source entry is not a single-link regular file: " + rel);
  }
  const dst = join(dest, rel);
  mkdirSync(dirname(dst), { recursive: true });
  cpSync(src, dst);
  chmodSync(dst, mode);
}
EOF
}

if [ -n "${TGZ_PATH:-}" ]; then
  stage=actual-artifact
  test -f "$TGZ_PATH"
  mkdir -p "$tmp/artifact-install"
  (cd "$tmp/artifact-install" && npm install --ignore-scripts "$TGZ_PATH" >/dev/null)
  artifact_cli="$tmp/artifact-install/node_modules/@ccoalm/ccl-skills/dist/cli.js"
  if artifact_json=$(node "$artifact_cli" doctor --host codex --json); then artifact_rc=0; else artifact_rc=$?; fi
  [ "$artifact_rc" = 3 ] || { echo "actual artifact doctor expected exit 3, got $artifact_rc: $artifact_json" >&2; exit 1; }
  grep -q '"status":"absent"' <<< "$artifact_json"
  if agy_artifact_json=$(node "$artifact_cli" doctor --host antigravity --json); then agy_artifact_rc=0; else agy_artifact_rc=$?; fi
  [ "$agy_artifact_rc" = 3 ] || { echo "actual artifact antigravity doctor expected exit 3, got $agy_artifact_rc: $agy_artifact_json" >&2; exit 1; }
  grep -q '"status":"absent"' <<< "$agy_artifact_json"
  printf '%s\n' '{"status":"actual-artifact-cli-passed"}'
fi

for version in 1.0.0 2.0.0; do
  stage="synthetic-$version-source"
  source="$tmp/source-$version"
  source_pkg="$source/packages/ccl-skills-npm"
  mkdir -p "$source"
  stage_tracked_source "$source"
  stage="synthetic-$version-version"
  (cd "$source_pkg" && npm version "$version" --no-git-tag-version --allow-same-version >/dev/null)
  synthetic_commit="$(printf '%040d' "${version%%.*}")"
  (cd "$source" && git init -q && git add . && git -c user.name=smoke -c user.email=smoke@example.invalid commit -qm "synthetic $version")
  printf 'packages/ccl-skills-npm/node_modules/\npackages/ccl-skills-npm/dist/\n' >> "$source/.git/info/exclude"
  stage="synthetic-$version-dependencies"
  (cd "$source_pkg" && npm ci >/dev/null)
  stage="synthetic-$version-build"
  (cd "$source_pkg" && CI=true CI_COMMIT_SHA="$synthetic_commit" npm run build >/dev/null && REQUIRE_CLEAN_RELEASE=1 EXPECT_SOURCE_COMMIT="$synthetic_commit" node scripts/verify-packed.mjs dist/assets >/dev/null)
  stage="synthetic-$version-pack"
  tgz=$(cd "$source_pkg" && npm pack --silent); mv "$source_pkg/$tgz" "$tmp/package-$version.tgz"
  stage="synthetic-$version-install"
  (cd "$tmp/install-v${version%%.*}" && npm install --ignore-scripts "$tmp/package-$version.tgz" >/dev/null)
done

cli_v1="$tmp/install-v1/node_modules/@ccoalm/ccl-skills/dist/cli.js"
cli_v2="$tmp/install-v2/node_modules/@ccoalm/ccl-skills/dist/cli.js"
stage=install-v1
if install_json=$(node "$cli_v1" install --host codex --json); then install_rc=0; else install_rc=$?; fi
[ "$install_rc" = 3 ] || { echo "install expected exit 3, got $install_rc: $install_json" >&2; exit 1; }
grep -q 'installed-hooks-pending' <<< "$install_json"
codex_markets=$(codex plugin marketplace list)
grep -q '^ccl-skills-npm ' <<< "$codex_markets"
codex_plugins=$(codex plugin list)
grep -q '^ccl-skills@ccl-skills-npm ' <<< "$codex_plugins"
old_root=$(awk '$1 == "ccl-skills-npm" { print $2 }' <<< "$codex_markets")
stage=update-v2
if update_json=$(node "$cli_v2" update --host codex --yes --json); then update_rc=0; else update_rc=$?; fi
[ "$update_rc" = 3 ] || { echo "update expected exit 3, got $update_rc: $update_json" >&2; exit 1; }
codex_markets_v2=$(codex plugin marketplace list)
new_root=$(awk '$1 == "ccl-skills-npm" { print $2 }' <<< "$codex_markets_v2")
[ "$old_root" != "$new_root" ] || { echo "update did not switch marketplace root" >&2; exit 1; }
printf '%s\n' "source-switch: old=$(basename "$(dirname "$old_root")") new=$(basename "$(dirname "$new_root")")"
stage=doctor-v2
if doctor_json=$(node "$cli_v2" doctor --host codex --json); then doctor_rc=0; else doctor_rc=$?; fi
[ "$doctor_rc" = 3 ] && grep -q 'installed-hooks-pending' <<< "$doctor_json"
stage=uninstall-v2
codex_uninstall_json=$(node "$cli_v2" uninstall --host codex --yes --json)
grep -q '"status":"uninstalled"' <<< "$codex_uninstall_json"
stage=verify-public-absence
codex_markets_after=$(codex plugin marketplace list)
! grep -q '^ccl-skills-npm ' <<< "$codex_markets_after"
codex_plugins_after=$(codex plugin list)
! grep -q '^ccl-skills@ccl-skills-npm ' <<< "$codex_plugins_after"

stage=claude-install-v1
claude_install_json=$(node "$cli_v1" install --host claude --json)
grep -q '"status":"installed"' <<< "$claude_install_json"
claude_list_json=$(claude plugin list --json)
grep -q 'ccl-skills@ccl-skills-npm' <<< "$claude_list_json"
stage=claude-update-v2
claude_update_json=$(node "$cli_v2" update --host claude --yes --json)
grep -q '"status":"updated"' <<< "$claude_update_json"
claude_doctor_json=$(node "$cli_v2" doctor --host claude --json)
grep -q '"status":"healthy"' <<< "$claude_doctor_json"
stage=claude-uninstall-v2
claude_uninstall_json=$(node "$cli_v2" uninstall --host claude --yes --json)
grep -q '"status":"uninstalled"' <<< "$claude_uninstall_json"
claude_list_after=$(claude plugin list --json)
! grep -q 'ccl-skills@ccl-skills-npm' <<< "$claude_list_after"

stage=opencode-install-v1
opencode_install_json=$(node "$cli_v1" install --host opencode --json)
grep -q '"status":"installed"' <<< "$opencode_install_json"
expected_skills=$(find "$tmp/install-v1/node_modules/@ccoalm/ccl-skills/dist/assets/marketplace/plugins/ccl-skills/skills" -mindepth 2 -maxdepth 2 -name SKILL.md | wc -l | tr -d ' ')
[ "$(find "$HOME/.config/opencode/skills" -mindepth 1 -maxdepth 1 -type d | wc -l | tr -d ' ')" = "$expected_skills" ]
for runtime_asset in hooks/hooks.json hooks/guard-merge-authorization.sh hooks/merge-authorization-prompt.sh agent-context/subagent-start.md scripts/owner-dispatch/owner-dispatch.sh; do
  test -f "$HOME/.config/opencode/ccl-skills/runtime/$runtime_asset"
done
stage=opencode-plugin-load-v1
opencode_config="$tmp/opencode-config.json"
(cd "$tmp/workspace" && opencode debug config) >"$opencode_config"
node -e '
const fs = require("node:fs");
const config = JSON.parse(fs.readFileSync(process.argv[1], "utf8"));
if (!Array.isArray(config.plugin) || !config.plugin.some((entry) =>
  typeof entry === "string" && entry.endsWith("/plugins/ccl-skills.ts"))) {
  process.exit(1);
}
' "$opencode_config"
stage=opencode-update-v2
opencode_update_json=$(node "$cli_v2" update --host opencode --yes --json)
grep -q '"status":"updated"' <<< "$opencode_update_json"
opencode_doctor_json=$(node "$cli_v2" doctor --host opencode --json)
grep -q '"status":"healthy"' <<< "$opencode_doctor_json"
stage=opencode-uninstall-v2
opencode_uninstall_json=$(node "$cli_v2" uninstall --host opencode --yes --json)
grep -q '"status":"uninstalled-shared-retained"' <<< "$opencode_uninstall_json"
[ -f "$HOME/.config/opencode/skills/product-rd-workflow/SKILL.md" ]

stage=antigravity-install-v1
agy_install_json=$(node "$cli_v1" install --host antigravity --json)
grep -q '"status":"installed"' <<< "$agy_install_json"
agy_list_json=$(agy plugin list --json)
grep -q '"name"[[:space:]]*:[[:space:]]*"ccl-skills"' <<< "$agy_list_json"
test -f "$HOME/.gemini/config/plugins/ccl-skills/.antigravity-plugin/plugin.json"
test -f "$HOME/.gemini/ccl-skills-npm/install-receipt.json"
stage=antigravity-update-v2
agy_update_json=$(node "$cli_v2" update --host antigravity --yes --json)
grep -q '"status":"updated"' <<< "$agy_update_json"
agy_doctor_json=$(node "$cli_v2" doctor --host antigravity --json)
grep -q '"status":"healthy"' <<< "$agy_doctor_json"
grep -q '"version"[[:space:]]*:[[:space:]]*"2.0.0"' "$HOME/.gemini/ccl-skills-npm/install-receipt.json"
stage=antigravity-uninstall-v2
agy_uninstall_json=$(node "$cli_v2" uninstall --host antigravity --yes --json)
grep -q '"status":"uninstalled"' <<< "$agy_uninstall_json"
agy_list_after=$(agy plugin list --json)
! grep -q '"name"[[:space:]]*:[[:space:]]*"ccl-skills"' <<< "$agy_list_after"
test ! -e "$HOME/.gemini/config/plugins/ccl-skills"
test ! -e "$HOME/.gemini/ccl-skills-npm/install-receipt.json"

printf '%s\n' '{"status":"four-host-smoke-passed","codexHooks":"native-plugin-registered","openCodeHooks":"plugin-registered","openCodeSharedFiles":"retained","antigravityPlugin":"native-plugin-registered"}'
