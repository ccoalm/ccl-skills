#!/usr/bin/env python3
"""Run an independent code review where the reviewer reads the diff itself.

The reviewer CLI runs read-only, reads the diff against the merge base that
this runner saved and whatever surrounding code it needs, and answers in a
fixed text form. This runner only picks independent reviewers, trying the next
when one fails, binds the reviewed candidate, parses the answer, and records
the result and the local receipt the pull-request reminder reads. The reviewer
clients live in review_diff_clients.py.

stdout carries the result line and the findings; progress and the summary go
to stderr. Exit codes: 0 passed, 1 findings, 2 inconclusive or not run.
"""
# No `from __future__ import annotations`: callers load this file by path
# without registering it in sys.modules, where dataclasses would look up
# string annotations.
import argparse
import datetime
import functools
import hashlib
import importlib.util
import json
import os
import re
import shutil
import signal
import subprocess
import sys
import tempfile
import time
import traceback
from dataclasses import dataclass, field
from pathlib import Path
from typing import Optional

HERE = Path(__file__).resolve().parent


def _load_sibling(name: str):
    """Load a module that ships next to this file, by path, so a module of that
    name in the caller's directory or on sys.path cannot stand in for it."""
    spec = importlib.util.spec_from_file_location(name, str(HERE / f"{name}.py"))
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


try:
    clients = _load_sibling("review_diff_clients")
except Exception as exc:  # a partial install; entry() reports it rather than exit 1
    clients, CLIENTS_ERROR = None, exc

SCHEMA_VERSION = 3  # the envelope check_review_evidence_present.py accepts
FINDING = re.compile(r"^\s*\[(P[0-3])\]\s+(.+?)\s+[—–-]{1,2}\s+(\S+?):(\d+)\s*$")
DIAG_LIMIT = 20000  # bytes of answer and of stderr kept in the private diagnostics file

# Replayed on past changes with known defects, a reviewer told to drop what it
# cannot prove from the code found about half as many of them
# (specs/diff-first-review/evidence/replay.md).
REVIEW_BRIEF = """Find defects this change introduces: correctness, security, data loss, broken
contracts, missing error handling, unsafe edge cases, and tests that would not
fail when the defect is present. Go through every hunk of the diff before
reading further. Report every defect you suspect with a concrete failing
scenario, including ones you could not fully confirm from the surrounding code;
say in the scenario what you could not confirm. Do not drop a suspicion only
because proving it would need more context. Skip style and problems that
existed before the change."""

CHALLENGE_BRIEF = """Think like an attacker and a chaos engineer. Find ways this change fails in
production: edge cases, races, security holes, resource leaks, silent data
corruption, swallowed errors and trust-boundary violations. Report only problems
in the changed code that you can show with a concrete scenario."""


# The candidate under review.

class Git:
    """git in one repository with repository-configured programs switched off.

    Repository config can name programs git runs on status, add and diff
    (fsmonitor, filter drivers, textconv, external diff). The candidate may
    carry those programs, so every git call here switches them off; diff also
    passes --no-ext-diff --no-textconv."""

    def __init__(self, cwd: str):
        self.cwd = cwd
        self.safety = ["-c", "core.fsmonitor=false"]

    def raw(self, *args: str) -> bytes:
        return subprocess.run(["git", "-C", self.cwd, *self.safety, *args],
                              check=True, capture_output=True).stdout

    def out(self, *args: str) -> str:
        return subprocess.run(["git", "-C", self.cwd, *self.safety, *args],
                              check=True, capture_output=True, text=True).stdout.strip()

    def neutralize_filters(self) -> None:
        """Replace every configured filter driver with a pass-through."""
        try:
            # Names only: a value can span lines and must never be parsed.
            listed = self.out("config", "--name-only", "--get-regexp", r"^filter\..*\.(clean|smudge|process)$")
        except subprocess.CalledProcessError:
            return  # none configured
        for name in sorted({key.rsplit(".", 1)[0][len("filter."):] for key in listed.splitlines() if key.strip()}):
            self.safety.extend(["-c", f"filter.{name}.clean=cat", "-c", f"filter.{name}.smudge=cat",
                                "-c", f"filter.{name}.process=", "-c", f"filter.{name}.required=false"])

    def untracked(self) -> list:
        # -z: unquoted paths, so non-ASCII names resolve on disk.
        out = self.raw("ls-files", "-z", "--others", "--exclude-standard")
        return sorted(p.decode("utf-8", "surrogateescape") for p in out.split(b"\0") if p)

    def digest(self) -> str:
        """Digest of HEAD and the working tree against it, untracked files included.

        Computed without writing objects: staging the tree would store working-tree
        bytes (with filters switched off, possibly plaintext) in the object store."""
        digest = hashlib.sha256(self.out("rev-parse", "HEAD").encode("ascii") + b"\0")
        digest.update(self.raw("diff", "--binary", "--no-ext-diff", "--no-textconv", "HEAD"))

        def frame(kind: bytes, data: bytes) -> None:
            digest.update(kind + len(data).to_bytes(8, "big") + data)

        for rel in self.untracked():
            path = os.path.join(self.cwd, rel)
            frame(b"P", rel.encode("utf-8", "surrogateescape"))
            if os.path.islink(path):
                frame(b"L", os.readlink(path).encode("utf-8", "surrogateescape"))
            elif os.path.isfile(path):
                frame(b"M", oct(os.stat(path).st_mode & 0o777).encode("ascii"))
                with open(path, "rb") as fh:
                    frame(b"F", hashlib.sha256(fh.read()).digest())
        return digest.hexdigest()


@dataclass(frozen=True)
class Candidate:
    """What is reviewed: the working tree, uncommitted edits included, against a base.

    Bound once before the first attempt; a verdict is void if the digest moves."""
    git: Git
    root: str
    git_dir: Path
    head: str
    base: str
    clean: bool
    untracked: list
    digest: str

    @classmethod
    def bind(cls, path: str, base_ref: Optional[str]) -> "Candidate":
        root = Git(str(Path(path).resolve())).out("rev-parse", "--show-toplevel")
        git = Git(root)
        git.neutralize_filters()
        git_dir = Path(git.out("rev-parse", "--absolute-git-dir"))
        head = git.out("rev-parse", "HEAD")
        if not base_ref:
            try:
                base_ref = git.out("symbolic-ref", "-q", "--short", "refs/remotes/origin/HEAD")
            except subprocess.CalledProcessError:
                base_ref = "origin/main"
        base = git.out("merge-base", "HEAD", base_ref)
        clean = git.out("status", "--porcelain", "--untracked-files=all") == ""
        return cls(git, root, git_dir, head, base, clean, git.untracked(), git.digest())

    def save_diff(self, path: str) -> int:
        """Write the diff against the base for the reviewer; return how many files it touches."""
        # Bytes, not text: a changed file need not be UTF-8.
        data = self.git.raw("diff", "--no-ext-diff", "--no-textconv", self.base)
        Path(path).write_bytes(data)
        return sum(1 for line in data.splitlines() if line.startswith(b"diff --git ")) + len(self.untracked)

    def changed(self) -> bool:
        return self.git.digest() != self.digest


def build_prompt(mode: str, candidate: Candidate, intent: str, focus: str, diff_file: str) -> str:
    # The reviewer reads the diff the runner saved with repository-configured git
    # programs switched off; a `git diff` of its own could be replaced by them.
    lines = [
        f"Review the change in the repository at {candidate.root} against base commit {candidate.base}.",
        f"Read the diff saved at {diff_file} (it includes uncommitted edits), and read",
        "surrounding code, tests and AGENTS.md files as needed. Do not modify anything.",
    ]
    if candidate.untracked:
        lines.append("These new untracked files are part of the change; read them directly:")
        lines += [f"- {p}" for p in candidate.untracked]
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
        "Your final message is read by a program: put nothing else in it, no summary.",
    ]
    return "\n".join(lines) + "\n"


# Judging an answer.

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


@functools.lru_cache(maxsize=None)
def _secret_patterns():
    """The controller's egress secret patterns, so both runners agree on what a credential is."""
    spec = importlib.util.spec_from_file_location("review_gate_patterns", str(HERE / "review_gate.py"))
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


def judge(run) -> tuple:
    """Return (status, findings, reason) for one run; a failed run's text is never a verdict."""
    if run.outcome == "interrupted":
        return None, [], "operator_interrupt"
    if run.outcome == "timeout":
        return None, [], "reviewer_timeout"
    if run.outcome == "missing":
        return None, [], "reviewer_launch_failed"
    if run.returncode != 0:
        return None, [], "reviewer_failed"
    if not run.answer.strip():
        return None, [], "empty_answer"
    status, findings = parse_answer(run.answer)
    if status is None:
        return None, [], "unparseable_answer"
    return status, [redact_finding(f) for f in findings], None


# The attempts.

@dataclass
class Attempt:
    client: str
    status: str = "operator_interrupt"  # until the run returns
    returncode: Optional[int] = None
    elapsed_seconds: Optional[float] = None
    meta: dict = field(default_factory=dict)  # model and provider, as the client recorded them
    answer: str = ""  # kept out of the result: it can quote repository content
    stderr: str = ""
    finished: bool = False

    def record(self) -> dict:
        if not self.finished:
            return {"client": self.client, "status": self.status}
        return {"client": self.client, "status": self.status, "returncode": self.returncode,
                "elapsed_seconds": self.elapsed_seconds, **self.meta}


@dataclass
class Review:
    status: Optional[str] = None
    findings: list = field(default_factory=list)
    reason: Optional[str] = None
    attempts: list = field(default_factory=list)
    selected: str = ""
    family: str = ""


def run_attempts(reviewers: list, prompt: str, candidate: Candidate, diff_dir: str, timeout: int,
                 reason: Optional[str], progress: "Progress") -> Review:
    """Run each reviewer in turn until one answers.

    Every attempt has its own private home and its answer is read only after a
    clean exit, so nothing from a failed attempt reaches the verdict. An
    interrupt ends the chain. `reason` stands when no reviewer runs."""
    review = Review(reason=reason)
    try:
        for index, reviewer in enumerate(reviewers):
            name = reviewer.client.name
            review.selected, review.family = name, reviewer.family
            attempt = Attempt(name)
            review.attempts.append(attempt)
            progress.attempt_started(name, reviewer.model, timeout)
            t0 = time.time()
            try:
                run = reviewer.client.run(reviewer.snapshot, prompt, candidate.root, diff_dir, timeout, attempt.meta)
            except (OSError, subprocess.CalledProcessError) as exc:
                # Its private home could not be built; the next reviewer still runs.
                run = clients.Run("missing", stderr=str(exc))
            attempt.returncode, attempt.elapsed_seconds = run.returncode, round(time.time() - t0, 1)
            attempt.answer, attempt.stderr, attempt.finished = run.answer, run.stderr, True
            review.status, review.findings, review.reason = judge(run)
            attempt.status = review.status or review.reason
            following = reviewers[index + 1].client.name if index + 1 < len(reviewers) else None
            progress.attempt_finished(attempt, review.reason, following)
            if review.status or review.reason == "operator_interrupt":
                break
        else:
            review.reason = review.reason or "no_eligible_reviewer"
    except clients.Interrupted:
        review.status, review.findings, review.reason = None, [], "operator_interrupt"
    return review


# What the person or agent running the review sees.

SKIP_TEXT = {"not_installed": "not installed", "config_unreadable": "config unreadable",
             "reviewer_family_unknown": "model family unknown", "same_family": "same family as the implementer"}
FAILURE_TEXT = {"reviewer_timeout": "timed out", "reviewer_launch_failed": "could not start",
                "reviewer_failed": "exited with an error", "empty_answer": "gave an empty answer",
                "unparseable_answer": "gave an answer not in the required form",
                "operator_interrupt": "was interrupted"}
INCONCLUSIVE_TEXT = {
    "no_eligible_reviewer": ("no installed reviewer of another model family",
                             "install a reviewer CLI of another family, or name one in --client-order"),
    "implementer_family_ambiguous": ("the model family that wrote the change is unknown",
                                     "pass the family of the model that wrote it to --implementer-family"),
    "operator_interrupt": ("interrupted", "rerun when ready; nothing was recorded as reviewed"),
    "candidate_changed": ("the working tree changed during the review", "let the working tree settle and rerun"),
    "reviewer_timeout": (None, "rerun with a larger --timeout, or review a smaller change"),
}
READ_DIAGNOSTICS = "read the diagnostics file, fix the cause (often login, quota or config) and rerun"
NO_DIAGNOSTICS = "the reviewer printed nothing; check its login, quota and model config, then rerun"


def duration(seconds: float) -> str:
    seconds = int(round(seconds))
    return f"{seconds}s" if seconds < 60 else f"{seconds // 60}m{seconds % 60:02d}s"


def to_stderr(text: str) -> None:
    """Write one line to stderr without ever failing the run or touching stdout."""
    stream = sys.stderr
    if stream is None:  # closed at start; print(file=None) would write to stdout
        return
    try:
        print(text, file=stream, flush=True)
    except ValueError:  # closed by someone else
        pass
    except OSError:
        # The reader left. Point fd 2 at /dev/null so the interpreter's final
        # flush cannot fail and replace the verdict's exit code with 120.
        try:
            os.dup2(os.open(os.devnull, os.O_WRONLY), stream.fileno())
        except (OSError, ValueError):
            pass


class Progress:
    """Plain lines on stderr for whoever watches the run."""

    def __init__(self, mode: str):
        self.mode = mode

    def say(self, text: str, detail: bool = False) -> None:
        to_stderr(f"  {text}" if detail else f"{self.mode}: {text}")

    def started(self, candidate: Candidate, files: int) -> None:
        note = "" if candidate.clean else ", uncommitted edits included"
        self.say(f"{files} file{'' if files == 1 else 's'} changed against {candidate.base[:7]}, "
                 f"head {candidate.head[:7]}{note}")

    def skipped(self, skipped: list) -> None:
        def why(s):
            text = SKIP_TEXT.get(s["reason"], s["reason"])
            return f"{text}: {s['model']}" if s.get("model") else text

        if skipped:
            self.say("skipped " + ", ".join(f"{s['client']} ({why(s)})" for s in skipped))

    def attempt_started(self, client: str, model: Optional[str], timeout: int) -> None:
        self.say(f"{client} reviewing ({model + ', ' if model else ''}timeout {timeout}s)")

    def attempt_finished(self, attempt: Attempt, reason: Optional[str], following: Optional[str]) -> None:
        took = duration(attempt.elapsed_seconds or 0)
        if reason is None:
            self.say(f"{attempt.client} answered in {took}")
            return
        failure = FAILURE_TEXT.get(reason, reason)
        if reason == "reviewer_failed":
            failure = f"exited {attempt.returncode}"
        then = f"; trying {following}" if following and reason != "operator_interrupt" else ""
        self.say(f"{attempt.client} {failure} after {took}{then}")

    def summary(self, result: dict) -> None:
        status, reason, client = result["status"], result["reason_code"], result["selected_client"]
        took = duration(result["elapsed_seconds"])
        if status == "findings":
            counts = {}
            for f in result["findings"]:
                counts[f["severity"]] = counts.get(f["severity"], 0) + 1
            by_severity = ", ".join(f"{n} {sev}" for sev, n in sorted(counts.items()))
            self.say(f"findings: {len(result['findings'])} ({by_severity}) from {client} in {took}")
        elif status == "passed":
            self.say(f"passed, no findings from {client} in {took}")
        else:
            fallback = READ_DIAGNOSTICS if result.get("diagnostics_path") else NO_DIAGNOSTICS
            what, action = INCONCLUSIVE_TEXT.get(reason, (None, fallback))
            if what is None:
                what = f"no reviewer answered; the last one {FAILURE_TEXT.get(reason, reason)}"
            self.say(f"inconclusive: {what}")
            self.say(f"next: {action}", detail=True)
        self.say(f"result: {result['result_path']}", detail=True)
        if result.get("diagnostics_path"):
            self.say(f"diagnostics: {result['diagnostics_path']} (private)", detail=True)


# Recording the result.

def write_json(path: Path, value: dict) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    # An exclusively created temp file, so a planted link is never followed.
    fd, tmp = tempfile.mkstemp(prefix=path.name + ".", dir=str(path.parent))
    with os.fdopen(fd, "w", encoding="utf-8") as fh:
        fh.write(json.dumps(value, indent=2, ensure_ascii=False) + "\n")
    os.replace(tmp, path)


def record(args, candidate: Candidate, review: Review, implementer: str, skipped: list,
           started: float) -> dict:
    """Write the diagnostics, the result and the receipt; return the result plus where it went."""
    final = review.status or "inconclusive"
    recorded_at = datetime.datetime.now(datetime.timezone.utc).isoformat(timespec="seconds")
    result = {
        "schema_version": SCHEMA_VERSION,
        "runner": "review_diff",
        "mode": args.mode,
        "status": final,
        "reason_code": review.reason,
        "findings": review.findings,
        "selected_client": review.selected,
        "reviewer_family": review.family,
        "implementer_family": implementer,
        "base": candidate.base,
        "head": candidate.head,
        "candidate_digest": candidate.digest,
        "worktree_clean": candidate.clean,
        "untracked_files": candidate.untracked,
        "intent_sha256": hashlib.sha256(args.intent.encode("utf-8")).hexdigest(),
        "elapsed_seconds": round(time.time() - started, 1),
        "attempts": [a.record() for a in review.attempts],
        "skipped": skipped,
        "recorded_at": recorded_at,
    }
    stamp = recorded_at.replace(":", "").replace("+0000", "Z")
    store = candidate.git_dir / "ccl-code-review"
    # The answer and stderr can quote repository content or credentials, so they
    # go to a private file under the git dir, never into the shareable result.
    noisy = [a for a in review.attempts if a.answer or a.stderr]
    if noisy:
        diag = store / "diagnostics" / f"{stamp}-{args.mode}.txt"
        diag.parent.mkdir(parents=True, exist_ok=True)
        clients.write_private(str(diag), "".join(
            f"## {a.client} answer\n{a.answer[:DIAG_LIMIT]}\n## {a.client} stderr (tail)\n{a.stderr[-DIAG_LIMIT:]}\n"
            for a in noisy))
        result["diagnostics_path"] = str(diag)
    out = Path(args.out) if args.out else store / "results" / f"{stamp}-{args.mode}.json"
    write_json(out, result)
    receipt = {k: result[k] for k in ("head", "worktree_clean", "mode", "status", "recorded_at",
                                       "candidate_digest", "selected_client", "runner")}
    receipt["result_path"] = str(out)
    write_json(store / "last-review.json", receipt)
    return dict(result, result_path=str(out))


def emit(result: dict) -> None:
    """The machine-readable lines on stdout. A reader that left early costs nothing:
    the result file is the record."""
    if sys.stdout is None:  # closed at start
        return
    try:
        print(json.dumps({"status": result["status"], "reason_code": result["reason_code"],
                          "result": result["result_path"], "reviewer": result["selected_client"],
                          "elapsed_seconds": result["elapsed_seconds"]}))
        for f in result["findings"]:
            print(f"[{f['severity']}] {f['title']} — {f['file']}:{f['line']}")
        sys.stdout.flush()
    except BrokenPipeError:
        # Point stdout at /dev/null so the interpreter's final flush cannot fail again.
        os.dup2(os.open(os.devnull, os.O_WRONLY), sys.stdout.fileno())


# Entry point.

def parse_args(argv):
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--cwd", required=True, help="repository under review")
    ap.add_argument("--mode", choices=("review", "challenge"), default="review")
    ap.add_argument("--intent", required=True, help="one or two sentences: what the change should do")
    ap.add_argument("--implementer-family", required=True,
                    help="model family that wrote the change: " + ", ".join(sorted(clients.KNOWN_FAMILIES))
                    + " (aliases: anthropic, openai, gpt, moonshot)")
    ap.add_argument("--base", help="ref to diff against via merge-base (default: origin/HEAD)")
    ap.add_argument("--focus", default="", help="challenge: what to look at hardest")
    ap.add_argument("--client-order", default=",".join(clients.CLIENT_ORDER),
                    help="reviewers to try in turn until one answers (default: %(default)s)")
    ap.add_argument("--timeout", type=int, default=900, help="seconds per reviewer attempt")
    ap.add_argument("--out", help="result JSON path (default: under <git-dir>/ccl-code-review/)")
    args = ap.parse_args(argv)
    # An argument cut mid-character arrives with surrogate escapes, which cannot
    # be sent to a reviewer; replace the broken bytes instead of crashing.
    args.intent, args.focus = (s.encode("utf-8", "surrogateescape").decode("utf-8", "replace")
                               for s in (args.intent, args.focus))
    return args


def on_signal(signum, frame):
    raise clients.Interrupted()


def main(argv=None) -> int:
    args = parse_args(argv)
    progress = Progress(args.mode)
    try:
        candidate = Candidate.bind(args.cwd, args.base)
    except subprocess.CalledProcessError as exc:
        err = exc.stderr.decode("utf-8", "replace") if isinstance(exc.stderr, bytes) else exc.stderr or ""
        lines = err.strip().splitlines()
        # git's own verdict, not a trailing note such as "Stopping at filesystem boundary".
        fatal = [line for line in lines if line.startswith(("fatal:", "error:"))]
        shown = fatal[0] if fatal else lines[-1] if lines else f"git exited {exc.returncode}"
        progress.say(f"not run: {shown}")
        progress.say("next: check that --cwd is inside a git repository and --base names a commit in it",
                     detail=True)
        return 2
    diff_dir = clients.scratch_dir("diff-")
    try:
        diff_file = os.path.join(diff_dir, "change.diff")
        files = candidate.save_diff(diff_file)
        started = time.time()
        implementer = clients.canonical_family(args.implementer_family)
        reviewers, skipped = clients.select_reviewers(args.client_order, implementer)
        reason = None if implementer in clients.KNOWN_FAMILIES else "implementer_family_ambiguous"
        prompt = build_prompt(args.mode, candidate, args.intent, args.focus, diff_file)
        progress.started(candidate, files)
        progress.skipped(skipped)
        handlers = {sig: signal.signal(sig, on_signal) for sig in (signal.SIGINT, signal.SIGTERM)}
        try:
            review = run_attempts(reviewers, prompt, candidate, diff_dir, args.timeout, reason, progress)
        finally:
            for sig, handler in handlers.items():
                signal.signal(sig, handler)
    finally:
        shutil.rmtree(diff_dir, ignore_errors=True)

    if review.status and candidate.changed():
        review.status, review.findings, review.reason = None, [], "candidate_changed"
    try:
        result = record(args, candidate, review, implementer, skipped, started)
    except OSError as exc:
        progress.say(f"not recorded: {exc}")
        progress.say("next: check that the --out directory and the repository's git dir are writable, then rerun",
                     detail=True)
        return 2
    emit(result)
    progress.summary(result)
    return {"passed": 0, "findings": 1}.get(result["status"], 2)


def entry() -> int:
    """main() under one rule: exit 1 means recorded findings and nothing else."""
    if clients is None:
        to_stderr(f"review_diff: cannot load review_diff_clients.py next to {Path(__file__).name}: {CLIENTS_ERROR}")
        to_stderr("  next: reinstall the code-review skill so both files are present, then rerun")
        return 2
    try:
        return main()
    except KeyboardInterrupt:
        to_stderr("review_diff: interrupted; nothing was recorded")
        return 2
    except Exception:  # an unexpected error is never a verdict
        to_stderr(traceback.format_exc().rstrip())
        to_stderr("review_diff: internal error, not a verdict")
        return 2


if __name__ == "__main__":
    sys.exit(entry())
