#!/usr/bin/env python3
"""lang-basics-ast-check.py — DETERMINISTIC (for the matched shapes) check for LB-1:
Python boundary error-faking.

Unlike the ripgrep smell-finder, this parses the AST, so it does NOT match text inside
comments or strings, and it catches the grep-bypass forms the smell-grep missed:
`dict(success=False)`, single-quoted dicts, a `{SUCCESS: False}` constant-key, and 2-tuple
error returns.

Scope: pass TRANSPORT / handler / view / router files or directories. The pure/domain core is
exempt (Result/Either is allowed there) — do not point this at the whole tree.

Determinism boundary: it is deterministic ONLY for the enumerated shapes below. "Is this a real
fake error" is undecidable in general, so a clean run means "none of the matched fake-error
shapes are present", NOT full conformance. Shapes it still does not catch (documented residual):
an ad-hoc `{"code": ..., "message": ...}` dict (indistinguishable from a legit envelope without
type/flow analysis), or a value aliased through another variable.

Exit: 0 no finding; 1 finding(s); 2 setup/inconclusive (missing path, non-.py file, directory
with no .py, or a parse error — NEVER reported as clean).
"""
import ast
import os
import sys

SUCCESS_KEYS = {"success", "ok"}
ERR_NAMES = {"err", "error", "errs", "exc", "e", "ex"}


def _iter_py(paths, onerror=None):
    for p in paths:
        if os.path.isdir(p):
            # onerror: os.walk silently skips unreadable subtrees by default — that could turn
            # a partly-unreadable scope into a false "clean". Surface it so main() exits 2.
            for root, _dirs, files in os.walk(p, onerror=onerror):
                for f in files:
                    if f.endswith(".py"):
                        yield os.path.join(root, f)
        elif p.endswith(".py"):
            yield p


def _is_false(node):
    return isinstance(node, ast.Constant) and node.value is False


def _dict_is_fake(d):
    # {"success": False} / {'ok': False} (any quote) / {SUCCESS: False} (constant-name key).
    # ONLY a literal boolean False — NOT 0/None: {"ok": 0} is a legit count, not an error fake.
    for k, v in zip(d.keys, d.values):
        key = None
        if isinstance(k, ast.Constant) and isinstance(k.value, str):
            key = k.value.lower()
        elif isinstance(k, ast.Name) and k.id.isupper():
            # only an ALL-CAPS constant name (e.g. SUCCESS); a lowercase `ok` is a runtime
            # variable key, too ambiguous to flag.
            key = k.id.lower()
        if key in SUCCESS_KEYS and _is_false(v):
            return True
    return False


def _call_is_fake_dict(c):
    # dict(success=False)
    if isinstance(c.func, ast.Name) and c.func.id == "dict":
        for kw in c.keywords:
            if kw.arg and kw.arg.lower() in SUCCESS_KEYS and _is_false(kw.value):
                return True
    return False


def _tuple_is_fake(t):
    if len(t.elts) != 2:
        return False
    a, b = t.elts
    # (data, err) / (x, error) / (payload, exc)
    if isinstance(b, ast.Name) and b.id.lower() in ERR_NAMES:
        return True
    # (None, "msg"): None paired with a string-literal message, or an error/message-ish name.
    # NOT (None, default) — a generic name is a legit optional-pair, not an error fake.
    if isinstance(a, ast.Constant) and a.value is None:
        if isinstance(b, ast.Constant) and isinstance(b.value, str):
            return True
        if isinstance(b, ast.Name) and (b.id.lower() in ERR_NAMES or any(t in b.id.lower() for t in ("msg", "message", "err", "error"))):
            return True
    return False


def _check_file(path):
    try:
        with open(path, encoding="utf-8") as fh:
            tree = ast.parse(fh.read(), filename=path)
    except (SyntaxError, UnicodeDecodeError, OSError) as exc:
        return None, f"{path}: {exc}"
    findings = []
    for node in ast.walk(tree):
        if not (isinstance(node, ast.Return) and node.value is not None):
            continue
        hit = _return_hit(node.value)
        if hit:
            findings.append(f"{path}:{node.lineno}: boundary error-fake [{hit}]")
    return findings, None


def _is_fake_dict_node(n):
    # a fake dict literal ({"success": False}) OR a dict(success=False) call
    return (isinstance(n, ast.Dict) and _dict_is_fake(n)) or (isinstance(n, ast.Call) and _call_is_fake_dict(n))


def _return_hit(v):
    # Inspect the return ROOT plus ONE level into a response constructor — NOT the whole
    # subtree, so a fake dict nested inside legitimate data
    # (`return {"items": [{"success": False}]}`) is not flagged.
    if isinstance(v, ast.Tuple):
        if _tuple_is_fake(v):
            return "error-tuple (data,err)/(None,msg)"
        # (body, status) form: return ({"success": False}, 400)
        for el in v.elts:
            if _is_fake_dict_node(el):
                return "fake dict in (body, status) tuple"
        return None
    if isinstance(v, ast.Dict) and _dict_is_fake(v):
        return "dict success/ok=False"
    if isinstance(v, ast.Call):
        if _call_is_fake_dict(v):
            return "dict(success=False)"
        # constructor-wrapped one level: JSONResponse({...}) / JSONResponse(dict(success=False))
        # / Response(content={...})
        for arg in list(v.args) + [kw.value for kw in v.keywords]:
            if _is_fake_dict_node(arg):
                return "fake dict (constructor-wrapped)"
    return None


def main(argv):
    if not argv:
        print("usage: lang-basics-ast-check.py <transport-path> [...]", file=sys.stderr)
        return 2
    walk_errs = []
    for p in argv:
        if not os.path.exists(p):
            print(f"lang-basics-ast: path not found: {p} — inconclusive", file=sys.stderr)
            return 2
        if os.path.isfile(p) and not p.endswith(".py"):
            print(f"lang-basics-ast: not a Python file: {p} — inconclusive", file=sys.stderr)
            return 2
        if os.path.isdir(p) and not any(_iter_py([p], onerror=walk_errs.append)):
            print(f"lang-basics-ast: no Python files under directory: {p} — inconclusive", file=sys.stderr)
            return 2
    files = list(_iter_py(argv, onerror=walk_errs.append))
    if walk_errs:
        print(f"lang-basics-ast: cannot read part of scope ({walk_errs[0]}) — inconclusive", file=sys.stderr)
        return 2
    if not files:
        print("lang-basics-ast: no Python files in scope — inconclusive", file=sys.stderr)
        return 2
    hits = 0
    for f in files:
        res, err = _check_file(f)
        if err is not None:
            print(f"lang-basics-ast: parse error: {err} — inconclusive", file=sys.stderr)
            return 2
        for line in res:
            print(f"lang-basics-ast smell: {line}")
            hits = 1
    return hits


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
