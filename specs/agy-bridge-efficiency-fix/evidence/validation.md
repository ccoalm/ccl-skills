# Validation: Antigravity Bridge Shadow Identity and Byte-Chunked Skill Reads

Runs use synthetic data in private temporary directories on Linux (`agy` 1.5.14, Python 3.11, Bash 5.2). Host-format evidence comes from local Antigravity transcripts, which were read in place and never copied into the repository.

## Behavioral Evidence (`RED-baseline`, constructed scenarios)

| Case | Baseline `c05fb28` | Candidate |
| --- | --- | --- |
| Reproduction probe: three `edit_file` events in one conversation | `deny` `First source-edit skill checkpoint` three times, three distinct checkpoint epochs | first `deny`, later `allow` |
| Reproduction probe: `Partial read` header over a valid `grill-me` body | 0 of 80 lines covered (control: the same body under `Showing lines` covers 80 of 80) | full coverage when the chunks verify |
| `hooks/test_agy_bridge.py`, final candidate tests with the baseline bridge in a disposable copy | 16 failures and 6 errors, every new case. Each error is a missing behavior: no shadow file left to stat, no sweep, no single canonical copy, no byte-chunk coverage to measure or combine, and an idle event that removes the file at the shadow path | 60 tests OK |

T1 initially passed on the baseline. On ext4 the inode the baseline unlinked was often handed straight back to the next event's temp file, so the identity looked stable by accident. Whether it stays stable depends on what else allocates inodes in between, such as the checkpoint's own attempt directories. On tmpfs, inode numbers never repeat. T1 now keeps the bridge state on `/dev/shm` when it exists, and the baseline then fails it 3 of 3 runs for the intended reason (the second edit is denied). T2 pins persistence of the inode on any filesystem.

## Killing-Mutation Walk

Each mutation was applied to a disposable copy of the candidate. The owning test ran RED, and the owning class was run to list every failure.

| ID | Protected predicate | Mutation | Owning test |
| --- | --- | --- | --- |
| M1 | Chunk bytes equal the canonical stream | Drop the byte comparison | `test_incomplete_or_mismatched_chunks_are_not_a_load` |
| M2 | Header byte total equals the stream size | Drop `size != len(stream)` | same |
| M3 | Header line total equals the skill | Drop the line-total check | same |
| M4 | A row counts only inside one verified interval | Count any row whose interval index exists | `test_a_cut_line_counts_only_once_some_chunk_shows_it_whole` (four other chunk tests also fail) |
| M4b | A row's separator byte must be shown | Drop the separator from the required span | `test_every_separator_byte_must_be_shown` |
| M5 | Mid-character back-off accepted | Remove the back-off | `test_an_offset_inside_a_character_counts_where_the_host_really_started` |
| M5b | Back-off stops at the lead byte of the character holding the offset | Derive the start from the body length | same |
| M5c | The earliest header in a result is the tool's | Prefer `Showing lines` wherever it appears | `test_header_like_text_at_the_start_of_a_chunk_body_is_not_a_header` |
| M5d | Byte intervals are kept per skill | Key all skills together | `test_byte_intervals_of_two_skills_never_combine`. After the canonical stream was cached in the same per-skill table, global keying rejected the second skill instead of mixing it, and M5d went green; the test now also requires complete reads of both skills to load both |
| M6 | Shadow has a single link | Drop the `st_nlink` check | `test_an_unsafe_shadow_path_blocks_and_is_not_written_through` |
| M7 | Sweep skips a shadow whose run lock is held | Skip the `flock` | `test_a_new_conversation_empties_only_stale_unlocked_leftover_shadows` |
| M7b | Sweep leaves a shadow without a lock file alone | Create the missing lock | same |
| M7c | Another conversation's unsafe file does not fail this event | Catch only `OSError` | same |
| M8 | Sweep empties a shadow, never removes it | Unlink instead | same |
| M14 | Sweep removes a legacy temp only under its conversation's run lock | Remove without the lock | same |
| M15 | A failing directory listing stays inside the sweep | Drop the outer guard | `test_a_directory_listing_error_never_fails_the_event` |
| M9 | Sweep touches exact shadow names only | Match any `*.jsonl` | same. The first run of M9 stayed green because the unrelated fixture file had no lock file; `other.run.lock` was added so only the name check protects it |
| M10 | Legacy temp names are ASCII PIDs without a leading zero | `\d+` | same |
| M11 | Event end keeps the inode | Restore the old unlink | `test_source_edit_checkpoint_fires_once_per_conversation`, plus the T3 and T4 cases that also rely on the shadow surviving |
| M12 | Event end leaves no content | Skip the truncation | `test_shadow_transcript_is_private_structural_and_empty_after_the_event` |
| M13 | Event end empties the inode it wrote, not whatever holds the name | Close the held descriptor without emptying it | `test_event_end_empties_the_inode_it_wrote_even_after_a_rename` |
| M16 | One canonical copy per skill, whatever ranges are claimed | Key the copy by range (lookup and store) | `test_many_claimed_ranges_keep_one_canonical_copy`. A first mutation that only skipped reuse stayed green because it still overwrote a single copy, so it did not break this predicate |
| M17 | A later write checks that the name still holds the descriptor | Skip the identity comparison | `test_a_replacement_between_two_writes_of_one_event_fails_closed` |
| M18 | An event that wrote nothing touches nothing | Empty by path when no descriptor is held | `test_an_event_that_wrote_nothing_leaves_the_shadow_path_alone` |
| M19 | A later write revalidates the held descriptor (single link) | Plain `fstat` instead of the safety check | `test_a_hardlink_added_between_two_writes_of_one_event_fails_closed`, `test_a_second_write_checks_the_file_before_writing_through_it` |
| M20 | Verified intervals combine across line ranges | Key intervals by range | `test_reads_of_different_line_ranges_combine` |
| M21 | A range read to its end shows its trailing separator | Drop the extension | same |
| M22 | The held descriptor is revalidated before writing | Move the check after the write | `test_a_second_write_checks_the_file_before_writing_through_it` |
| M23 | Body length is checked before any copy | Restore the eager slice | `test_a_right_sized_header_over_a_short_body_is_not_a_load` (peak allocation) |

## Out-of-Repository Rule (machine-local)

`~/.gemini/config/rules/agy-execution-efficiency.md` (1,734 bytes, `trigger: always_on`). A live `agy -p` run asked for the rule by its heading and answered with the heading and `4` items. The paired control asked for a heading that does not exist and answered `NONE`.

## Review pass (R1)

- Reviewed commit: `9e2e6ac`. Packet `c05fb28..9e2e6ac`, base `c05fb28` confirmed as `origin/main` with `git ls-remote origin refs/heads/main`. Reviewer Codex (OpenAI family), stage `release`, risk tags `shared-gate`, `permission-access`. Result: `evidence/review-R1.json`.
- Findings: 14 total (0 P0 / 4 P1 / 10 P2).
- R0 evidence: `check-ccl-skills.sh` with the private alias audit before the pass: `alias_audit_ok`, `r0_status=private-ok`, `ccl_skill_check_clean_ok`.
- Dispositions:
  - P1 sweep lets `BridgeError` from another conversation's hardlinked shadow escape and deny this event: fixed (`except (OSError, BridgeError)`; M7c; stale hardlinked shadow case in T4).
  - P1 sweep without a lock file races a starting event: fixed (a shadow with no run lock is left alone; M7b).
  - P1 an internal row separator could stay unread while every row looked shown: fixed (the separator is part of the required span; M4b; T6b).
  - P1 verifier outcomes and the challenge were not yet recorded: fixed. Outcomes are in Local Verification and the challenge in Challenge pass (C1).
  - P2 back-off not pinned to the lead byte: fixed (M5b). P2 header chosen by regex order: fixed (M5c; T6c). P2 `\d` accepts non-ASCII digits and leading zeros: fixed (M10). P2 rows × intervals scan: fixed with one monotonic pass. P2 privacy test checked only after the last event: fixed (stats after every event). P2 fixture tied to a real skill's size: fixed (synthetic bundled skills). P2 per-skill keying unpinned: fixed (T6d; M5d). P2 `TMPDIR` restore: fixed in the new helper. P2 overstated "every event gets a new identity": fixed in the plan and register row.
  - P2 "the global rule was not requested": rejected. The rule is a requested machine-local deliverable, outside the candidate and never committed.

## Challenge pass (C1)

- Reviewed commit: `ba6aa5e`. Packet `c05fb28..ba6aa5e`, unprimed adversarial framing, same reviewer family and risk tags as R1. Result: `evidence/challenge-C1.json`.
- Findings: 6 total (0 P0 / 1 P1 / 5 P2).
- R0 evidence: unchanged register content since the R1 audit run. Re-run on the final candidate under Local Verification.
- Gate-fireability applicability: no. The candidate changes no gate that decides review evidence.
- Dispositions:
  - P1 event-end cleanup reopened the path, so a rename during the event left the original inode full, and a replacement at the name could be emptied: fixed. The event holds its validated descriptor and empties through it; T3b; M13.
  - P2 legacy temp removed without its conversation's lock: fixed (M14; a lock-held legacy temp survives in T4).
  - P2 a listing error raised mid-iteration escaped the sweep: fixed (T4b; M15).
  - P2 every result rebuilt the canonical stream for its range: fixed. The stream is built once per skill and range, then each chunk is one slice comparison plus one pass over rows and merged spans.
  - P2 the validation record pointed at results it did not yet contain: fixed (this section and Local Verification).
  - P2 bind each chunk to the call's requested `ByteOffset`: rejected, keep. The same class came up in the plan review. A result paired with the wrong call still counts only if its bytes equal that skill's canonical stream at the offsets it states, so it can only report text the agent was actually shown. The requested offset is the tool's vocabulary, and the backed-up mid-character answer echoes it anyway. The invariant the bridge owns is the byte comparison.

## Delta pass D1

- Reviewed commit: `ac6c444`; packet `git diff ba6aa5e..ac6c444`. Generic controller `review_gate.sh --mode review`, because the delta holds no extraction-owned file. C1's P1 was carried verbatim as an open item. Result: `evidence/delta-D1.json`.
- Findings: 4 total (0 P0 / 4 P1 / 0 P2).
- Dispositions:
  - P1 one cached copy of the stream per claimed range, kept even for rejected results: fixed. One canonical copy per skill, with ranges as windows into it (T6e; M16).
  - P1 a later write in the same event reused the descriptor without checking the name: fixed. The name must still hold that inode, or the event fails closed (T4c; M17).
  - P1 cleanup by path when the event wrote nothing could empty a replacement: fixed. That branch is gone, and the sweep handles leftovers of killed events (T4d; M18).
  - P1 verifier outcomes for this candidate were not recorded: fixed in Local Verification.
- Same-class design check: R1 (sweep vs other conversations), C1 (rename during an event) and D1 (replacement between writes) each found a new instance of one class, same-uid interference with the private state directory. Decision: **narrow**. Keep the cheap invariants that stop stale or accidental state from redirecting a write: no-follow open, regular file, own uid, single link, descriptor-and-name identity. Remove the path-based cleanup branch instead of hardening it further. Record that a process with this uid acting deliberately is outside the threat model, because it already owns the `0700` directory (plan, Threat boundary). The scheme this replaces made the same assumption with no checks at all.


## Delta pass D2

- Reviewed commit: `0da41c3`; packet `git diff ac6c444..0da41c3`. D1's open items were carried verbatim. Result: `evidence/delta-D2.json`.
- Findings: 5 total (0 P0 / 5 P1 / 0 P2). D1's three code items did not reproduce.
- Dispositions:
  - P1 the full claimed interval was copied before the body length was checked: fixed. The length is checked first and the bytes are compared through a `memoryview` (T6f).
  - P1 no test pinned revalidation of the held descriptor against a hardlink added between writes: fixed (T4e; M19).
  - P1 verifier outcomes for this candidate were not recorded: fixed in Local Verification.
  - P1 coverage is combined only within one requested line range, so two different ranges that each show part of one row do not combine: first rejected as a conservative miss, then fixed after D3 raised it again (see D3).
  - P1 the packet omitted the unchanged sweep and event-lifecycle code: input scope, not a candidate defect. That code was in the C1 packet, and every later change to it is in the D1 and D2 packets.

## Delta pass D3 and review continuation checkpoint

- Reviewed commit: `f8193a0`; packet `git diff 0da41c3..f8193a0`. D2's two code items were carried verbatim. Result: `evidence/delta-D3.json`.
- Findings: 6 total (0 P0 / 6 P1 / 0 P2). D2's two code items did not reproduce as described. D3 found the tests for them too weak.
- Checkpoint (third delta pass, recurring items). Method changes instead of re-dispositioning:
  - Cross-range coverage was raised in D2 and D3. Changed the design instead of arguing again: intervals in whole-skill coordinates, and a range read to its end counts its trailing separator (T6g; M20, M21).
  - "The packet omits the sweep and lifecycle code" was raised in D2 and D3. Changed the evidence: the next pass reviews the whole candidate from `c05fb28`, so the current code is in its packet.
  - The verifier record was raised in R1, D1, D2 and D3. Closed by Local Verification on the final candidate.
- Dispositions:
  - P1 cross-range coverage: fixed (above).
  - P1 the hardlink test could not tell revalidation before the write from after it: fixed with a write-boundary unit test (T4f; M22).
  - P1 the short-body test could not see the eager copy: fixed with a `tracemalloc` peak bound (T6f; M23).
  - P1 the fixture path was interpolated into a shell script unquoted: fixed with `shlex.quote`.
  - P1 packet scope and P1 verifier record: handled by the checkpoint above.
