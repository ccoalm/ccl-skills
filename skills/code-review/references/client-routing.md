# Reviewer Client Routing

Load this file when a gate-eligible `review` or `challenge` uses
`scripts/review_gate.sh`, or when diagnosing its result. `consult` remains
Claude-only.

## Order And Exclusion

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

Before inference, the gate or client wrapper excludes a known same-family
candidate and records it in `skipped_clients`. Claude maps to the Claude family,
Kimi maps to the Moonshot family, and Codex maps to the OpenAI family. These
client identities are not subdivided by local provider/model aliases. OpenCode's
family is bound from the provider/model that actually ran. If a reviewer family
matches the implementer, that result is also ineligible and routing continues.
The implementer family must describe the model that produced the candidate, not
merely the host agent. This value is a caller assertion: there is no portable
cross-CLI host attestation that can prove it without adding host-specific
configuration. A false assertion can defeat same-family exclusion, so this gate
is a collaboration control for trusted local agents, not a boundary against a
hostile invoker.

Kimi performs this family exclusion before it creates or seeds a private runtime
home. A runtime copy or permission failure is client-local `client_unavailable`
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

The most common `capability_missing` in practice is Kimi's inline size ceiling.
Kimi's prompt mode has no stdin or prompt-file interface, so the packet rides in
argv, where same-host process inspection can read it; the wrapper therefore caps
the composed prompt (`MAX_INLINE_PROMPT_BYTES`) to bound both that exposure and
silent middle-elision. A larger candidate is not an error: the lane reports
`packet_too_large_for_inline` before invoking Kimi at all and cascades to a
file-backed client. It only bites when Kimi is the client you specifically need,
typically because every other client is same-family as the implementer. The path
then is candidate partitioning per `SKILL.md` — split by file group or risk
class, one packet and one recorded hash per partition, no candidate-wide claim
until every partition is conclusive. The gate will not partition for you; that is
a caller-level protocol with no executable support.

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
on the same actual provider/model.

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

Kimi retains the user's credentials and ordinary provider/model settings by
seeding a private writable runtime home from the validated source home. Session,
log, history, telemetry, update, workspace-index, binary, hook, MCP, plugin,
skill, agent, and `AGENTS.md` inputs are excluded so the formal reviewer cannot
inherit executable extensions. The `credentials/` and legacy `oauth/`
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
The formal run does not inherit executable review extensions: the private config
decodes TOML table headers before removing hook and inherited permission tables
(including quoted-key spellings), decodes top-level assignment keys before
removing hook, permission, and both skill-discovery controls in table or inline
form. It semantically verifies that the entire permission object is exactly the
generated three-rule policy and that hooks or skill discovery are absent. The
rendered config is written as a private mode-0600 sibling and atomically replaces
the copied file, so a read-only source config remains usable and unchanged. It omits
top-level `AGENTS.md`, MCP, hook, plugin, skill, and agent inputs. Runs without selected
owners pass an empty `--skills-dir`; owner-aware runs pass the controller-verified full
installed CCL skill registry through `--skills-dir` and explicitly name only the
selected owners in the prompt. It then installs static Kimi permission rules that allow only the
frozen packet `Read`: `Read(!<exact-normalized-packet>)` denies every other read,
while `!Read` denies every non-Read tool. This complement form is intentional:
Kimi 0.28 evaluates deny policy before allow policy, so a global `deny "*"`
would also suppress the exact allow. The wrapper resolves its fresh runtime root
with `pwd -P` before constructing the packet, prompt, allow, and complementary
deny, so macOS `/var`/`/private/var` aliases cannot give those surfaces different
spellings. The stream audit remains a second boundary and
rejects any non-packet or mutating model tool event. The packet is hashed before
and after the formal run, so mutation produces terminal `binding_mismatch`.
The prompt requires bounded contiguous reads of the exact packet, starting at
line 1. The parser correlates each `Read` result with its `line_offset` and
`n_lines`, rejects unpaginated reads and generated preview `output_path` reads,
rejects page offsets beyond the packet, requires every successful result line
to carry the expected contiguous line
number, and accepts a verdict only after the page ranges cover every packet
line. Candidate text that merely contains a tool diagnostic cannot change that
decision. The controller freezes valid staged profiles in a canonical multiline
form that every wrapper consumes unchanged, so Kimi's per-line preview limit
cannot hide `required_concerns`; valid resume hints remain metadata and
do not count as either packet coverage or verdict text.
Because Kimi interprets permission arguments as picomatch patterns, a physical
packet path containing pattern metacharacters is rejected before inference as
fallback-eligible `kimi_packet_path_unrepresentable`; it is never interpolated
as a falsely exact rule.

Kimi is therefore a supported reviewer client, not version-quarantined. The
wrapper gates on a **minimum verified permission-engine version, not an equality
pin**: what the check actually gates is Kimi's own engine (deny-before-allow
ordering plus the picomatch complement form), which is monotone in the version
being at least the verified one — an equality pin took the lane down on every
Kimi release while proving nothing more. Below the floor, and any unparseable
`--version` output, are refused before inference as fallback-eligible
`capability_missing`; a deterministic wrapper regression covers the floor
itself, versions above it, below-floor versions, and unparseable output. Set
`KIMI_MIN_VERSION` to raise the floor when a future engine change is verified.
The preflight version probe has a ten-second TERM deadline plus a one-second
forced-kill grace, and real host runs completed real inference through the
shared source lock. The documented negative host probes were re-run against the
generated three-rule policy at both verified points (0.28.1 and 0.29.1) and
returned Kimi's pre-execution permission denial for `Bash pwd`
(`code-review rejects non-Read tools`) and `/etc/hosts` Read
(`code-review rejects packet-external reads`); neither operation executed, and
the exact-packet Read stayed allowed. A version above the highest verified point
remains unverified by construction — the version-independent stream audit and
packet hashing stay terminal there, so the boundary degrades from prevention to
detection rather than disappearing; re-run the probes on a permission-engine
change.
The formal Kimi invocation uses the caller timeout plus the same one-second
forced-kill grace; exit 137 is fallback-eligible timeout only after elapsed whole
seconds exceed the configured deadline, while an early or pre-deadline 137 remains
terminal operator interruption.
Generated-config failure is fallback-eligible `capability_missing`; raising the
600-second ceiling or weakening the stream audit is not a remedy.

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
The temporary `ccl-review` agent allows read/glob/grep/skill and denies
known write, shell, network, interactive, and subagent routes. Additional
installed plugin tools are not rejected by name. Boundary proofs, event
streams, exports, and stderr stay outside the agent's readable project
directory.

The OpenCode debug-agent surface is a mandatory local structural check; it does
not invoke a model. OpenCode has no separate behavior-canary request. The formal
review session and its export are the only model inference path.

OpenCode calls use separate project/event/export and private XDG paths, so they
run concurrently. The wrapper does not create a shared process lock or expose a
serialization setting.
