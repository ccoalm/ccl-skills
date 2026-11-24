#!/usr/bin/env bash
# Regression: validate-skill.sh's credential/personal-path scan must be
# cwd-INDEPENDENT.
#
# rg matches --glob self-exclusions relative to its working directory, so running
# the gate from a subdirectory (scripts/, the mandated worktree workflow, or a
# test harness that lives in scripts/) used to break the exclusions and make the
# detector scripts flag their OWN embedded pattern literals (/Users/, glpat-,
# sk-...), a cwd-dependent false positive that turned green in CI (run from the
# repo root) but red locally. This test forces a subdirectory cwd and asserts (1)
# no false positive on the self-excluded detectors and (2) a real leak is still
# caught.
set -euo pipefail
# Ruby takes its encoding from the locale; under a POSIX/unset locale it reads the UTF-8 skill text as US-ASCII and crashes. Pin UTF-8, as CI runs.
case " ${RUBYOPT:-} " in *" -Ku "*) ;; *) export RUBYOPT="-Ku${RUBYOPT:+ $RUBYOPT}" ;; esac

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd -P)"
VALIDATE="$SCRIPT_DIR/validate-skill.sh"
# scripts -> skill-extraction-workflow -> skills -> repo root
ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd -P)"
SKILL_ROOT="$ROOT/skills/skill-extraction-workflow"  # embeds the detector pattern literals
[ -f "$VALIDATE" ] || { echo "FAIL: validate script not found: $VALIDATE" >&2; exit 1; }
[ -f "$SKILL_ROOT/SKILL.md" ] || { echo "FAIL: skill-extraction-workflow root missing: $SKILL_ROOT" >&2; exit 1; }

fail() { echo "FAIL: $*" >&2; exit 1; }

# (1) From a SUBDIRECTORY cwd, validating the skill root whose scripts embed the
# leak patterns must NOT false-fail on those self-excluded detector scripts.
set +e
out="$(cd "$SCRIPT_DIR" && bash "$VALIDATE" "$SKILL_ROOT" 2>&1)"; rc=$?
set -e
case "$out" in
  *credential_or_personal_path_scan_failed*)
    fail "detector self-patterns flagged from a subdir cwd (cwd-dependent glob exclusion):\n$out" ;;
esac
[ "$rc" -eq 0 ] || fail "validate-skill from a subdir cwd should pass on skill-extraction-workflow; rc=$rc\n$out"

# (2) A REAL leak in a synthetic skill must still be caught from the same subdir cwd.
TMP="$(mktemp -d "${TMPDIR:-/tmp}/valcwd.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/skills/demo"
cat > "$TMP/skills/demo/SKILL.md" <<'EOF'
---
name: demo
description: demo skill for the credential-scan cwd regression test.
---

Body with a planted absolute path leak: /Users/victim/secret/notes.md
EOF
set +e
out2="$(cd "$SCRIPT_DIR" && bash "$VALIDATE" "$TMP/skills/demo" 2>&1)"; rc2=$?
set -e
[ "$rc2" -ne 0 ] || fail "a real /Users/ leak must still be caught from a subdir cwd:\n$out2"
case "$out2" in
  *credential_or_personal_path_scan_failed*) : ;;
  *) fail "real leak not reported as a credential failure:\n$out2" ;;
esac
case "$out2" in
  *"/Users/victim/secret"*) : ;;
  *) fail "offending content not reported:\n$out2" ;;
esac

# (3) Multi-root validation batches the credential scan into a single `rg`
# invocation (not N per-root `rg` spawns), even from a subdirectory cwd.
MULTI="$TMP/multi"
for s in alpha beta gamma; do
  mkdir -p "$MULTI/skills/$s"
  cat > "$MULTI/skills/$s/SKILL.md" <<EOF
---
name: $s
description: clean multi-root fixture skill $s.
---

Clean body for $s.
EOF
done
RG_SHIM_DIR="$TMP/rg-shim"
RG_LOG="$TMP/rg.log"
DIRNAME_LOG="$TMP/dirname.log"
RUBY_LOG="$TMP/ruby.log"
REAL_RG="$(command -v rg)"
REAL_DIRNAME="$(command -v dirname)"
REAL_RUBY="$(command -v ruby)"
mkdir -p "$RG_SHIM_DIR"
cat > "$RG_SHIM_DIR/rg" <<EOF
#!/usr/bin/env bash
printf '%s\n' "\$*" >> "$RG_LOG"
exec "$REAL_RG" "\$@"
EOF
cat > "$RG_SHIM_DIR/dirname" <<EOF
#!/usr/bin/env bash
printf '%s\n' "\$*" >> "$DIRNAME_LOG"
exec "$REAL_DIRNAME" "\$@"
EOF
cat > "$RG_SHIM_DIR/ruby" <<EOF
#!/usr/bin/env bash
printf 'ruby\n' >> "$RUBY_LOG"
exec "$REAL_RUBY" "\$@"
EOF
chmod +x "$RG_SHIM_DIR/rg" "$RG_SHIM_DIR/dirname" "$RG_SHIM_DIR/ruby"
: > "$RG_LOG"
: > "$DIRNAME_LOG"
: > "$RUBY_LOG"
set +e
out3="$(cd "$SCRIPT_DIR" && PATH="$RG_SHIM_DIR:$PATH" bash "$VALIDATE" "$MULTI" 2>&1)"; rc3=$?
set -e
[ "$rc3" -eq 0 ] || fail "multi-root clean validate-skill should pass; rc=$rc3\n$out3"
rg_spawns="$(wc -l < "$RG_LOG" | tr -d ' ')"
dirname_spawns="$(wc -l < "$DIRNAME_LOG" | tr -d ' ')"
ruby_spawns="$(wc -l < "$RUBY_LOG" | tr -d ' ')"
[ "$rg_spawns" -eq 1 ] || fail "expected 1 batched rg spawn across 3 non-git skill roots, got $rg_spawns:\n$(cat "$RG_LOG")"
[ "$dirname_spawns" -eq 0 ] || fail "expected 0 dirname spawns during root discovery, got $dirname_spawns:\n$(cat "$DIRNAME_LOG")"
[ "$ruby_spawns" -le 2 ] || fail "expected <= 2 ruby spawns (merged pre-rg YAML+ref pass + post-rg heuristics), got $ruby_spawns"

# (3b) Merged pre-rg Ruby pass still preserves exact YAML and markdown-ref failure tokens.
BAD_YAML="$TMP/bad-yaml"
mkdir -p "$BAD_YAML"
printf '%s\n' '---' 'name: bad-yaml' 'description: ""' '---' > "$BAD_YAML/SKILL.md"
set +e
out3b="$(cd "$SCRIPT_DIR" && bash "$VALIDATE" "$BAD_YAML" 2>&1)"; rc3b=$?
set -e
[ "$rc3b" -eq 1 ] || fail "empty description must exit 1, got $rc3b:\n$out3b"
printf '%s' "$out3b" | grep -qF "missing_frontmatter_description: $BAD_YAML/SKILL.md" \
  || fail "missing_frontmatter_description token missing:\n$out3b"

BAD_REF="$TMP/bad-ref"
mkdir -p "$BAD_REF"
printf '%s\n' '---' 'name: bad-ref' 'description: test.' '---' 'See `references/nonexistent.md`.' > "$BAD_REF/SKILL.md"
set +e
out3c="$(cd "$SCRIPT_DIR" && bash "$VALIDATE" "$BAD_REF" 2>&1)"; rc3c=$?
set -e
[ "$rc3c" -eq 1 ] || fail "missing markdown ref must exit 1, got $rc3c:\n$out3c"
printf '%s' "$out3c" | grep -qF "missing_markdown_references:" \
  || fail "missing_markdown_references token missing:\n$out3c"

# (3d) CHECK_INSTALL_VISIBILITY=1 must fail closed if the Ruby name-extraction
# step exits non-zero, rather than swallowing process-substitution failure as
# install_visibility_not_found.
VIS_SHIM_DIR="$TMP/vis-ruby-shim"
mkdir -p "$VIS_SHIM_DIR" "$TMP/empty-host-skills"
cat > "$VIS_SHIM_DIR/ruby" <<EOF
#!/usr/bin/env bash
case "\$*" in
  *'missing_frontmatter_name:'*)
    echo "simulated install-visibility ruby failure" >&2
    exit 1
    ;;
esac
exec "$REAL_RUBY" "\$@"
EOF
chmod +x "$VIS_SHIM_DIR/ruby"
set +e
out3d="$(cd "$SCRIPT_DIR" && PATH="$VIS_SHIM_DIR:$PATH" CHECK_INSTALL_VISIBILITY=1 HOST_SKILL_DIRS="$TMP/empty-host-skills" bash "$VALIDATE" "$MULTI" 2>&1)"; rc3d=$?
set -e
[ "$rc3d" -eq 2 ] || fail "CHECK_INSTALL_VISIBILITY=1 must exit 2 when Ruby exits non-zero (got $rc3d):\n$out3d"
printf '%s' "$out3d" | grep -qF "install_visibility_scan_error" \
  || fail "expected install_visibility_scan_error token:\n$out3d"
if printf '%s' "$out3d" | grep -qF "install_visibility_not_found"; then
  fail "must not emit install_visibility_not_found on Ruby failure:\n$out3d"
fi

# (4) Unreadable skill root still fails closed with credential_path_scan_error.
chmod 000 "$MULTI/skills/beta" 2>/dev/null || true
if [ ! -r "$MULTI/skills/beta" ]; then
  set +e
  out4="$(cd "$SCRIPT_DIR" && bash "$VALIDATE" "$MULTI/skills/beta" 2>&1)"; rc4=$?
  set -e
  chmod 755 "$MULTI/skills/beta" 2>/dev/null || true
  [ "$rc4" -ne 0 ] || fail "unreadable skill root must fail closed"
else
  chmod 755 "$MULTI/skills/beta" 2>/dev/null || true
fi

# (5) Non-1 rg exit fails closed and names the scanned skill roots.
RG_ERR_DIR="$TMP/rg-err-shim"
mkdir -p "$RG_ERR_DIR"
printf '%s\n' '#!/usr/bin/env bash' 'exit 2' > "$RG_ERR_DIR/rg"
chmod +x "$RG_ERR_DIR/rg"
set +e
out5="$(cd "$SCRIPT_DIR" && PATH="$RG_ERR_DIR:$PATH" bash "$VALIDATE" "$MULTI" 2>&1)"; rc5=$?
set -e
[ "$rc5" -ne 0 ] || fail "rg exit 2 must fail closed"
printf '%s' "$out5" | grep -qF "credential_path_scan_error: scan exited 2 for $MULTI/skills/alpha" \
  || fail "rg exit 2 diagnostic must name scanned roots; got:\n$out5"

echo "test_validate_skill_credential_cwd: ok"
