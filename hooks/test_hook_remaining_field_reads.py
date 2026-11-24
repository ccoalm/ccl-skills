#!/usr/bin/env python3
"""Differential, stall, RSS, and jq-count suite for the remaining five multi-jq hooks.

Five shipped hooks read stdin JSON payloads (and local JSON state) with jq:

- ``hooks/skill-extraction-gate-stop.sh``;
- ``hooks/remind-review-covers-head.sh``;
- ``hooks/remind-post-merge-cleanup.sh``;
- ``hooks/merge-authorization-prompt.sh``;
- ``hooks/remind-unverified-cli-flag.sh``.

Unlike ``test_hook_field_reads.py`` (which compares against a static multi-OS
hash file), this suite executes both the reference implementation (extracted
from pinned baseline ``788470c`` when available in local git history, or a
per-field-fallback copy on shallow clones unless ``REQUIRE_BASELINE=1``) and
the working-tree candidate live on the current host, asserting byte-for-byte
agreement on ``(rc, stdout, stderr, filesystem state)``, ``<5s`` stall bounds,
``exported-fields`` / env-poisoning immunity, ``PWNED`` non-execution,
``SECRETMARK`` stderr hygiene, 800k-NUL ``RUSAGE_CHILDREN`` peak-RSS bounds,
and exact ``jq`` process-spawn reductions.
"""
from __future__ import annotations

import concurrent.futures
import json
import os
from pathlib import Path
import re
import shutil
import signal
import stat
import subprocess
import sys
import tempfile

sys.dont_write_bytecode = True

REPO = Path(__file__).resolve().parents[1]
BASELINE = "788470c"
BASELINE_COMMIT = "788470c31d70de3c11ef1a5e2df9c95a57916b94"

EXTRACTION_STOP = "hooks/skill-extraction-gate-stop.sh"
REVIEW_COVERS = "hooks/remind-review-covers-head.sh"
POST_MERGE = "hooks/remind-post-merge-cleanup.sh"
MERGE_PROMPT = "hooks/merge-authorization-prompt.sh"
CLI_FLAG = "hooks/remind-unverified-cli-flag.sh"

TARGET_HOOKS = (
    EXTRACTION_STOP,
    REVIEW_COVERS,
    POST_MERGE,
    MERGE_PROMPT,
    CLI_FLAG,
)

# Exact jq processes eliminated per counted scenario relative to 788470c.
JQ_SAVED = {
    "extraction-stop-blocked": 3,
    "extraction-stop-nosession-blocked": 4,
    "extraction-stop-invoked": 3,
    "extraction-stop-nosession-active": 1,
    "review-covers-head-passed": 5,
    "review-covers-head-remind": 5,
    "post-merge-cleanup-remind": 3,
    "merge-prompt-arm": 1,
    "merge-prompt-target-goal": 2,
    "unverified-cli-flag-remind": 1,
}

STALL_SECONDS = 5
BASH_DIAGNOSTIC_LINE = re.compile(r"(\.sh): line [0-9]+: (?:/[^:\s]*/)?")
EPOCH_TOKEN_RE = re.compile(r"\.epoch\.[A-Za-z0-9_.-]+")
SECRET = "SECRETMARK"
MISSING = object()

GIT_ENV = {
    "GIT_AUTHOR_NAME": "t",
    "GIT_AUTHOR_EMAIL": "t@example.invalid",
    "GIT_COMMITTER_NAME": "t",
    "GIT_COMMITTER_EMAIL": "t@example.invalid",
    "GIT_AUTHOR_DATE": "2026-01-01T00:00:00Z",
    "GIT_COMMITTER_DATE": "2026-01-01T00:00:00Z",
    "GIT_CONFIG_NOSYSTEM": "1",
    "GIT_CONFIG_GLOBAL": os.devnull,
}


def jtext(value):
    if isinstance(value, dict):
        return "{" + ",".join(
            json.dumps(k) + ":" + jtext(v) for k, v in value.items() if v is not MISSING
        ) + "}"
    if isinstance(value, list):
        return "[" + ",".join(jtext(v) for v in value) + "]"
    return json.dumps(value)


def variants(base: str):
    pwn = "$(touch PWNED)`touch PWNED`"
    return [
        ("base", base),
        ("absent", MISSING),
        ("null", None),
        ("false", False),
        ("true", True),
        ("int", 7),
        ("float", 1.5),
        ("array", [base, "x; touch PWNED"]),
        ("object", {"k": base}),
        ("empty", ""),
        ("nul-mid", base[:2] + "\0" + base[2:] if len(base) >= 2 else "a\0b"),
        ("nul-only", "\0"),
        ("nul-tail", base + "\0"),
        ("nl-tail", base + "\n\n"),
        ("nl-16", base + "\n" * 16),
        ("nl-17", base + "\n" * 17),
        ("nl-mid", base[:2] + "\n" + base[2:] if len(base) >= 2 else "a\nb"),
        ("nl-lead", "\n" + base),
        ("nl-nul-tail", base + "\n\0\n"),
        ("quotes", base + "'\"\\ " + pwn + " " + SECRET),
        ("unicode", base + "é提交"),
        ("base64-specials", base + "???~~~"),
    ]


def whole_payloads(base_text: str):
    return [
        ("empty-input", ""),
        ("garbage", "not json " + SECRET),
        ("truncated", base_text[:-3]),
        ("two-docs", base_text + base_text),
        ("trailing-garbage", base_text + " x"),
        ("array", "[]"),
        ("string", '"' + SECRET + '"'),
        ("null", "null"),
    ]


def utf8_locale() -> str:
    listed = subprocess.run(["locale", "-a"], capture_output=True, text=True).stdout.split()
    norm = {name.lower().replace("-", ""): name for name in listed}
    for want in ("C.UTF-8", "en_US.UTF-8"):
        if want.lower().replace("-", "") in norm:
            return norm[want.lower().replace("-", "")]
    raise SystemExit("FAIL: no C.UTF-8 or en_US.UTF-8 locale; stall cases require UTF-8")


def git_env(home: str | None = None) -> dict[str, str]:
    env = {k: v for k, v in os.environ.items() if not k.startswith("GIT_")}
    env["GIT_NO_REPLACE_OBJECTS"] = "1"
    if home:
        env.update(GIT_ENV, HOME=home, XDG_CONFIG_HOME=os.path.join(home, ".config"))
    return env


def has_baseline_commit() -> bool:
    proc = subprocess.run(
        ["git", "-c", f"safe.directory={REPO}", "-C", str(REPO), "cat-file", "-e", f"{BASELINE_COMMIT}^{{commit}}"],
        env=git_env(),
        capture_output=True,
    )
    return proc.returncode == 0


def put(obj, path, value):
    copied = json.loads(json.dumps(obj))
    cur = copied
    for key in path[:-1]:
        cur = cur.setdefault(key, {})
    cur[path[-1]] = value
    return copied


def dig(obj, path):
    for key in path:
        obj = obj[key]
    return obj


def field_cases(name: str, base: dict, fields: list[tuple[str, ...]]):
    cases = []
    for path in fields:
        for label, value in variants(str(dig(base, path))):
            cases.append((f"{name}/{'.'.join(path)}/{label}", jtext(put(base, path, value))))
    for label, text in whole_payloads(jtext(base)):
        cases.append((f"{name}/whole/{label}", text))
    return cases


class Sandbox:
    def __init__(self, mode: str, locale_name: str):
        self.mode = mode
        self.root = os.path.realpath(tempfile.mkdtemp(prefix=f"hook-rem-reads-{mode}."))
        self.plugin = os.path.join(self.root, "plugin")
        self.uid = str(os.getuid())
        self.locale = locale_name
        for rel in ("tmp", "home", "shim", "git-home/.config"):
            os.makedirs(os.path.join(self.root, rel), exist_ok=True)
        self._install(mode)
        self._fixtures()

    def _install(self, mode: str) -> None:
        os.makedirs(self.plugin, exist_ok=True)
        shutil.copytree(
            REPO / "hooks",
            os.path.join(self.plugin, "hooks"),
            ignore=shutil.ignore_patterns("__pycache__"),
        )
        if mode == "baseline":
            archive = subprocess.run(
                ["git", "-c", f"safe.directory={REPO}", "-C", str(REPO), "archive", BASELINE_COMMIT, *TARGET_HOOKS],
                check=True,
                capture_output=True,
                env=git_env(),
            ).stdout
            subprocess.run(["tar", "-x", "-C", self.plugin], input=archive, check=True)
        elif mode == "fallback":
            # Bypass merged jq calls completely so every hook executes only its per-field jq fallback.
            for rel in TARGET_HOOKS:
                target = Path(self.plugin) / rel
                text = target.read_text(encoding="utf-8")
                text = text.replace("\nfields=$(", '\nfields=""; false && fields=$(')
                text = text.replace("\nsummary_fields=$(", '\nsummary_fields=""; false && summary_fields=$(')
                text = text.replace("\n  receipt_fields=$(", '\n  receipt_fields=""; false && receipt_fields=$(')
                target.write_text(text, encoding="utf-8")

    def git(self, *args: str, cwd: str | None = None) -> str:
        proc = subprocess.run(
            ["git", *args],
            cwd=cwd,
            env=git_env(os.path.join(self.root, "git-home")),
            check=True,
            capture_output=True,
            text=True,
        )
        return proc.stdout.strip()

    def _fixtures(self) -> None:
        # 1. Fake ccl-skills checkout + transcripts for skill-extraction-gate-stop.sh
        self.ccl_repo = os.path.join(self.root, "ccl-checkout")
        for slug in ("skill-extraction-workflow", "sample-skill"):
            sdir = os.path.join(self.ccl_repo, "skills", slug)
            os.makedirs(sdir, exist_ok=True)
            with open(os.path.join(sdir, "SKILL.md"), "w", encoding="utf-8") as fh:
                fh.write(f"---\nname: {slug}\n---\nbody\n")
        self.tx_uninvoked = os.path.join(self.root, "tx-uninvoked.jsonl")
        edit_target = os.path.join(self.ccl_repo, "skills/sample-skill/SKILL.md")
        uninvoked_events = [
            {"type": "user", "message": {"role": "user", "content": "edit skill"}},
            {
                "type": "assistant",
                "message": {
                    "role": "assistant",
                    "content": [{"type": "tool_use", "id": "e1", "name": "Edit", "input": {"file_path": edit_target}}],
                },
            },
            {"type": "user", "message": {"role": "user", "content": [{"type": "tool_result", "tool_use_id": "e1", "content": "ok"}]}},
        ]
        with open(self.tx_uninvoked, "w", encoding="utf-8") as fh:
            for ev in uninvoked_events:
                fh.write(json.dumps(ev) + "\n")

        self.tx_invoked = os.path.join(self.root, "tx-invoked.jsonl")
        invoked_events = [
            *uninvoked_events,
            {
                "type": "assistant",
                "message": {
                    "role": "assistant",
                    "content": [
                        {
                            "type": "tool_use",
                            "id": "sk1",
                            "name": "Skill",
                            "input": {"skill": "ccl-skills:skill-extraction-workflow"},
                        }
                    ],
                },
            },
            {"type": "user", "message": {"role": "user", "content": [{"type": "tool_result", "tool_use_id": "sk1", "content": "loaded"}]}},
        ]
        with open(self.tx_invoked, "w", encoding="utf-8") as fh:
            for ev in invoked_events:
                fh.write(json.dumps(ev) + "\n")

        # 2. Git repo + linked worktree + receipt path for review-covers-head, post-merge-cleanup, merge-prompt
        self.repo = os.path.join(self.root, "repo")
        os.makedirs(self.repo)
        self.git("init", "-q", "-b", "main", cwd=self.repo)
        self.git("remote", "add", "origin", "https://github.com/acme/demo.git", cwd=self.repo)
        with open(os.path.join(self.repo, "file.txt"), "w", encoding="utf-8") as fh:
            fh.write("v1\n")
        self.git("add", "file.txt", cwd=self.repo)
        self.git("commit", "-q", "-m", "c1", cwd=self.repo)
        self.c1 = self.git("rev-parse", "HEAD", cwd=self.repo)
        self.git("update-ref", "refs/remotes/origin/main", self.c1, cwd=self.repo)
        self.git("symbolic-ref", "refs/remotes/origin/HEAD", "refs/remotes/origin/main", cwd=self.repo)
        with open(os.path.join(self.repo, "file.txt"), "w", encoding="utf-8") as fh:
            fh.write("v2\n")
        self.git("add", "file.txt", cwd=self.repo)
        self.git("commit", "-q", "-m", "c2", cwd=self.repo)
        self.c2 = self.git("rev-parse", "HEAD", cwd=self.repo)
        self.feat_wt = os.path.join(self.root, "repo-feat")
        self.git("worktree", "add", "-q", "-b", "feat", self.feat_wt, self.c1, cwd=self.repo)

        git_dir = self.git("rev-parse", "--absolute-git-dir", cwd=self.repo)
        self.receipt_dir = os.path.join(git_dir, "ccl-code-review")
        os.makedirs(self.receipt_dir, exist_ok=True)
        self.receipt_path = os.path.join(self.receipt_dir, "last-review.json")

        self.auth_dir = os.path.join(self.root, "tmp", f"ccl-skills-merge-auth-{self.uid}")
        shim = os.path.join(self.root, "shim", "jq")
        with open(shim, "w", encoding="utf-8") as fh:
            fh.write(f'#!/bin/sh\necho x >> "$JQ_COUNT_FILE"\nexec "{shutil.which("jq")}" "$@"\n')
        os.chmod(shim, stat.S_IRWXU)

    def write_receipt(self, text: str | None) -> None:
        if text is None:
            if os.path.lexists(self.receipt_path):
                os.unlink(self.receipt_path)
            return
        os.makedirs(self.receipt_dir, exist_ok=True)
        with open(self.receipt_path, "w", encoding="utf-8", errors="surrogatepass") as fh:
            fh.write(text.replace("<C1>", self.c1).replace("<C2>", self.c2))

    def env(self, extra: dict[str, str] | None = None) -> dict[str, str]:
        env = {
            "PATH": os.environ["PATH"],
            "HOME": os.path.join(self.root, "home"),
            "TMPDIR": os.path.join(self.root, "tmp"),
            "LC_ALL": self.locale,
        }
        if extra:
            env.update(extra)
        return env

    def norm(self, data: bytes) -> str:
        text = data.decode("utf-8", "backslashreplace")
        for spelling in (
            json.dumps(self.root)[1:-1],
            json.dumps(self.root, ensure_ascii=False)[1:-1],
            self.root,
        ):
            text = text.replace(spelling, "<T>")
        text = text.replace(self.c2, "<C2>").replace(self.c1, "<C1>")
        text = text.replace(self.c2[:12], "<C2_SHORT>").replace(self.c1[:12], "<C1_SHORT>")
        text = text.replace(f"merge-auth-{self.uid}", "merge-auth-<UID>")
        return EPOCH_TOKEN_RE.sub(".epoch.<EPOCH>", text)

    def run(self, script: str, payload: str, cwd: str | None = None, extra_env: dict[str, str] | None = None, timeout: int = 30) -> dict:
        expanded = (
            payload.replace("<T>", json.dumps(self.root)[1:-1])
            .replace("<C1>", self.c1)
            .replace("<C2>", self.c2)
        )
        proc = subprocess.Popen(
            ["bash", os.path.join(self.plugin, script)],
            stdin=subprocess.PIPE,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            cwd=cwd or self.root,
            env=self.env(extra_env),
            start_new_session=True,
        )
        try:
            out, err = proc.communicate(expanded.encode("utf-8", "surrogatepass"), timeout=timeout)
        except subprocess.TimeoutExpired:
            os.killpg(proc.pid, signal.SIGKILL)
            proc.communicate()
            return {"rc": f"timeout after {timeout}s", "stdout": "", "stderr": ""}
        return {
            "rc": proc.returncode,
            "stdout": self.norm(out),
            "stderr": BASH_DIAGNOSTIC_LINE.sub(r"\1: line <N>: ", self.norm(err)),
        }

    def tmp_markers(self) -> dict[str, str]:
        tmp_dir = os.path.join(self.root, "tmp")
        out = {}
        for name in sorted(os.listdir(tmp_dir)):
            full = os.path.join(tmp_dir, name)
            if name.startswith("skill-extraction-gate-") and os.path.isfile(full):
                with open(full, "rb") as fh:
                    out[name] = self.norm(fh.read())
            elif name == "ccl-skills-cliflag" and os.path.isdir(full):
                for sub in sorted(os.listdir(full)):
                    sfull = os.path.join(full, sub)
                    if os.path.isfile(sfull):
                        with open(sfull, "rb") as fh:
                            out[f"cliflag/{sub}"] = self.norm(fh.read())
        return out

    def grants_state(self) -> dict[str, object]:
        if not os.path.isdir(self.auth_dir):
            return {}
        raw: dict[str, str] = {}
        for name in sorted(os.listdir(self.auth_dir)):
            full = os.path.join(self.auth_dir, name)
            if os.path.isfile(full):
                with open(full, "rb") as fh:
                    raw[name] = fh.read().decode("utf-8", "backslashreplace")
        normalized: dict[str, object] = {}
        for name, val in raw.items():
            if name.endswith((".epoch", ".grant-epoch")):
                base = name.rsplit(".", 1)[0]
                normalized[f"{base}:epochs_match"] = (
                    raw.get(f"{base}.epoch") == raw.get(f"{base}.grant-epoch")
                    and bool(raw.get(f"{base}.epoch"))
                )
                normalized[f"{name}:present"] = bool(val.strip())
            else:
                normalized[name] = self.norm(val.encode("utf-8", "backslashreplace"))
        return normalized

    def check_not_executed(self) -> None:
        for top, _dirs, files in os.walk(self.root):
            if "PWNED" in files:
                raise AssertionError(f"payload text was executed: {top}/PWNED exists")

    def reset(self) -> None:
        self.check_not_executed()
        tmp_dir = os.path.join(self.root, "tmp")
        shutil.rmtree(tmp_dir, ignore_errors=True)
        os.makedirs(tmp_dir, mode=0o700, exist_ok=True)
        self.write_receipt(None)

    def close(self) -> None:
        shutil.rmtree(self.root, ignore_errors=True)


def group_extraction_stop(sb: Sandbox, record) -> None:
    base = {
        "session_id": "S-ext",
        "stop_hook_active": False,
        "transcript_path": "<T>/tx-uninvoked.jsonl",
        "cwd": "<T>/ccl-checkout",
    }
    for case_id, payload in field_cases(
        "extraction-stop",
        base,
        [("session_id",), ("stop_hook_active",), ("transcript_path",), ("cwd",)],
    ):
        sb.reset()
        res = sb.run(EXTRACTION_STOP, payload, cwd=sb.ccl_repo)
        res["again"] = sb.run(EXTRACTION_STOP, payload, cwd=sb.ccl_repo)
        res["markers"] = sb.tmp_markers()
        record(case_id, res)

    # No-session branch where stop_hook_active governs loop prevention.
    for label, val in variants("true") + [("bool-true", True), ("bool-false", False), ("str-false", "false")]:
        sb.reset()
        obj = {"transcript_path": "<T>/tx-uninvoked.jsonl", "cwd": "<T>/ccl-checkout"}
        if val is not MISSING:
            obj["stop_hook_active"] = val
        res = sb.run(EXTRACTION_STOP, jtext(obj), cwd=sb.ccl_repo)
        res["markers"] = sb.tmp_markers()
        record(f"extraction-stop/nosession-active/{label}", res)

    # Invoked transcript allows cleanly.
    sb.reset()
    inv_payload = jtext(dict(base, transcript_path="<T>/tx-invoked.jsonl"))
    res = sb.run(EXTRACTION_STOP, inv_payload, cwd=sb.ccl_repo)
    res["markers"] = sb.tmp_markers()
    record("extraction-stop/scenario/invoked", res)


def group_review_covers_head(sb: Sandbox, record) -> None:
    base_input = {"tool_input": {"command": "gh pr create --fill"}, "cwd": "<T>/repo"}
    receipt_base = {
        "head": "<C1>",
        "worktree_clean": True,
        "mode": "challenge",
        "status": "passed",
        "recorded_at": "2026-11-23T00:00:00Z",
    }
    for case_id, payload in field_cases("review-input", base_input, [("tool_input", "command"), ("cwd",)]):
        sb.reset()
        sb.write_receipt(jtext(receipt_base))
        record(case_id, sb.run(REVIEW_COVERS, payload, cwd=sb.repo))

    for case_id, receipt_text in field_cases(
        "review-receipt",
        receipt_base,
        [("head",), ("worktree_clean",), ("mode",), ("status",), ("recorded_at",)],
    ):
        sb.reset()
        sb.write_receipt(receipt_text)
        record(case_id, sb.run(REVIEW_COVERS, jtext(base_input), cwd=sb.repo))

    for s_label, r_obj in (
        ("no-receipt", None),
        ("covered-passed", dict(receipt_base, head="<C2>", status="passed")),
        ("covered-findings", dict(receipt_base, head="<C2>", status="findings")),
        ("covered-dirty", dict(receipt_base, head="<C2>", worktree_clean=False, status="passed")),
    ):
        sb.reset()
        sb.write_receipt(None if r_obj is None else jtext(r_obj))
        record(f"review-scenario/{s_label}", sb.run(REVIEW_COVERS, jtext(base_input), cwd=sb.repo))


def group_post_merge_cleanup(sb: Sandbox, record) -> None:
    base = {
        "tool_input": {"command": "gh pr merge 42 --squash"},
        "tool_response": "Merged pull request #42",
        "cwd": "<T>/repo",
    }
    for case_id, payload in field_cases(
        "post-merge",
        base,
        [("tool_input", "command"), ("tool_response",), ("cwd",)],
    ):
        sb.reset()
        record(case_id, sb.run(POST_MERGE, payload, cwd=sb.repo))

    for label, resp_obj in (
        ("obj-ok", {"exit_code": 0, "is_error": False, "output": "Merged #42"}),
        ("obj-nonzero", {"exit_code": 1, "is_error": False, "output": "Merged #42"}),
        ("obj-str-zero", {"exitCode": "0", "output": "Merged #42"}),
        ("obj-str-neg", {"returncode": "-1", "output": "Merged #42"}),
        ("obj-is-error", {"exit_code": 0, "is_error": True, "output": "Merged #42"}),
        ("obj-interrupted", {"interrupted": True, "output": "Merged #42"}),
        ("obj-queued", {"exit_code": 0, "output": "will be automatically merged when pipeline succeeds"}),
        ("obj-conflict", {"exit_code": 0, "output": "CONFLICT: cannot be merged"}),
        ("obj-quotes", {"exit_code": 0, "output": "ok '\" $(touch PWNED) " + SECRET}),
    ):
        sb.reset()
        record(
            f"post-merge/resp-obj/{label}",
            sb.run(POST_MERGE, jtext(dict(base, tool_response=resp_obj)), cwd=sb.repo),
        )


def group_merge_prompt(sb: Sandbox, record) -> None:
    base = {"prompt": "merge #42", "session_id": "S-merge", "cwd": "<T>/repo"}
    for case_id, payload in field_cases("merge-prompt", base, [("prompt",), ("session_id",), ("cwd",)]):
        sb.reset()
        res = sb.run(MERGE_PROMPT, payload, cwd=sb.repo)
        res["grants"] = sb.grants_state()
        record(case_id, res)

    # Multi-step target-goal lifecycle: arm -> neutral -> suspend -> revoke, plus batch arm.
    sb.reset()
    seq = []
    for step_prompt in ("完成并合并 PR #42", "continue", "check status details", "取消合并", "批量合并 3"):
        step_res = sb.run(
            MERGE_PROMPT,
            jtext({"prompt": step_prompt, "session_id": "S-goal", "cwd": "<T>/repo"}),
            cwd=sb.repo,
        )
        step_res["grants"] = sb.grants_state()
        seq.append(step_res)
    record("merge-prompt/scenario/lifecycle", {"steps": seq})


def group_unverified_cli_flag(sb: Sandbox, record) -> None:
    base = {"tool_input": {"command": "glab mr list --state opened"}, "session_id": "S-cli"}
    for case_id, payload in field_cases("cli-flag", base, [("tool_input", "command"), ("session_id",)]):
        sb.reset()
        res = sb.run(CLI_FLAG, payload, cwd=sb.repo)
        res["second"] = sb.run(CLI_FLAG, payload, cwd=sb.repo)
        res["markers"] = sb.tmp_markers()
        record(case_id, res)

    sb.reset()
    compound = jtext({"tool_input": {"command": "glab mr list --state opened && gh pr list --state open"}, "session_id": "S-two"})
    r1 = sb.run(CLI_FLAG, compound, cwd=sb.repo)
    r2 = sb.run(CLI_FLAG, compound, cwd=sb.repo)
    r3 = sb.run(CLI_FLAG, compound, cwd=sb.repo)
    record("cli-flag/scenario/compound-dedup", {"r1": r1, "r2": r2, "r3": r3, "markers": sb.tmp_markers()})


def group_stall_and_env(sb: Sandbox, record) -> None:
    for label, suffix, capped_suffix in (
        ("newlines", "\n" * 200000, "\n" * 200000),
        ("newlines-in-bound", "\n" * 60000, "\n" * 60000),
        ("nuls", "\0" * 800000, "\0" * 100000),
        ("apostrophes", "'" * 900000, "'" * 900000),
    ):
        runs = {
            "extraction-stop": (
                EXTRACTION_STOP,
                {
                    "session_id": "S-stall",
                    "transcript_path": "<T>/tx-uninvoked.jsonl",
                    "cwd": "<T>/ccl-checkout" + suffix,
                },
                sb.ccl_repo,
            ),
            "review-covers": (
                REVIEW_COVERS,
                {"tool_input": {"command": "gh pr create --fill" + suffix}, "cwd": "<T>/repo"},
                sb.repo,
            ),
            "post-merge": (
                POST_MERGE,
                {
                    "tool_input": {"command": "gh pr merge 42 --squash" + suffix},
                    "tool_response": "Merged #42",
                    "cwd": "<T>/repo",
                },
                sb.repo,
            ),
            "merge-prompt": (
                MERGE_PROMPT,
                {"prompt": "merge #42" + suffix, "session_id": "S-mp", "cwd": "<T>/repo"},
                sb.repo,
            ),
            "cli-flag": (
                CLI_FLAG,
                {"tool_input": {"command": "glab mr list --state opened" + capped_suffix}, "session_id": "S-cf"},
                sb.repo,
            ),
        }
        for name, (script, payload, cwd) in runs.items():
            sb.reset()
            if name == "review-covers":
                sb.write_receipt(jtext({"head": "<C1>", "worktree_clean": True, "mode": "review", "status": "passed", "recorded_at": "t"}))
            res = sb.run(script, jtext(payload), cwd=cwd, timeout=STALL_SECONDS)
            res["markers"] = sb.tmp_markers()
            res["grants"] = sb.grants_state()
            record(f"stall/{name}/{label}", res)

    quoted = "'" * 40000
    poison_env = {
        "fields": "inherited",
        "fields_read": "1",
        "receipt_fields": "inherited",
        "receipt_read": "1",
        "hf_cmd": "touch PWNED",
        "hf_prompt": "merge",
        "hf_sid": "S-poison",
        "hf_session": "S-poison",
    }
    env_runs = {
        "extraction-stop": (
            EXTRACTION_STOP,
            {"session_id": "S-env", "transcript_path": "<T>/tx-uninvoked.jsonl", "cwd": "<T>/ccl-checkout " + quoted},
            sb.ccl_repo,
        ),
        "review-covers": (
            REVIEW_COVERS,
            {"tool_input": {"command": "gh pr create --fill " + quoted}, "cwd": "<T>/repo"},
            sb.repo,
        ),
        "post-merge": (
            POST_MERGE,
            {"tool_input": {"command": "gh pr merge 42 --squash " + quoted}, "tool_response": "Merged #42", "cwd": "<T>/repo"},
            sb.repo,
        ),
        "merge-prompt": (
            MERGE_PROMPT,
            {"prompt": "status " + quoted, "session_id": "S-env", "cwd": "<T>/repo"},
            sb.repo,
        ),
        "cli-flag": (
            CLI_FLAG,
            {"tool_input": {"command": "glab mr list --state opened " + quoted}, "session_id": "S-env"},
            sb.repo,
        ),
    }
    for name, (script, payload, cwd) in env_runs.items():
        sb.reset()
        if name == "review-covers":
            sb.write_receipt(jtext({"head": "<C1>", "worktree_clean": True, "mode": "review", "status": "passed", "recorded_at": "t"}))
        res = sb.run(script, jtext(payload), cwd=cwd, extra_env=poison_env, timeout=STALL_SECONDS)
        res["markers"] = sb.tmp_markers()
        res["grants"] = sb.grants_state()
        record(f"exported-fields/{name}", res)


GROUPS = (
    group_extraction_stop,
    group_review_covers_head,
    group_post_merge_cleanup,
    group_merge_prompt,
    group_unverified_cli_flag,
    group_stall_and_env,
)


def count_jq(sb: Sandbox) -> dict[str, int]:
    runs = {
        "extraction-stop-blocked": (
            EXTRACTION_STOP,
            {"session_id": "S-cnt", "stop_hook_active": False, "transcript_path": "<T>/tx-uninvoked.jsonl", "cwd": "<T>/ccl-checkout"},
            sb.ccl_repo,
            None,
        ),
        "extraction-stop-nosession-blocked": (
            EXTRACTION_STOP,
            {"stop_hook_active": False, "transcript_path": "<T>/tx-uninvoked.jsonl", "cwd": "<T>/ccl-checkout"},
            sb.ccl_repo,
            None,
        ),
        "extraction-stop-invoked": (
            EXTRACTION_STOP,
            {"session_id": "S-cnt2", "stop_hook_active": False, "transcript_path": "<T>/tx-invoked.jsonl", "cwd": "<T>/ccl-checkout"},
            sb.ccl_repo,
            None,
        ),
        "extraction-stop-nosession-active": (
            EXTRACTION_STOP,
            {"stop_hook_active": True, "transcript_path": "<T>/tx-uninvoked.jsonl", "cwd": "<T>/ccl-checkout"},
            sb.ccl_repo,
            None,
        ),
        "review-covers-head-passed": (
            REVIEW_COVERS,
            {"tool_input": {"command": "gh pr create --fill"}, "cwd": "<T>/repo"},
            sb.repo,
            {"head": "<C2>", "worktree_clean": True, "mode": "challenge", "status": "passed", "recorded_at": "2026-11-23T00:00:00Z"},
        ),
        "review-covers-head-remind": (
            REVIEW_COVERS,
            {"tool_input": {"command": "gh pr create --fill"}, "cwd": "<T>/repo"},
            sb.repo,
            {"head": "<C1>", "worktree_clean": True, "mode": "review", "status": "passed", "recorded_at": "2026-11-23T00:00:00Z"},
        ),
        "post-merge-cleanup-remind": (
            POST_MERGE,
            {"tool_input": {"command": "gh pr merge 42 --squash"}, "tool_response": {"exit_code": 0, "output": "Merged #42"}, "cwd": "<T>/repo"},
            sb.repo,
            None,
        ),
        "merge-prompt-arm": (
            MERGE_PROMPT,
            {"prompt": "merge #42", "session_id": "S-cnt", "cwd": "<T>/repo"},
            sb.repo,
            None,
        ),
        "merge-prompt-target-goal": (
            MERGE_PROMPT,
            {"prompt": "完成并合并 PR #42", "session_id": "S-goal", "cwd": "<T>/repo"},
            sb.repo,
            None,
        ),
        "unverified-cli-flag-remind": (
            CLI_FLAG,
            {"tool_input": {"command": "glab mr list --state opened"}, "session_id": "S-cnt"},
            sb.repo,
            None,
        ),
    }
    counts: dict[str, int] = {}
    for name, (script, payload, cwd, receipt_obj) in runs.items():
        sb.reset()
        if receipt_obj is not None:
            sb.write_receipt(jtext(receipt_obj))
        count_file = os.path.join(sb.root, "jq-count")
        open(count_file, "w", encoding="utf-8").close()
        extra = {
            "PATH": os.path.join(sb.root, "shim") + os.pathsep + os.environ["PATH"],
            "JQ_COUNT_FILE": count_file,
        }
        res = sb.run(script, jtext(payload), cwd=cwd, extra_env=extra)
        with open(count_file, encoding="utf-8") as fh:
            counts[name] = len(fh.read().splitlines())
        if res["rc"] != 0 or counts[name] < 1:
            raise AssertionError(f"jq count run for {name} failed: {res}, {counts[name]} jq processes")
    return counts


PEAK_PROBE = """import resource, subprocess, sys
with open(sys.argv[1], 'rb') as fh:
    subprocess.run(sys.argv[2:], stdin=fh, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
r = resource.getrusage(resource.RUSAGE_CHILDREN).ru_maxrss
print(r if sys.platform == 'darwin' else r * 1024)
"""


def peak_ratios(sb: Sandbox) -> dict[str, float]:
    payloads = {
        "post-merge": (
            POST_MERGE,
            {"tool_input": {"command": "gh pr merge 42 --squash"}, "tool_response": "ok" + "\0" * 800000, "cwd": "<T>/repo"},
            ".tool_response",
        ),
        "merge-prompt": (
            MERGE_PROMPT,
            {"prompt": "merge #42" + "\0" * 800000, "session_id": "S-rss", "cwd": "<T>/repo"},
            ".prompt",
        ),
    }
    ratios: dict[str, float] = {}
    for name, (script, payload, jq_expr) in payloads.items():
        sb.reset()
        path = os.path.join(sb.root, "peak.json")
        with open(path, "w", encoding="utf-8", errors="surrogatepass") as fh:
            fh.write(jtext(payload).replace("<T>", json.dumps(sb.root)[1:-1]))

        def peak(*cmd: str) -> int:
            out = subprocess.run(
                [sys.executable, "-c", PEAK_PROBE, path, *cmd],
                cwd=sb.root,
                env=sb.env(),
                capture_output=True,
                text=True,
                timeout=60,
                check=True,
            )
            return int(out.stdout.strip())

        ratios[name] = round(peak("bash", os.path.join(sb.plugin, script)) / peak("jq", "-r", jq_expr), 2)
    return ratios


def walk_runs(result: dict):
    if "rc" in result:
        yield result
    for value in result.values():
        if isinstance(value, dict):
            yield from walk_runs(value)
        elif isinstance(value, list):
            for item in value:
                if isinstance(item, dict):
                    yield from walk_runs(item)


def run_unit(mode: str, group, locale_name: str):
    results: dict[str, dict] = {}

    def record(case_id: str, result: dict) -> None:
        if case_id in results:
            raise AssertionError(f"duplicate case id: {case_id}")
        results[case_id] = result

    sb = Sandbox(mode, locale_name)
    try:
        if group is None:
            return {}, {"jq_counts": count_jq(sb), "peak_ratios": peak_ratios(sb)}
        group(sb, record)
        sb.check_not_executed()
        return results, {}
    finally:
        sb.close()


def collect(mode: str, locale_name: str):
    results: dict[str, dict] = {}
    meta: dict[str, dict] = {}
    with concurrent.futures.ThreadPoolExecutor(max_workers=len(GROUPS) + 1) as pool:
        for part, part_meta in pool.map(lambda g: run_unit(mode, g, locale_name), (*GROUPS, None)):
            if set(part) & set(results):
                raise AssertionError("duplicate case ids across groups")
            results.update(part)
            meta.update(part_meta)
    return results, meta


def summary(obj: dict) -> str:
    text = json.dumps(obj, sort_keys=True, ensure_ascii=False)
    return text if len(text) <= 400 else text[:400] + "..."


def main() -> int:
    for tool in ("jq", "git", "python3"):
        if not shutil.which(tool):
            print(f"FAIL: {tool} is required", file=sys.stderr)
            return 1

    have_baseline = has_baseline_commit()
    if os.environ.get("REQUIRE_BASELINE") == "1" and not have_baseline:
        print(
            f"FAIL: REQUIRE_BASELINE=1 set, but baseline commit {BASELINE_COMMIT} is absent",
            file=sys.stderr,
        )
        return 1

    locale_name = utf8_locale()
    ref_mode = "baseline" if have_baseline else "fallback"
    ref_results, ref_meta = collect(ref_mode, locale_name)
    cand_results, cand_meta = collect("candidate", locale_name)

    failures: list[str] = []

    timed_out = sorted(
        k
        for k, v in cand_results.items()
        if any(str(r.get("rc", "")).startswith("timeout") for r in walk_runs(v))
    )
    if timed_out:
        failures.append(f"candidate timed out in: {timed_out[:5]}")

    if sorted(ref_results) != sorted(cand_results):
        failures.append(
            f"case set differs: missing={sorted(set(ref_results) - set(cand_results))[:5]}, "
            f"extra={sorted(set(cand_results) - set(ref_results))[:5]}"
        )

    for case_id in sorted(set(ref_results) & set(cand_results)):
        if cand_results[case_id] != ref_results[case_id]:
            failures.append(
                f"{case_id} differs from {ref_mode}:\n"
                f"  expected:  {summary(ref_results[case_id])}\n"
                f"  candidate: {summary(cand_results[case_id])}"
            )

    for case_id, result in sorted(cand_results.items()):
        if any(SECRET in r.get("stderr", "") for r in walk_runs(result)):
            failures.append(f"{case_id}: payload secret leaked to stderr")

    # Also verify that the fallback-forced copy matches 788470c on jq counts when 788470c is present,
    # proving shallow-clone fallback mode stays faithful to 788470c.
    if have_baseline:
        fb_sb = Sandbox("fallback", locale_name)
        try:
            fb_counts = count_jq(fb_sb)
        finally:
            fb_sb.close()
        if fb_counts != ref_meta["jq_counts"]:
            failures.append(
                f"shallow-clone fallback jq_counts drifted from {BASELINE}: "
                f"fallback={fb_counts} vs {BASELINE}={ref_meta['jq_counts']}"
            )

    for name, saved in sorted(JQ_SAVED.items()):
        base_cnt = ref_meta["jq_counts"][name]
        cand_cnt = cand_meta["jq_counts"][name]
        want = base_cnt - saved
        if cand_cnt != want:
            failures.append(
                f"{name} starts {cand_cnt} jq processes; expected {want} (reference {base_cnt}, saved {saved})"
            )

    for name, ratio in sorted(cand_meta["peak_ratios"].items()):
        base_ratio = ref_meta["peak_ratios"][name]
        limit = base_ratio * 1.25 + 0.15
        if ratio > limit:
            failures.append(
                f"{name} peaks at {ratio:.2f}x plain jq read; at most {limit:.2f}x allowed (reference {base_ratio:.2f}x)"
            )

    for failure in failures:
        print(f"FAIL: {failure}", file=sys.stderr)
    if failures:
        return 1

    print(
        f"ok: {len(cand_results)} remaining-hook differential cases match {ref_mode}, "
        f"jq counts {cand_meta['jq_counts']} (reference {ref_meta['jq_counts']})"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
