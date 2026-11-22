# PreToolUse Hook Latency (narrowed plan)

Supersedes both the R1–R11 reimplementing dispatcher and the orchestrator plan that followed it. Why: [`self-review-R11.md`](self-review-R11.md), plus the measurements below. The goal is unchanged: lower per-tool-call hook latency without weakening any hook.

## What the time actually is

All figures below use the same payloads and are measured in the same run on each host. The fixture is an ordinary git project with no `.owner-dispatch.json`; figures are the median of 11 runs, in ms.

- **parallel** is how Claude Code runs matching hooks;
- **serial** is how the OpenCode plugin and `agy-bridge.py` run them.

The harness is [`evidence/bench/hook_latency.py`](evidence/bench/hook_latency.py).

| Host | Call | main, parallel | main, serial | R11 dispatcher |
| --- | --- | ---: | ---: | ---: |
| macOS, jq 1.7.1 | Bash | 83 | 181 | 44 |
| macOS, jq 1.7.1 | Edit | 91 | 161 | 73 |
| Linux, jq 1.6, Python 3.11 | Bash | 202 | 487 | 77 |
| Linux, jq 1.6, Python 3.11 | Edit | 222 | 325 | 84 |

The R11 record compared its dispatcher with main's *serial* sum. On Claude Code the real baseline is the parallel figure, so R11 saved 18–39 ms per call on macOS.

Per-hook traces (Linux, `bash -x` with timestamps) show **jq start-up** is the main cost. Each `jq` call costs about 21 ms on jq 1.6 and about 4 ms on jq 1.7.1:

| Hook | `jq` calls | Time spent in `jq` |
| --- | ---: | --- |
| `guard-merge-authorization.sh` | 4 | 85 of 131 ms |
| owner-dispatch engine (`owner-dispatch.sh pretool`), before it finds the project has not opted in | 5 | about 110 of 137 ms |
| `guard-edit-isolation.sh` | 2 | 43 ms |
| `guard-broad-local-test.sh` | 2 | 47 ms |
| each of the 3 advisory hooks | 1 | about 22 of 30 ms |

The critical path on both hosts is `owner-dispatch-guard.sh`, which runs the engine and then `skill-loading.py` back to back.

A prototype on a scratch copy of main isolated each change's share of that hook's time (Linux):

| Variant | `owner-dispatch-guard.sh` |
| --- | ---: |
| main | 196 ms |
| one `jq` call in the engine | 107 ms |
| plus bytecode caching for `skill-loading.py` | 95 ms |

## Options

| Option | Result | Risk |
| --- | --- | --- |
| A. One `jq` read per hook | Removes about 21 ms per merged call on jq 1.6 and about 4 ms on jq 1.7.1. Applies to every host, because each runs the same scripts. | Low. Verdict logic is unchanged |
| B. Also cache bytecode under a user cache directory | 12 ms more on the critical hook | Rejected. Trusting a cache path, keeping it out of repo-local `XDG_CACHE_HOME`, and invalidating stale caches cost more than 12 ms is worth |
| C. Also run hooks concurrently in the OpenCode plugin | OpenCode serial sum down to about its slowest hook | Rejected. OpenCode currently runs owner-dispatch, then merge, then the advisories, and stops at the first block. Running them concurrently would let a merge grant, the one-shot source-edit checkpoint or the CLI-reminder dedup be consumed by a call that another hook denies |
| D. R11 dispatcher or an orchestrator | about 77 ms (Linux) / 44 ms (macOS) Claude Bash | Rejected. 119 findings across 11 rounds; the orchestrator design review returned 28 |

**Decision: A.**

## Changes

1. **Engine: `scripts/owner-dispatch/owner-dispatch.sh` (`cmd_pretool`).**
   - Read `session_id`, `agent_id`, the `agent_id` key, `tool_name`, `tool_input.command` and the edit path with one `jq` call that emits shell assignments via `@sh`, so NUL, newlines and quotes cannot shift fields.
   - Then strip trailing newlines from each value, as `$(...)` does today.
   - The injective key is still computed by `jq` (`@base64`, then `tr '+/' '-_'`) from the original JSON value.
2. **Merge guard: `hooks/guard-merge-authorization.sh`.** Read `tool_input.command`, `cwd`, `session_id` and `transcript_path` the same way. The jq and git presence checks and their degrade messages are unchanged.
3. **`hooks/guard-broad-local-test.sh` and `hooks/guard-edit-isolation.sh`.**
   - Merge their two `jq` reads into one, in the same form.
   - The edit guard's Python-free path (jq and git only) stays.
   - `host-input.py` and its `paths` output contract are not touched.
4. **Not changed:**
   - `hooks/hooks.json`;
   - `agy-bridge.py`;
   - the OpenCode plugin;
   - `skill-loading.py`;
   - every verdict, message and state file.

The work starts on a new branch from `origin/main`. The R1–R11 code is not carried forward; it stays reachable from the archived ref `archive/pretool-dispatch-r11` (`6ae8038`). Bugs on main that the reviews found go to a backlog, not this change:

- the SHA-256 health check in the merge guard;
- callID-less edit notices;
- symlinked path components in installers;
- leaf-symlink deletion in edit isolation.

### Field-read constraints

The differential test pins each of these.

- **Every field is a scalar string.** Each field is read as `(.x // "<default>") | tostring`, with the same default main uses (`nosession` for `session_id`, empty otherwise). A non-string value is converted the way `jq -r` prints it today.
- **NULs are removed in `jq`.** Before `@sh` quotes a value, `jq` deletes NUL (`gsub("\u0000"; "")`). That matches what bash's `$(...)` does to main's output today.
- **Trailing newlines are stripped after assignment**, matching `$(...)`.
- **The edit guard keeps its own reads.** Its trailing-newline-preserving path extraction and its malformed-patch flag are not merged. Only reads whose main form is `$(... | jq -r ...)` are merged, so a target list that is empty but malformed is still flagged.
- **Failures keep their branches.** A `jq` failure (malformed payload) takes the same branch as main's first failing read.

## Security questions

1. **Caller-controlled input:** the tool payload.
2. **Damage if forged:** a field decoded differently from main could change a verdict or skip recording state. The differential test below exists for that.
3. **Trust root:** unchanged.
4. **Negative tests:**
   - payloads with `\u0000`, embedded and trailing newlines, quotes and non-ASCII in every read field;
   - a landing command must still be denied.

## Quality checks

- **Domain model, observability, user experience:** not applicable. No new state, signals or rendered surface; messages are unchanged.
- **Performance:** applicable.
  - *Method:* `hook_latency.py` on the Linux and macOS hosts, main versus candidate, in the same run.
  - *Acceptance:* on Linux, main-parallel Bash and Edit each drop by at least 40%; on macOS, neither gets slower. Serial Bash (OpenCode and agy) is recorded too.
  - *Harness behavior:* paths are resolved before a hook runs, and a run whose hook exits non-zero or prints a degrade message is rejected, not timed.
  - *Recording:* results in `evidence/validation.md` with both revisions.

## Tests

| Layer | Decision | Command |
| --- | --- | --- |
| differential | add | `hooks/test_hook_field_reads.py`, registered in `make test-repo-gates`. It runs each changed script from pinned baseline `788470c` (stored as expected outputs, so a shallow clone works) and from the candidate. Both sides use the same temporary paths. It compares:<br>• stdout, stderr and exit code;<br>• engine activity markers for a real gated edit in an opted-in fixture repository, plus the following `owner-dispatch-stop.sh` verdict;<br>• merge-grant consumption: an armed grant is consumed once by a landing command and not by a denied one |
| hook suites | run | the existing suites for each changed hook, plus `scripts/owner-dispatch/test.sh` and `hooks/test_agy_bridge.py` |
| full | run | `CCL_BROAD_TEST_REASON=repo-required make test`, `make npm-publish-dry`, `npm test`, `npm run smoke:host` |
