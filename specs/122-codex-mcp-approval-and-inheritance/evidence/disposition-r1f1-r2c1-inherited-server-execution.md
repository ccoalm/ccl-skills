# Disposition — inherited MCP servers can execute during a review

Occurrences: review round 1 finding 1 (P1), challenge round 1 finding 1 (P1),
and the re-review finding 1 (P1), all against
`skills/code-review/scripts/codex_review.sh`.

Disposition: **fixed.** An earlier version of this file recorded the finding as
an accepted tradeoff; that is superseded. The reviewer now runs from a private
`CODEX_HOME` that never carried the user's MCP servers, so there is no foreign
server to reach.

## The finding was correct, and stronger than first stated

The implementer's original security answer claimed a foreign tool call "is
still terminal" because `audit_codex` rejects such a stream. A controlled probe
refuted that:

- With the wrapper's exact flags, the host's own `node_repl` server ran its
  `js` tool to completion during a packet-only review, executing arbitrary
  JavaScript that read files from disk. MCP servers run outside the CLI
  sandbox, so `--sandbox read-only` and `--disable shell_tool` do not reach
  them, and the parser's refusal happens after the call has completed.
- Auto-approval is not a gate either. `node_repl` declares
  `readOnlyHint: true` on `js`. A purpose-built stub that appends to a file was
  refused before execution without that declaration and auto-approved *with*
  it. A server therefore opts itself into auto-approval by asserting it is
  read-only, and the CLI trusts the assertion.

## One claim from the earlier draft is withdrawn

That draft added that "a hostile diff or a hostile tool description is a path
to invoking them." Two attempts to induce the call from inside the reviewed
diff did not reproduce it — on the previous wrapper and on the mid-round one —
because the prompt's untrusted-data framing held. The claim is withdrawn as
unsupported. What the probes do support is that a foreign server is reachable
and executable, which is enough to act on and does not depend on how
persuadable a model is.

## One correction about the baseline

`origin/dev` was not admitting foreign servers. Its per-name disable works for
a server the user's configuration declares and fails only for a
plugin-contributed one, where it dead-ends the whole preflight instead. The
finding therefore describes the mid-round candidate, not the baseline:

| Version | Lane usable | Foreign servers reachable |
| --- | --- | --- |
| `origin/dev` | no on any plugin host | no |
| mid-round candidate | yes | yes |
| private home | yes | no |

## The fix

A private `CODEX_HOME` under the run directory: a linked `auth.json`, a
model-preference file, copies of the selected owner skills, nothing else. Not
disabling anything, not naming anything — the servers are simply not in the
home this run uses. Routes measured and rejected on the way: a global
`apps._default.default_tools_approval_mode` did not override the `readOnlyHint`
auto-approval, and `--disable plugins` would disable the reviewer's own
installed skill registry while leaving user-declared servers untouched.

Evidence: `mcp list` over a source home declaring a foreign server returns that
server, while a wrapper run over the same source home returns a verdict — which
the preflight's single-enabled-server assertion would have refused had the
server reached the private home. The suite carries the same property as a
deterministic regression, RED against the mid-round wrapper.
