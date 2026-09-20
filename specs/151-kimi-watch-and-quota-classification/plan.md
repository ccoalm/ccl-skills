# The watcher guard is a belt, not an admission requirement

The Kimi review lane installs a generated packet-only `config.toml` into a
private runtime home and validates it with `kimi doctor config` before any
inference. This round adds a watcher guard to that config, sets the watcher
override on every invocation, and classifies provider quota exhaustion apart
from authentication failure. It is written after the first candidate was
reviewed; the review's open finding is dispositioned here, and the closeout
records that this plan did not exist before those edits.

Artifact classification: `gate implementation`. The lane's admission rule and
its failure classification both change: a new terminal reason for an
unusable runtime config, and a new `quota` reason code ahead of the existing
auth branch. The set of results that count as a review pass does not change —
every new branch is `die_inconclusive`, which is not a pass.

Risk tags: `shared-gate`, `external-integration`, `security-review`
(change-triggered arm). Visible surface: no — the changed surface is the
wrapper's JSON envelope and its private runtime config.

Security posture: unchanged. The isolation boundary is the generated `[tools]`
allowlist plus the tool_use scan, and neither changes here. The watcher is a
filesystem-change subscription, not an invocable tool surface; on `main` today
it runs enabled, so no path below is weaker than what ships now. The generated
config is still written to a temp sibling, semantically re-verified, and
`chmod 0600` before `os.replace`.

## Outcome and scope

In scope: `skills/code-review/scripts/kimi_review.sh`,
`skills/code-review/scripts/test_cli_review_wrappers.sh`,
`skills/code-review/scripts/AGENTS.md`, this plan.

The directory contract already forbade pinning the lane to one release's
vocabulary, but its text covered only the parser judging runtime output. The
same class re-entered through the config the wrapper writes, which is the third
instance; the rule is widened to both directions rather than patched at one
more site.

Three behaviors:

1. **Watcher guard.** The generated config carries `[watch] enabled = false`,
   the semantic verifier requires exactly that table, and all four Kimi
   invocations (doctor, capability probe, inline formal, MCP formal) set
   `KIMI_CODE_WATCH=0`.
2. **Runtime-compatibility fallback** (this session's disposition of the open
   review finding). If `doctor config` rejects the generated config, the lane
   regenerates it once without the `[watch]` table and revalidates. Only a
   second rejection is terminal. The generator reads the runtime config it is
   about to replace, so the retry's input is the previous generation; the
   generated marker comment is dropped on the way in and re-added, which keeps
   the regenerated file byte-equivalent to a first-pass `omit` generation
   instead of accumulating a marker per attempt.
3. **Quota classification.** A probe failure whose stderr carries provider
   quota wording is reported `kimi_quota` / `quota` instead of being folded
   into the auth or generic capability class. Digit-boundary guards keep byte
   and line offsets from matching an HTTP status code.

Out of scope: the `EMFILE` classification (unchanged, predates this round),
the OpenCode and Codex wrappers, and the cascade policy that consumes
`cascade_eligible`.

### Why the fallback, and why it is not a weakening

Read from the installed runtime (`kimi` 2.0.2), `isWatchEnabled()` consults the
environment first and returns the config-derived value only when the variable
is absent or empty:

```
function isWatchEnabled() {
  const raw = process.env[WATCH_ENV]?.trim().toLowerCase();
  if (raw !== void 0 && raw.length > 0) {
    if (FALSE_WATCH_ENV.has(raw)) return false;
    if (TRUE_WATCH_ENV.has(raw)) return true;
  }
  return watchEnabledFromConfig;
}
```

`WATCH_ENV` is `KIMI_CODE_WATCH`, `FALSE_WATCH_ENV` contains `0`, and the
config section and its environment binding are registered together. So on the
build this repository runs against, the environment override alone already
disables the watcher, and the table is redundant belt. Claim scope: this is
read from one installed build, not asserted for every release — which is
exactly why the table is kept wherever the runtime accepts it and only dropped
where it would otherwise cost the lane.

Failing closed on a rejected table would trade a certain, total lane outage for
a guard that, on this build, the environment variable already provides. It
would also re-introduce the failure this directory's contract names twice
already: pinning the lane to one release's vocabulary took every Claude lane
down while proving nothing. The fallback config is a strict subset of the
rejected one, so the retry cannot admit anything the first attempt would have
refused, and the retry is unconditional rather than matched against the
runtime's error wording — matching the wording would be the same pin again.

## Acceptance decision table

| Runtime behaviour under `doctor config` | Generated config on the attempt that is used | Lane verdict |
| --- | --- | --- |
| Accepts the config carrying `[watch]` | `[tools]` + `[watch] enabled = false` | admitted; review proceeds |
| Rejects a config carrying `[watch]`, accepts one without it | `[tools]`, no `watch` table | admitted; review proceeds, watcher still off via `KIMI_CODE_WATCH=0` |
| Rejects both attempts | — | `kimi_packet_only_config_unrecognized` / `capability_missing`, cascade-eligible |
| Config generation itself fails | — | `kimi_packet_only_config_failed` / `capability_missing`, cascade-eligible |

| Probe stderr | Reason | Reason code |
| --- | --- | --- |
| `EMFILE` / too many open files | `kimi_host_resource_exhausted` | `client_unavailable` |
| Weekly/usage-limit or quota-exceeded wording, no auth envelope | `kimi_quota` | `quota` |
| `403` auth envelope naming a weekly limit or exceeded quota | `kimi_quota` | `quota` |
| `403` auth envelope mentioning quota or limit metadata only | `kimi_auth_unavailable` | `provider_unavailable` |
| Auth status or wording, no quota wording | `kimi_auth_unavailable` | `provider_unavailable` |
| Bare `authentication` wording with no status code | `kimi_tool_capability_unverified` | `capability_missing` |
| Numeric offsets that merely contain `429`/`403` | `kimi_tool_capability_unverified` | `capability_missing` |

Every row below the first table's first two is a non-pass. No row turns a
failed probe into a review result.

## Test and register coverage

`skills/code-review/scripts/test_cli_review_wrappers.sh`, registered in
`make test` through `test-code-review` and in CI through
`code-review-regressions-1/2`.

Cases, one per new row:

- `doctor_reject_watch`: doctor rejects a config containing `[watch]`; the lane
  is admitted on the retry, the installed config carries no `watch` table,
  carries exactly one generated marker, and every invocation still reports
  `KIMI_CODE_WATCH=0`. The stub answers the doctor stage only, so its formal
  stage is mapped to the ordinary clean verdict — the case proves the lane
  survived, not that a rejection produces a pass.
- `doctor_reject_all`: doctor rejects both attempts; terminal
  `kimi_packet_only_config_unrecognized`, cascade-eligible.
- The watcher-guard assertions run under an inherited `KIMI_CODE_WATCH=1`, so a
  dropped override at any of the four sites fails the case rather than passing
  on the ambient value.
- `capability_quota`, `capability_auth`, `capability_auth_quota_mention`,
  `capability_auth_limit`, `capability_auth_word`, `capability_offset`: one per
  classification row above.

Falsification: each case must fail when its own behavior is removed. Mutations
applied on copies of the scripts directory, each differing from the candidate in
exactly one line, and each observed to fail its owning case for its own reason:

| Mutation | Cases that turn RED |
| --- | --- |
| Retry removed; first rejection terminal again | the fallback case only |
| `omit` mode still writes `[watch]` | the fallback case (no `watch`-absent config) and the terminal case (the omit generation now fails its own semantic check, so the reason changes to `kimi_packet_only_config_failed`) |
| `KIMI_CODE_WATCH=0` dropped from the capability probe alone | all four watcher-override assertions |
| Digit-boundary guard removed from the quota regex | the numeric-offset case only |

## Verification

`make test`; `test_check_ccl_regressions.sh --heavy-only`;
`python3 scripts/check-public-sanitization.py .`; `git diff --check`;
`check-ccl-skills.sh` with a base ref. Live Kimi inference is not available —
the account is quota-exhausted, which the lane itself now reports as
`kimi_quota`; recorded as blocked external verification rather than a pass.

## Status sync

No status source, release version, or catalog field changes.

## Review gate

One review and one challenge over the final candidate through the repository's
review gate, risk tag `shared-gate`; findings verified and dispositioned before
the pull request. The prior candidate's review findings are carried into this
round's disposition rather than treated as discharged.
