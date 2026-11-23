#!/usr/bin/env python3

from __future__ import annotations

import os
import subprocess
import sys
import tempfile
from pathlib import Path


CHECKER = Path(__file__).with_name("check-public-sanitization.py")


def run(root: Path) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        [sys.executable, str(CHECKER), str(root)],
        check=False,
        capture_output=True,
        text=True,
    )


def write_and_track(root: Path, relative: str, content: str) -> None:
    target = root / relative
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_text(content, encoding="utf-8")
    subprocess.run(["git", "-C", str(root), "add", relative], check=True)


def main() -> int:
    with tempfile.TemporaryDirectory(prefix="ccl-public-scan-") as temp:
        root = Path(temp)
        subprocess.run(["git", "-C", str(root), "init", "-q"], check=True)
        write_and_track(
            root,
            "README.md",
            "\n".join(
                (
                    "# CCL Skills",
                    "https://accounts.feishu.cn/open-apis/authen/v1/authorize",
                    "https://accounts.larksuite.com/accounts/page/login",
                    "https://open.feishu.cn/open-apis/",
                    "https://example.feishu.cn/base/BASxxx",
                    "https://xxx.feishu.cn/base/BASxxx",
                    "https://example.larksuite.com/wiki/WIKxxx",
                    "",
                )
            ),
        )
        clean = run(root)
        assert clean.returncode == 0, clean.stderr

        # A literal `\n@decorator` escape sequence in stored JSON evidence is not
        # an email address and must pass (observed false positive on probe
        # evidence files carrying model-written pytest code).
        write_and_track(
            root,
            "evidence.json",
            '{"ans": "code\\n@pytest.fixture\\ndef entry(): ...\\n@pytest.mark.parametrize"}\n',
        )
        clean = run(root)
        assert clean.returncode == 0, f"escaped decorator flagged: {clean.stdout}{clean.stderr}"

        transport_user = "git@" + "github.com"
        write_and_track(
            root, "git-transports.txt",
            f"{transport_user}:example/project.git\nssh://{transport_user}/example/project.git\n",
        )
        clean = run(root)
        assert clean.returncode == 0, f"Git SSH transport flagged: {clean.stdout}{clean.stderr}"

        # Lines mixing non-LF whitespace (\v, \f, \x85), example emails, and
        # GitHub SSH transports must preserve exact span alignment: clean lines
        # pass, while a real private email or URL sharing a line with a valid
        # SSH transport still blocks.
        write_and_track(
            root,
            "non-lf-clean.txt",
            f"prefix\x0bperson@example.com\x0c{transport_user}:example/repo.git\x85person@example.org\n",
        )
        clean = run(root)
        assert clean.returncode == 0, f"non-LF clean line flagged: {clean.stdout}{clean.stderr}"

        cases = {
            "private-ip": "10." + "1.2.3",
            "private-email": "person@" + "corp.local",
            "git-ssh-plus-real-email-same-line": f"{transport_user}:example/project.git and person@" + "corp.local",
            "vertical-tab-before-private-email": "note\x0bperson@" + "corp.local",
            "nel-before-private-url": "note\x85https://service." + "internal/api",
            "escaped-newline-then-real-email": '"\\nfoo@' + 'corp.com"',
            "bare-git-email": transport_user,
            "other-github-user": "person@" + "github.com:example/project.git",
            "github-suffix-domain": "git@" + "github.com.invalid:example/project.git",
            "missing-repository": transport_user + ":example/",
            "ssh-missing-repository": "ssh://" + transport_user + "/example/",
            "embedded-address-prefix": "person." + transport_user + ":example/project.git",
            "ssh-wrong-separator": "ssh://" + transport_user + ":example/project.git",
            "https-userinfo": "https://" + transport_user + ":example/project.git",
            "private-hostname": "https://service." + "internal/api",
            "feishu-tenant-hostname": "https://team-workspace." + "feishu.cn/base/BASxxx",
            "mixed-case-feishu-tenant-hostname": "https://Team-Workspace." + "FEISHU.CN/base/BASxxx",
            "trailing-dot-feishu-tenant-hostname": "https://team-workspace." + "feishu.cn./base/BASxxx",
            "unicode-dot-feishu-tenant-hostname": "https://team-workspace。" + "feishu.cn/base/BASxxx",
            "lark-tenant-hostname": "https://team-workspace." + "larksuite.com/wiki/WIKxxx",
            "fullwidth-dot-lark-tenant-hostname": "https://team-workspace．" + "larksuite.com/wiki/WIKxxx",
            "punycode-tenant-label": "https://xn--bcher-kva." + "feishu.cn/base/BASxxx",
            "userinfo-and-port-feishu-tenant-hostname": "https://user:pass@team-workspace."
            + "feishu.cn:443/base/BASxxx",
            "port-lark-tenant-hostname": "https://team-workspace."
            + "larksuite.com:8443/wiki/WIKxxx",
            "loopback-url-host": "http://127." + "0.0.1:8080/api",
            "link-local-url-host": "http://169.254." + "169.254/latest/meta-data",
        }
        for index, (label, value) in enumerate(cases.items()):
            relative = f"case-{index}.txt"
            write_and_track(root, relative, value + "\n")
            result = run(root)
            assert result.returncode == 1, f"{label} unexpectedly passed"
            assert f": {relative}" in result.stderr, f"{label} failed for another reason: {result.stderr}"
            subprocess.run(["git", "-C", str(root), "reset", "-q", "HEAD", "--", relative], check=False)
            (root / relative).unlink()

    # git tracks raw bytes and Linux allows a filename that is not valid UTF-8; a
    # strict decode made this checker raise before scanning anything, hard-failing
    # the gate on the ubuntu CI runner. macOS rejects such a name (APFS), so the
    # enumeration is driven directly instead of through the filesystem.
    import importlib.util

    spec = importlib.util.spec_from_file_location("check_public_sanitization", CHECKER)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)

    class FakeRun:
        stdout = b"README.md\x00bad\xff-name.md\x00"
        returncode = 0

    real_run = module.subprocess.run
    module.subprocess.run = lambda *a, **k: FakeRun()
    try:
        entries = module.tracked_paths(Path("."))
    finally:
        module.subprocess.run = real_run
    if len(entries) != 2:
        print(f"expected both tracked names to survive decoding, got {entries}", file=sys.stderr)
        return 1
    # count alone would pass for a LOSSY decode; require the byte round-trip.
    if os.fsencode(entries[1]).split(b"/")[-1] != b"bad\xff-name.md":
        print(f"tracked name did not round-trip to its original bytes: {entries[1]!r}", file=sys.stderr)
        return 1

    # display() must come from the shared scripts/_repo_text.py helper rather
    # than a local duplicate copy.
    repo_text_spec = importlib.util.spec_from_file_location(
        "_repo_text", CHECKER.with_name("_repo_text.py")
    )
    assert repo_text_spec is not None and repo_text_spec.loader is not None
    repo_text_mod = importlib.util.module_from_spec(repo_text_spec)
    repo_text_spec.loader.exec_module(repo_text_mod)
    assert module.display.__code__.co_filename == repo_text_mod.display.__code__.co_filename
    assert module.display("a\nb.txt") != module.display("a\\nb.txt")
    assert module.display("中文.md") == "中文.md"

    # Exhaustively verify across all 256x256 leading octet pairs that no IP_RE
    # match can bypass IP_LINE_PREFIXES.
    for oct_a in range(256):
        for oct_b in range(256):
            probe = f"addr={oct_a}.{oct_b}.1.1"
            if module.IP_RE.search(probe):
                assert any(p in probe for p in module.IP_LINE_PREFIXES), (
                    f"IP_RE matched {probe!r} without matching IP_LINE_PREFIXES"
                )

    print("public_sanitization_test_ok")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
