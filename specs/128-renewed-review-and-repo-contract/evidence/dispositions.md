# 128 dispositions

## Pass 1 — review (codex), reviewed commit 7aa6ecb: findings, 6 × P2, no P0/P1

| # | Finding | Disposition | Where |
| --- | --- | --- | --- |
| 1 | Receipt directory can be swapped for a link between the checks and the write | fixed: every step after opening the git directory is relative to a no-follow directory descriptor (mkdir, open O_EXCL/O_NOFOLLOW, replace, unlink) | `review_gate.py` `record_local_review`; regression "a linked receipt directory is never written through" covers a link present before the write only — it also passes on the pre-fix code, so the swap race itself is closed by construction and has no deterministic test (unverified by test) |
| 2 | HEAD sampled after the freeze can record a state the reviewer never read | fixed: anchor sampled before and after the freeze, nothing recorded when they differ | `stable_review_anchor`; regression "a freeze that straddles a HEAD or cleanliness change records nothing" |
| 3 | `.claude/CLAUDE.md` quoted twice for a change under `.claude/` | fixed: selected paths deduplicated at first occurrence | `repository_contract_section`; the partial-coverage case now also changes `.claude/notes.txt` and still expects one quote |
| 4 | Hook reads the directory of a quoted `cd "a b" &&` as QUOTED and checks the wrong repository | fixed: a quoted leading directory is read from the original command before masking, matched and never evaluated | `hooks/remind-review-covers-head.sh`; two quoted-space cases, red on the pre-fix hook |
| 5 | Non-UTF-8 repository path or resolve error escapes the best-effort block | fixed: decode and resolve are inside the block and return coverage `unavailable` | `repository_contract_section` |
| 6a | Evidence gap: complete-mode profile may lack `repository_contract` | source-refuted: complete mode builds its profile through the same `freeze_review_profile`, which always sets the key (default `None`); the full lane's complete-mode cases read results carrying it | `freeze_review_profile` signature default; `make test` rc=0 |
| 6b | A deadline crossed after the receipt is written turns a recorded review inconclusive | fixed: one clock read decides both the verdict and the receipt | success branch in `main` |

Differential for the fixes: the new controller suite on the pre-fix controller turns red on the dedupe case and the anchor-stability case; the new hook suite on the pre-fix hook turns red on both quoted-cd cases.

## Pass 2 — challenge (codex, focus: false-quiet hook, egress, human-deferral surfaces), reviewed commit 26ea963: findings, 1 × P1, 4 × P2

| # | Sev | Finding | Disposition | Where |
| --- | --- | --- | --- | --- |
| 1 | P1 | A bare `--diff-file` or `--paths` review from a clean newer HEAD records that HEAD as covered | fixed: the receipt is recorded only when the candidate is derived with `--base` from the whole worktree; the extraction delta pass now uses `--base <reviewed commit>` | `review_gate.py` main; `dual-track-review-gate.md` step 5; regression "a bare --diff-file review records no receipt" |
| 2 | P2 | `git commit ... && gh pr create` is judged against the pre-commit HEAD | fixed: a HEAD-moving git segment before the pull-request operation disables the covered fast paths and names the reason | hook; regressions "commit in the same command" (red on the pre-fix hook), "HEAD moves only after the PR opens" (quiet) |
| 3 | P2 | `--help` anywhere silences a later real pull-request operation | fixed: help is judged per command segment | hook; regression "help then action" with `--help ;` (red on the pre-fix hook) |
| 4 | P2 | The git directory path can be replaced during the review | fixed: the anchor records the git directory's device and inode; the writer opens it and refuses a different identity | `local_review_anchor`, `record_local_review`; regression "a git directory swapped during the review is never written into" (with a matching-identity control write) |
| 5 | P2 | Evidence gap: contract confidentiality rests on the unseen reader | source-refuted with added evidence: `read_bounded_regular_file` opens every component from the root with O_NOFOLLOW, refuses st_nlink != 1 and a change during the read, and re-verifies the path; regression "a contract file behind a linked ancestor is omitted and never quoted" |  `review_gate.py` `read_bounded_regular_file`; `test_review_gate.sh` |

## Pass 3 — delta 1 (codex), base 26ea963, reviewed commit 9676e0a: findings, 4 × P2, no P0/P1

| # | Finding | Disposition | Where |
| --- | --- | --- | --- |
| 1 | The original git directory relocated into the tree, its old path a link to it, passes the identity check | fixed: the anchor stores the resolved git directory path; the writer walks it from `/` with O_NOFOLLOW on every component, then checks identity | `open_directory_without_links`; swap test gains the relocated-original and linked-parent cases (red on the pre-fix controller) plus a control write |
| 2 | `gh pr create --draft && git commit && gh pr ready` is judged quiet | fixed: any pull-request operation after a HEAD move in the same command reminds; a move after the last one stays quiet | hook; regression "draft, commit, then ready" (red on the pre-fix hook) |
| 3 | Evidence gap: the reader is not in the delta packet | source-refuted, and the next delta pass carries `read_bounded_regular_file` as non-landing context; added a second-hard-link case (st_nlink != 1) beside the linked-ancestor case | `test_review_gate.sh` |
| 4 | Ledger rows rewritten instead of appended | source-refuted: none of the four rows exists at the base (origin/dev); append-only binds landed rows, and these are this round's unlanded rows, rebuilt in the round's single ledger commit | `git show origin/dev:skills/skill-extraction-workflow/references/source-register.md` has none of them |

## Pass 4 — delta 2 (codex), base 9676e0a, packet = candidate + `read_bounded_regular_file` as non-landing context, reviewed commit 7dac5e9: findings, 3 × P2, no P0/P1

| # | Finding | Disposition | Where |
| --- | --- | --- | --- |
| 1a | The already-opened git directory can be relocated into the tree before the receipt is published | accepted residual, deferred: needs a same-user process to move the repository's own git directory inside a sub-millisecond window after a no-link walk and identity check; the worst case is one non-secret receipt file in the moved directory and an advisory hook reading it; closing it needs per-write re-walks the repository's other writers do not carry. Reopen if a receipt is ever found inside a tree | `record_local_review` |
| 1b | Evidence gap: the contract-to-egress path is not shown | source-refuted: `freeze_packet` appends the section to `packet` before `scan_egress_secrets(packet)` and before the packet file is written; every contract read goes through `read_bounded_regular_file(relative, root=repo, ...)`, and all its failures are caught and recorded as omissions; delta pass 3 carries both as context | `freeze_packet`, `repository_contract_section` |
| 2 | A rooted read that fails part-way leaks the directory descriptors it holds (pre-existing in the shared reader, now reachable once per omitted contract file) | fixed: the failing walk closes what it opened | `read_bounded_regular_file`; regression "failed rooted reads release every directory descriptor" (4 → 254 descriptors on the pre-fix reader after 100 failed reads) |
| 3 | Ledger rows rewritten | source-refuted as in pass 3: the rows are this round's unlanded rows, absent from the base | — |

## Pass 5 — delta 3 (codex), base 7dac5e9, packet = candidate + the complete current contract, anchor, writer and freeze functions as non-landing context, reviewed commit 7202321: findings, 2 × P2, no P0/P1

| # | Finding | Disposition |
| --- | --- | --- |
| 1 | Evidence gap: the reader appears only as a hunk | source-refuted: `read_bounded_regular_file` initialises `fd = -1` and `directory_fds = []`; once a file is open its outer `finally` closes the file and every directory descriptor; a walk that fails before that now closes them itself; the verification walk closes its own descriptors in an inner `finally`; the descriptor-count regression is red on the pre-fix reader |
| 2 | Ledger rows rewritten | source-refuted as in passes 3 and 4 |

## Pass and commit map

The branch was rebuilt before its first push so the four source-register rows land once, in the round's last content commit; the reviewed commits below were local and are superseded by the pushed history. Each result JSON records the candidate it read.

| Pass | Mode | Base | Reviewed commit (local) | Result |
| --- | --- | --- | --- | --- |
| `pass1-review.json` | review | `origin/dev` | `7aa6ecb` | findings (6 × P2); candidate `05bcf89cb8b37cb0` |
| `pass2-challenge.json` | challenge | `origin/dev` | `26ea963` | findings (1 × P1, 4 × P2); candidate `27e16b6fcb17643d` |
| `pass3-delta.json` | delta 1 (review) | `26ea963` | `9676e0a` | findings (4 × P2); candidate `4802f05104327af0` |
| `pass4-delta.json` | delta 2 (review) | `9676e0a` | `7dac5e9` | findings (3 × P2); candidate `6fa93fd35be69ee8` |
| `pass5-delta.json` | delta 3 (review) | `7dac5e9` | `7202321` | findings (2 × P2); candidate `eb0103fad88fb9b2` |

No P0/P1 remains undispositioned. The last delta pass covered the last content commit; later commits carry only this evidence.
