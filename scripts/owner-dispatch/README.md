# owner-dispatch — mechanical firing for the owner-invoke gate

## The problem this solves

The owner-invoke rule — *invoke (load) the owning stack/design skill at each product-R&D
phase transition, before producing substance; naming an owner is not invoking it* — lived
only as prose in `product-rd-workflow/SKILL.md` (the owner-dispatch firing gate) and as
salience in `agent-context/session-start.md`. It recurringly **did not fire**: the failing action is
agent-initiated and intent-dependent, so a stronger prompt cannot enforce it.

Industry practice is unanimous that a must-happen step is enforced with a **code gate that
blocks, run as a separate check** — never a stronger prompt:

- Anthropic, *Building Effective Agents*: add programmatic **gates on intermediate steps**;
  **poka-yoke** your tools; prefer deterministic control flow where steps cannot be bypassed.
- Claude Code **hooks**: `PreToolUse` deny/ask and `Stop`/`SubagentStop` block are enforced *at the
  interpreter level* — "fundamentally different from asking Claude to follow a rule in a
  system prompt".
- OpenAI Agents SDK **guardrails**: a tripwire raises an exception and halts the run, run as
  a **separate** check — "deterministic enforcement rather than relying on the primary
  model's compliance"; **Structured Outputs** / `tool_choice:"required"` make a required
  step unskippable.

This subsystem is that gate. It mirrors the repo's existing `guard-edit-isolation.sh`
PreToolUse pattern and is built on the hook decision model in
`skills/llm-inference-integration/references/agent-lifecycle-hooks.md`.

## Surfaces (defense in depth)

| Surface | When | Hard? | Bypassable? |
|---|---|---|---|
| `PreToolUse` (Edit/Write/MultiEdit/NotebookEdit + Bash) → `owner-dispatch-guard.sh` | at the first product-code edit (**fires in subagents too** — Claude Code runs PreToolUse inside dispatched workers, carrying `agent_id`) | Claude: precise file edits `ask` (or `deny` if `strict`); **Bash writes are record-only — silent allow, no prompt** (they only drop an activity marker for the Stop backstop). Codex: advisory (ignores the decision). | Yes — the Bash heuristic never blocks (it over-matches read-only commands, so prompting on it is pure noise); many Bash write forms also slip it. This surface is a fast nudge on precise edits, not the gate. |
| `SubagentStart` → `subagent-start.sh` | when any subagent is spawned | injects a slim, **self-gating** ccl-skills routing pointer (impl/test/design/doc workers invoke their owning skill; read-only workers ignore it) — SessionStart's routing is NOT inherited by subagents, so this is their only see-it surface. Informational: SubagentStart **cannot block**. | n/a — additive context only; never overrides an owner-set the controller named in the dispatch prompt. |
| `Stop` / `SubagentStop` → `owner-dispatch-stop.sh` | at session/subagent end, **only if that actor actually changed gated code** (current tree diffed against a baseline snapshot taken at the first touch) with no boundary or with required owners not actually invoked | Claude: blocks **once per actor per session** — `SubagentStop` verifies `agent_transcript_path` when present; a legacy controller-transcript fallback never uses strict empty-set proof. Zero Skill calls are a miss only when the worker tool-event shape is verifiable. `agent_id` scopes activity/cap/waiver so siblings do not contaminate each other. Codex: advisory. | one-block cap + fail-open for unreadable/malformed/shape-drifted evidence + evidence-gate (read-only / rejected / reverted / pre-existing-dirty actors never block) means it never traps the user. |
| `ci` subcommand (pre-commit / CI) | at commit/merge | host-agnostic; rejects gated changes lacking an updated map, and rejects changes that remove/disable/malform the config or point the artifact off-tree | The durable backstop — **but only as un-bypassable as the CI job itself** (needs pipelines-must-succeed + protected branch + CODEOWNERS, per the repo deployment checklist). |

## Safety posture (every default is the safe one)

- **Opt-in, and only via a committed config.** The gate activates only when
  `.owner-dispatch.json` is **tracked in git at the repo top-level** and `enabled:true`. An
  untracked file, a parent-directory config, or a config in a nested non-repo cannot gate an
  unrelated repo. No config / disabled / malformed ⇒ complete no-op. ccl-skills itself
  ships no config (its edits are shared-skill/process edits, exempt from owner-load).
- **Fail-open (in-session hooks).** owner-dispatch is a process nudge, not a data-loss denial;
  the in-session hooks never hard-block on their own failure. A missing `jq` ⇒ **silent**
  allow (can't determine opt-in, and crying wolf on every edit would be worse). A missing or
  malformed config ⇒ silent allow (treated as not-opted-in). An unwritable/unsafe state dir ⇒
  allow (and `strict` downgrades to `ask`). The cheap opt-in walk runs before any git/jq, so a
  non-opted repo pays almost nothing.
- **Default `ask`, not `deny`.** Hard `deny` is the explicit `strict:true` opt-in, is
  Claude-only, and applies **only to the precise Edit/Write/MultiEdit/NotebookEdit file
  paths** — a write-like **Bash** command is matched only heuristically (it over-matches
  read-only commands and can never be sure), so it is **record-only: silent allow, never a
  prompt and never a deny**, even under `strict`. The Stop hook + `ci` catch what the Bash
  heuristic can only hint at. `strict` also downgrades to `ask` when the state dir can't be
  written (so it can never brick a repo).
- **Agent self-resolves the boundary; it is not a user-authorization prompt.** The deny/ask/Stop
  message is addressed to the **agent**: invoke the owning skills, then `record --owners` to clear
  the boundary — do not punt it to the user as an approval. It clears **only this gate**; separate
  user-authorized actions (merge, push, destructive cleanup, scope/product decisions) still require
  the user. `record` takes out a **per-worktree TTL lease**, not a per-slice token: it stays
  valid until the TTL expires as long as work continues forward from the recorded commit
  (committing does NOT invalidate it; switching to a divergent line does). The gate cannot
  tell two deliveries apart inside one lease, so a second slice on the same line within the
  TTL is not re-prompted — record at the start of a slice, then edit freely, and re-record
  when you have genuinely moved on to different work. When
  waiving via `touch …waiver`, first classify the edit as genuinely narrow-exempt; otherwise invoke
  owners and record.
- **`strict:true` is a maintainer/config decision, not an agent prompt-reduction knob, and not a
  safety guarantee.** Flipping `strict` is committed, team-wide repo config — make it a separate
  reviewed config-only change, never something an agent toggles inside a product edit to stop being
  prompted. What it buys is narrow: it reduces **Claude** user prompts for *precise file-edit* hooks
  by turning `ask` into an agent-facing `deny` the agent self-clears. It does **not** make the gate
  safe on its own — it is fail-open, downgrades to `ask` when the state dir is unwritable, never
  hard-denies heuristic Bash, is advisory on Codex, and does not replace CI / protected branches /
  CODEOWNERS / human map review (the durable backstop).
- **Stop / SubagentStop never traps the user.** It requires a real `session_id` (fail-open
  without one), inspects only the current `PWD` repo, blocks **at most once per actor per
  session**, is skipped by a `waiver`, and fails open if the cap can't be persisted (read-only
  FS). The same engine serves both events and scopes by `agent_id` (present only on
  SubagentStop): the main Stop cap is `s.$sidf.blocked`, a subagent's is `s.$sidf.a.$aidf.blocked`
  (independent — a subagent block never consumes the main nudge or vice versa); a **session-level
  waiver** (`s.$sidf.waiver`) suppresses both, a **per-subagent waiver** (`s.$sidf.a.$aidf.waiver`)
  suppresses only that subagent. It is **evidence-gated**: the main Stop blocks only when the
  session actually changed a gated path (the current tree — committed, staged, or unstaged —
  diffed against a baseline of HEAD + globs + content-hashed pre-session dirty paths captured at
  the first touch, classified under baseline∪current globs); **SubagentStop is actor-precise** —
  it blocks only when a gated path THIS subagent actually touched (its recorded Edit/Write paths)
  is among that changed set, so a sibling's change never blames it, and a Bash-only subagent
  (sentinel, no path list) is not attributable and is not blocked here. Read-only/dispatch-only,
  rejected/undone, reverted/stashed-to-baseline, and untouched-pre-existing-dirty actors produce
  no new gated change and never block. No baseline (write failed) ⇒ the **main Stop** falls
  back to a conservative dirty-only check, while **SubagentStop cannot attribute and therefore
  allows** (the missing per-actor evidence must not become a sibling-blaming session-wide block;
  the session Stop / `ci` remain the backstop). Stop
  inspects the **working tree**, so gated work parked only in the index/HEAD with the worktree
  deliberately restored to baseline (`git add` + `git restore --worktree`; commit + `git checkout
  <base> --`), a write the Bash heuristic never recorded (`node -e …`), a config mutation, or a
  cross-`PWD` repo is out of this nudge's reach — `ci` (diffs base..HEAD at commit/merge) is the
  reliable backstop for all of those. Stop is a fast in-session nudge, not the enforcement boundary.
- **Symlink-safe state.** State lives under `<git-dir>/owner-dispatch`; writes refuse/replace
  symlinked paths and use `mktemp`+atomic-rename. (Residual TOCTOU there requires write access
  to your `.git` — at which point the attacker already owns the repo.)
- **Boundary records** are bound to repo root + expiry + **HEAD continuity**, under the
  per-worktree git dir (never committed). A hand-moved or expired record no longer counts.
  **Validity requires the recorded `.head` to be an ANCESTOR of the current HEAD, not equal to
  it.** Equality was wrong because the gate demands recording before the first gated edit while
  a delivery's own commit lands after it — so equality invalidated the boundary of every
  delivery that commits, and the only strategy that satisfied it was re-recording at session
  end, i.e. post-hoc attestation. Dropping the HEAD condition entirely was also wrong: equality
  was incidentally catching history discontinuities (branch switch, reset, amend, rebase), which
  genuinely are different work. So `.head` is **gate-critical**, not decoration — it is the
  anchor the continuity check is evaluated against, with replacement refs disabled so a
  `git replace --graft` cannot fake ancestry. An unusable recorded head fails closed.
- **The TTL is the only thing that ages a boundary out** on a continuous line of work — reuse is
  still scoped to a valid record for the same repo root, under that worktree's own git dir, on a
  descendant of the recorded commit. Within those bounds a *different* actor
  inherits an existing boundary: PreToolUse does not read the transcript at all, and Stop's
  invocation check clears that actor too whenever it invoked the same owner names — which is
  the normal case for a repo with a stable owner set. So "record before first edit" is not
  enforced per-actor; treat the boundary as a per-worktree, time-bounded record.
- **`record` is in-session self-attestation** — `record --owners "…"` is trusted, not verified
  against actual owner invocation; it unblocks editing until the TTL expires. The real
  verification is the human/CI **map artifact**, checked by `ci`.

## Bootstrap a repo (one-click)

`install-gates` vendors the gate **mechanics** into a product repo in one step — the engine
script, a default config, and a warn-only CI fragment. It installs **both** repo-local gates
(`owner-dispatch` and `agents-file-coverage-gate`) since they share the same vendor-and-wire shape;
pass `--gates owner-dispatch` for this gate alone.

```bash
make install-gates TARGET=/path/to/product-repo          # both gates, warn-only
# or: bash scripts/install-gates.sh /path/to/product-repo [--gates owner-dispatch]
```

What it does for owner-dispatch:

- vendors `scripts/owner-dispatch/owner-dispatch.sh` into the target (CI/hooks can't reach the
  plugin cache, so the engine must live in-tree); re-running **refreshes** it to the current
  plugin version (fixes drift) and **never** overwrites an existing `.owner-dispatch.json`;
- writes a default `.owner-dispatch.json` with **`enabled:false`** — the gate is a complete
  no-op until you deliberately turn it on. The default `product_globs` are a generic guess the
  installer cannot verify against your layout;
- generates `ci/agent-gates.gitlab-ci.yml` with the owner-dispatch `ci` job scoped to **MR
  pipelines** (`$CI_MERGE_REQUEST_IID`) so the diff base SHA always exists — no shallow-clone
  `merge-base` guesswork — and `allow_failure: true` so a fresh repo never breaks.

It installs **mechanics, not obligations** — it cannot write your real `product_globs`, the
owner-dispatch map a gated change owes, or decide the enforce flip. Finish the rollout by hand:

1. Edit `product_globs` / `exclude_globs` to this repo's source layout, then **prove the globs
   match** — `owner-dispatch.sh status` only shows opt-in/boundary state, it does not exercise
   the gate. After you enable+commit the config, run `owner-dispatch.sh ci --base <sha>` on a
   branch that edits a real gated file and confirm it classifies that file as gated (a generic
   glob can silently gate nothing — see *Writing globs* below).
2. Flip `enabled:true` in a **separate config-only change** (no gated product files in that
   diff, so it passes `ci` cleanly), then add `include: { local: ci/agent-gates.gitlab-ci.yml }`
   to `.gitlab-ci.yml`.
3. To **enforce** (block, not warn): once contracts/maps exist, remove `allow_failure` from the
   CI job (a deliberate, separately-reviewed change — the installer never does this for you).
   Enabling on a repo with pending gated changes owes a map in that same MR — keep the install
   change and the product change separate.

## Usage

Or opt a **product** repo in by hand (what `install-gates` automates):

```bash
cp <plugin>/scripts/owner-dispatch/owner-dispatch.example.json <product-repo>/.owner-dispatch.json
# edit product_globs / exclude_globs / strict / ci_artifact, then commit it
```

The owner, after invoking the owning skills and building the owner-dispatch map, records the
boundary so editing is unblocked:

```bash
scripts/owner-dispatch/owner-dispatch.sh record --owners "product-rd-workflow,go-microservice-dev"
```

Wire the host-agnostic backstop into the product repo's CI / pre-commit:

```bash
scripts/owner-dispatch/owner-dispatch.sh ci --base "$CI_MERGE_REQUEST_DIFF_BASE_SHA"
```

Inspect state: `scripts/owner-dispatch/owner-dispatch.sh status`.

### Writing `product_globs` / `exclude_globs`

Globs are matched with bash `case` (extglob). Two semantics to know:

- `*` **crosses `/`** (unlike shell pathname globbing), so `src/**` matches `src/a.go`
  **and** `src/a/b/c.go` at any depth, and `**/*.go` matches any `.go` file that has a
  slash at any depth.
- A **leading `**/`** means *zero or more directories*: `**/*.go` gates a repo-**root**
  `main.go` as well as `pkg/a/b.go`. (The engine special-cases this; bash `case` is not
  globstar-aware on its own.) This applies to **both** `product_globs` and `exclude_globs`
  uniformly — so `**/*_test.go` in excludes also excludes a root `foo_test.go`. Because a
  `**/`-prefixed **exclude** therefore covers the root-level file too, size excludes to
  intent (`**/generated.go` excludes `generated.go` at every depth **including the root**).

Gotcha: to gate a **top-level** product file, use `**/*.go` (or a bare `*.go`) — a
dir-prefixed glob like `src/**` only covers files under that directory. A repo whose
production code lives at the root with a `["src/**"]`-style config silently gates
nothing. Verify a new config against a **real** product file: a gated edit must `ask`
(`owner-dispatch.sh status` + a dry `pretool`/`ci`), not just trust the glob.

### What `ci` enforces (and its limits)

Exit codes: **0** = ok / not-opted-in / clean config-only decommit; **1** = violation;
**2** = could-not-verify (a gating CI job must treat 2 as failure). `ci` fails **closed**.

It rejects, when gated product files changed in the diff:
- a missing or stale (not-updated-in-this-change) map artifact;
- an `enabled` config that is schema-invalid (`product_globs` not a non-empty string array, etc.);
- a `ci_artifact` that is unsafe (`..`/absolute), is the config file, or points at product code
  / a gated changed file (so a change to that file can't self-satisfy the gate);
- a change that disables/removes the config **and** touches gated code (disabling the gate must
  be a separate, reviewed, config-only commit);
- a change that shrinks `product_globs` / widens excludes to dodge — files are classified against
  the **union of base and head** globs, so **config-contract changes must land in their own
  commit**, separate from the product change they would re-scope.

It does **not** validate the map's semantic content (that the listed owners actually cover the
gated files) — that stays reviewer/owner judgment. And it is only as un-bypassable as the CI job
itself (needs pipelines-must-succeed + protected branch + CODEOWNERS on the config).

### Invocation evidence (name ≠ invoke)

`record --owners "a,b"` stores owner *names*; it cannot itself prove those owners were
actually **invoked** (loaded) this session — "naming an owner is not invoking it" was
recognition-dependent. The Stop hook now closes that mechanically: main `Stop` reads
`transcript_path`; `SubagentStop` reads the worker-only `agent_transcript_path` (falling back
only for older hosts that omit it). It parses real `Skill` tool invocations and blocks once
when a recorded skill-shaped owner was never loaded.

- **Reliable firing point = the Stop hook** (it gets the host transcript path on stdin; a plain
  CLI cannot reliably locate the transcript). `owner-dispatch.sh verify-invocations
  --owners "a,b" --transcript PATH [--empty-is-missing]` exposes the same check for tests/host
  adapters (exit 3 = a skill-shaped owner was never invoked).
- **Worker-empty is evidence only under a verified shape**: a worker transcript with at
  least one recognized assistant tool event, no malformed Skill block, and zero Skill calls
  reports every required skill-shaped owner as missing. No transcript, malformed-only
  evidence, or a visible Skill block whose input shape drifted stays fail-open. A legacy
  SubagentStop fallback to the main transcript also keeps empty-set fail-open. Main-session behavior remains backward
  compatible. The same block-once-per-actor cap, waiver, AND actual-gated-change
  requirement as the boundary-missing block, so a no-change / reverted / read-only
  session is never blocked even with a valid boundary present.
- **Native preload is not transcript evidence.** A custom worker may receive skill content
  at startup without a `Skill` tool event. For a write worker governed by this audit, keep
  the preload but explicitly invoke each required owner once before substance; the one-time
  continuation message makes the worker normalize that evidence itself, never the user.
- **Only skill-shaped owner tokens are checked** (a single kebab token, no spaces), so a
  free-text reference like "then the touched owner" never false-flags; a kebab token that
  is a non-skill reference is a possible false match, which the block message calls out
  ("if it is a non-skill reference, proceed").
- The Skill invocation JSONL shape (`message.content[].type=="tool_use"`, `name=="Skill"`,
  `input.skill=="<plugin>:<name>"`, in `type=="assistant"` events only) is an observed Claude Code format; a format change
  with no parseable JSON events degrades to fail-open, never to a wrong
  verdict.

### Strict mode escape

Under `strict:true` a precise gated edit is hard-denied (Claude only). If an edit is a genuinely
narrow exempt change (single bug/test/doc/config), the deny message names a per-session escape — `touch
<state-dir>/s.<session>.waiver` — so strict can never brick a legitimate edit. Classify the edit as
narrow-exempt first; if it is real product/delivery work, invoke the owners and `record` instead of
waiving.

## Tests

`bash scripts/owner-dispatch/test.sh` runs the RED→GREEN behavioral suite (baseline: no
config ⇒ silent allow; with config ⇒ gate fires; with boundary ⇒ allow; strict ⇒ deny; Stop
cap; CI mode).
