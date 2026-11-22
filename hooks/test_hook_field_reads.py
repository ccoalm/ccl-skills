#!/usr/bin/env python3
"""Differential test for the hooks' payload field reads.

Four scripts read PreToolUse payload fields with jq:

- ``scripts/owner-dispatch/owner-dispatch.sh pretool``;
- ``hooks/guard-merge-authorization.sh``;
- ``hooks/guard-broad-local-test.sh``;
- ``hooks/guard-edit-isolation.sh``.

Each case feeds one payload to one script and records stdout, stderr, the exit
code and the state the script leaves behind: owner-dispatch markers, the
following Stop verdict and merge grants. The expected results come from the
pinned baseline ``788470c`` and live in ``test_hook_field_reads.expected.json``,
so a shallow clone can run the test. Both sides run in the same sandbox layout,
and the sandbox path is replaced by ``<T>`` before comparison.

The test also counts jq processes for one ordinary payload per script. Each
script must read its payload fields with one jq call, so the count must fall
by the number of reads merged.

    python3 hooks/test_hook_field_reads.py               # check the working tree
    python3 hooks/test_hook_field_reads.py --regenerate  # rewrite the fixture from 788470c
    python3 hooks/test_hook_field_reads.py --dump FILE   # write full candidate results
    python3 hooks/test_hook_field_reads.py --dump-baseline FILE
"""

import argparse
import concurrent.futures
import hashlib
import json
import os
import re
import signal
import shutil
import stat
import subprocess
import sys
import tempfile

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
BASELINE = "788470c"
EXPECTED = os.path.join(REPO, "hooks", "test_hook_field_reads.expected.json")
COPIED = ("hooks", "scripts/owner-dispatch")
ENGINE = "scripts/owner-dispatch/owner-dispatch.sh"
MERGE = "hooks/guard-merge-authorization.sh"
BROAD = "hooks/guard-broad-local-test.sh"
EDIT = "hooks/guard-edit-isolation.sh"
STOP = "hooks/owner-dispatch-stop.sh"
# jq processes each script stops starting for the counted payload: the engine
# merges 5 reads, the merge guard 4, the broad-test guard 2, the edit guard 2.
JQ_SAVED = {"engine-edit": 4, "engine-bash": 4, "merge": 3, "merge-trailing-newline": 3,
            "broad": 1, "edit": 1}
# Half the 10 s timeout hooks.json gives every PreToolUse hook: a hook that
# outlives the host timeout does not block. Both sides finish in under 1 s.
STALL_SECONDS = 5
# Bash prefixes its own diagnostics with "<script>: line N:".
BASH_DIAGNOSTIC_LINE = re.compile(r"(\.sh): line [0-9]+: ")
SECRET = "SECRETMARK"
MISSING = object()
GIT_ENV = {
    "GIT_AUTHOR_NAME": "t", "GIT_AUTHOR_EMAIL": "t@example.invalid",
    "GIT_COMMITTER_NAME": "t", "GIT_COMMITTER_EMAIL": "t@example.invalid",
    "GIT_AUTHOR_DATE": "2026-01-01T00:00:00Z", "GIT_COMMITTER_DATE": "2026-01-01T00:00:00Z",
    "GIT_CONFIG_NOSYSTEM": "1",
}


def jtext(value):
    if isinstance(value, dict):
        return "{" + ",".join(
            json.dumps(k) + ":" + jtext(v) for k, v in value.items() if v is not MISSING) + "}"
    if isinstance(value, list):
        return "[" + ",".join(jtext(v) for v in value) + "]"
    return json.dumps(value)


def variants(base):
    """Field values that main reads in ways one merged read could get wrong.

    No number whose printed form differs between jq 1.6 and 1.7 (such as
    1e1000): the fixture must hold on both, and non-string values take the
    per-field reads anyway."""
    # Relative, so the value is the same in every sandbox; any PWNED file
    # anywhere under the sandbox means a value was executed.
    pwn = "$(touch PWNED)`touch PWNED`"
    return [
        ("base", base), ("absent", MISSING), ("null", None), ("false", False),
        ("true", True), ("int", 7), ("float", 1.5),
        ("array", [base, "x; touch PWNED"]), ("object", {"k": base}), ("empty", ""),
        ("nul-mid", base[:2] + "\0" + base[2:]), ("nul-only", "\0"), ("nul-tail", base + "\0"),
        ("nl-tail", base + "\n\n"), ("nl-16", base + "\n" * 16), ("nl-17", base + "\n" * 17), ("nl-mid", base[:2] + "\n" + base[2:]),
        ("nl-lead", "\n" + base), ("nl-nul-tail", base + "\n\0\n"),
        ("quotes", base + "'\"\\ " + pwn + " " + SECRET), ("unicode", base + "é提交"),
        # Base64 of this suffix contains "+" and "/", which the agent key maps.
        ("base64-specials", base + "???~~~"),
    ]


def whole_payloads(base_text):
    """Payloads that fail or partly fail to parse."""
    return [
        ("empty-input", ""), ("garbage", "not json " + SECRET), ("truncated", base_text[:-3]),
        ("two-docs", base_text + base_text), ("trailing-garbage", base_text + " x"),
        ("array", "[]"), ("string", '"' + SECRET + '"'), ("null", "null"),
    ]


def utf8_locale():
    """Hosts run hooks under a UTF-8 locale, where Bash's quote handling is
    slower than under C; the stall cases are only meaningful there."""
    listed = subprocess.run(["locale", "-a"], capture_output=True, text=True).stdout.split()
    norm = {name.lower().replace("-", ""): name for name in listed}
    for want in ("C.UTF-8", "en_US.UTF-8"):
        if want.lower().replace("-", "") in norm:
            return norm[want.lower().replace("-", "")]
    raise SystemExit("FAIL: no C.UTF-8 or en_US.UTF-8 locale; the stall cases need one")


def git_env():
    """The caller's GIT_* variables (GIT_DIR, GIT_INDEX_FILE, ...) would point
    fixture commands at the caller's repository."""
    env = {k: v for k, v in os.environ.items() if not k.startswith("GIT_")}
    env.update(GIT_ENV)
    return env


def put(obj, path, value):
    obj = json.loads(json.dumps(obj))  # deep copy
    cur = obj
    for key in path[:-1]:
        cur = cur.setdefault(key, {})
    cur[path[-1]] = value
    return obj


def dig(obj, path):
    for key in path:
        obj = obj[key]
    return obj


class Sandbox:
    def __init__(self, source):
        self.root = os.path.realpath(tempfile.mkdtemp(prefix="hook-field-reads."))
        self.plugin = os.path.join(self.root, "plugin")
        self.nopy = os.path.join(self.root, "plugin-nopy")
        self.uid = str(os.getuid())
        self.locale = utf8_locale()
        for d in ("tmp", "home/.claude/projects", "outside", "shim"):
            os.makedirs(os.path.join(self.root, d))
        self._install(source, self.plugin)
        self._install(source, self.nopy)
        os.remove(os.path.join(self.nopy, "hooks", "host-input.py"))
        self._fixtures()

    def _install(self, source, dest):
        os.makedirs(dest)
        if source == "baseline":
            archive = subprocess.run(
                ["git", "-C", REPO, "archive", BASELINE, *COPIED],
                check=True, capture_output=True, env=git_env()).stdout
            subprocess.run(["tar", "-x", "-C", dest], input=archive, check=True)
        else:
            for rel in COPIED:
                shutil.copytree(os.path.join(REPO, rel), os.path.join(dest, rel),
                                ignore=shutil.ignore_patterns("__pycache__"))

    def git(self, *args, cwd=None):
        subprocess.run(["git", *args], cwd=cwd, env=git_env(), check=True, capture_output=True)

    def _repo(self, name, files, config=None):
        path = os.path.join(self.root, name)
        os.makedirs(path)
        self.git("init", "-q", "-b", "main", cwd=path)
        for rel, text in files.items():
            os.makedirs(os.path.dirname(os.path.join(path, rel)), exist_ok=True)
            with open(os.path.join(path, rel), "w") as fh:
                fh.write(text)
        if config is not None:
            with open(os.path.join(path, ".owner-dispatch.json"), "w") as fh:
                json.dump(config, fh)
        self.git("add", "-A", cwd=path)
        self.git("commit", "-q", "-m", "init", cwd=path)
        return path

    def _fixtures(self):
        cfg = {"enabled": True, "strict": False, "gate_bash": True,
               "product_globs": ["src/**"], "exclude_globs": ["**/*_test.*"],
               "owner_hint": "the owner"}
        self.prod = self._repo("prod", {"src/foo.go": "package x\n", "README.md": "r\n"}, cfg)
        self.strict = self._repo("strict", {"src/foo.go": "package x\n"}, dict(cfg, strict=True))
        self.plain = self._repo("plain", {"a.txt": "a\n"})
        # A regular file whose name ends in a newline, beside a symlink with the
        # trimmed name that points outside: trimming the path changes the verdict.
        self.shared = self._repo("shared", {"a.txt": "a\n", ".worktree-only": "", "nl\n": "n\n"})
        with open(os.path.join(self.root, "outside", "nl"), "w") as fh:
            fh.write("o\n")
        os.symlink(os.path.join(self.root, "outside", "nl"), os.path.join(self.shared, "nl"))
        self.main = self._repo("mr-main", {"a.txt": "a\n"})
        self.git("branch", "-q", "feature", cwd=self.main)
        self.git("worktree", "add", "-q", os.path.join(self.root, "mr-feat"), "feature",
                 cwd=self.main)
        self.auth = os.path.join(self.root, "tmp", "ccl-skills-merge-auth-" + self.uid)
        shim = os.path.join(self.root, "shim", "jq")
        with open(shim, "w") as fh:
            fh.write('#!/bin/sh\necho x >> "$JQ_COUNT_FILE"\nexec "%s" "$@"\n' % shutil.which("jq"))
        os.chmod(shim, stat.S_IRWXU)

    def env(self, extra=None):
        env = {"PATH": os.environ["PATH"], "HOME": os.path.join(self.root, "home"),
               "TMPDIR": os.path.join(self.root, "tmp"), "LC_ALL": self.locale}
        env.update(extra or {})
        return env

    def run(self, script, payload, cwd=None, args=(), extra_env=None, plugin=None, timeout=60):
        # The payload is JSON text, so the sandbox path goes in JSON-escaped.
        payload = payload.replace("<T>", json.dumps(self.root)[1:-1])
        # Own process group, so a timeout also ends jq inside the hook.
        proc = subprocess.Popen(
            ["bash", os.path.join(plugin or self.plugin, script), *args],
            stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
            cwd=cwd or self.root, env=self.env(extra_env), start_new_session=True)
        try:
            out, err = proc.communicate(payload.encode("utf-8", "surrogatepass"), timeout=timeout)
        except subprocess.TimeoutExpired:
            os.killpg(proc.pid, signal.SIGKILL)
            proc.communicate()
            return {"rc": "timeout after %ds" % timeout, "stdout": "", "stderr": ""}
        # Bash diagnostics (such as the warning when $(...) drops a NUL) name
        # the script line, which inserted code moves. Only that number is
        # normalized; the diagnostic text is still compared.
        return {"rc": proc.returncode, "stdout": self.norm(out),
                "stderr": BASH_DIAGNOSTIC_LINE.sub(r"\1: line <N>: ", self.norm(err))}

    def norm(self, data):
        text = data.decode("utf-8", "backslashreplace")
        return text.replace(self.root, "<T>").replace("merge-auth-" + self.uid, "merge-auth-<UID>")

    def state_dirs(self):
        for repo in (self.prod, self.strict):
            yield repo, os.path.join(repo, ".git", "owner-dispatch")

    def engine_state(self):
        out = {}
        for repo, d in self.state_dirs():
            if not os.path.isdir(d):
                continue
            for name in sorted(os.listdir(d)):
                key = os.path.basename(repo) + "/" + name
                with open(os.path.join(d, name), "rb") as fh:
                    out[key] = self.norm(fh.read())
        return out

    def grants(self):
        if not os.path.isdir(self.auth):
            return {}
        out = {}
        for name in sorted(os.listdir(self.auth)):
            with open(os.path.join(self.auth, name), "rb") as fh:
                out[name] = self.norm(fh.read())
        return out

    def check_not_executed(self):
        for top, _dirs, files in os.walk(self.root):
            if "PWNED" in files:
                raise AssertionError("payload text was executed: %s/PWNED exists" % top)

    def reset(self):
        self.check_not_executed()
        for repo, d in self.state_dirs():
            shutil.rmtree(d, ignore_errors=True)
            self.git("checkout", "-q", "--", ".", cwd=repo)
        shutil.rmtree(self.auth, ignore_errors=True)
        os.makedirs(self.auth, mode=0o700)
        for sid in ("SA", "SB"):
            with open(os.path.join(self.auth, sid), "w") as fh:
                fh.write("armed\n")

    def close(self):
        shutil.rmtree(self.root, ignore_errors=True)


def field_cases(name, base, fields):
    """One case per (field, variant), plus the whole-payload cases."""
    cases = []
    for path in fields:
        for label, value in variants(dig(base, path)):
            cases.append(("%s/%s/%s" % (name, ".".join(path), label), jtext(put(base, path, value))))
    for label, text in whole_payloads(jtext(base)):
        cases.append(("%s/whole/%s" % (name, label), text))
    return cases


def group_engine_edit(sb, record):
    # Owner-dispatch engine, Edit: the strict repo's denial names the session's
    # waiver file, and the markers name session and agent.
    edit = {"session_id": "S1", "agent_id": "A1", "tool_name": "Edit",
            "tool_input": {"file_path": "<T>/strict/src/foo.go"}}
    for case_id, payload in field_cases("engine-edit", edit, [
            ("session_id",), ("agent_id",), ("tool_name",), ("tool_input", "file_path")]):
        sb.reset()
        res = sb.run(ENGINE, payload, args=("pretool",))
        res["state"] = sb.engine_state()
        record(case_id, res)
    for key in ("notebook_path", "path"):
        for label, value in variants("<T>/strict/src/foo.go"):
            sb.reset()
            payload = jtext(dict(edit, tool_input={"file_path": None, key: value}))
            res = sb.run(ENGINE, payload, args=("pretool",))
            res["state"] = sb.engine_state()
            record("engine-edit/tool_input.%s/%s" % (key, label), res)



def group_engine_bash(sb, record):
    # Engine, Bash write heuristic: silent, so the markers are the evidence.
    bash = {"session_id": "S1", "agent_id": "A1", "tool_name": "Bash",
            "tool_input": {"command": "echo x > src/foo.go"}}
    for case_id, payload in field_cases("engine-bash", bash, [
            ("session_id",), ("agent_id",), ("tool_name",), ("tool_input", "command")]):
        sb.reset()
        res = sb.run(ENGINE, payload, cwd=sb.prod, args=("pretool",))
        res["state"] = sb.engine_state()
        record(case_id, res)



def group_stop(sb, record):
    # A real gated edit in an opted-in repository, then the Stop verdict for
    # the same session and agent. Stop must block the actor that edited.
    for field in ("session_id", "agent_id"):
        for label, value in variants("S1" if field == "session_id" else "A1"):
            sb.reset()
            pre = put({"session_id": "S1", "agent_id": "A1", "tool_name": "Edit",
                       "tool_input": {"file_path": "<T>/prod/src/foo.go"}}, (field,), value)
            first = sb.run(ENGINE, jtext(pre), args=("pretool",))
            with open(os.path.join(sb.prod, "src", "foo.go"), "a") as fh:
                fh.write("// edited\n")
            stop_payload = {k: v for k, v in pre.items() if k in ("session_id", "agent_id")}
            stop = sb.run(STOP, jtext(stop_payload), cwd=sb.prod)
            record("stop/%s/%s" % (field, label), {
                "pretool": first, "stop": stop, "state": sb.engine_state()})



def group_merge(sb, record):
    # Merge guard. Two sessions hold one-shot grants; a landing command must
    # consume only its own session's grant, once.
    merge = {"session_id": "SA", "cwd": "<T>/mr-feat",
             "transcript_path": "<T>/home/.claude/projects/t.jsonl",
             "tool_input": {"command": "gh pr merge 12 --squash"}}
    for case_id, payload in field_cases("merge", merge, [
            ("tool_input", "command"), ("cwd",), ("session_id",), ("transcript_path",)]):
        sb.reset()
        res = sb.run(MERGE, payload, extra_env={"CLAUDECODE": "1"})
        res["again"] = sb.run(MERGE, payload, extra_env={"CLAUDECODE": "1"})
        res["grants"] = sb.grants()
        record(case_id, res)
    for label, cmd, cwd in (
            ("denied-git-push", "git push origin main", "<T>/mr-main"),
            ("compound", "gh pr merge 12 --squash && git push origin main", "<T>/mr-feat"),
            ("landing-from-main", "gh pr merge 12 --squash", "<T>/mr-main")):
        sb.reset()
        payload = jtext(dict(merge, cwd=cwd, tool_input={"command": cmd}))
        res = sb.run(MERGE, payload, extra_env={"CLAUDECODE": "1"})
        res["grants"] = sb.grants()
        record("merge/scenario/" + label, res)



def group_broad(sb, record):
    # Broad local test guard.
    broad = {"tool_name": "Bash", "tool_input": {"command": "pytest"}}
    for case_id, payload in field_cases("broad", broad, [("tool_name",), ("tool_input", "command")]):
        sb.reset()
        record(case_id, sb.run(BROAD, payload, cwd=sb.plain))
    sb.reset()
    record("broad/scenario/narrow", sb.run(
        BROAD, jtext(put(broad, ("tool_input", "command"), "pytest tests/test_x.py")), cwd=sb.plain))



def group_edit(sb, record):
    # Edit isolation guard, with and without the Python normalizer.
    edit_iso = {"tool_name": "Edit", "tool_input": {"file_path": "<T>/shared/a.txt"}}

    def patch(body):
        return {"tool_name": "apply_patch", "cwd": "<T>",
                "tool_input": {"command": "*** Begin Patch\n" + body + "*** End Patch"}}

    scenarios = {
        "protected": edit_iso,
        "plain": put(edit_iso, ("tool_input", "file_path"), "<T>/plain/a.txt"),
        "nl-name-beside-symlink": put(edit_iso, ("tool_input", "file_path"), "<T>/shared/nl\n"),
        "patch-malformed-empty": {"tool_name": "apply_patch", "tool_input": {"command": "nope"}},
        "patch-malformed-with-target": patch("*** Add File: plain/b.txt\n+x\n*** Bogus\n"),
        "patch-second-target-protected": patch(
            "*** Add File: plain/b.txt\n+x\n*** Add File: shared/b.txt\n+x\n"),
        "patch-plain": patch("*** Add File: plain/b.txt\n+x\n"),
    }
    # Several documents: the jq-only normalizer emits one object for each.
    raw = {
        "two-empty-docs": "{}{}",
        "two-docs-second-protected": jtext(scenarios["plain"]) + jtext(edit_iso),
    }
    for plugin_label, plugin in (("py", sb.plugin), ("nopy", sb.nopy)):
        for label, payload in scenarios.items():
            sb.reset()
            record("edit/%s/scenario/%s" % (plugin_label, label),
                   sb.run(EDIT, jtext(payload), plugin=plugin))
        for label, text in raw.items():
            sb.reset()
            record("edit/%s/scenario/%s" % (plugin_label, label),
                   sb.run(EDIT, text, cwd=sb.shared, plugin=plugin))
        for case_id, payload in field_cases("edit/" + plugin_label, edit_iso,
                                            [("tool_name",), ("tool_input", "file_path")]):
            sb.reset()
            record(case_id, sb.run(EDIT, payload, plugin=plugin))


def group_stall(sb, record):
    """Payloads that make some jq decodings superlinear must not stall a hook.

    A hook that outlives the host's timeout does not block, so a stall would
    let the call through. Main strips these in bash at no cost."""
    # Sized so the superlinear forms take well over the limit on jq 1.6 and
    # Bash 5.2; the broad guard's payloads stay under its 1 MiB input head.
    for label, suffix, broad_suffix in (
            ("newlines", "\n" * 200000, "\n" * 200000),
            ("nuls", "\0" * 800000, "\0" * 100000),
            ("apostrophes", "'" * 900000, "'" * 900000)):
        runs = {
            "engine-edit": (ENGINE, {"session_id": "S1", "tool_name": "Edit",
                                     "tool_input": {"file_path": "<T>/strict/src/foo.go" + suffix}},
                            None, ("pretool",)),
            "engine-bash": (ENGINE, {"session_id": "S1", "tool_name": "Bash",
                                     "tool_input": {"command": "echo x > src/foo.go" + suffix}},
                            sb.prod, ("pretool",)),
            "merge": (MERGE, {"session_id": "SA", "cwd": "<T>/mr-feat",
                              "tool_input": {"command": "gh pr merge 12 --squash" + suffix}},
                      None, ()),
            "broad": (BROAD, {"tool_name": "Bash",
                              "tool_input": {"command": "pytest" + broad_suffix}},
                      sb.plain, ()),
        }
        for name, (script, payload, cwd, args) in runs.items():
            sb.reset()
            res = sb.run(script, jtext(payload), cwd=cwd, args=args, timeout=STALL_SECONDS,
                         extra_env={"CLAUDECODE": "1"})
            res["state"] = sb.engine_state()
            res["grants"] = sb.grants()
            record("stall/%s/%s" % (name, label), res)
    # A long agent id whose base64 is full of "/" and "+".
    sb.reset()
    res = sb.run(ENGINE, jtext({"session_id": "S1", "agent_id": "?~" * 350000, "tool_name": "Bash",
                                "tool_input": {"command": "echo x > src/foo.go"}}),
                 cwd=sb.prod, args=("pretool",), timeout=STALL_SECONDS)
    res["state"] = sb.engine_state()
    record("stall/engine-bash/agent-key", res)


GROUPS = (group_engine_edit, group_engine_bash, group_stop, group_merge, group_broad, group_edit,
          group_stall)


def run_group(source, group):
    """Run one group in its own sandbox, so groups can run concurrently."""
    results = {}

    def record(case_id, result):
        if case_id in results:
            raise AssertionError("duplicate case id " + case_id)
        results[case_id] = result

    sb = Sandbox(source)
    try:
        if group is None:
            return {}, count_jq(sb)
        group(sb, record)
        sb.check_not_executed()
        return results, {}
    finally:
        sb.close()


def count_jq(sb):
    """jq processes started for one ordinary payload per script."""
    runs = {
        "engine-edit": (ENGINE, {"session_id": "S1", "tool_name": "Edit",
                                 "tool_input": {"file_path": "<T>/plain/a.txt"}}, ("pretool",)),
        "engine-bash": (ENGINE, {"session_id": "S1", "tool_name": "Bash",
                                 "tool_input": {"command": "ls"}}, ("pretool",)),
        "merge": (MERGE, {"session_id": "SA", "cwd": "<T>/mr-feat",
                          "tool_input": {"command": "ls"}}, ()),
        # A command ending in a newline keeps the one-call read.
        "merge-trailing-newline": (MERGE, {"session_id": "SA", "cwd": "<T>/mr-feat",
                                           "tool_input": {"command": "ls\n"}}, ()),
        "broad": (BROAD, {"tool_name": "Bash", "tool_input": {"command": "ls"}}, ()),
        "edit": (EDIT, {"tool_name": "Edit", "tool_input": {"file_path": "<T>/plain/a.txt"}}, ()),
    }
    counts = {}
    for name, (script, payload, args) in runs.items():
        sb.reset()
        count_file = os.path.join(sb.root, "jq-count")
        open(count_file, "w").close()
        env = {"PATH": os.path.join(sb.root, "shim") + os.pathsep + os.environ["PATH"],
               "JQ_COUNT_FILE": count_file}
        res = sb.run(script, jtext(payload), args=args, extra_env=env)
        with open(count_file) as fh:
            counts[name] = len(fh.read().splitlines())
        if res["rc"] != 0 or counts[name] < 1:
            raise AssertionError("jq count run for %s failed: %s, %d jq processes" % (
                name, res, counts[name]))
    return counts


def digest(result):
    return hashlib.sha256(json.dumps(result, sort_keys=True).encode()).hexdigest()


def summary(result):
    text = json.dumps(result, sort_keys=True, ensure_ascii=False)
    return text if len(text) <= 400 else text[:400] + "..."


def write_dump(path, results):
    with open(path, "w") as fh:
        json.dump(results, fh, indent=1, sort_keys=True, ensure_ascii=False)


def stderr_texts(result):
    yield result.get("stderr", "")
    for value in result.values():
        if isinstance(value, dict) and "rc" in value:
            yield value["stderr"]


def collect(source):
    results, counts = {}, {}
    with concurrent.futures.ThreadPoolExecutor(max_workers=len(GROUPS) + 1) as pool:
        for part, part_counts in pool.map(lambda g: run_group(source, g), GROUPS + (None,)):
            if set(part) & set(results):
                raise AssertionError("duplicate case ids across groups")
            results.update(part)
            counts.update(part_counts)
    return results, counts


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--regenerate", action="store_true",
                    help="rewrite the fixture from baseline %s" % BASELINE)
    ap.add_argument("--dump", metavar="FILE", help="write the full candidate results as JSON")
    ap.add_argument("--dump-baseline", metavar="FILE",
                    help="write the full baseline results as JSON and exit")
    opts = ap.parse_args()
    for tool in ("jq", "git", "python3"):
        if not shutil.which(tool):
            print("FAIL: %s is required" % tool, file=sys.stderr)
            return 1

    if opts.dump_baseline:
        write_dump(opts.dump_baseline, collect("baseline")[0])
        return 0
    if opts.regenerate:
        results, counts = collect("baseline")
        fixture = {"baseline": BASELINE, "jq_counts": counts,
                   "cases": {k: digest(v) for k, v in sorted(results.items())}}
        with open(EXPECTED, "w") as fh:
            json.dump(fixture, fh, indent=1, sort_keys=True, ensure_ascii=False)
            fh.write("\n")
        print("wrote %d cases to %s" % (len(results), os.path.relpath(EXPECTED, REPO)))
        return 0

    with open(EXPECTED) as fh:
        fixture = json.load(fh)
    results, counts = collect("candidate")
    if opts.dump:
        write_dump(opts.dump, results)

    failures = []
    expected = fixture["cases"]
    if sorted(expected) != sorted(results):
        failures.append("case set differs: missing %s, extra %s" % (
            sorted(set(expected) - set(results))[:5], sorted(set(results) - set(expected))[:5]))
    for case_id in sorted(set(expected) & set(results)):
        if digest(results[case_id]) != expected[case_id]:
            failures.append("%s differs from %s\n  candidate: %s" % (
                case_id, BASELINE, summary(results[case_id])))
    for case_id, result in sorted(results.items()):
        if any(SECRET in text for text in stderr_texts(result)):
            failures.append("%s: payload text reached stderr" % case_id)
    for name, saved in sorted(JQ_SAVED.items()):
        want = fixture["jq_counts"][name] - saved
        if counts[name] > want:
            failures.append("%s starts %d jq processes; at most %d expected (baseline %d)" % (
                name, counts[name], want, fixture["jq_counts"][name]))

    for failure in failures:
        print("FAIL " + failure)
    if failures:
        print("To compare in full: --dump FILE and --dump-baseline FILE")
    print("%d cases, %d failures" % (len(results), len(failures)))
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
