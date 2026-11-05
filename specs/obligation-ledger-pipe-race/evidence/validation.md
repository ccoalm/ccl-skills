# Validation

## Behavioral evidence (RED-baseline, constructed and recorded)

| Case | Before the change | After the change |
| --- | --- | --- |
| The helper's two checks on a synthetic two-line output (an `ERROR STALE_LEDGER:` line, then a 300-character line), `pipefail`, 3,000 runs each form, host load 15 to 40 | pipe form: 331 false misses | here-string form: 0 |
| Stock suite, standalone, same tree | 1 of 3 runs failed: `FAIL stale_locator: expected first code STALE_LEDGER at specs/ledger.md, got: ERROR STALE_LEDGER: <tmp>/stale_locator/specs/ledger.md` with the `fix:` line, which contains both strings | 5 of 5 standalone runs passed, run in parallel at load average 62 to 76 |

## Mutation walk

Each mutant copies the scripts directory to a scratch dir, replaces exactly one string in the suite copy (the runner asserts the string occurs once), and runs it with its own `TMPDIR`. Killed means a non-zero exit whose first FAIL line is the mutated check's own message; for the two bare checks at old lines 564 and 565, which fail through `set -e` without a message, killed means a non-zero exit with no FAIL line and the next check's PASS line absent.

| Mutant | Check | Result |
| --- | --- | --- |
| control (unmutated copy) | all | green, no FAIL line |
| `exact_mechanical=` → unmatchable | old 564 | killed, silent `set -e` exit before `PASS pinned-head domain freeze` |
| `reviewed_semantic=` → unmatchable | old 565 | killed, as above |
| pinned `audit_ok` → unmatchable | old 591 | killed: `FAIL pinned-head audit missing audit_ok` |
| unpinned `ROW_SET_MISMATCH` → unmatchable | old 598 | killed: `FAIL unpinned audit failed for the wrong reason` |
| `^ERROR $expected_code:` → unmatchable | old 620 | killed: `FAIL missing_row: expected first code ROW_SET_MISMATCH …` |
| `$expected_target` → unmatchable | old 621 | killed: as above |
| target check replaced by `true` | old 621, negative direction | killed: `FAIL mutation target attribution: unrelated same-code target was accepted` |
| delta-has-mapping → match everything | old 652 | killed: `FAIL wrong_parent: expected single mapping-row delta …` |
| target-is-source-row → match everything | old 653 | survived; see below |
| stale-fix-hint `^audit_ok` → unmatchable | old 1234 | killed: `FAIL stale fix hint: the printed command did not clear STALE_LEDGER` |
| the stale-fix-hint assignment's own command replaced by one that prints `audit_ok` and exits 1; paired control exits 0 | old 1234, exit status | exit 1: killed at `FAIL stale fix hint: the printed command did not clear STALE_LEDGER`; exit 0: that check's PASS line prints and the suite is green, so the exit status alone decides |
| carrier `^ERROR $carrier_code:` → unmatchable | old 1256 | killed: `FAIL render cannot clear wrong_parent …` |

The surviving mutant is not introduced by this change. The old-653 conjunct only narrows when the row-delta check runs, and no case has a mapping-file delta with a target outside `skills/source/`, so matching everything changes no outcome. The same mutant applied to the stock suite on `origin/main` also exits 0. It stays unpinned, as it was; pinning it means adding a case, which is outside this round.

## Replay

No pipe into `grep` remains in the suite: `grep -n '| *grep' skills/skill-extraction-workflow/scripts/test_obligation_ledger.sh` exits 1 with no output on `a8bca3c`.

Probe of the helper's shape, run as `bash probe.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail
out=$'ERROR STALE_LEDGER: /tmp/x/stale_locator/specs/ledger.md\nfix: regenerate the ledger: python3 '"$(printf 'a%.0s' $(seq 1 300))"
m() { printf '%s\n' "$3" | grep -q "^ERROR $1:" && printf '%s\n' "$3" | grep -Fq "$2"; }
m2() { grep -q "^ERROR $1:" <<<"$3" && grep -Fq "$2" <<<"$3"; }
f=0; f2=0
for i in $(seq 1 3000); do m STALE_LEDGER specs/ledger.md "$out" || f=$((f+1)); m2 STALE_LEDGER specs/ledger.md "$out" || f2=$((f2+1)); done
echo "pipe_fail=$f herestring_fail=$f2 of 3000"
```

Output: `pipe_fail=331 herestring_fail=0 of 3000`.

Mutation walk, run as `python3 mutwalk.py skills/skill-extraction-workflow/scripts <scratch-dir>` with umask 022. Each entry is (exact text replaced once, replacement, expected first FAIL line or none for a silent `set -e` exit, PASS line that must then be absent):

```python
import concurrent.futures as cf, os, shutil, subprocess, sys
from pathlib import Path

SRC, WORK, SUITE = Path(sys.argv[1]), Path(sys.argv[2]), "test_obligation_ledger.sh"
MUTANTS = {
    "control": (None, None, None, None),
    "m564_exact_mechanical": ("grep -Fq 'exact_mechanical=' <<<", "grep -Fq 'exact_mechanical=MUTANT' <<<", None, "PASS pinned-head domain freeze"),
    "m565_reviewed_semantic": ("grep -Fq 'reviewed_semantic=' <<<", "grep -Fq 'reviewed_semantic=MUTANT' <<<", None, "PASS pinned-head domain freeze"),
    "m591_pinned_audit_ok": ("grep -Fq 'audit_ok' <<<\"$pinned_audit\"", "grep -Fq 'audit_okMUTANT' <<<\"$pinned_audit\"", "FAIL pinned-head audit missing audit_ok", None),
    "m598_unpinned_row_set": ("grep -Fq 'ROW_SET_MISMATCH' <<<\"$unpinned_audit\"", "grep -Fq 'ROW_SET_MISMATCHMUTANT' <<<\"$unpinned_audit\"", "FAIL unpinned audit failed for the wrong reason", None),
    "m620_error_code": ("grep -q \"^ERROR $expected_code:\" <<<\"$output\"", "grep -q \"^ERROR MUTANT$expected_code:\" <<<\"$output\"", "FAIL missing_row: expected first code", None),
    "m621_target": ("grep -Fq \"$expected_target\" <<<\"$output\"", "grep -Fq \"MUTANT$expected_target\" <<<\"$output\"", "FAIL missing_row: expected first code", None),
    "m621_target_dropped": ("grep -Fq \"$expected_target\" <<<\"$output\"", "true", "FAIL mutation target attribution", None),
    "m652_delta_has_mapping": ("grep -Fq 'specs/mapping.jsonl' <<<\"$actual_delta\"", "grep -Fq '' <<<\"$actual_delta\"", "expected single mapping-row delta", None),
    "m653_target_is_source_row": ("grep -q '^skills/source/.*#[0-9]' <<<\"$expected_target\"", "grep -q '' <<<\"$expected_target\"", "expected single mapping-row delta", None),
    "m1234_stale_audit_ok": ("grep -q '^audit_ok' <<<\"$stale_fixed_output\"", "grep -q '^audit_okMUTANT' <<<\"$stale_fixed_output\"", "FAIL stale fix hint: the printed command did not clear STALE_LEDGER", None),
    "m1257_carrier_code": ("grep -q \"^ERROR $carrier_code:\" <<<\"$carrier_output\"", "grep -q \"^ERROR MUTANT$carrier_code:\" <<<\"$carrier_output\"", "FAIL render cannot clear", None),
}

def run(name):
    old, new, expect, absent = MUTANTS[name]
    case = WORK / name
    shutil.rmtree(case, ignore_errors=True)
    shutil.copytree(SRC, case / "scripts", ignore=shutil.ignore_patterns("__pycache__"))
    suite = case / "scripts" / SUITE
    if old is not None:
        text = suite.read_text(encoding="utf-8")
        if text.count(old) != 1:
            return name, f"SETUP-ERROR: pattern count {text.count(old)}"
        suite.write_text(text.replace(old, new), encoding="utf-8")
    (case / "tmp").mkdir()
    proc = subprocess.run(["bash", str(suite)], capture_output=True, text=True, env=dict(os.environ, TMPDIR=str(case / "tmp")))
    out = proc.stdout + proc.stderr
    fails = [line for line in out.splitlines() if line.startswith("FAIL") or "FAIL " in line[:40]]
    first = fails[0] if fails else ""
    if old is None:
        verdict = "ok" if proc.returncode == 0 and not fails else "CONTROL-NOT-GREEN"
    elif proc.returncode == 0:
        verdict = "SURVIVED"
    elif expect is None:
        verdict = "killed" if not fails and absent not in out else "WRONG-REASON"
    else:
        verdict = "killed" if expect in first else "WRONG-REASON"
    return name, f"{verdict} rc={proc.returncode} first_fail={first[:110]!r}"

with cf.ThreadPoolExecutor(max_workers=7) as pool:
    for name, result in pool.map(run, MUTANTS):
        print(f"{name}: {result}", flush=True)
```

The exit-status pair replaces, in a scratch copy, `stale_fixed_output="$(python3 "$TOOL" audit --repo "$stale_case"` with `stale_fixed_output="$(python3 -c 'import sys; print("audit_ok"); sys.exit(N)' "$TOOL" audit --repo "$stale_case"` for N = 1 and N = 0, so the check sees the same `audit_ok` text from the assignment it guards and only the exit status differs. The stock-suite check of the old-653 mutant replaces `printf '%s\n' "$expected_target" | grep -q '^skills/source/.*#[0-9]'` with the same command matching `''` in the `origin/main` copy, in a scratch copy of the scripts directory. Stress: five copies of `bash skills/skill-extraction-workflow/scripts/test_obligation_ledger.sh` started together, each with its own `TMPDIR`.

## Local lanes on the candidate

Candidate `2e47a93`, tree clean, tracked files at 644/755. Later commits add only this record.

| Lane | Result | Failed attempts |
| --- | --- | --- |
| `make test-repo-gates` | passed, load 7 to 19 | 2 on earlier commits of this branch, both from this round's records and both fixed: the impact-chain gate rejected the register row after a later commit edited it (branch rebuilt, see Review passes), and the spec-reference check read the fixture's ledger path in `plan.md` as a repository citation (reworded) |
| `make test-regressions-fast` | passed, load 8 to 17 | none on `2e47a93` |
| `make test-code-review-1` | passed, load 6 to 16 | none |
| `make test-code-review-2` | passed, load 4 to 13 | none |
| `make test-code-review-abort-leak` | passed in a private PID namespace (`unshare --user --map-root-user --pid --fork --mount-proc`) | outside a namespace leg 1 fails on this host, which reparents orphans to a subreaper rather than PID 1 |

## Review passes

Base `9f758e191757`. Reviewer: codex (implementer family: claude).

| Pass | Commit reviewed | Result | Disposition |
| --- | --- | --- | --- |
| Review (`review.json`) | `a8bca3c` | 3 P2: the register row said every converted check turns red, against the surviving old-653 mutant; `make test` had not run; the probe, mutation and stress runs were not replayable from the record and no whole-suite scan was shown | Register row now states 12 of 13 and the survivor's status. Lane results recorded above from the final run. Replay section added with the probe, the mutation runner and the scan command |
| Challenge (`challenge.json`), focus: false greens | `72c60f2` | 1 P2: the exit-status mutant prepended a separate failing assignment, so it reached FAIL without exercising the guarded assignment's status leg | Replaced by the paired probe on the guarded assignment itself (mutation table, Replay); exit 1 fails at that check, exit 0 passes it. No change to the suite |

The reviewed commits `a8bca3c` and `72c60f2` were local only. `72c60f2` edited this round's register row, and the impact-chain gate scopes rows per round, so an edited row no longer resolves against the round that added it. The branch was rebuilt from `origin/main` into `7f9c2b0` (the suite and the row in its final wording) and `8984a6c` (these records); the rebuilt tree is identical to the last local commit `f2de976`. The challenge read that final row wording at `72c60f2`.
