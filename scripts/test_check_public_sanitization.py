#!/usr/bin/env python3

from __future__ import annotations

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

    print("public_sanitization_test_ok")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
