#!/usr/bin/env bash
# Behavior regression for the canonical review-plan intent updater.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd -P)"
UPDATER="$SCRIPT_DIR/update_review_plan_intent.py"
GATE="$SCRIPT_DIR/review_gate.py"
ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd -P)"
[ -f "$UPDATER" ] || { echo "FAIL: updater not found: $UPDATER" >&2; exit 1; }
[ -f "$GATE" ] || { echo "FAIL: review gate not found: $GATE" >&2; exit 1; }

TMP="$(mktemp -d "${TMPDIR:-/tmp}/review-plan-intent.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

fail() { echo "FAIL: $*" >&2; exit 1; }
assert_rc() { [ "$1" = "$2" ] || fail "expected rc=$2 got rc=$1 ($3)"; }
assert_contains() { case "$2" in *"$1"*) : ;; *) fail "expected '$1' ($3): $2";; esac; }
digest() { python3 - "$1" <<'PY'
import hashlib
import sys
from pathlib import Path

print(hashlib.sha256(Path(sys.argv[1]).read_bytes()).hexdigest())
PY
}

PLAN="$TMP/review-plan.json"
APPEND="$TMP/append.txt"
CORE="$TMP/core.txt"
LATEST="$TMP/latest.txt"
OLD_INTENT="$TMP/old-intent.txt"

python3 - "$PLAN" "$APPEND" "$CORE" "$LATEST" "$OLD_INTENT" <<'PY'
import json
import hashlib
import sys
from pathlib import Path

plan_path, append_path, core_path, latest_path, old_intent_path = map(
    Path, sys.argv[1:]
)
old = "scope:" + ("x" * (3995 - len("scope:") - len("c27"))) + "c27"
latest = "latest-round:c28"
core = old[: 3892 - len("\n\n") - len(latest)]
replacement = f"{core}\n\n{latest}"
assert len(old) == 3995 and old.endswith("c27")
assert len(replacement) == 3892 and old.startswith(core)
plan = {
    "intent": old,
    "acceptance": ["The candidate behavior is verified."],
    "self_review": [
        {
            "concern": concern,
            "skill": "code-review",
            "conclusion": conclusion,
            "evidence_refs": ["focused-test"],
        }
        for concern, conclusion in (
            ("correctness", "The focused checks cover the updater's accepted state transitions."),
            ("safety", "The focused checks cover no-write failures and file integrity boundaries."),
            ("failure_paths", "The focused checks cover overflow, stale input, and malformed text paths."),
            ("tests_evidence", "The focused regression fails when bounded update guarantees are removed."),
            ("compatibility", "The focused checks preserve the plan schema and original file permissions."),
        )
    ],
    "evidence": [
        {
            "id": "focused-test",
            "result": "The focused updater regression covers overflow and replacement behavior.",
        },
        {
            "id": "review-plan-intent-stable-core-v1",
            "result": (
                f"chars={len(core)};sha256="
                f"{hashlib.sha256(core.encode('utf-8')).hexdigest()}"
            ),
        },
    ],
}
plan_path.write_text(json.dumps(plan, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
append_path.write_text("\nlatest-round:c28", encoding="utf-8")
core_path.write_text(core, encoding="utf-8")
latest_path.write_text(latest, encoding="utf-8")
old_intent_path.write_text(old, encoding="utf-8")
PY
chmod 600 "$PLAN"

before="$(digest "$PLAN")"
set +e
out="$(python3 "$UPDATER" --plan "$PLAN" --append-intent-file "$APPEND" 2>&1)"
rc=$?
set -e
assert_rc "$rc" 2 "3995-character append must fail closed"
assert_contains "intent_append_overflow" "$out" "stable overflow reason"
[ "$(digest "$PLAN")" = "$before" ] || fail "overflow changed the plan"

# Duplicate JSON keys must fail before any rewrite. Otherwise json.loads keeps
# only the last value and the updater permanently erases bytes while claiming
# that intent compaction is loss-preserving.
python3 - "$PLAN" "$TMP/duplicate-plan.json" "$TMP/duplicate-append.txt" <<'PY'
import json
import sys
from pathlib import Path

source, target, append = map(Path, sys.argv[1:])
plan = json.loads(source.read_text(encoding="utf-8"))
plan["intent"] = "short stable intent"
rendered = json.dumps(plan, ensure_ascii=False, indent=2) + "\n"
rendered = rendered.replace(
    '  "acceptance":',
    '  "acceptance": ["discarded duplicate"],\n  "acceptance":',
    1,
)
target.write_text(rendered, encoding="utf-8")
append.write_text(" next transition", encoding="utf-8")
PY
duplicate_before="$(digest "$TMP/duplicate-plan.json")"
set +e
out="$(python3 "$UPDATER" --plan "$TMP/duplicate-plan.json" \
  --append-intent-file "$TMP/duplicate-append.txt" \
  --expected-sha256 "$duplicate_before" 2>&1)"
rc=$?
set -e
assert_rc "$rc" 2 "duplicate JSON keys must fail closed"
assert_contains "plan_duplicate_key" "$out" "duplicate-key reason"
[ "$(digest "$TMP/duplicate-plan.json")" = "$duplicate_before" ] \
  || fail "duplicate-key refusal changed the plan"

set +e
out="$(python3 "$UPDATER" --plan "$PLAN" --compact-core-intent-file "$CORE" --latest-intent-file "$LATEST" --expected-sha256 "$before" 2>&1)"
rc=$?
set -e
assert_rc "$rc" 0 "compact core+latest update should succeed"
assert_contains "review_plan_intent_updated" "$out" "success token"
[ "$(digest "$PLAN")" != "$before" ] || fail "replacement did not change the plan digest"
[ "$(stat -f '%Lp' "$PLAN" 2>/dev/null || stat -c '%a' "$PLAN")" = 600 ] || fail "plan mode was not preserved"
python3 - "$PLAN" "$OLD_INTENT" <<'PY'
import base64
import hashlib
import json
import sys
from pathlib import Path

plan = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
core = Path(sys.argv[1]).with_name("core.txt").read_text(encoding="utf-8")
latest = Path(sys.argv[1]).with_name("latest.txt").read_text(encoding="utf-8")
old_intent = Path(sys.argv[2]).read_text(encoding="utf-8")
assert plan["intent"] == f"{core}\n\n{latest}"
assert len(plan["intent"]) == 3892
assert set(plan) == {"intent", "acceptance", "self_review", "evidence"}

history_prefix = "review-plan-intent-history-v1-"
manifests = [
    row
    for row in plan["evidence"]
    if row.get("id", "").startswith(history_prefix)
    and row["id"].endswith("-manifest")
]
assert len(manifests) == 1, plan["evidence"]
manifest = manifests[0]
manifest_fields = dict(
    field.split("=", 1) for field in manifest["result"].split(";")
)
group = manifest["id"][len(history_prefix) : -len("-manifest")]
parts = sorted(
    (
        row
        for row in plan["evidence"]
        if row.get("id", "").startswith(f"{history_prefix}{group}-part-")
    ),
    key=lambda row: row["id"],
)
assert len(parts) == int(manifest_fields["parts"]), parts
encoded_suffix = "".join(
    row["result"].split(";data=", 1)[1] for row in parts
)
suffix = base64.b64decode(encoded_suffix, validate=True).decode("utf-8")
preserved_old_intent = core + suffix
assert preserved_old_intent == old_intent
assert manifest_fields["format"] == "review-plan-intent-history-v1"
assert manifest_fields["encoding"] == "base64-utf8"
assert int(manifest_fields["old_chars"]) == len(old_intent)
assert int(manifest_fields["core_chars"]) == len(core)
assert manifest_fields["old_sha256"] == hashlib.sha256(
    old_intent.encode("utf-8")
).hexdigest()
assert int(manifest_fields["suffix_bytes"]) == len(suffix.encode("utf-8"))
assert manifest_fields["suffix_sha256"] == hashlib.sha256(
    suffix.encode("utf-8")
).hexdigest()
PY

# Feed the helper's output through the real plan validator. Restrict the client
# order to the implementer's own family so this proves validation reached the
# provider-selection boundary without launching an external reviewer.
printf '%s\n' \
  'diff --git a/skills/code-review/references/staged-review-contract.md b/skills/code-review/references/staged-review-contract.md' \
  '--- a/skills/code-review/references/staged-review-contract.md' \
  '+++ b/skills/code-review/references/staged-review-contract.md' \
  '@@ -1 +1 @@' \
  '-old contract text' \
  '+new contract text' >"$TMP/candidate.diff"
set +e
out="$(CODE_REVIEW_CLIENT_ORDER=codex python3 "$GATE" \
  --mode review \
  --cwd "$ROOT" \
  --diff-file "$TMP/candidate.diff" \
  --implementer-family openai \
  --review-plan-file "$PLAN" \
  --stage build \
  --challenge-budget 0 \
  --timeout 5 \
  --total-timeout 5 2>&1)"
rc=$?
set -e
assert_rc "$rc" 2 "gate-valid plan should reach the no-independent-reviewer boundary"
assert_contains '"reason_code":"no_independent_reviewer_available"' "$out" "real gate accepted the updated plan"

# Compaction is the recovery path when another producer has already written an
# over-limit intent. It must validate the replacement, not reject the old state
# before mode dispatch and force an identity-bypassing hand edit.
python3 - "$PLAN" "$TMP/overlong-plan.json" "$CORE" "$TMP/overlong-latest.txt" <<'PY'
import json
import sys
from pathlib import Path

source, target, core_path, latest_path = map(Path, sys.argv[1:])
plan = json.loads(source.read_text(encoding="utf-8"))
core = core_path.read_text(encoding="utf-8")
plan["intent"] = core + ("x" * (4001 - len(core)))
target.write_text(json.dumps(plan, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
latest_path.write_text("recover the newest over-limit transition", encoding="utf-8")
PY
overlong_before="$(digest "$TMP/overlong-plan.json")"
set +e
out="$(python3 "$UPDATER" --plan "$TMP/overlong-plan.json" --compact-core-intent-file "$CORE" --latest-intent-file "$TMP/overlong-latest.txt" --expected-sha256 "$overlong_before" 2>&1)"
rc=$?
set -e
assert_rc "$rc" 0 "an over-limit existing intent must remain compactable"
assert_contains "review_plan_intent_updated mode=compact" "$out" "over-limit recovery token"
python3 - "$TMP/overlong-plan.json" "$CORE" "$TMP/overlong-latest.txt" <<'PY'
import json
import sys
from pathlib import Path

plan_path, core_path, latest_path = map(Path, sys.argv[1:])
plan = json.loads(plan_path.read_text(encoding="utf-8"))
assert plan["intent"] == f"{core_path.read_text(encoding='utf-8')}\n\n{latest_path.read_text(encoding='utf-8')}"
assert len(plan["intent"]) <= 4000
PY

# Existing plans without a persisted stable-core identity remain appendable,
# but must not compact an arbitrary prefix into a new history boundary.
python3 - "$PLAN" "$TMP/legacy-plan.json" <<'PY'
import json
import sys
from pathlib import Path

source, target = map(Path, sys.argv[1:])
plan = json.loads(source.read_text(encoding="utf-8"))
plan["evidence"] = [
    row
    for row in plan["evidence"]
    if row.get("id") != "review-plan-intent-stable-core-v1"
]
target.write_text(json.dumps(plan, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
PY
printf ' legacy-append' >"$TMP/legacy-append.txt"
legacy_before="$(digest "$TMP/legacy-plan.json")"
set +e
out="$(python3 "$UPDATER" --plan "$TMP/legacy-plan.json" --append-intent-file "$TMP/legacy-append.txt" --expected-sha256 "$legacy_before" 2>&1)"
rc=$?
set -e
assert_rc "$rc" 0 "legacy plan append must remain compatible"
legacy_appended="$(digest "$TMP/legacy-plan.json")"
python3 - "$TMP/legacy-plan.json" "$TMP/legacy-core.txt" "$TMP/legacy-latest.txt" <<'PY'
import json
import sys
from pathlib import Path

plan_path, core_path, latest_path = map(Path, sys.argv[1:])
intent = json.loads(plan_path.read_text(encoding="utf-8"))["intent"]
core_path.write_text(intent[:100], encoding="utf-8")
latest_path.write_text("a genuinely new legacy transition", encoding="utf-8")
PY
set +e
out="$(python3 "$UPDATER" --plan "$TMP/legacy-plan.json" --compact-core-intent-file "$TMP/legacy-core.txt" --latest-intent-file "$TMP/legacy-latest.txt" --expected-sha256 "$legacy_appended" 2>&1)"
rc=$?
set -e
assert_rc "$rc" 2 "legacy plan compaction without identity must fail closed"
assert_contains "intent_core_identity_missing" "$out" "missing stable-core identity reason"
[ "$(digest "$TMP/legacy-plan.json")" = "$legacy_appended" ] || fail "identity-free compaction changed the legacy plan"

# Pin the exact documented character boundary. A 4001-character append must not
# change the last valid 4000-character plan.
python3 - "$APPEND" <<'PY'
import sys
from pathlib import Path

Path(sys.argv[1]).write_text("z" * 108, encoding="utf-8")
PY
expected="$(digest "$PLAN")"
python3 "$UPDATER" --plan "$PLAN" --append-intent-file "$APPEND" --expected-sha256 "$expected" >/dev/null
valid_4000="$(digest "$PLAN")"
printf 'q' >"$APPEND"
set +e
out="$(python3 "$UPDATER" --plan "$PLAN" --append-intent-file "$APPEND" --expected-sha256 "$valid_4000" 2>&1)"
rc=$?
set -e
assert_rc "$rc" 2 "4001-character append must fail closed"
assert_contains "intent_append_overflow" "$out" "append overflow reason"
[ "$(digest "$PLAN")" = "$valid_4000" ] || fail "append overflow changed the plan"

# A prefix is not a stable core merely because it happens to match. The plan's
# persisted identity binds compaction to the exact core chosen before history
# accumulated.
cp "$PLAN" "$TMP/arbitrary-prefix-plan.json"
python3 - "$TMP/arbitrary-prefix-plan.json" "$TMP/arbitrary-prefix-core.txt" "$TMP/arbitrary-prefix-latest.txt" <<'PY'
import json
import sys
from pathlib import Path

plan_path, core_path, latest_path = map(Path, sys.argv[1:])
intent = json.loads(plan_path.read_text(encoding="utf-8"))["intent"]
core_path.write_text(intent[:100], encoding="utf-8")
latest_path.write_text("a novel transition absent from the old intent", encoding="utf-8")
PY
prefix_before="$(digest "$TMP/arbitrary-prefix-plan.json")"
set +e
out="$(python3 "$UPDATER" --plan "$TMP/arbitrary-prefix-plan.json" --compact-core-intent-file "$TMP/arbitrary-prefix-core.txt" --latest-intent-file "$TMP/arbitrary-prefix-latest.txt" --expected-sha256 "$prefix_before" 2>&1)"
rc=$?
set -e
assert_rc "$rc" 2 "an arbitrary matching prefix must not redefine stable core"
assert_contains "intent_core_identity_mismatch" "$out" "stable-core identity mismatch reason"
[ "$(digest "$TMP/arbitrary-prefix-plan.json")" = "$prefix_before" ] || fail "arbitrary-prefix refusal changed the plan"

# A digest that was already stale when opened must fail before replacement.
python3 - "$LATEST" <<'PY'
import sys
from pathlib import Path

Path(sys.argv[1]).write_text("new compact intent", encoding="utf-8")
PY
set +e
out="$(python3 "$UPDATER" --plan "$PLAN" --compact-core-intent-file "$CORE" --latest-intent-file "$LATEST" --expected-sha256 "$(printf '0%.0s' {1..64})" 2>&1)"
rc=$?
set -e
assert_rc "$rc" 2 "stale expected digest must fail closed"
assert_contains "plan_digest_mismatch" "$out" "stale-input mismatch reason"
[ "$(digest "$PLAN")" = "$valid_4000" ] || fail "stale-input mismatch changed the plan"

# An intent hand-rewritten outside the helper still starts with the supplied
# core, but its first core_chars characters no longer hash to the persisted
# identity; compaction must refuse rather than adopt the rewritten boundary.
cp "$PLAN" "$TMP/identity-drift-plan.json"
python3 - "$TMP/identity-drift-plan.json" "$TMP/identity-drift-core.txt" <<'PY'
import json
import re
import sys
from pathlib import Path

plan_path, core_path = map(Path, sys.argv[1:])
plan = json.loads(plan_path.read_text(encoding="utf-8"))
identity = next(
    row["result"]
    for row in plan["evidence"]
    if row.get("id") == "review-plan-intent-stable-core-v1"
)
chars = int(re.search(r"chars=([0-9]+)", identity).group(1))
rewritten = "x" * chars + " freshly rewritten tail"
assert len(rewritten) <= 4000
plan["intent"] = rewritten
core_path.write_text(rewritten[:chars], encoding="utf-8")
plan_path.write_text(
    json.dumps(plan, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
)
PY
printf 'a novel transition for identity drift' >"$TMP/identity-drift-latest.txt"
drift_before="$(digest "$TMP/identity-drift-plan.json")"
set +e
out="$(python3 "$UPDATER" --plan "$TMP/identity-drift-plan.json" --compact-core-intent-file "$TMP/identity-drift-core.txt" --latest-intent-file "$TMP/identity-drift-latest.txt" --expected-sha256 "$drift_before" 2>&1)"
rc=$?
set -e
assert_rc "$rc" 2 "a rewritten intent must not satisfy the persisted identity"
assert_contains "plan_core_identity_mismatch" "$out" "persisted-identity drift reason"
[ "$(digest "$TMP/identity-drift-plan.json")" = "$drift_before" ] || fail "identity drift refusal changed the plan"

# Zero-loss compaction refuses to overflow the evidence-row cap and leaves the
# plan byte-identical.
cp "$PLAN" "$TMP/overflow-rows-plan.json"
python3 - "$TMP/overflow-rows-plan.json" <<'PY'
import json
import sys
from pathlib import Path

plan_path = Path(sys.argv[1])
plan = json.loads(plan_path.read_text(encoding="utf-8"))
rows = plan["evidence"]
index = 0
while len(rows) < 49:
    rows.append(
        {
            "id": f"synthetic-filler-{index:04d}",
            "result": "synthetic filler evidence row exercising the overflow cap",
        }
    )
    index += 1
plan_path.write_text(
    json.dumps(plan, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
)
PY
printf 'a novel transition for row overflow' >"$TMP/overflow-rows-latest.txt"
overflow_rows_before="$(digest "$TMP/overflow-rows-plan.json")"
set +e
out="$(python3 "$UPDATER" --plan "$TMP/overflow-rows-plan.json" --compact-core-intent-file "$CORE" --latest-intent-file "$TMP/overflow-rows-latest.txt" --expected-sha256 "$overflow_rows_before" 2>&1)"
rc=$?
set -e
assert_rc "$rc" 2 "history rows beyond the evidence cap must fail closed"
assert_contains "intent_history_evidence_overflow" "$out" "history-row overflow reason"
[ "$(digest "$TMP/overflow-rows-plan.json")" = "$overflow_rows_before" ] || fail "row overflow refusal changed the plan"

# File transport may contribute one final newline, but arbitrary outer
# whitespace or repeated blank lines must not be silently stripped into shape.
python3 - "$PLAN" "$CORE" <<'PY'
import json
import sys
from pathlib import Path

plan = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
Path(sys.argv[2]).write_text(plan["intent"][:100], encoding="utf-8")
PY
printf ' leading intent\n' >"$LATEST"
set +e
out="$(python3 "$UPDATER" --plan "$PLAN" --compact-core-intent-file "$CORE" --latest-intent-file "$LATEST" --expected-sha256 "$valid_4000" 2>&1)"
rc=$?
set -e
assert_rc "$rc" 2 "outer whitespace must be rejected instead of normalized away"
assert_contains "intent_latest_not_normalized" "$out" "outer-whitespace reason"
[ "$(digest "$PLAN")" = "$valid_4000" ] || fail "outer-whitespace refusal changed the plan"

printf 'replacement intent\n\n' >"$LATEST"
set +e
out="$(python3 "$UPDATER" --plan "$PLAN" --compact-core-intent-file "$CORE" --latest-intent-file "$LATEST" --expected-sha256 "$valid_4000" 2>&1)"
rc=$?
set -e
assert_rc "$rc" 2 "multiple trailing newlines must not be collapsed silently"
assert_contains "intent_latest_not_normalized" "$out" "repeated-newline reason"
[ "$(digest "$PLAN")" = "$valid_4000" ] || fail "repeated-newline refusal changed the plan"

# Structured compaction requires both components, preserves an exact old prefix,
# and refuses an already-present transition.
set +e
out="$(python3 "$UPDATER" --plan "$PLAN" --compact-core-intent-file "$CORE" --expected-sha256 "$valid_4000" 2>&1)"
rc=$?
set -e
assert_rc "$rc" 2 "core-only compaction must fail closed"
assert_contains "intent_update_mode_invalid" "$out" "core-only reason"

set +e
out="$(python3 "$UPDATER" --plan "$PLAN" --latest-intent-file "$LATEST" --expected-sha256 "$valid_4000" 2>&1)"
rc=$?
set -e
assert_rc "$rc" 2 "latest-only compaction must fail closed"
assert_contains "intent_update_mode_invalid" "$out" "latest-only reason"

printf 'unrelated stable core' >"$CORE"
printf 'genuinely new transition' >"$LATEST"
set +e
out="$(python3 "$UPDATER" --plan "$PLAN" --compact-core-intent-file "$CORE" --latest-intent-file "$LATEST" --expected-sha256 "$valid_4000" 2>&1)"
rc=$?
set -e
assert_rc "$rc" 2 "unrelated core must fail closed"
assert_contains "intent_core_not_preserved" "$out" "core-preservation reason"
[ "$(digest "$PLAN")" = "$valid_4000" ] || fail "bad-core refusal changed the plan"

python3 - "$PLAN" "$CORE" "$LATEST" <<'PY'
import json
import sys
from pathlib import Path

plan = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
Path(sys.argv[2]).write_text(plan["intent"][:100], encoding="utf-8")
Path(sys.argv[3]).write_text("latest-round:c28", encoding="utf-8")
PY
set +e
out="$(python3 "$UPDATER" --plan "$PLAN" --compact-core-intent-file "$CORE" --latest-intent-file "$LATEST" --expected-sha256 "$valid_4000" 2>&1)"
rc=$?
set -e
assert_rc "$rc" 2 "an already-present transition must fail closed"
assert_contains "intent_latest_not_new" "$out" "old-transition reason"
[ "$(digest "$PLAN")" = "$valid_4000" ] || fail "old-transition refusal changed the plan"

# Empty transport after removing one file delimiter is not a state transition.
for empty_kind in zero lf crlf; do
  case "$empty_kind" in
    zero) : >"$APPEND" ;;
    lf) printf '\n' >"$APPEND" ;;
    crlf) printf '\r\n' >"$APPEND" ;;
  esac
  set +e
  out="$(python3 "$UPDATER" --plan "$PLAN" --append-intent-file "$APPEND" --expected-sha256 "$valid_4000" 2>&1)"
  rc=$?
  set -e
  assert_rc "$rc" 2 "$empty_kind append must fail closed"
  assert_contains "intent_append_empty" "$out" "$empty_kind empty reason"
  [ "$(digest "$PLAN")" = "$valid_4000" ] || fail "$empty_kind append changed the plan"
done

# The plan itself is opened without following links, and multiply-linked files
# are rejected before any mutation.
ln -s "$PLAN" "$TMP/plan-link.json"
printf 'x' >"$APPEND"
set +e
out="$(python3 "$UPDATER" --plan "$TMP/plan-link.json" --append-intent-file "$APPEND" 2>&1)"
rc=$?
set -e
assert_rc "$rc" 2 "symlink plan must fail closed"
assert_contains "plan_unreadable" "$out" "symlink refusal reason"
[ "$(digest "$PLAN")" = "$valid_4000" ] || fail "symlink refusal changed the target"

cp "$PLAN" "$TMP/hard-plan.json"
ln "$TMP/hard-plan.json" "$TMP/hard-plan-alias.json"
set +e
out="$(python3 "$UPDATER" --plan "$TMP/hard-plan.json" --append-intent-file "$APPEND" 2>&1)"
rc=$?
set -e
assert_rc "$rc" 2 "hardlinked plan must fail closed"
assert_contains "plan_hardlinked" "$out" "hardlink refusal reason"

# Opening a FIFO for reading must not block before the regular-file check.
mkfifo "$TMP/fifo-plan.json"
set +e
out="$(python3 - "$UPDATER" "$TMP/fifo-plan.json" "$APPEND" <<'PY'
import subprocess
import sys

updater, plan, append = sys.argv[1:]
try:
    completed = subprocess.run(
        [sys.executable, updater, "--plan", plan, "--append-intent-file", append],
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        timeout=1,
        check=False,
    )
except subprocess.TimeoutExpired as exc:
    raise AssertionError("FIFO plan open blocked") from exc
assert completed.returncode == 2, completed
assert "plan_not_regular" in completed.stdout, completed.stdout
print(completed.stdout, end="")
PY
)"
rc=$?
set -e
assert_rc "$rc" 0 "FIFO plan must fail quickly"
assert_contains "plan_not_regular" "$out" "FIFO regular-file reason"

# Character limits count Unicode code points, while the whole plan remains
# byte-bounded.
python3 - "$PLAN" "$TMP/unicode-plan.json" <<'PY'
import json
import sys
from pathlib import Path

plan = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
plan["intent"] = "界" * 3999
Path(sys.argv[2]).write_text(
    json.dumps(plan, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
)
PY
printf '新' >"$APPEND"
unicode_before="$(digest "$TMP/unicode-plan.json")"
python3 "$UPDATER" --plan "$TMP/unicode-plan.json" --append-intent-file "$APPEND" --expected-sha256 "$unicode_before" >/dev/null
python3 - "$TMP/unicode-plan.json" <<'PY'
import json
import sys
from pathlib import Path

assert len(json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))["intent"]) == 4000
PY
unicode_4000="$(digest "$TMP/unicode-plan.json")"
set +e
out="$(python3 "$UPDATER" --plan "$TMP/unicode-plan.json" --append-intent-file "$APPEND" --expected-sha256 "$unicode_4000" 2>&1)"
rc=$?
set -e
assert_rc "$rc" 2 "4001 Unicode characters must fail closed"
assert_contains "intent_append_overflow" "$out" "Unicode overflow reason"
[ "$(digest "$TMP/unicode-plan.json")" = "$unicode_4000" ] || fail "Unicode overflow changed the plan"

# A character-valid update that would cross the serialized 32,000-byte plan
# limit is also a no-write failure.
python3 - "$PLAN" "$TMP/byte-plan.json" "$APPEND" <<'PY'
import json
import sys
from pathlib import Path

source, target, append = map(Path, sys.argv[1:])
base = json.loads(source.read_text(encoding="utf-8"))
base["intent"] = "small intent"
append.write_text("a" * 3000, encoding="utf-8")
for count in range(1, 51):
    base["evidence"] = [
        {"id": f"evidence-{index}", "result": "r" * 600}
        for index in range(count)
    ]
    before = (json.dumps(base, ensure_ascii=False, indent=2) + "\n").encode()
    after_plan = dict(base)
    after_plan["intent"] += "a" * 3000
    after = (json.dumps(after_plan, ensure_ascii=False, indent=2) + "\n").encode()
    if len(before) <= 32_000 < len(after):
        target.write_bytes(before)
        break
else:
    raise AssertionError("could not construct the 32,000-byte boundary fixture")
PY
byte_before="$(digest "$TMP/byte-plan.json")"
set +e
out="$(python3 "$UPDATER" --plan "$TMP/byte-plan.json" --append-intent-file "$APPEND" --expected-sha256 "$byte_before" 2>&1)"
rc=$?
set -e
assert_rc "$rc" 2 "serialized plan overflow must fail closed"
assert_contains "updated_plan_too_large" "$out" "serialized byte-limit reason"
[ "$(digest "$TMP/byte-plan.json")" = "$byte_before" ] || fail "serialized overflow changed the plan"

# A JSON escape may decode to a lone surrogate that cannot be emitted as UTF-8.
# That is a stable refusal, not a traceback, and leaves the file unchanged.
python3 - "$PLAN" "$TMP/surrogate-plan.json" <<'PY'
import json
import sys
from pathlib import Path

plan = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
plan["intent"] = "valid intent"
plan["evidence"][0]["result"] = "\ud800"
Path(sys.argv[2]).write_text(json.dumps(plan, ensure_ascii=True, indent=2) + "\n", encoding="utf-8")
PY
printf ' next' >"$APPEND"
surrogate_before="$(digest "$TMP/surrogate-plan.json")"
set +e
out="$(python3 "$UPDATER" --plan "$TMP/surrogate-plan.json" --append-intent-file "$APPEND" --expected-sha256 "$surrogate_before" 2>&1)"
rc=$?
set -e
assert_rc "$rc" 2 "unencodable plan content must fail closed"
assert_contains "updated_plan_invalid_unicode" "$out" "surrogate reason"
[ "$(digest "$TMP/surrogate-plan.json")" = "$surrogate_before" ] || fail "surrogate refusal changed the plan"

# Pre-commit file-sync and replace faults leave the original target intact and
# remove every temporary file; no sensitive plan copy survives the failed call.
python3 - "$UPDATER" "$TMP" <<'PY'
import importlib.util
import json
import os
import stat
import sys
from pathlib import Path

updater_path, root = Path(sys.argv[1]), Path(sys.argv[2])
spec = importlib.util.spec_from_file_location("intent_updater_faults", updater_path)
module = importlib.util.module_from_spec(spec)
assert spec.loader is not None
spec.loader.exec_module(module)


def exercise(kind: str) -> None:
    plan_path = root / f"{kind}-fault-plan.json"
    append_path = root / f"{kind}-fault-append.txt"
    plan = {
        "intent": "initial fault-test intent",
        "acceptance": ["The original target survives a pre-commit fault."],
        "self_review": [],
        "evidence": [{"id": "focused-test", "result": "A detailed pre-commit fault-injection result."}],
    }
    plan_path.write_text(json.dumps(plan, indent=2) + "\n", encoding="utf-8")
    append_path.write_text(" next", encoding="utf-8")
    before = plan_path.read_bytes()
    real_fsync = module.os.fsync
    real_replace = module.os.replace
    if kind == "fsync":
        def fail_regular_sync(fd: int) -> None:
            if stat.S_ISREG(os.fstat(fd).st_mode):
                raise OSError("synthetic file fsync failure")
            real_fsync(fd)

        module.os.fsync = fail_regular_sync
    else:
        def fail_replace(source: object, target: object) -> None:
            raise OSError("synthetic replace failure")

        module.os.replace = fail_replace
    try:
        module.run(["--plan", str(plan_path), "--append-intent-file", str(append_path)])
    except module.UpdateError as exc:
        assert exc.reason == "plan_write_failed", exc.reason
    else:
        raise AssertionError(f"{kind} fault did not fail")
    finally:
        module.os.fsync = real_fsync
        module.os.replace = real_replace
    assert plan_path.read_bytes() == before, f"{kind} fault changed the target"
    assert not list(root.glob(f".{plan_path.name}.*")), f"{kind} fault leaked a temporary plan"


exercise("fsync")
exercise("replace")
PY

# Once rename succeeds, a directory-sync failure is a committed-but-unknown
# durability outcome. It carries the new digest and forbids a blind retry.
python3 - "$UPDATER" "$TMP/durability-plan.json" "$TMP/durability-append.txt" <<'PY'
import importlib.util
import json
import os
import stat
import sys
from pathlib import Path

updater_path, plan_path, append_path = map(Path, sys.argv[1:])
spec = importlib.util.spec_from_file_location("intent_updater_under_test", updater_path)
module = importlib.util.module_from_spec(spec)
assert spec.loader is not None
spec.loader.exec_module(module)
plan = {
    "intent": "initial intent",
    "acceptance": ["The candidate behavior is verified."],
    "self_review": [],
    "evidence": [{"id": "focused-test", "result": "A sufficiently detailed result for this fault injection."}],
}
plan_path.write_text(json.dumps(plan, indent=2) + "\n", encoding="utf-8")
append_path.write_text(" next", encoding="utf-8")
real_fsync = module.os.fsync

def fail_directory_sync(fd):
    if stat.S_ISDIR(os.fstat(fd).st_mode):
        raise OSError("synthetic directory fsync failure")
    return real_fsync(fd)

module.os.fsync = fail_directory_sync
try:
    module.run(["--plan", str(plan_path), "--append-intent-file", str(append_path)])
except module.UpdateError as exc:
    assert exc.reason == "plan_committed_durability_unknown", exc.reason
    assert "sha256=" in exc.detail and "do not retry blindly" in exc.detail
else:
    raise AssertionError("directory fsync fault did not fail")
updated = json.loads(plan_path.read_text(encoding="utf-8"))
assert updated["intent"] == "initial intent next"
PY

# A stdout pipe closed before the flushed success receipt must exit nonzero
# with plan_committed_receipt_lost while the plan file keeps the committed
# update; rc 0 with a lost receipt reads as "no update happened".
python3 - "$UPDATER" "$TMP/closed-pipe-plan.json" "$TMP/closed-pipe-append.txt" <<'PY'
import json
import os
import subprocess
import sys
from pathlib import Path

updater_path, plan_path, append_path = map(Path, sys.argv[1:])
plan = {
    "intent": "initial intent",
    "acceptance": ["The candidate behavior is verified."],
    "self_review": [],
    "evidence": [
        {"id": "focused-test", "result": "A sufficiently detailed result for closed-pipe coverage."}
    ],
}
plan_path.write_text(json.dumps(plan, indent=2) + "\n", encoding="utf-8")
append_path.write_text(" next", encoding="utf-8")
read_fd, write_fd = os.pipe()
os.close(read_fd)
result = subprocess.run(
    [sys.executable, str(updater_path), "--plan", str(plan_path), "--append-intent-file", str(append_path)],
    stdout=write_fd,
    stderr=subprocess.PIPE,
    text=True,
)
os.close(write_fd)
assert result.returncode == 2, result.returncode
assert "plan_committed_receipt_lost" in result.stderr, result.stderr
assert "re-read the plan" in result.stderr, result.stderr
committed = json.loads(plan_path.read_text(encoding="utf-8"))
assert committed["intent"] == "initial intent next", committed["intent"]
PY

echo "test_update_review_plan_intent: ok"
