#!/usr/bin/env python3
"""Self-audit oracle for the reviewer init gate.

Not a re-read of the implementation: an INDEPENDENT statement of the intended
policy, exhaustively crossed over the init-event shape space, diffed against
what the parser + the wrapper's routing table actually do end to end.

Intended policy (stated here, not derived from the code):

  A. Isolation proof is the exact `tools` allowlist plus the tool_use scan.
     Any declared/invoked tool outside the expectation, or any non-empty
     customization list, is a BREACH -> terminal.
  B. A known field carrying a known-unsafe value (`permissionMode` outside
     {default, plan}) is a proven BREACH -> terminal.
  C. Anything we cannot verify -- an unrecognized surface-shaped field, or an
     authority knob that vanished / was renamed / was added -- is UNVERIFIABLE
     -> refuse, but fallback-eligible so review routes to another client.
  D. Routine version drift -- unknown scalar metadata, empty containers, new
     `agents`/`capabilities` member strings -- is TOLERATED.
  E. Breach beats unverifiable beats drift: a run that is both must report the
     stronger class.
  F. The verdict must never be steerable by CLI-supplied text: a field NAME
     cannot select which routing arm matches.

Every row below is (case, init-event, expected verdict class), run through BOTH
parse paths. Pass an alternate parser path as argv[1] to check a candidate or a
mutant against the same policy -- that is how this oracle is validated: it must
report mismatches for a deliberately weakened parser, or its clean verdict means
nothing. Recorded validation (see the spec validation log): the pre-change
parser scores 54 mismatches, and mutants that tolerate all unknown fields, drop
the authority-name guard, drop the authority-presence requirement, or drop the
field-name sanitizer score 16 / 8 / 2 / 1 respectively.
"""
from __future__ import annotations

import json
import subprocess
import sys
import tempfile
from pathlib import Path

SCRIPT_DIR = Path(__file__).resolve().parent
PARSER = SCRIPT_DIR / "parse_probe_result.py"
WRAPPER = SCRIPT_DIR / "claude_review.sh"

# Verdict classes the wrapper distinguishes, in decreasing strength.
TOLERATED = "tolerated"          # run accepted
TERMINAL = "terminal"            # refused, lane stops
FALLBACK = "fallback"            # refused, review routes to another client

BASE = {
    "type": "system",
    "subtype": "init",
    "tools": [],
    "mcp_servers": [],
    "slash_commands": [],
    "skills": [],
    "plugins": [],
    "permissionMode": "default",
}
RESULT = {"type": "result", "subtype": "success", "is_error": False, "result": "ok"}


def init(**overrides):
    ev = dict(BASE)
    for key, value in overrides.items():
        if value is ...:
            ev.pop(key, None)
        else:
            ev[key] = value
    return ev


def case(name, ev, expected, extra_events=()):
    return {"name": name, "events": [ev, *extra_events, RESULT], "expected": expected}


# Routing arms in claude_review.sh, mirrored here so field-name steering is
# testable. If a field name can make one of these match, policy F is violated.
ROUTING_PHRASES = [
    "permission",
    "tool invocation",
    "unexpected tool",
    "runtime isolation",
    "runtime capability",
    "Bash tool",
    "unrecognized surface-shaped init field",
]

CASES = [
    # --- D: routine drift is tolerated -------------------------------------
    case("clean", init(), TOLERATED),
    case("real-2.1.220", init(
        agents=["claude", "Explore", "general-purpose", "Plan"],
        capabilities=["interrupt_receipt_v1", "interrupt_cancel_queued_v1",
                      "msg_lifecycle_v1"],
        fast_mode_state="off",
        fast_mode_disabled_reason="sdk_opt_in_required",
        claude_code_version="2.1.220",
    ), TOLERATED),
    case("unknown-scalar-str", init(future_mode="compact"), TOLERATED),
    case("unknown-scalar-bool", init(future_flag=False), TOLERATED),
    case("unknown-scalar-int", init(future_count=0), TOLERATED),
    case("unknown-scalar-null", init(future_null=None), TOLERATED),
    case("unknown-empty-list", init(future_list=[]), TOLERATED),
    case("unknown-empty-dict", init(future_dict={}), TOLERATED),
    case("new-agent-name", init(agents=["FutureAgent"]), TOLERATED),
    case("new-capability-token", init(capabilities=["future_protocol_v1"]), TOLERATED),
    case("permission-mode-plan", init(permissionMode="plan"), TOLERATED),

    # --- C: unverifiable -> fallback ---------------------------------------
    case("unknown-nonempty-list", init(future_surface=["x"]), FALLBACK),
    case("unknown-nonempty-dict", init(future_surface={"a": 1}), FALLBACK),
    case("authority-absent", init(permissionMode=...), FALLBACK),
    case("authority-renamed", init(permissionMode=..., permission_mode="bypassPermissions"),
         FALLBACK),
    case("authority-added-scalar", init(dangerously_skip_permissions=True), FALLBACK),
    case("authority-added-container", init(bypass_rules=["x"]), FALLBACK),
    case("authority-added-sandbox", init(sandbox_disabled=True), FALLBACK),
    # The ADDED variant of a renamed-knob name: presence still holds, so only
    # the name guard can catch it.
    case("authority-added-named", init(authorityLevel="elevated"), FALLBACK),
    case("authority-added-admin", init(adminMode=True), FALLBACK),
    case("authority-added-superuser", init(superuser_mode=True), FALLBACK),
    # ...and the name guard must not fire on benign metadata that merely shares
    # a prefix. A false positive here is the outage class, not a safe default.
    case("benign-author", init(author="someone"), TOLERATED),
    case("benign-workspace-root", init(workspace_root="/tmp/x"), TOLERATED),
    case("benign-root-dir", init(root_dir="/tmp/x"), TOLERATED),
    case("benign-authenticated", init(authenticated=True), TOLERATED),

    # --- B: proven unsafe value -> terminal --------------------------------
    case("bypass-permissions", init(permissionMode="bypassPermissions"), TERMINAL),
    case("accept-edits", init(permissionMode="acceptEdits"), TERMINAL),

    # --- A: breach -> terminal ---------------------------------------------
    case("declared-tool", init(tools=["Write"]), TERMINAL),
    case("declared-bash", init(tools=["Bash"]), TERMINAL),
    case("declared-skill", init(skills=["x"]), TERMINAL),
    case("declared-plugin", init(plugins=["x"]), TERMINAL),
    case("declared-mcp", init(mcp_servers=["x"]), TERMINAL),
    case("declared-command", init(slash_commands=["x"]), TERMINAL),
    case("invoked-tool", init(), TERMINAL, extra_events=[
        {"type": "assistant", "message": {"content": [
            {"type": "tool_use", "name": "Write", "input": {}}]}}]),
    case("missing-tools", init(tools=...), TERMINAL),
    case("wrong-type-tools", init(tools="none"), TERMINAL),
    case("missing-skills", init(skills=...), TERMINAL),
    case("agents-non-string", init(agents=[{"name": "x"}]), FALLBACK),
    case("capabilities-non-list", init(capabilities="x"), FALLBACK),
    case("known-metadata-turned-container", init(cwd={"path": "x"}), FALLBACK),

    # --- E: stronger class wins on combination ------------------------------
    case("drift+breach", init(future_surface=["x"], skills=["y"]), TERMINAL),
    case("drift+unsafe-value", init(future_surface=["x"],
                                    permissionMode="bypassPermissions"), TERMINAL),
    case("authority+breach", init(permissionMode=..., tools=["Write"]), TERMINAL),
    case("authority+drift", init(permissionMode=..., future_surface=["x"]), FALLBACK),

    # Multi-init streams: every check that holds per event must be evaluated per
    # event. A later init that drops or renames a field cannot be masked by an
    # earlier one that stated it -- the union is not the contract.
    case("second-init-drops-authority", init(), FALLBACK,
         extra_events=[init(permissionMode=...)]),
    case("second-init-renames-authority", init(), FALLBACK,
         extra_events=[init(permissionMode=..., authorityLevel="elevated")]),
    case("second-init-declares-tool", init(), TERMINAL,
         extra_events=[init(tools=["Bash"])]),
]

# --- F: no CLI-supplied field name may steer the routing arm ---------------
for phrase in ROUTING_PHRASES:
    CASES.append(case(
        f"steer-drift[{phrase}]",
        init(**{phrase: ["x"]}) if " " not in phrase else init(),
        FALLBACK,
    ) if " " not in phrase else case(f"steer-drift[{phrase}]",
                                     {**BASE, phrase: ["x"]}, FALLBACK))
    # the same phrase attached to a genuine breach must NOT soften it
    CASES.append(case(f"steer-breach[{phrase}]",
                      {**BASE, "skills": ["y"], phrase: ["x"]}, TERMINAL))
    # Field names are not the only CLI-supplied text reaching the routed reason:
    # tool names, skill/plugin/command identifiers and invoked-tool names are
    # interpolated too, and they may contain spaces just as freely. A breach
    # must stay terminal no matter what the inspected CLI calls its surfaces.
    CASES.append(case(f"steer-tool-name[{phrase}]",
                      {**BASE, "tools": [phrase]}, TERMINAL))
    CASES.append(case(f"steer-skill-name[{phrase}]",
                      {**BASE, "skills": [phrase]}, TERMINAL))
    CASES.append(case(f"steer-invoked-tool[{phrase}]", dict(BASE), TERMINAL,
                      extra_events=[{"type": "assistant", "message": {"content": [
                          {"type": "tool_use", "name": phrase, "input": {}}]}}]))


def wrapper_arm(reason: str) -> str:
    """Mirror emit_runtime_inconclusive's case order from the wrapper source."""
    source = WRAPPER.read_text()
    block = source.split("emit_runtime_inconclusive() {", 1)[1].split("\n}", 1)[0]
    for line in block.splitlines():
        line = line.strip()
        if not line.startswith("*") or ")" not in line:
            continue
        patterns = line.split(")", 1)[0]
        body = line.split(")", 1)[1]
        for raw in patterns.split("|"):
            needle = raw.strip().strip("*").strip('"')
            if needle and needle in reason:
                if "stop_reviewer_lane" in body:
                    return TERMINAL
                if "fallback" in body:
                    return FALLBACK
                return "other:" + body.strip()[:40]
    return TERMINAL  # the wrapper's default arm stops the lane


# Both parse paths must reach the same verdict class. They build their reason
# strings independently and have drifted apart in opposite directions twice, and
# only the main path interpolates field names into the routed text - so a
# probe-path-only oracle cannot see a field-name steering bug at all.
PATHS = {
    "probe": [],
    "main": ["--require-empty-init", "--expected-tools", "",
             "--allow-expected-tool-use", "--runtime-surface-only"],
}


def run_case(entry, parser=PARSER, path="probe"):
    with tempfile.TemporaryDirectory() as tmp:
        out = Path(tmp, "stdout")
        err = Path(tmp, "stderr")
        out.write_text("\n".join(json.dumps(ev) for ev in entry["events"]))
        err.write_text("")
        proc = subprocess.run(
            [sys.executable, str(parser), "0", str(out), str(err), *PATHS[path]],
            capture_output=True, text=True)
    if proc.returncode == 0:
        return TOLERATED, ""
    try:
        reason = json.loads(proc.stdout)["reason"]
    except Exception:
        return "unparseable", proc.stdout[:120]
    return wrapper_arm(reason), reason


def main():
    parser = Path(sys.argv[1]) if len(sys.argv) > 1 else PARSER
    failures = []
    for entry in CASES:
        for path in PATHS:
            actual, reason = run_case(entry, parser, path)
            if actual != entry["expected"]:
                failures.append((f"{entry['name']}/{path}", entry["expected"],
                                 actual, reason[:160]))
    print(f"cases: {len(CASES) * len(PATHS)}  mismatches: {len(failures)}")
    for name, expected, actual, reason in failures:
        print(f"  MISMATCH {name}: expected {expected}, got {actual}")
        if reason:
            print(f"    reason: {reason}")
    return 1 if failures else 0


if __name__ == "__main__":
    raise SystemExit(main())
