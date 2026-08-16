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
  G. HOST VOCABULARY is unverifiable, not a proven breach. The built-in
     command/skill allowlists are a snapshot of names the host owns and this
     repo does not, so a BARE identifier they do not recognise cannot be shown
     to be a user customization -- it is class C, not class A. A NAMESPACED,
     path-shaped, duplicated or unparseable entry is still a customization and
     stays terminal, and `plugins` is never host vocabulary. Refusal is
     unchanged either way; only the next action differs, so no path that was
     terminal becomes TOLERATED.
  H. A same-executable, no-tool, no-plugin baseline may establish whole-string
     host command/skill names only for a formal init reporting the same CLI
     version. The baseline never establishes tools, authority, or schema.

Every row below is (case, init-event, expected verdict class), run through the
parse paths it declares. Policy G rows declare the review-skill paths, because
that is the only invocation shape whose customization lists are populated at all
(measured: 46 commands / 16 skills under `--plugin-dir`, both empty under
`--disable-slash-commands`) -- and it is the shape the skill-free paths never
exercised, which is why an earlier vocabulary outage passed a green matrix.
Each shape is crossed over BOTH parse implementations, since only
`--runtime-surface-only` selects the main-invocation branch.

Pass an alternate parser path as argv[1] to check a candidate or a mutant
against the same policy -- that is how this oracle is validated: it must report
mismatches for a deliberately weakened parser, or its clean verdict means
nothing. That walk is now EXECUTED by `test_init_policy_matrix.sh` rather than
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


def case(
    name,
    ev,
    expected,
    extra_events=(),
    paths=("probe", "main"),
    host_baseline=None,
):
    """One row. `paths` names the invocation shapes it is meaningful under.

    The two default paths declare no native skills, so their customization
    lists are empty in every real run and any entry is a breach. Policy G rows
    therefore declare the two review-skill paths instead -- see SKILL_BASE.
    """
    return {
        "name": name,
        "events": [ev, *extra_events, RESULT],
        "expected": expected,
        "paths": paths,
        "host_baseline": host_baseline,
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
    "unclassifiable host-vocabulary entry",
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


# --- G: host vocabulary, on the review-skill path --------------------------
# The only shape whose customization lists are populated in a real run. The
# selected skill name must NOT also be a built-in skill name, or the
# ambiguous-selected-owner guard fires on every row and masks the verdict under
# test (observed while measuring the pre-change behaviour).
SELECTED_SKILL = "product-rd-workflow"
SKILL_BASE = {
    **BASE,
    "slash_commands": ["init", "agents"],
    "skills": [f"ccl-skills:{SELECTED_SKILL}", "dataviz"],
    "plugins": [{"name": "ccl-skills"}],
}


def skill_init(**overrides):
    ev = dict(SKILL_BASE)
    for key, value in overrides.items():
        if value is ...:
            ev.pop(key, None)
        else:
            ev[key] = value
    return ev


def skill_case(name, ev, expected, extra_events=(), host_baseline=None):
    return case(name, ev, expected, extra_events,
                paths=("skill", "skill-probe"),
                host_baseline=host_baseline)


def with_command(*extra):
    return skill_init(slash_commands=[*SKILL_BASE["slash_commands"], *extra])


def with_skill(*extra):
    return skill_init(skills=[*SKILL_BASE["skills"], *extra])


CASES += [
    # the base itself must be accepted, or every row below proves nothing
    skill_case("skill-clean", skill_init(), TOLERATED),

    # Real Claude Code 2.1.233 owner-aware init drift. These three commands and
    # terminal_slash_commands were captured from the exact safe-mode/plugin
    # invocation used by claude_review.sh. They are host vocabulary/metadata,
    # not an extra invocable surface; the exact tools list remains independently
    # pinned by policy A.
    skill_case(
        "real-2.1.233-owner",
        skill_init(
            slash_commands=[
                *SKILL_BASE["slash_commands"],
                "__remote-workflow",
                "auto-mode-setup",
                "autocompact",
                "list-agents",
            ],
            terminal_slash_commands=["init", "agents"],
            claude_code_version="2.1.233",
        ),
        TOLERATED,
        host_baseline=init(
            slash_commands=[
                *SKILL_BASE["slash_commands"],
                "__remote-workflow",
                "auto-mode-setup",
                "autocompact",
                "list-agents",
            ],
            skills=["dataviz"],
            plugins=[],
            terminal_slash_commands=["init", "agents"],
            claude_code_version="2.1.233",
        ),
    ),
    skill_case(
        "host-baseline-version-mismatch",
        skill_init(
            slash_commands=[
                *SKILL_BASE["slash_commands"],
                "auto-mode-setup",
            ],
            claude_code_version="2.1.234",
        ),
        FALLBACK,
        host_baseline=init(
            slash_commands=["auto-mode-setup"],
            claude_code_version="2.1.233",
        ),
    ),
    skill_case(
        "host-baseline-does-not-allow-unbaselined-command",
        skill_init(
            slash_commands=[
                *SKILL_BASE["slash_commands"],
                "baseline-command",
                "formal-only-command",
            ],
            claude_code_version="2.1.233",
        ),
        FALLBACK,
        host_baseline=init(
            slash_commands=["baseline-command"],
            skills=["dataviz"],
            claude_code_version="2.1.233",
        ),
    ),
    skill_case(
        "host-baseline-does-not-authorize-new-skill",
        skill_init(
            skills=[*SKILL_BASE["skills"], "brand-new-host-skill"],
            claude_code_version="2.1.233",
        ),
        FALLBACK,
        host_baseline=init(
            skills=["brand-new-host-skill"],
            claude_code_version="2.1.233",
        ),
    ),
    skill_case(
        "host-baseline-rejects-namespaced-command",
        skill_init(
            slash_commands=[*SKILL_BASE["slash_commands"], "rogue:exfil"],
            claude_code_version="2.1.233",
        ),
        TERMINAL,
        host_baseline=init(
            slash_commands=["rogue:exfil"],
            claude_code_version="2.1.233",
        ),
    ),
    skill_case(
        "host-baseline-rejects-namespaced-skill",
        skill_init(
            skills=[*SKILL_BASE["skills"], "vendor:skill"],
            claude_code_version="2.1.233",
        ),
        TERMINAL,
        host_baseline=init(
            skills=["vendor:skill"],
            claude_code_version="2.1.233",
        ),
    ),
    skill_case(
        "host-baseline-does-not-allow-unbaselined-skill",
        skill_init(
            skills=[*SKILL_BASE["skills"], "formal-only-host-skill"],
            claude_code_version="2.1.233",
        ),
        FALLBACK,
        host_baseline=init(
            skills=["brand-new-host-skill"],
            claude_code_version="2.1.233",
        ),
    ),
    skill_case(
        "host-baseline-rejects-required-empty-surface",
        skill_init(claude_code_version="2.1.233"),
        TERMINAL,
        host_baseline=init(
            plugins=["untrusted-plugin"],
            claude_code_version="2.1.233",
        ),
    ),
    skill_case(
        "terminal-commands-must-be-declared",
        skill_init(terminal_slash_commands=["not-declared"]),
        FALLBACK,
    ),
    skill_case(
        "terminal-commands-ignore-json-key-order",
        {
            "terminal_slash_commands": ["init", "agents"],
            **skill_init(),
        },
        TOLERATED,
    ),
    skill_case(
        "terminal-commands-must-be-plain-strings",
        skill_init(terminal_slash_commands=[{"name": "init"}]),
        FALLBACK,
    ),

    # the defect: a name the host added and this snapshot does not know
    skill_case("host-vocab-new-command", with_command("brand-new-builtin"), FALLBACK),
    skill_case("host-vocab-new-skill", with_skill("brand-new-skill"), FALLBACK),
    # identifiers are normalized before classification, so case is not a class
    skill_case("host-vocab-mixed-case", with_command("BrandNewBuiltin"), FALLBACK),

    # ...and everything that is NOT host vocabulary stays a proven breach
    skill_case("namespaced-foreign-command", with_command("evil-plugin:pwn"), TERMINAL),
    skill_case("namespaced-foreign-skill", with_skill("evil-plugin:pwn"), TERMINAL),
    skill_case("path-shaped-identifier", with_command("dir/cmd"), TERMINAL),
    skill_case("unparseable-identifier", with_command("ev!l"), TERMINAL),
    skill_case("duplicate-identifiers", with_command("init"), TERMINAL),
    skill_case("foreign-plugin",
               skill_init(plugins=[{"name": "ccl-skills"}, {"name": "other"}]),
               TERMINAL),
    # A STRUCTURED entry stays terminal even when its reported `name` is bare:
    # the identifier helper reads `name` first, so a sibling key can carry
    # path-shaped proof of a real customization that the soft class would then
    # ignore. Unread evidence is not the same as absent evidence, which is the
    # only thing this class is for. Costs nothing: measured against the real
    # CLI, both host-vocabulary fields arrive as plain strings.
    skill_case("dict-entry-bare-name",
               with_command({"name": "brand-new-builtin", "command": "/x/y"}),
               TERMINAL),
    # ...and the same shape with no smuggled key is still terminal, so the rule
    # is "structured entries are not host vocabulary", not "we grep for paths".
    skill_case("dict-entry-bare-name-only",
               with_command({"name": "brand-new-builtin"}), TERMINAL),
    # The severe variant, and the one a round-5 review found: a structured entry
    # whose `name` is an ALLOWED built-in used to clear the allowlist outright,
    # so its other keys were never inspected and the run reached TOLERATED with
    # isolation reported verified. Reproduced before it was fixed. Both fields,
    # because the shape gate must not be per-field folklore.
    # The smuggled `name` must be an allowed built-in that is NOT already in the
    # base list: reusing one duplicates an identifier, and the duplicate check
    # then makes the row terminal for an unrelated reason. Caught by differential
    # attribution — with the first fixtures, removing the shape gate flipped
    # nothing here, which is a finding about the test, not a clean result.
    skill_case("dict-entry-smuggled-under-allowed-command",
               with_command({"name": "import", "command": "/x/y",
                             "extra": ["Bash"]}), TERMINAL),
    skill_case("dict-entry-smuggled-under-allowed-skill",
               with_skill({"name": "verify", "command": "/x/y"}), TERMINAL),
    # ...while `plugins` legitimately carries dicts in every real run, so the
    # gate must not spread to it: this is what stops the fix from breaking the
    # actual CLI.
    skill_case("plugin-dict-stays-legitimate",
               skill_init(plugins=[{"name": "ccl-skills", "path": "/p"}]),
               TOLERATED),
    # The third instance of the same class: a PLAIN STRING whose first token is
    # bare while the discarded remainder carries the proof. The identifier helper
    # keeps only that first token, so judging the token instead of the whole
    # value read `brand-new evil-plugin:pwn` as host vocabulary.
    skill_case("whitespace-hides-a-namespace",
               with_command("brand-new evil-plugin:pwn"), TERMINAL),
    skill_case("whitespace-hides-a-path",
               with_command("brand-new dir/cmd"), TERMINAL),
    skill_case("whitespace-hides-a-routing-phrase",
               with_command("brand-new runtime isolation"), TERMINAL),
    skill_case("whitespace-hides-a-namespace-in-skills",
               with_skill("brand-new evil-plugin:pwn"), TERMINAL),
    # SURROUNDING whitespace is the fourth instance, and the worst: wrapping an
    # ALLOWLISTED name reached TOLERATED, because both the allowlist and the
    # first version of the whole-value check stripped before comparing.
    skill_case("trailing-space-on-an-allowlisted-command",
               with_command("import "), TERMINAL),
    skill_case("leading-space-on-an-allowlisted-command",
               with_command(" import"), TERMINAL),
    skill_case("trailing-space-on-an-allowlisted-skill",
               with_skill("verify "), TERMINAL),
    skill_case("trailing-space-on-an-unknown-command",
               with_command("brand-new "), TERMINAL),
    skill_case("tab-wrapped-allowlisted-command",
               with_command("\timport"), TERMINAL),
    # ...and the legitimate namespaced entry must survive all of that, since its
    # whole value IS its identifier. Without this row the gate could be tightened
    # into rejecting the surface the review-skill mode depends on.
    skill_case("selected-namespaced-command-still-allowed",
               with_command(f"ccl-skills:{SELECTED_SKILL}"), TOLERATED),

    # E in review-skill mode: the softer class must never absorb a real breach
    skill_case("host-vocab+tool-breach",
               skill_init(slash_commands=[*SKILL_BASE["slash_commands"], "brand-new"],
                          tools=["Write"]), TERMINAL),
    skill_case("host-vocab+unsafe-value",
               skill_init(slash_commands=[*SKILL_BASE["slash_commands"], "brand-new"],
                          permissionMode="bypassPermissions"), TERMINAL),
    skill_case("host-vocab+namespaced",
               with_command("brand-new", "evil-plugin:pwn"), TERMINAL),
    skill_case("host-vocab+invoked-tool",
               with_command("brand-new"), TERMINAL,
               extra_events=[{"type": "assistant", "message": {"content": [
                   {"type": "tool_use", "name": "Write", "input": {}}]}}]),
    # two unverifiables are still one unverifiable
    skill_case("host-vocab+unknown-container",
               skill_init(slash_commands=[*SKILL_BASE["slash_commands"], "brand-new"],
                          future_surface=["x"]), FALLBACK),

    # per event, not on the union
    skill_case("second-init-adds-host-vocab", skill_init(), FALLBACK,
               extra_events=[with_command("brand-new-builtin")]),
    skill_case("second-init-adds-namespaced", skill_init(), TERMINAL,
               extra_events=[with_command("evil-plugin:pwn")]),

    # invariants that must survive in this mode too
    skill_case("skill-missing-plugin", skill_init(plugins=[]), TERMINAL),
    skill_case("skill-required-absent",
               skill_init(skills=["ccl-skills:other-skill"]), TERMINAL),
    skill_case("skill-authority-absent", skill_init(permissionMode=...), FALLBACK),
    skill_case("skill-declared-tool", skill_init(tools=["Write"]), TERMINAL),
]

# F in review-skill mode: the new class is reached through a CLI-supplied
# IDENTIFIER rather than a field name, so re-run the steering check over it. A
# phrase is normalized to its first token, which is bare -- so the softest arm
# it can reach is its own class, and it must never soften a breach.
for phrase in ROUTING_PHRASES:
    # A phrase containing whitespace cannot be a plain host name at all, so the
    # whole-value gate disqualifies it and it stays TERMINAL — stricter than the
    # single-token case, and the property under test is unchanged either way: a
    # CLI-supplied identifier never reaches an arm SOFTER than its own class.
    CASES.append(skill_case(f"steer-vocab-command[{phrase}]",
                            with_command(phrase),
                            FALLBACK if " " not in phrase else TERMINAL))
    CASES.append(skill_case(f"steer-vocab-breach[{phrase}]",
                            skill_init(
                                slash_commands=[*SKILL_BASE["slash_commands"], phrase],
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
    # The review-skill shape, carrying the native-skill flags the wrapper really
    # passes. Added because the two paths above declare no skills, so their
    # customization lists are empty in every real run -- leaving the branch that
    # actually classifies host vocabulary untested by a green matrix.
    "skill": ["--require-empty-init", "--expected-tools", "",
              "--expected-native-skills", SELECTED_SKILL,
              "--required-native-skills", SELECTED_SKILL,
              "--allow-expected-tool-use", "--runtime-surface-only"],
    # ...and the same shape through the OTHER parse path. `--runtime-surface-only`
    # is what selects the main-invocation branch, so without this the review-skill
    # cases would only ever exercise one of the two implementations that have
    # drifted apart in opposite directions twice before.
    "skill-probe": ["--require-empty-init", "--expected-tools", "",
                    "--expected-native-skills", SELECTED_SKILL,
                    "--required-native-skills", SELECTED_SKILL],
}


def run_case(entry, parser=PARSER, path="probe"):
    with tempfile.TemporaryDirectory() as tmp:
        out = Path(tmp, "stdout")
        err = Path(tmp, "stderr")
        out.write_text("\n".join(json.dumps(ev) for ev in entry["events"]))
        err.write_text("")
        parser_args = [*PATHS[path]]
        if entry["host_baseline"] is not None:
            baseline = Path(tmp, "host-baseline")
            baseline.write_text(
                "\n".join(
                    json.dumps(ev)
                    for ev in (entry["host_baseline"], RESULT)
                )
            )
            parser_args.extend(["--host-init-baseline", str(baseline)])
        proc = subprocess.run(
            [sys.executable, str(parser), "0", str(out), str(err), *parser_args],
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
        for path in entry["paths"]:
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
