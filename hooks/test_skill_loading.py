#!/usr/bin/env python3
"""Bounded skill-loading checkpoints on synthetic host events and files."""
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch
from types import SimpleNamespace

ROOT = Path(__file__).resolve().parents[1]


class SkillLoadingTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name).resolve()
        self.log = self.root / 'transcript.jsonl'
        self.log.write_text('')
        self.env = dict(os.environ, TMPDIR=str(self.root), CLAUDE_PLUGIN_ROOT=str(ROOT))
        for key in ('GIT_DIR', 'GIT_WORK_TREE', 'GIT_COMMON_DIR', 'GIT_INDEX_FILE'):
            self.env.pop(key, None)

    def payload(self, tool='Edit', **extra):
        return {'hook_event_name': 'PreToolUse', 'tool_name': tool,
                'tool_input': {'file_path': str(self.root / 'source.py')},
                'session_id': 'synthetic', 'transcript_path': str(self.log),
                'cwd': str(self.root), **extra}

    def run_hook(self, payload, name='owner-dispatch-guard.sh'):
        result = subprocess.run(['bash', str(ROOT / 'hooks' / name)],
                                input=json.dumps(payload), text=True, capture_output=True,
                                env=self.env, cwd=self.root, timeout=10)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stderr, '')
        return json.loads(result.stdout) if result.stdout else {}

    def decision(self, value):
        return value.get('hookSpecificOutput', {}).get('permissionDecision')

    def append(self, *events):
        with self.log.open('a') as stream:
            for event in events:
                stream.write(json.dumps(event) + '\n')

    def loaded(self, ident='load'):
        self.append({'type': 'assistant', 'message': {'content': [
            {'type': 'tool_use', 'id': ident, 'name': 'Skill',
             'input': {'skill': 'ccl-skills:multi-agent-delegation'}}]}},
            {'type': 'user', 'message': {'content': [
                {'type': 'tool_result', 'tool_use_id': ident, 'content': 'Loaded owner'}]}})

    def compact_event(self, event):
        return self.run_hook({'hook_event_name': event, 'session_id': 'synthetic',
                              'transcript_path': str(self.log), 'cwd': str(self.root)},
                             'skill-context-compact.sh')

    def compact(self):
        self.assertEqual(self.compact_event('PreCompact'), {})
        return self.compact_event('PostCompact')

    def boundary(self):
        self.append({'type': 'compacted', 'payload': {'message': 'summary'}})

    def attempts(self):
        return len(list(self.root.glob('ccl-skill-loading-*/*/attempt-*')))

    def test_default_checkpoint_without_repo_opt_in_replans_once(self):
        result = self.run_hook(self.payload())
        self.assertEqual(self.decision(result), 'deny')
        reason = result['hookSpecificOutput']['permissionDecisionReason']
        self.assertIn('multi-agent-delegation', reason)
        self.assertIn('implementation', reason.lower())
        self.assertNotIn('permissionDecision":"ask', json.dumps(result))
        self.assertEqual(self.run_hook(self.payload()), {})

    def test_native_patch_and_all_targets(self):
        patch = '*** Begin Patch\n*** Add File: README.md\n+doc\n*** Add File: src/new.ts\n+code\n*** End Patch'
        value = self.run_hook(self.payload('apply_patch', tool_input={'command': patch}))
        self.assertEqual(self.decision(value), 'deny')

    def test_read_only_document_and_unparseable_edits_do_not_consume_checkpoint(self):
        for tool, args in [('Read', {'file_path': 'source.py'}),
                           ('Bash', {'command': 'cat source.py'}),
                           ('Edit', {'file_path': 'README.md'}),
                           ('apply_patch', {'command': '*** Begin Patch\n*** Add File: README.md\n+doc\n*** End Patch'})]:
            with self.subTest(tool=tool, args=args):
                self.assertEqual(self.run_hook(self.payload(tool, tool_input=args)), {})
        self.assertEqual(self.decision(self.run_hook(self.payload())), 'deny')

    def test_existing_malformed_patch_denial_is_not_changed(self):
        result = self.run_hook(self.payload('apply_patch', tool_input={'command': 'invalid'}))
        self.assertEqual(self.decision(result), 'deny')
        self.assertIn('malformed', result['hookSpecificOutput']['permissionDecisionReason'])

    def test_session_actor_and_transcript_scopes_are_independent(self):
        self.assertEqual(self.decision(self.run_hook(self.payload())), 'deny')
        for extra in ({'session_id': 'other'}, {'agent_id': 'worker-a'}, {'agent_id': 'worker-b'}):
            with self.subTest(extra=extra):
                self.assertEqual(self.decision(self.run_hook(self.payload(**extra))), 'deny')
                self.assertEqual(self.run_hook(self.payload(**extra)), {})
        other = self.root / 'other.jsonl'
        other.write_text('')
        self.assertEqual(self.decision(self.run_hook(self.payload(transcript_path=str(other)))), 'deny')

    def test_native_compaction_boundary_rearms_without_erasing_old_audit(self):
        self.loaded()
        self.assertEqual(self.decision(self.run_hook(self.payload())), 'deny')
        self.append({'type': 'system', 'subtype': 'compact_boundary', 'compactMetadata': {'trigger': 'auto'}})
        self.assertEqual(self.decision(self.run_hook(self.payload())), 'deny')
        self.assertEqual(self.run_hook(self.payload()), {})
        self.append({'type': 'compacted', 'payload': {'message': 'summary'}})
        self.assertEqual(self.decision(self.run_hook(self.payload())), 'deny')

    def test_quoted_compaction_does_not_rearm(self):
        self.run_hook(self.payload())
        self.append({'type': 'user', 'message': {'content': [
            {'type': 'text', 'text': '{"type":"compacted","payload":{}}'}]}})
        self.assertEqual(self.run_hook(self.payload()), {})

    def test_postcompact_rearms_before_transcript_boundary_is_flushed(self):
        self.loaded()
        self.run_hook(self.payload())
        result = self.compact()
        self.assertEqual(result, {})
        self.assertEqual(self.decision(self.run_hook(self.payload())), 'deny')
        # A deferred boundary for the same completed compaction is not another
        # checkpoint. Only an actual later PostCompact event rearms this window.
        self.append({'type': 'compacted', 'payload': {'message': 'summary'}})
        self.assertEqual(self.run_hook(self.payload()), {})

    def test_missing_identity_and_unwritable_state_never_deny_forever(self):
        for payload in (self.payload(session_id=''), self.payload(transcript_path=None)):
            self.assertNotEqual(self.decision(self.run_hook(payload)), 'deny')
        self.env['TMPDIR'] = str(self.root / 'does-not-exist')
        self.assertNotEqual(self.decision(self.run_hook(self.payload())), 'deny')

    def test_existing_engine_deny_ask_and_advisory_are_preserved(self):
        plugin = self.root / 'plugin'
        engine = plugin / 'scripts/owner-dispatch/owner-dispatch.sh'
        engine.parent.mkdir(parents=True)
        self.env['CLAUDE_PLUGIN_ROOT'] = str(plugin)
        for decision in ('deny', 'ask'):
            value = {'hookSpecificOutput': {'hookEventName': 'PreToolUse',
                     'permissionDecision': decision, 'permissionDecisionReason': 'existing boundary'}}
            engine.write_text("#!/bin/sh\nprintf '%s\\n' '" + json.dumps(value) + "'\n")
            self.assertEqual(self.run_hook(self.payload()), value)
        advisory = {'hookSpecificOutput': {'hookEventName': 'PreToolUse', 'additionalContext': 'existing advisory'}}
        engine.write_text("#!/bin/sh\nprintf '%s\\n' '" + json.dumps(advisory) + "'\n")
        value = self.run_hook(self.payload())
        self.assertEqual(self.decision(value), 'deny')
        self.assertEqual(value['hookSpecificOutput']['additionalContext'], 'existing advisory')
        self.assertEqual(self.run_hook(self.payload()), advisory)

    def test_missing_routing_rule_does_not_spend_attempt(self):
        spec = importlib.util.spec_from_file_location('checkpoint_rule_test', ROOT / 'hooks/skill-loading.py')
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
        with patch.dict(os.environ, self.env), patch.object(module, 'routing_rule', side_effect=ValueError):
            with self.assertRaises(ValueError):
                module.handle(self.payload(), {})
        self.assertEqual(self.attempts(), 0)
        self.assertEqual(self.decision(self.run_hook(self.payload())), 'deny')

    def test_invalid_engine_output_falls_back_to_original_bytes(self):
        engine = self.root / 'plugin/scripts/owner-dispatch/owner-dispatch.sh'
        engine.parent.mkdir(parents=True)
        self.env['CLAUDE_PLUGIN_ROOT'] = str(self.root / 'plugin')
        for output in ('diagnostic\n{"decision":"block"}', '[]', '{"decision":"block"}\n{}'):
            with self.subTest(output=output):
                engine.write_text("#!/bin/sh\nprintf '%s' '" + output + "'\n")
                result = subprocess.run(['bash', str(ROOT / 'hooks/owner-dispatch-guard.sh')],
                                        input=json.dumps(self.payload()), text=True, capture_output=True,
                                        env=self.env, cwd=self.root, timeout=10)
                self.assertEqual(result.returncode, 0)
                self.assertEqual(result.stderr, '')
                self.assertEqual(result.stdout, output)
                self.assertEqual(self.attempts(), 0)

    def test_delegation_load_and_checkpoint_are_current_context_scoped(self):
        for tool in ('Agent', 'spawn_agent'):
            with self.subTest(tool=tool):
                payload = self.payload(tool, session_id=tool, tool_input={'prompt': 'synthetic task'})
                result = self.run_hook(payload, 'guard-delegation-owner.sh')
                self.assertEqual(self.decision(result), 'deny')
                self.assertEqual(self.run_hook(payload, 'guard-delegation-owner.sh'), {})
        self.loaded()
        warm = self.payload('spawn_agent', session_id='warm', tool_input={})
        self.assertEqual(self.run_hook(warm, 'guard-delegation-owner.sh'), {})
        self.append({'type': 'compacted', 'payload': {'message': 'summary'}})
        self.assertEqual(self.decision(self.run_hook(warm, 'guard-delegation-owner.sh')), 'deny')
        self.loaded('fresh')
        self.assertEqual(self.run_hook(warm, 'guard-delegation-owner.sh'), {})

    def test_postcompact_high_watermark_prevents_old_delegation_load_resurrection(self):
        self.loaded()
        payload = self.payload('spawn_agent', tool_input={})
        self.assertEqual(self.run_hook(payload, 'guard-delegation-owner.sh'), {})
        self.compact()
        self.assertEqual(self.decision(self.run_hook(payload, 'guard-delegation-owner.sh')), 'deny')
        self.loaded('after-event')
        self.assertEqual(self.run_hook(payload, 'guard-delegation-owner.sh'), {})

    def test_precompact_alone_preserves_warm_context_and_attempt_cap(self):
        self.loaded()
        self.run_hook(self.payload())
        self.assertEqual(self.compact_event('PreCompact'), {})
        self.assertEqual(self.run_hook(self.payload()), {})
        self.assertEqual(self.run_hook(self.payload('spawn_agent'), 'guard-delegation-owner.sh'), {})
        self.assertEqual(self.attempts(), 1)

    def test_delayed_old_read_after_postcompact_is_not_fresh_proof(self):
        self.boundary()
        self.compact()
        self.loaded('delayed-old-pair')
        value = self.run_hook(self.payload('spawn_agent'), 'guard-delegation-owner.sh')
        self.assertEqual(self.decision(value), 'deny')
        self.assertEqual(self.attempts(), 1)

    def test_new_boundary_and_full_load_after_postcompact_need_no_checkpoint(self):
        self.compact()
        self.boundary()
        self.loaded('fresh')
        self.assertEqual(self.run_hook(self.payload('spawn_agent'), 'guard-delegation-owner.sh'), {})
        self.assertEqual(self.attempts(), 0)

    def test_boundary_flushed_before_postcompact_is_compared_with_precompact(self):
        self.boundary()
        self.compact_event('PreCompact')
        self.boundary()
        self.compact_event('PostCompact')
        self.loaded('fresh')
        self.assertEqual(self.run_hook(self.payload('spawn_agent'), 'guard-delegation-owner.sh'), {})
        self.assertEqual(self.attempts(), 0)

    def test_missing_precompact_does_not_accept_existing_boundary(self):
        self.boundary()
        self.compact_event('PostCompact')
        self.loaded('delayed')
        value = self.run_hook(self.payload('spawn_agent'), 'guard-delegation-owner.sh')
        self.assertEqual(self.decision(value), 'deny')

    def test_replaced_or_shrunken_transcript_never_restores_old_proof(self):
        self.loaded()
        self.compact()
        self.log.rename(self.root / 'old.jsonl')
        self.loaded('replacement-old')
        value = self.run_hook(self.payload('spawn_agent'), 'guard-delegation-owner.sh')
        self.assertIn('unavailable', value.get('systemMessage', ''))
        self.assertEqual(self.attempts(), 0)
        self.compact()
        self.log.write_text('')
        value = self.run_hook(self.payload('spawn_agent'), 'guard-delegation-owner.sh')
        self.assertIn('unavailable', value.get('systemMessage', ''))

    def test_boundary_arriving_between_snapshots_cannot_upgrade_old_proof(self):
        spec = importlib.util.spec_from_file_location('checkpoint_test', ROOT / 'hooks/skill-loading.py')
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
        record = {'generation': 'a' * 32, 'offset': 100, 'device': 1, 'inode': 1,
                  'before_context': 'start:0'}
        state = SimpleNamespace(read=lambda: record, close=lambda: None,
                                claim_attempt=lambda *args: True)
        snapshots = iter([
            {'context_complete': True, 'context_id': 'offset:100',
             'completed_skills': ['ccl-skills:multi-agent-delegation']},
            {'context_complete': True, 'context_id': 'native:200:after', 'completed_skills': []}])
        reader = SimpleNamespace(context_transcript=lambda *a, **kw: next(snapshots))
        info = SimpleNamespace(st_dev=1, st_ino=1, st_size=1000)
        with patch.object(module, 'State', return_value=state), \
                patch.object(module, 'normalizer', return_value=reader), \
                patch.object(module, 'regular_info', return_value=info):
            self.assertEqual(self.decision(module.handle(self.payload('spawn_agent'), {})), 'deny')
if __name__ == '__main__':
    unittest.main()
