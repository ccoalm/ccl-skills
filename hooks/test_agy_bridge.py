#!/usr/bin/env python3
"""Antigravity bridge: protocol shapes, guard parity and evidence bounds.

Every case runs against synthetic repositories in a private TMPDIR; nothing
touches a real Antigravity installation.
"""
import importlib.util
import json
import os
from pathlib import Path
import shutil
import subprocess
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
            f'print(s.st_ino, oct(stat.S_IMODE(s.st_mode))[2:])" "$t" >> {capture}.ids\ncp "$t" {capture}\n')
        stop = {'conversationId': 'priv', 'cwd': str(self.tmp), 'transcriptPath': str(transcript),
                'terminationReason': 'NO_TOOL_CALL'}
        self.bridge('Stop', stop, root=copy)
        self.assertNotIn('secret-user-text', capture.read_text())
        self.assertIn('turn-0', capture.read_text())
        edit = self.edit('write_file', {'Path': str(self.tmp / 'notes.md')}, self.tmp, conversation='priv')
        self.bridge('PreToolUse', {**edit, 'transcriptPath': str(transcript)}, root=copy)
        self.bridge('PreToolUse', {**self.edit('run_command', {'CommandLine': 'ls'}, self.tmp, conversation='priv'),
                                   'transcriptPath': str(transcript)}, root=copy)
        self.bridge('Stop', stop, root=copy)
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
    """
    LIMIT = 46080
    SKILL = ROOT / 'skills/skill-extraction-workflow/SKILL.md'

    def setUp(self):
        super().setUp()
        self.lines = self.SKILL.read_text().split('\n')[:-1]
        self.stream = '\n'.join(f'{n}: {line}' for n, line in enumerate(self.lines, start=1)).encode()
        self.assertGreater(len(self.stream), 2 * self.LIMIT, 'fixture skill must need three chunks')

    def cut(self, start):
        end = min(start + self.LIMIT, len(self.stream))
        while end < len(self.stream) and self.stream[end] & 0xC0 == 0x80:
            end -= 1
        return end

    def chunks(self):
        spans, start = [], 0
        while start < len(self.stream):
            end = self.cut(start)
            spans.append((start, end))
            start = end
        return spans

    def line_start(self, offset):
        return self.stream.rfind(b'\n', 0, offset) + 1

    def result(self, start, end, body=None, size=None, total=None, shown_start=None):
        size = len(self.stream) if size is None else size
        header = (f'Partial read (lines 1-{len(self.lines)} of {total or len(self.lines)}). Showing bytes '
                  f'{start if shown_start is None else shown_start}-{end} of {size} in this line range')
        header += (f', truncated at the {self.LIMIT}-byte limit. To read the rest of this line range, call this '
                   f'tool again with the same StartLine and EndLine and ByteOffset={end}.' if end < len(self.stream)
                   else '.')
        text = self.stream[start:end].decode() if body is None else body
        return f'Created At: t\nCompleted At: t\n{header}\n{text}'

    def loaded(self, results, parallel=False):
        steps = [{'type': 'USER_INPUT', 'source': 'USER_EXPLICIT', 'step_index': 0, 'content': 'x'}]
        calls = [{'name': 'read_file', 'args': {'Path': str(self.SKILL), 'ByteOffset': offset}} for offset, _ in results]
        done = [{'type': 'GENERIC', 'status': 'DONE', 'content': content} for _, content in results]
        if parallel:
            steps += [{'type': 'PLANNER_RESPONSE', 'tool_calls': calls}] + done
        else:
            for call, outcome in zip(calls, done):
                steps += [{'type': 'PLANNER_RESPONSE', 'tool_calls': [call]}, outcome]
        steps = [dict(step, step_index=index) for index, step in enumerate(steps)]
        events, _, _ = load_bridge().shadow_events(steps, str(self.tmp))
        return [item['input']['skill'] for event in events
                for item in event['message']['content'] if item.get('name') == 'Skill']

    def test_parallel_byte_chunks_covering_the_skill_count_as_a_load(self):
        spans = self.chunks()
        self.assertEqual(len(spans), 3)
        self.assertTrue(any(self.stream[end - 1:end] != b'\n' and self.stream[end:end + 1] != b'\n'
                            for _, end in spans[:-1]), 'fixture must cut inside a line')
        results = [(start, self.result(start, end)) for start, end in spans]
        self.assertEqual(self.loaded(results, parallel=True), ['ccl-skills:skill-extraction-workflow'])
        self.assertEqual(self.loaded(results[::-1]), ['ccl-skills:skill-extraction-workflow'])

    def test_an_offset_inside_a_character_counts_where_the_host_really_started(self):
        (s1, e1), _, (_, e3) = self.chunks()
        inside = next(n for n in range(e1, e3) if self.stream[n] & 0xC0 == 0x80)
        boundary = inside
        while self.stream[boundary] & 0xC0 == 0x80:
            boundary -= 1
        first = (0, self.result(0, boundary))
        rest = self.cut(boundary)
        tail = [(rest, self.result(rest, e3))] if rest < e3 else []
        # The host answers ByteOffset=inside from the character's first byte but echoes `inside`.
        backed = (inside, self.result(boundary, rest, shown_start=inside))
        self.assertEqual(self.loaded([first, backed] + tail), ['ccl-skills:skill-extraction-workflow'])
        short = (inside, self.result(boundary + 1, rest, shown_start=inside,
                                     body=self.stream[boundary + 1:rest].decode('utf-8', 'replace')))
        self.assertEqual(self.loaded([first, short] + tail), [], 'bytes must match where they really start')

    def test_a_cut_line_counts_only_once_some_chunk_shows_it_whole(self):
        (s1, e1), (_, e2), (s3, e3) = self.chunks()
        resume = self.line_start(e1)
        self.assertLess(resume, e1)
        reread = self.cut(resume)
        overlapping = [(0, self.result(s1, e1)), (resume, self.result(resume, reread)),
                       (reread, self.result(reread, e3))]
        self.assertEqual(self.loaded(overlapping), ['ccl-skills:skill-extraction-workflow'])
        skip = self.stream.index(b'\n', e1) + 1
        skipped = [(0, self.result(s1, e1)), (skip, self.result(skip, self.cut(skip))),
                   (self.cut(skip), self.result(self.cut(skip), e3))]
        self.assertEqual(self.loaded(skipped), [], 'the line cut at the first boundary was never shown whole')

    def test_incomplete_or_mismatched_chunks_are_not_a_load(self):
        (s1, e1), (s2, e2), (s3, e3) = self.chunks()
        good = [(s1, self.result(s1, e1)), (s2, self.result(s2, e2)), (s3, self.result(s3, e3))]
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
        self.assertEqual(self.loaded(good), ['ccl-skills:skill-extraction-workflow'], 'control')


class ShadowIdentityTests(BridgeCase):
    def state(self):
        bridge = load_bridge()
        os.environ['TMPDIR'] = self.env['TMPDIR']
        try:
            return bridge, bridge.state_dir()
        finally:
            del os.environ['TMPDIR']

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
        key = {name: self.key(bridge, name) for name in ('left', 'fresh', 'held', 'paused', 'linked')}
        outside = self.tmp / 'outside.jsonl'
        outside.write_text('keep\n')
        content = {
            f'{key["left"]}.jsonl': 'left', f'{key["fresh"]}.jsonl': 'fresh', f'{key["held"]}.jsonl': 'held',
            f'{key["paused"]}.jsonl': '', f'{key["left"]}.4242.tmp': 'temp', 'notes.tmp': 'other',
            'other.jsonl': 'other', f'{key["left"]}.lock': '', f'{key["left"]}.run.lock': '',
            f'{key["left"]}.active.turn': '{}'}
        for name, text in content.items():
            (state / name).write_text(text)
            if name != f'{key["fresh"]}.jsonl':
                os.utime(state / name, (old, old))
        inode = (state / f'{key["left"]}.jsonl').stat().st_ino
        paused = (state / f'{key["paused"]}.jsonl').stat().st_ino
        link = state / f'{key["linked"]}.jsonl'
        link.symlink_to(outside)
        os.utime(outside, (old, old))
        os.utime(link, (old, old), follow_symlinks=False)
        holder = subprocess.Popen(['python3', '-c', 'import fcntl,os,sys,time; fd=os.open(sys.argv[1], os.O_WRONLY|os.O_CREAT, 0o600); '
                                   'fcntl.flock(fd, fcntl.LOCK_EX); print("held", flush=True); time.sleep(30)',
                                   str(state / f'{key["held"]}.run.lock')], stdout=subprocess.PIPE, text=True)
        try:
            self.assertEqual(holder.stdout.readline().strip(), 'held')
            self.bridge('PreToolUse', self.edit('run_command', {'CommandLine': 'ls'}, self.tmp, conversation='sweeper'))
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
        self.assertEqual((state / f'{self.key(bridge, "sweeper")}.jsonl').stat().st_size, 0)


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


if __name__ == '__main__':
    unittest.main()
