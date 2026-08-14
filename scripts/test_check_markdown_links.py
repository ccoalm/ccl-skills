#!/usr/bin/env python3
"""Regression tests for check-markdown-links.py."""

from __future__ import annotations

import importlib.util
import subprocess
import tempfile
import unittest
from pathlib import Path


SCRIPT = Path(__file__).with_name("check-markdown-links.py")
SPEC = importlib.util.spec_from_file_location("check_markdown_links", SCRIPT)
assert SPEC and SPEC.loader
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)


class MarkdownLinkCheckTest(unittest.TestCase):
    def make_repo(self, files: dict[str, str]) -> Path:
        sandbox = Path(self.enterContext(tempfile.TemporaryDirectory()))
        root = sandbox / "repo"
        root.mkdir()
        subprocess.run(["git", "init", "-q", "-b", "main", str(root)], check=True)
        for name, content in files.items():
            path = root / name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(content, encoding="utf-8")
        subprocess.run(["git", "-C", str(root), "add", "."], check=True)
        return root

    def test_accepts_existing_local_external_anchor_and_code_links(self) -> None:
        root = self.make_repo(
            {
                "README.md": """# Root

[guide](docs/guide.md#usage)
[directory](docs/)
[reference][guide-ref]
[web](https://example.com/missing)
[anchor](#root)
`[inline](missing-inline.md)`
``[double-inline](missing-double-inline.md)``
[parenthesized](docs/foo_(bar).md)

    [indented](missing-indented.md)

[guide-ref]: <docs/guide.md#usage> "Guide"

````text
```text
[fenced](missing-fenced.md)
```
````
""",
                "docs/guide.md": "# Guide\n",
                "docs/foo_(bar).md": "# Parenthesized\n",
            }
        )
        self.assertEqual(MODULE.broken_links(root), [])

    def test_reports_missing_local_target_with_source_line(self) -> None:
        root = self.make_repo(
            {
                "README.md": (
                    "# Root\n\n[missing](docs/nope.md)\n"
                    "[escape](../outside.md)\n"
                    "[missing-ref]: docs/missing-ref.md\n"
                    "[wrong-case](docs/Guide.md)\n"
                ),
                "docs/guide.md": "# Guide\n",
            }
        )
        (root.parent / "outside.md").write_text("# Outside\n", encoding="utf-8")
        self.assertEqual(
            MODULE.broken_links(root),
            [
                ("README.md", 3, "docs/nope.md"),
                ("README.md", 4, "../outside.md"),
                ("README.md", 5, "docs/missing-ref.md"),
                ("README.md", 6, "docs/Guide.md"),
            ],
        )


class InvalidUtf8FilenameTest(unittest.TestCase):
    """git tracks raw bytes and Linux allows a filename that is not valid UTF-8.

    A strict decode made this checker raise before scanning anything, so one such
    tracked file hard-failed the whole gate on the ubuntu CI runner. The name
    cannot be created on macOS (APFS rejects it), so the enumeration is driven
    directly rather than through the filesystem.
    """

    def test_invalid_utf8_tracked_name_does_not_crash(self) -> None:
        class FakeRun:
            stdout = b"README.md\x00bad\xff-name.md\x00"
            returncode = 0

        real = MODULE.subprocess.run
        MODULE.subprocess.run = lambda *a, **k: FakeRun()
        try:
            entries = MODULE.tracked_markdown_paths(Path("."))
        finally:
            MODULE.subprocess.run = real
        self.assertEqual(len(entries), 2, entries)
        # count alone would pass for a LOSSY decode; the point is that the
        # name round-trips back to the original bytes so the file can be opened.
        import os as _os
        self.assertEqual(_os.fsencode(_os.fspath(entries[1])).split(b"/")[-1], b"bad\xff-name.md")


if __name__ == "__main__":
    unittest.main()
