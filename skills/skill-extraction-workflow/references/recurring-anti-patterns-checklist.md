# Recurring Anti-Patterns in Skill Content

Distilled from dual-track review passes across the platform-* skill family + go-microservice-* + python-service-* during one multi-batch real-project extraction. These anti-patterns reappear across skills because they share extraction provenance, B5-style cross-skill updates, or industry myths. Before committing any skill or reference change, scan for these.

## Anti-pattern 1 — source evidence map as provenance dump

**Symptom**: a skill's source evidence map reference (or equivalent) contains real repo names, branch state, dates, module counts, private-package names, contributor habits, or dated re-extraction notes.

**Why bad**: shared skill tree exposes the extraction corpus + process; project changes invalidate the file; new project re-extraction has to delete and rewrite.

**Fix**: replace with a methodology template — describe the *shape* of source coverage tracking (which dimensions to inspect, which mini-map decisions to record, which coverage labels to use) without naming any specific project's artifacts. Real provenance migrates to `~/.<host>/.private-aliases/<project>.yaml`. The shared template tells future extractors *how* to track, not *what was tracked* for this project.

**Grep**: tailor a per-project pattern set. Common ones are real service names, real branch names, module counts, dated re-extraction notes, and the project's own short name. Run the maintainer's `ALIAS_AUDIT_CMD` against `*/references/source-evidence-map.md`.

## Anti-pattern 2 — Platform Boundary table with stack-specific contract names

**Symptom**: a Platform Boundary table (added by B5-style cross-skill update) uses concrete platform contract names from one organization: `base.Request`, `Base{...}`, `logs.CtxInfo/Error`, `filebeat→logstash`, `conf/<env>.yml`, `PSM-style identity`, mandatory middleware names.

**Why bad**: cross-language uniformity is the goal of Platform Boundary, but baking one organization's runtime/logging/config stack into the table forces every reader's product onto that stack.

**Fix**: replace concrete names with reusable role names: "request-metadata envelope", "structured logger interface", "log pipeline", "per-environment static config files", "platform service identifier". Keep the *role* row; route the *implementation* to the relevant `platform-*` skill.

**Grep**: `grep -l "base\.Request\|logs\.CtxInfo\|filebeat\|conf/<env>\.yml\|PSM-style" */SKILL.md`

## Anti-pattern 3 — gRPC error transport via `status.message`

**Symptom**: skill says typed errors ride in the gRPC "status message" field, encoded as JSON.

**Why bad**: gRPC status message is freeform text with size limits, not a structured channel. Standard clients use `google.rpc.Status` with `details` (carried via `grpc-status-details-bin` trailer or framework details mechanism). Packing JSON into status message loses typed retry/security semantics and risks leaking server-rendered text.

**Fix**: "encode structured details via `google.rpc.Status` with `details` (transported via the `grpc-status-details-bin` trailer or the framework's native details mechanism); do NOT pack JSON into the gRPC status message field."

**Grep** (case-insensitive — the Go idiom is `status.Message()`, not lowercase `status.message`; also catch JSON packed into the message): `grep -niE "status\.message|HTTP/2 status message|status\.Message\(\)" skills/*/references/*.md skills/*/SKILL.md`

## Anti-pattern 4 — Internal vocabulary leakage

**Symptom**: skill content uses one platform's terminology as generic vocabulary: `NACOS`, `PSM`, `lane`, `inner-network`, `H5`, `edu`, `infra`, `bizprod`, `idl2py.sh`/`idl2go.sh`, `kerrors.ErrBiz`, `x-token`, `x-app-id`, `ctx_keys`, `ppe-`/`ofe-`, internal hostname suffixes (e.g. `code.<organization>.com` or `<product>.internal`).

**Why bad**: same as anti-pattern 2 — readers from another platform get told to adopt one organization's naming conventions.

**Fix**: replace with role-based vocabulary:
- `NACOS` → "registry-based service discovery (Nacos / Consul / equivalent)"
- `PSM` → "platform service identifier" or `<service>`
- `lane` (when describing platform conventions) → "lane / environment label"
- `inner-network` → "private-network"
- `H5` → "mobile web"
- `edu` / `infra` (as IDL dir names) → `<product-line>` / `<platform-layer>`
- `bizprod` / `biz` (as image namespaces) → `<prod-namespace>` / `<dev-namespace>`
- `idl2py.sh` → "one codegen script per target language"
- `x-token` / `x-app-id` → "auth header" / "app-identity header"
- `ctx_keys` → "tiered context-keys convention"
- `ppe-` / `ofe-` → "designated online/offline lane prefix"

**Grep**: `grep -nl "NACOS\|\\bPSM\\b\|inner-network\|\\bH5\\b\|\\bedu\\b\|bizprod\|idl2py\|idl2go\|x-token\|x-app-id\|ctx_keys\|\\bppe-\\|\\bofe-" */references/*.md */SKILL.md` — also append the maintainer's project-specific tokens via `ALIAS_AUDIT_CMD`.

## Anti-pattern 5 — Dangling internal doc references

**Symptom**: skill text says "see today's X notes" or "see X.md in the platform docs" pointing at internal documents not available in the shared skill tree.

**Why bad**: future readers can't load the referenced doc; ad-hoc inline guidance becomes the only thing they see, and may be vague enough to mislead.

**Fix**: either inline the actual pattern, or link to a stable reference file in the shared skill tree, or remove the reference entirely.

**Grep**: `grep -nl "see today's\|see .*\.md\b\|today's notes\|internal doc" */references/*.md`

## Anti-pattern 6 — `psm` as placeholder in path/key schemas

**Symptom**: a key/path schema uses `psm` as the placeholder: `/{psm}/{namespace}/{key}`, `<psm>.svc.cluster.local`, etc.

**Why bad**: `psm` is one platform family's local naming convention. Other platforms use `service`, `service.name`, `app`, etc.

**Fix**: use `{service}` or `{platform-service-identifier}` as the placeholder, with a one-line gloss on the actual format the platform chose.

**Grep**: `grep -nl "{psm}\|/<psm>/\|<psm>\.svc" */references/*.md`

## Anti-pattern 7 — Cross-language inconsistency

**Symptom**: same architectural decision is stated differently across `python-service-*` and `go-microservice-*`. Example: Go says "avoid splitting into microservices until ownership/scaling/data/release cadence justify it"; Python says "default to microservices for new backend products".

**Why bad**: same backend product gets a different architecture solely because of language choice.

**Fix**: align both skills on the same decision, and route language-specific *implementation* differences to dev skills. When the language genuinely changes the architecture (e.g. Python async runtime affects worker design), call out the divergence explicitly with the reason.

**Grep**: cross-compare the SKILL.md "Architecture Defaults" / "Core Workflow" / opening section of each language pair; look for assertions that contradict.

## Anti-pattern 8 — Outbox vs post-commit MQ ambiguity

**Symptom**: skill says "publish to MQ after the transaction commits" as a normal pattern, while another reference in the same skill says "use outbox" for required async effects. Reader picks the wrong one.

**Why bad**: process death between DB commit and MQ publish loses the message. Required async side effects need outbox-in-transaction; only best-effort effects may go post-commit.

**Fix**: distinguish *required* (outbox in same transaction, dispatched by poller) from *best-effort* (post-commit). Document the promotion criterion: "if a side effect's failure would leave the system in an inconsistent state, it is NOT best-effort — promote it to the outbox."

**Grep**: `grep -nl "after the transaction\|post-commit MQ\|MQ.*after.*commit" */references/*.md`

## Anti-pattern 9 — `additive` field becomes required

**Symptom**: skill says "adding an optional field is compatible" without the caveat that the moment a service starts rejecting requests where the field is absent, it's a breaking change.

**Why bad**: IDL says compatible; handler validation says required; old clients break silently.

**Fix**: "optional is compatible only as long as absent remains accepted forever; new required semantics need a versioned method/message OR a staged compatibility gate."

**Grep**: `grep -nl "adding an optional\|optional field is compatible" */references/*.md`

## Anti-pattern 10 — Generic write fallback to baseline lane

**Symptom**: skill says "when the requested lane has no healthy instance, fall back to the baseline lane" without operation-specificity.

**Why bad**: write requests mutate prod baseline with canary/stress assumptions. Tenant-sensitive reads leak across lanes.

**Fix**: "fallback is operation-specific: read-only idempotent endpoints MAY fall back; writes + tenant-sensitive reads + side-effect routes fail closed when the requested lane has no healthy instance."

**Grep**: `grep -nl "fall back to.*baseline\|fallback to baseline lane" */references/*.md`

## Anti-pattern 11 — Watch reconnect without revision/monotonicity

**Symptom**: skill discusses etcd/config-center watch but doesn't mention persisting last-revision, resuming on reconnect, or handling `ErrCompacted` full-resync fallback.

**Why bad**: stale config remains active after disconnect; reconnect resumes from old position; auth/routing config silently doesn't update.

**Fix**: "persist last-observed revision; resume from `last+1` after reconnect; full resync (re-read all subscribed keys) on `ErrCompacted` or history loss; jittered backoff; readiness probe fails on stale critical-config watcher."

**Grep**: `grep -nl "watch.*callback\|watch.*reconnect\|watcher" */references/*.md`

## Anti-pattern 12 — Fixed-lease lock without fencing

**Symptom**: scheduled job has `lock_lease` + `max_execution_time` but no fencing tokens or renewable leases.

**Why bad**: if execution exceeds lease (GC pause, slow dependency, large backfill), a second pod acquires the lock and both run.

**Fix**: "renewable leases with fencing tokens for jobs whose runtime can exceed one lease window. Renew via heartbeat at < ½ TTL; every write carries the fencing token; second pod's stale token is rejected by the backend."

**Grep**: `grep -nl "lock lease\|max execution time\|max_execution\|lock TTL" */references/*.md`

## Anti-pattern 13 — Silent skip on invalid list-config entry

**Symptom**: skill says "skip invalid entries with warning logs" for list-style config.

**Why bad**: one malformed routing/credential entry disappears, shifting traffic or disabling protection without alerting.

**Fix**: "fail the whole snapshot for security/routing/credentials lists; partial-skip with warning only for non-critical inventory lists with explicit degraded-mode contract."

**Grep**: `grep -nl "skip invalid\|skip.*malformed" */references/*.md`

## Anti-pattern 14 — Lazy endpoint refresh in hot path

**Symptom**: skill says "refresh endpoints lazily on next operation" for service discovery / config center / similar clients.

**Why bad**: refresh + reconnect cost (DNS, TLS handshake) lands on a user request during endpoint churn; concurrent requests stampede the reconnect.

**Fix**: "background goroutine / task refresh on bounded cadence; singleflight on reconnect; serve last-known-good endpoints with bounded staleness while background refresh runs."

**Grep**: `grep -nl "refresh lazily\|reconnect lazily\|refresh on next" */references/*.md`

## Anti-pattern 15 — Recovery middleware ordered after auth

**Symptom**: skill says middleware order is "auth, recovery, ..." or doesn't specify recovery wraps auth.

**Why bad**: panic in session/token parsing happens before recovery wraps it; framework drops connection or crashes process depending on semantics.

**Fix**: "recovery wraps auth, validation, metrics, handler. Order: context injection → recovery → tracing → auth → metrics/logging → handler. Verify panic-catch coverage explicitly."

**Grep**: `grep -nl "middleware.*order\|recovery.*after\|auth.*recovery" */references/*.md`

## Anti-pattern 16 — Storage deletion before traffic drain

**Symptom**: cleanup sequence deletes pod / PVC / object storage before deregistering from service discovery and draining in-flight traffic.

**Why bad**: in-flight requests hit missing state; PVC data destroyed while still being read.

**Fix**: "(1) shift traffic weight to zero, (2) deregister from SD, (3) wait for in-flight drain (documented grace window), (4) snapshot or verify retention on durable storage, (5) delete workloads, (6) delete ephemeral-tagged storage, (7) remove service-level routing/metadata."

**Grep**: `grep -nl "delete.*lane.*storage\|cleanup.*storage\|delete.*workload" */references/*.md`

## Anti-pattern 17 — DELETE without safety gates

**Symptom**: DELETE operation cascades through k8s + mesh + DB in one transaction without protected-flag, dry-run preview, two-person approval, or expected-count confirmation.

**Why bad**: operator typo deletes prod. No mitigation.

**Fix**: "protected lanes (online lanes etc.) require unprotect-then-delete two-step; DELETE requires a matching dry-run preview token; two-person approval for online targets; finalizer pattern + Deleting state; expected_count confirmation prevents racing add; non-empty target requires `force: true` + approval."

**Grep**: `grep -nl "DELETE /lane\|cascade.*delete\|delete cascade" */references/*.md`

## Anti-pattern 18 — CORS AllowAllOrigins + AllowCredentials

**Symptom**: skill recommends CORS defaults with both `AllowAllOrigins: true` and `AllowCredentials: true`, OR with a permissive `AllowOriginFunc` that reflects arbitrary origins under credentials.

**Why bad**: browsers reject `*` with credentials, OR frameworks reflect origin and grant credentialed access to attacker hosts.

**Fix**: "default: explicit allowlist. Production admission rejects AllowAllOrigins+AllowCredentials combinations AND permissive AllowOriginFunc validators. AllowOriginFunc must exact-match against a reviewed list."

**Grep**: `grep -nl "AllowAllOrigins\|AllowCredentials\|AllowOriginFunc" */references/*.md`

## Anti-pattern 19 — `keys_under_root` + `overwrite_keys` letting app overwrite platform fields

**Symptom**: filebeat/log-shipper config uses `keys_under_root: true` + `overwrite_keys: true` without protecting platform-reserved fields.

**Why bad**: compromised or buggy service can emit `_lane=prod` from a non-prod pod; canary queries misclassify; audit searches lie.

**Fix**: "set `overwrite_keys: false` for platform-reserved `_`-prefixed fields. Add pipeline filter that strips/renames app-supplied platform fields and re-injects authoritative values from pod metadata. SDK contract: only platform SDK writes `_`-prefixed fields."

**Grep**: `grep -nl "keys_under_root\|overwrite_keys" */references/*.md`

## Anti-pattern 20 — Chat callback without signature/replay protection

**Symptom**: skill describes chat-platform card click → API callback → approve, without specifying HMAC signature verification, timestamp skew check, nonce/event-id replay check, action-task binding.

**Why bad**: attacker who captures one valid signed payload can replay it to approve arbitrary deploys.

**Fix**: "callback handler MUST verify: (a) platform HMAC signature, (b) timestamp skew (< 5 min), (c) nonce/event-id replay (against recently-seen set), (d) action binding (click's task_id + version + reviewer matches original send), (e) RBAC. All five required."

**Grep**: `grep -nl "chat.*callback\|card.*callback\|approve.*click\|callback/.*card" */references/*.md`

## Anti-pattern 21 — Stack-specific syntax in mirrored sections

**Symptom**: parallel-stack reference (Go + Python files mirroring the same architecture) has DB-engine syntax, runtime-mechanic names, or library/framework API names in the supposedly stack-agnostic mirrored sections — `SET LOCAL`, `BYPASSRLS`, `FORCE ROW LEVEL SECURITY`, `context.Context`, `goroutine`, `contextvars`, `asyncio`, `GORM`, `SQLAlchemy`, `FastAPI`, `run_in_executor`, etc.

**Why bad**: defeats the sibling-sync invariant; the mirrored sections drift between Go and Python; agents copying from the wrong stack produce code that does not run.

**Fix**: each parallel-stack file ends its stack-glue section with a `### Mirrored-section grep gate` (token list + awk-then-grep run command). The grep runs on every commit; zero hits required. See `parallel-stack-references-pattern.md` for the gate shape. Allowed exception: the sibling-sync header itself names the category classes (without tokens) and the routing-reference text may differ per stack (`api-security-boundaries.md` vs `web-framework-boundaries.md`).

**Grep**: run the file's own gate, e.g. `awk '/^## Go-specific implementation patterns/{exit} 1' <file>.md | grep -nE 'SET LOCAL|BYPASSRLS|FORCE ROW LEVEL SECURITY|context\.Context|\bgoroutine\b|contextvars|\basyncio\b|GORM|SQLAlchemy|FastAPI'`

## Anti-pattern 22 — Sibling-sync header self-violation

**Symptom**: the parallel-stack file's sibling-sync header itself contains the tokens it forbids — listing `SET LOCAL`, `BYPASSRLS`, `context.Context`, `contextvars`, `GORM`, `SQLAlchemy`, etc. as examples of what must NOT appear in mirrored sections. The grep gate then matches its own header and always fires.

**Why bad**: the gate is now unusable; maintainers learn to ignore it; the rule it states becomes unenforceable in practice.

**Fix**: header names category *classes* only ("DB-engine-specific syntax, runtime/concurrency-mechanic names, library/framework API names") and references the grep-gate subsection by name. Concrete token lists live only in the grep-gate subsection at the end of the stack-glue.

**Grep**: scan the header (top ~10 lines) for stack tokens; any hit there is the violation.

## Anti-pattern 23 — Body strengthened without checklist sync

**Symptom**: a body section was strengthened in a way that **alters acceptance criteria, required evidence, scope, exception handling, or verification behavior** (R3 added "classify every relation, not just tables with `tenant_id`"; R3 added "denylist propagation barrier before destructive action"; R3 added six evidence artifacts for crypto-deletion). The operations checklist still uses the older weaker rule ("every table with `tenant_id` is enumerated"; "reads consult the denylist"; "the six artifacts recorded").

**Why bad**: checklist regression — a launch verification that passes against the older rule misses what the stronger rule was supposed to catch; the body's safety improvement is invisible to launch readiness.

**Scope (what counts as "strengthening" for this rule)**: body changes that alter (a) acceptance criteria, (b) required evidence, (c) scope of applicability, (d) exception or carve-out handling, or (e) verification behavior. Rationale-only clarifications — explaining *why* an existing rule exists without changing what it requires — do not trigger this rule and should not bloat the checklist with duplicate or wording-only checks.

**Fix**: every qualifying body strengthening update must include the matching checklist update in the same commit. After each dual-track round's fixes, diff the checklist against the body's strengthened sections and verify each new clause that changes acceptance/evidence/scope/exception/verification has a corresponding verification item.

**Grep**: when reviewing a fix-up commit, diff body sections against the operations-checklist section; if a body rule changed any of the five categories above but the checklist did not, flag for fix-up.

## Anti-pattern 24 — Evidence-based carve-outs replaced with categorical ones

**Symptom**: a rule has a carve-out (irreversible-data-loss override of threshold inflation; monitoring-as-primary for external dependencies; crypto-deletion as erasure; large-tenant priority lane on shared accelerator). The carve-out is stated as **categorical** ("for external dependencies, monitoring may be primary"; "irreversible data loss overrides recurrence calibration") with no evidence requirement.

**Why bad**: agents apply the carve-out to any vaguely-fitting case; the carve-out becomes the default; the rule it carved out of is gutted.

**Fix**: every carve-out requires recorded evidence per case. Examples:
- Irreversible data loss carve-out: requires (a) category, (b) repair-impossible evidence, (c) blast radius, (d) narrowest workflow, (e) gate scope.
- Monitoring-as-primary carve-out: requires a prevention-disqualification checklist (boundary contract / idempotency / timeout-retry / capability-auth / contract-replay test / canary) where each applicable gate is marked unavailable with evidence.
- Crypto-deletion as erasure: requires six artifacts (key hierarchy / backup inventory / restore-path test / envelope destruction proof / backup-purge SLA / regulator acceptance) at per-store/per-tenant/per-key-version scope, freshness window, independent countersignature, non-forgeable workflow execution identifier.
- Large-tenant priority lane on shared accelerator: requires a named workload class with a latency SLO or large-prefill characteristic, with the specific isolation mechanism (reserved capacity / priority lane / max-wait admission / dedicated partition) declared.

A carve-out is a contract, not a category badge. Without the evidence row, fall back to the base rule.

**Grep**: search for `categorical`, `override`, `exception`, `carve-out`, `unless` and verify each has named evidence requirements; categorical carve-outs without an evidence row are the bug.

## Anti-pattern 25 — Bypass-role enforcement without bypass-path enumeration

**Symptom**: skill describes engine-level enforcement (RLS / row policies / equivalent) as "the authority" without naming the bypass paths — superuser, BYPASSRLS / equivalent role attribute, table owner unless forced, bulk-truncate / schema operations, logical replication, security-invoker vs definer views, triggers under different roles.

**Why bad**: every real engine has bypass paths; treating engine policy as universal authority means migration scripts, repair tools, replication streams, and admin queries silently bypass the safety the rule promised.

**Fix**: every engine-policy rule must (a) enumerate the bypass paths for the chosen engine, (b) require forced policy enforcement (FORCE RLS or equivalent) where the table-owner bypass otherwise applies, (c) use distinct DB roles for application / migration / admin / replication, none carrying the bypass attribute on the production app path, (d) require explicit tenant filters or offline approval on bypass-role connections, and (e) audit every bypass-role connection — with **both data-plane independence** (audit sink is write-only to bypass roles) **and control-plane independence** (bypass operator cannot modify audit-transport network/DNS/service-account/queue routing) plus an alert on audit delivery gaps.

**Grep**: `grep -nE 'RLS|row-level security|row policy|engine policy.*authoritative' */references/*.md` and verify each hit names bypass paths + role separation + audit-both-planes.

## Anti-pattern 26 — "Reversible step" without time-window classification

**Symptom**: migration / rollback design classifies steps as reversible or irreversible based on structural transforms (ID-scheme reshape, shard-key rewrite, encryption-key envelope change). Time-based irreversibility — TTL, retention purges, token expiry, object-lifecycle rules, backup rotation — is not classified, so "rollback safe" steps become irreversible during the migration window as old state is deleted by clock.

**Why bad**: rollback attempted past a TTL deadline finds the old state already purged; the recorded "last safe rollback point" is in the past even though no explicit structural irreversible step ran.

**Fix**: classify each step's reversibility along **two axes** — structural irreversibility AND time-based irreversibility. Last safe rollback point is the **earliest** of structural-irreversible boundary and any time-based deadline that touches state needed for rollback. Either freeze/extend those timers across the migration window (only where legally permitted — regulator-mandated retention maxima and data-subject deletion SLAs cannot be paused) or compute the rollback point from them.

**Grep**: `grep -nE 'reversible|rollback point|migration step' */references/*.md` and verify each migration rule names both axes.

## Anti-pattern 27 — Repo/worktree identity decided by PATH SHAPE instead of git structure

**Symptom**: a hook, gate, or state-keyed script decides "which repository is this" or "is this checkout already isolated" from a **path-shaped** signal — matching a git-dir string against `*/worktrees/*`, or using `rev-parse --absolute-git-dir` as the identity key. Both read as "the repo" and are correct in the team's own conventional layout, which is exactly why they survive review and local testing.

**Why bad**: neither signal is owned by the control. `--absolute-git-dir` is *per-worktree* (`<common>/worktrees/<id>`), so state written from a worktree is invisible from the primary checkout — and a path-name match on `worktrees/` is decided by the **user's directory naming**, so a primary checkout that merely lives under a directory called `worktrees/` (`~/work/worktrees/<repo>`) is misread as already-isolated and the control **silently fails open**. For a security/isolation gate that means every deny branch is disabled with no error, no log, and a green test suite — the suite's own fixtures are built in the conventional layout, so the trap case never occurs there.

**Fix**: predicate on the git structure the control actually owns.
- **Identity / state key** → `rev-parse --path-format=absolute --git-common-dir` (same value from every worktree of a repo; fall back to plain `--git-common-dir` + normalization for git < 2.31).
- **"Is this a linked worktree"** → compare `--absolute-git-dir` against the common dir; they differ **iff** it is linked. Path names never enter the decision.
- A submodule initialized inside a linked worktree keeps its git-dir under that worktree's admin dir and reports the SAME common dir, so it reads as primary; when "already isolated" must include it, detect the enclosing admin dir by the marker files git writes there (`commondir` + `gitdir`), still never by a directory *named* `worktrees`.
- Any fixture proving such a control must include a layout the team convention does not produce (a checkout under a `worktrees/`-named path), or the probe cannot see the failure.

**Grep**: `find hooks scripts -name '*.sh' -not -name 'test_*.sh' -not -name 'test.sh' | xargs grep -nE '\*['"'"'"]?/worktrees/['"'"'"]?\*'` (non-comment hits), and review every `--absolute-git-dir` whose output becomes a state path or identity key. Stars on **both** sides make it a match pattern rather than a path, so an ordinary `.work/worktrees/*` cleanup glob is not flagged. That spelling is machine-enforced by `check-ccl-skills.sh` (`git_identity_predicate_scan`); two things are deliberately **not** caught and stay human/challenge checks — a fully dynamic pattern (`*"/$seg/"*`) and `--absolute-git-dir` used as an identity key (the same call is legitimate for locating *this* worktree, so grepping it is false-positive-prone).

**Occurrences that promoted it**: `scripts/owner-dispatch/owner-dispatch.sh` (state keyed per-worktree → boundary record written in a worktree unreadable from the primary checkout) and `hooks/guard-edit-isolation.sh` (path-name match → the repo's only edit-time hard-deny gate silently disabled for checkouts under a `worktrees/`-named path).

## Anti-pattern 28 — Process liveness decided by an EXISTENCE test that a corpse answers

**Symptom**: a probe or fixture concludes "this process is still alive" — or "it is a live orphan" — from a test that only proves the pid is still in the process table: `kill -0 "$pid"`, or reading `ps -o ppid=` and comparing it against init's pid. The same suite's verdict scans then exclude zombies (`$stat !~ /Z/`) when deciding the process is *gone*.

**Why bad**: an exited-but-unreaped process is still in the table. It answers `kill -0`, and its ppid still reads — as `1` once it is reparented. So one process state gets two answers: the precondition check says "alive, scenario built", the verdict scan says "gone, nothing leaked", and an assertion between them that samples liveness at one instant says "already dead" and fails. The red then names the code under test for something it did not do, and the failure is intermittent because it depends on when the OS reaps. Worse, the precondition passing means the probe goes on to assert about a scenario it never actually built.

**Fix**: consult process **state**, not existence.
- One vocabulary for the whole probe — a helper returning `live` / `zombie` / `absent` (`ps -o stat=`; empty → absent, `*Z*` → zombie, else live) — used by *every* liveness question, so the checks cannot answer the same pid differently.
- Preconditions require `live`. A corpse is not an orphan; accepting one is how a probe goes on to assert about a scenario that was never constructed.
- Better still, stop asking the process at all: assert on an artifact the run leaves behind — a work dir the cleanup path would have deleted, a marker the fixture writes only on the code path under test. That answers *why* a process ended, which no liveness sample can.
- Never assert liveness by an instantaneous sample; reap lag on a loaded runner needs a bounded grace period. (`testing-strategy/references/ci-fixtures-and-flake-control.md` owns that rule — this row is its firing path.)

**Grep**: `find . -name 'test_*.sh' -o -name 'test.sh' | xargs grep -nE 'ps[[:space:]]+-o[[:space:]]+ppid=.*=[[:space:]]*"?1"?[[:space:]]*\]'` (non-comment hits with no `stat=` / `*_state` consult within two lines). Machine-enforced by `check-ccl-skills.sh` (`liveness_predicate_scan`). Scope is test scripts only: outside them a `kill -0` before signalling asks about existence, which is the right question there. Five things are deliberately **not** caught and stay human/challenge checks — `while kill -0 "$pid"` watchdog loops (two exist here; both wait on a direct child and `wait` for it immediately after, so the shell reaps it and the loop ends), a bare `kill -0` liveness branch inside a loop body, any dynamic spelling, a state-helper mention in a **trailing** comment (whole-line comments are dropped, but telling a trailing `#` from `${var#prefix}` needs a shell parser — the same call Anti-pattern 27 makes), and a process-state read — direct `ps -o stat=` or via a helper — that inspects a *different* pid than the oracle tests, or whose result never reaches the verdict. Both are the same irreducible gap: proving the read actually governs the decision needs dataflow over a parsed shell, not a text window, so this is the limit the mechanical gate stops at by design.

The waiver is a **proxy** for "this site consults process state", not an invariant, and five successive review rounds each found it too loose in a different way — a comment naming the helper, an unrelated `*_state` token, a helper that never reads state, a bare `stat=` assignment, and a hollow helper borrowing an unrelated read elsewhere in the file. Tying a call to its definition needs a shell parser, so the honest disposition is a narrow predicate with these limits stated rather than another round of widening. The mechanical gate is the deterministic catch for the exact recurring shape; this checklist and the adversarial challenge remain the comprehensive net.

**Occurrences that promoted it**: the code-review abort-leak probe red CI three times, each on a different leg-2 assertion, each asserting the probe's environment rather than the suite — the reparent check accepted a zombie, the "still alive right after the kill" check rejected that same zombie, and the verdict scan reported it gone. The rule forbidding this already existed in `testing-strategy`, and the suite's own hang cases followed it while the probe did not: the gap was enforcement, not content.

## How to use this checklist

Before committing any skill or reference change touching operational/architectural rules:

1. Run the grep from each applicable anti-pattern against the changed file set.
2. For each hit, decide: fix in this commit, defer with explicit reason (recorded in private alias `known_debt` if pre-existing), or confirm not-applicable (this skill's context legitimately uses the term).
3. After the dual-track review + challenge pass, re-run this checklist on the new content (passes often introduce new patterns).

The checklist grows over time. Add a new anti-pattern when:
- A pattern appears in 2+ skills and represents a real safety / correctness / sanitization issue.
- A codex challenge finding maps to a class, not a one-off.
- A user correction exposes a class of mistake the workflow should prevent.

## Promoting a symptom to a mechanical gate

These greps are only as strong as whoever remembers to run them — a human checklist does not stop a commit by an agent (or another model) that never runs it. When a symptom keeps reaching shared skills *despite* being named here (e.g. a one-organization contract token that leaked even though it was already listed), promote it from this checklist to a **mechanical gate in `check-ccl-skills.sh`** so it blocks regardless of who commits. Building that detector:

- **Anchor the pattern on the ACTUAL leaked text, not imagined variants.** Read the real leaked instances and extract their invariant (e.g. the leaked field was always the reserved number, always proto-terminated). Broadening by imagination starts a false-positive arms race that blocks legitimate docs — a real version/limit doc that merely mentions the same number.
- **Prefer high precision + a documented recall limit over broad matching.** For a *blocking* gate, a false-positive that blocks legitimate content is worse than a recall gap: the human checklist + dual-track challenge stay the comprehensive net, while the mechanical gate is the deterministic catch for the exact recurring shape. State the accepted recall limit in the script comment.
- Expect a multi-round precision/recall convergence — the challenge will keep surfacing one real FP or FN per round until the pattern matches the invariant and nothing else.
- The new gate will flag this checklist itself and any provenance row that legitimately **quotes** the symptom. Allowlist the symptom-defining file(s) by anchored repo-relative path (not a bare basename, and never a caller-settable env override that neuters the gate), and **reword provenance to non-literal** rather than broadly allowlisting — keep the gate maximally strict.
