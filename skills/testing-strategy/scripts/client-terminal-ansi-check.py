#!/usr/bin/env python3
r"""client-terminal-ansi-check.py — CB-1: terminal NO-HARDCODED-ANSI conformance.

Flags literal ANSI/VT100 escape sequences written directly in SOURCE code, outside an
allowlisted rendering/terminal-capability module. clig.dev (Output) and the terminfo model say
escapes must go through a capability-aware layer that can degrade for `TERM=dumb`/non-TTY/NO_COLOR;
a raw `\x1b[31m` sprinkled through business code is the anti-pattern this catches.

Language-agnostic: this is a BYTE/TEXT scan (no AST, no parser), so it is genuinely
zero-dependency and works across Go/Rust/Python/JS/TS/Swift/Kotlin/etc. It scans only
source-code extensions, so it does not flag golden/fixture files that legitimately embed ANSI.

Matched escape-intro forms (a CSI `[` or OSC `]` introducer must follow the ESC):
  \x1b[ \x1B[ \033[ \e[ \u001b[ \u{1b}[ and raw-ESC(0x1b)+[   (CSI) — plus the same six with
  a `]` introducer (OSC, e.g. OSC-8 hyperlink / OSC-52 clipboard write).

Determinism boundary (honest): deterministic for "a hardcoded CSI/OSC escape literal is PRESENT".
It does NOT decide whether the escape is correctly gated behind a capability lib / NO_COLOR / isatty
(semantic, agent-review), and it covers the CSI/OSC introducers only — other Fe sequences (charset
`\x1b(`, DCS `\x1bP`, etc.) and ESC introducers reached through a variable are not matched. It also
does NOT follow symlinked directories (os.walk default), so a violation behind a symlink is not
scanned. A clean run therefore means "no matched hardcoded escape literals found in the walked,
non-symlinked source tree outside the allowlist", NOT full conformance. Put your rendering/ANSI/
terminal lib on the allowlist so its legitimate escape definitions are exempt.

Allowlist: `--allow=<path-segment>` exempts files under a matching path COMPONENT (segment-anchored,
not a raw substring — `--allow=render` exempts `render/…` but not `surrender.ts`) relative to the
enclosing project root (`.git`, `go.mod`, `package.json`, `pyproject.toml`, `Cargo.toml`, `pubspec.yaml`),
or relative to `cwd` when inside `cwd` with no project marker (outside both `cwd` and any project marker,
resolved segments apply uniformly across directory and file scans unless a symlink escapes its lexical
anchor); a multi-segment value (`src/render`) matches a contiguous run of segments. Use `--allow=ansi
--allow=render` for the module that owns escape emission.

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


PROJECT_MARKERS = (".git", "go.mod", "package.json", "pyproject.toml", "Cargo.toml", "pubspec.yaml")


def _iter_src(paths, onerror=None):
    for p in paths:
        if os.path.isdir(p):
            for root, _dirs, files in os.walk(p, onerror=onerror):
                for f in files:
                    if os.path.splitext(f)[1] in SOURCE_EXT:
                        yield os.path.join(root, f)
        elif os.path.splitext(p)[1] in SOURCE_EXT:
            yield p


def _find_project_root(start_dir):
    cur = os.path.realpath(start_dir)
    while True:
        if any(os.path.exists(os.path.join(cur, m)) for m in PROJECT_MARKERS):
            return cur
        parent = os.path.dirname(cur)
        if parent == cur:
            return None
        cur = parent


def _is_within(child_real, root_real):
    try:
        rel = os.path.relpath(child_real, root_real)
    except ValueError:
        return False
    return rel == "." or (rel != ".." and not rel.startswith(".." + os.sep))


def _split_fs_path(p):
    seps = re.escape(os.sep + (os.altsep or ""))
    return [s for s in re.split(f"[{seps}]+", p) if s]


def _lexical_anchor_dir(arg):
    cur = os.getcwd() if not os.path.isabs(arg) else os.sep
    for part in _split_fs_path(arg):
        if part == ".":
            continue
        if part == "..":
            if os.path.islink(cur):
                break
            cur = os.path.dirname(cur)
            continue
        nxt = os.path.join(cur, part)
        if os.path.islink(nxt) or not os.path.isdir(nxt):
            break
        cur = nxt
    return os.path.realpath(cur)


def _scope_roots_for_arg(arg, cwd_real):
    anchor_dir = _lexical_anchor_dir(arg)
    proj = _find_project_root(anchor_dir)
    if proj is not None:
        return proj, proj
    if _is_within(anchor_dir, cwd_real):
        return anchor_dir, cwd_real
    return anchor_dir, os.path.abspath(os.sep)


def _rel_segments(path, roots):
    containment_root, segment_root = roots
    real_file = os.path.realpath(path)
    if not _is_within(real_file, containment_root):
        return None
    rel = os.path.relpath(real_file, segment_root)
    return [s for s in _split_fs_path(rel) if s != "."]


def _allow_segments(raw):
    return [s for s in re.split(r"[\\/]+", raw) if s and s != "."]


def _allowed(path, allow, roots):
    # Segment-anchored against the resolved path relative to the canonical project/scan root:
    # `--allow=render` matches `render/` inside the root, NOT an ancestor directory above the
    # checkout, NOT `surrender.ts`, NOT `render/../src/colors.go`, and NOT targets resolving
    # outside `containment_root`. Allowlist entries keep raw `..` un-collapsed so `--allow=..`
    # and `--allow=render/../src` never match normalized relative segments.
    segs = _rel_segments(path, roots)
    if not segs:
        return False
    for a in allow:
        parts = _allow_segments(a)
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
    cwd_real = os.path.realpath(os.getcwd())
    scoped_files = []
    for p in paths:
        if not os.path.exists(p):
            print(f"client-ansi: path not found: {p} — inconclusive", file=sys.stderr)
            return 2
        roots = _scope_roots_for_arg(p, cwd_real)
        if os.path.isdir(p):
            walk_errs = []
            sub = list(_iter_src([p], onerror=walk_errs.append))
            if walk_errs:
                print(f"client-ansi: cannot read part of scope ({walk_errs[0]}) — inconclusive", file=sys.stderr)
                return 2
            if not sub:
                print(f"client-ansi: no source files under directory: {p} — inconclusive", file=sys.stderr)
                return 2
            scoped_files.extend((f, roots) for f in sub)
        elif os.path.isfile(p):
            if os.path.splitext(p)[1] not in SOURCE_EXT:
                print(f"client-ansi: unsupported file type: {p} — inconclusive", file=sys.stderr)
                return 2
            scoped_files.append((p, roots))
        else:
            print(f"client-ansi: unsupported file type: {p} — inconclusive", file=sys.stderr)
            return 2
    if not scoped_files:
        print("client-ansi: no source files in scope — inconclusive", file=sys.stderr)
        return 2
    hits = 0
    for f, roots in scoped_files:
        if _allowed(f, allow, roots):
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
