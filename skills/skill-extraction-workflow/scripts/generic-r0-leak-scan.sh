#!/usr/bin/env bash
# generic-r0-leak-scan.sh — deterministic PUBLIC fallback for the R0 leakage gate.
#
# When the maintainer's private ALIAS_AUDIT_CMD is unavailable (a normal local
# machine), check-ccl-skills.sh runs this scan instead of leaving only an
# "audit skipped" notice. It is a HIGH-SIGNAL, LOW-FALSE-POSITIVE public check —
# NOT a replacement for the private alias audit.
#
# Scope: ONLY the ADDED lines of the current git diff (committed base..HEAD,
# staged, unstaged, and untracked) restricted to shared-skill MARKDOWN surfaces
# (skills/**/*.md, README.md, docs/**/*.md,
# packages/opencode-plugin/commands/**/*.md,
# .opencode/commands/**/*.md). Diff-scoping is deliberate: it never re-polices
# pre-existing known debt, only what THIS change introduces. Markdown-only is
# deliberate too: scripts and YAML overlays legitimately contain example tokens
# and path-handling code, and the private alias audit (not this fallback) is the
# comprehensive gate of record over every file type.
#
# Detected leak classes (each requires a CONCRETE shape, so prose and angle
# placeholders like </Users> or <repo> do not trip it):
#   - absolute local paths: /Users/<seg>, /home/<seg>, /private/var/<seg>, C:\<seg>
#   - RFC1918 private IPv4 literals (10/8, 172.16-31/12, 192.168/16) — NOT loopback
#   - internal-only hostnames: <label>.internal / .intranet / .corp
#   - secret/token literals: key=<12+char quoted value>, or known vendor token prefixes
#
# Exit codes: clean=0 (prints generic_r0_leak_scan_ok), leak found=1 (prints the
# offending lines), degraded=0 (prints generic_r0_leak_scan_degraded — a DISTINCT
# status, NOT a reassuring _ok). Degraded fires when coverage is incomplete: not a
# git work tree, OR no diff base resolves (no CCL_SKILL_BASE_REF / @{upstream} /
# origin/main merge-base) while HEAD exists, so committed branch commits were NOT
# scanned — the exact shallow / detached-HEAD CI case where a leak already committed
# on the branch would otherwise pass as a silent _ok. Degraded is WARNING-PASS
# (exit 0) by default because this is a best-effort preflight and the private
# ALIAS_AUDIT_CMD is the gate of record; opt IN to a hard failure with
# CCL_SKILL_R0_STRICT_BASE=1. A leak found in whatever WAS scanned still blocks
# (exit 1) regardless of degraded. `--self-test` validates the matcher and the
# clean/degraded status decision against in-memory fixtures (no git) and exits 0/1.
set -euo pipefail

# High-signal leak patterns (rg / Rust-regex syntax). A match anywhere on an
# added line flags it. Kept narrow to hold false positives down.
leak_patterns=(
  '/Users/[A-Za-z0-9._-]'
  '/home/[A-Za-z0-9._-]'
  '/private/var/[A-Za-z0-9._-]'
  '[A-Za-z]:\\[A-Za-z0-9._-]'
  '(?:^|[^0-9.])10\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}(?:[^0-9]|$)'
  '(?:^|[^0-9.])192\.168\.[0-9]{1,3}\.[0-9]{1,3}(?:[^0-9]|$)'
  '(?:^|[^0-9.])172\.(?:1[6-9]|2[0-9]|3[01])\.[0-9]{1,3}\.[0-9]{1,3}(?:[^0-9]|$)'
  '[A-Za-z0-9][A-Za-z0-9-]*\.(?:internal|intranet|corp)(?:[^A-Za-z0-9]|$)'
  '(?:^|[^A-Za-z0-9])AKIA[0-9A-Z]{16}(?:[^0-9A-Z]|$)'
  '(?:^|[^A-Za-z0-9])gh[opsu]_[A-Za-z0-9]{36}'
  '(?:^|[^A-Za-z0-9])glpat-[A-Za-z0-9_-]{20}'
  '(?:^|[^A-Za-z0-9])xox[baprs]-[A-Za-z0-9-]{10,}'
  '(?:^|[^A-Za-z0-9])sk-[A-Za-z0-9]{20,}'
  '-----BEGIN [A-Z ]*PRIVATE KEY-----'
)
# Secret-assignment pattern carries both quote chars, so build it with double
# quotes (\" -> "), keeping rg escapes (\\s -> \s) intact.
leak_patterns+=( "(?i:api[_-]?key|secret(?:[_-]?key)?|access[_-]?key|client[_-]?secret|password|passwd|token|bearer)[\"']?\\s*[:=]\\s*[\"'][A-Za-z0-9_+/.=-]{12,}[\"']" )

# scan_stream: reads "path:lineno:content" lines on stdin, prints offenders on
# stdout. Returns 0 normally (offenders may be empty), 2 on rg error.
scan_stream() {
  local args=() p out rc=0
  for p in "${leak_patterns[@]}"; do args+=( -e "$p" ); done
  # Capture rg's real status in the else branch (a false `if` with no else would
  # otherwise reset $? to 0). rg: 0=match, 1=no match, 2=error.
  if out="$(rg --no-line-number --no-filename --color never "${args[@]}" 2>/dev/null)"; then
    rc=0
  else
    rc=$?
  fi
  if [ "$rc" -eq 0 ]; then
    printf '%s\n' "$out"
    return 0
  fi
  [ "$rc" -eq 1 ] && return 0   # no matches
  echo "generic_r0_leak_scan_error: rg exited $rc" >&2
  return 2
}

# emit_clean_result <degraded> <line_count> <file_count>
# Prints the clean-outcome status line and returns its exit code. Isolated from
# git so --self-test can exercise it. degraded=1 -> a DISTINCT scan_degraded
# status (base unavailable; committed branch commits NOT covered), WARNING-PASS
# (exit 0) by default, or BLOCK (exit 1) under CCL_SKILL_R0_STRICT_BASE=1.
emit_clean_result() {
  local degraded="$1" line_count="$2" file_count="$3"
  if [ "$degraded" = 1 ]; then
    echo "generic_r0_leak_scan_degraded: base unavailable (no CCL_SKILL_BASE_REF / @{upstream} / origin/main merge-base); committed branch commits NOT scanned — only worktree/staged/untracked. Best-effort preflight; degraded-clean is NOT proof, the private ALIAS_AUDIT_CMD is the gate of record. Set CCL_SKILL_BASE_REF for full coverage." >&2
    if [ "${CCL_SKILL_R0_STRICT_BASE:-0}" = 1 ]; then
      echo "generic_r0_leak_scan_degraded_blocking: CCL_SKILL_R0_STRICT_BASE=1 -> treating degraded coverage as a failure" >&2
      return 1
    fi
    return 0
  fi
  echo "generic_r0_leak_scan_ok: scanned ${line_count} added markdown line(s) across ${file_count} file(s); no high-signal public leak patterns"
  return 0
}

run_self_test() {
  # Fixtures: "<expect>\t<content>" where expect is flag|clean.
  local fixture_label='api_key'
  local fixture_value='abcdef0123456789xyz'
  local fixtures=(
    $'flag\t/Users/alice/secret/path here'
    $'flag\tconfig at /home/bob/.config/app'
    $'flag\t/private/var/folders/ab/private-thing'
    $'flag\twindows path C:\\Users\\admin\\file.txt'
    $'flag\tconnect to 10.'$'1.2.3 today'
    $'flag\tinternal host 192.'$'168.0.5 only'
    $'flag\treach 172.'$'20.1.1 over vpn'
    $'flag\tservice db.'$'internal is up'
    $'flag\tAWS key AKIA'$'ABCDEFGHIJKLMNOP rotated'
    $'flag\tgithub ghp_'$'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789 leaked'
    "flag"$'\t'"$fixture_label = \"$fixture_value\" set"
    $'flag\tpassword: "hunter2hunter2hunter2"'
    $'flag\tbegin block -----BEGIN RSA PRIVATE KEY-----'
    $'clean\tsee <repo>/skills/foo for details'
    $'clean\tpath under /home/<user>/config'
    $'clean\tlocalhost 127.0.0.1 loopback only'
    $'clean\trelease version 1.2.3.4beta notes'
    $'clean\tset your api token in the settings page'
    $'clean\tthe secret sauce of good design'
    $'clean\tRFC1918 ranges like 10.x and 192.168.x'
    $'clean\tuse base64 to encode the payload'
    $'clean\ttask-runner sk module loaded'
    $'clean\texample.invalid is a reserved test host'
    $'clean\tSHA-256 digest of the file'
  )
  local failed=0 expect content line flagged
  local i=1
  for fx in "${fixtures[@]}"; do
    expect="${fx%%$'\t'*}"
    content="${fx#*$'\t'}"
    line="selftest:${i}:${content}"
    if [ -n "$(printf '%s\n' "$line" | scan_stream)" ]; then
      flagged=flag
    else
      flagged=clean
    fi
    if [ "$flagged" != "$expect" ]; then
      echo "generic_r0_leak_scan_self_test: MISMATCH expected=$expect got=$flagged :: $content" >&2
      failed=1
    fi
    i=$((i + 1))
  done
  # Status-decision unit: base-unavailable clean outcome must be a DISTINCT
  # scan_degraded (not a reassuring _ok), warning-pass by default, blocking under
  # strict; a covered clean outcome must be scan_ok.
  local dtext drc
  dtext="$(emit_clean_result 1 0 0 2>&1)" && drc=0 || drc=$?
  if ! printf '%s' "$dtext" | grep -q 'generic_r0_leak_scan_degraded'; then
    echo "generic_r0_leak_scan_self_test: emit_clean_result(degraded) must print scan_degraded" >&2; failed=1
  fi
  if [ "$drc" -ne 0 ]; then
    echo "generic_r0_leak_scan_self_test: degraded must be WARNING-PASS (exit 0) by default" >&2; failed=1
  fi
  dtext="$(CCL_SKILL_R0_STRICT_BASE=1 emit_clean_result 1 0 0 2>&1)" && drc=0 || drc=$?
  if [ "$drc" -eq 0 ]; then
    echo "generic_r0_leak_scan_self_test: CCL_SKILL_R0_STRICT_BASE=1 must make degraded BLOCK" >&2; failed=1
  fi
  if ! printf '%s' "$(emit_clean_result 0 5 2 2>&1)" | grep -q 'generic_r0_leak_scan_ok'; then
    echo "generic_r0_leak_scan_self_test: emit_clean_result(covered) must print scan_ok" >&2; failed=1
  fi

  if [ "$failed" -ne 0 ]; then
    echo "generic_r0_leak_scan_self_test_failed" >&2
    return 1
  fi
  echo "generic_r0_leak_scan_self_test_ok"
  return 0
}

# parse_diff: stdin = `git diff --unified=0` output; stdout = added markdown
# lines as "relpath:newlineno:content". Tracks the +++ target file and the new
# line counter from each @@ hunk header.
parse_diff() {
  awk '
    /^diff --git / { file=""; next }
    /^\+\+\+ / {
      f=$0; sub(/^\+\+\+ /,"",f)
      if (f=="/dev/null") { file=""; next }
      sub(/^b\//,"",f)
      file=f
      next
    }
    /^@@ / {
      if (match($0, /\+[0-9]+/)) { curline=substr($0, RSTART+1, RLENGTH-1)+0 }
      next
    }
    /^\+/ {
      if (file=="") next
      if (file !~ /\.md$/) next
      print file ":" curline ":" substr($0,2)
      curline++
      next
    }
  '
}

main_scan() {
  local root="${1:-.}"
  cd "$root"
  if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    echo "generic_r0_leak_scan_degraded: not a git work tree at '$root'; cannot diff added lines (non-blocking)"
    return 0
  fi

  local surfaces=( skills README.md docs packages/opencode-plugin/commands .opencode/commands )

  # Resolve diff base (mirrors check-ccl-skills.sh): explicit override, then
  # @{upstream}, then origin/main. merge_base may be empty when no base resolves
  # (shallow / detached-HEAD CI, no origin). The staged/unstaged/untracked scans
  # still run, but committed branch commits are then NOT covered — so when a HEAD
  # exists yet no base resolved, mark the clean outcome degraded rather than let a
  # branch-committed leak pass as a silent _ok.
  local base merge_base degraded=0
  base="${CCL_SKILL_BASE_REF:-}"
  if [ -z "$base" ]; then
    base="$(git rev-parse --abbrev-ref --symbolic-full-name '@{upstream}' 2>/dev/null || true)"
    [ -z "$base" ] && base="origin/main"
  fi
  merge_base="$(git merge-base "$base" HEAD 2>/dev/null || true)"
  if [ -z "$merge_base" ] && git rev-parse --verify -q HEAD >/dev/null 2>&1; then
    degraded=1
  fi

  local stream=""
  if [ -n "$merge_base" ]; then
    stream+="$(git diff --unified=0 "$merge_base" HEAD -- "${surfaces[@]}" 2>/dev/null | parse_diff)"$'\n'
  fi
  stream+="$(git diff --unified=0 --cached -- "${surfaces[@]}" 2>/dev/null | parse_diff)"$'\n'
  stream+="$(git diff --unified=0 -- "${surfaces[@]}" 2>/dev/null | parse_diff)"$'\n'

  # Untracked markdown files: every line counts as added.
  local f rel
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    case "$f" in *.md) ;; *) continue ;; esac
    rel="$f"
    stream+="$(awk -v p="$rel" '{print p":"FNR":"$0}' "$f" 2>/dev/null)"$'\n'
  done < <(git ls-files --others --exclude-standard -- "${surfaces[@]}" 2>/dev/null || true)

  # Drop empty lines produced by the joins.
  stream="$(printf '%s\n' "$stream" | sed '/^$/d')"

  local file_count line_count offenders
  line_count="$(printf '%s' "$stream" | grep -c . || true)"
  file_count="$(printf '%s\n' "$stream" | sed -n 's/^\([^:]*\):.*/\1/p' | sort -u | grep -c . || true)"

  if [ -z "$stream" ]; then
    # No added lines in the worktree/staged/untracked scan. If the committed base
    # was not covered this is under-scanned, not proven clean -> degraded.
    if [ "$degraded" = 1 ]; then
      if emit_clean_result 1 0 0; then return 0; else return $?; fi
    fi
    echo "generic_r0_leak_scan_ok: 0 added markdown line(s) in scope; nothing to scan"
    return 0
  fi

  offenders="$(printf '%s\n' "$stream" | scan_stream)" || return 2
  if [ -n "$offenders" ]; then
    # A leak in whatever WAS scanned always blocks, degraded or not.
    echo "generic_r0_leak_scan: high-signal public leak pattern(s) in added markdown lines:" >&2
    printf '%s\n' "$offenders" | sed 's/^/  /' >&2
    echo "generic_r0_leak_scan_failed: sanitize the line(s) above (use angle placeholders / generic terms), or run the private ALIAS_AUDIT_CMD audit if this is a false positive" >&2
    return 1
  fi
  if emit_clean_result "$degraded" "$line_count" "$file_count"; then return 0; else return $?; fi
}

if ! command -v rg >/dev/null 2>&1; then
  echo "generic_r0_leak_scan_error: missing required command: rg" >&2
  exit 2
fi

case "${1:-}" in
  --self-test) run_self_test ;;
  *) main_scan "${1:-.}" ;;
esac
