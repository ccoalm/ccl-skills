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
MAX_CACHE_BYTES = 4 * 1024 * 1024
CACHE_BLOCK_BYTES = 1024 * 1024
SHADOW_WRITE_CHUNK = 65536
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


SKILL_CACHE = {}  # slug -> [stat_sig, canonical_real, raw_bytes, lines, canonical_stream_or_None]


def build_canonical_stream(lines):
    rows = [f'{n}: {line}'.encode('utf-8') for n, line in enumerate(lines, start=1)]
    offsets, position = [], 0
    for row in rows:
        offsets.append(position)
        position += len(row) + 1
    return b'\n'.join(rows), offsets, [len(row) for row in rows]


def bundled_skill_entry(slug):
    canonical = SKILLS_DIR / slug / 'SKILL.md'
    try:
        info = os.stat(canonical)
        if not stat.S_ISREG(info.st_mode) or info.st_size > MAX_SKILL_BYTES:
            return None
        sig = (info.st_dev, info.st_ino, info.st_size, info.st_mtime_ns)
        cached = SKILL_CACHE.get(slug)
        if cached is not None and cached[0] == sig and len(cached[2]) == info.st_size:
            return cached
        raw = read_regular(canonical)
        post = os.stat(canonical)
        if not stat.S_ISREG(post.st_mode) or len(raw) != post.st_size:
            return None
        sig = (post.st_dev, post.st_ino, post.st_size, post.st_mtime_ns)
        text = raw.decode('utf-8')
        canonical_real = os.path.realpath(canonical)
    except (OSError, UnicodeError, BridgeError):
        return None
    frontmatter = re.match(r'\A---\r?\n(.*?)\r?\n---\r?\n', text, re.S)
    if not frontmatter or not re.search(r'^name:\s*' + re.escape(slug) + r'\s*$', frontmatter.group(1), re.M):
        return None
    lines = text.split('\n')
    if lines and lines[-1] == '':
        lines.pop()
    entry = [sig, canonical_real, raw, [line.rstrip('\r') for line in lines], None]
    SKILL_CACHE[slug] = entry
    return entry


def bundled_skill(path):
    """(slug, lines) of the bundled skill when `path` is a byte-identical copy of it."""
    path = Path(path)
    if path.name != 'SKILL.md' or path.parent.parent.name != 'skills':
        return None
    slug = path.parent.name
    entry = bundled_skill_entry(slug)
    if entry is None:
        return None
    _, canonical_real, raw, lines, _ = entry
    try:
        if os.path.realpath(path) != canonical_real and read_regular(path) != raw:
            return None
    except (OSError, BridgeError):
        return None
    return slug, lines


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
        canonical = spans['canonical'] = build_canonical_stream(lines)
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
            skill_chunks = chunks.setdefault(slug, {})
            cached_entry = SKILL_CACHE.get(slug)
            if cached_entry is not None and cached_entry[3] is lines and 'canonical' not in skill_chunks:
                if cached_entry[4] is None:
                    cached_entry[4] = build_canonical_stream(lines)
                skill_chunks['canonical'] = cached_entry[4]
            seen |= covered_lines(result.get('content'), lines, skill_chunks)
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


_DEFAULT_TRANSCRIPT_STEPS = transcript_steps
_DEFAULT_SHADOW_EVENTS = shadow_events


# The shadow keeps one inode for the conversation's lifetime, as a host transcript
# does: skill-loading.py keys its once-per-context checkpoint on (st_dev, st_ino).
# Its content lives only while an event runs; between events the file is empty.
# {key}.cache.json keeps only structural step tags and byte offsets into the host
# transcript file — never prompt text, tool outputs, commands, paths or prose.
SHADOW_NAME_RE = re.compile(r'[0-9a-f]{64}\.jsonl\Z')
CACHE_NAME_RE = re.compile(r'[0-9a-f]{64}\.cache\.json\Z')
LEGACY_TEMP_RE = re.compile(r'[0-9a-f]{64}\.[1-9][0-9]*\.tmp\Z')
WRITE_FLAGS = os.O_WRONLY | os.O_NOFOLLOW | os.O_NONBLOCK
READ_FLAGS = os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK


def resolve_transcript_stream(agy):
    raw = agy.get('transcriptPath')
    if not isinstance(raw, str) or not raw:
        return None
    path = Path(os.path.expanduser(raw))
    if not path.is_absolute():
        return None
    for candidate in (path.with_name('transcript_full.jsonl'), path):
        try:
            descriptor = os.open(candidate, os.O_RDONLY | os.O_NONBLOCK)
        except OSError:
            continue
        stream = os.fdopen(descriptor, 'rb')
        try:
            info = os.fstat(stream.fileno())
            if not stat.S_ISREG(info.st_mode):
                stream.close()
                continue
            return stream, info
        except BaseException:
            stream.close()
            raise
    return None


def compute_window_start(stream, size):
    if size <= MAX_TRANSCRIPT_BYTES:
        return 0
    pos = size - MAX_TRANSCRIPT_BYTES
    stream.seek(pos)
    remaining = MAX_TRANSCRIPT_BYTES
    while remaining > 0:
        chunk = stream.read(min(65536, remaining))
        if not chunk:
            return size
        nl = chunk.find(b'\n')
        if nl != -1:
            return pos + nl + 1
        pos += len(chunk)
        remaining -= len(chunk)
    return size


def span_block_digests(stream, start, end, prior_blocks=None, prior_end=None):
    span = end - start
    if span < 0:
        return None, False
    if span == 0:
        return [], True
    reused = 0
    blocks = []
    if prior_blocks is not None and prior_end is not None and start <= prior_end <= end:
        full = (prior_end - start) // CACHE_BLOCK_BYTES
        if full <= len(prior_blocks):
            reused = full
            blocks.extend(prior_blocks[:reused])
    pos = start + reused * CACHE_BLOCK_BYTES
    while pos < end:
        want = min(CACHE_BLOCK_BYTES, end - pos)
        stream.seek(pos)
        chunk = stream.read(want)
        if len(chunk) != want:
            return None, False
        blocks.append(hashlib.sha256(chunk).hexdigest())
        pos += want
    stream.seek(end - 1)
    if stream.read(1) != b'\n':
        return None, False
    return blocks, True


def read_cache_state(key):
    path = state_dir() / f'{key}.cache.json'
    try:
        descriptor = os.open(path, READ_FLAGS)
    except OSError:
        return None
    try:
        with os.fdopen(descriptor, 'rb') as stream:
            info = os.fstat(stream.fileno())
            if (not stat.S_ISREG(info.st_mode) or info.st_uid != os.getuid()
                    or info.st_nlink != 1 or info.st_size > MAX_CACHE_BYTES):
                return None
            parsed = json.loads(stream.read(MAX_CACHE_BYTES + 1).decode('utf-8'))
            return parsed if isinstance(parsed, dict) else None
    except (OSError, UnicodeError, ValueError):
        return None


def write_cache_state(key, payload):
    path = state_dir() / f'{key}.cache.json'
    descriptor = None
    try:
        try:
            descriptor = os.open(path, WRITE_FLAGS | os.O_CREAT | os.O_EXCL, 0o600)
        except FileExistsError:
            descriptor = os.open(path, WRITE_FLAGS)
        safe_shadow(descriptor)
        encoded = (json.dumps(payload, separators=(',', ':')) + '\n').encode('utf-8')
        if len(encoded) > MAX_CACHE_BYTES:
            return
        os.lseek(descriptor, 0, os.SEEK_SET)
        _write_all(descriptor, encoded)
        os.ftruncate(descriptor, len(encoded))
    except (OSError, BridgeError):
        return
    finally:
        if descriptor is not None:
            os.close(descriptor)


def serialize_skill_state(loaded, coverage, chunks):
    tracked = set(loaded) | set(coverage) | set(chunks)
    sigs = {}
    for slug in sorted(tracked):
        entry = bundled_skill_entry(slug)
        if entry is None:
            return None
        sigs[slug] = list(entry[0])
    cov_out = {
        slug: [list(span) for span in merge_spans((n, n + 1) for n in nums)]
        for slug, nums in sorted(coverage.items())
        if slug not in loaded and nums
    }
    ver_out = {
        slug: [list(span) for span in chunks[slug].get('verified', [])]
        for slug in sorted(chunks)
        if slug not in loaded and chunks[slug].get('verified')
    }
    return {'loaded': sorted(loaded), 'coverage': cov_out, 'verified': ver_out, 'skill_sigs': sigs}


def restore_skill_state(cache):
    sigs = cache.get('skill_sigs')
    loaded_raw = cache.get('loaded')
    cov_raw = cache.get('coverage')
    ver_raw = cache.get('verified')
    if not (isinstance(sigs, dict) and isinstance(loaded_raw, list)
            and isinstance(cov_raw, dict) and isinstance(ver_raw, dict)):
        return None
    for slug, want in sigs.items():
        if not isinstance(slug, str) or not isinstance(want, list) or len(want) != 4:
            return None
        entry = bundled_skill_entry(slug)
        if entry is None or list(entry[0]) != want:
            return None
    loaded = {s for s in loaded_raw if isinstance(s, str)}
    if len(loaded) != len(loaded_raw):
        return None
    coverage = {}
    for slug, ranges in cov_raw.items():
        if not isinstance(slug, str) or not isinstance(ranges, list):
            return None
        nums = set()
        for pair in ranges:
            if not (isinstance(pair, list) and len(pair) == 2 and is_int(pair[0]) and is_int(pair[1])
                    and 1 <= pair[0] < pair[1] <= 100000):
                return None
            nums.update(range(pair[0], pair[1]))
        coverage[slug] = nums
    chunks = {}
    for slug, ranges in ver_raw.items():
        if not isinstance(slug, str) or not isinstance(ranges, list):
            return None
        pairs = []
        for pair in ranges:
            if not (isinstance(pair, list) and len(pair) == 2 and is_int(pair[0]) and is_int(pair[1])
                    and 0 <= pair[0] <= pair[1] <= MAX_SKILL_BYTES * 2):
                return None
            pairs.append((pair[0], pair[1]))
        chunks[slug] = {'verified': pairs}
    return loaded, coverage, chunks


def emit_cached_records(stream, records, cwd):
    events, turn_id, last_prose = [], None, None
    if not isinstance(records, list):
        raise ValueError('records is not a list')
    for rec in records:
        if not isinstance(rec, list) or not rec:
            raise ValueError('malformed record')
        tag = rec[0]
        if tag == 'U':
            if len(rec) != 2 or not is_int(rec[1]):
                raise ValueError('bad user record')
            _, number = rec
            turn_id, last_prose = f'turn-{number}', None
            events.append({'type': 'user', 'uuid': turn_id, 'promptId': turn_id,
                           'message': {'role': 'user', 'content': [{'type': 'text', 'text': ''}]}})
        elif tag == 'P':
            if len(rec) != 3:
                raise ValueError('bad prose record')
            _, line_off, line_len = rec
            if not (is_int(line_off) and is_int(line_len) and line_off >= 0 and line_len >= 0):
                raise ValueError('bad prose span')
            stream.seek(line_off)
            raw_line = stream.read(line_len)
            if len(raw_line) != line_len:
                raise ValueError('short prose read')
            step = json.loads(raw_line.decode('utf-8', 'replace'))
            if not isinstance(step, dict) or step.get('type') != 'PLANNER_RESPONSE':
                raise ValueError('stale prose step')
            prose = step.get('content') if isinstance(step.get('content'), str) else ''
            if prose.strip():
                last_prose = prose
                events.append({'type': 'assistant', 'message': {
                    'role': 'assistant', 'content': [{'type': 'text', 'text': prose}]}})
        elif tag == 'C':
            if len(rec) != 7:
                raise ValueError('bad call record')
            _, number, line_off, line_len, paired_int, failed_hex, loaded_on_step = rec
            if not (is_int(number) and is_int(line_off) and is_int(line_len)
                    and is_int(paired_int) and paired_int in (0, 1)
                    and line_off >= 0 and line_len >= 0
                    and isinstance(failed_hex, str) and isinstance(loaded_on_step, list)):
                raise ValueError('bad call record')
            stream.seek(line_off)
            raw_line = stream.read(line_len)
            if len(raw_line) != line_len:
                raise ValueError('short call read')
            step = json.loads(raw_line.decode('utf-8', 'replace'))
            if not isinstance(step, dict) or step.get('type') != 'PLANNER_RESPONSE':
                raise ValueError('stale call step')
            calls = [c for c in step.get('tool_calls') or [] if isinstance(c, dict)]
            paired = bool(paired_int)
            failed_bits = int(failed_hex, 16)
            loaded_map = {}
            for item in loaded_on_step:
                if not (isinstance(item, list) and len(item) == 2 and is_int(item[0]) and isinstance(item[1], str)):
                    raise ValueError('bad loaded_on_step item')
                loaded_map[item[0]] = item[1]
            for position, call in enumerate(calls):
                name, args = str(call.get('name') or ''), tool_args(call)
                failed = bool((failed_bits >> position) & 1)
                base = str(call.get('id') or f'call-{number}-{position}')
                for offset, (tool, tool_input) in enumerate(claude_calls(name, args, cwd)):
                    call_id = base if offset == 0 else f'{base}-{offset}'
                    events.append({'type': 'assistant', 'message': {'role': 'assistant', 'content': [
                        {'type': 'tool_use', 'id': call_id, 'name': tool, 'input': tool_input}]}})
                    if paired:
                        events.append({'type': 'user', 'message': {'role': 'user', 'content': [
                            {'type': 'tool_result', 'tool_use_id': call_id, 'content': '',
                             'is_error': failed}]}})
                slug = loaded_map.get(position)
                if slug is not None:
                    skill_id = f'skill-{number}-{position}'
                    events.append({'type': 'assistant', 'message': {'role': 'assistant', 'content': [
                        {'type': 'tool_use', 'id': skill_id, 'name': 'Skill',
                         'input': {'skill': f'ccl-skills:{slug}'}}]}})
                    events.append({'type': 'user', 'message': {'role': 'user', 'content': [
                        {'type': 'tool_result', 'tool_use_id': skill_id, 'content': 'loaded',
                         'is_error': False}]}})
        else:
            raise ValueError('unknown record tag')
    return events, turn_id, last_prose


def parse_tail_slice(
    raw_bytes,
    parse_start,
    cwd,
    *,
    events,
    turn_id,
    last_prose,
    coverage,
    loaded,
    chunks,
    step_count,
    prior_records,
):
    parsed_steps = []
    complete_end = parse_start
    pos, total_bytes = 0, len(raw_bytes)
    while pos < total_bytes:
        nl = raw_bytes.find(b'\n', pos)
        if nl == -1:
            raw_line, has_nl, next_end = raw_bytes[pos:], False, parse_start + total_bytes
            pos = total_bytes
        else:
            raw_line, has_nl, next_end = raw_bytes[pos:nl], True, parse_start + nl + 1
            pos = nl + 1
        line_off = parse_start + (next_end - parse_start - len(raw_line) - (1 if has_nl else 0))
        try:
            step = json.loads(raw_line.decode('utf-8', 'replace'))
        except ValueError:
            if has_nl:
                complete_end = next_end
            continue
        if isinstance(step, dict):
            parsed_steps.append((line_off, len(raw_line), has_nl, next_end, step))
        if has_nl:
            complete_end = next_end

    frozen_records = list(prior_records)
    frozen_end = parse_start
    frozen_step_count = step_count
    frozen_loaded = set(loaded)
    frozen_coverage = {k: set(v) for k, v in coverage.items()}
    frozen_chunks = {k: {'verified': list(v.get('verified', []))} for k, v in chunks.items()}
    can_freeze = True

    cur_step_index = step_count
    idx = 0
    while idx < len(parsed_steps):
        line_off, line_len, has_nl, line_end, step = parsed_steps[idx]
        step_ord = cur_step_index
        kind, number = step.get('type'), step.get('step_index', step_ord)
        idx += 1
        cur_step_index += 1

        if kind == 'USER_INPUT':
            explicit = step.get('source') == 'USER_EXPLICIT'
            if explicit:
                turn_id, last_prose = f'turn-{number}', None
                events.append({'type': 'user', 'uuid': turn_id, 'promptId': turn_id,
                               'message': {'role': 'user', 'content': [{'type': 'text', 'text': ''}]}})
            if can_freeze and has_nl and (not explicit or is_int(number)):
                if explicit:
                    frozen_records.append(['U', number])
                frozen_end = parsed_steps[idx][0] if idx < len(parsed_steps) else complete_end
                frozen_step_count = cur_step_index
            else:
                can_freeze = False
            continue

        if kind != 'PLANNER_RESPONSE':
            if can_freeze and has_nl:
                frozen_end = parsed_steps[idx][0] if idx < len(parsed_steps) else complete_end
                frozen_step_count = cur_step_index
            else:
                can_freeze = False
            continue

        calls = [c for c in step.get('tool_calls') or [] if isinstance(c, dict)]
        prose = step.get('content') if isinstance(step.get('content'), str) else ''
        if not calls:
            if prose.strip():
                last_prose = prose
                events.append({'type': 'assistant', 'message': {
                    'role': 'assistant', 'content': [{'type': 'text', 'text': prose}]}})
                if can_freeze and has_nl:
                    frozen_records.append(['P', line_off, line_len])
            if can_freeze and has_nl:
                frozen_end = parsed_steps[idx][0] if idx < len(parsed_steps) else complete_end
                frozen_step_count = cur_step_index
            else:
                can_freeze = False
            continue

        results = []
        while idx < len(parsed_steps) and parsed_steps[idx][4].get('type') not in ('PLANNER_RESPONSE', 'USER_INPUT'):
            if parsed_steps[idx][4].get('type') == 'GENERIC':
                results.append(parsed_steps[idx][4])
            idx += 1
            cur_step_index += 1

        is_closed = idx < len(parsed_steps) and has_nl
        paired = len(results) == len(calls)
        failed_bits = 0
        loaded_on_step = []
        for position, call in enumerate(calls):
            name, args = str(call.get('name') or ''), tool_args(call)
            result = results[position] if paired else None
            failed = result is None or result.get('status') != 'DONE' or bool(result.get('error'))
            if failed:
                failed_bits |= 1 << position
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
            skill_chunks = chunks.setdefault(slug, {})
            cached_entry = SKILL_CACHE.get(slug)
            if cached_entry is not None and cached_entry[3] is lines and 'canonical' not in skill_chunks:
                if cached_entry[4] is None:
                    cached_entry[4] = build_canonical_stream(lines)
                skill_chunks['canonical'] = cached_entry[4]
            seen |= covered_lines(result.get('content'), lines, skill_chunks)
            if len(seen) == len(lines):
                loaded.add(slug)
                loaded_on_step.append([position, slug])
                skill_id = f'skill-{number}-{position}'
                events.append({'type': 'assistant', 'message': {'role': 'assistant', 'content': [
                    {'type': 'tool_use', 'id': skill_id, 'name': 'Skill',
                     'input': {'skill': f'ccl-skills:{slug}'}}]}})
                events.append({'type': 'user', 'message': {'role': 'user', 'content': [
                    {'type': 'tool_result', 'tool_use_id': skill_id, 'content': 'loaded',
                     'is_error': False}]}})

        if can_freeze and is_closed and is_int(number):
            frozen_records.append(['C', number, line_off, line_len, 1 if paired else 0,
                                   f'{failed_bits:x}', loaded_on_step])
            frozen_end = parsed_steps[idx][0]
            frozen_step_count = cur_step_index
            frozen_loaded = set(loaded)
            frozen_coverage = {k: set(v) for k, v in coverage.items()}
            frozen_chunks = {k: {'verified': list(v.get('verified', []))} for k, v in chunks.items()}
        else:
            can_freeze = False

    if can_freeze and not parsed_steps:
        frozen_end = complete_end

    frozen_state = (frozen_end, frozen_step_count, frozen_records,
                    frozen_loaded, frozen_coverage, frozen_chunks)
    return events, turn_id, last_prose, frozen_state


def cached_transcript_events(agy, key, cwd):
    opened = resolve_transcript_stream(agy)
    if opened is None:
        return [], None, None
    stream, info = opened
    try:
        size = info.st_size
        window_start = compute_window_start(stream, size)
        cwd_hash = digest(cwd or '')
        cache = read_cache_state(key)

        base_events, turn_id, last_prose = [], None, None
        loaded, coverage, chunks = set(), {}, {}
        parse_start = window_start
        step_count = 0
        prior_records = []
        reusable_blocks, reusable_end = None, None

        if (cache is not None and cache.get('version') == 2
                and cache.get('dev') == info.st_dev and cache.get('ino') == info.st_ino
                and cache.get('cwd') == cwd_hash and cache.get('window_start') == window_start):
            cand_end = cache.get('frozen_end')
            cand_steps = cache.get('step_count')
            cached_blocks = cache.get('block_sha256')
            if (is_int(cand_end) and is_int(cand_steps) and isinstance(cached_blocks, list)
                    and window_start <= cand_end <= size and cand_steps >= 0):
                verified_blocks, ok = span_block_digests(stream, window_start, cand_end)
                restored = restore_skill_state(cache) if ok else None
                if ok and restored is not None and verified_blocks == cached_blocks:
                    try:
                        prior_records = cache.get('records')
                        base_events, turn_id, last_prose = emit_cached_records(stream, prior_records, cwd)
                        loaded, coverage, chunks = restored
                        parse_start = cand_end
                        step_count = cand_steps
                        reusable_blocks, reusable_end = verified_blocks, cand_end
                    except (OSError, ValueError, TypeError, KeyError, IndexError, OverflowError):
                        base_events, turn_id, last_prose = [], None, None
                        loaded, coverage, chunks = set(), {}, {}
                        parse_start = window_start
                        step_count = 0
                        prior_records = []
                        reusable_blocks, reusable_end = None, None

        stream.seek(parse_start)
        tail_bytes = stream.read(max(0, size - parse_start))
        events, turn_id, last_prose, frozen = parse_tail_slice(
            tail_bytes, parse_start, cwd,
            events=base_events, turn_id=turn_id, last_prose=last_prose,
            coverage=coverage, loaded=loaded, chunks=chunks,
            step_count=step_count, prior_records=prior_records,
        )
        frozen_end, frozen_steps, frozen_records, f_loaded, f_cov, f_chunks = frozen
        skill_blob = serialize_skill_state(f_loaded, f_cov, f_chunks)
        if skill_blob is not None and (cache is None or cache.get('version') != 2
                                       or frozen_end != cache.get('frozen_end')
                                       or reusable_blocks is None
                                       or cache.get('dev') != info.st_dev
                                       or cache.get('ino') != info.st_ino
                                       or cache.get('cwd') != cwd_hash
                                       or cache.get('window_start') != window_start):
            new_blocks, ok = span_block_digests(
                stream, window_start, frozen_end, reusable_blocks, reusable_end,
            )
            if ok:
                write_cache_state(key, {
                    'version': 2, 'dev': info.st_dev, 'ino': info.st_ino, 'cwd': cwd_hash,
                    'window_start': window_start, 'frozen_end': frozen_end,
                    'step_count': frozen_steps, 'block_sha256': new_blocks,
                    'records': frozen_records, **skill_blob,
                })
        return events, turn_id, last_prose
    finally:
        stream.close()


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
SHADOW_BASES = {}  # key -> byte length of the base events written for this event


def _write_all(descriptor, data):
    view = memoryview(data)
    while view:
        view = view[os.write(descriptor, view):]


def _write_events(descriptor, records):
    buf = bytearray()
    written = 0
    try:
        for event in records:
            line = (json.dumps(event) + '\n').encode('utf-8')
            if buf and len(buf) + len(line) > SHADOW_WRITE_CHUNK:
                _write_all(descriptor, buf)
                written += len(buf)
                buf.clear()
            if len(line) >= SHADOW_WRITE_CHUNK:
                _write_all(descriptor, line)
                written += len(line)
            else:
                buf.extend(line)
    except BaseException:
        if buf:
            _write_all(descriptor, buf)
        raise
    if buf:
        _write_all(descriptor, buf)
        written += len(buf)
    return written


def write_shadow(key, events, extra=None, reuse_prefix=False):
    directory = state_dir()
    target = directory / f'{key}.jsonl'
    descriptor, created, held = OPEN_SHADOWS.get(key), False, None
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
    base = SHADOW_BASES.get(key) if (reuse_prefix and held is not None and extra is not None) else None
    if base is not None and held.st_size >= base:
        os.lseek(descriptor, base, os.SEEK_SET)
        written = base + _write_events(descriptor, [extra])
    else:
        os.lseek(descriptor, 0, os.SEEK_SET)
        base_written = _write_events(descriptor, events)
        SHADOW_BASES[key] = base_written
        written = base_written + (_write_events(descriptor, [extra]) if extra else 0)
    os.ftruncate(descriptor, written)
    if created:
        sweep_stale(directory)
    return str(target)


def clear_shadow(key):
    """Empty the shadow at event end through the descriptor the event wrote, so a
    rename or replacement of the name during the event cannot keep content around.
    An event that wrote nothing touches nothing; the sweep empties what a killed
    event left behind."""
    SHADOW_BASES.pop(key, None)
    descriptor = OPEN_SHADOWS.pop(key, None)
    if descriptor is None:
        return
    try:
        os.ftruncate(descriptor, 0)
    finally:
        os.close(descriptor)


def sweep_stale(directory, budget=1.0):
    """Empty shadows an interrupted event left full and drop stale parse caches / legacy temp files.

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
                                       lambda p=entry.path: remove_if_stale(p, cutoff))
                    elif CACHE_NAME_RE.match(entry.name):
                        key = entry.name[:-len('.cache.json')]
                        under_run_lock(directory, key, lambda p=entry.path: remove_if_stale(p, cutoff))
                    elif SHADOW_NAME_RE.match(entry.name) and info.st_size:
                        key = entry.name[:-len('.jsonl')]
                        under_run_lock(directory, key, lambda n=entry.name: empty_if_stale(directory / n, cutoff))
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
    if transcript_steps is _DEFAULT_TRANSCRIPT_STEPS and shadow_events is _DEFAULT_SHADOW_EVENTS:
        events, turn_id, prose = cached_transcript_events(agy, key, cwd)
    else:
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
            ctx['transcript'] = write_shadow(ctx['key'], ctx['events'], pending, reuse_prefix=True)
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
    entrypoint = os.environ.get('CLAUDE_CODE_ENTRYPOINT', '')
    sdk_entrypoint = entrypoint == 'sdk' or entrypoint.startswith('sdk-')
    for script in DISPATCH['Stop']:
        if script == 'headless-background-stop.sh' and not sdk_entrypoint:
            continue
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
