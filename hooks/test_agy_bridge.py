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

    def test_shadow_transcript_is_private_structural_and_removed_after_the_event(self):
        transcript = self.tmp / 'logs/transcript.jsonl'
        transcript.parent.mkdir()
        transcript.write_text(json.dumps({'type': 'USER_INPUT', 'source': 'USER_EXPLICIT', 'step_index': 0,
                                          'content': 'secret-user-text'}) + '\n')
        copy = self.tmp / 'plugin'
        shutil.copytree(ROOT / 'hooks', copy / 'hooks')
        capture = self.tmp / 'captured'
        (copy / 'hooks/proposed-next-stop.sh').write_text(
            f'#!/bin/sh\nt=$(jq -r .transcript_path)\npython3 -c "import os,stat,sys; print(oct(stat.S_IMODE(os.stat(sys.argv[1]).st_mode))[2:])" "$t" > {capture}.mode\ncp "$t" {capture}\n')
        self.bridge('Stop', {'conversationId': 'priv', 'cwd': str(self.tmp), 'transcriptPath': str(transcript),
                             'terminationReason': 'NO_TOOL_CALL'}, root=copy)
        self.assertEqual(capture.with_name('captured.mode').read_text().strip(), '600')
        self.assertNotIn('secret-user-text', capture.read_text())
        self.assertIn('turn-0', capture.read_text())
        state = next((self.tmp / 'state').glob('ccl-skills-agy-*'))
        self.assertEqual(state.stat().st_mode & 0o777, 0o700)
        self.assertEqual(list(state.glob('*.jsonl')), [], 'shadow transcript must not outlive the event')

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
