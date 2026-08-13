#!/usr/bin/env python3
"""Fail when tracked repository paths or contents expose private provenance."""

from __future__ import annotations

import ipaddress
import os
import re
import subprocess
import sys
from pathlib import Path
from urllib.parse import urlparse



def display(text: str) -> str:
    """Render untrusted repo text safe to print on one physical line.

    A tracked filename may legally contain a newline, an ANSI escape, or (after
    os.fsdecode) a surrogate for a byte that is not valid UTF-8. Interpolated
    raw, one filename splits a finding across two physical lines, so anything
    reading this output line by line — a human, a CI annotation parser — sees a
    forged line. Escaping is display-only; the value used for resolution is
    untouched. Printable non-ASCII (an ordinary CJK filename) is preserved.
    """
    # Backslash FIRST, then every non-printable character including tab:
    # otherwise the encoding is not reversible — a real newline and a filename
    # containing a literal backslash-n both render as the same two characters,
    # so two distinct tracked paths produce an identical diagnostic. Printable
    # non-ASCII (an ordinary CJK filename) is preserved.
    escaped = text.replace("\\", "\\\\")
    return "".join(ch if ch.isprintable() else repr(ch)[1:-1] for ch in escaped)

def tracked_paths(root: Path) -> list[str]:
    result = subprocess.run(
        ["git", "-C", str(root), "ls-files", "-z"],
        check=True,
        capture_output=True,
    )
    # os.fsdecode, not a strict decode: git tracks raw bytes and Linux allows a
    # filename that is not valid UTF-8, which made every one of these three
    # checkers crash with a traceback before scanning anything. macOS rejects
    # such names outright, so it is unreachable on this team's own machines and
    # reachable on the ubuntu CI runner. surrogateescape round-trips back to the
    # original bytes when the path is opened, so the file is still scanned.
    return [os.fsdecode(item) for item in result.stdout.split(b"\0") if item]


URL_RE = re.compile(r"(?:https?|ssh)://[^\s<>\"')\]]+", re.IGNORECASE)
EMAIL_RE = re.compile(r"[A-Z0-9._%+-]+@([A-Z0-9.-]+\.[A-Z]{2,})", re.IGNORECASE)
IP_RE = re.compile(r"(?<![0-9])(?:10(?:\.[0-9]{1,3}){3}|192\.168(?:\.[0-9]{1,3}){2}|172\.(?:1[6-9]|2[0-9]|3[01])(?:\.[0-9]{1,3}){2})(?![0-9])")
ALLOWED_EMAIL_DOMAINS = {"example.com", "example.org", "example.net", "example.invalid"}
SAAS_TENANT_SUFFIXES = ("feishu.cn", "larksuite.com")
PUBLIC_SAAS_HOSTS = {
    "accounts.feishu.cn",
    "accounts.larksuite.com",
    "feishu.cn",
    "larksuite.com",
    "open.feishu.cn",
    "open.larksuite.com",
    "www.feishu.cn",
    "www.larksuite.com",
}
PLACEHOLDER_TENANT_RE = re.compile(
    r"(?:x+|example|sample|tenant|your-tenant|\*+|\.+|\$[a-z_][a-z0-9_]*)",
    re.IGNORECASE,
)


def is_organization_saas_tenant(host: str) -> bool:
    try:
        host = host.encode("idna").decode("ascii")
    except UnicodeError:
        pass
    host = host.rstrip(".").casefold()
    if host in PUBLIC_SAAS_HOSTS:
        return False
    for suffix in SAAS_TENANT_SUFFIXES:
        marker = f".{suffix}"
        if not host.endswith(marker):
            continue
        tenant = host[: -len(marker)]
        return PLACEHOLDER_TENANT_RE.fullmatch(tenant) is None
    return False


def scan(root: Path) -> list[tuple[str, str]]:
    findings: list[tuple[str, str]] = []

    for relative in tracked_paths(root):
        target = root / relative
        if target.is_symlink():
            content = target.readlink().as_posix()
        else:
            content = target.read_bytes().decode("utf-8", errors="ignore")

        for value in IP_RE.findall(content):
            try:
                if ipaddress.ip_address(value).is_private:
                    findings.append((relative, "content:private-ipv4"))
            except ValueError:
                findings.append((relative, "content:malformed-private-ipv4"))

        for match in EMAIL_RE.finditer(content):
            if match.group(1).casefold() not in ALLOWED_EMAIL_DOMAINS:
                findings.append((relative, "content:non-example-email"))

        for raw_url in URL_RE.findall(content):
            host = (urlparse(raw_url).hostname or "").casefold()
            if not host:
                continue
            if host.endswith((".internal", ".local")):
                findings.append((relative, "content:private-hostname"))
                continue
            if is_organization_saas_tenant(host):
                findings.append((relative, "content:organization-saas-tenant-hostname"))
                continue
            try:
                if ipaddress.ip_address(host).is_private:
                    findings.append((relative, "content:private-url-host"))
            except ValueError:
                pass

    return sorted(set(findings))


def main() -> int:
    root = Path(sys.argv[1] if len(sys.argv) > 1 else ".").resolve()
    findings = scan(root)
    if findings:
        for relative, reason in findings:
            print(
            f"public_sanitization_block: {display(reason)}: {display(relative)}",
            file=sys.stderr,
        )
        print(f"public_sanitization_failed: findings={len(findings)}", file=sys.stderr)
        return 1
    print("public_sanitization_ok")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
