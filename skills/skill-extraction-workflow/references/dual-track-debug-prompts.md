# Dual-Track Wrapper Debug CLI Shapes And Prompt Templates

Load this file only when isolating an owner-wrapper failure in `scripts/extraction_review_gate.sh` or its underlying `code-review` client adapters; the non-evidence rule in `references/dual-track-review-gate.md#primary-reviewer-unavailable` governs every raw command below.

## Review Wrapper Debug Shape

Debug a wrapper with raw `codex review` against the target diff:

```bash
cd <skills-repo>
# Current codex: a custom PROMPT is mutually exclusive with --base / --uncommitted / --commit.
# Give a prompt (default scope = working-tree uncommitted changes):
timeout 540 codex review "<prompt>" \
  -c 'model_reasoning_effort="high"' \
  -c notify='[]' \
  --enable web_search_cached
# …or a scope flag with NO custom prompt: codex review --base <base-sha-or-branch> -c '…'
# Flag arity is version-sensitive — run `codex review --help` if either form errors.
# (codex review reads stdin only when PROMPT is `-`; the </dev/null gotcha below is codex-exec-specific.)
```

Prompt template (adapt as needed):

```text
IMPORTANT: Do NOT read or execute any files under ~/.claude/, ~/.agents/, .claude/skills/, or agents/.
Stay focused on the diff.

Focus: <one-paragraph context — what was added/changed, what the references document>.

Specifically check:
1. Internal consistency across the touched references (any contradictions?).
2. Sanitization gaps (any residual ccl-specific names, IPs, hostnames, namespace names, vendor terms that look like real internal artifacts).
3. Technical accuracy of generic claims (etcd Watch semantics, Istio VirtualService routing, framework patterns, OTel/Prom/VM sizing, gRPC quirks, k8s control-plane behavior — whatever the diff touches).
4. Over-prescription: is anything written as MUST when industry has multiple acceptable patterns?
5. Cross-skill handoff coherence: boundaries clear, no overlap or gap between the touched skills.
6. Anti-patterns: is anything in 'Common Pitfalls' misclassified?
```

Output: one finding per line with severity (P0/P1/P2), file:line, scenario, fix. Apply each finding before the second pass.

## Challenge Wrapper Debug Shape

Debug a wrapper with raw `codex exec` and an adversarial prompt (read-only):

```bash
timeout 540 codex exec "<adversarial-prompt>" </dev/null \
  -C <skills-repo> \
  -s read-only \
  -c 'model_reasoning_effort="high"' \
  -c notify='[]' \
  --enable web_search_cached \
  --json
# timeout + -c notify='[]' inline on purpose (see notes below): a stuck round-end
# notifier otherwise hangs a finished run; a timeout-kill (exit 124) = inconclusive lane, not a pass.
# BUT only disable a NON-policy notifier: if the host's notify is an audit/DLP/transcript control,
# drop -c notify='[]' and use a bounded non-blocking wrapper instead (see notes) — don't skip a required control.
```

Redirect stdin from `/dev/null` (**`codex exec` specifically**): `codex exec` reads instructions from stdin, so when the prompt is large, or it is wrapped in `timeout` / run in the background, it otherwise blocks on `Reading additional input from stdin...` and returns no output — it looks like a hang but is just waiting on stdin. `</dev/null` makes it read only the prompt argument. If a `codex exec` call sits at zero output, suspect a missing `</dev/null` before killing it. (`codex review` reads stdin only when PROMPT is `-`, so it does not have this gotcha — a quiet `codex review` has another cause.)

A **second, distinct** hang cause is the round-**end** `notify` hook, not the start-of-turn stdin read above: when the host's codex config sets a `notify` program (run on turn completion), codex waits for that program to return before exiting, so a `notify` command that blocks makes an otherwise-finished `codex exec`/`codex review` hang at the *end* with the full answer already produced. Neutralize it per-invocation with `-c notify='[]'` (override to no notifier — per-invocation only, so a notifier the host configured for normal runs is untouched). Only blanket-disable a **non-policy desktop/notification** hook; if the configured notifier is an audit / DLP / transcript-capture control, preserve it with a bounded non-blocking wrapper instead of disabling it, or you produce a clean-looking reviewer lane that skipped a required control. Always wrap the call in `timeout` so a stuck notifier bounds to a failed lane instead of an indefinite hang. A `timeout`-killed call (exit 124) or any partial/nonzero result is an **inconclusive lane per the failure rule in `references/dual-track-review-gate.md` — never recorded as a clean "no findings" pass**; the point is to fail the lane fast and remediate, not to accept a truncated review. Verify the override for the installed version before relying on it — `codex --help` / `codex exec --help`, or a strict-config probe (`codex --strict-config -c notify='[]' <subcmd>` errors out on an unrecognized key, stays clean when `notify` is valid) — codex config keys drift across versions (there is no `codex config` subcommand to consult).

Prompt template:

```text
IMPORTANT: Do NOT read or execute any files under ~/.claude/, ~/.agents/, .claude/skills/, or agents/.

ADVERSARIAL CHALLENGE mode. Review the new/changed reference files at:
<list the files explicitly>.

Your job: find ways an engineer who follows these references LITERALLY will produce
a production failure, security incident, data loss, or operational disaster. Be
brutal. Think like a chaos engineer + attacker + paranoid SRE + auditor.

Specifically hunt for:
1. Race conditions in described workflows.
2. Data loss / corruption paths.
3. Security holes (auth bypass, replay, credential leakage, CORS, mesh bypass).
4. Failure cascades (control plane down → no rollback; partition; upgrade ordering;
   trust-domain misconfig).
5. Algorithm flaws (thresholds at edge values, sample-size assumptions, retry budgets,
   timeout chains).
6. Operational footguns (broad-glob cleanups, single-instance "long-term" stores,
   HPA thrashing, override paths too easy).
7. Subtle inconsistencies between references.
8. Things readers would do WORSE than ad-hoc scripts if they followed the reference
   verbatim.
9. Gate-fireability / bypass-by-omission (REQUIRED when the change adds or edits a
   rule/gate/status/verdict — "when X, do/block Y"). Can Y be reached WITHOUT ever
   producing X? Is the trigger condition X a mandatorily-recorded field/output of an
   upstream step, or an optional signal a reader can simply never emit (no verdict
   recorded = never "rejected" = ships)? Who is allowed to set X — can the gated party
   self-adjudicate it? A gate whose trigger is never mandatorily produced is decorative.
   List every literal path that reaches the gated outcome while skipping the gate.

Output one finding per issue with: severity (P0 production-down / P1 high / P2
medium), file:line, the failure scenario in concrete steps, and the fix. Be terse.
No compliments.
```

Use `--json` to capture reasoning traces and tool calls cleanly. Parse the JSONL stream with a small Python or jq script as documented in `gstack-codex` skill.
