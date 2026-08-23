#!/usr/bin/env bash
# Policy-matrix regression for the reviewer init gate.
#
# This is the self-audit oracle, not another example-based suite: it states the
# intended policy independently of the implementation and crosses it over the
# init-event shape space through both parse paths.
#
# Its own ability to fail is CHECKED HERE, not asserted. The walk used to live in
# init_policy_matrix.py's docstring as a set of hand-maintained mismatch counts,
# with a note saying to re-run it by hand when the policy changes -- so every
# added row silently invalidated the recorded numbers, and nothing failed when
# they went stale. Each mutation below weakens the parser in a named way in a
# disposable copy; the oracle must report at least one mismatch for every one of
# them. A mutation that flips nothing is a finding about the oracle, so a
# mutation whose pattern no longer matches is a hard failure rather than a skip.
set -euo pipefail
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
parser="$script_dir/parse_probe_result.py"
tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

pristine_digest="$(shasum -a 256 "$parser" | awk '{print $1}')"

# control: the real parser must satisfy the oracle. The case count is captured
# because every mutant must run the SAME number of cases -- a mutant that dies
# early runs fewer, and its truncated output must not read as sensitivity.
# Captured with the failure path made visible: under `set -e` a plain assignment
# from a failing substitution aborts the script with the oracle's own output
# swallowed into the variable, so a mismatching control looked like a silent
# exit 1 with no diagnosis at all.
control_output=""
control_rc=0
control_output="$(python3 "$script_dir/init_policy_matrix.py")" || control_rc=$?
printf '%s\n' "$control_output"
if [ "$control_rc" -ne 0 ]; then
  printf 'the oracle does not pass against the real parser; the mutation walk below would prove nothing\n' >&2
  exit 1
fi
# Parsed with bash's own regex rather than a pipeline. Under `pipefail` a
# producer whose consumer exits early (`grep -q`, `head -1`) takes SIGPIPE and
# the pipeline reports failure, so a check would fail nondeterministically on
# large output depending on the pipe buffer -- and under `set -e` an assignment
# from such a substitution aborts the script outright.
control_cases=""
if [[ "$control_output" =~ cases:\ ([0-9]+) ]]; then
  control_cases="${BASH_REMATCH[1]}"
fi
if [ -z "$control_cases" ] || [ "$control_cases" -le 0 ]; then
  printf 'control run did not report a case count; the walk below would prove nothing\n' >&2
  exit 1
fi

# Each entry is NAME, then the literal to replace, then its replacement. The
# literals are chosen to be load-bearing lines rather than incidental text, so a
# refactor that moves them fails loudly here instead of quietly disarming the
# check.
mutate_and_expect_mismatch() {
  local name="$1" find="$2" replace="$3" out
  local mutant="$tmp_dir/mutant_$name.py"
  if ! python3 - "$parser" "$mutant" "$find" "$replace" <<'PY'
import sys
from pathlib import Path

source, target, find, replace = sys.argv[1:5]
text = Path(source).read_text(encoding="utf-8")
if text.count(find) != 1:
    print(f"pattern must match exactly once, matched {text.count(find)}", file=sys.stderr)
    raise SystemExit(1)
Path(target).write_text(text.replace(find, replace), encoding="utf-8")
PY
  then
    printf 'mutation %s could not be applied; its anchor moved -- the sensitivity check is disarmed, not passing\n' "$name" >&2
    return 1
  fi
  if out="$(python3 "$script_dir/init_policy_matrix.py" "$mutant" 2>&1)"; then
    printf 'mutation %s flipped NOTHING; the oracle cannot detect it:\n%s\n' "$name" "$out" >&2
    return 1
  fi
  # A nonzero exit is NECESSARY BUT NOT SUFFICIENT. A mutant that crashes,
  # raises, or breaks the module also exits nonzero, so accepting the exit code
  # alone would bank a broken build as proof of sensitivity -- a green verdict
  # structurally incapable of being red. Require positive evidence instead: the
  # full case count, a parsed positive mismatch total, and at least one MISMATCH
  # record naming a case.
  # Pure-bash matching, for the pipefail/SIGPIPE reason recorded at the control.
  local mutant_cases="" mutant_mismatches=""
  if [[ "$out" =~ cases:\ ([0-9]+)\ +mismatches:\ ([0-9]+) ]]; then
    mutant_cases="${BASH_REMATCH[1]}"
    mutant_mismatches="${BASH_REMATCH[2]}"
  fi
  if [ "$mutant_cases" != "$control_cases" ]; then
    printf 'mutation %s exited nonzero without completing the matrix (cases=%s, control=%s); that is a broken mutant, not detected sensitivity:\n%s\n' \
      "$name" "${mutant_cases:-none}" "$control_cases" "$out" >&2
    return 1
  fi
  if [ -z "$mutant_mismatches" ] || [ "$mutant_mismatches" -le 0 ]; then
    printf 'mutation %s exited nonzero but reported no positive mismatch count; the nonzero came from something other than a detected verdict change:\n%s\n' \
      "$name" "$out" >&2
    return 1
  fi
  # A crashing mutant DOES complete the matrix and DOES report mismatches: the
  # oracle catches each parser failure per case and records it as `unparseable`.
  # So the count alone still cannot tell "the policy verdict moved" from "the
  # parser is broken". Require at least one mismatch whose observed value is a
  # real verdict class, and refuse the run outright if any case came back
  # unparseable.
  # Matched as the VERDICT token, not as a bare substring: one legitimate case is
  # named `unparseable-identifier`, so a substring test rejects a perfectly good
  # mutant on the strength of a fixture's name.
  if [[ "$out" == *"got unparseable"* ]]; then
    printf 'mutation %s produced unparseable verdicts; that is a broken parser, not a detected verdict change:\n%s\n' "$name" "$out" >&2
    return 1
  fi
  if ! [[ "$out" =~ MISMATCH[^$'\n']*got\ (tolerated|terminal|fallback) ]]; then
    printf 'mutation %s reported a mismatch count with no MISMATCH record naming a real verdict class:\n%s\n' "$name" "$out" >&2
    return 1
  fi
  # First line via parameter expansion, not `| head -1`: the consumer would exit
  # after one line and the producer could take SIGPIPE, so under `pipefail` the
  # SUCCESS path itself would abort the suite on a mutant with enough output.
  printf '  sensitive to %s: %s\n' "$name" "${out%%$'\n'*}"
}

# The walk below REGISTERS its mutants instead of running them inline, so they can
# be dispatched concurrently further down. Registration changes nothing about what
# is asserted: every registered triple is handed to the same
# mutate_and_expect_mismatch above, unmodified.
mutation_names=()
mutation_finds=()
mutation_replaces=()
register_mutation() {
  mutation_names+=("$1")
  mutation_finds+=("$2")
  mutation_replaces+=("$3")
}

# Prove the guard above can actually fail before trusting any verdict it gives.
# The first version of this walk accepted ANY nonzero exit as sensitivity, so a
# mutant that merely broke the parser would have banked as proof — an
# independent review caught it, and this is the check that would have caught it
# here. A syntactically broken mutant completes the matrix and reports a full
# set of mismatches, so only the verdict-class requirement rejects it.
# A bare "it returned nonzero" would repeat the same defect one level up: the
# helper also returns nonzero when its anchor moved or the copy could not be
# written, and then the guard was never exercised at all. So require the
# SPECIFIC rejection reason in its stderr.
self_check_stderr="$tmp_dir/guard_self_check.err"
if mutate_and_expect_mismatch guard-self-check-broken-mutant \
  'def is_bare_host_identifier(identifier: str) -> bool:' \
  'def is_bare_host_identifier(identifier: str) -> bool  # deliberately broken' \
  >/dev/null 2>"$self_check_stderr"
then
  printf 'the walk accepted a BROKEN mutant as sensitivity; its own guard does not work, so every result below is meaningless\n' >&2
  exit 1
fi
if ! grep -q 'produced unparseable verdicts' "$self_check_stderr"; then
  printf 'the guard self-check failed for the WRONG reason, so the guard itself is unproven and every result below is meaningless:\n' >&2
  cat "$self_check_stderr" >&2
  exit 1
fi
printf '  guard self-check: a broken mutant is rejected, and for the right reason\n'

register_mutation tolerate-all-unknown-containers \
  '                if isinstance(value, (list, dict)) and value:
                    unknown_fields.add(field)' \
  '                if False:
                    unknown_fields.add(field)'

register_mutation drop-authority-name-guard \
  '    segments = re.split(r"[_.\-]+|(?<=[a-z0-9])(?=[A-Z])", name)' \
  '    return False'

register_mutation drop-authority-presence-requirement \
  'REQUIRED_PRESENT_INIT_FIELDS = ("permissionMode",)' \
  'REQUIRED_PRESENT_INIT_FIELDS = ()'

register_mutation drop-field-name-sanitizer \
  '    text = name if isinstance(name, str) else repr(name)' \
  '    return name if isinstance(name, str) else repr(name)'

# The two directions of the host-vocabulary class. Both must be detectable, and
# they fail for opposite reasons: widening it launders a proven customization
# into the cascadable class, while removing it restores the total-outage
# behaviour this class exists to prevent.
register_mutation widen-host-vocabulary-to-any-entry \
  '    return bool(BARE_HOST_IDENTIFIER.fullmatch(identifier))' \
  '    return True'

register_mutation terminalize-host-vocabulary \
  '    return bool(BARE_HOST_IDENTIFIER.fullmatch(identifier))' \
  '    return False'

# Dynamic host command vocabulary is useful only if both halves are enforced:
# the baseline must affect the allow decision, and its CLI version must bind the
# formal init. Baseline skills are deliberately not authority because a leaked
# user skill would otherwise become callable in the formal run.
register_mutation drop-host-baseline-vocabulary \
  '                        if customization_entry_allowed(
                            field,
                            entry,
                            expected_native_skills,
                            baseline_commands,
                            baseline_skills,
                        ):' \
  '                        if customization_entry_allowed(
                            field,
                            entry,
                            expected_native_skills,
                            set(),
                            set(),
                        ):'

register_mutation authorize-host-baseline-skill \
  '            identifier in KNOWN_SAFE_BUILTIN_SKILLS
            or identifier in selected_names' \
  '            identifier in KNOWN_SAFE_BUILTIN_SKILLS
            or identifier in baseline_skills
            or identifier in selected_names'

register_mutation drop-host-baseline-required-empty-check \
  '        if field not in HOST_VOCABULARY_FIELDS and init_event.get(field) != []:' \
  '        if field not in HOST_VOCABULARY_FIELDS and False:'

register_mutation widen-host-baseline-to-namespaced-entries \
  '            or any(
                identifier not in known_host_identifiers
                and not is_bare_host_identifier(identifier)
                for identifier in identifiers
            )' \
  '            or any(identifier == "<unidentified>" for identifier in identifiers)'

register_mutation drop-host-baseline-version-binding \
  '        if baseline_version is not None and ev.get("claude_code_version") != baseline_version:
            # The two invocations no longer prove one same-version host
            # vocabulary snapshot. Refuse this lane, but treat the mismatch as
            # capability drift rather than a proven tool/authority breach so a
            # different reviewer may continue.
            unknown_fields.add("claude_code_version:host-baseline-mismatch")' \
  '        if False:
            unknown_fields.add("claude_code_version:host-baseline-mismatch")'

# The shape gate. Dropping it lets a structured entry be judged on its `name`
# alone, which reaches TOLERATED when that name is an allowed built-in -- the
# most severe class in this file, so it needs its own mutant rather than riding
# on the bare-identifier one.
register_mutation drop-whole-value-gate \
  '                        if field in HOST_VOCABULARY_FIELDS and (
                            not host_entry_is_whole(entry, identifier)
                        ):' \
  '                        if False:'

# ...and the weaker version of the same gate: checking only the SHAPE (a plain
# string) while still judging a truncated token. This is what the gate looked
# like before the third finding, so it must be detectable on its own.
register_mutation weaken-whole-value-gate-to-shape-only \
  '    normalized = entry.lower()
    if normalized.startswith("/"):
        normalized = normalized[1:]
    return normalized == identifier' \
  '    return True'

# The regression a round-9 review found in the gate itself: stripping before the
# comparison re-introduces the lossiness the gate exists to reject, and wrapping
# an ALLOWLISTED name in whitespace then reaches TOLERATED.
register_mutation strip-before-the-whole-value-comparison \
  '    normalized = entry.lower()' \
  '    normalized = entry.strip().lower()'

register_mutation drop-host-vocabulary-breach-guard \
  '        if unclassifiable_vocabulary and not surface_breached:' \
  '        if unclassifiable_vocabulary:'

# The two parse paths implement the class separately, so each needs its own
# mutant: dropping it from the main-invocation predicate leaves the probe path
# correct, which is exactly the shape of divergence this oracle exists to catch.
register_mutation drop-host-vocabulary-from-main-path \
  'runtime_drift_only = bool(unknown or unverifiable or vocabulary) and not (' \
  'runtime_drift_only = bool(unknown or unverifiable) and not ('

# Dispatch the registered walk with bounded concurrency. The mutants are
# independent by construction: each writes its own `mutant_<name>.py` copy under
# $tmp_dir and runs the oracle against that copy, sharing nothing writable. Only
# the SCHEDULE changes -- every assertion in mutate_and_expect_mismatch still runs
# once per mutant. This suite was CI's slowest single entry (pure subprocess time,
# zero sleeps), so serial dispatch left the runner's other cores idle.
# Output is replayed in REGISTRATION order so a parallel run reads like the serial
# one, and any failure's stderr is replayed before the run is failed.
mutation_jobs="${INIT_POLICY_MATRIX_JOBS:-${SUITE_JOBS:-4}}"
case "$mutation_jobs" in ''|*[!0-9]*) mutation_jobs=4 ;; esac
[ "$mutation_jobs" -ge 1 ] || mutation_jobs=1

walk_total=${#mutation_names[@]}
if [ "$walk_total" -lt 1 ]; then
  printf 'the mutation walk registered nothing; the sensitivity check is disarmed\n' >&2
  exit 1
fi

walk_i=0
while [ "$walk_i" -lt "$walk_total" ]; do
  # `-p` is load-bearing: plain `jobs -r` prints multi-line command text, so a
  # line count would read one running job as several and degrade to serial.
  while [ "$(jobs -rp 2>/dev/null | wc -l)" -ge "$mutation_jobs" ]; do sleep 0.1; done
  (
    if mutate_and_expect_mismatch \
      "${mutation_names[$walk_i]}" "${mutation_finds[$walk_i]}" "${mutation_replaces[$walk_i]}" \
      >"$tmp_dir/walk_out_$walk_i" 2>"$tmp_dir/walk_err_$walk_i"
    then printf 'ok\n' >"$tmp_dir/walk_status_$walk_i"
    else printf 'failed\n' >"$tmp_dir/walk_status_$walk_i"; fi
  ) &
  walk_i=$((walk_i + 1))
done
wait

# Every registered index must have written an EXPLICIT terminal status. A worker
# killed before it could report (fatal shell error, OOM, cancellation) leaves no
# file, and treating that absence as success would bank a mutant that never ran
# as proof of sensitivity — the same absence-means-pass defect this walk's own
# guard exists to prevent one level down.
walk_failed=0
walk_i=0
while [ "$walk_i" -lt "$walk_total" ]; do
  cat "$tmp_dir/walk_out_$walk_i" 2>/dev/null
  if [ ! -f "$tmp_dir/walk_status_$walk_i" ]; then
    printf 'mutation %s never reported a terminal status; its worker died without completing\n' \
      "${mutation_names[$walk_i]}" >&2
    cat "$tmp_dir/walk_err_$walk_i" 2>/dev/null >&2
    walk_failed=1
  elif [ "$(cat "$tmp_dir/walk_status_$walk_i")" != ok ]; then
    cat "$tmp_dir/walk_err_$walk_i" >&2
    walk_failed=1
  fi
  walk_i=$((walk_i + 1))
done
if [ "$walk_failed" -ne 0 ]; then
  printf 'the mutation walk reported at least one non-sensitive or broken mutant (see above)\n' >&2
  exit 1
fi

if [ "$(shasum -a 256 "$parser" | awk '{print $1}')" != "$pristine_digest" ]; then
  printf 'the mutation walk modified the real parser; every mutation must stay in a copy\n' >&2
  exit 1
fi

printf 'init_policy_matrix_ok\n'
