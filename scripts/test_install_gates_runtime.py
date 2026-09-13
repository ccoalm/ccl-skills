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


if __name__ == '__main__':
    unittest.main()
