#!/usr/bin/env python3
"""Block AI-session and provenance metadata on candidate Git/PR surfaces."""

from __future__ import annotations

import argparse
import json
import os
import re
import selectors
import stat
import subprocess
import sys
import tempfile
import time
from dataclasses import dataclass
from pathlib import Path
from typing import NoReturn


MAX_EVENT_BYTES = 1_000_000
MAX_PR_TEXT_BYTES = 100_000
MAX_GIT_OUTPUT_BYTES = 8_000_000

# ``--repo`` is the one repository identity for this gate. Git otherwise lets
# ambient variables replace its refs, objects, ancestry, index, or worktree even
# when every command also supplies ``-C <repo>``. A clean decoy GIT_DIR can then
# certify a prohibited candidate from another repository. This gate is for a
# worktree pre-push/CI lane (not a receive-pack quarantine), so none of these
# routing overrides is a supported input.
GIT_REPOSITORY_ROUTING_ENV = (
    "GIT_DIR",
    "GIT_WORK_TREE",
    "GIT_IMPLICIT_WORK_TREE",
    "GIT_INDEX_FILE",
    "GIT_COMMON_DIR",
    "GIT_NAMESPACE",
    "GIT_OBJECT_DIRECTORY",
    "GIT_ALTERNATE_OBJECT_DIRECTORIES",
    "GIT_CEILING_DIRECTORIES",
    "GIT_DISCOVERY_ACROSS_FILESYSTEM",
    "GIT_GRAFT_FILE",
    "GIT_SHALLOW_FILE",
    "GIT_REPLACE_REF_BASE",
    "GIT_PREFIX",
    "GIT_INTERNAL_SUPER_PREFIX",
    "GIT_QUARANTINE_PATH",
)
GIT_CONFIG_ROUTING_ENV = (
    "GIT_CONFIG",
    "GIT_CONFIG_COUNT",
    "GIT_CONFIG_GLOBAL",
    "GIT_CONFIG_SYSTEM",
    "GIT_CONFIG_NOSYSTEM",
    "GIT_CONFIG_PARAMETERS",
)
GIT_CONFIG_ROUTING_ENV_PREFIXES = ("GIT_CONFIG_KEY_", "GIT_CONFIG_VALUE_")

# Keep provider aliases in one registry. Surface patterns may add their own
# grammar (URL hosts, attribution verbs, analysis labels), but must not carry a
# second, narrower provider-name list that silently drifts.
AI_PROVIDER_ALIASES = (
    r"claude(?:\s+code)?",
    r"codex",
    r"chatgpt",
    r"gpt",
    r"openai",
    r"kimi",
    r"opencode",
    r"gemini",
    r"(?:github\s+)?copilot(?:\s+swe\s+agent)?",
    r"cursor",
    r"grok",
    r"qwen",
    r"doubao",
    r"windsurf",
    r"perplexity",
    r"poe",
)
AI_PROVIDER = rf"(?:{'|'.join(AI_PROVIDER_ALIASES)})"
# GitHub App display names use slug separators. Derive that grammar from the
# one provider registry instead of maintaining a second alias list.
AI_PROVIDER_ACCOUNT_ALIASES = tuple(
    alias.replace(r"\s+", r"[-_ ]+") for alias in AI_PROVIDER_ALIASES
)
AI_PROVIDER_ACCOUNT = rf"(?:{'|'.join(AI_PROVIDER_ACCOUNT_ALIASES)})"
# These display names are not ordinary personal names. They remain a strong AI
# attribution signal even when a host or wrapper supplies a conventional email.
# A Co-Authored-By trailer may additionally use the bot-shaped email signal
# below; author/committer fields do not, because humans commonly use GitHub
# noreply privacy addresses.
AI_IDENTITY_QUALIFIER_TOKEN = (
    r"(?:v?[0-9][A-Za-z0-9.+-]*|code|codex|chatgpt|gpt|swe|agent|assistant|bot|cli|"
    r"reviewer|sonnet|opus|haiku|fable|mythos)"
)
AI_IDENTITY_QUALIFIER = rf"(?:[-_\s]+{AI_IDENTITY_QUALIFIER_TOKEN}){{0,3}}"
AI_IDENTITY_VERSION_INFIX = r"(?:[-_\s]+v?[0-9][A-Za-z0-9.+-]*){0,2}"
QWEN_MODEL_IDENTITY = (
    rf"qwen(?:[-_\s]*v?[0-9][A-Za-z0-9.+-]*)?[-_\s]+coder"
    rf"{AI_IDENTITY_QUALIFIER}"
)
GEMINI_MODEL_IDENTITY = (
    rf"gemini{AI_IDENTITY_VERSION_INFIX}[-_\s]+(?:pro|flash|ultra)"
    rf"{AI_IDENTITY_QUALIFIER}"
)
UNAMBIGUOUS_AI_IDENTITY = (
    rf"(?:claude{AI_IDENTITY_VERSION_INFIX}[-_\s]+"
    rf"(?:code|sonnet|opus|haiku|fable|mythos){AI_IDENTITY_QUALIFIER}"
    rf"|{QWEN_MODEL_IDENTITY}|{GEMINI_MODEL_IDENTITY}"
    rf"|(?:codex|chatgpt|gpt|openai|opencode|(?:github\s+)?copilot|qwen|"
    rf"doubao|windsurf|perplexity){AI_IDENTITY_QUALIFIER})"
)
BRACKETED_AI_BOT_IDENTITY = rf"(?:{AI_PROVIDER_ACCOUNT})\[bot\]"
UNAMBIGUOUS_AI_DISPLAY_NAME = (
    rf"(?:{UNAMBIGUOUS_AI_IDENTITY}|{BRACKETED_AI_BOT_IDENTITY})"
)
AI_BRACKETED_BOT_EMAIL_IDENTITY = (
    rf"[^<>\r\n]+[ \t]*<(?:[0-9]+\+)?"
    rf"{BRACKETED_AI_BOT_IDENTITY}@[^>\r\n]*>"
)
# Emphasis wrapped around just the identity ("**Claude Code**") must not
# defeat the anchored trailer rule; whole-line wrappers are unwrapped later.
INLINE_EMPHASIS_WRAP = r"[*_~`]*"
AI_ATTRIBUTION_IDENTITY = (
    rf"(?:{INLINE_EMPHASIS_WRAP}{UNAMBIGUOUS_AI_DISPLAY_NAME}"
    rf"{INLINE_EMPHASIS_WRAP}[ \t]*<[^>\r\n]*>"
    rf"|{INLINE_EMPHASIS_WRAP}{AI_PROVIDER}{INLINE_EMPHASIS_WRAP}[ \t]*<[^>\r\n]*"
    r"(?<![A-Za-z0-9])(?:no-?reply|bot)(?![A-Za-z0-9])"
    rf"[^>\r\n]*>|{AI_BRACKETED_BOT_EMAIL_IDENTITY})"
)
AI_COMMIT_IDENTITY = re.compile(
    rf"^(?:{UNAMBIGUOUS_AI_DISPLAY_NAME}[ \t]*<[^>\r\n]*>"
    rf"|{AI_BRACKETED_BOT_EMAIL_IDENTITY})[ \t]*$",
    re.IGNORECASE,
)
MARKDOWN_LINE_PREFIX = (
    r"[ \t]*(?:(?:>[ \t]*)"
    r"|(?:[-*+][ \t]+(?:\[[ xX]\][ \t]+)?)"
    r"|(?:[0-9]{1,9}[.)][ \t]+(?:\[[ xX]\][ \t]+)?)"
    r"|(?:#{1,6}[ \t]+))*"
)
MARKDOWN_LINE_PREFIX_RE = re.compile(MARKDOWN_LINE_PREFIX)
INLINE_MARKDOWN_WRAPPERS = ("```", "**", "__", "~~", "``", "*", "_", "`")
GENERIC_AI_ACTOR = r"(?:ai|llm)"
AI_SESSION_ACTOR = rf"(?:{AI_PROVIDER}|{GENERIC_AI_ACTOR})"
# Keep the two verified human-name collisions precise without treating every
# capitalized model/product continuation (Model, Pro, Sonnet, ...) as a surname.
KNOWN_HUMAN_CREDIT_GUARD = r"(?!(?:ai[ \t]+weiwei|claude[ \t]+monet)\b)"
AI_GENERATOR = (
    rf"(?:{UNAMBIGUOUS_AI_IDENTITY}|generative\s+ai|large\s+language\s+model"
    rf"|{KNOWN_HUMAN_CREDIT_GUARD}(?:{AI_PROVIDER}|{GENERIC_AI_ACTOR}))"
)
AI_SESSION_ORIGIN_ALIASES = (
    (r"(?:www\.)?claude\.ai", ""),
    (r"(?:www\.)?chatgpt\.com", ""),
    (r"chat\.openai\.com", ""),
    (r"(?:www\.)?kimi\.com", ""),
    (r"gemini\.google\.com", ""),
    (r"g\.co", "gemini/"),
    (r"copilot\.microsoft\.com", ""),
    (r"(?:www\.)?opencode\.ai", ""),
)


def ai_session_origins(default_port: str) -> str:
    return "(?:" + "|".join(
        rf"{host}(?::{default_port})?/{path_prefix}"
        for host, path_prefix in AI_SESSION_ORIGIN_ALIASES
    ) + ")"


AI_SESSION_HTTPS_ORIGIN = ai_session_origins("443")
AI_SESSION_HTTP_ORIGIN = ai_session_origins("80")
# Stop a failed candidate at the next URL scheme. Without this boundary, a
# greedy path rescan starts again at every repeated recognized origin and turns
# a bounded 100 KB input into quadratic work.
AI_SESSION_PATH_CHAR = r"(?:(?!https?://)[^\s<>\"'])"
CANONICAL_UUID = (
    r"[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-"
    r"[0-9a-f]{4}-[0-9a-f]{12}"
)
BRANCH_SEPARATOR_CHAR = r"[-_/\.]"
BRANCH_SEPARATOR = rf"{BRANCH_SEPARATOR_CHAR}+"
BRANCH_START = rf"(?:^|(?<={BRANCH_SEPARATOR_CHAR}))"
BRANCH_BOUNDARY = rf"(?=$|{BRANCH_SEPARATOR_CHAR})"
AI_PROVIDER_BRANCH_ALIASES = tuple(
    alias.replace(r"\s+", BRANCH_SEPARATOR) for alias in AI_PROVIDER_ALIASES
)
AI_PROVIDER_BRANCH = rf"(?:{'|'.join(AI_PROVIDER_BRANCH_ALIASES)})"
AI_SESSION_BRANCH_ACTOR = rf"(?:{AI_PROVIDER_BRANCH}|{GENERIC_AI_ACTOR})"


@dataclass(frozen=True)
class Pattern:
    category: str
    regex: re.Pattern[str]


PATTERNS = (
    Pattern(
        "ai_session_url",
        re.compile(
            rf"(?:(?:https://{AI_SESSION_HTTPS_ORIGIN})"
            rf"|(?:http://{AI_SESSION_HTTP_ORIGIN}))(?:"
            rf"(?:c|chat)/{CANONICAL_UUID}"
            rf"|{AI_SESSION_PATH_CHAR}*(?:(?:session|shares?)[_/-]|code/"
            r"|codex/tasks?[_/-])"
            r"[A-Za-z0-9][A-Za-z0-9_-]{5,})",
            re.IGNORECASE,
        ),
    ),
    Pattern(
        "ai_session_id",
        re.compile(
            rf"\b{AI_SESSION_ACTOR}[-_ ]?session(?:[-_ ]?id)?"
            r"\s*[:=_-]\s*[A-Za-z0-9][A-Za-z0-9_-]{5,}",
            re.IGNORECASE,
        ),
    ),
    Pattern(
        "ai_session_trailer",
        re.compile(
            rf"^{MARKDOWN_LINE_PREFIX}{AI_SESSION_ACTOR}"
            rf"[-_ ]session(?:[-_ ]id)?\s*:\s*\S+",
            re.IGNORECASE | re.MULTILINE,
        ),
    ),
    Pattern(
        "ai_coauthor_trailer",
        re.compile(
            rf"^{MARKDOWN_LINE_PREFIX}co-authored-by\s*:"
            rf"\s*{AI_ATTRIBUTION_IDENTITY}[ \t]*$",
            re.IGNORECASE | re.MULTILINE,
        ),
    ),
    Pattern(
        "generated_by_footer",
        re.compile(
            rf"^{MARKDOWN_LINE_PREFIX}(?:(?:🤖[ \t]*)?"
            rf"(?:generated|created|written|built|authored|produced)"
            rf"[ \t]+(?:with|by|using)[ \t]+[\[(<\"'*_~]*{AI_GENERATOR}\b.*"
            rf"|🤖[ \t]*{AI_PROVIDER})[ \t]*$",
            re.IGNORECASE | re.MULTILINE,
        ),
    ),
    Pattern(
        "conversation_process",
        re.compile(
            rf"^{MARKDOWN_LINE_PREFIX}(?:用户原话|会话过程|模型分析"
            rf"|{AI_SESSION_ACTOR}\s*分析"
            rf"|user\s+prompt|conversation\s+(?:process|transcript)"
            rf"|{AI_SESSION_ACTOR}\s+(?:analysis|reasoning))\s*[:：]",
            re.IGNORECASE | re.MULTILINE,
        ),
    ),
    Pattern(
        "provenance_wording",
        re.compile(
            r"(?:外部|他人|模型|会话|来源|出处).{0,16}(?:吸收|借鉴)"
            r"|(?:吸收|借鉴).{0,16}(?:外部|他人|模型|会话|来源|出处)"
            r"|\b(?:inspired\s+(?:by|from)|(?:adapted|borrowed)\s+from)\s+"
            rf"(?:{UNAMBIGUOUS_AI_IDENTITY}|{KNOWN_HUMAN_CREDIT_GUARD}"
            rf"{AI_PROVIDER}|another\s+(?:agent|model)"
            r"|external\s+(?:practice|source))\b",
            re.IGNORECASE,
        ),
    ),
)

# Branch refs use slug separators instead of prose whitespace or trailer
# punctuation. Keep this grammar branch-only so normal prose keeps the tighter
# line-oriented precision above.
BRANCH_PATTERNS = (
    Pattern(
        "provenance_wording",
        re.compile(
            rf"{BRANCH_START}(?:inspired{BRANCH_SEPARATOR}(?:by|from)"
            rf"|(?:adapted|borrowed){BRANCH_SEPARATOR}from)"
            rf"{BRANCH_SEPARATOR}{AI_PROVIDER_BRANCH}{BRANCH_BOUNDARY}",
            re.IGNORECASE,
        ),
    ),
    Pattern(
        "generated_by_footer",
        re.compile(
            rf"{BRANCH_START}(?:generated|created|written|built|authored|produced)"
            rf"{BRANCH_SEPARATOR}(?:with|by|using){BRANCH_SEPARATOR}"
            rf"{AI_SESSION_BRANCH_ACTOR}{BRANCH_BOUNDARY}",
            re.IGNORECASE,
        ),
    ),
    Pattern(
        "ai_coauthor_trailer",
        re.compile(
            rf"{BRANCH_START}co{BRANCH_SEPARATOR}authored{BRANCH_SEPARATOR}by"
            rf"{BRANCH_SEPARATOR}{AI_SESSION_BRANCH_ACTOR}{BRANCH_BOUNDARY}",
            re.IGNORECASE,
        ),
    ),
    Pattern(
        "conversation_process",
        re.compile(
            rf"{BRANCH_START}(?:{AI_SESSION_BRANCH_ACTOR}{BRANCH_SEPARATOR}"
            rf"(?:analysis|reasoning|分析)|user{BRANCH_SEPARATOR}prompt"
            rf"|conversation{BRANCH_SEPARATOR}(?:process|transcript)"
            rf"|用户原话|会话过程|模型分析){BRANCH_BOUNDARY}",
            re.IGNORECASE,
        ),
    ),
)


class GateError(Exception):
    pass


def fail(detail: str) -> NoReturn:
    raise GateError(detail)


def read_fd(fd: int, size: int) -> bytes:
    return os.read(fd, size)


def git_environment() -> dict[str, str]:
    environment = os.environ.copy()
    for key in tuple(environment):
        if (
            key in GIT_REPOSITORY_ROUTING_ENV
            or key in GIT_CONFIG_ROUTING_ENV
            or key.startswith(GIT_CONFIG_ROUTING_ENV_PREFIXES)
        ):
            environment.pop(key, None)
    return environment


def stop_process(process: subprocess.Popen[bytes]) -> None:
    if process.poll() is None:
        try:
            process.kill()
        except OSError:
            pass
    try:
        process.wait(timeout=1)
    except (OSError, subprocess.TimeoutExpired):
        pass


def git(
    repo: Path,
    *args: str,
    max_bytes: int = MAX_GIT_OUTPUT_BYTES,
    operation: str = "git command",
    input_bytes: bytes | None = None,
) -> bytes:
    if max_bytes < 0:
        fail(f"{operation} has an invalid safety limit")
    if input_bytes is not None and len(input_bytes) > MAX_GIT_OUTPUT_BYTES:
        fail(f"{operation} input exceeds the safety limit")
    input_stream = None
    try:
        if input_bytes is not None:
            input_stream = tempfile.TemporaryFile()
            input_stream.write(input_bytes)
            input_stream.seek(0)
        process = subprocess.Popen(
            ["git", "--no-replace-objects", "-C", str(repo), *args],
            stdin=input_stream,
            stdout=subprocess.PIPE,
            stderr=subprocess.DEVNULL,
            env=git_environment(),
        )
    except (OSError, ValueError):
        fail(f"{operation} could not run")
    finally:
        if input_stream is not None:
            input_stream.close()
    if process.stdout is None:
        stop_process(process)
        fail(f"{operation} could not capture output")

    selector = selectors.DefaultSelector()
    chunks: list[bytes] = []
    total = 0
    deadline = time.monotonic() + 30
    returncode: int | None = None
    try:
        selector.register(process.stdout, selectors.EVENT_READ)
        while True:
            remaining = deadline - time.monotonic()
            if remaining <= 0:
                fail(f"{operation} timed out")
            try:
                ready = selector.select(remaining)
            except OSError:
                fail(f"{operation} failed")
            if not ready:
                fail(f"{operation} timed out")
            try:
                chunk = read_fd(
                    process.stdout.fileno(), min(65_536, max_bytes + 1 - total)
                )
            except OSError:
                fail(f"{operation} failed")
            if not chunk:
                break
            total += len(chunk)
            if total > max_bytes:
                fail(f"{operation} output exceeds the safety limit")
            chunks.append(chunk)

        remaining = deadline - time.monotonic()
        if remaining <= 0:
            fail(f"{operation} timed out")
        try:
            returncode = process.wait(timeout=remaining)
        except subprocess.TimeoutExpired:
            fail(f"{operation} timed out")
    except BaseException:
        stop_process(process)
        raise
    finally:
        selector.close()
        try:
            process.stdout.close()
        except OSError:
            pass

    if returncode != 0:
        fail(f"{operation} failed")
    return b"".join(chunks)


def git_text(repo: Path, *args: str, operation: str = "git command") -> str:
    return git(repo, *args, operation=operation).decode(
        "utf-8", errors="replace"
    ).strip()


def reject_git_grafts(repo: Path) -> None:
    raw_path = git(
        repo,
        "rev-parse",
        "--git-path",
        "info/grafts",
        max_bytes=16_384,
        operation="candidate graft path resolution",
    )
    try:
        path_text = raw_path.decode("utf-8", errors="strict").strip()
    except UnicodeDecodeError:
        fail("candidate graft path is not valid UTF-8")
    if not path_text or "\x00" in path_text:
        fail("candidate graft path is invalid")
    graft_path = Path(path_text)
    if not graft_path.is_absolute():
        graft_path = repo / graft_path

    if not hasattr(os, "O_NOFOLLOW"):
        fail("candidate graft inspection is unavailable")
    flags = os.O_RDONLY | os.O_NONBLOCK | os.O_NOFOLLOW
    if hasattr(os, "O_CLOEXEC"):
        flags |= os.O_CLOEXEC
    try:
        fd = os.open(graft_path, flags)
    except FileNotFoundError:
        return
    except OSError:
        fail("candidate graft state is unreadable")
    try:
        try:
            info = os.fstat(fd)
        except OSError:
            fail("candidate graft state is unreadable")
        if not stat.S_ISREG(info.st_mode):
            fail("candidate graft state is unsafe")
        try:
            first_byte = read_fd(fd, 1)
        except OSError:
            fail("candidate graft state is unreadable")
    finally:
        try:
            os.close(fd)
        except OSError:
            pass
    if first_byte:
        fail("candidate history uses unsupported grafts")


def read_regular(path: Path, *, max_bytes: int, label: str) -> str:
    if not hasattr(os, "O_NOFOLLOW"):
        fail(f"{label} secure reading is unavailable")
    flags = os.O_RDONLY | os.O_NONBLOCK | os.O_NOFOLLOW
    if hasattr(os, "O_CLOEXEC"):
        flags |= os.O_CLOEXEC
    try:
        fd = os.open(path, flags)
    except OSError:
        fail(f"{label} unreadable")
    try:
        try:
            info = os.fstat(fd)
        except OSError:
            fail(f"{label} unreadable")
        if not stat.S_ISREG(info.st_mode):
            fail(f"{label} must be a regular, non-symlink file")
        if info.st_size > max_bytes:
            fail(f"{label} exceeds the safety limit")

        chunks: list[bytes] = []
        total = 0
        while total <= max_bytes:
            try:
                chunk = read_fd(fd, min(65_536, max_bytes + 1 - total))
            except OSError:
                fail(f"{label} unreadable")
            if not chunk:
                break
            chunks.append(chunk)
            total += len(chunk)
        data = b"".join(chunks)
    finally:
        try:
            os.close(fd)
        except OSError:
            pass
    if len(data) > max_bytes:
        fail(f"{label} exceeds the safety limit")
    try:
        return data.decode("utf-8")
    except UnicodeDecodeError as exc:
        fail(f"{label} is not UTF-8 at byte {exc.start}")


def event_path(args: argparse.Namespace) -> Path | None:
    if args.event_json is not None:
        return args.event_json
    raw = os.environ.get("GITHUB_EVENT_PATH", "")
    return Path(raw) if raw else None


def load_event(path: Path | None) -> dict[str, object] | None:
    if path is None:
        return None
    raw = read_regular(path, max_bytes=MAX_EVENT_BYTES, label="event JSON")
    try:
        parsed = json.loads(raw)
    except json.JSONDecodeError as exc:
        fail(f"event JSON is malformed at line {exc.lineno} column {exc.colno}")
    if not isinstance(parsed, dict):
        fail("event JSON top level must be an object")
    return parsed


def pull_request_fields(event: dict[str, object] | None) -> list[tuple[str, str]]:
    if event is None or "pull_request" not in event:
        return []
    pr = event["pull_request"]
    if not isinstance(pr, dict):
        fail("event pull_request must be an object")
    title = pr.get("title")
    body = pr.get("body")
    if not isinstance(title, str):
        fail("event pull_request.title must be a string")
    if body is not None and not isinstance(body, str):
        fail("event pull_request.body must be a string or null")
    return [("pull_request_title", title), ("pull_request_body", body or "")]


def event_base(event: dict[str, object] | None) -> str | None:
    if event is None:
        return None
    pr = event.get("pull_request")
    if isinstance(pr, dict):
        base = pr.get("base")
        if isinstance(base, dict) and isinstance(base.get("sha"), str):
            return base["sha"]
    before = event.get("before")
    return before if isinstance(before, str) and before.strip("0") else None


def is_branch_push_without_base(event: dict[str, object] | None) -> bool:
    if event is None or "pull_request" in event:
        return False
    ref = event.get("ref")
    if not isinstance(ref, str) or not ref.startswith("refs/heads/"):
        return False
    before = event.get("before")
    return not (isinstance(before, str) and before.strip("0"))


def event_branch(event: dict[str, object] | None) -> str | None:
    if event is None:
        return None
    pr = event.get("pull_request")
    if isinstance(pr, dict):
        head = pr.get("head")
        if isinstance(head, dict) and isinstance(head.get("ref"), str):
            return head["ref"]
    ref = event.get("ref")
    if isinstance(ref, str) and ref.startswith("refs/heads/"):
        return ref.removeprefix("refs/heads/")
    return None


def resolve_commit(
    repo: Path,
    ref: str,
    *,
    label: str,
    unresolved_detail: str | None = None,
) -> str:
    try:
        result = subprocess.run(
            [
                "git",
                "--no-replace-objects",
                "-C",
                str(repo),
                "rev-parse",
                "--verify",
                "--quiet",
                "--end-of-options",
                f"{ref}^{{commit}}",
            ],
            stdout=subprocess.PIPE,
            stderr=subprocess.DEVNULL,
            check=False,
            timeout=30,
            env=git_environment(),
        )
    except subprocess.TimeoutExpired:
        fail(f"{label} resolution timed out")
    except (OSError, ValueError):
        fail(f"{label} resolution could not run")
    if result.returncode != 0:
        fail(unresolved_detail or f"{label} does not resolve")
    oid = result.stdout.strip()
    if not re.fullmatch(rb"[0-9a-fA-F]{40}|[0-9a-fA-F]{64}", oid):
        fail(f"{label} resolved to an invalid object id")
    return oid.decode("ascii").lower()


def resolve_head(repo: Path, requested: str | None) -> str:
    return resolve_commit(repo, requested or "HEAD", label="candidate head")


def resolve_base(
    repo: Path,
    requested: str | None,
    event: dict[str, object] | None,
    default_ref: str | None,
    head: str,
) -> str:
    selected = next(
        (
            (value, source)
            for value, source in (
                (requested, "explicit"),
                (event_base(event), "trusted_event"),
                (os.environ.get("CCL_SKILL_BASE_REF"), "environment"),
                (default_ref, "default"),
            )
            if value
        ),
        None,
    )
    if selected is None:
        fail(
            "candidate base is unresolved; pass --base-ref/CCL_SKILL_BASE_REF, "
            "use a PR event with pull_request.base.sha, or configure --default-base-ref"
        )
    candidate, source = selected
    unresolved_by_source = {
        "explicit": (
            "the explicit candidate base does not resolve; pass a resolvable "
            "--base-ref, or set CCL_SKILL_BASE_REF in a pre-push caller"
        ),
        "trusted_event": (
            "the trusted event candidate base does not resolve; repair the event "
            "base or pass an explicit --base-ref"
        ),
        "environment": (
            "the CCL_SKILL_BASE_REF candidate base does not resolve; set "
            "CCL_SKILL_BASE_REF to a resolvable landing base"
        ),
        "default": (
            "the default candidate base does not resolve; set CCL_SKILL_BASE_REF "
            "to a resolvable landing base"
        ),
    }
    base = resolve_commit(
        repo,
        candidate,
        label="configured candidate base",
        unresolved_detail=unresolved_by_source[source],
    )
    merge_base = git_text(
        repo,
        "merge-base",
        base,
        head,
        operation="candidate merge-base",
    )
    if not re.fullmatch(r"[0-9a-fA-F]{40}|[0-9a-fA-F]{64}", merge_base):
        fail("candidate merge-base returned an invalid object id")
    return merge_base.lower()


def resolve_branch(
    repo: Path, requested: str | None, event: dict[str, object] | None
) -> str:
    for value in (
        requested,
        event_branch(event),
        os.environ.get("GITHUB_HEAD_REF"),
        os.environ.get("GITHUB_REF_NAME"),
    ):
        if value:
            return value
    try:
        result = subprocess.run(
            [
                "git",
                "--no-replace-objects",
                "-C",
                str(repo),
                "symbolic-ref",
                "--quiet",
                "--short",
                "HEAD",
            ],
            stdout=subprocess.PIPE,
            stderr=subprocess.DEVNULL,
            check=False,
            text=True,
            timeout=30,
            env=git_environment(),
        )
    except subprocess.TimeoutExpired:
        fail("candidate branch resolution timed out")
    except (OSError, ValueError):
        fail("candidate branch resolution could not run")
    if result.returncode == 0 and result.stdout.strip():
        return result.stdout.strip()
    fail("candidate branch name is unavailable")


def validate_commit_batch(raw: bytes, oids: list[str]) -> None:
    offset = 0
    for expected_oid in oids:
        header_end = raw.find(b"\n", offset)
        if header_end < 0:
            fail("candidate commit object scan returned malformed records")
        header = raw[offset:header_end]
        fields = header.split(b" ")
        if len(fields) != 3:
            fail("candidate commit object scan returned malformed records")
        oid_bytes, object_type, size_bytes = fields
        try:
            oid = oid_bytes.decode("ascii", errors="strict")
            size_text = size_bytes.decode("ascii", errors="strict")
        except UnicodeDecodeError:
            fail("candidate commit object scan returned malformed records")
        if (
            oid.lower() != expected_oid.lower()
            or object_type != b"commit"
            or re.fullmatch(r"0|[1-9][0-9]*", size_text) is None
        ):
            fail("candidate commit object scan returned malformed records")
        size = int(size_text)
        payload_start = header_end + 1
        payload_end = payload_start + size
        if payload_end >= len(raw) or raw[payload_end : payload_end + 1] != b"\n":
            fail("candidate commit object scan returned malformed records")
        payload = raw[payload_start:payload_end]
        if b"\x00" in payload:
            fail("candidate commit object contains NUL")
        offset = payload_end + 1
    if offset != len(raw):
        fail("candidate commit object scan returned malformed records")


def commit_messages(
    repo: Path, base: str, head: str
) -> list[tuple[str, str, str, str]]:
    oid_output = git(
        repo,
        "rev-list",
        f"{base}..{head}",
        operation="candidate commit enumeration",
    )
    try:
        oids = [line.decode("ascii", errors="strict") for line in oid_output.splitlines()]
    except UnicodeDecodeError:
        fail("candidate commit enumeration returned an invalid object id")
    if any(
        re.fullmatch(r"[0-9a-fA-F]{40}|[0-9a-fA-F]{64}", oid) is None
        for oid in oids
    ):
        fail("candidate commit enumeration returned an invalid object id")
    if oids:
        raw_objects = git(
            repo,
            "cat-file",
            "--batch",
            input_bytes=b"".join(oid.encode("ascii") + b"\n" for oid in oids),
            operation="candidate commit object scan",
        )
        validate_commit_batch(raw_objects, oids)

    raw = git(
        repo,
        "log",
        "--encoding=UTF-8",
        "--format=%H%x00%B%x00%an <%ae>%x00%cn <%ce>%x00",
        f"{base}..{head}",
        operation="candidate commit scan",
    )
    parts = raw.split(b"\x00")
    if len(parts) % 4 != 1:
        fail("candidate commit scan returned malformed records")
    records: list[tuple[str, str, str, str]] = []
    record_oids: list[str] = []
    for index in range(0, len(parts) - 3, 4):
        try:
            sha = parts[index].decode("ascii", errors="strict").strip()
        except UnicodeDecodeError:
            fail("candidate commit scan returned an invalid object id")
        locator = sha[:12] if sha else "unknown"

        decoded: list[str] = []
        for field, value in (
            ("message", parts[index + 1]),
            ("author", parts[index + 2]),
            ("committer", parts[index + 3]),
        ):
            try:
                text = value.decode("utf-8", errors="strict")
            except UnicodeDecodeError:
                fail(
                    "candidate commit metadata is not valid UTF-8 "
                    f"locator={locator} field={field}"
                )
            if "\ufffd" in text:
                fail(
                    "candidate commit metadata is not valid UTF-8 "
                    f"locator={locator} field={field}"
                )
            decoded.append(text)
        message, author, committer = decoded
        if not re.fullmatch(r"[0-9a-fA-F]{40}|[0-9a-fA-F]{64}", sha):
            fail("candidate commit scan returned an invalid object id")
        record_oids.append(sha.lower())
        records.append((locator, message, author.strip(), committer.strip()))
    if record_oids != [oid.lower() for oid in oids]:
        fail("candidate commit scan returned inconsistent records")
    return records


MAX_TAG_PEEL_DEPTH = 10


def annotated_tag_records(
    repo: Path, requested: str | None
) -> list[tuple[str, str, str]]:
    """Collect (locator, message, tagger) for each annotated-tag layer of the
    candidate ref. resolve_head peels straight to the commit, so tag messages
    and tagger identities — prohibited surfaces of a `refs/tags/*` push — are
    invisible to the commit walk and must be scanned from the tag objects."""
    ref = requested or "HEAD"
    oid = git_text(
        repo,
        "rev-parse",
        "--verify",
        "--quiet",
        "--end-of-options",
        ref,
        operation="candidate object resolution",
    ).lower()
    if not re.fullmatch(r"[0-9a-f]{40}|[0-9a-f]{64}", oid):
        fail("candidate object resolved to an invalid object id")
    records: list[tuple[str, str, str]] = []
    for _ in range(MAX_TAG_PEEL_DEPTH):
        object_type = git_text(
            repo, "cat-file", "-t", oid, operation="candidate tag type scan"
        )
        if object_type != "tag":
            return records
        locator = oid[:12]
        payload = git(
            repo, "cat-file", "tag", oid, operation="candidate tag object scan"
        )
        if b"\x00" in payload:
            fail("candidate tag object contains NUL")
        try:
            text = payload.decode("utf-8", errors="strict")
        except UnicodeDecodeError:
            fail(
                "candidate tag metadata is not valid UTF-8 "
                f"locator={locator}"
            )
        if "�" in text:
            fail(
                "candidate tag metadata is not valid UTF-8 "
                f"locator={locator}"
            )
        header_text, separator, message = text.partition("\n\n")
        if not separator:
            header_text, message = text, ""
        # Git peels the FIRST object header; a crafted literal tag could add a
        # second one to redirect this scan onto a clean decoy chain. Require
        # the canonical layout and reject duplicated core headers outright.
        header_lines = header_text.split("\n")
        if not header_lines or not header_lines[0].startswith("object "):
            fail(f"candidate tag object header is malformed locator={locator}")
        header_counts: dict[str, int] = {}
        target = ""
        tagger = ""
        for line in header_lines:
            key = line.split(" ", 1)[0]
            if key in {"object", "type", "tag", "tagger"}:
                header_counts[key] = header_counts.get(key, 0) + 1
                if header_counts[key] > 1:
                    fail(
                        "candidate tag object has duplicate headers "
                        f"locator={locator}"
                    )
            if line.startswith("object "):
                target = line.removeprefix("object ").strip().lower()
            elif line.startswith("tagger "):
                tagger = re.sub(
                    r"\s+\d+\s+[+-]\d{4}$", "", line.removeprefix("tagger ")
                ).strip()
        records.append((locator, message, tagger))
        if not re.fullmatch(r"[0-9a-f]{40}|[0-9a-f]{64}", target):
            fail("candidate tag object names an invalid target id")
        oid = target
    fail("candidate tag peel depth exceeded")


def unwrap_inline_markdown_body(body: str) -> str:
    start = 0
    end = len(body)
    while start < end:
        wrapper = next(
            (
                candidate
                for candidate in INLINE_MARKDOWN_WRAPPERS
                if end - start > 2 * len(candidate)
                and body.startswith(candidate, start, end)
                and body.endswith(candidate, start, end)
            ),
            None,
        )
        if wrapper is None:
            break
        start += len(wrapper)
        end -= len(wrapper)
    return body[start:end]


def outer_markdown_link(body: str) -> tuple[str, str] | None:
    if not body.startswith("[") or not body.endswith(")"):
        return None
    label_end = body.find("](", 1)
    if label_end <= 1:
        return None
    label = body[1:label_end]
    if "[" in label or "]" in label:
        return None
    return label, body[label_end + 2 : -1]


def unwrap_inline_markdown_line(line: str) -> str:
    content_end = len(line.rstrip(" \t"))
    content = line[:content_end]
    trailing = line[content_end:]
    prefix_match = MARKDOWN_LINE_PREFIX_RE.match(content)
    prefix_end = prefix_match.end() if prefix_match is not None else 0
    prefix = content[:prefix_end]
    body = unwrap_inline_markdown_body(content[prefix_end:])

    link = outer_markdown_link(body)
    if link is None:
        return prefix + body + trailing
    label, destination = link
    label = unwrap_inline_markdown_body(label)
    # Scan the visible label as its own line so anchored trailer rules apply;
    # retain the destination on another line so a session URL cannot disappear.
    return prefix + label + trailing + "\n" + destination


def normalize_scan_text(text: str) -> str:
    normalized = text.replace("\r\n", "\n").replace("\r", "\n")
    return "\n".join(
        unwrap_inline_markdown_line(line) for line in normalized.split("\n")
    )


def violations(surface: str, locator: str, text: str) -> list[str]:
    scan_text = normalize_scan_text(text)
    found: list[str] = []
    patterns = PATTERNS + BRANCH_PATTERNS if surface == "branch" else PATTERNS
    for pattern in patterns:
        if pattern.regex.search(scan_text):
            found.append(
                f"surface={surface} locator={locator} category={pattern.category}"
            )
    return found


def commit_identity_violations(
    surface: str, locator: str, identity: str
) -> list[str]:
    if not AI_COMMIT_IDENTITY.fullmatch(identity):
        return []
    return [f"surface={surface} locator={locator} category=ai_commit_identity"]


class SafeArgumentParser(argparse.ArgumentParser):
    def error(self, message: str) -> NoReturn:
        del message
        self.exit(2, "shared_git_surface_gate_error: invalid arguments\n")


def parse_args(argv: list[str]) -> argparse.Namespace:
    parser = SafeArgumentParser(
        description=(
            "Scan only the candidate commit range plus current branch and PR text. "
            "Diagnostics report categories without echoing private identifiers."
        )
    )
    parser.add_argument("--repo", type=Path, default=Path("."))
    parser.add_argument("--base-ref")
    parser.add_argument(
        "--head-ref",
        help="candidate commit/ref to scan without changing the working tree (default: HEAD)",
    )
    parser.add_argument(
        "--default-base-ref",
        help="repository-owned fallback used only when no explicit/env/event base exists",
    )
    parser.add_argument("--branch-name")
    parser.add_argument("--event-json", type=Path)
    parser.add_argument("--pr-text-file", type=Path)
    return parser.parse_args(argv)


def run(argv: list[str]) -> int:
    args = parse_args(argv)
    repo = args.repo
    if (
        git_text(
            repo,
            "rev-parse",
            "--is-inside-work-tree",
            operation="work-tree check",
        )
        != "true"
    ):
        fail("repository is not a git work tree")
    reject_git_grafts(repo)
    event = load_event(event_path(args))
    head = resolve_head(repo, args.head_ref)
    base = resolve_base(repo, args.base_ref, event, args.default_base_ref, head)
    branch = resolve_branch(repo, args.branch_name, event)
    if base == head and is_branch_push_without_base(event):
        fail(
            "direct-push candidate commit range is empty; provide a resolvable "
            "pre-push base before the candidate head"
        )
    commits = commit_messages(repo, base, head)
    tag_records = annotated_tag_records(repo, args.head_ref)
    reject_git_grafts(repo)

    findings: list[str] = []
    findings.extend(violations("branch", "current", branch))
    for locator, message, tagger in tag_records:
        findings.extend(violations("tag_message", locator, message))
        if tagger:
            findings.extend(
                commit_identity_violations("tag_tagger", locator, tagger)
            )
    for sha, message, author, committer in commits:
        findings.extend(violations("commit", sha, message))
        findings.extend(commit_identity_violations("commit_author", sha, author))
        findings.extend(
            commit_identity_violations("commit_committer", sha, committer)
        )

    pr_fields = pull_request_fields(event)
    for surface, value in pr_fields:
        findings.extend(violations(surface, "event", value))
    if args.pr_text_file is not None:
        proposed = read_regular(
            args.pr_text_file, max_bytes=MAX_PR_TEXT_BYTES, label="proposed PR text"
        )
        if not proposed.strip():
            fail("proposed PR text must contain non-whitespace content")
        findings.extend(violations("proposed_pr_text", "file", proposed))

    if findings:
        print("shared_git_surface_gate: prohibited metadata in candidate surface(s):", file=sys.stderr)
        for finding in findings:
            print(f"  {finding}", file=sys.stderr)
        print(
            "shared_git_surface_gate_failed: use neutral capability/change wording; keep provenance in a private archive",
            file=sys.stderr,
        )
        return 1

    print(
        "shared_git_surface_gate_ok: "
        f"commits={len(commits)} branch=1 pr_fields={len(pr_fields)} "
        f"proposed_pr_files={1 if args.pr_text_file is not None else 0} "
        f"tag_objects={len(tag_records)}"
    )
    return 0


def emit_error(detail: str) -> int:
    try:
        print(f"shared_git_surface_gate_error: {detail}", file=sys.stderr)
    except (BrokenPipeError, OSError):
        pass
    return 2


def main() -> int:
    try:
        return run(sys.argv[1:])
    except GateError as exc:
        return emit_error(str(exc))
    except BrokenPipeError:
        return 2
    except Exception:
        return emit_error("unexpected internal failure")


if __name__ == "__main__":
    raise SystemExit(main())
