#!/usr/bin/env python3
"""Run this directory's pytest-style tests without installing pytest.

This is intentionally small and local to the CI fallback path. It implements
only the pytest subset used by test_gen_report.py: parametrize, raises,
tmp_path, monkeypatch, capsys, and skip/skipif handling.
"""

from __future__ import annotations

import contextlib
import importlib
import importlib.util
import inspect
import io
import os
import re
import sys
import tempfile
import traceback
import types
from pathlib import Path
from typing import Any, Callable


_NOT_SET = object()
_SKIP_KEY = "__pytestless_skip__"
_XFAIL_KEY = "__pytestless_xfail__"


class MarkDecorator:
    def __init__(self, name: str, reason: str = "", condition: bool = True):
        self.name = name
        self.reason = reason
        self.condition = condition

    def __call__(self, func: Callable) -> Callable:
        if not callable(func):
            raise TypeError(f"pytest.mark.{self.name} can only decorate callables")
        marks = list(getattr(func, "__pytestless_marks__", []))
        marks.append(self)
        setattr(func, "__pytestless_marks__", marks)
        return func


class ParamValue:
    def __init__(
        self,
        values: tuple[Any, ...],
        skip_reason: str | None = None,
        xfail_reason: str | None = None,
    ):
        self.values = values
        self.skip_reason = skip_reason
        self.xfail_reason = xfail_reason


class RaisesContext:
    def __init__(self, expected: type[BaseException], match: str | None = None):
        self.expected = expected
        self.match = match
        self.value: BaseException | None = None

    def __enter__(self) -> "RaisesContext":
        return self

    def __exit__(
        self,
        exc_type: type[BaseException] | None,
        exc: BaseException | None,
        tb: Any,
    ) -> bool:
        if exc_type is None or exc is None:
            raise AssertionError(f"expected {self.expected.__name__} to be raised")
        if not issubclass(exc_type, self.expected):
            return False
        if self.match and not re.search(self.match, str(exc)):
            raise AssertionError(
                f"exception message {str(exc)!r} does not match {self.match!r}"
            )
        self.value = exc
        return True


class Mark:
    def parametrize(
        self,
        argnames: str,
        argvalues: list[Any],
        **kwargs: Any,
    ) -> Callable:
        unsupported = set(kwargs) - {"ids"}
        if unsupported:
            names = ", ".join(sorted(unsupported))
            raise NotImplementedError(f"pytestless parametrize does not support {names}")
        names = [name.strip() for name in argnames.split(",") if name.strip()]

        def decorate(func: Callable) -> Callable:
            current = list(getattr(func, "__pytestless_parametrize__", []))
            current.append((names, argvalues))
            setattr(func, "__pytestless_parametrize__", current)
            return func

        return decorate

    def skip(self, *args: Any, reason: str = "") -> MarkDecorator:
        if args and callable(args[0]):
            return MarkDecorator("skip", reason or "skip")(args[0])
        if args and isinstance(args[0], str) and not reason:
            reason = args[0]
        return MarkDecorator("skip", reason or "skip")

    def skipif(self, condition: bool, *args: Any, reason: str = "") -> MarkDecorator:
        if args and isinstance(args[0], str) and not reason:
            reason = args[0]
        return MarkDecorator("skipif", reason or "skipif", bool(condition))

    def xfail(
        self,
        *args: Any,
        reason: str = "",
        condition: bool = True,
        **_kwargs: Any,
    ) -> MarkDecorator:
        remaining = list(args)
        if remaining and isinstance(remaining[0], bool):
            condition = remaining.pop(0)
        if remaining and callable(remaining[0]):
            return MarkDecorator("xfail", reason or "xfail", bool(condition))(
                remaining[0]
            )
        if remaining and isinstance(remaining[0], str) and not reason:
            reason = remaining[0]
        return MarkDecorator("xfail", reason or "xfail", bool(condition))

    def __getattr__(self, _name: str) -> Callable:
        raise NotImplementedError(f"pytestless runner does not support pytest.mark.{_name}")


def install_pytest_stub() -> None:
    stub = types.ModuleType("pytest")
    stub.mark = Mark()
    stub.raises = lambda expected, match=None: RaisesContext(expected, match)
    stub.param = make_pytest_param
    sys.modules["pytest"] = stub


def make_pytest_param(*values: Any, **kwargs: Any) -> ParamValue:
    unsupported = set(kwargs) - {"id", "marks"}
    if unsupported:
        names = ", ".join(sorted(unsupported))
        raise NotImplementedError(f"pytestless pytest.param does not support {names}")
    marks = kwargs.get("marks")
    return ParamValue(
        values,
        skip_reason_from_marks(marks),
        xfail_reason_from_marks(marks),
    )


class MonkeyPatch:
    def __init__(self) -> None:
        self._undo: list[Callable[[], None]] = []

    def setenv(self, name: str, value: str) -> None:
        old = os.environ.get(name, _NOT_SET)
        os.environ[name] = str(value)
        self._undo.append(lambda: self._restore_env(name, old))

    def delenv(self, name: str, raising: bool = True) -> None:
        old = os.environ.get(name, _NOT_SET)
        if old is _NOT_SET and raising:
            raise KeyError(name)
        os.environ.pop(name, None)
        self._undo.append(lambda: self._restore_env(name, old))

    def setattr(
        self,
        target: Any,
        name: str | Any,
        value: Any = _NOT_SET,
        raising: bool = True,
    ) -> None:
        if isinstance(target, str):
            if value is not _NOT_SET:
                raise TypeError(
                    "pytestless monkeypatch.setattr string form expects target, value"
                )
            target, attr_name = self._resolve_dotted_target(target)
            value = name
            name = attr_name
        if not isinstance(name, str) or value is _NOT_SET:
            raise TypeError("pytestless monkeypatch.setattr requires target, name, value")
        old = getattr(target, name, _NOT_SET)
        if old is _NOT_SET and raising:
            raise AttributeError(name)
        setattr(target, name, value)
        self._undo.append(lambda: self._restore_attr(target, name, old))

    def undo(self) -> None:
        for undo in reversed(self._undo):
            undo()
        self._undo.clear()

    @staticmethod
    def _resolve_dotted_target(target: str) -> tuple[Any, str]:
        module_name, sep, attr_name = target.rpartition(".")
        if not sep:
            raise TypeError("string target must be a dotted import path")
        module = importlib.import_module(module_name)
        return module, attr_name

    @staticmethod
    def _restore_env(name: str, old: Any) -> None:
        if old is _NOT_SET:
            os.environ.pop(name, None)
        else:
            os.environ[name] = old

    @staticmethod
    def _restore_attr(target: Any, name: str, old: Any) -> None:
        if old is _NOT_SET:
            delattr(target, name)
        else:
            setattr(target, name, old)


class CaptureFixture:
    def __init__(self) -> None:
        self._stdout = io.StringIO()
        self._stderr = io.StringIO()
        self._out_cm: contextlib.AbstractContextManager[Any] | None = None
        self._err_cm: contextlib.AbstractContextManager[Any] | None = None

    def start(self) -> None:
        self._out_cm = contextlib.redirect_stdout(self._stdout)
        self._err_cm = contextlib.redirect_stderr(self._stderr)
        self._out_cm.__enter__()
        self._err_cm.__enter__()

    def stop(self) -> None:
        if self._err_cm is not None:
            self._err_cm.__exit__(None, None, None)
            self._err_cm = None
        if self._out_cm is not None:
            self._out_cm.__exit__(None, None, None)
            self._out_cm = None

    def readouterr(self) -> types.SimpleNamespace:
        out = self._stdout.getvalue()
        err = self._stderr.getvalue()
        self._stdout.seek(0)
        self._stdout.truncate(0)
        self._stderr.seek(0)
        self._stderr.truncate(0)
        return types.SimpleNamespace(out=out, err=err)


def load_module(test_file: Path) -> types.ModuleType:
    sys.path.insert(0, str(test_file.parent))
    spec = importlib.util.spec_from_file_location(test_file.stem, test_file)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"cannot load {test_file}")
    module = importlib.util.module_from_spec(spec)
    sys.modules[test_file.stem] = module
    spec.loader.exec_module(module)
    return module


def expand_cases(func: Callable) -> list[tuple[str, dict[str, Any]]]:
    cases: list[tuple[str, dict[str, Any]]] = [("", {})]
    for names, values in getattr(func, "__pytestless_parametrize__", []):
        expanded: list[tuple[str, dict[str, Any]]] = []
        for prefix, base_kwargs in cases:
            for raw in values:
                skip_reason = None
                if isinstance(raw, ParamValue):
                    raw_values = raw.values
                    skip_reason = raw.skip_reason
                else:
                    raw_values = raw if len(names) != 1 else (raw,)
                if len(names) != 1 and not isinstance(raw_values, tuple):
                    raw_values = tuple(raw_values)
                if len(raw_values) != len(names):
                    raise RuntimeError(
                        f"{func.__name__}: parametrize expects {len(names)} values, "
                        f"got {len(raw_values)}"
                    )
                params = dict(zip(names, raw_values))
                if skip_reason:
                    params[_SKIP_KEY] = skip_reason
                if isinstance(raw, ParamValue) and raw.xfail_reason:
                    params[_XFAIL_KEY] = raw.xfail_reason
                label = ",".join(f"{k}={short(v)}" for k, v in params.items())
                expanded.append((f"{prefix}[{label}]", {**base_kwargs, **params}))
        cases = expanded
    return cases


def skip_reason_from_marks(marks: Any) -> str | None:
    return reason_from_marks(marks, {"skip", "skipif"})


def xfail_reason_from_marks(marks: Any) -> str | None:
    return reason_from_marks(marks, {"xfail"})


def reason_from_marks(marks: Any, names: set[str]) -> str | None:
    if marks is None:
        return None
    if not isinstance(marks, (list, tuple, set)):
        marks = [marks]
    for mark in marks:
        if isinstance(mark, MarkDecorator) and mark.condition and mark.name in names:
            return mark.reason
    return None


def skip_reason_for(func: Callable) -> str | None:
    return skip_reason_from_marks(getattr(func, "__pytestless_marks__", []))


def xfail_reason_for(func: Callable) -> str | None:
    return xfail_reason_from_marks(getattr(func, "__pytestless_marks__", []))


def short(value: Any) -> str:
    text = repr(value)
    return text if len(text) <= 48 else text[:45] + "..."


def call_test(func: Callable, params: dict[str, Any]) -> None:
    kwargs = dict(params)
    cleanups: list[Callable[[], None]] = []
    capsys: CaptureFixture | None = None

    for name in inspect.signature(func).parameters:
        if name in kwargs:
            continue
        if name == "tmp_path":
            tmp = tempfile.TemporaryDirectory(prefix=f"{func.__name__}-")
            cleanups.append(tmp.cleanup)
            kwargs[name] = Path(tmp.name)
        elif name == "monkeypatch":
            mp = MonkeyPatch()
            cleanups.append(mp.undo)
            kwargs[name] = mp
        elif name == "capsys":
            capsys = CaptureFixture()
            kwargs[name] = capsys
        else:
            raise RuntimeError(f"{func.__name__}: unsupported fixture {name!r}")

    try:
        if capsys is not None:
            capsys.start()
        func(**kwargs)
    finally:
        if capsys is not None:
            capsys.stop()
        for cleanup in reversed(cleanups):
            cleanup()


def iter_tests(module: types.ModuleType) -> list[tuple[str, Callable]]:
    tests: list[tuple[str, Callable]] = []
    for name, value in module.__dict__.items():
        if (
            name.startswith("test_")
            and inspect.isfunction(value)
            and value.__module__ == module.__name__
        ):
            tests.append((name, value))
        if (
            name.startswith("Test")
            and inspect.isclass(value)
            and value.__module__ == module.__name__
        ):
            for method_name, method in inspect.getmembers(value, inspect.isfunction):
                if method_name.startswith("test_") and inspect.isfunction(method):
                    test = bind_test_method(value, method_name, method)
                    tests.append((f"{name}.{method_name}", test))
    return tests


def bind_test_method(cls: type, method_name: str, method: Callable) -> Callable:
    signature = inspect.signature(method)
    parameters = list(signature.parameters.values())
    if parameters and parameters[0].name == "self":
        signature = signature.replace(parameters=parameters[1:])

    def wrapped(**kwargs: Any) -> Any:
        return getattr(cls(), method_name)(**kwargs)

    wrapped.__name__ = f"{cls.__name__}.{method_name}"
    wrapped.__module__ = method.__module__
    wrapped.__signature__ = signature  # type: ignore[attr-defined]
    setattr(
        wrapped,
        "__pytestless_parametrize__",
        list(getattr(method, "__pytestless_parametrize__", [])),
    )
    setattr(
        wrapped,
        "__pytestless_marks__",
        list(getattr(method, "__pytestless_marks__", [])),
    )
    return wrapped


def main(argv: list[str]) -> int:
    if len(argv) != 2:
        print(f"usage: {Path(argv[0]).name} TEST_FILE", file=sys.stderr)
        return 2

    install_pytest_stub()
    module = load_module(Path(argv[1]).resolve())
    tests = iter_tests(module)
    failures = 0
    skipped = 0
    xfailed = 0
    total = 0

    for name, func in tests:
        for suffix, params in expand_cases(func):
            total += 1
            case_name = f"{name}{suffix}"
            skip_reason = params.pop(_SKIP_KEY, None) or skip_reason_for(func)
            xfail_reason = params.pop(_XFAIL_KEY, None) or xfail_reason_for(func)
            if skip_reason:
                skipped += 1
                print(f"SKIP {case_name}: {skip_reason}")
                continue
            try:
                call_test(func, params)
                if xfail_reason:
                    failures += 1
                    print(f"XPASS {case_name}: {xfail_reason}", file=sys.stderr)
                    continue
                print(f"PASS {case_name}")
            except KeyboardInterrupt:
                raise
            except BaseException:
                if xfail_reason:
                    xfailed += 1
                    print(f"XFAIL {case_name}: {xfail_reason}")
                    continue
                failures += 1
                print(f"FAIL {case_name}", file=sys.stderr)
                traceback.print_exc()

    passed = total - failures - skipped - xfailed
    if total == 0:
        print("pytestless summary: passed=0 failed=1 total=0", file=sys.stderr)
        print("ERROR: no tests collected", file=sys.stderr)
        return 1
    if passed == 0:
        print(
            "pytestless summary: "
            f"passed=0 failed={failures} skipped={skipped} "
            f"xfailed={xfailed} total={total}",
            file=sys.stderr,
        )
        print("ERROR: no tests executed", file=sys.stderr)
        return 1
    print(
        "pytestless summary: "
        f"passed={passed} failed={failures} skipped={skipped} "
        f"xfailed={xfailed} total={total}"
    )
    return 1 if failures else 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
