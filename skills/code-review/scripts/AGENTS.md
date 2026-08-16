# skills/code-review/scripts Agent Contract

Scripts here provide bounded, provider-neutral review/challenge wrappers and
parsers for Claude, Kimi, OpenCode, and Codex.

Rules:

- Preserve no-tools posture and structured output validation. A malformed,
  timeout, or inconclusive wrapper result is not a pass.
- **Never pin the parser to a CLI version's vocabulary.** `parse_probe_result.py`
  gates on *shape*, not on field/value names: the isolation proof is the exact
  `tools` allowlist plus the tool_use scan, which no init field can bypass.
  Field-name and value whitelists were tried twice (`fast_mode_state`, then
  `capabilities`) and both times a routine CLI release took every Claude lane
  down while proving nothing. So: unknown init fields are tolerated when scalar
  or empty-container, and `agents`/`capabilities` are list-of-strings checks
  with no value vocabulary. Only `permissionMode` stays value-pinned (it widens
  what the runtime may do with no tool added).
- **Keep unsafe *values* out of the schema-drift class.** An unrecognized shape
  means this lane cannot verify isolation → fallback-eligible. A known field
  carrying an unsafe value (`permissionMode: "bypassPermissions"`) is a breached
  boundary → terminal. They report through different reasons and different
  buckets (`unknown_fields` vs `unsafe_values`) precisely so a real privilege
  escalation cannot inherit the drift class's softer `next_action`. Any new
  value-pinned field goes in `unsafe_values`.
- When every Claude run goes inconclusive with "unrecognized surface-shaped init
  field", the CLI added a NON-EMPTY list/dict under a name the parser does not
  know — the one shape that could carry a new invocable surface. That reason is
  fallback-eligible (`capability_missing`), not a terminal boundary violation,
  so review routes to another client meanwhile. Recipe: (1) capture a normal
  wrapper invocation and diff its formal review stream's init event against the
  parser's known fields; do not add a separate inference probe; (2) decide
  whether the new container is a model-invocable surface — if it is, it belongs
  in the required-empty set, not the allowlist; (3) if it is host metadata, add
  the name to `KNOWN_SAFE_INIT_METADATA_FIELDS` (or give it a shape check),
  never a value whitelist; (4) add RED/GREEN fixtures to
  `test_parse_probe_result.sh` and record the RED round in the slice's own plan
  under `specs/` (see `specs/012-challenge-index-default/plan.md` under
  "Test / register coverage" for the shape); (5) full dual-track before landing.
- **A fail-closed stop must carry the evidence that justifies it.** When a lane
  refuses to cascade *because* the output may hold a real finding
  (`concern_evidence`), a boolean plus a fixed reason string is not enough: the
  operator is told a finding exists but not what it says, so the documented
  reject-and-rerun remediation runs blind and a false positive is
  indistinguishable from a real one. Emit a bounded, line-selected excerpt
  (`concern_excerpt.py`) — matched lines only, never the raw verdict, which may
  echo the packet and would widen the evidence row past the class a schema-valid
  `findings` result already persists. Wrapper run dirs are deleted on exit and the
  gate unlinks the frozen packet, so anything not in the emitted payload is gone;
  the OpenCode timeout path may additionally retain only its explicitly requested,
  curated private diagnostic copy under the contract in
  `../references/timeout-auth-and-capabilities.md`.
  `test_concern_excerpt.sh` is the firing path; keep new stop paths covered by it.
- **Timeout diagnostics separate portable summary from sensitive raw evidence.**
  The ordinary payload may keep bounded counts/types/booleans needed to classify
  a stall, but never raw event, log, prompt, diff, session-id, credential, or model
  text. Raw OpenCode artifacts require an explicit private diagnostic directory,
  restrictive permissions with no extended ACL, a sensitivity marker,
  caller-owned retention, and a test proving credential bindings are excluded.
  A requested owner profile alone
  does not prove a native-skill stall: require positive structured stream-part
  evidence or keep the generic timeout classification.
- Keep review and challenge lanes distinct; do not let one satisfy the other.
- Do not execute target-repo code or grant broad tools from the reviewer lane.
- Parser changes need tests with positive, finding, malformed, and inconclusive
  cases.
- A recipe step here must never cite a repo path that does not exist in this repo — for the specs/ namespace that is now machine-checked and blocking — and a step whose target is absent is not a step, because a contributor cannot run it. Backticked paths in prose are invisible to `check-markdown-links.py`,
  which resolves only Markdown inline-link destinations in tracked `*.md`; the
  gap that leaves is now closed for one namespace by
  `scripts/check-spec-references.py`, which runs in `make test` and CI and fails
  when a backticked specs/ token does not resolve. Verify each cited path
  resolves before landing, and when one is already dead, repoint it at what the
  repo does rather than creating the missing target — back-filling it fabricates
  evidence for a round nobody ran.
- **A path TEMPLATE is not written as a citation.** That checker has no
  exemption: a backticked token beginning specs/ must resolve, full stop, because
  the exemption that used to carve out angle-bracket shapes produced five
  separate bypasses and was deleted. Write a shape by naming it without the
  prefix and leaving the prefix in prose — a `<NNN>-<slug>/plan.md` file under
  specs/ — or put it in a fenced block. Keep the backticks: an unbackticked angle
  bracket is swallowed as an HTML tag when the Markdown renders.

Validation:

- `bash skills/code-review/scripts/test_classify_envelope.sh`
- `bash skills/code-review/scripts/test_concern_excerpt.sh`
- `bash skills/code-review/scripts/test_claude_review_probe.sh`
- `bash skills/code-review/scripts/test_parse_opencode_review.sh`
- `bash skills/code-review/scripts/test_parse_probe_result.sh`
- `bash skills/code-review/scripts/test_parse_review_json.sh`
- `bash skills/code-review/scripts/test_opencode_review_retry.sh`
- `bash skills/code-review/scripts/test_opencode_review_concurrency.sh`
- `bash skills/code-review/scripts/test_review_gate.sh`
- `bash skills/code-review/scripts/test_review_client_order.sh`
- `bash skills/code-review/scripts/test_cli_review_wrappers.sh`
- `python3 skills/code-review/scripts/test_kimi_packet_mcp.py`
- `python3 skills/code-review/scripts/test_review_client_compat.py`
- `bash skills/code-review/scripts/test_code_review_identity.sh`
