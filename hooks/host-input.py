#!/usr/bin/env python3
"""Normalize host hook inputs and transcript evidence, without executing tool text.

Codex shapes: openai/codex rust-v0.154.0 protocol/models.rs and
core/src/tools/context.rs. Unsupported evidence remains unverifiable.
"""
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import re
import shlex
import stat
import sys
import tempfile

# Hook assets may be installed read-only; importing the optional state helper
# must not create bytecode beside them.
sys.dont_write_bytecode = True


class TranscriptTruncated(ValueError):
    """The bounded scan could not establish complete transcript evidence."""


def prose_lines(text):
    """Yield assistant prose lines, skipping fenced, quoted and indented text."""
    if not isinstance(text, str):
        return
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
        yield stripped


HANDOFF = re.compile(r'(?:[-*] )?(?:\*\*)?proposed-next:(?:\*\*)?\s*(.+)')


def handoff_values(text):
    """Return assistant handoff values, never quoted examples or fenced output."""
    values = []
    for stripped in prose_lines(text):
        match = HANDOFF.fullmatch(stripped)
        if match and match[1].strip() and not match[1].strip().startswith('<'):
            values.append(match[1].strip())
    return values


def handoff(text, actionable_only=False):
    """Recognize an assistant handoff, never quoted examples or fenced output."""
    return any(not (actionable_only and re.fullmatch(
        r'(?:none(?:\s*[—–-]\s*.+)?|blocked:\s*.+)', value, re.IGNORECASE))
        for value in handoff_values(text))


# A stop that waits on the user: a blocked handoff, a non-status "none" naming
# a wait for the user, or a last prose line asking permission. Matching is
# phrase-based so finished states ("PR approved", "tests confirm") stay quiet.
USER_WAIT = re.compile(
    r'^blocked:'
    r'|\b(?:await(?:s|ing)?|waiting (?:for|on)|pending)\s+(?:your|the user|user|the owner|owner|approval'
    r'|confirmation|a decision|decision|sign[- ]?off|input|reply|a resource|access|credentials)\b'
    r'|\b(?:approval|confirmation|decision|sign[- ]?off) (?:is )?(?:pending|needed|required)\b'
    r'|(?<!after )(?<!per )(?<!on )(?<!following )\byour (?:call|decision|approval|confirmation|go-ahead'
    r'|input|reply)\b|\b(?:up|over) to you\b'
    r'|\bneeds? (?:approval|confirmation|a decision|your|the owner|an owner|sign[- ]?off|access|credentials)\b'
    r'|待确认|待你(?:确认|决定|审批|批准|回复|选择)|等你|等待(?:你|用户|确认|审批|批准|授权|决定)|请你|请选择|需要你'
    r'|你来定|由你定|你定吧|由你决定|你决定|负责人未定|待审批|待批准|待授权', re.IGNORECASE)
PERMISSION_QUESTION = re.compile(
    r'(?:(?:^|[.;!:,—–-]\s*)(?:should|shall|may) I\b|\bcan I (?:proceed|continue|go ahead|start|merge|push)\b'
    r'|\b(?:do|would) you (?:want|like) me\b|\bwant me to\b'
    r'|\bok(?:ay)? to (?:merge|push|proceed|continue|go ahead|start|deploy)\b'
    r'|^(?:proceed|continue|go ahead)\b|\bgo ahead(?: and [^?？]{0,40})?(?=[?？])'
    r'|是否(?:继续|需要我|要我|合并|推送|提交|执行|开始)|需要我|请确认|你决定|您决定|由你决定|(?:^|我|[。，！；.!;,]\s*)继续'
    r'|继续吗|接着做|要不要我|可以吗|行吗)', re.IGNORECASE)
PERMISSION_REQUEST = re.compile(
    r'\blet me know if you(?:\'d| would)? (?:like|want) me to (?:continue|proceed|go ahead|push|merge)\b'
    r'|^要不要我[^。]*$', re.IGNORECASE)


# A final message that announces the agent's own next steps, or parks one on a
# decision nobody was asked for, has not finished the work it names.
ANNOUNCED_STEP = re.compile(
    r'\b(?:next|now|then),? (?:I|we)(?:\'ll| will| am going to|\'m going to)\b'
    r'|\bI(?:\'ll| will) (?:now|next|then|start|begin|proceed|continue|move on)\b'
    r'|^(?:next|now),? let me\b|^let me now\b'
    r'|\b(?:still )?needs? to (?:settle|decide|agree on|confirm) (?:a |the )?(?:budget|cost|spend|quota|cap|limit)\b'
    r'|接下来(?:我|先)?(?:会|将|要|去|就|再|先)|下一步(?:我)?(?:会|将|要|去|就|先)|先推进'
    r'|我(?:会|将|马上|这就|随后|接着)(?:去|来|再|先)?(?:推进|做|处理|执行|修|改|补|跑|运行|实现|开始|继续|提交|推送|验证|测试|检查)'
    r'|还需要(?:先)?(?:确定|确认|决定|商定)|需要先(?:确定|确认|决定)', re.IGNORECASE)
# Offers conditioned on the user are pleasantries or scope questions, not steps.
CONDITIONAL_OFFER = re.compile(r'\bif you\b|\blet me know\b|如果你|如需|如果需要|需要的话|要是你', re.IGNORECASE)


def announces_steps(text):
    lines = [line for line in prose_lines(text) if line and not HANDOFF.fullmatch(line)]
    # Conditions qualify their own sentence/semicolon clause. A separate
    # optional offer must not hide an unconditional step elsewhere on the line.
    clauses = (clause.strip('*_ ') for line in lines[-3:]
               for clause in re.split(r'[.;!?。；！？]', line))
    return any(ANNOUNCED_STEP.search(clause) and not CONDITIONAL_OFFER.search(clause)
               for clause in clauses)


def waits_on_user(values):
    return any(USER_WAIT.search(value) for value in values
               if not re.fullmatch(r'none\s*[—–-]\s*status only\.?', value, re.IGNORECASE))


def asks_permission(text):
    lines = [line for line in prose_lines(text) if line and not HANDOFF.fullmatch(line)]
    if not lines:
        return False
    line = lines[-1]
    # Remove one terminal emphasis pair, including a question after a prose
    # prefix. Fixed marker choices keep malformed Markdown scans linear.
    for marker in ('***', '___', '**', '__', '*', '_'):
        if not line.endswith(marker):
            continue
        opening = line.rfind(marker, 0, len(line) - len(marker))
        if (opening >= 0 and not line[opening + len(marker)].isspace()
                and (opening == 0 or not (line[opening - 1].isalnum()
                                         or line[opening - 1] in '\\*_'))):
            line = line[:opening] + line[opening + len(marker):-len(marker)]
            break
    # Test terminal punctuation once, rather than rescanning the remaining
    # suffix for every permission phrase in an unpunctuated long line.
    return bool((line.endswith(('?', '？')) and PERMISSION_QUESTION.search(line))
                or PERMISSION_REQUEST.search(line))


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
        metadata = os.fstat(stream.fileno())
        if not stat.S_ISREG(metadata.st_mode):
            raise ValueError('transcript is not a regular file')
        if metadata.st_size > remaining:
            raise TranscriptTruncated()
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


def stop_notice(payload, lane, message):
    """Cap notice attempts only; these markers never establish verification."""
    try:
        # Reuse the installed runtime's owned-directory/no-follow/atomic claim
        # protections. Minimal vendored runtimes may omit this optional helper.
        source = Path(__file__).resolve().with_name('skill-loading.py')
        spec = importlib.util.spec_from_file_location('ccl_stop_state', source)
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
        # Stop checks scan transcript_path even if subagent metadata also
        # carries a separate agent_transcript_path.
        notice_actor = dict(payload)
        notice_actor.pop('agent_transcript_path', None)
        key, path = module.actor(notice_actor)
        info = module.regular_info(path)
        state = module.State(key)
        try:
            if not state.claim_attempt('stop-notice-' + lane, [info.st_dev, info.st_ino]):
                return None
        finally:
            state.close()
    except Exception:
        # Missing identity, a broken optional helper or unsafe/unavailable state
        # must not invent success. This boundary only controls advisory output.
        pass
    return {'systemMessage': message}


def extraction_overflow(payload):
    path = payload.get('transcript_path')
    cwd = payload.get('cwd')
    current = context_transcript(path, cwd if isinstance(cwd, str) else os.getcwd())
    if any(skill in ('skill-extraction-workflow', 'ccl-skills:skill-extraction-workflow')
           for skill in current['requested_skills']):
        # Positive current-context evidence also proves a session invocation.
        # Missing current evidence cannot prove a missing session invocation.
        return None
    return stop_notice(payload, 'extraction-overflow',
                       'Conversation history is too large for the skill workflow check. '
                       'The check is incomplete; this does not block your task.')


def delivery_eligible(summary):
    return (any(skill in ('product-rd-workflow', 'ccl-skills:product-rd-workflow')
                for skill in summary['completed_skills']) or summary['prior_handoff']
            or summary['continuation_contract_visible'])


# Stops kept surviving the recheck by restating the blocker in a new term, so
# the test is stated as an invariant (who can act) and the observed terms are
# only examples of restatements that fail it.
NOT_BLOCKERS = (
    'A blocker names something only the user can supply: a decision the evidence cannot settle, a credential '
    'or access grant, permission the goal does not cover, or a fact absent from every source you can read. '
    'A next step you can perform yourself is not a blocker, whatever it costs in time or runs: a fix with its '
    'tests and review, a branch push and MR/PR, marking that MR/PR ready once your own checks pass instead of '
    'leaving it in Draft, waiting on a CI run you can poll, a rerun or retry of a failed, timed-out or '
    'inconclusive check, or a lookup. Restatements observed to fail this test: "you only asked me to investigate" — a failure or '
    'diagnosis goal includes the verified fix, tests, review, branch push and MR/PR to the development target '
    'unless an explicit user limit says otherwise (diagnosis only, no push); "pushing or opening an MR is outward-facing" — a feature branch '
    'and its MR/PR are routine; a count, round or stop bar you proposed yourself, unless the user adopted it as '
    'a limit; "the check can only restart '
    'from scratch"; and facts, logs, test data or access you can find or reuse yourself. A clarifying question '
    'is not a status-only request: answer it, then continue. ')

# One bounded recheck (host stop_hook_active) for stops that hand work back to
# the user; it names the real blockers and grants no authority.
DECISION_RECHECK = {'decision': 'block', 'reason': (
    'Decision recheck: this stop hands a decision, confirmation or wait back to the user. '
    'Real blockers are: missing credentials or authority; a fact unavailable from local evidence; '
    'an action the safety rules gate (destructive or irreversible without recovery, production or '
    'customer data, merge or publication outside the goal); overturning an established user direction; '
    'or a material product tradeoff the evidence cannot settle. ' + NOT_BLOCKERS +
    'An ordinary change needs no human review, '
    'sign-off or risk owner: run the self-review and external review yourself. '
    'Small tests and routine development/test-environment operations within the authorized task '
    'run directly with configured accounts; do not ask for per-run approval or invent a cost cap. '
    'Respect explicit user cost or run-count limits and keep production, destructive actions and '
    'new purchases within their actual authorization boundaries. '
    'Announcing a plan or next steps is not a stopping point: run the runnable steps now; '
    'a real blocker parks only its dependent step. Design-time security questions, '
    'security self-review, choosing the owner skill, module or approach, test and naming choices, and '
    'the next in-scope step are yours: decide, state the assumption, and finish the remaining requested '
    'work now. A report or summary does not complete delivery. If a real blocker remains, first finish '
    'all independent work, then end with proposed-next: blocked: <action> — <concrete blocker>. '
    'Respect explicit stop, planning-only and status-only requests and add no work beyond the request. '
    'This reminder supplies no new goal or authorization.')}


# Reader-facing documents edited in a session owe the tighten-doc closeout
# readback (the routing rule says so), yet it was skipped in 26 of 29 observed
# sessions. Agent-facing files are excluded: skill bodies, contracts, memory
# and scratch or temporary paths.
READER_DOC_SUFFIXES = ('.md', '.mdx', '.rst')
AGENT_DOC_NAMES = {'skill.md', 'agents.md', 'claude.md', 'memory.md'}
AGENT_DOC_DIRS = {'memory', '.claude', '.codex', '.git', 'node_modules', 'skills', 'agent-context',
                  'scratchpad'}


def reader_docs(edit_paths, cwd):
    base = os.path.realpath(cwd) if isinstance(cwd, str) and cwd else None
    temp_roots = tuple(os.path.realpath(root) + os.sep
                       for root in {tempfile.gettempdir(), '/tmp', '/private/tmp', '/var/folders'})
    found = []
    for path in edit_paths:
        if not isinstance(path, str) or not path.lower().endswith(READER_DOC_SUFFIXES):
            continue
        real = os.path.realpath(path)
        if base and (real == base or real.startswith(base + os.sep)):
            parts = os.path.relpath(real, base).split(os.sep)
        elif real.startswith(temp_roots):
            continue
        else:
            parts = real.split(os.sep)
        if parts[-1].lower() in AGENT_DOC_NAMES or any(p.lower() in AGENT_DOC_DIRS for p in parts[:-1]):
            continue
        found.append(real)
    return found


def doc_closeout_note(payload):
    path, cwd = payload.get('transcript_path'), payload.get('cwd')
    if not isinstance(path, str) or not path:
        return ''
    cwd = cwd if isinstance(cwd, str) else os.getcwd()
    try:
        summary = transcript(path, cwd)
    except TranscriptTruncated:
        summary = context_transcript(path, cwd)
    except (OSError, ValueError):
        return ''
    if any(skill.split(':')[-1] == 'tighten-doc' for skill in summary['completed_skills']):
        return ''
    docs = reader_docs(summary['edit_paths'], cwd)
    if not docs:
        return ''
    names = ', '.join(sorted({os.path.basename(doc) for doc in docs})[:5])
    return ('Document closeout: this session edited reader-facing documents ({}) without loading '
            'tighten-doc. Load it and run its closeout readback on those documents before finishing; '
            'the substance stays as the owning skill decided.'.format(names))


def proposed_next(payload):
    if (not isinstance(payload, dict) or payload.get('hook_event_name') != 'Stop'
            or payload.get('stop_hook_active') is not False):
        return None
    result = delivery_reminder(payload)
    try:
        note = doc_closeout_note(payload)
    except Exception:  # advisory: a failed document check never costs the reminder
        note = ''
    if not note:
        return result
    if not result:
        return {'decision': 'block', 'reason': note + ' Then end with the same proposed-next: line. '
                'This reminder supplies no new goal or authorization.'}
    return {'decision': 'block', 'reason': note + ' ' + result['reason']}


def delivery_reminder(payload):
    final = payload.get('last_assistant_message')
    if not isinstance(final, str) or not final.strip() or machine_artifact(final):
        return None
    values = handoff_values(final)
    actionable = handoff(final, actionable_only=True)
    if values and not actionable:
        if waits_on_user(values) or asks_permission(final):
            return DECISION_RECHECK
        if not announces_steps(final):
            return None
        # An announcement beside a status handoff still needs the work evidence
        # used below; a status-only explanation cannot create a delivery task.
    # A declared next action triggers a recheck, never inferred authorization.
    # Host stop_hook_active bounds this reminder to one stop attempt per turn.
    if actionable:
        return {'decision': 'block', 'reason': (
            'Delivery continuation reminder: a proposed-next: action is still declared. '
            'Recheck the active goal and current user scope before stopping. If that action is already '
            'authorized and runnable, execute it now instead of waiting for another continue message. '
            'For unrun, failed or inconclusive checks, continue available diagnosis, research, safe repair '
            'and retesting; a report alone does not complete implementation. Respect explicit stop, '
            'planning-only and status-only requests. ' + NOT_BLOCKERS +
            'If a user decision or missing authority/resource '
            'prevents action, report the concrete blocker; do not invent work or bypass a failed gate. '
            'This reminder supplies no new goal or authorization.')}
    path = payload.get('transcript_path')
    if not isinstance(path, str) or not path:
        return None
    cwd = payload.get('cwd')
    cwd = cwd if isinstance(cwd, str) else os.getcwd()
    try:
        summary = transcript(path, cwd)
    except TranscriptTruncated:
        summary = context_transcript(path, cwd)
        if not delivery_eligible(summary):
            if summary['edit_paths'] and (asks_permission(final) or announces_steps(final)):
                return DECISION_RECHECK
            # A complete recent context can establish eligibility, but cannot
            # disprove evidence in the omitted session prefix.
            raise
    if ((asks_permission(final) or announces_steps(final))
            and (delivery_eligible(summary) or summary['edit_paths'])):
        return DECISION_RECHECK
    if not delivery_eligible(summary):
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
    elif sys.argv[1] in ('proposed-next', 'extraction-overflow'):
        payload = {}
        try:
            raw = sys.stdin.read(2 * 1024 * 1024 + 1)
            if len(raw) > 2 * 1024 * 1024:
                raise ValueError('oversized input')
            payload = json.loads(raw)
            result = (extraction_overflow(payload) if sys.argv[1] == 'extraction-overflow'
                      else proposed_next(payload))
            if result:
                print(json.dumps(result))
        except TranscriptTruncated:
            result = stop_notice(payload, 'handoff-overflow',
                                 'Delivery handoff reminder unverified: transcript scan exceeded its bounded limit.')
            if result:
                print(json.dumps(result))
        except (OSError, ValueError, TypeError, IndexError, AttributeError):
            message = ('Skill workflow check incomplete: input or conversation history could not be verified. '
                       'This does not block your task.' if sys.argv[1] == 'extraction-overflow' else
                       'Delivery handoff reminder unavailable: input or transcript could not be verified.')
            print(json.dumps({'systemMessage': message}))
    return 0


if __name__ == '__main__':
    try:
        sys.exit(main())
    except (OSError, ValueError, TypeError, IndexError):
        sys.exit(1)
