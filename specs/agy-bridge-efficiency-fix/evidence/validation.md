# Validation: Antigravity Bridge Shadow Identity and Byte-Chunked Skill Reads

Runs use synthetic data in private temporary directories on Linux (`agy` 1.5.14, Python 3.11, Bash 5.2). Host-format evidence comes from local Antigravity transcripts, which were read in place and never copied into the repository.

## Behavioral Evidence (`RED-baseline`, constructed scenarios)

| Case | Baseline `c05fb28` | Candidate |
| --- | --- | --- |
| Reproduction probe: three `edit_file` events in one conversation | `deny` `First source-edit skill checkpoint` three times, three distinct checkpoint epochs | first `deny`, later `allow` |
| Reproduction probe: `Partial read` header over a valid `grill-me` body | 0 of 80 lines covered (control: the same body under `Showing lines` covers 80 of 80) | full coverage when the chunks verify |
| `hooks/test_agy_bridge.py`, candidate tests with the baseline bridge in a disposable copy | 10 failures across T1–T6 and the corrected T2. The one error is a copy artifact: the root `hooks.json` was not copied, and that test is unrelated | 48 tests OK |

T1 initially passed on the baseline. On ext4 the inode the baseline unlinked was often handed straight back to the next event's temp file, so the identity looked stable by accident. Whether it stays stable depends on what else allocates inodes in between, such as the checkpoint's own attempt directories. On tmpfs, inode numbers never repeat. T1 now keeps the bridge state on `/dev/shm` when it exists, and the baseline then fails it 3 of 3 runs for the intended reason (the second edit is denied). T2 pins persistence of the inode on any filesystem.

## Killing-Mutation Walk

Each mutation was applied to a disposable copy of the candidate. The owning test ran RED, and the owning class was run to list every failure.

| ID | Protected predicate | Mutation | Failing tests |
| --- | --- | --- | --- |
| M1 | Chunk bytes equal the canonical stream | Drop the byte comparison | `test_incomplete_or_mismatched_chunks_are_not_a_load` |
| M2 | Header byte total equals the stream size | Drop `size != len(stream)` | same |
| M3 | Header line total equals the skill | Drop the line-total check | same |
| M4 | A line counts only when one interval holds all of it | Count any overlap | `test_a_cut_line_counts_only_once_some_chunk_shows_it_whole` |
| M5 | Mid-character back-off verified at the real start | Remove the back-off | `test_an_offset_inside_a_character_counts_where_the_host_really_started` |
| M6 | Shadow has a single link | Drop the `st_nlink` check | `test_an_unsafe_shadow_path_blocks_and_is_not_written_through` |
| M7 | Sweep skips a shadow whose run lock is held | Skip the `flock` | `test_a_new_conversation_empties_only_stale_unlocked_leftover_shadows` |
| M8 | Sweep empties a shadow, never removes it | Unlink instead | same |
| M9 | Sweep touches exact shadow names only | Match any `*.jsonl` | same |
| M10 | Sweep removes exact legacy temp names only | Match any `*.tmp` | same |
| M11 | Event end keeps the inode | Restore the old unlink | `test_source_edit_checkpoint_fires_once_per_conversation`, plus the T3 and T4 cases that also rely on the shadow surviving |
| M12 | Event end leaves no content | Skip the truncation | `test_shadow_transcript_is_private_structural_and_empty_after_the_event` |

Unverified by mutation: per-skill keying of byte intervals (`chunks.setdefault(slug, ...)`). A cross-skill mix needs two skills read under the same line range, and no test builds one.
