# 122 — Codex packet lane: a private reviewer home, and the continuation gate it exposed

## Artifact classification

`gate design` + `gate implementation` (per
`product-rd-workflow/references/shared-gate-artifact-classification.md`) across
two owners: `code-review` for the reviewer lane, and `product-rd-workflow` for
the continuation gate this delivery exposed. Both decide whether required work
actually happens — one whether an independent review is produced at all, the
other whether a turn ends before the next authorized step — so this plan exists
before the edits and the round carries its own review ledger.

Risk tags (`feature-risk-router`): `shared-gate`, `security-review`.

`security-review`: **triggered**. The change removes a preflight refusal class
from the reviewer's MCP isolation check, so the design-time questions are
answered below rather than waved through as `security posture unchanged`.

`visible surface: no` — a wrapper preflight and the config it emits.

## Defects this closes

Two independent faults, both reproduced first-hand against `codex-cli 0.153.4`
on `darwin-arm64`. Together they make the Codex lane unusable on any host that
has a plugin-provided MCP server, and unusable on every host regardless.

### D1 — every packet tool call is refused before it runs

`mcp_permission_prompt_is_auto_approved` in the CLI's own source auto-approves
an MCP tool call under `approval_policy = never` only when the permission
profile is unmanaged or its sandbox has full disk write access. The wrapper
sets `approval_policy="never"` *and* `--sandbox read-only`, so the auto-approve
branch is unreachable and every `read_packet` call fails with
`MCP tool call requires approval, but approval policy is never`.

Single-variable arms, all other flags identical:

| sandbox | ephemeral | extra config | `read_packet` |
| --- | --- | --- | --- |
| `read-only` | yes | — | failed (approval) |
| `read-only` | **no** | — | failed (approval) |
| `workspace-write` | yes | — | failed (approval) |
| `danger-full-access` | yes | — | completed |
| `read-only` | yes | `default_tools_approval_mode="approve"` | completed |

`--ephemeral` is not a variable, and the fault is not specific to
`read-only`: the sole discriminator is full disk write access, or a per-server
approval mode. The lane must not buy the tool call by widening the sandbox, so
the per-server key is the fix.

The parser's report of this fault is not a stable signature. Holding the
transport failure fixed and varying only the `max_bytes` the model happens to
choose flips the verdict between `tool_boundary_violation` (argument outside
the packet schema, evaluated first) and `invalid_model_output` (no verifiable
result). Neither carries the CLI's own `requires approval` text, because
`audit_codex` reads `item.result` and the recomputed expectation, never
`item.error.message`. Diagnosing D1 from the emitted reason alone is not
possible; that is recorded here, not fixed here.

### D2 — a plugin-provided MCP server dead-ends the preflight

`codex mcp list` reports servers contributed by installed plugins alongside
those declared in `mcp_servers`. The wrapper disabled every non-packet name by
emitting `mcp_servers.<name>={enabled=false}`. For a plugin-provided server
that override creates a table with no transport, and the CLI refuses to load
the whole configuration:

```
Error: failed to load bootstrap configuration
Caused by:
    invalid transport
    in `mcp_servers.<name>`
```

Both branches of the preflight then dead-end: emitting the override fails the
second `mcp list`, and omitting it leaves two enabled servers, which the
`len(active) != 1` check refuses. Either way the lane reports
`codex_packet_tools_unavailable` before inference. Confirmed by contrast — the
same override against a server that *is* declared in `config.toml` loads fine;
only the plugin-provided one fails.

The wrapper's comment claimed "TOML overrides merge server tables". That holds
for a server the configuration already declares, and not for one contributed
by a plugin. The stub in `test_cli_review_wrappers.sh` modelled the merge
unconditionally, which is why the whole class was invisible to the suite.

## Design

**The reviewer runs from a private `CODEX_HOME`.** It is built under the run
directory, carries a linked `auth.json`, a model-preference file, and copies of
the selected owner skills, and nothing else. The user's MCP servers are not
disabled, not enumerated, and not named — they are simply not in the home this
run uses.

That replaces the enumeration entirely, so the preflight no longer has a branch
that fails on a plugin-contributed server. It also closes the execution
residual an earlier draft of this plan proposed to accept: a server that is not
in the home cannot be called, whereas a server left enabled can be, because MCP
servers run outside the CLI sandbox and the parser's audit only refuses the
verdict afterwards.

Three properties were measured before the design was chosen:

| Property | Result |
| --- | --- |
| `mcp list` under a home holding only a linked `auth.json` | no servers at all |
| Inference and packet reads from that home | complete; the verdict is produced |
| `$CODEX_HOME/skills/<name>/SKILL.md` discovery | the model invokes it and quotes its content |

Two mechanics are not obvious and are load-bearing:

- **The credential is linked, not copied.** The CLI refreshes it in place, so a
  copy would strand the rotated token inside a run directory that is deleted on
  exit. The link is re-checked after the run; a replaced link means the
  credential was written into the run directory instead, and that is terminal.
- **Skills are copied, not linked.** A symlinked skill directory is not
  discovered — measured: the same package reachable through a symlink answered
  `NO_SKILL`, and answered correctly once copied. A link here would silently
  cost the owner-skill binding.

**Model preferences are carried across explicitly**, because this lane is
contracted to review on the user's own default model and an empty home
substitutes the CLI default silently. Measured indirectly: the same packet
produced `reasoning_output_tokens: 422` under the user's home and `0` under an
empty one. The carry-over is an allowlist of model-identity keys, deliberately
not a denylist over the user's config: a key an allowlist has not heard of
costs a preference, while a key a denylist has not heard of would let an
executable server back in.

**Approval mode is declared per server.** The emitted `mcp_servers` table
carries `default_tools_approval_mode="approve"` for `code_review_packet` only.
The sandbox stays `read-only` and `approval_policy` stays `never`.

## Acceptance matrix

Preflight verdict as a function of the `mcp list` reply (`AP` = the emitted
packet-server table carries `default_tools_approval_mode="approve"`):

| `mcp list` exit | packet row | other rows | verdict |
| --- | --- | --- | --- |
| 0 | present, enabled, transport exact | none | proceed to inference, `AP` |
| 0 | present, enabled, transport exact | any enabled | `codex_packet_tools_unavailable` / `capability_missing` |
| 0 | absent | any | `codex_packet_tools_unavailable` / `capability_missing` |
| 0 | present, `enabled=false` | any | `codex_packet_tools_unavailable` / `capability_missing` |
| 0 | present, transport args/command mismatched | any | `codex_packet_tools_unavailable` / `capability_missing` |
| 0 | present, transport carries `env`/`env_vars`/`cwd` | any | `codex_packet_tools_unavailable` / `capability_missing` |
| 0 | reply is not a JSON array of objects | any | `codex_packet_tools_unavailable` / `capability_missing` |
| non-zero | — | — | `codex_packet_tools_unavailable` / `capability_missing` |

Row 2 reads like the rule this round set out to remove, and is not: under the
private home nothing else was ever registered, so a second enabled server means
the home leaked. It is an invariant this run establishes about itself, not a
judgement about the user's configuration — which is why it can be strict
without dead-ending on any host.

## Security review (design-time questions)

This section has been wrong twice and both corrections are recorded rather than
edited away, because each was found by something other than the author.

*First retraction.* An earlier draft claimed a foreign tool call "is still
terminal" because `audit_codex` rejects such a stream, and that the parser's
audit was the load-bearing boundary. Independent review disputed it; a probe
refuted it. The audit runs after the call has completed, MCP servers run
outside the CLI sandbox, and a server auto-approves itself by declaring
`readOnlyHint`, which the CLI trusts — measured with the host's own `node_repl`
(its `js` tool ran arbitrary JavaScript to completion during a packet-only
review) and with a purpose-built stub that was refused without the declaration
and auto-approved with it.

*Second retraction.* The draft that recorded the residual then claimed "a
hostile diff or a hostile tool description is a path to invoking them." That is
**withdrawn as unsupported**: two attempts to induce the call from inside the
reviewed diff did not reproduce it, on both the previous wrapper and the
mid-round one — the prompt's untrusted-data framing held. What is supported is
narrower and sufficient to act on: a foreign server is *reachable and
executable*, demonstrated by direct instruction. Reachability is the property
this design removes, and it does not depend on how persuadable a model is.

*A correction the same probe forced.* `origin/dev` was not leaving foreign
servers reachable. Its per-name disable works for a server the user's
configuration declares; it fails only for a plugin-contributed one, and there
it dead-ends the whole preflight rather than admitting the server. The three
states are therefore:

| Version | Lane usable | Foreign servers reachable |
| --- | --- | --- |
| `origin/dev` | no on any plugin host | no |
| this round's first draft | yes | **yes** |
| private home | yes | no |

The value of the private home is that it is the first state with both columns
right, not that it rescues an unsafe baseline.

1. *What can the reviewer now do that it could not before?* Nothing that was
   measured. Its only registered MCP server is the frozen packet reader this run
   created, and the preflight refuses the run if a second enabled server ever
   appears. The scope of that claim is MCP servers: hooks and the shell tool are
   disabled through capability probes that fail closed, and the working
   directory is an empty run-scoped workspace, but whether skill or hook
   discovery consults any root outside `CODEX_HOME` was not verified. The
   containment established here is over servers, not over every discovery
   surface.
2. *What did the user's home contribute that is now absent?* Their MCP servers,
   installed plugins, hooks, marketplaces, and skill registry. Model identity
   is carried across explicitly; everything else is absent because it was never
   placed there.
3. *What does `default_tools_approval_mode="approve"` widen?* One server's
   tools, named explicitly, restricted by `enabled_tools` to the two pathless
   packet readers, over a file this run wrote and hashed.
4. *What is the residual?* The credential link. The run reads the user's
   `auth.json` through a symlink so token rotation persists; a CLI that
   replaced the link with a file would place a credential inside the run
   directory. That is checked after the run and is terminal, and the run
   directory is deleted on exit with `umask 077` and mode-700 directories.
5. *What is not claimed?* That a reviewer cannot be talked into anything. The
   claim is only that there is no foreign server to talk it into calling.

## Test / register coverage

| Layer | Row |
| --- | --- |
| unit | not applicable — the change is shell preflight plus emitted config |
| integration | `test_cli_review_wrappers.sh`, fake CLI, RED before / GREEN after |
| E2E | real `codex-cli 0.153.4`, wrapper end-to-end, recorded below |
| manual | not applicable |

New fake-CLI behaviors, each RED against the pre-change wrapper:

- `plugin_mcp` — an inherited server the stub refuses to accept an
  `{enabled=false}` override for, exactly as the real CLI refuses a
  transportless table. Pre-change: `codex_packet_tools_unavailable`.
  Post-change: review verdict.
- `packet_read_plugin` — the same plugin-provided server, but the run replays
  the real packet server's bytes through the parser instead of emitting a
  canned verdict. Added after review pointed out that a CLI which accepts the
  configuration and still refuses `read_packet` would pass every other new
  assertion; the configuration checks alone could not distinguish the repair
  from its absence.
- the approval-mode assertion — the emitted packet-server table carries
  `default_tools_approval_mode="approve"`, no other server does, and the
  sandbox stays read-only.
- the private-home assertion — the source home used for the run declares a
  foreign MCP server and a model preference, and the home the CLI is actually
  handed must be a different directory that carries no `mcp_servers` and no
  `plugins/`, carries the model preference forward, and reaches the credential
  through a symlink back to the source. Each clause corresponds to a way the
  seeding can fail: not built at all, a server leaking in, a silent model
  substitution, or a credential copied into the run directory.

Verified RED twice against the two versions this round passed through: with
`origin/dev`'s wrapper the seven pre-private-home assertions fail, and with the
mid-round wrapper — the one that removed the enumeration but had no private
home — exactly the private-home assertion fails. Both pass on the final
candidate.

The reachability claim was additionally checked outside the suite, against the
real CLI: a source home declaring a foreign server produces `[('foreign',
True)]` from `mcp list`, while the wrapper run over that same source home
returns a verdict — which it could not do if the foreign server had reached the
private home, because the preflight refuses a second enabled server.

The four existing `inherited_mcp*` cases invert: they asserted the inherited
key was encoded and disabled, and now assert the run proceeds with the
inherited row untouched and no `{enabled=false}` override emitted for it.

## Second landing: the continuation gate this delivery exposed

`gate implementation` on `product-rd-workflow`, landed in the same round because
the delivery is what produced the evidence.

**The failure.** After launching a step whose result only it would consume — a
test suite, a repository gate — the agent ended its turn to report that the step
was running. It did this twice, and the user named the stopping itself as the
defect rather than asking for the result.

**Why the existing rule did not fire.** The gate already said not to stop at a
recommendation and to continue with a clearly owned low-risk slice, so the
content was adequate and the enforcement was not. Its stop-condition list is
written as an enumeration, and "awaiting work I started" is not in it — but
neither was it named as a non-condition, and the host returns control the moment
a step is backgrounded, so the pause presents itself as a turn boundary. An
enumeration that is silent on a shape is read as permitting it.

**What landed.** Four clauses, all firing mechanisms rather than reminders:
awaiting a finite self-started step is a named non-condition; a process meant to
stay up has no terminal result, so it contributes a readiness signal and the rule
says nothing about its lifetime, which the delivery owns; ending any turn requires
naming the next action first, and if
it can be performed now the turn is not over; a still-running self-initiated step
is `continuing:`, never `blocked:` and never a final response. The finite/
persistent split and the fourth pin both came from independent review, and the
split itself took three passes: polling to a terminal result would have hung on a
dev server, shutting the process down at closeout would have destroyed a service
that was itself the deliverable, and only the third form stops prescribing a
lifetime the clause does not own. Its outcome-contract line could also be deleted
with every assertion still green until a pin anchored the obligation rather than
its opening. The entrypoint carries the same obligation, consolidated
into its existing stop rule rather than appended — the repository's entrypoint
budget gate blocks net growth on this file, and it caught the first attempt.

**Evidence.** Deleting each of the four clauses reds only its own assertion in
the shared implementation-gates fixture, with no other assertion failing and the
unmutated control passing.

**Not claimed.** That a prose rule mechanically prevents the behavior. The
honest scope is that the shape is now named where the gate is read, and pinned
so it cannot be silently deleted.

## Status-sync target

Round register row in the impact ledger; no product/status document outside
this repo tracks the Codex lane.

## Review/challenge gate

Dual-track review over the implementation diff before the merge request, per
`skills/code-review`. A wrapper change that gates independent review cannot be
landed on the author's own reading.

## Two mechanism notes for the next round in this harness

**A control arm that cannot go red proves nothing.** Three probe designs in
this round produced a clean "no side effect" that meant only that the
instrument was broken: a wrapper copied without its sibling scripts died at
`timeout_normalizer_missing` before inference; `origin/dev` was used as the red
arm for a defect it does not have; and an injected instruction inside the diff
was declined by the model, which is the prompt working rather than the
containment working. Each was discarded rather than reported. The rule that
survived: state what the arm must do to be believed, and check that first.

**A round that edits the review harness cannot use chain succession.**
`review_controller_sha256` hashes every `.py` and `.sh` under
`skills/code-review/scripts/`, so any further edit to a wrapper mid-chain
changes the controller identity and the succession is refused with
`chain succession predecessor does not preserve the controller and owner
selection`. The working discipline is to land every edit first, then run
review and challenge back to back with nothing changed in between. This round
learned it the expensive way.

**A finding accepted rather than refuted is re-reported every round.**
`--mode complete` accepts only `source_refuted` dispositions, so an accepted
tradeoff has no machine-readable closure in the review gate; the round-level
ledger validator carries `accepted_tradeoff`, the review gate does not. This
round stopped needing that: the residual is closed rather than accepted, so
there is nothing standing for a future review to re-raise. The mechanism note
is kept because the next round that wants to accept something will meet it.

## Out of scope

- The unstable reason-code mapping for a failed packet tool call (D1's
  reporting half). `audit_codex` should name a transport-refused call rather
  than let the model's argument choice pick the class, but that is a parser
  change with its own fixtures and does not block this repair.
- Whether a hostile diff can induce a foreign tool call. Two attempts did not
  reproduce it and the question is now moot for this lane, since no foreign
  server is registered. It stays open for any lane that does register one.
- Kimi, Claude, and OpenCode wrappers keep their own preflights. The Kimi lane
  already seeds a private runtime home; this round makes the Codex lane match
  that shape rather than inventing one.
