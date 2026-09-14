#!/usr/bin/env python3
"""Synthetic native Stop payloads; no real host state or conversations."""
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]


class ProposedNextTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        self.hooks = self.root / 'hooks'
        self.hooks.mkdir()
        for name in ('host-input.py', 'proposed-next-stop.sh'):
            source = ROOT / 'hooks' / name
            if source.exists():
                shutil.copyfile(source, self.hooks / name)
        self.skill = self.root / 'skills/product-rd-workflow/SKILL.md'
        self.skill.parent.mkdir(parents=True)
        source = (ROOT / 'skills/product-rd-workflow/SKILL.md').read_text()
        self.contract = next(p for p in source.split('\n\n') if p.startswith(
            '**Continuation-proposal output contract (session-wide for product delivery).**'))
        self.skill.write_text('---\nname: product-rd-workflow\n---\n\n' + self.contract + '\n')
        self.path = self.root / 'synthetic.jsonl'
        self.path.write_text('')
        self.payload = {'session_id': 'synthetic', 'cwd': str(self.root),
                        'transcript_path': str(self.path), 'hook_event_name': 'Stop',
                        'stop_hook_active': False, 'last_assistant_message': 'Checks passed.'}

    def events(self, events):
        self.path.write_text(''.join(json.dumps(e) + '\n' for e in events))

    def run_hook(self, payload=None):
        value = self.payload if payload is None else payload
        raw = value if isinstance(value, str) else json.dumps(value)
        result = subprocess.run(['bash', str(self.hooks / 'proposed-next-stop.sh')],
                                input=raw, text=True, capture_output=True, cwd=self.root)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stderr, '')
        return json.loads(result.stdout) if result.stdout else {}

    def claude_load(self, name='product-rd-workflow', error=False):
        return [
            {'type': 'assistant', 'message': {'content': [{'type': 'tool_use', 'id': 'load',
             'name': 'Skill', 'input': {'skill': 'ccl-skills:' + name}}]}},
            {'type': 'user', 'message': {'content': [{'type': 'tool_result',
             'tool_use_id': 'load', 'is_error': error, 'content': 'Skill loaded'}]}}]

    def codex_read(self, command=None, body=None, code=0, call_id='load', output_id='load'):
        return [
            {'type': 'response_item', 'payload': {'type': 'function_call', 'name': 'exec_command',
             'call_id': call_id, 'arguments': json.dumps({'cmd': command or f'cat {self.skill}'})}},
            {'type': 'response_item', 'payload': {'type': 'function_call_output', 'call_id': output_id,
             'output': f'Process exited with code {code}\nOutput:\n' + (
                 self.skill.read_text() if body is None else body)}}]

    def assistant(self, text, host='codex', phase='final_answer'):
        if host == 'claude':
            return {'type': 'assistant', 'message': {'content': [{'type': 'text', 'text': text}]}}
        return {'type': 'response_item', 'payload': {'type': 'message', 'role': 'assistant',
                'phase': phase, 'content': [{'type': 'output_text', 'text': text}]}}

    def assert_block(self, value):
        self.assertEqual(value.get('decision'), 'block', value)
        self.assertEqual(set(value), {'decision', 'reason'})
        self.assertIn('proposed-next:', value['reason'])

    def test_native_claude_and_codex_completed_owner(self):
        for host, events in [('claude', self.claude_load()), ('codex', self.codex_read())]:
            with self.subTest(host=host):
                self.events(events)
                payload = dict(self.payload)
                if host == 'codex':
                    payload.update(turn_id='synthetic-turn', model='synthetic-model',
                                   permission_mode='default')
                self.assert_block(self.run_hook(payload))

    def test_direct_final_overrides_stale_transcript_answer(self):
        self.events(self.claude_load() + [self.assistant('proposed-next: verify the local patch')])
        self.assert_block(self.run_hook())
        self.payload['last_assistant_message'] = 'Done.\nproposed-next: none — status only'
        self.assertEqual(self.run_hook(), {})

    def test_loop_and_malformed_fields_are_quiet(self):
        self.events(self.claude_load())
        for updates in ({'stop_hook_active': True}, {'stop_hook_active': 'false'},
                        {'stop_hook_active': 0}, {'last_assistant_message': None},
                        {'last_assistant_message': ''}, {'last_assistant_message': []},
                        {'hook_event_name': 'SubagentStop'}, {'hook_event_name': 'StopFailure'}):
            with self.subTest(updates=updates):
                self.assertEqual(self.run_hook(dict(self.payload, **updates)), {})
        for field in ('last_assistant_message', 'stop_hook_active', 'hook_event_name'):
            payload = dict(self.payload)
            del payload[field]
            self.assertEqual(self.run_hook(payload), {})
        for payload in ('[]', 'null', '{}'):
            self.assertEqual(self.run_hook(payload), {})

    def test_plain_answers_and_unrelated_owner_do_not_trigger(self):
        for events in ([], self.claude_load('testing-strategy'), self.claude_load(error=True),
                       self.claude_load()[:1]):
            self.events(events)
            self.assertEqual(self.run_hook(), {})

    def test_prior_assistant_handoff_is_eligibility_for_both_hosts(self):
        for host in ('claude', 'codex'):
            self.events([self.assistant('proposed-next: verify the local patch', host)])
            self.assert_block(self.run_hook())

    def test_quoted_examples_and_commentary_do_not_establish_eligibility(self):
        for text in ('> proposed-next: run checks', '```text\nproposed-next: run checks\n```',
                     'Example: proposed-next: run checks', 'proposed-next: <action and scope>',
                     '`proposed-next: run checks`', '    proposed-next: code example',
                     '```text\n```not a closing fence\nproposed-next: code example\n```'):
            self.events([self.assistant(text)])
            self.assertEqual(self.run_hook(), {})
        self.events([self.assistant('proposed-next: run checks', phase='commentary')])
        self.assertEqual(self.run_hook(), {})
        self.events([{'type': 'response_item', 'payload': {'type': 'message', 'role': 'user',
                     'content': [{'type': 'input_text', 'text': 'proposed-next: run checks'}]}}])
        self.assertEqual(self.run_hook(), {})

    def test_marker_in_quote_does_not_satisfy_current_handoff(self):
        self.events(self.claude_load())
        for text in ('Done.\n> proposed-next: run checks',
                     'Done.\n```text\nproposed-next: run checks\n```',
                     'Done.\nproposed-next: <action and scope>', 'Done.\nproposed-next:  '):
            self.payload['last_assistant_message'] = text
            self.assert_block(self.run_hook())

    def test_status_question_and_user_stop_keep_truthful_formatting(self):
        self.events(self.claude_load())
        for text in ('Which option should I use?', 'Stopped as requested.', 'Status: checks passed.'):
            self.payload['last_assistant_message'] = text
            self.assert_block(self.run_hook())
        for text in ('proposed-next: none — status only', '**proposed-next:** none — status only'):
            self.payload['last_assistant_message'] = text
            self.assertEqual(self.run_hook(), {})

    def test_actionable_handoff_rechecks_continuation_instead_of_silently_stopping(self):
        for events in ([], self.claude_load(), self.codex_read()):
            self.events(events)
            for text in ('Next I will verify.\nproposed-next: run the existing local verification suite',
                         '**proposed-next:** repair the failing check and retest',
                         'proposed-next: none — status only\nproposed-next: finish the remaining repair'):
                payload = dict(self.payload, last_assistant_message=text)
                result = self.run_hook(payload)
                self.assert_block(result)
                self.assertIn('execute it now', result['reason'])
                self.assertIn('planning-only', result['reason'])
                self.assertIn('supplies no new goal or authorization', result['reason'])
                self.assertEqual(self.run_hook(dict(payload, stop_hook_active=True)), {})

    def test_quoted_actions_do_not_turn_a_status_handoff_into_work(self):
        self.events(self.claude_load())
        for suffix in ('\n> proposed-next: deploy', '\n```text\nproposed-next: deploy\n```'):
            self.payload['last_assistant_message'] = 'proposed-next: none — status only' + suffix
            self.assertEqual(self.run_hook(), {})

    def test_current_action_recheck_needs_no_transcript_read(self):
        self.path.write_text('not a valid transcript')
        for path in (str(self.path), str(self.root / 'missing'), None):
            payload = dict(self.payload, transcript_path=path,
                           last_assistant_message='proposed-next: run the existing checks')
            self.assert_block(self.run_hook(payload))

    def test_complete_machine_artifacts_are_preserved(self):
        self.events(self.claude_load())
        for text in ('{"status":"done"}', '[1,2]', 'true', '"done"', '42',
                     '```json\n{"status":"done"}\n```', '~~~text\nexact output\n~~~'):
            self.payload['last_assistant_message'] = text
            self.assertEqual(self.run_hook(), {})
        self.payload['last_assistant_message'] = '```json\n{}\n```\nChecks passed.\n```text\nexample\n```'
        self.assert_block(self.run_hook())

    def test_missing_optional_canonical_rule_does_not_disable_other_evidence(self):
        self.skill.unlink()
        for events in (self.claude_load(), [self.assistant('proposed-next: run local checks')]):
            self.events(events)
            self.assert_block(self.run_hook())
        self.events([])
        self.assertEqual(self.run_hook(), {})

    def test_successful_fragment_read_is_visibility_not_completed_owner(self):
        for command, body in [(f'sed -n \'10,12p\' {self.skill}', self.contract),
                              (f'printf before; sed -n \'1,20p\' {self.skill}', self.skill.read_text())]:
            with self.subTest(command=command):
                self.events(self.codex_read(command, body))
                self.assert_block(self.run_hook())
                result = subprocess.run(['python3', str(self.hooks / 'host-input.py'),
                                         'transcript', str(self.path), str(self.root)],
                                        capture_output=True, text=True, check=True)
                summary = json.loads(result.stdout)
                self.assertEqual(summary['completed_skills'], [])
                self.assertTrue(summary['continuation_contract_visible'])

    def test_visibility_requires_whole_current_rule_and_terminal_matching_output(self):
        command = f'sed -n \'10,12p\' {self.skill}'
        for label, events in [
            ('pending', self.codex_read(command)[:1]),
            ('error', self.codex_read(command, self.contract, code=1)),
            ('mismatch', self.codex_read(command, self.contract, output_id='unpaired')),
            ('truncated', self.codex_read(command, 'Warning: truncated output\n' + self.contract)),
            ('partial-rule', self.codex_read(command, self.contract[:120])),
            ('strings-only', self.codex_read(command, 'proposed-next: <action and scope>')),
        ]:
            with self.subTest(label=label):
                self.events(events)
                self.assertEqual(self.run_hook(), {})
        events = self.codex_read(command)
        events[1]['payload']['output'] = 'Process running with session ID 1\nOutput:\n' + self.contract
        self.events(events)
        self.assertEqual(self.run_hook(), {})

    def test_claude_successful_read_visibility_is_not_a_skill_load(self):
        request = {'type': 'assistant', 'message': {'content': [{'type': 'tool_use', 'name': 'Read',
                   'id': 'read', 'input': {'file_path': str(self.skill)}}]}}
        for error, expected in ((False, 'block'), (True, None)):
            self.events([request, {'type': 'user', 'message': {'content': [{'type': 'tool_result',
                         'tool_use_id': 'read', 'is_error': error,
                         'content': [{'type': 'text', 'text': self.contract}]}]}}])
            self.assertEqual(self.run_hook().get('decision'), expected)

    def test_visibility_tracks_canonical_rule_without_copied_matching_prose(self):
        self.contract += ' Synthetic changed obligation.'
        self.skill.write_text('---\nname: product-rd-workflow\n---\n\n' + self.contract + '\n')
        self.events(self.codex_read('sed -n \'1,20p\' skills/product-rd-workflow/SKILL.md', self.contract))
        self.assert_block(self.run_hook())

    def test_internal_errors_warn_without_leaking_inputs(self):
        self.events(self.claude_load())
        self.payload['last_assistant_message'] = 'Private synthetic payload, never echo this.'
        first = self.run_hook()
        self.payload['last_assistant_message'] = 'Another synthetic payload.'
        self.assertEqual(self.run_hook(), first)
        self.assertNotIn('synthetic', json.dumps(first))
        result = self.run_hook('{invalid secret fixture')
        self.assertIn('unavailable', result.get('systemMessage', ''))
        self.assertNotIn('secret', json.dumps(result))
        (self.hooks / 'host-input.py').unlink()
        self.assertIn('unavailable', self.run_hook().get('systemMessage', ''))

    def test_scan_is_bounded_and_no_filesystem_markers_are_written(self):
        self.events([{'type': 'ignored'}] * 20000 + self.claude_load())
        before = set(self.root.rglob('*'))
        self.assertIn('unverified', self.run_hook().get('systemMessage', '').lower())
        self.assertEqual(set(self.root.rglob('*')), before)
        self.events([{'type': 'ignored'}] * 20000)
        self.assertEqual(self.run_hook(), {})
        self.events(self.claude_load())
        self.assert_block(self.run_hook())
        self.assert_block(self.run_hook())  # A new host turn must not be suppressed by session id.
        self.assertEqual(set(self.root.rglob('*')), before)

    def test_oversized_or_malformed_input_fails_soft_without_transcript_echo(self):
        self.path.write_text(json.dumps({'type': 'ignored', 'text': 'x' * (1024 * 1024)}) + '\n')
        self.assertIn('unverified', self.run_hook().get('systemMessage', '').lower())
        oversized = dict(self.payload, last_assistant_message='x' * (2 * 1024 * 1024))
        self.assertIn('unavailable', self.run_hook(oversized).get('systemMessage', ''))
        malformed = self.claude_load()
        malformed[0]['message']['content'][0]['id'] = ['synthetic-private']
        malformed[1]['message']['content'][0]['tool_use_id'] = ['synthetic-private']
        self.events(malformed)
        result = self.run_hook()
        self.assertIn('unavailable', result.get('systemMessage', ''))
        self.assertNotIn('synthetic-private', json.dumps(result))

    def test_nonregular_transcript_does_not_block_on_a_pipe(self):
        pipe = self.root / 'synthetic-pipe'
        os.mkfifo(pipe)
        payload = dict(self.payload, transcript_path=str(pipe))
        result = subprocess.run(['python3', str(self.hooks / 'host-input.py'), 'proposed-next'],
                                input=json.dumps(payload), text=True, capture_output=True, timeout=2)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn('unavailable', json.loads(result.stdout).get('systemMessage', ''))


if __name__ == '__main__':
    unittest.main()
