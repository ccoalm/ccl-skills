# Agent Session Persistence (Durable Log, Resume/Fork, Compaction)

Implementation companion to the Agent Loop and "Sessions" building block in `retrieval-agent-safety.md`
and the Context-Editing/Memory notes there. Those say a session must be persistable and resumable and
that long loops cross a compaction boundary; this reference is *how* to build durable session state for
a multi-turn agent so it survives crashes, resumes/forks faithfully, and compacts past the context
window without corrupting history.

Use when an agent runs multi-turn conversations that must survive process restarts, be resumed or
forked later, or run long enough to exceed the model context window. For a single request/response
call with no persisted state, skip this.

Patterns observed in a production reference agent; the underlying append-only-event-log idea is the
well-established event-sourcing / write-ahead-log shape applied to agent conversations.

## 1. The session is an append-only event log, not a mutable blob

Persist the conversation as an **append-only log of canonical events** (one record per line, e.g.
JSONL), written in order as the turn progresses. This log is the *source of truth*; full state is
reconstructed by replaying it. Benefits that mutable-snapshot persistence loses: crash safety (a
half-written turn is a truncated tail, not a corrupted document — *under the §2 durability
preconditions*), faithful resume/fork (replay), and human/tool inspectability (each line is a
self-contained event you can `grep`/`jq`).

The flip side of append-only is unbounded growth: a long session accumulates every pre-compaction
event forever, and every resume replays all of it. Bound it with **segmented logs plus durable
compacted checkpoints** (§5): once a compaction checkpoint is written and replay-verified, older
segments it subsumes can be archived so the live replay set stays bounded.

- Give each session a stable id and a creation-time metadata header record (id, created-at, source,
  base instructions, model, fork parent if any) as the first line, so a listing can summarize a
  session by reading only its head.
- Keep a **separate index** (a small SQLite/DB or derived cache) for listing, search, sort, and
  pagination. The index is derived/disposable; never make it the source of truth. Rebuildable from
  the logs means a corrupt index is recoverable.
- Store active sessions and archived sessions in distinct locations so listing the active set does
  not scan archives.

## 2. Write through a background writer with flush-before-finality and observable failure

Appends should not block the turn, but they also must not be silently lost. The crash-safety claim in
§1 only holds under these durability preconditions — state them, do not assume them:

- **One exclusive writer per session** (a lock/lease), so appends cannot interleave from two
  processes into the same file.
- **Whole-record atomic append** — serialize each event to a complete line and write it in one
  operation; never flush a partial record, so a crash leaves a clean truncated tail, not a spliced
  half-line.
- **`fsync` (or platform equivalent) before acking a Flush** — an OS crash can lose buffered writes
  the application already "wrote"; durability is only real after fsync.
- **Monotonic per-event sequence number, and ideally a checksum**, so a truncated/garbled tail is
  detectable on resume and the high-water mark is unambiguous.

Use a background writer fed by a queue with explicit control messages:

- **Append** (enqueue events), **Flush** (process all prior writes, ack when on disk), **Shutdown**
  (drain + ack), each acknowledged so callers can await durability at the points that matter.
- **Flush before any finality signal.** Before you tell the user, the model, the SDK/control stream,
  or a transcript consumer that a turn/session completed, flush the log. A "done" that outraces the
  writer can lose the last turn on crash. (This mirrors the background-task finality rule in
  `terminal-cli-dev`: retain final output until consumers have acknowledged it.)
- **Checkpoint before external commitments, not only before finality.** Flush the recorded log
  prefix durable *before a model adapter receives a request*, *before any tool call may produce an
  external side effect — nested and delegated calls (code-mode sub-calls, sub-agent tool use)
  included, since they route through the same effect surface*, and at each pre-step boundary — and treat a rejected/failed checkpoint
  as blocking that dispatch or side effect (fail closed), not as a warning. Finality-only flushing
  leaves a mid-turn window where a crash loses the prior response and ordered tool results that an
  already-executed side effect or the next request acted on. The flushed prefix alone still cannot
  distinguish *never dispatched* from *dispatched, outcome unknown* after a crash — so pair the
  checkpoint with a durable dispatch-intent/attempt record appended-and-flushed before the action
  and a completion record after: for model requests that is exactly §3's attempt-state rule
  (prepared → dispatch-attempted → accepted/uncertain/rejected, idempotency-keyed); apply the same
  shape to non-idempotent tool side effects, where an unresolved attempt is reconciled or surfaced
  as a typed indeterminate outcome — never auto-retried (the task-level counterpart lives in
  `agent-task-orchestration.md`'s effect-finality rule). (This is the event-log half; the §3
  accounting records carry their own commit-before-dispatch rule — complementary, not duplicates.)
- **Make writer failure observable.** If the writer task dies (disk full, IO error), record a
  terminal-failure state that every later append/flush call surfaces — never let the recorder keep
  accepting events into the void. A dropped persist is a data-loss bug, not a best-effort log line.
- Do not return an empty-success on a failed write/flush; raise it. Silent log-and-continue on a
  persistence failure is the data-loss anti-pattern.

## 3. A persistence policy decides what is durable, ephemeral, or truncated

Not every in-memory event belongs in the durable log. Define an explicit policy:

- **Always persist structural markers** the replay depends on: the session-meta header, per-turn
  context records, and **compaction markers** (§5). Without these, a replayed or compacted session
  reconstructs wrong.
- **Persist canonical conversation items** (user/assistant messages, tool calls + outputs) needed to
  rebuild model context.
- **Classify volatile UI/telemetry events as ephemeral** — progress ticks, spinners, and status
  updates do not belong in the durable transcript.
- **Bound payloads before persisting — but persist what the model actually saw.** Capping/middle-
  truncating large tool output keeps one noisy command from bloating the file, *but truncation that
  diverges from the model-visible context breaks faithful replay* (replay would reconstruct a
  different context than the original run). Reconcile by either (a) applying the same truncation to
  the model input, so the persisted form *is* what the model saw; or (b) storing the full payload
  content-addressed out-of-line and logging a deterministic truncation artifact applied identically
  at original run and replay. Do not promise faithful replay while silently persisting less than the
  model consumed. Sanitize/redact at persistence time as well as display time.
- Support more than one persistence mode (e.g. a lean default vs an extended/debug mode that keeps
  larger payloads) so verbosity is a policy choice, not hardcoded.
- **Model-visible ⟹ accounted-for.** Every item in the client-dispatched envelope must carry
  exactly one durable accounting classification (the sealed envelope defined below; the
  provider-effective context is the separate, conditional surface at the end of this rule).
  The policy above decides what is durable; this invariant decides what is *explainable
  afterwards* — user/assistant messages, tool outputs, injected context, and resolved
  instruction surfaces all count. The classes:
  - **Reconstructable (raw)** — the persisted content is byte-equivalent to its item in the
    sealed client-dispatched envelope and lives in the session log itself (per the truncation
    rule above, the client dispatched the same truncated form that was persisted; what the
    provider did after that is the provider-effective surface at the end of this rule). A payload stored out-of-line classifies by
    reference below — never raw — so the availability and authorization criteria apply to it.
    An item transformed by persistence-time redaction does not classify raw — classify it
    non-reconstructable, with the redacted derivative recorded as the marker's metadata rather
    than as the item.
  - **Reconstructable (by reference)** — the log carries an immutable, versioned reference
    (an opaque pinned id or version; for content-derived ids see the digest rule below)
    plus a digest, and the referenced store keeps the item
    resolvable for the session log's whole retention horizon, with access no broader than
    the log's policy while the authorized replay principal keeps access. "Stricter policy" is
    not the test: a store that purges earlier than the log, or denies the replay principal,
    fails it — availability and authorization are what make the promise true.
    A mutable reference target does not qualify: replay would resolve different or missing
    content, turning "reconstructable" into a false promise — classify such an item
    non-reconstructable instead.
  - **Non-reconstructable** — an explicit marker carrying the reason (policy forbids persistence,
    the payload was ephemeral, the source lives behind stricter access control) plus either a
    keyed digest or an explicit no-digest note.
- **The accounting invariant audits records; it must never force raw persistence.** Assertions
  over a session log check completeness (no envelope item without a classification) and
  validity (by-reference targets immutable and policy-aligned) — never "everything model-visible
  is persisted raw"; that inversion is how an accounting rule becomes a credential-persistence
  bug. Completeness is only as real as the record it audits: assign stable per-item ids at
  context assembly and durably commit each item's complete accounting record — the id, the
  classification, and that classification's evidence (the raw content itself, the validated
  pinned reference plus digest, or the full non-reconstructable marker) — before model
  dispatch, failing closed if that commit fails; a retry reuses the ids so a replayed
  dispatch deduplicates rather than double-classifies. The denominator must be authoritative
  too: derive one atomic, invocation-scoped manifest from the finalized dispatch payload
  itself — the ordered item ids and boundaries — and commit it with the records, so an audit
  checks the log against the invocation's own manifest rather than against whatever subset of
  records happened to land. Seal before you account: freeze the dispatch payload into an
  immutable envelope, derive the manifest and records from that sealed envelope, and let
  transport and retries send only the sealed envelope — a payload middleware can still mutate
  between commit and send re-opens the window (the same check-then-act closure the §4 config
  lock pins with a generation). Account the attempt, not only the content: record durable
  attempt states around the sealed envelope — prepared, dispatch-attempted, then accepted or
  delivery-uncertain — plus the provider request/idempotency key; the durable
  dispatch-attempted state (unique attempt id plus that key) commits before transport is
  invoked, failing closed like the item records, and after transport the state moves only to
  accepted, delivery-uncertain, or rejected — the last a provider-attested definitive rejection
  before model execution, recording that no invocation occurred; a corrected resend after it is
  a new sealed invocation with its own envelope and key, since an idempotency key may only ever
  cover one identical payload — so a retry that may have
  invoked the model twice shows as two attempts even while item accounting deduplicates.
  Recovery treats a stale dispatch-attempted record as delivery-uncertain — a crash just after
  the commit and a crash after provider acceptance leave the same record — reconciling by
  provider request id where the provider supports it, and auto-retrying only under
  provider-guaranteed idempotency with the invocation's original key and the identical sealed
  envelope — a retry that mints a fresh key is a second invocation, not a retry; otherwise the
  uncertainty is surfaced, not retried through. A stale prepared record — committed but never
  dispatch-attempted, so transport cannot have run — is recovered explicitly too: either cancel
  it into a typed terminal state, its committed evidence following the normal retention or
  erasure policy, or resume by committing dispatch-attempted and sending the identical sealed
  envelope under the original key; left prepared forever it surfaces nothing and strands
  committed evidence with no invocation to explain it.
  Version the accounting schema and apply it prospectively: an invocation recorded before the
  accounting existed carries a typed legacy marker (the non-reconstructable family, with
  pre-accounting as the reason) — never synthesized classifications — the same rule §4 applies
  to sessions recorded before the config lock existed. The guarantee is honest about its edge:
  it is scoped to what the client dispatched. A provider can inject, truncate, or compact
  server-side, so the accounting claims the sealed envelope, not the provider's effective
  context — where authoritative provider evidence of the effective context exists, record it;
  where it does not, the invocation carries a typed model-context-unverifiable marker rather
  than an implied full-fidelity claim. A crash between dispatch and append
  otherwise leaves items whose classification landed but whose evidence never did, and a
  log-only audit sees neither gap.
  Credentials and secrets never reach this accounting as content, because they are never
  model-visible raw (resolve them by reference at the boundary — `agent-credentials-auth.md`).
  A secret detected in the sealed envelope before dispatch aborts the transport and records a
  rejected-exposure event, itself under the same discipline as every exposure record (never
  the value, never a plain digest); accounting for a known exposure never licenses sending it.
  The scan
  runs before accounting evidence is derived or committed and fails closed itself: a scanner
  error, timeout, or absence never reads as no detection — the dispatch waits or aborts; where
  any persistence preceded
  detection, the late-discovery transition below applies to the aborted dispatch as well. If a
  secret is discovered only after it reached model context, classify that item
  non-reconstructable with an explicit no-digest note — never raw, never by reference — and
  attach the exposure as that marker's metadata: the accounting records a typed exposure event
  (class, source, span) — never the value, and never a plain digest of it. Late discovery is a
  transition, not a label, and it covers every class that persisted content: whether the item
  was raw in the log or reachable through a by-reference target, supersede the classification,
  contain read access to the affected records and the referenced target at once, and purge or
  cryptographically erase the persisted or referenced content, its replicas, and any digest or
  content-derived identifier stored for it, where the store supports it —
  an append-only log does this as a supersession event plus erasure, never a silent rewrite —
  recording any residue that could not be erased as part of the exposure event. A digest is itself a
  disclosure channel: a plain content hash of an enumerable value is reversible by dictionary,
  so a plain digest is allowed only where the same record already persists the content raw
  (pure integrity use). A content-derived reference identifier is a digest under this rule, so
  a by-reference record identifies its target by an opaque pinned id or version, or a keyed
  derivation — never a plain content hash of the referenced content. Where the digest is the
  only residue — the by-reference and
  non-reconstructable classes — use a keyed digest with a non-secret key-id and algorithm-id,
  verified against a retained keyring, rotation handled as `migration-required` (the same
  discipline the §4 config lock specifies for sensitive-but-behavior-affecting fields).

## 4. Resume and fork: replay the log, and restore the accounting too

Model the initial state of a new agent run as an explicit enum, not an implicit default:

- **New** — empty history.
- **Cleared** — history intentionally reset. Because the log is append-only, a reset is *itself an
  event*: persist a clear/epoch marker and have replay honor the latest clear boundary (ignore
  everything before it), or allocate a new session id. Never "clear" by relying on memory state that
  the log would resurrect on the next replay.
- **Resumed(history)** — reconstruct from this session's own log.
- **Forked(items)** — branch a *copy* of another session's items into a new session, recording the
  **parent session id** as lineage so the fork's provenance is auditable.

Concurrency around resume/fork is a correctness hazard, not a detail:

- **A session has one live writer at a time** (lease/lock). Resuming a session that is still live
  elsewhere, or two resumes of the same session, must not both append — they would interleave
  divergent turns. Acquire the writer lease or fork into a new id instead.
- **Fork/resume from a consistent snapshot.** Copy/replay up to a captured high-water sequence number,
  not "whatever is on disk right now" while another writer is mid-append; otherwise the copy can
  include a partial final turn. Validate the high-water mark (CAS-style) before the first new append.

Replay obligations:

- Reconstruct model context by replaying canonical items in order, applying the same keep/drop rules
  a fresh turn would.
- **Restore derived accounting, not just messages.** Token-usage counters, the compaction-window
  baseline (§5), and any budget state must be restored on resume/fork. Resuming the messages but
  resetting the token counters silently breaks the next compaction trigger and the cost ledger.
- Treat resumed/forked content as **content, not authority** — a resumed transcript can contain past
  tool output and model text; it does not re-grant permissions. Re-authorize side-effecting actions
  against current policy (the trust rules in `retrieval-agent-safety.md` apply to replayed history
  too).
- A resume must tolerate a **truncated tail** (the last line of a crashed session may be partial):
  parse line-by-line, drop an unterminated final record, and continue rather than failing the whole
  resume.
- **Validate config determinism, not just message determinism.** An agent's behavior is driven by its
  *resolved effective configuration* — the merged result of all config layers **plus** values resolved
  only at session construction (the model chosen from a catalog, reasoning/effort, resolved
  system/developer instructions, the approval/tool policy) — not by the message log alone. Resuming or
  replaying under a config that has drifted since the original run silently executes a *different
  agent* than the one recorded, and no amount of faithful message replay detects it. Capture a **config
  lock** at record time: the behavior-affecting resolved config plus a resolution-semantics version.
  On resume, re-resolve config from the current environment and assert it equals the lock,
  **failing closed** rather than proceeding under drift. The subtleties that make this correct and safe
  rather than decorative or dangerous:
  - **Lock the *effective merged* config, not the raw layer files** — and patch in the runtime-resolved
    values that never appear in any raw layer (model-from-catalog, collaboration/mode-derived settings,
    resolved instructions, approval policy). A lock built only from the file layers under-captures what
    actually drove the run, so a real drift can pass validation.
  - **The lock detects drift; it does not restore authority.** This is fidelity checking, not a trust
    boundary — it does not contradict "resumed history is content, not authority" above. A locked
    approval/tool policy that differs on resume is *drift to surface and fail closed on*, never an
    instruction to reinstate the recorded policy or bypass current enforcement. Side-effecting actions
    still re-authorize against the *current* policy (per `retrieval-agent-safety.md`); the lock only
    answers "is this the same agent configuration the recorded run executed under?".
  - **The lock applies to *resume*, not uniformly to replay and fork** (the §4 state enum). *Resume*
    continues the same agent → validate continuity (this rule). *Replay* for diagnosis runs read-only
    against the *recorded* config-as-evidence and must not require equality with the live environment.
    *Fork* intentionally starts a new session that may adopt a new model/tool/policy → it records a
    *fresh* lock plus parent lineage, not an equality check against the parent's lock. Applying the
    resume gate to replay or fork either blocks valid operations or pushes operators toward a blanket
    override.
  - **Lock canonicalized, behavior-affecting values only — and treat the lock and its diff as
    disclosure-sensitive.** A raw effective config carries secrets/tokens, env-derived ephemerals,
    absolute paths, timestamps, and availability-probe results; persisting or comparing those leaks data
    (§3 / R10 sanitization) and manufactures false drift. But "non-secret" is not enough: resolved
    *instructions*, tool manifests, policy text, internal endpoints, and tenant/router identifiers are
    behavior-affecting yet still sensitive. Lock such fields by **stable id + keyed digest**, not raw
    value, and surface drift as *which fields changed* by default; expose value-level diffs only to a
    privileged operator. The error a normal user sees must not become an exfiltration channel for the
    hidden prompt/policy surface the lock is meant to protect. The digest must record a **non-secret
    key-id and algorithm-id**, and verification must run against a *retained keyring* for the session
    retention window — otherwise a key rotation makes every prior session falsely drift (then someone
    "fixes" it by disabling sensitive-field comparison, reopening the hole). A missing/retired digest
    key is a `migration-required` case (below), never silently equality, inequality, or a global
    bypass; rotation produces a new lock generation or a typed migration record, never a demand to
    re-expose the protected raw value.
  - **Canonicalization must be one specified scheme, not "canonicalize" hand-waved.** Two resolvers that
    disagree on key ordering, default elision, path/float/string normalization, env expansion, or
    redaction placeholders will either lock users out (false drift) or compare equal after dropping a
    behavior-affecting distinction (missed drift). Pin a single canonical schema with field-level
    equality rules and golden test vectors; the lock is only as trustworthy as that scheme is
    deterministic across versions.
  - **Strip the lock's own control knobs before comparing.** The settings that enable/locate the lock
    are not part of the locked surface; if you compare them too, the lock diverges on its own
    configuration (self-reference) and every resume fails spuriously.
  - **Classify drift; do not collapse it to one coarse override.** Fail-closed-with-a-single-bypass-flag
    is a footgun: the same flag that waves through an unsafe silent change also blocks (or normalizes
    bypassing) *required* changes — a deprecated model removed, a rotated endpoint, a tightened safety
    limit, a schema migration. Distinguish drift classes (compatible / safety-tightening /
    safety-loosening / unavailable-deprecated / migration-required) and require a *typed* migration or
    acceptance per class, so accepting a forced upgrade never silently also accepts a behavior-loosening
    drift. Relatedly, when a locked value was resolved from a mutable catalog / feature-flag service /
    remote default, current resolution may no longer be able to reproduce it: lock stable artifact
    *identities and resolver inputs* (so the lock stays interpretable), and treat an unreproducible value
    as a migration-required case to record explicitly — never a silent pass. A migration/acceptance is
    itself a durable, auditable record that yields a *new* lock generation, not an in-memory "operator
    clicked OK".
  - **Version the lock on resolution semantics, not raw build, and fail on mismatch by default** with an
    explicit, *typed* operator acceptance (not a global ignore-all). The durable invariant is the config
    resolver/schema/catalog-semantics version — a routine build/patch bump that does not change
    resolution semantics should not hard-fail an otherwise-identical resume (record raw build as audit
    metadata, not as the gate); but bump the semantics version whenever resolution can differ even when
    the serialized config looks identical.
  - **Scope one lock per config-authority boundary, normally the root session.** A child/sub-agent that
    truly inherits the parent's already-resolved config references the parent lock rather than
    re-locking (re-locking inherited config validates against the wrong baseline); a sub-agent launched
    with its *own* distinct model/tool/instruction scope is its own boundary and locks that.
  - **Pin the validated config as the turn's authority to close the check-then-act window.** "Re-resolve,
    compare, proceed" leaves a TOCTOU gap: config can change after validation but before a side effect,
    so the resumed turn acts under a config neither validated nor current. Snapshot the validated
    resolution as a generation/lease that is the turn's runtime authority, and re-check it (CAS-style,
    like the high-water mark above) — together with current policy — before each side-effecting action.
  - **A session with no lock is not silently resumable.** Sessions recorded before locking existed (or
    with the lock disabled) have no baseline to validate against; default them to `migration-required`
    or `replay-only`, never "resume as if validated". And log every lock outcome — *including denials
    and migration rejections*, not only acceptances — or the audit trail only shows the resumes that
    succeeded.
  This is the configuration analogue of "restore derived accounting" above: replay fidelity requires
  the same *inputs*, not just the same *history*.

## 5. Compaction: summarize past the context window without corrupting history

When a session's estimated context approaches the model window, compact it.

- **Trigger on a token-budget watermark measured from the last compaction.** Track a per-window
  baseline and a window ordinal so "how much have we grown" is measured since the previous compaction,
  not from zero. **Prefer server-reported token usage over local estimation** when the provider
  returns it; estimation is the fallback that drives the trigger when no server count is available
  yet. Feed the trigger from **one unified token meter**, not per-consumer recounts: a single
  replay-aware event source (rebuilt from the log on resume/replay, per §4's restore-accounting
  rule), deduplicating repeated *ingestion of the same attempt* (a replayed or re-read response)
  by attempt/request id. Keep two projections over that one source, and derive each correctly:
  the **logical/pressure projection** (compaction trigger, budget displays) measures the *current
  model-visible envelope*: the latest authoritative envelope measurement — server-reported context
  size bound to the *accepted canonical attempt*, not merely the newest report — **plus the
  estimated size of every model-visible item appended since that measurement** (a large tool
  result landing after the report otherwise dispatches an over-window request unpruned), or a
  fresh full-envelope estimate taken before dispatch; never a sum across sequential requests,
  which re-counts the resent history every turn and trips the watermark while the real context
  still fits; the
  **per-attempt/billing projection** sums every real provider attempt — a genuine retry consumes
  and may bill tokens even when its payload duplicates the first attempt. Collapsing the two
  either underreports spend or triggers needless lossy compaction; consumers that recount for
  themselves disagree about when pressure exists.
- **Run a deterministic pruning layer before the summarization layer.** Before invoking any
  model-written summary, apply a model-free, replay-safe pruning pass over the candidate window —
  dropping or trimming stale tool-call/tool-output payloads under the same keep/drop rules — and
  only summarize if the window is still over pressure afterwards. Pruning is deterministic, cheap,
  and reversible in design terms; jumping straight to LLM summarization pays nondeterminism and
  fidelity loss for reduction that pruning could have achieved. Declare which of two shapes the
  pruning layer is, because a prune that relieves pressure without a summary has no summary-bearing
  compaction marker to ride on: **ephemeral** pruning is applied at context assembly from the same
  versioned rules every time, never mutates the log, and replay reproduces it by re-running the
  rules; **committed** pruning persists a typed prune-only marker — covered range, rule/version,
  resulting kept-set references, and the window-baseline update, with the summary field legitimately
  absent — so resume neither reconstructs the unpruned envelope nor re-triggers compaction. An
  unclassified prune that changes the model-visible envelope without either contract breaks
  faithful replay. (The trim-to-fit rule below stays as the last-resort fallback *after* a
  summary; this layer runs *first*.)
- **Manual/user-invoked compaction fails with typed codes, not a generic error.** Distinguish at
  least: another compaction already in flight, cancelled, context changed since the request,
  summarization failed, and commit/persistence failed — the caller's correct reaction (retry,
  re-read, give up, surface data-loss risk) is different for each, and a generic failure trains
  users to spam retry across all of them.
- **Two strategies, chosen by provider capability:** *local/inline* compaction (you send the history
  to the model with a dedicated summarization prompt and replace it with the returned summary) or
  *provider-remote* compaction (the provider compacts server-side). Pick per provider; do not assume
  one is always available.
- **Record a self-sufficient compaction marker in the log** so replay is deterministic. The marker
  must carry the summary text itself, the covered range / window ordinal, and ideally a summary hash
  — not just "a boundary happened". Without the summary in the log, replay must either re-summarize
  (nondeterministic) or re-expand the dropped items (defeats compaction). This marker is what later
  segments can be archived behind (§1).
- **Store the summary as a typed synthetic event, not a text prefix.** A stable prefix string is not
  a trust boundary — a compactor can emit text that mimics user instructions or role labels. Give the
  summary a non-user role/source on its event, escape embedded role-like text, and make replay
  serialize it so it can never become a user message or carry authority (the "history is content, not
  authority" rule applies in full).
- **Keep/drop rules decide what survives, and the kept set must shrink.** Keep: the recent
  conversational tail (the last user/assistant turns), the compaction summary itself, and still-
  authoritative system/hook prompts. Drop or subsume into the summary: older user/assistant turns the
  summary now covers, instruction/developer wrappers, session-prefix scaffolding, and stale
  tool-call / function-output / reasoning items. Keeping *every* user and assistant message across
  compaction re-bloats the window and duplicates what the summary already says — compaction must
  actually reduce the kept set, not just relabel it.
- **Re-filter provider-produced compaction output.** A remote compactor can echo stale or duplicated
  instruction content; run the same keep/drop filter over its output before trusting it.
- **Re-inject durable initial context at a deterministic position** relative to the summary (the
  fixed system/tool context must survive compaction). Be explicit and consistent about whether fresh
  context goes before or after the summary and the last user message; an inconsistent injection point
  produces subtly different model behavior across compaction paths.
- **Fallback when even the summary plus recent turns do not fit:** trim the oldest/largest tool-call
  and tool-output records to fit the window, preserving the conversational messages. Trimming bulky
  tool output is less damaging than dropping user/assistant turns.

## Non-negotiables

- The append-only log is the source of truth; any index/cache is derived and rebuildable.
- Crash-safety requires the §2 preconditions: one exclusive writer per session, whole-record atomic
  append, `fsync` before acking Flush, and a monotonic sequence number.
- Flush the log before signaling turn/session finality; never let a completion signal outrace the
  writer. The same checkpoint discipline gates external commitments mid-turn: flush the recorded
  prefix before model dispatch and before a tool's external side effect, and a failed checkpoint
  blocks the action, fail closed.
- A failed persist/flush is raised and made observable, never swallowed as empty success.
- Always persist the structural markers (session meta, turn context, compaction) that replay needs.
- Truncating a persisted payload is allowed only if it matches what the model saw (or the full
  payload is stored out-of-line); never claim faithful replay while persisting less than the model
  consumed.
- A "clear" is a persisted epoch marker (or a new session id), never an in-memory reset the log
  would resurrect.
- One live writer per session; resume/fork copies from a validated high-water snapshot, not a
  concurrently-appended file.
- Resume/fork restores token-usage and compaction-window accounting, not just messages; forks record
  parent lineage; replay tolerates a truncated final record.
- **Resume** validates a **config lock** and fails closed on drift (replay runs read-only against
  recorded config; fork records a fresh lock + lineage). The lock captures canonicalized
  behavior-affecting values including runtime-resolved ones (not just raw layers) under one specified
  canonicalization scheme; sensitive-but-behavior-affecting fields (instructions, policy text,
  endpoints, identifiers) are locked by id+keyed-digest and drift surfaces as which-fields-changed,
  value diffs operator-only — the resume error is not an exfiltration channel. The lock detects drift
  without restoring authority (current policy still enforces), strips its own control knobs, gates on a
  resolution-semantics version (not raw build), classifies drift into typed migration/acceptance
  classes (never one coarse bypass), is scoped per config-authority boundary (normally root session),
  and is pinned as the turn's authority + re-checked (CAS) before side effects to close the
  check-then-act window.
- Replayed/resumed history is untrusted content and does not re-grant permissions.
- The compaction marker carries the summary, covered range, and window ordinal so replay is
  deterministic; the summary is a typed non-user event that can never become user input or authority;
  compaction must shrink the kept set, and bounded growth needs segmented logs + durable checkpoints.
- A compaction summary is marked as a summary, recorded as a log marker, and produced/accepted only
  after the keep/drop filter; durable system/tool context is re-injected at a deterministic position.
- Every item in the client-dispatched envelope is accounted for as reconstructable-raw, reconstructable by immutable
  reference (digest + policy-aligned store), or explicitly non-reconstructable with reason;
  accounting assertions check completeness and classification, never force raw persistence; secrets
  stay reference-resolved — a leaked secret classifies non-reconstructable with an explicit
  no-digest note and a typed exposure event as metadata — and a digest that is the only
  residue of an item is keyed, never plain.

## Routing

- The Agent Loop bounds (max turns/tokens/time), tool-result re-entry, and "history is not authority"
  rule live in `retrieval-agent-safety.md` — this reference is the persistence/compaction layer
  beneath them.
- Background-writer finality and flush-before-completion as a *terminal-UI task* concern →
  `terminal-cli-dev` (this reference covers the session-log durability concern; keep them aligned).
- Durable session metrics, session-index health, and compaction-rate signals → `platform-observability`.
- Replaying a session log to reproduce a bug or a bad turn → `defect-diagnosis`.
- Rollout/migration of a session-file format change or a default-compaction-policy change →
  `platform-release-engineering`.
- Generic relational-store/index durability mechanics (if the index grows into a real service DB) →
  `go-microservice-architecture` / `python-service-architecture`; the agent-session semantics stay here.

## Remote or externally controlled agent sessions

For remote or externally controlled agent sessions, keep session/worker credentials scoped to the transport instance, not process-wide environment or shared client globals that untrusted or user-configured tools can read. Account switch, logout, or re-enrollment must clear stale credential caches before any new control channel can send requests.

## Runtime workspace-scope changes

Treat runtime workspace-scope changes as permission-boundary transitions, not UI preferences. Adding, removing, or persisting working directories must validate a canonical directory identity before it can affect tools: expanded path, platform-normalized path form, stable filesystem identity or realpath-equivalent where available, existence, directory type, accessibility class, root/parent/child/sibling relationship to current working roots, source scope, session versus persisted lifetime, principal/session/workspace identity, policy version, root-set generation, and approval request id when user-mediated. Serialize root-set transitions or use compare-and-swap generation fencing so memory state, persisted settings, approval caches, and sandbox allowlists cannot commit on different generations; revalidate the directory identity before persistence, sandbox refresh, and first use, and fail closed if it changed. A narrower or duplicate child root must not widen scope; any sibling, unrelated, broad home/drive/root, or broader parent root that expands reachable resources needs explicit approval and policy allowance naming the widened resource set. Every root-set change must invalidate cached allow decisions, planned tool invocations, permission suggestions, file/source caches, prompt-visible file context, and sandbox allowlists keyed to the old root set. Scope shrink or removal must also make stale reads, writes, shell commands, late callbacks, resumed sessions, and queued filesystem-capable actions re-authorize against the new root set or fail closed. Persisted-scope writes need clear success, failure, rollback, or partial-finality semantics so a runtime cannot report durable access that exists only in memory. Refresh sandbox configuration synchronously before the next filesystem-capable command after any root-set change, and treat refresh failure or stale config as permission uncertainty rather than allow. Diagnostics may expose bounded categories and counts, but not raw local paths, sensitive project structure, denied path values, or full command contents; route sink policy to `platform-observability`.

## Persisted settings/config migrations

When persisted agent/runtime settings migrations change model/runtime choices, permission modes, tool approvals, tool-source scope, or default safety behavior, treat the migration as a runtime policy change: invalidate prompt/tool caches keyed by old settings, recompute model-visible tool schemas, require fresh execution-time authorization, preserve explicit deny/revocation and narrower scopes, and replay representative allow/deny/resume/dynamic-tool-change traces after migration.

## Session discovery, resume, and fork

Treat session discovery, resume, and fork as provenance-boundary transitions, not log browsing or convenience startup. A resumable session must be selected and reopened only after binding the candidate to an exact tuple: principal, account, tenant, organization, or explicit absent-scope markers; workspace or repository identity; canonical working root; branch or worktree identity when present; privacy/data-residency state; session id; transcript artifact identity plus content digest, signed or manifested transcript generation, or monotonic durable append/high-watermark identity; current session incarnation; policy and permission generation; tool/capability generation; prompt/model generation; and source trust scope. Search text, custom names, summaries, tags, branch labels, project paths, modified times, and indexes are discovery hints, not authority; discovery indexes and results themselves must be scope-authorized and redacted before model or UI exposure, and cross-workspace discovery may expose only sanitized existence or counts until an explicit directory/session switch is authorized and revalidates the tuple. Ambiguous matches, stale metadata, missing transcript proof, auxiliary/background transcripts, and current-session self-matches must be suppressed or fail closed; cross-workspace candidates require an explicit switch and tuple revalidation before model-visible context or tools are restored. Resume must open a stable immutable snapshot or locked generation across candidate selection, transcript open, rehydration, and fork-copy preparation; revalidate transcript identity and high-watermark immediately before restoring context/tools or copying a fork prefix; and reject concurrent append, delete, rename, compaction, or partial-copy drift. Resume must clear or revalidate stale file, skill, memory, prompt, approval, session-message, tool, capability, tool-server, connector, and settings-derived caches before rehydration; restore cost, content-replacement, attribution, worktree, task, and metadata state only when the stored tuple still matches or an explicit migration policy says which fields may carry forward.

## Forked session incarnation and boundaries

Forked sessions need a new session incarnation and parent-child boundary. Copy only the authorized per-message conversation prefix through a verified fork point after checking each message, attachment, replacement record, summary, and source-scope provenance label; summaries that merged differently scoped parent sources must be rejected or replaced with typed redacted markers. Preserve ordering and tool-use/tool-result pairing, remap durable message ids, record parent session and fork-point provenance, and reject fork points outside the selected transcript chain or stable snapshot. Copied-prefix effect and finality records must be preserved as immutable parent provenance and no-reexecute barriers; committed or unknown effects must block automatic retry in the child until reconciled. Do not inherit undo history, removable worktree ownership, pending approvals, permission bypasses, live background tasks, remote-control credentials, prompt/tool caches, or usage counters unless each item is explicitly rebound to the child tuple or intentionally omitted with degraded finality. Parent and child transcripts, cost/accounting, cached approvals, file-history state, replacement records, memory writes, side-effect ledgers, usage counters, and diagnostics must stay distinguishable so a child cannot mutate, delete, share, rerun, or bill against the parent by accident. Diagnostics may expose bounded categories, counts, and sanitized reason codes, but not raw prompts, local paths, branch names, transcript contents, session ids, credentials, or free-form metadata.

## History and transcript synchronization

History or transcript synchronization must preserve ordering across initial replay, live writes, echoes, reconnect, and server-side replay. Use durable message ids, monotonic sequence or cursor state, ack/high-watermark advancement only after durable write, bounded deduplication, flush gates, explicit gap detection, and fail-closed stop/resync behavior when replay or ordering is ambiguous.

## SDK/headless/remote protocol streams

SDK, headless, or remote-agent protocol streams are runtime control planes, not plain logs. Define a versioned frame envelope, discriminated message types, one-message-per-frame serialization rules, safe line/framing escaping, schema validation for every inbound control and data frame, maximum frame/queue sizes, unknown-type behavior, and parse-error finality. Outbound control requests need stable request ids, cancellation frames, one writer or ordered outbound queue, pending-request cleanup when input closes, duplicate or orphan response suppression, and response binding to the pending request, tool/action id, session/transport incarnation, policy/capability version, and normalized payload digest. Streamed deltas must either be reconstructable from durable prior state or emitted as self-contained snapshots; retries, reconnects, and late completions must not duplicate mutable messages, lose terminal results, or re-open a completed authorization/action path.

## Protocol-to-transcript adapters

Remote/headless protocol-to-transcript adapters are model-visible finality boundaries, not display glue. For each entrypoint mode, define which protocol messages become assistant, user, system, stream, permission, progress, history, or status-only local state; bind conversion to session/incarnation, transport generation, history cursor or live-stream generation, message id or bounded dedupe key, tool-use id where present, and viewer versus actor role. Live user-message echoes must be deduplicated without hiding historical user messages; remote tool-result messages must clear in-progress tool state even when user messages are otherwise not rendered; task, progress, compaction, and heartbeat/status signals must update counters, loading, timeout, and stale-spinner state without polluting the model-visible transcript. Product-visible status requires either a bounded typed marker outside the model-visible transcript or a lower-precedence redacted meta/status record with no raw protocol payload. Result messages need separated terminal finality and display policy: success may be status-only, but errors and unknown finality need visible degraded evidence. History pagination and replay must preserve scroll/anchor or cursor position, suppress duplicate init/setup records, cap fill loops when many protocol events convert to no visible message, and treat failed pages as retryable degraded state rather than end-of-history truth. Connection gaps, reconnect, direct-connect, remote-shell, viewer-only, and live actor modes need explicit state reset or reconciliation for pending permissions, streaming fragments, in-progress tools, background task counters, response timers, and title/suggestion side effects; diagnostics may expose bounded categories and counts, not raw messages, tool names, session ids, transport endpoints, command labels, stderr, prompt text, payload bodies, credentials, or free-form remote errors.

## Machine-readable stdout purity

When a CLI, SDK, or headless runtime declares stdout as a machine-readable protocol channel, treat stdout/stderr separation as part of the protocol contract. Install any stdout purity guard before the first structured write; allow only complete structured frames or tolerated blank separators on stdout; divert human text, debug prints, dependency banners, setup warnings, progress lines, and console-style telemetry output to stderr or an approved diagnostic sink with a bounded marker. Structured error results that are part of the machine-readable protocol may go to stdout; human-readable validation, setup, and degraded-mode messages go to stderr unless a versioned protocol frame carries them. Guards must be idempotent, preserve writer callbacks or backpressure semantics where the host exposes them, buffer until frame boundaries before classification, flush or divert partial buffered text during abort, exception, broken-pipe, forced-close, and shutdown paths, restore the original writer during cleanup, and surface diversion as sanitized diagnostics without recording raw prompts, paths, credentials, payload bodies, account/session/principal/workspace identifiers, transport or request ids, raw stdout/stderr byte chunks, or free-form diverted lines. Disable or reroute console exporters and other background emitters that can write formatted objects to stdout while the protocol channel is active. Language-level writer guards are not enough when subprocesses, native extensions, inherited file descriptors, or host wrappers can write to the same channel; use fd-level capture/isolation or explicit child-process stdout routing for every spawned or embedded emitter under machine-readable mode. A polluted, truncated, or mixed stdout stream is a protocol failure, not a recoverable parser warning, unless the protocol defines versioned, bounded, self-delimiting resynchronization that is bound to the current generation, clears or tombstones pending requests safely, preserves durable high-watermarks, and cannot re-open completed authorization or action paths.
