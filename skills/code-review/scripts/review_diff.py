#!/usr/bin/env python3
"""Run an independent code review where the reviewer reads the diff itself.

The reviewer CLI runs read-only, reads the diff against the merge base that
this runner saved and whatever surrounding code it needs, and answers in a
fixed text form. This runner only picks independent reviewers, trying the next
when one fails, binds the reviewed candidate, parses the answer, and records
the result and the local receipt the pull-request reminder reads.

Exit codes: 0 passed, 1 findings, 2 inconclusive.
"""
from __future__ import annotations

import argparse
import datetime
import hashlib
import json
import os
import re
import shutil
import signal
import subprocess
import sys
import tempfile
import time
from pathlib import Path
from typing import Optional

SCHEMA_VERSION = 3  # the envelope check_review_evidence_present.py accepts
CLIENTS = ("codex", "claude", "opencode", "kimi")
DEFAULT_ORDER = ",".join(CLIENTS)
# Spellings of a model family used across this repository and its callers.
FAMILY_ALIASES = {"openai": "codex", "gpt": "codex", "chatgpt": "codex", "anthropic": "claude",
                  "moonshot": "kimi"}
# A word in a model id that names its family. OpenCode can run any provider, so
# its family comes from the model it is configured with; an id naming none of
# these is of unknown family and is not used as a reviewer.
MODEL_FAMILY_WORDS = (("claude", "claude"), ("anthropic", "claude"), ("gpt", "codex"),
                      ("openai", "codex"), ("codex", "codex"), ("kimi", "kimi"),
                      ("moonshot", "kimi"), ("deepseek", "deepseek"), ("gemini", "gemini"),
                      ("qwen", "qwen"), ("glm", "glm"))
# Families an implementer can be named as. A client name that can run any model
# (opencode) or "other" says nothing about independence, so it is refused.
KNOWN_FAMILIES = {family for _, family in MODEL_FAMILY_WORDS}
INTERRUPT_CODES = {130, 137, 143}
# Top-level config keys carried into a reviewer's private home, plus the tables
# that define the models they select. An allowlist on purpose: anything else
# (MCP servers, hooks, plugins, skills, tool settings) stays out.
CODEX_KEYS = ("model", "model_reasoning_effort", "model_provider", "model_verbosity")
KIMI_KEYS = ("default_model", "default_effort", "default_thinking")
KIMI_TABLES = ("models", "providers", "thinking")
KIMI_LINKS = ("credentials", "oauth", "device_id", "region")  # links, so a token refresh persists
READ_TOOLS = ("Read", "Grep", "Glob")
FINDING = re.compile(r"^\s*\[(P[0-3])\]\s+(.+?)\s+[—–-]{1,2}\s+(\S+?):(\d+)\s*$")
DIAG_LIMIT = 20000  # bytes of answer and of stderr kept in the private diagnostics file

REVIEW_BRIEF = """Report only defects introduced by this change that the author would fix:
correctness, security, data loss, broken contracts, or clearly wrong behavior.
Each finding must name a concrete failing scenario you can show from the code.
Skip style nits, speculation and problems that existed before the change."""

CHALLENGE_BRIEF = """Think like an attacker and a chaos engineer. Find ways this change fails in
production: edge cases, races, security holes, resource leaks, silent data
corruption, swallowed errors and trust-boundary violations. Report only problems
in the changed code that you can show with a concrete scenario."""


class Interrupted(Exception):
    pass


# Repository config can name programs git runs on status, add and diff
# (fsmonitor, filter drivers, textconv, external diff). The candidate may carry
# those programs, so every git call here switches them off.
GIT_SAFETY = ["-c", "core.fsmonitor=false"]  # diff also passes --no-ext-diff --no-textconv


def git(cwd: str, *args: str, env: Optional[dict] = None) -> str:
    return subprocess.run(
        ["git", "-C", cwd, *GIT_SAFETY, *args], check=True, capture_output=True, text=True, env=env
    ).stdout.strip()


def neutralize_filters(cwd: str) -> None:
    """Replace every configured filter driver with a pass-through for this run."""
    try:
        # Names only: a value can span lines and must never be parsed.
        listed = git(cwd, "config", "--name-only", "--get-regexp", r"^filter\..*\.(clean|smudge|process)$")
    except subprocess.CalledProcessError:
        return  # none configured
    for name in sorted({key.rsplit(".", 1)[0][len("filter."):] for key in listed.splitlines() if key.strip()}):
        GIT_SAFETY.extend(["-c", f"filter.{name}.clean=cat", "-c", f"filter.{name}.smudge=cat",
                           "-c", f"filter.{name}.process=", "-c", f"filter.{name}.required=false"])


def resolve_base(cwd: str, ref: Optional[str]) -> str:
    if not ref:
        try:
            ref = git(cwd, "symbolic-ref", "-q", "--short", "refs/remotes/origin/HEAD")
        except subprocess.CalledProcessError:
            ref = "origin/main"
    return git(cwd, "merge-base", "HEAD", ref)


def untracked_files(cwd: str) -> list:
    # -z: unquoted paths, so non-ASCII names resolve on disk.
    out = subprocess.run(["git", "-C", cwd, *GIT_SAFETY, "ls-files", "-z", "--others", "--exclude-standard"],
                         check=True, capture_output=True).stdout
    return sorted(p.decode("utf-8", "surrogateescape") for p in out.split(b"\0") if p)


def candidate_digest(cwd: str) -> str:
    """Digest of HEAD and the working tree against it, untracked files included.

    Computed without writing objects: staging the tree would store working-tree
    bytes (with filters switched off, possibly plaintext) in the object store.
    """
    digest = hashlib.sha256(git(cwd, "rev-parse", "HEAD").encode("ascii") + b"\0")
    digest.update(subprocess.run(
        ["git", "-C", cwd, *GIT_SAFETY, "diff", "--binary", "--no-ext-diff", "--no-textconv", "HEAD"],
        check=True, capture_output=True).stdout)
    def frame(kind: bytes, data: bytes) -> None:
        digest.update(kind + len(data).to_bytes(8, "big") + data)

    for rel in untracked_files(cwd):
        path = os.path.join(cwd, rel)
        frame(b"P", rel.encode("utf-8", "surrogateescape"))
        if os.path.islink(path):
            frame(b"L", os.readlink(path).encode("utf-8", "surrogateescape"))
        elif os.path.isfile(path):
            frame(b"M", oct(os.stat(path).st_mode & 0o777).encode("ascii"))
            with open(path, "rb") as fh:
                frame(b"F", hashlib.sha256(fh.read()).digest())
    return digest.hexdigest()


def build_prompt(mode: str, cwd: str, base: str, intent: str, focus: str, untracked: list, diff_file: str) -> str:
    # The reviewer reads the diff the runner saved with repository-configured git
    # programs switched off; a `git diff` of its own could be replaced by them.
    lines = [
        f"Review the change in the repository at {cwd} against base commit {base}.",
        f"Read the diff saved at {diff_file} (it includes uncommitted edits), and read",
        "surrounding code, tests and AGENTS.md files as needed. Do not modify anything.",
    ]
    if untracked:
        lines.append("These new untracked files are part of the change; read them directly:")
        lines += [f"- {p}" for p in untracked]
    lines += ["", f"What the change is meant to do: {intent}", ""]
    lines.append(CHALLENGE_BRIEF if mode == "challenge" else REVIEW_BRIEF)
    if focus:
        lines += ["", f"Look hardest at: {focus}"]
    lines += [
        "Never quote secret values (keys, tokens, passwords) in your answer.",
        "",
        "Output format, nothing else:",
        "One line per finding: [P0|P1|P2|P3] <imperative title> — <path>:<line>",
        "followed by one short paragraph with the failing scenario.",
        "If there are no qualifying findings, output exactly: No findings.",
    ]
    return "\n".join(lines) + "\n"


def parse_answer(text: str):
    """Return (status, findings); status is None when the answer is unreadable."""
    findings, current = [], None
    for line in text.splitlines():
        m = FINDING.match(line)
        if m:
            current = {"severity": m.group(1), "title": m.group(2), "file": m.group(3),
                       "line": int(m.group(4)), "body": ""}
            findings.append(current)
        elif current is not None and line.strip():
            current["body"] = (current["body"] + " " + line.strip()).strip()
    if findings:
        # A finding without its scenario is a truncated or placeholder answer.
        return ("findings", findings) if all(f["body"] for f in findings) else (None, findings)
    # Only the bare sentinel passes; the same sentinel after "reads failed" does not.
    return ("passed", []) if text.strip() == "No findings." else (None, [])


def _secret_patterns():
    """The controller's egress secret patterns, so both runners agree on what a credential is."""
    import importlib.util
    spec = importlib.util.spec_from_file_location(
        "review_gate_patterns", str(Path(__file__).resolve().with_name("review_gate.py")))
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return (module.EGRESS_SECRET_PATTERNS, module._SECRET_ASSIGNMENT,
            module._SECRET_ASSIGNMENT_PLACEHOLDERS, module._SECRET_ASSIGNMENT_PLACEHOLDER_PREFIXES)


def redact(text: str):
    """Return (text, changed) with credential material replaced by [REDACTED]."""
    patterns, assignment, placeholders, prefixes = _secret_patterns()
    data = text.encode("utf-8", "surrogateescape")
    original = data
    for _, pattern in patterns:
        data = pattern.sub(b"[REDACTED]", data)

    def scrub(match):
        value = match.group("value")
        low = value.strip().lower()
        if not low or low in placeholders or low.startswith(prefixes):
            return match.group(0)
        start, end = match.span("value")
        whole = match.group(0)
        return whole[:start - match.start()] + b"[REDACTED]" + whole[end - match.start():]

    data = assignment.sub(scrub, data)
    return data.decode("utf-8", "surrogateescape"), data != original


def redact_finding(finding: dict) -> dict:
    title, t_changed = redact(finding["title"])
    body, b_changed = redact(finding["body"])
    out = dict(finding, title=title, body=body)
    if t_changed or b_changed:
        out["redacted"] = True
    return out


def scratch_dir(prefix: str) -> str:
    # Not under the system temp dir: Codex refuses to create its sandbox helper
    # binaries there, and every shell command in the review then fails.
    parent = Path(os.environ.get("XDG_CACHE_HOME") or Path.home() / ".cache") / "ccl-code-review"
    parent.mkdir(parents=True, exist_ok=True)
    path = tempfile.mkdtemp(prefix=prefix, dir=str(parent))
    os.chmod(path, 0o700)
    return path


def write_private(path: str, text: str) -> None:
    # Reviewer config can hold provider keys.
    fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_TRUNC | getattr(os, "O_NOFOLLOW", 0), 0o600)
    with os.fdopen(fd, "w", encoding="utf-8") as fh:
        fh.write(text)


def link_if_present(source: Path, target: str) -> None:
    # A link, so a refreshed token lands in the user's own file.
    if source.exists():
        os.symlink(str(source), target)


def filter_toml(config: Path, keys, keep_table):
    """Keep top-level `keys` and the tables keep_table(name, top) accepts.

    Returns (kept lines, {key: value}) for the kept top-level keys."""
    kept, top, table, keep = [], {}, None, False
    if not config.is_file():
        return kept, top
    for line in config.read_text(encoding="utf-8", errors="replace").splitlines():
        stripped = line.strip()
        if stripped.startswith("["):
            header = stripped.split("#", 1)[0].strip()  # a header may carry a comment
            table = header.strip("[]").replace('"', "").replace("'", "").strip()
            keep = keep_table(table, top)
            if keep:
                kept += ["", line]
            continue
        if table is None:
            key = stripped.split("=", 1)[0].strip()
            if key in keys:
                kept.append(line)
                value = stripped.split("=", 1)[1].strip()
                quoted = re.match(r"""^(["'])(.*?)\1""", value)
                top[key] = quoted.group(2) if quoted else value.split("#", 1)[0].strip()
        elif keep:
            kept.append(line)
    return kept, top


def private_codex_home(source: Path):
    """Return (home, model, provider) for a Codex run that loads nothing else."""
    home = scratch_dir("codex-home-")
    link_if_present(source / "auth.json", os.path.join(home, "auth.json"))

    def selected_provider(table, top):
        provider = top.get("model_provider")
        return bool(provider) and (table == f"model_providers.{provider}"
                                   or table.startswith(f"model_providers.{provider}."))

    kept, top = filter_toml(source / "config.toml", CODEX_KEYS, selected_provider)
    Path(home, "config.toml").write_text("\n".join(kept) + "\n", encoding="utf-8")
    return home, top.get("model"), top.get("model_provider")


def kimi_source() -> Path:
    return Path(os.environ.get("KIMI_CODE_HOME") or Path.home() / ".kimi-code")


def kimi_config(source: Path):
    return filter_toml(source / "config.toml", KIMI_KEYS,
                       lambda table, top: table.split(".", 1)[0] in KIMI_TABLES)


def private_kimi_home(source: Path):
    """Return the home for a Kimi Code run with read tools only and no hooks, MCP or skills."""
    home = scratch_dir("kimi-home-")
    for name in KIMI_LINKS:
        link_if_present(source / name, os.path.join(home, name))
    kept, _ = kimi_config(source)
    # A non-empty enabled list is Kimi Code's global tool allowlist.
    kept += ["", "[tools]", "enabled = " + json.dumps(list(READ_TOOLS))]
    write_private(os.path.join(home, "config.toml"), "\n".join(kept) + "\n")
    os.mkdir(os.path.join(home, "no-skills"))
    return home


def load_jsonc(path: Path):
    """Parse JSON with comments and trailing commas, as OpenCode config allows."""
    text, out, i, in_string = path.read_text(encoding="utf-8", errors="replace"), [], 0, False
    while i < len(text):
        ch = text[i]
        if in_string:
            out.append(text[i:i + 2] if ch == "\\" else ch)
            i += 2 if ch == "\\" else 1
            in_string = ch != '"'
            continue
        if text.startswith("//", i):
            end = text.find("\n", i)
            i = len(text) if end < 0 else end
            continue
        if text.startswith("/*", i):
            end = text.find("*/", i + 2)
            i = len(text) if end < 0 else end + 2
            continue
        in_string = ch == '"'
        out.append(ch)
        i += 1
    return json.loads(re.sub(r",(\s*[}\]])", r"\1", "".join(out)))


def opencode_config():
    """Return (model, provider tables) from the user's global OpenCode config."""
    base = Path(os.environ.get("XDG_CONFIG_HOME") or Path.home() / ".config") / "opencode"
    paths = [base / name for name in ("config.json", "opencode.json", "opencode.jsonc")]
    if os.environ.get("OPENCODE_CONFIG"):
        paths.append(Path(os.environ["OPENCODE_CONFIG"]))
    model, providers = None, {}
    for path in paths:
        try:
            data = load_jsonc(path) if path.is_file() else None
        except (OSError, ValueError):
            data = None
        if not isinstance(data, dict):
            continue
        if isinstance(data.get("model"), str):
            model = data["model"]
        if isinstance(data.get("provider"), dict):
            providers.update(data["provider"])
    return model, providers


def private_opencode_root(model: str, providers: dict, read_dirs: list) -> str:
    """Return the root of a private XDG layout and project for an OpenCode run with read tools only.

    OpenCode imports `.opencode/plugin` code from its project directory and each
    parent up to the git root, whatever its config says, so its project is an
    empty git repository here and the reviewed repository is an outside
    directory it may only read."""
    root = scratch_dir("opencode-")
    provider = model.split("/", 1)[0]
    outside = {"*": "deny"}
    outside.update({d + "/*": "allow" for d in read_dirs})
    permission = {"*": "deny", "read": "allow", "grep": "allow", "glob": "allow", "list": "allow",
                  "external_directory": outside}
    config = {"model": model, "small_model": model, "share": "disabled", "autoupdate": False,
              "permission": permission,
              "agent": {"ccl-review": {"mode": "primary", "description": "Read-only code review",
                                       "permission": permission}}}
    if provider in providers:
        config["provider"] = {provider: providers[provider]}
    for sub in ("config/opencode", "data/opencode", "state", "project"):
        os.makedirs(os.path.join(root, sub))
    subprocess.run(["git", "init", "-q", os.path.join(root, "project")], check=True, capture_output=True)
    write_private(os.path.join(root, "config", "opencode", "opencode.json"), json.dumps(config))
    data_home = Path(os.environ.get("XDG_DATA_HOME") or Path.home() / ".local" / "share")
    link_if_present(data_home / "opencode" / "auth.json", os.path.join(root, "data", "opencode", "auth.json"))
    return root


def model_family(model: Optional[str]) -> Optional[str]:
    lowered = (model or "").lower()
    return next((family for word, family in MODEL_FAMILY_WORDS if word in lowered), None)


def reviewer_family(client: str):
    """Return (family, model) of the model a client would review with; family None if unknown."""
    if client == "opencode":
        model, _ = opencode_config()
        return model_family(model), model
    if client == "kimi":
        model = kimi_config(kimi_source())[1].get("default_model")
        return model_family(model) or "kimi", model
    return client, None


def unbullet(text: str) -> str:
    # Kimi's text output bullets the first line and indents the rest by two spaces.
    lines = text.strip("\n").splitlines()
    if not lines or not lines[0].startswith("• "):
        return text
    return "\n".join([lines[0][2:]] + [line[2:] if line.startswith("  ") else line for line in lines[1:]])


def run_child(cmd: list, prompt: str, cwd: str, env: dict, timeout: int):
    """Run one reviewer; return (outcome, returncode, stdout, stderr)."""
    try:
        proc = subprocess.Popen(cmd, cwd=cwd, env=env, stdin=subprocess.PIPE,
                                stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                                text=True, start_new_session=True)
    except OSError as exc:
        return "missing", None, "", str(exc)
    try:
        out, err = proc.communicate(prompt, timeout=timeout)
    except subprocess.TimeoutExpired:
        if proc.poll() is None:
            _, err = reap(proc)
            return "timeout", None, "", err  # a cut-off answer is never read
        # The reviewer exited but a descendant still holds its pipes.
        out, err = reap(proc)
    except Interrupted:
        reap(proc)
        raise
    else:
        reap(proc)  # descendants left in the reviewer's group
    if proc.returncode in INTERRUPT_CODES or proc.returncode < 0:
        return "interrupted", proc.returncode, "", err
    return "ran", proc.returncode, out, err


def reap(proc):
    """Kill the reviewer's process group and drain its pipes within a bound."""
    try:
        os.killpg(proc.pid, signal.SIGKILL)
    except (ProcessLookupError, PermissionError):
        pass
    try:
        out, err = proc.communicate(timeout=5)
    except subprocess.TimeoutExpired:
        # A descendant in another session keeps the pipes open; stop reading.
        for pipe in (proc.stdin, proc.stdout, proc.stderr):
            if pipe:
                pipe.close()
        proc.wait()
        out, err = "", ""
    return out or "", err or ""


def run_client(client: str, prompt: str, cwd: str, timeout: int, diff_dir: str, meta: dict):
    env = dict(os.environ)
    if client == "opencode":
        model, providers = opencode_config()
        meta.update(model=model or "")
        root = private_opencode_root(model, providers, [cwd, diff_dir])
        project = os.path.join(root, "project")
        for name in ("OPENCODE_CONFIG", "OPENCODE_CONFIG_DIR", "OPENCODE_CONFIG_CONTENT", "OPENCODE_PERMISSION"):
            env.pop(name, None)
        env.update(XDG_CONFIG_HOME=os.path.join(root, "config"), XDG_DATA_HOME=os.path.join(root, "data"),
                   XDG_STATE_HOME=os.path.join(root, "state"), OPENCODE_DISABLE_PROJECT_CONFIG="1",
                   OPENCODE_DISABLE_DEFAULT_PLUGINS="1", OPENCODE_DISABLE_CLAUDE_CODE="1",
                   OPENCODE_DISABLE_AUTOUPDATE="1", OPENCODE_DISABLE_SHARE="1", OPENCODE_PURE="1")
        cmd = ["opencode", "run", "--dir", project, "--agent", "ccl-review", "-m", model, "--", prompt]
        try:
            return run_child(cmd, "", project, env, timeout)
        finally:
            shutil.rmtree(root, ignore_errors=True)
    if client == "kimi":
        source = kimi_source()
        home = private_kimi_home(source)
        model = kimi_config(source)[1].get("default_model")
        meta.update(model=model or "")
        env.pop("KIMI_CODE_TRUST_WORKSPACE", None)  # an untrusted workspace loads no project MCP or config
        env.update(KIMI_CODE_HOME=home, KIMI_CODE_WATCH="0", KIMI_DISABLE_TELEMETRY="1",
                   KIMI_CODE_NO_AUTO_UPDATE="1", KIMI_CLI_NO_AUTO_UPDATE="1")
        cmd = ["kimi", "--skills-dir", os.path.join(home, "no-skills"), "--add-dir", diff_dir]
        cmd += ["-m", model] if model else []
        cmd += ["-p", prompt, "--output-format", "text"]
        try:
            outcome, rc, out, err = run_child(cmd, "", cwd, env, timeout)
        finally:
            shutil.rmtree(home, ignore_errors=True)
        return outcome, rc, unbullet(out), err
    if client == "codex":
        source = Path(os.environ.get("CODEX_HOME") or Path.home() / ".codex")
        home, model, provider = private_codex_home(source)
        meta.update(model=model or "", provider=provider or "openai")
        answer = os.path.join(home, "answer.txt")
        env["CODEX_HOME"] = home
        cmd = ["codex", "exec", "-C", cwd, "-s", "read-only", "--ephemeral", "-o", answer, "-"]
        try:
            outcome, rc, _, err = run_child(cmd, prompt, cwd, env, timeout)
            text = ""
            if outcome == "ran" and os.path.exists(answer):
                text = Path(answer).read_text(encoding="utf-8", errors="replace")
        finally:
            shutil.rmtree(home, ignore_errors=True)
        return outcome, rc, text, err
    # No shell at all: git itself can write files (`git diff --output=...`), so
    # Claude gets only read tools and reads the diff the runner saved for it.
    cmd = ["claude", "-p", "--tools", *READ_TOOLS, "--add-dir", diff_dir,
           "--permission-mode", "dontAsk", "--setting-sources", "", "--strict-mcp-config",
           "--no-session-persistence", "--output-format", "text"]
    return run_child(cmd, prompt, cwd, env, timeout)


def write_json(path: Path, value: dict) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    # An exclusively created temp file, so a planted link is never followed.
    fd, tmp = tempfile.mkstemp(prefix=path.name + ".", dir=str(path.parent))
    with os.fdopen(fd, "w", encoding="utf-8") as fh:
        fh.write(json.dumps(value, indent=2, ensure_ascii=False) + "\n")
    os.replace(tmp, path)


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--cwd", required=True, help="repository under review")
    ap.add_argument("--mode", choices=("review", "challenge"), default="review")
    ap.add_argument("--intent", required=True, help="one or two sentences: what the change should do")
    ap.add_argument("--implementer-family", required=True,
                    help="model family that wrote the change: " + ", ".join(sorted(KNOWN_FAMILIES))
                    + " (aliases: anthropic, openai, gpt, moonshot)")
    ap.add_argument("--base", help="ref to diff against via merge-base (default: origin/HEAD)")
    ap.add_argument("--focus", default="", help="challenge: what to look at hardest")
    ap.add_argument("--client-order", default=DEFAULT_ORDER,
                    help="reviewers to try in turn until one answers (default: %(default)s)")
    ap.add_argument("--timeout", type=int, default=900, help="seconds per reviewer attempt")
    ap.add_argument("--out", help="result JSON path (default: under <git-dir>/ccl-code-review/)")
    args = ap.parse_args(argv)

    cwd = git(str(Path(args.cwd).resolve()), "rev-parse", "--show-toplevel")
    neutralize_filters(cwd)
    git_dir = Path(git(cwd, "rev-parse", "--absolute-git-dir"))
    head = git(cwd, "rev-parse", "HEAD")
    base = resolve_base(cwd, args.base)
    clean = git(cwd, "status", "--porcelain", "--untracked-files=all") == ""
    untracked = untracked_files(cwd)
    digest_before = candidate_digest(cwd)
    diff_dir = scratch_dir("diff-")
    diff_file = os.path.join(diff_dir, "change.diff")
    # Bytes, not text: a changed file need not be UTF-8.
    Path(diff_file).write_bytes(subprocess.run(
        ["git", "-C", cwd, *GIT_SAFETY, "diff", "--no-ext-diff", "--no-textconv", base],
        check=True, capture_output=True).stdout)
    started = time.time()

    def on_signal(signum, frame):
        raise Interrupted()

    signal.signal(signal.SIGINT, on_signal)
    signal.signal(signal.SIGTERM, on_signal)

    implementer = args.implementer_family.strip().lower()
    implementer = FAMILY_ALIASES.get(implementer, implementer)
    reviewers, skipped = [], []
    for client in (s.strip() for s in args.client_order.split(",")):
        if client not in CLIENTS or implementer not in KNOWN_FAMILIES:
            continue
        if not shutil.which(client):
            skipped.append({"client": client, "reason": "not_installed"})
            continue
        family, model = reviewer_family(client)
        if family is None:
            skipped.append({"client": client, "reason": "reviewer_family_unknown", "model": model or ""})
        elif family == implementer:
            skipped.append({"client": client, "reason": "same_family", "model": model or ""})
        else:
            reviewers.append((client, family))
    reason = None if implementer in KNOWN_FAMILIES else "implementer_family_ambiguous"
    status, findings, selected, family, attempts, diagnostics = None, [], "", "", [], []
    prompt = build_prompt(args.mode, cwd, base, args.intent, args.focus, untracked, diff_file)
    # Each reviewer runs in turn until one answers. Every attempt has its own
    # private home and its answer is read only after a clean exit, so nothing
    # from a failed attempt reaches the verdict. An interrupt ends the chain.
    try:
        for selected, family in reviewers:
            t0, meta = time.time(), {}
            attempt = {"client": selected, "status": "operator_interrupt"}
            attempts.append(attempt)
            try:
                outcome, rc, text, err = run_client(selected, prompt, cwd, args.timeout, diff_dir, meta)
            except (OSError, subprocess.CalledProcessError) as exc:
                # Its private home could not be built; the next reviewer still runs.
                outcome, rc, text, err = "missing", None, "", str(exc)
            attempt.update(returncode=rc, elapsed_seconds=round(time.time() - t0, 1), **meta)
            if text or err:
                diagnostics.append((selected, text, err))
            status, findings, reason = None, [], None
            if outcome == "interrupted":
                reason = "operator_interrupt"
            elif outcome == "timeout":
                reason = "reviewer_timeout"
            elif outcome == "missing":
                reason = "reviewer_launch_failed"
            elif rc != 0:
                reason = "reviewer_failed"  # its text is never a verdict
            elif not text.strip():
                reason = "empty_answer"
            else:
                status, findings = parse_answer(text)
                findings = [redact_finding(f) for f in findings] if status else []
                if status is None:
                    reason = "unparseable_answer"
            attempt["status"] = status or reason
            if status or reason == "operator_interrupt":
                break
        else:
            reason = reason or "no_eligible_reviewer"
    except Interrupted:
        status, findings, reason = None, [], "operator_interrupt"
    finally:
        shutil.rmtree(diff_dir, ignore_errors=True)

    if status and candidate_digest(cwd) != digest_before:
        status, findings, reason = None, [], "candidate_changed"
    final = status or "inconclusive"
    recorded_at = datetime.datetime.now(datetime.timezone.utc).isoformat(timespec="seconds")
    result = {
        "schema_version": SCHEMA_VERSION,
        "runner": "review_diff",
        "mode": args.mode,
        "status": final,
        "reason_code": reason,
        "findings": findings,
        "selected_client": selected,
        "reviewer_family": family,
        "implementer_family": implementer,
        "base": base,
        "head": head,
        "candidate_digest": digest_before,
        "worktree_clean": clean,
        "untracked_files": untracked,
        "intent_sha256": hashlib.sha256(args.intent.encode("utf-8")).hexdigest(),
        "elapsed_seconds": round(time.time() - started, 1),
        "attempts": attempts,
        "skipped": skipped,
        "recorded_at": recorded_at,
    }
    stamp = recorded_at.replace(":", "").replace("+0000", "Z")
    # The answer and stderr can quote repository content or credentials, so they
    # go to a private file under the git dir, never into the shareable result.
    if diagnostics:
        diag = git_dir / "ccl-code-review" / "diagnostics" / f"{stamp}-{args.mode}.txt"
        diag.parent.mkdir(parents=True, exist_ok=True)
        write_private(str(diag), "".join(
            f"## {client} answer\n{text[:DIAG_LIMIT]}\n## {client} stderr (tail)\n{err[-DIAG_LIMIT:]}\n"
            for client, text, err in diagnostics))
        result["diagnostics_path"] = str(diag)
    out = Path(args.out) if args.out else git_dir / "ccl-code-review" / "results" / f"{stamp}-{args.mode}.json"
    write_json(out, result)
    receipt = {k: result[k] for k in ("head", "worktree_clean", "mode", "status", "recorded_at",
                                       "candidate_digest", "selected_client", "runner")}
    receipt["result_path"] = str(out)
    write_json(git_dir / "ccl-code-review" / "last-review.json", receipt)

    print(json.dumps({"status": final, "reason_code": reason, "result": str(out),
                      "reviewer": selected, "elapsed_seconds": result["elapsed_seconds"]}))
    for f in findings:
        print(f"[{f['severity']}] {f['title']} — {f['file']}:{f['line']}")
    return {"passed": 0, "findings": 1}.get(final, 2)


if __name__ == "__main__":
    sys.exit(main())
