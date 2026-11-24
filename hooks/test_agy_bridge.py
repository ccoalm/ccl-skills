#!/usr/bin/env python3
"""Antigravity bridge: protocol shapes, guard parity and evidence bounds.

Every case runs against synthetic repositories in a private TMPDIR; nothing
touches a real Antigravity installation.
"""
import importlib.util
import json
import os
from pathlib import Path
import io
import shlex
import shutil
import subprocess
import sys
import tempfile
import time
import unittest

ROOT = Path(__file__).resolve().parents[1]
BRIDGE = ROOT / 'hooks/agy-bridge.py'


def load_bridge():
    spec = importlib.util.spec_from_file_location('agy_bridge', BRIDGE)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def git(*args, cwd):
    subprocess.run(['git', *args], cwd=cwd, check=True, capture_output=True,
                   env={**os.environ, 'GIT_AUTHOR_NAME': 't', 'GIT_AUTHOR_EMAIL': 't@example.invalid',
                        'GIT_COMMITTER_NAME': 't', 'GIT_COMMITTER_EMAIL': 't@example.invalid'})


class BridgeCase(unittest.TestCase):
    def setUp(self):
        self.tmp = Path(tempfile.mkdtemp(prefix='ccl-agy-bridge-'))
        self.env = {**os.environ, 'TMPDIR': str(self.tmp / 'state')}
        for key in ('CLAUDECODE', 'CLAUDE_CODE_ENTRYPOINT', 'CLAUDE_PLUGIN_ROOT'):
            self.env.pop(key, None)
        (self.tmp / 'state').mkdir()

    def tearDown(self):
        shutil.rmtree(self.tmp, ignore_errors=True)

    def bridge(self, event, payload, root=ROOT, raw=None):
        result = subprocess.run(['python3', '-I', str(root / 'hooks/agy-bridge.py'), event],
                                input=raw if raw is not None else json.dumps(payload),
                                capture_output=True, text=True, timeout=90, env=self.env, cwd=root)
        self.assertEqual(result.returncode, 0, result.stderr)
        lines = result.stdout.strip().split('\n')
        self.assertEqual(len(lines), 1, result.stdout)
        return json.loads(lines[0])

    def protected_repo(self):
        repo = self.tmp / 'protected'
        repo.mkdir()
        git('init', '-q', '-b', 'main', cwd=repo)
        (repo / '.worktree-only').write_text('\n')
        (repo / 'notes.md').write_text('a\n')
        git('add', '.', cwd=repo)
        git('commit', '-q', '-m', 'init', cwd=repo)
        linked = self.tmp / 'linked'
        git('worktree', 'add', '-q', '-b', 'feature', str(linked), cwd=repo)
        return repo, linked

    def edit(self, name, args, cwd, conversation='conv-a'):
        return {'conversationId': conversation, 'hookEventName': 'PreToolUse', 'cwd': str(cwd),
                'workspacePaths': [str(cwd)], 'toolCall': {'id': 't1', 'name': name, 'args': args}}


class BindingTests(BridgeCase):
    def test_inventory_covers_every_command_hook(self):
        manifest = json.loads((ROOT / 'hooks/hooks.json').read_text())['hooks']
        scripts = {Path(hook['command'].split('"')[-2] if '"' in hook['command'] else hook['command'].split()[-1]).name
                   for groups in manifest.values() for group in groups for hook in group['hooks']}
        printed = subprocess.run(['python3', '-I', str(BRIDGE), '--bindings'], capture_output=True,
                                 text=True, check=True).stdout
        self.assertEqual(set(json.loads(printed)), scripts)

    def test_root_hooks_json_routes_every_event_through_the_bridge(self):
        config = json.loads((ROOT / 'hooks.json').read_text())['ccl-skills']
        self.assertEqual(set(config), {'SessionStart', 'PreInvocation', 'PreToolUse', 'PostToolUse', 'Stop'})
        commands = []
        for event, entries in config.items():
            for entry in entries:
                for handler in entry.get('hooks', [entry]):
                    commands.append((event, handler['command']))
        for event, command in commands:
            self.assertEqual(command, f'python3 -I ./hooks/agy-bridge.py {event}')
        matcher = config['PreToolUse'][0]['matcher'].split('|')
        bridge = load_bridge()
        self.assertEqual(set(matcher), set(bridge.EDIT_TOOLS) | {'run_command', 'invoke_subagent'})


class GuardParityTests(BridgeCase):
    def claude_guard(self, path):
        payload = {'session_id': 's', 'hook_event_name': 'PreToolUse', 'cwd': str(path.parent),
                   'tool_name': 'Write', 'tool_input': {'file_path': str(path)}}
        out = subprocess.run(['bash', str(ROOT / 'hooks/guard-edit-isolation.sh')], input=json.dumps(payload),
                             capture_output=True, text=True, env={**self.env, 'CLAUDE_PLUGIN_ROOT': str(ROOT)})
        decision = json.loads(out.stdout or '{}').get('hookSpecificOutput', {}).get('permissionDecision')
        return decision or 'allow'

    def test_primary_checkout_edits_are_denied_like_the_claude_path(self):
        repo, _ = self.protected_repo()
        target = repo / 'notes.md'
        self.assertEqual(self.claude_guard(target), 'deny')
        for name, args in (('write_file', {'Path': str(target), 'Content': 'x'}),
                           ('edit_file', {'Path': 'notes.md', 'Target': 'a', 'Replacement': 'b'}),
                           ('write_to_file', {'TargetFile': str(target), 'CodeContent': 'x'}),
                           ('replace_file_content', {'TargetFile': str(target)}),
                           ('create_file', {'Path': str(repo / 'new/dir/file.md')}),
                           ('apply_patch', {'Input': f'*** Begin Patch\n*** Update File: {target}\n*** End Patch'})):
            with self.subTest(name=name):
                result = self.bridge('PreToolUse', self.edit(name, args, repo))
                self.assertEqual(result['decision'], 'deny', result)
                self.assertIn('worktree', result['reason'])

    def test_linked_worktree_edit_is_allowed_like_the_claude_path(self):
        _, linked = self.protected_repo()
        target = linked / 'notes.md'
        self.assertEqual(self.claude_guard(target), 'allow')
        result = self.bridge('PreToolUse', self.edit('write_file', {'Path': str(target)}, linked))
        self.assertEqual(result, {'decision': 'allow'})

    def test_symlinked_target_into_protected_repo_is_denied(self):
        repo, _ = self.protected_repo()
        alias = self.tmp / 'alias'
        alias.symlink_to(repo)
        result = self.bridge('PreToolUse', self.edit('write_file', {'Path': str(alias / 'notes.md')}, self.tmp))
        self.assertEqual(result['decision'], 'deny', result)

    def test_symlink_inside_protected_primary_checkout_is_denied(self):
        repo, linked = self.protected_repo()
        outside = self.tmp / 'outside.txt'
        outside.write_text('outside\n')
        tracked_link = repo / 'tracked_link.txt'
        tracked_link.symlink_to(outside)
        dangling_link = repo / 'dangling_link.txt'
        dangling_link.symlink_to(self.tmp / 'missing' / 'target.txt')
        linked_link = linked / 'linked_link.txt'
        linked_link.symlink_to(outside)

        self.assertEqual(self.claude_guard(tracked_link), 'deny')
        patch = f'*** Begin Patch\n*** Delete File: {tracked_link}\n*** End Patch'
        deleted = self.bridge('PreToolUse', self.edit('apply_patch', {'Input': patch}, repo))
        self.assertEqual(deleted['decision'], 'deny', deleted)
        dangling = self.bridge('PreToolUse', self.edit('write_file', {'Path': str(dangling_link), 'Content': 'x'}, repo))
        self.assertEqual(dangling['decision'], 'deny', dangling)
        allowed = self.bridge('PreToolUse', self.edit('write_file', {'Path': str(linked_link), 'Content': 'x'}, linked))
        self.assertEqual(allowed, {'decision': 'allow'})

    def test_unknown_edit_target_fails_closed(self):
        result = self.bridge('PreToolUse', self.edit('write_file', {'Content': 'x'}, self.tmp))
        self.assertEqual(result['decision'], 'deny')
        self.assertIn('could not determine', result['reason'])

    def test_guard_that_cannot_run_fails_closed(self):
        copy = self.tmp / 'plugin'
        shutil.copytree(ROOT / 'hooks', copy / 'hooks')
        (copy / 'hooks/guard-edit-isolation.sh').write_text('#!/bin/sh\nexit 3\n')
        _, linked = self.protected_repo()
        result = self.bridge('PreToolUse', self.edit('write_file', {'Path': str(linked / 'notes.md')}, linked),
                             root=copy)
        self.assertEqual(result['decision'], 'deny')
        self.assertIn('could not run', result['reason'])

    def test_bridge_exception_on_guarded_tool_denies(self):
        result = self.bridge('PreToolUse', None, raw='[1, 2')
        self.assertEqual(result['decision'], 'deny')

    def test_malformed_tool_call_is_denied(self):
        for call in (None, {}, {'name': ''}, 'write_file'):
            with self.subTest(call=call):
                result = self.bridge('PreToolUse', {'conversationId': 'm', 'cwd': str(self.tmp), 'toolCall': call})
                self.assertEqual(result['decision'], 'deny')

    def test_relative_target_without_a_known_cwd_is_denied(self):
        _, linked = self.protected_repo()
        for extra in ({}, {'workspacePaths': str(linked)}, {'workspacePaths': [str(linked), str(self.tmp)]}):
            with self.subTest(extra=extra):
                result = self.bridge('PreToolUse', {'conversationId': 'r', **extra, 'toolCall': {
                    'id': 'x', 'name': 'write_file', 'args': {'Path': 'notes.md'}}})
                self.assertEqual(result['decision'], 'deny')
                self.assertIn('could not determine', result['reason'])

    def test_parent_component_through_a_symlinked_directory_is_resolved_by_the_guard(self):
        repo, linked = self.protected_repo()
        (repo / 'sub').mkdir()
        (linked / 'link').symlink_to(repo / 'sub')
        result = self.bridge('PreToolUse', self.edit('write_file', {'Path': 'link/../notes.md'}, linked))
        self.assertEqual(result['decision'], 'deny', result)

    def test_a_later_denied_target_beats_an_earlier_ask(self):
        copy = self.tmp / 'plugin'
        shutil.copytree(ROOT / 'hooks', copy / 'hooks')
        (copy / 'hooks/guard-edit-isolation.sh').write_text(
            '#!/bin/sh\nf=$(jq -r .tool_input.file_path)\ncase "$f" in *second*) d=deny ;; *) d=ask ;; esac\n'
            'printf \'{"hookSpecificOutput":{"permissionDecision":"%s","permissionDecisionReason":"%s"}}\\n\' "$d" "$d"\n')
        patch = '*** Begin Patch\n*** Update File: first.md\n*** Update File: second.md\n*** End Patch'
        result = self.bridge('PreToolUse', self.edit('apply_patch', {'Input': patch}, self.tmp), root=copy)
        self.assertEqual(result['decision'], 'deny', result)

    def test_patch_text_inside_file_contents_is_not_a_target(self):
        repo, linked = self.protected_repo()
        content = f'Example:\n*** Begin Patch\n*** Update File: {repo / "notes.md"}\n*** End Patch\n'
        result = self.bridge('PreToolUse', self.edit('write_file', {'Path': str(linked / 'doc.md'),
                                                                     'Content': content}, linked))
        self.assertEqual(result, {'decision': 'allow'})
        unknown = self.bridge('PreToolUse', self.edit('write_file', {'Content': content}, linked))
        self.assertEqual(unknown['decision'], 'deny')

    def test_unguarded_tool_is_allowed(self):
        self.assertEqual(self.bridge('PreToolUse', self.edit('read_file', {'Path': '/etc/hostname'}, self.tmp)),
                         {'decision': 'allow'})


class CommandTests(BridgeCase):
    def command(self, line, cwd):
        return self.edit('run_command', {'CommandLine': line}, cwd)

    def test_every_command_fails_closed_when_merge_guard_cannot_run(self):
        copy = self.tmp / 'plugin'
        shutil.copytree(ROOT / 'hooks', copy / 'hooks')
        (copy / 'hooks/guard-merge-authorization.sh').write_text('#!/bin/sh\nexit 3\n')
        for line in ('git push origin feature', 'git -C repo push origin feature', 'git "push" origin', "g'i't push",
                     'echo Z2l0IHB1c2g= | base64 -d | sh', 'ls -la'):
            with self.subTest(line=line):
                result = self.bridge('PreToolUse', self.command(line, self.tmp), root=copy)
                self.assertEqual(result['decision'], 'deny')
                self.assertIn('guard-merge-authorization.sh could not run', result['reason'])
        self.assertEqual(self.bridge('PreToolUse', self.command('ls -la', self.tmp))['decision'], 'allow',
                         'with a working merge guard an ordinary command still runs')

    def test_run_command_without_a_command_is_denied(self):
        result = self.bridge('PreToolUse', self.edit('run_command', {'Other': 'x'}, self.tmp))
        self.assertEqual(result['decision'], 'deny')

    def test_ordinary_command_is_allowed(self):
        self.assertEqual(self.bridge('PreToolUse', self.command('echo hi', self.tmp))['decision'], 'allow')

    def test_post_tool_use_prints_empty_object(self):
        payload = self.command('git status', self.tmp)
        payload['hookEventName'] = 'PostToolUse'
        self.assertEqual(self.bridge('PostToolUse', payload), {})


class EventShapeTests(BridgeCase):
    def test_session_start_injects_the_bootstrap(self):
        result = self.bridge('SessionStart', {'conversationId': 'c', 'cwd': str(self.tmp)})
        self.assertEqual(set(result), {'injectSteps'})
        text = result['injectSteps'][0]['systemMessage']['systemMessage']
        self.assertIn('ccl-skills-routing', text)

    def test_task_entry_runs_once_per_user_turn(self):
        transcript = self.tmp / 'logs/transcript_full.jsonl'
        transcript.parent.mkdir()
        steps = [{'type': 'USER_INPUT', 'source': 'USER_EXPLICIT', 'step_index': 0, 'content': 'add a feature'}]
        transcript.write_text(''.join(json.dumps(s) + '\n' for s in steps))
        base = {'conversationId': 'turns', 'cwd': str(self.tmp), 'lastUserInput': 'add a feature',
                'transcriptPath': str(transcript.with_name('transcript.jsonl'))}
        first = self.bridge('PreInvocation', {**base, 'invocationNum': 0, 'initialNumSteps': 1})
        self.assertIn('<ccl-task-entry>', first['injectSteps'][0]['systemMessage']['systemMessage'])
        steps.extend([
            {'type': 'PLANNER_RESPONSE', 'step_index': 1, 'tool_calls': [{'name': 'run_command', 'args': {'CommandLine': 'ls'}}]},
            {'type': 'GENERIC', 'status': 'DONE', 'step_index': 2, 'content': 'ok'},
        ])
        transcript.write_text(''.join(json.dumps(s) + '\n' for s in steps))
        self.assertEqual(self.bridge('PreInvocation', {**base, 'invocationNum': 1, 'initialNumSteps': 5}), {})
        # Next user turn with the exact same prompt text must still run task entry once.
        steps.append({'type': 'USER_INPUT', 'source': 'USER_EXPLICIT', 'step_index': 7, 'content': 'add a feature'})
        transcript.write_text(''.join(json.dumps(s) + '\n' for s in steps))
        again = self.bridge('PreInvocation', {**base, 'invocationNum': 0, 'initialNumSteps': 8})
        self.assertIn('<ccl-task-entry>', again['injectSteps'][0]['systemMessage']['systemMessage'])
        self.assertEqual(self.bridge('PreInvocation', {**base, 'invocationNum': 1, 'initialNumSteps': 12}), {})

        # Without a transcript file, invocationNum > 0 still stays in the current turn.
        notx = {'conversationId': 'turns-notx', 'cwd': str(self.tmp), 'lastUserInput': 'add a feature'}
        first_notx = self.bridge('PreInvocation', {**notx, 'invocationNum': 0, 'initialNumSteps': 4})
        self.assertIn('<ccl-task-entry>', first_notx['injectSteps'][0]['systemMessage']['systemMessage'])
        self.assertEqual(self.bridge('PreInvocation', {**notx, 'invocationNum': 1, 'initialNumSteps': 9}), {})
        next_notx = self.bridge('PreInvocation', {**notx, 'invocationNum': 0, 'initialNumSteps': 12})
        self.assertIn('<ccl-task-entry>', next_notx['injectSteps'][0]['systemMessage']['systemMessage'])

    def test_multi_step_turn_does_not_rearm_consumed_merge_grant(self):
        _, linked = self.protected_repo()
        transcript = self.tmp / 'merge-logs/transcript_full.jsonl'
        transcript.parent.mkdir()
        transcript.write_text(json.dumps({'type': 'USER_INPUT', 'source': 'USER_EXPLICIT',
                                          'step_index': 0, 'content': 'merge #123'}) + '\n')
        pre = {'conversationId': 'merge-once', 'cwd': str(linked), 'lastUserInput': 'merge #123',
               'transcriptPath': str(transcript.with_name('transcript.jsonl'))}
        self.bridge('PreInvocation', {**pre, 'invocationNum': 0, 'initialNumSteps': 1})

        merge_cmd = ' '.join(('gh', 'pr', 'merge', '123', '--merge'))
        merge_call = {'conversationId': 'merge-once', 'hookEventName': 'PreToolUse', 'cwd': str(linked),
                      'workspacePaths': [str(linked)], 'transcriptPath': pre['transcriptPath'],
                      'toolCall': {'id': 'm1', 'name': 'run_command', 'args': {'CommandLine': merge_cmd}}}
        first_merge = self.bridge('PreToolUse', merge_call)
        self.assertEqual(first_merge['decision'], 'allow', first_merge)
        second_merge = self.bridge('PreToolUse', merge_call)
        self.assertEqual(second_merge['decision'], 'deny', second_merge)

        # Next model step of the SAME user turn advances initialNumSteps; must not re-arm merge grant,
        # while queued advisory notes must still be delivered.
        bridge = load_bridge()
        os.environ['TMPDIR'] = self.env['TMPDIR']
        try:
            _, conv_key = bridge.conversation({'conversationId': 'merge-once'})
            bridge.push_notes(conv_key, ['advisory-step-2'])
        finally:
            del os.environ['TMPDIR']
        step2 = self.bridge('PreInvocation', {**pre, 'invocationNum': 1, 'initialNumSteps': 5})
        delivered_text = step2['injectSteps'][0]['systemMessage']['systemMessage']
        self.assertIn('advisory-step-2', delivered_text)
        self.assertNotIn('<ccl-task-entry>', delivered_text)
        third_merge = self.bridge('PreToolUse', merge_call)
        self.assertEqual(third_merge['decision'], 'deny', third_merge)

    def test_mid_turn_missing_or_late_transcript_preserves_turn_key(self):
        # Late transcript flush: step 0 sees no transcript yet, step 1 sees turn-0, step 2 sees absorbed turn-9.
        late_tx = self.tmp / 'late/transcript_full.jsonl'
        late_tx.parent.mkdir()
        base = {'conversationId': 'late-tx', 'cwd': str(self.tmp), 'lastUserInput': 'ship it',
                'transcriptPath': str(late_tx.with_name('transcript.jsonl'))}
        first = self.bridge('PreInvocation', {**base, 'invocationNum': 0, 'initialNumSteps': 1})
        self.assertIn('<ccl-task-entry>', first['injectSteps'][0]['systemMessage']['systemMessage'])
        late_tx.write_text(json.dumps({'type': 'USER_INPUT', 'source': 'USER_EXPLICIT', 'step_index': 0}) + '\n')
        self.assertEqual(self.bridge('PreInvocation', {**base, 'invocationNum': 1, 'initialNumSteps': 4}), {})
        late_tx.write_text(
            json.dumps({'type': 'USER_INPUT', 'source': 'USER_EXPLICIT', 'step_index': 0}) + '\n' +
            json.dumps({'type': 'USER_INPUT', 'source': 'USER_EXPLICIT', 'step_index': 9}) + '\n'
        )
        absorbed = self.bridge('PreInvocation', {**base, 'invocationNum': 2, 'initialNumSteps': 9,
                                                  'lastUserInput': 'also fix lint'})
        self.assertIn('<ccl-task-entry>', absorbed['injectSteps'][0]['systemMessage']['systemMessage'])

        # Oversized transcript tail drop: step 0 sees turn-0, step 1 loses turn_id (None) at invocationNum > 0.
        tail_tx = self.tmp / 'tail/transcript_full.jsonl'
        tail_tx.parent.mkdir()
        tail_tx.write_text(json.dumps({'type': 'USER_INPUT', 'source': 'USER_EXPLICIT', 'step_index': 0}) + '\n')
        tail_base = {'conversationId': 'tail-drop', 'cwd': str(self.tmp), 'lastUserInput': 'big turn',
                     'transcriptPath': str(tail_tx.with_name('transcript.jsonl'))}
        first_tail = self.bridge('PreInvocation', {**tail_base, 'invocationNum': 0, 'initialNumSteps': 1})
        self.assertIn('<ccl-task-entry>', first_tail['injectSteps'][0]['systemMessage']['systemMessage'])
        tail_tx.write_text(json.dumps({'type': 'GENERIC', 'status': 'DONE', 'step_index': 50}) + '\n')
        self.assertEqual(self.bridge('PreInvocation', {**tail_base, 'invocationNum': 3, 'initialNumSteps': 51}), {})

        # Stale transcript at start of a new user turn with identical prompt:
        # Turn 2 begins (invocationNum=0, initialNumSteps=8) before turn-7 flushes, then turn-7 flushes on step 1.
        stale_tx = self.tmp / 'stale/transcript_full.jsonl'
        stale_tx.parent.mkdir()
        stale_tx.write_text(json.dumps({'type': 'USER_INPUT', 'source': 'USER_EXPLICIT', 'step_index': 0}) + '\n')
        stale_base = {'conversationId': 'stale-turn2', 'cwd': str(self.tmp), 'lastUserInput': 'continue',
                      'transcriptPath': str(stale_tx.with_name('transcript.jsonl'))}
        t1 = self.bridge('PreInvocation', {**stale_base, 'invocationNum': 0, 'initialNumSteps': 1})
        self.assertIn('<ccl-task-entry>', t1['injectSteps'][0]['systemMessage']['systemMessage'])
        self.assertEqual(self.bridge('PreInvocation', {**stale_base, 'invocationNum': 1, 'initialNumSteps': 4}), {})
        t2_step0 = self.bridge('PreInvocation', {**stale_base, 'invocationNum': 0, 'initialNumSteps': 8})
        self.assertIn('<ccl-task-entry>', t2_step0.get('injectSteps', [{}])[0].get('systemMessage', {}).get('systemMessage', ''))
        stale_tx.write_text(
            json.dumps({'type': 'USER_INPUT', 'source': 'USER_EXPLICIT', 'step_index': 0}) + '\n' +
            json.dumps({'type': 'USER_INPUT', 'source': 'USER_EXPLICIT', 'step_index': 7}) + '\n'
        )
        self.assertEqual(self.bridge('PreInvocation', {**stale_base, 'invocationNum': 1, 'initialNumSteps': 12}), {})

        # New user turns at invocationNum=0 with identical prompt and NO initialNumSteps
        # (both with stale transcript and with no transcript at all).
        nosteps_tx = self.tmp / 'stale-nosteps/transcript_full.jsonl'
        nosteps_tx.parent.mkdir()
        nosteps_tx.write_text(json.dumps({'type': 'USER_INPUT', 'source': 'USER_EXPLICIT', 'step_index': 0}) + '\n')
        nosteps_base = {'conversationId': 'stale-nosteps', 'cwd': str(self.tmp), 'lastUserInput': 'continue',
                        'transcriptPath': str(nosteps_tx.with_name('transcript.jsonl'))}
        ns_t1 = self.bridge('PreInvocation', {**nosteps_base, 'invocationNum': 0})
        self.assertIn('<ccl-task-entry>', ns_t1.get('injectSteps', [{}])[0].get('systemMessage', {}).get('systemMessage', ''))
        self.assertEqual(self.bridge('PreInvocation', {**nosteps_base, 'invocationNum': 1}), {})
        ns_t2 = self.bridge('PreInvocation', {**nosteps_base, 'invocationNum': 0})
        self.assertIn('<ccl-task-entry>', ns_t2.get('injectSteps', [{}])[0].get('systemMessage', {}).get('systemMessage', ''))
        nosteps_tx.write_text(
            json.dumps({'type': 'USER_INPUT', 'source': 'USER_EXPLICIT', 'step_index': 0}) + '\n' +
            json.dumps({'type': 'USER_INPUT', 'source': 'USER_EXPLICIT', 'step_index': 7}) + '\n'
        )
        self.assertEqual(self.bridge('PreInvocation', {**nosteps_base, 'invocationNum': 1}), {})

        notx_nosteps = {'conversationId': 'notx-nosteps', 'cwd': str(self.tmp), 'lastUserInput': 'again'}
        nt_t1 = self.bridge('PreInvocation', {**notx_nosteps, 'invocationNum': 0})
        self.assertIn('<ccl-task-entry>', nt_t1.get('injectSteps', [{}])[0].get('systemMessage', {}).get('systemMessage', ''))
        nt_t2 = self.bridge('PreInvocation', {**notx_nosteps, 'invocationNum': 0})
        self.assertIn('<ccl-task-entry>', nt_t2.get('injectSteps', [{}])[0].get('systemMessage', {}).get('systemMessage', ''))

    def test_failed_task_entry_is_retried_in_the_same_turn(self):
        copy = self.tmp / 'plugin'
        shutil.copytree(ROOT / 'hooks', copy / 'hooks')
        shutil.copytree(ROOT / 'agent-context', copy / 'agent-context')
        real = (copy / 'hooks/task-entry.sh').read_text()
        (copy / 'hooks/task-entry.sh').write_text('#!/bin/sh\nexit 1\n')
        payload = {'conversationId': 'retry', 'cwd': str(self.tmp), 'lastUserInput': 'go', 'initialNumSteps': 1}
        self.assertEqual(self.bridge('PreInvocation', payload, root=copy), {})
        (copy / 'hooks/task-entry.sh').write_text(real)
        delivered = self.bridge('PreInvocation', payload, root=copy)
        self.assertIn('<ccl-task-entry>', delivered['injectSteps'][0]['systemMessage']['systemMessage'])

    def test_queued_notes_are_delivered_once(self):
        bridge = load_bridge()
        os.environ['TMPDIR'] = self.env['TMPDIR']
        try:
            _, key = bridge.conversation({'conversationId': 'notes'})
            bridge.push_notes(key, ['reminder one', '', 'reminder one'])
        finally:
            del os.environ['TMPDIR']
        payload = {'conversationId': 'notes', 'cwd': str(self.tmp)}
        first = self.bridge('PreInvocation', payload)
        self.assertEqual(first['injectSteps'][0]['systemMessage']['systemMessage'], 'reminder one')
        self.assertEqual(self.bridge('PreInvocation', payload), {})

    def test_stop_respects_continuation_and_termination(self):
        base = {'conversationId': 'stop', 'cwd': str(self.tmp)}
        self.assertEqual(self.bridge('Stop', {**base, 'continuationActive': True}), {'decision': 'allow'})
        self.assertEqual(self.bridge('Stop', {**base, 'terminationReason': 'USER_CANCELED'}), {'decision': 'allow'})
        result = self.bridge('Stop', {**base, 'terminationReason': 'NO_TOOL_CALL'})
        self.assertIn(result['decision'], ('allow', 'continue'))

    def test_stop_maps_a_blocking_hook_to_continue(self):
        copy = self.tmp / 'plugin'
        shutil.copytree(ROOT / 'hooks', copy / 'hooks')
        (copy / 'hooks/proposed-next-stop.sh').write_text(
            '#!/bin/sh\necho \'{"decision":"block","reason":"finish the named step"}\'\n')
        base = {'conversationId': 'stop', 'cwd': str(self.tmp), 'terminationReason': 'NO_TOOL_CALL'}
        result = self.bridge('Stop', base, root=copy)
        self.assertEqual(result, {'decision': 'continue', 'reason': 'finish the named step'})
        # The same blocking hook must not loop once a Stop continuation is active,
        # nor fire after an error or cancellation.
        self.assertEqual(self.bridge('Stop', {**base, 'continuationActive': True}, root=copy),
                         {'decision': 'allow'})
        self.assertEqual(self.bridge('Stop', {**base, 'terminationReason': 'ERROR'}, root=copy),
                         {'decision': 'allow'})

    def test_subagent_dispatch_needs_the_delegation_owner_then_gets_context(self):
        payload = {'conversationId': 'sub', 'cwd': str(self.tmp),
                   'toolCall': {'id': 's1', 'name': 'invoke_subagent',
                                'args': {'TypeName': 'general', 'Role': 'Researcher', 'Prompt': 'Find X'}}}
        blocked = self.bridge('PreToolUse', payload)
        self.assertEqual(blocked['decision'], 'deny')
        self.assertIn('multi-agent-delegation', blocked['reason'])
        skill = ROOT / 'skills/multi-agent-delegation/SKILL.md'
        lines = skill.read_text().split('\n')[:-1]
        transcript = self.tmp / 'logs/transcript_full.jsonl'
        transcript.parent.mkdir()
        steps = [{'type': 'USER_INPUT', 'source': 'USER_EXPLICIT', 'step_index': 0, 'content': 'go'},
                 {'type': 'PLANNER_RESPONSE', 'step_index': 1, 'tool_calls': [
                     {'name': 'read_file', 'args': {'Path': str(skill)}}]},
                 {'type': 'GENERIC', 'status': 'DONE', 'step_index': 2, 'content':
                  f'Showing lines 1-{len(lines)} of {len(lines)}\n' +
                  '\n'.join(f'{n}: {line}' for n, line in enumerate(lines, start=1))}]
        transcript.write_text(''.join(json.dumps(step) + '\n' for step in steps))
        result = self.bridge('PreToolUse', {**payload, 'transcriptPath': str(transcript.with_name('transcript.jsonl'))})
        self.assertEqual(result['decision'], 'allow', result)
        prompt = result['overwrite']['Prompt']
        self.assertTrue(prompt.endswith('Find X'))
        self.assertGreater(len(prompt), len('Find X'))


class EvidenceTests(BridgeCase):
    def skill_steps(self, path, ranges, total=None, mutate=None):
        lines = (ROOT / 'skills/grill-me/SKILL.md').read_text().split('\n')[:-1]
        steps = [{'type': 'USER_INPUT', 'source': 'USER_EXPLICIT', 'step_index': 0, 'content': 'x'}]
        for number, (first, last) in enumerate(ranges, start=1):
            body = [f'{n}: {lines[n - 1]}' for n in range(first, last + 1)]
            if mutate and number == 1:
                body[0] = mutate(body[0])
            steps.append({'type': 'PLANNER_RESPONSE', 'step_index': number * 2 - 1, 'tool_calls': [
                {'name': 'read_file', 'args': {'Path': str(path), 'StartLine': first, 'EndLine': last}}]})
            steps.append({'type': 'GENERIC', 'status': 'DONE', 'step_index': number * 2, 'content':
                          f'Showing lines {first}-{last} of {total or len(lines)}\n' + '\n'.join(body)})
        return steps, len(lines)

    def loaded(self, steps):
        events, _, _ = load_bridge().shadow_events(steps, str(self.tmp))
        return [item['input']['skill'] for event in events
                for item in event['message']['content'] if item.get('name') == 'Skill']

    def test_full_coverage_counts_as_a_load(self):
        path = ROOT / 'skills/grill-me/SKILL.md'
        _, total = self.skill_steps(path, [(1, 1)])
        steps, _ = self.skill_steps(path, [(1, total // 2), (total // 2 + 1, total)])
        self.assertEqual(self.loaded(steps), ['ccl-skills:grill-me'])

    def test_partial_read_is_not_a_load(self):
        path = ROOT / 'skills/grill-me/SKILL.md'
        steps, _ = self.skill_steps(path, [(1, 5)])
        self.assertEqual(self.loaded(steps), [])

    def test_forged_or_mismatched_reads_are_not_a_load(self):
        path = ROOT / 'skills/grill-me/SKILL.md'
        _, total = self.skill_steps(path, [(1, 1)])
        forged, _ = self.skill_steps(path, [(1, total)], mutate=lambda row: row + ' tampered')
        self.assertEqual(self.loaded(forged), [])
        wrong_total, _ = self.skill_steps(path, [(1, total)], total=total + 1)
        self.assertEqual(self.loaded(wrong_total), [])
        copy = self.tmp / 'skills/grill-me/SKILL.md'
        copy.parent.mkdir(parents=True)
        copy.write_text(path.read_text() + 'extra\n')
        different, _ = self.skill_steps(copy, [(1, total)])
        self.assertEqual(self.loaded(different), [])

    def test_swapped_parallel_results_give_no_false_evidence(self):
        path = ROOT / 'skills/grill-me/SKILL.md'
        steps, total = self.skill_steps(path, [(1, 1)])
        steps, _ = self.skill_steps(path, [(1, total)])
        other = {'type': 'GENERIC', 'status': 'DONE', 'step_index': 3, 'content': 'Showing lines 1-1 of 1\n1: hello'}
        call = {'name': 'read_file', 'args': {'Path': str(self.tmp / 'other.txt')}}
        swapped = [steps[0], {**steps[1], 'tool_calls': steps[1]['tool_calls'] + [call]}, other, steps[2]]
        self.assertEqual(self.loaded(swapped), [], 'the skill call was paired with the other file and must not count')

    def test_identical_copy_counts_as_a_load(self):
        path = ROOT / 'skills/grill-me/SKILL.md'
        copy = self.tmp / 'skills/grill-me/SKILL.md'
        copy.parent.mkdir(parents=True)
        shutil.copyfile(path, copy)
        _, total = self.skill_steps(path, [(1, 1)])
        steps, _ = self.skill_steps(copy, [(1, total)])
        self.assertEqual(self.loaded(steps), ['ccl-skills:grill-me'])

    def test_shadow_transcript_is_private_structural_and_empty_after_the_event(self):
        transcript = self.tmp / 'logs/transcript.jsonl'
        transcript.parent.mkdir()
        transcript.write_text(json.dumps({'type': 'USER_INPUT', 'source': 'USER_EXPLICIT', 'step_index': 0,
                                          'content': 'secret-user-text'}) + '\n')
        copy = self.tmp / 'plugin'
        shutil.copytree(ROOT / 'hooks', copy / 'hooks')
        capture = self.tmp / 'captured'
        (copy / 'hooks/proposed-next-stop.sh').write_text(
            '#!/bin/sh\nt=$(jq -r .transcript_path)\npython3 -c "import os,stat,sys; s=os.stat(sys.argv[1]); '
            f'print(s.st_ino, oct(stat.S_IMODE(s.st_mode))[2:])" "$t" >> {shlex.quote(str(capture) + ".ids")}\n'
            f'cp "$t" {shlex.quote(str(capture))}\n')
        stop = {'conversationId': 'priv', 'cwd': str(self.tmp), 'transcriptPath': str(transcript),
                'terminationReason': 'NO_TOOL_CALL'}
        between = []

        def event(name, payload):
            self.bridge(name, payload, root=copy)
            shadow = next(next((self.tmp / 'state').glob('ccl-skills-agy-*')).glob('*.jsonl'))
            info = shadow.stat()
            between.append((info.st_ino, info.st_mode & 0o777, info.st_size))
        event('Stop', stop)
        self.assertNotIn('secret-user-text', capture.read_text())
        self.assertIn('turn-0', capture.read_text())
        edit = self.edit('write_file', {'Path': str(self.tmp / 'notes.md')}, self.tmp, conversation='priv')
        event('PreToolUse', {**edit, 'transcriptPath': str(transcript)})
        event('PreToolUse', {**self.edit('run_command', {'CommandLine': 'ls'}, self.tmp, conversation='priv'),
                             'transcriptPath': str(transcript)})
        event('Stop', stop)
        self.assertEqual(len({inode for inode, _, _ in between}), 1, between)
        self.assertEqual({(mode, size) for _, mode, size in between}, {(0o600, 0)},
                         'after every event the shadow is private and empty')
        seen = [line.split() for line in capture.with_name('captured.ids').read_text().splitlines()]
        self.assertEqual(len(seen), 2)
        self.assertEqual({mode for _, mode in seen}, {'600'})
        self.assertEqual(seen[0][0], seen[1][0], 'every event must hand the hooks the same transcript inode')
        state = next((self.tmp / 'state').glob('ccl-skills-agy-*'))
        self.assertEqual(state.stat().st_mode & 0o777, 0o700)
        shadows = list(state.glob('*.jsonl'))
        self.assertEqual(len(shadows), 1)
        self.assertEqual(str(shadows[0].stat().st_ino), seen[0][0])
        self.assertEqual(shadows[0].stat().st_size, 0, 'no transcript-derived content may outlive the event')

    def test_results_pair_only_when_unambiguous_and_done(self):
        path = ROOT / 'skills/grill-me/SKILL.md'
        steps, total = self.skill_steps(path, [(1, 1)])
        steps, _ = self.skill_steps(path, [(1, total)])
        running = [dict(s) for s in steps]
        running[2]['status'] = 'RUNNING'
        self.assertEqual(self.loaded(running), [])
        extra_call = [dict(s) for s in steps]
        extra_call[1] = {**steps[1], 'tool_calls': steps[1]['tool_calls'] + [
            {'name': 'run_command', 'args': {'CommandLine': 'ls'}}]}
        self.assertEqual(self.loaded(extra_call), [])


class PartialReadTests(BridgeCase):
    """read_file answers past its byte limit with `Partial read ... Showing bytes S-E of Z`.

    The offsets index the formatted stream `"\\n".join(f"{n}: {line}")` in UTF-8 bytes; the
    tool cuts at a character boundary at or below the limit and its hint names the next offset.
    A synthetic bundled skill in a private plugin copy keeps the byte layout under test control.
    """
    LIMIT = 46080

    def setUp(self):
        super().setUp()
        self.plugin = self.tmp / 'plugin'
        (self.plugin / 'hooks').mkdir(parents=True)
        shutil.copyfile(BRIDGE, self.plugin / 'hooks/agy-bridge.py')
        self.skill, self.lines, self.stream = self.make('sample-skill', 'x')
        self.assertGreater(len(self.stream), 2 * self.LIMIT)
        self.assertLess(len(self.stream), 3 * self.LIMIT)

    def make(self, slug, filler, extra=()):
        lines = ['---', f'name: {slug}', 'description: synthetic fixture', '---']
        lines += [f'Rule {i}: ' + '中文' * (i % 7) + filler * (20 + i % 50) for i in range(1500)]
        lines[900:900] = list(extra)
        path = self.plugin / 'skills' / slug / 'SKILL.md'
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text('\n'.join(lines) + '\n')
        stream = '\n'.join(f'{n}: {line}' for n, line in enumerate(lines, start=1)).encode()
        return path, lines, stream

    def cut(self, start, stream=None):
        stream = self.stream if stream is None else stream
        end = min(start + self.LIMIT, len(stream))
        while end < len(stream) and stream[end] & 0xC0 == 0x80:
            end -= 1
        return end

    def tile(self, *starts, stream=None):
        """Chunks covering the stream, with extra request offsets forced in."""
        stream = self.stream if stream is None else stream
        spans, start, forced = [], 0, sorted(set(starts))
        while start < len(stream):
            end = min([self.cut(start, stream)] + [s for s in forced if s > start])
            spans.append((start, end))
            start = end
        return spans

    def result(self, start, end, body=None, size=None, total=None, shown_start=None, stream=None, lines=None):
        stream = self.stream if stream is None else stream
        lines = self.lines if lines is None else lines
        size = len(stream) if size is None else size
        header = (f'Partial read (lines 1-{len(lines)} of {total or len(lines)}). Showing bytes '
                  f'{start if shown_start is None else shown_start}-{end} of {size} in this line range')
        header += (f', truncated at the {self.LIMIT}-byte limit. To read the rest of this line range, call this '
                   f'tool again with the same StartLine and EndLine and ByteOffset={end}.' if end < len(stream)
                   else '.')
        text = stream[start:end].decode() if body is None else body
        return f'Created At: t\nCompleted At: t\n{header}\n{text}'

    def loaded(self, results, parallel=False):
        """`results` are (offset, content) for the main skill or (path, offset, content)."""
        results = [r if len(r) == 3 else (self.skill, *r) for r in results]
        steps = [{'type': 'USER_INPUT', 'source': 'USER_EXPLICIT', 'step_index': 0, 'content': 'x'}]
        calls = [{'name': 'read_file', 'args': {'Path': str(path), 'ByteOffset': offset}} for path, offset, _ in results]
        done = [{'type': 'GENERIC', 'status': 'DONE', 'content': content} for _, _, content in results]
        if parallel:
            steps += [{'type': 'PLANNER_RESPONSE', 'tool_calls': calls}] + done
        else:
            for call, outcome in zip(calls, done):
                steps += [{'type': 'PLANNER_RESPONSE', 'tool_calls': [call]}, outcome]
        steps = [dict(step, step_index=index) for index, step in enumerate(steps)]
        spec = importlib.util.spec_from_file_location('agy_bridge_copy', self.plugin / 'hooks/agy-bridge.py')
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
        events, _, _ = module.shadow_events(steps, str(self.tmp))
        return [item['input']['skill'] for event in events
                for item in event['message']['content'] if item.get('name') == 'Skill']

    def good(self, spans=None):
        return [(start, self.result(start, end)) for start, end in (spans or self.tile())]

    def test_parallel_byte_chunks_covering_the_skill_count_as_a_load(self):
        spans = self.tile()
        self.assertEqual(len(spans), 3)
        self.assertTrue(any(self.stream[end - 1:end] != b'\n' and self.stream[end:end + 1] != b'\n'
                            for _, end in spans[:-1]), 'fixture must cut inside a line')
        results = self.good(spans)
        self.assertEqual(self.loaded(results, parallel=True), ['ccl-skills:sample-skill'])
        self.assertEqual(self.loaded(results[::-1]), ['ccl-skills:sample-skill'])

    def test_an_offset_inside_a_character_counts_where_the_host_really_started(self):
        inside = next(n for n in range(self.LIMIT, len(self.stream)) if self.stream[n] & 0xC0 == 0x80)
        lead = inside
        while self.stream[lead] & 0xC0 == 0x80:
            lead -= 1
        spans = self.tile(lead)
        at = next(i for i, (start, _) in enumerate(spans) if start == lead)
        rest = spans[at][1]
        results = self.good(spans)
        # The host answers ByteOffset=inside from the character's first byte but echoes `inside`.
        results[at] = (inside, self.result(lead, rest, shown_start=inside))
        self.assertEqual(self.loaded(results), ['ccl-skills:sample-skill'])
        # A body reaching back past that character's first byte is not the host's answer.
        results[at] = (inside, self.result(lead - 1, rest, shown_start=inside))
        self.assertEqual(self.loaded(results), [], 'back-off stops at the character that holds the offset')

    def test_a_cut_line_counts_only_once_some_chunk_shows_it_whole(self):
        (_, e1), *_ = self.tile()
        resume = self.stream.rfind(b'\n', 0, e1) + 1
        self.assertLess(resume, e1)
        reread = [(0, self.result(0, e1))] + [r for r in self.good(self.tile(resume)) if r[0] >= resume]
        self.assertEqual(self.loaded(reread), ['ccl-skills:sample-skill'])
        skip = self.stream.index(b'\n', e1) + 1
        skipped = [(0, self.result(0, e1))] + [r for r in self.good(self.tile(skip)) if r[0] >= skip]
        self.assertEqual(self.loaded(skipped), [], 'the line cut at the first boundary was never shown whole')

    def test_every_separator_byte_must_be_shown(self):
        newline = self.stream.index(b'\n', self.LIMIT // 2)
        spans = [span for span in self.tile(newline, newline + 1) if span != (newline, newline + 1)]
        self.assertEqual(self.loaded(self.good(spans)), [], 'one row separator was never shown')
        self.assertEqual(self.loaded(self.good(self.tile(newline, newline + 1))), ['ccl-skills:sample-skill'])

    def test_header_like_text_at_the_start_of_a_chunk_body_is_not_a_header(self):
        self.skill, self.lines, self.stream = self.make('sample-skill', 'x', extra=['Showing lines 1-2 of 3'])
        text = self.stream.index(b'Showing lines 1-2 of 3')
        self.assertEqual(self.loaded(self.good(self.tile(text))), ['ccl-skills:sample-skill'])

    def test_byte_intervals_of_two_skills_never_combine(self):
        other, other_lines, other_stream = self.make('sample-other', 'y')
        self.assertEqual(len(other_stream), len(self.stream))
        first, *rest = self.tile()
        mixed = [(self.skill, first[0], self.result(*first))]
        mixed += [(other, start, self.result(start, end, stream=other_stream, lines=other_lines))
                  for start, end in rest]
        self.assertEqual(self.loaded(mixed), [])
        complete = mixed + [(self.skill, start, self.result(start, end)) for start, end in rest]
        self.assertEqual(self.loaded(complete), ['ccl-skills:sample-skill'])
        both = complete + [(other, first[0], self.result(*first, stream=other_stream, lines=other_lines))]
        self.assertEqual(sorted(self.loaded(both)), ['ccl-skills:sample-other', 'ccl-skills:sample-skill'])

    def test_many_claimed_ranges_keep_one_canonical_copy(self):
        spec = importlib.util.spec_from_file_location('agy_bridge_copy', self.plugin / 'hooks/agy-bridge.py')
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
        spans, total = {}, len(self.lines)
        for first in range(1, 401):
            content = (f'Partial read (lines {first}-{total} of {total}). Showing bytes 0-1 of 1 in this line range.'
                       '\nx')
            self.assertEqual(module.covered_lines(content, self.lines, spans), set())
        stored = [value for value in spans.values() if isinstance(value, tuple)]
        self.assertEqual(len(stored), 1)
        self.assertEqual(len(stored[0][0]), len(self.stream))

    def module(self):
        spec = importlib.util.spec_from_file_location('agy_bridge_copy', self.plugin / 'hooks/agy-bridge.py')
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
        return module

    def ranged(self, first, last, start, end):
        """A result for an explicit StartLine/EndLine read; offsets are relative to that range."""
        rows = '\n'.join(f'{n}: {self.lines[n - 1]}' for n in range(first, last + 1)).encode()
        header = (f'Partial read (lines {first}-{last} of {len(self.lines)}). Showing bytes {start}-{end} of '
                  f'{len(rows)} in this line range.')
        return f'{header}\n{rows[start:end].decode()}', len(rows)

    def row_start(self, number):
        return len('\n'.join(f'{n}: {self.lines[n - 1]}' for n in range(1, number)).encode()) + (number > 1)

    def test_reads_of_different_line_ranges_combine(self):
        total, k = len(self.lines), 700
        cut = self.row_start(k) + 3  # stops inside row k
        module, spans = self.module(), {}
        head, _ = self.ranged(1, total, 0, cut)
        self.assertNotIn(k, module.covered_lines(head, self.lines, spans))
        _, size = self.ranged(k, total, 0, 1)
        resume = cut - self.row_start(k)  # the rest of row k, in the second range's offsets
        tail, _ = self.ranged(k, total, resume, size)
        self.assertEqual(module.covered_lines(tail, self.lines, dict(spans)), set(range(1, total + 1)))
        gap, _ = self.ranged(k, total, resume + 1, size)
        self.assertNotIn(k, module.covered_lines(gap, self.lines, dict(spans)), 'one byte of row k unread')
        adjacent = {}
        _, size_a = self.ranged(1, k, 0, 1)
        _, size_b = self.ranged(k + 1, total, 0, 1)
        module.covered_lines(self.ranged(1, k, 0, size_a)[0], self.lines, adjacent)
        shown = module.covered_lines(self.ranged(k + 1, total, 0, size_b)[0], self.lines, adjacent)
        self.assertEqual(shown, set(range(1, total + 1)), 'two whole adjacent ranges cover every row')

    def test_a_right_sized_header_over_a_short_body_is_not_a_load(self):
        (s1, e1), (s2, e2), (s3, e3) = self.tile()
        short = (s2, self.result(s2, e2, body=self.stream[s2:s2 + 10].decode()))
        self.assertEqual(self.loaded([self.good()[0], short, self.good()[2]]), [])
        # The rejection must not copy the claimed interval first.
        import tracemalloc
        module, spans = self.module(), {}
        module.covered_lines(self.good()[0][1], self.lines, spans)
        content = short[1]
        tracemalloc.start()
        try:
            module.covered_lines(content, self.lines, spans)
            _, peak = tracemalloc.get_traced_memory()
        finally:
            tracemalloc.stop()
        self.assertLess(peak, (e2 - s2) // 2, 'a short body is rejected before the claimed interval is copied')

    def test_incomplete_or_mismatched_chunks_are_not_a_load(self):
        (s1, e1), (s2, e2), (s3, e3) = self.tile()
        good = self.good()
        middle = self.stream[s2:e2].decode()
        tampered = middle[:100] + ('X' if middle[100] != 'X' else 'Y') + middle[101:]
        row = middle.index('\n') + 1
        number = middle[row:].split(':', 1)[0]
        renumbered = number[:-1] + ('1' if number[-1] == '0' else '0')
        forged = middle[:row] + renumbered + middle[row + len(number):]
        self.assertEqual(len(forged.encode()), len(middle.encode()))
        self.assertNotEqual(forged, middle)
        cases = {
            'missing middle': [good[0], good[2]],
            'tampered byte': [good[0], (s2, self.result(s2, e2, body=tampered)), good[2]],
            'forged line number': [good[0], (s2, self.result(s2, e2, body=forged)), good[2]],
            'wrong byte total': [good[0], (s2, self.result(s2, e2, size=len(self.stream) + 1)), good[2]],
            'wrong line total': [good[0], (s2, self.result(s2, e2, total=len(self.lines) + 1)), good[2]],
            'misplaced start': [good[0], (s2, self.result(s2, e2, shown_start=s2 - 1)), good[2]],
            'cut tail never read': good[:2],
        }
        for name, results in cases.items():
            with self.subTest(case=name):
                self.assertEqual(self.loaded(results), [])
        self.assertEqual(self.loaded(good), ['ccl-skills:sample-skill'], 'control')


class ShadowIdentityTests(BridgeCase):
    def state(self):
        bridge = load_bridge()
        previous = os.environ.get('TMPDIR')
        os.environ['TMPDIR'] = self.env['TMPDIR']
        try:
            return bridge, bridge.state_dir()
        finally:
            if previous is None:
                del os.environ['TMPDIR']
            else:
                os.environ['TMPDIR'] = previous

    def key(self, bridge, conversation):
        return bridge.conversation({'conversationId': conversation})[1]

    def test_source_edit_checkpoint_fires_once_per_conversation(self):
        # ext4 often hands a freed inode straight back to the next file, which hid the
        # churn; tmpfs numbers never repeat, so the state lives there when it exists.
        shm = Path('/dev/shm')
        if shm.is_dir() and os.access(shm, os.W_OK):
            state = Path(tempfile.mkdtemp(prefix='ccl-agy-bridge-', dir=shm))
            self.addCleanup(shutil.rmtree, state, True)
            self.env['TMPDIR'] = str(state)
        work = self.tmp / 'work'
        work.mkdir()
        transcript = self.tmp / 'logs/transcript_full.jsonl'
        transcript.parent.mkdir()
        transcript.write_text(json.dumps({'type': 'USER_INPUT', 'source': 'USER_EXPLICIT', 'step_index': 0,
                                          'content': 'fix it'}) + '\n')

        def edit(name):
            return {**self.edit(name, {'Path': str(work / 'module.py')}, work, conversation='once'),
                    'transcriptPath': str(transcript.with_name('transcript.jsonl'))}
        first = self.bridge('PreToolUse', edit('edit_file'))
        self.assertEqual(first['decision'], 'deny', first)
        self.assertIn('First source-edit skill checkpoint', first['reason'])
        self.assertEqual(self.bridge('PreToolUse', {**self.edit('run_command', {'CommandLine': 'ls'}, work,
                                                                conversation='once')})['decision'], 'allow')
        self.assertEqual(self.bridge('PreToolUse', edit('edit_file')), {'decision': 'allow'})
        self.assertEqual(self.bridge('PreToolUse', edit('write_file')), {'decision': 'allow'})
        other = self.bridge('PreToolUse', {**edit('edit_file'), 'conversationId': 'another'})
        self.assertEqual(other['decision'], 'deny', 'a different conversation is a different context')

    def test_an_unsafe_shadow_path_blocks_and_is_not_written_through(self):
        bridge, state = self.state()
        for name, plant in (('symlink', lambda target, path: path.symlink_to(target)),
                            ('hardlink', lambda target, path: os.link(target, path))):
            with self.subTest(kind=name):
                target = self.tmp / f'{name}-target.txt'
                target.write_text('keep\n')
                shadow = state / f'{self.key(bridge, name)}.jsonl'
                plant(target, shadow)
                result = self.bridge('PreToolUse', self.edit('run_command', {'CommandLine': 'echo hi'}, self.tmp,
                                                             conversation=name))
                self.assertEqual(result['decision'], 'deny', result)
                self.assertEqual(target.read_text(), 'keep\n')
                self.assertEqual(shadow.is_symlink(), name == 'symlink', 'the planted entry is left in place')
                self.assertEqual(target.stat().st_nlink, 2 if name == 'hardlink' else 1)

    def test_a_new_conversation_empties_only_stale_unlocked_leftover_shadows(self):
        bridge, state = self.state()
        old = time.time() - 25 * 3600
        key = {name: self.key(bridge, name) for name in ('left', 'fresh', 'held', 'paused', 'linked',
                                                       'unlocked', 'multi')}
        outside = self.tmp / 'outside.jsonl'
        outside.write_text('keep\n')
        content = {
            f'{key["left"]}.jsonl': 'left', f'{key["fresh"]}.jsonl': 'fresh', f'{key["held"]}.jsonl': 'held',
            f'{key["paused"]}.jsonl': '', f'{key["left"]}.4242.tmp': 'temp', 'notes.tmp': 'other',
            f'{key["fresh"]}.run.lock': '', f'{key["fresh"]}.4244.tmp': 'fresh temp',
            f'{key["linked"]}.run.lock': '',
            f'{key["held"]}.4243.tmp': 'temp of a running event',
            'other.jsonl': 'other', 'other.run.lock': '', f'{key["left"]}.lock': '', f'{key["left"]}.run.lock': '',
            f'{key["left"]}.active.turn': '{}', f'{key["unlocked"]}.jsonl': 'no lock file',
            f'{key["multi"]}.run.lock': '', f'{key["left"]}.04242.tmp': 'leading zero',
            f'{key["left"]}.\u0664\u0662.tmp': 'not ascii digits'}
        for name, text in content.items():
            (state / name).write_text(text)
            if not name.startswith(key['fresh']):
                os.utime(state / name, (old, old))
        inode = (state / f'{key["left"]}.jsonl').stat().st_ino
        paused = (state / f'{key["paused"]}.jsonl').stat().st_ino
        twin = self.tmp / 'twin.txt'
        twin.write_text('multi\n')
        os.utime(twin, (old, old))
        os.link(twin, state / f'{key["multi"]}.jsonl')
        link = state / f'{key["linked"]}.jsonl'
        link.symlink_to(outside)
        os.utime(outside, (old, old))
        os.utime(link, (old, old), follow_symlinks=False)
        holder = subprocess.Popen(['python3', '-c', 'import fcntl,os,sys,time; fd=os.open(sys.argv[1], os.O_WRONLY|os.O_CREAT, 0o600); '
                                   'fcntl.flock(fd, fcntl.LOCK_EX); print("held", flush=True); time.sleep(30)',
                                   str(state / f'{key["held"]}.run.lock')], stdout=subprocess.PIPE, text=True)
        try:
            self.assertEqual(holder.stdout.readline().strip(), 'held')
            swept = self.bridge('PreToolUse', self.edit('run_command', {'CommandLine': 'ls'}, self.tmp,
                                                       conversation='sweeper'))
        finally:
            holder.kill()
            holder.wait()
            holder.stdout.close()
        expected = dict(content, **{f'{key["left"]}.jsonl': ''})
        del expected[f'{key["left"]}.4242.tmp']
        for name, text in expected.items():
            with self.subTest(file=name):
                self.assertEqual((state / name).read_text(), text)
        self.assertFalse((state / f'{key["left"]}.4242.tmp').exists(), 'the old scheme left this temp file')
        self.assertEqual((state / f'{key["left"]}.jsonl').stat().st_ino, inode, 'emptied, not replaced')
        self.assertEqual((state / f'{key["paused"]}.jsonl').stat().st_ino, paused, 'a paused conversation keeps its identity')
        self.assertTrue(link.is_symlink(), 'a link is not a regular shadow file')
        self.assertEqual(outside.read_text(), 'keep\n')
        self.assertEqual(twin.read_text(), 'multi\n', "another conversation's linked file is left alone")
        self.assertEqual(swept['decision'], 'allow', "another conversation's unsafe file does not block this one")
        self.assertEqual((state / f'{self.key(bridge, "sweeper")}.jsonl').stat().st_size, 0)


    def test_event_end_empties_the_inode_it_wrote_even_after_a_rename(self):
        copy = self.tmp / 'plugin'
        shutil.copytree(ROOT / 'hooks', copy / 'hooks')
        (copy / 'hooks/proposed-next-stop.sh').write_text(
            '#!/bin/sh\nt=$(jq -r .transcript_path)\nmv "$t" "$t.moved"\nprintf replacement > "$t"\n'
            'chmod 600 "$t"\n')
        transcript = self.tmp / 'logs/transcript.jsonl'
        transcript.parent.mkdir()
        transcript.write_text(json.dumps({'type': 'USER_INPUT', 'source': 'USER_EXPLICIT', 'step_index': 0}) + '\n')
        self.bridge('Stop', {'conversationId': 'moved', 'cwd': str(self.tmp), 'transcriptPath': str(transcript),
                             'terminationReason': 'NO_TOOL_CALL'}, root=copy)
        bridge, state = self.state()
        shadow = state / f'{self.key(bridge, "moved")}.jsonl'
        self.assertEqual(shadow.with_name(shadow.name + '.moved').stat().st_size, 0,
                         'the inode the event wrote is emptied wherever it went')
        self.assertEqual(shadow.read_text(), 'replacement', 'a file that took the name is not the event\'s to empty')

    def test_a_replacement_between_two_writes_of_one_event_fails_closed(self):
        copy = self.tmp / 'plugin'
        shutil.copytree(ROOT / 'hooks', copy / 'hooks')
        (copy / 'hooks/guard-edit-isolation.sh').write_text(
            '#!/bin/sh\nt=$(jq -r .transcript_path)\n[ -e "$t.moved" ] || { mv "$t" "$t.moved"; printf replacement > "$t"; '
            'chmod 600 "$t"; }\n')
        patch = '*** Begin Patch\n*** Update File: one.md\n*** Update File: two.md\n*** End Patch'
        result = self.bridge('PreToolUse', self.edit('apply_patch', {'Input': patch}, self.tmp, conversation='swap'),
                             root=copy)
        self.assertEqual(result['decision'], 'deny', result)
        bridge, state = self.state()
        shadow = state / f'{self.key(bridge, "swap")}.jsonl'
        self.assertEqual(shadow.read_text(), 'replacement')
        self.assertEqual(shadow.with_name(shadow.name + '.moved').stat().st_size, 0)

    def test_a_second_write_checks_the_file_before_writing_through_it(self):
        bridge, state = self.state()
        key = self.key(bridge, 'boundary')
        previous = os.environ.get('TMPDIR')
        os.environ['TMPDIR'] = self.env['TMPDIR']
        try:
            path = Path(bridge.write_shadow(key, [{'n': 1}]))
            twin = self.tmp / 'boundary-twin.jsonl'
            os.link(path, twin)
            with self.assertRaises(bridge.BridgeError):
                bridge.write_shadow(key, [{'n': 2}])
            self.assertEqual(twin.read_text(), json.dumps({'n': 1}) + '\n', 'nothing was written through the link')
            bridge.clear_shadow(key)
        finally:
            if previous is None:
                del os.environ['TMPDIR']
            else:
                os.environ['TMPDIR'] = previous

    def test_a_hardlink_added_between_two_writes_of_one_event_fails_closed(self):
        copy = self.tmp / 'plugin'
        shutil.copytree(ROOT / 'hooks', copy / 'hooks')
        twin = self.tmp / 'twin.jsonl'
        quoted = shlex.quote(str(twin))
        (copy / 'hooks/guard-edit-isolation.sh').write_text(
            f'#!/bin/sh\nt=$(jq -r .transcript_path)\n[ -e {quoted} ] || ln "$t" {quoted}\n')
        patch = '*** Begin Patch\n*** Update File: one.md\n*** Update File: two.md\n*** End Patch'
        result = self.bridge('PreToolUse', self.edit('apply_patch', {'Input': patch}, self.tmp, conversation='twin'),
                             root=copy)
        self.assertEqual(result['decision'], 'deny', result)
        self.assertEqual(twin.stat().st_size, 0, 'the second write never went through the extra name')

    def test_an_event_that_wrote_nothing_leaves_the_shadow_path_alone(self):
        bridge, state = self.state()
        shadow = state / f'{self.key(bridge, "idle")}.jsonl'
        shadow.write_text('sentinel')
        result = self.bridge('PreToolUse', self.edit('read_file', {'Path': '/etc/hostname'}, self.tmp,
                                                     conversation='idle'))
        self.assertEqual(result, {'decision': 'allow'})
        self.assertEqual(shadow.read_text(), 'sentinel')

    def with_state_env(self):
        previous = os.environ.get('TMPDIR')
        os.environ['TMPDIR'] = self.env['TMPDIR']

        def restore():
            if previous is None:
                os.environ.pop('TMPDIR', None)
            else:
                os.environ['TMPDIR'] = previous
        self.addCleanup(restore)

    def test_a_write_that_fails_midway_is_still_emptied_at_event_end(self):
        bridge, state = self.state()
        self.with_state_env()
        path = state / f'{self.key(bridge, "midway")}.jsonl'
        seen, real_write, real_events = {}, bridge.os.write, bridge.shadow_events

        def write(descriptor, data):
            written = real_write(descriptor, data)
            seen.setdefault('first', (os.fstat(descriptor).st_ino, path.stat().st_size))
            return written
        # The second record cannot be serialized after the first reached the fresh shadow.
        bridge.shadow_events = lambda steps, cwd: ([{'n': 1}, {'bad': object()}], None, None)
        bridge.os.write = write
        stdin, stdout = sys.stdin, sys.stdout
        sys.stdin = io.StringIO(json.dumps({'conversationId': 'midway', 'cwd': str(self.tmp), 'toolCall': {
            'id': 'x', 'name': 'run_command', 'args': {'CommandLine': 'ls'}}}))
        sys.stdout = io.StringIO()
        try:
            bridge.main(['agy-bridge.py', 'PreToolUse'])
            printed = sys.stdout.getvalue()
        finally:
            bridge.os.write, bridge.shadow_events = real_write, real_events
            sys.stdin, sys.stdout = stdin, stdout
        inode, size = seen['first']
        self.assertGreater(size, 0, 'the first record reached the shadow before the failure')
        self.assertEqual(json.loads(printed)['decision'], 'deny')
        self.assertEqual((path.stat().st_ino, path.stat().st_size), (inode, 0))

    def test_the_sweep_rechecks_age_under_the_lock(self):
        bridge, state = self.state()
        old = time.time() - 25 * 3600
        own, other = self.key(bridge, 'refreshed'), self.key(bridge, 'refreshed-temp')
        shadow, temp = state / f'{own}.jsonl', state / f'{other}.4245.tmp'
        for key in (own, other):
            (state / f'{key}.run.lock').write_text('')
        for path, text in ((shadow, 'refreshed'), (temp, 'refreshed temp')):
            path.write_text(text)
            os.utime(path, (old, old))
        original = bridge.under_run_lock
        refresh = {own: shadow, other: temp}

        def refreshed_meanwhile(directory, name, action):
            # That conversation's event writes its file between the scan and the lock.
            os.utime(refresh[name], None)
            return original(directory, name, action)
        bridge.under_run_lock = refreshed_meanwhile
        try:
            bridge.sweep_stale(state)
        finally:
            bridge.under_run_lock = original
        self.assertEqual(shadow.read_text(), 'refreshed')
        self.assertEqual(temp.read_text(), 'refreshed temp')

    def test_a_directory_listing_error_never_fails_the_event(self):
        bridge, state = self.state()

        class Broken:
            def __enter__(self):
                return self

            def __exit__(self, *_):
                return False

            def __iter__(self):
                raise OSError('listing failed')
        original = bridge.os.scandir
        bridge.os.scandir = lambda _: Broken()
        try:
            bridge.sweep_stale(state)
        finally:
            bridge.os.scandir = original


class ScopeExemptionTests(BridgeCase):
    """An installed Antigravity plugin copy is not a ccl-skills checkout to edit."""

    def fake_root(self, base):
        for slug in ('skill-extraction-workflow', 'sample-skill'):
            (base / 'skills' / slug).mkdir(parents=True)
            (base / 'skills' / slug / 'SKILL.md').write_text(f'---\nname: {slug}\n---\nbody\n')
        return base / 'skills/sample-skill/SKILL.md'

    def roots(self):
        installed = self.fake_root(self.tmp / 'home/.gemini/config/plugins/ccl-skills')
        checkout = self.fake_root(self.tmp / 'work/ccl-skills')
        return installed, checkout

    def test_skill_loading_scope_exempts_the_antigravity_plugin_directory(self):
        spec = importlib.util.spec_from_file_location('skill_loading', ROOT / 'hooks/skill-loading.py')
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
        installed, checkout = self.roots()
        self.assertEqual(module.shared_skill_paths([str(installed)], str(self.tmp)), [])
        self.assertEqual(module.shared_skill_paths([str(checkout)], str(self.tmp)), [str(checkout)])

    def test_extraction_stop_gate_exempts_the_antigravity_plugin_directory(self):
        installed, checkout = self.roots()

        def gate(path, session):
            transcript = self.tmp / f'{session}.jsonl'
            transcript.write_text(''.join(json.dumps(event) + '\n' for event in (
                {'type': 'user', 'message': {'role': 'user', 'content': 'edit it'}},
                {'type': 'assistant', 'message': {'role': 'assistant', 'content': [
                    {'type': 'tool_use', 'id': 'e1', 'name': 'Edit', 'input': {'file_path': str(path)}}]}},
                {'type': 'user', 'message': {'role': 'user', 'content': [
                    {'type': 'tool_result', 'tool_use_id': 'e1', 'content': 'ok'}]}})))
            out = subprocess.run(['bash', str(ROOT / 'hooks/skill-extraction-gate-stop.sh')],
                                 input=json.dumps({'session_id': session, 'transcript_path': str(transcript),
                                                   'cwd': str(self.tmp), 'hook_event_name': 'Stop'}),
                                 capture_output=True, text=True, env=self.env, timeout=30)
            return json.loads(out.stdout or '{}').get('decision')
        self.assertIsNone(gate(installed, 'installed'))
        self.assertEqual(gate(checkout, 'checkout'), 'block')


class LockTests(BridgeCase):
    def test_an_event_queued_behind_a_slow_one_still_answers_in_budget(self):
        copy = self.tmp / 'plugin'
        shutil.copytree(ROOT / 'hooks', copy / 'hooks')
        bridge = load_bridge()
        os.environ['TMPDIR'] = self.env['TMPDIR']
        try:
            _, key = bridge.conversation({'conversationId': 'slow'})
            lock = bridge.state_dir() / f'{key}.run.lock'
        finally:
            del os.environ['TMPDIR']
        holder = subprocess.Popen(['python3', '-c', 'import fcntl,os,sys,time; fd=os.open(sys.argv[1], os.O_WRONLY|os.O_CREAT, 0o600); '
                                   'fcntl.flock(fd, fcntl.LOCK_EX); print("held", flush=True); time.sleep(30)', str(lock)],
                                  stdout=subprocess.PIPE, text=True)
        try:
            self.assertEqual(holder.stdout.readline().strip(), 'held')
            started = __import__('time').monotonic()
            result = self.bridge('PostToolUse', {'conversationId': 'slow', 'cwd': str(self.tmp),
                                                 'toolCall': {'name': 'run_command', 'args': {'CommandLine': 'ls'}}}, root=copy)
            elapsed = __import__('time').monotonic() - started
        finally:
            holder.kill()
            holder.wait()
            holder.stdout.close()
        self.assertEqual(result, {})
        self.assertLess(elapsed, 15, 'PostToolUse must answer inside its 15 s host timeout')


class BoundTests(BridgeCase):
    def test_conversation_id_cannot_traverse(self):
        session, key = load_bridge().conversation({'conversationId': '../../etc/passwd'})
        self.assertNotIn('/', session)
        self.assertRegex(key, r'^[0-9a-f]{64}$')

    def test_fifo_transcript_does_not_hang(self):
        fifo = self.tmp / 'fifo.jsonl'
        os.mkfifo(fifo)
        result = self.bridge('Stop', {'conversationId': 'fifo', 'cwd': str(self.tmp),
                                      'transcriptPath': str(fifo), 'terminationReason': 'NO_TOOL_CALL'})
        self.assertIn(result['decision'], ('allow', 'continue'))

    def test_oversized_transcript_is_read_from_the_tail(self):
        bridge = load_bridge()
        big = self.tmp / 'transcript.jsonl'
        user = json.dumps({'type': 'USER_INPUT', 'source': 'USER_EXPLICIT', 'step_index': 7})
        with big.open('w') as stream:
            stream.write('x' * (bridge.MAX_TRANSCRIPT_BYTES + 10) + '\n' + user + '\n')
        steps = bridge.transcript_steps({'transcriptPath': str(big)})
        self.assertEqual([s['step_index'] for s in steps], [7])


class HotpathCacheTests(BridgeCase):
    def with_state_env(self):
        previous = os.environ.get('TMPDIR')
        os.environ['TMPDIR'] = self.env['TMPDIR']

        def restore():
            if previous is None:
                os.environ.pop('TMPDIR', None)
            else:
                os.environ['TMPDIR'] = previous
        self.addCleanup(restore)

    def run_inprocess(self, bridge, event, payload):
        stdin, stdout = sys.stdin, sys.stdout
        sys.stdin = io.StringIO(json.dumps(payload))
        sys.stdout = io.StringIO()
        try:
            rc = bridge.main(['agy-bridge.py', event])
            self.assertEqual(rc, 0)
            return json.loads(sys.stdout.getvalue().strip())
        finally:
            sys.stdin, sys.stdout = stdin, stdout

    def test_incremental_transcript_cache_skips_prior_generic_steps_without_persisting_content(self):
        self.with_state_env()
        bridge = load_bridge()
        state = bridge.state_dir()
        _, conv_key = bridge.conversation({'conversationId': 'inc-cache'})

        grill_path = ROOT / 'skills/grill-me/SKILL.md'
        grill_lines = grill_path.read_text().split('\n')[:-1]
        half = len(grill_lines) // 2
        wt_path = ROOT / 'skills/worktree-isolation/SKILL.md'
        wt_lines = wt_path.read_text().split('\n')[:-1]

        secrets = (
            'SECRET_USER_PROMPT_TOKEN',
            'SECRET_COMMAND_TOKEN',
            'SECRET_SUBAGENT_TOKEN',
            'SECRET_FILE_PATH_TOKEN',
            'SECRET_TOOL_OUTPUT_TOKEN',
            'SECRET_ASSISTANT_PROSE_TOKEN',
        )
        steps = [
            {'type': 'USER_INPUT', 'source': 'USER_EXPLICIT', 'step_index': 0,
             'content': 'SECRET_USER_PROMPT_TOKEN'},
            {'type': 'PLANNER_RESPONSE', 'step_index': 1, 'tool_calls': [
                {'id': 'g1', 'name': 'read_file',
                 'args': {'Path': str(grill_path), 'StartLine': 1, 'EndLine': half}}]},
            {'type': 'GENERIC', 'status': 'DONE', 'step_index': 2,
             'content': f'Showing lines 1-{half} of {len(grill_lines)}\n'
                        + '\n'.join(f'{n}: {grill_lines[n - 1]}' for n in range(1, half + 1))},
        ]
        for idx in range(12):
            step_no = 3 + idx * 2
            steps.append({
                'type': 'PLANNER_RESPONSE', 'step_index': step_no,
                'tool_calls': [
                    {'id': f'cmd-{idx}', 'name': 'run_command',
                     'args': {'CommandLine': f'echo SECRET_COMMAND_TOKEN_{idx}'}},
                    {'id': f'sub-{idx}', 'name': 'invoke_subagent',
                     'args': {'TypeName': 'research', 'Role': 'Reader',
                              'Prompt': f'SECRET_SUBAGENT_TOKEN_{idx}'}},
                    {'id': f'ed-{idx}', 'name': 'write_file',
                     'args': {'Path': f'SECRET_FILE_PATH_TOKEN_{idx}.txt', 'Content': 'x'}},
                ],
            })
            for sub_pos in range(3):
                steps.append({
                    'type': 'GENERIC', 'status': 'DONE',
                    'content': f'SECRET_TOOL_OUTPUT_TOKEN_{idx}_{sub_pos}: ' + ('payload-' * 220),
                })
        # Step with omitted step_index (tests fallback positional numbering), second half of grill-me,
        # assistant prose, and a trailing OPEN PLANNER_RESPONSE awaiting its GENERIC result.
        steps.extend([
            {'type': 'PLANNER_RESPONSE', 'tool_calls': [
                {'name': 'read_file',
                 'args': {'Path': str(grill_path), 'StartLine': half + 1, 'EndLine': len(grill_lines)}}]},
            {'type': 'GENERIC', 'status': 'DONE',
             'content': f'Showing lines {half + 1}-{len(grill_lines)} of {len(grill_lines)}\n'
                        + '\n'.join(f'{n}: {grill_lines[n - 1]}'
                                    for n in range(half + 1, len(grill_lines) + 1))},
            {'type': 'PLANNER_RESPONSE',
             'content': 'SECRET_ASSISTANT_PROSE_TOKEN\nproposed-next: none — status only'},
            {'type': 'PLANNER_RESPONSE', 'step_index': 90, 'tool_calls': [
                {'id': 'wt-open', 'name': 'read_file', 'args': {'Path': str(wt_path)}}]},
        ])

        transcript = self.tmp / 'logs/transcript_full.jsonl'
        transcript.parent.mkdir(parents=True)
        transcript.write_text(''.join(json.dumps(s) + '\n' for s in steps))
        tx_arg = str(transcript.with_name('transcript.jsonl'))

        cmd_payload = {
            'conversationId': 'inc-cache', 'hookEventName': 'PreToolUse',
            'cwd': str(self.tmp), 'workspacePaths': [str(self.tmp)], 'transcriptPath': tx_arg,
            'toolCall': {'id': 'live-1', 'name': 'run_command', 'args': {'CommandLine': 'echo ok'}},
        }
        first_res = self.run_inprocess(bridge, 'PreToolUse', cmd_payload)
        self.assertEqual(first_res['decision'], 'allow')

        cache_path = state / f'{conv_key}.cache.json'
        self.assertTrue(cache_path.is_file(), 'incremental transcript cache file was not created')
        cache_stat = os.lstat(cache_path)
        self.assertEqual(cache_stat.st_mode & 0o777, 0o600)
        self.assertEqual(cache_stat.st_nlink, 1)
        cache_raw = cache_path.read_text(encoding='utf-8')
        for secret in (*secrets, str(self.tmp)):
            self.assertNotIn(secret, cache_raw, f'cache leaked sensitive transcript text: {secret}')
        self.assertEqual(len(list(state.glob('*.jsonl'))), 1)
        self.assertEqual(next(state.glob('*.jsonl')).stat().st_size, 0)

        # Append the GENERIC result closing step 90 (`worktree-isolation` SKILL.md) + one new step.
        appended = [
            {'type': 'GENERIC', 'status': 'DONE', 'step_index': 91,
             'content': f'Showing lines 1-{len(wt_lines)} of {len(wt_lines)}\n'
                        + '\n'.join(f'{n}: {line}' for n, line in enumerate(wt_lines, start=1))},
            {'type': 'PLANNER_RESPONSE',
             'content': 'Final answer ready.\nproposed-next: none — status only'},
        ]
        with transcript.open('a', encoding='utf-8') as fh:
            for item in appended:
                fh.write(json.dumps(item) + '\n')

        parsed_lines = []
        real_loads = bridge.json.loads

        def spy_loads(raw_text, *args, **kwargs):
            parsed_lines.append(raw_text if isinstance(raw_text, str) else raw_text.decode('utf-8', 'replace'))
            return real_loads(raw_text, *args, **kwargs)

        captured_events = {}
        real_write_shadow = bridge.write_shadow

        def spy_write_shadow(key, events, *args, **kwargs):
            captured_events['cached'] = (list(events), kwargs)
            return real_write_shadow(key, events, *args, **kwargs)

        bridge.json.loads = spy_loads
        bridge.write_shadow = spy_write_shadow
        try:
            second_res = self.run_inprocess(bridge, 'Stop', {
                'conversationId': 'inc-cache', 'cwd': str(self.tmp),
                'transcriptPath': tx_arg, 'terminationReason': 'NO_TOOL_CALL',
            })
        finally:
            bridge.json.loads = real_loads
            bridge.write_shadow = real_write_shadow

        self.assertEqual(second_res['decision'], 'allow', second_res)
        self.assertFalse(
            any('SECRET_TOOL_OUTPUT_TOKEN_' in item for item in parsed_lines),
            'incremental cache hit re-parsed historical GENERIC tool-result lines',
        )
        uncached_events, uncached_turn, uncached_prose = bridge.shadow_events(
            bridge.transcript_steps({'transcriptPath': tx_arg}), str(self.tmp),
        )
        self.assertEqual(captured_events['cached'][0], uncached_events)
        self.assertEqual(uncached_turn, 'turn-0')
        self.assertEqual(uncached_prose, 'Final answer ready.\nproposed-next: none — status only')
        loaded_skills = [
            item['input']['skill']
            for ev in captured_events['cached'][0]
            for item in ev['message']['content']
            if item.get('name') == 'Skill'
        ]
        self.assertEqual(loaded_skills, ['ccl-skills:grill-me', 'ccl-skills:worktree-isolation'])

        # In-place overwrite on the same inode (same-layout prefix edit, same-layout middle edit
        # outside 8 KiB head/tail boundaries, longer rewrite, and shorter rewrite) must all invalidate cleanly.
        raw_before_mid = transcript.read_bytes()
        mid_anchor = b'SECRET_TOOL_OUTPUT_TOKEN_6_0'
        anchor_pos = raw_before_mid.index(mid_anchor)
        done_pos = raw_before_mid.rfind(b'"status": "DONE"', 0, anchor_pos)
        self.assertGreater(done_pos, 16384, 'middle edit must sit well past the first 8 KiB')
        self.assertLess(done_pos, len(raw_before_mid) - 16384, 'middle edit must sit well before the last 8 KiB')
        mid_edited = (
            raw_before_mid[:done_pos]
            + b'"status": "FAIL"'
            + raw_before_mid[done_pos + len(b'"status": "DONE"'):]
        )
        self.assertEqual(len(mid_edited), len(raw_before_mid))
        transcript.write_bytes(mid_edited)
        cached_mid_events, _, _ = bridge.cached_transcript_events(
            {'transcriptPath': tx_arg}, conv_key, str(self.tmp),
        )
        uncached_mid_events, _, _ = bridge.shadow_events(
            bridge.transcript_steps({'transcriptPath': tx_arg}), str(self.tmp),
        )
        self.assertEqual(
            cached_mid_events,
            uncached_mid_events,
            'whole-span block SHA-256 must detect same-length in-place edit in the middle of the transcript',
        )

        same_layout_bytes = transcript.read_bytes().replace(b'"step_index": 0', b'"step_index": 9', 1)
        self.assertEqual(len(same_layout_bytes), transcript.stat().st_size)
        transcript.write_bytes(same_layout_bytes)
        same_layout_res = self.run_inprocess(bridge, 'Stop', {
            'conversationId': 'inc-cache', 'cwd': str(self.tmp),
            'transcriptPath': tx_arg, 'terminationReason': 'NO_TOOL_CALL',
        })
        self.assertEqual(same_layout_res['decision'], 'allow')
        _, cached_turn_after_same_len, _ = bridge.cached_transcript_events(
            {'transcriptPath': tx_arg}, conv_key, str(self.tmp),
        )
        self.assertEqual(cached_turn_after_same_len, 'turn-9', 'boundary digest must catch same-length in-place edit')

        orig_len = transcript.stat().st_size
        rewritten_longer = [
            {'type': 'USER_INPUT', 'source': 'USER_EXPLICIT', 'step_index': 3, 'content': 'rewritten-long'},
            {'type': 'PLANNER_RESPONSE', 'step_index': 4,
             'content': 'Longer rewritten prose. ' + ('pad-' * (orig_len // 4 + 64))
                        + '\nproposed-next: none — status only'},
        ]
        transcript.write_text(''.join(json.dumps(s) + '\n' for s in rewritten_longer), encoding='utf-8')
        self.assertGreaterEqual(transcript.stat().st_size, orig_len)
        captured_after_long = {}

        def capture_long(key, events, *args, **kwargs):
            captured_after_long['events'] = list(events)
            return real_write_shadow(key, events, *args, **kwargs)

        bridge.write_shadow = capture_long
        try:
            self.run_inprocess(bridge, 'Stop', {
                'conversationId': 'inc-cache', 'cwd': str(self.tmp),
                'transcriptPath': tx_arg, 'terminationReason': 'NO_TOOL_CALL',
            })
        finally:
            bridge.write_shadow = real_write_shadow
        fresh_long, _, _ = bridge.shadow_events(
            bridge.transcript_steps({'transcriptPath': tx_arg}), str(self.tmp),
        )
        self.assertEqual(captured_after_long['events'], fresh_long)

        rewritten = [
            {'type': 'USER_INPUT', 'source': 'USER_EXPLICIT', 'step_index': 5, 'content': 'rewritten'},
            {'type': 'PLANNER_RESPONSE', 'step_index': 6,
             'content': 'Rewritten prose.\nproposed-next: none — status only'},
        ]
        transcript.write_text(''.join(json.dumps(s) + '\n' for s in rewritten), encoding='utf-8')
        captured_after_rewrite = {}

        def capture_rewrite(key, events, *args, **kwargs):
            captured_after_rewrite['events'] = list(events)
            return real_write_shadow(key, events, *args, **kwargs)

        bridge.write_shadow = capture_rewrite
        try:
            self.run_inprocess(bridge, 'Stop', {
                'conversationId': 'inc-cache', 'cwd': str(self.tmp),
                'transcriptPath': tx_arg, 'terminationReason': 'NO_TOOL_CALL',
            })
        finally:
            bridge.write_shadow = real_write_shadow
        fresh_rewritten, _, _ = bridge.shadow_events(
            bridge.transcript_steps({'transcriptPath': tx_arg}), str(self.tmp),
        )
        self.assertEqual(captured_after_rewrite['events'], fresh_rewritten)

        # Planted symlink or hardlink at {key}.cache.json is never followed or written through.
        for kind in ('symlink', 'hardlink'):
            with self.subTest(cache_link=kind):
                cache_path.unlink(missing_ok=True)
                outside = self.tmp / f'outside-{kind}.json'
                outside.write_text('{"keep": true}\n', encoding='utf-8')
                if kind == 'symlink':
                    cache_path.symlink_to(outside)
                else:
                    os.link(outside, cache_path)
                res = self.run_inprocess(bridge, 'PreToolUse', cmd_payload)
                self.assertEqual(res['decision'], 'allow')
                self.assertEqual(outside.read_text(encoding='utf-8'), '{"keep": true}\n')
                cache_path.unlink(missing_ok=True)

    def test_stale_transcript_cache_is_swept_under_run_lock_and_absent_transcript_writes_no_cache(self):
        self.with_state_env()
        bridge = load_bridge()
        state = bridge.state_dir()

        # Conversation without transcriptPath creates no .cache.json file.
        _, notx_key = bridge.conversation({'conversationId': 'no-tx-conv'})
        res = self.run_inprocess(
            bridge, 'PreToolUse',
            self.edit('run_command', {'CommandLine': 'echo hi'}, self.tmp, conversation='no-tx-conv'),
        )
        self.assertEqual(res['decision'], 'allow')
        self.assertFalse((state / f'{notx_key}.cache.json').exists())

        old = time.time() - 25 * 3600
        keys = {name: bridge.conversation({'conversationId': f'cache-{name}'})[1]
                for name in ('stale', 'fresh', 'held', 'refreshed')}
        for name in ('stale', 'fresh', 'held', 'refreshed'):
            (state / f'{keys[name]}.run.lock').write_text('')
            cpath = state / f'{keys[name]}.cache.json'
            cpath.write_text('{"version":1}')
            if name != 'fresh':
                os.utime(cpath, (old, old))

        holder = subprocess.Popen(
            ['python3', '-c',
             'import fcntl,os,sys,time; fd=os.open(sys.argv[1], os.O_WRONLY|os.O_CREAT, 0o600); '
             'fcntl.flock(fd, fcntl.LOCK_EX); print("held", flush=True); time.sleep(30)',
             str(state / f'{keys["held"]}.run.lock')],
            stdout=subprocess.PIPE, text=True,
        )
        original_under_lock = bridge.under_run_lock

        def refresh_on_lock(directory, k, action):
            if k == keys['refreshed']:
                os.utime(state / f'{k}.cache.json', None)
            return original_under_lock(directory, k, action)

        bridge.under_run_lock = refresh_on_lock
        try:
            self.assertEqual(holder.stdout.readline().strip(), 'held')
            bridge.sweep_stale(state)
        finally:
            bridge.under_run_lock = original_under_lock
            holder.kill()
            holder.wait()
            holder.stdout.close()

        self.assertFalse((state / f'{keys["stale"]}.cache.json').exists(), 'stale cache must be swept')
        self.assertTrue((state / f'{keys["fresh"]}.cache.json').exists(), 'fresh cache must remain')
        self.assertTrue((state / f'{keys["held"]}.cache.json').exists(), 'locked cache must remain')
        self.assertTrue((state / f'{keys["refreshed"]}.cache.json').exists(), 'age must be rechecked under lock')

    def test_multiblock_span_digests_keep_prefix_and_reject_string_step_index(self):
        self.with_state_env()
        bridge = load_bridge()
        state = bridge.state_dir()

        # 1. Non-int step_index values must never be frozen into {key}.cache.json or accepted by emit_cached_records.
        with self.assertRaises(ValueError):
            bridge.emit_cached_records(io.BytesIO(b''), [['U', 'not-an-int']], str(self.tmp))
        with self.assertRaises(ValueError):
            bridge.emit_cached_records(io.BytesIO(b'{}'), [['C', 'not-an-int', 0, 2, 1, '0', []]], str(self.tmp))

        _, str_key = bridge.conversation({'conversationId': 'str-step-index'})
        str_tx = self.tmp / 'str-logs/transcript_full.jsonl'
        str_tx.parent.mkdir(parents=True)
        str_tx_arg = str(str_tx.with_name('transcript.jsonl'))
        str_steps = [
            {'type': 'USER_INPUT', 'source': 'USER_EXPLICIT', 'step_index': 0, 'content': 'u0'},
            {'type': 'USER_INPUT', 'source': 'USER_EXPLICIT',
             'step_index': 'SECRET_USER_STEP_INDEX_TOKEN', 'content': 'u1'},
            {'type': 'PLANNER_RESPONSE', 'step_index': 'SECRET_CALL_STEP_INDEX_TOKEN',
             'tool_calls': [{'name': 'run_command', 'args': {'CommandLine': 'echo 1'}}]},
            {'type': 'GENERIC', 'status': 'DONE', 'step_index': 3, 'content': 'ok'},
            {'type': 'PLANNER_RESPONSE', 'step_index': 4,
             'content': 'Done.\nproposed-next: none — status only'},
        ]
        str_tx.write_text(''.join(json.dumps(s) + '\n' for s in str_steps), encoding='utf-8')
        events_1, turn_1, prose_1 = bridge.cached_transcript_events({'transcriptPath': str_tx_arg}, str_key, str(self.tmp))
        uncached_1 = bridge.shadow_events(bridge.transcript_steps({'transcriptPath': str_tx_arg}), str(self.tmp))
        self.assertEqual((events_1, turn_1, prose_1), uncached_1)
        str_cache_raw = (state / f'{str_key}.cache.json').read_text(encoding='utf-8')
        self.assertNotIn('SECRET_USER_STEP_INDEX_TOKEN', str_cache_raw)
        self.assertNotIn('SECRET_CALL_STEP_INDEX_TOKEN', str_cache_raw)
        with str_tx.open('a', encoding='utf-8') as fh:
            fh.write(json.dumps({'type': 'PLANNER_RESPONSE', 'step_index': 5,
                                 'content': 'Appended.\nproposed-next: none — status only'}) + '\n')
        events_2, turn_2, prose_2 = bridge.cached_transcript_events({'transcriptPath': str_tx_arg}, str_key, str(self.tmp))
        uncached_2 = bridge.shadow_events(bridge.transcript_steps({'transcriptPath': str_tx_arg}), str(self.tmp))
        self.assertEqual((events_2, turn_2, prose_2), uncached_2)

        # 2. Multi-block (> 2 MiB) transcript exercises prior_blocks reuse on append and invalidates edits in any block.
        _, mb_key = bridge.conversation({'conversationId': 'multi-block-cache'})
        mb_tx = self.tmp / 'mb-logs/transcript_full.jsonl'
        mb_tx.parent.mkdir(parents=True)
        mb_tx_arg = str(mb_tx.with_name('transcript.jsonl'))
        mb_steps = [{'type': 'USER_INPUT', 'source': 'USER_EXPLICIT', 'step_index': 0, 'content': 'start'}]
        for idx in range(18):
            mb_steps.append({
                'type': 'PLANNER_RESPONSE', 'step_index': 1 + idx * 2,
                'tool_calls': [{'id': f'mb-{idx}', 'name': 'run_command', 'args': {'CommandLine': f'echo {idx}'}}],
            })
            mb_steps.append({
                'type': 'GENERIC', 'status': 'DONE', 'step_index': 2 + idx * 2,
                'content': f'MB_ANCHOR_{idx}:' + ('p' * (135 * 1024)),
            })
        mb_steps.append({'type': 'PLANNER_RESPONSE', 'step_index': 99,
                         'content': 'Ready.\nproposed-next: none — status only'})
        mb_tx.write_text(''.join(json.dumps(s) + '\n' for s in mb_steps), encoding='utf-8')
        self.assertGreater(mb_tx.stat().st_size, 2 * bridge.CACHE_BLOCK_BYTES + 100_000)
        self.assertLess(mb_tx.stat().st_size, 3 * bridge.CACHE_BLOCK_BYTES - 100_000)

        init_events = bridge.cached_transcript_events({'transcriptPath': mb_tx_arg}, mb_key, str(self.tmp))
        self.assertEqual(init_events, bridge.shadow_events(bridge.transcript_steps({'transcriptPath': mb_tx_arg}), str(self.tmp)))
        mb_cache = json.loads((state / f'{mb_key}.cache.json').read_text(encoding='utf-8'))
        self.assertEqual(len(mb_cache['block_sha256']), 3)

        # Append a step and verify write-side span_block_digests reuses the 2 full 1 MiB prefix blocks
        # without re-seeking into bytes 0 .. 2 MiB during the cache update.
        with mb_tx.open('a', encoding='utf-8') as fh:
            fh.write(json.dumps({'type': 'PLANNER_RESPONSE', 'step_index': 100,
                                 'content': 'After append.\nproposed-next: none — status only'}) + '\n')
        real_span_digests = bridge.span_block_digests
        write_seek_offsets = []

        def spy_span_digests(stream, start, end, prior_blocks=None, prior_end=None):
            if prior_blocks is not None:
                real_seek = stream.seek

                def rec_seek(off, *a):
                    write_seek_offsets.append(off)
                    return real_seek(off, *a)

                stream.seek = rec_seek
                try:
                    return real_span_digests(stream, start, end, prior_blocks, prior_end)
                finally:
                    stream.seek = real_seek
            return real_span_digests(stream, start, end, prior_blocks, prior_end)

        bridge.span_block_digests = spy_span_digests
        try:
            app_events = bridge.cached_transcript_events({'transcriptPath': mb_tx_arg}, mb_key, str(self.tmp))
        finally:
            bridge.span_block_digests = real_span_digests
        self.assertEqual(app_events, bridge.shadow_events(bridge.transcript_steps({'transcriptPath': mb_tx_arg}), str(self.tmp)))
        self.assertTrue(write_seek_offsets, 'expected write-side span_block_digests call on append')
        self.assertGreaterEqual(
            min(write_seek_offsets),
            2 * bridge.CACHE_BLOCK_BYTES,
            f'write-side span_block_digests re-read full prefix blocks instead of reusing prior_blocks: {write_seek_offsets}',
        )
        # Second call after append must also hit the updated 3-block cache cleanly.
        hit_after_append = bridge.cached_transcript_events({'transcriptPath': mb_tx_arg}, mb_key, str(self.tmp))
        self.assertEqual(hit_after_append, app_events)

        # Same-length edit inside reused block 0 (< 1 MiB) and block 1 (1..2 MiB) must both invalidate.
        for anchor, lo, hi in (
            (b'MB_ANCHOR_2:', 0, bridge.CACHE_BLOCK_BYTES),
            (b'MB_ANCHOR_10:', bridge.CACHE_BLOCK_BYTES, 2 * bridge.CACHE_BLOCK_BYTES),
        ):
            raw = mb_tx.read_bytes()
            anchor_pos = raw.index(anchor)
            done_pos = raw.rfind(b'"status": "DONE"', 0, anchor_pos)
            self.assertGreaterEqual(done_pos, lo)
            self.assertLess(done_pos, hi)
            edited = raw[:done_pos] + b'"status": "FAIL"' + raw[done_pos + len(b'"status": "DONE"'):]
            self.assertEqual(len(edited), len(raw))
            mb_tx.write_bytes(edited)
            got = bridge.cached_transcript_events({'transcriptPath': mb_tx_arg}, mb_key, str(self.tmp))
            want = bridge.shadow_events(bridge.transcript_steps({'transcriptPath': mb_tx_arg}), str(self.tmp))
            self.assertEqual(got, want)

    def test_stat_keyed_bundled_skill_entry_avoids_reread_until_file_changes(self):
        plugin = self.tmp / 'plugin'
        (plugin / 'hooks').mkdir(parents=True)
        shutil.copyfile(BRIDGE, plugin / 'hooks/agy-bridge.py')
        skill = plugin / 'skills/demo-skill/SKILL.md'
        skill.parent.mkdir(parents=True)
        skill.write_text('---\nname: demo-skill\ndescription: d\n---\nLine one\nLine two\n', encoding='utf-8')

        spec = importlib.util.spec_from_file_location('agy_bridge_skill_cache', plugin / 'hooks/agy-bridge.py')
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)

        reads = []
        real_read_regular = module.read_regular

        def spy_read_regular(path):
            reads.append(str(path))
            return real_read_regular(path)

        module.read_regular = spy_read_regular
        try:
            first = module.bundled_skill(skill)
            for _ in range(4):
                again = module.bundled_skill(skill)
                self.assertEqual(again, first)
            self.assertEqual(len(reads), 1, f'expected 1 disk read for 5 unchanged calls, got {len(reads)}')

            # Modified external copy must still be rejected byte-for-byte.
            ext_copy = self.tmp / 'external/skills/demo-skill/SKILL.md'
            ext_copy.parent.mkdir(parents=True)
            ext_copy.write_text(skill.read_text(encoding='utf-8') + 'tampered\n', encoding='utf-8')
            self.assertIsNone(module.bundled_skill(ext_copy))

            # Updating the canonical SKILL.md on disk must invalidate the cache immediately.
            skill.write_text(
                '---\nname: demo-skill\ndescription: d\n---\nLine one\nLine two\nLine three\n',
                encoding='utf-8',
            )
            updated = module.bundled_skill(skill)
            self.assertIsNotNone(updated)
            self.assertEqual(updated[1][-1], 'Line three')
        finally:
            module.read_regular = real_read_regular

    def test_write_shadow_batches_chunks_and_rewrites_only_tail_for_multi_target_patches(self):
        self.with_state_env()
        bridge = load_bridge()
        key = bridge.conversation({'conversationId': 'batched-shadow'})[1]

        writes = []
        real_write = bridge.os.write

        def spy_write(descriptor, data):
            if descriptor not in bridge.OPEN_SHADOWS.values():
                return real_write(descriptor, data)
            pos = os.lseek(descriptor, 0, os.SEEK_CUR)
            n = real_write(descriptor, data)
            writes.append((pos, n))
            return n

        bridge.os.write = spy_write
        try:
            events_small = [{'i': i, 'pad': 'a' * 80} for i in range(400)]
            target = Path(bridge.write_shadow(key, events_small))
            self.assertEqual(len(writes), 1, f'expected single buffered write under 64 KiB, got {len(writes)}')
            self.assertEqual(len(target.read_text(encoding='utf-8').splitlines()), 400)
            bridge.clear_shadow(key)

            writes.clear()
            events_large = [{'i': i, 'pad': 'b' * 90} for i in range(2000)]
            bridge.write_shadow(key, events_large)
            self.assertLessEqual(len(writes), 6, f'expected chunked writes, got {len(writes)}')
            bridge.clear_shadow(key)

            # Buffered T4g invariant: if a later record fails serialization before 64 KiB fills,
            # earlier buffered records are still flushed to the shadow fd before re-raising.
            err_key = bridge.conversation({'conversationId': 'partial-flush-err'})[1]
            err_target = bridge.state_dir() / f'{err_key}.jsonl'
            with self.assertRaises(TypeError):
                bridge.write_shadow(err_key, [{'ok': 'x' * 64}, {'unserializable': {1, 2}}])
            self.assertGreater(err_target.stat().st_size, 0, 'buffered records must flush before re-raising')
            bridge.clear_shadow(err_key)
            self.assertEqual(err_target.stat().st_size, 0)

            # Renaming the shadow path aside and planting a new file at the same path keeps
            # held.st_nlink == 1, so (held.st_dev, held.st_ino) != (named.st_dev, named.st_ino) must catch it.
            swap_key = bridge.conversation({'conversationId': 'swap-during-reuse'})[1]
            swap_target = Path(bridge.write_shadow(swap_key, [{'ok': 1}], {'tail': 1}))
            moved_shadow = self.tmp / 'moved-shadow.jsonl'
            try:
                swap_target.rename(moved_shadow)
                swap_target.write_text('replaced\n', encoding='utf-8')
                with self.assertRaisesRegex(bridge.BridgeError, 'replaced during the event'):
                    bridge.write_shadow(swap_key, [{'ok': 1}], {'tail': 2}, reuse_prefix=True)
            finally:
                bridge.clear_shadow(swap_key)
                moved_shadow.unlink(missing_ok=True)

            # Multi-target apply_patch: after context() writes the base events once,
            # each target iteration must write only the single pending tool_use tail.
            writes.clear()
            transcript = self.tmp / 'patch-logs/transcript_full.jsonl'
            transcript.parent.mkdir(parents=True)
            tx_steps = [{'type': 'USER_INPUT', 'source': 'USER_EXPLICIT', 'step_index': 0}]
            for idx in range(1, 250):
                tx_steps.append({'type': 'PLANNER_RESPONSE', 'step_index': idx * 2 - 1,
                                 'tool_calls': [{'id': f'c{idx}', 'name': 'run_command',
                                                 'args': {'CommandLine': f'echo {idx}'}}]})
                tx_steps.append({'type': 'GENERIC', 'status': 'DONE', 'step_index': idx * 2, 'content': 'ok'})
            transcript.write_text(''.join(json.dumps(s) + '\n' for s in tx_steps), encoding='utf-8')

            work = self.tmp / 'patch-work'
            work.mkdir()
            patch_lines = ['*** Begin Patch'] + [f'*** Update File: f{i}.txt' for i in range(6)] + ['*** End Patch']
            res = self.run_inprocess(bridge, 'PreToolUse', {
                'conversationId': 'multi-target', 'hookEventName': 'PreToolUse',
                'cwd': str(work), 'workspacePaths': [str(work)],
                'transcriptPath': str(transcript.with_name('transcript.jsonl')),
                'toolCall': {'id': 'p1', 'name': 'apply_patch', 'args': {'Input': '\n'.join(patch_lines)}},
            })
            self.assertEqual(res['decision'], 'allow', res)
            base_writes = [size for offset, size in writes if offset == 0]
            tail_writes = [size for offset, size in writes if offset > 0 and size < 1024]
            self.assertEqual(len(base_writes), 1, f'expected base prefix written once, got writes={writes}')
            self.assertEqual(len(tail_writes), 6, f'expected 6 tail-only pending writes, got writes={writes}')
        finally:
            bridge.os.write = real_write

    def test_stop_skips_inert_headless_background_hook_unless_claude_sdk_entrypoint(self):
        bridge = load_bridge()
        self.assertIn('headless-background-stop.sh', bridge.DISPATCH['Stop'])
        invoked = []
        real_run_hook = bridge.run_hook

        def spy_run_hook(script, data, cwd, deadline, cap=None):
            invoked.append(script)
            return 'ok', {}

        stop_payload = {
            'conversationId': 'stop-headless-skip',
            'hookEventName': 'Stop',
            'cwd': str(self.tmp),
            'workspacePaths': [str(self.tmp)],
            'terminationReason': 'NO_TOOL_CALL',
        }
        bridge.run_hook = spy_run_hook
        old_entry = os.environ.pop('CLAUDE_CODE_ENTRYPOINT', None)
        try:
            invoked.clear()
            res = bridge.handle('Stop', stop_payload)
            self.assertEqual(res, {'decision': 'allow'})
            self.assertNotIn('headless-background-stop.sh', invoked)
            self.assertEqual(invoked, ['owner-dispatch-stop.sh', 'skill-extraction-gate-stop.sh',
                                       'proposed-next-stop.sh'])

            invoked.clear()
            os.environ['CLAUDE_CODE_ENTRYPOINT'] = 'sdk-ts'
            res_sdk = bridge.handle('Stop', stop_payload)
            self.assertEqual(res_sdk, {'decision': 'allow'})
            self.assertIn('headless-background-stop.sh', invoked)
        finally:
            bridge.run_hook = real_run_hook
            if old_entry is None:
                os.environ.pop('CLAUDE_CODE_ENTRYPOINT', None)
            else:
                os.environ['CLAUDE_CODE_ENTRYPOINT'] = old_entry


if __name__ == '__main__':
    unittest.main()
