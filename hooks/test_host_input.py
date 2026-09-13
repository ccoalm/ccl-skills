#!/usr/bin/env python3
"""Host boundary regressions; all repositories and transcripts are synthetic."""
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]


class HostInputTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name).resolve()
        self.env = dict(os.environ, TMPDIR=str(self.root), GIT_CONFIG_GLOBAL='/dev/null',
                        GIT_CONFIG_SYSTEM='/dev/null')
        for key in ('GIT_DIR', 'GIT_WORK_TREE', 'GIT_INDEX_FILE', 'GIT_COMMON_DIR'):
            self.env.pop(key, None)
        self.repo = self.root / 'primary'
        self.git('init', '-q', '-b', 'main', str(self.repo), cwd=self.root)
        (self.repo / '.worktree-only').touch()
        (self.repo / 'src').mkdir()
        (self.repo / 'src/file.py').write_text('before\n')
        (self.repo / '.owner-dispatch.json').write_text(json.dumps({
            'enabled': True, 'strict': True, 'product_globs': ['src/**']}))
        self.git('add', '.')
        self.git('-c', 'user.email=test@example.invalid', '-c', 'user.name=Test',
                 'commit', '-qm', 'fixture')
        self.wt = self.root / 'linked'
        self.git('worktree', 'add', '-q', '-b', 'feature', str(self.wt))

    def git(self, *args, cwd=None):
        return subprocess.run(['git', *args], cwd=cwd or self.repo, env=self.env,
                              check=True, capture_output=True)

    def run_hook(self, name, payload, *args):
        result = subprocess.run(['bash', str(ROOT / name), *args], input=json.dumps(payload),
                                text=True, capture_output=True, cwd=self.root, env=self.env)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stderr, '')
        return json.loads(result.stdout) if result.stdout else {}

    def patch(self, text, cwd=None):
        return {'tool_name': 'apply_patch', 'tool_input': {'command': text},
                'cwd': str(cwd or self.repo), 'session_id': 'synthetic'}

    def decision(self, result):
        return result.get('hookSpecificOutput', {}).get('permissionDecision')

    def test_patch_targets_receive_isolation_policy(self):
        cases = [
            ('add', '*** Add File: new/file.py\n+new', self.repo, 'deny'),
            ('delete', '*** Delete File: src/file.py', self.repo, 'deny'),
            ('update', '*** Update File: src/file.py\n@@\n-before\n+after', self.repo, 'deny'),
            ('linked', '*** Add File: new.py\n+new', self.wt, None),
            ('multi', f'*** Add File: safe.py\n+new\n*** Delete File: {self.repo}/src/file.py', self.wt, 'deny'),
            ('move-destination', f'*** Update File: src/file.py\n*** Move to: {self.repo}/new.py\n@@\n-before\n+after', self.wt, 'deny'),
        ]
        for label, body, cwd, expected in cases:
            with self.subTest(label=label):
                value = self.run_hook('hooks/guard-edit-isolation.sh', self.patch(
                    '*** Begin Patch\n' + body + '\n*** End Patch', cwd))
                self.assertEqual(self.decision(value), expected)

    def test_unparseable_patch_denies_and_patch_text_is_never_executed(self):
        for patch in ('not a patch', '*** Begin Patch\n*** Add File: \n+x\n*** End Patch',
                      '*** Begin Patch\n*** Delete File: src/file.py'):
            with self.subTest(patch=patch):
                self.assertEqual(self.decision(self.run_hook('hooks/guard-edit-isolation.sh',
                                                            self.patch(patch))), 'deny')
        marker = self.root / 'executed'
        body = f'*** Begin Patch\n*** Add File: $(touch {marker})\n+x\n*** End Patch'
        self.run_hook('hooks/guard-edit-isolation.sh', self.patch(body))
        self.assertFalse(marker.exists())

    def test_owner_dispatch_checks_later_patch_targets(self):
        payload = self.patch('*** Begin Patch\n*** Add File: README.md\n+x\n'
                             '*** Delete File: src/file.py\n*** End Patch')
        self.assertEqual(self.decision(self.run_hook('scripts/owner-dispatch/owner-dispatch.sh',
                                                    payload, 'pretool')), 'deny')
        self.git('config', 'user.email', 'test@example.invalid')
        self.git('config', 'user.name', 'Test')
        subprocess.run(['bash', str(ROOT / 'scripts/owner-dispatch/owner-dispatch.sh'),
                        'record', '--owners', 'testing-strategy'], cwd=self.repo,
                       env=self.env, check=True, capture_output=True)
        self.assertEqual(self.run_hook('scripts/owner-dispatch/owner-dispatch.sh', payload, 'pretool'), {})

    def transcript(self, events):
        path = self.root / 'transcript.jsonl'
        path.write_text(''.join(json.dumps(event) + '\n' for event in events))
        return str(path)

    def call(self, name, args, call_id='load'):
        return {'type': 'response_item', 'payload': {'type': 'function_call',
                'name': name, 'arguments': json.dumps(args), 'call_id': call_id}}

    def output(self, output, call_id='load'):
        return {'type': 'response_item', 'payload': {'type': 'function_call_output',
                'call_id': call_id, 'output': output}}

    def test_codex_dispatch_reminder_is_advisory_and_completed_read_satisfies_it(self):
        skill = self.repo / 'skills/multi-agent-delegation/SKILL.md'
        skill.parent.mkdir(parents=True)
        skill.write_text('---\nname: multi-agent-delegation\n---\n# Loaded owner\n')
        request = self.call('exec_command', {'cmd': f'cat {skill}'})
        for label, events, expect_context in [
            ('cold', [], True), ('pending', [request], True),
            ('failed', [request, self.output('Process exited with code 1\nOutput:\nfailed')], True),
            ('mismatch', [request, self.output('Process exited with code 0\nOutput:\n' + skill.read_text(), 'other')], True),
            ('empty', [request, self.output('Process exited with code 0\nOutput:\n')], True),
            ('unrelated-output', [request, self.output('Process exited with code 0\nOutput:\nhello')], True),
            ('truncated', [request, self.output('Process exited with code 0\nOutput:\nWarning: truncated output\n' + skill.read_text())], True),
            ('completed', [request, self.output('Process exited with code 0\nOutput:\n' + skill.read_text())], False),
        ]:
            with self.subTest(label=label):
                payload = {'tool_name': 'spawn_agent', 'session_id': label,
                           'transcript_path': self.transcript(events)}
                value = self.run_hook('hooks/guard-delegation-owner.sh', payload)
                specific = value.get('hookSpecificOutput', {})
                self.assertNotIn('permissionDecision', specific)
                self.assertEqual(bool(specific.get('additionalContext')), expect_context)
                self.assertEqual(self.run_hook('hooks/guard-delegation-owner.sh', payload), {})

    def test_codex_patch_transcript_triggers_extraction_backstop(self):
        marker = self.repo / 'skills/skill-extraction-workflow/SKILL.md'
        marker.parent.mkdir(parents=True)
        marker.write_text('---\nname: skill-extraction-workflow\n---\n# Extraction\n')
        patch = f'*** Begin Patch\n*** Add File: {self.repo}/hooks/new.sh\n+echo x\n*** End Patch'
        event = {'type': 'response_item', 'payload': {'type': 'custom_tool_call',
                 'name': 'apply_patch', 'call_id': 'patch', 'input': patch}}
        value = self.run_hook('hooks/skill-extraction-gate-stop.sh', {
            'session_id': 'stop-patch', 'cwd': str(self.repo),
            'transcript_path': self.transcript([event])})
        self.assertEqual(value.get('decision'), 'block')

    def test_owner_dispatch_codex_completed_read_evidence(self):
        skill = self.repo / 'skills/testing-strategy/SKILL.md'
        skill.parent.mkdir(parents=True)
        skill.write_text('---\nname: testing-strategy\n---\n# Owner\n')
        request = self.call('exec_command', {'cmd': f'cat {skill}'})
        for completed, expected in ((False, 3), (True, 0)):
            events = [request]
            if completed:
                events.append(self.output('Process exited with code 0\nOutput:\n' + skill.read_text()))
            path = self.transcript(events)
            result = subprocess.run(['bash', str(ROOT / 'scripts/owner-dispatch/owner-dispatch.sh'),
                                     'verify-invocations', '--owners', 'testing-strategy',
                                     '--transcript', path, '--empty-is-missing'],
                                    env=self.env, capture_output=True, text=True)
            self.assertEqual(result.returncode, expected, result.stdout + result.stderr)

    def test_owner_patch_move_destination_and_advisory_output(self):
        patch = self.patch('*** Begin Patch\n*** Update File: README.md\n'
                           '*** Move to: src/new.py\n@@\n-before\n+after\n*** End Patch')
        self.assertEqual(self.decision(self.run_hook('scripts/owner-dispatch/owner-dispatch.sh', patch, 'pretool')), 'deny')
        config = self.repo / '.owner-dispatch.json'
        value = json.loads(config.read_text())
        value['strict'] = False
        config.write_text(json.dumps(value))
        result = self.run_hook('scripts/owner-dispatch/owner-dispatch.sh', patch, 'pretool')
        self.assertNotIn('permissionDecision', result['hookSpecificOutput'])
        self.assertIn('additionalContext', result['hookSpecificOutput'])

    def test_owner_patch_deny_wins_over_an_earlier_advisory(self):
        config = self.wt / '.owner-dispatch.json'
        value = json.loads(config.read_text())
        value['strict'] = False
        config.write_text(json.dumps(value))
        soft = f'*** Add File: {self.wt}/src/soft.py\n+new'
        hard = f'*** Delete File: {self.repo}/src/file.py'
        advisory = self.run_hook('scripts/owner-dispatch/owner-dispatch.sh', self.patch(
            f'*** Begin Patch\n{soft}\n*** End Patch'), 'pretool')
        self.assertIn('additionalContext', advisory['hookSpecificOutput'])
        self.assertEqual(self.decision(self.run_hook('scripts/owner-dispatch/owner-dispatch.sh',
                         self.patch(f'*** Begin Patch\n{hard}\n*** End Patch'), 'pretool')), 'deny')
        for first, second in ((soft, hard), (hard, soft)):
            with self.subTest(first=first):
                result = self.run_hook('scripts/owner-dispatch/owner-dispatch.sh', self.patch(
                    f'*** Begin Patch\n{first}\n{second}\n*** End Patch'), 'pretool')
                self.assertEqual(self.decision(result), 'deny')

    def test_claude_isolation_survives_missing_python_or_helper(self):
        isolated = self.root / 'isolated'
        isolated.mkdir()
        copy = isolated / 'guard-edit-isolation.sh'
        copy.write_text((ROOT / 'hooks/guard-edit-isolation.sh').read_text())
        commands = self.root / 'no-python'
        commands.mkdir()
        for command in ('bash', 'cat', 'dirname', 'jq', 'git', 'awk', 'realpath'):
            (commands / command).symlink_to(shutil.which(command))
        original_path = self.env['PATH']
        for mode in ('missing-helper', 'missing-python'):
            hook = str(copy) if mode == 'missing-helper' else 'hooks/guard-edit-isolation.sh'
            self.env['PATH'] = original_path if mode == 'missing-helper' else str(commands)
            try:
                for tool, field in (('Edit', 'file_path'), ('Write', 'file_path'),
                                    ('MultiEdit', 'file_path'), ('NotebookEdit', 'notebook_path')):
                    for cwd, expected in ((self.repo, 'deny'), (self.wt, None)):
                        for path in (str(cwd / 'src/file.py'), 'src/file.py'):
                            with self.subTest(mode=mode, tool=tool, cwd=cwd, path=path):
                                payload = {'tool_name': tool, 'cwd': str(cwd),
                                           'tool_input': {field: path}}
                                value = self.run_hook(hook, payload)
                                self.assertEqual(self.decision(value), expected)
                                if expected is None:
                                    self.assertEqual(value, {})
            finally:
                self.env['PATH'] = original_path

    def test_completed_extraction_read_allows_and_prose_does_not(self):
        skill = self.repo / 'skills/skill-extraction-workflow/SKILL.md'
        skill.parent.mkdir(parents=True)
        skill.write_text('---\nname: skill-extraction-workflow\n---\n# Owner\n')
        edit = self.call('apply_patch', {'command': '*** Begin Patch\n*** Add File: hooks/new.sh\n+x\n*** End Patch'}, 'patch')
        request = self.call('exec_command', {'cmd': f'cat {skill}'})
        for name, extra, expected in [
            ('prose', [{'type': 'response_item', 'payload': {'type': 'message', 'role': 'assistant', 'content': [
                {'type': 'output_text', 'text': 'Launching skill: ccl-skills:skill-extraction-workflow'}]}}], 'block'),
            ('pending', [request], 'block'),
            ('loaded', [request, self.output('Process exited with code 0\nOutput:\n' + skill.read_text())], None),
        ]:
            with self.subTest(name=name):
                result = self.run_hook('hooks/skill-extraction-gate-stop.sh', {
                    'session_id': name, 'cwd': str(self.repo),
                    'transcript_path': self.transcript([edit, *extra])})
                self.assertEqual(result.get('decision'), expected)

    def test_relative_symlink_patch_target_and_missing_normalizer(self):
        for link_name in ('protected', 'protected\u0085target'):
            link = self.wt / link_name
            link.symlink_to(self.repo, target_is_directory=True)
            patch = self.patch(f'*** Begin Patch\n*** Add File: {link_name}/new/file.py\n+x\n*** End Patch', self.wt)
            self.assertEqual(self.decision(self.run_hook('hooks/guard-edit-isolation.sh', patch)), 'deny')
        isolated_hooks = self.root / 'isolated-hooks'
        isolated_hooks.mkdir()
        for name in ('guard-edit-isolation.sh', 'guard-delegation-owner.sh', 'skill-extraction-gate-stop.sh'):
            (isolated_hooks / name).write_text((ROOT / 'hooks' / name).read_text())
        self.assertEqual(self.decision(self.run_hook(str(isolated_hooks / 'guard-edit-isolation.sh'), patch)), 'deny')
        payload = {'tool_name': 'spawn_agent', 'session_id': 'missing',
                   'transcript_path': self.transcript([])}
        for name in ('guard-delegation-owner.sh', 'skill-extraction-gate-stop.sh'):
            result = self.run_hook(str(isolated_hooks / name), payload)
            self.assertIn('unavailable', result['systemMessage'])

    def test_claude_extraction_invocation_semantics_are_preserved(self):
        skill = self.repo / 'skills/skill-extraction-workflow/SKILL.md'
        skill.parent.mkdir(parents=True)
        skill.write_text('# Owner\n')
        edit = {'type': 'assistant', 'message': {'content': [{'type': 'tool_use', 'name': 'Edit',
                 'input': {'file_path': str(self.repo / 'hooks/new.sh')}}]}}
        invoke = {'type': 'assistant', 'message': {'content': [{'type': 'tool_use', 'name': 'Skill',
                   'input': {'skill': 'ccl-skills:skill-extraction-workflow'}}]}}
        for label, events, expected in [('missing', [edit], 'block'), ('invoked', [invoke, edit], None)]:
            result = self.run_hook('hooks/skill-extraction-gate-stop.sh', {
                'session_id': label, 'transcript_path': self.transcript(events)})
            self.assertEqual(result.get('decision'), expected)

    def test_truncated_transcripts_never_supply_partial_verification(self):
        marker = self.repo / 'skills/skill-extraction-workflow/SKILL.md'
        marker.parent.mkdir(parents=True)
        marker.write_text('# Synthetic extraction owner\n')
        leading = [
            {'type': 'assistant', 'message': {'content': [{'type': 'tool_use', 'id': 'owner',
             'name': 'Skill', 'input': {'skill': 'ccl-skills:product-rd-workflow'}}]}},
            {'type': 'user', 'message': {'content': [{'type': 'tool_result',
             'tool_use_id': 'owner', 'content': 'Loaded'}]}}]
        edit = {'type': 'assistant', 'message': {'content': [{'type': 'tool_use', 'name': 'Edit',
                'input': {'file_path': str(self.repo / 'hooks/late.sh')}}]}}
        for label, padding in (
                ('events', [{'type': 'ignored'}] * 20000),
                ('line', [{'type': 'ignored', 'text': 'x' * (1024 * 1024)}]),
                ('bytes', [{'type': 'ignored', 'text': 'x' * 900000}] * 20)):
            path = self.transcript(leading + padding + [edit])
            with self.subTest(limit=label, consumer='helper'):
                result = subprocess.run(['python3', str(ROOT / 'hooks/host-input.py'),
                                         'transcript', path, str(self.repo)],
                                        capture_output=True, text=True)
                self.assertNotEqual(result.returncode, 0)
                summary = json.loads(result.stdout)
                self.assertFalse(summary['verifiable'])
                self.assertTrue(summary['truncated'])
                self.assertEqual(summary['completed_skills'], [])
                self.assertEqual(summary['edit_paths'], [])
            for hook in ('skill-extraction-gate-stop.sh', 'proposed-next-stop.sh'):
                with self.subTest(limit=label, consumer=hook):
                    result = self.run_hook('hooks/' + hook, {
                        'session_id': 'limit-' + label, 'cwd': str(self.repo),
                        'transcript_path': path, 'hook_event_name': 'Stop',
                        'stop_hook_active': False, 'last_assistant_message': 'Synthetic private status.'})
                    self.assertIn('unverified', result.get('systemMessage', '').lower())
                    self.assertNotIn('decision', result)
                    self.assertNotIn('Synthetic private status', json.dumps(result))


if __name__ == '__main__':
    unittest.main()
