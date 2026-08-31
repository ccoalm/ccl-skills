#!/usr/bin/env bash
# Tests for gate_receipt.py — candidate-SHA-bound receipts of deterministic-gate
# output. Proves the mint preconditions (clean committed tree, out-of-tree
# receipt, never overwrite), the structural validator, and — critically — that
# the re-run verifier goes RED for the RIGHT reason under applied mutations
# (tampered output hash, tampered exit code, foreign key), and stays infra (rc 2,
# no verdict) when the environment cannot judge (wrong checked-out candidate,
# dirty tree). RED-run receipts (non-zero recorded exit) are first-class: the
# pre-fix RED claim is the canonical use case.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd -P)"
GR="$SCRIPT_DIR/gate_receipt.py"
[ -f "$GR" ] || { echo "FAIL: gate_receipt.py not found: $GR" >&2; exit 1; }

fail() { echo "FAIL: $*" >&2; exit 1; }
assert_rc() { [ "$1" = "$2" ] || fail "expected rc=$2 got rc=$1${3:+ ($3)}"; }
assert_contains() { case "$2" in *"$1"*) : ;; *) fail "expected output to contain: $1${3:+ ($3)}; got: $2";; esac; }

TMP="$(mktemp -d "${TMPDIR:-/tmp}/gatereceipt.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
REPO="$TMP/repo"; LEDGER="$TMP/ledger"
mkdir -p "$REPO" "$LEDGER"
git -C "$REPO" init -q
git -C "$REPO" config user.email test@example.invalid
git -C "$REPO" config user.name test
echo seed > "$REPO/f.txt"
git -C "$REPO" add f.txt
git -C "$REPO" commit -qm init

run_gr() { (cd "$REPO" && python3 "$GR" "$@"); }

# (1) Mint on a clean tree, green command; receipt lands out of tree.
set +e
out="$(run_gr mint --out "$LEDGER/green.json" -- bash -c 'echo gate-output; exit 0' 2>&1)"; rc=$?
set -e
assert_rc "$rc" 0 "mint green"
assert_contains "gate_receipt_minted:" "$out" "mint green token"
head_sha="$(git -C "$REPO" rev-parse HEAD)"
assert_contains "candidate=$head_sha" "$out" "mint records HEAD"

# (2) Never overwrite an existing receipt.
set +e
out="$(run_gr mint --out "$LEDGER/green.json" -- true 2>&1)"; rc=$?
set -e
assert_rc "$rc" 2 "mint overwrite refused"
assert_contains "never overwritten" "$out" "overwrite message"

# (3) Refuse a dirty tree (a receipt binds a committed candidate only).
echo drift >> "$REPO/f.txt"
set +e
out="$(run_gr mint --out "$LEDGER/dirty.json" -- true 2>&1)"; rc=$?
set -e
assert_rc "$rc" 2 "mint dirty tree refused"
assert_contains "tree not clean" "$out" "dirty message"
git -C "$REPO" checkout -q f.txt

# (4) A RED run mints fine — recorded exit code, not required success.
set +e
out="$(run_gr mint --out "$LEDGER/red.json" -- bash -c 'echo failing; exit 3' 2>&1)"; rc=$?
set -e
assert_rc "$rc" 0 "mint red run"
assert_contains "exit=3" "$out" "red exit recorded"

# (5) Structural verify passes for both receipts.
set +e
out="$(run_gr verify "$LEDGER/green.json" 2>&1)"; rc=$?
set -e
assert_rc "$rc" 0 "structural green"
assert_contains "gate_receipt_structural_ok" "$out" "structural token"

# (6) Re-run verify passes: green receipt and red-recorded receipt alike.
set +e
out="$(run_gr verify "$LEDGER/green.json" --rerun -- bash -c 'echo gate-output; exit 0' 2>&1)"; rc=$?
set -e
assert_rc "$rc" 0 "rerun green"
assert_contains "scope=full" "$out" "rerun full scope"
set +e
out="$(run_gr verify "$LEDGER/red.json" --rerun -- bash -c 'echo failing; exit 3' 2>&1)"; rc=$?
set -e
assert_rc "$rc" 0 "rerun red-recorded"

# (7) APPLIED MUTATION: tampered output hash -> rc 1, named output_hash_mismatch.
python3 - "$LEDGER" <<'EOF'
import json, sys
ledger = sys.argv[1]
d = json.load(open(f"{ledger}/green.json"))
d["output_sha256"] = "0" * 64
open(f"{ledger}/tampered-hash.json", "w").write(
    json.dumps(d, ensure_ascii=False, sort_keys=True, indent=1) + "\n")
EOF
set +e
out="$(run_gr verify "$LEDGER/tampered-hash.json" --rerun -- bash -c 'echo gate-output; exit 0' 2>&1)"; rc=$?
set -e
assert_rc "$rc" 1 "tampered hash"
assert_contains "output_hash_mismatch" "$out" "tampered hash reason"

# (8) APPLIED MUTATION: tampered exit code -> rc 1, named exit_code_mismatch.
python3 - "$LEDGER" <<'EOF'
import json, sys
ledger = sys.argv[1]
d = json.load(open(f"{ledger}/red.json"))
d["exit_code"] = 0
open(f"{ledger}/tampered-exit.json", "w").write(
    json.dumps(d, ensure_ascii=False, sort_keys=True, indent=1) + "\n")
EOF
set +e
out="$(run_gr verify "$LEDGER/tampered-exit.json" --rerun -- bash -c 'echo failing; exit 3' 2>&1)"; rc=$?
set -e
assert_rc "$rc" 1 "tampered exit"
assert_contains "exit_code_mismatch" "$out" "tampered exit reason"

# (9) APPLIED MUTATION: foreign key -> rc 1 structural (exact key set enforced).
python3 - "$LEDGER" <<'EOF'
import json, sys
ledger = sys.argv[1]
d = json.load(open(f"{ledger}/green.json"))
d["note"] = "smuggled"
open(f"{ledger}/extra-key.json", "w").write(
    json.dumps(d, ensure_ascii=False, sort_keys=True, indent=1) + "\n")
EOF
set +e
out="$(run_gr verify "$LEDGER/extra-key.json" 2>&1)"; rc=$?
set -e
assert_rc "$rc" 1 "extra key"
assert_contains "exactly the gate-receipt key set" "$out" "extra key reason"

# (10) Wrong checked-out candidate -> rc 2 (no verdict), named wrong_candidate.
echo advance >> "$REPO/f.txt"
git -C "$REPO" commit -qam advance
set +e
out="$(run_gr verify "$LEDGER/green.json" --rerun -- bash -c 'echo gate-output; exit 0' 2>&1)"; rc=$?
set -e
assert_rc "$rc" 2 "wrong candidate"
assert_contains "wrong_candidate" "$out" "wrong candidate reason"
git -C "$REPO" reset -q --hard "$head_sha"

# (11) Nondeterministic gate output: full rerun red, --exit-only green.
# (python3 secrets, not `date +%N`: BSD/macOS date prints a literal N, which
# would be deterministic and silently invert this case on those hosts.)
set +e
out="$(run_gr mint --out "$LEDGER/nondet.json" -- python3 -c 'import secrets; print(secrets.token_hex())' 2>&1)"; rc=$?
set -e
assert_rc "$rc" 0 "mint nondet"
set +e
out="$(run_gr verify "$LEDGER/nondet.json" --rerun -- python3 -c 'import secrets; print(secrets.token_hex())' 2>&1)"; rc=$?
set -e
assert_rc "$rc" 1 "nondet full rerun"
assert_contains "output_hash_mismatch" "$out" "nondet reason"
set +e
out="$(run_gr verify "$LEDGER/nondet.json" --rerun --exit-only -- python3 -c 'import secrets; print(secrets.token_hex())' 2>&1)"; rc=$?
set -e
assert_rc "$rc" 0 "nondet exit-only"
assert_contains "scope=exit-only" "$out" "exit-only scope token"

# (12) --exit-only without --rerun is a usage error, not a verdict.
set +e
out="$(run_gr verify "$LEDGER/green.json" --exit-only 2>&1)"; rc=$?
set -e
assert_rc "$rc" 2 "exit-only without rerun"

# (13) Dirty tree at the CORRECT candidate: rerun verification is rc 2 named
# dirty_tree (no verdict) — dirty state must never surface as a false rc 0/1.
echo drift >> "$REPO/f.txt"
set +e
out="$(run_gr verify "$LEDGER/green.json" --rerun -- bash -c 'echo gate-output; exit 0' 2>&1)"; rc=$?
set -e
assert_rc "$rc" 2 "dirty rerun"
assert_contains "dirty_tree" "$out" "dirty rerun reason"
git -C "$REPO" checkout -q f.txt

# (14) Signal-killed gate: minted with the shell convention 128+N, structurally
# valid, and a re-run (which signals itself again) matches. A raw negative
# Python returncode would make a legitimate RED receipt unusable.
set +e
out="$(run_gr mint --out "$LEDGER/signal.json" -- bash -c 'kill -KILL $$' 2>&1)"; rc=$?
set -e
assert_rc "$rc" 0 "mint signal-killed"
assert_contains "exit=137" "$out" "signal exit normalized to 128+9"
set +e
out="$(run_gr verify "$LEDGER/signal.json" 2>&1)"; rc=$?
set -e
assert_rc "$rc" 0 "signal receipt structural"
set +e
out="$(run_gr verify "$LEDGER/signal.json" --rerun -- bash -c 'kill -KILL $$' 2>&1)"; rc=$?
set -e
assert_rc "$rc" 0 "signal receipt rerun"

# (15) Silent hanging gate: --timeout kills the process group and mints
# nothing (rc 2), instead of blocking forever on a pipe with no output.
set +e
out="$(run_gr mint --out "$LEDGER/hang.json" --timeout 3 -- bash -c 'sleep 60' 2>&1)"; rc=$?
set -e
assert_rc "$rc" 2 "hanging gate timeout"
assert_contains "no receipt minted" "$out" "timeout message"
[ ! -f "$LEDGER/hang.json" ] || fail "timeout must not leave a receipt"

# (16) Candidate moved mid-run (the gate itself commits): refuse, no receipt.
set +e
out="$(run_gr mint --out "$LEDGER/moved.json" -- git commit -q --allow-empty -m mid-run 2>&1)"; rc=$?
set -e
assert_rc "$rc" 2 "mid-run HEAD move"
assert_contains "candidate changed during the run" "$out" "mid-run move reason"
[ ! -f "$LEDGER/moved.json" ] || fail "mid-run move must not leave a receipt"
git -C "$REPO" reset -q --hard "$head_sha"

# (17) Repository-relative cwd is recorded and re-runs execute from it:
# mint from a subdirectory, verify --rerun from the repository root.
mkdir -p "$REPO/sub"
( cd "$REPO/sub" && python3 "$GR" mint --out "$LEDGER/subdir.json" -- bash -c 'cat ../f.txt' ) \
  || fail "mint from subdirectory"
python3 - "$LEDGER/subdir.json" <<'EOF'
import json, sys
d = json.load(open(sys.argv[1]))
assert d["cwd"] == "sub", d["cwd"]
assert d["output_tail"] == "", "tail must default to empty"
EOF
set +e
out="$(run_gr verify "$LEDGER/subdir.json" --rerun -- bash -c 'cat ../f.txt' 2>&1)"; rc=$?
set -e
assert_rc "$rc" 0 "subdir receipt rerun from repo root"

# (18) Receipts are created 0600, and the default tail is empty even for a
# gate that prints output (nothing verbatim is copied without opt-in).
perms="$(python3 -c "import os,sys,stat; print(oct(stat.S_IMODE(os.stat(sys.argv[1]).st_mode)))" "$LEDGER/green.json")"
[ "$perms" = "0o600" ] || fail "receipt permissions must be 0600, got $perms"
python3 - "$LEDGER/green.json" <<'EOF'
import json, sys
d = json.load(open(sys.argv[1]))
assert d["output_tail"] == "", "default mint must not embed a plaintext tail"
EOF

# (19) Opt-in tail with maximally invalid UTF-8: replacement decoding must not
# inflate the stored tail past the cap — the minted receipt stays structurally
# valid.
set +e
out="$(run_gr mint --out "$LEDGER/invalid-utf8.json" --tail-bytes 16384 -- python3 -c 'import sys; sys.stdout.buffer.write(b"\xff" * 16384)' 2>&1)"; rc=$?
set -e
assert_rc "$rc" 0 "mint invalid-utf8 tail"
set +e
out="$(run_gr verify "$LEDGER/invalid-utf8.json" 2>&1)"; rc=$?
set -e
assert_rc "$rc" 0 "invalid-utf8 tail receipt structural"

# (20) The verifier's command is mandatory and compared: --rerun without a
# command refuses (rc 2, the recorded argv is untrusted input), and a receipt
# whose recorded command differs from what the verifier typed is rc 1
# command_mismatch — the recorded argv is NEVER executed.
set +e
out="$(run_gr verify "$LEDGER/green.json" --rerun 2>&1)"; rc=$?
set -e
assert_rc "$rc" 2 "rerun without command"
assert_contains "candidate-controlled" "$out" "rerun-without-command reason"
set +e
out="$(run_gr verify "$LEDGER/green.json" --rerun -- bash -c 'echo attacker' 2>&1)"; rc=$?
set -e
assert_rc "$rc" 1 "command mismatch"
assert_contains "command_mismatch" "$out" "command mismatch reason"

# (21) Receipts may not be minted INSIDE the candidate repository (they would
# dirty the tree after the cleanliness check ran, or hide under .git).
set +e
out="$(run_gr mint --out "$REPO/in-tree.json" -- true 2>&1)"; rc=$?
set -e
assert_rc "$rc" 2 "in-tree receipt refused"
assert_contains "inside the candidate repository" "$out" "in-tree reason"
set +e
out="$(run_gr mint --out "$REPO/.git/hidden.json" -- true 2>&1)"; rc=$?
set -e
assert_rc "$rc" 2 "under-.git receipt refused"

# (22) A receipt the tool's own verifier would reject as oversized is never
# minted: huge argv refuses with rc 2 and no file.
set +e
big_arg="$(python3 -c 'print("x" * 70000)')"
out="$(run_gr mint --out "$LEDGER/huge.json" -- bash -c true bash "$big_arg" 2>&1)"; rc=$?
set -e
assert_rc "$rc" 2 "oversized receipt refused"
[ ! -f "$LEDGER/huge.json" ] || fail "oversized mint must not leave a receipt"

# (23) An EMPTY later argument is legal argv: mint, structural verify, and
# rerun must all round-trip (only command[0] must be non-empty).
set +e
out="$(run_gr mint --out "$LEDGER/empty-arg.json" -- printf '%s' '' 2>&1)"; rc=$?
set -e
assert_rc "$rc" 0 "mint empty-arg"
set +e
out="$(run_gr verify "$LEDGER/empty-arg.json" 2>&1)"; rc=$?
set -e
assert_rc "$rc" 0 "empty-arg structural"
set +e
out="$(run_gr verify "$LEDGER/empty-arg.json" --rerun -- printf '%s' '' 2>&1)"; rc=$?
set -e
assert_rc "$rc" 0 "empty-arg rerun"

# (24) An OS-level failure (permission denied on the gate binary) is rc 2
# no-verdict — never the rc 1 the contract reserves for a failed receipt.
: > "$TMP/noexec"
chmod -x "$TMP/noexec"
set +e
out="$(run_gr mint --out "$LEDGER/noexec.json" -- "$TMP/noexec" 2>&1)"; rc=$?
set -e
assert_rc "$rc" 2 "permission-denied gate"

# (25) status.showUntrackedFiles=no cannot hide untracked gate inputs: the
# explicit --untracked-files=all flag sees them and mint refuses.
git -C "$REPO" config status.showUntrackedFiles no
echo hidden > "$REPO/untracked-input.txt"
set +e
out="$(run_gr mint --out "$LEDGER/hidden-untracked.json" -- true 2>&1)"; rc=$?
set -e
assert_rc "$rc" 2 "hidden untracked state"
assert_contains "tree not clean" "$out" "hidden untracked reason"
rm "$REPO/untracked-input.txt"
git -C "$REPO" config --unset status.showUntrackedFiles

# (26) A forged cwd that is an in-repo symlink resolving OUTSIDE the
# repository is refused before anything executes.
ln -s "$TMP" "$REPO/escape"
git -C "$REPO" add escape
git -C "$REPO" commit -qm add-escape-symlink
python3 - "$LEDGER" "$(git -C "$REPO" rev-parse HEAD)" <<'EOF'
import json, sys
ledger, head = sys.argv[1], sys.argv[2]
d = json.load(open(f"{ledger}/green.json"))
d["cwd"] = "escape"
d["candidate_commit"] = head
open(f"{ledger}/forged-cwd.json", "w").write(
    json.dumps(d, ensure_ascii=False, sort_keys=True, indent=1) + "\n")
EOF
set +e
out="$(run_gr verify "$LEDGER/forged-cwd.json" --rerun -- bash -c 'echo gate-output; exit 0' 2>&1)"; rc=$?
set -e
assert_rc "$rc" 2 "forged escaping cwd"
assert_contains "resolves outside the repository" "$out" "escaping cwd reason"
git -C "$REPO" reset -q --hard "$head_sha"

# (27) An untracked filename with invalid UTF-8 bytes (core.quotePath=false)
# must yield rc 2 tree-not-clean — never an uncaught decode traceback exiting
# with the verdict-reserved rc 1. APFS refuses such names; skip the leg (with
# a printed marker) where the filesystem cannot produce the state.
git -C "$REPO" config core.quotePath false
if python3 -c 'import os,sys; os.close(os.open(os.path.join(sys.argv[1].encode(), b"\xff\xfebad"), os.O_CREAT|os.O_WRONLY, 0o644))' "$REPO" 2>/dev/null; then
  set +e
  out="$(run_gr mint --out "$LEDGER/badname.json" -- true 2>&1)"; rc=$?
  set -e
  assert_rc "$rc" 2 "invalid-utf8 filename"
  case "$out" in *Traceback*) fail "decode error surfaced as a traceback";; esac
  python3 -c 'import os,sys; os.unlink(os.path.join(sys.argv[1].encode(), b"\xff\xfebad"))' "$REPO"
else
  echo "note: filesystem refuses invalid-UTF-8 names; case 27 leg skipped"
fi
git -C "$REPO" config --unset core.quotePath

# (28) APPLIED MUTATION: forged output_bytes with genuine hash/exit -> rc 1
# named output_bytes_mismatch (every recorded field is compared on full rerun).
python3 - "$LEDGER" <<'EOF'
import json, sys
ledger = sys.argv[1]
d = json.load(open(f"{ledger}/green.json"))
d["output_bytes"] = d["output_bytes"] + 7
open(f"{ledger}/forged-bytes.json", "w").write(
    json.dumps(d, ensure_ascii=False, sort_keys=True, indent=1) + "\n")
EOF
set +e
out="$(run_gr verify "$LEDGER/forged-bytes.json" --rerun -- bash -c 'echo gate-output; exit 0' 2>&1)"; rc=$?
set -e
assert_rc "$rc" 1 "forged bytes"
assert_contains "output_bytes_mismatch" "$out" "forged bytes reason"

# (29) APPLIED MUTATION: forged human-readable tail -> rc 1 output_tail_mismatch;
# a genuine opt-in tail round-trips on full rerun.
set +e
out="$(run_gr mint --out "$LEDGER/tailed.json" --tail-bytes 4096 -- bash -c 'echo tail-content; exit 0' 2>&1)"; rc=$?
set -e
assert_rc "$rc" 0 "mint tailed"
set +e
out="$(run_gr verify "$LEDGER/tailed.json" --rerun -- bash -c 'echo tail-content; exit 0' 2>&1)"; rc=$?
set -e
assert_rc "$rc" 0 "genuine tail rerun"
python3 - "$LEDGER" <<'EOF'
import json, sys
ledger = sys.argv[1]
d = json.load(open(f"{ledger}/tailed.json"))
d["output_tail"] = "forged human-readable excerpt\n"
open(f"{ledger}/forged-tail.json", "w").write(
    json.dumps(d, ensure_ascii=False, sort_keys=True, indent=1) + "\n")
EOF
set +e
out="$(run_gr verify "$LEDGER/forged-tail.json" --rerun -- bash -c 'echo tail-content; exit 0' 2>&1)"; rc=$?
set -e
assert_rc "$rc" 1 "forged tail"
assert_contains "output_tail_mismatch" "$out" "forged tail reason"

# (30) A failed publish never wedges the slot: after an overwrite refusal the
# temp file is gone and the original receipt is intact.
set +e
out="$(run_gr mint --out "$LEDGER/green.json" -- true 2>&1)"; rc=$?
set -e
assert_rc "$rc" 2 "republish refused"
ls "$LEDGER"/green.json.tmp.* 2>/dev/null && fail "temp file left behind"
python3 -c 'import json,sys; json.load(open(sys.argv[1]))' "$LEDGER/green.json" || fail "original receipt corrupted"

# (31) APPLIED MUTATIONS on the tail binding: an EMPTIED tail and a TRUNCATED
# genuine suffix must both go red on full rerun — the tail is reconstructed at
# the recorded tail_bytes and compared exactly, so weakening the excerpt while
# keeping exit/hash cannot ride a full-verification verdict.
python3 - "$LEDGER" <<'EOF'
import json, sys
ledger = sys.argv[1]
d = json.load(open(f"{ledger}/tailed.json"))
d["output_tail"] = ""
open(f"{ledger}/emptied-tail.json", "w").write(
    json.dumps(d, ensure_ascii=False, sort_keys=True, indent=1) + "\n")
d2 = json.load(open(f"{ledger}/tailed.json"))
d2["output_tail"] = d2["output_tail"][-5:]
open(f"{ledger}/truncated-tail.json", "w").write(
    json.dumps(d2, ensure_ascii=False, sort_keys=True, indent=1) + "\n")
EOF
set +e
out="$(run_gr verify "$LEDGER/emptied-tail.json" --rerun -- bash -c 'echo tail-content; exit 0' 2>&1)"; rc=$?
set -e
assert_rc "$rc" 1 "emptied tail"
assert_contains "output_tail_mismatch" "$out" "emptied tail reason"
set +e
out="$(run_gr verify "$LEDGER/truncated-tail.json" --rerun -- bash -c 'echo tail-content; exit 0' 2>&1)"; rc=$?
set -e
assert_rc "$rc" 1 "truncated tail"
assert_contains "output_tail_mismatch" "$out" "truncated tail reason"

echo "test_gate_receipt: ok"
