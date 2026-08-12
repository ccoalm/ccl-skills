---
description: Verify CCL skills and OpenCode local discovery
---

Verify the CCL skills repository and OpenCode discovery state.

Run these checks from the repository root:

```bash
bash -n scripts/install.sh && bash -n scripts/install-opencode.sh
python3 -m json.tool opencode.json >/dev/null
git diff --check
bash skills/skill-extraction-workflow/scripts/check-ccl-skills.sh .
tmp_home=$(mktemp -d)
skills_json=$(mktemp)
real_home=${HOME:-}
HOME="$tmp_home" OPENCODE_DISABLE_EXTERNAL_SKILLS=1 opencode debug skill > "$skills_json"
HOME="$tmp_home" REAL_HOME="$real_home" SKILLS_JSON="$skills_json" python3 - <<'PY'
import json
import os
import urllib.parse
from pathlib import Path


def parse_frontmatter_name(path):
    lines = path.read_text(encoding='utf-8').splitlines()
    if not lines or lines[0].strip() != '---':
        return None
    for line in lines[1:]:
        if line.strip() == '---':
            return None
        if line.startswith('name:'):
            return line.split(':', 1)[1].strip().strip('"\'') or None
    return None


def location_path(value):
    text = str(value or '')
    if text.startswith('file://'):
        return Path(urllib.parse.unquote(urllib.parse.urlparse(text).path)).resolve()
    return Path(text).resolve() if text else None


repo = Path.cwd().resolve()
skills_root = repo / 'skills'
expected = {}
for skill_file in sorted(skills_root.glob('*/SKILL.md')):
    dirname = skill_file.parent.name
    fm_name = parse_frontmatter_name(skill_file)
    if fm_name and fm_name != dirname:
        raise AssertionError(f'frontmatter name mismatch: {skill_file}: name={fm_name!r} dir={dirname!r}')
    expected[dirname] = skill_file.resolve()

skills = json.load(open(os.environ['SKILLS_JSON'], encoding='utf-8'))
actual = {}
for item in skills:
    loc = location_path(item.get('location'))
    if not loc:
        continue
    try:
        loc.relative_to(skills_root.resolve())
    except ValueError:
        continue
    name = item.get('name') or (loc.parent.name if loc.name == 'SKILL.md' else None)
    if name:
        actual[str(name)] = loc

expected_names = set(expected)
actual_names = set(actual)
missing = sorted(expected_names - actual_names)
extra = sorted(actual_names - expected_names)
print('expected_local_skill_count=', len(expected_names))
print('actual_local_skill_count=', len(actual_names))
print('missing_local_skills=', ','.join(missing) or '<none>')
print('extra_local_skills=', ','.join(extra) or '<none>')
if missing or extra:
    raise AssertionError({'missing': missing, 'extra': extra, 'actual': sorted(actual_names), 'expected': sorted(expected_names)})

real_home = os.environ.get('REAL_HOME')
if real_home:
    global_root = Path(real_home).expanduser() / '.config' / 'opencode' / 'skills'
    duplicates = sorted(name for name in expected_names if (global_root / name / 'SKILL.md').exists())
    if duplicates:
        print('warning_global_skill_snapshots=', ','.join(duplicates))
        print('warning_global_skill_snapshots_note=these are independent installed snapshots; repo development should trust this isolated local verify. To refresh global OpenCode skills, run install/update and restart OpenCode.')
PY
rm -rf "$tmp_home" "$skills_json"
```

Report pass/fail honestly. Do not claim OpenCode support is verified if any command fails.

## Injection liveness probe (do this in-session, not via shell)

The bootstrap injection rides OpenCode's `experimental.chat.system.transform`
plugin API; an OpenCode upgrade can rename/remove it and the plugin fails
SILENTLY (all hooks are wrapped to never break startup). Skill discovery
passing does NOT prove injection. So, as the agent running this command,
check your CURRENT system prompt: it must contain the dedupe marker string
formed by joining `ccl-skills` and `-routing` into one hyphenated word
(written SPLIT here on purpose — if this command spelled the marker out, the
command text itself would satisfy the check and a dead injection would still
report LIVE). Search your system prompt for that joined word outside of this
command's own text. Report one line:

- marker present  -> `bootstrap injection: LIVE`
- marker absent   -> `bootstrap injection: NOT LIVE` — remediate: confirm the
  plugin file is in `~/.config/opencode/plugins/`, restart OpenCode, and if it
  still fails check OpenCode release notes for the experimental hook rename and
  report to the ccl-skills maintainer (do not self-patch the plugin API).
