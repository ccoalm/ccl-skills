# hooks Agent Contract

Hooks are plugin-shipped runtime enforcement surfaces. Hosts may execute them on
session start or tool use, so changes here are shared-skill behavior changes.

Rules:

- Keep hooks deterministic, fail-closed where safety requires it, and explicit
  about advisory versus blocking outcomes.
- Do not read secrets or personal config unless the hook's contract documents
  why and how failures degrade.
- Avoid broad filesystem mutation from hooks.
- Non-wording changes require deterministic validation plus independent review
  and adversarial challenge before landing.

- `agy-bridge.py` adapts Antigravity's hook protocol to these scripts. Policy
  decisions stay in the scripts; the bridge owns only protocol errors, failure
  defaults (edit, delegation, owner-dispatch and merge guards fail closed; a
  merge guard that cannot run blocks every command), verdict aggregation (deny over ask over allow)
  and Stop loop prevention. Its dispatch lists are the binding inventory and must
  equal the command hooks in `hooks.json`; it prints exactly one JSON object per
  event. Its shadow transcript (`{key}.jsonl`) holds content only during an
  event and is truncated to zero at event end; its incremental parse cache
  (`{key}.cache.json`) stores only structural tags and byte offsets into the
  host transcript (never user prompts, tool output, commands, paths or assistant
  prose) and is swept under `{key}.run.lock` when stale.
- A hook reads its payload fields with one jq call, because jq start-up is most
  of a hook's latency. Each value must equal what `$(jq -r '.x // default')`
  gave. A payload the merged read cannot decode that way, or could decode only
  in more than linear time or memory (values over 65,536 characters, NULs,
  long trailing-newline runs), falls back to the per-field reads. A hook
  stalled past the host timeout does not block. `test_hook_field_reads.py`
  pins this against baseline `788470c` for the merge, broad-test and
  edit-isolation guards and the owner-dispatch engine;
  `test_hook_remaining_field_reads.py` pins live `788470c` differential parity,
  stall bounds, peak RSS and jq-spawn counts for `skill-extraction-gate-stop.sh`,
  `remind-review-covers-head.sh`, `remind-post-merge-cleanup.sh`,
  `merge-authorization-prompt.sh` and `remind-unverified-cli-flag.sh`.

Validation:

- `bash skills/skill-extraction-workflow/scripts/check-ccl-skills.sh .`
- `git diff --check`
- `python3 hooks/test_agy_bridge.py` when the bridge, `hooks.json` or the root
  `hooks.json` changes
- `python3 hooks/test_hook_field_reads.py` and
  `python3 hooks/test_hook_remaining_field_reads.py` when a hook's payload
  field reads change (`REQUIRE_BASELINE=1` requires `788470c` in local git
  history rather than falling back on shallow clones); regenerate
  `test_hook_field_reads.expected.json` only from the pinned baseline
