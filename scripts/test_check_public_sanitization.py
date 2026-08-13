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

        cases = {
            "private-ip": "10." + "1.2.3",
            "private-email": "person@" + "corp.local",
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
        }
        for index, (label, value) in enumerate(cases.items()):
            relative = f"case-{index}.txt"
            write_and_track(root, relative, value + "\n")
            result = run(root)
            assert result.returncode == 1, f"{label} unexpectedly passed"
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

    print("public_sanitization_test_ok")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
