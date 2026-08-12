#!/usr/bin/env python3
"""client-terminal-ansi-check.py — CB-1: terminal NO-HARDCODED-ANSI conformance.

Flags literal ANSI/VT100 escape sequences written directly in SOURCE code, outside an
allowlisted rendering/terminal-capability module. clig.dev (Output) and the terminfo model say
escapes must go through a capability-aware layer that can degrade for `TERM=dumb`/non-TTY/NO_COLOR;
a raw `\\x1b[31m` sprinkled through business code is the anti-pattern this catches.

Language-agnostic: this is a BYTE/TEXT scan (no AST, no parser), so it is genuinely
zero-dependency and works across Go/Rust/Python/JS/TS/Swift/Kotlin/etc. It scans only
source-code extensions, so it does not flag golden/fixture files that legitimately embed ANSI.

Matched escape-intro forms (a CSI `[` or OSC `]` introducer must follow the ESC):
  \\x1b[ \\x1B[ \\033[ \\e[ \\u001b[ \\u{1b}[ and raw-ESC(0x1b)+[   (CSI) — plus the same six with
  a `]` introducer (OSC, e.g. OSC-8 hyperlink / OSC-52 clipboard write).

Determinism boundary (honest): deterministic for "a hardcoded CSI/OSC escape literal is PRESENT".
It does NOT decide whether the escape is correctly gated behind a capability lib / NO_COLOR / isatty
(semantic, agent-review), and it covers the CSI/OSC introducers only — other Fe sequences (charset
`\\x1b(`, DCS `\\x1bP`, etc.) and ESC introducers reached through a variable are not matched. It also
does NOT follow symlinked directories (os.walk default), so a violation behind a symlink is not
scanned. A clean run therefore means "no matched hardcoded escape literals found in the walked,
non-symlinked source tree outside the allowlist", NOT full conformance. Put your rendering/ANSI/
terminal lib on the allowlist so its legitimate escape definitions are exempt.

Allowlist: `--allow=<path-segment>` exempts files under a matching path COMPONENT (segment-anchored,
not a raw substring — `--allow=render` exempts `render/…` but not `surrender.ts`); a multi-segment
value (`src/render`) matches a contiguous run of segments. Use it for the one module that owns escape
emission, e.g. `--allow=ansi --allow=render`.

Comments are NOT excluded (comment syntax varies across the many languages this scans — `//`, `#`,
`--`, `/* */`), so a hardcoded escape inside a comment is still flagged; move illustrative escapes
into an allowlisted module or restructure them. Likewise a double-escaped TEXT literal such as
`"\\e]"` (an escaped backslash, not a real ESC) is flagged — source-text scanning cannot tell it
from `"\e]"`. Both are accepted residuals (advisory: a hit is "to verify"), not parser bugs.

Exit: 0 no finding; 1 finding(s); 2 setup/inconclusive (missing path, unsupported file, scope with
no source files, or an unreadable subtree — NEVER reported as clean).
"""
import os
import re
import sys

SOURCE_EXT = {
    ".go", ".rs", ".py", ".js", ".jsx", ".ts", ".tsx", ".mjs", ".cjs", ".mts", ".cts",
    ".c", ".cc", ".cpp", ".h", ".hpp", ".swift", ".kt", ".kts", ".java",
    ".rb", ".sh", ".bash", ".zsh", ".lua", ".dart",
}

# An introducer must follow the ESC, to avoid matching unrelated `\e`/`\033` text. Accept both
# `[` (CSI: cursor/clear/color) AND `]` (OSC: hyperlink / OSC-52 clipboard write) — §6 of the
# terminal skill treats OSC-8/OSC-52 as a security boundary, so a hardcoded OSC escape is in scope.
ESCAPE_RE = re.compile(
    r"\\x1[bB][\[\]]"          # \x1b[
    r"|\\033[\[\]]"            # \033[
    r"|\\e[\[\]]"              # \e[
    r"|\\u001[bB][\[\]]"       # [
    r"|\\u\{0*1[bB]\}[\[\]]"     # \u{1b}[
    r"|\x1b[\[\]]"             # raw ESC byte (0x1b) + [
)


def _iter_src(paths, onerror=None):
    for p in paths:
        if os.path.isdir(p):
            for root, _dirs, files in os.walk(p, onerror=onerror):
                for f in files:
                    if os.path.splitext(f)[1] in SOURCE_EXT:
                        yield os.path.join(root, f)
        elif os.path.splitext(p)[1] in SOURCE_EXT:
            yield p


def _allowed(path, allow):
    # Segment-anchored: `--allow=render` matches a `render/` path component, NOT the substring inside
    # `surrender.ts`. A multi-segment entry (`src/render`) matches as a contiguous run of segments.
    segs = [s for s in re.split(r"[\\/]+", path) if s]
    for a in allow:
        parts = [p for p in re.split(r"[\\/]+", a) if p]
        if not parts:
            continue
        for i in range(len(segs) - len(parts) + 1):
            if segs[i:i + len(parts)] == parts:
                return True
    return False


def _check_file(path):
    try:
        with open(path, encoding="utf-8") as fh:
            lines = fh.readlines()
    except (UnicodeDecodeError, OSError) as exc:
        return None, f"{path}: {exc}"
    findings = []
    for i, line in enumerate(lines, 1):
        if ESCAPE_RE.search(line):
            findings.append(f"{path}:{i}: hardcoded ANSI/OSC escape literal")
    return findings, None


def main(argv):
    allow = [a[len("--allow="):] for a in argv if a.startswith("--allow=")]
    paths = [a for a in argv if not a.startswith("--allow=")]
    if not paths:
        print("usage: client-terminal-ansi-check.py <src-path> [...] [--allow=<substr>]...", file=sys.stderr)
        return 2
    walk_errs = []
    for p in paths:
        if not os.path.exists(p):
            print(f"client-ansi: path not found: {p} — inconclusive", file=sys.stderr)
            return 2
        if os.path.isfile(p) and os.path.splitext(p)[1] not in SOURCE_EXT:
            print(f"client-ansi: unsupported file type: {p} — inconclusive", file=sys.stderr)
            return 2
        if os.path.isdir(p) and not any(_iter_src([p], onerror=walk_errs.append)):
            print(f"client-ansi: no source files under directory: {p} — inconclusive", file=sys.stderr)
            return 2
    files = list(_iter_src(paths, onerror=walk_errs.append))
    if walk_errs:
        print(f"client-ansi: cannot read part of scope ({walk_errs[0]}) — inconclusive", file=sys.stderr)
        return 2
    if not files:
        print("client-ansi: no source files in scope — inconclusive", file=sys.stderr)
        return 2
    hits = 0
    for f in files:
        if _allowed(f, allow):
            continue
        res, err = _check_file(f)
        if err is not None:
            print(f"client-ansi: read error: {err} — inconclusive", file=sys.stderr)
            return 2
        for line in res:
            print(f"client-ansi smell: {line}")
            hits = 1
    return hits


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
