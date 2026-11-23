#!/usr/bin/env python3
"""Antigravity hook bridge: run the plugin's Claude-protocol hooks on Antigravity.

Antigravity sends camelCase protojson on stdin and strictly parses stdout
(`decision`/`reason`, `injectSteps`, `{}`); the hook scripts in this directory
read Claude Code's payload (`tool_name`, `tool_input`, `transcript_path`) and
answer with `hookSpecificOutput`, `decision: "block"` or nothing. This bridge
owns both directions. Decisions stay with the scripts; the bridge only maps.

Failure policy: guards that protect edits, delegation and owner dispatch fail
closed, as in the OpenCode adapter; a merge guard that cannot run blocks every
command; reminders fail open. Every handler prints exactly one JSON object.
"""
import fcntl
import hashlib
import json
import os
from pathlib import Path
import re
import stat
import subprocess
import sys
import tempfile
import time

sys.dont_write_bytecode = True

PLUGIN_ROOT = Path(__file__).resolve().parents[1]
HOOKS_DIR = PLUGIN_ROOT / 'hooks'
SKILLS_DIR = PLUGIN_ROOT / 'skills'

# The handlers dispatch from these lists, and --bindings prints the inventory
# derived from them, so the inventory cannot claim a hook the bridge never runs.
# hooks/test_agy_bridge.py and the npm package test compare the inventory with
# every command hook in hooks/hooks.json, so a new hook cannot ship inactive here.
DISPATCH = {
    'SessionStart': ('session-start.sh',),
    'PreInvocation:first-of-turn': ('task-entry.sh', 'merge-authorization-prompt.sh'),
    'PreToolUse:edit': ('guard-edit-isolation.sh', 'owner-dispatch-guard.sh'),
    'PreToolUse:run_command': ('owner-dispatch-guard.sh', 'guard-merge-authorization.sh',
                               'guard-broad-local-test.sh', 'remind-unverified-cli-flag.sh',
                               'remind-untracked-background.sh', 'remind-review-covers-head.sh'),
    'PreToolUse:invoke_subagent': ('guard-delegation-owner.sh', 'subagent-start.sh'),
    'PostToolUse:run_command': ('remind-post-merge-cleanup.sh',),
    # headless-background-stop.sh is inert here: it acts only for a Claude Code sdk
    # entrypoint, which the bridge never passes on.
    'Stop': ('owner-dispatch-stop.sh', 'skill-extraction-gate-stop.sh', 'proposed-next-stop.sh',
             'headless-background-stop.sh'),
}
# A merge guard that cannot run blocks every command: shell text cannot be
# classified as non-landing reliably (quoting, encoding and indirection all hide
# a subcommand), so there is no denylist here. This is stricter than the OpenCode
# adapter, which blocks only landing-looking commands in that case.
FAIL_CLOSED = {'PreToolUse:edit': DISPATCH['PreToolUse:edit'],
               'PreToolUse:run_command': ('owner-dispatch-guard.sh', 'guard-merge-authorization.sh'),
               'PreToolUse:invoke_subagent': DISPATCH['PreToolUse:invoke_subagent']}
UNSUPPORTED = {'skill-context-compact.sh': 'unsupported:no-compaction-event'}
STOP_CAPS = {'owner-dispatch-stop.sh': 10, 'skill-extraction-gate-stop.sh': 15}


def bindings():
    inventory = dict(UNSUPPORTED)
    for event, scripts in DISPATCH.items():
        for script in scripts:
            inventory.setdefault(script, [])
            inventory[script].append(event)
    return {k: v if isinstance(v, str) else ','.join(v) for k, v in inventory.items()}

EDIT_TOOLS = {
    'edit_file': 'Edit', 'replace_file_content': 'Edit', 'multi_replace_file_content': 'Edit',
    'apply_patch': 'Edit', 'delete_file': 'Edit',
    'write_file': 'Write', 'write_to_file': 'Write', 'create_file': 'Write',
    'notebook_edit': 'NotebookEdit',
}
PATH_KEYS = {'path', 'targetfile', 'target_file', 'absolutepath', 'absolute_path', 'filepath',
             'file_path', 'notebookpath', 'notebook_path'}
PATCH_PATH_RE = re.compile(r'^\*\*\* (?:(?:Add|Update|Delete) File|Move to): (.+?)\s*$', re.M)
SHOWING_RE = re.compile(r'^Showing lines (\d+)-(\d+) of (\d+)\s*$', re.M)
# A read past the byte limit: offsets index the formatted `N: line` stream of lines A-B.
PARTIAL_RE = re.compile(r'^Partial read \(lines (\d{1,9})-(\d{1,9}) of (\d{1,9})\)\. Showing bytes '
                        r'(\d{1,9})-(\d{1,9}) of (\d{1,9}) in this line range\b[^\n]*$', re.M)
NUMBERED_RE = re.compile(r'(\d+): ?(.*)\Z', re.S)
SESSION_RE = re.compile(r'[A-Za-z0-9_-]{1,128}\Z')
HANDLER_BUDGET = {'SessionStart': 12, 'PreInvocation': 17, 'PreToolUse': 72,
                  'PostToolUse': 12, 'Stop': 42}
# Each budget sits a few seconds under the event's timeout in the root hooks.json.
MAX_TRANSCRIPT_BYTES = 32 * 1024 * 1024
MAX_SKILL_BYTES = 256 * 1024
MAX_NOTE_BYTES = 8 * 1024
SHADOW_TTL = 24 * 3600


class BridgeError(Exception):
    pass


def digest(text):
    return hashlib.sha256(text.encode('utf-8', 'surrogatepass')).hexdigest()


def state_dir():
    base = Path(os.environ.get('TMPDIR') or tempfile.gettempdir())
    target = base / f'ccl-skills-agy-{os.getuid()}'
    try:
        os.mkdir(target, 0o700)
    except FileExistsError:
        pass
    info = os.lstat(target)
    if not stat.S_ISDIR(info.st_mode) or info.st_uid != os.getuid():
        raise BridgeError(f'unsafe bridge state directory: {target}')
    if info.st_mode & 0o077:
        os.chmod(target, 0o700)
    return target


def conversation(agy):
    value = agy.get('conversationId')
    raw = value if isinstance(value, str) and value else f'pid-{os.getppid()}'
    session = raw if SESSION_RE.match(raw) else digest(raw)
    return session, digest(raw)


def resolve_cwd(agy):
    cwd = agy.get('cwd')
    if isinstance(cwd, str) and os.path.isabs(cwd) and os.path.isdir(cwd):
        return cwd
    # Without cwd, a workspace root is a usable base only when it is unambiguous.
    roots = agy.get('workspacePaths')
    if (isinstance(roots, list) and len(roots) == 1 and isinstance(roots[0], str)
            and os.path.isabs(roots[0]) and os.path.isdir(roots[0])):
        return roots[0]
    return None


def unwrap(value):
    """Antigravity transcripts may carry arguments as JSON-encoded strings."""
    if isinstance(value, str) and len(value) >= 2 and value[0] == '"' and value[-1] == '"':
        try:
            parsed = json.loads(value)
            if isinstance(parsed, str):
                return parsed
        except ValueError:
            pass
    return value


def tool_args(call):
    args = call.get('args') if isinstance(call, dict) else None
    return {k: unwrap(v) for k, v in args.items()} if isinstance(args, dict) else {}


def absolute(path, cwd):
    # No lexical normalisation: `link/../x` must reach the guard as written, so the
    # guard resolves it through the filesystem the way the host's write will.
    path = os.path.expanduser(path)
    return path if os.path.isabs(path) else os.path.join(cwd, path)


def edit_paths(args, cwd, patch=False):
    """Every target the call names; [] means unknown. A relative target needs a known cwd.

    Patch headers are read only from an apply_patch call, never from file contents.
    """
    raw = [v.strip() for k, v in args.items() if k.lower() in PATH_KEYS and isinstance(v, str) and v.strip()]
    if patch:
        raw += [m.group(1) for v in args.values() if isinstance(v, str) for m in PATCH_PATH_RE.finditer(v)]
    paths = []
    for value in raw:
        value = os.path.expanduser(value)
        if not os.path.isabs(value) and not cwd:
            return []
        paths.append(absolute(value, cwd or '/'))
    return list(dict.fromkeys(paths))


def command_of(args):
    for key in ('CommandLine', 'command', 'Command', 'cmd'):
        if isinstance(args.get(key), str):
            return args[key]
    return None


def command_cwd(args, cwd):
    for key in ('Cwd', 'cwd', 'WorkingDirectory'):
        value = args.get(key)
        if isinstance(value, str) and value and (os.path.isabs(value) or cwd):
            path = absolute(value, cwd or '/')
            if os.path.isdir(path):
                return path
    return cwd


def claude_calls(name, args, cwd):
    """Map one Antigravity tool call to Claude tool_use (name, input) pairs."""
    if name in EDIT_TOOLS:
        tool = EDIT_TOOLS[name]
        return [(tool, {'file_path': p, **({'notebook_path': p} if tool == 'NotebookEdit' else {})})
                for p in edit_paths(args, cwd, patch=name == 'apply_patch')]
    if name == 'run_command':
        return [('Bash', {'command': command_of(args) or ''})]
    if name == 'invoke_subagent':
        return [('Task', {'prompt': str(args.get('Prompt') or ''),
                          'subagent_type': str(args.get('TypeName') or ''),
                          'description': str(args.get('Role') or '')})]
    if name in ('read_file', 'view_file'):
        paths = edit_paths(args, cwd)
        return [('Read', {'file_path': paths[0]})] if paths else []
    return []


# --- transcript -----------------------------------------------------------

def read_bounded(path):
    descriptor = os.open(path, os.O_RDONLY | os.O_NONBLOCK)
    with os.fdopen(descriptor, 'rb') as stream:
        info = os.fstat(stream.fileno())
        if not stat.S_ISREG(info.st_mode):
            raise BridgeError('transcript is not a regular file')
        skip = info.st_size > MAX_TRANSCRIPT_BYTES
        if skip:
            stream.seek(info.st_size - MAX_TRANSCRIPT_BYTES)
        data = stream.read(MAX_TRANSCRIPT_BYTES)
    if skip:
        data = data.split(b'\n', 1)[1] if b'\n' in data else b''
    return data.decode('utf-8', 'replace')


def transcript_steps(agy):
    raw = agy.get('transcriptPath')
    if not isinstance(raw, str) or not raw:
        return []
    path = Path(os.path.expanduser(raw))
    if not path.is_absolute():
        return []
    for candidate in (path.with_name('transcript_full.jsonl'), path):
        try:
            text = read_bounded(candidate)
        except (OSError, BridgeError):
            continue
        steps = []
        for line in text.splitlines():
            try:
                step = json.loads(line)
            except ValueError:
                continue
            if isinstance(step, dict):
                steps.append(step)
        return steps
    return []


def read_regular(path):
    descriptor = os.open(path, os.O_RDONLY | os.O_NONBLOCK)
    with os.fdopen(descriptor, 'rb') as stream:
        info = os.fstat(stream.fileno())
        if not stat.S_ISREG(info.st_mode) or info.st_size > MAX_SKILL_BYTES:
            raise BridgeError('not a bounded regular file')
        return stream.read(MAX_SKILL_BYTES + 1)


def bundled_skill(path):
    """(slug, lines) of the bundled skill when `path` is a byte-identical copy of it."""
    path = Path(path)
    if path.name != 'SKILL.md' or path.parent.parent.name != 'skills':
        return None
    slug = path.parent.name
    canonical = SKILLS_DIR / slug / 'SKILL.md'
    try:
        raw = read_regular(canonical)
        if os.path.realpath(path) != os.path.realpath(canonical) and read_regular(path) != raw:
            return None
        text = raw.decode('utf-8')
    except (OSError, UnicodeError, BridgeError):
        return None
    frontmatter = re.match(r'\A---\r?\n(.*?)\r?\n---\r?\n', text, re.S)
    if not frontmatter or not re.search(r'^name:\s*' + re.escape(slug) + r'\s*$', frontmatter.group(1), re.M):
        return None
    lines = text.split('\n')
    if lines and lines[-1] == '':
        lines.pop()
    return slug, [line.rstrip('\r') for line in lines]


def merge_spans(spans):
    merged = []
    for start, end in sorted(spans):
        if merged and start <= merged[-1][1]:
            merged[-1] = (merged[-1][0], max(merged[-1][1], end))
        else:
            merged.append((start, end))
    return merged


def partial_lines(content, header, lines, spans):
    """Lines that verified byte chunks of one line range show whole.

    Each chunk must equal the canonical formatted stream at the offsets its header
    names, so a cut, shifted, tampered or renumbered chunk adds nothing. `spans`
    keeps the verified intervals per skill across reads, so a line cut at a chunk
    boundary counts once any later chunk shows the rest of it. The canonical stream
    is built once per skill; a range is a window into it.
    """
    first, last, total, start, end, size = (int(value) for value in header.groups())
    if total != len(lines) or not 1 <= first <= last <= total:
        return set()
    if content[header.end():header.end() + 1] != '\n':
        return set()
    canonical = spans.get('canonical')
    if canonical is None:
        rows = [f'{n}: {line}'.encode('utf-8') for n, line in enumerate(lines, start=1)]
        offsets, position = [], 0
        for row in rows:
            offsets.append(position)
            position += len(row) + 1
        canonical = spans['canonical'] = (b'\n'.join(rows), offsets, [len(row) for row in rows])
    stream, offsets, lengths = canonical
    base = offsets[first - 1]
    if size != offsets[last - 1] + lengths[last - 1] - base or not 0 <= start < end <= size:
        return set()
    body = content[header.end() + 1:].encode('utf-8', 'surrogatepass')
    lead = start
    while lead > 0 and stream[base + lead] & 0xC0 == 0x80:
        lead -= 1
    if lead != start and len(body) == end - lead:
        # An offset inside a character makes the host start at that character's
        # first byte but still report the requested offset.
        start = lead
    if len(body) != end - start or memoryview(stream)[base + start:base + end] != body:
        return set()
    # Intervals live in whole-skill coordinates, so reads of different line ranges
    # combine. A range read to its end also counts the separator after its last row:
    # the header proves the range ended there, though no body carries that byte.
    stop = base + end + (end == size and last < total)
    merged = spans['verified'] = merge_spans(spans.get('verified', []) + [(base + start, stop)])
    # A row counts with its separator, so complete rows imply a complete stream.
    shown, index = set(), 0
    for number in range(1, total + 1):
        position = offsets[number - 1]
        needed = position + lengths[number - 1] + (number < total)
        while index < len(merged) and merged[index][1] < needed:
            index += 1
        if index < len(merged) and merged[index][0] <= position:
            shown.add(number)
    return shown


def covered_lines(content, lines, spans=None):
    """Line numbers a read_file result shows verbatim; empty when it does not match.

    `spans` carries verified byte intervals between results; without it a byte-limited
    `Partial read` result counts for nothing.
    """
    if not isinstance(content, str):
        return set()
    header = SHOWING_RE.search(content)
    partial = PARTIAL_RE.search(content)
    # The first header is the tool's; a later match is file text inside the body.
    if partial and (not header or partial.start() < header.start()):
        return partial_lines(content, partial, lines, spans) if spans is not None else set()
    if not header:
        return set()
    first, last, total = (int(value) for value in header.groups())
    if total != len(lines) or not 1 <= first <= last <= total:
        return set()
    seen = {}
    for row in content[header.end():].split('\n'):
        match = NUMBERED_RE.match(row)
        if match:
            seen.setdefault(int(match.group(1)), match.group(2).rstrip('\r'))
    shown = set(range(first, last + 1))
    if any(seen.get(number) != lines[number - 1] for number in shown):
        return set()
    return shown


def shadow_events(steps, cwd):
    """Claude-shaped transcript events plus (turn_id, last assistant prose).

    User prompt text and tool output are not copied; the hooks need structure.
    """
    events, turn_id, last_prose, coverage, loaded, chunks = [], None, None, {}, set(), {}
    index = 0
    while index < len(steps):
        step = steps[index]
        kind, number = step.get('type'), step.get('step_index', index)
        index += 1
        if kind == 'USER_INPUT' and step.get('source') == 'USER_EXPLICIT':
            turn_id, last_prose = f'turn-{number}', None
            events.append({'type': 'user', 'uuid': turn_id, 'promptId': turn_id,
                           'message': {'role': 'user', 'content': [{'type': 'text', 'text': ''}]}})
            continue
        if kind != 'PLANNER_RESPONSE':
            continue
        calls = [c for c in step.get('tool_calls') or [] if isinstance(c, dict)]
        prose = step.get('content') if isinstance(step.get('content'), str) else ''
        if not calls:
            if prose.strip():
                last_prose = prose
                events.append({'type': 'assistant', 'message': {
                    'role': 'assistant', 'content': [{'type': 'text', 'text': prose}]}})
            continue
        results = []
        while index < len(steps) and steps[index].get('type') not in ('PLANNER_RESPONSE', 'USER_INPUT'):
            if steps[index].get('type') == 'GENERIC':
                results.append(steps[index])
            index += 1
        # Results carry no call id; pair by position only when the counts agree.
        paired = len(results) == len(calls)
        for position, call in enumerate(calls):
            name, args = str(call.get('name') or ''), tool_args(call)
            result = results[position] if paired else None
            failed = result is None or result.get('status') != 'DONE' or bool(result.get('error'))
            base = str(call.get('id') or f'call-{number}-{position}')
            for offset, (tool, tool_input) in enumerate(claude_calls(name, args, cwd)):
                call_id = base if offset == 0 else f'{base}-{offset}'
                events.append({'type': 'assistant', 'message': {'role': 'assistant', 'content': [
                    {'type': 'tool_use', 'id': call_id, 'name': tool, 'input': tool_input}]}})
                if paired:
                    events.append({'type': 'user', 'message': {'role': 'user', 'content': [
                        {'type': 'tool_result', 'tool_use_id': call_id, 'content': '',
                         'is_error': failed}]}})
            if name not in ('read_file', 'view_file') or failed:
                continue
            target = edit_paths(args, cwd)
            skill = bundled_skill(target[0]) if target else None
            if not skill or skill[0] in loaded:
                continue
            slug, lines = skill
            seen = coverage.setdefault(slug, set())
            seen |= covered_lines(result.get('content'), lines, chunks.setdefault(slug, {}))
            if len(seen) == len(lines):
                loaded.add(slug)
                skill_id = f'skill-{number}-{position}'
                events.append({'type': 'assistant', 'message': {'role': 'assistant', 'content': [
                    {'type': 'tool_use', 'id': skill_id, 'name': 'Skill',
                     'input': {'skill': f'ccl-skills:{slug}'}}]}})
                events.append({'type': 'user', 'message': {'role': 'user', 'content': [
                    {'type': 'tool_result', 'tool_use_id': skill_id, 'content': 'loaded',
                     'is_error': False}]}})
    return events, turn_id, last_prose


# The shadow keeps one inode for the conversation's lifetime, as a host transcript
# does: skill-loading.py keys its once-per-context checkpoint on (st_dev, st_ino).
# Its content lives only while an event runs; between events the file is empty.
SHADOW_NAME_RE = re.compile(r'[0-9a-f]{64}\.jsonl\Z')
LEGACY_TEMP_RE = re.compile(r'[0-9a-f]{64}\.[1-9][0-9]*\.tmp\Z')
WRITE_FLAGS = os.O_WRONLY | os.O_NOFOLLOW | os.O_NONBLOCK


def safe_shadow(descriptor):
    """Raise unless the descriptor is a private regular file with a single name."""
    info = os.fstat(descriptor)
    if not stat.S_ISREG(info.st_mode) or info.st_uid != os.getuid() or info.st_nlink != 1:
        raise BridgeError('unsafe shadow transcript')
    if stat.S_IMODE(info.st_mode) != 0o600:
        os.fchmod(descriptor, 0o600)
    return info


def checked_shadow(descriptor):
    """Accept a newly opened descriptor only if it is safe; never write through a link."""
    try:
        safe_shadow(descriptor)
    except BaseException:
        os.close(descriptor)
        raise
    return descriptor


OPEN_SHADOWS = {}  # key -> the descriptor this event validated and writes through


def write_shadow(key, events, extra=None):
    directory = state_dir()
    target = directory / f'{key}.jsonl'
    descriptor, created = OPEN_SHADOWS.get(key), False
    if descriptor is None:
        try:
            descriptor, created = os.open(target, WRITE_FLAGS | os.O_CREAT | os.O_EXCL, 0o600), True
        except FileExistsError:
            descriptor = os.open(target, WRITE_FLAGS)
        OPEN_SHADOWS[key] = checked_shadow(descriptor)
    else:
        # A later write of the same event must still name the file the hooks will read.
        held, named = safe_shadow(descriptor), os.lstat(target)
        if (held.st_dev, held.st_ino) != (named.st_dev, named.st_ino):
            raise BridgeError('shadow transcript was replaced during the event')
    os.lseek(descriptor, 0, os.SEEK_SET)
    written = 0
    for event in events + ([extra] if extra else []):
        view = memoryview((json.dumps(event) + '\n').encode('utf-8'))
        written += len(view)
        while view:
            view = view[os.write(descriptor, view):]
    os.ftruncate(descriptor, written)
    if created:
        sweep_stale(directory)
    return str(target)


def clear_shadow(key):
    """Empty the shadow at event end through the descriptor the event wrote, so a
    rename or replacement of the name during the event cannot keep content around.
    An event that wrote nothing touches nothing; the sweep empties what a killed
    event left behind."""
    descriptor = OPEN_SHADOWS.pop(key, None)
    if descriptor is None:
        return
    try:
        os.ftruncate(descriptor, 0)
    finally:
        os.close(descriptor)


def sweep_stale(directory, budget=1.0):
    """Empty shadows an interrupted event left full and drop the old scheme's temp files.

    Runs when a conversation's shadow is first created. A shadow is emptied, never
    removed, so a paused conversation keeps its identity. Either kind of file is
    touched only under its conversation's run lock, so a running event is skipped.
    Failures never affect the event.
    """
    started, cutoff = time.monotonic(), time.time() - SHADOW_TTL
    try:
        with os.scandir(directory) as entries:
            for entry in entries:
                if time.monotonic() - started > budget:
                    return
                try:
                    info = entry.stat(follow_symlinks=False)
                    if (not stat.S_ISREG(info.st_mode) or info.st_uid != os.getuid()
                            or info.st_mtime >= cutoff):
                        continue
                    if LEGACY_TEMP_RE.match(entry.name):
                        under_run_lock(directory, entry.name.split('.', 1)[0],
                                       lambda: remove_if_stale(entry.path, cutoff))
                    elif SHADOW_NAME_RE.match(entry.name) and info.st_size:
                        key = entry.name[:-len('.jsonl')]
                        under_run_lock(directory, key, lambda: empty_if_stale(directory / entry.name, cutoff))
                except (OSError, BridgeError):
                    continue  # another conversation's unsafe file is its own event's problem
    except OSError:
        return


def under_run_lock(directory, key, action):
    # Every event takes this lock before writing; without it the age check races a
    # starting event, so a file whose conversation has no lock file is left alone.
    lock = os.open(directory / f'{key}.run.lock', WRITE_FLAGS)
    try:
        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        action()
    finally:
        os.close(lock)


def remove_if_stale(path, cutoff):
    info = os.lstat(path)
    if stat.S_ISREG(info.st_mode) and info.st_uid == os.getuid() and info.st_mtime < cutoff:
        os.unlink(path)


def empty_if_stale(path, cutoff):
    descriptor = checked_shadow(os.open(path, WRITE_FLAGS))
    try:
        if os.fstat(descriptor).st_mtime < cutoff:
            os.ftruncate(descriptor, 0)
    finally:
        os.close(descriptor)


def context(agy, extra=None):
    cwd = resolve_cwd(agy)
    session, key = conversation(agy)
    events, turn_id, prose = shadow_events(transcript_steps(agy), cwd)
    return {'cwd': cwd or os.getcwd(), 'known_cwd': cwd, 'session': session, 'key': key, 'turn_id': turn_id, 'prose': prose,
            'events': events, 'transcript': write_shadow(key, events, extra)}


# --- running hooks --------------------------------------------------------

class Deadline:
    def __init__(self, seconds):
        self.end = time.monotonic() + seconds

    def left(self, cap):
        return max(0.0, min(cap, self.end - time.monotonic()))


def run_hook(script, payload, cwd, deadline, cap=10):
    path = HOOKS_DIR / script
    timeout = deadline.left(cap)
    if not path.is_file() or path.is_symlink():
        return 'missing', {}
    if timeout < 0.5:
        return 'error', {}
    env = {k: v for k, v in os.environ.items() if k not in ('CLAUDE_CODE_ENTRYPOINT', 'CLAUDECODE')}
    env['CLAUDE_PLUGIN_ROOT'] = str(PLUGIN_ROOT)
    try:
        proc = subprocess.run(['bash', str(path)], cwd=cwd if os.path.isdir(cwd) else str(PLUGIN_ROOT),
                              env=env, input=json.dumps(payload), capture_output=True, text=True,
                              timeout=timeout)
    except (OSError, subprocess.SubprocessError):
        return 'error', {}
    if proc.returncode != 0:
        return 'error', {}
    out = proc.stdout.strip()
    if not out:
        return 'ok', {}
    try:
        parsed = json.loads(out)
    except ValueError:
        return 'error', {}
    return ('ok', parsed) if isinstance(parsed, dict) else ('error', {})


def specific(output, key):
    value = (output.get('hookSpecificOutput') or {}).get(key)
    return value.strip() if isinstance(value, str) else ''


def system_message(output):
    value = output.get('systemMessage')
    return value.strip() if isinstance(value, str) else ''


def inject(texts):
    texts = [t for t in texts if t]
    return {'injectSteps': [{'systemMessage': {'systemMessage': '\n\n'.join(texts)}}]} if texts else {}


def with_lock(key, action):
    descriptor = os.open(state_dir() / f'{key}.lock', os.O_WRONLY | os.O_CREAT, 0o600)
    try:
        fcntl.flock(descriptor, fcntl.LOCK_EX)
        return action()
    finally:
        os.close(descriptor)


def write_private(path, text):
    descriptor = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
    with os.fdopen(descriptor, 'w', encoding='utf-8') as stream:
        stream.write(text)


def read_queue(path):
    try:
        queued = json.loads(path.read_text(encoding='utf-8'))
    except (OSError, ValueError):
        return []
    return [n for n in queued if isinstance(n, str) and n.strip()] if isinstance(queued, list) else []


def push_notes(key, notes):
    notes = [n[:MAX_NOTE_BYTES] for n in notes if n]
    if not notes:
        return
    path = state_dir() / f'{key}.notes.json'

    def action():
        queued = read_queue(path)
        queued.extend(n for n in notes if n not in queued)
        write_private(path, json.dumps(queued[-8:]))
    with_lock(key, action)


def pop_notes(key):
    path = state_dir() / f'{key}.notes.json'

    def action():
        queued = read_queue(path)
        path.unlink(missing_ok=True)
        return queued
    return with_lock(key, action)


def payload(ctx, event, **extra):
    data = {'hook_event_name': event, 'session_id': ctx['session'], 'cwd': ctx['cwd'],
            'transcript_path': ctx['transcript']}
    data.update(extra)
    return data


# --- handlers -------------------------------------------------------------

def session_start(agy, deadline):
    ctx = context(agy)
    texts = []
    for script in DISPATCH['SessionStart']:
        _, out = run_hook(script, payload(ctx, 'SessionStart', source='startup'), ctx['cwd'], deadline, 5)
        texts.append(specific(out, 'additionalContext'))
    return inject(texts)


def is_int(value):
    return isinstance(value, int) and not isinstance(value, bool)


def resolve_turn_key(agy, ctx):
    """One key per user turn across multi-step tool loops (invocationNum 0 -> 1, 2, ...)."""
    prompt = agy.get('lastUserInput')
    if not isinstance(prompt, str) or not prompt.strip():
        return None, ''
    inv = agy.get('invocationNum')
    steps = agy.get('initialNumSteps')
    turn_id = ctx['turn_id']
    active_file = state_dir() / f"{ctx['key']}.active.turn"
    active = {}
    try:
        parsed = json.loads(active_file.read_text(encoding='utf-8'))
        if isinstance(parsed, dict):
            active = parsed
    except (OSError, ValueError):
        pass
    raw_seq = active.get('seq')
    seq = raw_seq if is_int(raw_seq) and raw_seq >= 0 else 0
    prev_turn = active.get('turn_id')
    stale_turn = active.get('stale_turn_id')
    effective_turn = None if (turn_id and turn_id == stale_turn) else turn_id
    active_key = active.get('key')
    if is_int(inv) and inv > 0 and isinstance(active_key, str) and active_key:
        if not (prev_turn and effective_turn and prev_turn != effective_turn):
            if prev_turn is None and effective_turn:
                write_private(active_file, json.dumps({
                    'seq': seq, 'turn_id': effective_turn,
                    'stale_turn_id': stale_turn, 'key': active_key}))
            return active_key, prompt
    new_stale = stale_turn if (turn_id and turn_id == stale_turn) else None
    if is_int(inv) and inv == 0:
        seq += 1
        if turn_id and turn_id in (prev_turn, stale_turn):
            new_stale = turn_id
            effective_turn = None
        marker = f'seq:{seq}'
    elif is_int(inv) and inv > 0:
        seq += 1
        marker = f'seq:{seq}'
    elif effective_turn:
        marker = f'turn:{effective_turn}:steps:{steps}' if is_int(steps) else f'turn:{effective_turn}'
    else:
        marker = f'steps:{steps}' if is_int(steps) else 'noturn'
    key = digest(f'{marker}\0{prompt}')
    write_private(active_file, json.dumps({
        'seq': seq, 'turn_id': effective_turn, 'stale_turn_id': new_stale, 'key': key}))
    return key, prompt


def pre_invocation(agy, deadline):
    ctx = context(agy)
    texts = []
    key, prompt = resolve_turn_key(agy, ctx)
    for script in DISPATCH['PreInvocation:first-of-turn']:
        marker = state_dir() / f"{ctx['key']}.{script}.turn"
        try:
            if not key or marker.read_text(encoding='utf-8').strip() == key:
                continue
        except OSError:
            pass
        status, out = run_hook(script, payload(ctx, 'UserPromptSubmit', prompt=prompt), ctx['cwd'], deadline, 5)
        if status == 'ok':
            write_private(marker, key)  # recorded only after delivery, so a failed hook retries
            texts.extend([specific(out, 'additionalContext'), system_message(out)])
    texts.extend(pop_notes(ctx['key']))
    return inject(texts)


def deny(reason):
    return {'decision': 'deny', 'reason': reason}


def evaluate(scripts, data, cwd, deadline, closed=()):
    """Run scripts in hooks.json order; deny beats ask beats allow."""
    asked, notes, reasons = None, [], []
    for script in scripts:
        status, out = run_hook(script, data, cwd, deadline)
        if status != 'ok':
            if script in closed:
                return deny(f'ccl-skills: {script} could not run, so this operation is blocked. '
                            'Check that bash, jq and python3 are available, then retry.'), notes, reasons
            continue
        decision = (out.get('hookSpecificOutput') or {}).get('permissionDecision')
        reason = specific(out, 'permissionDecisionReason') or system_message(out)
        if decision == 'deny':
            return deny(reason or f'Blocked by ccl-skills {script}.'), notes, reasons
        if decision == 'ask':
            asked = asked or {'decision': 'ask', 'reason': reason or f'ccl-skills {script} asks for confirmation.'}
        elif reason:
            reasons.append(reason)
        notes.append(specific(out, 'additionalContext'))
    return asked, notes, reasons


def pre_tool_use(agy, deadline):
    call = agy.get('toolCall')
    if not isinstance(call, dict) or not isinstance(call.get('name'), str) or not call['name']:
        return deny('ccl-skills could not decode this tool call, so it is blocked.')
    name, args = call['name'], tool_args(call)
    if name not in EDIT_TOOLS and name not in ('run_command', 'invoke_subagent'):
        return {'decision': 'allow'}
    ctx = context(agy)
    if name in EDIT_TOOLS:
        targets = edit_paths(args, ctx['known_cwd'], patch=name == 'apply_patch')
        if not targets:
            return deny(f'ccl-skills could not determine which file {name} changes, so the '
                        'edit-isolation guard cannot check it. Name the target file explicitly.')
        tool = EDIT_TOOLS[name]
        asked = None
        for target in targets:
            tool_input = {'file_path': target, **({'notebook_path': target} if tool == 'NotebookEdit' else {})}
            pending = {'type': 'assistant', 'message': {'role': 'assistant', 'content': [
                {'type': 'tool_use', 'id': str(call.get('id') or 'call-current'), 'name': tool,
                 'input': tool_input}]}}
            ctx['transcript'] = write_shadow(ctx['key'], ctx['events'], pending)
            data = payload(ctx, 'PreToolUse', tool_name=tool, tool_input=tool_input)
            verdict, notes, _ = evaluate(DISPATCH['PreToolUse:edit'], data, ctx['cwd'], deadline,
                                         FAIL_CLOSED['PreToolUse:edit'])
            push_notes(ctx['key'], notes)
            if verdict and verdict['decision'] == 'deny':
                return verdict
            asked = asked or verdict  # an ask waits until every target was checked for a deny
        return asked or {'decision': 'allow'}
    if name == 'run_command':
        command = command_of(args)
        if not isinstance(command, str) or not command.strip():
            return deny('ccl-skills could not read the command of this run_command call, so it is blocked.')
        data = payload(ctx, 'PreToolUse', tool_name='Bash', tool_input={'command': command})
        data['cwd'] = command_cwd(args, ctx['known_cwd'])
        verdict, notes, reasons = evaluate(DISPATCH['PreToolUse:run_command'], data, data['cwd'], deadline,
                                           FAIL_CLOSED['PreToolUse:run_command'])
        push_notes(ctx['key'], notes)
        if verdict:
            return verdict
        return {'decision': 'allow', **({'reason': '\n\n'.join(reasons)} if reasons else {})}
    tool_input = claude_calls(name, args, ctx['known_cwd'])[0][1]
    data = payload(ctx, 'PreToolUse', tool_name='Task', tool_input=tool_input)
    verdict, notes, reasons = evaluate(DISPATCH['PreToolUse:invoke_subagent'], data, ctx['cwd'], deadline,
                                       FAIL_CLOSED['PreToolUse:invoke_subagent'])
    if verdict:
        return verdict
    prefix = '\n\n'.join(r for r in reasons + notes if r)
    if not prefix:
        return {'decision': 'allow'}
    original = args.get('Prompt') if isinstance(args.get('Prompt'), str) else ''
    return {'decision': 'allow', 'overwrite': {'Prompt': f'{prefix}\n\n{original}'.strip()}}


def post_tool_use(agy, deadline):
    call = agy.get('toolCall') if isinstance(agy.get('toolCall'), dict) else {}
    if call.get('name') != 'run_command':
        return {}
    args = tool_args(call)
    ctx = context(agy)
    error = agy.get('error') if isinstance(agy.get('error'), str) else ''
    data = payload(ctx, 'PostToolUse', tool_name='Bash', tool_input={'command': command_of(args) or ''},
                   tool_response={'is_error': bool(error), 'output': error})
    data['cwd'] = command_cwd(args, ctx['known_cwd'])
    texts = []
    for script in DISPATCH['PostToolUse:run_command']:
        _, out = run_hook(script, data, data['cwd'], deadline)
        texts.append(specific(out, 'additionalContext'))
    push_notes(ctx['key'], texts)
    return {}


def stop(agy, deadline):
    if agy.get('continuationActive') is True:
        return {'decision': 'allow'}
    reason = agy.get('terminationReason')
    if isinstance(reason, str) and reason and reason != 'NO_TOOL_CALL':
        return {'decision': 'allow'}
    ctx = context(agy)
    data = payload(ctx, 'Stop', stop_hook_active=False, last_assistant_message=ctx['prose'])
    if ctx['turn_id']:
        data['turn_id'] = ctx['turn_id']
    reasons = []
    for script in DISPATCH['Stop']:
        status, out = run_hook(script, data, ctx['cwd'], deadline, STOP_CAPS.get(script, 5))
        text = out.get('reason')
        if status == 'ok' and out.get('decision') == 'block' and isinstance(text, str) and text.strip():
            reasons.append(text.strip())
    return {'decision': 'continue', 'reason': '\n\n'.join(reasons)} if reasons else {'decision': 'allow'}


HANDLERS = {'SessionStart': session_start, 'PreInvocation': pre_invocation,
            'PreToolUse': pre_tool_use, 'PostToolUse': post_tool_use, 'Stop': stop}


def fallback(event):
    if event == 'PreToolUse':
        return deny('ccl-skills bridge failed while checking this tool call, so it is blocked. '
                    'Retry; if it persists, reinstall the plugin.')
    if event == 'Stop':
        return {'decision': 'allow'}
    return {}


def handle(event, agy):
    """Run one event under the conversation's run lock; the shadow's content lives only for that run.

    The deadline starts before the lock is requested and the wait is bounded, so an
    event queued behind a slow one still answers before the host's timeout.
    """
    deadline = Deadline(HANDLER_BUDGET[event])
    _, key = conversation(agy)
    descriptor = os.open(state_dir() / f'{key}.run.lock', os.O_WRONLY | os.O_CREAT, 0o600)
    try:
        while True:
            try:
                fcntl.flock(descriptor, fcntl.LOCK_EX | fcntl.LOCK_NB)
                break
            except BlockingIOError:
                if deadline.left(10**6) < 2:
                    raise BridgeError('timed out waiting for another hook event of this conversation')
                time.sleep(0.05)
        try:
            return HANDLERS[event](agy, deadline)
        finally:
            clear_shadow(key)
    finally:
        os.close(descriptor)


def main(argv):
    if argv[1:] == ['--bindings']:
        print(json.dumps(bindings(), sort_keys=True))
        return 0
    event = argv[1] if len(argv) > 1 else ''
    try:
        agy = json.loads(sys.stdin.read() or '{}')
        if not isinstance(agy, dict):
            raise BridgeError('payload is not an object')
        event = event or str(agy.get('hookEventName') or '')
        result = handle(event, agy) if event in HANDLERS else {}
    except Exception:  # noqa: BLE001 - every failure maps to the event's safe answer
        result = fallback(event)
    sys.stdout.write(json.dumps(result) + '\n')
    return 0


if __name__ == '__main__':
    raise SystemExit(main(sys.argv))
