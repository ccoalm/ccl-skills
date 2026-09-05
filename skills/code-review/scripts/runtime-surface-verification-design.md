# Formal-invocation runtime verification design

## Decision

Claude and OpenCode do not make a separate model request to test tool behavior.
A cooperative canary describes only that response, adds latency and cost, and
cannot turn the wrapper into a hard sandbox. Gate evidence comes from the formal
review/challenge invocation itself.

Kimi and Codex already follow this shape: each uses one formal invocation and
audits its own event stream. OpenCode additionally runs the non-inference
`opencode debug agent ccl-review` command to resolve its configured tool
surface and optional model before the formal session.

## Claude evidence

The formal Claude stream must contain a parseable `system/init` record. The
runtime judge requires:

- the exact expected built-in tool set (`StructuredOutput` only for schema-based
  packet modes; `Read,Grep,Glob` plus `StructuredOutput` for repository consult);
- an empty `mcp_servers` list;
- only reviewed init metadata fields and values, where `slash_commands`,
  `terminal_slash_commands`, `skills`, and `plugins` are vocabulary that may
  hold any value;
- no tool invocation outside the expected set;
- a structurally clean result envelope with no error, API status, permission
  denial, auth, or quota signal.

Missing init evidence, malformed JSONL, unknown fields, unexpected tools, and
permission denials fail closed. `parse_review_json.py` separately validates the
review payload and requested mode.

## OpenCode evidence

Before inference, `debug agent ccl-review` must resolve the required read
tools and explicit `false` values for known write, execution, network,
interactive, and subagent tools. If it resolves a configured model, the formal
export must match it. A null model is valid and leaves default selection to the
user's OpenCode configuration.

The formal run then binds one session ID to one export. Every assistant message
must use the same provider/model, the exported family must differ from the
implementer family, and only a stop-finished schema verdict may pass. No probe
session or probe export exists.

## Verification

- `test_claude_review_probe.sh` asserts one formal invocation and validates its
  exact argv/runtime surface.
- `test_parse_probe_result.sh` exercises the stream-init and tool-use judge.
- `test_opencode_review_retry.sh` asserts one conforming formal invocation and a
  maximum of two only for bounded format repair.
- `test_opencode_review_concurrency.sh` proves two wrappers overlap and export
  exactly their two formal review sessions.
