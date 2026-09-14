#!/usr/bin/env python3
"""Normalize host hook inputs and transcript evidence, without executing tool text.

Codex shapes: openai/codex rust-v0.154.0 protocol/models.rs and
core/src/tools/context.rs. Unsupported evidence remains unverifiable.
"""
import hashlib
import json
import os
from pathlib import Path
import re
import shlex
import stat
import sys


class TranscriptTruncated(ValueError):
    """The bounded scan could not establish complete transcript evidence."""


def handoff(text, actionable_only=False):
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
            if actionable_only and re.fullmatch(r'none(?:\s*[—–-]\s*status only)?',
                                               match[1].strip(), re.IGNORECASE):
                continue
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
                if stream.read(1):
                    raise TranscriptTruncated()
                return
            line = stream.readline(limit + 1)
            if not line:
                return
            if len(line) > limit:
                raise TranscriptTruncated()
            remaining -= len(line)
            yield line.decode('utf-8', errors='replace')
        if stream.read(1):
            raise TranscriptTruncated()


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


def bounded_skill_source(path):
    descriptor = os.open(path, os.O_RDONLY | os.O_NONBLOCK)
    with os.fdopen(descriptor, 'rb') as stream:
        if not stat.S_ISREG(os.fstat(stream.fileno()).st_mode):
            raise ValueError('skill source is not a regular file')
        raw = stream.read(128 * 1024 + 1)
    if len(raw) > 128 * 1024:
        raise ValueError('skill source exceeds its bounded limit')
    return raw


def skill_reads(name, args, cwd, sources):
    """Describe literal reads; compare output against bounded current file bytes.

    None means a recognizable but unsupported/unavailable skill read. An empty
    list is unrelated activity. No command is evaluated, including quoted text.
    """
    if name not in ('exec_command', 'shell_command') or not isinstance(args, dict):
        return []
    command = args.get('cmd' if name == 'exec_command' else 'command')
    if not isinstance(command, str) or 'SKILL.md' not in command:
        return []
    if re.search(r'[\n\r;$`|&<>*?{}]', command):
        return None
    try:
        words = shlex.split(command)
    except ValueError:
        return None
    first, last = 1, None
    if words and words[0] in ('cat', '/bin/cat', '/usr/bin/cat'):
        operands = words[1:]
        if operands and operands[0] == '--':
            operands = operands[1:]
    elif (len(words) == 4 and words[0] in ('sed', '/bin/sed', '/usr/bin/sed')
          and words[1] == '-n' and re.fullmatch(r'[1-9][0-9]{0,6},[1-9][0-9]{0,6}p', words[2])):
        first, last = map(int, words[2][:-1].split(','))
        operands = words[3:]
        if first > last:
            return None
    else:
        return None
    if not operands or len(operands) > 32 or any(p.startswith('-') for p in operands):
        return None
    workdir = args.get('workdir', cwd)
    if not isinstance(workdir, str):
        return None
    result = []
    for operand in operands:
        path = Path(absolute(operand, absolute(workdir, cwd)))
        if path.name != 'SKILL.md' or path.parent.parent.name != 'skills':
            return None
        if path not in sources:
            # At most 64 candidate sources; each candidate/canonical read is
            # capped at 128 KiB and never blocks on a FIFO.
            if len(sources) >= 64:
                return None
            try:
                raw = bounded_skill_source(path)
                # The helper's installed package is the authority, never cwd
                # or an environment-selected root. A same-named project file
                # proves this owner only if it is a byte-identical copy.
                canonical = Path(__file__).resolve().parents[1] / 'skills' / path.parent.name / 'SKILL.md'
                if path != canonical.resolve() and raw != bounded_skill_source(canonical):
                    return None
                source = raw.decode('utf-8')
                frontmatter = re.match(r'\A---\r?\n(.*?)\r?\n---\r?\n(.+)', source, re.S)
                if (not frontmatter or not frontmatter[2].strip() or not re.search(
                        r'^name:\s*' + re.escape(path.parent.name) + r'\s*$', frontmatter[1], re.M)):
                    return None
                # sed addresses LF-delimited lines; Unicode separators remain
                # literal body characters and must not shift chunk coverage.
                parts = source.split('\n')
                sources[path] = [part + '\n' for part in parts[:-1]]
                if parts[-1]:
                    sources[path].append(parts[-1])
            except (OSError, UnicodeError, ValueError):
                return None
        lines = sources[path]
        end = min(last or len(lines), len(lines))
        if first > end:
            return None
        result.append({'path': path, 'skill': 'ccl-skills:' + path.parent.name,
                       'first': first, 'last': end, 'total': len(lines),
                       'lines': lines})
    return result


def successful_output(value):
    if not isinstance(value, str):
        return False
    header, separator, body = value.partition('\nOutput:\n')
    return bool(separator and body.strip()
                and re.search(r'^Process exited with code 0$', header, re.M)
                and not re.search(r'^Process running with session ID ', header, re.M)
                and 'Warning: truncated output' not in value)


def compact_boundary(event):
    """Only native top-level records identify a context reset."""
    return (not event.get('isSidechain') and
            ((event.get('type') == 'system' and event.get('subtype') == 'compact_boundary')
             or (event.get('type') == 'compacted' and isinstance(event.get('payload'), dict))))


def summarize(lines, cwd, current=False):
    requested, completed, edited = set(), set(), set()
    pending = {}
    pending_reads, coverage, sources = {}, {}, {}
    pending_visibility = set()
    contract = continuation_contract()
    contract_visible = False
    prior_handoff = False
    verifiable = current
    invalid = False
    unverifiable_reads = False
    for line in lines:
        try:
            event = json.loads(line)
        except (ValueError, TypeError):
            continue
        if not isinstance(event, dict):
            continue
        if compact_boundary(event):
            # Completed audit evidence survives; pending requests and partial
            # coverage must never be joined across a native context reset.
            pending.clear()
            pending_reads.clear()
            pending_visibility.clear()
            coverage.clear()
            continue
        if current and event.get('isSidechain'):
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
                    skills = pending.pop(tool_id, []) if isinstance(tool_id, str) else []
                    if not item.get('is_error'):
                        completed.update(skills)
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
            reads = skill_reads(name, args, cwd, sources)
            if reads is None:
                unverifiable_reads = True
            elif reads and isinstance(item.get('call_id'), str):
                pending_reads[item['call_id']] = reads
        elif kind == 'function_call_output':
            call_id = item.get('call_id')
            if isinstance(call_id, str) and call_id in pending_visibility:
                pending_visibility.remove(call_id)
                if successful_output(item.get('output')):
                    body = item['output'].partition('\nOutput:\n')[2]
                    contract_visible = contract_visible or visible_contract(body, contract)
            reads = pending_reads.pop(call_id, []) if isinstance(call_id, str) else []
            if reads and successful_output(item.get('output')):
                body = item['output'].partition('\nOutput:\n')[2]
                expected = ''.join(''.join(read['lines'][read['first'] - 1:read['last']])
                                   for read in reads)
                if body.rstrip('\n') != expected.rstrip('\n'):
                    unverifiable_reads = True
                    continue
                for read in reads:
                    if read['path'] not in coverage:
                        coverage[read['path']] = [bytearray(read['total']), 0]
                    covered = coverage[read['path']]
                    first, last = read['first'] - 1, read['last']
                    covered[1] += last - first - covered[0][first:last].count(1)
                    covered[0][first:last] = b'\x01' * (last - first)
                    if covered[1] == read['total']:
                        completed.add(read['skill'])
                        # Codex has no Skill request; only a completed full read
                        # is invocation evidence, including proven line chunks.
                        requested.add(read['skill'])
    return {'requested_skills': sorted(requested), 'completed_skills': sorted(completed),
            'edit_paths': sorted(edited), 'verifiable': verifiable and not invalid and not unverifiable_reads,
            'unverifiable_reads': unverifiable_reads,
            'prior_handoff': prior_handoff, 'continuation_contract_visible': contract_visible}


def transcript(path, cwd):
    """Whole-session audit; exceeding any leading scan limit is an error."""
    return summarize(transcript_lines(path), cwd)


def context_transcript(path, cwd, start_offset=0):
    """Current-context evidence from a bounded snapshot of a regular JSONL file.

    A supplied byte high-watermark excludes requests that started before actual
    PostCompact delivery, even before its native boundary record is flushed.
    An omitted prefix is safe only when a later native boundary is visible.
    Unknown/incomplete context discards evidence; IDs contain no transcript text.
    """
    unknown = {'requested_skills': [], 'completed_skills': [], 'edit_paths': [],
               'verifiable': False, 'context_complete': False, 'context_id': None,
               'unverifiable_reads': False, 'prior_handoff': False,
               'continuation_contract_visible': False}
    if type(start_offset) is not int or start_offset < 0:
        return unknown
    try:
        descriptor = os.open(path, os.O_RDONLY | os.O_NONBLOCK)
        with os.fdopen(descriptor, 'rb') as stream:
            metadata = os.fstat(stream.fileno())
            if not stat.S_ISREG(metadata.st_mode) or start_offset > metadata.st_size:
                return unknown
            end = metadata.st_size
            begin = max(start_offset, end - 16 * 1024 * 1024)
            partial = False
            if begin:
                stream.seek(begin - 1)
                partial = stream.read(1) != b'\n'
            stream.seek(begin)
            data = stream.read(end - begin)
            if len(data) != end - begin:
                return unknown
        omitted = begin > start_offset
        if partial:
            newline = data.find(b'\n')
            if newline < 0:
                return unknown
            begin += newline + 1
            data = data[newline + 1:]
        # rsplit bounds allocated records even for millions of tiny lines.
        records = data.rsplit(b'\n', 20001)
        if records and not records[-1]:
            records.pop()
        if len(records) > 20000:
            dropped = len(records) - 20000
            begin += sum(len(line) + 1 for line in records[:dropped])
            records = records[dropped:]
            omitted = True
        context_id = None if omitted else (f'offset:{start_offset}' if start_offset else 'start:0')
        selected = []
        complete = not omitted
        position = begin
        for raw in records:
            line_position = position
            position += len(raw) + 1
            if len(raw) > 1024 * 1024:
                complete = False
                continue
            try:
                line = raw.decode('utf-8')
                event = json.loads(line)
                if not isinstance(event, dict):
                    raise ValueError('unsupported record')
            except (ValueError, UnicodeError, RecursionError):
                complete = False
                continue
            if compact_boundary(event):
                context_id = f'native:{line_position}:' + hashlib.sha256(raw).hexdigest()[:16]
                selected.clear()
                complete = True
            else:
                selected.append(line)
        if not complete:
            return dict(unknown, context_id=context_id)
        summary = summarize(selected, cwd, current=True)
        summary.update(context_complete=True, context_id=context_id)
        return summary
    except (OSError, ValueError, TypeError, RecursionError):
        return unknown


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
    if not isinstance(final, str) or not final.strip() or machine_artifact(final):
        return None
    actionable = handoff(final, actionable_only=True)
    if handoff(final) and not actionable:
        return None
    # A declared next action triggers a recheck, never inferred authorization.
    # Host stop_hook_active bounds this reminder to one stop attempt per turn.
    if actionable:
        return {'decision': 'block', 'reason': (
            'Delivery continuation reminder: a proposed-next: action is still declared. '
            'Recheck the active goal and current user scope before stopping. If that action is already '
            'authorized and runnable, execute it now instead of waiting for another continue message. '
            'For unrun, failed or inconclusive checks, continue available diagnosis, research, safe repair '
            'and retesting; a report alone does not complete implementation. Respect explicit stop, '
            'planning-only and status-only requests. If a user decision or missing authority/resource '
            'prevents action, report the concrete blocker; do not invent work or bypass a failed gate. '
            'This reminder supplies no new goal or authorization.')}
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
        try:
            print(json.dumps(transcript(path, sys.argv[3] if len(sys.argv) > 3 else os.getcwd())))
        except TranscriptTruncated:
            # Discard partial evidence even for callers that inspect stdout
            # without propagating the subprocess failure status.
            print(json.dumps({'requested_skills': [], 'completed_skills': [], 'edit_paths': [],
                              'verifiable': False, 'truncated': True, 'prior_handoff': False,
                              'continuation_contract_visible': False}))
            return 1
    elif sys.argv[1] == 'proposed-next':
        try:
            raw = sys.stdin.read(2 * 1024 * 1024 + 1)
            if len(raw) > 2 * 1024 * 1024:
                raise ValueError('oversized input')
            result = proposed_next(json.loads(raw))
            if result:
                print(json.dumps(result))
        except TranscriptTruncated:
            print(json.dumps({'systemMessage': 'Delivery handoff reminder unverified: transcript scan exceeded its bounded limit.'}))
        except (OSError, ValueError, TypeError, IndexError, AttributeError):
            print(json.dumps({'systemMessage': 'Delivery handoff reminder unavailable: input or transcript could not be verified.'}))
    return 0


if __name__ == '__main__':
    try:
        sys.exit(main())
    except (OSError, ValueError, TypeError, IndexError):
        sys.exit(1)
