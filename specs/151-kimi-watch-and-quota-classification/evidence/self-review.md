# Implementer self-review — round 151

Recorded before the independent review and challenge, on the candidate those
rounds read.

| Concern | Conclusion |
| --- | --- |
| correctness | The retry regenerates from the config it is about to replace. That input is the previous generation, and the filter is idempotent over it: `tools` and `watch` are outside `safe_table_roots` so both are stripped, and the generated marker is dropped explicitly, so the `omit` output equals a first-pass `omit` output. The semantic check is mode-specific — `guard` requires `watch == {"enabled": false}` and keeps `watch` in the allowed roots, `omit` requires `watch` absent and drops it from the allowed roots — so neither mode accepts the other's file. |
| safety | Admission cannot widen on the retry: the second config is a strict subset of the first, `[tools]` is unchanged in both modes, and the tool_use scan is untouched. The retry is unconditional rather than matched on the runtime's error text, so no new parsing of runtime output is introduced. Both install failures and a second doctor rejection remain `die_inconclusive`, never a pass. |
| failure_paths | Four paths exercised: first generation fails (`kimi_packet_only_config_failed`); doctor rejects the table then accepts the subset (admitted); doctor rejects both (`kimi_packet_only_config_unrecognized`, cascade-eligible, carrying the second attempt's exit code); second generation fails (same `..._failed` reason). `doctor_rc` is captured inside the validation helper, so the reason carries the attempt that actually failed rather than a stale value. |
| tests_evidence | Two new fixtures, one per branch, plus a marker-count assertion for the idempotence claim. Four mutations applied on copies of the scripts directory, each one line: removing the retry reds the fallback case only; making `omit` write the table reds the fallback case and changes the terminal case's reason; dropping the override from the capability probe alone reds all four override assertions; removing the digit-boundary guard reds the numeric-offset case only. Full local lane green on the final candidate, plus the heavy lane, the public-sanitization scan and the base-ref repository gate. |
| compatibility | The change strictly widens the set of runtimes the lane admits. On a runtime that accepts the table, behaviour is byte-identical to the prior candidate — one doctor call, the same generated file. Nothing in the JSON envelope's field set changes; `kimi_quota` is a new value of an existing reason field, which consumers already treat as an opaque inconclusive reason. |
| rollout_rollback | No migration, no persisted state, no version or catalog field. The wrapper is stateless per run and the generated config lives in a per-run private runtime home that is discarded on exit. Rollback is reverting the commit. |
| observability_operations | A rejected table now produces a lane that runs instead of an inconclusive result, so the operator loses the signal that a runtime did not recognise the table. That signal was previously a total outage, which is not a usable diagnostic either; the doctor stderr is still captured to the run directory for the failing case. Quota exhaustion is newly distinguishable from an auth failure, which is the operationally meaningful split this round adds. |
| claim_strength | The precedence claim is read from one installed build (`kimi` 2.0.2) — `isWatchEnabled()` consults the environment first and falls back to the config value — and is stated with that scope, not asserted for every release. That bounded claim is exactly why the table is kept wherever the runtime takes it and dropped only where keeping it would cost the lane. No claim is made that the watcher is an isolation boundary; it is a filesystem-change subscription, and `main` ships with it enabled today. |
| high_risk_boundary | The isolation boundary is the generated `[tools]` allowlist plus the tool_use scan; neither is touched, and the `omit` config still fails closed on any root outside its allowlist. The degraded path's worst case equals the posture currently shipping on `main`, so no path here is weaker than production. Credentials, egress, permissions and the packet boundary are unchanged. |

Owner attestations:

- `code-review` — the wrapper's admission contract and its reason vocabulary are
  the changed surface; the directory contract is widened in the same landing so
  the write side of the anti-pin rule is no longer implicit.
- `terminal-cli-dev` — the shell changes are a helper function plus one
  conditional; `set -uo pipefail` semantics were checked for the `if !` guard and
  the exit-code capture, and no user-facing command, flag or exit contract
  changes.
- `testing-strategy` — the two fixtures assert the observable branch outcome
  rather than the implementation, and each was shown to fail under a mutation
  that removes only its own property.
