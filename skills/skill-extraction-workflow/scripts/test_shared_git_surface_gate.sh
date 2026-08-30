#!/usr/bin/env bash
# Behavior regression for the shared Git/PR metadata leakage gate.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd -P)"
GATE="$SCRIPT_DIR/shared_git_surface_gate.py"
[ -f "$GATE" ] || { echo "FAIL: gate not found: $GATE" >&2; exit 1; }

TMP="$(mktemp -d "${TMPDIR:-/tmp}/shared-git-surface.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

fail() { echo "FAIL: $*" >&2; exit 1; }
assert_rc() { [ "$1" = "$2" ] || fail "expected rc=$2 got rc=$1 ($3)"; }
assert_equals() { [ "$1" = "$2" ] || fail "expected '$1' = '$2' ($3)"; }
assert_contains() { case "$2" in *"$1"*) : ;; *) fail "expected '$1' ($3): $2";; esac; }
assert_not_contains() { case "$2" in *"$1"*) fail "unexpected '$1' ($3): $2";; *) : ;; esac; }

REPO="$TMP/repo"
mkdir -p "$REPO"
git init -q -b main "$REPO"
git -C "$REPO" config user.email tester@example.invalid
git -C "$REPO" config user.name "Synthetic Tester"
printf 'baseline\n' >"$REPO/file.txt"
git -C "$REPO" add file.txt

# Construct the provider URL at runtime so the repository test source does not
# itself carry a clickable session URL.
session_url="https://claude"'.'"ai/code/"'synthetic_fixture_123456'
claude_product_url="https://claude"'.'"ai/code"
kimi_url="https://kimi"'.'"com/share/"'synthetic_fixture_abcdef'
gemini_url="https://g"'.'"co/gemini/share/"'synthetic_fixture_ghijkl'
google_product_url="https://g"'.'"co/product/share/"'synthetic_fixture_product'
conversation_uuid='12345678-1234-4abc-8def-123456789abc'
chatgpt_conversation_url="https://chatgpt"'.'"com/c/$conversation_uuid"
claude_chat_url="https://claude"'.'"ai/chat/$conversation_uuid"
chatgpt_https_default_port_url="https://chatgpt"'.'"com:443/share/$conversation_uuid"
chatgpt_http_default_port_url="http://chatgpt"'.'"com:80/share/$conversation_uuid"
chatgpt_wrong_port_url="https://chatgpt"'.'"com:80/share/$conversation_uuid"
chatgpt_nested_help_url="https://chatgpt"'.'"com/help/chat/$conversation_uuid"
claude_nonconversation_url="https://claude"'.'"ai/chat/product-guide"
printf 'baseline debt\n\nClaude-Session: %s\n' "$session_url" >"$TMP/message.txt"
git -C "$REPO" commit -q -F "$TMP/message.txt"
BASE="$(git -C "$REPO" rev-parse HEAD)"
git -C "$REPO" switch -q -c feature/sanitized-capability

run_gate() {
  set +e
  out="$(env -u GITHUB_EVENT_PATH -u GITHUB_HEAD_REF -u GITHUB_REF_NAME \
    python3 "$GATE" --repo "$REPO" --base-ref "$BASE" "$@" 2>&1)"
  rc=$?
  set -e
}

run_gate_without_base() {
  set +e
  out="$(env -u GITHUB_EVENT_PATH -u GITHUB_HEAD_REF -u GITHUB_REF_NAME -u CCL_SKILL_BASE_REF \
    python3 "$GATE" --repo "$REPO" "$@" 2>&1)"
  rc=$?
  set -e
}

run_gate_without_base
assert_rc "$rc" 2 "an unbound candidate base must fail closed"
assert_contains "candidate base is unresolved" "$out" "unresolved-base reason"

set +e
out="$(env -u GITHUB_EVENT_PATH -u GITHUB_HEAD_REF -u GITHUB_REF_NAME -u CCL_SKILL_BASE_REF \
  python3 "$GATE" --repo "$REPO" --base-ref refs/heads/missing-candidate-base \
  --default-base-ref "$BASE" 2>&1)"
rc=$?
set -e
assert_rc "$rc" 2 "an invalid explicit base must not fall through to a lower-priority default"
assert_contains "explicit candidate base does not resolve" "$out" "invalid explicit-base reason"

# A branch-creation push has an all-zero `before` SHA. The repository-owned
# fallback can then point at the just-pushed HEAD and silently produce an empty
# range, skipping the commit message that crossed the merge boundary.
git -C "$REPO" update-ref refs/remotes/origin/dev "$BASE"
python3 - "$TMP/zero-before-push.json" <<'PY'
import json
import sys
from pathlib import Path

Path(sys.argv[1]).write_text(json.dumps({
    "ref": "refs/heads/dev",
    "before": "0" * 40,
}), encoding="utf-8")
PY
run_gate_without_base \
  --event-json "$TMP/zero-before-push.json" \
  --default-base-ref refs/remotes/origin/dev
assert_rc "$rc" 2 "a zero-before direct push with an empty candidate range must fail closed"
assert_contains "direct-push candidate commit range is empty" "$out" "zero-before push reason"

# PR text cannot substitute for the unscanned commit surface on a direct push.
printf 'Neutral proposed PR summary.\n' >"$TMP/zero-before-proposed-pr.txt"
run_gate_without_base \
  --event-json "$TMP/zero-before-push.json" \
  --default-base-ref refs/remotes/origin/dev \
  --pr-text-file "$TMP/zero-before-proposed-pr.txt"
assert_rc "$rc" 2 "proposed PR text must not excuse an empty direct-push range"
assert_contains "direct-push candidate commit range is empty" "$out" "PR text cannot mask the push"

# A non-zero but unreachable `before` SHA is already a hard error and must not
# fall through to the repository-owned fallback.
python3 - "$TMP/unreachable-before-push.json" <<'PY'
import json
import sys
from pathlib import Path

Path(sys.argv[1]).write_text(json.dumps({
    "ref": "refs/heads/dev",
    "before": "f" * 40,
}), encoding="utf-8")
PY
run_gate_without_base \
  --event-json "$TMP/unreachable-before-push.json" \
  --default-base-ref refs/remotes/origin/dev
assert_rc "$rc" 2 "an unreachable non-zero push base must fail closed"
assert_contains "trusted event candidate base does not resolve" "$out" "unreachable push-base reason"

# Outside a direct-push event, an explicit empty range is valid for local
# pre-commit validation; historical debt at/before the base stays excluded.
run_gate
assert_rc "$rc" 0 "a local explicit empty range must remain valid"
assert_contains "commits=0" "$out" "local empty range remains explicit"

printf 'clean candidate\n' >>"$REPO/file.txt"
git -C "$REPO" commit -qam "describe bounded capability"
clean_head="$(git -C "$REPO" rev-parse HEAD)"
run_gate
assert_rc "$rc" 0 "sanitized candidate commit should pass while historical debt stays excluded"

# A pre-publication PR text check remains useful even when no candidate commit
# exists yet. The supplied non-empty file is itself an explicit scanned surface.
printf 'Neutral proposed PR summary.\n' >"$TMP/empty-range-proposed-pr.txt"
set +e
out="$(env -u GITHUB_EVENT_PATH -u GITHUB_HEAD_REF -u GITHUB_REF_NAME -u CCL_SKILL_BASE_REF \
  python3 "$GATE" --repo "$REPO" --base-ref "$clean_head" \
  --branch-name feature/sanitized-capability \
  --pr-text-file "$TMP/empty-range-proposed-pr.txt" 2>&1)"
rc=$?
set -e
assert_rc "$rc" 0 "a non-empty proposed PR surface may be checked with no candidate commits"
assert_contains "commits=0" "$out" "the allowed empty range remains explicit"

for empty_pr_case in zero-byte whitespace-only; do
  case "$empty_pr_case" in
    zero-byte) : >"$TMP/empty-range-proposed-pr.txt" ;;
    whitespace-only) printf ' \t\r\n' >"$TMP/empty-range-proposed-pr.txt" ;;
  esac
  set +e
  out="$(env -u GITHUB_EVENT_PATH -u GITHUB_HEAD_REF -u GITHUB_REF_NAME -u CCL_SKILL_BASE_REF \
    python3 "$GATE" --repo "$REPO" --base-ref "$clean_head" \
    --branch-name feature/sanitized-capability \
    --pr-text-file "$TMP/empty-range-proposed-pr.txt" 2>&1)"
  rc=$?
  set -e
  assert_rc "$rc" 2 "$empty_pr_case proposed PR text must fail closed"
  assert_contains \
    "proposed PR text must contain non-whitespace content" "$out" \
    "$empty_pr_case proposed PR diagnostic"
done

printf 'Private session: %s\n' "$session_url" >"$TMP/empty-range-proposed-pr.txt"
set +e
out="$(env -u GITHUB_EVENT_PATH -u GITHUB_HEAD_REF -u GITHUB_REF_NAME -u CCL_SKILL_BASE_REF \
  python3 "$GATE" --repo "$REPO" --base-ref "$clean_head" \
  --branch-name feature/sanitized-capability \
  --pr-text-file "$TMP/empty-range-proposed-pr.txt" 2>&1)"
rc=$?
set -e
assert_rc "$rc" 1 "a prohibited proposed PR surface must still block with no candidate commits"
assert_contains "category=ai_session_url" "$out" "empty-range proposed PR category"
assert_not_contains "synthetic_fixture_123456" "$out" "empty-range diagnostic stays redacted"

python3 - "$TMP/empty-range-pr-event.json" "$clean_head" <<'PY'
import json
import sys
from pathlib import Path

Path(sys.argv[1]).write_text(json.dumps({
    "pull_request": {
        "title": "Bound a shared capability",
        "body": "Neutral behavior and verification summary.",
        "head": {"ref": "feature/sanitized-capability"},
        "base": {"sha": sys.argv[2]},
    }
}), encoding="utf-8")
PY
run_gate_without_base --event-json "$TMP/empty-range-pr-event.json"
assert_rc "$rc" 0 "trusted non-empty PR text may be checked with no candidate commits"
assert_contains "commits=0" "$out" "the trusted PR exception remains explicit"

python3 - "$TMP/empty-range-pr-event.json" "$clean_head" "$session_url" <<'PY'
import json
import sys
from pathlib import Path

Path(sys.argv[1]).write_text(json.dumps({
    "pull_request": {
        "title": "Bound a shared capability",
        "body": "Private session: " + sys.argv[3],
        "head": {"ref": "feature/sanitized-capability"},
        "base": {"sha": sys.argv[2]},
    }
}), encoding="utf-8")
PY
run_gate_without_base --event-json "$TMP/empty-range-pr-event.json"
assert_rc "$rc" 1 "prohibited trusted PR text must block with no candidate commits"
assert_contains "surface=pull_request_body" "$out" "empty-range trusted PR locator"
assert_not_contains "synthetic_fixture_123456" "$out" "empty-range trusted PR stays redacted"

candidate_case() {
  local branch="$1" message_file="$2"
  git -C "$REPO" switch -q -C "$branch" "$clean_head"
  printf '%s\n' "$branch" >>"$REPO/file.txt"
  git -C "$REPO" add file.txt
  git -C "$REPO" commit -q -F "$message_file"
}

candidate_identity_case() {
  local branch="$1" author_name="$2" author_email="$3"
  local committer_name="$4" committer_email="$5"
  git -C "$REPO" switch -q -C "$branch" "$clean_head"
  printf '%s\n' "$branch" >>"$REPO/file.txt"
  git -C "$REPO" add file.txt
  GIT_AUTHOR_NAME="$author_name" GIT_AUTHOR_EMAIL="$author_email" \
    GIT_COMMITTER_NAME="$committer_name" GIT_COMMITTER_EMAIL="$committer_email" \
    git -C "$REPO" commit -q -m "describe bounded capability"
}

printf 'change summary\n\nClaude-Session: %s\n' "$session_url" >"$TMP/session-message.txt"
candidate_case case/session-trailer "$TMP/session-message.txt"
session_commit="$(git -C "$REPO" rev-parse --short=12 HEAD)"
run_gate
assert_rc "$rc" 1 "new session trailer must block"
assert_contains "category=ai_session_url" "$out" "URL category"
assert_contains "category=ai_session_trailer" "$out" "trailer category"
assert_not_contains "synthetic_fixture_123456" "$out" "diagnostic must redact the session id"
run_gate --event-json "$TMP/zero-before-push.json"
assert_rc "$rc" 1 "an explicit ancestor must recover scanning for a zero-before push"
assert_contains "category=ai_session_trailer" "$out" "explicit push base scans the candidate commit"

# A clean HEAD must not hide a prohibited message in an earlier candidate
# commit. This kills a tempting `git log -1`/last-record-only regression.
printf 'clean follow-up\n' >>"$REPO/file.txt"
git -C "$REPO" commit -qam "follow up with neutral wording"
run_gate
assert_rc "$rc" 1 "an earlier candidate violation must remain blocking"
assert_contains "locator=$session_commit" "$out" "the earlier candidate commit was scanned"

# `--repo` is the single repository identity. Ambient Git routing variables
# must not redirect every subprocess to a clean decoy and certify the wrong
# object graph. Exercise both the shortest bypass and the full same-shape set.
DECOY_REPO="$TMP/git-env-decoy"
git clone -q "$REPO" "$DECOY_REPO"
git -C "$DECOY_REPO" reset -q --hard "$clean_head"
git -C "$DECOY_REPO" config user.email tester@example.invalid
git -C "$DECOY_REPO" config user.name "Synthetic Tester"
git -C "$DECOY_REPO" commit -q --allow-empty -m "neutral decoy head"
: >"$TMP/empty-grafts"

set +e
out="$(env -u GITHUB_EVENT_PATH -u GITHUB_HEAD_REF -u GITHUB_REF_NAME \
  GIT_DIR="$DECOY_REPO/.git" \
  python3 "$GATE" --repo "$REPO" --base-ref "$BASE" \
  --branch-name feature/sanitized-capability 2>&1)"
rc=$?
set -e
assert_rc "$rc" 1 "ambient GIT_DIR must not redirect the candidate scan"
assert_contains "locator=$session_commit" "$out" "GIT_DIR isolation keeps the real candidate"

set +e
out="$(env -u GITHUB_EVENT_PATH -u GITHUB_HEAD_REF -u GITHUB_REF_NAME \
  GIT_DIR="$DECOY_REPO/.git" \
  GIT_WORK_TREE="$DECOY_REPO" \
  GIT_INDEX_FILE="$DECOY_REPO/.git/index" \
  GIT_COMMON_DIR="$DECOY_REPO/.git" \
  GIT_NAMESPACE=synthetic-clean \
  GIT_OBJECT_DIRECTORY="$DECOY_REPO/.git/objects" \
  GIT_ALTERNATE_OBJECT_DIRECTORIES="$DECOY_REPO/.git/objects" \
  GIT_CEILING_DIRECTORIES="$DECOY_REPO" \
  GIT_GRAFT_FILE="$TMP/empty-grafts" \
  python3 "$GATE" --repo "$REPO" --base-ref "$BASE" \
  --branch-name feature/sanitized-capability 2>&1)"
rc=$?
set -e
assert_rc "$rc" 1 "ambient Git repository-routing matrix must be ignored"
assert_contains "locator=$session_commit" "$out" "routing-matrix isolation keeps the real candidate"
assert_not_contains "$DECOY_REPO" "$out" "routing diagnostics do not echo decoy paths"

# Git's runtime config channels are repository-routing channels too. An
# injected include can supply core.worktree and executable options even though
# every command also uses `-C <repo>`. Keep the end-to-end range assertion and
# probe the shared subprocess helper so sanitization cannot regress one key at
# a time.
python3 - "$GATE" "$REPO" "$DECOY_REPO" "$TMP" "$BASE" "$session_commit" <<'PY'
import importlib.util
import os
import shlex
import subprocess
import sys
from pathlib import Path

gate_path = Path(sys.argv[1])
repo_path = Path(sys.argv[2])
decoy_path = Path(sys.argv[3])
fixture_root = Path(sys.argv[4])
base = sys.argv[5]
candidate_locator = sys.argv[6]
config_path = fixture_root / "ambient-git-config.cfg"
fsmonitor_path = fixture_root / "ambient-fsmonitor.sh"
fsmonitor_marker = fixture_root / "ambient-fsmonitor-ran"

fsmonitor_path.write_text(
    "#!/bin/sh\n: >" + shlex.quote(str(fsmonitor_marker)) + "\nexit 0\n",
    encoding="utf-8",
)
fsmonitor_path.chmod(0o700)

clean_setup_env = os.environ.copy()
for key in tuple(clean_setup_env):
    if key in {
        "GIT_CONFIG",
        "GIT_CONFIG_COUNT",
        "GIT_CONFIG_GLOBAL",
        "GIT_CONFIG_SYSTEM",
        "GIT_CONFIG_NOSYSTEM",
        "GIT_CONFIG_PARAMETERS",
    } or key.startswith(("GIT_CONFIG_KEY_", "GIT_CONFIG_VALUE_")):
        clean_setup_env.pop(key, None)
subprocess.run(
    ["git", "config", "--file", str(config_path), "core.worktree", str(decoy_path)],
    check=True,
    env=clean_setup_env,
)
subprocess.run(
    ["git", "config", "--file", str(config_path), "core.fsmonitor", str(fsmonitor_path)],
    check=True,
    env=clean_setup_env,
)

counted_config = {
    "GIT_CONFIG_COUNT": "1",
    "GIT_CONFIG_KEY_0": "include.path",
    "GIT_CONFIG_VALUE_0": str(config_path),
}
ambient_env = clean_setup_env | counted_config
candidate = subprocess.run(
    [
        sys.executable,
        str(gate_path),
        "--repo",
        str(repo_path),
        "--base-ref",
        base,
        "--branch-name",
        "feature/sanitized-capability",
    ],
    stdout=subprocess.PIPE,
    stderr=subprocess.PIPE,
    check=False,
    env=ambient_env,
    text=True,
)
assert candidate.returncode == 1, candidate.stderr
assert f"locator={candidate_locator}" in candidate.stderr
assert str(decoy_path) not in candidate.stderr
assert not fsmonitor_marker.exists()

spec = importlib.util.spec_from_file_location(
    "shared_git_surface_gate_config_probe", gate_path
)
module = importlib.util.module_from_spec(spec)
sys.modules[spec.name] = module
spec.loader.exec_module(module)

original_environment = os.environ.copy()
try:
    os.environ.clear()
    os.environ.update(ambient_env)
    try:
        configured_worktree = module.git(
            decoy_path,
            "config",
            "--get",
            "core.worktree",
            operation="ambient core.worktree probe",
        ).decode("utf-8").strip()
    except module.GateError as exc:
        assert str(exc) == "ambient core.worktree probe failed"
        configured_worktree = None
    module.git(
        decoy_path,
        "status",
        "--porcelain=v1",
        operation="ambient fsmonitor probe",
    )
finally:
    os.environ.clear()
    os.environ.update(original_environment)

absorbed = []
if configured_worktree is not None:
    absorbed.append("include.path/core.worktree")
if fsmonitor_marker.exists():
    absorbed.append("core.fsmonitor command")
assert not absorbed, "ambient config reached Git subprocess: " + ", ".join(absorbed)

blocked_config_keys = {
    "GIT_CONFIG",
    "GIT_CONFIG_COUNT",
    "GIT_CONFIG_GLOBAL",
    "GIT_CONFIG_SYSTEM",
    "GIT_CONFIG_NOSYSTEM",
    "GIT_CONFIG_PARAMETERS",
}
blocked_config_prefixes = ("GIT_CONFIG_KEY_", "GIT_CONFIG_VALUE_")
synthetic_environment = {
    key: f"synthetic-{index}"
    for index, key in enumerate(module.GIT_REPOSITORY_ROUTING_ENV)
}
synthetic_environment.update(
    {
        key: str(config_path)
        for key in blocked_config_keys
    }
)
synthetic_environment.update(
    {
        "GIT_CONFIG_KEY_0": "include.path",
        "GIT_CONFIG_VALUE_0": str(config_path),
        "GIT_CONFIG_KEY_91": "core.worktree",
        "GIT_CONFIG_VALUE_91": str(decoy_path),
        "GIT_TERMINAL_PROMPT": "0",
        "CCL_SKILL_BASE_REF": base,
        "SYNTH_GIT_ENV_CONTROL": "preserved",
    }
)
try:
    os.environ.update(synthetic_environment)
    sanitized = module.git_environment()
finally:
    os.environ.clear()
    os.environ.update(original_environment)

for key in module.GIT_REPOSITORY_ROUTING_ENV:
    assert key not in sanitized, key
for key in blocked_config_keys:
    assert key not in sanitized, key
assert not any(key.startswith(blocked_config_prefixes) for key in sanitized)
for key in (
    "GIT_TERMINAL_PROMPT",
    "CCL_SKILL_BASE_REF",
    "SYNTH_GIT_ENV_CONTROL",
):
    assert sanitized[key] == synthetic_environment[key], key
PY

printf '%s\n' 'change summary' 'Codex'"-Session-ID: synthetic_fixture_654321" >"$TMP/session-id-message.txt"
candidate_case case/session-id "$TMP/session-id-message.txt"
run_gate
assert_rc "$rc" 1 "new session identifier must block"
assert_contains "category=ai_session_id" "$out" "session-id category"
assert_not_contains "synthetic_fixture_654321" "$out" "session-id diagnostic must redact the identifier"

printf '%s\n' 'change summary' 'Kimi-Session-ID: synthetic_fixture_777777' >"$TMP/kimi-session-id-message.txt"
candidate_case case/kimi-session-id "$TMP/kimi-session-id-message.txt"
run_gate
assert_rc "$rc" 1 "Kimi session identifier must block"
assert_contains "category=ai_session_id" "$out" "expanded session-id provider category"

printf 'change summary\n\nPrivate review: %s\n' "$kimi_url" >"$TMP/kimi-url-message.txt"
candidate_case case/kimi-url "$TMP/kimi-url-message.txt"
run_gate
assert_rc "$rc" 1 "Kimi session URL must block"
assert_contains "category=ai_session_url" "$out" "expanded session URL provider category"
assert_not_contains "synthetic_fixture_abcdef" "$out" "expanded-provider URL must be redacted"

printf 'change summary\n\nCo-Authored-By: Claude <noreply@example.invalid>\n' >"$TMP/coauthor-message.txt"
candidate_case case/coauthor "$TMP/coauthor-message.txt"
run_gate
assert_rc "$rc" 1 "AI co-author trailer must block"
assert_contains "category=ai_coauthor_trailer" "$out" "co-author category"

printf 'change summary\n\nCo-Authored-By: Human Reviewer <reviewer@example.invalid>\n' >"$TMP/human-coauthor-message.txt"
candidate_case case/human-coauthor "$TMP/human-coauthor-message.txt"
run_gate
assert_rc "$rc" 0 "a human co-author trailer must remain valid"

printf 'change summary\n\nCo-Authored-By: Ai Weiwei <reviewer@example.invalid>\n' >"$TMP/ai-human-coauthor-message.txt"
candidate_case case/ai-human-coauthor "$TMP/ai-human-coauthor-message.txt"
run_gate
assert_rc "$rc" 0 "a human whose name starts with Ai must not be treated as an AI provider"

printf 'change summary\n\nCo-Authored-By: Kimi <k@example.invalid>\n' >"$TMP/provider-name-human-message.txt"
candidate_case case/provider-name-human "$TMP/provider-name-human-message.txt"
run_gate
assert_rc "$rc" 0 "a human whose exact name is also a provider alias must remain valid"

printf 'change summary\n\nCo-Authored-By: Qwen Li <qwen.li@example.invalid>\n' >"$TMP/provider-prefix-human-message.txt"
candidate_case case/provider-prefix-human "$TMP/provider-prefix-human-message.txt"
run_gate
assert_rc "$rc" 0 "a human surname after a provider-shaped given name must remain valid"

printf 'change summary\n\nCo-Authored-By: Gemini Proctor <gemini.proctor@example.invalid>\n' >"$TMP/ambiguous-provider-human-message.txt"
candidate_case case/ambiguous-provider-human "$TMP/ambiguous-provider-human-message.txt"
run_gate
assert_rc "$rc" 0 "an ambiguous provider prefix in a human name must remain valid"

printf 'change summary\n\nCo-Authored-By: Claude Code <helper@example.invalid>\n' >"$TMP/unambiguous-provider-coauthor-message.txt"
candidate_case case/unambiguous-provider-coauthor "$TMP/unambiguous-provider-coauthor-message.txt"
run_gate
assert_rc "$rc" 1 "an unambiguous AI display name must block with an ordinary email"
assert_contains "category=ai_coauthor_trailer" "$out" "unambiguous AI display-name co-author category"

for qualified_identity in \
  "Claude Sonnet" "Claude 3.5 Sonnet" "Claude v3.5 Sonnet" \
  "OpenAI Codex" "ChatGPT-5" "Qwen2.5-Coder" "Gemini 2.5 Pro"; do
  printf 'change summary\n\nCo-Authored-By: %s <helper@example.invalid>\n' \
    "$qualified_identity" >"$TMP/model-qualified-coauthor-message.txt"
  candidate_case "case/model-qualified-coauthor-${qualified_identity//[^A-Za-z0-9]/-}" \
    "$TMP/model-qualified-coauthor-message.txt"
  run_gate
  assert_rc "$rc" 1 "model-qualified AI co-author $qualified_identity must block"
  assert_contains "category=ai_coauthor_trailer" "$out" \
    "model-qualified AI co-author category"
done

printf 'change summary\n\nCo-Authored-By: Claude\tCode <helper@example.invalid>\n' >"$TMP/tab-qualified-coauthor-message.txt"
candidate_case case/tab-qualified-coauthor "$TMP/tab-qualified-coauthor-message.txt"
run_gate
assert_rc "$rc" 1 "a tab-qualified AI co-author identity must block"
assert_contains "category=ai_coauthor_trailer" "$out" \
  "tab-qualified AI co-author category"

printf 'change summary\n\nCo-Authored-By: Codex <helper@example.invalid>\n' >"$TMP/codex-ordinary-email-message.txt"
candidate_case case/codex-ordinary-email "$TMP/codex-ordinary-email-message.txt"
run_gate
assert_rc "$rc" 1 "a non-human provider name must block with an ordinary email"
assert_contains "category=ai_coauthor_trailer" "$out" "ordinary-email provider co-author category"

printf 'change summary\n\nCo-Authored-By: ChatGPT <noreply@example.invalid>\n' >"$TMP/chatgpt-coauthor-message.txt"
candidate_case case/chatgpt-coauthor "$TMP/chatgpt-coauthor-message.txt"
run_gate
assert_rc "$rc" 1 "another AI-family co-author trailer must block"
assert_contains "category=ai_coauthor_trailer" "$out" "AI-family co-author category"

printf 'change summary\n\nCo-Authored-By: OpenCode <noreply@example.invalid>\n' >"$TMP/opencode-coauthor-message.txt"
candidate_case case/opencode-coauthor "$TMP/opencode-coauthor-message.txt"
run_gate
assert_rc "$rc" 1 "OpenCode co-author trailer must block"
assert_contains "category=ai_coauthor_trailer" "$out" "expanded co-author provider category"

printf 'change summary\n\nCo-Authored-By: claude[bot] <123+claude[bot]@users.noreply.github.com>\n' >"$TMP/bracketed-bot-coauthor-message.txt"
candidate_case case/bracketed-bot-coauthor "$TMP/bracketed-bot-coauthor-message.txt"
run_gate
assert_rc "$rc" 1 "a bracketed GitHub App co-author identity must block"
assert_contains "category=ai_coauthor_trailer" "$out" "bracketed bot co-author category"

printf 'change summary\n\nCo-Authored-By: claude-code[bot] <123+claude-code[bot]@users.noreply.github.com>\n' >"$TMP/hyphenated-bot-coauthor-message.txt"
candidate_case case/hyphenated-bot-coauthor "$TMP/hyphenated-bot-coauthor-message.txt"
run_gate
assert_rc "$rc" 1 "a hyphenated provider GitHub App co-author identity must block"
assert_contains "category=ai_coauthor_trailer" "$out" "hyphenated bot co-author category"

candidate_identity_case case/ai-author "Claude Code" helper@example.invalid \
  "Synthetic Tester" tester@example.invalid
run_gate
assert_rc "$rc" 1 "an unambiguous AI author identity must block"
assert_contains "surface=commit_author" "$out" "AI author surface"
assert_contains "category=ai_commit_identity" "$out" "AI author category"

candidate_identity_case case/ai-committer "Synthetic Tester" tester@example.invalid \
  Codex helper@example.invalid
run_gate
assert_rc "$rc" 1 "an unambiguous AI committer identity must block"
assert_contains "surface=commit_committer" "$out" "AI committer surface"
assert_contains "category=ai_commit_identity" "$out" "AI committer category"

candidate_identity_case case/model-qualified-ai-author "OpenAI Codex" \
  helper@example.invalid "Synthetic Tester" tester@example.invalid
run_gate
assert_rc "$rc" 1 "a model-qualified AI author identity must block"
assert_contains "surface=commit_author" "$out" "model-qualified AI author surface"
assert_contains "category=ai_commit_identity" "$out" "model-qualified AI author category"

candidate_identity_case case/model-qualified-ai-committer "Synthetic Tester" \
  tester@example.invalid "Claude Sonnet" helper@example.invalid
run_gate
assert_rc "$rc" 1 "a model-qualified AI committer identity must block"
assert_contains "surface=commit_committer" "$out" "model-qualified AI committer surface"
assert_contains "category=ai_commit_identity" "$out" "model-qualified AI committer category"

candidate_identity_case case/version-infix-ai-author "Claude 3.5 Sonnet" \
  helper@example.invalid "Synthetic Tester" tester@example.invalid
run_gate
assert_rc "$rc" 1 "a version-infix AI author identity must block"
assert_contains "surface=commit_author" "$out" "version-infix AI author surface"
assert_contains "category=ai_commit_identity" "$out" "version-infix AI author category"

candidate_identity_case case/version-infix-human-control "Claude 3.5 Monet" \
  painter@example.invalid "Synthetic Tester" tester@example.invalid
run_gate
assert_rc "$rc" 0 "a version-infix human name must remain valid"

candidate_identity_case case/non-claude-human-controls "Codex Ramirez" \
  codex.ramirez@example.invalid "OpenAI Smith" openai.smith@example.invalid
run_gate
assert_rc "$rc" 0 "non-Claude provider-shaped human names must remain valid"

candidate_identity_case case/versioned-provider-human-controls "Qwen Li" \
  qwen.li@example.invalid "Gemini Proctor" gemini.proctor@example.invalid
run_gate
assert_rc "$rc" 0 "versioned-provider grammar must preserve nearby human names"

for qualified_identity in "Qwen2.5-Coder" "Gemini 2.5 Pro"; do
  identity_slug="${qualified_identity//[^A-Za-z0-9]/-}"
  candidate_identity_case "case/model-qualified-author-$identity_slug" \
    "$qualified_identity" helper@example.invalid \
    "Synthetic Tester" tester@example.invalid
  run_gate
  assert_rc "$rc" 1 "model-qualified AI author $qualified_identity must block"
  assert_contains "surface=commit_author" "$out" \
    "model-qualified AI author $qualified_identity surface"

  candidate_identity_case "case/model-qualified-committer-$identity_slug" \
    "Synthetic Tester" tester@example.invalid \
    "$qualified_identity" helper@example.invalid
  run_gate
  assert_rc "$rc" 1 "model-qualified AI committer $qualified_identity must block"
  assert_contains "surface=commit_committer" "$out" \
    "model-qualified AI committer $qualified_identity surface"
done

candidate_identity_case case/tab-qualified-ai-author $'Claude\tCode' \
  helper@example.invalid "Synthetic Tester" tester@example.invalid
run_gate
assert_rc "$rc" 1 "a tab-qualified AI author identity must block"
assert_contains "surface=commit_author" "$out" "tab-qualified AI author surface"
assert_contains "category=ai_commit_identity" "$out" "tab-qualified AI author category"

candidate_identity_case case/bracketed-bot-author 'claude[bot]' \
  '123+claude[bot]@users.noreply.github.com' "Synthetic Tester" tester@example.invalid
run_gate
assert_rc "$rc" 1 "a bracketed GitHub App author identity must block"
assert_contains "surface=commit_author" "$out" "bracketed bot author surface"
assert_contains "category=ai_commit_identity" "$out" "bracketed bot author category"

candidate_identity_case case/bracketed-bot-committer "Synthetic Tester" tester@example.invalid \
  'copilot[bot]' '123+copilot[bot]@users.noreply.github.com'
run_gate
assert_rc "$rc" 1 "a bracketed GitHub App committer identity must block"
assert_contains "surface=commit_committer" "$out" "bracketed bot committer surface"
assert_contains "category=ai_commit_identity" "$out" "bracketed bot committer category"

candidate_identity_case case/hyphenated-bot-author 'github-copilot[bot]' \
  '123+github-copilot[bot]@users.noreply.github.com' \
  "Synthetic Tester" tester@example.invalid
run_gate
assert_rc "$rc" 1 "a separator-normalized provider GitHub App author must block"
assert_contains "surface=commit_author" "$out" "hyphenated bot author surface"
assert_contains "category=ai_commit_identity" "$out" "hyphenated bot author category"

candidate_identity_case case/provider-bot-email "Synthetic App" \
  '123+copilot-swe-agent[bot]@users.noreply.github.com' \
  "Synthetic Tester" tester@example.invalid
run_gate
assert_rc "$rc" 1 "a known provider GitHub App email must block with a neutral display name"
assert_contains "surface=commit_author" "$out" "provider bot email author surface"
assert_contains "category=ai_commit_identity" "$out" "provider bot email author category"

candidate_identity_case case/unrelated-bot-email "Synthetic App" \
  '123+release-helper[bot]@users.noreply.github.com' \
  "Synthetic Tester" tester@example.invalid
run_gate
assert_rc "$rc" 0 "an unrelated automation bot identity must remain outside the AI gate"

for bot_near_miss in release-codex not-claude human-copilot pre-openai; do
  candidate_identity_case "case/bot-near-miss-$bot_near_miss" "Synthetic App" \
    "123+$bot_near_miss[bot]@users.noreply.github.com" \
    "Synthetic Tester" tester@example.invalid
  run_gate
  assert_rc "$rc" 0 "a provider-token suffix inside another bot account must remain allowed"
done

candidate_identity_case case/provider-name-human Kimi k@example.invalid \
  "Synthetic Tester" tester@example.invalid
run_gate
assert_rc "$rc" 0 "a human author whose name is also a provider alias must remain valid"

for human_case in claude:Claude kimi:Kimi poe:Poe; do
  human_slug="${human_case%%:*}"
  human_name="${human_case#*:}"
  candidate_identity_case "case/noreply-human-$human_slug" "$human_name" \
    "12345+human.noreply@example.invalid" "Synthetic Tester" tester@example.invalid
  run_gate
  assert_rc "$rc" 0 "a human $human_name author using a privacy-style address must remain valid"
done

printf 'change summary\n\n🤖 Claude Code\n' >"$TMP/footer-message.txt"
candidate_case case/generated-footer "$TMP/footer-message.txt"
run_gate
assert_rc "$rc" 1 "a bot footer must block without depending on its prose"
assert_contains "category=generated_by_footer" "$out" "footer category"

printf 'change summary\n\nGenerated with Gemini\n' >"$TMP/plain-footer-message.txt"
candidate_case case/plain-generated-footer "$TMP/plain-footer-message.txt"
run_gate
assert_rc "$rc" 1 "a generated footer without an emoji must block"
assert_contains "category=generated_by_footer" "$out" "plain footer category"

printf 'change summary\n\n🤖 Generated with [Claude Code](%s)\n' "$claude_product_url" >"$TMP/markdown-footer-message.txt"
candidate_case case/markdown-generated-footer "$TMP/markdown-footer-message.txt"
run_gate
assert_rc "$rc" 1 "a markdown-linked host footer must block"
assert_contains "category=generated_by_footer" "$out" "markdown-linked footer category"

printf '%s\n' 'change summary' '会话'"过程：synthetic internal narration" >"$TMP/process-message.txt"
candidate_case case/conversation-process "$TMP/process-message.txt"
run_gate
assert_rc "$rc" 1 "conversation-process narration must block"
assert_contains "category=conversation_process" "$out" "conversation-process category"

# A repository may request a legacy log output encoding even when each commit
# correctly declares its own message encoding. The gate must override that
# ambient presentation choice so CJK-only rules cannot disappear during decode.
python3 - "$TMP/gb18030-process-message.txt" <<'PY'
import sys
from pathlib import Path

Path(sys.argv[1]).write_bytes(
    "change summary\n\n会话过程：synthetic legacy narration\n".encode("gb18030")
)
PY
git -C "$REPO" switch -q -C case/gb18030-conversation-process "$clean_head"
printf '%s\n' 'case/gb18030-conversation-process' >>"$REPO/file.txt"
git -C "$REPO" add file.txt
git -C "$REPO" -c i18n.commitEncoding=GB18030 commit -q \
  -F "$TMP/gb18030-process-message.txt"
git -C "$REPO" config i18n.logOutputEncoding GB18030
run_gate
git -C "$REPO" config --unset i18n.logOutputEncoding
assert_rc "$rc" 1 "ambient legacy log encoding must not hide a CJK violation"
assert_contains "category=conversation_process" "$out" "legacy-encoding category"
assert_not_contains "synthetic legacy narration" "$out" "legacy diagnostic stays redacted"

# Git's pretty formatter silently truncates a malformed raw commit message at
# an embedded NUL. Validate the raw object before trusting formatted metadata,
# otherwise a neutral prefix can hide a prohibited tail.
nul_tree="$(git -C "$REPO" rev-parse "$clean_head^{tree}")"
python3 - "$TMP/nul-commit-object" "$nul_tree" "$clean_head" <<'PY'
import sys
from pathlib import Path

tree, parent = sys.argv[2:4]
headers = (
    f"tree {tree}\n"
    f"parent {parent}\n"
    "author Synthetic Tester <tester@example.invalid> 1700000000 +0000\n"
    "committer Synthetic Tester <tester@example.invalid> 1700000000 +0000\n"
    "\n"
).encode("ascii")
Path(sys.argv[1]).write_bytes(
    headers
    + b"neutral summary\x00Claude-Session: SYNTH_NUL_MESSAGE_SENTINEL\n"
)
PY
nul_commit="$(git -C "$REPO" hash-object --literally -t commit -w \
  "$TMP/nul-commit-object")"
git -C "$REPO" switch -q -C case/nul-commit-message "$clean_head"
git -C "$REPO" update-ref refs/heads/case/nul-commit-message "$nul_commit"
run_gate
assert_rc "$rc" 2 "an embedded NUL in a raw commit object must fail closed"
assert_contains "candidate commit object contains NUL" "$out" "raw commit NUL reason"
assert_not_contains "SYNTH_NUL_MESSAGE_SENTINEL" "$out" "raw NUL diagnostic stays redacted"

# Replacement refs are a local view only: a push still sends the original OID
# and object. Every Git read in the gate must therefore ignore a clean local
# replacement rather than certifying bytes that will never be published.
clean_replacement="$(printf 'neutral replacement message\n' | \
  git -C "$REPO" commit-tree "$nul_tree" -p "$clean_head")"
git -C "$REPO" replace "$nul_commit" "$clean_replacement"
run_gate
git -C "$REPO" replace -d "$nul_commit" >/dev/null
assert_rc "$rc" 2 "a clean replacement ref must not hide the pushed raw object"
assert_contains "candidate commit object contains NUL" "$out" "replacement ref NUL reason"
assert_not_contains "SYNTH_NUL_MESSAGE_SENTINEL" "$out" "replacement diagnostic stays redacted"

# Legacy grafts rewrite ancestry independently of replacement objects. A clean
# grafted head can hide a prohibited intermediate commit even though a push
# publishes the original parent chain.
graft_bad="$(printf '%s\n' 'Claude-Session-ID: SYNTH_GRAFT_SENTINEL' | \
  git -C "$REPO" commit-tree "$nul_tree" -p "$clean_head")"
graft_head="$(printf 'neutral graft head\n' | \
  git -C "$REPO" commit-tree "$nul_tree" -p "$graft_bad")"
git -C "$REPO" switch -q -C case/graft-history "$clean_head"
git -C "$REPO" update-ref refs/heads/case/graft-history "$graft_head"
graft_file="$(git -C "$REPO" rev-parse --git-path info/grafts)"
case "$graft_file" in
  /*) ;;
  *) graft_file="$REPO/$graft_file" ;;
esac
printf '%s %s\n' "$graft_head" "$clean_head" >"$graft_file"
run_gate
mv "$graft_file" "$graft_file.disabled"
assert_rc "$rc" 2 "a non-empty graft file must not hide pushed ancestry"
assert_contains "candidate history uses unsupported grafts" "$out" "graft reason"
assert_not_contains "SYNTH_GRAFT_SENTINEL" "$out" "graft diagnostic stays redacted"

printf 'tighten-doc: 外部写作实践吸收\n' >"$TMP/provenance-message.txt"
candidate_case case/provenance "$TMP/provenance-message.txt"
run_gate
assert_rc "$rc" 1 "provenance wording must block"
assert_contains "category=provenance_wording" "$out" "provenance category"

# Benign use of the verbs is not provenance unless it names an outside source.
printf 'review loop: 吸收用户反馈经验并收敛规则\n' >"$TMP/benign-message.txt"
candidate_case case/benign-wording "$TMP/benign-message.txt"
run_gate
assert_rc "$rc" 0 "ordinary feedback wording must not be treated as provenance"
assert_contains "commits=2" "$out" "the full multi-commit candidate range is scanned"

printf 'document ordinary product URL https://example.com/session/share-not-ai\n' >"$TMP/product-url-message.txt"
candidate_case case/product-url "$TMP/product-url-message.txt"
run_gate
assert_rc "$rc" 0 "an ordinary product URL must not be treated as an AI session"

# Branch names are shared even before a commit exists.
git -C "$REPO" switch -q -C feature/claude-session_synthetic123 "$clean_head"
run_gate
assert_rc "$rc" 1 "session-shaped branch name must block"
assert_contains "surface=branch" "$out" "branch locator"
assert_not_contains "synthetic123" "$out" "branch diagnostic must not echo the identifier"

assert_branch_block() {
  local branch_name="$1" category="$2" reason="$3"
  set +e
  out="$(env -u GITHUB_EVENT_PATH -u GITHUB_HEAD_REF -u GITHUB_REF_NAME -u CCL_SKILL_BASE_REF \
    python3 "$GATE" --repo "$REPO" --base-ref "$clean_head" \
    --head-ref "$clean_head" --branch-name "$branch_name" 2>&1)"
  rc=$?
  set -e
  assert_rc "$rc" 1 "$reason"
  assert_contains "surface=branch" "$out" "$reason surface"
  assert_contains "category=$category" "$out" "$reason category"
}

assert_branch_clean() {
  local branch_name="$1" reason="$2"
  set +e
  out="$(env -u GITHUB_EVENT_PATH -u GITHUB_HEAD_REF -u GITHUB_REF_NAME -u CCL_SKILL_BASE_REF \
    python3 "$GATE" --repo "$REPO" --base-ref "$clean_head" \
    --head-ref "$clean_head" --branch-name "$branch_name" 2>&1)"
  rc=$?
  set -e
  assert_rc "$rc" 0 "$reason"
}

# Branch refs cannot contain spaces, so prose regexes must not be reused as-is.
# Exercise each branch-only metadata class with every ordinary slug separator.
for branch_separator in '-' '_' '/' '.'; do
  assert_branch_block \
    "feature${branch_separator}inspired${branch_separator}by${branch_separator}claude" \
    provenance_wording "branch provenance wording with '$branch_separator' separators"
  assert_branch_block \
    "feature${branch_separator}adapted${branch_separator}from${branch_separator}gemini" \
    provenance_wording "branch adapted-from wording with '$branch_separator' separators"
  assert_branch_block \
    "feature${branch_separator}generated${branch_separator}by${branch_separator}claude" \
    generated_by_footer "branch generated-by wording with '$branch_separator' separators"
  assert_branch_block \
    "feature${branch_separator}co${branch_separator}authored${branch_separator}by${branch_separator}claude" \
    ai_coauthor_trailer "branch co-author wording with '$branch_separator' separators"
  assert_branch_block \
    "feature${branch_separator}claude${branch_separator}analysis${branch_separator}secret" \
    conversation_process "branch conversation label with '$branch_separator' separators"
done

# A forbidden phrase is a branch segment sequence, not necessarily the final
# text in the ref. Suffixes must not turn shared metadata into an allowed ref.
assert_branch_block \
  feature/inspired-by-claude-fix provenance_wording \
  "branch provenance phrase before a suffix"
assert_branch_block \
  feature/generated-by-claude-cleanup generated_by_footer \
  "branch generated-by phrase before a suffix"
assert_branch_block \
  feature/co-authored-by-claude-change ai_coauthor_trailer \
  "branch co-author phrase before a suffix"
for conversation_branch in \
  feature/user-prompt-secret \
  feature/conversation-process-export \
  feature/conversation-transcript-export \
  feature/claude-analysis-findings \
  feature/用户原话-secret \
  feature/会话过程-export \
  feature/模型分析-internal \
  feature/claude-分析-findings; do
  assert_branch_block \
    "$conversation_branch" conversation_process \
    "branch conversation-process phrase before a suffix"
done

for benign_branch in \
  feature/inspired-by-human-review \
  feature/generated-schema \
  feature/co-authored-policy \
  feature/claude-sdk-compatibility \
  feature/analysis-dashboard \
  feature/analysis-engine \
  feature/user-profile-export \
  feature/conversation-list-export \
  feature/用户反馈-export \
  feature/模型能力-internal \
  feature/claude-分析器-findings; do
  assert_branch_clean "$benign_branch" "ordinary branch capability wording remains accepted"
done

# PR title/body arrive through the GitHub event payload in CI.
git -C "$REPO" switch -q -C feature/sanitized-pr "$clean_head"
python3 - "$TMP/pr-event.json" "$session_url" <<'PY'
import json
import sys
from pathlib import Path

Path(sys.argv[1]).write_text(json.dumps({
    "pull_request": {
        "title": "Bound a shared capability",
        "body": "Details and private session: " + sys.argv[2],
        "head": {"ref": "feature/sanitized-pr"},
        "base": {"sha": ""},
    }
}), encoding="utf-8")
PY
run_gate --event-json "$TMP/pr-event.json"
assert_rc "$rc" 1 "PR body session URL must block"
assert_contains "surface=pull_request_body" "$out" "PR body locator"
assert_not_contains "synthetic_fixture_123456" "$out" "PR diagnostic must redact the session id"

python3 - "$TMP/pr-event.json" "$BASE" <<'PY'
import json
import sys
from pathlib import Path

Path(sys.argv[1]).write_text(json.dumps({
    "pull_request": {
        "title": "借鉴外部实践的规则",
        "body": "Neutral behavior and verification summary.",
        "head": {"ref": "feature/sanitized-pr"},
        "base": {"sha": sys.argv[2]},
    }
}), encoding="utf-8")
PY
run_gate --event-json "$TMP/pr-event.json"
assert_rc "$rc" 1 "PR title provenance wording must block"
assert_contains "surface=pull_request_title" "$out" "PR title locator"

python3 - "$TMP/pr-event.json" "$BASE" <<'PY'
import json
import sys
from pathlib import Path

Path(sys.argv[1]).write_text(json.dumps({
    "pull_request": {
        "title": "Bound a shared capability",
        "body": "Neutral behavior and verification summary.",
        "head": {"ref": "feature/sanitized-pr"},
        "base": {"sha": sys.argv[2]},
    }
}), encoding="utf-8")
PY
run_gate --event-json "$TMP/pr-event.json"
assert_rc "$rc" 0 "sanitized PR metadata should pass"

# A trusted PR event defines the candidate range in CI. An ambient local
# override must not move the base forward to HEAD and hide a violating commit.
candidate_case case/event-base-precedence "$TMP/session-message.txt"
event_head="$(git -C "$REPO" rev-parse HEAD)"
python3 - "$TMP/pr-event.json" "$BASE" <<'PY'
import json
import sys
from pathlib import Path

Path(sys.argv[1]).write_text(json.dumps({
    "pull_request": {
        "title": "Bound a shared capability",
        "body": "Neutral behavior and verification summary.",
        "head": {"ref": "case/event-base-precedence"},
        "base": {"sha": sys.argv[2]},
    }
}), encoding="utf-8")
PY
set +e
out="$(env -u GITHUB_EVENT_PATH -u GITHUB_HEAD_REF -u GITHUB_REF_NAME \
  CCL_SKILL_BASE_REF="$event_head" python3 "$GATE" --repo "$REPO" \
  --event-json "$TMP/pr-event.json" 2>&1)"
rc=$?
set -e
assert_rc "$rc" 1 "trusted PR event base must outrank an ambient environment base"
assert_contains "category=ai_session_trailer" "$out" "event-base precedence preserves the candidate range"
git -C "$REPO" switch -q -C feature/sanitized-pr "$clean_head"

printf 'Neutral proposed PR summary.\n' >"$TMP/proposed-pr.txt"
run_gate --event-json "$TMP/pr-event.json" --pr-text-file "$TMP/proposed-pr.txt"
assert_rc "$rc" 0 "sanitized proposed PR text should pass"
printf 'Private session: %s\n' "$session_url" >"$TMP/proposed-pr.txt"
run_gate --event-json "$TMP/pr-event.json" --pr-text-file "$TMP/proposed-pr.txt"
assert_rc "$rc" 1 "prohibited proposed PR text must block before publication"
assert_contains "surface=proposed_pr_text" "$out" "proposed PR locator"
assert_not_contains "synthetic_fixture_123456" "$out" "proposed PR diagnostic must redact the session id"

# Every provider-shaped surface uses the same provider registry. These cases
# kill partial fixes where a name is added to session IDs but not co-authors,
# narration/provenance, generated attribution, or share URLs.
assert_proposed_block() {
  local text="$1" category="$2" reason="$3"
  printf '%s\n' "$text" >"$TMP/proposed-pr.txt"
  run_gate --event-json "$TMP/pr-event.json" --pr-text-file "$TMP/proposed-pr.txt"
  assert_rc "$rc" 1 "$reason"
  assert_contains "category=$category" "$out" "$reason category"
}
assert_proposed_block "Built with Claude Code" generated_by_footer "generated attribution verb"
assert_proposed_block "- Generated with Claude Code" generated_by_footer "list-wrapped generated attribution"
assert_proposed_block "> 🤖 Generated with Claude Code" generated_by_footer "quote-wrapped generated attribution"
assert_proposed_block "1. Generated with Claude Code" generated_by_footer "ordered-list generated attribution"
assert_proposed_block "### Generated with Claude Code" generated_by_footer "heading-wrapped generated attribution"

# Markdown wrappers are presentation only. Exercise every line-oriented
# metadata class against the same wrapper matrix so a one-pattern fix cannot
# leave a sibling category bypassable.
for markdown_prefix in '- ' '> ' '1. ' '### ' '> - ' '- [ ] ' '> 1. [x] '; do
  assert_proposed_block \
    "${markdown_prefix}Generated with Claude Code" \
    generated_by_footer "Markdown-wrapped generated attribution"
  assert_proposed_block \
    "${markdown_prefix}Claude-Session: synthetic_markdown_123456" \
    ai_session_trailer "Markdown-wrapped session trailer"
  assert_proposed_block \
    "${markdown_prefix}Co-Authored-By: Claude Code <bot@example.invalid>" \
    ai_coauthor_trailer "Markdown-wrapped AI co-author trailer"
  assert_proposed_block \
    "${markdown_prefix}会话过程：synthetic internal narration" \
    conversation_process "Markdown-wrapped conversation-process label"
done

# Inline emphasis/code spans are presentation wrappers too. Keep the opener and
# closer paired so an ordinary leading marker cannot be consumed accidentally.
for inline_pair in '*|*' '_|_' '**|**' '__|__' '~~|~~' '`|`'; do
  inline_open="${inline_pair%%|*}"
  inline_close="${inline_pair#*|}"
  assert_proposed_block \
    "${inline_open}Generated with Claude Code${inline_close}" \
    generated_by_footer "inline-Markdown generated attribution"
  assert_proposed_block \
    "${inline_open}Claude-Session: synthetic_inline_123456${inline_close}" \
    ai_session_trailer "inline-Markdown session trailer"
  assert_proposed_block \
    "${inline_open}Co-Authored-By: Claude Code <bot@example.invalid>${inline_close}" \
    ai_coauthor_trailer "inline-Markdown AI co-author trailer"
  assert_proposed_block \
    "${inline_open}会话过程：synthetic inline narration${inline_close}" \
    conversation_process "inline-Markdown conversation-process label"

  printf '%s\n' "${inline_open}Human-authored compatibility note${inline_close}" >"$TMP/proposed-pr.txt"
  run_gate --event-json "$TMP/pr-event.json" --pr-text-file "$TMP/proposed-pr.txt"
  assert_rc "$rc" 0 "paired inline Markdown around neutral prose remains accepted"
done

# Wrapper depth is input-controlled. Five levels killed the former fixed-depth
# loop; 64 levels keeps the regression honest without making the fixture large.
for nested_depth in 5 64; do
  nested_marker=''
  for ((nested_index = 0; nested_index < nested_depth; nested_index += 1)); do
    nested_marker="${nested_marker}**"
  done
  assert_proposed_block \
    "${nested_marker}Generated with Claude Code${nested_marker}" \
    generated_by_footer "deep inline wrapper generated attribution"
  assert_proposed_block \
    "${nested_marker}Claude-Session: synthetic_nested_123456${nested_marker}" \
    ai_session_trailer "deep inline wrapper session trailer"
  assert_proposed_block \
    "${nested_marker}Co-Authored-By: Claude Code <bot@example.invalid>${nested_marker}" \
    ai_coauthor_trailer "deep inline wrapper co-author trailer"
  assert_proposed_block \
    "${nested_marker}会话过程：synthetic nested narration${nested_marker}" \
    conversation_process "deep inline wrapper conversation label"
done

printf '**Generated with Claude Code__\n' >"$TMP/proposed-pr.txt"
run_gate --event-json "$TMP/pr-event.json" --pr-text-file "$TMP/proposed-pr.txt"
assert_rc "$rc" 0 "mismatched inline wrappers are not normalized as a pair"

assert_proposed_block \
  '[Generated with Claude Code](https://example.invalid)' \
  generated_by_footer "outer Markdown-link generated attribution"
assert_proposed_block \
  '[Co-Authored-By: Claude Code <bot@example.invalid>](https://example.invalid)' \
  ai_coauthor_trailer "outer Markdown-link co-author trailer"
assert_proposed_block \
  '[会话过程：摘要](https://example.invalid)' \
  conversation_process "outer Markdown-link conversation label"

printf '[Claude Code integration guide](https://example.invalid)\n' >"$TMP/proposed-pr.txt"
run_gate --event-json "$TMP/pr-event.json" --pr-text-file "$TMP/proposed-pr.txt"
assert_rc "$rc" 0 "an ordinary complete Markdown link remains accepted"
printf '[Ordinary review](%s)\n' "$session_url" >"$TMP/proposed-pr.txt"
run_gate --event-json "$TMP/pr-event.json" --pr-text-file "$TMP/proposed-pr.txt"
assert_rc "$rc" 1 "a normalized outer link must retain destination scanning"
assert_contains "category=ai_session_url" "$out" "outer-link destination URL category"
assert_not_contains "synthetic_fixture_123456" "$out" "outer-link destination remains redacted"

assert_proposed_block \
  '> **Generated with Claude Code**' \
  generated_by_footer "block and inline Markdown wrappers compose"

for near_miss_prefix in '[x] ' '- [xx] '; do
  printf '%s\n' "${near_miss_prefix}Generated with Claude Code" >"$TMP/proposed-pr.txt"
  run_gate --event-json "$TMP/pr-event.json" --pr-text-file "$TMP/proposed-pr.txt"
  assert_rc "$rc" 0 "a non-task-list checkbox shape must not be consumed as Markdown framing"
done

assert_proposed_block "Co-Authored-By: GitHub Copilot <bot@example.invalid>" ai_coauthor_trailer "provider alias co-author"
assert_proposed_block "Gemini 分析：synthetic internal narration" conversation_process "provider analysis label"
assert_proposed_block "Adapted from Gemini" provenance_wording "provider provenance wording"
assert_proposed_block "Cursor-Session-ID: synthetic_provider_123456" ai_session_id "provider session ID"
assert_not_contains "synthetic_provider_123456" "$out" "expanded provider ID remains redacted"
assert_proposed_block "AI-Session-ID: synthetic_generic_123456" ai_session_id "generic AI session ID"
assert_not_contains "synthetic_generic_123456" "$out" "generic AI ID remains redacted"
assert_proposed_block "Generated by AI" generated_by_footer "generic AI attribution"
assert_proposed_block "Generated by AI model" generated_by_footer "generic AI model attribution"
for model_credit in \
  'Generated by AI Model' \
  'Generated by Gemini Pro' \
  'Generated by Claude Sonnet'; do
  assert_proposed_block \
    "$model_credit" generated_by_footer \
    "common model/product continuation remains generated attribution"
done
assert_proposed_block "Private review: $gemini_url" ai_session_url "provider share URL"
assert_not_contains "synthetic_fixture_ghijkl" "$out" "provider URL remains redacted"
assert_proposed_block "Private review: $chatgpt_conversation_url" ai_session_url "root conversation URL"
assert_not_contains "$conversation_uuid" "$out" "root conversation URL remains redacted"
assert_proposed_block "Private review: $claude_chat_url" ai_session_url "root chat URL"
assert_not_contains "$conversation_uuid" "$out" "root chat URL remains redacted"
assert_proposed_block "Private review: $chatgpt_https_default_port_url" ai_session_url "HTTPS default-port session URL"
assert_not_contains "$conversation_uuid" "$out" "HTTPS default-port URL remains redacted"
assert_proposed_block "Private review: $chatgpt_http_default_port_url" ai_session_url "HTTP default-port session URL"
assert_not_contains "$conversation_uuid" "$out" "HTTP default-port URL remains redacted"

printf 'Private review: %s\n' "$chatgpt_wrong_port_url" >"$TMP/proposed-pr.txt"
run_gate --event-json "$TMP/pr-event.json" --pr-text-file "$TMP/proposed-pr.txt"
assert_rc "$rc" 0 "a cross-scheme non-default port is not treated as the canonical origin"

for human_credit in 'Written by Ai Weiwei' 'Created by Ai Weiwei for the exhibition' 'Written by Claude Monet'; do
  printf '%s\n' "$human_credit" >"$TMP/proposed-pr.txt"
  run_gate --event-json "$TMP/pr-event.json" --pr-text-file "$TMP/proposed-pr.txt"
  assert_rc "$rc" 0 "a human-name credit must not be treated as generated attribution"
done

assert_proposed_block "Inspired by Claude" provenance_wording "standard English provenance wording"
printf 'Inspired by Claude Monet\n' >"$TMP/proposed-pr.txt"
run_gate --event-json "$TMP/pr-event.json" --pr-text-file "$TMP/proposed-pr.txt"
assert_rc "$rc" 0 "a human-name inspiration credit remains accepted"

printf 'Summary\r\n\r\nCo-Authored-By: Claude Code <helper@example.invalid>\r\n🤖 Claude Code\r\n' >"$TMP/proposed-pr.txt"
run_gate --event-json "$TMP/pr-event.json" --pr-text-file "$TMP/proposed-pr.txt"
assert_rc "$rc" 1 "CRLF proposed PR text must not bypass line-anchored metadata checks"
assert_contains "category=ai_coauthor_trailer" "$out" "CRLF co-author trailer category"
assert_contains "category=generated_by_footer" "$out" "CRLF generated footer category"
printf 'Neutral CRLF proposed PR summary.\r\n' >"$TMP/proposed-pr.txt"
run_gate --event-json "$TMP/pr-event.json" --pr-text-file "$TMP/proposed-pr.txt"
assert_rc "$rc" 0 "neutral CRLF proposed PR text remains accepted"

printf '🤖 OpenCode compatibility matrix\n' >"$TMP/proposed-pr.txt"
run_gate --event-json "$TMP/pr-event.json" --pr-text-file "$TMP/proposed-pr.txt"
assert_rc "$rc" 0 "a provider compatibility heading is not a generated footer"
printf 'Ordinary product link: %s\n' "$google_product_url" >"$TMP/proposed-pr.txt"
run_gate --event-json "$TMP/pr-event.json" --pr-text-file "$TMP/proposed-pr.txt"
assert_rc "$rc" 0 "a non-Gemini g.co share path is not an AI session URL"
printf 'Nested help link: %s\n' "$chatgpt_nested_help_url" >"$TMP/proposed-pr.txt"
run_gate --event-json "$TMP/pr-event.json" --pr-text-file "$TMP/proposed-pr.txt"
assert_rc "$rc" 0 "a nested help/chat path is not a root conversation URL"
printf 'Product guide: %s\n' "$claude_nonconversation_url" >"$TMP/proposed-pr.txt"
run_gate --event-json "$TMP/pr-event.json" --pr-text-file "$TMP/proposed-pr.txt"
assert_rc "$rc" 0 "a non-UUID root chat path is not a conversation URL"

# A detached Actions checkout still obtains both the branch and base from the
# event, rather than silently skipping either surface.
git -C "$REPO" switch -q --detach "$clean_head"
run_gate_without_base --event-json "$TMP/pr-event.json"
assert_rc "$rc" 0 "detached checkout with complete PR event should pass"
assert_contains "branch=1" "$out" "event head ref supplied the branch surface"
git -C "$REPO" switch -q -C feature/sanitized-pr "$clean_head"

printf '{ malformed' >"$TMP/pr-event.json"
run_gate --event-json "$TMP/pr-event.json"
assert_rc "$rc" 2 "malformed CI event must fail closed"
assert_contains "shared_git_surface_gate_error" "$out" "malformed-event error marker"

printf '\377' >"$TMP/pr-event.json"
run_gate --event-json "$TMP/pr-event.json"
assert_rc "$rc" 2 "non-UTF-8 CI event must fail closed"
assert_contains "event JSON is not UTF-8" "$out" "non-UTF-8 event reason"

# Error diagnostics are themselves shared log surfaces. Ref/path/error details
# must never repeat the sentinel that made the command fail.
orphan_tree="$(git -C "$REPO" mktree </dev/null)"
orphan_commit="$(printf 'orphan probe\n' | git -C "$REPO" commit-tree "$orphan_tree")"
error_ref='refs/heads/feature/claude-session_SYNTH_ERROR_SENTINEL'
git -C "$REPO" update-ref "$error_ref" "$orphan_commit"
set +e
out="$(env -u GITHUB_EVENT_PATH -u GITHUB_HEAD_REF -u GITHUB_REF_NAME -u CCL_SKILL_BASE_REF \
  python3 "$GATE" --repo "$REPO" --base-ref "$error_ref" 2>&1)"
rc=$?
set -e
assert_rc "$rc" 2 "a base without a merge-base must fail closed"
assert_contains "shared_git_surface_gate_error" "$out" "merge-base error marker"
assert_not_contains "SYNTH_ERROR_SENTINEL" "$out" "git errors must not echo a private ref"

missing_event="$TMP/claude-session_SYNTH_PATH_SENTINEL.json"
run_gate --event-json "$missing_event"
assert_rc "$rc" 2 "an unreadable event path must fail closed"
assert_contains "event JSON unreadable" "$out" "unreadable event reason"
assert_not_contains "SYNTH_PATH_SENTINEL" "$out" "file errors must not echo a private path"

# Pin the secure-open mechanism, not only its happy-path result: opening first
# with no-follow/nonblocking flags and then fstat/read on that descriptor closes
# the lstat→open swap and FIFO-blocking windows.
python3 - "$GATE" "$TMP" "$REPO" <<'PY'
import importlib.util
import os
import signal
import sys
from pathlib import Path

gate_path = Path(sys.argv[1])
probe_path = Path(sys.argv[2]) / "reader-mechanism-probe.json"
repo_path = Path(sys.argv[3])
probe_path.write_text('{"probe": true}', encoding="utf-8")
spec = importlib.util.spec_from_file_location("shared_git_surface_gate_probe", gate_path)
module = importlib.util.module_from_spec(spec)
sys.modules[spec.name] = module
spec.loader.exec_module(module)

# A candidate controls commit/PR text. Repeating a recognized origin without a
# session path must remain bounded by the public PR-text limit rather than make
# the regex rescan the full suffix once per origin.
class RegexDeadline(Exception):
    pass

def regex_deadline(_signum, _frame):
    raise RegexDeadline

origin_near_miss = "https://claude" + "." + "ai/aaaaaaaa"
adversarial_text = (origin_near_miss * 4_000)[:module.MAX_PR_TEXT_BYTES]
previous_alarm = signal.signal(signal.SIGALRM, regex_deadline)
signal.setitimer(signal.ITIMER_REAL, 1.0)
try:
    assert module.violations("proposed_pr_text", "file", adversarial_text) == []
except RegexDeadline as exc:
    raise AssertionError("session URL near-miss scan exceeded its bounded deadline") from exc
finally:
    signal.setitimer(signal.ITIMER_REAL, 0)
    signal.signal(signal.SIGALRM, previous_alarm)

# Branch slug separators are also input-controlled. Boundary recognition must
# not greedily rescan the remaining suffix at every separator position.
branch_near_miss = "-" * 8_000 + "neutral"
previous_alarm = signal.signal(signal.SIGALRM, regex_deadline)
signal.setitimer(signal.ITIMER_REAL, 1.0)
try:
    assert module.violations("branch", "current", branch_near_miss) == []
except RegexDeadline as exc:
    raise AssertionError("branch separator near-miss scan exceeded its bounded deadline") from exc
finally:
    signal.setitimer(signal.ITIMER_REAL, 0)
    signal.signal(signal.SIGALRM, previous_alarm)

real_git = module.git
seen_commit_args = []

def batch_frame(oid, payload=b"synthetic raw commit without a NUL\n"):
    return (
        oid
        + b" commit "
        + str(len(payload)).encode("ascii")
        + b"\n"
        + payload
        + b"\n"
    )

sha1_oid = b"e" * 40
sha256_oid = b"f" * 64
module.validate_commit_batch(batch_frame(sha1_oid), [sha1_oid.decode("ascii")])
module.validate_commit_batch(batch_frame(sha256_oid), [sha256_oid.decode("ascii")])
malformed_batches = (
    b"",
    b"wrong commit 0\n\n",
    sha1_oid + b" blob 0\n\n",
    sha1_oid + b" commit 01\nx\n",
    sha1_oid + b" commit 4\nabc\n",
    sha1_oid + b" commit 3\nabc",
    batch_frame(sha1_oid) + b"trailing",
)
for malformed_batch in malformed_batches:
    try:
        module.validate_commit_batch(malformed_batch, [sha1_oid.decode("ascii")])
    except module.GateError as exc:
        assert str(exc) == "candidate commit object scan returned malformed records"
    else:
        raise AssertionError("malformed batch boundary did not fail closed")
try:
    module.validate_commit_batch(batch_frame(sha1_oid, b"left\x00right"), [sha1_oid.decode("ascii")])
except module.GateError as exc:
    assert str(exc) == "candidate commit object contains NUL"
else:
    raise AssertionError("a NUL inside a length-framed payload did not fail closed")

def clean_commit_git(repo, *args, **kwargs):
    seen_commit_args.extend(args)
    if args[0] == "rev-list":
        return b"a" * 40 + b"\n"
    if args[:2] == ("cat-file", "--batch"):
        assert kwargs["input_bytes"] == b"a" * 40 + b"\n"
        return batch_frame(b"a" * 40)
    return b"a" * 40 + b"\0neutral message\0Human <h@example.invalid>\0Human <h@example.invalid>\0"

module.git = clean_commit_git
assert len(module.commit_messages(repo_path, "base", "head")) == 1
assert "--encoding=UTF-8" in seen_commit_args

def malformed_batch_git(repo, *args, **kwargs):
    if args[0] == "rev-list":
        return b"d" * 40 + b"\n"
    if args[:2] == ("cat-file", "--batch"):
        return b"not a length-framed batch response\n"
    return b"d" * 40 + b"\0neutral\0Human <h@example.invalid>\0Human <h@example.invalid>\0"

module.git = malformed_batch_git
try:
    module.commit_messages(repo_path, "base", "head")
except module.GateError as exc:
    assert str(exc) == "candidate commit object scan returned malformed records"
else:
    raise AssertionError("malformed cat-file batch framing did not fail closed")

prefix = b"c" * 12
first_oid = prefix + b"0" * 28
second_oid = prefix + b"1" * 28

def colliding_prefix_git(repo, *args, **kwargs):
    if args[0] == "rev-list":
        return first_oid + b"\n" + second_oid + b"\n"
    if args[:2] == ("cat-file", "--batch"):
        return batch_frame(first_oid) + batch_frame(second_oid)
    one = b"\0neutral one\0Human <h@example.invalid>\0Human <h@example.invalid>\0"
    two = b"\0neutral two\0Human <h@example.invalid>\0Human <h@example.invalid>\0"
    return second_oid + two + first_oid + one

module.git = colliding_prefix_git
try:
    module.commit_messages(repo_path, "base", "head")
except module.GateError as exc:
    assert str(exc) == "candidate commit scan returned inconsistent records"
else:
    raise AssertionError("full object-id ordering was compared only by locator")

for undecodable in (b"\xff", "\ufffd".encode("utf-8")):
    def undecodable_commit_git(repo, *args, payload=undecodable, **kwargs):
        if args[0] == "rev-list":
            return b"b" * 40 + b"\n"
        if args[:2] == ("cat-file", "--batch"):
            return batch_frame(b"b" * 40)
        return (
            b"b" * 40
            + b"\0"
            + payload
            + b"\0Human <h@example.invalid>\0Human <h@example.invalid>\0"
        )

    module.git = undecodable_commit_git
    try:
        module.commit_messages(repo_path, "base", "head")
    except module.GateError as exc:
        assert str(exc) == (
            "candidate commit metadata is not valid UTF-8 "
            "locator=bbbbbbbbbbbb field=message"
        )
    else:
        raise AssertionError("undecodable commit metadata did not fail closed")

module.git = real_git
seen = {"flags": None, "fstat": 0, "max_read": 0}
real_open = module.os.open
real_fstat = module.os.fstat
real_read = module.read_fd

def tracked_open(path, flags):
    seen["flags"] = flags
    return real_open(path, flags)

def tracked_fstat(fd):
    seen["fstat"] += 1
    return real_fstat(fd)

def tracked_read(fd, size):
    seen["max_read"] = max(seen["max_read"], size)
    return real_read(fd, size)

module.os.open = tracked_open
module.os.fstat = tracked_fstat
module.read_fd = tracked_read
text = module.read_regular(probe_path, max_bytes=32, label="probe")
assert text == '{"probe": true}'
assert seen["flags"] & os.O_NOFOLLOW
assert seen["flags"] & os.O_NONBLOCK
assert seen["fstat"] == 1
assert 0 < seen["max_read"] <= 33

module.os.open = real_open
module.os.fstat = real_fstat
seen["max_read"] = 0
try:
    module.git(
        repo_path,
        "log",
        "-1",
        "--format=%B",
        max_bytes=8,
        operation="bounded git probe",
    )
except module.GateError as exc:
    assert str(exc) == "bounded git probe output exceeds the safety limit"
else:
    raise AssertionError("oversized Git output did not fail closed")
assert 0 < seen["max_read"] <= 9, seen
PY

# Exercise the hook against a synthetic repository because string matching
# cannot prove that every ref is actually scanned with the right head/base.
# Makefile/CI wiring belongs to test_ci_checkout_ref_binding.sh so this focused
# suite remains a self-contained behavior check for the gate and hook.
ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd -P)"
python3 - "$ROOT/AGENTS.md" <<'PY'
import re
import sys
from pathlib import Path

source = Path(sys.argv[1]).read_text(encoding="utf-8")
rule = re.search(
    r"^- \*\*共享 Git 面去会话化\*\*：.*?(?=^- \*\*|\Z)",
    source,
    re.MULTILINE | re.DOTALL,
)
if rule is None or "--pr-text-file <proposed-pr.md>" not in rule.group(0):
    raise SystemExit(
        "FAIL: the root pre-PR contract must scan the proposed title/body "
        "with --pr-text-file <proposed-pr.md>"
    )
PY
HOOK_REPO="$TMP/hook-repo"
mkdir -p "$HOOK_REPO"
git init -q -b dev "$HOOK_REPO"
git -C "$HOOK_REPO" config user.email tester@example.invalid
git -C "$HOOK_REPO" config user.name "Synthetic Tester"
printf 'baseline\n' >"$HOOK_REPO/file.txt"
git -C "$HOOK_REPO" add file.txt
git -C "$HOOK_REPO" commit -qm "baseline"
HOOK_BASE="$(git -C "$HOOK_REPO" rev-parse HEAD)"
HOOK_TREE="$(git -C "$HOOK_REPO" rev-parse 'HEAD^{tree}')"
git -C "$HOOK_REPO" update-ref refs/remotes/origin/dev "$HOOK_BASE"
mkdir -p "$HOOK_REPO/.githooks" "$HOOK_REPO/skills/skill-extraction-workflow/scripts"
cp "$ROOT/.githooks/pre-push" "$HOOK_REPO/.githooks/pre-push"
cp "$GATE" "$HOOK_REPO/skills/skill-extraction-workflow/scripts/shared_git_surface_gate.py"
printf '#!/usr/bin/env bash\nexit 0\n' >"$HOOK_REPO/skills/skill-extraction-workflow/scripts/check-ccl-skills.sh"
chmod +x "$HOOK_REPO/.githooks/pre-push" "$HOOK_REPO/skills/skill-extraction-workflow/scripts/check-ccl-skills.sh"

run_hook_for_remote() {
  local remote_name="$1"
  shift
  set +e
  out="$(printf '%s\n' "$@" | (
    cd "$HOOK_REPO"
    env -u CCL_SKILL_BASE_REF -u GITHUB_EVENT_PATH -u GITHUB_HEAD_REF -u GITHUB_REF_NAME \
      .githooks/pre-push "$remote_name" synthetic
  ) 2>&1)"
  rc=$?
  set -e
}

run_hook() {
  run_hook_for_remote origin "$@"
}

run_hook_with_base() {
  local base_override="$1"
  shift
  set +e
  out="$(printf '%s\n' "$@" | (
    cd "$HOOK_REPO"
    env -u GITHUB_EVENT_PATH -u GITHUB_HEAD_REF -u GITHUB_REF_NAME \
      CCL_SKILL_BASE_REF="$base_override" .githooks/pre-push origin synthetic
  ) 2>&1)"
  rc=$?
  set -e
}

zero=0000000000000000000000000000000000000000
run_hook "refs/heads/feature/deleted $zero refs/heads/feature/deleted $HOOK_BASE"
assert_rc "$rc" 0 "a delete-only push publishes no new metadata and must be skipped"
assert_equals "" "$out" "a delete-only push exits before checkout or metadata gates"

printf 'candidate leak\n\nClaude-Session-ID: SYNTH_REMOTE_TIP_SENTINEL\n' >"$TMP/hook-bad-message.txt"
hook_bad="$(git -C "$HOOK_REPO" commit-tree "$HOOK_TREE" -p "$HOOK_BASE" -F "$TMP/hook-bad-message.txt")"
hook_follow="$(printf 'neutral follow-up\n' | git -C "$HOOK_REPO" commit-tree "$HOOK_TREE" -p "$hook_bad")"
git -C "$HOOK_REPO" update-ref refs/heads/feature/base-probe "$hook_follow"
git -C "$HOOK_REPO" symbolic-ref HEAD refs/heads/feature/base-probe
run_hook "refs/heads/feature/base-probe $hook_follow refs/heads/feature/base-probe $hook_bad"
assert_rc "$rc" 1 "an existing feature remote tip must not hide an earlier candidate leak"
assert_contains "category=ai_session_id" "$out" "feature push uses the landing target base"
assert_not_contains "SYNTH_REMOTE_TIP_SENTINEL" "$out" "hook failure remains redacted"

hook_clean="$(printf 'neutral candidate\n' | git -C "$HOOK_REPO" commit-tree "$HOOK_TREE" -p "$HOOK_BASE")"
printf 'other ref leak\n\nCursor-Session-ID: SYNTH_MULTI_REF_SENTINEL\n' >"$TMP/hook-other-message.txt"
hook_other="$(git -C "$HOOK_REPO" commit-tree "$HOOK_TREE" -p "$HOOK_BASE" -F "$TMP/hook-other-message.txt")"
git -C "$HOOK_REPO" update-ref refs/heads/feature/clean "$hook_clean"
git -C "$HOOK_REPO" update-ref refs/heads/feature/other "$hook_other"
git -C "$HOOK_REPO" symbolic-ref HEAD refs/heads/feature/clean
before_head="$(git -C "$HOOK_REPO" rev-parse HEAD)"
before_status="$(git -C "$HOOK_REPO" status --porcelain=v1)"
run_hook \
  "refs/heads/feature/clean $hook_clean refs/heads/feature/clean $zero" \
  "refs/heads/feature/other $hook_other refs/heads/feature/other $zero"
assert_rc "$rc" 1 "every non-delete ref in a multi-ref push must be scanned"
assert_contains "category=ai_session_id" "$out" "non-HEAD pushed ref finding"
assert_not_contains "SYNTH_MULTI_REF_SENTINEL" "$out" "multi-ref finding remains redacted"
assert_equals "$before_head" "$(git -C "$HOOK_REPO" rev-parse HEAD)" "hook must not move HEAD"
assert_equals "$before_status" "$(git -C "$HOOK_REPO" status --porcelain=v1)" "hook must not alter the working tree"

# The checkout-level structural gate is about HEAD/working-tree state. A clean
# non-HEAD ref must still receive metadata scanning without being rejected by
# an unrelated ambient checkout failure.
hook_non_head="$(printf 'neutral non-head candidate\n' | git -C "$HOOK_REPO" commit-tree "$HOOK_TREE" -p "$HOOK_BASE")"
git -C "$HOOK_REPO" update-ref refs/heads/feature/non-head "$hook_non_head"
printf '#!/usr/bin/env bash\necho SYNTH_AMBIENT_GATE_RAN\nexit 9\n' >"$HOOK_REPO/skills/skill-extraction-workflow/scripts/check-ccl-skills.sh"
chmod +x "$HOOK_REPO/skills/skill-extraction-workflow/scripts/check-ccl-skills.sh"
run_hook "refs/heads/feature/non-head $hook_non_head refs/heads/feature/non-head $zero"
assert_rc "$rc" 0 "a non-HEAD push must not inherit ambient checkout failure"
assert_not_contains "SYNTH_AMBIENT_GATE_RAN" "$out" "checkout gate must be skipped for a non-HEAD-only push"
printf '#!/usr/bin/env bash\nexit 0\n' >"$HOOK_REPO/skills/skill-extraction-workflow/scripts/check-ccl-skills.sh"
chmod +x "$HOOK_REPO/skills/skill-extraction-workflow/scripts/check-ccl-skills.sh"

run_hook "refs/heads/feature/clean $hook_clean refs/heads/feature/claude-session_SYNTH_DEST_SENTINEL $zero"
assert_rc "$rc" 1 "the destination branch name must be scanned"
assert_contains "surface=branch" "$out" "destination branch finding"
assert_not_contains "SYNTH_DEST_SENTINEL" "$out" "destination finding remains redacted"

# A violation already present on the actual main target is outside the new
# main candidate range. This allowed case prevents replacing every base with
# origin/dev and re-policing target history.
printf 'main known debt\n\nClaude-Session-ID: SYNTH_MAIN_DEBT\n' >"$TMP/hook-main-message.txt"
hook_main="$(git -C "$HOOK_REPO" commit-tree "$HOOK_TREE" -p "$HOOK_BASE" -F "$TMP/hook-main-message.txt")"
hook_main_head="$(printf 'neutral promotion\n' | git -C "$HOOK_REPO" commit-tree "$HOOK_TREE" -p "$hook_main")"
git -C "$HOOK_REPO" update-ref refs/heads/dev "$hook_main_head"
git -C "$HOOK_REPO" symbolic-ref HEAD refs/heads/dev
run_hook "refs/heads/dev $hook_main_head refs/heads/main $hook_main"
assert_rc "$rc" 0 "an existing landing target SHA is the main promotion base"

printf 'landing candidate leak\n\nCodex-Session-ID: SYNTH_LANDING_BASE_SENTINEL\n' >"$TMP/hook-landing-leak-message.txt"
hook_landing_leak="$(git -C "$HOOK_REPO" commit-tree "$HOOK_TREE" -p "$hook_main" -F "$TMP/hook-landing-leak-message.txt")"
git -C "$HOOK_REPO" update-ref refs/heads/dev "$hook_landing_leak"
for landing_ref in refs/heads/dev refs/heads/main; do
  run_hook_with_base "$hook_landing_leak" \
    "refs/heads/dev $hook_landing_leak $landing_ref $hook_main"
  assert_rc "$rc" 1 "an environment base must not narrow an existing $landing_ref candidate"
  assert_contains "category=ai_session_id" "$out" "existing landing target remote SHA outranks environment base"
  assert_not_contains "SYNTH_LANDING_BASE_SENTINEL" "$out" "landing-target finding remains redacted"
done
git -C "$HOOK_REPO" update-ref refs/heads/dev "$hook_main_head"

run_hook "refs/heads/dev $hook_main_head refs/heads/main $zero"
assert_rc "$rc" 1 "a new landing target without an explicit base must fail closed"
assert_contains "candidate base is unresolved" "$out" "new landing target failure reason"

run_hook_with_base "$HOOK_BASE" \
  "refs/heads/feature/clean $hook_clean refs/heads/main $zero"
assert_rc "$rc" 0 "an explicit base may delimit a new landing target"

git -C "$HOOK_REPO" update-ref -d refs/remotes/origin/dev
git -C "$HOOK_REPO" update-ref refs/remotes/upstream/dev "$HOOK_BASE"
run_hook_for_remote upstream \
  "refs/heads/feature/clean $hook_clean refs/heads/feature/clean $zero"
assert_rc "$rc" 0 "a feature push derives its dev base from the pushed remote name"
git -C "$HOOK_REPO" update-ref -d refs/remotes/upstream/dev
run_hook "refs/heads/feature/clean $hook_clean refs/heads/feature/clean $zero"
assert_rc "$rc" 1 "a feature push without a resolvable default landing base must fail closed"
assert_contains "set CCL_SKILL_BASE_REF" "$out" "missing default-base remediation hint"
git -C "$HOOK_REPO" update-ref refs/remotes/origin/dev "$HOOK_BASE"

echo "test_shared_git_surface_gate: ok"
