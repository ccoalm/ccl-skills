#!/usr/bin/env bash
# Regression test for eval-routing-bank's routing_surface self-identification:
# every emitted report must name the exact surface it graded — the raw
# description-line surface (byte-compatible with the binding wrapper's
# surface_hash), a per-skill description-line hash map, the graded catalog
# text's own hash (post desc-budget truncation), and the bank bytes — so a
# round artifact can never be attributed to the wrong wording by operator
# assertion alone. Uses a fake claude earlier in PATH; never invokes a real
# Claude CLI or account. Grading semantics must be untouched.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd -P)"
EVAL_SCRIPT="$SCRIPT_DIR/eval-routing-bank.rb"
[ -f "$EVAL_SCRIPT" ] || { echo "FAIL: eval script not found: $EVAL_SCRIPT" >&2; exit 1; }

TMP="$(mktemp -d "${TMPDIR:-/tmp}/eval-routing-bank-surface.XXXXXX")"
cleanup() { rm -rf "$TMP"; }
trap cleanup EXIT

fail() { echo "FAIL: $*" >&2; exit 1; }

REPO="$TMP/repo"
FAKE_BIN="$TMP/bin"
mkdir -p "$REPO/skills/testing-strategy" "$REPO/skills/product-rd-workflow" "$REPO/eval" "$FAKE_BIN"

git -C "$TMP" init -q repo
git -C "$REPO" config user.email test@example.invalid
git -C "$REPO" config user.name "Test User"

cat > "$REPO/skills/testing-strategy/SKILL.md" <<'EOF'
---
description: Use when choosing test layers and regression evidence.
---
# Testing Strategy
EOF

cat > "$REPO/skills/product-rd-workflow/SKILL.md" <<'EOF'
---
description: Use as the product delivery entry router for features and specs.
---
# Product RD Workflow
EOF

cat > "$REPO/eval/routing-tasks.jsonl" <<'EOF'
{"id":"surface-case","utterance":"补一个回归测试","expected_skill":"testing-strategy","frozen_at_sha":""}
EOF

git -C "$REPO" add -A
git -C "$REPO" commit -qm "fixture"

cat > "$FAKE_BIN/claude" <<'EOF'
#!/usr/bin/env bash
cat >/dev/null
printf '{"selected_skill": "testing-strategy", "confidence": 0.9, "rationale_short": "stub"}\n'
EOF
chmod +x "$FAKE_BIN/claude"

report1="$TMP/report1.json"
report2="$TMP/report2.json"
set +e
out1="$(PATH="$FAKE_BIN:$PATH" ruby "$EVAL_SCRIPT" "$REPO" --json "$report1" --timeout 60 2>&1)"
rc1=$?
out2="$(PATH="$FAKE_BIN:$PATH" ruby "$EVAL_SCRIPT" "$REPO" --json "$report2" --timeout 60 --desc-budget-chars 10 2>&1)"
rc2=$?
set -e
[ "$rc1" = "0" ] || fail "plain arm exited $rc1: $out1"
[ "$rc2" = "0" ] || fail "budget arm exited $rc2: $out2"

REPO_DIR="$REPO" python3 - "$report1" "$report2" <<'PYEOF'
import hashlib, json, os, sys, glob

report1 = json.load(open(sys.argv[1]))
report2 = json.load(open(sys.argv[2]))
repo = os.environ["REPO_DIR"]

def fail(msg):
    print("FAIL: " + msg, file=sys.stderr)
    sys.exit(1)

rs1 = report1.get("routing_surface")
if not isinstance(rs1, dict):
    fail("report has no routing_surface object")

# Grading semantics untouched: the stub grader's verdict still lands as PASS.
if report1["results"][0]["status"] != "PASS":
    fail("grading changed: expected PASS, got %r" % report1["results"][0]["status"])

bank_bytes = open(os.path.join(repo, "eval", "routing-tasks.jsonl"), "rb").read()
if rs1.get("bank_sha256") != hashlib.sha256(bank_bytes).hexdigest():
    fail("bank_sha256 does not match the bank file bytes")

# Recompute the wrapper-compatible surface: dir-name-tagged raw description
# lines in sorted glob order (line bytes include the trailing newline, matching
# `grep -m1 '^description:'` piped output), then the bank bytes.
surface = b""
expected_per_skill = {}
for path in sorted(glob.glob(os.path.join(repo, "skills", "*", "SKILL.md"))):
    name = os.path.basename(os.path.dirname(path))
    line = None
    with open(path, "rb") as f:
        for l in f:
            if l.startswith(b"description:"):
                line = l
                break
    if line is None:
        continue
    surface += name.encode() + b"\t" + line
    expected_per_skill[name] = hashlib.sha256(line).hexdigest()
if rs1.get("descriptions_sha256") != hashlib.sha256(surface + bank_bytes).hexdigest():
    fail("descriptions_sha256 does not match the wrapper-compatible surface bytes")

per_skill = rs1.get("per_skill_description_line_sha256")
if per_skill != expected_per_skill:
    fail("per_skill_description_line_sha256 mismatch: got %r expected %r" % (per_skill, expected_per_skill))

if not rs1.get("catalog_sha256"):
    fail("catalog_sha256 missing or empty")

rs2 = report2.get("routing_surface")
if not isinstance(rs2, dict):
    fail("budget-arm report has no routing_surface object")
if rs2.get("catalog_sha256") == rs1.get("catalog_sha256"):
    fail("desc-budget truncation must change catalog_sha256")
if rs2.get("descriptions_sha256") != rs1.get("descriptions_sha256"):
    fail("desc-budget truncation must NOT change the raw descriptions_sha256")
print("surface binding assertions ok")
PYEOF

# The multiline-description differential (both review lanes' finding): editing a
# `description: >-` CONTINUATION line changes what the grader sees but not the
# raw first line, so descriptions_sha256 must stay UNCHANGED (the documented
# raw-surface blind spot) while catalog_sha256 must CHANGE — which is exactly
# why the graded-catalog binding is load-bearing on its own and the round
# wrapper cross-checks it independently.
mkdir -p "$REPO/skills/platform-observability"
cat > "$REPO/skills/platform-observability/SKILL.md" <<'EOF'
---
description: >-
  Use when wiring service logs and metrics.
  Continuation line one for the multiline fixture.
---
# Platform Observability
EOF

report3="$TMP/report3.json"
report4="$TMP/report4.json"
set +e
out3="$(PATH="$FAKE_BIN:$PATH" ruby "$EVAL_SCRIPT" "$REPO" --json "$report3" --timeout 60 2>&1)"
rc3=$?
set -e
[ "$rc3" = "0" ] || fail "multiline baseline arm exited $rc3: $out3"

perl -pi -e 's/Continuation line one for the multiline fixture\./Continuation line one, materially reworded\./' "$REPO/skills/platform-observability/SKILL.md"

set +e
out4="$(PATH="$FAKE_BIN:$PATH" ruby "$EVAL_SCRIPT" "$REPO" --json "$report4" --timeout 60 2>&1)"
rc4=$?
set -e
[ "$rc4" = "0" ] || fail "multiline mutated arm exited $rc4: $out4"

python3 - "$report3" "$report4" <<'PYEOF'
import json, sys

r3 = json.load(open(sys.argv[1]))["routing_surface"]
r4 = json.load(open(sys.argv[2]))["routing_surface"]

def fail(msg):
    print("FAIL: " + msg, file=sys.stderr)
    sys.exit(1)

if r3["descriptions_sha256"] != r4["descriptions_sha256"]:
    fail("editing a continuation line must NOT change the raw descriptions_sha256 (that blind spot is documented, not fixed here)")
if r3["catalog_sha256"] == r4["catalog_sha256"]:
    fail("editing a continuation line MUST change catalog_sha256 — the graded-catalog binding is load-bearing")
print("multiline differential assertions ok")
PYEOF

echo "test_eval_routing_bank_surface_binding: ok"
