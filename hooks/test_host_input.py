#!/usr/bin/env python3
"""Host boundary regressions; all repositories and transcripts are synthetic."""
import importlib.util
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest
from unittest.mock import patch

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

    def runtime_for_skill(self, skill):
        # A synthetic canonical source belongs to an isolated helper/runtime,
        # never to an arbitrary same-named file in the tested project.
        runtime = self.root / 'runtime'
        shutil.copytree(ROOT / 'hooks', runtime / 'hooks')
        shutil.copytree(ROOT / 'scripts/owner-dispatch', runtime / 'scripts/owner-dispatch')
        shutil.copytree(ROOT / 'agent-context', runtime / 'agent-context')
        canonical = runtime / 'skills' / skill.parent.name / 'SKILL.md'
        canonical.parent.mkdir(parents=True)
        canonical.write_bytes(skill.read_bytes())
        return runtime

    def test_codex_dispatch_replans_once_and_completed_read_satisfies_it(self):
        skill = self.repo / 'skills/multi-agent-delegation/SKILL.md'
        skill.parent.mkdir(parents=True)
        skill.write_text('---\nname: multi-agent-delegation\n---\n# Loaded owner\n')
        runtime = self.runtime_for_skill(skill)
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
                payload = {'hook_event_name': 'PreToolUse', 'tool_name': 'spawn_agent', 'session_id': label,
                           'transcript_path': self.transcript(events)}
                value = self.run_hook(runtime / 'hooks/guard-delegation-owner.sh', payload)
                specific = value.get('hookSpecificOutput', {})
                self.assertEqual(specific.get('permissionDecision'), 'deny' if expect_context else None)
                self.assertEqual(self.run_hook(runtime / 'hooks/guard-delegation-owner.sh', payload), {})

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
        runtime = self.runtime_for_skill(skill)
        request = self.call('exec_command', {'cmd': f'cat {skill}'})
        for completed, expected in ((False, 3), (True, 0)):
            events = [request]
            if completed:
                events.append(self.output('Process exited with code 0\nOutput:\n' + skill.read_text()))
            path = self.transcript(events)
            result = subprocess.run(['bash', str(runtime / 'scripts/owner-dispatch/owner-dispatch.sh'),
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
        runtime = self.runtime_for_skill(skill)
        edit = self.call('apply_patch', {'command': '*** Begin Patch\n*** Add File: hooks/new.sh\n+x\n*** End Patch'}, 'patch')
        request = self.call('exec_command', {'cmd': f'cat {skill}'})
        for name, extra, expected in [
            ('prose', [{'type': 'response_item', 'payload': {'type': 'message', 'role': 'assistant', 'content': [
                {'type': 'output_text', 'text': 'Launching skill: ccl-skills:skill-extraction-workflow'}]}}], 'block'),
            ('pending', [request], 'block'),
            ('loaded', [request, self.output('Process exited with code 0\nOutput:\n' + skill.read_text())], None),
        ]:
            with self.subTest(name=name):
                result = self.run_hook(runtime / 'hooks/skill-extraction-gate-stop.sh', {
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


class ContextTranscriptTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        module_path = self.root / 'hooks/host-input.py'
        module_path.parent.mkdir()
        module_path.write_bytes((ROOT / 'hooks/host-input.py').read_bytes())
        spec = importlib.util.spec_from_file_location('host_input', module_path)
        self.helper = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(self.helper)
        self.skill = self.root / 'skills/example-owner/SKILL.md'
        self.skill.parent.mkdir(parents=True)
        self.source = '---\nname: example-owner\ndescription: Synthetic owner\n---\n# Owner\n\nRead all rules.\nLast required rule.\n'
        self.skill.write_text(self.source)
        self.path = self.root / 'transcript.jsonl'
        self.path.touch()

    def append(self, *events):
        with self.path.open('a') as stream:
            for event in events:
                stream.write(json.dumps(event) + '\n')

    def call(self, command=None, call_id='read'):
        return {'type': 'response_item', 'payload': {'type': 'function_call',
                'name': 'exec_command', 'call_id': call_id,
                'arguments': json.dumps({'cmd': command or f'cat {self.skill}'})}}

    def output(self, body=None, call_id='read', code=0):
        return {'type': 'response_item', 'payload': {'type': 'function_call_output',
                'call_id': call_id, 'output': f'Process exited with code {code}\nOutput:\n' +
                (self.source if body is None else body)}}

    def claude(self, call_id='owner'):
        return ({'type': 'assistant', 'message': {'content': [{'type': 'tool_use',
                 'id': call_id, 'name': 'Skill', 'input': {'skill': 'ccl-skills:example-owner'}}]}},
                {'type': 'user', 'message': {'content': [{'type': 'tool_result',
                 'tool_use_id': call_id, 'content': 'Loaded'}]}})

    def summary(self, offset=0):
        return self.helper.context_transcript(str(self.path), str(self.root), offset)

    def test_audit_requires_full_current_body_not_name_or_frontmatter(self):
        for output in ('name: example-owner\n', ''.join(self.source.splitlines(True)[:4]), self.source):
            with self.subTest(output=output):
                self.path.write_text('')
                self.append(self.call(), self.output(output))
                summary = self.helper.transcript(str(self.path), str(self.root))
                self.assertEqual(summary['completed_skills'],
                                 ['ccl-skills:example-owner'] if output == self.source else [])

    def test_foreign_short_skill_cannot_claim_canonical_owner(self):
        canonical = self.root / 'skills/multi-agent-delegation/SKILL.md'
        canonical.parent.mkdir()
        canonical.write_text(self.source.replace('example-owner', 'multi-agent-delegation'))
        foreign = self.root / 'project/skills/multi-agent-delegation/SKILL.md'
        foreign.parent.mkdir(parents=True)
        foreign.write_text('---\nname: multi-agent-delegation\n---\n# loaded\n')
        self.append(self.call('cat skills/multi-agent-delegation/SKILL.md'), self.output(foreign.read_text()))
        project = str(foreign.parents[2])
        with patch.dict(os.environ, {'CLAUDE_PLUGIN_ROOT': project}):
            for summary in (self.helper.context_transcript(str(self.path), project),
                            self.helper.transcript(str(self.path), project)):
                self.assertEqual(summary['completed_skills'], [])
                self.assertTrue(summary['unverifiable_reads'])

    def test_identical_copy_preserves_full_and_chunked_source_evidence(self):
        copy = self.root / 'project/skills/example-owner/SKILL.md'
        copy.parent.mkdir(parents=True)
        copy.write_bytes(self.skill.read_bytes())
        self.append(self.call(f'cat {copy}'), self.output())
        self.assertEqual(self.summary()['completed_skills'], ['ccl-skills:example-owner'])
        self.path.write_text('')
        for first, last in ((1, 4), (5, 8)):
            self.append(self.call(f"sed -n '{first},{last}p' {copy}", str(first)),
                        self.output(''.join(self.source.splitlines(True)[first - 1:last]), str(first)))
        self.assertEqual(self.summary()['completed_skills'], ['ccl-skills:example-owner'])
        self.skill.write_text(self.source + 'New canonical requirement.\n')
        self.assertEqual(self.summary()['completed_skills'], [])

    def test_missing_canonical_source_cannot_be_replaced_by_project_file(self):
        foreign = self.root / 'project/skills/example-owner/SKILL.md'
        foreign.parent.mkdir(parents=True)
        foreign.write_bytes(self.skill.read_bytes())
        self.skill.unlink()
        self.append(self.call(f'cat {foreign}'), self.output())
        self.assertEqual(self.summary()['completed_skills'], [])

    def test_native_boundaries_reset_current_evidence_but_preserve_audit(self):
        for boundary in ({'type': 'system', 'subtype': 'compact_boundary'},
                         {'type': 'compacted', 'payload': {'message': 'Synthetic summary'}}):
            with self.subTest(boundary=boundary):
                self.path.write_text('')
                self.append(*self.claude())
                before = self.summary()
                self.append(boundary)
                after = self.summary()
                self.assertTrue(after['context_complete'])
                self.assertTrue(after['verifiable'])
                self.assertEqual(after['completed_skills'], [])
                self.assertNotEqual(before['context_id'], after['context_id'])
                self.assertEqual(self.helper.transcript(str(self.path), str(self.root))['completed_skills'],
                                 ['ccl-skills:example-owner'])
                self.append(*self.claude('fresh'))
                fresh = self.summary()
                self.assertEqual(fresh['context_id'], after['context_id'])
                self.assertEqual(fresh['completed_skills'], ['ccl-skills:example-owner'])

    def test_pending_requests_never_pair_across_either_boundary(self):
        for boundary in ({'type': 'system', 'subtype': 'compact_boundary'},
                         {'type': 'compacted', 'payload': {}}):
            for request, result in (self.claude(), (self.call(), self.output())):
                with self.subTest(boundary=boundary, host=request['type']):
                    self.path.write_text('')
                    self.append(request, boundary, result)
                    self.assertEqual(self.summary()['completed_skills'], [])
                    self.assertEqual(self.helper.transcript(str(self.path), str(self.root))['completed_skills'], [])

    def test_only_native_top_level_boundary_resets_context(self):
        self.append(*self.claude())
        first = self.summary()
        self.append({'type': 'system', 'subtype': 'compact_boundary', 'isSidechain': True},
                    {'type': 'assistant', 'message': {'content': [{'type': 'text',
                     'text': json.dumps({'type': 'compacted', 'payload': {}})}]}},
                    {'type': 'compacted', 'payload': 'unsupported'})
        self.assertEqual(self.summary()['context_id'], first['context_id'])
        self.assertEqual(self.summary()['completed_skills'], first['completed_skills'])

    def test_current_full_read_and_disjoint_literal_sed_coverage(self):
        chunks = [(5, 8), (1, 2), (3, 4)]
        for index, (first, last) in enumerate(chunks):
            self.append(self.call(f"sed -n '{first},{last}p' {self.skill}", str(index)),
                        self.output(''.join(self.source.splitlines(True)[first - 1:last]), str(index)))
            self.assertEqual(self.summary()['completed_skills'],
                             ['ccl-skills:example-owner'] if index == 2 else [])
        self.assertEqual(self.helper.transcript(str(self.path), str(self.root))['completed_skills'],
                         ['ccl-skills:example-owner'])

    def test_sed_counts_lf_lines_and_preserves_unicode_body(self):
        self.source = self.source.replace('Read all rules.', 'Read all\u2028rules.')
        self.skill.write_text(self.source)
        self.append(self.call(f"sed -n '1,8p' {self.skill}"), self.output())
        self.assertEqual(self.summary()['completed_skills'], ['ccl-skills:example-owner'])

    def test_literal_cat_multiple_files_and_relative_workdir(self):
        second = self.root / 'skills/second-owner/SKILL.md'
        second.parent.mkdir()
        second_source = self.source.replace('example-owner', 'second-owner')
        second.write_text(second_source)
        request = self.call()
        request['payload']['arguments'] = json.dumps({
            'cmd': 'cat -- example-owner/SKILL.md second-owner/SKILL.md', 'workdir': 'skills'})
        self.append(request, self.output(self.source + second_source))
        self.assertEqual(self.summary()['completed_skills'],
                         ['ccl-skills:example-owner', 'ccl-skills:second-owner'])

    def test_failed_claude_completion_consumes_request(self):
        request, result = self.claude()
        failed = json.loads(json.dumps(result))
        failed['message']['content'][0]['is_error'] = True
        self.append(request, failed, result)
        self.assertEqual(self.summary()['completed_skills'], [])

    def test_oversized_current_record_is_unknown_but_older_damage_can_be_discarded(self):
        self.append({'type': 'ignored', 'text': 'x' * (1024 * 1024)}, self.call(), self.output())
        self.assertFalse(self.summary()['context_complete'])
        self.assertEqual(self.summary()['completed_skills'], [])
        self.append({'type': 'system', 'subtype': 'compact_boundary'}, *self.claude())
        self.assertTrue(self.summary()['context_complete'])
        self.assertEqual(self.summary()['completed_skills'], ['ccl-skills:example-owner'])

    def test_partial_failed_truncated_and_mismatched_reads_never_complete(self):
        for variant in ('partial', 'failed', 'truncated', 'mismatch', 'pending'):
            with self.subTest(variant=variant):
                self.path.write_text('')
                self.append(self.call(f"sed -n '1,4p' {self.skill}", 'first'),
                            self.output(''.join(self.source.splitlines(True)[:4]), 'first'))
                self.append(self.call(f"sed -n '5,8p' {self.skill}", 'second'))
                body = ''.join(self.source.splitlines(True)[4:])
                if variant == 'partial':
                    body = body.splitlines(True)[0]
                elif variant == 'truncated':
                    body += 'Warning: truncated output'
                elif variant == 'mismatch':
                    body = 'different body\n'
                if variant != 'pending':
                    self.append(self.output(body, 'second', 1 if variant == 'failed' else 0))
                self.assertEqual(self.summary()['completed_skills'], [])

    def test_chunk_coverage_does_not_cross_compaction_or_file_revision(self):
        self.append(self.call(f"sed -n '1,4p' {self.skill}", 'first'),
                    self.output(''.join(self.source.splitlines(True)[:4]), 'first'),
                    {'type': 'compacted', 'payload': {}},
                    self.call(f"sed -n '5,8p' {self.skill}", 'second'),
                    self.output(''.join(self.source.splitlines(True)[4:]), 'second'))
        self.assertEqual(self.summary()['completed_skills'], [])
        self.assertEqual(self.helper.transcript(str(self.path), str(self.root))['completed_skills'], [])
        self.path.write_text('')
        self.append(self.call(), self.output())
        self.skill.write_text(self.source + 'New required rule.\n')
        self.assertEqual(self.summary()['completed_skills'], [])

    def test_compound_skill_reads_are_explicitly_unverifiable_and_never_executed(self):
        marker = self.root / 'executed'
        self.append(self.call(f'cat {self.skill}; touch {marker}'), self.output())
        summary = self.summary()
        self.assertEqual(summary['completed_skills'], [])
        self.assertFalse(summary['verifiable'])
        self.assertTrue(summary['unverifiable_reads'])
        self.assertFalse(marker.exists())
        self.append(self.call(call_id='repair'), self.output(call_id='repair'))
        repaired = self.summary()
        self.assertTrue(repaired['context_complete'])
        self.assertTrue(repaired['unverifiable_reads'])
        self.assertEqual(repaired['completed_skills'], ['ccl-skills:example-owner'])

    def test_recent_native_context_survives_large_omitted_prefix(self):
        for padding in ([{'type': 'ignored'}] * 20010,
                        [{'type': 'ignored', 'text': 'x' * 900000}] * 20):
            with self.subTest(padding_count=len(padding)):
                self.path.write_text('')
                self.append(*padding, {'type': 'compacted', 'payload': {}}, self.call(), self.output())
                summary = self.summary()
                self.assertTrue(summary['context_complete'])
                self.assertTrue(summary['verifiable'])
                self.assertEqual(summary['completed_skills'], ['ccl-skills:example-owner'])

    def test_truncated_unknown_prefix_or_malformed_current_record_is_not_verified(self):
        self.append(*([{'type': 'ignored'}] * 20001), self.call(), self.output())
        summary = self.summary()
        self.assertFalse(summary['context_complete'])
        self.assertFalse(summary['verifiable'])
        self.assertIsNone(summary['context_id'])
        self.assertEqual(summary['completed_skills'], [])
        self.path.write_text('')
        self.append({'type': 'compacted', 'payload': {}}, self.call(), self.output())
        with self.path.open('a') as stream:
            stream.write('{incomplete')
        self.assertFalse(self.summary()['context_complete'])
        self.assertFalse(self.summary()['verifiable'])
        self.assertEqual(self.summary()['completed_skills'], [])

    def test_postcompact_high_watermark_handles_late_boundary_flush(self):
        self.append(self.call(call_id='old'))
        offset = self.path.stat().st_size
        self.append(self.output(call_id='old'), self.call(call_id='new'), self.output(call_id='new'))
        summary = self.summary(offset)
        self.assertTrue(summary['context_complete'])
        self.assertTrue(summary['verifiable'])
        self.assertEqual(summary['completed_skills'], ['ccl-skills:example-owner'])
        self.assertEqual(summary['context_id'], f'offset:{offset}')
        self.path.write_text('')
        self.append(self.call(call_id='old'))
        offset = self.path.stat().st_size
        self.append(self.output(call_id='old'))
        self.assertEqual(self.summary(offset)['completed_skills'], [])
        self.append({'type': 'compacted', 'payload': {}})
        native = self.summary(offset)
        self.assertNotEqual(native['context_id'], f'offset:{offset}')
        self.append(*self.claude())
        self.assertEqual(self.summary(offset)['context_id'], native['context_id'])

    def test_invalid_offset_or_nonregular_file_is_unknown(self):
        for offset in (-1, True, '0', 1):
            with self.subTest(offset=offset):
                self.assertFalse(self.summary(offset)['context_complete'])
        self.path.unlink()
        os.mkfifo(self.path)
        self.assertFalse(self.summary()['context_complete'])
        self.path.unlink()
        self.assertFalse(self.summary()['context_complete'])

    def test_deeply_nested_current_record_cannot_escape_as_parser_exception(self):
        self.path.write_text('{"type":"ignored","payload":' + '[' * 2000 + '0' + ']' * 2000 + '}\n')
        summary = self.summary()
        # Older Python JSON decoders reject this depth; newer iterative decoders
        # can parse it. Both must return a bounded summary with no skill proof.
        self.assertIsInstance(summary['context_complete'], bool)
        self.assertEqual(summary['completed_skills'], [])


if __name__ == '__main__':
    unittest.main()
