# Validation

Base: `origin/main` at `319955d`, confirmed with `git ls-remote` before the review. Every command ran with `CCL_SKILL_BASE_REF=origin/main`.

## Lanes

Results for the final candidate are listed under Final run below.

## Hook tests

`python3 hooks/test_proposed_next.py`: 71 tests pass. Run against the base hook (`git show origin/main:hooks/host-input.py`), the new behavior tests fail; tests guarding existing behavior pass on both.

## Killing mutations

Each mutation was applied to a disposable copy of the hook. Each turned its named test red with an assertion failure, and a copy run also confirmed the file still parsed.

| Mutation | Test turned red |
| --- | --- |
| `origin-any` | `test_recheck_counts_only_a_persons_message_in_the_main_chain` |
| `mode-any` | `test_recheck_counts_only_a_persons_message_in_the_main_chain` |
| `sidechain-msg` | `test_recheck_counts_only_a_persons_message_in_the_main_chain` |
| `non-string-uuid` | `test_recheck_counts_only_a_persons_message_in_the_main_chain` |
| `threshold-9` | `test_recheck_needs_ten_silent_calls_and_any_prose_ends_the_silence` |
| `threshold-11` | `test_message_the_agent_never_answered_gets_one_recheck_without_echo` |
| `prose-no-clear` | `test_recheck_needs_ten_silent_calls_and_any_prose_ends_the_silence` |
| `subagent-counts` | `test_subagent_tool_calls_do_not_count_as_silence` |
| `claim-constant` | `test_a_newer_unanswered_message_fires_again_with_the_running_count` |
| `claim-first` | `test_a_newer_unanswered_message_fires_again_with_the_running_count` |
| `no-delivery-gate` | `test_recheck_waits_for_delivery_evidence` |
| `tail-needs-delivery` | `test_tail_scan_does_not_need_delivery_evidence_it_cannot_see` |
| `join-replaces` | `test_recheck_shares_one_continuation_with_a_declared_action` |
| `state-none-fires` | `test_recheck_stays_quiet_without_its_state_helper` |
| `no-tail` | `test_recheck_survives_a_transcript_past_the_full_scan_limits` |
| `tail-limit` | `test_recheck_survives_a_transcript_past_the_full_scan_limits` |
| `echo` | `test_message_the_agent_never_answered_gets_one_recheck_without_echo` |
| `failure-costs` | `test_recheck_failure_never_costs_the_delivery_reminder` |
| `overflow-drops-note` | `test_recheck_reaches_an_unlabelled_stop_past_the_scan_limits` |
| `overflow-swallowed` | `test_recheck_reaches_an_unlabelled_stop_past_the_scan_limits` |
| `claim-ignored` | `test_concurrent_stops_get_one_recheck` |
| `reading-unreported` | `test_recheck_tells_the_agent_to_report_an_unclear_reading_not_assume_a_request` |
| `assumes-request` | `test_recheck_tells_the_agent_to_report_an_unclear_reading_not_assume_a_request` |
| `retry-fires` | `test_recheck_is_not_spent_by_a_retry_stop` |

## Checked from source, not in the review packet

- `claim_notice` calls `State.claim_attempt` in `hooks/skill-loading.py`, which creates a directory named by a digest of the lane and the epoch. The creation is atomic, and the message uuid is stored only inside that digest.
- `main()` still handles `TranscriptTruncated` and still wraps the result in `with_context_notice`. `test_recheck_reaches_an_unlabelled_stop_past_the_scan_limits` covers the overflow notice, and `test_recheck_rides_with_the_large_context_notice` covers the context notice. `test_concurrent_stops_get_one_recheck` runs eight stops at once and expects one recheck.

## Message-to-stop distance

The tail scan covers the last 16 MiB and 20,000 lines. Across 40 qualifying messages in real sessions, the longest stretch from message to first stop was 9.6 MB and 3,036 lines, so none fell outside it. A longer stretch would lose that message; only the always-on rule covers it then.

## Final run

Pending the last commit.
