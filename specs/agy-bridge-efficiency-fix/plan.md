# Antigravity Bridge: Stable Shadow Transcript Identity and Byte-Chunked Skill Reads

Fix two defects in `hooks/agy-bridge.py` that make Antigravity sessions slower than Claude Code and Codex sessions running the same hooks:

1. **Shadow transcript identity churn.** The bridge rebuilds its shadow transcript for each hook event, swaps it into place with `os.replace`, and unlinks it when the event ends. Every event therefore hands the hooks a new `(st_dev, st_ino)`. `hooks/skill-loading.py` keys its once-per-context checkpoint attempt on that identity (`epoch = [context_id, st_dev, st_ino]`), so the `First source-edit skill checkpoint` denies every source edit instead of only the first one in a context. Claude Code and Codex append to one persistent transcript file, so on those hosts the identity is constant and the checkpoint fires once.
2. **Byte-chunked reads never count as a skill load.** Antigravity `read_file` returns at most 46,080 bytes. A larger read answers with a `Partial read (lines A-B of T). Showing bytes S-E of Z in this line range...` header instead of `Showing lines A-B of T`. `covered_lines()` only recognizes the latter, so reading a large `SKILL.md` with `ByteOffset` chunks never produces the synthesized `Skill` event. The agent then has to re-read the file in small line ranges to satisfy the hooks.

## Extraction Charter

| Field | Answer |
| --- | --- |
| Purpose | Prevent the Antigravity bridge from re-arming a once-per-context edit checkpoint on every event, and from discarding complete byte-chunked skill reads as load evidence. Both make the agent repeat work that Claude Code and Codex sessions do once. |
| Scope | In: `hooks/agy-bridge.py`, `hooks/test_agy_bridge.py`, `specs/agy-bridge-efficiency-fix/` (this plan and `evidence/`), and one row in `skills/skill-extraction-workflow/references/source-register.md`. Out: `hooks/skill-loading.py` policy (unchanged: the defect is the identity the bridge hands it, not the epoch rule); the `Showing lines` path of `covered_lines()` (unchanged); Antigravity's own `read_file` limits; any `SKILL.md` text. The machine-local Antigravity rule file is a separate, non-repository deliverable (see Out-of-Repository Deliverable). No iterative-program watermark applies. |
| Depth | Generator/tooling change: runtime hook bridge plus its regression suite; no skill prose or routing surface changes. |
| Result classification | Failure/correction. Both defects reproduce on the unmodified baseline `c05fb28` (see Baseline Reproduction). |
| Matching analysis | Contributing factors: (1) the bridge's original design rebuilt the shadow atomically and deleted it per event to keep transcript-derived content short-lived. It did not consider that a downstream hook keys state on file identity. (2) `covered_lines()` was written against the `Showing lines` header seen in the first host smoke, which used a small skill, so the byte-limited header never appeared in a test fixture. (3) No test exercised two consecutive edit events in one conversation, and none used a skill larger than the read limit. Counterfactual: with the identity fixed alone, chunked reads still never count, and with chunked reads fixed alone, every edit still re-arms the checkpoint. Both changes are needed. Prevention: regression tests that pin repeated-event identity and the chunked-read header, each shown RED on the baseline. |
| Failure mode | A weak fix could (a) keep transcript-derived commands or assistant prose on disk between events, (b) write through a planted symlink or hardlink at the shadow path, (c) let a cleanup sweep delete another conversation's in-use shadow, (d) count a byte chunk that the tool truncated mid-line, cut at a moved offset, or tampered with as verified skill text, or (e) count a partial skill read as a full load. |
| Lifecycle impact | Implementation and debugging: Antigravity agents stop seeing the source-edit checkpoint deny on every edit, and can read large skills in a few parallel byte chunks. Testing: new regression cases in `hooks/test_agy_bridge.py`. Product intent, design/UX, launch, onboarding: not applicable (no user-visible surface beyond fewer denials). |
| Evidence plan | (1) Baseline reproduction against `c05fb28` with a paired control per form. (2) First-hand Antigravity transcripts on this machine (read locally, never copied into the repository): the real `Partial read` header variants, byte arithmetic and chunk reassembly checked against current skill files. (3) `hooks/skill-loading.py` and `hooks/host-input.py` source for every consumer of transcript identity. (4) The prior design decision in `specs/antigravity-host-support/plan.md` (shadow lifetime). The handoff that reported the defects is a hypothesis source. Each form it registered was reproduced before any code was written. |
| Completion standard | RED on baseline and GREEN on candidate for every new case. An applied killing-mutation walk over the protected predicates. Green focused suites, `check-ccl-skills.sh` with the private R0 audit (`ccl_skill_check_clean_ok`), `make test`, and the npm package tests. Independent review and adversarial challenge recorded under `evidence/`. |

## Baseline Reproduction (`c05fb28`)

| Form | Probe | Baseline result | Control |
| --- | --- | --- | --- |
| Identity churn | Three `PreToolUse` `edit_file` events on a `.py` target, same `conversationId`, no skill loaded | `deny` `First source-edit skill checkpoint` on all three. Three distinct `attempt-*` epochs were recorded in the checkpoint state. | After the fix (same probe): the first event is denied and later events are allowed, as on Claude Code |
| Chunked read | `covered_lines()` on a full `grill-me` body under a `Partial read (lines 1-80 of 80). Showing bytes ...` header | `0` of `80` lines covered | Same body under `Showing lines 1-80 of 80`: `80` of `80` covered, so the fixture body is valid |

## Real Host Format Evidence

Checked against 23 local Antigravity transcripts (`agy` 1.5.14):

- The headers come in two variants: `Partial read (lines A-B of T). Showing bytes S-E of Z in this line range, truncated at the N-byte limit. To read the rest of this line range, call this tool again with the same StartLine and EndLine and ByteOffset=E.` and the final chunk's `... of Z in this line range.`
- The byte offsets index the formatted stream `"\n".join(f"{n}: {line}" for n in A..B)`, measured in UTF-8 bytes, with no trailing newline. `Z` is the size of that stream for lines `A..B`, not the file size.
- In 289 of 291 chunks, the body after the header is exactly `E-S` bytes. The other two came from a `ByteOffset` that fell inside a multi-byte character: the tool backed up to a character boundary but still reported the requested offset. The cut-off hint always gives `ByteOffset=E`, so an agent that follows the hint never hits this.
- All 30 complete multi-chunk groups reassemble to rows `A..B` exactly. All 16 of those groups that are skill files equal the current skill file's formatted stream byte for byte.

## Decisions

| Decision | Choice | Rejected alternative and rationale |
| --- | --- | --- |
| Shadow lifetime | One regular file `{key}.jsonl` per conversation, kept with the same inode. Each event rewrites it in place (`O_WRONLY \| O_CREAT \| O_NOFOLLOW \| O_NONBLOCK`; `fstat` must show a regular file owned by this uid with one link; `fchmod 0600`; write, then `ftruncate` to length). When the event ends, `ftruncate(0)` empties it. | **Keep content between events** (as the handoff proposed): this keeps commands and assistant prose on disk between events and reverses the privacy decision in `specs/antigravity-host-support/plan.md`. Truncating instead of unlinking keeps the identity and drops the content. **Unlink and recreate**: this is the defect. **Change `skill-loading.py` to key on path**: that would weaken the Claude Code and Codex compaction/rotation detection, which relies on identity. |
| Unsafe shadow path | A symlink, a non-regular file, another owner, or a hardlinked file at the shadow path raises `BridgeError`. `PreToolUse` then fails closed through the existing fallback. | Silently unlinking and recreating would hide tampering in a directory only this uid can write. |
| Stale state | When a conversation's shadow is first created, sweep the bridge state directory once. Remove regular files owned by this uid that are older than 24 h and named `*.jsonl` or `*.tmp` (the latter left by the previous `os.replace` scheme). Never follow links. Skip a shadow whose conversation run lock is held (`LOCK_NB`), and recheck its age while holding that lock. Sweep failures never fail the event. | **Sweeping lock files**: unlinking a lock that another process holds or waits on lets two events of one conversation run at once. **Sweeping on every event**: this pays a directory scan on every tool call. |
| Chunked-read evidence | Verify each `Partial read` chunk against the canonical formatted stream: `T == len(lines)`, `1 <= A <= B <= T`, `Z == len(stream(A..B))`, `0 <= S < E <= Z`, and body `== stream[S:E]` byte for byte. Record verified byte intervals per `(A, B)` range across the transcript. A line counts once some single verified interval, after merging, contains all of its bytes. | **Per-chunk line parsing with fragment rules** (as the handoff proposed): this needs separate rules for headless leading fragments, cut-off trailing lines and forged `\n12:` rows. Exact byte comparison against the canonical stream rejects all three by construction, and merging intervals handles a line split across two chunks. **Accepting a mismatched length**: the mid-character case would then count bytes that the header misplaces. |

## Shared-Gate Classification

- **Artifact classification**: `gate implementation` (`hooks/agy-bridge.py` adapts the edit, delegation and stop gates for Antigravity) plus `spec/plan` (this directory).
- **Verifiers run before and after**: `python3 hooks/test_agy_bridge.py`, `python3 hooks/test_skill_loading.py`, `bash skills/skill-extraction-workflow/scripts/check-ccl-skills.sh .`, `git diff --check`, `make test`, `npm --prefix packages/ccl-skills-npm test`.

## Risk Inventory and Security Four Questions

| Tag | Applies | Gates |
| --- | --- | --- |
| `shared-gate` | yes: the bridge feeds the edit/delegation checkpoints and the stop notices | RED-baseline tests, mutation walk, `make test`, independent review and adversarial challenge |
| `permission-access` | yes: a forged load would skip a checkpoint, and an unsafe shadow write could touch another file | Negative matrix below |
| `release-ops`, `data-migration`, `money-quota`, `api-contract`, `visible-ui`, `docs-only` | no | No release, schema or UI change |

1. **Caller-controllable inputs**: the Antigravity payload (`conversationId`, `transcriptPath`, `toolCall`), the contents of transcript tool results (file text the agent read), and the contents of the bridge state directory, which only this uid can write.
2. **Blast radius if forged**: a forged load skips one checkpoint attempt. The checkpoint is a delivery-attempt cap, not an authorization boundary, and the isolation and merge guards are unaffected. A shadow write through a planted link could overwrite another file this uid owns. An over-broad sweep could delete another conversation's shadow or locks.
3. **Trust roots**: load evidence is checked against the canonical bundled `SKILL.md` bytes, never against transcript-supplied text. The shadow path's safety comes from `fstat` on the opened descriptor (regular, own uid, one link) inside the `0700` state directory.
4. **Negative cases** (all in the test register): tampered chunk byte, forged line number, missing middle chunk, cut-off last line never re-read, wrong `Z`, wrong `T`, a misplaced start offset with mismatched body length, symlinked shadow path with its target untouched, hardlinked shadow path, a fresh or lock-held shadow surviving the sweep, and a symlink in the state directory not followed by the sweep.

## Test-Case Register (`hooks/test_agy_bridge.py`)

| ID | Scenario | Expected on baseline | Expected on candidate |
| --- | --- | --- | --- |
| T1 | Same conversation, two `edit_file` events on a `.py` target, no skill loaded: first `deny` with the checkpoint reason, second `allow` | fail (second also denied) | pass |
| T2 | Shadow keeps one inode across `PreToolUse` edit, `run_command` and `Stop`. It is `0600` and empty between events. During an event a hook sees structural content without user prompt text | fail (unlinked) | pass |
| T3 | Symlinked or hardlinked shadow path: `PreToolUse` denies, and the link target is unchanged | fail (old scheme replaces the link) | pass |
| T4 | Sweep: a stale `*.jsonl` and `*.tmp` are removed. A fresh shadow, a stale one whose run lock is held, a stale `.lock`/`.turn` file, and a symlink target outside the directory remain | fail (no sweep) | pass |
| T5 | A skill over 46,080 formatted bytes read as three `ByteOffset` chunks, with cuts inside lines and inside a multi-byte character, synthesizes the `Skill` event | fail | pass |
| T6 | A cut-off last line that is re-read by an overlapping chunk counts. Without the re-read, it does not | fail | pass |
| T7 | No `Skill` event when: the middle chunk is missing, a byte is tampered, a line number is forged at equal length, `Z` is wrong, `T` is wrong, or the start offset is misplaced with mismatched body length | pass (nothing counted) | pass |
| T8 | The existing `Showing lines` evidence tests are unchanged | pass | pass |

## Out-of-Repository Deliverable: Antigravity Global Execution Rules

This is machine-local configuration and never enters Git. Verified against the `agy` 1.5.14 binary: global rules are read from `~/.gemini/GEMINI.md`, `~/.gemini/AGENTS.md`, their `~/.gemini/config/` counterparts, and `~/.gemini/config/rules/*.md`. Files in `rules/` need `trigger: always_on` frontmatter. The rule goes in `~/.gemini/config/rules/agy-execution-efficiency.md` (under 3 KB) and covers four practices: parallel `ByteOffset` reads for files over 46,080 bytes, `invoke_subagent` for independent slices, no `manage_task` status polling, and local gates before external review or push. Every tool and parameter name it cites (`read_file.ByteOffset`, `run_command.WaitMsBeforeAsync`, `manage_task` `Action=status`, `invoke_subagent` `TypeName` `research`/`self`) was confirmed in local transcripts. Its load is verified with a live `agy` run.
