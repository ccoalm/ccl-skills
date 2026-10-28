#!/usr/bin/env python3
"""Verify the installed owner-dispatch dependency closure on disposable repos."""
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]


class InstalledRuntimeTests(unittest.TestCase):
    def test_installed_normalizer_and_contract(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary).resolve()
            source, target = root / 'source', root / 'target'
            for relative in ('scripts/install-gates.sh',
                             'scripts/owner-dispatch/owner-dispatch.sh',
                             'hooks/host-input.py'):
                destination = source / relative
                destination.parent.mkdir(parents=True, exist_ok=True)
                shutil.copyfile(ROOT / relative, destination)
            # A baseline run uses the original installer against the same source
            # assets and assertions, isolating the distribution-list defect.
            if os.environ.get('BASELINE_INSTALL_GATES') == '1':
                original = subprocess.check_output(
                    ['git', 'show', 'HEAD:scripts/install-gates.sh'], cwd=ROOT)
                (source / 'scripts/install-gates.sh').write_bytes(original)
            env = dict(os.environ, GIT_CONFIG_GLOBAL='/dev/null',
                       GIT_CONFIG_SYSTEM='/dev/null')
            for key in ('GIT_DIR', 'GIT_COMMON_DIR', 'GIT_WORK_TREE', 'GIT_INDEX_FILE'):
                env.pop(key, None)
            subprocess.run(['git', 'init', '-q', '-b', 'dev', str(target)],
                           env=env, check=True, capture_output=True)
            result = subprocess.run(['bash', str(source / 'scripts/install-gates.sh'),
                                     str(target), '--gates', 'owner-dispatch',
                                     '--ci-platform', 'none'], env=env,
                                    capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stderr)
            helper = target / 'hooks/host-input.py'
            self.assertTrue(helper.is_file(), 'installed owner engine is missing its normalizer')
            self.assertEqual(helper.read_bytes(), (ROOT / 'hooks/host-input.py').read_bytes())
            self.assertIn('install-gates:machinery', (target / 'hooks/AGENTS.md').read_text())
            parsed = subprocess.run(['python3', str(helper), 'paths'], input=json.dumps({
                'cwd': str(target), 'tool_name': 'apply_patch', 'tool_input': {
                    'command': '*** Begin Patch\n*** Delete File: file.py\n*** End Patch'}}),
                text=True, capture_output=True, check=True)
            self.assertEqual(json.loads(parsed.stdout), {
                'paths': [str(target / 'file.py')], 'malformed_patch': False})

    # owner-dispatch is in-session only: a committed per-change map made parallel merge
    # requests conflict, so the installer emits no CI job and no map key for it.
    @staticmethod
    def _env():
        env = dict(os.environ, GIT_CONFIG_GLOBAL='/dev/null', GIT_CONFIG_SYSTEM='/dev/null')
        for key in ('GIT_DIR', 'GIT_COMMON_DIR', 'GIT_WORK_TREE', 'GIT_INDEX_FILE'):
            env.pop(key, None)
        return env

    def _repo(self, root):
        target = Path(root).resolve() / 'target'
        subprocess.run(['git', 'init', '-q', '-b', 'dev', str(target)],
                       env=self._env(), check=True, capture_output=True)
        return target

    def _install(self, target, *args):
        result = subprocess.run(['bash', str(ROOT / 'scripts/install-gates.sh'), str(target), *args],
                                env=self._env(), capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertTrue((target / 'scripts/owner-dispatch/owner-dispatch.sh').is_file())
        self.assertTrue((target / 'hooks/host-input.py').is_file())
        self.assertNotIn('ci_artifact', json.loads((target / '.owner-dispatch.json').read_text()))
        return result

    def test_full_install_has_no_owner_dispatch_job(self):
        with tempfile.TemporaryDirectory() as temporary:
            target = self._repo(temporary)
            self._install(target)
            text = (target / 'ci/agent-gates.gitlab-ci.yml').read_text()
            self.assertIn('\nagent-contract-coverage:\n', text)
            self.assertIn('\ncontrol-plane:\n', text)
            self.assertNotIn('\nowner-dispatch:\n', text)
            self.assertNotIn('owner-dispatch.sh ci', text)

    def test_owner_dispatch_alone_writes_no_ci_fragment(self):
        with tempfile.TemporaryDirectory() as temporary:
            target = self._repo(temporary)
            result = self._install(target, '--gates', 'owner-dispatch')
            self.assertFalse((target / 'ci/agent-gates.gitlab-ci.yml').exists())
            self.assertNotIn('include: { local: ci/agent-gates', result.stdout)

    def test_warns_on_a_kept_owner_dispatch_ci_job(self):
        # An edited fragment is left untouched, so a job calling the removed subcommand
        # would fail on every run against the refreshed engine.
        with tempfile.TemporaryDirectory() as temporary:
            target = self._repo(temporary)
            (target / 'ci').mkdir()
            (target / 'ci/agent-gates.gitlab-ci.yml').write_text(
                'owner-dispatch:\n  script:\n    - bash scripts/owner-dispatch/owner-dispatch.sh ci --base x\n')
            result = self._install(target)
            self.assertIn("ci/agent-gates.gitlab-ci.yml still runs 'owner-dispatch.sh ci'",
                          result.stderr)

    def test_no_stale_job_warning_on_a_clean_target(self):
        with tempfile.TemporaryDirectory() as temporary:
            result = self._install(self._repo(temporary))
            self.assertNotIn('still runs', result.stderr)

if __name__ == '__main__':
    unittest.main()
