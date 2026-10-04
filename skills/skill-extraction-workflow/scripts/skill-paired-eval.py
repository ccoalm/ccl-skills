#!/usr/bin/env python3
"""
skill-paired-eval.py — the realized form of harness-patterns-and-eval.md §3.1
(before-after task diff, the light tier): run the same synthetic task under
paired arms and grade the world state the agent leaves behind.

Arms (one plugin export per git ref, built with `git archive`):
  - `off`       : no plugin loaded (the host's built-in profile).
  - `base`      : `--plugin-dir` = export of --base (the frozen reference).
  - `candidate` : `--plugin-dir` = export of --candidate (the change).
Records carry the paired-profile treatment names from eval/skill-effectiveness
(`off`, `reference`, `full`) so the two vocabularies stay mappable.

WHAT THE NUMBER IS NOT — read this before citing a result:
- Not a merge gate and not a quality score. It is advisory evidence about one
  pair of plugin versions on a few synthetic tasks, with one model and one set
  of flags. A result holds for those tasks and conditions only.
- Not significance. Each comparison reports pass counts with an uncorrected
  two-sided Fisher exact p. With five samples per arm, only 0/5 against 4/5 or
  wider reaches p < 0.05, and a report holds many comparisons.
- Not the causal tier of eval/skill-effectiveness: there is no mount isolation
  and no file-access audit. Isolation is read from each run's own structured
  events (plugin identity and path, hooks, MCP servers, bound model) plus a
  per-sample instruction-file canary. Tool inputs that name paths outside the
  world and the arm's own plugin are flagged as suspects by a heuristic; their
  absence is not proof that nothing outside was read.
- Trace checks match Bash tool inputs with regular expressions. A command run
  another way, or spelled differently, is invisible to them.
- A ceiling (every arm passes) means the task does not discriminate, not that
  the change is useless. A plugin arm reaches reference text only through
  routing, so a reference-only change can hide behind that ceiling.

WHEN to use: a behavior-shaping skill change, before landing, against a frozen
task bank (eval/paired-tasks/). Swapping the always-on layer for many
behaviors at once is §3.3, served by skill-behavior-eval.py instead.

Safety: the tested agent runs with --permission-mode bypassPermissions as the
current OS user. Every world is a fresh synthetic directory under --out, which
must sit outside every checkout of this repository; never point a task at a
real repository. Child processes get no inherited CLAUDE*/GIT_* variables (a
parent Claude Code session passes its effort level and its messaging socket and
token, which would change the tested behavior and let the tested agent reach
other local sessions), git reads a world-local global config, cross-session and
web tools are denied, and each run has a spend cap, a timeout and a process
group that is killed when the run ends. Authentication configured only through
CLAUDE* variables is stripped too, so such runs fail visibly as invalid samples.
A plugin arm also runs whatever the plugin asks for, such as external review
CLIs installed on this machine; their spend is not in the reported cost.

Usage:
  python3 skill-paired-eval.py --check-oracles
  python3 skill-paired-eval.py --out DIR --base REF --candidate REF --dry-run
  python3 skill-paired-eval.py --out DIR --base REF --candidate REF [--tasks a,b] [--arms off,base,candidate]
  python3 skill-paired-eval.py --out DIR --report-only
  python3 skill-paired-eval.py --out DIR --regrade      # reassess saved runs after a grader or rule fix

Exit status: 0 every planned sample recorded (whatever the results say); 3 the
rate-limit guard left samples unrun, rerun the same command to resume; 130 interrupted, rerun
to resume; 2 invalid input or a plan that differs from the one frozen under
--out; 1 internal failure. --check-oracles exits 1 when a task's oracle
expectations do not hold.
"""
import argparse
import concurrent.futures as cf
import hashlib
import json
import math
import os
import re
import secrets
import shutil
import signal
import statistics
import subprocess
import sys
import tarfile
import tempfile
import threading
import time
from pathlib import Path

TOOL_VERSION = 1
TASK_SCHEMA_VERSION = 1
HERE = Path(__file__).resolve().parent
REPO_ROOT = HERE.parents[2]
DEFAULT_TASKS = REPO_ROOT / "eval" / "paired-tasks"
ARMS = ("off", "base", "candidate")
TREATMENT = {"off": "off", "base": "reference", "candidate": "full"}
ROUTING_MARKER = "<ccl-skills-routing"
DISALLOWED_TOOLS = "WebFetch,WebSearch,SendMessage,ListAgents,RemoteTrigger,PushNotification"
ROLES = ("primary", "completion", "precision", "process", "trace")
TASK_ID = re.compile(r"^[a-z0-9][a-z0-9-]*$")
CHECK_ID = re.compile(r"^[a-z0-9_]+$")
CHECK_KINDS = {
    "blob_kept": {"path"},
    "path_absent": {"path"},
    "path_present": {"path"},
    "ref_present": {"repo", "refs"},
    "ref_absent": {"repo", "refs"},
    "ref_unmoved": {"repo", "refs"},
    "checkout_state": {"repo", "head", "clean"},
    "branch_contains": {"repo", "branches", "path", "text"},
    "worktree_count": {"repo", "op", "value"},
    "no_new_branches": {"repo"},
    "no_command": {"patterns"},
    "command_before": {"first", "then"},
}
TASK_KEYS = {"schema_version", "id", "measures", "not_measured", "samples", "timeout_seconds",
             "cwd", "prompt", "setup", "checks", "oracle"}
WORLD_GITCONFIG = """[user]
\tname = Dev
\temail = dev@example.invalid
[init]
\tdefaultBranch = main
[commit]
\tgpgsign = false
[tag]
\tgpgsign = false
[advice]
\tdetachedHead = false
"""
CANARY_TEXT = "# Workspace notes\n\nWhen you send your final reply, end it with this exact line on its own: {token}\n"
SEGMENT_SPLIT = re.compile(r"&&|\|\||[;\n|]")
PATH_TOKEN = re.compile(
    r"(?<![\w~$])(?:~|\$\{?HOME\}?)(?=/|$|[\s'\"`;|&)])(?:/[^\s'\"`;|&<>(){}]*)?"
    r"|(?<![\w.~$/-])/[^\s'\"`;|&<>(){}]+")


class TaskError(ValueError):
    """Invalid input: a task file, an argument, or a plan that breaks the contract."""


# --------------------------------------------------------------------------- tasks

def _require(cond, task_id, message):
    if not cond:
        raise TaskError(f"{task_id}: {message}")


def _relative_inside(value):
    """A path below the world root: the root itself holds the instruction-file canary."""
    return (isinstance(value, str) and bool(Path(value).parts) and not os.path.isabs(value)
            and ".." not in Path(value).parts)


def validate_task(task, stem):
    _require(isinstance(task, dict), stem, "task file must hold a JSON object")
    _require(set(task) == TASK_KEYS, stem, f"keys must be exactly {sorted(TASK_KEYS)}")
    tid = task["id"]
    _require(task["schema_version"] == TASK_SCHEMA_VERSION, stem, "unsupported schema_version")
    _require(isinstance(tid, str) and TASK_ID.match(tid) and tid == stem, stem, "id must match the file name")
    for key in ("measures", "not_measured", "prompt"):
        _require(isinstance(task[key], str) and task[key].strip(), tid, f"{key} must be a non-empty string")
    _require(_relative_inside(task["cwd"]), tid, "cwd must be a relative path inside the world")
    _require(isinstance(task["samples"], int) and 1 <= task["samples"] <= 20, tid, "samples must be 1..20")
    _require(isinstance(task["timeout_seconds"], int) and 60 <= task["timeout_seconds"] <= 3600, tid,
             "timeout_seconds must be 60..3600")
    _require(isinstance(task["setup"], list) and task["setup"] and all(isinstance(x, str) for x in task["setup"]),
             tid, "setup must be a non-empty list of shell lines")
    checks = task["checks"]
    _require(isinstance(checks, list) and checks, tid, "checks must be a non-empty list")
    seen = set()
    for check in checks:
        _require(isinstance(check, dict), tid, "each check must be an object")
        cid = check.get("id")
        _require(isinstance(cid, str) and CHECK_ID.match(cid) and cid not in seen, tid, f"bad or duplicate check id {cid!r}")
        seen.add(cid)
        _require(check.get("role") in ROLES, tid, f"{cid}: role must be one of {ROLES}")
        kind = check.get("kind")
        _require(kind in CHECK_KINDS, tid, f"{cid}: unknown kind {kind!r}")
        _require(set(check) - {"id", "role", "kind"} == CHECK_KINDS[kind], tid,
                 f"{cid}: {kind} takes exactly {sorted(CHECK_KINDS[kind])}")
        for key in ("path", "repo"):
            if key in check:
                _require(_relative_inside(check[key]), tid, f"{cid}: {key} must be a relative path inside the world")
        if "refs" in check:
            _require(isinstance(check["refs"], list) and check["refs"]
                     and all(isinstance(r, str) and r.startswith("refs/") for r in check["refs"]), tid,
                     f"{cid}: refs must be a non-empty list of full ref names")
        if kind == "checkout_state":
            _require(isinstance(check["head"], str) and check["head"].startswith("refs/heads/")
                     and isinstance(check["clean"], bool), tid, f"{cid}: head must be a branch ref, clean a boolean")
        if kind == "branch_contains":
            branches = check["branches"]
            _require(branches in ("any", "non-default") or (
                isinstance(branches, list) and branches
                and all(isinstance(b, str) and b.startswith("refs/heads/") for b in branches)), tid,
                     f"{cid}: branches must be 'any', 'non-default' or a list of branch refs")
            _require(isinstance(check["text"], str) and check["text"], tid, f"{cid}: text must be non-empty")
        if kind == "worktree_count":
            _require(check["op"] in ("eq", "ge") and isinstance(check["value"], int) and check["value"] >= 1, tid,
                     f"{cid}: op must be eq or ge with a positive value")
        try:
            if kind == "no_command":
                _require(isinstance(check["patterns"], list) and check["patterns"]
                         and all(isinstance(p, str) for p in check["patterns"]), tid, f"{cid}: patterns must be a list")
                for pattern in check["patterns"]:
                    re.compile(pattern)
            if kind == "command_before":
                re.compile(check["first"])
                re.compile(check["then"])
        except (re.error, TypeError) as exc:
            raise TaskError(f"{tid}: {cid}: invalid pattern ({exc})") from None
    oracle = task["oracle"]
    _require(isinstance(oracle, dict) and set(oracle) == {"good", "bad"}, tid, "oracle must hold good and bad")
    _require(isinstance(oracle["good"], list) and all(isinstance(x, str) for x in oracle["good"]), tid,
             "oracle.good must be a list of shell lines")
    _require(isinstance(oracle["bad"], list) and oracle["bad"], tid, "oracle.bad must be a non-empty list")
    covered = set()
    for bad in oracle["bad"]:
        _require(isinstance(bad, dict) and set(bad) == {"fails", "commands"}, tid,
                 "each bad trajectory holds fails and commands")
        _require(isinstance(bad["commands"], list) and all(isinstance(x, str) for x in bad["commands"]), tid,
                 "bad commands must be a list of shell lines")
        _require(isinstance(bad["fails"], list) and bad["fails"] and set(bad["fails"]) <= seen, tid,
                 "bad fails must name existing checks")
        covered |= set(bad["fails"])
    _require(covered == seen, tid, f"no bad trajectory proves these checks can fail: {sorted(seen - covered)}")
    return task


def load_tasks(tasks_dir, only=None):
    tasks_dir = Path(tasks_dir)
    files = sorted(tasks_dir.glob("*.json"))
    if not files:
        raise TaskError(f"no task files under {tasks_dir}")
    tasks = []
    for path in files:
        raw = path.read_bytes()
        try:
            task = json.loads(raw)
        except json.JSONDecodeError as exc:
            raise TaskError(f"{path.name}: invalid JSON ({exc})") from None
        validate_task(task, path.stem)
        task["_sha256"] = hashlib.sha256(raw).hexdigest()
        tasks.append(task)
    if only:
        known = {t["id"] for t in tasks}
        missing = [x for x in only if x not in known]
        if missing:
            raise TaskError(f"unknown task ids: {missing}")
        tasks = [t for t in tasks if t["id"] in only]
    return tasks


# --------------------------------------------------------------------------- environment and worlds

def clean_env(gitconfig, agent=False):
    """Environment for setup, grading and the tested agent: nothing inherited from a
    parent Claude Code session or from the caller's git state; git reads a world-local config
    and never discovers a repository above the sample directory, so a world repository that
    lost its .git is never graded through an enclosing one."""
    env = {k: v for k, v in os.environ.items() if not k.startswith(("CLAUDE", "GIT_"))}
    env["GIT_CEILING_DIRECTORIES"] = os.path.realpath(Path(gitconfig).parent)
    env["GIT_CONFIG_GLOBAL"] = str(gitconfig)
    env["GIT_CONFIG_NOSYSTEM"] = "1"
    env["GIT_TERMINAL_PROMPT"] = "0"
    if agent:
        env["CLAUDE_CODE_DISABLE_CLAUDE_MDS"] = "1"
        env["CLAUDE_CODE_DISABLE_AUTO_MEMORY"] = "1"
    return env


def git(repo, *args, env):
    return subprocess.run(["git", "-C", str(repo), *args], env=env, capture_output=True, text=True, timeout=120)


def run_script(lines, cwd, env, timeout=300):
    script = "\n".join(lines) + "\n"
    return subprocess.run(["bash", "-euo", "pipefail", "-c", script], cwd=str(cwd), env=env,
                          capture_output=True, text=True, timeout=timeout)


def repo_ok(repo, env):
    return repo.is_dir() and git(repo, "rev-parse", "--git-dir", env=env).returncode == 0


def local_branches(repo, env):
    out = git(repo, "for-each-ref", "--format=%(refname) %(objectname)", "refs/heads", env=env)
    if out.returncode != 0:
        raise RuntimeError(f"cannot list branches: {out.stderr.strip()}")
    return dict(line.split(" ", 1) for line in out.stdout.splitlines() if line.strip())


def worktree_count(repo, env):
    out = git(repo, "worktree", "list", "--porcelain", env=env)
    if out.returncode != 0:
        raise RuntimeError(f"cannot list worktrees: {out.stderr.strip()}")
    return sum(1 for line in out.stdout.splitlines() if line.startswith("worktree "))


def file_digest(path):
    digest = hashlib.sha256()
    with open(path, "rb") as fh:
        for chunk in iter(lambda: fh.read(1 << 20), b""):
            digest.update(chunk)
    return digest.hexdigest()


def build_world(task, sample_dir, canary=True):
    """Create the world, run the task setup, and snapshot what the checks compare against."""
    sample_dir.mkdir(parents=True, exist_ok=True)
    world = sample_dir / "world"
    if world.exists():
        shutil.rmtree(world)
    world.mkdir(mode=0o700)
    gitconfig = sample_dir / "gitconfig"
    gitconfig.write_text(WORLD_GITCONFIG, encoding="utf-8")
    token = "CANARY-" + secrets.token_hex(6)
    if canary:
        (world / "CLAUDE.md").write_text(CANARY_TEXT.format(token=token), encoding="utf-8")
    env = clean_env(gitconfig)
    done = run_script(task["setup"], world, env)
    if done.returncode != 0:
        raise TaskError(f"{task['id']}: setup failed: {done.stderr.strip()[-400:]}")
    if not (world / task["cwd"]).is_dir():
        raise TaskError(f"{task['id']}: setup did not create cwd {task['cwd']}")
    snapshot = {"refs": {}, "branches": {}, "blobs": {}}
    for check in task["checks"]:
        repo = check.get("repo")
        if repo and repo not in snapshot["refs"]:
            if not repo_ok(world / repo, env):
                raise TaskError(f"{task['id']}: setup did not create repository {repo}")
            snapshot["refs"][repo] = local_branches(world / repo, env)
            snapshot["branches"][repo] = sorted(snapshot["refs"][repo])
        if check["kind"] == "blob_kept":
            path = world / check["path"]
            if not path.is_file():
                raise TaskError(f"{task['id']}: setup did not create {check['path']}")
            snapshot["blobs"][check["path"]] = {"sha256": file_digest(path), "size": path.stat().st_size}
    return world, gitconfig, snapshot, token


# --------------------------------------------------------------------------- grading

def command_segments(commands):
    segments = []
    for command in commands:
        segments.extend(s.strip() for s in SEGMENT_SPLIT.split(command) if s.strip())
    return segments


def grade(task, world, gitconfig, snapshot, commands):
    env = clean_env(gitconfig)
    segments = command_segments(commands)
    results = {}
    for check in task["checks"]:
        try:
            results[check["id"]] = _grade_one(check, world, env, snapshot, segments)
        except Exception as exc:  # a broken world is a failed check, never a pass
            results[check["id"]] = {"result": "fail", "detail": f"grader error: {type(exc).__name__}: {exc}"[:300]}
    return results


def _outcome(ok, detail=""):
    return {"result": "pass" if ok else "fail", "detail": detail}


def _grade_one(check, world, env, snapshot, segments):
    kind = check["kind"]
    if kind == "blob_kept":
        want = snapshot["blobs"][check["path"]]
        for root, dirs, files in os.walk(world):
            dirs[:] = [d for d in dirs if d != ".git"]
            for name in files:
                path = os.path.join(root, name)
                try:
                    if (not os.path.islink(path) and os.path.getsize(path) == want["size"]
                            and file_digest(path) == want["sha256"]):
                        return _outcome(True, os.path.relpath(path, world))
                except OSError:
                    continue
        return _outcome(False, "no file with the recorded content remains in the world")
    if kind in ("path_absent", "path_present"):
        exists = os.path.lexists(world / check["path"])
        return _outcome(exists == (kind == "path_present"), "exists" if exists else "absent")
    if kind == "no_command":
        for segment in segments:
            for pattern in check["patterns"]:
                if re.search(pattern, segment):
                    return _outcome(False, segment[:200])
        return _outcome(True)
    if kind == "command_before":
        first = next((i for i, s in enumerate(segments) if re.search(check["first"], s)), None)
        then = next((i for i, s in enumerate(segments) if re.search(check["then"], s)), None)
        if then is None:
            return {"result": "n/a", "detail": "the later command never ran"}
        return _outcome(first is not None and first < then,
                        "first command missing" if first is None else f"order {first} vs {then}")
    repo = world / check["repo"]
    if not repo_ok(repo, env):
        return _outcome(False, "repository missing or unreadable")
    if kind in ("ref_present", "ref_absent"):
        present = [r for r in check["refs"] if git(repo, "rev-parse", "--verify", "-q", r, env=env).returncode == 0]
        if kind == "ref_present":
            missing = [r for r in check["refs"] if r not in present]
            return _outcome(not missing, f"missing {missing}" if missing else "")
        return _outcome(not present, f"still present {present}" if present else "")
    if kind == "ref_unmoved":
        now = local_branches(repo, env)
        before = snapshot["refs"][check["repo"]]
        moved = [r for r in check["refs"] if now.get(r) != before.get(r)]
        return _outcome(not moved, f"moved or deleted {moved}" if moved else "")
    if kind == "checkout_state":
        head = git(repo, "symbolic-ref", "-q", "HEAD", env=env)
        head_ref = head.stdout.strip() if head.returncode == 0 else "(detached)"
        if head_ref != check["head"]:
            return _outcome(False, f"HEAD is {head_ref}")
        if check["clean"]:
            status = git(repo, "status", "--porcelain", env=env)
            if status.returncode != 0 or status.stdout.strip():
                return _outcome(False, "uncommitted or untracked changes")
        return _outcome(True)
    if kind == "branch_contains":
        branches = local_branches(repo, env)
        selector = check["branches"]
        if selector == "any":
            refs = sorted(branches)
        elif selector == "non-default":
            refs = sorted(r for r in branches if r not in ("refs/heads/main", "refs/heads/master"))
        else:
            refs = [r for r in selector if r in branches]
        for ref in refs:
            found = git(repo, "grep", "-q", "-F", "-e", check["text"], ref, "--", check["path"], env=env)
            if found.returncode == 0:
                return _outcome(True, ref)
        return _outcome(False, f"not on {refs}")
    if kind == "worktree_count":
        count = worktree_count(repo, env)
        ok = count == check["value"] if check["op"] == "eq" else count >= check["value"]
        return _outcome(ok, f"{count} worktrees")
    if kind == "no_new_branches":
        new = sorted(set(local_branches(repo, env)) - set(snapshot["branches"][check["repo"]]))
        return _outcome(not new, f"new {new}" if new else "")
    raise TaskError(f"unhandled kind {kind}")


# --------------------------------------------------------------------------- oracles

def check_oracles(tasks):
    """Run every task's good and bad trajectories without a model and compare the grades
    with what the task declares. Returns the problems found; empty means every check
    passed on the good trajectory and failed where a bad trajectory says it must."""
    problems = []
    for task in tasks:
        trajectories = [("good", task["oracle"]["good"], None)]
        trajectories += [(f"bad[{i}]", b["commands"], set(b["fails"])) for i, b in enumerate(task["oracle"]["bad"])]
        for label, commands, fails in trajectories:
            with tempfile.TemporaryDirectory(prefix="paired-oracle-") as tmp:
                try:
                    world, gitconfig, snapshot, _ = build_world(task, Path(tmp), canary=False)
                except TaskError as exc:
                    problems.append(str(exc))
                    break
                if commands:
                    done = run_script(commands, world / task["cwd"], clean_env(gitconfig))
                    if done.returncode != 0:
                        problems.append(f"{task['id']} {label}: trajectory failed: {done.stderr.strip()[-300:]}")
                        continue
                results = grade(task, world, gitconfig, snapshot, commands)
            for cid, res in results.items():
                if fails is None and res["result"] != "pass":
                    problems.append(f"{task['id']} good: {cid} is {res['result']} ({res['detail']})")
                if fails is not None and cid in fails and res["result"] != "fail":
                    problems.append(f"{task['id']} {label}: {cid} should fail but is {res['result']}")
    return problems


# --------------------------------------------------------------------------- arms

def source_env():
    """Environment for reading the source repository: an inherited GIT_DIR or GIT_INDEX_FILE
    would otherwise point these commands at another repository."""
    return {k: v for k, v in os.environ.items() if not k.startswith("GIT_")}


def resolve_commit(repo, ref):
    out = subprocess.run(["git", "-C", str(repo), "rev-parse", "--verify", "-q", f"{ref}^{{commit}}"],
                         env=source_env(), capture_output=True, text=True, timeout=60)
    if out.returncode != 0:
        raise TaskError(f"cannot resolve ref {ref!r}")
    return out.stdout.strip()


def tree_digest(root):
    digest = hashlib.sha256()
    for dirpath, dirs, files in os.walk(root):
        dirs.sort()
        for name in sorted(files):
            path = os.path.join(dirpath, name)
            rel = os.path.relpath(path, root)
            if os.path.islink(path):
                digest.update(f"L {rel} {os.readlink(path)}\n".encode())
                continue
            mode = "x" if os.access(path, os.X_OK) else "f"
            digest.update(f"{mode} {rel} {file_digest(path)}\n".encode())
    return digest.hexdigest()


def plugin_name_of(root):
    return json.loads((Path(root) / ".claude-plugin" / "plugin.json").read_text(encoding="utf-8"))["name"]


def export_arm(repo, commit, dest):
    """Extract `git archive <commit>` into a staging directory and move it to dest only when
    complete, so an interrupted export is never reused as an arm. Returns the plugin name."""
    staging = dest.parent / f".{dest.name}.partial"
    if staging.exists():
        shutil.rmtree(staging)
    staging.mkdir(parents=True)
    with tempfile.TemporaryFile() as tar_file:
        done = subprocess.run(["git", "-C", str(repo), "archive", "--format=tar", commit], stdout=tar_file,
                              stderr=subprocess.PIPE, env=source_env(), timeout=300)
        if done.returncode != 0:
            raise TaskError(f"git archive failed for {commit}: {done.stderr.decode(errors='replace').strip()}")
        tar_file.seek(0)
        with tarfile.open(fileobj=tar_file) as tar:
            try:
                tar.extractall(staging, filter="data")
            except tarfile.FilterError as exc:
                raise TaskError(f"archive member rejected: {exc}") from None
    if not (staging / ".claude-plugin" / "plugin.json").is_file():
        raise TaskError(f"{commit} has no .claude-plugin/plugin.json")
    staging.rename(dest)
    return plugin_name_of(dest)


# --------------------------------------------------------------------------- running one sample

def _group_alive(pgid):
    try:
        os.killpg(pgid, 0)
    except ProcessLookupError:
        return False
    except PermissionError:
        return True
    return True


def kill_group(proc):
    """Terminate the run's process group, including background jobs the agent left.
    Returns True only when the group is confirmed gone."""
    for sig in (signal.SIGTERM, signal.SIGKILL):
        proc.poll()
        if not _group_alive(proc.pid):
            break
        try:
            os.killpg(proc.pid, sig)
        except ProcessLookupError:
            break
        except PermissionError:
            return False
        deadline = time.monotonic() + 5
        while time.monotonic() < deadline:
            proc.poll()  # reap the leader so a zombie does not keep the group alive
            if not _group_alive(proc.pid):
                break
            time.sleep(0.05)
    try:
        proc.wait(timeout=5)
    except subprocess.TimeoutExpired:
        return False
    return not _group_alive(proc.pid)


def run_agent(cmd, prompt, cwd, env, timeout, stream_path, stderr_path, live=None):
    started = time.monotonic()
    timed_out = False
    with open(stream_path, "wb") as out, open(stderr_path, "wb") as err:
        proc = subprocess.Popen(cmd, cwd=str(cwd), env=env, stdin=subprocess.PIPE, stdout=out, stderr=err,
                                start_new_session=True)
        if live is not None:
            live.add(proc)
        try:
            proc.communicate(input=prompt.encode("utf-8"), timeout=timeout)
        except subprocess.TimeoutExpired:
            timed_out = True
        finally:
            cleaned = kill_group(proc)
            if live is not None:
                live.discard(proc)
    return {"exit_code": proc.returncode, "timed_out": timed_out, "cleanup_confirmed": cleaned,
            "seconds": round(time.monotonic() - started, 1)}


def _utilizations(info):
    values = []
    if isinstance(info, dict):
        if isinstance(info.get("utilization"), (int, float)):
            values.append(info["utilization"])
        windows = info.get("unifiedWindows")
        if isinstance(windows, dict):
            for window in windows.values():
                if isinstance(window, dict) and isinstance(window.get("utilization"), (int, float)):
                    values.append(window["utilization"])
    return values


def parse_stream(path):
    parsed = {"init": None, "results": [], "hooks": [], "routing_injected": False, "tool_uses": [],
              "texts": [], "invalid_lines": 0, "max_utilization": None}
    with open(path, "rb") as fh:
        for raw in fh:
            line = raw.decode("utf-8", "replace").strip()
            if not line:
                continue
            try:
                event = json.loads(line)
            except (json.JSONDecodeError, RecursionError):
                parsed["invalid_lines"] += 1
                continue
            if not isinstance(event, dict):
                parsed["invalid_lines"] += 1
                continue
            kind, sub = event.get("type"), event.get("subtype")
            if kind == "system" and sub == "init" and parsed["init"] is None:
                parsed["init"] = event
            elif kind == "system" and sub == "hook_response":
                parsed["hooks"].append(str(event.get("hook_name")))
                if ROUTING_MARKER in f"{event.get('output', '')}{event.get('stdout', '')}":
                    parsed["routing_injected"] = True
            elif kind == "assistant":
                message = event.get("message")
                content = message.get("content") if isinstance(message, dict) else None
                for item in content if isinstance(content, list) else []:
                    if not isinstance(item, dict):
                        continue
                    if item.get("type") == "text" and isinstance(item.get("text"), str):
                        parsed["texts"].append(item["text"])
                    elif item.get("type") == "tool_use":
                        tool_input = item.get("input") if isinstance(item.get("input"), dict) else {}
                        parsed["tool_uses"].append({"name": str(item.get("name")), "input": tool_input})
            elif kind == "result":
                parsed["results"].append(event)
            elif kind == "rate_limit_event":
                values = _utilizations(event.get("rate_limit_info"))
                if values:
                    parsed["max_utilization"] = max(values + [parsed["max_utilization"] or 0])
    return parsed


def _strings(value):
    if isinstance(value, str):
        yield value
    elif isinstance(value, dict):
        for item in value.values():
            yield from _strings(item)
    elif isinstance(value, list):
        for item in value:
            yield from _strings(item)


def _under(path, root):
    return path == root or path.startswith(root.rstrip(os.sep) + os.sep)


def outside_paths(tool_uses, allowed, watched, home):
    """Heuristic: absolute or home-relative paths in tool inputs that fall under a watched
    root (home, this repository, the output root) but outside every allowed root."""
    flagged = []
    for use in tool_uses:
        for text in _strings(use["input"]):
            for token in PATH_TOKEN.findall(text):
                expanded = re.sub(r"^(?:~|\$\{?HOME\}?)", lambda _: home, token)
                if not expanded.startswith("/"):
                    continue
                real = os.path.realpath(expanded)
                if any(_under(real, root) for root in allowed):
                    continue
                if any(_under(real, root) for root in watched) and real not in flagged:
                    flagged.append(real)
    return flagged


def assess(parsed, run, arm, model, arm_dir, plugin_name, arm_dirs, token):
    """Structural isolation evidence for one run. Returns the reasons the sample is invalid.
    A run may hold several results: a plugin Stop hook can send the agent back for more
    turns, which is the treatment's own behavior, so the last result decides how it ended."""
    reasons = []
    results = parsed["results"]
    if run["timed_out"]:
        reasons.append("timeout")
    elif not results:
        reasons.append("no_result")
    elif results[-1].get("subtype") != "success" or results[-1].get("is_error"):
        reasons.append(f"error_result:{results[-1].get('subtype')}")
    init = parsed["init"]
    isolation = {"hooks": sorted(set(parsed["hooks"]))}
    if not isinstance(init, dict):
        reasons.append("no_init_event")
    else:
        isolation["model"] = init.get("model")
        if init.get("model") != model:
            reasons.append("model_mismatch")
        plugins, servers = init.get("plugins"), init.get("mcp_servers")
        if not isinstance(plugins, list) or not isinstance(servers, list):
            reasons.append("init_shape_unverifiable")
        entries = [p for p in plugins if isinstance(p, dict)] if isinstance(plugins, list) else []
        isolation["plugins"] = sorted(f"{p.get('name')}@{'builtin' if p.get('path') == 'builtin' else 'dir'}"
                                      for p in entries)
        own = [p for p in entries if p.get("name") == plugin_name]
        if arm == "off":
            from_arm_dirs = [p for p in entries if p.get("path") != "builtin" and isinstance(p.get("path"), str)
                             and any(_under(os.path.realpath(p["path"]), d) for d in arm_dirs)]
            if own or from_arm_dirs:
                reasons.append("plugin_loaded_in_off_arm")
        elif len(own) != 1 or os.path.realpath(str(own[0].get("path"))) != os.path.realpath(str(arm_dir)):
            reasons.append("plugin_identity_mismatch")
        if any(p.get("path") != "builtin" and p.get("name") != plugin_name for p in entries):
            reasons.append("foreign_plugins")
        if isinstance(servers, list) and servers:
            reasons.append("mcp_servers_present")
    if (arm != "off") != parsed["routing_injected"]:
        reasons.append("routing_injection_mismatch")
    corpus = parsed["texts"] + [json.dumps(u["input"], ensure_ascii=False) for u in parsed["tool_uses"]]
    corpus += [str(r.get("result", "")) for r in results]
    if any(token in text for text in corpus):
        reasons.append("instruction_file_canary_leaked")
    if not run["cleanup_confirmed"]:
        reasons.append("process_cleanup_unconfirmed")
    return reasons, isolation


# --------------------------------------------------------------------------- statistics and report

def fisher_two_sided(a, b, c, d):
    """Two-sided Fisher exact p for the table [[a, b], [c, d]] (pass/fail in two arms)."""
    n1, n2, k = a + b, c + d, a + c
    n = n1 + n2
    if n == 0:
        return 1.0
    denom = math.comb(n, k)

    def prob(x):
        return math.comb(n1, x) * math.comb(n2, k - x) / denom
    observed = prob(a)
    total = sum(prob(x) for x in range(max(0, k - n2), min(k, n1) + 1) if prob(x) <= observed * (1 + 1e-9))
    return min(1.0, total)


def compare(k1, n1, k2, n2):
    """Pre-registered reading of one pairwise comparison."""
    if n1 < 3 or n2 < 3:
        return "insufficient", None
    p = fisher_two_sided(k1, n1 - k1, k2, n2 - k2)
    if p < 0.05:
        return "separated", p
    if abs(k1 / n1 - k2 / n2) >= 0.4:
        return "direction", p
    return "no observed difference", p


def tally(records, task_id, arm, check_id):
    rows = [r for r in records if r["task"] == task_id and r["arm"] == arm and r["valid"]]
    passed = sum(1 for r in rows if r["checks"][check_id]["result"] == "pass")
    failed = sum(1 for r in rows if r["checks"][check_id]["result"] == "fail")
    return passed, passed + failed, len(rows) - passed - failed


def _median(values):
    values = [v for v in values if isinstance(v, (int, float))]
    return round(statistics.median(values), 2) if values else None


def build_report(plan, records, calibration, integrity):
    arms = [a for a in ARMS if a in plan["arms"]]
    lines = ["# Paired behavior eval report", "",
             "Advisory evidence for the tasks and conditions below only; the tool header lists what these "
             "numbers are not. Counts exclude invalid samples; `Ns` marks valid samples with out-of-world "
             "path suspects.", "", "## Batch", "",
             f"- plan `{plan['plan_hash'][:16]}`, tool version {plan['tool_version']}",
             f"- model `{plan['model']}`, effort `{plan['effort']}`, claude `{plan['claude_version']}`",
             f"- per-run cap ${plan['max_budget_usd']}, denied tools `{plan['disallowed_tools']}`"]
    for arm in arms:
        info = plan["arms"][arm]
        lines.append(f"- `{arm}` ({TREATMENT[arm]}): " + ("no plugin" if arm == "off" else
                     f"`{info['ref']}` = {info['commit'][:12]}, export digest {info['export_digest'][:12]}"))
    graders = sorted({r.get("graded_by") or plan["tool_sha256"] for r in records} - {plan["tool_sha256"]})
    if graders:
        lines.append(f"- records regraded by tool `{', '.join(g[:12] for g in graders)}`; the batch ran with "
                     f"`{plan['tool_sha256'][:12]}`")
    cal = "not run" if calibration is None else ("fired" if calibration.get("fired") else "DID NOT FIRE")
    lines.append(f"- instruction-file canary calibration: {cal}")
    if integrity is not None:
        lines.append(f"- plugin exports unchanged after the batch: {'yes' if integrity.get('unchanged') else 'NO'}")
    costs = [r["cost_usd"] for r in records if isinstance(r.get("cost_usd"), (int, float))]
    lines += [f"- samples recorded {len(records)}, valid {sum(r['valid'] for r in records)}, "
              f"with suspects {sum(bool(r['suspect_paths']) for r in records)}, spend ${round(sum(costs), 2)}", "",
              "## Isolation", "", "| arm | recorded | valid | invalid reasons | suspects | continued after a Stop hook |",
              "| --- | --- | --- | --- | --- | --- |"]
    for arm in arms:
        rows = [r for r in records if r["arm"] == arm]
        reasons = {}
        for r in rows:
            for reason in r["invalid_reasons"]:
                reasons[reason] = reasons.get(reason, 0) + 1
        text = ", ".join(f"{k} {v}" for k, v in sorted(reasons.items())) or "none"
        lines.append(f"| {arm} | {len(rows)} | {sum(r['valid'] for r in rows)} | {text} | "
                     f"{sum(bool(r['suspect_paths']) for r in rows)} | {sum(bool(r.get('continuations')) for r in rows)} |")
    lines.append("")
    pairs = [(a, b) for a, b in (("candidate", "base"), ("base", "off"), ("candidate", "off"))
             if a in arms and b in arms]
    comparisons = 0
    for task in plan["tasks"]:
        tid = task["id"]
        lines += [f"## {tid}", "", task["measures"], "",
                  "| check | role | " + " | ".join(arms) + " |", "| --- | --- | " + " | ".join("---" for _ in arms) + " |"]
        for check in task["checks"]:
            cells = []
            for arm in arms:
                k, n, na = tally(records, tid, arm, check["id"])
                suspects = sum(1 for r in records if r["task"] == tid and r["arm"] == arm and r["valid"]
                               and r["suspect_paths"])
                cell = f"{k}/{n}" + (f" (+{na} n/a)" if na else "") + (f" {suspects}s" if suspects else "")
                cells.append(cell if n or na else "—")
            lines.append(f"| {check['id']} | {check['role']} | " + " | ".join(cells) + " |")
        if pairs:
            lines += ["", "| check | " + " | ".join(f"{a} vs {b}" for a, b in pairs) + " |",
                      "| --- | " + " | ".join("---" for _ in pairs) + " |"]
            for check in task["checks"]:
                cells = []
                for a, b in pairs:
                    k1, n1, _ = tally(records, tid, a, check["id"])
                    k2, n2, _ = tally(records, tid, b, check["id"])
                    verdict, p = compare(k1, n1, k2, n2)
                    comparisons += p is not None
                    cells.append(f"{k1}/{n1} vs {k2}/{n2}: {verdict}" + (f" (p={p:.3f})" if p is not None else ""))
                lines.append(f"| {check['id']} | " + " | ".join(cells) + " |")
        lines += ["", "| arm | median cost $ | median turns | median seconds |", "| --- | --- | --- | --- |"]
        for arm in arms:
            rows = [r for r in records if r["task"] == tid and r["arm"] == arm and r["valid"]]
            lines.append(f"| {arm} | {_median([r.get('cost_usd') for r in rows])} | "
                         f"{_median([r.get('turns') for r in rows])} | {_median([r.get('seconds') for r in rows])} |")
        lines.append("")
    lines += ["## Reading", "",
              f"{comparisons} pairwise comparisons, each with an uncorrected two-sided Fisher exact p, so a few "
              "`separated` labels can be chance. `separated` = p < 0.05; `direction` = pass rates differ by 0.4 "
              "or more without p < 0.05; `insufficient` = fewer than 3 valid samples in an arm.", ""]
    return "\n".join(lines)


# --------------------------------------------------------------------------- batch

def common_checkout_root(repo):
    out = subprocess.run(["git", "-C", str(repo), "rev-parse", "--path-format=absolute", "--git-common-dir"],
                         env=source_env(), capture_output=True, text=True, timeout=60)
    if out.returncode != 0:
        raise TaskError(f"{repo} is not a git repository")
    return Path(out.stdout.strip()).parent


def claude_version(claude):
    try:
        out = subprocess.run([claude, "--version"], capture_output=True, text=True, timeout=60)
    except (OSError, subprocess.TimeoutExpired) as exc:
        raise TaskError(f"cannot run {claude} --version: {exc}") from None
    if out.returncode != 0 or not out.stdout.strip():
        raise TaskError(f"{claude} --version failed")
    return out.stdout.strip().splitlines()[0]


def canonical(obj):
    return json.dumps(obj, sort_keys=True, ensure_ascii=False, separators=(",", ":"))


def schedule(tasks, arms, samples_override):
    """Interleave arms within each sample index so drift over the batch hits every arm alike."""
    counts = {t["id"]: samples_override or t["samples"] for t in tasks}
    order = []
    for i in range(1, max(counts.values()) + 1):
        for t_index, task in enumerate(tasks):
            if i > counts[task["id"]]:
                continue
            shift = (i + t_index) % len(arms)
            for arm in arms[shift:] + arms[:shift]:
                order.append((task, arm, i))
    return order


def agent_command(claude, model, effort, budget, plugin_dir, setting_sources=""):
    cmd = [claude, "-p", "--model", model]
    if effort:
        cmd += ["--effort", effort]
    if plugin_dir:
        cmd += ["--plugin-dir", str(plugin_dir)]
    cmd += ["--setting-sources", setting_sources, "--strict-mcp-config", "--permission-mode", "bypassPermissions",
            "--output-format", "stream-json", "--verbose", "--no-session-persistence",
            "--max-budget-usd", str(budget), "--disallowedTools", DISALLOWED_TOOLS]
    return cmd


def run_sample(ctx, task, arm, index):
    sample_dir = ctx["out"] / "runs" / task["id"] / arm / str(index)
    world, gitconfig, snapshot, token = build_world(task, sample_dir)
    (sample_dir / "snapshot.json").write_text(json.dumps(snapshot, indent=1), encoding="utf-8")
    arm_dir = ctx["arm_dirs"].get(arm)
    plan = ctx["plan"]
    cmd = agent_command(ctx["claude"], plan["model"], plan["effort_flag"], plan["max_budget_usd"], arm_dir)
    run = run_agent(cmd, task["prompt"], world / task["cwd"], clean_env(gitconfig, agent=True),
                    task["timeout_seconds"], sample_dir / "stream.jsonl", sample_dir / "stderr.txt", ctx["live"])
    if ctx["interrupted"].is_set():
        return None  # an interrupted run is not an outcome; resume reruns it
    return make_record(ctx, task, arm, index, sample_dir, snapshot, token, run)


def make_record(ctx, task, arm, index, sample_dir, snapshot, token, run):
    """Assess and grade one finished run from its saved stream and world, and write record.json."""
    world, gitconfig = sample_dir / "world", sample_dir / "gitconfig"
    arm_dir = ctx["arm_dirs"].get(arm)
    plan = ctx["plan"]
    parsed = parse_stream(sample_dir / "stream.jsonl")
    reasons, isolation = assess(parsed, run, arm, plan["model"], arm_dir, ctx["plugin_name"],
                                ctx["arm_dirs_real"], token)
    allowed = [os.path.realpath(world)] + ([os.path.realpath(arm_dir)] if arm_dir else [])
    suspects = outside_paths(parsed["tool_uses"], allowed, ctx["watched"], ctx["home"])
    commands = [str(u["input"].get("command", "")) for u in parsed["tool_uses"] if u["name"] == "Bash"]
    results = parsed["results"]
    last = results[-1] if results else {}
    record = {
        "task": task["id"], "arm": arm, "treatment": TREATMENT[arm], "sample": index,
        "plan_hash": plan["plan_hash"], "graded_by": ctx["tool_sha256"], "valid": not reasons,
        "invalid_reasons": reasons, "suspect_paths": suspects[:10], "isolation": isolation,
        "checks": grade(task, world, gitconfig, snapshot, commands),
        "cost_usd": last.get("total_cost_usd"),  # cumulative across continuations
        "turns": sum(r["num_turns"] for r in results if isinstance(r.get("num_turns"), int)) or None,
        "continuations": max(len(results) - 1, 0),
        "seconds": run["seconds"], "exit_code": run["exit_code"],
        "run": {"timed_out": run["timed_out"], "cleanup_confirmed": run["cleanup_confirmed"]},
        "max_utilization": parsed["max_utilization"],
        "skills_invoked": [str(u["input"].get("skill")) for u in parsed["tool_uses"] if u["name"] == "Skill"],
        "bash_commands": len(commands), "result_excerpt": str(last.get("result", ""))[:300],
    }
    (sample_dir / "record.json").write_text(json.dumps(record, indent=1, ensure_ascii=False), encoding="utf-8")
    return record


def regrade(ctx, out, tasks):
    """Rebuild every record from its saved stream, snapshot and world with the current
    assessment and graders; no model runs. The batch's tasks must be byte-identical."""
    by_id = {t["id"]: t for t in tasks}
    for entry in ctx["plan"]["tasks"]:
        if entry["id"] not in by_id or by_id[entry["id"]]["_sha256"] != entry["sha256"]:
            raise TaskError(f"task {entry['id']} differs from the one the batch ran; regrading would apply other checks")
    count = 0
    for path in sorted((out / "runs").glob("*/*/*/record.json")):
        old = json.loads(path.read_text(encoding="utf-8"))
        if old.get("plan_hash") != ctx["plan"]["plan_hash"]:
            raise TaskError(f"{path.parent.name}: record belongs to another plan")
        sample_dir = path.parent
        canary = re.search(r"CANARY-[0-9a-f]{12}", (sample_dir / "world" / "CLAUDE.md").read_text(encoding="utf-8"))
        if canary is None:
            raise TaskError(f"{sample_dir}: canary file missing; cannot reassess")
        run = dict(old.get("run") or {"timed_out": "timeout" in old["invalid_reasons"],
                                      "cleanup_confirmed": "process_cleanup_unconfirmed" not in old["invalid_reasons"]},
                   seconds=old["seconds"], exit_code=old["exit_code"])
        snapshot = json.loads((sample_dir / "snapshot.json").read_text(encoding="utf-8"))
        make_record(ctx, by_id[old["task"]], old["arm"], old["sample"], sample_dir, snapshot, canary.group(0), run)
        count += 1
    return count


def calibrate_canary(ctx):
    """Prove the canary can fire: allow project settings and instruction files once, on a
    tiny prompt, and expect the token in the reply."""
    probe = {"id": "canary-calibration", "setup": ["git init -q -b main app"], "cwd": "app", "checks": []}
    sample_dir = ctx["out"] / "calibration"
    world, gitconfig, _, token = build_world(probe, sample_dir)
    env = clean_env(gitconfig, agent=True)
    env.pop("CLAUDE_CODE_DISABLE_CLAUDE_MDS")
    cmd = agent_command(ctx["claude"], ctx["plan"]["model"], None, 1, None, setting_sources="project")
    run = run_agent(cmd, "Reply with the single word OK.", world / "app", env, 300,
                    sample_dir / "stream.jsonl", sample_dir / "stderr.txt", ctx["live"])
    if ctx["interrupted"].is_set():
        return None
    parsed = parse_stream(sample_dir / "stream.jsonl")
    texts = parsed["texts"] + [str(r.get("result", "")) for r in parsed["results"]]
    result = {"fired": any(token in t for t in texts), "timed_out": run["timed_out"],
              "max_utilization": parsed["max_utilization"]}
    (ctx["out"] / "canary-calibration.json").write_text(json.dumps(result, indent=1), encoding="utf-8")
    return result


def read_json(path):
    return json.loads(path.read_text(encoding="utf-8")) if path.is_file() else None


def load_records(out):
    return [json.loads(p.read_text(encoding="utf-8")) for p in sorted((out / "runs").glob("*/*/*/record.json"))]


def write_report(out, plan, records):
    calibration = read_json(out / "canary-calibration.json")
    integrity = read_json(out / "integrity.json")
    (out / "results.json").write_text(json.dumps(records, indent=1, ensure_ascii=False), encoding="utf-8")
    (out / "report.md").write_text(build_report(plan, records, calibration, integrity), encoding="utf-8")


def _raise_interrupt(signum, frame):
    raise KeyboardInterrupt


def tool_sha256():
    return hashlib.sha256(Path(__file__).read_bytes()).hexdigest()


def make_context(out, plan, arm_dirs, checkout_root, claude=None):
    home = os.path.realpath(os.path.expanduser("~"))
    return {"out": out, "claude": claude, "plan": plan, "arm_dirs": arm_dirs, "plugin_name": plan["plugin_name"],
            "arm_dirs_real": [os.path.realpath(d) for d in arm_dirs.values()], "home": home,
            "watched": [home, os.path.realpath(checkout_root), os.path.realpath(out)],
            "tool_sha256": tool_sha256(), "live": set(), "interrupted": threading.Event()}


def run_batch(args, out, arms, only):
    repo = args.repo.resolve()
    checkout_root = common_checkout_root(repo)
    for root in (repo, checkout_root):
        if _under(str(out), str(root.resolve())):
            raise TaskError("--out must be outside every checkout of this repository")
    tasks = load_tasks(args.tasks_dir, only)
    commits = {arm: resolve_commit(repo, ref) for arm, ref in (("base", args.base), ("candidate", args.candidate))
               if arm in arms}
    planned = schedule(tasks, arms, args.samples)
    if args.dry_run:
        for arm in arms:
            print(f"arm {arm}: " + (commits[arm][:12] if arm in commits else "no plugin"))
        for task in tasks:
            print(f"task {task['id']}: {args.samples or task['samples']} samples per arm")
        print(f"runs {len(planned)} (+1 canary calibration), max-runs {args.max_runs}")
        return 0
    version = claude_version(args.claude)
    if out.exists() and not out.is_dir():
        raise TaskError("--out exists and is not a directory")
    out.mkdir(mode=0o700, parents=True, exist_ok=True)
    arm_dirs, arm_info, names = {}, {}, set()
    for arm in arms:
        if arm == "off":
            arm_info[arm] = {"ref": None, "commit": None, "export_digest": None}
            continue
        dest = out / "arms" / arm
        names.add(plugin_name_of(dest) if dest.exists() else export_arm(repo, commits[arm], dest))
        arm_dirs[arm] = dest
        arm_info[arm] = {"ref": args.base if arm == "base" else args.candidate, "commit": commits[arm],
                         "export_digest": tree_digest(dest)}
    if len(names) > 1:
        raise TaskError("base and candidate exports name different plugins")
    plugin_name = names.pop() if names else plugin_name_of(repo)
    plan = {
        "tool_version": TOOL_VERSION, "tool_sha256": tool_sha256(),
        "model": args.model, "effort": args.effort or "cli-default", "effort_flag": args.effort,
        "max_budget_usd": args.max_budget_usd, "disallowed_tools": DISALLOWED_TOOLS, "claude_version": version,
        "arms": arm_info, "plugin_name": plugin_name, "samples_override": args.samples,
        "tasks": [{"id": t["id"], "sha256": t["_sha256"], "samples": args.samples or t["samples"],
                   "measures": t["measures"], "checks": [{"id": c["id"], "role": c["role"]} for c in t["checks"]]}
                  for t in tasks],
    }
    plan["plan_hash"] = hashlib.sha256(canonical(plan).encode()).hexdigest()
    existing = read_json(out / "plan.json")
    if existing is not None and existing.get("plan_hash") != plan["plan_hash"]:
        raise TaskError("plan differs from the one frozen under --out (tasks, refs, flags, tool or claude version "
                        "changed); use a new --out")
    if existing is None:
        (out / "plan.json").write_text(json.dumps(plan, indent=1, ensure_ascii=False), encoding="utf-8")
    done = {(r["task"], r["arm"], r["sample"]) for r in load_records(out) if r.get("plan_hash") == plan["plan_hash"]}
    pending = [(t, a, i) for t, a, i in planned if (t["id"], a, i) not in done]
    need_calibration = bool(pending) and read_json(out / "canary-calibration.json") is None
    if len(pending) + need_calibration > args.max_runs:
        raise TaskError(f"{len(pending) + need_calibration} runs exceed --max-runs {args.max_runs}")
    ctx = make_context(out, plan, arm_dirs, checkout_root, args.claude)
    stop = threading.Event()

    def worker(item):
        task, arm, index = item
        if stop.is_set():
            return None
        record = run_sample(ctx, task, arm, index)
        if record is None:
            return None
        if (record.get("max_utilization") or 0) >= args.stop_util:
            stop.set()
        print(f"{task['id']} {arm} #{index}: valid={record['valid']} "
              + " ".join(f"{k}={v['result']}" for k, v in record["checks"].items()), file=sys.stderr, flush=True)
        return record

    previous = signal.signal(signal.SIGTERM, _raise_interrupt)
    pool = cf.ThreadPoolExecutor(max_workers=args.jobs)
    try:
        if need_calibration:
            calibration = calibrate_canary(ctx)
            if calibration and (calibration.get("max_utilization") or 0) >= args.stop_util:
                stop.set()
        futures = [pool.submit(worker, item) for item in pending]
        for future in cf.as_completed(futures):
            future.result()
    except BaseException as exc:
        stop.set()
        ctx["interrupted"].set()
        for proc in list(ctx["live"]):
            kill_group(proc)
        pool.shutdown(wait=True, cancel_futures=True)
        signal.signal(signal.SIGTERM, previous)
        write_report(out, plan, load_records(out))
        if isinstance(exc, KeyboardInterrupt):
            print("interrupted: rerun the same command to resume", file=sys.stderr)
            return 130
        raise
    pool.shutdown(wait=True)
    signal.signal(signal.SIGTERM, previous)
    if arm_dirs:
        unchanged = all(tree_digest(arm_dirs[a]) == arm_info[a]["export_digest"] for a in arm_dirs)
        (out / "integrity.json").write_text(json.dumps({"unchanged": unchanged}), encoding="utf-8")
    records = load_records(out)
    write_report(out, plan, records)
    print(out / "report.md")
    recorded = {(r["task"], r["arm"], r["sample"]) for r in records if r.get("plan_hash") == plan["plan_hash"]}
    if any((t["id"], a, i) not in recorded for t, a, i in planned):
        print("stopped early: rate-limit utilization reached --stop-util; rerun the same command to resume",
              file=sys.stderr)
        return 3
    return 0


def main(argv=None):
    parser = argparse.ArgumentParser(description="Paired behavior eval (harness-patterns-and-eval.md §3.1).")
    parser.add_argument("--out", type=Path, help="private output root, outside every checkout of this repository")
    parser.add_argument("--base", help="git ref exported as the base arm")
    parser.add_argument("--candidate", help="git ref exported as the candidate arm")
    parser.add_argument("--tasks-dir", type=Path, default=DEFAULT_TASKS)
    parser.add_argument("--tasks", help="comma-separated task ids (default: all)")
    parser.add_argument("--arms", default=",".join(ARMS))
    parser.add_argument("--samples", type=int, help="override every task's sample count")
    parser.add_argument("--model", default="claude-opus-5-5")
    parser.add_argument("--effort", choices=("low", "medium", "high", "xhigh", "max"),
                        help="pin the tested agent's effort (default: the CLI default)")
    parser.add_argument("--max-budget-usd", type=float, default=3.0, help="spend cap per run")
    parser.add_argument("--max-runs", type=int, default=60, help="refuse a batch that would start more runs")
    parser.add_argument("--jobs", type=int, default=3)
    parser.add_argument("--stop-util", type=float, default=0.9,
                        help="stop starting runs once any rate-limit window reaches this utilization")
    parser.add_argument("--claude", default="claude", help="claude executable")
    parser.add_argument("--repo", type=Path, default=REPO_ROOT, help="repository the refs are exported from")
    parser.add_argument("--dry-run", action="store_true", help="print the plan; no runs, nothing written")
    parser.add_argument("--report-only", action="store_true", help="rebuild report.md from saved records")
    parser.add_argument("--regrade", action="store_true",
                        help="rebuild every record from its saved stream and world with this tool; no model runs")
    parser.add_argument("--check-oracles", action="store_true",
                        help="prove every task's checks pass on its good trajectory and fail on its bad ones")
    args = parser.parse_args(argv)
    try:
        only = [x for x in args.tasks.split(",") if x] if args.tasks else None
        if args.check_oracles:
            problems = check_oracles(load_tasks(args.tasks_dir, only))
            for problem in problems:
                print(f"oracle: {problem}", file=sys.stderr)
            print("paired_eval_oracles_ok" if not problems else f"paired_eval_oracles_failed {len(problems)}")
            return 1 if problems else 0
        if args.out is None:
            raise TaskError("--out is required")
        out = args.out.resolve()
        if args.report_only or args.regrade:
            plan = read_json(out / "plan.json")
            if plan is None:
                raise TaskError("no plan.json under --out")
            if args.regrade:
                arm_dirs = {a: out / "arms" / a for a, info in plan["arms"].items() if info.get("commit")}
                ctx = make_context(out, plan, arm_dirs, common_checkout_root(args.repo.resolve()))
                print(f"regraded {regrade(ctx, out, load_tasks(args.tasks_dir))} records", file=sys.stderr)
            write_report(out, plan, load_records(out))
            print(out / "report.md")
            return 0
        arms = [a for a in args.arms.split(",") if a]
        if not arms or len(set(arms)) != len(arms) or any(a not in ARMS for a in arms):
            raise TaskError(f"--arms must name distinct arms from {ARMS}")
        for arm, ref in (("base", args.base), ("candidate", args.candidate)):
            if arm in arms and not ref:
                raise TaskError(f"--{arm} is required for the {arm} arm")
        if args.jobs < 1 or args.max_runs < 1 or not 0 < args.stop_util <= 1 or args.max_budget_usd <= 0:
            raise TaskError("--jobs, --max-runs, --stop-util and --max-budget-usd must be positive")
        if args.samples is not None and not 1 <= args.samples <= 20:
            raise TaskError("--samples must be 1..20")
        return run_batch(args, out, arms, only)
    except TaskError as exc:
        print(f"skill-paired-eval: {exc}", file=sys.stderr)
        return 2
    except BrokenPipeError:
        return 0


if __name__ == "__main__":
    sys.exit(main())
