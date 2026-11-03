#!/usr/bin/env python3
"""Run an independent code review where the reviewer reads the diff itself.

The reviewer CLI runs read-only inside the repository, reads `git diff` against
the merge base and whatever surrounding code it needs, and answers in a fixed
text form. This runner only picks an independent reviewer, binds the reviewed
candidate, parses the answer, and records the result and the local receipt the
pull-request reminder reads.

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
FAMILY = {"codex": "codex", "claude": "claude"}
# Spellings of a model family used across this repository and its callers.
FAMILY_ALIASES = {"openai": "codex", "gpt": "codex", "chatgpt": "codex", "anthropic": "claude",
                  "moonshot": "kimi"}
# Families an implementer can be named as. A client name that can run any model
# (opencode) or "other" says nothing about independence, so it is refused.
KNOWN_FAMILIES = {"claude", "codex", "kimi"}
DEFAULT_ORDER = "codex,claude"
INTERRUPT_CODES = {130, 137, 143}
# Top-level Codex config keys carried into the reviewer's private home, plus the
# table of the provider they select. An allowlist on purpose: anything else
# (mcp_servers, hooks, plugins, other providers) stays out.
CODEX_KEYS = ("model", "model_reasoning_effort", "model_provider", "model_verbosity")
FINDING = re.compile(r"^\s*\[(P[0-3])\]\s+(.+?)\s+[—–-]{1,2}\s+(\S+?):(\d+)\s*$")
RAW_LIMIT = 20000

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
        listed = git(cwd, "config", "--get-regexp", r"^filter\..*\.(clean|smudge|process)$")
    except subprocess.CalledProcessError:
        return  # none configured
    for name in sorted({line.split()[0].rsplit(".", 1)[0][len("filter."):] for line in listed.splitlines() if line}):
        GIT_SAFETY.extend(["-c", f"filter.{name}.clean=cat", "-c", f"filter.{name}.smudge=cat",
                           "-c", f"filter.{name}.process=", "-c", f"filter.{name}.required=false"])


def resolve_base(cwd: str, ref: Optional[str]) -> str:
    if not ref:
        try:
            ref = git(cwd, "symbolic-ref", "-q", "--short", "refs/remotes/origin/HEAD")
        except subprocess.CalledProcessError:
            ref = "origin/main"
    return git(cwd, "merge-base", "HEAD", ref)


def candidate_tree(cwd: str) -> str:
    """Tree id of the working tree, untracked files included, via a scratch index."""
    fd, index = tempfile.mkstemp(prefix="review-index-")
    os.close(fd)
    os.unlink(index)
    env = dict(os.environ, GIT_INDEX_FILE=index)
    try:
        git(cwd, "read-tree", "HEAD", env=env)
        git(cwd, "add", "-A", env=env)
        return git(cwd, "write-tree", env=env)
    finally:
        if os.path.exists(index):
            os.unlink(index)


def build_prompt(mode: str, base: str, intent: str, focus: str, untracked: list,
                 diff_file: Optional[str]) -> str:
    """diff_file is set for reviewers without a shell: they read the saved diff."""
    if diff_file:
        see = f"Read the diff saved at {diff_file} (it includes uncommitted edits), and read"
    else:
        see = f"Run `git diff {base}` to see it (it includes uncommitted edits), and read"
    lines = [
        f"Review the change in this repository against base commit {base}.",
        see,
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
    # Only the bare sentinel is a pass: "reads failed ... No findings." is not.
    return ("passed", []) if text.strip() == "No findings." else (None, [])


def scratch_dir(prefix: str) -> str:
    # Not under the system temp dir: Codex refuses to create its sandbox helper
    # binaries there, and every shell command in the review then fails.
    parent = Path(os.environ.get("XDG_CACHE_HOME") or Path.home() / ".cache") / "ccl-code-review"
    parent.mkdir(parents=True, exist_ok=True)
    path = tempfile.mkdtemp(prefix=prefix, dir=str(parent))
    os.chmod(path, 0o700)
    return path


def private_codex_home(source: Path) -> str:
    home = scratch_dir("codex-home-")
    auth = source / "auth.json"
    if auth.exists():
        # A link, so a refreshed token lands in the user's own file.
        os.symlink(auth, os.path.join(home, "auth.json"))
    kept, table, provider = [], None, None
    config = source / "config.toml"
    if config.is_file():
        for line in config.read_text(encoding="utf-8", errors="replace").splitlines():
            stripped = line.strip()
            if stripped.startswith("["):
                table = stripped.strip("[]").replace('"', "").replace("'", "").strip()
                selected = provider and (table == f"model_providers.{provider}"
                                         or table.startswith(f"model_providers.{provider}."))
                if selected:
                    kept += ["", line]
                continue
            key = stripped.split("=", 1)[0].strip()
            if table is None and key in CODEX_KEYS:
                kept.append(line)
                if key == "model_provider":
                    value = stripped.split("=", 1)[1].strip()
                    quoted = re.match(r"""^(["'])(.*?)\1""", value)
                    provider = quoted.group(2) if quoted else value.split("#", 1)[0].strip()
            elif table is not None and provider and (table == f"model_providers.{provider}"
                                                     or table.startswith(f"model_providers.{provider}.")):
                kept.append(line)
    Path(home, "config.toml").write_text("\n".join(kept) + "\n", encoding="utf-8")
    return home


def run_child(cmd: list, prompt: str, cwd: str, env: dict, timeout: int):
    """Run one reviewer; return (outcome, returncode, stdout)."""
    try:
        proc = subprocess.Popen(cmd, cwd=cwd, env=env, stdin=subprocess.PIPE,
                                stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                                text=True, start_new_session=True)
    except OSError:
        return "missing", None, ""
    try:
        out, _ = proc.communicate(prompt, timeout=timeout)
    except subprocess.TimeoutExpired:
        if proc.poll() is None:
            reap(proc)
            return "timeout", None, ""
        # The reviewer exited but a descendant still holds its pipes.
        out = reap(proc)
    except Interrupted:
        reap(proc)
        raise
    else:
        reap(proc)  # descendants left in the reviewer's group
    if proc.returncode in INTERRUPT_CODES or proc.returncode < 0:
        return "interrupted", proc.returncode, out
    return "ran", proc.returncode, out


def reap(proc) -> str:
    """Kill the reviewer's process group and drain its pipes within a bound."""
    try:
        os.killpg(proc.pid, signal.SIGKILL)
    except (ProcessLookupError, PermissionError):
        pass
    try:
        out, _ = proc.communicate(timeout=5)
    except subprocess.TimeoutExpired:
        # A descendant in another session keeps the pipes open; stop reading.
        for pipe in (proc.stdin, proc.stdout, proc.stderr):
            if pipe:
                pipe.close()
        proc.wait()
        out = ""
    return out or ""


def run_client(client: str, prompt: str, cwd: str, timeout: int, diff_dir: str):
    env = dict(os.environ)
    if client == "codex":
        source = Path(os.environ.get("CODEX_HOME") or Path.home() / ".codex")
        home = private_codex_home(source)
        answer = os.path.join(home, "answer.txt")
        env["CODEX_HOME"] = home
        cmd = ["codex", "exec", "-C", cwd, "-s", "read-only", "--ephemeral", "-o", answer, "-"]
        try:
            outcome, rc, _ = run_child(cmd, prompt, cwd, env, timeout)
            text = Path(answer).read_text(encoding="utf-8", errors="replace") if os.path.exists(answer) else ""
        finally:
            shutil.rmtree(home, ignore_errors=True)
        return outcome, rc, text
    # No shell at all: git itself can write files (`git diff --output=...`), so
    # Claude gets only read tools and reads the diff the runner saved for it.
    cmd = ["claude", "-p", "--tools", "Read", "Grep", "Glob", "--add-dir", diff_dir,
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
                    help="model family that wrote the change: claude, codex or kimi (aliases: anthropic, openai, gpt)")
    ap.add_argument("--base", help="ref to diff against via merge-base (default: origin/HEAD)")
    ap.add_argument("--focus", default="", help="challenge: what to look at hardest")
    ap.add_argument("--client-order", default=DEFAULT_ORDER)
    ap.add_argument("--timeout", type=int, default=900, help="seconds per reviewer attempt")
    ap.add_argument("--out", help="result JSON path (default: under <git-dir>/ccl-code-review/)")
    args = ap.parse_args(argv)

    cwd = git(str(Path(args.cwd).resolve()), "rev-parse", "--show-toplevel")
    neutralize_filters(cwd)
    git_dir = Path(git(cwd, "rev-parse", "--absolute-git-dir"))
    head = git(cwd, "rev-parse", "HEAD")
    base = resolve_base(cwd, args.base)
    clean = git(cwd, "status", "--porcelain", "--untracked-files=all") == ""
    untracked = [p for p in git(cwd, "ls-files", "--others", "--exclude-standard").splitlines() if p]
    tree_before = candidate_tree(cwd)
    diff_dir = scratch_dir("diff-")
    diff_file = os.path.join(diff_dir, "change.diff")
    Path(diff_file).write_text(git(cwd, "diff", "--no-ext-diff", "--no-textconv", base) + "\n",
                               encoding="utf-8")
    started = time.time()

    def on_signal(signum, frame):
        raise Interrupted()

    signal.signal(signal.SIGINT, on_signal)
    signal.signal(signal.SIGTERM, on_signal)

    implementer = args.implementer_family.strip().lower()
    implementer = FAMILY_ALIASES.get(implementer, implementer)
    eligible = [c for c in (s.strip() for s in args.client_order.split(","))
                if c in FAMILY and FAMILY[c] != implementer]
    attempts, status, findings, selected, text, reason = [], None, [], None, "", None
    carried = []  # findings from attempts whose run failed; a later pass cannot erase them
    if implementer not in KNOWN_FAMILIES:
        eligible, reason = [], "implementer_family_ambiguous"
    try:
        for client in eligible:
            if shutil.which(client) is None:
                attempts.append({"client": client, "status": "missing"})
                continue
            t0 = time.time()
            prompt = build_prompt(args.mode, base, args.intent, args.focus, untracked,
                                  diff_file if client == "claude" else None)
            outcome, rc, text = run_client(client, prompt, cwd, args.timeout, diff_dir)
            attempt = {"client": client, "returncode": rc, "elapsed_seconds": round(time.time() - t0, 1)}
            attempts.append(attempt)
            if outcome == "interrupted":
                attempt["status"], reason = "interrupted", "operator_interrupt"
                break
            if outcome != "ran" or rc != 0 or not text.strip():
                # A failed run's text is never a verdict; the next family gets one try.
                attempt["status"] = outcome if outcome != "ran" else ("failed" if rc else "empty")
                carried += [dict(f, from_failed_attempt=client) for f in parse_answer(text)[1]]
                continue
            status, findings = parse_answer(text)
            attempt["status"] = status or "unparseable"
            selected = client
            if status is None:
                reason = "unparseable_answer"
            break
        else:
            reason = reason or ("no_eligible_reviewer" if not attempts else "all_reviewers_failed")
    except Interrupted:
        status, reason = None, "operator_interrupt"
    finally:
        shutil.rmtree(diff_dir, ignore_errors=True)

    if carried:
        findings = findings + carried
        if status == "passed":
            status = "findings"
    if status and candidate_tree(cwd) != tree_before:
        status, reason = None, "candidate_changed"
    final = status or "inconclusive"
    recorded_at = datetime.datetime.now(datetime.timezone.utc).isoformat(timespec="seconds")
    result = {
        "schema_version": SCHEMA_VERSION,
        "runner": "review_diff",
        "mode": args.mode,
        "status": final,
        "reason_code": reason,
        "findings": findings,
        "selected_client": selected if status else (selected or ""),
        "reviewer_family": FAMILY.get(selected or "", ""),
        "implementer_family": implementer,
        "base": base,
        "head": head,
        "candidate_tree": tree_before,
        "worktree_clean": clean,
        "untracked_files": untracked,
        "intent_sha256": hashlib.sha256(args.intent.encode("utf-8")).hexdigest(),
        "elapsed_seconds": round(time.time() - started, 1),
        "attempts": attempts,
        "recorded_at": recorded_at,
        "raw_answer": text[:RAW_LIMIT],
    }
    stamp = recorded_at.replace(":", "").replace("+0000", "Z")
    out = Path(args.out) if args.out else git_dir / "ccl-code-review" / "results" / f"{stamp}-{args.mode}.json"
    write_json(out, result)
    receipt = {k: result[k] for k in ("head", "worktree_clean", "mode", "status", "recorded_at",
                                       "candidate_tree", "selected_client", "runner")}
    receipt["result_path"] = str(out)
    write_json(git_dir / "ccl-code-review" / "last-review.json", receipt)

    print(json.dumps({"status": final, "reason_code": reason, "result": str(out),
                      "reviewer": selected, "elapsed_seconds": result["elapsed_seconds"]}))
    for f in findings:
        print(f"[{f['severity']}] {f['title']} — {f['file']}:{f['line']}")
    return {"passed": 0, "findings": 1}.get(final, 2)


if __name__ == "__main__":
    sys.exit(main())
