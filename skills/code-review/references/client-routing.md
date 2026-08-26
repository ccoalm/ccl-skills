# Reviewer Client Routing

Load this file when a gate-eligible `review` or `challenge` uses
`scripts/review_gate.sh`, or when diagnosing its result. `consult` remains
Claude-only.

## Order And Attribution

The gate freezes one bounded packet and verifies its SHA-256 before and after
every attempted client. A mutation stops with `binding_mismatch` before another
client runs.

The optional clients are `claude`, `kimi`, `opencode`, and `codex`. Their default
order is:

```text
claude -> codex -> kimi -> opencode
```

Teammates who prefer another order set one local variable; a subset is valid:

```bash
export CODE_REVIEW_CLIENT_ORDER=claude,opencode,kimi,codex
```

Empty entries, duplicates, and unknown clients fail before inference. There is
no per-invocation client-order flag, provider list, model list, or shared
Kimi/DeepSeek chain.

Claude maps to the Claude family, Kimi maps to the Moonshot family, and Codex
maps to the OpenAI family. These client identities are not subdivided by local
provider/model aliases. OpenCode's family is bound from the provider/model that
actually ran. Reviewer and implementer families remain attributed in the result,
but a match is allowed and never causes a preflight skip or postflight rejection.
The implementer family must describe the model that produced the candidate, not
merely the host agent; it remains audit metadata and a compatibility input for
existing callers, not an eligibility gate.

Kimi validates its runtime before it creates or seeds a private runtime home. A
runtime copy or permission failure is client-local `client_unavailable`
and may continue to the next configured reviewer after cleanup.
Binary discovery and configuration-home selection are intentionally independent:
a standard binary may use a custom `KIMI_CODE_HOME`; set an absolute `KIMI_BIN`
when the binary itself must be pinned.

## Continuation Rules

A valid `passed` or `findings` result ends the lane. A client-local failure may
continue only when its wrapper marks it eligible and its `reason_code` is one
of: unavailable client/provider (including non-Claude local authentication),
quota/rate limit, timeout, missing capability, or malformed model output that
contains no concern evidence. If malformed output still contains a severity and
file/line-shaped concern, the lane stops so another client cannot launder that
finding into a pass.

Kimi keeps composed prompts up to `MAX_INLINE_PROMPT_BYTES` inline. Larger
packets, up to the wrapper's global packet limit, use a private explicit agent
that exposes only a generated stdio MCP server's
`read_packet(byte_offset, max_bytes)`. Candidate bytes never enter the agent
system prompt or process argv. The tool accepts no path, rechecks the frozen
packet SHA-256 on every call, and returns UTF-8-safe chunks with exact byte
ranges until the parser proves complete coverage. The parser verifies every
chunk body against the frozen packet bytes, so even a physical line larger than
one bounded 48 KB tool result remains reviewable without trusting claimed
offsets. Non-UTF-8 large packets still degrade before alternate delivery. The
gate never synthesizes candidate-wide claims from partitions.

`EMFILE` or `too many open files` from either Kimi preflight or the formal run is
classified as fallback-eligible `kimi_host_resource_exhausted` with
`client_unavailable`. It is a local CLI/runtime failure, not OAuth, provider
authentication, or a model verdict.

Packet/input/binding/tool-boundary failures are terminal. Unknown errors and
legacy inconclusive objects without machine fields are also terminal. Claude or
Kimi `auth_path_unavailable`, and Codex's exact sandbox-only in-process
app-server `EPERM` as `host_path_unavailable`, request one host rerun of the same
gate and packet with `--host-remediation-attempted`; the gate never elevates
itself. Kimi emits its code only for an exact pre-inference OAuth refresh-lock
`EPERM`/`EACCES`. A second Codex occurrence becomes
`host_path_unavailable_after_host_retry` and may cascade; other Codex exit-1
failures remain terminal. A different non-Claude authentication failure remains
a candidate-local provider failure and may continue to the next approved client.
An operator interrupt (`TERM`, `INT`, or `HUP`) is terminal and never starts a
different client.

The result records `client_order`, `selected_client`, `attempts`, and
`skipped_clients` with preflight/attempt/postflight stages. Exit `0` means one
fully validated review/challenge verdict; exit `2` means inconclusive. Review
and challenge remain separate lanes. `packet_sha256` identifies the gate's
frozen input and is assigned by the gate; it is not a provider-signed echo or
an attestation of transport internals.

## Invocation And Egress

```bash
scripts/review_gate.sh \
  --mode review \
  --stage build \
  --review-plan-file /absolute/review-plan.json \
  --cwd /absolute/repository \
  --base origin/main \
  --implementer-family openai \
  --allow-fallback-egress
```

This shape is a single untracked round only while the effective challenge budget is
0; at release depth, or under a risk tag that raises depth there, the gate rejects it
and requires the tracked review→challenge pair. Agent multi-round automation must
likewise open the chain on the initial review, per
[`staged-review-contract.md`](staged-review-contract.md) (Agent review chain) and
the runnable pair in this skill's `SKILL.md`.

The plan file is optional for review and challenge; when supplied it must
satisfy [`staged-review-contract.md`](staged-review-contract.md), and when
omitted the gate synthesizes a derived default and stamps
`review_plan_source=derived-default` (`complete` mode still requires an explicit
plan). The gate freezes its controller-rendered profile alongside the candidate
and verifies both hashes before and after every attempted client.

Non-Claude egress is governed by a secret-scan tripwire. The gate scans the
frozen packet for high-signal credential material: a clean packet may egress to
any non-Claude client in the effective local order automatically, while a scan
hit denies that client (`egress_denied`) unless `--allow-fallback-egress`
approves it. The result's `egress.secret_scan` lists the categories hit (empty
when clean) and `egress.approval_flag` records whether the flag was passed.
Egress delivers both the frozen candidate and the rendered review profile,
including intent, acceptance criteria, self-review conclusions, and evidence
text. Set
`CODE_REVIEW_CLIENT_ORDER` to a subset when either artifact may go only to
specific clients. Approval must follow the data-egress rules in `SKILL.md`:
scrub live credentials, customer PII, or regulated content, or keep both
artifacts in-boundary.

## Model Ownership

The shared repository never chooses a provider or model:

- Kimi is uniformly treated as the Moonshot family and uses the user's ordinary
  CLI model selection. It does not pass `--model` or subdivide provider/model
  identity.
- Codex is uniformly treated as the OpenAI family and uses the user's ordinary
  CLI model selection. It does not pass `--model` or subdivide provider/model
  identity.
- OpenCode runs the `ccl-review` agent without `--model`. A local
  `agent.ccl-review.model` wins when configured; otherwise OpenCode selects
  its ordinary default.

`opencode debug agent ccl-review` returns the agent's configured model or
`null`; it is not a general default-model resolver. The wrapper therefore binds
the exported review session's actual provider/model. When debug reports a
configured model, the export must match it. Every assistant message must remain
on the same actual provider/model. The local boundary probe uses at most 60
seconds of the controller-granted wrapper timeout, and its elapsed time is
charged against later run, retry, and export calls. Each call receives only the
remaining wrapper timeout. Model runs also reserve 10% of the original budget,
clamped to 3–10 seconds, so a completed session still has bounded time to export
the verdict after a run-tail timeout. Timeout-tail recovery additionally
requires the export's final assistant message to contain the exact frozen set
of required concern conclusions; an ordinary stop/sentinel without that bound
coverage remains a timeout. Legacy calls with no frozen concern set therefore
never recover a verdict from exit 124.

To make OpenCode reviews use a different model from everyday OpenCode work,
configure only the local agent entry, using provider/model names that exist on
that machine:

```json
{
  "agent": {
    "ccl-review": {
      "model": "your-provider/your-review-model"
    }
  }
}
```

If the entry is absent, leave it absent; the wrapper deliberately does not
invent a default.

Executable discovery does not select a provider or model. The Kimi wrapper
uses an absolute executable `KIMI_BIN` when explicitly set; otherwise it checks
`PATH`, `$KIMI_CODE_HOME/bin/kimi` when configured, and finally
`~/.kimi-code/bin/kimi`, the standard Kimi Code install path. Every resolved
path must be absolute and executable before the wrapper changes workspace. A
relative PATH hit is ignored and discovery continues to the validated home
candidates; an explicit relative, missing, or non-executable `KIMI_BIN` fails
before inference. An executable PATH hit keeps normal shell precedence;
operators bypass a broken executable shim with explicit `KIMI_BIN`.

## Client Tool Boundaries

Claude owner-aware review takes a bounded host-vocabulary baseline before the
formal invocation. The baseline uses the same resolved Claude executable with
an independent empty working directory and no tools, plugins, MCP servers,
settings, workspace instructions, custom commands, agents, or user skills. Its
model result is ignored; only the init event is used. The wrapper also requires
the installed CLI's own `--safe-mode` help contract to state that skills are
disabled; if an upgrade removes that contract, this lane refuses and may
cascade instead of treating user vocabulary as host vocabulary. The formal
init may reuse unique whole-string baseline commands only when each name is
either bare or an already pinned built-in with a non-bare spelling, and both
events report the same CLI version. Baseline-reported skills never grant
formal-run authority: a new skill remains fallback-eligible until it is pinned
as a reviewed built-in or selected by the controller. `terminal_slash_commands`
must be a unique plain-string subset of the declared slash commands.

The baseline and formal invocation share one caller-granted timeout budget.
Baseline elapsed time, including validation, is deducted before the formal
call; if no whole second remains, the Claude lane reports a fallback-eligible
timeout instead of extending the controller deadline.

The baseline never weakens the executable boundary. Any baseline tool, plugin,
MCP server, permission change, malformed entry, or unknown non-empty surface
invalidates the lane. The formal invocation still rejects tools, authority
drift, namespaced customizations, and host names absent from its baseline. A
version mismatch or an unbaselined bare host identifier refuses this Claude
lane but may cascade as unverified capability drift; a proven tool, authority,
or customization breach remains terminal.
Owner-free review disables slash commands and does not need this probe. Routine
Claude built-in command changes therefore do not require a repository allowlist
update. A new skill, tool, authority mode, or unreviewed schema may still make
the Claude lane unavailable by design because those surfaces can carry
capability rather than display-only vocabulary.

Kimi retains the user's credentials and ordinary provider/model settings by
seeding a private writable runtime home from the validated source home. Session,
log, history, telemetry, update, workspace-index, binary, hook, MCP, plugin,
skill, agent, and `AGENTS.md` inputs are excluded so the formal reviewer cannot
inherit executable extensions. Controller-selected native skill names must
match the package-name grammar before they can enter the generated agent body.
The `credentials/` and legacy `oauth/`
directories are never copied: each validated one is linked back to its
user-owned path, because the CLI persists OAuth credentials with an atomic
tmp/fsync/rename write and uses the legacy path for cross-process refresh
locking. A private copy or private lock would silently discard rotation or
split mutual exclusion. A
validated home without a credential directory
(configuration-marker-only) has no credentials to rotate, and the
non-interactive review lane cannot complete an interactive OAuth login, so
nothing credential-bearing is lost there. The wrapper never creates
credential directories in the user's home; a validated home with only one of
the two directories links that directory alone. If the CLI then writes the
sibling path during the run (a legacy-token migration between credential
paths), the write lands in the discarded runtime home and the run is
terminal `kimi_credential_dir_created` on a writable home — deliberately
loud, with the operator remediation of running the CLI once interactively so
the migration persists before re-running the review — and cascade-eligible
`client_unavailable` on a non-writable home, where the write was never
persistable. A symlinked `credentials/`
or `oauth/` entry is resolved to its real directory and the runtime name
links to the resolved path, so a relocated credential store keeps working
provided the home is still independently recognizable as a Kimi home — the
entry marker gate accepts only a kimi/moonshot `config.toml` marker or a
`kimi-code*` marker file under a non-symlinked credential directory, so a
home whose only marker sits behind the relocated symlink fails
`invalid_kimi_home` and cascades before the resolve-and-link phase; a
resolution outside the source home must point at a credential-shaped tree (a
non-linked `kimi-code*` or `mcp` entry), and an entry that is a regular file
or a symlink that does not resolve to a real directory is rejected before
inference as fallback-eligible `client_unavailable` rather than silently
omitted. Binding integrity is verified before run-failure classification,
matching the packet-mutation check: a replaced or missing credential link, a
drift toward more permissive bits on the linked directory, or an unlinked
credential entry (a file, directory, or symlink) created during the run is terminal
`binding_mismatch` against the exact seed-time recorded link set, even when
the run itself fails for a recoverable reason. The wrapper never chmods
user-owned credential state: it cannot distinguish a session fault from a
deliberate concurrent user change, so a drift toward more permissive bits is
reported terminally as `kimi_credential_mode_loosened` and remediation is
left to the owner, while a tightening or same-permissiveness difference is
cascade-eligible `kimi_credential_mode_changed` and never reverted. Mode
comparison machinery failure is checked again with an independent shell bitmask:
confirmed loosening stays terminal, confirmed non-loosening is cascade-eligible
`kimi_credential_mode_check_failed`, and an unclassifiable fallback is terminal.
Mode
verification covers the top-level credential directory only; nested
directory modes and file content stay inside the trusted-input boundary. A
post-run credential scan that itself fails (an unreadable subtree) is
cascade-eligible `kimi_credential_scan_failed`, not a binding replacement. Known
residuals, accepted by the risk owner at landing: the loose-file baseline is
newline-delimited, so a credential filename itself containing a newline can
misattribute the baseline (such names are outside any realistic credential
configuration); and a resolution fault while seeding an ordinary entry is
reported as `kimi_runtime_home_copy_failed` (correct cascade classification,
imprecise reason label). The
created-directory case is gate-terminal by design, not cascade-eligible: a
packet-only review lane has no legitimate path that writes fresh OAuth
credentials, so a new credential directory is both anomalous and
unpersistable, and crediting that run would report a silent credential loss
as green; the valid review result is deliberately discarded with it. On a
non-writable source home the same artifact is instead cascade-eligible
`client_unavailable`, because the write was never persistable there.
Cleanup
never follows the links or repairs permissions through them. Content inside the linked store is
a trusted-input boundary exactly like the OpenCode `auth.json` link: the
wrapper deliberately keeps no snapshot, because restoring one could revert a
legitimate rotation. Non-credential mutable runtime state never
requires writes to the source home. The source must be a directory with a
non-symlink Kimi-specific
marker: `config.toml` with a Kimi/Moonshot `default_model`, provider, or model
entry, a bare `default_model` paired with a Kimi/Moonshot `base_url`, or a
non-symlink `credentials/kimi-code*` or `oauth/kimi-code*` file.
Comments and unrelated free text do not count. A missing, uninitialized,
or broad unrelated path fails this client before copying or inference and remains
eligible to continue to the next configured client. Top-level symlinks are never
seeded into the private runtime home. Recursive copies preserve nested symlinks
without dereferencing their targets and preserve regular-file source modes;
owner-write repair applies only to real directories, not regular files or symlink
targets. The wrapper registers removal of the private home before
seeding, restores removal access on real runtime directories during cleanup,
including partial copy failure and trappable signal paths, and emits at most one
terminal inconclusive result when those paths overlap. `SIGKILL`
or a host crash cannot run cleanup and may leave the private home in `TMPDIR`;
operators treat that as infrastructure cleanup evidence, never review success.
The formal run removes inherited hooks, permissions, MCP, plugins, skills,
agents, and workspace instructions from the private runtime. Its generated
config preserves only provider, model, and thinking settings, then installs a
non-matching global tool allowlist for no-tools delivery. `kimi doctor config`
validates that config. For both inline and MCP delivery, a bounded cooperative
probe attempts forbidden Read/Glob/Grep calls and rejects any observed tool
activity before candidate content is sent; MCP's one packet reader remains
separately constrained by the generated agent, server, and formal parser.

Packets at or below 16 KB stay in the no-tools prompt. Every larger packet uses
a mode-0600 explicit agent whose frontmatter enables only
`mcp__code_review_packet__read_packet`; candidate bytes remain in the private
packet file rather than gaining system-prompt authority. Generated MCP config
binds its pathless server to the one private packet path and hash. The wrapper
hashes the frozen packet and every generated agent/MCP artifact before and
after inference.
It also executes the server's packet validation before Kimi starts, including
the UTF-8 chunk bound. The agent/MCP user prompt never reveals the packet
receipt; the reviewer must obtain it from the packet tail. Mutation is terminal
`binding_mismatch`.

The stream parser accepts only safe Kimi metadata and final assistant text for
no-tools transports. MCP delivery additionally accepts only the exact pathless
tool schema and packet-matching byte chunks; arbitrary paths, other tools, and
incomplete coverage are terminal. A verdict is accepted only when its first
line echoes the packet-specific receipt and the remaining text matches the
review contract. Pre-inference setup and the capability probe are charged
against the controller-granted lane budget, and the probe itself is capped at
60 seconds. MCP review receives
the remaining budget up to the wrapper's existing 600-second ceiling; inline
review is additionally capped at 120 seconds because its bounded prompt remains
visible in process argv. Both
use a one-second forced-kill grace; a deadline timeout may cascade, while an
early process signal remains terminal operator interruption. Generated-config or
unsupported explicit-agent input failures remain explicit inconclusive results.

Codex retains local config/rules/skills as trusted workstation inputs, receives
the complete prompt over stdin, and runs `read-only`, `ephemeral`, and outside
the candidate repository. Each selected owner must exist as a structurally safe
installed package, but a newer installed CCL release is accepted by name
instead of being compared byte-for-byte with an older candidate branch.
Packet-only review resolves past a cmux launcher shim,
requires the exact `exec --disable hooks` capability, invokes it, and sets the cmux
hook opt-out defensively. The capability probe runs
`exec --disable hooks --help` and requires successful non-empty help output under the same five-second
deadline plus one-second forced-kill grace. The formal Codex invocation applies
the configured timeout plus the same forced-kill grace. Both wrappers call one
shared deterministic classifier: exit 137 is timeout only when elapsed whole
seconds exceed the configured deadline, while deadline-edge or earlier SIGKILL
remains terminal.
If Codex cannot initialize its in-process app-server only because the sandbox
returns `Operation not permitted`, and both its event stream and result file
remain empty, the wrapper returns
`host_path_unavailable`; the controller requests one host rerun of the same
packet. The marked rerun converts the same error to
`host_path_unavailable_after_host_retry`, which may cascade. No broader exit-1
pattern receives this treatment.
Its JSON event stream is audited; command, MCP, web, or
other model tool activity invalidates the result. The exact diagnostic that skill
descriptions were shortened to fit the 2% skills context budget is ignored as a
non-tool item at any stream position. A hook-trust-bypass diagnostic is terminal
`tool_boundary_violation`, because host hooks execute outside the model tool-event
audit. Every other unknown `error` item stays fail-closed even when the last-message
file is valid, including the existing protection against discarding earlier
concern evidence.

OpenCode uses a private XDG data/state runtime for logs, sessions, and state.
Only `auth.json` is linked to the user's normal credential file so a rotated
OAuth refresh token is not stranded in a deleted private copy. The link is
checked after every public debug/run/export command; replacement is terminal.
The temporary `ccl-review` agent denies every built-in, plugin, and MCP tool by
wildcard, then permits native skill loading only for the controller-selected
skill names. The complete diff is already attached to the prompt, so workspace
read/glob/grep access is neither needed nor available. The debug-agent boundary
must resolve with `skill` as the only enabled capability when owner skills were
selected; a zero-owner run requires `skill` to remain disabled. The parser gets
that controller-owned expectation explicitly, so it cannot weaken an
owner-aware run. OpenCode's inert `invalid` pseudo-tool may also be present
because it only reports rejected tool calls. Boundary proofs, event streams,
exports, and stderr stay outside the agent project directory.

If `opencode run` reaches its deadline but the public session export already
binds the same session/provider/model, the event stream itself ends with a
matching `step_finish`/`step-finish: stop`, and the export contains the same
final stop plus schema-valid review text, the parser accepts that verdict and
records `transport_tail_timeout: true`. Export-only completion or any other
incomplete evidence remains a timeout and may
retain only the existing bounded, explicitly requested diagnostic evidence.
HTTP 401/402/429 provider errors can arrive anywhere in a multi-event stream
while stderr stays empty. The wrapper examines the entire bounded stream, so a
later unrelated error cannot erase an earlier authentication, quota, or billing
failure. Those failures remain fallback-eligible instead of becoming terminal
`transport_unverifiable`.

The OpenCode debug-agent surface is a mandatory local structural check; it does
not invoke a model. OpenCode has no separate behavior-canary request. The formal
review session and its export are the only model inference path.

OpenCode calls use separate project/event/export and private XDG paths, so they
run concurrently. The wrapper does not create a shared process lock or expose a
serialization setting.
