# 116 — Reviewer init: vocabulary lists are data, not a boundary

## Artifact classification

`gate design` + `gate implementation` (per
`product-rd-workflow/references/shared-gate-artifact-classification.md`). The
change removes a class of refusals from the Claude reviewer lane's isolation
classifier and relaxes the owner-skill binding from a precondition to a
receipt. Both decide whether an independent review is produced at all, so this
plan exists before the edit and the round carries its own review ledger.

Risk tags (`feature-risk-router`): `shared-gate`, `security-review`.

`security-review`: **triggered**. The change narrows what the isolation
verifier judges, so the four design-time questions are answered below rather
than waved through as `security posture unchanged`.

`visible surface: no` — a classifier, a wrapper, and a controller acceptance
rule.

## Defect this closes

Claude Code 2.1.261 ships a new built-in skill, `workflow-authoring`. The
owner-aware Claude lane compared the init event's `skills` list against a
snapshot of built-in names, found a name it did not know, classified it
`unclassifiable_host_vocabulary`, reported `capability_missing`, and cascaded.
Every review in that period was served by another client. This is the third
release-driven outage of the same class (`/import`, then `auto-mode-setup` and
its siblings, now `workflow-authoring`); the baseline invocation added after the
second could not help, because baseline-reported skills were by design not
authority.

The maintainer decision for this round is that the class is not worth keeping
in any form: the reviewer should not judge skill, command, or plugin
vocabulary at all, and an absent or older installed CCL plugin should cost the
owner-skill binding rather than the review. The strictness bought nothing
across CLI iterations and made the lane unusable across them.

## Measured, not assumed

Captured from the real CLI at `claude_code_version 2.1.261` with the exact
flag set `claude_review.sh` builds (`--safe-mode --tools "" --strict-mcp-config
--setting-sources ""`):

| Field | Without `--disable-slash-commands` | With it |
| --- | --- | --- |
| `skills` | 17 host built-ins, including `workflow-authoring` | 0 |
| `slash_commands` | 51 host built-ins, six unknown to the snapshot | 0 |
| `terminal_slash_commands` | 3 | absent |
| `tools` | 0 | 0 |
| `mcp_servers` / `plugins` | 0 / 0 | 0 / 0 |

Differential reproduction against the base parser: a success stream
synthesized from that init plus the CCL plugin entries is refused before this
change with `unclassifiable_host_vocabulary=skills:workflow-authoring` and
accepted after it; the same stream with one inherited MCP server is refused on
both sides. The isolation proof therefore never depended on the vocabulary
fields: `tools` is pinned exactly, `tool_use` is scanned, `mcp_servers` must
be empty, `permissionMode` is value-pinned, and nothing in a skill or command
list can be invoked past those.

## Design

**Rule**: `slash_commands`, `terminal_slash_commands`, `skills`, and `plugins`
are `KNOWN_VOCABULARY_INIT_FIELDS` — recorded, never judged by name, shape, or
origin, present or absent. `REQUIRED_EMPTY_INIT_FIELDS` keeps only
`mcp_servers`. Every other verdict class (tool breach, unsafe permission mode,
unknown non-empty container, unverifiable authority, schema drift) is
unchanged and is asserted unchanged beside populated vocabulary.

Removed with the class: the built-in name snapshots, the acknowledgement-only
baseline invocation and its loader, the whole-value and bare-identifier gates,
the `unclassifiable host-vocabulary entry` reason and its routing arm, the
native-skill parser flags, and the help-prose probe that required `--safe-mode`
to describe skills as disabled. `--safe-mode` must exist and is passed;
`--disable-slash-commands` is passed when offered and no plugin is loaded.

**Owner-skill binding is a receipt, not a precondition.** When the controller
selected owners, the wrapper verifies the installed registry against the
profile and loads the plugin through `--plugin-dir`; that run attests
`native_skill_binding=established`. When the registry is absent, older, or
fails verification, or the CLI cannot load a skills-only plugin, the wrapper
reviews the packet without owner skills and attests
`native_skill_binding=unavailable`. The controller accepts that receipt as a
review with `controller-profile` skill evidence and an empty `reviewed_skills`;
a wrapper that attests neither still fails closed with `binding_mismatch`.
A profile that names no owners yet fails its own consistency check, or owner
arguments without a profile, remain caller errors.

## Security review (design-time questions)

1. *What can the reviewer now do that it could not before?* Nothing. The
   invocable surface is still exactly the pinned `tools` set with no
   `tool_use` outside it, no MCP server, and a default or plan permission mode.
   A listed skill or command is inert without the Skill tool, which is not in
   the set.
2. *What can an attacker-controlled CLI or plugin now smuggle?* Names. A
   hostile CLI could always steer which client serves the review through the
   existing drift classes; it still cannot reach acceptance with a tool, an
   MCP server, or an elevated permission mode. A plugin manifest declaring
   hooks, commands, agents, or MCP servers is not loaded at all.
3. *What evidence is weaker?* Owner-skill usage. A run attesting
   `unavailable` has no natively reviewed skills, and the controller records
   that rather than inferring it. Isolation evidence is unchanged.
4. *What is the residual?* A safe-mode regression in the CLI that loads user
   skills would no longer be caught by the vocabulary check. It was never a
   reliable catch — the check compared against a snapshot of names, not
   against the user's skills — and the tool set, tool_use scan, and MCP list
   still bound what such a skill could do.

## Executed evidence

- `test_parse_probe_result.sh`: green after rewrite; populated vocabulary,
  absent vocabulary fields, and oddly typed vocabulary fields are tolerated on
  both parse paths; tool, tool_use, MCP, and permission-mode breaches keep
  their class beside vocabulary.
- `init_policy_matrix.py`: 270 cases / 0 mismatches on the real parser.
  `test_init_policy_matrix.sh` mutation walk, each mutant in a disposable copy
  and the real parser digest unchanged after: `drop-mcp-empty-requirement` 40
  mismatches, `judge-vocabulary-as-capability` 76, `drift-on-vocabulary` 72,
  and the four pre-existing mutants (`tolerate-all-unknown-containers` 18,
  `drop-authority-name-guard` 10, `drop-authority-presence-requirement` 6,
  `drop-field-name-sanitizer` 3) still detected.
- `test_claude_review_probe.sh`: green after rewrite. Through the fake CLI: a
  hooks-declaring manifest, a stale registry, and a missing registry each yield
  a challenge verdict with `unavailable` and no `--plugin-dir`; six vocabulary
  fixtures that used to refuse now attest `established`; a CLI lacking
  `--disable-slash-commands` and four safe-mode help-prose variants still run;
  a CLI lacking `--safe-mode` still refuses.
- `test_review_gate.sh`: green; the wrapper that omits the receipt still fails
  `binding_mismatch`.

## Out of scope

- Kimi, Codex, and OpenCode wrappers keep their own registry preflight; only
  the controller's acceptance of an `unavailable` receipt is shared. Relaxing
  those wrappers the same way is a follow-up if their preflight is observed
  refusing across CLI iterations.
- The four 015 register rows describing the removed mechanism stay in the
  ledger as history; the round's own row supersedes them.
