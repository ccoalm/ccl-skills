#!/usr/bin/env python3
"""Bounded model-replan checkpoints; never approval or owner-selection proof."""
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import re
import stat
import sys
import tempfile
import uuid

sys.dont_write_bytecode = True
ROOT = Path(__file__).resolve().parents[1]
SOURCE_EXTENSIONS = frozenset((
    '.sh', '.py', '.ts', '.mjs', '.rb', '.go', '.dart', '.js', '.jsx', '.tsx',
    '.rs', '.c', '.cc', '.cpp', '.h', '.hpp', '.java', '.kt', '.kts', '.swift',
    '.cs', '.vue', '.svelte', '.ipynb', '.sql', '.css', '.scss', '.html'))


EXTRACTION_OWNER = 'ccl-skills:skill-extraction-workflow'


def shared_skill_paths(paths, cwd):
    """Targets on a ccl-skills checkout's shared-skill or plugin-behavior surface.

    Same scope as the extraction stop backstop: a root that holds
    skills/skill-extraction-workflow/SKILL.md, reached through skills/, hooks/
    or scripts/, with plugin caches excluded. Moving that knowledge to the first
    edit lets the round open with the extraction charter instead of learning at
    Stop, after commit, push and pull request.
    """
    shared = []
    for raw in paths:
        path = Path(raw) if os.path.isabs(raw) else Path(cwd) / raw
        text = path.as_posix()
        if '/plugins/cache/' in text or '/.codex/' in text:
            continue
        # Every occurrence, not only the first: a checkout may sit under an
        # ancestor that is itself named skills, hooks or scripts.
        roots = (text[:match.start()] for match in re.finditer(r'/(?:skills|hooks|scripts)/', text))
        if any(root and (Path(root) / 'skills/skill-extraction-workflow/SKILL.md').is_file() for root in roots):
            shared.append(text)
    return shared


def digest(value):
    return hashlib.sha256(json.dumps(value, ensure_ascii=True, sort_keys=True).encode()).hexdigest()


def normalizer():
    spec = importlib.util.spec_from_file_location('ccl_host_input', ROOT / 'hooks/host-input.py')
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def actor(payload):
    session = payload.get('session_id')
    agent = payload.get('agent_id', '')
    transcript = payload.get('agent_transcript_path') or payload.get('transcript_path')
    if not isinstance(session, str) or not session or len(session) > 1024:
        raise ValueError('unavailable session identity')
    if not isinstance(agent, str) or len(agent) > 1024:
        raise ValueError('unavailable actor identity')
    if not isinstance(transcript, str) or not transcript or len(transcript) > 8192:
        raise ValueError('unavailable actor transcript')
    transcript = os.path.realpath(transcript)
    return digest([str(ROOT), session, agent, transcript]), transcript


def owned_directory(path=None, *, name=None, parent=None):
    if parent is None:
        try:
            os.mkdir(path, 0o700)
        except FileExistsError:
            pass
        descriptor = os.open(path, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW)
    else:
        try:
            os.mkdir(name, 0o700, dir_fd=parent)
        except FileExistsError:
            pass
        descriptor = os.open(name, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW, dir_fd=parent)
    info = os.fstat(descriptor)
    if info.st_uid != os.getuid() or info.st_mode & 0o022:
        os.close(descriptor)
        raise ValueError('unsafe checkpoint state')
    return descriptor


class State:
    def __init__(self, key):
        temporary = os.environ.get('TMPDIR') or tempfile.gettempdir()
        parent = owned_directory(os.path.join(temporary, 'ccl-skill-loading-' + str(os.getuid())))
        try:
            self.fd = owned_directory(name=key, parent=parent)
        finally:
            os.close(parent)

    def close(self):
        os.close(self.fd)

    def read(self, name='context.json'):
        try:
            descriptor = os.open(name, os.O_RDONLY | os.O_NONBLOCK | os.O_NOFOLLOW,
                                 dir_fd=self.fd)
        except FileNotFoundError:
            return None
        with os.fdopen(descriptor, 'rb') as stream:
            info = os.fstat(stream.fileno())
            if not stat.S_ISREG(info.st_mode) or info.st_uid != os.getuid() or info.st_size > 4096:
                raise ValueError('invalid context state')
            value = json.load(stream)
        if (not isinstance(value, dict) or not re.fullmatch(r'[a-f0-9]{32}', value.get('generation', ''))
                or not isinstance(value.get('offset'), int) or value['offset'] < 0
                or not isinstance(value.get('device'), int) or not isinstance(value.get('inode'), int)):
            raise ValueError('invalid context state')
        boundary = value.get('before_context')
        if boundary is not None and (not isinstance(boundary, str) or len(boundary) > 128):
            raise ValueError('invalid context boundary')
        return value

    def save(self, name, info, before_context=None):
        value = {'generation': uuid.uuid4().hex, 'offset': info.st_size,
                 'device': info.st_dev, 'inode': info.st_ino,
                 'before_context': before_context}
        temporary = 'context-' + uuid.uuid4().hex
        descriptor = os.open(temporary, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW,
                             0o600, dir_fd=self.fd)
        try:
            with os.fdopen(descriptor, 'w') as stream:
                json.dump(value, stream)
            os.replace(temporary, name, src_dir_fd=self.fd, dst_dir_fd=self.fd)
        finally:
            try:
                os.unlink(temporary, dir_fd=self.fd)
            except FileNotFoundError:
                pass

    def claim_attempt(self, lane, epoch):
        # Atomic delivery-attempt cap only. No marker says a skill was loaded,
        # a user approved, or the model saw the output. Parallel siblings and a
        # blind retry may proceed; configured policy remains the hard backstop.
        try:
            os.mkdir('attempt-' + digest([lane, epoch]), 0o700, dir_fd=self.fd)
            return True
        except FileExistsError:
            return False


def regular_info(path):
    descriptor = os.open(path, os.O_RDONLY | os.O_NONBLOCK)
    try:
        info = os.fstat(descriptor)
        if not stat.S_ISREG(info.st_mode):
            raise ValueError('unavailable regular transcript')
        return info
    finally:
        os.close(descriptor)


def routing_rule():
    with (ROOT / 'agent-context/session-start.md').open(encoding='utf-8') as stream:
        source = stream.read(32 * 1024)
    for paragraph in source.split('\n\n'):
        if paragraph.startswith('**Transitions:**') and len(paragraph.encode()) < 4096:
            return paragraph
    raise ValueError('canonical routing rule unavailable')


def handle(payload, base):
    specific = base.get('hookSpecificOutput', {})
    if (base.get('continue') is False or base.get('decision') == 'block'
            or isinstance(specific, dict) and specific.get('permissionDecision') in ('deny', 'ask', 'allow')):
        return base
    event = payload.get('hook_event_name')
    tool = payload.get('tool_name')
    module = normalizer()
    if event in ('PreCompact', 'PostCompact'):
        lane = 'compact'
    elif event == 'PreToolUse' and tool in ('Task', 'Agent', 'spawn_agent'):
        lane = 'delegation'
    elif event == 'PreToolUse' and tool in ('Edit', 'Write', 'MultiEdit', 'NotebookEdit', 'apply_patch'):
        parsed = module.paths(payload)
        if parsed['malformed_patch']:
            return base
        edit_cwd = payload.get('cwd') if isinstance(payload.get('cwd'), str) else os.getcwd()
        shared = shared_skill_paths(parsed['paths'], edit_cwd)
        # Skill text is behavior on the shared surface, so markdown counts there only.
        if not (any(Path(path).suffix.lower() in SOURCE_EXTENSIONS for path in parsed['paths'])
                or any(Path(path).suffix.lower() == '.md' for path in shared)):
            return base
        lane = 'implementation'
    else:
        return base
    key, path = actor(payload)
    info = regular_info(path)
    cwd = payload.get('cwd')
    cwd = cwd if isinstance(cwd, str) else os.getcwd()
    state = State(key)
    try:
        if lane == 'compact':
            if event == 'PreCompact':
                # Snapshot only: a cancelled/failed compaction must not reset
                # checkpoints or invalidate instructions still in context.
                summary = module.context_transcript(path, cwd)
                state.save('precompact.json', info, summary.get('context_id'))
            else:
                before = state.read('precompact.json')
                boundary = None
                if before and (before['device'], before['inode']) == (info.st_dev, info.st_ino):
                    boundary = before.get('before_context')
                state.save('context.json', info, boundary)
                try:
                    os.unlink('precompact.json', dir_fd=state.fd)
                except FileNotFoundError:
                    pass
            # These events do not inject model context. Guidance is delivered
            # through the next supported PreToolUse checkpoint.
            return base
        record = state.read()
        offset = 0
        if record:
            if ((record['device'], record['inode']) != (info.st_dev, info.st_ino)
                    or record['offset'] > info.st_size):
                raise ValueError('transcript changed after compaction')
            offset = record['offset']
        # Establish the boundary before reading proof. The reverse order can
        # combine delayed old reads with a boundary appended between snapshots.
        latest = module.context_transcript(path, cwd).get('context_id') if record else None
        summary = module.context_transcript(path, cwd, start_offset=offset)
        current_info = regular_info(path)
        if ((info.st_dev, info.st_ino) != (current_info.st_dev, current_info.st_ino)
                or current_info.st_size < info.st_size):
            raise ValueError('transcript changed during context read')
        # Explicit completion events take precedence over a delayed disk marker;
        # that marker must not spend another checkpoint in the same window.
        epoch = [record['generation'] if record else summary.get('context_id'), info.st_dev, info.st_ino]
        complete = summary.get('context_complete') is True
        if record:
            # Transcript writes can lag both callbacks. Even complete old reads
            # appended after the high-watermark are stale until a new native
            # context boundary is visible. A missing PreCompact snapshot needs
            # a boundary at/after the cutoff; never infer it from append alone.
            native = isinstance(latest, str) and latest.startswith('native:')
            before = record.get('before_context')
            fresh = native and (latest != before if before is not None
                                else int(latest.split(':')[1]) >= offset)
            proof_context = summary.get('context_id')
            same = (proof_context == latest or native and int(latest.split(':')[1]) < offset
                    and proof_context == 'offset:' + str(offset))
            complete = complete and fresh and same
        loaded = summary.get('completed_skills', []) if complete else []
        if lane == 'delegation' and 'ccl-skills:multi-agent-delegation' in loaded:
            return base
        if lane == 'delegation':
            reason = ('Delegation skill checkpoint: load ccl-skills:multi-agent-delegation in this actor\'s '
                      'current context before dispatch. A prior-context read, a name, or a partial read is '
                      'not current full-load evidence. ')
        else:
            reason = ('First source-edit skill checkpoint: this edit attempt did not execute. Before retrying, '
                      'apply the canonical routing rule and load the owning implementation skill if missing '
                      'from the current context. If already loaded, apply it without unnecessary re-reading. ')
            if shared and EXTRACTION_OWNER not in loaded:
                reason += ('This edit targets a ccl-skills shared-skill or plugin-behavior surface ('
                           + shared[0] + '). Invoke ' + EXTRACTION_OWNER + ' now and record its extraction '
                           'charter before this edit, even when another owner (a bug fix, a test change) also '
                           'applies: the charter cannot be written after the edits, and the stop backstop '
                           'fires only after commit, push and pull request. ')
        reason += routing_rule() + (' Resolve this checkpoint yourself; do not ask the user to approve skill loading. '
                          'Respect explicit user scope and skill choices. This is one bounded replan opportunity, '
                          'not new authority or proof that the owner is correct.')
        if not state.claim_attempt(lane, epoch):
            return base
        result = dict(base)
        output = dict(specific) if isinstance(specific, dict) else {}
        output.update(hookEventName='PreToolUse', permissionDecision='deny', permissionDecisionReason=reason)
        result['hookSpecificOutput'] = output
        return result
    finally:
        state.close()


def main():
    base = {}
    try:
        if len(sys.argv) > 1 and sys.argv[1]:
            base = json.loads(sys.argv[1])
        if not isinstance(base, dict):
            return 1
    except (ValueError, TypeError):
        # The shell wrapper retains the exact engine output on this path.
        # Malformed upstream output must not become a successful replacement.
        return 1
    try:
        raw = sys.stdin.read(2 * 1024 * 1024 + 1)
        if len(raw) > 2 * 1024 * 1024:
            raise ValueError('oversized hook input')
        payload = json.loads(raw)
        if not isinstance(payload, dict):
            raise ValueError('invalid hook input')
        result = handle(payload, base)
    except (OSError, ValueError, TypeError, AttributeError, ImportError):
        result = dict(base)
        result['systemMessage'] = 'Skill-loading checkpoint unavailable: current context or local state could not be verified; existing policy is unchanged.'
    if result:
        print(json.dumps(result))
    return 0


if __name__ == '__main__':
    sys.exit(main())
