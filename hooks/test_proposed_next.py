#!/usr/bin/env python3
"""Synthetic native Stop payloads; no real host state or conversations."""
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
        for text in ('proposed-next: none — status only', '**proposed-next:** none — status only',
                     'proposed-next: none — all requested work is done and verified'):
            with self.subTest(text=text):
                self.payload['last_assistant_message'] = text
                self.assertEqual(self.run_hook(), {})

    def assert_decision_recheck(self, payload):
        result = self.run_hook(payload)
        self.assert_block(result)
        self.assertIn('Decision recheck', result['reason'])
        self.assertIn('security', result['reason'])
        self.assertIn('supplies no new goal or authorization', result['reason'])
        self.assertEqual(self.run_hook(dict(payload, stop_hook_active=True)), {})

    def test_user_dependent_stop_rechecks_the_blocker_once(self):
        for events in ([], self.claude_load()):
            self.events(events)
            for text in ('proposed-next: blocked: need an explicit decision',
                         'proposed-next: none — awaiting approval',
                         'proposed-next: none - waiting for a resource',
                         'proposed-next: none — 等待确认安全负责人'):
                with self.subTest(text=text):
                    self.assert_decision_recheck(dict(self.payload, last_assistant_message=text))

    def test_permission_question_after_edits_rechecks_instead_of_formatting(self):
        for events in (self.claude_load(), self.edit_events()):
            self.events(events)
            for text in ('Patch is ready. Should I proceed with the remaining tests?',
                         'Done with step 1. Do you want me to continue?',
                         '第一步已完成，是否继续？', '安全风险需要你决定，要不要我修改？',
                         'Patch ready. **Should I proceed?**', '**是否继续？**',
                         'Patch ready. __Should I proceed?__', '_是否继续？_',
                         '***Should I proceed?***', '*是否继续？*',
                         '**是否继续？**\nproposed-next: none — status only'):
                with self.subTest(text=text):
                    self.assert_decision_recheck(dict(self.payload, last_assistant_message=text))
        self.events([])
        for text in ('Should I proceed?', '是否继续？', '**Should I proceed?**', '_是否继续？_'):
            self.payload['last_assistant_message'] = text
            self.assertEqual(self.run_hook(), {})
        self.events(self.edit_events())
        self.payload['last_assistant_message'] = 'Done; checks passed.'
        self.assertEqual(self.run_hook(), {})

    def test_long_permission_lines_finish_within_hook_timeout(self):
        self.events(self.edit_events())
        prefix = 'Should I do this; ' * 60000
        for suffix, expected in (('', None), ('continue?', 'block')):
            with self.subTest(terminal_question=bool(suffix)):
                payload = dict(self.payload, last_assistant_message=prefix + suffix)
                result = subprocess.run(
                    ['python3', str(self.hooks / 'host-input.py'), 'proposed-next'],
                    input=json.dumps(payload), text=True, capture_output=True,
                    cwd=self.root, timeout=5)
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertEqual(result.stderr, '')
                value = json.loads(result.stdout) if result.stdout else {}
                self.assertEqual(value.get('decision'), expected)

    def test_finished_none_states_are_not_waits(self):
        self.events(self.claude_load())
        for text in ('proposed-next: none — PR approved and merged',
                     'proposed-next: none — tests confirm the fix',
                     'proposed-next: none — permission tests added',
                     'proposed-next: none — authorization module refactored',
                     'proposed-next: none — status only; awaiting nothing',
                     'proposed-next: none — 已确认完成',
                     'proposed-next: none — 已批准并合并',
                     'proposed-next: none — merged after your approval',
                     'proposed-next: none — all done; let me know if you need more',
                     'proposed-next: none — fixed the await bug in fetch()',
                     'proposed-next: none — 修复了等待超时',
                     'proposed-next: none — 审批流程已实现',
                     'proposed-next: none — PR opened; awaiting review',
                     "Done.\nLet me know if you'd like me to make any other changes.\nproposed-next: none — complete",
                     'proposed-next: none — 完成，期待你的反馈', 'proposed-next: none — 已按你定义的接口实现',
                     'proposed-next: none — merged based on your approval'):
            with self.subTest(text=text):
                self.assertEqual(self.run_hook(dict(self.payload, last_assistant_message=text)), {})

    def test_more_user_waits_and_labelled_questions_are_rechecked(self):
        self.events(self.claude_load())
        for text in ('proposed-next: none — your call', 'proposed-next: none — needs sign-off',
                     'proposed-next: none — 等你拍板', 'proposed-next: none — 需要你审批',
                     'Patch ready. Should I push it?\nproposed-next: none — work is ready',
                     'Ready to merge. OK to merge?', 'Should I proceed? Or stop?',
                     'Should I push the branch?\nproposed-next: none — status only',
                     'proposed-next: none — 待确认', 'proposed-next: none — pending approval',
                     'proposed-next: none — decision pending', 'proposed-next: none — 负责人未定',
                     'proposed-next: none — need the owner to sign off', 'proposed-next: none — 请选择方案 A 或 B',
                     '已改完。继续？\nproposed-next: none — 改动已完成', '要不要我继续\nproposed-next: none — 改动已完成',
                     'proposed-next: none — 由你决定', 'proposed-next: none — up to you',
                     'proposed-next: none — need access to prod', 'Done — should I push?\nproposed-next: none — ready',
                     '我可以继续吗？\nproposed-next: none — 改动已完成'):
            with self.subTest(text=text):
                self.assert_decision_recheck(dict(self.payload, last_assistant_message=text))

    def test_announced_next_steps_after_work_recheck_instead_of_stopping(self):
        plan = ('已完成两项检查。下一步：\n1. 补回归用例\n2. 重跑本地套件\n3. 跑一次付费对照生成\n'
                '先推进前两步；付费对照还需要确定费用上限。')
        for events in (self.edit_events(), self.claude_load(), self.codex_read()):
            self.events(events)
            for text in (plan, "Patch applied. Next, I'll rerun the suite and update the docs.",
                         '接下来我会补测试并重跑。', 'Now let me run the remaining checks.',
                         'The config change is in. I will now update the migration.',
                         'Step 1 is done; the paid comparison run still needs to settle a budget cap.',
                         '**接下来我先修复失败用例。**', '第一步完成，我马上跑回归。',
                         '下一步我先跑回归。\nproposed-next: none — status only'):
                with self.subTest(text=text):
                    payload = dict(self.payload, last_assistant_message=text)
                    self.assert_decision_recheck(payload)
                    self.assertIn('not a stopping point', self.run_hook(payload)['reason'])

    def test_optional_clause_does_not_hide_an_unconditional_next_step(self):
        self.events(self.edit_events())
        for text in ("Patch applied. Next, I'll rerun the tests; let me know if you need anything else.",
                     "Next, I'll rerun the tests. If you want, I can also add a flag.",
                     "Let me know if you need a flag; next, I'll rerun the tests.",
                     '改动已完成，接下来我会跑回归；如需其他调整请告诉我。',
                     '如需其他调整请告诉我。接下来我会跑回归。'):
            with self.subTest(text=text):
                self.assert_decision_recheck(dict(self.payload, last_assistant_message=text))

    def test_condition_applies_to_its_own_announced_step(self):
        self.events(self.edit_events())
        for text in ("If you want, next I'll add an optional flag.",
                     "Next, I'll add the flag if you want it.",
                     '如果你需要，接下来我会补文档。',
                     '接下来我会补文档，如果你需要的话。'):
            with self.subTest(text=text):
                self.assertEqual(self.run_hook(dict(self.payload, last_assistant_message=text)), {})

    def test_routine_test_permission_recheck_does_not_invent_a_cost_blocker(self):
        self.events(self.edit_events())
        for text in ('proposed-next: blocked: 小额测试等待你批准费用上限',
                     '测试环境的回归已准备好，是否开始？',
                     '开发环境验证准备完成，请确认授权？',
                     'Should I start the small model smoke test?'):
            with self.subTest(text=text):
                payload = dict(self.payload, last_assistant_message=text)
                self.assert_decision_recheck(payload)
                reason = self.run_hook(payload)['reason']
                self.assertIn('Small tests and routine development/test-environment operations', reason)
                self.assertIn('explicit user cost or run-count limits', reason)
                self.assertNotIn('such as a cost cap or a paid run', reason)

    def test_finished_reports_offers_and_quoted_plans_are_not_announcements(self):
        self.events(self.edit_events())
        for text in ('Done; all checks passed.', "If you want, I'll also add a CLI flag.",
                     '如需，我可以接着补文档。', '修复完成。我已经补了测试并重跑。',
                     'Earlier I said I would rerun the suite; it now passes.',
                     "Let me know if you need anything else and I'll start on it.",
                     '> 接下来我会补测试', "```text\nNext, I'll run the suite\n```",
                     "Plan was: next, I'll fix A.\nFixed A.\nFixed B.\nAll checks pass."):
            with self.subTest(text=text):
                self.assertEqual(self.run_hook(dict(self.payload, last_assistant_message=text)), {})
        self.events([])
        for text in ('接下来我会解释这个错误的含义。', "Next, I'll explain the error."):
            with self.subTest(text=text, transcript='no work evidence'):
                self.assertEqual(self.run_hook(dict(self.payload, last_assistant_message=text)), {})
                self.assertEqual(self.run_hook(dict(
                    self.payload, last_assistant_message=text + '\nproposed-next: none — status only')), {})

    def test_pleasantries_and_quoted_questions_after_edits_are_not_permission_asks(self):
        self.events(self.edit_events())
        for text in ('Done. Can I help with anything else?',
                     'Fixed. Q: why does continue fail?',
                     'Done.\n> Should I proceed?',
                     '这个问题是否已修复？', 'How should I interpret this error?',
                     'What is the default if I go ahead without a flag?',
                     'Does this look ok to you?', '不管要不要我做都行。',
                     '> **Should I proceed?**', '```text\n**是否继续？**\n```',
                     '`**Should I proceed?**`', '**Done; checks passed.**',
                     '__Done; checks passed.__'):
            with self.subTest(text=text):
                self.assertEqual(self.run_hook(dict(self.payload, last_assistant_message=text)), {})

    def edit_events(self):
        target = str(self.root / 'src.txt')
        return [
            {'type': 'assistant', 'message': {'content': [{'type': 'tool_use', 'id': 'edit',
             'name': 'Edit', 'input': {'file_path': target, 'old_string': 'a', 'new_string': 'b'}}]}},
            {'type': 'user', 'message': {'content': [{'type': 'tool_result',
             'tool_use_id': 'edit', 'is_error': False, 'content': 'updated'}]}}]

    def test_actionable_handoff_rechecks_continuation_instead_of_silently_stopping(self):
        for events in ([], self.claude_load(), self.codex_read()):
            self.events(events)
            for text in ('Next I will verify.\nproposed-next: run the existing local verification suite',
                         '**proposed-next:** repair the failing check and retest',
                         'proposed-next: none — status only\nproposed-next: finish the remaining repair',
                         'proposed-next: blocked: need approval\nproposed-next: run local checks',
                         'proposed-next: nonetheless finish the repair'):
                payload = dict(self.payload, last_assistant_message=text)
                result = self.run_hook(payload)
                self.assert_block(result)
                self.assertIn('execute it now', result['reason'])
                self.assertIn('planning-only', result['reason'])
                self.assertIn('supplies no new goal or authorization', result['reason'])
                self.assertEqual(self.run_hook(dict(payload, stop_hook_active=True)), {})

    def test_diagnosis_scope_and_question_turn_are_named_in_both_reminders(self):
        # Observed stops after a verified root cause: the agent read "missing
        # authority" as "you only asked me to investigate", and a clarifying
        # question as a status-only request. Both reminders must close those terms.
        for events in ([], self.claude_load()):
            self.events(events)
            for text in (
                    'Fixing it changes shared code and opens an MR, beyond the investigation you asked for.\n'
                    'proposed-next: blocked: limit fix, consistency test and MR — waiting for you to authorize the code change',
                    '这一轮你只问了一个问题，我只解释了现状。\n'
                    'proposed-next: blocked: 上限修复、补测试、提 MR——改共享仓库需要你确认',
                    'Root cause verified.\nproposed-next: open a branch, fix the limit, add the test and open the MR',
                    'Required CI passed; the advisory review timed out and its evidence was cleared.\n'
                    'proposed-next: blocked: complete the CI review — no resume handle; a retry restarts from scratch',
                    'Both MRs pushed; required CI is still running, the MRs stay in Draft.\n'
                    'proposed-next: wait for CI to finish and for your merge confirmation'):
                with self.subTest(text=text):
                    result = self.run_hook(dict(self.payload, last_assistant_message=text))
                    self.assert_block(result)
                    self.assertIn('you only asked me to investigate', result['reason'])
                    self.assertIn('failure or diagnosis goal includes the verified fix', result['reason'])
                    # Closing the terms must not widen past an explicit user
                    # limit: a "fix locally, do not push" instruction still binds.
                    self.assertIn('unless an explicit user limit says otherwise (diagnosis only, no push)',
                                  result['reason'])
                    self.assertIn('clarifying question is not a status-only request', result['reason'])
                    self.assertIn('outward-facing" — a feature branch and its MR/PR are routine', result['reason'])
                    self.assertIn('stop bar you proposed yourself', result['reason'])
                    self.assertIn('A blocker names something only the user can supply', result['reason'])
                    self.assertIn('a rerun or retry of a failed, timed-out or inconclusive check', result['reason'])
                    self.assertIn('marking that MR/PR ready once your own checks pass', result['reason'])
                    self.assertIn('waiting on a CI run you can poll', result['reason'])
                    self.assertIn('supplies no new goal or authorization', result['reason'])

    def doc_edit(self, relative, tool_id='doc', tool='Write'):
        target = str(self.root / relative)
        return [
            {'type': 'assistant', 'message': {'content': [{'type': 'tool_use', 'id': tool_id,
             'name': tool, 'input': {'file_path': target, 'content': 'x'}}]}},
            {'type': 'user', 'message': {'content': [{'type': 'tool_result',
             'tool_use_id': tool_id, 'is_error': False, 'content': 'written'}]}}]

    def test_reader_doc_edit_without_tighten_doc_gets_one_closeout_reminder(self):
        # Observed: 26 of 29 sessions that edited plans, specs, READMEs or
        # handoff documents never loaded tighten-doc before finishing.
        status = 'Plan updated.\nproposed-next: none — status only'
        for relative in ('docs/plans/rollout.md', 'README.md', 'handoffs/state.md', 'specs/9-x/plan.md'):
            with self.subTest(relative=relative):
                self.events(self.doc_edit(relative))
                result = self.run_hook(dict(self.payload, last_assistant_message=status))
                self.assert_block(result)
                self.assertIn('tighten-doc', result['reason'])
                self.assertIn(Path(relative).name, result['reason'])
                self.assertIn('supplies no new goal or authorization', result['reason'])
                self.assertEqual(self.run_hook(dict(self.payload, last_assistant_message=status,
                                                    stop_hook_active=True)), {})

    def test_doc_reminder_is_quiet_after_tighten_doc_or_for_agent_files(self):
        status = 'Plan updated.\nproposed-next: none — status only'
        self.events(self.claude_load('tighten-doc') + self.doc_edit('docs/plans/rollout.md'))
        self.assertEqual(self.run_hook(dict(self.payload, last_assistant_message=status)), {})
        for relative in ('skills/x/SKILL.md', 'AGENTS.md', 'CLAUDE.md', 'memory/note.md',
                         '.claude/notes.md', 'src/app.py', 'notes.txt'):
            with self.subTest(relative=relative):
                self.events(self.doc_edit(relative))
                self.assertEqual(self.run_hook(dict(self.payload, last_assistant_message=status)), {})

    def test_doc_reminder_joins_a_continuation_reminder(self):
        self.events(self.doc_edit('docs/plans/rollout.md'))
        result = self.run_hook(dict(self.payload,
                                    last_assistant_message='proposed-next: run the remaining local checks'))
        self.assert_block(result)
        self.assertIn('execute it now', result['reason'])
        self.assertIn('tighten-doc', result['reason'])

    def test_doc_reminder_covers_each_file_edit_tool(self):
        # Edits are seen through the file-edit tool calls the transcript records;
        # shell writes are outside this check by design.
        for tool in ('Edit', 'MultiEdit'):
            with self.subTest(tool=tool):
                self.events(self.doc_edit('docs/handoff.md', tool=tool))
                result = self.run_hook()
                self.assert_block(result)
                self.assertIn('handoff.md', result['reason'])

    def test_unreadable_doc_path_never_costs_the_delivery_reminder(self):
        # The document check is advisory; a path it cannot resolve (an embedded
        # NUL makes realpath raise) must not replace the continuation reminder
        # with the "reminder unavailable" notice.
        self.events(self.doc_edit('docs/plans/roll\x00out.md'))
        result = self.run_hook(dict(self.payload,
                                    last_assistant_message='proposed-next: run the remaining local checks'))
        self.assert_block(result)
        self.assertIn('execute it now', result['reason'])

    def test_doc_check_failure_never_costs_the_delivery_reminder(self):
        # The document check is advisory: whatever it raises, the continuation
        # reminder it would have joined is still returned.
        self.events(self.doc_edit('docs/plans/rollout.md'))
        spec = importlib.util.spec_from_file_location('doc_check_probe', self.hooks / 'host-input.py')
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
        payload = dict(self.payload, last_assistant_message='proposed-next: run the remaining local checks')
        with patch.object(module, 'reader_docs', side_effect=RuntimeError('unexpected')):
            result = module.proposed_next(payload)
        self.assert_block(result)
        self.assertIn('execute it now', result['reason'])
        self.assertNotIn('tighten-doc', result['reason'])

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
