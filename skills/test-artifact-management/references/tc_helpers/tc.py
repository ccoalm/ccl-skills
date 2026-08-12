"""
TC ID helper for pytest.

Link a test to one or more TC IDs using the `@pytest.mark.tc(...)` marker.
Recorded at collection time, so `@skip`, `@skipif`, `xfail`, and fixture
failures all map to Bitable status correctly:

    @pytest.mark.tc("TC-SY-001")
    @pytest.mark.skipif(sys.platform != "linux", reason="requires linux")
    def test_login_success():
        assert ...

    @pytest.mark.tc("TC-SY-001", "TC-SY-002")
    def test_bulk_import_partial_failure():
        ...

For TC IDs computed at runtime (property-based tests, ID derived from input),
the in-body `tc("TC-...")` form is available — it records only when the body
actually runs, so skipped tests are not covered:

    def test_dynamic():
        tc(decide_tc_id())
        ...

Each registration appends one JSONL line to `test/results/tc-map.jsonl`
(configurable via `TC_SIDECAR` env). gen_report.py joins JUnit XML against
the sidecar by pytest nodeid (e.g. `tests/test_auth.py::test_login_success`).

## Install

1. Drop this file at `<project>/test/tc.py` (or anywhere on pythonpath).
2. In pytest config (`pyproject.toml` or `pytest.ini`), make it importable and
   register it as a plugin:

       [tool.pytest.ini_options]
       pythonpath = ["test"]
       addopts = ["-p", "tc"]

   Or in `pytest.ini`:

       [pytest]
       pythonpath = test
       addopts = -p tc

3. In test files: `import pytest` and use `@pytest.mark.tc(...)`. For the
   rare dynamic-ID case, `from tc import tc` and call `tc(...)` in the body.
   Markers and in-body calls compose — gen_report.py merges duplicates.

4. The Makefile `test` target truncates the sidecar before each run (so
   deleted tests do not leave stale entries).

5. Set `TC_SIDECAR_STRICT=1` in CI so sidecar write failures fail the test
   (otherwise a permission/disk error silently leaves Bitable stale while
   CI passes).
"""

from __future__ import annotations

import json
import os
import threading
from pathlib import Path

import pytest

_lock = threading.Lock()


def _sidecar_path() -> Path:
    return Path(os.environ.get("TC_SIDECAR", "test/results/tc-map.jsonl"))


def _append_entry(test_name: str, ids: list[str]) -> None:
    """Append one JSONL line for (test_name, ids). Safe under thread parallelism.

    Best-effort by default (CI sidecar write failures don't fail the test).
    Set TC_SIDECAR_STRICT=1 (recommended in CI) to raise on write failure —
    otherwise a permissions/disk error silently turns linked tests into
    untracked tests and Bitable goes stale while CI passes.
    """
    if not ids or not test_name:
        return
    path = _sidecar_path()
    line = json.dumps({"test": test_name, "tc_ids": list(ids)}, ensure_ascii=False)
    strict = os.environ.get("TC_SIDECAR_STRICT", "").lower() in ("1", "true", "yes")
    try:
        with _lock:
            path.parent.mkdir(parents=True, exist_ok=True)
            with path.open("a", encoding="utf-8") as f:
                f.write(line + "\n")
    except OSError:
        if strict:
            raise


def _current_test_nodeid() -> str:
    raw = os.environ.get("PYTEST_CURRENT_TEST", "")
    return raw.split(" ")[0] if raw else ""


def tc(*ids: str) -> None:
    """Record TC IDs at runtime from inside a test body. Use only when the IDs
    are computed (property-based tests, parameterised inputs that produce
    different TCs per run). For static TC mapping use @pytest.mark.tc(...).

    Skipped tests / fixture failures don't reach the body, so this form
    cannot register them — the marker form is the answer for those cases.
    """
    if not ids:
        return
    _append_entry(_current_test_nodeid(), list(ids))


# ── pytest plugin: marker registration + collection-time sidecar write ──────

def pytest_configure(config):
    config.addinivalue_line(
        "markers",
        "tc(*ids): link this test to one or more TC IDs (e.g. @pytest.mark.tc(\"TC-SY-001\")). "
        "Recorded at collection time so @skip / fixture failures still register correctly.",
    )


def pytest_collection_modifyitems(config, items):
    """Record TC IDs from @pytest.mark.tc markers at collection time.
    This catches @skip / @skipif / setup-failure cases (the test body never
    runs in those, so the in-body tc() call wouldn't be reached)."""
    for item in items:
        ids: list[str] = []
        for marker in item.iter_markers(name="tc"):
            for arg in marker.args:
                if isinstance(arg, str) and arg:
                    ids.append(arg)
        if ids:
            _append_entry(item.nodeid, ids)
