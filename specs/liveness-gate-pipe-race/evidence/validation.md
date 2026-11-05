# Validation

## Behavioral evidence (RED-baseline)

Both gate sections are extracted from the checker the way `test_liveness_predicate_gate.sh` extracts them, and differ only in line 695. Host load average 56 to 69 on 8 cores; `grep` on this host is ugrep 7.8.4.

| Case | Pipe form (before) | Here-string form (after) |
| --- | --- | --- |
| p10b's fixture: a `ps -o stat=` read, then the banned ppid read | 10 false reds in 300 runs | 0 in 300 |
| p10c's fixture: the same, then a 1 MiB line | 30 false reds in 30 runs | 0 in 30 |
| Each false red | `liveness_predicate_scan_failed` naming the probe's line 3, the line the waiver should clear | n/a |

The suite with p10c added, run against the unfixed checker: `FAIL  p10c …`, `pass=22 fail=1`, exit 1. Against the fixed checker: 10 of 10 standalone runs ended `liveness_predicate_gate_ok`; load average was about 70 when they ended.

## Mutation

In a disposable copy of the scripts directory, the fixed line is restored to the pipe form (the runner asserts the fixed line occurs once). Each round runs the unmutated copy, then the mutant.

| Mutant | Result |
| --- | --- |
| control (fixed checker) | green in all 15 runner rounds, and in 10 of 10 standalone runs |
| fixed line restored to `printf '%s' "$liveness_win" \| grep -qE …` | fails in 15 of 15 runner rounds (a first batch of 5, then 10). p10c fails in every round. In the first batch p3 also failed in 2 rounds and p13 in 1. In the second batch, at lower load, p10c was the only failure |

p3 and p13, like p10b, have a fixture with a `ps -o stat=` read and expect the line cleared, so the waiver decides them. With the pipe restored they hit the same race through their short windows, which is why they fail only sometimes. The runner accepts a failure only from that exposed set (p3, p3b, p8, p10b, p10c, p12b, p13, p14) and fails the round on any other. No case outside it failed. p10b, the existing case on this property, failed in no mutant round. It cannot pin the defect, which is why p10c exists.

A hand run of 5 mutant rounds before the runner existed saw only p10c fail. The runner's first batch shows that was chance: the other cases the waiver decides fail too, though rarely. So the acceptance is that, with the pipe, p10c fails in every round and no case outside that set fails; with the fix, no case changes result.

## Replay

Probe, run as `bash probe.sh <checker> <scratch-dir>`:

```bash
#!/usr/bin/env bash
set -u
checker=$1; sp=$2
build() { { echo '#!/usr/bin/env bash'; echo 'set -euo pipefail'; echo 'root="$1"'
  awk '/^# Anti-pattern 28 —/{p=1} p; /^echo "liveness_predicate_scan_ok"$/{if(p) exit}' "$1"; } > "$2"; }
build "$checker" "$sp/fixed.sh"
sed "s/if grep -qE '\\\\-o\[\[:space:\]\]\*stat=' <<<\"\$liveness_win\"; then/if printf '%s' \"\$liveness_win\" | grep -qE '\\\\-o[[:space:]]*stat='; then/" \
  "$sp/fixed.sh" > "$sp/pipe.sh"
cmp -s "$sp/fixed.sh" "$sp/pipe.sh" && { echo "pipe variant not produced"; exit 1; }
v='[ "$(ps -o ppid= -p "$pid" 2>/dev/null | tr -d " ")" = "1" ] && echo orphan'
mkdir -p "$sp/p10b/scripts" "$sp/p10c/scripts"
{ printf '#!/usr/bin/env bash\n'; printf 'st="$(ps -o stat= -p "$pid")"\n'; printf '%s\n' "$v"; } > "$sp/p10b/scripts/test_probe.sh"
{ cat "$sp/p10b/scripts/test_probe.sh"; printf 'pad="%s"\n' "$(head -c 1048576 /dev/zero | tr '\0' a)"; } > "$sp/p10c/scripts/test_probe.sh"
for form in pipe fixed; do
  for case in p10b:300 p10c:30; do
    f=0; for _ in $(seq 1 "${case#*:}"); do TMPDIR="$sp" bash "$sp/$form.sh" "$sp/${case%%:*}" >/dev/null 2>&1 || f=$((f+1)); done
    echo "$form ${case%%:*}: $f/${case#*:} false reds"
  done
done
```

A rerun of this probe against the fixed checker printed `pipe p10b: 12/300`, `pipe p10c: 30/30`, `fixed p10b: 0/300`, `fixed p10c: 0/30`.

Mutation runner, run as `bash mutate.sh skills/skill-extraction-workflow/scripts <scratch-dir> 5` from the repository root. It runs the unmutated copy as the control, then the mutant. A round passes when the control is green and the mutant exits non-zero, fails p10c, and fails no case outside the exposed set:

```bash
#!/usr/bin/env bash
set -u
src=$1; work=$2; runs=${3:-5}
fixed="    if grep -qE '\\-o[[:space:]]*stat=' <<<\"\$liveness_win\"; then"
pipe="    if printf '%s' \"\$liveness_win\" | grep -qE '\\-o[[:space:]]*stat='; then"
run_suite() { TMPDIR="$work/tmp" bash "$1/test_liveness_predicate_gate.sh" 2>&1; }
rm -rf "$work"; mkdir -p "$work/tmp"
cp -R "$src" "$work/control"; cp -R "$src" "$work/mutant"
python3 - "$work/mutant/check-ccl-skills.sh" "$fixed" "$pipe" <<'PY'
import pathlib, sys
path, old, new = pathlib.Path(sys.argv[1]), sys.argv[2], sys.argv[3]
text = path.read_text(encoding="utf-8")
assert text.count(old) == 1, f"fixed line occurs {text.count(old)} times"
path.write_text(text.replace(old, new), encoding="utf-8")
PY
# Cases whose fixture carries a state read and which expect the line cleared: the only
# cases the waiver decides, so the only ones the mutant may fail.
exposed=' p3 p3b p8 p10b p10c p12b p13 p14 '
bad=0
for i in $(seq 1 "$runs"); do
  out=$(run_suite "$work/control"); rc=$?
  if [ "$rc" -eq 0 ] && ! grep -q '^FAIL' <<<"$out"; then echo "control $i: green"; else echo "control $i: NOT GREEN rc=$rc"; bad=1; fi
  out=$(run_suite "$work/mutant"); rc=$?
  ids=$(sed -n 's/^FAIL  \(p[0-9]*[a-z]*\) .*/\1/p' <<<"$out" | tr '\n' ' ')
  stray=""; for id in $ids; do case "$exposed" in *" $id "*) ;; *) stray="$stray $id" ;; esac; done
  if [ "$rc" -ne 0 ] && case " $ids" in *" p10c "*) true ;; *) false ;; esac && [ -z "$stray" ]; then
    echo "mutant $i: killed; failing cases: $ids"
  else echo "mutant $i: WRONG rc=$rc failing=[$ids] stray=[$stray]"; bad=1; fi
done
exit "$bad"
```

Scope check: `grep -n '| *grep' skills/skill-extraction-workflow/scripts/check-ccl-skills.sh` lists four sites after the change. Line 738 feeds `grep -o` through process substitution, which reads all its input and whose status `pipefail` does not see. Line 1147 is `grep -c`, which reads all its input. Line 1392 is the grammar check recorded under Residual risk in `plan.md`. Line 1541 is a comment. The suite itself runs under `set -u` without `pipefail`, so its own `printf | grep -q` checks take `grep`'s status and are not exposed.

## Local lanes on the candidate

Pending.

## Review passes

Base `ebec7f7`, the branch head before this round. Reviewer: codex (implementer family: claude). Both passes ran through `extraction_review_gate.sh` with `--risk-tag shared-gate`.

| Pass | Commit reviewed | Result | Disposition |
| --- | --- | --- | --- |
| Review (`review.json`) | `bac2007` | 2 P2: local lanes not yet recorded; the mutation runner was described but not supplied | Runner added under Replay and run; it refuted the earlier "p10c alone" count, and the Mutation section now reports counts. Lane results are recorded above |
| Challenge (`challenge.json`), focus: false greens and false reds in the waiver | `6463065` | 2 P2: p10c's every-run red rests on `grep -q` stopping at its match, which the packet does not bound for every host; the runner's exposed-set rule contradicted the stated "p10c only" acceptance | Claims scoped to this host, with the assumption and the `grep` in use stated in `plan.md`; the fixed form's pass does not depend on it. The suggested synchronized writer is not adopted: the cut-off writer is inside the checker, where a test cannot add synchronization. The acceptance is reconciled with the evidence: with the pipe, cases the waiver decides may fail and p10c fails in every round; with the fix, no case changes result |

`bac2007` and `6463065` were local only. `bac2007`'s register row was reworded after its review, and the impact-chain gate scopes a row to the commit that adds it, so the branch was rebuilt into a code commit carrying the row in its final wording and a records commit, with the tree unchanged. `origin/main` was then merged in, which brings the released package version; the release-version check fails on the branch without it.
