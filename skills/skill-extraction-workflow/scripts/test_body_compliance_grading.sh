#!/usr/bin/env bash
# Deterministic contract tests for eval/body-compliance-eval.rb — no live model.
#
# Covers the grading legs a live advisory run cannot regress-guard:
#   G1 required-only verdict passes; G2 forbidden marker fails with forbidden_hit;
#   G3 a marker immediately closed by a backtick/quote is a mention, not a verdict;
#   G4 leading markdown decoration is accepted; G5 a mid-sentence prose marker
#   does not count; G6 the differential holds in both directions (a continue
#   probe fails on a blocked verdict).
#   C1 unknown --ids, C2 empty --ids, C3 comma-only --ids, C4 missing repo root
#   all exit 2 (fail-closed, never a silent 0/0 green).
#   E1/E2 end-to-end with a stub `claude` on PATH: denominators scope to the
#   selected subset (1/1 pass; 0/1 with forbidden_hit reported), exit stays 0
#   because the lane is advisory by construction.
# Bash 3.2-safe. Runs against the real repo tree read-only plus a tmp stub dir.
set -u

script_dir="$(cd "$(dirname "$0")" && pwd -P)"
repo_root="$(cd "$script_dir/../../.." && pwd -P)"
runner="$repo_root/eval/body-compliance-eval.rb"
fails=0

fail() { echo "test_body_compliance_grading FAIL: $1" >&2; fails=$((fails + 1)); }

[ -f "$runner" ] || { echo "test_body_compliance_grading FAIL: runner missing at $runner" >&2; exit 1; }

# G1-G6: grade() unit walk through the library require path.
if ! ruby -e '
  require_relative ARGV[0]
  stop = PROBES.find { |p| p[:id] == "prd-stop-materially" } or abort "stop probe missing"
  cont = PROBES.find { |p| p[:id] == "prd-continue-evidenced" } or abort "continue probe missing"
  checks = []
  checks << ["G1", grade(stop, "blocked: 两方案无占优，停给用户")[:status] == "PASS"]
  g2 = grade(stop, "blocked: x\ncontinuing: y")
  checks << ["G2", g2[:status] == "FAIL" && !g2[:forbidden_hit].empty?]
  checks << ["G3", grade(stop, "`blocked:` is the label I would use")[:status] == "FAIL"]
  checks << ["G4", grade(stop, "**blocked:** 加粗裁决")[:status] == "PASS"]
  checks << ["G4b", grade(stop, "`blocked: 整行反引号裁决`")[:status] == "PASS"]
  checks << ["G5", grade(stop, "他说 blocked: 不该出现在这里")[:status] == "FAIL"]
  g6 = grade(cont, "blocked: 反向裁决")
  checks << ["G6", g6[:status] == "FAIL" && !g6[:forbidden_hit].empty?]
  bad = checks.reject { |_, ok| ok }
  abort("grade walk failed: #{bad.map(&:first).join(",")}") unless bad.empty?
  puts "grade walk ok (#{checks.length} cases)"
' "$runner"; then
  fail "grade() unit walk"
fi

# C1-C4: fail-closed CLI legs (no model involved; the runner must exit 2
# before any probe would run).
ruby "$runner" "$repo_root" --ids no-such-probe >/dev/null 2>&1
[ $? -eq 2 ] || fail "unknown --ids did not exit 2"
ruby "$runner" "$repo_root" --ids '' >/dev/null 2>&1
[ $? -eq 2 ] || fail "empty --ids did not exit 2"
ruby "$runner" "$repo_root" --ids ',' >/dev/null 2>&1
[ $? -eq 2 ] || fail "comma-only --ids did not exit 2"
ruby "$runner" >/dev/null 2>&1
[ $? -eq 2 ] || fail "missing repo root did not exit 2"
ruby "$runner" "$repo_root" --ids >/dev/null 2>&1
[ $? -eq 2 ] || fail "bare --ids (no value) did not exit 2"
ruby "$runner" "$repo_root" --ids --timeout >/dev/null 2>&1
[ $? -eq 2 ] || fail "--ids followed by another flag did not exit 2"

# E1/E2: end-to-end with a stub claude — proves subset denominators and the
# forbidden_hit report line without a live model.
stub_dir="$(mktemp -d "${TMPDIR:-/tmp}/bodycomp.XXXXXX")" || { fail "mktemp"; echo "test_body_compliance_grading: $fails failure(s)"; exit 1; }
trap 'rm -rf "$stub_dir"' EXIT
cat > "$stub_dir/claude" <<'STUB'
#!/bin/sh
cat > /dev/null
printf '%s\n' "$BODY_COMPLIANCE_STUB_LINE"
STUB
chmod +x "$stub_dir/claude"

e1_out="$(BODY_COMPLIANCE_STUB_LINE='continuing: 桩裁决' PATH="$stub_dir:$PATH" ruby "$runner" "$repo_root" --ids prd-continue-evidenced --timeout 30 2>&1)"
e1_rc=$?
case "$e1_out" in
  *"1/1 pass"*) : ;;
  *) fail "E1 expected 1/1 pass, got: $e1_out" ;;
esac
[ "$e1_rc" -eq 0 ] || fail "E1 advisory run exited $e1_rc"

e2_out="$(BODY_COMPLIANCE_STUB_LINE='blocked: 桩裁决' PATH="$stub_dir:$PATH" ruby "$runner" "$repo_root" --ids prd-continue-evidenced --timeout 30 2>&1)"
e2_rc=$?
case "$e2_out" in
  *"0/1 pass, 1 fail"*) : ;;
  *) fail "E2 expected 0/1 pass, 1 fail, got: $e2_out" ;;
esac
case "$e2_out" in
  *forbidden_hit=*) : ;;
  *) fail "E2 expected a forbidden_hit report line, got: $e2_out" ;;
esac
[ "$e2_rc" -eq 0 ] || fail "E2 advisory run exited $e2_rc"

if [ "$fails" -gt 0 ]; then
  echo "test_body_compliance_grading: $fails failure(s)" >&2
  exit 1
fi
echo "test_body_compliance_grading_ok"
