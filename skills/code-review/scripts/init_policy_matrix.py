#!/usr/bin/env python3
"""Self-audit oracle for the reviewer init gate.

Not a re-read of the implementation: an INDEPENDENT statement of the intended
policy, exhaustively crossed over the init-event shape space, diffed against
what the parser + the wrapper's routing table actually do end to end.

Intended policy (stated here, not derived from the code):

  A. Isolation proof is the exact `tools` allowlist plus the tool_use scan.
     Any declared/invoked tool outside the expectation, or a non-empty MCP
     server list, is a BREACH -> terminal.
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
  G. HOST AND PLUGIN VOCABULARY IS NOT A BOUNDARY. `slash_commands`,
     `terminal_slash_commands`, `skills` and `plugins` are recorded and never
     judged: any value, any shape, any origin, present or absent, is
     TOLERATED on its own. Nothing listed there is invocable past the pinned
     `tools` set, so judging those lists against a snapshot of the host's own
     built-in names turned every CLI release that shipped a new skill or
     command into a reviewer-lane outage while proving nothing. Policies A-E
     still apply unchanged alongside any vocabulary.

Every row below is (case, init-event, expected verdict class), run through both
parse paths: only `--runtime-surface-only` selects the main-invocation branch,
and the two implementations have drifted apart in opposite directions before.

Pass an alternate parser path as argv[1] to check a candidate or a mutant
against the same policy -- that is how this oracle is validated: it must report
mismatches for a deliberately weakened parser, or its clean verdict means
nothing. That walk is EXECUTED by `test_init_policy_matrix.sh` rather than
recorded here as prose: per-mutant scores were a hand-maintained number that
every added row invalidated, and a sensitivity claim nothing runs is one
refactor away from being vacuous.
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
    """One row, run through both parse paths."""
    return {
        "name": name,
        "events": [ev, *extra_events, RESULT],
        "expected": expected,
    }


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
    case("declared-mcp", init(mcp_servers=["x"]), TERMINAL),
    case("declared-mcp-dict", init(mcp_servers=[{"name": "x"}]), TERMINAL),
    case("invoked-tool", init(), TERMINAL, extra_events=[
        {"type": "assistant", "message": {"content": [
            {"type": "tool_use", "name": "Write", "input": {}}]}}]),
    case("missing-tools", init(tools=...), TERMINAL),
    case("wrong-type-tools", init(tools="none"), TERMINAL),
    case("missing-mcp", init(mcp_servers=...), TERMINAL),
    case("wrong-type-mcp", init(mcp_servers="none"), TERMINAL),
    case("agents-non-string", init(agents=[{"name": "x"}]), FALLBACK),
    case("capabilities-non-list", init(capabilities="x"), FALLBACK),
    case("known-metadata-turned-container", init(cwd={"path": "x"}), FALLBACK),

    # --- E: stronger class wins on combination ------------------------------
    case("drift+breach", init(future_surface=["x"], mcp_servers=["y"]), TERMINAL),
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
                      {**BASE, "mcp_servers": ["y"], phrase: ["x"]}, TERMINAL))
    # Field names are not the only CLI-supplied text reaching the routed reason:
    # tool names and invoked-tool names are interpolated too, and they may
    # contain spaces just as freely. A breach must stay terminal no matter what
    # the inspected CLI calls its surfaces.
    CASES.append(case(f"steer-tool-name[{phrase}]",
                      {**BASE, "tools": [phrase]}, TERMINAL))
    CASES.append(case(f"steer-mcp-name[{phrase}]",
                      {**BASE, "mcp_servers": [phrase]}, TERMINAL))
    CASES.append(case(f"steer-invoked-tool[{phrase}]", dict(BASE), TERMINAL,
                      extra_events=[{"type": "assistant", "message": {"content": [
                          {"type": "tool_use", "name": phrase, "input": {}}]}}]))


# --- G: vocabulary is never a verdict --------------------------------------
# The owner-aware invocation is the shape whose vocabulary lists are populated
# in a real run (captured from Claude Code 2.1.261 under `--safe-mode
# --plugin-dir`); the skill-free shape reports them empty. Both shapes must be
# accepted with those lists holding anything at all, and every breach class
# must stay exactly as strong beside them.
REAL_2_1_261_COMMANDS = [
    "deep-research", "design-sync", "dataviz", "update-config", "verify",
    "debug", "code-review", "simplify", "batch", "fewer-permission-prompts",
    "doctor", "loop", "schedule", "claude-api", "workflow-authoring", "run",
    "run-skill-generator", "advisor", "agents", "auto-mode-setup",
    "autocompact", "clear", "color", "compact", "config", "context", "effort",
    "fast", "heapdump", "init", "mcp", "import", "model", "__remote-workflow",
    "workflow-launch-exec", "reload-plugins", "reload-skills", "rename",
    "ultrareview", "security-review", "usage-credits", "extra-usage", "usage",
    "insights", "recap", "skill-doctor", "goal", "design", "design-consent",
    "design-revoke", "list-agents", "team-onboarding",
    "ccl-skills:product-rd-workflow",
]
REAL_2_1_261_SKILLS = [
    "deep-research", "design-sync", "dataviz", "update-config", "verify",
    "debug", "code-review", "simplify", "batch", "fewer-permission-prompts",
    "doctor", "loop", "schedule", "claude-api", "workflow-authoring", "run",
    "run-skill-generator", "ccl-skills:product-rd-workflow",
]
VOCAB_BASE = {
    **BASE,
    "slash_commands": REAL_2_1_261_COMMANDS,
    "terminal_slash_commands": ["doctor", "color", "reload-plugins"],
    "skills": REAL_2_1_261_SKILLS,
    "plugins": [{"name": "ccl-skills", "path": "/p"}],
    "claude_code_version": "2.1.261",
}


def vocab(**overrides):
    ev = dict(VOCAB_BASE)
    for key, value in overrides.items():
        if value is ...:
            ev.pop(key, None)
        else:
            ev[key] = value
    return ev


def with_command(*extra):
    return vocab(slash_commands=[*VOCAB_BASE["slash_commands"], *extra])


def with_skill(*extra):
    return vocab(skills=[*VOCAB_BASE["skills"], *extra])


CASES += [
    # the real owner-aware init, and the same on a skill-free run
    case("real-2.1.261-owner", vocab(), TOLERATED),
    case("declared-skill", init(skills=["x"]), TOLERATED),
    case("declared-plugin", init(plugins=["x"]), TOLERATED),
    case("declared-command", init(slash_commands=["x"]), TOLERATED),
    case("missing-skills", init(skills=...), TOLERATED),
    case("missing-commands", init(slash_commands=...), TOLERATED),
    case("missing-plugins", init(plugins=...), TOLERATED),
    # names the host may ship tomorrow, in any spelling
    case("vocab-new-command", with_command("brand-new-builtin"), TOLERATED),
    case("vocab-new-skill", with_skill("brand-new-skill"), TOLERATED),
    case("vocab-mixed-case", with_command("BrandNewBuiltin"), TOLERATED),
    # shapes that used to be read as proof of a customization
    case("vocab-namespaced-command", with_command("other-plugin:cmd"), TOLERATED),
    case("vocab-namespaced-skill", with_skill("other-plugin:skill"), TOLERATED),
    case("vocab-path-shaped", with_command("dir/cmd"), TOLERATED),
    case("vocab-unparseable", with_command("ev!l"), TOLERATED),
    case("vocab-duplicate", with_command("init"), TOLERATED),
    case("vocab-whitespace", with_command(" import", "brand-new dir/cmd"), TOLERATED),
    case("vocab-dict-entry", with_command({"name": "x", "command": "/x/y"}), TOLERATED),
    case("vocab-dict-skill", with_skill({"name": "verify", "command": "/x/y"}), TOLERATED),
    case("vocab-foreign-plugin",
         vocab(plugins=[{"name": "ccl-skills"}, {"name": "other"}]), TOLERATED),
    case("vocab-plugin-strings", vocab(plugins=["ccl-skills"]), TOLERATED),
    case("vocab-no-plugin", vocab(plugins=[]), TOLERATED),
    case("vocab-wrong-type", vocab(skills="none", slash_commands={"a": 1}), TOLERATED),
    case("vocab-terminal-any-shape",
         vocab(terminal_slash_commands=[{"name": "init"}, "not-declared"]), TOLERATED),
    case("vocab-terminal-wrong-type", vocab(terminal_slash_commands="doctor"), TOLERATED),
    case("second-init-adds-vocab", vocab(), TOLERATED,
         extra_events=[with_command("evil-plugin:pwn")]),

    # ...while every breach class keeps exactly its strength beside vocabulary
    case("vocab+tool-breach", vocab(tools=["Write"]), TERMINAL),
    case("vocab+bash", vocab(tools=["Bash"]), TERMINAL),
    case("vocab+mcp", vocab(mcp_servers=["x"]), TERMINAL),
    case("vocab+unsafe-value", vocab(permissionMode="bypassPermissions"), TERMINAL),
    case("vocab+invoked-tool", vocab(), TERMINAL,
         extra_events=[{"type": "assistant", "message": {"content": [
             {"type": "tool_use", "name": "Write", "input": {}}]}}]),
    case("vocab+unknown-container", vocab(future_surface=["x"]), FALLBACK),
    case("vocab+authority-absent", vocab(permissionMode=...), FALLBACK),
    case("vocab+missing-tools", vocab(tools=...), TERMINAL),
]

# F over vocabulary: a routing phrase placed INSIDE a vocabulary list is data,
# never a verdict -- so it is tolerated alone and must not soften a breach.
for phrase in ROUTING_PHRASES:
    CASES.append(case(f"steer-vocab-command[{phrase}]", with_command(phrase), TOLERATED))
    CASES.append(case(f"steer-vocab-skill[{phrase}]", with_skill(phrase), TOLERATED))
    CASES.append(case(f"steer-vocab-breach[{phrase}]",
                      vocab(slash_commands=[*VOCAB_BASE["slash_commands"], phrase],
                            tools=["Write"]), TERMINAL))


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
    runs = 0
    for entry in CASES:
        for path in PATHS:
            runs += 1
            actual, reason = run_case(entry, parser, path)
            if actual != entry["expected"]:
                failures.append((f"{entry['name']}/{path}", entry["expected"],
                                 actual, reason[:160]))
    print(f"cases: {runs}  mismatches: {len(failures)}")
    for name, expected, actual, reason in failures:
        print(f"  MISMATCH {name}: expected {expected}, got {actual}")
        if reason:
            print(f"    reason: {reason}")
    return 1 if failures else 0


if __name__ == "__main__":
    raise SystemExit(main())
