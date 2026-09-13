#!/usr/bin/env python3
"""Normalize host hook inputs and transcript evidence, without executing tool text.

Codex shapes: openai/codex rust-v0.154.0 protocol/models.rs and
core/src/tools/context.rs. Unsupported evidence remains unverifiable.
"""
import json
import os
from pathlib import Path
import re
import shlex
import stat
import sys


def handoff(text):
    """Recognize an assistant handoff, never quoted examples or fenced output."""
    if not isinstance(text, str):
        return False
    fence = None
    for line in text.splitlines():
        stripped = line.strip()
        match = re.match(r'^(`{3,}|~{3,})', stripped)
        if match:
            token = match[1]
            if fence is None:
                fence = token
            elif token[0] == fence[0] and len(token) >= len(fence) and stripped == token:
                fence = None
            continue
        if fence is not None or stripped.startswith('>') or line.startswith(('    ', '\t')):
            continue
        match = re.fullmatch(r'(?:[-*] )?(?:\*\*)?proposed-next:(?:\*\*)?\s*(.+)', stripped)
        if match and match[1].strip() and not match[1].strip().startswith('<'):
            return True
    return False


def text_content(content):
    if isinstance(content, str):
        return content
    if not isinstance(content, list):
        return ''
    return '\n'.join(item['text'] for item in content if isinstance(item, dict)
                     and item.get('type') in ('text', 'output_text')
                     and isinstance(item.get('text'), str))


def continuation_contract():
    # Optional in minimal vendored runtimes. Read the canonical rule instead of
    # duplicating its prose; a missing rule only disables this visibility signal.
    path = Path(__file__).resolve().parents[1] / 'skills/product-rd-workflow/SKILL.md'
    try:
        with path.open(encoding='utf-8') as stream:
            source = stream.read(128 * 1024)
    except OSError:
        return ''
    for paragraph in source.split('\n\n'):
        if paragraph.startswith('**Continuation-proposal output contract (session-wide for product delivery).**'):
            return ' '.join(paragraph.split())
    return ''


def visible_contract(content, contract):
    text = text_content(content)
    return bool(contract and 'Warning: truncated output' not in text
                and '<persisted-output>' not in text and contract in ' '.join(text.split()))


def transcript_lines(path):
    # Bound both event count and bytes, including a hostile oversized JSONL line.
    remaining = 16 * 1024 * 1024
    descriptor = os.open(path, os.O_RDONLY | os.O_NONBLOCK)
    with os.fdopen(descriptor, 'rb') as stream:
        if not stat.S_ISREG(os.fstat(stream.fileno()).st_mode):
            raise ValueError('transcript is not a regular file')
        for _ in range(20000):
            limit = min(remaining, 1024 * 1024)
            if limit <= 0:
                break
            line = stream.readline(limit + 1)
            if not line or len(line) > limit:
                break
            remaining -= len(line)
            yield line.decode('utf-8', errors='replace')


def absolute(path, cwd):
    return os.path.realpath(os.path.join(cwd, path))


def paths(payload):
    tool = payload.get('tool_name')
    args = payload.get('tool_input')
    args = args if isinstance(args, dict) else {}
    cwd = payload.get('cwd') or os.getcwd()
    cwd = cwd if isinstance(cwd, str) else os.getcwd()
    found = []
    malformed = False
    if tool == 'apply_patch':
        patch = args.get('command', args.get('patchText', args.get('input')))
        if not isinstance(patch, str):
            return {'paths': [], 'malformed_patch': True}
        # Patch framing splits on LF/CRLF only. Other Unicode separators are
        # filename characters and must not hide a symlinked protected target.
        lines = [line[:-1] if line.endswith('\r') else line
                 for line in patch.strip().split('\n')]
        if len(lines) < 3 or lines[0] != '*** Begin Patch' or lines[-1] != '*** End Patch':
            return {'paths': [], 'malformed_patch': True}
        operation = None
        for line in lines[1:-1]:
            match = re.fullmatch(r'\*\*\* (Add|Update|Delete) File: (.+)', line)
            move = re.fullmatch(r'\*\*\* Move to: (.+)', line)
            if match:
                operation = match[1]
                found.append(match[2])
            elif move and operation == 'Update':
                found.append(move[1])
            elif line.startswith('*** ') and line != '*** End of File':
                malformed = True
        malformed = malformed or not found or any(not p.strip() or '\x00' in p for p in found)
    else:
        for key in ('file_path', 'notebook_path', 'path'):
            value = args.get(key)
            if isinstance(value, str) and value and '\x00' not in value:
                found.append(value)
                break
    return {'paths': list(dict.fromkeys(absolute(p, cwd) for p in found)),
            'malformed_patch': malformed}


def skill_reads(name, args, cwd):
    # Deliberately small shell grammar: literal cat operands, no shell expansion,
    # pipelines, redirection, compound commands, or environment substitution.
    if name not in ('exec_command', 'shell_command') or not isinstance(args, dict):
        return []
    command = args.get('cmd' if name == 'exec_command' else 'command')
    if not isinstance(command, str) or re.search(r'[\n\r;$`|&<>*?{}]', command):
        return []
    try:
        words = shlex.split(command)
    except ValueError:
        return []
    if len(words) < 2 or words[0] not in ('cat', '/bin/cat', '/usr/bin/cat'):
        return []
    operands = words[1:]
    if operands and operands[0] == '--':
        operands = operands[1:]
    if any(p.startswith('-') for p in operands):
        return []
    workdir = args.get('workdir', cwd)
    if not isinstance(workdir, str):
        return []
    result = []
    for operand in operands:
        path = Path(absolute(operand, absolute(workdir, cwd)))
        if path.name == 'SKILL.md' and path.parent.parent.name == 'skills':
            result.append(path.parent.name)
    return result


def successful_output(value):
    if not isinstance(value, str):
        return False
    header, separator, body = value.partition('\nOutput:\n')
    return bool(separator and body.strip()
                and re.search(r'^Process exited with code 0$', header, re.M)
                and not re.search(r'^Process running with session ID ', header, re.M)
                and 'Warning: truncated output' not in value)


def transcript(path, cwd):
    requested, completed, edited = set(), set(), set()
    pending = {}
    pending_visibility = set()
    contract = continuation_contract()
    contract_visible = False
    prior_handoff = False
    verifiable = False
    invalid = False
    for line in transcript_lines(path):
        try:
            event = json.loads(line)
        except (ValueError, TypeError):
            continue
        if not isinstance(event, dict):
            continue
        if event.get('type') == 'turn_context':
            context = event.get('payload', {})
            if isinstance(context, dict) and isinstance(context.get('cwd'), str):
                cwd = context['cwd']
        if event.get('type') in ('assistant', 'user'):
            message = event.get('message', {})
            content = message.get('content', []) if isinstance(message, dict) else []
            if (event['type'] == 'assistant' and not event.get('isSidechain')
                    and isinstance(content, list)
                    and not any(isinstance(i, dict) and i.get('type') == 'tool_use' for i in content)):
                prior_handoff = prior_handoff or handoff(text_content(content))
            if not isinstance(content, list):
                continue
            for item in content:
                if not isinstance(item, dict):
                    continue
                if event['type'] == 'assistant' and item.get('type') == 'tool_use':
                    name, args = item.get('name'), item.get('input', {})
                    verifiable = True
                    if not isinstance(name, str):
                        invalid = True
                    if isinstance(name, str) and isinstance(item.get('id'), str):
                        pending_visibility.add(item['id'])
                    if name == 'Skill':
                        skill = args.get('skill') if isinstance(args, dict) else None
                        if isinstance(skill, str) and skill:
                            requested.add(skill.lower())
                            if item.get('id'):
                                pending[item['id']] = [skill.lower()]
                        else:
                            invalid = True
                    if name in ('Edit', 'Write', 'MultiEdit', 'NotebookEdit'):
                        edited.update(paths({'tool_name': name, 'tool_input': args, 'cwd': cwd})['paths'])
                elif event['type'] == 'user' and item.get('type') == 'tool_result':
                    tool_id = item.get('tool_use_id')
                    if isinstance(tool_id, str) and tool_id in pending_visibility:
                        pending_visibility.remove(tool_id)
                        if not item.get('is_error'):
                            contract_visible = contract_visible or visible_contract(item.get('content'), contract)
                    if not item.get('is_error'):
                        completed.update(pending.pop(item.get('tool_use_id'), []))
        if event.get('type') != 'response_item' or not isinstance(event.get('payload'), dict):
            continue
        item = event['payload']
        kind, name = item.get('type'), item.get('name')
        if (kind == 'message' and item.get('role') == 'assistant'
                and item.get('phase') in (None, 'final_answer')):
            prior_handoff = prior_handoff or handoff(text_content(item.get('content')))
        if kind in ('function_call', 'custom_tool_call'):
            verifiable = True
            if not isinstance(name, str):
                invalid = True
                continue
            if kind == 'custom_tool_call':
                args = {'command': item.get('input')}
            else:
                try:
                    args = json.loads(item.get('arguments', ''))
                except (ValueError, TypeError):
                    invalid = True
                    continue
            if name == 'apply_patch':
                edited.update(paths({'tool_name': name, 'tool_input': args, 'cwd': cwd})['paths'])
            if name in ('exec_command', 'shell_command') and isinstance(item.get('call_id'), str):
                pending_visibility.add(item['call_id'])
            skills = skill_reads(name, args, cwd)
            if skills and item.get('call_id'):
                pending[item['call_id']] = ["ccl-skills:" + skill for skill in skills]
        elif kind == 'function_call_output':
            call_id = item.get('call_id')
            if isinstance(call_id, str) and call_id in pending_visibility:
                pending_visibility.remove(call_id)
                if successful_output(item.get('output')):
                    body = item['output'].partition('\nOutput:\n')[2]
                    contract_visible = contract_visible or visible_contract(body, contract)
            skills = pending.pop(item.get('call_id'), [])
            if successful_output(item.get('output')):
                # A successful command with unrelated output is not a skill load.
                body = item['output'].partition('\nOutput:\n')[2]
                skills = [skill for skill in skills if re.search(
                    r'^name:\s*' + re.escape(skill.split(':')[-1]) + r'\s*$', body, re.M)]
                completed.update(skills)
                # Codex has no Skill request; only a completed read is invocation evidence.
                requested.update(skills)
    return {'requested_skills': sorted(requested), 'completed_skills': sorted(completed),
            'edit_paths': sorted(edited), 'verifiable': verifiable and not invalid,
            'prior_handoff': prior_handoff, 'continuation_contract_visible': contract_visible}


def machine_artifact(text):
    try:
        json.loads(text)
        return True
    except ValueError:
        pass
    lines = text.strip().splitlines()
    match = re.match(r'^(`{3,}|~{3,})', lines[0]) if lines else None
    if not match:
        return False
    fence = match[1]
    for index, line in enumerate(lines[1:], 1):
        if re.fullmatch(re.escape(fence[0]) + '{' + str(len(fence)) + ',}', line.strip()):
            return index == len(lines) - 1
    return False


def proposed_next(payload):
    if (not isinstance(payload, dict) or payload.get('hook_event_name') != 'Stop'
            or payload.get('stop_hook_active') is not False):
        return None
    final = payload.get('last_assistant_message')
    if not isinstance(final, str) or not final.strip() or machine_artifact(final) or handoff(final):
        return None
    path = payload.get('transcript_path')
    if not isinstance(path, str) or not path:
        return None
    cwd = payload.get('cwd')
    summary = transcript(path, cwd if isinstance(cwd, str) else os.getcwd())
    eligible = (any(skill in ('product-rd-workflow', 'ccl-skills:product-rd-workflow')
                    for skill in summary['completed_skills']) or summary['prior_handoff']
                or summary['continuation_contract_visible'])
    if not eligible:
        return None
    # This is formatting eligibility, never intent, authorization, or completed
    # owner evidence. A source review may expose the rule and receive one nudge.
    return {'decision': 'block', 'reason': (
        'Delivery handoff reminder: repair one proposed-next: line with the next action and scope, '
        'or proposed-next: none — status only when there is no authorized next action. '
        'Preserve the active original goal, current user stop and requested output format. '
        'Do not invent work or authority, and do not ask the user to repair formatting. '
        'If already-authorized work remains and can be completed now, finish it instead of ending prematurely. '
        'This reminder supplies no new goal or authorization.')}


def main():
    if sys.argv[1] == 'paths':
        value = json.load(sys.stdin)
        print(json.dumps(paths(value if isinstance(value, dict) else {})))
    elif sys.argv[1] == 'transcript':
        path = sys.argv[2]
        if not os.path.isfile(path):
            return 1
        print(json.dumps(transcript(path, sys.argv[3] if len(sys.argv) > 3 else os.getcwd())))
    elif sys.argv[1] == 'proposed-next':
        try:
            raw = sys.stdin.read(2 * 1024 * 1024 + 1)
            if len(raw) > 2 * 1024 * 1024:
                raise ValueError('oversized input')
            result = proposed_next(json.loads(raw))
            if result:
                print(json.dumps(result))
        except (OSError, ValueError, TypeError, IndexError, AttributeError):
            print(json.dumps({'systemMessage': 'Delivery handoff reminder unavailable: input or transcript could not be verified.'}))
    return 0


if __name__ == '__main__':
    try:
        sys.exit(main())
    except (OSError, ValueError, TypeError, IndexError):
        sys.exit(1)
