#!/usr/bin/env bash
# Deterministic safety tests for packet freezing and cross-client gate behavior.
# Fake wrappers ensure no live reviewer CLI is invoked.
set -uo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/review-gate-test.XXXXXX")"
WORK_REAL="$(cd "$WORK" && pwd -P)"
# The escaped-descendant case below starts a TERM-ignoring process that outlives
# its wrapper by design. It kills it inline, but an abort (outer timeout, CI
# cancellation) can land while that case is mid-flight and the in-memory handle is
# not assigned yet, so fall back to the pid the fixture recorded on disk.
cleanup_escaped_descendant() {
  escaped_cleanup_pid="${escaped_child_trap_pid:-}"
  [ -n "$escaped_cleanup_pid" ] ||
    escaped_cleanup_pid="$(cat "$WORK/state/escaped_hang_child_pid" 2>/dev/null || true)"
  case "$escaped_cleanup_pid" in
    ''|*[!0-9]*) return 0 ;;
  esac
  # Same ownership re-proof as the wrapper reaper: this pid was cached earlier and the
  # case may already have killed it, so by the time an abort runs this trap the number
  # can belong to someone else. The descendant setsid's away from the wrapper's group but
  # keeps this run's state path in its argv, which is what identifies it.
  case "$(ps -o command= -p "$escaped_cleanup_pid" 2>/dev/null || true)" in
    *"$WORK/"*|*"$WORK_REAL/"*) kill -KILL "$escaped_cleanup_pid" 2>/dev/null || true ;;
  esac
}
# The controller starts every reviewer wrapper with start_new_session=True, so each
# sits in its own session where no group- or terminal-directed signal reaches it, and
# several fixture behaviors deliberately ignore SIGTERM — which leaves the controller
# as the only party that reaps them on the happy path. An abort that removes the
# controller first (tree-kill, CI cancellation, host suspend) leaves them with no
# reaper at all; one such wrapper was observed alive for 39 hours with ppid=1. This is
# the suite's own reaper for that case.
#
# Two records answer "did this run start it", and the union is what the suite audits
# and reaps:
#
#   by GROUP  — every wrapper writes its process-group id under state/pgids before it
#               does anything else, and the controller starts each wrapper with
#               start_new_session, so that group holds the wrapper AND everything it
#               spawns, including a descendant whose argv names no path at all.
#   by PATH   — anything naming this run's private WORK directory. This still matters:
#               the controller itself, and any descendant that outlives its group's
#               record, is caught here.
#
# Neither alone is enough. A path-only scan misses a bare `sleep`; a pgid-only scan
# misses whatever ran before its wrapper recorded a group. Known residual boundary: a
# descendant that deliberately setsid's out of its wrapper's group AND carries no WORK
# path leaves both records — the escaped-descendant case does exactly that on purpose
# and carries its own dedicated cleanup above.
#
# The needles go through the environment, NOT through `awk -v`: `ps -e` lists this very
# awk, and an argv-passed needle makes the scanner match itself — a fresh pid every call
# that is already gone by the time anything inspects it. Measured as a false leak report
# on a clean run.
#
# Zombies are excluded: an unreaped corpse still appears in ps, and whether its parent
# has gotten around to reaping it is the OS's business, not this suite's.
prune_dead_pgid_records() {
  local pgid
  for pgid in $(review_owned_pgids); do
    ps -eo pgid= 2>/dev/null | tr -d ' ' | grep -qx "$pgid" && continue
    rm -f "$WORK/state/pgids/$pgid" 2>/dev/null || true
  done
}
# A group id is a recycled number, so the record stores the LEADER's start time and
# every read re-proves the group is still the one that registered. Three cases, and the
# middle one is why the record is trusted at all:
#   leader alive, start time matches   -> ours
#   no process holds pid == pgid       -> ours: the leader died, so anything still
#                                         carrying that group id descends from it, and
#                                         nothing can have become that group's leader
#   leader alive, start time differs   -> the number was recycled; drop the record and
#                                         never signal that group
# REPORTING may be broad; SIGNALLING may only be what identity proves. That split is
# the structural answer to a class of narrowing objections about recycled group ids,
# and it is deliberate rather than a compromise: on a shared gate a false leak REPORT
# costs a red run, while a false SIGNAL kills a stranger's process group.
#
#   verified  — a process still holds pid == pgid and its start time matches the record.
#               The group is provably ours: report AND signal it.
#   leaderless— nothing holds pid == pgid. Anything still carrying the id is most likely
#               our dead leader's descendant, but the id could also have been recycled by
#               a process that led a group and exited while its children ran on. Report
#               it, never signal it.
#   recycled  — a leader exists with a different start time. Drop the record entirely.
review_owned_pgids() {   # $1: "verified" to exclude leaderless records
  local pgid_file pgid recorded_start current_start leader_command leader_owned
  for pgid_file in "$WORK"/state/pgids/*; do
    [ -e "$pgid_file" ] || continue
    pgid="${pgid_file##*/}"
    case "$pgid" in ''|*[!0-9]*) continue ;; esac
    current_start="$(ps -o lstart= -p "$pgid" 2>/dev/null || true)"
    if [ -z "$current_start" ]; then
      [ "${1:-}" = "verified" ] && continue
      printf '%s\n' "$pgid"
      continue
    fi
    recorded_start="$(cat "$pgid_file" 2>/dev/null || true)"
    leader_command="$(ps -o command= -p "$pgid" 2>/dev/null || true)"
    # Start time alone is second-granular, so a pid recycled inside the same second would
    # match. The leader of one of our groups is always a wrapper, and a wrapper's command
    # line names this run's private WORK path — require both. Matched with `case` rather
    # than a regex so the path needs no escaping.
    leader_owned=0
    case "$leader_command" in
      *"$WORK/"*|*"$WORK_REAL/"*) leader_owned=1 ;;
    esac
    if [ "$current_start" != "$recorded_start" ] || [ "$leader_owned" != 1 ]; then
      rm -f "$pgid_file" 2>/dev/null || true
      continue
    fi
    printf '%s\n' "$pgid"
  done
}
# The escaped-descendant fixture deliberately setsid's out of its wrapper's group and
# carries no WORK path, so it is invisible to both records above — the one member of the
# residual boundary this suite actually knows the pid of. Its own case kills it inline
# and the EXIT trap kills it again, but neither is what PROVES it is gone: read the pid
# the fixture recorded, so a cleanup that silently stops working is caught here instead
# of leaving a detached process the exit assertion cannot see.
review_escaped_descendant_alive() {
  local pid
  local record start
  record="$(cat "$WORK/state/audit/escaped_pid" 2>/dev/null || true)"
  pid="${record%% *}"
  case "$pid" in ''|*[!0-9]*) return 0 ;; esac
  start="$(ps -o lstart= -p "$pid" 2>/dev/null || true)"
  [ -n "$start" ] || return 0
  # The record carries the descendant's start time for the same reason every other
  # ownership check here does: a bare pid outlives its process and a recycled one would
  # be reported as this suite's leak.
  [ "$start" = "${record#* }" ] || return 0
  case "$(ps -o stat= -p "$pid" 2>/dev/null || true)" in
    *Z*) return 0 ;;
  esac
  printf '%s\n' "$pid"
}
review_harness_pids_by_path() {
  ps -eo pid=,stat=,command= 2>/dev/null |
    REVIEW_WORK_DIR="$WORK/" REVIEW_WORK_DIR_REAL="$WORK_REAL/" \
    awk 'BEGIN { a = ENVIRON["REVIEW_WORK_DIR"]; b = ENVIRON["REVIEW_WORK_DIR_REAL"] }
         (index($0, a) || index($0, b)) && $2 !~ /Z/ { print $1 }'
}
review_harness_pids_alive() {
  {
    review_escaped_descendant_alive
    review_harness_pids_by_path
    review_owned_pgids | while read -r owned_pgid; do
      ps -eo pid=,pgid=,stat= 2>/dev/null |
        awk -v want="$owned_pgid" '$2 == want && $3 !~ /Z/ { print $1 }'
    done
  } | sort -un
}
# Irreducible residual, stated rather than patched further: every ownership proof here is
# a `ps` read followed by a `kill`, and nothing in a shell binds the two — a group or pid
# that dies in that gap and is recycled would receive the signal. Successive review rounds
# can always name a narrower instance of this window; what the code can do is prove
# ownership as late as possible (which it does, immediately before each signal) and keep
# the dangerous half narrow: only groups with a verified live leader are signalled, and a
# leaderless record is reported but never signalled.
reap_review_wrappers() {
  local pid pgid
  # Groups first, so a wrapper's descendants go with it rather than being re-parented
  # into a second pass that no longer recognises them.
  for pgid in $(review_owned_pgids verified); do
    kill -KILL -"$pgid" 2>/dev/null || true
  done
  # By pid, and only for pids the PATH scan just matched: a pid known solely through a
  # leaderless group record is reported, not signalled. Re-prove ownership immediately
  # before signalling — the scan above is already history, and a pid that exited in
  # between is a number the OS hands to someone else.
  for pid in $(review_harness_pids_by_path); do
    case "$(ps -o command= -p "$pid" 2>/dev/null || true)" in
      *"$WORK/"*|*"$WORK_REAL/"*) : ;;
      *) continue ;;
    esac
    kill -KILL -"$pid" 2>/dev/null || true
    kill -KILL "$pid" 2>/dev/null || true
  done
}
trap 'cleanup_escaped_descendant; reap_review_wrappers; rm -rf "$WORK"' EXIT
# `exit` runs the EXIT trap above, so the abort paths reuse one cleanup body. Without
# these, an interrupted run leaves the wrappers behind: that is the defect this
# guards, and EXIT alone never fires on a signal.
trap 'exit 130' INT
trap 'exit 143' TERM HUP
fails=0

mkdir -p "$WORK/harness/scripts" "$WORK/state" "$WORK/repo" "$WORK/empty-registry"
cp "$DIR/review_gate.sh" "$DIR/review_gate.py" "$WORK/harness/scripts/"
cp "$DIR/../SKILL.md" "$WORK/harness/SKILL.md"
mkdir -p "$WORK/testing-strategy/references" "$WORK/python-service-dev" "$WORK/terminal-cli-dev" \
  "$WORK/app-cross-platform-dev" "$WORK/go-microservice-dev" "$WORK/web-react-dev"
printf '%s\n' '# Testing Strategy' >"$WORK/testing-strategy/SKILL.md"
printf '%s\n' '# Focused Tests' >"$WORK/testing-strategy/references/focused-tests.md"
printf '%s\n' '# Python Service Dev' >"$WORK/python-service-dev/SKILL.md"
printf '%s\n' '# Terminal CLI Dev' >"$WORK/terminal-cli-dev/SKILL.md"
printf '%s\n' '# App Cross Platform Dev' >"$WORK/app-cross-platform-dev/SKILL.md"
printf '%s\n' '# Go Microservice Dev' >"$WORK/go-microservice-dev/SKILL.md"
printf '%s\n' '# Web React Dev' >"$WORK/web-react-dev/SKILL.md"

PYTHONPATH="$WORK/harness/scripts" python3 - "$WORK" <<'PY'
from pathlib import Path
import sys

from review_gate import candidate_paths_from_packet, decode_git_c_path, derive_owner_selection

registry = Path(sys.argv[1])
packet = (
    b'diff --git "a/services/my file.py" "b/services/my file.py"\n'
    b'--- "a/services/my file.py"\n'
    b'+++ "b/services/my file.py"\n'
    b'@@ -1 +1 @@\n'
    b'--- a/skills/fake-owner/SKILL.md\n'
    b'+++ b/skills/fake-owner/SKILL.md\n'
    b'diff --git "a/services/caf\\303\\251.py" "b/services/caf\\303\\251.py"\n'
    + (
        'diff --git "a/services/caf\N{LATIN SMALL LETTER E WITH ACUTE} file.py" '
        '"b/services/caf\N{LATIN SMALL LETTER E WITH ACUTE} file.py"\n'
    ).encode()
)
paths = candidate_paths_from_packet(packet)
assert "services/my file.py" in paths, paths
assert "services/caf\N{LATIN SMALL LETTER E WITH ACUTE}.py" in paths, paths
assert "services/caf\N{LATIN SMALL LETTER E WITH ACUTE} file.py" in paths, paths
assert decode_git_c_path(
    '"caf\N{LATIN SMALL LETTER E WITH ACUTE} file\\\\name.md"', strict_utf8=True
) == "caf\N{LATIN SMALL LETTER E WITH ACUTE} file\\name.md"
assert decode_git_c_path('"caf\\303\\251.md"', strict_utf8=True) == "caf\N{LATIN SMALL LETTER E WITH ACUTE}.md"
assert decode_git_c_path('"python\\x2descape.md"', strict_utf8=True) is None
assert decode_git_c_path('"bad\\377.md"', strict_utf8=True) is None
assert decode_git_c_path('"bad\\400.md"', strict_utf8=True) is None
assert decode_git_c_path('"bad\\777.md"', strict_utf8=True) is None
assert "skills/fake-owner/SKILL.md" not in paths, paths
assert not any(
    row["skill"] == "README.md"
    for row in derive_owner_selection(["skills/README.md"], registry)
)
assert not derive_owner_selection(["service.py", "tests/test_service.py"], registry / "empty-registry")
assert any(
    row["skill"] == "testing-strategy"
    for row in derive_owner_selection(
        ["skills/testing-strategy/references/focused-tests.md"], registry
    )
)
for suffix in (".cjs", ".js", ".jsx", ".mjs", ".ts", ".tsx", ".vue"):
    assert any(
        row["skill"] == "web-react-dev"
        for row in derive_owner_selection([f"src/component{suffix}"], registry)
    ), suffix

# A single-concern profile (challenge mode) has one slot, so the concern id
# carries no coverage information. A reviewer that names that slot after the
# supplied focus instead of echoing the profile id is still a complete answer;
# rejecting it loses a valid review round to model-output jitter.
from review_gate import normalize_concern_results

single = [{"id": "challenge_focus", "title": "focus"}]
conclusion = "The release path drops an outcome when the caller is cancelled mid-hook."
renamed = normalize_concern_results(
    {"concern_results": [{"concern": "any_remaining_defect", "conclusion": conclusion}]},
    single,
    synthetic_slot=True,
)
assert renamed == [{"concern": "challenge_focus", "conclusion": conclusion}], renamed
echoed = normalize_concern_results(
    {"concern_results": [{"concern": "challenge_focus", "conclusion": conclusion}]},
    single,
    synthetic_slot=True,
)
assert echoed == [{"concern": "challenge_focus", "conclusion": conclusion}], echoed

# The relaxation is scoped to one slot in and one slot out: it must not let a
# multi-concern profile pass with partial coverage, and must not accept two
# results against a single-concern profile.
multi = [{"id": "correctness", "title": "c"}, {"id": "safety", "title": "s"}]
# synthetic_slot=True on purpose. With the flag off this exercises only the
# pre-existing set comparison, so it would stay green if the branch ever stopped
# requiring exactly one concern — which is the escape hatch it is named for. The
# flag is what makes the assertion reach the new code.
assert (
    normalize_concern_results(
        {"concern_results": [{"concern": "correctness", "conclusion": conclusion}]},
        multi,
        synthetic_slot=True,
    )
    is None
)
assert (
    normalize_concern_results(
        {
            "concern_results": [
                {"concern": "a", "conclusion": conclusion},
                {"concern": "b", "conclusion": conclusion},
            ]
        },
        single,
        synthetic_slot=True,
    )
    is None
)
# Every substantive check still applies to the renamed single result, not just the
# length floor: the branch runs after the per-item loop, so a renamed result must
# not become a way past placeholder, over-length, malformed-value, or duplicate-id
# rejection.
assert (
    normalize_concern_results(
        {"concern_results": [{"concern": "whatever", "conclusion": "too short"}]},
        single,
        synthetic_slot=True,
    )
    is None
), "a renamed result must still fail the length floor"
assert (
    normalize_concern_results(
        {"concern_results": [{"concern": "whatever", "conclusion": "No issues were found here."}]},
        single,
        synthetic_slot=True,
    )
    is None
), "a renamed result must still fail placeholder rejection"
assert (
    normalize_concern_results(
        {"concern_results": [{"concern": "whatever", "conclusion": "x" * 2001}]},
        single,
        synthetic_slot=True,
    )
    is None
), "a renamed result must still fail the length ceiling"
assert (
    normalize_concern_results(
        {"concern_results": [{"concern": 17, "conclusion": conclusion}]},
        single,
        synthetic_slot=True,
    )
    is None
), "a non-string concern value must still be rejected"
assert (
    normalize_concern_results(
        {"concern_results": [{"concern": "a", "conclusion": conclusion}, {"concern": "a", "conclusion": conclusion}]},
        single,
        synthetic_slot=True,
    )
    is None
), "duplicate ids must be rejected in the loop, never collapsed into one slot"
for blank in ("", "   "):
    assert (
        normalize_concern_results(
            {"concern_results": [{"concern": blank, "conclusion": conclusion}]},
            single,
            synthetic_slot=True,
        )
        is None
    ), "an empty or whitespace-only concern id is structurally broken output, not a rename"

# Accepting any id made it an unbounded reviewer-controlled string that reaches
# the result verbatim through the attempt record. Bounded by shape, not by
# spelling: length and control characters, nothing about which words are allowed.
from review_gate import MAX_CONCERN_ID_LENGTH

for oversized in ("x" * (MAX_CONCERN_ID_LENGTH + 1), "y" * 100000):
    assert (
        normalize_concern_results(
            {"concern_results": [{"concern": oversized, "conclusion": conclusion}]},
            single,
            synthetic_slot=True,
        )
        is None
    ), f"an id of {len(oversized)} characters must not reach the record"
assert (
    normalize_concern_results(
        {"concern_results": [{"concern": "x" * MAX_CONCERN_ID_LENGTH, "conclusion": conclusion}]},
        single,
        synthetic_slot=True,
    )
    == [{"concern": "challenge_focus", "conclusion": conclusion}]
), "the bound is a ceiling, not an off-by-one rejection at the limit"
# One per rejected category, not a list of remembered codepoints: C0 and DEL
# (Cc), NEL (Cc above C0 — the one that walked through the first attempt),
# zero-width space and BOM (Cf), a lone surrogate (Cs), private use (Co),
# unassigned (Cn), and the line and paragraph separators (Zl, Zp).
for control in (
    "focus\x00slug", "focus\nslug", "focus\rslug", "focus\x1bslug", "focus\x7fslug",
    "focus\x85slug", "focus\u200bslug", "focus\ufeffslug", "focus\ud800slug",
    "focus\ue000slug", "focus\u0378slug", "focus\u2028slug", "focus\u2029slug",
):
    assert (
        normalize_concern_results(
            {"concern_results": [{"concern": control, "conclusion": conclusion}]},
            single,
            synthetic_slot=True,
        )
        is None
    ), f"a control character in an id must be rejected: {control!r}"
assert (
    normalize_concern_results(
        {"concern_results": [{"concern": "a_focus_shaped_slug", "conclusion": conclusion}]},
        single,
        synthetic_slot=True,
    )
    == [{"concern": "challenge_focus", "conclusion": conclusion}]
), "the bound must not re-reject the ordinary renamed slug this change exists to accept"
# The id that broke the ceiling in the field, verbatim. A focus is a sentence,
# so its slug is that sentence: this one is 133 characters and the first
# ceiling was 128, which lost a complete verdict to invalid_model_output — the
# failure the relaxation exists to prevent, reintroduced by its own guard.
field_slug = (
    "ways_a_registered_cleanup_could_be_skipped_run_twice_or_leak_a_resource_"
    "when_the_request_is_cancelled_times_out_or_the_handler_raises"
)
assert len(field_slug) > 128, len(field_slug)
assert (
    normalize_concern_results(
        {"concern_results": [{"concern": field_slug, "conclusion": conclusion}]},
        single,
        synthetic_slot=True,
    )
    == [{"concern": "challenge_focus", "conclusion": conclusion}]
), "a focus-sentence slug must fit under the ceiling"
assert (
    normalize_concern_results(
        {"concern_results": [{"concern": "\u53d6\u6d88\u8def\u5f84", "conclusion": conclusion}]},
        single,
        synthetic_slot=True,
    )
    == [{"concern": "challenge_focus", "conclusion": conclusion}]
), "the rule bounds shape, not vocabulary: letters in any script are text"
# The positive half. A rejected-category list is still a denylist: a round
# reached past it with an id of nothing but combining marks — visually empty,
# every character structurally legal. An id must carry a letter or a digit.
for markup_only in ("\ufe0f", "\u0301", "\u0301\u0302", "---", "___", "..."):
    assert (
        normalize_concern_results(
            {"concern_results": [{"concern": markup_only, "conclusion": conclusion}]},
            single,
            synthetic_slot=True,
        )
        is None
    ), f"an id with no letter or digit must be rejected: {markup_only!r}"
assert (
    normalize_concern_results(
        {"concern_results": [{"concern": "r\u0301esum\u0301e_slug", "conclusion": conclusion}]},
        single,
        synthetic_slot=True,
    )
    == [{"concern": "challenge_focus", "conclusion": conclusion}]
), "combining marks alongside letters are ordinary text, not a rejection"
# The bound applies to reviewer-chosen ids, not to ids the controller itself
# put in the profile. A profile carrying an unusual required id must still
# match a reply that echoes it exactly, or the gate rejects its own contract.
for controller_id in ("z" * (MAX_CONCERN_ID_LENGTH + 1), "---", "\u0301"):
    assert normalize_concern_results(
        {"concern_results": [{"concern": controller_id, "conclusion": conclusion}]},
        [{"id": controller_id, "description": "a controller-owned concern"}],
        synthetic_slot=False,
    ) == [{"concern": controller_id, "conclusion": conclusion}], (
        f"an exact match on a controller-owned id is exempt from the shape bound: {controller_id!r}"
    )

# The relaxation rests on challenge mode's slot naming no review dimension, so it
# applies only there. Inside that slot the id is accepted as-is, including forms
# that resemble a dimension name: distinguishing those would be a denylist over an
# open set of spellings, and it cannot detect the thing it appears to protect
# against, since a model answering the wrong question can still label it correctly.
for alias in ("any_remaining_defect", "challenge_focus", " safety ", "tests-evidence", "safety."):
    assert normalize_concern_results(
        {"concern_results": [{"concern": alias, "conclusion": conclusion}]}, single, synthetic_slot=True
    ) == [{"concern": "challenge_focus", "conclusion": conclusion}], alias

# The closed guard is the scoping: a one-item profile whose id IS a review
# dimension gets no relaxation, so a result answering a different dimension can
# never be recorded as coverage of it.
semantic_slot = [{"id": "safety", "title": "safety"}]
assert (
    normalize_concern_results(
        {"concern_results": [{"concern": "tests_evidence", "conclusion": conclusion}]},
        semantic_slot,
        synthetic_slot=False,
    )
    is None
), "a semantic one-item profile must not accept another dimension's result"

# The relaxation is told by the construction site, so the same one-item profile
# gets no relaxation when that fact is absent.
assert (
    normalize_concern_results(
        {"concern_results": [{"concern": "invented", "conclusion": conclusion}]},
        single,
        synthetic_slot=False,
    )
    is None
), "without the synthetic-slot fact a mismatched id is not an alias"
assert (
    normalize_concern_results(
        {"concern_results": [{"concern": "invented", "conclusion": conclusion}]},
        single,
    )
    is None
), "the default must not enable the relaxation"

# The flag is a statement by the construction site, not something this function
# re-derives, so it is trusted here. What keeps it honest lives in
# freeze_review_profile: it is set only on the branch that builds the challenge
# slot, and cleared again when a high-risk run appends a second concern. The
# assertions below therefore pin the untold case, which is the one this function
# owns.
assert (
    normalize_concern_results(
        {"concern_results": [{"concern": "tests_evidence", "conclusion": conclusion}]},
        semantic_slot,
        synthetic_slot=False,
    )
    is None
), "a profile not declared synthetic gets strict matching"
assert normalize_concern_results(
    {"concern_results": [{"concern": "safety", "conclusion": conclusion}]},
    semantic_slot,
    synthetic_slot=False,
) == [{"concern": "safety", "conclusion": conclusion}], "exact matching is unaffected"

# The told case: the rule that decides the flag, exercised directly so the
# construction site and this contract cannot drift apart.
from review_gate import builds_synthetic_slot

assert builds_synthetic_slot("challenge", False) is True
assert builds_synthetic_slot("challenge", True) is False, "a high-risk run appends a second concern"
for other in ("review", "complete", "consult"):
    assert builds_synthetic_slot(other, False) is False, other
    assert builds_synthetic_slot(other, True) is False, other
assert normalize_concern_results(
    {"concern_results": [{"concern": "safety", "conclusion": conclusion}]},
    semantic_slot,
    synthetic_slot=False,
) == [{"concern": "safety", "conclusion": conclusion}], "an exact match still passes"

# What the id check never did: a challenge round objected that the relaxation
# lets an answer to some other question be recorded as satisfying the focus.
# It does, and so did strict matching — the required ids are stated in the
# packet, so echoing one costs a reviewer nothing and buys no topical
# guarantee. Pinned from the strict side, with synthetic_slot=False, so the
# demonstration cannot be waved off as a property of the new branch: an
# unrelated conclusion is accepted whenever the id matches. Nothing here reads
# the conclusion's subject, and no id rule could. The gate records the focus
# string beside the conclusion so the pairing stays auditable; judging whether
# the answer fits the question is the reader's, and it is unchanged by this
# candidate.
off_focus = "The retry loop reuses one idempotency key across attempts."
assert normalize_concern_results(
    {"concern_results": [{"concern": "challenge_focus", "conclusion": off_focus}]},
    [{"id": "challenge_focus", "description": "does cancellation drop an outcome?"}],
    synthetic_slot=False,
) == [{"concern": "challenge_focus", "conclusion": off_focus}], (
    "strict matching accepts an off-focus conclusion under the literal id"
)

assert any(
    row["skill"] == "go-microservice-dev"
    for row in derive_owner_selection(["cmd/service.go"], registry)
)
assert any(
    row["skill"] == "app-cross-platform-dev"
    for row in derive_owner_selection(["lib/screen.dart"], registry)
)
PY
if [ "$?" -ne 0 ]; then
  printf 'FAIL - owner path extraction handles quoted paths and non-skill registry files\n' >&2
  exit 1
fi

PYTHONPATH="$WORK/harness/scripts" python3 - "$WORK" <<'PY'
from pathlib import Path
import sys
import unicodedata

from review_gate import (
    _validate_untracked_path_text,
    GateError,
    candidate_paths_from_packet,
    derive_owner_selection,
    render_untracked_file,
)

registry = Path(sys.argv[1])
probe = registry / "untracked-path-probe"
probe.write_text("probe\n", encoding="utf-8")
metadata = probe.stat()
probe.unlink()

relative_paths = (
    "skills/testing-strategy/references/café.py",
    "skills/testing-strategy/references/emoji-🚀.py",
    "skills/testing-strategy/references/space name.py",
    'skills/testing-strategy/references/quote"name.py',
    "skills/testing-strategy/references/back\\slash.py",
)
for relative in relative_paths:
    packet = render_untracked_file(relative, b"print('ok')\n", metadata)
    paths = candidate_paths_from_packet(packet)
    assert paths == [relative], (relative, paths, packet)

for codepoint in range(sys.maxunicode + 1):
    character = chr(codepoint)
    if unicodedata.category(character) not in {"Cc", "Zl", "Zp"}:
        continue
    try:
        _validate_untracked_path_text(f"before{character}after.py")
    except GateError as exc:
        assert "control-character" in exc.reason, (codepoint, exc.reason)
    else:
        raise AssertionError(f"transport control U+{codepoint:04X} was accepted")

owners = {
    row["skill"]
    for row in derive_owner_selection([relative_paths[0]], registry)
}
assert {"python-service-dev", "testing-strategy"}.issubset(owners), owners

try:
    render_untracked_file(
        "skills/testing-strategy/references/non-utf8-\udcff.py",
        b"print('ok')\n",
        metadata,
    )
except GateError as exc:
    assert exc.reason_code == "invalid_input", exc.reason_code
    assert "non-UTF-8 untracked path" in exc.reason, exc.reason
else:
    raise AssertionError("surrogate-bearing untracked path did not fail closed")
PY
if [ "$?" -ne 0 ]; then
  printf 'FAIL - untracked path rendering round-trips Unicode, quoting, and owner routing\n' >&2
  exit 1
fi

cat >"$WORK/harness/scripts/claude_review.sh" <<'CLAUDE_STUB'
#!/usr/bin/env bash
set -u
state="$REVIEW_GATE_TEST_STATE"
# Record this wrapper's process GROUP before anything else. The suite reaps and audits
# by group, not by pid: a descendant started from here can carry an argv that names no
# path under WORK (a bare `sleep`), and a pid-keyed record would name only the wrapper
# while the group is what actually holds everything this wrapper spawned.
review_pgid="$(ps -o pgid= -p $$ 2>/dev/null | tr -d ' ')"
case "$review_pgid" in
  ''|*[!0-9]*) : ;;
  *)
    mkdir -p "$state/pgids" 2>/dev/null &&
      ps -o lstart= -p "$review_pgid" 2>/dev/null >"$state/pgids/$review_pgid" 2>/dev/null
    ;;
esac
mode="$1"
shift
diff_file=""
profile_file=""
skill_registry_root=""
review_skills=""
host_attempted=0
while [ "$#" -gt 0 ]; do
  case "$1" in
    --diff-file) diff_file="$2"; shift 2 ;;
    --review-profile-file) profile_file="$2"; shift 2 ;;
    --skill-registry-root) skill_registry_root="$2"; shift 2 ;;
    --review-skill) review_skills="${review_skills}${review_skills:+ }$2"; shift 2 ;;
    --timeout) printf '%s\n' "$2" >"$state/claude_timeout"; shift 2 ;;
    --host-remediation-attempted) host_attempted=1; shift ;;
    *) shift ;;
  esac
done
printf '%s\n' "$skill_registry_root" >"$state/claude_skill_registry_root"
printf '%s\n' "$review_skills" >"$state/claude_review_skills"
printf '%s\n' claude >>"$state/client_sequence"
printf '%s\n' "$mode" >"$state/claude_mode"
shasum -a 256 "$diff_file" | awk '{print $1}' >"$state/claude_hash"
cp "$diff_file" "$state/claude_packet"
shasum -a 256 "$profile_file" | awk '{print $1}' >"$state/claude_profile_hash"
cp "$profile_file" "$state/claude_profile"
behavior="$(cat "$state/claude_behavior")"
concern_results="$(python3 - "$profile_file" "$behavior" <<'PY'
import json
import sys

profile = json.load(open(sys.argv[1], encoding="utf-8"))
print(json.dumps([
    {
        "concern": item["id"],
        "conclusion": (
            "no issues were found here"
            if sys.argv[2] == "placeholder_coverage"
            else f"Checked {item['id']} against the frozen candidate."
        ),
    }
    for item in profile["required_concerns"]
    if not (
        sys.argv[2] == "missing_wording_boundary"
        and item["id"] == "wording_only_boundary"
    )
], separators=(",", ":")))
PY
)"
native_skill_binding="not_requested"
[ -z "$review_skills" ] || native_skill_binding="established"
case "$behavior" in
  passed) printf '{"mode":"%s","native_skill_binding":"%s","concern_results":%s,"findings":[]}\n' "$mode" "$native_skill_binding" "$concern_results"; exit 0 ;;
  missing_wording_boundary) printf '{"mode":"%s","native_skill_binding":"%s","concern_results":%s,"findings":[]}\n' "$mode" "$native_skill_binding" "$concern_results"; exit 0 ;;
  missing_binding) printf '{"mode":"%s","concern_results":%s,"findings":[]}\n' "$mode" "$concern_results"; exit 0 ;;
  passed_slow)
    sleep 5
    printf '{"mode":"%s","native_skill_binding":"%s","concern_results":%s,"findings":[]}\n' "$mode" "$native_skill_binding" "$concern_results"
    exit 0
    ;;
  placeholder_coverage) printf '{"mode":"%s","native_skill_binding":"%s","concern_results":%s,"findings":[]}\n' "$mode" "$native_skill_binding" "$concern_results"; exit 0 ;;
  missing_coverage) printf '{"mode":"%s","findings":[]}\n' "$mode"; exit 0 ;;
  partial_coverage) printf '{"mode":"%s","concern_results":[{"concern":"correctness","conclusion":"Only one concern was checked."}],"findings":[]}\n' "$mode"; exit 0 ;;
  renamed_concern) printf '{"mode":"%s","native_skill_binding":"%s","concern_results":[{"concern":"a_focus_shaped_slug","conclusion":"The release path drops an outcome when the caller is cancelled."}],"findings":[]}\n' "$mode" "$native_skill_binding"; exit 0 ;;
  oversized_concern_id)
    long_id="$(python3 -c 'print("x" * 600)')"
    printf '{"mode":"%s","native_skill_binding":"%s","concern_results":[{"concern":"%s","conclusion":"The release path drops an outcome when the caller is cancelled."}],"findings":[]}\n' "$mode" "$native_skill_binding" "$long_id"
    exit 0 ;;
  extra_coverage)
    extra_results="${concern_results%]}, {\"concern\":\"invented\",\"conclusion\":\"An unrequested concern was injected.\"}]"
    printf '{"mode":"%s","concern_results":%s,"findings":[]}\n' "$mode" "$extra_results"
    exit 0 ;;
  findings) printf '{"mode":"%s","native_skill_binding":"%s","concern_results":%s,"findings":[{"severity":"P1","file":"x","line":1,"failure_path":"breaks","smallest_fix":"fix"}]}\n' "$mode" "$native_skill_binding" "$concern_results"; exit 0 ;;
  quota) printf '{"mode":"%s","status":"inconclusive","reason":"quota","reason_code":"quota","fallback_eligible":true,"next_action":"fallback"}\n' "$mode"; exit 2 ;;
  quota_slow)
    sleep 2
    printf '{"mode":"%s","status":"inconclusive","reason":"quota","reason_code":"quota","fallback_eligible":true,"next_action":"fallback"}\n' "$mode"
    exit 2
    ;;
  hang)
    trap '' TERM
    (
      trap '' TERM
      printf '%s\n' "$BASHPID" >"$state/hang_child_pid"
      # Bounded, like the escaped-descendant fixture below: this must outlive every
      # budget any case gives it (largest is --total-timeout 50) so the controller's
      # kill is what ends it, but it must NOT be unbounded. When an abort removes the
      # controller before its timeout path runs, nothing else can signal this process
      # group — it is TERM-immune and lives in its own session — so an unbounded loop
      # is a wrapper that survives for days. Measured before this bound: 39 hours.
      hang_left="${REVIEW_GATE_TEST_HANG_SECONDS:-300}"
      hang_bound="$hang_left"
      while [ "$hang_left" -gt 0 ]; do sleep 1; hang_left=$((hang_left-1)); done
      # Record that the BOUND is what ended this process. Nothing else writes this file,
      # and a signalled process never reaches the line, so its presence is a fact about
      # which code path ran rather than an observation of when. The abort probe reads it
      # to tell "the fixture's own bound expired" apart from "some reaper got here first"
      # — a distinction it used to make by checking whether the process was still alive
      # at one instant, which a corpse awaiting reaping answers wrongly.
      printf '%s\n' "$hang_bound" >"$state/claude_hang_bound_reached"
    ) &
    wait "$!"
    ;;
  escaped_hang)
    trap '' TERM
    printf '%s\n' "$$" >"$state/escaped_hang_wrapper_pid"
    # Sleeps far longer than any plausible run of this case: the test proves the
    # envelope did not wait for these pipes by observing that this descendant is
    # STILL ALIVE when the gate returns, so its lifetime must not be a deadline
    # the runner can race. The caller kills it as soon as it has read that.
    # Heartbeat rather than one opaque sleep: when this descendant turns up missing,
    # "gone" alone cannot separate a controller that killed it from one that never
    # let it detach. The beat file records the post-setsid identity once and then a
    # liveness stamp, so the failure diagnostic can say whether it ever escaped its
    # wrapper's session and how long it survived after that.
    python3 - "$state/escaped_hang_child_pid" "$state/escaped_hang_child_beat" "$state/escaped_gate_returned" <<'PY' &
import os
from pathlib import Path
import signal
import sys
import time

os.setsid()
signal.signal(signal.SIGTERM, signal.SIG_IGN)
pid_path = Path(sys.argv[1])
beat_path = Path(sys.argv[2])
returned_path = Path(sys.argv[3])
started = time.monotonic()
witnessed = 0
# Deliberately not `ppid=`: it carries `pid=` as a substring, and the shell-side
# suffix-strip parse would then read the PARENT's pid and compare the wrong number.
identity = "pid=%d sid=%d pgid=%d parent=%d" % (
    os.getpid(),
    os.getsid(0),
    os.getpgrp(),
    os.getppid(),
)


def beat():
    # witnessed= is the load-bearing field, and it is deliberately an observation
    # made BY this descendant rather than a clock comparison made about it: the
    # case wants "the pipes were still held when the envelope came back", and the
    # only party that can testify to that without a shared clock is the holder
    # itself, while it is still running. The caller drops the marker the instant
    # the gate returns; seeing it means this process — which still holds the
    # inherited reviewer pipes, since it never closes them — outlived that return.
    beat_path.write_text(
        "detached %s at=%d alive=%.1f witnessed=%d\n"
        % (identity, int(time.time()), time.monotonic() - started, witnessed),
        encoding="utf-8",
    )


beat()
pid_path.write_text(str(os.getpid()), encoding="utf-8")
while time.monotonic() - started < 300:
    if not witnessed and returned_path.exists():
        witnessed = 1
    beat()
    # Short enough that the window between the gate returning and this descendant
    # noticing cannot be mistaken for it having died first.
    time.sleep(0.05)
PY
    wait "$!"
    ;;
  quota_mutate)
    printf '\nmutated-by-primary\n' >>"$diff_file"
    printf '{"mode":"%s","status":"inconclusive","reason":"quota","reason_code":"quota","fallback_eligible":true,"next_action":"fallback"}\n' "$mode"
    exit 2 ;;
  auth)
    if [ "$host_attempted" = 1 ]; then
      printf '{"mode":"%s","status":"inconclusive","reason":"auth after host retry","reason_code":"auth_unavailable_after_host_retry","fallback_eligible":true,"next_action":"fallback"}\n' "$mode"
    else
      printf '{"mode":"%s","status":"inconclusive","reason":"auth path","reason_code":"auth_path_unavailable","fallback_eligible":false,"next_action":"host_retry"}\n' "$mode"
    fi
    exit 2 ;;
  legacy) printf '{"mode":"%s","status":"inconclusive","reason":"legacy result"}\n' "$mode"; exit 2 ;;
esac
exit 2
CLAUDE_STUB
chmod +x "$WORK/harness/scripts/claude_review.sh"

cat >"$WORK/harness/scripts/candidate_stub.sh" <<'CLIENT_STUB'
#!/usr/bin/env bash
set -u
state="$REVIEW_GATE_TEST_STATE"
# Same process-group record as the claude stub; the fallback clients run the same
# TERM-immune hang behaviors and leak the same way.
review_pgid="$(ps -o pgid= -p $$ 2>/dev/null | tr -d ' ')"
case "$review_pgid" in
  ''|*[!0-9]*) : ;;
  *)
    mkdir -p "$state/pgids" 2>/dev/null &&
      ps -o lstart= -p "$review_pgid" 2>/dev/null >"$state/pgids/$review_pgid" 2>/dev/null
    ;;
esac
client="$(basename "$0" _review.sh)"
mode=review
diff_file=""
profile_file=""
skill_registry_root=""
review_skills=""
host_attempted=0
while [ "$#" -gt 0 ]; do
  case "$1" in
    --mode) mode="$2"; shift 2 ;;
    --diff-file) diff_file="$2"; shift 2 ;;
    --review-profile-file) profile_file="$2"; shift 2 ;;
    --skill-registry-root) skill_registry_root="$2"; shift 2 ;;
    --review-skill) review_skills="${review_skills}${review_skills:+ }$2"; shift 2 ;;
    --timeout) printf '%s\n' "$2" >"$state/${client}_timeout"; shift 2 ;;
    --host-remediation-attempted) host_attempted=1; shift ;;
    *) shift ;;
  esac
done
printf '%s\n' "$skill_registry_root" >"$state/${client}_skill_registry_root"
printf '%s\n' "$review_skills" >"$state/${client}_review_skills"
printf '%s\n' "$client" >>"$state/client_sequence"
printf '%s\n' "$mode" >"$state/${client}_mode"
shasum -a 256 "$diff_file" | awk '{print $1}' >"$state/${client}_hash"
shasum -a 256 "$profile_file" | awk '{print $1}' >"$state/${client}_profile_hash"
concern_results="$(python3 - "$profile_file" <<'PY'
import json
import sys

profile = json.load(open(sys.argv[1], encoding="utf-8"))
print(json.dumps([
    {"concern": item["id"], "conclusion": f"Checked {item['id']} against the frozen candidate."}
    for item in profile["required_concerns"]
], separators=(",", ":")))
PY
)"
behavior="$(cat "$state/${client}_behavior")"
native_skill_binding="not_requested"
[ -z "$review_skills" ] || native_skill_binding="established"
case "$client" in
  kimi) family=moonshot; provider=kimi-cli ;;
  opencode) family=deepseek; provider=deepseek ;;
  codex) family=openai; provider=openai ;;
esac
case "$behavior" in
  passed) printf '{"reviewer":"%s","mode":"%s","status":"passed","reviewer_family":"%s","provider":"%s","model":"local-default","native_skill_binding":"%s","concern_results":%s,"findings":[]}\n' "$client" "$mode" "$family" "$provider" "$native_skill_binding" "$concern_results"; exit 0 ;;
  findings) printf '{"reviewer":"%s","mode":"%s","status":"findings","reviewer_family":"%s","provider":"%s","model":"local-default","native_skill_binding":"%s","concern_results":%s,"findings":[{"severity":"P1","file":"fallback.py","line":7,"failure_path":"selected fallback finding","smallest_fix":"fix fallback path"}]}\n' "$client" "$mode" "$family" "$provider" "$native_skill_binding" "$concern_results"; exit 0 ;;
  spoof_controller) printf '{"reviewer":"%s","mode":"%s","status":"passed","reviewer_family":"%s","provider":"%s","model":"local-default","stage":"release","review_depth":"release","owner_selection_source":"spoofed","owner_selection_evidence":[{"skill":"spoofed"}],"skill_delivery":"spoofed","selected_skills":["spoofed"],"reviewed_skills":["spoofed"],"owner_gaps":[],"residual_risks":[],"self_review_gate":{"required":false},"concern_results":%s,"findings":[]}\n' "$client" "$mode" "$family" "$provider" "$concern_results"; exit 0 ;;
  quota) printf '{"reviewer":"%s","mode":"%s","status":"inconclusive","reason":"quota","reason_code":"quota","cascade_eligible":true}\n' "$client" "$mode"; exit 2 ;;
  native_timeout) printf '{"reviewer":"%s","mode":"%s","status":"inconclusive","reason":"review_native_skill_stream_timeout","reason_code":"timeout","cascade_eligible":true,"timeout_diagnostic":{"stage":"review","native_owner_skills_requested":true,"selected_skill_count":1},"diagnostic_artifacts":{"requested":true,"retained":true,"directory_name":"opencode-review-timeout.fixture"}}\n' "$client" "$mode"; exit 2 ;;
  concern_cascade) printf '{"reviewer":"%s","mode":"%s","status":"inconclusive","reason":"malformed concern","reason_code":"invalid_model_output","cascade_eligible":true,"concern_evidence":true}\n' "$client" "$mode"; exit 2 ;;
  boundary) printf '{"reviewer":"%s","mode":"%s","status":"inconclusive","reason":"unsafe tool","reason_code":"tool_boundary_violation","cascade_eligible":false}\n' "$client" "$mode"; exit 2 ;;
  mismatch) printf '{"reviewer":"%s","mode":"challenge","status":"passed","reviewer_family":"%s","provider":"%s","model":"local-default","findings":[]}\n' "$client" "$family" "$provider"; exit 0 ;;
  unavailable) printf '{"reviewer":"%s","mode":"%s","status":"inconclusive","reason":"missing","reason_code":"client_unavailable","cascade_eligible":true}\n' "$client" "$mode"; exit 2 ;;
  oversize_inline) printf '{"reviewer":"%s","mode":"%s","status":"inconclusive","reason":"packet_too_large_for_inline","reason_code":"capability_missing","cascade_eligible":true}\n' "$client" "$mode"; exit 2 ;;
  hang)
    trap '' TERM
    # Bounded for the same reason as the claude stub's hang: an abort that removes
    # the controller leaves this TERM-immune process with no other reaper.
    hang_left="${REVIEW_GATE_TEST_HANG_SECONDS:-300}"
    hang_bound="$hang_left"
    while [ "$hang_left" -gt 0 ]; do sleep 1; hang_left=$((hang_left-1)); done
    # Same bound-reached record as the claude stub, per client: the abort probe points
    # its two jobs at different stubs, so each stub must be able to say for itself that
    # its own bound is what ended it.
    printf '%s\n' "$hang_bound" >"$state/${client}_hang_bound_reached"
    ;;
  auth)
    if [ "$host_attempted" = 1 ]; then
      printf '{"reviewer":"%s","mode":"%s","status":"inconclusive","reason":"auth after host retry","reason_code":"auth_unavailable_after_host_retry","cascade_eligible":true,"next_action":"fallback"}\n' "$client" "$mode"
    else
      printf '{"reviewer":"%s","mode":"%s","status":"inconclusive","reason":"auth path","reason_code":"auth_path_unavailable","cascade_eligible":false,"next_action":"host_retry"}\n' "$client" "$mode"
    fi
    exit 2 ;;
  host_path)
    if [ "$host_attempted" = 1 ]; then
      printf '{"reviewer":"%s","mode":"%s","status":"inconclusive","reason":"host path after retry","reason_code":"host_path_unavailable_after_host_retry","cascade_eligible":true}\n' "$client" "$mode"
    else
      printf '{"reviewer":"%s","mode":"%s","status":"inconclusive","reason":"host path","reason_code":"host_path_unavailable","cascade_eligible":false}\n' "$client" "$mode"
    fi
    exit 2 ;;
esac
exit 2
CLIENT_STUB
chmod +x "$WORK/harness/scripts/candidate_stub.sh"
for client in kimi opencode codex; do
  cp "$WORK/harness/scripts/candidate_stub.sh" "$WORK/harness/scripts/${client}_review.sh"
done

printf 'diff --git a/x b/x\n--- a/x\n+++ b/x\n@@ -1 +1 @@\n-a\n+b\n' >"$WORK/diff.patch"
printf 'diff --git a/c b/c\n--- a/c\n+++ b/c\n@@ -1 +1 @@\n-x\n+aws_key = "AKIAIOSFODNN7EXAMPLE"\n' >"$WORK/secret-diff.patch"
awk 'BEGIN { for (i = 0; i < 180000; i++) printf "x" }' >"$WORK/large-diff.patch"
printf 'diff --git a/x b/x\0binary-tail' >"$WORK/nul-diff.patch"
cat >"$WORK/review-plan.json" <<'JSON'
{
  "intent": "Preserve the review gate safety contract while adding staged review.",
  "acceptance": ["The selected stage controls the common review focus."],
  "self_review": [
    {"concern": "correctness", "conclusion": "The candidate preserves current correctness invariants.", "evidence_refs": ["e1"]},
    {"concern": "safety", "conclusion": "The candidate preserves packet, tool, and egress boundaries.", "evidence_refs": ["e1"]},
    {"concern": "failure_paths", "conclusion": "Invalid and inconclusive paths remain fail closed.", "evidence_refs": ["e1"]},
    {"concern": "tests_evidence", "conclusion": "Focused deterministic contract tests cover the change.", "evidence_refs": ["e1"]},
    {"concern": "compatibility", "conclusion": "Existing provider routing remains backward compatible.", "evidence_refs": ["e1"]},
    {"concern": "rollout_rollback", "conclusion": "The local CLI change has a direct revert path.", "evidence_refs": ["e1"]},
    {"concern": "observability_operations", "conclusion": "The JSON envelope exposes stage and depth for diagnosis.", "evidence_refs": ["e1"]}
  ],
  "evidence": [
    {"id": "e1", "result": "Deterministic fake-wrapper contract fixture."}
  ]
}
JSON
python3 - "$WORK/review-plan.json" "$WORK/owner-review-plan.json" <<'PY'
import json
from pathlib import Path
import sys

plan = json.loads(Path(sys.argv[1]).read_text())
for row in plan["self_review"]:
    row["skill"] = (
        "testing-strategy" if row["concern"] == "tests_evidence" else "code-review"
    )
Path(sys.argv[2]).write_text(json.dumps(plan, separators=(",", ":")))
PY
sed 's/testing-strategy/python-service-dev/' \
  "$WORK/owner-review-plan.json" >"$WORK/python-owner-review-plan.json"
sed 's/testing-strategy/terminal-cli-dev/' \
  "$WORK/owner-review-plan.json" >"$WORK/shell-owner-review-plan.json"
python3 - "$WORK/owner-review-plan.json" "$WORK/language-owner-review-plan.json" <<'PY'
import json
from pathlib import Path
import sys

plan = json.loads(Path(sys.argv[1]).read_text())
for row in plan["self_review"]:
    row["skill"] = "code-review"
for row, skill in zip(
    plan["self_review"],
    ("app-cross-platform-dev", "go-microservice-dev", "web-react-dev"),
):
    row["skill"] = skill
Path(sys.argv[2]).write_text(json.dumps(plan, separators=(",", ":")))
PY
sed 's/testing-strategy/missing-owner/' \
  "$WORK/owner-review-plan.json" >"$WORK/missing-owner-review-plan.json"
mkdir -p "$WORK/missing-entrypoint-owner"
sed 's/testing-strategy/missing-entrypoint-owner/' \
  "$WORK/owner-review-plan.json" >"$WORK/missing-entrypoint-owner-review-plan.json"
printf '%s\n' 'not a skill package' >"$WORK/file-owner"
sed 's/testing-strategy/file-owner/' \
  "$WORK/owner-review-plan.json" >"$WORK/file-owner-review-plan.json"
sed 's/testing-strategy/testing_strategy/' \
  "$WORK/owner-review-plan.json" >"$WORK/invalid-owner-review-plan.json"
python3 - "$WORK/owner-review-plan.json" \
  "$WORK/non-string-owner-review-plan.json" \
  "$WORK/empty-owner-review-plan.json" <<'PY'
import json
from pathlib import Path
import sys

source = json.loads(Path(sys.argv[1]).read_text())
for value, target in ((None, sys.argv[2]), ("", sys.argv[3])):
    plan = json.loads(json.dumps(source))
    plan["self_review"][0]["skill"] = value
    Path(target).write_text(json.dumps(plan, separators=(",", ":")))
PY
mkdir -p "$WORK/linked-owner-real"
printf '%s\n' '# Linked Owner Target' >"$WORK/linked-owner-real/SKILL.md"
ln -s "$WORK/linked-owner-real" "$WORK/linked-owner"
sed 's/testing-strategy/linked-owner/' \
  "$WORK/owner-review-plan.json" >"$WORK/linked-owner-review-plan.json"
sed 's/Preserve the review gate safety contract while adding staged review\./Preserve the review gate safety contract while changing staged review evidence./' \
  "$WORK/review-plan.json" >"$WORK/changed-review-plan.json"
sed 's/The selected stage controls the common review focus\./The selected stage controls a changed completion contract./' \
  "$WORK/review-plan.json" >"$WORK/changed-acceptance-plan.json"
cat >"$WORK/incomplete-plan.json" <<'JSON'
{"intent":"Add stages","acceptance":["Stage is recorded"],"self_review":[],"evidence":[]}
JSON
cat >"$WORK/placeholder-plan.json" <<'JSON'
{
  "intent": "Reject self-review filler before invoking a provider.",
  "acceptance": ["Every self-review conclusion carries concern-specific reasoning."],
  "self_review": [
    {"concern": "correctness", "conclusion": "Verified.", "evidence_refs": ["e1"]},
    {"concern": "safety", "conclusion": "Packet and tool boundaries remain fail closed.", "evidence_refs": ["e1"]},
    {"concern": "failure_paths", "conclusion": "Invalid and inconclusive paths remain terminal.", "evidence_refs": ["e1"]},
    {"concern": "tests_evidence", "conclusion": "A focused regression proves filler is rejected.", "evidence_refs": ["e1"]},
    {"concern": "compatibility", "conclusion": "Existing provider routing remains compatible.", "evidence_refs": ["e1"]}
  ],
  "evidence": [{"id": "e1", "result": "Deterministic placeholder-validation fixture."}]
}
JSON
sed 's/Deterministic fake-wrapper contract fixture\./Verified./' \
  "$WORK/review-plan.json" >"$WORK/placeholder-evidence-plan.json"
sed 's/The candidate preserves current correctness invariants\./No problems found./' \
  "$WORK/review-plan.json" >"$WORK/low-information-self-review-plan.json"
sed 's/Deterministic fake-wrapper contract fixture\./Checks all passed./' \
  "$WORK/review-plan.json" >"$WORK/low-information-evidence-plan.json"
sed 's/Deterministic fake-wrapper contract fixture\./Live token AKIAIOSFODNN7EXAMPLE captured during setup./' \
  "$WORK/review-plan.json" >"$WORK/secret-plan.json"
cat >"$WORK/high-risk-plan.json" <<'JSON'
{
  "intent": "Preserve a shared gate while changing its staged review contract.",
  "acceptance": ["High-risk routing raises review depth and checks bypass paths."],
  "self_review": [
    {"concern": "correctness", "conclusion": "The gate still selects a valid independent result.", "evidence_refs": ["e1"]},
    {"concern": "safety", "conclusion": "Packet, tool, and egress boundaries remain fail closed.", "evidence_refs": ["e1"]},
    {"concern": "failure_paths", "conclusion": "Invalid and inconclusive paths remain terminal.", "evidence_refs": ["e1"]},
    {"concern": "tests_evidence", "conclusion": "Deterministic contract tests cover the risky path.", "evidence_refs": ["e1"]},
    {"concern": "compatibility", "conclusion": "Existing provider routing remains compatible.", "evidence_refs": ["e1"]},
    {"concern": "rollout_rollback", "conclusion": "The local contract change has a direct revert path.", "evidence_refs": ["e1"]},
    {"concern": "observability_operations", "conclusion": "The result exposes depth and risk tags for diagnosis.", "evidence_refs": ["e1"]},
    {"concern": "high_risk_boundary", "conclusion": "Bypass attempts cannot remove controller-required concerns.", "evidence_refs": ["e1"]}
  ],
  "evidence": [{"id": "e1", "result": "Deterministic high-risk gate fixture."}]
}
JSON
large_intent="$(awk 'BEGIN { for (i = 0; i < 3900; i++) printf "i" }')"
large_acceptance="$(awk 'BEGIN { for (i = 0; i < 990; i++) printf "a" }')"
large_conclusion="$(awk 'BEGIN { for (i = 0; i < 1900; i++) printf "c" }')"
large_evidence="$(awk 'BEGIN { for (i = 0; i < 1900; i++) printf "e" }')"
cat >"$WORK/near-limit-plan.json" <<JSON
{
  "intent": "$large_intent",
  "acceptance": [
    "$large_acceptance", "$large_acceptance", "$large_acceptance", "$large_acceptance",
    "$large_acceptance", "$large_acceptance", "$large_acceptance", "$large_acceptance",
    "$large_acceptance", "$large_acceptance", "$large_acceptance", "$large_acceptance",
    "$large_acceptance", "$large_acceptance", "$large_acceptance"
  ],
  "self_review": [
    {"concern": "correctness", "conclusion": "$large_conclusion", "evidence_refs": ["e1"]},
    {"concern": "safety", "conclusion": "$large_conclusion", "evidence_refs": ["e1"]},
    {"concern": "failure_paths", "conclusion": "$large_conclusion", "evidence_refs": ["e1"]},
    {"concern": "tests_evidence", "conclusion": "$large_conclusion", "evidence_refs": ["e1"]},
    {"concern": "compatibility", "conclusion": "$large_conclusion", "evidence_refs": ["e1"]}
  ],
  "evidence": [{"id": "e1", "result": "$large_evidence"}]
}
JSON

reset_case() {
  # Files only: the process-group record is a directory and must survive case resets —
  # a wrapper still running from the previous case would otherwise lose the only handle
  # the suite has on its group.
  find "$WORK/state" -maxdepth 1 -type f -exec rm -f {} +
  # Drop records whose group has no live member. A group id is a recycled number, so a
  # record kept past its group's life can eventually name a stranger's group — and this
  # suite signals groups. Pruning between cases bounds that staleness to a single case,
  # a window in which the OS cannot plausibly have recycled the number, while a record
  # whose wrapper is still running (the leak this all exists for) is kept.
  prune_dead_pgid_records
  printf '%s' "$1" >"$WORK/state/claude_behavior"
  printf '%s' "$2" >"$WORK/state/kimi_behavior"
  printf '%s' "$3" >"$WORK/state/opencode_behavior"
  printf '%s' "${4:-unavailable}" >"$WORK/state/codex_behavior"
}

run_gate_from() {
  entrypoint="$1"
  shift
  REVIEW_GATE_TEST_STATE="$WORK/state" "$entrypoint" \
    --mode review --cwd "$WORK/repo" --diff-file "$WORK/diff.patch" \
    --implementer-family openai --review-plan-file "$WORK/review-plan.json" "$@"
}

run_gate() {
  run_gate_from "$WORK/harness/scripts/review_gate.sh" "$@"
}

run_challenge_gate() {
  REVIEW_GATE_TEST_STATE="$WORK/state" "$WORK/harness/scripts/review_gate.sh" \
    --mode challenge --cwd "$WORK/repo" --diff-file "$WORK/diff.patch" \
    --implementer-family openai --review-plan-file "$WORK/review-plan.json" \
    --challenge-budget 1 --challenge-index 1 "$@"
}

run_completion_gate() {
  REVIEW_GATE_TEST_STATE="$WORK/state" "$WORK/harness/scripts/review_gate.sh" \
    --mode complete --cwd "$WORK/repo" --diff-file "$WORK/diff.patch" \
    --implementer-family openai --review-plan-file "$WORK/review-plan.json" "$@"
}

run_base_gate() {
  REVIEW_GATE_TEST_STATE="$WORK/state" "$WORK/harness/scripts/review_gate.sh" \
    --mode review --cwd "$WORK/repo" --base HEAD --implementer-family openai \
    --review-plan-file "$WORK/review-plan.json" "$@"
}

check() {
  if eval "$2"; then echo "ok   - $1"; else echo "FAIL - $1"; fails=$((fails+1)); fi
}

json_fields() {
  local payload="$1"
  shift
  JSON_PAYLOAD="$payload" python3 - "$@" <<'PY' 2>/dev/null
import json, os, sys
payload = json.loads(os.environ["JSON_PAYLOAD"])
for expected in sys.argv[1:]:
    path, wanted = expected.split("=", 1)
    value = payload
    for part in path.split("."):
        value = value[int(part)] if isinstance(value, list) else value[part]
    assert str(value).lower() == wanted.lower(), (path, value, wanted)
PY
}

json_lacks() {
  local payload="$1" field="$2"
  JSON_PAYLOAD="$payload" python3 - "$field" <<'PY' 2>/dev/null
import json, os, sys
payload = json.loads(os.environ["JSON_PAYLOAD"])
assert sys.argv[1] not in payload, (sys.argv[1], payload.get(sys.argv[1]))
PY
}

# Direct unit coverage for the egress secret-scan tripwire: precision (no false
# positive on ordinary code or placeholders) and recall (catches representative
# credential shapes). Locks in the security-sensitive behavior independently of
# the end-to-end egress tests below.
scan_out="$(REVIEW_GATE_DIR="$DIR" python3 - <<'PY' 2>&1
import os, sys
sys.path.insert(0, os.environ["REVIEW_GATE_DIR"])
from review_gate import scan_egress_secrets as s
cases = [
    (b"def handler():\n    return get_password(user)\n", []),
    (b"-a\n+b\n", []),
    (b'password = "changeme"\n', []),
    (b'token = "${VAULT_TOKEN}"\n', []),
    (b'api_key: "<your-api-key-here>"\n', []),
    (b'+aws_key = "AKIAIOSFODNN7EXAMPLE"\n', ["aws_access_key_id"]),
    (b"-----BEGIN RSA PRIVATE KEY-----\n", ["private_key"]),
    (b"gh_token = ghp_" + b"a" * 36 + b"\n", ["github_token"]),
    (b"pat = github_pat_" + b"a" * 22 + b"\n", ["github_token"]),
    (b"OPENAI_API_KEY=sk-proj-" + b"a" * 24 + b"\n", ["openai_api_key"]),
    (b"legacy = sk-" + b"a" * 24 + b"\n", ["openai_api_key"]),
    (b"slug = sk-" + b"this-is-an-ordinary-config-name\n", []),
    (b'password = "s3cr3t-value-here"\n', ["secret_assignment"]),
    (b'url = "https://user:hunter2@db.' + b'internal/x"\n', ["credentialed_url"]),
]
bad = [(p, want, s(p)) for p, want in cases if s(p) != want]
if bad:
    for entry in bad:
        print("MISMATCH", entry)
    sys.exit(1)
print("scanner_ok")
PY
)"
check "egress secret scanner: precision and recall on representative inputs" \
  '[ "$scan_out" = "scanner_ok" ]'

reset_case passed unavailable unavailable
out="$(run_gate --allow-fallback-egress)"; rc=$?
profile="$(cat "$WORK/state/claude_profile" 2>/dev/null || true)"
check "Claude pass stops before other clients" \
  '[ "$rc" = 0 ] && [ "$(cat "$WORK/state/client_sequence")" = claude ] && json_fields "$profile" owner_selection_source=implementer-declared selected_skills.0.name=code-review && [ "$(printf "%s" "$profile" | python3 -c "import json,sys; print(len(json.load(sys.stdin).get(\"selected_skills\", [])))")" = 1 ] && json_fields "$out" selected_client=claude owner_selection_source=implementer-declared selected_skills.0=code-review fallback_attempt_count=0 completion_gated=true next_action=deep_self_review_before_completion autonomous_review_budget=1 autonomous_review_index=1 autonomous_reviews_remaining=0 autonomous_review_allowed=false human_decision_required=false review_state=reviewed self_review_gate.required=true self_review_gate.required_triggers.0=before_completion_claim self_review_gate.satisfied_triggers.0=before_external_review self_review_gate.blocks.0=completion_claim && [ "$(printf "%s" "$out" | python3 -c "import json,sys; print(len(json.load(sys.stdin).get(\"selected_skills\", [])))")" = 1 ] && json_lacks "$out" delivery && json_lacks "$out" owner_gaps && json_lacks "$out" residual_risks && json_lacks "$out" decision && json_lacks "$out" skill_gap_candidates'

printf '%s\n' "$out" >"$WORK/completion-review.json"
reset_case passed unavailable unavailable
out="$(run_completion_gate --completion-review-result-file "$WORK/completion-review.json")"; rc=$?
check "completion claim requires a separate exact-candidate deep-self-review checkpoint" \
  '[ "$rc" = 0 ] && [ ! -e "$WORK/state/client_sequence" ] && json_fields "$out" mode=complete status=passed completion_gated=false next_action=complete review_state=self_reviewed self_review_gate.required=false self_review_gate.satisfied_triggers.0=before_completion_claim completion_review_result_sha256='"$(shasum -a 256 "$WORK/completion-review.json" | awk '{print $1}')"''

reset_case passed unavailable unavailable
out="$(run_completion_gate --review-plan-file "$WORK/changed-review-plan.json" --completion-review-result-file "$WORK/completion-review.json")"; rc=$?
check "an untracked completion checkpoint rejects changed intent" \
  '[ "$rc" = 2 ] && [ ! -e "$WORK/state/client_sequence" ] && json_fields "$out" reason_code=completion_checkpoint_invalid completion_gated=true'

printf 'diff --git a/x b/x\n--- a/x\n+++ b/x\n@@ -1 +1 @@\n-b\n+c\n' >"$WORK/diff.patch"
reset_case passed unavailable unavailable
out="$(run_completion_gate --completion-review-result-file "$WORK/completion-review.json")"; rc=$?
check "a completion checkpoint rejects a review result for an older candidate" \
  '[ "$rc" = 2 ] && [ ! -e "$WORK/state/client_sequence" ] && json_fields "$out" reason_code=completion_checkpoint_invalid completion_gated=true next_action=run_external_review_for_current_candidate self_review_gate.required=true self_review_gate.required_triggers.0=material_candidate_change self_review_gate.blocks.0=completion_claim'
printf 'diff --git a/x b/x\n--- a/x\n+++ b/x\n@@ -1 +1 @@\n-a\n+b\n' >"$WORK/diff.patch"

reset_case passed unavailable unavailable
out="$(run_gate --review-plan-file "$WORK/owner-review-plan.json" --allow-fallback-egress)"; rc=$?
profile="$(cat "$WORK/state/claude_profile" 2>/dev/null || true)"
check "owner-guided self-review passes installed skill names without copying owner bodies" \
  '[ "$rc" = 0 ] && json_fields "$profile" owner_selection_source=implementer-declared selected_skills.0.name=code-review selected_skills.1.name=testing-strategy self_review.3.skill=testing-strategy skill_delivery=native-installed && json_lacks "$profile" owner_context && ! grep -q "# Testing Strategy" <<<"$profile" && [ "$(cat "$WORK/state/claude_skill_registry_root")" = "$WORK_REAL" ] && [ "$(cat "$WORK/state/claude_review_skills")" = testing-strategy ] && json_fields "$out" owner_selection_source=implementer-declared selected_skills.0=code-review selected_skills.1=testing-strategy reviewed_skills.0=testing-strategy skill_usage_evidence.mode=native-explicit-invocation skill_usage_evidence.observed=false skill_usage_evidence.source=claude-wrapper && [ "$(printf "%s" "$out" | python3 -c "import json,sys; p=json.load(sys.stdin); print(len(p.get(\"selected_skills\", [])), len(p.get(\"reviewed_skills\", [])), len(p.get(\"observed_skill_usage\", [])))")" = "2 1 0" ]'

reset_case missing_binding unavailable unavailable
out="$(run_gate --review-plan-file "$WORK/owner-review-plan.json" --allow-fallback-egress)"; rc=$?
check "owner-aware success without a wrapper binding receipt fails closed" \
  '[ "$rc" = 2 ] && json_fields "$out" reason_code=binding_mismatch next_action=stop_reviewer_lane && [ "$(printf "%s" "$out" | python3 -c "import json,sys; print(len(json.load(sys.stdin).get(\"reviewed_skills\", [])))")" = 0 ]'

printf 'diff --git a/skills/testing-strategy/SKILL.md b/skills/testing-strategy/SKILL.md\n--- a/skills/testing-strategy/SKILL.md\n+++ b/skills/testing-strategy/SKILL.md\n@@ -1 +1 @@\n-old\n+new\n' >"$WORK/diff.patch"
reset_case passed unavailable unavailable
out="$(run_gate --allow-fallback-egress)"; rc=$?
check "a path-derived owner missing from self-review fails before provider execution" \
  '[ "$rc" = 2 ] && [ ! -e "$WORK/state/client_sequence" ] && json_fields "$out" reason_code=self_review_incomplete next_action=deep_self_review'

reset_case passed unavailable unavailable
out="$(run_gate --review-plan-file "$WORK/owner-review-plan.json" --allow-fallback-egress)"; rc=$?
profile="$(cat "$WORK/state/claude_profile" 2>/dev/null || true)"
check "a changed skill path routes its owner into the frozen reviewer profile" \
  '[ "$rc" = 0 ] && json_fields "$profile" owner_selection_source=controller-derived+implementer-declared owner_selection_evidence.0.skill=testing-strategy owner_selection_evidence.0.source=changed-skill-path skill_delivery=native-installed && [ "$(cat "$WORK/state/claude_review_skills")" = testing-strategy ] && json_fields "$out" owner_selection_source=controller-derived+implementer-declared reviewed_skills.0=testing-strategy'

printf 'diff --git a/src/service.py b/src/service.py\n--- a/src/service.py\n+++ b/src/service.py\n@@ -1 +1 @@\n-old\n+new\n' >"$WORK/diff.patch"
reset_case passed unavailable unavailable
out="$(run_gate --review-plan-file "$WORK/python-owner-review-plan.json" --allow-fallback-egress)"; rc=$?
profile="$(cat "$WORK/state/claude_profile" 2>/dev/null || true)"
check "a Python candidate routes the registered Python implementation owner" \
  '[ "$rc" = 0 ] && json_fields "$profile" owner_selection_evidence.0.skill=python-service-dev owner_selection_evidence.0.source=file-type:.py skill_delivery=native-installed && [ "$(cat "$WORK/state/claude_review_skills")" = python-service-dev ] && json_fields "$out" reviewed_skills.0=python-service-dev'

printf 'diff --git a/scripts/review.sh b/scripts/review.sh\n--- a/scripts/review.sh\n+++ b/scripts/review.sh\n@@ -1 +1 @@\n-old\n+new\n' >"$WORK/diff.patch"
reset_case passed unavailable unavailable
out="$(run_gate --review-plan-file "$WORK/shell-owner-review-plan.json" --allow-fallback-egress)"; rc=$?
profile="$(cat "$WORK/state/claude_profile" 2>/dev/null || true)"
check "a shell candidate routes the terminal CLI owner" \
  '[ "$rc" = 0 ] && json_fields "$profile" owner_selection_evidence.0.skill=terminal-cli-dev owner_selection_evidence.0.source=file-type:.sh skill_delivery=native-installed && [ "$(cat "$WORK/state/claude_review_skills")" = terminal-cli-dev ] && json_fields "$out" reviewed_skills.0=terminal-cli-dev'

printf 'diff --git a/cmd/service.go b/cmd/service.go\n--- a/cmd/service.go\n+++ b/cmd/service.go\n@@ -1 +1 @@\n-old\n+new\ndiff --git a/web/view.ts b/web/view.ts\n--- a/web/view.ts\n+++ b/web/view.ts\n@@ -1 +1 @@\n-old\n+new\ndiff --git a/lib/screen.dart b/lib/screen.dart\n--- a/lib/screen.dart\n+++ b/lib/screen.dart\n@@ -1 +1 @@\n-old\n+new\n' >"$WORK/diff.patch"
reset_case passed unavailable unavailable
out="$(run_gate --review-plan-file "$WORK/language-owner-review-plan.json" --allow-fallback-egress)"; rc=$?
profile="$(cat "$WORK/state/claude_profile" 2>/dev/null || true)"
check "Go, web, and Dart candidates route all registered implementation owners" \
  '[ "$rc" = 0 ] && json_fields "$profile" owner_selection_evidence.0.skill=app-cross-platform-dev owner_selection_evidence.1.skill=go-microservice-dev owner_selection_evidence.2.skill=web-react-dev && [ "$(cat "$WORK/state/claude_review_skills")" = "app-cross-platform-dev go-microservice-dev web-react-dev" ] && json_fields "$out" reviewed_skills.0=app-cross-platform-dev reviewed_skills.1=go-microservice-dev reviewed_skills.2=web-react-dev'

printf 'diff --git a/src/service.py b/src/service.py\n--- a/src/service.py\n+++ b/src/service.py\n@@ -1 +1 @@\n-old\n+new\n' >"$WORK/diff.patch"
reset_case quota passed unavailable
out="$(run_gate --review-plan-file "$WORK/python-owner-review-plan.json" --allow-fallback-egress)"; rc=$?
check "fallback reviewers receive the same native owner-skill binding" \
  '[ "$rc" = 0 ] && [ "$(cat "$WORK/state/claude_review_skills")" = python-service-dev ] && [ "$(cat "$WORK/state/kimi_review_skills")" = python-service-dev ] && [ "$(cat "$WORK/state/claude_skill_registry_root")" = "$(cat "$WORK/state/kimi_skill_registry_root")" ] && json_fields "$out" selected_client=kimi reviewed_skills.0=python-service-dev'
printf 'diff --git a/x b/x\n--- a/x\n+++ b/x\n@@ -1 +1 @@\n-a\n+b\n' >"$WORK/diff.patch"

mkdir -p "$WORK/alternate-registry"
ln -s "$WORK/harness" "$WORK/alternate-registry/linked-harness"
reset_case passed unavailable unavailable
out="$(run_gate_from "$WORK/alternate-registry/linked-harness/scripts/review_gate.sh" \
  --review-plan-file "$WORK/owner-review-plan.json" --allow-fallback-egress)"; rc=$?
profile="$(cat "$WORK/state/claude_profile" 2>/dev/null || true)"
check "a symlinked baseline resolves owners from the canonical source registry" \
  '[ "$rc" = 0 ] && json_fields "$profile" selected_skills.0.name=code-review selected_skills.1.name=testing-strategy && json_fields "$out" selected_skills.0=code-review selected_skills.1=testing-strategy'

reset_case passed unavailable unavailable
out="$(run_gate --review-plan-file "$WORK/missing-owner-review-plan.json")"; rc=$?
check "an explicit owner outside the complete sibling registry fails before provider execution" \
  '[ "$rc" = 2 ] && [ ! -e "$WORK/state/client_sequence" ] && json_fields "$out" reason_code=self_review_incomplete fallback_eligible=false next_action=deep_self_review self_review_gate.required=true self_review_gate.required_triggers.0=before_external_review'

reset_case passed unavailable unavailable
out="$(run_gate --review-plan-file "$WORK/missing-entrypoint-owner-review-plan.json")"; rc=$?
check "an explicit owner directory without SKILL.md is incomplete and terminal" \
  '[ "$rc" = 2 ] && [ ! -e "$WORK/state/client_sequence" ] && json_fields "$out" reason_code=self_review_incomplete fallback_eligible=false next_action=deep_self_review self_review_gate.required=true'

reset_case passed unavailable unavailable
out="$(run_gate --review-plan-file "$WORK/file-owner-review-plan.json")"; rc=$?
check "a regular file cannot occupy an explicit owner package name" \
  '[ "$rc" = 2 ] && [ ! -e "$WORK/state/client_sequence" ] && json_fields "$out" reason_code=local_tool_failure fallback_eligible=false next_action=stop_reviewer_lane'

reset_case passed unavailable unavailable
out="$(run_gate --review-plan-file "$WORK/invalid-owner-review-plan.json")"; rc=$?
check "an out-of-contract owner name fails before provider execution" \
  '[ "$rc" = 2 ] && [ ! -e "$WORK/state/client_sequence" ] && json_fields "$out" reason_code=self_review_incomplete fallback_eligible=false next_action=deep_self_review self_review_gate.required=true'

for malformed_plan in non-string-owner-review-plan empty-owner-review-plan; do
  reset_case passed unavailable unavailable
  out="$(run_gate --review-plan-file "$WORK/$malformed_plan.json")"; rc=$?
  check "a malformed owner value is incomplete self-review and remains terminal ($malformed_plan)" \
    '[ "$rc" = 2 ] && [ ! -e "$WORK/state/client_sequence" ] && json_fields "$out" reason_code=self_review_incomplete fallback_eligible=false next_action=deep_self_review self_review_gate.required=true'
done

owner_lstat_classification="$(python3 - "$DIR/review_gate.py" <<'PY'
import errno
import importlib.util
from pathlib import Path
import sys
import tempfile
from unittest.mock import patch

spec = importlib.util.spec_from_file_location("review_gate_under_test", sys.argv[1])
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)
results = []
for error_number in (errno.ENOENT, errno.EACCES, errno.ENOTDIR):
    with patch.object(Path, "lstat", side_effect=OSError(error_number, "test")):
        try:
            module._hash_skill_package(Path("/registry/testing-strategy"), "testing-strategy")
        except module.GateError as exc:
            results.append(exc.reason_code)
with tempfile.TemporaryDirectory() as directory:
    skill_root = Path(directory) / "testing-strategy"
    skill_root.mkdir()
    (skill_root / "SKILL.md").write_text("# Testing Strategy\n")
    (skill_root / "references").mkdir()
    original_lstat = Path.lstat
    for target in (skill_root / "SKILL.md", skill_root / "references"):
        def selective_lstat(self, target=target):
            if self == target:
                raise OSError(errno.EACCES, "test")
            return original_lstat(self)

        with patch.object(Path, "lstat", selective_lstat):
            try:
                module._hash_skill_package(skill_root, "testing-strategy")
            except module.GateError as exc:
                results.append(exc.reason_code)
print(" ".join(results))
PY
)"
check "owner root inspection distinguishes absence from local access failure" \
  '[ "$owner_lstat_classification" = "self_review_incomplete local_tool_failure local_tool_failure local_tool_failure local_tool_failure" ]'

reset_case passed unavailable unavailable
out="$(run_gate --review-plan-file "$WORK/linked-owner-review-plan.json")"; rc=$?
check "a linked owner package is a terminal local registry-integrity failure" \
  '[ "$rc" = 2 ] && [ ! -e "$WORK/state/client_sequence" ] && json_fields "$out" reason_code=local_tool_failure fallback_eligible=false next_action=stop_reviewer_lane'

printf '%s\n' '# Linked owner reference target' >"$WORK/owner-reference-target.md"
ln -s "$WORK/owner-reference-target.md" \
  "$WORK/testing-strategy/references/linked.md"
reset_case passed unavailable unavailable
out="$(run_gate --review-plan-file "$WORK/owner-review-plan.json")"; rc=$?
check "a linked Markdown reference in an explicit owner package is terminal" \
  '[ "$rc" = 2 ] && [ ! -e "$WORK/state/client_sequence" ] && json_fields "$out" reason_code=local_tool_failure fallback_eligible=false next_action=stop_reviewer_lane'
unlink "$WORK/testing-strategy/references/linked.md"

mv "$WORK/testing-strategy/references" "$WORK/testing-strategy/references-real"
ln -s "$WORK/testing-strategy/references-real" \
  "$WORK/testing-strategy/references"
reset_case passed unavailable unavailable
out="$(run_gate --review-plan-file "$WORK/owner-review-plan.json")"; rc=$?
check "a linked references root in an explicit owner package is terminal" \
  '[ "$rc" = 2 ] && [ ! -e "$WORK/state/client_sequence" ] && json_fields "$out" reason_code=local_tool_failure fallback_eligible=false next_action=stop_reviewer_lane'
unlink "$WORK/testing-strategy/references"
mv "$WORK/testing-strategy/references-real" "$WORK/testing-strategy/references"

mv "$WORK/testing-strategy/SKILL.md" "$WORK/testing-strategy/SKILL.md.real"
mkdir "$WORK/testing-strategy/SKILL.md"
reset_case passed unavailable unavailable
out="$(run_gate --review-plan-file "$WORK/owner-review-plan.json")"; rc=$?
check "a non-regular entrypoint in an explicit owner package is terminal" \
  '[ "$rc" = 2 ] && [ ! -e "$WORK/state/client_sequence" ] && json_fields "$out" reason_code=local_tool_failure fallback_eligible=false next_action=stop_reviewer_lane'
rmdir "$WORK/testing-strategy/SKILL.md"
mv "$WORK/testing-strategy/SKILL.md.real" "$WORK/testing-strategy/SKILL.md"

python3 - "$WORK/harness/scripts/oversized-runtime.py" <<'PY'
import os
import sys

path = sys.argv[1]
open(path, "wb").close()
os.truncate(path, 1_048_577)
PY
reset_case passed unavailable unavailable
out="$(run_gate)"; rc=$?
check "an oversized controller-runtime file fails before provider execution" \
  '[ "$rc" = 2 ] && [ ! -e "$WORK/state/client_sequence" ] && json_fields "$out" reason_code=local_tool_failure'
rm -f "$WORK/harness/scripts/oversized-runtime.py"

mkdir -p "$WORK/harness/scripts/runtime-aggregate"
python3 - "$WORK/harness/scripts/runtime-aggregate" <<'PY'
import os
import sys
from pathlib import Path

root = Path(sys.argv[1])
for index in range(9):
    path = root / f"part-{index}.py"
    path.touch()
    os.truncate(path, 1_000_000)
PY
reset_case passed unavailable unavailable
out="$(run_gate)"; rc=$?
check "an oversized controller-runtime aggregate fails before provider execution" \
  '[ "$rc" = 2 ] && [ ! -e "$WORK/state/client_sequence" ] && json_fields "$out" reason_code=local_tool_failure'
rm -rf "$WORK/harness/scripts/runtime-aggregate"

reset_case passed unavailable unavailable
out="$(REVIEW_GATE_TEST_STATE="$WORK/state" "$WORK/harness/scripts/review_gate.sh" \
  --mode review --cwd "$WORK/repo" --diff-file "$WORK/large-diff.patch" \
  --implementer-family openai --review-plan-file "$WORK/review-plan.json")"; rc=$?
check "a bounded 180 KB candidate remains reviewable as one frozen packet" \
  '[ "$rc" = 0 ] && [ "$(wc -c <"$WORK/state/claude_packet" | tr -d "[:space:]")" = 180000 ] && json_fields "$out" selected_client=claude'

reset_case passed unavailable unavailable
out="$(REVIEW_GATE_TEST_STATE="$WORK/state" "$WORK/harness/scripts/review_gate.sh" \
  --mode review --cwd "$WORK/repo" --diff-file "$WORK/nul-diff.patch" \
  --implementer-family openai --review-plan-file "$WORK/review-plan.json")"; rc=$?
check "a NUL-bearing candidate fails before provider execution" \
  '[ "$rc" = 2 ] && [ ! -e "$WORK/state/client_sequence" ] && json_fields "$out" reason_code=invalid_input completion_gated=true'

reset_case passed unavailable unavailable
out="$(REVIEW_GATE_TEST_STATE="$WORK/state" "$WORK/harness/scripts/review_gate.sh" \
  --mode review --cwd "$WORK/repo" --diff-file "$WORK/diff.patch" \
  --implementer-family openai --review-plan-file "$WORK/near-limit-plan.json")"; rc=$?
check "a valid plan near the documented 32 KB input limit can render its profile" \
  '[ "$(wc -c <"$WORK/near-limit-plan.json")" -le 32000 ] && [ "$rc" = 0 ] && [ "$(cat "$WORK/state/client_sequence")" = claude ]'

ln -s "$WORK/review-plan.json" "$WORK/symlink-review-plan.json"
reset_case passed unavailable unavailable
out="$(run_gate --review-plan-file "$WORK/symlink-review-plan.json")"; rc=$?
check "a symlinked review plan fails before provider execution" \
  '[ "$rc" = 2 ] && [ ! -e "$WORK/state/client_sequence" ] && json_fields "$out" reason_code=invalid_input'
unlink "$WORK/symlink-review-plan.json"

cp "$WORK/review-plan.json" "$WORK/hardlink-review-plan.json"
ln "$WORK/hardlink-review-plan.json" "$WORK/hardlink-review-plan-alias.json"
reset_case passed unavailable unavailable
out="$(run_gate --review-plan-file "$WORK/hardlink-review-plan.json")"; rc=$?
check "a hardlinked review plan fails before provider execution" \
  '[ "$rc" = 2 ] && [ ! -e "$WORK/state/client_sequence" ] && json_fields "$out" reason_code=invalid_input'
unlink "$WORK/hardlink-review-plan-alias.json"
unlink "$WORK/hardlink-review-plan.json"

mkfifo "$WORK/fifo-review-plan.json"
reset_case passed unavailable unavailable
fifo_probe="$(python3 - \
  "$WORK/harness/scripts/review_gate.py" \
  "$WORK/repo" \
  "$WORK/diff.patch" \
  "$WORK/fifo-review-plan.json" \
  "$WORK/state" <<'PY'
import json
import os
import subprocess
import sys

gate, cwd, diff, plan, state = sys.argv[1:]
environment = os.environ.copy()
environment["REVIEW_GATE_TEST_STATE"] = state
try:
    completed = subprocess.run(
        [
            sys.executable,
            gate,
            "--mode", "review",
            "--cwd", cwd,
            "--diff-file", diff,
            "--implementer-family", "openai",
            "--review-plan-file", plan,
        ],
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=1,
        env=environment,
        check=False,
    )
except subprocess.TimeoutExpired as exc:
    raise AssertionError("FIFO review-plan open blocked") from exc
assert completed.returncode == 2, (completed.returncode, completed.stdout, completed.stderr)
payload = json.loads(completed.stdout)
assert payload["reason_code"] == "invalid_input", payload
assert "Traceback" not in completed.stderr, completed.stderr
print("ok")
PY
)"
fifo_probe_rc=$?
check "a FIFO review plan fails quickly before provider execution" \
  '[ "$fifo_probe_rc" = 0 ] && [ "$fifo_probe" = ok ] && [ ! -e "$WORK/state/client_sequence" ]'

python3 - "$WORK/review-plan.json" "$WORK/surrogate-review-plan.json" <<'PY'
import json
import sys
from pathlib import Path

source, target = map(Path, sys.argv[1:])
plan = json.loads(source.read_text(encoding="utf-8"))
plan["intent"] = "Reject this escaped lone surrogate: \ud800"
target.write_text(json.dumps(plan, ensure_ascii=True), encoding="utf-8")
PY
reset_case passed unavailable unavailable
out="$(run_gate --review-plan-file "$WORK/surrogate-review-plan.json" 2>&1)"; rc=$?
check "an escaped lone surrogate is a stable rc2 before provider execution" \
  '[ "$rc" = 2 ] && [ ! -e "$WORK/state/client_sequence" ] && json_fields "$out" reason_code=invalid_input completion_gated=true'

python3 - "$WORK/oversized-review-plan.json" <<'PY'
import sys
from pathlib import Path

Path(sys.argv[1]).write_bytes(b"x" * 32001)
PY
reset_case passed unavailable unavailable
out="$(run_gate --review-plan-file "$WORK/oversized-review-plan.json")"; rc=$?
check "an oversized review plan fails before provider execution" \
  '[ "$rc" = 2 ] && [ ! -e "$WORK/state/client_sequence" ] && json_fields "$out" reason_code=invalid_input'

# The path checks for diff/prior/completion inputs must bind the bytes to one
# already-open descriptor.  Simulate the old check-then-open race by replacing a
# regular path with a symlink immediately after Path.is_symlink() reports clean.
# A secure open-once implementation never calls that pathname predicate, so it
# either reads the original inode or rejects the input; it can never consume the
# alternate bytes behind the replacement link.
file_input_race_probe="$(PYTHONPATH="$WORK/harness/scripts" python3 - "$WORK" <<'PY' 2>&1
import contextlib
import ast
import hashlib
import json
import os
from pathlib import Path
from types import SimpleNamespace
import sys
import time

import review_gate


@contextlib.contextmanager
def replace_after_symlink_check(source: Path, alternate: Path):
    original_is_symlink = Path.is_symlink
    backup = source.with_name(source.name + ".before-link-swap")
    swapped = False

    def injecting_is_symlink(path: Path) -> bool:
        nonlocal swapped
        result = original_is_symlink(path)
        if path == source and not swapped:
            source.rename(backup)
            source.symlink_to(alternate)
            swapped = True
        return result

    Path.is_symlink = injecting_is_symlink
    try:
        yield
    finally:
        Path.is_symlink = original_is_symlink
        if swapped:
            source.unlink()
            backup.rename(source)


@contextlib.contextmanager
def replace_after_first_fstat(source: Path, alternate: Path):
    """Replace the pathname after the reader has already opened its inode."""

    original_fstat = os.fstat
    original_inode = source.stat().st_ino
    backup = source.with_name(source.name + ".after-open-link-swap")
    swapped = False

    def injecting_fstat(fd: int):
        nonlocal swapped
        metadata = original_fstat(fd)
        if metadata.st_ino == original_inode and not swapped:
            source.rename(backup)
            source.symlink_to(alternate)
            swapped = True
        return metadata

    os.fstat = injecting_fstat
    try:
        yield
    finally:
        os.fstat = original_fstat
        if swapped:
            source.unlink()
            backup.rename(source)


root = Path(sys.argv[1]) / "file-input-race"
root.mkdir()

original_diff = (
    b"diff --git a/safe b/safe\n--- a/safe\n+++ b/safe\n"
    b"@@ -1 +1 @@\n-old\n+safe\n"
)
alternate_diff = (
    b"diff --git a/other b/other\n--- a/other\n+++ b/other\n"
    b"@@ -1 +1 @@\n-old\n+alternate\n"
)
diff_source = root / "candidate.patch"
diff_alternate = root / "alternate.patch"
diff_source.write_bytes(original_diff)
diff_alternate.write_bytes(alternate_diff)
with replace_after_symlink_check(diff_source, diff_alternate):
    packet_path, digest, _, _ = review_gate.freeze_packet(
        SimpleNamespace(
            cwd=str(root), diff_file=str(diff_source), base=None, paths=[]
        ),
        time.monotonic() + 5,
    )
try:
    assert packet_path.read_bytes() == original_diff
    assert digest == hashlib.sha256(original_diff).hexdigest()
finally:
    packet_path.unlink()

# Both --prior-review-result-file and --completion-review-result-file consume
# this loader.  Exercise two independent path replacements so neither call site
# can regress to check-then-open behavior under a later refactor.
for label in ("prior", "completion"):
    source = root / f"{label}.json"
    alternate = root / f"{label}-alternate.json"
    original_bytes = json.dumps({"source": label}).encode()
    alternate.write_text(json.dumps({"source": "alternate"}), encoding="utf-8")
    source.write_bytes(original_bytes)
    with replace_after_symlink_check(source, alternate):
        payload, digest = review_gate._load_prior_review_result(str(source), 1)
    assert payload == {"source": label}
    assert digest == hashlib.sha256(original_bytes).hexdigest()

# Opening once prevents following an attacker-selected replacement, but the
# gate also needs to reject that the pathname stopped naming the opened inode.
# Otherwise a successful result can be attributed to bytes that are no longer
# the candidate at the point the freeze returns.
swap_source = root / "opened-then-swapped.patch"
swap_alternate = root / "opened-then-swapped-alternate.patch"
swap_source.write_bytes(original_diff)
swap_alternate.write_bytes(alternate_diff)
with replace_after_first_fstat(swap_source, swap_alternate):
    try:
        review_gate.freeze_packet(
            SimpleNamespace(
                cwd=str(root), diff_file=str(swap_source), base=None, paths=[]
            ),
            time.monotonic() + 5,
        )
    except review_gate.GateError as exc:
        assert "changed" in exc.reason, exc.reason
    else:
        raise AssertionError("a pathname replaced after open was accepted")

# Frozen packet/profile verification and owner/controller hashing used to
# reopen by pathname as well. Keep a structural assertion beside the live race
# probes so a new Path.read_bytes() call cannot silently recreate that class.
tree = ast.parse(Path(review_gate.__file__).read_text(encoding="utf-8"))
path_reads = [
    node
    for node in ast.walk(tree)
    if isinstance(node, ast.Call)
    and isinstance(node.func, ast.Attribute)
    and node.func.attr in {"read_bytes", "read_text"}
]
assert not path_reads, [(node.func.attr, node.lineno) for node in path_reads]

# Resource bounds are checked from fstat before reading. A sparse oversized
# owner file must fail closed instead of allocating its declared size, and an
# individually valid set must still respect the package aggregate ceiling.
oversized_skill = root / "oversized-skill"
oversized_skill.mkdir()
(oversized_skill / "SKILL.md").touch()
os.truncate(oversized_skill / "SKILL.md", 1_048_577)
try:
    review_gate._hash_skill_package(oversized_skill, "oversized-skill")
except review_gate.GateError as exc:
    assert exc.reason_code == "local_tool_failure", exc.reason_code
else:
    raise AssertionError("an oversized selected-skill file was hashed")

aggregate_skill = root / "aggregate-skill"
(aggregate_skill / "references").mkdir(parents=True)
(aggregate_skill / "SKILL.md").write_text("# aggregate\n", encoding="utf-8")
for index in range(9):
    part = aggregate_skill / "references" / f"part-{index}.md"
    part.touch()
    os.truncate(part, 1_000_000)
try:
    review_gate._hash_skill_package(aggregate_skill, "aggregate-skill")
except review_gate.GateError as exc:
    assert exc.reason_code == "local_tool_failure", exc.reason_code
else:
    raise AssertionError("an oversized selected-skill package was hashed")

print("open_once_file_inputs_ok")
PY
)"
file_input_race_rc=$?
check "diff, prior, and completion inputs are read once from a bounded opened descriptor" \
  '[ "$file_input_race_rc" = 0 ] && [ "$file_input_race_probe" = open_once_file_inputs_ok ]'

reset_case missing_coverage passed unavailable
out="$(run_gate --diff-file "$WORK/secret-diff.patch")"; rc=$?
check "missing coverage cannot widen egress for a secret-bearing diff without approval" \
  '[ "$rc" = 2 ] && [ "$(cat "$WORK/state/client_sequence")" = claude ] && [ ! -e "$WORK/state/kimi_profile_hash" ] && json_fields "$out" reason_code=egress_denied egress.secret_scan.0=aws_access_key_id'

reset_case missing_coverage passed unavailable
out="$(run_gate --allow-fallback-egress)"; rc=$?
check "a clean reply without per-concern conclusions cannot satisfy the gate" \
  '[ "$rc" = 0 ] && [ "$(tr "\n" " " < "$WORK/state/client_sequence")" = "claude kimi " ] && json_fields "$out" selected_client=kimi skipped_clients.0.reason_code=invalid_model_output'

# The wire, not its ends: builds_synthetic_slot and normalize_concern_results are
# each asserted directly, but only a run through the gate proves the flag is
# returned by freeze_review_profile and forwarded by main. Drop the forwarding and
# the challenge case below stops accepting.
#
# The review case does NOT cover the opposite mistake. Every review profile has
# several concerns, so a flag forwarded unconditionally would still be refused for
# failing the single-slot count rather than the flag — no end-to-end review case
# can distinguish the two. That direction is covered directly instead, by
# builds_synthetic_slot returning False for non-challenge modes and by
# normalize_concern_results refusing a renamed result when the flag is absent.
# What the review case does prove is that a renamed id is not accepted there.
reset_case renamed_concern passed unavailable
out="$(run_challenge_gate --focus "the release path under cancellation")"; rc=$?
check "challenge accepts a renamed concern id through the whole gate" \
  '[ "$rc" = 0 ] && json_fields "$out" selected_client=claude status=passed reviewed_concerns.0=challenge_focus attempts.0.concern_results.0.concern=a_focus_shaped_slug'

reset_case renamed_concern passed unavailable
out="$(run_gate --allow-fallback-egress)"; rc=$?
check "review refuses the same renamed concern id" \
  '[ "$rc" = 2 ] && json_fields "$out" status=inconclusive attempts.0.status=inconclusive'

# What the id bound does and does not do. It decides what may be ACCEPTED: an
# oversized id cannot become a recorded conclusion. It does not keep the raw
# string out of the attempt record, because record_attempt runs before
# normalize_concern_results and copies the payload verbatim — an earlier comment
# here claimed the opposite ordering and a review round caught it. That is the
# design, not a leak to plug: attempt records are evidence of what a reviewer
# actually returned, and every field in them is unbounded the same way, so
# truncating one would forge the evidence while fixing nothing. Both halves are
# pinned so neither can be quietly changed into the other.
reset_case oversized_concern_id passed unavailable
out="$(run_challenge_gate --focus "the release path under cancellation")"; rc=$?
check "an oversized concern id is refused while the raw reply stays readable" \
  '[ "$rc" = 2 ] && json_fields "$out" status=inconclusive reason_code=invalid_model_output && [ "$(printf %s "$out" | python3 -c "import json,sys; print(len(json.load(sys.stdin)[\"attempts\"][0][\"concern_results\"][0][\"concern\"]))")" = 600 ]'

reset_case partial_coverage passed unavailable
out="$(run_gate --allow-fallback-egress)"; rc=$?
check "partial concern conclusions are terminal and cannot be laundered by fallback" \
  '[ "$rc" = 2 ] && [ "$(cat "$WORK/state/client_sequence")" = claude ] && json_fields "$out" reason_code=invalid_model_output attempts.0.concern_evidence=true'

reset_case extra_coverage passed unavailable
out="$(run_gate --allow-fallback-egress)"; rc=$?
check "extra concern conclusions are terminal and cannot expand controller scope" \
  '[ "$rc" = 2 ] && [ "$(cat "$WORK/state/client_sequence")" = claude ] && json_fields "$out" reason_code=invalid_model_output attempts.0.concern_evidence=true'

reset_case placeholder_coverage passed unavailable
out="$(run_gate --allow-fallback-egress)"; rc=$?
check "complete but placeholder concern conclusions cannot false-green" \
  '[ "$rc" = 2 ] && [ "$(cat "$WORK/state/client_sequence")" = claude ] && json_fields "$out" reason_code=invalid_model_output attempts.0.concern_evidence=true'

reset_case findings unavailable unavailable
out="$(run_gate --allow-fallback-egress)"; rc=$?
check "Claude findings remain findings" \
  '[ "$rc" = 0 ] && json_fields "$out" status=findings selected_client=claude next_action=triage_findings_and_continue_independent_work autonomous_review_budget=1 autonomous_review_index=1 autonomous_review_allowed=false human_decision_required=true review_state=post_review_budget findings_require_implementer_self_review=true self_review_gate.required=true self_review_gate.required_triggers.0=findings_returned self_review_gate.required_triggers.1=post_review_budget_checkpoint self_review_gate.satisfied_triggers.0=before_external_review self_review_gate.blocks.0=external_review self_review_gate.blocks.1=completion_claim self_review_gate.allowed_next_actions.0=deep_self_review self_review_gate.allowed_next_actions.1=continue_implementation self_review_gate.allowed_next_actions.2=continue_independent_work'

reset_case quota passed unavailable
out="$(run_gate --allow-fallback-egress)"; rc=$?
check "candidate-local Claude failure uses Kimi next" \
  '[ "$rc" = 0 ] && [ "$(tr "\n" " " < "$WORK/state/client_sequence")" = "claude kimi " ] && json_fields "$out" selected_client=kimi fallback_attempt_count=1'

reset_case quota findings unavailable
out="$(run_gate --allow-fallback-egress)"; rc=$?
check "selected fallback findings are promoted to the stable result contract" \
  '[ "$rc" = 0 ] && json_fields "$out" status=findings selected_client=kimi selected_attempt_index=1 findings.0.severity=P1 findings.0.file=fallback.py primary.status=inconclusive fallbacks.0.status=findings'

reset_case quota quota passed
out="$(run_gate --allow-fallback-egress)"; rc=$?
check "candidate-local Kimi failure continues to OpenCode" \
  '[ "$rc" = 0 ] && [ "$(tr "\n" " " < "$WORK/state/client_sequence")" = "claude kimi opencode " ] && json_fields "$out" selected_client=opencode fallback_attempt_count=2'
claude_hash="$(cat "$WORK/state/claude_hash")"
check "all attempted clients receive the same frozen packet" \
  '[ "$claude_hash" = "$(cat "$WORK/state/kimi_hash")" ] && [ "$claude_hash" = "$(cat "$WORK/state/opencode_hash")" ] && json_fields "$out" packet_sha256="$claude_hash"'
claude_profile_hash="$(cat "$WORK/state/claude_profile_hash")"
check "all attempted clients receive the same staged review profile" \
  '[ "$claude_profile_hash" = "$(cat "$WORK/state/kimi_profile_hash")" ] && [ "$claude_profile_hash" = "$(cat "$WORK/state/opencode_profile_hash")" ] && json_fields "$out" review_profile_sha256="$claude_profile_hash" stage=build review_depth=build challenge_budget=0 reviewed_concerns.0=correctness'

reset_case quota quota native_timeout passed
out="$(run_gate --allow-fallback-egress)"; rc=$?
check "native owner-skill timeout receipt remains fail-closed and cascade-eligible through the gate" \
  '[ "$rc" = 2 ] && [ "$(tr "\n" " " < "$WORK/state/client_sequence")" = "claude kimi opencode " ] && json_fields "$out" status=inconclusive reason_code=timeout attempts.2.status=inconclusive attempts.2.reason=review_native_skill_stream_timeout attempts.2.reason_code=timeout attempts.2.cascade_eligible=true attempts.2.timeout_diagnostic.native_owner_skills_requested=true attempts.2.diagnostic_artifacts.retained=true'

# A reviewer-local input ceiling is a client capability failure, not a candidate
# defect. It must cascade; dropping capability_missing from the allowed set
# would turn a routine transport limit into a lane-fatal result.
reset_case quota oversize_inline passed
out="$(run_gate --allow-fallback-egress)"; rc=$?
check "a client-local input ceiling cascades instead of stopping the lane" \
  '[ "$rc" = 0 ] && [ "$(tr "\n" " " < "$WORK/state/client_sequence")" = "claude kimi opencode " ] && json_fields "$out" selected_client=opencode attempts.1.reason_code=capability_missing'

reset_case quota concern_cascade passed
out="$(run_gate --allow-fallback-egress)"; rc=$?
check "gate never cascades past explicit concern evidence" \
  '[ "$rc" = 2 ] && [ "$(tr "\n" " " < "$WORK/state/client_sequence")" = "claude kimi " ] && json_fields "$out" reason_code=invalid_model_output attempts.1.concern_evidence=true'

reset_case quota_mutate passed passed
out="$(run_gate --allow-fallback-egress)"; rc=$?
check "packet mutation fails before another client" \
  '[ "$rc" = 2 ] && [ "$(cat "$WORK/state/client_sequence")" = claude ] && json_fields "$out" reason_code=binding_mismatch client_order.0=claude attempts.0.client=claude attempts.0.reason_code=binding_mismatch'

reset_case quota boundary passed
out="$(run_gate --allow-fallback-egress)"; rc=$?
check "tool-boundary failure is terminal" \
  '[ "$rc" = 2 ] && [ "$(tr "\n" " " < "$WORK/state/client_sequence")" = "claude kimi " ] && json_fields "$out" reason_code=tool_boundary_violation'

reset_case quota unavailable mismatch
out="$(run_gate --allow-fallback-egress)"; rc=$?
check "mode attribution mismatch is terminal" \
  '[ "$rc" = 2 ] && [ "$(tr "\n" " " < "$WORK/state/client_sequence")" = "claude kimi opencode " ] && json_fields "$out" reason_code=binding_mismatch'

reset_case quota passed passed
out="$(run_gate --diff-file "$WORK/secret-diff.patch")"; rc=$?
check "secret-bearing non-Claude egress is denied unless approved" \
  '[ "$rc" = 2 ] && [ "$(cat "$WORK/state/client_sequence")" = claude ] && json_fields "$out" reason_code=egress_denied egress.allowed=false egress.secret_scan.0=aws_access_key_id'

reset_case quota passed passed
out="$(run_gate)"; rc=$?
check "a clean (secret-free) diff egresses to a non-Claude reviewer without the approval flag" \
  '[ "$rc" = 0 ] && [ "$(tr "\n" " " < "$WORK/state/client_sequence")" = "claude kimi " ] && json_fields "$out" selected_client=kimi egress.allowed=true egress.approval_flag=false'

reset_case quota passed passed
out="$(run_gate --review-plan-file "$WORK/secret-plan.json")"; rc=$?
check "a secret in the review plan (which egresses in the profile) blocks non-Claude egress without approval" \
  '[ "$rc" = 2 ] && [ "$(cat "$WORK/state/client_sequence")" = claude ] && json_fields "$out" reason_code=egress_denied egress.secret_scan.0=aws_access_key_id'

reset_case quota passed passed
out="$(run_gate --diff-file "$WORK/secret-diff.patch" --allow-fallback-egress)"; rc=$?
check "a secret-bearing diff egresses when the approval flag is passed" \
  '[ "$rc" = 0 ] && [ "$(tr "\n" " " < "$WORK/state/client_sequence")" = "claude kimi " ] && json_fields "$out" selected_client=kimi egress.allowed=true egress.approval_flag=true egress.secret_scan.0=aws_access_key_id'

reset_case passed unavailable unavailable
out="$(REVIEW_GATE_TEST_STATE="$WORK/state" "$WORK/harness/scripts/review_gate.sh" \
  --mode review --cwd "$WORK/repo" --diff-file "$WORK/diff.patch" \
  --implementer-family openai)"; rc=$?
check "review runs without a --review-plan-file and marks the plan derived-default" \
  '[ "$rc" = 0 ] && [ "$(cat "$WORK/state/client_sequence")" = claude ] && json_fields "$out" review_plan_source=derived-default'

reset_case passed unavailable unavailable
out="$(run_gate --allow-fallback-egress)"; rc=$?
check "a supplied review plan is marked implementer-supplied" \
  '[ "$rc" = 0 ] && json_fields "$out" review_plan_source=implementer-supplied'

out="$(REVIEW_GATE_TEST_STATE="$WORK/state" "$WORK/harness/scripts/review_gate.sh" \
  --mode complete --cwd "$WORK/repo" --diff-file "$WORK/diff.patch" \
  --implementer-family openai --completion-review-result-file "$WORK/completion-review.json")"; rc=$?
check "complete mode still requires an explicit --review-plan-file" \
  '[ "$rc" = 2 ] && json_fields "$out" reason_code=completion_checkpoint_invalid'

reset_case auth passed passed
out="$(run_gate --allow-fallback-egress)"; rc=$?
check "Claude auth-path failure requests host retry first" \
  '[ "$rc" = 2 ] && [ "$(cat "$WORK/state/client_sequence")" = claude ] && json_fields "$out" next_action=host_retry'

reset_case quota auth passed
out="$(run_gate --allow-fallback-egress)"; rc=$?
check "Kimi auth-path failure requests the same bounded host retry" \
  '[ "$rc" = 2 ] && [ "$(tr "\n" " " < "$WORK/state/client_sequence")" = "claude kimi " ] && json_fields "$out" reason_code=auth_path_unavailable next_action=host_retry'

reset_case quota auth passed
out="$(run_gate --host-remediation-attempted --allow-fallback-egress)"; rc=$?
check "Kimi auth failure after host retry may use the next client" \
  '[ "$rc" = 0 ] && [ "$(tr "\n" " " < "$WORK/state/client_sequence")" = "claude kimi opencode " ]'

reset_case auth passed unavailable
out="$(run_gate --host-remediation-attempted --allow-fallback-egress)"; rc=$?
check "auth failure after host retry may use the next client" \
  '[ "$rc" = 0 ] && [ "$(tr "\n" " " < "$WORK/state/client_sequence")" = "claude kimi " ]'

reset_case unavailable unavailable unavailable host_path
out="$(CODE_REVIEW_CLIENT_ORDER=codex run_gate --implementer-family anthropic --allow-fallback-egress)"; rc=$?
check "Codex sandbox host-path failure requests one host retry" \
  '[ "$rc" = 2 ] && [ "$(cat "$WORK/state/client_sequence")" = codex ] && json_fields "$out" reason_code=host_path_unavailable next_action=host_retry'

reset_case unavailable unavailable unavailable host_path
out="$(CODE_REVIEW_CLIENT_ORDER=codex run_gate --implementer-family anthropic --host-remediation-attempted --allow-fallback-egress)"; rc=$?
check "Codex repeated host-path failure becomes fallback-eligible only after retry" \
  '[ "$rc" = 2 ] && json_fields "$out" reason_code=host_path_unavailable_after_host_retry'

# The gate's own fail-closed floor: when the configured order contains no
# cross-family client, every candidate is skipped in preflight and the loop
# exhausts without ever setting a per-client reason. The initial
# `no_independent_reviewer_available` must survive to the terminal envelope --
# an independent review that never ran must not read as a clean lane.
reset_case unavailable unavailable unavailable
out="$(CODE_REVIEW_CLIENT_ORDER=claude run_gate --implementer-family anthropic)"; rc=$?
# client_sequence is appended only after the fake wrapper's argument loop, so on
# its own it cannot tell "never spawned" from "spawned and died early". The
# wrapper records ${client}_timeout inside that loop, strictly earlier, so
# asserting both is what pins the skip to preflight rather than to a short-lived
# provider process.
check "an order without any cross-family reviewer fails closed instead of reporting a clean lane" \
  '[ "$rc" = 2 ] && [ ! -e "$WORK/state/client_sequence" ] && [ ! -e "$WORK/state/claude_timeout" ] && json_fields "$out" status=inconclusive reason_code=no_independent_reviewer_available next_action=stop_reviewer_lane skipped_clients.0.client=claude skipped_clients.0.stage=preflight skipped_clients.0.reason_code=same_family_as_implementer'

# Precision row for the guard above: skipping a same-family client must cost
# that client only, not the lane. A tightening that turned the skip into a
# terminal outcome would pass the case above and fail here.
reset_case unavailable passed unavailable
out="$(CODE_REVIEW_CLIENT_ORDER=claude,kimi run_gate --implementer-family anthropic)"; rc=$?
check "a same-family skip still leaves a cross-family reviewer usable" \
  '[ "$rc" = 0 ] && [ "$(cat "$WORK/state/client_sequence")" = kimi ] && json_fields "$out" selected_client=kimi skipped_clients.0.reason_code=same_family_as_implementer'

printf '' >"$WORK/empty-diff.patch"
reset_case passed unavailable unavailable
out="$(REVIEW_GATE_TEST_STATE="$WORK/state" "$WORK/harness/scripts/review_gate.sh" \
  --mode review --cwd "$WORK/repo" --diff-file "$WORK/empty-diff.patch" \
  --implementer-family openai --review-plan-file "$WORK/review-plan.json")"; rc=$?
# No ${client}_timeout assertion here: freeze_packet raises before the client
# loop exists, so no wrapper is ever spawned on this path and the clause would
# be unreachable decoration. reason_code plus the absent client_sequence is the
# whole reachable surface.
check "an empty candidate fails before provider execution" \
  '[ "$rc" = 2 ] && [ ! -e "$WORK/state/client_sequence" ] && json_fields "$out" status=inconclusive reason_code=empty_diff fallback_eligible=false next_action=stop_reviewer_lane'

# --challenge-index is derived, not defaulted: in each shape exactly one value is
# legal, so an omitted flag resolves to that value instead of to a constant that
# is illegal in the mode the flag exists for. Explicit values keep their old
# validation, which is what the last three rows here pin.
challenge_gate_no_index() {
  REVIEW_GATE_TEST_STATE="$WORK/state" "$WORK/harness/scripts/review_gate.sh" \
    --mode challenge --cwd "$WORK/repo" --diff-file "$WORK/diff.patch" \
    --implementer-family openai --review-plan-file "$WORK/review-plan.json" \
    --challenge-budget 1 --focus fallback-contract "$@"
}

reset_case quota passed unavailable
out="$(challenge_gate_no_index --allow-fallback-egress)"; rc=$?
check "an untracked challenge without --challenge-index resolves to its only legal index" \
  '[ "$rc" = 0 ] && json_fields "$out" mode=challenge challenge_index=1'

reset_case quota passed unavailable
out="$(challenge_gate_no_index --allow-fallback-egress --challenge-index 0)"; rc=$?
check "an explicit --challenge-index 0 is still rejected in challenge mode" \
  '[ "$rc" = 2 ] && [ ! -e "$WORK/state/client_sequence" ] && json_fields "$out" reason_code=invalid_input'

# Budget 2 on purpose: with budget 1 an index of 2 is caught by the range check
# first, so it would never reach the tracked-chain requirement this row pins.
reset_case quota passed unavailable
out="$(challenge_gate_no_index --allow-fallback-egress --challenge-budget 2 --challenge-index 2)"; rc=$?
check "an explicit later untracked challenge index still demands a tracked chain" \
  '[ "$rc" = 2 ] && [ ! -e "$WORK/state/client_sequence" ] && json_fields "$out" reason_code=review_chain_required'

reset_case passed unavailable unavailable
out="$(REVIEW_GATE_TEST_STATE="$WORK/state" "$WORK/harness/scripts/review_gate.sh" \
  --mode review --cwd "$WORK/repo" --diff-file "$WORK/diff.patch" \
  --implementer-family openai --review-plan-file "$WORK/review-plan.json" \
  --challenge-index 1)"; rc=$?
check "--challenge-index outside challenge mode is still rejected" \
  '[ "$rc" = 2 ] && [ ! -e "$WORK/state/client_sequence" ] && json_fields "$out" reason_code=invalid_input'

# The guard reads `challenge_index != 0`, so it rejects a nonzero index outside
# challenge mode and an explicit 0 keeps running. Pinned because the resolver now
# makes explicit-0 and omitted distinguishable, so a later presence-sensitive
# tightening would be a silent CLI break rather than a caught one.
reset_case passed unavailable unavailable
out="$(run_gate --challenge-index 0)"; rc=$?
check "an explicit --challenge-index 0 outside challenge mode is not rejected on the index" \
  '[ "$rc" = 0 ] && json_fields "$out" mode=review challenge_index=0'

reset_case passed unavailable unavailable
out="$(run_gate)"; rc=$?
check "review mode without --challenge-index still carries index 0" \
  '[ "$rc" = 0 ] && json_fields "$out" mode=review challenge_index=0'

# An orphan --autonomous-review-index (no --review-chain-id) is rejected before
# the derivation could matter. Pinned so that if that guard ever moves, the
# resolver is already keyed off chain presence rather than silently deriving a
# tracked value for an untracked invocation.
reset_case passed unavailable unavailable
out="$(challenge_gate_no_index --challenge-budget 2 --autonomous-review-index 3)"; rc=$?
check "an untracked challenge carrying an orphan Agent review index is rejected before derivation" \
  '[ "$rc" = 2 ] && [ ! -e "$WORK/state/client_sequence" ] && json_fields "$out" reason_code=review_chain_invalid'

reset_case passed unavailable unavailable
out="$(run_completion_gate --completion-review-result-file "$WORK/completion-review.json")"; rc=$?
check "complete mode without --challenge-index still carries index 0" \
  '[ "$rc" = 0 ] && json_fields "$out" mode=complete challenge_index=0'

reset_case legacy passed passed
out="$(run_gate --allow-fallback-egress)"; rc=$?
check "legacy inconclusive without machine fields fails closed" \
  '[ "$rc" = 2 ] && [ "$(cat "$WORK/state/client_sequence")" = claude ]'

reset_case quota passed unavailable
out="$(run_challenge_gate --allow-fallback-egress --focus fallback-contract)"; rc=$?
check "challenge mode remains challenge across clients" \
  '[ "$rc" = 0 ] && [ "$(cat "$WORK/state/claude_mode")" = challenge ] && [ "$(cat "$WORK/state/kimi_mode")" = challenge ] && json_fields "$out" mode=challenge challenge_budget=1 challenge_index=1 challenge_focus=fallback-contract challenge_rounds_remaining=0 autonomous_review_budget=2 autonomous_review_index=2 autonomous_reviews_remaining=0 autonomous_review_allowed=false human_decision_required=false review_state=reviewed next_action=deep_self_review_before_completion completion_gated=true reviewed_concerns.0=challenge_focus self_review_gate.required=true self_review_gate.required_triggers.0=before_completion_claim && ! grep -q challenges_used <<<"$out"'

printf '%s\n' "$out" >"$WORK/untracked-challenge.json"
reset_case passed unavailable unavailable
out="$(run_completion_gate --challenge-budget 1 --completion-review-result-file "$WORK/untracked-challenge.json")"; rc=$?
check "an untracked standalone challenge cannot become Agent completion evidence" \
  '[ "$rc" = 2 ] && [ ! -e "$WORK/state/client_sequence" ] && json_fields "$out" reason_code=completion_checkpoint_invalid completion_gated=true'

reset_case passed unavailable unavailable
out="$(run_challenge_gate --challenge-budget 2 --challenge-index 2 --focus missing-chain-history)"; rc=$?
check "a later challenge requires the single tracked Agent review chain" \
  '[ "$rc" = 2 ] && [ ! -e "$WORK/state/client_sequence" ] && json_fields "$out" reason_code=review_chain_required'

reset_case passed unavailable unavailable
out="$(run_challenge_gate)"; rc=$?
check "every challenge requires an explicit focus before provider execution" \
  '[ "$rc" = 2 ] && [ ! -e "$WORK/state/client_sequence" ] && json_fields "$out" reason_code=invalid_input'

reset_case passed unavailable unavailable
out="$(run_challenge_gate --stage explore --risk-tag shared-gate --review-plan-file "$WORK/high-risk-plan.json" --focus trust-boundary)"; rc=$?
check "high-risk challenge keeps its focus plus the high-risk boundary only" \
  '[ "$rc" = 0 ] && json_fields "$out" reviewed_concerns.0=challenge_focus reviewed_concerns.1=high_risk_boundary && ! grep -q correctness <<<"$out"'

reset_case passed unavailable unavailable
out="$(run_challenge_gate --challenge-budget 2 --challenge-index 1 --focus trust-boundary)"; rc=$?
check "a clean challenge may stop before exhausting its maximum budget" \
  '[ "$rc" = 0 ] && json_fields "$out" mode=challenge challenge_budget=2 challenge_index=1 challenge_rounds_remaining=1 autonomous_review_budget=3 autonomous_review_index=2 autonomous_reviews_remaining=1 autonomous_review_allowed=true next_action=orchestrator_verify_history'

for stage in explore build release; do
  reset_case passed unavailable unavailable
  if [ "$stage" = release ]; then
    out="$(run_gate --stage "$stage" --review-chain-id release-task --autonomous-review-index 1)"; rc=$?
  else
    out="$(run_gate --stage "$stage")"; rc=$?
  fi
  check "stage $stage selects and records its minimum review depth" \
    '[ "$rc" = 0 ] && json_fields "$out" stage='"$stage"' review_depth='"$stage"''
done

reset_case passed unavailable unavailable
out="$(run_gate --challenge-budget 2)"; rc=$?
check "an initial review with challenge capacity requires a tracked Agent chain" \
  '[ "$rc" = 2 ] && [ ! -e "$WORK/state/client_sequence" ] && json_fields "$out" reason_code=review_chain_required next_action=stop_reviewer_lane'

reset_case passed unavailable unavailable
out="$(run_gate --stage explore --risk-tag shared-gate --review-plan-file "$WORK/high-risk-plan.json" --review-chain-id high-risk-task --autonomous-review-index 1)"; rc=$?
check "high-risk tags raise explore to release depth and default one challenge" \
  '[ "$rc" = 0 ] && json_fields "$out" stage=explore stage_source=caller-declared review_depth=release risk_tags_source=caller-declared challenge_budget=1 challenge_rounds_remaining=1 review_chain_tracked=true review_chain_id=high-risk-task autonomous_review_budget=2 autonomous_review_index=1 autonomous_reviews_remaining=1 autonomous_review_allowed=true next_action=run_challenge completion_gated=true risk_tags.0=shared-gate reviewed_concerns.7=high_risk_boundary self_review_gate.required=false self_review_gate.satisfied_triggers.0=before_external_review self_review_gate.satisfied_triggers.1=risk_or_scope_escalation'

# Release/high-risk normally requires a challenge. The only single-review
# exception is a candidate-bound deterministic wording-only proof whose result
# the controller can reproduce from the frozen canonical unified packet.
mkdir -p "$WORK/wording-reviewed-repo/skills/code-review/references"
printf '%s\n' '# Code Review' \
  >"$WORK/wording-reviewed-repo/skills/code-review/SKILL.md"
for target in \
  fenced-backtick.md \
  fenced-tilde.md \
  fenced-unclosed.md \
  fenced-list-bullet.md \
  fenced-list-ordered.md \
  fenced-list-indented.md \
  indented-space.md \
  indented-tab.md \
  indented-list.md \
  html-pre.md \
  html-code.md \
  inline-code.md \
  link-destination.md \
  heading-structure.md \
  list-structure.md \
  table-structure.md \
  after-closed-fence.md \
  after-closed-list-fence.md \
  ordinary-list-punctuation.md; do
  printf '%s\n' '# Existing Markdown fixture' \
    >"$WORK/wording-reviewed-repo/skills/code-review/references/$target"
done
mkdir -p "$WORK/repo/skills/code-review/references"
printf '%s\n' '# Reviewed Code Review' >"$WORK/repo/skills/code-review/SKILL.md"
for target in \
  punctuation.md \
  'café file.md' \
  typo.md \
  normative.md \
  zero-width.md \
  bidi-control.md \
  emoji-symbol.md \
  currency-symbol.md \
  decomposed-boundary.md \
  zwj-boundary.md; do
  printf '%s\n' '# Existing Markdown fixture' \
    >"$WORK/repo/skills/code-review/references/$target"
done
mkdir -p "$WORK/wording-missing-package-repo"
mkdir -p "$WORK/wording-repo-only/skills/repo-only/references"
printf '%s\n' '# Repo Only' \
  >"$WORK/wording-repo-only/skills/repo-only/SKILL.md"
printf '%s\n' '# Existing Markdown fixture' \
  >"$WORK/wording-repo-only/skills/repo-only/references/punctuation.md"
mkdir -p "$WORK/wording-linked-package-repo/skills"
ln -s "$WORK/wording-reviewed-repo/skills/code-review" \
  "$WORK/wording-linked-package-repo/skills/code-review"
mkdir -p "$WORK/wording-hardlinked-package-repo/skills/code-review"
printf '%s\n' '# Hardlinked Code Review' \
  >"$WORK/wording-hardlinked-package-repo/skills/code-review/SKILL.md"
ln "$WORK/wording-hardlinked-package-repo/skills/code-review/SKILL.md" \
  "$WORK/wording-hardlinked-package-repo/skills/code-review/SKILL.alias"
mkdir -p "$WORK/wording-nonregular-package-repo/skills/code-review/SKILL.md"
mkdir -p "$WORK/wording-oversized-package-repo/skills/code-review"
python3 - "$WORK/wording-oversized-package-repo/skills/code-review/SKILL.md" <<'PY'
import os
from pathlib import Path
import sys

path = Path(sys.argv[1])
path.touch()
os.truncate(path, 1_048_577)
PY
for unsafe_target in missing linked hardlinked nonregular oversized; do
  mkdir -p \
    "$WORK/wording-$unsafe_target-target-repo/skills/code-review/references"
  printf '%s\n' '# Code Review' \
    >"$WORK/wording-$unsafe_target-target-repo/skills/code-review/SKILL.md"
done
ln -s "$WORK/repo/skills/code-review/references/punctuation.md" \
  "$WORK/wording-linked-target-repo/skills/code-review/references/punctuation.md"
printf '%s\n' '# Hardlinked Markdown fixture' \
  >"$WORK/wording-hardlinked-target-repo/skills/code-review/references/punctuation.md"
ln "$WORK/wording-hardlinked-target-repo/skills/code-review/references/punctuation.md" \
  "$WORK/wording-hardlinked-target-repo/skills/code-review/references/punctuation.alias"
mkdir \
  "$WORK/wording-nonregular-target-repo/skills/code-review/references/punctuation.md"
python3 - "$WORK/wording-oversized-target-repo/skills/code-review/references/punctuation.md" <<'PY'
import os
from pathlib import Path
import sys

path = Path(sys.argv[1])
path.touch()
os.truncate(path, 1_048_577)
PY
cat >"$WORK/wording-punctuation.patch" <<'DIFF'
diff --git a/skills/code-review/references/punctuation.md b/skills/code-review/references/punctuation.md
index 1111111..2222222 100644
--- a/skills/code-review/references/punctuation.md
+++ b/skills/code-review/references/punctuation.md
@@ -1 +1 @@
-Review remains exact.
+Review remains exact!
DIFF
cat >"$WORK/repo-only-wording.patch" <<'DIFF'
diff --git a/skills/repo-only/references/punctuation.md b/skills/repo-only/references/punctuation.md
index 1111111..2222222 100644
--- a/skills/repo-only/references/punctuation.md
+++ b/skills/repo-only/references/punctuation.md
@@ -1 +1 @@
-Review remains exact.
+Review remains exact!
DIFF
cat >"$WORK/fenced-backtick-wording.patch" <<'DIFF'
diff --git a/skills/code-review/references/fenced-backtick.md b/skills/code-review/references/fenced-backtick.md
index 1111111..2222222 100644
--- a/skills/code-review/references/fenced-backtick.md
+++ b/skills/code-review/references/fenced-backtick.md
@@ -1,3 +1,3 @@
 ```bash
-command;;
+command;
 ```
DIFF
cat >"$WORK/fenced-tilde-wording.patch" <<'DIFF'
diff --git a/skills/code-review/references/fenced-tilde.md b/skills/code-review/references/fenced-tilde.md
index 1111111..2222222 100644
--- a/skills/code-review/references/fenced-tilde.md
+++ b/skills/code-review/references/fenced-tilde.md
@@ -1,3 +1,3 @@
 ~~~sh
-command;;
+command;
 ~~~
DIFF
cat >"$WORK/after-closed-fence-wording.patch" <<'DIFF'
diff --git a/skills/code-review/references/after-closed-fence.md b/skills/code-review/references/after-closed-fence.md
index 1111111..2222222 100644
--- a/skills/code-review/references/after-closed-fence.md
+++ b/skills/code-review/references/after-closed-fence.md
@@ -1,4 +1,4 @@
 ```shell
 command stays unchanged
 ```
-Review remains exact.
+Review remains exact!
DIFF
cat >"$WORK/fenced-unclosed-wording.patch" <<'DIFF'
diff --git a/skills/code-review/references/fenced-unclosed.md b/skills/code-review/references/fenced-unclosed.md
index 1111111..2222222 100644
--- a/skills/code-review/references/fenced-unclosed.md
+++ b/skills/code-review/references/fenced-unclosed.md
@@ -1,2 +1,2 @@
 ```bash
-command;;
+command;
DIFF
cat >"$WORK/fenced-list-bullet-wording.patch" <<'DIFF'
diff --git a/skills/code-review/references/fenced-list-bullet.md b/skills/code-review/references/fenced-list-bullet.md
index 1111111..2222222 100644
--- a/skills/code-review/references/fenced-list-bullet.md
+++ b/skills/code-review/references/fenced-list-bullet.md
@@ -1,3 +1,3 @@
 - ```bash
-  command;;
+  command;
   ```
DIFF
cat >"$WORK/fenced-list-ordered-wording.patch" <<'DIFF'
diff --git a/skills/code-review/references/fenced-list-ordered.md b/skills/code-review/references/fenced-list-ordered.md
index 1111111..2222222 100644
--- a/skills/code-review/references/fenced-list-ordered.md
+++ b/skills/code-review/references/fenced-list-ordered.md
@@ -1,3 +1,3 @@
 10. ~~~sh
-    command;;
+    command;
     ~~~
DIFF
python3 - "$WORK/fenced-list-indented-wording.patch" <<'PY'
from pathlib import Path
import sys

Path(sys.argv[1]).write_text(
    "diff --git a/skills/code-review/references/fenced-list-indented.md "
    "b/skills/code-review/references/fenced-list-indented.md\n"
    "index 1111111..2222222 100644\n"
    "--- a/skills/code-review/references/fenced-list-indented.md\n"
    "+++ b/skills/code-review/references/fenced-list-indented.md\n"
    "@@ -1,5 +1,5 @@\n"
    " - shell example\n"
    " \n"
    "     ```sh\n"
    "-    command;;\n"
    "+    command;\n"
    "     ```\n",
    encoding="utf-8",
)
PY
cat >"$WORK/indented-space-wording.patch" <<'DIFF'
diff --git a/skills/code-review/references/indented-space.md b/skills/code-review/references/indented-space.md
index 1111111..2222222 100644
--- a/skills/code-review/references/indented-space.md
+++ b/skills/code-review/references/indented-space.md
@@ -1 +1 @@
-    command;;
+    command;
DIFF
python3 - "$WORK/indented-tab-wording.patch" <<'PY'
from pathlib import Path
import sys

Path(sys.argv[1]).write_text(
    "diff --git a/skills/code-review/references/indented-tab.md "
    "b/skills/code-review/references/indented-tab.md\n"
    "index 1111111..2222222 100644\n"
    "--- a/skills/code-review/references/indented-tab.md\n"
    "+++ b/skills/code-review/references/indented-tab.md\n"
    "@@ -1 +1 @@\n"
    "-\tcommand;;\n"
    "+\tcommand;\n",
    encoding="utf-8",
)
PY
cat >"$WORK/indented-list-wording.patch" <<'DIFF'
diff --git a/skills/code-review/references/indented-list.md b/skills/code-review/references/indented-list.md
index 1111111..2222222 100644
--- a/skills/code-review/references/indented-list.md
+++ b/skills/code-review/references/indented-list.md
@@ -1,2 +1,2 @@
 - item
-      command;;
+      command;
DIFF
cat >"$WORK/html-pre-wording.patch" <<'DIFF'
diff --git a/skills/code-review/references/html-pre.md b/skills/code-review/references/html-pre.md
index 1111111..2222222 100644
--- a/skills/code-review/references/html-pre.md
+++ b/skills/code-review/references/html-pre.md
@@ -1,3 +1,3 @@
 <pre>
-command;;
+command;
 </pre>
DIFF
cat >"$WORK/html-code-wording.patch" <<'DIFF'
diff --git a/skills/code-review/references/html-code.md b/skills/code-review/references/html-code.md
index 1111111..2222222 100644
--- a/skills/code-review/references/html-code.md
+++ b/skills/code-review/references/html-code.md
@@ -1,3 +1,3 @@
 <code>
-command;;
+command;
 </code>
DIFF
cat >"$WORK/inline-code-wording.patch" <<'DIFF'
diff --git a/skills/code-review/references/inline-code.md b/skills/code-review/references/inline-code.md
index 1111111..2222222 100644
--- a/skills/code-review/references/inline-code.md
+++ b/skills/code-review/references/inline-code.md
@@ -1 +1 @@
-`command;;`
+`command;`
DIFF
cat >"$WORK/link-destination-wording.patch" <<'DIFF'
diff --git a/skills/code-review/references/link-destination.md b/skills/code-review/references/link-destination.md
index 1111111..2222222 100644
--- a/skills/code-review/references/link-destination.md
+++ b/skills/code-review/references/link-destination.md
@@ -1 +1 @@
-[docs](#)
+[docs](/)
DIFF
cat >"$WORK/heading-structure-wording.patch" <<'DIFF'
diff --git a/skills/code-review/references/heading-structure.md b/skills/code-review/references/heading-structure.md
index 1111111..2222222 100644
--- a/skills/code-review/references/heading-structure.md
+++ b/skills/code-review/references/heading-structure.md
@@ -1 +1 @@
-# Review remains exact.
+## Review remains exact.
DIFF
cat >"$WORK/list-structure-wording.patch" <<'DIFF'
diff --git a/skills/code-review/references/list-structure.md b/skills/code-review/references/list-structure.md
index 1111111..2222222 100644
--- a/skills/code-review/references/list-structure.md
+++ b/skills/code-review/references/list-structure.md
@@ -1 +1 @@
-- Review remains exact.
+* Review remains exact.
DIFF
cat >"$WORK/table-structure-wording.patch" <<'DIFF'
diff --git a/skills/code-review/references/table-structure.md b/skills/code-review/references/table-structure.md
index 1111111..2222222 100644
--- a/skills/code-review/references/table-structure.md
+++ b/skills/code-review/references/table-structure.md
@@ -1 +1 @@
-| Review remains exact |
+| Review remains exact: |
DIFF
cat >"$WORK/after-closed-list-fence-wording.patch" <<'DIFF'
diff --git a/skills/code-review/references/after-closed-list-fence.md b/skills/code-review/references/after-closed-list-fence.md
index 1111111..2222222 100644
--- a/skills/code-review/references/after-closed-list-fence.md
+++ b/skills/code-review/references/after-closed-list-fence.md
@@ -1,4 +1,4 @@
 - ```shell
   command stays unchanged
   ```
-Review remains exact.
+Review remains exact!
DIFF
cat >"$WORK/ordinary-list-punctuation-wording.patch" <<'DIFF'
diff --git a/skills/code-review/references/ordinary-list-punctuation.md b/skills/code-review/references/ordinary-list-punctuation.md
index 1111111..2222222 100644
--- a/skills/code-review/references/ordinary-list-punctuation.md
+++ b/skills/code-review/references/ordinary-list-punctuation.md
@@ -1 +1 @@
-- Review remains exact.
+- Review remains exact!
DIFF
cat >"$WORK/wording-token.patch" <<'DIFF'
diff --git a/skills/code-review/references/typo.md b/skills/code-review/references/typo.md
index 1111111..2222222 100644
--- a/skills/code-review/references/typo.md
+++ b/skills/code-review/references/typo.md
@@ -1 +1 @@
-This teh rule stays otherwise byte-identical.
+This the rule stays otherwise byte-identical.
DIFF
cat >"$WORK/wording-normative-token.patch" <<'DIFF'
diff --git a/skills/code-review/references/normative.md b/skills/code-review/references/normative.md
index 1111111..2222222 100644
--- a/skills/code-review/references/normative.md
+++ b/skills/code-review/references/normative.md
@@ -1 +1 @@
-Agents must reject unsafe input.
+Agents may reject unsafe input.
DIFF
cat >"$WORK/quoted-unicode-wording.patch" <<'DIFF'
diff --git "a/skills/code-review/references/café file.md" "b/skills/code-review/references/café file.md"
index 1111111..2222222 100644
--- "a/skills/code-review/references/café file.md"
+++ "b/skills/code-review/references/café file.md"
@@ -1 +1 @@
-Review remains exact.
+Review remains exact!
DIFF
cat >"$WORK/non-wording-punctuation.patch" <<'DIFF'
diff --git a/skills/demo/scripts/runtime.py b/skills/demo/scripts/runtime.py
index 1111111..2222222 100644
--- a/skills/demo/scripts/runtime.py
+++ b/skills/demo/scripts/runtime.py
@@ -1 +1 @@
-.
+!
DIFF
cat >"$WORK/multi-skill-wording.patch" <<'DIFF'
diff --git a/skills/code-review/references/one.md b/skills/code-review/references/one.md
index 1111111..2222222 100644
--- a/skills/code-review/references/one.md
+++ b/skills/code-review/references/one.md
@@ -1 +1,2 @@
 First package.
+***
diff --git a/skills/testing-strategy/references/two.md b/skills/testing-strategy/references/two.md
index 1111111..2222222 100644
--- a/skills/testing-strategy/references/two.md
+++ b/skills/testing-strategy/references/two.md
@@ -1 +1,2 @@
 Second package.
+***
DIFF
cat >"$WORK/truncated-context-wording.patch" <<'DIFF'
diff --git a/skills/code-review/references/deep.md b/skills/code-review/references/deep.md
index 1111111..2222222 100644
--- a/skills/code-review/references/deep.md
+++ b/skills/code-review/references/deep.md
@@ -8 +8 @@
-This teh rule is below omitted context.
+This the rule is below omitted context.
DIFF
cat >"$WORK/symlink-mode-wording.patch" <<'DIFF'
diff --git a/skills/code-review/references/link.md b/skills/code-review/references/link.md
index 1111111..2222222 120000
--- a/skills/code-review/references/link.md
+++ b/skills/code-review/references/link.md
@@ -1 +1 @@
-targets/teh
+targets/the
DIFF
cat >"$WORK/frontmatter-shift-insert-wording.patch" <<'DIFF'
diff --git a/skills/code-review/SKILL.md b/skills/code-review/SKILL.md
index 1111111..2222222 100644
--- a/skills/code-review/SKILL.md
+++ b/skills/code-review/SKILL.md
@@ -1,3 +1,4 @@
+#
 ---
 description: Canonical routing metadata.
 ---
DIFF
cat >"$WORK/frontmatter-shift-delete-wording.patch" <<'DIFF'
diff --git a/skills/code-review/SKILL.md b/skills/code-review/SKILL.md
index 1111111..2222222 100644
--- a/skills/code-review/SKILL.md
+++ b/skills/code-review/SKILL.md
@@ -1,4 +1,3 @@
-#
 ---
 description: Canonical routing metadata.
 ---
DIFF
cat >"$WORK/no-final-newline-wording.patch" <<'DIFF'
diff --git a/skills/code-review/references/no-newline.md b/skills/code-review/references/no-newline.md
index 1111111..2222222 100644
--- a/skills/code-review/references/no-newline.md
+++ b/skills/code-review/references/no-newline.md
@@ -1 +1 @@
-This teh token has no final newline.
\ No newline at end of file
+This the token has no final newline.
\ No newline at end of file
DIFF
cat >"$WORK/invalid-octal-wording.patch" <<'DIFF'
diff --git "a/skills/code-review/references/bad\777.md" "b/skills/code-review/references/bad\777.md"
index 1111111..2222222 100644
--- "a/skills/code-review/references/bad\777.md"
+++ "b/skills/code-review/references/bad\777.md"
@@ -1 +1,2 @@
 Plain context.
+***
DIFF
python3 - "$WORK/huge-hunk-number-wording.patch" <<'PY'
from pathlib import Path
import sys

Path(sys.argv[1]).write_text(
    "diff --git a/skills/code-review/references/huge.md b/skills/code-review/references/huge.md\n"
    "index 1111111..2222222 100644\n"
    "--- a/skills/code-review/references/huge.md\n"
    "+++ b/skills/code-review/references/huge.md\n"
    f"@@ -{'9' * 5001} +1 @@\n"
    "-*\n"
    "+!\n",
    encoding="utf-8",
)
PY
python3 - "$WORK" <<'PY'
from pathlib import Path
import sys

root = Path(sys.argv[1])
for slug, value in (
    ("zero-width", "\u200b"),
    ("bidi-control", "\u202e"),
    ("emoji-symbol", "\U0001f6a8"),
    ("currency-symbol", "$$"),
):
    (root / f"{slug}-wording.patch").write_text(
        f"diff --git a/skills/code-review/references/{slug}.md b/skills/code-review/references/{slug}.md\n"
        "index 1111111..2222222 100644\n"
        f"--- a/skills/code-review/references/{slug}.md\n"
        f"+++ b/skills/code-review/references/{slug}.md\n"
        "@@ -1 +1,2 @@\n"
        " Plain context.\n"
        f"+{value}\n",
        encoding="utf-8",
    )
PY
python3 - "$WORK" <<'PY'
from pathlib import Path
import sys

root = Path(sys.argv[1])
for slug, old_line, new_line in (
    (
        "decomposed-boundary",
        "Context cafe\u0301 token.",
        "Context coffee\u0301 token.",
    ),
    (
        "zwj-boundary",
        "Context admin\u200distrator token.",
        "Context root\u200distrator token.",
    ),
):
    (root / f"{slug}-wording.patch").write_text(
        f"diff --git a/skills/code-review/references/{slug}.md b/skills/code-review/references/{slug}.md\n"
        "index 1111111..2222222 100644\n"
        f"--- a/skills/code-review/references/{slug}.md\n"
        f"+++ b/skills/code-review/references/{slug}.md\n"
        "@@ -1 +1 @@\n"
        f"-{old_line}\n"
        f"+{new_line}\n",
        encoding="utf-8",
    )
PY

write_wording_proof() { # <packet> <proof> <kind> [old new count]
  python3 - "$@" <<'PY'
import hashlib
import json
from pathlib import Path
import sys

packet_path, proof_path, kind, *replacement = sys.argv[1:]
packet = Path(packet_path).read_bytes()
candidate_sha = hashlib.sha256(packet).hexdigest()
if kind == "markdown-punctuation-only":
    check = {"kind": kind}
elif kind == "markdown-token-replacement":
    old, new, count_text = replacement
    check = {
        "kind": kind,
        "old_token": old,
        "new_token": new,
        "expected_count": int(count_text),
    }
else:
    raise AssertionError(kind)
proof = {
    "schema_version": 1,
    "candidate_sha256": candidate_sha,
    "check": check,
}
Path(proof_path).write_text(
    json.dumps(proof, sort_keys=True, separators=(",", ":")), encoding="utf-8"
)
PY
}

write_wording_proof "$WORK/wording-punctuation.patch" \
  "$WORK/wording-punctuation-proof.json" markdown-punctuation-only
write_wording_proof "$WORK/repo-only-wording.patch" \
  "$WORK/repo-only-wording-proof.json" markdown-punctuation-only
for fenced_scope in \
  fenced-backtick \
  fenced-tilde \
  fenced-unclosed \
  fenced-list-bullet \
  fenced-list-ordered \
  fenced-list-indented; do
  write_wording_proof "$WORK/$fenced_scope-wording.patch" \
    "$WORK/$fenced_scope-wording-proof.json" markdown-punctuation-only
done
for rejected_punctuation_scope in \
  indented-space \
  indented-tab \
  indented-list \
  html-pre \
  html-code \
  inline-code \
  link-destination \
  heading-structure \
  list-structure \
  table-structure \
  ordinary-list-punctuation; do
  write_wording_proof "$WORK/$rejected_punctuation_scope-wording.patch" \
    "$WORK/$rejected_punctuation_scope-wording-proof.json" \
    markdown-punctuation-only
done
for eligible_scope in \
  after-closed-fence \
  after-closed-list-fence; do
  write_wording_proof "$WORK/$eligible_scope-wording.patch" \
    "$WORK/$eligible_scope-wording-proof.json" markdown-punctuation-only
done
write_wording_proof "$WORK/wording-token.patch" \
  "$WORK/wording-token-proof.json" markdown-token-replacement teh the 1
write_wording_proof "$WORK/wording-normative-token.patch" \
  "$WORK/wording-normative-token-proof.json" markdown-token-replacement must may 1
write_wording_proof "$WORK/quoted-unicode-wording.patch" \
  "$WORK/quoted-unicode-wording-proof.json" markdown-punctuation-only
write_wording_proof "$WORK/non-wording-punctuation.patch" \
  "$WORK/non-wording-proof.json" markdown-punctuation-only
write_wording_proof "$WORK/multi-skill-wording.patch" \
  "$WORK/multi-skill-wording-proof.json" markdown-punctuation-only
write_wording_proof "$WORK/truncated-context-wording.patch" \
  "$WORK/truncated-context-wording-proof.json" markdown-token-replacement teh the 1
write_wording_proof "$WORK/symlink-mode-wording.patch" \
  "$WORK/symlink-mode-wording-proof.json" markdown-token-replacement teh the 1
write_wording_proof "$WORK/frontmatter-shift-insert-wording.patch" \
  "$WORK/frontmatter-shift-insert-wording-proof.json" markdown-punctuation-only
write_wording_proof "$WORK/frontmatter-shift-delete-wording.patch" \
  "$WORK/frontmatter-shift-delete-wording-proof.json" markdown-punctuation-only
write_wording_proof "$WORK/no-final-newline-wording.patch" \
  "$WORK/no-final-newline-wording-proof.json" markdown-token-replacement teh the 1
write_wording_proof "$WORK/invalid-octal-wording.patch" \
  "$WORK/invalid-octal-wording-proof.json" markdown-punctuation-only
write_wording_proof "$WORK/huge-hunk-number-wording.patch" \
  "$WORK/huge-hunk-number-wording-proof.json" markdown-punctuation-only
for rejected_character in zero-width bidi-control emoji-symbol currency-symbol; do
  write_wording_proof "$WORK/$rejected_character-wording.patch" \
    "$WORK/$rejected_character-wording-proof.json" markdown-punctuation-only
done
write_wording_proof "$WORK/decomposed-boundary-wording.patch" \
  "$WORK/decomposed-boundary-wording-proof.json" markdown-token-replacement cafe coffee 1
write_wording_proof "$WORK/zwj-boundary-wording.patch" \
  "$WORK/zwj-boundary-wording-proof.json" markdown-token-replacement admin root 1

mkdir -p "$WORK/wording-base-repo/skills/code-review/references"
git -C "$WORK/wording-base-repo" init -q
git -C "$WORK/wording-base-repo" config user.name 'Review Gate Test'
git -C "$WORK/wording-base-repo" config user.email 'review-gate@example.invalid'
printf '%s\n' '# Code Review' \
  >"$WORK/wording-base-repo/skills/code-review/SKILL.md"
cat >"$WORK/wording-base-repo/skills/code-review/references/long.md" <<'MARKDOWN'
---
title: Bounded example
---
# Review contract

Context line one.
Context line two.
Context line three.
This teh token is below frontmatter and ordinary context.
Context line four.
MARKDOWN
git -C "$WORK/wording-base-repo" add skills/code-review
git -C "$WORK/wording-base-repo" commit -q -m base
python3 - "$WORK/wording-base-repo/skills/code-review/references/long.md" <<'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1])
path.write_text(path.read_text().replace("This teh token", "This the token"))
PY
git -C "$WORK/wording-base-repo" diff --no-color --no-ext-diff --no-textconv \
  --unified=1000000 HEAD >"$WORK/wording-base.patch"
write_wording_proof "$WORK/wording-base.patch" \
  "$WORK/wording-base-proof.json" markdown-token-replacement teh the 1

reset_case passed unavailable unavailable
out="$(REVIEW_GATE_TEST_STATE="$WORK/state" "$WORK/harness/scripts/review_gate.sh" \
  --mode review --stage release --challenge-budget 0 \
  --cwd "$WORK/wording-missing-package-repo" \
  --diff-file "$WORK/wording-punctuation.patch" \
  --implementer-family openai --review-plan-file "$WORK/review-plan.json" \
  --wording-only-proof-file "$WORK/wording-punctuation-proof.json")"; rc=$?
check "wording proof cannot borrow a missing candidate package from the controller tree" \
  '[ "$rc" = 2 ] && [ ! -e "$WORK/state/client_sequence" ] && json_fields "$out" reason_code=wording_only_proof_invalid'

reset_case passed unavailable unavailable
out="$(REVIEW_GATE_TEST_STATE="$WORK/state" "$WORK/harness/scripts/review_gate.sh" \
  --mode review --stage release --challenge-budget 0 \
  --cwd "$WORK/wording-repo-only" \
  --diff-file "$WORK/repo-only-wording.patch" \
  --implementer-family openai --review-plan-file "$WORK/review-plan.json" \
  --wording-only-proof-file "$WORK/repo-only-wording-proof.json")"; rc=$?
check "wording proof accepts a candidate-only package absent from the controller tree" \
  '[ "$rc" = 0 ] && json_fields "$out" wording_only_scope.status=passed wording_only_scope.changed_files.0=skills/repo-only/references/punctuation.md'

for unsafe_package in linked hardlinked nonregular oversized; do
  reset_case passed unavailable unavailable
  out="$(REVIEW_GATE_TEST_STATE="$WORK/state" "$WORK/harness/scripts/review_gate.sh" \
    --mode review --stage release --challenge-budget 0 \
    --cwd "$WORK/wording-$unsafe_package-package-repo" \
    --diff-file "$WORK/wording-punctuation.patch" \
    --implementer-family openai --review-plan-file "$WORK/review-plan.json" \
    --wording-only-proof-file "$WORK/wording-punctuation-proof.json")"; rc=$?
  check "wording proof rejects a $unsafe_package candidate package entrypoint" \
    '[ "$rc" = 2 ] && [ ! -e "$WORK/state/client_sequence" ] && json_fields "$out" reason_code=wording_only_proof_invalid'
done

for unsafe_target in missing linked hardlinked nonregular oversized; do
  reset_case passed unavailable unavailable
  out="$(REVIEW_GATE_TEST_STATE="$WORK/state" "$WORK/harness/scripts/review_gate.sh" \
    --mode review --stage release --challenge-budget 0 \
    --cwd "$WORK/wording-$unsafe_target-target-repo" \
    --diff-file "$WORK/wording-punctuation.patch" \
    --implementer-family openai --review-plan-file "$WORK/review-plan.json" \
    --wording-only-proof-file "$WORK/wording-punctuation-proof.json")"; rc=$?
  check "wording proof rejects a $unsafe_target changed Markdown target" \
    '[ "$rc" = 2 ] && [ ! -e "$WORK/state/client_sequence" ] && json_fields "$out" reason_code=wording_only_proof_invalid'
done

for fenced_scope in \
  fenced-backtick \
  fenced-tilde \
  fenced-unclosed \
  fenced-list-bullet \
  fenced-list-ordered \
  fenced-list-indented; do
  reset_case passed unavailable unavailable
  out="$(REVIEW_GATE_TEST_STATE="$WORK/state" "$WORK/harness/scripts/review_gate.sh" \
    --mode review --stage release --challenge-budget 0 \
    --cwd "$WORK/wording-reviewed-repo" \
    --diff-file "$WORK/$fenced_scope-wording.patch" \
    --implementer-family openai --review-plan-file "$WORK/review-plan.json" \
    --wording-only-proof-file "$WORK/$fenced_scope-wording-proof.json")"; rc=$?
  check "$fenced_scope cannot use the punctuation-only release waiver" \
    '[ "$rc" = 2 ] && [ ! -e "$WORK/state/client_sequence" ] && json_fields "$out" reason_code=wording_only_proof_invalid'
done

for rejected_punctuation_scope in \
  indented-space \
  indented-tab \
  indented-list \
  html-pre \
  html-code \
  inline-code \
  link-destination \
  heading-structure \
  list-structure \
  table-structure \
  ordinary-list-punctuation; do
  reset_case passed unavailable unavailable
  out="$(REVIEW_GATE_TEST_STATE="$WORK/state" "$WORK/harness/scripts/review_gate.sh" \
    --mode review --stage release --challenge-budget 0 \
    --cwd "$WORK/wording-reviewed-repo" \
    --diff-file "$WORK/$rejected_punctuation_scope-wording.patch" \
    --implementer-family openai --review-plan-file "$WORK/review-plan.json" \
    --wording-only-proof-file "$WORK/$rejected_punctuation_scope-wording-proof.json")"; rc=$?
  check "$rejected_punctuation_scope cannot use the punctuation-only release waiver" \
    '[ "$rc" = 2 ] && [ ! -e "$WORK/state/client_sequence" ] && json_fields "$out" reason_code=wording_only_proof_invalid'
done

for eligible_scope in \
  after-closed-fence \
  after-closed-list-fence; do
  reset_case passed unavailable unavailable
  out="$(REVIEW_GATE_TEST_STATE="$WORK/state" "$WORK/harness/scripts/review_gate.sh" \
    --mode review --stage release --challenge-budget 0 \
    --cwd "$WORK/wording-reviewed-repo" \
    --diff-file "$WORK/$eligible_scope-wording.patch" \
    --implementer-family openai --review-plan-file "$WORK/review-plan.json" \
    --wording-only-proof-file "$WORK/$eligible_scope-wording-proof.json")"; rc=$?
  check "$eligible_scope remains eligible for punctuation-only proof" \
    '[ "$rc" = 0 ] && json_fields "$out" wording_only_scope.status=passed wording_only_scope.check_kind=markdown-punctuation-only'
done

reset_case passed unavailable unavailable
out="$(REVIEW_GATE_TEST_STATE="$WORK/state" "$WORK/harness/scripts/review_gate.sh" \
  --mode review --stage release --challenge-budget 0 \
  --cwd "$WORK/repo" --diff-file "$WORK/wording-punctuation.patch" \
  --implementer-family openai --review-plan-file "$WORK/review-plan.json" \
  --wording-only-proof-file "$WORK/wording-punctuation-proof.json")"; rc=$?
punctuation_proof_hash="$(shasum -a 256 "$WORK/wording-punctuation-proof.json" | awk '{print $1}')"
check "release wording-only punctuation scope can take one proof-bound review" \
  '[ "$rc" = 0 ] && json_fields "$out" challenge_budget=0 review_chain_tracked=false wording_only_scope.status=passed wording_only_scope.check_kind=markdown-punctuation-only wording_only_proof_sha256="$punctuation_proof_hash" reviewed_concerns.7=wording_only_boundary'

reset_case passed unavailable unavailable
out="$(REVIEW_GATE_TEST_STATE="$WORK/state" "$WORK/harness/scripts/review_gate.sh" \
  --mode review --stage build --challenge-budget 0 \
  --cwd "$WORK/repo" --diff-file "$WORK/wording-punctuation.patch" \
  --implementer-family openai --review-plan-file "$WORK/review-plan.json" \
  --wording-only-proof-file "$WORK/wording-punctuation-proof.json")"; rc=$?
check "build wording-only review records the same controller-bound proof" \
  '[ "$rc" = 0 ] && json_fields "$out" review_depth=build challenge_budget=0 wording_only_scope.check_kind=markdown-punctuation-only reviewed_concerns.5=wording_only_boundary'
printf '%s\n' "$out" >"$WORK/wording-punctuation-review.json"
reset_case passed unavailable unavailable
out="$(REVIEW_GATE_TEST_STATE="$WORK/state" "$WORK/harness/scripts/review_gate.sh" \
  --mode complete --stage build --challenge-budget 0 \
  --cwd "$WORK/repo" --diff-file "$WORK/wording-punctuation.patch" \
  --implementer-family openai --review-plan-file "$WORK/review-plan.json" \
  --completion-review-result-file "$WORK/wording-punctuation-review.json")"; rc=$?
check "a wording-only single review cannot become a complete checkpoint" \
  '[ "$rc" = 2 ] && [ ! -e "$WORK/state/client_sequence" ] && json_fields "$out" reason_code=completion_checkpoint_invalid'

python3 - "$WORK/wording-punctuation-review.json" "$WORK/wording-punctuation-review-without-proof-keys.json" <<'PY'
import json
import sys
from pathlib import Path

source, target = map(Path, sys.argv[1:])
payload = json.loads(source.read_text(encoding="utf-8"))
payload.pop("wording_only_proof_sha256")
payload.pop("wording_only_scope")
target.write_text(json.dumps(payload), encoding="utf-8")
PY
reset_case passed unavailable unavailable
out="$(REVIEW_GATE_TEST_STATE="$WORK/state" "$WORK/harness/scripts/review_gate.sh" \
  --mode complete --stage build --challenge-budget 0 \
  --cwd "$WORK/repo" --diff-file "$WORK/wording-punctuation.patch" \
  --implementer-family openai --review-plan-file "$WORK/review-plan.json" \
  --completion-review-result-file "$WORK/wording-punctuation-review-without-proof-keys.json")"; rc=$?
check "a receipt cannot hide wording-only proof by dropping controller-owned keys" \
  '[ "$rc" = 2 ] && [ ! -e "$WORK/state/client_sequence" ] && json_fields "$out" reason_code=completion_checkpoint_invalid'

python3 - "$WORK/wording-punctuation-review.json" "$WORK/wording-punctuation-review-with-null-proof.json" <<'PY'
import json
import sys
from pathlib import Path

source, target = map(Path, sys.argv[1:])
payload = json.loads(source.read_text(encoding="utf-8"))
payload["wording_only_proof_sha256"] = None
payload["wording_only_scope"] = None
target.write_text(json.dumps(payload), encoding="utf-8")
PY
reset_case passed unavailable unavailable
out="$(REVIEW_GATE_TEST_STATE="$WORK/state" "$WORK/harness/scripts/review_gate.sh" \
  --mode complete --stage build --challenge-budget 0 \
  --cwd "$WORK/repo" --diff-file "$WORK/wording-punctuation.patch" \
  --implementer-family openai --review-plan-file "$WORK/review-plan.json" \
  --completion-review-result-file "$WORK/wording-punctuation-review-with-null-proof.json")"; rc=$?
check "a receipt cannot hide wording-only proof by replacing it with null" \
  '[ "$rc" = 2 ] && [ ! -e "$WORK/state/client_sequence" ] && json_fields "$out" reason_code=completion_checkpoint_invalid'

reset_case passed unavailable unavailable
out="$(REVIEW_GATE_TEST_STATE="$WORK/state" "$WORK/harness/scripts/review_gate.sh" \
  --mode review --stage build --challenge-budget 0 \
  --cwd "$WORK/repo" --diff-file "$WORK/quoted-unicode-wording.patch" \
  --implementer-family openai --review-plan-file "$WORK/review-plan.json" \
  --wording-only-proof-file "$WORK/quoted-unicode-wording-proof.json")"; rc=$?
check "wording proof binds Git-quoted literal Unicode and space paths" \
  '[ "$rc" = 0 ] && json_fields "$out" wording_only_scope.changed_files.0="skills/code-review/references/café file.md"'

reset_case passed unavailable unavailable
out="$(REVIEW_GATE_TEST_STATE="$WORK/state" "$WORK/harness/scripts/review_gate.sh" \
  --mode review --stage build --challenge-budget 1 \
  --cwd "$WORK/repo" --diff-file "$WORK/wording-punctuation.patch" \
  --implementer-family openai --review-plan-file "$WORK/review-plan.json" \
  --wording-only-proof-file "$WORK/wording-punctuation-proof.json")"; rc=$?
check "wording-only proof cannot open positive autonomous review capacity" \
  '[ "$rc" = 2 ] && [ ! -e "$WORK/state/client_sequence" ] && json_fields "$out" reason_code=wording_only_proof_invalid'

reset_case passed unavailable unavailable
out="$(REVIEW_GATE_TEST_STATE="$WORK/state" "$WORK/harness/scripts/review_gate.sh" \
  --mode review --stage build --challenge-budget 0 \
  --cwd "$WORK/repo" --diff-file "$WORK/wording-token.patch" \
  --implementer-family openai --review-plan-file "$WORK/review-plan.json" \
  --wording-only-proof-file "$WORK/wording-token-proof.json")"; rc=$?
check "build exact typo replacement can take one proof-bound review" \
  '[ "$rc" = 0 ] && json_fields "$out" review_depth=build challenge_budget=0 wording_only_scope.check_kind=markdown-token-replacement wording_only_scope.old_token=teh wording_only_scope.new_token=the wording_only_scope.expected_count=1 wording_only_scope.replacement_count=1 reviewed_concerns.5=wording_only_boundary'

reset_case passed unavailable unavailable
out="$(REVIEW_GATE_TEST_STATE="$WORK/state" "$WORK/harness/scripts/review_gate.sh" \
  --mode review --stage release --challenge-budget 0 \
  --cwd "$WORK/repo" --diff-file "$WORK/wording-normative-token.patch" \
  --implementer-family openai --review-plan-file "$WORK/review-plan.json" \
  --wording-only-proof-file "$WORK/wording-normative-token-proof.json")"; rc=$?
check "release token replacement cannot waive its required challenge" \
  '[ "$rc" = 2 ] && [ ! -e "$WORK/state/client_sequence" ] && json_fields "$out" reason_code=wording_only_proof_invalid'

reset_case passed unavailable unavailable
out="$(REVIEW_GATE_TEST_STATE="$WORK/state" "$WORK/harness/scripts/review_gate.sh" \
  --mode review --stage explore --risk-tag shared-gate --challenge-budget 0 \
  --cwd "$WORK/repo" --diff-file "$WORK/wording-normative-token.patch" \
  --implementer-family openai --review-plan-file "$WORK/high-risk-plan.json" \
  --wording-only-proof-file "$WORK/wording-normative-token-proof.json")"; rc=$?
check "high-risk token replacement cannot waive its required challenge" \
  '[ "$rc" = 2 ] && [ ! -e "$WORK/state/client_sequence" ] && json_fields "$out" reason_code=wording_only_proof_invalid'

reset_case passed unavailable unavailable
out="$(REVIEW_GATE_TEST_STATE="$WORK/state" "$WORK/harness/scripts/review_gate.sh" \
  --mode review --stage build --challenge-budget 0 \
  --cwd "$WORK/wording-base-repo" --base HEAD \
  --implementer-family openai --review-plan-file "$WORK/review-plan.json" \
  --wording-only-proof-file "$WORK/wording-base-proof.json")"; rc=$?
check "base-mode build wording proof freezes full context from line one" \
  '[ "$rc" = 0 ] && json_fields "$out" review_depth=build wording_only_scope.check_kind=markdown-token-replacement wording_only_scope.replacement_count=1 reviewed_concerns.5=wording_only_boundary'

for rejected_scope in multi-skill-wording truncated-context-wording symlink-mode-wording frontmatter-shift-insert-wording frontmatter-shift-delete-wording no-final-newline-wording invalid-octal-wording huge-hunk-number-wording zero-width-wording bidi-control-wording emoji-symbol-wording currency-symbol-wording decomposed-boundary-wording zwj-boundary-wording; do
  reset_case passed unavailable unavailable
  packet="$WORK/$rejected_scope.patch"
  proof="$WORK/$rejected_scope-proof.json"
  out="$(REVIEW_GATE_TEST_STATE="$WORK/state" "$WORK/harness/scripts/review_gate.sh" \
    --mode review --stage release --challenge-budget 0 \
    --cwd "$WORK/repo" --diff-file "$packet" \
    --implementer-family openai --review-plan-file "$WORK/review-plan.json" \
    --wording-only-proof-file "$proof")"; rc=$?
  check "$rejected_scope cannot waive the release challenge" \
    '[ "$rc" = 2 ] && [ ! -e "$WORK/state/client_sequence" ] && json_fields "$out" reason_code=wording_only_proof_invalid'
done

reset_case missing_wording_boundary unavailable unavailable
out="$(REVIEW_GATE_TEST_STATE="$WORK/state" "$WORK/harness/scripts/review_gate.sh" \
  --mode review --stage release --challenge-budget 0 \
  --cwd "$WORK/repo" --diff-file "$WORK/wording-punctuation.patch" \
  --implementer-family openai --review-plan-file "$WORK/review-plan.json" \
  --wording-only-proof-file "$WORK/wording-punctuation-proof.json")"; rc=$?
check "wording-only proof still requires independent semantic-boundary review" \
  '[ "$rc" = 2 ] && json_fields "$out" status=inconclusive reason_code=invalid_model_output'

reset_case passed unavailable unavailable
out="$(REVIEW_GATE_TEST_STATE="$WORK/state" "$WORK/harness/scripts/review_gate.sh" \
  --mode review --stage release --challenge-budget 0 \
  --cwd "$WORK/repo" --diff-file "$WORK/wording-punctuation.patch" \
  --implementer-family openai --review-plan-file "$WORK/review-plan.json" \
  --review-chain-id wording-chain --autonomous-review-index 1 \
  --wording-only-proof-file "$WORK/wording-punctuation-proof.json")"; rc=$?
check "wording-only single review cannot open a tracked review chain" \
  '[ "$rc" = 2 ] && [ ! -e "$WORK/state/client_sequence" ] && json_fields "$out" reason_code=wording_only_proof_invalid'

python3 - "$WORK/wording-punctuation-proof.json" \
  "$WORK/stale-wording-proof.json" "$WORK/extra-result-wording-proof.json" \
  "$WORK/noninteger-schema-wording-proof.json" \
  "$WORK/extra-check-wording-proof.json" \
  "$WORK/duplicate-top-wording-proof.json" \
  "$WORK/duplicate-check-wording-proof.json" <<'PY'
import json
from pathlib import Path
import sys

source = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
stale = json.loads(json.dumps(source))
stale["candidate_sha256"] = "0" * 64
Path(sys.argv[2]).write_text(json.dumps(stale), encoding="utf-8")
extra_result = json.loads(json.dumps(source))
extra_result["scope_result"] = {"status": "passed"}
Path(sys.argv[3]).write_text(json.dumps(extra_result), encoding="utf-8")
noninteger = json.loads(json.dumps(source))
noninteger["schema_version"] = 1.0
Path(sys.argv[4]).write_text(json.dumps(noninteger), encoding="utf-8")
extra_check = json.loads(json.dumps(source))
extra_check["check"]["result"] = "passed"
Path(sys.argv[5]).write_text(json.dumps(extra_check), encoding="utf-8")
source_text = json.dumps(source, sort_keys=True, separators=(",", ":"))
candidate_field = (
    '"candidate_sha256":' + json.dumps(source["candidate_sha256"])
)
Path(sys.argv[6]).write_text(
    source_text.replace(candidate_field, candidate_field + "," + candidate_field, 1),
    encoding="utf-8",
)
kind_field = '"kind":"markdown-punctuation-only"'
Path(sys.argv[7]).write_text(
    source_text.replace(kind_field, kind_field + "," + kind_field, 1),
    encoding="utf-8",
)
PY

for invalid_proof in stale-wording-proof extra-result-wording-proof noninteger-schema-wording-proof extra-check-wording-proof duplicate-top-wording-proof duplicate-check-wording-proof non-wording-proof; do
  reset_case passed unavailable unavailable
  packet="$WORK/wording-punctuation.patch"
  [ "$invalid_proof" != non-wording-proof ] || packet="$WORK/non-wording-punctuation.patch"
  out="$(REVIEW_GATE_TEST_STATE="$WORK/state" "$WORK/harness/scripts/review_gate.sh" \
    --mode review --stage release --challenge-budget 0 \
    --cwd "$WORK/repo" --diff-file "$packet" \
    --implementer-family openai --review-plan-file "$WORK/review-plan.json" \
    --wording-only-proof-file "$WORK/$invalid_proof.json")"; rc=$?
  check "$invalid_proof cannot waive release challenge" \
    '[ "$rc" = 2 ] && [ ! -e "$WORK/state/client_sequence" ] && json_fields "$out" reason_code=wording_only_proof_invalid'
done

python3 - "$WORK/wording-token-proof.json" "$WORK/surrogate-token-wording-proof.json" <<'PY'
import json
from pathlib import Path
import sys

proof = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
proof["check"]["old_token"] = "\ud800"
Path(sys.argv[2]).write_text(json.dumps(proof), encoding="utf-8")
PY
reset_case passed unavailable unavailable
out="$(REVIEW_GATE_TEST_STATE="$WORK/state" "$WORK/harness/scripts/review_gate.sh" \
  --mode review --stage release --challenge-budget 0 \
  --cwd "$WORK/repo" --diff-file "$WORK/wording-token.patch" \
  --implementer-family openai --review-plan-file "$WORK/review-plan.json" \
  --wording-only-proof-file "$WORK/surrogate-token-wording-proof.json" 2>/dev/null)"; rc=$?
check "a non-UTF-8 token proof fails as a structured gate result" \
  '[ "$rc" = 2 ] && [ ! -e "$WORK/state/client_sequence" ] && json_fields "$out" reason_code=wording_only_proof_invalid'

ln -s "$WORK/wording-punctuation-proof.json" "$WORK/linked-wording-proof.json"
reset_case passed unavailable unavailable
out="$(REVIEW_GATE_TEST_STATE="$WORK/state" "$WORK/harness/scripts/review_gate.sh" \
  --mode review --stage release --challenge-budget 0 \
  --cwd "$WORK/repo" --diff-file "$WORK/wording-punctuation.patch" \
  --implementer-family openai --review-plan-file "$WORK/review-plan.json" \
  --wording-only-proof-file "$WORK/linked-wording-proof.json")"; rc=$?
check "a linked wording-only proof cannot waive release challenge" \
  '[ "$rc" = 2 ] && [ ! -e "$WORK/state/client_sequence" ] && json_fields "$out" reason_code=wording_only_proof_invalid'
unlink "$WORK/linked-wording-proof.json"

python3 - "$WORK/oversized-wording-proof.json" <<'PY'
import os
from pathlib import Path
import sys

path = Path(sys.argv[1])
path.touch()
os.truncate(path, 16_001)
PY
reset_case passed unavailable unavailable
out="$(REVIEW_GATE_TEST_STATE="$WORK/state" "$WORK/harness/scripts/review_gate.sh" \
  --mode review --stage release --challenge-budget 0 \
  --cwd "$WORK/repo" --diff-file "$WORK/wording-punctuation.patch" \
  --implementer-family openai --review-plan-file "$WORK/review-plan.json" \
  --wording-only-proof-file "$WORK/oversized-wording-proof.json")"; rc=$?
check "an oversized wording-only proof cannot waive release challenge" \
  '[ "$rc" = 2 ] && [ ! -e "$WORK/state/client_sequence" ] && json_fields "$out" reason_code=wording_only_proof_invalid'

reset_case passed unavailable unavailable
out="$(run_gate --stage release --challenge-budget 0)"; rc=$?
check "release review without wording-only proof cannot waive its first challenge" \
  '[ "$rc" = 2 ] && [ ! -e "$WORK/state/client_sequence" ] && json_fields "$out" reason_code=invalid_input next_action=stop_reviewer_lane'

reset_case passed unavailable unavailable
out="$(run_gate --stage explore --risk-tag shared-gate --review-plan-file "$WORK/high-risk-plan.json" --challenge-budget 0)"; rc=$?
check "high-risk depth without wording-only proof cannot waive its first challenge" \
  '[ "$rc" = 2 ] && [ ! -e "$WORK/state/client_sequence" ] && json_fields "$out" reason_code=invalid_input next_action=stop_reviewer_lane'

reset_case findings unavailable unavailable
chain_round_one="$(run_gate --challenge-budget 2 --review-chain-id long-task --autonomous-review-index 1)"; chain_round_one_rc=$?
printf '%s\n' "$chain_round_one" >"$WORK/chain-round-one.json"
printf 'diff --git a/x b/x\n--- a/x\n+++ b/x\n@@ -1 +1 @@\n-b\n+c\n' >"$WORK/diff.patch"
python3 - "$WORK/chain-round-one.json" \
  "$WORK/chain-round-one-forged-controller.json" \
  "$WORK/chain-round-one-forged-skills.json" \
  "$WORK/chain-round-one-forged-skills-hash.json" <<'PY'
import json
from pathlib import Path
import sys

source = json.loads(Path(sys.argv[1]).read_text())
mutations = (
    ("review_controller_sha256", "0" * 64),
    ("selected_skills", ["testing-strategy"]),
    ("selected_skills_sha256", "0" * 64),
)
for target, (field, value) in zip(sys.argv[2:], mutations):
    result = json.loads(json.dumps(source))
    result[field] = value
    Path(target).write_text(json.dumps(result, separators=(",", ":")))
PY
for forged_case in controller skills skills-hash; do
  reset_case passed unavailable unavailable
  forged_file="$WORK/chain-round-one-forged-${forged_case}.json"
  out="$(run_challenge_gate --challenge-budget 2 --challenge-index 1 --focus "forged-${forged_case}" --review-chain-id long-task --autonomous-review-index 2 --prior-review-result-file "$forged_file")"; rc=$?
  check "a tracked round rejects forged prior ${forged_case} binding before provider execution" \
    '[ "$rc" = 2 ] && [ ! -e "$WORK/state/client_sequence" ] && json_fields "$out" reason_code=review_chain_invalid'
done
reset_case passed unavailable unavailable
chain_round_two="$(run_challenge_gate --challenge-budget 2 --challenge-index 1 --focus corrected-path --review-chain-id long-task --autonomous-review-index 2 --prior-review-result-file "$WORK/chain-round-one.json")"; chain_round_two_rc=$?
printf '%s\n' "$chain_round_two" >"$WORK/chain-round-two.json"
check "a finding-bearing older candidate remains consumed in the same Agent review chain" \
  '[ "$chain_round_one_rc" = 0 ] && [ "$chain_round_two_rc" = 0 ] && json_fields "$chain_round_two" review_chain_tracked=true review_chain_id=long-task autonomous_review_index=2 autonomous_reviews_remaining=1 prior_review_result_sha256.0='"$(shasum -a 256 "$WORK/chain-round-one.json" | awk '{print $1}')"' self_review_gate.satisfied_triggers.0=before_external_review self_review_gate.satisfied_triggers.1=material_candidate_change'

reset_case passed unavailable unavailable
out="$(run_completion_gate --challenge-budget 2 --completion-review-result-file "$WORK/chain-round-two.json")"; rc=$?
check "a clean tracked challenge may close before exhausting its maximum review budget" \
  '[ "$rc" = 0 ] && [ ! -e "$WORK/state/client_sequence" ] && json_fields "$out" mode=complete status=passed review_chain_tracked=true review_chain_id=long-task autonomous_review_budget=3 autonomous_review_index=2 autonomous_reviews_remaining=1 autonomous_review_allowed=false completion_gated=false'

python3 - "$WORK/chain-round-two.json" \
  "$WORK/chain-round-two-forged-controller.json" \
  "$WORK/chain-round-two-forged-skills.json" \
  "$WORK/chain-round-two-forged-skills-hash.json" \
  "$WORK/chain-round-two-forged-selection-source.json" <<'PY'
import json
from pathlib import Path
import sys

source = json.loads(Path(sys.argv[1]).read_text())
mutations = (
    ("review_controller_sha256", "0" * 64),
    ("selected_skills", ["testing-strategy"]),
    ("selected_skills_sha256", "0" * 64),
    ("owner_selection_source", "spoofed-source"),
)
for target, (field, value) in zip(sys.argv[2:], mutations):
    result = json.loads(json.dumps(source))
    result[field] = value
    Path(target).write_text(json.dumps(result, separators=(",", ":")))
PY
for forged_case in controller skills skills-hash selection-source; do
  reset_case passed unavailable unavailable
  out="$(run_completion_gate --challenge-budget 2 --completion-review-result-file "$WORK/chain-round-two-forged-${forged_case}.json")"; rc=$?
  check "the completion checkpoint rejects a forged ${forged_case} binding" \
    '[ "$rc" = 2 ] && [ ! -e "$WORK/state/client_sequence" ] && json_fields "$out" reason_code=completion_checkpoint_invalid completion_gated=true'
done

reset_case passed unavailable unavailable
out="$(run_completion_gate --review-plan-file "$WORK/changed-acceptance-plan.json" --challenge-budget 2 --completion-review-result-file "$WORK/chain-round-two.json")"; rc=$?
check "a tracked completion checkpoint rejects changed acceptance" \
  '[ "$rc" = 2 ] && [ ! -e "$WORK/state/client_sequence" ] && json_fields "$out" reason_code=completion_checkpoint_invalid completion_gated=true'

reset_case passed unavailable unavailable
out="$(run_challenge_gate --review-plan-file "$WORK/changed-review-plan.json" --challenge-budget 2 --challenge-index 1 --focus changed-scope --review-chain-id long-task --autonomous-review-index 2 --prior-review-result-file "$WORK/chain-round-one.json")"; rc=$?
check "tracked scope escalation requires deep self-review and a task reframe before another external review" \
  '[ "$rc" = 2 ] && [ ! -e "$WORK/state/client_sequence" ] && json_fields "$out" reason_code=review_scope_changed next_action=deep_self_review_and_request_task_reframe self_review_gate.required=true self_review_gate.required_triggers.0=risk_or_scope_escalation self_review_gate.blocks.0=external_review self_review_gate.allowed_next_actions.2=request_human_decision'

reset_case passed unavailable unavailable
passed_round_one="$(run_gate --challenge-budget 2 --review-chain-id passed-task --autonomous-review-index 1)"; passed_round_one_rc=$?
printf '%s\n' "$passed_round_one" >"$WORK/passed-round-one.json"
check "a passed first tracked round still owes its challenge before completion" \
  '[ "$passed_round_one_rc" = 0 ] && json_fields "$passed_round_one" status=passed autonomous_review_index=1 autonomous_reviews_remaining=2 autonomous_review_allowed=true next_action=run_challenge completion_gated=true'

python3 - "$WORK/passed-round-one.json" "$WORK/chain-round-two.json" \
  "$WORK/round-one-forged-final-shape.json" \
  "$WORK/round-two-forged-final-shape.json" <<'PY'
import json
from pathlib import Path
import sys

final_gate = {
    "required": True,
    "required_triggers": ["before_completion_claim"],
    "blocks": ["completion_claim"],
    "allowed_next_actions": ["deep_self_review", "continue_implementation"],
}
for source_path, target_path in zip(sys.argv[1:3], sys.argv[3:5]):
    source = json.loads(Path(source_path).read_text())
    result = json.loads(json.dumps(source))
    result["next_action"] = "deep_self_review_before_completion"
    gate = dict(final_gate)
    gate["satisfied_triggers"] = source["self_review_gate"]["satisfied_triggers"]
    result["self_review_gate"] = gate
    Path(target_path).write_text(json.dumps(result, separators=(",", ":")))
PY
for forged_round in one two; do
  reset_case passed unavailable unavailable
  out="$(run_completion_gate --challenge-budget 2 --completion-review-result-file "$WORK/round-${forged_round}-forged-final-shape.json")"; rc=$?
  check "the completion checkpoint rejects a final-round shape while autonomous reviews remain (round ${forged_round})" \
    '[ "$rc" = 2 ] && [ ! -e "$WORK/state/client_sequence" ] && json_fields "$out" reason_code=completion_checkpoint_invalid completion_gated=true'
done

python3 - "$WORK/chain-round-one.json" \
  "$WORK/round-one-forged-scope-depth.json" \
  "$WORK/round-one-forged-scope-tags.json" \
  "$WORK/round-one-forged-scope-stage.json" \
  "$WORK/round-one-forged-scope-budget.json" <<'PY'
import json
from pathlib import Path
import sys

source = json.loads(Path(sys.argv[1]).read_text())
mutations = (
    ("review_depth", "release"),
    ("risk_tags", ["shared-gate"]),
    ("stage", "explore"),
    ("challenge_budget", 5),
)
for target, (field, value) in zip(sys.argv[2:], mutations):
    result = json.loads(json.dumps(source))
    result[field] = value
    Path(target).write_text(json.dumps(result, separators=(",", ":")))
PY
for forged_scope in depth tags stage budget; do
  reset_case passed unavailable unavailable
  out="$(run_challenge_gate --challenge-budget 2 --challenge-index 1 --focus "scope-${forged_scope}" --review-chain-id long-task --autonomous-review-index 2 --prior-review-result-file "$WORK/round-one-forged-scope-${forged_scope}.json")"; rc=$?
  check "a tracked round rejects a prior scope field contradicting the copied scope digest (${forged_scope})" \
    '[ "$rc" = 2 ] && [ ! -e "$WORK/state/client_sequence" ] && json_fields "$out" reason_code=review_chain_invalid'
done

python3 - "$WORK/chain-round-one.json" \
  "$WORK/round-one-forged-inner-intent.json" \
  "$WORK/round-one-forged-inner-acceptance.json" \
  "$WORK/round-one-forged-inner-schema.json" \
  "$WORK/round-one-forged-inner-missing.json" <<'PY'
import json
from pathlib import Path
import sys

source = json.loads(Path(sys.argv[1]).read_text())
mutations = (
    ("intent_sha256", "f" * 64),
    ("acceptance_sha256", "e" * 64),
    ("schema_version", 99),
    (None, None),
)
for target, (field, value) in zip(sys.argv[2:], mutations):
    result = json.loads(json.dumps(source))
    if field is None:
        result.pop("review_scope", None)
    else:
        result["review_scope"][field] = value
    Path(target).write_text(json.dumps(result, separators=(",", ":")))
PY
for forged_inner in intent acceptance schema missing; do
  reset_case passed unavailable unavailable
  out="$(run_challenge_gate --challenge-budget 2 --challenge-index 1 --focus "inner-${forged_inner}" --review-chain-id long-task --autonomous-review-index 2 --prior-review-result-file "$WORK/round-one-forged-inner-${forged_inner}.json")"; rc=$?
  check "a tracked round rejects a prior whose recorded scope does not produce its own digest (${forged_inner})" \
    '[ "$rc" = 2 ] && [ ! -e "$WORK/state/client_sequence" ] && json_fields "$out" reason_code=review_chain_invalid'
done

# Built from chain-round-two, the prior the completion checkpoint otherwise ACCEPTS
# (early-challenge close, remaining=1). Forging a findings-bearing or
# challenge-owing prior instead would be rejected by an unrelated existing check,
# leaving this assertion vacuous.
python3 - "$WORK/chain-round-two.json" "$WORK/round-two-forged-inner-intent.json" <<'PY'
import json
from pathlib import Path
import sys

result = json.loads(Path(sys.argv[1]).read_text())
result["review_scope"]["intent_sha256"] = "f" * 64
Path(sys.argv[2]).write_text(json.dumps(result, separators=(",", ":")))
PY
reset_case passed unavailable unavailable
out="$(run_completion_gate --challenge-budget 2 --completion-review-result-file "$WORK/round-two-forged-inner-intent.json")"; rc=$?
check "the completion checkpoint rejects a prior whose recorded scope does not produce its own digest" \
  '[ "$rc" = 2 ] && [ ! -e "$WORK/state/client_sequence" ] && json_fields "$out" reason_code=completion_checkpoint_invalid completion_gated=true'

# Both samples are built from priors the gate otherwise ACCEPTS, so removing the
# guard under test actually turns these red rather than tripping an unrelated check.
python3 - "$WORK/chain-round-two.json" "$WORK/round-two-legacy-envelope.json" <<'PY'
import json
from pathlib import Path
import sys

# A legacy envelope: previous schema version, and no recorded review scope.
two = json.loads(Path(sys.argv[1]).read_text())
two["schema_version"] = 2
two.pop("review_scope", None)
Path(sys.argv[2]).write_text(json.dumps(two, separators=(",", ":")))
PY

# The boolean impersonation only bites when the CURRENT budget is 1 (True == 1),
# so the prior must come from a budget-1 chain; reusing the budget-2 prior would
# change the current scope digest and trip review_scope_changed first, leaving
# the type guard untested.
reset_case passed unavailable unavailable
budget_one_round_one="$(run_gate --challenge-budget 1 --review-chain-id bool-task --autonomous-review-index 1)"; budget_one_rc=$?
printf '%s\n' "$budget_one_round_one" >"$WORK/budget-one-round-one.json"
check "a budget-one first tracked round renders before the boolean probe" \
  '[ "$budget_one_rc" = 0 ] && json_fields "$budget_one_round_one" status=passed challenge_budget=1 autonomous_review_index=1'

python3 - "$WORK/budget-one-round-one.json" "$WORK/budget-one-bool-budget.json" <<'PY'
import json
from pathlib import Path
import sys

# A JSON boolean must not satisfy an integer budget: Python's True == 1. The
# nested canonical scope is left intact so its digest still verifies.
result = json.loads(Path(sys.argv[1]).read_text())
result["challenge_budget"] = True
Path(sys.argv[2]).write_text(json.dumps(result, separators=(",", ":")))
PY
reset_case passed unavailable unavailable
out="$(run_challenge_gate --challenge-budget 1 --challenge-index 1 --focus bool-budget --review-chain-id bool-task --autonomous-review-index 2 --prior-review-result-file "$WORK/budget-one-bool-budget.json")"; rc=$?
check "a JSON boolean cannot impersonate the integer challenge budget of a tracked prior" \
  '[ "$rc" = 2 ] && [ ! -e "$WORK/state/client_sequence" ] && json_fields "$out" reason_code=review_chain_invalid'

reset_case passed unavailable unavailable
out="$(run_completion_gate --challenge-budget 2 --completion-review-result-file "$WORK/round-two-legacy-envelope.json")"; rc=$?
check "a legacy pre-scope envelope is rejected instead of being read as a malformed current result" \
  '[ "$rc" = 2 ] && [ ! -e "$WORK/state/client_sequence" ] && json_fields "$out" reason_code=completion_checkpoint_invalid completion_gated=true'

# The per-invocation budget must cover a real reviewer run: measured lane costs
# on this repository's own diffs were roughly 89s, 247s, and 419s, so a default
# below those silently converts a working lane into an inconclusive timeout.
# Intentionally omit both timeout flags: this is the end-to-end default path,
# not only a parser-default assertion.
reset_case passed unavailable unavailable
out="$(run_gate)"; rc=$?
check "the default cumulative budget leaves the default 600-second invocation uncapped" \
  '[ "$rc" = 0 ] && [ "$(cat "$WORK/state/claude_timeout")" = 600 ] && json_fields "$out" status=passed selected_client=claude'

reset_case passed unavailable unavailable
out="$(run_gate --timeout 90)"; rc=$?
check "an explicit budget still overrides the default" \
  '[ "$rc" = 0 ] && [ "$(cat "$WORK/state/claude_timeout")" = 90 ]'

reset_case passed unavailable unavailable
out="$(run_gate --timeout 1200 --total-timeout 3600)"; rc=$?
check "the generic timeout accepts and forwards the documented 1200-second ceiling" \
  '[ "$rc" = 0 ] && [ "$(cat "$WORK/state/claude_timeout")" = 1200 ] && json_fields "$out" status=passed selected_client=claude'

reset_case passed unavailable unavailable
out="$(run_gate --timeout 1201 --total-timeout 3600)"; rc=$?
check "the generic timeout rejects a value above the documented ceiling before client execution" \
  '[ "$rc" = 2 ] && [ ! -e "$WORK/state/client_sequence" ] && json_fields "$out" reason_code=invalid_input'

# The gate always passes --timeout, which overrides each wrapper's own default,
# so the assertions above cannot see the direct-invocation defaults at all. Pin
# each declared default separately or three of the four silently regress.
wrapper_defaults_ok=1
wrapper_defaults_seen=0
for wrapper_default in \
  'claude_review.sh:^timeout_s=600$' \
  'codex_review.sh:^TIMEOUT=600$' \
  'kimi_review.sh:^TIMEOUT=600$' \
  'opencode_review.sh:^BASE=.*; TIMEOUT="600"$'; do
  wrapper_file="${wrapper_default%%:*}"
  wrapper_pattern="${wrapper_default#*:}"
  if grep -qE "$wrapper_pattern" "$DIR/$wrapper_file"; then
    wrapper_defaults_seen=$((wrapper_defaults_seen + 1))
  else
    wrapper_defaults_ok=0
    printf 'wrapper default drift: %s does not declare %s\n' "$wrapper_file" "$wrapper_pattern" >&2
  fi
done
check "every wrapper declares the same direct-invocation budget as the gate default" \
  '[ "$wrapper_defaults_ok" = 1 ] && [ "$wrapper_defaults_seen" = 4 ]'

# Direct wrapper invocations share one decimal-string normalizer. Exercise the
# boundary itself rather than grepping arithmetic fragments: shell integer
# overflow used to make a 50-digit timeout bypass Claude's clamp and fail the
# other three clients as invalid input.
# shellcheck source=normalize_review_timeout.sh
. "$DIR/normalize_review_timeout.sh"
wrapper_timeout_inputs_match=1
while IFS='|' read -r input expected; do
  actual="$(normalize_review_timeout "$input")" || actual="invalid"
  if [ "$actual" != "$expected" ]; then
    wrapper_timeout_inputs_match=0
    printf 'wrapper timeout normalization drift: %s -> %s, want %s\n' \
      "$input" "$actual" "$expected" >&2
  fi
done <<'EOF'
4|invalid
5|5
1200|1200
1201|1200
99999999999999999999999999999999999999999999999999|1200
EOF
wrapper_timeout_bindings_match=1
wrapper_timeout_bindings_seen=0
for wrapper_file in claude_review.sh codex_review.sh kimi_review.sh opencode_review.sh; do
  if grep -qF 'normalize_review_timeout "$' "$DIR/$wrapper_file"; then
    wrapper_timeout_bindings_seen=$((wrapper_timeout_bindings_seen + 1))
  else
    wrapper_timeout_bindings_match=0
    printf 'wrapper timeout binding drift: %s does not call the shared normalizer\n' \
      "$wrapper_file" >&2
  fi
done
check "every wrapper accepts and clamps the full decimal-string timeout domain" \
  '[ "$wrapper_timeout_inputs_match" = 1 ] && [ "$wrapper_timeout_bindings_match" = 1 ] && [ "$wrapper_timeout_bindings_seen" = 4 ]'

parser_total_timeout="$(python3 - "$DIR/review_gate.py" "$WORK" <<'PY'
import importlib.util
from pathlib import Path
import sys
import time

spec = importlib.util.spec_from_file_location("review_gate", sys.argv[1])
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)
real_monotonic = module.time.monotonic
args = module.build_parser().parse_args([
    "--mode", "review",
    "--cwd", "/tmp",
    "--implementer-family", "openai",
    "--review-plan-file", "/tmp/plan.json",
])
print(args.total_timeout)
module.time.monotonic = lambda: 95.9
print(module.remaining_gate_seconds(100.0))
print(
    module.invocation_timeout_seconds(600, 90, "review"),
    module.invocation_timeout_seconds(600, 90, "challenge"),
    module.invocation_timeout_seconds(600, 20, "review"),
    module.invocation_timeout_seconds(600, 19, "review"),
)
print(
    module.reviewer_lane_timeout_seconds(5, 50, "review"),
    module.reviewer_lane_timeout_seconds(600, 90, "review"),
)
captured_git_timeout = []
real_run = module.run
module.run = lambda command, **kwargs: (
    captured_git_timeout.append(kwargs.get("timeout_seconds"))
    or module.subprocess.CompletedProcess(command, 0, b"ok", b"")
)
assert module.git_output(Path(sys.argv[2]), ["status"], deadline=100.0) == b"ok"
assert captured_git_timeout == [4]
module.time.monotonic = lambda: 100.0
try:
    module.remaining_preflight_seconds(100.0)
except module.GateError as exc:
    assert exc.reason_code == "gate_timeout"
else:
    raise AssertionError("expired preflight budget was accepted")
module.run = real_run
module.time.monotonic = real_monotonic
print("preflight_deadline_ok")

real_freeze_packet = module.freeze_packet
real_emit = module.emit

def expired_freeze(*args, **kwargs):
    raise module.GateError(
        "review gate exhausted its total wall-clock budget", "gate_timeout"
    )

module.freeze_packet = expired_freeze
module.emit = lambda payload, exit_code: (payload, exit_code)
preflight_expired, preflight_expired_code = module.main([
    "--mode", "review",
    "--cwd", "/tmp",
    "--diff-file", "/tmp/diff.patch",
    "--implementer-family", "openai",
    "--review-plan-file", "/tmp/plan.json",
])
assert preflight_expired_code == 2
assert preflight_expired["reason_code"] == "gate_timeout"
assert preflight_expired["review_state"] == "self_reviewing"
assert preflight_expired["completion_gated"] is True
assert preflight_expired["self_review_gate"]["required_triggers"] == [
    "post_review_budget_checkpoint"
]
assert preflight_expired["self_review_gate"]["blocks"] == [
    "external_review",
    "completion_claim",
]
module.freeze_packet = real_freeze_packet
module.emit = real_emit
print("preflight_envelope_ok")

tree_pid_file = Path(sys.argv[2]) / "state" / "fallback_tree_child_pid"
tree_process = module.subprocess.Popen(
    [
        sys.executable,
        "-c",
        """
import os
import signal
import sys

signal.signal(signal.SIGTERM, signal.SIG_IGN)
child_pid = os.fork()
if child_pid == 0:
    with open(sys.argv[1], "w", encoding="utf-8") as pid_file:
        pid_file.write(str(os.getpid()))
    while True:
        signal.pause()
while True:
    signal.pause()
""",
        str(tree_pid_file),
    ],
    stdout=module.subprocess.PIPE,
    stderr=module.subprocess.PIPE,
    start_new_session=True,
)
tree_child_text = ""
for _ in range(100):
    if tree_pid_file.exists():
        tree_child_text = tree_pid_file.read_text().strip()
        if tree_child_text:
            break
    time.sleep(0.01)
assert tree_child_text
tree_child_pid = int(tree_child_text)
real_killpg = module.os.killpg
killpg_calls = 0

def transient_killpg(pgid, signal_value):
    global killpg_calls
    killpg_calls += 1
    if killpg_calls <= 2:
        raise PermissionError()
    real_killpg(pgid, signal_value)

module.os.killpg = transient_killpg
module.signal_reviewer_process_group(
    tree_process, module.signal.SIGKILL, tree_process.pid
)
tree_process.communicate(timeout=2)
tree_child_gone = False
for _ in range(100):
    try:
        module.os.kill(tree_child_pid, 0)
    except ProcessLookupError:
        tree_child_gone = True
        break
    time.sleep(0.01)
assert tree_child_gone
print("tree_fallback_ok")

class TimedOutProcess:
    pid = 12345
    returncode = None
    terminated = False
    killed = False
    polled = False
    waited = False
    communicate_calls = 0

    class Pipe:
        closed = False

        def close(self):
            self.closed = True

    stdout = Pipe()
    stderr = Pipe()

    def communicate(self, timeout):
        self.communicate_calls += 1
        if self.communicate_calls == 1:
            raise module.subprocess.TimeoutExpired(["reviewer"], timeout)
        raise OSError("cleanup pipe race")

    def terminate(self):
        self.terminated = True

    def kill(self):
        self.killed = True

    def poll(self):
        self.polled = True
        return -9

    def wait(self, timeout):
        self.waited = True
        raise module.subprocess.TimeoutExpired(["reviewer"], timeout)

timed_out_process = TimedOutProcess()
module.subprocess.Popen = lambda *args, **kwargs: timed_out_process
module.os.killpg = lambda *args, **kwargs: (_ for _ in ()).throw(PermissionError())
try:
    module.run(["reviewer"], timeout_seconds=5)
except module.GateError as exc:
    print(exc.reason_code)
print(
    timed_out_process.terminated,
    timed_out_process.killed,
    timed_out_process.waited,
    timed_out_process.polled,
    timed_out_process.stdout.closed,
    timed_out_process.stderr.closed,
)

class PostLaunchIoErrorProcess:
    pid = 12346
    returncode = None
    stdout = None
    stderr = None

    def communicate(self, timeout):
        raise OSError("reviewer pipe failed")

module.subprocess.Popen = lambda *args, **kwargs: PostLaunchIoErrorProcess()
try:
    module.run(["reviewer"], timeout_seconds=5)
except module.GateError as exc:
    assert exc.reason_code == "local_process_io_failure"
    assert "subprocess I/O failed after starting" in exc.reason
else:
    raise AssertionError("post-launch reviewer I/O failure was accepted")
print("post_launch_io_ok")

class TermGraceProcess:
    pid = 12347
    returncode = None
    stdout = None
    stderr = None
    communicate_calls = 0

    def communicate(self, timeout):
        self.communicate_calls += 1
        if self.communicate_calls == 1:
            raise module.subprocess.TimeoutExpired(["reviewer"], timeout)
        return b"", b""

term_grace_process = TermGraceProcess()
signals = []
module.subprocess.Popen = lambda *args, **kwargs: term_grace_process
module.signal_reviewer_process_group = (
    lambda process, signal_value, recorded_pgid=None: signals.append(signal_value)
)
try:
    module.run(["reviewer"], timeout_seconds=5)
except module.GateError as exc:
    assert exc.reason_code == "gate_timeout"
else:
    raise AssertionError("timed-out reviewer was accepted")
assert signals == [module.signal.SIGTERM, module.signal.SIGKILL]
print("kill_after_term_grace_ok")

module.time.monotonic = lambda: 101.0
module.emit = lambda payload, exit_code: (payload, exit_code)
expired, expired_code = module.emit_with_gate_deadline(
    {
        "status": "findings",
        "selected_client": "claude",
        "selected_reviewer": "claude",
        "selected_attempt_index": 0,
        "findings": [{"severity": "P1"}],
        "concern_results": [{"concern": "correctness"}],
        "reviewed_concerns": ["correctness"],
        "reviewed_skills": ["code-review"],
        "findings_require_implementer_self_review": True,
        "human_decision_required": True,
        "review_state": "reviewed",
        "completion_gated": False,
    },
    0,
    100.0,
)
assert expired_code == 2
assert expired["status"] == "inconclusive"
assert expired["reason_code"] == "gate_timeout"
assert expired["fallback_eligible"] is False
assert expired["selected_client"] is None
assert expired["findings"] == []
assert expired["unbound_findings"] == [{"severity": "P1"}]
assert expired["concern_results"] == []
assert expired["findings_require_implementer_self_review"] is False
assert expired["human_decision_required"] is False
assert expired["review_state"] == "self_reviewing"
assert expired["completion_gated"] is True
assert expired["self_review_gate"]["required"] is True
assert expired["self_review_gate"]["required_triggers"] == [
    "post_review_budget_checkpoint"
]
assert expired["self_review_gate"]["blocks"] == [
    "external_review",
    "completion_claim",
]
module.time.monotonic = lambda: 99.1
near_deadline, near_deadline_code = module.emit_with_gate_deadline(
    {"status": "passed"}, 0, 100.0
)
assert near_deadline_code == 0
assert near_deadline["status"] == "passed"
print("post_deadline_ok")
PY
)"
check "the gate declares a finite cumulative default and floors the remaining budget" \
  '[ "$parser_total_timeout" = "2400
4
40 80 5 4
20 90
preflight_deadline_ok
preflight_envelope_ok
tree_fallback_ok
gate_timeout
True True True True True True
post_launch_io_ok
kill_after_term_grace_ok
post_deadline_ok" ]'

check "the staged contract declares the current result schema" \
  'grep -q "current result envelope is schema 3" "$DIR/../references/staged-review-contract.md"'

reset_case passed unavailable unavailable
out="$(run_gate --timeout 600 --total-timeout 90)"; rc=$?
claude_timeout="$(cat "$WORK/state/claude_timeout" 2>/dev/null || true)"
check "the remaining total budget caps the wrapper timeout" \
  '[ "$rc" = 0 ] && [ "$claude_timeout" -ge 5 ] && [ "$claude_timeout" -le 40 ]'

reset_case quota_slow passed unavailable unavailable
out="$(run_gate --allow-fallback-egress --total-timeout 25)"; rc=$?
kimi_timeout="$(cat "$WORK/state/kimi_timeout" 2>/dev/null || true)"
check "a fallback receives only the remaining cumulative budget" \
  '[ "$rc" = 0 ] && [ "$kimi_timeout" -ge 5 ] && [ "$kimi_timeout" -lt 12 ] && json_fields "$out" selected_client=kimi'

reset_case quota_slow hang unavailable unavailable
out="$(run_gate --allow-fallback-egress --total-timeout 25)"; rc=$?
kimi_timeout="$(cat "$WORK/state/kimi_timeout" 2>/dev/null || true)"
check "a started fallback that exhausts the remaining budget cannot starve a later lane" \
  '[ "$rc" = 2 ] && [ "$kimi_timeout" -ge 5 ] && [ "$kimi_timeout" -lt 12 ] && [ ! -e "$WORK/state/opencode_timeout" ] && json_fields "$out" status=inconclusive fallback_eligible=false reason_code=gate_timeout next_action=stop_reviewer_lane'

reset_case quota_slow passed unavailable unavailable
out="$(run_gate --allow-fallback-egress --total-timeout 5)"; rc=$?
check "the gate does not start a fallback with less than the wrapper minimum remaining" \
  '[ "$rc" = 2 ] && [ ! -e "$WORK/state/kimi_timeout" ] && json_fields "$out" status=inconclusive fallback_eligible=false reason_code=gate_timeout review_state=self_reviewing completion_gated=true self_review_gate.required=true self_review_gate.required_triggers.0=post_review_budget_checkpoint self_review_gate.blocks.0=external_review self_review_gate.blocks.1=completion_claim next_action=stop_reviewer_lane'

reset_case quota_slow passed unavailable unavailable
out="$(run_gate --allow-fallback-egress --total-timeout 22)"; rc=$?
check "a primary may consume the usable budget without starting a doomed fallback" \
  '[ "$rc" = 2 ] && [ -e "$WORK/state/claude_timeout" ] && [ ! -e "$WORK/state/kimi_timeout" ] && json_fields "$out" status=inconclusive fallback_eligible=false reason_code=gate_timeout next_action=stop_reviewer_lane'

reset_case hang passed unavailable unavailable
out="$(run_gate --diff-file "$WORK/secret-diff.patch" --timeout 5 --total-timeout 50)"; rc=$?
hang_child_pid="$(cat "$WORK/state/hang_child_pid" 2>/dev/null || true)"
hang_child_gone=0
if [ -n "$hang_child_pid" ]; then
  if ! kill -0 "$hang_child_pid" 2>/dev/null; then
    hang_child_gone=1
  elif ps -o stat= -p "$hang_child_pid" 2>/dev/null | grep -q '^Z'; then
    hang_child_gone=1
  fi
fi
check "a timed-out primary cannot bypass fallback egress authorization" \
  '[ "$rc" = 2 ] && [ "$hang_child_gone" = 1 ] && [ ! -e "$WORK/state/kimi_timeout" ] && [ ! -e "$WORK/state/opencode_timeout" ] && json_fields "$out" status=inconclusive reason_code=egress_denied next_action=stop_reviewer_lane'

reset_case hang passed unavailable unavailable
out="$(run_gate --allow-fallback-egress --timeout 5 --total-timeout 50)"; rc=$?
hang_child_pid="$(cat "$WORK/state/hang_child_pid" 2>/dev/null || true)"
hang_child_gone=0
if [ -n "$hang_child_pid" ]; then
  if ! kill -0 "$hang_child_pid" 2>/dev/null; then
    hang_child_gone=1
  elif ps -o stat= -p "$hang_child_pid" 2>/dev/null | grep -q '^Z'; then
    hang_child_gone=1
  fi
fi
check "a timed-out primary lane leaves total budget for an independent fallback" \
  '[ "$rc" = 0 ] && [ "$hang_child_gone" = 1 ] && [ -e "$WORK/state/kimi_timeout" ] && json_fields "$out" status=passed selected_client=kimi && [ "$(printf "%s" "$out" | python3 -c "import json,sys; value=json.load(sys.stdin); print(len(value[\"attempts\"]), sum(item.get(\"reason_code\") == \"timeout\" for item in value[\"skipped_clients\"]))")" = "2 1" ]'

reset_case hang passed unavailable unavailable
out="$(run_challenge_gate --allow-fallback-egress --focus process-group-timeout --total-timeout 16)"; rc=$?
hang_child_pid="$(cat "$WORK/state/hang_child_pid" 2>/dev/null || true)"
hang_child_gone=0
if [ -n "$hang_child_pid" ]; then
  if ! kill -0 "$hang_child_pid" 2>/dev/null; then
    hang_child_gone=1
  elif ps -o stat= -p "$hang_child_pid" 2>/dev/null | grep -q '^Z'; then
    hang_child_gone=1
  fi
fi
hang_envelope_ok=0
if json_fields "$out" status=inconclusive fallback_eligible=false reason_code=gate_timeout next_action=stop_reviewer_lane; then
  hang_envelope_ok=1
fi
if [ "$rc" != 2 ] || [ "$hang_child_gone" != 1 ] || [ -e "$WORK/state/kimi_timeout" ] || [ "$hang_envelope_ok" != 1 ]; then
  printf 'hang diagnostic: rc=%s child_pid=%s child_gone=%s kimi_started=%s envelope_ok=%s out=%s\n' \
    "$rc" "$hang_child_pid" "$hang_child_gone" "$([ -e "$WORK/state/kimi_timeout" ] && printf yes || printf no)" "$hang_envelope_ok" "$out" >&2
fi
check "the controller terminates an over-budget wrapper process group" \
  '[ "$rc" = 2 ] && [ "$hang_child_gone" = 1 ] && [ ! -e "$WORK/state/kimi_timeout" ] && [ "$hang_envelope_ok" = 1 ]'

reset_case escaped_hang passed unavailable unavailable
escaped_started_at="$(date +%s)"
# Run the gate asynchronously under a watchdog independent of it: a regressed
# envelope that waits for the descendant's pipes would otherwise park this case
# for that descendant's whole lifetime before any elapsed check could fail.
escaped_out_file="$WORK/escaped-out.json"
run_challenge_gate --allow-fallback-egress --focus escaped-pipe-timeout --total-timeout 16 >"$escaped_out_file" 2>/dev/null &
escaped_gate_pid=$!
escaped_gate_deadline="$(( escaped_started_at + 120 ))"
escaped_watchdog_fired=0
while kill -0 "$escaped_gate_pid" 2>/dev/null; do
  if [ "$(date +%s)" -ge "$escaped_gate_deadline" ]; then
    escaped_watchdog_fired=1
    kill -KILL "$escaped_gate_pid" 2>/dev/null || true
    break
  fi
  sleep 1
done
wait "$escaped_gate_pid"; rc=$?
escaped_returned_at="$(date +%s)"
# Drop the marker the descendant is watching for BEFORE anything else, so what it
# witnesses is the gate's return and not this test's bookkeeping.
: >"$WORK/state/escaped_gate_returned"
out="$(cat "$escaped_out_file" 2>/dev/null || true)"
escaped_elapsed="$(( $(date +%s) - escaped_started_at ))"
escaped_child_pid="$(cat "$WORK/state/escaped_hang_child_pid" 2>/dev/null || true)"
escaped_child_trap_pid="$escaped_child_pid"
# Audit copy, in a directory neither this case nor reset_case clears: the working pid
# file below is removed as part of this case's own cleanup, so a mutation that disables
# the kill while leaving the removal in place would erase the only handle the exit
# assertion could have used.
mkdir -p "$WORK/state/audit" 2>/dev/null || true
printf '%s %s\n' "$escaped_child_pid" \
  "$(ps -o lstart= -p "$escaped_child_pid" 2>/dev/null || true)" \
  >"$WORK/state/audit/escaped_pid" 2>/dev/null || true
# Read the beat BEFORE the liveness probe so a descendant that dies between the two
# still reports how far it got; empty means it never reached its own setsid.
# Wait for the descendant to TESTIFY, not for time to pass: a live holder stamps
# the witness within one beat interval, so this loop ends immediately on a healthy
# run and only burns its bound when there is nothing alive to answer — which is
# itself the failure this case must report.
escaped_witness_deadline="$(( $(date +%s) + 5 ))"
while :; do
  escaped_child_beat="$(tr -d '\n' <"$WORK/state/escaped_hang_child_beat" 2>/dev/null || true)"
  case "$escaped_child_beat" in *witnessed=1*) break ;; esac
  [ "$(date +%s)" -ge "$escaped_witness_deadline" ] && break
  sleep 1
done
escaped_test_sid="$(ps -o sess= -p $$ 2>/dev/null | tr -d ' ' || true)"
escaped_wrapper_pid="$(cat "$WORK/state/escaped_hang_wrapper_pid" 2>/dev/null || true)"
# What this case must prove is that the terminal envelope did not WAIT for the
# escaped descendant to release the reviewer pipes, and two facts already prove it
# without asking anything of the runner's timing: the descendant really escaped its
# wrapper's session (so it still held those pipes), and the gate came back on its
# own — watchdog_fired=0 means it returned inside 120s while the descendant's own
# lifetime is 300s, so a gate that waited on the pipes could not have produced this
# run. Detachment is read structurally from the beat the descendant wrote after its
# own setsid: its session id equals its pid exactly when setsid took effect.
#
# The two oracles this replaces both asserted things no runner owes us. Probing
# liveness *now* assumes nothing reaps a detached process between the gate's return
# and this line — a host that reaps promptly then fails a gate that behaved
# correctly (observed in CI: child gone, wrapper gone, envelope correct). Comparing
# the last beat's clock against the return instant fails for a subtler reason: the
# beat lags by up to its interval, so at one-second resolution a healthy run and a
# descendant killed with its wrapper are indistinguishable — both land one second
# before the return (measured: control at=...987 vs return ...988; mutant at=...817
# vs return ...818). Sub-second stamps would only narrow that gap, not close it.
escaped_child_beat_pid="${escaped_child_beat##* pid=}"
escaped_child_beat_pid="${escaped_child_beat_pid%% *}"
escaped_child_beat_sid="${escaped_child_beat##* sid=}"
escaped_child_beat_sid="${escaped_child_beat_sid%% *}"
escaped_child_detached=0
case "$escaped_child_beat_pid$escaped_child_beat_sid" in
  ''|*[!0-9]*) : ;;
  *) [ "$escaped_child_beat_sid" = "$escaped_child_beat_pid" ] && escaped_child_detached=1 ;;
esac
# Detachment alone would let the case pass without exercising itself: a controller
# that kills the detached descendant and only THEN waits for the reviewer pipes
# gets EOF immediately, returns well inside the watchdog, and satisfies every other
# condition here — the exact waiting defect this case exists to catch, wearing a
# green badge. The witness is what makes the pipes provably still held at return.
escaped_child_witnessed=0
case "$escaped_child_beat" in *witnessed=1*) escaped_child_witnessed=1 ;; esac
escaped_child_alive=0
escaped_child_stat=""
if [ -n "$escaped_child_pid" ] && kill -0 "$escaped_child_pid" 2>/dev/null; then
  escaped_child_stat="$(ps -o stat= -p "$escaped_child_pid" 2>/dev/null || true)"
  case "$escaped_child_stat" in
    ""|*Z*) : ;;
    *) escaped_child_alive=1 ;;
  esac
fi
# The controller signals the wrapper's process group, but reaping the corpse is
# the OS's business and lags on a loaded runner: an unreaped zombie still answers
# kill -0, so treat it as gone and give the reap a bounded grace period. Both stay
# far below the descendant lifetime, so a wrapper the controller never killed
# (it would outlive this loop) is still a hard failure.
escaped_wrapper_gone=0
escaped_wrapper_stat=""
if [ -n "$escaped_wrapper_pid" ]; then
  escaped_wrapper_deadline="$(( $(date +%s) + 15 ))"
  while :; do
    if ! kill -0 "$escaped_wrapper_pid" 2>/dev/null; then
      escaped_wrapper_gone=1
      break
    fi
    escaped_wrapper_stat="$(ps -o stat= -p "$escaped_wrapper_pid" 2>/dev/null || true)"
    case "$escaped_wrapper_stat" in
      *Z*) escaped_wrapper_gone=1; break ;;
    esac
    [ "$(date +%s)" -ge "$escaped_wrapper_deadline" ] && break
    sleep 1
  done
fi
# Release the descendant only after that poll: while it runs the descendant must
# still hold the reviewer pipes, or the wrapper would exit on its own and a
# controller that never killed it would read as gone. Clearing the trap handle
# right after keeps a much later EXIT from killing whatever inherited this pid.
[ -z "$escaped_child_pid" ] || kill -KILL "$escaped_child_pid" 2>/dev/null || true
escaped_child_trap_pid=""
rm -f "$WORK/state/escaped_hang_child_pid" "$WORK/state/escaped_hang_child_beat" "$WORK/state/escaped_gate_returned"
escaped_envelope_ok=0
if json_fields "$out" status=inconclusive fallback_eligible=false reason_code=gate_timeout next_action=stop_reviewer_lane; then
  escaped_envelope_ok=1
fi
if [ "$rc" != 2 ] || [ "$escaped_child_detached" != 1 ] || [ "$escaped_child_witnessed" != 1 ] || [ "$escaped_watchdog_fired" != 0 ] || [ "$escaped_wrapper_gone" != 1 ] || [ -e "$WORK/state/kimi_timeout" ] || [ "$escaped_envelope_ok" != 1 ]; then
  printf 'escaped diagnostic: rc=%s elapsed=%s watchdog_fired=%s child_pid=%s child_alive=%s child_detached=%s child_witnessed=%s returned_at=%s child_stat=%s child_beat=%s test_sid=%s wrapper_pid=%s wrapper_gone=%s wrapper_stat=%s kimi_started=%s envelope_ok=%s out=%s\n' \
    "$rc" "$escaped_elapsed" "$escaped_watchdog_fired" "$escaped_child_pid" "$escaped_child_alive" "$escaped_child_detached" "$escaped_child_witnessed" "$escaped_returned_at" "[$escaped_child_stat]" "[$escaped_child_beat]" "$escaped_test_sid" "$escaped_wrapper_pid" "$escaped_wrapper_gone" "[$escaped_wrapper_stat]" \
    "$([ -e "$WORK/state/kimi_timeout" ] && printf yes || printf no)" "$escaped_envelope_ok" "$out" >&2
fi
check "an escaped descendant holding reviewer pipes cannot block the terminal envelope" \
  '[ "$rc" = 2 ] && [ "$escaped_child_detached" = 1 ] && [ "$escaped_child_witnessed" = 1 ] && [ "$escaped_watchdog_fired" = 0 ] && [ "$escaped_wrapper_gone" = 1 ] && [ ! -e "$WORK/state/kimi_timeout" ] && [ "$escaped_envelope_ok" = 1 ]'

reset_case passed_slow passed unavailable unavailable
out="$(run_challenge_gate --allow-fallback-egress --focus deadline-edge-verdict --total-timeout 16)"; rc=$?
check "controller headroom preserves a valid challenge verdict near the inner deadline" \
  '[ "$rc" = 0 ] && json_fields "$out" status=passed selected_client=claude'

reset_case passed unavailable unavailable
out="$(run_gate --total-timeout 4)"; rc=$?
check "an out-of-range cumulative budget fails before provider execution" \
  '[ "$rc" = 2 ] && [ ! -e "$WORK/state/client_sequence" ] && json_fields "$out" reason_code=invalid_input'

printf 'diff --git a/x b/x\n--- a/x\n+++ b/x\n@@ -1 +1 @@\n-c\n+d\n' >"$WORK/diff.patch"
reset_case passed unavailable unavailable
out="$(run_challenge_gate --challenge-budget 2 --challenge-index 2 --focus final-surface --review-chain-id long-task --autonomous-review-index 3 --prior-review-result-file "$WORK/chain-round-one.json" --prior-review-result-file "$WORK/chain-round-two.json")"; rc=$?
check "a changed third candidate reaches the last Agent round without resetting budget" \
  '[ "$rc" = 0 ] && json_fields "$out" review_chain_tracked=true review_chain_id=long-task autonomous_review_index=3 autonomous_reviews_remaining=0 autonomous_review_allowed=false prior_challenge_focuses.0=corrected-path'
printf '%s\n' "$out" >"$WORK/chain-final.json"

reset_case passed unavailable unavailable
out="$(run_completion_gate --challenge-budget 2 --completion-review-result-file "$WORK/chain-final.json")"; rc=$?
check "completion preserves the verified tracked review-chain evidence" \
  '[ "$rc" = 0 ] && [ ! -e "$WORK/state/client_sequence" ] && json_fields "$out" mode=complete status=passed review_chain_tracked=true review_chain_id=long-task autonomous_review_budget=3 autonomous_review_index=3 autonomous_reviews_remaining=0 autonomous_review_allowed=false prior_challenge_focuses.0=corrected-path completion_gated=false'

reset_case findings unavailable unavailable
out="$(run_challenge_gate --challenge-budget 2 --challenge-index 2 --focus final-findings --review-chain-id long-task --autonomous-review-index 3 --prior-review-result-file "$WORK/chain-round-one.json" --prior-review-result-file "$WORK/chain-round-two.json")"; rc=$?
check "findings in the last tracked Agent round return to a post-budget checkpoint" \
  '[ "$rc" = 0 ] && json_fields "$out" status=findings review_chain_tracked=true autonomous_review_index=3 autonomous_reviews_remaining=0 autonomous_review_allowed=false human_decision_required=true review_state=post_review_budget findings_require_implementer_self_review=true next_action=triage_findings_and_continue_independent_work self_review_gate.required=true self_review_gate.required_triggers.0=findings_returned self_review_gate.required_triggers.1=post_review_budget_checkpoint self_review_gate.blocks.0=external_review self_review_gate.allowed_next_actions.2=continue_independent_work'

reset_case passed unavailable unavailable
out="$(run_challenge_gate --challenge-budget 2 --challenge-index 1 --focus missing-history --review-chain-id long-task --autonomous-review-index 2)"; rc=$?
check "a tracked Agent round rejects omitted prior results before provider execution" \
  '[ "$rc" = 2 ] && [ ! -e "$WORK/state/client_sequence" ] && json_fields "$out" reason_code=review_chain_invalid'

# In a tracked chain the challenge index is not free: the chain requires
# autonomous_review_index == challenge_index + 1, so an omitted flag has exactly
# one legal value to resolve to, and a chain declared as Agent round 1 still has
# none.
reset_case passed unavailable unavailable
out="$(challenge_gate_no_index --challenge-budget 2 --focus derived-tracked --review-chain-id long-task --autonomous-review-index 2 --prior-review-result-file "$WORK/chain-round-one.json")"; rc=$?
check "a tracked challenge derives its index from the Agent review index" \
  '[ "$rc" = 0 ] && json_fields "$out" review_chain_tracked=true autonomous_review_index=2 challenge_index=1'

reset_case passed unavailable unavailable
out="$(challenge_gate_no_index --challenge-budget 2 --focus derived-tracked-last --review-chain-id long-task --autonomous-review-index 3 --prior-review-result-file "$WORK/chain-round-one.json" --prior-review-result-file "$WORK/chain-round-two.json")"; rc=$?
check "the derived tracked index follows the Agent review index past the first challenge" \
  '[ "$rc" = 0 ] && json_fields "$out" autonomous_review_index=3 challenge_index=2'

reset_case passed unavailable unavailable
out="$(challenge_gate_no_index --challenge-budget 2 --focus derived-round-one --review-chain-id long-task --autonomous-review-index 1)"; rc=$?
check "a tracked challenge declared as Agent round 1 still fails on the derived index" \
  '[ "$rc" = 2 ] && [ ! -e "$WORK/state/client_sequence" ] && json_fields "$out" reason_code=invalid_input'

reset_case passed unavailable unavailable
out="$(run_challenge_gate --challenge-budget 2 --challenge-index 1 --focus changed-chain --review-chain-id renamed-task --autonomous-review-index 2 --prior-review-result-file "$WORK/chain-round-one.json")"; rc=$?
check "renaming the review chain cannot reset a consumed Agent round" \
  '[ "$rc" = 2 ] && [ ! -e "$WORK/state/client_sequence" ] && json_fields "$out" reason_code=review_chain_invalid'

reset_case passed unavailable unavailable
out="$(run_challenge_gate --challenge-budget 2 --challenge-index 2 --focus fourth-round --review-chain-id long-task --autonomous-review-index 4 --prior-review-result-file "$WORK/chain-round-one.json" --prior-review-result-file "$WORK/chain-round-two.json")"; rc=$?
check "an Agent review beyond its configured chain budget is rejected" \
  '[ "$rc" = 2 ] && [ ! -e "$WORK/state/client_sequence" ] && json_fields "$out" reason_code=review_chain_invalid'

reset_case passed unavailable unavailable
max_five_round_one="$(run_gate --challenge-budget 4 --review-chain-id max-five-task --autonomous-review-index 1)"; max_five_round_one_rc=$?
printf '%s\n' "$max_five_round_one" >"$WORK/max-five-round-one.json"
check "a caller may configure four challenges after the initial Agent review" \
  '[ "$max_five_round_one_rc" = 0 ] && json_fields "$max_five_round_one" autonomous_review_budget=5 autonomous_review_index=1 autonomous_reviews_remaining=4 autonomous_review_allowed=true'

reset_case passed unavailable unavailable
out="$(run_gate --challenge-budget 1 --review-chain-id per-budget-bound --autonomous-review-index 5)"; rc=$?
check "the tracked index is bounded by this invocation's challenge budget" \
  '[ "$rc" = 2 ] && [ ! -e "$WORK/state/client_sequence" ] && [ "$(printf "%s" "$out" | python3 -c "import json,sys; print(json.load(sys.stdin).get(\"reason\"))")" = "a tracked Agent review requires --autonomous-review-index between 1 and 2" ] && json_fields "$out" reason_code=review_chain_invalid'

reset_case passed unavailable unavailable
max_five_round_two="$(run_challenge_gate --challenge-budget 4 --challenge-index 1 --focus max-five-one --review-chain-id max-five-task --autonomous-review-index 2 --prior-review-result-file "$WORK/max-five-round-one.json")"; max_five_round_two_rc=$?
printf '%s\n' "$max_five_round_two" >"$WORK/max-five-round-two.json"
reset_case passed unavailable unavailable
max_five_round_three="$(run_challenge_gate --challenge-budget 4 --challenge-index 2 --focus max-five-two --review-chain-id max-five-task --autonomous-review-index 3 --prior-review-result-file "$WORK/max-five-round-one.json" --prior-review-result-file "$WORK/max-five-round-two.json")"; max_five_round_three_rc=$?
printf '%s\n' "$max_five_round_three" >"$WORK/max-five-round-three.json"
reset_case passed unavailable unavailable
max_five_round_four="$(run_challenge_gate --challenge-budget 4 --challenge-index 3 --focus max-five-three --review-chain-id max-five-task --autonomous-review-index 4 --prior-review-result-file "$WORK/max-five-round-one.json" --prior-review-result-file "$WORK/max-five-round-two.json" --prior-review-result-file "$WORK/max-five-round-three.json")"; max_five_round_four_rc=$?
printf '%s\n' "$max_five_round_four" >"$WORK/max-five-round-four.json"
reset_case passed unavailable unavailable
max_five_round_five="$(run_challenge_gate --challenge-budget 4 --challenge-index 4 --focus max-five-four --review-chain-id max-five-task --autonomous-review-index 5 --prior-review-result-file "$WORK/max-five-round-one.json" --prior-review-result-file "$WORK/max-five-round-two.json" --prior-review-result-file "$WORK/max-five-round-three.json" --prior-review-result-file "$WORK/max-five-round-four.json")"; max_five_round_five_rc=$?
printf '%s\n' "$max_five_round_five" >"$WORK/max-five-round-five.json"
if [ "$max_five_round_two_rc" != 0 ] || [ "$max_five_round_three_rc" != 0 ] || [ "$max_five_round_four_rc" != 0 ] || [ "$max_five_round_five_rc" != 0 ]; then
  printf 'max-five diagnostic: rc=%s/%s/%s/%s round2=%s round3=%s round4=%s round5=%s\n' \
    "$max_five_round_two_rc" "$max_five_round_three_rc" "$max_five_round_four_rc" "$max_five_round_five_rc" \
    "$max_five_round_two" "$max_five_round_three" "$max_five_round_four" "$max_five_round_five" >&2
fi
check "one tracked Agent chain reaches five total external review rounds" \
  '[ "$max_five_round_two_rc" = 0 ] && [ "$max_five_round_three_rc" = 0 ] && [ "$max_five_round_four_rc" = 0 ] && [ "$max_five_round_five_rc" = 0 ] && json_fields "$max_five_round_five" autonomous_review_budget=5 autonomous_review_index=5 autonomous_reviews_remaining=0 autonomous_review_allowed=false prior_challenge_focuses.2=max-five-three next_action=deep_self_review_before_completion'

reset_case passed unavailable unavailable
out="$(run_completion_gate --challenge-budget 4 --completion-review-result-file "$WORK/max-five-round-five.json")"; rc=$?
check "completion accepts the fifth exact-candidate Agent round" \
  '[ "$rc" = 0 ] && [ ! -e "$WORK/state/client_sequence" ] && json_fields "$out" mode=complete status=passed autonomous_review_budget=5 autonomous_review_index=5 autonomous_reviews_remaining=0 completion_gated=false'

reset_case passed unavailable unavailable
out="$(run_challenge_gate --challenge-budget 4 --challenge-index 5 --focus max-five-overflow --review-chain-id max-five-task --autonomous-review-index 6 --prior-review-result-file "$WORK/max-five-round-one.json" --prior-review-result-file "$WORK/max-five-round-two.json" --prior-review-result-file "$WORK/max-five-round-three.json" --prior-review-result-file "$WORK/max-five-round-four.json" --prior-review-result-file "$WORK/max-five-round-five.json")"; rc=$?
check "a sixth Agent review is rejected before provider execution" \
  '[ "$rc" = 2 ] && [ ! -e "$WORK/state/client_sequence" ] && json_fields "$out" reason_code=review_chain_invalid'

printf 'diff --git a/x b/x\n--- a/x\n+++ b/x\n@@ -1 +1 @@\n-a\n+b\n' >"$WORK/diff.patch"

reset_case passed unavailable unavailable
out="$(run_gate --challenge-budget 5)"; rc=$?
check "Agent challenge budget above four fails closed before provider execution" \
  '[ "$rc" = 2 ] && [ ! -e "$WORK/state/client_sequence" ] && json_fields "$out" reason_code=invalid_input'

reset_case passed unavailable unavailable
out="$(REVIEW_GATE_TEST_STATE="$WORK/state" "$WORK/harness/scripts/review_gate.sh" \
  --mode review --cwd "$WORK/repo" --diff-file "$WORK/diff.patch" \
  --implementer-family openai --review-plan-file "$WORK/incomplete-plan.json")"; rc=$?
check "incomplete owner-guided self-review fails before provider execution" \
  '[ "$rc" = 2 ] && [ ! -e "$WORK/state/client_sequence" ] && json_fields "$out" reason_code=self_review_incomplete self_review_gate.required=true self_review_gate.required_triggers.0=before_external_review self_review_gate.blocks.0=external_review self_review_gate.blocks.1=completion_claim self_review_gate.allowed_next_actions.0=deep_self_review self_review_gate.allowed_next_actions.1=continue_implementation'

reset_case passed unavailable unavailable
out="$(REVIEW_GATE_TEST_STATE="$WORK/state" "$WORK/harness/scripts/review_gate.sh" \
  --mode review --cwd "$WORK/repo" --diff-file "$WORK/diff.patch" \
  --implementer-family openai --review-plan-file "$WORK/placeholder-plan.json")"; rc=$?
check "placeholder self-review conclusions fail before provider execution" \
  '[ "$rc" = 2 ] && [ ! -e "$WORK/state/client_sequence" ] && json_fields "$out" reason_code=self_review_incomplete'

reset_case passed unavailable unavailable
out="$(REVIEW_GATE_TEST_STATE="$WORK/state" "$WORK/harness/scripts/review_gate.sh" \
  --mode review --cwd "$WORK/repo" --diff-file "$WORK/diff.patch" \
  --implementer-family openai --review-plan-file "$WORK/placeholder-evidence-plan.json")"; rc=$?
check "placeholder evidence results fail before provider execution" \
  '[ "$rc" = 2 ] && [ ! -e "$WORK/state/client_sequence" ] && json_fields "$out" reason_code=self_review_incomplete'

for low_information_plan in low-information-self-review-plan low-information-evidence-plan; do
  reset_case passed unavailable unavailable
  out="$(REVIEW_GATE_TEST_STATE="$WORK/state" "$WORK/harness/scripts/review_gate.sh" \
    --mode review --cwd "$WORK/repo" --diff-file "$WORK/diff.patch" \
    --implementer-family openai --review-plan-file "$WORK/$low_information_plan.json")"; rc=$?
  check "$low_information_plan fails before provider execution" \
    '[ "$rc" = 2 ] && [ ! -e "$WORK/state/client_sequence" ] && json_fields "$out" reason_code=self_review_incomplete'
done

reset_case quota spoof_controller unavailable
out="$(run_gate --allow-fallback-egress)"; rc=$?
check "reviewer cannot self-report controller-owned stage or coverage fields" \
  '[ "$rc" = 0 ] && json_fields "$out" stage=build review_depth=build owner_selection_source=implementer-declared selected_skills.0=code-review self_review_gate.required=true self_review_gate.required_triggers.0=before_completion_claim && [ "$(printf "%s" "$out" | python3 -c "import json,sys; print(len(json.load(sys.stdin).get(\"reviewed_skills\", [])))")" = 0 ] && ! grep -q spoofed <<<"$out"'

rm -rf "$WORK/repo/skills"
(
  cd "$WORK/repo"
  git init -q
  git config user.email test@example.invalid
  git config user.name 'Test User'
  printf 'before\n' >tracked.txt
  git add tracked.txt
  git commit -q -m initial
  printf 'after\n' >tracked.txt
  printf 'new\n' >untracked.txt
)
reset_case passed unavailable unavailable
out="$(run_base_gate --allow-fallback-egress)"; rc=$?
check "base packet freezes tracked and untracked changes once" \
  '[ "$rc" = 0 ] && grep -q tracked.txt "$WORK/state/claude_packet" && grep -q untracked.txt "$WORK/state/claude_packet" && grep -q "Untracked files" "$WORK/state/claude_packet"'

# The explicit cwd is the only repository identity. Ambient Git variables must
# not redirect discovery, objects, refs, index, or worktree to a clean decoy.
git clone -q "$WORK/repo" "$WORK/git-env-decoy"
git -C "$WORK/git-env-decoy" config core.worktree "$WORK/git-env-decoy"
: >"$WORK/empty-grafts"
: >"$WORK/empty-shallow"

reset_case passed unavailable unavailable
out="$(GIT_DIR="$WORK/git-env-decoy/.git" run_base_gate --allow-fallback-egress)"; rc=$?
check "ambient GIT_DIR cannot redirect the base-mode packet to a clean decoy" \
  '[ "$rc" = 0 ] && grep -q tracked.txt "$WORK/state/claude_packet" && grep -q -- "+after" "$WORK/state/claude_packet"'

reset_case passed unavailable unavailable
out="$( \
  GIT_DIR="$WORK/git-env-decoy/.git" \
  GIT_WORK_TREE="$WORK/git-env-decoy" \
  GIT_IMPLICIT_WORK_TREE=1 \
  GIT_INDEX_FILE="$WORK/git-env-decoy/.git/index" \
  GIT_COMMON_DIR="$WORK/git-env-decoy/.git" \
  GIT_NAMESPACE=synthetic-clean \
  GIT_OBJECT_DIRECTORY="$WORK/git-env-decoy/.git/objects" \
  GIT_ALTERNATE_OBJECT_DIRECTORIES="$WORK/git-env-decoy/.git/objects" \
  GIT_CEILING_DIRECTORIES="$WORK/git-env-decoy" \
  GIT_DISCOVERY_ACROSS_FILESYSTEM=0 \
  GIT_GRAFT_FILE="$WORK/empty-grafts" \
  GIT_SHALLOW_FILE="$WORK/empty-shallow" \
  GIT_REPLACE_REF_BASE=refs/synthetic-replace \
  GIT_PREFIX=synthetic-prefix \
  GIT_QUARANTINE_PATH="$WORK/git-env-decoy/.git/objects" \
  run_base_gate --allow-fallback-egress
)"; rc=$?
check "ambient Git routing matrix cannot replace the requested repository" \
  '[ "$rc" = 0 ] && grep -q tracked.txt "$WORK/state/claude_packet" && grep -q -- "+after" "$WORK/state/claude_packet" && ! grep -q "$WORK/git-env-decoy" "$WORK/state/claude_packet"'

git_config_env_probe="$(
  GIT_CONFIG="$WORK/attacker.cfg" \
  GIT_CONFIG_GLOBAL="$WORK/attacker-global.cfg" \
  GIT_CONFIG_SYSTEM="$WORK/attacker-system.cfg" \
  GIT_CONFIG_NOSYSTEM=1 \
  GIT_CONFIG_COUNT=2 \
  GIT_CONFIG_PARAMETERS="'core.fsmonitor=$WORK/fake-fsmonitor.sh'" \
  GIT_CONFIG_KEY_0=core.worktree \
  GIT_CONFIG_VALUE_0="$WORK/git-env-decoy" \
  GIT_CONFIG_KEY_custom=include.path \
  GIT_CONFIG_VALUE_custom="$WORK/attacker-include.cfg" \
  PYTHONPATH="$WORK/harness/scripts" python3 - <<'PY' 2>&1
import os

import review_gate

environment = review_gate.git_environment()
for key in (
    "GIT_CONFIG",
    "GIT_CONFIG_COUNT",
    "GIT_CONFIG_PARAMETERS",
    "GIT_CONFIG_KEY_0",
    "GIT_CONFIG_VALUE_0",
    "GIT_CONFIG_KEY_custom",
    "GIT_CONFIG_VALUE_custom",
):
    assert key not in environment, (key, environment[key])
assert environment["GIT_CONFIG_GLOBAL"] == os.devnull
assert environment["GIT_CONFIG_SYSTEM"] == os.devnull
assert environment["GIT_CONFIG_NOSYSTEM"] == "1"
print("git_config_environment_clean")
PY
)"; git_config_env_rc=$?
check "base-mode Git environment removes fixed and indexed config injection variables" \
  '[ "$git_config_env_rc" = 0 ] && [ "$git_config_env_probe" = git_config_environment_clean ]'

cat >"$WORK/fake-fsmonitor.sh" <<'SH'
#!/bin/sh
: >"$REVIEW_FSMONITOR_MARKER"
printf '\n'
SH
chmod +x "$WORK/fake-fsmonitor.sh"
printf '[core]\n\tworktree = %s\n\tfsmonitor = %s\n' \
  "$WORK/git-env-decoy" "$WORK/fake-fsmonitor.sh" \
  >"$WORK/attacker-include.cfg"
printf '[include]\n\tpath = %s\n' "$WORK/attacker-include.cfg" \
  >"$WORK/attacker-root.cfg"

for config_env in GIT_CONFIG_GLOBAL GIT_CONFIG_SYSTEM; do
  rm -f "$WORK/fsmonitor-marker"
  reset_case passed unavailable unavailable
  out="$(
    export "$config_env=$WORK/attacker-root.cfg"
    REVIEW_FSMONITOR_MARKER="$WORK/fsmonitor-marker" \
      run_base_gate --allow-fallback-egress
  )"; rc=$?
  check "ambient $config_env include cannot route the worktree or execute fsmonitor" \
    '[ "$rc" = 0 ] && [ ! -e "$WORK/fsmonitor-marker" ] && grep -q -- "+after" "$WORK/state/claude_packet"'
done

for config_route in indexed parameters; do
  rm -f "$WORK/fsmonitor-marker"
  reset_case passed unavailable unavailable
  if [ "$config_route" = indexed ]; then
    out="$( \
      REVIEW_FSMONITOR_MARKER="$WORK/fsmonitor-marker" \
      GIT_CONFIG_COUNT=1 \
      GIT_CONFIG_KEY_0=include.path \
      GIT_CONFIG_VALUE_0="$WORK/attacker-include.cfg" \
      run_base_gate --allow-fallback-egress
    )"; rc=$?
  else
    out="$( \
      REVIEW_FSMONITOR_MARKER="$WORK/fsmonitor-marker" \
      GIT_CONFIG_PARAMETERS="'include.path=$WORK/attacker-include.cfg'" \
      run_base_gate --allow-fallback-egress
    )"; rc=$?
  fi
  check "ambient $config_route config cannot load executable Git configuration" \
    '[ "$rc" = 0 ] && [ ! -e "$WORK/fsmonitor-marker" ] && grep -q -- "+after" "$WORK/state/claude_packet"'
done

git -C "$WORK/repo" config include.path "$WORK/attacker-include.cfg"
rm -f "$WORK/fsmonitor-marker"
reset_case passed unavailable unavailable
out="$(REVIEW_FSMONITOR_MARKER="$WORK/fsmonitor-marker" \
  run_base_gate --allow-fallback-egress)"; rc=$?
check "repository-local include cannot execute fsmonitor during packet construction" \
  '[ "$rc" = 0 ] && [ ! -e "$WORK/fsmonitor-marker" ] && grep -q -- "+after" "$WORK/state/claude_packet"'
git -C "$WORK/repo" config --unset-all include.path

# Neither an ambient external-diff helper nor a repository-configured textconv
# may execute or replace the bytes in the tracked packet.
cat >"$WORK/fake-external-diff.sh" <<'SH'
#!/bin/sh
: >"$REVIEW_EXTERNAL_DIFF_MARKER"
exit 0
SH
chmod +x "$WORK/fake-external-diff.sh"
rm -f "$WORK/external-diff-marker"
reset_case passed unavailable unavailable
out="$( \
  REVIEW_EXTERNAL_DIFF_MARKER="$WORK/external-diff-marker" \
  GIT_EXTERNAL_DIFF="$WORK/fake-external-diff.sh" \
  GIT_DIFF_OPTS=--unified=0 \
  run_base_gate --allow-fallback-egress
)"; rc=$?
check "tracked packet disables ambient external diff execution and spoofing" \
  '[ "$rc" = 0 ] && [ ! -e "$WORK/external-diff-marker" ] && grep -q -- "-before" "$WORK/state/claude_packet" && grep -q -- "+after" "$WORK/state/claude_packet"'

printf '%s\n' 'tracked.txt diff=review-spoof' >"$WORK/repo/.gitattributes"
git -C "$WORK/repo" add .gitattributes
git -C "$WORK/repo" commit -q -m 'add synthetic diff driver fixture' -- .gitattributes
cat >"$WORK/fake-textconv.sh" <<'SH'
#!/bin/sh
: >"$REVIEW_TEXTCONV_MARKER"
printf '%s\n' normalized
SH
chmod +x "$WORK/fake-textconv.sh"
git -C "$WORK/repo" config diff.review-spoof.textconv "$WORK/fake-textconv.sh"
rm -f "$WORK/textconv-marker"
reset_case passed unavailable unavailable
out="$(REVIEW_TEXTCONV_MARKER="$WORK/textconv-marker" run_base_gate --allow-fallback-egress)"; rc=$?
check "tracked packet disables configured textconv execution and clean spoofing" \
  '[ "$rc" = 0 ] && [ ! -e "$WORK/textconv-marker" ] && grep -q -- "-before" "$WORK/state/claude_packet" && grep -q -- "+after" "$WORK/state/claude_packet"'
git -C "$WORK/repo" config --unset diff.review-spoof.textconv

ln -s tracked.txt "$WORK/repo/untracked-link.txt"
reset_case passed unavailable unavailable
out="$(run_base_gate --allow-fallback-egress)"; rc=$?
check "base mode rejects an untracked symlink instead of reviewing a non-exact placeholder" \
  '[ "$rc" = 2 ] && [ ! -e "$WORK/state/client_sequence" ] && json_fields "$out" reason_code=invalid_input'
unlink "$WORK/repo/untracked-link.txt"

ln "$WORK/repo/tracked.txt" "$WORK/repo/untracked-hardlink.txt"
reset_case passed unavailable unavailable
out="$(run_base_gate --allow-fallback-egress)"; rc=$?
check "base mode rejects an untracked hardlink instead of omitting it" \
  '[ "$rc" = 2 ] && [ ! -e "$WORK/state/client_sequence" ] && json_fields "$out" reason_code=invalid_input'
unlink "$WORK/repo/untracked-hardlink.txt"

: >"$WORK/repo/empty-untracked.txt"
reset_case passed unavailable unavailable
out="$(run_base_gate --allow-fallback-egress)"; rc=$?
check "base mode binds an empty untracked file without a skipped placeholder" \
  '[ "$rc" = 0 ] && grep -q empty-untracked.txt "$WORK/state/claude_packet" && ! grep -qE "skipped|not shown as text diff" "$WORK/state/claude_packet"'
unlink "$WORK/repo/empty-untracked.txt"

untracked_exact_probe="$(PYTHONPATH="$WORK/harness/scripts" python3 - "$WORK" <<'PY' 2>&1
import os
import time
from pathlib import Path
import sys

import review_gate


root = Path(sys.argv[1]) / "untracked-exact-probe"
repo = root / "repo"
outside = root / "outside"
repo.mkdir(parents=True)
outside.mkdir()


def expect_rejected(fake_git_output, label):
    original = review_gate.git_output
    review_gate.git_output = fake_git_output
    try:
        try:
            review_gate.untracked_packet(repo, [], time.monotonic() + 5)
        except review_gate.GateError as exc:
            assert exc.reason_code == "invalid_input", (label, exc.reason_code)
            return exc
        raise AssertionError(f"{label} produced a placeholder instead of failing closed")
    finally:
        review_gate.git_output = original


gone = repo / "gone.txt"
gone.write_text("gone\n", encoding="utf-8")


def disappear_after_listing(repo_path, args, *unused, **kwargs):
    assert args[0] == "ls-files", args
    gone.unlink()
    return b"gone.txt\0"


expect_rejected(disappear_after_listing, "disappeared untracked path")

(outside / "escaped.txt").write_text("outside\n", encoding="utf-8")
(repo / "linked-parent").symlink_to(outside, target_is_directory=True)


def parent_symlink_listing(repo_path, args, *unused, **kwargs):
    assert args[0] == "ls-files", args
    return b"linked-parent/escaped.txt\0"


expect_rejected(parent_symlink_listing, "symlinked untracked parent")

fifo = repo / "fifo"
os.mkfifo(fifo)


def fifo_listing(repo_path, args, *unused, **kwargs):
    assert args[0] == "ls-files", args
    return b"fifo\0"


expect_rejected(fifo_listing, "untracked FIFO")
fifo.unlink()

nul = repo / "nul.bin"
nul.write_bytes(b"safe\0unsafe")


def nul_listing(repo_path, args, *unused, **kwargs):
    assert args[0] == "ls-files", args
    return b"nul.bin\0"


error = expect_rejected(nul_listing, "NUL-bearing untracked file")
assert "NUL-bearing" in error.reason, error.reason
nul.unlink()

non_utf8 = repo / "non-utf8.bin"
non_utf8.write_bytes(b"\xff")


def non_utf8_listing(repo_path, args, *unused, **kwargs):
    assert args[0] == "ls-files", args
    return b"non-utf8.bin\0"


error = expect_rejected(non_utf8_listing, "non-UTF-8 untracked file")
assert "non-UTF-8" in error.reason, error.reason
non_utf8.unlink()

accepted_control_paths = []
for label, relative in (
    ("tab", "tab\tname.txt"),
    ("newline", "line\nname.txt"),
    ("carriage-return", "carriage\rname.txt"),
    ("C0", "unit\x01name.txt"),
    ("DEL", "delete\x7fname.txt"),
    ("C1-NEL", "next\u0085line.txt"),
    ("line-separator", "line\u2028separator.txt"),
    ("paragraph-separator", "paragraph\u2029separator.txt"),
):
    control_path = repo / relative
    control_path.write_text("control path\n", encoding="utf-8")
    encoded_path = relative.encode("utf-8")

    def control_listing(repo_path, args, *unused, **kwargs):
        assert args[0] == "ls-files", args
        return encoded_path + b"\0"

    try:
        error = expect_rejected(control_listing, f"{label} untracked path")
    except AssertionError:
        accepted_control_paths.append(label)
    else:
        assert "control-character" in error.reason, error.reason
    finally:
        control_path.unlink()
assert not accepted_control_paths, accepted_control_paths

oversized = repo / "oversized.txt"
with oversized.open("wb") as handle:
    handle.truncate(review_gate.MAX_PACKET_BYTES + 1)


def oversized_listing(repo_path, args, *unused, **kwargs):
    assert args[0] == "ls-files", args
    return b"oversized.txt\0"


error = expect_rejected(oversized_listing, "oversized untracked file")
assert "exceeds" in error.reason, error.reason
oversized.unlink()

aggregate_a = repo / "aggregate-a.txt"
aggregate_b = repo / "aggregate-b.txt"
aggregate_a.write_bytes(b"a" * (review_gate.MAX_PACKET_BYTES // 2))
aggregate_b.write_bytes(b"b" * (review_gate.MAX_PACKET_BYTES // 2))


def aggregate_listing(repo_path, args, *unused, **kwargs):
    assert args[0] == "ls-files", args
    return b"aggregate-a.txt\0aggregate-b.txt\0"


error = expect_rejected(aggregate_listing, "aggregate untracked packet overflow")
assert "untracked review packet exceeds" in error.reason, error.reason
aggregate_a.unlink()
aggregate_b.unlink()

raced = repo / "raced.txt"
alternate = root / "alternate.txt"
backup = repo / "raced.before-swap"
raced.write_text("original-safe-bytes\n", encoding="utf-8")
alternate.write_text("alternate-link-bytes\n", encoding="utf-8")
calls = 0


def replace_before_old_diff(repo_path, args, *unused, **kwargs):
    global calls
    calls += 1
    if args[0] == "ls-files":
        return b"raced.txt\0"
    raced.rename(backup)
    raced.symlink_to(alternate)
    return b"diff --git a/raced.txt b/raced.txt\n+alternate-link-bytes\n"


original = review_gate.git_output
review_gate.git_output = replace_before_old_diff
try:
    packet = review_gate.untracked_packet(repo, [], time.monotonic() + 5)
finally:
    review_gate.git_output = original
    if raced.is_symlink():
        raced.unlink()
        backup.rename(raced)
assert b"original-safe-bytes" in packet, packet
assert b"alternate-link-bytes" not in packet, packet
assert calls == 1, "untracked bytes were reopened by git diff"

print("untracked_exact_inputs_ok")
PY
)"
untracked_exact_rc=$?
check "untracked unsafe types, bytes, sizes, races, and parent links fail closed" \
  '[ "$untracked_exact_rc" = 0 ] && [ "$untracked_exact_probe" = untracked_exact_inputs_ok ]'

check "owner selection source has one controller-owned definition" \
  '[ "$(grep -c '\''"implementer-declared"'\'' "$DIR/review_gate.py")" = 1 ]'

# The acceptance object for wrapper cleanup is a clean process table, not a green
# case: every case above can pass while a wrapper the controller failed to reap is
# still running. Read the ledger last, so a wrapper any case abandoned is named here
# instead of surviving the run silently.
# Settle first: the last cases' wrappers may still be tearing down when this line is
# reached, and flagging a process that is already exiting makes this check flaky
# rather than load-bearing (measured: one pid reported, already gone by the time the
# diagnostic below ran). The bound stays far under the fixture's own 300s hang bound,
# so a wrapper nobody reaped still fails here.
leaked_settle_deadline="$(( $(date +%s) + 10 ))"
while :; do
  leaked_wrappers="$(review_harness_pids_alive | tr '\n' ' ')"
  [ -z "$leaked_wrappers" ] && break
  [ "$(date +%s)" -ge "$leaked_settle_deadline" ] && break
  sleep 1
done
[ -z "$leaked_wrappers" ] || {
  printf 'leaked reviewer wrappers: %s\n' "$leaked_wrappers" >&2
  # One `ps` per pid: a space-separated list after a single -p relies on BSD operand
  # parsing and does not carry across ps implementations. Redirection ORDER is
  # load-bearing: `2>/dev/null >&2` points fd2 at /dev/null and then duplicates fd1 onto
  # THAT, sending the diagnostic to /dev/null — measured, three times, as a failure that
  # named pids it could not describe.
  for leaked_pid in $leaked_wrappers; do
    ps -o pid=,ppid=,etime=,stat=,command= -p "$leaked_pid" >&2 2>/dev/null || true
  done
}
check "the suite leaves no reviewer wrapper running" '[ -z "$leaked_wrappers" ]'

printf '%s\n' '----'
if [ "$fails" -eq 0 ]; then
  echo review_gate_tests_ok
else
  echo "$fails FAILURES"
  exit 1
fi
