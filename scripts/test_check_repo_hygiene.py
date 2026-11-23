#!/usr/bin/env python3
"""Unit and integration tests for scripts/check-repo-hygiene.py."""

from __future__ import annotations

import hashlib
import importlib.util
import json
import os
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

SCRIPT = Path(__file__).with_name("check-repo-hygiene.py")
REPO_ROOT = SCRIPT.resolve().parent.parent

SPEC = importlib.util.spec_from_file_location("check_repo_hygiene", SCRIPT)
assert SPEC is not None and SPEC.loader is not None
MODULE = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = MODULE
SPEC.loader.exec_module(MODULE)


def _git_env() -> dict[str, str]:
    env = MODULE._clean_git_env()
    return env


def _make_git_repo(sandbox: Path, files: dict[str, str | bytes]) -> Path:
    root = sandbox / "repo"
    root.mkdir(parents=True, exist_ok=True)
    env = _git_env()
    subprocess.run(["git", "init", "-q", "-b", "main", str(root)], env=env, check=True)
    for rel, content in files.items():
        path = root / rel
        path.parent.mkdir(parents=True, exist_ok=True)
        if isinstance(content, bytes):
            path.write_bytes(content)
        else:
            path.write_text(content, encoding="utf-8")
    subprocess.run(["git", "-C", str(root), "add", "-A"], env=env, check=True)
    return root


def _canonical_git_env_file(
    func_name: str,
    extra_routing: tuple[str, ...] = (),
    omit_config: tuple[str, ...] = (),
) -> str:
    routing = tuple(sorted(MODULE.REQUIRED_GIT_ROUTING_KEYS)) + extra_routing
    config = tuple(k for k in sorted(MODULE.REQUIRED_GIT_CONFIG_KEYS) if k not in omit_config)
    prefixes = MODULE.REQUIRED_GIT_PREFIXES
    return (
        f"GIT_REPOSITORY_ROUTING_ENV = {routing!r}\n"
        f"GIT_CONFIG_ROUTING_ENV = {config!r}\n"
        f"GIT_CONFIG_ROUTING_ENV_PREFIXES = {prefixes!r}\n"
        f"def {func_name}(env=None):\n"
        "    d = dict(env or {})\n"
        "    for k in tuple(d):\n"
        "        if k in GIT_REPOSITORY_ROUTING_ENV or k in GIT_CONFIG_ROUTING_ENV or k.startswith(GIT_CONFIG_ROUTING_ENV_PREFIXES):\n"
        "            d.pop(k, None)\n"
        "    return d\n"
    )


def _minimal_clean_repo_files() -> dict[str, str | bytes]:
    return {
        "scripts/select-affected-tests.py": _canonical_git_env_file("_clean_git_env"),
        "skills/code-review/scripts/review_gate.py": _canonical_git_env_file("git_environment"),
        "skills/skill-extraction-workflow/scripts/shared_git_surface_gate.py": _canonical_git_env_file(
            "git_environment"
        ),
        "scripts/_repo_text.py": (
            "def display(text: str) -> str:\n"
            "    escaped = text.replace('\\\\', '\\\\\\\\')\n"
            "    return ''.join(ch if ch.isprintable() else repr(ch)[1:-1] for ch in escaped)\n"
        ),
        "scripts/check-markdown-links.py": "from _repo_text import display\n",
        "scripts/check-public-sanitization.py": "from _repo_text import display\n",
        "scripts/check-repo-hygiene.py": "from _repo_text import display\n",
        "scripts/check-spec-references.py": "from _repo_text import display\n",
        "Makefile": (
            "test: test-repo-gates test-regressions-fast\n"
            "test-repo-gates:\n"
            "\tbash scripts/run-parallel-suites.sh --label repo_gates scripts/test_alpha.py hooks/test_beta.sh\n"
            "\tpython3 -m unittest eval.test_gamma\n"
            "\tbash skills/code-review/scripts/test_review_gate_abort_leak.sh\n"
            "test-regressions-fast:\n"
            "\tbash skills/skill-extraction-workflow/scripts/test_check_ccl_regressions.sh --fast\n"
            "test-verify-sandbox:\n"
            "\tbash scripts/verify-sandbox/test.sh\n"
        ),
        ".github/workflows/ci.yml": (
            "name: CI\n"
            "jobs:\n"
            "  repository-gates:\n"
            "    steps:\n"
            "      - run: python3 scripts/test_ci_only.py\n"
            "      - run: make test-repo-gates\n"
            "  npm-packages:\n"
            "    steps:\n"
            "      - working-directory: packages/ccl-skills-npm\n"
            "        run: npm test\n"
            "      - working-directory: packages/ccl-skills-npm\n"
            "        run: npm run test:pack\n"
        ),
        "skills/skill-extraction-workflow/scripts/test_check_ccl_regressions.sh": (
            "#!/usr/bin/env bash\n"
            "fast_tests=(\n"
            "  test_reg_one.sh\n"
            ")\n"
            "heavy_tests=(\n"
            "  test_reg_two.sh\n"
            ")\n"
        ),
        "skills/skill-extraction-workflow/scripts/test_reg_one.sh": "#!/usr/bin/env bash\nexit 0\n",
        "skills/skill-extraction-workflow/scripts/test_reg_two.sh": "#!/usr/bin/env bash\nexit 0\n",
        "packages/ccl-skills-npm/package.json": json.dumps(
            {
                "name": "@ccoalm/ccl-skills",
                "scripts": {
                    "test": "node scripts/test-build-modes.mjs && node --test test/*.test.mjs",
                    "test:pack": "node --test scripts/check-pack-suite.mjs",
                },
            }
        ),
        "packages/ccl-skills-npm/scripts/test-build-modes.mjs": "export {};\n",
        "packages/ccl-skills-npm/scripts/check-pack-suite.mjs": "export {};\n",
        "packages/ccl-skills-npm/test/unit.test.mjs": "export {};\n",
        "scripts/test_alpha.py": "assert True\n",
        "scripts/test_ci_only.py": "assert True\n",
        "hooks/test_beta.sh": "#!/usr/bin/env bash\nexit 0\n",
        "eval/test_gamma.py": "assert True\n",
        "scripts/verify-sandbox/test.sh": "#!/usr/bin/env bash\nexit 0\n",
        "skills/code-review/scripts/test_review_gate_abort_leak.sh": (
            "#!/usr/bin/env bash\npython3 skills/code-review/scripts/test_abort_leak_readiness.py\n"
        ),
        "skills/code-review/scripts/test_abort_leak_readiness.py": "assert True\n",
    }


class RepoHygieneTest(unittest.TestCase):
    def test_live_repository_passes_all_hygiene_checks(self) -> None:
        proc = subprocess.run(
            [sys.executable, str(SCRIPT), str(REPO_ROOT)],
            capture_output=True,
            text=True,
            env=_git_env(),
        )
        self.assertEqual(proc.returncode, 0, proc.stderr)
        self.assertIn("repo_hygiene_ok", proc.stdout)

    def test_synthetic_clean_repo_passes_and_spares_non_test_surfaces(self) -> None:
        sandbox = Path(self.enterContext(tempfile.TemporaryDirectory()))
        files = _minimal_clean_repo_files()
        # Spare cases: JSON fixture named test_*, specs/ test script, and MANIFEST-sealed eval/evidence .py with \A
        sealed_py = b'"""legacy \\A escape in sealed archive"""\nx = 1\n'
        sealed_sha = hashlib.sha256(sealed_py).hexdigest()
        files["hooks/test_fixture.expected.json"] = '{"ok": true}\n'
        files["specs/001-demo/evidence/test_red_probe.py"] = 's = "\\e"\n'
        files["eval/evidence/archive-1/recompute.py"] = sealed_py
        files["eval/evidence/archive-1/test_helper.sh"] = "#!/usr/bin/env bash\n"
        files["eval/evidence/archive-1/MANIFEST.json"] = json.dumps(
            {"files_sha256": {"recompute.py": sealed_sha}}
        )
        root = _make_git_repo(sandbox, files)
        self.assertEqual(MODULE.run_all_checks(root), [])

    def test_git_env_parity_catches_missing_extra_and_unscrubbed_constants(self) -> None:
        sandbox = Path(self.enterContext(tempfile.TemporaryDirectory()))
        files = _minimal_clean_repo_files()
        # Drop GIT_TEMPLATE_DIR from shared_git_surface_gate.py
        bad_gate = _canonical_git_env_file(
            "git_environment", omit_config=("GIT_TEMPLATE_DIR",)
        )
        files["skills/skill-extraction-workflow/scripts/shared_git_surface_gate.py"] = bad_gate
        # Extra key in review_gate.py
        files["skills/code-review/scripts/review_gate.py"] = _canonical_git_env_file(
            "git_environment", extra_routing=("GIT_CUSTOM_EXTRA",)
        )
        # Function in select-affected-tests.py forgets GIT_CONFIG_ROUTING_ENV
        files["scripts/select-affected-tests.py"] = _canonical_git_env_file(
            "_clean_git_env"
        ).replace(" or k in GIT_CONFIG_ROUTING_ENV", "")
        root = _make_git_repo(sandbox, files)
        findings = MODULE.check_git_env_parity(root)
        joined = "\n".join(findings)
        self.assertIn("git-env-missing-config-keys", joined)
        self.assertIn("git-env-routing-drift", joined)
        self.assertIn("git-env-unscrubbed-constant", joined)

    def test_display_sharing_catches_inline_duplicate_and_missing_import(self) -> None:
        self.assertIn("scripts/check-repo-hygiene.py", MODULE.DISPLAY_CALLERS)
        sandbox = Path(self.enterContext(tempfile.TemporaryDirectory()))
        files = _minimal_clean_repo_files()
        files["scripts/check-markdown-links.py"] = "def display(x):\n    return x\n"
        files["scripts/check-repo-hygiene.py"] = "def display(x):\n    return x\n"
        root = _make_git_repo(sandbox, files)
        findings = MODULE.check_display_sharing(root)
        joined = "\n".join(findings)
        self.assertIn("display-inline-duplicate: scripts/check-markdown-links.py", joined)
        self.assertIn("display-missing-shared-import: scripts/check-markdown-links.py", joined)
        self.assertIn("display-inline-duplicate: scripts/check-repo-hygiene.py", joined)
        self.assertIn("display-missing-shared-import: scripts/check-repo-hygiene.py", joined)

    def test_registration_catches_orphan_tests_dead_makefile_targets_and_stale_delegates(self) -> None:
        sandbox = Path(self.enterContext(tempfile.TemporaryDirectory()))
        files = _minimal_clean_repo_files()
        files["Makefile"] = (
            str(files["Makefile"])
            + "dead-target:\n\tpython3 scripts/test_in_dead_target.py\n"
        )
        files["scripts/test_orphan.py"] = "assert True\n"
        files["hooks/test_orphan.sh"] = "#!/usr/bin/env bash\n"
        files["packages/ccl-skills-npm/scripts/orphan.test.mjs"] = "export {};\n"
        files["scripts/test_in_dead_target.py"] = "assert True\n"
        # Break delegate reference in parent
        files["skills/code-review/scripts/test_review_gate_abort_leak.sh"] = "#!/usr/bin/env bash\necho no child\n"
        root = _make_git_repo(sandbox, files)
        tracked = set(MODULE.tracked_paths(root))
        findings = MODULE.check_test_registration(root, tracked)
        joined = "\n".join(findings)
        self.assertIn("unregistered-test-file: scripts/test_orphan.py", joined)
        self.assertIn("unregistered-test-file: hooks/test_orphan.sh", joined)
        self.assertIn("unregistered-test-file: packages/ccl-skills-npm/scripts/orphan.test.mjs", joined)
        self.assertIn("unregistered-test-file: scripts/test_in_dead_target.py", joined)
        self.assertIn("test-registration-unreferenced-delegate", joined)

        cap_findings = MODULE.check_test_registration(
            root,
            tracked,
            opt_in_suites={"a": "t1", "b": "t2", "c": "t3"},
        )
        self.assertTrue(any("test-registration-cap-exceeded" in f for f in cap_findings))

    def test_python_warnings_catches_invalid_escape_and_tampered_manifest_archive(self) -> None:
        sandbox = Path(self.enterContext(tempfile.TemporaryDirectory()))
        files = _minimal_clean_repo_files()
        files["scripts/has_escape_warning.py"] = 'DOC = "bad \\e escape"\n'
        files["eval/evidence/tampered/recompute.py"] = 'DOC = "bad \\A escape"\n'
        files["eval/evidence/tampered/MANIFEST.json"] = json.dumps(
            {"files_sha256": {"recompute.py": "0" * 64}}
        )
        root = _make_git_repo(sandbox, files)
        tracked = set(MODULE.tracked_paths(root))
        findings = MODULE.check_python_warnings(root, tracked)
        joined = "\n".join(findings)
        self.assertIn("scripts/has_escape_warning.py", joined)
        self.assertIn("eval/evidence/tampered/recompute.py", joined)


if __name__ == "__main__":
    unittest.main()
