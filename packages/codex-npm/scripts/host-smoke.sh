#!/usr/bin/env bash
set -Eeuo pipefail
stage=bootstrap
on_error(){ rc=$?; trap - ERR; printf 'host-smoke failed at stage=%s exit=%s\n' "$stage" "$rc" >&2; exit "$rc"; }
trap on_error ERR
pkg_dir=$(cd "$(dirname "$0")/.." && pwd)
command -v codex >/dev/null || { echo "codex missing" >&2; exit 4; }
version=$(codex --version); printf '%s\n' "$version" | grep -Eq '0\.(13[3-9]|1[4-9][0-9])\.|[1-9][0-9]*\.' || { echo "Codex >=0.133.0 required: $version" >&2; exit 4; }
tmp=$(mktemp -d); cleanup(){ rm -rf "$tmp"; }; trap cleanup EXIT
mkdir -p "$tmp/home/.codex" "$tmp/workspace" "$tmp/install-v1" "$tmp/install-v2"
export HOME="$tmp/home"
export CODEX_HOME="$tmp/home/.codex"
unset npm_config_allow_scripts NPM_CONFIG_ALLOW_SCRIPTS
export NPM_CONFIG_USERCONFIG="$tmp/home/.npmrc"
export NPM_CONFIG_CACHE="$tmp/npm-cache"
export npm_config_userconfig="$tmp/home/.npmrc"
export npm_config_cache="$tmp/npm-cache"
if [ -n "${TGZ_PATH:-}" ]; then
  stage=actual-artifact
  test -f "$TGZ_PATH"
  mkdir -p "$tmp/artifact-install"
  (cd "$tmp/artifact-install" && npm install --ignore-scripts "$TGZ_PATH" >/dev/null)
  artifact_cli="$tmp/artifact-install/node_modules/@ccoalm/ccl-skills-codex/dist/cli.js"
  if artifact_json=$(node "$artifact_cli" doctor --json); then artifact_rc=0; else artifact_rc=$?; fi
  [ "$artifact_rc" = 3 ] || { echo "actual artifact doctor expected exit 3, got $artifact_rc: $artifact_json" >&2; exit 1; }
  printf '%s' "$artifact_json" | grep -q '"status":"absent"'
  printf '%s\n' '{"status":"actual-artifact-cli-passed"}'
fi
for version in 1.0.0 2.0.0; do
  stage="synthetic-$version-source"
  source="$tmp/source-$version"; source_pkg="$source/packages/codex-npm"; mkdir -p "$source_pkg"; cp -R "$pkg_dir"/. "$source_pkg/"; rm -rf "$source_pkg/node_modules" "$source_pkg/dist" "$source_pkg"/*.tgz
  for asset in .codex-plugin agent-context/session-start.md skills hooks scripts/owner-dispatch .worktree-only; do mkdir -p "$(dirname "$source/$asset")"; cp -R "$pkg_dir/../../$asset" "$source/$asset"; done
  stage="synthetic-$version-version"
  (cd "$source_pkg" && npm ci >/dev/null && npm version "$version" --no-git-tag-version --allow-same-version >/dev/null)
  rm -rf "$source_pkg/node_modules"
  synthetic_commit="$(printf '%040d' "${version%%.*}")"
  if command -v git >/dev/null 2>&1; then
    (cd "$source" && git init -q && git add . && git -c user.name=smoke -c user.email=smoke@example.invalid commit -qm "synthetic $version")
    printf 'packages/codex-npm/node_modules/\n' >> "$source/.git/info/exclude"
  fi
  stage="synthetic-$version-dependencies"
  (cd "$source_pkg" && npm ci >/dev/null)
  stage="synthetic-$version-build"
  (cd "$source_pkg" && CI=true CI_COMMIT_SHA="$synthetic_commit" npm run build >/dev/null && REQUIRE_CLEAN_RELEASE=1 EXPECT_SOURCE_COMMIT="$synthetic_commit" node scripts/verify-packed.mjs dist/assets >/dev/null)
  stage="synthetic-$version-pack"
  tgz=$(cd "$source_pkg" && npm pack --silent); mv "$source_pkg/$tgz" "$tmp/package-$version.tgz"
  stage="synthetic-$version-install"
  (cd "$tmp/install-v${version%%.*}" && npm install --ignore-scripts "$tmp/package-$version.tgz" >/dev/null)
done
cli_v1="$tmp/install-v1/node_modules/@ccoalm/ccl-skills-codex/dist/cli.js"
cli_v2="$tmp/install-v2/node_modules/@ccoalm/ccl-skills-codex/dist/cli.js"
stage=install-v1
if install_json=$(node "$cli_v1" install --json); then install_rc=0; else install_rc=$?; fi
[ "$install_rc" = 3 ] || { echo "install expected exit 3, got $install_rc: $install_json" >&2; exit 1; }
printf '%s' "$install_json" | grep -q 'installed-hooks-pending'
codex plugin marketplace list | grep -q '^ccl-skills-npm '
codex plugin list | grep -q '^ccl-skills@ccl-skills-npm '
old_root=$(codex plugin marketplace list | awk '$1 == "ccl-skills-npm" { print $2 }')
stage=update-v2
if update_json=$(node "$cli_v2" update --yes --json); then update_rc=0; else update_rc=$?; fi
[ "$update_rc" = 3 ] || { echo "update expected exit 3, got $update_rc: $update_json" >&2; exit 1; }
new_root=$(codex plugin marketplace list | awk '$1 == "ccl-skills-npm" { print $2 }')
[ "$old_root" != "$new_root" ] || { echo "update did not switch marketplace root" >&2; exit 1; }
printf '%s\n' "source-switch: old=$(basename "$(dirname "$old_root")") new=$(basename "$(dirname "$new_root")")"
stage=doctor-v2
if doctor_json=$(node "$cli_v2" doctor --json); then doctor_rc=0; else doctor_rc=$?; fi
[ "$doctor_rc" = 3 ] && printf '%s' "$doctor_json" | grep -q 'installed-hooks-pending'
stage=uninstall-v2
node "$cli_v2" uninstall --yes --json | grep -q '"status":"uninstalled"'
stage=verify-public-absence
! codex plugin marketplace list | grep -q '^ccl-skills-npm '
! codex plugin list | grep -q '^ccl-skills@ccl-skills-npm '
printf '%s\n' '{"status":"host-smoke-passed","trust":"pending-unverified"}'
