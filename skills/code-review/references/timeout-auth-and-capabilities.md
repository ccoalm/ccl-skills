# Wait Policy Details, Auth Pitfalls, And CLI Capability Notes

Load this file when a wrapper run times out, returns an auth-path failure,
or when maintaining the wrapper's CLI-flag adoption. The hard rules —
timeout/no-output is inconclusive and never approval, auth failures are
classified by evidence, raw `claude -p` never substitutes for the wrapper —
live in `SKILL.md`; this file holds the operational detail.

## Wait Policy

Do not use a 30 second timeout as a review failure.

- Around 30s with no output: wait.
- Around 60s with no output: treat as a possible slow or broad review, not approval. Keep waiting if the process is still active.
- For narrow diff reviews, allow roughly 2-3 minutes before calling it stuck.
- For broad product/architecture reviews, allow roughly 5 minutes or narrow the prompt.
- Never treat no output as "no findings."

Host execution APIs may yield before the command exits. A response containing a
live `session_id`, `cell_id`, or equivalent execution handle is a progress
response even when its current output string is empty. Resume the same handle
with the host's polling primitive (`write_stdin`/poll for a unified exec session,
or `wait` for a yielded cell) until it reports a terminal exit. Do not start a
second reviewer, enter fallback, or call the partial chunk "empty reviewer
output" while that handle or its child process is alive. If orchestration loses
the handle, the lane is infrastructure-inconclusive/manual-review-required and
no replacement or fallback may be started or credited. The original PID/process
tree and wrapper-owned result artifacts may be inspected for diagnosis only;
they cannot reconstruct the missing terminal result or authorize continuation.
For every yielded run, the caller's lane evidence must record the handle type,
an opaque host transcript/tool-call reference (never copy a credential-like raw
handle into shared evidence), and terminal exit status. If the handle was lost,
record the lost state, any diagnostic process-tree or wrapper artifacts, and
that fallback was unavailable.
This is a procedural host-workflow obligation, not a controller-owned field:
the outer host allocates the handle after launching the gate, so the inner gate
cannot observe or authenticate it. Hosts that need mechanical enforcement must
provide their own trusted execution adapter; this repository preserves the
contract and evidence shape without claiming that enforcement.

The wrapper default timeout is 600 seconds per formal invocation, matching the
accepted maximum. Measured single-lane costs on this repository's own review
diffs were roughly 89, 247, and 419 seconds, so a smaller default silently
converts a working reviewer into an inconclusive timeout; because a timeout is
cascade-eligible, spending wall-clock is recoverable while a premature timeout
quietly loses that lane's verdict. Lower it explicitly with `--timeout` when a
fast bound matters more than lane coverage. It makes no separate model behavior-probe request. Challenge makes one invocation; review and consult may make up to two only through their existing bounded result-recovery paths. The wrapper rejects timeout values below 5 seconds and clamps values above 600 seconds to 600 seconds. The bound is per invocation, not per wrapper run: an outer timeout must cover `timeout` for challenge and up to `2 * timeout` for review or consult, and must never kill the wrapper and then treat the killed output as success. With defaults, allow about ten minutes for challenge and up to twenty minutes for review or consult. If the command is still running but silent, poll the same execution handle again.

The controller separately enforces a cumulative reviewer-lane budget.
`--total-timeout` defaults to 2400 seconds and accepts 5 to 3600. Its clock
starts before packet/profile setup, so setup consumes the budget. Git preflight
subprocesses use the remaining deadline; direct filesystem reads are not
preempted, so the host's outer timeout remains responsible for stuck file I/O. Before each client attempt it
passes `min(--timeout, floor((remaining total seconds - 10) / invocation count))`
to the wrapper. The invocation count is two for review and one for challenge,
matching each wrapper's maximum recovery path while reserving ten controller
seconds for wrapper overhead, cleanup, and result handling. An allowance below five seconds cannot
satisfy the wrapper contract, so the gate returns inconclusive `gate_timeout`
without starting another client. The
practical minimum before setup overhead is 21 total seconds for review and 16
for challenge; smaller accepted values intentionally produce the terminal
fail-closed result. The controller bounds each wrapper lane by the smaller of
the remaining total budget and its mode-adjusted invocation allowance plus the
ten-second headroom. On lane expiry it
terminates the process group with TERM, waits one second, then uses KILL if
needed, and bounds final descriptor closure and reap. Cleanup is bounded but may
finish just after the requested deadline. Partial or killed output is not
parsed as a verdict. A lane timeout may cascade only when the cumulative clock
still leaves the next client its minimum allowance; total exhaustion stops the
lane. With defaults, the
cumulative reviewer-lane bound is about 40 minutes plus cleanup/launch overhead,
instead of the prior four-lane worst case of about 80 minutes. Callers needing a
tighter host bound should lower `--total-timeout` and set their outer runner
above that value plus setup and cleanup overhead. Process-group termination
covers the wrapper and descendants that remain in its session; a descendant that deliberately creates a new session can
escape signaling, but cannot keep the gate waiting or supply a verdict.

Any timeout is an inconclusive result, not an empty-finding result. The final status must say `inconclusive` with the timeout reason so downstream review or merge state cannot treat the missing challenge as approval. If total expiry invalidates a result that already carried findings, the gate clears verdict-bearing fields and may preserve those findings only as diagnostic `unbound_findings`; downstream policy must not promote that field into a verdict.

The wrapper traps TERM/INT and emits an inconclusive JSON result when the shell gives it a recoverable termination signal. SIGKILL and host crashes cannot be trapped, so callers must still treat non-zero exit without valid JSON as inconclusive/manual-review-required, never as success.

## Auth And CLI Pitfalls

On this machine, Claude Code and Kimi Code may be logged in locally while a
sandboxed child cannot reach their host-owned auth paths. Classify auth failures
by evidence, not by one invocation path.

Kimi has one additional exact false-negative shape: before any model output,
preparing the OAuth refresh lock fails with `EPERM` or `EACCES` through the
private runtime-home binding. Preserve the whole source `credentials/` and
`oauth/` bindings—never copy or disable that lock—and use the same single
`--host-remediation-attempted` rerun described below. A second lock-path failure
is `auth_unavailable_after_host_retry` and may cascade; unrelated exit-1 errors
remain fail-closed.

Codex has a separate sandbox-path false negative: its in-process app-server may
fail before inference with exact `Operation not permitted` evidence while both
the event stream and result file are empty. The first occurrence is
`host_path_unavailable` and requests the same single host rerun.
Only the marked rerun may classify a repeat as
`host_path_unavailable_after_host_retry` and continue to another approved
client; unrelated Codex exit-1 failures remain fail-closed.

Use this bounded host-remediation procedure for either failure class:

1. For Claude, run `claude auth status` first. If it reports logged in, classify the failed invocation as an auth-path false negative; use `claude --version` only to confirm the binary/version when auth status is unavailable or fails.
2. For Codex, require the wrapper's exact pre-inference app-server `EPERM` classification with empty event/result evidence. Any non-empty inference evidence or broader exit-1 remains terminal.
3. Confirm a real host/outside-sandbox runner is available, such as an approved unrestricted shell path in the current Codex session. Without it, keep the gate at `next_action=host_retry`; do not reinterpret the path failure as provider unavailability.
4. Rerun the same `review_gate.sh` command through that host path with `--host-remediation-attempted`, preserving the frozen packet or unchanged base/paths, mode, focus, timeout, implementer family, and egress approval. The gate passes the bounded marker to the affected wrapper; it does not elevate itself.
5. If the host rerun returns `auth_unavailable_after_host_retry` or `host_path_unavailable_after_host_retry`, the gate may try the next client in the effective `CODE_REVIEW_CLIENT_ORDER`, subject to the egress secret-scan tripwire (a clean packet egresses automatically; a scan hit needs `--allow-fallback-egress`). If no fallback is valid, the lane remains inconclusive. Do not manually invoke raw provider commands for review/challenge as a fallback.
6. For Claude only, tell the user to log in again only if `claude auth status` also reports logged out, or the same wrapper command fails from the host/local login path. Never repeat host remediation for either client.

Do not manually substitute a raw `claude -p` command for review/challenge after an auth false negative. Raw commands are easy to leave without the wrapper's outer timeout, JSON schema validation, untracked-file handling, and fail-closed classification; a hung or prose-only raw run remains inconclusive. The only exception is wrapper debugging in the same turn: record the wrapper bug being reproduced, edit `scripts/claude_review.sh` or its parser/tests, and do not report the raw run as a review result.

For challenge mode, require `--tools ""` and the included diff packet as the whole review surface; this keeps adversarial passes bounded and avoids silent repo exploration hangs. If the installed Claude CLI does not advertise `--tools`, challenge exits inconclusive and must not be reported as passing or as no findings. The formal invocation's own stream-json init must prove the exact tool surface and empty inherited MCP/skill/command/plugin surfaces before its result can be accepted. A permission denial, unexpected tool use, missing init evidence, or schema drift fails closed; auth/quota evidence remains separately classified. If the challenge run hits an auth false negative, do not spend another Claude invocation inside the same wrapper run; report inconclusive and rerun once from the host path (optionally with `--direct`). Review mode uses the same no-tool, diff-packet-only surface. Repository consult uses `--tools Read,Grep,Glob`, `--permission-mode plan`, and `--add-dir <REPO_ROOT>`; treat those read tools as workspace scoping, not as proof that absolute-path reads are impossible, keep sensitive/harness paths outside `<REPO_ROOT>`, and fail closed if the exact positive read-only surface is unavailable. Prompt-only consult uses `--tools ""` and no `--add-dir`; it requires the needed evidence pasted into `--extra` (the legacy `--allow-prompt-only-advisory` opt-in is accepted for back-compat but no longer required), and the final JSON carries `status: "evidence_only"`, `consult_scope: "prompt-only"`, `advisory: true`, `untrusted_evidence: true`, and `gate_eligible: false` as the guard. Consult findings use scope-specific statuses: repository findings use `status: "findings"` and prompt-only findings use `status: "prompt_only_findings"`; all consult results exit `2`, all consult statuses carry `gate_eligible:false`, and prompt-only findings still require controller-side verification before they affect a landing decision. The prompt boundary is not a sandbox.

Use `--no-session-persistence` for review, challenge, and prompt-only consult when `claude -p --help` advertises it. For no-tool modes (review, challenge, and prompt-only consult), use low effort when supported, because the prompt is otherwise prone to long silent reasoning. Do not enable `--json-schema` by hand for review evidence; the wrapper pairs it with `--output-format stream-json --verbose` when supported and enforces both the runtime init record and final result through its parsers. A bare `--json-schema` without structured capture can return prose or blank stdout. Model selection remains the user's Claude CLI default; the shared wrapper does not pass a model override. Avoid changing capture flags by hand, because some modes can use a different auth path.

## CLI Capability Notes

Current Claude Code CLIs expose capabilities that *could* harden this harness, but they are machine- and version-specific and several have fail-closed implications. These notes are **policy, not a recommendation to flip flags by hand**: a capability may be adopted only inside the wrapper, behind local help/version inspection plus fixture tests that prove the same fail-closed classification, schema validation, attribution, auth hygiene, and timeout semantics the wrapper already guarantees. This local inspection is not a model inference probe. None of this changes review *policy* — when dual-track (independent fact review + adversarial challenge) is required, the convergence standard, and the severity rubric + finding-quality bar are owned by `../skill-extraction-workflow/references/dual-track-review-gate.md` and `../skill-extraction-workflow/references/review-finding-standards.md` (sibling-skill paths, written relative to this skill's directory per repo convention); this skill owns the provider-neutral client invocation mechanics.

- **`--bare` (minimal mode), when advertised**: skips hooks, LSP, plugin sync, auto-memory, background prefetches, keychain reads, and `CLAUDE.md` auto-discovery (skills still resolve), and forces Anthropic auth to be `ANTHROPIC_API_KEY` (or `apiKeyHelper` via `--settings`) — OAuth and keychain are not read. It is therefore forbidden in the normal owner-aware wrapper path, which must preserve the user's existing OAuth/keychain login through `--safe-mode` plus explicit `--plugin-dir`. Two narrow, guarded uses remain outside that normal path:
  - **Isolation**: it can suppress ambient context the Harness Exclusion section guards against — BUT only when every safety boundary the review depends on is wrapper-owned and independently enforced. Do not use `--bare` to skip hooks/plugins that themselves enforce safety (DLP, tool-deny, audit/logging, policy/model enforcement, org prompt boundaries); confirm none of the skipped mechanisms is a required control before relying on it. Skipping ambient noise is fine; skipping a guardrail is not.
  - **Sandbox auth**: the host/OAuth rerun remains the PREFERRED remedy for the keychain false-negative. `--bare` + `ANTHROPIC_API_KEY` is a security-sensitive last resort, not a default, because it pushes a credential into exactly the sandbox/review path this skill treats as hostile. Allowed only if the wrapper injects an ephemeral, least-privilege key through a non-logged env path, never writes it to settings, prompt files, logs, or shell history, and treats missing safe-injection as inconclusive rather than exporting a long-lived key. Do not adopt `apiKeyHelper`/on-disk secret config unless the wrapper owns and validates it.
- **`--output-format stream-json --verbose` — ADOPTED as the default capture**: paired with `--json-schema` when local help advertises schema support and covered by fixture tests (`test_parse_review_json.sh`, `test_classify_envelope.sh`, and `test_parse_probe_result.sh`). The stream envelope is NOT the review schema, so `extract_payload` in `parse_review_json.py` unwraps `structured_output` (or the nested `result` JSON string) and rejects any envelope flagged by `is_error`, `subtype != success`, `api_error_status`, `permission_denials`, or a non-`completed` `terminal_reason`; `classify_envelope.py` turns those same fields into auth/quota/permission/error reasons. Never let the envelope's own success shape (for example `{"result": "...LGTM..."}`) be read as a passing review. The init record from this same formal stream is also the runtime tool-surface evidence; no separate model request is made.
- **`--fallback-model`, when advertised**: auto-switches when the default model is overloaded or not available (`--print` only). When the team has an approved pinned review model, silent fallback is forbidden unless the fallback target is also explicitly approved for this harness; an unexpected fallback makes the result inconclusive / manual-review-required, not pass or no-findings. Reporting the model used preserves attribution but not approval.
- **`--max-budget-usd`, when advertised**: caps spend per invocation, but budget exhaustion is an inconclusive output condition, not a clean stop — it can truncate generation into empty, partial, or tail-only output. The wrapper must detect a budget-limit stop reason / usage metadata where available; output produced under a hit or ambiguous cap is inconclusive. Never set a cap low enough to preempt the Output Validity rules or the Wait Policy above.
