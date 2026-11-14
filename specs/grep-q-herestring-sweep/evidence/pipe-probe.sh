#!/usr/bin/env bash
# Paired probe for the pipe-into-`grep -q` assertions this round changes.
#
# Usage: bash pipe-probe.sh <source-root> [runs]
#
# <source-root> holds a `skills/` tree: the working tree, or `git archive <rev> skills`
# unpacked somewhere. Each case pulls the assertion's own code out of that tree (a helper
# function, or a `check "<label>"` expression) and runs it on input whose match is on the
# first line and is followed by 256 KiB of further lines, far more than a Linux pipe
# buffer (64 KiB). With the old pipe form, `grep -q` exits on the matching line while the
# writer still has data, the writer takes SIGPIPE, and `pipefail` turns the pipeline's
# status into 141. A positive assertion then reads a match as a miss (false red); a
# negated one reads a present string as absent (false green). The here-string form reads
# the same text and does not depend on the writer.
#
# Two groups:
#   changed  - the sites this round changes. Expected: wrong runs on the old tree,
#              none on the new one.
#   control  - sites left unchanged because their input is one line: `grep` must read to
#              the end of a line before it can match, so it cannot stop while the writer
#              still has data. Expected: no wrong runs on either tree.
#
# Each case prints `wrong=<k>/<runs>`. The script exits 1 if any case had a wrong run,
# and 2 if a case could not be set up (a renamed helper or label never passes silently).
set -uo pipefail

root="${1:?usage: pipe-probe.sh <source-root> [runs]}"
runs="${2:-50}"
root="$(cd "$root" && pwd -P)"
work="$(mktemp -d "${TMPDIR:-/tmp}/pipe-probe.XXXXXX")"
trap '[ -n "${KEEP:-}" ] || rm -rf "$work"' EXIT

# 256 KiB of filler lines, written once and reused.
filler="$work/filler"
awk 'BEGIN { for (i = 0; i < 4096; i++) printf "filler line %06d xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx\n", i }' >"$filler"

# extract_fn <file> <name>: a top-level function, from `name() {` to its closing line.
extract_fn() {
  awk -v name="$2" '
    !on && index($0, name "() {") == 1 { on = 1 }
    on { print; if ($0 == "}" || $0 ~ /; }$/) exit }
  ' "$1"
}

# extract_check <file> <label>: the `check "<label>"` call plus its continuation lines.
extract_check() {
  awk -v label="check \"$2\"" '
    !on && index($0, label) == 1 { on = 1 }
    on { print; if ($0 !~ /\\$/) exit }
  ' "$1"
}

# require <text> <what>: stop on an empty extraction.
require() {
  [ -n "$1" ] || { echo "probe_setup_failed: could not extract $2" >&2; exit 2; }
}

failed=0
# run_case <group> <case> <script>: runs <script> <runs> times; each run prints RIGHT or WRONG.
run_case() {
  local group="$1" name="$2" script="$3" i wrong=0 verdict
  for ((i = 0; i < runs; i++)); do
    verdict="$(bash "$script" 2>/dev/null | tail -n 1)"
    case "$verdict" in
      RIGHT) ;;
      WRONG) wrong=$((wrong + 1)) ;;
      *) echo "probe_setup_failed: $name printed '$verdict'" >&2; exit 2 ;;
    esac
  done
  printf '%-8s %-62s wrong=%s/%s\n' "$group" "$name" "$wrong" "$runs"
  [ "$wrong" = 0 ] || failed=1
}

ts="$root/skills/testing-strategy/scripts"
cr="$root/skills/code-review/scripts"
td="$root/skills/tighten-doc/scripts"
sx="$root/skills/skill-extraction-workflow/scripts"

# --- changed: testing-strategy, assert_hit in two checker suites ----------------------
for suite in lang-basics-ast-check client-terminal-ansi-check; do
  fn="$(extract_fn "$ts/$suite.test.sh" assert_hit)"
  require "$fn" "$suite assert_hit"
  cat >"$work/$suite.sh" <<EOF
set -euo pipefail
script=checker-stub
python3() { printf 'NEEDLE at the top\n'; cat "$filler"; return 1; }
$fn
pass=0 fail=0
assert_hit "probe" NEEDLE x >/dev/null
# A run counts only when the stub's output reached the assertion: pass+fail must be 1.
[ "\$((pass + fail))" = 1 ] || { echo SETUP; exit 0; }
[ "\$fail" = 0 ] && echo RIGHT || echo WRONG
EOF
  run_case changed "$suite.test.sh: assert_hit finds a match" "$work/$suite.sh"
done

# --- changed: tighten-doc, mutation_probe.sh probe() ----------------------------------
fn="$(extract_fn "$td/mutation_probe.sh" probe)"
require "$fn" "mutation_probe probe"
cat >"$work/mutation.sh" <<EOF
set -uo pipefail
cp() { :; }; mv() { :; }; python3() { :; }
bash() { printf 'FAIL - mutant caught\n'; cat "$filler"; return 1; }
$fn
pass=0; total=0; missed=""
probe lint.py CODE >/dev/null
[ "\$pass" = 1 ] && echo RIGHT || echo WRONG
EOF
run_case changed "mutation_probe.sh: a red mutant counts as covered" "$work/mutation.sh"

# --- changed: code-review retry suite, symlinks in the diagnostic copy ----------------
retry="$cr/test_opencode_review_retry.sh"
check_fn="$(extract_fn "$retry" check)"
require "$check_fn" "retry check"
expr="$(extract_check "$retry" "timeout diagnostics never copy the credential binding")"
require "$expr" "retry credential-binding check"
mkdir -p "$work/diag"
for ((i = 0; i < 3000; i++)); do
  ln -s /nonexistent/target "$work/diag/link-$(printf '%05d' "$i")-xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx"
done
cat >"$work/retry-links.sh" <<EOF
set -uo pipefail
fails=0
$check_fn
diagnostic_name=probe diagnostic_path="$work/diag"
got="\$($expr)"
case "\$got" in "FAIL "*) echo RIGHT ;; *) echo WRONG ;; esac
EOF
run_case changed "test_opencode_review_retry.sh: 3000 symlinks are found" "$work/retry-links.sh"

# --- changed: code-review gate suite, live process-group records -----------------------
gate="$cr/test_review_gate.sh"
fn="$(extract_fn "$gate" prune_dead_pgid_records)"
require "$fn" "gate prune_dead_pgid_records"
cat >"$work/prune.sh" <<EOF
set -uo pipefail
WORK="$work/prune-\$\$"
mkdir -p "\$WORK/state/pgids"
: >"\$WORK/state/pgids/4242"
review_owned_pgids() { echo 4242; }
ps() { echo ' 4242'; cat "$filler"; }
$fn
prune_dead_pgid_records
if [ -e "\$WORK/state/pgids/4242" ]; then echo RIGHT; else echo WRONG; fi
rm -rf "\$WORK"
EOF
run_case changed "test_review_gate.sh: a live group keeps its record" "$work/prune.sh"

# --- changed: skill-extraction-workflow, UI/UX completion-claim scan -------------------
ux="$sx/test_uiux_delivery_contract.sh"
fns=""
for name in active_markdown active_text parallel_completion_claims_absent; do
  fn="$(extract_fn "$ux" "$name")"
  require "$fn" "uiux $name"
  fns+="$fn"$'\n'
done
{ echo 'Implementation is considered ready: when the checklist passes.'; cat "$filler"; } >"$work/claim.md"
cat >"$work/uiux.sh" <<EOF
set -euo pipefail
$fns
if parallel_completion_claims_absent "$work/claim.md"; then echo WRONG; else echo RIGHT; fi
EOF
run_case changed "test_uiux_delivery_contract.sh: a claim on line 1 is found" "$work/uiux.sh"

# --- inverse: the same changed sites still reach the opposite verdict -------------------
# Same input shape, minus the thing the assertion looks for. A here-string form that
# always matched (or never did) would turn these wrong.
sed -e 's/NEEDLE at the top/nothing at the top/' "$work/lang-basics-ast-check.sh" \
  | sed -e 's/\[ "\$fail" = 0 \] && echo RIGHT || echo WRONG/[ "$fail" = 1 ] \&\& echo RIGHT || echo WRONG/' \
  >"$work/inv-ast.sh"
run_case inverse "lang-basics-ast-check.test.sh: no match is a failure" "$work/inv-ast.sh"
sed -e 's/NEEDLE at the top/nothing at the top/' "$work/client-terminal-ansi-check.sh" \
  | sed -e 's/\[ "\$fail" = 0 \] && echo RIGHT || echo WRONG/[ "$fail" = 1 ] \&\& echo RIGHT || echo WRONG/' \
  >"$work/inv-ansi.sh"
run_case inverse "client-terminal-ansi-check.test.sh: no match is a failure" "$work/inv-ansi.sh"
sed -e "s/printf 'FAIL - mutant caught\\\\n'/printf 'ok   - mutant survived\\\\n'/" \
    -e 's/\[ "\$pass" = 1 \] && echo RIGHT || echo WRONG/[ "$pass" = 0 ] \&\& echo RIGHT || echo WRONG/' \
  "$work/mutation.sh" >"$work/inv-mutation.sh"
run_case inverse "mutation_probe.sh: no FAIL line is no coverage" "$work/inv-mutation.sh"
mkdir -p "$work/diag-clean"
sed -e "s|$work/diag\"|$work/diag-clean\"|" -e 's/"FAIL "\*) echo RIGHT/"ok "*) echo RIGHT/' \
  "$work/retry-links.sh" >"$work/inv-links.sh"
run_case inverse "test_opencode_review_retry.sh: no symlinks passes" "$work/inv-links.sh"
sed -e "s/echo ' 4242'/echo ' 4343'/" \
    -e 's/then echo RIGHT; else echo WRONG; fi/then echo WRONG; else echo RIGHT; fi/' \
  "$work/prune.sh" >"$work/inv-prune.sh"
run_case inverse "test_review_gate.sh: a dead group loses its record" "$work/inv-prune.sh"
{ echo 'Implementation follows the delivery contract.'; cat "$filler"; } >"$work/no-claim.md"
sed -e "s|$work/claim.md|$work/no-claim.md|" \
    -e 's/then echo WRONG; else echo RIGHT; fi/then echo RIGHT; else echo WRONG; fi/' \
  "$work/uiux.sh" >"$work/inv-uiux.sh"
run_case inverse "test_uiux_delivery_contract.sh: no claim reads as absent" "$work/inv-uiux.sh"

# --- writer-fails: the writer prints the match, then exits non-zero --------------------
# The new forms decide from what the writer printed. Expected verdicts below are the
# new tree's; the old pipe forms also failed on the writer's status, so the old tree
# differs here by design (see plan.md, Change).
sed -e "s|ps() { echo ' 4242'; cat \"$filler\"; }|ps() { echo ' 4242'; return 1; }|" \
  "$work/prune.sh" >"$work/wf-prune.sh"
grep -qF "return 1; }" "$work/wf-prune.sh" || { echo "probe_setup_failed: wf-prune rewrite" >&2; exit 2; }
run_case writer-fails "test_review_gate.sh: a group ps listed keeps its record" "$work/wf-prune.sh"
mkdir -p "$work/diag-fail/locked"
ln -s /nonexistent/target "$work/diag-fail/link"
chmod 000 "$work/diag-fail/locked"
sed -e "s|$work/diag\"|$work/diag-fail\"|" "$work/retry-links.sh" >"$work/wf-links.sh"
if find "$work/diag-fail" -type l >/dev/null 2>&1; then
  chmod 700 "$work/diag-fail/locked"
  echo "probe_setup_failed: find did not fail on the locked directory (running as root?)" >&2; exit 2
fi
run_case writer-fails "test_opencode_review_retry.sh: a link find printed is caught" "$work/wf-links.sh"
chmod 700 "$work/diag-fail/locked"
{
  echo 'set -euo pipefail'
  printf '%s\n' "$fns"
  echo "active_text() { echo 'Implementation is considered ready: now.'; return 1; }"
  echo "if parallel_completion_claims_absent \"$work/claim.md\"; then echo WRONG; else echo RIGHT; fi"
} >"$work/wf-uiux.sh"
run_case writer-fails "test_uiux_delivery_contract.sh: a printed claim is found" "$work/wf-uiux.sh"

# --- control: retry suite checks over the wrapper's one-line JSON ---------------------
# opencode_review.sh prints one compact JSON line on stdout; the suite captures stdout only.
# retry_control <case> <label> <expected ok|FAIL> <python printing the JSON>
retry_control() {
  local name="$1" label="$2" want="$3" builder="$4" expr
  expr="$(extract_check "$retry" "$label")"
  require "$expr" "retry check '$label'"
  python3 -c "$builder" "$filler" >"$work/$name.json"
  cat >"$work/$name.sh" <<EOF
set -uo pipefail
fails=0
$check_fn
out="\$(cat "$work/$name.json")"
got="\$($expr)"
case "\$got" in "$want "*) echo RIGHT ;; *) echo WRONG ;; esac
EOF
  run_case control "$name" "$work/$name.sh"
}
pad='import json,sys; f=open(sys.argv[1]).read()'
retry_control "test_opencode_review_retry.sh: per-concern conclusions" \
  "retry result preserves per-concern conclusions" ok \
  "$pad; print(json.dumps({'concern_results': [], 'note': f}, separators=(',', ':')))"
retry_control "test_opencode_review_retry.sh: model prose absent (negated)" \
  "ineligible verdict no longer relays the model prose" FAIL \
  "$pad; print(json.dumps({'text': 'auth handling ' + f}, separators=(',', ':')))"
retry_control "test_opencode_review_retry.sh: finding text preserved" \
  "retry finding text preserved" ok \
  "$pad; print(json.dumps({'findings': 'handlers/auth.code:3 ' + f}, separators=(',', ':')))"
retry_control "test_opencode_review_retry.sh: prose sentinel absent (negated)" \
  "terminal concern verdict does not relay the prose in ANY field" FAIL \
  "$pad; print(json.dumps({'text': 'ZZPROSESENTINELZZ ' + f}, separators=(',', ':')))"

# --- control: identity suite, reference read through `tr '\n' ' '` --------------------
ident="$cr/test_code_review_identity.sh"
ident_check="$(extract_fn "$ident" check)"
require "$ident_check" "identity check"
{
  echo 'Do not start a second reviewer, enter fallback, or call the partial chunk "empty reviewer output" while that handle or its child process is alive.'
  echo 'If orchestration loses the handle, the lane is infrastructure-inconclusive/manual-review-required and no replacement or fallback may be started or credited.'
  echo 'Artifacts may be inspected for diagnosis only; they cannot reconstruct the missing terminal result or authorize continuation.'
  cat "$filler"
} >"$work/wait-ref.md"
n=0
for label in "wait reference forbids replacement while the original handle is live" \
             "wait reference forbids replacement after handle loss" \
             "wait reference makes artifacts diagnostic only"; do
  n=$((n + 1))
  expr="$(extract_check "$ident" "$label")"
  require "$expr" "identity check '$label'"
  cat >"$work/ident-$n.sh" <<EOF
set -uo pipefail
fails=0
WAIT_REF="$work/wait-ref.md"
$ident_check
got="\$($expr)"
case "\$got" in "ok "*) echo RIGHT ;; *) echo WRONG ;; esac
EOF
  run_case control "test_code_review_identity.sh: phrase $n found" "$work/ident-$n.sh"
done

[ "$failed" = 0 ] && echo "pipe_probe_ok" || echo "pipe_probe_failed"
exit "$failed"
