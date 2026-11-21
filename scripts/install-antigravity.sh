#!/usr/bin/env bash
# Install or refresh ccl-skills as a native Antigravity plugin from this checkout.
#
#   bash scripts/install-antigravity.sh            # install / refresh
#   bash scripts/install-antigravity.sh --dry-run  # show what would happen
#
# Antigravity reads .antigravity-plugin/plugin.json and the root hooks.json, so
# `agy plugin install` loads the tree natively (no Claude-extension conversion).
# Only the tracked runtime closure is staged (working-tree contents of tracked
# files): no specs/, eval/, node_modules or other local files. `agy plugin
# install` replaces the whole plugin directory, so an existing ccl-skills plugin
# is replaced only when it still matches the file inventory this installer
# recorded; anything else (an npm-managed copy, a hand-made clone, an installed
# copy someone edited) is left untouched. The npm adapter takes the same lock.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd -P)"
NAME=ccl-skills
MARKER=.ccl-skills-install.json
INSTALLER=scripts/install-antigravity.sh
DRY_RUN=0
for arg in "$@"; do
  case "$arg" in
    --dry-run) DRY_RUN=1 ;;
    *) echo "Unknown option: $arg (available: --dry-run)" >&2; exit 2 ;;
  esac
done

command -v agy >/dev/null 2>&1 || { echo "[Antigravity] agy CLI not found; skipping" >&2; exit 0; }
[ -n "${HOME:-}" ] || { echo "[Antigravity] HOME is not set" >&2; exit 2; }
TARGET="$HOME/.gemini/config/plugins/$NAME"

LOCK="$HOME/.gemini/ccl-skills-plugin.lock"
mkdir -p "$HOME/.gemini"
if ! ( set -o noclobber; : >"$LOCK" ) 2>/dev/null; then
  echo "[Antigravity] another ccl-skills install holds $LOCK; if none is running, remove that file and retry" >&2
  exit 3
fi
STAGE=""
trap 'rm -f "$LOCK"; [ -z "$STAGE" ] || rm -rf "$STAGE"' EXIT

# An existing plugin is ours only if it matches, file for file, the inventory we recorded.
if [ -e "$TARGET" ] || [ -L "$TARGET" ]; then
  if ! python3 -I -c '
import hashlib, json, os, stat, sys
target, marker, installer = sys.argv[1], sys.argv[2], sys.argv[3]
info = os.lstat(target)
if stat.S_ISLNK(info.st_mode) or not stat.S_ISDIR(info.st_mode):
    sys.exit(1)
try:
    receipt = json.load(open(os.path.join(target, marker)))
except Exception:
    sys.exit(1)
if receipt.get("installer") != installer or not isinstance(receipt.get("files"), dict):
    sys.exit(1)
seen = {}
for base, dirs, files in os.walk(target):
    for name in files + [d for d in dirs if os.path.islink(os.path.join(base, d))]:
        full = os.path.join(base, name)
        rel = os.path.relpath(full, target)
        if rel == marker:
            continue
        if os.path.islink(full) or not os.path.isfile(full):
            sys.exit(1)
        seen[rel] = hashlib.sha256(open(full, "rb").read()).hexdigest()
sys.exit(0 if seen == receipt["files"] else 1)
' "$TARGET" "$MARKER" "$INSTALLER"; then
    echo "[Antigravity] $TARGET was not installed by $INSTALLER, or was changed after install; leaving it untouched." >&2
    echo "  Inspect it, keep anything you need, then run: agy plugin uninstall $NAME  (and rerun this script)" >&2
    exit 3
  fi
fi

ROOTS=(.antigravity-plugin hooks.json agent-context skills hooks scripts/owner-dispatch)
STAGE="$(mktemp -d "${TMPDIR:-/tmp}/ccl-skills-agy-stage.XXXXXX")"
PLUGIN="$STAGE/$NAME"
mkdir "$PLUGIN"
# Tracked paths only, each staged as a verified regular file from the working tree
# (so an uncommitted edit is what gets installed); a tracked path that is now a
# directory, a symlink, or sits under a symlinked directory stops the install.
git -C "$ROOT" ls-files -z -- "${ROOTS[@]}" | python3 -I -c '
import os, shutil, stat, sys
root, dest = sys.argv[1], sys.argv[2]
for rel in sys.stdin.buffer.read().decode().split("\0"):
    if not rel:
        continue
    current = root
    for part in rel.split("/"):
        current = os.path.join(current, part)
        info = os.lstat(current)
        if stat.S_ISLNK(info.st_mode):
            sys.exit(f"[Antigravity] refusing to stage {rel}: {os.path.relpath(current, root)} is a symlink")
    if not stat.S_ISREG(info.st_mode):
        sys.exit(f"[Antigravity] refusing to stage {rel}: not a regular file")
    target = os.path.join(dest, rel)
    os.makedirs(os.path.dirname(target), exist_ok=True)
    shutil.copyfile(current, target)
    os.chmod(target, 0o755 if info.st_mode & 0o111 else 0o644)
' "$ROOT" "$PLUGIN"
for required in .antigravity-plugin/plugin.json hooks.json hooks/agy-bridge.py; do
  [ -f "$PLUGIN/$required" ] || { echo "[Antigravity] staged plugin is missing $required" >&2; exit 1; }
done
# agy installs to plugins/<manifest name>; ownership above was checked for $NAME only.
staged_name=$(python3 -I -c 'import json,sys; print(json.load(open(sys.argv[1])).get("name",""))' "$PLUGIN/.antigravity-plugin/plugin.json")
[ "$staged_name" = "$NAME" ] || { echo "[Antigravity] staged manifest names \"$staged_name\", not $NAME; refusing to install" >&2; exit 1; }
commit=$(git -C "$ROOT" rev-parse HEAD 2>/dev/null || echo unknown)
dirty=false
[ -z "$(git -C "$ROOT" status --porcelain -- "${ROOTS[@]}" 2>/dev/null)" ] || dirty=true
python3 -I -c 'import hashlib,json,os,sys
plugin, marker = sys.argv[1], sys.argv[2]
files = {os.path.relpath(os.path.join(b, n), plugin): hashlib.sha256(open(os.path.join(b, n), "rb").read()).hexdigest()
         for b, _, names in os.walk(plugin) for n in names}
json.dump({"installer":sys.argv[3],"source_commit":sys.argv[4],"source_dirty":sys.argv[5]=="true","files":files},
          open(os.path.join(plugin, marker),"w"),indent=2,sort_keys=True)' \
  "$PLUGIN" "$MARKER" "$INSTALLER" "$commit" "$dirty"

if [ "$DRY_RUN" = 1 ]; then
  echo "[Antigravity] dry run: would install $(find "$PLUGIN" -type f | wc -l | tr -d ' ') files from $commit to $TARGET"
  exit 0
fi
echo "[Antigravity] installing native plugin from $commit"
agy plugin install "$PLUGIN"
diff -rq "$PLUGIN" "$TARGET" >/dev/null 2>&1 || {
  echo "[Antigravity] agy reported success but $TARGET does not match the staged plugin" >&2; exit 1; }
echo "[Antigravity] installed to $TARGET; start a new agy session to load it"
